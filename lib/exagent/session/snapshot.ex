defmodule ExAgent.Session.Snapshot do
  @moduledoc """
  Version 2 JSON checkpoint of coordination data; reads valid v1 data.

  Decoding never loads modules or constructs structs chosen by stored bytes.
  `restore/3` uses only the policy explicitly supplied by the host app. Custom
  policies opt in with TurnPolicy.snapshot/1 and restore_snapshot/3. Participant
  refs and live processes are not stored. JSON does not redact secret strings.
  """
  alias ExAgent.{SnapshotData, Session.PolicyCodec}

  defstruct [
    :session_id,
    :shared_state,
    :participants,
    :policy_mod,
    :policy_state,
    :current,
    :status,
    :saved_at,
    seq: 0,
    metadata: %{},
    version: 2,
    policy_version: 1,
    revision: 0
  ]

  @type t :: %__MODULE__{}
  @statuses [:created, :running, :paused, :closed, :done]

  def new(state) do
    unless Enum.all?(state.participants, fn {id, _} -> SnapshotData.id?(id) end) do
      raise ArgumentError, "persisted participant ids must be strings or integers"
    end

    case PolicyCodec.dump(state.policy_state) do
      {:ok, version, data} ->
        %__MODULE__{
          session_id: state.session_id,
          shared_state: state.shared_state,
          participants: Enum.map(state.participants, fn {id, p} -> %{id: id, kind: p.kind} end),
          policy_mod: Atom.to_string(state.policy_mod),
          policy_state: data,
          policy_version: version,
          current: state.current,
          status: state.status,
          seq: state.seq,
          metadata: state.metadata,
          revision: state.revision,
          saved_at: DateTime.utc_now()
        }

      {:error, reason} ->
        raise ArgumentError, "cannot snapshot policy: #{inspect(reason)}"
    end
  end

  def serialize(%__MODULE__{} = snapshot),
    do: snapshot |> Map.from_struct() |> Jason.encode!()

  def deserialize(binary), do: SnapshotData.decode(binary, &from_map/1)

  def validate(%__MODULE__{} = snapshot, expected_id) do
    with {:ok, snapshot} <- deserialize(serialize(snapshot)),
         true <- snapshot.session_id == expected_id do
      {:ok, snapshot}
    else
      false -> {:error, :snapshot_id_mismatch}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :invalid_snapshot}
  end

  def validate(_, _), do: {:error, :invalid_snapshot}

  def restore(snapshot, trusted_mod, context) do
    if snapshot.policy_mod == Atom.to_string(trusted_mod) do
      PolicyCodec.restore(trusted_mod, snapshot.policy_version, snapshot.policy_state, context)
    else
      {:error, :snapshot_policy_mismatch}
    end
  rescue
    _ -> {:error, :invalid_policy_state}
  catch
    _, _ -> {:error, :invalid_policy_state}
  end

  defp from_map(map) do
    version = Map.get(map, "version", 1)
    status = Enum.find(@statuses, &(Atom.to_string(&1) == map["status"]))
    participants = map["participants"]

    cond do
      version not in [1, 2] ->
        {:error, {:unsupported_snapshot_version, version}}

      not is_binary(map["session_id"]) ->
        {:error, :invalid_session_id}

      is_nil(status) ->
        {:error, :invalid_status}

      not valid_participants?(participants) ->
        {:error, :invalid_participants}

      not SnapshotData.counter?(Map.get(map, "revision", 0)) ->
        {:error, :invalid_revision}

      not SnapshotData.counter?(Map.get(map, "seq", 0)) ->
        {:error, :invalid_seq}

      not is_map(Map.get(map, "metadata", %{})) ->
        {:error, :invalid_metadata}

      not is_binary(map["policy_mod"]) ->
        {:error, :invalid_policy_module}

      true ->
        with {:ok, date} <- SnapshotData.timestamp(map["saved_at"]),
             {:ok, data} <- policy_data(map, version) do
          roster =
            Enum.map(participants, fn p ->
              %{id: p["id"], kind: if(p["kind"] == "agent", do: :agent, else: :human)}
            end)

          current = map["current"]

          if (is_nil(current) or Enum.any?(roster, &(&1.id == current))) and
               (status != :running or not is_nil(current)) and
               (status not in [:created, :done] or is_nil(current)) do
            {:ok,
             %__MODULE__{
               session_id: map["session_id"],
               shared_state: map["shared_state"],
               participants: roster,
               policy_mod: map["policy_mod"],
               policy_state: data,
               policy_version: Map.get(map, "policy_version", 1),
               current: current,
               status: status,
               seq: Map.get(map, "seq", 0),
               revision: Map.get(map, "revision", 0),
               metadata: Map.get(map, "metadata", %{}),
               saved_at: date
             }}
          else
            {:error, :invalid_current}
          end
        end
    end
  end

  defp policy_data(map, 1) do
    expected = map["policy_mod"]

    case map["policy_state"] do
      %{"__struct__" => ^expected} = data ->
        {:ok, Map.delete(data, "__struct__")}

      _ ->
        {:error, :invalid_policy_state}
    end
  end

  defp policy_data(map, 2) do
    if is_integer(map["policy_version"]) and map["policy_version"] > 0,
      do: {:ok, map["policy_state"]},
      else: {:error, :invalid_policy_version}
  end

  defp valid_participants?(participants) when is_list(participants) do
    Enum.all?(participants, fn
      %{"id" => id, "kind" => kind} -> SnapshotData.id?(id) and kind in ["agent", "human"]
      _ -> false
    end) and length(participants) == MapSet.size(MapSet.new(participants, & &1["id"]))
  end

  defp valid_participants?(_), do: false
end
