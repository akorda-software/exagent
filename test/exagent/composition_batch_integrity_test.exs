defmodule ExAgent.CompositionBatchIntegrityTest do
  use ExUnit.Case, async: false
  alias ExAgent.{ExecutionScope, Message, Store, Tool}
  alias ExAgent.Continuation.{Frame, Outcome, Record, Writer}
  alias ExAgent.Coordination.Composition

  defmodule Tap do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, k), do: Store.ETS.load_record(c.table, k)
    def scan_records(c, n, q), do: Store.ETS.scan_records(c.table, n, q)

    def transition(c, k, r, command) do
      runtime = command["payload"]["progress"]["runtime"]
      leaf = if runtime, do: runtime["children"] |> Map.values() |> List.first()

      if leaf && leaf["frame"]["run_step"] == c.step &&
           (command["operation"] == c.operation and
              (c.operation != "outcome" or leaf["frame"]["cursor"] == "response")) do
        {:ok, current} = Store.ETS.load_record(c.table, k)
        send(c.owner, {:blocked, k, r, command, current})
        {:error, :batch_integrity_boundary}
      else
        Store.ETS.transition(c.table, k, r, command)
      end
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    :ok
  end

  defp call(id, mode),
    do: %Message.Part.ToolCall{tool_name: "effect", tool_call_id: id, args: %{"mode" => mode}}

  defp response(calls), do: Message.new_response(calls, finish_reason: :tool_calls)

  defp fixture(batches, operation, opts \\ []) do
    tool =
      Tool.new(
        name: "effect",
        max_retries: 10,
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"mode" => %{"type" => "string"}}
        },
        call: fn _, args ->
          case args["mode"] do
            "retry" ->
              {:retry, "retry"}

            "nil" ->
              {:ok, "done"}

            "partial" ->
              {:ok, "done", Message.Usage.partial(Message.Usage.normalized(%{input_tokens: 7}))}

            _ ->
              {:ok, "done", %Message.Usage{input_tokens: 7, output_tokens: 11}}
          end
        end
      )

    output? = operation == "output_resolution"

    final =
      if output? do
        response([
          %Message.Part.ToolCall{
            tool_name: "final_result",
            tool_call_id: "output",
            args: %{"count" => 7}
          },
          call("sibling", "ok")
        ])
      else
        "done"
      end

    agent_opts =
      [
        model: %ExAgent.Models.Test{script: Enum.map(batches, &response/1) ++ [final]},
        tools: [tool]
      ]

    agent_opts =
      if output?,
        do: Keyword.put(agent_opts, :output_type, ExAgent.CompositionOutputSuccessFixture.Output),
        else: agent_opts

    step = %{
      id: "A",
      agent: ExAgent.new(agent_opts),
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, d -> {:ok, %{m | index: d["index"]}} end
      },
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"}
    }

    {:ok, definition} = Composition.new(id: "batch", version: "1", steps: [step])

    store =
      Store.scoped(
        {Tap,
         %{table: __MODULE__, owner: self(), step: length(batches) + 1, operation: operation}},
        "batch"
      )

    {:ok, scope} = ExecutionScope.start_structural("root", [])

    config = %{
      kind: :composition,
      composition: definition,
      store: store,
      id: "batch",
      definition: %{"id" => "batch", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000
    }

    # Explicit legacy-9 source; current producer-10 has separate runtime coverage.
    {:ok, writer, _} =
      ExAgent.LegacyStructuralFixture.open(
        %{run_id: "root", execution_scope: scope, input: "probe"},
        config
      )

    try do
      assert {:error,
              %ExAgent.RunError{
                reason: {:continuation_checkpoint_failed, :batch_integrity_boundary}
              }} = ExAgent.run_composition_step(writer, definition, "A", opts)

      assert_receive {:blocked, key, revision, command, current}
      assert {:ok, ^current} = Record.decode(Jason.encode!(current), key)
      {key, revision, command, current}
    after
      Writer.stop(writer)
      ExecutionScope.stop(scope)
    end
  end

  defp mutate(runtime, kind) do
    scope = runtime["scope"]
    [first | rest] = scope["batches"]
    delta = if kind == :drop, do: first["count"], else: 1
    batches = if kind == :drop, do: rest, else: [Map.update!(first, "count", &(&1 - 1)) | rest]

    scope =
      scope
      |> Map.put("batches", batches)
      |> Map.update!("nodes", fn nodes ->
        Map.new(nodes, fn {id, node} -> {id, Map.update!(node, "tools", &(&1 - delta))} end)
      end)

    Frame.with_scope(runtime, scope)
  end

  for operation <- ["step_output", "outcome", "output_resolution"],
      kind <- [:drop, :reduce],
      multi? <- [false, true] do
    @operation operation
    @kind kind
    @multi multi?
    test "#{operation} rejects coherent #{@kind} historical batch multi=#{multi?}" do
      batches = [[call("one", "ok"), call("two", "ok")]]

      batches =
        if @multi, do: batches ++ [[call("one", "partial"), call("two", "nil")]], else: batches

      {key, revision, command, current} = fixture(batches, @operation)
      changed = update_in(current, ["execution", "progress", "runtime"], &mutate(&1, @kind))
      assert changed["execution"]["effects"] === current["execution"]["effects"]
      assert {:error, :invalid_record} = Record.decode(Jason.encode!(changed), key)
      altered = update_in(command, ["payload", "progress", "runtime"], &mutate(&1, @kind))
      assert {:error, _} = Store.ETS.transition(__MODULE__, key, revision, altered)
      assert {:ok, ^current} = Store.ETS.load_record(__MODULE__, key)
      # The rejected write did not consume its operation receipt or revision.
      assert {:ok, %{record: committed}} =
               Store.ETS.transition(__MODULE__, key, revision, command)

      assert {:ok, ^committed} = Record.decode(Jason.encode!(committed), key)
      assert {:ok, _} = Store.ETS.transition(__MODULE__, key, revision, command)

      assert {:error, :conflict} =
               Store.ETS.transition(
                 __MODULE__,
                 key,
                 revision,
                 Map.put(command, "operation_id", "stale")
               )
    end
  end

  for mode <- ["nil", "partial", "retry", 42], operation <- ["step_output", "outcome"] do
    @mode mode
    @operation operation
    test "legitimate #{inspect(mode)} contribution through #{operation}" do
      {key, revision, command, _} =
        fixture([[call("same", @mode)], [call("same", "nil")]], @operation)

      assert {:ok, %{record: committed}} =
               Store.ETS.transition(__MODULE__, key, revision, command)

      assert {:ok, ^committed} = Record.decode(Jason.encode!(committed), key)
    end
  end

  test "output siblings cannot acquire a fictitious batch even with coherent counts" do
    {key, revision, command, _} = fixture([], "output_resolution")
    assert {:ok, %{record: attested}} = Store.ETS.transition(__MODULE__, key, revision, command)
    root = attested["execution"]["progress"]["runtime"]
    [child] = Map.values(root["children"])
    request = child["frame"]["model_request_id"]

    scope =
      root["scope"]
      |> Map.put("batches", [
        %{"id" => request, "run_id" => child["frame"]["run_id"], "count" => 2}
      ])
      |> Map.update!("nodes", fn nodes ->
        Map.new(nodes, fn {id, node} -> {id, %{node | "tools" => 2}} end)
      end)

    changed =
      put_in(attested, ["execution", "progress", "runtime"], Frame.with_scope(root, scope))

    assert {:error, :invalid_record} = Record.decode(Jason.encode!(changed), key)
    assert {:ok, ^attested} = Store.ETS.load_record(__MODULE__, key)
  end

  test "denied calls still consume admitted batch cardinality without usage" do
    {key, revision, command, current} =
      fixture([[call("one", "ok"), call("two", "ok")]], "step_output",
        permissions: ExAgent.Permissions.new!(default: :deny)
      )

    tools =
      current["execution"]["effects"]
      |> Map.values()
      |> Enum.filter(&(&1["intent"]["kind"] == "tool"))

    assert length(tools) == 2
    assert Enum.all?(tools, &(&1["outcome"]["status"] == "denied"))
    assert {:ok, _} = Store.ETS.transition(__MODULE__, key, revision, command)
  end

  test "usage evidence limitation: history and outcome hashes do not encode tool usage" do
    part = %Message.Part.ToolReturn{
      tool_name: "effect",
      tool_call_id: "same",
      content: "done",
      status: :succeeded
    }

    used = %{part | usage: %Message.Usage{input_tokens: 7, output_tokens: 11}}
    assert Outcome.encode(part) == Outcome.encode(used)
    assert Outcome.new(part, "final") == Outcome.new(used, "final")
    assert {:ok, [%Message.Request{parts: [decoded]}]} = Message.from_json(Outcome.encode(used))
    assert decoded.usage == nil
  end
end
