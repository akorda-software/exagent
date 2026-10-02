#!/usr/bin/env python3
"""Source-sealed, finite Opik A10 acceptance; default invocation does nothing."""
import argparse
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import time

sys.dont_write_bytecode = True
import opik_api as api
from api import BoundaryError, digest, private_json
from run import (OWNED, SOURCE, COLLECTOR_SHA, Collector, Owned, closed_env, metrics,
                 native, prepare, require, safe_name, verify_admission, wait_owned)


def read_worker(args):
    admission = admitted(args)
    require(args.project_id == admission["project_id"] and args.workspace == admission["workspace"],
            "opik_worker_scope_changed_before_keys")
    authorization = api.credentials(args.credentials_file)
    attempted = 0
    try:
        if args.scope_worker:
            attempted = 1
            result = api.scope(authorization, None if args.project_id == "unresolved" else args.project_id,
                               workspace=args.workspace)
        else:
            manifest = json.loads(args.manifest.read_text())
            require(manifest["status"] == "native_admitted" and len(manifest["traces"]) == 2 and
                    sorted(t["span_count"] for t in manifest["traces"]) == [15, 18], "api_native_profile")
            results, traces, sizes = [], [], []
            started = time.monotonic()
            for trace in manifest["traces"]:
                mapping = api.identity_map(trace)
                for route, query in (("/api/v1/private/traces/" + mapping["trace_id"], {}),
                                     ("/api/v1/private/spans", {"project_id": args.project_id,
                                      "trace_id": mapping["trace_id"], "page": "1", "size": "32", "truncate": "false"})):
                    require(time.monotonic() - started < 7 and attempted < 4, "api_read_budget")
                    attempted += 1
                    value, size = api.get_json(authorization, route, query, workspace=args.workspace,
                                              timeout=min(2, 7 - (time.monotonic() - started)))
                    sizes.append(size)
                    if query:
                        results.append(api.inspect_page(value, trace, args.project_id, manifest["sentinels"]))
                    else:
                        traces.append(api.inspect_trace(value, trace, args.project_id, manifest["sentinels"]))
                    del value
            good = all(r["status"] == "native_api_rows_verified_only" for r in results) and all(
                not t["mismatch_codes"] for t in traces)
            result = {"status": "native_api_rows_verified_only" if good else "native_api_not_qualified",
                      "gets": attempted, "body_bytes": sizes, "pages": results, "traces": traces,
                      "observations_verified": sum(r["observations_verified"] for r in results) if good else 0,
                      "api_ms": round((time.monotonic() - started) * 1000), "raw_responses_retained": False,
                      "ui_accepted": False, "is_not_billing": True}
    except BoundaryError as error:
        result = {"status": "api_failed_private_boundary", "code": str(error), "gets": attempted,
                  "ui_accepted": False}
    private_json(args.report, result)
    print(json.dumps({"status": result["status"], "gets": result["gets"]}))
    return result["status"] in ("synthetic_workspace_project_verified", "native_api_rows_verified_only")


def stage(admission, work, credentials, *, scope_only, admission_path, admission_sha256, manifest=None):
    report = work / ("project-scope.json" if scope_only else "api.json")
    argv = ["/usr/bin/python3", str(Path(admission["harness"]) / "opik_run.py"),
            "--scope-worker" if scope_only else "--api-worker", "--credentials-file", str(credentials.resolve()),
            "--report", str(report), "--project-id", admission["project_id"], "--workspace", admission["workspace"],
            "--admission", str(admission_path.resolve()), "--admission-sha256", admission_sha256,
            "--work", str(work)]
    if manifest:
        argv.extend(["--manifest", str(manifest)])
    owner = Owned(argv, cwd=work, env=closed_env())
    try:
        code = wait_api_owner(owner, seconds=3 if scope_only else 7)
    except BoundaryError as error:
        return {"status": "api_failed_private_boundary", "code": str(error)}
    if not report.is_file():
        return {"status": "api_failed_private_boundary", "code": "reader_no_receipt", "exit": code}
    result = json.loads(report.read_text())
    require(code == 0 or result["status"] not in ("synthetic_workspace_project_verified", "native_api_rows_verified_only"),
            "reader_success_with_failed_exit")
    return result


