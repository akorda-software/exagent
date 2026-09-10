# ExAgent orchestration checkpoint

> **Closed historical run log.** Handles, ownership and instructions below belong
> to the completed consolidation. Use the current
> [handoff](../../development/handoff.md) before starting new work; never reuse a
> closed handle or treat an archived assignment as active authority.

Updated: 2026-09-10, final local night acceptance completed.

## Current night state — consult this before historical checkpoints

Run `run_4315531152c9`, generation1; runtime
`bd91a4f6-82f0-4a36-b3c3-db7494593bc1`, host local, same main workspace.
The coordinator completed multiple useful waves from22:20UTC through final
acceptance after00:32UTC. N01–N18 local scope is complete or explicitly delimited;
the original pause/backlog text below is historical, not a pending assignment.

- Final fresh verifier `task_7217175a868e` / `ctx_eb2d891ead54` completed and released.
  **619 passed,0 failed,28 excluded**, seed37556, in Elixir1.20.0/OTP29.0.5,
  1.18.4/OTP28.0 and1.17.3/OTP27.3.4.17, each with forced compile73.
- C0 14/14, documentation probe7/7 and isolated R3 1/1 in all three runtimes.
  Seven native examples and final load smoke pass; all runtime inputs are synthetic.
- Final TAR:72/72 contracts in12 byte-based consumers;11 strict passes and one
  explicit strict failure, exporter/OTP29's nine gproc warnings. No own ExAgent
  warnings remain. The native fresh root graph also reports dependency xref notices;
  project compile success is not a claim that all dependency compilers are silent.
- N13 dataset:4000 measured successful runs,12200 local spans without normal loss,
  bounded saturation32/610, sampled maxima and percentiles recorded. It predates
  the final startup-only compiler fix; final smoke verifies the new code. N14
  intentionally makes no optimization without a demonstrated hotspot.
- Startup optionality, test batching, runner selectors/destinations/diagnostic
  artifacts, oracle payload/accounting and two README errors were corrected with
  reproductions and independent verification. No new production feature mode.
- Docs generation with warnings-as-errors, complete format and diff checks passed.
  Durable evidence: ACTION_PLAN10, ROADMAP, DESIGN8.8–8.9, tests and probes.

**Resources:**16 Tasks/Dispatches completed,15 distinct Astra worker terminals
closed, no active worker or build window, mailbox empty. One initial attempt is
historically labelled retained after useful reuse; its final resource is released
and exact worker observation is exited (`ctx_76661ceb4f2f`). Do not reuse closed
handles. No scheduler keeps working after this coordinator's final response.

**Unrepaired host incident:** package bootstrap inherited MIX_ARCHIVES and
overwrote shared Hex2.5.1 with incompatible BEAM. Further global writes stopped;
no exact previous backup found. Runner now checks effective isolated destinations,
and coordinator uses direct ERTS/Elixir PATH (avoids mise shim) plus temporary
MIX_HOME/MIX_ARCHIVES. Global repair needs authorization. Do not hide this under
claims of clean verification; native tests and package contracts use isolated Hex.

Final accepted TAR: `/tmp/opencode/exagent-night-final-reviewed-preview.tar`, SHA256
`d656bd2a83608046028e031e3d6585c606d9a2fcb6f2774ba793da0fcc6c008a`, nominal1.2.0.
It contains82 files whose hashes matched the final checkout at verification.
Previous TARs remain historical evidence. Detailed final report/JSON/term:
`/tmp/opencode/exagent-night-final-verification.*`; logs and runtime-specific
environments/builds: `/tmp/opencode/exagent-night-final-n18/`. Generated docs:
`/tmp/opencode/exagent-night-final-docs/`. The temporary1.17/OTP27 toolchain remains
under `/tmp/opencode/exagent-night-package-toolchain`, with official origins/hashes
recorded in ACTION_PLAN and the package report.

**Next authorized continuation:** rediscover runtime/Run/mail before new work.
Do not rerun the completed backlog to consume time. Shared Hex repair requires
explicit authorization; native HTTP ownership/fidelity, Langfuse/Opik access and
comparison, real providers/DB/consumer migration and C7 scope remain separate gates.
No publish, bump, commit, merge, deploy, service restart or consumer edits occurred.
HEAD remains c08125be71eada363d08ca463cc7df2ea7855e4a; all WIP/untracked preserved.

## Historical night checkpoints — superseded by the final state above

### N18 checkpoint 00:16UTC — all latest fixes frozen, Mix reopened

Final load/docs review completed without findings and was released. N18 then
found a native1.20 no-SDK warning on helper-only startup (dynamic false inferred),
although1.18 and1.17 TAR matrices passed24/24 strict. Coordinator reproduced it
with actual isolated compilation, then selected start_link at compile time and
compiled its private validation/default helpers only with SDK. No-diagnostics
checks pass1.20/29 and1.17/27, with late SDK still unavailable; SDK-present focal16
passes. Library startup semantics/defaults are preserved; no suppression.

Coordinator also found phase diagnostics overwriting graph.term in real N18
consumer artifacts. A new synthetic graph output control reproduced the overwrite;
record_phase now writes phase-*.term, leaving graph.term intact. Full isolation
controls and format pass. Root test-only restart batching fix remains frozen.

N18 was paused for these edits and now has exclusive Mix reopened. It must review
them independently, repeat three root suites and consumer matrices on the revised
TAR, and verify graph.term plus phase-graph.term separately. The original load
matrix predates this startup-only change (outside measured run paths); final
smoke checks the new code, without rebranding old hashes as current.

