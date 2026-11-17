defmodule ExAgent.Eval.Result do
  @moduledoc """
  One run of one case. `scores` holds `%{name, score, passed, reason}` per
  evaluator (`score` and `passed` are `nil` when it skipped). A failed run keeps
  the usage its partial result reports; usage fields are `nil` when there is
  none (a timeout, a raise or a target without a result).
  """

  defstruct [
    :case,
    :attempt,
    :output,
    :error,
    :duration_ms,
    :input_tokens,
    :output_tokens,
    :requests,
    :tool_calls,
    :cost_cents,
    scores: [],
    passed: false
  ]

  @type t :: %__MODULE__{}
end
