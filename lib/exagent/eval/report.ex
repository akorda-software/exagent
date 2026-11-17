defmodule ExAgent.Eval.Report do
  @moduledoc """
  The results of `ExAgent.Eval.run/3` and their summary.

  `summary` holds `runs`, `passed`, `pass_rate`, `errors`, per-evaluator
  `evaluators` (`%{name => %{mean, pass_rate}}`, skips excluded), per-case
  `cases` (`%{name => pass_rate}`), latency `duration_ms` (`p50`, `p95`, `max`),
  token and request totals (failed runs included), and `cost_cents` (`nil`
  unless every run reported a cost).
  """

  alias ExAgent.Eval.Result

  defstruct results: [], summary: %{}

  @type t :: %__MODULE__{results: [Result.t()], summary: map()}

  @doc false
  def new(results), do: %__MODULE__{results: results, summary: summarize(results)}

  defp summarize(results) do
    runs = length(results)
    passed = Enum.count(results, & &1.passed)
    ok = Enum.reject(results, & &1.error)

    %{
      runs: runs,
      passed: passed,
      pass_rate: ratio(passed, runs),
      errors: runs - length(ok),
      evaluators: evaluators(results),
      cases:
        results
        |> Enum.group_by(& &1.case)
        |> Map.new(fn {name, rs} -> {name, ratio(Enum.count(rs, & &1.passed), length(rs))} end),
      duration_ms: percentiles(results |> Enum.map(& &1.duration_ms) |> Enum.reject(&is_nil/1)),
      # Failed runs count what they spent.
      input_tokens: sum(results, :input_tokens),
      output_tokens: sum(results, :output_tokens),
      requests: sum(results, :requests),
      cost_cents:
        if(results != [] and Enum.all?(results, &is_number(&1.cost_cents)),
          do: sum(results, :cost_cents),
          else: nil
        )
    }
  end

  defp evaluators(results) do
    results
    |> Enum.flat_map(& &1.scores)
    |> Enum.reject(&is_nil(&1.score))
    |> Enum.group_by(& &1.name)
    |> Map.new(fn {name, scores} ->
      {name,
       %{
         mean: Enum.sum(Enum.map(scores, & &1.score)) / length(scores),
         pass_rate: ratio(Enum.count(scores, & &1.passed), length(scores))
       }}
    end)
  end

  defp ratio(_, 0), do: 0.0
  defp ratio(n, d), do: n / d

  defp sum(results, key), do: results |> Enum.map(&(Map.get(&1, key) || 0)) |> Enum.sum()

  defp percentiles([]), do: %{p50: nil, p95: nil, max: nil}

  defp percentiles(values) do
    sorted = Enum.sort(values)
    at = fn p -> Enum.at(sorted, min(length(sorted) - 1, ceil(p * length(sorted)) - 1)) end
    %{p50: at.(0.5), p95: at.(0.95), max: List.last(sorted)}
  end

  @doc """
  Compare a candidate report with a baseline: cases whose pass rate dropped
  (`regressed`) or rose (`improved`), cases only in the candidate (`added`) or
  only in the baseline (`removed`), and the change in overall pass rate.
  """
  @spec compare(t(), t()) :: %{
          regressed: [{String.t(), float(), float()}],
          improved: [{String.t(), float(), float()}],
          added: [String.t()],
          removed: [String.t()],
          pass_rate_delta: float()
        }
  def compare(%__MODULE__{summary: base}, %__MODULE__{summary: candidate}) do
    changes =
      for {name, after_rate} <- candidate.cases,
          before_rate = Map.get(base.cases, name),
          before_rate != nil and before_rate != after_rate,
          do: {name, before_rate, after_rate}

    %{
      regressed: changes |> Enum.filter(fn {_, b, a} -> a < b end) |> Enum.sort(),
      improved: changes |> Enum.filter(fn {_, b, a} -> a > b end) |> Enum.sort(),
      added: Enum.sort(Map.keys(candidate.cases) -- Map.keys(base.cases)),
      removed: Enum.sort(Map.keys(base.cases) -- Map.keys(candidate.cases)),
      pass_rate_delta: candidate.pass_rate - base.pass_rate
    }
  end

  @doc "A plain-text summary and the failed runs, for a console or CI log."
  @spec format(t()) :: String.t()
  def format(%__MODULE__{results: results, summary: s}) do
    header =
      "Eval: #{s.passed}/#{s.runs} passed (#{percent(s.pass_rate)}), #{s.errors} errors, " <>
        "p50 #{s.duration_ms.p50 || "-"} ms, p95 #{s.duration_ms.p95 || "-"} ms, " <>
        "#{s.input_tokens} in / #{s.output_tokens} out tokens" <>
        if(s.cost_cents, do: ", #{Float.round(s.cost_cents * 1.0, 2)} cents", else: "")

    evaluators =
      s.evaluators
      |> Enum.sort()
      |> Enum.map(fn {name, e} ->
        "  #{name}: pass #{percent(e.pass_rate)}, mean #{Float.round(e.mean, 2)}"
      end)

    failures =
      results
      |> Enum.reject(& &1.passed)
      |> Enum.map(fn r ->
        why =
          if r.error,
            do: "error " <> inspect(r.error, limit: 5, printable_limit: 200),
            else:
              r.scores
              |> Enum.filter(&(&1.passed == false))
              |> Enum.map_join("; ", fn sc ->
                sc.name <>
                  if(sc.reason, do: " (" <> String.slice(sc.reason, 0, 200) <> ")", else: "")
              end)

        "  FAIL #{r.case} ##{r.attempt}: #{why}"
      end)

    Enum.join(
      [header | evaluators] ++ if(failures == [], do: [], else: ["Failures:" | failures]),
      "\n"
    )
  end

  defp percent(rate), do: "#{round(rate * 100)}%"
end
