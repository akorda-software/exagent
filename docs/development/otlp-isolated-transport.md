# Native OTLP: application-owned VM per batch

## Published stock HTTP extension — October 3

The packaged recipe now also supports `protocol: :http_protobuf` with the published
exporter1.11, SDK1.7 and API1.5. Use `examples/otlp_transport/vm_http_worker.exs`
as the worker. In the application-owned `:otlp_isolated_probe, :transport` config,
set `http_options` with the public signal-specific configuration:

```elixir
%{
  protocol: :http_protobuf,
  http_options: %{
    otlp_traces_endpoint: "https://collector.example/v1/traces",
    otlp_traces_headers: [{"authorization", "host-private-value"}]
  }
}
```

This is the HTTP part of the transport map; also supply the launcher, worker,
runtime paths, observer, gate and port fields described below. `port` remains a
launcher validation field; the actual HTTP address is the complete traces URL.
The child sets these values only in its own OTP application environment, then
calls the native exporter's public init/export/shutdown callbacks. Generic
`endpoints` would append a signal path; this recipe uses the specific endpoint to
preserve it. Optional ssl_options and otlp_traces_compression are allowed. A gRPC
request_profile projection is not admitted on this native HTTP route.

The host sends the native exporter callback's SDK table entries and opaque
resource through its own bounded IPC. Native records can contain symbols created
by host instrumentation, so HTTP ETF decoding admits those symbols **only in the
owned disposable VM**, within the65,536-byte packet limit. Never feed this worker
stored/network ETF or expose its stdin externally. No callback/module is selected
from span data. Existing gRPC converter-map IPC retains safe decode. The recipe
does not implement an OTLP encoder/parser or persist runtime terms.

Every outcome reclaims the registered VM group, including profiles, held HTTP
requests, sockets and that VM's atoms. This does not repair shutdown in an
in-process stock exporter or touch the host's inets service. Three healthy cycles
and held-POST deadline/owner-death controls verify the actual wire and OS closure.
These controls use the published stock callback, not a custom exporter stub.

Stock HTTP ignores the response body, including partial_success. Its2xx callback
result means transport_ok; receipts report0 spans known accepted and all sent spans
unknown. The same remains true for a synthetic partial response. HTTP errors and
deadline/owner death fail without automatic replay. Separate backend API/UI
receipts are required to prove ingestion. The existing finite limits, one-VM gate,
Linux ownership and startup overhead below still apply; this is not a high-rate
default transport. The earlier receipts and gRPC results remain identified below.

This continues objective004. It preserves the earlier [gRPC experiment](otlp-transport.md)
and its receipt. It does not change ExAgent defaults, dependencies, the root build,
the version, or release acceptance. The new consumer physically freezes source and
builds elsewhere; that snapshot is evidence, not the evolving final candidate.

## Ownership and public interfaces

The maintained upstream pin remains official commit
`9cb8b3627cf68aeb0df7b3243378f0c2520cff66`, exporter **1.11.0 pre-release**,
with SDK1.7.0/API1.5.0/grpcbox0.18.0. The application implements the public
`otel_exporter_traces` callback. Conversion uses documented
`otel_otlp_traces:to_proto/2`; transmission uses the documented generated
`opentelemetry_trace_service:export/3` gRPC client and public channel APIs.
The application's transport does not call the private protobuf encoder or decoder.
Only the synthetic receiver registers the upstream generated protobuf service.

This describes the source of receipt004. The later
[Collector route010](otlp-collector-transport.md) uses published exporter1.11.0,
verifies identical converter source and the same `export/3`, and records the
converter's published-signature maintenance boundary. Receipt004 and its original
source hashes remain historical evidence.

The host converts a native SDK batch, checks cardinality and the serialized term
budget, and hands one trusted local ETF term to a launcher through packet framing.
This IPC is not an OTLP encoder or parser. Safe ETF decode admits existing atoms;
the child loads the public converter modules before decoding. Both processes are
application-owned and use a physical private code path, without ROOT symlinks.

