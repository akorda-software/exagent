defmodule ExAgent.Server do
  @moduledoc """
  Supervised owner of conversational history, model state and accumulated usage.

  Runs execute in owned supervised tasks. Stopping or killing the Server kills
  its active worker; external effects and detached user processes cannot be undone.
  `chat/3` waits for completion; `send_message/3`, `steer/3` and `stream/3` return
  an admission id for volatile work, not a durable execution acknowledgement.

  With an opt-in Store, terminal success follows a confirmed checkpoint. A failed
  save returns `ExAgent.CheckpointError`, preserving the execution outcome and
  new state in memory. Mutations and queue draining then wait for `checkpoint/1`,
  which retries only saving. Adapter IO is synchronous and must be bounded by the
  adapter. Recovery restores conversation data, never replays tools or queued work.

  Events use the agent topic and a sequence local to `emitter_id`. A living owner
  attempts one terminal emission per run; PubSub is not a durable event log.
  """
  use GenServer
  require Logger
  alias ExAgent.{Event, PubSub, RunEvent, RunError, RuntimeCheckpoint, Store}
  alias ExAgent.Message.Usage
  alias ExAgent.Server.Snapshot
  alias ExAgent.Observability.OpenTelemetry, as: Observability

  defmodule State do
    @moduledoc false
    defstruct agent: nil,
              model: nil,
              history: [],
              usage: %Usage{input_tokens: 0, output_tokens: 0},
              status: :idle,
              current: nil,
              pending: :queue.new(),
              max_pending: 8,
              pubsub: {ExAgent.PubSub.None, []},
              store: nil,
              topic: nil,
              agent_id: nil,
              seq: 0,
              metadata: %{},
              emitter_id: nil,
              revision: 0,
              checkpoint_error: nil,
              observability: nil
  end

  @doc """
  Start with `:agent` and optional `:agent_id`, `:name`, `:store`, `:pubsub`,
  `:metadata`, `:max_pending` (8). Only Store not_found starts a new conversation;
  invalid/incompatible snapshots or load failures return a controlled error.
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: {:exagent_server, opts[:agent_id] || opts[:name] || make_ref()},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  @doc """
  Execute a run. Options include deps, model_settings, stream_text, estimate_cost,
  permissions and approve. Explicit message_history overrides accumulated context;
  run_id, on_event, on_progress and instruction management belong to the Server.
  A call timeout does not cancel work already owned by the Server.
  """
  def chat(server, prompt, opts \\ []),
    do:
      GenServer.call(
        server,
        {:chat, prompt, Observability.options(opts)},
        Keyword.get(opts, :timeout, :infinity)
      )

  def send_message(server, prompt, opts \\ []),
    do: GenServer.call(server, {:send_message, prompt, Observability.options(opts)})

  def steer(server, prompt, opts \\ []),
    do: GenServer.call(server, {:steer, prompt, Observability.options(opts)})

  @doc "Run the same agentic loop with provisional text deltas and one complete terminal."
  def stream(server, prompt, opts \\ []),
    do: GenServer.call(server, {:stream, prompt, Observability.options(opts)})

  @doc "Request cancellation; idempotent. Does not undo external effects."
  def abort(server), do: GenServer.call(server, :abort)
  def set_model(server, model), do: GenServer.call(server, {:set_model, model})
  def history(server), do: GenServer.call(server, :history)
  def usage(server), do: GenServer.call(server, :usage)
  def health(server), do: GenServer.call(server, :health)

  def reset(server),
    do: GenServer.call(server, {:observed, :reset, Observability.capture_context()})

  @doc "Retry an unconfirmed snapshot only, without repeating execution."
  def checkpoint(server),
    do:
      GenServer.call(server, {:observed, :checkpoint, Observability.capture_context()}, :infinity)

  @impl true
  def init(opts) do
    agent = Keyword.fetch!(opts, :agent)
    id = Keyword.get(opts, :agent_id) || generate_id("agent_")
    store = Store.normalize(Keyword.get(opts, :store))
    max_pending = Keyword.get(opts, :max_pending, 8)

    with true <- is_binary(id) and is_integer(max_pending) and max_pending >= 0,
         {:ok, restored} <- load_state(store, id) do
      {:ok,
       %State{
         agent: agent,
         model: agent.model,
         agent_id: id,
         history: restored.history,
         usage: restored.usage,
         revision: restored.revision,
         topic: Event.agent_topic(id),
         pubsub: PubSub.normalize(Keyword.get(opts, :pubsub)),
         store: store,
         observability: Keyword.get(opts, :observability, agent.observability),
         max_pending: max_pending,
         metadata: Keyword.get(opts, :metadata, %{}),
         emitter_id: generate_id("emitter_")
       }}
    else
      false -> {:stop, :invalid_max_pending}
      {:error, reason} -> {:stop, {:restore_failed, reason}}
    end
  end

  @impl true
  def handle_call({:observed, command, context}, from, state) do
    Observability.with_context(context, fn -> handle_call(command, from, state) end)
  end

  def handle_call(:history, _from, state), do: {:reply, state.history, state}
  def handle_call(:usage, _from, state), do: {:reply, state.usage, state}

  def handle_call(:health, _from, state) do
    {:reply,
     %{
       status: state.status,
       pending: :queue.len(state.pending),
       persistence: RuntimeCheckpoint.health(state),
       emitter_id: state.emitter_id
     }, state}
  end

  def handle_call(:checkpoint, _from, %{current: current} = state) when not is_nil(current),
    do: {:reply, {:error, :busy}, state}

  def handle_call(:checkpoint, _from, state) do
    {result, state} = RuntimeCheckpoint.retry(state, &snapshot/1)
    {:reply, result, drain(state)}
  end

  def handle_call(:abort, _from, %{current: nil} = state), do: {:reply, :ok, state}

  def handle_call(:abort, _from, state) do
    cur = state.current
    _ = Task.Supervisor.terminate_child(ExAgent.TaskSupervisor, cur.pid)
    result = failure(cur, :aborted, :cancelled)
    {:reply, :ok, finish(state, result, :server_request_cancelled, :last_progress)}
  end

  # Read/control remain available while the last complete revision is unconfirmed.
  def handle_call(_mutation, _from, %{checkpoint_error: error} = state) when not is_nil(error),
    do: {:reply, RuntimeCheckpoint.blocked(state), state}

  def handle_call({:chat, _, _}, _from, %{status: :running} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:chat, prompt, opts}, from, state),
    do: {:noreply, start_run(state, prompt, opts, {:call, from}, false)}

  def handle_call({kind, prompt, opts}, _from, %{status: :idle} = state)
      when kind in [:send_message, :steer, :stream] do
    state = start_run(state, prompt, opts, :event, kind == :stream)
    {:reply, {:ok, state.current.request_id}, state}
  end

  def handle_call({:stream, _, _}, _from, state), do: {:reply, {:error, :busy}, state}

  def handle_call({kind, prompt, opts}, _from, state) when kind in [:send_message, :steer] do
    if :queue.len(state.pending) >= state.max_pending do
      {:reply, {:error, :queue_full}, state}
    else
      id = request_id(opts)
      entry = {prompt, Keyword.put(opts, :request_id, id)}

      pending =
        if kind == :steer,
          do: :queue.in_r(entry, state.pending),
          else: :queue.in(entry, state.pending)

      {:reply, {:ok, id}, %{state | pending: pending}}
    end
  end

  def handle_call({:set_model, _}, _from, %{status: :running} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:set_model, spec}, _from, state) do
    case resolve_model(spec) do
      {:ok, model} -> {:reply, :ok, %{state | model: model, agent: %{state.agent | model: model}}}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:reset, _from, %{status: :running} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call(:reset, _from, state) do
    state = %{state | history: [], usage: %Usage{input_tokens: 0, output_tokens: 0}}
    {result, state} = RuntimeCheckpoint.commit(state, :agent, :ok, &snapshot/1)
    {:reply, result, state}
  end

  @impl true
  def handle_info({ref, result}, %{current: %{ref: ref}} = state),
    do: {:noreply, finish(state, result)}

  def handle_info({:DOWN, ref, :process, _, reason}, %{current: %{ref: ref} = cur} = state),
    do: {:noreply, finish(state, failure(cur, {:crashed, reason}, :failed), nil, :last_progress)}

  def handle_info({:run_progress, run_id, progress}, %{current: %{run_id: run_id} = cur} = state)
      when is_map(progress) do
    # This is a run subtotal, not an increment. Only terminal integration adds it.
    {:noreply, %{state | current: %{cur | progress: progress}}}
  end

  def handle_info({:stream_delta, run_id, text}, %{current: %{run_id: run_id} = cur} = state),
    do: {:noreply, broadcast(state, :text_delta, cur, %{text: text})}

  def handle_info(
        {:run_event, %RunEvent{run_id: run_id} = event},
        %{current: %{run_id: run_id} = cur} = state
      ) do
    cond do
      event.type in [:run_finished, :run_failed] -> {:noreply, state}
      cur.streaming? and event.type == :text_delta -> {:noreply, state}
      true -> {:noreply, broadcast(state, event.type, cur, build_payload(event))}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp start_run(state, prompt, opts, reply_to, streaming?) do
    id = request_id(opts)
    run_id = generate_id("run_")
    parent = self()
    agent = %{state.agent | model: state.model}
    config = Observability.configuration(state.observability, opts)

    operation =
      Observability.start(
        config,
        :run,
        Observability.ids(%{
          run_id: run_id,
          root_run_id: run_id,
          agent_id: state.agent_id,
          request_id: id
        }),
        opts[:trace_context]
      )

    run_opts =
      build_run_opts(state, run_id, opts)
      |> Keyword.put(:observability, config)
      |> Keyword.put(:observability_operation, operation)
      |> Keyword.put(:trace_context, Observability.context(operation))

    task =
      start_owned_task(fn ->
        if streaming? do
          ExAgent.run_stream(agent, prompt, run_opts)
          |> Enum.reduce(nil, fn
            {:delta, text}, acc ->
              send(parent, {:stream_delta, run_id, text})
              acc

            {:result, result}, _ ->
              {:ok, result}

            {:error, reason}, _ ->
              {:error, reason}
          end)
        else
          ExAgent.run(agent, prompt, run_opts)
        end
      end)

    partial = %{
      output: nil,
      messages: run_opts[:message_history],
      new_messages: [],
      usage: %Usage{input_tokens: 0, output_tokens: 0},
      model: state.model,
      run_step: 0,
      run_id: run_id,
      status: :running,
      usage_status: :unknown
    }

    %{
      state
      | status: :running,
        current: %{
          ref: task.ref,
          pid: task.pid,
          reply_to: reply_to,
          request_id: id,
          run_id: run_id,
          progress: partial,
          streaming?: streaming?,
          observation: operation,
          observability: config
        }
    }
  end

  defp build_run_opts(state, run_id, opts) do
    parent = self()
    history = Keyword.get(opts, :message_history) || state.history

    opts
    |> Keyword.take([
      :deps,
      :model_settings,
      :stream_text,
      :estimate_cost,
      :deadline,
      :max_concurrent_requests,
      :permissions,
      :approve
    ])
    |> Keyword.merge(
      message_history: history,
      prepend_instructions: history == [],
      run_id: run_id,
      on_event: fn event -> send(parent, {:run_event, event}) end,
      on_progress: fn progress -> send(parent, {:run_progress, run_id, progress}) end
    )
  end

  defp failure(cur, reason, status) do
    # The last progress message may predate admission of in-flight work. Keep
    # its observed subtotals, but never claim they are a complete bill or usage.
    partial =
      Map.merge(cur.progress, %{status: status, usage_status: :partial, cost_status: :unknown})

    {:error, %RunError{reason: reason, partial: partial}}
  end

  defp finish(state, outcome, terminal_type \\ nil, observation_source \\ :confirmed) do
    Observability.within(state.current.observation, fn ->
      finish_observed(state, outcome, terminal_type, observation_source)
    end)
  end

  defp finish_observed(state, outcome, terminal_type, observation_source) do
    cur = state.current
    Process.demonitor(cur.ref, [:flush])

    {outcome, observation_source} =
      case outcome do
        {:ok, result} when is_map(result) -> {{:ok, result}, observation_source}
        {:error, _} = error -> {error, observation_source}
        _ -> {failure(cur, :missing_terminal_result, :failed), :last_progress}
      end

    progress =
      case outcome do
        {:ok, result} -> result
        {:error, %RunError{partial: partial}} -> partial
        _ -> cur.progress
      end

    state = integrate(state, progress)

    {outcome, state} =
      RuntimeCheckpoint.commit(state, :agent, outcome, &snapshot/1,
        observability: cur.observability,
        trace_context: Observability.context(cur.observation)
      )

    Observability.run_result(cur.observation, outcome, observation_source)
    Observability.finish(cur.observation, outcome)

    {type, payload} =
      case outcome do
        {:ok, result} -> {:run_finished, Event.result_payload(result)}
        {:error, reason} -> {terminal_type || :run_failed, Event.error_payload(reason)}
      end

    state =
      broadcast(state, type, cur, Map.put(payload, :persistence, RuntimeCheckpoint.health(state)))

    if match?({:call, _}, cur.reply_to) do
      {:call, from} = cur.reply_to
      GenServer.reply(from, outcome)
    end

    drain(%{state | current: nil, status: :idle})
  end

  defp integrate(state, progress) do
    %{
      state
      | history: Map.get(progress, :messages, state.history),
        model: Map.get(progress, :model, state.model),
        usage: merge_usage(state.usage, Map.get(progress, :usage))
    }
  end

  defp merge_usage(acc, nil), do: acc

  defp merge_usage(acc, usage) do
    %Usage{
      input_tokens: (acc.input_tokens || 0) + (usage.input_tokens || 0),
      output_tokens: (acc.output_tokens || 0) + (usage.output_tokens || 0),
      details:
        merge_details(
          ExAgent.SnapshotData.json(acc.details || %{}),
          ExAgent.SnapshotData.json(usage.details || %{})
        )
    }
  end

  defp merge_details(left, right) do
    Map.merge(left, right, fn
      _, a, b when is_number(a) and is_number(b) -> a + b
      _, a, b when is_map(a) and is_map(b) -> merge_details(a, b)
      _, _, b -> b
    end)
  end

  defp drain(%{checkpoint_error: error} = state) when not is_nil(error), do: state
  defp drain(%{current: current} = state) when not is_nil(current), do: state

  defp drain(state) do
    case :queue.out(state.pending) do
      {:empty, _} ->
        %{state | status: :idle}

      {{:value, {prompt, opts}}, rest} ->
        start_run(%{state | pending: rest}, prompt, opts, :event, false)
    end
  end

  defp snapshot(state) do
    Snapshot.new(
      agent_id: state.agent_id,
      history: state.history,
      usage: state.usage,
      metadata: state.metadata,
      revision: state.revision
    )
  end

  defp load_state(nil, _),
    do: {:ok, %{history: [], usage: %Usage{input_tokens: 0, output_tokens: 0}, revision: 0}}

  defp load_state(store, id) do
    case Store.load_agent_snapshot(store, id) do
      {:ok, raw} ->
        with {:ok, snapshot} <- Snapshot.validate(raw, id),
             {:ok, history} <- Snapshot.messages(snapshot) do
          {:ok,
           %{
             history: history,
             usage: Snapshot.usage_struct(snapshot),
             revision: snapshot.revision
           }}
        end

      {:error, :not_found} ->
        load_state(nil, id)

      {:error, _} = error ->
        error
    end
  end

  defp broadcast(state, type, cur, payload) do
    seq = state.seq + 1

    event =
      Event.new(
        type: type,
        seq: seq,
        emitter_id: state.emitter_id,
        source: if(type == :server_request_cancelled, do: :server, else: :run),
        agent_id: state.agent_id,
        run_id: cur.run_id,
        request_id: cur.request_id,
        payload: payload,
        metadata: state.metadata
      )

    case PubSub.broadcast(state.pubsub, state.topic, event) do
      :ok -> :ok
      {:error, _} -> Logger.warning("exagent pubsub broadcast failed")
    end

    %{state | seq: seq}
  end

  defp build_payload(%RunEvent{type: :run_started, data: data}),
    do: %{prompt: Map.get(data, :prompt)}

  defp build_payload(%RunEvent{type: type, step: step})
       when type in [:run_step_started, :run_step_finished], do: %{step: step}

  defp build_payload(%RunEvent{type: type, data: data})
       when type in [:text_delta, :thinking_delta], do: Map.take(data, [:text])

  defp build_payload(%RunEvent{type: type, step: step, data: data})
       when type in [:tool_call_started, :tool_call_finished] do
    Map.take(data, [:tool_name, :tool_call_id, :args, :success, :duration_ms])
    |> Map.put(:step, step)
  end

  defp build_payload(_), do: %{}

  # Guardian is established before executing user code; handles even owner :kill.
  defp start_owned_task(fun) do
    owner = self()

    Task.Supervisor.async_nolink(ExAgent.TaskSupervisor, fn ->
      worker = self()
      ready = make_ref()
      spawn_link(fn -> watch_run(owner, worker, ready) end)

      receive do
        {^ready, :ready} -> fun.()
      end
    end)
  end

  defp watch_run(owner, worker, ready) do
    owner_ref = Process.monitor(owner)
    worker_ref = Process.monitor(worker)
    send(worker, {ready, :ready})

    receive do
      {:DOWN, ^owner_ref, :process, ^owner, _} -> Process.exit(worker, :kill)
      {:DOWN, ^worker_ref, :process, ^worker, _} -> :ok
    end
  end

  defp request_id(opts), do: Keyword.get(opts, :request_id) || generate_id("req_")
  defp resolve_model(%_{} = model), do: {:ok, model}
  defp resolve_model(spec), do: ExAgent.Model.resolve(spec)

  defp generate_id(prefix),
    do: prefix <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