### N18 checkpoint 2026-09-10 00:03UTC

First native fresh compile73 passed, with upstream warnings recorded. Full suite
seed37556 had618/619 passed,28excluded: the pre-existing processor restart test
assumed both ended spans share the first batch. Focal same seed16/16 passed.
Verifier paused root builds and continued immutable TAR consumers independently.
Coordinator forced the interleaving with a first-export barrier, reproduced0/1,
and changed ONLY bounded_processor_test.exs to assert two separate exports,
unique IDs and accepted/exported2/retained0. Compiled focal16/16 and format pass.
Root sources frozen again; verifier `ctx_eb2d891ead54` has exclusive Mix window
reopened and will independently review/repeat native/full alternative gates.
Final TAR unchanged: test-only correction. No production fix or timeout change.

### Review follow-up23:15UTC — package bootstrap temporarily gated

- Fresh package review reproduced P1: inherited MIX_EXS can load a foreign project
  after the path-only preflight passes. Its reproduction substitutes harmless Mix
  commands in a /tmp copy; no further host installation occurred. Also found that
  compile.log warnings escape the runner's edge-only warning gate, and a symlink
  ancestor can bypass the work-dir string prefix. Do not run package bootstrap
  until these fixes and regression controls pass.
- Fresh scenario review completed12/12, seed37556, without a production P0/P1.
  Two P2 oracle gaps: per-request OTLP usage/cache/cost and partial tokens, and
  Server snapshot tool payload/full usage. Reviewer `ctx_5ba842c9d4b5` released
  with captured archive/closed terminal.
- New fix owner: `task_a92dfdb9e95e` / `ctx_71bb943bd26e`, fresh Astra terminal
  `term_fc6bfb38-9c8d-4891-9ec9-b3b9789f7cd3`. Exclusively package runner/isolation
  support (templates if needed), native_otlp_scenario_probe.exs and
  runtime_sequence_test.exs. No lib/root Mix edits or builds; isolated own VMs only.
  N13/N14/N15 now owns the focal/example Mix window. Package reviewer completed its
  report and was released with a closed terminal; fixes remain in progress.
- Decision: warning checks cover all compile phases and remain strict; do not
  suppress/allowlist or upgrade gproc to claim all-green. The known OTP29 exporter
  graph can have runtime contracts passing while the strict runner exits1 on
  third-party warnings. Report those states distinctly in final acceptance.

## Active night checkpoint — supersedes the historical pause below

- Full NEXT_AGENT_PROMPT read; orchestration skill loaded. User explicitly started
  this new night session and authorized multiple useful units with Astra workers.
- Runtime `bd91a4f6-82f0-4a36-b3c3-db7494593bc1`, host local, Orca1.4.198-kukapu.1;
  same main workspace/key. C6 was inspected: all nine Dispatches completed.
  Closed worker handles are not reused.
- Fresh milestone Run `run_4315531152c9`, generation1, created22:20:39UTC.
  Runtime resolved coordinator `term_64587472-faf7-47e2-875c-6f990f29d728` itself;
  no historical `--from` impersonation. C6 is preceding history.
- Fresh baseline22:20UTC: `EXAGENT_OFFLINE=1 MIX_ENV=test mix test
  --warnings-as-errors`: **579 passed,28 excluded**, seed280440,5.3s. HEAD remains
  c08125be71eada363d08ca463cc7df2ea7855e4a; existing WIP/untracked preserved.
- Frozen package built before author edits: `/tmp/opencode/exagent-night-wave1-preview.tar`,
  Hex checksum `ddd66c13a4a87e8900828826ed15ef2d0f599d048d5abe8310c3b6bd3927eea2`.
  Nominal1.2.0 local preview only. No publication or version change.

| Task | Dispatch | Fresh worker | Ownership/build window |
|---|---|---|---|
| `task_df8f94538ab0` | `ctx_0ed3fc45043f` | `term_3bdb33c5-19f3-462a-9316-bd1c4ea5fd63` | N01–N03 native OTLP tests/support, justified observability fixes, exclusive mix.exs/lock; sole root build owner. |
| `task_7715da65eff2` | `ctx_6e8f963febf8` | `term_7aaf0593-a74e-46fd-b0e5-ae560beaa334` | N05–N06 frozen TAR consumers, new package_acceptance support; only independent /tmp sources/deps/builds. |

Both terminal previews confirmed `openai/gpt-6-astra`, xhigh, OpenCode1.18.30,
with authorized heartbeat/progress. Coordinator owns root docs/contracts/integration.
No other root compilation while OTLP author edits. Mail FIFO/ACK, fresh reviews,
resource release and next-unit selection remain coordinator responsibilities.
Langfuse/Opik access, real providers/DB/consumers and C7 remain separate gates;
no commits/bump/publish/deploy/restart/global config/consumer changes authorized.
Next: supervise both authors, review concrete results, then advance viable backlog.

### Tooling incident22:36–22:38UTC — active limitation

The package worker's bootstrap isolated MIX_HOME but inherited a host MIX_ARCHIVES:
`/home/kukapu/.local/share/mise/installs/elixir/1.20.0/.mix/archives`. Its Elixir1.17
`mix local.hex` consequently replaced Hex2.5.1 there with a BEAM incompatible with
OTP29. This was an unintended out-of-scope write, not authorized global setup.
The coordinator independently reproduced the failure with `mix help hex.audit`;
before the incident that command and `mix hex.audit` worked at22:28UTC.

