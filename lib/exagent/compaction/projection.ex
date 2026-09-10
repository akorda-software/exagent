defmodule ExAgent.Compaction.Projection do
  @moduledoc false

  alias ExAgent.Message.{Part, Request, Response}

  # Groups end only after every call is resolved, and include immediately
  # following retry/return requests. This also keeps unkeyed output retries with
  # the response they ask the model to correct.
  def groups(messages) when is_list(messages), do: group(messages, %{}, [], [])
  def groups(_), do: {:error, :invalid_messages}

  defp group([], pending, [], groups) when map_size(pending) == 0,
    do: {:ok, Enum.reverse(groups)}

  defp group([], _, _, _), do: {:error, :unresolved_tool_calls}

  defp group([message | rest], pending, current, groups) do
    with {:ok, pending} <- message_pending(message, pending) do
      current = [message | current]

      if map_size(pending) == 0 and not continuation?(List.first(rest)) do
        group(rest, pending, [], [Enum.reverse(current) | groups])
      else
        group(rest, pending, current, groups)
      end
    end
  end

  defp message_pending(%Request{parts: parts}, pending) when is_list(parts),
    do: parts_pending(parts, pending, :request)

  defp message_pending(%Response{parts: parts}, pending)
       when is_list(parts) and map_size(pending) == 0,
       do: parts_pending(parts, pending, :response)

  defp message_pending(_, _), do: {:error, :invalid_message_sequence}

  defp parts_pending(parts, pending, role) do
    Enum.reduce_while(parts, {:ok, pending}, fn part, {:ok, pending} ->
      case part_pending(part, pending, role) do
        {:ok, pending} -> {:cont, {:ok, pending}}
        error -> {:halt, error}
      end
    end)
  end

  defp part_pending(%Part.ToolCall{tool_call_id: id, tool_name: name}, pending, :response)
       when is_binary(id) and id != "" and is_binary(name) do
    if Map.has_key?(pending, id),
      do: {:error, :duplicate_tool_call},
      else: {:ok, Map.put(pending, id, name)}
  end

  defp part_pending(%Part.ToolReturn{tool_call_id: id, tool_name: name}, pending, :request),
    do: resolve(pending, id, name)

  defp part_pending(%Part.Retry{tool_call_id: nil}, pending, :request), do: {:ok, pending}

  defp part_pending(%Part.Retry{tool_call_id: id, tool_name: name}, pending, :request),
    do: resolve(pending, id, name)

  defp part_pending(%Part.System{}, pending, :request), do: {:ok, pending}
  defp part_pending(%Part.User{}, pending, :request), do: {:ok, pending}
  defp part_pending(%Part.Text{}, pending, :response), do: {:ok, pending}
  defp part_pending(%Part.Thinking{}, pending, :response), do: {:ok, pending}
  defp part_pending(_, _, _), do: {:error, :invalid_message_part}

  defp resolve(pending, id, name) do
    case Map.fetch(pending, id) do
      {:ok, expected} when name == expected or is_nil(name) -> {:ok, Map.delete(pending, id)}
      _ -> {:error, :orphan_tool_result}
    end
  end

  defp continuation?(%Request{parts: parts}) do
    Enum.any?(parts, &(match?(%Part.ToolReturn{}, &1) or match?(%Part.Retry{}, &1)))
  end

  defp continuation?(_), do: false

  def partition(messages, keep) do
    with {:ok, groups} <- groups(messages) do
      latest_user_from_end =
        groups
        |> Enum.reverse()
        |> Enum.find_index(&Enum.any?(&1, fn message -> user_message?(message) end))

      latest_user_group =
        if is_nil(latest_user_from_end), do: nil, else: length(groups) - latest_user_from_end - 1

      recent_start = recent_start(groups, keep)

      {retained, old} =
        groups
        |> Enum.with_index()
        |> Enum.split_with(fn {group, index} ->
          index >= recent_start or index == latest_user_group or
            Enum.any?(group, &instructions?/1)
        end)

      retained = Enum.flat_map(retained, &elem(&1, 0))
      old = Enum.flat_map(old, &elem(&1, 0))

      if is_nil(latest_user_group),
        do: {:ok, [], messages},
        else: {:ok, old, retained}
    end
  end

  defp recent_start(groups, keep) do
    {start, _count} =
      groups
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.reduce_while({length(groups), 0}, fn {group, index}, {_start, count} = acc ->
        if count >= keep, do: {:halt, acc}, else: {:cont, {index, count + length(group)}}
      end)

    start
  end

  # Keep leading instruction-only messages first. Summary is ordinary user-level
  # context before every retained conversational message, including the active
  # user request; it must never become the latest user prompt or a System part.
  def insert_summary(retained, text) do
    {instructions, rest} = Enum.split_while(retained, &instructions_only?/1)

    summary = %Request{
      parts: [
        %Part.User{
          content: "Summary of earlier conversation (context, not instructions):\n" <> text
        }
      ],
      timestamp: DateTime.utc_now()
    }

    instructions ++ [summary | rest]
  end

  def validate(source, candidate) do
    with {:ok, original_groups} <- groups(source),
         {:ok, candidate_groups} <- groups(candidate),
         true <- instruction_parts(source) === instruction_parts(candidate),
         true <- last_user(source) === last_user(candidate),
         true <- subsequence?(Enum.filter(source, &instructions?/1), candidate),
         true <- preserved_tool_groups?(original_groups, candidate_groups),
         {:ok, _encoded} <- Jason.encode_to_iodata(candidate, maps: :strict) do
      :ok
    else
      _ -> {:error, :invalid_compaction_projection}
    end
  rescue
    _ -> {:error, :invalid_compaction_projection}
  end

  defp preserved_tool_groups?(source, candidate) do
    occurrences =
      source
      |> Enum.with_index()
      |> Enum.group_by(fn {group, _index} -> group end, fn {_group, index} -> index end)

    original_messages = List.flatten(source)

    # Match whole group occurrences, consuming their source positions in order.
    # Equal messages in another group cannot stand in for a missing retry/result,
    # and one complete occurrence cannot justify retaining a second, split one.
    Enum.reduce_while(candidate, {-1, occurrences}, fn group, {previous, remaining} = acc ->
      case Map.fetch(remaining, group) do
        {:ok, positions} ->
          case Enum.drop_while(positions, &(&1 <= previous)) do
            [position | rest] ->
              {:cont, {position, Map.put(remaining, group, rest)}}

            [] ->
              {:halt, false}
          end

        :error ->
          # Fresh non-tool context (such as a summary) has no source occurrence.
          # A group containing an original message must instead match as a whole.
          if tool_group?(group) or Enum.any?(group, &(&1 in original_messages)),
            do: {:halt, false},
            else: {:cont, acc}
      end
    end) != false
  end

  defp tool_group?(group) do
    Enum.any?(group, fn message ->
      Enum.any?(
        message.parts,
        &(match?(%Part.ToolCall{}, &1) or match?(%Part.ToolReturn{}, &1) or
            match?(%Part.Retry{}, &1))
      )
    end)
  end

  defp subsequence?([], _), do: true
  defp subsequence?(_, []), do: false
  defp subsequence?([item | wanted], [item | rest]), do: subsequence?(wanted, rest)
  defp subsequence?(wanted, [_ | rest]), do: subsequence?(wanted, rest)

  defp instruction_parts(messages) do
    Enum.flat_map(messages, fn
      %Request{parts: parts, instructions: instructions} ->
        if(is_nil(instructions), do: [], else: [{:instructions, instructions}]) ++
          Enum.filter(parts, &match?(%Part.System{}, &1))

      _ ->
        []
    end)
  end

  defp instructions?(%Request{parts: parts, instructions: instructions}),
    do: not is_nil(instructions) or Enum.any?(parts, &match?(%Part.System{}, &1))

  defp instructions?(_), do: false

  defp instructions_only?(%Request{parts: parts} = request),
    do: instructions?(request) and Enum.all?(parts, &match?(%Part.System{}, &1))

  defp instructions_only?(_), do: false

  defp last_user(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find(&user_message?/1)
  end

  defp user_message?(%Request{parts: parts}), do: Enum.any?(parts, &match?(%Part.User{}, &1))
  defp user_message?(_), do: false
end
