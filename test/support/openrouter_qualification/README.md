# Explicit, repeatable OpenRouter qualification gate

Integrated from G2's validated portable delivery into
`test/support/openrouter_qualification/`. Its six executable files are `run.py`,
`entry.exs`, `g2.exs`, `input_budget.exs`, `synthetic.exs` and `text_probe.exs`.
No new package, runtime framework or dependency is required: Python3, Elixir and
the project's stock ReqLLM1.24 graph are already used by the validated harness.

## Running the gate

Run from the ExAgent project root with the project's ordinary verified toolchain,
deps/build and isolated Mix/Hex/Rebar environment from `docs/development/environment.md`.
The command compiles normally through `mix run`; it does not install dependencies,
repair global Hex, use a stale `--no-compile`, or copy a running mutable checkout.
Use a stable worktree/snapshot while the gate runs. Every execution computes and
rechecks its own source fingerprint over lib/config/mix/lock/README and records
runtime/model/profile/settings/budget alongside results. Optional `--source-id`
is a caller label, distinct from the independently computed fingerprint.

Choose a **new** artifact directory each time:

```sh
python3 test/support/openrouter_qualification/run.py \
  --live --dotenv .env --model openai/gpt-4o-mini \
  --artifacts /tmp/opencode/exagent-online-20260927-gpt4-01 \
  --max-admissions 30 --budget-usd 2.0

python3 test/support/openrouter_qualification/run.py \
  --live --dotenv .env --model openai/gpt-6-luna \
  --artifacts /tmp/opencode/exagent-online-20260927-luna-01 \
  --max-admissions 30 --budget-usd 2.0
```

An existing private child environment containing only the needed
`OPENROUTER_API_KEY` can be used instead of `--dotenv`. The optional dotenv loader
requires mode0600, extracts only that exact nonempty key programmatically, passes
it in memory to the child and never copies the file or prints headers/key values.
The wrapper constructs an allowlisted child environment rather than inheriting
other service keys. It redacts the key from captured process output.

**`--live` is the explicit paid opt-in, not a new human approval workflow.** Under
the user's standing authorization, run this gate for relevant model/profile
integration changes with an allocated wave budget. It does not enable paid default
tests: MIX_ENV=test/EXAGENT_OFFLINE=1 remain set and this dedicated command selects
its own live cases. With no opt-in it exits64 before key reads, artifact creation,
Mix invocation or Model/network IO. Never delete/reset an old ledger to rerun.

Without `--catalog`, a live run reads the public unauthenticated OpenRouter models
catalog and records its exact selected entry. `--catalog path.json` accepts an
explicit previously captured public snapshot with a `models` array for reproducible
offline checks or a deliberate fixed-catalog run; preserve its date/provenance.
Luna requires nonmandatory reasoning and explicit none support. Model IDs are an
allowlist; no fallback/substitution or generic forced capabilities are provided.

## Profiles, results and stopping

- GPT-4o-mini:14 text/tools/Ecto/native/empty/length cases, three surfaces;
  temperature0.0, max256/length16, original prompts/schema and public oracles.
- GPT-6 Luna: the same cases with truthful reasoning capabilities,
  `reasoning_mode: :none`, nil temperature, canonical max_tokens256/16 translated
  by the product to stock max_completion_tokens; continuation3 checks included.
- GLM5.3Flash and DeepSeek4.1Flash: **buffered text only**, truthful reasoning,
  existing stock OpenRouter provider, max256 and zero tools. They are not accepted
  by the non-reasoning tools profile. The default case is text_sync; other cases
  are rejected. Reasoning content is not logged, only public counts/usage metadata.

Optional `--cases tools_stream,native_sync` selects a relevant subset explicitly.
All model/output/tool retries remain0 and execution concurrency is1. Any failed
oracle stops the selection with exit1, preserving its result and reserved admission;
no automatic paid rerun or assertion weakening. A successful HTTP status is not
an oracle. Failed/pre-IO attempts reach the admission ledger before the inspection
hook; the hook rejects excess input without rewriting messages or arguments.

The current Luna evidence is **13/14**, with length_stream unqualified:
ExAgent safely returned invalid_tool_arguments rather than a consumable length
terminal. A separate diagnostic exposed tool_calls+args_lost. The portable gate
keeps the real-length assertion and can still exit1 on this scenario; it does not
hide the red to make normal online use appear green. The later independent terminal
priority correction does not establish or reclassify that original live terminal.

## Budget and privacy assumptions

Every new artifact directory starts its own count0/reservation0 ledger. Allocate
the overall authorized wave across model invocations; separate new directories
are not permission to exceed a shared wave budget. Defaults:30 admissions/USD2,
hard accepted CLI maxima80/USD5. Reservations per admission default to0.025GPT4,
0.05Luna,0.60reasoning text; `--reserve-usd` can raise, not lower, those defaults.
The cap is on **operational reservations**, not a promise of measured billing.

Luna's0.05 reservation was explicitly approved for this bounded synthetic input:
16KiB projected canonical input including instructions, function/output envelopes,
native schema and history, at most10 messages, max output256/length16. The source
experiment confirmed actual TCP bodies≤16KiB and boundary16384/+1 rejection before
IO. A64Ki token allowance with worst observed rates0.0000005input and0.0000015output
gives0.033152USD, rounded to0.05. The allowance is conservative operational reasoning,
**not a mathematical tokenizer bound or an invoice**. Recheck catalog/endpoint
prices and reservation assumptions when changing the target, rates or fixture.
Reasoning tokens are already included in output usage, never added again.

Artifacts contain only synthetic prompts/receipts, public semantic messages and
allowlisted metadata. No user-provided data belongs in this gate. They include
manifest, results, exact admission ledger, input measurements, summary and process
log; a refused directory reuse does not overwrite the prior log. Default offline
suite integration should only check opt-in/fixtures, never invoke `--live` silently.

## Offline checks

```sh
python3 test/support/openrouter_qualification/run.py
# expected exit64, zero Model/network/key IO

python3 test/support/openrouter_qualification/run.py \
  --offline-check --model openai/gpt-6-luna \
  --catalog /path/to/public-catalog-snapshot.json \
  --artifacts /tmp/opencode/exagent-gate-fixture-new \
  --cases tools_stream,native_sync --max-admissions 10 --budget-usd 1.0
```

The supplied worker verification used no extra live inference: no-optin64; two
Luna fixture cases3TCP/1effect with a fresh ledger3; reasoning-text fixture1TCP/
0effects with a separate ledger1; directory reuse exit1 with old ledger unchanged.
ROOT integration records its own hashes and offline executions in the unit archive,
not a relabeling of those earlier worker results. Temporary artifact paths above
are examples, not required machine-specific source IDs or runtime dependencies.
