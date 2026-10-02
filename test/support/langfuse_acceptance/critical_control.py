#!/usr/bin/env python3
"""Offline ownership, constructor rollback and privacy regression controls."""
import argparse
import copy
import ctypes
import errno
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parent
HARNESS = Path(os.environ.get("CRITICAL027_HARNESS", BASE))
sys.path.insert(0, str(HARNESS))
import opik_api
import opik_control
import opik_run
import run


def record(path, value):
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write("\n")


def ownership(work, fixed):
    # This controller adopts only descendants of children it creates. Cleanup
    # targets the recorded group, while our recorded grandchild pins its identity.
    libc = ctypes.CDLL(None, use_errno=True)
    assert libc.prctl(36, 1, 0, 0, 0) == 0
    results = []
    for mode in ("normal", "leader_exit", "deadline"):
        path = work / (mode + "-child.json")
        child_code = "import time; time.sleep(0.05)" if mode == "normal" else (
            "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)")
        code = (
            "import json,os,signal,subprocess,sys,time; "
            "child=subprocess.Popen([sys.executable,'-c'," + repr(child_code) + "]); "
            "open(sys.argv[1],'w').write(json.dumps({'pid':child.pid,'group':os.getpgrp()})); "
            + ("child.wait(timeout=1)" if mode == "normal" else
               "time.sleep(0.1)" if mode == "leader_exit" else
               "signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)")
        )
        owner = run.Owned([sys.executable, "-c", code, str(path)], cwd=work, env=run.closed_env())
        until = time.monotonic() + 2
        while not path.exists() and time.monotonic() < until:
            time.sleep(0.005)
        assert path.is_file()
        child = json.loads(path.read_text())
        assert child["group"] == owner.group and os.getpgid(child["pid"]) == owner.group
        started = time.monotonic()
        if mode == "deadline":
            time.sleep(0.05)
        try:
            result = run.wait_owned(owner, seconds=0.25 if mode == "deadline" else 2)
            failure = None
        except run.BoundaryError as error:
            result, failure = None, str(error)
        try:
            info = os.waitid(os.P_PID, child["pid"], os.WEXITED | os.WNOHANG | os.WNOWAIT)
            child_alive = info is None
        except ChildProcessError:
            # Normal leader already waited for its own child.
            child_alive = False
        observed = {"mode": mode, "exit": result, "code": failure,
                    "elapsed_ms": round((time.monotonic() - started) * 1000),
                    "leader_reaped": owner.process.returncode is not None,
                    "registered_descendant_alive_after_stop": child_alive}
        if child_alive:
            # Never signal a recycled or discovered target: both values came
            # from this spawn and the existing descendant still pins the group.
            assert os.getpgid(child["pid"]) == owner.group
            os.killpg(owner.group, signal.SIGKILL)
        try:
            os.waitpid(child["pid"], 0)
        except ChildProcessError:
            pass
        assert owner.process.returncode is not None
        observed["control_cleanup_complete"] = True
        results.append(observed)
    record(work / "ownership.json", {"source": str(HARNESS / "run.py"), "results": results,
                                      "cloud_requests": 0, "credential_reads": 0})
    assert results[0]["registered_descendant_alive_after_stop"] is False
    assert results[1]["registered_descendant_alive_after_stop"] is (not fixed)
    assert results[2]["registered_descendant_alive_after_stop"] is False
    if fixed:
        # Another registered group's exited leader must remain waitable while
        # cleanup adopts/reaps children of the first group.
        other = run.Owned([sys.executable, "-c", "pass"], cwd=work, env=run.closed_env())
        until = time.monotonic() + 2
        while other.alive() and time.monotonic() < until:
            time.sleep(0.005)
        assert not other.alive()
        current = run.Owned([sys.executable, "-c", "import time; time.sleep(30)"], cwd=work, env=run.closed_env())
        current.stop(grace=0)
        assert not other.alive() and other.process.returncode is None
        assert other.stop(grace=0) == 0
        record(work / "group-specific-reap.json", {"other_registered_group_leader_preserved": True,
                                                    "both_groups_closed": current.closed and other.closed,
                                                    "cloud_requests": 0, "credential_reads": 0})


