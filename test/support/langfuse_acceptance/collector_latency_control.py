#!/usr/bin/env python3
"""Owned, offline causal control of Collector ACK deadlines; no keys or cloud."""
import argparse
import json
import os
from pathlib import Path
import sys
import tempfile
import time
sys.dont_write_bytecode = True
from api import BoundaryError, digest, private_json
from run import Collector, Owned, closed_env, metrics, native, require, verify_admission


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--admission", type=Path)
    parser.add_argument("--admission-sha256")
    parser.add_argument("--work", type=Path)
    args = parser.parse_args()
    if not args.run:
        print("Skipped: explicit offline admission required. No keys or network.")
        return
    require(digest(args.admission) == args.admission_sha256, "latency_control_source")
    admission = json.loads(args.admission.read_text())
    verify_admission(admission)
    work = Path(tempfile.mkdtemp(prefix="collector-latency-control-", dir=args.work))
    work.chmod(0o700)
    rows = []
    for timeout_ms in (500, 3000):
        stage = work / str(timeout_ms)
        stage.mkdir(mode=0o700)
        fixture = Owned(["/usr/bin/python3", str(Path(admission["harness"]) / "http_fixture.py"),
                         "--run", "--backend", "opik", "--workspace", admission["workspace"],
                         "--response-delay-ms", "700", "--ready", str(stage / "ready.json"),
                         "--report", str(stage / "fixture.json")], cwd=stage, env=closed_env())
        collector = None
        try:
            until = time.monotonic() + 2
            while not (stage / "ready.json").is_file() and time.monotonic() < until:
                time.sleep(0.01)
            require((stage / "ready.json").is_file(), "latency_fixture_not_ready")
            port = json.loads((stage / "ready.json").read_text())["port"]
            configuration = dict(admission)
            if timeout_ms == 500:
                # Use the unchanged recipe default in the negative control.
                configuration.pop("backend")
            collector = Collector(configuration, stage,
                                  f"http://127.0.0.1:{port}/api/v1/private/otel/v1/traces",
                                  headers={"projectName": "exagent", "Comet-Workspace": admission["workspace"]})
            manifest, result = native(admission, stage, wave="latency-control-" + str(timeout_ms), collector=collector)
            counters = metrics(collector)
        finally:
            try:
                lifecycle = collector.stop() if collector else None
            finally:
                fixture.stop()
        good = result["status"] == "native_phase_complete"
        require(good == (timeout_ms == 3000), "latency_control_expected_result")
        require(lifecycle["owner"]["group_closed"] is True, "latency_collector_group")
        require(lifecycle["loss_logs"]["transport_timeout_events"] == (1 if timeout_ms == 500 else 0),
                "latency_timeout_classification")
        rows.append({"timeout_ms": timeout_ms, "response_delay_ms": 700, "native_status": result["status"],
                     "collector_metrics": counters, "collector": lifecycle,
                     "transport_receipts": result["transport_receipts"],
                     "span_count": sum(t["span_count"] for t in manifest["traces"]),
                     "fixture_group_reaped": fixture.process.returncode is not None})
    receipt = {"status": "collector_latency_causal_control_passed", "admission_sha256": args.admission_sha256,
               "rows": rows, "cloud_requests": 0, "real_keys_read": False, "paid_provider_requests": 0}
    private_json(work / "receipt.json", receipt)
    print(json.dumps({"status": receipt["status"], "receipt": str(work / "receipt.json")}))


if __name__ == "__main__":
    main()
