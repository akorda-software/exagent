# Offline, native SDK + a bounded processor + a local in-memory exporter:
#   EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/observability.exs
#   EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/observability.exs --bench
#
# In a host application add :opentelemetry_api (~> 1.5), :opentelemetry (~> 1.7)
# and :opentelemetry_exporter (~> 1.10) to the application's dependencies. In
# runtime.exs configure ONLY the application's chosen processor route:
#
# config :opentelemetry, processors: [
#   {ExAgent.Observability.BoundedProcessor, %{
#     name: :agent_export,
#     exporter: {:opentelemetry_exporter, %{}},
#     max_queue_size: 2048, max_export_batch_size: 256,
#     scheduled_delay_ms: 1000, exporting_timeout_ms: 2000
#   }}
# ]
# config :opentelemetry_exporter,
#   otlp_protocol: :http_protobuf,
#   otlp_traces_endpoint: System.fetch_env!("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"),
#   otlp_headers: [{"authorization", System.fetch_env!("TRACE_AUTHORIZATION")}]
#
# Endpoint/headers/resources, sampler and backend are application decisions.
# No exporter configuration is passed through model settings or dependencies.
# HTTP success is not proof of complete backend ingestion or GenAI UI semantics.
# See docs/guides/observability.md for configuration and limitations.

defmodule ExAgent.ObservabilityExample do
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  alias ExAgent.Observability.{OpenTelemetry, BoundedProcessor}
  alias ExAgent.Message.{Response, Usage, Part}
  alias ExAgent.Models.Test, as: TestModel

  defmodule LocalExporter do
    def init(sink), do: {:ok, sink}

    def export(table, _resource, sink) do
      records = :ets.tab2list(table)

      Agent.update(sink, fn %{count: count, samples: samples} ->
        %{count: count + length(records), samples: Enum.take(samples ++ records, 20)}
      end)

      :ok
    end

    def shutdown(_), do: :ok
  end

  def run do
    {:ok, sink} = Agent.start_link(fn -> %{count: 0, samples: []} end)
    # This script is the host application in a fresh Mix VM. Instrumentation
    # itself does not start/stop/configure any SDK or replace the global tracer.
    previous = Application.get_env(:opentelemetry, :processors)
    Application.put_env(:opentelemetry, :processors, [])
    {:ok, started} = Application.ensure_all_started(:opentelemetry)
    resource = :otel_resource.create(%{"service.name" => "exagent-offline-example"})

    config = %{
      sampler: :always_on,
      id_generator: :otel_id_generator,
      deny_list: [],
      processors: [
        {BoundedProcessor,
         %{
           name: :example_export,
           resource: resource,
           exporter: {LocalExporter, sink},
           max_queue_size: 2048,
           max_export_batch_size: 256,
           scheduled_delay_ms: 10,
           exporting_timeout_ms: 1000
         }}
      ]
    }

    {:ok, provider} = :otel_tracer_provider_sup.start(:exagent_example, resource, config)

    try do
      await(fn -> BoundedProcessor.stats(:example_export).status == :ready end)
      tracer = :otel_tracer_provider.get_tracer(:exagent_example, :exagent, "1", :undefined)
      tracing = OpenTelemetry.new(tracer: tracer)
      child = ExAgent.new(model: %TestModel{label: "specialist result"})

      read =
        ExAgent.Tool.new(
          name: "lookup",
          parameters_json_schema: %{"type" => "object"},
          call: fn _, _ -> "local result" end
        )

      delegate = ExAgent.Coordination.delegation_tool(child)

      agent =
        ExAgent.new(
          name: "example",
          observability: tracing,
          tools: [read, delegate],
          model: %TestModel{
            script: [
              {:tool_calls,
               [
                 %Part.ToolCall{tool_name: "lookup", tool_call_id: "lookup-1", args: %{}},
                 %Part.ToolCall{
                   tool_name: "delegate",
                   tool_call_id: "delegate-1",
                   args: %{"prompt" => "summarize"}
                 }
               ]},
              %Response{
                parts: [%Part.Text{content: "complete"}],
                usage: %Usage{input_tokens: 10, output_tokens: 2, details: %{cached_tokens: 4}}
              }
            ]
          }
        )

      {:ok, server} = ExAgent.Server.start_link(agent: agent, store: :ets)

      {:ok, result} =
        ExAgent.Server.chat(server, "synthetic input",
          estimate_cost: fn usage -> (usage.input_tokens + usage.output_tokens) / 100 end
        )

      GenServer.stop(server)
      BoundedProcessor.force_flush(:example_export)
      await(fn -> Agent.get(sink, & &1.count) >= 9 end)

      IO.inspect(Map.take(result, [:status, :request_count, :tool_calls, :cost_cents]),
        label: "run result (inclusive ledger)"
      )

      samples = Agent.get(sink, & &1.samples)

      IO.inspect(
        Enum.map(samples, fn record ->
          %{
            name: span(record, :name),
            span_id: span(record, :span_id),
            parent_span_id: span(record, :parent_span_id),
            attrs: :otel_attributes.map(span(record, :attributes))
          }
        end),
        label: "redacted metadata-only native spans"
      )

      if "--bench" in System.argv(), do: benchmark(tracing)
      BoundedProcessor.force_flush(:example_export)

      await(fn ->
        stats = BoundedProcessor.stats(:example_export)
        stats.queue_depth == 0 and stats.in_flight == 0
      end)

      IO.inspect(BoundedProcessor.stats(:example_export), label: "bounded export diagnostics")
    after
      :supervisor.terminate_child(:otel_tracer_provider_sup, provider)
      if :opentelemetry in started, do: Application.stop(:opentelemetry)

      if previous == nil,
        do: Application.delete_env(:opentelemetry, :processors),
        else: Application.put_env(:opentelemetry, :processors, previous)

      Agent.stop(sink)
    end
  end

  defp benchmark(tracing) do
    # Reusable definitions are constructed before measurement; each request is
    # deterministic and local. This is instrumentation overhead, not LLM latency.
    for {name, config} <- [{:disabled, nil}, {:enabled, tracing}] do
      agent = ExAgent.new(model: %TestModel{label: "bench"}, observability: config)
      for _ <- 1..50, do: ExAgent.run(agent, "bench")

      samples =
        for _ <- 1..200 do
          {duration, {:ok, _}} = :timer.tc(fn -> ExAgent.run(agent, "bench") end)
          duration
        end

      sorted = Enum.sort(samples)

      IO.inspect(
        %{
          mode: name,
          warmup: 50,
          samples: 200,
          concurrency: 1,
          p50_us: Enum.at(sorted, 99),
          p95_us: Enum.at(sorted, 189)
        },
        label: "offline overhead"
      )
    end
  end

  defp await(fun, remaining \\ 400)
  defp await(_fun, 0), do: raise("local exporter did not reach its barrier")

  defp await(fun, remaining) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(5)
          await(fun, remaining - 1)
        )
  end
end

ExAgent.ObservabilityExample.run()
