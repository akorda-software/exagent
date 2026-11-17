defmodule ExAgent.MCP.StreamableHTTP.Message do
  @moduledoc false

  def decode(bytes, expected_id) do
    case Jason.decode(bytes, objects: :ordered_objects) do
      {:ok, value} ->
        with {:ok, message} <- unique_objects(value), do: classify(message, expected_id)

      _ ->
        {:error, :invalid_jsonrpc}
    end
  rescue
    _ -> {:error, :invalid_jsonrpc}
  end

  defp unique_objects(%Jason.OrderedObject{values: pairs}) do
    if length(pairs) == length(Enum.uniq_by(pairs, &elem(&1, 0))) do
      Enum.reduce_while(pairs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
        case unique_objects(value) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
          error -> {:halt, error}
        end
      end)
    else
      {:error, :duplicate_json_key}
    end
  end

  defp unique_objects(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case unique_objects(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp unique_objects(value), do: {:ok, value}

  defp classify(%{"jsonrpc" => "2.0"} = message, expected) do
    cond do
      Map.has_key?(message, "method") ->
        control(message)

      message["id"] !== expected ->
        {:error, :response_id_mismatch}

      Map.has_key?(message, "result") and not Map.has_key?(message, "error") and
          is_map(message["result"]) ->
        {:result, message["result"]}

      Map.has_key?(message, "error") and not Map.has_key?(message, "result") ->
        case message["error"] do
          %{"code" => code, "message" => text} when is_integer(code) and is_binary(text) ->
            # Server data/strings can contain credentials. Expose only the code.
            {:error, {:jsonrpc_error, code}}

          _ ->
            {:error, :invalid_jsonrpc}
        end

      true ->
        {:error, :invalid_jsonrpc}
    end
  end

  defp classify(_, _), do: {:error, :invalid_jsonrpc}

  defp control(message) do
    valid =
      is_binary(message["method"]) and
        is_map(Map.get(message, "params", %{})) and
        not Map.has_key?(message, "result") and not Map.has_key?(message, "error")

    cond do
      not valid ->
        {:error, :invalid_jsonrpc}

      not Map.has_key?(message, "id") ->
        :notification

      not (is_integer(message["id"]) or is_binary(message["id"])) ->
        {:error, :invalid_jsonrpc}

      message["method"] == "ping" ->
        {:control, %{"jsonrpc" => "2.0", "id" => message["id"], "result" => %{}}}

      true ->
        {:control,
         %{
           "jsonrpc" => "2.0",
           "id" => message["id"],
           "error" => %{"code" => -32601, "message" => "Method not found"}
         }}
    end
  end

  def initialize(%{
        "protocolVersion" => "2025-06-18",
        "capabilities" => caps,
        "serverInfo" => %{"name" => name, "version" => version}
      })
      when is_map(caps) and is_binary(name) and is_binary(version), do: :ok

  def initialize(_), do: {:error, :invalid_initialize}

  def tools(%{"tools" => tools} = result, limit) when is_list(tools) do
    cond do
      not (is_nil(result["nextCursor"]) or is_binary(result["nextCursor"])) ->
        {:error, :invalid_tools}

      length(tools) > limit ->
        {:error, :discovery_limit}

      not Enum.all?(tools, &tool?/1) ->
        {:error, :invalid_tools}

      length(Enum.uniq_by(tools, & &1["name"])) != length(tools) ->
        {:error, :invalid_tools}

      true ->
        {:ok, result}
    end
  end

  def tools(_, _), do: {:error, :invalid_tools}

  defp tool?(%{"name" => name, "inputSchema" => _} = spec),
    do:
      is_binary(name) and name != "" and
        (is_nil(spec["description"]) or is_binary(spec["description"]))

  defp tool?(_), do: false

  # Text blocks pass through; other well-formed blocks are accepted and become
  # explicit notices in `Protocol.result_to_text/1`, never raw payloads.
  def tool_result(%{"content" => content} = result) when is_list(content) do
    if Map.get(result, "isError", false) in [true, false] and Enum.all?(content, &block?/1),
      do: {:ok, result},
      else: {:error, :unsupported_tool_content}
  end

  def tool_result(_), do: {:error, :invalid_tool_result}

  defp block?(%{"type" => "text", "text" => text}), do: is_binary(text)

  defp block?(%{"type" => type, "data" => data} = block) when type in ["image", "audio"],
    do: is_binary(data) and is_binary(block["mimeType"])

  defp block?(%{"type" => "resource", "resource" => %{"uri" => uri} = resource}),
    do: is_binary(uri) and (is_binary(resource["text"]) or is_binary(resource["blob"]))

  defp block?(%{"type" => "resource_link", "uri" => uri}), do: is_binary(uri)
  defp block?(_block), do: false
end
