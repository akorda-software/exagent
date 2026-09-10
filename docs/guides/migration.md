# Migration to the consolidation major

Draft for the implementation in this worktree. No version has been bumped or
published. [Design decisions](../architecture/design.md) record the selected
contracts; [project status](../status.md) distinguishes accepted behavior and
pending gates. Do not infer real-backend or consumer compatibility from this guide.

## 1. Run failures retain progress

The outer result remains `{:ok, result}` or `{:error, reason}`. Operational loop
failures now use `ExAgent.RunError` with the original cause in `reason` and the
last known progress in `partial`:

```elixir
case ExAgent.run(agent, prompt) do
  {:ok, result} ->
    deliver_validated_output(result.output)

  {:error, %ExAgent.RunError{reason: reason, partial: partial}} ->
    record_failure(reason, partial)
end
```

The functions above are application placeholders. Revisit nested error patterns,
not only the outer two-tuple. For example a local admission error previously
matched as `{:error, {:model_request_failed, :busy}}` must now be inspected through
`RunError.reason`; it must not become an upstream outage or invalid-output event.

Partial output is not authorization to act. Retain known history, tool outcomes,
usage and model state for diagnosis/reconciliation. Missing usage is not zero
cost. A complete tool effect followed by a failed request must not be replayed
solely because the final result is an error. Applications own external idempotency
and reconciliation; restoring history is not automatic replay or deduplication.

Results contain live model state and may contain credentials. Use explicit
projections for persistence, logs and events rather than serializing a full result
or RunError object.

## 2. One loop for synchronous and streaming execution

`run_stream/3` now runs the agentic loop: tools, output validation, hooks and limits
apply. It is no longer a text-only shortcut that ignores tools. Success produces
`{:delta, text}` events followed by `{:result, full_result}`; failure produces a
single `{:error, RunError}`, not another `{:result, %{error: ...}}`.

Deltas are provisional and can span multiple model requests. Use final validated
output as the result; do not infer it by blindly concatenating every delta.
Creating a stream does not execute a request. Each enumeration is a new run and
may repeat effects; enumerate once. Halting/cancelling must close owned resources.
An Enumerable suspension still needs to be resumed or halted; retaining an
abandoned continuation is not automatically detected as cancellation.

`run/3` with `stream_text: true` uses the same loop and result contract. Existing
`deps.on_text_delta` callbacks continue receiving binary previews; avoid publishing
the same preview again through a second event bridge.

### Custom Model adapters

Synchronous `request/4` keeps `{:ok, response, final_model}`. Streaming adapters
must end with:

```elixir
{:response, response, final_model}
```

Replace old `{:response, response}` terminals, even for stateless models (return
the supplied model). Stateful adapters must return the advanced state. Preserve
the last confirmed state and partial response on request failure when known;
do not manufacture completed tool calls from truncated output. EOF without a
terminal is an error. A synchronous-only adapter may continue rejecting streaming.

Existing public OpenAIChat encoding/parsing helpers remain relevant to custom
adapters. Consolidation does not authorize replacing application admission,
accounting, retry or tool-choice policy with a default from another library.

## 3. Tool schemas now protect local invocation

Arguments are checked before invoking tools; declaring a schema is no longer just
a hint to the provider. Review required fields, types, extra properties and unions
in both manual tools and macro-generated schemas. Unknown Elixir types still need
an explicit schema if their derived fallback is unconstrained.

- Atom/string map keys supported by the existing Elixir API are preserved for
  the callable, but collisions after JSON normalization reject.
- Strings are not coerced to numbers, missing fields are not filled with defaults,
  and no atoms or custom JSV casts are created/executed.
- Only supported embedded JSON Schema dialects are admitted; unresolved external
  refs and executable module/cast extensions reject before schema compilation.
  Tool schemas received through MCP use the same boundary.
- Tool results must be Jason-encodable. Existing encodable structs/atom values
  remain valid; pids, closures and ambiguous encoded map keys are not valid results.
- `Tool.prepared_validator` is an internal cache, not persisted configuration.
  `Tool.definition/1` remains the provider-facing projection.

MCP schema selection preserves an explicit `false`, which rejects every invocation
through the ordinary Tool validator. The empty object fallback applies only when
both schema keys are absent; a present invalid schema is not replaced by that
fallback. The standard `inputSchema` key takes precedence over `input_schema`.

OutputSchema reflection preserves numeric/boolean inclusion and exclusion values
instead of converting them to strings. Array length uses `minItems`/`maxItems`;
exact length uses equal bounds. Review generated payload snapshots and backend
support for these corrected constraints. Ecto remains the final output authority;
custom/conditional validations and differing text-count semantics are still not
universally equivalent to JSON Schema.

Boolean-named members of Ecto.Enum still use their string names; they are not
native boolean fields. Length constraints intersect across options and chained
validation calls, regardless of ordering, and contradictory bounds remain
unsatisfiable just as in the changeset.

