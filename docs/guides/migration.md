# Migration to the consolidation major

Migration reference for the unreleased v2 candidate. No version has been bumped
or published. [Design decisions](../architecture/design.md) record the selected
contracts; [project status](../status.md) distinguishes accepted behavior and
pending gates. Do not infer real-backend or consumer compatibility from this guide.

## ReqLLM 1.26 dependency update

The current candidate requires `req_llm ~> 1.26.0` and resolves the required
`llm_db` catalogue to 2026.9.8. Update your application's dependency lock and run
its integration checks. The older 1.24 qualification records below remain dated
evidence; they do not certify the newer dependency graph.

Existing tool/output profiles, argument envelopes, continuation codecs, snapshots
and accounting quality remain unchanged. New upstream usage metadata does not
make this adapter's normalized totals observed provider counters. Cache reads and
writes remain separate; inclusive input and reasoning already included in output
must not be added twice.

ReqLLM now preserves Anthropic `redacted_thinking` as opaque provider blocks.
ExAgent's thinking/continuation profile is still unqualified: thinking options
reject before IO, and an unexpected returned provider block rejects explicitly
instead of being silently dropped. This update does not enable that profile.

## Upgrade checklist

Start with the changes your consumer actually uses. The sections below preserve
the detailed contract decisions; stage names refer to implementation milestones,
not additional work an application must execute.

| Existing consumer behavior | Required change |
|---|---|
| Pattern-matches bare operational errors | Read `RunError.reason` and retain `RunError.partial`. |
| Uses old provider helpers or implicit tools support | Resolve stock ReqLLM specs and explicitly configure the qualified profile. |
| Treats every stream delta as final output | Deliver the successful terminal result; enumerate once. |
| Calls tools without a validated schema/envelope | Use current Tool contracts and preserve the mandatory argument gate. |
| Adds parent and child usage totals | Use inclusive parent totals and qualified accounting/status fields. |
| Retries a prompt after a failed checkpoint | Retry storage only with `checkpoint/1` or the exact checkpoint token. |
| Restores messages to replay interrupted effects | Use C7 continuation bindings and explicit effect reconciliation. |
| Subscribes without tenant/request correlation | Match the authenticated namespace and request ID. |

The [task guides](../README.md) provide shorter integration examples.
[Support status](../status.md) is the current evidence summary: integrated reviews,
real SQL and both backend UI gates are closed in their declared profiles; strict
stock dependency diagnostics and release publication remain open. Historical
fixture-only evidence is not a substitute for those later receipts.

## Final tool arguments and streaming diagnostics

The qualified Chat profile consumes one stock ReqLLM final response. A valid
final tool call may retain `invalid_arguments`, `unparseable_arguments` and
`raw_arguments` diagnostics from its initial incomplete fragment. These are kept
in portable metadata; do not classify the final call using those flags alone.
ExAgent still requires strict JSON, the required `arguments` envelope, logical
schema, valid completion and unchanged identity/permissions before execution.

Any non-nil `error` under either atom or string key rejects with
`invalid_tool_arguments`: this includes args_lost, missing fragments, unknown
values, false and empty strings. Nil under one key cannot hide an error under the
other. A schema-valid fallback map with explicit loss remains rejected, including
the current stock complete-JSON-plus-whitespace case. This is a fail-closed host
policy, not a claim that ReqLLM documents every diagnostic as terminal.

No configuration flag, metadata stripping, JSON repair or alternate materializer
is introduced. Codec/history and persisted approval formats are unchanged; approved
calls must still revalidate current authority on resume. Consumers should handle
the explicit argument error rather than depend on the former incidental
`invalid_message_or_options` portability error for args_lost tuples. Public metadata
already normalized away by stock cannot be recovered by this adapter. Live-provider
requalification remains a separate gate from these offline admission regressions.

A public incomplete finish (`length`, `content_filter`, other non-success value)
has priority over a simultaneous argument-projection failure. Handle
`{:incomplete_response, finish}` even when `partial_response` is nil. A partial
is retained only if the existing complete translation passes every guard; its
qualified usage remains available then. If it cannot be projected, no replacement
usage or call is invented. This does not confer a new executable-history guarantee
on error partials. Successful tool_calls with malformed/lost args still return the
argument error; invalid args never imply a length terminal.

## Explicit none mode and continuation readers

Set `reasoning_mode: :none` on a ReqLLM instance only with the existing qualified
OpenAIChat profile and current, truthful capability evidence:
`reasoning.enabled=true`, `reasoning.effort.supported=true`, effort values containing
`"none"`, and `reasoning.thinking.disable_supported=true`. A host may project an
explicit optional/disable-supported catalog declaration into these fields; it must
not turn mandatory reasoning into disable support or invent none from its absence.
There are no hardcoded model names or automatic gateway capability guesses.

Omit temperature in this mode: an explicit value rejects instead of being removed.
`ModelSettings.max_tokens` remains the only limit (1..4096, default4096), translated
to the public stock max_completion_tokens option with canonical max_tokens omitted.
Do not supply those keys through provider_options/extra. Nil reasoning_mode retains
previous settings/profile behavior. Thinking support is effectively false and any
publicly exposed reasoning continuation still rejects before tool effects.

None responses use message continuation3 with top-level reasoning_mode="none".
None cannot resume v1/v2 response history, nor can nil mode adopt v3. Envelope1 and
logical arguments remain unchanged. No automatic downcast or guessed migration.

For persisted runs, the optional no-IO `Model.continuation_binding/1` callback returns
`{:ok, portable_json}` or an error. Absence defaults to nil; portable values are
normalized and capped at4096 JSON bytes. Bind only deterministic nonsecret static
configuration, never runtime cursors/auth. The dispatcher returns
invalid_model_continuation_binding or model_continuation_binding_too_large for
invalid callbacks/data. ReqLLM none binds its effective target, profiles, mode and
relevant capabilities; reordering effort values or rotating credentials does not
change that binding. Your application still supplies its ordinary model codec.

Frame3 and Abort2 store binding explicitly and compare the trusted current template
**before** codec load, then the restored model afterwards; a codec cannot hide a
changed target or disabled mode. Mismatch is continuation_model_binding_changed.
Legacy root1/tree2/abort1 reads require nil binding; binding-aware models need an
explicit external migration rather than invented evidence. All new captures use
the new versions. Old readers must reject them. Snapshot4/Scope2/envelope1 stay.
Binding data counts toward aggregate checkpoint J/JSON/tree reservations. Exact
data-only retry_checkpoint commands retain their old versions and invoke neither
binding callbacks nor Model IO. Approval, reconciliation and retry continue to
require current actor/authority, schema and budgets. Scoped offline review is
accepted; live qualifications remain model/profile-specific and partly limited.
Consult the roadmap for exact accepted bytes and operations.

## Persisted continuation integration (R5)

