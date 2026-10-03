#!/usr/bin/env python3
"""Causal binary-IPC regression control, without SDK/network/private payloads."""
import argparse
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import time
sys.dont_write_bytecode = True
from api import BoundaryError, private_json
from run import Owned, closed_env, require, wait_owned


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run", action="store_true")
    p.add_argument("--elixir-bin", type=Path)
    p.add_argument("--erlang-bin", type=Path)
    p.add_argument("--work", type=Path)
    args = p.parse_args()
    if not args.run:
        print("Skipped: explicit binary-IPC control required. No runtime/network/key access.")
        return
    os.umask(0o077)
    require(args.elixir_bin and args.erlang_bin and args.work, "packet4_control_arguments")
    results = []
    for size, binary in [(22447, False), (29917, False)] + [(s, True) for s in (22447, 29917, 32706, 32735, 32736, 32752, 65536)]:
        code = (":ok = :io.setopts(:standard_io, [:binary, {:encoding, :latin1}]); " if binary else "")
        code += f"<<{size}::unsigned-big-32>> = IO.binread(:stdio, 4); IO.binwrite(:stdio, \"PACKET4_OK\")"
        env = closed_env(elixir_bin=args.elixir_bin.resolve(), erlang_bin=args.erlang_bin.resolve())
        env.update(PATH=f"{args.erlang_bin.resolve()}:{args.elixir_bin.resolve()}:/usr/bin:/bin",
                   ERL_FLAGS="+S 2:2 +A 1")
        owner = Owned([str(args.elixir_bin / "elixir"), "-e", code], cwd=args.work, env=env,
                      stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        started = time.monotonic()
        timed_out = False
        try:
            owner.process.stdin.write(struct.pack("!I", size))
            owner.process.stdin.flush()
            try:
                exit_code = wait_owned(owner, seconds=2)
            except BoundaryError as error:
                require(str(error) == "owned_command_deadline", "packet4_unexpected_boundary")
                timed_out, exit_code = True, None
            output = owner.process.stdout.read(64)
            expected_stall = size == 29917 and not binary
            require(timed_out if expected_stall else exit_code == 0 and output == b"PACKET4_OK", "packet4_regression")
            results.append({"length": size, "binary_latin1": binary, "expected_legacy_stall": expected_stall,
                            "timeout": timed_out, "exit_code": exit_code,
                            "ms": round((time.monotonic() - started) * 1000), "child_reaped": owner.process.returncode is not None})
        finally:
            owner.stop()
            owner.process.stdin.close()
            owner.process.stdout.close()
    result = {"status": "packet4_causal_control_passed", "rows": results, "network_requests": 0,
              "sdk_loaded": False, "private_payloads_read": False}
    private_json(args.work / "packet4-control.json", result)
    print(json.dumps({"status": result["status"], "rows": len(results)}))


if __name__ == "__main__":
    main()
