#!/usr/bin/env python3
"""Own one checksum-verified official Collector with finite stop and lifetime."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import selectors
import signal
import socket
import struct
import subprocess
import sys
import time

VERSION = "0.162.0"
BINARY_SHA256 = "910a66b1210e09143260914ef0634b4d234c789f23efc34bc9c7a3c0480324fa"
MAX_LOG_BYTES = 1_048_576


class OwnerClosed(Exception):
    pass


def packet(value):
    payload = json.dumps(value, separators=(",", ":")).encode()
    if len(payload) > 4_096:
        raise ValueError("receipt_limit")
    sys.stdout.buffer.write(struct.pack("!I", len(payload)) + payload)
    sys.stdout.buffer.flush()


def free_port():
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        return server.getsockname()[1]


def validate_binary(path):
    with path.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    if digest != BINARY_SHA256:
        raise ValueError("official_binary_checksum")


def group_members(group):
    # Read-only verification. A kill target never comes from /proc inspection.
    members = []
    for directory in Path("/proc").iterdir():
        if directory.name.isdigit():
            try:
                stat = (directory / "stat").read_text()
                fields = stat[stat.rfind(")") + 2:].split()
                if int(fields[2]) == group:
                    members.append(int(directory.name))
            except (OSError, ValueError, IndexError):
                pass
    return members


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run", action="store_true")
    p.add_argument("--binary", type=Path)
    p.add_argument("--config", type=Path)
    p.add_argument("--log", type=Path)
    p.add_argument("--http-endpoint")
    p.add_argument("--grpc-port", type=int)
    p.add_argument("--metrics-port", type=int)
    p.add_argument("--lifetime-ms", type=int, default=10_000)
    p.add_argument("--stop-ms", type=int, default=2_000)
    p.add_argument("--fault", choices=("none", "suspend_before_stop"), default="none",
                   help="synthetic lifecycle control; normal applications keep none")
    args = p.parse_args()
    if not args.run:
        print("Skipped: opt in with --run. No binary/configuration/environment access.")
        return
    if not args.binary or not args.config or not args.log or not args.http_endpoint:
        raise SystemExit("Require explicit trusted binary/config/log/endpoint")
    if not (100 <= args.lifetime_ms <= 30_000 and 100 <= args.stop_ms <= 2_000):
        raise SystemExit("Require finite lifetime/stop profile")
    validate_binary(args.binary)
    grpc_port = args.grpc_port or free_port()
    metrics_port = args.metrics_port or free_port()
    if grpc_port == metrics_port or not (1 <= grpc_port <= 65_535 and 1 <= metrics_port <= 65_535):
        raise SystemExit("invalid_ports")
    env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
           "GOMAXPROCS": "2", "GOMEMLIMIT": "96MiB",
           "EXAGENT_COLLECTOR_GRPC_ENDPOINT": f"127.0.0.1:{grpc_port}",
           "EXAGENT_COLLECTOR_METRICS_PORT": str(metrics_port),
           "EXAGENT_OTLP_HTTP_TRACES_ENDPOINT": args.http_endpoint}
    process = None
    registered = False
    reason = "lifetime"
    escalated = False
    started = time.monotonic()
    selector = selectors.DefaultSelector()
    selector.register(sys.stdin, selectors.EVENT_READ)
    previous_mask = None

    def interrupted(_signal, _frame):
        raise OwnerClosed()

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    log = args.log.open("wb")
    try:
        # CLI is single-threaded. Block termination until spawn/group registration.
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})

        def setup_child():
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
            resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_LOG_BYTES, MAX_LOG_BYTES))

        process = subprocess.Popen([str(args.binary), "--config", str(args.config)],
                                   stdout=log, stderr=log, env=env, start_new_session=True,
                                   preexec_fn=setup_child)
        if os.getpgid(process.pid) != process.pid:
            raise ValueError("group_registration")
        registered = True
        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
        previous_mask = None
        ready_until = min(started + 3, started + args.lifetime_ms / 1000)
        ready = False
        while time.monotonic() < ready_until:
            try:
                with socket.create_connection(("127.0.0.1", grpc_port), timeout=0.05):
                    ready = True
                break
            except OSError:
                time.sleep(0.01)
        if not ready:
            reason = "startup_failed"
        else:
            packet({"type": "ready", "collector_pid": process.pid, "registered": True,
                    "grpc_port": grpc_port, "metrics_port": metrics_port, "version": VERSION})
            until = started + args.lifetime_ms / 1000
            control = bytearray()
            while time.monotonic() < until:
                # WNOWAIT observes exit without reaping/recycling the registered PID.
                info = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                if info is not None:
                    reason = "collector_exit"
                    break
                if log.tell() >= MAX_LOG_BYTES:
                    reason = "log_limit"
                    break
                if selector.select(min(0.05, max(0, until - time.monotonic()))):
                    data = os.read(sys.stdin.fileno(), 32)
                    if not data:
                        reason = "owner_closed"
                        break
                    control.extend(data)
                    if len(control) > 9 or (len(control) >= 4 and struct.unpack("!I", control[:4])[0] != 5):
                        reason = "invalid_control"
                        break
                    if len(control) == 9:
                        reason = "stop" if control[4:] == b"STOP\n" else "invalid_control"
                        break
    except OwnerClosed:
        reason = "owner_closed"
    finally:
        selector.close()
        # Keep termination masked through cleanup, including when a pending
        # owner signal interrupted unmasking just after group registration.
        signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
        closed = False
        stop_started = time.monotonic()
        if process is not None and registered:
            # Targets only the group created and registered by this exact spawn.
            if args.fault == "suspend_before_stop":
                os.killpg(process.pid, signal.SIGSTOP)
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=args.stop_ms / 1000)
            except subprocess.TimeoutExpired:
                escalated = True
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=1)
            closed = group_members(process.pid) == []
        log.close()
        receipt = {"type": "closed", "reason": reason, "group_closed": closed,
                   "collector_pid": process.pid if process else 0, "stop_escalated": escalated,
                   "fault": args.fault, "exit": process.returncode if process else None,
                   "stop_ms": round((time.monotonic() - stop_started) * 1000),
                   "log_bytes": args.log.stat().st_size,
                   "lifetime_ms": round((time.monotonic() - started) * 1000)}
        try:
            packet(receipt)
        except (BrokenPipeError, OSError):
            discarded = os.open(os.devnull, os.O_WRONLY)
            os.dup2(discarded, sys.stdout.fileno())
            os.close(discarded)


if __name__ == "__main__":
    main()
