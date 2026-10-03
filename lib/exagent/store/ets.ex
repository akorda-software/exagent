defmodule ExAgent.Store.ETS do
  @moduledoc """
  In-process, ETS-backed `ExAgent.Store` implementation (dev/test default).

  A supervised `ExAgent.Store.ETS` GenServer owns a public, named ETS table
  (default name `ExAgent.Store.ETS`, started by the application supervisor), so
  the table outlives any single `ExAgent.Server` crash and snapshots survive a
  restart. Mutations are serialized by the owner, including legacy writes; record
  deadlines are checked after waiting in that owner's mailbox. Reads use ETS.

  ## Portability (the important bit)

  Even though ETS can hold arbitrary Erlang terms, this implementation
  **round-trips snapshots through JSON** (`Snapshot.serialize/1`), never
  `term_to_binary`. That enforces two things a future Postgres store will rely
  on:

    1. the stored shape is portable (JSON, not opaque binaries), and
    2. non-serializable values (pids, function captures) are refused
       at write time — `Jason.encode!` raises rather than persisting junk.

  Use it as `store: :ets` on `ExAgent.Server` / `ExAgent.AgentSupervisor`.
  JSON does not redact secret strings. Data survives a conversation owner restart
  while the ETS table owner lives, not table-owner or VM loss.
  """

  use GenServer

  @behaviour ExAgent.Store

  alias ExAgent.Server.Snapshot
  alias ExAgent.Session.Snapshot, as: SessionSnapshot
  alias ExAgent.Continuation.{Record, Storage, Transition}

  @default_table __MODULE__

  # ---------------------------------------------------------------------------
  # GenServer (owns the table)
  # ---------------------------------------------------------------------------

  @doc false
  def start_link(opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)
    GenServer.start_link(__MODULE__, table, name: via(table))
  end

  @doc false
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  @impl true
  def init(table) do
    # Create the table if it doesn't already exist (e.g. across app restarts).
    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:ordered_set, :public, :named_table])
    end

    {:ok, table}
  end

  defp via(table), do: {:via, :global, {:exagent_store_ets, table}}

  # ---------------------------------------------------------------------------
  # ExAgent.Store — agents
  # ---------------------------------------------------------------------------

  @impl true
  def save_agent_snapshot(table, %Snapshot{} = snap) do
    binary = Snapshot.serialize(snap)
    legacy_write(table, {:agent, snap.agent_id}, binary)
  end

  @impl true
  def load_agent_snapshot(table, agent_id) do
    case :ets.lookup(table, {:agent, agent_id}) do
      [{_, binary}] ->
        case Storage.snapshot(binary, :agent, agent_id) do
          {:ok, %Snapshot{} = snap} -> {:ok, snap}
          {:error, _} = e -> e
        end

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def list_agent_snapshots(table) do
    :ets.match(table, {{:agent, :"$1"}, :"$2"})
    |> Enum.flat_map(fn [id, binary] ->
      case Storage.snapshot(binary, :agent, id) do
        {:ok, %Snapshot{} = snap} -> [snap]
        {:error, _} -> []
      end
    end)
  end

  @impl true
  def delete_agent_snapshot(table, agent_id) do
    legacy_write(table, {:agent, agent_id}, nil)
  end

  # ---------------------------------------------------------------------------
  # ExAgent.Store — sessions. Stored as JSON keyed by session_id, round-tripping
  # through Session.Snapshot.serialize/deserialize (strict JSON, no opaque
  # terms — same rule as agent snapshots).
  # ---------------------------------------------------------------------------

  @impl true
  def save_session_snapshot(table, %SessionSnapshot{} = snap) do
    binary = SessionSnapshot.serialize(snap)
    legacy_write(table, {:session, snap.session_id}, binary)
  end

  @impl true
  def load_session_snapshot(table, session_id) do
    case :ets.lookup(table, {:session, session_id}) do
      [{_, binary}] ->
        case Storage.snapshot(binary, :session, session_id) do
          {:ok, %SessionSnapshot{} = snap} -> {:ok, snap}
          {:error, _} = e -> e
        end

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def delete_session_snapshot(table, session_id) do
    legacy_write(table, {:session, session_id}, nil)
  end

  @impl true
  def capabilities(table),
    do: %{continuation: if(record_owner(table), do: :atomic, else: :none), durability: :ephemeral}

  @impl true
  def load_record(table, key) do
    with {:ok, physical} <- Record.key(key),
         {:ok, record} <- Storage.record(lookup(table, physical), key) do
      if is_nil(record), do: {:error, :not_found}, else: {:ok, record}
    end
  end

  @impl true
  def transition(table, key, expected, command) do
    case record_owner(table) do
      nil -> {:error, :unsupported_store_capability}
      owner -> GenServer.call(owner, {:transition, key, expected, command})
    end
  end

  # Raw ETS tids are an existing snapshot-only consumer (framework evals). They
  # do not gain atomic continuation capabilities without our serialized owner.
  # Compare-and-swap preserves their snapshot API without a check/write gap that
  # could overwrite a record inserted through a different configuration.
  defp legacy_write(table, key, bytes) do
    case record_owner(table) do
      nil -> legacy_cas(table, key, bytes, 20)
      owner -> GenServer.call(owner, {:legacy, key, bytes})
    end
  end

  defp legacy_cas(_, _, _, 0), do: {:error, :conflict}

  defp legacy_cas(table, key, bytes, attempts) do
    current = lookup(table, key)

    with :ok <- Storage.legacy_writable(current) do
      changed =
        case {current, bytes} do
          {nil, nil} ->
            true

          {nil, value} ->
            :ets.insert_new(table, {key, value})

          {old, nil} ->
            :ets.select_delete(table, [{{key, old}, [], [true]}]) == 1

          {old, value} ->
            :ets.select_replace(table, [{{key, old}, [], [{:const, {key, value}}]}]) == 1
        end

      if changed, do: :ok, else: legacy_cas(table, key, bytes, attempts - 1)
    end
  end

  defp record_owner(table) do
    name = :ets.info(table, :name)
    owner = :global.whereis_name({:exagent_store_ets, name})

    if is_pid(owner) and :ets.info(table, :owner) == owner and
         :ets.info(table, :type) == :ordered_set, do: owner, else: nil
  end

  @impl true
  def scan_records(table, namespace, query) do
    with {:ok, {limit, cursor}} <- Storage.scan_query(query),
         :ok <- ExAgent.RuntimeIdentity.validate(namespace, "") do
      case cursor && Storage.physical_parts(cursor) do
        nil when not is_nil(cursor) ->
          {:error, :invalid_scan}

        after_key ->
          first = if after_key, do: :ets.next(table, after_key), else: :ets.first(table)
          {rows, next} = scan(table, first, limit, [], nil)
          Storage.page(rows, namespace, next)
      end
    end
  end

  @impl true
  def handle_call({:legacy, key, binary}, _from, table) do
    reply =
      ExAgent.Store.protect(
        fn ->
          with :ok <- Storage.legacy_writable(lookup(table, key)) do
            write(table, key, binary)
            :ok
          end
        end,
        :save
      )

    {:reply, reply, table}
  end

  def handle_call({:transition, key, expected, command}, _from, table) do
    reply =
      ExAgent.Store.protect(
        fn ->
          with {:ok, physical} <- Record.key(key),
               {:ok, current} <- Storage.record(lookup(table, physical), key),
               {:ok, result} <-
                 Transition.apply(
                   current,
                   key,
                   expected,
                   command,
                   System.system_time(:millisecond)
                 ),
               {:ok, binary} <- encode_result(result, key) do
            unless result.replayed, do: write(table, physical, binary)
            {:ok, result}
          end
        end,
        :load
      )

    {:reply, reply, table}
  end

  defp encode_result(%{record: nil}, _), do: {:ok, nil}
  defp encode_result(%{record: record}, key), do: Record.encode(record, key)

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      [{_, binary}] -> binary
      [] -> nil
    end
  end

  defp write(table, key, nil), do: :ets.delete(table, key)
  defp write(table, key, binary), do: :ets.insert(table, {key, binary})

  defp scan(_table, :"$end_of_table", _left, acc, _last), do: {Enum.reverse(acc), nil}
  defp scan(_table, _key, 0, acc, last), do: {Enum.reverse(acc), last}

  defp scan(table, key, left, acc, _last) do
    next = :ets.next(table, key)
    last = Storage.physical(key)

    case :ets.lookup(table, key) do
      [{_, binary}] -> scan(table, next, left - 1, [{last, binary} | acc], last)
      [] -> scan(table, next, left - 1, acc, last)
    end
  end
end
