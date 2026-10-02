defmodule ExAgent.ContinuationResolutionTest do
  use ExUnit.Case, async: false
  alias ExAgent.Store
  alias ExAgent.Continuation.{Outcome, Record, Transition}
  alias ExAgent.Message.Part
  import ExAgent.Test.ContinuationFixtures

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "tenant-a")}
  end

  test "pre-dispatch resolution has no running stage and cannot fabricate successful or failed IO",
       %{store: store} do
    r = seed(store)

    for status <- [:succeeded, :failed] do
      assert {:error, :invalid_resolution} =
               Store.transition(store, :agent, "conversation", r["revision"], resolve(r, status))
    end

    {:ok, %{record: resolved}} =
      Store.transition(store, :agent, "conversation", r["revision"], resolve(r, :denied))

    effect = resolved["execution"]["effects"]["effect-1"]
    assert effect["state"] == "confirmed"
    assert effect["intent"]["payload"]["phase"] == "pre_dispatch"
    assert effect["outcome"]["data"]["phase"] == "final"

    assert {:ok, %{record: ^resolved, replayed: true}} =
             Store.transition(store, :agent, "conversation", r["revision"], resolve(r, :denied))

    changed = resolve(r, :validation_error)

    assert {:error, :operation_conflict} =
             Store.transition(store, :agent, "conversation", r["revision"], changed)

    assert {:error, :invalid_resolution} =
             Store.transition(store, :agent, "conversation", resolved["revision"], %{
               resolve(resolved, :not_executed)
               | "operation_id" => "new-resolution"
             })
  end

  test "resolve_call cannot rewrite a running or confirmed dispatch intent", %{store: store} do
    r = seed(store)

    {:ok, %{record: running}} =
      Store.transition(store, :agent, "conversation", r["revision"], dispatch(r))

    assert {:error, :invalid_resolution} =
             Store.transition(
               store,
               :agent,
               "conversation",
               running["revision"],
               resolve(running, :not_executed)
             )

    {:ok, %{record: raw}} =
      Store.transition(store, :agent, "conversation", running["revision"], raw(running))

    assert {:error, :invalid_resolution} =
             Store.transition(
               store,
               :agent,
               "conversation",
               raw["revision"],
               resolve(raw, :denied)
             )

    assert {:ok, ^raw} = Store.load_record(store, :agent, "conversation")
  end

  test "finalization fixes phase explicitly, preserves raw evidence and rejects second transform/status/stale owner",
       %{store: store} do
    r = seed(store)

    {:ok, %{record: running}} =
      Store.transition(store, :agent, "conversation", r["revision"], dispatch(r))

    {:ok, %{record: raw}} =
      Store.transition(store, :agent, "conversation", running["revision"], raw(running))

    raw_effect = raw["execution"]["effects"]["effect-1"]
    final = finalize(raw, "transformed")
    changed_status = put_in(final, ["payload", "outcome", "status"], "failed")

    assert {:error, :invalid_finalization} =
             Store.transition(store, :agent, "conversation", raw["revision"], changed_status)

    bad_hash =
      put_in(final, ["payload", "outcome", "data", "raw_hash"], String.duplicate("0", 64))

    assert {:error, :invalid_finalization} =
             Store.transition(store, :agent, "conversation", raw["revision"], bad_hash)

    stale = put_in(final, ["payload", "fence"], 0)

    assert {:error, :stale_owner} =
             Store.transition(store, :agent, "conversation", raw["revision"], stale)

    {:ok, %{record: finalized}} =
      Store.transition(store, :agent, "conversation", raw["revision"], final)

    effect = finalized["execution"]["effects"]["effect-1"]
    assert effect["intent"] == raw_effect["intent"]
    assert effect["outcome"]["status"] == "succeeded"
    assert effect["outcome"]["data"]["raw_hash"] == raw_effect["outcome"]["data"]["raw_hash"]
    assert effect["outcome"]["data"]["phase"] == "final"

    assert {:ok, %{replayed: true}} =
             Store.transition(store, :agent, "conversation", raw["revision"], final)

    assert {:error, :invalid_finalization} =
             Store.transition(store, :agent, "conversation", finalized["revision"], %{
               finalize(finalized, "another transform")
               | "operation_id" => "second-final"
             })
  end

  test "identity hook still requires an explicit final phase even when hashes are equal", %{
    store: store
  } do
    r = seed(store)

    {:ok, %{record: running}} =
      Store.transition(store, :agent, "conversation", r["revision"], dispatch(r))

    {:ok, %{record: raw}} =
      Store.transition(store, :agent, "conversation", running["revision"], raw(running))

    {:ok, %{record: final}} =
      Store.transition(store, :agent, "conversation", raw["revision"], finalize(raw, "raw"))

    data = final["execution"]["effects"]["effect-1"]["outcome"]["data"]
    assert data["raw_hash"] == data["result_hash"]
    assert data["phase"] == "final"
  end

  @tag timeout: 120_000
  test "encoded exact cap/+1 reserves raw and final receipts with escaped actor IDs", %{
    store: store
  } do
    r = seed(store)
    candidate = dispatch(r) |> put_in(["payload", "intent", "payload", "blob"], "")
    {:ok, %{record: sample}} = Transition.apply(r, key(), r["revision"], candidate, now())

    room =
      Record.max_bytes() - byte_size(Jason.encode!(sample)) - Record.cleanup_reserve_bytes(sample)

    candidate =
      put_in(candidate, ["payload", "intent", "payload", "blob"], String.duplicate("x", room))

    too_large = update_in(candidate, ["payload", "intent", "payload", "blob"], &(&1 <> "x"))

    assert {:error, :record_limit} =
             Store.transition(store, :agent, "conversation", r["revision"], too_large)

    {:ok, %{record: running}} =
      Store.transition(store, :agent, "conversation", r["revision"], candidate)

    assert Record.receipt_reserve(running["execution"]) == 4

    assert byte_size(Jason.encode!(running)) + Record.cleanup_reserve_bytes(running) ==
             Record.max_bytes()

    raw_cmd = escaped(raw(running), 1)

    {:ok, %{record: raw}} =
      Store.transition(store, :agent, "conversation", running["revision"], raw_cmd)

    assert Record.receipt_reserve(raw["execution"]) == 3

    {:ok, %{record: final}} =
      Store.transition(
        store,
        :agent,
        "conversation",
        raw["revision"],
        escaped(finalize(raw, "raw"), 2)
      )

    assert Record.receipt_reserve(final["execution"]) == 2

    finish =
      command(
        "finish",
        worker(final, %{
          "snapshot" => final["snapshot"],
          "progress" => final["execution"]["progress"]
        })
      )
      |> escaped(3)

    {:ok, %{record: closed}} =
      Store.transition(store, :agent, "conversation", final["revision"], finish)

    assert closed["execution"]["state"] == "completed"
    assert byte_size(Jason.encode!(closed)) <= Record.max_bytes()

    assert closed["execution"]["effects"]["effect-1"]["intent"] ==
             running["execution"]["effects"]["effect-1"]["intent"]
  end

  test "receipt cardinality reserves both raw and final confirmation before admitting dispatch",
       %{store: store} do
    base = seed(store)
    receipt = base["receipts"]["create"]

    filled = fn n ->
      %{base | "revision" => n, "receipts" => Map.new(1..n, &{"receipt-#{&1}", receipt})}
    end

    blocked = filled.(1020)
    assert :ok = Record.validate(blocked, key())

    assert {:error, :receipt_limit} =
             Transition.apply(blocked, key(), 1020, dispatch(blocked), now())

    allowed = filled.(1019)
    {:ok, %{record: running}} = Transition.apply(allowed, key(), 1019, dispatch(allowed), now())
    assert map_size(running["receipts"]) + Record.receipt_reserve(running["execution"]) == 1024
    {:ok, %{record: raw}} = Transition.apply(running, key(), 1020, raw(running), now())
    {:ok, %{record: final}} = Transition.apply(raw, key(), 1021, finalize(raw, "raw"), now())
    assert map_size(final["receipts"]) + Record.receipt_reserve(final["execution"]) == 1024

    finish =
      command(
        "finish",
        worker(final, %{
          "snapshot" => final["snapshot"],
          "progress" => final["execution"]["progress"]
        })
      )

    assert {:ok, %{record: %{"execution" => %{"state" => "completed"}}}} =
             Transition.apply(final, key(), 1022, finish, now())
  end

  defp seed(store) do
    {:ok, _} = Store.transition(store, :agent, "conversation", :absent, create())

    {:ok, %{record: r}} =
      Store.transition(store, :agent, "conversation", 1, claim(now() + 60_000))

    r
  end

  defp part(status \\ :succeeded, value \\ "raw"),
    do: %Part.ToolReturn{
      tool_name: "charge",
      tool_call_id: "call-1",
      status: status,
      content: value
    }

  defp dispatch(r),
    do: begin_effect(r) |> put_in(["payload", "intent", "payload", "phase"], "dispatch")

  defp raw(r) do
    {:ok, result} = Outcome.new(part())
    outcome(r) |> put_in(["payload", "outcome"], result)
  end

  defp finalize(r, value) do
    {:ok, result} =
      Outcome.new(
        part(:succeeded, value),
        "final",
        r["execution"]["effects"]["effect-1"]["outcome"]["data"]["raw_hash"]
      )

    command(
      "finalize_call",
      worker(r, %{
        "effect_id" => "effect-1",
        "outcome" => result,
        "snapshot" => r["snapshot"],
        "progress" => r["execution"]["progress"]
      })
    )
  end

  defp resolve(r, status) do
    {:ok, result} = Outcome.new(part(status), "final")
    intent = put_in(intent(), ["payload", "phase"], "pre_dispatch")

    command(
      "resolve_call",
      worker(r, %{
        "effect_id" => "effect-1",
        "intent" => intent,
        "outcome" => result,
        "snapshot" => r["snapshot"],
        "progress" => r["execution"]["progress"]
      })
    )
  end

  defp escaped(command, suffix),
    do: %{
      command
      | "actor_id" => String.duplicate(<<1>>, 512),
        "operation_id" => String.duplicate(<<1>>, 511) <> <<suffix>>
    }

  defp now, do: System.system_time(:millisecond)
end
