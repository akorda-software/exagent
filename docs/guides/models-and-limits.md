# Models, budgets and limits

ExAgent uses **official stock ReqLLM** as its general backend. Custom adapters
implement `ExAgent.Model`; the Test adapter runs locally. A model being present
in a catalogue is distinct from its tools, output and streaming profile being
qualified for ExAgent.

## Resolve a text model

The application supplies credentials. This example resolves configuration;
calling `ExAgent.run/3` with it makes a real provider request:

```elixir
{:ok, model} = ExAgent.Model.resolve({:openai, id: "gpt-4o-mini"},
  api_key: System.fetch_env!("OPENAI_API_KEY")
)
agent = ExAgent.new(model: model, instructions: "Be concise.")
```

Use instance credentials for explicit ownership. ReqLLM's startup environment
loading is described in [Getting started](getting-started.md). Never place a key
in a prompt or persist the complete live model.

## Configure Chat tools and streaming

The explicit profile binds the protocol, tools and reasoning capability:

```elixir
model = ExAgent.Models.ReqLLM.new(
  model: %{
    provider: :openai,
    id: "gpt-4o-mini",
    capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
    extra: %{wire: %{protocol: "openai_chat"}}
  },
  api_key: System.fetch_env!("OPENAI_API_KEY"),
  tool_profile: :chat_tools_v1
)
```

These declarations configure admission; they do not prove the endpoint behaves
correctly. Qualify the exact gateway/model combination you deploy. The
[support matrix](../status.md) records the accepted minimal OpenRouter profile
and leaves unproven reasoning, modality and continuation combinations guarded.

Native output is separate: `output_profile: :chat_json_schema_v1` plus agent
`output_mode: :native`. See [Tools and output](tools-and-output.md).

## Bound requests and tool calls

```elixir
agent = ExAgent.new(
  model: "test",
  usage_limits: %ExAgent.UsageLimits{request_limit: 3, tool_calls_limit: 2}
)
{:ok, result} = ExAgent.run(agent, "Hello!")
result.request_count
# => 1
```

Request and tool counters are host observations. Limits apply before admission
of the next operation. Scoped child runs inherit ancestor authority and budgets;
a child cannot enlarge the parent's allowance. Parent usage is inclusive of its
children, so adding every span's totals would count delegated work twice.

For token/cost dimensions, read `ExAgent.UsageLimits`
and `ExAgent.CostGuard`. Strict metric accounting
requires a finite request limit. Provider-reported or normalized tokens and
estimated cost have quality/status fields. Unknown usage or cost is not zero,
and an estimated threshold is not a guaranteed invoice ceiling.

## Separate the timeout boundaries

| Boundary | Meaning |
|---|---|
| `ModelSettings.timeout` | Receive inactivity timeout; takes precedence over the model's receive setting. |
| ReqLLM `total_timeout` | Positive millisecond bound on one buffered model operation. |
| Run `deadline` | Absolute monotonic milliseconds, inherited and narrowed by child scope. |
| Continuation lease and active-time budget | Bounds one owned continuation attempt; not permission to retry an uncertain effect. |

Stopping an owned task closes framework resources. It cannot roll back external
IO or guarantee cancellation of arbitrary application callbacks. Host retention
limits apply after stock decoding; no upstream hard RAM bound before decoding is
promised. [Migration](migration.md) documents option precedence and failure shapes.

API: `ExAgent.Models.ReqLLM`,
`ExAgent.Model`,
`ExAgent.ModelSettings`.