def privacy(work, fixed):
    timestamp = 1_759_363_200_000
    root = {"id": "1" * 16, "parent_id": None, "name": "exagent.application",
            "start_time_ms": timestamp, "end_time_ms": timestamp + 10, "level": "DEFAULT",
            "attributes": {"test.synthetic": True, "test.false": False}}
    model = {"id": "2" * 16, "parent_id": root["id"], "name": "exagent.model",
             "start_time_ms": timestamp + 1, "end_time_ms": timestamp + 9, "level": "ERROR",
             "attributes": {"exagent.operation": "model", "gen_ai.request.model": "test",
                            "gen_ai.provider.name": "test", "gen_ai.usage.input_tokens": 3,
                            "gen_ai.usage.output_tokens": 2, "error.type": "validation_error"}}
    trace = {"trace_id": "1" * 32, "spans": [root, model], "span_count": 2,
             "resource_attributes": {"test.synthetic": True, "test.false": False}}
    project = "00000000-0000-7000-8000-000000000001"
    original = opik_control.fixtures(trace, project)
    results = []
    mutations = {
        "baseline": lambda page: None,
        "extra_content_metadata": lambda page: page["content"][0]["metadata"].update(
            {"exagent.content.prompt": "SYNTHETIC_NEW_PRIVATE_CONTENT"}),
        "input_content": lambda page: page["content"][0].update(input={"prompt": "SYNTHETIC_NEW_PRIVATE_CONTENT"}),
        "error_message_content": lambda page: page["content"][1]["error_info"].update(
            message="SYNTHETIC_NEW_PRIVATE_CONTENT", traceback="SYNTHETIC_NEW_PRIVATE_CONTENT"),
        "expected_boolean_changed": lambda page: page["content"][0]["metadata"].update({"test.false": "false"}),
        "known_sentinel": lambda page: page["content"][0]["metadata"].update(
            {"exagent.content.prompt": "KNOWN_CONTENT_SENTINEL"}),
    }
    for label, mutation in mutations.items():
        page = copy.deepcopy(original)
        mutation(page)
        value = opik_api.inspect_page(page, trace, project, ["KNOWN_CONTENT_SENTINEL"])
        text = json.dumps(value)
        results.append({"label": label, "status": value["status"], "codes": value["mismatch_codes"],
                        "raw_in_diagnostics": "SYNTHETIC_NEW_PRIVATE_CONTENT" in text or "KNOWN_CONTENT_SENTINEL" in text})
    record(work / "privacy.json", {"source": str(HARNESS / "opik_api.py"), "results": results,
                                    "remote_responses": 0, "cloud_requests": 0, "credential_reads": 0})
    assert results[0]["status"] == "native_api_rows_verified_only"
    assert results[1]["status"] == ("native_api_not_qualified" if fixed else "native_api_rows_verified_only")
    assert results[2]["status"] == "native_api_not_qualified"
    assert results[3]["status"] == ("native_api_not_qualified" if fixed else "native_api_rows_verified_only")
    assert results[4]["status"] == "native_api_not_qualified"
    assert results[5]["status"] == "native_api_not_qualified"
    assert not any(result["raw_in_diagnostics"] for result in results)


def constructor(work, exhaust, fixed):
    fd_before = len(list(Path("/proc/self/fd").iterdir()))
    admission = {"recipe": str(BASE.parents[2] / "examples/otlp_transport"),
                 "collector_binary": str(work / "NOT_EXECUTED"),
                 "profile": {"collector_lifetime_ms": 100, "collector_stop_ms": 100}}
    old_limit = resource.getrlimit(resource.RLIMIT_NOFILE)
    descriptors = []
    if exhaust:
        resource.setrlimit(resource.RLIMIT_NOFILE, (64, old_limit[1]))
        # Leave 2 free descriptors: FIFO and YAML can be created; Popen's pipes
        # then hit a real process-local EMFILE, without any child creation.
        while True:
            try:
                descriptors.append(os.open(os.devnull, os.O_RDONLY))
            except OSError as error:
                assert error.errno == errno.EMFILE
                break
        for _ in range(2):
            os.close(descriptors.pop())
    try:
        headers = {"Authorization": "SYNTHETIC_AUTH_NO_REAL_KEY"} if exhaust else {"Bad\nHeader": "invalid"}
        try:
            run.Collector(admission, work, "http://127.0.0.1:1/synthetic", headers=headers)
            raise AssertionError("constructor should fail")
        except (OSError, run.BoundaryError) as error:
            code = error.errno if isinstance(error, OSError) else str(error)
    finally:
        for descriptor in descriptors:
            os.close(descriptor)
        resource.setrlimit(resource.RLIMIT_NOFILE, old_limit)
    config = work / "collector-private.yaml"
    retained = config.exists()
    has_header = b"SYNTHETIC_AUTH_NO_REAL_KEY" in config.read_bytes() if retained else False
    # Only scalar facts survive; remove this control's own synthetic header file.
    config.unlink(missing_ok=True)
    result = {"mode": "emfile" if exhaust else "header_denial", "failure": code,
              "private_config_retained_after_constructor_failure": retained,
              "synthetic_authorization_retained": has_header,
              "file_descriptor_delta": len(list(Path("/proc/self/fd").iterdir())) - fd_before,
              "children_created": len(run.OWNED), "cloud_requests": 0, "real_keys_read": False}
    record(work / "constructor.json", result)
    assert result["children_created"] == 0
    assert retained is (exhaust and not fixed) and has_header is (exhaust and not fixed)
    assert result["file_descriptor_delta"] == (0 if fixed else 1)


