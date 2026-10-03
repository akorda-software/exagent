# Long-lived observability polish — 2026-10-03

User authorizes further known-limit polish. Baseline
`6402e4a65f1fa9589d5cb4f6eeb349f0792d07fb`; official ReqLLM1.26 only.
Owner implements and verifies the functional delta; no new independent R9 review,
consumer modification, paid call, cloud, SQL or publication work.

## Implemented contracts

- `ReqLLM.Maintenance` is an optional singleton GenServer child, explicitly
  supervised by the host. TTL/cadence are required; invalid/duplicate/unknown
  options reject. Timer references prevent stale-message scans. Scans do not
  overlap, counters are numeric/generation-local, and absent integration stays
  dormant without installing handlers or an SDK. Stop/restart preserves tracing.
- Only the integrated handler is pruned through ReqLLM's public API. TTL must
  exceed every allowed live request, including standalone/stream/retries. Age
  pruning does not prove death, finish spans or bound overall upstream RAM/table.
- BoundedProcessor adds `max_exporter_restarts`, retaining infinity default.
  Finite exhaustion disables admission, discards pending spans and leaves the
  manager alive/unavailable. Additive numeric counters record replacements and
  exhaustion. Normal completed error callbacks do not spend the budget. SDK/
  app/VM restart resets the per-instance budget; no durable circuit is claimed.

