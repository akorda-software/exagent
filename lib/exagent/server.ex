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
              usage: Usage.sum([]),
              status: :idle,
              current: nil,
              pending: :queue.new(),
              max_pending: 8,
              pending_bytes: 0,
              max_input_bytes: 1_048_576,
              max_pending_bytes: 8_388_608,
              max_history_bytes: 8_388_608,
              pubsub: {ExAgent.PubSub.None, []},
              store: nil,
              topic: nil,
              agent_id: nil,
              namespace: nil,
              seq: 0,
              metadata: %{},
              emitter_id: nil,
              revision: 0,
              checkpoint_error: nil,
              continuation_config: nil,
              continuation_reference: nil,
              continuation_checkpoint: nil,
              continuation_abort_run_id: nil,
              continuation_abort_request_id: nil,
              observability: nil
  end

  @doc """
  Start with `:agent` and optional `:agent_id`, `:name`, `:store`, `:pubsub`,
  `:namespace` (trusted application string, nil for legacy), `:metadata`,
  `:max_pending` (8). Only Store not_found starts a new conversation;
  invalid/incompatible snapshots or load failures return a controlled error.

  Payload admission options are `:max_input_bytes` (1MiB), `:max_pending_bytes`
  and `:max_history_bytes` (8MiB each), integers1..64MiB. Bytes mean uncompressed
  Erlang external term size, including opts/deps/callback representation, not
  JSON, referenced resources or live RAM. Input/history errors reject before
  admission; pending count/bytes return `:queue_full`. Queued work rechecks input
  and history when dequeued; health exposes charged pending bytes.

  History limits gate admission/restore, not output retention of the current run.
  Canonical history is never silently truncated. Application-created terms and
  mailbox traffic already exist before these checks. Caller timeout is not cancel.
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

  @doc "Query the persisted continuation independently of PubSub delivery."
  def continuation(server), do: GenServer.call(server, :continuation)

  @doc "Persist a host-authorized decision; this call does not resume the run."
  def decide(server, decision, opts),
    do: GenServer.call(server, {:decide, decision, opts}, :infinity)

  @doc "Resume the pending logical run with fresh host deps/options in a new owned worker."
  def resume(server, opts \\ []),
    do: GenServer.call(server, {:resume, Observability.options(opts)}, :infinity)

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
    namespace = Keyword.get(opts, :namespace)
    max_pending = Keyword.get(opts, :max_pending, 8)

    limits =
      Map.new([:max_input_bytes, :max_pending_bytes, :max_history_bytes], fn key ->
        {key, Keyword.get(opts, key, Map.fetch!(%State{}, key))}
      end)

    with true <- is_binary(id) and is_integer(max_pending) and max_pending >= 0,
         :ok <- ExAgent.RuntimeIdentity.validate(namespace, id),
         :ok <- validate_payload_limits(limits),
         store = Store.scoped(Keyword.get(opts, :store), namespace),
         {:ok, continuation_config} <- continuation_config(opts[:continuation], store, id),
         {:ok, restored} <- load_runtime_state(store, id, continuation_config, agent),
         :ok <- size_limit(restored.history, limits.max_history_bytes, :history_too_large),
         :ok <- ExAgent.Retention.check(restored.usage, ExAgent.Retention.usage_bytes(), :usage) do
      {:ok,
       %State{
         agent: agent,
         model: Map.get(restored, :model, agent.model),
         agent_id: id,
         namespace: namespace,
         history: restored.history,
         usage: restored.usage,
         revision: restored.revision,
         status: Map.get(restored, :status, :idle),
         continuation_config: continuation_config,
         continuation_reference: Map.get(restored, :continuation),
         topic: Event.agent_topic(id, namespace),
         pubsub: PubSub.normalize(Keyword.get(opts, :pubsub)),
         store: store,
         observability: Keyword.get(opts, :observability, agent.observability),
         max_pending: max_pending,
         max_input_bytes: limits.max_input_bytes,
         max_pending_bytes: limits.max_pending_bytes,
         max_history_bytes: limits.max_history_bytes,
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

  def handle_call(
        {:continuation_writer, run_id, token, writer},
        _from,
        %{current: %{run_id: run_id, owner_token: token} = current} = state
      )
      when is_pid(writer) do
    if is_nil(current.writer) or current.writer == writer,
      do: {:reply, :ok, %{state | current: %{current | writer: writer}}},
      else: {:reply, :stale, state}
  end

  def handle_call({:continuation_writer, _, _, _}, _from, state), do: {:reply, :stale, state}

  def handle_call(:health, _from, state) do
    {:reply,
     %{
       status: state.status,
       pending: :queue.len(state.pending),
       pending_bytes: state.pending_bytes,
       persistence: persistence(state),
       emitter_id: state.emitter_id,
       namespace: state.namespace,
       continuation: state.continuation_reference,
       continuation_abort_run_id: state.continuation_abort_run_id
     }, state}
  end

  def handle_call(:checkpoint, _from, %{current: current} = state) when not is_nil(current),
    do: {:reply, {:error, :busy}, state}

  def handle_call(:continuation, _from, %{continuation_config: nil} = state),
    do: {:reply, {:error, :continuation_not_configured}, state}

  def handle_call(:continuation, _from, state),
    do: {:reply, ExAgent.Continuation.get(state.store, state.agent_id), state}

  def handle_call({:decide, _, _}, _from, %{continuation_config: nil} = state),
    do: {:reply, {:error, :continuation_not_configured}, state}

  def handle_call({:decide, _, _}, _from, %{continuation_checkpoint: token} = state)
      when not is_nil(token),
      do: {:reply, {:error, :checkpoint_pending}, state}

  def handle_call({:decide, decision, opts}, _from, state) do
    result = ExAgent.Continuation.decide(state.store, state.agent_id, decision, opts)

    state =
      case result do
        {:ok, %{record: record, replayed: replayed}} ->
          state = state_from_record(state, record)

          if replayed,
            do: state,
            else:
              broadcast(
                state,
                :approval_decided,
                %{
                  run_id: record["execution"]["run_id"],
                  request_id: record["execution"]["request_id"]
                },
                %{
                  decision: decision,
                  continuation: Event.continuation_reference(state.continuation_reference)
                }
              )

        _ ->
          state
      end

    {:reply, result, drain(state)}
  end

  def handle_call({:resume, _}, _from, %{continuation_config: nil} = state),
    do: {:reply, {:error, :continuation_not_configured}, state}

  def handle_call({:resume, _}, _from, %{current: current} = state) when not is_nil(current),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:resume, _}, _from, %{continuation_checkpoint: token} = state)
      when not is_nil(token),
      do: {:reply, {:error, :checkpoint_pending}, state}

  def handle_call({:resume, opts}, from, state) do
    case Store.load_record(state.store, :agent, state.agent_id) do
      {:ok, %{"execution" => %{"state" => "ready"}} = record} ->
        ref = record_reference(record, state.agent_id)

        base =
          case record["execution"]["progress"]["conversation_usage"] do
            nil -> Usage.sum([])
            data -> Usage.from_map!(data)
          end

        opts =
          opts
          |> Keyword.put(:resume_reference, ref)
          |> Keyword.put(:request_id, record["execution"]["request_id"])
          |> Keyword.put(:continuation_base_usage, base)

        {:noreply, start_run(state, nil, opts, {:call, from}, opts[:stream_text] == true)}

      {:ok, record} ->
        {:reply, {:error, {:continuation_not_ready, record["execution"]["state"]}}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:checkpoint, _from, %{continuation_config: config} = state)
      when not is_nil(config) do
    case state.continuation_checkpoint do
      nil ->
        {:reply, :ok, state}

      token ->
        case ExAgent.Continuation.retry_checkpoint(state.store, token) do
          {:ok, %{record: record}} = result ->
            state =
              state_from_record(
                %{
                  state
                  | continuation_checkpoint: nil,
                    continuation_abort_run_id: nil,
                    continuation_abort_request_id: nil
                },
                record
              )

            {:reply, result, drain(state)}

          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call(:checkpoint, _from, state) do
    {result, state} = RuntimeCheckpoint.retry(state, &snapshot/1)
    {:reply, result, drain(state)}
  end

  def handle_call(:abort, _from, %{continuation_checkpoint: token} = state)
      when not is_nil(token), do: {:reply, {:error, :checkpoint_pending}, state}

  def handle_call(:abort, _from, %{continuation_config: config} = state)
      when not is_nil(config) do
    if state.current && state.current.progress[:continuation_checkpoint] do
      {:reply, {:error, :checkpoint_pending}, state}
    else
      current = state.current

      state =
        if current,
          do: %{
            state
            | continuation_abort_run_id: current.run_id,
              continuation_abort_request_id: current.request_id
          },
          else: state

      quiescence = stop_continuation_worker(current)

      {cancelled, state} =
        if quiescence == :ok, do: cancel_continuation(state), else: {quiescence, state}

      state =
        if current,
          do:
            finish(
              state,
              failure(current, :aborted, :cancelled),
              :server_request_cancelled,
              :last_progress
            ),
          else: state

      case cancelled do
        {:ok, nil} ->
          {:reply, :ok,
           drain(%{
             state
             | status: :idle,
               continuation_reference: nil,
               continuation_abort_run_id: nil,
               continuation_abort_request_id: nil
           })}

        {:ok, record} ->
          {:reply, :ok,
           drain(
             state_from_record(
               %{state | continuation_abort_run_id: nil, continuation_abort_request_id: nil},
               record
             )
           )}

        {:error, _} = error ->
          {:reply, error, %{state | status: :blocked}}
      end
    end
  end

  def handle_call(:abort, _from, %{current: nil} = state), do: {:reply, :ok, state}

  def handle_call(:abort, _from, state) do
    cur = state.current
    _ = Task.Supervisor.terminate_child(ExAgent.TaskSupervisor, cur.pid)
    result = failure(cur, :aborted, :cancelled)
    {:reply, :ok, finish(state, result, :server_request_cancelled, :last_progress)}
  end

  # Read/control remain available while the last complete revision is unconfirmed.
  def handle_call(_mutation, _from, %{continuation_checkpoint: token} = state)
      when not is_nil(token),
      do: {:reply, {:error, :checkpoint_pending}, state}

  def handle_call(_mutation, _from, %{checkpoint_error: error} = state) when not is_nil(error),
    do: {:reply, RuntimeCheckpoint.blocked(state), state}

  def handle_call({:chat, _, _}, _from, %{status: :running} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({kind, _, _}, _from, %{status: status} = state)
      when kind in [:chat, :stream] and status in [:paused, :blocked, :reset_required],
      do: {:reply, {:error, :continuation_pending}, state}

  def handle_call({:set_model, _}, _from, %{status: status} = state)
      when status in [:paused, :blocked, :reset_required],
      do: {:reply, {:error, :continuation_pending}, state}

  def handle_call(:reset, _from, %{status: status} = state) when status in [:paused, :blocked],
    do: {:reply, {:error, :continuation_pending}, state}

  def handle_call({:chat, prompt, opts}, from, state) do
    case admission(state, prompt, opts) do
      :ok -> {:noreply, start_run(state, prompt, opts, {:call, from}, false)}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({kind, prompt, opts}, _from, %{status: :idle} = state)
      when kind in [:send_message, :steer, :stream] do
    case admission(state, prompt, opts) do
      :ok ->
        state = start_run(state, prompt, opts, :event, kind == :stream)
        {:reply, {:ok, state.current.request_id}, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:stream, _, _}, _from, state), do: {:reply, {:error, :busy}, state}

  def handle_call({kind, prompt, opts}, _from, state) when kind in [:send_message, :steer] do
    id = request_id(opts)
    opts = Keyword.put(opts, :request_id, id)
    entry = {prompt, opts}
    bytes = :erlang.external_size(entry)

    with :ok <- admission(state, prompt, opts) do
      if :queue.len(state.pending) >= state.max_pending or
           state.pending_bytes + bytes > state.max_pending_bytes do
        {:reply, {:error, :queue_full}, state}
      else
        pending =
          if kind == :steer,
            do: :queue.in_r({entry, bytes}, state.pending),
            else: :queue.in({entry, bytes}, state.pending)

        {:reply, {:ok, id},
         %{state | pending: pending, pending_bytes: state.pending_bytes + bytes}}
      end
    else
      {:error, _} = error -> {:reply, error, state}
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

  def handle_call(:reset, _from, %{continuation_config: config} = state)
      when not is_nil(config) do
    case Store.load_record(state.store, :agent, state.agent_id) do
      {:error, :not_found} ->
        {:reply, :ok, %{state | history: [], usage: Usage.sum([])}}

      {:ok, %{"execution" => %{"state" => terminal}} = record}
      when terminal in ~w(completed denied expired cancelled) ->
        candidate = %{
          state
          | history: [],
            usage: Usage.sum([]),
            revision: record["snapshot"]["revision"] + 1
        }

        command = %{
          "record_id" => record["record_id"],
          "operation" => "reset_snapshot",
          "operation_id" => generate_id("reset_"),
          "actor_id" => "exagent-server",
          "payload" => %{
            "snapshot" => ExAgent.Continuation.Record.snapshot_data(snapshot(candidate))
          }
        }

        token = %{
          "token_version" => 1,
          "namespace" => config.store.namespace,
          "id" => state.agent_id,
          "expected_revision" => record["revision"],
          "command" => command
        }

        limit = Map.get(config, :max_checkpoint_bytes, ExAgent.Continuation.Record.max_bytes())

        case ExAgent.Retention.check(token, limit, :checkpoint) do
          :ok ->
            case ExAgent.Continuation.retry_checkpoint(state.store, token) do
              {:ok, %{record: saved}} ->
                {:reply, :ok, drain(state_from_record(state, saved))}

              {:error, reason} ->
                error = %ExAgent.CheckpointError{
                  operation: :agent,
                  reason: ExAgent.Retention.reason(reason),
                  result: :ok,
                  revision: record["revision"] + 1
                }

                {:reply, {:error, error},
                 %{state | continuation_checkpoint: token, status: :blocked}}
            end

          {:error, _} = error ->
            {:reply, error, state}
        end

      {:ok, record} ->
        {:reply, {:error, :continuation_pending}, state_from_record(state, record)}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:reset, _from, state) do
    state = %{state | history: [], usage: Usage.sum([])}
    {result, state} = RuntimeCheckpoint.commit(state, :agent, :ok, &snapshot/1)
    {:reply, result, state}
  end

  def handle_call(
        {:run_progress_ack, run_id, progress},
        _from,
        %{current: %{run_id: run_id} = cur} = state
      ),
      do: {:reply, :ok, %{state | current: %{cur | progress: progress}}}

  def handle_call({:run_event_ack, event}, _from, state) do
    {:noreply, state} = handle_info({:run_event, event}, state)
    {:reply, :ok, state}
  end

  def handle_call({:stream_delta_ack, run_id, text}, _from, state) do
    {:noreply, state} = handle_info({:stream_delta, run_id, text}, state)
    {:reply, :ok, state}
  end

  def handle_call({:run_progress_ack, _, _}, _from, state), do: {:reply, :stale, state}

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
      event.type in [:run_finished, :run_failed, :run_paused] -> {:noreply, state}
      cur.streaming? and event.type == :text_delta -> {:noreply, state}
      true -> {:noreply, broadcast(state, event.type, cur, build_payload(event))}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp start_run(state, prompt, opts, reply_to, streaming?) do
    id = request_id(opts)

    run_id =
      if opts[:resume_reference], do: opts[:resume_reference].run_id, else: generate_id("run_")

    parent = self()
    owner_token = make_ref()
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

    base_usage = opts[:continuation_base_usage] || state.usage

    run_opts =
      if state.continuation_config do
        config =
          state.continuation_config
          |> Map.put(:snapshot_base_usage, base_usage)
          |> Map.put(:snapshot_metadata, state.metadata)
          |> Map.put(:request_id, id)
          |> Map.put(:on_writer, fn writer ->
            GenServer.call(parent, {:continuation_writer, run_id, owner_token, writer}, :infinity)
          end)

        Keyword.put(run_opts, :continuation, config)
      else
        run_opts
      end

    admission = admission(state, prompt, opts)

    partial = %{
      output: nil,
      messages: run_opts[:message_history],
      new_messages: [],
      usage: Usage.sum([]),
      model: state.model,
      run_step: 0,
      run_id: run_id,
      status: :running,
      usage_status: :unknown
    }

    task =
      start_owned_task(fn ->
        case admission do
          {:error, reason} ->
            {:error, %RunError{reason: reason, partial: %{partial | status: :failed}}}

          :ok ->
            if streaming? do
              stream =
                if opts[:resume_reference],
                  do: ExAgent.resume_stream(agent, opts[:resume_reference], run_opts),
                  else: ExAgent.run_stream(agent, prompt, run_opts)

              stream
              |> Enum.reduce(nil, fn
                {:delta, text}, acc ->
                  GenServer.call(parent, {:stream_delta_ack, run_id, text}, :infinity)
                  acc

                {:result, result}, _ ->
                  {:ok, result}

                {:error, reason}, _ ->
                  {:error, reason}
              end)
            else
              if opts[:resume_reference],
                do: ExAgent.resume(agent, opts[:resume_reference], run_opts),
                else: ExAgent.run(agent, prompt, run_opts)
            end
        end
      end)

    %{
      state
      | status: :running,
        current: %{
          ref: task.ref,
          pid: task.pid,
          writer: nil,
          owner_token: owner_token,
          reply_to: reply_to,
          request_id: id,
          run_id: run_id,
          progress: partial,
          base_usage: base_usage,
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
      max_history_bytes: min(state.max_history_bytes, state.agent.max_history_bytes),
      on_event: fn event -> GenServer.call(parent, {:run_event_ack, event}, :infinity) end,
      on_progress: fn progress ->
        GenServer.call(parent, {:run_progress_ack, run_id, progress}, :infinity)
      end
    )
  end

  defp failure(cur, reason, status) do
    # The last progress message may predate admission of in-flight work. Keep
    # its observed subtotals, but never claim they are a complete bill or usage.
    partial =
      Map.merge(cur.progress, %{
        status: status,
        usage_status: :partial,
        cost_status: :unknown,
        cost_cents: nil,
        usage: Usage.partial(cur.progress.usage)
      })

    {:error, %RunError{reason: ExAgent.Retention.reason(reason), partial: partial}}
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

    {state, retention_error} = integrate(state, progress)

    outcome =
      if retention_error,
        do:
          {:error,
           %RunError{reason: retention_error, partial: Map.put(progress, :status, :failed)}},
        else: outcome

    {outcome, state} =
      if state.continuation_config do
        {outcome,
         %{
           state
           | continuation_reference: Map.get(progress, :continuation),
             continuation_checkpoint:
               Map.get(progress, :continuation_checkpoint) || state.continuation_checkpoint
         }}
      else
        RuntimeCheckpoint.commit(state, :agent, outcome, &snapshot/1,
          observability: cur.observability,
          trace_context: Observability.context(cur.observation)
        )
      end

    Observability.run_result(cur.observation, outcome, observation_source)
    Observability.finish(cur.observation, outcome)

    {type, payload} =
      case outcome do
        {:ok, %{status: :paused} = result} -> {:run_paused, Event.result_payload(result)}
        {:ok, result} -> {:run_finished, Event.result_payload(result)}
        {:error, reason} -> {terminal_type || :run_failed, Event.error_payload(reason)}
      end

    state =
      broadcast(state, type, cur, Map.put(payload, :persistence, persistence(state)))

    if match?({:call, _}, cur.reply_to) do
      {:call, from} = cur.reply_to
      GenServer.reply(from, outcome)
    end

    status =
      cond do
        state.continuation_checkpoint -> :blocked
        progress[:status] == :paused -> :paused
        state.continuation_config && match?({:error, _}, outcome) -> :blocked
        true -> :idle
      end

    drain(%{state | current: nil, status: status})
  end

  defp integrate(state, progress) do
    {usage, retention_error} =
      merge_usage(
        if(state.continuation_config, do: state.current.base_usage, else: state.usage),
        Map.get(progress, :usage)
      )
      |> ExAgent.Retention.usage()

    state = %{
      state
      | history: Map.get(progress, :messages, state.history),
        model: Map.get(progress, :model, state.model),
        usage: usage
    }

    {state, retention_error}
  end

  defp merge_usage(acc, nil), do: acc

  defp merge_usage(acc, usage) do
    Usage.add(
      %{acc | details: ExAgent.SnapshotData.json(acc.details)},
      %{usage | details: ExAgent.SnapshotData.json(usage.details)}
    )
  end

  defp drain(%{checkpoint_error: error} = state) when not is_nil(error), do: state

  defp drain(%{status: status} = state) when status in [:paused, :blocked, :reset_required],
    do: state

  defp drain(%{current: current} = state) when not is_nil(current), do: state

  defp drain(state) do
    case :queue.out(state.pending) do
      {:empty, _} ->
        %{state | status: :idle}

      {{:value, {{prompt, opts}, bytes}}, rest} ->
        start_run(
          %{state | pending: rest, pending_bytes: state.pending_bytes - bytes},
          prompt,
          opts,
          :event,
          false
        )
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

  defp persistence(%{continuation_config: nil} = state), do: RuntimeCheckpoint.health(state)

  defp persistence(state),
    do: %{
      mode: :atomic,
      dirty: not is_nil(state.continuation_checkpoint),
      record_revision: state.continuation_reference && state.continuation_reference.revision,
      execution_status: state.status
    }

  defp continuation_config(nil, _, _), do: {:ok, nil}

  defp continuation_config(config, store, id) when is_map(config),
    do: ExAgent.Continuation.Writer.config(config |> Map.put(:store, store) |> Map.put(:id, id))

  defp continuation_config(_, _, _), do: {:error, :invalid_continuation_configuration}

  defp load_runtime_state(store, id, nil, _), do: load_state(store, id)

  defp load_runtime_state(store, id, config, agent) do
    case Store.load_record(store, :agent, id) do
      {:error, :not_found} -> load_state(nil, id)
      {:ok, record} -> restore_record(record, config, agent)
      error -> error
    end
  end

  defp restore_record(record, config, agent) do
    with {:ok, snapshot} <-
           ExAgent.Continuation.Record.snapshot(
             record["snapshot"],
             {config.store.namespace, :agent, config.id}
           ),
         {:ok, messages} <- Snapshot.messages(snapshot),
         {:ok, model} <- ExAgent.Continuation.Frame.model_from_record(agent.model, record, config) do
      status =
        case record["execution"]["state"] do
          state when state in ~w(pending ready) ->
            :paused

          state when state in ~w(claimed uncertain) ->
            :blocked

          _ ->
            if ExAgent.Continuation.Frame.open_batch?(messages), do: :reset_required, else: :idle
        end

      {:ok,
       %{
         history: messages,
         usage: Snapshot.usage_struct(snapshot),
         model: model,
         revision: snapshot.revision,
         status: status,
         continuation: record_reference(record, config.id)
       }}
    end
  end

  defp state_from_record(state, record) do
    case restore_record(record, state.continuation_config, state.agent) do
      {:ok, restored} ->
        %{
          state
          | history: restored.history,
            usage: restored.usage,
            model: restored.model,
            revision: restored.revision,
            continuation_reference: restored.continuation,
            status: if(state.current, do: :running, else: restored.status)
        }

      _ ->
        %{state | status: :blocked}
    end
  end

  defp stop_continuation_worker(nil), do: :ok

  defp stop_continuation_worker(current) do
    _ = Task.Supervisor.terminate_child(ExAgent.TaskSupervisor, current.pid)

    if is_pid(current.writer) do
      ref = Process.monitor(current.writer)
      Process.exit(current.writer, :kill)

      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      after
        5_000 ->
          Process.demonitor(ref, [:flush])
          {:error, :continuation_owner_not_quiescent}
      end
    else
      # No Store dispatch is allowed until the writer's registration ACK.
      :ok
    end
  end

  defp cancel_continuation(state, attempts \\ 3)
  defp cancel_continuation(state, 0), do: {{:error, :continuation_abort_conflict}, state}

  defp cancel_continuation(state, attempts) do
    case Store.load_record(state.store, :agent, state.agent_id) do
      {:error, :not_found} ->
        if state.continuation_abort_run_id do
          case abort_execution(state) do
            {:ok, payload} ->
              abort_transition(
                state,
                :absent,
                generate_id("record_"),
                "create_cancelled",
                payload,
                attempts
              )

            {:error, _} = error ->
              {error, state}
          end
        else
          {{:ok, nil}, state}
        end

      {:error, _} = error ->
        {error, state}

      {:ok, record} ->
        target = state.continuation_abort_run_id || record["execution"]["run_id"]

        state = %{
          state
          | continuation_abort_run_id: target,
            continuation_abort_request_id:
              state.continuation_abort_request_id || record["execution"]["request_id"]
        }

        same? = target == record["execution"]["run_id"]
        status = record["execution"]["state"]

        cond do
          same? and status in ~w(ready pending claimed) ->
            abort_transition(
              state,
              record["revision"],
              record["record_id"],
              "cancel",
              %{},
              attempts
            )

          same? ->
            {{:ok, record}, state}

          status in ~w(completed denied expired cancelled) ->
            abort_transition(
              state,
              record["revision"],
              record["record_id"],
              "fence_admission",
              %{"run_id" => target},
              attempts
            )

          true ->
            {{:error, :continuation_abort_conflict}, state}
        end
    end
  end

  defp abort_execution(state) do
    config = state.continuation_config
    run_id = state.continuation_abort_run_id

    with {:ok, frame} <- ExAgent.Continuation.Frame.aborted(state.model, run_id, config) do
      execution = %{
        "continuation_id" => generate_id("continuation_"),
        "run_id" => run_id,
        "request_id" => state.continuation_abort_request_id,
        "definition" => config.definition,
        "policy" => config.policy,
        "model_ref" => config.model_ref,
        "deadline_at" => config[:deadline_at],
        "expires_at" => config.expires_at,
        "progress" => %{"runtime" => frame}
      }

      {:ok,
       %{
         "execution" => execution,
         "snapshot" => ExAgent.Continuation.Record.snapshot_data(snapshot(state))
       }}
    end
  rescue
    _ -> {:error, :invalid_continuation_snapshot}
  end

  defp abort_transition(state, revision, lifetime, operation, payload, attempts) do
    token = %{
      "token_version" => 1,
      "namespace" => state.continuation_config.store.namespace,
      "id" => state.agent_id,
      "expected_revision" => if(revision == :absent, do: "absent", else: revision),
      "command" => %{
        "record_id" => lifetime,
        "operation" => operation,
        "operation_id" => generate_id("abort_"),
        "actor_id" => "exagent-server",
        "payload" => payload
      }
    }

    limit =
      Map.get(
        state.continuation_config,
        :max_checkpoint_bytes,
        ExAgent.Continuation.Record.max_bytes()
      )

    with :ok <- ExAgent.Retention.check(token, limit, :checkpoint) do
      case ExAgent.Continuation.retry_checkpoint(state.store, token) do
        {:ok, %{record: record}} ->
          {{:ok, record}, state}

        {:error, reason} when reason in [:conflict, :record_mismatch] ->
          cancel_continuation(state, attempts - 1)

        {:error, reason} ->
          error = %ExAgent.CheckpointError{
            operation: :agent,
            reason: ExAgent.Retention.reason(reason),
            result: :ok,
            revision: if(revision == :absent, do: 1, else: revision + 1)
          }

          {{:error, error}, %{state | continuation_checkpoint: token}}
      end
    else
      {:error, _} = error -> {error, state}
    end
  end

  defp record_reference(record, id),
    do: %{
      version: 1,
      id: id,
      record_id: record["record_id"],
      revision: record["revision"],
      run_id: record["execution"]["run_id"],
      attempt_id: record["execution"]["attempt_id"]
    }

  defp load_state(nil, _),
    do: {:ok, %{history: [], usage: Usage.sum([]), revision: 0}}

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
        source:
          if(type in [:server_request_cancelled, :approval_decided], do: :server, else: :run),
        agent_id: state.agent_id,
        run_id: cur.run_id,
        namespace: state.namespace,
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
    do: Map.take(data, [:prompt, :attempt_id])

  defp build_payload(%RunEvent{type: :approval_requested, data: data}),
    do: %{
      continuation: Event.continuation_reference(data[:continuation]),
      attempt_id: data[:attempt_id]
    }

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

  defp validate_payload_limits(limits) do
    if Enum.all?(limits, fn {_, value} -> is_integer(value) and value in 1..67_108_864 end),
      do: :ok,
      else: {:error, :invalid_payload_limits}
  end

  defp admission(state, prompt, opts) do
    history = Keyword.get(opts, :message_history) || state.history

    with :ok <- ExAgent.Retention.usage_error(state.usage),
         :ok <- size_limit({prompt, opts}, state.max_input_bytes, :input_too_large),
         do: size_limit(history, state.max_history_bytes, :history_too_large)
  end

  defp size_limit(value, limit, reason) do
    bytes = :erlang.external_size(value)
    if bytes <= limit, do: :ok, else: {:error, {reason, %{bytes: bytes, limit: limit}}}
  end

  defp resolve_model(%_{} = model), do: {:ok, model}
  defp resolve_model(spec), do: ExAgent.Model.resolve(spec)

  defp generate_id(prefix),
    do: prefix <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
