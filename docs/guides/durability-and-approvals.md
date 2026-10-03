# Durability and human approvals

Saving a conversation and resuming a paused execution solve different problems.
Choose the boundary first; then supply the Store and trusted host configuration
that boundary needs.

## Choose what must survive

| Need | Mechanism | Application responsibility |
|---|---|---|
| A later follow-up with the same messages | Serialized history | Save history and retain the model state your adapter needs. |
| A restarted Server or Session | Confirmed snapshot | Supply the trusted agent/policy template and Store. |
| Approval or restart at an admitted execution boundary | C7 continuation record | Supply versioned bindings, authorization, codecs and explicit recovery. |
| An uncertain payment, write or remote request | External reconciliation | Establish the real outcome before deciding what may execute next. |

None of these makes an arbitrary external effect transactional or exactly once.

## Add a conversation checkpoint

```elixir
{:ok, server} = ExAgent.AgentSupervisor.start_agent(
  agent: ExAgent.new(model: "test"),
  agent_id: "docs-checkpoint",
  namespace: "docs-workspace",
  store: :ets
)

{:ok, result} = ExAgent.Server.chat(server, "Hello!")
:ok = ExAgent.Server.checkpoint(server)
result.output
```

ETS is ephemeral: losing its table owner or the VM loses the data. For durable
storage, your application brings `ecto_sql`, `postgrex` and a supervised Repo,
runs `ExAgent.Store.Postgres.migrate(MyApp.Repo)`, then uses
`store: {ExAgent.Store.Postgres, MyApp.Repo}`. See the
[SQL and migration contract](migration.md).

Snapshots contain portable history, usage and metadata. The live model, tools,
credentials and closures come from the trusted template on restart. Strings can
still contain secrets introduced by your application; JSON portability is not
secret detection.

## Handle a failed save

An unconfirmed save returns `ExAgent.CheckpointError`, while the runtime retains
the new state and marks it dirty. Further mutations wait for a confirmed save.
`Server.checkpoint/1` and `Session.checkpoint/1` retry **storage only**. They do
not call the model, tool or state-change function again.

Restore accepts absence as a new conversation, but rejects corrupt, future or
mismatched snapshots. Treat that error as a recovery decision rather than
silently starting empty.

## Use persisted approval

The [job integration recipe](../development/continuation-jobs.md) is the complete
starting point. It runs with TestModel and ETS, so it needs no Oban, database or
credentials:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/continuation_job.exs
```

The demonstrated sequence is:

1. Run a trusted template with a scoped Store and stable execution ID.
2. Pause before a tool that requires approval; its effect has not executed.
3. Read the current record using `ExAgent.Continuation.get/2`.
4. Authenticate the actor and persist the exact decision with `decide/4`.
5. Enqueue a wake-up after the decision commits.
6. Inspect the same record, then resume its approved cursor with the trusted template.

An approval binds the record lifetime, revision, approval ID and payload hash.
The host's `authorize` callback establishes authority; the prompt cannot approve
itself. A decision changes data and does not execute the tool. A duplicate job
reads the existing state: waiting stays waiting, terminal stays terminal, and an
active claim does not become a second attempt.

## Recover uncertainty explicitly

After owner loss, recover the expired claim and reconcile unknown effects using
host evidence. Changing an agent's instructions, tools, policy, mapping or codec
requires an appropriate version/binding change. Reusing an ID under changed code
does not prove the old boundary still authorizes it.

Checkpoint retry tokens authorize the exact data transition only. A storage ACK
does not authorize new model/tool IO. Resume validates current authority and
bindings, and completed steps are data rather than replay instructions.

The accepted SQL profile includes PostgreSQL 17.4, lost ACKs, competing resumers
and restart across VMs. Read [Support status](../status.md) for its scope;
arbitrary cluster failover and external-effect rollback are not qualified.

API: `ExAgent.Store`,
`ExAgent.Continuation`,
`ExAgent.CheckpointError`,
`ExAgent.resume/3`.
