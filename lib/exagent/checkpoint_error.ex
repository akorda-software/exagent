defmodule ExAgent.CheckpointError do
  @moduledoc """
  A state transition whose checkpoint was not confirmed by the configured Store.

  `result` preserves the execution outcome, including completed output or partial
  progress. The new state remains in memory. Retry `Server.checkpoint/1` or
  `Session.checkpoint/1`, never the prompt, tool or change function. A failed save
  does not prove the backend did not write. This runtime value can contain a live
  model; use the event projection rather than serializing it directly.
  """
  @enforce_keys [:operation, :reason, :result, :revision]
  defstruct [:operation, :reason, :result, :revision]

  @type t :: %__MODULE__{
          operation: atom(),
          reason: term(),
          result: term(),
          revision: non_neg_integer()
        }
end