An intentionally correctable tool rejection should use the existing explicit
`ExAgent.ModelRetry` mechanism, before any uncertain effect. Arbitrary exceptions,
timeouts and execution failures no longer mean permission to repeat that effect.
Review consumers that raised `max_retries` expecting all tool errors to retry.
ToolReturn status distinguishes success, denial, validation failure, failure,
unknown outcome and non-execution; retain those distinctions in history codecs.

## 4. Scoped delegation, accounting and context

`Coordination.delegation_tool/2` uses `ExAgent.run_child/4` internally. Custom
auxiliary calls can use the same entry point with their current RunContext or
run state. It requires a live parent execution scope; callers cannot replace
ancestry by supplying another run_id/scope in child options.

- Ancestor permissions intersect. A child allow rule or approval callback does
  not remove an ancestor's deny/ask decision.
- Request/tool admission is atomic across applicable ancestor limits. A batch
  that does not fit executes none of its calls. `run_step` remains local;
  `request_count` and usage describe the relevant subtree. Do not add child
  totals again to an already inclusive parent total.
- `deadline` is an absolute monotonic millisecond integer (which may be negative),
  not a wall-clock timestamp or a duration. `max_concurrent_requests` is a positive
  integer or nil and rejects saturation rather than creating an unbounded queue.
- Arity-one `estimate_cost` remains available for homogeneous per-request pricing;
  heterogeneous model pricing uses `(model, usage)`. Review nonlinear/rounded
  estimators: keeping the arity does not imply identical aggregate billing.
- CostGuard rates are **cents per 1,000 tokens**. For example 0.25 cents/1K is
  2.50 USD/1M. Fractional cents are retained; missing rates for consumed tokens
  make cost unknown. `cost_cents`/`cost_status` are estimates of known usage,
  not an invoice or a promise to predict in-flight consumption.

Compaction now changes only `request_messages`, not canonical messages or the
`new_messages` index. Custom compactors must retain instructions, the active user
prompt and complete tool/retry groups. A summary is conversation context rather
than a new System instruction. Canonical history still needs an application
retention policy. IO inside an ordinary one-argument summarizer is not implicitly
part of the scope; use explicit scoped auxiliary calls when accounting is needed.

Provider usage fields that are absent or null remain unknown per dimension.
Numeric aggregated subtotals remain available, but `usage_status: :partial` and
`cost_status: :unknown` must not be treated as a complete free request. With a
monetary budget this can block later tools/requests; explicit zero/zero remains
known usage. No missing value is inferred from total/cache tokens.

Delegation forwards prompts from valid atom- or string-keyed argument maps while
preserving the original arguments delivered to the builder. `prompt_arg` remains
a string option; ambiguous atom/string keys still reject before the builder.

## 5. Store confirmation and recovery

Without Store, runtime state is in memory. With Store configured, a terminal
positive acknowledgement follows confirmation of the complete checkpoint. Async
`send_message` admission remains a volatile queue acknowledgement, not a durable job.

A checkpoint failure returns `ExAgent.CheckpointError` preserving the execution
result and revision. The new state remains in memory and further mutations wait
for checkpoint recovery. Retry `Server.checkpoint/1` or `Session.checkpoint/1`;
do not resend the prompt or reapply the change function merely to retry storage.

Only `:not_found` starts fresh. Corrupt/future snapshots, mismatched identity or
policy, and backend load failures are errors rather than silent empty restores.
Back up snapshots before switching writers; reverting the package alone may not
make newer snapshots readable. A bounded reader for valid v1 data supports actual
1.x consumers; it is not a second execution mode.

Session policies are restored through trusted application configuration, not module
names selected by stored data. Review custom policy handoff and snapshot codecs.
Repeated joins must not duplicate membership; paused sessions that lose their
current actor select a valid actor when resumed. Terminal sessions do not restart
implicitly on a join. A take_turn checkpoint contains the whole transition.

These guarantees concern conversation/coordination at confirmed boundaries, not
exactly-once external effects or universal resumption of a killed tool. ETS also
depends on its table owner/VM; acceptance of Postgres is a separate verification.

The message JSON codec now preserves optional non-null Text/Thinking part IDs.
Older data without these fields still loads with nil IDs; the writer omits the
new key when the ID is nil. A previously discarded ID cannot be recovered from
an old snapshot. Consumers that compare exact JSON objects should allow these
optional fields. This does not change snapshot v2 or the documented omission of
ToolReturn contributed usage from message history.

## 6. Known application migration points

Read-only inventory on 2026-09-09; applications have not been edited or executed.

### Dragonex

- `/home/kukapu/dev/projects/dragonex` pins Git `a31b306` (declared 1.3.0).
  Its optional local dependency path defaults to `../exagent`, which is not the
  same spelling as `../exAgent` on Linux. Confirm the source actually compiled.
