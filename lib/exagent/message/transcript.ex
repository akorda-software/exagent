defmodule ExAgent.Message.Transcript do
  @moduledoc false
  # Bounded, provider-neutral text rendering of a conversation, for a second
  # model (a reviewer or an advisor) that must not receive another provider's
  # replay data such as signed reasoning.

  alias ExAgent.Message.{Part, Request, Response}
  alias ExAgent.Tool.OutputLimit

  @entry_bytes 4_096

  @doc false
  @spec render([ExAgent.Message.t()], pos_integer()) :: String.t()
  def render(messages, max_bytes) when is_list(messages) and max_bytes >= 256 do
    entries = messages |> Enum.flat_map(&entries/1) |> Enum.with_index()

    # Keep the latest user message (the current task) and as many of the most
    # recent other entries as fit; gaps are marked.
    pinned =
      entries
      |> Enum.filter(fn {entry, _} -> String.starts_with?(entry, "User:") end)
      |> List.last()

    pinned_size = if pinned, do: byte_size(elem(pinned, 0)) + 2, else: 0
    others = entries |> Enum.reject(&(&1 == pinned)) |> Enum.reverse()
    kept = take_tail(others, max_bytes - pinned_size - 128, [])

    (List.wrap(pinned) ++ kept)
    |> Enum.sort_by(&elem(&1, 1))
    |> with_gaps(length(entries))
    |> Enum.join("\n\n")
    |> bound(max_bytes)
  end

  defp take_tail([], _budget, kept), do: kept

  defp take_tail([{entry, _} = item | rest], budget, kept) do
    size = byte_size(entry) + 2
    if size <= budget, do: take_tail(rest, budget - size, [item | kept]), else: kept
  end

  defp with_gaps(items, total) do
    {lines, last} =
      Enum.flat_map_reduce(items, -1, fn {entry, index}, previous ->
        {gap(index - previous - 1) ++ [entry], index}
      end)

    lines ++ gap(total - last - 1)
  end

  defp gap(0), do: []
  defp gap(n), do: ["[#{n} entries omitted]"]

  defp entries(%Request{parts: parts}) when is_list(parts) do
    Enum.flat_map(parts, fn
      %Part.User{content: content} -> ["User: " <> bound(user_text(content), @entry_bytes)]
      %Part.ToolReturn{} = part -> [tool_return(part)]
      %Part.Retry{content: content} -> ["Runtime retry: " <> bound(text(content), 1_024)]
      _ -> []
    end)
  end

  defp entries(%Response{parts: parts}) when is_list(parts) do
    Enum.flat_map(parts, fn
      %Part.Text{content: content} when is_binary(content) and content != "" ->
        ["Assistant: " <> bound(content, @entry_bytes)]

      %Part.ToolCall{tool_name: name} = call ->
        args =
          case Part.ToolCall.args_as_map(call) do
            {:ok, map} -> text(map)
            _ -> text(call.args || "")
          end

        ["Assistant called #{name} with #{bound(args, 1_024)}"]

      _ ->
        []
    end)
  end

  defp entries(_message), do: []

  defp tool_return(%Part.ToolReturn{tool_name: name, status: status, content: content}) do
    label = if status in [nil, :succeeded], do: "", else: " (#{status})"
    "Tool #{name} returned#{label}: " <> bound(text(content), @entry_bytes)
  end

  @doc false
  # A user prompt as text: images and files become short placeholders.
  def user_text(content) when is_binary(content), do: content

  def user_text(parts) when is_list(parts) do
    Enum.map_join(parts, " ", fn part ->
      case part[:type] || part["type"] do
        "text" -> part[:text] || part["text"] || ""
        "file" -> "[file #{part[:filename] || part["filename"] || ""}]"
        _ -> "[image]"
      end
    end)
  end

  def user_text(other), do: text(other)

  @doc false
  def text(value) when is_binary(value), do: value

  def text(value) do
    Jason.encode!(value)
  rescue
    _ -> inspect(value, limit: 50, printable_limit: 4_096)
  end

  defp bound(text, max) when byte_size(text) <= max, do: text
  defp bound(text, max), do: OutputLimit.shorten(text, OutputLimit.new(max_bytes: max(max, 256)))
end
