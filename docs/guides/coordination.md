# Coordinate agents

Choose coordination according to the state and ownership you need. Adding more
agents does not require a fixed researcher, worker and reviewer pipeline.

| Pattern | Public entry | Use when |
|---|---|---|
| A helper exposed as a parent tool | `Coordination.delegation_tool/2` | The parent decides when to call a specialist. |
| Several participants taking turns | `Session` and a `TurnPolicy` | Shared state needs one writer and explicit turn ownership. |
| A resumable sequence | `Coordination.Composition` | Completed steps must survive a pause or restart. |
| A selected branch or bounded parallel branches | `Coordination.Flow` | The host needs explicit routing or bounded fan-out. |

Composition and Flow are experimental host-defined contracts in this candidate;
their accepted profiles remain bounded. They do not imply a general distributed
workflow engine.

## Delegate inside the parent's scope

```elixir
alias ExAgent.Message.Part.ToolCall

helper = ExAgent.new(model: %ExAgent.Models.Test{label: "A concise summary."})
delegate = ExAgent.Coordination.delegation_tool(helper, name: "summarize")

model = %ExAgent.Models.Test{
  script: [
    {:tool_calls, [
      %ToolCall{tool_name: "summarize", tool_call_id: "summary-1",
        args: %{"prompt" => "Summarize this note."}}
    ]},
    "Summary received."
  ]
}

parent = ExAgent.new(model: model, tools: [delegate])
{:ok, result} = ExAgent.run(parent, "Summarize my note.")
result.output
# => "Summary received."
```

The helper inherits ancestor permissions and limits. Its reported work is part
of the parent's inclusive totals. For a custom auxiliary call, use
`ExAgent.run_child/4` with the current `RunContext`; an unrelated `ExAgent.run/3`
does not establish that parent scope.

## Give shared state one writer

```elixir
alias ExAgent.Session
alias ExAgent.Session.Participant

{:ok, session} = Session.start_link(
  shared_state: %{notes: []},
  participants: [
    Participant.new(id: "writer", kind: :agent),
    Participant.new(id: "editor", kind: :human)
  ],
  policy: {:initiative, order: ["writer", "editor"]}
)

{:ok, "writer"} = Session.start(session)
{:ok, state, "editor"} = Session.take_turn(session, "writer", fn current ->
  {:ok, %{current | notes: ["Draft ready" | current.notes]}}
end)
state.notes
# => ["Draft ready"]
```

Session owns mutations. Tools use a `Session.SharedState` handle through
`RunContext.deps` to read or propose changes through its API. A human participant
is an application-controlled turn, not an automated agent with a human label.

## Add durable orchestration

Start from the [coordination recipes](../development/coordination-recipes.md)
and runnable `examples/coordination_workflows.exs`. They show versioned trusted
definitions, input mappings, output bindings and continuation configuration.
`Composition.run/3` requires a continuation Writer configuration; construction
does not execute callbacks or recover configuration from serialized data.

Flow uses a host selector for routing or a flat set of bounded parallel branches.
Its `:collect` and `:fail_fast` policies have explicit outcomes; fail-fast cannot
undo effects that a sibling already completed. Current limits include at most
32 branches/concurrent workers, independent 64 KiB branch/merge JSON bounds and
an 8 MiB journal. [R6 contracts](../development/r6-implementation.md) explain the
accepted combinations and guards.

API: `ExAgent.Coordination`,
`ExAgent.Session`,
`ExAgent.Coordination.Composition`,
`ExAgent.Coordination.Flow`.
