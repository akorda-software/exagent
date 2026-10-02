# ExAgent Development Guidance

At session start, read design sections 2.1-2.3, the roadmap board and current
changelog/status headers; then read only the contract/source sections needed for
the objective. Do not repeat whole-document/history reads at every checkpoint.
Use `docs/README.md` as the index. Archived plans/prompts are evidence, not tasks.
The current entry is `docs/prompts/continue-native.md`; the execution policy is
`docs/development/execution-flow.md` (user decision 2026-10-01): functional objectives,
at most one independent review, no re-review chain or routine parent reruns.

For the v2.0.0 implementation, use `docs/development/release-scope.md` and
`docs/development/production-acceptance.md` with roadmap R0–R9. The user explicitly
included persisted approval/continuation (C7) on 2026-09-21, superseding its earlier
deferral. `docs/prompts/implement-v2.md` is the prepared execution mandate; merely
reading it does not activate implementation or authorize publication.
The 2026-09-22 approved replan is design8.22: official stock ReqLLM only, no
fork/vendor/patch/monkeypatch/private wire parser or Jido runtime. Preserve the
accepted R1.2 mandatory-envelope gate; do not restart it from a dated prompt.
Keep unproven guards intact, not another R0/Jido audit. Separate exact host counters
from qualified normalized/estimated usage; bounded host postdecode retention and
cleanup remain required without promising upstream hard RAM predecode. C7 remains.
Reuse a useful implementation context; change models only on user request.
Native orchestration has no fixed researcher/worker/reviewer chain. Give the owner
causal edit scope, not per-file permission loops. Dispatched workers do not delegate
or expand their task merely from reading another prompt.

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
