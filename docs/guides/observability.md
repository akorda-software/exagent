# Optional OpenTelemetry observability

ExAgent instruments operations with native Erlang/Elixir OpenTelemetry.
The application owns its SDK, sampler, resource, processors, exporter and
credentials. A tracing service is optional for the core, Server and Session.

ExAgent is the span producer for its executions. Its optional ReqLLM bridge
adds request metadata to existing model spans and preserves tracing for
standalone ReqLLM calls. Use one bridge to avoid duplicated generations.

## 1. Application setup

Add these dependencies when your application needs native OTLP tracing:

```elixir
{:opentelemetry_api, "~> 1.5.0"},
{:opentelemetry, "~> 1.7.0"},
{:opentelemetry_exporter, "~> 1.11.0"}
```

The SDK/exporter belong to the application. API availability alone is a no-op
tracer without a running SDK. Configure the route before starting the SDK.

This direct HTTP configuration illustrates exporter options. Direct native HTTP
has an exporter lifecycle limitation: timeouts/shutdown can retain HTTP profiles,
atoms or active sockets. For bounded ownership use the
[isolated VM](../development/otlp-isolated-transport.md) or
[Collector](../development/otlp-collector-transport.md) route.

```elixir
import Config

config :opentelemetry,
  processors: [
    {ExAgent.Observability.BoundedProcessor,
     %{
       name: :exagent_export,
       exporter: {:opentelemetry_exporter, %{}},
       max_queue_size: 2048,
       max_export_batch_size: 256,
       scheduled_delay_ms: 1000,
       exporting_timeout_ms: 2000,
       shutdown_timeout_ms: 1000
     }}
  ]

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_traces_endpoint: System.fetch_env!("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
```

These capacities are configuration examples, not latency or throughput guarantees.
Use the full signal-specific traces URL. `otlp_endpoint` appends `/v1/traces`;
`otlp_traces_endpoint` preserves its complete path.

Supply authentication through `OTEL_EXPORTER_OTLP_TRACES_HEADERS`, using
comma-separated `header=value` pairs, or trusted `otlp_traces_headers` configuration.
Set `OTEL_SERVICE_NAME` and resource attributes for your application.

Keep credentials out of `processors:` bootstrap arguments: OTP supervisor
reports can retain and print those arguments. The example's exporter map is
empty so its implementation resolves credentials from its own configuration.
Custom exporters should resolve secrets inside initialization too.

An existing OTel application integrates this route with its current provider;
ExAgent does not replace that provider or install a processor automatically.
The processor sees every recording span routed through the provider.
For a named provider, supply an explicit `tracer:` to
`ExAgent.Observability.OpenTelemetry.new/1` and a matching processor `resource:`.
Avoid configuring both `span_processor:` and `processors:`. SDK 1.7 can
short-circuit later processors when one drops: put dropping processors last
and check your intended fan-out.

## 2. Enable instrumentation

```elixir
alias ExAgent.Observability.OpenTelemetry

tracing = OpenTelemetry.new()
agent = ExAgent.new(model: model, observability: tracing)
{:ok, result} = ExAgent.run(agent, "A request")
```

`model` is your configured application model. Supply `observability:` on a run
or Server/Session when that scope needs instrumentation. Spans cover runs,
model requests, tools, delegation, compaction and checkpoints. Server owns a run
span through its checkpoint; it does not create a conversation-lifetime span
or one span per token. Model spans end before after-request hooks and tool IO.

The default tracer resolves the live provider for each span. If you pass a
`tracer:` handle explicitly, replace it when recreating its provider.

### ReqLLM and one owner for request spans

After SDK configuration, attach the integrated bridge once at application startup:

```elixir
:ok = ExAgent.Observability.ReqLLM.attach()
```

It uses ReqLLM 1.27's public adapter and mapping. During an ExAgent request it
adds bounded request/response IDs, model, server address/port, max tokens,
stream flag and first-chunk time to the existing model span. It does not create
another generation or overwrite ExAgent status, accounting, cost or content.
Standalone ReqLLM calls keep their ordinary spans and child callbacks.

`exagent.req_llm.request_id` identifies the upstream interaction.
`gen_ai.response.time_to_first_chunk` is in seconds. Invalid or unknown values
are omitted. Raw ReqLLM payload capture stays disabled for this adapter even
when enabled globally; ExAgent content uses its own redactor.

Replace a separate `ReqLLM.OpenTelemetry.attach/1,2` with the integrated attach.
A foreign bridge is rejected without detaching it. Observed ReqLLM model calls
fail with `{:observability_conflict, :req_llm_bridge}` before provider IO when
an incompatible bridge is active. Third-party instrumentation and concurrent
handler reconfiguration require application coordination.

### Optional metrics

Add `opentelemetry_api_experimental ~> 0.6.0` and
`opentelemetry_experimental ~> 0.6.0`. Configure that SDK's `:readers` and start it
before enabling measurements:

```elixir
:ok = ExAgent.Observability.ReqLLM.attach(metrics: [models: ["my-fixed-model"]])
```