Further global writes/restoration are stopped. Workers must explicitly isolate
MIX_HOME **and** MIX_ARCHIVES (and relevant Rebar/tooling paths) under/tmp for every
bootstrap/subcommand, preserving incident logs. The package author owns prevention
in its runner; OTLP author recovers its compiled gate using separate temporary Hex.
No repo reset or consumer modification occurred. Repair of shared Hex remains a
separate authorization gate; no success claim may hide that host limitation.
Initial logs: `/tmp/opencode/exagent-night-package-120-fresh/tooling-hex.log` and
`/tmp/opencode/exagent-night-package-117-fresh/tooling-hex.log`. Confirm final report
paths and safe command prefixes on author delivery before further root gates.

### Wave1 OTLP checkpoint22:45UTC

- N01–N03 `task_df8f94538ab0` / `ctx_0ed3fc45043f` completed, focal4/4 seed576860;
  coordinator full compiled gate583/28 seed280424,11.1s. Sources stable, no libfix.
  Native bool/partial-success/lifecycle limits recorded in DESIGN8.8/OBSERVABILITY7.
- Fresh review `task_ba1c3ef3eeab` / `ctx_8c19b7d9dd60`, terminal
  `term_b3143140-f345-461f-ae6e-ea6194411656`, read-only original N01–N03 files.
- Author immediately reused for own N04/N12 context: `task_f4a858b961f2` /
  `ctx_76661ceb4f2f`, same verified live terminal. Exclusive new
  `native_otlp_scenario*` test/probe files; original receiver/probe frozen forreview.
  Sole root build owner remains this author; lib/mix changes require coordination.
- Package author remains active on independent frozen consumers/toolchain evidence
  and isolation prevention. Final delivery/review pending.
- Coordinator's PATH had a mise `erl` shim overriding even explicit MIX_ prefix.
  Effective values confirmed with direct erlang29/bin + elixir1.20.0/bin PATH.
  Use the full command recorded in ACTION_PLAN10; short prefix alone is insufficient
  in that shell. Shared Hex remains unrepaired; local `/tmp/opencode/exagent-native-otlp-mix`
  works with both MIX_HOME and MIX_ARCHIVES plus direct runtime PATH.

### Ownership update22:53UTC

- N01–N03 fresh review completed: no new P0/P1 in the patch; four independent
  probes exit0. Native HTTP operational P1 remains explicitly gated. Reviewer
  `ctx_8c19b7d9dd60` released with captured archive and closed terminal.
- N07/N08 started: `task_b0811b2c406f` / `ctx_20f4cfb015d6`, fresh Astra terminal
  `term_905b4b5b-1c2b-47b7-9882-e05e00e20abb`. Owns only new runtime/session
  sequence `.exs` tests; direct isolated-VM verification against existing BEAMs.
  Server/Session production edits need explicit transfer; no root Mix builds.
- N06 found a real Elixir1.17 absent-SDK compile warning in BoundedProcessor's
  constant guard. Earlier package72 passing contracts did not certify clean
  dependency compilation; the author corrected that overstatement.
- OTLP author confirmed no active build and closed future Mix builds. Package
  author `ctx_6e8f963febf8` now temporarily owns ONLY
  `lib/exagent/observability/bounded_processor.ex` for that warning fix, preserving
  API/return/compile-time SDK availability. No root compilation while editing.
  It may build a distinct local `/tmp/opencode/exagent-night-package-fixed-preview.tar`
  and verify its bytes in isolated consumers; initial TAR stays immutable.
- Next exact action: package author freezes the library file; reopen only OTLP
  author's focal Mix window. Runtime sequence author keeps direct VM tests. Review
  package/tooling and fixed branch with fresh context after delivery. No global
  Hex repair or any further out-of-scope tooling write is authorized.

## Historical user steering: prepare a fresh-context night coordinator

The user wants autonomous improvement over multiple useful units while sleeping,
then explicitly paused this coordinator to prepare the next-agent prompt first.
Only documentation is being prepared in this handoff; **no night implementation,
new Orca Tasks/Dispatches or workers have been started**. The next coordinator is
authorized to execute the night backlog after reading the full prompt and
recovering runtime authority. This coordinator stops at delivering that prompt.

`NEXT_AGENT_PROMPT.md` is the complete handoff: original mandate/invariants,
implemented C1-C5/C6, evidence, current restrictions and eighteen prioritized night
units. First wave: native OTLP loopback and genuinely independent frozen-package/
compatibility acceptance. Continue to runtime/protocol/property/soak/eval work;
unavailable Langfuse/Opik access blocks that branch, not all offline improvement.
C7 public continuation/workflow scope remains conditional, not implicitly approved.

Fresh discovery before pause: same local runtime/workspace/HEAD and current
`run_395ccad931e7`, generation1. C1-C5 Run is now generation2 without a coordinator
(generation1 was its execution-time identity). All nine C6 Dispatches are completed,
their five worker terminals are closed, and the Run inbox is empty. Do not infer a
live worker from historical retained resources or reuse a closed handle.

Fresh baseline at approximately21:52 UTC:
`EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors` -> **579 passed,
28 excluded**, seed806578, 5.3 seconds, Elixir1.20/OTP29. No source code changed
after that baseline during handoff preparation. The independent two-runtime
acceptance below remains the preceding full matrix, not a new test result.

No nightly Run has been created. Discover/inspect the relevant Run and caller
before binding or creating a new milestone; never impersonate the old `--from`.
Orca stores state/mail, not a scheduler: the next chat must be started and keep its
coordinator executing. No background-night promise is made by this paused chat.
Keep Astra for workers, explicit ownership/build windows, fresh reviews and all
existing no-commit/bump/publish/deploy/paid-provider/consumer-edit constraints.

