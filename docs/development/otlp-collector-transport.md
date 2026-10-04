# OTLP through an application-owned Collector

This optional route connects native ExAgent spans to an OTLP HTTP destination:

```text
Application SDK → isolated batch VM → Collector gRPC → OTLP HTTP/protobuf backend
```

The application owns both the [batch VM](otlp-isolated-transport.md) and Collector.
ExAgent does not install a Collector, download its binary or start a service.

## Prepare the Collector

The packaged `examples/otlp_transport/collector.py` supports official core
Collector 0.162.0 on Linux amd64. Obtain it from the
[official release](https://github.com/open-telemetry/opentelemetry-collector-releases/releases/tag/v0.162.0).
The owner validates the extracted binary SHA256 before each start:

```text
910a66b1210e09143260914ef0634b4d234c789f23efc34bc9c7a3c0480324fa
```

Use the packaged `collector.yaml` as the finite synchronous pipeline. Supply
an application-owned log path and trusted destination. The owner command accepts:

```bash
python3 /app/otlp/collector.py --run \
  --binary /app/otlp/otelcol \
  --config /app/otlp/collector.yaml \
  --log /app/private/collector.jsonl \
  --http-endpoint https://collector.example/v1/traces \
  --lifetime-ms 10000
```

The application launches it through an owned pipe/port and consumes packet4
JSON messages, rather than treating it as a detached daemon. A `ready` message
returns the loopback gRPC and metrics ports. Use that gRPC port in the isolated
exporter's transport configuration. Optional `--grpc-port` and `--metrics-port`
select explicit distinct ports; otherwise ports are selected dynamically.

Configure destination authentication in the application's private Collector
configuration according to [Observability](../guides/observability.md).
The supplied owner uses an explicit child environment; do not assume arbitrary
host environment variables or credentials are inherited.

## Keep the acknowledgement boundary explicit

The supplied pipeline disables the sending queue, automatic retries and
asynchronous batching. HTTP runs in the synchronous gRPC request path.
Adding a queue/batcher changes what a successful callback acknowledges.

The maintained HTTP exporter can return success while recording an OTLP partial
rejection as a structured `dropped_spans` warning. Consume the Collector's public
metrics and loss logs alongside the host callback outcome; `sent_spans` alone
does not establish full backend acceptance.

| Outcome | Application interpretation |
|---|---|
| Successful callback | Collector transport response succeeded; destination durability still needs checking. |
| Partial rejection warning | Some spans were rejected even when the callback succeeded. |
| HTTP failure or timeout | Acceptance is unknown; do not infer every span was rejected. |
| Collector stop with a request active | Reconcile loss/unknown acceptance independently of process cleanup. |

Processor `accepted` means enqueue admission and `exported` means successful
callback. Neither is a durable ingestion receipt. Query the backend when your
application needs to establish which observations arrived.

## Own shutdown and resources

Send a packet4 `STOP\n` command or close the owner pipe when finished.
SIGTERM and the finite lifetime also trigger cleanup. The owner signals only
the process group it spawned and registered, keeps its leader unreaped during
signalling and escalates from SIGTERM to SIGKILL within finite waits.
Keep `--fault none` for ordinary use. Uncatchable SIGKILL of the owner itself
requires an external supervisor that owns the complete OS job.

Supported lifetime is 100–30,000 ms, with a default of 10,000 ms. Readiness has a 3 s
deadline and no restart loop. Logs are capped at 1 MiB; reaching the cap ends the
Collector instead of silently hiding loss records. The gRPC receiver admits
at most 1 MiB per message and one stream per connection in this supplied profile.

The shared batch gate limits the trusted client to one VM and small batches.
It does not provide a server-wide limit against unrelated clients. SDK attribute
and queue limits, child VM lifetime and Collector memory settings are separate
resource controls. `GOMEMLIMIT` and a memory limiter are not hard RSS guarantees.

A disposable BEAM plus Collector startup, checksum verification and diagnostic
collection have overhead. This recipe targets finite batches; applications with
a permanent high-rate collector deployment should own and verify that deployment's
queueing, loss, authentication and shutdown contracts separately.
