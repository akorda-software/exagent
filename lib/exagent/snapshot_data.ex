defmodule ExAgent.SnapshotData do
  @moduledoc false
  alias ExAgent.Message.Usage

  def json(value), do: Jason.decode!(Jason.encode!(value))
  def counter?(n), do: is_integer(n) and n >= 0
  def id?(id), do: is_binary(id) or is_integer(id)

  def usage_map(%Usage{} = usage) do
    usage |> Usage.to_map() |> json()
  end

  def usage_map(nil), do: usage_map(Usage.qualify(nil))
  def usage_map(map) when is_map(map), do: json(map)

  def usage_valid?(usage) when is_map(usage) do
    Usage.from_map!(usage)
    true
  rescue
    _ -> false
  end

  def usage_valid?(_), do: false

  def usage_struct(map), do: Usage.from_map!(map)

  def timestamp(nil), do: {:ok, nil}
  def timestamp(%DateTime{} = date), do: {:ok, date}

  def timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} -> {:ok, date}
      _ -> {:error, :invalid_timestamp}
    end
  end

  def timestamp(_), do: {:error, :invalid_timestamp}

  def decode(binary, fun) do
    case Jason.decode(binary) do
      {:ok, map} when is_map(map) -> fun.(map)
      _ -> {:error, :invalid_snapshot}
    end
  rescue
    _ -> {:error, :invalid_snapshot}
  catch
    _, _ -> {:error, :invalid_snapshot}
  end
end
