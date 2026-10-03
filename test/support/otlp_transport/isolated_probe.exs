defmodule OTLPTransportProbe.IsolatedReceiver do
  # Private generated PB registration is confined to this synthetic receiver.
  def export(ctx, request) do
    send(:persistent_term.get({__MODULE__, :observer}), {:isolated_request, self(), request})

    receive do
      {:reply, :error} -> throw({:grpc_error, {"14", "synthetic unavailable"}})
      {:reply, reply} -> {:ok, reply, ctx}
    after
      5_000 -> throw({:grpc_error, {"4", "fixture deadline"}})
    end
  end
end

defmodule OTLPTransportProbe.IsolatedStats do
  def handle(ctx, _, event, stats, state) do
    if event in [:in_payload, :out_payload] do
      send(
        :persistent_term.get({OTLPTransportProbe.IsolatedReceiver, :observer}),
        {:isolated_bytes, event, Map.fetch!(stats, :compressed_size)}
      )
    end

    {ctx, state}
  end
end

defmodule OTLPTransportProbe.IsolatedProbe do
  import ExUnit.Assertions
  alias ExAgent.Observability.{BoundedProcessor, OpenTelemetry}
  alias OTLPTransportProbe.{IsolatedExporter, IsolatedReceiver, IsolatedStats}
  @provider :otlp_isolated_provider
  @processor :otlp_isolated_processor
  @prompt "PRIVATE_SYNTHETIC_PROMPT"
  @argument "PRIVATE_SYNTHETIC_ARGUMENT"
  @output "PRIVATE_SYNTHETIC_OUTPUT"

  def run do
    Application.put_env(:opentelemetry, :processors, [])

    for app <- [:inets, :grpcbox, :opentelemetry, :exagent],
        do: assert(match?({:ok, _}, Application.ensure_all_started(app)))

    :persistent_term.put({IsolatedReceiver, :observer}, self())
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)

    {:ok, server} =
      :grpcbox.start_server(%{
        grpc_opts: %{
          service_protos: [:opentelemetry_exporter_trace_service_pb],
          services: %{:"opentelemetry.proto.collector.trace.v1.TraceService" => IsolatedReceiver},
          stats_handler: IsolatedStats
        },
        listen_opts: %{ip: {127, 0, 0, 1}, port: port},
        pool_opts: %{size: 1},
        transport_opts: %{ssl: false}
      })

    Application.put_env(:otlp_isolated_probe, :transport, %{
      port: port,
      observer: self(),
      python: System.fetch_env!("PROBE_PYTHON"),
      elixir: System.fetch_env!("PROBE_ELIXIR"),
      beam_path: System.fetch_env!("PROBE_BEAM_PATH"),
      launcher: Path.expand("vm_launcher.py"),
      worker: Path.expand("vm_worker.exs"),
      gate: :atomics.new(1, signed: false)
    })

    cases =
      Enum.map(
        [
          :success,
          :partial,
          :error,
          :rpc_timeout,
          :shutdown_block,
          :vm_deadline,
          :worker_timeout,
          :guard_killed
        ],
        &exercise/1
      )

    continuation = continuation()
    _ = gauges()
    Process.sleep(100)
    baseline = gauges()

    cycles =
      for _ <- 1..3 do
        result = exercise(:success)
        Process.sleep(100)
        after_cycle = gauges()
        assert after_cycle.atoms == baseline.atoms
        assert after_cycle.ets == baseline.ets
        assert after_cycle.ports == baseline.ports
        assert after_cycle.processes <= baseline.processes
        assert after_cycle.monitors <= baseline.monitors
        assert after_cycle.httpc_profiles == baseline.httpc_profiles
        Map.put(result, :gauges, after_cycle)
      end

    :ok = Supervisor.stop(server, :normal, 2_000)
    :persistent_term.erase({IsolatedReceiver, :observer})

    report = %{
      status: "exagent_native_loopback_vm_recipe_only",
      cases: cases,
      cycles: cycles,
      baseline: baseline,
      continuation: continuation,
      versions: %{
        elixir: System.version(),
        otp: to_string(:erlang.system_info(:otp_release)),
        sdk: version(:opentelemetry),
        api: version(:opentelemetry_api),
        exporter: version(:opentelemetry_exporter),
        grpcbox: version(:grpcbox),
        exagent_snapshot: version(:exagent)
      },
      limits: %{
        spans_per_batch: 4,
        maximum_admitted_spans: 8,
        ipc_request_bytes: 65_536,
        ipc_receipt_bytes: 4_096,
        concurrent_vms: 1,
        batch_deadline_ms: 2_000,
        attributes_per_span: 64,
        attribute_string_characters: 128,
        events_per_span: 8,
        links_per_span: 4
      },
      limitations: [
        "Synthetic Test model; no provider, SQL, cloud, Collector or backend API/UI acceptance",
        "Official exporter 1.11 pre-release source; ROOT remains intact",
        "Remote reported acceptance is not durable backend receipt",
        "Trusted public converter term IPC, not an OTLP encoder or wire parser",
        "Upstream gRPC decode precedes postdecode checks; no predecode RAM guarantee",
        "Fresh BEAM startup per batch is operational overhead; recipe is not a core default"
      ]
    }

    File.write!(System.fetch_env!("PROBE_REPORT"), Jason.encode!(report))
    IO.puts("OTLP_ISOLATED_PROBE passed: 8 cases and 3 measured ExAgent cleanup cycles")
  end

  defp exercise(mode) do
    fault =
      cond do
        mode == :shutdown_block -> "shutdown_block"
        mode in [:vm_deadline, :worker_timeout, :guard_killed] -> "before_rpc_hold"
        true -> "none"
      end

    deadline =
      cond do
        mode == :vm_deadline -> 650
        mode == :worker_timeout -> 5_000
        mode == :guard_killed -> 650
        true -> 2_000
      end

    processor_timeout = if mode == :worker_timeout, do: 650, else: deadline + 1_700

    resource =
      :otel_resource.create(%{
        "service.name" => "exagent-isolated-probe",
        "test.synthetic" => true,
        "test.false" => false
      })

    config = %{
      name: @processor,
      resource: resource,
      exporter: {IsolatedExporter, %{deadline_ms: deadline, rpc_deadline_ms: 350, fault: fault}},
      max_queue_size: 4,
      max_export_batch_size: 4,
      scheduled_delay_ms: 60_000,
      exporting_timeout_ms: processor_timeout,
      shutdown_timeout_ms: 1_000
    }

    {:ok, provider} =
      :otel_tracer_provider_sup.start(@provider, resource, %{
        sampler: :always_on,
        id_generator: :otel_id_generator,
        deny_list: [],
        processors: [{BoundedProcessor, config}]
      })

    assert wait(fn -> match?(%{status: :ready}, BoundedProcessor.stats(@processor)) end)
    tracer = :otel_tracer_provider.get_tracer(@provider, :exagent, "isolated-probe", :undefined)
    effects = :atomics.new(2, [])
    agent = make_agent(OpenTelemetry.new(tracer: tracer), effects)
    assert {:ok, result} = ExAgent.run(agent, @prompt)
    assert result.output == @output
    assert :atomics.get(effects, 1) == 1 and :atomics.get(effects, 2) == 2
    assert BoundedProcessor.stats(@processor).accepted == 4
    :ok = BoundedProcessor.force_flush(@processor)
    started = System.monotonic_time(:millisecond)
    assert_receive {:isolated_port, worker, guard, port, {:os_pid, launcher_pid}}, 1_000
    assert_receive {:isolated_lease, lease}, 1_000
    assert_receive {:isolated_group, vm_pid}, 1_000
    assert File.exists?("/proc/#{vm_pid}") and File.exists?("/proc/#{launcher_pid}")
    refs = Enum.map([worker, guard, lease], &Process.monitor/1)
    if mode == :worker_timeout, do: assert(:erlang.suspend_process(guard))
    # The application continues running while its previous telemetry batch is
    # retained. Capacity is fixed; these four additional real spans are dropped.
    assert {:ok, _} = ExAgent.run(make_agent(OpenTelemetry.new(tracer: tracer), effects), @prompt)
    assert :atomics.get(effects, 1) == 2 and :atomics.get(effects, 2) == 4
    assert BoundedProcessor.stats(@processor).dropped_queue_full == 4

    handler =
      if mode in [:vm_deadline, :worker_timeout, :guard_killed] do
        nil
      else
        assert_receive {:isolated_bytes, :in_payload, bytes}, 2_000
        assert bytes in 1..65_536
        Process.put(:wire_request_bytes, bytes)
        assert_receive {:isolated_request, handler, request}, 1_000
        assert_native(request, result.run_id)

        if mode != :rpc_timeout do
          send(
            handler,
            {:reply,
             if(mode == :partial,
               do: %{partial_success: %{rejected_spans: 1, error_message: "synthetic rejection"}},
               else: if(mode == :error, do: :error, else: %{})
             )}
          )
        end

        handler
      end

    # Delay the actual reply in timeout mode: the receiver gets an explicit
    # hold command only via this fixture, not from application instrumentation.
    if mode == :guard_killed, do: Process.exit(guard, :kill)

    admission_dropped =
      if mode == :worker_timeout do
        assert wait(fn -> BoundedProcessor.stats(@processor).export_timed_out == 4 end)

        assert {:ok, _} =
                 ExAgent.run(make_agent(OpenTelemetry.new(tracer: tracer), effects), @prompt)

        assert :atomics.get(effects, 1) == 3 and :atomics.get(effects, 2) == 6
        :ok = BoundedProcessor.force_flush(@processor)

        assert_receive {:isolated_receipt,
                        %{"source" => "admission", "dropped" => 4, "sent" => 0}},
                       1_000

        assert wait(fn -> BoundedProcessor.stats(@processor).export_failed == 4 end)
        refute_receive {:isolated_port, _, _, _, _}, 20
        assert :erlang.resume_process(guard)
        4
      else
        0
      end

    transport =
      if mode == :guard_killed do
        assert wait(fn ->
                 not File.exists?("/proc/#{vm_pid}") and not File.exists?("/proc/#{launcher_pid}")
               end)

        nil
      else
        assert_receive {:isolated_receipt, transport}, 7_000
        assert transport["group_closed"] == true
        assert transport["reported_accepted"] + transport["rejected"] + transport["unknown"] == 4
        assert transport["request_etf_bytes"] in 1..65_536
        assert transport["launcher_exit"] == 0
        IO.inspect(%{mode: mode, transport: transport}, label: "isolated_batch_receipt")

        case mode do
          m when m in [:success, :shutdown_block] ->
            assert transport["reported_accepted"] == 4

          :partial ->
            assert transport["reported_accepted"] == 3 and transport["rejected"] == 1

          :error ->
            assert transport["unknown"] == 4

          :rpc_timeout ->
            assert transport["unknown"] == 4 and transport["rpc_timeout"] == true

          :vm_deadline ->
            assert transport["unknown"] == 4 and transport["reason"] == "deadline"

          :worker_timeout ->
            assert transport["unknown"] == 4 and transport["caller_alive"] == false
        end

        if mode == :shutdown_block, do: assert(transport["stop_blocked"] == true)
        transport
      end

    expected =
      cond do
        mode in [:success, :shutdown_block] -> :exported
        mode == :worker_timeout -> :export_timed_out
        true -> :export_failed
      end

    assert wait(fn -> Map.fetch!(BoundedProcessor.stats(@processor), expected) == 4 end, 6_000)
    stats = BoundedProcessor.stats(@processor)

    assert stats.accepted == 4 + admission_dropped and stats.dropped_queue_full == 4 and
             stats.retained == 0

    assert not File.exists?("/proc/#{vm_pid}") and not File.exists?("/proc/#{launcher_pid}")
    assert Port.info(port) == nil
    if handler && mode == :rpc_timeout, do: send(handler, {:reply, %{}})
    {:ok, final} = BoundedProcessor.shutdown(@processor)
    :ok = :supervisor.terminate_child(:otel_tracer_provider_sup, provider)

    Enum.zip([worker, guard, lease], refs)
    |> Enum.each(fn {pid, ref} ->
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
    end)

    response_bytes =
      if handler do
        receive do
          {:isolated_bytes, :out_payload, bytes} -> bytes
        after
          200 -> nil
        end
      else
        nil
      end

    Process.sleep(50)

    %{
      mode: mode,
      processor: final,
      transport: transport,
      wire_request_bytes: Process.delete(:wire_request_bytes),
      wire_response_bytes: response_bytes,
      own_os_processes_closed: 2,
      transport_admission_dropped: admission_dropped,
      worker_guard_and_lease_down: 3,
      batch_and_cleanup_ms: System.monotonic_time(:millisecond) - started
    }
  end

  defp continuation do
    resource =
      :otel_resource.create(%{"service.name" => "exagent-isolated-c7", "test.synthetic" => true})

    config = %{
      name: @processor,
      resource: resource,
      exporter: {IsolatedExporter, %{}},
      max_queue_size: 8,
      max_export_batch_size: 8,
      scheduled_delay_ms: 60_000,
      exporting_timeout_ms: 4_000,
      shutdown_timeout_ms: 1_000
    }

    {:ok, provider} =
      :otel_tracer_provider_sup.start(@provider, resource, %{
        sampler: :always_on,
        id_generator: :otel_id_generator,
        deny_list: [],
        processors: [{BoundedProcessor, config}]
      })

    assert wait(fn -> match?(%{status: :ready}, BoundedProcessor.stats(@processor)) end)
    tracer = :otel_tracer_provider.get_tracer(@provider, :exagent, "isolated-c7", :undefined)
    tracing = OpenTelemetry.new(tracer: tracer)
    {:ok, store_owner} = ExAgent.Store.ETS.start_link(table: :otlp_isolated_c7_store)
    store = ExAgent.Store.scoped({ExAgent.Store.ETS, :otlp_isolated_c7_store}, "isolated-c7")

    options = [
      permissions: ExAgent.Permissions.new!(default: :ask),
      continuation: %{
        store: store,
        id: "conversation",
        durability: :ephemeral,
        expires_at: nil,
        deadline_at: nil,
        lease_ms: 60_000,
        active_time_limit_ms: 30_000,
        definition: %{"id" => "fixture", "version" => "1"},
        policy: %{"id" => "policy", "version" => "1"},
        model_ref: %{"id" => "test-model", "version" => "1"},
        model_codec: %{
          dump: fn m -> {:ok, %{"index" => m.index}} end,
          load: fn m, %{"index" => i} -> {:ok, %{m | index: i}} end
        }
      }
    ]

    effects = :atomics.new(2, [])
    assert {:ok, paused} = ExAgent.run(make_agent(tracing, effects), @prompt, options)
    assert paused.status == :paused and paused.request_count == 1 and paused.tool_calls == 1
    assert :atomics.get(effects, 1) == 0 and :atomics.get(effects, 2) == 1
    first = flush_continuation()
    [first_run] = Enum.filter(first.spans, &(attributes(&1)["exagent.operation"] == "run"))
    assert attributes(first_run)["exagent.status"] == "paused"
    assert attributes(first_run)["exagent.attempt_id"] == paused.attempt_id
    refute attributes(first_run)["error.type"]
    {:ok, %{record: record}} = ExAgent.Continuation.get(store, "conversation")
    [{approval_id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    {:ok, %{record: approved}} =
      ExAgent.Continuation.decide(store, "conversation", :approve,
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "approve",
        approval_id: approval_id,
        payload_hash: approval["payload_hash"],
        actor: "PRIVATE_ACTOR",
        authorize: fn "PRIVATE_ACTOR", :approve, _ -> {:ok, "PRIVATE_AUTHORIZATION"} end
      )

    reference = %{paused.continuation | revision: approved["revision"]}
    # A fresh Test model starts at index zero; only the public model codec
    # restores its persisted cursor. The first request must not be replayed.
    assert {:ok, result} = ExAgent.resume(make_agent(tracing, effects), reference, options)
    assert result.status == :succeeded and result.run_id == paused.run_id
    assert result.attempt_id != paused.attempt_id
    assert result.request_count == 2 and result.tool_calls == 1
    assert :atomics.get(effects, 1) == 1 and :atomics.get(effects, 2) == 2
    second = flush_continuation()
    [second_run] = Enum.filter(second.spans, &(attributes(&1)["exagent.operation"] == "run"))
    assert second_run.span_id != first_run.span_id
    assert attributes(second_run)["exagent.status"] == "succeeded"
    assert attributes(second_run)["exagent.run_id"] == attributes(first_run)["exagent.run_id"]
    assert attributes(second_run)["exagent.attempt_id"] == result.attempt_id

    assert attributes(second_run)["exagent.continuation.record_id"] ==
             attributes(first_run)["exagent.continuation.record_id"]

    assert Enum.count(
             first.spans ++ second.spans,
             &(attributes(&1)["exagent.operation"] == "model")
           ) == 2

    worker_refs =
      [first.worker, second.worker] |> Enum.uniq() |> Enum.map(&{&1, Process.monitor(&1)})

    {:ok, final} = BoundedProcessor.shutdown(@processor)

    for {worker, ref} <- worker_refs do
      assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1_000
    end

    :ok = :supervisor.terminate_child(:otel_tracer_provider_sup, provider)
    :ok = GenServer.stop(store_owner, :normal, 1_000)
    assert :ets.whereis(:otlp_isolated_c7_store) == :undefined

    %{
      storage: "owned_ephemeral_ETS",
      model_codec: "public_callbacks_cursor",
      paused_spans: length(first.spans),
      resumed_spans: length(second.spans),
      model_calls: 2,
      effects: 1,
      distinct_attempts: true,
      stable_run_and_record: true,
      processor: final,
      batches: [Map.drop(first, [:spans, :worker]), Map.drop(second, [:spans, :worker])]
    }
  end

  defp flush_continuation do
    before = BoundedProcessor.stats(@processor).exported
    :ok = BoundedProcessor.force_flush(@processor)
    assert_receive {:isolated_port, worker, guard, port, {:os_pid, launcher}}, 1_000
    assert_receive {:isolated_lease, lease}, 1_000
    assert_receive {:isolated_group, vm}, 1_000
    refs = Enum.map([guard, lease], &Process.monitor/1)
    assert_receive {:isolated_bytes, :in_payload, wire_bytes}, 2_000

    assert_receive {:isolated_request, handler,
                    %{resource_spans: [%{resource: resource, scope_spans: [%{spans: spans}]}]}},
                   1_000

    assert typed(resource)["test.synthetic"] == {:bool_value, true}

    for secret <- [@prompt, @argument, @output, "PRIVATE_ACTOR", "PRIVATE_AUTHORIZATION"],
        do: refute(inspect(spans) =~ secret)

    send(handler, {:reply, %{}})
    assert_receive {:isolated_receipt, receipt}, 3_000
    assert receipt["group_closed"] and receipt["reported_accepted"] == length(spans)
    assert wait(fn -> BoundedProcessor.stats(@processor).exported == before + length(spans) end)

    assert Port.info(port) == nil and not File.exists?("/proc/#{vm}") and
             not File.exists?("/proc/#{launcher}")

    Enum.zip([guard, lease], refs)
    |> Enum.each(fn {pid, ref} ->
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
    end)

    assert_receive {:isolated_bytes, :out_payload, 0}, 1_000

    %{
      spans: spans,
      worker: worker,
      wire_request_bytes: wire_bytes,
      wire_response_bytes: 0,
      transport: receipt
    }
  end

  defp make_agent(tracing, effects) do
    tool =
      ExAgent.Tool.new(
        name: "record_effect",
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"value" => %{"type" => "string"}}
        },
        call: fn _, %{"value" => @argument} ->
          :atomics.add(effects, 1, 1)
          @output
        end
      )

    ExAgent.new(
      observability: tracing,
      tools: [tool],
      model: %ExAgent.Models.Test{
        script: [
          fn _, _ ->
            :atomics.add(effects, 2, 1)

            {:tool_calls,
             [
               %ExAgent.Message.Part.ToolCall{
                 tool_name: "record_effect",
                 tool_call_id: "synthetic-call",
                 args: %{"value" => @argument}
               }
             ]}
          end,
          fn _, _ ->
            :atomics.add(effects, 2, 1)
            @output
          end
        ]
      }
    )
  end

  defp assert_native(
         %{resource_spans: [%{resource: resource, scope_spans: [%{scope: scope, spans: spans}]}]},
         run_id
       ) do
    assert typed(resource)["test.synthetic"] == {:bool_value, true}
    assert typed(resource)["test.false"] == {:bool_value, false}
    assert scope.name == "exagent" and length(spans) == 4
    for secret <- [@prompt, @argument, @output], do: refute(inspect(spans) =~ secret)
    by_operation = Enum.group_by(spans, &attributes(&1)["exagent.operation"])
    assert [run] = by_operation["run"]
    assert length(by_operation["model"]) == 2 and length(by_operation["tool"]) == 1
    assert attributes(run)["exagent.run_id"] == run_id
    assert attributes(run)["exagent.usage.request_count"] == 2
    assert attributes(run)["exagent.usage.tool_calls"] == 1

    for span <- spans do
      assert byte_size(span.span_id) == 8 and byte_size(span.trace_id) == 16
      assert span.trace_id == run.trace_id
      assert attributes(span)["exagent.status"] == "succeeded"
      if span != run, do: assert(span.parent_span_id == run.span_id)
      refute Enum.any?(Map.keys(attributes(span)), &String.starts_with?(&1, "exagent.content."))
    end
  end

  defp typed(%{attributes: attrs}),
    do: Map.new(attrs, fn %{key: key, value: %{value: value}} -> {key, value} end)

  defp attributes(span), do: Map.new(typed(span), fn {key, {_, value}} -> {key, value} end)
  defp wait(fun, ms \\ 2_000), do: wait_until(fun, System.monotonic_time(:millisecond) + ms)

  defp wait_until(fun, until) do
    if fun.(),
      do: true,
      else:
        if(System.monotonic_time(:millisecond) >= until,
          do: false,
          else:
            (
              Process.sleep(5)
              wait_until(fun, until)
            )
        )
  end

  defp gauges do
    pids = Process.list()

    %{
      processes: length(pids),
      ets: length(:ets.all()),
      ports: length(:erlang.ports()),
      atoms: :erlang.system_info(:atom_count),
      httpc_profiles: Enum.count(:inets.services(), &(elem(&1, 0) == :httpc)),
      monitors:
        Enum.reduce(pids, 0, fn pid, acc ->
          case Process.info(pid, :monitors) do
            {:monitors, ms} -> acc + length(ms)
            _ -> acc
          end
        end)
    }
  end

  defp version(app), do: Application.spec(app, :vsn) |> to_string()
end

OTLPTransportProbe.IsolatedProbe.run()
