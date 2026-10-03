# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0]

### Release preparation — 2026-10-03

- Prepare version2.0.0 and align the installation guides and documentation footer.
  Publication is deferred to the next session; a version bump is not proof of a
  published package. The migration guide covers the breaking runtime, model,
  error, event, snapshot and continuation contracts consolidated below.
- Add a GitHub release workflow: stable published releases build and publish
  package/docs with a package-scoped Hex API key. Manual runs preview only.
  Validate version/changelog/documentation, exact tag and main ancestry; preserve
  artifacts and verify published TAR bytes. Keep long test suites local.
- Record the user's acceptance of external stock dependency diagnostics without
  upstream changes, warning suppression or broader runtime guarantees. Direct
  native in-process HTTP remains limited; the owned disposable-VM recipe is
  qualified. Existing runtime acceptance retains its source identity and scope.

### Integrated Dragonex and operational observability — 2026-10-03

- Bind OpenRouter routing in both disabled and none modes before the first
  request and in response continuation4. Reject rerouting and legacy routed
  history before IO; keep OpenAI continuation1–3 contracts. Validate Session
  policy and continuation identities before its trusted shared-state decoder.
- Add opt-in histogram support through the published experimental OTel0.6
  APIs and ReqLLM's public Adapter. Keep one bridge, four fixed instruments,
  host model allowlist, normalized token quality and no implicit metric SDK.
- Resolve the default tracer through the live public provider so SDK replacement
  cannot leave ExAgent using a cached tracer from the previous instance. Explicit
  tracers remain application-owned. Add a causal SDK-restart regression.
- Extend the application-owned VM recipe to stock HTTP protobuf. Reclaim its
  VM/profile/socket on all outcomes; report transport acceptance separately
  from unknown span acceptance. Direct stock HTTP and upstream strict warnings
  retain their limitations. See design8.54 and the operational guides.

### Dragonex consumer boundaries — 2026-10-03

- Add explicit `:openrouter_chat_tools_v1` over stock ReqLLM, with bounded
  provider `order`/`only`/`ignore` and fallback/parameter flags, plus attribution.
  The mandatory argument envelope remains enforced; generic OpenRouter tools,
  native JSON output and unrelated provider settings remain closed.
- OpenRouter none mode keeps canonical max_tokens; OpenAI's qualified profile
  keeps its existing max_completion_tokens translation. Routing participates
  in the static nonsecret continuation binding.
- Add host-selected `Session.shared_state_codec` for JSON checkpoint encoding
  and decoding after structural snapshot/identity/roster validation. Stored
  bytes cannot choose a module. Invalid callbacks fail explicitly; failed save
  preserves the existing unconfirmed-checkpoint mutation block.
- Scoped offline HTTP/SSE/session tests and Dragonex live Decart smoke verify
  these boundaries. MiMo's `reasoning.enabled:false` is unavailable in stock
  ReqLLM1.26; no capability guess, dependency patch or publication is included.

### Long-lived observability polish — 2026-10-03

- Add opt-in supervised ReqLLM tracking maintenance with explicit TTL/cadence,
  numeric counters, handler isolation and no implicit bridge/SDK installation.
  The host must choose TTL longer than all live request durations.
- Add a per-instance exporter worker restart budget to BoundedProcessor, retaining
  the existing infinity default. Exhaustion disables admission and discards queued
  spans; additive counters expose replacements/exhaustion. Completed error callbacks
  do not spend the budget. Native OTLP verifies bounded profile recreation while
  retaining the unresolved socket/profile cleanup limitation.
- Identify ReqLLM's metrics arity mismatch with published experimental0.6 APIs;
  no dependency patch, meter shim or metrics-export acceptance is introduced.

### Known-limit investigation — 2026-10-03

- Qualify the consumer's native receipt scenario with an explicit required
  merchant/currency changeset. Preserve the partial-upload schema and original
  nullable failures. Both models pass the final case; nullable reversal reproduces
  DeepSeek's failure. Add three offline consumer regressions; no library behavior,
  provider guard, prompt, oracle or retry-policy change.
- Identify stock warning categories and their dependency paths. Track the merged
  TOML charlist fix awaiting publication and gproc1.3 blocked by grpcbox's range.
  Preserve the red strict diagnostic without patches, overrides or suppression;
  document exact upstream adoption checks and add the guide to ExDoc.

### Documentation and test-contract alignment — 2026-10-03

- Correct TestModel's exhausted-script documentation and the two-argument
  callback type: it receives a message list, and a nonempty exhausted script
  fails the request. Add an executed guide example that proves one confirmed
  tool effect survives in the failed partial result; no runtime behavior changes.
- Align current testing counts and runtime identities, C7/SQL/backend acceptance
  labels, MCP HTTP availability and integrated tracing guidance. Resolve README
  API references against the generated candidate instead of published 1.x pages.
  Explain which checks establish offline, package or real-profile acceptance;
  preserve failed diagnostics, historical receipts and unqualified profiles.

### Combined ReqLLM instrumentation — 2026-10-03

- Add the host opt-in `ExAgent.Observability.ReqLLM` bridge using stock ReqLLM's
  public adapter behaviour. Reuse the ExAgent Model span for allowlisted request
  attributes and streaming timing; keep accounting/status/content and lifecycle
  with ExAgent. Preserve stock standalone tracing, child callbacks and optional
  metrics without a second generation observation or overwriting the priced ledger.
- Propagate runtime-only Model ownership across existing context/worker boundaries.
  Force metadata-only telemetry on the ExAgent ReqLLM adapter, including when the
  host enables raw capture. Reject incompatible/duplicate stock bridge configuration
  before provider IO; document startup migration, host-owned attach/detach and
  upstream in-flight TTL maintenance. No fork, exporter installation, snapshot
  change, dependency update, version bump or publication.

### Combined application workflows — 2026-10-03

- Add four opt-in SQL consumer scenarios: six-stage typed approval pipeline;
  parallel branches with two delegation levels and a collected failure; fresh-VM
  recovery after an external synthetic effect loses its ACK; and a full workflow
  combining persisted conversation/Session state, busy/abort, parallel delegation,
  two approvals, abrupt VM exit, PostgreSQL restart, archive and PubSub stream.
- Accept all four with TestModel and both real model profiles, 46 requests and
  15 synthetic effects per model. Preserve fixture failures and DeepSeek's initial
  Session marker failure; explicit ASCII-copy instructions pass the same oracle
  in both profiles. Keep independent complex ledgers, finite SQL/host budgets and
  owned process/database cleanup. Consumer precommit: 17 passes / 27 exclusions.
- Reuse the unaffected smoke receipts: combined coverage is Luna 27/27 and
  DeepSeek 26/27; native receipt case 08 remains unqualified. Library runtime,
  root lock and published contracts are unchanged; SQL dependencies are test-only
  additions to the authorized consumer. No version bump or publication.

### Observability ownership assessment — 2026-10-03

- Compare the stock ReqLLM 1.26 bridge with ExAgent's instrumentation and recommend
  one span owner for ExAgent runs. Document request-level overlap, native telemetry
  versus exported spans, orchestration/lifecycle/accounting/privacy differences,
  and the tradeoffs of delegating generation instrumentation in a future change.
  Preserve equal Langfuse/Opik acceptance of the existing A10 profile.
- Add a native SDK / local HTTP-SSE integration matrix: four cases prove one
  request with one generation observation by default, and two observations when
  the application explicitly attaches both bridges. Summing output tokens then
  doubles the traced value without changing execution accounting. No runtime,
  SDK/exporter defaults, dependency, release version or publication change.

### Application model comparison — 2026-10-03

- Select GPT-6-Luna and DeepSeek V4.1 Flash explicitly in the authorized sibling
  consumer's real suite, through stock ReqLLM 1.26/OpenRouter Chat with reasoning
  disabled. Use a separate persistent request ledger per model, reject unknown
  profiles without fallback, and allow selecting stable case IDs for finite
  causal controls. Keep the user's environment and library runtime unchanged.
- Expand the application matrix from 18 to 23 scenarios with permission denial,
  terminal tool error, busy/abort cleanup, request-budget enforcement and
  Composition with persisted approval and no extraction replay. Require exact
  marker text to reject incidental matches in unrequested code. Consumer
  precommit passes 17 offline tests with 23 real-provider exclusions.
- Execute all 23 scenarios per model. Luna accepts 23; DeepSeek accepts 22 and
  retains a reproduced native JSON receipt-content failure. Preserve diagnostic
  failures and the earlier weak-oracle false positive. Do not claim a single
  green DeepSeek wave, native extraction acceptance or reasoning-on support.

### Dependency baseline — 2026-10-03

- Audit all 43 resolved Hex dependencies against current stable releases and
  update eleven: Finch 0.24.0, Mint 1.11.0, HPAX 1.1.0, JSV 0.25.0, Ecto 3.14.2,
  test-only OpenTelemetry exporter 1.11.0, ExDoc 0.40.4 and four transitives.
  Raise the declared HTTP/decoder floors together and qualify the new JSV series
  without removing schema/callback/continuation guards. Keep gproc 1.2.0 because
  grpcbox 0.18.0 excludes 1.3.0; retain strict upstream warning diagnostics.
  Document all versions, compatible constraints and validation separately from
  earlier candidate receipts. No release version, tag or publication change.
- Require native boolean protobuf values in the OTLP span/resource and composed
  scenario probes after the upstream exporter fix. Preserve the HTTP partial-success
  and lifecycle limitations. Correct the live length-test stimulus after the model
  returns a short refusal to the old enumeration prompt; the new harmless long
  paragraph still requires an actual length terminal and zero effects.

### Candidate qualification — 2026-10-02

- Update the unreleased candidate to official ReqLLM 1.26.0 and its required
  llm_db 2026.9.8 catalogue, retaining other compatible root lock entries. Keep
  current tool/output/accounting/continuation guards. Characterize preserved
  Anthropic redacted provider blocks and reject their unqualified continuation;
  verify cache read/write aliases without double-counting input or reasoning.
  Record fresh qualification separately from the historical 1.24 receipts.
  Complete local, real-model, application, SQL and clean-consumer checks. Correct
  the tool-owner test's startup wait using the existing readiness barrier;
  preserve its cancellation assertion and the original 1.18 integrated failure.

- Add an ExDoc documentation home and ten task guides for first runs, tools/output,
  models/limits, runtime/events, durability/approvals, coordination, testing, MCP,
  troubleshooting and coding-agent integration. Keep native search, keyboard
  navigation and themes with local styling/assets. Separate current support from
  dated evidence and correct stale backend/CI acceptance claims. Require dev-only
  ExDoc0.40.3 for native Markdown/llms generation; use its public custom formatter
  to rebase flattened Markdown links while preserving snippets. Add link/resource
  readback to the local routine. No runtime API, version or publication change.

- Move routine validation to the local checkout with `bin/check`: canonical
  formatting, strict compilation, finite probes, complete offline tests, ExDoc
  and package build/isolation. Clean TAR consumers remain explicitly selectable.
  Keep the GitHub compatibility matrix manually dispatched instead of running it
  on every push/PR update. Document the22 real-provider and6 PostgreSQL exclusions;
  they are filtered cases, not timeouts or passing external-service tests.

- Reduce continuation validation overhead without changing canonical JSON bytes,
  digests, error pointers or persisted formats. Materialize diagnostic paths only
  on normalization errors and encode an already normalized, sorted JSON tree
  once with Jason's strict encoder. Keep raw ordered-object duplicate detection,
  argument gates and all retention/authority/time limits. The same profiled
  81-ACK scenario drops from27.205s to18.968s; differential and regression evidence
  remain separate from full remote acceptance.

- Make offline fresh-VM tests use per-test temporary directories and the actual
  Mix build path. Fix the seeded fanout fixture's five-leaf launch barrier on
  runners with four tool workers, preserving admission pressure and counters.
  Check the large JSON-record cap directly against the exact dirty runtime
  command so its oracle is independent of ETS call latency under CPU load.
  Preserve the original CI failures and strict stock dependency diagnostics.

- Run the authorized draft PR CI against the committed v2 checkout. Use one
  canonical formatter (Elixir1.20.0), while both supported runtimes compile and
  execute the offline suite. Construct regex permission-floor fixtures at setup
  time so Elixir1.18 can compile their full restore matrix without escaping an
  OTP reference. Bind stream-layout test parameters at runtime to avoid six
  constant-comparison warnings on1.18. Keep all assertions and strict dependency
  diagnostics intact; both compatibility fixes pass their focal strict checks
  on1.18 and1.20 without changing the distributed core.

- Qualify18 real application scenarios in the authorized sibling Phoenix consumer
  through stock ReqLLM/GPT-4o-mini at OpenRouter: chat/stream/tools, text/native/
  image extraction, Server/PubSub/Session, router/parallel/typed Composition,
  delegation and host-approved C7 approve/deny. Preserve the initial13/18 failure
  receipt and retry only the affected cases;40 total admissions/USD1.00 synthetic
  reservation, all seven owned groups closed, no observed invoice. Keep the
  invalid original multi-call batch unqualified; final case06 is sequential.
  Migrate the consumer's old private HTTP/image parser and outdated APIs to the
  public stock adapter. Its15offline tests pass; live execution stays opt-in.

- Fix instructed agents failing with `invalid_record` before Model IO inside
  Composition, router and parallel Flow. The initial canonical request may carry
  a System prefix followed by its single exactly bound User input. Preserve
  instructions, request hashes, authority and terminal-read guards; reject extra
  User parts or a System block after User. Three API regressions pass without
  warnings, with45 adjacent cases passing; no persisted format migration.

- Fix a blocked parallel Flow when one branch opens another approval round while
  a sibling still consumes a previously granted approval. Frame11 may prepare
  that exactly authorized call during a nonfatal approval drain; current deny,
  binding, owner/fence and uncertain-effect guards stay intact. Eight causal
  cases pass; a genuine pre-fix record completes in a fresh VM without replaying
  confirmed Models or effects. No persisted format or migration changes.

- Fix loss of an already priced cumulative subtotal when a custom Model stream
  ends with non-nil sparse usage. Preserve known cost as partial evidence, stop
  an estimated over-budget effect before admission, and retain complete explicit
  zero replacement. The same correction preserves failed delegate cost in its
  ancestors. Five causal and25 adjacent offline cases pass on the exact integrated
  patch; this trigger was not demonstrated on the stock ReqLLM stream adapter.
- Harden the optional observability acceptance recipe: close owned descendants
  before reaping their group leader, roll back private YAML and descriptors when
  Collector construction fails, and reject unexpected content metadata or error
  text in the Opik privacy oracle. Three counterexamples have offline regression
  evidence. No new cloud wave, SDK change or claim that previous accepted traces
  contained those violations.

- Extend the observability acceptance scope at the user's explicit request:
  Langfuse and Opik must each qualify the same A10 scenario through native
  transport, complete API readback and authenticated UI diagnosis. Preserve
  Langfuse acceptance; Opik now passes the same finite acceptance criteria.
  The optional isolated recipe accepts an application-owned projection of the
  stock converter's public map. Its Opik profile preserves native/resource
  scalar attributes as metadata with content off. Core instrumentation and
  native identities remain unchanged. Opik native export and complete API
  readback now match33spans,667attributes and12model/usage mappings in the new
  authorized synthetic workspace. Authenticated UI checks match the same twelve
  cases and248native attributes, with seven genuine browser views inspected.
  Preserve intermittent navigation/capture failures as a UI limitation; this
  acceptance does not certify backend availability or browser stability.
  Preserve the500ms/1s failed cloud receipts;
  the finite qualified Opik profile uses3s HTTP acknowledgements without retry.
  Fix the optional VM worker's binary IPC setup: a packet4 length ending in a
  UTF-8 lead byte could stall before payload decoding. Configure only that
  worker's IO as binary/Latin1, preserving safe ETF, limits and the stock client.
- The common nominal1.3.0 candidate runs2157 offline tests without functional
  failures (28excluded); its strict exit1 is retained for fixture warnings. The
  causal test-only correction uses Req's public module adapter with per-owner
  Registry bindings and excludes the separate framework application from root
  discovery. Its136affected tests pass without warnings; the full suite is not
  repeated for this correction.
- Qualify the minimal chat_tools_v1 profile through14real GPT-4o-mini/OpenRouter
  cases and17admissions; operational reserveUSD0.425 is not observed billing.
  PostgreSQL17.4 passes14recovery phases including COMMIT/ACK loss, competing
  resumers and Flow/C7 across VMs. Public recipes, MCP SDK5/5 and real
  LiveViewTest/Oban6/6 retain their exact-source limits.
- Eight independent package graphs pass56runtime contracts across
  Elixir1.18.4/OTP28.0 and1.20.0/OTP29.0.5. Strict dependency diagnostics stay red
  for stock TOML/WebSockex/gproc; no warnings are hidden or upstream code patched.
  Finite load/soak/saturation and owned-resource cleanup are recorded separately.
- Native A10 export and Langfuse API validate33observations,667attributes and
 12model/usage mappings on two fresh traces. User-authorized inspection of the
  authenticated UI matches12observations/248attributes and five screenshots:
  paused/succeeded attempts, stable run/record IDs, retries, usage provenance and
  estimated cents. Content remains off; synthetic tokens are not billing. Exact
  remote CI remains pending; neither Collector ACK nor UI proves durable retention.
