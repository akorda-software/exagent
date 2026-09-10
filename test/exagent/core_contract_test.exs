defmodule ExAgent.CoreContractTest do
  use ExUnit.Case, async: true

  alias ExAgent.{Message, Model, RunError, Tool, UsageLimits}
  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Models.Test, as: TestModel

  defmodule Script do
    @behaviour ExAgent.Model
    defstruct [:owner, index: 0, script: [], supports_tools: true]
    @impl true
    def model_name(_), do: "script"
    @impl true
    def system(_), do: "test"

    @impl true
    def profile(model),
      do: %ExAgent.ModelProfile{
        supports_tools: model.supports_tools,
        supports_json_schema_output: false
      }

    @impl true
    def request(model, _messages, _settings, _params) do
      if model.owner, do: send(model.owner, {:request, model.index})

      case Enum.at(model.script, model.index) do
        {:error, reason} -> {:error, reason}
        %Response{} = response -> {:ok, response, %{model | index: model.index + 1}}
      end
    end

    @impl true
    def request_stream(model, messages, settings, params) do
      case request(model, messages, settings, params) do
        {:ok, response, next} ->
          [{:text_delta, Response.text(response)}, {:response, response, next}]

        error ->
          [error]
      end
    end
  end

  defmodule Source do
    @behaviour ExAgent.Model
    defstruct [:owner, events: []]
    def model_name(_), do: "source"
    def system(_), do: "test"
    def request(_, _, _, _), do: {:error, :stream_only}

    def request_stream(model, _, _, _) do
      send(model.owner, {:opened, self()})

      Stream.resource(
        fn -> {model.events, 0} end,
        fn
          {[], n} ->
            {:halt, {[], n}}

          {[event | rest], n} ->
            send(model.owner, {:source_event, n})
            {[event], {rest, n + 1}}
        end,
        fn _ -> send(model.owner, {:closed, self()}) end
      )
    end
  end

  defmodule Output do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:value, :integer)
    end

    def changeset(schema, attrs),
      do:
        schema
        |> Ecto.Changeset.cast(attrs, [:value])
        |> Ecto.Changeset.validate_required([:value])
  end

  defmodule Rewrite do
    use ExAgent.Capability
    defstruct [:name, :args, :id]

    def before_tool_execute(cap, _, call),
      do: %{
        call
        | tool_name: cap.name || call.tool_name,
          args: cap.args || call.args,
          tool_call_id: cap.id || call.tool_call_id
      }
  end

  defmodule AfterFailure do
    use ExAgent.Capability
    defstruct sleep: false
    def after_tool_execute(%{sleep: true}, _, _, _), do: Process.sleep(:infinity)
    def after_tool_execute(_, _, _, _), do: raise("after effect")
  end

  defmodule ModelSpy do
    use ExAgent.Capability
    defstruct [:owner]

    def after_model_request(cap, state) do
      send(cap.owner, {:after_model, List.last(state.messages), state.model.index})
      state
    end
  end

  defmodule FailSecondResponse do
    use ExAgent.Capability
    def after_model_request(_, %{run_step: 2}), do: raise("second response hook")
    def after_model_request(_, state), do: state
  end

  test "sync and stream preserve state, usage and successful effect when the next model fails" do
    for stream? <- [false, true] do
      owner = self()

      effect =
        tool("effect", fn _ ->
          send(owner, :effect)
          {:ok, "recorded"}
        end)

      response = response([call("effect")], 5)
      agent = ExAgent.new(model: %Script{script: [response, {:error, :busy}]}, tools: [effect])

      result =
        if stream?,
          do: agent |> ExAgent.run_stream("go") |> Enum.to_list() |> List.last(),
          else: ExAgent.run(agent, "go")

      assert {:error, %RunError{reason: {:model_request_failed, :busy}, partial: partial}} =
               result

      assert partial.output == nil
      assert partial.status == :failed
      assert partial.model.index == 1
      assert partial.run_step == 2
      assert partial.usage.input_tokens == 5
      assert partial.usage.details == %{cache: %{read: 2}}
      assert [%Part.ToolReturn{status: :succeeded, content: "recorded"}] = returns(partial)
      assert partial.new_messages == partial.messages
      assert is_binary(partial.run_id)
      assert_receive :effect
      refute_receive :effect
    end
  end

  test "one canonical loop advances TestModel through a tool and typed output" do
    agent =
      ExAgent.new(
        model: %TestModel{
          script: [
            {:tool_calls, [call("read")]},
            {:tool_calls, [call("final_result", %{"value" => 7})]}
          ]
        },
        tools: [tool("read", fn _ -> "ok" end)],
        output: Output,
        capabilities: [%ModelSpy{owner: self()}]
      )

    assert {:ok, sync} = ExAgent.run(agent, "go")

    assert {:result, streamed} =
             agent |> ExAgent.run_stream("go") |> Enum.to_list() |> List.last()

    for result <- [sync, streamed] do
      assert result.output == %Output{value: 7}
      assert result.model.index == 2
      assert result.run_step == 2
      assert result.status == :succeeded
      assert Enum.map(returns(result), & &1.status) == [:succeeded, :succeeded]
    end

    assert sync.usage == streamed.usage
    assert_receive {:after_model, %Response{}, 1}
    assert_receive {:after_model, %Response{}, 2}
  end

  test "fatal first batch member cannot erase a later completed effect or contributed usage" do
    owner = self()
    failed = tool("failed", fn _ -> {:error, :known_failure} end)

    effect =
      tool("effect", fn _ ->
        send(owner, :completed)
        {:ok, "ok", %Usage{input_tokens: 9, output_tokens: 3}}
      end)

    agent =
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("failed"), call("effect")]}]},
        tools: [failed, effect]
      )

    assert {:error, %RunError{partial: partial}} = ExAgent.run(agent, "go")
    assert_receive :completed
    assert Enum.map(returns(partial), & &1.status) == [:failed, :succeeded]
    assert partial.usage.input_tokens == 10
    assert partial.model.index == 1
  end

  test "progress captures a completed effect while a sibling is still running" do
    owner = self()

    slow =
      tool("slow", fn _ ->
        send(owner, {:slow, self()})

        receive do
          :finish -> "slow done"
        end
      end)

    fast = tool("fast", fn _ -> "fast done" end)

    agent =
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("slow"), call("fast")]}, "done"]},
        tools: [slow, fast]
      )

    task =
      Task.async(fn -> ExAgent.run(agent, "go", on_progress: &send(owner, {:progress, &1})) end)

    assert_receive {:slow, slow_pid}
    assert_receive {:progress, _}
    partial = await_completed_progress("fast")

    assert [%Part.ToolReturn{status: :unknown}, %Part.ToolReturn{status: :succeeded}] =
             returns(partial)

    send(slow_pid, :finish)
    assert {:ok, _} = Task.await(task)
  end

  test "after-hook exception and timeout retain the successful effect and usage without replay" do
    for sleep? <- [false, true] do
      effect =
        tool("effect", fn _ -> {:ok, "saved", %Usage{input_tokens: 3, output_tokens: 4}} end)

      agent =
        ExAgent.new(
          model: %TestModel{script: [{:tool_calls, [call("effect")]}, "must not run"]},
          tools: [effect],
          tool_timeout: 100,
          capabilities: [%AfterFailure{sleep: sleep?}]
        )

      assert {:error, %RunError{partial: partial}} = ExAgent.run(agent, "go")
      assert [%Part.ToolReturn{status: :succeeded, content: "saved"}] = returns(partial)
      assert partial.usage.input_tokens == 4
      assert partial.model.index == 1
    end
  end

  test "tool schema is prepared before model invocation and invalid args have no effect" do
    invalid = %{
      tool("effect", fn _ -> flunk("must not execute") end)
      | parameters_json_schema: %{"type" => "nonsense"}
    }

    agent = ExAgent.new(model: %Script{owner: self()}, tools: [invalid])

    assert {:error, %RunError{reason: {:invalid_tool_schema, _}, partial: %{run_step: 0}}} =
             ExAgent.run(agent, "go")

    refute_receive {:request, _}

    valid = %{
      invalid
      | parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"n" => %{"type" => "integer"}},
          "required" => ["n"]
        }
    }

    model = %TestModel{script: [{:tool_calls, [call("effect", %{"n" => "bad"})]}, "corrected"]}
    assert {:ok, result} = ExAgent.run(ExAgent.new(model: model, tools: [valid]), "go")
    assert [%Part.ToolReturn{status: :validation_error}] = returns(result)
  end

  test "explicitly unsupported tools reject both functions and tool output but allow sync text" do
    model = %Script{
      owner: self(),
      supports_tools: false,
      script: [response([%Part.Text{content: "text"}])]
    }

    assert {:ok, %{output: "text"}} = ExAgent.run(ExAgent.new(model: model), "go")
    assert_receive {:request, 0}

    for options <- [[tools: [tool("read", fn _ -> "ok" end)]], [output: Output]] do
      agent = ExAgent.new([model: model] ++ options)
      assert {:error, %RunError{reason: {:unsupported, :tools}}} = ExAgent.run(agent, "go")
      refute_receive {:request, _}
    end

    output_model = %Script{
      supports_tools: true,
      script: [response([call("final_result", %{"value" => 1})])]
    }

    assert {:ok, %{output: %Output{value: 1}}} =
             ExAgent.run(ExAgent.new(model: output_model, output: Output), "go")
  end

  test "hooks cannot evade effective tool permissions, argument validation or identity" do
    protected = %{
      tool("protected", fn _ -> flunk("must not execute") end)
      | parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"n" => %{"type" => "integer"}}
        }
    }

    original = tool("original", fn _ -> flunk("wrong tool executed") end)
    model = %TestModel{script: [{:tool_calls, [call("original", %{}, "fixed")]}, "done"]}
    perms = ExAgent.Permissions.new!(rules: [{"protected", :deny}])
    base = ExAgent.new(model: model, tools: [original, protected])

    assert {:ok, denied} =
             ExAgent.run(
               %{base | capabilities: [%Rewrite{name: "protected", args: %{"n" => 1}}]},
               "go",
               permissions: perms
             )

    assert [%Part.ToolReturn{tool_name: "protected", tool_call_id: "fixed", status: :denied}] =
             returns(denied)

    assert {:ok, invalid} =
             ExAgent.run(
               %{base | capabilities: [%Rewrite{name: "protected", args: %{"n" => "bad"}}]},
               "go"
             )

    assert [%Part.ToolReturn{status: :validation_error}] = returns(invalid)

    assert {:error, %RunError{reason: :tool_call_identity_changed, partial: partial}} =
             ExAgent.run(%{base | capabilities: [%Rewrite{id: "changed"}]}, "go")

    assert [%Part.ToolReturn{status: :not_executed, tool_call_id: "fixed"}] = returns(partial)
  end

  test "missing call IDs are unique and duplicate provider IDs execute nothing" do
    safe = tool("safe", fn _ -> "ok" end)
    model = %TestModel{script: [{:tool_calls, [call("safe"), call("safe")]}, "done"]}
    assert {:ok, result} = ExAgent.run(ExAgent.new(model: model, tools: [safe]), "go")
    ids = Enum.map(returns(result), & &1.tool_call_id)
    assert length(Enum.uniq(ids)) == 2
    assert Enum.all?(ids, &is_binary/1)

    unsafe = tool("safe", fn _ -> flunk("duplicate call executed") end)

    duplicate = %TestModel{
      script: [{:tool_calls, [call("safe", %{}, "dup"), call("safe", %{}, "dup")]}]
    }

    assert {:error, %RunError{reason: :duplicate_tool_call_id, partial: partial}} =
             ExAgent.run(ExAgent.new(model: duplicate, tools: [unsafe]), "go")

    assert partial.pending_response != nil
    assert returns(partial) == []
  end

  test "batch limits and exhausted structured validation leave paired history" do
    safe = tool("safe", fn _ -> flunk("limit must prevent effect") end)
    model = %TestModel{script: [{:tool_calls, [call("safe"), call("safe")]}]}

    agent =
      ExAgent.new(model: model, tools: [safe], usage_limits: %UsageLimits{tool_calls_limit: 1})

    assert {:error, %RunError{partial: partial}} = ExAgent.run(agent, "go")
    assert Enum.map(returns(partial), & &1.status) == [:not_executed, :not_executed]
    assert_paired(partial)

    output_model = %TestModel{
      script: [{:tool_calls, [call("final_result", %{}, "out"), call("safe", %{}, "sibling")]}]
    }

    agent = ExAgent.new(model: output_model, tools: [safe], output: Output, output_retries: 0)
    assert {:error, %RunError{partial: partial}} = ExAgent.run(agent, "go")
    assert_paired(partial)
  end

  test "truncated responses never execute their tool calls" do
    model = %TestModel{script: [%{response([call("effect")]) | finish_reason: :length}]}

    agent =
      ExAgent.new(model: model, tools: [tool("effect", fn _ -> flunk("truncated effect") end)])

    assert {:error, %RunError{reason: {:max_tokens_exceeded, _}, partial: partial}} =
             ExAgent.run(agent, "go")

    assert [%Part.ToolReturn{status: :not_executed}] = returns(partial)
  end

  test "a reused provider call ID in a later request still gets its own failure resolution" do
    model = %TestModel{
      script: [
        {:tool_calls, [call("effect", %{}, "same")]},
        {:tool_calls, [call("effect", %{}, "same")]}
      ]
    }

    agent =
      ExAgent.new(
        model: model,
        tools: [tool("effect", fn _ -> "done" end)],
        capabilities: [FailSecondResponse]
      )

    assert {:error, %RunError{partial: partial}} = ExAgent.run(agent, "go")
    assert Enum.map(returns(partial), & &1.status) == [:succeeded, :not_executed]
    assert partial.model.index == 2
    assert_paired(partial)
  end

  test "result serialization failure stops the loop as unknown without losing usage" do
    agent =
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("effect")]}]},
        tools: [
          tool("effect", fn _ -> {:ok, self(), %Usage{input_tokens: 3, output_tokens: 2}} end)
        ]
      )

    assert {:error, %RunError{reason: {:invalid_tool_result, _, _}, partial: partial}} =
             ExAgent.run(agent, "go")

    assert [%Part.ToolReturn{status: :unknown}] = returns(partial)
    assert partial.usage.input_tokens == 4
  end

  test "context carries actual run identity, step and retry counters" do
    owner = self()

    effect =
      tool(
        "effect",
        fn ctx, _ ->
          send(owner, {:ctx, ctx})
          "ok"
        end,
        true
      )

    agent =
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("effect")]}, "done"]},
        tools: [effect]
      )

    assert {:ok, result} = ExAgent.run(agent, "go")
    assert_receive {:ctx, ctx}
    assert ctx.run_id == result.run_id
    assert ctx.run_step == 1
    assert ctx.retries == %{}
    assert is_binary(ctx.tool_call_id)
  end

  test "execution exceptions never ask the model to replay an uncertain effect" do
    owner = self()

    effect =
      tool("effect", fn _ ->
        send(owner, :attempt)
        raise "uncertain"
      end)

    agent =
      ExAgent.new(
        model: %TestModel{
          script: [{:tool_calls, [call("effect")]}, {:tool_calls, [call("effect")]}]
        },
        tools: [effect]
      )

    assert {:error, %RunError{partial: partial}} = ExAgent.run(agent, "go")
    assert_receive :attempt
    refute_receive :attempt
    assert partial.model.index == 1
    assert [%Part.ToolReturn{status: :unknown}] = returns(partial)
  end

  test "run! retains its exception type and exposes the partial run error" do
    agent = ExAgent.new(model: %Script{script: [{:error, :busy}]})
    exception = assert_raise ExAgent.UnexpectedModelBehavior, fn -> ExAgent.run!(agent, "go") end

    assert %RunError{reason: {:model_request_failed, :busy}, partial: %{status: :failed}} =
             exception.error
  end

  test "delegated failure usage is retained without copying its live model to history" do
    child_error = %RunError{
      reason: :child_failed,
      partial: %{
        usage: %Usage{input_tokens: 4, output_tokens: 2},
        model: %{private: "never-export-this"}
      }
    }

    effect = tool("delegate", fn _ -> {:error, child_error} end)

    agent =
      ExAgent.new(model: %TestModel{script: [{:tool_calls, [call("delegate")]}]}, tools: [effect])

    assert {:error, %RunError{partial: partial}} = ExAgent.run(agent, "go")
    assert partial.usage.input_tokens == 5
    refute Message.to_json(partial.messages) =~ "never-export-this"
  end

  test "Model dispatcher and public stream are lazy and release on halt" do
    source = %Source{owner: self(), events: [{:text_delta, "one"}, {:text_delta, "two"}]}
    model_stream = Model.request_stream(source, [], nil, %ExAgent.ModelRequestParameters{})
    public_stream = ExAgent.run_stream(ExAgent.new(model: source), "go")
    refute_receive {:opened, _}
    assert [{:text_delta, "one"}] = Enum.take(model_stream, 1)
    assert_receive {:closed, _}
    assert [{:delta, "one"}] = Enum.take(public_stream, 1)
    assert_receive {:closed, _}
    refute_receive {:source_event, 1}
  end

  test "suspended public enumeration makes no further progress until demand" do
    source = %Source{owner: self(), events: [{:text_delta, "one"}, {:text_delta, "two"}]}
    stream = ExAgent.run_stream(ExAgent.new(model: source), "go")

    assert {:suspended, {:delta, "one"}, continuation} =
             Enumerable.reduce(stream, {:cont, nil}, fn event, _ -> {:suspend, event} end)

    assert_receive {:source_event, 0}
    refute_receive {:source_event, 1}
    assert {:halted, nil} = continuation.({:halt, nil})
    assert_receive {:closed, _}
  end

  test "consumer death cancels the owned worker and cleans its adapter resource" do
    owner = self()
    source = %Source{owner: owner, events: [{:text_delta, "one"}, {:text_delta, "two"}]}

    consumer =
      spawn(fn ->
        ExAgent.run_stream(ExAgent.new(model: source), "go")
        |> Enum.each(fn _ ->
          send(owner, :consuming)

          receive do
            :never -> :ok
          end
        end)
      end)

    assert_receive {:opened, worker}
    monitor = Process.monitor(worker)
    assert_receive :consuming
    Process.exit(consumer, :kill)
    assert_receive {:closed, ^worker}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
  end

  test "stream error is one terminal and retains provisional text and cumulative usage" do
    source = %Source{
      owner: self(),
      events: [
        {:usage, %Usage{input_tokens: 2, output_tokens: 1}},
        {:usage, %Usage{input_tokens: 2, output_tokens: 3}},
        {:text_delta, "partial"},
        {:error, :lost}
      ]
    }

    events = ExAgent.new(model: source) |> ExAgent.run_stream("go") |> Enum.to_list()
    assert [{:delta, "partial"}, {:error, %RunError{partial: partial}}] = events
    assert partial.usage.input_tokens == 2
    assert partial.usage.output_tokens == 3
    assert Response.text(partial.pending_response) == "partial"
    refute Enum.any?(partial.messages, &match?(%Response{}, &1))
    assert partial.usage_status == :partial
  end

  test "terminal response reconciles cumulative usage once and supplies final model" do
    final_model = %TestModel{index: 17}
    final = response([%Part.Text{content: "final"}], 5)

    source = %Source{
      owner: self(),
      events: [
        {:usage, %Usage{input_tokens: 2, output_tokens: 1}},
        {:response, final, final_model}
      ]
    }

    assert [{:result, result}] =
             ExAgent.new(model: source) |> ExAgent.run_stream("go") |> Enum.to_list()

    assert result.usage.input_tokens == 5
    assert result.model == final_model
    assert result.output == "final"
    assert result.pending_response == nil
  end

  test "EOF without terminal and legacy two-tuple response are explicit errors" do
    for events <- [[], [{:response, response([])}]] do
      source = %Source{owner: self(), events: events}

      assert [{:error, %RunError{reason: {:model_request_failed, _}}}] =
               ExAgent.new(model: source) |> ExAgent.run_stream("go") |> Enum.to_list()
    end
  end

  test "thinking deltas remain separate from text callbacks and preserve the terminal response" do
    owner = self()

    final =
      response([
        %Part.Thinking{content: "thought", signature: "sig"},
        %Part.Text{content: "answer"}
      ])

    source = %Source{
      owner: owner,
      events: [
        {:thinking_delta, "thought"},
        {:text_delta, "answer"},
        {:response, final, %TestModel{index: 2}}
      ]
    }

    agent = ExAgent.new(model: source)

    assert [{:delta, "answer"}, {:result, result}] =
             ExAgent.run_stream(agent, "go", deps: %{on_text_delta: &send(owner, {:text, &1})})
             |> Enum.to_list()

    assert result.output == "answer"
    assert List.last(result.messages) == final
    assert_receive {:text, "answer"}
    refute_receive {:text, "thought"}
  end

  test "tool statuses survive JSON round trips; invalid statuses reject" do
    for status <- [:succeeded, :validation_error, :denied, :failed, :unknown, :not_executed] do
      part = %Part.ToolReturn{
        tool_name: "x",
        tool_call_id: "id",
        content: "result",
        status: status
      }

      assert {:ok, [%Message.Request{parts: [^part]}]} =
               [Message.new_request([part])] |> Message.to_json() |> Message.from_json()
    end

    assert {:error, {:invalid_message, _}} =
             Message.from_json(
               ~s([{"__type__":"request","parts":[{"__type__":"tool_return","status":"bogus"}]}])
             )
  end

  defp tool(name, fun, ctx? \\ false),
    do:
      Tool.new(
        name: name,
        takes_ctx: ctx?,
        parameters_json_schema: %{"type" => "object"},
        call: fun
      )

  defp call(name, args \\ %{}, id \\ nil),
    do: %Part.ToolCall{tool_name: name, args: args, tool_call_id: id}

  defp response(parts, input \\ 1),
    do: %Response{
      parts: parts,
      usage: %Usage{input_tokens: input, output_tokens: 1, details: %{cache: %{read: 2}}}
    }

  defp returns(result),
    do: Enum.filter(Message.parts(result.messages), &match?(%Part.ToolReturn{}, &1))

  defp assert_paired(result) do
    parts = Message.parts(result.messages)
    calls = for %Part.ToolCall{tool_call_id: id} <- parts, do: id

    resolved =
      for p <- parts,
          match?(%Part.ToolReturn{}, p) or match?(%Part.Retry{}, p),
          do: p.tool_call_id

    assert Enum.sort(calls) == Enum.sort(resolved)
  end

  defp await_completed_progress(name) do
    receive do
      {:progress, partial} ->
        if Enum.any?(returns(partial), &(&1.tool_name == name and &1.status == :succeeded)),
          do: partial,
          else: await_completed_progress(name)
    after
      1_000 -> flunk("completed tool progress not observed")
    end
  end
end
