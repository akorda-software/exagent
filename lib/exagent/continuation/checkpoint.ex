defmodule ExAgent.Continuation.Checkpoint do
  @moduledoc """
  Experimental persistence-only retry seam for a runtime owner integrating R4.

  Unlike snapshot RuntimeCheckpoint, the pending value is an exact CAS command
  with its operation ID, not a callback rebuilding state. While pending, new
  commands are rejected. Retry performs only Store IO. This does not pause/resume
  a run or authorize external IO; R5 must integrate the runtime mutation gate.
  """
  alias ExAgent.Store
  alias ExAgent.Continuation.Transition

  @enforce_keys [:store, :kind, :id]
  defstruct [:store, :kind, :id, :pending, :error]

  def new(store, kind, id, durability) do
    with :ok <- Store.require_continuation(store, durability),
         {:ok, _} <- ExAgent.Continuation.Record.key({store.namespace, kind, id}) do
      {:ok, %__MODULE__{store: store, kind: kind, id: id}}
    end
  end

  def write(%__MODULE__{pending: nil} = checkpoint, expected, command) do
    case Transition.command(command) do
      {:ok, command} -> retry(%{checkpoint | pending: {expected, command}})
      {:error, reason} -> {{:error, reason}, checkpoint}
    end
  end

  def write(%__MODULE__{} = checkpoint, _, _), do: {{:error, :checkpoint_pending}, checkpoint}

  def retry(%__MODULE__{pending: nil} = checkpoint), do: {:ok, checkpoint}

  def retry(%__MODULE__{pending: {expected, command}} = checkpoint) do
    case Store.transition(checkpoint.store, checkpoint.kind, checkpoint.id, expected, command) do
      {:ok, result} -> {{:ok, result}, %{checkpoint | pending: nil, error: nil}}
      {:error, reason} -> {{:error, reason}, %{checkpoint | error: reason}}
    end
  end
end
