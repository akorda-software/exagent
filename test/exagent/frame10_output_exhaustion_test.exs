defmodule ExAgent.Frame10OutputExhaustionTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, Message, Store}
  alias ExAgent.Continuation.{OutputResolution, Record, ToolEvidence}
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Frame10OutputCASFixture, as: O
  alias ExAgent.Frame10OutputExhaustionFixture, as: X
  alias ExAgent.Frame10OutputCapacityFixture, as: C

  @moduletag timeout: 600_000
  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "output-exhaustion10")}
  end

  test "mixed node/call errors use structural order, not arrival; admitted effects must drain", %{
    store: store
  } do
    for order <- [["D", "E"], ["E", "D"]], arrivals <- [[:node, :call], [:call, :node]] do
      store = %{store | namespace: "mixed-#{Enum.join(order)}-#{hd(arrivals)}"}
      r = X.setup(store, order)
      before = r
      [first, last] = arrivals
      r = if first == :node, do: X.exhaust(store, r), else: X.fatal(store, r)
      X.reject(store, r, F.worker(r, "finish", %{"elapsed_ms" => 29}))
      r = if last == :node, do: X.exhaust(store, r), else: X.fatal(store, r)
      X.reject(store, r, F.worker(r, "finish", %{"elapsed_ms" => 29}))
      X.reject(store, r, O.request(r, "new-model"))
      X.reject(store, r, F.worker(r, "batch_begin", F.target("D", "invalid")))
      selected = F.root(r)["frontier"]["fatal"]
      assert selected["kind"] == if(hd(order) == "D", do: "node", else: "call")
      assert selected["run_id"] == hd(order)
      r = X.drain(store, r)
      X.reject(store, r, F.worker(r, "call_wrap", F.target("E", "request-E", "admitted")))
      drained = r
      r = X.close(store, r)
      assert F.root(r)["frontier"]["fatal"] == selected
      assert F.root(r)["children"]["done"] == F.root(before)["children"]["done"]
      assert F.root(r)["children"]["D"]["status"] == "failed"
      assert F.root(r)["scope"] == F.root(drained)["scope"]
      assert r["execution"]["effects"] == drained["execution"]["effects"]
      assert r["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_971
      assert {:ok, %{record: ^r, status: :failed}} = Continuation.get(store, "conversation")
    end
  end

  test "source-prefix boundary with escaped maximum receipts, terminal diagnostic and 4096 call error",
       %{store: store} do
    roomy = %{store | namespace: String.pad_trailing("capacity-roomy", 32, "x")}
    {final, source} = X.run(roomy, ["D", "E"], [:node, :call])
    {source_command, _, threshold} = Enum.max_by(source, &elem(&1, 2))
    assert byte_size(Jason.encode!(ToolEvidence.reservation_error())) == 4096
    assert final["execution"]["state"] == "failed"
    assert Enum.max(Enum.map(Process.get(:rows), &elem(&1, 2))) == threshold
    IO.puts("exhaustion source MAX=#{threshold} op=#{source_command["operation"]}")

    for delta <- [-1, 0, 1] do
      s = %{store | namespace: String.pad_trailing("capacity-#{delta}", 32, "x")}

      if delta == -1 do
        assert {:rejected, cmd, {:error, :record_limit}, previous} =
                 catch_throw(X.run(s, ["D", "E"], [:node, :call], threshold + delta))

        assert cmd["operation"] == source_command["operation"]
        assert cmd["operation_id"] == source_command["operation_id"]
        assert is_nil(F.root(previous)["frontier"]["fatal"])
        assert {:ok, ^previous} = Store.load_record(s, :agent, "conversation")
      else
        {r, _} = X.run(s, ["D", "E"], [:node, :call], threshold + delta)
        assert r["execution"]["state"] == "failed"
        assert F.root(r)["children"]["D"]["frame"]["output_retries_used"] == 0
        assert F.root(r)["children"]["done"]["result"] == "confirmed partial"
      end
    end
  end

  test "step-only exhaustion reserves attestation before validation without borrowing a tool batch",
       %{store: store} do
    s = %{store | namespace: "step-capacity-00"}
    r = X.step_source(s, Record.max_bytes())
    source = Process.get(:rows)
    {cmd, _, threshold} = Enum.max_by(source, &elem(&1, 2))
    r = X.step_exhaust(s, r)
    r = X.close(s, r)
    assert r["execution"]["state"] == "failed"
    assert F.root(r)["tool_batches"] == %{}
    assert Enum.max(Enum.map(Process.get(:rows), &elem(&1, 2))) == threshold
    # The limit's own decimal width changes when narrowing from8MiB. Measure an
    # actual source with that width before taking exact +/-1, not the later sink.
    s = %{store | namespace: "step-capacity-01"}
    _ = X.step_source(s, threshold)
    {_, _, threshold} = Enum.max_by(Process.get(:rows), &elem(&1, 2))
    IO.puts("step exhaustion source MAX=#{threshold} op=#{cmd["operation"]}")

    for {delta, suffix} <- [{-1, "02"}, {0, "03"}, {1, "04"}] do
      s = %{store | namespace: "step-capacity-#{suffix}"}

      if delta == -1 do
        assert {:rejected, rejected, {:error, :record_limit}, before} =
                 catch_throw(X.step_source(s, threshold + delta))

        assert rejected["operation"] == cmd["operation"]
        assert is_nil(F.root(before)["frontier"]["fatal"])
      else
        r = X.step_source(s, threshold + delta)
        r = X.step_exhaust(s, r)
        assert X.close(s, r)["execution"]["state"] == "failed"
      end
    end
  end

  defp reject(store, r, cmd) do
    assert {:error, _} = Store.transition(store, :agent, "conversation", r["revision"], cmd)
    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end

  test "preparing ambiguity survives node exhaustion and a settled sibling fatal", %{store: store} do
    r = X.setup(store, ["D", "E"], Record.max_bytes(), :preparing)
    r = X.exhaust(store, r)
    r = X.fatal(store, r)
    assert Record.unresolved?(r["execution"])
    reject(store, r, F.worker(r, "finish", %{"elapsed_ms" => 3}))
    reject(store, r, F.worker(r, "pause", %{"elapsed_ms" => 3}))

    reject(
      store,
      r,
      F.worker(r, "call_prepared", Map.put(F.target("E", "request-E", "admitted"), "args", %{}))
    )

    assert {:ok, %{record: ^r}} = Continuation.get(store, "conversation")
  end

  test "multiple pending exhaustion frontiers with large IDs consume only their own history/receipts",
       %{store: store} do
    large = String.duplicate("Z", 512)
    r = C.attached(store, Record.max_bytes(), [large, "D"])

    r =
      Enum.reduce(1..3, r, fn i, r ->
        Enum.reduce(["D", large], r, fn run, r ->
          r = C.response(store, r, run, "#{String.slice(run, 0, 1)}-retry-#{i}")
          r = C.commit(store, r, C.resolution(r, "retry", "invalid", run))
          C.consume(store, r, "retry", run)
        end)
      end)

    r = C.response(store, r, "D", "D-last")
    r = C.response(store, r, large, String.duplicate("Q", 512))
    scope = F.root(r)["scope"]
    r = C.commit(store, r, C.resolution(r, "retry", "last-D", "D"))
    first = F.root(r)["children"]["D"]
    assert F.root(r)["frontier"]["fatal"]["run_id"] == "D"
    r = C.commit(store, r, C.resolution(r, "retry", "last-large", large))
    assert F.root(r)["frontier"]["fatal"]["run_id"] == large
    assert F.root(r)["children"]["D"] == first
    assert F.root(r)["scope"] == scope
    r = F.op(store, r, "finish", %{"elapsed_ms" => 0})
    assert F.root(r)["scope"] == scope

    for run <- ["D", large] do
      assert F.root(r)["children"][run]["status"] == "failed"
      assert F.root(r)["children"][run]["frame"]["output_retries_used"] == 3
      assert F.root(r)["children"][run]["frame"]["scope"]["requests"] == 4
    end
  end

  test "pause refund then reclaim reserves current balance; exhaustion refunds only current claim",
       %{store: store} do
    r = O.draining(store)
    r = F.commit(store, r, O.resolution(r, "retry"))
    r = F.op(store, r, "output_consume", F.target("D", "invalid"))
    r = Enum.reduce(["D", "E", "B"], r, &F.op(store, &2, "node_suspend", %{"node_id" => &1}))
    r = F.op(store, r, "pause", %{"elapsed_ms" => 11})
    assert r["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_989

    r =
      Enum.reduce(1..2, r, fn i, r ->
        {id, approval} =
          Enum.find(r["execution"]["progress"]["approvals"], fn {_, a} ->
            is_nil(a["decision"])
          end)

        assert {:ok, _} =
                 Continuation.decide(store, "conversation", :approve,
                   record_id: r["record_id"],
                   revision: r["revision"],
                   operation_id: "decision-#{i}",
                   approval_id: id,
                   payload_hash: approval["payload_hash"],
                   actor: :host,
                   authorize: fn _, _, _ -> {:ok, "host"} end
                 )

        {:ok, next} = Store.load_record(store, :agent, "conversation")
        next
      end)

    r = F.commit(store, r, F.claim("reclaimed"))
    r = F.op(store, r, "frontier_open")
    assert r["execution"]["progress"]["active_budget"]["reserved_ms"] == 59_989
    r = O.model(store, r, "last-invalid")
    scope = F.root(r)["scope"]
    r = F.commit(store, r, O.resolution(r, "retry"))
    before = r
    command = F.worker(r, "finish", %{"elapsed_ms" => 17})
    r = F.commit(store, r, command)
    assert r["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_972
    assert is_nil(r["execution"]["progress"]["active_budget"]["reserved_ms"])
    assert F.root(r)["scope"] == scope

    assert {:ok, %{record: ^r, replayed: true}} =
             Store.transition(store, :agent, "conversation", before["revision"], command)

    reject(store, r, F.claim("closed"))
    reject(store, r, F.worker(r, "cancel", %{}))
    reject(store, r, F.worker(r, "recover", %{}))
    assert {:ok, %{status: :failed, record: ^r}} = Continuation.get(store, "conversation")
  end

  for limit <- [0, 1, 3] do
    test "exact exhaustion #{limit} closes with one terminal Retry and no new permission", %{
      store: store
    } do
      limit = unquote(limit)
      r = O.attached(store, limit)

      r =
        Enum.reduce(Enum.to_list(1..limit//1), r, fn i, r ->
          request = "retry-#{i}"
          r = O.model(store, r, request)
          r = F.commit(store, r, O.resolution(r, "retry"))
          F.op(store, r, "output_consume", F.target("D", request))
        end)

      r = O.model(store, r, "exhausted")
      before = r
      command = O.resolution(r, "retry")
      r = F.commit(store, r, command)
      child = F.root(r)["children"]["D"]
      assert child["status"] == "failed"
      assert child["error"] == OutputResolution.exhaustion_error10()
      assert child["frame"]["output_retries_used"] == limit
      assert child["frame"]["scope"]["requests"] == limit + 1
      assert F.root(r)["scope"] == F.root(before)["scope"]
      assert r["execution"]["effects"] == before["execution"]["effects"]
      {:ok, history} = Message.from_json(child["snapshot"]["message_history"])
      assert length(history) == 2 * limit + 3

      assert Enum.at(history, -2) ==
               List.last(
                 elem(
                   Message.from_json(
                     F.root(before)["children"]["D"]["snapshot"]["message_history"]
                   ),
                   1
                 )
               )

      assert F.root(r)["frontier"]["fatal"] == %{
               "kind" => "node",
               "run_id" => "D",
               "error" => child["error"]
             }

      assert {:ok, %{record: ^r, replayed: true}} =
               Store.transition(store, :agent, "conversation", before["revision"], command)

      reject(store, r, F.worker(r, "output_consume", F.target("D", "exhausted")))
      reject(store, r, O.request(r, "forbidden"))
      reject(store, r, O.resolution(r, "retry"))
      reject(store, r, F.worker(r, "node_complete", %{"node_id" => "D"}))
      parent = F.root(r)["tool_batches"][ToolEvidence.key("B", "request-B")]["calls"]["delegate"]
      assert parent["raw"]["control"]["error"] == child["error"]
      reject(store, r, F.worker(r, "call_wrap", F.target("B", "request-B", "delegate")))
      r = F.op(store, r, "finish", %{"elapsed_ms" => 17})
      assert {:ok, %{status: :failed, record: ^r}} = Continuation.get(store, "conversation")
      assert r["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_983
      assert F.root(r)["children"]["D"] == child

      assert F.root(r)["tool_batches"][ToolEvidence.key("B", "request-B")]["calls"]["delegate"] ==
               parent |> Map.put("state", "blocked") |> Map.put("blocked_by", "fatal")

      reject(store, r, F.claim())
      reject(store, r, F.worker(r, "finish", %{"elapsed_ms" => 17}))

      for {path, value} <- [
            {~w(children D frame output_retries_used), limit + 1},
            {~w(children D frame limits output_retries), limit + 1},
            {~w(children D frame model_request_id), "fake-next"},
            {~w(children D frame cursor), "request"},
            {~w(children D error), ToolEvidence.error(:generic_failure)},
            {~w(output_resolutions exhausted parts_hash), String.duplicate("0", 64)},
            {~w(output_resolutions exhausted decision), "exhaust"},
            {~w(output_resolutions exhausted run_id), "B"},
            {~w(output_resolutions), %{}},
            {~w(children D snapshot message_history), Message.to_json(Enum.drop(history, -1))}
          ] do
        bad = put_in(r, ~w(execution progress runtime) ++ path, value)

        assert {:error, _} =
                 Record.decode(Jason.encode!(bad), {store.namespace, :agent, "conversation"}),
               inspect(path)
      end
    end
  end
end
