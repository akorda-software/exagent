# R4 isolated owner evidence — 2026-09-26

Status: primitives implemented and owner-verified offline in an isolated physical
copy, **not accepted or integrated**. Root belongs to R3.4. ADR8.33 and the exact
matrix are in `docs/development/r4-implementation.md`; snapshot codecs from baseline
R3 remain in this copy. R3.4 omission/version integration and independent review
are the next gate. G3 SQL real is BLOCKED without destination/schema/permissions.

## Source and scope

Baseline `/tmp/opencode/exagent-r3-source.tar.gz` SHA256
`643ade7778977655ea2daae26d528b7d192b9d6277a59562e58770e19dfc98b2`.
Design proposal `/tmp/opencode/exagent-r4-design/PLAN.md` SHA256
`a889baff88bc34a051328bbae74a8f42a58adaae1538a32ea81fedeabfcb03cc`.
258 source files matched before edits; deps/tooling were physically copied with
no symlinks/hardlinks. No root writes, dependency resolution/install, live Model,
DB/backend/service, global configuration, consumer app, version or Git publication.

Exclusive implementation files: Store, Store.ETS, Store.Postgres,
Continuation and its Record/Transition/Storage/Checkpoint helpers; three new test
files, one fixture module, and the existing SQL protocol test adjusted for guarded
quoted SQL. Documentation: design8.33, changelog, roadmap proposal row, migration
guide/SQL template, implementation matrix and this evidence record. Immutable
Server/Session/run/RunStream/Message/RuntimeIdentity/accounting, mix/lock/CI remain
byte-identical to baseline. The exact manifest and unified diff accompany the source
snapshot; integration must apply that delta, never overwrite root with this older
R3 snapshot.

## Reproducible tooling and commands

Runner `/tmp/opencode/exagent-r4-run.py` uses a clean explicit child environment,
not an inherited credential-bearing environment. Every log begins with full cwd,
environment and argv, and ends with exit status. Seed37556 unless noted.

```text
cwd=/tmp/opencode/exagent-r4-implementation
PATH=/home/kukapu/.local/share/mise/installs/erlang/29/bin:/home/kukapu/.local/share/mise/installs/elixir/1.20.0/bin:/usr/bin:/bin
HOME=MIX_HOME=<cwd>/.tooling
MIX_ARCHIVES=<cwd>/.tooling/native-archives
HEX_HOME=<cwd>/.tooling/hex
REBAR_CACHE_DIR=<cwd>/.tooling/rebar
REBAR_GLOBAL_CONFIG_DIR=<cwd>/.tooling/rebar-config
MIX_DEPS_PATH=<cwd>/deps
MIX_BUILD_PATH=<cwd>/_build/test
EXAGENT_OFFLINE=1 MIX_ENV=test HEX_OFFLINE=1 LANG=C.UTF-8
ERL_FLAGS=+S 8:8
```

Initial runs used +S4:4; the reason for the final scheduler setting is preserved
below. Runtime preflight observed Elixir1.20.0/OTP29 and private paths. Docs use
MIX_ENV=dev and their own `_build/dev`, physically copied from this copy's test
build before compiling the existing offline ExDoc dependency graph.

| Gate / log | Actual command (runner prefix omitted) | Result |
|---|---|---|
| compile-final-3.log | `mix compile --force --warnings-as-errors` | 79 sources, exit0 |
| focal-final.log | `mix test test/exagent/continuation_record_test.exs test/exagent/continuation_store_test.exs test/exagent/continuation_postgres_contract_test.exs test/exagent/store_repo_contract_test.exs test/exagent/store_test.exs test/exagent/server_checkpoint_contract_test.exs test/exagent/session_persistence_test.exs test/exagent/session_cold_restore_test.exs test/exagent/runtime_namespace_test.exs --seed 37556 --warnings-as-errors` | 79/0 exit0 before final raw-tid/SQL-delete additions; final full suite covers both |
| ets-compat-fix.log | `mix test test/exagent/continuation_store_test.exs test/exagent/framework_evals_test.exs --seed 37556 --warnings-as-errors` | 18/0 exit0 |
| sql-delete-race-green.log | `mix test test/exagent/continuation_postgres_contract_test.exs --seed 37556 --warnings-as-errors` | 9/0 exit0; protocol fixture only |
| suite-final-3.log | `mix test --seed 37556 --warnings-as-errors` | **754 passed, 0 failed, 28 excluded**, exit0 |
| format-freeze.log | `mix format --check-formatted` | exit0 after final source fix |
| snippets-final.log | `elixir -pa '/tmp/opencode/exagent-r4-implementation/_build/test/lib/*/ebin' test/support/documentation_probe.exs` | 9/0, seed0, exit0 |
| docs-freeze.log | `mix docs --warnings-as-errors --output /tmp/opencode/exagent-r4-evidence/docs` | exit0 after final docs/source fix |
| links-freeze.log | `/usr/bin/python3 /tmp/opencode/exagent-r4-doc-check.py` | 227 local links /50 Markdown, exit0 |

