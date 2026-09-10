defmodule ExAgent.Observability.BoundedProcessor do
  @moduledoc """
  An application-owned, bounded native OpenTelemetry span processor.

      config :opentelemetry,
        processors: [
          {ExAgent.Observability.BoundedProcessor,
           %{name: :agent_export,
             exporter: {:opentelemetry_exporter, %{}},
             max_queue_size: 2048,
             max_export_batch_size: 256,
             scheduled_delay_ms: 1000,
             exporting_timeout_ms: 2000}}
        ]

  The application must include the optional OpenTelemetry SDK when compiling
  this adapter. This module neither starts nor replaces a tracer provider. The
  SDK starts it through the public `:otel_span_processor` extension. Configure
  `:processors`, not both `:processors` and `:span_processor`. SDK `bsp_*` options
  are not automatically applied to custom processors; pass options here.

  Admission uses a finite ETS slot table, **without sending a message per span**.
  Slots stay occupied until export completes or fails, including the one batch
  in flight. At most `max_queue_size` distinct admitted spans are retained. A
  bounded scan may conservatively drop during concurrent slot turnover. Batch
  copies, native serialization and exporter allocations are additional memory;
  this is a count bound, not a byte limit. Configure SDK attribute/event limits
  and bound/redact content before creating spans. Active SDK spans are separate.

  One guarded exporter process owns initialization, export and shutdown. Exports
  and initialization have a monotonic deadline, enforced outside that process.
  A failed batch is discarded, never retried. After an export worker dies it is
  replaced once; failed/timed-out initialization disables admission until the
  processor is restarted. An independent owner monitor kills our worker even
  when an exporter traps exit signals or blocks inside a callback. Killing a
  worker does not guarantee remote rollback
  or cleanup of processes created independently by a custom exporter.

  `force_flush/1` coalesces an asynchronous request to start/drain batches. Its
  `:ok` is **not** an exporter or remote-delivery acknowledgement. Use an exporter
  barrier when testing. `shutdown/1` closes admission and discards remaining
  spans; it does not flush. Exporter shutdown is bounded by
  `shutdown_timeout_ms` (default 1000, maximum 4000). A busy exporter is killed
  rather than concurrently invoking its shutdown callback. Abrupt VM/process
  loss can lose spans and counters. In-flight admission racing shutdown is
  best-effort and may not appear in its final counter snapshot.

  `stats/1` returns cumulative, generation-local counters and a point-in-time
  queue snapshot. Counters are operational diagnostics, not a delivery ledger.
  Every scheduled interval an isolated, single observer emits the same numeric
  measurements on `[:exagent, :observability, :processor]`, with only a fixed
  `:status` metadata value. Slow telemetry handlers cannot block admission or
  export deadlines; they can delay these periodic notifications. No raw errors,
  exporter state, configuration, names or spans are emitted by this processor.
  A native/custom exporter may have its own logging policy.

  **Bootstrap configuration must not contain secrets.** The processor options,
  including `exporter: {module, opts}`, are non-secret bootstrap descriptors:
  SDK/OTP supervisors retain their original start arguments and may log them on
  startup or restart, before this module's status/error projection can act. Use
  `exporter: {:opentelemetry_exporter, %{}}` and configure credentials through the
  exporter's application environment or OS environment. Custom exporters should
  likewise resolve credentials inside `init/1`, rather than accept credentials
  in their supervised start arguments. No general validator can identify all
  arbitrary secrets, and this processor does not intercept application logging.

  The SDK short-circuits later processors when an earlier `on_end` drops. When
  composing independent destinations, the application must choose/test their
  ordering. This processor receives all scopes routed through its provider.
  `resource` may be supplied explicitly; otherwise the SDK resource detector is
  used. Choose stable instance names; name registration is node-qualified and
  never creates atoms from runtime names. Old tracer configurations resolve the
  current instance after a restart, rather than retaining a dead PID/table.
  `shutdown/1` stops one instance, not the SDK child specification: a permanent
  SDK child may restart. To uninstall a route, the app must change its provider's
  supervision/configuration rather than rely on this helper.
  """

  use GenServer

  if Code.ensure_loaded?(:otel_span_processor) do
    @behaviour :otel_span_processor
    @span_fields Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  else
    @span_fields []
  end

  @compile {:no_warn_undefined, [:otel_exporter_traces, :otel_resource_detector]}
  @scope_keypos (Enum.find_index(@span_fields, &(elem(&1, 0) == :instrumentation_scope)) || 0) + 2

  @counter_names [
    :accepted,
    :dropped_queue_full,
    :dropped_unavailable,
    :dropped_unsampled,
    :dropped_invalid,
    :exported,
    :export_failed,
    :export_timed_out,
    :batches_exported,
    :batches_failed,
    :batches_timed_out,
    :init_failed,
    :init_timed_out,
    :shutdown_dropped,
    :shutdown_failed,
    :shutdown_timed_out
  ]
  @indexes @counter_names |> Enum.with_index(1) |> Map.new()
  @in_flight length(@counter_names) + 1
  @accepting @in_flight + 1
  @flush @in_flight + 2
  @phase @in_flight + 4
  @phases %{initializing: 0, ready: 1, exporting: 2, unavailable: 3, closing: 4}
  @event [:exagent, :observability, :processor]
  @doc "Start through the SDK processor extension; returns a stable callback config."
  if @span_fields == [] do
    def start_link(_config), do: {:error, :sdk_unavailable}
  else
    def start_link(config) do
      with true <- Code.ensure_loaded?(:otel_exporter_traces),
           {:ok, config} <- validate(config),
           {:ok, pid} <- GenServer.start_link(__MODULE__, config, name: server(config.name)) do
        {:ok, pid, %{name: config.name}}
      else
        false -> {:error, :sdk_unavailable}
        error -> error
      end
    end
  end

  @doc false
  def on_start(_ctx, span, _config), do: span

  @doc false
  def on_end(span, config) do
    case handle(config) do
      nil -> :dropped
      handle -> admit(span, handle)
    end
  end

  @doc "Request asynchronous draining; success is not an export acknowledgement."
  def force_flush(config) do
    case handle(config) do
      nil ->
        {:error, :no_export_buffer}

      %{counters: counters, pid: pid} ->
        if :atomics.compare_exchange(counters, @flush, 0, 1) == :ok do
          send(pid, :flush)
        end

        :ok
    end
  end

  @doc "Read generation-local counters and queue gauges without calling the processor."
  def stats(config) do
    case handle(config) do
      nil -> {:error, :unavailable}
      handle -> snapshot(handle)
    end
  end

  @doc "Discard pending spans and stop this instance, returning its final snapshot."
  def shutdown(config, timeout \\ 5000) do
    case handle(config) do
      nil ->
        {:error, :unavailable}

      %{pid: pid} ->
        try do
          GenServer.call(pid, :shutdown, timeout)
        catch
          :exit, _ -> {:error, :unavailable}
        end
    end
  end

  def init(config) do
    Process.flag(:trap_exit, true)
    table = :ets.new(__MODULE__, [:set, :public, write_concurrency: true])
    counters = :atomics.new(@phase, signed: false)
    handle = %{table: table, counters: counters, pid: self(), capacity: config.max_queue_size}
    :persistent_term.put(key(config.name), handle)
    owner = self()

    observer =
      spawn_link(fn ->
        guard_owner(owner)
        observe(handle, config.scheduled_delay_ms)
      end)

    state = %{
      config: config,
      handle: handle,
      observer: observer,
      worker: nil,
      monitor: nil,
      timer: nil,
      deadline: nil,
      operation: nil,
      operation_ref: nil,
      pending_failure: nil,
      slots: [],
      cleaned: false
    }

    Process.send_after(self(), :tick, config.scheduled_delay_ms)
    {:ok, start_worker(state)}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, state.config.scheduled_delay_ms)
    {:noreply, maybe_export(state)}
  end

  def handle_info(:flush, state), do: {:noreply, maybe_export(state)}

  def handle_info(
        {:exporter_ready, pid, ref},
        %{worker: pid, operation_ref: ref, operation: :init, pending_failure: nil} = state
      ) do
    if expired?(state) do
      {:noreply, stop_worker(state, :timeout)}
    else
      state = cancel_deadline(state)
      :atomics.put(state.handle.counters, @accepting, 1)
      phase(state, :ready)
      state = %{state | operation: :idle, operation_ref: nil}
      {:noreply, maybe_export(state)}
    end
  end

  def handle_info(
        {:exporter_init_failed, pid, ref},
        %{worker: pid, operation_ref: ref, operation: :init, pending_failure: nil} = state
      ) do
    {:noreply, stop_worker(state, if(expired?(state), do: :timeout, else: :error))}
  end

  def handle_info(
        {:exported, pid, ref, result},
        %{worker: pid, operation_ref: ref, operation: :export, pending_failure: nil} = state
      ) do
    if expired?(state) do
      {:noreply, stop_worker(state, :timeout)}
    else
      state = finish_batch(state, result)
      {:noreply, maybe_continue(state)}
    end
  end

  def handle_info({:deadline, pid, ref}, %{worker: pid, operation_ref: ref} = state) do
    {:noreply, stop_worker(state, :timeout)}
  end

  def handle_info(
        {:DOWN, monitor, :process, pid, _reason},
        %{monitor: monitor, worker: pid} = state
      ) do
    failure = state.pending_failure || :error
    operation = state.operation
    state = cancel_deadline(state)
    state = %{state | worker: nil, monitor: nil, pending_failure: nil}

    case operation do
      :init ->
        increment(state.handle, if(failure == :timeout, do: :init_timed_out, else: :init_failed))
        :atomics.put(state.handle.counters, @accepting, 0)
        discard(state.handle, :dropped_unavailable)
        phase(state, :unavailable)
        {:noreply, %{state | operation: :unavailable, operation_ref: nil}}

      :export ->
        state = finish_batch(state, failure)
        {:noreply, start_worker(state)}

      _ ->
        {:noreply, start_worker(state)}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  def handle_call(:shutdown, _from, state) do
    {stats, state} = cleanup(state)
    {:stop, :normal, {:ok, stats}, state}
  end

  def terminate(_reason, %{cleaned: false} = state) do
    cleanup(state)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  def format_status(%{state: state} = status) do
    Map.put(status, :state, %{operation: state.operation, stats: snapshot(state.handle)})
  end

  if @span_fields == [] do
    defp admit(_span, _handle), do: {:error, :no_export_buffer}
  else
    @span_size length(@span_fields) + 1
    @flags_index Enum.find_index(@span_fields, &(elem(&1, 0) == :trace_flags)) + 1
    @cursor @in_flight + 3

    defp admit(span, handle) do
      cond do
        not valid_span?(span) ->
          increment(handle, :dropped_invalid)
          {:error, :invalid_span}

        Bitwise.band(elem(span, @flags_index), 1) == 0 ->
          increment(handle, :dropped_unsampled)
          :dropped

        :atomics.get(handle.counters, @accepting) == 0 ->
          increment(handle, :dropped_unavailable)
          :dropped

        true ->
          cursor = :atomics.add_get(handle.counters, @cursor, 1)
          insert_slot(handle, span, rem(cursor, handle.capacity), handle.capacity)
      end
    rescue
      ArgumentError ->
        increment(handle, :dropped_unavailable)
        {:error, :no_export_buffer}
    end

    defp valid_span?(span) do
      is_tuple(span) and tuple_size(span) == @span_size and elem(span, 0) == :span and
        is_integer(elem(span, @flags_index))
    end

    defp insert_slot(handle, _span, _slot, 0) do
      increment(handle, :dropped_queue_full)
      :dropped
    end

    defp insert_slot(handle, span, slot, remaining) do
      if :ets.insert_new(handle.table, {slot, span}) do
        increment(handle, :accepted)
        true
      else
        insert_slot(handle, span, rem(slot + 1, handle.capacity), remaining - 1)
      end
    end
  end

  defp maybe_export(%{operation: :idle} = state) do
    case select_batch(state) do
      :"$end_of_table" ->
        :atomics.put(state.handle.counters, @flush, 0)

        # Admission followed by flush can race the empty observation above.
        # Recheck AFTER clearing: an earlier coalesced request has a visible row;
        # a later request sees zero and queues its own bounded wakeup. Never clear
        # the bit after this second observation, which would reopen the race.
        case select_batch(state) do
          :"$end_of_table" ->
            state

          {rows, _continuation} ->
            :atomics.put(state.handle.counters, @flush, 1)
            export_batch(state, rows)
        end

      {rows, _continuation} ->
        export_batch(state, rows)
    end
  end

  defp maybe_export(state), do: state

  defp select_batch(state) do
    :ets.select(
      state.handle.table,
      [{{:"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}],
      state.config.max_export_batch_size
    )
  end

  defp export_batch(state, rows) do
    ref = make_ref()
    send(state.worker, {:export, ref, rows})
    :atomics.put(state.handle.counters, @in_flight, length(rows))
    phase(state, :exporting)

    state
    |> Map.merge(%{operation: :export, operation_ref: ref, slots: Enum.map(rows, &elem(&1, 0))})
    |> set_deadline()
  end

  defp maybe_continue(state) do
    if :atomics.get(state.handle.counters, @flush) == 1 do
      maybe_export(state)
    else
      state
    end
  end

  defp finish_batch(state, result) do
    {spans, batches} =
      case result do
        :ok -> {:exported, :batches_exported}
        :timeout -> {:export_timed_out, :batches_timed_out}
        _ -> {:export_failed, :batches_failed}
      end

    increment(state.handle, spans, length(state.slots))
    increment(state.handle, batches)
    Enum.each(state.slots, &:ets.delete(state.handle.table, &1))
    :atomics.put(state.handle.counters, @in_flight, 0)
    phase(state, :ready)

    state
    |> cancel_deadline()
    |> Map.merge(%{operation: :idle, operation_ref: nil, slots: []})
  end

  defp start_worker(state) do
    :atomics.put(state.handle.counters, @accepting, 0)
    phase(state, :initializing)
    owner = self()
    ref = make_ref()
    config = state.config

    {pid, monitor} =
      :erlang.spawn_opt(fn -> exporter_worker(owner, ref, config) end, [:link, :monitor])

    state
    |> Map.merge(%{worker: pid, monitor: monitor, operation: :init, operation_ref: ref})
    |> set_deadline()
  end

  defp stop_worker(%{pending_failure: nil} = state, failure) do
    Process.exit(state.worker, :kill)
    %{cancel_deadline(state) | pending_failure: failure}
  end

  defp stop_worker(state, _failure), do: state

  defp set_deadline(state) do
    timeout = state.config.exporting_timeout_ms
    timer = Process.send_after(self(), {:deadline, state.worker, state.operation_ref}, timeout)
    %{state | timer: timer, deadline: System.monotonic_time(:millisecond) + timeout}
  end

  defp cancel_deadline(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: nil, deadline: nil}
  end

  defp expired?(state), do: System.monotonic_time(:millisecond) >= state.deadline

  defp exporter_worker(owner, ref, config) do
    guard_owner(owner)

    result =
      try do
        resource = config.resource || :otel_resource_detector.get_resource()
        {module, opts} = config.exporter

        # The generic SDK init helper logs raw exception terms/configuration.
        # Invoke the public exporter behaviour directly, catching only here.
        case module.init(opts) do
          {:ok, exporter_state} -> {:ok, {module, exporter_state}, resource}
          _ -> :error
        end
      catch
        _, _ -> :error
      end

    case result do
      {:ok, exporter, resource} ->
        send(owner, {:exporter_ready, self(), ref})
        export_loop(owner, exporter, resource)

      :error ->
        send(owner, {:exporter_init_failed, self(), ref})
    end
  end

  defp export_loop(owner, exporter, resource) do
    receive do
      {:export, ref, rows} ->
        table = :ets.new(__MODULE__, [:duplicate_bag, {:keypos, @scope_keypos}])

        result =
          try do
            :ets.insert(table, Enum.map(rows, &elem(&1, 1)))

            case :otel_exporter_traces.export(exporter, table, resource) do
              success when success in [:ok, :success] -> :ok
              _ -> :error
            end
          catch
            _, _ -> :error
          after
            :ets.delete(table)
          end

        send(owner, {:exported, self(), ref, result})
        export_loop(owner, exporter, resource)

      {:shutdown, ref} ->
        result =
          try do
            :otel_exporter_traces.shutdown(exporter)
            :ok
          catch
            _, _ -> :error
          end

        send(owner, {:exporter_stopped, self(), ref, result})
    end
  end

  # This process runs no exporter/telemetry callbacks and is intentionally not
  # linked to the owner. A callback may change its worker's trap_exit flag; a
  # monitor in the same blocked worker cannot enforce ownership in that case.
  defp guard_owner(owner) do
    worker = self()

    guard =
      spawn(fn ->
        owner_ref = Process.monitor(owner)
        worker_ref = Process.monitor(worker)
        send(worker, {:owner_guard_ready, self()})

        receive do
          {:DOWN, ^owner_ref, :process, ^owner, _} -> Process.exit(worker, :kill)
          {:DOWN, ^worker_ref, :process, ^worker, _} -> :ok
        end
      end)

    receive do
      {:owner_guard_ready, ^guard} -> :ok
    end
  end

  defp cleanup(state) do
    state = cancel_deadline(state)
    :atomics.put(state.handle.counters, @accepting, 0)
    phase(state, :closing)
    Process.exit(state.observer, :kill)
    discard(state.handle, :shutdown_dropped)
    :atomics.put(state.handle.counters, @in_flight, 0)
    stop_for_shutdown(state)
    stats = snapshot(state.handle)
    :persistent_term.erase(key(state.config.name))
    :ets.delete(state.handle.table)
    {stats, %{state | cleaned: true}}
  end

  defp stop_for_shutdown(%{worker: nil}), do: :ok

  defp stop_for_shutdown(state) do
    pid = state.worker
    monitor = state.monitor
    ref = make_ref()

    if state.operation == :idle do
      send(pid, {:shutdown, ref})
    else
      Process.exit(pid, :kill)
    end

    deadline = System.monotonic_time(:millisecond) + state.config.shutdown_timeout_ms
    wait_for_shutdown(state.handle, pid, monitor, ref, deadline)
  end

  defp wait_for_shutdown(handle, pid, monitor, ref, deadline) do
    receive do
      {:exporter_stopped, ^pid, ^ref, :error} ->
        increment(handle, :shutdown_failed)
        wait_for_shutdown(handle, pid, monitor, ref, deadline)

      {:exporter_stopped, ^pid, ^ref, :ok} ->
        wait_for_shutdown(handle, pid, monitor, ref, deadline)

      {:DOWN, ^monitor, :process, ^pid, _} ->
        :ok
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        increment(handle, :shutdown_timed_out)
        Process.exit(pid, :kill)
    end
  end

  defp discard(handle, counter) do
    count = :ets.select_delete(handle.table, [{{:_, :_}, [], [true]}])
    increment(handle, counter, count)
  end

  defp observe(handle, delay) do
    receive do
    after
      delay ->
        case snapshot(handle) do
          %{status: status} = stats ->
            :telemetry.execute(@event, Map.delete(stats, :status), %{status: status})

          _ ->
            :ok
        end

        observe(handle, delay)
    end
  end

  defp snapshot(handle) do
    case :ets.info(handle.table, :size) do
      :undefined ->
        {:error, :unavailable}

      retained ->
        counters =
          Map.new(@counter_names, &{&1, :atomics.get(handle.counters, Map.fetch!(@indexes, &1))})

        in_flight = :atomics.get(handle.counters, @in_flight)
        phase_code = :atomics.get(handle.counters, @phase)
        {status, _} = Enum.find(@phases, fn {_, code} -> code == phase_code end)

        Map.merge(counters, %{
          status: status,
          retained: retained,
          queue_depth: max(0, retained - in_flight),
          in_flight: in_flight,
          capacity: handle.capacity
        })
    end
  end

  defp increment(handle, counter, count \\ 1),
    do: :atomics.add(handle.counters, Map.fetch!(@indexes, counter), count)

  defp phase(state, phase),
    do: :atomics.put(state.handle.counters, @phase, Map.fetch!(@phases, phase))

  defp key(name), do: {__MODULE__, name}
  defp instance_name(%{name: name}), do: name
  defp instance_name(name), do: name

  defp handle(config) do
    case :persistent_term.get(key(instance_name(config)), nil) do
      %{pid: pid} = handle -> if Process.alive?(pid), do: handle
      _ -> nil
    end
  end

  # Compile out the unavailable start path, rather than hiding a constant false
  # behind a helper that newer compilers can infer. Its private validation code
  # is absent too, avoiding unused-function warnings on older Elixir versions.
  if @span_fields != [] do
    @defaults %{
      name: __MODULE__,
      max_queue_size: 2048,
      max_export_batch_size: 256,
      scheduled_delay_ms: 1000,
      exporting_timeout_ms: 2000,
      shutdown_timeout_ms: 1000,
      resource: nil
    }

    defp server(name), do: {:global, {__MODULE__, node(), name}}

    defp validate(config) when is_map(config) do
      unknown = Map.keys(config) -- (Map.keys(@defaults) ++ [:exporter])
      config = Map.merge(@defaults, config)

      valid =
        unknown == [] and valid_name?(config.name) and
          match?({module, _} when is_atom(module), Map.get(config, :exporter)) and
          integer_between?(config.max_queue_size, 1, 65_536) and
          integer_between?(config.max_export_batch_size, 1, config.max_queue_size) and
          integer_between?(config.scheduled_delay_ms, 1, 60_000) and
          integer_between?(config.exporting_timeout_ms, 1, 60_000) and
          integer_between?(config.shutdown_timeout_ms, 1, 4000)

      if valid, do: {:ok, config}, else: {:error, :invalid_config}
    end

    defp validate(_), do: {:error, :invalid_config}

    defp integer_between?(value, low, high),
      do: is_integer(value) and value >= low and value <= high

    defp valid_name?(name) when is_atom(name), do: true
    defp valid_name?(name) when is_binary(name), do: byte_size(name) in 1..256

    defp valid_name?(name) when is_list(name),
      do: length(name) in 1..256 and :io_lib.printable_list(name)

    defp valid_name?(_), do: false
  end
end
