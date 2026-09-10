# ExAgent Development Guidance

Before making changes, read `docs/architecture/design.md` (especially sections
2.1-2.3), `docs/development/roadmap.md`, and `docs/changelog.md`.
Use `docs/README.md` as the documentation index and `docs/status.md` for the
accepted baseline. Archived plans and prompts are historical, not active tasks.

- Build a high-quality, provider-extensible Elixir agent framework. Application
  examples motivate general improvements; they must not dictate domain-specific
  behavior in the library.
- Preserve compatibility when practical. Justified breaking changes are allowed;
  cosmetic API churn and speculative abstractions are not.
- For contract changes, document the demonstrated problem, general benefit,
  alternatives, observable impact, migration, and verification in
  `docs/architecture/design.md` and `docs/changelog.md`. Follow SemVer for published contracts.
- Consider schemas, defaults, errors, events, persisted snapshots and lifecycle
  semantics as contracts, not only function signatures.
- Prefer one coherent design. Compatibility layers need a concrete consumer or
  migration need and a retirement criterion; do not add permanent duplicate modes
  merely to avoid acknowledging a necessary breaking change.
- Consolidate and test the foundation before expanding features. Once reviewed
  contracts are stable, prefer additive extensions and planned deprecations.
- Update `docs/development/roadmap.md` after a unit of work. Distinguish implemented behavior,
  verification evidence, limitations and future goals.
- Preserve existing worktree changes. Do not publish to Hex, bump a version,
  commit, or modify consumer applications without an explicit request.
- Use `apply_patch` for manual edits. For offline runtime verification use
  `EXAGENT_OFFLINE=1 MIX_ENV=test mix test`; do not silently run paid-provider
  tests or assume an offline suite proves real-backend compatibility.
- For local tooling, read `docs/development/environment.md`; the shared Hex
  incident is not permission to modify global configuration. Keep current guides
  separate from dated records under `docs/archive/`.
