# Support and release status

Updated **2026-10-03**. These docs describe the unreleased v2 candidate on
`codex/v2-candidate-029`. The nominal version remains **1.3.0**. No v2 version
bump, tag, merge to `main` or Hex publication has been performed.

## What is accepted

| Boundary | Evidence | Scope |
|---|---|---|
| Offline runtime | Updated dependencies, October 3: both complete suites have 2,177 passes / zero failures / 28 exclusions. | Preserve the previous ReqLLM-only 1.18 failure below. TestModel and fixtures, not real-provider compatibility. |
| Runtime targets | Elixir 1.18 / OTP 28 and Elixir 1.20 / OTP 29; strict test compile passes on both. | Tested combinations, not every patch release or dependency graph. |
| Real model | Updated dependencies: 12 scenarios pass initially; length sync/stream pass after correcting the stimulus. All 14 scenarios covered, 18 admissions / 3 effects. | Original refusal/stop failure retained; not a single new 14/14 wave. GPT-4o-mini/OpenRouter Chat tools profile only. |
| Real consumer | October 3: 23 smoke scenarios plus four combined SQL/application workflows. Combined receipts accept Luna 27/27 and DeepSeek 26/27; native receipt extraction remains red. New complex scenarios pass 4/4 per model, with 46 requests / 15 synthetic effects each. Consumer precommit: 17 offline passes / 27 opt-in exclusions. | OpenRouter Chat, reasoning disabled. Complex ledgers: 70/53 admissions including causal controls, USD1.75/1.325 reserved; prior smoke ledgers remain 51/54. Invoice unobserved. Marker failures retained; not a single new 27-case wave or universal provider qualification. |
| Durable recovery | October 3 PostgreSQL 17.4: 14 phases, including lost COMMIT ACK, competing resumers, fresh-VM resume, explicit recovery and backup/restore; cleanup confirmed. | Declared single-database/host profile, not universal HA or external exactly-once effects. |
| Langfuse and Opik | Each: prior native/API 33/33 observations, 667 attributes, 12 model usages; UI 12 cases / 248 attributes. Exporter 1.11 booleans newly verified locally. | Same finite A10 criteria. No fresh cloud/API/UI wave. Content off; synthetic TestModel tokens. |
| Package consumers | October 3 updated dependencies: eight clean graphs across two runtimes, 56 contract checks and 46 commands pass. | Functional acceptance; upstream strict warnings remain red. |
| Integrations | Official MCP SDK 2.2.0: five profiles; LiveViewTest/Oban SQL: six cases plus crash/recovery. | Qualified recipes, not every deployment combination. |
| Load and cleanup | Finite TestModel load/soak/saturation and owned-resource cleanup. | No LLM latency SLO, cloud availability or upstream predecode RAM guarantee. |

The critical review's one P1/four P2 findings were corrected and verified.
The single final R9 integration/distribution review is closed. No known
unresolved finding from those scoped reviews is being hidden by this summary.

## Read the CI result accurately

