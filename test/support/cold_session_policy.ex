defmodule ExAgent.Test.ColdSessionPolicy do
  @moduledoc false
  @behaviour ExAgent.Session.TurnPolicy
  defstruct [:actor]

  @impl true
  def init(opts), do: %__MODULE__{actor: hd(opts[:participants]).id}
  @impl true
  def next_participant(state, _context), do: {:ok, state.actor, state}
  @impl true
  def can_act?(state, id, _context), do: state.actor == id
  @impl true
  def snapshot(state), do: {:ok, 1, %{actor: state.actor}}
  @impl true
  def restore_snapshot(1, %{"actor" => id}, context) do
    if Enum.any?(context.participants, &(&1.id == id)),
      do: {:ok, %__MODULE__{actor: id}},
      else: {:error, :invalid_actor}
  end
end
