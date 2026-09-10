# Optional OpenTelemetry observability

ExAgent instruments operations with native Erlang/Elixir OpenTelemetry. The host
application owns the SDK, sampler, resource, processors, exporter and credentials.
No tracing service is required for the ordinary core, Server or Session.

This guide describes the current optional tracing implementation. The
[verification guide](../development/verification.md) provides runnable checks;
[project status](../status.md) records accepted evidence and remaining limits.
Langfuse and Opik are candidates; neither is a selected or verified reference
backend yet. The next comparison is defined in the
[backend acceptance plan](../development/backend-evaluation.md).

## 1. Application setup

An application choosing OTLP can add these dependencies to its own `mix.exs`:

```elixir
{:opentelemetry_api, "~> 1.5.0"},
{:opentelemetry, "~> 1.7.0"},
{:opentelemetry_exporter, "~> 1.10.0"}
```

ExAgent declares API and SDK as optional consumer dependencies; the SDK is marked
`runtime: false`. The optional SDK compile edge ensures native record definitions
are available when the host opts in, even on a clean or partitioned build. It does
not install/start the SDK for consumers that omit it. The exporter belongs to the
host application. API present without an SDK uses the native no-op tracer.

Configure one processor route before starting the SDK, for example in the host's
`config/runtime.exs`:

**Native HTTP exporter qualification:** the recipe below is verified for local
wire transport with exporter1.10.0, but its long-lived HTTP lifecycle is not
accepted. Timeout/shutdown can leave native profiles, atoms and outstanding TCP
requests after ExAgent's own processes close. Read section7 before choosing this
route for an application; a callback deadline is not a network cancellation.

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

The numbers above are an example configuration, not measured production SLOs.
Use the complete traces URL, including its ingestion path. The generic
`otlp_endpoint` option appends `/v1/traces`, whereas `otlp_traces_endpoint` preserves
the full path. Configure authentication through the exporter's native
`OTEL_EXPORTER_OTLP_TRACES_HEADERS` environment variable (comma-separated
`header=value` pairs), or trusted `otlp_traces_headers` application configuration.
Credentials never belong in an agent, attribute or baggage item. Configure
`OTEL_SERVICE_NAME` and resource attributes for the host application as usual.

Keep processor/exporter options in `processors:` **non-secret bootstrap data**.
The SDK's OTP supervisor retains those original start arguments and can include
them in a crash/restart report, before ExAgent's status projection can sanitize
anything. Put credentials in the exporter's environment/application configuration,
as above, and keep `exporter: {:opentelemetry_exporter, %{}}` free of secrets.
Custom exporters should resolve credentials inside their own initialization.

An existing OTel application should integrate this route deliberately: ExAgent
does not replace its provider or install a processor automatically. The processor
sees all recording spans routed through that provider, not only ExAgent's scope.
An app-supplied native tracer can select a named provider via the `tracer:` option
of `ExAgent.Observability.OpenTelemetry.new/1`. Pass a matching explicit `resource:` to a processor when
using a provider-specific resource. Avoid configuring both `span_processor:` and
`processors:`. Native SDK 1.7 may short-circuit subsequent processors when one
returns a drop; put a dropping processor last and test any intended fan-out.

## 2. Enable instrumentation

```elixir
alias ExAgent.Observability.OpenTelemetry

tracing = OpenTelemetry.new()
agent = ExAgent.new(model: model, observability: tracing)
{:ok, result} = ExAgent.run(agent, "A request")
```

`model` is the application's live model. `observability:` can also be supplied
per run or to the optional Server/Session runtime. Result shapes, execution scope,
limits, checkpoint acknowledgement and snapshot formats retain their contracts.
See [migration](migration.md) for conservative completeness flags on synthesized Server failures.

Operations are run, model request, tool, delegation, compaction and checkpoint.
Server owns a run span through its checkpoint; its core worker shares that span.
There is no span per token and no span covering a Server's entire lifetime.
Model-request spans end before after-request hooks and tool execution.

For application-owned process boundaries, capture before dispatch and attach in
the receiving process:

```elixir
context = OpenTelemetry.capture_context()

Task.async(fn ->
  OpenTelemetry.with_context(context, fn ->
    ExAgent.run(agent, "Another request")
  end)
end)
```

