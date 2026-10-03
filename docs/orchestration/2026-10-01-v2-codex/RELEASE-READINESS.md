# Final documentation/code/test alignment — 2026-10-03

Owner pass requested by the user after the instrumentation implementation.
Baseline: `9701d58b56fb9d7f9c597411b957e1819552bd85`. This is not another
independent R9 review, a new complete suite or permission to publish.

## Findings corrected

| Finding | Demonstration and correction |
|---|---|
| TestModel claimed default fallback after exhausting a nonempty script | Public requests return a failure after the scripted response; only an initially empty script uses label/default. Correct module/guide docs, keep runtime unchanged. |
| Script callback type claimed a single message | The public request path passes a message list. Correct the two-argument type and describe that input. |
| Tests page and current status mixed older counts/runtime waves | Identify the latest 1.20 FULL, earlier two-runtime baseline and later focal runs separately. Date historical counts; exclusions remain 22 provider and six PostgreSQL cases. |
| README said backend acceptance was pending | Langfuse and Opik already have equal finite native/API/UI acceptance. Retain the distinction from the new bridge's local-only attributes. |
| README API references led to published 1.x | Use candidate API autolinks in generated docs; published-package badges remain clearly external. |
| Scope/SQL template still claimed C7 and external gates were pending | Align current state with implementation and receipts; G5 strict stock diagnostics remain open. Historical ADRs remain dated evidence. |
| G2 runner limits could be read as framework-wide capabilities | Distinguish that runner's selected profiles from the broader consumer E2E matrix. Add a boundary/check/evidence table and integrated tracing entry for agents. |
| README omitted opt-in MCP HTTP | Reference the existing HTTP1 Finch recipe, protocol profile and separate SDK acceptance. |

## Verification and evidence identity

- Fresh critical check on baseline: **146 pass / zero failures**, 29.6 seconds,
  seed1032026, offline. Observability and ReqLLM admission/stream/accounting/host
  boundaries; no model-provider calls. This precedes the documentation edits.
- Strict compilation and actual Markdown-snippet probe after the corrections:
  **18 cases pass on each Elixir1.20/OTP29 and Elixir1.18/OTP28**. The new failure
  example proves two model requests, exactly one confirmed tool effect, failed
  status and the retained successful ToolReturn. It does not add a runtime mode.
- TestModel executable AST and six runtime BEAM chunks (Code/StrT/ImpT/ExpT/FunT/LitT)
  match the baseline. All other library function sources, manifest, lock and
  runtime config are unchanged; only TestModel documentation/type metadata differ.
  The earlier **2198/0/28 FULL1.20** and **146 integrated cases per runtime** keep
  their original source identity in [OBSERVABILITY-COMBINATION](OBSERVABILITY-COMBINATION.md).
- Root format check passes. Final site/package readback is recorded below.
  No complete runtime or paid/SQL/cloud
  acceptance is rerun for this documentation-only execution delta.

Private commands/logs live in `.exagent-local/release-readiness20261003/`.
The first reproduction had a stimulus syntax error; the first chunk-inspection
helper matched the wrong Erlang return tuple after proving AST equality. Both
failures remain recorded; corrected helper runs pass without changing ExAgent.

## Final site and package

Strict ExDoc passes. Local readback finds **118 HTML pages /5275 targets,
116 Markdown pages /852 targets and116 EPUB pages /2918 targets**, with zero
missing local pages, anchors or resources. The README and agent-map API targets
resolve to candidate pages; neither contains published1.x API destinations.
The first API inspection selected the short README-derived module page instead
of the full `readme.html` extra; checking the actual extra resolves every target.

The probe selects **43 blocks**:32 local execution/resolution blocks and11
syntax-only external setup blocks, within18 cases per runtime. This is explicit
selection, not a claim that every historical snippet or external setup ran.

Final nominal1.3.0 TAR:
`4eff85d9dd412751a257b434e3c70d0c5ebf9d9503d7dc2cb8b8d0ad0af8164f`,
**169 files**,851456 bytes. All file bytes equal the aligned checkout; metadata
and membership equal the prior TAR
`13f8cc9175625642159db1391fe0d2de65ae0bdb54e9a4eb16035674bc3ace3c`.
Of92 library/Mix files,91 are byte-identical; the remaining TestModel source has
only the documented metadata/type changes with executable AST/chunks equal.
Ten packaged files differ: README, changelog, scope, roadmap, verification,
agent map, SQL template, testing guide, status and TestModel. The new receipt
and CURRENT remain outside the package. Isolation controls pass; no new clean
consumer matrix is inferred from this documentation-only TAR.

The previous four clean graphs/28 contracts and two-runtime/full-suite evidence
remain in the combination receipt with their original hashes and qualification
scope. Site/package phases exit0:docs3.607s, links0.309s, build0.432s,
isolation22.228s. No new cloud, invoice, metrics, deployment or live-model result.

## Remaining limits and release status

The accepted profiles have no new runtime finding from this pass. This does not
prove all possible inputs, providers or deployments. Stock TOML/WebSockex/gproc
strict diagnostic evidence remains red; functional clean-consumer contracts pass.
DeepSeek native receipt case08 remains unqualified, while its other26 scenarios
are accepted. Current tracing API/SDK has no metrics-export acceptance, and cloud
receipts use synthetic TestModel usage with content capture off.

Version remains **1.3.0**, draft PR1; no bump/tag/merge/Hex publication. Publication
requires the release decision and authenticated publish credentials. Private
`hex.user whoami` reports no authenticated account; no key was created or read.
The public Hex package check still reports1.2.0, independently of this checkout.
