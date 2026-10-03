#!/usr/bin/env python3
"""One source-sealed, explicitly admitted read-only wave for two fresh native traces."""
import argparse
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import time

sys.dont_write_bytecode = True
from api import (BoundaryError, EU, FIELDS, METADATA_PROJECTION, NAME_PROJECTION, MAX_BODY,
                 digest, expected_api_name, observation_query, private_json)
from run import OWNED, Owned, closed_env, require, safe_name, tree_hashes, wait_owned

PROFILE = {"max_posts": 0, "max_gets": 3, "api_seconds": 12, "identity_gets": 1,
           "identity_seconds": 3, "observation_gets": 2, "observation_seconds": 7,
           "cleanup_seconds": 2, "observations_per_trace": 1, "polling": False, "retries": 0,
           "limit_per_trace": 32, "max_body_bytes": 524288, "pagination_fallback": False}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run", action="store_true")
    for name in ("plan", "credentials-file", "work"):
        p.add_argument("--" + name, type=Path)
    p.add_argument("--plan-sha256")
    args = p.parse_args()
    if not args.run:
        print("Skipped: explicit read-only wave and sealed plan required. No credentials or network access.")
        return
    os.umask(0o077)

    def interrupted(_signal, _frame):
        raise BoundaryError("read_owner_interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    require(all((args.plan, args.plan_sha256, args.credentials_file, args.work)), "read_wave_arguments")
    require(digest(args.plan) == args.plan_sha256, "read_plan_changed_before_keys")
    plan = json.loads(args.plan.read_text())
    require(plan["status"] == "read_only_wave_authorized_after_causal_api_focal", "read_plan_not_admitted")
    safe_name(plan["wave"])
    require(plan["base"] == EU and plan["project_name"] == "exagent", "read_backend_not_admitted")
    require(plan["profile"] == PROFILE and plan["fields"] == FIELDS and
            plan["metadata_projection"] == METADATA_PROJECTION and
            plan["name_projection"] == NAME_PROJECTION and MAX_BODY == 524288, "read_profile_changed")
    source = Path(__file__).resolve().parent
    require(tree_hashes(source) == plan["api_driver_hashes"], "read_driver_changed_before_keys")
    for path, expected in plan["input_hashes"].items():
        require(digest(path) == expected, "read_input_changed_before_keys")
    manifest = json.loads(Path(plan["native_manifest"]).read_text())
    require(manifest["status"] == "native_admitted" and manifest["source_tar_sha256"] == plan["source_tar_sha256"],
            "read_native_source")
    expected = [{key: trace[key] for key in ("trace_id", "span_count", "from_start_time", "to_start_time")}
                for trace in manifest["traces"]]
    require(expected == plan["traces"] and sum(t["span_count"] for t in expected) == 33,
            "read_trace_ids_or_windows_changed")
    require([observation_query(trace) for trace in manifest["traces"]] == plan["queries"], "read_queries_changed")
    for trace in manifest["traces"]:
        for span in trace["spans"]:
            expected_api_name(span)
    require(args.work.resolve().is_relative_to(Path("/tmp")), "private_read_work_required")
    work = Path(tempfile.mkdtemp(prefix="langfuse-read-wave-", dir=args.work))
    work.chmod(0o700)
    # This scalar plan is persisted and verified before either credential access
    # or network I/O; the only child program is the bounded API reader.
    private_json(work / "source-before-read.json", {"plan_sha256": args.plan_sha256, **plan})
    started = time.monotonic()

    def stage(scope):
        path = work / ("identity.json" if scope else "api.json")
        argv = ["/usr/bin/python3", str(source / "poll.py"), "--run", "--credentials-file",
                str(args.credentials_file.resolve()), "--report", str(path), "--project-id", plan["project_id"],
                "--base", EU]
        if scope:
            argv.append("--scope-only")
        else:
            argv.extend(["--manifest", plan["native_manifest"], "--once", "--seconds", "7", "--max-gets", "2"])
        owner = Owned(argv, cwd=work, env=closed_env())
        try:
            code = wait_owned(owner, seconds=3 if scope else 7)
        except BoundaryError as error:
            return {"status": "api_failed_private_boundary", "code": str(error)}
        if path.is_file():
            return json.loads(path.read_text())
        return {"status": "api_failed_private_boundary", "code": "reader_exit_without_public_report", "exit": code}

    identity = stage(True)
    if identity.get("status") == "synthetic_project_key_verified":
        observed = stage(False)
    else:
        observed = {"status": "not_polled_after_identity_failure"}
    complete = observed.get("status") == "native_api_rows_verified_only"
    count = sum(len(rows) for rows in observed.get("observations", {}).values())
    require(not complete or count == 33, "read_complete_count")
    receipt = {"status": "native_api_verified_ui_pending" if complete else "native_api_not_qualified",
               "source": plan, "plan_sha256": args.plan_sha256, "identity": identity, "api": observed,
               "backend_observations_verified": count, "collector_ack_spans_previous_wave": 33,
               "ack_is_not_durable_ingestion": True, "backend_read_is_not_billing_or_ui_acceptance": True,
               "cloud_posts": 0, "producer_collector_model_reruns": 0,
               "api_ms": round((time.monotonic() - started) * 1000),
               "owned_reader_groups_reaped": all(owner.process.returncode is not None for owner in OWNED),
               "native_name_and_api_name_separated": True,
               "trace_ids": [t["trace_id"] for t in expected],
               "ui_links": [EU + "/project/" + plan["project_id"] + "/traces/" + t["trace_id"] for t in expected],
               "ui_accepted": False}
    path = work / "receipt.json"
    private_json(path, receipt)
    print(json.dumps({"status": receipt["status"], "receipt": str(path), "receipt_sha256": digest(path),
                      "backend_observations_verified": count, "cloud_posts": 0,
                      "trace_ids": receipt["trace_ids"], "ui_accepted": False}))


if __name__ == "__main__":
    try:
        main()
    except BoundaryError as error:
        print(json.dumps({"status": "failed", "code": str(error)}))
        raise SystemExit(1)
    except (Exception, KeyboardInterrupt):
        print('{"status":"failed","code":"private_read_owner_failure"}')
        raise SystemExit(1)
    finally:
        signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
        for owner in reversed(OWNED):
            owner.stop()
