defmodule ExAgent.Continuation.Writer do
  @moduledoc false
  use GenServer
  alias ExAgent.{ExecutionScope, Message, Retention, Store}

  alias ExAgent.Continuation.{
    Approval,
    Authority,
    Budget,
    Checkpoint,
    Frame,
    Outcome,
    OutputResolution,
    Record,
    Transition,
    Retry,
    RequestData
  }

  alias ExAgent.Message.{Part, Usage}
  alias ExAgent.Server.Snapshot
  @max_measurement 18_446_744_073_709_551_615

  def config(nil), do: {:ok, nil}

  def config(%{kind: :composition} = config) do
    allowed =
      ~w(kind composition store id definition policy durability expires_at lease_ms deadline_at active_time_limit_ms max_checkpoint_bytes on_writer)a

    with true <- Enum.all?(Map.keys(config), &(&1 in allowed)),
         {:ok, binding} <- ExAgent.Coordination.Composition.binding(config[:composition]),
         true <- config[:definition] === Map.take(binding, ~w(id version)),
         true <- Record.reference?(config[:policy]) and Record.text?(config[:id]),
         true <- Map.has_key?(config, :expires_at),
         true <-
           Record.nullable_timestamp?(config[:expires_at]) and
             Record.nullable_timestamp?(config[:deadline_at]),
         true <- is_integer(config[:lease_ms]) and config.lease_ms > 0,
         true <- Budget.valid?(Budget.new(config[:active_time_limit_ms])),
         true <-
           is_integer(Map.get(config, :max_checkpoint_bytes, Record.max_bytes())) and
             Map.get(config, :max_checkpoint_bytes, Record.max_bytes()) in 1..Record.max_bytes(),
         true <- is_nil(config[:on_writer]) or is_function(config[:on_writer], 1),
         :ok <- Store.require_continuation(config[:store], config[:durability]) do
      {:ok, config}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_continuation_configuration}
    end
  end

  def config(config) when is_map(config) do
    with true <- not Map.has_key?(config, :kind),
         true <- Enum.all?([:definition, :policy, :model_ref], &Record.reference?(config[&1])),
         true <- Record.text?(config[:id]) and Map.has_key?(config, :expires_at),
         true <-
           Record.nullable_timestamp?(config[:expires_at]) and
             Record.nullable_timestamp?(config[:deadline_at]),
         true <- is_integer(config[:lease_ms]) and config.lease_ms > 0,
         true <- Budget.valid?(Budget.new(config[:active_time_limit_ms])),
         true <-
           is_integer(Map.get(config, :max_checkpoint_bytes, Record.max_bytes())) and
             Map.get(config, :max_checkpoint_bytes, Record.max_bytes()) in 1..Record.max_bytes(),
         %{dump: dump, load: load} <- config[:model_codec],
         true <- is_function(dump, 1) and is_function(load, 2),
         :ok <- Store.require_continuation(config[:store], config[:durability]) do
      {:ok, config}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_continuation_configuration}
    end
  end

  def config(_), do: {:error, :invalid_continuation_configuration}

  def bind_deadline(opts) do
    if is_map(opts[:continuation]) and is_integer(opts[:deadline]) do
      utc =
        max(
          System.system_time(:millisecond) + opts[:deadline] - System.monotonic_time(:millisecond),
          0
        )

      config = opts[:continuation]
      deadline = if is_integer(config[:deadline_at]), do: min(utc, config.deadline_at), else: utc
      Keyword.put(opts, :continuation, Map.put(config, :deadline_at, deadline))
    else
      opts
    end
  end

  def deadline(opts) do
    case opts[:continuation] do
      nil ->
        opts[:deadline]

      config ->
        now = System.monotonic_time(:millisecond)
        utc = System.system_time(:millisecond)

        remaining =
          case opts[:continuation_record] do
            nil ->
              config[:active_time_limit_ms]

            r ->
              r["execution"]["progress"]
              |> Budget.tighten(config[:active_time_limit_ms])
              |> get_in(["active_budget", "remaining_ms"])
          end

        stored_times =
          case opts[:continuation_record] do
            nil ->
              []

            record ->
              for key <- ~w(deadline_at expires_at),
                  is_integer(record["execution"][key]),
                  do: now + record["execution"][key] - utc
          end

        ([
           opts[:deadline],
           if(config[:deadline_at], do: now + config.deadline_at - utc),
           if(config[:expires_at], do: now + config.expires_at - utc),
           if(remaining, do: now + remaining),
           now + config.lease_ms
         ] ++ stored_times)
        |> Enum.reject(&is_nil/1)
        |> Enum.min()
    end
  end

  def open(state, config, record \\ nil)

  def open(run, %{kind: :composition} = config, record) do
    with {:ok, config} <- config(config),
         {:ok, frame} <- Frame.capture_structural(run, config),
         frame = structural_lifetime_frame(frame, record),
         :ok <- structural_binding(record, frame, config),
         command = structural_create(run, frame, config),
         {:ok, %{record: projected}} <-
           Transition.apply(
             nil,
             {config.store.namespace, :agent, config.id},
             :absent,
             command,
             System.system_time(:millisecond)
           ),
         :ok <- structural_claim_capacity(record || projected, config),
         true <-
           Retention.bytes(token(%{config: config}, :absent, command)) <=
             Map.get(config, :max_checkpoint_bytes, Record.max_bytes()),
         {:ok, checkpoint} <- Checkpoint.new(config.store, :agent, config.id, config.durability),
         {:ok, pid} <- GenServer.start_link(__MODULE__, {self(), config, checkpoint}) do
      case register_owner(pid, config) do
        :ok ->
          case call(pid, {:open_structural, run, command, record}) do
            {:ok, data} -> {:ok, pid, data}
            {:error, reason} -> {:ok, pid, {:error, reason}}
          end

        error ->
          stop(pid)
          error
      end
    else
      false -> {:error, :continuation_frame_limit}
      error -> error
    end
  end

  def open(_, _, %{"record_version" => 2}), do: {:error, :structural_root_requires_definition}
  def open(_, %{kind: _}, _), do: {:error, :invalid_continuation_configuration}

  def open(state, config, record) do
    with {:ok, frame} <-
           Frame.capture(
             state,
             config,
             "request",
             if(state.continuation_frame,
               do: Map.get(state.continuation_frame, "children", %{}),
               else: %{}
             )
           ),
         {:ok, checkpoint} <- Checkpoint.new(config.store, :agent, config.id, config.durability),
         {:ok, pid} <- GenServer.start_link(__MODULE__, {self(), config, checkpoint}) do
      case register_owner(pid, config) do
        :ok ->
          case GenServer.call(pid, {:open, state, frame, record}, :infinity) do
            {:ok, data} -> {:ok, pid, data}
            {:error, reason} -> {:ok, pid, {:error, reason}}
          end

        {:error, _} = error ->
          stop(pid)
          error
      end
    end
  end

  defp structural_lifetime_frame(frame, %{
         "execution" => %{"progress" => %{"runtime" => %{"frame_version" => 7}}}
       }),
       do: frame |> Map.drop(["tool_batches", "frontier"]) |> Map.put("frame_version", 7)

  defp structural_lifetime_frame(frame, %{
         "execution" => %{"progress" => %{"runtime" => %{"frame_version" => 8}}}
       }),
       do: frame |> Map.delete("frontier") |> Map.put("frame_version", 8)

  defp structural_lifetime_frame(frame, %{
         "execution" => %{"progress" => %{"runtime" => %{"frame_version" => 9}}}
       }),
       do: frame |> Map.delete("frontier") |> Map.put("frame_version", 9)

  defp structural_lifetime_frame(frame, _), do: frame

  defp structural_binding(nil, _, config) do
    case Store.load_record(config.store, :agent, config.id) do
      {:error, :not_found} -> :ok
      {:ok, _} -> {:error, :continuation_pending}
      error -> error
    end
  end

  defp structural_binding(record, frame, config) do
    with :ok <- Record.validate(record, {config.store.namespace, :agent, config.id}),
         true <- record["record_version"] === 2,
         true <- record["execution"]["progress"]["runtime"] === frame,
         true <- record["execution"]["policy"] === config.policy do
      :ok
    else
      _ -> {:error, :structural_root_changed}
    end
  end

  defp structural_create(run, frame, config) do
    execution = %{
      "kind" => "composition",
      "continuation_id" => id("continuation"),
      "run_id" => run.run_id,
      "definition" => config.definition,
      "policy" => config.policy,
      "deadline_at" => config[:deadline_at],
      "expires_at" => config.expires_at,
      "progress" => %{
        "runtime" => frame,
        "active_budget" => Budget.new(config[:active_time_limit_ms])
      }
    }

    command(id("record"), "create", %{
      "snapshot" => ExAgent.Continuation.StructuralSnapshot.new(config.id, frame),
      "execution" => execution
    })
  end

  # Check the claimed record as well as create: its receipt and cleanup horizon
  # grow before any leaf exists. IDs have the same fixed encoded width as claim/1.
  defp structural_claim_capacity(record, config) do
    now = System.system_time(:millisecond)

    payload = %{
      "owner_id" => id("owner"),
      "attempt_id" => id("attempt"),
      "lease_until" => now + config.lease_ms,
      "deadline_at" => config[:deadline_at],
      "expires_at" => config[:expires_at],
      "active_limit_ms" => config[:active_time_limit_ms]
    }

    claim = command(record["record_id"], "claim", payload)

    case Transition.apply(
           record,
           {config.store.namespace, :agent, config.id},
           record["revision"],
           claim,
           now
         ) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp register_owner(pid, config) do
    case config[:on_writer] do
      nil ->
        :ok

      callback when is_function(callback, 1) ->
        if callback.(pid) == :ok, do: :ok, else: {:error, :continuation_owner_registration_failed}

      _ ->
        {:error, :continuation_owner_registration_failed}
    end
  rescue
    _ -> {:error, :continuation_owner_registration_failed}
  catch
    _, _ -> {:error, :continuation_owner_registration_failed}
  end

  def stop(nil), do: :ok

  def stop(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid)
  catch
    :exit, _ -> :ok
  end

  def model_begin(nil, _), do: :ok
  def model_begin(pid, state), do: call(pid, {:model_begin, state})
  def model_done(nil, _), do: :ok
  def model_done(pid, state), do: call(pid, {:model_done, state})
  def output_resolution(nil, _, _, _, _), do: :ok

  def output_resolution(pid, run, decision, parts, output),
    do: call(pid, {:output_resolution, run, decision, parts, output})

  def batch(nil, _), do: :ok
  def batch(pid, state), do: call(pid, {:batch, state})
  def saved(nil, _, _), do: nil
  def saved(pid, run_id, id), do: call(pid, {:saved, run_id, id})
  def admit(pid, state, call, tool), do: call(pid, {:admit, state, call, tool})
  def outcome(nil, _, _), do: :ok
  def outcome(pid, state, part), do: call(pid, {:outcome, state, part})
  def pause(pid, state, parts), do: call(pid, {:pause, state, parts})
  def finish(nil, _, _), do: :ok
  def finish(pid, state, output), do: call(pid, {:finish, state, output})
  def failed(nil, _), do: :ok
  def failed(pid, state), do: call(pid, {:failed, state})
  def child(pid, run, call), do: call(pid, {:child, run, call})

  def attach(pid, parent, run, call, config, options),
    do: call(pid, {:attach, parent, run, call, config, options})

  def observed_outcome(nil, run, part, input) do
    ExecutionScope.contribute(
      run.execution_scope,
      {run.model_request_id, part.tool_call_id},
      input
    )

    :ok
  end

  def observed_outcome(pid, run, part, input),
    do: call(pid, {:observed_outcome, run, part, input})

  def tool_resolution(nil, _, _, _, _), do: :ok

  def tool_resolution(pid, run, parts, controls, settle_error),
    do: call(pid, {:tool_resolution, run, parts, controls, settle_error})

  def settle(nil, _, parts), do: {parts, nil}

  def settle(pid, state, parts) do
    case call(pid, {:settle, state, parts}) do
      {:ok, retained} -> {retained, nil}
      {:settled, retained, reason} -> {retained, reason}
      {:error, reason} -> {parts, reason}
    end
  end

  def reference(pid), do: call(pid, :reference)
  def confirmed_record(pid), do: call(pid, :confirmed_record)
  def pending(pid), do: call(pid, :pending)

  def record_metadata(record, config, token \\ nil) do
    %{
      token: token,
      max_bytes: Map.get(config, :max_checkpoint_bytes, Record.max_bytes()),
      record_bytes: if(record, do: Retention.bytes(record), else: 0),
      record_json_bytes: if(record, do: byte_size(Jason.encode!(record)), else: 0),
      historical_uncertainty: if(record, do: Retry.summary(record["execution"])),
      effect_attempts:
        if(record,
          do:
            Enum.frequencies_by(
              Enum.filter(
                Map.values(record["execution"]["effects"]),
                &(&1["intent"]["payload"]["phase"] in ~w(dispatch model_dispatch))
              ),
              & &1["intent"]["kind"]
            ),
          else: %{}
        )
    }
  end

  def claim_composition(record, config) do
    with :ok <- structural_claim_capacity(record, config),
         {:ok, checkpoint} <- Checkpoint.new(config.store, :agent, config.id, config.durability),
         {:ok, pid} <- GenServer.start_link(__MODULE__, {self(), config, checkpoint}) do
      case call(pid, {:claim_composition, record}) do
        {:ok, claimed} ->
          {:ok, pid, claimed}

        error ->
          token =
            case pending(pid) do
              %{token: token} -> token
              _ -> nil
            end

          stop(pid)
          {:error, {:composition_claim_failed, error, token}}
      end
    end
  end

  def restore_step(pid, root, run, config, options),
    do: call(pid, {:restore_step, root, run, config, options})

  def bind_composition_scope(pid, root), do: call(pid, {:bind_composition_scope, root})

  def attempt_deadline(pid), do: call(pid, :attempt_deadline)

  # Data-only restore inspection. It intentionally does not reconstruct Scope
  # authority or turn an in-flight model intent into permission to repeat IO.
  def step_status(record, config, step_id) do
    with {:ok, %{kind: :composition} = config} <- config(config),
         :ok <- Record.validate(record, {config.store.namespace, :agent, config.id}),
         frame = record["execution"]["progress"]["runtime"],
         :ok <-
           ExAgent.Coordination.Composition.validate_binding(config.composition, frame["binding"]),
         true <- record["execution"]["policy"] === config.policy,
         step when not is_nil(step) <- Enum.find(config.composition.steps, &(&1.id === step_id)),
         true <- step.id === step_id do
      case frame do
        %{"cursor" => "empty"} ->
          {:ok, %{status: :empty}}

        %{"frame_version" => version, "children" => children}
        when version in [5, 6, 7, 8, 9, 10] ->
          {id, child} = Enum.find(children, fn {_, c} -> c["link"]["step_id"] === step_id end)

          status =
            cond do
              child["status"] == "completed" -> :completed
              child["frame"]["run_step"] == 0 -> :input_confirmed
              true -> :running
            end

          {:ok,
           %{
             status: status,
             run_id: id,
             input: child["link"]["input"],
             output: child["result"],
             output_omitted: child["result_omitted"],
             frame: child["frame"],
             snapshot: child["snapshot"]
           }}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_composition_step}
    end
  end

  def step_descriptor(pid, definition, step_id),
    do: call(pid, {:step_descriptor, definition, step_id})

  def attach_step(pid, ticket, run, options), do: call(pid, {:attach_step, ticket, run, options})

  def release_step(pid, ticket), do: call(pid, {:release_step, ticket})

  def delegate_definitions(pid, catalog), do: call(pid, {:delegate_definitions, catalog})
  def delegate_definition(pid, descriptor), do: call(pid, {:delegate_definition, descriptor})
  def call10(pid, run, id), do: call(pid, {:call10, run, id})

  def phase10(pid, run, id, operation, data \\ %{}),
    do: call(pid, {:phase10, run, id, operation, data})

  def consume10(pid, run, operation), do: call(pid, {:consume10, run, operation})

  def worker_begin(pid, run, role, call_id \\ nil),
    do: call(pid, {:worker_begin, run, role, call_id})

  def worker_done(pid, identity), do: call(pid, {:worker_done, identity})
  def drain_node(pid, run_id), do: call(pid, {:drain_node, run_id})

  def restore_nodes10(pid, root, nodes), do: call(pid, {:restore_nodes10, root, nodes})

  def flow_checkpoint(pid, operation, data), do: call(pid, {:flow_checkpoint, operation, data})

  def flow_branch_done(pid, id) do
    with :ok <- drain_node(pid, "branch:" <> id), do: call(pid, {:flow_branch_done, id})
  end

  defp call(pid, request) do
    GenServer.call(pid, request, :infinity)
  catch
    :exit, _ -> {:error, :continuation_owner_lost}
  end

  @impl true
  def init({owner, config, checkpoint}) do
    {:ok,
     %{
       owner: owner,
       monitor: Process.monitor(owner),
       config: config,
       checkpoint: checkpoint,
       record: nil,
       pending: %{},
       scope: nil,
       nodes: %{},
       delegate_definitions: [],
       workers: %{},
       drain_waiters: [],
       tool_reserve: nil,
       step_ticket: nil,
       flow_tickets: %{},
       attempt_deadline: nil,
       started_at: System.monotonic_time(:millisecond)
     }}
  end

  @impl true
  def format_status(status) do
    # Runtime messages/config contain trusted model handles, deps and callbacks;
    # crash reporting must not dump them or whole persisted application payloads.
    status
    |> Map.put(:state, :continuation_writer)
    |> Map.put(:message, :redacted)
    |> Map.put(:log, [])
    |> Map.update(:reason, :redacted, &Retention.reason/1)
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{monitor: ref} = s), do: {:stop, :normal, s}

  def handle_info({:DOWN, ref, :process, _, _}, %{step_ticket: %{monitor: ref}} = s),
    do: {:noreply, %{s | step_ticket: nil}}

  def handle_info({:DOWN, ref, :process, pid, _}, s) do
    workers =
      Map.new(s.workers, fn {identity, worker} ->
        {identity,
         if(worker.monitor == ref and worker.pid == pid,
           do: Map.put(worker, :down, true),
           else: worker
         )}
      end)
      |> Map.reject(fn {_, w} -> w.done and w.down end)

    s = %{s | workers: workers}

    {ready, waiting} =
      Enum.split_with(s.drain_waiters, fn {_, id} ->
        own = Enum.filter(s.workers, fn {{_, run, _, _, _}, _} -> run == id end)
        own == [] or Enum.any?(own, fn {_, w} -> w.down end)
      end)

    Enum.each(ready, fn {from, id} ->
      GenServer.reply(from, drained10(s, id))
    end)

    {:noreply, %{s | drain_waiters: waiting}}
  end

  @impl true
  def terminate(_, s) do
    Enum.each(s.workers, fn {_, w} ->
      if not w.down, do: Process.exit(w.pid, :kill)
    end)
  end

  @impl true
  def handle_call({:claim_composition, record}, _, s) do
    {reply, next} = claim(%{s | record: record})
    {:reply, reply, next}
  end

  def handle_call(:attempt_deadline, _, s), do: {:reply, {:ok, s.attempt_deadline}, s}

  def handle_call({:bind_composition_scope, root}, {owner, _}, s) do
    with true <- owner == s.owner,
         nil <- s.scope,
         "claimed" <- s.record["execution"]["state"],
         true <- root.run_id == s.record["execution"]["run_id"],
         :ok <- register_owner(self(), s.config) do
      {:reply, :ok, %{s | scope: root}}
    else
      {:error, _} = error -> {:reply, error, s}
      _ -> {:reply, {:error, :invalid_composition_restore}, s}
    end
  end

  def handle_call({:restore_step, root, run, config, options}, _, s) do
    with true <- is_nil(s.scope) or s.scope == root,
         true <- s.nodes == %{},
         "claimed" <- s.record["execution"]["state"],
         :ok <- if(is_nil(s.scope), do: register_owner(self(), s.config), else: :ok),
         {:ok, s} <- restore_tool_capacity(s, run) do
      run = %{run | continuation: self(), attempt_id: s.record["execution"]["attempt_id"]}

      {:reply, {:ok, run},
       %{s | scope: root, nodes: %{run.run_id => %{state: run, config: config, options: options}}}}
    else
      {:error, reason} -> {:reply, {:error, reason}, s}
      _ -> {:reply, {:error, :invalid_composition_restore}, s}
    end
  end

  def handle_call({:restore_nodes10, root, nodes}, {owner, _}, %{owner: owner} = s) do
    active =
      root10(s)["children"]
      |> Enum.filter(fn {_, n} -> n["status"] in ~w(suspended running) end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    with true <- s.scope == root and s.nodes == %{} and s.workers == %{},
         true <-
           root10(s)["frame_version"] in [10, 11] and
             s.record["execution"]["state"] == "claimed",
         true <- Enum.sort(Map.keys(nodes)) == active,
         true <-
           Enum.all?(nodes, fn {id, n} ->
             n.state.run_id == id and n.state.continuation == self() and
               n.state.continuation_version == root10(s)["frame_version"] and
               n.state.execution_scope.pid == root.pid
           end) do
      {reply, next} =
        if root10(s)["frontier"]["state"] == "quiescent",
          do: write10(%{s | nodes: nodes}, "frontier_open", %{}),
          else: {:ok, %{s | nodes: nodes}}

      {:reply, reply, next}
    else
      _ -> {:reply, {:error, :invalid_composition_restore}, s}
    end
  end

  def handle_call({:open_structural, run, command, record}, _, s) do
    s = %{s | scope: run.execution_scope}

    {reply, s} =
      if is_nil(record) do
        write_command(s, :absent, command)
      else
        {{:ok, record}, %{s | record: record}}
      end

    {reply, s} = if match?({:ok, _}, reply), do: claim(s), else: {reply, s}
    {:reply, reply, s}
  end

  def handle_call({:open, _, _, _}, _, %{config: %{kind: :composition}} = s),
    do: {:reply, {:error, :unsupported_structural_operation}, s}

  def handle_call({:open, run, frame, nil}, _, s) do
    progress = %{
      "runtime" => frame,
      "active_budget" => Budget.new(s.config[:active_time_limit_ms])
    }

    execution = %{
      "continuation_id" => id("continuation"),
      "run_id" => run.run_id,
      "request_id" => s.config[:request_id] || run.run_id,
      "definition" => s.config.definition,
      "policy" => s.config.policy,
      "model_ref" => s.config.model_ref,
      "deadline_at" => s.config[:deadline_at],
      "expires_at" => s.config.expires_at,
      "progress" => progress
    }

    s = %{s | scope: run.execution_scope, nodes: run.continuation_nodes}

    {reply, s} =
      case Store.load_record(s.config.store, :agent, s.config.id) do
        {:error, :not_found} ->
          execution = execution_progress(execution, s.config, 0)

          write(
            s,
            :absent,
            "create",
            %{"snapshot" => snapshot(run, s), "execution" => execution},
            id("record")
          )

        {:ok, %{"execution" => %{"state" => state}} = record}
        when state in ~w(completed denied expired cancelled) ->
          execution = execution_progress(execution, s.config, record["snapshot"]["revision"])
          write(%{s | record: record}, "start", %{"execution" => execution})

        {:ok, _} ->
          {{:error, :continuation_pending}, s}

        {:error, reason} ->
          {{:error, reason}, s}
      end

    {reply, s} = if match?({:ok, _}, reply), do: claim(s), else: {reply, s}
    {:reply, reply, s}
  end

  def handle_call({:open, run, _frame, record}, _, s) do
    {reply, s} =
      claim(%{s | record: record, scope: run.execution_scope, nodes: run.continuation_nodes})

    {reply, s} = if match?({:ok, _}, reply), do: upgrade_root(s), else: {reply, s}
    {:reply, reply, s}
  end

  def handle_call(:reference, _, s), do: {:reply, ref(s.record, s.config), s}
  def handle_call(:confirmed_record, _, s), do: {:reply, s.record, s}

  def handle_call(:pending, _, s) do
    token =
      case s.checkpoint.pending do
        nil -> nil
        {expected, command} -> token(s, expected, command)
      end

    {:reply, record_metadata(s.record, s.config, token), s}
  end

  def handle_call({:delegate_definitions, catalog}, {owner, _}, %{owner: owner} = s),
    do: {:reply, :ok, %{s | delegate_definitions: catalog}}

  def handle_call({:delegate_definition, descriptor}, _, s),
    do: {:reply, ExAgent.Continuation.Delegation.lookup(s.delegate_definitions, descriptor), s}

  def handle_call({:worker_begin, run, role, call_id}, {pid, _}, s) do
    root = root10(s)

    identity =
      {s.record["execution"]["attempt_id"], run.run_id, run.model_request_id, call_id, role}

    batch =
      root["tool_batches"][
        ExAgent.Continuation.ToolEvidence.key(run.run_id, run.model_request_id)
      ]

    branch? =
      root["frame_version"] == 11 and role == :branch and is_nil(call_id) and
        String.starts_with?(run.run_id, "branch:") and
        String.replace_prefix(run.run_id, "branch:", "") in root["flow"]["selected"]

    branch_count = Enum.count(s.workers, fn {{_, _, _, _, role}, _} -> role == :branch end)

    with true <- root["frame_version"] in [10, 11] and s.record["execution"]["state"] == "claimed",
         nil <- s.checkpoint.pending,
         true <- root["frontier"]["state"] in ~w(open draining),
         nil <- root["frontier"]["fatal"],
         true <- branch? or (is_map(batch) and is_nil(batch["consumption"])),
         true <-
           (branch? and branch_count < root["binding"]["max_concurrency"]) or
             (role == :producer and is_nil(call_id)) or
             (role == :tool and Map.has_key?(batch["calls"], call_id)),
         false <- Map.has_key?(s.workers, identity) do
      worker = %{pid: pid, monitor: Process.monitor(pid), done: false, down: false}
      {:reply, {:ok, identity}, %{s | workers: Map.put(s.workers, identity, worker)}}
    else
      _ -> {:reply, {:error, :continuation_worker_admission_closed}, s}
    end
  end

  def handle_call({:worker_done, identity}, {pid, _}, s) do
    case s.workers[identity] do
      %{pid: ^pid, down: false} = worker ->
        {:reply, :ok, %{s | workers: Map.put(s.workers, identity, %{worker | done: true})}}

      _ ->
        {:reply, {:error, :invalid_continuation_worker}, s}
    end
  end

  def handle_call({:drain_node, id}, from, s) do
    case drained10(s, id) do
      :waiting -> {:noreply, %{s | drain_waiters: [{from, id} | s.drain_waiters]}}
      reply -> {:reply, reply, s}
    end
  end

  def handle_call({:flow_checkpoint, operation, data}, {owner, _}, %{owner: owner} = s) do
    root = root10(s)

    with true <- root["frame_version"] == 11 and s.record["execution"]["state"] == "claimed",
         nil <- s.checkpoint.pending,
         :ok <- ExecutionScope.check(s.scope),
         :ok <- check_step_deadline(s),
         true <- s.workers == %{} do
      {reply, next} =
        case operation do
          "flow_drain" ->
            cond do
              Frame.call_fatal_closable10?(s.record) ->
                write10(s, "finish", %{"elapsed_ms" => elapsed(s)})

              root["frontier"]["reason"] == "approval" ->
                write10(s, "pause", %{"elapsed_ms" => elapsed(s)})

              Frame.terminal_branches11?(root) ->
                {:ok, s}

              true ->
                {{:error, :continuation_uncertain}, s}
            end

          op when op in ~w(flow_merge flow_host_failed) ->
            write10(s, operation, Map.put(data, "elapsed_ms", elapsed(s)))

          _ ->
            write10(s, operation, data)
        end

      reply =
        if reply == :ok and operation in ~w(flow_select_begin flow_merge_begin),
          do: check_step_deadline(next),
          else: reply

      {:reply, reply, next}
    else
      {:error, _} = error -> {:reply, error, s}
      _ -> {:reply, {:error, :invalid_flow_checkpoint}, s}
    end
  end

  def handle_call({:flow_branch_done, id}, {owner, _}, %{owner: owner} = s) do
    root = root10(s)

    node =
      Enum.find_value(root["children"], fn {_, n} -> if n["link"]["step_id"] == id, do: n end)

    with true <- root["frame_version"] == 11 and s.record["execution"]["state"] == "claimed",
         nil <- s.checkpoint.pending,
         :ok <- drained10(s, "branch:" <> id) do
      {reply, next} =
        cond do
          node["status"] in ~w(completed suspended failed cancelled) ->
            {:ok, s}

          is_nil(node) and id in root["flow"]["selected"] and
            root["frontier"]["state"] == "draining" and
            root["frontier"]["reason"] == "approval" and
              Frame.branch_drained11?(s.record, id) ->
            # This selected worker reached DOWN without attaching a node or
            # admitting an effect. Its branch remains not_started for resume.
            {:ok, s}

          Frame.branch_closable11?(s.record, id) ->
            write10(s, "flow_branch_done", %{"branch_id" => id})

          root["frontier"]["reason"] == "fatal" and Frame.branch_drained11?(s.record, id) ->
            # A sibling need not invent its own fatal. Keep its exact raw/source;
            # the root owner will close only after every branch DOWN and the
            # global original-record certificate proves all effects are known.
            {:ok, s}

          true ->
            {{:error, :continuation_uncertain}, s}
        end

      {:reply, reply, next}
    else
      {:error, _} = error -> {:reply, error, s}
      _ -> {:reply, {:error, :invalid_flow_branch}, s}
    end
  end

  def handle_call(
        {:step_descriptor, definition, step_id},
        {owner, _},
        %{record: %{"execution" => %{"progress" => %{"runtime" => %{"frame_version" => 11}}}}} = s
      ) do
    root = root10(s)
    step_index = Enum.find_index(definition.steps, &(&1.id == step_id))

    registered =
      Enum.any?(s.workers, fn {{_, id, _, _, role}, worker} ->
        role == :branch and id == "branch:" <> step_id and worker.pid == owner and not worker.down
      end)

    with nil <- s.checkpoint.pending,
         :ok <- ExAgent.Coordination.Composition.validate_binding(definition, root["binding"]),
         true <- registered and step_id in root["flow"]["selected"] and is_integer(step_index),
         true <- root["frontier"]["state"] == "open" and root["flow"]["phase"] == "running",
         false <- Enum.any?(root["children"], fn {_, n} -> n["link"]["step_id"] == step_id end),
         false <- Enum.any?(s.flow_tickets, fn {_, t} -> t.step.id == step_id end),
         :ok <- ExecutionScope.check(s.scope),
         :ok <- step_capacity(s),
         :ok <- step_journal_capacity(s.record),
         :ok <- check_step_deadline(s) do
      ticket = make_ref()

      descriptor = %{
        ticket: ticket,
        owner: owner,
        monitor: Process.monitor(owner),
        step: Enum.at(definition.steps, step_index),
        index: step_index,
        revision: s.record["revision"],
        input: root["input"],
        deadline: step_deadline(s),
        parent: %{
          run_id: s.scope.run_id,
          root_run_id: s.scope.root_run_id,
          execution_scope: s.scope
        }
      }

      {:reply, {:ok, descriptor},
       %{s | flow_tickets: Map.put(s.flow_tickets, ticket, descriptor)}}
    else
      {:error, _} = error -> {:reply, error, s}
      _ -> {:reply, {:error, :flow_branch_unavailable}, s}
    end
  end

  def handle_call(
        {:step_descriptor, definition, step_id},
        {owner, _},
        %{config: %{kind: :composition}} = s
      ) do
    with nil <- s.checkpoint.pending,
         nil <- s.step_ticket,
         :ok <-
           ExAgent.Coordination.Composition.validate_binding(
             definition,
             s.record["execution"]["progress"]["runtime"]["binding"]
           ),
         frame = s.record["execution"]["progress"]["runtime"],
         true <- frame["frame_version"] in [9, 10] or length(definition.steps) == 1,
         index = length(step_nodes(frame)),
         step when not is_nil(step) <-
           Enum.at(
             definition.steps,
             if(frame["cursor"] == "completed", do: index - 1, else: index)
           ),
         true <- step.id === step_id do
      frame = s.record["execution"]["progress"]["runtime"]

      case {frame["cursor"], s.record["execution"]["state"]} do
        {cursor, "claimed"} when cursor in ["empty", "between_steps"] ->
          with :ok <- ExecutionScope.check(s.scope),
               :ok <- step_capacity(s),
               :ok <- step_journal_capacity(s.record),
               :ok <- check_step_deadline(s),
               true <- Enum.all?(frame["children"], fn {_, c} -> is_nil(c["result_omitted"]) end),
               {:ok, input} <- retained_step_input(step, frame, s),
               :ok <- check_step_deadline(s) do
            ticket = make_ref()

            descriptor = %{
              ticket: ticket,
              owner: owner,
              monitor: Process.monitor(owner),
              step: step,
              index: index,
              revision: s.record["revision"],
              input: input,
              deadline: step_deadline(s),
              parent: %{
                run_id: s.scope.run_id,
                root_run_id: s.scope.root_run_id,
                execution_scope: s.scope
              }
            }

            {:reply, {:ok, descriptor}, %{s | step_ticket: descriptor}}
          else
            {:error, reason} -> {:reply, {:error, Retention.reason(reason)}, s}
            _ -> {:reply, {:error, :invalid_composition_input}, s}
          end

        {"completed", "completed"} ->
          child = Enum.max_by(Map.values(frame["children"]), & &1["link"]["index"])

          reply =
            if child["result_omitted"],
              do: {:error, :omitted_payload_history},
              else: {:completed, child["result"]}

          {:reply, reply, s}

        _ ->
          {:reply, {:error, :composition_step_in_progress}, s}
      end
    else
      {:error, _} = error -> {:reply, error, s}
      _ -> {:reply, {:error, :composition_step_unavailable}, s}
    end
  end

  def handle_call({:release_step, ticket}, {owner, _}, s) do
    case s.flow_tickets[ticket] || s.step_ticket do
      %{ticket: ^ticket, owner: ^owner, monitor: monitor}
      when is_nil(s.checkpoint.pending) ->
        Process.demonitor(monitor, [:flush])
        {:reply, :ok, %{s | step_ticket: nil, flow_tickets: Map.delete(s.flow_tickets, ticket)}}

      _ ->
        {:reply, {:error, :invalid_composition_step_ticket}, s}
    end
  end

  def handle_call(
        {:attach_step, ticket, run, options},
        {owner, _},
        %{config: %{kind: :composition}} = s
      ) do
    {run, options} = restrict_node10(s, s.scope.run_id, run, options)
    flow? = root10(s)["frame_version"] == 11
    s = if flow?, do: %{s | step_ticket: s.flow_tickets[ticket]}, else: s

    with %{
           ticket: ^ticket,
           owner: ^owner,
           step: step,
           input: input,
           revision: revision,
           index: index
         } <- s.step_ticket,
         nil <- s.checkpoint.pending,
         true <- flow? or revision === s.record["revision"],
         true <-
           flow? or index === length(step_nodes(s.record["execution"]["progress"]["runtime"])),
         true <- run.agent === step.agent and run.prompt === input,
         true <-
           if(flow?,
             do: root10(s)["frontier"]["state"] == "open" and root10(s)["cursor"] == "running",
             else: root10(s)["cursor"] in ["empty", "between_steps"]
           ),
         {:ok, scope} <- ExecutionScope.join_for(s.scope, run.run_id, run.model, options, owner) do
      case attach_step(
             %{s | flow_tickets: Map.delete(s.flow_tickets, ticket)},
             run,
             options,
             step,
             input,
             scope
           ) do
        {:reply, {:error, _}, %{checkpoint: %{pending: nil}} = next} = reply
        when not is_map_key(next.nodes, run.run_id) ->
          :ok = ExecutionScope.discard_empty_child(s.scope, scope)
          reply

        reply ->
          reply
      end
    else
      {:error, _} = error -> {:reply, error, s}
      _ -> {:reply, {:error, :invalid_composition_step}, s}
    end
  end

  def handle_call(_, _, %{config: %{kind: :composition}, record: nil} = s),
    do: {:reply, {:error, :unsupported_structural_operation}, s}

  def handle_call(
        _,
        _,
        %{
          config: %{kind: :composition},
          record: %{"execution" => %{"progress" => %{"runtime" => %{"cursor" => "empty"}}}}
        } = s
      ),
      do: {:reply, {:error, :unsupported_structural_operation}, s}

  def handle_call(
        {:attach, _, _, _, _, _},
        _,
        %{
          config: %{kind: :composition},
          record: %{"execution" => %{"progress" => %{"runtime" => %{"frame_version" => version}}}}
        } = s
      )
      when version not in [10, 11],
      do: {:reply, {:error, :unsupported_structural_operation}, s}

  def handle_call({:saved, run_id, id}, _, s) do
    {:reply, Frame.outcome(Frame.node(s.record["execution"]["progress"]["runtime"], run_id), id),
     s}
  end

  def handle_call(_, _, %{checkpoint: %{pending: pending}} = s) when not is_nil(pending),
    do: {:reply, {:error, :checkpoint_pending}, s}

  def handle_call(_, _, %{record: %{"execution" => %{"state" => state}}} = s)
      when state != "claimed",
      do: {:reply, {:error, :execution_not_claimed}, s}

  def handle_call(
        request,
        from,
        %{
          record: %{"execution" => %{"progress" => %{"runtime" => %{"frame_version" => version}}}}
        } = s
      )
      when version in [10, 11],
      do: handle10(request, from, s)

  def handle_call(
        {:output_resolution, run, decision, parts, output},
        _,
        %{config: %{kind: :composition}} = s
      ) do
    with {:ok, entry} <- OutputResolution.new(run, decision, parts, output, checkpoint_limit(s)) do
      runtime = s.record["execution"]["progress"]["runtime"]
      entries = Map.get(runtime, "output_resolutions", %{})

      runtime =
        runtime
        |> Map.put(
          "frame_version",
          if(runtime["frame_version"] in [7, 8, 9], do: runtime["frame_version"], else: 6)
        )
        |> Map.put("output_resolutions", Map.put(entries, run.model_request_id, entry))

      progress = Map.put(s.record["execution"]["progress"], "runtime", runtime)

      payload =
        worker(s, %{
          "node_id" => run.run_id,
          "snapshot" => s.record["snapshot"],
          "progress" => progress
        })

      case command_capacity(s, "output_resolution", payload) do
        :ok ->
          {reply, next} = write(s, "output_resolution", payload)
          {:reply, ok(reply), next}

        error ->
          {:reply, error, s}
      end
    else
      error -> {:reply, error, s}
    end
  end

  def handle_call({:output_resolution, _, _, _, _}, _, s), do: {:reply, :ok, s}

  def handle_call({:model_begin, run}, _, s) do
    with :ok <-
           if(s.config[:kind] == :composition, do: OutputResolution.preflight(run), else: :ok),
         :ok <- ExecutionScope.admit_request(run.execution_scope, run.model_request_id, run.model),
         {:ok, progress} <- frame_progress(s, run, "request"),
         {:ok, request_data} <-
           RequestData.capture(
             run,
             Frame.node(progress["runtime"], run.run_id),
             node_config(s, run.run_id)
           ),
         id = effect_id(run, "model", run.model_request_id),
         intent = %{
           "kind" => "model",
           "call_id" => run.model_request_id,
           "payload" => %{
             "phase" => "model_dispatch",
             "run_id" => run.run_id,
             "step" => run.run_step,
             "history_index" => length(run.messages),
             "request_data" => request_data
           }
         },
         {:ok, intent} <- retry_intent(s, id, intent, run.params.idempotency_key),
         progress = legacy_admission(s, progress),
         {:ok, s} <-
           begin_effect(s, id, intent, %{"snapshot" => snapshot(run, s), "progress" => progress}) do
      {:reply, :ok, s}
    else
      {:error, reason} -> {:reply, {:error, reason}, s}
      {:error, reason, s} -> {:reply, {:error, reason}, s}
    end
  end

  def handle_call({:model_done, run}, _, s) do
    case frame_progress(s, run, "response") do
      {:ok, progress} ->
        payload =
          worker(s, %{
            "effect_id" => effect_id(run, "model", run.model_request_id),
            "outcome" =>
              Outcome.model(
                List.last(run.messages),
                Frame.node(progress["runtime"], run.run_id)["model_data"]
              ),
            "snapshot" => snapshot(run, s),
            "progress" => progress
          })

        case outcome_capacity(s, payload) do
          :ok ->
            {reply, s} = write(s, "outcome", payload)
            {:reply, ok(reply), s}

          {:error, reason} ->
            model_without_frame(s, run, reason)
        end

      {:error, reason} ->
        model_without_frame(s, run, reason)
    end
  end

  def handle_call({:batch, run}, _, s) do
    result =
      with :ok <-
             ExecutionScope.admit_tools(
               run.execution_scope,
               run.model_request_id,
               length(Message.Response.tool_calls(List.last(run.messages)))
             ) do
        checkpoint(s, run, "batch")
      end

    case result do
      {:ok, s} -> {:reply, :ok, s}
      {:error, reason} -> {:reply, {:error, reason}, s}
      {:error, reason, s} -> {:reply, {:error, reason}, s}
    end
  end

  def handle_call({:admit, run, call, tool}, _, s) do
    budget = ExecutionScope.check_reserved_tools(run.execution_scope, run.model_request_id)
    action = ExecutionScope.decision(run.execution_scope, call.tool_name)
    approval_id = effect_id(run, "approval", call.tool_call_id)
    previous = get_in(s.record, ["execution", "progress", "approvals", approval_id])
    {:ok, schema_hash} = Frame.fingerprint(tool)
    {:ok, args} = ExAgent.Tool.JSON.normalize(call.args)

    binding = %{
      "id" => approval_id,
      "run_id" => run.run_id,
      "call_id" => call.tool_call_id,
      "tool_name" => call.tool_name,
      "args" => args,
      "schema_hash" => schema_hash,
      "definition" => node_config(s, run.run_id).definition,
      "policy" => node_config(s, run.run_id).policy
    }

    cond do
      match?({:error, _}, budget) ->
        {:reply, budget, s}

      action == :deny ->
        {:reply, :deny, s}

      previous && not approval_matches?(previous, binding) ->
        {:reply, {:error, :approval_payload_changed}, s}

      action == :ask and not (is_map(previous) and Approval.approved?(previous)) ->
        {:reply, :pending, %{s | pending: Map.put(s.pending, approval_id, binding)}}

      not is_nil(tool.delegation) ->
        case Frame.child_for(
               s.record["execution"]["progress"]["runtime"],
               run.run_id,
               run.model_request_id,
               call.tool_call_id
             ) do
          nil ->
            {:reply, :allow, s}

          {_, child} ->
            if Record.digest(child["call"]["args"]) == Record.digest(args) and
                 child["call"]["schema_hash"] == schema_hash,
               do: {:reply, :allow, s},
               else: {:reply, {:error, :continuation_delegation_mismatch}, s}
        end

      true ->
        intent = %{
          "kind" => "tool",
          "call_id" => call.tool_call_id,
          "payload" => %{
            "tool_name" => call.tool_name,
            "args" => args,
            "schema_hash" => schema_hash,
            "run_id" => run.run_id,
            "model_request_id" => run.model_request_id
          }
        }

        {:ok, original_hash} = Outcome.call_hash(original_call(run, call.tool_call_id))

        intent =
          intent
          |> put_in(["payload", "call_hash"], original_hash)
          |> put_in(["payload", "phase"], "dispatch")

        id = Retry.active_id(s.record["execution"], effect_id(run, "tool", call.tool_call_id))

        case admit_tool_attempt(s, run, id, intent, tool) do
          {:ok, s, nil} -> {:reply, :allow, s}
          {:ok, s, key} -> {:reply, {:allow, key, id}, s}
          {:error, reason, s} -> {:reply, {:error, reason}, s}
        end
    end
  end

  def handle_call({:observed_outcome, run, part, input}, _, s) do
    alias ExAgent.Continuation.ToolEvidence
    runtime = s.record["execution"]["progress"]["runtime"]
    active = Retry.active_id(s.record["execution"], effect_id(run, "tool", part.tool_call_id))

    identity =
      if active == effect_id(run, "tool", part.tool_call_id),
        do: {run.model_request_id, part.tool_call_id},
        else: {run.model_request_id, part.tool_call_id, active}

    if runtime["frame_version"] in [8, 9] do
      with {:ok, observation, accounting} <-
             ExecutionScope.observe_tool(run.execution_scope, identity, input),
           true <- ToolEvidence.observation?(observation) do
        case handle_call({:tool_outcome, run, part, observation}, nil, s) do
          {:reply, :ok, next} -> {:reply, accounting, next}
          other -> other
        end
      else
        {:error, reason} -> {:reply, {:error, reason}, s}
        _ -> {:reply, {:error, :invalid_tool_accounting}, s}
      end
    else
      ExecutionScope.contribute(run.execution_scope, identity, input)
      handle_call({:outcome, run, part}, nil, s)
    end
  end

  def handle_call({:outcome, run, part}, _, s) do
    case Frame.child_for(
           s.record["execution"]["progress"]["runtime"],
           run.run_id,
           run.model_request_id,
           part.tool_call_id
         ) do
      nil -> handle_call({:tool_outcome, run, part, nil}, nil, s)
      {id, _} -> delegation_outcome(s, run, part, id, "raw")
    end
  end

  def handle_call({:tool_outcome, run, part, observation}, _, s) do
    progress = s.record["execution"]["progress"]

    with {:ok, scope} <- Frame.export_scope(s.scope, progress["runtime"]) do
      {:ok, outcome} = Outcome.new(part)
      frame = put_part(progress["runtime"], run.run_id, part) |> Frame.with_scope(scope)
      frame = put_observation(frame, run, part, observation)
      frame = accounting_snapshot(frame, run, s)
      progress = Map.put(progress, "runtime", frame)

      payload =
        worker(s, %{
          "effect_id" =>
            Retry.active_id(s.record["execution"], effect_id(run, "tool", part.tool_call_id)),
          "outcome" => outcome,
          "snapshot" => s.record["snapshot"],
          "progress" => progress
        })

      case tool_command_capacity(s, "outcome", payload) do
        {:ok, s} ->
          {reply, s} = write(s, "outcome", payload)
          {:reply, ok(reply), s}

        {:error, reason} ->
          bytes = Retention.bytes(part)

          if bytes <= @max_measurement do
            omitted = %{
              part
              | content: nil,
                payload_omitted: Retention.marker(:checkpoint, bytes, checkpoint_limit(s))
            }

            frame =
              s.record["execution"]["progress"]["runtime"]
              |> put_part(run.run_id, omitted)
              |> Frame.with_scope(scope)
              |> put_observation(run, omitted, observation)
              |> accounting_snapshot(run, s)

            progress = Map.put(s.record["execution"]["progress"], "runtime", frame)
            {:ok, omitted_outcome} = Outcome.new(omitted)
            payload = %{payload | "progress" => progress, "outcome" => omitted_outcome}

            {reply, s} =
              case tool_command_capacity(s, "outcome", payload) do
                {:ok, reserved} -> write(reserved, "outcome", payload)
                {:error, reason} -> {{:error, reason}, s}
              end

            reply =
              case reply do
                {:ok, _} -> {:omitted, omitted, reason}
                error -> error
              end

            {:reply, reply, s}
          else
            # Preserve the known effect even outside the validated measurement
            # domain. The absent frame outcome explicitly blocks future resume.
            payload = %{payload | "progress" => s.record["execution"]["progress"]}
            {reply, s} = write(s, "outcome", payload)

            error =
              case reply do
                {:ok, _} -> {:error, :checkpoint_measurement_out_of_domain}
                other -> other
              end

            {:reply, error, s}
          end
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, s}
    end
  end

  def handle_call({:pause, run, parts}, _, %{config: %{kind: :composition}} = s) do
    with :ok <- pending_composition(s, run, parts),
         approvals =
           Enum.reduce(s.pending, Map.get(s.record["execution"]["progress"], "approvals", %{}), fn
             {id, binding}, acc ->
               {:ok, approval} =
                 Approval.new(Map.put(binding, "requested_revision", s.record["revision"] + 1))

               Map.put(acc, id, approval)
           end) do
      progress =
        s.record["execution"]["progress"]
        |> Map.put("approvals", approvals)
        |> Budget.refund(elapsed(s))

      {reply, next} =
        write(
          s,
          "pause",
          worker(s, %{"snapshot" => s.record["snapshot"], "progress" => progress})
        )

      reply =
        case reply do
          {:ok, _} -> {:ok, ref(next.record, next.config)}
          error -> error
        end

      {:reply, reply, next}
    else
      {:error, reason} -> {:reply, {:error, reason}, s}
    end
  end

  def handle_call({:pause, run, parts}, _, s) do
    with {:ok, progress} <- frame_progress(s, run, "batch") do
      frame =
        Enum.reduce(parts, Frame.node(progress["runtime"], run.run_id), fn
          %{status: :pending}, f -> f
          part, f -> Frame.put_outcome(f, part)
        end)

      approvals =
        Enum.reduce(s.pending, Map.get(progress, "approvals", %{}), fn {id, binding}, acc ->
          {:ok, approval} =
            Approval.new(Map.put(binding, "requested_revision", s.record["revision"] + 1))

          Map.put(acc, id, approval)
        end)

      runtime = Frame.put_node(progress["runtime"], run.run_id, frame)

      progress = Map.put(progress, "runtime", runtime)

      progress =
        if run.parent_run_id, do: progress, else: Map.put(progress, "approvals", approvals)

      {operation, progress} =
        if run.parent_run_id do
          {"checkpoint",
           put_in(progress, ["runtime", "children", run.run_id, "status"], "paused")}
        else
          {"pause", Budget.refund(progress, elapsed(s))}
        end

      {reply, s} =
        if operation == "pause" and
             Enum.any?(Map.get(runtime, "children", %{}), fn {_, c} ->
               c["status"] == "running"
             end),
           do: {{:error, :continuation_tree_not_quiescent}, s},
           else:
             write_node(
               s,
               run,
               operation,
               worker(s, %{"snapshot" => snapshot(run, s), "progress" => progress})
             )

      reply =
        case reply do
          {:ok, _} -> {:ok, ref(s.record, s.config)}
          error -> error
        end

      {:reply, reply, s}
    else
      {:error, reason} -> {:reply, {:error, reason}, s}
    end
  end

  def handle_call({:settle, run, parts}, _, s) do
    result =
      Enum.reduce_while(parts, {:ok, s, %{}, nil}, fn
        %{status: :pending}, acc ->
          {:cont, acc}

        part, {:ok, current, replacements, error} ->
          case settle_part(current, run, part) do
            {:ok, next} ->
              {:cont, {:ok, next, replacements, error}}

            {:retained, retained, reason, next} ->
              {:cont,
               {:ok, next, Map.put(replacements, part.tool_call_id, retained), error || reason}}

            {:error, reason, next} ->
              {:halt, {:error, reason, next, replacements}}
          end
      end)

    case result do
      {:ok, s, replacements, error} ->
        {:reply, {:settled, Enum.map(parts, &Map.get(replacements, &1.tool_call_id, &1)), error},
         s}

      {:error, reason, s, replacements} ->
        {:reply, {:settled, Enum.map(parts, &Map.get(replacements, &1.tool_call_id, &1)), reason},
         s}
    end
  end

  def handle_call({:tool_resolution, run, parts, controls, settle_error}, _, s) do
    alias ExAgent.Continuation.ToolEvidence
    runtime = s.record["execution"]["progress"]["runtime"]

    cond do
      runtime["frame_version"] == 9 and settle_error == nil and
        controls === List.duplicate({false, nil}, length(parts)) and
          pending_composition(s, run, parts) == :ok ->
        {:reply, :ok, s}

      runtime["frame_version"] in [8, 9] ->
        key = ToolEvidence.key(run.run_id, run.model_request_id)
        batch = runtime["tool_batches"][key]

        calls =
          Enum.zip(parts, controls)
          |> Enum.map(fn {part, {retry, error}} ->
            %{
              "effect_id" => effect_id(run, "tool", part.tool_call_id),
              "result_hash" => elem(Outcome.hash(part), 1),
              "retry" => retry,
              "error" => ToolEvidence.error(error)
            }
          end)

        complete =
          Enum.all?(calls, fn c ->
            effect = s.record["execution"]["effects"][c["effect_id"]]
            effect["state"] == "confirmed" and effect["outcome"]["data"]["phase"] == "final"
          end)

        if complete do
          resolution = %{"calls" => calls, "settle_error" => ToolEvidence.error(settle_error)}

          inputs =
            Enum.zip(parts, controls)
            |> Enum.map(fn {p, {retry, error}} -> {p.tool_name, p.status, retry, error} end)

          {counts, _} = ToolEvidence.reduce(inputs, run.tool_retries, batch["limits"])

          runtime =
            runtime
            |> put_in(["tool_batches", key, "resolution"], resolution)
            |> put_in(["children", run.run_id, "frame", "tool_retries"], counts)

          payload =
            worker(s, %{
              "node_id" => run.run_id,
              "snapshot" => s.record["snapshot"],
              "progress" => Map.put(s.record["execution"]["progress"], "runtime", runtime)
            })

          {reply, next} = write(s, "tool_resolution", payload)
          {:reply, ok(reply), next}
        else
          {:reply, {:error, :execution_uncertain}, s}
        end

      true ->
        {:reply, :ok, s}
    end
  end

  def handle_call({:finish, run, output}, _, s) do
    with {:ok, progress} <- frame_progress(s, run, "finish") do
      if run.parent_run_id do
        finish_child(s, run, progress, output)
      else
        progress = Budget.refund(progress, elapsed(s))

        {reply, s} =
          write_node(
            s,
            run,
            "finish",
            worker(s, %{"snapshot" => snapshot(run, s), "progress" => progress})
          )

        {:reply, ok(reply), s}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, s}
    end
  end

  def handle_call({:child, parent, call}, _, s) do
    runtime = s.record["execution"]["progress"]["runtime"]

    case Frame.child_for(runtime, parent.run_id, parent.model_request_id, call.tool_call_id) do
      nil ->
        {:reply, nil, s}

      {_, %{"status" => "completed", "result_omitted" => omitted}} when not is_nil(omitted) ->
        {:reply, {:error, :omitted_payload_history}, s}

      {_, %{"status" => "completed", "result" => value}} ->
        {:reply, {:completed, value}, s}

      {id, _} ->
        progress =
          put_in(
            s.record["execution"]["progress"],
            ["runtime", "children", id, "status"],
            "running"
          )

        {reply, s} =
          write(
            s,
            "node_checkpoint",
            worker(s, %{
              "node_id" => id,
              "snapshot" => s.record["snapshot"],
              "progress" => progress
            })
          )

        {:reply, if(match?({:ok, _}, reply), do: {:resume, s.nodes[id]}, else: reply), s}
    end
  end

  def handle_call({:attach, parent, run, call, config, options}, {owner, _}, s) do
    with {:ok, scope} <-
           ExecutionScope.join_for(parent.execution_scope, run.run_id, run.model, options, owner),
         run = %{
           run
           | execution_scope: scope,
             parent_run_id: parent.run_id,
             root_run_id: parent.root_run_id,
             continuation: self(),
             attempt_id: s.record["execution"]["attempt_id"]
         },
         {:ok, frame} <- Frame.capture(run, config, "request"),
         {:ok, tree} <- ExecutionScope.export_tree(s.scope),
         {:ok, schema_hash} <-
           Frame.fingerprint(Map.fetch!(parent.prepared_tools, call.tool_name)),
         {:ok, call_hash} <- Outcome.call_hash(original_call(parent, call.tool_call_id)),
         {:ok, args} <- ExAgent.Tool.JSON.normalize(call.args) do
      child = %{
        "parent_run_id" => parent.run_id,
        "parent_request_id" => parent.model_request_id,
        "parent_response" => Message.to_json([List.last(parent.messages)]),
        "parent_result" => nil,
        "call" => %{
          "call_id" => call.tool_call_id,
          "tool_name" => call.tool_name,
          "args" => args,
          "schema_hash" => schema_hash,
          "call_hash" => call_hash
        },
        "definition" => config.definition,
        "policy" => config.policy,
        "model_ref" => config.model_ref,
        "deadline_at" =>
          if(options[:deadline],
            do:
              max(
                System.system_time(:millisecond) + options[:deadline] -
                  System.monotonic_time(:millisecond),
                0
              )
          ),
        "frame" => frame,
        "snapshot" => capture_snapshot(run, s),
        "result" => nil,
        "result_omitted" => nil,
        "outcome" => nil,
        "status" => "running"
      }

      runtime = s.record["execution"]["progress"]["runtime"]
      runtime = runtime |> put_in(["children", run.run_id], child) |> Frame.with_scope(tree)
      progress = Map.put(s.record["execution"]["progress"], "runtime", runtime)

      s = %{
        s
        | nodes: Map.put(s.nodes, run.run_id, %{state: run, config: config, options: options})
      }

      payload = worker(s, %{"snapshot" => s.record["snapshot"], "progress" => progress})

      case Frame.validate(runtime) do
        :ok ->
          {reply, s} = write_node(s, run, "checkpoint", payload)
          {:reply, if(match?({:ok, _}, reply), do: {:ok, run}, else: reply), s}

        error ->
          {:reply, error, s}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, s}
    end
  end

  defp execution_progress(execution, config, revision) do
    progress = execution["progress"] |> Map.put("snapshot_revision_base", revision)

    progress =
      if config[:snapshot_base_usage],
        do: Map.put(progress, "conversation_usage", Usage.to_map(config.snapshot_base_usage)),
        else: progress

    %{execution | "progress" => progress}
  end

  # The new empty leaf reserves three receipts plus its input receipt. Keep the
  # completed-prefix reserve intact; payload-dependent byte checks follow mapping.
  defp step_journal_capacity(record) do
    execution = record["execution"]

    if map_size(execution["effects"]) + Retry.pending_slots(execution) < 256 and
         map_size(record["receipts"]) + Record.receipt_reserve(execution) + 4 <= 1024,
       do: :ok,
       else: {:error, :record_limit}
  end

  defp check_step_deadline(s) do
    if System.monotonic_time(:millisecond) < step_deadline(s),
      do: :ok,
      else: {:error, :deadline_exceeded}
  end

  defp retained_step_input(step, frame, s) do
    with {:ok, input} <- mapped_step_input(step, frame),
         {:ok, input} <- ExAgent.Tool.JSON.normalize(input),
         :ok <- Retention.check(input, checkpoint_limit(s), :checkpoint) do
      {:ok, input}
    else
      _ -> {:error, :invalid_composition_input}
    end
  end

  defp step_capacity(s) do
    if s.record["execution"]["progress"]["runtime"]["cursor"] == "empty" do
      :ok
    else
      successor_capacity(s)
    end
  end

  defp successor_capacity(s) do
    with {:ok, authority} <- ExecutionScope.authority(s.scope),
         {:ok, total} <- ExecutionScope.snapshot(s.scope) do
      limits = ExAgent.Continuation.Authority.limits_load(authority["usage"])

      ExAgent.UsageLimits.check_before_request(
        limits,
        total.usage,
        total.request_count,
        total.cost_cents
      )
    end
  end

  defp mapped_step_input(step, frame) do
    children = Enum.sort_by(step_nodes(frame), & &1["link"]["index"])
    outputs = Map.new(children, &{&1["link"]["step_id"], &1["result"]})

    if Map.has_key?(step, :input),
      do: step.input.(frame["input"], outputs),
      else: {:ok, if(children == [], do: frame["input"], else: List.last(children)["result"])}
  rescue
    _ -> {:error, :invalid_composition_input}
  catch
    _, _ -> {:error, :invalid_composition_input}
  end

  defp step_deadline(s) do
    Authority.minimum(s.scope.deadline, s.attempt_deadline)
  end

  defp finish_child(s, run, progress, output) do
    # Persist the actual post-hook value. A minimal omission is reserved before
    # Model IO so an oversized value cannot turn into permission to replay hooks.
    portable =
      with {:ok, _} <- ExAgent.Tool.JSON.encoded_result(output),
           do: {:ok, output |> Jason.encode!() |> Jason.decode!()}

    step? = get_in(progress, ["runtime", "children", run.run_id, "link", "kind"]) == "step"
    operation = if step?, do: "step_output", else: "node_checkpoint"

    terminal? =
      step? and
        map_size(progress["runtime"]["children"]) ==
          length(progress["runtime"]["binding"]["steps"])

    progress = if terminal?, do: Budget.refund(progress, elapsed(s)), else: progress
    base = put_in(progress, ["runtime", "children", run.run_id, "status"], "completed")

    base =
      if step?,
        do:
          put_in(
            base,
            ["runtime", "cursor"],
            if(terminal?, do: "completed", else: "between_steps")
          ),
        else: base

    candidate =
      case portable do
        {:ok, value} -> put_in(base, ["runtime", "children", run.run_id, "result"], value)
        _ -> base
      end

    payload =
      worker(s, %{
        "node_id" => run.run_id,
        "snapshot" => s.record["snapshot"],
        "progress" => candidate
      })

    capacity =
      if match?({:ok, _}, portable),
        do: command_capacity(s, operation, payload),
        else: {:error, :unrepresentable_child_result}

    case capacity do
      :ok ->
        {reply, next} = write(s, operation, payload)
        {:reply, ok(reply), next}

      {:error, reason} ->
        measured =
          if step? and progress["runtime"]["frame_version"] in [6, 7, 8, 9] and
               match?({:ok, _}, portable),
             do: elem(portable, 1),
             else: output

        marker = Retention.marker(:checkpoint, Retention.bytes(measured), checkpoint_limit(s))
        omitted = put_in(base, ["runtime", "children", run.run_id, "result_omitted"], marker)
        {reply, next} = write(s, operation, %{payload | "progress" => omitted})
        {:reply, if(match?({:ok, _}, reply), do: {:error, reason}, else: reply), next}
    end
  end

  defp settle_part(%{record: %{"execution" => %{"state" => state}}} = s, _, _)
       when state != "claimed",
       do: {:error, :execution_not_claimed, s}

  defp settle_part(s, run, part) do
    case Frame.child_for(
           s.record["execution"]["progress"]["runtime"],
           run.run_id,
           run.model_request_id,
           part.tool_call_id
         ) do
      nil ->
        settle_tool_part(s, run, part)

      {id, _} ->
        case delegation_outcome(s, run, part, id, "final") do
          {:reply, :ok, next} -> {:ok, next}
          {:reply, {:error, reason}, next} -> {:error, reason, next}
        end
    end
  end

  defp attach_step(s, run, options, step, input, scope) do
    with run = %{
           run
           | execution_scope: scope,
             parent_run_id: s.scope.run_id,
             root_run_id: s.scope.root_run_id,
             continuation: self(),
             continuation_version: s.record["execution"]["progress"]["runtime"]["frame_version"],
             attempt_id: s.record["execution"]["attempt_id"]
         },
         config =
           Map.merge(s.config, Map.take(step, [:definition, :policy, :model_ref, :model_codec])),
         {:ok, frame} <- Frame.capture(run, config, "request"),
         {:ok, authority} <- ExecutionScope.authority(scope),
         {:ok, tree} <- ExecutionScope.export_tree(s.scope) do
      child = %{
        "parent_run_id" => s.scope.run_id,
        "link" => %{
          "kind" => "step",
          "step_id" => step.id,
          "index" => s.step_ticket.index,
          "input" => input
        },
        "definition" => step.definition,
        "policy" => step.policy,
        "model_ref" => step.model_ref,
        "output_ref" => step.output_ref,
        "frame" => frame,
        "snapshot" => capture_snapshot(run, s),
        "status" => "running",
        "result" => nil,
        "result_omitted" => nil
      }

      runtime =
        s.record["execution"]["progress"]["runtime"]
        |> Map.merge(%{
          "frame_version" => s.record["execution"]["progress"]["runtime"]["frame_version"],
          "cursor" => "running",
          "children" =>
            Map.put(s.record["execution"]["progress"]["runtime"]["children"], run.run_id, child)
        })
        |> update_in(["authority"], &Map.put(&1, run.run_id, Map.delete(authority, "usage")))
        |> Frame.with_scope(tree)

      progress = Map.put(s.record["execution"]["progress"], "runtime", runtime)

      payload =
        worker(s, %{
          "node_id" => run.run_id,
          "snapshot" => s.record["snapshot"],
          "progress" => progress
        })

      payload =
        if run.continuation_version in [10, 11],
          do:
            worker10(s, %{
              "node_id" => run.run_id,
              "node" => Map.put(child, "error", nil),
              "authority" => Map.delete(authority, "usage")
            }),
          else: payload

      case command_capacity(s, "step_input", payload) do
        :ok ->
          Process.demonitor(s.step_ticket.monitor, [:flush])

          s = %{
            s
            | nodes:
                Map.put(s.nodes, run.run_id, %{state: run, config: config, options: options}),
              step_ticket: nil
          }

          {reply, s} = write(s, "step_input", payload)

          reply =
            case reply do
              {:ok, %{replayed: false}} -> {:ok, run}
              {:ok, _} -> {:error, :stale_receipt}
              error -> error
            end

          {:reply, reply, s}

        error ->
          Process.demonitor(s.step_ticket.monitor, [:flush])
          {:reply, error, %{s | step_ticket: nil}}
      end
    else
      {:error, _} = error -> {:reply, error, s}
      _ -> {:reply, {:error, :invalid_composition_step}, s}
    end
  end

  defp settle_tool_part(s, run, part) do
    effect_id = Retry.active_id(s.record["execution"], effect_id(run, "tool", part.tool_call_id))
    previous = s.record["execution"]["effects"][effect_id]

    {:ok, scope} =
      Frame.export_scope(s.scope, s.record["execution"]["progress"]["runtime"])

    frame =
      s.record["execution"]["progress"]["runtime"]
      |> put_part(run.run_id, part)
      |> Frame.with_scope(scope)

    progress = Map.put(s.record["execution"]["progress"], "runtime", frame)

    payload =
      worker(s, %{
        "effect_id" => effect_id,
        "snapshot" => snapshot(run, s),
        "progress" => progress
      })

    result =
      case previous do
        nil ->
          if Retry.incoming(s.record["execution"], effect_id) do
            {{:error, :retry_not_dispatched}, s}
          else
            call = original_call(run, part.tool_call_id)
            {:ok, call_hash} = Outcome.call_hash(call)
            {:ok, outcome} = Outcome.new(part, "final")

            intent = %{
              "kind" => "tool",
              "call_id" => part.tool_call_id,
              "payload" => %{
                "tool_name" => part.tool_name,
                "call_hash" => call_hash,
                "schema_hash" => Frame.node(frame, run.run_id)["selected_tools"][part.tool_name],
                "phase" => "pre_dispatch"
              }
            }

            resolved_payload =
              Map.merge(payload, %{"intent" => intent, "outcome" => outcome})
              |> update_in(
                ["progress", "runtime"],
                &put_observation(&1, run, part, ExAgent.Continuation.ToolEvidence.pre_dispatch())
              )

            case tool_command_capacity(s, "resolve_call", resolved_payload) do
              {:ok, reserved} -> write(reserved, "resolve_call", resolved_payload)
              {:error, reason} -> {{:error, reason}, s}
            end
          end

        %{"state" => "confirmed", "outcome" => %{"data" => %{"phase" => "raw"} = data}} ->
          {:ok, outcome} = Outcome.new(part, "final", data["raw_hash"])
          final_payload = Map.put(payload, "outcome", outcome)

          case tool_command_capacity(s, "finalize_call", final_payload) do
            {:ok, s} ->
              write(s, "finalize_call", final_payload)

            {:error, reason} ->
              retained = %{
                part
                | content: nil,
                  payload_omitted:
                    Retention.marker(:checkpoint, Retention.bytes(part), checkpoint_limit(s))
              }

              {:ok, outcome} = Outcome.new(retained, "final", data["raw_hash"])

              progress = Map.update!(progress, "runtime", &put_part(&1, run.run_id, retained))

              retained_payload = %{
                final_payload
                | "outcome" => outcome,
                  "progress" => progress
              }

              {reply, next} =
                case tool_command_capacity(s, "finalize_call", retained_payload) do
                  {:ok, reserved} -> write(reserved, "finalize_call", retained_payload)
                  {:error, reason} -> {{:error, reason}, s}
                end

              case reply do
                {:ok, _} -> {{:retained, retained, reason}, next}
                other -> {other, next}
              end
          end

        %{"state" => "confirmed", "outcome" => %{"data" => %{"phase" => "final"} = data}} ->
          if Outcome.hash(part) == {:ok, data["result_hash"]},
            do: {{:ok, nil}, s},
            else: {{:error, :continuation_outcome_mismatch}, s}

        _ ->
          {{:error, :execution_uncertain}, s}
      end

    case result do
      {{:ok, _}, next} -> {:ok, next}
      {{:retained, retained, reason}, next} -> {:retained, retained, reason, next}
      {{:error, reason}, next} -> {:error, reason, next}
    end
  end

  defp node_config(s, id), do: if(id == s.scope.run_id, do: s.config, else: s.nodes[id].config)

  defp admit_tool_attempt(s, run, id, intent, tool) do
    case Retry.incoming(s.record["execution"], id) do
      nil ->
        case begin_effect(s, id, intent) do
          {:ok, next} -> {:ok, next, nil}
          error -> error
        end

      plan ->
        with true <- tool.takes_ctx,
             {:ok, intent} <- retry_intent(s, id, intent, plan["idempotency_key"]),
             original_usage_id =
               if(Retry.incoming(s.record["execution"], plan["original_effect_id"]),
                 do: {run.model_request_id, intent["call_id"], plan["original_effect_id"]},
                 else: {run.model_request_id, intent["call_id"]}
               ),
             :ok <-
               ExecutionScope.retain_uncertain_tool_usage(run.execution_scope, original_usage_id),
             :ok <- ExecutionScope.admit_retry_tool(run.execution_scope, id, run.model_request_id),
             {:ok, progress} <- frame_progress(s, run, "batch"),
             {:ok, next} <-
               begin_effect(s, id, intent, %{
                 "snapshot" => snapshot(run, s),
                 "progress" => progress
               }) do
          {:ok, next, plan["idempotency_key"]}
        else
          false -> {:error, :retry_tool_context_required, s}
          {:error, reason} -> {:error, reason, s}
          {:error, _, _} = error -> error
        end
    end
  end

  defp upgrade_root(s) do
    old = s.record["execution"]["progress"]["runtime"]

    if old["frame_version"] in [1, 2] do
      {:ok, scope} = ExecutionScope.export_tree(s.scope)

      frame =
        old
        |> Map.put("frame_version", 3)
        |> Map.put("model_binding", nil)
        |> Map.put_new("children", %{})
        |> Map.put("scope", scope)

      progress =
        s.record["execution"]["progress"]
        |> Map.put("runtime", frame)
        |> then(&legacy_admission(s, &1))

      {reply, next} =
        write(
          s,
          "checkpoint",
          worker(s, %{"snapshot" => s.record["snapshot"], "progress" => progress})
        )

      {if(match?({:ok, _}, reply), do: {:ok, next.record}, else: reply), next}
    else
      {{:ok, s.record}, s}
    end
  end

  defp put_part(runtime, id, part) do
    Frame.put_node(runtime, id, Frame.put_outcome(Frame.node(runtime, id), part))
  end

  defp delegation_outcome(s, run, part, id, phase) do
    runtime = s.record["execution"]["progress"]["runtime"]
    child = runtime["children"][id]
    previous = child["outcome"]

    cond do
      child["status"] != "completed" or part.status != :succeeded ->
        {:reply, {:error, :execution_uncertain}, s}

      previous && previous["data"]["phase"] == "final" ->
        reply =
          if Outcome.hash(part) == {:ok, previous["data"]["result_hash"]},
            do: :ok,
            else: {:error, :continuation_outcome_mismatch}

        {:reply, reply, s}

      phase == "raw" and not is_nil(previous) ->
        {:reply, {:error, :continuation_outcome_mismatch}, s}

      phase == "final" and is_nil(previous) ->
        {:reply, {:error, :continuation_outcome_unavailable}, s}

      true ->
        raw_hash = if previous, do: previous["data"]["raw_hash"], else: nil
        {:ok, outcome} = Outcome.new(part, phase, raw_hash)

        runtime =
          runtime
          |> put_part(run.run_id, part)
          |> put_in(["children", id, "outcome"], outcome)
          |> put_in(["children", id, "parent_result"], Outcome.encode(part))

        progress = Map.put(s.record["execution"]["progress"], "runtime", runtime)

        {reply, s} =
          write(
            s,
            "delegation_outcome",
            worker(s, %{
              "node_id" => id,
              "snapshot" => s.record["snapshot"],
              "progress" => progress
            })
          )

        {:reply, ok(reply), s}
    end
  end

  defp original_call(run, id) do
    run.messages
    |> List.last()
    |> Message.Response.tool_calls()
    |> Enum.find(&(&1.tool_call_id == id))
  end

  defp step_nodes(frame),
    do: frame["children"] |> Map.values() |> Enum.filter(&(&1["link"]["kind"] == "step"))

  defp root10(s), do: s.record["execution"]["progress"]["runtime"]

  defp target10(run, id \\ nil),
    do:
      Map.merge(
        %{"run_id" => run.run_id, "request_id" => run.model_request_id},
        if(id, do: %{"call_id" => id}, else: %{})
      )

  defp worker10(s, data), do: worker(s, Map.put(data, "epoch", root10(s)["frontier"]["epoch"]))

  defp write10(s, operation, data) do
    payload = worker10(s, data)

    with :ok <- command_capacity(s, operation, payload) do
      {reply, next} = write(s, operation, payload)

      reply =
        case reply do
          {:ok, %{replayed: false}} -> :ok
          {:ok, _} -> {:error, :stale_receipt}
          error -> error
        end

      {reply, next}
    else
      error -> {error, s}
    end
  end

  defp handle10({:model_begin, run}, _, s) do
    with :ok <- OutputResolution.preflight(run),
         :ok <- ExecutionScope.admit_request(run.execution_scope, run.model_request_id, run.model),
         root = root10(s),
         {:ok, data} <-
           RequestData.capture(
             run,
             Frame.node(root, run.run_id),
             node_config(s, run.run_id),
             root
           ) do
      {reply, next} = write10(s, "begin_effect", Map.put(target10(run), "request_data", data))
      {:reply, reply, next}
    else
      error -> {:reply, error, s}
    end
  end

  defp handle10({:model_done, run}, _, s) do
    with {:ok, frame} <- Frame.capture(run, node_config(s, run.run_id), "response") do
      {reply, next} =
        write10(
          s,
          "outcome",
          Map.merge(target10(run), %{
            "response" => Message.to_json([List.last(run.messages)]),
            "model_data" => frame["model_data"]
          })
        )

      {:reply, reply, next}
    else
      error -> {:reply, error, s}
    end
  end

  defp handle10({:batch, run}, _, s) do
    with :ok <-
           ExecutionScope.admit_tools(
             run.execution_scope,
             run.model_request_id,
             length(Message.Response.tool_calls(List.last(run.messages)))
           ) do
      {reply, next} = write10(s, "batch_begin", target10(run))
      {:reply, reply, next}
    else
      error -> {:reply, error, s}
    end
  end

  defp handle10({:call10, run, id}, _, s) do
    batch =
      root10(s)["tool_batches"][
        ExAgent.Continuation.ToolEvidence.key(run.run_id, run.model_request_id)
      ]

    {:reply, {:ok, batch["calls"][id]}, s}
  end

  defp handle10({:admit, run, call, tool}, _, s) do
    root = root10(s)

    batch =
      root["tool_batches"][
        ExAgent.Continuation.ToolEvidence.key(run.run_id, run.model_request_id)
      ]

    current = batch["calls"][call.tool_call_id]
    action = ExecutionScope.decision(run.execution_scope, call.tool_name)

    approved =
      Frame.authorized10?(
        s.record,
        run.run_id,
        run.model_request_id,
        call.tool_call_id,
        current["binding"]
      )

    cond do
      ExecutionScope.check_reserved_tools(run.execution_scope, run.model_request_id) != :ok ->
        {:reply, {:error, :usage_limit}, s}

      action == :deny ->
        {:reply, :deny, s}

      action == :ask and not approved ->
        {reply, next} =
          if root["frame_version"] == 11 and current["state"] == "approval" and
               root["frontier"]["state"] == "draining" and
               root["frontier"]["reason"] == "approval",
             do: {:ok, s},
             else: write10(s, "call_wait", target10(run, call.tool_call_id))

        {:reply, if(reply == :ok, do: :pending, else: reply), next}

      true ->
        {reply, next} =
          if current["state"] == "approval",
            do:
              write10(
                s,
                "call_prepared",
                Map.put(target10(run, call.tool_call_id), "args", current["binding"]["args"])
              ),
            else: {:ok, s}

        {reply, next} =
          if reply == :ok and is_nil(tool.delegation),
            do: write10(next, "begin_effect", target10(run, call.tool_call_id)),
            else: {reply, next}

        {:reply, if(reply == :ok, do: :allow, else: reply), next}
    end
  end

  defp handle10({:phase10, run, id, operation, data}, _, s) do
    {reply, next} = write10(s, operation, Map.merge(target10(run, id), data))
    {:reply, reply, next}
  end

  defp handle10({:consume10, run, operation}, _, s) do
    {reply, next} = write10(s, operation, target10(run))
    {:reply, reply, next}
  end

  defp handle10({:settle, _, parts}, _, s), do: {:reply, {:ok, parts}, s}

  defp handle10({:tool_resolution, run, parts, _, error}, _, s) do
    cond do
      error ->
        {:reply, {:error, error}, s}

      root10(s)["frontier"]["reason"] == "fatal" ->
        # The certified controls already selected a deterministic fatal frontier.
        # This batch cannot acquire a successful resolution or consume history.
        {:reply, :ok, s}

      Enum.any?(parts, &(&1.status == :pending)) ->
        {:reply, :ok, s}

      true ->
        {reply, next} = write10(s, "tool_resolution", target10(run))
        {:reply, reply, next}
    end
  end

  defp handle10({:output_resolution, run, decision, parts, output}, _, s) do
    with {:ok, entry} <- OutputResolution.new(run, decision, parts, output, checkpoint_limit(s)) do
      {reply, next} = write10(s, "output_resolution", Map.put(target10(run), "resolution", entry))
      {:reply, reply, next}
    else
      error -> {:reply, error, s}
    end
  end

  defp handle10({:finish, run, _output}, _, s) do
    step? = root10(s)["children"][run.run_id]["link"]["kind"] == "step"

    data =
      Map.merge(
        %{"node_id" => run.run_id},
        if(step?, do: %{"elapsed_ms" => elapsed(s)}, else: %{})
      )

    {reply, next} = write10(s, if(step?, do: "step_output", else: "node_complete"), data)
    {:reply, reply, next}
  end

  defp handle10({:failed, _run}, {owner, _}, %{owner: owner, workers: workers} = s)
       when map_size(workers) == 0 do
    if Frame.call_fatal_closable10?(s.record) do
      {reply, next} = write10(s, "finish", %{"elapsed_ms" => elapsed(s)})
      {:reply, reply, next}
    else
      # No error string authorizes a terminal write. Ambiguous effects/control
      # retain their exact checkpoint for explicit administrative recovery.
      {:reply, :ok, s}
    end
  end

  defp handle10({:failed, _}, _, s), do: {:reply, :ok, s}

  defp handle10({:pause, run, _parts}, _, s) do
    {reply, next} =
      if drained10(s, run.run_id) == :ok,
        do: write10(s, "node_suspend", %{"node_id" => run.run_id}),
        else: {{:error, :continuation_workers_not_quiescent}, s}

    {reply, next} =
      if reply == :ok and root10(s)["children"][run.run_id]["link"]["kind"] == "step" and
           next.workers == %{} and root10(s)["frame_version"] == 10,
         do: write10(next, "pause", %{"elapsed_ms" => elapsed(s)}),
         else: {reply, next}

    {:reply, if(reply == :ok, do: {:ok, ref(next.record, next.config)}, else: reply), next}
  end

  defp handle10({:child, parent, call}, _, s) do
    case Frame.child_for(root10(s), parent.run_id, parent.model_request_id, call.tool_call_id) do
      nil -> {:reply, nil, s}
      {_, %{"status" => "completed", "result" => value}} -> {:reply, {:completed, value}, s}
      {id, _} -> {:reply, {:resume, s.nodes[id]}, s}
    end
  end

  defp handle10({:attach, parent, run, call, config, options}, {owner, _}, s) do
    {run, options} = restrict_node10(s, parent.run_id, run, options)

    with {:ok, scope} <-
           ExecutionScope.join_for(parent.execution_scope, run.run_id, run.model, options, owner),
         run = %{
           run
           | execution_scope: scope,
             parent_run_id: parent.run_id,
             root_run_id: parent.root_run_id,
             continuation: self(),
             continuation_version: root10(s)["frame_version"],
             attempt_id: s.record["execution"]["attempt_id"]
         },
         {:ok, frame} <- Frame.capture(run, config, "request"),
         {:ok, authority} <- ExecutionScope.authority(scope) do
      batch =
        root10(s)["tool_batches"][
          ExAgent.Continuation.ToolEvidence.key(parent.run_id, parent.model_request_id)
        ]

      binding = batch["calls"][call.tool_call_id]["binding"]

      node = %{
        "parent_run_id" => parent.run_id,
        "link" =>
          Map.merge(binding, %{
            "kind" => "delegate",
            "parent_request_id" => parent.model_request_id,
            "call_id" => call.tool_call_id
          }),
        "definition" => config.definition,
        "policy" => config.policy,
        "model_ref" => config.model_ref,
        "output_ref" => nil,
        "frame" => frame,
        "snapshot" => capture_snapshot(run, s),
        "status" => "running",
        "result" => nil,
        "result_omitted" => nil,
        "error" => nil
      }

      {reply, next} =
        write10(
          s,
          "node_attach",
          Map.merge(
            target10(parent, call.tool_call_id),
            %{
              "node_id" => run.run_id,
              "node" => node,
              "authority" => Map.delete(authority, "usage")
            }
          )
        )

      next =
        if reply == :ok,
          do: %{
            next
            | nodes:
                Map.put(next.nodes, run.run_id, %{state: run, config: config, options: options})
          },
          else: next

      {:reply, if(reply == :ok, do: {:ok, run}, else: reply), next}
    else
      error -> {:reply, error, s}
    end
  end

  defp handle10(_, _, s), do: {:reply, {:error, :unsupported_structural_operation}, s}

  defp restrict_node10(s, parent_id, run, options) do
    root = s.record["execution"]["progress"]["runtime"]

    if root["frame_version"] in [10, 11] do
      parent = root["authority"][parent_id]

      usage =
        if parent_id == root["run_id"],
          do: parent["usage"],
          else: root["children"][parent_id]["frame"]["limits"]["usage"]

      options =
        Authority.intersect(parent, usage, Keyword.put(options, :usage_limits, run.usage_limits))

      {%{run | usage_limits: options[:usage_limits]}, options}
    else
      {run, options}
    end
  end

  defp drained10(s, id) do
    own = Enum.filter(s.workers, fn {{_, run, _, _, _}, _} -> run == id end)

    cond do
      own == [] -> :ok
      Enum.any?(own, fn {_, w} -> w.down end) -> {:error, :unconfirmed_continuation_worker}
      true -> :waiting
    end
  end

  defp pending_composition(s, run, parts) do
    runtime = s.record["execution"]["progress"]["runtime"]

    with true <- s.config.kind == :composition,
         true <- Frame.active_step_id(runtime) == run.run_id,
         {:ok, calls} <- Frame.approval_boundary(s.record, s.pending),
         true <- length(parts) == length(calls),
         true <-
           Enum.zip(parts, calls)
           |> Enum.all?(fn {part, call} ->
             part.status == :pending and part.tool_call_id == call.tool_call_id and
               part.tool_name == call.tool_name and
               is_nil(run.prepared_tools[call.tool_name].delegation)
           end),
         true <-
           Message.to_json(run.messages) ===
             runtime["children"][run.run_id]["snapshot"]["message_history"],
         {:ok, scope} <- ExecutionScope.export_tree(s.scope),
         true <- Frame.with_scope(runtime, scope) === runtime do
      :ok
    else
      _ -> {:error, :unsupported_structural_operation}
    end
  rescue
    _ -> {:error, :unsupported_structural_operation}
  end

  defp restore_tool_capacity(s, run) do
    approvals = Map.get(s.record["execution"]["progress"], "approvals", %{})
    own = Map.filter(approvals, fn {_, a} -> a["run_id"] == run.run_id end)

    if own != %{} and match?({:ok, _}, Frame.approval_boundary(s.record, own)) do
      # Restore only the in-memory byte reservation. The durable batch and host
      # counters are already admitted; never call admit_tools again here.
      with {:ok, capacity} <- reserve_tool_batches(s, s.record),
           do: {:ok, %{s | tool_reserve: capacity}}
    else
      {:ok, s}
    end
  end

  defp approval_matches?(previous, binding) do
    case Approval.new(Map.put(binding, "requested_revision", previous["requested_revision"])) do
      {:ok, candidate} -> candidate["payload_hash"] === previous["payload_hash"]
      _ -> false
    end
  end

  defp claim(s) do
    lease = System.system_time(:millisecond) + s.config.lease_ms

    payload = %{
      "owner_id" => id("owner"),
      "attempt_id" => id("attempt"),
      "lease_until" => lease,
      "deadline_at" => s.config[:deadline_at],
      "expires_at" => s.config[:expires_at],
      "active_limit_ms" => s.config[:active_time_limit_ms]
    }

    {reply, s} = write(s, "claim", payload)

    case reply do
      {:ok, %{replayed: false}} ->
        started_at = System.monotonic_time(:millisecond)

        {:ok,
         %{
           s
           | started_at: started_at,
             attempt_deadline:
               ExAgent.Continuation.CompositionRestore.attempt_deadline(s.record, started_at)
         }}
        |> then(fn {:ok, s} -> {{:ok, s.record}, s} end)

      {:ok, _} ->
        {{:error, :stale_receipt}, s}

      error ->
        {error, s}
    end
  end

  defp checkpoint(s, run, cursor) do
    with {:ok, progress} <- frame_progress(s, run, cursor) do
      payload = worker(s, %{"snapshot" => snapshot(run, s), "progress" => progress})

      reserve =
        if progress["runtime"]["frame_version"] in [8, 9] and cursor == "batch" do
          candidate =
            command(
              s.record["record_id"],
              "node_checkpoint",
              Map.put(payload, "node_id", run.run_id)
            )

          with {:ok, %{record: projected}} <-
                 Transition.apply(
                   s.record,
                   {s.config.store.namespace, :agent, s.config.id},
                   s.record["revision"],
                   candidate,
                   System.system_time(:millisecond)
                 ),
               do: reserve_tool_batches(s, projected)
        else
          {:ok, nil}
        end

      case reserve do
        {:ok, capacity} ->
          case write_node(s, run, "checkpoint", payload) do
            {{:ok, _}, s} -> {:ok, if(capacity, do: %{s | tool_reserve: capacity}, else: s)}
            {{:error, reason}, s} -> {:error, reason, s}
          end

        {:error, reason} ->
          {:error, reason, s}
      end
    else
      {:error, reason} -> {:error, reason, s}
    end
  end

  defp frame_progress(s, run, cursor) do
    runtime = s.record["execution"]["progress"]["runtime"]

    with {:ok, frame} <-
           Frame.capture(
             run,
             node_config(s, run.run_id),
             cursor,
             Map.get(runtime, "children", %{})
           ),
         :ok <- same_binding(Frame.node(runtime, run.run_id), frame) do
      previous = Frame.node(runtime, run.run_id)
      frame = Map.put(frame, "permissions", previous["permissions"])

      frame =
        if runtime["frame_version"] in [7, 8, 9],
          do: Map.put(frame, "limits", previous["limits"]),
          else: frame

      frame =
        if cursor == "batch" and previous["model_request_id"] == frame["model_request_id"],
          do: Map.put(frame, "outcomes", previous["outcomes"]),
          else: frame

      runtime = Frame.put_node(runtime, run.run_id, frame)

      runtime =
        if runtime["frame_version"] in [8, 9] and cursor == "batch" do
          key = ExAgent.Continuation.ToolEvidence.key(run.run_id, run.model_request_id)

          update_in(
            runtime,
            ["tool_batches"],
            &Map.put_new(&1, key, ExAgent.Continuation.ToolEvidence.batch(run))
          )
        else
          runtime
        end

      runtime =
        if run.parent_run_id,
          do: put_in(runtime, ["children", run.run_id, "snapshot"], capture_snapshot(run, s)),
          else: runtime

      with {:ok, scope} <- ExecutionScope.export_tree(s.scope) do
        {:ok,
         Map.put(s.record["execution"]["progress"], "runtime", Frame.with_scope(runtime, scope))}
      end
    end
  end

  defp same_binding(previous, current) do
    if Map.get(previous, "model_binding") === current["model_binding"],
      do: :ok,
      else: {:error, :continuation_model_binding_changed}
  end

  defp put_observation(%{"frame_version" => version} = frame, run, part, observation)
       when version in [8, 9] and is_map(observation) do
    key = ExAgent.Continuation.ToolEvidence.key(run.run_id, run.model_request_id)

    put_in(
      frame,
      ["tool_batches", key, "observations", effect_id(run, "tool", part.tool_call_id)],
      observation
    )
  end

  defp put_observation(frame, _, _, _), do: frame

  defp accounting_snapshot(%{"frame_version" => version} = frame, run, s) when version in [8, 9],
    do: put_in(frame, ["children", run.run_id, "snapshot"], capture_snapshot(run, s))

  defp accounting_snapshot(frame, _, _), do: frame

  defp begin_effect(s, effect_id, intent, frame_payload \\ %{}) do
    payload = worker(s, Map.merge(%{"effect_id" => effect_id, "intent" => intent}, frame_payload))
    command = command(s.record["record_id"], "begin_effect", payload)

    preflight =
      with {:ok, %{record: projected}} <-
             Transition.apply(
               s.record,
               {s.config.store.namespace, :agent, s.config.id},
               s.record["revision"],
               command,
               System.system_time(:millisecond)
             ),
           :ok <- reserve_outcome(s, projected, effect_id),
           do: :ok

    result =
      case preflight do
        :ok -> write_command(s, s.record["revision"], command)
        {:error, reason} -> {{:error, reason}, s}
      end

    case result do
      {{:ok, %{replayed: false}}, s} -> {:ok, s}
      {{:ok, _}, s} -> {:error, :stale_receipt, s}
      {{:error, reason}, s} -> {:error, reason, s}
    end
  end

  defp legacy_admission(s, progress) do
    frame = s.record["execution"]["progress"]["runtime"]
    request = frame["model_request_id"]

    if frame["frame_version"] == 1 and frame["cursor"] == "request" and is_binary(request) do
      {:ok, hash} = Record.digest([frame["run_id"], request, "model", request])

      if Map.has_key?(s.record["execution"]["effects"], "model-" <> hash),
        do: progress,
        else:
          Map.put(progress, "legacy_model_admissions", [
            %{"run_id" => frame["run_id"], "request_id" => request}
          ])
    else
      progress
    end
  end

  defp retry_intent(s, id, intent, supplied_key) do
    case Retry.incoming(s.record["execution"], id) do
      nil ->
        cond do
          is_nil(supplied_key) ->
            {:ok, intent}

          Retry.key?(supplied_key) ->
            {:ok, put_in(intent, ["payload", "idempotency_key"], supplied_key)}

          true ->
            {:error, :invalid_idempotency_key}
        end

      plan ->
        original = s.record["execution"]["effects"][plan["original_effect_id"]]["intent"]

        match? =
          if intent["kind"] == "model",
            do: intent["payload"]["request_data"] === original["payload"]["request_data"],
            else:
              Map.take(intent["payload"], ~w(tool_name args schema_hash call_hash)) ===
                Map.take(original["payload"], ~w(tool_name args schema_hash call_hash))

        if match? and supplied_key === plan["idempotency_key"] do
          {:ok,
           Map.update!(
             intent,
             "payload",
             &Map.merge(&1, %{
               "retry_of" => plan["original_effect_id"],
               "idempotency_key" => supplied_key
             })
           )}
        else
          {:error, :retry_payload_changed}
        end
    end
  end

  defp write(s, operation, payload),
    do: write(s, s.record["revision"], operation, payload, s.record["record_id"])

  defp write_node(s, %{parent_run_id: parent, run_id: id}, "checkpoint", payload)
       when not is_nil(parent),
       do: write(s, "node_checkpoint", Map.put(payload, "node_id", id))

  defp write_node(s, _, operation, payload), do: write(s, operation, payload)

  defp write(s, expected, operation, payload, lifetime) do
    write_command(s, expected, command(lifetime, operation, payload))
  end

  defp command(lifetime, operation, payload),
    do: %{
      "record_id" => lifetime,
      "operation" => operation,
      "operation_id" => id("operation"),
      "actor_id" => "exagent-runtime",
      "payload" => payload
    }

  defp write_command(s, expected, command) do
    # A dirty command is bounded before being retained; an oversized future
    # outcome leaves its previously committed intent unresolved, never replayable.
    if Retention.bytes(token(s, expected, command)) > checkpoint_limit(s) or
         byte_size(Jason.encode!(command)) > Record.max_bytes() do
      {{:error, :continuation_frame_limit}, s}
    else
      {reply, checkpoint} = Checkpoint.write(s.checkpoint, expected, command)
      s = %{s | checkpoint: checkpoint}

      case reply do
        {:ok, %{record: record}} ->
          {reply, %{s | record: record}}

        {:error, reason} ->
          {{:error, {:continuation_checkpoint_failed, Retention.reason(reason)}}, s}
      end
    end
  end

  # Reserve a concrete worst-case minimal outcome command before every owned IO.
  # Each pending tool gets its real IDs and marker. ToolReturn's existing history
  # codec omits contributed Usage: the ledger, not that encoded part, owns it.
  # A 4096-control-byte placeholder dominates actual Usage EFT <=4096 and its JSON
  # expansion in each ledger contribution, aggregate and model-response slot.
  defp reserve_outcome(
         s,
         %{"execution" => %{"progress" => %{"runtime" => %{"frame_version" => version}}}} =
           projected,
         effect_id
       )
       when version in [8, 9] do
    if projected["execution"]["effects"][effect_id]["intent"]["kind"] == "tool",
      do: reserved_tool_arguments(s, projected, effect_id),
      else: reserve_legacy_outcome(s, projected, effect_id)
  end

  defp reserve_outcome(s, projected, effect_id),
    do: reserve_legacy_outcome(s, projected, effect_id)

  defp reserve_tool_batches(s, projected) do
    alias ExAgent.Continuation.ToolEvidence
    usage = ToolEvidence.reservation_usage()
    data = Usage.to_map(usage)
    error = ToolEvidence.reservation_error()
    root = projected["execution"]["progress"]["runtime"]

    {root, effects} =
      Enum.reduce(root["tool_batches"], {root, projected["execution"]["effects"]}, fn
        {_, %{"resolution" => resolution}}, acc when not is_nil(resolution) ->
          acc

        {key, batch}, {frame, effects} ->
          run = batch["run_id"]
          request = batch["request_id"]
          calls = ToolEvidence.calls(projected, batch)

          {frame, effects, controls} =
            Enum.reduce(calls, {frame, effects, []}, fn call, {frame, effects, controls} ->
              id = ToolEvidence.effect_id(run, request, call.tool_call_id)
              existing = effects[id]

              {frame, part} =
                if Map.has_key?(batch["observations"], id) do
                  {:ok, [%Message.Request{parts: [part]}]} =
                    Message.from_json(Frame.node(frame, run)["outcomes"][call.tool_call_id])

                  {frame, part}
                else
                  part = %Part.ToolReturn{
                    tool_name: call.tool_name,
                    tool_call_id: call.tool_call_id,
                    status: :validation_error,
                    content: nil,
                    payload_omitted:
                      Retention.marker(:checkpoint, @max_measurement, checkpoint_limit(s))
                  }

                  ancestors = reserve_ancestors(frame["scope"]["nodes"], run, data)

                  op = %{
                    "id" => ["tool", request, call.tool_call_id],
                    "run_id" => run,
                    "usage" => data,
                    "terminal_usage" => data,
                    "complete" => true,
                    "ancestors" => ancestors
                  }

                  obs = %{
                    "origin" => "tool_return",
                    "presence" => "usage",
                    "usage" => data,
                    "application" => %{
                      "status" => "contributed",
                      "complete" => true,
                      "ancestors" => ancestors
                    }
                  }

                  frame =
                    frame
                    |> put_part(run, part)
                    |> update_in(["scope", "operations"], &(&1 ++ [op]))
                    |> put_in(["tool_batches", key, "observations", id], obs)

                  {frame, part}
                end

              raw_hash = existing && existing["outcome"]["data"]["raw_hash"]
              {:ok, outcome} = Outcome.new(part, "final", raw_hash)

              intent =
                if existing,
                  do: existing["intent"],
                  else: %{
                    "kind" => "tool",
                    "call_id" => call.tool_call_id,
                    "payload" => %{
                      "phase" => "dispatch",
                      "run_id" => run,
                      "model_request_id" => request,
                      "tool_name" => call.tool_name,
                      "args" =>
                        get_in(projected, [
                          "execution",
                          "progress",
                          "approvals",
                          "approval-" <>
                            elem(Record.digest([run, request, "approval", call.tool_call_id]), 1),
                          "args"
                        ]) || %{},
                      "call_hash" => elem(Outcome.call_hash(call), 1),
                      "schema_hash" => batch["limits"][call.tool_name]["schema_hash"]
                    }
                  }

              effects =
                Map.put(effects, id, %{
                  "intent" => intent,
                  "state" => "confirmed",
                  "outcome" => outcome
                })

              control = %{
                "effect_id" => id,
                "result_hash" => outcome["data"]["result_hash"],
                "retry" =>
                  frame["tool_batches"][key]["observations"][id]["application"]["status"] !=
                    "rejected",
                "error" => error
              }

              {frame, effects, controls ++ [control]}
            end)

          resolution = %{"calls" => controls, "settle_error" => error}
          batch = %{frame["tool_batches"][key] | "resolution" => resolution}
          frame = put_in(frame, ["tool_batches", key], batch)
          fake = put_in(projected, ["execution", "effects"], effects)

          {counts, _} =
            ToolEvidence.reduce_resolution(
              batch,
              calls,
              fake,
              Frame.node(frame, run)["tool_retries"]
            )

          frame = put_in(frame, ["children", run, "frame", "tool_retries"], counts)
          {frame, effects}
      end)

    root = Frame.with_scope(root, root["scope"])

    root =
      update_in(root, ["children"], fn children ->
        Map.new(children, fn {id, child} ->
          snapshot_usage =
            if ToolEvidence.rejected?(root, id),
              do: Usage.to_map(Usage.partial(usage)),
              else: data

          {id,
           if(child["status"] == "completed",
             do: child,
             else: put_in(child, ["snapshot", "usage"], snapshot_usage)
           )}
        end)
      end)

    candidate =
      projected
      |> put_in(["execution", "effects"], effects)
      |> put_in(["execution", "progress", "runtime"], root)

    payload =
      worker(s, %{
        "node_id" => Frame.active_step_id(root),
        "snapshot" => candidate["snapshot"],
        "progress" => candidate["execution"]["progress"]
      })

    closing = command(projected["record_id"], "tool_resolution", payload)

    # Validate a coherent future current/command pair, not merely a large JSON
    # object. In the current copy all finals/observations already exist, while
    # counters still precede the pending resolution. No synthetic effect is saved.
    control_current =
      Enum.reduce(projected["execution"]["progress"]["runtime"]["tool_batches"], candidate, fn
        {key, %{"resolution" => nil, "run_id" => run}}, current ->
          current
          |> put_in(["execution", "progress", "runtime", "tool_batches", key, "resolution"], nil)
          |> put_in(
            ["execution", "progress", "runtime", "children", run, "frame", "tool_retries"],
            Frame.node(projected["execution"]["progress"]["runtime"], run)["tool_retries"]
          )

        _, current ->
          current
      end)

    # All retry counters grow in the projection. A non-retry boolean is one
    # encoded byte larger; charge the exact codec delta for every projected call.
    calls =
      Enum.reduce(root["tool_batches"], 0, fn {_, b}, n ->
        if is_nil(
             projected["execution"]["progress"]["runtime"]["tool_batches"][
               ToolEvidence.key(b["run_id"], b["request_id"])
             ]["resolution"]
           ), do: n + length(b["resolution"]["calls"]), else: n
      end)

    token = token(s, projected["revision"], closing)

    token_bytes =
      Retention.bytes(token) + calls * (Retention.bytes(false) - Retention.bytes(true))

    with {:ok, %{record: committed}} <-
           Transition.apply(
             control_current,
             {s.config.store.namespace, :agent, s.config.id},
             projected["revision"],
             closing,
             System.system_time(:millisecond)
           ),
         :ok <-
           if(token_bytes <= checkpoint_limit(s),
             do: :ok,
             else: {:error, Retention.error(:checkpoint, token_bytes, checkpoint_limit(s))}
           ),
         :ok <- Retention.check(committed, checkpoint_limit(s), :checkpoint) do
      # Preserve the original cleanup horizon, not the smaller synthetic-final one.
      bytes =
        byte_size(Jason.encode!(committed)) + Record.cleanup_reserve_bytes(projected) +
          calls * (byte_size(Jason.encode!(false)) - byte_size(Jason.encode!(true)))

      if bytes <= Record.max_bytes() do
        {_, batch} =
          Enum.find(projected["execution"]["progress"]["runtime"]["tool_batches"], fn {_, b} ->
            is_nil(b["resolution"])
          end)

        {:ok,
         %{
           run_id: batch["run_id"],
           request_id: batch["request_id"],
           json_room: Record.max_bytes() - bytes,
           term_room:
             min(
               checkpoint_limit(s) - token_bytes,
               checkpoint_limit(s) - Retention.bytes(committed)
             ),
           arguments: argument_sizes(projected, batch["run_id"], batch["request_id"])
         }}
      else
        {:error, :record_limit}
      end
    end
  end

  # The expensive concurrent projection is reserved before Task spawning. During
  # admission only effective argument growth can differ; result/control space is
  # already held. Rebase this margin whenever an outcome changes the record.
  defp reserved_tool_arguments(%{tool_reserve: reserve}, projected, id) when is_map(reserve) do
    payload = projected["execution"]["effects"][id]["intent"]["payload"]

    if payload["run_id"] == reserve.run_id and payload["model_request_id"] == reserve.request_id do
      {json, term} =
        Enum.reduce(
          argument_sizes(projected, reserve.run_id, reserve.request_id),
          {0, 0},
          fn {effect, {j, t}}, {js, ts} ->
            {before_j, before_t} = Map.get(reserve.arguments, effect, {0, 0})
            {js + max(j - before_j, 0), ts + max(t - before_t, 0)}
          end
        )

      cond do
        json > reserve.json_room ->
          {:error, :record_limit}

        term > reserve.term_room ->
          {:error, Retention.error(:checkpoint, term, reserve.term_room)}

        true ->
          :ok
      end
    else
      {:error, :invalid_tool_reservation}
    end
  end

  defp reserved_tool_arguments(_, _, _), do: {:error, :invalid_tool_reservation}

  defp argument_sizes(record, run, request) do
    for {id, effect} <- record["execution"]["effects"],
        effect["intent"]["kind"] == "tool",
        payload = effect["intent"]["payload"],
        payload["run_id"] == run and payload["model_request_id"] == request,
        args = payload["args"] || %{},
        into: %{},
        do:
          {id,
           {byte_size(Jason.encode!(args)) - byte_size(Jason.encode!(%{})),
            Retention.bytes(args) - Retention.bytes(%{})}}
  end

  defp tool_command_capacity(s, operation, payload) do
    if s.record["execution"]["progress"]["runtime"]["frame_version"] in [8, 9] do
      command = command(s.record["record_id"], operation, payload)

      with :ok <-
             Retention.check(
               token(s, s.record["revision"], command),
               checkpoint_limit(s),
               :checkpoint
             ),
           {:ok, %{record: projected}} <-
             Transition.apply(
               s.record,
               {s.config.store.namespace, :agent, s.config.id},
               s.record["revision"],
               command,
               System.system_time(:millisecond)
             ),
           {:ok, reserve} <- reserve_tool_batches(s, projected) do
        {:ok, %{s | tool_reserve: reserve}}
      end
    else
      with :ok <- command_capacity(s, operation, payload), do: {:ok, s}
    end
  end

  defp reserve_legacy_outcome(s, projected, effect_id) do
    usage =
      Usage.qualify(%Usage{
        input_tokens: 0,
        output_tokens: 0,
        details: %{"reservation" => String.duplicate(<<1>>, Retention.usage_bytes())}
      })

    progress = projected["execution"]["progress"]
    frame = reserve_delegations(progress["runtime"], s)

    active_effects =
      Map.reject(projected["execution"]["effects"], fn {id, _} ->
        Retry.retired?(projected["execution"], id)
      end)

    {frame, operations} =
      Enum.reduce(active_effects, {frame, frame["scope"]["operations"]}, fn
        {id, %{"state" => "running", "intent" => %{"kind" => "tool"} = intent}}, {f, ops} ->
          part = %Part.ToolReturn{
            tool_name: intent["payload"]["tool_name"],
            tool_call_id: intent["call_id"],
            status: :validation_error,
            content: nil,
            usage: usage,
            payload_omitted: Retention.marker(:checkpoint, @max_measurement, checkpoint_limit(s))
          }

          op = reserved_tool_usage(f, intent, usage, id)

          {put_part(f, Map.get(intent["payload"], "run_id", f["run_id"]), part), ops ++ [op]}

        _, acc ->
          acc
      end)

    operations = reserve_model_usage(operations, active_effects, frame, usage)
    frame = put_in(frame, ["scope", "operations"], operations)
    frame = reserve_node_copies(frame, usage)
    # Model IO needs room for qualified usage even if its response cannot fit;
    # that case is uncertain rather than replaying a response we did not retain.
    progress =
      progress
      |> Map.put("runtime", frame)
      |> Map.put("outcome_usage_reserve", Usage.to_map(usage))

    snapshot =
      if projected["record_version"] == 2,
        do: projected["snapshot"],
        else: Map.put(projected["snapshot"], "usage", Usage.to_map(usage))

    {snapshot, progress} =
      reserve_model_responses(snapshot, progress, active_effects, usage, s)

    payload =
      Map.merge(
        Map.take(projected["execution"], ~w(owner_id attempt_id fence)),
        %{
          "effect_id" => effect_id,
          "outcome" => %{
            "status" => "validation_error",
            "data" =>
              if(projected["execution"]["effects"][effect_id]["intent"]["kind"] == "tool",
                do: %{
                  "runtime_outcome_version" => 1,
                  "phase" => "raw",
                  "raw_hash" => String.duplicate("f", 64),
                  "result_hash" => String.duplicate("f", 64)
                },
                else: %{
                  "runtime_model_version" => 1,
                  "response_hash" => String.duplicate("f", 64),
                  "model_state_hash" => String.duplicate("f", 64),
                  "state_available" => true
                }
              )
          },
          "snapshot" => snapshot,
          "progress" => progress
        }
      )

    payload =
      if projected["record_version"] == 2 and
           projected["execution"]["effects"][effect_id]["intent"]["kind"] == "model" do
        run_id = projected["execution"]["effects"][effect_id]["intent"]["payload"]["run_id"]
        child = progress["runtime"]["children"][run_id]
        {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])

        Map.put(
          payload,
          "outcome",
          Outcome.model(List.last(messages), child["frame"]["model_data"], false)
        )
      else
        payload
      end

    # Frame5 validates tool bytes against the journal even in this capacity-only
    # projection. Use the concrete reserved parts, not unrelated dummy hashes.
    {projected, payload} =
      if projected["record_version"] == 2 do
        Enum.reduce(active_effects, {projected, payload}, fn
          {id, %{"state" => "running", "intent" => %{"kind" => "tool"} = intent}},
          {record, payload} ->
            node = Frame.node(frame, intent["payload"]["run_id"])

            {:ok, [%Message.Request{parts: [part]}]} =
              Message.from_json(node["outcomes"][intent["call_id"]])

            {:ok, outcome} = Outcome.new(part)

            if id == effect_id do
              {record, Map.put(payload, "outcome", outcome)}
            else
              effect = %{
                record["execution"]["effects"][id]
                | "state" => "confirmed",
                  "outcome" => outcome
              }

              record = put_in(record, ["execution", "effects", id], effect)
              runtime = record["execution"]["progress"]["runtime"]
              runtime = put_part(runtime, intent["payload"]["run_id"], part)
              {put_in(record, ["execution", "progress", "runtime"], runtime), payload}
            end

          _, acc ->
            acc
        end)
      else
        {projected, payload}
      end

    closing = command(projected["record_id"], "outcome", payload)

    with :ok <-
           Retention.check(
             token(s, projected["revision"], closing),
             checkpoint_limit(s),
             :checkpoint
           ),
         {:ok, _} <-
           Transition.apply(
             projected,
             {s.config.store.namespace, :agent, s.config.id},
             projected["revision"],
             closing,
             System.system_time(:millisecond)
           ) do
      :ok
    end
  end

  defp reserved_tool_usage(frame, intent, usage, id) do
    run_id = Map.get(intent["payload"], "run_id", frame["run_id"])
    request = Map.get(intent["payload"], "model_request_id", frame["model_request_id"])

    op = %{
      "id" =>
        if(intent["payload"]["retry_of"],
          do: ["tool", request, intent["call_id"], id],
          else: ["tool", request, intent["call_id"]]
        ),
      "usage" => Usage.to_map(usage),
      "complete" => false
    }

    if Map.has_key?(frame, "children") do
      Map.merge(op, %{
        "run_id" => run_id,
        "terminal_usage" => Usage.to_map(usage),
        "ancestors" => reserve_ancestors(frame["scope"]["nodes"], run_id, Usage.to_map(usage))
      })
    else
      op
    end
  end

  defp reserve_delegations(frame, s) do
    Enum.reduce(Map.get(frame, "children", %{}), frame, fn {id, child}, runtime ->
      if get_in(child, ["link", "kind"]) == "step" do
        # Step completion has no parent tool outcome. Its minimal omission and
        # receipt are covered by the record's existing per-child cleanup reserve.
        runtime
      else
        if child["outcome"] && child["outcome"]["data"]["phase"] == "final" do
          runtime
        else
          marker = Retention.marker(:checkpoint, @max_measurement, checkpoint_limit(s))

          part = %Part.ToolReturn{
            tool_name: child["call"]["tool_name"],
            tool_call_id: child["call"]["call_id"],
            status: :succeeded,
            content: nil,
            payload_omitted: marker
          }

          {:ok, outcome} = Outcome.new(part, "final")

          runtime
          |> put_part(child["parent_run_id"], part)
          |> put_in(["children", id, "result_omitted"], marker)
          |> put_in(["children", id, "parent_result"], Outcome.encode(part))
          |> put_in(["children", id, "outcome"], outcome)
        end
      end
    end)
  end

  defp reserve_model_usage(operations, effects, frame, usage) do
    ids =
      for {_, %{"state" => "running", "intent" => %{"kind" => "model", "call_id" => id}}} <-
            effects,
          into: MapSet.new(),
          do: id

    Enum.map(operations, fn op ->
      case op["id"] do
        ["model", id] ->
          if MapSet.member?(ids, id) do
            if Map.has_key?(frame, "children"),
              do:
                op
                |> Map.put("usage", Usage.to_map(usage))
                |> Map.put("terminal_usage", Usage.to_map(usage))
                |> Map.update!(
                  "ancestors",
                  &Map.new(&1, fn {key, _} -> {key, Usage.to_map(usage)} end)
                ),
              else: Map.put(op, "usage", Usage.to_map(usage))
          else
            op
          end

        _ ->
          op
      end
    end)
  end

  defp reserve_node_copies(%{"children" => _} = frame, usage) do
    children =
      Map.new(frame["children"], fn {id, child} ->
        ops =
          for op <- frame["scope"]["operations"],
              op["run_id"] == id,
              do: %{
                "id" => op["id"],
                "usage" => op["ancestors"][id],
                "complete" => op["complete"]
              }

        child =
          if child["status"] == "completed" do
            child
          else
            child
            |> put_in(["frame", "scope", "operations"], ops)
            |> put_in(["snapshot", "usage"], Usage.to_map(usage))
          end

        {id, child}
      end)

    Map.put(frame, "children", children)
  end

  defp reserve_node_copies(frame, _), do: frame

  defp reserve_model_responses(snapshot, progress, effects, usage, s) do
    Enum.reduce(effects, {snapshot, progress}, fn
      {_, %{"state" => "running", "intent" => %{"kind" => "model", "payload" => intent}}},
      {snapshot, progress} ->
        root? = intent["run_id"] == progress["runtime"]["run_id"]

        saved =
          if root?,
            do: snapshot,
            else: progress["runtime"]["children"][intent["run_id"]]["snapshot"]

        {:ok, messages} = Message.from_json(saved["message_history"])

        omitted = %Message.Response{
          parts: [],
          usage: usage,
          payload_omitted: Retention.marker(:checkpoint, @max_measurement, checkpoint_limit(s))
        }

        saved = Map.put(saved, "message_history", Message.to_json(messages ++ [omitted]))

        if root?,
          do: {saved, progress},
          else:
            {snapshot,
             put_in(progress, ["runtime", "children", intent["run_id"], "snapshot"], saved)}

      _, acc ->
        acc
    end)
  end

  defp reserve_ancestors(_, nil, _), do: %{}

  defp reserve_ancestors(nodes, id, usage),
    do: Map.put(reserve_ancestors(nodes, nodes[id]["parent_run_id"], usage), id, usage)

  defp outcome_capacity(s, payload) do
    command_capacity(s, "outcome", payload)
  end

  defp command_capacity(s, operation, payload) do
    candidate = command(s.record["record_id"], operation, payload)

    with :ok <-
           Retention.check(
             token(s, s.record["revision"], candidate),
             checkpoint_limit(s),
             :checkpoint
           ),
         {:ok, _} <-
           Transition.apply(
             s.record,
             {s.config.store.namespace, :agent, s.config.id},
             s.record["revision"],
             candidate,
             System.system_time(:millisecond)
           ) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp model_without_frame(s, run, reason) do
    # The request returned successfully; retain that fact even if its continuation
    # cannot be represented. Omitted history blocks resume until explicit host
    # data recovery. No template substitution or repeat request is attempted.
    progress = s.record["execution"]["progress"]
    {:ok, scope} = Frame.export_scope(s.scope, progress["runtime"])
    progress = Map.update!(progress, "runtime", &Frame.with_scope(&1, scope))

    saved =
      if run.parent_run_id,
        do: progress["runtime"]["children"][run.run_id]["snapshot"],
        else: s.record["snapshot"]

    {:ok, previous} = Message.from_json(saved["message_history"])
    response = List.last(run.messages)
    omitted = Retention.omit_response(response, checkpoint_limit(s), :checkpoint)
    captured = capture_snapshot(%{run | messages: previous ++ [omitted]}, s)

    {snapshot, progress} =
      if run.parent_run_id,
        do:
          {s.record["snapshot"],
           put_in(progress, ["runtime", "children", run.run_id, "snapshot"], captured)},
        else: {captured, progress}

    payload =
      worker(s, %{
        "effect_id" => effect_id(run, "model", run.model_request_id),
        "outcome" =>
          Outcome.model(omitted, Frame.node(progress["runtime"], run.run_id)["model_data"], false),
        "snapshot" => snapshot,
        "progress" => progress
      })

    {reply, s} = write(s, "outcome", payload)

    {:reply,
     case(reply,
       do: (
         {:ok, _} -> {:error, reason}
         error -> error
       )
     ), s}
  end

  defp checkpoint_limit(s), do: Map.get(s.config, :max_checkpoint_bytes, Record.max_bytes())

  defp token(s, expected, command),
    do: %{
      "token_version" => 1,
      "namespace" => s.config.store.namespace,
      "id" => s.config.id,
      "expected_revision" => if(expected == :absent, do: "absent", else: expected),
      "command" => command
    }

  defp snapshot(run, s) do
    if run.parent_run_id, do: s.record["snapshot"], else: capture_snapshot(run, s)
  end

  defp capture_snapshot(run, s) do
    progress = if s.record, do: s.record["execution"]["progress"], else: %{}

    base =
      case progress["conversation_usage"] do
        nil -> s.config[:snapshot_base_usage]
        data -> Usage.from_map!(data)
      end

    usage =
      case ExecutionScope.snapshot(run.execution_scope) do
        {:ok, totals} -> totals.usage
        _ -> run.usage
      end

    usage = if base && is_nil(run.parent_run_id), do: Usage.add(base, usage), else: usage
    {usage, _} = Retention.usage(usage)

    Snapshot.new(
      agent_id: s.config.id,
      history: run.messages,
      usage: usage,
      revision: Map.get(progress, "snapshot_revision_base", 0) + run.run_step,
      metadata: Map.get(s.config, :snapshot_metadata, %{})
    )
    |> Record.snapshot_data()
  end

  defp worker(s, payload),
    do: Map.merge(Map.take(s.record["execution"], ~w(owner_id attempt_id fence)), payload)

  defp elapsed(s), do: max(System.monotonic_time(:millisecond) - s.started_at, 0)
  defp ok({:ok, _}), do: :ok
  defp ok(error), do: error

  defp effect_id(run, kind, call) do
    {:ok, digest} = Record.digest([run.run_id, run.model_request_id, kind, call])
    kind <> "-" <> digest
  end

  defp id(prefix),
    do: prefix <> "-" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  defp ref(record, config),
    do: %{
      version: 1,
      id: config.id,
      record_id: record["record_id"],
      revision: record["revision"],
      run_id: record["execution"]["run_id"],
      attempt_id: record["execution"]["attempt_id"]
    }
end
