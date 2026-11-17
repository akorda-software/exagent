defmodule ExAgent.Tool.OutputLimit do
  @moduledoc """
  Capability that shortens large successful tool results before the model sees them.

  A tool result stays in the conversation and is sent again on every later step,
  so one large file read or command log can dominate the context window and the
  bill. By default every result below the run's `:max_payload_bytes` retention
  ceiling (1 MiB by default) is kept whole. That ceiling is checked before any hook runs,
  so a larger result still fails the run with this capability installed.

  Results larger than `:max_bytes` are replaced by their beginning and end with a
  notice saying how much was omitted, so the model can ask for a narrower read
  instead of guessing. Text is cut on UTF-8 character boundaries. Non-string
  results are measured and cut as their JSON encoding, so the model receives a
  string. Results within the limit, failures and retries are left unchanged.

      ExAgent.new(model: model, tools: tools, capabilities: [ExAgent.Tool.OutputLimit.new(max_bytes: 16_000)])

  Options (struct fields):

    * `:max_bytes` — largest result kept whole, in bytes (default `32_768`,
      minimum `256`). The shortened result, notice included, fits within it.
    * `:keep` — `:head_tail` (default), `:head` or `:tail`.
    * `:tools` — `:all` (default) or a list of tool names to limit.
    * `:on_truncate` — optional `fn info -> String.t() | nil end`, called with
      `%{tool_name, tool_call_id, content, bytes}` holding the full result, before
      it is shortened. Use it to keep the full output elsewhere; a returned string
      is added to the notice (for example, how to page through the stored copy),
      cut if needed so the result still fits `:max_bytes`.

  The shortened result is what later model requests, the conversation history
  and events see. It runs as an `after_tool_execute` hook, so list it after
  capabilities that should see the full result. The tool's raw outcome is
  confirmed before hooks run: a persisted continuation's effect record, and a run
  that fails while the hook runs (for example, a slow `:on_truncate` reaching the
  tool timeout), can still hold the full result. Keep `:on_truncate` fast.
  """

  use ExAgent.Capability

  alias ExAgent.Message.Part

  defstruct max_bytes: 32_768, keep: :head_tail, tools: :all, on_truncate: nil

  @type t :: %__MODULE__{
          max_bytes: pos_integer(),
          keep: :head_tail | :head | :tail,
          tools: :all | [String.t()],
          on_truncate: (map() -> String.t() | nil) | nil
        }

  @doc "Build a validated limit. Raises `ArgumentError` for invalid options."
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: __MODULE__ |> struct!(opts) |> validate!()

  @impl true
  def after_tool_execute(%__MODULE__{} = limit, _ctx, call, {:ok, %Part.ToolReturn{} = part}) do
    validate!(limit)

    with true <- part.status == :succeeded and applies?(limit, call.tool_name),
         {:ok, text} <- text(part.content),
         true <- byte_size(text) > limit.max_bytes do
      hint = hint(limit, part, byte_size(text))
      {:ok, %{part | content: shorten(text, limit, hint)}}
    else
      _ -> {:ok, part}
    end
  end

  def after_tool_execute(_limit, _ctx, _call, result), do: result

  @doc false
  def shorten(text, %__MODULE__{max_bytes: max, keep: keep}, hint \\ nil) do
    total = byte_size(text)
    hint = fit_hint(hint, max - byte_size(notice(total, total, nil)) - 1)
    # Reserve room for the notice with the largest omitted count it can show.
    budget = max - byte_size(notice(total, total, hint))
    {head, tail} = split(keep, max(budget, 0))
    head = valid_prefix(binary_part(text, 0, head))
    tail = valid_suffix(binary_part(text, total - tail, tail))
    omitted = total - byte_size(head) - byte_size(tail)
    head <> notice(omitted, total, hint) <> tail
  end

  defp split(:head_tail, budget), do: {div(budget, 2), budget - div(budget, 2)}
  defp split(:head, budget), do: {budget, 0}
  defp split(:tail, budget), do: {0, budget}

  defp notice(omitted, total, hint) do
    "\n\n[... #{omitted} of #{total} bytes omitted from this tool result." <>
      if(hint, do: " " <> hint, else: "") <> " ...]\n\n"
  end

  # A hint longer than the limit is cut so the whole result still fits.
  defp fit_hint(hint, room) when is_binary(hint) and room > 0,
    do: valid_prefix(binary_part(hint, 0, min(byte_size(hint), room)))

  defp fit_hint(_hint, _room), do: nil

  defp hint(%__MODULE__{on_truncate: nil}, _part, _bytes), do: nil

  defp hint(%__MODULE__{on_truncate: fun}, part, bytes) when is_function(fun, 1) do
    info = %{
      tool_name: part.tool_name,
      tool_call_id: part.tool_call_id,
      content: part.content,
      bytes: bytes
    }

    case fun.(info) do
      hint when is_binary(hint) and hint != "" -> hint
      _ -> nil
    end
  end

  defp text(content) when is_binary(content) do
    if String.valid?(content), do: {:ok, content}, else: :error
  end

  defp text(content) do
    case Jason.encode(content) do
      {:ok, json} -> {:ok, json}
      _ -> :error
    end
  end

  defp applies?(%__MODULE__{tools: :all}, _name), do: true
  defp applies?(%__MODULE__{tools: names}, name), do: name in names

  # Drop an incomplete trailing character from a byte-cut prefix.
  defp valid_prefix(binary) do
    case :unicode.characters_to_binary(binary) do
      valid when is_binary(valid) -> valid
      {_, valid, _rest} -> valid
    end
  end

  # Drop continuation bytes left at the start of a byte-cut suffix.
  defp valid_suffix(<<0b10::2, _::6, rest::binary>>), do: valid_suffix(rest)
  defp valid_suffix(binary), do: binary

  defp validate!(%__MODULE__{max_bytes: max, keep: keep, tools: tools, on_truncate: fun} = limit) do
    unless is_integer(max) and max >= 256 and keep in [:head_tail, :head, :tail] and
             (tools == :all or (is_list(tools) and Enum.all?(tools, &is_binary/1))) and
             (is_nil(fun) or is_function(fun, 1)),
           do: raise(ArgumentError, "invalid ExAgent.Tool.OutputLimit options")

    limit
  end
end
