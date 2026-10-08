# Supported features and limits

ExAgent 2.1 is published on [Hex](https://hex.pm/packages/exagent/2.1.0).
Its runtime targets are Elixir 1.18 / OTP 28 and Elixir 1.20 / OTP 29.
The general model backend uses official ReqLLM 1.27; applications may implement
`ExAgent.Model` for a different adapter.

## Select the capability you need

| Capability | Configuration | Boundary |
|---|---|---|
| Text generation | `Model.resolve/2` or `Models.ReqLLM.new/1` with credentials | Resolving a catalogue identity does not enable tools or streaming. |
| Chat tools and streaming | `tool_profile: :chat_tools_v1` and truthful Chat capability metadata | Requires a compatible non-reasoning Chat endpoint and the mandatory argument envelope. |
| OpenRouter tool routing | `tool_profile: :openrouter_chat_tools_v1` | Provider routing and reasoning mode are bound to the conversation. |
| Native JSON Schema output | `output_profile: :chat_json_schema_v1`, `output_mode: :native` | Non-strict remote schema; local Ecto validation remains authoritative. The routed OpenRouter tools profile does not enable this output profile. |
| Deterministic local runs | `model: "test"` or `%Models.Test{script: ...}` | Exercises the agent loop without interpreting prompts or calling a provider. |
| Skills | `ExAgent.new(skills: ExAgent.Skills.from_dir!(dir))` | Agent Skills `SKILL.md` subset; trusted host content; scripts are never executed. |
| Stateful conversations | `AgentSupervisor` and `Server` | Queue admission is volatile; the application handles backpressure. |
| Shared-state coordination | `Session`, `Composition`, `Flow` | Trusted host definitions, explicit ownership and bounded branches. |
| Conversation checkpoints | `Store.ETS` or `Store.Postgres` | ETS is ephemeral. PostgreSQL requires the application's Repo and database lifecycle. |
| Persisted approval | `Continuation`, a scoped Store, bindings and an authorizer | Approved boundaries can resume; uncertain external effects need explicit reconciliation. |
| MCP tools | stdio or Streamable HTTP | HTTP requires an application-owned HTTP1-only Finch pool. |
| Traces | Native OpenTelemetry instrumentation and the optional ReqLLM bridge | The host owns SDK/exporter; content is off by default. |
| Metrics | Opt-in ReqLLM bridge with experimental API/SDK 0.6 and a reader | Fixed instruments and bounded model labels; metric destination is separate from trace ingestion. |

Capability declarations configure admission; they cannot prove a particular
provider follows the contract. Verify your exact model, endpoint, routing and
options before relying on tools, streaming or native output in production.
Unrepresented reasoning, modality or provider-block combinations reject
explicitly instead of silently falling back.

## Accounting and effects

Host request/tool counters count admissions. Token values have declared
normalized or reported quality; cost is an estimate in cents. Missing usage or
price is unknown rather than zero. A limit checked after a response is not an
invoice ceiling for work already in flight. Parent totals include their children.

A timeout, cancellation, lost storage acknowledgement or process death cannot
prove an external effect did not happen. Checkpoint retry saves the same state;
it does not rerun a model or tool. For an uncertain effect, reconcile its actual
outcome before granting another execution attempt.

## Resource boundaries

Run deadlines and request/tool limits control owned admission. Host response and
history retention limits apply after stock decoding; there is no upstream hard
RAM bound before materialization. Compaction reduces the next request context,
not the canonical persisted history. Arbitrary application callbacks and
external systems have their own resource and cancellation contracts.

Flow permits at most 32 branches/concurrent workers, separate 64 KiB branch/merge
JSON bounds and an 8 MiB journal. Fail-fast cannot undo a sibling's completed effect.
See [Coordination](coordination.md) for construction and failure policy.

## Observability transport

Langfuse and Opik receive native spans through the application's OTLP exporter.
Default empty input/output previews indicate disabled content capture; inspect
attributes for IDs, status and accounting. Exporter callback success and an HTTP
2xx do not prove every span was retained by the destination.

Direct native OTLP HTTP can retain exporter-owned profiles, atoms and active
sockets after timeout/shutdown. For bounded transport ownership, use the
[disposable VM](../development/otlp-isolated-transport.md) or
[Collector](../development/otlp-collector-transport.md) recipe.
A finite processor restart budget limits recreation but does not repair cleanup.
See [Observability](observability.md) for authentication, privacy and lifecycle.

## Dependency diagnostics

Some stock TOML, WebSockex and gproc dependencies emit compiler diagnostics.
Functional operation and a warning-free dependency graph are different properties.
ExAgent uses official dependency releases; applications should review their
chosen graph and avoid treating suppression as a repair.
