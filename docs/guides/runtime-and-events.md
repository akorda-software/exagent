# Runtime, streaming and events

Use `ExAgent.Server` when a conversation needs a supervised owner. It preserves
history, threads a stateful model across turns, accumulates usage and emits
events. A one-shot `ExAgent.run/3` remains useful inside scripts and jobs.

## Start a conversation

```elixir
{:ok, server} = ExAgent.AgentSupervisor.start_agent(
  agent: ExAgent.new(model: "test", instructions: "Be concise."),
  agent_id: "docs-conversation",
  namespace: "docs-workspace",
  pubsub: :local,
  max_pending: 2
)

{:ok, first} = ExAgent.Server.chat(server, "Hello!")
{:ok, second} = ExAgent.Server.chat(server, "Continue.")
%{first: first.output, second: second.output}
```

The application chooses a stable ID and obtains the namespace from authenticated
application state. Do not derive authority from model text or convert arbitrary
tenant names to atoms. `chat/3` is synchronous and returns `{:error, :busy}` while
another run is active.

## Subscribe before asynchronous admission

```elixir
alias ExAgent.{Event, PubSub, Server}

pubsub = PubSub.normalize(:local)
topic = Event.agent_topic("docs-conversation", "docs-workspace")
:ok = PubSub.subscribe(pubsub, topic)
{:ok, request_id} = Server.send_message(server, "Continue asynchronously.")

receive do
  {:exagent_event, %Event{namespace: "docs-workspace",
    request_id: ^request_id, type: :run_finished, payload: payload}} ->
    payload.output
after
  2000 -> {:error, :event_not_observed}
end
```

Match the namespace and request ID for the authenticated screen or job. Handle
`run_failed` and `server_request_cancelled` as well as `run_finished` in production.
The snippet shows the success path with a local Test model; its two-second wait
is an example receive timeout, not a provider deadline.

`send_message/3` acknowledges **volatile queue admission**, not completed work.
It admits up to `max_pending` queued requests, then returns
`{:error, :queue_full}`. PubSub events are not a durable queue: reconnect using
`Server.history/1`, `Server.health/1` or confirmed Store data.

For Phoenix, use `{ExAgent.PubSub.Phoenix, MyApp.PubSub}` after your application
starts that PubSub. [Framework recipes](../development/framework-integrations.md)
show the authenticated host boundary for LiveView and Oban.

## Stream a one-shot run

```elixir
agent = ExAgent.new(model: %ExAgent.Models.Test{label: "Hello from Elixir"})

events = ExAgent.run_stream(agent, "Hello!") |> Enum.to_list()
{:result, result} = List.last(events)
result.output
# => "Hello from Elixir"
```

The stream emits `{:delta, text}`, then `{:result, result}` or `{:error, error}`.
Deltas can span tool and corrective-output requests; they are provisional until
the final validated result. Enumerate once: a second enumeration starts a new
run. Halting closes owned resources; a suspended stream continuation must be
resumed or halted by its owner.

## Cancel and checkpoint

`Server.abort/1` cancels in-flight work and is idempotent. It does not reverse a
tool effect. With a Store configured, a failed save retains the new state in
memory and blocks further mutations. Retry `Server.checkpoint/1` to save that
state, rather than submitting the prompt again.

[Durability and approvals](durability-and-approvals.md) explains the difference
between conversation snapshots and resumable execution.

API: `ExAgent.Server`,
`ExAgent.Event`, `ExAgent.PubSub`,
`ExAgent.run_stream/3`.
