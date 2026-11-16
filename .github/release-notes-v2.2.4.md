# ExAgent 2.2.4

Security and dependency maintenance patch. ExAgent runtime sources, public
function signatures and persisted formats are unchanged.

- ReqLLM 1.29.0 → 1.30.0 and JSV 0.26.1 → 0.27.0, with updated public minimums.
- JSV includes the fix for [GHSA-cvmg-hgv6-jqcp](https://github.com/lud/jsv/security/advisories/GHSA-cvmg-hgv6-jqcp).
  Regex budget exhaustion rejects tool arguments with `indeterminate_pattern`,
  including inside `not`, `anyOf` and `patternProperties`, before callable effects.
- Ecto 3.14.2 → 3.14.3, required by the published manifest to exclude
  [GHSA-cxjx-vmm2-qr8r](https://github.com/elixir-ecto/ecto/security/advisories/GHSA-cxjx-vmm2-qr8r).
- LLMDB 2026.10.7 → 2026.11.2, Zoi 0.18.11 → 0.19.0,
  NimbleOptions 1.1.1 → 1.2.0 and test-only SSLVerifyFun 1.1.7 → 1.1.9.
- All 45 locked packages reviewed; gproc and IDNA remain constrained by their
  stock parent dependencies. No overrides or vendored patches; Elixir stays at 1.18.

The catalogue adds 434 IDs, removes 258 and changes metadata for 1,802 retained
IDs. Review selected models, prices, limits and capabilities. Use explicit model
specs for verified application-owned metadata; catalogue additions do not qualify
new provider transports. Rewrite pathological regexes if valid input reaches
the matching budget. Keep persisted continuation mismatch checks intact.

```elixir
{:exagent, "~> 2.2.4"}
```

Existing applications own their lockfiles. Adopt the dependency changes with
`mix deps.update exagent req_llm jsv ecto llm_db zoi nimble_options`.

Validation: 2,321 offline tests pass, zero failures and 28 provider/PostgreSQL
exclusions; 235 focused tests and 40 installed-consumer contracts pass on
Elixir 1.18/1.20. Another 27 tool-validation cases pass against the installed
1.18 package, including regex-budget rejection. Hex audit is clean; documentation,
links, packaging and isolation pass. Strict consumer diagnostics retain stock
TOML/WebSockex/gproc warnings. The later version/prose change has separate release
checks without repeating the full suite. No new paid-provider or external SQL
qualification is claimed. Details: `docs/development/dependencies.md`.
