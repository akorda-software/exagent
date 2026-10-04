# ExAgent 2.0.0

ExAgent2 consolidates the agent loop, supervised conversations, multi-agent
coordination and durable human approval into one framework using official
ReqLLM1.26. Applications own their effects, persistence and observability services.

- One-shot and streaming runs with validated tools, structured Ecto output,
  explicit capabilities and bounded host retention/accounting.
- Stateful supervised agents and coordinated sessions, composition and delegation.
- Durable snapshots and persisted approval/continuation with explicit recovery,
  authority checks and protection against unintended effect replay.
- Qualified OpenRouter tool routing and application-defined shared-state codecs.
- Opt-in OpenTelemetry tracing and metrics. ExAgent is the span producer for its
  runs; ReqLLM metadata supplies usage without duplicate model spans.
- MCP, Phoenix/LiveView, Oban and PostgreSQL integration recipes, with human and
  agent documentation generated from the same source.

This is a major upgrade. Read the
[migration guide](https://hexdocs.pm/exagent/2.0.0/migration.html) before updating
an application. Supported runtime combinations are Elixir1.18/OTP28 and
Elixir1.20/OTP29; provider capability profiles remain explicitly qualified.

Acceptance includes the2,235-case offline runtime receipt, scoped real-model and
complex consumer flows, PostgreSQL recovery, clean installed package contracts,
and equivalent finite native/API/UI acceptance for Langfuse and Opik. These
receipts have different dates and scopes; publication does not repeat them or
turn exclusions into passes. See
[support status](https://hexdocs.pm/exagent/2.0.0/status.html) for exact evidence.

The final October4 envelope-guidance and incomplete-response failure-cause
adjustments pass159 focused offline cases together. The earlier complete-suite
receipt predates those two changes; caller history, tool validation, effect
authority and retention ceilings remain intact.

Known limits remain explicit: stock TOML/WebSockex/gproc compiler diagnostics,
qualified provider profiles, normalized rather than invoiced usage, and no
upstream hard RAM bound before decoding. Direct native in-process OTLP HTTP has
a cleanup limitation; use the qualified application-owned disposable-VM or
Collector recipes when that transport is required. There is no fork, patch or
unsupported dependency override. See
[known limits](https://hexdocs.pm/exagent/2.0.0/known-limits.html).

Install after publication with `{:exagent, "~> 2.0"}`. Package and versioned
documentation are published automatically from this official GitHub release.
