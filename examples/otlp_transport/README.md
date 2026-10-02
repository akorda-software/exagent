# Application-owned isolated OTLP recipe

These optional files ship in ExAgent's existing `examples` package. They are not
compiled into the library or installed as its default exporter. See the complete
[ownership/limits contract](../../docs/development/otlp-isolated-transport.md).

The native `OTLPTransportProbe.IsolatedExporter` callback requires an application-owned
SDK and official exporter **1.11.0**, with the published gRPC client available in its
physical child code path. Objective004's historical receipt used official commit
`9cb8b3627cf68aeb0df7b3243378f0c2520cff66` before that release; objective010 verifies
the published release and the same converter/client contract. The earlier stock1.10
HTTP exporter is not the implementation of this recipe. The converter has a
published signature, with the [maintenance boundary](../../docs/development/otlp-collector-transport.md)
recorded separately from supported stock-exporter configuration.

Before SDK initialization, the host supplies trusted
`:otlp_isolated_probe, :transport` configuration: a loopback gRPC `:port`, diagnostic
`:observer` PID, shared `:gate` from `:atomics.new(1, signed: false)`, absolute
`:python`/`:elixir` executable paths, `:launcher`/`:worker` file paths and a private
`:beam_path` glob. It compiles the callback into its own application and configures
the existing bounded processor with `{OTLPTransportProbe.IsolatedExporter, %{}}`.
The optional callback profile permits finite `:deadline_ms` and `:rpc_deadline_ms`;
`:fault` is a synthetic test control and stays `"none"` for normal use.

An explicit application profile may additionally supply `:request_profile`, a
module with `project/1`, in that trusted transport configuration. It transforms
the published converter's map before the existing span/ETF bounds and generated
gRPC client. The default is identity. It must preserve identities, parentage,
names, timestamps and statuses; this hook supplies no private SDK record or wire
codec. The checkout Opik acceptance profile uses its documented `opik.metadata`
prefix to keep native diagnostics out of input/output and preserve resource
scalars. ExAgent core does not emit backend-specific attributes.

The host owns SDK metadata/queue limits and receives scalar diagnostic receipts.
The gate must be shared by every instance that belongs to that transport budget.
Gate closure is verified before reuse; an unverified cleanup leaves admission
closed. A Linux launcher creates/reaps only its own VM group, so a hung dependency
shutdown does not extend the host callback's wait indefinitely.

Use the opt-in checkout runner `test/support/otlp_transport/run_isolated.py`
from the source repository for the actual run/tool and persisted approval/resume
matrix. Tests and receipts are intentionally outside the packaged recipe. gRPC
loopback evidence does not qualify Langfuse HTTP or backend API/UI.

The optional [Collector bridge](../../docs/development/otlp-collector-transport.md)
adds `collector.py` and `collector.yaml`. It owns a checksum-verified official
Collector0.162.0 process, binds gRPC and metrics to ephemeral loopback ports, and
forwards traces using maintained OTLP HTTP/protobuf without a queue, asynchronous
batcher or retries. The CLI sends packet4 JSON ready/closed receipts; the host sends
one packet4 `STOP\n` command or closes its owner pipe. Normal applications keep
`--fault none`. The supervisor has a finite lifetime and escalates stop only against
the process group it created and registered.

The bridge receipt proves synthetic HTTP success, partial rejection, error, timeout
and cleanup. A partial HTTP response produces an unsampled structured Collector
warning even though its gRPC ACK is successful. The host must read those operational
loss events alongside terminal metrics and later backend receipts. `exported` and
`sent_spans` do not mean that a backend durably ingested every span. The optional
recipe ships no binary, credential, service or automatic backend ingestion.
