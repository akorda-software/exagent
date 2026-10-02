defmodule ExAgent.Store.Scope do
  @moduledoc false
  alias ExAgent.{RuntimeIdentity, Store}
  alias ExAgent.Server.Snapshot
  alias ExAgent.Session.Snapshot, as: SessionSnapshot

  @enforce_keys [:store, :namespace]
  defstruct [:store, :namespace]
  @type t :: %__MODULE__{store: {module(), term()}, namespace: String.t()}

  def save(%__MODULE__{store: {mod, config}, namespace: namespace}, kind, snapshot) do
    {field, codec, save, _load, _delete} = contract(kind)

    with {:ok, key} <- RuntimeIdentity.key(namespace, kind, Map.get(snapshot, field)),
         {:ok, snapshot} <- codec.validate(snapshot, Map.get(snapshot, field)) do
      Store.protect(fn -> apply(mod, save, [config, Map.put(snapshot, field, key)]) end, :save)
    end
  end

  def load(%__MODULE__{store: {mod, config}, namespace: namespace}, kind, id) do
    {field, codec, _save, load, _delete} = contract(kind)

    with {:ok, key} <- RuntimeIdentity.key(namespace, kind, id),
         {:ok, raw} <- Store.protect(fn -> apply(mod, load, [config, key]) end, :load),
         {:ok, snapshot} <- codec.validate(raw, key) do
      # Exact canonical key equality includes namespace, kind and logical ID.
      {:ok, Map.put(snapshot, field, id)}
    end
  end

  def delete(%__MODULE__{store: {mod, config}, namespace: namespace}, kind, id) do
    {_field, _codec, _save, _load, delete} = contract(kind)

    with {:ok, key} <- RuntimeIdentity.key(namespace, kind, id) do
      Store.protect(fn -> apply(mod, delete, [config, key]) end, :save)
    end
  end

  def list(%__MODULE__{store: {mod, config}, namespace: namespace} = scope) do
    mod.list_agent_snapshots(config)
    |> Enum.flat_map(fn snapshot ->
      with %Snapshot{agent_id: key} <- snapshot,
           {:ok, {^namespace, :agent, id}} <- RuntimeIdentity.decode(key),
           {:ok, validated} <- load(scope, :agent, id) do
        [validated]
      else
        _ -> []
      end
    end)
    |> Enum.uniq_by(& &1.agent_id)
  end

  defp contract(:agent),
    do: {:agent_id, Snapshot, :save_agent_snapshot, :load_agent_snapshot, :delete_agent_snapshot}

  defp contract(:session),
    do:
      {:session_id, SessionSnapshot, :save_session_snapshot, :load_session_snapshot,
       :delete_session_snapshot}
end