[Compatibility run03](https://github.com/akorda-software/exagent/actions/runs/37019949320)
tested commit `f69aedea1a2f7c94c546fa95b631a71664110b4d`.
Both complete suites passed with warnings-as-errors:
**2,176 passes, zero failures, 28 exclusions per runtime**. Package and finite
harness checks passed, as did all functional consumer contracts.

The **overall run is failure**, because strict dependency diagnostics report
stock TOML/WebSockex/gproc warnings. There are no ExAgent compiler warnings in
those accepted checks. G5 strict diagnostics remain open; there is no suppression,
fork or forced unsupported upgrade.

The local `bin/check` routine subsequently passed all eight phases. It took
**33m44s**, including a 1,979.7-second suite, almost entirely synchronous work.
This does not demonstrate a 20× local speedup. New documentation checks are
recorded separately; they do not relabel an old TAR or test receipt as new evidence.

## Dependency review — October 3

All 43 locked Hex packages were checked against official stable releases.
Eleven are updated; 42 are current. Gproc remains at 1.2 because stock grpcbox
requires `~> 1.2.0`, excluding 1.3. No unsupported override is introduced.
The [dependency record](development/dependencies.md) lists every version,
compatibility change and official source. `hex.audit` reports no retired packages
or advisories for this lock at the time of the query.

The new local routine passes all nine phases in 2,073.45 seconds. The complete
1.20 and 1.18 suites pass in 2,007.4 and 2,024.7 seconds respectively. Compile
checks report no ExAgent warnings. The previous failed 1.18 receipt remains below;
these new runs qualify the updated dependency graph independently.
Fresh G2 covers all fourteen scenarios with the initial failure retained and two
causal length controls; PostgreSQL and all eight clean package graphs also pass
their functional checks. Strict upstream diagnostics remain open.

The subsequent [application model comparison](development/real-consumer-e2e.md)
uses GPT-6-Luna and DeepSeek V4.1 Flash instead of Mini, with five additional
negative/lifecycle/composed-approval scenarios. Luna's initial 23/23 wave passes;
affected exact-marker controls also pass. DeepSeek's 22 accepted scenarios span
several finite waves; native JSON receipt output still has missing merchant and
currency despite schema validation. Its native extraction profile remains
unqualified. No private parser, coercion, guard relaxation or model fallback is
used to convert that failure to a pass. The library runtime and root lock are
unchanged by this comparison; the earlier G2 Mini receipt remains historical.

Four additional combined workflows now exercise six typed stages, two levels of
delegation, failure collection, lost effect ACK with explicit uncertain recovery,
and a complete application journey across fresh VMs and a PostgreSQL restart.
The last combines memory, shared state/turns, cancellation, parallel delegation,
two approvals, finalization and PubSub streaming. All four pass offline and with
both real models. An initial DeepSeek Session-marker failure is retained; a
clearer ASCII-copy instruction passes the unchanged oracle in both profiles.
Owned processes and databases close; confirmed work is not replayed. These
receipts extend the application matrix without rerunning unrelated qualifications.

## ReqLLM 1.26 qualification — October 2 receipt

The candidate requires ReqLLM 1.26.0 and its llm_db 2026.9.8 catalogue. The fresh
local routine passes all nine phases, including the complete 1.20 suite, ExDoc,
link readback, TAR and isolation. Fresh G2, application E2E, PostgreSQL and clean
consumer results are listed above. Historical 1.24 receipts retain their identity.

The 1.18 integrated run executes all 2,205 cases: 2,176 pass, one fails and 28 are
excluded. The failure is a 100 ms tool-readiness assertion before owner-death
cancellation, using TestModel. A controlled 150 ms startup reproduces it; the
existing 1,000 ms readiness barrier used by neighbouring ownership tests passes.
The cancellation assertion and runtime remain unchanged. All 12 ownership cases
plus that slow-start control pass on both runtimes; the original full-suite failure
is retained, with no claim of a second green full run.

Argument, accounting, continuation and capability guards remain in place. Stock
Anthropic now preserves redacted provider blocks; ExAgent rejects their unqualified
continuation explicitly. Cache reads/writes remain separate without double-counting
inclusive input or reasoning. This update does not expand supported profiles.
Langfuse/Opik retain their previous native/API/UI qualification; their SDK,
exporter and ExAgent bridge are unchanged, with local tests exercised by this run.

## What remains before publication

- Resolve or explicitly decide the strict stock-dependency diagnostic policy
  using compatible upstream releases. Preserve the red diagnostic evidence.
- Finalize versioning, release notes, tag and the separately authorized Hex
  publication pipeline. The current draft PR is not a published v2.
- Qualify any additional provider, modality, deployment or scaling profile before
  claiming support for it. These are future qualification goals, not silently
  implemented guarantees.

The October 3 [instrumentation ownership implementation](development/backend-evaluation.md#reqllm-and-exagent-instrumentation-ownership)
keeps ExAgent as generation owner during its observed Model requests. The
host opt-in `ExAgent.Observability.ReqLLM.attach/1` uses ReqLLM's public adapter to
enrich that span and preserve standalone tracing. Incompatible/duplicate bridges
reject before provider IO in the ExAgent ReqLLM adapter; no foreign handler is
removed. Twenty-one bridge cases within 146 integrated cases pass on both
Elixir 1.18/OTP 28 and 1.20/OTP 29 with identical runtime sources,
including concurrency, sampling/named tracer, once-only pricing, raw-capture
privacy and owner death/public prune. The complete local 1.20 routine passes all
nine phases: 2,198 offline tests pass, zero fail and 28 opt-in cases are excluded.
Four clean package graphs pass 28 contracts; strict dependency diagnostics remain
red for stock TOML/WebSockex/gproc. No new cloud/UI or metrics export acceptance
is inferred; equal prior Langfuse/Opik A10 evidence remains. See the
[combination receipt](https://github.com/akorda-software/exagent/blob/codex/v2-candidate-029/docs/orchestration/2026-10-01-v2-codex/OBSERVABILITY-COMBINATION.md).

Routine verification now runs locally before commit/push. The candidate branch's
six-job CI workflow is manual; `main` adopts that change when the PR is integrated.
The [verification guide](development/verification.md) describes `bin/check`,
its optional package consumers and focused documentation checks.

## Exclusions and observations

The 28 offline exclusions are **22 real-provider tests and six PostgreSQL tests**.
Their bodies did not run; exclusions are not passes or timeouts. Real-provider and
SQL acceptance above come from separate explicit profiles.

Langfuse/Opik preview Input `null` and Output `undefined` are expected with
content capture disabled. Inspect IDs/parentage, status, request/tool counters,
usage quality/provenance and estimated cents in attributes. Neither export ACKs,
API readback nor UI visibility proves durable retention, invoice accuracy or
browser/cloud reliability.

## Source of detail

- [Roadmap](development/roadmap.md): the current R0–R9 board and evidence boundaries.
- [Release scope](development/release-scope.md) and
  [production acceptance](development/production-acceptance.md): promised profiles and oracles.
- [Consumer E2E](development/real-consumer-e2e.md) and
  [backend acceptance](development/backend-evaluation.md): exact external profiles.
- [Execution policy](development/execution-flow.md): at most one independent review per objective.
- Historical status is preserved under
  `docs/archive/2026-10-02-status-history.md` in the checkout. The
  [original dated record](https://github.com/akorda-software/exagent/blob/70c4a0c9d4b3f69805f24def7e61def5b0f5ab08/docs/status.md)
  retains its original paths and results. Historical pending labels do not reopen
  accepted work.

Receipts and private tooling remain outside the consumer package. Read task guides
to integrate the library; read these evidence records when evaluating support.
