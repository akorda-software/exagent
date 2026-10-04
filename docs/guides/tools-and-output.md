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

For a correctable rejection before an uncertain effect, use `ExAgent.ModelRetry`.
An execution exception or timeout may occur after an external effect; it does not
authorize automatic replay. Your application owns idempotency and reconciliation.
Use [persisted approvals](durability-and-approvals.md) when a decision must survive
process loss or wait for a human.

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
