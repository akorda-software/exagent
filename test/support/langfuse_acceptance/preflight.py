#!/usr/bin/env python3
"""Finite synthetic API-boundary checks and official Collector FIFO startup."""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
from api import BoundaryError, credentials, digest, poll, private_json, verify_project_scope
from datetime import datetime


def fails(code, function):
    try:
        function()
    except BoundaryError as error:
        assert str(error) == code, (str(error), code)
    else:
        raise AssertionError("expected_fixed_boundary")


def api_checks():
    scope = verify_project_scope({"data": [{"id": "synthetic_exagent", "name": "exagent", "metadata": {"private": "ignored"}}]},
                                 120, "synthetic_exagent")
    assert scope["historical_traces_read"] == 0 and "metadata" not in scope
    fails("api_project_scope_mismatch", lambda: verify_project_scope({"data": [{"id": "other", "name": "exagent"}]}, 60, "synthetic_exagent"))
    fails("api_project_scope_mismatch", lambda: verify_project_scope({"data": [{"id": "synthetic_exagent", "name": "other"}]}, 60, "synthetic_exagent"))
    fails("api_project_scope_shape", lambda: verify_project_scope({"data": []}, 10, "synthetic_exagent"))
    manifest = {"sentinels": ["FAKE_PRIVATE_CONTENT"], "traces": [{
        "trace_id": "1" * 32, "resource_attributes": {"test.synthetic": True, "test.false": False},
        "from_start_time": "2026-10-01T00:00:00Z", "to_start_time": "2026-10-01T00:00:05Z",
        "spans": [{"id": "2" * 16, "parent_id": None, "name": "exagent.a10.application", "level": "DEFAULT",
                   "attributes": {"test.synthetic": True, "test.false": False, "exagent.request_count": 12}},
                  {"id": "3" * 16, "parent_id": "2" * 16, "name": "exagent.checkpoint", "level": "ERROR",
                   "attributes": {"exagent.status": "failed", "exagent.checkpoint.retry": False}},
                  {"id": "4" * 16, "parent_id": "2" * 16, "name": "exagent.model", "level": "DEFAULT",
                   "attributes": {"exagent.operation": "model", "gen_ai.request.model": "test",
                                  "gen_ai.usage.input_tokens": 3, "gen_ai.usage.output_tokens": 2,
                                  "exagent.usage.quality": "reported", "exagent.cost.status": "unknown"}}]}]}
    queries = []
    trace = manifest["traces"][0]
    for span in trace["spans"]:
        span["start_time_ms"] = round(datetime.fromisoformat("2026-10-01T00:00:01+00:00").timestamp() * 1_000)
        span["end_time_ms"] = round(datetime.fromisoformat("2026-10-01T00:00:03+00:00").timestamp() * 1_000)
    rows = [{"id": s["id"], "traceId": trace["trace_id"], "projectId": "synthetic_exagent",
             "parentObservationId": s["parent_id"], "name": s["name"], "level": s["level"],
             "startTime": "2026-10-01T00:00:01Z", "endTime": "2026-10-01T00:00:03Z", "input": None, "output": "",
             "metadata": {**{"attributes." + key: value for key, value in s["attributes"].items()},
                          **{"resourceAttributes." + key: value for key, value in trace["resource_attributes"].items()}}}
            for s in trace["spans"]]
    rows[2].update(type="GENERATION", model="test", usageDetails={"input": 3, "output": 2, "total": 5})

    def read(page):
        def get(query, timeout):
            assert query["traceId"] == "1" * 32 and query["limit"] == "32" and timeout <= 2
            assert query["fromStartTime"] == trace["from_start_time"] and query["toStartTime"] == trace["to_start_time"]
            assert query["fields"] == "core,basic,metadata,io,model,usage,trace_context"
            assert "expandMetadata" not in query
            queries.append(query)
            return page, len(json.dumps(page).encode())
        return get

    full = {"data": rows, "meta": {"cursor": None}}
    result = poll(manifest, "synthetic_exagent", read(full), seconds=.05, interval=.005, max_gets=2)
    assert result["status"] == "native_api_rows_verified_only" and result["ui_accepted"] is False
    missing = poll(manifest, "synthetic_exagent", read({"data": rows[:1], "meta": {"cursor": None}}),
                   seconds=.05, interval=.005, max_gets=2)
    assert missing["status"] == "api_visibility_incomplete" and missing["gets"] == 2
    cases = [("api_trace_or_project", lambda r: r[1].update(projectId="other")),
             ("api_parent_or_name", lambda r: r[1].update(parentObservationId=None)),
             ("api_status_or_open_span", lambda r: r[1].update(level="DEFAULT")),
             ("api_native_timestamp", lambda r: r[1].update(startTime="2026-10-01T00:00:02Z")),
             ("api_content_not_absent", lambda r: r[1].update(input="raw prompt")),
             ("api_native_attribute", lambda r: r[0]["metadata"].update({"attributes.test.false": "false"})),
             ("api_native_attribute", lambda r: r[0]["metadata"].update({"attributes.exagent.request_count": 11})),
             ("api_model_mapping", lambda r: r[2].update(type="SPAN")),
             ("api_usage_mapping", lambda r: r[2].update(usageDetails={"input": 3, "output": 1})),
             ("api_private_sentinel", lambda r: r[1].update(statusMessage="FAKE_PRIVATE_CONTENT")),
             ("api_unexpected_or_duplicate_id", lambda r: r[1].update(id=r[0]["id"])),
             ("api_unexpected_or_duplicate_id", lambda r: r.append(None)),
             ("api_unexpected_or_duplicate_id", lambda r: r[1].update(id="5" * 16))]
    for code, mutate in cases:
        changed = copy.deepcopy(rows)
        mutate(changed)
        fails(code, lambda: poll(manifest, "synthetic_exagent", read({"data": changed, "meta": {"cursor": None}}),
                                 seconds=.05, interval=.005, max_gets=2))
    fails("api_unexpected_pagination", lambda: poll(manifest, "synthetic_exagent", read({"data": rows, "meta": {"cursor": "next"}}), seconds=.05))
    return {"positive": 2, "negative": len(cases) + 4, "missing_rows_not_accepted": True,
            "project_identity_required_before_write": True,
            "bounded_gets_verified": True, "only_synthetic_new_ids": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--collector-binary", type=Path)
    parser.add_argument("--recipe", type=Path)
    parser.add_argument("--work", type=Path)
    args = parser.parse_args()
    if not args.run:
        print("Skipped: opt in with --run. No fixture, binary or credentials access.")
        return
    os.umask(0o077)
    source = Path(__file__).resolve().parent
    for path in source.glob("*.py"):
        import ast
        ast.parse(path.read_text(), filename=str(path))
    controls = api_checks()
    parent = args.work or Path(tempfile.mkdtemp(prefix="langfuse-preflight-parent-"))
    parent.mkdir(exist_ok=True, parents=True)
    work = Path(tempfile.mkdtemp(prefix="boundaries-", dir=parent))
    fake = work / "fake-credentials.json"
    private_json(fake, {"public_key": "pk_fake_explicit", "secret_key": "sk_fake_explicit"})
    authorization = credentials(fake)
    assert authorization.startswith("Basic ") and "sk_fake" not in authorization
    fake.chmod(0o644)
    fails("credential_file_ownership_or_mode", lambda: credentials(fake))
    fake.unlink()
    controls["fake_secret_fixture_removed"] = True
    spec = importlib.util.spec_from_file_location("langfuse_owner_tools", source / "run.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    logs = runner.ScalarLogs(work / "scalar-control.fifo")
    fake_line = json.dumps({"msg": "Partial success response", "dropped_spans": 1,
                            "error": "FAKE_PRIVATE_CONTENT", "Authorization": "Basic FAKE_PRIVATE_CONTENT"}).encode() + b"\n"
    os.write(logs.fd, fake_line)
    scalars = logs.finish()
    logs.close()
    assert scalars["partial_events"] == 1 and scalars["dropped_spans"] == 1
    assert "FAKE_PRIVATE_CONTENT" not in json.dumps(scalars) and scalars["raw_logs_retained"] is False
    controls["partial_loss_and_secret_discard_fifo"] = scalars
    lifecycle = None
    if args.collector_binary or args.recipe:
        assert args.collector_binary and args.recipe
        assert digest(args.collector_binary) == runner.COLLECTOR_SHA
        bridge = runner.Collector({"recipe": str(args.recipe.resolve()), "collector_binary": str(args.collector_binary.resolve())},
                                  work, "http://127.0.0.1:1/api/public/otel/v1/traces", authorization)
        del authorization
        try:
            bridge.start()
            lifecycle = bridge.stop()
        finally:
            for owner in runner.OWNED:
                owner.stop()
        assert lifecycle["owner"]["group_closed"] is True
        assert lifecycle["owner"]["reason"] == "stop"
        assert not (work / "collector-private.yaml").exists()
        assert lifecycle["loss_logs"]["raw_logs_retained"] is False
    for name in ("run.py", "poll.py", "http_fixture.py"):
        reply = subprocess.run(["/usr/bin/python3", str(source / name)], env={"PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"},
                               capture_output=True, timeout=2, check=True)
        assert b"Skipped" in reply.stdout and b"sk_fake" not in reply.stdout and not reply.stderr
    report = {"status": "synthetic_boundaries_verified_only", "api": controls, "collector_fifo_start_stop": lifecycle,
              "source_hashes": {p.name: digest(p) for p in sorted(source.iterdir()) if p.suffix in (".py", ".exs")},
              "credentials_real_read": False, "cloud_writes": 0, "native_a10_not_executed_here": True,
              "ui_accepted": False}
    private_json(work / "report.json", report)
    print(json.dumps({"status": report["status"], "report": str(work / "report.json"), "cloud_writes": 0}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print('{"status":"failed","code":"private_preflight_failure"}')
        raise SystemExit(1)
