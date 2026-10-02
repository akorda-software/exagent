# R7.4a — Streamable HTTP owner implementation

## Current delta — portable SDK and durable identity (2026-10-01)

The SDK harness is now maintained in `test/support/mcp_sdk_interop/` and its five
declared profiles pass in a physical private build. Durable MCP tools now require
trusted target/principal references: see [the binding guide](mcp-continuation-binding.md)
and design8.43. The combined binding focal passes11/11; the single integration
review found no concrete additional MCP blocker in that bounded profile.
Receipts, hashes, the retrieval P2 correction and remaining qualifications are in
the current [R7 roadmap receipt](roadmap.md). This does not qualify a final package,
OAuth/TLS, other SDK/protocol profiles, SQL or cloud ingestion. Earlier open-binding
statements below describe their dated snapshots, not current missing code.

## Current receipt — integrated, bounded offline acceptance (2026-09-28)

The parent accepted the ROOT integration after reviewing diff/docs, checking
377/377 manifest files and confirming9/9 delivered paths byte-identical to the
private snapshot. Parent ROOT review:77 passes (8 intact probes+69 adjacent),
20.9s, WA48seed37556, exit0. Owner FULL1467 passes/28 excluded/508.9s remains
separate evidence; this documentation receipt runs no new runtime tests.

Owner report: `/tmp/opencode/exagent-integration-mcp-qlq7ladh/REPORT.md`, SHA256
`9b192949fa5a68988909f8766d278052d4bfcb7351679b3f8efeb996f9f3a208`.
Parent evidence: `parent-review.{command,log,exit}` in that same directory.
See the [roadmap receipt](roadmap.md) for acceptance and integration provenance.
The9/9 byte comparison predates this document's receipt edits; sealed artifacts
retain the original document. R7.4/A9, persisted C7 endpoint/principal binding,
independent SDK interoperability, G4 and general R6 remain open.

Usage and limits below describe the integrated transport. The private delivery
note and parent proposals are preserved as history, not pending integration work.

## Historical private delivery note — superseded by the receipt above

2026-09-28, private snapshot; fresh review/integration pending. This supersedes
the preflight-only proposal in this file. The preflight's sealed report, patch,
manifests and logs remain intact in the sibling artifacts directory. New evidence
is under `artifacts/transport/`. R7.4/A9 are not closed by local fixtures.

## Public usage and trusted configuration

```elixir
# In the application's supervision tree, not ExAgent.Application:
{Finch, name: MyApp.MCPFinch,
 pools: %{default: [protocols: [:http1], size: 8, count: 1]}}

{:ok, client} = ExAgent.MCP.Client.start_link(
  transport: :streamable_http,
  url: "https://mcp.example.invalid/mcp",
  finch: MyApp.MCPFinch,
  headers: [],
  timeout: 5_000,
  max_pending: 128
)
{:ok, tools} = ExAgent.MCP.Client.tools(client)
# Pass tools to ExAgent.new/1 to use normal schema/permission validation.
:ok = ExAgent.MCP.Client.close(client)
```

The application owns the Finch instance and **must configure HTTP1-only pools**
for this endpoint. This is a trusted precondition, not inferred from metrics and
not enforced by inspecting Finch internals. Public `find_pool/2`/metrics cannot
certify ALPN; `start_pool/3` success does not reconfigure existing pools. At least
two free connections are needed for a server request during an SSE response;
size for expected concurrent requests plus control traffic. Saturation is bounded
by deadlines and returns an error, not an automatic retry.

No Application/mix/lock changes. Stock Finch0.22 `build/4` and `stream_while/5`
are used; no Req pipeline, HTTP redirects, automatic POST retry, wire fork or
private Finch API. HTTP2 behavior is outside the supported configuration.

## Protocol and observable errors

- MCP2025-06-18 only for HTTP. Initialize version/capabilities/serverInfo validate
  before initialized POST; initialized must return202 with an empty body. Ready
  and session are installed by Client only after both operations succeed. Stdio
  remains2024-11-05 and `protocol.ex` remains byte-identical.
- Subsequent requests carry MCP-Protocol-Version and, when negotiated, the session.
  URL userinfo/fragments, reserved custom headers and CR/LF injection reject.
  Sessions must be nonempty visible ASCII33–126, unique in response headers and
  bounded. A later response cannot replace the session. Stateless servers work.
