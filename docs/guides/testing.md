# Test your integration

Use TestModel to test application behavior without credentials or a network.
Test a real provider, database or exporter separately when your application
depends on that system's actual behavior.

## Assert on the public result

```elixir
defmodule DocumentationAgentTest do
  use ExUnit.Case, async: true

  test "returns the validated final output" do
    agent = ExAgent.new(model: %ExAgent.Models.Test{label: "Ready"})
    assert {:ok, result} = ExAgent.run(agent, "Start")
    assert result.status == :succeeded
    assert result.output == "Ready"
    assert result.request_count == 1
  end
end
```

Put this in your application's `test/` directory and run `mix test`.
Use `script:` for sequential responses, `{:tool_calls, calls}` for tool requests
and `fn messages, params -> response end` to inspect the actual request.
The messages include the history supplied to that interaction.

## Script every expected request

An initially empty script uses `label:` or the generic response. A nonempty
script must cover the whole loop, including the next response after a tool or an
output-validation retry. Exhaustion fails instead of inventing a final answer.

This script records one simulated effect, then fails on the next request:

```elixir
effects = :atomics.new(1, [])
tool = ExAgent.Tool.new(
  name: "record",
  parameters_json_schema: %{"type" => "object", "properties" => %{}},
  takes_ctx: false,
  call: fn _args ->
    :atomics.add(effects, 1, 1)
    {:ok, "recorded"}
  end
)
model = %ExAgent.Models.Test{script: [
  {:tool_calls, [%ExAgent.Message.Part.ToolCall{
    tool_name: "record", tool_call_id: "record-1", args: %{}}]}
]}
agent = ExAgent.new(model: model, tools: [tool])
{:error, %ExAgent.RunError{partial: partial}} = ExAgent.run(agent, "Record once.")
%{status: partial.status, requests: partial.request_count, effects: :atomics.get(effects, 1)}
# => %{status: :failed, requests: 2, effects: 1}
```

## Make effects observable

Inject a dependency that records tool invocations or sends a message to the test
process. Assert on arguments, effect count, returned parts and terminal result.
Use an observable admission or effect boundary rather than elapsed sleeps to
prove ordering. [Tools and output](tools-and-output.md) contains a scripted tool run.

Cover invalid arguments before an effect, failure after an effect, exhausted
budgets, cancellation, failed checkpoint and duplicate approval/job wake-ups.
A failed final result must not accidentally make the application repeat a
completed tool. Verify that checkpoint retry only repeats storage.

## Test the external boundary separately

| Your application uses | Verify |
|---|---|
| A real model | Exact endpoint/model, tool envelope, reasoning settings, streaming and output schema. |
| PostgreSQL | Confirmed saves, restart/restore, competing decisions and uncertain-effect recovery. |
| MCP | Your server's protocol, identity, timeout behavior and remote outcome. |
| LiveView or jobs | Scoped event correlation, reconnect, duplicate deliveries and authenticated approval. |
| OpenTelemetry | Parentage, status, usage quality, permitted content and destination ingestion. |

A skipped or excluded case never ran. A selected case that times out fails.
TestModel covers local execution contracts; it cannot prove a provider's wire
compatibility, database durability or successful trace ingestion.

See [Supported features and limits](support.md) for the supported configurations.

API: `ExAgent.Models.Test`, `ExAgent.RunError`.