def wait_api_owner(owner, *, seconds):
    """One read deadline, plus at most one second for this owned group's cleanup."""
    until = time.monotonic() + seconds
    try:
        while time.monotonic() < until:
            if not owner.alive():
                return owner.stop(grace=0)
            time.sleep(0.01)
        raise BoundaryError("owned_command_deadline")
    finally:
        owner.stop(grace=0)


def verify_executing_harness(admission):
    root = Path(admission["harness"]).resolve()
    require(Path(__file__).resolve().parent == root, "opik_unsealed_driver_before_keys")
    files = {"opik_run.py": Path(__file__)}
    for name in ("opik_api", "api", "run"):
        files[name + ".py"] = Path(sys.modules[name].__file__)
    for name, path in files.items():
        require(path.resolve() == root / name and digest(path) == admission["harness_hashes"].get(name),
                "opik_unsealed_helper_before_keys")


def admitted(args):
    require(all((args.admission, args.admission_sha256, args.credentials_file, args.work)), "opik_wave_arguments")
    require(digest(args.admission) == args.admission_sha256, "admission_changed_before_keys")
    admission = json.loads(args.admission.read_text())
    verify_admission(admission)
    verify_executing_harness(admission)
    require(admission.get("backend") == "opik" and admission["base"] == api.BASE and
            admission["project_name"] == api.PROJECT and
            admission["request_projection"] == api.PROJECTION and
            admission["profile"]["max_traces"] == 2 and admission["profile"]["max_posts"] == 5 and
            admission["profile"].get("http_timeout_ms") == 3_000 and
            admission["profile"].get("rpc_deadline_ms") == 3_500 and
            admission["profile"].get("batch_deadline_ms") == 5_000 and
            admission["profile"].get("export_timeout_ms") == 20_000 and
            admission["profile"].get("native_deadline_seconds") == 28 and
            admission["profile"].get("collector_lifetime_ms") == 30_000 and
            admission["profile"]["retries"] == 0, "opik_admission_scope")
    safe_name(admission["workspace"])
    require(args.work.resolve().is_relative_to(Path("/tmp")), "opik_private_work")
    return admission


def live(args):
    admission = admitted(args)
    safe_name(args.wave)
    require(api.valid_uuid(admission["project_id"]), "opik_project_id_not_frozen")
    work = Path(tempfile.mkdtemp(prefix="opik-wave-", dir=args.work))
    work.chmod(0o700)
    source = {"wave": args.wave, "admission_sha256": args.admission_sha256,
              "tar_sha256": admission["tar_sha256"], "base": api.BASE, "workspace": admission["workspace"],
              "project_id": admission["project_id"], "project_name": api.PROJECT,
              "profile": admission["profile"], "request_projection": api.PROJECTION,
              "harness_hashes": admission["harness_hashes"], "recipe_hashes": admission["recipe_hashes"],
              "collector_sha256": COLLECTOR_SHA, "fresh_native_ids": True, "ui_accepted": False}
    private_json(work / "source-before-write.json", source)
    identity = stage(admission, work, args.credentials_file, scope_only=True,
                     admission_path=args.admission, admission_sha256=args.admission_sha256)
    require(identity["status"] == "synthetic_workspace_project_verified", "project_scope_failed_before_write")
    authorization = api.credentials(args.credentials_file)
    collector = Collector(admission, work, api.BASE + "/api/v1/private/otel/v1/traces", headers={
        "Authorization": authorization, "projectName": api.PROJECT, "Comet-Workspace": admission["workspace"]})
    del authorization
    manifest, result, counters, failure = None, None, None, None
    try:
        manifest, result = native(admission, work, wave=args.wave, collector=collector)
        counters = metrics(collector)
    except BoundaryError as error:
        failure = str(error)
    finally:
        lifecycle = collector.stop()
    if manifest and manifest["status"] == "native_admitted" and result and result["status"] == "native_phase_complete":
        # Single finite read after the one native wave; no poll/reingestion loop.
        observed = stage(admission, work, args.credentials_file, scope_only=False,
                         admission_path=args.admission, admission_sha256=args.admission_sha256,
                         manifest=work / "native-manifest.json")
    else:
        observed = {"status": "not_read_without_complete_native_wave"}
    metric_good = counters and counters["counters"] == {
        "otelcol_receiver_accepted_spans": 33, "otelcol_receiver_refused_spans": 0,
        "otelcol_exporter_sent_spans": 33, "otelcol_exporter_send_failed_spans": 0}
    transport_good = result and len(result["transport_receipts"]) == 5 and all(
        r.get("reported_accepted") == r.get("sent") and r.get("rejected") == 0 and
        r.get("unknown") == 0 and r.get("group_closed") is True for r in result["transport_receipts"])
    good = (failure is None and metric_good and transport_good and
            observed["status"] == "native_api_rows_verified_only")
    # Keep the conjunction explicit below, avoiding a successful exit for a
    # receipt that only proves Collector acknowledgement.
    good = bool(good and lifecycle["loss_logs"]["partial_events"] == 0 and
                lifecycle["loss_logs"]["other_events"] == 0)
    maps = [api.identity_map(t) for t in manifest["traces"]] if manifest else []
    links = [api.BASE + "/" + admission["workspace"] + "/projects/" + admission["project_id"] +
             "/logs?trace=" + m["trace_id"] for m in maps]
    receipt = {"status": "native_api_verified_ui_pending" if good else "native_api_not_qualified",
               "source": source, "identity": identity, "native": result, "collector_metrics": counters,
               "collector": lifecycle, "api": observed, "failure_code": failure, "identity_maps": maps,
               "ui_links": links, "ui_accepted": False, "ack_is_not_durable_ingestion": True,
               "provider_requests_paid": 0, "producer_cloud_waves": 1,
               "owned_groups_reaped": all(o.process.returncode is not None for o in OWNED)}
    path = work / "receipt.json"
    private_json(path, receipt)
    print(json.dumps({"status": receipt["status"], "receipt": str(path), "ui_links": links}))
    return good


