# Upgrade from ExAgent 1.x to 2.0

ExAgent 2 changes model configuration, operational failures, streaming, events,
accounting and persistence contracts. Upgrade the application's dependency and
review each boundary it uses before resuming existing conversations or jobs.

## Update the dependency and environment

```elixir
{:exagent, "~> 2.0"}
```

Use Elixir 1.18/OTP 28 or Elixir 1.20/OTP 29. Update the application lock for ReqLLM 1.27
and the declared decoder/HTTP dependency floors. When the application supplies
credentials itself, set this before startup:

```elixir
config :req_llm, load_dotenv: false
```

ReqLLM otherwise loads `.env` from the working directory. Credentials belong in
trusted application configuration, outside prompts, snapshots and trace payloads.

## 1. Run failures retain progress

Operational failures carry the original cause and last known progress:

```elixir
case ExAgent.run(agent, prompt) do
  {:ok, result} ->
    deliver_validated_output(result.output)

  {:error, %ExAgent.RunError{reason: reason, partial: partial}} ->
    record_failure(reason, partial)
end
```

The two functions are application callbacks. Update nested error patterns to
inspect `RunError.reason`; inspecting only the outer error tuple loses the cause.
Invalid construction options can still raise before execution.

Keep `partial` for reconciliation. A completed tool followed by a model failure
is not permission to repeat the tool. Live results contain configured model
state and can contain credentials; persist message codecs or deliberate safe
projections rather than the complete result/error.

An incomplete response stays outside executable history in
`partial.pending_response`. Its duplicate error copy may replace large parts with
an explicit omission marker; read the original diagnostic partial from RunError.
Neither copy authorizes a tool or proves completion.

## 2. Streaming runs the full loop

`run_stream/3` executes tools, output validation, hooks and limits. It emits
provisional `{:delta, text}` events followed by `{:result, result}` or
`{:error, %RunError{}}`. A failure is not another successful result containing an
error field. Use the validated terminal result instead of concatenating deltas
and assuming they are final output.

Creating a stream does not start a request. Each enumeration starts a new run
and can repeat effects; enumerate once. Halting closes owned resources. If your
application suspends enumeration, it owns resuming or halting that continuation.
Custom streaming Models emit a complete terminal response or an error.

## 3. Configure the ReqLLM backend explicitly

Replace legacy provider-specific wrappers with `ExAgent.Models.ReqLLM.new/1` or
`ExAgent.Model.resolve/2`. Supply instance `api_key:` and, for a gateway,
`base_url:`. Anthropic may use explicit `auth_token:` instead. Resolution alone
does not supply credentials or enable a tool/stream/native-output profile.

Tools require `:chat_tools_v1` or OpenRouter's `:openrouter_chat_tools_v1`, with
truthful Chat protocol and capability metadata. Models with reasoning enabled
require the separately supported `reasoning_mode: :none` capabilities; merely
declaring those flags cannot establish provider compatibility. See
[Models](models-and-limits.md) for constructors and routing options.

The provider sees each function's mandatory outer `arguments` object. Callers,
hooks and local tools continue to work with logical argument objects. Invalid
or truncated arguments reject before execution; no unwrapping, JSON repair or
guessing old history is performed.

OpenRouter's provider route and reasoning mode participate in static bindings
and response continuation version 4. Reusing routed history with a changed mode
or route rejects. OpenAI's supported continuation versions remain separate.
Pre-envelope or unbound routed history cannot be silently upgraded: reconcile
the old conversation and start a fresh one with the current configuration.

`zai:` resolves the stock ZAI provider. OpenCode Go/Zen require explicit gateway
specifications and endpoints; do not treat those aliases as interchangeable.
Custom implementations of `ExAgent.Model` remain supported.

### Timeouts and retention

Receive inactivity timeout precedence is request `ModelSettings.timeout`, model
`http_options[:receive_timeout]`, then 60,000 ms. Stock pool checkout also uses that
receive value; there is no separate exposed pool timeout.

`total_timeout:` bounds one buffered operation and may inherit the ReqLLM default
when nil. Streaming nil means 60,000 ms; explicit stream values are 1–300,000 ms.
Run `deadline:` is a separate absolute monotonic-millisecond admission boundary.
None of these can roll back an external effect or stop arbitrary callback descendants.

Stream limits apply after decoding: at most 4,096 public chunks, 65,536 bytes per
chunk and 1,048,576 serialized bytes across chunks. Stock decoding and upstream
queues can allocate before those checks. No hard predecode RAM guarantee or
end-to-end backpressure is provided. Streaming `max_tokens` defaults to 4,096 and
explicit values must be 1–4,096.

