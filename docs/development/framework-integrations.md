# Phoenix, LiveView and Oban integrations

Use the packaged recipes in `examples/continuation_integrations/` to present
conversation events, persist authenticated approval and wake a resumable run from
a queue. Phoenix and Oban are application dependencies; ExAgent does not start
their endpoint, Repo, tables or queues.

## Wire the application

Copy `live_view.ex`, `oban_worker.ex` and `job_dispatch.ex` into your application's
compilation paths. They define example macros and dispatch code, not modules
installed in ExAgent's runtime. The recipes use Phoenix 1.8, LiveView 1.2,
Phoenix.PubSub 2.3 and Oban 2.24 APIs.

```elixir
defmodule MyAppWeb.ContinuationLive do
  use ExAgent.Examples.ContinuationLive, host: MyApp.ContinuationHost
end

defmodule MyApp.Workers.Continuation do
  use ExAgent.Examples.ContinuationWorker, host: MyApp.ContinuationHost
end
```

Add these children alongside your application's Repo and endpoint:

```elixir
children = [
  {Phoenix.PubSub, name: MyApp.PubSub},
  {Oban, repo: MyApp.Repo, queues: [continuations: 4]}
]
```

Configure your Server with `pubsub: {ExAgent.PubSub.Phoenix, MyApp.PubSub}`, an
authenticated namespace, trusted agent and scoped Store/continuation settings.
Run your Repo, ExAgent Store and Oban migrations before admitting durable work.
Resolve executable configuration in trusted host code, never from browser/job JSON.

## Implement the host module

`MyApp.ContinuationHost` supplies the following functions:

| Function | Responsibility and return |
|---|---|
| `open(session)` | Authenticate and authorize the conversation. Return `{:ok, %{actor: authenticated_context, reference: opaque_host_reference}}` or an error. |
| `live_target(context, action)` | Reauthorize `:view`, `:stream`, `:decision` or `:resume`. Resolve server, namespace, agent ID and PubSub; execution also supplies trusted prompt and options. Return `{:ok, target}` or an error. |
| `authorize(context, actor, decision, requested)` | Enforce current authority over the exact persisted request. Return `{:ok, bounded_actor_id}` or an error; passed to `Server.decide/3`. |
| `present_history(history)` | Produce authorized, redacted text from `Server.history/1`. |
| `present_approval(approval)` | Present the tool and arguments while preserving the bound payload hash. |
| `job_target(reference)` | Authorize the service principal and resolve trusted agent, prompt, continuation and options for the opaque reference. Return `{:ok, target}` or an error. |

Bind references to the authenticated tenant/owner. A queue reference selects work;
it is not an authorization credential. The queue service principal and human
decision actor can have different permissions.

## LiveView events and reconnect

The recipe subscribes after an authorized connected mount. Private socket state
holds the actor and trusted target. Render assigns hold presented history,
status, bounded correlation/approval identifiers and provisional text.
The browser cannot choose a module, template or executable run option.

`Server.stream/3` acknowledges admission with `{:ok, request_id}`. Match event
version, namespace, agent ID, emitter, request ID and increasing sequence before
updating the screen. Ignore duplicate and foreign attempts. Restrict access to
the PubSub bus; sequence numbers are not a durable cursor or peer authentication.

Mount/refresh query `Server.history/1`, `health/1` and `continuation/1`.
Reconnect can recover current state even when notifications were lost. A restarted
Server has a new emitter; the host resolves it under the same trusted identity.
Mount and refresh do not resume work automatically.

## Approval and resume

An approval event carries the exact record ID, revision, approval ID, payload
hash and per-view operation ID. The host authorizer and persisted compare-and-swap
validate those values against the current pending request. Keep the operation ID
stable while displaying that revision. A stale or lost reply requires refresh.

Approve only persists a decision. Resume is a separate authorized action using
`Server.resume/2` through LiveView `start_async/3`. Refresh on completion.
Closing a view ends its caller task; Server still owns admitted work.
Use `Server.abort/1` for explicit cancellation and reconcile uncertain effects.

## Queue delivery

The worker accepts exactly `%{"reference" => binary_reference}` and calls the
shared `ContinuationJob.dispatch/4`. New work runs; pending work waits; approved
work resumes its cursor; terminal duplicates return existing data.

Pending/terminal/success returns `:ok`. Enqueue a wake-up after approval commits;
a pending `:ok` neither polls nor grants execution. Errors, an active attempt or
uncertainty return `{:cancel, reason}`. The example uses `max_attempts: 1` so an
operator resolves the condition before inserting/retrying another delivery.

Job uniqueness can help queue admission; the persisted continuation controls the
execution cursor. A queue/Store transaction cannot make an arbitrary external
effect transactional or exactly once. Follow [Continuation jobs](continuation-jobs.md)
and [Durability](../guides/durability-and-approvals.md) for recovery.

API: `ExAgent.Server`, `ExAgent.Event`, `ExAgent.Continuation`.