def main():
    p = argparse.ArgumentParser(description=__doc__)
    mode = p.add_mutually_exclusive_group()
    for flag in ("prepare", "run", "scope", "scope-worker", "api-worker"):
        mode.add_argument("--" + flag, action="store_true")
    for name in ("consumer", "package", "collector-binary", "elixir-bin", "erlang-bin", "rebar3", "archives",
                 "work", "admission", "credentials-file", "manifest", "report"):
        p.add_argument("--" + name, type=Path)
    for name in ("tar-sha256", "admission-sha256", "wave"):
        p.add_argument("--" + name)
    p.add_argument("--project-id", default="unresolved")
    p.add_argument("--workspace")
    p.add_argument("--package-source", default="vendor/exagent")
    args = p.parse_args()
    if not any((args.prepare, args.run, args.scope, args.scope_worker, args.api_worker)):
        print("Skipped: explicit Opik source/scope/wave admission required. No key/file/network access.")
        return True
    os.umask(0o077)
    def interrupted(_signal, _frame):
        raise BoundaryError("opik_owner_interrupted")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    if args.prepare:
        args.backend, args.max_traces = "opik", 2
        result = prepare(args)
        return result["status"] == "prepared_for_explicit_wave"
    if args.scope_worker or args.api_worker:
        return read_worker(args)
    if args.scope:
        admission = admitted(args)
        work = Path(tempfile.mkdtemp(prefix="opik-identity-", dir=args.work))
        work.chmod(0o700)
        private_json(work / "source-before-read.json", {"admission_sha256": args.admission_sha256,
                                                       "project_name": api.PROJECT, "workspace": admission["workspace"],
                                                       "max_gets": 1, "max_posts": 0, "deadline_seconds": 3})
        result = stage(admission, work, args.credentials_file, scope_only=True,
                       admission_path=args.admission, admission_sha256=args.admission_sha256)
        print(json.dumps(result))
        print(json.dumps({"identity_receipt": str(work / "project-scope.json")}))
        return result["status"] == "synthetic_workspace_project_verified"
    return live(args)


if __name__ == "__main__":
    try:
        good = main()
        raise SystemExit(0 if good else 1)
    except BoundaryError as error:
        print(json.dumps({"status": "failed", "code": str(error)}))
        raise SystemExit(1)
    except Exception:
        print('{"status":"failed","code":"opik_private_driver_failure"}')
        raise SystemExit(1)
    finally:
        for owner in reversed(OWNED):
            owner.stop()
