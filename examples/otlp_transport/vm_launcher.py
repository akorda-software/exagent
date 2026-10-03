#!/usr/bin/env python3
"""Packaged recipe: own one registered BEAM group and bound trusted packet IPC."""
import argparse
import ctypes
import json
import os
import selectors
import signal
import struct
import subprocess
import sys
import time

MAX_REQUEST = 65_536
MAX_RECEIPT = 4_096
MAX_STDERR = 8_192


class OwnerClosed(Exception):
    pass


def packet(value):
    body = json.dumps(value, separators=(",", ":")).encode()
    if len(body) > MAX_RECEIPT:
        raise ValueError("receipt_limit")
    sys.stdout.buffer.write(struct.pack("!I", len(body)) + body)
    sys.stdout.buffer.flush()


def take_frame(buffer, maximum):
    if len(buffer) < 4:
        return None
    length = struct.unpack("!I", buffer[:4])[0]
    if not 1 <= length <= maximum:
        raise ValueError("packet_limit")
    if len(buffer) < 4 + length:
        return None
    value = bytes(buffer[4:4 + length])
    del buffer[:4 + length]
    return value


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--elixir", required=True)
    p.add_argument("--beam-path", required=True)
    p.add_argument("--worker", required=True)
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--count", type=int, required=True)
    p.add_argument("--deadline-ms", type=int, required=True)
    p.add_argument("--rpc-deadline-ms", type=int, required=True)
    p.add_argument("--fault", choices=("none", "shutdown_block", "before_rpc_hold"), default="none")
    args = p.parse_args()
    if not (1 <= args.count <= 8 and 1 <= args.port <= 65_535
            and 100 <= args.deadline_ms <= 5_000 and 1 <= args.rpc_deadline_ms <= 5_000):
        raise SystemExit(2)
    # Linux public process-local API: reap this launcher's own orphaned VM
    # descendants too. This does not change the host BEAM or any other process.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        raise OSError(ctypes.get_errno(), "subreaper")
    child = None
    registered = False
    input_buffer, output_buffer = bytearray(), bytearray()
    sent = False
    received = False
    pending = bytearray()
    stderr_bytes = 0
    receipt = None
    reason = "deadline"
    failure_code = None
    until = time.monotonic() + args.deadline_ms / 1000

    def interrupted(_signum, _frame):
        raise OwnerClosed()

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    selector = selectors.DefaultSelector()
    os.set_blocking(sys.stdin.fileno(), False)
    selector.register(sys.stdin, selectors.EVENT_READ, "owner")
    try:
        # Keep termination pending until creation and registration are atomic
        # from this supervisor's perspective. No PID is read from outside it.
        blocked = {signal.SIGTERM, signal.SIGINT}
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, blocked)
        try:
            def child_signals():
                signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
            command = [args.elixir, "-pa", args.beam_path, args.worker,
                       str(args.port), str(args.count), str(args.rpc_deadline_ms), args.fault]
            child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, start_new_session=True,
                                     preexec_fn=child_signals, env={
                                         "PATH": os.environ["PATH"], "LANG": "C.UTF-8",
                                         "LC_ALL": "C.UTF-8", "ERL_FLAGS": "+S 2:2 +A 1",
                                     })
            if os.getpgid(child.pid) != child.pid:
                raise RuntimeError("group_registration")
            registered = True
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
        packet({"type": "started", "vm_pid": child.pid, "registered": True})
        for stream, label in ((child.stdout, "vm"), (child.stderr, "stderr")):
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, label)
        os.set_blocking(child.stdin.fileno(), False)

        while time.monotonic() < until and receipt is None:
            for key, _ in selector.select(max(0, until - time.monotonic())):
                if key.data == "input":
                    written = os.write(child.stdin.fileno(), pending)
                    del pending[:written]
                    if not pending:
                        selector.unregister(child.stdin)
                        sent = True
                    continue
                data = os.read(key.fileobj.fileno(), 16_384)
                if key.data == "owner":
                    if not data:
                        raise OwnerClosed()
                    input_buffer.extend(data)
                    # At most one request and the nine-byte CANCEL frame.
                    if len(input_buffer) > MAX_REQUEST + 4 + 9:
                        raise ValueError("input_buffer_limit")
                    frame = take_frame(input_buffer, MAX_REQUEST)
                    while frame is not None:
                        if received:
                            if frame != b"CANCEL":
                                raise ValueError("second_request")
                            raise OwnerClosed()
                        pending.extend(struct.pack("!I", len(frame)) + frame)
                        received = True
                        selector.register(child.stdin, selectors.EVENT_WRITE, "input")
                        frame = take_frame(input_buffer, MAX_REQUEST)
                elif key.data == "stderr":
                    if not data:
                        selector.unregister(key.fileobj)
                    stderr_bytes = min(MAX_STDERR + 1, stderr_bytes + len(data))
                else:
                    if not data:
                        raise ValueError("vm_exit_without_receipt")
                    output_buffer.extend(data)
                    if len(output_buffer) > MAX_RECEIPT + 4:
                        raise ValueError("output_buffer_limit")
                    frame = take_frame(output_buffer, MAX_RECEIPT)
                    if frame is not None:
                        receipt = json.loads(frame)
                        if not isinstance(receipt, dict) or output_buffer:
                            raise ValueError("invalid_receipt")
                        reason = "result"
    except OwnerClosed:
        reason = "owner_closed"
    except (ValueError, RuntimeError, OSError) as exc:
        reason = "transport_failure"
        fixed = ("packet_limit", "input_buffer_limit", "second_request", "vm_exit_without_receipt",
                 "output_buffer_limit", "invalid_receipt", "group_registration")
        failure_code = str(exc) if str(exc) in fixed else type(exc).__name__
    finally:
        selector.close()
        # No poll()/wait() precedes group kill: its registered leader is alive
        # or an unreaped zombie, so its PID cannot have been recycled.
        closed = False
        adopted_reaped = 0
        if child is not None and registered:
            signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=1)
                closed = True
            except subprocess.TimeoutExpired:
                closed = False
            reaping_until = time.monotonic() + 0.5
            while closed and time.monotonic() < reaping_until:
                try:
                    pid, _ = os.waitpid(-1, os.WNOHANG)
                except ChildProcessError:
                    break
                if pid:
                    adopted_reaped += 1
                else:
                    time.sleep(0.005)
            else:
                closed = False
            for stream in (child.stdin, child.stdout, child.stderr):
                stream.close()
        if receipt is None or reason != "result":
            receipt = {"result": "failed", "sent": args.count if sent else 0,
                       "reported_accepted": 0, "rejected": 0, "unknown": args.count}
        receipt.update({"type": "closed", "reason": reason, "group_closed": closed,
                        "vm_pid": child.pid if child else 0,
                        "adopted_reaped": adopted_reaped,
                        "failure_code": failure_code, "stderr_bytes_capped": stderr_bytes,
                        "stderr_truncated": stderr_bytes > MAX_STDERR})
        try:
            packet(receipt)
        except (BrokenPipeError, OSError):
            # Discard a failed buffered flush too, without noisy atexit output.
            discarded = os.open(os.devnull, os.O_WRONLY)
            os.dup2(discarded, sys.stdout.fileno())
            os.close(discarded)


if __name__ == "__main__":
    main()
