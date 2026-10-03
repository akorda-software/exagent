defmodule ExAgent.Frame10CASTest do
  use ExUnit.Case, async: false
  alias ExAgent.Store
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Continuation.{Outcome, Record}

  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, namespace, query), do: Store.ETS.scan_records(c.table, namespace, query)

    def transition(c, key, expected, command) do
      case Agent.get_and_update(c.fault, &{&1, :ok}) do
        :before ->
          {:error, :save_failed}

        :after ->
          {:ok, _} = Store.ETS.transition(c.table, key, expected, command)
          {:error, :lost_ack}

        :ok ->
          Store.ETS.transition(c.table, key, expected, command)
      end
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    fault = start_supervised!({Agent, fn -> :ok end})
    store = Store.scoped({FaultStore, %{table: __MODULE__, fault: fault}}, "cas10")
    %{store: store, fault: fault}
  end

  test "two simultaneous claimants, operation conflict, and old receipt is not new authority", %{
    store: store
  } do
    r = F.commit(store, nil, F.create())

    tasks =
      for attempt <- ~w(left right) do
        Task.async(fn ->
          receive do
            :go ->
              Store.transition(store, :agent, "conversation", r["revision"], F.claim(attempt))
          end
        end)
      end

    Enum.each(tasks, &send(&1.pid, :go))
    results = Enum.map(tasks, &Task.await(&1, 30_000))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 1
    {:ok, current} = Store.load_record(store, :agent, "conversation")
    assert {:ok, bytes} = Record.encode(current, {store.namespace, :agent, "conversation"})
    assert {:ok, ^current} = Record.decode(bytes, {store.namespace, :agent, "conversation"})

    {id, _} =
      Enum.find(current["receipts"], fn {_, receipt} -> receipt["operation"] == "claim" end)

    conflict = F.claim("different") |> Map.put("operation_id", id)

    assert {:error, :operation_conflict} =
             Store.transition(store, :agent, "conversation", r["revision"], conflict)

    forged = F.worker(current, "frontier_open") |> put_in(["payload", "attempt_id"], "not-owner")

    assert {:error, _} =
             Store.transition(store, :agent, "conversation", current["revision"], forged)

    assert {:ok, ^current} = Store.load_record(store, :agent, "conversation")
  end

  test "attach has no partial child/scope/authority/source on save failure or stale CAS", c do
    {r, payload} = F.attached(c.store, F.started(c.store))
    cmd = F.worker(r, "node_attach", payload)
    failed_write(c, r, cmd)

    assert {:error, :conflict} =
             Store.transition(c.store, :agent, "conversation", r["revision"] - 1, cmd)

    for field <- ~w(owner_id attempt_id fence epoch) do
      bad =
        update_in(cmd, ["payload", field], fn value ->
          if is_integer(value), do: value + 1, else: value <> "-stale"
        end)

      assert {:error, _} = Store.transition(c.store, :agent, "conversation", r["revision"], bad)
      assert {:ok, ^r} = Store.load_record(c.store, :agent, "conversation")
    end

    r = F.commit(c.store, r, cmd)
    assert F.root(r)["scope"]["nodes"]["D"]["parent_run_id"] == "B"
  end

  test "raw and final have atomic source/outcome/observation projections; lost ACK replays once",
       c do
    r = F.model(c.store, F.started(c.store), "B", "request", [F.call("plain", "call")])
    target = F.target("B", "request", "call")
    r = F.prepare(c.store, r, target, %{})
    r = F.op(c.store, r, "begin_effect", target)

    bytes =
      Outcome.encode(%ExAgent.Message.Part.ToolReturn{
        tool_name: "plain",
        tool_call_id: "call",
        content: "X",
        status: :succeeded
      })

    payload =
      Map.merge(target, %{"result" => bytes, "control" => %{"retry" => false, "error" => nil}})

    raw = F.worker(r, "outcome", payload)
    failed_write(c, r, raw)
    Agent.update(c.fault, fn _ -> :after end)

    assert {:error, :lost_ack} =
             Store.transition(c.store, :agent, "conversation", r["revision"], raw)

    assert {:ok, %{record: next, replayed: true}} =
             Store.transition(c.store, :agent, "conversation", r["revision"], raw)

    assert next["revision"] == r["revision"] + 1
    r = F.op(c.store, next, "call_wrap", target)
    settle = F.worker(r, "call_settle", payload)
    failed_write(c, r, settle)
    r = F.commit(c.store, r, settle)

    assert {:ok, %{record: ^r, replayed: true}} =
             Store.transition(c.store, :agent, "conversation", next["revision"] - 1, raw)

    assert {:error, _} =
             Store.transition(
               c.store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "begin_effect", target)
             )
  end

  test "pause failure cannot publish approvals or refund; stale epoch cannot suspend", c do
    r = F.awaiting_pause(c.store)
    cmd = F.worker(r, "pause", %{"elapsed_ms" => 5})
    failed_write(c, r, cmd)
    stale = put_in(cmd, ["payload", "epoch"], 0)
    assert {:error, _} = Store.transition(c.store, :agent, "conversation", r["revision"], stale)
    assert {:ok, ^r} = Store.load_record(c.store, :agent, "conversation")
    paused = F.commit(c.store, r, cmd)
    assert paused["execution"]["progress"]["active_budget"]["reserved_ms"] == nil
    assert paused["execution"]["progress"]["active_budget"]["remaining_ms"] <= 59_995
    assert map_size(paused["execution"]["progress"]["approvals"]) == 2
  end

  defp failed_write(c, r, command) do
    Agent.update(c.fault, fn _ -> :before end)

    assert {:error, :save_failed} =
             Store.transition(c.store, :agent, "conversation", r["revision"], command)

    assert {:ok, ^r} = Store.load_record(c.store, :agent, "conversation")
  end
end
