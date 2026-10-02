# Native OTLP through an application-owned Collector

Objective010 demonstrates ExAgent native instrumentation → the optional
[isolated exporter callback](otlp-isolated-transport.md) → official Collector gRPC
receiver → maintained OTLP HTTP/protobuf exporter → a synthetic HTTP receiver.
The application owns both the disposable batch VM and the temporary Collector.
The library installs neither. This closes the transport route delta; G4 cloud,
backend API/UI, sustained load and destination attribute mapping remain separate.

## Published source and maintenance contract

The route uses official **exporter1.11.0**, published on2026-09-16 according to the
[Hex release API](https://hex.pm/api/packages/opentelemetry_exporter/releases/1.11.0).
Its tarball SHA256 is
`24833c5f54d0996a454793383a5a8526750cbacc5c03e5be54b593fe7d47fb0a`.
The runner verifies that checksum before extraction, without patching the source or
modifying ROOT's dependencies. SDK1.7.0, API1.5.0 and grpcbox0.18.0 come from the
physical freeze004. This receipt does not change the earlier stock HTTP1.10 red gate.

The converter `otel_otlp_traces:to_proto/2` is exported in a normal release and its
[signature is published in official HexDocs1.9](https://hexdocs.pm/opentelemetry_exporter/otel_otlp_traces.html).
Release1.11 retains its export and typed signature; its module `@doc` is empty and
there is no additional prose contract or stability guarantee for custom consumers.
Its source and `otel_otlp_common` are byte identical to receipt004's official pin.
The generated `opentelemetry_trace_service:export/3` has a documented client-module
and typed response contract in the release. Comparison with004 finds only the
removal of unused `export/2`; the used `export/3` is unchanged.
The recipe depends on these published interfaces, pins the tested release, and
must repeat a focused contract/route check when that dependency changes. It does
not claim that custom conversion has the same maintenance coverage as configuring
the stock exporter. Only the synthetic fixture calls upstream protobuf encode/decode
to inspect requests and fabricate responses; transport contains no private wire parser.

Collector core **0.162.0** comes from the
[official release](https://github.com/open-telemetry/opentelemetry-collector-releases/releases/tag/v0.162.0).
The Linux amd64 archive SHA256 is
`f99929987a915d3c6b2c9b15bc4938c5cea903a37a3f49e478024a0fa0772339`, matched against
its official release checksum file. The extracted binary SHA256 is
`910a66b1210e09143260914ef0634b4d234c789f23efc34bc9c7a3c0480324fa`; the launcher
verifies it on each invocation. This is checksum verification, not a claimed
Sigstore verification. The packaged recipe contains no downloaded binary.
It uses the current `otlp_http` component name, whose trace pipeline is maintained
by the [official OTLP HTTP exporter](https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector/v0.162.0/exporter/otlphttpexporter/README.md).

## Synchronous route and separate receipts

[collector.yaml](https://github.com/akorda-software/exagent/blob/main/examples/otlp_transport/collector.yaml) intentionally disables
the sending queue, retries and batch processor. An HTTP request runs in the gRPC
request's synchronous pipeline. A503 or HTTP deadline returns a failed callback;
adding a batcher or queue would change this ACK boundary and needs new acceptance.

The official exporter handles an HTTP OTLP partial response by logging a structured
warning with `dropped_spans`, then returning success. It does not propagate partial
rejection in the gRPC response. This is demonstrated in the fixture and supported by
the [pinned partial-success handler](https://github.com/open-telemetry/opentelemetry-collector/blob/v0.162.0/exporter/otlphttpexporter/otlp.go).
Collector log sampling is disabled so loss warnings are retained for this finite
profile. Its public metrics and log schema remain versioned operational interfaces;
see [internal telemetry](https://opentelemetry.io/docs/collector/internal-telemetry/).
The private probe reads public Prometheus scalar diagnostics and structured JSON
logs. Neither operation is an OTLP codec.

| Synthetic response for four spans | Host callback | Collector metrics | Backend fixture and loss evidence |
| --- | --- | --- | --- |
| 200/full | `exported=4`; gRPC `reported_accepted=4` | `sent=4`, receiver `accepted=4` | fixture declares4; no loss warning |
| 200/partial | `exported=4`; gRPC `reported_accepted=4` | same `sent=4` and receiver `accepted=4` | fixture declares3/rejects1; warning `dropped_spans=1` |
| 503 | `export_failed=4`; transport `unknown=4` | `send_failed=4`, receiver `refused=4` | fixture declares0; one HTTP request |
| held HTTP response past500ms | `export_failed=4`; `unknown=4` | same failure/refusal counts | fixture declares4 while holding its response; no qualified ACK |
| Collector stop with HTTP request active | `export_failed=4`; `unknown=4` | before stop: one in-flight request; final metrics unavailable | no fixture ACK; owned groups close |

Processor `accepted` means enqueue admission. Callback `exported` means successful
callback completion. `reported_accepted` describes the Collector's gRPC response,
not backend durability. `unknown` must not be converted into either rejection or
acceptance: the slow fixture shows why a destination might accept a request while
the sender times out. A partial loss count does not identify which spans were
rejected. These synthetic fixture declarations are not durable storage receipts.
An application should consume loss warnings before removing the private log and
keep them separate from `sent_spans`; metrics alone miss this partial rejection.

## Ownership, deadlines and bounds

[collector.py](https://github.com/akorda-software/exagent/blob/main/examples/otlp_transport/collector.py) is a single-threaded Linux
CLI owner. It directly spawns the verified binary in a new session, registers that
exact process group, and keeps its leader unreaped until signalling completes.
No kill target comes from process-list inspection or a PID supplied by another
application. Read-only `/proc` inspection verifies closure afterward. The supported
core pipeline has no process-execution components or OS children.

The host gets packet4 JSON `ready` and `closed` receipts of at most4,096 bytes and
sends a single packet4 `STOP\n` command. Owner EOF or SIGTERM also starts cleanup;
a finite lifetime catches forgotten normal shutdown. Stop sends SIGTERM only to
the registered group, waits at most2s, then sends SIGKILL to that still-owned group
and waits at most1s. Cleanup masks further termination signals, including a pending
owner signal immediately after registration. The controlled fault suspends that
same Collector before stop and proves escalation; it does not claim that the
Collector's normal Go shutdown was internally hung. `--fault` stays `none` in use.
Killing the CLI itself with uncatchable SIGKILL is outside its EOF/signal contract;
an external OS supervisor would need to own the whole job for that guarantee.

The default lifetime is10s, with permitted finite profiles100–30,000ms. Readiness
has a3s deadline and no restart loop. The test chooses ephemeral loopback gRPC and
metrics ports; no service, Docker container or existing infrastructure is changed.
Each instance writes one private JSON log capped at1MiB by its child process-local
file-size limit and the owner check. Reaching that limit ends the Collector; it is
not permission to discard loss records and claim ingestion success.

The host processor uses queue/batch capacity4. The004 shared atomic gate admits
one private batch VM, with at most8 spans and65,536 uncompressed ETF bytes;010 sends
four spans/batch. SDK limits are64 attributes/span,128 string characters,8 events,
4 links and16 attributes/event or link, with content recording disabled. The
Collector receives at most1MiB per gRPC message and one stream per connection.
Concurrency1 is the shared gate's contract for this trusted host/client profile,
not a server-wide bound on arbitrary other loopback clients. No exporter sending
queue or asynchronous batch buffer is added. HTTP timeout500ms < RPC deadline1,200ms
< VM deadline2,000ms < processor timeout4,000ms. The maintained HTTP response reader
limits its response body to64KiB before OTLP response decoding.

`GOMAXPROCS=2`, `GOMEMLIMIT=96MiB` and the128MiB memory limiter constrain this profile;
they do not promise a hard RSS or general predecode-allocation bound. The host's
conversion still precedes its ETF admission check, as recorded in004. A disposable
BEAM per batch plus a Collector process, binary checksum pass, metrics scrape and
log collection have operational cost. This recipe is optional and demonstrated
for small finite batches; high-throughput or permanent services are not qualified.

## Reproduction and evidence

The checkout runner `test/support/otlp_transport/run_collector.py` defaults to
skip before source/artifact/configuration access. Opt in with explicit freeze004,
official downloaded artifacts and tooling directories. Its private consumer is a
physical copy, including only validated private build links; it never reads or
builds ROOT's current `_build`. It copies no `.env`. The runner verifies archive
checksums, replaces only that copy's exporter with the published release, compiles
that dependency and performs the route delta. It does not repeat004's C7 or fault
matrix, and the historical freeze is not the evolving final candidate.

```sh
python3 test/support/otlp_transport/run_collector.py --run \
  --freeze /path/to/private/freeze004/project \
  --artifacts /path/to/verified/artifacts \
  --work /path/to/private/otlp-work \
  --elixir-bin /path/to/elixir/bin \
  --erlang-bin /path/to/erlang/bin \
  --rebar3 /path/to/official/rebar3
```

The artifacts directory contains `provenance.json` with the receipt's official URLs
and `downloads/otelcol_0.162.0_linux_amd64.tar.gz` plus
`downloads/opentelemetry_exporter-1.11.0.tar`. The current runner expects this
verified Linux amd64 profile. A consumer application can instead compile the
packaged callback into its own app, supply a physical official1.11 code path to
the private VM, launch `collector.py` with its own trusted config/log/HTTP endpoint,
and set the returned loopback gRPC port in the callback's transport config.

The checkout receipt010 `test/support/otlp_transport/receipt-collector-2026-10-01.json`
records consumer `/tmp/opencode/exagent-v2-codex-t6qgpstl/otlp/route-5o5vpw05/project`.
Collector version, release dependency compile, private app compile with
`--warnings-as-errors`, owner/lifecycle controls and native route probe all exited0.
Elixir1.20.0/OTP29.0.5 were used. The incremental release/app/run logs have zero
warning lines; this reuses004's compiled graph and does not claim that its previously
recorded upstream full-build warnings disappeared. Mix/Hex/Rebar directories are
private and `ERL_FLAGS` supplies an Erlang `-home`; neither `HOME` nor `CODEX_HOME`
is assigned. The corrected historical runners receive no new attribution for004.

The native HTTP body is4,447 bytes and trusted request ETF10,069 bytes. The fixture
asserts protobuf booleans true/false, IDs/parentage, one run/two model/one tool spans,
two model calls/one effect, usage counters and absent content sentinels. Every case
has exactly one HTTP request, confirmed after terminal counters and a150ms quiet
window. Three post-warm cycles retain identical gauges:183 processes,76 ETS tables,
3 ports,44 monitors,39,206 atoms and2 httpc profiles. Their times after the HTTP
barrier through terminal cleanup were198/210/208ms; these exclude startup before
that barrier. All three owned OS leaders and exporter guard/worker/lease close per
cycle, and all Collector groups close. The separate controls prove owner EOF
(stop9ms), lifetime (stop18ms) and suspended stop (escalated318ms, child exit-9).

For a later Langfuse wave, a consumer-owned private config can use the maintained
HTTP exporter's `headers` setting. The current
[Langfuse OTLP documentation](https://langfuse.com/integrations/native/opentelemetry)
specifies an HTTP traces endpoint ending `/api/public/otel/v1/traces`, Basic auth,
and the `x-langfuse-ingestion-version: 4` header for its current v4 ingestion model.
This lot reads no credentials, constructs no authorized cloud configuration and
sends no cloud data. The later wave must qualify the actual destination/version,
loss evidence and backend API/UI trace IDs. A synthetic ACK or a Collector warning
cannot substitute for that acceptance.
