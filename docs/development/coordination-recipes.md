# Durable coordination recipes

`examples/coordination_workflows.exs` contains three deterministic recipes:
Ecto-validated extraction, a host router selecting one specialist, and an
extraction→publish sequence with human approval before publishing.

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix run --no-start examples/coordination_workflows.exs --run
```

The script uses TestModel and its own ephemeral ETS scope, without provider keys,
network services or a database. Adapt its trusted definitions to your application.

## Select one specialist

The host supplies a versioned selector. The selected branch executes; unselected
branches do not. Branch descriptors bind trusted agent, policy, model and output
references plus a host model codec. Version a reference when its meaning changes.
Portable binding data cannot reconstruct a live agent or authenticate an actor.

## Persist extraction before approval

The sequence persists JSON text, validates it with the Ecto changeset in a
versioned input mapper and returns `{:ok, input}` for the publishing agent.
The mapper runs before the pause; resume uses the saved input and completed
extraction rather than executing them again.

Compile application Jason encoders when persisting custom schema structs, or
persist explicitly portable data as this standalone recipe does.
`Continuation.decide/4` binds the authenticated actor's decision to the record
ID/revision, approval ID and payload hash. Application authentication and its
decision endpoint remain host responsibilities.

## Choose durability and bounds

ETS provides atomic transitions inside one VM; its data disappears with its
table owner or VM. For durable recovery supply `Store.Postgres`, your Repo and
database lifecycle. Changed definitions, uncertain effects and recovery retain
the same explicit continuation contracts.

Flow bounds branch/concurrency and portable branch/merge results separately.
Journal or history admission can still reject a definition that fits individual
branch limits. See [Coordination](../guides/coordination.md) for supported forms
and [Framework integrations](framework-integrations.md) for LiveView/job delivery.
