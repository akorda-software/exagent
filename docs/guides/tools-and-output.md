# Tools and structured output

A tool gives an agent a bounded way to invoke application code. An output schema
gives your application a validated final value. They share JSON Schema support,
but a tool return and the final agent output are different results.

This page uses the deterministic Test model throughout. To use these APIs with
a provider, configure the explicit [Chat tools profile](models-and-limits.md).

## Define a tool

```elixir
defmodule DocumentationTools do
  use ExAgent.Tools

  @doc "Convert a distance in kilometres to metres."
  tool_plain to_metres(kilometres :: integer()) do
    {:ok, kilometres * 1000}
  end
end

DocumentationTools.tools()
```

`tool_plain` receives only the declared arguments. Use `deftool` when you also
need a `RunContext` as the first argument, for example to use application-owned
dependencies from `ctx.deps`. `@doc` supplies the description and type annotations
supply the input schema. For a manually built schema, use
`ExAgent.Tool.new/1`.

## Exercise the whole tool loop

```elixir
alias ExAgent.Message.Part.ToolCall

model = %ExAgent.Models.Test{
  script: [
    {:tool_calls, [
      %ToolCall{tool_name: "to_metres", tool_call_id: "conversion-1",
        args: %{"kilometres" => 3}}
    ]},
    "3 kilometres is 3000 metres."
  ]
}

agent = ExAgent.new(model: model, tools: DocumentationTools.tools())
{:ok, result} = ExAgent.run(agent, "Convert 3 kilometres.")
%{output: result.output, requests: result.request_count, tools: result.tool_calls}
# => %{output: "3 kilometres is 3000 metres.", requests: 2, tools: 1}
```

The first model response requests a tool; the loop validates its arguments,
executes it and sends the result to the next model request. The second response
ends the run. Tests can inspect the actual tool-return part in `result.messages`.

## Decide what a failure means

Arguments are validated **before invocation**. Tool results must be JSON-portable
and can be returned as a value, `{:ok, value}` or `{:error, reason}`.

When a schema regex exhausts its backtracking budget, validation rejects with
`indeterminate_pattern`, including inside `not`, `anyOf` and `patternProperties`.
The tool is not invoked. Rewrite nested quantifiers or overlapping alternatives
if legitimate input reaches that limit. This security correction is included in
ExAgent 2.2.4's JSV 0.27 dependency update; no error-shape migration is required.

For a correctable rejection before an uncertain effect, use `ExAgent.ModelRetry`.
An execution exception or timeout may occur after an external effect; it does not
authorize automatic replay. Your application owns idempotency and reconciliation.
Use [persisted approvals](durability-and-approvals.md) when a decision must survive
process loss or wait for a human.

## Control how tool calls run

When one model response requests several calls, they run concurrently and each
is bounded by the agent's `:tool_timeout` (30 seconds by default). Two optional
`ExAgent.Tool` fields refine that per tool:

```elixir
write = ExAgent.Tool.new(
  name: "write_file",
  parameters_json_schema: %{type: "object"},
  call: fn _ctx, args -> MyApp.Files.write(args) end,
  concurrency: :exclusive,
  timeout: 5_000
)

tools = [write | Enum.map(DocumentationTools.tools(), &%{&1 | timeout: 2_000})]
```

An `:exclusive` call runs alone: calls listed before it finish first, and calls
after it start only when it has finished. Consecutive `:parallel` calls (the
default) still run together, whatever their timeouts. `timeout` replaces
`:tool_timeout` for that tool's calls, may be shorter or longer, and remains
capped by the run deadline. A call that exceeds it is killed and reported with
an `:unknown` outcome, which fails the run with `{:tool_execution_failed, name,
{:exit, :timeout}}`; use `ExAgent.Jobs` for work that may outlast it. Results
keep the order the model requested.

Ordering applies to the calls executed in one attempt: a call that pauses for
[approval](durability-and-approvals.md) does not hold back later calls of the
same response. Neither field is sent to the model or included in persisted
continuation fingerprints, so a resumed run uses the current definition, even
when its timeout exceeds the persisted `:tool_timeout`.

## Keep tool results and loops in check

A tool result stays in the conversation and is sent again on every later step.
`ExAgent.Tool.OutputLimit` shortens large successful results to their beginning
and end, with a notice of how much was omitted:

```elixir
limit = ExAgent.Tool.OutputLimit.new(
  max_bytes: 16_000,
  on_truncate: fn %{tool_call_id: id, content: full} ->
    MyApp.Outputs.store(id, full)
    "The full output is stored as #{id}; call read_output to page through it."
  end
)

guard = ExAgent.Tool.RepeatGuard.new(warn_at: 3)

ExAgent.new(model: model, tools: tools, capabilities: [limit, guard])
```

`:keep` chooses `:head_tail` (default), `:head` or `:tail`, and `:tools` limits
the capability to named tools. Structured results are shortened as their JSON
encoding, so the model then receives a string. Later requests, the history and
events see the shortened result; the raw outcome confirmed before hooks run, as
kept in persisted effect records, may still hold the full one. Results over the
run's `:max_payload_bytes` retention ceiling (1 MiB by default) still fail
before any capability sees them.

