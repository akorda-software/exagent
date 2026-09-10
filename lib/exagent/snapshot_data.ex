defmodule ExAgent.SnapshotData do
  @moduledoc false
  alias ExAgent.Message.Usage

  def json(value), do: Jason.decode!(Jason.encode!(value))
  def counter?(n), do: is_integer(n) and n >= 0
  def id?(id), do: is_binary(id) or is_integer(id)

  def usage_map(%Usage{} = usage) do
    %{
      "input_tokens" => usage.input_tokens || 0,
      "output_tokens" => usage.output_tokens || 0,
      "details" => json(usage.details || %{})
    }
  end

  def usage_map(nil), do: usage_map(%Usage{input_tokens: 0, output_tokens: 0})
  def usage_map(map) when is_map(map), do: json(map)

  def usage_valid?(usage) when is_map(usage) do
    counter?(Map.get(usage, "input_tokens", 0)) and
      counter?(Map.get(usage, "output_tokens", 0)) and
      is_map(Map.get(usage, "details", %{}))
  end

  def usage_valid?(_), do: false

  def usage_struct(map) do
    %Usage{
      input_tokens: Map.get(map, "input_tokens", 0),
      output_tokens: Map.get(map, "output_tokens", 0),
      details: Map.get(map, "details", %{})
    }
  end

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