## Final C6 checkpoint

- Objective: optional, decoupled native OpenTelemetry instrumentation with offline
  acceptance, privacy and bounded asynchronous export. Langfuse/Opik comparison
  still needs authorized access; neither backend is selected or deployed.
- Runtime rediscovered: `bd91a4f6-82f0-4a36-b3c3-db7494593bc1`, local,
  Orca `1.4.198-kukapu.1`, existing main workspace/key below. All C1-C5 Tasks were
  completed; old retained resource records do not reopen the seven closed workers.
- New milestone Run: `run_395ccad931e7`, generation `1`. The runtime freshly
  confirmed coordinator `term_64587472-faf7-47e2-875c-6f990f29d728` on run-create,
  with no historical handle impersonation or takeover. C1-C5 Run remains history.
- Baseline before source edits: native Elixir1.20.0/OTP29.0.5 forced compile70,
  warnings-as-errors, **542 passed/28 excluded**, seed517405, all14 C0 invariants
  true. Alternative Elixir1.18.4/OTP28 forced compile70 passed; full suite seed664393
  had one 100ms startup assert_receive timeout in ServerOwnershipTest stop_agent/
  stream. The same file/seed passed12/12 immediately without edits. Its readiness
  barrier was changed to1000ms; both complete final suites passed cancellation checks.
- Git HEAD remains `c08125be71eada363d08ca463cc7df2ea7855e4a`, main ahead1/behind3.
  All existing modified and untracked implementation is preserved.

| Task | Dispatch | Fresh terminal | Ownership |
|---|---|---|---|
| `task_a4f8288c7860` | `ctx_73fd67c255f6` | `term_9f5c4dbb-0569-439a-89d4-0fa4c5c9209f` | Completed PREPARED; sources frozen, context reused for gate below. |
| `task_4794507bf0ac` | `ctx_0e87a0c76452` | `term_eb01d783-1359-48fa-ad91-75f4206d3fd5` | Completed read-only audit; report `/tmp/opencode/exagent-c6-sdk-audit.md`; context reused below. |
| `task_03fed70a9617` | `ctx_651101dd2213` | `term_eb01d783-1359-48fa-ad91-75f4206d3fd5` | Completed initial preparation; context reused for fixes and subsequently closed. |
| `task_d05065870b3e` | `ctx_7af91754423e` | `term_9f5c4dbb-0569-439a-89d4-0fa4c5c9209f` | Completed: focal27 PASS seed442576; example/bench509/509, context reused below. |
| `task_026c0fd4506e` | `ctx_64507f40d619` | `term_2defd6e7-1580-45c5-aa47-4cd23512c754` | Completed: three static P2; released/closed with archive. |
| `task_08ebbb1ef335` | `ctx_fc2c48783c51` | `term_6ef114e0-a0eb-4e5e-bde0-db393fcf945a` | Completed: R1-R4; released/closed with archive. |
| `task_c9a7d9b554ed` | `ctx_2b87cb40ccad` | `term_eb01d783-1359-48fa-ad91-75f4206d3fd5` | Completed; 16 isolated tests, optional compile probes and persistent R3 probe; released/closed with archive. |
| `task_ee31d11d6ab5` | `ctx_c98bc24c2a8b` | `term_9f5c4dbb-0569-439a-89d4-0fa4c5c9209f` | Completed; 6 red/21 then21 green isolated; closed after exact completed+idle/path verification (release retained external). |
| `task_5aa36ce92827` | `ctx_be95da946f17` | `term_e2d71acc-a936-49d1-a42b-24244ab726ad` | Final gates succeeded; released/closed with archive. No build window or worker remains active. |

All five fresh workers selected `openai/gpt-6-astra`; terminal previews showed
Astra OpenAI xhigh on authors/reviewers and high on the final verifier. No effort
flag or global model configuration change was used.
Coordinator owns root documentation, final integration gates and the pre-existing
ServerOwnershipTest timing investigation. No shared-source builds while editing;
initial joint compile passed for72 files plus OTel API/SDK. Focal27 seed366931
gave25 passes and2 fixture failures (Store :ets normalization, save timestamps).
Focal/example window ended with27/27 PASS and509/509 exports, zero drops/errors.
50warmup/200 samples c1: disabled55/76us p50/p95, enabled121/153us; construction
excluded, synthetic only. This was an intermediate gate, superseded by final
verification below. R3 probe MUST use its isolated `elixir -pa` command, not mix run.
Next authorized work follows the night backlog in NEXT_AGENT_PROMPT: native OTLP
local acceptance and offline C8; Langfuse/Opik API/UI needs authorized access.
No backend is selected; C7 scope and C8 real
providers/DB/consumers remain separate. No commit, bump, publication, deployment,
consumer edit or paid-provider test is authorized by this checkpoint.

