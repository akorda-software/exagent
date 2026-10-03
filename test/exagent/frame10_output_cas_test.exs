defmodule ExAgent.Frame10OutputCASTest do
  use ExUnit.Case, async: true
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Frame10OutputCASFixture, as: O
  alias ExAgent.Continuation.{Outcome, Record, ToolEvidence}
  alias ExAgent.{Message, Store}

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "output-cas10")}
  end

  defp reject(store, r, command) do
    assert {:error, _} = Store.transition(store, :agent, "conversation", r["revision"], command)
    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end

  defp roundtrip(store, r) do
    key = {store.namespace, :agent, "conversation"}
    assert {:ok, bytes} = Record.encode(r, key)
    assert {:ok, ^r} = Record.decode(bytes, key)
    r
  end

  test "approval drain retains consumed retry across pause, two decisions and reclaim", %{
    store: store
  } do
    r = O.draining(store)
    assert F.root(r)["frontier"]["state"] == "draining"
    r = F.commit(store, r, O.resolution(r, "retry"))
    cmd = F.worker(r, "output_consume", F.target("D", "invalid"))
    r = F.commit(store, r, cmd)
    consumed = r

    assert {:ok, %{record: ^r, replayed: true}} =
             Store.transition(store, :agent, "conversation", r["revision"] - 1, cmd)

    roundtrip(store, r)
    reject(store, r, F.worker(r, "output_consume", F.target("D", "invalid")))
    reject(store, r, O.request(r, "not-before-reclaim"))
    scope = F.root(r)["scope"]
    r = Enum.reduce(["D", "E", "B"], r, &F.op(store, &2, "node_suspend", %{"node_id" => &1}))
    r = F.op(store, r, "pause", %{"elapsed_ms" => 0})
    assert F.root(r)["scope"] === scope

    assert F.root(r)["children"]["D"]["snapshot"] ===
             F.root(consumed)["children"]["D"]["snapshot"]

    r =
      Enum.reduce(["pending", "ready"], r, fn expected, current ->
        {id, a} =
          Enum.find(current["execution"]["progress"]["approvals"], fn {_, a} ->
            is_nil(a["decision"])
          end)

        assert {:ok, _} =
                 ExAgent.Continuation.decide(store, "conversation", :approve,
                   record_id: current["record_id"],
                   revision: current["revision"],
                   operation_id: "decide-#{expected}",
                   approval_id: id,
                   payload_hash: a["payload_hash"],
                   actor: :host,
                   authorize: fn _, _, _ -> {:ok, "host"} end
                 )

        assert {:ok, next} = Store.load_record(store, :agent, "conversation")
        assert next["execution"]["state"] == expected
        roundtrip(store, next)
      end)

    r = F.commit(store, r, F.claim("reclaimed"))
    r = F.op(store, r, "frontier_open")
    reject(store, r, cmd)
    next = O.request(r, "valid")
    r = F.commit(store, r, next)
    reject(store, r, O.request(r, "duplicate-dispatch"))

    assert {:ok, %{record: ^r, replayed: true}} =
             Store.transition(store, :agent, "conversation", r["revision"] - 1, next)

    roundtrip(store, r)
    r = O.response(store, r, "valid")
    r = F.commit(store, r, O.resolution(r, "succeeded"))
    scope = F.root(r)["scope"]
    r = F.op(store, r, "node_complete", %{"node_id" => "D"})
    target = F.target("B", "request-B", "D")
    r = F.op(store, r, "call_wrap", target)

    final =
      Outcome.encode(%Message.Part.ToolReturn{
        tool_name: "delegate",
        tool_call_id: "D",
        status: :succeeded,
        content: "Y"
      })

    r =
      F.op(
        store,
        r,
        "call_settle",
        Map.merge(target, %{"result" => final, "control" => %{"retry" => false, "error" => nil}})
      )

    assert F.root(r)["scope"] === scope
    assert F.root(r)["scope"]["nodes"]["D"]["requests"] == 2
    assert F.root(r)["scope"]["nodes"]["root"]["requests"] == 4
    assert F.root(r)["children"]["D"]["frame"]["model_request_id"] == "valid"
    assert F.root(r)["children"]["E"]["status"] == "running"
  end

  test "two retries retain every history entry, and exhaustion certifies terminal evidence",
       %{store: store} do
    r = O.attached(store, 2)

    r =
      Enum.reduce(1..2, r, fn i, r ->
        request = "retry-#{i}"
        r = O.model(store, r, request)
        r = F.commit(store, r, O.resolution(r, "retry"))
        F.op(store, r, "output_consume", F.target("D", request))
      end)

    r = O.model(store, r, "exhausted")
    r = F.commit(store, r, O.resolution(r, "retry"))
    reject(store, r, F.worker(r, "node_complete", %{"node_id" => "D"}))
    reject(store, r, F.worker(r, "finish", %{}))
    reject(store, r, F.worker(r, "recover", %{}))
    reject(store, r, F.worker(r, "node_suspend", %{"node_id" => "D"}))
    assert F.root(r)["children"]["D"]["status"] == "failed"
    reject(store, r, O.resolution(r, "succeeded"))
    {:ok, history} = Message.from_json(F.root(r)["children"]["D"]["snapshot"]["message_history"])
    assert length(history) == 7

    assert Enum.count(
             for(%Message.Request{parts: parts} <- history, part <- parts, do: part),
             &match?(%Message.Part.Retry{}, &1)
           ) == 3

    assert map_size(F.root(r)["output_resolutions"]) == 3
    assert F.root(r)["children"]["D"]["frame"]["output_retries_used"] == 2
  end

  test "zero retry allowance certifies exhaustion, while success still needs no retry", %{
    store: store
  } do
    r = O.model(store, O.attached(store, 0), "only")
    r = F.commit(store, r, O.resolution(r, "retry"))
    assert F.root(r)["children"]["D"]["status"] == "failed"
    reject(store, r, F.worker(r, "output_consume", F.target("D", "only")))
    store = %{store | namespace: "zero-success10"}
    r = O.model(store, O.attached(store, 0), "only")
    r = F.commit(store, r, O.resolution(r, "succeeded"))
    reject(store, r, F.worker(r, "output_consume", F.target("D", "only")))
    r = F.op(store, r, "node_complete", %{"node_id" => "D"})
    assert F.root(r)["children"]["D"]["frame"]["output_retries_used"] == 0
  end

  test "stale epoch, phase and forged attestation inputs reject atomically", %{store: store} do
    r = O.model(store, O.attached(store), "invalid")
    good = O.resolution(r, "retry")

    for {path, value} <- [
          {["epoch"], 999},
          {["request_id"], "other"},
          {["resolution", "parts_hash"], String.duplicate("0", 64)},
          {["resolution", "run_id"], "B"},
          {["resolution", "call_id"], "wrong"},
          {["resolution", "descriptor", "mode"], "text"},
          {["resolution", "decision"], "fatal"}
        ] do
      reject(store, r, put_in(good, ["payload" | path], value))
    end

    r = F.commit(store, r, good)
    reject(store, r, put_in(good, ["payload", "resolution", "decision"], "succeeded"))
    reject(store, r, O.resolution(r, "retry"))
    r = F.op(store, r, "output_consume", F.target("D", "invalid"))
    reject(store, r, O.resolution(r, "retry"))
    reject(store, r, F.worker(r, "node_complete", %{"node_id" => "D"}))
  end

  for decision <- ["retry", "succeeded"] do
    test "unconsumed #{decision} attestation survives real suspended response ACK", %{
      store: store
    } do
      r = O.draining(store)
      r = F.commit(store, r, O.resolution(r, unquote(decision)))
      before = F.root(r)
      r = Enum.reduce(["D", "E", "B"], r, &F.op(store, &2, "node_suspend", %{"node_id" => &1}))
      r = F.op(store, r, "pause", %{"elapsed_ms" => 0})
      assert F.root(r)["children"]["D"]["frame"]["cursor"] == "response"
      assert F.root(r)["children"]["D"]["frame"]["output_retries_used"] == 0
      assert F.root(r)["output_resolutions"] === before["output_resolutions"]
      assert F.root(r)["scope"] === before["scope"]
    end
  end

  test "typed terminal must match resolution, source raw and exact consumed history", %{
    store: store
  } do
    r = O.model(store, O.attached(store), "typed")
    r = F.commit(store, r, O.resolution(r, "succeeded"))
    r = F.op(store, r, "node_complete", %{"node_id" => "D"})
    root = F.root(r)
    batch = ToolEvidence.key("B", "request-B")
    {:ok, history} = Message.from_json(root["children"]["D"]["snapshot"]["message_history"])

    model_id =
      Enum.find_value(r["execution"]["effects"], fn {id, e} ->
        if e["intent"]["call_id"] == "typed", do: id
      end)

    path = ~w(execution progress runtime)

    for bad <- [
          put_in(r, path ++ ~w(children D result), %{"n" => 43}),
          put_in(
            r,
            path ++ ~w(children D snapshot message_history),
            Message.to_json(Enum.drop(history, -1))
          ),
          put_in(
            r,
            path ++ ~w(children D snapshot message_history),
            Message.to_json(history ++ [List.last(history)])
          ),
          put_in(r, path ++ ["tool_batches", batch, "calls", "delegate", "source", "id"], "B"),
          put_in(
            r,
            path ++ ["tool_batches", batch, "calls", "delegate", "raw", "result"],
            Outcome.encode(%Message.Part.ToolReturn{
              tool_name: "delegate",
              tool_call_id: "delegate",
              status: :succeeded,
              content: %{"n" => 43}
            })
          ),
          put_in(r, ["execution", "effects", model_id, "intent", "payload", "history_index"], 0)
        ] do
      assert {:error, _} =
               Record.decode(Jason.encode!(bad), {store.namespace, :agent, "conversation"})
    end

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end

  test "global certificate rejects tampered consumed output positions, counters, source and orphans",
       %{store: store} do
    r = O.model(store, O.attached(store), "invalid")
    r = F.commit(store, r, O.resolution(r, "retry"))
    r = F.op(store, r, "output_consume", F.target("D", "invalid"))
    path = ~w(execution progress runtime)
    entry = F.root(r)["output_resolutions"]["invalid"]

    mutations = [
      {~w(children D frame output_retries_used), 0},
      {~w(children D frame output_retries_used), 2},
      {~w(children D frame limits output_retries), 0},
      {~w(children D frame cursor), "response"},
      {~w(children D frame model_request_id), "fake-next"},
      {~w(children D frame output_fingerprint), String.duplicate("a", 64)},
      {~w(output_resolutions invalid parts_hash), String.duplicate("a", 64)},
      {~w(output_resolutions invalid run_id), "B"},
      {~w(output_resolutions invalid request_id), "other"},
      {~w(output_resolutions orphan), entry},
      {~w(output_resolutions), %{}},
      {~w(children D status), "completed"}
    ]

    for {suffix, value} <- mutations do
      bad = put_in(r, path ++ suffix, value)
      key = {store.namespace, :agent, "conversation"}
      assert {:error, _} = Record.decode(Jason.encode!(bad), key), inspect(suffix)
    end

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end

  test "real CAS retries consume once and complete typed child with canonical raw", %{
    store: store
  } do
    r = O.attached(store)
    usage = Message.Usage.qualify(%Message.Usage{input_tokens: 2, output_tokens: 1})
    r = O.model(store, r, "invalid", usage)
    r = F.commit(store, r, O.resolution(r, "retry"))
    r = F.op(store, r, "output_consume", F.target("D", "invalid"))
    assert F.root(r)["children"]["D"]["frame"]["output_retries_used"] == 1
    r = O.model(store, r, "valid", usage)
    r = F.commit(store, r, O.resolution(r, "succeeded"))
    scope = F.root(r)["scope"]
    r = F.op(store, r, "node_complete", %{"node_id" => "D"})
    assert F.root(r)["scope"] === scope
    child = F.root(r)["children"]["D"]
    assert child["result"] == %{"n" => 42}
    batch = F.root(r)["tool_batches"][ToolEvidence.key("B", "request-B")]
    assert {:ok, raw} = ToolEvidence.child_raw10(child, F.call("delegate", "delegate"))
    assert batch["calls"]["delegate"]["raw"] === raw
    target = F.target("B", "request-B", "delegate")
    r = F.op(store, r, "call_wrap", target)

    final =
      Outcome.encode(%Message.Part.ToolReturn{
        tool_name: "delegate",
        tool_call_id: "delegate",
        status: :succeeded,
        content: "wrapper Y"
      })

    r =
      F.op(
        store,
        r,
        "call_settle",
        Map.merge(target, %{"result" => final, "control" => %{"retry" => false, "error" => nil}})
      )

    r = F.op(store, r, "tool_resolution", F.target("B", "request-B"))
    r = F.op(store, r, "batch_consume", F.target("B", "request-B"))
    assert F.root(r)["scope"] === scope
  end
end
