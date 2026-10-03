defmodule ExAgent.ContinuationPostgresContractTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Store, RuntimeIdentity}
  alias ExAgent.Continuation.Record
  import ExAgent.Test.ContinuationFixtures

  # Scripted Repo protocol fixture ONLY. No SQL engine, durable storage, concurrent
  # transaction isolation or real rollback is certified by these assertions.
  defmodule Repo do
    def script(steps), do: Process.put({__MODULE__, :steps}, steps)
    def remaining, do: Process.get({__MODULE__, :steps}, [])

    def query(sql, params) do
      send(self(), {:sql, sql, params})
      [{match, result} | rest] = remaining()
      unless match.(sql, params), do: raise("unexpected SQL protocol step: #{sql}")
      Process.put({__MODULE__, :steps}, rest)
      result
    end

    def transaction(fun, opts) do
      send(self(), {:transaction, opts})

      try do
        result = fun.()
        send(self(), :commit)
        {:ok, result}
      catch
        {:rollback, reason} ->
          send(self(), {:rolled_back, reason})
          {:error, reason}
      end
    end

    def rollback(reason), do: throw({:rollback, reason})
  end

  defp store, do: Store.scoped({Store.Postgres, {Repo, table: "r4_fixture"}}, "tenant-a")

  defp physical do
    {:ok, encoded} = RuntimeIdentity.key("tenant-a", :agent, "conversation")
    "agent:" <> encoded
  end

  defp step(fragment, rows),
    do: {fn sql, _ -> String.contains?(sql, fragment) end, {:ok, %{rows: rows}}}

  defp transaction_prefix(rows, now),
    do: [
      step("SET LOCAL statement_timeout", []),
      step("FOR UPDATE", rows),
      step("clock_timestamp()) * 1000", [[now]])
    ]

  test "existing row transition locks before clock, updates once and commits receipt" do
    record = ready()
    {:ok, bytes} = Record.encode(record, key())
    Repo.script(transaction_prefix([[bytes]], 1_001) ++ [step("UPDATE", [[physical()]])])

    assert {:ok, %{record: claimed}} =
             Store.transition(store(), :agent, "conversation", 1, claim())

    assert claimed["revision"] == 2
    assert Repo.remaining() == []
    assert_receive {:transaction, [timeout: 5_000]}
    assert_receive :commit
    assert_receive {:sql, update, [key, written]}
    # The first two setup queries do not have two parameters; receive selects UPDATE.
    assert update =~ "UPDATE"
    assert key == physical()
    assert {:ok, ^claimed} = Record.decode(written, key())
  end

  defp cancelled_bytes do
    {:ok, %{record: record}} =
      ExAgent.Continuation.Transition.apply(ready(), key(), 1, command("cancel"), 1_001)

    {:ok, bytes} = Record.encode(record, key())
    bytes
  end

  defp delete_step(rows) do
    {fn sql, params -> sql =~ "DELETE FROM" and params == [physical()] end,
     {:ok, %{command: :delete, num_rows: length(rows), rows: rows}}}
  end

  test "delete denied with zero affected rows conflicts and rolls back instead of acknowledging" do
    Repo.script(transaction_prefix([[cancelled_bytes()]], 1_003) ++ [delete_step([])])

    assert {:error, :conflict} =
             Store.transition(
               store(),
               :agent,
               "conversation",
               2,
               command("delete", %{"before" => 1_002})
             )

    assert_receive {:rolled_back, :conflict}
    refute_receive :commit
    assert Repo.remaining() == []
  end

  test "delete acknowledges the returned physical key and preserves SQL errors" do
    Repo.script(transaction_prefix([[cancelled_bytes()]], 1_003) ++ [delete_step([[physical()]])])
    delete = command("delete", %{"before" => 1_002})

    assert {:ok, %{record: nil, receipt: nil, replayed: false}} =
             Store.transition(store(), :agent, "conversation", 2, delete)

    assert_receive :commit
    assert_receive {:sql, "DELETE FROM" <> sql, [_]}
    assert sql =~ "RETURNING key"
    assert Repo.remaining() == []

    Repo.script(
      transaction_prefix([[cancelled_bytes()]], 1_003) ++
        [{fn sql, _ -> sql =~ "DELETE FROM" end, {:error, :synthetic_delete_denial}}]
    )

    assert {:error, :synthetic_delete_denial} =
             Store.transition(store(), :agent, "conversation", 2, delete)

    assert_receive {:rolled_back, :synthetic_delete_denial}
    refute_receive :commit
    assert Repo.remaining() == []
  end

  test "absent delete stays not_found and retained receipt replay performs no delete" do
    Repo.script(transaction_prefix([], 1_003))

    assert {:error, :not_found} =
             Store.transition(
               store(),
               :agent,
               "conversation",
               2,
               command("delete", %{"before" => 1_002})
             )

    assert_receive {:rolled_back, :not_found}
    refute_receive :commit
    assert Repo.remaining() == []

    Repo.script(transaction_prefix([[cancelled_bytes()]], 1_003))

    assert {:ok, %{replayed: true, record: %{"revision" => 2}}} =
             Store.transition(store(), :agent, "conversation", 1, command("cancel"))

    assert_receive :commit
    refute_receive {:sql, "DELETE FROM" <> _, _}
    assert Repo.remaining() == []
  end

  test "lost create race re-reads locked winner and cannot report two winners" do
    {:ok, bytes} = Record.encode(ready(), key())
    loser = %{create() | "operation_id" => "loser"}

    Repo.script(
      transaction_prefix([], 1_000) ++
        [
          step("DO NOTHING RETURNING", []),
          step("FOR UPDATE", [[bytes]]),
          step("clock_timestamp()) * 1000", [[1_001]])
        ]
    )

    assert {:error, :conflict} = Store.transition(store(), :agent, "conversation", :absent, loser)
    assert_receive {:rolled_back, :conflict}
    refute_receive :commit
    assert Repo.remaining() == []
  end

  test "lost create ACK can recover same operation from winner after conflict" do
    {:ok, bytes} = Record.encode(ready(), key())

    Repo.script(
      transaction_prefix([], 1_000) ++
        [
          step("DO NOTHING RETURNING", []),
          step("FOR UPDATE", [[bytes]]),
          step("clock_timestamp()) * 1000", [[1_001]])
        ]
    )

    assert {:ok, %{replayed: true, receipt: %{"revision" => 1}}} =
             Store.transition(store(), :agent, "conversation", :absent, create())

    assert_receive :commit
    assert Repo.remaining() == []
  end

  test "conflict and failed persistence roll back; no compensating success or fallback" do
    {:ok, bytes} = Record.encode(ready(), key())
    Repo.script(transaction_prefix([[bytes]], 1_001))
    assert {:error, :conflict} = Store.transition(store(), :agent, "conversation", 99, claim())
    assert_receive {:rolled_back, :conflict}

    Repo.script(
      transaction_prefix([[bytes]], 1_001) ++
        [{fn sql, _ -> sql =~ "UPDATE" end, {:error, :synthetic_disconnect}}]
    )

    assert {:error, :synthetic_disconnect} =
             Store.transition(store(), :agent, "conversation", 1, claim())

    assert_receive {:rolled_back, :synthetic_disconnect}
    refute_receive :commit
  end

  test "legacy mutation protects record in SQL write or locked transaction" do
    {:ok, bytes} = Record.encode(ready(), key())

    Repo.script([
      {fn sql, _ ->
         sql =~ "WHERE NOT (\"r4_fixture\".data::jsonb ? 'record_version') RETURNING key"
       end, {:ok, %{rows: []}}}
    ])

    assert {:error, :atomic_record_required} =
             Store.save_agent_snapshot(
               store(),
               ExAgent.Server.Snapshot.new(agent_id: "conversation")
             )

    Repo.script([step("SET LOCAL", []), step("FOR UPDATE", [[bytes]])])

    assert {:error, :atomic_record_required} =
             Store.delete_agent_snapshot(store(), "conversation")

    assert_receive {:rolled_back, :atomic_record_required}
    refute_receive {:sql, "DELETE" <> _, _}
  end

  test "legacy delete of initially absent row cannot erase a concurrently created envelope" do
    {:ok, bytes} = Record.encode(ready(), key())

    Repo.script([
      step("SET LOCAL", []),
      step("FOR UPDATE", []),
      {fn sql, _ ->
         sql =~ "DELETE" and sql =~ "NOT (data::jsonb ? 'record_version')" and
           sql =~ "RETURNING key"
       end, {:ok, %{rows: []}}},
      step("FOR UPDATE", [[bytes]])
    ])

    assert {:error, :atomic_record_required} =
             Store.delete_agent_snapshot(store(), "conversation")

    assert_receive {:rolled_back, :atomic_record_required}
    refute_receive :commit
    assert Repo.remaining() == []
  end

  test "scan bounds physical rows and never turns DB error into empty success" do
    Repo.script([
      {fn sql, params -> sql =~ "ORDER BY key LIMIT $2" and params == ["", 2] end,
       {:error, :synthetic_db_failure}}
    ])

    assert {:error, :synthetic_db_failure} = Store.scan_records(store(), %{limit: 2})
    {:ok, bytes} = Record.encode(ready(), key())
    Repo.script([step("ORDER BY key LIMIT $2", [[physical(), bytes]])])
    assert {:ok, %{records: [record], cursor: nil}} = Store.scan_records(store(), %{limit: 2})
    assert record["key"] == ["tenant-a", "agent", "conversation"]
    assert {:error, :invalid_scan} = Store.scan_records(store(), %{limit: 101})
  end

  test "configured table identifier is validated before Repo IO" do
    bad = Store.scoped({Store.Postgres, {Repo, table: "table;DROP TABLE x"}}, "tenant-a")

    assert {:error, {:exception, %ArgumentError{}}} =
             Store.load_record(bad, :agent, "conversation")

    refute_receive {:sql, _, _}
  end

  test "create revalidates UTC expiry after INSERT may have waited on a unique conflict" do
    create = put_in(create(), ["payload", "execution", "deadline_at"], 1_010)

    Repo.script(
      transaction_prefix([], 1_000) ++
        [
          step("DO NOTHING RETURNING", [[physical()]]),
          step("clock_timestamp()) * 1000", [[1_010]])
        ]
    )

    assert {:error, :expired} = Store.transition(store(), :agent, "conversation", :absent, create)
    assert_receive {:rolled_back, :expired}
    refute_receive :commit
  end
end
