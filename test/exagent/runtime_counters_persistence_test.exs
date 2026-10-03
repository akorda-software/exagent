defmodule ExAgent.RuntimeCountersPersistenceTest do
  use ExUnit.Case, async: false
  alias ExAgent.{ExecutionScope, Store, Tool}
  alias ExAgent.Continuation.{Record, Writer}
  alias ExAgent.Coordination.Composition
  alias ExAgent.Message.Part

  defmodule Change do
    use ExAgent.Capability
    def before_model_request(_, s), do: change(:before, s)
    def after_model_request(_, s), do: change(:after, s)

    defp change(hook, s) do
      if s.deps.hook == hook, do: s.deps.change.(s), else: s
    end
  end

  defmodule Observe do
    use ExAgent.Capability
    defstruct []
    def before_model_request(_, s), do: observe(s)
    def after_model_request(_, s), do: observe(s)

    defp observe(s) do
      send(s.deps.owner, {:observed, s.run_step, s.tool_calls})
      s
    end
  end

  defmodule Tap do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, k), do: Store.ETS.load_record(c.table, k)
    def scan_records(c, n, q), do: Store.ETS.scan_records(c.table, n, q)

    def transition(c, k, r, command) do
      result = Store.ETS.transition(c.table, k, r, command)

      case result do
        {:ok, %{record: record}} -> send(c.owner, {:stored, k, command, record})
        _ -> :ok
      end

      result
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    store = Store.scoped({Tap, %{table: __MODULE__, owner: self()}}, "counters")
    %{store: store}
  end

  defp codec do
    %{
      dump: fn m -> {:ok, %{"index" => m.index}} end,
      load: fn m, d -> {:ok, %{m | index: d["index"]}} end
    }
  end

  defp refs do
    %{
      definition: %{"id" => "leaf", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      model_ref: %{"id" => "model", "version" => "1"},
      output_ref: %{"id" => "output", "version" => "1"}
    }
  end

  defp execute(:direct, agent, store, opts) do
    config =
      Map.merge(refs(), %{
        store: store,
        id: "run",
        durability: :ephemeral,
        expires_at: nil,
        lease_ms: 60_000,
        model_codec: codec()
      })

    ExAgent.run(agent, "input", Keyword.put(opts, :continuation, config))
  end

  defp execute(:composition, agent, store, opts) do
    step = Map.merge(refs(), %{id: "A", agent: agent, model_codec: codec()})
    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [step])
    {:ok, scope} = ExecutionScope.start_structural("root", [])

    config = %{
      kind: :composition,
      composition: definition,
      store: store,
      id: "run",
      definition: %{"id" => "sequence", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000
    }

    {:ok, writer, _} =
      Writer.open(%{run_id: "root", execution_scope: scope, input: "input"}, config)

    try do
      ExAgent.run_composition_step(writer, definition, "A", opts)
    after
      Writer.stop(writer)
      ExecutionScope.stop(scope)
    end
  end

  defp leaf(record, :direct), do: {record["execution"]["progress"]["runtime"], record["snapshot"]}

  defp leaf(record, :composition) do
    case Map.values(record["execution"]["progress"]["runtime"]["children"] || %{}) do
      [child] -> {child["frame"], child["snapshot"]}
      [] -> {nil, nil}
    end
  end

  defp stored(acc \\ []) do
    receive do
      {:stored, key, command, record} -> stored([{key, command, record} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp assert_refs(:direct, record) do
    assert record["execution"]["model_ref"] == refs().model_ref
  end

  defp assert_refs(:composition, record) do
    runtime = record["execution"]["progress"]["runtime"]
    assert runtime["authority"] != nil
    [child] = Map.values(runtime["children"])
    assert child["model_ref"] == refs().model_ref
  end

  defp counts(%{"scope_version" => 1} = scope, _id), do: scope
  defp counts(%{"scope_version" => 2} = scope, id), do: scope["nodes"][id]

  for hook <- [:before, :after], kind <- [:direct, :composition] do
    test "#{kind} #{hook}: real intents, captures and snapshots retain runtime counters", %{
      store: store
    } do
      owner = self()
      kind = unquote(kind)

      tool =
        Tool.new(
          name: "effect",
          max_retries: 1,
          parameters_json_schema: %{
            "type" => "object",
            "properties" => %{"retry" => %{"type" => "boolean"}}
          },
          call: fn _, args ->
            send(owner, :effect)
            if args["retry"], do: {:retry, "again"}, else: {:ok, "done"}
          end
        )

      script =
        for {id, retry?} <- [{"a", true}, {"b", false}] do
          fn _, _ ->
            {:ok, record} = Store.load_record(store, :agent, "run")
            send(owner, {:intent_at_io, record})

            {:tool_calls,
             [%Part.ToolCall{tool_name: "effect", tool_call_id: id, args: %{"retry" => retry?}}]}
          end
        end

      final = fn _, _ ->
        {:ok, record} = Store.load_record(store, :agent, "run")
        send(owner, {:intent_at_io, record})
        "done"
      end

      agent =
        ExAgent.new(
          model: %ExAgent.Models.Test{script: script ++ [final]},
          tools: [tool],
          capabilities: [Change, %Observe{}],
          max_steps: 5,
          output_retries: 1
        )

      change = fn s ->
        %{
          s
          | tool_retries: %{"forged" => 99},
            run_step: 99,
            tool_calls: 99,
            output_retries_used: 99,
            max_steps: 99,
            agent: %{s.agent | output_retries: 99}
        }
      end

      opts = [deps: %{owner: owner, hook: unquote(hook), change: change}]
      assert {:ok, _} = execute(kind, agent, store, opts)

      for {step, retries} <- [{1, %{}}, {2, %{"effect" => 1}}, {3, %{}}] do
        assert_receive {:intent_at_io, record}
        {frame, snapshot} = leaf(record, kind)
        assert frame["run_step"] == step
        assert frame["tool_retries"] == retries
        assert frame["limits"]["max_steps"] == 5
        assert frame["limits"]["output_retries"] == 1
        assert frame["output_retries_used"] == 0
        assert snapshot["revision"] == step
        assert counts(frame["scope"], frame["run_id"])["requests"] == step
        assert counts(frame["scope"], frame["run_id"])["tools"] == step - 1
        calls = step - 1
        assert_receive {:observed, ^step, ^calls}
      end

      captures = stored()
      assert length(captures) > 10

      for {key, command, record} <- captures do
        assert {:ok, ^record} = Record.decode(Jason.encode!(record), key)
        {frame, _} = leaf(record, kind)

        if frame do
          assert frame["run_step"] in 0..3
          assert frame["tool_retries"] in [%{}, %{"effect" => 1}]
          assert frame["limits"]["max_steps"] == 5
          assert frame["limits"]["output_retries"] == 1
          assert frame["output_retries_used"] == 0
        end

        refute Jason.encode!(command) =~ "forged"
      end

      assert_receive :effect
      assert_receive :effect
      refute_receive :effect
      {:ok, final_record} = Store.load_record(store, :agent, "run")
      {frame, _} = leaf(final_record, kind)
      assert frame["tool_retries"] == %{}
      assert_refs(kind, final_record)
    end
  end
end