The integrated delegation vertical now writes internal frame2/scope2, retaining
all node references, cursors and accounting in the same agent row. Existing valid
root1 checkpoints remain readable; the compatibility test uses actual bytes from
the accepted root writer. Root-only readers cannot resume trees. Durable delegation
requires the trusted descriptor on `Coordination.delegation_tool/2`, including child
definition/policy/model references and a portable model codec; arbitrary `run_child`
inside a callable remains rejected in durable mode. Resume rebuilds configuration
from the host descriptor and does not invoke that parent callable or repeat a
confirmed sibling. Child and ancestor constraints still apply after restore.
Snapshot4, message continuation2, accounting1 and envelope1 remain unchanged.
The C7 framework source8b3b plus separate SQL4b89 correction is accepted offline
after independent review. The old TARba17 does not include that SQL correction;
external qualification and acceptance of subsequent admission/package bytes remain
separate gates. See the roadmap for the exact accepted identities.

### Explicit recovery and historical risk

`Continuation.reconcile_model/5` takes the host-confirmed effective post-hook
`Response` and portable `model_data`, plus the trusted target agent, references and
codec in the administrative options. For a child, supply that child's definition.
It validates state/profile/output without calling Model or replaying hooks. Unknown
cost is not priced retroactively; optional per-ancestor accounting must match the
request's actual ancestor set and preserve already-confirmed observations.

`Continuation.get/2` also returns `retryable_effects` and `historical_uncertainty`.
To authorize another attempt, pass one exact binding to `retry_effect/4` with the
usual actor/authorize/operation options, `accept_duplicate_risk: true` and a
nonsecret visible-ASCII `idempotency_key` of1..512 bytes. The decision itself does
not dispatch; resume must obtain a fresh claim and intent ACK. A changed key in an
already-keyed chain is rejected. Model retries restore the effective request rather
than reexecuting before-model hooks. Legacy Model intents without portable request
evidence require reconciliation rather than guessed replay.

Context-taking tools receive `ctx.idempotency_key`; Models receive
`params.idempotency_key`. The new fields default to nil. Context-free tools cannot
receive an explicit retry key and reject that path before IO. ReqLLM's qualified
Chat profile sends `Idempotency-Key` through public stock options for buffered and
streaming HTTP. Delivery **does not guarantee external deduplication**, particularly
when the original attempt did not carry that key. Applications own that contract.

New Model requests and explicit Tool retry reservations consume budgets once.
Historical reservations are not debited again. `effect_attempts` counts committed
host dispatch intents, including attempts that may not have reached the service;
it is not a count of proven external effects. Unobserved original accounting stays
unknown/partial. Active budget spent in a crash and UTC expiry remain binding.

Successful retry does not rewrite the original uncertain journal entry. Results,
queries and terminal events expose a bounded `historical_uncertainty` summary.
Start/prune preserve that evidence until the host calls `acknowledge_history/3`
with its exact evidence hash and `allow_evidence_deletion: true`, under normal
administrative authorization. This permits later replacement/deletion; it neither
deletes immediately nor asserts the old effect was reconciled. Retention limits
can reject a command instead of evicting evidence. Local C7 integration, capacity
and fixed-graph distribution gates have accepted evidence; integrated review and
the declared external profiles are closed. Strict dependency diagnostics remain
open. See the roadmap for the
accepted baseline rather than treating local passes as production certification.

Distinguish `status: :paused` from a successful final output. A paused stream ends;
resuming opens a new attempt. Server continuation mode writes one atomic record,
not an additional legacy snapshot. A terminal deny/cancel/expiry may retain an
open tool batch: health reports `:reset_required` and execution admission returns
`:continuation_pending` until the host explicitly calls `Server.reset/1`.
That reset abandons conversational history while preserving execution evidence,
lifetime and monotonic revisions. It never clears uncertain or dirty execution.
Only confirmed reset permits retained queued work to drain; queues remain volatile
across process restart. Failed reset exposes a checkpoint error and retries only
its exact data command through `Server.checkpoint/1`.

Session's partial continuation extension is under verification. Its opt-in
binding maps participant IDs to trusted scoped Store/agent IDs, never inferring a
Server from `Participant.ref`. The `continuation/2` query and explicit
`complete_turn/4` require versioned references bound to participant, namespace/id,
record lifetime, run and revision. Completing the same lifetime/run twice is
rejected even if reset changed its revision. The completion callback must be pure
host calculation: no transactional or exactly-once effect guarantee spans Session
and agent rows. Session pause/resume remains independent turn control; existing
unbound shared-state maps remain generic. Bound Sessions write snapshot3 and require
the same trusted bindings on restore; unbound writers stay at2, with legacy1/2
readers. At most64 bindings retain one pending reference and one consumed identity
each; no unbounded deduplication history is promised. Do not treat this partial integration
as accepted C7 until the roadmap's integrated verification/review gates close.

Session local failures remain blocked even if the agent Store still exposes an
older consumed terminal. To acknowledge such a diagnostic explicitly, obtain the
`witness` from `Session.continuation/2` and pass it to `Session.reconcile_turn/3`.
This host-authenticated action changes neither shared state nor the current turn,
does not consume the terminal again and executes no callback. It cannot clear
pending/uncertain/dirty work or a changed identity. The witness binds the exact
local diagnostic/revision and Store reference; a stale witness cannot clear a new
error. Prototype Session3 error snapshots lacking diagnostic identity fail closed;
error-free prototype data is still readable. This is not external-effect recovery.

An opt-in bound participant cannot leave while the agent row still exists: handle
`:continuation_binding_retained` instead of assuming membership was removed.
This preserves the current consumed identity and restart consistency. The host may
quiesce and explicitly delete eligible terminal evidence using the existing Store
retention API; after confirmed absence with no pending/local error, leave removes
roster and binding together. Leave does not delete agent data itself, and historical
deduplication after deletion is not promised. Unbound leave remains unchanged.

The abort follow-up introduces same-row admission barriers and a non-executable
terminal abort frame. Killing an owner alone does not cancel a Store commit already
sent; callers must distinguish confirmed abort from its checkpoint error and retry
only persistence. Terminal data can be queried/restarted, but never claimed as a
resumable aborted run. These new windows remain under verification.

If a competing admission wins after a barrier save failure, retrying its exact
checkpoint may conflict. Server remains dirty/blocked and does not replace that
command or drain the queue. Inspect the authoritative record, explicitly reconcile
the intended run through the host-authorized continuation API, then reload the
Server from that record. Volatile queued requests are not replayed by restart.

## Atomic persistence data primitives (R4)

R4 adds experimental data operations, not a runtime pause/approval/resume API.
Integration on accepted R3.4 is verified and reviewed; G3 separately qualifies
the real PostgreSQL17.4 profile. ETS is ephemeral; earlier SQL protocol fixtures
remain offline evidence rather than real G3.

### Select capabilities and a trusted namespace

Use the existing `Store.scoped({adapter, config}, namespace)` descriptor. Call
`Store.require_continuation(scope, :ephemeral)` for ETS, or `:durable` for Postgres,
before any Model/tool effect. Missing/unknown atomic capabilities or a durability
mismatch fail closed. Custom snapshot-only Stores remain valid for snapshots.
Existing raw ETS table handles also remain snapshots-only: atomic continuation
requires the actual ExAgent ETS GenServer owner and its ordered table. Raw-tid
snapshot mutations use bounded atomic compare/replace/delete (20 contention
attempts, then conflict), preserving legacy consumers without pretending to have
serialized continuation clocks or claims.
Optional callbacks are `capabilities/1`, `load_record/2`, `transition/4` and
`scan_records/3`; the backend receives native `{namespace, kind, logical_id}` keys.
Kinds are the existing `:agent`/`:session`; no new R3 identity codec is introduced.
R5 chooses the identity for one-shot runs; this layer does not reinterpret it.

