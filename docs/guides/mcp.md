# Connect MCP tools

`ExAgent.MCP.Client` discovers tools from a Model Context Protocol server and
exposes them as `ExAgent.Tool` values. Use those tools through the ordinary agent
loop to retain local validation, permissions and scoped accounting.

The client supports stdio and opt-in Streamable HTTP. This page contains
**external setup recipes**, not offline examples: install/start a trusted server
and supply a qualified tools model before executing them.

## Connect a stdio server

This example uses the filesystem server already shown in the API reference.
The application chooses and owns the executable, arguments and allowed directory;
do not obtain them from the model's prompt.

```elixir
{:ok, client} = ExAgent.MCP.Client.start_link(
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "./data"],
  timeout: 5000,
  max_pending: 16
)

try do
  {:ok, tools} = ExAgent.MCP.Client.tools(client)
  agent = ExAgent.new(model: chat_model, tools: tools)
  ExAgent.run(agent, "List the allowed files.")
after
  ExAgent.MCP.Client.close(client)
end
```

`chat_model` is the application's qualified model from
[Models](models-and-limits.md). The example command may download a package;
production applications should manage and pin their chosen server separately.
Stdio uses the 2024-11-05 protocol profile.

## Supply an HTTP pool

For Streamable HTTP, the application starts its own Finch instance with
**HTTP1-only pools**. This child belongs in your supervision tree:

```elixir
{Finch, name: MyApp.MCPFinch,
  pools: %{default: [protocols: [:http1], size: 8, count: 1]}}
```

Connect to your trusted endpoint. The URL below is a placeholder:

```elixir
{:ok, client} = ExAgent.MCP.Client.start_link(
  transport: :streamable_http,
  url: "https://mcp.example.invalid/mcp",
  finch: MyApp.MCPFinch,
  headers: [],
  timeout: 5000,
  max_pending: 16
)
```

HTTP uses the 2025-06-18 profile. Size the pool for requests and control traffic;
at least two free connections are needed for a server request during an SSE
response. HTTP2 is outside the supported configuration. The library does not
inspect Finch internals to certify that the application honored this precondition.

## Own failures and cleanup

- A request timeout or caller loss drops local pending state. It does not prove
  the remote tool stopped or rolled back.
- `max_pending` limits admission; saturation returns `{:error, :busy}` before send.
- Byte limits bound frames/response retention, not arbitrary upstream traffic or
  the BEAM mailbox under a push transport.
- After a session 404, `Client.reconnect/1` explicitly starts a new handshake.
  It does not replay the previous tool request.
- `Client.close/1` closes owned transport resources. The application owns the
  external server, credentials and any external effects.

Calling `Client.call_tool/3` directly is transport IO and bypasses the agent's
approval boundary. Use generated tools in the agent for ordinary guarded calls.

## Resume an approved MCP call

Persisted continuation requires explicit non-secret endpoint/principal references
through `continuation_binding:`. These references bind identity; they neither
authenticate the peer nor persist the credentials. On resume, reconnect the
trusted client and rediscover the current inventory before validating the call.

Follow the [MCP continuation recipe](../development/mcp-continuation-binding.md)
for the complete binding. The client defaults to 128 pending requests and 8 MiB
frames; configure tighter limits when your application needs them. Use the
module reference for exact options. Verify your server's protocol and OAuth
deployment separately from the agent's local tool validation.

API: `ExAgent.MCP.Client`,
`ExAgent.MCP.StreamableHTTP`.
