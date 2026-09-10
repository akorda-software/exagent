# Finite offline load probe. Run in its OWN VM, not inside a shared application:
#   EXAGENT_OFFLINE=1 MIX_ENV=test mix run test/support/framework_load_probe.exs --json /tmp/framework-load.json
#   EXAGENT_OFFLINE=1 MIX_ENV=test mix run test/support/framework_load_probe.exs --smoke --json /tmp/framework-load-smoke.json
# Mix compiles normally. Only the script's named SDK provider is installed; there
# is no HTTP exporter/socket, real model, persistent service, or global host edit.
# Full preset is fixed BEFORE running: 18 rows, 32 warmups + 200 samples each;
# two finite paced soaks of 200 runs/c8; one 64-run/c8 saturation barrier.
# Percentiles cover run wall time inside fixed-concurrency waves, excluding
# construction, scheduler admission before worker start, and exporter draining.
# Resource sampling includes its own overhead and can miss between-sample peaks.
Code.require_file("../../examples/framework_scenarios.exs", __DIR__)

defmodule ExAgent.FrameworkLoadProbe do
  alias ExAgent.FrameworkScenarios, as: Scenarios
  alias ExAgent.Observability.{BoundedProcessor, OpenTelemetry}
  @processor "framework-load-probe"
  @provider :exagent_framework_load_probe

  defmodule Exporter do
    def init(config), do: {:ok, config}

    def export(table, _resource, config) do
      # Store only scalar counts. Span records live in the processor's bounded
      # batch table; this exporter cannot accidentally grow an unlimited sink.
      if config.gate and :atomics.compare_exchange(config.counter, 3, 0, 1) == :ok do
        send(config.owner, {:export_gate, self(), table})

        receive do
          :release_export -> :ok
        after
          5000 -> raise "finite exporter barrier timed out"
        end
      end

      if config.delay_ms > 0, do: Process.sleep(config.delay_ms)
      :atomics.add(config.counter, 1, :ets.info(table, :size))
      :atomics.add(config.counter, 2, 1)
      :ok
    end

    def shutdown(_), do: :ok
  end

  def run(smoke?) do
    preset = %{
      seed: 131_415,
      concurrency: [1, 8, 32],
      cases: [:simple, :tools, :delegation],
      warmup: if(smoke?, do: 2, else: 32),
      samples: if(smoke?, do: 8, else: 200),
      sample_interval_ms: 5,
      cleanup_deadline_ms: 5000,
      soak_samples: if(smoke?, do: 8, else: 200),
      soak_concurrency: 8,
      soak_tool_delay_ms: 2,
      soak_export_delay_ms: 3,
      soak_wave_pause_ms: 100,
      saturation_runs: if(smoke?, do: 8, else: 64),
      saturation_capacity: 32,
      saturation_batch: 8
    }

    sources = Scenarios.provenance()
    :rand.seed(:exsss, {preset.seed, 13, 15})
    previous = Application.get_env(:opentelemetry, :processors)
    Application.put_env(:opentelemetry, :processors, [])
    {:ok, started} = Application.ensure_all_started(:opentelemetry)

    try do
      # Warm module loading and native provider lifecycle before recorded rows.
      preliminary = start_route(%{delay_ms: 0, capacity: 2048, batch: 256, gate: false})
      :ok = finish_route(preliminary) |> then(fn _ -> :ok end)

      definitions =
        Map.new(preset.cases, fn kind ->
          {elapsed, definition} = :timer.tc(fn -> Scenarios.definition(kind) end)
          {kind, %{definition: definition, construction_us: elapsed}}
        end)

      order =
        for kind <- preset.cases,
            concurrency <- preset.concurrency,
            tracing <- [false, true],
            do: {kind, concurrency, tracing}

      order = Enum.shuffle(order)

      rows =
        Enum.map(order, fn {kind, concurrency, tracing} ->
          definition = definitions[kind].definition
          row(definition, kind, concurrency, tracing, preset, :load)
        end)

      slow = Scenarios.definition(:delegation, delay_ms: preset.soak_tool_delay_ms)

      soaks =
        Enum.map(
          [false, true],
          &row(slow, :delegation, preset.soak_concurrency, &1, preset, :paced_soak)
        )

      saturation = saturation(Scenarios.definition(:delegation), preset)

      report = %{
        version: 1,
        passed: Enum.all?(rows ++ soaks, & &1.passed) and saturation.passed,
        preset: preset,
        smoke: smoke?,
        runtime: runtime(),
        input: Scenarios.input(),
        source_sha256: sources,
        sources_unchanged: sources == Scenarios.provenance(),
        definition_construction_us:
          Map.new(definitions, fn {kind, entry} -> {kind, entry.construction_us} end),
        rows: rows,
        soaks: soaks,
        saturation: saturation,
        n14: %{
          decision: "no production change",
          reason:
            "No measured, demonstrated avoidable hotspot warrants weakening contracts or rewriting the cached-definition path; these timings alone do not identify an algorithmic defect."
        },
        limitations: [
          "Synthetic TestModel latency, not LLM latency or intelligence",
          "Observed sampled maxima, not absolute maxima or SLOs",
          "Closed-loop fixed-concurrency waves, no open-loop arrival queue",
          "5ms resource observer competes with measured work",
          "Short finite paced soak, not long-duration leak proof",
          "SDK/exporter counters acknowledge local callbacks only",
          "Construction measured separately; no CPU-affinity changes",
          "VM-wide resources include Mix, SDK, runtime caches and the observer"
        ]
      }

      %{report | passed: report.passed and report.sources_unchanged}
    after
      if :opentelemetry in started, do: Application.stop(:opentelemetry)

      if previous == nil,
        do: Application.delete_env(:opentelemetry, :processors),
        else: Application.put_env(:opentelemetry, :processors, previous)
    end
  end

  defp row(definition, kind, concurrency, tracing?, preset, phase) do
    config = %{
      delay_ms: if(phase == :paced_soak, do: preset.soak_export_delay_ms, else: 0),
      capacity: 2048,
      batch: 256,
      gate: false
    }

    route = if tracing?, do: start_route(config)
    tracing = if route, do: route.tracing

    try do
      warm = waves(definition, tracing, preset.warmup, concurrency, 0)
      warm_correct = Enum.all?(warm, & &1.correct)
      if route, do: drain(preset.warmup * definition.spans)
      before_stats = stats()
      before_resources = resources()
      observer = start_observer(preset.sample_interval_ms)
      count = if phase == :paced_soak, do: preset.soak_samples, else: preset.samples
      pause = if phase == :paced_soak, do: preset.soak_wave_pause_ms, else: 0
      start = System.monotonic_time(:microsecond)
      samples = waves(definition, tracing, count, concurrency, pause)
      elapsed = System.monotonic_time(:microsecond) - start
      observe_now(observer)
      drain_started = System.monotonic_time(:microsecond)
      if route, do: drain((preset.warmup + count) * definition.spans)
      drain_us = System.monotonic_time(:microsecond) - drain_started
      after_stats = stats()
      observed = stop_observer(observer)
      cleanup = if route, do: finish_route(route), else: cleanup_runs()
      after_resources = resources()

      observed = %{
        observed
        | maxima: merge_maxima([observed.maxima, before_resources, after_resources])
      }

      delta = counter_delta(before_stats, after_stats)
      correct = Enum.count(samples, & &1.correct)

      report = %{
        phase: phase,
        case: kind,
        concurrency: concurrency,
        tracing: tracing?,
        samples: count,
        warmup: preset.warmup,
        correct: correct,
        elapsed_us: elapsed,
        latency_us: percentiles(Enum.map(samples, & &1.us)),
        raw_latency_us: Enum.map(samples, & &1.us),
        throughput_runs_per_second: count * 1_000_000 / max(elapsed, 1),
        ledger_per_run: samples |> hd() |> Map.fetch!(:ledger),
        resources_before: before_resources,
        resources_after: after_resources,
        resources_observed: observed,
        processor_delta: delta,
        drain_us: drain_us,
        cleanup: cleanup,
        passed:
          warm_correct and correct == count and cleanup.passed and
            (not tracing? or
               (delta.accepted + delta.dropped_queue_full == count * definition.spans and
                  delta.exported == delta.accepted and
                  cleanup.local_exported == after_stats.exported and delta.export_failed == 0 and
                  delta.export_timed_out == 0))
      }

      IO.puts(
        :stderr,
        "#{phase} #{kind} c#{concurrency} otel=#{tracing?} p50/p95/p99=#{report.latency_us.p50}/#{report.latency_us.p95}/#{report.latency_us.p99}us correct=#{correct}/#{count}"
      )

      report
    after
      if route && Process.alive?(route.provider), do: finish_route(route)
    end
  end

  defp waves(definition, tracing, count, concurrency, pause) do
    1..count
    |> Enum.chunk_every(concurrency)
    |> Enum.flat_map(fn items ->
      tasks =
        Enum.map(items, fn _ ->
          Task.async(fn ->
            receive do
              :begin_wave -> :ok
            after
              5000 -> raise "wave start barrier timed out"
            end

            {us, outcome} = :timer.tc(fn -> Scenarios.execute(definition, tracing) end)

            %{
              us: us,
              correct: Scenarios.correct?(definition, outcome),
              ledger: outcome_ledger(outcome)
            }
          end)
        end)

      Enum.each(tasks, &send(&1.pid, :begin_wave))
      results = Task.await_many(tasks, 5000)
      if pause > 0, do: Process.sleep(pause)
      results
    end)
  end

  defp outcome_ledger({:ok, result}), do: Scenarios.ledger(result)
  defp outcome_ledger({:error, %ExAgent.RunError{partial: result}}), do: Scenarios.ledger(result)
  defp outcome_ledger(_), do: %{status: :unexpected_result}

  defp saturation(definition, preset) do
    route =
      start_route(%{
        delay_ms: 0,
        capacity: preset.saturation_capacity,
        batch: preset.saturation_batch,
        gate: true
      })

    observer = start_observer(preset.sample_interval_ms)

    try do
      {:ok, _} = Scenarios.execute(Scenarios.definition(:simple), route.tracing)
      :ok = BoundedProcessor.force_flush(@processor)

      {worker, table} =
        receive do
          {:export_gate, worker, table} -> {worker, table}
        after
          2000 -> raise "exporter did not enter finite barrier"
        end

      held_start = System.monotonic_time(:microsecond)
      results = waves(definition, route.tracing, preset.saturation_runs, 8, 0)
      held = stats()
      held_work_us = System.monotonic_time(:microsecond) - held_start
      observe_now(observer)
      batch_size = :ets.info(table, :size)
      send(worker, :release_export)
      drain(2 + preset.saturation_runs * definition.spans)
      final = stats()
      observed = stop_observer(observer)
      cleanup = finish_route(route)

      criteria = %{
        runs_finished_while_export_held: Enum.all?(results, & &1.correct),
        finite_retention:
          held.retained == preset.saturation_capacity and
            held.queue_depth + held.in_flight <= preset.saturation_capacity,
        finite_batch: batch_size > 0 and batch_size <= preset.saturation_batch,
        loss_observed: held.dropped_queue_full > 0,
        complete_local_accounting:
          final.accepted + final.dropped_queue_full ==
            2 + preset.saturation_runs * definition.spans,
        accepted_callbacks_completed: final.exported == final.accepted and final.retained == 0,
        observer_saw_bound:
          observed.maxima.retained <= preset.saturation_capacity and
            observed.maxima.in_flight <= preset.saturation_batch,
        cleanup: cleanup.passed
      }

      %{
        passed: Enum.all?(Map.values(criteria)),
        criteria: criteria,
        held: held,
        final: final,
        batch_size: batch_size,
        runs: preset.saturation_runs,
        held_work_us: held_work_us,
        resources_observed: observed,
        cleanup: cleanup
      }
    after
      if Process.alive?(observer), do: stop_observer(observer)
      if Process.alive?(route.provider), do: finish_route(route)
    end
  end

  defp start_route(config) do
    before_pids = MapSet.new(Process.list())
    before_tables = MapSet.new(:ets.all())
    counter = :atomics.new(3, signed: false)
    resource = :otel_resource.create(%{"service.name" => "exagent-framework-load"})

    opts = %{
      name: @processor,
      resource: resource,
      max_queue_size: config.capacity,
      max_export_batch_size: config.batch,
      scheduled_delay_ms: 5,
      exporting_timeout_ms: 5000,
      shutdown_timeout_ms: 100,
      exporter: {Exporter, Map.merge(config, %{counter: counter, owner: self()})}
    }

    sdk = %{
      sampler: :always_on,
      id_generator: :otel_id_generator,
      deny_list: [],
      processors: [{BoundedProcessor, opts}]
    }

    {:ok, provider} = :otel_tracer_provider_sup.start(@provider, resource, sdk)
    await(fn -> match?(%{status: :ready}, BoundedProcessor.stats(@processor)) end)

    tracer =
      :otel_tracer_provider.get_tracer(@provider, :exagent_framework_probe, "1", :undefined)

    %{
      provider: provider,
      counter: counter,
      tracing: OpenTelemetry.new(tracer: tracer),
      pids: MapSet.difference(MapSet.new(Process.list()), before_pids),
      tables: MapSet.difference(MapSet.new(:ets.all()), before_tables)
    }
  end

  defp finish_route(route) do
    started = System.monotonic_time(:microsecond)
    # Include tables created after exporter init, not just the admission table.
    tables =
      MapSet.union(
        route.tables,
        MapSet.new(
          Enum.filter(:ets.all(), fn table ->
            :ets.info(table, :owner) in route.pids
          end)
        )
      )

    :ok = :supervisor.terminate_child(:otel_tracer_provider_sup, route.provider)

    await(fn ->
      Enum.all?(route.pids, &(not Process.alive?(&1))) and
        Enum.all?(tables, &(:ets.info(&1) == :undefined))
    end)

    runs = cleanup_runs()

    %{
      passed: runs.passed and BoundedProcessor.stats(@processor) == {:error, :unavailable},
      elapsed_us: System.monotonic_time(:microsecond) - started,
      owned_pids: MapSet.size(route.pids),
      owned_tables: MapSet.size(tables),
      surviving_owned_pids: Enum.count(route.pids, &Process.alive?/1),
      surviving_owned_tables: Enum.count(tables, &(:ets.info(&1) != :undefined)),
      task_children: runs.task_children,
      local_exported: :atomics.get(route.counter, 1)
    }
  end

  defp cleanup_runs do
    started = System.monotonic_time(:microsecond)
    await(fn -> Task.Supervisor.children(ExAgent.TaskSupervisor) == [] end)
    children = length(Task.Supervisor.children(ExAgent.TaskSupervisor))

    %{
      passed: children == 0,
      elapsed_us: System.monotonic_time(:microsecond) - started,
      task_children: children
    }
  end

  defp drain(expected) do
    :ok = BoundedProcessor.force_flush(@processor)

    await(fn ->
      s = stats()
      s.accepted + s.dropped_queue_full == expected and s.retained == 0 and s.in_flight == 0
    end)
  end

  defp stats do
    case BoundedProcessor.stats(@processor) do
      %{} = value -> value
      _ -> %{}
    end
  end

  defp counter_delta(before, after_stats) do
    Map.new(
      [:accepted, :dropped_queue_full, :exported, :export_failed, :export_timed_out],
      fn key ->
        {key, Map.get(after_stats, key, 0) - Map.get(before, key, 0)}
      end
    )
  end

  defp percentiles(values) do
    sorted = Enum.sort(values)

    Map.new([{:p50, 0.5}, {:p95, 0.95}, {:p99, 0.99}], fn {key, p} ->
      {key, Enum.at(sorted, ceil(length(sorted) * p) - 1)}
    end)
    |> Map.put(:max, List.last(sorted))
  end

  defp resources do
    pids = Process.list()

    mailbox =
      Enum.map(pids, fn pid ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, value} -> value
          nil -> 0
        end
      end)

    fd_count =
      case File.ls("/proc/self/fd") do
        {:ok, entries} -> length(entries)
        _ -> nil
      end

    s = stats()

    %{
      memory_bytes: :erlang.memory(:total),
      ets_memory_bytes: :erlang.memory(:ets),
      pids: length(pids),
      fds: fd_count,
      ets_tables: length(:ets.all()),
      ports: length(Port.list()),
      mailbox_total: Enum.sum(mailbox),
      mailbox_single_max: Enum.max(mailbox, fn -> 0 end),
      retained: Map.get(s, :retained, 0),
      queue_depth: Map.get(s, :queue_depth, 0),
      in_flight: Map.get(s, :in_flight, 0)
    }
  end

  defp start_observer(interval) do
    spawn_link(fn -> observe(%{maxima: resources(), samples: 1}, interval) end)
  end

  defp observe(state, interval) do
    receive do
      {:sample, owner, ref} ->
        updated = sample(state)
        send(owner, {ref, :ok})
        observe(updated, interval)

      {:stop, owner, ref} ->
        send(owner, {ref, sample(state)})
    after
      interval -> observe(sample(state), interval)
    end
  end

  defp sample(state) do
    maxima = merge_maxima([state.maxima, resources()])

    %{maxima: maxima, samples: state.samples + 1}
  end

  defp merge_maxima([first | rest]) do
    Enum.reduce(rest, first, fn values, acc ->
      Map.merge(acc, values, fn _key, a, b ->
        if is_number(a) and is_number(b), do: max(a, b), else: nil
      end)
    end)
  end

  defp observe_now(observer), do: observer_call(observer, :sample)
  defp stop_observer(observer), do: observer_call(observer, :stop)

  defp observer_call(observer, action) do
    ref = make_ref()
    send(observer, {action, self(), ref})

    receive do
      {^ref, value} -> value
    after
      5000 -> raise "resource observer exceeded finite deadline"
    end
  end

  defp await(fun), do: await(fun, System.monotonic_time(:millisecond) + 5000)

  defp await(fun, deadline) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline,
        do: raise("finite probe barrier timed out; processor=#{inspect(stats())}")

      Process.sleep(2)
      await(fun, deadline)
    end
  end

  defp runtime do
    %{
      elixir: System.version(),
      otp: to_string(:erlang.system_info(:otp_release)),
      erts: to_string(:erlang.system_info(:version)),
      system: to_string(:erlang.system_info(:system_version)),
      schedulers: :erlang.system_info(:schedulers),
      schedulers_online: :erlang.system_info(:schedulers_online),
      logical_processors: :erlang.system_info(:logical_processors_available),
      os_pid: System.pid(),
      scheduler_bind_type: :erlang.system_info(:scheduler_bind_type),
      word_size: :erlang.system_info(:wordsize),
      os: :os.type() |> Tuple.to_list(),
      run_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end

{opts, [], []} = OptionParser.parse(System.argv(), strict: [json: :string, smoke: :boolean])
report = ExAgent.FrameworkLoadProbe.run(Keyword.get(opts, :smoke, false))
encoded = Jason.encode!(report, pretty: true)
if opts[:json], do: File.write!(opts[:json], encoded <> "\n")
IO.puts(encoded)
if not report.passed, do: System.halt(1)
