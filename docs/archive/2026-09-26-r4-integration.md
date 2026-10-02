# R4 integration onto accepted R3.4 — 2026-09-26

Status: accepted offline on the immutable freeze; post-freeze documentary receipt below.

Coordinator gate_1a7cfef26f1f grants task_e81726b250f6 / ctx_14cb9835a666 exclusive
root/docs/build ownership. ORCA_CHECKPOINT remains coordinator-owned.

## Accepted inputs and reused evidence

- R3.4 source `05a024593553491c86e576535b5093d77ec05ceb4c2725024fdb919aa8e1efbf`,
  `/tmp/opencode/exagent-r34-p2-v2-source.tar.gz`; package
  `8775e6657bea8f427792d7314796401f85b9f468453a7e7cb077a21ef8005176`.
  Root matched all263 frozen files before editing; previous WIP is preserved.
- Independent review task_d3420f865920 closes all four retention P2 findings:
  compile74, unchanged probes6/6 and focal85/85 pass. Owner suite755/0/28 and
  fixed-graph consumer128/0/0 remain reused owner evidence, not new integrated runs.
- R4 corrected source `b3498467c189a77d677955b66fce60af6b5e7c5e34335b428fba62cd945a22e9`;
  cumulative delta `b5052dbba28aa8bf5079d9c656baeb09d09e234fe3f56e7ff7e969d10e374f85`;
  manifest `9c8faaf32dfb545c4ece41edbc97deba98a719e889bc1155c05af4f4ccbf8331`.
  Independent review task_60fd56a7fead closes cleanup P2 on these isolated bytes:
  compile79, focal45/45 and independent admission/cleanup probes3/3. Owner763/0/28
  is isolated evidence, not evidence for the integrated root.
- All four input hashes verified. Delta has22 paths; only docs and
  test/exagent/store_repo_contract_test.exs diverge from its R3 preimage.
  Runtime imports must match corrected R4 exactly; all R3.4-specific runtime
  sources and codecs must remain byte-identical to their accepted freeze.

R3 phase is accepted offline. R4 integration/review, C7/R5, SQLlive/G3 and other
external gates remain open. No clean-resolution G5 is claimed.

## Explicit transfer pause — 2026-09-26

User and coordinator message msg_96e69cfbb69f pause this same incomplete Task;
ownership ROOT/docs/builds remains task_e81726b250f6 / ctx_14cb9835a666. No worker_done,
acceptance or ownership transfer is implied. No worker-started command, test/build,
background process or service remains active. Await explicit resumption by the new
coordinator; do not continue gates or poll while idle. ORCA_CHECKPOINT is untouched.

### Exact work saved

- Imported with apply_patch and byte-compared against corrected R4b349: all eight
  runtime paths (`lib/exagent/continuation.ex`, its checkpoint/record/storage/
  transition helpers, `lib/exagent/store.ex`, store/ets.ex and store/postgres.ex).
- Imported four test files continuation_cleanup/record/store/postgres_contract and
  `test/support/continuation_fixtures.ex`; all five byte-identical to R4b349.
- Manually merged three SQL fixture hunks in `test/exagent/store_repo_contract_test.exs`
  onto R3.4, preserving its Snapshot4 expectation. Result SHA256
  `b5d4cfc45243471566609e89840efbbbc659065708f1a2814c37534341cb77b4`.
- All R3.4 lib/test sources outside the reviewed R4 allowlist were checked byte-equal
  to accepted source05a02459 after import. No core/Model/Message/Usage/Server/
  RunStream/Session/codec/retention changes. mix.exs, lock and CI untouched.
- Registered R3.4/R3 offline acceptance in roadmap/status/changelog/handoff/prompt/
  documentation index/release-scope and this record before runtime imports.
- Merged ADR8.33 after intact ADR8.32, preserving the cleanup proof and migration;
  added R4 changelog and migration sections plus `docs/development/r4-implementation.md`.
  Current guides describe encoded reservation instead of fixed4224. Added app-owned
  `docs/guides/continuation-schema.sql` and both isolated historical R4 records.
  These latest documentation edits have not had format/link/ExDoc gates yet.
- One manual historical transcription needs checking against the input: cleanup
  record prose currently says `/tmp` copy/artifacts where the input says copy and
  artifacts. Restore historical byte identity on resumption, not during this pause.

### New completed executions, not reused evidence

Runner `/tmp/opencode/exagent-r4-integration-run.py`, root cwd, logs and JSON
environment/command/exit under `/tmp/opencode/exagent-r11/r4i-*`. Existing direct
Elixir1.20/OTP29 tooling from environment.md; clean allowlisted child environment,
EXAGENT_OFFLINE=1, HEX_OFFLINE=1, MIX_ENV=test, ERL_FLAGS=+S8:8, explicit root
MIX_BUILD_PATH/MIX_DEPS_PATH (needed by the cold-VM test). No installs/resolution.