- Fix actual ExDoc references, register the execution guide and preserve README
  anchors. The documentation derivative generates104HTML pages with no broken
  owned links. Later changes include documentation, test support and the two
  causally qualified fixes in the optional isolated transport recipe;
  candidate identity and evidence distinguish those from the qualified runtime.
  No version bump, release publication or consumer application migration.

### Official Mint security patch and consumer floor

- Require official Mint1.10.2+ within1.x and pin the root to1.10.2. This addresses
  the maintainer's HTTP/1 framing and HTTP/2 header/frame buffering advisories
  CVE-2026-94194, CVE-2026-91043 and CVE-2026-92103. Consumer applications with
  older constraints or locks must update them; the library lock alone cannot
  protect consumer resolution. See design8.45 and the migration guide.
- HPAX1.0.4, ReqLLM1.24 and every other root lock entry are retained. The official
  TAR checksum is verified; fourteen selected real local HTTP transport cases
  pass in a private graph. Final-candidate, HTTP/2-peer and live-provider evidence
  remain separate. No source patch, fork, version bump or publication.

### Bounded durable host routing and parallel collection

- `Coordination.Flow.new/run/resume` adds a trusted versioned router and flat
  parallel fan-out/fan-in. Leaves use the original agent loop and shared scope;
  structural roots create no Model request. Outcomes and merge follow definition
  order, with explicit `fail_fast` (default) or `collect` failure policy.
- Frame11 has its own selection/merge phases and causal branch failures, while
  readers9/10 and their journals remain unchanged. C7 drains admitted workers to
  DOWN before pause; partial approvals and competing resumes keep the same CAS
  authority. Confirmed historical branches and terminal resumes are data only.
- An admitted Model response arriving during a sibling approval drain can
  persist its real tool batch and share the quiescent pause. Unattached selected
  workers retain `not_started`; explicit recovery of a known interrupted drain
  completes attached work without replaying confirmed IO or starting queued
  branches. Unknown effects/control preserve uncertainty and abandoned budget.
- Resume checks current deadlines only for selected executable branches, binds
  the root deadline to claim, and checks effective deadlines before loaders and
  codecs after a late ACK. Historical or unselected branches remain data only;
  a confirmed claim is retained on rejection without invented refunds.
- Pure host selection/merge require versions and admitted ACKs. Missing outcome
  after a crash remains uncertain without replay or refund. Known fail-fast drain
  can close only from the root owner after every effect is confirmed; collect
  retains failures alongside paused or completed siblings.
- There are at most32 branches and32 live branch workers (default concurrency4).
  Portable branch and merged JSON limits are independently64KiB, reducible and
  persisted. Exact/+1 produces data or an explicit marker/error; omitted typed
  output keeps its original checkpoint evidence. Limits do not promise admission
  of any batch/depth into8MiB, and do not increase payload/global bounds.
- Durable delegation now preserves native tool→delegation→child span ancestry
  during execution/resume, without instrumenting a completed child again. The
  public offline Flow plugin proves7requests/3attempts/2external effects under a
  common application context. Matrix, migration and limits are in design8.44/R6;
  SQL, candidate FULL/package and live acceptance remain separately recorded.

### Public continuation and retrieval recipes

- The external job recipe inspects the same continuation before dispatch:
  pending approvals wait, ready/approved resumes the saved cursor, terminal
  duplicate deliveries return data, and uncertainty requires host recovery.
  The host supplies authentication, versioned definitions and fresh deps.
- External retrieval accepts only a query; its trusted host supplies the space
  and source. Results are bounded and remain ToolReturn evidence. Returned errors,
  exceptions, throws and capturable exits are sanitized at the source callback
  boundary without another call or exposing private messages in partial history.
- A single integration review found that exception gap; the owner corrected it
  with four error-form regressions. MCP binding/SDK and these recipes have bounded
  offline receipts in R7; real frameworks and the final package remain separate.

### MCP endpoint/principal binding for persisted continuation

- MCP Client accepts explicit host `continuation_binding` endpoint/principal
  references and binds transport, protocol and a digest of its public HTTP URL.
  Changed targets or principals cannot spend an existing persisted approval;
  same-principal credential rotation preserves identity. Session IDs, headers,
  credentials, PIDs and executable captures are never persisted as authority.
- Binding lives in private `Tool.execution_binding`, preserving model-facing
  schemas/descriptions and existing local/legacy fingerprints. Unbound MCP tools
  remain ordinarily usable but fail before persisted Model/tool IO. HTTP bound
  URLs reject userinfo/query/fragment; bound stdio confirms the declared revision.
- Historical unbound MCP pauses require a new bound execution and explicit
  approval rather than silent migration. Host references declare identity, not
  peer authentication or proof of credential ownership. See design8.43 and the
  durable MCP binding guide. Combined causal/fresh-VM focal11 and the single R7
  integration review are recorded in the roadmap; no production/SQL/cloud
  qualification, version bump or publication.

### Executable durable delegation and causal failure closure (integration)

- The Frame10 composition producer and restore execute nested delegation through
  the original fenced journal and bounded catalog. Mixed sibling effects and several
  asks drain to a quiescent C7 pause; worker DOWN precedes pause/failure ACK.
- Explicit recovery distinguishes confirmed child raw before wrapper admission
  from uncertain admitted wrapper control. JSON-only fresh-VM continuation preserves
  completed callbacks, authority, usage and exact host counters. Lost ACK retries
  confirm the same command and never dispatch tool/model/wrapper callbacks.
- Confirmed tool/wrapper, retention, rejected-accounting and host preparation
  errors close failed after admitted effects drain. A rejected usage observation
  preserves its marker and confirmed subtotal without a fabricated ledger debit.
  Unknown Model/tool IO keeps its uncertainty guards, requiring explicit recovery.
- Oversized confirmed text/typed child output gets a canonical fatal raw before
  the parent wrapper. The certificate derives the marker from the exact confirmed
  Model/history/output preimage and persisted parent slot; generic node/root failures
  remain closed. Current denial can reject an approved ask with no effect.
- No migration of7/8/9, version bump, publication, router/fan-out/fan-in or external
  backend qualification. Accumulated offline evidence and limits are recorded in R6.
- Preserve ordinary retry controls; only rejected accounting forces a fatal retry
  decision. Restored confirmed raw is checked against the current narrower tool
  slot before its wrapper runs; settlement keeps a marker and fatal control while
  retaining historical raw, effects, completed child and usage. Both paths have
  public C7/recover regressions. Authentic legacy9 CAS/codec fixtures retain the
  old contracts; current10 admission/ACK tests use its actual command shape.

### Durable Frame10 tool slots and typed omission (implementation)

- Frame10 intersects each portable tool-result slot with64KiB. The ordinary1MiB
  payload default previously required24MiB of independent JSON projections per
  call in an8MiB record, rejecting tools/accounting/C7 before tool IO. Record bounds,
  admission and cleanup reservations remain unchanged; a64KiB slot does not promise
  admission of arbitrary batches or nested trees.
- Oversized durable returns retain an omission marker and fail without silent
  truncation or automatic replay. Return a bounded external-resource reference
  when the result needs more space. Ordinary runs and persisted lifetimes7/8/9
  retain their limits. Restore preserves the persisted slot without widening it.
  The canonical Outcome envelope also fits the slot:65536 bytes retain the result;
  65537 retain the marker/error and forbid the wrapper. Usage remains separate.
- A sequence's typed output omission may ACK its completed cursor while returning
  a checkpoint error and blocking successors. Delegated omission remains unable
  to produce successful raw parent data. No snapshot migration, version bump or
  publication. Verification is recorded in R6 after integration.

### Internal Frame10 compositional exhaustion capacity (accepted internal subset)

- Reserve every possible subset of terminal output copies alongside still-pending
  sibling branches, crediting only the exhausted node's retired slot in each
  closure alternative. No second raw-result credit, schema/limit/guard changes.
- Source−1/exact/+1 and per-phase conservation verified across eight permanent
  variants, plus corruption/oversized-raw negatives. Existing typed/plain closure,
  callfatal, control/receipt and qualified accounting tests remain green.
- Original boundary remains historically red at its sink-funded "roomy" setup;
  separately authorized two-line copy passes without changing source assertions
  or production limits. Independent review and previous parent probes passed;
  receipt/provenance in `docs/development/r6-implementation.md`. No producer/VM/R6
  acceptance and no new runtime tests for this documentation update.

### Internal Frame10 certified output exhaustion (accepted internal subset)

- Preserve OutputResolution1 keys and retry decision as terminal invalid-output
  evidence at exact exhaustion, not another retry permission. Atomically append its
  final parts once without incrementing used, certify NODE failure/frontier and
  canonical delegated raw. Validate original Model/descriptor/history/counts; never
  decode callbacks, fabricate requests or admit generic failed-output records.
- Select confirmed CALL/NODE errors by structural order; drain only admitted work,
  retain ambiguity guards, completed children, raw/partial results and qualified
  usage. Reuse failed closure and current-claim refund exactly once.
- Reserve mandatory terminal copies before validation; spend only their matching
  history/control/receipt credits. Source-prefix capacity tests, not later sinks.
  Legacy7/8/9 and producer/restore guards unchanged; no schema/version migration,
  public runtime/VM/R6 acceptance, new retry API or release bump.

### Internal Frame10 final-control capacity correction (review pending)

- Spend each call's existing metadata allowance as its final control materializes;
  keep the bounded control slot independent of success/cancellation alternatives,
  raw sources, frontier and future history. No payload/limit or legacy changes.
- Spend the child/host settlement receipt exactly once (effect-backed calls already
  release theirs), and the batch-resolution receipt on materialization. Consumed
  batches do not receive a second credit. Preserve successful consumption capacity.
- Real-CAS source-prefix ±1, maximum escaped receipts/control and plain/Unicode/
  escaped return regressions; no producer10, VM/R6 acceptance, migration or bump.

### Internal Frame10 confirmed call-fatal terminal closure (review pending)

- Add fenced internal finish after admitted work drains: preserve selected exact
  fatal, all evidence and confirmed partial results; block unfinished calls and
  cancel only eligible nonterminal nodes without synthetic returns or consumption.
  Completed children and settled calls remain immutable. Ambiguous callbacks and
  running/unknown effects prevent closure/refund; no new admission after fatal.
- Atomically release ownership and refund the current claim once using existing
  budget math. Reserve alternative success/cancellation projections before admission,
  independently of receipts/frontier; retain materialized data without double credit.
- Data-only Continuation.get reports failed10; terminal deletion remains retention
  guarded and structural reset remains closed. No legacy failed state, public
  Composition.resume10, producer/VM/PID-drain guarantee or new recovery API. Other
  fatal origins, output exhaustion and general cancel/expire remain closed/pending.
  No format migration, bump or publication; cumulative independent review required.

### Internal Frame10 final-control fatal drain (partial, review pending)

- Atomically retain confirmed wrapper result/control and close new admissions;
  select call-origin errors by structural path and original response order, not
  arrival. Already admitted outcomes/wrappers can persist without new IO or replay.
- Globally reject historical/unbound fatal continuation; preserve raw sources,
  immutable completed children, qualified usage and ambiguous callback markers.
  Reserve the additional bounded frontier projection independently of tool/output
  slots before batch admission, crediting only materialized frontier bytes.
- This is not failed-terminal support: raw/host/root/node fatal, exhaustion,
  blocked/cancellation and terminal refund/facade remain closed and pending.
  No producer10, legacy migration, budget math changes, VM/R6 acceptance or bump.

### Internal Frame10 successful structural closure (review pending)

- Add fenced `step_output` CAS from confirmed plain/typed output: immutable step
  prefix/input, ordered advancement and atomic root completion. Certify every node,
  consumed batch and terminal state; preserve scope, qualified usage and authority.
- Return only the current claim's unspent active budget using existing refund math,
  once; no delegated refund or replay debit. Reserve plain result copies/receipts
  at response ACK alongside the existing typed-output reservation.
- Data-only Record/get inspection accepts certified completed10. Public composition
  resume10 remains closed; its definition-bound terminal projection is a pending
  consumer seam, not a partially enabled runtime. Trusted attestations do not prove
  callback semantics or authenticate arbitrary snapshots. No schema/ledger change,
  legacy migration, producer10 activation, failed/recovery expansion or release bump.
  Real-CAS tests are not live callback/VM/SQL or R6 acceptance.

### Internal Frame10 output capacity correction (review pending)

- Reserve pending attested output history/result copies and canonical delegated
  raw/observation growth before ACK, with one consumable receipt slot. Credit only
  the matching tool result projections, never the same bytes twice; consumed and
  historical output entries retain evidence without a repeated pending charge.
- A checkpoint too small for mandatory consumption now rejects output_resolution
  atomically instead of accepting an unconsumable attestation. No payload truncation,
  larger limit, producer10 enablement, legacy7/8/9 migration or accounting changes.
  Real-CAS boundary/escaping/replay/sibling regressions are not product/VM acceptance.

### Internal Frame10 typed output/retry CAS (review pending)

- Admit trusted output attestations through fenced CAS and globally certify their
  Model source, descriptor/hash, history position and exact retry counters/limits.
  New internal `output_consume` consumes retry once without admitting a request;
  approval drain/pause/decisions/reclaim retain that evidence.
- Typed delegated `node_complete` consumes success and creates canonical child raw
  atomically. Raw X may subsequently settle as wrapper Y; no second usage contribution
  or historical repricing. Validation/hook callbacks never run on data decode.
- Existing persisted formats and legacy7/8/9 producers are unchanged. No automatic
  migration, public mode or release bump. Uncertified exhaustion/fatal/rootterminal/
  recovery and producer10 remain outside this internal subset. Real ETS/CAS tests
  use synthetic trusted command inputs, not live hooks/VM10/SQL or R6 acceptance.

### Internal Frame10 qualified accounting (review pending)

- Correlate non-null Model/tool usage with existing CAS outcomes, observations and
  Scope2 operations. Preserve availability/quality/costs, ancestral sums and exact
  host counters; no historical repricing, wrapper/delegate redebit or receipt replay.
- Tool outcome accepts optional trusted usage separately from ToolReturn history,
  whose codec remains unchanged. Partial10 completeness uses availability; legacy
  certificates retain their existing rule. ScopeLedger aggregation now uses its
  existing nil-capable decoder, never treating absence as zero.
- Apply existing retrospective token/cost and request/tool limits at new admissions.
  Invalid/retained/oversized accounting rejects atomically with confirmed progress
  intact. No new ledger/Usage format, migration, producer10 or unsupported terminal/
  fatal/recovery expansion.26 new synthetic-input real-CAS tests; selected regression
  235 passes and2 original probes pass separately after the authorized old Model
  oracle update. Injected wrapper usage still rejects; forced compile112WA, global
  format/diff pass. Historical red runs remain recorded; independent review pending.

### Internal Frame10 causal fixes (independent review pending)

- Reject new model intents over non-executable history and unknown child finals;
  preserve confirmed evidence and unresolved wrapping, without implicit recovery.
- Credit actual materialized raw/final/leaf-result JSON against the existing closure
  reservation; retain worst-case future slots, metadata and cleanup/receipts. No
  larger limits or smaller coefficients.
- Certify observed post-before-hook malformed/schema failures through the fenced
  preparing transition, preserving original identity/hash and exact status/retry.
  Do not revalidate original arguments or fabricate effective bindings.
- Internal unpublished10 only: invalid previously tolerated rows now reject;
  legacy7/8/9 and producer9 unchanged, no automatic migration or release bump.
  Real-CAS regression evidence is not producer10/VM/SQL or product acceptance.

### Internal Frame10 CAS checkpoint (pending independent review)

- Build records from real Store create/claim and narrow, fenced operations through
  nested mixed B→D pause, two public decisions and reclaim/frontier. Roundtrip each
  ACK; atomic child/source/scope/authority, raw observation and final leaf outcomes.
  Child raw X can settle as Y only after wrap ACK; no generic receipt authorization.
- RequestData2 retains exact portable tool fingerprint preimages for Frame10-only
  delegated input/ref/schema checks. RequestData1 bytes and producer9 remain intact;
  no automatic migration, public mode option or publication.
- Unknown/malformed/schema host failures need no invented binding/effect; prepared
  permission denial keeps its projection. CAS/capacity failure does not manufacture
  not-executed results. Conservative closure reserves reject before tool phases.
- Verified113 focal cases (14 new),207 selected legacy cases. Trusted command inputs
  are not live workers, VM, SQL or producer10 acceptance. Non-null external usage,
  output resolutions/retry, root terminal/recovery and fatal/output_failed remain
  rejected: this checkpoint is not completion of the full transition mandate.

### Internal Frame10 source preparation (not runtime admission)

- Add pure child-terminal raw projection and SOURCE certificates. Failed10 is
  explicitly lossy: portable error.message determines content; complete error stays
  in control. Future producer and restore must share this helper. Legacy7/8/9 and
  ordinary delegation are unchanged; no persisted migration or release bump.
- Certify the exact observed host permission-denied variant without fake effects.
  Other host failures, current authority and final-wrapper evidence remain closed.
  Synthetic tests are not producer/VM/atomicity acceptance. Global evidence10,
  Record execution10 and transitions remain rejected.

### Active sequence evidence — bounded offline acceptance (2026-09-29)

