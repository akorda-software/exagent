# ExAgent

[![Hex Version](https://img.shields.io/hexpm/v/exagent.svg)](https://hex.pm/packages/exagent)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/exagent)
[![License](https://img.shields.io/hexpm/l/exagent.svg)](https://github.com/akorda-software/exagent/blob/main/LICENSE)
[![CI](https://github.com/akorda-software/exagent/actions/workflows/ci.yml/badge.svg)](https://github.com/akorda-software/exagent/actions/workflows/ci.yml)

<!-- MDOC -->

> **Unreleased consolidation major:** these source docs describe the current
> development checkout, not the published 1.x package. Use a local path dependency
> to try it, and read the [migration guide](docs/guides/migration.md) before upgrading a consumer.

**An agent framework for Elixir** — structured output, tool-calling, streaming,
stateful agents, multi-agent sessions and durable persistence, powered by the
BEAM.

ExAgent is **layered and opt-in**: use just the one-shot core, or stack on the
stateful runtime, persistence and coordination as you need them. It is built the
Elixir way — recursion, behaviours, Ecto changesets, cheap concurrency for tools,
supervision/durability, `:telemetry`, and events that plug straight into LiveView.

```
Layer 3  ExAgent.Session          coordinated multi-agent turns + shared state
Layer 2  ExAgent.Store            snapshots: resume after crash / restart
Layer 1  ExAgent.Server           a supervised, stateful, event-emitting agent
Layer 0  ExAgent.run/3            the one-shot model ⇄ tools loop
         ────────────────────────  events (ExAgent.Event) over ExAgent.PubSub
```

## Features

- **One-shot agentic loop** — a model ⇄ tools recursion built as idiomatic Elixir.
- **Type-derived tool schemas** — define tools as plain functions; JSON Schema is
  generated from `name :: Type` annotations and `@doc` strings (no hand-written schemas).
- **Structured output** — any Ecto `embedded_schema` becomes the output spec; JSON
  Schema is derived from the schema **and** its changeset validations, validated
  with retry-on-failure.
- **Streaming** — a lazy, demand-driven view of the same tool/output loop,
  with provisional deltas and one complete result or partial failure.
- **Supervised stateful agents** — keep history, accumulate usage, thread stateful
  models across runs, and emit versioned events over PubSub (LiveView-ready).
- **Opt-in checkpoints** — confirm complete state through a Store and restore a
  conversation on restart. ETS is in-process; Postgres uses your DB/repo. This
  does not replay or roll back arbitrary in-flight effects.
- **Multi-agent sessions** — coordinated turns over shared state with pluggable
  turn policies (`round_robin`, `initiative`, or your own).
- **Orchestration** — scoped delegation with ancestor budgets/permissions and
  hand-off between session participants.
- **Robustness & safety** — context compaction, usage/cost limits, and per-tool
  permissions (`allow` / `ask` / `deny`).
- **Model-agnostic** — OpenAI, OpenRouter, OpenCode Zen/Go, Anthropic and Z.AI; bring your
  own by implementing the `ExAgent.Model` behaviour.
- **External tools (MCP)** — consume stdio Model Context Protocol tools with
  caller-owned timeouts, pending limits and transport cleanup.
- **Observable** — `:telemetry`, app-level `ExAgent.Event` envelopes and opt-in
  native OpenTelemetry with content disabled by default.
- **Offline-first testing** — a deterministic [`ExAgent.Models.Test`] model drives the
  full loop with no API key and no network.

## Requirements

- Elixir 1.17+
- Erlang/OTP 25+

Package-consumer contracts have been verified on Elixir 1.17.3 / OTP 27.3.4.17.
See [project status](docs/status.md) for tested runtime/dependency combinations
and the remaining acceptance gates; the declared floors are not an exhaustive matrix.

## Installation

For this unreleased checkout, point your application at the source directory
(adjust the path to your clone). The published 1.x package has older contracts.

```elixir
def deps do
  [{:exagent, path: "../exAgent"}]
end
```

The library starts its own supervised `ExAgent.Finch` HTTP pool, a `Registry`
(`ExAgent.PubSub.Local`), a `Task.Supervisor`, an `ExAgent.Store.ETS` table and
an `ExAgent.AgentSupervisor`, so it works out of the box. Tune the Finch pool
with:

```elixir
config :exagent, :finch_pools, %{:default => [size: 32]}
```

> `ExAgent` does not shadow OTP's `Agent` unless you alias it as `Agent`.

## Quick start

The fastest way to try ExAgent is with [`Mix.install/2`] (Livebook or a script) —
using the built-in [`ExAgent.Models.Test`] model, **no API key needed**:

```elixir
Mix.install([
  {:exagent, path: "../exAgent"}
])

agent = ExAgent.new(model: "test", instructions: "Be concise.")
{:ok, %{output: text}} = ExAgent.run(agent, "Hello!")
```

Point it at a real provider with a `"provider:model"` string:

```elixir
agent = ExAgent.new(model: "openai:gpt-4o", instructions: "Be concise.")
{:ok, %{output: text}} = ExAgent.run(agent, "Hello!")
```

[hexdocs]: https://hexdocs.pm/exagent
[source]: https://github.com/akorda-software/exagent
[`Mix.install/2`]: https://hexdocs.pm/mix/Mix.html#install/2
[`ExAgent.Model`]: https://hexdocs.pm/exagent/ExAgent.Model.html
[`RunContext`]: https://hexdocs.pm/exagent/ExAgent.RunContext.html
[`ExAgent.run/3`]: https://hexdocs.pm/exagent/ExAgent.html#run/3
[`ExAgent.run_stream/3`]: https://hexdocs.pm/exagent/ExAgent.html#run_stream/3
[`ExAgent.Server`]: https://hexdocs.pm/exagent/ExAgent.Server.html
[`ExAgent.Session`]: https://hexdocs.pm/exagent/ExAgent.Session.html
[`ExAgent.Models.Test`]: https://hexdocs.pm/exagent/ExAgent.Models.Test.html
[`ExAgent.Event`]: https://hexdocs.pm/exagent/ExAgent.Event.html
[`ExAgent.PubSub`]: https://hexdocs.pm/exagent/ExAgent.PubSub.html

<!-- MDOC -->

## Table of Contents

- [Layer 0 — the one-shot loop](#layer-0--the-one-shot-loop)
  - [Tools with derived schemas](#tools-with-derived-schemas)
  - [Structured output](#structured-output)
  - [Streaming](#streaming)
  - [Serialization / durable runs](#serialization--durable-runs)
- [Layer 1 — a stateful, supervised agent](#layer-1--a-stateful-supervised-agent)
- [Layer 2 — snapshots & resume](#layer-2--snapshots--resume)
- [Layer 3 — multi-agent sessions](#layer-3--multi-agent-sessions)
- [Coordination](#coordination)
- [Robustness & safety](#robustness--safety)
- [External tools (MCP)](#external-tools-mcp)
- [Events & PubSub](#events--pubsub)
- [OpenTelemetry](#opentelemetry)
- [Models](#models)
- [Examples](#examples)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Layer 0 — the one-shot loop

The core is a small loop: `UserPromptNode → ModelRequestNode ⇄ CallToolsNode → End`.

```elixir
agent = ExAgent.new(model: "test", instructions: "Be concise.")
{:ok, %{output: text}} = ExAgent.run(agent, "Hello!")
```

Operational loop failures return `{:error, %ExAgent.RunError{reason: cause,
partial: result}}`; success returns `{:ok, result}`. Invalid construction options
may still raise. The
`result` map carries `:output`, `:messages`, `:new_messages`, `:usage`
(`%{input_tokens:, output_tokens:}`), `:run_step` and the (possibly updated)
`:model`, plus run/tree/request IDs, status, usage completeness, scoped counters
and estimated `:cost_cents` / `:cost_status`. Inspect `error.reason` for classification
and retain `error.partial` for reconciliation; never treat partial output as
authorization to act. Live results may contain model credentials: use safe error
projections for logs/events instead of serializing the whole result.

### Tools with derived schemas

```elixir
defmodule MyApp.Tools do
  use ExAgent.Tools

  @doc "Get the weather for a city."
  deftool get_weather(_ctx, city :: String.t(), days :: integer()) do
    {:ok, "#{city}: sunny for #{days} day(s)"}
  end
end

agent = ExAgent.new(model: "openai:gpt-4o", tools: MyApp.Tools.tools())
```

`deftool` receives the [`RunContext`] as its first arg (named `ctx` by convention);
`tool_plain` takes only parameters. Each parameter is `name :: Type`, so the JSON
Schema is derived for you. A tool may return `value`, `{:ok, value}` or
`{:error, reason}`. Arguments are validated locally before invocation, and results
must be JSON-portable. Use `ExAgent.ModelRetry` explicitly for a correctable
rejection before an uncertain effect; execution exceptions/timeouts are not
automatic permission to replay it. Valid tool schemas are prepared on the reusable
agent definition and checked again if their schema changes.

### Structured output

Any `embedded_schema` becomes the output spec; JSON Schema is derived from the
schema **and** its changeset validations (`validate_inclusion` → `enum`,
`validate_number` → `minimum`/`maximum`, `validate_length` → `minLength`/
`maxLength`), then validated with the changeset, with retry-on-failure.

```elixir
defmodule WeatherReport do
  use Ecto.Schema
  embedded_schema do
    field :city, :string
    field :temp_c, :float
    field :condition, Ecto.Enum, values: [:sunny, :rainy, :cloudy]
  end

  def changeset(s, a) do
    s |> Ecto.Changeset.cast(a, [:city, :temp_c, :condition])
      |> Ecto.Changeset.validate_required([:city, :temp_c])
      |> Ecto.Changeset.validate_number(:temp_c, greater_than: -100, less_than: 100)
  end
end
# → the model is told temp_c is a number in (-100, 100) and condition is one of
#   the enum values, so it can comply instead of guessing and being retried.

agent = ExAgent.new(model: "anthropic:claude-3-5-haiku", output: WeatherReport)
{:ok, %{output: %{__struct__: WeatherReport}}} =
  ExAgent.run(agent, "It's 22 and sunny in Madrid")
```

### Streaming

```elixir
ExAgent.run_stream(agent, "count to five")
|> Stream.each(fn
  {:delta, t} -> IO.write(t)
  {:result, %{usage: u}} -> IO.puts("\n#{u.output_tokens} tokens")
  {:error, error} -> IO.puts(Exception.message(error))
end)
|> Stream.run()
```

[`ExAgent.run_stream/3`] uses the full loop, including tools, hooks, Ecto output
validation and limits. Deltas are provisional across all model requests; the final
result supplies the validated output. Each enumeration is a new run, so enumerate
once. Halting closes owned resources; a deliberately suspended continuation must
be resumed or halted. Custom Model adapters emit a terminal
`{:response, response, final_model}` or an error.

### Serialization / durable runs

The core is **DB-free**: it doesn't own a database or job queue. It provides
best-effort message-history serialization so you can persist a conversation
anywhere and resume it:

```elixir
json = ExAgent.Message.to_json(result.messages)   # store this
{:ok, history} = ExAgent.Message.from_json(json)  # load it back
ExAgent.run(agent, "follow up", message_history: history)
```

For persistent job dispatch, an application can use **Oban** — see the limitations
in `examples/durable_oban.exs`. Retrying a job can repeat requests/effects; storing
history is not mid-run recovery. A Server with Store provides conversation
checkpoints, with the same external-effect limitation.

## Layer 1 — a stateful, supervised agent

[`ExAgent.Server`] keeps an agent alive across runs: it preserves history,
accumulates usage, threads stateful models, and emits events.

```elixir
{:ok, dm} =
  ExAgent.AgentSupervisor.start_agent(
    agent: ExAgent.new(model: "openai:gpt-4o", instructions: "You are a DM."),
    agent_id: "dm",
    pubsub: :local
  )

{:ok, %{output: _}} = ExAgent.Server.chat(dm, "I enter the tavern.")   # synchronous
{:ok, %{output: _}} = ExAgent.Server.chat(dm, "I pick the lock.")      # sees prior turn

# Async: returns immediately, result arrives as a :run_finished event
{:ok, request_id} = ExAgent.Server.send_message(dm, "describe the room")
ExAgent.Server.abort(dm)      # cancel the in-flight run (stays responsive)
ExAgent.Server.health(dm)     # %{status: :idle, pending: 0}
```

While a run is in flight, `chat/3` returns `{:error, :busy}` and `send_message/3`
enqueues up to `max_pending` (default `8`) then returns `{:error, :queue_full}`.

## Layer 2 — snapshots & resume

Point a Server at a store to confirm complete checkpoints and rehydrate the last
confirmed conversation on restart:

```elixir
ExAgent.AgentSupervisor.start_agent(
  agent: agent_template,
  agent_id: "dm",
  store: :ets          # ExAgent.Store behaviour; ETS ships by default
)
```

The persisted `ExAgent.Server.Snapshot` carries serializable history, usage and
metadata, not the live model, pids or tool closures. JSON does not detect secrets
introduced as strings by the application. The live model/tools come from a trusted
template on restart. Store is disabled unless configured;
`ExAgent.Store.ETS` is in-process and depends on its table owner/VM. For a durable DB, use
`ExAgent.Store.Postgres` (needs `ecto_sql` + `postgrex`):

```elixir
ExAgent.Store.Postgres.migrate(MyApp.Repo)   # once
ExAgent.AgentSupervisor.start_agent(
  agent: agent_template, agent_id: "dm",
  store: {ExAgent.Store.Postgres, MyApp.Repo}
)
```

A failed save returns `ExAgent.CheckpointError` while retaining the new state in
memory. Further mutations wait for `Server.checkpoint/1` (or `Session.checkpoint/1`)
to retry only storage, not the model, tools or state-change function. Async queue
admission remains volatile. Restore rejects corrupt/future/mismatched snapshots
instead of starting empty; see the v1/v2 migration guidance.

## Layer 3 — multi-agent sessions

[`ExAgent.Session`] coordinates participants (agents or humans) taking turns over
a piece of shared state, through a pluggable `TurnPolicy`. The Session is the
**single writer** of `shared_state`.

```elixir
alias ExAgent.Session
alias ExAgent.Session.Participant

{:ok, game} =
  Session.start_link(
    shared_state: %{log: []},
    policy: {:initiative, order: ["rogue", "fighter"]},
    participants: [
      Participant.new(id: "rogue", kind: :agent),
      Participant.new(id: "fighter", kind: :human)
    ],
    pubsub: :local
  )

{:ok, "rogue"} = Session.start(game)
{:ok, world, next} =
  Session.take_turn(game, "rogue", fn s -> {:ok, %{s | log: ["rogue acts" | s.log]}} end)
# `next` is now "fighter"; it sees the rogue's change via Session.read_state/1
```

Tools inside an agent run read/propose state through an
`ExAgent.Session.SharedState` handle in `RunContext.deps`, through the Session's
API rather than direct mutation of a shared value. Policies: `RoundRobin`, `Initiative` (custom `:order`),
`SupervisorPolicy` (a coordinator alternates with workers).

## Coordination

`ExAgent.Coordination` adds the classic orchestration patterns on top of a
Session (levels 2 & 3):

```elixir
alias ExAgent.Coordination

# Delegation (agent-as-tool): the parent calls a sub-agent; both runs' tokens
# are counted together.
helper = ExAgent.new(model: "openai:gpt-4o-mini", instructions: "You summarize.")
parent =
  ExAgent.new(
    model: "openai:gpt-4o",
    tools: [Coordination.delegation_tool(helper, name: "summarize")]
  )

# Hand-off: transfer control between participants directly.
{:ok, "fighter"} = Coordination.handoff(game, "fighter")
```

Delegation uses one owned execution scope: child rules cannot override ancestor
denial/approval or expand their limits. `ExAgent.run_child(context, agent, prompt,
opts)` is the explicit scoped entry point for custom auxiliary calls. Arbitrary
IO outside that scope is not automatically accounted or sandboxed.

## Robustness & safety

Long sessions and cost stay under control, all opt-in:

```elixir
alias ExAgent.{Compaction, CostGuard, Permissions, UsageLimits}

# Summarize old turns once the context grows (capability hook).
compaction = %Compaction.Capability{
  compactor: Compaction.Summary,
  opts: [threshold_tokens: 6000, keep_recent: 8, summarize: &MyApp.summarize/1]
}

# Per-tool admission control (allow/ask/deny with globs).
perms = Permissions.new!(rules: [{"*", :deny}, {"read", :allow}, {"bash", :ask}])

agent =
  ExAgent.new(
    model: "anthropic:claude-3-5-haiku",       # cache: true → prompt caching
    capabilities: [compaction],
    usage_limits: %UsageLimits{request_limit: 20, tool_calls_limit: 15, max_budget_cents: 25}
  )

ExAgent.run(agent, "go",
  permissions: perms,
  approve: &MyApp.ask_human/1,                 # called on :ask
  # Illustrative cents per 1K tokens; supply your provider's actual prices.
  estimate_cost: CostGuard.estimator(%{input_per_1k_cents: 0.25, output_per_1k_cents: 1.0})
)
```

Compaction projects request context while retaining canonical history; it does not
bound persisted history size. A caller's one-argument summarizer may perform IO
outside the scope. Cost is estimated per request, retaining fractional cents;
heterogeneous model pricing uses an arity-two `(model, usage)` estimator. Missing
usage/price is unknown, not zero, and requests already in flight can exceed a
retrospective token/cost threshold. Run options `deadline` (absolute monotonic
milliseconds) and `max_concurrent_requests` control admission separately.

## External tools (MCP)

Consume a stdio [Model Context Protocol](https://modelcontextprotocol.io) server's
tools as plain `ExAgent.Tool`s:

```elixir
alias ExAgent.MCP.Client

{:ok, fs} =
  Client.start_link(
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-filesystem", "./data"]
  )

{:ok, tools} = Client.tools(fs)   # [ExAgent.Tool.t(), ...]
agent = ExAgent.new(model: "anthropic:claude-3-5-haiku", tools: tools)
```

The client owns the stdio JSON-RPC connection (handshake, `tools/list`,
`tools/call`, line buffering); transport exits and errors surface cleanly.
Defaults are 128 pending requests and 8 MiB frames, configurable. A timeout/dead
caller is cleaned up locally; that does not prove rollback of a remote effect.

## Events & PubSub

Every layer emits versioned [`ExAgent.Event`] envelopes (distinct from
`:telemetry`). Subscribe to drive a UI:

```elixir
:ok = ExAgent.PubSub.subscribe({ExAgent.PubSub.Local, []}, ExAgent.Event.agent_topic("dm"))

receive do
  {:exagent_event, %ExAgent.Event{type: :run_finished, payload: p}} ->
    IO.puts("done: #{inspect(p)}")
end
```

[`ExAgent.PubSub`] is a behaviour: `None` (default, no-op), `Local` (Registry),
`Phoenix` (delegates to `Phoenix.PubSub` dynamically — no hard dependency), or
your own.

## OpenTelemetry

Opt into native Erlang/Elixir OTel with an application-owned SDK and exporter:

```elixir
tracing = ExAgent.Observability.OpenTelemetry.new()
agent = ExAgent.new(model: model, observability: tracing)
```

Spans cover runs, model requests, tools, delegation, compaction and checkpoints.
Content is off by default; enabling it requires explicit redaction before
attributes reach the exporter. Request usage and inclusive run totals are kept
separate to avoid double counting. The optional bounded processor provides an
asynchronous export route with observable saturation and failures.

See [observability](docs/guides/observability.md) for application configuration, context
propagation, privacy and export limits. Langfuse/Opik comparison and external
backend acceptance remain pending; neither platform is required or selected.

## Models

Resolve from a string or pass a struct:

```elixir
ExAgent.new(model: "openai:gpt-4o")
ExAgent.new(model: "openrouter:deepseek/deepseek-v4-flash")   # one gateway, many backends
ExAgent.new(model: "opencode:deepseek-v4-flash")             # Go by default; Zen is configurable
ExAgent.new(model: "anthropic:claude-3-5-haiku-20241022")
ExAgent.new(model: "zai:glm-4.5-air")   # Z.AI's Anthropic-compatible endpoint (GLM)
```

The loop is provider-agnostic and the parsers tolerate the malformed responses
real providers occasionally return (empty `choices`, `content: null`, partial
`usage`). Bring your own provider by implementing the [`ExAgent.Model`] behaviour.
Native HTTP adapters disable automatic retries/redirects. Model `stream_options`
controls bounded framing/response size and demand timeouts. Native streaming
support and external-backend acceptance are separate from the offline tests.

## Examples

- `examples/demo.exs` — offline loop with the TestModel.
- `examples/openrouter.exs` — live tool-calling via OpenRouter.
- `examples/structured_output.exs` — live structured output via Ecto.
- `examples/streaming.exs` — live SSE streaming.
- `examples/stateful_agent.exs` — supervised stateful agent + events.
- `examples/observability.exs` — native OTel with a local exporter; optional
  `--bench` measures synthetic instrumentation overhead.
- `examples/framework_evals.exs` — deterministic offline evaluations in two
  domains, with typed output, scoped delegation and checkpoint-only recovery;
  `--json <path>` writes the machine-readable result.
- `examples/multi_agent_session.exs` — two agents, round-robin, shared state.
- `examples/dnd_session.exs` — a mini D&D round: DM + bot + human over a shared
  world, coordinated by a Session (SupervisorPolicy), offline.

Run any of them with `mix run examples/<name>.exs` (live ones need an API key in
the environment).

The source checkout also includes `test/support/framework_load_probe.exs` for
bounded local concurrency/observability measurements (`--smoke` for a small
fixture check, `--json <path>` for the report). Its percentiles and sampled resource
maxima are synthetic framework evidence, not LLM latency or production SLOs.

## Documentation

- [Full module reference on hexdocs][hexdocs]
- [Documentation index](docs/README.md) — guides, current state and maintenance rules.
- [Project status](docs/status.md) — verified baseline, recap and open gates.
- [Architecture](docs/architecture/overview.md) and
  [design decisions](docs/architecture/design.md) — layers, contracts and evolution policy.
- [Roadmap](docs/development/roadmap.md) — current priorities and acceptance criteria.
- [Changelog](docs/changelog.md) — release history and unreleased changes.
- [Migration](docs/guides/migration.md) — upcoming-major caller/adapter/snapshot migration.
- [Observability](docs/guides/observability.md) — optional native OTel setup and privacy.
- [Verification](docs/development/verification.md) — offline tests, snippets and package checks.

## Contributing

Bug reports and pull requests are welcome on [GitHub][source].

ExAgent aims to make reliable agents and tool use straightforward across a broad
range of providers, from one-shot calls to layered stateful workflows. The current
priority is a solid, maintainable foundation, not adding features at the expense
of coherent contracts. This is a product direction, not a claim that every
provider or capability is already supported.

Preserve compatibility where practical. Breaking changes are acceptable when
they solve a demonstrated design problem and their general benefit justifies
the migration cost; cosmetic API churn is not. Document the rationale,
alternatives, observable impact, migration and verification. Published stable
contracts still follow SemVer, even while the author's own applications are
pre-production. Once the foundation is validated, favor additive extensions and
planned deprecations over repeated structural changes. See the policy in
[design principles](docs/architecture/design.md) and the current
[roadmap](docs/development/roadmap.md).

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix compile --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix test --warnings-as-errors
EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/demo.exs
```

`EXAGENT_OFFLINE=1` skips even the Postgres bootstrap. Real-provider tests are
tagged `:integration` and excluded by default; enable them only for an explicitly
scoped backend check. Without offline mode, Postgres tests attempt their database
and auto-skip if unavailable. Mock/stdio/local-HTTP tests do not prove acceptance
by external providers or a durable database.

## License

Copyright (c) 2025 kukapu

Licensed under the MIT License — see [LICENSE](./LICENSE).
