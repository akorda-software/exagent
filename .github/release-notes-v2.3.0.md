# ExAgent 2.3.0

Feature release. Additive: existing agents, tools and persisted formats keep
working; new behavior is opt-in.

**Agents that remember and work longer**

- `ExAgent.Memory`: long-term memory the agent curates as files under
  `/memories`, scoped per user or tenant, with ETS (default) and PostgreSQL
  backends, compare-and-swap writes, size limits and `preload/3` for the
  instructions.
- `ExAgent.Jobs`: background tools and sub-agents with `job_status`,
  `wait_job` and `cancel_job` tools and notifications into a Server conversation.
- `ExAgent.Compaction.Memo`: reuses the last summary instead of summarizing on
  every request.

**Better answers**

- `:output_validators`: host checks on the final answer with feedback and retry.
- `ExAgent.Judge`: a reviewer model for final answers (PASS/FAIL) and for
  `:ask` tool calls (ALLOW/DENY/ASK with human escalation).
- `ExAgent.Tool.Advisor`: a fast model consults a stronger one mid-task.
- Reasoning with tools on OpenRouter (`reasoning_mode: :enabled`).

**Tools at scale**

- Per-tool `timeout` and `concurrency: :exclusive`.
- `Tool.Search` loads large tool catalogues on demand; `Tool.OutputLimit`
  shortens large results; `Tool.RepeatGuard` notices repeated identical calls.
- MCP: `tools/list` pagination over stdio and HTTP, and explicit notices for
  non-text tool results.

**Measure quality**

- `ExAgent.Eval`: run an agent over cases with built-in evaluators (`equals`,
  `contains`, `matches`, `tool_called`, `judge`), repeats, concurrency,
  latency/token/cost summaries and `Report.compare/2` for regressions.

```elixir
{:exagent, "~> 2.3.0"}
```

Migration notes: OpenRouter continuation v4 may now record
`reasoning_mode: "enabled"`, which earlier readers reject; `%ExAgent{}` gains
`output_validators` and `%ExAgent.Tool{}` gains `timeout`/`concurrency`. MCP
servers that paginate `tools/list` now return their full catalogue instead of
`{:error, :pagination_unsupported}` (HTTP) or only the first page (stdio).
Lock: transitive `telemetry` 1.4.3 and `nimble_pool` 1.2.0.

Validation: the full offline suite passes with zero failures (provider and
PostgreSQL tests excluded), plus strict docs, links and package isolation.
Memory's PostgreSQL backend passes against PostgreSQL 18. Live OpenRouter probes
(DeepSeek V4.1 Flash and Sonnet 5.5) cover memory across sessions, reviewers,
the advisor and evals. Each feature had an independent review, followed by an
integrated review of the whole release. Details: `docs/changelog.md`.
