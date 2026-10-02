# MCP tools with persisted approval

Ordinary MCP calls need no new options. To use a discovered tool with persisted
continuation, give Client explicit, non-secret host identity references:

```elixir
{:ok, client} = ExAgent.MCP.Client.start_link(
  transport: :streamable_http,
  url: "https://mcp.example.invalid/service",
  finch: MyHTTP1Pool,
  headers: [{"authorization", "Bearer " <> credential}],
  continuation_binding: %{
    endpoint: %{"id" => "inventory-service", "version" => "1"},
    principal: %{"id" => "tenant-account-123", "version" => "1"}
  }
)

{:ok, tools} = ExAgent.MCP.Client.tools(client)
agent = ExAgent.new(model: model, tools: tools)
```

Configure Finch's application-owned HTTP1-only pools and the ordinary transport
limits as before. Run/pause/get/decide/resume use the existing Continuation API and
host definition/policy/model refs and codecs. A committed approval is checked
against the currently reconstructed tools before new model/tool IO. Changed
endpoint, principal, transport, protocol or reference rejects with
`:continuation_tools_changed`, leaving the approved record available to its
original trusted definition. This does not add another approval path or retry an
uncertain effect.

The host chooses identity. `endpoint` identifies an externally stable service
definition; `principal` identifies the authority under which remote tools execute,
not the human approving the call. Use explicit id/version strings and update the
reference when its semantics change. A reference does not authenticate a peer or
establish that credentials belong to that principal; the host must enforce those
associations. Never put secrets in these references, infer a principal from an
Authorization header, or strip the private Tool metadata.

To rotate credentials for the same principal, start a new Client with the same
endpoint URL and identity references and new headers, discover tools, reconstruct
the trusted definition and resume with the existing reference. The new Client PID
and HTTP session do not change the persisted fingerprint. If credentials now
represent another principal, update its reference and obtain a new approval under
a new execution. A completed or uncertain call is not automatically replayed.

HTTP binds the effective public URL through SHA256 independently of the declared
endpoint reference. It normalizes URI host case, default ports and an empty path
to `/`, without DNS lookup or broader path equivalence. Binding rejects userinfo,
query and fragment before transport startup to keep URL credentials out of
authority. Move auth to headers for this mode. Ordinary unbound HTTP keeps its
existing query support. No URL literal, headers, secrets, Finch name, PID or session
ID enters the binding.

Stdio uses the same `continuation_binding` option. The host endpoint reference must
identify the command/arguments/environment's semantics because those values may
contain secrets and are not persisted. Stdio binds `:protocol_version` (default
`2024-11-05`) and requires that revision in the initialize reply before completing
the handshake. A mismatch returns `:mcp_protocol_binding_mismatch`. This equality
check does not qualify every possible MCP revision or authenticate the executable.

Protocol/Client tools without a trusted reference remain usable for ordinary
calls; persisted selection fails `:tool_continuation_binding_required` before
model/tool IO. Initial Store create/claim may already have occurred, following
existing tool-selection order. Malformed explicit identity options return
`:invalid_mcp_continuation_binding` before transport startup. Local tools with
`execution_binding: nil` retain their exact historical fingerprint.

Historical MCP approval rows did not identify the target/principal. They cannot
be silently upgraded by assigning the current target: a bound tool has a different
fingerprint. Start a new bound execution and obtain its explicit approval. Existing
local snapshots/descriptors do not require migration. Tool schemas, descriptions,
argument validation, permissions and effective-argument checks remain independent
authority and are still revalidated on resume.

The dedicated offline tests are:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix test \
  test/exagent/mcp/continuation_binding_test.exs \
  --seed 0 --warnings-as-errors
```

They use deterministic models, real loopback HTTP and a test-only single-writer
disk Store across five fresh VMs. Set `EXAGENT_MCP_BINDING_ARTIFACTS` to a private
artifact parent to retain their serialized records/phase receipts; otherwise the
temporary directories are removed. This demonstrates bounded host binding and
byte recovery, not production SQL, peer authentication, OAuth/TLS, cloud providers
or multileaf C7 acceptance. The twelve-path integration passes its eleven-case
focal on the combined physical freeze, after the delegation delta. The single
R7 integration review found no concrete additional MCP blocker in that profile;
its receipt and remaining qualifications are in the [roadmap](roadmap.md).
