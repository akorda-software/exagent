# Native PostgreSQL qualification

This opt-in runner creates a new native PostgreSQL cluster, with TCP disabled and
a private Unix socket, and uses real `Store.Postgres`, transactions and runtime
continuations. It never connects to a default database or uses `.env` credentials.
Ordinary offline tests do not select the probe.

```bash
python3 test/support/postgres_acceptance/run.py --list
python3 test/support/postgres_acceptance/run.py --execute \
  --project /absolute/path/to/physical-isolated-checkout \
  --pg-bin /absolute/path/to/postgresql/bin
# Focused network-fault delta with its primitive bootstrap:
python3 test/support/postgres_acceptance/run.py --execute --network-ack-only \
  --project /absolute/path/to/physical-isolated-checkout \
  --pg-bin /absolute/path/to/postgresql/bin
# Separate public resumers, actual SQL request/effect observations:
python3 test/support/postgres_acceptance/run.py --execute --resumers-only \
  --project /absolute/path/to/physical-isolated-checkout \
  --pg-bin /absolute/path/to/postgresql/bin
# Flow A8 with a failed branch and delegated approvals across fresh VMs:
python3 test/support/postgres_acceptance/run.py --execute --flow-only \
  --project /absolute/path/to/physical-isolated-checkout \
  --pg-bin /absolute/path/to/postgresql/bin
```

The project must contain current probe bytes, physically isolated dependencies
and a private build. Prepare isolated Mix/Hex/Rebar using
[environment.md](../../../docs/development/environment.md). A separate finite
300s bootstrap compiles with warnings as errors before starting PostgreSQL. All
runtime phases use `--no-compile` against that private build; their 45s VM guard
remains independent of cold compilation. The runner requires `psql`, configures
the owned server's `statement_timeout` to 5s and records `SHOW statement_timeout`
before any phase. The runner does not install tools,
fetch dependencies, repair global tooling or own another task's sources/build.

Phases check real concurrent create/claim winners, receipt replay after an
intentionally discarded committed ACK and an actual TCP connection loss after
the server's COMMIT, stale revisions, legacy mutation guards,
a suppressing DELETE trigger with rollback, runtime pause in one VM and approved
resume in a second after a database restart, abrupt VM exit after a real tool
effect, explicit recovery with uncertainty and no replay, and backup/restore of
identical record bytes and effects. Source/phase commands, statuses and log hashes
are retained in a new `exagent-pg-*` artifact directory. Database files are private
synthetic artifacts; the runner stops its own cluster and preserves the dump/logs.
Its command wrapper kills and reaps its registered process group when an
interrupted wait or timeout occurs. Cleanup records the cluster and each owned
child's observed exit; this does not promise atomic registration against every
possible host/process failure. PostgreSQL restart logs can keep growing after
`pg_ctl` returns because the daemon inherits stdout; a final log seal distinguishes
those bytes from the command-return prefix hash.

The database itself still disables TCP. The runner owns a temporary loopback
proxy that forwards to its own private Unix socket, observes PostgreSQL's
`CommandComplete(COMMIT)` and closes the caller's connection before forwarding
that reply. The first call is unconfirmed; direct SQL proves revision1 exists,
and replaying the same public Store command returns its receipt without changing
the record or running a Model/tool. The proxy forwards Postgrex's separate
CancelRequests during cleanup, records no query/credentials, admits at most8
connections with262,144-byte protocol frames and has a30s lifetime/finite cleanup.
It is a fault fixture, not a production proxy or predecode memory guarantee.

The resumer race uses a second database in this same owned cluster. A real pause
and bound host approval precede a ready barrier for two new VMs; both call public
`ExAgent.resume` with the same reference. Exactly one succeeds. SQL records actual
Model callbacks and tool effects outside those VMs, proving2 total Model calls
and1 effect including the pre-pause request. The other caller returns an error;
the final record is valid/completed. The main backup database remains separate.

