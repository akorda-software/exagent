defmodule ExAgent.Store.Postgres do
  @moduledoc """
  A durable `ExAgent.Store` backed by PostgreSQL, for resume across crashes and
  multiple nodes.

  Snapshots are stored as **JSON** (the same strict serialization `ExAgent.Store.ETS`
  uses), never raw Erlang terms — so nothing non-serializable (pids,
  closures) can land in the database. The store is **DB-free by default** in the
  rest of exAgent: this module needs `ecto_sql` + `postgrex`, declared as optional
  dependencies that a host app adds when it wants a durable store.
  JSON does not redact secrets present in application data. Ordinary snapshots
  retain their single-writer contract. Experimental continuation commands use one
  row transaction and receipts; they do not make external effects transactional.
  Real SQL recovery/locking qualification is separate from offline protocol tests.

  ## Wiring

  The store takes the host app's `Ecto.Repo` as its config (the host owns the
  database connection — exAgent never does):

      # 1) add deps in your app:
      #   {:ecto_sql, "~> 3.0"}, {:postgrex, "~> 0.19"}
      # 2) create the table once (migration or at boot):
      ExAgent.Store.Postgres.migrate(MyApp.Repo)
      # 3) use it:
      ExAgent.AgentSupervisor.start_agent(
        agent: agent_template,
        agent_id: "dm",
        store: {ExAgent.Store.Postgres, MyApp.Repo}
      )

  The snapshots table is `exagent_snapshots` by default; override it with
  `{ExAgent.Store.Postgres, {MyApp.Repo, table: "my_snapshots"}}`.

  ## Why not own the database?

  A library shouldn't own your connection pool, credentials or migrations. The
  repo comes from your app; exAgent only issues parameterized SQL against one
  table.
  """

  @behaviour ExAgent.Store

  alias ExAgent.Server.Snapshot
  alias ExAgent.Session.Snapshot, as: SessionSnapshot
  alias ExAgent.Continuation.{Record, Storage, Transition}

  @default_table "exagent_snapshots"

  # config forms: repo | {repo, opts} | {repo, table: "..."}
  defp conf(repo) when is_atom(repo), do: {repo, identifier!(@default_table)}

  defp conf({repo, opts}) when is_atom(repo) and is_list(opts),
    do: {repo, identifier!(opts[:table] || @default_table)}

  defp identifier!(name) when is_binary(name) do
    if Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]{0,62}\z/, name),
      do: ~s("#{name}"),
      else: raise(ArgumentError, "invalid Store table identifier")
  end

  # ----- agents -------------------------------------------------------------
  @impl true
  def save_agent_snapshot(config, %Snapshot{} = snap) do
    {repo, table} = conf(config)

    save_legacy(repo, table, agent_key(snap.agent_id), Snapshot.serialize(snap))
  end

  @impl true
  def load_agent_snapshot(config, agent_id) do
    {repo, table} = conf(config)

    case repo.query("SELECT data FROM #{table} WHERE key = $1", [agent_key(agent_id)]) do
      {:ok, %{rows: [[binary | _] | _]}} -> Storage.snapshot(binary, :agent, agent_id)
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:error, _} = e -> e
    end
  end

  @impl true
  def list_agent_snapshots(config) do
    {repo, table} = conf(config)

    case repo.query("SELECT key, data FROM #{table} WHERE key LIKE 'agent:%'", []) do
      {:ok, %{rows: rows}} ->
        Enum.flat_map(rows, fn ["agent:" <> id, binary] ->
          case Storage.snapshot(binary, :agent, id) do
            {:ok, %Snapshot{} = s} -> [s]
            {:error, _} -> []
          end
        end)

      {:error, _} ->
        []
    end
  end

  @impl true
  def delete_agent_snapshot(config, agent_id) do
    {repo, table} = conf(config)

    delete_legacy(repo, table, agent_key(agent_id))
  end

  # ----- sessions -----------------------------------------------------------
  @impl true
  def save_session_snapshot(config, %SessionSnapshot{} = snap) do
    {repo, table} = conf(config)

    save_legacy(repo, table, session_key(snap.session_id), SessionSnapshot.serialize(snap))
  end

  @impl true
  def load_session_snapshot(config, session_id) do
    {repo, table} = conf(config)

    case repo.query("SELECT data FROM #{table} WHERE key = $1", [session_key(session_id)]) do
      {:ok, %{rows: [[binary | _] | _]}} ->
        Storage.snapshot(binary, :session, session_id)

      {:ok, %{rows: []}} ->
        {:error, :not_found}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def delete_session_snapshot(config, session_id) do
    {repo, table} = conf(config)

    delete_legacy(repo, table, session_key(session_id))
  end

  # ----- schema -------------------------------------------------------------
  @doc """
  Create the snapshots table (idempotent). Run this once from a migration or at
  boot, against your app's repo. Columns: `key` (PK), `data` (the JSON text),
  `updated_at`.
  """
  @spec migrate(module(), String.t()) :: :ok | {:error, term()}
  def migrate(repo, table \\ @default_table) do
    table = identifier!(table)

    sql =
      "CREATE TABLE IF NOT EXISTS #{table} (" <>
        "key text PRIMARY KEY, data text NOT NULL, updated_at timestamptz NOT NULL DEFAULT now())"

    with {:ok, _} <- repo.query(sql, []) do
      :ok
    end
  end

  defp agent_key(id), do: "agent:" <> to_string(id)
  defp session_key(id), do: "session:" <> to_string(id)

  defp save_legacy(repo, table, key, binary) do
    sql =
      "INSERT INTO #{table} (key, data) VALUES ($1, $2) " <>
        "ON CONFLICT (key) DO UPDATE SET data = EXCLUDED.data, updated_at = now() " <>
        "WHERE NOT (#{table}.data::jsonb ? 'record_version') RETURNING key"

    case repo.query(sql, [key, binary]) do
      {:ok, %{rows: [[^key]]}} -> :ok
      {:ok, %{rows: []}} -> {:error, :atomic_record_required}
      {:error, _} = error -> error
    end
  end

  defp delete_legacy(repo, table, key) do
    transaction(repo, fn ->
      with {:ok, binary} <- locked_row(repo, table, key),
           :ok <- Storage.legacy_writable(binary),
           {:ok, %{rows: rows}} <-
             repo.query(
               "DELETE FROM #{table} WHERE key = $1 AND NOT (data::jsonb ? 'record_version') RETURNING key",
               [key]
             ) do
        case rows do
          [[^key]] ->
            {:ok, :ok}

          [] ->
            # An absent row cannot be locked. A record may appear between SELECT
            # and DELETE; the write predicate protects it, then this read reports
            # the refusal rather than claiming a successful legacy deletion.
            with {:ok, current} <- locked_row(repo, table, key),
                 :ok <- Storage.legacy_writable(current),
                 do: {:ok, :ok}
        end
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  @impl true
  def capabilities(_config), do: %{continuation: :atomic, durability: :durable}

  @impl true
  def load_record(config, key) do
    {repo, table} = conf(config)

    with {:ok, physical} <- Record.key(key),
         {:ok, %{rows: rows}} <-
           repo.query("SELECT data FROM #{table} WHERE key = $1", [Storage.physical(physical)]) do
      case rows do
        [[binary]] -> Storage.record(binary, key)
        [] -> {:error, :not_found}
      end
    end
  end

  @impl true
  def transition(config, key, expected, command) do
    {repo, table} = conf(config)

    with {:ok, physical} <- Record.key(key) do
      physical = Storage.physical(physical)

      transaction(repo, fn ->
        with {:ok, binary} <- locked_row(repo, table, physical),
             {:ok, current} <- Storage.record(binary, key) do
          transition_locked(repo, table, physical, key, current, expected, command)
        end
      end)
    end
  end

  defp transition_locked(repo, table, physical, key, current, expected, command) do
    with {:ok, now} <- clock(repo),
         {:ok, result} <- Transition.apply(current, key, expected, command, now) do
      cond do
        result.replayed ->
          {:ok, result}

        is_nil(result.record) ->
          case repo.query("DELETE FROM #{table} WHERE key = $1 RETURNING key", [physical]) do
            {:ok, %{rows: [[^physical]]}} -> {:ok, result}
            {:error, _} = error -> error
            _ -> {:error, :conflict}
          end

        is_nil(current) ->
          insert_record(repo, table, physical, key, expected, command, result)

        true ->
          with {:ok, binary} <- Record.encode(result.record, key),
               {:ok, %{rows: [[^physical]]}} <-
                 repo.query(
                   "UPDATE #{table} SET data = $2, updated_at = clock_timestamp() WHERE key = $1 RETURNING key",
                   [physical, binary]
                 ) do
            {:ok, result}
          else
            {:error, _} = error -> error
            _ -> {:error, :conflict}
          end
      end
    end
  end

  defp insert_record(repo, table, physical, key, expected, command, result) do
    with {:ok, binary} <- Record.encode(result.record, key),
         {:ok, %{rows: rows}} <-
           repo.query(
             "INSERT INTO #{table} (key, data) VALUES ($1, $2) ON CONFLICT (key) DO NOTHING RETURNING key",
             [physical, binary]
           ) do
      case rows do
        [[^physical]] ->
          # INSERT can wait for a competing uncommitted key whose transaction
          # ultimately rolls back. Revalidate time after obtaining that key;
          # this provisional row is still invisible outside our transaction.
          with {:ok, now} <- clock(repo),
               {:ok, refreshed} <- Transition.apply(nil, key, expected, command, now),
               {:ok, bytes} <- Record.encode(refreshed.record, key),
               {:ok, %{rows: [[^physical]]}} <-
                 repo.query(
                   "UPDATE #{table} SET data = $2, updated_at = clock_timestamp() WHERE key = $1 RETURNING key",
                   [physical, bytes]
                 ) do
            {:ok, refreshed}
          else
            {:error, _} = error -> error
            _ -> {:error, :conflict}
          end

        [] ->
          # A concurrent creator can win while our SELECT found no row. Re-read
          # under lock, allowing only identical receipt recovery or a conflict.
          with {:ok, winner_bytes} <- locked_row(repo, table, physical),
               {:ok, winner} when not is_nil(winner) <- Storage.record(winner_bytes, key),
               {:ok, now} <- clock(repo) do
            Transition.apply(winner, key, expected, command, now)
          else
            {:error, _} = error -> error
            _ -> {:error, :conflict}
          end
      end
    end
  end

  @impl true
  def scan_records(config, namespace, query) do
    {repo, table} = conf(config)

    with {:ok, {limit, after_key}} <- Storage.scan_query(query),
         :ok <- ExAgent.RuntimeIdentity.validate(namespace, ""),
         {:ok, %{rows: rows}} <-
           repo.query("SELECT key, data FROM #{table} WHERE key > $1 ORDER BY key LIMIT $2", [
             after_key || "",
             limit
           ]) do
      cursor = if length(rows) == limit, do: rows |> List.last() |> hd(), else: nil
      Storage.page(Enum.map(rows, fn [key, bytes] -> {key, bytes} end), namespace, cursor)
    end
  end

  defp locked_row(repo, table, key) do
    case repo.query("SELECT data FROM #{table} WHERE key = $1 FOR UPDATE", [key]) do
      {:ok, %{rows: [[binary]]}} -> {:ok, binary}
      {:ok, %{rows: []}} -> {:ok, nil}
      {:error, _} = error -> error
    end
  end

  defp clock(repo) do
    case repo.query("SELECT floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint", []) do
      {:ok, %{rows: [[now]]}} when is_integer(now) -> {:ok, now}
      {:error, _} = error -> error
      _ -> {:error, :invalid_store_clock}
    end
  end

  defp transaction(repo, fun) do
    repo.transaction(
      fn ->
        result =
          with {:ok, _} <- repo.query("SET LOCAL statement_timeout = '5000ms'", []), do: fun.()

        case result do
          {:ok, value} -> value
          {:error, reason} -> repo.rollback(reason)
        end
      end,
      timeout: 5_000
    )
  end
end
