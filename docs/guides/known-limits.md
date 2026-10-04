# Known limits

These boundaries matter when deciding how to deploy ExAgent. Use
[Supported features](support.md) for the capability map and each guide for exact
configuration, results and failure handling.

| Boundary | What to account for |
|---|---|
| Provider capabilities | A catalogue model ID does not certify Chat tools, streaming or native JSON output. Declare the actual compatible profile and verify your endpoint. |
| Tool arguments | Function calls require the mandatory `arguments` envelope. Invalid/truncated calls reject before effects; there is no JSON repair. |
| Native output | The provider receives a non-strict schema. Local schema/Ecto validation decides success. Stock responses may omit a refusal that accompanies valid JSON. |
| Usage and cost | Tokens retain normalized/reported quality and cost is estimated. Unknown is not zero. A retrospective threshold cannot bound an invoice for work already in flight. |
| Memory | Host retention limits act after stock decoding. Upstream queues/materialization and caller-retained history have their own allocations. |
| Streaming | Deltas are provisional. Every enumeration starts work; a suspended continuation remains caller-owned until resumed or halted. |
| Cancellation | Framework-owned tasks can close; arbitrary callbacks and external effects cannot be rolled back. |
| Checkpoints | Confirmed data is durable only according to the Store. ETS is ephemeral, and failed saves block mutations until storage retry succeeds. |
| External effects | Timeouts, owner loss or lost acknowledgement can leave outcomes uncertain. Recovery requires host reconciliation; approval is not universal exactly-once execution. |
| Coordination | Trusted definitions and versioned bindings constrain branches. Flow has bounded flat branch/concurrency and journal/result limits. Fail-fast cannot undo sibling effects. |
| MCP | Streamable HTTP requires an application-owned HTTP1-only Finch pool. A local timeout or reconnect cannot establish remote rollback or peer identity. |
| Trace ingestion | HTTP success and exporter callbacks do not prove durable acceptance of every span. Sampling, saturation and partial rejection can lose data. |
| Direct OTLP HTTP | Native exporter timeout/shutdown can retain profiles, atoms or sockets. Use an application-owned isolated VM/Collector when bounded cleanup is required. |
| Metrics | The optional bridge needs an application-owned experimental 0.6 metric SDK/reader. Trace ingestion endpoints do not imply metric support. |
| Dependency warnings | Stock TOML/WebSockex/gproc can emit diagnostics. Review your graph; a functional integration does not imply warning-free dependencies. |

For the corresponding application handling, see
[Models](models-and-limits.md), [Runtime](runtime-and-events.md),
[Durability](durability-and-approvals.md), [Coordination](coordination.md),
[MCP](mcp.md) and [Observability](observability.md).
