# Optional Langfuse A10 acceptance (objective 015)

This checkout-only harness prepares an exact private source, then admits an
explicit wave. Preparation performs no cloud request and reads no real key or
`.env`. The live command is **not authorized merely by reading this recipe**;
the integration owner must declare the package/admission, public project ID,
wave name, trace budget and real credential source before invoking `--run`.
No library dependency, required exporter, global configuration or service is
installed. Objective 004/010 receipts remain separate experiments. Their R8
review does not cover this later harness.

## Route and source

The application uses public ExAgent run/tool, Server checkpoint, Continuation
approve/resume and `ExAgent.Examples.FlowPipeline.execute/2`. The default profile
tries one application parent containing router + two parallel branches + D
delegation, corrective retry with one effect, failed checkpoint + retry without
rerunning effects, and pause → approve → resume. The admitted pair profile has
two correlated application parents, one for flow and one for recovery. It
preserves all six scenes; it is not one combined trace. The complete scenes require exactly **12 model
requests, 6 logical tool calls and 4 effects**. Seven native tool attempt spans
are expected: the paused and resumed approval attempts share one logical call.
Counters on parent runs are inclusive; do not sum every run's counters.

`producer.exs` starts a named private native SDK provider and the public
`BoundedProcessor` callback. The complete batch is converted with the official
public `otel_otlp_traces:to_proto/2` before admission. Opaque ETS rows are copied
using public ETS metadata into batches of at most 8; their trace identity is
obtained through the public converter. There is no private span-record match,
OTLP encoder or wire parser. The unchanged 004 exporter owns one private VM per
batch and uses the generated public gRPC client. Official exporter **1.11.0**
is required, together with the official Collector **0.162.0** from 010.