The launcher creates a new OS session/process group and records its directly spawned
leader before unmasking termination signals. It never obtains a kill target from
`/proc`, a port diff, or another BEAM. Deadline, owner pipe closure, and cancellation
all kill only that registered group. Its leader remains unreaped until that kill,
preventing PID reuse before signalling. A process-local Linux subreaper then waits
for its own adopted descendants, including runtime helpers; no global service or
host setting changes. This uses the documented
[Linux subreaper API](https://man7.org/linux/man-pages/man2/PR_SET_CHILD_SUBREAPER.2const.html).

A host guard monitors the exporter worker and owns the launcher port. A separate
finite lease watcher keeps admission closed until verified closure. All callbacks
using the same application-supplied atomic gate share a maximum of one live batch
VM. A killed exporter worker cannot admit another VM while the old guard cleans
up. If closure cannot be verified, the gate stays closed and its watcher terminates;
later batches are dropped in admission. Reopening requires the application to audit
its own transport ownership and replace the gate. This is a fail-closed transport,
while application runs can continue.

`grpcbox_channel:stop/2` still calls upstream `gen_statem:stop(..., infinity)`.
The lifetime boundary is now the owned OS group, so host cleanup need not wait for
that dependency call. The controlled shutdown test suspends the recipe's own
shutdown task inside its private VM, before its public stop call; it then proves
group reclamation with that task pending. **It does not reproduce an internal
grpcbox hang.** `:sys.suspend(channel)` was discriminated and discarded as a fault
control because OTP system stop still terminates a suspended gen_statem.

## Finite profile and observations

The declared transport profile admits 1–8 spans and at most65,536 bytes of uncompressed
ETF. The run/tool matrix uses queue/batch capacity4, the C7 scenario capacity8.
IPC receipts are at most4,096 bytes; stderr is drained and discarded with a capped
byte counter. Child writes and reads are nonblocking and share a finite launcher
deadline. Normal batch deadline is2,000ms; permitted profiles are100–5,000ms.
The host callback wait is batch deadline+1,500ms. Guard and lease waits are finite;
the isolated test's held child fallback is10s and is reclaimed by its launcher first.

The private consumer supplies standard SDK environment limits:64 attributes/span,
128 string characters,8 events,4 links,16 attributes/event or link. The SDK's string
limit counts characters, not UTF-8 bytes; this profile exports bounded ASCII metadata
and disables conversational content. Export admission counts actual ETF bytes.
The checked native fixture has four spans/run: one run, two model calls, one tool.
Resource booleans retain protobuf `bool_value=true/false`, with the earlier experiment
also covering native span booleans. Logical IDs, parentage, usage and privacy are
asserted at the actual receiver, through the public gRPC client.

The matrix covers full success, partial rejection, transport error, RPC timeout,
owned shutdown task pending, VM deadline, exporter-worker timeout, and killed port
guard. A second actual ExAgent run/tool finishes during each held batch and generates
four queue-full drops. In the worker-timeout control a third run finishes while the
old guard is suspended: its new batch is dropped in transport admission, with no
second VM. Resuming the guard closes the original group and releases admission.
Three additional host cycles compare process, ETS, port, monitor, atom and httpc
gauges after warming the transport and diagnostic paths.

C7 uses its own ephemeral ETS Store and public model-codec callbacks. A paused run
persists its cursor and pending approval without executing the tool. Approval and
resume use a fresh Test model; the codec restores its cursor, so total execution is
two model calls and one effect. Both attempt run spans close, carry distinct attempt
IDs and the same logical run/record IDs, and the paused span has no error status.
Raw prompt, argument, output, actor and authorization sentinels must be absent from
the exported spans. This proves the native synthetic path with ephemeral storage;
it does not prove database durability or restart of a different host VM.

Counters are separate: processor `accepted` means enqueue admission, `exported` means
successful callback completion, `dropped_queue_full` means local queue loss. Transport
`reported_accepted` and `rejected` summarize a received peer response; `unknown`
means no qualified response. Transport admission drops have `sent=0`, `unknown=0`.
A partial response returns `failed_not_retryable` for the whole callback even when
it reports some accepted spans. Worker/guard death and a late peer reply cannot turn
an expired callback into success. None of these counters proves durable backend
ingestion, billing, or an API/UI trace.

Upstream protobuf decoding still occurs before the response term-size check; this
recipe does not promise a predecode RAM bound. A valid oversized SDK batch can also
allocate its public conversion before the local byte check. The demonstrated finite
postconversion profile and complete reclamation of the owned VM are separate claims.

## Reproduction and operational cost

Run `test/support/otlp_transport/run_isolated.py` from the checkout with `--run`
and the same explicit tooling arguments as the earlier recipe's README. Without
`--run` it returns before filesystem/configuration/network/build access. It copies
lib, config, mix/lock and required README/license plus dependency source; rejects
symlinks; checks freeze hashes before/after copying; and records every source file in
`freeze.json`. No `.env`, root `_build`, global Hex archive or consumer is modified.
Fresh commands/logs, compile warnings, source identities and transport measurements
belong to its private output directory and the new receipt.

The final checkout receipt `test/support/otlp_transport/receipt-isolated-2026-10-01.json`
records private consumer
`/tmp/opencode/exagent-v2-codex-t6qgpstl/otlp/isolated-ciq3m0_l/project`.
`mix deps.get`, `mix compile --warnings-as-errors` and `mix run --no-start
isolated_probe.exs` each exited0. Default skip, Python syntax and standalone Elixir
format checks also exited0. The recipe and probe hashes match their actual private
copies. Freeze manifest:1,538 source files,
SHA256`166e72fe592d2c2149aa44abda995d5866026cfa1de87fb32d1a4af71ee3ca0a`.
Elixir1.20.0/OTP29.0.5 were used. Existing upstream compile diagnostics remain:
50 warning lines in compile and41 replayed warning lines in the probe invocation
(Toml, gproc, Makeup, ExDoc, WebSockex and the deprecated Mix xref option).
The application recipe compiles without its own warnings; no upstream warning was
suppressed or patched.

After receipt004, `run.py` and `run_isolated.py` were corrected to avoid assigning
`HOME` or `CODEX_HOME`. Git uses explicit `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`;
Mix/Hex/Rebar use private task directories and Erlang gets a private `-home` through
`ERL_FLAGS`. The old receipt is not attributed to these changed runner bytes and its
matrix was not repeated for the tooling change. Route010's private release compile
and owner/lifecycle checks exercise the corrected environment causally.

Final recurring gauges were187 processes,89 ETS tables,3 ports,50 monitors,
40,235 atoms and2 httpc profiles, unchanged across all three measured cycles.
Their elapsed batch/cleanup times were432/427/425ms. Each matrix run/tool request
carried4,448 protobuf bytes and10,072 ETF bytes. Full success response:0 protobuf
bytes; partial rejection:25 protobuf bytes and85 bytes of Erlang external term.
C7 exported3 paused and3 resumed spans, with its own Store removed after verification.
The worker-timeout case recorded four additional admission drops while its old VM
was still owned, without creating another VM. Read-only OS identity checks and the
verified launcher receipt distinguish reclaimed owned leaders from host gauges.

A disposable VM imposes one BEAM/launcher startup per exported batch. Local measured
success batches have been around400–450ms including cleanup, with a2s guard-death
fallback; final receipt measurements are authoritative. This is a deliberate
application-level recipe for a low-throughput bounded profile. It is not installed
in ExAgent core, recommended as a universal default, or qualified for high-rate
export/large metadata. A permanent owner VM would need its own public control and
recovery contract and has not been implemented in this objective.

The endpoint here is gRPC loopback. Langfuse's HTTP-only route is **not** qualified
by this receipt. An application-owned maintained Collector could bridge gRPC→HTTP,
but its ACK would acknowledge the Collector, not Langfuse. Collector-side partial
rejection/loss metrics, final HTTP/backend response, and backend API/UI evidence
would still be separate acceptance requirements. No Collector infrastructure or
cloud ingestion was created during this lot.

Objective010 subsequently qualifies a temporary application-owned Collector against
a synthetic HTTP receiver, with separate ACK, loss and finite-stop evidence. Its
[own receipt and limits](otlp-collector-transport.md) do not replace this gRPC receipt
or qualify cloud/backend API/UI acceptance.