| Label | Command/result |
|---|---|
| r4i-compile-01 | `mix compile --force --warnings-as-errors`:80 files, exit0 |
| r4i-focal-01 | `mix test test/exagent/continuation_cleanup_test.exs test/exagent/continuation_record_test.exs test/exagent/continuation_store_test.exs test/exagent/continuation_postgres_contract_test.exs test/exagent/store_repo_contract_test.exs test/exagent/retention_contract_test.exs test/exagent/retention_review_regression_test.exs test/exagent/server/snapshot_test.exs test/exagent/runtime_namespace_test.exs test/exagent/server_checkpoint_contract_test.exs --seed 37556 --warnings-as-errors`:121 passed, exit0 |

No new runtime red was observed. One temporary Python-script apply_patch failed to
match because automatic formatting changed quotes/layout; it made no edit, then
the script was read and patched successfully. No failing test was hidden or retried.
Identity checker `/tmp/opencode/exagent-r4-integration-identity.py` verified imported
runtime/tests and unchanged R3.4 sources; initial run matched all263 baseline files.
The last gate is the121-case focal, not a full integrated suite or distribution gate.

Transfer inventory/delta are saved as `/tmp/opencode/exagent-r4-integration-pause.json`
and `.diff`: exact per-file comparisons against both freezes plus log hashes.
These are pause artifacts, not a final accepted source freeze or Hex TAR.

### Remaining work and next action

1. Read/ack fresh coordinator mail and confirm same ownership/task before resuming.
   Inspect pause inventory and historical-byte discrepancy; no import restart needed.
2. Add bounded integration-specific public oracles for Snapshot1–3/4 inside records,
   omitted ToolReturn nil/status/IDs and Usage marker/accounting roundtrip, no Model/
   tool IO from omitted history, and namespace/kind/logical-ID payload consistency.
   Existing121 focal cases pass but do not by themselves cover every new codec seam.
3. Finish unique roadmap§5 R4.1–R4.6 state rows, current status/handoff/prompt and
   integration matrix/evidence, keeping C7/R5 and all external gates open. Decide
   whether ExDoc needs the new guide indexed; ask before any mix.exs change.
4. Run final focal integration, forced compile, complete offline suite, format,
   snippets, ExDoc, links and planchecker, retaining all logs and failures.
5. Produce new Hex TAR with DDL inclusion, source freeze, exact per-file manifests
   against both accepted inputs; run fresh fixed-graph minimum/extensible consumer
   and existing SQL opt-in fixtures, no dependency resolution or real SQL/G3.
6. Route exact final artifacts via coordinator to waiting independent reviewer
   task_60fd56a7fead / ctx_0b5c45dd5d3a for bounded integrated revalidation; only then
   coordinator acceptance. No delegation, R5 implementation or automatic publication.

## Resumed same Task and integrated owner gates

Coordinator msg_8ad7f75097e2 explicitly lifted the transfer pause; received/ACKed
delivery_70506ad2d97d. Same Run/Task/Dispatch and exclusive root ownership continue.
No imports or R0–3 phases were restarted. Historical transcription was restored
to the reviewed bytes. Three public seam tests were added in
`test/exagent/continuation_retention_integration_test.exs`: record JSON of snapshots
1–4, exact omission nil/status/IDs and Usage marker/accounting, Model dispatch
rejection for omitted history, key namespace/kind/logical-ID and payload mismatch.
They pass3/3 seed37556. Existing R4 runtime bytes remain unchanged from reviewed
b349; no integration runtime bug or alternative codec was introduced.

The coordinator explicitly authorized one ExDoc index line in mix.exs extras:
`docs/development/r4-implementation.md`. This is the sole mix change from accepted
R3.4; version/dependencies/lock/CI remain intact. The guide and app-owned DDL are
already included by existing package globs; no package manifest broadening.

New executions use the same root runner and full JSON/env/exit logs:

| Label | Result |
|---|---|
| r4i-seam-01 | Public integration tests3/3, exit0 |
| r4i-compile-final | Forced compile80, warnings-as-errors, exit0 |
| r4i-suite-final | Full offline803 passed/0 failed/28 excluded, seed37556, exit0 |
| r4i-format-new / r4i-format-final | Format new test then global check, exit0 |
| r4i-snippets | Executable documentation9/9 seed0, exit0 |
| r4i-docs | ExDoc with warnings-as-errors, new guide indexed, exit0 |
| r4i-links |233 local links/53 Markdown, exit0 |
| r4i-plan |57 unique work units/A1–A10/G1–G6, exit0 |

Excluded22 providers/6 PostgreSQL tests were not run. Existing Req synthetic-adapter
deprecation, telemetry informational logs and deliberately interrupted transport
diagnostics remain in complete logs; no project test failed. Schedulers+S8 preserve
the reviewed fixture width5 profile, not portability evidence below five schedulers.
Documentation-only metadata closure follows these runs; runtime is unchanged.

## Distribution and independent handoff

