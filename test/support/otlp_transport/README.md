# Private OTLP transport qualification

`run.py` is opt-in. Without `--run` it exits before building, opening network
connections or reading environment/configuration. The enabled probe fetches one
official pinned commit over HTTPS, copies already-resolved dependency sources and
the processor into a fresh consumer, and compiles only that private consumer.
It neither loads `.env` nor writes root deps/build, shared toolchains or consumers.

```bash
python3 test/support/otlp_transport/run.py

python3 test/support/otlp_transport/run.py --run \
  --work /tmp/opencode/exagent-v2-codex-t6qgpstl/otlp \
  --hex-archive /tmp/opencode/exagent-v2-codex-t6qgpstl/tooling/archives/hex-2.5.1 \
  --elixir-bin /home/kukapu/.local/share/mise/installs/elixir/1.20.0/bin \
  --erlang-bin /home/kukapu/.local/share/mise/installs/erlang/29/bin \
  --rebar3 /home/kukapu/.local/share/mise/installs/elixir/1.20.0/.mix/elixir/1-20-otp-29/rebar3
```

Adjust the explicit toolchain/archive paths for a different host. An existing
untouched official checkout at the exact pin can be supplied with
`--official-checkout`; no checkout of the root project occurs. Dependencies must
already exist under root `deps/`; their sources are copied, not symlinked, and all
Mix/Rebar homes, caches, sources and outputs are private. The runner limits builds
to180s and the probe to45s; timeout kills only the process group it created.

Each fresh consumer keeps `commands.jsonl`, dependency/build/probe logs,
`report.json`, and exact compiled source hashes. The checked-in
`receipt-2026-10-01.json` preserves the synthetic final report even after `/tmp`
cleanup. It is evidence for the stated profile, not a golden count or future gate.

The recipe is experimental and loopback-only. Read
[`docs/development/otlp-transport.md`](../../../docs/development/otlp-transport.md)
for public APIs, byte/callback/cleanup limits, warnings and remaining gates.
# Disposable VM continuation

The new opt-in `run_isolated.py` uses the same tooling arguments as `run.py` and
adds a physical ExAgent source freeze. It exercises actual Test-model run/tool,
persisted approval/resume through public codecs, and a shared one-VM admission
gate. See [the ownership contract](../../../docs/development/otlp-isolated-transport.md).
The original `receipt-2026-10-01.json` remains the earlier gRPC experiment.
The packaged recipe lives under `examples/otlp_transport/`; the new
`receipt-isolated-2026-10-01.json` records8 cases, C7 pause/resume and3 measured cycles.
