defmodule ExAgent.ServerRunOptionsTest do
  use ExUnit.Case, async: true

  alias ExAgent.{Event, Message, Models.Test, Permissions, PubSub, Server, Tool}
  alias ExAgent.Message.Part

  for {action, approval, executed?} <- [
        {:deny, nil, false},
        {:ask, nil, false},
        {:ask, :deny, false},
        {:ask, :approve, true}
      ] do
    test "chat forwards permissions #{action} and approval #{inspect(approval)}" do
      parent = self()
      server = start_supervised!({Server, agent: tool_agent(parent)})
      approve = approval_callback(parent, unquote(approval))

      assert {:ok, result} =
               Server.chat(server, "go",
                 permissions: Permissions.new!(default: unquote(action)),
                 approve: approve
               )

      returns =
        for %Message.Request{parts: parts} <- result.messages,
            %Part.ToolReturn{} = part <- parts,
            do: part.content

      if unquote(executed?) do
        assert "executed" in returns
        assert_receive :executed
      else
        assert Enum.any?(returns, &String.contains?(&1, "not permitted"))
        refute_received :executed
      end

      if unquote(approval != nil), do: assert_receive({:approval, "write"})
    end
  end

  test "cost estimator reaches the budget guard" do
    parent = self()

    # Estimates describe observed request usage, not a prediction on empty usage.
    # The first response spends the budget; no subsequent tool/request may run.
    agent = %{tool_agent(parent) | usage_limits: %ExAgent.UsageLimits{max_budget_cents: 1}}

    server = start_supervised!({Server, agent: agent})

    assert {:error, %ExAgent.RunError{reason: {:usage_limit_exceeded, :budget_cents, 2}}} =
             Server.chat(server, "go",
               estimate_cost: fn usage ->
                 send(parent, {:estimated, usage})
                 2
               end
             )

    assert_receive {:estimated, %Message.Usage{input_tokens: 1, output_tokens: 1}}
    refute_received :executed
  end

  test "queued send_message and steer retain per-run options" do
    parent = self()

    blocking = %Test{
      script: [
        fn ->
          send(parent, {:blocked, self()})

          receive do
            :go -> "done"
          end
        end
      ]
    }

    server = start_supervised!({Server, agent: tool_agent(parent, blocking), pubsub: :local})

    :ok =
      PubSub.subscribe(
        {ExAgent.PubSub.Local, []},
        Event.agent_topic(:sys.get_state(server).agent_id)
      )

    assert {:ok, _} = Server.send_message(server, "block")
    assert_receive {:blocked, worker}, 1000
    deny = Permissions.new!(default: :deny)
    assert {:ok, queued} = Server.send_message(server, "queued", permissions: deny)
    assert {:ok, steered} = Server.steer(server, "steered", permissions: deny)
    send(worker, :go)
    assert_receive {:exagent_event, %Event{type: :run_finished, request_id: ^steered}}, 1000
    assert_receive {:exagent_event, %Event{type: :run_finished, request_id: ^queued}}, 1000
    refute_received :executed

    returns =
      for %Message.Request{parts: parts} <- Server.history(server),
          %Part.ToolReturn{} = part <- parts,
          do: part.content

    assert length(returns) == 2
    assert Enum.all?(returns, &String.contains?(&1, "not permitted"))
  end

  test "an expired negative absolute deadline is forwarded before any model request" do
    parent = self()

    model = %Test{
      script: [
        fn ->
          send(parent, :unexpected_model_request)
          "too late"
        end
      ]
    }

    server = start_supervised!({Server, agent: ExAgent.new(model: model)})
    deadline = min(-1, System.monotonic_time(:millisecond) - 1)

    assert {:error, %ExAgent.RunError{reason: :deadline_exceeded}} =
             Server.chat(server, "go", deadline: deadline)

    refute_received :unexpected_model_request
  end

  test "max_concurrent_requests reaches the scope validation boundary" do
    parent = self()

    model = %Test{
      script: [
        fn ->
          send(parent, :unexpected_model_request)
          "unbounded"
        end
      ]
    }

    server = start_supervised!({Server, agent: ExAgent.new(model: model)})

    assert {:error, %ExAgent.RunError{reason: :invalid_execution_scope_options}} =
             Server.chat(server, "go", max_concurrent_requests: 0)

    refute_received :unexpected_model_request
  end

  test "model-aware arity-two pricing survives the Server boundary" do
    parent = self()
    server = start_supervised!({Server, agent: ExAgent.new(model: %Test{label: "priced"})})

    estimator = fn identity, usage ->
      send(parent, {:model_priced, identity, usage})
      if (usage.input_tokens || 0) + (usage.output_tokens || 0) == 0, do: 0, else: 2
    end

    assert {:ok, result} =
             Server.chat(server, "go",
               estimate_cost: estimator,
               deadline: System.monotonic_time(:millisecond) + 30_000,
               max_concurrent_requests: 1
             )

    assert_receive {:model_priced, _identity, %Message.Usage{}}
    assert result.cost_cents == 2
    assert result.cost_status == :known
  end

  test "explicit history stays supported and internal event/run options cannot be replaced" do
    parent = self()
    agent = ExAgent.new(model: %Test{label: "ok"}, instructions: "system")
    server = start_supervised!({Server, agent: agent, pubsub: :local})

    :ok =
      PubSub.subscribe(
        {ExAgent.PubSub.Local, []},
        Event.agent_topic(:sys.get_state(server).agent_id)
      )

    opts = [
      run_id: "injected",
      root_run_id: "injected-root",
      parent_run_id: "injected-parent",
      model_request_id: "injected-request",
      execution_scope: self(),
      parent_context: %{execution_scope: self()},
      on_progress: fn _ -> send(parent, :injected_progress) end,
      on_event: fn e -> send(parent, {:injected, e}) end,
      prepend_instructions: false
    ]

    assert {:ok, first} = Server.chat(server, "first", opts)
    assert %Message.Request{parts: [%Part.System{}, %Part.User{}]} = hd(first.messages)
    assert_receive {:exagent_event, %Event{type: :run_started, run_id: id}}
    refute id == "injected"
    assert first.root_run_id == first.run_id
    assert first.parent_run_id == nil
    refute first.model_request_id == "injected-request"
    refute_received :injected_progress
    refute_received {:injected, _}
    history = [Message.new_request([%Part.User{content: "shared"}])]
    assert {:ok, result} = Server.chat(server, "next", message_history: history)
    assert Enum.take(result.messages, 1) == history
    assert length(result.messages) == 3
    assert {:ok, fresh} = Server.chat(server, "fresh", message_history: [])
    assert length(fresh.messages) == 2
    assert %Message.Request{parts: [%Part.System{}, %Part.User{}]} = hd(fresh.messages)
  end

  defp approval_callback(_parent, nil), do: nil

  defp approval_callback(parent, approval) do
    fn call ->
      send(parent, {:approval, call.tool_name})
      approval
    end
  end

  defp tool_agent(parent, initial_model \\ nil) do
    tool =
      Tool.new(
        name: "write",
        takes_ctx: false,
        call: fn _ ->
          send(parent, :executed)
          {:ok, "executed"}
        end
      )

    call = {:tool_calls, [%Part.ToolCall{tool_name: "write", args: %{}}]}
    script = if(initial_model, do: initial_model.script, else: []) ++ [call, "done", call, "done"]
    ExAgent.new(model: %Test{script: script}, tools: [tool])
  end
end
