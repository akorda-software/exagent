# Build agents with Elixir

<div class="exagent-intro">
<p class="exagent-kicker">ExAgent · Elixir / OTP</p>
<p class="exagent-lead">Start with a model and a tool.<br>Keep control as your application grows.</p>
<p>One agent loop, with optional layers for conversations, persistence, approvals and coordination. Stock ReqLLM connects your models; your application owns its data and effects.</p>
</div>

[Run your first agent →](guides/getting-started.md){: .exagent-primary}
[Integrate with a coding agent](guides/agents.md)
{: .exagent-actions}

> #### Using ExAgent 2.1 {: .info}
>
> These pages describe **ExAgent 2.1.0**; published 1.x packages have older
> contracts. Check [supported features and limits](guides/support.md), use the dependency in
> [Getting started](guides/getting-started.md), or read
> [Migration](guides/migration.md) when upgrading an existing application.

## A small, working beginning

Run this inside an application that depends on ExAgent2.0. No credentials or
network are needed:

```elixir
agent = ExAgent.new(model: "test", instructions: "Be concise.")
{:ok, result} = ExAgent.run(agent, "Hello!")
result.output
# => "a test response"
```

The test model follows the same loop as a provider. Next, add a tool, validate a
typed result, or replace the model with a qualified ReqLLM instance.

## Choose the layer your application needs

<dl class="exagent-layers">
<div><dt>Run</dt><dd>A request, tools and a validated result. Start here for scripts, jobs and extraction.</dd></div>
<div><dt>Server</dt><dd>A supervised conversation with history, a bounded queue and events.</dd></div>
<div><dt>Store</dt><dd>Confirmed snapshots and explicit continuation boundaries. Add durability when you need it.</dd></div>
<div><dt>Coordination</dt><dd>Session turns, scoped delegation, durable sequences and bounded router or parallel flows.</dd></div>
</dl>

Each layer has its own ownership contract. A checkpoint confirms saved data; an
application still reconciles an external effect whose outcome is uncertain.

## Build something useful

| Your next task | Guide |
|---|---|
| Call application code and return validated data | [Tools and structured output](guides/tools-and-output.md) |
| Select a provider and bound work | [Models, budgets and limits](guides/models-and-limits.md) |
| Add conversation history, streaming and UI events | [Runtime and events](guides/runtime-and-events.md) |
| Persist a conversation or wait for human approval | [Durability and approvals](guides/durability-and-approvals.md) |
| Coordinate several agents | [Coordination](guides/coordination.md) |
| Test without calling a model provider | [Testing](guides/testing.md) |
| Export traces to Langfuse or Opik | [Observability](guides/observability.md) |
| Connect an external tool server | [MCP](guides/mcp.md) |

For an unexpected result, start with [Troubleshooting](guides/troubleshooting.md).

## Read the contract behind the example

`ExAgent.run/3` is the main entry point. `ExAgent.Tool` describes a tool;
`ExAgent.Server` owns a conversation. Browse the **Modules** tab or use **/**
to search functions and pages. Guides link to the relevant API as you go.

For coding agents, [Integration notes](guides/agents.md) provide an API map,
result shapes, responsibilities and a reading route. ExDoc also generates
`llms.txt` and Markdown versions of these pages from the same source. Use the
**View llms.txt** action at the bottom of the generated page.

[Supported features and limits](guides/support.md) explains deployment boundaries.
[The documentation map](guides/index.md) connects tutorials, integration recipes
and the API reference.
