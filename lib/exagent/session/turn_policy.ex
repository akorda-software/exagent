defmodule ExAgent.Session.TurnPolicy do
  @moduledoc """
  Decides the order in which session participants take turns.

  A turn policy is a small, stateful module that sequences participants. The
  `ExAgent.Session` owns no scheduling logic of its own — it delegates "who acts
  next" and "may this participant act now" to the policy, so the same Session can
  drive a round-robin chat, an initiative-ordered combat, or a supervisor that
  delegates (Phase 4).

  Policy state is a struct whose module implements this behaviour; arbitrary map
  or tuple states are not dispatched. Handoff uses an explicit callback, or keeps
  state unchanged when the destination is already admitted by `can_act?/3`.
  Custom persistence requires the opt-in versioned data codec callbacks; stored
  bytes never select a module to load or execute.

  ## Callbacks

    * `init/1`              — build the policy state from options. `opts` carries
                              `:participants` (the initial list) plus any
                              policy-specific keys (e.g. `:order` for initiative).
    * `next_participant/2`  — return `{:ok, id, new_state}` for the next actor,
                              or `{:done, new_state}` when the sequence is
                              exhausted. `context` carries `%{shared_state: _, participants: _}`
                              for policies that need it.
    * `can_act?/3`          — whether `participant_id` may act right now (the
                              policy tracks the current actor).
    * `participant_joined/2` / `participant_left/2` — keep the policy's roster in
                              sync as participants come and go.

  ## Built-in implementations

    * `ExAgent.Session.TurnPolicy.RoundRobin` — insertion order, cycling forever.
    * `ExAgent.Session.TurnPolicy.Initiative` — an explicit `:order`, cycling forever.
    * (Phase 4) `SupervisorDriven` — a coordinator participant directs others.
  """

  alias ExAgent.Session.Participant

  @type id :: term()
  @type state :: struct()
  @type context :: %{shared_state: term(), participants: [Participant.t()]}

  @callback init(opts :: keyword()) :: state()

  @callback next_participant(state(), context()) ::
              {:ok, id(), state()} | {:done, state()}

  @callback can_act?(state(), participant_id :: id(), context()) :: boolean()

  @callback participant_joined(state(), Participant.t()) :: state()

  @callback participant_left(state(), id()) :: state()

  @doc "Override the current actor without advancing the scheduling cursor."
  @callback handoff(state(), id(), context()) :: {:ok, state()} | {:error, term()}

  @doc "Opt-in JSON data codec for persisted custom policies."
  @callback snapshot(state()) :: {:ok, pos_integer(), term()} | {:error, term()}
  @callback restore_snapshot(pos_integer(), term(), context()) ::
              {:ok, state()} | {:error, term()}

  @optional_callbacks [
    participant_joined: 2,
    participant_left: 2,
    handoff: 3,
    snapshot: 1,
    restore_snapshot: 3
  ]

  # ---------------------------------------------------------------------------
  # Dispatch (struct-based, like ExAgent.Model). Lets callers hold an opaque
  # policy state and call through this module without knowing the impl.
  # ---------------------------------------------------------------------------

  @spec init(module(), keyword()) :: state()
  def init(mod, opts) when is_atom(mod), do: mod.init(opts)

  @spec next_participant(state(), context()) ::
          {:ok, id(), state()} | {:done, state()}
  def next_participant(%mod{} = state, ctx), do: mod.next_participant(state, ctx)

  @spec can_act?(state(), id(), context()) :: boolean()
  def can_act?(%mod{} = state, id, ctx), do: mod.can_act?(state, id, ctx)

  @spec participant_joined(state(), Participant.t()) :: state()
  def participant_joined(%mod{} = state, participant) do
    if function_exported?(mod, :participant_joined, 2) do
      mod.participant_joined(state, participant)
    else
      state
    end
  end

  @spec participant_left(state(), id()) :: state()
  def participant_left(%mod{} = state, id) do
    if function_exported?(mod, :participant_left, 2) do
      mod.participant_left(state, id)
    else
      state
    end
  end

  def handoff(%mod{} = state, id, ctx) do
    cond do
      function_exported?(mod, :handoff, 3) -> mod.handoff(state, id, ctx)
      mod.can_act?(state, id, ctx) == true -> {:ok, state}
      true -> {:error, :unsupported_handoff}
    end
  end
end
