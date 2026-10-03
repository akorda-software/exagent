Code.require_file("native_otlp_receiver.ex")

defmodule OTLPTransportProbe.CollectorProbe do
  import ExUnit.Assertions
  alias ExAgent.Observability.{BoundedProcessor, OpenTelemetry}
  alias ExAgent.Test.NativeOTLPReceiver, as: Receiver
  alias OTLPTransportProbe.IsolatedExporter
  @provider :collector_bridge_provider
  @processor :collector_bridge_processor
  @pb :opentelemetry_exporter_trace_service_pb
  @prompt "PRIVATE_BRIDGE_PROMPT"
  @argument "PRIVATE_BRIDGE_ARGUMENT"
  @output "PRIVATE_BRIDGE_OUTPUT"

  def run do
    Application.put_env(:opentelemetry, :processors, [])
    Application.put_env(:req_llm, :load_dotenv, false)

    for app <- [:inets, :grpcbox, :opentelemetry, :exagent],
        do: assert(match?({:ok, _}, Application.ensure_all_started(app)))

    assert Application.load(:opentelemetry_exporter) in [
             :ok,
             {:error, {:already_loaded, :opentelemetry_exporter}}
           ]

    assert version(:opentelemetry_exporter) == "1.11.0"
    true = Code.ensure_loaded?(:otel_otlp_traces)
    assert function_exported?(:otel_otlp_traces, :to_proto, 2)
    true = Code.ensure_loaded?(:opentelemetry_trace_service)
    assert function_exported?(:opentelemetry_trace_service, :export, 3)

    cases =
      for {mode, index} <-
            Enum.with_index([:success, :partial, :http_error, :http_slow, :collector_stop], 1),
          do: exercise(mode, index)

    _ = gauges()
    Process.sleep(100)
    baseline = gauges()

    cycles =
      for index <- 6..8 do
        result = exercise(:success, index)
        Process.sleep(100)
        after_cycle = gauges()
        assert after_cycle.atoms == baseline.atoms and after_cycle.ets == baseline.ets

        assert after_cycle.ports == baseline.ports and
                 after_cycle.httpc_profiles == baseline.httpc_profiles

        assert after_cycle.processes <= baseline.processes and
                 after_cycle.monitors <= baseline.monitors

        Map.put(result, :gauges, after_cycle)
      end

    report = %{
      status: "synthetic_collector_http_bridge_only",
      cases: cases,
      cycles: cycles,
      baseline: baseline,
      versions: %{
        elixir: System.version(),
        otp: to_string(:erlang.system_info(:otp_release)),
        sdk: version(:opentelemetry),
        api: version(:opentelemetry_api),
        exporter: version(:opentelemetry_exporter),
        grpcbox: version(:grpcbox),
        collector: "0.162.0"
      },
      profile: %{
        span_capacity: 4,
        concurrent_batch_vms: 1,
        retries: 0,
        collector_queue: 0,
        collector_batch_processor: false,
        grpc_receive_limit_bytes: 1_048_576,
        ipc_request_limit_bytes: 65_536,
        http_response_read_limit_bytes: 65_536,
        http_timeout_ms: 500,
        collector_log_limit_bytes: 1_048_576,
        collector_stop_ms: 2_000,
        collector_lifetime_ms: 10_000
      },
      limitations: [
        "No cloud credentials/ingestion or backend API/UI acceptance",
        "Partial rejection is an official unsampled JSON log, not a propagated gRPC partial ACK or rejection metric",
        "Collector sent_spans and callback exported are not durable destination acceptance",
        "Memory limiter/GOMEMLIMIT are not a hard RSS or predecode-allocation promise",
        "Release1.11 keeps the converter/client public API; stock HTTP1.10 remains red",
        "Freeze004 is historical source evidence, not final mutable ROOT"
      ]
    }

    File.write!(System.fetch_env!("PROBE_REPORT"), Jason.encode!(report))
    IO.puts("OTLP_COLLECTOR_PROBE passed: 5 route cases and 3 cleanup cycles")
  end

  defp exercise(mode, index) do
    {:ok, receiver} = Receiver.start_link()
    endpoint = "http://127.0.0.1:#{Receiver.port(receiver)}/synthetic/v1/traces"
    log = Path.join(System.fetch_env!("PROBE_WORK"), "collector-#{index}.jsonl")

    collector =
      Port.open({:spawn_executable, System.fetch_env!("PROBE_PYTHON")}, [
        :binary,
        {:packet, 4},
        :exit_status,
        :use_stdio,
        {:args,
         [
           Path.expand("collector.py"),
           "--run",
           "--binary",
           System.fetch_env!("PROBE_COLLECTOR"),
           "--config",
           Path.expand("collector.yaml"),
           "--log",
           log,
           "--http-endpoint",
           endpoint
         ]}
      ])

    assert_receive {^collector, {:data, ready_bytes}}, 4_000

    assert %{
             "type" => "ready",
             "registered" => true,
             "collector_pid" => collector_pid,
             "grpc_port" => grpc_port,
             "metrics_port" => metrics_port
           } = Jason.decode!(ready_bytes)

    Application.put_env(:otlp_isolated_probe, :transport, %{
      port: grpc_port,
      observer: self(),
      python: System.fetch_env!("PROBE_PYTHON"),
      elixir: System.fetch_env!("PROBE_ELIXIR"),
      beam_path: System.fetch_env!("PROBE_BEAM_PATH"),
      launcher: Path.expand("vm_launcher.py"),
      worker: Path.expand("vm_worker.exs"),
      gate: :atomics.new(1, signed: false)
    })

    resource =
      :otel_resource.create(%{
        "service.name" => "exagent-collector-bridge",
        "test.synthetic" => true,
        "test.false" => false
      })

    config = %{
      name: @processor,
      resource: resource,
      exporter: {IsolatedExporter, %{deadline_ms: 2_000, rpc_deadline_ms: 1_200}},
      max_queue_size: 4,
      max_export_batch_size: 4,
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
    tracer = :otel_tracer_provider.get_tracer(@provider, :exagent, "collector-route", :undefined)
    effects = :atomics.new(2, [])
    assert {:ok, result} = ExAgent.run(agent(OpenTelemetry.new(tracer: tracer), effects), @prompt)

    assert result.output == @output and :atomics.get(effects, 1) == 1 and
             :atomics.get(effects, 2) == 2

    assert BoundedProcessor.stats(@processor).accepted == 4
    :ok = BoundedProcessor.force_flush(@processor)
    assert_receive {:isolated_port, worker, guard, port, {:os_pid, launcher}}, 1_000
    assert_receive {:isolated_lease, lease}, 1_000
    assert_receive {:isolated_group, vm}, 1_000
    refs = Enum.map([worker, guard, lease], &Process.monitor/1)
    assert_receive {:native_otlp_request, ^receiver, handler, request}, 2_000
    assert_native(request, result.run_id)
    assert BoundedProcessor.stats(@processor).exported == 0
    handler_ref = Process.monitor(handler)
    before_stop = if mode == :collector_stop, do: metrics(metrics_port), else: nil

    {status, body, accepted, rejected} =
      case mode do
        :partial ->
          {200,
           @pb.encode_msg(
             %{partial_success: %{rejected_spans: 1, error_message: "synthetic rejection"}},
             :export_trace_service_response
           ), 3, 1}

        :http_error ->
          {503, <<>>, 0, 0}

        :collector_stop ->
          {nil, <<>>, 0, 0}

        _ ->
          {200, <<>>, 4, 0}
      end

    started = System.monotonic_time(:millisecond)
    if mode not in [:http_slow, :collector_stop], do: Receiver.reply(handler, status, body)

    collector_closed =
      if mode == :collector_stop do
        assert Port.command(collector, "STOP\n")
        close_receipt(collector)
      else
        nil
      end

    assert_receive {:isolated_receipt, receipt}, 4_000
    assert receipt["group_closed"] and receipt["request_etf_bytes"] in 1..65_536
    expected = if mode in [:success, :partial], do: :exported, else: :export_failed
    assert wait(fn -> Map.fetch!(BoundedProcessor.stats(@processor), expected) == 4 end)

    if expected == :exported do
      assert receipt["reported_accepted"] == 4 and receipt["rejected"] == 0 and
               receipt["unknown"] == 0
    else
      assert receipt["reported_accepted"] == 0 and receipt["unknown"] == 4
    end

    if mode in [:http_slow, :collector_stop],
      do: assert_receive({:native_otlp_peer_closed, ^handler}, 1_000)

    assert_receive {:DOWN, ^handler_ref, :process, ^handler, _}, 1_000

    current_metrics =
      if mode == :collector_stop,
        do: %{available: false, before_stop: before_stop},
        else: metrics(metrics_port)

    if mode != :collector_stop do
      assert current_metrics["otelcol_exporter_sent_spans"] ==
               if(expected == :exported, do: 4, else: 0)

      assert current_metrics["otelcol_exporter_send_failed_spans"] ==
               if(expected == :exported, do: 0, else: 4)

      assert current_metrics["otelcol_receiver_accepted_spans"] ==
               if(expected == :exported, do: 4, else: 0)

      assert current_metrics["otelcol_receiver_refused_spans"] ==
               if(expected == :exported, do: 0, else: 4)
    end

    # No retry/replay is inferred from config alone: terminal counters and a
    # bounded quiet window verify one HTTP request for each actual native batch.
    :ok = BoundedProcessor.force_flush(@processor)
    refute_receive {:native_otlp_request, ^receiver, _, _}, 150
    {:ok, final} = BoundedProcessor.shutdown(@processor)
    :ok = :supervisor.terminate_child(:otel_tracer_provider_sup, provider)

    Enum.zip([worker, guard, lease], refs)
    |> Enum.each(fn {pid, ref} -> assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000 end)

    assert Port.info(port) == nil and not File.exists?("/proc/#{vm}") and
             not File.exists?("/proc/#{launcher}")

    closed =
      collector_closed ||
        (
          assert Port.command(collector, "STOP\n")
          close_receipt(collector)
        )

    assert closed["group_closed"] and not File.exists?("/proc/#{collector_pid}")
    assert closed["lifetime_ms"] <= 12_000 and closed["log_bytes"] <= 1_048_576
    assert Port.info(collector) == nil
    :ok = Receiver.stop(receiver)
    logs = File.read!(log) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    partial_events =
      for %{"msg" => "Partial success response", "dropped_spans" => n} <- logs,
          do: %{event: "Partial success response", dropped_spans: n}

    assert partial_events ==
             if(mode == :partial,
               do: [%{event: "Partial success response", dropped_spans: 1}],
               else: []
             )

    %{
      mode: mode,
      processor: final,
      collector_ack: receipt,
      collector_metrics: current_metrics,
      collector_partial_events: partial_events,
      collector_lifecycle: closed,
      backend_fixture: %{
        path: request.path,
        seen_spans: 4,
        declared_accepted: accepted,
        rejected: rejected,
        response_status: status,
        response_bytes: byte_size(body),
        response_held: mode in [:http_slow, :collector_stop],
        durable_receipt: false
      },
      wire_request_bytes: byte_size(request.body),
      requests: 1,
      model_calls: 2,
      effects: 1,
      terminal_and_cleanup_ms: System.monotonic_time(:millisecond) - started,
      owned_exporter_processes_down: 3,
      owned_os_leaders_closed: 3
    }
  end

  defp close_receipt(port) do
    assert_receive {^port, {:data, bytes}}, 3_500
    assert %{"type" => "closed"} = receipt = Jason.decode!(bytes)
    assert_receive {^port, {:exit_status, 0}}, 1_000
    receipt
  end

  defp metrics(port) do
    {:ok, {{_, 200, _}, _, body}} =
      :httpc.request(:get, {~c"http://127.0.0.1:#{port}/metrics", []}, [timeout: 1_000],
        body_format: :binary
      )

    assert byte_size(body) <= 1_048_576

    names = [
      "otelcol_exporter_sent_spans",
      "otelcol_exporter_send_failed_spans",
      "otelcol_receiver_accepted_spans",
      "otelcol_receiver_refused_spans",
      "otelcol_process_memory_rss",
      "otelcol_exporter_in_flight_requests"
    ]

    # Public Prometheus scalar diagnostics only; this is not an OTLP parser.
    for name <- names, into: %{} do
      values =
        Regex.scan(Regex.compile!("^" <> name <> "(?:\\{[^\\n]*\\})? ([0-9.eE+-]+)$", "m"), body)
        |> Enum.map(fn [_, value] -> elem(Float.parse(value), 0) end)

      {name, Enum.sum(values)}
    end
  end

  defp agent(tracing, effects) do
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
                 tool_call_id: "bridge-call",
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

  defp assert_native(request, run_id) do
    assert request.method == :POST and request.path == "/synthetic/v1/traces"
    assert request.headers["content-type"] == "application/x-protobuf"
    refute Map.has_key?(request.headers, "content-encoding")
    assert request.headers["user-agent"] =~ "0.162.0"
    for sentinel <- [@prompt, @argument, @output], do: refute(request.body =~ sentinel)

    assert %{resource_spans: [%{resource: resource, scope_spans: [%{spans: spans}]}]} =
             @pb.decode_msg(request.body, :export_trace_service_request)

    assert typed(resource)["test.synthetic"] == {:bool_value, true} and
             typed(resource)["test.false"] == {:bool_value, false}

    assert length(spans) == 4
    by_operation = Enum.group_by(spans, &attributes(&1)["exagent.operation"])
    assert [run] = by_operation["run"]
    assert length(by_operation["model"]) == 2 and length(by_operation["tool"]) == 1
    assert attributes(run)["exagent.run_id"] == run_id

    assert attributes(run)["exagent.usage.request_count"] == 2 and
             attributes(run)["exagent.usage.tool_calls"] == 1

    for span <- spans do
      assert byte_size(span.span_id) == 8 and byte_size(span.trace_id) == 16 and
               span.trace_id == run.trace_id

      if span != run, do: assert(span.parent_span_id == run.span_id)
      refute Enum.any?(Map.keys(attributes(span)), &String.starts_with?(&1, "exagent.content."))
    end
  end

  defp typed(%{attributes: attrs}),
    do: Map.new(attrs, fn %{key: key, value: %{value: value}} -> {key, value} end)

  defp attributes(span), do: Map.new(typed(span), fn {key, {_, value}} -> {key, value} end)
  defp wait(fun), do: wait_until(fun, System.monotonic_time(:millisecond) + 2_000)

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
            {:monitors, monitors} -> acc + length(monitors)
            _ -> acc
          end
        end)
    }
  end

  defp version(app), do: Application.spec(app, :vsn) |> to_string()
end

OTLPTransportProbe.CollectorProbe.run()
