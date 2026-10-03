# Official MCP SDK interoperability

This opt-in harness starts synthetic localhost peers with the **official Python
`mcp==2.2.0` SDK** and exercises ExAgent's real `MCP.Client`, generated `Tool`s,
schema validation, deterministic model and permission boundary. It replaces the
dependency on missing historical `/tmp` runners, without adding a library dependency.

From the repository root, with project dependencies and isolated Hex tooling
already available:

```bash
python3 test/support/mcp_sdk_interop/run.py --profile all
```

On this workspace, first use the runtime PATH and isolated `MIX_ARCHIVES`/
`MIX_REBAR3` described in [environment.md](../../../docs/development/environment.md).
The runner gives Mix private homes and Rebar cache, uses `EXAGENT_OFFLINE=1` and
`MIX_ENV=test`, and runs the explicitly selected ExUnit probe with
`mix test --warnings-as-errors`, compiling the current sources. The `.exs` probe
does not match normal `*_test.exs` discovery. It does **not** bootstrap Hex,
fetch Elixir dependencies, repair global tooling or run paid providers. Its Mix
invocation owns the configured build; do not run it alongside another owner of
the same sources/build/dependency cache. `MIX_BUILD_PATH` and `MIX_DEPS_PATH` can
be supplied explicitly when an independently isolated checkout requires them.

No arguments exits 2 with usage. `--list` exits 0. Neither starts Mix, installs
the SDK, creates artifacts or accesses the network. A selected profile is an
explicit opt-in to SDK preparation and local transport execution. Missing SDK,
tooling, failed assertions and cleanup failures return nonzero: there are no
skips, profile substitutions or fallback peers.

## Profiles

| Selector | MCP revision | Transport | Session |
| --- | --- | --- | --- |
| `stdio` | `2024-11-05` | SDK stdio | No HTTP session |
| `http-json-session` | `2025-06-18` | SDK Streamable HTTP, JSON | Negotiated |
| `http-json-stateless` | `2025-06-18` | SDK Streamable HTTP, JSON | Stateless |
| `http-sse-session` | `2025-06-18` | SDK Streamable HTTP, SSE | Negotiated |
| `http-sse-stateless` | `2025-06-18` | SDK Streamable HTTP, SSE | Stateless |

Select one, repeat `--profile` for a subset, or use `--profile all` for these five.
This explicitly preserves the bounded SDK receipt recorded in the roadmap; it
does not select the SDK's newer MCP protocol by default. SSE here is the response
form of Streamable HTTP, not the retired standalone SSE transport.

The HTTP client has request/response/line/event caps of **65 KiB**, pending and
discovery caps of **4**, 5 s request deadlines and 2 s control deadlines. Its
application-owned Finch pool has four HTTP1-only connections. Stdio retains its
8 MiB frame/128 pending defaults. These are host post-delivery bounds, not an
upstream RAM guarantee, aggregate stress test or HTTP2 qualification.

## Preparation and evidence

Each invocation creates a fresh `exagent-mcp-sdk-*` directory under the OS temp
directory; `--artifacts-parent PATH` selects an existing parent. It installs a
private venv from PyPI using wheels only and checks the SDK and `mcp-types` wheels'
published SHA256 and every installed `mcp/`/`mcp_types/` file against them. SDK files are never patched or
vendored. Resolver output for dependencies is captured in `dependencies.txt`;
those dependency versions are recorded per run, rather than claimed as a pinned
cross-platform lock. `pip check` is mandatory.

To prepare offline from an already downloaded complete wheelhouse:

```bash
python3 test/support/mcp_sdk_interop/run.py --profile all --wheelhouse /absolute/path/to/wheels
```

`--wheelhouse` uses `--no-index`, so an incomplete wheelhouse fails instead of
fetching a fallback. `--prepare-only` validates package provenance, APIs and
schemas without starting transports or Mix. Its report says
`interop_executed: false`, `passed: false`; successful preparation never certifies
ExAgent interoperability. Python 3.10+ and POSIX process groups are required.

The full run verifies discovery/schema preservation, exact integer request and
reply IDs, Unicode/newline argument round trips, allow/deny/ask (with and without
approval), rejection of invalid arguments before network IO, SDK tool errors and
one remote effect per accepted token. Peers do not deduplicate effects. HTTP also
checks negotiated revision, JSON/SSE content type, stable session headers, empty
202 initialized acknowledgement, DELETE on sessionful close and absence of GET.
An oversized SDK response must return the specific host limit error, followed by
a successful fresh call. It checks empty Client pending/workers, Client/Port death,
peer process exit and closed loopback listeners. Any HTTP SIGKILL fallback
or surviving stdio process fails the run.

`report.json` is the receipt, supported by `mix.log`/`.exit`, per-profile
`result.json`, unmodified SDK observation journals, peer logs, source manifests,
wheel provenance and dependency versions. The ASGI observer passes every byte
and message through; its JSON/SSE audit decoder never serves a peer or replaces
the SDK or ExAgent transport. Source changes during execution invalidate the run.
All data is synthetic. The child environment is an explicit tooling allowlist;
the runner never reads `.env` or copies provider credentials, auth or proxy settings.

## Limits and official references

This is bounded offline interoperability evidence, not closure of R7.4/A9/R7/G4.
It does not qualify OAuth, TLS, C7 endpoint/principal binding, cancellation/late
reply/reconnect/chaos, other SDKs or protocol revisions, production services, SQL
or multileaf composition. Existing local negative tests remain separate evidence.

APIs were checked against the official 2.2.0 wheel and these primary sources:

- [Official SDK and PyPI 2.2.0 files/provenance](https://pypi.org/project/mcp/2.2.0/#files)
- [Official companion wire types and PyPI 2.2.0 files/provenance](https://pypi.org/project/mcp-types/2.2.0/#files)
- [SDK repository](https://github.com/modelcontextprotocol/python-sdk)
- [Legacy-client serving and session configuration](https://py.sdk.modelcontextprotocol.io/run/legacy-clients/)
- [MCPServer Context and exact request metadata](https://py.sdk.modelcontextprotocol.io/handlers/context/)
- [Observation middleware](https://py.sdk.modelcontextprotocol.io/advanced/middleware/)
- [ASGI app lifespan](https://py.sdk.modelcontextprotocol.io/run/asgi/)

The SDK's observation middleware is documented as provisional, so the harness
pins 2.2.0. Changing that pin or adding profiles requires explicit verification;
the runner never silently upgrades it.
