"""Explicit paid opt-in; private child environment; optional in-memory application dotenv."""

import argparse
import os
import pathlib
import stat
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent


def main():
    if "--live" not in sys.argv and "--offline-check" not in sys.argv:
        print(
            "No Model IO: pass --live or --offline-check explicitly.", file=sys.stderr
        )
        return 64
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--dotenv")
    opts, args = parser.parse_known_args()
    live = "--live" in args
    assert not (live and "--offline-check" in args)
    assert live or not opts.dotenv, "offline checks never load dotenv"
    allowed = [
        "PATH",
        "LANG",
        "HOME",
        "MIX_HOME",
        "MIX_ARCHIVES",
        "HEX_HOME",
        "MIX_REBAR3",
        "REBAR_CACHE_DIR",
        "XDG_CACHE_HOME",
        "XDG_CONFIG_HOME",
        "MIX_BUILD_PATH",
        "MIX_DEPS_PATH",
        "ERL_FLAGS",
        "HEX_OFFLINE",
    ]
    env = {k: os.environ[k] for k in allowed if k in os.environ}
    env.update({"MIX_ENV": "test", "EXAGENT_OFFLINE": "1"})
    secret = None
    if live:
        secret = os.environ.get("OPENROUTER_API_KEY")
        if not secret and opts.dotenv:
            path = pathlib.Path(opts.dotenv)
            assert stat.S_IMODE(path.stat().st_mode) == 0o600
            values = [
                line.strip().split("=", 1)[1].strip().strip("\"'")
                for line in path.read_text().splitlines()
                if line.strip().startswith("OPENROUTER_API_KEY=")
            ]
            assert len(values) == 1 and values[0], "authorized key missing or ambiguous"
            secret = values[0]
        assert secret, (
            "OPENROUTER_API_KEY missing; use application environment or --dotenv"
        )
        env["OPENROUTER_API_KEY"] = secret
    result = subprocess.run(
        ["mix", "run", str(ROOT / "entry.exs"), *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=900,
    )
    output = result.stdout + result.stderr
    if secret:
        output = output.replace(secret, "[REDACTED]")
    if "--artifacts" in args:
        artifact = pathlib.Path(args[args.index("--artifacts") + 1])
        if artifact.is_dir():
            # Do not overwrite a prior execution's log when directory reuse is rejected.
            log = artifact / "process.log"
            if not log.exists():
                log.write_text(output)
    print(output)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
