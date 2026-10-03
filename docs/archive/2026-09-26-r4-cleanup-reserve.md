# R4 P2 cleanup reservation correction — isolated owner evidence

This record concerns only the bounded reservation correction in
`/tmp/opencode/exagent-r4-fix`. Independent revalidation, R4 integration/acceptance,
G3 and C7 runtime remain pending. It does not replace the original R4 evidence.

## Inputs, isolation and causal red

- R4 source SHA256 `913e591bc518ad901b1a73bd48e2a8ba8bbc25adc4e0125b1fdf8d3d6d678352`.
- Original R3 baseline SHA256 `643ade7778977655ea2daae26d528b7d192b9d6277a59562e58770e19dfc98b2`.
-270 source files byte-matched R4 before edits. Deps/tooling physically copied,
  without symlinks/hardlinks; own builds/caches, explicit environment and no downloads.
- Before edits: `mix test /tmp/opencode/exagent-r4-review/review_probes_test.exs
  --seed 92626`, exit2. Public ASCII cancel passed; escaped-ID cancel returned
  record_limit after successful create. Full `red-review.log` retained.
- Root and original R4 source hashes captured before edits and rechecked at freeze.
  Initial freeze stopped on root drift: coordinator confirmed concurrent authorized
  R3.4 integration in ten source/test/doc paths and its own ORCA_CHECKPOINT changes;
  two Ruff cache changes have no observed author and are outside the source freeze.
  Before/after hashes are retained, not overwritten or claimed identical. Original
  R4 owner remains byte-identical; worker commands/edits target only its physical
  `/tmp` copy and artifacts, with no source links to root.

## Correction and oracle

Only Record size/cardinality/time validators change at runtime. Reservation now
charges real encoded duplicated execution IDs and maximal escaped operation/actor
IDs, minimal known/unknown outcome marker growth, owner release, revision/fence
decimal growth and the enforced signed64 nonnegative UTC-ms domain. ADR8.33 gives
the monotonic cleanup-step proof and explicit experimental migration limitations.

Public Store regressions cover ASCII/U+0001 IDs, accepted reserved exact cap and
cap+1/no row, checkpoint/begin-effect cap+1 retaining byte-identical previous state,
512-byte escaped owner/attempt identities, cancel/finish/recover→cancel, expiry,
two retained effects through uncertain/reconcile/close, unknown and known outcomes,
1024 receipt saturation without eviction, and terminal encoded8MiB exact/+1.
Additional reducer checks exercise largest supported UTC and revision/fence99→100.
Helpers size candidates but assertions execute public Store transitions and inspect
loaded state; they neither bypass admission nor seed ETS with forged records.

The first new focal run39/41 exit2 exposed two invalid test operation IDs generated
by the existing claim helper (`claim-` plus512-byte attempt). Tests now explicitly
choose a legal claim operation ID. The next focal44/44 seed92626 exited0; this
precedes the final terminal-cap regression and final checks listed below.

## Environment and final verification

Runner `/tmp/opencode/exagent-r4-fix-run.py` preserves explicit child environment,
command, complete output and exit for every invocation under
`/tmp/opencode/exagent-r4-fix-evidence`. Elixir1.20.0/OTP29, `EXAGENT_OFFLINE=1`,
`HEX_OFFLINE=1`, `MIX_ENV=test`, `ERL_FLAGS=+S 8:8`, isolated deps/build/Hex/Rebar.
The unchanged width5 fanout fixtures need this scheduler configuration; evidence
does not establish portability below five schedulers. No paid providers, live
Postgres, Opik, consumer applications, installations or global tooling changes.

Final forced compile79, full offline suite **763 passed /0 failed /28 excluded**
seed37556, format check and ExDoc exited0. Documentation probe9/9 seed0 exited0;
the preceding wrong-path `mix test test/exagent/documentation_snippets_test.exs`
invocation exited1 and is retained, followed by the actual
`mix run test/support/documentation_probe.exs`. The28 excluded tests include22
provider and6 Postgres tests; they were not run. Exact artifact identities and
patch roundtrips are in the external delivery manifest/report; R4/G3 acceptance
is reserved to independent review/coordinator.
