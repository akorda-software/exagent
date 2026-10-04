# OTLP through an application-owned exporter VM

The packaged `examples/otlp_transport/` recipe runs one disposable BEAM VM per
small batch. The application owns the callback, launcher and child code path.
It provides a finite transport lifetime when a native in-process exporter cannot
reclaim HTTP profiles, sockets or atoms after timeout/shutdown.

This is an optional Linux recipe with startup overhead, not ExAgent's default
exporter or a high-throughput permanent service.

## Prepare the files and runtime

Compile `isolated_exporter.ex` into your application. It defines the native
`OTLPTransportProbe.IsolatedExporter` callback. Keep `vm_launcher.py` and the
chosen worker in trusted application paths:

| Transport | Worker | Destination |
|---|---|---|
| Native HTTP/protobuf | `vm_http_worker.exs` | Full OTLP traces URL. |
| gRPC | `vm_worker.exs` | Trusted gRPC receiver, including the optional Collector. |

Supply Python 3, Elixir and a physical child BEAM code path containing official
exporter 1.11, SDK 1.7, API 1.5 and their dependencies. The child must be able to load
the same public native record/converter/client interfaces as the application.
The recipe does not download or patch dependencies automatically.

## Configure an HTTP batch

Before starting the SDK, construct trusted transport configuration. The
`observer_pid` below is an application-owned process that consumes diagnostic
messages; keep it alive for the transport lifetime.

```elixir
gate = :atomics.new(1, signed: false)

transport = %{
  python: "/app/runtime/python3",
  elixir: "/app/runtime/elixir",
  launcher: "/app/otlp/vm_launcher.py",
  worker: "/app/otlp/vm_http_worker.exs",
  beam_path: "/app/_build/prod/lib/*/ebin",
  observer: observer_pid,
  gate: gate,
  port: 4317,
  protocol: :http_protobuf,
  http_options: %{
    otlp_traces_endpoint: "https://collector.example/v1/traces",
    otlp_traces_headers: trusted_headers
  }
}

Application.put_env(:otlp_isolated_probe, :transport, transport)
```

Replace paths/URL with your deployment's values. HTTP `port` is a launcher
validation field; the full `otlp_traces_endpoint` controls the actual address.
Allowed HTTP options are endpoint, headers, compression and `ssl_options`.
Do not supply the gRPC `request_profile` projection on this HTTP route.

Configure your `BoundedProcessor` exporter as:

```elixir
exporter = {OTLPTransportProbe.IsolatedExporter,
  %{deadline_ms: 2000, rpc_deadline_ms: 250}}
```

Put that tuple in the processor's `exporter:` field from
[Observability](../guides/observability.md). Credentials are resolved through
trusted transport configuration, outside SDK bootstrap options and span data.

## Use gRPC when needed

Choose `protocol: :grpc`, use `vm_worker.exs`, and supply the receiver's loopback
`port`. The callback converts native SDK table/resource values through the public
`otel_otlp_traces:to_proto/2` interface; the child uses the published generated
gRPC `export/3` client. The application owns keeping those versioned interfaces
compatible when updating its exporter dependencies.

An optional trusted `request_profile:` module implements `project/1` on that
public converter map before admission. Use it for application-specific destination
attribute mapping while preserving IDs, parentage, names, timestamps and statuses.
It is not a module selected from span data or a private wire parser.

## Bound admission and lifetime

The shared atomic gate admits at most one live batch VM for that transport budget.
Each batch permits 1–8 spans and at most 65,536 uncompressed ETF bytes.
Receipts are at most 4,096 bytes. Conversion and upstream decoding can allocate
before the byte checks; those are not hard predecode RAM limits.

The batch deadline is 100–5,000 ms; the default is 2,000 ms. The host waits at most
the deadline plus 1,500 ms. Keep `fault: "none"` for application use. The launcher creates
and registers its own OS process group before unmasking termination signals.
Deadline, cancellation or owner-pipe closure reclaims only that owned group.
It never obtains a kill target from another process or an unrelated PID.

The gate reopens only after verified closure. If closure cannot be established,
admission stays closed and later batches drop. The application audits that
ownership condition before replacing the gate. Reclamation removes resources
and atoms inside the child VM; it does not repair an in-process stock exporter
or touch the host's shared HTTP services.

The HTTP worker decodes trusted native terms only inside the disposable VM.
Never expose its stdin to a network or feed it stored/untrusted ETF.

## Interpret outcomes

The observer receives `{:isolated_receipt, map}` and lifecycle messages.
Processor enqueue/callback counters and transport outcomes are different:

- `sent` counts dispatched spans.
- `reported_accepted` and `rejected` describe an available peer response.
- `unknown` records spans whose acceptance cannot be established.
- Admission failure sends no batch; it must not be counted as remote rejection.

Stock HTTP ignores the successful response body, including `partial_success`.
A 2xx callback means transport success while span acceptance stays unknown.
A gRPC partial response fails the callback without automatic replay even if
some spans were reported accepted. A late reply cannot revive an expired callback.
Query the destination separately to establish actual ingestion.

For a gRPC-to-HTTP bridge, use the [application-owned Collector](otlp-collector-transport.md).
