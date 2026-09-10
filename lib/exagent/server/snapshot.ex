defmodule ExAgent.Server.Snapshot do
  @moduledoc """
  Version 2 checkpoint of conversational data, with a bounded reader for v1.

  Restores confirmed history and usage, not live models, tasks or external effects.
  The app supplies the live template. JSON rejects non-encodable values but does
  not redact secrets contained in messages, metadata or provider data.
  """
  alias ExAgent.{Message, SnapshotData}
  alias ExAgent.Message.{Part, Request, Response, Usage}

  @derive Jason.Encoder
  @enforce_keys [:agent_id]
  defstruct version: 2,
            agent_id: nil,
            message_history: nil,
            usage: %{},
            metadata: %{},
            provider_state: nil,
            saved_at: nil,
            revision: 0

  @type t :: %__MODULE__{}

  def new(opts) do
    %__MODULE__{
      agent_id: Keyword.fetch!(opts, :agent_id),
      message_history: Message.to_json(Keyword.get(opts, :history, [])),
      usage: SnapshotData.usage_map(Keyword.get(opts, :usage)),
      metadata: Keyword.get(opts, :metadata, %{}),
      provider_state: Keyword.get(opts, :provider_state),
      revision: Keyword.get(opts, :revision, 0),
      saved_at: DateTime.utc_now()
    }
  end

  def serialize(%__MODULE__{} = snapshot), do: Jason.encode!(snapshot)

  def deserialize(binary), do: SnapshotData.decode(binary, &from_map/1)

  @doc "Validate snapshots returned by any Store, including custom implementations."
  def validate(%__MODULE__{} = snapshot, expected_id) do
    with {:ok, snapshot} <- deserialize(serialize(snapshot)),
         true <- snapshot.agent_id == expected_id do
      {:ok, snapshot}
    else
      false -> {:error, :snapshot_id_mismatch}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :invalid_snapshot}
  end

  def validate(_, _), do: {:error, :invalid_snapshot}

  def messages(%__MODULE__{message_history: nil}), do: {:ok, []}

  def messages(%__MODULE__{message_history: binary}) when is_binary(binary) do
    case Message.from_json(binary) do
      {:ok, messages} when is_list(messages) ->
        if Enum.all?(messages, &valid_message?/1),
          do: {:ok, messages},
          else: {:error, :invalid_history}

      _ ->
        {:error, :invalid_history}
    end
  rescue
    _ -> {:error, :invalid_history}
  end

  def messages(_), do: {:error, :invalid_history}

  # The Message decoder is polymorphic; validate the protocol tree at its boundary.
  # Content/args are application JSON, not additional protocol nodes to traverse.
  defp valid_message?(%Request{parts: parts}) when is_list(parts),
    do: Enum.all?(parts, &request_part?/1)

  defp valid_message?(%Response{parts: parts, usage: usage}) when is_list(parts),
    do: (is_nil(usage) or is_struct(usage, Usage)) and Enum.all?(parts, &response_part?/1)

  defp valid_message?(_), do: false

  defp request_part?(%mod{}) when mod in [Part.System, Part.User, Part.ToolReturn, Part.Retry],
    do: true

  defp request_part?(_), do: false
  defp response_part?(%mod{}) when mod in [Part.Text, Part.Thinking, Part.ToolCall], do: true
  defp response_part?(_), do: false

  def usage_struct(%__MODULE__{usage: usage}),
    do: usage |> SnapshotData.usage_map() |> SnapshotData.usage_struct()

  defp from_map(map) do
    version = Map.get(map, "version", 1)
    usage = Map.get(map, "usage", %{})
    revision = Map.get(map, "revision", 0)

    cond do
      version not in [1, 2] ->
        {:error, {:unsupported_snapshot_version, version}}

      not is_binary(map["agent_id"]) ->
        {:error, :invalid_agent_id}

      not SnapshotData.usage_valid?(usage) ->
        {:error, :invalid_usage}

      not SnapshotData.counter?(revision) ->
        {:error, :invalid_revision}

      not is_map(Map.get(map, "metadata", %{})) ->
        {:error, :invalid_metadata}

      not (is_nil(map["provider_state"]) or is_map(map["provider_state"])) ->
        {:error, :invalid_provider_state}

      true ->
        with {:ok, saved_at} <- SnapshotData.timestamp(map["saved_at"]) do
          snapshot = %__MODULE__{
            agent_id: map["agent_id"],
            message_history: map["message_history"],
            usage: usage,
            metadata: Map.get(map, "metadata", %{}),
            provider_state: map["provider_state"],
            saved_at: saved_at,
            revision: revision
          }

          with {:ok, _} <- messages(snapshot), do: {:ok, snapshot}
        end
    end
  end
end