The Flow A8 profile uses a third owned database and the public Flow runtime.
Branch A has a confirmed failure after its effect; B delegates D with two asks;
C completes. The pending Frame11 record preserves the failed branch and releases
its owner. After a database restart, a fresh VM approves both exact payloads and
resumes with replacement callbacks/codecs that raise if A/B/D's confirmed work is
replayed. Ordered output preserves failed/completed/completed, exact requests
increase4→6 while logical tool attempts remain6, and actual tool effects3→5.
A completed reference is data only. The main backup covers its own database;
it does not silently claim backup acceptance of the separate race/Flow DBs.

This is a finite declared profile, not universal G3 acceptance. It does not yet
check RLS, HA, SERIALIZABLE, physical host loss or
transactional external effects. The original discarded-return control remains
explicitly synthetic; the new network phase has its own evidence. Passing checkout bytes does not qualify
the final package. Record the exact server/runtime/source/package identity and
remaining scenarios before accepting a candidate.

On 2026-10-01 the seven declared phases passed on a private physical source
freeze, PostgreSQL17.4/READ COMMITTED, Elixir1.20/OTP29. The crash phase returned
its required exit73; all other phase receipts passed, and the cluster stopped.
Receipt `/tmp/exagent-pg-q9qa49pf/report.json`, SHA256
`1dea02289a80b5456cbf24549173a682ddf96706a0a5b3ac5142da4b9323cad6`, identifies
92 source files, the unchanged lock, commands and four restored records/two
effects. Source manifest SHA256
`65f8bcfb62afe8334e0ff67abaa7e2f94fd6b9c9f68566ce48275a46c7c1956e`.
The executed private probe is retained there; the checkout probe subsequently
received formatting only. Earlier failures in VM-home setup, fixture binding,
missing configuration field and receipt/data filename collision remain in the
preceding `exagent-pg-*` receipts. None required a product Store change or global
tool repair. Candidate qualification must execute the final probe/package bytes.

Objective013's network delta and primitive bootstrap passed on2026-10-01 with
cleanup confirmed: `/tmp/exagent-pg-jwtg8lzq/report.json`, SHA256
`7c158fbfc3d8673e0bd0c37a6281c4aa5465b897620235f5b51e1fb57930beb8`.
The proxy observed one committed operation, forwarded no first COMMIT reply,
closed4 connections including2 cancellation requests and reported no errors.
This reuses the earlier physical core source (manifest above), not the evolving
Flow11 or final candidate. A preceding control exposed unsupported CancelRequest
frames; its receipt is retained, and forwarding those frames plus checking the
final closed-proxy error list has a causal regression. The seven old phases were
not repeated for this delta. The expanded fourteen-phase candidate run is pending.

The separate-resumer delta passed with confirmed cleanup on2026-10-01:
`/tmp/exagent-pg-hvimwsu5/report.json`, SHA256
`44335a58a3d460e77bbefd8a1b23b06e742aab19c270dd8d7b5d26c0ccf841e2`.
Both concurrent commands exited0 and observations show exactly1 winner,2 actual
requests and1 effect. A preceding fixture incorrectly expected public `:ready`
instead of `:approved`; the red receipt remains intact. The fixture now uses the
documented public status and groups its function clauses without warnings.
This is the same earlier core freeze, not Flow11/final TAR; no product Store change
was needed. The full candidate profile remains pending.

The focused Flow profile's primitive bootstrap and two A8 phases passed on
2026-10-01: `/tmp/exagent-pg-w44o318e/report.json`, SHA256
`9e80921c6e4edadb0f039798074df42ee5676de1a059fd6592fa87e96a6d50db`.
All selected commands exited0 and cluster cleanup is confirmed. This uses the
physical pre-review-fix Flow11 freeze plus the official Mint1.10.2 patch, not
the final package. Source and fixture hashes retain that distinction; the
Flow owner's later deadline/draining fixes still need candidate evidence.