Dispatch operations are `Store.load_record(scope, kind, id)`,
`Store.transition(scope, kind, id, expected_revision, command)` and
`Store.scan_records(scope, %{limit: 50, after: cursor})`. Expected revision is
`:absent` only for creation, otherwise a positive integer. A command is a JSON map
with exactly `record_id`, `operation`, `operation_id`, `actor_id`, `payload`.
IDs are nonempty UTF-8 strings at most512 bytes. The host supplies a fresh unique
record_id per row lifetime and authorizes actors; these are not LLM permissions.
Persisted bytes never choose a module, callable, template resolver or credential.
JSON does not detect secrets in application data: use persistible values or opaque
references that trusted host configuration resolves in R5.

### Data seam and closed commands

The record stores `record_version:1`, record_id, native key as JSON array,
record revision, snapshot, execution, receipts and UTC created_at/updated_at.
Use `ExAgent.Continuation.Record.snapshot_data(snapshot)` to obtain JSON data and
`Record.snapshot(data, native_key)` to validate it through the existing readers.
Message/history/Usage formats are not copied into a second parser. Snapshot
revision is independent of record CAS revision and may not regress. Snapshot4,
omitted-v1, Usage omission/accounting1, continuation2 and envelope1 remain intact;
omitted history stays diagnostic and cannot be dispatched to a Model.

Initial execution data has exactly continuation_id, run_id, request_id, definition,
policy, model_ref, deadline_at, expires_at and progress. References are `{id,version}`
JSON maps of strings; progress is host-owned portable data. The reducer adds
execution_version1, state, owner_id, attempt_id, fence, lease_until and effects.
Claims preserve progress exactly, including acquired budgets and elapsed active
time. R5 must validate/export actual accounting and authority through its runtime
seam; an arbitrary progress map is not itself an accepted scope rehydration format.

| Operation | Payload / precondition |
|---|---|
| create | snapshot + initial execution; absent row; no inferred continuation from a legacy snapshot |
| start | execution; previous execution terminal; fresh run/continuation IDs, same row/lifetime; revision/fence never reset |
| claim | owner_id, fresh attempt_id, lease_until; ready and before deadline/expiry |
| checkpoint | worker identity + snapshot/progress; claimed with no unresolved effect |
| begin_effect | worker identity + effect_id + intent; intent is kind (`model`/`tool`), call_id, payload map; effect ID not previously present |
| outcome | worker identity + effect_id + outcome + snapshot/progress; running intent; confirmed status/data |
| recover | empty payload; expired claimed lease; invalidates fence; unfinished intent becomes uncertain |
| reconcile | effect_id + demonstrated outcome + snapshot/progress; uncertain; no replay command |
| finish | worker identity + snapshot/progress; no unresolved effect; becomes completed |
| expire | empty payload; ready and deadline/expiry reached |
| cancel | empty payload; ready/claimed; unresolved effect becomes uncertain, otherwise cancelled |
| delete | exclusive UTC cutoff `before`; completed/expired/cancelled only, no unresolved effect |

Worker identity is owner_id, attempt_id and fence. Outcomes have exactly status
and data; statuses reuse succeeded/validation_error/denied/failed/not_executed/
unknown. Unknown is not success and keeps the execution uncertain. Claim/recovery
do not dispatch external effects. Fencing rejects old writes, but cannot stop an
HTTP request already sent by an old owner. Reconciliation is a trusted host action
based on demonstrated outcome; new effect IDs are not an automatic retry policy.

UTC integer milliseconds in0..9223372036854775807 are read by ETS inside its owner
or by Postgres after row locking; unique INSERT wait also requires a fresh UTC check.
Deadline and expiry include waiting; nil means no expiration. Lease is distinct
from active execution timeout. Completion can save observed effects after an
execution deadline while its owner lease remains valid; no new effect may begin.
R5 counts active time separately from human wait and must not reset acquired budgets.

### ACKs, effects and bounded retention

Persist begin_effect before issuing IO. A success returns `%{record, receipt,
replayed}`; operation identity includes original expected revision, key/lifetime,
actor and full canonical command. Same operation ID with different data conflicts.
Identical retry returns its original receipt even if the record advanced. The
returned record is current, not the old receipt's revision. **A replayed receipt is
evidence of a past data commit, not permission to execute again.** The future runtime
must verify current execution, owner/attempt/fence, lease and intent before dispatch.

After an effect, keep its outcome/snapshot as a dirty candidate until confirmed.
`Continuation.Checkpoint.new(scope, kind, id, durability)` and `write/3`/`retry/1`
are an opt-in persistence-only seam: pending writes block new commands and retry
the exact captured operation. They execute no Model, tool or change callback.
They do not yet gate Server/Session queues; that integration is R5. A process lost
after intent but before saving outcome is uncertain even if the effect never ran.

Encoded record limit is8MiB, with256 effects and1024 receipts per retained lifetime.
Admission reserves receipt slots and encoded bytes based on actual execution IDs,
worst-case escaped actor/operation IDs, minimal outcome/state growth and counter/
timestamp widths; claimed records reserve recover and close. See design8.33 in
[design decisions](../architecture/design.md). This is an encoded retention bound,
not a predecode RAM promise or a guarantee every future result fits. Bound/externalize
application payloads before effects; oversized results remain persistence failures,
never reasons to rerun effects. Validate old experimental backups against stricter
reservation and UTC constraints; remediate explicitly with writers stopped.
No product quota limits number of conversations per namespace; the host owns it.

Receipts retain digest/revision/actor and run/continuation/state projection, plus
claim attempt IDs. Start drops the preceding terminal execution's detailed effect
journal, retaining its terminal receipt projection and the conversation snapshot.
Receipts are never pruned from an active record. Hitting the cap rejects new work;
close/archive/delete terminal data according to application retention. Delete has
no retained receipt: a repeat is not_found. IDs must not be reused for a new
lifetime; anti-reuse guarantees extend only over retained evidence.

Scan limit1..100 bounds **physical rows examined**, not only matching records. An
empty page with a cursor is valid. Continue until cursor nil; errors are errors,
not empty success. `Continuation.prune_page(scope, cutoff, actor, query)` reports
each deleted/retained/conflicted identity and next cursor. Stop all namespace
admissions/writers before full namespace removal; pages are not one global atomic
transaction. Active, nil-expiry and uncertain executions cannot be swept away.

### Legacy data, SQL setup and backup/restore

One selected table contains either legacy snapshot JSON or a record envelope in
the same key/data row, using the R3 physical identity codec. There is no dual-write,
second authoritative table or fallback after corrupt/future/mismatched records.
Legacy load/save/delete on a record fail with atomic_record_required; legacy lists
omit records. This prevents an unintegrated Server from restoring and executing
before its eventual snapshot save would fail. Inspect with load_record instead.

