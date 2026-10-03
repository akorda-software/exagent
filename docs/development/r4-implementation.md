# R4 persistence primitives: implementation and verification boundaries

The data primitives are integrated onto accepted R3.4 and owner-verified offline;
independent integrated review remains pending. The single status table is [roadmap§5](roadmap.md).
This document describes design/oracles, not another status board. R5 owns C7 runtime.

## Inputs and architecture

The isolated implementation used R3 source643ade77; corrected reviewed R4 source
b3498467 is integrated by its exclusive delta onto accepted R3.4 source05a02459.
Historical identities, commands and failures remain in the checkout records
`docs/archive/2026-09-26-r4-persistence.md` and
`docs/archive/2026-09-26-r4-cleanup-reserve.md`. New integration evidence is separate
in `docs/archive/2026-09-26-r4-integration.md`.

Design8.33 in [design decisions](../architecture/design.md) keeps one JSON row with
snapshot, execution identity/references/progress/effect journal and receipts.
Native callback key is `{namespace, kind, id}` from trusted Store.Scope; adapters
reuse RuntimeIdentity. Existing public snapshot/Message/Usage codecs validate
Snapshot1–4, omitted-v1/accounting1/continuation2/envelope1 without a second parser.
Persisted data never selects modules, credentials or permissions.

Closed commands are create/start/claim/checkpoint/begin_effect/outcome/recover/
reconcile/finish/expire/cancel/delete. CAS revision, record lifetime, actor/payload
digest and owner/attempt/fence have separate roles. Old receipts attest past commits,
not renewed IO permits. Start preserves revision/fence and terminal receipt
projections; it does not run anything. After intent, missing outcome means uncertainty
even if a worker died before actual IO. Lease expiry does not permit replay.

Legacy load/save/delete reject envelopes under the same exclusion boundary;
legacy lists omit them. Unintegrated Server restore fails before execution.
Raw unnamed ETS tids remain a concrete snapshots-only consumer with bounded
insert_new/select_replace/select_delete (20 attempts); atomic continuation requires
the actual ordered-table GenServer owner. This compatibility retires only with
explicit retirement/migration of the raw-tid snapshot API.

## Integration oracles

| Boundary | Discriminating verification |
|---|---|
| Public codecs | Legacy1–3 and4 snapshots inside records; future/corrupt/mismatch and nonportable inputs reject without fallback |
| Omission/usage | Record roundtrip retains omitted nil/status/IDs and Usage marker/accounting; diagnostic history rejects before Model/tool IO |
| Identity | Namespace/key/payload kind/id consistency, identical logical IDs isolated, malformed adapter replies fail closed |
| Atomicity | Two barrier-synchronized creators/claimants, one winner; immutable actor/payload-bound retries and stale fence rejection |
| Dirty/ACK | Save before/after-commit failure, exact captured command retry, one counted effect, no callback or effect replay |
| Retention | Encoded8MiB exact/+1,256 effects,1024 receipts; maximal escaped IDs and cleanup, active/uncertain deletion rejection, bounded page errors |
| Retained outputs | Existing core/model/tool/RunStream/Server retention and ACK regressions remain unchanged and are rerun together |
| Distribution | New TAR identity and app-owned SQL DDL; fixed-graph minimum/extensible and SQL opt-in fixtures, no real DB claim |

## Encoded cleanup reservation

Admission reserves receipt slots and encoded bytes using actual run/continuation
IDs plus worst-case512-byte escaped actor/operation IDs, minimal state/outcome
growth, counter horizons and UTC widths. Claimed records reserve recover and close
even without unresolved effects. The proof and migration implications are in
design8.33. It is not the obsolete fixed4224-byte reservation.

UTC milliseconds have domain0..9223372036854775807; revision/fence remain exact.
Bounds cannot evict active evidence or promise arbitrary future outcomes will fit.
Hosts bound/externalize payloads before IO and retain dirty candidates after failures.
Old experimental near-cap backups may need explicit remediation with writers stopped.
No hard predecode RAM bound or per-namespace cardinality quota is implied.

## Remaining runtime and external work

Continuation.Checkpoint is a data-only exact-command retry seam. It does not replace
RuntimeCheckpoint or gate Server/Session queues. R5 owns pause/decision/resume,
trusted definition/configuration/authority restoration, actual budgets/active-time,
approval/frame/batch lifecycle and effects. ETS loses records on owner death.
Postgres transaction/locking/rollback/ACK/restart/backup-restore need authorized G3;
scripted SQL protocol fixtures cannot certify a database. The app owns DDL and
quiescence; deletion removes retained deduplication evidence without eternal history.