Provide 1–32 unique model labels; other models map to `"other"`. The instruments
are operation duration, token usage, time to first chunk and time per output
chunk. Durations use seconds and token usage uses `{token}` with normalized
quality. Other dimensions are fixed input/output and error labels. IDs,
endpoints, response model names and content do not become series dimensions.

The application owns views, aggregation, reader/exporter and their lifecycle.
Choose a metric-capable destination separately from Langfuse/Opik trace ingestion.
An absent or stopped metric SDK drops measurements. No instrument cache survives
SDK restart. Normalized zeros do not establish actual zero consumption.

### Tracking maintenance

ReqLLM keeps in-flight tracking entries. A worker dying without a terminal event
can leave one behind. Optionally supervise this child after bridge configuration:

```elixir
{ExAgent.Observability.ReqLLM.Maintenance,
 ttl_ms: 120_000, interval_ms: 30_000}
```

The TTL must exceed every permitted live request, including standalone calls,
streams and retries. Bound indefinite requests before choosing a finite TTL.
Cleanup is age-based, so a shorter TTL can remove active tracking and lose
terminal diagnostics. The worker neither changes deadlines nor starts an SDK.

Read numeric counters with `ExAgent.Observability.ReqLLM.Maintenance.stats/0`.
Applications with an existing maintenance job can call
`ExAgent.Observability.ReqLLM.prune_stale_spans(ttl_ms)` instead.
Pruning removes tracking entries; ExAgent's watcher closes its own span separately.
`detach/0` removes this bridge's handler/entries. Periodic scanning does not impose
a hard bound on upstream table size or request admission.

### Application-owned process boundaries

Capture before dispatch and attach in the receiving process:

```elixir
context = OpenTelemetry.capture_context()

Task.async(fn ->
  OpenTelemetry.with_context(context, fn ->
    ExAgent.run(agent, "Another request")
  end)
end)
```

ExAgent propagates context across its tools, child runs and runtime requests.
Server queues capture at admission; lazy streams capture at enumeration unless
an explicit `trace_context:` is supplied. Handles contain bounded span context
and instrumentation settings, not arbitrary baggage. They are live runtime values,
not snapshot data. Attachment restores the previous trace and owned Logger keys.

### Durable attempts

A confirmed pause closes the attempt span with `exagent.status=paused` and no
OTel error. Resume creates another attempt under the same `run_id` and `record_id`.
Use `attempt_id` to distinguish them. Lifetime request/tool totals are cumulative
snapshots: do not add snapshots across resume or add parent totals to children.

Validated continuation references expose only version, IDs, revision and optional
attempt ID. Actors, decision tokens, stored records and payloads are not exported.

## 3. Privacy before export

Prompts, responses and tool arguments/results are off by default. ExAgent exports
bounded IDs, status and usage rather than live model/dependency configuration,
arbitrary exception messages, stacks or provider bodies.

Opt-in capture requires an explicit redactor:

```elixir
tracing = OpenTelemetry.new(
  content: true,
  redact: fn _field, _value -> {:ok, "[content withheld]"} end,
  max_content_bytes: 4096,
  max_content_input_bytes: 65_536
)
```

A redactor returns `{:ok, safe_utf8_binary}` or `:drop`. Oversized input is dropped
before calling it. Invalid/oversized output or callback failure drops the field
before creating SDK attributes. No unredacted prefix is exported. Keep synchronous
redactors fast; they are trusted callbacks, not sandboxed workers.

Only bounded plain data is admitted. Structs, including Ecto output, and opaque
values are dropped before redaction. Enabling content does not automatically
serialize custom types. Backend masking happens after transport and is not this
privacy boundary. Exporters and their logs have independent privacy contracts.

## 4. Usage and cost