The app applies `docs/guides/continuation-schema.sql`; startup runs no DDL. The
existing snapshot schema is compatible. Postgres config accepts a validated bare
table identifier (quoted in SQL); configure schema/search_path in the trusted Repo.
Transactions use five-second transaction/statement bounds, parameterized values,
row locks and unique-key creation. SQL real concurrency, restart, disconnect/ACK,
rollback and backup/restore remain G3 acceptance work in an authorized database.

Migration is explicit: stop old writers, export and validate legacy data with its
existing codec, preserve a read-only backup, choose the new scope/lifetime and
construct a fresh execution from host configuration. Creating at an occupied legacy
key fails with legacy_snapshot. Prefer a fresh destination namespace with old
namespace retired/read-only; only the destination is authoritative. Same-key
conversion requires an application-owned offline migration transaction after
validation; ExAgent never infers a resumable execution or overwrites legacy data.

Back up full envelopes including revisions, lifetime IDs, fences and receipts.
Restore with owners/admissions stopped and validate keys/codecs before enabling
reads. Changing namespace requires explicit transformation and validation against
the destination key. Never automatically dispatch restored intents or turn an
uncertain record into ready. Tests of fresh-VM JSON use test-only disk files,
not a new product disk Store and not evidence of Postgres durability.

## Runtime consumer namespaces and admission (R3 partial)

Supply a trusted nonempty UTF-8 `namespace` to Server and Session. IDs of agents,
conversations and participants remain local; correlate them with namespace, then
run/request/emitter IDs. An emitter incarnation owns its sequence; a new live run
has a new run_id and each model interaction has its own model_request_id. These
are not durable attempt/claim identities. A living owner attempts one terminal;
late task/run events cannot finish a different current run.

`Store.scoped(store, namespace)` scopes public load/save/list/delete operations.
Passing an already scoped store with a different namespace (including nil) is a
configuration error before backend IO. Nil keeps legacy keys/topics except IDs
starting with reserved `exagent.scope.v1:`: rename them explicitly. Scoped keys
are a versioned injective encoding of namespace/kind/local ID; snapshots validate
the exact key before restoring their logical ID. No legacy lookup fallback occurs.
Moving data between scopes requires validated export/import. Current snapshot
list callbacks enumerate backend entries and filter/revalidate within the
dispatcher; they are not server-side tenant-query or pagination guarantees.

Namespaces do not authenticate callers or claim owners. The host must maintain
one logical writer per scoped conversation and supply live participant refs from
that same trusted scope. Restored data selects neither modules nor processes.
Direct backend calls bypass the public dispatcher; SQL claims remain R4/R5.

Server admission defaults: `max_pending: 8`, `max_input_bytes: 1_048_576`,
`max_pending_bytes: 8_388_608`, `max_history_bytes: 8_388_608`; byte options accept
integers1..67_108_864. Input measures `{prompt, opts}` (including captured context;
queued opts also contain the admission request_id); pending measures each such
queued tuple, history the selected canonical message list, using uncompressed
`:erlang.external_size`. Deps/callback representations count, referenced resources
do not: this is not JSON size, process RAM, mailbox backpressure or a predecode
bound. Host terms already exist before the check. Payloads beyond these defaults
need explicit tuning within the ceiling or external references.

Input/history return `{:error, {:input_too_large | :history_too_large,
%{bytes: measured, limit: configured}}}` before admission. Saturated pending count
or bytes returns `{:error, :queue_full}`; health reports pending_bytes. Dequeue
releases bytes and rechecks history; a previously admitted request can then
produce a correlated run_failed terminal with zero new model/tool operations.
Steer inserts at the front of the volatile pending queue; it does not modify an
active model request. Caller timeout does not cancel owned work; abort cancels the
current run and drains the next admitted entry. Owner death loses pending work.

### Current-run postdecode retention (R3.4)

Agent definitions and run options now have `max_payload_bytes` P (1MiB default)
and `max_history_bytes` H (8MiB default), integers1..64MiB. Server uses the smaller
of its H and the definition's H. Response/ToolReturn checks include their entire
external term, including metadata, and run admission includes the current prompt
and instructions. Compaction only changes request projection; canonical history
remains intact and must fit H. Hooks cannot erase confirmed history to free space.

Before admitting a batch the loop reserves a deterministic serialized result slot
per call from the remaining H. Each slot must fit its identity, omission marker,
4KiB Usage allowance and control overhead; otherwise no tools are admitted.
Oversized decoded model responses reject before tools. An oversized tool return
can occur **after its effect**: it keeps its actual status and IDs, sets content
to nil and `payload_omitted` to a version1 map with boundary/bytes/limit. If only
Usage metadata was omitted, content that fits is preserved and boundary is usage.
The run fails with `{:retention_limit_exceeded, %{boundary: ..., bytes: ..., limit: ...}}`
after collecting the admitted batch. It does not retry or issue another model
request; confirmed siblings survive errors and timeout.

Check `payload_omitted` before consuming a value: nil content with a marker differs
from a genuine nil result. Oversized Usage details/dimensions are explicitly
marked, retaining canonical metrics, source/quality/availability that fit. Missing
values are not observed zeros. Host counters remain exact; unknown prices are
not recomputed on restore. Error causes above4KiB are replaced by size diagnostics.

`result.retention` measures Erlang external terms, not JSON or RAM:
`history_bytes` measures messages, and `data_bytes` measures the map containing
output/messages/new_messages/pending_response/usage. The public-data bound is
2H+P+65536, explicitly counting duplicate history and a separate64KiB control
reserve. Events also carry these measurements; projected-event overhead is
documented in design8.32. Definitions/model state/deps, application callbacks and
subscriber mailboxes are outside this metric. Core/Server bridges now await ACKs,
so suspending an owner deliberately blocks its worker instead of queuing snapshots.
R1's stock limits remain64KiB/chunk,1MiB/4096chunks, one view and owned cleanup.
Upstream decoding and arbitrary tool/hook materialization remain O(response), not
a hard predecode RAM bound; multiple host copies depend on steps/concurrency/nodes.

Server snapshot4 preserves markers and reads versions1/2/3. Old snapshot readers
reject4; Message JSON uses omitted-v1 discriminators so old readers reject marked
nodes even outside a snapshot. Unknown marker versions reject. Accounting1 and
continuation2 stay unchanged. Restored omitted history remains diagnostic and is
rejected before model IO; it is not permission to execute the tool again. Preserve
that diagnostic checkpoint, recover original data explicitly in the application,
or begin a new conversation with references to reconciled results. Externalize
large payloads or tune finite limits; do not automatically replay the prompt.

### Minimal runtime integration recipe

The host supplies `agent`, the authenticated namespace and its supervised owner
registry. This code uses only public ExAgent APIs; Local PubSub and ETS need no
Phoenix, jobs library or database. ETS is ephemeral across table-owner/VM loss.

```elixir
alias ExAgent.{Event, PubSub, Server}

namespace = "workspace-a" # obtained from the authenticated application context
conversation_id = "conversation-1"
pubsub = PubSub.normalize(:local)
:ok = PubSub.subscribe(pubsub, Event.agent_topic(conversation_id, namespace))
{:ok, server} = Server.start_link(
  agent: agent,
  agent_id: conversation_id,
  namespace: namespace,
  pubsub: pubsub,
  store: :ets,
  max_pending: 2
)
{:ok, request_id} = Server.send_message(server, "Hello")
%{server: server, namespace: namespace, request_id: request_id,
  cancel: fn -> Server.abort(server) end}
```

