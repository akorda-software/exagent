# Long-term memory

A run only knows its conversation history. `ExAgent.Memory` gives an agent a
small set of text files that survives across runs and sessions (and restarts and
nodes, with the Postgres backend): the agent reads it when it starts and records
preferences, decisions and progress for the next session.

## Give an agent memory

Memory belongs to a **scope** that your application chooses, usually one per
user, team or project. Never derive the scope from model input.

```elixir
tool = ExAgent.Memory.tool(:ets, scope: fn ctx -> "user:" <> ctx.deps.user_id end)

agent = ExAgent.new(model: model, tools: [tool])
ExAgent.run(agent, "I'm vegetarian. Suggest a dinner.", deps: %{user_id: "42"})
```

The tool keeps files under `/memories` and uses the commands of Anthropic's
memory tool: `view`, `create`, `str_replace`, `insert`, `delete` and `rename`.
It is an ordinary function tool, so it works with any provider. Its description
tells the agent to view its memory first, record durable facts, keep the files
concise and treat them as notes rather than instructions.

A command the agent gets wrong, such as a missing file or an ambiguous
`str_replace`, returns text that starts with `Error:` so the agent can correct
the call; it does not fail the run. Neither does an unavailable backend: the
agent continues without memory and telemetry reports it. Edits from one model
response run one at a time, in order.

## Start with the memory already loaded

Viewing memory costs one or two model round trips per session. To skip them,
render the scope into the instructions:

```elixir
{:ok, notes} = ExAgent.Memory.preload(:ets, "user:42", max_bytes: 8_000)
agent = ExAgent.new(model: model, instructions: base_instructions <> "\n\n" <> notes, tools: [tool])
```

Whole files are included while they fit; the rest are listed by path. File text
cannot close the `<memory>` frame, but preloaded text still reaches the system
prompt, so preload only scopes whose content you trust as much as the agent
itself.

## Store memory durably

`:ets` (the default `ExAgent.Memory.ETS` table) lives in the node's memory. For
memory that survives restarts and is shared between nodes, use PostgreSQL through
your application's repo:

```elixir
:ok = ExAgent.Memory.Postgres.migrate(MyApp.Repo)
tool = ExAgent.Memory.tool({ExAgent.Memory.Postgres, MyApp.Repo}, scope: "team:7")
```

Every command loads the scope, applies the change and stores it only if nobody
changed it meanwhile, retrying on conflict, so agents sharing a scope do not lose
each other's edits. To use another store, implement the two callbacks of
`ExAgent.Memory` (`load/2` and `store/4`, plus an optional `validate/1` that
checks the config when the tool is built).

## Keep memory safe and small

- Limits apply per scope: by default 32 KB per file and 128 KB in at most 100
  files. A write past a limit asks the agent to condense or delete content.
- `read_only: true` offers only `view`, for agents that must not write.
- Memory persists what the model wrote, possibly after reading untrusted tool
  output. Keep scopes narrow and inspect or reset them with `files/2`,
  `update/3` and `clear/2`.
- Memory edits happen outside the run: a failed run does not undo them.