- JSON accumulates incrementally within a byte cap and decodes at EOF. SSE parses
  incrementally with UTF8/BOM, CR/LF/CRLF, comments and multiline data support.
   Terminal response halts the stream; it does not wait for an indefinite EOF.
   Events are delivered in wire order before scanning the next event. Once a
   terminal result/error is decoded, suffix bytes cannot invalidate it or trigger
   ping/control replies, regardless of HTTP chunk boundaries. Framing, JSONRPC
   errors and limits reached before that terminal still reject.
  No spontaneous GET, Last-Event-ID/reconnect replay, OAuth or2025-11-25 support.
- JSONRPC version and IDs match exactly (`1` differs from `1.0`/`"1"`). Result and
  error are mutually exclusive; duplicate JSON object keys and batch arrays reject.
  Remote errors expose code only (`{:jsonrpc_error, code}`), not server messages.
  Unknown request methods receive -32601; ping receives an empty result. No sampling
  or roots capability is advertised. Notifications consume control count/byte caps.
- Discovery preserves inputSchema for common Tool validation. Duplicate names,
  malformed entries, excessive count and nonnil nextCursor reject; no truncation.
  Tool results currently support text content only; nontext content rejects
  explicitly (`:unsupported_tool_content`) instead of silently dropping modalities.
- 401/403 return `:unauthorized`/`:forbidden`; other unsupported statuses return
  `{:http_status, status}`. A session404 returns `:session_expired`, invalidates the
  generation and every pending call, and clears ready/session. `Client.reconnect/1`
  starts a fresh handshake explicitly. It does not repeat previous tools.

## Authority, lifecycle and limits

Client owns pending admission, caller monitors, absolute monotonic deadlines,
unique IDs and terminal replies. Worker results require generation+ID+worker PID;
stdio messages cannot complete HTTP requests. No HTTP IO runs inside GenServer.
Each HTTP worker has a separate owner/worker/deadline guardian. Caller death,
timeout, close and untrappable Client/owner kill release workers and HTTP1 sockets.
Progress never renews a deadline; the guardian still enforces it when Client is
suspended, and Client rejects late nominal successes when resumed.

Timeout/caller death sends a bounded best-effort cancellation, including for
stateless sessions, but never for initialize. Outstanding cancellation workers have
their own cap/deadline and are killed on close/invalidation. A sessionful close
attempts bounded DELETE;405 is accepted. DELETE failure/timeout returns an error
and still stops Client. Killing Client does not promise a remote DELETE or rollback.
Transport timeout/disconnect leaves the remote effect uncertain, not replayable.

All options below are positive integers. Session/header/name/auth configuration
belongs to the trusted host; URL length is capped at8192 bytes. Byte caps count
encoded bytes, not codepoints. Bounds are inclusive.

| Option | Default | Scope |
|---|---:|---|
| timeout | 5000ms | Total request/handshake deadline |
| max_pending | 128 | Client pending requests, before encoding/IO |
| max_request_bytes | 1048576 | Encoded outgoing body |
| max_response_bytes | 1048576 | Cumulative response body, including SSE metadata through the first terminal |
| max_line_bytes | 65536 | SSE line excluding delimiter |
| max_event_bytes | 262144 | Joined SSE data lines including inserted newlines |
| max_header_bytes | 16384 | Custom configuration headers; response headers+trailers |
| max_session_bytes | 256 | Negotiated session value |
| max_tools | 256 | Discovered catalog cardinality |
| max_controls | 16 | SSE control messages per response |
| max_control_bytes | 65536 | Cumulative incoming control data and outgoing control body |
| max_control_workers | 4 | Concurrent best-effort cancellation workers |
| control_timeout | 1000ms | Initialized/control replies/cancellation/DELETE |

Host body/carry retention is bounded and copies small retained sub-binaries.
These are post-delivery limits: Finch/Mint may allocate a chunk/headers first,
and JSON encode/decode temporarily allocates. No hard upstream RAM cap is claimed.
Aggregate request retention scales with max_pending and configured byte caps.
The caller/BEAM mailbox is not a public untrusted-network ingress API.

