# Diagnose an integration

Start with the boundary that failed: construction, model admission, tool
validation, effect execution, persistence or export. Retain the known progress
without turning uncertainty into permission to repeat work.

## Common symptoms

| Symptom | Inspect | Next action |
|---|---|---|
| A provider resolves but tools/streaming are rejected | Model protocol, capabilities and explicit profile. | Configure the [qualified profile](models-and-limits.md); catalogue membership is insufficient. |
| `invalid_tool_arguments` before invocation | Final arguments envelope, strict JSON, schema and stock diagnostics. | Fix the producer/profile. Preserve the argument gate; do not strip evidence or repair JSON. |
| Output validation fails | Ecto changeset, output mode and remaining request budget. | Fix the output contract or input. Deliver only the successful terminal output. |
| Server returns `:busy` / `:queue_full` | Active run, pending count and byte bounds via `Server.health/1`. | Apply application backpressure; queue admission is volatile. |
| An event appears on the wrong screen | Namespace and request ID in `ExAgent.Event`. | Subscribe to the authenticated topic and match both identifiers. |
| A checkpoint fails | `CheckpointError` and current dirty state. | Retry the exact storage transition, not the prompt or effect. |
| Restore rejects stored data | Snapshot/record version, ID, policy and model/tool bindings. | Follow [migration](migration.md); do not silently replace it with an empty conversation. |
| A resumed attempt reports uncertainty or an active claim | Current continuation record and external effect evidence. | Recover/reconcile explicitly; do not start a competing fresh run. |
| MCP times out | Request deadline, pool capacity and remote outcome. | Treat the effect as potentially completed; reconnect never means replay. |
| Token/cost totals differ across parent and child spans | Inclusive totals, provenance and completeness. | Read the root once; do not add an inclusive parent to its children. |

## Langfuse or Opik shows empty input/output

With default content capture disabled, **Input `null` and Output `undefined` are
expected**. They are not evidence that a model step did nothing. Use the
observation's attributes to inspect run/root/parent IDs, request/tool counters,
status, usage completeness, provenance and estimated cents.

TestModel tokens are synthetic, and estimated cost is not an invoice. A recovery
trace can retain an earlier error followed by a valid checkpoint/resume; inspect
the operation's place in the tree and its causal outcome. Historical error spans
are not erased by later success.

Both backends have equal finite native/API/UI acceptance. Read
[Observability](observability.md) before enabling content capture or choosing an
export route. Content redaction occurs before transport; the host owns credentials,
SDK and exporter lifecycle.

## Distinguish test results

An excluded test never executed. In the accepted offline suite, 22 provider and
six SQL cases are excluded because their external profiles are run separately.
An executing test that reaches its timeout fails.

The latest accepted compatibility run has green suites and functional consumer
contracts, but the overall result is red from strict upstream dependency warnings.
[Support status](../status.md) preserves both facts. Suppressing warnings or adding
timeouts does not provide evidence of a repaired contract.

## Report a reproducible problem

Include the package/source version, Elixir/OTP, model/transport profile, a minimal
public-API example, the sanitized reason and the relevant partial counters/status.
Use TestModel when the issue can be reproduced locally. Include real-backend
evidence separately when the failure depends on that backend.

Do not attach a whole live result, error, `.env`, credential-bearing model or
unredacted trace payload. Application data can contain secrets even when it is
valid JSON.

API: `ExAgent.RunError`,
`ExAgent.Server.health/1`,
`ExAgent.Continuation`.