`ExAgent.Tool.RepeatGuard` notices when the latest response repeats an identical
call (same tool name and equal arguments) for the `warn_at`-th time since the
latest user message, and adds a short runtime note to the model request asking
it to use the earlier result or change approach. The note is not added to the
canonical history or events, and is rebuilt in the same position on later
requests, so it keeps provider cache prefixes stable. It never blocks a call. List it after
compaction, and exclude tools that are expected to repeat, such as polling.

## Offer a large catalogue on demand

Every tool schema is sent with every model request. When an agent has dozens of
tools, for example from several MCP servers, `ExAgent.Tool.Search` keeps the
rarely used ones out of the request until the model searches for them:

```elixir
search = ExAgent.Tool.Search.new(deferred: mcp_tools, max_results: 5)

ExAgent.new(
  model: model,
  tools: [lookup_order | ExAgent.Tool.Search.tools(search)],
  capabilities: [search]
)
```

The model sees `lookup_order` and `search_tools`. A search returns the best
matching deferred tools by name and description, or exactly the tools it names,
and those tools are offered from the next request on. Which tools are loaded is
read from the conversation history, so a restored conversation or a later run
offers the same tools in the same order, which keeps provider prompt caches
valid. Deferred tools keep their permissions and approvals; hiding a tool does
not restrict it. Do not gate the same tools with skills.

## Check the final answer

`:output_validators` runs your checks on the final output after it passed its
schema and before the run accepts it. Return `{:retry, message}` to send
feedback to the model and let it continue:

```elixir
cites_sources = fn output, _ctx ->
  if output =~ "Source:", do: :ok, else: {:retry, "Cite the source of each figure."}
end

ExAgent.new(model: model, tools: tools, output_validators: [cites_sources], output_retries: 2)
```

`:ok` accepts, `{:ok, replaced}` replaces the output, and `{:error, reason}`
fails the run with `{:output_validation_failed, reason}`. Retries share the
`:output_retries` budget. Checks also see Ecto structs and native JSON output.

`ExAgent.Judge.output_validator/1` lets another model do the check against
written criteria; its PASS/FAIL feedback reaches the agent the same way, and
its usage counts toward the run (with a persisted continuation it runs
separately and its usage is not added). `ExAgent.Judge.approver/1` reviews tool
calls whose permission is `:ask`; each review is a separate run inside the tool
call, so it counts toward the tool's timeout and not toward the run's usage:

```elixir
review = ExAgent.Judge.output_validator(model: reviewer, criteria: "Answers every question asked.")

approve =
  ExAgent.Judge.approver(
    model: reviewer,
    policy: "Writes only under /tmp/. Never touch system files.",
    escalate: &MyApp.ask_a_human/1
  )

agent = ExAgent.new(model: model, tools: tools, output_validators: [review])
ExAgent.run(agent, prompt, permissions: permissions, approve: approve)
```

A reviewer is a model and can be wrong; keep hard limits in permissions and in
the tools themselves.

## Return an Ecto struct

```elixir
defmodule DocumentationDistance do
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :metres, :integer
  end

  def changeset(struct, attrs) do
    struct
    |> Ecto.Changeset.cast(attrs, [:metres])
    |> Ecto.Changeset.validate_required([:metres])
    |> Ecto.Changeset.validate_number(:metres, greater_than_or_equal_to: 0)
  end
end

model = %ExAgent.Models.Test{
  script: [{:tool_calls, [
    %ExAgent.Message.Part.ToolCall{tool_name: "final_result",
      tool_call_id: "distance-1", args: %{"metres" => 3000}}
  ]}]
}

agent = ExAgent.new(model: model, output: DocumentationDistance)
{:ok, result} = ExAgent.run(agent, "Convert 3 kilometres.")
result.output.metres
# => 3000
```

The default output mode exposes a `final_result` tool to the model. ExAgent
derives the schema and validates the result with the changeset. Invalid output
can trigger corrective requests within the same run budget. Deliver the value
from the **successful final result**, not a provisional delta.

`Ecto.Enum` advertises its declared storage values with their JSON type:
`values: [pending: 0, done: 1]` asks for `0` or `1`, while
`values: [pending: "P", done: "D"]` asks for `"P"` or `"D"`. Inclusion and
exclusion constraints use that same vocabulary. The validated Ecto struct still
contains the enum atom, such as `:done`.

## Choose native output deliberately

Native JSON Schema uses `output_profile: :chat_json_schema_v1` on the model and
`output_mode: :native` on the agent. It sends a separate, non-strict schema and
does not create an output tool. The local changeset remains authoritative;
there is no automatic fallback to tool mode or JSON repair.

Read the [native-output migration contract](migration.md#4-validate-tools-and-typed-output-locally)
for qualification, refusal and streaming limits before choosing this mode.

API: `ExAgent.Tools`, `ExAgent.Tool`,
`ExAgent.OutputSchema`,
`ExAgent.ModelRetry`.
