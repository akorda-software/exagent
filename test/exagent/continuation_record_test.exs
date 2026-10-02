defmodule ExAgent.ContinuationRecordTest do
  use ExUnit.Case, async: true
  alias ExAgent.Continuation.{Record, Transition}
  import ExAgent.Test.ContinuationFixtures

  test "canonical identity golden vectors are deterministic and preserve numeric representation" do
    assert {:ok, ~s({"a":[1,1.0],"z":{"b":"ñ"}})} =
             Record.canonical(%{"z" => %{"b" => "ñ"}, "a" => [1, 1.0]})

    assert Record.digest(%{"a" => 1, "b" => 2}) == Record.digest(%{"b" => 2, "a" => 1})
    refute Record.digest(%{"a" => 1}) == Record.digest(%{"a" => 1.0})
    assert {:error, _} = Record.canonical(%{:a => 1, "a" => 2})
  end

  test "canonical JSON preserves extreme numbers, escaped keys and rejects non-JSON terms" do
    huge = Integer.pow(10, 1000)

    assert Record.canonical([huge, -huge, -0.0, 1.0e-200, 1.0e200]) ==
             {:ok, Jason.encode!([huge, -huge, -0.0, 1.0e-200, 1.0e200])}

    assert {:ok, ~s({"\\n":[1,1.0],"~/":"ñ中😀"})} =
             Record.canonical(%{"~/" => "ñ中😀", "\n" => [1, 1.0]})

    for invalid <- [
          <<255>>,
          %{<<255>> => 1},
          %{1 => 1},
          :bad,
          [1 | 2],
          self(),
          make_ref(),
          %Jason.OrderedObject{values: [{"a", 1}, {"a", 2}]}
        ] do
      assert {:error, _} = Record.canonical(invalid)
    end
  end

  test "JSON normalization materializes identical escaped diagnostic pointers" do
    alias ExAgent.Tool.JSON

    assert {:error, [%{path: "/~0a~1b/0/nested~0~1", keyword: "json"}]} =
             JSON.normalize(%{"~a/b" => [%{"nested~/" => self()}]})

    assert {:error, [%{path: "/~0a~1b/0/a", keyword: "uniqueKeys"}]} =
             JSON.normalize(%{"~a/b" => [%{:a => 1, "a" => 2}]})

    assert {:error, [%{path: "/~0a~1b", keyword: "json"}]} =
             JSON.normalize(%{"~a/b" => [1 | 2]})

    assert {:error, [%{path: "/~0a~1b/0", keyword: "json"}]} =
             JSON.normalize(%{"~a/b" => [<<255>>]})

    assert {:error, [%{path: "/~0a~1b/0", keyword: "json"}]} =
             JSON.normalize(%{"~a/b" => [%{<<255>> => 1}]})

    assert JSON.pointer("/root", "~/") == "/root/~0~1"

    assert {:error, [%{path: [:unchanged], keyword: "json", message: "message"}]} =
             JSON.error([:unchanged], "json", "message")
  end

  test "codec reuses snapshot identity, legacy readers and qualified usage without reinterpretation" do
    record = ready()
    assert {:ok, bytes} = Record.encode(record, key())
    assert {:ok, ^record} = Record.decode(bytes, key())
    assert {:error, :invalid_record} = Record.decode(bytes, {"tenant-b", :agent, "conversation"})

    for version <- [1, 2] do
      legacy = record["snapshot"] |> Map.put("version", version) |> Map.delete("revision")
      assert {:ok, snapshot} = Record.snapshot(legacy, key())
      assert snapshot.revision == 0
      assert {:ok, _} = Record.encode(%{record | "snapshot" => legacy}, key())
    end

    assert record["snapshot"]["usage"]["accounting"] == snapshot()["usage"]["accounting"]
  end

  test "future, corrupt, mismatched and nonportable records fail without selecting modules" do
    record = ready()

    for bad <- [
          Map.put(record, "record_version", 99),
          put_in(record, ["snapshot", "agent_id"], "other"),
          put_in(record, ["execution", "definition"], %{"module" => "Injected"}),
          put_in(record, ["execution", "progress"], %{"callback" => fn -> :bad end}),
          put_in(record, ["execution", "progress"], %{"pid" => self()}),
          Map.put(record, "future", true)
        ] do
      assert {:error, _} = Record.encode(bad, key())
    end

    assert {:error, :invalid_record} = Record.decode("{broken", key())
    assert {:error, _} = Transition.apply(record, key(), 1, command("arbitrary", %{}), 1_001)
  end

  test "receipt binds original revision, actor, operation and payload, even after later commits" do
    original = ready()
    {:ok, result} = Transition.apply(original, key(), 1, claim(), 1_001)

    assert {:ok, %{replayed: true, record: current, receipt: receipt}} =
             Transition.apply(result.record, key(), :absent, create(), 1_002)

    assert current["revision"] == 2
    assert receipt["revision"] == 1

    for changed <- [
          Map.put(claim(), "actor_id", "other"),
          put_in(claim(), ["payload", "owner_id"], "other")
        ] do
      assert {:error, :operation_conflict} =
               Transition.apply(result.record, key(), 1, changed, 1_002)
    end

    assert {:error, :operation_conflict} =
             Transition.apply(result.record, key(), 2, claim(), 1_002)

    assert {:error, :conflict} =
             Transition.apply(result.record, key(), 1, command("recover"), 3_000)
  end

  test "deadlines/expiry count waiting; nil expiry preserves budgets across a claim" do
    record = ready()
    {:ok, %{record: current}} = Transition.apply(record, key(), 1, claim(1_000_001), 1_000_000)
    assert current["execution"]["progress"] == record["execution"]["progress"]
    expired = put_in(record, ["execution", "deadline_at"], 1_500)
    assert {:error, :expired} = Transition.apply(expired, key(), 1, claim(), 1_500)

    assert {:ok, %{record: terminal}} =
             Transition.apply(expired, key(), 1, command("expire"), 1_500)

    assert terminal["execution"]["state"] == "expired"
    assert {:error, :clock_regressed} = Transition.apply(record, key(), 1, claim(), 999)
  end

  test "lease loss before intent can recover with new fence and attempt; stale writes reject" do
    old = claimed()
    {:ok, %{record: recovered}} = Transition.apply(old, key(), 2, command("recover"), 2_000)
    assert recovered["execution"]["state"] == "ready"

    assert {:error, :attempt_reused} =
             Transition.apply(
               recovered,
               key(),
               3,
               %{claim(4_000) | "operation_id" => "reuse-attempt"},
               2_001
             )

    {:ok, %{record: fresh}} =
      Transition.apply(recovered, key(), 3, claim(4_000, "attempt-2"), 2_001)

    assert fresh["execution"]["fence"] > old["execution"]["fence"]
    assert {:error, :stale_owner} = Transition.apply(fresh, key(), 4, begin_effect(old), 2_002)
    assert {:error, :lease_expired} = Transition.apply(old, key(), 2, begin_effect(old), 2_000)
  end

  test "intent is irreversible evidence of uncertainty after crash, not permission to replay" do
    claimed = claimed()
    {:ok, %{record: running}} = Transition.apply(claimed, key(), 2, begin_effect(claimed), 1_002)
    {:ok, %{record: uncertain}} = Transition.apply(running, key(), 3, command("recover"), 2_000)
    assert uncertain["execution"]["state"] == "uncertain"

    assert {:error, :invalid_transition} =
             Transition.apply(uncertain, key(), 4, claim(4_000, "attempt-2"), 2_001)

    assert {:error, :stale_owner} = Transition.apply(uncertain, key(), 4, outcome(running), 2_001)

    assert {:error, :active_or_retained} =
             Transition.apply(uncertain, key(), 4, command("delete", %{"before" => 9_999}), 2_001)

    payload = outcome(running)["payload"] |> Map.drop(~w(owner_id attempt_id fence))

    {:ok, %{record: resolved}} =
      Transition.apply(uncertain, key(), 4, command("reconcile", payload), 2_001)

    assert resolved["execution"]["state"] == "ready"
    assert resolved["execution"]["effects"]["effect-1"]["outcome"]["status"] == "succeeded"

    {:ok, %{record: fresh}} =
      Transition.apply(resolved, key(), 5, claim(4_000, "attempt-2"), 2_002)

    assert {:error, :invalid_effect} =
             Transition.apply(
               fresh,
               key(),
               6,
               %{begin_effect(fresh) | "operation_id" => "another-effect-op"},
               2_003
             )
  end

  test "unknown outcome cannot be presented as terminal success" do
    claimed = claimed()
    {:ok, %{record: running}} = Transition.apply(claimed, key(), 2, begin_effect(claimed), 1_002)

    {:ok, %{record: uncertain}} =
      Transition.apply(running, key(), 3, outcome(running, "unknown"), 1_003)

    assert uncertain["execution"]["state"] == "uncertain"

    finish =
      command("finish", worker(running, %{"snapshot" => running["snapshot"], "progress" => %{}}))

    assert {:error, :stale_owner} = Transition.apply(uncertain, key(), 4, finish, 1_004)
  end

  test "receipt and record bounds reject without evicting active evidence" do
    record = claimed()
    receipt = record["receipts"]["create"]
    full = %{record | "receipts" => Map.new(1..1022, &{"r#{&1}", receipt})}
    assert {:error, :receipt_limit} = Transition.apply(full, key(), 2, begin_effect(full), 1_002)

    assert {:ok, %{record: recovered}} =
             Transition.apply(full, key(), 2, command("recover"), 2_000)

    assert {:ok, %{record: closed}} =
             Transition.apply(recovered, key(), 3, command("cancel"), 2_001)

    assert closed["execution"]["state"] == "cancelled"
    assert map_size(closed["receipts"]) == 1024

    huge =
      put_in(record, ["execution", "progress"], %{
        "large" => String.duplicate("x", Record.max_bytes())
      })

    assert {:error, :record_limit} = Record.encode(huge, key())
  end

  test "same conversation starts a fresh execution without resetting fences or accepting old writes" do
    old = claimed()

    finish =
      command(
        "finish",
        worker(old, %{"snapshot" => old["snapshot"], "progress" => old["execution"]["progress"]})
      )

    {:ok, %{record: terminal}} = Transition.apply(old, key(), 2, finish, 1_002)

    new_execution =
      execution() |> Map.put("continuation_id", "continuation-2") |> Map.put("run_id", "run-2")

    assert {:error, :invalid_start} =
             Transition.apply(
               terminal,
               key(),
               3,
               command("start", %{"execution" => execution()}),
               1_003
             )

    {:ok, %{record: started}} =
      Transition.apply(
        terminal,
        key(),
        3,
        command("start", %{"execution" => new_execution}),
        1_003
      )

    assert started["execution"]["fence"] > old["execution"]["fence"]
    assert started["receipts"]["finish"]["state"] == "completed"
    assert started["receipts"]["finish"]["run_id"] == "run-1"

    {:ok, %{record: current}} =
      Transition.apply(started, key(), 4, claim(3_000, "attempt-2"), 1_004)

    assert {:error, :stale_owner} = Transition.apply(current, key(), 5, begin_effect(old), 1_005)

    assert {:ok, %{replayed: true, receipt: %{"revision" => 3}, record: ^current}} =
             Transition.apply(current, key(), 2, finish, 1_005)

    assert {:error, :record_mismatch} =
             Transition.apply(
               current,
               key(),
               5,
               %{begin_effect(current) | "record_id" => "deleted-lifetime"},
               1_005
             )
  end

  test "encoded byte budget reserves a minimal administrative close" do
    record = put_in(ready(), ["execution", "progress"], %{"blob" => ""})
    base_size = byte_size(Jason.encode!(record))

    record =
      put_in(
        record,
        ["execution", "progress", "blob"],
        String.duplicate(
          "x",
          Record.max_bytes() - base_size - Record.cleanup_reserve_bytes(record)
        )
      )

    assert {:ok, _} = Record.encode(record, key())

    cancel =
      command("cancel")
      |> Map.put("operation_id", String.duplicate("o", 512))
      |> Map.put("actor_id", String.duplicate("a", 512))

    assert {:ok, %{record: closed}} = Transition.apply(record, key(), 1, cancel, 1_001)
    assert closed["execution"]["state"] == "cancelled"
    assert closed["snapshot"] == record["snapshot"]
  end

  test "cancel with an in-flight marker fences the owner and remains uncertain" do
    claimed = claimed()
    {:ok, %{record: running}} = Transition.apply(claimed, key(), 2, begin_effect(claimed), 1_002)
    {:ok, %{record: cancelled}} = Transition.apply(running, key(), 3, command("cancel"), 1_003)
    assert cancelled["execution"]["state"] == "uncertain"
    assert cancelled["execution"]["fence"] > running["execution"]["fence"]
    assert {:error, :stale_owner} = Transition.apply(cancelled, key(), 4, outcome(running), 1_004)
  end

  test "inconsistent state, duplicate JSON object keys and snapshot rollback reject" do
    claimed = claimed()
    {:ok, %{record: running}} = Transition.apply(claimed, key(), 2, begin_effect(claimed), 1_002)

    forged =
      running
      |> put_in(["execution", "state"], "ready")
      |> put_in(["execution", "owner_id"], nil)
      |> put_in(["execution", "attempt_id"], nil)
      |> put_in(["execution", "lease_until"], nil)

    assert {:error, :invalid_record} = Record.encode(forged, key())
    {:ok, json} = Record.encode(claimed, key())

    duplicate =
      String.replace(json, "\"record_version\":1", "\"record_version\":99,\"record_version\":1")

    assert {:error, :invalid_record} = Record.decode(duplicate, key())

    rollback =
      command(
        "checkpoint",
        worker(claimed, %{
          "snapshot" => Map.put(claimed["snapshot"], "revision", 0),
          "progress" => claimed["execution"]["progress"]
        })
      )

    assert {:error, :snapshot_revision_regressed} =
             Transition.apply(claimed, key(), 2, rollback, 1_002)
  end
end
