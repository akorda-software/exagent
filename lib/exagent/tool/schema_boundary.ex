defmodule ExAgent.Tool.SchemaBoundary do
  @moduledoc false

  alias ExAgent.Tool.JSON

  @literal_keywords ~w(enum const examples default)
  @map_keywords ~w($defs definitions properties patternProperties dependentSchemas dependencies)
  @uri_keywords ~w($ref $dynamicRef $recursiveRef $id $schema)

  # Inspect data as data, except when a reference makes it a schema. Candidate
  # resources include nested IDs; checking all candidates avoids trusting a URI
  # namespace when deciding whether code can be reached. This is deliberately
  # conservative for documents reusing the same pointer in multiple resources.
  def prepare(schema) do
    nodes = all_maps(schema, "")

    resources = [
      {schema, ""} | Enum.filter(nodes, fn {node, _} -> is_binary(Map.get(node, "$id")) end)
    ]

    dialect =
      if is_map(schema),
        do: Map.get(schema, "$schema", "https://json-schema.org/draft/2020-12/schema"),
        else: nil

    with {:ok, seen} <- walk([{schema, ""}], MapSet.new(), resources, nodes, dialect) do
      {:ok, prune_defaults(schema, "", seen)}
    end
  end

  defp walk([], seen, _, _, _), do: {:ok, seen}

  defp walk([{schema, path} | rest], seen, resources, nodes, dialect) do
    if MapSet.member?(seen, path) do
      walk(rest, seen, resources, nodes, dialect)
    else
      with :ok <- safe_node(schema, path),
           :ok <- same_dialect(schema, path, dialect) do
        children = children(schema, path)
        targets = reference_targets(schema, resources, nodes)
        walk(children ++ targets ++ rest, MapSet.put(seen, path), resources, nodes, dialect)
      end
    end
  end

  # JSV inherits the root dialect even across embedded resource IDs. Reject
  # mixed dialects rather than silently applying the parent's semantics.
  defp same_dialect(%{"$schema" => declared}, path, root) do
    if is_binary(declared) and is_binary(root) and
         String.trim_trailing(declared, "#") == String.trim_trailing(root, "#") do
      :ok
    else
      JSON.error(
        JSON.pointer(path, "$schema"),
        "$schema",
        "Nested schemas must use the root dialect"
      )
    end
  end

  defp same_dialect(_, _, _), do: :ok

  # JSV scans default data for IDs, unlike const/enum/examples. Omit only inert
  # defaults from the private build projection, after checking all reachable
  # schemas. Keep referenced default subtrees verbatim: they can serve as both
  # data and schemas, and changing a literal inside them could change const/enum.
  defp prune_defaults(schema, path, seen) when is_map(schema) do
    schema
    |> Enum.flat_map(fn
      {"default", value} ->
        child = JSON.pointer(path, "default")

        if Enum.any?(seen, &(&1 == child or String.starts_with?(&1, child <> "/"))),
          do: [{"default", value}],
          else: []

      {key, value} when key in @literal_keywords ->
        [{key, value}]

      {key, value} when key in @map_keywords and is_map(value) ->
        [
          {key,
           Map.new(value, fn {name, sub} ->
             {name, prune_defaults(sub, JSON.pointer(JSON.pointer(path, key), name), seen)}
           end)}
        ]

      {key, value} ->
        [{key, prune_defaults(value, JSON.pointer(path, key), seen)}]
    end)
    |> Map.new()
  end

  defp prune_defaults(list, path, seen) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {value, i} ->
      prune_defaults(value, JSON.pointer(path, Integer.to_string(i)), seen)
    end)
  end

  defp prune_defaults(value, _, _), do: value

  defp safe_node(schema, path) when is_map(schema) do
    Enum.reduce_while(schema, :ok, fn {key, value}, :ok ->
      result =
        cond do
          key in ["x-jsv-cast", "jsv-cast"] ->
            JSON.error(JSON.pointer(path, key), key, "Executable schema casts are not supported")

          key in @uri_keywords and is_binary(value) and
              String.downcase(URI.parse(value).scheme || "") == "jsv" ->
            JSON.error(JSON.pointer(path, key), key, "Module schema references are not supported")

          true ->
            :ok
        end

      case result do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp safe_node(_, _), do: :ok

  defp children(schema, path) when is_map(schema) do
    Enum.flat_map(schema, fn
      {key, _value} when key in @literal_keywords ->
        []

      {key, value} when key in @map_keywords and is_map(value) ->
        Enum.map(value, fn {name, child} ->
          {child, JSON.pointer(JSON.pointer(path, key), name)}
        end)

      {key, value} ->
        [{value, JSON.pointer(path, key)}]
    end)
  end

  defp children(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {value, i} -> {value, JSON.pointer(path, Integer.to_string(i))} end)
  end

  defp children(_, _), do: []

  defp reference_targets(schema, resources, nodes) when is_map(schema) do
    targets =
      Enum.flat_map(["$ref", "$dynamicRef", "$recursiveRef"], fn key ->
        case Map.get(schema, key) do
          ref when is_binary(ref) -> targets(URI.parse(ref).fragment, resources, nodes)
          _ -> []
        end
      end)

    # A pointer can skip over a resource boundary hidden in literal data. Its
    # namespace/dialect still affects the target, so check those ancestors too.
    ancestors =
      Enum.filter(resources, fn {_, parent} ->
        Enum.any?(targets, fn {_, path} ->
          parent == "" or path == parent or String.starts_with?(path, parent <> "/")
        end)
      end)

    targets ++ ancestors
  end

  defp reference_targets(_, _, _), do: []

  defp targets(fragment, resources, nodes) do
    # Match JSV 0.22's fragment handling: split first, then decode each pointer
    # segment. Decoding before splitting would miss keys with encoded slashes.
    case fragment || "" do
      "" ->
        resources

      "/" ->
        resources

      "/" <> pointer ->
        parts =
          pointer
          |> String.split("/")
          |> Enum.map(
            &(&1
              |> String.replace("~1", "/")
              |> String.replace("~0", "~")
              |> URI.decode())
          )

        Enum.flat_map(resources, fn {schema, path} -> locate(schema, path, parts) end)

      anchor ->
        Enum.filter(nodes, fn {node, _} ->
          Map.get(node, "$anchor") == anchor or Map.get(node, "$dynamicAnchor") == anchor or
            Map.get(node, "$id") == "#" <> anchor
        end)
    end
  end

  defp locate(value, path, []), do: [{value, path}]

  defp locate(map, path, [key | rest]) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> locate(value, JSON.pointer(path, key), rest)
      :error -> []
    end
  end

  defp locate(list, path, [key | rest]) when is_list(list) do
    case Integer.parse(key) do
      {index, ""} when index >= 0 ->
        case Enum.fetch(list, index) do
          {:ok, value} -> locate(value, JSON.pointer(path, key), rest)
          :error -> []
        end

      _ ->
        []
    end
  end

  defp locate(_, _, _), do: []

  defp all_maps(map, path) when is_map(map) do
    [
      {map, path}
      | Enum.flat_map(map, fn {key, value} -> all_maps(value, JSON.pointer(path, key)) end)
    ]
  end

  defp all_maps(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, i} ->
      all_maps(value, JSON.pointer(path, Integer.to_string(i)))
    end)
  end

  defp all_maps(_, _), do: []
end