Consume `{:exagent_event, %Event{namespace: namespace, request_id: request_id}}`,
matching both against the authenticated screen/job. Provisional deltas are not
final output; use run_finished/run_failed/server_request_cancelled and inspect
their persistence status. The cancel closure is the same API an authenticated
cancel button invokes while work is in flight; repeated abort is harmless.

In Phoenix replace the adapter with
`{ExAgent.PubSub.Phoenix, MyApp.PubSub}` after the app starts its own PubSub;
the subscribe/topic/message contract is unchanged. Reconnect via Server.history,
Server.health or Store.load_agent_snapshot(Store.scoped(store, namespace), id),
not by treating missed PubSub events as durable work. The app resolves Server
refs from its scoped registry; never `String.to_atom(namespace)`.

A job wrapper calls `Server.chat(server, prompt)` on that same app-owned writer
and handles the returned result. Async send_message/steer/stream acknowledges
volatile admission, not job completion. On CheckpointError retry only
`Server.checkpoint(server)`; do not rerun the prompt/tool or invoke a Session
change function again. On owner loss or uncertain effects persist/reconcile
application state before deciding whether any new execution is safe. Neither
PubSub, OTP restart nor a retried job supplies durable agent replay; C7 is R4/R5.

## Explicit native output (R2.3)

The core validates the effective native schema after `before_model_request` and
before each request admission, including custom Models. Invalid schemas return
`RunError.reason == {:invalid_output_schema, errors}` (Tool's normalized schema
diagnostics); malformed `output_object` or nonempty native `output_tools` returns
`:invalid_output_configuration`. Fix the configuration in the hook: these errors
do not spend a new request/tool or enter output retries. Earlier confirmed progress
is preserved when a later hook selects invalid configuration. Model data that
fails JSON/schema/Ecto validation still uses the existing corrective retry budget.

Existing `output: EctoModule` / `output_type: EctoModule` keeps tool mode.
Opt in with `output_mode: :native`; custom Models must explicitly declare
`supports_json_schema_output: true`. Requests carry `output_object.json_schema`
and its Ecto module separately, with no synthetic final_result tool. The core
decodes an object, validates the announced schema and runs the actual changeset.
JSON/schema/changeset failures can request a new model response using the existing
`output_retries` limit; exhausted retries and request limits return counted partials.
This never repairs malformed JSON or retries an already confirmed function effect.

For ReqLLM use `output_profile: :chat_json_schema_v1` alongside
`tool_profile: :chat_tools_v1`. The same explicit OpenAI Chat metadata, no reasoning
and non-strict tools requirements apply. Native schema is reference-free, object
root, with the existing supported logical keywords; refs/$defs/unsupported roots
or strict/provider overrides fail before transport. Native uses the public
`response_format` option with `strict:false`, preserving optional/null/defaults.
Function tools can accompany native output and keep their envelope/authority.
No fallback to tool output, remote strict-validation promise or guaranteed
`parallel_tool_calls:false`. Other families remain guarded pending qualification.

Buffered text and public streaming objects become existing Text parts containing
JSON; whitespace/key order may differ, semantic data and continuation2 remain.
No new message/snapshot version is required. A refusal exposed through the public
ReqLLM projection rejects; malformed/non-object/truncated output and incomplete
terminals never finalize. **Stock Chat 1.26 may discard a wire refusal field beside
valid content**: public refusals/content/metadata/provider_meta/finish_reason can
be identical to an ordinary valid response, which can produce a locally valid
output. No total wire-refusal detection is promised. G2 and fresh review are
separate from local implementation evidence; see design8.29 and roadmap§5.

## Core extension contracts (R2 base)

Custom Model implementations may still omit `profile/1` for basic text. Extra
capabilities now default to false: implement `profile/1` returning
`%ExAgent.ModelProfile{supports_tools: true}` only when the model implements the
logical tool/return contract. Ecto-tool support does not imply native JSON output.
TestModel explicitly declares tools; ReqLLM keeps its qualified profile guards.
Unknown capability support never becomes true merely by using the default struct.

`before_model_request` may select model, settings and `params.function_tools`
per request. Selected tools are validated/prepared before IO and are the executable
set, including callables of the declared arity (`takes_ctx: true` = 2, false = 1).
Omitted tools no longer execute from the wider definition inventory. Fix an
invalid callable declaration rather than discovering an arity failure after IO.

`before_tool_execute` may modify arguments, not ID/name/kind/metadata, including
custom/Test models without an envelope marker. Move name routing to pre-request
selection or expose an explicit dispatcher tool with its own schema/identity.
Context now includes the immutable call identity/retry before that hook. A raised
before-hook reports `:not_executed` / `:tool_hook_failed`; callable uncertainty
remains `:unknown`, and after-hook failure preserves the completed effect.
Batch transformation in `after_model_request` remains before tool admission,
followed by validation, limits and ancestor authorization.

The public/internal map and common paused-result design are in design8.28.
Paused is **not implemented** here: today's callback approval and Session.pause
do not persist a resumable run. R4/R5 will add status paused to the common result
with output:nil only after confirmed persistence; callers adopting that future
extension must distinguish suspension from final success. No Store/C7 runtime or
message/snapshot format change is part of R2 base; native output remains R2.3.

## ReqLLM dependency and runtime floor (R1.1)

The original dependency integration added `req_llm ~> 1.24.0`, resolved to1.24.0.
The current requirement is documented above. Its mandatory
`llm_db >= 2026.9.3` dependency requires Elixir 1.18, so consumers on 1.17 must
upgrade before adopting this major. The manifest now requires `~> 1.18`;
qualification targets are 1.18/OTP28 and 1.20/OTP29, with exact executed versions
in project status. Older 1.17 audit results do not qualify this dependency graph.

ReqLLM starts a supervisor and Finch pool and loads `.env` by default. Hosts that
own environment loading should configure `config :req_llm, load_dotenv: false`
before startup. SQL, Jido and the OTel SDK remain outside the minimal consumer
graph. R1.1 does not change existing Model dispatch or retire wire helpers;
adapter and helper migration follow their separate acceptance units in R1.

### Single general backend and model resolution (R1.8)

The major removes `ExAgent.Models.OpenAI`, `OpenRouter`, `OpenCode`, `Anthropic`
and `ExAgent.Providers.OpenAIChat`, `Anthropic`, `SSE`, `StreamTransport`,
`EventStream`. Their codecs, arbitrary wire extras, extra_headers, cache and
stream_options APIs have no legacy fallback. Use the single ReqLLM adapter:

```elixir
{:ok, model} = ExAgent.Model.resolve({:openai, id: "gpt-4o"},
  api_key: System.fetch_env!("OPENAI_API_KEY"))
agent = ExAgent.new(model: model)
{:ok, result} = ExAgent.run(agent, "Hello")
```

