defmodule ExAgent.Judge do
  @moduledoc """
  A second model that reviews the agent's work: final answers before they are
  accepted, and tool calls before they run.

  ## Review final answers

      check =
        ExAgent.Judge.output_validator(
          model: reviewer_model,
          criteria: "Answers every question asked, cites the tool results it relies on."
        )

      ExAgent.new(model: model, tools: tools, output_validators: [check], output_retries: 2)

  The reviewer sees a bounded text transcript of the conversation (the latest
  user message and the most recent entries) and the final answer, and replies
  PASS or FAIL with feedback; a reply in another format is asked again once. On FAIL the feedback goes back to the agent, which
  continues and answers again; that uses the `:output_retries` budget, so the
  run fails with `{:unexpected_model_behavior, {:output_retries_exhausted, _}}`
  if the answer never passes. Inside a
  run the reviewer runs through `ExAgent.run_child/4`, so its usage counts
  toward the run's usage and limits; with a persisted continuation it runs as a
  separate run whose usage is not added.

  ## Review tool calls

      approve =
        ExAgent.Judge.approver(
          model: reviewer_model,
          policy: "Reading is fine. Writes only inside /tmp. Never delete files.",
          escalate: &MyApp.ask_a_human/1
        )

      ExAgent.run(agent, prompt, permissions: perms, approve: approve)

  Use it as the `:approve` callback for tools whose permission is `:ask`. The
  reviewer sees the tool name and arguments and answers ALLOW, DENY or ASK; ASK
  calls `:escalate` (a human, for example), and without one the call is denied.
  Each review is a separate run whose usage is not added to the agent's run,
  and it counts toward the reviewed tool's timeout (see `approver/1`).

  The reviewer is a model: it can be wrong or manipulated by content it reviews.
  Keep hard limits in `ExAgent.Permissions` and in the tools themselves.
  Telemetry: `[:exagent, :judge, :verdict]` with metadata `%{kind, verdict}`
  (`kind` is `:output` or `:approval`).
  """

  alias ExAgent.Message.Transcript

  @output_instructions """
  You review an AI agent's final answer before it reaches the user. Judge it
  only against the criteria and the conversation shown. Reply with one line:
  PASS, or FAIL followed by specific, actionable feedback for the agent.
  """

  @approval_instructions """
  You review a tool call an AI agent wants to make, against a policy. Reply with
  one line: ALLOW if the policy clearly permits it, DENY if the policy forbids
  it, or ASK if a human should decide. Add a short reason after the word.
  """

  @doc """
  An output validator (see `ExAgent.new/1` `:output_validators`) that asks
  `:model` whether the final answer meets `:criteria`.

  Options: `:model` and `:criteria` (required); `:model_settings`;
  `:max_transcript_bytes` (default `24_000`); `:on_error`, `:accept` (default)
  or `:fail`, when the reviewer fails or twice replies in another format. The
  answer is never accepted unreviewed because the run's own deadline, usage
  limits or cancellation stopped the reviewer.
  """
  @spec output_validator(keyword()) :: ExAgent.output_validator()
  def output_validator(opts) do
    {model, settings} = model!(opts)
    criteria = text!(opts, :criteria)
    max_bytes = Keyword.get(opts, :max_transcript_bytes, 24_000)
    on_error = Keyword.get(opts, :on_error, :accept)

    unless is_integer(max_bytes) and max_bytes >= 1_024,
      do: raise(ArgumentError, "max_transcript_bytes must be an integer >= 1024")

    unless on_error in [:accept, :fail],
      do: raise(ArgumentError, "on_error must be :accept or :fail")

    reviewer = reviewer(model, settings, @output_instructions)

    fn output, ctx ->
      prompt =
        "Criteria:\n#{criteria}\n\nConversation (may be shortened):\n<conversation>\n" <>
          Transcript.render(ctx.messages || [], max_bytes) <>
          "\n</conversation>\n\nFinal answer to review:\n<answer>\n" <>
          shorten(Transcript.text(output), max_bytes) <> "\n</answer>"

      case verdict(ctx, reviewer, prompt, ~w(PASS FAIL)) do
        {:ok, "PASS", _reason} ->
          telemetry(:output, :pass)
          :ok

        {:ok, "FAIL", reason} ->
          telemetry(:output, :fail)

          {:retry,
           "A reviewer checked your final answer and asked for changes: " <>
             if(reason == "", do: "it does not meet the requirements.", else: reason) <>
             "\nRevise your work and give your complete final answer again."}

        {:error, reason} ->
          telemetry(:output, :error)

          # Never pass an unreviewed answer because the run itself ran out.
          if on_error == :accept and not run_limit?(reason),
            do: :ok,
            else: {:error, {:judge_failed, reason}}
      end
    end
  end

  @doc """
  An `:approve` callback for `ExAgent.run/3` that asks `:model` whether a tool
  call follows `:policy`.

  Options: `:model` and `:policy` (required); `:model_settings`; `:escalate`, a
  `fn tool_call -> :approve | :deny end` used for ASK verdicts and reviewer
  failures (default: deny); `:timeout`, the reviewer's deadline in milliseconds
  (default `20_000`), after which the call is escalated.

  The `:approve` callback receives only the tool call, not the run, so each
  review is a separate run: its usage is not added to the run's usage, limits
  or cost. The review and any escalation happen inside the tool call and count
  toward that tool's timeout (`:tool_timeout` by default); keep `:escalate`
  quick, or give the reviewed tools a longer `timeout`.
  """
  @spec approver(keyword()) :: (ExAgent.Message.Part.ToolCall.t() -> :approve | :deny)
  def approver(opts) do
    {model, settings} = model!(opts)
    policy = text!(opts, :policy)
    escalate = Keyword.get(opts, :escalate)
    timeout = Keyword.get(opts, :timeout, 20_000)

    unless is_integer(timeout) and timeout > 0,
      do: raise(ArgumentError, "timeout must be a positive integer")

    unless is_nil(escalate) or is_function(escalate, 1),
      do: raise(ArgumentError, "escalate must be a one-argument function")

    reviewer = reviewer(model, settings, @approval_instructions)

    fn call ->
      args =
        case ExAgent.Message.Part.ToolCall.args_as_map(call) do
          {:ok, map} -> Transcript.text(map)
          :empty -> "{}"
          _ -> Transcript.text(call.args)
        end

      prompt =
        "Policy:\n#{policy}\n\nTool call:\nname: #{call.tool_name}\narguments:\n" <>
          "<arguments>\n#{shorten(args, 8_192)}\n</arguments>"

      deadline = System.monotonic_time(:millisecond) + timeout

      case verdict(nil, reviewer, prompt, ~w(ALLOW DENY ASK), deadline: deadline) do
        {:ok, "ALLOW", _} ->
          telemetry(:approval, :allow)
          :approve

        {:ok, "DENY", _} ->
          telemetry(:approval, :deny)
          :deny

        {:ok, "ASK", _} ->
          telemetry(:approval, :ask)
          escalate(escalate, call)

        {:error, _} ->
          telemetry(:approval, :error)
          escalate(escalate, call)
      end
    end
  end

  @doc false
  # Ask for a one-line verdict; returns the label and the rest of the reply as
  # the reason. A reply in another format is asked again once.
  def verdict(ctx, reviewer, prompt, labels, run_opts \\ []) do
    with {:error, :invalid_verdict} <- ask(ctx, reviewer, prompt, labels, run_opts) do
      reminder =
        "\n\nYour previous reply did not follow the format. Reply with one line " <>
          "that starts with exactly one of: #{Enum.join(labels, ", ")}."

      ask(ctx, reviewer, prompt <> reminder, labels, run_opts)
    end
  end

  defp ask(ctx, reviewer, prompt, labels, run_opts) do
    result =
      if child?(ctx),
        do: ExAgent.run_child(ctx, reviewer, prompt, run_opts),
        else: ExAgent.run(reviewer, prompt, run_opts)

    case result do
      {:ok, %{output: output}} when is_binary(output) -> parse(output, labels)
      {:ok, _} -> {:error, :invalid_verdict}
      {:error, %ExAgent.RunError{reason: reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  # The reply must start with a label (optionally after markdown or a
  # "Verdict:"-style prefix) that ends at a space, end of text or `: . , — *`.
  # "Pass-fail", "pass/fail", "Allow?" and "FAILED" are not verdicts.
  def parse(output, labels) do
    pattern =
      ~r/\A[\s*_`#>]*(?:(?:verdict|result|decision|answer)\s*[:\-]\s*[*_`]*)?([A-Za-z]+)(?=\z|[\s:.,—*])[\s*_`:.,—\-]*(.*)\z/is

    with [_, word, reason] <- Regex.run(pattern, String.trim(output)),
         word = String.upcase(word),
         true <- word in labels do
      {:ok, word, reason |> String.trim() |> shorten(2_048)}
    else
      _ -> {:error, :invalid_verdict}
    end
  end

  defp run_limit?(reason)
       when reason in [:deadline_exceeded, :execution_scope_closed, :cancelled],
       do: true

  defp run_limit?(reason) when is_tuple(reason) and elem(reason, 0) == :usage_limit_exceeded,
    do: true

  defp run_limit?(_reason), do: false

  defp reviewer(model, settings, instructions),
    do: ExAgent.new(model: model, instructions: instructions, model_settings: settings)

  # A run child shares the parent's usage ledger, limits and cancellation; a
  # persisted continuation needs a descriptor that a validator cannot provide.
  defp child?(%{execution_scope: %ExAgent.ExecutionScope{}} = ctx),
    do: is_nil(Map.get(ctx, :continuation))

  defp child?(_ctx), do: false

  defp escalate(nil, _call), do: :deny

  defp escalate(fun, call) do
    if fun.(call) == :approve, do: :approve, else: :deny
  end

  defp model!(opts) do
    model = Keyword.fetch!(opts, :model)
    settings = Keyword.get(opts, :model_settings, [])
    {model, settings}
  end

  defp text!(opts, key) do
    case Keyword.fetch!(opts, key) do
      text when is_binary(text) and text != "" -> text
      _ -> raise ArgumentError, "#{key} must be a non-empty string"
    end
  end

  defp shorten(text, max) when byte_size(text) <= max, do: text

  defp shorten(text, max),
    do: ExAgent.Tool.OutputLimit.shorten(text, ExAgent.Tool.OutputLimit.new(max_bytes: max))

  defp telemetry(kind, verdict),
    do:
      ExAgent.Telemetry.execute([:judge, :verdict], %{count: 1}, %{kind: kind, verdict: verdict})
end