ExAgent propagates context across its own tools, delegated runs and runtime
requests. Server queues capture at admission. A public lazy stream captures at
enumeration unless supplied an explicit `trace_context:`. Capture contains span
context and instrumentation configuration, excluding arbitrary context/baggage.
Handles are ephemeral runtime values, not snapshot or JSON data. Attachment
restores prior trace context and owned Logger trace keys.

## 3. Privacy before export

Content is **off by default**, including prompts, responses and tool arguments or
results. The adapter selects bounded identifiers, operation status and usage; it
does not serialize model/deps/configuration, arbitrary metadata, exception
messages, stacktraces or provider bodies. Use non-secret labels and correlation
IDs: a caller-supplied name is still data supplied by the application.

Opt-in content requires an explicit redactor:

```elixir
tracing = OpenTelemetry.new(
  content: true,
  redact: fn _field, _value -> {:ok, "[content withheld]"} end,
  max_content_bytes: 4096,
  max_content_input_bytes: 65_536
)
```

This example deliberately replaces every admitted value. A real application can select
approved fields and return `{:ok, safe_utf8_binary}` or `:drop`. It is responsible
for the redaction policy. Oversized input is dropped before invoking the redactor;
oversized or invalid output and failed callbacks drop the entire field before
SDK attributes are created. No unredacted prefix is exported. Redactors are
trusted synchronous callbacks and should be fast; they are not sandboxed.

Only bounded plain data is admitted. Opaque values and structs, including an
Ecto structured output, are dropped before the callback even with content opt-in.
This initial profile does not automatically serialize custom encoders or typed
outputs for export. The validated result returned to the application is unchanged.

Backend/UI masking is not this privacy boundary. It may happen after temporary
storage. Native/third-party exporters and their own logs have their own contracts;
ExAgent's safe diagnostic projection does not certify arbitrary exporter logging.
No hidden model reasoning is promised or automatically exported.

## 4. Usage, costs and the versioned profile

