defmodule ExAgent.Tool.RepeatGuard do
  @moduledoc """
  Capability that tells the model when it keeps repeating an identical tool call.

  Models sometimes loop: they call the same tool with the same arguments, get
  the same result and call it again until the step budget runs out. Before each
  model request this capability counts the calls made since the latest user
  message. When the model's latest response repeats a call (same tool name and
  equal decoded arguments) for the `:warn_at`-th time or more, the request gets
  a short runtime note asking it to use the earlier result, change the
  arguments or explain what is blocking it.

      ExAgent.new(
        model: model,
        tools: tools,
        capabilities: [compaction, ExAgent.Tool.RepeatGuard.new(warn_at: 3)]
      )

  The note exists only in the projection sent to the model, like the final-step
  instruction: the canonical history and events never contain it (a persisted
  continuation's request record captures the projection actually sent). It is rebuilt from the history at the same position in every later
  request of the task, so the request prefix stays stable for provider prompt
  caches and for providers that check signed reasoning against it. It never
  blocks a call; use `ExAgent.Permissions`, `:max_steps` or usage limits
  to bound execution. List it after capabilities that rewrite the projection,
  such as compaction, so they do not treat the note as the user's request.

  Options (struct fields):

    * `:warn_at` — repetition count that triggers the note (default `3`,
      minimum `2`).
    * `:tools` — `:all` (default) or the tool names to watch. Exclude tools that
      are expected to repeat, such as polling a job status.
  """

  use ExAgent.Capability

  alias ExAgent.Message.{Part, Request, Response}

  defstruct warn_at: 3, tools: :all

  @type t :: %__MODULE__{warn_at: pos_integer(), tools: :all | [String.t()]}

  @doc "Build a validated guard. Raises `ArgumentError` for invalid options."
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: __MODULE__ |> struct!(opts) |> validate!()

  @impl true
  def before_model_request(%__MODULE__{} = guard, state) do
    validate!(guard)

    case notes(guard, state.messages) do
      notes when map_size(notes) == 0 ->
        state

      notes ->
        %{state | request_messages: insert(state.request_messages || state.messages, notes)}
    end
  end

  # Responses since the latest user message whose calls reached the threshold,
  # mapped to their note. A pure function of the history, so every later request
  # rebuilds the same notes in the same places.
  defp notes(guard, messages) do
    messages
    |> Enum.reverse()
    |> Enum.take_while(&(not user_request?(&1)))
    |> Enum.reverse()
    |> Enum.reduce({%{}, %{}}, fn
      %Response{} = response, {counts, notes} ->
        calls = calls(guard, response)
        counts = Enum.reduce(calls, counts, &Map.update(&2, &1, 1, fn count -> count + 1 end))

        repeats =
          calls
          |> Enum.uniq()
          |> Enum.map(&{&1, Map.fetch!(counts, &1)})
          |> Enum.filter(fn {_call, count} -> count >= guard.warn_at end)

        {counts, if(repeats == [], do: notes, else: Map.put(notes, response, note(repeats)))}

      _message, acc ->
        acc
    end)
    |> elem(1)
  end

  # Each note follows the requests that answer its response, before the next
  # response, so it never splits a tool exchange. Responses a compactor already
  # summarized are absent from the projection and get no note.
  defp insert(projection, notes) do
    {messages, pending} =
      Enum.reduce(projection, {[], nil}, fn message, {acc, pending} ->
        acc = if pending && match?(%Response{}, message), do: [pending | acc], else: acc
        pending = if match?(%Response{}, message), do: note_request(notes[message]), else: pending
        {[message | acc], pending}
      end)

    Enum.reverse(if(pending, do: [pending | messages], else: messages))
  end

  defp note_request(nil), do: nil

  defp note_request(text),
    do: %Request{parts: [%Part.User{content: text}], timestamp: DateTime.utc_now()}

  defp calls(guard, %Response{parts: parts}) when is_list(parts) do
    for %Part.ToolCall{tool_name: name} = call <- parts,
        watched?(guard, name),
        {:ok, args} <- [args(call)],
        do: {name, args}
  end

  defp calls(_guard, _message), do: []

  defp args(call) do
    case Part.ToolCall.args_as_map(call) do
      :empty -> {:ok, %{}}
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> :error
    end
  end

  defp watched?(%__MODULE__{tools: :all}, _name), do: true
  defp watched?(%__MODULE__{tools: names}, name), do: name in names

  defp user_request?(%Request{parts: parts}) when is_list(parts),
    do: Enum.any?(parts, &match?(%Part.User{}, &1))

  defp user_request?(_message), do: false

  defp note(repeats) do
    calls =
      Enum.map_join(repeats, ", ", fn {{name, _args}, count} ->
        "`#{name}` #{count} times"
      end)

    "Runtime note (not from the user): since the last user message you have called " <>
      calls <>
      " with identical arguments. Repeating the call returns the same result. Use the earlier " <>
      "result, call it with different arguments, try another approach, or explain what is " <>
      "blocking you."
  end

  defp validate!(%__MODULE__{warn_at: warn_at, tools: tools} = guard) do
    unless is_integer(warn_at) and warn_at >= 2 and
             (tools == :all or (is_list(tools) and Enum.all?(tools, &is_binary/1))),
           do: raise(ArgumentError, "invalid ExAgent.Tool.RepeatGuard options")

    guard
  end
end
