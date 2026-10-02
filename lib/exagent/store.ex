defmodule ExAgent.Store do
  @moduledoc """
  Behaviour for persisting agent/session snapshots and optional atomic records.

   ExAgent never owns a database: the store is a pluggable behaviour. The optional
  `ExAgent.Store.ETS` keeps snapshots in an in-process ETS table (dev/test); a
  `ExAgent.Store.Postgres` uses the application's Repo. Its continuation SQL
  protocol requires separate real-backend qualification before claiming G3.

  Atomic continuation operations are experimental, optional and data-only. They
  require a trusted `scoped/2` descriptor and explicit durability admission.
  Legacy snapshot operations reject a continuation envelope; legacy lists omit
  it, preventing an unintegrated runtime from executing its embedded snapshot.

  ## The contract (what a store must do)

    * `save_agent_snapshot/2`   — persist a snapshot, keyed by its `agent_id`.
    * `load_agent_snapshot/2`   — fetch a snapshot by `agent_id`.
    * `list_agent_snapshots/1`  — list all persisted agent snapshots.
    * `delete_agent_snapshot/2` — remove a snapshot by `agent_id`.
    * `save_session_snapshot/2` / `load_session_snapshot/2` — the session
      counterparts (used by `ExAgent.Session` from Phase 3).

  ## Portability rule

  Implementations MUST round-trip snapshots through a portable encoding (JSON
  for the ETS impl), never `term_to_binary` of arbitrary terms. This guarantees
  the same data can land in Postgres later without redesign, and refuses to
   persist non-serializable state (pids, closures). JSON does not redact secrets.

   Save replaces one complete snapshot atomically and returns `:ok` only after
   the backend confirms the write. Error/timeout can mean an unknown write
   outcome. There must be one logical writer per key; this contract does not
   provide distributed locking or replay of external effects. Adapter IO must
   be bounded: a synchronous blocked adapter also blocks its runtime owner.

  A store is referenced as `{module, config}` where `config` is opaque to
  ExAgent (e.g. an ETS table name). `normalize/1` turns friendly forms into that
  tuple; `nil` means "no store" (the default — one-shot friendly).
  """

  alias ExAgent.Server.Snapshot
  alias ExAgent.Session.Snapshot, as: SessionSnapshot
  alias ExAgent.Store.Scope
  alias ExAgent.RuntimeIdentity
  alias ExAgent.Continuation.{Record, Transition}

  @type agent_snapshot :: Snapshot.t()
  @type session_snapshot :: SessionSnapshot.t()
  @type t :: {module(), term()} | scoped()
  @opaque scoped :: %Scope{store: {module(), term()}, namespace: String.t()}

  @doc "Persist an agent snapshot, keyed by its `agent_id`."
  @callback save_agent_snapshot(config :: term(), snapshot :: agent_snapshot()) ::
              :ok | {:error, term()}

  @doc "Load an agent snapshot by `agent_id`, or `{:error, :not_found}`."
  @callback load_agent_snapshot(config :: term(), agent_id :: String.t()) ::
              {:ok, agent_snapshot()} | {:error, :not_found | term()}

  @doc "List every persisted agent snapshot."
  @callback list_agent_snapshots(config :: term()) :: [agent_snapshot()]

  @doc "Delete an agent snapshot by `agent_id`."
  @callback delete_agent_snapshot(config :: term(), agent_id :: String.t()) :: :ok

  @doc "Persist a session snapshot, keyed by `session_id` (Phase 3)."
  @callback save_session_snapshot(config :: term(), snapshot :: session_snapshot()) ::
              :ok | {:error, term()}

  @doc "Load a session snapshot by `session_id` (Phase 3)."
  @callback load_session_snapshot(config :: term(), session_id :: String.t()) ::
              {:ok, session_snapshot()} | {:error, :not_found | term()}

  @doc "Delete a session snapshot by `session_id` (Phase 3)."
  @callback delete_session_snapshot(config :: term(), session_id :: String.t()) :: :ok

  @optional_callbacks [
    save_session_snapshot: 2,
    load_session_snapshot: 2,
    delete_session_snapshot: 2,
    capabilities: 1,
    load_record: 2,
    transition: 4,
    scan_records: 3
  ]

  @type record_key :: {String.t(), :agent | :session, String.t()}
  @callback capabilities(term()) :: %{
              continuation: :atomic | :none,
              durability: :ephemeral | :durable
            }
  @callback load_record(term(), record_key()) :: {:ok, map()} | {:error, term()}
  @callback transition(term(), record_key(), :absent | pos_integer(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback scan_records(term(), String.t(), map()) :: {:ok, map()} | {:error, term()}

  @doc "Optional atomic capability; unknown or malformed declarations fail closed."
  def capabilities(%Scope{store: store}), do: capabilities(store)

  def capabilities({mod, config}) do
    _ = Code.ensure_loaded(mod)

    if function_exported?(mod, :capabilities, 1) do
      case protect(fn -> {:ok, mod.capabilities(config)} end, :load) do
        {:ok, %{continuation: :atomic, durability: durability} = caps}
        when durability in [:ephemeral, :durable] ->
          if Enum.all?([load_record: 2, transition: 4, scan_records: 3], fn {f, a} ->
               function_exported?(mod, f, a)
             end), do: caps, else: %{continuation: :none, durability: :unknown}

        _ ->
          %{continuation: :none, durability: :unknown}
      end
    else
      %{continuation: :none, durability: :unknown}
    end
  end

  def capabilities(_), do: %{continuation: :none, durability: :unknown}

  @doc "Admit a continuation before effects; callers must explicitly choose durability."
  def require_continuation(%Scope{} = store, durability)
      when durability in [:ephemeral, :durable] do
    case capabilities(store) do
      %{continuation: :atomic, durability: actual} when actual == durability -> :ok
      _ -> {:error, :unsupported_store_capability}
    end
  end

  def require_continuation(_, _), do: {:error, :unsupported_store_capability}

  @doc "Read the current record using the trusted Store.Scope namespace."
  def load_record(scope, kind, id) do
    with {:ok, {mod, config, key}} <- record_target(scope, kind, id),
         {:ok, record} <- protect(fn -> mod.load_record(config, key) end, :load),
         :ok <- Record.validate(record, key) do
      {:ok, record}
    end
  end

  @doc "Apply a closed data command atomically. A replayed receipt is not a new effect permit."
  def transition(scope, kind, id, expected, command) do
    with {:ok, {mod, config, key}} <- record_target(scope, kind, id),
         true <- expected == :absent or Record.positive?(expected),
         {:ok, command} <- Transition.command(command),
         {:ok, reply} <- protect(fn -> mod.transition(config, key, expected, command) end, :load),
         :ok <- validate_reply(reply, key, expected, command) do
      {:ok, reply}
    else
      false -> {:error, :invalid_revision}
      {:error, _} = error -> error
    end
  end

  @doc "Bounded page. Limit bounds physical rows examined, so a page can be empty with a cursor."
  def scan_records(%Scope{store: {mod, config}, namespace: namespace} = scope, query \\ %{}) do
    with %{continuation: :atomic} <- capabilities(scope),
         {:ok, {limit, _}} <- ExAgent.Continuation.Storage.scan_query(query),
         {:ok, %{records: records, cursor: cursor} = page} <-
           protect(fn -> mod.scan_records(config, namespace, query) end, :load),
         true <-
           is_list(records) and length(records) <= limit and (is_nil(cursor) or is_binary(cursor)),
         true <- Enum.all?(records, &valid_scanned?(&1, namespace)) do
      {:ok, page}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_store_return}
    end
  end

  defp valid_scanned?(%{"key" => [namespace, kind, id]} = r, namespace) do
    kind = Enum.find([:agent, :session], &(Atom.to_string(&1) == kind))
    Record.validate(r, {namespace, kind, id}) == :ok
  end

  defp valid_scanned?(_, _), do: false

  defp record_target(%Scope{store: {mod, config}, namespace: namespace} = store, kind, id) do
    with %{continuation: :atomic} <- capabilities(store),
         {:ok, _} <- Record.key({namespace, kind, id}) do
      {:ok, {mod, config, {namespace, kind, id}}}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_store_capability}
    end
  end

  defp record_target(_, _, _), do: {:error, :unsupported_store_capability}

  defp validate_reply(%{record: nil, receipt: nil, replayed: false}, _, _, %{
         "operation" => "delete"
       }),
       do: :ok

  defp validate_reply(
         %{record: record, receipt: receipt, replayed: replayed},
         key,
         expected,
         command
       )
       when is_boolean(replayed) do
    with :ok <- Record.validate(record, key),
         {:ok, digest} <- Transition.digest(key, expected, command),
         true <-
           is_map(receipt) and record["receipts"][command["operation_id"]] == receipt and
             receipt["digest"] == digest and record["record_id"] == command["record_id"] do
      :ok
    else
      _ -> {:error, :invalid_store_return}
    end
  end

  defp validate_reply(_, _, _, _), do: {:error, :invalid_store_return}

  @doc """
  Resolve a store option into a `{module, config}` tuple, or `nil` for "no store".

    * `nil`        → `nil` (no persistence — default).
    * `:ets`       → `{ExAgent.Store.ETS, ExAgent.Store.ETS}` (default table).
    * `{mod, cfg}` → as-is.
    * `mod`        → `{mod, []}`.
  """
  @spec normalize(term()) :: t() | nil
  def normalize(nil), do: nil
  def normalize(%Scope{} = scope), do: scope
  def normalize(:ets), do: {ExAgent.Store.ETS, ExAgent.Store.ETS}
  def normalize({mod, config}) when is_atom(mod), do: {mod, config}
  def normalize(mod) when is_atom(mod), do: {mod, []}

  @doc """
  Scope snapshot operations to an application-supplied namespace (nonempty UTF-8
  string). Nil preserves legacy keys. Use the same namespace on Server/Session
  and Event topic helpers; never obtain it from untrusted stored data.

  Existing snapshot callbacks receive versioned encoded IDs. Loads verify the
  exact stored ID before restoring its logical value; no legacy fallback occurs.
  Lists omit other namespaces and invalid entries. Direct backend calls bypass
  this dispatch boundary. This provides neither distributed claims nor access
  control against the application itself.
  """
  @spec scoped(term(), String.t() | nil) :: t() | nil
  def scoped(store, namespace) do
    case {RuntimeIdentity.validate(namespace, ""), normalize(store)} do
      {:ok, %Scope{namespace: ^namespace} = scope} -> scope
      {:ok, %Scope{}} -> raise ArgumentError, "store namespace mismatch"
      {:ok, nil} -> nil
      {:ok, normalized} when is_nil(namespace) -> normalized
      {:ok, normalized} -> %Scope{store: normalized, namespace: namespace}
      _ -> raise ArgumentError, "invalid namespace"
    end
  end

  @doc "Persist an agent snapshot via the resolved `{module, config}` tuple."
  @spec save_agent_snapshot(t(), Snapshot.t()) :: :ok | {:error, term()}
  def save_agent_snapshot(%Scope{} = scope, %Snapshot{} = snapshot),
    do: Scope.save(scope, :agent, snapshot)

  def save_agent_snapshot({mod, config}, %Snapshot{} = snapshot) do
    with :ok <- RuntimeIdentity.validate(nil, snapshot.agent_id),
         do: protect(fn -> mod.save_agent_snapshot(config, snapshot) end, :save)
  end

  @doc "Load an agent snapshot via the resolved tuple."
  @spec load_agent_snapshot(t(), String.t()) ::
          {:ok, Snapshot.t()} | {:error, term()}
  def load_agent_snapshot(%Scope{} = scope, agent_id), do: Scope.load(scope, :agent, agent_id)

  def load_agent_snapshot({mod, config}, agent_id) do
    with :ok <- RuntimeIdentity.validate(nil, agent_id),
         do: protect(fn -> mod.load_agent_snapshot(config, agent_id) end, :load)
  end

  @doc "List agent snapshots via the resolved tuple."
  @spec list_agent_snapshots(t()) :: [Snapshot.t()]
  def list_agent_snapshots(%Scope{} = scope), do: Scope.list(scope)

  def list_agent_snapshots({mod, config}) do
    mod.list_agent_snapshots(config)
    |> Enum.reject(&RuntimeIdentity.reserved?(&1.agent_id))
  end

  @doc "Delete an agent snapshot via the resolved tuple."
  @spec delete_agent_snapshot(t(), String.t()) :: :ok | {:error, term()}
  def delete_agent_snapshot(%Scope{} = scope, agent_id), do: Scope.delete(scope, :agent, agent_id)

  def delete_agent_snapshot({mod, config}, agent_id) do
    with :ok <- RuntimeIdentity.validate(nil, agent_id),
         do: mod.delete_agent_snapshot(config, agent_id)
  end

  @doc "Persist a session snapshot via the resolved tuple."
  @spec save_session_snapshot(t(), SessionSnapshot.t()) :: :ok | {:error, term()}
  def save_session_snapshot(%Scope{} = scope, %SessionSnapshot{} = snapshot),
    do: Scope.save(scope, :session, snapshot)

  def save_session_snapshot({mod, config}, %SessionSnapshot{} = snapshot) do
    with :ok <- RuntimeIdentity.validate(nil, snapshot.session_id),
         do: protect(fn -> mod.save_session_snapshot(config, snapshot) end, :save)
  end

  @doc "Load a session snapshot via the resolved tuple."
  @spec load_session_snapshot(t(), String.t()) ::
          {:ok, SessionSnapshot.t()} | {:error, term()}
  def load_session_snapshot(%Scope{} = scope, session_id),
    do: Scope.load(scope, :session, session_id)

  def load_session_snapshot({mod, config}, session_id) do
    with :ok <- RuntimeIdentity.validate(nil, session_id),
         do: protect(fn -> mod.load_session_snapshot(config, session_id) end, :load)
  end

  @doc "Delete a session snapshot via the resolved tuple."
  @spec delete_session_snapshot(t(), String.t()) :: :ok | {:error, term()}
  def delete_session_snapshot(%Scope{} = scope, session_id),
    do: Scope.delete(scope, :session, session_id)

  def delete_session_snapshot({mod, config}, session_id) do
    with :ok <- RuntimeIdentity.validate(nil, session_id),
         do: mod.delete_session_snapshot(config, session_id)
  end

  @doc false
  def protect(fun, operation) do
    case fun.() do
      :ok when operation == :save -> :ok
      {:ok, _} = result when operation == :load -> result
      {:error, _} = error -> error
      other -> {:error, {:invalid_store_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
