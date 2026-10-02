defmodule OTLPTransportProbe.Receiver do
  @moduledoc false
  # Only the synthetic receiver registers the upstream private generated decoder.
  # The application-owned exporter never calls its encode/decode API.
  def export(ctx, request) do
    observer = :persistent_term.get({__MODULE__, :observer})
    send(observer, {:grpc_request, self(), request})

    receive do
      {:reply, :error} -> throw({:grpc_error, {"14", "synthetic unavailable"}})
      {:reply, reply} -> {:ok, reply, ctx}
    after
      5_000 -> throw({:grpc_error, {"4", "synthetic deadline"}})
    end
  end
end

defmodule OTLPTransportProbe.ReceiverStats do
  @moduledoc false
  # grpcbox's documented stats handler reports encoded payload sizes separately
  # from Erlang external_size. Capture only scalars, never decoded messages.
  def handle(ctx, _side, event, stats, state) do
    if event in [:in_payload, :out_payload] do
      observer = :persistent_term.get({OTLPTransportProbe.Receiver, :observer})
      send(observer, {:grpc_bytes, event, Map.fetch!(stats, :compressed_size)})
    end

    {ctx, state}
  end
end

defmodule OTLPTransportProbe do
  import ExUnit.Assertions
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))
  alias ExAgent.Observability.BoundedProcessor
  alias OTLPTransportProbe.{GrpcExporter, Receiver, ReceiverStats}

  def run do
    Application.put_env(:opentelemetry, :processors, [])
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:grpcbox)
    :persistent_term.put({Receiver, :observer}, self())
    {:ok, listener} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listener)
    :ok = :gen_tcp.close(listener)

    {:ok, server} =
      :grpcbox.start_server(%{
        grpc_opts: %{
          service_protos: [:opentelemetry_exporter_trace_service_pb],
          services: %{:"opentelemetry.proto.collector.trace.v1.TraceService" => Receiver},
          stats_handler: ReceiverStats
        },
        listen_opts: %{ip: {127, 0, 0, 1}, port: port},
        pool_opts: %{size: 1},
        transport_opts: %{ssl: false}
      })

    Application.put_env(:otlp_transport_probe, :transport, %{port: port, observer: self()})

    # Warm all application/module/connection paths before measuring recurring
    # retention. The synthetic receiver remains alive for every measured cycle.
    success = exercise(:success, 1)
    partial = exercise(:partial, 2)
    warning = exercise(:warning, 3)
    error = exercise(:error, 4)
    timeout = exercise(:timeout, 5)
    killed = exercise(:killed, 6)
    await_quiet()
    # The first services/gauges call itself loads diagnostic paths. Warm those
    # before recording the baseline, without adding transport cycles or relaxing
    # the zero-growth assertions.
    _ = gauges()
    baseline = gauges()

    cycles =
      for index <- 7..9 do
        result = exercise(:success, index)
        await_quiet()
        after_cycle = gauges()
        assert after_cycle.atoms == baseline.atoms
        assert after_cycle.ets == baseline.ets
        assert after_cycle.ports == baseline.ports
        assert after_cycle.processes <= baseline.processes
        assert after_cycle.monitors <= baseline.monitors
        assert after_cycle.httpc_profiles == baseline.httpc_profiles
        Map.put(result, :gauges, after_cycle)
      end

    report = %{
      status: "local_grpc_recipe_only",
      cases: [success, partial, warning, error, timeout, killed],
      baseline: baseline,
      cycles: cycles,
      versions: %{
        elixir: System.version(),
        otp: to_string(:erlang.system_info(:otp_release)),
        sdk: version(:opentelemetry),
        api: version(:opentelemetry_api),
        exporter: version(:opentelemetry_exporter),
        grpcbox: version(:grpcbox)
      },
      limitations: [
        "No ExAgent run, paid model, backend API/UI or cloud acceptance",
        "Official pre-release exporter source; root lock remains 1.10.0",
        "Upstream gRPC decode allocates before local postdecode bounds",
        "Span count/external term byte limits do not bound all wire allocations",
        "Reported remote acceptance is not durable backend receipt"
      ]
    }

    :ok = Supervisor.stop(server, :normal, 2_000)
    :persistent_term.erase({Receiver, :observer})
    File.write!(System.fetch_env!("PROBE_REPORT"), :json.encode(report))
    IO.puts("OTLP_GRPC_PROBE passed: 6 cases and 3 measured cleanup cycles")
  end

  defp exercise(mode, index) do
    exporting_timeout = if mode == :killed, do: 150, else: 1_500
    transport_timeout = if mode == :killed, do: 5_000, else: 250

    {:ok, processor, config} =
      BoundedProcessor.start_link(%{
        name: :otlp_transport_probe,
        resource: resource(),
        exporter: {GrpcExporter, %{timeout_ms: transport_timeout}},
        max_queue_size: 2,
        max_export_batch_size: 2,
        scheduled_delay_ms: 10_000,
        exporting_timeout_ms: exporting_timeout,
        shutdown_timeout_ms: 1_000
      })

    assert wait(fn -> BoundedProcessor.stats(config).status == :ready end)
    assert BoundedProcessor.on_end(native_span(index * 10 + 1), config) == true
    assert BoundedProcessor.on_end(native_span(index * 10 + 2), config) == true
    assert BoundedProcessor.on_end(native_span(index * 10 + 3), config) == :dropped
    :ok = BoundedProcessor.force_flush(config)
    assert_receive {:grpc_bytes, :in_payload, wire_request_bytes}, 2_000
    assert wire_request_bytes in 1..65_536
    assert_receive {:grpc_request, handler, request}, 2_000
    assert_types(request)
    assert_receive {:transport_channel, worker, guard, channel}, 1_000
    owned = [processor, worker, guard, channel]
    refs = Enum.map(owned, &Process.monitor/1)
    handler_ref = Process.monitor(handler)
    started = System.monotonic_time(:millisecond)

    response =
      case mode do
        :partial -> %{partial_success: %{rejected_spans: 1, error_message: "synthetic rejection"}}
        :warning -> %{partial_success: %{rejected_spans: 0, error_message: "synthetic warning"}}
        :error -> :error
        _ -> %{}
      end

    if mode not in [:timeout, :killed], do: send(handler, {:reply, response})

    if mode == :killed do
      assert wait(fn -> BoundedProcessor.stats(config).export_timed_out == 2 end)
      assert wait(fn -> not Process.alive?(guard) and not Process.alive?(channel) end)
      refute_receive {:transport_result, _}, 20
    else
      assert_receive {:transport_result, transport}, 2_000

      case mode do
        :success ->
          assert transport.reported_accepted == 2 and transport.rejected == 0

        :partial ->
          assert transport.reported_accepted == 1 and transport.rejected == 1 and
                   transport.warning == 1

        :warning ->
          assert transport.reported_accepted == 2 and transport.warning == 1

        :error ->
          assert transport.unknown == 2 and transport.failed == 1

        :timeout ->
          assert transport.unknown == 2 and transport.timeout == 1
      end

      expected = if mode in [:success, :warning], do: :exported, else: :export_failed
      assert wait(fn -> Map.fetch!(BoundedProcessor.stats(config), expected) == 2 end)
      Process.put(:transport_result, transport)
    end

    if mode in [:success, :partial, :warning] do
      assert_receive {:grpc_bytes, :out_payload, wire_response_bytes}, 1_000
      assert wire_response_bytes in 0..65_536
      Process.put(:wire_response_bytes, wire_response_bytes)
    end

    stats = BoundedProcessor.stats(config)
    assert stats.accepted == 2 and stats.dropped_queue_full == 1 and stats.retained == 0
    assert wait(fn -> client_sockets() == [] end)
    # Cancelling a client does not terminate arbitrary work at the peer. The
    # synchronous receiver callback deliberately waits for its own fixture
    # release; its late response cannot undo a failed/timed-out local batch.
    if mode in [:timeout, :killed], do: send(handler, {:reply, %{}})
    {:ok, final_stats} = BoundedProcessor.shutdown(config)

    Enum.zip(owned, refs)
    |> Enum.each(fn {pid, ref} ->
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_500
    end)

    assert_receive {:DOWN, ^handler_ref, :process, ^handler, _}, 1_500

    if mode in [:timeout, :killed] do
      receive do
        {:grpc_bytes, :out_payload, 0} -> :ok
      after
        100 -> :ok
      end
    end

    # Aggregate VM gauges below also count sockets/ETS and monitor refs.
    %{
      mode: mode,
      processor: final_stats,
      wire_request_bytes: wire_request_bytes,
      wire_response_bytes: Process.delete(:wire_response_bytes) || :null,
      transport: Process.delete(:transport_result) || :null,
      owned_down: length(owned),
      receiver_released: true,
      cleanup_ms: System.monotonic_time(:millisecond) - started
    }
  end

  defp assert_types(%{resource_spans: [%{resource: resource, scope_spans: [%{spans: spans}]}]}) do
    for exported <- spans do
      attrs = typed(exported)
      assert attrs["test.true"] == {:bool_value, true}
      assert attrs["test.false"] == {:bool_value, false}
      assert attrs["test.string"] == {:string_value, "control"}
      assert attrs["test.int"] == {:int_value, 17}
      assert byte_size(exported.trace_id) == 16 and byte_size(exported.span_id) == 8
    end

    assert typed(resource)["test.synthetic"] == {:bool_value, true}
  end

  defp typed(%{attributes: attrs}),
    do: Map.new(attrs, fn %{key: key, value: %{value: value}} -> {key, value} end)

  defp resource,
    do:
      :otel_resource.create(%{
        "service.name" => "exagent-otlp-grpc-probe",
        "test.synthetic" => true
      })

  defp native_span(id) do
    now = :opentelemetry.timestamp()

    span(
      trace_id: id,
      span_id: id,
      name: "otlp-transport-probe",
      kind: :internal,
      start_time: now,
      end_time: now,
      attributes:
        :otel_attributes.new(
          %{
            "test.true" => true,
            "test.false" => false,
            "test.string" => "control",
            "test.int" => 17
          },
          128,
          128
        ),
      events: :otel_events.new(128, 128, 128),
      links: :otel_links.new([], 128, 128, 128),
      instrumentation_scope:
        :opentelemetry.instrumentation_scope(:exagent, "transport-probe", :undefined)
    )
  end

  defp wait(fun), do: wait(fun, System.monotonic_time(:millisecond) + 2_000)

  defp wait(fun, until) do
    if fun.() do
      true
    else
      if System.monotonic_time(:millisecond) >= until do
        false
      else
        Process.sleep(5)
        wait(fun, until)
      end
    end
  end

  defp gauges do
    pids = Process.list()

    %{
      processes: length(pids),
      ets: length(:ets.all()),
      ports: length(:erlang.ports()),
      atoms: :erlang.system_info(:atom_count),
      monitors:
        Enum.reduce(pids, 0, fn pid, count ->
          case Process.info(pid, :monitors) do
            {:monitors, monitors} -> count + length(monitors)
            _ -> count
          end
        end),
      httpc_profiles: Enum.count(:inets.services(), &(elem(&1, 0) == :httpc))
    }
  end

  defp client_sockets do
    port = Application.fetch_env!(:otlp_transport_probe, :transport).port

    Enum.filter(:erlang.ports(), fn socket ->
      case :inet.peername(socket) do
        {:ok, {{127, 0, 0, 1}, ^port}} -> true
        _ -> false
      end
    end)
  end

  defp await_quiet, do: Process.sleep(50)
  defp version(app), do: Application.spec(app, :vsn) |> to_string()
end

OTLPTransportProbe.run()
