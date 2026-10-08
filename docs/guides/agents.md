# Integration notes for coding agents

This is a compact entry point for agents implementing an **application using
ExAgent**. It describes public APIs, result shapes and application responsibilities.

## Read only what the task needs

1. Check [Supported features and limits](support.md) and the application's dependency version.
2. Read [Getting started](getting-started.md) for the result and environment contract.
3. Select the task guide below and inspect its linked module/function docs.
4. Implement with public APIs, verify locally with TestModel, then qualify any
   new real-backend combination explicitly.

The generated site's `llms.txt` indexes pages and modules. Each page also has a
Markdown representation, for example `getting-started.md` beside
`getting-started.html`. Use those files for retrieval rather than scraping the
sidebar. In a source clone,
paths below are relative to `docs/guides/`; generated ExDoc pages are flattened.

## API map

| Task | Entry | Read |
|---|---|---|
| One-shot execution | `ExAgent.new/1`, `run/3` | [Getting started](getting-started.md) |
| Lazy streaming | `ExAgent.run_stream/3` | [Runtime](runtime-and-events.md) |
| Define tools | `ExAgent.Tools`, `Tool.new/1` | [Tools and output](tools-and-output.md) |
| Typed output | `output: MyEmbeddedSchema`, `output_mode:` | [Tools and output](tools-and-output.md) |
| Skills loaded on demand | `ExAgent.new(skills:)`, `Skills.from_dir!/2`, `Skill.new/1` | [Skills](skills.md) |
| Provider/model | `Model.resolve/2`, `Models.ReqLLM.new/1` | [Models](models-and-limits.md) |
| Qualified OpenRouter routing | `tool_profile: :openrouter_chat_tools_v1`, bounded `provider_options:` | [Models](models-and-limits.md) |
| Conversation owner | `AgentSupervisor.start_agent/1`, `Server.chat/3` | [Runtime](runtime-and-events.md) |
| UI updates | `Event.agent_topic/2`, `PubSub.subscribe/2` | [Runtime](runtime-and-events.md) |
| Checkpoint | `store:`, `Server.checkpoint/1`, `Session.checkpoint/1` | [Durability](durability-and-approvals.md) |
| Persisted approval | `Continuation.get/2`, `decide/4`, `ExAgent.resume/3` | [Durability](durability-and-approvals.md) |
| Shared-state turns | `Session`, `Session.Participant`, `TurnPolicy` | [Coordination](coordination.md) |
| Typed durable shared state | Host `Session.StateCodec`, `shared_state_codec:` | [Coordination](coordination.md) |
| Delegation | `Coordination.delegation_tool/2`, `ExAgent.run_child/4` | [Coordination](coordination.md) |
| Durable sequence/router/parallel | `Coordination.Composition`, `Coordination.Flow` | [Coordination](coordination.md) |
| MCP tools | `MCP.Client.start_link/1`, `tools/1`, `close/1` | [MCP](mcp.md) |
| Retrieval/jobs | Host-owned integration recipes | [Documentation map](index.md) |
| Traces and mixed ReqLLM calls | `ExAgent.Observability.OpenTelemetry`, `ExAgent.Observability.ReqLLM.attach/1` | [Observability](observability.md) |
| Long-lived tracing cleanup | Supervise `ExAgent.Observability.ReqLLM.Maintenance`; set a finite processor `max_exporter_restarts` when needed | [Observability](observability.md) |
| ReqLLM metrics | `ReqLLM.attach(metrics: [models: [...]])`; host experimental API/SDK 0.6 and reader | [Observability](observability.md) |
| Disposable native HTTP/gRPC export | Application-owned VM recipe with finite batch and deadline | [Isolated transport](../development/otlp-isolated-transport.md) |
| Offline verification | `%ExAgent.Models.Test{script: ...}` | [Testing](testing.md) |
| Unexpected behavior | Sanitized reason + relevant boundary | [Troubleshooting](troubleshooting.md) |

## Preserve these contracts

- **Result:** `{:ok, result}` or `{:error, %ExAgent.RunError{reason: reason,
  partial: result}}` for operational run failures. Invalid construction can raise.
  `result.output` is final only on success. Do not serialize live results wholesale.
- **Stream:** provisional `{:delta, text}` events, then `{:result, result}` or
  `{:error, error}`. Enumerate once; own and close suspended continuations.
- **Model:** official stock ReqLLM. Catalogue resolution alone does not qualify
  tools/streaming/native output. Configure an explicit compatible profile.
- **Tools:** validate before invocation. Keep results JSON-portable. A tool timeout
  or failure is not evidence that its external effect never occurred.
- **Authority:** derive namespace/actor from authenticated host state. Ancestor
  permissions and budgets constrain children. Prompt text cannot grant approval.
- **Accounting:** exact host counters differ from normalized/reported tokens and
  estimated cost. Parent totals include descendants. Unknown cost is not zero.
- **Persistence:** ACK requires confirmed save. Dirty blocks mutations; checkpoint
  retry saves data only. ETS is ephemeral. Resume needs trusted templates and bindings.
  A typed Session codec is supplied by the host on every start; stored data never
  selects its module. Keep encode/decode pure and validate application data.
- **Recovery:** reconcile uncertain effects explicitly. Do not turn every error,
  queue retry or restored message history into a fresh run.
- **Observability:** optional, host-owned SDK/exporter, content off by default.
  Use the integrated ReqLLM bridge for mixed applications; attach once at startup
  and maintain its upstream tracking TTL, optionally with the supervised child.
  The TTL must exceed live request durations; restart budgets reset per instance.
  Metrics require an explicit bounded model allowlist and a host-owned reader;
  their token counts retain normalized quality. The default tracer follows a
  restarted SDK; replace any explicit tracer when replacing its provider.
  Sampled spans are not a billing ledger
  or guaranteed durable audit record.

## Verify the relevant boundary

Test ordinary app behavior with TestModel. For tools, assert real invocation and
returned parts; for runtime, match namespace/request IDs; for persistence, assert
the confirmed transition and duplicate-attempt behavior. Run the app's own tests.
Changes to a real provider profile need separate opt-in acceptance and credentials
supplied by the host. Passing offline cases must not be reported as live compatibility.

If upgrading 1.x, read [Migration](migration.md) before copying an old example.