Audit accepted: API1.5/SDK1.7/exporter1.10, upstream SHA9f0511e. BSP queue is soft,
has no requested loss counters or flush ACK; a small app-owned native processor
extension is justified. GenAI profile pins SHA b5d8440f6f126738fd50f927752cd669772c517b,
uses cache_write, no invented schema URL. Explicit Logger trace-metadata restoration
is required because native detach does not remove all old keys. DESIGN8.6 records
the additive contract. Coordinator prepared a temporary minimal downstream project
to check optionality, and extended only the failed test's readiness barrier from
100ms to1000ms (same cancellation assertions, verified by both final suites).
Three temporary downstream projects live in /tmp/opencode/exagent-c6-*-consumer.
Initially minimal and API-only emitted an absent-SDK tuple-index warning despite
successful execution; the corrected branch is now warning-free. The third,
SDK-enabled host REPRODUCED R1: compiling ExAgent+children before sibling SDK leaves
processor permanently sdk_unavailable. Commands: mix deps.compile exagent
--include-children; mix deps.compile opentelemetry; mix run smoke.exs, all offline
runtime flags, no --no-compile. Final fresh builds of all three now pass without
warnings; the SDK consumer visibly compiles SDK before ExAgent and exports2 spans.
Root docs now include OBSERVABILITY.md; README and MIGRATION link
it. Source version remains1.2.0, not a releasable major. The checkpoint logger now
uses a stricter additive ErrorProjection.diagnostic helper, documented in the
changelog; rich explicit channels retain their data. Synthesized Server failure
completeness is conservatively corrected across partial/Event/span (DESIGN8.7).

Resolved review findings and decisions:
- Processor report `/tmp/opencode/exagent-c6-processor-review.md`: R1 compile
  dependency reproduced above; R2 trap_exit exporter can orphan OWN worker; R3
  concurrent flush bit reset loses a request; R4 SDK/OTP supervisor mfargs can
  print secret-bearing bootstrap opts. The author reproduced R2/R3/R4 in isolation.
  R4 boundary decision: opts must be non-secret bootstrap descriptors; resolve
  credentials through exporter env/app configuration. No global Logger masking
  or claim to detect arbitrary secrets. The recommended safe path was verified
  with a synthetic credential and SASL reports enabled in a disposable VM.
- Tracing report `/tmp/opencode/exagent-c6-tracing-review.md`: F1 Server synthetic
  abort claims complete/known zero cost from old progress; F2 empty context leaves
  old Logger IDs DURING callback; F3 bigint bypasses input content budget. All
  reproduced and fixed without recalculating the ledger; known subtotals survive.
- Reports `/tmp/opencode/exagent-c6-focal-verified.md` and the prepared implementation
  reports preserve intermediate evidence. Final evidence follows; Langfuse/Opik
  and native OTLP acceptance remain separate unfinished gates.

### Final acceptance and resources

- Native forced compile72, warnings-as-errors: PASS. Full suite **579 passed,
  28 excluded**, seed482769. Elixir1.20.0/OTP29.0.5.
- Compatibility fresh full dependency build and compile72: PASS. Full suite
  **607 total, 0 failures, 28 excluded =579 passed**, seed648445, Elixir1.18.4/OTP28.
  Build `/tmp/opencode/exagent-c6-compat-118-final`. Rebar discarded one stale DAG
  cache and rebuilt successfully; no compiler warning remained.
- Both C0 probes:14 true invariants. Separate deterministic R3 probe:1 passed.
- All three fresh consumer graphs warning-free, including optional SDK ordering.
- Final local example:509/509 exports, no losses/errors. 50warmup/200 samples/c1,
  construction excluded: disabled p50/p95=56/70us; enabled123/178us. No real-LLM SLO.
- First final-suite attempts failed only because an old exhaustive struct-key
  fixture omitted observability. Coordinator paused the verifier, added only
  observability/defaultnil to that fixture and retained the exact schema API;
  both complete suites then passed. No further source changes followed those gates.
- Documentation: `EXAGENT_OFFLINE=1 mix docs --warnings-as-errors --output
  /tmp/opencode/exagent-c6-docs` PASS after qualifying one guide function link.
- Local package: `EXAGENT_OFFLINE=1 mix hex.build --output
  /tmp/opencode/exagent-c6-preview.tar` PASS. Output lists API/SDK optional and no
  runtime SQL, includes OBSERVABILITY/README/MIGRATION/CHANGELOG. Nominal1.2.0 is
  unchanged and **not publishable as the pending major**; no publish/commit occurred.
- Durable evidence: ACTION_PLAN9, DESIGN8.6–8.7, CHANGELOG, tests and probe. Detailed
  report `/tmp/opencode/exagent-c6-final-verification.md`, logs `exagent-c6-final-*`.
- All nine C6 Tasks/Dispatches completed. All five distinct worker terminals are
  closed. Four closed by worker-release with archives; the tracing author returned
  retained/external, so exact completed state, idle preview and original workspace
  identity were checked before its authorized individual terminal close
  (`ptyKilled:true`). Historical retained records in worker-list are not live workers.
- No questions, editors, verifiers, retained live workers or pending build ownership.
  Rediscover runtime/Run/authority on the next request; do not reuse closed handles.
  `NEXT_AGENT_PROMPT.md` now describes this C6-neutral closure and the next gates.

## Historical C1-C5 closure

Implementation, review fixes, verification and worker cleanup for C1-C5 are complete.
The prior Run is a recoverable record, not a scheduler.

The current handoff is `NEXT_AGENT_PROMPT.md`. The final C6 checkpoint above
supersedes intermediate startup state. The final-acceptance section below records C1-C5;
intermediate checkpoints are historical, not pending assignments to reactivate.

## Objective and authority

The author authorized autonomous technical decisions and sustained implementation
of ACTION_PLAN, using Astra for all workers. Preserve C0/C2.1 and existing WIP.
Target an advanced, verified C1-C5 foundation; choose Langfuse/Opik only at C6
after comparative acceptance tests. Ask the author for real product/access/cost
blockers, not ordinary implementation choices.

