# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