The small `exagent.gen_ai.v1` profile is pinned to GenAI revision
[`b5d8440`](https://github.com/open-telemetry/semantic-conventions-genai/tree/b5d8440f6f126738fd50f927752cd669772c517b).
It is an explicit subset, not full semantic/UI compatibility. That revision has
no published schema URL; ExAgent does not invent one.

- `gen_ai.usage.*` is emitted only for model requests. Cache read/write and
  reasoning tokens are subsets of input/output, not additional billable totals.
  Reasoning detail in this profile is `exagent.usage.reasoning_tokens`.
- Native Anthropic input excludes cache: the generation projection adds cache
  read/write to obtain GenAI's inclusive input. OpenAI-compatible/Test inputs are
  already inclusive. Run aggregates retain the ledger's provider-native semantics.
  For custom models with unknown input semantics, the GenAI input total is omitted;
  `exagent.usage.reported_input_tokens` preserves the observed value and
  `exagent.usage.input_tokens_semantics` is `provider_reported`.
- The current cache-write key is `gen_ai.usage.cache_write.input_tokens`.
  Older backends may expect a different mapping; verify their actual interpretation.
- Run usage is an inclusive subtree aggregate under `exagent.usage.*`. Do not add
  root, child and generation totals together. Keeping run aggregates out of the
  GenAI namespace is a deliberate profile choice to avoid that ambiguity.
- Estimated costs reuse execution accounting in cents, including fractions and
  known/unknown status. Instrumentation does not call a second pricing function.
- Missing usage is not zero; cancellation cannot reconstruct unreported usage.
  A sampled or lossy trace is not an authoritative cost ledger.

If Server synthesizes a terminal after abort/worker loss, it marks the retained
partial and Event as partial/unknown rather than certifying an older subtotal.
The run span omits a purported total cost and exposes an available numeric
subtotal as `exagent.cost.known_subtotal_cents`. Normal core results preserve their
confirmed completeness; no estimator is called again by this projection.

## 5. Bounded export and diagnostics

The native SDK 1.7 batch processor writes to ETS without HTTP in the caller, but
checks its queue threshold periodically. That threshold is not a hard bound, and
the SDK does not expose the requested drop/error/timeout counters. The optional
`BoundedProcessor` addresses that specific gap through the public span-processor
extension, using native tracer/span/exporter data.

Its finite slots include queued and in-flight spans, with a bounded batch and one
export worker. The run does not wait for exporter I/O. Saturation rejects rather
than queuing indefinitely. Quantity of spans is not a byte bound on arbitrary
application attributes or exporter allocations; SDK storage for active spans is
another boundary. Slots do not promise FIFO ordering. An exporter timeout/error drops
its batch without implicit retry; cancellation does not imply remote rollback.

`BoundedProcessor.stats(:exagent_export)` exposes local scalar counters. Its
`force_flush/1` is a coalesced asynchronous request, **not a delivery ACK**. A
successful exporter callback also does not certify durable backend reception or
zero OTLP partial rejection. Use exporter barriers in local tests and query the
destination for acceptance. Arbitrary synchronous app processors/samplers can
still block their caller; use the configured, verified asynchronous route.

`shutdown(:exagent_export)` returns `{:ok, final_stats}` after discarding pending
and in-flight spans and bounded cleanup; it does **not** drain them. Flush and
wait for an application-defined exporter barrier before shutdown if needed.
SDK supervision may restart a permanently supervised processor after direct
shutdown; the application manages its provider/supervision to remove that route.
Counters reset per processor generation and are not durable across a VM/manager
crash. An observer emits scalar cumulative snapshots on
`[:exagent, :observability, :processor]`; slow handlers do not hold up export
deadlines. Instrumentation failures and content drops use separate safe events.

## 6. Offline and backend acceptance

The local example uses deterministic models and an in-memory exporter. Additional
tests traverse the real native OTLP exporter into a loopback receiver, as described
below. The accepted runtime and downstream-package matrices, including exclusions
and strict dependency warnings, are centralized in [project status](../status.md).

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/observability.exs --bench
```

The example can measure synthetic overhead with `--bench`; those measurements
are not LLM latency or a production SLO. The
[verification guide](../development/verification.md) includes current commands
and the isolated scheduling probe for the flush race. Historical sample counts
remain in the dated execution record rather than being presented as a new run.

External acceptance remains a separate gate: run the same synthetic scenario in
Langfuse and Opik, inspect both API and UI, and verify hierarchy, retries,
cancellation, checkpoint, cost/cache, permitted content and error diagnosis.
Compare licensed functionality and operational effort with the user's stated
preference for more license-free functionality at comparable quality. Neither
OTLP HTTP200 nor a different label establishes equivalent observability.

Prompts, datasets, scores, evaluations and historical data do not migrate merely
by changing an endpoint. Their integrations belong outside the critical run path.

## 7. Native OTLP HTTP: measured local contract and limits

N01–N03 add the real `opentelemetry_exporter`1.10.0 as a **test-only** dependency.
Four isolated-VM tests use SDK1.7/API1.5, a controller-gated receiver bound to
127.0.0.1 on a dynamic port, and the exporter's official protobuf decoder. They
inspect POST, full/generic path mapping, content type, resource/scope, nonzero
trace/span/parent IDs, operation attributes and usage. A two-request run with one
tool emits four spans. Synthetic authentication reaches the HTTP header and is
absent from the body, as are content/model/dependency sentinels under content-off.
Callbacks first prove those inputs actually entered the run.

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix test test/exagent/observability/native_otlp_test.exs --warnings-as-errors
```

The tests own disposable VMs; the lifecycle experiment does not modify the parent
test VM's tracing configuration. See `test/support/native_otlp_probe.exs` for its
direct command and machine-readable measurements. Use the
[environment guide](../development/environment.md) for the temporary tooling prefix
required by this development workspace; [status](../status.md) records accepted gates.

### Delivery counters describe callbacks

While the first real HTTP request waits at a receiver barrier, another full run
finishes its model calls and tool effect. Each failure case observes four model
calls, two effects, two traces and two HTTP export requests. After both batches:

| First batch response; second succeeds | accepted | exported | export_failed | export_timed_out |
|---|---:|---:|---:|---:|
| 401,403,429,503 or connection close | 8 | 4 | 4 | 0 |
| Response held beyond processor deadline | 8 | 4 | 0 | 4 |
| 200 with protobuf `rejected_spans=4` | 8 | 8 | 0 | 0 |

Exporter1.10.0 ignores the successful response body, including `partial_success`.
Thus **`exported` is successful-callback count, not remote accepted-span count**.
A late HTTP success does not undo a timed-out batch; another flush does not replay
effects/batches. The test does not certify every upstream redirect/retry variant.
Native failure logs can print a response body; use synthetic responses in tests
and assess third-party exporter logging separately from ExAgent's projections.

### Boolean type fidelity is a known upstream defect

The native SDK retains boolean span/resource attributes. Exporter1.10.0 handles
atoms before booleans and serializes true/false as protobuf strings. A direct
native-export control reproduces this independently of ExAgent, alongside correctly
typed string/integer controls. No vendor patch or false assertion of type fidelity
is included. Carry this loss into destination/profile acceptance.

### Owned-process cleanup is distinct from HTTP cleanup

After warmup, three direct native init/export/shutdown cycles retain one profile
and four ETS tables per cycle; this occurs without BoundedProcessor. Profile names
derive from exporter PIDs, producing unreclaimable atoms (seven per new profile in
the observed OTP29 VM). Removing the profiles does not reclaim those atoms.

In three processor timeout/reinit/shutdown cycles, monitors prove all seven tracked
ExAgent processes terminate and their ETS/handle is removed, while a native HTTP
handler/socket survives. Merely calling `:inets.stop/2` on the profile also leaves
the active handler in the observed OTP29 implementation. The probe preserves this
negative control and observes peer closure at the receiver, rather than inferring
it from exporter-worker death.

Only within the exclusively owned disposable VM, the probe can observe outstanding
request IDs before profile removal, cancel those requests, wait for handler DOWN
and actual peer closure, then stop its own profiles. Default/unrelated profiles
survive and measured process/monitor/ETS/socket gauges return to warm baseline.
This uses version-specific diagnostic information from `:httpc.info/1`; it is not
a general ownership API safe to copy into a concurrent host application, and it
does not solve atom retention.

General long-lived native HTTP cleanup remains gated on an upstream ownership/
cancellation/lifecycle fix, or an independently owned disposable exporter VM
boundary with its own acceptance. Other transports/exporters require separate
tests. ExAgent does not inspect private profile names, close shared inets services,
or implement a second OTLP client to hide this limitation. Platform API/UI
comparison and production-like acceptance remain open.

### Composed scenario for later platform comparison

`test/exagent/observability/native_otlp_scenario_test.exs` persists three further
scenarios with68 spans in11 loopback POSTs. They compose parallel tools/delegation,
corrective retry, five stream deltas, compaction, failed checkpoint and save-only
retry; compare identical tracing-off/on ledgers (4 requests,43/8 tokens,0.51 cents,
10 estimator invocations); and inspect generation usage as protobuf integer tags.
Parent/subtree totals remain separate from generation sums.

Two queued callers retain separate trace IDs and parent contexts. Cancellation
preserves0.12 cents as a known subtotal with unknown total; a post-model hook
failure retains its already completed effect and confirmed usage. Content-off and
stateful redactors are checked with effective callback sentinels, eight allowed
fields, fail-closed exceptions/oversize output, input limits, empty context and
owner/tool DOWN. These are reproducible inputs for future destination comparison;
they do not imply that Langfuse/Opik render the payload correctly or resolve the
native HTTP lifecycle gate above. [Project status](../status.md) records accepted
gates and points to the dated evidence.

## 8. Reproducible framework measurements

The source checkout's `test/support/framework_load_probe.exs` compares reused
simple, typed-tool and delegated definitions at concurrency1/8/32 with tracing
off/on. It records raw samples, nearest-rank p50/p95/p99, own-VM resource samples,
export counters and cleanup. Use `--json <path>` as the machine-readable channel;
stdout can also contain expected Logger diagnostics. `--smoke` validates a smaller
fixture and is not the performance dataset.

The initial full run uses seed131415,32 warmups and200 samples per matrix row,
plus two finite200-run delayed-callback cases. All4000 measured results pass;
12200 measured spans export locally without normal drops. A separate callback
barrier holds32 accepted spans while610 further spans drop and64 agent runs still
finish. Construction, pre-start waiting and export draining are outside individual
run latency. Resource sampling is every5ms plus collection cost and boundary
snapshots; reported maxima can miss peaks and are not simultaneous upper bounds.

These experiments use an in-memory exporter and do not fix or measure the native
HTTP ownership limitation in section7. Detailed percentiles, conditions and
review evidence are in the
[dated consolidation record](https://github.com/kukapu/exagent/blob/main/docs/archive/2026-09-consolidation/action-plan.md);
no new optimization or production SLO is
inferred from a concurrency comparison alone.
