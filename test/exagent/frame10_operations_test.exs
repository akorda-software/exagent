defmodule ExAgent.Frame10OperationsTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, Store}
  alias ExAgent.Frame10OperationsFixture, as: F

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "frame10-operations")}
  end

  test "terminal child raw X, wrap ACK, final Y and ordered consume are real CAS operations", %{
    store: store
  } do
    {r, attach} = F.attached(store, F.started(store))
    r = F.op(store, r, "node_attach", attach)
    r = F.model(store, r, "D", "request-D", [%ExAgent.Message.Part.Text{content: "X"}])
    r = F.op(store, r, "node_complete", %{"node_id" => "D"})
    target = F.target("B", "request-B", "delegate")

    final =
      ExAgent.Continuation.Outcome.encode(%ExAgent.Message.Part.ToolReturn{
        tool_name: "delegate",
        tool_call_id: "delegate",
        content: "Y",
        status: :succeeded
      })

    payload =
      Map.merge(target, %{"result" => final, "control" => %{"retry" => false, "error" => nil}})

    assert {:error, _} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "call_settle", payload)
             )

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    r = F.op(store, r, "call_wrap", target)
    r = F.op(store, r, "call_settle", payload)
    child = F.root(r)["children"]["D"]
    assert child["result"] == "X"
    r = F.op(store, r, "tool_resolution", F.target("B", "request-B"))
    r = F.op(store, r, "batch_consume", F.target("B", "request-B"))
    assert F.root(r)["children"]["D"] === child
    assert F.root(r)["children"]["B"]["frame"]["outcomes"] == %{}

    assert {:error, _} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "node_complete", %{"node_id" => "D"})
             )

    r = F.model(store, r, "B", "next-B", [F.call("plain", "next")])
    assert F.root(r)["children"]["B"]["frame"]["run_step"] == 2
  end

  test "unknown host source has no binding, uses original identity and never invents an effect",
       %{store: store} do
    r = F.model(store, F.started(store), "B", "unknown-request", [F.call("absent", "unknown")])
    target = F.target("B", "unknown-request", "unknown")
    r = F.op(store, r, "call_prepare", target)

    payload =
      Map.merge(target, %{
        "reason" => "unknown_tool",
        "error" => ExAgent.Continuation.ToolEvidence.error(:unknown_tool)
      })

    r = F.op(store, r, "call_reject", payload)

    batch =
      F.root(r)["tool_batches"][ExAgent.Continuation.ToolEvidence.key("B", "unknown-request")]

    call = batch["calls"]["unknown"]
    assert is_nil(call["binding"])
    assert call["source"]["phase"] == "unprepared"
    assert map_size(r["execution"]["effects"]) == 1

    bad =
      put_in(
        r,
        [
          "execution",
          "progress",
          "runtime",
          "tool_batches",
          ExAgent.Continuation.ToolEvidence.key("B", "unknown-request"),
          "calls",
          "unknown",
          "source",
          "call_hash"
        ],
        String.duplicate("0", 64)
      )

    assert {:error, :invalid_record} =
             ExAgent.Continuation.Record.validate(bad, {store.namespace, :agent, "conversation"})
  end

  test "real create and every ACK roundtrip through nested mixed pause, two public decisions and reclaim",
       %{store: store} do
    r = F.commit(store, nil, F.create())
    r = F.commit(store, r, F.claim())
    root = F.root(r)

    node =
      F.node(root, "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })

    r =
      F.op(store, r, "step_input", %{
        "node_id" => "B",
        "node" => node,
        "authority" => F.authority()
      })

    args = %{"task" => "delegated input", "prompt" => "distractor"}

    r =
      F.model(store, r, "B", "request-B", [
        F.call("plain", "sibling"),
        F.call("delegate", "delegate", args)
      ])

    r = F.settled(store, r, F.target("B", "request-B", "sibling"))
    target = F.target("B", "request-B", "delegate")
    r = F.prepare(store, r, target, args)

    binding =
      F.root(r)["tool_batches"][ExAgent.Continuation.ToolEvidence.key("B", "request-B")]["calls"][
        "delegate"
      ]["binding"]

    link =
      Map.merge(binding, %{
        "kind" => "delegate",
        "parent_request_id" => "request-B",
        "call_id" => "delegate"
      })

    node = F.node(F.root(r), "D", "B", link)

    authority =
      update_in(F.authority(), ["policies"], &(&1 ++ [%{"default" => "ask", "rules" => []}]))

    r =
      F.op(
        store,
        r,
        "node_attach",
        Map.merge(target, %{"node_id" => "D", "node" => node, "authority" => authority})
      )

    r = F.model(store, r, "D", "request-D", [F.call("plain", "first"), F.call("plain", "second")])
    r = F.prepare(store, r, F.target("D", "request-D", "first"), %{})
    r = F.prepare(store, r, F.target("D", "request-D", "second"), %{})
    r = F.op(store, r, "call_wait", F.target("D", "request-D", "first"))
    r = F.op(store, r, "call_wait", F.target("D", "request-D", "second"))
    r = F.op(store, r, "node_suspend", %{"node_id" => "D"})
    r = F.op(store, r, "node_suspend", %{"node_id" => "B"})
    r = F.op(store, r, "pause", %{"elapsed_ms" => 7})
    assert r["execution"]["state"] == "pending"
    assert F.root(r)["frontier"]["epoch"] == 1
    assert map_size(r["execution"]["progress"]["approvals"]) == 2

    for expected <- ["pending", "ready"] do
      {:ok, current} = Store.load_record(store, :agent, "conversation")

      {id, approval} =
        Enum.find(current["execution"]["progress"]["approvals"], fn {_, a} ->
          is_nil(a["decision"])
        end)

      assert {:ok, _} =
               Continuation.decide(store, "conversation", :approve,
                 record_id: current["record_id"],
                 revision: current["revision"],
                 operation_id: "decision-#{expected}",
                 approval_id: id,
                 payload_hash: approval["payload_hash"],
                 actor: :host,
                 authorize: fn _, _, _ -> {:ok, "host"} end
               )

      {:ok, next} = Store.load_record(store, :agent, "conversation")
      assert next["execution"]["state"] == expected
      key = {store.namespace, :agent, "conversation"}
      assert {:ok, bytes} = ExAgent.Continuation.Record.encode(next, key)
      assert {:ok, ^next} = ExAgent.Continuation.Record.decode(bytes, key)
    end

    {:ok, r} = Store.load_record(store, :agent, "conversation")
    r = F.commit(store, r, F.claim("second-attempt"))
    r = F.op(store, r, "frontier_open")
    # pause releases/fences the first owner; reclaim advances the fence again.
    assert r["execution"]["fence"] == 3
    assert F.root(r)["frontier"]["state"] == "open"
    assert Enum.all?(F.root(r)["children"], fn {_, n} -> n["status"] == "running" end)
  end
end
