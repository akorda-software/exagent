# Optional Opik A10 acceptance (objective 024)

User mandate 2026-10-02 requires Langfuse and Opik to have equal acceptance depth.
The existing Langfuse receipt stays immutable. This separate explicit native
wave reuses the six-scene public A10 application, TestModel and owned
SDK/Collector route. No paid model/provider, default runtime, global tooling,
historical trace, deployment or library backend dependency is added.

`opik_run.py` defaults to skip before file/key/network access. Preparation is
local only. Live ingestion requires the exact package, sealed private admission,
an explicitly supplied synthetic workspace, project `exagent` with an independently checked public UUID,
and owner-only regular 0600 JSON containing only `api_key`. It validates source
bytes before key access and project identity before any POST. Opik's account key
is broader than a Langfuse project key: the driver restricts routes, workspace,
project, trace IDs and finite calls; it does not claim project-limited credentials.

The official Cloud [OTel integration](https://www.comet.com/docs/opik/integrations/opentelemetry)
requires HTTP/protobuf at `/api/v1/private/otel/v1/traces`, raw-key `Authorization`,
`projectName` and `Comet-Workspace`. The official Collector version/checksum,
loopback ownership, native ETF and body ceilings, retry/queue/lifetime and
raw-log boundaries are the same as [Langfuse's route](README.md). This pair
admits 18 flow + 15 recovery spans, 12 model requests, 6 logical tool calls,
7 tool attempts and 4 effects. One live wave permits at most **five POSTs**;
the finite profile does not certify general throughput or durable retention.

Opik's pinned official mapper
[`ada1cc563fe3b4b19364014e5a0d4832ec5ffee2`](https://github.com/comet-ml/opik/blob/ada1cc563fe3b4b19364014e5a0d4832ec5ffee2/apps/opik-backend/src/main/java/com/comet/opik/domain/OpenTelemetryMapper.java)
converts OTLP IDs to UUIDv7, routes unknown attributes to input, and consumes
only span attributes. `opik_profile.exs` is an application-owned projection of
the public stock-converter map: every native scalar and resource scalar enters
the documented `opik.metadata.<key>` namespace with its original AnyValue type;
native ID correspondence is proved from the independently derived UUID map.
Model/provider/usage enter Opik's
native fields only on inference spans. No content, fake tool arguments, price
or ID overrides are emitted. The original manifest precedes ingestion, and
sorting opaque rows by public-converter start time makes UUID derivation from
the native trace start deterministic. Projection expansion must fit 64 attrs
and 65,536 ETF bytes per trace before any batch is sent; each batch retains the
original eight-span/65,536-byte gate and opaque HTTP preflight.

With content off, Opik's mapper types tools as `general`; `exagent.operation`
and `gen_ai.operation.name=execute_tool` in metadata must diagnose the real
tools and attempts. Inference spans must be `llm`, with exact projected usage.
This is a documented presentation difference, not a weakened parent/identity,
status, usage, cost/provenance/unit or privacy oracle. Pinned public source
explains the expected mapping; it does not identify the running Cloud build.

One identity GET has a three-second owner deadline. After native completion,
one bounded read (four GETs/seven seconds, no polling/retries/pagination/history)
fetches each exact fresh trace and its at-most-32-span page. Each owner has at
most one additional second for group cleanup, so the two stages admit twelve
seconds in total. Bodies are limited
to 512 KiB, with no redirects or inherited proxies. The reader checks all IDs,
edges, names, native milliseconds, error states, every native/resource attribute
and scalar type, model/provider/leaf usage, absence of inclusive double count,
empty input/output and private sentinels. Failed diagnostics keep fixed labels,
types and native identities, never remote bodies/unknown IDs/private values.
API success does not accept UI, price, billing, retention or other profiles.

Opik's admitted Cloud profile allows 3 s per HTTP acknowledgement, 3.5 s per
gRPC call, 5 s per owned batch VM, 20 s for the processor export, 28 s for the
native owner and 30 s for Collector lifetime. These are finite acceptance
ceilings, not latency guarantees. The 500 ms and 1 s attempts failed while Opik
stored their first batches; retain those failures separately. No retry or queue
is enabled. Langfuse retains its previously accepted timing profile. Equal
validation means the same identity/tree/usage/privacy oracles, not a claim that
both backends have the same latency.

Offline controls deliberately corrupt rows, parent/trace/project IDs, UUIDs,
booleans/integers/cost provenance, statuses/timestamps, usage, pagination and
private content. They must fail closed before the explicit new cloud wave.

```bash
python3 test/support/langfuse_acceptance/opik_control.py --run \
  --manifest /tmp/<native-preflight>/native-manifest.json \
  --report /tmp/<private-parent>/api-controls.json

python3 test/support/langfuse_acceptance/opik_run.py --prepare \
  --consumer /tmp/<physical-current-consumer> \
  --workspace <explicit-synthetic-workspace> \
  --package /tmp/<exact-candidate>.tar --tar-sha256 <sha256> \
  --collector-binary /tmp/<official>/otelcol \
  --elixir-bin /path/to/elixir/bin --erlang-bin /path/to/erlang/bin \
  --rebar3 /path/to/rebar3 --archives /tmp/<private-tooling>/archives \
  --work /tmp/<private-parent>

# Only after source/control preflight, project UUID discovery and sealing.
# Run the frozen driver, not the mutable checkout entrypoint:
python3 /tmp/<sealed>/harness/opik_run.py --run \
  --admission /tmp/<sealed>/admission-scope.json --admission-sha256 <sha256> \
  --wave <explicit-fresh-wave> --credentials-file /tmp/<owner-only-key>.json \
  --work /tmp/<private-parent>
```

The owner and both read workers verify the executed driver/helper paths and
hashes against the sealed harness before opening credentials. A mutable checkout
driver cannot attribute its execution to a different frozen copy.

The authenticated browser must then independently show the two exact trees,
parallel/delegation, correction/checkpoint retry and both C7 attempts, logical
IDs/continuation correlation, qualified counters/cost/provenance/units and
privacy. Retain actual rendered fields/screens separately from API evidence;
an unlogged-in session or missing fields leaves UI and expanded G4 pending.