`resolve/1` accepts stock strings, explicit maps, tuples and `LLMDB.Model` specs.
The latter is a spec, not a custom implementation. Other Model structs pass through
unchanged; `test`/`test:label` remain offline. `resolve/2` configures the ReqLLM
instance and rejects unknown options or an overriding `:model` option. A string
alone resolves identity, **not credentials or operational qualification**. There
is no automatic environment auth fallback; load credentials in trusted app code.
Catalogue specs may use upstream's unverified-model fallback, never ExAgent's old
wire transport. Full maps support models outside the catalogue without guessing
capabilities. Tools/stream/Ecto-tool still require the explicit profile below;
no automatic selection by provider prefix/model name.

| Previous route | Explicit migration and qualification |
|---|---|
| OpenAI | Stock `openai:` spec and instance api_key; select explicit Chat metadata/profile for tools, not inferred from a catalogue slug |
| OpenRouter | Stock `openrouter:` preserves OpenRouter provider identity, with its existing tools/stream guards; a Chat-compatible gateway uses an **explicit** OpenAI protocol spec, exact gateway model ID, endpoint and key, as in `examples/openrouter.exs` |
| OpenCode Go | Explicit Chat spec with bare slug and `base_url: "https://opencode.ai/zen/go/v1"`, api_key from OPENCODE_API_KEY in app code |
| OpenCode Zen | Same explicit configuration with `base_url: "https://opencode.ai/zen/v1"`; there is no plan/env default or silent billing-endpoint substitution |
| Anthropic API key | Spec provider `:anthropic`, api_key → x-api-key; only initial text with explicit non-reasoning metadata is admitted |
| Anthropic/ZAI Bearer | Spec provider `:anthropic`, exact ID, auth_token and exact base_url; auth_token takes precedence over api_key, using public stock OAuth/access_token with no subscription behavior |

The old `opencode:` alias has no stock equivalent and returns
`{:error, {:explicit_model_required, :opencode}}`. **`zai:` is a valid stock provider:
it now preserves ZAI identity and is not the former Anthropic alias.** To keep the
Anthropic destination, explicitly choose `provider: :anthropic` and
`base_url: "https://api.z.ai/api/anthropic"`; do not relabel a reasoning model as
non-reasoning to bypass admission. `examples/zai_anthropic.exs` demonstrates that
guard without network. Neither alias routing nor an auth-only loopback test
qualifies GLM/Anthropic tools, reasoning or continuation. A future stock resolution
of a previously missing alias is preserved rather than blocked solely by prefix.

Auth_token is rejected for non-Anthropic providers. Provider/HTTP options cannot
override credentials; errors are sanitized and Inspect omits both credential fields.
Live results still contain the configured model: persist Message codecs/snapshots,
not the full result/configuration. Metadata and prompt strings supplied by the app
are not a secret-detection service. The API key/Bearer distinction, precedence,
exact path/model, normalized accounting, retries0 and redirectfalse are tested with
synthetic loopback HTTP; no live gateway support is inferred.

Removed parser tests are replaced by ExAgent/public stock boundary tests where
the guarantee remains. Predecode byte bounds and raw-argument strings are no longer
contracts (8.22); use postdecode stream limits and logical codec-tagged args.
Validation covers **all semantic calls exposed by stock ReqLLM**, not wire entries
discarded upstream. Stock 1.26 drops an id-only entry, null entry, or function name
without args/ID from a tool_calls array, with no error/metadata signal in the
public Response. A response with one valid call and such a lost sibling can execute
the one valid, authorized call; ExAgent cannot promise wire-batch rejection or count
those lost entries as host reservations. This is an explicit loss boundary, not
preservation of the old parser's raw guarantees. An invalid call that remains
visible (unparseable args, missing envelope, schema/ID errors) rejects the batch
before any effect, and incomplete terminals remain errors. A valid visible call
still needs current authority; a lost sibling never grants permission to it.
Strict/native/extra wire settings that lack qualified
representation reject explicitly. See the retirement inventory and roadmap for
test counts and remaining gates. Custom Model and Test extensions require no private
ReqLLM interfaces and remain usable by independent package consumers.

### Buffered ReqLLM (R1.2/R1.3)

Construct `ExAgent.Models.ReqLLM.new(model: spec, api_key: key)` and pass it to
`ExAgent.new/1`. A spec can be a catalogue string or a portable explicit map;
custom specs must declare tools/image capabilities when needed. `base_url:`
selects a gateway, without mutating application-global credentials. Extra wire
options from the legacy adapters are not forwarded: this adapter rejects
`ModelSettings.extra` and unsupported HTTP/provider option keys. Its module docs
list the currently accepted settings. Qualified streaming is described below.

The ReqLLM adapter rejects tools and Ecto tool output before IO unless the explicit
`chat_tools_v1` profile described below is selected. Stock normalization discards
argument invalidity; the profile validates a mandatory envelope rather than
repairing upstream. The general guard and custom Model/Test contracts remain.
Native schema output is not selected. For Responses stateless reasoning-only
continuation, `provider_options: [store: false]` keeps reasoning/encrypted content
in the next payload instead of relying on a server-side previous response ID.

Response adds optional version1 `continuation`, and Text/Thinking/ToolCall add
portable `metadata` maps. Use `Message.to_json/from_json` or the existing snapshot
codec to preserve these fields; do not persist a ReqLLM struct or configuration.
Changing provider/model/endpoint rejects a bound continuation. Older messages
still load, but older writers may discard new fields: preserve checkpoints before
downgrading and do not claim fidelity from an old reader.

**Restrictions:** R1.5 below qualifies public normalized metrics; the new 1.26
usage-presence metadata has not been qualified as observed accounting for this
adapter. Unqualified ReqLLM tools reject, and Google also loses thought
signatures. Anthropic thinking-enabled models/options and any Response continuation
reject before IO until a complete provider-block round-trip is qualified;
plain single-turn input requires
reasoning explicitly false in the resolved model. R1.3 remains partially blocked,
not complete. Streaming is limited to the explicit Chat profile below, with
postdecode operational limits rather than a public predecode RAM guarantee.
The R1.8 migration above removes the old wrappers and duplicated transport.

### Qualified streaming (R1.4)

Use the same explicit `chat_tools_v1` model with `Model.request_stream/4`,
`ExAgent.run(..., stream_text: true)` or `ExAgent.run_stream/3`. Creation is lazy:
enumeration starts the request. Deltas remain provisional until a validated terminal;
tool callbacks run only in ExAgent after that terminal. Each enumeration is a new
interaction. Halt/exception, owner death and deadlines terminate owned work.

This initial stream profile admits4096 decoded public chunks, at most64KiB per
chunk and1MiB summed using external_size. These are postdecode serialized-byte
budgets, not heap or hard RAM limits: upstream may already retain larger frames,
queues and its O(response) accumulator. Input/history, tool results and events the
caller retains are separate. Host delta and progress bridges acknowledge demand
rather than queue growing histories. Common RunStream progress timing now applies
backpressure, including custom/Test adapters, without changing event contents.

Unset max_tokens requests4096; explicit values outside1..4096 reject before IO.
For streaming only, nil total_timeout means60000ms and explicit values must be
1..300000ms. Buffered nil still inherits ReqLLM's application default; set the same
effective budgets when comparing both paths. Slow-consumer wait counts toward the
stream deadline. HTTP adapter injection is buffered-only and rejects in streaming.
Oversize or timed-out interactions produce errors, never a successful truncated
output. Scope request/concurrency/deadline limits remain configurable; there is no
new VM-global admission controller. Usage follows the qualified R1.5 contract below.

