defmodule ExAgent.ContinuationRetentionIntegrationTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Message, Store}
  alias ExAgent.Continuation.Record
  alias ExAgent.Message.{Part, Request, Usage}
  alias ExAgent.Server.Snapshot
  import ExAgent.Test.ContinuationFixtures

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "tenant-a")}
  end

  test "public record seam retains legacy1–3 bytes and reads snapshot4 through its public codec",
       %{
         store: store
       } do
    for version <- 1..4 do
      id = "version-#{version}"
      data = snapshot(id) |> Map.put("version", version)
      data = if version < 3, do: Map.delete(data, "revision"), else: data
      cmd = put_in(create(id), ["payload", "snapshot"], data)
      assert {:ok, %{record: record}} = Store.transition(store, :agent, id, :absent, cmd)
      assert record["snapshot"] == data
      key = {"tenant-a", :agent, id}
      assert {:ok, bytes} = Record.encode(record, key)
      assert {:ok, ^record} = Record.decode(bytes, key)
      assert {:ok, restored} = Record.snapshot(record["snapshot"], key)
      assert restored.version == 4
      assert restored.revision == if(version < 3, do: 0, else: 7)
      assert {:ok, []} = Snapshot.messages(restored)
      assert {:ok, ^record} = Store.load_record(store, :agent, id)
    end
  end

  test "record roundtrip preserves omitted nil status IDs and qualified usage and cannot revive IO",
       %{
         store: store
       } do
    marker = %{"version" => 1, "boundary" => "tool_return", "bytes" => 210_000, "limit" => 8192}

    part = %Part.ToolReturn{
      tool_name: "effect",
      tool_call_id: "confirmed",
      content: nil,
      status: :succeeded,
      payload_omitted: marker
    }

    usage_marker = %{"version" => 1, "boundary" => "usage", "bytes" => 9000, "limit" => 4096}
    usage = %Usage{input_tokens: 7, output_tokens: 3, payload_omitted: usage_marker}
    history = [%Request{parts: [part]}]

    data =
      Snapshot.new(agent_id: "omitted", history: history, usage: usage) |> Record.snapshot_data()

    cmd = put_in(create("omitted"), ["payload", "snapshot"], data)
    assert {:ok, %{record: record}} = Store.transition(store, :agent, "omitted", :absent, cmd)
    assert {:ok, bytes} = Record.encode(record, {"tenant-a", :agent, "omitted"})
    assert {:ok, ^record} = Record.decode(bytes, {"tenant-a", :agent, "omitted"})
    assert record["snapshot"]["usage"]["accounting"] == data["usage"]["accounting"]
    assert record["snapshot"]["usage"]["payload_omitted"] == usage_marker
    assert {:ok, restored} = Record.snapshot(record["snapshot"], {"tenant-a", :agent, "omitted"})
    assert {:ok, ^history} = Snapshot.messages(restored)
    assert Snapshot.usage_struct(restored).payload_omitted == usage_marker
    assert Snapshot.usage_struct(restored).input_tokens == 7
    assert Message.to_json(history) =~ "tool_return_omitted_v1"
    owner = self()

    model = %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          send(owner, :unexpected_model_io)
          "bad"
        end
      ]
    }

    agent = ExAgent.new(model: model)

    for stream? <- [false, true] do
      assert {:error, %ExAgent.RunError{reason: :omitted_payload_history}} =
               ExAgent.run(agent, "continue", message_history: history, stream_text: stream?)
    end

    refute_receive :unexpected_model_io
    assert {:error, :atomic_record_required} = Store.load_agent_snapshot(store, "omitted")
    assert {:ok, ^record} = Store.load_record(store, :agent, "omitted")
  end

  test "record key namespace kind and snapshot payload ID cannot be substituted", %{store: store} do
    assert {:ok, %{record: record}} =
             Store.transition(store, :agent, "conversation", :absent, create())

    assert {:ok, bytes} = Record.encode(record, key())

    for wrong <- [
          {"tenant-b", :agent, "conversation"},
          {"tenant-a", :session, "conversation"},
          {"tenant-a", :agent, "other"}
        ] do
      assert {:error, :invalid_record} = Record.decode(bytes, wrong)
    end

    bad = put_in(create("other"), ["payload", "snapshot", "agent_id"], "conversation")

    assert {:error, :snapshot_id_mismatch} =
             Store.transition(store, :agent, "other", :absent, bad)

    assert {:error, :not_found} = Store.load_record(store, :agent, "other")
    assert {:ok, ^record} = Store.load_record(store, :agent, "conversation")
    other = Store.scoped({Store.ETS, __MODULE__}, "tenant-b")
    assert {:error, :not_found} = Store.load_record(other, :agent, "conversation")
  end
end
