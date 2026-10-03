defmodule ExAgent.SequenceIntentDispatchTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, RunError, Store, Tool}
  alias ExAgent.Coordination.Composition
  alias ExAgent.Message.Part

  defmodule Model do
    @behaviour ExAgent.Model
    defstruct [:owner, script: [], index: 0]
    def system(_), do: "test"
    def model_name(_), do: "test"
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}
    def validate_resume(_, _, _, _), do: :ok

    def request(model, messages, settings, params) do
      send(model.owner, {:dispatch, :buffered, settings.timeout})
      response(model, messages, settings, params)
    end

    def request_stream(model, messages, settings, params) do
      send(model.owner, {:dispatch, :stream, settings.timeout})
      {:ok, result, next} = response(model, messages, settings, params)
      [{:response, result, next}]
    end

    defp response(model, messages, settings, params) do
      {:ok, result, next} =
        ExAgent.Models.Test.request(
          %ExAgent.Models.Test{script: model.script, index: model.index},
          messages,
          settings,
          params
        )

      {:ok, result, %{model | index: next.index}}
    end
  end

  defmodule Journal do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, query), do: Store.ETS.scan_records(c.table, ns, query)

    def transition(c, key, revision, command) do
      result = Store.ETS.transition(c.table, key, revision, command)

      kind =
        get_in(command, ["payload", "intent", "kind"]) ||
          if command["operation"] == "begin_effect" do
            if command["payload"]["call_id"], do: "tool", else: "model"
          end

      boundary = {command["operation"], kind}

      action =
        Agent.get_and_update(c.control, fn
          {^boundary, action} -> {action, nil}
          other -> {nil, other}
        end)

      if action == :hold do
        send(c.owner, {:intent_committed, self()})

        receive do
          :release_ack -> :ok
        end
      end

      if action == :lose, do: {:error, :lost_input_ack}, else: result
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    control = start_supervised!({Agent, fn -> nil end})
    owner = self()

    store =
      Store.scoped({Journal, %{table: __MODULE__, owner: owner, control: control}}, "intent")

    codec = %{
      dump: fn m -> {:ok, %{"index" => m.index}} end,
      load: fn m, data -> {:ok, %{m | index: data["index"]}} end
    }

    config = %{
      store: store,
      id: "run",
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000,
      policy: %{"id" => "policy", "version" => "1"},
      on_writer: fn pid ->
        send(owner, {:attempt, pid})
        :ok
      end
    }

    %{store: store, control: control, owner: owner, codec: codec, config: config}
  end

  defp definition(c, kind) do
    tool = %Tool{
      name: "effect",
      description: "Observed local effect",
      parameters_json_schema: %{"type" => "object", "properties" => %{}},
      call: fn _, _ ->
        send(c.owner, :tool_dispatched)
        "done"
      end
    }

    script =
      if kind == "tool",
        do: [
          {:tool_calls, [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}]},
          "done"
        ],
        else: ["done"]

    agent = ExAgent.new(model: %Model{owner: c.owner, script: script}, tools: [tool])

    steps =
      for id <- ~w(A B) do
        %{
          id: id,
          agent: agent,
          definition: %{id: "leaf", version: "1"},
          policy: %{id: "policy", version: "1"},
          model_ref: %{id: "model", version: "1"},
          output_ref: %{id: "output", version: "1"},
          model_codec: c.codec
        }
      end

    {:ok, definition} = Composition.new(id: "intent", version: "1", steps: steps)
    {definition, agent}
  end

  defp reference(r),
    do: %{
      version: 1,
      id: "run",
      record_id: r["record_id"],
      revision: r["revision"],
      run_id: r["execution"]["run_id"]
    }

  defp wait_until(deadline) do
    receive do
    after
      max(deadline - System.monotonic_time(:millisecond) + 1, 0) -> :ok
    end
  end

  defp ready(c, definition) do
    Agent.update(c.control, fn _ -> {{"step_input", nil}, :lose} end)

    assert {:error, %RunError{}} =
             Composition.run(definition, "input", continuation: %{c.config | lease_ms: 350})

    assert_receive {:attempt, writer}
    refute Process.alive?(writer)
    {:ok, r} = Store.load_record(c.store, :agent, "run")

    receive do
    after
      max(r["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0) -> :ok
    end

    assert {:ok, %{record: r}} =
             Continuation.recover(c.store, "run",
               record_id: r["record_id"],
               revision: r["revision"],
               operation_id: "recover",
               actor: "host",
               authorize: fn a, _, _ -> {:ok, a} end
             )

    assert r["execution"]["state"] == "ready"
    r
  end

  defp launch(c, mode, kind, config) do
    {definition, agent} = definition(c, kind)
    r = if mode == :resume, do: ready(c, definition)
    Agent.update(c.control, fn _ -> {{"begin_effect", kind}, :hold} end)

    Task.async(fn ->
      case mode do
        :resume ->
          Composition.resume(definition, reference(r), continuation: config)

        :run ->
          Composition.run(definition, "input", continuation: config)

        :stream ->
          config =
            Map.merge(config, %{
              definition: %{"id" => "leaf", "version" => "1"},
              model_ref: %{"id" => "model", "version" => "1"},
              model_codec: c.codec
            })

          ExAgent.run(agent, "input", continuation: config, stream_text: true)
      end
    end)
  end

  for mode <- [:run, :resume, :stream], bound <- [:budget, :lease] do
    test "#{mode} Model ACK after #{bound} expiry preserves intent without dispatch", c do
      config =
        if unquote(bound) == :budget,
          do: Map.put(c.config, :active_time_limit_ms, 600),
          else: %{c.config | lease_ms: 600}

      task = launch(c, unquote(mode), "model", config)
      assert_receive {:attempt, writer}, 2000
      assert_receive {:intent_committed, ^writer}, 2000
      {:ok, committed} = Store.load_record(c.store, :agent, "run")
      assert map_size(committed["execution"]["effects"]) == 1
      refute_receive {:dispatch, _, _}, 0
      wait_until(System.monotonic_time(:millisecond) + 601)
      send(writer, :release_ack)
      assert {:error, %RunError{}} = Task.await(task, 5000)
      refute_receive {:dispatch, _, _}, 0
      {:ok, final} = Store.load_record(c.store, :agent, "run")
      assert final == committed
      refute Process.alive?(writer)
    end
  end

  for mode <- [:run, :resume, :stream], bound <- [:budget, :lease] do
    test "#{mode} tool intent ACK after #{bound} expiry cannot enter callable", c do
      config =
        if unquote(bound) == :budget,
          do: Map.put(c.config, :active_time_limit_ms, 600),
          else: %{c.config | lease_ms: 600}

      task = launch(c, unquote(mode), "tool", config)
      assert_receive {:attempt, writer}, 2000
      assert_receive {:dispatch, _, _}, 2000
      assert_receive {:intent_committed, ^writer}, 2000
      {:ok, committed} = Store.load_record(c.store, :agent, "run")
      wait_until(System.monotonic_time(:millisecond) + 601)
      send(writer, :release_ack)
      assert {:error, %RunError{}} = Task.await(task, 5000)
      refute_receive :tool_dispatched, 0
      {:ok, final} = Store.load_record(c.store, :agent, "run")
      assert final["execution"]["effects"] == committed["execution"]["effects"]
      refute Process.alive?(writer)
    end
  end

  for mode <- [:run, :resume, :stream] do
    test "#{mode} tool intent ACK before expiry reaches the callable", c do
      task = launch(c, unquote(mode), "tool", c.config)
      assert_receive {:attempt, writer}, 2000
      assert_receive {:dispatch, _, _}, 2000
      assert_receive {:intent_committed, ^writer}, 2000
      refute_receive :tool_dispatched, 0
      send(writer, :release_ack)
      assert_receive :tool_dispatched, 2000
      assert {:ok, _} = Task.await(task, 5000)
      refute Process.alive?(writer)
    end
  end

  for mode <- [:resume, :stream] do
    test "#{mode} ACK before deadline dispatches with remaining original timeout", c do
      config = Map.put(c.config, :active_time_limit_ms, 4000)
      task = launch(c, unquote(mode), "model", config)
      assert_receive {:attempt, writer}, 2000
      assert_receive {:intent_committed, ^writer}, 2000
      observed = System.monotonic_time(:millisecond)
      deadline = observed + 4000
      wait_until(observed + 200)
      released = System.monotonic_time(:millisecond)
      assert released < deadline
      send(writer, :release_ack)
      assert_receive {:dispatch, _, timeout}, 2000
      assert timeout > 0
      # The dispatch sample is after this causal release; no entry-time tolerance.
      assert timeout <= deadline - released
      assert {:ok, _} = Task.await(task, 5000)
      refute Process.alive?(writer)
    end
  end
end
