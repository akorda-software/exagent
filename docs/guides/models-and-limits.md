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

Catalogue updates can remove a model or change its prices, limits and capabilities.
ExAgent 2.2.3 retains ReqLLM 1.29 and updates the checkout lock to
LLMDB 2026.10.7. Some former OpenRouter entries, including
`unbiased/pareto` and `inclusionai/ling-3.0-flash-fin`, are no longer present.
Resolving an absent ID can still succeed as an unverified model without catalogue
metadata. Do not interpret that success as tool qualification or known pricing.

The 2026.10.7 snapshot adds 609 model IDs and removes 501 relative to 2026.10.6;
prices, limits and capabilities also change for retained models.
The retired OpenRouter IDs include `openai/gpt-3.5-turbo` and
`microsoft/wizardlm-2-8x22b`. A library's lockfile does not constrain consuming
applications. To adopt the reviewed transitive updates, update the application lock with
`mix deps.update exagent llm_db splode` and review the resulting model metadata.

Applications that need stable metadata can pass an explicit model map to
`ExAgent.Model.resolve/2` or `ExAgent.Models.ReqLLM.new/1`, with the provider,
exact `id`, verified `capabilities`, `limits`, `cost` and wire protocol they rely
on. Maintain those facts against the actual provider; ExAgent does not restore
retired catalogue entries or invent prices. Review a model change before resuming
persisted work, and keep continuation mismatch checks intact.

ReqLLM 1.29 can merge `provider_options` from its application configuration or
the resolved model's `extra` metadata. ExAgent rejects non-empty defaults with
`{:unsupported_options, :provider_defaults}` before IO and continuation binding:
these options would otherwise bypass the instance allowlist and persisted route.
Remove those defaults and pass supported options explicitly as
`ExAgent.Models.ReqLLM.new(provider_options: ...)`. Empty defaults are accepted.

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
[supported profiles](support.md) describe the available tool/output combinations.
Unrepresented reasoning, modality and continuation combinations reject explicitly.

Native output is separate: `output_profile: :chat_json_schema_v1` plus agent
`output_mode: :native`. See [Tools and output](tools-and-output.md).

## Route OpenRouter Chat tools explicitly

Use `tool_profile: :openrouter_chat_tools_v1` for a qualified OpenRouter Chat
endpoint. The host supplies the exact model ID and truthful capabilities:

```elixir
model = ExAgent.Models.ReqLLM.new(
  model: %{
    provider: :openrouter,
    id: qualified_model_id,
    capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
    extra: %{wire: %{protocol: "openai_chat"}}
  },
  api_key: System.fetch_env!("OPENROUTER_API_KEY"),
  tool_profile: :openrouter_chat_tools_v1,
  provider_options: [
    openrouter_provider: %{only: [qualified_provider_id], allow_fallbacks: false}
  ]
)
```

Routing admits `order`, `only`, `ignore`, `allow_fallbacks` and
`require_parameters`. Provider lists contain 1–32 bounded identifiers. Optional
`app_title` and `app_referer` are attribution; other wire settings remain closed.
The mandatory tool argument envelope and validation still apply.

For a reasoning-capable model, `reasoning_mode: :none` additionally requires
declared support for effort `"none"` and disabling thinking. It sends one
`max_tokens` budget. Declaring those capabilities does not establish real
provider compatibility. This tools profile does not enable native JSON output.

The route and reasoning mode are bound before the first request and in tool
history. Changing them requires a fresh conversation; an existing approval or
uncertain request cannot resume through another route. Earlier unbound
OpenRouter history is rejected. See [Migration](migration.md) for continuation
version 4 and the unaffected OpenAI history versions.

## Send images and documents

`ExAgent.run/3` also accepts a list of content parts instead of a string:

```elixir
ExAgent.run(agent, [
  %{type: "text", text: "Summarize the report and describe the chart."},
  %{type: "image", data: Base.encode64(png), media_type: "image/png"},
  %{type: "file", data: Base.encode64(pdf), media_type: "application/pdf",
    filename: "report.pdf"}
])
```

