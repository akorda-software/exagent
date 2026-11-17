defmodule ExAgent.MCP.Protocol do
  @moduledoc """
  Pure JSON-RPC 2.0 encoding/decoding for the Model Context Protocol, plus the
  mapping from an MCP tool spec to an `ExAgent.Tool`.

  Splitting the protocol out (no ports, no processes) keeps it trivially
  unit-testable. `ExAgent.MCP.Client` owns the transport and calls into here.
  """

  alias ExAgent.Tool

  @type decoded ::
          {:response, id :: term(), result :: map()}
          | {:error_response, id :: term(), error :: map()}
          | {:notification, method :: String.t(), params :: map()}
          | :ignore

  @version Mix.Project.config()[:version]

  @doc false
  # The ExAgent version reported as `clientInfo.version` in `initialize`.
  def client_version, do: @version

  @doc "Encode a JSON-RPC request (with an `id`) as a newline-terminated binary."
  @spec encode_request(term(), String.t(), map()) :: iodata()
  def encode_request(id, method, params) when is_binary(method) do
    Jason.encode_to_iodata!(%{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method,
      "params" => params
    }) ++
      "\n"
  end

  @doc "Encode a JSON-RPC notification (no `id`, no reply expected)."
  @spec encode_notification(String.t(), map()) :: iodata()
  def encode_notification(method, params) when is_binary(method) do
    Jason.encode_to_iodata!(%{"jsonrpc" => "2.0", "method" => method, "params" => params}) ++ "\n"
  end

  @doc """
  Decode one complete JSON-RPC line.

    * a response with a `result` → `{:response, id, result}`
    * a response with an `error` → `{:error_response, id, error}`
    * a notification (no `id`) → `{:notification, method, params}`
    * anything unparseable / unrelated → `:ignore`
  """
  @spec decode(binary()) :: decoded()
  def decode(line) when is_binary(line) do
    line = String.trim(line)

    case Jason.decode(line) do
      {:ok, %{"id" => id, "result" => result}} when id != nil ->
        {:response, id, result}

      {:ok, %{"id" => id, "error" => error}} when id != nil ->
        {:error_response, id, error}

      {:ok, %{"method" => method, "params" => params}} ->
        {:notification, method, params || %{}}

      _ ->
        :ignore
    end
  end

  @doc """
  Map an MCP `tools/list` entry to an `ExAgent.Tool` whose `call` forwards to the
  server via `call_fun`. The tool's result text is extracted from the MCP
  `content` blocks; an MCP `isError: true` becomes `{:error, _}`.

  `inputSchema` takes precedence over `input_schema` by key presence. Explicit
  false or invalid values are preserved for the common Tool validation boundary;
  only an absent schema uses the default object schema.

  The optional third argument is a validated private execution descriptor built
  by Client from trusted host options, never from server tool metadata. Without
  it the tool is marked `:unbound`: ordinary calls work, but durable fingerprints
  reject. Identity never changes the model-facing schema or description.
  """
  @spec to_tool(map(), (String.t(), map() -> {:ok, String.t()} | {:error, term()})) :: Tool.t()
  @spec to_tool(
          map(),
          (String.t(), map() -> {:ok, String.t()} | {:error, term()}),
          map() | :unbound
        ) :: Tool.t()
  def to_tool(spec, call_fun, execution_binding \\ :unbound) when is_function(call_fun, 2) do
    name = spec["name"]

    schema =
      Map.get(
        spec,
        "inputSchema",
        Map.get(spec, "input_schema", %{type: "object", properties: %{}})
      )

    Tool.new(
      name: name,
      description: spec["description"] || "MCP tool #{name}",
      parameters_json_schema: schema,
      takes_ctx: false,
      execution_binding: if(is_nil(execution_binding), do: :unbound, else: execution_binding),
      call: fn args -> call_fun.(name, args) end
    )
  end

  @doc """
  Extract the text of an MCP `tools/call` result.

  Text blocks are concatenated. ExAgent tool results are text, so other blocks
  become explicit notices instead of raw payloads: images and audio name their
  MIME type and size, embedded text resources contribute their text, binary
  resources and resource links are named by URI. A result with no content but
  `structuredContent` returns that content as JSON. `isError: true` becomes
  `{:error, text}`.
  """
  @spec result_to_text(map()) :: {:ok, String.t()} | {:error, term()}
  def result_to_text(%{"isError" => true} = result),
    do: {:error, extract_text(result)}

  def result_to_text(%{"content" => content} = result) when is_list(content),
    do: {:ok, extract_text(result)}

  def result_to_text(other), do: {:ok, inspect(other)}

  defp extract_text(%{"content" => [], "structuredContent" => structured})
       when is_map(structured),
       do: Jason.encode!(structured)

  defp extract_text(%{"content" => content}) when is_list(content),
    do: Enum.map_join(content, &block_text/1)

  defp extract_text(other), do: inspect(other)

  defp block_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text

  defp block_text(%{"type" => type} = block) when type in ["image", "audio"],
    do: notice("#{type} #{mime(block)}#{size(block["data"])} not shown: tool results are text")

  defp block_text(%{"type" => "resource", "resource" => %{"text" => text} = resource})
       when is_binary(text),
       do: "\n[resource #{uri(resource)}]\n" <> text <> "\n"

  defp block_text(%{"type" => "resource", "resource" => %{} = resource}),
    do:
      notice(
        "binary resource #{uri(resource)} #{mime(resource)}#{size(resource["blob"])} not shown"
      )

  defp block_text(%{"type" => "resource_link"} = link),
    do:
      notice("resource link #{uri(link)}#{if is_binary(link["name"]), do: " (#{link["name"]})"}")

  defp block_text(%{"text" => text}) when is_binary(text), do: text

  defp block_text(%{"type" => type}) when is_binary(type),
    do: notice("#{String.slice(type, 0, 64)} content not shown")

  defp block_text(_block), do: notice("unrecognized content not shown")

  defp notice(text), do: "\n[" <> text <> "]\n"

  defp mime(%{"mimeType" => mime}) when is_binary(mime), do: String.slice(mime, 0, 128)
  defp mime(_), do: "(unknown type)"

  defp uri(%{"uri" => uri}) when is_binary(uri), do: String.slice(uri, 0, 2_048)
  defp uri(_), do: "(no uri)"

  # Base64 payload size in decoded bytes, approximately.
  defp size(data) when is_binary(data), do: ", about #{div(byte_size(data) * 3, 4)} bytes"
  defp size(_), do: ""
end
