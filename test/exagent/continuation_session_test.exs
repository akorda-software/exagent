defmodule ExAgent.ContinuationSessionTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Permissions, Server, Session, Store, Tool}
  alias ExAgent.Message.{Part, Response}
  alias ExAgent.Session.Participant

  defmodule SessionFaultStore do
    def load_session_snapshot({table, _}, id), do: Store.ETS.load_session_snapshot(table, id)

    def save_session_snapshot({table, fault}, snapshot) do
      case Agent.get_and_update(fault, &{&1, :ok}) do
        :before ->
          {:error, :save_failed}

        :after ->
          :ok = Store.ETS.save_session_snapshot(table, snapshot)
          {:error, :ack_lost}

        :ok ->
          Store.ETS.save_session_snapshot(table, snapshot)
      end
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    store = {Store.ETS, __MODULE__}
    owner = self()

    model = %ExAgent.Models.Test{
      script: [
        %Response{parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}]},
        %Response{parts: [%Part.Text{content: "done"}]},
        %Response{parts: [%Part.Text{content: "next"}]}
      ]
    }

    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :effect)
          {:ok, "saved"}
        end
      )

    config = %{
      durability: :ephemeral,
      lease_ms: 60_000,
      expires_at: nil,
      definition: %{"id" => "agent", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      model_ref: %{"id" => "model", "version" => "1"},
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, %{"index" => i} -> {:ok, %{m | index: i}} end
      }
    }

    server =
      start_supervised!(
        {Server,
         agent: ExAgent.new(model: model, tools: [tool]),
         agent_id: "agent",
         namespace: "session-c7",
         store: store,
         continuation: config}
      )

    opts = [
      session_id: "session",
      namespace: "session-c7",
      store: store,
      participants: [Participant.new(id: "worker", kind: :agent, ref: :opaque_host_handle)],
      shared_state: %{"count" => 0},
      continuations: %{"worker" => %{store: Store.scoped(store, "session-c7"), id: "agent"}}
    ]

    %{server: server, opts: opts, store: Store.scoped(store, "session-c7")}
  end

  defp approve(server) do
    {:ok, %{record: record}} = Server.continuation(server)
    [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    assert {:ok, _} =
             Server.decide(server, :approve,
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "approve",
               approval_id: id,
               payload_hash: approval["payload_hash"],
               actor: :host,
               authorize: fn :host, :approve, _ -> {:ok, "human"} end
             )

    assert {:ok, %{status: :succeeded}} =
             Server.resume(server,
               permissions: Permissions.new!(default: :ask)
             )
  end

  defp reject_new_run(session) do
    Session.take_turn(session, "worker", fn _ ->
      ExAgent.run(ExAgent.new(model: "test"), "invalid continuation",
        continuation: %{expires_at: nil}
      )
    end)
  end

  test "leave retains a consumed binding while its row exists and detaches only after explicit terminal deletion",
       ctx do
    {:ok, session} = Session.start_link(ctx.opts)
    {:ok, "worker"} = Session.start(session)
    {:ok, _} = Server.chat(ctx.server, "go")
    assert_receive :effect
    {:ok, %{reference: ref}} = Session.continuation(session, "worker")
    {:ok, _, _} = Session.complete_turn(session, "worker", ref, fn _ -> %{"count" => 1} end)
    assert {:error, :continuation_binding_retained} = Session.leave(session, "worker")
    assert [%Participant{id: "worker"}] = Session.participants(session)
    GenServer.stop(session)
    {:ok, restored} = Session.start_link(ctx.opts)
    assert Session.read_state(restored) == %{"count" => 1}

    assert {:error, :invalid_session_continuation_reference} =
             Session.complete_turn(restored, "worker", ref, fn _ ->
               flunk("still-current consumed run replayed")
             end)

    assert {:ok, %{results: [{_, {:ok, _}}]}} =
             ExAgent.Continuation.prune_page(
               ctx.store,
               System.system_time(:millisecond) + 1_000,
               "operator"
             )

    assert {:error, :not_found} = Server.continuation(ctx.server)
    assert :ok = Session.leave(restored, "worker")
    assert Session.participants(restored) == []
    {:ok, snapshot} = Store.load_session_snapshot(ctx.store, "session")
    assert snapshot.continuations == []
    GenServer.stop(restored)

    {:ok, empty} =
      Session.start_link(
        ctx.opts
        |> Keyword.put(:participants, [])
        |> Keyword.put(:continuations, %{})
      )

    assert Session.read_state(empty) == %{"count" => 1}
    assert Session.participants(empty) == []
    refute_receive :effect
    GenServer.stop(empty)
  end

  test "new local failure stays blocked across old-terminal refresh and restart; stale witness cannot clear a newer failure",
       ctx do
    {:ok, session} = Session.start_link(ctx.opts)
    {:ok, "worker"} = Session.start(session)
    {:ok, _} = Server.chat(ctx.server, "go")
    assert_receive :effect
    {:ok, %{reference: ref}} = Session.continuation(session, "worker")

    {:ok, %{"count" => 1}, "worker"} =
      Session.complete_turn(session, "worker", ref, fn _ -> %{"count" => 1} end)

    assert {:error, {:session_continuation_pending, "worker", "result_not_final"}} =
             reject_new_run(session)

    assert {:error, {:session_continuation_pending, "worker", "result_not_final"}} =
             Session.end_turn(session, "worker")

    {:ok, %{witness: witness_a}} = Session.continuation(session, "worker")
    assert is_map(witness_a)
    assert :ok = Session.reconcile_turn(session, "worker", witness_a)
    assert Session.read_state(session) == %{"count" => 1}
    assert Session.current(session) == "worker"

    assert {:error, :invalid_session_continuation_reference} =
             Session.complete_turn(session, "worker", ref, fn _ -> flunk("consumed callback") end)

    assert {:error, {:session_continuation_pending, "worker", "result_not_final"}} =
             reject_new_run(session)

    {:ok, %{witness: witness_b}} = Session.continuation(session, "worker")
    assert witness_b["reference"] == witness_a["reference"]
    refute witness_b["diagnostic_id"] == witness_a["diagnostic_id"]

    assert {:error, :invalid_session_reconciliation} =
             Session.reconcile_turn(session, "worker", witness_a)

    forged = Map.put(witness_a, "session_revision", witness_b["session_revision"])

    assert {:error, :invalid_session_reconciliation} =
             Session.reconcile_turn(session, "worker", forged)

    GenServer.stop(session)
    {:ok, restored} = Session.start_link(ctx.opts)

    assert {:error, {:session_continuation_pending, _, "result_not_final"}} =
             Session.end_turn(restored, "worker")

    {:ok, %{witness: restored_witness}} = Session.continuation(restored, "worker")
    assert restored_witness == witness_b
    assert :ok = Session.reconcile_turn(restored, "worker", restored_witness)
    assert Session.current(restored) == "worker"
    assert Session.read_state(restored) == %{"count" => 1}
    refute_receive :effect
    GenServer.stop(restored)
  end

  test "local reconciliation lost ACK retries only data and preserves shared state, turn and consumed identity",
       ctx do
    {:ok, fault} = Agent.start_link(fn -> :ok end)
    opts = Keyword.put(ctx.opts, :store, {SessionFaultStore, {__MODULE__, fault}})
    {:ok, session} = Session.start_link(opts)
    {:ok, "worker"} = Session.start(session)
    {:ok, _} = Server.chat(ctx.server, "go")
    assert_receive :effect
    {:ok, %{reference: ref}} = Session.continuation(session, "worker")
    {:ok, _, _} = Session.complete_turn(session, "worker", ref, fn _ -> %{"count" => 1} end)
    assert {:error, _} = reject_new_run(session)
    {:ok, %{witness: witness}} = Session.continuation(session, "worker")
    Agent.update(fault, fn _ -> :after end)

    assert {:error, %ExAgent.CheckpointError{result: :ok}} =
             Session.reconcile_turn(session, "worker", witness)

    assert {:error, %ExAgent.CheckpointError{}} = Session.end_turn(session, "worker")
    assert :ok = Session.checkpoint(session)
    assert Session.current(session) == "worker"
    assert Session.read_state(session) == %{"count" => 1}
    GenServer.stop(session)
    {:ok, restored} = Session.start_link(opts)

    assert {:error, :invalid_session_reconciliation} =
             Session.reconcile_turn(restored, "worker", witness)

    refute_receive :effect
    GenServer.stop(restored)
    Agent.stop(fault)
  end

  test "continuation binding metadata is finite and missing v3 guard data is rejected", ctx do
    roster = Enum.map(1..64, &Participant.new(id: "p#{&1}"))
    bindings = Map.new(roster, &{&1.id, %{store: ctx.store, id: "missing-#{&1.id}"}})
    opts = ctx.opts |> Keyword.put(:participants, roster) |> Keyword.put(:continuations, bindings)
    {:ok, session} = Session.start_link(opts)
    assert {:ok, _} = Session.start(session)
    {:ok, snapshot} = Store.load_session_snapshot(ctx.store, "session")
    assert length(snapshot.continuations) == 64
    assert ExAgent.Retention.bytes(snapshot.continuations) <= 64 * 8192 + 16
    map = snapshot |> ExAgent.Session.Snapshot.serialize() |> Jason.decode!()

    assert {:error, :invalid_session_continuations} =
             ExAgent.Session.Snapshot.deserialize(Jason.encode!(Map.delete(map, "continuations")))

    GenServer.stop(session)

    large =
      Keyword.put(
        opts,
        :continuations,
        Map.put(bindings, "p65", %{store: ctx.store, id: "missing"})
      )
      |> Keyword.put(:participants, roster ++ [Participant.new(id: "p65")])

    assert {:error, {:restore_failed, :invalid_session_continuations}} =
             Task.async(fn ->
               Process.flag(:trap_exit, true)
               Session.start_link(large)
             end)
             |> Task.await()
  end

  test "paused callback preserves shared state and turn; explicit completion survives restart and reset",
       ctx do
    {:ok, session} = Session.start_link(ctx.opts)
    assert {:ok, "worker"} = Session.start(session)

    assert {:error, {:session_continuation_pending, "worker", _}} =
             Session.take_turn(session, "worker", fn _ ->
               Server.chat(ctx.server, "go", permissions: Permissions.new!(default: :ask))
             end)

    assert Session.read_state(session) == %{"count" => 0}
    assert Session.current(session) == "worker"
    assert {:ok, %{status: :pending}} = Session.continuation(session, "worker")
    {:ok, %{witness: pending_witness}} = Session.continuation(session, "worker")

    assert {:error, :invalid_session_reconciliation} =
             Session.reconcile_turn(session, "worker", pending_witness)

    assert {:error, {:session_continuation_pending, _, _}} = Session.end_turn(session, "worker")
    assert {:error, {:session_continuation_pending, _, _}} = Session.handoff(session, "worker")
    assert {:error, {:session_continuation_pending, _, _}} = Session.leave(session, "worker")
    assert :ok = Session.pause(session)
    assert Session.status(session) == :paused
    assert :ok = Session.resume(session)
    approve(ctx.server)
    assert_receive :effect
    {:ok, %{reference: ref, status: :completed}} = Session.continuation(session, "worker")

    assert {:ok, %{"count" => 1}, "worker"} =
             Session.complete_turn(session, "worker", ref, fn state ->
               %{"count" => state["count"] + 1}
             end)

    {:ok, snapshot} = Store.load_session_snapshot(ctx.store, "session")
    assert snapshot.version == 3
    assert length(snapshot.continuations) == 1
    GenServer.stop(session)
    {:ok, restored} = Session.start_link(ctx.opts)
    assert Session.read_state(restored) == %{"count" => 1}
    assert :ok = Server.reset(ctx.server)
    {:ok, %{reference: reset_ref}} = Session.continuation(restored, "worker")
    assert reset_ref["revision"] > ref["revision"]
    owner = self()

    assert {:error, :invalid_session_continuation_reference} =
             Session.complete_turn(restored, "worker", reset_ref, fn _ ->
               send(owner, :duplicate_callback)
               %{"count" => 2}
             end)

    refute_receive :duplicate_callback
    refute_receive :effect
    GenServer.stop(restored)
  end

  test "restore consults authoritative row when pause happened without a local pending reference",
       ctx do
    {:ok, session} = Session.start_link(ctx.opts)
    {:ok, "worker"} = Session.start(session)
    GenServer.stop(session)

    assert {:ok, %{status: :paused}} =
             Server.chat(ctx.server, "go", permissions: Permissions.new!(default: :ask))

    {:ok, restored} = Session.start_link(ctx.opts)
    assert {:error, {:session_continuation_pending, _, _}} = Session.end_turn(restored, "worker")
    assert Session.read_state(restored) == %{"count" => 0}
    refute_receive :effect
    GenServer.stop(restored)
  end

  test "authority revision changed during pure completion callback blocks commit without callback replay",
       ctx do
    {:ok, session} = Session.start_link(ctx.opts)
    {:ok, "worker"} = Session.start(session)
    {:ok, _} = Server.chat(ctx.server, "go")
    assert_receive :effect
    {:ok, %{reference: ref}} = Session.continuation(session, "worker")
    owner = self()

    task =
      Task.async(fn ->
        Session.complete_turn(session, "worker", ref, fn _ ->
          send(owner, {:calculating, self()})

          receive do
            :release -> %{"count" => 1}
          end
        end)
      end)

    assert_receive {:calculating, callback}, 1_000
    assert :ok = Server.reset(ctx.server)
    send(callback, :release)
    assert {:error, :continuation_changed_during_callback} = Task.await(task)
    assert Session.read_state(session) == %{"count" => 0}
    assert {:error, {:session_continuation_pending, _, _}} = Session.end_turn(session, "worker")
    refute_receive {:calculating, _}
    GenServer.stop(session)
  end

  test "wrong namespace, participant, lifetime and revision reject before completion callback",
       ctx do
    {:ok, session} = Session.start_link(ctx.opts)
    {:ok, "worker"} = Session.start(session)
    {:ok, _} = Server.chat(ctx.server, "go")
    {:ok, %{reference: ref}} = Session.continuation(session, "worker")
    owner = self()

    for wrong <- [
          Map.put(ref, "namespace", "other"),
          Map.put(ref, "participant_id", "other"),
          Map.put(ref, "record_id", "other"),
          Map.put(ref, "run_id", "other"),
          Map.update!(ref, "revision", &(&1 - 1)),
          Map.put(ref, "version", 2)
        ] do
      assert {:error, :invalid_session_continuation_reference} =
               Session.complete_turn(session, "worker", wrong, fn _ ->
                 send(owner, :bad_callback)
                 %{"count" => 100}
               end)
    end

    refute_receive :bad_callback
    assert Session.read_state(session) == %{"count" => 0}
    GenServer.stop(session)
  end

  test "Session save failure before or after commit retries data without recalculating completion",
       ctx do
    {:ok, _} = Server.chat(ctx.server, "go")

    for mode <- [:before, :after] do
      {:ok, fault} = Agent.start_link(fn -> :ok end)

      opts =
        ctx.opts
        |> Keyword.put(:session_id, "dirty-#{mode}")
        |> Keyword.put(:store, {SessionFaultStore, {__MODULE__, fault}})

      {:ok, session} = Session.start_link(opts)
      {:ok, "worker"} = Session.start(session)
      {:ok, %{reference: ref}} = Session.continuation(session, "worker")
      Agent.update(fault, fn _ -> mode end)
      owner = self()

      assert {:error, %ExAgent.CheckpointError{result: {:ok, %{"count" => 1}, "worker"}}} =
               Session.complete_turn(session, "worker", ref, fn state ->
                 send(owner, :calculated)
                 %{"count" => state["count"] + 1}
               end)

      assert_receive :calculated
      assert Session.read_state(session) == %{"count" => 1}
      assert {:error, %ExAgent.CheckpointError{}} = Session.end_turn(session, "worker")
      assert :ok = Session.checkpoint(session)
      refute_receive :calculated
      GenServer.stop(session)
      {:ok, restored} = Session.start_link(opts)
      assert Session.read_state(restored) == %{"count" => 1}

      assert {:error, :invalid_session_continuation_reference} =
               Session.complete_turn(restored, "worker", ref, fn _ ->
                 send(owner, :calculated)
                 %{"count" => 2}
               end)

      refute_receive :calculated
      GenServer.stop(restored)
      Agent.stop(fault)
    end
  end

  test "unbound paused-shaped application maps remain ordinary data and v3 cannot downgrade guard data",
       ctx do
    ordinary =
      Keyword.drop(ctx.opts, [:continuations, :store]) |> Keyword.put(:session_id, "ordinary")

    {:ok, session} = Session.start_link(ordinary)
    {:ok, "worker"} = Session.start(session)
    map = %{status: :paused, output: nil}
    assert {:ok, ^map, "worker"} = Session.take_turn(session, "worker", fn _ -> map end)
    GenServer.stop(session)
    {:ok, bound} = Session.start_link(ctx.opts)
    {:ok, "worker"} = Session.start(bound)
    {:ok, snapshot} = Store.load_session_snapshot(ctx.store, "session")

    json =
      snapshot
      |> ExAgent.Session.Snapshot.serialize()
      |> Jason.decode!()
      |> Map.put("version", 2)
      |> Jason.encode!()

    assert {:error, :invalid_session_continuations} = ExAgent.Session.Snapshot.deserialize(json)
    GenServer.stop(bound)

    changed =
      Keyword.put(ctx.opts, :continuations, %{
        "worker" => %{
          store: Store.scoped({Store.ETS, __MODULE__}, "another-namespace"),
          id: "agent"
        }
      })

    for opts <- [Keyword.delete(ctx.opts, :continuations), changed] do
      assert {:error, {:restore_failed, :session_continuation_binding_changed}} =
               Task.async(fn ->
                 Process.flag(:trap_exit, true)
                 Session.start_link(opts)
               end)
               |> Task.await()
    end
  end
end