## 4. Validate tools and typed output locally

Tool parameters use JSON Schema and are validated before invocation. Tools can
return a value, `{:ok, value}` or `{:error, reason}`; successful values must be
JSON-portable. Use `ExAgent.ModelRetry` only for a correctable rejection. A timeout
or arbitrary execution failure cannot establish that the effect never happened.

An Ecto output schema uses tool mode by default. Native output requires agent
`output_mode: :native` and model `output_profile: :chat_json_schema_v1`.
The non-strict remote schema is a request hint; local JSON/schema validation and
the actual changeset decide success. Corrective retries spend the same request
budget. Native output does not silently fall back to tool output.

Review required/optional fields, defaults, bounds and supported schema constructs.
Unsupported adapter schemas reject rather than strengthening optional fields.
Stock Chat may discard a wire refusal beside otherwise valid JSON; the exposed
response, rather than the original wire representation, is validated.

## 5. Use scoped events and conversation ownership

Server async calls acknowledge volatile admission with a request ID. Completion
arrives through versioned `ExAgent.Event` envelopes. Derive the namespace from
authenticated application state and match both namespace and request ID.
Events are notifications; query Server history/health on reconnect.

### Minimal runtime integration recipe

The application supplies `agent`. Local PubSub and ETS need no Phoenix or database;
ETS does not survive loss of its table owner or VM.

```elixir
alias ExAgent.{Event, PubSub, Server}

namespace = "workspace-a" # obtained from authenticated application context
conversation_id = "conversation-1"
pubsub = PubSub.normalize(:local)
:ok = PubSub.subscribe(pubsub, Event.agent_topic(conversation_id, namespace))
{:ok, server} = Server.start_link(
  agent: agent,
  agent_id: conversation_id,
  namespace: namespace,
  pubsub: pubsub,
  store: :ets,
  max_pending: 2
)
{:ok, request_id} = Server.send_message(server, "Hello")
%{server: server, namespace: namespace, request_id: request_id,
  cancel: fn -> Server.abort(server) end}
```

For Phoenix use `{ExAgent.PubSub.Phoenix, MyApp.PubSub}` after starting the host's
PubSub. Keep the same topic/envelope checks. Repeated abort is harmless, but
closing a UI caller does not itself prove an admitted external effect stopped.

## 6. Migrate snapshots and persisted approvals deliberately

Snapshots hold portable data; restore obtains live models, tools, policy and
codecs from trusted application templates. Restore validates structure, version,
namespace, identity and bindings. Missing data can start a new conversation;
corrupt, future or mismatched data fails. Preserve and reconcile old snapshots
instead of silently replacing rejected data with an empty conversation.

With a Store, positive completion acknowledgement follows a confirmed save.
`CheckpointError` retains the new state and blocks further mutations while dirty.
Retry `Server.checkpoint/1` or `Session.checkpoint/1` to save that same transition;
do not run the prompt, tool or state-change callback again.

Applications provide their Repo/database lifecycle for `Store.Postgres` and run
`Store.Postgres.migrate/1`. A typed Session supplies `shared_state_codec:` on
every start; stored bytes cannot choose its module. Keep encoding/decoding pure.

Persisted approval uses a stable execution ID, scoped Store, trusted versioned
references, codecs and current authorization. Persisting a decision performs no
effect. Resume revalidates the current definitions and executes the approved
cursor. Completed steps are data, not replay instructions. After owner loss,
explicit recovery and effect reconciliation determine what may execute next.
See [Durability and approvals](durability-and-approvals.md) and
[Continuation jobs](../development/continuation-jobs.md).

## 7. Keep accounting quality and observability ownership

Request/tool counts are exact host admissions. Tokens retain declared normalized
or reported quality, costs are estimated cents and missing values remain unknown.
Parent totals include descendants; do not add inclusive parent and child totals.
Strict token/cost limits reject normalized accounting. Opt into estimated
thresholds with a finite request limit if that contract fits your application.

Native OpenTelemetry is optional. The application owns its SDK, processors and
exporter. Use `ExAgent.Observability.ReqLLM.attach/1` once when also tracing ReqLLM
calls: ExAgent produces its run/model spans and the bridge enriches them.
Replace a separate stock ReqLLM bridge rather than attaching both.
Content remains off unless an explicit redactor is configured.

For metrics, tracking maintenance, transport ownership and callback/ingestion
counters, follow [Observability](observability.md). Traces are not a billing ledger.
