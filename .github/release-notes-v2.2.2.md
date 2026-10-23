# ExAgent 2.2.2

Maintenance release with an updated ReqLLM security floor and fixes for ETS,
fallback continuation and integer-backed enum schemas.

## Dependencies and compatibility

- Require official ReqLLM `~> 1.29.0`, which fixes
  [GHSA-6vww-5m28-f26v](https://github.com/agentjido/req_llm/security/advisories/GHSA-6vww-5m28-f26v).
  The advisory affects ReqLLM WebSocket TLS verification; ExAgent uses the
  unaffected HTTP/Finch transport.
- Update the checkout to LLMDB 2026.10.6 and the test-only TLS certificate bundle
  to 1.36.0. Zoi and gproc remain within their parents' supported requirements.
- LLMDB has removed catalogue entries. Applications must review their selected
  models or supply explicit model specs with verified capabilities, limits and
  prices. A resolved unknown ID does not imply known pricing or tool support.
- ReqLLM's new implicit provider-option defaults are rejected before IO or
  continuation binding. Configure supported options explicitly on the ExAgent
  model so request routing and persisted authority remain aligned.

## Fixes

- Connected BEAM nodes can start their own ETS store; data remains local to each
  node. Connecting already running nodes preserves their independent stores.
- Fallback can resume valid backup history through a compatible candidate in
  synchronous and streaming requests, skipping incompatible models before IO.
- Integer-backed `Ecto.Enum` schemas use JSON integers; custom enum restrictions
  use the same vocabulary as their mappings.

## Upgrade

```elixir
{:exagent, "~> 2.2.2"}
```

Update the application's ExAgent/ReqLLM/LLMDB lock entries. Regenerate cached
schemas for affected enums. Persisted continuations with an old affected output
schema retain their mismatch rejection: finish with the original definition or
start a new execution after reconciling prior effects. Do not rewrite approvals
or bypass fingerprint checks. No snapshot format migration is introduced.

## Verification

- 2,320 offline tests pass; 28 provider/PostgreSQL tests are intentionally excluded.
- 40 installed-consumer contracts pass across Elixir 1.18/OTP28 and 1.20/OTP29,
  including the optional API, SDK and exporter graphs. Separate strict dependency
  diagnostics retain known TOML/WebSockex compiler warnings.
- Formatting, strict project compilation, documentation links, package isolation
  and release guards pass. Hex audit reports no retired or advisory packages.

No new live-provider, database or external-backend qualification is claimed.
