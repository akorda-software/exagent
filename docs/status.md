# Support and release status

Updated **2026-10-02**. These docs describe the unreleased v2 candidate on
`codex/v2-candidate-029`. The nominal version remains **1.3.0**. No v2 version
bump, tag, merge to `main` or Hex publication has been performed.

## What is accepted

| Boundary | Evidence | Scope |
|---|---|---|
| Offline runtime | 2,176 passes / 0 failures / 28 exclusions on both remote runtime targets; the local routine also passes. | TestModel and fixtures, not real-provider compatibility. |
| Runtime targets | Elixir 1.18 / OTP 28 and Elixir 1.20 / OTP 29; strict test compile passes on both. | Tested combinations, not every patch release or dependency graph. |
| Real model | G2: 14/14 cases, 17 requests, 3 effects through stock ReqLLM 1.24, GPT-4o-mini/OpenRouter Chat tools profile. | Other providers, reasoning families and modalities remain subject to their guards. |
| Real consumer | 18 application E2E scenarios accepted, with the initial 13/18 receipt and five causal retries preserved. | The authorized Phoenix consumer, 40 admissions; no observed invoice. |
| Durable recovery | PostgreSQL 17.4, 14 phases: lost COMMIT ACK, competing resumers, fresh-VM resume, explicit recovery and backup/restore. | Declared single-database/host profile, not universal HA or external exactly-once effects. |
| Langfuse and Opik | Each: native transport + API 33/33 observations, 667 attributes, 12 model usages; UI 12 cases / 248 attributes. | Same finite A10 acceptance criteria. Content off; synthetic TestModel tokens. |
| Package consumers | Eight clean graphs across two runtimes, 56 contract checks and 46 commands pass. | Functional acceptance; upstream strict warnings remain red. |
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

## What remains before publication

- Resolve or explicitly decide the strict stock-dependency diagnostic policy
  using compatible upstream releases. Preserve the red diagnostic evidence.
- Finalize versioning, release notes, tag and the separately authorized Hex
  publication pipeline. The current draft PR is not a published v2.
- Qualify any additional provider, modality, deployment or scaling profile before
  claiming support for it. These are future qualification goals, not silently
  implemented guarantees.

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
