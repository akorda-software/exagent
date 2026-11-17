defmodule ExAgent.Eval.Evaluator do
  @moduledoc "A named scoring function; build one with `ExAgent.Eval.evaluator/3`."

  defstruct [:name, :fun, threshold: 1.0]

  @type t :: %__MODULE__{
          name: String.t(),
          fun: (ExAgent.Eval.outcome() -> ExAgent.Eval.score()),
          threshold: number()
        }
end
