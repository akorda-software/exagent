# Getting started

Run an agent without credentials first. This gives you a working application and
the result contract before introducing a provider, streaming or persistence.

## Install ExAgent 2.0

This guide targets **ExAgent 2.0.0**. Published 1.x releases have older contracts.
After the official 2.0 release is available on Hex, add:

```elixir
def deps do
  [{:exagent, "~> 2.0"}]
end
```

Before publication, use `{:exagent, path: "../exAgent"}` with the clone beside
your application. [Release status](../status.md) records the accepted scope.

Run `mix deps.get`, then `iex -S mix` in your application. The supported runtime
targets are Elixir 1.18 / OTP 28 and Elixir 1.20 / OTP 29. ExAgent starts its own
supervised runtime; a one-shot run needs no database, Phoenix or tracing service.

If your application manages its own environment and credentials, set this in
`config/config.exs` **before application startup**:

```elixir
import Config
config :req_llm, load_dotenv: false
```

Stock ReqLLM otherwise loads `.env` from the host's working directory.

## Run your first agent

```elixir
agent = ExAgent.new(model: "test", instructions: "Be concise.")
{:ok, result} = ExAgent.run(agent, "Hello!")

%{output: result.output, status: result.status, requests: result.request_count}
# => %{output: "a test response", status: :succeeded, requests: 1}
```

`"test"` is a deterministic in-process model. It does not interpret the prompt
or call a provider. It exercises the same public loop, so you can build your
application's handling of results before making real requests.

An agent definition is reusable configuration. A run produces history and a
possibly updated model; the definition itself does not hold a conversation.

## Keep a conversation

For an occasional follow-up, pass the previous history explicitly:

```elixir
{:ok, first} = ExAgent.run(agent, "Hello!")
{:ok, second} =
  ExAgent.run(%{agent | model: first.model}, "And next?",
    message_history: first.messages
  )
second.output
```

Retain `result.model` for stateful model adapters as well as `result.messages`.
For a supervised conversation with multiple requests, use
[Server](runtime-and-events.md).

## Handle success and failure

An operational failure includes the progress known before it failed:

```elixir
case ExAgent.run(agent, "Hello!") do
  {:ok, result} ->
    {:completed, result.output}

  {:error, %ExAgent.RunError{reason: reason, partial: partial}} ->
    {:failed, reason, partial.status}
end
```

The failure branch is application handling, not permission to retry a tool.
Keep the partial history and outcomes for reconciliation when an effect may
already have happened. Invalid construction options can raise before execution.
Live results may contain model credentials; log a deliberate projection rather
than the whole result or error.

## Connect a real model

Resolve a catalogue model for text, or explicitly configure a qualified tools
profile. [Models and limits](models-and-limits.md) explains the difference and
shows the constructor. Keep keys in application configuration, outside prompts,
source code and serialized results.

The live acceptance of GPT-4o-mini through OpenRouter covers a bounded Chat
profile. It does not qualify every model that ReqLLM can resolve. Check
[Support status](../status.md) before choosing a production combination.

## Next steps

- [Tools and output](tools-and-output.md): invoke application functions and return an Ecto struct.
- [Runtime and events](runtime-and-events.md): keep history and update a UI.
- [Testing](testing.md): script model responses and verify effects without network access.

API: `ExAgent.new/1`,
`ExAgent.run/3`,
`ExAgent.RunError`.
