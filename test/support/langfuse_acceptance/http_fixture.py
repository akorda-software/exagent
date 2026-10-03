#!/usr/bin/env python3
"""Finite loopback fixture: count opaque OTLP bytes; never decode their contents."""
import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import sys
import time

sys.dont_write_bytecode = True
from api import private_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--backend", choices=("langfuse", "opik"), default="langfuse")
    parser.add_argument("--workspace", default="akorda")
    parser.add_argument("--ready", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--response-delay-ms", type=int, default=0)
    args = parser.parse_args()
    if not args.run:
        print("Skipped: opt in with --run. No listener or file access.")
        return
    os.umask(0o077)
    if not 0 <= args.response_delay_ms <= 800:
        raise ValueError("fixture_delay_boundary")
    requests = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_POST(self):
            self.connection.settimeout(2)
            try:
                size = int(self.headers.get("Content-Length", "-1"))
                route = "/api/v1/private/otel/v1/traces" if args.backend == "opik" else "/api/public/otel/v1/traces"
                if self.path != route or not 0 <= size <= 65_536 or len(requests) >= 8:
                    raise ValueError()
                body = self.rfile.read(size)
                if len(body) != size or self.headers.get("Content-Encoding", "") not in ("", "identity"):
                    raise ValueError()
                requests.append({"bytes": size, "sha256": hashlib.sha256(body).hexdigest(),
                                 "authorization_absent": "Authorization" not in self.headers,
                                 "ingestion_version": self.headers.get("x-langfuse-ingestion-version"),
                                 "opik_headers_verified": self.headers.get("projectName") == "exagent" and
                                 self.headers.get("Comet-Workspace") == args.workspace and
                                 "x-langfuse-ingestion-version" not in self.headers,
                                 "content_type": self.headers.get("Content-Type")})
                # Empty protobuf ExportTraceServiceResponse is valid success. No
                # private codec, byte parser, or synthetic backend qualification.
                time.sleep(args.response_delay_ms / 1000)
                self.send_response(200)
                self.send_header("Content-Type", "application/x-protobuf")
                self.send_header("Content-Length", "0")
                self.end_headers()
            except Exception:
                self.send_response(400)
                self.send_header("Content-Length", "0")
                self.end_headers()

    with http.server.HTTPServer(("127.0.0.1", 0), Handler) as server:
        server.timeout = 0.1
        private_json(args.ready, {"port": server.server_port, "pid": os.getpid()})
        until = time.monotonic() + 28
        last = None
        while time.monotonic() < until:
            before = len(requests)
            server.handle_request()
            if len(requests) != before:
                last = time.monotonic()
            if last is not None and time.monotonic() - last > 5:
                break
        private_json(args.report, {"status": "opaque_loopback_only", "requests": requests,
                                   "total_requests": len(requests), "private_body_retained": False})


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("fixture_private_failure")
        raise SystemExit(1)