Design/alternatives/migration: [design](../../architecture/design.md#operación-prolongada-de-observabilidad-2026-10-03).
Host setup/limits: [guide](../../guides/observability.md),
[known limits](../../development/known-limits.md).

## Tests and preserved failures

| Wave | Result | Scope |
|---|---|---|
| maintenance-red | 0/3, exit2 | Child/API absent; original red retained |
| maintenance-green-01 | 3/3, exit0 | Configuration, dormant/no-SDK start, supervision, singleton, stale timer, stop |
| bridge-focal-01 | 25/27, exit2 | Two new fixture assumptions fail, retained below |
| bridge-focal-02 | 27/27, exit0 | Corrected public event/cleanup oracle;24 bridge +3 maintenance |
| restart-budget-red | 16/19, exit2 | New option rejected before implementation |
| restart-budget-green-01 | 24/24, exit0 |19 processor +5 native OTLP, includes the new one-profile control |
| integrated120 | 94/94, exit0,32.720s | Full observability directory, strict, seed1032026 |
| integrated118 | 94/94, exit0,36.979s | Same cases and92 library sources, private1.18/OTP28 build |
| candidate-integrated120 | 94/94, exit0,31.273s | Isolated baseline plus owned changes |
| candidate-integrated118 | 94/94, exit0,36.379s | Same isolated92 library sources on1.18/OTP28 |
| candidate-doc-probe | 18/18, exit0,3.270s | Actual selected documentation snippets |

The first live-request oracle assumed ReqLLM's metadata-only synchronous event
exports response ID; it does not. Use the public start/stop request ID plus native
Model ID/usage instead. The first streaming orphan oracle assumed all8 kills
require pruning; transport exception events can clear some automatically.
The corrected test waits for a completed maintenance pass after TTL and requires
public zero-TTL prune to return0. It does not credit natural cleanup to this child.

Each surface has two waves of8 killed owners and two healthy requests:32 owner
deaths and4 healthy loopback requests overall, no paid requests/tools/effects.
All64 cancelled native run/model spans close. Healthy total request deadline1000ms
is below TTL2000ms; two maintenance passes preserve pending public request ID,
then completion has exactly one generation/2 fixture tokens. Foreign-handler
tracking remains until its own public prune. Stopping maintenance keeps the bridge.

Restart budgets0/1 prove exact timeouts, queued discard, no replay, no further init,
manager survival, dropped admission and final stats. Idle worker kill spends the
same budget, while a completed failed callback remains ready. Native budget0 uses
real exporter1.11: one profile/one held POST, one timeout, three later drops,
zero replacements. The socket survives; VM-owned public cancellation/removal
returns sockets/profiles to baseline. Unlimited native negative controls remain.

## Parallel work and installed consumer results

During the first integration runs, a separate request-adapter change appeared;
later unrelated Session/state-codec work also appeared in the shared tree. Preserve
all of it, exclude it from this objective and do not format/commit it. The first
root format check rejects only the parallel OpenRouter files; retained verbatim.
Qualification uses a physical baseline archive plus owned files, private sources/
builds, and confirms92 identical library files across both runtimes. The child
moduledoc correction has identical executable AST; parallel adapter differences
justify the new isolated94-case runs rather than relabelling mixed-source runs.

Staging TAR SHA256:
`0c05e7ebd4145b54fc91126d76cb30271549d5c65e58a5c01bf1151db63d02e1`.
Four cold1.20 none/API/SDK/exporter graphs execute8 exact cases each, zero failures/
excluded/skipped. The new case verifies a dormant maintenance child without
implicit apps/handlers; SDK/exporter exercise finite budget0 in their real routes.

The first runner still expected seven cases and labels all32 runtime results
not-passed despite their successful raw ExUnit records. Fix the independent
manifest to include the eighth contract; its new regression rejects missing,
duplicate, failed and excluded cases. Red3/4 then green4/4 retained. Re-evaluate
the same32 raw records with that corrected exact-name/module/state manifest:
all pass. No new dependency download/compilation/test replay is needed to correct
this inspection. Original summary/logs remain; stock strict warnings stay red.

The complete offline routine runs on the unchanged isolated library freeze.
Its tooling-validator update is tested separately; final source/artifact comparison
distinguishes that correction from unchanged framework code.

## Upstream inspection and remaining scope

Fresh official Hex queries confirm exporter1.11/API1.5/experimental0.6. Main HTTP
sources still derive profiles from PIDs and do not shut them down in the HTTP
exporter callback. No compatible public ownership/cancellation fix adopted.

Stock ReqLLM expects get_meter/3 and histogram.record/4. Published experimental
API0.6 exports get_meter/1–2 and record/5. Its API TAR checksum is
`8a4d5902034e95a1eda09575c4e9902245f16dac1c08c7b0cc0b1f7c593ce56a`;
experimental SDK TAR is
`01483c4dfc46044e8f2f3955a5d372765fd3e2584a9ad05ac81a8e495029919e`.
Inspection only, not installed/overridden. No metric export/reader acceptance.

Private logs/manifests/official-source checksums:
`.exagent-local/maintenance20261003/`. Native response/error logs and synthetic
transport-closure logs are expected fixture evidence, not compiler warnings.
Provider guards, core execution/accounting, snapshots, lock and credentials are
unchanged. Prior cloud/SQL/paid/FULL receipts retain their identities; the new
94-case integrated run does not relabel them as a full new candidate wave.

## Complete local routine and final source boundary

The isolated1.20/OTP29 `./bin/check` finishes with exit0 in2,035.684 seconds.
Its complete offline suite passes **2,208 cases /0 failures /28 exclusions** in
1,995.2 seconds (26.9s async/1,968.2s sync), seed37556. All nine phases exit0:
whitespace, staged whitespace, format, strict finite harness, suite, strict
ExDoc, local links, package build and package isolation. The FULL manifest has
438 tracked runtime/test/tooling inputs;92 are library files. The separately
added package-oracle regression is not folded into this FULL count.

The routine builds the exact staging TAR above and verifies120 HTML pages /
5,381 targets,118 Markdown entries /885 targets and118 EPUB pages /2,981 targets,
with no missing local targets. These counts belong to the routine's doc freeze;
final prose/link checks retain their own result below. No complete1.18 suite,
new paid request or external backend acceptance follows from this routine.

Parallel Dragonex work later also adds sections to shared design/changelog/
roadmap files. Preserve those sections in the working tree; construct the owned
documentation/commit separately so unsupported contracts are not included without
their implementation. Adapter, Session, migration/stream tests and their new
files stay outside this source/artifact qualification and commit. This boundary
does not assess or revoke the other owner's independent receipts.

Final docs/package/source verification is recorded below.

## Final documentation, package and tooling correction

Final format/whitespace, four package-oracle regressions, strict ExDoc and local
links pass. Links retain120 HTML /5,381 targets,118 Markdown /885 targets and
118 EPUB /2,981 targets, zero errors. The guide explicitly warns that an unbounded
live request has no safe finite TTL; configure deadlines before maintenance.

The first final isolation run fails because its synthetic diagnostic replay still
writes total7 for an eight-case manifest. Its clean replay is correctly rejected
as `runtime acceptance failed: consumer ExUnit totals`; the first failure/log and
generated evidence remain. Update only that synthetic total to8. The corrected
isolation run passes in22.495s, preserving strict warning rejection in all seven
diagnostic phases, project/tooling/symlink guards and the unchanged fake host.
It does not execute or certify another consumer runtime wave.

Final nominal1.3.0 TAR SHA256:
`1a5db9207553f438a1fd6d6f1d5457cfcc2c1e3553ee9348e65132ef4a603346`.
All171 files match the isolated candidate. Compared with prior documentary TAR
`1669807e28007c99691d3f760d6a7a5713e82a256cc23094ff9c9ff24dd0fddc`, only the new
Maintenance library file is added; the only other library delta is BoundedProcessor.
Package metadata is identical except the file list; Mix AST is identical excluding
docs/0. Version, dependency ranges/lock, snapshots and provider guards retain their
contracts. All92 library files match the FULL and both94-case integration freezes.

Of438 tracked runtime/test/tooling inputs, three change after FULL: the package
manifest, its separately qualified four-case regression, and the corrected
synthetic isolation total. All other inputs retain their bytes. Five packaged
files change after staging: four documentation pages and the separately tested
manifest tooling. The final TAR is not the staging32-contract artifact; runtime
identity makes that functional evidence reusable without relabelling its SHA.

The owned commit has22 files, excluding parallel Dragonex code/tests/migration
and their portions of shared design/changelog/roadmap. Working-tree content is
preserved; source comparison checks the committed selection, not a clean shared
tree. No new external acceptance, R9 review, version/tag/merge or Hex publication.
