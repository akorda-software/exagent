# Architecture and ownership

ExAgent is a reusable agent definition with optional runtime layers. A one-shot
run needs no conversation process, database or tracing service. Add the layers
your application needs; each has a distinct owner and persistence boundary.

| Layer | Owns | Application responsibility |
|---|---|---|
| `%ExAgent{}` | Reusable model, tools, output, hooks and limit configuration. | Credentials, trusted callbacks and application data. |
| Run | Model/tool loop, local validation, result and usage. | Reconcile external effects with uncertain outcomes. |
| Execution scope | Delegation ancestry, shared admission and accounting. | Keep auxiliary execution inside that scope when it must inherit authority. |
| Server | Conversation history/model, bounded queue and events. | Backpressure, authenticated namespace and lifecycle. |
| Session | Participants, turn policy and one writer of shared state. | Trusted state transitions, policy and codecs. |
| Store | Confirmed snapshots and atomic continuation records. | Database lifecycle and durable storage deployment. |

```text
Agent definition
  └─ run / stream_text / run_stream
       ├─ Model → ReqLLM or a custom adapter
       ├─ Tool → schema + permission + execution + JSON result
       └─ run_child → inherited scope, authority and budgets

Server → runs and conversation → optional Store
Session → turns and shared state → optional Store

Event / telemetry / OpenTelemetry → separate application-facing channels
```

## Contracts between layers

- A successful result contains validated final output. An operational failure
  carries its cause and known partial progress in `RunError`.
- Streaming deltas are provisional. A complete validated terminal response is
  required before tool execution or successful final output.
- Tools validate effective arguments before effects. Permissions, schema rejection,
  retryable rejection, execution failure and unknown effect have distinct meanings.
- Children inherit ancestor permissions and budgets. Parent usage includes its
  subtree; tokens and estimated cost retain their quality/completeness fields.
- Compaction projects the next model request while preserving canonical history.
- A confirmed Store save precedes positive durable acknowledgement. An unconfirmed
  transition blocks mutations; checkpoint retry only saves data.
- Persisted approval binds an exact execution boundary. Resume uses trusted live
  configuration and current authorization; recovery does not guess effect outcomes.
- The application owns the OpenTelemetry SDK and exporter. Default traces omit
  content and never serialize arbitrary live models or configuration.

## Extension points

Implement `ExAgent.Model`, `ExAgent.Store`, `ExAgent.PubSub` or a `TurnPolicy`
when an application needs another model, persistence service, event bus or turn
selection strategy. Tools, hooks, model codecs and state codecs remain trusted
application code. OTP supervision cleans up owned framework resources; it cannot
roll back arbitrary external IO.

Read [Models](../guides/models-and-limits.md),
[Durability](../guides/durability-and-approvals.md),
[Coordination](../guides/coordination.md) and
[Observability](../guides/observability.md) for configuration and exact boundaries.
