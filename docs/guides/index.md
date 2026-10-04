# Documentation map

Start with a task guide, then follow its API links for exact options and return
values. These pages describe ExAgent 2.0; use [Migration](migration.md) when
upgrading an application from 1.x.

## Learn and build

| Your task | Guide |
|---|---|
| Install and run your first agent | [Getting started](getting-started.md) |
| Call application code and return an Ecto struct | [Tools and output](tools-and-output.md) |
| Select a model, provider route and budget | [Models and limits](models-and-limits.md) |
| Keep conversation history and stream UI updates | [Runtime and events](runtime-and-events.md) |
| Persist state, approve a tool and resume work | [Durability and approvals](durability-and-approvals.md) |
| Coordinate participants, delegate or run a workflow | [Coordination](coordination.md) |
| Write deterministic tests | [Testing](testing.md) |
| Export traces and metrics | [Observability](observability.md) |
| Connect external tools | [MCP](mcp.md) |
| Diagnose a failed operation | [Troubleshooting](troubleshooting.md) |

## Integration recipes

| Application need | Recipe |
|---|---|
| Persisted approval and queue wake-ups | [Continuation jobs](../development/continuation-jobs.md) |
| Phoenix, LiveView and Oban | [Framework integrations](../development/framework-integrations.md) |
| Durable sequences and selected specialists | [Coordination recipes](../development/coordination-recipes.md) |
| External data supplied through a tool | [Retrieval](../development/external-retrieval.md) |
| Resuming an approved MCP request | [MCP continuation binding](../development/mcp-continuation-binding.md) |
| OTLP through a disposable exporter VM | [Isolated exporter](../development/otlp-isolated-transport.md) |
| OTLP through an application-owned Collector | [Collector route](../development/otlp-collector-transport.md) |

## Find a contract

- [Architecture](../architecture/overview.md) explains ownership between layers.
- [Supported features and limits](support.md) lists profiles and deployment requirements.
- [Known limits](known-limits.md) explains the boundaries that affect production handling.
- [Migration](migration.md) gives the steps for upgrading an existing application.
- [Coding-agent integration notes](agents.md) map tasks to public APIs and result shapes.
- The **Modules** tab contains the complete public module and function reference.

The same site provides `llms.txt`, per-page Markdown and an EPUB. Use the Markdown
pages and API links when integrating ExAgent with a coding agent.