### Qualified accounting (R1.5, major migration)

`Message.Usage` adds `accounting`, a string-keyed JSON map with `version: 1`,
`source`, `quality`, `provider_presence`, input/reasoning semantics, per-dimension
`availability` and `cost`. It is separate from additive `details`; never sum map
versions or infer fidelity from `usage_status: :complete`. Source is model,
req_llm, aggregate or legacy_snapshot; quality is reported, normalized, mixed or
unknown. Availability is available, unavailable or partial. Provider presence is
unknown: reported means the Model's contract reports a value to the host.

Both buffered and streaming adapters read the public terminal Response usage.
Missing wire fields can normalize to the same zero as an explicit zero; those
values have the same normalized quality. No-map public output instead retains
nil values/unavailable dimensions. Cache/reasoning aliases are selected once;
semantics are qualified by public flags when available, never inferred from totals.
An input-inclusive cache is not added again; reasoning included in output is not
added again. An absent direction may be nil, and aggregates retain available
subtotals with partial coverage rather than inventing observed zero.

Multi-contribution `details` now sums only total_tokens, cached_tokens,
cache_creation_input_tokens and reasoning_tokens. Existing cache/reasoning aliases
are canonicalized once (canonical key wins; string key wins over atom key).
Arbitrary numeric metadata such as version/price is preserved per operation and
in history but omitted from multi-operation aggregates, not summed or revived after
restore. Consumers needing custom additive details must aggregate them explicitly.

Configure limits on `ExAgent.new/1`, for example
`usage_limits: %ExAgent.UsageLimits{accounting: :estimated, request_limit: 4,
total_tokens_limit: 10_000}`. Strict is the default for existing metric limits:
it requires sufficient host-reported data, and known normalized-only profiles
reject before IO with accounting_unavailable/normalized_only. Custom models have
an unknown default `ModelProfile.accounting_quality`; actual nil/sparse reports
reject before subsequent effects for the required dimensions only. A declaration
does not certify provider billing. Estimated mode requires a finite effective
request limit in the metric scope or its ancestors; mentioning estimated without
a metric threshold does not add that requirement. Child policy never weakens
parent strict policy. Ordinary host-only execution continues without accounting.

Thresholds check subsequent admissions and can be exceeded by work in flight.
request_count counts admitted Model attempts, tool_calls exact batch reservations;
neither promises custom HTTP counts, dispatched tools, successes or external effects.
Upstream retries remain disabled. Operation identity reconciles cumulative snapshots
by replacement; terminal nil seals and retains partial subtotals, identical terminal
repeats are idempotent, conflicting terminals reject. No durable C7 ledger is added.

`estimate_cost` arities1/2 and model restrictions remain; explicit unknown/error
never falls back to upstream. Preflight no longer invokes callbacks with synthetic
zero usage. Without a callback, a valid public ReqLLM total_cost (then cost.total)
is an estimate in USD converted exactly once to cents, without adding aliases or
breakdowns. Missing price is unavailable. Zero is a valid estimate, not a free
invoice. cost_status known means a complete estimate is available, always qualified
as estimated; incomplete totals have cost_cents nil with accounting.cost.subtotal_cents.
Failure after losing the ledger/progress degrades coverage and total cost while
retaining that subtotal. Output, Events, Server and OTel expose the same distinction.
Cost coverage is independent of token coverage: a valid cost-only public report
can have known estimated cost while usage_status is partial. Explicit component
pricing with absent/non-USD currency is unavailable rather than mislabelled cents;
the public API's documented USD contract applies without such a pricing override.

Server snapshots now write v4 (v3 introduced accounting; v4 preserves omission).
Readers accept v3 accounting and v1/v2 as legacy_snapshot/unknown,
preserving numeric subtotals but not fabricating past reports or repricing history.
V3/v4 missing/corrupt accounting and future versions reject. JSON Message codecs
qualify unmarked live Usage on write; unmarked persisted Usage reads as legacy
unknown. Update equality checks/readers to include accounting and avoid old writers
that discard it. Continuation2/envelope1 remain unchanged. Session snapshot2 stores
coordination/policy data, not Usage/history, so its schema is unchanged. Restore
integrates only new runs; it never creates ledger operations from stored history.

The codec/schema migration below is unchanged. Other profiles remain guarded;
the accepted candidate and review status are recorded in the roadmap, with
no live-provider qualification inferred from loopback tests. See design8.24.

### Qualified buffered envelope and remaining stock replan

**Buffered partial accepted offline (R1.2, fresh review received):** to select the new qualified
tool protocol, set `tool_profile: :chat_tools_v1` on the ReqLLM instance and provide
explicit model metadata `extra: %{wire: %{protocol: "openai_chat"}}`, with
`capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}`. Gateway
and API key stay per-instance. This profile rejects strict tools true and extra
provider options; tools set `strict:false` (stock omits the wire field) without
rewriting optional fields. This is offline qualification, not live certification.

Tools and Ecto output keep logical object arguments; do not add an `arguments`
wrapper in your callable or hooks. The adapter owns exactly one wire wrapper and
requires a reference-free schema subset (design8.23), rejecting unsupported schemas
before IO. Defaults are annotations, never inserted by envelope/JSV validation.
Response continuation2 and call metadata carry `exagent.arguments/1`; preserve them
through `Message.to_json/from_json` and snapshots. Call-bearing v1/unversioned
history or non-object historical args cannot be submitted to this profile: start a
new conversation or explicitly migrate verified historical data outside the adapter,
retaining completed outcomes and avoiding effect replay. No automatic migration or
legacy wire fallback is provided. Existing v1 textual continuation still decodes.

All buffered ReqLLM operations now use host-owned HTTP work, including text. A
finite `total_timeout` or the inherited `:req_llm, :total_timeout` default is
applied by the host guardian, with ReqLLM's internal total timer set to infinity.
Nil still inherits that default (normally infinity); instance settings still win.
Caller death now terminates the owned worker/socket even during partial HTTP.
Callbacks run in the owned worker and must not rely on the caller's process
dictionary; tracing context is propagated explicitly. Arbitrary callback-created
descendants remain the callback author's responsibility. No global config changes.
The host compares its worker's monotonic completion timestamp with the deadline:
late completion fails even when timer handling was delayed. A result completed in
time may be delivered later after scheduler delay; this is not a real-time delivery
guarantee, and the enclosing run deadline is separate.

Design8.22 (2026-09-22) selects an official stock ReqLLM release with no fork,
vendoring, patch, monkeypatch, private wire parser or Jido runtime. Remaining guards
and temporary unknown/fail-closed behavior above remain until their gates pass.
The mandatory generic `{"arguments": logical_object}` envelope now has the offline
buffered candidate above; this is not a published API or upstream fix.

- Tool callers keep logical arguments. Model wire projection, history/codec and
  snapshots need explicit versioning/migration. Validate the envelope and logical
  schema, then effective arguments after hooks, before permissions/effects. Empty
  valid tools stay representable; invalid/truncated calls are never repaired into
  valid ones. Never wrap invalid historical calls to make them valid or fall back
  to the old wire format. Do not infer a codec version from ambiguous data shape.