- `lib/dragonex/game/beats.ex`, `game/beat.ex` and `game/settlement.ex` must carry
  partial failures through classification/accounting and avoid retrying completed
  effects based only on HTTP status. The app rebuilds actor history from its own
  events, so preserving Server history alone does not update that projection.
- Preserve `after_model_request` narration and `deps.on_text_delta` previews
  without duplicate publication. Revisit the TestModel streaming workaround and
  migrate `GameRetryTest.FlakyModel` to the three-element stream terminal.
- `make_attack`/`ability_check` declare `mode` as required but some fixtures omit
  it and rely on a function fallback. Supply the value or declare genuine
  optionality; the framework must not special-case these tools.
- Review correctable guard errors currently returned as `{:error, binary}` and
  `max_retries: 3`, WorldDriven policy handoff, and Store.Coded snapshot tests.
  Store is not wired into the live bootstrap observed in this inventory.

### WhoamAI

- `/home/kukapu/dev/projects/whoamai` declares `path: "vendor/exAgent"` with a
  c08125b snapshot marker (declared 1.2.0). Editing this framework does not update
  that vendor. Review the source and residual lock entry when upgrading.
- Update `lib/whoamai/game/ai/player.ex`, telemetry and BotSmoke error classification,
  preserving the distinction between local `:busy` and provider failures.
- Its OpenRouterModel owns admission/reservation/settlement before output
  validation, disables HTTP retries and omits tool_choice. Preserve these controls
  and avoid counting reservations as confirmed usage or refunding unknown cost.
- Continue delivering chat/vote only after valid final Ecto output and live-state
  checks. It is a synchronous-only adapter; no need to adopt streaming or Store.

Acceptance in both apps must be a separate authorized unit against the actual
dependency revision. Do not claim their suites pass merely because framework
fixtures or this read-only inventory cover similar paths.

## 7. Decoder dependency floors

The manifest now requires Mint 1.10+ and HPAX 1.0.4+ within their 1.x ranges.
Updating only this repository's lockfile would not constrain a Hex consumer's
dependency resolution. Applications that pin older decoder versions must update
those constraints before adopting the major; no dependency override bypasses them.

These floors address concrete HTTP/HPACK buffering/decoding advisories. Mint must
deliver partial chunk bodies so ExAgent can enforce its byte limit before a peer
finishes a huge advertised chunk. A local regression verifies this with only
128 bytes of body data, not a memory-exhaustion test. Postgrex 0.22.4 and its
DBConnection patch are test-only updates; real Store acceptance stays separate.

## 8. Optional observability

C6 adds opt-in native OpenTelemetry instrumentation. Existing callers need no
tracing configuration; enabling it uses `ExAgent.Observability.OpenTelemetry.new/1`
and the `observability:` option. The application supplies the SDK, exporter and
its resource/authentication configuration. See [observability](observability.md).

The adapter exports an explicitly selected profile, not arbitrary `RunEvent`,
`RunError`, model, dependency or snapshot data. Content remains absent unless an
explicit redactor is configured. Trace-context handles belong only to live
process boundaries and are not a new snapshot format.

Applications already using OTel should select processors deliberately rather
than replacing their global provider. Use the optional bounded processor where
a hard pending-span limit and loss counters are required: SDK 1.7's batch queue
threshold is periodic, and its flush return does not acknowledge delivery.
Generation usage and inclusive run usage have separate namespaces. Update queries
that sum both, and verify the GenAI profile mapping in the actual destination.
Backend choice and migration of tracing history, prompts, datasets or scores
remain separate acceptance work; changing an endpoint does not migrate them.

For a terminal synthesized by Server after abort/worker loss, the last published
subtotal may predate an in-flight request. Its returned partial and Event now mark
usage partial and cost unknown, preserving known numeric subtotals. The trace
uses `exagent.cost.known_subtotal_cents` rather than claiming that amount as a
complete cost. Normal core outcomes retain their confirmed information. Do not
reinterpret these conservative flags as a refund, zero consumption or replay
authorization; no cost estimator is reinvoked by this correction.

Keep SDK processor bootstrap arguments free of credentials: OTP supervisor reports
can include the original arguments on restart, before the processor's own status
projection. Resolve credentials through exporter environment/application config.

Native exporter1.10.0 HTTP qualification is measured in the
[observability guide](observability.md), section 7.
Do not treat `BoundedProcessor.stats/1`'s `exported` counter as remote accepted
spans: this exporter ignores successful OTLP partial-rejection bodies. Boolean
attributes lose their native type, and timeout/shutdown can leave native HTTP
profiles/atoms/requests after ExAgent's own resources close. The direct HTTP
recipe is locally wire-tested, but general long-lived cleanup remains gated.
No automatic profile cleanup or alternative transport is installed by ExAgent.
