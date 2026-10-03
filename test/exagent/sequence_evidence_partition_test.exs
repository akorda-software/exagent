defmodule ExAgent.SequenceEvidencePartitionTest do
  use ExUnit.Case, async: false

  alias ExAgent.{ExecutionScope, Message, Store, Tool}
  alias ExAgent.Continuation.{Frame, OutputResolution, Record, Writer}
  alias ExAgent.Coordination.Composition
  alias ExAgent.Message.Part
  alias ExAgent.ContinuationNativeFixture.CountOutput

  setup do
    start_supervised!({Store.ETS, table: __MODULE__.A}, id: :a)
    start_supervised!({Store.ETS, table: __MODULE__.B}, id: :b)
    :ok
  end

  defp leaf(label, typed?) do
    owner = self()
    call = %Part.ToolCall{tool_name: "effect", tool_call_id: "reused", args: %{}}

    output = %Part.ToolCall{
      tool_name: "final_result",
      tool_call_id: "reused",
      args: %{"count" => 7}
    }

    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, {:effect, label})
          {:ok, label}
        end
      )

    script = [{:tool_calls, [call]}, if(typed?, do: {:tool_calls, [output]}, else: label)]

    agent =
      ExAgent.new(
        model: %ExAgent.Models.Test{script: script},
        tools: [tool],
        output: if(typed?, do: CountOutput, else: :text)
      )

    ref = %{id: "fixture", version: "1"}

    step = %{
      id: label,
      agent: agent,
      definition: ref,
      policy: ref,
      model_ref: ref,
      output_ref: ref,
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, data -> {:ok, %{m | index: data["index"]}} end
      }
    }

    assert {:ok, definition} = Composition.new(id: label, version: "1", steps: [step])
    assert {:ok, scope} = ExecutionScope.start_structural("root", [])
    table = if label == "A", do: __MODULE__.A, else: __MODULE__.B
    store = Store.scoped({Store.ETS, table}, "partition")

    config = %{
      kind: :composition,
      composition: definition,
      store: store,
      id: "record",
      definition: %{"id" => label, "version" => "1"},
      policy: %{"id" => "fixture", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000
    }

    # Explicit legacy-9 source; current producer-10 has separate runtime coverage.
    assert {:ok, writer, _} =
             ExAgent.LegacyStructuralFixture.open(
               %{run_id: "root", execution_scope: scope, input: label},
               config
             )

    try do
      assert {:ok, _} = ExAgent.run_composition_step(writer, definition, label, [])
      assert_receive {:effect, ^label}
      refute_receive {:effect, ^label}
      assert {:ok, record} = Store.load_record(store, :agent, "record")

      assert {:ok, ^record} =
               Record.decode(Jason.encode!(record), {"partition", :agent, "record"})

      assert :ok = Frame.structural_evidence(record)
      record
    after
      Writer.stop(writer)
      ExecutionScope.stop(scope)
    end
  end

  # Combine authentic, independently executed evidence for the partition helper.
  # This is deliberately not a persisted Frame8/9 record or a sequence execution.
  defp project(a, b) do
    ar = a["execution"]["progress"]["runtime"]
    br = b["execution"]["progress"]["runtime"]

    root =
      Enum.reduce(~w(children authority output_resolutions tool_batches), ar, fn field, root ->
        Map.put(root, field, Map.merge(ar[field], br[field]))
      end)

    scope =
      Enum.reduce(~w(operations batches retry_batches), ar["scope"], fn field, scope ->
        Map.put(scope, field, ar["scope"][field] ++ br["scope"][field])
      end)

    scope = Map.put(scope, "nodes", Map.merge(ar["scope"]["nodes"], br["scope"]["nodes"]))

    a
    |> put_in(
      ["execution", "effects"],
      Map.merge(a["execution"]["effects"], b["execution"]["effects"])
    )
    |> put_in(["execution", "progress", "runtime"], Map.put(root, "scope", scope))
  end

  defp output_evidence(record, child) do
    assert {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])

    models =
      record["execution"]["effects"]
      |> Map.values()
      |> Enum.filter(
        &(&1["intent"]["kind"] == "model" and
            &1["intent"]["payload"]["run_id"] == child["frame"]["run_id"])
      )

    OutputResolution.evidence?(record, child, messages, models)
  end

  for kinds <- [[true, true], [true, false], [false, true], [false, false]] do
    test "real leaf evidence partitions tools/output #{inspect(kinds)} with repeated provider call IDs" do
      [left, right] = unquote(kinds)
      record = project(leaf("A", left), leaf("B", right))
      assert :ok = Frame.graph_evidence(record)
      assert ExAgent.Continuation.ToolEvidence.evidence?(record)
      assert :ok = Frame.structural_evidence(record)
      assert OutputResolution.coverage?(record)

      for child <- Map.values(record["execution"]["progress"]["runtime"]["children"]) do
        assert output_evidence(record, child)
      end

      assert {:error, _} = Record.validate(record, {"partition", :agent, "record"})
    end
  end

  test "partition cannot hide orphaned output, model or tool evidence" do
    record = project(leaf("A", true), leaf("B", true))
    assert :ok = Frame.structural_evidence(record)
    root = record["execution"]["progress"]["runtime"]
    [{request, entry} | _] = Map.to_list(root["output_resolutions"])
    [child | _] = Map.values(root["children"])

    for bad <- [%{entry | "run_id" => "unknown"}, %{entry | "request_id" => "unknown"}, nil, 1] do
      corrupted =
        put_in(record, ["execution", "progress", "runtime", "output_resolutions", request], bad)

      refute OutputResolution.coverage?(corrupted)
      refute output_evidence(corrupted, child)
      assert {:error, _} = Frame.structural_evidence(corrupted)
    end

    for kind <- ~w(model tool) do
      {id, _} =
        Enum.find(record["execution"]["effects"], fn {_, e} -> e["intent"]["kind"] == kind end)

      corrupted =
        put_in(record, ["execution", "effects", id, "intent", "payload", "run_id"], "unknown")

      assert {:error, _} = Frame.structural_evidence(corrupted)
    end
  end

  test "global host request identity cannot be reused across leaves" do
    record = project(leaf("A", true), leaf("B", true))

    models =
      Enum.filter(record["execution"]["effects"], fn {_, e} -> e["intent"]["kind"] == "model" end)

    [{id, _}, {_, other} | _] = models

    corrupted =
      put_in(
        record,
        ["execution", "effects", id, "intent", "call_id"],
        other["intent"]["call_id"]
      )

    refute OutputResolution.coverage?(corrupted)
    assert {:error, _} = Frame.structural_evidence(corrupted)
  end

  test "partition retains same-leaf attestation and tool result validation" do
    record = project(leaf("A", true), leaf("B", true))
    root = record["execution"]["progress"]["runtime"]
    [{request, _} | _] = Map.to_list(root["output_resolutions"])

    corrupted =
      put_in(
        record,
        ["execution", "progress", "runtime", "output_resolutions", request, "parts_hash"],
        String.duplicate("0", 64)
      )

    assert {:error, _} = Frame.structural_evidence(corrupted)

    {id, _} =
      Enum.find(record["execution"]["effects"], fn {_, e} -> e["intent"]["kind"] == "tool" end)

    corrupted =
      put_in(
        record,
        ["execution", "effects", id, "intent", "payload", "call_hash"],
        String.duplicate("0", 64)
      )

    assert {:error, _} = Frame.structural_evidence(corrupted)
  end
end
