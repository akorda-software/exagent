defmodule ExAgent.Providers.SSE do
  @moduledoc """
  Incremental, bounded SSE JSON decoding over an enumerable of binary chunks.

  Supports LF, CRLF and CR (including split terminators), multiline `data:` and
  comments. Emits JSON objects, `:done` for `[DONE]`, and `:eof` for clean HTTP
  EOF. EOF is not a provider success: adapters must require their own terminal.
  Malformed JSON and unfinished frames are explicit errors, never discarded.

  `max_frame_bytes` and `max_buffer_bytes` default to 1 MiB each;
  `max_response_bytes` defaults to 8 MiB. Limits count wire bytes, including
  comments. The buffer limit bounds the current incomplete frame, not the total
  conversation. Options are shared with `ExAgent.Providers.StreamTransport`.

  Migration from the old async-response helper: pass byte chunks from
  `StreamTransport.stream(http_options, limits)` to `stream/2`, instead of
  starting Req with `into: :self` and passing its `Req.Response`. Cancel any
  previously started async response with `Req.cancel_async_response/1` before
  replacing it. The new helper never receives arbitrary mailbox messages.
  """

  alias ExAgent.Providers.StreamTransport

  def stream(chunks, opts \\ []) do
    Stream.transform(
      Stream.concat(chunks, [:eof]),
      fn ->
        limits = StreamTransport.options!(opts)
        %{line: "", data: [], frame: 0, total: 0, pending_cr: false, done: false, limits: limits}
      end,
      &decode/2,
      fn _ -> :ok end
    )
  end

  defp decode(_, %{done: true} = state), do: {:halt, state}
  defp decode({:error, _} = error, state), do: {[error], %{state | done: true}}
  defp decode({:data, chunk}, state), do: decode(chunk, state)

  defp decode(:eof, state) do
    {event, state} =
      if state.pending_cr, do: finish_line(%{state | pending_cr: false}), else: {nil, state}

    events = if event == nil, do: [], else: [event]

    cond do
      state.done ->
        {events, state}

      state.line != "" or state.data != [] ->
        {events ++ [{:error, :truncated_sse_frame}], %{state | done: true}}

      true ->
        {events ++ [:eof], %{state | done: true}}
    end
  end

  defp decode(chunk, state) when is_binary(chunk) do
    state = %{state | total: state.total + byte_size(chunk)}

    if state.total > state.limits[:max_response_bytes] do
      fail(state, {:stream_limit, :max_response_bytes})
    else
      lines(chunk, state, [])
    end
  end

  defp lines(_, %{done: true} = state, events), do: {Enum.reverse(events), state}
  defp lines("", state, events), do: {Enum.reverse(events), state}

  defp lines(chunk, %{pending_cr: true} = state, events) do
    {rest, extra} =
      case chunk do
        <<10, rest::binary>> -> {rest, 1}
        _ -> {chunk, 0}
      end

    state = %{state | pending_cr: false, frame: state.frame + extra}

    case limit_error(state) do
      nil ->
        {event, state} = finish_line(state)
        lines(rest, state, if(event == nil, do: events, else: [event | events]))

      reason ->
        {Enum.reverse([{:error, reason} | events]), %{state | done: true}}
    end
  end

  defp lines(chunk, state, events) do
    case :binary.match(chunk, ["\r", "\n"]) do
      :nomatch ->
        state = %{state | line: state.line <> chunk, frame: state.frame + byte_size(chunk)}
        bounded(state, events)

      {index, 1} ->
        {fragment, <<separator, rest::binary>>} = :erlang.split_binary(chunk, index)
        state = %{state | line: state.line <> fragment, frame: state.frame + index + 1}

        case limit_error(state) do
          nil ->
            if separator == 13 do
              lines(rest, %{state | pending_cr: true}, events)
            else
              {event, state} = finish_line(state)
              events = if event == nil, do: events, else: [event | events]
              lines(rest, state, events)
            end

          reason ->
            {Enum.reverse([{:error, reason} | events]), %{state | done: true}}
        end
    end
  end

  defp bounded(state, events) do
    case limit_error(state) do
      nil -> {Enum.reverse(events), state}
      reason -> {Enum.reverse([{:error, reason} | events]), %{state | done: true}}
    end
  end

  defp limit_error(state) do
    cond do
      state.frame > state.limits[:max_frame_bytes] -> {:stream_limit, :max_frame_bytes}
      state.frame > state.limits[:max_buffer_bytes] -> {:stream_limit, :max_buffer_bytes}
      true -> nil
    end
  end

  defp finish_line(%{line: ""} = state) do
    payload = state.data |> Enum.reverse() |> Enum.join("\n")
    next = %{state | data: [], frame: 0}

    cond do
      state.data == [] ->
        {nil, next}

      payload == "[DONE]" ->
        {:done, %{next | done: true}}

      true ->
        case Jason.decode(payload) do
          {:ok, map} when is_map(map) -> {map, next}
          _ -> {{:error, :invalid_sse_json}, %{next | done: true}}
        end
    end
  end

  defp finish_line(%{line: "data:" <> data} = state) do
    data =
      case data do
        <<32, rest::binary>> -> rest
        _ -> data
      end

    {nil, %{state | line: "", data: [data | state.data]}}
  end

  defp finish_line(%{line: "data"} = state),
    do: {nil, %{state | line: "", data: ["" | state.data]}}

  defp finish_line(state), do: {nil, %{state | line: ""}}
  defp fail(state, reason), do: {[{:error, reason}], %{state | done: true}}
end