Final package path `/tmp/opencode/exagent-r4-integration-final.tar`, source path
`/tmp/opencode/exagent-r4-integration-source.tar.gz`, manifest
`/tmp/opencode/exagent-r4-integration-manifest.json` and delivery
`/tmp/opencode/exagent-r4-integration-DELIVERY.md` carry exact identities after
the final byte checks. Per-file comparisons against both accepted freezes and
all new/reused evidence are explicit. Source includes tests/records; package omits
them and includes `docs/guides/continuation-schema.sql` and the new current guide.
Those artifact paths are a handoff convention, not evidence until materialized.
Fixed-graph consumers copy existing dependency sources with fresh private builds;
no download, clean dependency resolution, real DB or clean-resolution G5 is implied.
Independent integrated review is required before coordinator acceptance; C7/R5,
SQLlive/G3 and other external release gates remain open.

### Distribution gates completed by owner

Package103 files, SHA256
`ac5447127d90e829185cfeb95d820bdbe0d3d1e1ee51750c8c0882cfd2601386`,
materialized from actual TAR bytes into independent
`/tmp/opencode/exagent-r4-integration-consumer`; fixed root lock/dependency sources
physically copied with fresh build/Rebar paths. `mix deps.compile` and
`mix run graph.exs` exit0; graph excludes SQL, Jido and OTel API/SDK/exporter.
`r4i-consumer-tests-strict`: **186/0/0**, seed37556, warnings-as-errors, exit0.
This includes external custom Model/tool contracts, original runtime/retention,
all45 R4 cases, public seam3 and merged SQL Repo fixtures. No resolution occurred.

Two harness failures are preserved, not presented as product regressions:
`r4i-consumer-tests`185/186 exit3 lacked the test-only TestingAuditRuntime helper;
root's working test imports it from test/support. Supplying its exact bytes restored
the assertion. `r4i-consumer-tests-final`186/186 exit1 then exposed Mix1.20's warning
for helper `.ex` files inside test discovery. Moved both required helpers outside
test/ and adjusted test_helper paths; same test bytes then186/186 strict exit0.
No warning suppression, test weakening or runtime/package edit was used.

SQL opt-in uses a second physical consumer
`/tmp/opencode/exagent-r4-integration-consumer-sql`, same TAR103 bytes and lock,
fresh build, explicit app-level ecto_sql/postgrex dependencies from copied graph.
`r4i-sql-build` exit0; `r4i-sql-probe` compiles an app-owned Ecto.Repo and checks
transaction/query exports, packaged DDL and Store capability without starting Repo
or opening a connection. Versions: EctoSQL3.14.0/Postgrex0.22.4/DBConnection2.10.2.
`r4i-sql-tests`: **15/15**, seed37556, warnings-as-errors, exit0 (SQL protocol9,
merged Repo fixture3 and new seam3). This is SQL opt-in packaging/protocol evidence,
not real locking, durability, backup/restore or G3. No minimum-runtime matrix rerun.

Final documentation rerender, local links/plan/diff and identity checks follow the
metadata closure; no runtime/package source change follows the green suite/consumer.
Independent review receives this exact source/package identity, not the isolated
R4 or old R3.4 identities. Acceptance is reserved to that review/coordinator.

## Post-freeze documentary receipt: R4 accepted offline

Coordinator msg_57de32de8f89 accepts R4.1–R4.6 offline after final independent
review task_60fd56a7fead / ctx_0b5c45dd5d3a, report
`/tmp/opencode/exagent-r4-integrated-review/REVIEW.md`, verdict msg_b32f0cf8abaa.
No concrete P1/P2 remains within the reviewed scope; cleanup P2 and guide P3 closed.

Accepted immutable identities: source279
`cdd2a042387f24e6b29dd83adb1cfae06aad07669c2ee8682302aaa32083f013`, TAR103
`ac5447127d90e829185cfeb95d820bdbe0d3d1e1ee51750c8c0882cfd2601386`, manifest
`1488bbd69be8ae8b872047ecd7a03839b5a29142054919a6393696da6ae3b1f8`.
Independent new checks: forced compile80, focal33/33 seed92626, snippets9/9 seed0,
both delta roundtrips279/279, TAR103/103/checksum/DDL and final identity, all exit0.
Owner803/0/28, minimum/extensible186 and SQLoptin15 remain owner evidence, not
reviewer reruns. Coordinator also verified source279/TAR103 and diff-check exit0.

**This receipt is later prose, not part of the accepted source/TAR/manifest.**
Only roadmap/status/handoff/prompt/this record are updated for receipt; original
delivery and all accepted artifacts remain unchanged. Runtime/tests/config/mix/lock
must match the reviewed freeze. Receipt gates are documentation links/plan/ExDoc
and exact preservation checks, without repeating suite/consumers or building a TAR.
Separate receipt report records their exits and the changed-file hashes.

After this Task's worker_done, ROOT/docs/builds ownership is ceded for a fresh R5
Task authorized by coordinator. R5 owns actual C7 runtime; SQLlive/G3 and external
release gates remain open. No R5 implementation is included in this reception.