def collector_positive(work):
    binary = Path(os.environ["OTELCOL_BINARY"])
    assert hashlib.sha256(binary.read_bytes()).hexdigest() == run.COLLECTOR_SHA
    admission = {"recipe": str(BASE.parents[2] / "examples/otlp_transport"), "collector_binary": str(binary),
                 "backend": "opik", "profile": {"collector_lifetime_ms": 1_000, "collector_stop_ms": 100,
                                                   "http_timeout_ms": 3_000}}
    fd_before = len(list(Path("/proc/self/fd").iterdir()))
    collector = run.Collector(admission, work, "http://127.0.0.1:1/synthetic", headers={})
    try:
        collector.start()
    finally:
        lifecycle = collector.stop()
    result = {"status": "owned_collector_started_and_stopped", "collector_sha256": run.COLLECTOR_SHA,
              "lifecycle": lifecycle, "private_config_removed": not collector.config.exists(),
              "file_descriptor_delta": len(list(Path("/proc/self/fd").iterdir())) - fd_before,
              "network_scope": "loopback_readiness_only", "cloud_requests": 0,
              "otlp_posts": 0, "credential_reads": 0}
    record(work / "collector-positive.json", result)
    assert result["private_config_removed"] and result["file_descriptor_delta"] == 0
    assert lifecycle["owner"]["group_closed"] and lifecycle["owner"]["reason"] == "stop"


def defaults_and_denial(work):
    results = []
    for entry in ("opik_run.py", "read_only.py", "run.py"):
        arguments = [sys.executable, str(HARNESS / entry), "--credentials-file", str(work / "NOT_A_KEY"),
                     "--work", str(work)]
        result = subprocess.run(arguments, cwd=work, env=run.closed_env(), timeout=2,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 0 and result.stdout.startswith(b"Skipped:") and not result.stderr
        results.append({"entry": entry, "exit": result.returncode, "default_skipped": True})
    # Corruptions at the outer admission/plan gates are exercised with a key
    # path that does not exist. A stat/open attempt would therefore change the
    # fixed refusal label, even though no real secret is ever available.
    inputs = (("opik_run.py", "--admission", "--admission-sha256", "admission_changed_before_keys"),
              ("read_only.py", "--plan", "--plan-sha256", "read_plan_changed_before_keys"))
    for index, (entry, path_flag, sha_flag, expected) in enumerate(inputs):
        path = work / (str(index) + "-unsealed.json")
        record(path, {})
        command = [sys.executable, str(HARNESS / entry), "--run", path_flag, str(path), sha_flag, "0" * 64,
                   "--credentials-file", str(work / "NOT_A_KEY"), "--work", str(work)]
        result = subprocess.run(command, cwd=work, env=run.closed_env(), timeout=2,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        value = json.loads(result.stdout)
        assert result.returncode == 1 and value["code"] == expected and not result.stderr
        results.append({"entry": entry, "exit": result.returncode, "refusal": value["code"],
                        "credential_file_exists": False})
    assert set(p.name for p in work.iterdir()) == {"0-unsealed.json", "1-unsealed.json"}
    record(work / "defaults-and-denial.json", {"results": results, "cloud_requests": 0,
                                               "credential_reads": 0, "new_owned_groups": 0})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("ownership", "privacy", "constructor-emfile", "constructor-denial", "defaults-and-denial", "collector-positive"))
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--expect-fixed", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    args.work.mkdir(parents=True, mode=0o700)
    if args.mode == "ownership":
        ownership(args.work, args.expect_fixed)
    elif args.mode == "privacy":
        privacy(args.work, args.expect_fixed)
    elif args.mode == "defaults-and-denial":
        defaults_and_denial(args.work)
    elif args.mode == "collector-positive":
        collector_positive(args.work)
    else:
        constructor(args.work, args.mode == "constructor-emfile", args.expect_fixed)
    print(json.dumps({"status": "counterexample_and_causal_control_recorded", "mode": args.mode}))


if __name__ == "__main__":
    main()
