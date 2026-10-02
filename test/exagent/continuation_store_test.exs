defmodule ExAgent.ContinuationStoreTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Store, RuntimeIdentity, Continuation}
  alias ExAgent.Continuation.{Checkpoint, Record}
  alias ExAgent.Server.Snapshot
  import ExAgent.Test.ContinuationFixtures

  defmodule SnapshotOnly do
    def save_agent_snapshot(_, _), do: raise("must not reach snapshot-only IO")
  end

  defmodule MalformedStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(record, _), do: {:ok, record}
    def transition(_, _, _, _), do: :ok
    def scan_records(record, _, _), do: {:ok, %{records: [record], cursor: nil}}
  end

  # A persistence fault injector, not another product backend. The real ETS
  # transaction executes before a synthetic lost ACK in the :after_write case.
  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(config, key), do: Store.ETS.load_record(config.table, key)

    def scan_records(config, namespace, query),
      do: Store.ETS.scan_records(config.table, namespace, query)

    def transition(config, key, expected, command) do
      send(config.observer, {:persistence_attempt, command["operation_id"]})
      mode = Agent.get_and_update(config.fault, &{&1, :ok})

      case mode do
        :before_write ->
          {:error, :synthetic_save_failure}

        :after_write ->
          {:ok, _} = Store.ETS.transition(config.table, key, expected, command)
          {:error, :synthetic_ack_lost}

        :ok ->
          Store.ETS.transition(config.table, key, expected, command)
      end
    end
  end

  setup do
    owner = start_supervised!({Store.ETS, table: __MODULE__})
    store = Store.scoped({Store.ETS, __MODULE__}, "tenant-a")
    %{store: store, owner: owner}
  end

  test "snapshot-only and ephemeral-as-durable reject before external effects", %{store: store} do
    only = Store.scoped({SnapshotOnly, nil}, "tenant-a")
    assert {:error, :unsupported_store_capability} = Store.require_continuation(only, :durable)

    assert {:error, :unsupported_store_capability} =
             Store.transition(only, :agent, "conversation", :absent, create())

    assert {:error, :unsupported_store_capability} = Store.require_continuation(store, :durable)
    assert :ok = Store.require_continuation(store, :ephemeral)
  end

  test "pre-existing raw ETS tid remains snapshot-only with guarded atomic legacy updates" do
    table = :ets.new(:raw_r4_snapshot, [:set, :public])
    raw = {Store.ETS, table}
    scoped = Store.scoped(raw, "tenant-a")
    snapshot = Snapshot.new(agent_id: "raw", history: [], revision: 1)
    assert :ok = Store.save_agent_snapshot(raw, snapshot)
    assert :ok = Store.save_agent_snapshot(raw, %{snapshot | revision: 2})
    assert {:ok, %{revision: 2}} = Store.load_agent_snapshot(raw, "raw")

    assert {:error, :unsupported_store_capability} =
             Store.require_continuation(scoped, :ephemeral)

    assert {:error, :unsupported_store_capability} =
             Store.transition(scoped, :agent, "conversation", :absent, create())

    assert :ok = Store.delete_agent_snapshot(raw, "raw")
    {:ok, encoded} = RuntimeIdentity.key("tenant-a", :agent, "conversation")
    {:ok, bytes} = Record.encode(ready(), key())
    :ets.insert(table, {{:agent, encoded}, bytes})

    assert {:error, :atomic_record_required} =
             Store.save_agent_snapshot(scoped, Snapshot.new(agent_id: "conversation"))

    assert {:error, :atomic_record_required} = Store.delete_agent_snapshot(scoped, "conversation")
    :ets.delete(table)
  end

  test "malformed custom replies and wrong-scope records fail closed" do
    scope = Store.scoped({MalformedStore, ready()}, "tenant-b")
    assert {:error, :invalid_record} = Store.load_record(scope, :agent, "conversation")

    assert {:error, {:invalid_store_return, :ok}} =
             Store.transition(scope, :agent, "conversation", 1, claim())

    assert {:error, :invalid_store_return} = Store.scan_records(scope)
  end

  test "session and agent with identical namespace/id use separate native keys and codecs", %{
    store: store
  } do
    {:ok, _} = Store.transition(store, :agent, "conversation", :absent, create())

    snapshot = %ExAgent.Session.Snapshot{
      session_id: "conversation",
      participants: [%{id: "a", kind: :human}],
      status: :running,
      current: "a",
      policy_mod: "Elixir.NeverResolveFromBytes",
      policy_state: %{"actor" => "a"}
    }

    create = put_in(create(), ["payload", "snapshot"], Record.snapshot_data(snapshot))

    assert {:ok, %{record: record}} =
             Store.transition(store, :session, "conversation", :absent, create)

    assert record["key"] == ["tenant-a", "session", "conversation"]
    assert {:error, :atomic_record_required} = Store.load_session_snapshot(store, "conversation")
    assert {:error, :atomic_record_required} = Store.save_session_snapshot(store, snapshot)

    assert {:error, :atomic_record_required} =
             Store.delete_session_snapshot(store, "conversation")

    assert {:ok, _} = Store.load_record(store, :agent, "conversation")
  end

  test "two creators and claimants released by barriers have exactly one winner", %{store: store} do
    creates = [create(), %{create() | "operation_id" => "other-create"}]

    results =
      race(fn i ->
        Store.transition(store, :agent, "conversation", :absent, Enum.at(creates, i))
      end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 1
    until = System.system_time(:millisecond) + 10_000

    claims =
      race(fn i ->
        Store.transition(store, :agent, "conversation", 1, claim(until, "attempt-#{i}"))
      end)

    assert Enum.count(claims, &match?({:ok, _}, &1)) == 1
    assert Enum.count(claims, &(&1 == {:error, :conflict})) == 1
    assert {:ok, record} = Store.load_record(store, :agent, "conversation")
    assert record["revision"] == 2
  end

  test "legacy saves/delete cannot bypass atomic record, including concurrent creation", %{
    store: store
  } do
    {:ok, _} = Store.transition(store, :agent, "conversation", :absent, create())
    snapshot = Snapshot.new(agent_id: "conversation", history: [])
    assert {:error, :atomic_record_required} = Store.save_agent_snapshot(store, snapshot)
    assert {:error, :atomic_record_required} = Store.delete_agent_snapshot(store, "conversation")
    assert {:error, :atomic_record_required} = Store.load_agent_snapshot(store, "conversation")
    assert Store.list_agent_snapshots(store) == []
    assert {:ok, current} = Store.load_record(store, :agent, "conversation")
    assert {:ok, restored} = Record.snapshot(current["snapshot"], key())
    assert restored.revision == 7

    legacy = Snapshot.new(agent_id: "race", history: [])

    results =
      race(fn
        0 -> Store.save_agent_snapshot(store, legacy)
        1 -> Store.transition(store, :agent, "race", :absent, create("race"))
      end)

    assert (:ok in results and {:error, :legacy_snapshot} in results) or
             (Enum.any?(results, &match?({:ok, _}, &1)) and
                {:error, :atomic_record_required} in results)
  end

  test "legacy snapshot stays byte-identical and readable; no inferred execution", %{store: store} do
    {:ok, encoded} = RuntimeIdentity.key("tenant-a", :agent, "old")
    bytes = Jason.encode!(%{"version" => 1, "agent_id" => encoded, "message_history" => "[]"})
    :ets.insert(__MODULE__, {{:agent, encoded}, bytes})
    assert {:ok, legacy} = Store.load_agent_snapshot(store, "old")
    assert legacy.agent_id == "old"

    assert {:error, :legacy_snapshot} =
             Store.transition(store, :agent, "old", :absent, create("old"))

    assert [{{:agent, ^encoded}, ^bytes}] = :ets.lookup(__MODULE__, {:agent, encoded})
  end

  test "unintegrated Server refuses atomic record during restore, before admitting a run", %{
    store: store
  } do
    Process.flag(:trap_exit, true)
    {:ok, _} = Store.transition(store, :agent, "conversation", :absent, create())

    assert {:error, {:restore_failed, :atomic_record_required}} =
             ExAgent.Server.start_link(
               agent: ExAgent.new(model: %ExAgent.Models.Test{}),
               agent_id: "conversation",
               namespace: "tenant-a",
               store: {Store.ETS, __MODULE__}
             )

    assert {:ok, record} = Store.load_record(store, :agent, "conversation")
    assert record["revision"] == 1
  end

  test "waiting for ETS owner consumes absolute deadline", %{store: store, owner: owner} do
    deadline = System.system_time(:millisecond) + 50
    create = put_in(create(), ["payload", "execution", "deadline_at"], deadline)
    {:ok, _} = Store.transition(store, :agent, "conversation", :absent, create)
    :sys.suspend(owner)

    task =
      Task.async(fn ->
        Store.transition(store, :agent, "conversation", 1, claim(deadline + 5_000))
      end)

    wait_until(deadline)
    :sys.resume(owner)
    assert {:error, :expired} = Task.await(task)
  end

  test "dirty retry only persists the captured outcome; lost ACK returns original receipt", %{
    store: store
  } do
    for {fault, id} <- [{:before_write, "before"}, {:after_write, "after"}] do
      {:ok, _} = Store.transition(store, :agent, id, :absent, create(id))

      {:ok, %{record: record}} =
        Store.transition(store, :agent, id, 1, claim(System.system_time(:millisecond) + 10_000))

      {:ok, %{record: running}} = Store.transition(store, :agent, id, 2, begin_effect(record))
      effect_journal = start_supervised!({Agent, fn -> 0 end}, id: {:journal, id})
      Agent.update(effect_journal, &(&1 + 1))
      fault_pid = start_supervised!({Agent, fn -> fault end}, id: {:fault, id})

      failing =
        Store.scoped(
          {FaultStore, %{table: __MODULE__, fault: fault_pid, observer: self()}},
          "tenant-a"
        )

      {:ok, checkpoint} = Checkpoint.new(failing, :agent, id, :ephemeral)
      {{:error, _}, dirty} = Checkpoint.write(checkpoint, 3, outcome(running))
      assert_receive {:persistence_attempt, "outcome"}

      assert {{:error, :checkpoint_pending}, ^dirty} =
               Checkpoint.write(dirty, 3, begin_effect(record))

      refute_receive {:persistence_attempt, _}, 0
      assert {{:ok, reply}, clean} = Checkpoint.retry(dirty)
      assert_receive {:persistence_attempt, "outcome"}
      assert reply.replayed == (fault == :after_write)
      assert reply.receipt["revision"] == 4
      assert clean.pending == nil
      assert Agent.get(effect_journal, & &1) == 1
      assert {:ok, current} = Store.load_record(store, :agent, id)
      assert current["revision"] == 4
    end
  end

  test "killed worker after intent or effect leaves uncertain marker and stale write is fenced",
       %{store: store} do
    for effect? <- [false, true] do
      id = if effect?, do: "after-effect", else: "before-effect"
      journal = start_supervised!({Agent, fn -> 0 end}, id: {:crash_journal, id})
      {:ok, _} = Store.transition(store, :agent, id, :absent, create(id))
      lease = System.system_time(:millisecond) + 100
      {:ok, %{record: claimed}} = Store.transition(store, :agent, id, 1, claim(lease))
      parent = self()

      {pid, monitor} =
        spawn_monitor(fn ->
          {:ok, %{record: running}} =
            Store.transition(store, :agent, id, 2, begin_effect(claimed))

          if effect?, do: Agent.update(journal, &(&1 + 1))
          send(parent, {:barrier, self(), running})

          receive do
            :never -> :ok
          end
        end)

      assert_receive {:barrier, ^pid, running}, 1_000
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
      wait_until(lease)

      assert {:ok, %{record: uncertain}} =
               Store.transition(store, :agent, id, 3, command("recover"))

      assert uncertain["execution"]["state"] == "uncertain"
      assert {:error, :stale_owner} = Store.transition(store, :agent, id, 4, outcome(running))

      assert {:error, :invalid_transition} =
               Store.transition(store, :agent, id, 4, claim(lease + 10_000, "attempt-2"))

      assert Agent.get(journal, & &1) == if(effect?, do: 1, else: 0)
    end
  end

  test "bounded namespace prune preserves active/uncertain rows and surfaces corruption", %{
    store: store
  } do
    other = Store.scoped({Store.ETS, __MODULE__}, "tenant-b")

    for scope <- [store, other], id <- ["active", "terminal"] do
      {:ok, _} = Store.transition(scope, :agent, id, :absent, create(id))
    end

    {:ok, %{record: claimed}} =
      Store.transition(
        store,
        :agent,
        "terminal",
        1,
        claim(System.system_time(:millisecond) + 10_000)
      )

    finish =
      command(
        "finish",
        worker(claimed, %{
          "snapshot" => claimed["snapshot"],
          "progress" => claimed["execution"]["progress"]
        })
      )

    {:ok, _} = Store.transition(store, :agent, "terminal", 2, finish)
    assert {:ok, page} = Store.scan_records(store, %{limit: 1})
    assert length(page.records) <= 1
    assert is_binary(page.cursor)

    assert {:ok, pruned} =
             Continuation.prune_page(store, System.system_time(:millisecond) + 1, "admin")

    assert Enum.count(pruned.results, &match?({_, {:ok, _}}, &1)) == 1
    assert {:ok, _} = Store.load_record(store, :agent, "active")
    assert {:error, :not_found} = Store.load_record(store, :agent, "terminal")
    assert {:ok, _} = Store.load_record(other, :agent, "terminal")
    {:ok, encoded} = RuntimeIdentity.key("tenant-a", :agent, "active")
    :ets.insert(__MODULE__, {{:agent, encoded}, "{broken"})
    assert {:error, :invalid_record} = Store.scan_records(store)
    assert {:error, :invalid_record} = Store.transition(store, :agent, "active", 1, claim())
  end

  test "table-owner loss actually loses ETS continuation data", %{store: store, owner: owner} do
    {:ok, _} = Store.transition(store, :agent, "conversation", :absent, create())
    GenServer.stop(owner)
    assert :ets.whereis(__MODULE__) == :undefined
    assert {:error, _} = Store.load_record(store, :agent, "conversation")
  end

  @tag :tmp_dir
  test "new VM reads synthetic disk JSON and preserves uncertain progress without any live owner",
       %{tmp_dir: dir} do
    claimed = claimed()

    {:ok, %{record: running}} =
      ExAgent.Continuation.Transition.apply(claimed, key(), 2, begin_effect(claimed), 1_002)

    {:ok, bytes} = Record.encode(running, key())
    path = Path.join(dir, "synthetic-record.json")
    File.write!(path, bytes)

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.filter(&String.starts_with?(&1, System.fetch_env!("MIX_BUILD_PATH")))
      |> Enum.flat_map(&["-pa", &1])

    script = """
    alias ExAgent.Continuation.{Record, Transition}
    key = {"tenant-a", :agent, "conversation"}
    {:ok, record} = Record.decode(File.read!(hd(System.argv())), key)
    command = %{"record_id" => "record-1", "operation" => "recover", "operation_id" => "cold-recover", "actor_id" => "host", "payload" => %{}}
    {:ok, %{record: record}} = Transition.apply(record, key, 3, command, 2000)
    IO.puts(Jason.encode!(%{"state" => record["execution"]["state"], "progress" => record["execution"]["progress"], "run_id" => record["execution"]["run_id"], "revision" => record["revision"]}))
    """

    {output, 0} = System.cmd("elixir", paths ++ ["-e", script, path], stderr_to_stdout: true)

    assert Jason.decode!(String.trim(output)) == %{
             "state" => "uncertain",
             "progress" => running["execution"]["progress"],
             "run_id" => "run-1",
             "revision" => 4
           }

    assert File.read!(path) == bytes
  end

  defp race(fun) do
    parent = self()

    tasks =
      for i <- 0..1 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> fun.(i)
          end
        end)
      end

    for task <- tasks, do: assert_receive({:ready, pid} when pid == task.pid)
    for task <- tasks, do: send(task.pid, :go)
    Enum.map(tasks, &Task.await/1)
  end

  defp wait_until(deadline) do
    remaining = max(deadline - System.system_time(:millisecond) + 1, 0)

    receive do
    after
      remaining -> :ok
    end
  end
end