Client diagnostic state/message/logs redact HTTP configuration/session. Adapter
errors omit raw URL/header/session/server-error content. The application must keep
Finch telemetry handlers from exporting raw requests: that instrumentation is
outside the adapter's ownership. Ordinary tool output may contain application data.

## Tools, persistence and open acceptance

`call_tool/3` is low-level IO, not runtime authorization. Discovered tools enter
normal JSV validation, allow/ask/deny and the existing runtime. Real TCP tests
exercise those permissions and failed checkpoint→save-only retry with one remote
effect. Synchronous `ask` is not persisted C7 acceptance.

The preflight demonstrated that otherwise equal Tools with different endpoint/
principal closures have equal continuation fingerprints. Automatic C7 target
binding remains unqualified. Existing host definition/policy references are a
direction to qualify separately, not an invented guarantee. No Tool/Frame/runtime/
continuation seam was changed, and HTTP session IDs are never persisted authority.

Local tests include real HTTP1 bytes, JSON/SSE handshakes, framing splits, auth/
session isolation, errors, exact/+1 bounds, concurrency/admission, close/cancel/
caller death/owner kill, suspended Client deadlines,404/stale result/no replay,
permissions and checkpoint retry. The server fixture is implementation-controlled:
an independently maintained SDK/server interoperability run is still required.
Durable MCP pause/restart/decision/resume with trusted target binding is also open.

## Historical proposed parent documentation updates (private delivery)

The following proposals retain their original evidence and then-pending status.
The current acceptance is recorded above and in the roadmap.

### Historical P2 SSE segmentation correction — owner verified, fresh review pending then

Review reproduced terminal+257-byte comment with max_line_bytes256: split HTTP
chunks succeeded, coalesced failed. Eager whole-chunk framing discarded completed
events on a later error. The internal parser now exposes `next/2`, yielding one
event and borrowed remainder; the transport decides whether to continue before
scanning more. `feed/2` remains a full-input framing collector used by parser tests;
its historical error oracle is intact, not used for terminal-aware transport.
Scanning still uses binary delimiter search per line, not byte-at-a-time feeding.
No whole-response event list is retained by the SSE transport.

The response byte budget bounds the scan prefix and counts consumed bytes through
the terminal delimiter (CR alone already terminates a line; a following LF belongs
to the unread suffix). A suffix beyond that point is neither parsed nor charged;
all preterminal metadata/data remains charged. This restores the documented halt
contract instead of increasing limits or accepting malformed preterminal data.
No public API/configuration migration or persisted format change is required.

Permanent regression coverage adds all two-part parser partitions, real HTTP1
coalesced/fragmented/terminal-split responses, UTF8/line/event/JSON errors, exact
and minus-one response budgets, preterminal notifications/errors, control limits,
ping ordering, terminal JSONRPC errors and observed socket/pending cleanup.
Receipts, immutable reviewer-probe reruns and cumulative original-baseline patch
are in `artifacts/fix-sse/`. Parent roadmap proposal: P2 owner-corrected and locally
verified, awaiting independent revalidation; R7.4/A9, C7 target binding and SDK
interoperability remain open. Design/changelog/status/roadmap files are outside
this worker's allowlist; integrate their proposal only under parent ownership.

### Historical transport proposal

1. **Design:** record additive HTTP transport with Client authority/HTTP1 trusted
   configuration, bounded postdecode ownership, explicit failure/no replay, and
   text-only/pagination rejection. Stock Finch was chosen over an adapter that
   materializes SSE before host limits. Dedicated C7 binding remains separate.
2. **Changelog:** announce the above opt-in API only after review; describe errors,
   `reconnect/1`, pool configuration, conservative unsupported profiles and close
   error return. Existing stdio consumers need no migration; HTTP users configure
   an app-owned pool. No nominal version bump or publication occurs here.
3. **Roadmap:** R7.4a owner-implemented/local-tested pending review, R7.4/A9 still
   open for independent interoperability and MCP C7 acceptance. Preserve the
   preflight evidence as historical rather than relabeling its72/81 passes.
4. **Status:** record the final transport receipt counts/hashes after fresh review;
   never present this local fixture as independent external support acceptance.