- Accepted active Frame9 final/resolved/accounting-accepted batches, own continuable
  prefixes and current attested output retry/success, including historically consumed
  approvals. Same `Composition.resume/3`, explicit recover and exact reference; no
  API/format migration. Legacy7/8/single9 and C7 first-all-pending remain accepted.
- Owner FULL1845 passes/28 excluded/1410.3s exit0, compile109WA/global format/diff0;
  favorable review40 existing+4 own cases,9+306 identities. Parent checked9 hashes
  and roundtrip copy, reran the same4 corrected probes:4 passes/16.7s/exit0. Owner55
  cases are25+30. Reports/hashes: [R6 implementation](development/r6-implementation.md).
  Owner54/55 red→focused4→FULL green and harness failures remain historical. Review
  original3/4 wrong allow-over-ask oracle stays red; separate corrected copy4/4,
  no source fix. Current allow cannot widen original ask.
- Consumed approval is resolved history, never authorization for a new request even
  with identical call ID/args. Global Record/retry-plan guards precede private views;
  reducers retain original records. No historical repricing/redebit; exact host
  counters remain distinct from qualified normalized/estimated usage. Current fatal
  is operational failure without C/final refund; historical fatal rejects, typed host
  preparation retains precedence. Structural retry stays unsupported; a tool exception
  leaves unresolved intent, not a confirmed unknown outcome.
- Inflated token parsing is separate from valid CAS/JSON+cleanup/receipt capacities.
  ETS and cross-VM files do not certify SQL durability; started callbacks have no
  atomic preemption promise. No mixed/raw/uncertain/delegation/router/parallel/general
  R6 or SQL/live/production acceptance. Next: read-only structural research into
  delegation+C7 quiescence/mixed control; no further implementation activated.

Historical functional checkpoint and owner matrix, before acceptance:

- Extend the same unit with30 active-history matrix cases (55 total): consumed
  approval authority/binding/effective args, qualified contributed tool accounting,
  observability deadlines, ownership/fencing and exact capacity boundaries. Runtime
  is unchanged from the functional checkpoint; token parsing is tested separately
  from valid CAS capacity. Final verification and independent review status are in
  [R6 implementation](development/r6-implementation.md).
  Final integrated FULL:1845 passed/28 excluded,1410.3s,exit0; forced compile109 WA,
  global format/diff pass,306 source identities unchanged. Independent accumulated
  review and parent acceptance remain pending.
- Restore resolved active Frame9 tool batches/prefixes, terminal text after tools,
  and current attested output retry/success using existing consumers. Retain consumed
  approvals as immutable history, bound by run/request/call and complete safe batch
  resolution. Global validation and administrative retry-plan guards remain intact.
- Two real fresh VMs continue A→B public approvals→resolved batch→output retry→B→C
  with no historical replay/repricing:6 requests,3 tools,cost58.25 new cases cover
  control order/retry counts, current deny, CAS, late ACK, Store-only tokens, corruption,
  fatal/preparation precedence and abandoned finite budget. Exact verification and
  remaining matrix are in [R6 implementation](development/r6-implementation.md).
- No API/persisted-format migration or version bump. Explicit recover and exact
  references remain required. Independent review and acceptance remain pending;
  this does not accept mixed/raw/delegation or general R6.

### Experimental sequence approvals — bounded offline acceptance (2026-09-29)

- Accepted first all-pending own batch on Frame9 sequences: confirmed paused root
  and leaf projection, halt before C, host decisions and new-claim VM resume without
  prefix effect replay or repricing, exact counters/reservations/root refund.
  Owner FULL1790 passes/28 excluded/1121.2s exit0 is separate from favorable review
  271 existing+7 own probes, compile108WA/global format/diff0 and15+303 identities.
  Parent checked15 hashes/helper/runner and a roundtrip-verified copy, then reran the
  same7 probes:7 passes/13.2s/exit0, not additional cases. Owner57 cases are43+14.
  Reports/hashes and accepted old-test provenance are in
  [R6 implementation](development/r6-implementation.md); historical failures remain.
- All-pending certification follows async results; mixed siblings can already have
  effects and fail closed without pause/refund. No atomic batch preadmission promise.
  Current permission deny may yield denied outcomes and continue C without B tools;
  administrative deny is terminal. Declared refs/policy reject preclaim; current
  schema/actual Model binding checks are postclaim. Inflated token parse−1/exact
  candidates return invalid_command, +1 invalid_checkpoint_token, not oversized
  valid commits; JSON capacity is separate. Already-started callbacks are not preempted.
- No general R6/mixed/raw/delegation/router/parallel, SQL/live/production or MCP
  endpoint/principal binding acceptance. Next work is read-only investigation.
  Host run/get/decide/resume usage and directional Record2/Frame9 compatibility are
  documented in design8.41; this receipt is documentation after the reviewed bytes.

Historical owner implementation/verification, before independent acceptance:

- Pause a Frame9 sequence at an active leaf's first all-pending functional tool
  batch. Return confirmed paused root/step projection, no output, real continuation
  reference and no successor execution. Persist root snapshot/runtime unchanged;
  the child stays running. Lost ACK exposes only confirmed partials and real tokens.
- Use public continuation decisions: partial pending, final approve ready, deny
  terminal; decisions perform no execution or claim. Resume approved batches with
  current authority, existing batch reservations and immutable historical approvals.
  Human wait excludes active budget but retains TTL/logical deadlines; old persisted
  deadlines remain restrictive. Mixed batches may already have sibling effects and
  reject without a quiescent pause or refund.
- Explicit experimental Record2 extension with existing Frame9/Approval1: older
  readers reject new C7 rows; no migration, duplicate mode or version bump. Consumers
  must handle paused and explicitly inspect/decide/resume. Global journal validity
  does not imply partial approved effects are safely resumable.
- New43 VM/ACK/CAS/time/corruption/capacity cases; owner FULL1776 passes/28 excluded,
  1098.2s, exit0. Forced compile108 WA, global format and diff pass;303 source paths
  unchanged across FULL. Exact evidence and independent review status are tracked
  in [R6 implementation](development/r6-implementation.md).
  No independent C7/R6 or production acceptance is claimed.
- Additional owner matrix:14 cases isolate token parsing ±1 from CAS record capacity,
  exercise post-approval refs/policy/schema/current Model binding changes and hold
  approved-tool/next-Model observability across real budget/lease expiry, with timely
  controls. Runtime unchanged;129 focused cases and integrated FULL1790 passes/28
  excluded (1121.2s, exit0); forced compile108 WA, format/diff pass. Evidence and
  old-test provenance are recorded in R6 implementation; independent review remains open.

### Experimental Composition.resume — bounded offline acceptance (2026-09-29)

- Accepted ready Frame9 empty/between/input without own operations, safe text terminal
  without own tool history and admitted typed-success; completed remains data-only.
  Explicit administrative recover, exact closed-tree import and inert prefix accounting
  preserve the same lifetime without replay/repricing. Finite abandoned budgets still
  deny; unlimited recovery stays subject to current limits. Old persisted deadlines
  are not expanded. Host counters remain distinct from qualified normalized/estimated usage.
- Final owner FULL1733/28 excluded/967.8s exit0; fresh favorable review29(2+10+17)
  +113 focused+3 observability; parent checked6/6 identities and reran the same15
  (2+10+3) probes in12.6s exit0, not15 additional cases. Receipt and report hashes:
  [R6 implementation](development/r6-implementation.md). This supersedes the historical
  pending-review statements below, preserving P1/P2 reds, harness failures and old10ms
  sampling results. No active multileaf batch/output retry, raw/uncertain, C7 compositions,
  delegation, router/parallel, general R6 or SQL/live/production acceptance. MCP SDK
  qualification stays separate; no R7/A9/G4 expansion or publication.

Historical implementation and fix evidence, before the final receipt:

- Recheck effective Scope authority after durable Model intent ACK and observability
  callbacks, immediately before buffered/stream dispatch. Shrink the timeout using
  the same original deadline. Expired attempts return the existing RunError without
  Model IO, preserving committed unresolved intent and confirmed partial state; no
  outcome, refund or replay is invented. Shared run/resume/stream fix, no persisted
  migration or API change. Seventeen permanent dispatch tests cover expired and
  timely Model/tool ACKs. Final worker FULL1733 passes/28 excluded,967.8s,exit0;
  compile107 WA, global format and diff pass. Independent review and acceptance
  remain pending; final identity and preserved red evidence are in R6 implementation.
- Correct review P1/P2: active restore and normal descriptors share one monotonic
  deadline fixed at fresh claim ACK, including owner/codec/preflight elapsed time.
  Known expiration rejects the next preparation phase or IO without renewing the
  reservation. Root option values use the existing structural Scope validator before CAS,
  returning bounded RunError without consuming a claim. No compensating refund,
  persisted migration or new validation policy. Consumers should handle these
  existing error reasons, including rejection of model-unaware root estimators;
  ordinary nonstructural estimators remain valid. Already-started callbacks are not rolled back.
  Original independent probes reproduced three failures, then all ten passed;
  ten permanent regressions added. Final worker verification (2026-09-29):
  FULL1716 passes/28 excluded,948.9s,exit0; forced compile107 WA, format and diff
  pass. Final identities are recorded in R6 implementation. Fresh review is still required.
- Resume exact public references with strict run options and explicit administrative
  recovery. Reuse the journal, Scope and Writer; completed prefixes are inert and
  preserve historical accounting/prices. Admit empty/between/input and safe text or
  typed-success terminal multileaf boundaries; singleton7/8/9 subsets remain intact.
- Preserve claim/output/input ACK-before-IO and real pending tokens. Completed reads
  need no claim or callbacks; expired historical leaf deadlines do not block suffixes.
  Finite abandoned budgets remain exhausted. New runs distinguish logical root
  authority from per-attempt lease/budget; existing stored deadlines are not relaxed.
- Bind current root deadlines into claim CAS and recheck time after receiving ACK,
  before owner/model callbacks. A late confirmed claim stays visible in the partial
  without granting further execution; an unacknowledged claim keeps its real token.
- Additive experimental API, no persisted migration, version bump or publication.
  Host must explicitly recover expired claims and use the returned exact revision.
  Active multileaf tool history, retries awaiting output, raw/uncertain, C7 and
  delegation remain unsupported. Owner verification:33 new cases and integrated
  FULL1706 passes/28 excluded,933.0s,exit0; forced compile107 WA and format pass.
  Evidence in R6 implementation; independent review remains pending.

### Experimental Composition.run — bounded offline acceptance (2026-09-28)

- Correct admission failures mislabeled as mapping: preserve bounded quota/deadline/
  capacity reasons and report preparation, while genuine mapping failures remain
  mapping. A trapping caller losing Writer now receives operational RunError,
  only previously received confirmed state, partial usage and no invented token.
  Includes open and both record/metadata read boundaries; normal linked death stays.
  Experimental bugfix, no persisted migration; consumers should handle the original
  admission reason instead of invalid_composition_input. Independent fix review is
  favorable; the sealed probe remains4/5, with its old-reason assertion corrected
  only in an authorized copy, independently checked and rerun by the parent.
- Add durable fail-fast execution with required continuation configuration, strict
  root/step options, one Scope/Writer/claim and existing OTel tracing. Completed
  inspection shares the portable confirmed projection, including ordered steps,
  qualified ancestral totals, omission markers and claim attempt identity.
- Operational RunError partials expose the confirmed prefix, failing step/phase and
  existing checkpoint token before cleanup. No model objects or live outputs are
  used as completion evidence; rejected/unconfirmed accounting stays partial.
- Additive experimental API for the pending major; no persisted migration, new
  resume API or active multileaf restore. Internal completed inspection now returns
  the expanded result. Verification and the exact boundary matrix are in R6
  implementation. Acceptance covers durable sequential execution and completed
  data-only inspection, not C7 compositions, raw/uncertain recovery, delegation,
  routing/parallel execution, general R6 or production.
- Add real sequence capacity probes for Writer admission, full JSON plus cleanup,
  checkpoint tokens and receipts at minus/exact/plus one. Real CAS checkpoints
  grow the receipt journal; cancellation preserves uncertain intents and does not
  refund abandoned reservations. Runtime and persisted contracts are unchanged.
  Final owner FULL1673 passes (28 excluded),885.2s,exit0; independent review62
  focused+5 corrected prior probes+2 new terminal-loss probes passes. Parent checks
  26 source hashes and the single assertion correction, then reruns the same7
  probes,7 passes/3.3s/exit0, not7 additional cases. Historical FULL1651/1652 stays
  failed. Evidence identities are in [R6 implementation](development/r6-implementation.md).

### Frame9 durable sequence vertical — bounded offline acceptance

- New structural roots use9. The internal step seam now runs A→B→C through one
  Writer/Scope/CAS journal, with persisted-output mapping and PID/revision/index
  tickets consumed before attach CAS. Intermediate output preserves the root
  claim/lease/budget; final output refunds once from that claim.
- Explicit9 accounting, partial evidence and reservation paths preserve completed
  prefixes. Active multi-leaf restore remains blocked before claim; validated
  completed sequences are data-only. Legacy7/8 lifetimes keep their versions.
- At that phase1 milestone there was no public execution API or migration; phase2
  integration and acceptance are recorded above. Evidence and boundary matrix
  are recorded in R6 implementation; broader recovery remains open.

### Historical Frame9 validation groundwork — preparatory milestone

- Add explicit structural validation of ordered sequence prefixes, `between_steps`,
  exact binding/authority links and omitted-predecessor rejection. Partition tool
  and output evidence by leaf while retaining global orphan checks and globally
  unique host request IDs; provider call IDs may repeat across requests/leaves.
- This is preparatory internal work: new roots still use8; Record/Writer do not
  yet admit9. No persisted migration or public execution API is enabled. Existing
  lifetimes and authentic historical fixtures remain unchanged.
- Owner31 new tests and focused523 pass offline. Combined evidence tests use
  independently executed leaves, not a durable A→B→C execution. Producer/transitions,
  tickets, terminal refund, restore and the remaining phase1 matrix are pending;
  no sequencer acceptance is claimed. Details in R6 implementation.

### Internal Frame8 final/control restore — bounded offline acceptance

- Bounded consumption of confirmed tool prefixes and resolved current
  batches, selecting the current request before historical output attestations.
  Ordered portable control and lifetime counters survive restore without effect
  replay or duplicate accounting. New IO retains current/original authority.
- No persisted migration or public API addition; legacy tool histories, unresolved,
  uncertain, raw/no-control, rejected/omitted evidence, approval/retry-plan profiles
  and delegation/A→B remain blocked. Acceptance covers single-leaf Frame8 only;
  general R6 and SQL/cloud/live qualification remain open.
- Fatal recovery returns bounded portable control data (or derived retry exhaustion),
  not reconstructed BEAM exceptions. Returns append once; current output configuration
  and model preflight still apply. Preparation/retention errors preserve confirmed
  history without contradictory tool stubs. Lower admission quotas do not retroactively
  invalidate historical close/fatal, while further IO uses intersected authority.
- Owner matrix99 and focused261 pass. Both obsolete restore exclusions were updated
  under explicit authorization. The separately authorized MCP deadline oracle now
  accepts either normal transport completion or guardian kill with exact PID/ref;
  two deterministic ordering tests preserve socket, timeout and late-success checks.
  MCP runtime unchanged; owner final FULL1568 passes/28 excluded,716.8s,exit0.
  Independent review50 distinct cases (43 focused+3 independent+4 adjacent) found
  no reproducible P1/P2. Parent verified12/12 source hashes and reran the3 intact
  probes,9.3s,exit0, accepting this bounded slice. Evidence identities are in
  [R6 implementation](development/r6-implementation.md); historical failed gates
  and the diagnostic remain recorded with their original results.

### MCP Streamable HTTP — integrated, bounded offline acceptance

- Add opt-in `transport: :streamable_http` with an application-owned Finch pool
  explicitly configured HTTP1-only; public metrics cannot reliably detect HTTP2.
  MCP2025-06-18 supports bounded JSON and terminal-aware SSE, exact request IDs,
  session invalidation, deadlines and worker cleanup without redirect or effect replay.
- HTTP consumers configure/supervise the pool, handle uncertain remote effects and
  explicitly reconnect after session expiry. Close can return a DELETE error while
  still stopping the client. Existing stdio consumers need no migration.
- Discovery uses normal Tool schema/permission validation; pagination and nontext
  results reject explicitly. Limits bound host postdelivery retention, not upstream
  allocation. No persisted format migration or version bump.
- ROOT integration accepted by the parent after diff/docs review,377/377 manifest
  checks and9/9 paths byte-identical to the private delivery. Parent review77 cases
  (8 intact probes+69 adjacent),20.9s exit0, is separate from owner FULL1467/28/508.9s
  and private acceptance121+6+2/parent8. REPORT9b192949 and `parent-review.*` evidence
  are identified in the [roadmap](development/roadmap.md); this receipt is docs-only.
- Bounded SDK interoperability accepted2026-09-28: official Python mcp2.2.0,
  stdio2024-11-05 and HTTP2025-06-18 JSON/SSE × session/stateless, localhost text tools
  through real Client/Tool/permissions. Owner5/5 and independent review5/5 are the
  same cases, without skips; parent checked source identity, not another test run.
  Harness integration remains pending. HTTP limits65KiB/pending4/tools4 do not apply
  to stdio defaults8MiB/128; this was not a stress test. Reports/hashes in roadmap.
