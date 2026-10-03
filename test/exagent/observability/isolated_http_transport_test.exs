Code.require_file("../../../examples/otlp_transport/isolated_exporter.ex", __DIR__)

defmodule ExAgent.Observability.IsolatedHTTPTransportTest do
  use ExUnit.Case, async: false
  require Record
  @fields Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  @scope_keypos Enum.find_index(@fields, &(elem(&1, 0) == :instrumentation_scope)) + 2
  alias OTLPTransportProbe.IsolatedExporter
  alias ExAgent.Test.NativeOTLPReceiver, as: Receiver

  defmodule Processor do
    def on_start(_, span, _), do: span

    def on_end(span, _) do
      send(Process.whereis(:isolated_http_owner), {:native_span, span})
      true
    end

    def force_flush(_), do: :ok
  end

  setup do
    Process.register(self(), :isolated_http_owner)
    old = Application.get_env(:opentelemetry, :processors)
    Application.put_env(:opentelemetry, :processors, [{Processor, %{}}])
    {:ok, started} = Application.ensure_all_started(:opentelemetry)
    assert :opentelemetry in started
    {:ok, receiver} = Receiver.start_link()
    port = Receiver.port(receiver)
    gate = :atomics.new(1, signed: false)

    Application.put_env(:otlp_isolated_probe, :transport, %{
      port: port,
      observer: self(),
      protocol: :http_protobuf,
      http_options: %{
        otlp_traces_endpoint: "http://127.0.0.1:#{port}/v1/traces",
        otlp_traces_headers: [{"x-synthetic", "fixture"}]
      },
      python: System.find_executable("python3"),
      elixir: System.find_executable("elixir"),
      beam_path: Path.expand("_build/test/lib/*/ebin"),
      launcher: Path.expand("examples/otlp_transport/vm_launcher.py"),
      worker: Path.expand("examples/otlp_transport/vm_http_worker.exs"),
      gate: gate
    })

    tracer = :otel_tracer_provider.get_tracer(:exagent, "isolated-http", :undefined)

    {:ok, _} =
      ExAgent.run(
        ExAgent.new(
          model: "test",
          observability: ExAgent.Observability.OpenTelemetry.new(tracer: tracer)
        ),
        "PRIVATE_PROMPT"
      )

    table = :ets.new(__MODULE__, [:duplicate_bag, :public, {:keypos, @scope_keypos}])

    for _ <- 1..2 do
      assert_receive {:native_span, span}
      :ets.insert(table, span)
    end

    resource = :otel_resource.create(%{"service.name" => "isolated-http"})

    on_exit(fn ->
      Application.stop(:opentelemetry)

      if old,
        do: Application.put_env(:opentelemetry, :processors, old),
        else: Application.delete_env(:opentelemetry, :processors)

      Application.delete_env(:otlp_isolated_probe, :transport)
    end)

    %{receiver: receiver, gate: gate, table: table, resource: resource}
  end

  defp export(ctx, timeout \\ 2000) do
    {:ok, config} = IsolatedExporter.init(%{deadline_ms: timeout})
    Task.async(fn -> IsolatedExporter.export(ctx.table, ctx.resource, config) end)
  end

  defp identities do
    assert_receive {:isolated_group, vm}, 2000
    assert_receive {:isolated_port, _, _, _, {:os_pid, launcher}}, 2000
    {vm, launcher}
  end

  defp closed({vm, launcher}, gate) do
    assert_receive {:isolated_receipt, receipt}, 2500
    assert receipt["group_closed"] == true
    refute File.exists?("/proc/#{vm}")
    refute File.exists?("/proc/#{launcher}")
    assert :atomics.get(gate, 1) == 0
    receipt
  end

  @tag timeout: 20_000
  test "stock HTTP callback exports exact native spans and every successful VM is reaped", ctx do
    for _ <- 1..3 do
      task = export(ctx)
      pids = identities()
      receiver = ctx.receiver
      assert_receive {:native_otlp_request, ^receiver, handler, request}, 2000
      assert request.path == "/v1/traces"
      assert request.headers["x-synthetic"] == "fixture"
      # Decode only in the synthetic receiver oracle, using generated stock PB.
      decoded =
        :opentelemetry_exporter_trace_service_pb.decode_msg(
          request.body,
          :export_trace_service_request
        )

      spans = for r <- decoded.resource_spans, s <- r.scope_spans, span <- s.spans, do: span
      assert length(spans) == 2
      assert length(Enum.uniq(Enum.map(spans, & &1.trace_id))) == 1
      refute inspect(decoded) =~ "PRIVATE_PROMPT"
      Receiver.reply(handler, 200)
      assert Task.await(task, 5000) == :ok
      receipt = closed(pids, ctx.gate)
      assert receipt["http_status_success"] == true
      assert receipt["reported_accepted"] == 0 and receipt["unknown"] == 2
    end
  end

  @tag timeout: 10_000
  test "HTTP error and response partial_success retain qualified acceptance semantics", ctx do
    for status <- [503, 200] do
      task = export(ctx)
      pids = identities()
      receiver = ctx.receiver
      assert_receive {:native_otlp_request, ^receiver, handler, _}, 2000
      # Stock HTTP ignores even a partial-success response body. Preserve unknown.
      body =
        :opentelemetry_exporter_trace_service_pb.encode_msg(
          %{partial_success: %{rejected_spans: 1, error_message: "fixture"}},
          :export_trace_service_response
        )

      Receiver.reply(handler, status, body)
      assert Task.await(task, 5000) == if(status == 200, do: :ok, else: :failed_not_retryable)
      receipt = closed(pids, ctx.gate)
      assert receipt["reported_accepted"] == 0 and receipt["unknown"] == 2
    end
  end

  @tag timeout: 10_000
  test "deadline and owner death close an actual held POST, VM and launcher", ctx do
    for mode <- [:deadline, :owner_death] do
      {:ok, config} = IsolatedExporter.init(%{deadline_ms: 1500})
      owner = spawn(fn -> IsolatedExporter.export(ctx.table, ctx.resource, config) end)
      ref = Process.monitor(owner)
      pids = identities()
      receiver = ctx.receiver
      assert_receive {:native_otlp_request, ^receiver, handler, _}, 2000
      if mode == :owner_death, do: Process.exit(owner, :kill)
      assert_receive {:native_otlp_peer_closed, ^handler}, 2500
      receipt = closed(pids, ctx.gate)
      assert receipt["unknown"] == 2
      assert_receive {:DOWN, ^ref, :process, ^owner, _}, 2000
    end
  end
end
