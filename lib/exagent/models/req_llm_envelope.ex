defmodule ExAgent.Models.ReqLLMEnvelope do
  @moduledoc false
  alias ExAgent.Tool

  @codec "exagent.arguments/1"
  @annotations ~w(title description default examples deprecated readOnly writeOnly)
  @values ~w(type enum const required minimum maximum exclusiveMinimum exclusiveMaximum multipleOf minLength maxLength pattern format minItems maxItems uniqueItems minContains maxContains minProperties maxProperties)
  @single ~w(additionalProperties items contains propertyNames not if then else)
  @lists ~w(anyOf allOf oneOf prefixItems)
  @maps ~w(properties patternProperties dependentSchemas)

  def codec, do: @codec

  def schema!(schema) do
    schema = normalize!(schema)

    unless is_boolean(schema) or match?(%{"type" => "object"}, schema),
      do: fail!({:unsupported, :tool_schema_root})

    subset!(schema)
    prepare_tool!(Tool.new(name: "output", parameters_json_schema: schema))
    schema
  end

  def prepare!(definitions) do
    names = Enum.map(definitions, & &1.name)
    unless length(names) == length(Enum.uniq(names)), do: fail!(:duplicate_tool_names)

    Map.new(definitions, fn definition ->
      schema = schema!(definition.parameters_json_schema)
      logical = Tool.new(name: definition.name, parameters_json_schema: schema)
      logical = prepare_tool!(logical)
      nested = if schema == true, do: %{"type" => "object"}, else: schema

      wire = %{
        "type" => "object",
        "properties" => %{"arguments" => nested},
        "required" => ["arguments"],
        "additionalProperties" => false
      }

      outer = prepare_tool!(%{logical | parameters_json_schema: wire})
      {definition.name, %{logical: logical, outer: outer, wire: wire}}
    end)
  end

  def decode!(call, definitions) do
    metadata = ReqLLM.ToolCall.metadata(call)

    # Fragment diagnostics can survive successful stock assembly. Explicit errors
    # can instead accompany fallback arguments that still satisfy both schemas.
    if not is_map(metadata) or not is_nil(metadata[:error]) or not is_nil(metadata["error"]),
      do: fail!(:invalid_tool_arguments)

    %{logical: logical, outer: outer} = lookup!(definitions, call.function.name)

    with {:ok, decoded} <- Jason.decode(call.function.arguments),
         {:ok, %{"arguments" => args}} <- Tool.validate_args(outer, decoded),
         {:ok, ^args} <- Tool.validate_args(logical, args) do
      args
    else
      _ -> fail!(:invalid_tool_arguments)
    end
  end

  def encode!(call, definitions) do
    %{logical: logical} = lookup!(definitions, call.tool_name)

    unless call.metadata["arguments_codec"] == @codec,
      do: fail!({:unsupported, :tool_history_codec})

    case Tool.validate_args(logical, call.args) do
      {:ok, args} -> Jason.encode!(%{"arguments" => args})
      _ -> fail!(:invalid_tool_history)
    end
  end

  defp lookup!(definitions, name) do
    case Map.fetch(definitions, name) do
      {:ok, definition} -> definition
      :error -> fail!(:unknown_tool)
    end
  end

  defp prepare_tool!(tool) do
    case Tool.prepare(tool) do
      {:ok, prepared} -> prepared
      _ -> fail!(:invalid_tool_schema)
    end
  end

  defp normalize!(schema) do
    case Tool.JSON.normalize(schema) do
      {:ok, normal} -> normal
      _ -> fail!(:invalid_tool_schema)
    end
  end

  defp subset!(schema) when is_boolean(schema), do: :ok

  defp subset!(schema) when is_map(schema) do
    Enum.each(schema, fn {key, value} ->
      cond do
        key in @annotations or key in @values -> :ok
        key in @single -> subset!(value)
        key in @lists and is_list(value) -> Enum.each(value, &subset!/1)
        key in @maps and is_map(value) -> Enum.each(Map.values(value), &subset!/1)
        true -> fail!({:unsupported, :tool_schema_keyword})
      end
    end)
  end

  defp subset!(_), do: fail!(:invalid_tool_schema)
  defp fail!(reason), do: throw({:req_llm_adapter, reason})
end
