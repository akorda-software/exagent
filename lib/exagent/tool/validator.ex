defmodule ExAgent.Tool.Validator do
  @moduledoc false

  alias ExAgent.Tool.{JSON, SchemaBoundary}

  @build_opts [
    resolver: [],
    atoms: false,
    warnings: :silent,
    vocabularies: %{
      "https://json-schema.org/draft/2020-12/vocab/validation" =>
        ExAgent.Tool.ValidationVocabulary,
      "https://json-schema.org/draft-07/--fallback--vocab/validation" =>
        ExAgent.Tool.ValidationVocabulary
    }
  ]
  @validate_opts [cast: false, cast_formats: false]
  @drafts [
    "https://json-schema.org/draft/2020-12/schema",
    "http://json-schema.org/draft-07/schema"
  ]

  def prepare(schema) do
    with {:ok, normal} <- JSON.normalize(schema),
         {:ok, build_schema} <- SchemaBoundary.prepare(normal),
         :ok <- validate_schema(normal),
         {:ok, root} <- JSV.build(build_schema, @build_opts) do
      {:ok, root}
    else
      {:error, errors} when is_list(errors) -> {:error, errors}
      {:error, _} -> JSON.error("", "schema", "Invalid or unresolved JSON Schema")
    end
  rescue
    _ -> JSON.error("", "schema", "Invalid or unsupported JSON Schema")
  end

  defp validate_schema(schema) when is_boolean(schema), do: :ok

  defp validate_schema(schema) when is_map(schema) do
    meta = Map.get(schema, "$schema", hd(@drafts))
    meta = if is_binary(meta), do: String.trim_trailing(meta, "#"), else: meta

    if meta in @drafts do
      with {:ok, root} <- JSV.build(%{"$ref" => meta}, @build_opts),
           {:ok, _} <- validate(schema, root) do
        :ok
      end
    else
      JSON.error("/$schema", "$schema", "Unsupported JSON Schema dialect")
    end
  end

  defp validate_schema(_), do: JSON.error("", "schema", "Expected an object or boolean schema")

  def validate(data, root) do
    case JSV.validate(data, root, @validate_opts) do
      {:ok, _} -> {:ok, data}
      {:error, error} -> {:error, errors(JSV.normalize_error(error, keys: :strings))}
    end
  rescue
    _ -> JSON.error("", "validation", "JSON Schema validation could not be completed")
  end

  defp errors(%{"details" => details}), do: Enum.flat_map(details, &errors/1)

  defp errors(%{"instanceLocation" => path, "errors" => errors}) do
    Enum.flat_map(errors, fn error ->
      [
        %{path: String.trim_leading(path, "#"), keyword: error["kind"], message: error["message"]}
        | errors(error)
      ]
    end)
  end

  defp errors(_), do: []
end
