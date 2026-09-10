defmodule ExAgent.Compaction.Estimate do
  @moduledoc false

  alias ExAgent.Message.{Part, Request, Response}

  def messages(messages) do
    Enum.reduce(messages, 0, fn
      %Request{parts: parts, instructions: instructions}, total ->
        total + 8 + value(instructions) + Enum.reduce(parts, 0, &(part(&1) + &2))

      %Response{parts: parts}, total ->
        total + 8 + Enum.reduce(parts, 0, &(part(&1) + &2))
    end)
  end

  # Only the advertised definition is context; never count/inspect a callable or
  # a prepared validator, which may be large and is not transmitted to the model.
  def tools(tools) do
    Enum.reduce(tools, 0, fn tool, total ->
      definition = Map.take(tool, [:name, :description, :parameters_json_schema])
      total + 12 + value(definition)
    end)
  end

  defp part(%Part.ToolCall{tool_name: name, args: args, tool_call_id: id}),
    do: 4 + value(name) + value(args) + value(id)

  defp part(%Part.ToolReturn{tool_name: name, content: content, tool_call_id: id}),
    do: 4 + value(name) + value(content) + value(id)

  defp part(%Part.Retry{tool_name: name, content: content, tool_call_id: id}),
    do: 4 + value(name) + value(content) + value(id)

  defp part(%Part.Thinking{content: content, signature: signature}),
    do: 4 + value(content) + value(signature)

  defp part(%{content: content}), do: 4 + value(content)

  defp value(nil), do: 0
  defp value(binary) when is_binary(binary), do: div(byte_size(binary) + 3, 4)

  defp value(term) do
    case Jason.encode(term) do
      {:ok, encoded} -> value(encoded)
      {:error, _} -> value(inspect(term, limit: :infinity, printable_limit: :infinity))
    end
  end
end