- Persisted C7 endpoint/principal binding, OAuth/TLS, SDK cancel/reconnect/chaos,
  protocol2026 and other SDKs remain unqualified; no multileaf/SQL qualification
  or closure of R7.4/A9, R7, G4 or general R6.

### Durable pause observability — bounded offline acceptance, pending major

- Paused runs close their span as `paused` without an OTel error. Resume has a new
  attempt/span under the same lifetime identity. Add bounded `exagent.attempt_id`
  and allowlisted public continuation identity, never actors, tokens or records.
- Continuation references must be plain maps without `__struct__`, with integer
  version exactly1 and validated bounded IDs. Invalid references are omitted as a
  whole while independent valid result IDs remain available.
- Migration: dashboards must distinguish a paused attempt from durable completion;
  correlate run/attempt/continuation record IDs. Request/tool counts and usage are
  cumulative lifetime snapshots, not successful effects or per-attempt deltas.
  Do not sum resumed snapshots or root/child/generation totals. No persisted migration.
- Private review145+9 and parent9 accept this bounded projection; ROOT integration
  is now accepted after independent review9+69 (REPORT c58bcc93). Earlier FULL1423/28
  remains integrator evidence, separate in the roadmap. Administrative tracing and G4/backend
  acceptance remain open; Langfuse is provisional, not a final platform selection.

### Internal Frame8 tool evidence — accepted offline

- Independent per-effect accounting observations and ordered
  postsettle control, with durable rejection of invalid/omitted/nonportable usage
  and explicit partial totals. Existing Message/Outcome1/RequestData1/Record2/Scope2
  shapes remain; Frame8 introduces `tool_batches` only for new structural roots.
- Migration plan: existing Frame7 lifetimes keep writing7, without inferred
  observations or relabeling. The producer alone did not enable tool restore;
  the accepted final/control exception is described above. Tool-free subsets remain.
- Raw observations and accepted accounting commit before ACK/after-hooks; invalid,
  omitted or nonportable usage is rejected durably before applying an external
  contribution. Partial totals remain visible after refresh and in persisted usage.
- Ordered postsettle control uses the same pure retry reducer, preserves the first
  fatal error, and commits before further work. Batch-wide evidence/cleanup is
  reserved before tasks. Historical schemas use request-local limits.
- CompositionRestore's discriminator accepts7/8 while retaining all executable
  guards; completed remains data-only. Verification and independent review status
  are tracked in the R6 implementation document; no publication is implied.
- Independent review95 cases and parent7 intact probes accept the producer/validator
  only. Owner FULL1409/28 is separate evidence; ambiguous legacy usage/retry is not
  migrated or relabeled. General tool restore and R6 remain pending.

### Runtime-owned Model-hook counters — accepted offline, pending major

- Model hooks can observe but cannot replace `tool_retries`, `output_retries_used`,
  `run_step`, `tool_calls`, `max_steps` or `agent.output_retries`. Writes are ignored
  after each capability, before the next callback and admission/persistence/IO.
- Migration: configure limits before starting the run and remove counter overrides.
  Valid model/settings/agent/tool selection, selected tools' `max_retries`, request
  projection and response transformations remain supported. Generic map pipelines
  retain their behavior; malformed callback results are not repaired.
- This behavioral change targets the pending major, without a version bump. It
  introduces no persisted evidence or migration of ambiguous legacy counters and
  does not close persisted retry/usage integrity or enable additional restore.

### Internal historical tool batch integrity — accepted offline

- Structural Frame validation binds consumed function-call batches to their exact
  request cardinality. Output-resolution siblings do not admit batches.
- Decode and CAS reject coordinated batch reductions even when ledger totals agree.
  Valid records require no migration; historical costs are not recalculated and nil
  usage requires no invented contribution. Legacy agent/raw contracts remain unchanged.
- Tool usage integrity remains blocked: serialized ToolReturns and outcome hashes
  omit usage. Existing history cannot prove per-call contributions; a persisted
  evidence contract must be decided before adding that validation.
- That batch-only change did not enable tool-prefix restore or protect retry counters.
   Independent review accepts batch cardinality only; functional restore remains pending.

### Internal attested output-chain restore — accepted offline

- Extend the internal confirmed-output boundary beyond the first response, selecting
  only the current request's attestation. Earlier retries and nonexecuted siblings
  remain immutable history; existing counters, authority and admission apply.
- No historical revalidation/repricing, new format or migration. Unattested textual
  chains, tool batches, uncertainty and multi-step compositions remain excluded.
- Confirmed later success/retry attestations can resume after repeated interruptions.
  Retry counters include historical call-less retries; repeated call IDs are scoped
  to their requests. Only the current descriptor is compared with host configuration.
  Success stays data-only; retry prepares host configuration after claim and admits
  a new request under current and original authority. ACK retries remain Store-only;
  a current outcome without attestation still cannot execute.
- The runtime delta is confined to CompositionRestore. Existing validation, consumers,
  formats and bounds remain in use, with no artificial response-count limit. The
  owner matrix passes134 cases, including fresh VMs, CAS, crashes, mixed history,
   corruption and exact retention boundaries. Independent review accepts this bounded
   slice; general R6 acceptance remains pending. Evidence is in the R6 implementation document.

### Internal confirmed output-retry consumption — accepted offline

- Bounded first-response retry recovery consumes attested parts without
  revalidating historical arguments. Unlike success-only consumption, future
  requests require host schema reflection after claim and current admission.
- Executable output configuration is prepared once per winning attempt and compared
  against the exact persisted descriptor/fingerprint. Host refs and typed/tool profile
  precede claim; Model bindings and validate_resume remain enforced. JSON cannot
  choose a module, and historical arguments are never revalidated.
- Exhaustion diagnostics use persisted Retry.content, not reconstructed Ecto
  errors. Consumption belongs to the existing next-request intent; ACK retries
  remain data-only. Later interrupted response boundaries were outside this first
  accepted slice; the attested-chain extension is recorded above.
- Failure protection preserves unconsumed evidence and is removed after appending
  attested parts, allowing normal failure handling of future responses. The live
  loop can continue normally; completed output and existing tokens remain data-only.
- No new format/token, migration, publication or general R6 acceptance is implied.
  Independent review accepts only the bounded first-response retry slice.

### Internal confirmed output-success consumption — accepted offline

- Frame7 first-response output-tool success can close from its single portable
  attestation using the existing CAS, Scope and Writer. Both preparation paths
  avoid Ecto/schema reflection; exact attested returns are appended once, including
  nonexecuted siblings, without a new output resolution or Model request.
- Restored output is JSON-normalized data, not an Ecto struct; live output is
  unchanged. Versioned host references and typed/tool profile are checked before
  claim. Unversioned host code changes are not detectable; persisted descriptors
  never select modules or authorize new validation. No public bypass or new format.
- Attested omission rejects before claim. Terminal-copy omission retains existing
  retention errors. A too-small history limit preserves confirmed history in the
  error instead of fabricating conflicting returns. No migration, retry/raw/general
   resume, A→B or SQL/live qualification is announced. Independent review accepts
   only this bounded offline slice, not R6 as a whole.

### Internal first confirmed text restore — accepted offline

- Narrow Frame7 text/tool response boundary using the existing claim, loop and
  Writer, without another Model request or historical repricing. Typed/native,
  retries, tools and output attestations remain unsupported. No new format or
  migration. Fresh-VM JSON recovery, CAS losers, persistence-only ACK retries,
  historical pricing/quality and exact retention boundaries are covered offline;
  independent review accepts this bounded slice. Admission limits do not retroactively
  debit historical effects; closing consumes no new request. Logical time, active
  reservation and retention still apply. Reconstruction codecs/binding and winner
  registration are allowed; this is not a promise of zero callbacks globally.

### Internal composition input0 restore — accepted offline

- Independent review accepts only the input-confirmed/request0 boundary with no
  prior operations, plus completed data-only reads. It does not accept general
  restore, response/raw/pending output boundaries, sequences, or SQL/live operation.

- Fresh review found that restoring a leaf replaced its current singular
  `permission_floor` with persisted Frame3 permissions. Restore now adds the
  persisted floor to the conjunction, preserving the current singular/plural
  floors and policy order. Integrated root/leaf deny/ask regressions cover both
  current restrictions and restrictive originals. No format or scope expansion.

- Frame7 persists original effective root/leaf authority, intersected with current
  host restrictions on restore. Legacy Frame4–6 remain readable but cannot execute
  without authority; no inferred migration. Record2, leaf Frame3 and Scope2 remain.
- Internal `resume_composition_step/3` supports only confirmed input/request step0
  without operations, using a fresh CAS claim before codecs and the existing loop.
  Completed results are portable data-only; omitted output remains an explicit error.
  Other boundaries reject before callbacks. This is not general composition resume,
  sequences, delegated approval, or independent acceptance of R6.

### Internal single-step composition persistence (partial)

- Frame6 introduces versioned structural output-resolution attestations, without
  changing leaf Frame3 or silently extending Frame5. Typed output and its siblings
  are distinguished from function dispatch using the request's bound output
  descriptor; call-bound Retry parts require provenance too. Existing valid
  Frame5 records without output remain readable, with no fabricated migration.
- Capacity projections validate a coherent current/command pair for concurrent
  tools: sibling outcomes accompany synthetic confirmations, while the target
  remains running until the projected command. Live effects are never confirmed
  by capacity simulation. Output-tool descriptors are bounded at65536 JSON bytes
  before Model admission; native/text output does not acquire this bound. Terminal
  omission of a duplicated result is tied to the retained portable attestation.
  The integrated single-step scope is independently accepted offline. Frame6
  children remain included in receipt/cleanup capacity reservations; exact limits
  and one-over rejection are covered. This does not accept executable restore,
  sequences, SQL/live compatibility, or R6 as a whole.

- Frame5 now verifies historical ToolReturns and intermediate outcomes against
  their node/request/call journal evidence in both directions, including hashes,
  status and tool binding. Forged/mutated returns reject at CAS and decode;
  legitimate pre-dispatch errors and retained omission markers remain readable.
- Failed pre-write step capture/capacity checks discard only the exact empty Scope
  adhesion. Pending or confirmed input and nodes with operations are never removed.
  No ledger rollback, format migration or public composition run/resume is added.

- An internal ExAgent seam executes one real leaf under the existing structural
  Writer/Scope: `step_input` confirms its portable input and explicit step link
  before Model IO; `step_output` confirms output and terminal cursor afterward.
  No synthetic parent tool/request, second Store, or alternate agent loop.
- Frame5 explicitly carries step links and the existing Frame3/ServerSnapshot leaf.
  Empty-only Frame4 and legacy agent formats remain readable and unchanged.
  Record2 and the identity-only root snapshot keep their formats. Root authority,
  admission, active budget, accounting, CAS and checkpoint retries remain shared.
- Data-only restored progress distinguishes input-confirmed/running/completed;
  ACK retries do not rerun mappings or leaves. This is **not executable resume**
  from bytes: persisting/restoring the root authority floor remains necessary.
  No public Composition.run/resume, A→B sequencer, delegated approval, or complete
  composition C7 is announced. The following sections retain earlier milestones.

### Host composition definitions — execution still pending

- Internal Writer opening now persists and claims an **empty structural root** via
  the existing Checkpoint/Transition/Store CAS and receipts. Record2/execution2
  explicitly mark composition; Frame4 accepts only sequence/cursor `empty`, trusted
  definition binding, bounded portable input and an empty single-root Scope2.
  Composition snapshot1 has identity/binding/revision0, no Model or root history.
  Legacy Record1/Frame1–3 retain their formats; Server/Session snapshot readers and
  agent restore reject composition rather than inventing a model. No migration
  or public Composition.run/resume is introduced.
- Root owner/lease/fence, administrative recover/cancel/expire/delete and data-only
  persistence retries use existing machinery. Model/tool effects, step links,
  outputs, approvals, checkpoints and successful completion are rejected in this
  empty format. This is not A→B, executable composition, or complete composition C7.

- Internal structural ExecutionScope roots now share existing leaf admission and
  accounting without a fictitious root Model or effect. Root-owned requests,
  tools/retries and usage contributions reject; JSON ledger restore preserves
  historical leaf prices and rejects root-owned operations in a structural host.
  Scope2 and legacy agent readers/writers remain unchanged. Model-less root pricing
  accepts nil or a model-aware binary estimator, not a model-specific unary one.
  This is a tested runtime primitive, not durable Composition.run/resume: step
  links and persisted input/output sequencing remain unimplemented.

- Experimental `Coordination.Composition.new/1`, `binding/1` and
  `validate_binding/2` now validate trusted sequence definitions without executing
  model/codec/mapping callbacks. Portable composition_definition_version1 binds
  ordered step IDs, versioned definition/policy/model/output references and mapping
  versions with canonical SHA256; it never serializes live agents/functions/deps.
- Bindings reject malformed/future data and changed host identities, including
  rehashed invalid structures. Limits:255 steps,512 UTF-8 bytes per reference
  component,65536 JSON bytes for the entire binding including fingerprint.
  Hosts must bump declared versions when code changes; this is not introspection
  of callbacks or a substitute for runtime admission/model/tool bindings.

- ADR8.38 proposes a host sequence root without a fictitious Model/tool/request,
  sharing the existing continuation Writer/CAS/journal and ancestral Scope. First
  vertical is A→B with a paused delegate inside B; runtime is not implemented yet.
- Proposed future frames explicitly distinguish composition step links from
  legacy delegated agents; Record1/Frame1–3 readers must remain intact. Confirmed
  outputs/mapped inputs must survive restart without replay or double accounting.
  Mapping code stays trusted/versioned host configuration, never persisted code.
- No public run/resume stubs; legacy agent writers retain their existing formats.
  API, migration and acceptance gates are in `docs/development/r6-implementation.md`.
  Router/parallel, SQL A8, live qualification and independent review remain pending;
  Constructor, structural Scope and empty-root persistence are available, not
  durable composition execution.

### Incomplete public terminal error priority

- A real public finish other than stop/tool_calls now determines the primary
  `incomplete_response` error even if tool argument translation also fails. The
  existing complete translation is attempted once under all guards: retain its
  valid partial/qualified usage, or return partial_response:nil on failure.
  Successful finishes still reject malformed/lost arguments normally. No finish
  is inferred from invalid arguments; no new codec, omission marker or fabricated
  accounting-only response. Consumers must handle incomplete errors with nil partial.
- Stock TCP proves this independent error-priority issue. It does not qualify the
  Luna live length-stream red, whose original terminal was not observed and whose
  separate stock diagnostic returned tool_calls. See design8.37.

### Explicit none mode and static persisted Model binding — accepted offline scope

- ReqLLM instances add `reasoning_mode: :none` for the existing qualified Chat
  profile when current truthful capabilities explicitly support effort none and
  disabling reasoning. Nil preserves the existing route. None requires absent
  temperature and maps bounded ModelSettings.max_tokens1..4096 (default4096) to
  public max_completion_tokens while keeping on_unsupported:error and retries0.
  No model-ID special case, arbitrary provider options or reasoning continuation.
- None history writes continuation3 with explicit mode; default history keeps v1/v2.
  Changed mode/target, missing legacy evidence and exposed reasoning fail closed.
- Optional generic `Model.continuation_binding/1` adds a deterministic, nonsecret
  static configuration binding, normalized to JSON and limited to4096 encoded bytes.
  Missing callbacks/nil-mode ReqLLM return nil. Callback errors and overflow use
  normalized reasons without echoing configuration. Template and restored model
  must match, including first-request uncertainty before any response history.
- New captures write Frame3 and Abort2 with explicit model_binding. Legacy root1/
  tree2/abort1 read only with nil current binding; data-only persistence retries
  retain original commands and do not migrate or rerun callbacks. Existing J/JSON/
  tree reservation bounds include the binding. Update readers before enabling none;
  Snapshot4/Scope2/envelope1 remain. This opt-in guarantee does not reclassify old
  application codecs as defective. Design8.36 records rationale and migration.
- Independent review/coordinator accepts none/bindingb609 offline; the subsequent
  terminal-priority delta is separately accepted ondda4. Live Luna remains13/14
  with streaming length unqualified; GLM/DeepSeek have buffered-text-only controls.
  No whole-catalog or release acceptance follows. The recurring checkout-only
  qualification runner uses explicit opt-in, fresh bounded ledgers and private env;
  it preserves the real-length oracle and never enables paid default tests.

### Final argument admission on stock ReqLLM1.24

- Valid assembled arguments are now admitted despite retained initial-fragment
  `invalid_arguments`/`unparseable_arguments` diagnostics. Strict final JSON, the
  required envelope and host JSV/Ecto validation remain authoritative; diagnostics
  are preserved in portable metadata, history and persisted approval/resume.
- Any non-nil public `:error` or `"error"` metadata rejects as
  `invalid_tool_arguments`, including args_lost, missing fragments, unknown errors,
  false and empty strings. Both aliases are checked independently. This explicitly
  rejects even a schema-valid fallback map rather than relying on tuple metadata
  failing portability. Additional nonportable metadata still rejects normally.
- Migration: treat these flags as diagnostics, not a final execution verdict;
  handle the explicit argument error for loss. No codec, dependency or nominal
  version change. The single stock materialization, noop callbacks, repair=false,
  retries=0, identity/permission/terminal and C7/budget/cleanup guards remain.
  Design8.35 records the demonstrated public TCP red→green and alternatives;
  fresh review and live G2 qualification remain required for this delta.
