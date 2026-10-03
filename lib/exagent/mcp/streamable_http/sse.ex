defmodule ExAgent.MCP.StreamableHTTP.SSE do
  @moduledoc false
  # Bounded incremental SSE framing. No replay cursor is retained or emitted.
  defstruct line: "",
            first_line: true,
            data: [],
            event_bytes: 0,
            skip_lf: false,
            line_limit: 65_536,
            event_limit: 262_144

  def new(line_limit, event_limit),
    do: %__MODULE__{line_limit: line_limit, event_limit: event_limit}

  def feed(state, bytes), do: collect(state, bytes, [])

  # Yield before scanning any suffix. The caller decides whether another event
  # is wanted; rest is borrowed only for the current callback, never retained.
  def next(state, bytes), do: scan(state, bytes)

  defp collect(state, bytes, events) do
    case next(state, bytes) do
      {:event, state, event, rest} -> collect(state, rest, [event | events])
      {:more, state} -> {:ok, state, Enum.reverse(events)}
      error -> error
    end
  end

  def finish(%{line: "", data: []}), do: :ok
  def finish(_), do: {:error, :incomplete_sse}

  defp scan(state, ""), do: {:more, state}

  defp scan(%{skip_lf: true} = state, <<10, rest::binary>>),
    do: scan(%{state | skip_lf: false}, rest)

  defp scan(state, bytes) do
    state = %{state | skip_lf: false}

    case :binary.match(bytes, ["\r", "\n"]) do
      {index, 1} ->
        {part, <<separator, rest::binary>>} = :erlang.split_binary(bytes, index)

        with {:ok, state} <- append(state, part),
             {:ok, state, event} <- line(state) do
          state = %{state | skip_lf: separator == 13}

          if is_nil(event),
            do: scan(state, rest),
            else: {:event, state, event, rest}
        end

      :nomatch ->
        with {:ok, state} <- append(state, bytes),
             do: {:more, state}
    end
  end

  defp append(state, part) do
    if byte_size(state.line) + byte_size(part) <= state.line_limit,
      do:
        {:ok,
         %{state | line: if(state.line == "", do: :binary.copy(part), else: state.line <> part)}},
      else: {:error, :sse_line_limit}
  end

  defp line(%{first_line: true} = state),
    do: line(%{state | first_line: false, line: String.replace_prefix(state.line, "\uFEFF", "")})

  defp line(%{line: "", data: []} = state), do: {:ok, state, nil}

  defp line(%{line: ""} = state) do
    event = state.data |> Enum.reverse() |> Enum.join("\n")
    {:ok, %{state | data: [], event_bytes: 0}, event}
  end

  defp line(state) do
    if String.valid?(state.line) do
      case state.line do
        "data:" <> value -> data(state, String.replace_prefix(value, " ", ""))
        "data" -> data(state, "")
        _ -> {:ok, %{state | line: ""}, nil}
      end
    else
      {:error, :invalid_sse_utf8}
    end
  end

  defp data(state, value) do
    size = state.event_bytes + byte_size(value) + if(state.data == [], do: 0, else: 1)

    if size <= state.event_limit,
      do:
        {:ok, %{state | line: "", data: [:binary.copy(value) | state.data], event_bytes: size},
         nil},
      else: {:error, :sse_event_limit}
  end
end
