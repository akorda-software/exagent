# Application-owned isolated OTLP transport

These optional files ship in ExAgent's `examples` directory. The application
compiles and configures the callback; it owns the SDK, exporter and child process.
They are not compiled into ExAgent or installed as its default exporter.

Read the [isolated transport guide](../../docs/development/otlp-isolated-transport.md)
for configuration, process ownership, batch bounds and shutdown behavior.

| File | Purpose |
|---|---|
| `isolated_exporter.ex` | `OTLPTransportProbe.IsolatedExporter` callback for the bounded processor. |
| `vm_launcher.py` | Linux owner of a disposable Elixir VM and its process group. |
| `vm_worker.exs` | Native OTLP/gRPC export using the official exporter. |
| `vm_http_worker.exs` | Native OTLP/HTTP export using the official exporter. |
| `collector.py`, `collector.yaml` | Optional finite Collector bridge from gRPC to HTTP/protobuf. |

The child code path requires the official OpenTelemetry exporter 1.11.0 and its
dependencies. Supply trusted absolute paths, a shared admission gate, an observer
PID and the selected worker in `:otlp_isolated_probe, :transport` before initializing
the SDK. HTTP uses an explicit endpoint; gRPC uses a loopback port. Keep synthetic
fault injection disabled in applications.

Each batch has finite size, admission and deadline bounds. The launcher terminates
and reaps only its own VM group. If cleanup cannot be confirmed, admission stays
closed. A successful callback reports transport success; it does not guarantee
durable ingestion of every span. Reconcile loss, partial rejection and unknown
outcomes using operational diagnostics and the destination backend.

The optional [Collector bridge](../../docs/development/otlp-collector-transport.md)
requires an application-supplied, checksum-verified official binary. It runs without
an asynchronous batcher, queue or retries and has a finite lifetime. The recipe
ships no binary, credential, service or automatic backend configuration.
