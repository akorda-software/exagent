#!/usr/bin/env python3
"""Opt-in owner EOF, lifetime and suspended-stop controls of our Collector CLI."""
import argparse
import json
import os
from pathlib import Path
import selectors
import socket
import struct
import subprocess
import sys
import time


def receive(stream, timeout):
    until = time.monotonic() + timeout
    data = bytearray()
    size = 4
    with selectors.DefaultSelector() as selector:
        selector.register(stream, selectors.EVENT_READ)
        while len(data) < size:
            remaining = until - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise AssertionError("finite receipt deadline exceeded")
            chunk = os.read(stream.fileno(), size - len(data))
            if not chunk:
                raise AssertionError("owner stream closed before its receipt")
            data.extend(chunk)
            if len(data) == 4 and size == 4:
                payload_size = struct.unpack("!I", data)[0]
                assert 0 < payload_size <= 4_096
                size = 4 + payload_size
    return json.loads(data[4:])


def exercise(mode, args):
    # This listener is ours and receives no spans; no external HTTP endpoint is used.
    with socket.socket() as unused_http:
        unused_http.bind(("127.0.0.1", 0))
        endpoint = f"http://127.0.0.1:{unused_http.getsockname()[1]}/unused/v1/traces"
        command = [sys.executable, str(args.launcher), "--run", "--binary", str(args.binary),
                   "--config", str(args.config), "--log", str(args.work / f"control-{mode}.jsonl"),
                   "--http-endpoint", endpoint, "--stop-ms", "300"]
        if mode == "lifetime":
            command.extend(["--lifetime-ms", "1_200"])
        if mode == "suspended_stop":
            command.extend(["--fault", "suspend_before_stop"])
        started = time.monotonic()
        with (args.work / f"control-{mode}.stderr").open("wb") as stderr:
            owner = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=stderr, env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"})
            try:
                ready = receive(owner.stdout, 4)
                assert ready["type"] == "ready" and ready["registered"]
                if mode == "owner_eof":
                    owner.stdin.close()
                elif mode == "suspended_stop":
                    owner.stdin.write(struct.pack("!I", 5) + b"STOP\n")
                    owner.stdin.flush()
                closed = receive(owner.stdout, 4)
                assert owner.wait(timeout=1) == 0
                assert closed["type"] == "closed" and closed["group_closed"]
                assert closed["collector_pid"] == ready["collector_pid"]
                assert not Path(f"/proc/{ready['collector_pid']}").exists()
                assert closed["log_bytes"] <= 1_048_576 and closed["stop_ms"] <= 1_500
                assert closed["reason"] == {
                    "owner_eof": "owner_closed", "lifetime": "lifetime", "suspended_stop": "stop"
                }[mode]
                assert closed["stop_escalated"] == (mode == "suspended_stop")
                assert closed["exit"] == (-9 if mode == "suspended_stop" else 0)
                assert time.monotonic() - started < 6
                return {"mode": mode, "ready": ready, "closed": closed,
                        "owner_exit": 0, "elapsed_ms": round((time.monotonic() - started) * 1000)}
            finally:
                # EOF is the launcher's public owner-loss contract. We never
                # signal a PID inferred from its receipt or the host process list.
                if not owner.stdin.closed:
                    owner.stdin.close()
                owner.wait(timeout=4)
                owner.stdout.close()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run", action="store_true")
    for name in ("launcher", "binary", "config", "work", "report"):
        p.add_argument(f"--{name}", type=Path)
    args = p.parse_args()
    if not args.run:
        print("Skipped: opt in with --run. No binary/configuration access.")
        return
    if not all((args.launcher, args.binary, args.config, args.work, args.report)):
        raise SystemExit("Require explicit private launcher, binary, config and report paths")
    cases = [exercise(mode, args) for mode in ("owner_eof", "lifetime", "suspended_stop")]
    args.report.write_text(json.dumps({"cases": cases}, indent=2) + "\n")
    print("COLLECTOR_LIFECYCLE passed: owner EOF, lifetime and owned suspended-stop controls")


if __name__ == "__main__":
    main()