User steering: keep working; reuse agents only when their accumulated context
helps the next task, otherwise start fresh Astra agents and close unused workers.
The core author is reused for closely related fixes. The latest Event/Compaction
fix worker starts fresh; subsequent independent acceptance should also use fresh
context. Do not pause the implementation merely to acknowledge this steering.

No commits, version bumps, publication, deployments, global configuration changes,
consumer edits or paid-provider test calls. Worker inference with Astra is
authorized. Use apply_patch and offline runtime verification. Do not merge/reset
the main worktree or delete any worker workspace without authorization.

## Runtime identity

- Executable: `orca` in the coordinator environment.
- Runtime: `bd91a4f6-82f0-4a36-b3c3-db7494593bc1`, host `local`.
- Orca version: `1.4.198-kukapu.1`.
- Workspace: `/home/kukapu/dev/projects/exAgent`.
- Worktree key: `wt2:local:4d7e38d1-cc77-4904-90e3-7117ab004c64`.
- Worktree ID: `83438294-6397-425c-a0b2-8def0a505dda::/home/kukapu/dev/projects/exAgent`.
- Run: `run_ab7595996c57`, consumer generation `1`.
- Coordinator: `term_64587472-faf7-47e2-875c-6f990f29d728`.
- Git base: `c08125be71eada363d08ca463cc7df2ea7855e4a`; local branch main has
  three remote OpenCode-adapter commits pending integration and one local commit.

This CLI requires `task-create --spec` followed by `worker-start --task`.
`worker-start --spec` is rejected before mutation. OpenCode does not support the
worker-start effort flag. Worker previews during execution showed GPT-6 Astra
OpenAI, high; requested/effective launch model was `openai/gpt-6-astra`.
Background visibility warnings do not require focusing/opening their windows.
This installed CLI also rejects `worker-list --include-remote`; use worker-list
with --run/--json here. All workers in this Run were placed on the local host.

## Current ownership

| Task | Dispatch | Terminal | Responsibility / state |
|---|---|---|---|
| `task_7600e92eee6a` | `ctx_89fc753ea8dd` | `term_c1049573-c109-4662-b94a-fbdce2cc72f5` | Completed; fixes green; settled idle terminal explicitly closed with user authorization. |
| `task_e09367660ef6` | `ctx_0b7f481b97b9` | `term_9f3cebff-fe90-481a-acc9-5342e72413f2` | Completed and released/closed with archive; same 43-test green gate. |
| `task_97d0d26d0743` | `ctx_7639b60ad3a3` | `term_88cfa917-d9c8-4aab-9920-91175536d2d0` | Fresh independent verifier succeeded; released/closed with transcript archive. |

Coordinator owns shared contracts, project docs, dependency decisions and final
integration. No two writers for one area. During parallel editing phases workers
must not compile/test shared sources; coordinator grants an explicit verification
window after all editors settle. Read-only reviewers may run concurrently.
No editors or verifiers remain active; build/test ownership is released. The prior
BEAM was retained for a genuine --no-compile red run, then fixes were compiled.
Several workers reported automatic formatting
after apply_patch; no semantic foreign edits have been identified.

During execution, fleet observations marked some reused terminals external or
user-owned via user_takeover. That was a historical ownership state, not evidence
of an active Dispatch now. The subsequent authorized closures are recorded below;
do not reuse these closed handles or infer fresh authority from old observations.

Release initially returned retained for the reused/user-owned terminals. After
the author's explicit permission to close unused spawned agents, coordinator
verified latest Dispatch completed + idle preview + exact local workspace and
closed only these four settled worker panes with terminal close (ptyKilled true):
term_db15ab27-94a1-455f-aada-56d38d0af0d9,
term_3eafc841-d855-4e0d-b76b-36f335681bf1,
term_999dfc29-32b1-40a1-b36c-52377b04278c,
term_52ede0d2-8720-4c03-95b9-af741e146d51.
No active worker/coordinator, workspace, setup or unrelated terminal was closed.
Fresh ctx_0b7f481b97b9 completed and worker-release closed its terminal with an
output archive. The core author's final Dispatch then completed; its exact idle
terminal was checked and explicitly closed too. The fresh final verifier was
closed by worker-release with its output archive. All seven spawned worker
terminals are closed; the coordinator and unrelated terminals were not closed.

## Historical checkpoints — not active assignments

The pending/next wording in these intermediate records describes that earlier
stage. Final verification and closure supersede it; no old worker remains active.

- C0/C2.1 baseline: 319 offline tests pass, 28 excluded, two pre-existing unused
  alias warnings in tests. Forced project compilation passed. See ACTION_PLAN 7.
- JSV 0.20.0 isolated spike passed in /tmp/opencode: integer/minimum/extras,
  local refs and rejection of an unresolved external ref with no HTTP resolver.
  Hex declares Elixir ~> 1.15; current project requires ~> 1.17. Dependency is
  added by the Tool worker; it reported deps.get finished without unrelated
  upgrades. JSV-specific casting/internal module refs are blocked before build;
  independent review and runtime tests are pending.
- C1 decisions selected in DESIGN 8.2-8.4; contracts are recorded before their
  implementations, not claimed as passing yet. Core supplies RunError{reason,
  partial}, full result status/run_id/usage_status/pending_response and private
  on_progress callback. Runtime can retain that progress without putting models
  into PubSub. Tool helpers expose prepare/validate_args/validate_result.
- Initial design Tasks task_8de867204726 and task_321a4d9170c1 completed read-only;
  terminals reused above. Runtime proposal: /tmp/opencode/exagent-c1-c5-runtime-proposal.md.