- Prior C7 framework source8b3b plus separately identified SQL4b89 is now accepted
  offline by the coordinator after final independent review. TARba17 still has
  old SQL bytes and is not an accepted corrected distribution. Earlier pending
  review statements below describe their dated implementation checkpoints.

### Postgres delete acknowledgement correction — real SQL profile accepted

- Atomic `transition(delete)` now requires the expected physical key from
  `DELETE ... RETURNING key`. Zero affected rows return `{:error, :conflict}` and
  roll back instead of falsely acknowledging deletion with `record: nil`; original
  SQL errors are preserved. Prior absence remains `:not_found`, and legitimate
  receipt replay is unchanged. Callers must retain failed-persistence handling;
  no schema migration or RLS/trigger-policy change is required.
- Public scripted-Repo regression reproduced the false ACK before the fix;
  focused SQL/Store/cleanup/retention gates pass41/41 offline. Coordinator receipt
  `msg_8249d33f7914` reports exact real RLS and trigger probes red exit2→green exit0
  on Postgres4b89, plus primitives8/C7runtime3 green. Blocked rows remain with an
  error, while positive controls delete; full G3 report and independent acceptance
  remained pending at that receipt. Subsequent coordinator receipt
  `msg_12a78ba009d5` accepts G3's PostgreSQL17.11 READ COMMITTED profile and this fix;
  the identified report records21 cases plus VM/DB restart, network ACK loss and
  backup/restore. Independent C7 review remains blocked, without a final verdict.
- G2 diagnosed stock ReqLLM1.24 option validation rejecting integer temperature0.
  OpenRouter/streaming/structured-output examples, the run-agent snippet and the two
  real-provider test defaults now use `0.0`; no runtime coercion or live-provider
  acceptance is implied. Those paid tests were not executed by this fix owner.

### R5 persisted approval — owner-verified offline, independent acceptance pending

- Owner gates now include a delegated tree across fresh VMs, Server/Session/queue/
  stream/native composition and exact token/JSON/receipt boundaries. The integrated
  suite passes921 tests with28 existing exclusions; fixed-graph package consumers
  pass minimum6/runtime106/extensible30/SQL opt-in12. These results do not certify
  real SQL/provider services, clean resolution or independent C7 acceptance.

- Model reconciliation now accepts host-confirmed effective response/portable state
  and validates the trusted target Model/output binding without replaying Model or
  hooks. Missing cost remains qualified unknown; confirmed accounting is not repriced.
- Explicit effect retry requires a revision-bound host authorization and acceptance
  of duplicate-effect risk. Original uncertainty remains visible; a new linked intent,
  claim and ACK are required. Keys reach context-taking tools and Model parameters;
  stock ReqLLM Chat delivers the HTTP header in buffered/stream tests, without any
  provider-deduplication guarantee. Current budgets/expiry and original constraints
  still apply, and new attempts are counted separately from historical reservations.
- Retry links bind to their authorization receipts. Results/query/terminal events
  expose historical risk; start/prune retain that evidence until a separate explicit
  host acknowledgement permits future deletion. Acknowledgement is not reconciliation.
- Tree review correction: reverse journal/approval-to-node validation rejects an
  otherwise coherent pruned subtree before replay. Owner reproduced the independent
  probe and now passes it; independent acceptance remains blocked, not inferred.

- Initial integrated delegation tree (review pending): frame2/scope2 checkpoints
  retain child cursors, host references, per-ancestor accounting and parent/child
  result bindings in one row. Durable descriptors bypass the parent callable;
  confirmed children/siblings and raw/final hooks are not replayed on resume.
  `node_checkpoint` and `delegation_outcome` preserve the root quiescence guards
  rather than pretending delegation is an external running effect. Tool recovery
  targets the actual node, including colliding call IDs in different branches.
- New writers use frame2 even for root-only runs. The root1 reader remains covered
  by real paused bytes from the accepted writer; old readers must reject trees.
  Explicit child UTC deadlines survive human wait, but expired attempt leases do
  not become permanent child deadlines. Snapshot/message/accounting codecs are
  unchanged. Full C7 recovery, boundary gates and independent acceptance remain open.

- Bound Session participants cannot leave while their current agent row/evidence
  remains: `continuation_binding_retained` preserves the consumed identity and a
  restorable checkpoint. Detachment removes roster and binding together only after
  confirmed absence without pending/local error; leave never deletes Store data.
  Ordinary unbound leave is unchanged; deduplication after evidence deletion is
  outside the retained-evidence guarantee.

- Review follow-up: Session keeps a new local failure blocked even when the agent
  row still points to an older consumed terminal. Explicit `reconcile_turn/3`
  acknowledges a versioned, bounded diagnostic witness without running callbacks,
  advancing the turn or consuming a run again. Pending/uncertain/dirty or changed
  identities remain blocked; applications authenticate this local acknowledgement.
- Server abort follow-up under verification: linked/registered writer cleanup plus
  same-row `create_cancelled`/`fence_admission` barriers prevent a previously sent
  create/start from committing past a confirmed abort. Terminal abort frames are
  explicitly non-executable and preserve trusted portable model state; no effect
  outcome is invented. Missing ACK retains a data-only token and blocks draining.

- Atomic Server reset uses terminal-only `reset_snapshot` CAS, preserving execution
  evidence and lifetime instead of sending a legacy snapshot write to an envelope.
  Dirty reset retries persist only the exact command and block subsequent mutations;
  paused or uncertain executions cannot be erased by resetting the conversation.
- A terminal deny/cancel/expiry with an open tool batch requires explicit reset:
  Server health reports `reset_required`, retaining queued work until reset ACK.
  Restart derives the same guard from persisted history; no tool outcomes are
  fabricated to make that history executable. Queues remain volatile.
- Partial Session continuation integration (under verification): opt-in trusted bindings,
  `continuation/2` and `complete_turn/4`, exact versioned reference, consumed identity
  by lifetime/run and pre/post-callback authority checks. Paused/error results do
  not advance turns or replace shared state; ordinary unbound maps remain generic.
  Session rows require reconciliation with agent rows, not a cross-row transaction.
  Opt-in Session snapshots write v3; unbound writers remain v2 with v1/v2 readers.
  Missing/downcast guard data and changed bindings fail closed. Control metadata is
  finite:64 bindings,4KiB references,8KiB entries and one consumed identity per binding.

- Approved tree direction (implementation pending): internal frame2/scope2 bind
  node ancestry, operation identity and already-priced per-ancestor Usage; old
  root-only readers must reject trees. The accepted root1 reader remains for
  existing validated root checkpoints, without changing message/snapshot codecs.
  Trusted delegation descriptors rebuild configuration instead of replaying the
  parent callable. Server/Session and explicit uncertainty recovery remain required
  integrated gates; this design does not enable durable children by itself.

- Root-review corrections: approval binding uses canonical digest equality (1 and
  1.0 differ); current budgets revalidate historical reservations without a second
  debit. Restored cursors/outcomes must agree with history and confirmed journal
  evidence. Native fingerprints contain portable schema/config, and native recovery
  rebuilds its validator before consuming the already-confirmed response.
- Data-only `resolve_call` records pre-dispatch rejections; `finalize_call` preserves
  the raw effect confirmation while atomically fixing the post-hook result/frame.
  Explicit raw/final phases, immutable raw hash/status/intent, fresh owner/fence and
  exact-receipt replay prevent forged or repeatedly transformed results. Runtime
  reservations include both confirmations and bounded hashes. Unaccepted earlier
  prototype frames lacking coherent evidence fail closed rather than replay.

- The root vertical now has opt-in run/resume/resume_stream, qualified ledger
  restore, bounded data-only dirty retry, and host tool-effect reconciliation.
  Model codecs are explicitly supplied by the application. The optional Model
  `validate_resume/4` callback is required only for C7 and must perform no IO;
  ReqLLM reuses its existing adapter preflight before invoking the backend.
  Root support is under verification; durable delegation/Server/Session and the
  complete C7 acceptance gates are still pending.

- Design8.34 and the approved R5 implementation proposal extend the existing loop
  and result contract, using the single atomic R4 row. The first unit adds pending/
  denied transitions and payload-bound, host-authorized administrative decisions;
  it does not yet implement runtime pause/resume.
- Repeated exact operations use receipts; opposite decisions, changed actor/payload
  and stale revisions conflict. Deny terminates the pending execution without
  rolling back confirmed siblings. UTC expiry keeps running during human wait.
- Planned runtime migration: discriminate result status before consuming output;
  paused is not final output. Trusted templates/model codecs and actor authorization
  are application responsibilities; no serialized modules, credentials or closures.
  Owner fencing cannot make an arbitrary external API exactly-once. Scope/active
  budgets and crash uncertainty must survive restore before C7 can be accepted.
- C7 adds its own finite checkpoint payload budget J (default/max8MiB, measured on
  the complete data-only retry token in uncompressed Erlang external term bytes).
  Tokens are included in public data measurements: durable bound2H+P+J+64KiB;
  ordinary bound2H+P+64KiB remains unchanged. JSON record/cleanup limits apply
  separately. Retry receives Store configuration separately and performs only the
  captured CAS command. Oversized confirmed outcomes require explicit checkpoint
  omission, not loss of effect status or automatic replay. Verification is ongoing.

### R4 atomic data primitives — integrated and owner-verified offline, review pending

- Design8.33 adds optional Store capabilities/load_record/transition/scan_records,
  a closed JSON reducer and persistence-only dirty CAS retry seam. Trusted
  Store.Scope/RuntimeIdentity and existing snapshot codecs are reused, preserving
  Snapshot4/omitted-v1/Usage marker/accounting1/continuation2/envelope1. No runtime
  pause/approve/resume or C7 acceptance is introduced.
- One physical row contains a legacy snapshot or an atomic record. ETS owner
  serialization is ephemeral; Postgres row transactions/unique inserts have offline
  protocol tests, with real G3 still open. Legacy load/save/delete reject envelopes;
  list omits them so an unintegrated Server cannot execute their embedded snapshot.
- Lifetime IDs, actor/payload-bound operation receipts, CAS, owner/attempt/fence,
  leases and effect intent/outcomes preserve uncertainty. Lost ACK retries only
  persistence; old receipts never authorize new effects. Start preserves counters.
- Encoded JSON is bounded to8MiB, effects256, receipts1024. Corrected cleanup
  reservation charges actual execution IDs and worst-case escaped actor/operation
  IDs plus minimal state/outcome and counter growth; claimed records retain recovery
  and close slots even with no pending effect. No eviction, truncation or replay.
- UTC milliseconds validate0..9223372036854775807 inclusive; counters remain exact.
  Near-cap experimental backups may fail stricter admission: validate and remediate
  explicitly with writers stopped, without coercion/fallback. Current guides replace
  the obsolete fixed4224 reservation; historical failure evidence is preserved.
- Bounded scan/prune rejects active/uncertain deletion and reports errors. Hosts own
  quotas, authorization and quiescence; deduplication is limited to retained evidence.
- SQL identifiers are validated/quoted bare names; configure trusted Repo search_path
  rather than schema-qualified/interpolated names. App-owned DDL ships at
  `docs/guides/continuation-schema.sql`; startup executes no DDL.
- Reviewed isolated R4 sourceb3498467 is integrated only by its exclusive delta onto
  accepted R3.4 source05a02459. New integrated evidence and remaining review gates:
  `docs/archive/2026-09-26-r4-integration.md`. No SQLlive/G3 or clean-resolution G5.
- Forced compile80, focal121 and new public seam3/3, full offline803/0/28 seed37556,
  format, snippets9/9 and ExDoc pass. No new runtime correction was needed at this
  seam; all eight R4 runtime files retain reviewed bytes, R3.4 runtime is preserved.

### R3.4 postdecode retention — accepted offline after independent revalidation

- Review fixes under the approved design8.32 contract: bound monitor crash reasons
  before RunStream/Server publication and estimator failures before ledger storage
  or duplicate replies. Keep confirmed internal pending_response across hook
  transforms, and encode omitted ToolReturn nil as JSON null through snapshot4.
  Small errors, valid response transforms, accounting and legacy codecs retain
  their semantics; no replay, repricing or additional migration/version is added.
  Six independent probes now pass (previously five failed);12 permanent regressions,
  forced compile74, focal146 and offline755/0/28 seed37556 pass locally.
  Independent task_d3420f865920 closes all four P2 findings on source05a02459 /
  TAR8775e665: forced compile74, unchanged probes6/6 and focal85/85 pass.
- Design8.32 was written before code and approved for implementation. Agent/run
  defaults now bound complete Response/ToolReturn payloads to1MiB and canonical
  history to8MiB, configurable1..64MiB in uncompressed Erlang external term bytes.
  Server applies its own history bound as well. These are not RAM/token/bill limits.
- Reserve deterministic aggregate result slots before tool admission; oversized
  post-effect returns retain confirmed status/IDs with an explicit version1
  `payload_omitted` marker and terminal `retention_limit_exceeded`. No automatic
  retry, next model request or silent truncation. After-hooks are checked again;
  confirmed siblings survive oversized results and timeout.
- Usage records are bounded to4KiB, including cumulative request updates. Omitted
  details/dimensions are marked; retained source/quality/availability and host
  counters remain honest, unavailable values are never invented observed zeros.
  Errors omit oversized original causes. Results/events expose serialized data
  measurements; measured public-data bound is2H+P+64KiB, not total RAM≤H.
- Server bridges now wait for correlated consumption ACKs, preserving bounded
  progress under slow/suspended consumers. Completion/abort tests use a receipt
  barrier before terminal publication; a suspended owner intentionally blocks its
  worker rather than allowing unconsumed snapshots to accumulate.
- Major migration: Server snapshot4 reads1/2/3; old readers reject4. Omitted
  message nodes use `tool_return_omitted_v1`/`response_omitted_v1`, so older JSON
  readers reject rather than discard the marker. Accounting1/continuation2 and
  native-output guards remain. Omitted history is diagnostic: model dispatch and
  ReqLLM projection reject it before IO; recover data explicitly or start a new
  conversation without replaying effects. Keep the diagnostic snapshot.
- Canonical history already confirmed cannot be discarded by hooks/compaction
  to evade H; use request_messages for projection. If a new input cannot fit,
  previously retained history is preserved. Externalize large payloads as refs
  or configure finite bounds; content:nil with marker differs from a real nil.
- Forced compile74, focal139, offline suite743/0/28 seed37556, formatting/ExDoc
  and snippets9/9 pass. Slow-consumer smoke has24 closures; the three-step case
  retains22805/24576 history bytes with3 requests/2 effects and3 stream closures.
- R3 accepted offline by gate_1a7cfef26f1f; artifact/consumer evidence and rojos in
  `docs/archive/2026-09-26-r3-retention.md`. C7/live gates remain open.

### R3 runtime namespaces — partial unit accepted offline

- Forced compile73, focal122 and offline suite718/0/28 seed37556 pass; formatting
  and nine executable documentation probes pass. Runtime smoke saturates16
  independent namespaces with48 correlated terminals and16 queue rejections.
  Fresh review task_529ac64dfe7e accepted this partial unit with no concrete P1/P2;
  gate_115377365ca5, TAR29e35296/source643ade77. New retention bytes need a new review.
- R3.4 current-run output retention remains explicitly open: a65536-byte tool
  result produces68792-byte canonical history despite a1024-byte next-admission
  limit, with one confirmed effect. The next unit must define an explicit
  postdecode omission/error contract preserving effects; no silent truncation,
  replay, core outcome change or full R3 acceptance is claimed here.

- Server payload admission (design8.31): finite `max_input_bytes` (1MiB),
  `max_pending_bytes` and `max_history_bytes` (8MiB each), configurable1..64MiB.
  These measure uncompressed Erlang external term size, including deps/callback
  representation, not JSON or live RAM. Oversized input/history fails explicitly;
  queued bytes saturate with queue_full and are released on dequeue. Already
  admitted work rechecks history before execution. Current-run output retention
  is a separate open R3.4 requirement; canonical history is not silently truncated.

- Design8.30 defines trusted application `namespace` for Server/Session, event
  correlation/topics and `Store.scoped/2` snapshot dispatch. Logical IDs remain
  local; persisted keys use a shared versioned injective codec, validated before
  restore. No implicit legacy fallback, CAS or durable continuation is introduced.
- Migration: nil retains legacy keys/topics, except IDs beginning with reserved
  `exagent.scope.v1:` must be explicitly renamed. Use two-argument Event topic
  helpers for scoped subscriptions and group by namespace plus logical ID.
  Moving legacy data to a namespace requires explicit validated export/import.

### R2.3 native output — accepted offline after independent revalidation

- Final review task_f955b8e8ea60/ctx_cd5ed6947704 closes P2 with no remaining
  concrete P1/P2 findings on TARf6b549f5/source7eb34210: compile71/focal32
  seed92624 and causal fixture contrast1/3→3/3. Coordinator17/17 and exact93/253
  identity pass; owner suite707/0/28 and fixed-graph consumer80/0/0 remain owner
  evidence. R2 accepted offline; no live G2, clean-resolution G5 or C7 acceptance.

