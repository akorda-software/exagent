# Generic coordination recipes

`examples/coordination_workflows.exs` ships three deterministic public API recipes:
an Ecto-validated extraction, a trusted host router selecting one specialist, and
an extraction→publish sequence with human review before the publish effect.

```sh
EXAGENT_OFFLINE=1 MIX_ENV=test mix run --no-start examples/coordination_workflows.exs --run
```

Run it in a disposable consumer VM. It uses the stock Test model and its own ETS
owner/namespace, without keys, network services or a database. The script checks
the selected output and actual callback/effect counters. The unselected specialist
never runs. Guest approval is rejected; approved resume restores the model cursor,
reuses the completed extraction and publishes exactly once. Reading the completed
reference again executes no Model/tool/input mapping callback.

The router uses a versioned selector supplied by trusted host code. It does not
ask a model to invent definitions or authorize a tool. Every branch descriptor
includes agent/policy/model/output references and a host model codec; version them
when their meaning changes. Portable binding data cannot reconstruct those live
agents or authenticate the supplied actor.

The first recipe returns a validated Ecto struct. The sequence persists JSON
text, validates that confirmed text with the same Ecto changeset in its versioned
input mapper, and supplies a bounded JSON object to the publishing agent. The
mapper returns `{:ok, input}` under the public composition contract. The
mapper runs once before pause; resume uses the saved input. Application schema
structs need a Jason encoder compiled with the application to be persisted as
JSON; this standalone script uses portable data without altering consolidated
protocols. `Continuation.decide` binds the authenticated host actor's decision
to the record identity/revision, approval ID and payload hash. The fixture actor
is deliberately a host callback example; application authentication and the
decision endpoint remain the application's responsibility.

ETS provides atomic in-process transitions and JSON roundtrip, with ephemeral
durability. It cannot prove recovery after VM loss. An application needing that
guarantee supplies its own Repo and `Store.Postgres`; migration, ambiguous external
effects and explicit recovery keep the same continuation contracts. See the
[framework integrations](framework-integrations.md) for LiveView/Oban delivery
and the declared SQL qualification in [verification](verification.md).

Flow bounds branches/concurrency and portable branch/merge results independently.
Queue/history/journal admission can still reject a definition that fits those
individual limits; a recipe does not remove the existing shared authority/budget
or promise arbitrary fan-out/delegation depth. The demonstration passes on the
common candidate019 (2026-10-02): typed extraction, exactly one selected
specialist, authenticated human review, one mapper/publish effect and inert
completed reads. Its source is included in the single review of the new R6 delta.
The source and receipt hashes are recorded in the [roadmap](roadmap.md); this
ETS recipe remains separate from the real SQL/VM qualification.
