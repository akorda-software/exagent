defmodule ExAgent.RunError do
  @moduledoc """
  An operational run failure with the last confirmed execution state.

  `reason` retains the underlying error category; `partial` has the same fields
  as a successful run result, with `output: nil` and a failed/cancelled status.
  Incomplete model output is in `partial.pending_response`, never executable
  conversation history. Preserving progress does not make replay idempotent.

  The partial model is a live runtime value and may contain credentials. Use
  the message/snapshot codecs rather than exporting this struct as JSON.
  """
  @enforce_keys [:reason, :partial]
  defstruct [:reason, :partial]

  @type t :: %__MODULE__{reason: term(), partial: map()}
end
