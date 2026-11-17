defmodule ExAgent.Eval do
  @moduledoc """
  Measure an agent on a set of cases: run each case, score the result with
  evaluators and summarize pass rate, latency, usage and cost.

      cases = [
        ExAgent.Eval.Case.new("refund", "Refund order 7", expected: "refunded"),
        ExAgent.Eval.Case.new("lookup", "Where is order 9?", expected: "shipped")
      ]

      report =
        ExAgent.Eval.run(agent, cases,
          evaluators: [
            ExAgent.Eval.contains(),
            ExAgent.Eval.tool_called("lookup_order"),
            ExAgent.Eval.judge(model: reviewer, criteria: "Polite and accurate.")
          ],
          concurrency: 4,
          repeat: 3
        )

      IO.puts(ExAgent.Eval.Report.format(report))
      report.summary.pass_rate

  Use it to compare prompts, models or tools before shipping a change
  (`ExAgent.Eval.Report.compare/2` lists the cases that regressed), or in CI with
  a pass-rate threshold. Runs call the model for real unless the agent uses a
  test model, so cost is real; `repeat` measures how stable the agent is.

  ## Targets

  The target is an `%ExAgent{}` agent, run with `ExAgent.run/3`, or a function
  `fn input, run_opts -> ExAgent.run(...) end` returning `{:ok, result}` or
  `{:error, reason}`, for agents that need per-case setup.

  ## Evaluators

  An evaluator has a name and a function of the case's outcome (`t:outcome/0`)
  that returns `true`, `false`, a score between `0` and `1`, `{score, reason}` or
  `:skip`. A result passes an evaluator when its score is at least the
  evaluator's threshold (default `1.0`, so a boolean must be `true`). Build one
  with `evaluator/3` or use the built-ins: `equals/1`, `contains/1`,
  `matches/2`, `tool_called/2` and `judge/1`. A case whose run fails, raises or
  times out gets no scores and does not pass; an evaluator that raises scores
  `0`.
  """

  alias ExAgent.Eval.{Case, Evaluator, Report, Result}
  alias ExAgent.Message.{Part, Response}

  @typedoc "What evaluators receive for one run of one case."
  @type outcome :: %{
          case: Case.t(),
          output: term(),
          result: ExAgent.result() | nil,
          error: term() | nil
        }

  @type score :: boolean() | number() | {boolean() | number(), String.t()} | :skip

  @doc """
  Build an evaluator from a name and a function of `t:outcome/0`.
  Options: `:threshold` (default `1.0`).
  """
  @spec evaluator(String.t(), (outcome() -> score()), keyword()) :: Evaluator.t()
  def evaluator(name, fun, opts \\ []) when is_binary(name) and is_function(fun, 1) do
    threshold = Keyword.get(opts, :threshold, 1.0)

    unless is_number(threshold) and threshold >= 0 and threshold <= 1,
      do: raise(ArgumentError, "threshold must be a number between 0 and 1")

    %Evaluator{name: name, fun: fun, threshold: threshold}
  end

  @doc """
  Run every case and score it.

  Options:

    * `:evaluators` — list of `t:ExAgent.Eval.Evaluator.t/0` (default `[]`: a
      case passes when its run succeeds).
    * `:concurrency` — runs (and scorings) at a time (default `4`).
    * `:timeout` — milliseconds per run (default `120_000`); a run that exceeds
      it is killed and its result's `error` is `:timeout`.
    * `:evaluator_timeout` — milliseconds to score one run with all evaluators
      (default `120_000`); when exceeded, every evaluator of that run fails with
      a timeout reason. Scoring time is not part of the run's `duration_ms`.
    * `:repeat` — runs per case (default `1`).
    * `:run_opts` — options for every run, merged under each case's own.

  Case names must be unique. A target that raises, exits or throws produces a
  failed result; so does an evaluator, which then scores `0` and fails
  regardless of its threshold.
  """
  @spec run(ExAgent.t() | (term(), keyword() -> term()), [Case.t()], keyword()) :: Report.t()
  def run(target, cases, opts \\ []) do
    evaluators = Keyword.get(opts, :evaluators, [])
    concurrency = positive!(opts, :concurrency, 4)
    timeout = positive!(opts, :timeout, 120_000)
    evaluator_timeout = positive!(opts, :evaluator_timeout, 120_000)
    repeat = positive!(opts, :repeat, 1)
    run_opts = Keyword.get(opts, :run_opts, [])

    unless is_list(cases) and Enum.all?(cases, &match?(%Case{}, &1)),
      do: raise(ArgumentError, "cases must be a list of ExAgent.Eval.Case structs")

    unless length(Enum.uniq_by(cases, & &1.name)) == length(cases),
      do: raise(ArgumentError, "case names must be unique")

    unless is_list(evaluators) and Enum.all?(evaluators, &match?(%Evaluator{}, &1)),
      do: raise(ArgumentError, "evaluators must be a list built with ExAgent.Eval functions")

    unless Keyword.keyword?(run_opts), do: raise(ArgumentError, "run_opts must be a keyword list")

    unless match?(%ExAgent{}, target) or is_function(target, 2),
      do: raise(ArgumentError, "target must be an agent or a function of (input, run_opts)")

    runs = for c <- cases, attempt <- 1..repeat, do: {c, attempt}

    # Unlinked tasks: a process the target links to and that crashes must not
    # take the caller down with it.
    {:ok, sup} = Task.Supervisor.start_link()

    try do
      execute(sup, target, runs, evaluators, run_opts, concurrency, timeout, evaluator_timeout)
    after
      Supervisor.stop(sup)
    end
  end

  defp execute(sup, target, runs, evaluators, run_opts, concurrency, timeout, evaluator_timeout) do
    # Runs first, each bounded by :timeout; scoring after, with its own bound,
    # so a slow reviewer never discards a finished run.
    outcomes =
      Task.Supervisor.async_stream_nolink(
        sup,
        runs,
        fn {c, attempt} -> attempt(target, c, attempt, run_opts) end,
        max_concurrency: concurrency,
        timeout: timeout,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.zip(runs)
      |> Enum.map(fn
        {{:ok, outcome}, _} -> outcome
        {{:exit, :timeout}, {c, attempt}} -> failed(c, attempt, :timeout, timeout)
        {{:exit, reason}, {c, attempt}} -> failed(c, attempt, {:exit, reason}, nil)
      end)

    Task.Supervisor.async_stream_nolink(sup, outcomes, &score_all(&1, evaluators),
      max_concurrency: concurrency,
      timeout: evaluator_timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip(outcomes)
    |> Enum.map(fn
      {{:ok, scores}, outcome} -> result(outcome, scores)
      {{:exit, reason}, outcome} -> result(outcome, timed_out(evaluators, outcome, reason))
    end)
    |> Report.new()
  end

  # One run of the target; never raises, exits or throws into the caller.
  defp attempt(target, c, attempt, run_opts) do
    opts = Keyword.merge(run_opts, c.run_opts)
    started = System.monotonic_time(:millisecond)

    {output, result, error} =
      try do
        case call(target, c.input, opts) do
          {:ok, %{output: output} = result} ->
            {output, result, nil}

          {:error, %ExAgent.RunError{reason: reason, partial: partial}} ->
            {nil, partial, reason || :error}

          {:error, reason} ->
            {nil, nil, reason || :error}

          other ->
            {nil, nil, {:invalid_target_result, other}}
        end
      rescue
        error -> {nil, nil, {:raised, Exception.message(error)}}
      catch
        :exit, reason -> {nil, nil, {:exit, reason}}
        :throw, value -> {nil, nil, {:throw, value}}
      end

    %{
      case: c,
      attempt: attempt,
      output: output,
      # A failed run keeps its partial result for usage, not for evaluators.
      result: result,
      error: error,
      duration_ms: System.monotonic_time(:millisecond) - started
    }
  end

  defp failed(c, attempt, error, duration),
    do: %{
      case: c,
      attempt: attempt,
      output: nil,
      result: nil,
      error: error,
      duration_ms: duration
    }

  defp score_all(%{error: nil} = outcome, evaluators) do
    view = %{case: outcome.case, output: outcome.output, result: outcome.result, error: nil}
    Enum.map(evaluators, &score(&1, view))
  end

  defp score_all(_failed, _evaluators), do: []

  defp timed_out(_evaluators, %{error: error}, _reason) when not is_nil(error), do: []

  defp timed_out(evaluators, _outcome, reason) do
    why = if reason == :timeout, do: "evaluators timed out", else: "evaluators exited"
    Enum.map(evaluators, &%{name: &1.name, score: 0.0, passed: false, reason: why})
  end

  defp result(outcome, scores) do
    usage = outcome.result && Map.get(outcome.result, :usage)
    field = fn key -> outcome.result && Map.get(outcome.result, key) end

    %Result{
      case: outcome.case.name,
      attempt: outcome.attempt,
      output: outcome.output,
      error: outcome.error,
      scores: scores,
      passed: is_nil(outcome.error) and Enum.all?(scores, &(&1.passed != false)),
      duration_ms: outcome.duration_ms,
      input_tokens: usage && Map.get(usage, :input_tokens),
      output_tokens: usage && Map.get(usage, :output_tokens),
      requests: field.(:request_count),
      tool_calls: field.(:tool_calls),
      cost_cents: field.(:cost_cents)
    }
  end

  defp call(%ExAgent{} = agent, input, opts), do: ExAgent.run(agent, input, opts)
  defp call(fun, input, opts), do: fun.(input, opts)

  defp score(%Evaluator{} = e, outcome) do
    normalized =
      try do
        normalize(e.fun.(outcome))
      rescue
        error -> {:failed, "evaluator raised: " <> Exception.message(error)}
      catch
        kind, reason -> {:failed, "evaluator #{kind}: " <> inspect(reason, limit: 5)}
      end

    case normalized do
      {:skip, reason} ->
        %{name: e.name, score: nil, passed: nil, reason: reason}

      {:failed, reason} ->
        %{name: e.name, score: 0.0, passed: false, reason: reason}

      {value, reason} ->
        %{name: e.name, score: value, passed: value >= e.threshold, reason: reason}
    end
  end

  defp normalize({value, reason}) when is_binary(reason) or is_nil(reason) do
    case normalize(value) do
      {:failed, _} = failed -> failed
      {value, _} -> {value, reason}
    end
  end

  defp normalize(true), do: {1.0, nil}
  defp normalize(false), do: {0.0, nil}
  defp normalize(:skip), do: {:skip, nil}
  defp normalize(n) when is_number(n) and n >= 0 and n <= 1, do: {n * 1.0, nil}
  defp normalize(other), do: {:failed, "invalid evaluator result: " <> inspect(other, limit: 5)}

  defp positive!(opts, key, default) do
    case Keyword.get(opts, key, default) do
      n when is_integer(n) and n > 0 -> n
      _ -> raise ArgumentError, "#{key} must be a positive integer"
    end
  end

  # ----- built-in evaluators -------------------------------------------------

  @doc """
  The output equals the case's `:expected`. For strings, `trim: true` (default)
  ignores surrounding whitespace and `case_sensitive: false` ignores case.
  Option `:name` (default `"equals"`) names it in reports.
  """
  @spec equals(keyword()) :: Evaluator.t()
  def equals(opts \\ []) do
    evaluator(Keyword.get(opts, :name, "equals"), fn %{case: c, output: output} ->
      if expected?(c),
        do: normalize_text(output, opts) == normalize_text(c.expected, opts),
        else: :skip
    end)
  end

  @doc """
  The text output contains the case's `:expected` (a string, or a list of
  strings that must all appear). The score is the fraction found. Options:
  `case_sensitive` (default `false`), `:name`, `:threshold`.
  """
  @spec contains(keyword()) :: Evaluator.t()
  def contains(opts \\ []) do
    evaluator(
      Keyword.get(opts, :name, "contains"),
      fn %{case: c, output: output} ->
        cond do
          not expected?(c) ->
            :skip

          not is_binary(output) ->
            {false, "output is not text"}

          List.wrap(c.expected) == [] ->
            :skip

          not Enum.all?(List.wrap(c.expected), &(is_binary(&1) or is_number(&1))) ->
            {false, "expected must be text, a number or a list of them"}

          true ->
            wanted = c.expected |> List.wrap() |> Enum.map(&to_string/1)
            text = normalize_text(output, Keyword.put_new(opts, :case_sensitive, false))

            missing =
              Enum.reject(wanted, fn w ->
                String.contains?(
                  text,
                  normalize_text(w, Keyword.put_new(opts, :case_sensitive, false))
                )
              end)

            score = (length(wanted) - length(missing)) / length(wanted)
            if missing == [], do: score, else: {score, "missing: " <> Enum.join(missing, ", ")}
        end
      end,
      Keyword.take(opts, [:threshold])
    )
  end

  @doc "The text output matches `regex`. Option: `:name` (default `\"matches\"`)."
  @spec matches(Regex.t(), keyword()) :: Evaluator.t()
  def matches(%Regex{} = regex, opts \\ []) do
    evaluator(Keyword.get(opts, :name, "matches"), fn %{output: output} ->
      is_binary(output) and Regex.match?(regex, output)
    end)
  end

  @doc """
  The run called the tool `name`. `:args` (a function of the arguments map)
  narrows the match; `:times` requires an exact number of calls.
  """
  @spec tool_called(String.t(), keyword()) :: Evaluator.t()
  def tool_called(name, opts \\ []) when is_binary(name) do
    args? = Keyword.get(opts, :args, fn _ -> true end)
    times = Keyword.get(opts, :times)

    evaluator(Keyword.get(opts, :name, "tool_called:" <> name), fn %{result: result} ->
      count =
        for %Response{parts: parts} <- result.new_messages,
            %Part.ToolCall{tool_name: ^name} = call <- parts,
            {:ok, args} <- [Part.ToolCall.args_as_map(call)],
            args?.(args),
            reduce: 0,
            do: (n -> n + 1)

      if times,
        do: {count == times, "called #{count} times"},
        else: {count > 0, "called #{count} times"}
    end)
  end

  @doc """
  A reviewer model grades the answer against `:criteria` and replies PASS or
  FAIL with a reason.

  The reviewer sees the task, a transcript of the run (tool calls and results
  included, so facts the agent looked up count as supported) and the answer,
  each bounded by `:max_transcript_bytes`; images and files in the task appear
  as placeholders. The case's `:expected`, when present, is shown as the key content a
  correct answer must convey, not as the only acceptable wording.

  Options: `:model` and `:criteria` (required), `:model_settings`,
  `:max_transcript_bytes` (default `16_000`, at least `1_024`), `:name`. The
  reviewer's usage is not included in the report; an unusable reply scores `0`
  with the error as reason.
  """
  @spec judge(keyword()) :: Evaluator.t()
  def judge(opts) do
    model = Keyword.fetch!(opts, :model)
    criteria = Keyword.fetch!(opts, :criteria)
    max_bytes = Keyword.get(opts, :max_transcript_bytes, 16_000)

    unless is_binary(criteria) and criteria != "",
      do: raise(ArgumentError, "criteria must be a non-empty string")

    unless is_integer(max_bytes) and max_bytes >= 1_024,
      do: raise(ArgumentError, "max_transcript_bytes must be an integer >= 1024")

    reviewer =
      ExAgent.new(
        model: model,
        model_settings: Keyword.get(opts, :model_settings, []),
        instructions: """
        You grade an AI agent's final answer to a task against the criteria.
        Facts the agent obtained from tool results in the transcript are
        supported, not invented. When key content is given, the answer must
        convey it; extra correct detail is fine unless the criteria forbid it.
        Reply with one line: PASS, or FAIL followed by the reason.
        """
      )

    evaluator(Keyword.get(opts, :name, "judge"), fn %{case: c, output: output, result: result} ->
      # Every part is bounded, so one large field cannot crowd out the rest.
      quarter = div(max_bytes, 4)

      key =
        if expected?(c),
          do:
            "\n\nKey content:\n<key_content>\n#{bounded(text(c.expected), quarter)}\n</key_content>",
          else: ""

      task = c.input |> ExAgent.Message.Transcript.user_text() |> bounded(quarter)

      prompt =
        "Criteria:\n#{criteria}\n\nTask:\n<task>\n#{task}\n</task>" <>
          "\n\nRun transcript (may be shortened):\n<transcript>\n" <>
          ExAgent.Message.Transcript.render(result.messages, max_bytes) <>
          "\n</transcript>" <>
          key <> "\n\nFinal answer:\n<answer>\n#{bounded(text(output), 2 * quarter)}\n</answer>"

      case ExAgent.Judge.verdict(nil, reviewer, prompt, ["PASS", "FAIL"]) do
        {:ok, "PASS", reason} -> {true, reason}
        {:ok, "FAIL", reason} -> {false, reason}
        {:error, reason} -> {false, "reviewer failed: " <> inspect(reason, limit: 5)}
      end
    end)
  end

  defp expected?(%Case{expected: expected}), do: not is_nil(expected)

  defp bounded(text, max) when byte_size(text) <= max, do: text

  defp bounded(text, max),
    do: ExAgent.Tool.OutputLimit.shorten(text, ExAgent.Tool.OutputLimit.new(max_bytes: max))

  defp text(value) when is_binary(value), do: value
  defp text(value), do: ExAgent.Message.Transcript.text(value)

  defp normalize_text(value, opts) when is_binary(value) do
    value = if Keyword.get(opts, :trim, true), do: String.trim(value), else: value
    if Keyword.get(opts, :case_sensitive, true), do: value, else: String.downcase(value)
  end

  defp normalize_text(value, _opts), do: value
end