- Fresh-review P2: prepare the effective native schema after before-model hooks
  and before request admission for every Model. Invalid schemas now fail with
  `{:invalid_output_schema, errors}`; malformed native output configuration or a
  nonempty output-tool inventory fails with `:invalid_output_configuration`.
  Neither consumes a new request nor retries model data; prior progress remains.
  Fix hook-selected schemas/inventories rather than relying on output retries.
  Ecto final authority and corrective retries for invalid model data remain.
- Separately authorized test-only fix: the local OTLP receiver acknowledges
  handler registration before allowing HTTP processing, preventing late links to
  already terminated handlers. Suspended-owner, cleanup and failure-propagation
  controls retain the causal red/green evidence; no observability runtime change.
- Design8.29 specifies explicit `output_mode: :native` with an Ecto output module,
  keeping tool mode as the default. Native schema is separate from output tools;
  local schema validation and the actual Ecto changeset remain authoritative.
- Stock ReqLLM1.24 native output is qualified only through an explicit
  `output_profile: :chat_json_schema_v1` alongside the existing Chat-tools profile,
  with exact reference-free schema and strict:false. No optional-to-required
  rewriting, defaults insertion, repair or automatic tool fallback.
- Native public stream object content becomes canonical JSON text history; this
  preserves semantic data, not original JSON bytes. Corrective retries use the
  existing host budget/accounting. Stock Chat1.24 can discard refusal beside valid
  JSON; such content can still produce locally valid output. Publicly exposed
  refusals reject; no total wire-refusal detection is promised. Integration tests
  cover function tools with one effect and counted retries; final review is accepted above.
- Twelve new tests cover stock projection and real TCP integration; compile71,
  suite699/0/28 seed37556, formatting, snippets8/8 and fixed-graph TAR consumer75/0/0
  pass. No new clean dependency resolution, live qualification, C7 or publication.

### R2 base — accepted offline after independent review

- Design8.28 classifies the small public extension surface and designs a common
  paused result for sync/stream/Server, with separate logical run/attempt/request/
  approval identities, confirmed persistence and no replay of completed effects.
  This is an ADR for R4/R5, not an executable paused feature or C7 acceptance.
  Existing versioned codecs and Store/PubSub/policy contracts are reused.
- Design8.27 records reproduced custom/Test identity substitution, execution of
  request-omitted tools, and undeclared capability promises before changing them.
  In v2, before-tool hooks may change validated arguments, not call ID/name/kind/
  metadata; select tools before the model request or use an explicit dispatcher
  tool instead of renaming an admitted call.
- ModelProfile defaults extra tools/JSON support to false (not negotiated).
  A custom Model that implements tools must explicitly declare supports_tools:true;
  basic text remains usable without profile/1, and native JSON is not implied by
  Ecto-tool support. Request-selected tools, rather than the wider definition
  inventory, are the executable set. No version bump or native-output acceptance.
- Before-tool hooks now receive the same call identity/retry fields as the
  callable. Their exceptions return a not_executed outcome and tool_hook_failed;
  uncertain callable IO still reports unknown, and after-hook failures preserve
  confirmed effects. No automatic retry of uncertain IO is introduced.
- Executable request-selected tools require a callable of arity2 with takes_ctx:true
  or arity1 with false before model IO; fix mismatched declarations rather than
  discovering BadArityError after an admitted request. Schema-only Tool.prepare
  and internal output tools remain usable without a callable.
- Seven new public regressions preserve red/green evidence; root compile71 and
  suite687/0/28 seed37556, snippets8/8 and a fresh fixed-graph TAR consumer63/0/0
  pass. The consumer implements its own Model/tool using public APIs and checks
  unsupported preIO admission plus effect preservation on a later model error.
  Fresh review task_28d681ef6334 accepts TAR482e26a3/source1eefe618 without concrete
  P1/P2 findings: compile71, focal54 and probes6 pass; coordinator focal38 passes.
  This review does not cover later bytes. R2.3 remains separate; no full
  R2/C7/live-provider acceptance or publication.

### R1.8 single backend — minimum profile accepted offline

- Design8.26 selects stock model resolution plus explicit per-instance options,
  preserving custom Model/Test and qualified guards; no automatic Chat/tool inference.
- Major migration retires four provider wrappers and five duplicated wire/stream
  modules after concrete callers and preserved guarantees move to ReqLLM. Strings
  resolve stock identity only: explicit auth and profile options are required.
  OpenCode Go/Zen needs explicit endpoints; stock `zai:` retains ZAI identity rather
  than the former Anthropic alias. Legacy Anthropic gateway users must specify it.
- Anthropic auth_token uses public stock Bearer options; real loopback gates prove
  precedence, no extra API key/subscription headers and sanitized errors/history.
  No new qualified tool/stream families, wire fallback, version bump or live acceptance.
- Remove88 legacy helper/wrapper tests, add13 public resolution/auth/framing/loss and
  custom reported-usage tests; preserve R1.4/5/7 and migrate Ecto/OTel/sentinels.
  Offline suite680/0/28 seed37556 passes; removal rationale in the retirement record,
  not numerical parity or certification of upstream internals. Fresh review accepted
  TAR6a2eb6aa with no remaining concrete P1/P2 findings in this offline scope.
  September26 documentation closure corrects remaining auth/profile examples and
  local skills; functional library AST and tests/config/dependencies are unchanged.
- R1.8 fresh review exposed an overclaim about malformed wire siblings: stock1.24
  can discard id-only/null/name-only entries without a public signal. Explicitly
  document semantic exposed-call validation, not wire-batch fidelity; preserve a
  TCP characterization with positive, visible-invalid batch and denied-call controls.
  A lost sibling does not authorize effects, but cannot force rejection of the
  surviving valid authorized call. Host counts are not counts of discarded wire entries.

### R1.3 / R1.6 / R1.7 minimum qualified composition — accepted offline

- Add destination-binding and effective internal tool-choice oracles, plus real
  stock ReqLLM TCP composition covering delegation, Ecto corrective retry, Server
  streaming, Session/ETS checkpoint failure/retry/restore and normalized OTel.
  Ancestor denial produces zero effects; restored history/checkpoint retry does
  not replay model/tools or pricing. Root suite755/0/28; final fresh review4/4 and
  TARd2bfe978 identity accepted, documentary follow-up closed.
- Reuse accepted profile/codec/settings/stream/accounting behavior without runtime
  or API changes. R1.8 inventory is preparatory; legacy/default backend remain for
  that separate unit. No C7 durable, native output or live-provider acceptance.

### R1.5 qualified accounting — accepted offline after final fresh review

- Decision8.25: Usage.accounting v1 separates source/quality/availability and
  estimated cents from additive details; stock public metrics are normalized,
  including zero, with unknown provider presence. Owner suite751/0/28 is offline
   evidence; final fresh review173/173 accepted the frozen TAR3c7867ad. External
   acceptance remains separate.
- Strict metric limits require sufficient host-reported data; stock normalized
  metrics cannot satisfy them. Explicit estimated mode requires an effective
  finite request_limit and checks available subtotals retrospectively.
- Major migration: Server snapshot3 with bounded legacy unknown readers,
  qualified results/events/OTel, and no re-pricing restored history; continuation2
  and envelope1 stay unchanged. R1.4 fresh review accepts only partial offline
  chat_tools_v1, not R1.5 or R1 complete.
- Fresh-review fixes preserve per-dimension availability for input-only strict
  limits, upstream cost-only reports and prior cost subtotals after terminal nil.
  Aggregates canonicalize existing cache/reasoning atom/string aliases once and
  sum only known token details; arbitrary numeric metadata (version/price) stays
  per-operation/history and is omitted from multi-contribution totals. This replaces
  the previous indiscriminate numeric merge; custom additive details need explicit
  consumer aggregation. Unknown/non-USD component pricing is unavailable.

### R1.4 qualified streaming — partial offline accepted after fresh review

- Enable lazy ReqLLM `Model.request_stream`, `stream_text: true` and `run_stream`
  only for explicit `chat_tools_v1`, using one public process_stream view and the
  buffered Envelope/history/response boundary. Tools execute only after complete
  validated response; provisional deltas, truncation, cancellation and invalid
  arguments never authorize effects. Usage remains unknown pending R1.5.
- Add host producer/guardian ownership, registration handshake, explicit public
  close and completion timestamps. Preserve native trace context, exact host
  request admission and zero upstream retries; test owner death before/during
  registration, halt/exception, deadline and queued completion through real TCP.
  Shutdown allows100ms grace then kill/reap, including a producer that traps exits.
- Define postdecode serialized chunk budgets: 64KiB/chunk, 1MiB summed and4096
  chunks. One unacknowledged delta; upstream materialization/queues still retain
  O(response) data. No hard RAM/predecode guarantee, and input/canonical history
  are separate. Default max_tokens4096, explicit1..4096; stream total_timeout nil
  means60000ms, explicit1..300000ms, unlike buffered's inherited default.
  Unsupported values and buffered-only HTTP adapter injection reject before IO.
- Bound the shared public RunStream progress bridge with correlated ACKs after a
  real203-snapshot backlog reproduction, and link its worker to its guardian so
  guardian death cannot strand the worker. Progress timing now applies backpressure;
  event data/order and terminal semantics remain compatible. Test/custom and ReqLLM
  lifecycle regressions cover the common change; see design8.24 and migration.
  Propagate reserved cancellation through progress and stop sending snapshots once
  cancelled, preserving custom stream finalizers instead of waiting for a closing
  guardian's ACK. Fresh review findings were reproduced and regression-tested.
- Record fresh R1.2 review `task_16e800274a86`: acceptable buffered partial offline,
  P2 deadline fixed/revalidated, no remaining concrete P1/P2 in that review. Its
  TAR51f36adc and715/0/28 evidence do not certify this new stream candidate.

### R1.2 mandatory envelope — buffered partial accepted offline

- Add explicit ReqLLM `tool_profile: :chat_tools_v1` qualification: OpenAI Chat
  wire metadata required, tools enabled, reasoning disabled, strict tools and
  extra provider options rejected. Preserve the general guard outside this profile.
- Validate required single-field `arguments` envelope and logical schema using
  existing Tool/JSV before execution; revalidate effective hook arguments and bind
  call ID/name/codec metadata. Upstream callbacks remain inert, repair and retries
  disabled, strict false preserves optional fields and inert defaults.
- Limit schema projection to a documented reference-free subset, rejecting roots,
  refs/$defs/identifiers/dialects or keywords not represented before IO. Ecto-tool
  output uses the same envelope; native output remains a separate unsupported mode.
- Version continuation2 / `exagent.arguments/1` logical calls; JSON and snapshots
  preserve markers and wire wraps once. Reject pre-envelope/invalid call history
  rather than guessing migration; custom/Test/legacy message formats stay intact.
  No ExAgent streaming, usage metric integration, C7 or live-provider acceptance.
- Own all buffered ReqLLM calls with a host guardian/linked worker and startup
  handshake. A real partial-HTTP owner-kill gate exposed stock total-timeout
  nolink work surviving its caller; apply the same instance/inherited application
  deadline in the host while disabling upstream's internal total timer. Preserve
  receive timeout, trace context and sanitized errors; no arbitrary external
  callback-descendant cleanup or effect rollback is promised.
- Fresh review exposed a queued-result deadline race: reject worker completion
  at/after the absolute deadline even if the guardian handles its timer late.
  Preserve on-time completion delivered later, with explicit monotonic timestamps
  and no real-time scheduling promise; regression checks zero/one tool effects.

### 2026-09-22 design replan — official stock ReqLLM, pending implementation

- Adopt design8.22: own runtime/minimal Model over an official ReqLLM release,
  without fork, vendoring, patch, monkeypatch, private wire parser or Jido runtime.
  Jido AI2.3.0 locks ReqLLM1.17.1; inspected main locks1.22.0 and does not solve
  invalid-arguments normalization, usage presence, hard RAM or atomic continuation.
  Durable source/version evidence is in framework-direction§9; prior comparison
  and test counts remain dated evidence, not fresh acceptance.
- First R1.2 gate: mandatory generic `{arguments: object}` envelope, still an
  unproved hypothesis. Validate envelope and logical schema locally, then effective
  arguments after hooks before authority/effects; keep upstream callbacks inert.
  Promise validated semantic objects, not unavailable raw bytes. Never repair
  explicit invalidity/truncation into valid tool calls. Test schema root/refs/$defs,
  strict/defaults/history/codec/Ecto and zero-effect negatives before lifting guards.
- Major migration must version wire/history/codec and handle old data explicitly:
  never make invalid historical calls valid by wrapping them or fall back to old
  wire. Reject unrepresentable schemas before IO; no preventive general rewriter.
- Separate exact host requests/attempts/tools and atomic admission from normalized
  or reported provider metrics and estimated costs, carrying quality/provenance and
  availability. Normalized zero is not observed zero; no zero-to-unknown heuristic,
  invoices or double counting. Ordinary execution with host limits need not stop
  solely for missing accounting; strict limits depending on missing data explicitly
  reject rather than silently become best-effort. Migrate Usage/limits/snapshots/OTel
  with units and cache semantics preserved.
- Streaming target is one lazy host view with valid terminal before effects,
  deadlines/concurrency and bounded measured host postdecode retention/chunks/bytes,
  plus cleanup on halt/error/owner death. No upstream hard-RAM-predecode guarantee;
  process_stream callbacks/final Response is the preferred candidate, not an
  obligation if public events passes better gates. No duplicate transport/SSE.
- Qualify a minimal non-reasoning/non-provider-native Chat-compatible profile with
  tools/Ecto/stream on exact model/endpoint/config; other families are capabilities
  per tested combination, not required by catalogue membership. Lost metadata
  paths stay closed, without silent fallback; Anthropic3536ff94 is only a future
  official-release lead. Preserve G2 live and all external release gates.
- C7/R4/R5, exact-call approval, atomic claim, current authority, uncertain effects
  and no replay remain required. R1.8 removes duplicate transport/helpers in the
  major, not a permanent legacy backend. This entry changes design/docs only:
  guards, unknown/fail-closed runtime, version and dependencies remain as before;
  affected acceptance criteria are reopened, never green from replanning.

### R1.6 textual option precedence

- Add an optional positive `total_timeout` on ReqLLM model instances, using the
  demonstrated public upstream total-call budget. Nil preserves upstream defaults;
  receive and run deadlines remain distinct, errors expose `{:timeout, :total}`
  without credentials, and no arbitrary callback-effect rollback is promised.
- Require Req `~>0.7.4`: real loopback exposed that ReqLLM's Finch keyword options
  are incompatible with the earlier root lock's Req0.6.1. Update the verified
  transport dependency rather than adding a shim; retain other locks where possible.
- Honor the ReqLLM adapter's instance receive timeout when ModelSettings.timeout
  is nil; explicit request settings win, then the instance default, then60000ms.
  Keep receive inactivity distinct from total-call deadlines, without a new knob.
- Stop duplicating/reinserting definition instructions in the adapter. Canonical
  or hook-projected messages are authoritative; direct Model clients place System
  instructions in messages, as existing providers do. No fidelity guard is lifted.

### Review safeguards and R1.4 streaming gate

- Temporarily disable all tools/Ecto tool output on the ReqLLM adapter before IO:
  stock buffered decoding erases the distinction between non-object JSON arguments
  and valid empty objects. Reject unsolicited calls and call-bearing history too;
  custom Model/Test/legacy contracts remain available and unchanged.
- Reject affected Anthropic thinking/response-continuation before IO because stock
  discards redacted thinking blocks. Derive thinking capability from the resolved
  model and accepted provider path instead of returning true unconditionally.
- Characterize stock streaming via finite real loopback: cleanup and one-view
  terminals are observable, but public predecode byte budgets are absent. Keep
  streaming explicitly unsupported; these guards do not repair upstream or close R1.
- Stabilize the ownership-test readiness barrier only after a diagnostic retained
  the 100ms failure and measured the worker message at155ms with no queued work;
  cancellation/guardian DOWN assertions keep their original thresholds.

### R1.2 / R1.3 — buffered Model adapter and portable continuation

- Add `ExAgent.Models.ReqLLM`: catalogue/explicit specs, instance auth/gateways,
  text/tools/Ecto tool output through the ExAgent loop. One buffered operation,
  public `max_retries: 0`, reserved options rejected, incomplete responses never
  execute tools; streaming remains explicitly unsupported pending R1.4.
- Add portable per-part metadata and versioned Response continuation data, preserving
  reasoning signatures/IDs across JSON and snapshots. Bind continuation to resolved
  provider/model/endpoint; no persisted ReqLLM structs or credentials. Existing
  messages without these fields still load. See design8.17 and migration.
- Temporary stock limitations: usage remains unknown pending R1.5, and Google/Vertex
  tools (including tool output) reject before IO because buffered tool signatures
  are lost upstream. R1.3 remains partial; this is not a reduction of v2 scope.

### R1.1 follow-up — HTTP framing and offline startup

- Require Mint1.10.1+ within1.x and update only Mint in the root lock, closing
  CVE-2026-82672's malformed HTTP/1 chunk-size suffix boundary. Add actual
  loopback transport negative and positive controls; consumer graph checks the floor.
- Disable ReqLLM dotenv loading before startup in remaining direct-Elixir offline
  probe VMs; test config alone does not protect those entry points.

### R1.1 — ReqLLM dependency boundary

- Add `req_llm ~> 1.24.0` (resolved 1.24.0) and qualify its public one-interaction
  host boundary using synthetic transport; loop, tools, authority and persistence
  remain ExAgent responsibilities. The Model adapter is still pending R1.2–R1.8.