- Schema roots/refs/$defs/strict/defaults require acceptance of the effective
  payload. Unrepresentable subsets reject before IO; no silent optional-to-required
  conversion or general-purpose schema rewriter. Ecto remains the final validator.
- Usage/limits/events/snapshots/OTel will distinguish exact host requests/attempts/
  tool counts and atomic admission from normalized/reported tokens/cache and
  estimated costs with quality/provenance/availability. Normalized zero is not
  observed zero; zero is not an unknown heuristic. Preserve USD/cents, cache
  semantics and deduplication. Ordinary execution with host limits may continue
  without accounting; a strict limit depending on unavailable data explicitly
  rejects, never silently becomes best-effort. These metrics are not invoices.
- Streaming changes to an operational contract: one lazy host view, valid terminal
  before effects, cleanup on success/halt/error/owner kill, deadlines/concurrency
  and bounded measured host postdecode queues/retention/chunks/bytes. No upstream
  hard-RAM-predecode guarantee, including buffered responses; materialization is
  O(response) and canonical history needs its own documented limit.
- Qualify a minimal Chat-compatible profile without reasoning/provider-native
  features, with tools/Ecto/stream on exact model/endpoint/API/config. Additional
  families/modalities require evidence; paths losing metadata stay closed, without
  silent fallback. A reasoning-disabled catalogue flag alone proves no absence.
- C7 keeps exact logical call/definition/codec/outcome persistence, atomic claim,
  current authority and no replay; uncertain effects remain explicit. R1.8 removes
  duplicate general adapters/transport/wire helpers in the major while preserving
  Model/Test/custom extensibility. Final API names and old-data policy are fixed
  with the implementation gates, not invented by this planning guide.

See [acceptance](../development/production-acceptance.md) for the reopened gates.
Historical691/0/28 and previous artifacts do not qualify this migration.

## 1. Run failures retain progress

ReqLLM text option precedence now honors `ModelSettings.timeout` first, then the
instance `http_options[:receive_timeout]`, then60000ms. It remains a receive
inactivity timeout, not a total deadline. Define agent defaults with
`ExAgent.new(model_settings: [...])` and override non-nil values with
`ExAgent.run(..., model_settings: [...])`. Direct Model calls place System parts
in messages: the adapter no longer duplicates `params.instructions` or reinserts
definition text removed by a hook's request projection.
Stock ReqLLM also derives its pool-checkout default from the receive value; the
adapter does not expose an independent pool option. A full operation can therefore
span separate queue/receive waits unless bounded by `total_timeout`.

Req now requires `~>0.7.4`: ReqLLM1.24 uses Finch keyword options, which root
Req0.6.1 could not execute on actual HTTP. Update consumer locks accordingly;
passing synthetic-adapter tests did not prove that older transport compatible.
Function adapters still work but emit Req0.7 deprecation warnings. This change
does not lift any tool/thinking/stream/usage guard and does not change Elixir1.18.

The ReqLLM instance now accepts `total_timeout: milliseconds` (positive integer).
Nil keeps the upstream default, normally infinity. This bounds one buffered model
operation, separately from receive inactivity and the agent's run deadline; it is
not rollback or a guarantee over arbitrary descendants of host callbacks. A total
expiry returns sanitized `RequestError` with reason `{:timeout, :total}`. The option
cannot be injected through `ModelSettings.extra` or HTTP reserved keys.

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

The former OpenAIChat encoding/parsing helpers are removed in R1.8; custom models
implement this public behaviour directly, or use public stock ReqLLM APIs for
their interaction. Consolidation does not authorize replacing application admission,
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

The manifest now requires Mint 1.11+ and HPAX 1.1+ within their 1.x ranges,
plus Finch 0.24+. The [dependency review](../development/dependencies.md) records
the current versions and qualification. Finch's HTTP/1 error cleanup accompanies
Mint's changed receive-timeout behavior; update them together.
Updating only this repository's lockfile would not constrain a Hex consumer's
dependency resolution. Applications that pin older decoder versions must update
those constraints before adopting the major; no dependency override bypasses them.

Mint1.10.1 additionally rejects malformed chunk-size suffixes (CVE-2026-82672).
Attacker-influenced HTTP/1 origins behind strict intermediaries on reused
connections can otherwise cause response misattribution. Update consumer locks
too; a new floor protects resolutions, not already-installed packages.

The official Mint1.10.2 patch also fixes HTTP/1 response framing
([CVE-2026-94194](https://cna.erlef.org/cves/CVE-2026-94194.html)), HTTP/2 decoded
header amplification
([CVE-2026-91043](https://cna.erlef.org/cves/CVE-2026-91043.html)) and buffering an
oversized HTTP/2 frame before checking its declared size
([CVE-2026-92103](https://cna.erlef.org/cves/CVE-2026-92103.html)). Existing locks
at1.10.1 must update Mint too. The previous candidate adopted the minimal official
1.10.2 patch; the current candidate advances to 1.11 with Finch/HPAX and the
documented dependency review. ReqLLM contracts and host resource guards remain.

These floors address concrete HTTP/HPACK buffering/decoding advisories. Mint must
deliver partial chunk bodies so ExAgent can enforce its byte limit before a peer
finishes a huge advertised chunk. A local regression verifies this with only
128 bytes of body data, not a memory-exhaustion test. Postgrex 0.22.4 and its
DBConnection patch are test-only updates; real Store acceptance stays separate.

## 8. Optional observability

### One generation owner with ReqLLM

If your host attaches ReqLLM's OTel bridge and also enables ExAgent Model tracing,
replace that startup attach with `ExAgent.Observability.ReqLLM.attach/1`.
Its public stock adapter enriches the existing ExAgent span and delegates
standalone ReqLLM calls; do not register both bridges. Attach refuses a foreign
bridge without detaching it. An observed ExAgent ReqLLM request with conflicting
or duplicate stock bridge handlers now fails before provider IO, with
`RunError.reason = {:model_request_failed, %RequestError{reason:
{:observability_conflict, :req_llm_bridge}}}`. This explicit configuration error
replaces silent double generation observations in the unreleased major.

Hosts without a ReqLLM OTel bridge need no change. Generation tokens/costs still
come from ExAgent's existing qualified ledger, not upstream bridge attributes.
Provider success does not bypass ExAgent's terminal/argument/output guards.
ExAgent adapter telemetry is now metadata-only even with a global ReqLLM raw
capture setting; opt-in content still uses ExAgent's redactor. The integrated
bridge retains ReqLLM's upstream tracking TTL maintenance requirement; use
`prune_stale_spans/1` from the host. See [configuration](observability.md#reqllm-and-one-owner-for-request-spans).

### Existing instrumentation and transport boundaries

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

Native exporter1.11.0 HTTP qualification is measured in the
[observability guide](observability.md), section 7.
Do not treat `BoundedProcessor.stats/1`'s `exported` counter as remote accepted
spans: this exporter ignores successful OTLP partial-rejection bodies. Version1.11
preserves boolean types, unlike the historical1.10 receipt. Timeout/shutdown can leave native HTTP
profiles/atoms/requests after ExAgent's own resources close. The direct HTTP
recipe is locally wire-tested, but general long-lived cleanup remains gated.
No automatic profile cleanup or alternative transport is installed by ExAgent.
