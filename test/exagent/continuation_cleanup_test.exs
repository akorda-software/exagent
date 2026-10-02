defmodule ExAgent.ContinuationCleanupTest do
  use ExUnit.Case, async: false
  alias ExAgent.Store
  alias ExAgent.Continuation.{Record, Transition}
  import ExAgent.Test.ContinuationFixtures

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "tenant-a")}
  end

  test "public create exact reserved cap/+1 and minimal cancel preserve ASCII and escaped IDs", %{
    store: store
  } do
    for {id, text} <- [{"ascii", String.duplicate("a", 512)}, {"escaped", escaped()}] do
      cmd =
        create(id)
        |> put_in(["payload", "execution", "continuation_id"], text)
        |> put_in(["payload", "execution", "run_id"], text)
        |> put_in(["payload", "execution", "progress"], %{"blob" => ""})

      cmd = fill(nil, id, cmd, ["payload", "execution", "progress", "blob"])
      too_large = update_in(cmd, ["payload", "execution", "progress", "blob"], &(&1 <> "x"))
      assert {:error, :record_limit} = Store.transition(store, :agent, id, :absent, too_large)
      assert {:error, :not_found} = Store.load_record(store, :agent, id)
      ready = commit(store, id, nil, cmd)
      assert_at_cap(ready)
      closed = commit(store, id, ready, cleanup("cancel", %{}, 1))
      assert closed["execution"]["state"] == "cancelled"
      assert closed["execution"]["continuation_id"] == text
      assert closed["execution"]["run_id"] == text
      assert closed["execution"]["progress"] == ready["execution"]["progress"]
      assert closed["snapshot"] == ready["snapshot"]
      assert map_size(closed["receipts"]) == 2
      assert_bounded(closed)
    end
  end

  test "claimed boundary preserves escaped owners and admits finish, cancel, or recover then cancel",
       %{
         store: store
       } do
    for operation <- ~w(finish cancel recover) do
      id = operation
      ready = commit(store, id, nil, create(id))

      cmd =
        claim(now() + 2_000, escaped())
        |> Map.put("operation_id", "claim")
        |> put_in(["payload", "owner_id"], escaped())

      claimed = commit(store, id, ready, cmd)

      checkpoint =
        command(
          "checkpoint",
          worker(claimed, %{"snapshot" => claimed["snapshot"], "progress" => %{"blob" => ""}})
        )
        |> then(&fill(claimed, id, &1, ["payload", "progress", "blob"]))

      too_large = update_in(checkpoint, ["payload", "progress", "blob"], &(&1 <> "x"))

      assert {:error, :record_limit} =
               Store.transition(store, :agent, id, claimed["revision"], too_large)

      assert {:ok, ^claimed} = Store.load_record(store, :agent, id)
      full = commit(store, id, claimed, checkpoint)
      assert_at_cap(full)
      assert full["execution"]["owner_id"] == escaped()
      assert full["execution"]["attempt_id"] == escaped()
      assert Record.receipt_reserve(full["execution"]) == 2

      payload =
        if operation == "finish",
          do:
            worker(full, %{
              "snapshot" => full["snapshot"],
              "progress" => full["execution"]["progress"]
            }),
          else: %{}

      if operation == "recover", do: wait_until(full["execution"]["lease_until"])
      cleaned = commit(store, id, full, cleanup(operation, payload, 1))

      closed =
        if operation == "recover" do
          assert cleaned["execution"]["state"] == "ready"
          commit(store, id, cleaned, cleanup("cancel", %{}, 2))
        else
          cleaned
        end

      assert closed["execution"]["state"] in ~w(completed cancelled)
      assert closed["execution"]["owner_id"] == nil
      assert closed["execution"]["progress"] == full["execution"]["progress"]
      assert_bounded(closed)
    end
  end

  test "ready expiry at encoded cap consumes reserved cleanup", %{store: store} do
    id = "expiry"

    cmd =
      create(id)
      |> put_in(["payload", "execution", "deadline_at"], now() + 2_000)
      |> put_in(["payload", "execution", "progress"], %{"blob" => ""})
      |> then(&fill(nil, id, &1, ["payload", "execution", "progress", "blob"]))

    full = commit(store, id, nil, cmd)
    assert_at_cap(full)
    wait_until(full["execution"]["deadline_at"])
    closed = commit(store, id, full, cleanup("expire", %{}, 1))
    assert closed["execution"]["state"] == "expired"
    assert_bounded(closed)
  end

  test "full running records retain intents through cancel/recover, reconciliation and close", %{
    store: store
  } do
    for operation <- ~w(cancel recover outcome) do
      id = "effects-#{operation}"

      cmd =
        create(id)
        |> put_in(["payload", "execution", "continuation_id"], escaped())
        |> put_in(["payload", "execution", "run_id"], escaped())

      ready = commit(store, id, nil, cmd)

      claimed =
        commit(
          store,
          id,
          ready,
          Map.put(claim(now() + 2_000, escaped()), "operation_id", "claim")
        )

      first = commit(store, id, claimed, begin_effect(claimed))

      begin_second =
        begin_effect(first)
        |> Map.put("operation_id", "second")
        |> put_in(["payload", "effect_id"], "effect-2")
        |> put_in(["payload", "intent", "payload"], %{"blob" => ""})
        |> then(&fill(first, id, &1, ["payload", "intent", "payload", "blob"]))

      too_large = update_in(begin_second, ["payload", "intent", "payload", "blob"], &(&1 <> "x"))

      assert {:error, :record_limit} =
               Store.transition(store, :agent, id, first["revision"], too_large)

      assert {:ok, ^first} = Store.load_record(store, :agent, id)
      full = commit(store, id, first, begin_second)
      assert_at_cap(full)
      assert Record.receipt_reserve(full["execution"]) == 4

      payload =
        if operation == "outcome" do
          outcome(full, "unknown")["payload"] |> put_in(["outcome", "data"], nil)
        else
          %{}
        end

      if operation == "recover", do: wait_until(full["execution"]["lease_until"])
      uncertain = commit(store, id, full, cleanup(operation, payload, 1))
      assert uncertain["execution"]["state"] == "uncertain"
      assert Record.receipt_reserve(uncertain["execution"]) == 3

      assert {:error, :stale_owner} =
               Store.transition(store, :agent, id, uncertain["revision"], outcome(full))

      assert {:ok, ^uncertain} = Store.load_record(store, :agent, id)

      resolved =
        Enum.reduce(1..2, uncertain, fn index, current ->
          payload = %{
            "effect_id" => "effect-#{index}",
            "outcome" => %{"status" => "validation_error", "data" => nil},
            "snapshot" => current["snapshot"],
            "progress" => current["execution"]["progress"]
          }

          commit(store, id, current, cleanup("reconcile", payload, index + 1))
        end)

      assert resolved["execution"]["state"] == "ready"
      closed = commit(store, id, resolved, cleanup("cancel", %{}, 4))
      assert closed["execution"]["state"] == "cancelled"
      assert map_size(closed["receipts"]) == map_size(full["receipts"]) + 4

      for effect <- ~w(effect-1 effect-2) do
        assert closed["execution"]["effects"][effect]["intent"] ==
                 full["execution"]["effects"][effect]["intent"]
      end

      assert_bounded(closed)
    end
  end

  @tag timeout: 120_000
  test "receipt cardinality admission leaves recover and cancel slots without eviction", %{
    store: store
  } do
    id = "receipts"
    ready = commit(store, id, nil, create(id))
    claimed = commit(store, id, ready, claim(now() + 60_000))

    full =
      Enum.reduce(3..1022, claimed, fn index, current ->
        payload =
          worker(current, %{
            "snapshot" => current["snapshot"],
            "progress" => current["execution"]["progress"]
          })

        commit(store, id, current, command("checkpoint", payload, "checkpoint-#{index}"))
      end)

    payload =
      worker(full, %{"snapshot" => full["snapshot"], "progress" => full["execution"]["progress"]})

    assert {:error, :receipt_limit} =
             Store.transition(
               store,
               :agent,
               id,
               full["revision"],
               command("checkpoint", payload, "overflow")
             )

    assert {:ok, ^full} = Store.load_record(store, :agent, id)
    wait_until(full["execution"]["lease_until"])
    recovered = commit(store, id, full, command("recover"))
    closed = commit(store, id, recovered, command("cancel"))
    assert map_size(closed["receipts"]) == 1024
    assert Map.take(closed["receipts"], Map.keys(full["receipts"])) == full["receipts"]
    assert_bounded(closed)
  end

  test "supported UTC domain is finite and rejects invalid future values without writes", %{
    store: store
  } do
    max_time = 9_223_372_036_854_775_807
    assert Record.timestamp?(0)
    assert Record.timestamp?(max_time)
    refute Record.timestamp?(-1)
    refute Record.timestamp?(max_time + 1)

    for field <- ~w(deadline_at expires_at) do
      cmd = put_in(create(field), ["payload", "execution", field], max_time + 1)
      assert {:error, :invalid_execution} = Store.transition(store, :agent, field, :absent, cmd)
      assert {:error, :not_found} = Store.load_record(store, :agent, field)
    end

    cmd =
      create("clock")
      |> put_in(["payload", "execution", "deadline_at"], max_time)
      |> put_in(["payload", "execution", "expires_at"], max_time)

    ready = commit(store, "clock", nil, cmd)

    assert {:error, :invalid_command} =
             Store.transition(store, :agent, "clock", ready["revision"], claim(max_time + 1))

    assert {:ok, ^ready} = Store.load_record(store, :agent, "clock")
    claimed = commit(store, "clock", ready, claim(max_time))
    assert claimed["execution"]["lease_until"] == max_time

    assert {:error, :invalid_time} =
             Transition.apply(
               claimed,
               {"tenant-a", :agent, "clock"},
               claimed["revision"],
               command("cancel"),
               max_time + 1
             )

    assert {:ok, ^claimed} = Store.load_record(store, :agent, "clock")
  end

  test "reserve survives maximum supported UTC and revision/fence digit rollover" do
    record =
      ready()
      |> Map.put("revision", 99)
      |> put_in(["execution", "fence"], 99)
      |> put_in(["execution", "progress"], %{"blob" => ""})

    room =
      Record.max_bytes() - byte_size(Jason.encode!(record)) - Record.cleanup_reserve_bytes(record)

    full = put_in(record, ["execution", "progress", "blob"], String.duplicate("x", room))
    assert {:ok, _} = Record.encode(full, key())

    assert {:ok, %{record: closed}} =
             Transition.apply(
               full,
               key(),
               99,
               cleanup("cancel", %{}, 1),
               9_223_372_036_854_775_807
             )

    assert closed["revision"] == 100
    assert closed["execution"]["fence"] == 100
    assert_bounded(closed)
  end

  test "terminal encoded max is exact and max plus one leaves the claimed record intact", %{
    store: store
  } do
    id = "terminal-cap"
    ready = commit(store, id, nil, create(id))
    claimed = commit(store, id, ready, claim(now() + 60_000))

    cmd =
      command(
        "finish",
        worker(claimed, %{"snapshot" => claimed["snapshot"], "progress" => %{"blob" => ""}})
      )
      |> then(&fill(claimed, id, &1, ["payload", "progress", "blob"]))

    too_large = update_in(cmd, ["payload", "progress", "blob"], &(&1 <> "x"))

    assert {:error, :record_limit} =
             Store.transition(store, :agent, id, claimed["revision"], too_large)

    assert {:ok, ^claimed} = Store.load_record(store, :agent, id)
    closed = commit(store, id, claimed, cmd)
    assert byte_size(Jason.encode!(closed)) == Record.max_bytes()
    assert Record.cleanup_reserve_bytes(closed) == 0
    assert closed["execution"]["state"] == "completed"
  end

  test "minimal known outcome and finish fit without shrinking admitted intent or progress", %{
    store: store
  } do
    id = "known-outcome"
    ready = commit(store, id, nil, create(id))
    claimed = commit(store, id, ready, claim(now() + 60_000))

    cmd =
      begin_effect(claimed)
      |> put_in(["payload", "intent", "payload"], %{"blob" => ""})
      |> then(&fill(claimed, id, &1, ["payload", "intent", "payload", "blob"]))

    full = commit(store, id, claimed, cmd)
    assert_at_cap(full)
    payload = outcome(full, "validation_error")["payload"] |> put_in(["outcome", "data"], nil)
    resolved = commit(store, id, full, cleanup("outcome", payload, 1))
    assert resolved["execution"]["state"] == "claimed"

    payload =
      worker(resolved, %{
        "snapshot" => resolved["snapshot"],
        "progress" => resolved["execution"]["progress"]
      })

    closed = commit(store, id, resolved, cleanup("finish", payload, 2))
    assert closed["execution"]["state"] == "completed"

    assert closed["execution"]["effects"]["effect-1"]["intent"] ==
             full["execution"]["effects"]["effect-1"]["intent"]

    assert_bounded(closed)
  end

  defp fill(current, id, cmd, path) do
    expected = if current, do: current["revision"], else: :absent

    {:ok, %{record: sample}} =
      Transition.apply(current, {"tenant-a", :agent, id}, expected, cmd, now())

    room =
      Record.max_bytes() - byte_size(Jason.encode!(sample)) - Record.cleanup_reserve_bytes(sample)

    put_in(cmd, path, String.duplicate("x", room))
  end

  defp commit(store, id, current, cmd) do
    expected = if current, do: current["revision"], else: :absent
    assert {:ok, %{record: record}} = Store.transition(store, :agent, id, expected, cmd)
    assert_bounded(record)
    record
  end

  defp assert_at_cap(record) do
    assert byte_size(Jason.encode!(record)) + Record.cleanup_reserve_bytes(record) ==
             Record.max_bytes()
  end

  defp assert_bounded(record) do
    assert byte_size(Jason.encode!(record)) <= Record.max_bytes()
    assert map_size(record["receipts"]) + Record.receipt_reserve(record["execution"]) <= 1024
  end

  defp cleanup(operation, payload, index) do
    command(operation, payload, String.duplicate(<<1>>, 511) <> <<index>>)
    |> Map.put("actor_id", escaped())
  end

  defp escaped, do: String.duplicate(<<1>>, 512)
  defp now, do: System.system_time(:millisecond)

  defp wait_until(time) do
    receive do
    after
      max(0, time - now()) -> :ok
    end
  end
end