- Consumer Task task_13b55718a098 completed; terminal reused for providers.
  Report: /tmp/opencode/exagent-consumer-inventory-c1-c8-task_13b55718a098.md.
  Dragonex at /home/kukapu/dev/projects/dragonex pins Git a31b306 (1.3.0), uses
  chat(stream_text:true), deps.on_text_delta and custom WorldDriven Session policy.
  WhoamAI at /home/kukapu/dev/projects/whoamai vendors c08125b (1.2.0), uses sync
  run and custom OpenRouter adapter/Admission plus public OpenAIChat helpers.
  Neither consumer was edited or run; their migration acceptance remains C8.
- ReqLLM evaluated through API docs and concrete consumers. Keep/consolidate own
  adapters this cycle, preserve public helpers, reconsider only with an equivalent
  adapter spike. See DESIGN 8.4; not a negative backend-compatibility claim.
- Next: finish current edits, reuse Tool worker for MCP if useful; after editors
  settle run focal/build gates centrally, route fixes to owners, then C4 and
  independent review. Do not mark C2/C3/C5 complete on worker_done alone.

## Historical prepared implementations (subsequently verified)

- Core C2/C3 Task task_2e0b4a5598c9 completed prepared (24 new regression sources,
  no project compile/tests). Result/Model/RunStream/tools/status codecs done;
  C4 task above extends it. Provider identified missing thinking_delta handling,
  Compaction identified sync ignoring request_messages; both sent to C4 owner.
- Runtime task_dba36ac82683 completed prepared: /tmp/opencode/exagent-c5-runtime-implementation.md.
  CheckpointError, dirty revision retry, safe v1/v2 restore and FSM implemented;
  project runtime tests pending. Custom handoff fallback accepted only when
  can_act already admits the requested live member.
- Providers task_8d620548ffcd completed prepared: lazy Req callback transport,
  bounded SSE, complete OpenAI/Anthropic responses with final_model, OpenCode.
  Defaults required/any were explicitly RESTORED after a misunderstood instruction;
  do not migrate output_schema_contract_test to auto. retry/redirect false and
  stream_options 1MiB frame/buffer, 8MiB response, 60s demand timeout are observable.
  C0 probe needs migration from Req.Response.Async to chunk source/eof sentinel.
- MCP task_53fd943491a6 completed prepared: /tmp/opencode/exagent-mcp-task_53fd943491a6.md.
  Internal timers/caller monitors, late-event cleanup, max_pending128/frame8MiB,
  timeout returned as error, map() reflected as object. Project tests pending.
- Independent Tool review task_2638e037258d found five static P2 cases:
  /tmp/opencode/exagent-tool-jsv-review-task_2638e037258d.md. Fix worker reproduced
  them on 0.20 and 0.22, reported 21 isolated Tool tests passing, is still finishing.
  Prefer 0.22 for upstream recursion/regex fixes; use bounded public vocabulary
  corrections for remaining numeric equality/codepoint semantics, enforce nested
  dialects, validate encoded result JSON including duplicate keys, handle inert
  default literals without destroying referenced schemas.
- C4 interface announced: ExAgent.run_child(parent_context_or_state, agent,
  prompt, opts), requires live parent.execution_scope and fixes inherited scope
  after caller opts. Fields root_run_id/parent_run_id/model_request_id; deadline
  absolute monotonic milliseconds; optional max_concurrent_requests;
  estimate_cost arity1/arity2 model-aware. Await final interface and gate.
- MIGRATION.md is a draft informed by consumers; update against actual verified
  code and final C4 interfaces. C6/backend choice and C7 remain unimplemented.

## Historical joint gates and review iterations

- First forced compile needed two external-bitstring-size warning fixes in
  MCP/SSE; coordinator used erlang.split_binary (compatible with older Elixir).
  Forced compile then passed for 69 files with warnings as errors.
- A test-file guard in refute_receive was invalid; replaced with explicit pinned
  patterns. A test fragmentation warning was fixed similarly. Full suite then
  produced 497/516 passes, 19 failures (seed591508): chiefly old error/result/usage
  expectations, added scope monitor count and expected linked startup EXITs.
- Coordinator migrated those assertions without weakening effect/cleanup checks,
  observed OTP29 start_link init-stop EXIT in a minimal external reproduction,
  trapped expected startup exits in tests, and confirmed the 100ms queued-test
  startup passed alone before using a 1s barrier under the parallel suite. Removed
  two pre-existing unused aliases. Affected focal gate: 71 passed (seed854177).
- Full EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors: **516 passed,
  28 excluded**, seed398741. C0 probe now all seven groups true. SSE probe was
  migrated from Async to byte chunks/eof, preserving original two CRLF frames
  and unrelated mailbox message. No paid providers/Postgres were called.
- Canonical synthetic bench before optimization: structured p50 1080us(c1)/1224us(c8),
  effect_failure1043/1278us. This motivated actual cache profiling, not removing checks.
- task_18e4cd834195 / ctx_893494753b05 completed optimization: valid tools prepared
  opportunistically in ExAgent.new, invalid ones still fail as RunError at run.
  29 focal tests pass; controlled same-spike p50 1092->143us structured(c1),
  1472->356us(c8); effect 1038->137 /1440->342us. C0 stays true. Report:
  /tmp/opencode/exagent-tool-cache-profile-report.md. Full post-cache gate pending.