Parts are `text`, `image_url` (`http`, `https` or `data` URL), `image` and
`file` (base64 data). The list is checked and stored with string keys before
any request; an invalid part fails with `{:invalid_prompt_part, index}` and an
empty list with `:invalid_prompt`. The model then accepts or rejects each
modality before IO: images need `:image` in the model's input modalities, and
PDFs need `:pdf` and a provider that sends documents (OpenRouter, Anthropic or
Google; stock OpenAI Chat accepts only images). Base64 content counts towards
`max_history_bytes`, so raise it for large files.

## Cache stable prompt prefixes

`prompt_cache` lowers the cost of long instructions and growing tool histories
without changing what is sent:

```elixir
model = ExAgent.Models.ReqLLM.new(
  model: openrouter_spec,
  api_key: System.fetch_env!("OPENROUTER_API_KEY"),
  tool_profile: :openrouter_chat_tools_v1,
  prompt_cache: [ttl: "5m"]
)
```

On OpenRouter it marks the last system message and the newest message with a
`cache_control` breakpoint, which Anthropic and Gemini routes use; `ttl` is
`"5m"` or `"1h"`. OpenAI caches long prefixes automatically, and
`prompt_cache: [key: "tenant:42"]` sends a stable `prompt_cache_key` to improve
hits. Other providers reject the option before IO. Cache reads and writes show
up in `result.usage.details` when the provider reports them.

## Retry and fall back to another model

`ExAgent.Models.Fallback` retries transient provider failures and then tries
the next model:

```elixir
primary = ExAgent.Models.ReqLLM.new(primary_options ++ [foreign_history: :portable])
backup = ExAgent.Models.ReqLLM.new(backup_options ++ [foreign_history: :portable])

model = ExAgent.Models.Fallback.new(models: [primary, backup], max_retries: 2)
agent = ExAgent.new(model: model, tools: tools)
```

Only failures that returned no output are retried: HTTP 408, 429, 500, 502,
503, 504 and 529 by default (`:retry_statuses`). A gateway may still bill an
upstream attempt behind a 502 or 504. Connection failures and total timeouts
may already have been processed and billed, so they need
`retry_transport: true`. Backoff is exponential with jitter. Each attempt
keeps `ModelSettings.timeout` as its receive timeout, and the run `deadline`
bounds all attempts together. A stream is retried only if it fails before its
first event.

A retried request is still one admitted request: `request_limit` and
`result.request_count` count model requests, not HTTP attempts. Each retry
emits `[:exagent, :model, :retry]` telemetry. An explicit `estimate_cost`
callback receives the `Fallback` model rather than the one that answered;
price by the response's `model_name` or rely on usage the models report.

Switching models mid-conversation sends one model's responses to another.
`Models.ReqLLM` rejects that by default. With `foreign_history: :portable` it
sends history it cannot replay natively (another model's responses, or its
own from another route or reasoning mode) as plain text and tool calls,
without their reasoning, signatures or provider metadata, instead of
rejecting it. Tool calls keep ExAgent's argument codec, so tool history stays
exact. A conversation that only uses one model and route is sent exactly as
before. Fallback skips a candidate whose optional preflight reports a history
target mismatch, without IO or retry telemetry. A persisted backup conversation
can therefore continue with that compatible model. If all candidates mismatch,
the request fails; malformed history and other configuration errors remain
terminal.

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

## Finish at the step limit

By default a run that reaches `max_steps` fails with `:max_steps_exceeded`.
With `on_max_steps: :final`, the last allowed step asks for an answer instead:

```elixir
agent = ExAgent.new(model: model, tools: tools, max_steps: 8, on_max_steps: :final)
```

In step `max_steps` the function tools stay declared but cannot be called (the
model gets `tool_choice: none`, or the output tool for structured output), and
that request alone ends with a user instruction saying the limit was reached.
The instruction is not added to the conversation history. If the model still
calls a function tool, the call is not executed (it gets a `not_executed`
return) and the run fails with `:max_steps_exceeded`. The run never makes more
than `max_steps` model requests.

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

An incomplete response stays in `RunError.partial.pending_response`, outside
executable history. Its duplicate in `RunError.reason` may carry an explicit
`payload_omitted` marker when that error copy would exceed 4 KiB. Read the cause
from the bounded RequestError and diagnostic partial data from RunError;
neither authorizes tools or proves that a turn completed. Arbitrary oversized
error control still fails the original retention limit.

API: `ExAgent.Models.ReqLLM`,
`ExAgent.Models.Fallback`,
`ExAgent.Model`,
`ExAgent.ModelSettings`.