- Raise the Elixir requirement to `~> 1.18`: mandatory `llm_db >= 2026.9.3`
  requires it, independently of warnings or toolchain availability. Align current
  CI targets to 1.18/OTP28 and 1.20/OTP29; preserve historical 1.17 evidence.
  Hosts on 1.17 must upgrade before adopting this unreleased major.
- Document ReqLLM supervisor/Finch startup and default `.env` loading; tests and
  synthetic consumers explicitly disable dotenv loading. Hosts manage this setting
  before startup; no global host configuration is changed by ExAgent.
- Preserve existing decoder floors and optional SQL/SDK graphs. See design8.15
  and migration for rationale, alternatives, observable impact and gate scope.

### v2.0.0 roadmap — persisted approval included

- Prepare the executable R0–R9 plan, replacing H1–H6/H3.0 while archiving their
  dated scope and evidence. Start with full ReqLLM integration, then consolidate
  core/runtime, persistence, continuation, composition and optional integrations.
- By explicit user confirmation, include bounded persisted human approval (C7)
  in v2.0.0, superseding its earlier deferral. Atomic continuation claims, exact-call
  authorization and uncertain-effect recovery must be designed and verified before
  the feature is considered implemented; snapshots alone do not provide them.
- Define ten acceptance scenarios, six release gates and a prepared iterative-agent
  execution prompt. Qualify production support by tested profiles/combinations,
  with external acceptance distinct from offline tests and publication separately
  authorized. This is a documentation/planning change; nominal1.3.0, dependencies
  and runtime remain unchanged.

### Architecture direction — ReqLLM adoption planned

- Record the user's request to adopt ReqLLM and prioritize ExAgent as a reusable
  personal foundation for future Elixir applications, independent of current
  proof-of-concept consumers. Compare Jido, LangChain, Nous and Ash AI and recommend
  retaining a focused ExAgent runtime over ReqLLM's one-interaction boundary.
- Plan H3.0 for the common adapter, contract acceptance and removal of duplicated
  provider transport. Usage availability, streaming bounds, continuation metadata,
  retries and trace ownership require explicit integration decisions. This unit
  changes documentation only; ReqLLM is not yet a runtime dependency and no new
  provider or migration is accepted. See design 8.13 and the direction document.

### Release planning — six milestones

- Organize production readiness as H1–H6 with explicit dependencies, completion
  evidence and one tracking roadmap. Record the current integrated base7f25b33
  without treating historical test counts as a fresh candidate verification.
- Set the next major's scope around the general Hex library and representative
  consumers. By user decision, defer persisted human approval (C7) and adapt
  Dragonex/WhoamAI after the package contracts are settled; app migration no longer
  blocks this release plan. No runtime or version change is part of this unit.

### Testing audit — oracles, boundaries and CI

- Close the audit by user agreement and return to ExAgent development. Document
  testing ownership, proportionate verification and lower-priority tracking of
  dependency warnings; upstream internals are not a new ExAgent testing project.
  Keep the recorded strict failures intact and leave a dormant second-review note
  for the functionally complete package. This clarification changes documentation
  and prioritization, not CI flags or runtime behavior.
- Complete a source-level inventory of root tests, excluded integrations, support,
  package fixtures, examples and CI before test consolidation. Preserve meaningful
  distinctions between execution modes, runtime owners, codecs and optional SDK
  compilation. Track findings and verification in
  [the testing audit](development/testing-audit.md).
- Preserve non-null Text/Thinking part IDs in the public message JSON codec, with
  legacy missing-ID reads unchanged and no new null keys. Previous roundtrip
  fixtures used nil IDs and missed this data loss. Snapshot version and the
  intentional omission of ToolReturn contributed usage remain unchanged; old
  serialized data cannot recover IDs that were not written. See design 8.10.
- Preserve missing provider usage dimensions as unknown instead of zero, including
  downstream completeness, cost and budget admission. Explicit zero usage remains
  valid. Correct OutputSchema's typed inclusion/exclusion and array/exact-length
  keywords, retain explicit false MCP schemas and forward valid atom-keyed prompts
  to delegated agents. These reproduced boundary defects and their migration are
  described in design 8.11; verification of the implementation is tracked in the
  testing audit rather than inferred from the earlier green baseline.
- Independent review caught boolean-named Ecto.Enum members and ordering/chaining
  of length constraints in the first reflection correction. The final mapping uses
  the Ecto field type and intersects bounds, including contradictory constraints;
  five regressions preserve the review's negative controls.
- Strengthen terminal acceptance, effective context/content, effect journals,
  runtime events/FIFO/stale guards, telemetry attribution and owner cleanup. Remove
  one fictitious OpenAI payload test only after independent mutation checks proved
  its existing Req substitutes; consolidate lifecycle support for twelve MCP mocks.
- Require manifests and meaningful data in C0/evals/load and six actual ExUnit
  contracts per TAR consumer. CI explicitly runs offline with warnings-as-errors
  and per-phase evidence; its finite driver is locally verified, not remotely run.
- Final local suites: **655 passed,28 excluded**, seed37556, on Elixir1.20/OTP29
  and1.17/OTP27. Four native TAR consumers pass **24/24 runtime contracts**, but
  all four retain a strict failure for Req0.6.1's Mix1.20 `xref.exclude` deprecation;
  exporter also retains nine gproc warnings. No dependency/floor/version changes,
  publication or external-provider/DB acceptance are implied.

### Documentation — organization and current state

- Group documentation under `docs/`, with a maintained index, current architecture,
  status, roadmap, verification guide and backend acceptance plan. Preserve dated
  research, execution logs and the completed night handoff in the archive.
- Update ExDoc navigation, package documentation paths and executable documentation
  checks. Root README and AGENTS remain the repository entry points. No runtime API,
  dependency version or release version changes are part of this reorganization.

Verification counts below belong to their dated consolidation milestones. For the
current accepted baseline and open gates, see [project status](status.md).

### Added — native OTLP local acceptance

- Test-only native exporter1.10.0, loopback receiver and official protobuf decoding
  verify actual transport paths, resource/scope, hierarchy, content-off and seven
  failure/partial-success cases. Agent model calls/effects continue while the real
  exporter request is held; neither a failed batch nor another flush replays them.
- Persisted isolated-VM lifecycle probes distinguish ExAgent's owned-process/ETS
  cleanup from retained native HTTP profiles, atoms and outstanding TCP requests.
  They preserve unrelated/default profiles and require receiver-observed closure.
- Documented upstream limits: booleans become strings, successful partial-rejection
  bodies are ignored, and native HTTP timeout/shutdown does not provide complete
  network cleanup. No production wrapper/vendor patch conceals these defects.
  `exported` remains a callback counter, not remote acceptance. See DESIGN8.8 and
  OBSERVABILITY7 before selecting the direct native HTTP recipe.
- Initial native integration: **583 passed,28 excluded**, seed280424; four new
  focal tests passed with seed576860. Platform selection, general native HTTP
  lifecycle and external acceptance remain open. No release/version change.

### Fixed — optional SDK compilation on Elixir 1.17

- Select the bounded processor's startup branch at compile time, with private
  validation/default helpers only where reachable. This removes constant-match
  warnings on Elixir1.17 and1.20 without changing SDK-present startup/results or
  permitting late SDK loading to bypass missing records. A first helper-only fix
  was insufficient under1.20's type inference and was corrected during N18.
- Add a reproducible TAR consumer runner with none/API/SDK/native-exporter graphs,
  package-byte provenance and explicit dependency-compilation warning checks.
  The old TAR reproduces the warning; an initial corrected TAR passes36 focal contracts
  on Elixir1.17.3/OTP27.3.4.17. Runtime/dependency scope is recorded in ACTION_PLAN10;
  this does not certify every Elixir/OTP combination or real consumer application.
- Harden the local acceptance runner after independent review: reject inherited
  project selectors before every child CLI, require a new real temporary work-dir,
  and record warnings across all compilation phases. Negative controls cover
  foreign MIX_EXS, symlinks and later-phase warnings without installing anything.
  These are test-tooling boundaries, not a sandbox for arbitrary package code.
  Phase diagnostics use separate `phase-*.term` files so they cannot overwrite
  the dependency graph artifact written by the consumer fixture.

### Added — composed transport and runtime acceptance

- Three new native-OTLP scenarios inspect68 spans across11 loopback POSTs: parallel
  tools/delegation, corrective retry, streaming, compaction, checkpoint/retry-save,
  two-caller queues, partial cancellation and post-model-hook failure. Tracing
  on/off preserves the same ledger and estimator invocation count. Content opt-in,
  failed/oversized redactors and context/Logger cleanup are checked on real protobuf.
- Independent bounded Server/Session sequence models add six fixed seeds, exact
  effect/request/terminal/revision checks, volatile-queue loss at an owner crash,
  v1/v2 process restore and adversarial codec/load byte preservation. They complement
  the existing cold-module and deterministic race tests. No runtime defect was
  demonstrated by these new sequences; their fixture fixes do not alter the core.
- Initial compiled integration after these units: **595 passed,28 excluded**,
  seed37556. Fresh reviews and final multi-runtime gates remain tracked separately.
- Twenty further bounded tests combine nested scope/authority/admission with
  schema-reference/cache mutation, effective hooks and mixed batch outcomes;
  OpenAI/Anthropic parity under UTF8 fragmentation, terminal-less EOF with zero
  tool effects, repeated stream suspension and late MCP replies. Coordinator
  compiled focal20/20 passes, seed897031. No production change was required by
  these scenarios; fresh review and integrated matrix are tracked in ACTION_PLAN10.

### Added — deterministic evaluations and bounded load evidence

- `examples/framework_evals.exs` and shared scenarios exercise typed reading plus
  scoped delegation, and an effect followed by failure/checkpoint-only recovery.
  Machine-readable criteria retain actual request/effect/usage observations and
  known/unknown cost, with live negative controls rather than an LLM judge.
- A finite load probe compares three reused definitions at concurrency1/8/32,
  OTel off/on, with raw latency samples, p50/p95/p99, sampled own-VM resources,
  short delayed-callback runs and a causal saturation barrier. The initial matrix
  completes4000 measured runs and exports12200 local spans without normal drops;
  intentional capacity32 saturation records610 drops while64 runs finish.
  These are synthetic measurements, not SLOs or remote-delivery guarantees.
- No further production optimization was justified by these measurements. Existing
  definition caching and all validation/ownership limits remain in place. Detailed
  conditions, limits, review and final gates are recorded in ACTION_PLAN10.

### Documentation — executable snippets

- A source-checkout probe selects16 actual documentation blocks:11 execute with
  explicitly declared offline fixtures and five remain syntax/recipes for setup
  or external systems. Seven checks pass with native context/redactor controls.
- Fix README's unused tool parameters while preserving the `days` JSON property,
  and avoid premature `%WeatherReport{}` expansion in a single copied code block.
  No library API/schema contract changes. Requirements now distinguish declared
  floors from the specific package/runtime combinations verified.

### Added — optional native OpenTelemetry (C6)

- `ExAgent.Observability.OpenTelemetry.new/1` and `observability:` opt into native
  spans for runs, model requests, tools, delegation, compaction and checkpoints.
  The application owns its SDK, tracer provider, resource, sampler and exporter;
  ExAgent does not install a tracing service or replace the global provider.
- Explicit ephemeral context propagation covers owned tasks, Server queues,
  delegated runs and runtime operations. Server shares one run span with its
  worker through checkpoint completion. Lazy streams capture at enumeration;
  operation monitors close recording spans after owner death. Context handles
  are not persisted and arbitrary baggage is not exported.
- Content is disabled by default. Opt-in requires an explicit fail-closed
  redactor, bounded plain-data input and valid bounded UTF-8 output before SDK
  attributes. Opaque values, structs/Ecto outputs, hidden reasoning, arbitrary
  metadata and live model/dependency/configuration objects are excluded.
- The `exagent.gen_ai.v1` subset pins GenAI revision `b5d8440`, with generation
  usage separate from inclusive native run totals. Known Anthropic cache input
  is normalized only in the generation projection; custom unknown input semantics
  remain provider-reported. Costs reuse reconciled fractional-cent estimates,
  without another estimator invocation or treating traces as a billing ledger.
- `ExAgent.Observability.BoundedProcessor` is an optional native SDK extension
  for the demonstrated soft-queue/counter gaps in SDK 1.7. Its finite slots include
  pending/in-flight spans, batching and exporter deadlines run outside agent I/O,
  and scalar counters distinguish saturation and export/init/shutdown failures.
  Flush requests coalesce without promising delivery acknowledgement; shutdown
  discards remaining spans, with bounded cleanup and no automatic batch replay.
- API and SDK dependencies are optional; the SDK compile edge is runtime-disabled
  so downstream opt-in builds have native record definitions available. The
  ordinary consumer remains OTel/SQL-free. Processor bootstrap options must be
  non-secret: SDK/OTP supervisor reports can contain original child arguments.
  Configure credentials through the exporter's environment/application config.
- [The observability guide](guides/observability.md) provides host configuration, privacy/profile semantics and
  operational limits. `examples/observability.exs` uses a local exporter and
  optional synthetic overhead measurements. Langfuse/Opik comparison, native OTLP
  endpoint acceptance and backend selection remain separate, unfinished gates.

The first focal gate passes **27/27 tests** (seed `442576`), and the example exports
509/509 spans with zero drops/failures. A 200-sample offline benchmark after 50
warmups observes p50/p95 of 55/76 microseconds disabled and 121/153 enabled, with
construction excluded; this is not real-provider latency. Independent review
found additional compile-order, ownership, flush, synthetic-cancellation,
context-entry and numeric-content-budget cases. These were reproduced and
resolved before final acceptance:

- **579 passed, 28 excluded** on Elixir 1.20/OTP29 and 1.18/OTP28 (seeds `482769`
  and `648445`), with forced compilation of 72 files and warnings as errors.
- All 14 C0 invariants pass in both runtimes; the independent deterministic flush
  probe passes. Three clean downstream graphs compile/run without warnings:
  no OTel, API-only/no SDK, and app-owned SDK with the correct compile order.
- The final example again exports **509/509** spans without losses. Final
  p50/p95 is **56/70µs disabled**, **123/178µs enabled**, under the same synthetic
  setup. This is not a real-backend SLO. Details and limits are in ACTION_PLAN9.

Server-synthesized abort/worker-loss partials now conservatively mark usage partial
and cost unknown while retaining numeric subtotals; Event agrees with the returned
partial, and the trace uses `exagent.cost.known_subtotal_cents` instead of claiming
a complete cost. Confirmed normal core results retain their information. Existing
schema API assertions remain exhaustive; their agent-field fixture now includes
the additive `observability: nil` field. A pre-C6 100ms readiness timeout in an
ownership test was replaced by a 1000ms readiness barrier, preserving cancellation
checks. C6's neutral offline unit is complete; native OTLP/backend acceptance and
platform selection still remain open. No version bump or release occurred.

### Fixed — safe automatic checkpoint diagnostics

- Added a stricter internal `ErrorProjection.diagnostic/1` for automatic OTel and
  checkpoint logging. A checkpoint's arbitrary binary cause is no longer
  interpolated into that automatic log metadata. Rich returned errors and the
  existing Event/`reason/1`/`message/1` projections preserve their contracts.

### Documentation

- Added `ACTION_PLAN.md`: ordered consolidation units, dependencies, acceptance
  criteria, verification and migration work. Recorded the author's preference for
  broader license-free functionality when quality is comparable, while allowing
  commercial advanced features for demonstrated observability benefits. Backend
  selection still requires acceptance testing. C0 evidence and the first scoped
  permission-admission correction are now recorded in the plan.
- Added `RESEARCH.md`: implementation audit, current framework/harness and
  Elixir ecosystem research, open-source observability comparison, and a staged
  consolidation proposal. Recommendations are pending agreement and backend
  acceptance tests, not new public contracts or implemented integrations.
- Linked the research from DESIGN and ROADMAP, separating historical claims,
  observed gaps, offline verification and future work. No runtime, dependency,
  version or consumer-application changes are part of this research unit.

### Fixed — permission admission (C2.1)

- `Permissions.new!/1` now rejects unknown options, malformed rules and actions
  outside `:allow | :ask | :deny` with `ArgumentError`. Previously a misspelled
  option could silently use the allow default and an invalid action could execute
  a tool. `decide/2` denies unknown selected actions in manually built structs;
  `resolve/3` denies invalid actions and non-callable approval callbacks. The
  core loop requires an explicit resolved `:allow` before invoking a tool.
- Valid defaults, glob precedence, approvals and result/event/snapshot shapes
  are preserved. Configuration migration: use `:rules`/`:default`, ordered
  `{binary_glob, action_atom}` pairs, and a one-argument approval function;
  `:approve` is only a callback return value, never a rule/default action.
  Invalid inputs previously accepted or raising incidental exceptions now reject
  consistently or deny. Rationale and alternatives are in DESIGN section 8.1.
- Added an offline consolidation probe with seven reproducible P0 scenarios and
  optional synthetic baseline measurements. It reports outstanding gaps, not a
  passing acceptance suite. Permission effects change from one to zero; streaming,
  argument validation, delegation and recovery gaps remain tracked in ACTION_PLAN.
