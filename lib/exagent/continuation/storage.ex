defmodule ExAgent.Continuation.Storage do
  @moduledoc false
  alias ExAgent.Continuation.Record
  alias ExAgent.RuntimeIdentity
  alias ExAgent.Server.Snapshot
  alias ExAgent.Session.Snapshot, as: SessionSnapshot

  def record(nil, _), do: {:ok, nil}

  def record(binary, key) do
    with {:ok, value} <- Jason.decode(binary) do
      if is_map(value) and Map.has_key?(value, "record_version"),
        do: Record.decode(binary, key),
        else: {:error, :legacy_snapshot}
    else
      _ -> {:error, :invalid_record}
    end
  end

  # Used within the SAME write lock/transaction as the legacy mutation.
  def legacy_writable(nil), do: :ok

  def legacy_writable(binary) do
    case Jason.decode(binary) do
      {:ok, map} when is_map(map) ->
        if Map.has_key?(map, "record_version"), do: {:error, :atomic_record_required}, else: :ok

      _ ->
        {:error, :invalid_snapshot}
    end
  end

  def snapshot(binary, kind, id) do
    codec = if kind == :agent, do: Snapshot, else: SessionSnapshot

    with {:ok, map} when is_map(map) <- Jason.decode(binary) do
      if Map.has_key?(map, "record_version") do
        {:error, :atomic_record_required}
      else
        with {:ok, snapshot} <- codec.deserialize(binary), do: codec.validate(snapshot, id)
      end
    else
      _ -> {:error, :invalid_snapshot}
    end
  end

  def scan_row(kind, id, binary, namespace) do
    case RuntimeIdentity.decode(id) do
      {:ok, {^namespace, ^kind, _} = key} ->
        case record(binary, key) do
          {:error, :legacy_snapshot} -> {:ok, nil}
          result -> result
        end

      _ ->
        {:ok, nil}
    end
  end

  def scan_query(query) when is_map(query) do
    limit = Map.get(query, :limit, 50)
    after_key = Map.get(query, :after)

    if Enum.all?(Map.keys(query), &(&1 in [:limit, :after])) and
         is_integer(limit) and limit in 1..100 and
         (is_nil(after_key) or (is_binary(after_key) and byte_size(after_key) <= 4096)),
       do: {:ok, {limit, after_key}},
       else: {:error, :invalid_scan}
  end

  def scan_query(_), do: {:error, :invalid_scan}

  def physical({kind, id}), do: Atom.to_string(kind) <> ":" <> id
  def physical_parts("agent:" <> id), do: {:agent, id}
  def physical_parts("session:" <> id), do: {:session, id}
  def physical_parts(_), do: nil

  def page(rows, namespace, cursor) do
    Enum.reduce_while(rows, {:ok, []}, fn {physical, binary}, {:ok, acc} ->
      case physical_parts(physical) do
        {kind, id} ->
          case scan_row(kind, id, binary, namespace) do
            {:ok, nil} -> {:cont, {:ok, acc}}
            {:ok, record} -> {:cont, {:ok, [record | acc]}}
            {:error, _} = error -> {:halt, error}
          end

        nil ->
          {:cont, {:ok, acc}}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, %{records: Enum.reverse(records), cursor: cursor}}
      error -> error
    end
  end
end
