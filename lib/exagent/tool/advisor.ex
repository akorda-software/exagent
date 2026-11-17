defmodule ExAgent.Tool.Advisor do
  @moduledoc """
  A tool that lets the agent consult a stronger (or different) model mid-task.

  A fast, cheap model can run the loop and ask for advice only when it is stuck,
  planning or about to take a risky step. The advisor receives a bounded text
  transcript of the conversation so far (the latest user message and the most
  recent entries) plus the agent's question, and answers in text. It has no tools and
  never acts.

      advisor = ExAgent.Tool.Advisor.new(model: strong_model, max_uses: 3)

      ExAgent.new(model: fast_model, tools: [advisor | tools])

  If the advisor fails, the agent receives a note saying so and continues on its
  own; the run's own limits still stop it at the next check.

  The transcript is plain text, so the advisor may use any provider: it never
  receives the executor's provider replay data such as signed reasoning. Inside
  a run the advisor runs through `ExAgent.run_child/4`, so its usage counts
  toward the run's usage, limits and deadline. With a persisted continuation it
  runs as a separate run and its usage is added to the tool result instead.

  Options for `new/1`:

    * `:model` (required) — the advisor model.
    * `:name` — tool name (default `"consult_advisor"`).
    * `:description` — tool description for the agent; the default says when to
      use it.
    * `:instructions` — the advisor's system prompt.
    * `:max_uses` — consultations per user message, failed ones included
      (default `3`).
    * `:max_transcript_bytes` — transcript size (default `32_000`).
    * `:model_settings` — settings for the advisor model.
    * `:timeout` — how long one consultation may take, in milliseconds (default
      `120_000`). It bounds the advisor's run as a deadline (never extending the
      run's own), so a slow provider request ends in the "unavailable" note; the
      tool's timeout is set 5 seconds longer, replacing `:tool_timeout`.
  """

  alias ExAgent.Message.{Part, Request, Transcript}
  alias ExAgent.Tool

  @default_description "Ask a more capable advisor model for guidance. Use it when you are " <>
                         "stuck, before a long plan or a risky step, or when unsure your " <>
                         "answer is right. Ask one specific question; the advisor sees the " <>
                         "conversation so far but cannot use tools."

  @default_instructions """
  You advise an AI agent that is working on a task for a user. You see the
  conversation so far and the agent's question. Give concise, concrete guidance:
  the next steps, what to check, or what is wrong. Do not address the user.
  """

  @doc "Build the advisor tool. Raises `ArgumentError` for invalid options."
  @spec new(keyword()) :: Tool.t()
  def new(opts) do
    model = Keyword.fetch!(opts, :model)
    name = Keyword.get(opts, :name, "consult_advisor")
    max_uses = Keyword.get(opts, :max_uses, 3)
    max_bytes = Keyword.get(opts, :max_transcript_bytes, 32_000)
    settings = Keyword.get(opts, :model_settings, [])
    instructions = Keyword.get(opts, :instructions, @default_instructions)
    timeout = Keyword.get(opts, :timeout, 120_000)

    unless is_integer(max_uses) and max_uses > 0,
      do: raise(ArgumentError, "max_uses must be a positive integer")

    unless is_integer(max_bytes) and max_bytes >= 1_024,
      do: raise(ArgumentError, "max_transcript_bytes must be an integer >= 1024")

    unless is_integer(timeout) and timeout > 0,
      do: raise(ArgumentError, "timeout must be a positive integer")

    agent = ExAgent.new(model: model, instructions: instructions, model_settings: settings)

    Tool.new(
      name: name,
      description: Keyword.get(opts, :description, @default_description),
      # A strong model reading a long transcript can outlast `:tool_timeout`.
      timeout: timeout + 5_000,
      parameters_json_schema: %{
        "type" => "object",
        "properties" => %{
          "question" => %{"type" => "string", "description" => "What you want advice on."}
        },
        "required" => ["question"],
        "additionalProperties" => false
      },
      call: fn ctx, %{"question" => question} ->
        messages = ctx.messages || []

        if uses(messages, name) + earlier_in_batch(messages, name, ctx.tool_call_id) >= max_uses do
          "The advisor limit for this task (#{max_uses}) is reached. Continue on your own."
        else
          prompt =
            "Conversation so far (may be shortened):\n<conversation>\n" <>
              Transcript.render(messages, max_bytes) <>
              "\n</conversation>\n\nThe agent asks:\n" <> question

          deadline = System.monotonic_time(:millisecond) + timeout
          consult(ctx, agent, prompt, deadline: deadline)
        end
      end
    )
  end

  defp consult(
         %{execution_scope: %ExAgent.ExecutionScope{}, continuation: nil} = ctx,
         agent,
         prompt,
         opts
       ) do
    case ExAgent.run_child(ctx, agent, prompt, opts) do
      # The shared ledger already holds the child's usage.
      {:ok, %{output: output}} -> {:ok, output}
      {:error, error} -> unavailable(error)
    end
  end

  defp consult(_ctx, agent, prompt, opts) do
    case ExAgent.run(agent, prompt, opts) do
      {:ok, %{output: output, usage: usage}} ->
        {:ok, output, usage}

      # Count what the failed consultation used.
      {:error, %ExAgent.RunError{partial: %{usage: %ExAgent.Message.Usage{} = usage}} = error} ->
        {:ok, note} = unavailable(error)
        {:ok, note, usage}

      {:error, error} ->
        unavailable(error)
    end
  end

  # An ordinary result, so the agent continues on its own: a tool error would
  # fail the whole run. Run limits still stop the run at its next check.
  defp unavailable(error),
    do: {:ok, "The advisor is unavailable (#{reason(error)}). Continue on your own."}

  defp reason(%ExAgent.RunError{reason: reason}),
    do: ExAgent.ErrorProjection.reason(reason) |> inspect(limit: 10)

  defp reason(other), do: inspect(other, limit: 10)

  # Advisor calls in the response being executed that come before this one:
  # parallel calls all see the same history.
  defp earlier_in_batch(messages, name, id) do
    case Enum.find(Enum.reverse(messages), &match?(%ExAgent.Message.Response{}, &1)) do
      %{parts: parts} when is_list(parts) ->
        parts
        |> Enum.filter(&match?(%Part.ToolCall{tool_name: ^name}, &1))
        |> Enum.take_while(&(&1.tool_call_id != id))
        |> length()

      _ ->
        0
    end
  end

  # Consultations since the latest user message; a failed one returns a note
  # with status :succeeded and counts too.
  defp uses(messages, name) do
    messages
    |> Enum.reverse()
    |> Enum.take_while(fn
      %Request{parts: parts} when is_list(parts) ->
        not Enum.any?(parts, &match?(%Part.User{}, &1))

      _ ->
        true
    end)
    |> Enum.flat_map(fn
      %Request{parts: parts} when is_list(parts) -> parts
      _ -> []
    end)
    |> Enum.count(&match?(%Part.ToolReturn{tool_name: ^name, status: :succeeded}, &1))
  end
end
