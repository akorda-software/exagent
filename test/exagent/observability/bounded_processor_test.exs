defmodule ExAgent.Observability.BoundedProcessorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  require Record

  alias ExAgent.Observability.BoundedProcessor, as: Processor

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  defmodule Exporter do
    def init(opts) do
      if Map.get(opts, :trap_exit, false), do: Process.flag(:trap_exit, true)
      send(opts.owner, {:bounded_init, self()})

      case Map.get(opts, :init, :ok) do
        :raise -> raise "bounded-secret-init"
        :block -> receive do: (:never -> :ok)
        :ok -> {:ok, opts}
      end
    end

    def export(table, resource, opts) do
      send(opts.owner, {:bounded_export, self(), table, resource, :ets.tab2list(table)})

      receive do
        {:bounded_reply, :raise} -> raise "bounded-secret-export"
        {:bounded_reply, :exit} -> exit(:bounded_secret_export)
        {:bounded_reply, :kill} -> Process.exit(self(), :kill)
        {:bounded_reply, result} -> result
      end
    end

    def shutdown(opts) do
      send(opts.owner, {:bounded_shutdown, self()})

      case Map.get(opts, :shutdown, :ok) do
        :raise -> raise "bounded-secret-shutdown"
        :block -> receive do: (:never -> :ok)
        :ok -> :ok
      end
    end
  end

  defmodule RuntimeCredentialExporter do
    def init(%{} = descriptor) when map_size(descriptor) == 0 do
      state = Application.fetch_env!(:exagent, __MODULE__)
      send(state.owner, {:bounded_runtime_init, self(), state.credential})
      {:ok, state}
    end

    def export(_table, _resource, state) do
      send(state.owner, :bounded_runtime_export)
      {:error, state.credential}
    end

    def shutdown(_state), do: :ok
  end

  setup_all do
    # Bring up only the SDK, with no default network exporter, for the named
    # provider regression below. Restore the test application's prior setting.
    old = Application.get_env(:opentelemetry, :processors)
    Application.put_env(:opentelemetry, :processors, [])
    {:ok, started} = Application.ensure_all_started(:opentelemetry)

    on_exit(fn ->
      if :opentelemetry in started, do: Application.stop(:opentelemetry)

      if old == nil,
        do: Application.delete_env(:opentelemetry, :processors),
        else: Application.put_env(:opentelemetry, :processors, old)
    end)

    :ok
  end

  test "finite admission includes in-flight batch and never queues span messages" do
    {pid, config} = start_processor(max_queue_size: 8, max_export_batch_size: 3)
    Enum.each(1..8, &assert(Processor.on_end(make_span(&1), config) == true))
    assert Processor.force_flush(config) == :ok
    assert_receive {:bounded_export, exporter, table, :test_resource, batch}, 1000
    assert length(batch) == 3
    assert Processor.stats(config).retained == 8
    assert Processor.stats(config).in_flight == 3

    # Suspended admission owner is the mailbox-overflow regression: all 400
    # producers finish using local ETS; none sends the span to the owner.
    :ok = :sys.suspend(pid)

    try do
      tasks =
        for id <- 1..400, do: Task.async(fn -> Processor.on_end(make_span(1000 + id), config) end)

      assert Enum.all?(Task.await_many(tasks, 2000), &(&1 == :dropped))
      assert Processor.stats(config).retained == 8
      assert Processor.stats(config).dropped_queue_full == 400
      {:message_queue_len, messages} = Process.info(pid, :message_queue_len)
      assert messages <= 2
      assert :ets.info(table, :size) == 3
      assert Process.alive?(exporter)

      Enum.each(1..400, fn _ -> assert Processor.force_flush(config) == :ok end)
      {:message_queue_len, after_flush} = Process.info(pid, :message_queue_len)
      assert after_flush <= messages + 1
    after
      :sys.resume(pid)
    end

    send(exporter, {:bounded_reply, :ok})
    assert_receive {:bounded_export, ^exporter, _table, :test_resource, next}, 1000
    assert length(next) == 3
    send(exporter, {:bounded_reply, :success})
    assert_receive {:bounded_export, ^exporter, _table, :test_resource, last}, 1000
    assert length(last) == 2
    send(exporter, {:bounded_reply, :ok})
    assert eventually(fn -> Processor.stats(config).exported == 8 end)
    assert Processor.stats(config).retained == 0
    assert Processor.stats(config).batches_exported == 3
  end

  test "concurrent admission never exceeds capacity even before batching" do
    {pid, config} = start_processor(max_queue_size: 12, max_export_batch_size: 4)
    :ok = :sys.suspend(pid)

    try do
      results =
        1..240
        |> Enum.map(fn id -> Task.async(fn -> Processor.on_end(make_span(id), config) end) end)
        |> Task.await_many(2000)

      assert Enum.count(results, &(&1 == true)) == 12
      assert Enum.count(results, &(&1 == :dropped)) == 228
      assert Processor.stats(config).retained == 12
      assert Processor.stats(config).accepted == 12
      {:message_queue_len, messages} = Process.info(pid, :message_queue_len)
      assert messages <= 1
    after
      :sys.resume(pid)
    end
  end

  test "export errors and exceptions discard exactly one batch and recover without replay" do
    {_pid, config} = start_processor(max_queue_size: 2, max_export_batch_size: 2)

    log =
      capture_log(fn ->
        for {outcome, id} <-
              Enum.with_index([:failed_retryable, :failed_not_retryable, :raise, :exit], 1) do
          assert Processor.on_end(make_span(id), config) == true
          assert Processor.force_flush(config) == :ok
          assert_receive {:bounded_export, exporter, _table, :test_resource, [record]}, 1000
          assert span(record, :span_id) == id
          send(exporter, {:bounded_reply, outcome})
          assert eventually(fn -> Processor.stats(config).export_failed == id end)
          assert Processor.stats(config).retained == 0
        end
      end)

    refute log =~ "bounded-secret"
    refute log =~ "bounded_secret"
    assert Processor.on_end(make_span(99), config) == true
    assert Processor.force_flush(config) == :ok
    assert_receive {:bounded_export, exporter, _table, :test_resource, [record]}, 1000
    assert span(record, :span_id) == 99
    send(exporter, {:bounded_reply, :ok})
    assert eventually(fn -> Processor.stats(config).exported == 1 end)
    assert Processor.stats(config).batches_failed == 4
    refute_receive {:bounded_export, _, _, _, _}, 30
  end

  test "timeout kills the sole exporter, retains capacity until DOWN and recovers" do
    {_pid, config} =
      start_processor(max_queue_size: 2, max_export_batch_size: 1, exporting_timeout_ms: 100)

    assert Processor.on_end(make_span(1), config) == true
    assert Processor.on_end(make_span(2), config) == true
    assert Processor.force_flush(config) == :ok
    assert_receive {:bounded_export, first, table, :test_resource, [_]}, 1000
    monitor = Process.monitor(first)
    assert Processor.on_end(make_span(3), config) == :dropped
    assert_receive {:DOWN, ^monitor, :process, ^first, :killed}, 1000
    assert :ets.info(table) == :undefined
    assert_receive {:bounded_init, second}, 1000
    refute first == second
    refute Process.alive?(first)
    assert_receive {:bounded_export, ^second, _, :test_resource, [remaining]}, 1000
    assert span(remaining, :span_id) in [1, 2]
    send(second, {:bounded_reply, :ok})
    assert eventually(fn -> Processor.stats(config).exported == 1 end)
    assert Processor.stats(config).export_timed_out == 1
    assert Processor.stats(config).batches_timed_out == 1
    assert Processor.stats(config).retained == 0
  end

  test "late completion after deadline cannot change a timed-out batch into success" do
    {pid, config} = start_processor(exporting_timeout_ms: 100)
    assert Processor.on_end(make_span(1), config) == true
    Processor.force_flush(config)
    assert_receive {:bounded_export, worker, _, _, [_]}, 1000
    :ok = :sys.suspend(pid)
    Process.sleep(120)
    send(worker, {:bounded_reply, :ok})
    :ok = :sys.resume(pid)
    assert eventually(fn -> Processor.stats(config).batches_timed_out == 1 end)
    assert Processor.stats(config).exported == 0
    assert Processor.stats(config).retained == 0
  end

  test "initialization failures fail closed without retrying indefinitely or logging secrets" do
    for mode <- [:raise, :block] do
      config =
        options(exporter: {Exporter, %{owner: self(), init: mode}}, exporting_timeout_ms: 60)

      log =
        capture_log(fn ->
          {:ok, pid, handle} = Processor.start_link(config)
          Process.unlink(pid)
          on_exit(fn -> Processor.shutdown(handle) end)
          assert_receive {:bounded_init, worker}, 1000
          assert eventually(fn -> Processor.stats(handle).status == :unavailable end)
          assert Processor.on_end(make_span(1), handle) == :dropped
          assert Processor.stats(handle).retained == 0
          counter = if mode == :raise, do: :init_failed, else: :init_timed_out
          assert Map.fetch!(Processor.stats(handle), counter) == 1
          refute Process.alive?(worker)
          refute_receive {:bounded_init, _}, 100
        end)

      refute log =~ "bounded-secret"
    end
  end

  test "shutdown discards pending and active spans and leaves no worker or table" do
    {pid, config} = start_processor(max_queue_size: 4, max_export_batch_size: 2)
    Enum.each(1..4, &assert(Processor.on_end(make_span(&1), config) == true))
    Processor.force_flush(config)
    assert_receive {:bounded_export, worker, table, _, _}, 1000
    worker_monitor = Process.monitor(worker)
    owner_monitor = Process.monitor(pid)
    assert {:ok, stats} = Processor.shutdown(config)
    assert stats.shutdown_dropped == 4
    assert stats.retained == 0
    assert stats.in_flight == 0
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}, 1000
    assert_receive {:DOWN, ^owner_monitor, :process, ^pid, :normal}, 1000
    assert :ets.info(table) == :undefined
    assert Processor.on_end(make_span(5), config) == :dropped
    assert Processor.stats(config) == {:error, :unavailable}
  end

  test "idle exporter shutdown is bounded and errors are sanitized" do
    for mode <- [:raise, :block] do
      {pid, config} =
        start_processor(
          exporter: {Exporter, %{owner: self(), shutdown: mode}},
          shutdown_timeout_ms: 60
        )

      started = System.monotonic_time(:millisecond)

      log =
        capture_log(fn ->
          assert {:ok, stats} = Processor.shutdown(config)
          counter = if mode == :raise, do: :shutdown_failed, else: :shutdown_timed_out
          assert Map.fetch!(stats, counter) == 1
        end)

      assert System.monotonic_time(:millisecond) - started < 1000
      assert_receive {:bounded_shutdown, worker}, 1000
      assert eventually(fn -> not Process.alive?(worker) end)
      assert eventually(fn -> not Process.alive?(pid) end)
      refute log =~ "bounded-secret"
    end
  end

  test "existing callback config resolves restarted instance without stale ETS references" do
    opts = options()
    {first, old_config} = start_processor(Map.to_list(opts))
    assert Processor.on_end(make_span(1), old_config) == true
    Processor.force_flush(old_config)
    assert_receive {:bounded_export, worker, table, _, _}, 1000
    monitor = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first, :killed}, 1000
    assert eventually(fn -> not Process.alive?(worker) end)
    assert :ets.info(table) == :undefined
    {_second, new_config} = start_processor(Map.to_list(opts))
    assert new_config == old_config
    assert Processor.on_end(make_span(2), old_config) == true
    Processor.force_flush(old_config)
    assert_receive {:bounded_export, next_worker, _, _, [record]}, 1000
    assert span(record, :span_id) == 2
    send(next_worker, {:bounded_reply, :ok})
    assert eventually(fn -> Processor.stats(old_config).exported == 1 end)
    assert Processor.stats(old_config).accepted == 1
  end

  test "owner death kills workers that trap exits during blocked initialization or export" do
    for callback <- [:init, :export] do
      exporter_opts = %{
        owner: self(),
        trap_exit: true,
        init: if(callback == :init, do: :block, else: :ok)
      }

      {:ok, manager, config} = Processor.start_link(options(exporter: {Exporter, exporter_opts}))
      Process.unlink(manager)
      on_exit(fn -> Processor.shutdown(config) end)
      assert_receive {:bounded_init, worker}, 1000
      assert Process.info(worker, :trap_exit) == {:trap_exit, true}

      table =
        if callback == :export do
          assert eventually(fn -> Processor.stats(config).status == :ready end)
          assert Processor.on_end(make_span(1), config) == true
          Processor.force_flush(config)
          assert_receive {:bounded_export, ^worker, table, _, [_]}, 1000
          table
        end

      # The independent guard monitors the worker before any callback begins.
      {:monitored_by, monitors} = Process.info(worker, :monitored_by)
      guards = List.delete(monitors, manager)
      assert guards != []
      worker_monitor = Process.monitor(worker)
      manager_monitor = Process.monitor(manager)

      try do
        Process.exit(manager, :kill)
        assert_receive {:DOWN, ^manager_monitor, :process, ^manager, :killed}, 1000
        assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}, 1000
        assert eventually(fn -> Enum.all?(guards, &(not Process.alive?(&1))) end)
        if table, do: assert(:ets.info(table) == :undefined)
      after
        # A failing regression must not leave the pre-fix orphan in the test VM.
        Process.exit(worker, :kill)
      end
    end
  end

  test "coalesced flush continues through the final in-flight batch and a fresh idle flush" do
    {_pid, config} =
      start_processor(max_queue_size: 4, max_export_batch_size: 1, scheduled_delay_ms: 60_000)

    assert Processor.on_end(make_span(1), config) == true
    Processor.force_flush(config)
    assert_receive {:bounded_export, worker, _, _, [_]}, 1000
    assert Processor.on_end(make_span(2), config) == true
    Processor.force_flush(config)
    send(worker, {:bounded_reply, :ok})
    assert_receive {:bounded_export, ^worker, _, _, [second]}, 1000
    assert span(second, :span_id) == 2
    send(worker, {:bounded_reply, :ok})
    assert eventually(fn -> Processor.stats(config).retained == 0 end)
    assert Processor.on_end(make_span(3), config) == true
    Processor.force_flush(config)
    assert_receive {:bounded_export, ^worker, _, _, [third]}, 1000
    assert span(third, :span_id) == 3
    send(worker, {:bounded_reply, :ok})
    assert eventually(fn -> Processor.stats(config).exported == 3 end)
  end

  test "scalar telemetry has no exporter state and slow handlers do not stall deadlines" do
    owner = self()
    handler = "bounded-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:exagent, :observability, :processor],
        fn _, measurements, metadata, _ ->
          Process.flag(:trap_exit, true)
          send(owner, {:bounded_telemetry, self(), measurements, metadata})
          receive do: (:release_observer -> :ok)
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    {pid, config} = start_processor(scheduled_delay_ms: 10, exporting_timeout_ms: 80)
    assert_receive {:bounded_telemetry, observer, measurements, metadata}, 1000
    assert Enum.all?(Map.values(measurements), &is_number/1)
    assert Map.keys(metadata) == [:status]
    assert Processor.on_end(make_span(1), config) == true
    Processor.force_flush(config)
    assert_receive {:bounded_export, _, _, _, [_]}, 1000
    assert eventually(fn -> Processor.stats(config).export_timed_out == 1 end)
    observer_monitor = Process.monitor(observer)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^observer_monitor, :process, ^observer, :killed}, 1000
  end

  test "native tracer survives processor restart under the SDK supervisor" do
    resource = :otel_resource.create(%{"service.name" => "bounded-sdk-test"})
    opts = options(resource: resource)

    sdk_config = %{
      sampler: :always_on,
      id_generator: :otel_id_generator,
      deny_list: [],
      processors: [{Processor, opts}]
    }

    provider_name = :exagent_bounded_sdk_restart_test
    {:ok, provider} = :otel_tracer_provider_sup.start(provider_name, resource, sdk_config)

    on_exit(fn ->
      :supervisor.terminate_child(:otel_tracer_provider_sup, provider)
    end)

    assert_receive {:bounded_init, _}, 1000
    assert eventually(fn -> Processor.stats(opts).status == :ready end)
    tracer = :otel_tracer_provider.get_tracer(provider_name, :bounded_test, "1", :undefined)
    global = :opentelemetry.get_tracer()
    first_span = :otel_tracer.start_span(%{}, tracer, "before_restart", %{})
    :otel_span.end_span(first_span)
    Processor.force_flush(opts)
    assert_receive {:bounded_export, first_worker, _, ^resource, [before_record]}, 1000
    assert span(before_record, :name) == "before_restart"
    send(first_worker, {:bounded_reply, :ok})
    assert eventually(fn -> Processor.stats(opts).exported == 1 end)

    # Keep both the tracer AND a started span with its on_end closure across
    # the processor-only restart; SDK tracer configuration is not re-created.
    crossing_span = :otel_tracer.start_span(%{}, tracer, "crossing_restart", %{})

    [{:otel_span_processor_sup, processor_sup, _, _} | _] =
      Enum.filter(
        :supervisor.which_children(provider),
        &(elem(&1, 0) == :otel_span_processor_sup)
      )

    [{_, processor, _, _}] = :supervisor.which_children(processor_sup)
    monitor = Process.monitor(processor)
    Process.exit(processor, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^processor, :killed}, 1000
    assert_receive {:bounded_init, second_worker}, 1000
    refute second_worker == first_worker
    assert eventually(fn -> Processor.stats(opts).status == :ready end)
    assert Process.alive?(provider)

    # The exporter may select a batch between these two end_span calls. Hold
    # that first export to make the valid split deterministic, rather than
    # requiring spans finished at different times to share one batch.
    :otel_span.end_span(crossing_span)
    Processor.force_flush(opts)
    assert_receive {:bounded_export, ^second_worker, _, ^resource, [crossing_record]}, 1000
    assert span(crossing_record, :name) == "crossing_restart"

    after_span = :otel_tracer.start_span(%{}, tracer, "after_restart", %{})
    :otel_span.end_span(after_span)
    Processor.force_flush(opts)
    assert Processor.stats(opts).accepted == 2
    send(second_worker, {:bounded_reply, :ok})
    assert_receive {:bounded_export, ^second_worker, _, ^resource, [after_record]}, 1000
    assert span(after_record, :name) == "after_restart"
    refute span(after_record, :span_id) == span(crossing_record, :span_id)
    send(second_worker, {:bounded_reply, :ok})
    assert eventually(fn -> Processor.stats(opts).exported == 2 end)
    assert Processor.stats(opts).accepted == 2
    assert Processor.stats(opts).retained == 0
    assert :opentelemetry.get_tracer() == global
    refute Process.alive?(first_worker)
  end

  test "unsampled and invalid spans are distinguished from queue saturation" do
    {_pid, config} = start_processor(max_queue_size: 1, max_export_batch_size: 1)
    assert Processor.on_start(%{}, :opaque, config) == :opaque
    assert Processor.on_end(span(make_span(1), trace_flags: 0), config) == :dropped
    assert Processor.on_end(:invalid, config) == {:error, :invalid_span}
    assert Processor.stats(config).dropped_unsampled == 1
    assert Processor.stats(config).dropped_invalid == 1
    assert Processor.stats(config).dropped_queue_full == 0
    assert Processor.stats(config).retained == 0
  end

  test "SDK bootstrap descriptors exclude credentials resolved inside exporter initialization" do
    secret = "C6_BOOTSTRAP_RUNTIME_SECRET"
    previous = Application.fetch_env(:exagent, RuntimeCredentialExporter)
    Application.put_env(:exagent, RuntimeCredentialExporter, %{owner: self(), credential: secret})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:exagent, RuntimeCredentialExporter, value)
        :error -> Application.delete_env(:exagent, RuntimeCredentialExporter)
      end
    end)

    resource = :otel_resource.create([])
    opts = options(resource: resource, exporter: {RuntimeCredentialExporter, %{}})

    sdk_config = %{
      sampler: :always_on,
      id_generator: :otel_id_generator,
      deny_list: [],
      processors: [{Processor, opts}]
    }

    provider_name = :exagent_bounded_bootstrap_test
    {:ok, provider} = :otel_tracer_provider_sup.start(provider_name, resource, sdk_config)
    on_exit(fn -> :supervisor.terminate_child(:otel_tracer_provider_sup, provider) end)
    assert_receive {:bounded_runtime_init, _, ^secret}, 1000
    assert eventually(fn -> Processor.stats(opts).status == :ready end)

    [{_, processor_sup, _, _}] =
      Enum.filter(
        :supervisor.which_children(provider),
        &(elem(&1, 0) == :otel_span_processor_sup)
      )

    [{_, processor, _, _}] = :supervisor.which_children(processor_sup)

    # OTP keeps the original child arguments, not the processor's effective
    # callback config. Check the actual retained bootstrap independently of
    # whether this test VM's Logger filters SASL reports before formatting.
    refute inspect(:sys.get_state(provider), limit: :infinity) =~ secret
    refute inspect(:sys.get_state(processor_sup), limit: :infinity) =~ secret

    log =
      capture_log(fn ->
        assert Processor.on_end(make_span(1), opts) == true
        Processor.force_flush(opts)
        assert_receive :bounded_runtime_export, 1000
        assert eventually(fn -> Processor.stats(opts).export_failed == 1 end)
        Process.exit(processor, :kill)
        assert_receive {:bounded_runtime_init, _, ^secret}, 1000
        assert eventually(fn -> Processor.stats(opts).status == :ready end)
        Logger.flush()
      end)

    refute log =~ secret
    refute inspect(:sys.get_state(processor_sup), limit: :infinity) =~ secret
  end

  test "configuration rejects unbounded, inconsistent and misspelled options" do
    for overrides <- [
          %{max_queue_size: :infinity},
          %{max_queue_size: 0},
          %{max_export_batch_size: 100},
          %{exporting_timeout_ms: :infinity},
          %{shutdown_timeout_ms: 5000},
          %{max_queu_size: 10}
        ] do
      assert Processor.start_link(Map.merge(options(), overrides)) == {:error, :invalid_config}
    end
  end

  defp start_processor(overrides) do
    {:ok, pid, config} = Processor.start_link(options(overrides))
    Process.unlink(pid)
    on_exit(fn -> Processor.shutdown(config) end)
    assert_receive {:bounded_init, _worker}, 1000
    assert eventually(fn -> Processor.stats(config).status == :ready end)
    {pid, config}
  end

  defp options(overrides \\ []) do
    Map.merge(
      %{
        name: "bounded-test-#{System.unique_integer([:positive])}",
        exporter: {Exporter, %{owner: self()}},
        resource: :test_resource,
        max_queue_size: 16,
        max_export_batch_size: 4,
        scheduled_delay_ms: 1000,
        exporting_timeout_ms: 5000,
        shutdown_timeout_ms: 200
      },
      Map.new(overrides)
    )
  end

  defp make_span(id) do
    span(trace_id: 1, span_id: id, name: "test", instrumentation_scope: :test_scope)
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end
end
