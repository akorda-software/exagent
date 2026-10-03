defmodule ExAgent.Message.Continuation do
  @moduledoc false

  # Portable data only. No term serialization, module names or dynamic atoms.
  def json!(value) do
    case ExAgent.Tool.JSON.normalize(value) do
      {:ok, value} -> value
      {:error, _} -> raise ArgumentError, "continuation must contain portable JSON data"
    end
  end

  def metadata!(value) when is_map(value) and not is_struct(value), do: json!(value)
  def metadata!(_), do: raise(ArgumentError, "invalid message metadata")

  def validate!(nil), do: nil

  def validate!(value) do
    value = metadata!(value)

    case value do
      %{
        "version" => 4,
        "reasoning_mode" => mode,
        "routing" => routing,
        "provider" => "openrouter",
        "arguments_codec" => "exagent.arguments/1"
      }
      when mode in ["disabled", "none"] and is_map(routing) ->
        routing!(routing)
        value |> Map.drop(["routing", "reasoning_mode"]) |> Map.put("version", 2) |> validate!()
        value

      %{"version" => 3, "reasoning_mode" => "none", "arguments_codec" => "exagent.arguments/1"} ->
        value |> Map.delete("reasoning_mode") |> Map.put("version", 2) |> validate!()
        value

      %{"version" => 2, "arguments_codec" => "exagent.arguments/1"} ->
        value |> Map.delete("arguments_codec") |> Map.put("version", 1) |> validate!()
        value

      _ ->
        validate_v1!(value)
    end
  end

  def routing!(routing) when is_map(routing) do
    routing = metadata!(routing)

    unless map_size(routing) <= 5 and
             Enum.all?(routing, fn
               {key, values} when key in ["order", "only", "ignore"] ->
                 is_list(values) and length(values) in 1..32 and
                   Enum.all?(values, fn value ->
                     is_binary(value) and byte_size(value) in 1..128 and
                       Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.\/-]*\z/, value)
                   end)

               {key, value} when key in ["allow_fallbacks", "require_parameters"] ->
                 is_boolean(value)

               _ ->
                 false
             end),
           do: raise(ArgumentError, "invalid bounded OpenRouter routing")

    routing
  end

  def routing!(_), do: raise(ArgumentError, "invalid bounded OpenRouter routing")

  defp validate_v1!(value) do
    case value do
      %{
        "version" => 1,
        "provider" => provider,
        "model" => model,
        "endpoint" => endpoint,
        "message_metadata" => metadata,
        "reasoning_details" => details
      }
      when is_binary(provider) and is_binary(model) and
             (is_binary(endpoint) or is_nil(endpoint)) and is_map(metadata) and is_list(details) ->
        if Enum.sort(Map.keys(value)) !=
             Enum.sort(~w(version provider model endpoint message_metadata reasoning_details)),
           do: raise(ArgumentError, "unknown continuation fields")

        Enum.each(details, &reasoning!/1)
        value

      _ ->
        raise ArgumentError, "invalid or unsupported continuation version"
    end
  end

  def reasoning!(
        %{
          "text" => text,
          "signature" => signature,
          "encrypted" => encrypted,
          "provider" => provider,
          "format" => format,
          "index" => index,
          "provider_data" => data
        } = value
      )
      when (is_binary(text) or is_nil(text)) and (is_binary(signature) or is_nil(signature)) and
             is_boolean(encrypted) and (is_binary(provider) or is_nil(provider)) and
             (is_binary(format) or is_nil(format)) and is_integer(index) and index >= 0 and
             is_map(data) do
    if map_size(value) != 7, do: raise(ArgumentError, "unknown reasoning fields")
    json!(value)
  end

  def reasoning!(_), do: raise(ArgumentError, "invalid reasoning continuation")
end