The published converter signature is documented in the official exporter
[HexDocs](https://hexdocs.pm/opentelemetry_exporter/otel_otlp_traces.html).
The 1.11 release keeps its exported/spec'd function but supplies no additional
custom-consumer stability promise; future changes need a causal focal. The
Collector binary is SHA-verified on preparation, admission and launcher start:
`910a66b1210e09143260914ef0634b4d234c789f23efc34bc9c7a3c0480324fa`.
Its release/archive provenance is recorded by objective 010.

Preparation accepts only a physical `/tmp` Mix consumer with compiled private
dependencies and `_build/lib/*/ebin`. It creates another physical copy, excludes
`.env` and external symlinks, checks every public Hex TAR member against the
installed ExAgent source, and compiles that private project with
`--warnings-as-errors`. Sources, package, recipe, plugin, tools and private
BEAM/source files are hashed into the admission. Live invocation refuses changed
bytes before reading credentials. `HOME`/`CODEX_HOME` are never reassigned.

## Finite profile

| Boundary | Admission |
| --- | --- |
| Trace count | 1 by default; 2 only with a new explicit `--max-traces 2` admission |
| Per trace | At most 32 spans and 65,536 bytes of uncompressed native ETF |
| HTTP body | At most 65,536 bytes per request; aggregate per-trace bytes are qualified by the exact opaque loopback preflight |
| Host preview retention | Queue/batch ceiling 64 spans; any queue loss refuses admission |
| Transport | At most 8 spans/VM batch, concurrency 1, no retries |
| VM batch/RPC | 2,000/1,200 ms, cleanup by registered owned VM/process group |
| Collector | Loopback ephemeral gRPC/metrics, 30 s lifetime, finite 2 s stop + escalation |
| Collector exporter | Protobuf HTTP, 500 ms timeout, queue/retry disabled, no batch processor |
| Collector memory | 128 MiB memory limiter, 32 MiB spike, Go memory target 96 MiB |
| Logs | FIFO, at most 1 MiB processed/64 KiB line; scalar counters only, no raw log file |
| Native host | 24 s command deadline plus owned stop; no credentials in VM env/argv |
| API | 1 project-identity GET before POST (3 s owner deadline), then at most 19 observation GETs (27 s owner deadline) |
| API body | At most 512 KiB per GET, no redirects/proxy inheritance, no pagination/history scan |
| Separate acceptance read | At most 3 GET/12 s: one identity GET/3 s + one observation GET per trace/7 s total + 2 s cleanup; no polling/retries |

The 64 KiB native ETF ceiling is a conservative host/admission limit, not an
upstream hard RAM or protobuf-size theorem. Conversion precedes the ETF check;
SDK attribute count/value limits are 64/128, events/links 8/4. The local fixture
counts opaque protobuf bytes without decoding or retaining bodies. The HTTP
payload proof belongs to the exact deterministic admitted scenario, not arbitrary
future content. The aggregate per-trace HTTP ceiling is a preflight proof, not a
live wire intercept or hard protobuf allocation limit. All Elixir scripts are loaded only in a private VM; `.exs` prevents
ROOT Mix from compiling them as test-support modules.

Each isolated VM and Collector have operational startup cost. This route is an
optional application-owned recipe, suitable for a finite acceptance wave; it is
not the core default. C7 here uses an owned ephemeral ETS store and fresh model
cursor restoration in the same host VM. It does not repeat or qualify durable
cross-host restart, SQL, real providers, billing or MCP acceptance.

## Preparation

Default calls skip before source, key, environment or network access. Run the
synthetic API/secret/FIFO checks with explicit artifacts:

```bash
python3 test/support/langfuse_acceptance/preflight.py --run \
  --collector-binary /tmp/<official-artifacts>/bin/otelcol \
  --recipe examples/otlp_transport --work /tmp/<private-parent>
```

After the source owner supplies a stable private consumer and exact TAR:

```bash
python3 test/support/langfuse_acceptance/run.py --prepare \
  --consumer /tmp/<sealed-consumer> \
  --package /tmp/<candidate>.tar --tar-sha256 <exact-package-sha> \
  --package-source . \
  --collector-binary /tmp/<official-artifacts>/bin/otelcol \
  --elixir-bin /path/to/elixir/bin --erlang-bin /path/to/erlang/bin \
  --rebar3 /path/to/rebar3 --archives /tmp/<private-tooling>/archives \
  --project-id <public-exagent-project-id> --work /tmp/<private-parent>
```

Use the actual physical installed source path for `--package-source`; the
qualified consumer uses `vendor/exagent`, not `deps/exagent`. Preparation
executes this new complete A10 scene once through the real route to an owned
loopback HTTP fixture, with no auth. It proves per-request bytes and the v4
header. Native manifest admission is persisted **before** the callback may send
the first batch. A profile rejection writes `blocked_profile`; it never silently
omits a scene or splits a trace. If the complete shape exceeds a trace budget,
the owner can explicitly prepare two application traces (flow and recovery) in
one wave, preserving all scenes and exact counters. Local preflight IDs are not
cloud acceptance IDs. The complete default trace was correctly rejected at
79,919 ETF bytes > 65,536. A separately admitted pair fits: recovery 15 spans /
33,298 ETF bytes / 14,836 opaque HTTP bytes; flow 18 spans / 47,701 ETF bytes /
22,030 HTTP bytes. The pair has 33 observations and five HTTP batches of at most
eight spans. A single limit-32 API query cannot cover both roots: query each
trace separately, without pagination or dropping an observation.

## Explicit live wave

The owner supplies one owner-only regular JSON credential file with mode `0600`,
keys `public_key` and `secret_key`. No values belong in CLI arguments, shell
history, stdout, receipts, events or environment variables. No `.env` parser is
used here. Credential reads occur only after exact admission verification in
the opt-in live phase. A project-scoped identity GET must return exactly the
admitted ID and name `exagent`; otherwise the command stops before POST.

```bash
python3 test/support/langfuse_acceptance/run.py --run \
  --admission /tmp/<prepared>/admission.json \
  --admission-sha256 <exact-admission-sha> \
  --wave <public-admitted-wave-name> \
  --credentials-file /tmp/<private-0600-credentials>.json \
  --work /tmp/<private-parent>
```

The fixed destination is EU Langfuse. Basic auth exists only in memory and a
private `0600` Collector YAML removed after stop. Collector stderr/stdout goes
to `/dev/null`; its public logger writes to an owned `0600` FIFO. The owner
retains only counts/recognized partial-success loss, discarding message/body/
header fields. Secrets never enter the ExAgent VM, receipt or API body log.

Langfuse currently accepts
[OTLP HTTP/protobuf and the v4 header](https://langfuse.com/integrations/native/opentelemetry),
not direct gRPC. The bridge sets `x-langfuse-ingestion-version: 4` on
`/api/public/otel/v1/traces`. This is required for real-time v4 visibility.
The current [primary OpenAPI](https://cloud.langfuse.com/generated/api/openapi.yml)
defines `GET /api/public/projects` for key scope and `GET
/api/public/v2/observations` for bounded reads. Observation queries use only
fresh native trace IDs and bounded start-time windows, projection
`core,basic,metadata,io,model,usage,trace_context`, limit 32. The `model` group is
required to verify model identity. There is no legacy API
fallback or query of historical traces. A missing row remains incomplete.

The explicit metadata profile is `v4_flat_paths`. The official v4
[worker](https://github.com/langfuse/langfuse/blob/main/worker/src/services/IngestionService/index.ts)
flattens raw metadata with
[flattenJsonToPathArrays](https://github.com/langfuse/langfuse/blob/main/packages/shared/src/server/otel/utils.ts).
The public API [converter](https://github.com/langfuse/langfuse/blob/main/packages/shared/src/server/utils/metadata_conversion.ts)
returns literal dotted keys and decoded scalar types. This reader accepts only
the `attributes.` and `resourceAttributes.` prefixes, without a nested-object or
JSON-string fallback. Current native scalar strings are at most 40 characters;
the SDK cap is 128, below the API's 200-character truncation threshold. If a
future admitted manifest requires expansion, `expandMetadata` contains only its
exact literal stored keys, not container names, wildcards or arbitrary keys.

The explicit name profile is `v4_gen_ai_tool_name_else_native`. The official
[extractName](https://github.com/langfuse/langfuse/blob/main/packages/shared/src/server/otel/OtelIngestionProcessor.ts)
prioritizes a nonempty `gen_ai.tool.name`. Four spans in this pair use that name;
the API name and native span name are recorded separately. Parent identity is
unchanged. This profile requires string tool names and rejects other naming
integration attributes before credential access. These projections are grounded
in saved official source hashes, not a guarantee that future backend versions
will retain the same representation. A change needs an explicit causal control
and new admission; there is no alternative fallback.

API verification requires exact own IDs/parentage/projected-name/status, native timestamps
at millisecond resolution, all `exagent.*`/`test.*` scalars, bool types, empty
I/O and absent private sentinels. Model spans require the actual generation/model
mapping and input/output usage. Quality/provenance and cost cents remain separate
native metadata; API cost-in-USD is not a billing receipt. Native, Collector and
API receipts remain distinct: callback `ok` and Collector `sent_spans` can include
backend partial rejection. The Collector handles that response as success and
logs `dropped_spans`; any partial event prevents qualification. Full API rows
verify this bounded read path only, not durable retention or UI.

## Separate acceptance read

A failed API verification does not authorize replaying ingestion. The optional
`read_only.py` reads only the two previously admitted fresh IDs and original UTC
windows. Its source-sealed plan verifies the TAR, actual consumer lock, native
manifest, fields, v4 metadata/name profiles and exact queries before reading
keys. A mismatched project identity prevents observation reads. The process
owner bounds the reader's full lifetime, including DNS, and reaps only groups it
created. Both observation pages are inspected once; failures retain all checks
for all known rows, using fixed labels, JSON types, presence/matches and mismatch
codes. Remote values, arbitrary keys, content and usage amounts are discarded.

Run the local fixture against the prior native manifest without API access:

```bash
python3 test/support/langfuse_acceptance/api_control.py --run \
  --manifest /tmp/<ingestion-wave>/native-manifest.json \
  --work /tmp/<private-parent>
```

Only after the owner admits one concrete read and seals its plan:

```bash
python3 test/support/langfuse_acceptance/read_only.py --run \
  --plan /tmp/<read-plan>.json --plan-sha256 <exact-plan-sha> \
  --credentials-file /tmp/<private-0600-credentials>.json \
  --work /tmp/<private-parent>
```

This phase makes zero POST and runs no Producer, SDK, Collector or Model.
Exhausted quotas, missing rows or mismatches stay incomplete/red. Command exit
zero means an outcome receipt was written; use its `status` to assess acceptance.

## User browser checklist

The live receipt prints only newly created trace IDs and exact links of the form
`https://cloud.langfuse.com/project/<project-id>/traces/<trace-id>`, matching the
official [Langfuse trace URL construction](https://github.com/langfuse/langfuse/blob/main/packages/shared/src/server/repositories/traces.ts).
`ui_accepted` remains false until the user confirms from their own browser.
No browser session, cookie, login or unrelated trace is acquired.

1. Open only those links in project `exagent`; compare observation IDs and parent
   edges with `native-manifest.json` and the API receipt.
2. Router has one selected leaf. Parallel has A/B, and B has tool → delegation
   → D. Terminal data-only Flow resume adds no requests or effects.
3. Corrective retry has one error attempt and one successful effect. Two
   checkpoint spans show failed save then successful retry without rerunning work.
4. Paused run is `DEFAULT`, with no effect before approval. Resume has the same
   logical run/record ID, a fresh attempt ID and exactly one approved effect.
5. Native host totals are 12 requests / 6 logical tool calls / 4 effects. Parent
   counters are inclusive; usage/cost metadata shows its quality and units.
6. I/O remains absent and private sentinel values are absent. Compare loss/unknown
   diagnostics independently of ACK and UI tree rendering; report any mismatch.

## Recorded qualification and preserved failures

Candidate TAR `4629a1f2d22669b5fc352dcb62b8711cf11a4a2940a0c1fa25f3e98a8611c233`
and actual consumer lock `4f7947774c597783b5372049f32a7afdbc32cc0cf1330c5368662a8d303f2fd3`
produced the complete native pair on Elixir 1.20.0/OTP 29, official SDK 1.7.0 /
API 1.5.0 / exporter 1.11.0 and Collector 0.162.0. The single admitted ingestion
wave has 33 callback ACKs, five VM groups closed, no reported loss/unknown,
retained host spans zero and finite Collector stop. This evidence is distinct
from backend verification.

The final separately admitted read verifies 33/33 backend observations, 667
native attributes and 12 model/usage mappings with three GET/734 ms, zero POST
or ingestion reruns, and reaped reader groups. Status is
`native_api_verified_ui_pending`. Both fresh URLs are in its receipt. User UI,
durable backend retention and provider billing remain unqualified.

Prior red receipts are retained: the original boolean/map C7 oracle bug;
default one-trace budget rejection; first ingestion/API failure with its remote
cause unrecoverable; read `api_attribute_projection`; diagnostic proving 33
known IDs with flattened metadata; and read `api_parent_or_name` before the
documented tool-name projection. These are separate source/admission identities,
not overwritten by the final receipt. The earlier stock HTTP exporter 1.10 red
gate and objective 004/010 experiment limits also remain in force.
