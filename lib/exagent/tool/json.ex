defmodule ExAgent.Tool.JSON do
  @moduledoc false

  def normalize(value), do: normalize(value, "")

  # Ordered objects retain duplicate keys (including escaped spellings) so the
  # decoder, rather than a second JSON parser, establishes valid encoded data.
  def encoded_result(value) do
    with {:ok, encoded} <- Jason.encode(value, maps: :strict),
         {:ok, decoded} <- Jason.decode(encoded, objects: :ordered_objects),
         true <- unique_objects?(decoded) do
      {:ok, value}
    else
      _ -> result_error()
    end
  rescue
    _ -> result_error()
  catch
    _, _ -> result_error()
  end

  defp unique_objects?(%Jason.OrderedObject{values: pairs}) do
    keys = Enum.map(pairs, &elem(&1, 0))

    MapSet.size(MapSet.new(keys)) == length(keys) and
      Enum.all?(pairs, fn {_, value} -> unique_objects?(value) end)
  end

  defp unique_objects?(list) when is_list(list), do: Enum.all?(list, &unique_objects?/1)
  defp unique_objects?(_), do: true

  defp result_error,
    do: error("", "json", "Tool result must encode valid JSON with unique object keys")

  defp normalize(value, _) when is_boolean(value) or is_nil(value) or is_number(value),
    do: {:ok, value}

  defp normalize(value, path) when is_binary(value) do
    if String.valid?(value), do: {:ok, value}, else: error(path, "json", "Expected valid UTF-8")
  end

  defp normalize(value, path) when is_struct(value),
    do: error(path, "json", "Expected JSON data, not a struct")

  defp normalize(value, path) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, key} <- normalize_key(key, path),
           child = pointer(path, key),
           :ok <- unique_key(acc, key, child),
           {:ok, value} <- normalize(value, child) do
        {:cont, {:ok, Map.put(acc, key, value)}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp normalize(value, path) when is_list(value), do: normalize_list(value, path, 0, [])
  defp normalize(_, path), do: error(path, "json", "Expected a JSON value")

  defp normalize_list([], _, _, acc), do: {:ok, Enum.reverse(acc)}

  defp normalize_list([value | rest], path, index, acc) do
    case normalize(value, pointer(path, Integer.to_string(index))) do
      {:ok, value} -> normalize_list(rest, path, index + 1, [value | acc])
      {:error, _} = error -> error
    end
  end

  defp normalize_list(_, path, _, _), do: error(path, "json", "Expected a proper JSON array")

  defp normalize_key(key, path) when is_atom(key), do: normalize(Atom.to_string(key), path)
  defp normalize_key(key, path) when is_binary(key), do: normalize(key, path)
  defp normalize_key(_, path), do: error(path, "json", "Expected a string or atom object key")

  defp unique_key(map, key, path) do
    if Map.has_key?(map, key),
      do: error(path, "uniqueKeys", "Object keys collide in JSON"),
      else: :ok
  end

  def pointer(path, key),
    do: path <> "/" <> (key |> String.replace("~", "~0") |> String.replace("/", "~1"))

  def error(path, keyword, message),
    do: {:error, [%{path: path, keyword: keyword, message: message}]}
end