Excluded tests remain22 providers +6 Postgres; no excluded test is counted as a
pass. Existing Req runtime deprecation diagnostics remain in full logs. Initial
ExDoc dependency compilation emitted Makeup/ExDoc upstream warnings, separately
from successful project compilation/documentation. No upstream tests were run.
No new installed consumer/dependency graph was required: mix/deps unchanged;
existing framework evals and cold-VM codec probe exercise affected consumers.

## Failure history (not erased by final green)

- compile-r4-1 exit1: inline `defp ..., do: case ... do` parsed as defp/3. Converted
  to a block function; compile-r4-2 exit1 then identified separated reduce/4 clauses.
  Grouped clauses; no runtime behavior was claimed before compile succeeded.
- focal-r4-1:18 passed but exit1 due one unused test alias, removed by using Record
  in the subsequent fresh-VM gate. No warning suppression.
- focal-r4-2:26/27, exit2. SQL create checked deadline before unique INSERT could
  wait. Fixture injected UTC1000→1010 against deadline1010: old code confirmed;
  new code rechecks UTC after owning the inserted row and rolls back expired data.
- suite-final:747/752,5 failures,28 excluded, exit2. Two framework evals exposed
  old raw unnamed ETS handles without a GenServer; initial serialized legacy save
  returned noproc. Corrected by retaining guarded CAS snapshots-only support and
  refusing continuation capability on unmanaged tables; focal18 then passed.
- The other three suite failures were nested-fanout launch barriers. The isolated
  diagnostic reproduced3 failures with +S4; fixtures generate width5 while existing
  Task.async_stream uses its scheduler-count default. Only the runner changed to
  +S8; the same Scope tests passed without edits or timeout relaxation. Scope/core
  were readonly throughout. suite-final-2 then753/0/28 exit0.
  This is not a Scope fix or portability evidence below five schedulers. R8 should
  make the fixture's intended concurrency explicit; integration owner runs the
  usual main environment. That follow-up is outside this isolated R4 task.
- Self-review found absent-row legacy DELETE lacked a write predicate despite its
  earlier SELECT FOR UPDATE. sql-delete-race-red:8/9 exit2 requires protection
  against a record created between those statements. Added predicate at DELETE
  plus locked refusal re-read; green9/9, then final754/0/28. This is SQL protocol
  evidence, not real database isolation proof.
- The first documentation-link checker launch used unversioned `python`, absent
  from the deliberately clean runtime PATH; no checker process started and the
  runner exited1. The initial links-final.log contains its argv/environment only.
  The checker was rerun with `/usr/bin/python3`; future launcher exceptions are
  also captured with a trailing exit in the runner rather than lost on stderr.

## Demonstrated boundaries and remaining work

- Two barrier-released ETS creators/claimants: one commit, one conflict. Managed
  owner waits consume UTC deadline. Scalar snapshot revision cannot go backwards.
- Operation identity binds key/lifetime/expected revision/actor/payload; repeated
  ACK lookup returns original receipt with current record. Same ID/different data
  conflicts. Start maintains increasing fence and rejects stale old-execution writes.
- Killed workers before/after externally counted effect leave intent uncertain;
  expired lease cannot claim again until demonstrated reconciliation. Dirty
  persistence faults before/after commit retry only Store with one external effect.
- Genuine legacy snapshot bytes stay unchanged/readable; future/corrupt/mismatch/
  nonportable/duplicate-key records fail. Old runtime restore refuses an envelope
  before run admission. Session/agent and tenant identities remain distinct.
- Encoded8MiB/256effects/1024receipts, minimal cleanup reservation, terminal guarded
  delete/prune and bounded physical-row pages; errors are not empty scan success.
  Host owns namespace cardinality quotas and external payload-size planning.
- Fresh VM reads a synthetic disk JSON fixture and reconstructs uncertain data
  without a live owner. Disk is test-only, not a product Store. ETS owner death
  demonstrably loses data. Neither result certifies SQL durability or C7 runtime.
- SQL real locking/rollback, disconnect/ACK, new VM/backup/restore require G3.
  Authorization, config/template resolution, actual Scope rehydration/active-time
  debiting, paused/approval/frame/batch lifecycle, effects and runtime queue gates
  remain R5. No R4 phase acceptance is claimed by this owner.
