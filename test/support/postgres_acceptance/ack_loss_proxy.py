#!/usr/bin/env python3
"""Owned loopback PostgreSQL fault control: drop the first real COMMIT reply."""
import argparse
import json
from pathlib import Path
import signal
import socket
import struct
import threading
import time


MAX_FRAME_BYTES = 262144
MAX_CONNECTIONS = 8


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    args = parser.parse_args()
    stop = threading.Event()
    lock = threading.Lock()
    connections = set()
    threads = []
    receipt = {"server_commit_observed": False, "commit_reply_forwarded": False,
               "connections": 0, "cancel_requests": 0, "closed": False, "errors": [],
               "maximum_frame_bytes": MAX_FRAME_BYTES}
    target = args.socket / ".s.PGSQL.5432"

    def write_receipt():
        # No SQL, row data, startup usernames or credentials enter this receipt.
        temporary = args.artifacts / "ack-proxy.json.tmp"
        temporary.write_text(json.dumps(receipt, indent=2) + "\n")
        temporary.replace(args.artifacts / "ack-proxy.json")

    def shutdown_socket(peer):
        try:
            peer.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        peer.close()

    def stop_signal(*_):
        stop.set()

    signal.signal(signal.SIGTERM, stop_signal)
    signal.signal(signal.SIGINT, stop_signal)

    def exact(peer, size):
        value = bytearray()
        while len(value) < size:
            chunk = peer.recv(size - len(value))
            if not chunk:
                return None
            value.extend(chunk)
        return bytes(value)

    def client_to_server(client, backend):
        try:
            # Plaintext StartupMessage is length-prefixed without a type byte.
            header = exact(client, 4)
            if header is None:
                return
            size = struct.unpack("!I", header)[0]
            if not 8 <= size <= MAX_FRAME_BYTES:
                raise ValueError("startup_frame_size")
            payload = exact(client, size - 4)
            if payload is None:
                return
            protocol = struct.unpack("!I", payload[:4])[0]
            # Postgrex sends CancelRequest on a separate connection while
            # cleaning up a disconnected Repo. Forward it to this own server;
            # it has no typed response and cannot trigger the COMMIT fault.
            if protocol == 80877102 and size == 16:
                with lock:
                    receipt["cancel_requests"] += 1
                backend.sendall(header + payload)
                return
            # This profile explicitly disables SSL/GSS negotiation.
            if protocol != 196608:
                raise ValueError("unexpected_startup_protocol")
            backend.sendall(header + payload)
            while not stop.is_set():
                chunk = client.recv(16384)
                if not chunk:
                    break
                backend.sendall(chunk)
        except (OSError, ValueError) as error:
            if not stop.is_set() and isinstance(error, ValueError):
                with lock:
                    receipt["errors"].append(str(error))
                    write_receipt()
        finally:
            shutdown_socket(client)
            shutdown_socket(backend)

    def relay(client):
        backend = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(5)
        backend.settimeout(5)
        with lock:
            connections.update((client, backend))
        forward = None
        try:
            backend.connect(str(target))
            forward = threading.Thread(target=client_to_server, args=(client, backend), daemon=True)
            forward.start()
            while not stop.is_set():
                header = exact(backend, 5)
                if header is None:
                    break
                size = struct.unpack("!I", header[1:])[0]
                if not 4 <= size <= MAX_FRAME_BYTES:
                    raise ValueError("backend_frame_size")
                payload = exact(backend, size - 4)
                if payload is None:
                    break
                with lock:
                    drop = (header[:1] == b"C" and payload == b"COMMIT\x00"
                            and not receipt["server_commit_observed"])
                    if drop:
                        receipt["server_commit_observed"] = True
                        receipt["commit_reply_forwarded"] = False
                        write_receipt()
                if drop:
                    # PostgreSQL produced CommandComplete(COMMIT); do not deliver
                    # it or ReadyForQuery to the caller. Closing the connection
                    # creates genuine client uncertainty after the committed write.
                    break
                client.sendall(header + payload)
        except (OSError, ValueError) as error:
            if not stop.is_set() and isinstance(error, ValueError):
                with lock:
                    receipt["errors"].append(str(error))
                    write_receipt()
        finally:
            shutdown_socket(client)
            shutdown_socket(backend)
            if forward:
                forward.join(timeout=1)
            with lock:
                connections.discard(client)
                connections.discard(backend)

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0))
    listener.listen(2)
    listener.settimeout(0.2)
    (args.artifacts / "ack-proxy-port.txt").write_text(str(listener.getsockname()[1]) + "\n")
    write_receipt()
    deadline = time.monotonic() + 30
    try:
        while not stop.is_set() and time.monotonic() < deadline:
            try:
                client, _ = listener.accept()
            except socket.timeout:
                continue
            with lock:
                receipt["connections"] += 1
                permitted = receipt["connections"] <= MAX_CONNECTIONS
            if not permitted:
                shutdown_socket(client)
                stop.set()
                break
            thread = threading.Thread(target=relay, args=(client,), daemon=True)
            threads.append(thread)
            thread.start()
    finally:
        stop.set()
        listener.close()
        with lock:
            peers = list(connections)
        for peer in peers:
            shutdown_socket(peer)
        for thread in threads:
            thread.join(timeout=1)
        receipt["closed"] = not any(thread.is_alive() for thread in threads)
        write_receipt()
    return 0 if receipt["closed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