- Verification: nine new permission tests, including effect counters in the core
  and Server. Full offline suite: **319 passed, 28 excluded** (seed `567723`);
  forced project compilation with warnings as errors passes. Two pre-existing
  unused-alias warnings remain in tests. Real backends were not exercised.

### Changed — consolidation major contracts

The following contracts are implemented in the worktree and passed the first
joint offline gate (**516 tests passed, 28 excluded**, seed `398741`, warnings
as errors). Final review/performance evidence is tracked in ACTION_PLAN and
ROADMAP. These changes require the coordinated major described in DESIGN 8.2-8.4;
no version is bumped or published. See [migration](guides/migration.md) for caller/adapter changes.

- Operational failures return `{:error, %ExAgent.RunError{reason, partial}}`,
  preserving the original cause and known history/usage/model/effects. Result
  maps retain existing fields and add run/tree/request identities, status, usage
  completeness, request/tool counts and known/unknown estimated cost. Do not
  replay effects merely because the terminal result is an error.
- `run_stream/3` now executes the same agentic loop as `run/3` and
  `stream_text: true`, including tools, Ecto output validation, hooks and limits.
  Construction is lazy; deltas are provisional. Success has one full result;
  failure has one RunError, not another pseudo-result. Custom Model streams
  must return `{:response, response, final_model}`; missing/legacy terminals
  reject explicitly. Stateful Test models advance correctly in all paths.
- Tool arguments are validated locally using JSV 0.22 with an explicit
  untrusted-schema boundary. No HTTP/file/module resolution or executable casts
  from tool schemas. Nested dialect changes reject; supported dialects are
  draft7 and 2020-12. Results must encode/decode as unambiguous JSON, including
  Fragment/encoder output. Original arguments and valid result objects survive;
  opaque validator caches are not provider/persistence data.
- A small public-vocabulary adapter corrects JSV's numeric `uniqueItems` and
  Unicode codepoint length semantics; retire it when upstream passes the same
  regressions. Conservative multi-resource preflight and referenced-default
  restrictions are documented in Tool/DESIGN. Derived unions now contain real
  schemas or literal enums; `map()` reflects an object.
- Tool batches preserve every completed outcome and usage before deciding a
  failure, including effects preceding after-hook failure. ToolReturn status
  distinguishes succeeded/validation_error/denied/failed/unknown/not_executed.
  Invalid arguments and explicit ModelRetry may request correction; arbitrary
  execution errors/timeouts no longer authorize automatic retries. IDs and
  call/return pairing survive terminal failures; truncated responses cannot
  execute their tool calls.
- `ExAgent.run_child/4` and delegation share an owned, ephemeral execution scope.
  Requests and batches are admitted atomically against ancestor constraints;
  permissions intersect rather than being overridden by child allow rules.
  Usage is reconciled by operation identity without counting descendants twice.
  Deadline and fail-fast request concurrency are separate controls; custom
  callbacks are not universally preempted and external unscoped IO is not tracked.
- CostGuard retains fractional cents per 1K tokens instead of truncating each
  small operation; missing rates for consumed tokens mean unknown. Existing
  arity-one estimators are homogeneous/per-request; arity-two estimators receive
  the model for heterogeneous scopes. Unknown cost is not zero or an exact bill.
- Compaction changes only request projection, preserving canonical history and
  new_messages. It protects instructions, the active user prompt and complete
  tool/retry groups, and accounts approximately for tool/thinking content. Summary
  context is a User message, not new System authority. Canonical memory still
  grows; arbitrary IO in a caller's summarizer is not automatically accounted.
- Configuring Store requires a confirmed checkpoint before positive terminal
  acknowledgement. CheckpointError retains outcome/revision; dirty state blocks
  new mutations/drain until `Server.checkpoint/1` or `Session.checkpoint/1` saves
  it, without reexecuting tools/model/change_fn. Async admission remains volatile.
  Runtime integrates partial progress once and emits one terminal per live-owner
  outcome, with safe projections and usage details.
- Snapshots write v2 and read valid v1 data through bounded migration. Corrupt,
  future, mismatched or unavailable snapshots fail restore instead of starting
  empty and overwriting good data. Policies come from trusted application
  configuration and explicit codecs; cold custom modules load safely. Session
  transitions save once, roster/cursors remain coherent across joins/leaves and
  pauses, and accepted Supervisor handoffs remain restorable.
- MCP requests own timers/caller monitors; timeout is a returned error, not only
  a caller exit. Port failure and late events close pending once; valid response
  prefixes survive a later oversized frame independent of chunk boundaries.
  Defaults are 128 pending calls and 8 MiB frames, configurable. Local cancellation
  does not imply remote rollback or exactly-once execution.
- Provider streaming uses a demand-driven Req callback bridge and bounded SSE
  parsing, with complete OpenAI/Anthropic tool/thinking/usage assembly. Default
  frame/buffer limits are 1 MiB, response 8 MiB, demand timeout 60 seconds via
  model `stream_options`. SSE now takes chunks and distinguishes EOF from DONE;
  errors/truncation are explicit. HTTP retries/redirects are disabled. Existing
  structured tool-choice defaults and overrides remain, as do public OpenAIChat
  helpers consumed by WhoamAI. OpenCode Zen/Go was carried forward from the
  pending remote commits without a merge/version change.

Verification does not include real LLM providers, Postgres acceptance or consumer
migration. The C0 probe's seven functional checks pass; its SSE input was migrated
to the new chunk API while preserving framing/message-retention invariants.

### Final consolidation verification and decoder floors

- Final review regressions reproduced stale post-hook responses, loss of known
  subtree usage after scope death, automatic model leakage in telemetry/run!
  messages, reused stream DOWN/continuations, and occurrence/diagnostic projection
  defects. Corrected code passed 43 focal tests; rich returned errors remain
  explicit while automatic channels use a shared safe ErrorProjection.
- Preparing reusable tool definitions removes repeated JSV builds without removing
  per-call validation or stale-schema checks. A controlled offline sample reduced
  structured-run p50 from 1092 to 143 microseconds at concurrency one; construction
  pays preparation cost, and this is not a real-LLM latency claim.
- Require Mint >=1.10 and HPAX >=1.0.4 in their 1.x ranges, not only the local lock,
  so downstream Hex consumers cannot select decoder versions that defeat response
  memory limits. A local TCP regression advertises a large unfinished HTTP chunk
  but sends only 128 bytes: the configured limit now acts before chunk completion.
  Test-only Postgrex/DBConnection locks move to 0.22.4/2.10.2. DESIGN 8.5 records
  the advisories, rationale and migration; no SQL dependency is added to runtime.
- A fresh independent verifier passed 541 tests/28 exclusions on Elixir 1.20/OTP 29
  and Elixir 1.18/OTP 28, including C0. After the decoder update and added regression,
  both final suites pass **542 tests, 28 excluded**, with warnings as errors
  (seeds `950880` and `580649`); forced project compilation passes for 70 files.
- Offline examples and documentation generation pass. Migration docs are included
  in package/doc manifests. The declared minimum Elixir 1.17 and real provider/DB/
  consumer acceptance remain unverified; this work neither bumps nor publishes.

### Changed — breaking observable schema contract

- `OutputSchema.json_schema/1` now follows the changeset's declared required
  fields, including an empty list. Previously an empty list made every field
  required in the generated schema, despite the changeset accepting omissions.
- Optional properties now permit `null` through `anyOf`, retaining reflected
  constraints on the non-null branch. Optional `embeds_many` remains array-only,
  matching Ecto; required fields remain non-null. These rules apply recursively
  to embeds, including optional fields inside required embedded objects/arrays.
  Schemas without a changeset keep the original all-required fallback.
- There is one generation contract, with no mode option or additional agent
  field. Keeping divergent schema/changeset semantics would add permanent API
  and testing complexity solely to preserve a discrepancy. A single contract
  favors long-term maintainability and a more accurate description to the model.
- The original source APIs (`json_schema/1`, `new/1`, `validate/2`) and result
  shapes remain, but **the JSON Schema emitted in `final_result` changes**.
  Consumers and providers can observe this change: it is not a compatible
  patch just because function signatures stay the same. The next release
  containing it **must be a new major version under SemVer (2.0.0 or later),
  not a 1.x release**. This work does not bump the version or publish anything.

### Migration

- Declare genuinely required scalar fields with `validate_required/2` in the
  changeset. For required embeds use `cast_embed/3` with `required: true`.
  Repeat this review in nested schemas rather than relying on the old
  empty-required-list fallback.
- Update schema snapshots and consumers that assumed optional fields were
  always present or never null. Optional scalars and `embeds_one` can be omitted
  or null; optional `embeds_many` can be omitted or an array, not null.
- Test the generated schema against the actual provider/backend before adopting
  the major release. It must support the emitted `anyOf`; strict structured-output
  modes may impose additional requirements on `required` and other keywords.
  Offline request tests prove the payload, not backend acceptance.
- Reflection reads a changeset built with empty attributes. It cannot perfectly
  represent arbitrary custom or conditional validations; `validate/2` remains
  the final authority and validation failures still use the existing retry path.

### Fixed

- `Server.chat/3`, `send_message/3` and `steer/3` forward `:estimate_cost`,
  `:permissions` and `:approve`, including queued requests. Explicit
  `:message_history` remains supported; internal event/run options stay protected.
- Active Server runs (including streams) are cancelled when their owner stops
  or is killed. A per-run guardian monitors owner and worker, cleans itself up
  on completion/abort/crash, and preserves isolation of run failures.
- `OutputSchema` loads schema modules before checking for `changeset/2`, so
  first-use reflection/validation does not accidentally choose the fallback.
- OpenAIChat forwards `ModelSettings.extra` in normal and streaming requests,
  enabling reasoning controls and explicit `tool_choice` (e.g. OpenRouter
  `"auto"`). Typed non-nil settings take precedence; `model/messages/tools/stream`
  cannot be overwritten, with atom/string keys normalized before merging.

Server option forwarding, owner cancellation and OpenAIChat `extra` forwarding
are fixes to existing run ownership/options contracts, not new configuration
defaults. With omitted options / empty `extra`, their prior request defaults
remain; supplied options now take effect and orphaned runs are cancelled.

Offline verification: `EXAGENT_OFFLINE=1 MIX_ENV=test mix test` skips the Postgres
bootstrap and real-provider tests; provider body tests use an in-process Req
adapter, including end-to-end `final_result` payloads with optional/nested schemas.

## [1.2.0] — turn handoff, prompt-cache accounting, refreshed docs

Two small additions to the public API and a documentation overhaul. No breaking
changes.

- `Session.handoff/2` — hand the turn directly to a participant, bypassing the
  turn policy. Useful when rehydrating a session to restore the exact participant
  whose turn it was (the policy's `next_participant` would otherwise jump to its
  computed "first"). Must be called while `:running`.
- OpenAI provider: `usage.details` now carries `cached_tokens` (extracted from
  `prompt_tokens_details.cached_tokens`), so `UsageLimits` and cost accounting can
  measure prompt-caching savings. Enable prompt caching with `cache: true` on the
  model settings.
- README rewritten (badges, Features, Requirements, Quick start with `Mix.install`,
  table of contents, hexdocs link references). `ExAgent`'s `@moduledoc` is now
  generated from the README between `<!-- MDOC -->` markers, so module docs and
  README stay in sync.

## [1.1.0] — session durability

`ExAgent.Session` now mirrors `ExAgent.Server`'s persistence: checkpoint the
session's coordination state (shared_state + turn position + status + roster
ids/kinds) to a store and rehydrate on restart. The store layer always had the
session-snapshot callbacks declared; this release wires them end-to-end.

- `ExAgent.Session.Snapshot` — a strictly JSON-serializable checkpoint
  (round-trips the policy struct too, so turn position survives). The live
  participant `ref`s come from the app on restart; only serializable parts
  restore.
- `Session.start_link(store: :ets | {mod, config})` — opt-in persistence; no-op
  by default. Checkpoint after every mutation (take_turn / update_state /
  join / leave / start / pause / resume / close / handoff); rehydrate in `init`.
- Store dispatchers for `save/load/delete_session_snapshot` added to
  `ExAgent.Store`; both `ETS` and `Postgres` impls use the new snapshot codec
  (previously stored raw maps).
- `shared_state` must be JSON-portable (plain maps/lists/scalars, or a struct
  with `@derive [Jason.Encoder]` whose fields are JSON-safe). `Jason.encode!`
  raises on non-serializable values — same rule `Server.Snapshot` enforces for
  history/metadata. After rehydrate, atom keys come back as strings (the standard
  JSON tradeoff).

This closes the asymmetry where a crashed Server resumed its conversation but a
crashed Session lost its shared_state — useful for any long-lived multi-agent
session (support triage, collaborative editing, research pipelines, D&D).

## [1.0.0] — first stable release

The complete, layered agent framework for Elixir. Inspired by pydanticAI's
ergonomics, built on BEAM-native supervision, message passing and durability.

### Layer 0 — one-shot agent loop (`ExAgent.run/3`)

- Model ⇄ tools recursive loop with parallel tool execution, per-tool retry
  budgets, structured-output retry, `max_steps`, and telemetry.
- **Structured output** via any Ecto `embedded_schema`: JSON Schema is derived
  from the schema AND its changeset validations (`validate_inclusion` → `enum`,
  `validate_number` → `minimum`/`maximum`, `validate_length` → `minLength`/
  `maxLength`), so the model can actually comply.
- **`deftool`** macro derives tool JSON Schemas from `::` type annotations.
- **Streaming** via `run_stream/3` (lazy deltas + final result).
- Provider-agnostic: OpenAI, OpenRouter, Anthropic, Z.AI (Anthropic-compatible),
  plus a deterministic `Test` model for offline development.
- Provider parsers are **crash-safe** against malformed real-world responses
  (empty/absent `choices`, `content: null`, `tool_calls: null`, partial `usage`).
- A tool task that raises is **contained** → `{:error, _}`, never a linked EXIT
  that kills the agent process.
- DB-free core: serialize/resume a conversation via `Message.to_json/from_json`.

### Layer 1 — stateful runtime (`ExAgent.Server`)

- A supervised, long-lived agent preserving history, accumulating usage,
  threading stateful models across runs, emitting events.
- Sync `chat/3`, async `send_message/3`, text `stream/3`, `steer/2` (front-of-
  queue), `abort/1`, `set_model/2`, `reset/1`, `history/1`, `usage/1`, `health/1`.
- Runs execute under `ExAgent.TaskSupervisor`, so the server stays responsive to
  `abort/1`/`health/1` and applies backpressure (`:busy` / `:queue_full`).
- Streaming handlers guard on `run_id`: a stale delta from an aborted run can't
  corrupt the next run's history. `abort/1` is race-safe vs natural completion.

### Layer 2 — persistence (`ExAgent.Store` + `Server.Snapshot`)

- Behaviour + `ETS` (in-process) + `Postgres` (durable, optional deps) impls.
- Strictly JSON-serializable snapshots (never pids, secrets or tool closures);
  the live model/tools come from an app-supplied template on restart.
- Checkpoint after every run, rehydrate on restart — survives supervised crashes.
- Cross-store portable: a snapshot round-trips ETS ↔ Postgres unchanged.
- Checkpoint/rehydrate failures are **logged** (never silently swallowed).

### Layer 3 — multi-agent sessions (`ExAgent.Session`)

- Coordinated multi-participant turns over app-defined `shared_state`, with the
  Session as the **single writer**.
- `TurnPolicy` behaviour + `RoundRobin`, `Initiative` (custom order),
  `SupervisorPolicy` (a coordinator alternates with workers).
- `SharedState` handle in `RunContext.deps` so tools read/propose state safely.
- Lifecycle: `start/join/leave/take_turn/update_state/end_turn/pause/resume/close`.
- **Leaving mid-turn never deadlocks**: the next participant is advanced (all
  three policies); an empty roster transitions to `:done`.

### Coordination (`ExAgent.Coordination`)

- `delegation_tool/2` — agent-as-tool with **shared usage** up the tree.
- `handoff/2` — direct control transfer bypassing the turn policy.

### Robustness & safety

- `Compaction` behaviour + `Summary` impl + `Capability` hook: shrink long
  histories (LLM-driven summary + recent window) before they exceed the context
  window, keeping `new_messages` accurate.
- `UsageLimits` + `CostGuard`: request/token/tool-calls/budget caps.
- Anthropic prompt caching (`cache: true`).
- `Permissions`: per-tool `allow`/`ask`/`deny` globs, fail-closed, wired into
  the loop via `:permissions` + `:approve`.

### External tools (MCP)

- `ExAgent.MCP.Client` (stdio JSON-RPC) consumes any
  [Model Context Protocol](https://modelcontextprotocol.io) server's tools and
  exposes them as `ExAgent.Tool`s. Handshake is resilient to frames split across
  data chunks; transport exits and errors surface cleanly.

### Events & PubSub

- Versioned `ExAgent.Event` envelopes (distinct from `:telemetry`).
- `ExAgent.PubSub` behaviour: `None` (default), `Local` (Registry), `Phoenix`
  (dynamic, no hard dependency). A backend returning `{:error, _}` degrades
  gracefully (logs, never crashes the stateful owner).

### Packaging

- `config/` is excluded from the published package; `ecto_sql` + `postgrex` are
  optional (test-only) deps — exAgent stays DB-free unless you opt into the
  Postgres store.
