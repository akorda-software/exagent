# ExAgent 2.2.1

Compatible maintenance release. Public APIs, defaults, runtime, events, history
and persisted snapshots are unchanged from 2.2.0.

## Dependencies

- Require JSV `~> 0.26.1` (previously `~> 0.26.0`). The patched validator's
  stricter date/time formats do not alter ExAgent's annotation-only handling.
- Retain LLMDB 2026.10.3 in the checkout lock: the newer catalog removes existing
  entries and their pricing/limit metadata. Consumer LLMDB ranges are unchanged.
- No forced gproc override; its test-only parent still requires 1.2.x.

## Upgrade

```elixir
{:exagent, "~> 2.2.1"}
```

Update the application's ExAgent/JSV lock entries. No code or data migration is
required. Review model selection before independently updating LLMDB; a library's
lock does not pin transitive versions in consuming applications.

## Verification

- 2,307 offline tests pass; 28 provider/PostgreSQL tests intentionally excluded.
- Eight installed-consumer contracts pass. Known upstream compiler warnings remain
  visible in the separate strict dependency diagnostic.
- Documentation, package isolation and compatibility checks pass.

No new live-provider, database or external-backend qualification is claimed.
