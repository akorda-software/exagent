defmodule ExAgent.Session do
  @moduledoc """
  Single-writer coordination of application state and a participant roster.

  TurnPolicy uses struct state and controls scheduling/admission. Session enforces
  membership and lifecycle. A turn computes one complete coordination transition,
  then checkpoints it once. Change functions should calculate state, not perform
  external effects expecting transactional rollback.

  With Store, successful mutation replies follow save confirmation. Checkpoint
  errors preserve the new state in memory and block further mutations until
  `checkpoint/1` saves it; the change function is never retried. Restore loads
  validated conversation data, not processes or arbitrary executable continuations.
  JSON changes atom keys to strings and does not redact secret content.
  """
  use GenServer
  require Logger
  alias ExAgent.{Event, PubSub, RuntimeCheckpoint, Store}
  alias ExAgent.Session.{Participant, TurnPolicy, Snapshot}
  alias ExAgent.Observability.OpenTelemetry, as: Observability

  defmodule State do
    @moduledoc false
    defstruct session_id: nil,
              shared_state: nil,
              participants: %{},
              policy_mod: nil,
              policy_state: nil,
              current: nil,
              status: :created,
              pubsub: {ExAgent.PubSub.None, []},
              store: nil,
              topic: nil,
              seq: 0,
              metadata: %{},
              emitter_id: nil,
              revision: 0,
              checkpoint_error: nil,
              observability: nil

    @type t :: %__MODULE__{}
  end

  @doc """
  Start a Session with shared_state, policy, participants, session_id, pubsub,
  metadata and optional Store. Live participant refs are supplied by the app.
  Store errors/incompatible snapshots fail startup rather than starting empty.
  Additional participants after restore must be added explicitly with join/2.
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def join(session, %Participant{} = p), do: call(session, {:join, p})
  def join(session, opts), do: join(session, Participant.new(opts))
  def leave(session, id), do: call(session, {:leave, id})
  def start(session), do: call(session, :start)
  def current(session), do: GenServer.call(session, :current)
  def participants(session), do: GenServer.call(session, :participants)
  def status(session), do: GenServer.call(session, :status)
  def read_state(session), do: GenServer.call(session, :read_state)
  def take_turn(session, id, change), do: call(session, {:take_turn, id, change})
  def update_state(session, id, change), do: call(session, {:update_state, id, change})
  def end_turn(session, id), do: call(session, {:end_turn, id})
  @doc "Override the actor while preserving the policy scheduling cursor."
  def handoff(session, id), do: call(session, {:handoff, id})
  def pause(session), do: call(session, :pause)
  def resume(session), do: call(session, :resume)
  def close(session), do: call(session, :close)
  @doc "Retry only the unconfirmed save, without invoking a change function."
  def checkpoint(session), do: call(session, :checkpoint, :infinity)
  def health(session), do: GenServer.call(session, :health)

  defp call(session, command, timeout \\ 5000),
    do: GenServer.call(session, {:observed, command, Observability.capture_context()}, timeout)

  @impl true
  def init(opts) do
    {mod, policy_opts} = normalize_policy(Keyword.get(opts, :policy, :round_robin))
    participants = Keyword.get(opts, :participants, [])
    id = Keyword.get(opts, :session_id) || generate_id("session_")
    store = Store.normalize(Keyword.get(opts, :store))

    state = %State{
      session_id: id,
      shared_state: Keyword.get(opts, :shared_state),
      policy_mod: mod,
      store: store,
      observability: Keyword.get(opts, :observability),
      topic: Event.session_topic(id),
      pubsub: PubSub.normalize(Keyword.get(opts, :pubsub)),
      metadata: Keyword.get(opts, :metadata, %{}),
      emitter_id: generate_id("emitter_")
    }

    with true <- is_binary(id),
         :ok <- validate_roster(participants),
         {:ok, state} <-
           restore(
             %{state | participants: Map.new(participants, &{&1.id, &1})},
             Keyword.put(policy_opts, :participants, participants)
           ),
         :ok <- validate_actor(state) do
      {:ok, state}
    else
      false -> {:stop, :invalid_session_id}
      {:error, reason} -> {:stop, {:restore_failed, reason}}
    end
  end

  @impl true
  def handle_call({:observed, command, context}, from, state),
    do: Observability.with_context(context, fn -> handle_call(command, from, state) end)

  def handle_call(:read_state, _from, state), do: {:reply, state.shared_state, state}
  def handle_call(:current, _from, state), do: {:reply, state.current, state}

  def handle_call(:participants, _from, state),
    do: {:reply, Map.values(state.participants), state}

  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  def handle_call(:health, _from, state),
    do:
      {:reply,
       %{
         status: state.status,
         persistence: RuntimeCheckpoint.health(state),
         emitter_id: state.emitter_id
       }, state}

  def handle_call(:checkpoint, _from, state) do
    {reply, state} = RuntimeCheckpoint.retry(state, &Snapshot.new/1)
    {:reply, reply, state}
  end

  def handle_call(_, _from, %{checkpoint_error: error} = state) when not is_nil(error),
    do: {:reply, RuntimeCheckpoint.blocked(state), state}

  def handle_call(command, _from, state) do
    case transition(state, command) do
      {:ok, result, ^state, []} ->
        {:reply, result, state}

      {:ok, result, candidate, events} ->
        case validate_actor(candidate) do
          :ok ->
            {reply, candidate} =
              RuntimeCheckpoint.commit(candidate, :session, result, &Snapshot.new/1)

            candidate =
              Enum.reduce(events, candidate, fn {type, payload}, acc ->
                broadcast(
                  acc,
                  type,
                  Map.put(payload, :persistence, RuntimeCheckpoint.health(acc))
                )
              end)

            {:reply, reply, candidate}

          {:error, _} = error ->
            {:reply, error, state}
        end

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  defp transition(state, {:join, p}) do
    with :ok <- roster_open(state), :ok <- validate_roster([p]) do
      case Map.get(state.participants, p.id) do
        %Participant{kind: kind} when kind != p.kind ->
          {:error, :participant_kind_mismatch}

        %Participant{} ->
          {:ok, :ok, %{state | participants: Map.put(state.participants, p.id, p)}, []}

        nil ->
          with {:ok, policy} <-
                 policy_call(state, fn -> TurnPolicy.participant_joined(state.policy_state, p) end),
               :ok <- valid_policy(state, policy) do
            candidate = %{
              state
              | participants: Map.put(state.participants, p.id, p),
                policy_state: policy
            }

            {:ok, :ok, candidate, [{:participant_joined, %{participant_id: p.id, kind: p.kind}}]}
          end
      end
    end
  end

  defp transition(state, {:leave, id}) do
    with :ok <- roster_open(state),
         true <- Map.has_key?(state.participants, id),
         {:ok, policy} <-
           policy_call(state, fn -> TurnPolicy.participant_left(state.policy_state, id) end),
         :ok <- valid_policy(state, policy) do
      candidate = %{
        state
        | participants: Map.delete(state.participants, id),
          policy_state: policy
      }

      events = [{:participant_left, %{participant_id: id}}]

      cond do
        state.current == id and state.status == :running ->
          with {:ok, next, turn_events} <- advance(%{candidate | current: nil}) do
            {:ok, :ok, next, events ++ turn_events}
          end

        state.current == id ->
          {:ok, :ok, %{candidate | current: nil}, events}

        true ->
          {:ok, :ok, candidate, events}
      end
    else
      false -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp transition(%{status: :created} = state, :start) do
    with {:ok, state, events} <- advance(%{state | status: :running}) do
      result =
        if state.status == :done, do: {:error, :no_participants}, else: {:ok, state.current}

      {:ok, result, state, [{:session_started, %{first: state.current}} | events]}
    end
  end

  defp transition(state, :start), do: {:error, {:already_started, state.status}}

  defp transition(state, {kind, id, change}) when kind in [:take_turn, :update_state] do
    with :ok <- can_act(state, id),
         {:ok, shared_state} <- apply_change(state.shared_state, change) do
      candidate = %{state | shared_state: shared_state}
      events = [{:shared_state_updated, %{participant_id: id}}]

      if kind == :update_state do
        {:ok, {:ok, shared_state}, candidate, events}
      else
        with {:ok, candidate, turn_events} <- advance(candidate) do
          next = if candidate.status == :done, do: :done, else: candidate.current
          {:ok, {:ok, shared_state, next}, candidate, events ++ turn_events}
        end
      end
    end
  end

  defp transition(state, {:end_turn, id}) do
    with :ok <- can_act(state, id), {:ok, candidate, events} <- advance(state) do
      next = if candidate.status == :done, do: :done, else: candidate.current
      {:ok, {:ok, next}, candidate, events}
    end
  end

  defp transition(%{status: status}, {:handoff, _}) when status != :running,
    do: {:error, {:not_running, status}}

  defp transition(state, {:handoff, id}) do
    with :ok <- running(state),
         true <- Map.has_key?(state.participants, id),
         {:ok, outcome} <-
           policy_call(state, fn -> TurnPolicy.handoff(state.policy_state, id, context(state)) end),
         {:ok, policy} <- outcome,
         :ok <- valid_policy(state, policy),
         :ok <- validate_actor(%{state | current: id, policy_state: policy}) do
      {:ok, {:ok, id}, %{state | current: id, policy_state: policy},
       [{:session_turn_changed, %{participant_id: id, via: :handoff}}]}
    else
      false -> {:error, :not_a_participant}
      {:error, _} = error -> error
      _ -> {:error, :invalid_policy_return}
    end
  end

  defp transition(%{status: :running} = state, :pause),
    do: {:ok, :ok, %{state | status: :paused}, [{:session_paused, %{}}]}

  defp transition(state, :pause), do: {:error, {:not_running, state.status}}

  defp transition(%{status: :paused, current: nil} = state, :resume) do
    with {:ok, candidate, events} <- advance(%{state | status: :running}) do
      {:ok, :ok, candidate, [{:session_resumed, %{}} | events]}
    end
  end

  defp transition(%{status: :paused} = state, :resume) do
    with :ok <- validate_actor(state) do
      {:ok, :ok, %{state | status: :running}, [{:session_resumed, %{}}]}
    end
  end

  defp transition(state, :resume), do: {:error, {:not_paused, state.status}}
  defp transition(%{status: :closed} = state, :close), do: {:ok, :ok, state, []}

  defp transition(state, :close),
    do: {:ok, :ok, %{state | status: :closed}, [{:session_closed, %{}}]}

  defp transition(_, _), do: {:error, :invalid_command}

  defp advance(state) do
    with {:ok, outcome} <-
           policy_call(state, fn ->
             TurnPolicy.next_participant(state.policy_state, context(state))
           end) do
      case outcome do
        {:ok, id, policy} ->
          candidate = %{state | current: id, policy_state: policy}

          with :ok <- valid_policy(state, policy), :ok <- validate_actor(candidate) do
            {:ok, candidate, [{:session_turn_changed, %{participant_id: id}}]}
          end

        {:done, policy} ->
          with :ok <- valid_policy(state, policy) do
            {:ok, %{state | current: nil, status: :done, policy_state: policy}, []}
          end

        _ ->
          {:error, :invalid_policy_return}
      end
    end
  end

  defp can_act(state, id) do
    with :ok <- running(state),
         true <- Map.has_key?(state.participants, id),
         {:ok, true} <-
           policy_call(state, fn ->
             TurnPolicy.can_act?(state.policy_state, id, context(state))
           end) do
      :ok
    else
      false -> {:error, :not_your_turn}
      {:ok, false} -> {:error, :not_your_turn}
      {:error, _} = error -> error
      _ -> {:error, :invalid_policy_return}
    end
  end

  defp running(%{status: :running}), do: :ok
  defp running(%{status: :paused}), do: {:error, :paused}
  defp running(state), do: {:error, {:not_running, state.status}}
  defp roster_open(%{status: status}) when status in [:created, :running, :paused], do: :ok
  defp roster_open(state), do: {:error, {:not_running, state.status}}

  defp context(state),
    do: %{shared_state: state.shared_state, participants: Map.values(state.participants)}

  defp valid_policy(%{policy_mod: mod}, %mod{}), do: :ok
  defp valid_policy(_, _), do: {:error, :invalid_policy_state}

  defp policy_call(_state, fun) do
    {:ok, fun.()}
  rescue
    exception -> {:error, {:policy_exception, exception.__struct__}}
  catch
    kind, _ -> {:error, {:policy_failure, kind}}
  end

  defp validate_actor(state) do
    with :ok <- valid_policy(state, state.policy_state) do
      cond do
        is_nil(state.current) and state.status == :running ->
          {:error, :invalid_current}

        is_nil(state.current) ->
          :ok

        not Map.has_key?(state.participants, state.current) ->
          {:error, :invalid_current}

        true ->
          case policy_call(state, fn ->
                 TurnPolicy.can_act?(state.policy_state, state.current, context(state))
               end) do
            {:ok, true} -> :ok
            _ -> {:error, :invalid_current}
          end
      end
    end
  end

  defp apply_change(shared_state, change) do
    case change.(shared_state) do
      {:ok, state} -> {:ok, state}
      {:error, _} = error -> error
      state -> {:ok, state}
    end
  rescue
    exception -> {:error, {:change_exception, exception.__struct__}}
  catch
    kind, _ -> {:error, {:change_failure, kind}}
  end

  defp validate_roster(participants) when is_list(participants) do
    if Enum.all?(participants, fn
         %Participant{id: id, kind: kind, metadata: metadata} ->
           not is_nil(id) and kind in [:agent, :human] and is_map(metadata)

         _ ->
           false
       end) and length(participants) == MapSet.size(MapSet.new(participants, & &1.id)),
       do: :ok,
       else: {:error, :invalid_participants}
  end

  defp validate_roster(_), do: {:error, :invalid_participants}

  defp restore(%{store: nil} = state, opts), do: initialize_policy(state, opts)

  defp restore(state, opts) do
    case Store.load_session_snapshot(state.store, state.session_id) do
      {:error, :not_found} ->
        initialize_policy(state, opts)

      {:error, _} = error ->
        error

      {:ok, raw} ->
        with {:ok, snapshot} <- Snapshot.validate(raw, state.session_id),
             {:ok, participants} <- attach_participants(state.participants, snapshot.participants) do
          candidate = %{
            state
            | shared_state: snapshot.shared_state,
              participants: participants,
              current: snapshot.current,
              status: snapshot.status,
              revision: snapshot.revision
          }

          with {:ok, policy} <- Snapshot.restore(snapshot, state.policy_mod, context(candidate)),
               do: {:ok, %{candidate | policy_state: policy}}
        end
    end
  end

  defp initialize_policy(state, opts) do
    with {:ok, policy} <- policy_call(state, fn -> TurnPolicy.init(state.policy_mod, opts) end),
         :ok <- valid_policy(state, policy),
         do: {:ok, %{state | policy_state: policy}}
  end

  defp attach_participants(live, saved) do
    saved_map = Map.new(saved, &{&1.id, &1})

    if Enum.all?(live, fn {id, p} -> match?(%{kind: kind} when kind == p.kind, saved_map[id]) end) do
      {:ok,
       Map.new(saved, fn p ->
         {p.id, Map.get(live, p.id, Participant.new(id: p.id, kind: p.kind))}
       end)}
    else
      {:error, :snapshot_roster_mismatch}
    end
  end

  defp broadcast(state, type, payload) do
    seq = state.seq + 1

    event =
      Event.new(
        type: type,
        seq: seq,
        emitter_id: state.emitter_id,
        source: :session,
        session_id: state.session_id,
        payload: payload,
        metadata: state.metadata
      )

    case PubSub.broadcast(state.pubsub, state.topic, event) do
      :ok -> :ok
      {:error, _} -> Logger.warning("exagent session pubsub broadcast failed")
    end

    %{state | seq: seq}
  end

  defp normalize_policy(:round_robin), do: {ExAgent.Session.TurnPolicy.RoundRobin, []}
  defp normalize_policy(:initiative), do: {ExAgent.Session.TurnPolicy.Initiative, []}
  defp normalize_policy({:initiative, opts}), do: {ExAgent.Session.TurnPolicy.Initiative, opts}
  defp normalize_policy(:supervisor), do: {ExAgent.Session.TurnPolicy.SupervisorPolicy, []}

  defp normalize_policy({:supervisor, opts}),
    do: {ExAgent.Session.TurnPolicy.SupervisorPolicy, opts}

  defp normalize_policy({mod, opts}) when is_atom(mod), do: {mod, opts}
  defp normalize_policy(mod) when is_atom(mod), do: {mod, []}

  defp generate_id(prefix),
    do: prefix <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