The `exagent.gen_ai.v1` profile uses an explicit subset of
[GenAI conventions](https://github.com/open-telemetry/semantic-conventions-genai/tree/b5d8440f6f126738fd50f927752cd669772c517b).

- `gen_ai.usage.*` describes model requests; `exagent.usage.*` on a run is its
  inclusive subtree aggregate. Summing both counts work twice.
- Input/cache/reasoning dimensions follow declared semantics. Unknown input
  semantics omit the GenAI total and retain the reported value separately.
- ReqLLM numbers retain normalized quality and unknown provider presence, including
  at zero. Missing values remain unavailable; output does not add a reasoning subset.
- Estimated cents reuse execution accounting without another pricing call.
  Availability and known-subtotal fields distinguish complete from partial cost.
- Abort or worker loss cannot reconstruct missing usage. Synthesized Server
  failures mark the retained accounting partial/unknown instead of claiming a total.

Sampled or lossy spans are not a durable billing ledger. Host request/tool counts
measure admissions rather than completed effects; invoice data belongs to the
application/provider integration.

## 5. Bounded export and diagnostics

`BoundedProcessor` has finite queued-plus-in-flight slots, a bounded batch and one
export worker. The run does not wait for its network IO. Saturation drops rather
than accumulating indefinitely. Slot count is not a byte bound on arbitrary
application attributes or exporter allocations. Ordering is not guaranteed FIFO.

An exporter failure/timeout drops the batch without implicit retry.
`max_exporter_restarts: n` limits replacements per processor instance;
`:infinity` is the default. Zero permits the initial worker only. Exhaustion
keeps the processor alive as `:unavailable`, discards queued spans and drops
admission. Application restart resets the budget; it does not repair HTTP cleanup.

`BoundedProcessor.stats(:exagent_export)` exposes local scalar counters.
`accepted` counts enqueue admission and `exported` counts successful callbacks.
Neither guarantees durable destination ingestion. Stock HTTP can ignore
`partial_success`; query the destination and consume loss diagnostics separately.

`force_flush/1` requests asynchronous export; it is not a delivery acknowledgement.
`shutdown/1` returns final stats after discarding pending/in-flight work and bounded
cleanup; it does not drain. Flush and wait for an application-defined barrier when
needed, then remove the route through the application's SDK/supervision lifecycle.
Counters reset on restart. Slow custom processors, samplers or callbacks can
still block their own callers.

## 6. Send traces to Langfuse or Opik

Use OTLP HTTP/protobuf and your deployment's full traces endpoint. Keep
credentials in exporter configuration and out of spans or bootstrap arguments.

| Destination | Cloud traces endpoint | Authentication headers |
|---|---|---|
| Langfuse EU | `https://cloud.langfuse.com/api/public/otel/v1/traces` | `Authorization=Basic <base64(public_key:secret_key)>`, `x-langfuse-ingestion-version=4` |
| Opik | `https://www.comet.com/opik/api/v1/private/otel/v1/traces` | `Authorization=<api-key>`, `projectName=<project>`, `Comet-Workspace=<workspace>` |

Use your region or self-hosted URL when applicable. The header names and endpoint
requirements come from [Langfuse OTLP](https://langfuse.com/integrations/native/opentelemetry)
and [Opik OTLP](https://www.comet.com/docs/opik/integrations/opentelemetry).
These are traces endpoints; configure a separate destination for metrics.

### Opik attribute presentation

Opik places unrecognized attributes in input and does not display resource
attributes as ordinary span metadata. To preserve diagnostics in metadata while
leaving content disabled, apply an application-owned projection of the public
OTLP map. This example preserves scalar types, identities, status and timestamps:

```elixir
defmodule MyApp.OpikProjection do
  @model_keys ~w(gen_ai.operation.name gen_ai.provider.name gen_ai.request.model
                 gen_ai.usage.input_tokens gen_ai.usage.output_tokens)

  def project(%{resource_spans: resources} = request) do
    resources = for resource <- resources do
      scopes = for scope <- resource.scope_spans do
        spans = for span <- scope.spans do
          native = span.attributes
          diagnostic = Enum.map(native, &prefix(&1, "opik.metadata."))
          resource_metadata = Enum.map(resource.resource.attributes,
            &prefix(&1, "opik.metadata.resource."))

          model = Enum.any?(native, &(&1.key == "exagent.operation" and
            &1.value == %{value: {:string_value, "model"}}))
          semantic = if model, do: Enum.filter(native, &(&1.key in @model_keys)), else: []
          attributes = diagnostic ++ resource_metadata ++ semantic
          true = length(attributes) <= 64
          %{span | attributes: attributes}
        end
        %{scope | spans: spans}
      end
      %{resource | scope_spans: scopes}
    end
    %{request | resource_spans: resources}
  end

  defp prefix(attribute, prefix), do: %{attribute | key: prefix <> attribute.key}
end
```

Compile this module in your application. Set `request_profile: MyApp.OpikProjection`
in the trusted configuration of the isolated **gRPC** exporter and route its output
through the [Collector HTTP bridge](../development/otlp-collector-transport.md)
to Opik's endpoint. The direct stock HTTP exporter has no `request_profile` option.
This projection is for the converter interface described in the
[isolated transport guide](../development/otlp-isolated-transport.md).
The 64-attribute bound rejects excessive expansion instead of silently losing data.
The model fields populate inference usage; other operations remain general spans.
No fake arguments or results are added to force a backend type.

With content off, Langfuse and the projected Opik route can show Input `null` or
Output `undefined`; an empty preview is not a missing trace.
Inspect the hierarchy and attributes for run/request IDs, terminal status,
accounting quality and partial progress. A recovered execution retains the
earlier failed attempt in the trace; success does not erase its error history.
Further destination-specific labels require trusted application mappings according
to the backend's attribute contract, without exporting private content.

## 7. Verify your application's route

First exercise tracing with TestModel and an in-memory exporter. Then check the
actual destination's hierarchy, errors, generation usage and permitted content.
Verify cancellation, pause/resume and checkpoint retry when your application uses
them. A successful HTTP response alone cannot establish how a backend retained
or displayed every span.

The packaged local example needs no provider or cloud credentials:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/observability.exs
```

Its optional `--bench` measures synthetic framework instrumentation overhead,
not model latency or a production SLO. Prompts, evaluations, datasets and
historical backend data remain application/service concerns.
