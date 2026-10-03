# Jobs with persisted approvals

[continuation_job.exs](https://github.com/akorda-software/exagent/blob/main/examples/continuation_job.exs) is a runnable,
deterministic recipe using public continuation APIs. A queue attempt loads the
record first: a pending approval waits, an approved/ready record resumes its exact
cursor, and a terminal record returns data without starting another run. A claimed
attempt remains busy; uncertainty requires explicit host recovery/reconciliation.
The demo uses ephemeral ETS and synthetic effects; PostgreSQL durability and an
actual Oban worker remain separate consumer qualification.

```bash
EXAGENT_OFFLINE=1 mix run examples/continuation_job.exs
```

The trusted app supplies the template, scoped Store, stable run ID, versioned
definition/policy/model references, codecs and credentials. Job arguments carry
only the application's identifier. Tenant/actor authorization is resolved from
authenticated app state; a prompt, job payload or notification cannot approve a
tool. Persist decisions with `ExAgent.Continuation.decide/4`, including the exact
record lifetime, revision, approval ID and payload hash. Enqueue a wake-up only
after the decision commits. A duplicate wake-up inspects the same durable record.

For Oban, the app's `perform/1` calls the recipe's `dispatch/4`. A terminal result
or `:await_approval` completes that queue attempt. The app can schedule a later
wake-up for `:attempt_in_progress`; `:host_recovery_required` enters its recovery
flow. A checkpoint error retries only its captured data transition through
`Continuation.retry_checkpoint/2`; its receipt cannot authorize another effect.
Do not convert every RunError into a fresh `ExAgent.run/3`. Oban uniqueness is
useful queue admission and does not replace the continuation's CAS boundary.

The library owns neither Oban nor the app's tables, authentication, jobs or
database lifecycle. Replace the demo ETS store with the app-owned PostgreSQL Repo
and `durability: :durable` after running the real SQL profile. A changed template
must change its version/reference, and resumes still validate current tool,
authority, Model and output bindings. The recipe does not provide transactional
external effects or exactly-once delivery.