- Final independent reports (read-only; bugs need new regression gates):
  /tmp/opencode/exagent-core-c4-review-task_77c80eaf00ea.md and
  /tmp/opencode/exagent-stream-compaction-review-task_75a2e8364797.md.
  Fixes now assigned above: stale response after after_model_request; loss of
  already published subtree usage on scope death; automatic telemetry/run! model
  leakage; consumed worker DOWN causing delayed cleanup/orphan guardian; Model
  double-closing a failed continuation; compaction equal-value occurrences;
  Event losing safe provider/status/reason diagnostics.
- Shared helper contract confirmed: ExAgent.ErrorProjection.reason/1 and message/1.
  RequestError -> exception String, provider normalized identifier String|nil,
  HTTP status100..599|nil, safe reason categories as strings/lists. No model/body/
  headers/partial in reason projection. Event owns explicit partial wrappers.
  Core owns rich returned RunError and uses safe projection for automatic channels.
- New public regressions were executed against the prior compiled BEAM without
  compiling the source fixes: `mix test --no-compile` for final_review_regression,
  compaction and event_error_projection. Result **25/42, 17 expected failures**,
  seed155080. All reported effect/usage/privacy/cleanup/occurrence/diagnosis defects
  reproduced. The test stream_consumer fixture also assumed done instead of valid
  halted; sent that correction to core owner, not counted as a new runtime defect.
- Fresh verification Task `task_97d0d26d0743` is pending dependency on
  task_7600e92eee6a, now satisfied. Compiled focal green completed and source/docs
  frozen for verification. It will run full test/warnings/probe plus already
  installed Elixir1.18.4-otp-28/Erlang28.0 in isolated MIX_BUILD_PATH. Current native
  toolchain is Elixir1.20.0/OTP29. No Elixir1.17 runtime is installed or verified.
- Post-review green: EXAGENT_OFFLINE=1 MIX_ENV=test mix compile --force
  --warnings-as-errors passed for **70 files**. New final_review_regression,
  compaction and event_error_projection focal gate: **43 passed**, seed686206,
  with warnings as errors. Worker fixture done/halted and monitor barrier corrected.
  Shared ErrorProjection preserves safe categories/status/provider while rich
  RunError stays explicit; scope-loss snapshot cannot decrease previously published
  consumption; effective Response after hook governs tools/output; stream finalizers
  and guardian termination no longer reuse a consumed continuation/DOWN.
- Coordinator updated README/MIGRATION and the Oban documentation recipe to remove
  old replay/stream/Store claims; mix.exs now includes MIGRATION/CHANGELOG in package
  files and MIGRATION in docs extras. Version unchanged. These doc edits do NOT
  authorize compiling before the --no-compile red gate (README is external_resource).

## Recovery / next action

### Final acceptance after dependency closure

- Independent fresh verification: 541 passed/28 excluded on both native
  Elixir1.20/OTP29 and Elixir1.18/OTP28; all 14 C0 invariants true. Reports/logs:
  /tmp/opencode/exagent-independent-verification-task_97d0d26d0743.md,
  /tmp/opencode/exagent-independent-native-task_97d0d26d0743.log,
  /tmp/opencode/exagent-independent-compat118-task_97d0d26d0743.log.
- Docs generation exposed missing extras links and inherited decoder advisories.
  Coordinator added ACTION_PLAN/RESEARCH extras and verified a local regression:
  oversized declared HTTP chunk + only128 actual bytes produced timeout on old
  Mint instead of response-limit error. Required Mint1.10 and HPAX>=1.0.4 in the
  manifest, updated corresponding locks, and test-only Postgrex0.22.4 with
  DBConnection2.10.2. See DESIGN8.5; no unrelated bulk upgrade or runtime SQL.
- Final native forced compile70 + suite: **542 passed/28 excluded**, seed950880.
  The old compatibility build held stale .app metadata; a fresh build directory
  /tmp/opencode/exagent-compat-118-final compiled70 and ran **570 total,0 failures,
  28 excluded =542 passed**, seed580649 on Elixir1.18.4/OTP28. No global configs
  or installed versions were changed. Both gates used warnings-as-errors.
- Five offline examples passed; stateful collector subscription was corrected.
  Documentation generated with warnings-as-errors into /tmp/opencode/exagent-docs.
  Local Hex build succeeded at /tmp/opencode/exagent-consolidation-preview.tar;
  it is a packaging check with unchanged nominal1.2.0, NOT a releasable major or
  a published artifact. Runtime package requirements exclude SQL and doc tools.
  Changed Elixir files and new files passed format checks; git diff --check passed.
- Source HEAD remains c08125be71eada363d08ca463cc7df2ea7855e4a with uncommitted
  implementation/docs/tests. No commit, version bump, Hex publish, deployment or
  consumer modification occurred. Elixir1.17 and real providers/Postgres/consumer
  acceptance remain unverified; C6/C7/C8 are the next units, not active work.

The milestone is complete. To start a further user-authorized unit, verify Run,
mailbox and resource identities again; do not reuse closed terminal handles.

Check Run and fleet before resuming; do not replace active workers by assumption:

```bash
orca orchestration run-show --id run_ab7595996c57 --json
orca orchestration check --run run_ab7595996c57 --wait --timeout-ms 60000 --json
orca orchestration worker-list --run run_ab7595996c57 --json
```

Process each delivered batch before ACK. Reuse completed workers with a new Task
and Dispatch, or release them, respecting user-owned retention. Never record
worker capabilities here. Continue supervision until an advanced verified state,
real blocker or explicit user pause; do not end with workers merely dispatched.
