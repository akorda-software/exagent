defmodule ExAgent.ContinuationApprovalTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, Store}
  alias ExAgent.Continuation.{Approval, Record, Transition}
  import ExAgent.Test.ContinuationFixtures

  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record({table, _}, key), do: Store.ETS.load_record(table, key)

    def scan_records({table, _}, namespace, query),
      do: Store.ETS.scan_records(table, namespace, query)

    def transition({table, fault}, key, revision, command) do
      case Agent.get_and_update(fault, &{&1, :ok}) do
        :before ->
          {:error, :save_failed}

        :after ->
          {:ok, _} = Store.ETS.transition(table, key, revision, command)
          {:error, :ack_lost}

        :ok ->
          Store.ETS.transition(table, key, revision, command)
      end
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "tenant-a")}
  end

  test "approval binds logical effective args, schema, definition and revision without code" do
    a = approval(3)
    assert Approval.valid?(a)
    assert {:ok, decoded} = Jason.decode(Jason.encode!(a))
    assert decoded == a

    for path <- [
          ["args", "amount"],
          ["definition", "version"],
          ["policy", "version"],
          ["schema_hash"],
          ["call_id"],
          ["requested_revision"]
        ] do
      refute Approval.valid?(put_in(a, path, "changed"))
    end

    refute Approval.valid?(Map.put(a, "module", "Elixir.Evil"))
    assert {:error, :invalid_approval} = Approval.new(%{"args" => fn -> :bad end})
  end

  test "pause releases ownership only at a resolved frontier and cannot be claimed", %{
    store: store
  } do
    r = store_claimed(store)
    p = pause(r)

    assert {:ok, %{record: pending}} =
             Store.transition(store, :agent, "conversation", r["revision"], p)

    assert pending["execution"]["state"] == "pending"
    assert pending["execution"]["owner_id"] == nil
    assert pending["execution"]["fence"] > r["execution"]["fence"]
    assert {:ok, %{status: :pending, record: ^pending}} = Continuation.get(store, "conversation")

    assert {:error, :invalid_transition} =
             Store.transition(store, :agent, "conversation", 3, claim(now() + 60_000, "new"))

    assert {:error, :stale_owner} =
             Store.transition(store, :agent, "conversation", 3, begin_effect(r))
  end

  test "running intent cannot become a paused success" do
    r = claimed()
    {:ok, %{record: r}} = Transition.apply(r, key(), 2, begin_effect(r), 1_002)
    assert {:error, :execution_uncertain} = Transition.apply(r, key(), 3, pause(r), 1_003)
  end

  test "host actor authorization is mandatory, fail closed and never persisted", %{store: store} do
    r = store_pending(store)
    opts = options(r)

    for changed <- [
          Keyword.delete(opts, :authorize),
          Keyword.put(opts, :authorize, fn _, _, _ -> :approve end),
          Keyword.put(opts, :authorize, fn _, _, _ -> raise "private actor context" end),
          Keyword.put(opts, :actor, :model_text)
        ] do
      assert {:error, :unauthorized} =
               Continuation.decide(store, "conversation", :approve, changed)

      assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    end

    assert {:ok, %{record: approved}} = Continuation.decide(store, "conversation", :approve, opts)

    assert approved["execution"]["progress"]["approvals"]["approval-1"]["decision"]["actor_id"] ==
             "human-1"

    refute Jason.encode!(approved) =~ "private_context"
    assert {:ok, %{status: :approved}} = Continuation.get(store, "conversation")
  end

  test "exact receipt retry is idempotent, opposite/actor/payload/stale operation conflicts", %{
    store: store
  } do
    r = store_pending(store)
    opts = options(r)

    assert {:ok, %{record: approved, replayed: false}} =
             Continuation.decide(store, "conversation", :approve, opts)

    assert {:ok, %{record: ^approved, replayed: true}} =
             Continuation.decide(store, "conversation", :approve, opts)

    assert {:error, :operation_conflict} = Continuation.decide(store, "conversation", :deny, opts)

    assert {:error, :operation_conflict} =
             Continuation.decide(
               store,
               "conversation",
               :approve,
               Keyword.put(opts, :authorize, fn _, _, _ -> {:ok, "another-human"} end)
             )

    assert {:error, :operation_conflict} =
             Continuation.decide(
               store,
               "conversation",
               :approve,
               Keyword.put(opts, :payload_hash, String.duplicate("f", 64))
             )

    assert {:error, :conflict} =
             Continuation.decide(
               store,
               "conversation",
               :approve,
               Keyword.put(opts, :operation_id, "new-operation")
             )
  end

  test "competing approve and deny both authorize at a barrier but only one commits", %{
    store: store
  } do
    r = store_pending(store)
    owner = self()

    tasks =
      for decision <- [:approve, :deny] do
        Task.async(fn ->
          opts =
            options(r)
            |> Keyword.put(:operation_id, Atom.to_string(decision))
            |> Keyword.put(:authorize, fn _, _, _ ->
              send(owner, {:authorized, self()})

              receive do
                :go -> {:ok, "human-1"}
              end
            end)

          Continuation.decide(store, "conversation", decision, opts)
        end)
      end

    assert_receive {:authorized, a}
    assert_receive {:authorized, b}
    send(a, :go)
    send(b, :go)
    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 1
  end

  test "multiple approvals require all and prior decisions cannot be rewritten in a later pause" do
    r = claimed()
    cmd = pause(r, 2)
    {:ok, %{record: pending}} = Transition.apply(r, key(), 2, cmd, 1_002)

    {:ok, %{record: first}} =
      Transition.apply(pending, key(), 3, decide_cmd(pending, "approval-1"), 1_003)

    assert first["execution"]["state"] == "pending"

    assert {:error, :decision_conflict} =
             Transition.apply(
               first,
               key(),
               4,
               decide_cmd(first, "approval-1")
               |> Map.put("operation_id", "opposite")
               |> put_in(["payload", "decision"], "deny"),
               1_004
             )

    {:ok, %{record: ready}} =
      Transition.apply(first, key(), 4, decide_cmd(first, "approval-2"), 1_004)

    assert ready["execution"]["state"] == "ready"
    {:ok, %{record: next}} = Transition.apply(ready, key(), 5, claim(2_000, "attempt-2"), 1_005)

    assert {:error, :invalid_pause} =
             Transition.apply(
               next,
               key(),
               6,
               Map.put(pause(next), "operation_id", "pause-2"),
               1_006
             )
  end

  test "deny/cancel terminate; nil expiry stays pending, deadline expires in Store clock" do
    for decision <- ["deny", "cancel", "expire"] do
      r = claimed()
      r = if decision == "expire", do: put_in(r, ["execution", "expires_at"], 1_010), else: r
      {:ok, %{record: pending}} = Transition.apply(r, key(), 2, pause(r), 1_002)

      cmd =
        if decision == "deny",
          do: put_in(decide_cmd(pending, "approval-1"), ["payload", "decision"], "deny"),
          else: command(decision)

      {:ok, %{record: closed}} = Transition.apply(pending, key(), 3, cmd, 1_010)

      assert closed["execution"]["state"] ==
               %{"deny" => "denied", "cancel" => "cancelled", "expire" => "expired"}[decision]

      assert Record.receipt_reserve(closed["execution"]) == 0
    end

    r = claimed()
    {:ok, %{record: pending}} = Transition.apply(r, key(), 2, pause(r), 1_002)

    assert {:error, :invalid_transition} =
             Transition.apply(pending, key(), 3, command("expire"), 999_999)

    expired = put_in(pending, ["execution", "deadline_at"], 1_003)

    assert {:error, :expired} =
             Transition.apply(expired, key(), 3, decide_cmd(expired, "approval-1"), 1_003)
  end

  @tag timeout: 120_000
  test "pending exact encoded cap/+1 reserves decisions with escaped actor and final cancel", %{
    store: store
  } do
    r = store_claimed(store)
    cmd = pause(r, 2) |> put_in(["payload", "progress", "blob"], "")
    {:ok, %{record: sample}} = Transition.apply(r, key(), 2, cmd, now())

    room =
      Record.max_bytes() - byte_size(Jason.encode!(sample)) - Record.cleanup_reserve_bytes(sample)

    cmd = put_in(cmd, ["payload", "progress", "blob"], String.duplicate("x", room))
    too_large = update_in(cmd, ["payload", "progress", "blob"], &(&1 <> "x"))
    assert {:error, :record_limit} = Store.transition(store, :agent, "conversation", 2, too_large)
    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    {:ok, %{record: pending}} = Store.transition(store, :agent, "conversation", 2, cmd)

    assert byte_size(Jason.encode!(pending)) + Record.cleanup_reserve_bytes(pending) ==
             Record.max_bytes()

    assert Record.receipt_reserve(pending["execution"]) == 3

    final =
      Enum.reduce(1..2, pending, fn index, current ->
        opts =
          options(current, "approval-#{index}")
          |> Keyword.put(:operation_id, String.duplicate(<<1>>, 511) <> <<index>>)
          |> Keyword.put(:authorize, fn _, _, _ -> {:ok, String.duplicate(<<1>>, 512)} end)

        assert {:ok, %{record: updated}} =
                 Continuation.decide(store, "conversation", :approve, opts)

        updated
      end)

    assert final["execution"]["state"] == "ready"

    opts =
      options(final)
      |> Keyword.put(:operation_id, String.duplicate(<<1>>, 511) <> <<3>>)
      |> Keyword.put(:authorize, fn _, _, _ -> {:ok, String.duplicate(<<1>>, 512)} end)

    assert {:ok, %{record: closed}} = Continuation.decide(store, "conversation", :cancel, opts)
    assert closed["execution"]["state"] == "cancelled"
    assert byte_size(Jason.encode!(closed)) <= Record.max_bytes()
    assert closed["execution"]["progress"]["blob"] == pending["execution"]["progress"]["blob"]
  end

  test "receipt cardinality counts remaining decisions plus closure before accepting pause" do
    r = claimed()
    receipt = r["receipts"]["create"]
    receipts = Map.new(1..1022, &{"receipt-#{&1}", receipt})
    r = %{r | "revision" => 1022, "receipts" => receipts}
    assert :ok = Record.validate(r, key())
    assert {:error, :receipt_limit} = Transition.apply(r, key(), 1022, pause(r), 1_002)
    r = %{r | "revision" => 1021, "receipts" => Map.delete(receipts, "receipt-1022")}
    assert {:ok, %{record: pending}} = Transition.apply(r, key(), 1021, pause(r), 1_002)
    assert map_size(pending["receipts"]) + Record.receipt_reserve(pending["execution"]) == 1024
  end

  test "decision save failure before commit and lost ACK retry only the exact transition", %{
    store: store
  } do
    r = store_pending(store)
    {:ok, fault} = Agent.start_link(fn -> :before end)
    faulty = Store.scoped({FaultStore, {__MODULE__, fault}}, "tenant-a")
    opts = options(r)
    assert {:error, :save_failed} = Continuation.decide(faulty, "conversation", :approve, opts)
    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    Agent.update(fault, fn _ -> :after end)
    assert {:error, :ack_lost} = Continuation.decide(faulty, "conversation", :approve, opts)
    assert {:ok, committed} = Store.load_record(store, :agent, "conversation")
    assert committed["revision"] == r["revision"] + 1

    assert {:ok, %{record: ^committed, replayed: true}} =
             Continuation.decide(faulty, "conversation", :approve, opts)

    Agent.stop(fault)
  end

  test "checkpoint cannot inject, discard or alter approvals outside their transitions" do
    r = claimed()
    payload = worker(r, %{"snapshot" => r["snapshot"], "progress" => %{"approvals" => "invalid"}})

    assert {:error, :approval_regressed} =
             Transition.apply(r, key(), 2, command("checkpoint", payload), 1_002)

    {:ok, %{record: pending}} = Transition.apply(r, key(), 2, pause(r), 1_002)

    {:ok, %{record: ready}} =
      Transition.apply(pending, key(), 3, decide_cmd(pending, "approval-1"), 1_003)

    {:ok, %{record: active}} = Transition.apply(ready, key(), 4, claim(2_000, "attempt-2"), 1_004)
    payload = worker(active, %{"snapshot" => active["snapshot"], "progress" => %{}})

    assert {:error, :approval_regressed} =
             Transition.apply(active, key(), 5, command("checkpoint", payload), 1_005)

    injected =
      put_in(create(), ["payload", "execution", "progress"], ready["execution"]["progress"])

    assert {:error, :invalid_execution} = Transition.apply(nil, key(), :absent, injected, 1_006)
  end

  defp approval(revision, id \\ "approval-1") do
    {:ok, a} =
      Approval.new(%{
        "id" => id,
        "run_id" => "run-1",
        "call_id" => "call-#{id}",
        "tool_name" => "charge",
        "args" => %{"amount" => 3},
        "schema_hash" => String.duplicate("a", 64),
        "definition" => %{"id" => "agent", "version" => "1"},
        "policy" => %{"id" => "policy", "version" => "1"},
        "requested_revision" => revision
      })

    a
  end

  defp pause(r, count \\ 1) do
    approvals =
      Map.new(1..count, fn index ->
        id = "approval-#{index}"
        {id, approval(r["revision"] + 1, id)}
      end)

    progress = Map.put(r["execution"]["progress"], "approvals", approvals)
    command("pause", worker(r, %{"snapshot" => r["snapshot"], "progress" => progress}))
  end

  defp decide_cmd(r, id),
    do:
      command(
        "decide",
        %{
          "approval_id" => id,
          "payload_hash" => r["execution"]["progress"]["approvals"][id]["payload_hash"],
          "decision" => "approve"
        },
        "decide-#{id}"
      )

  defp options(r, id \\ "approval-1"),
    do: [
      record_id: r["record_id"],
      revision: r["revision"],
      operation_id: "decision-#{id}",
      approval_id: id,
      payload_hash: r["execution"]["progress"]["approvals"][id]["payload_hash"],
      actor: %{private_context: true},
      authorize: fn actor, _, _ ->
        if actor == %{private_context: true}, do: {:ok, "human-1"}, else: :deny
      end
    ]

  defp store_claimed(store) do
    {:ok, _} = Store.transition(store, :agent, "conversation", :absent, create())

    {:ok, %{record: r}} =
      Store.transition(store, :agent, "conversation", 1, claim(now() + 60_000))

    r
  end

  defp store_pending(store) do
    r = store_claimed(store)
    {:ok, %{record: r}} = Store.transition(store, :agent, "conversation", 2, pause(r))
    r
  end

  defp now, do: System.system_time(:millisecond)
end
