# ExAgent 2.2.3

Maintenance patch refreshing the model catalogue and transitive error library.
ExAgent's runtime sources, public APIs, persisted formats and dependency
requirements remain unchanged.

- LLMDB 2026.10.6 → 2026.10.7: new catalogue entries and refreshed metadata.
- Splode 0.3.2 → 0.3.3: fix error-variable keys when deserializing JSON.
- All 45 locked packages reviewed; Zoi and gproc remain at the newest versions
  permitted by their stock parent dependencies. ReqLLM stays at 1.29.0.

The catalogue adds 609 IDs, removes 501 and changes metadata for 4,674 retained
IDs. Review selected models, prices, limits and capabilities. Explicit model
specs remain available for verified application-owned metadata. New catalogue
entries do not imply new qualified provider transports or tool profiles.

```elixir
{:exagent, "~> 2.2.3"}
```

Existing applications own their lockfiles. Run
`mix deps.update exagent llm_db splode` to adopt these transitive updates.
Keep persisted continuation mismatch checks intact when changing models.

Validation: 2,320 offline tests pass (28 provider/PostgreSQL exclusions), plus
76 focused tests and 16 installed-consumer contracts on Elixir 1.18/1.20.
The dependency audit is clean. Strict consumer diagnostics retain the known
upstream TOML/WebSockex warnings. Details are in `docs/development/dependencies.md`.
No new paid-provider or external PostgreSQL qualification is claimed.
