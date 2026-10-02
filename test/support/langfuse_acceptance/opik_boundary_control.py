#!/usr/bin/env python3
"""Offline controls: credential shape/ownership, HTTP limits and source refusal."""
import argparse
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import urllib.error
from unittest.mock import patch
sys.dont_write_bytecode = True
import opik_api as api
import opik_run as driver
from api import BoundaryError, digest, private_json


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run", action="store_true")
    p.add_argument("--admission", type=Path)
    p.add_argument("--work", type=Path)
    args = p.parse_args()
    if not args.run:
        print("Skipped: explicit offline control admission required. No network or keys.")
        return
    work = Path(tempfile.mkdtemp(prefix="opik-boundary-controls-", dir=args.work))
    work.chmod(0o700)
    checks = []
    def rejects(label, function, wanted):
        try:
            function()
            raise AssertionError(label + " accepted")
        except BoundaryError as error:
            assert str(error) == wanted, label
            checks.append(label)
    key = work / "synthetic-key.json"
    private_json(key, {"api_key": "SYNTHETIC_KEY_ONLY"})
    assert api.credentials(key) == "SYNTHETIC_KEY_ONLY"
    checks.append("owned_0600_synthetic_key")
    key.chmod(0o644)
    rejects("mode_0644", lambda: api.credentials(key), "credential_file_ownership_or_mode")
    key.chmod(0o600)
    extra = work / "extra.json"
    private_json(extra, {"api_key": "SYNTHETIC_KEY_ONLY", "extra": "PRIVATE_KEY_CANARY"})
    rejects("extra_fields", lambda: api.credentials(extra), "credential_file_fields")
    for index, value in enumerate(("short", "PRIVATE_KEY_CANARY\n", "x" * 257)):
        path = work / (str(index) + ".json")
        private_json(path, {"api_key": value})
        rejects("key_shape_" + str(index), lambda: api.credentials(path), "credential_key_shape")
    large = work / "large.json"
    large.write_bytes(b"x" * 4097)
    large.chmod(0o600)
    rejects("credential_size", lambda: api.credentials(large), "credential_file_limit")
    # A changed admission must refuse before a nonexistent key is opened and
    # before Collector/project API setup. No live route is entered by this test.
    arguments = argparse.Namespace(admission=args.admission, admission_sha256="0" * 64,
                                   credentials_file=work / "DOES_NOT_EXIST", work=work)
    rejects("changed_admission_before_keys", lambda: driver.admitted(arguments), "admission_changed_before_keys")

    sealed = work / "synthetic-harness"
    sealed.mkdir()
    source = {}
    for name in ("opik_run.py", "opik_api.py", "api.py", "run.py"):
        path = sealed / name
        path.write_text("# synthetic source boundary control\n")
        source[name] = digest(path)
    admission = {"harness": str(sealed), "harness_hashes": source}
    rejects("mutable_driver_before_keys", lambda: driver.verify_executing_harness(admission),
            "opik_unsealed_driver_before_keys")
    with contextlib.ExitStack() as stack:
        stack.enter_context(patch.object(driver, "__file__", str(sealed / "opik_run.py")))
        for name in ("opik_api", "api", "run"):
            stack.enter_context(patch.object(sys.modules[name], "__file__", str(sealed / (name + ".py"))))
        driver.verify_executing_harness(admission)
        checks.append("executed_sealed_driver_and_helpers")
        (sealed / "opik_api.py").write_text("# changed helper\n")
        rejects("changed_executed_helper_before_keys", lambda: driver.verify_executing_harness(admission),
                "opik_unsealed_helper_before_keys")

    arguments = argparse.Namespace(project_id="wrong", workspace="synthetic-workspace")
    with patch.object(driver, "admitted", return_value={"project_id": "sealed", "workspace": "synthetic-workspace"}), \
            patch.object(api, "credentials", side_effect=AssertionError("credentials opened before scope guard")):
        rejects("worker_scope_before_keys", lambda: driver.read_worker(arguments),
                "opik_worker_scope_changed_before_keys")
    owner = driver.Owned(["/usr/bin/python3", "-c",
                          "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)"],
                         cwd=work, env=driver.closed_env())
    started = time.monotonic()
    rejects("api_owner_deadline", lambda: driver.wait_api_owner(owner, seconds=0.2), "owned_command_deadline")
    assert time.monotonic() - started < 1.25 and owner.process.returncode is not None
    checks.append("api_owner_cleanup_within_one_second")

    class Reply(io.BytesIO):
        status = 200
    captured = []
    class Opener:
        body = b"{}"
        error = None
        def open(self, request, timeout):
            captured.append((request, timeout))
            if self.error:
                raise self.error
            return Reply(self.body)
    opener = Opener()
    get = lambda key, path, query=None: api.get_json(key, path, query, workspace="synthetic-workspace")
    def build(*handlers):
        assert any(isinstance(h, api.NoRedirect) for h in handlers)
        assert any(getattr(h, "proxies", None) == {} for h in handlers)
        checks.append("no_redirect_or_inherited_proxy")
        return opener
    with patch.object(api.urllib.request, "build_opener", build):
        for route in ("/api/v1/private/spans/unknown", "/api/v1/private/traces/private", "/other"):
            before = len(captured)
            rejects("route_refused", lambda: get("SYNTHETIC_KEY_ONLY", route), "unadmitted_api_route")
            assert len(captured) == before
        result, size = get("SYNTHETIC_KEY_ONLY", "/api/v1/private/projects", {"name": "exagent"})
        assert result == {} and size == 2
        request, timeout = captured[-1]
        assert request.get_method() == "GET" and timeout == 2
        assert request.get_header("Comet-workspace") == "synthetic-workspace"
        assert request.get_header("Authorization") == "SYNTHETIC_KEY_ONLY"
        checks.append("exact_get_scope_and_header")
        opener.body = b"x" * (api.MAX_BODY + 1)
        rejects("body_limit", lambda: get("SYNTHETIC_KEY_ONLY", "/api/v1/private/spans"), "api_body_limit")
        opener.body = b"PRIVATE_RESPONSE_CANARY"
        rejects("malformed_json", lambda: get("SYNTHETIC_KEY_ONLY", "/api/v1/private/spans"), "api_json")
        opener.error = urllib.error.HTTPError("https://private", 401, "PRIVATE_RESPONSE_CANARY", {}, io.BytesIO(b"PRIVATE_RESPONSE_CANARY"))
        rejects("auth_error_private", lambda: get("SYNTHETIC_KEY_ONLY", "/api/v1/private/spans"), "api_http_401")
        opener.error = TimeoutError("PRIVATE_RESPONSE_CANARY")
        rejects("timeout_private", lambda: get("SYNTHETIC_KEY_ONLY", "/api/v1/private/spans"), "api_transport")
        rejects("redirect", lambda: api.NoRedirect().redirect_request(None), "api_redirect_refused")
    # Credential symlinks are refused by the OS NOFOLLOW boundary.
    link = work / "link.json"
    link.symlink_to(key)
    try:
        api.credentials(link)
        raise AssertionError("symlink accepted")
    except OSError:
        checks.append("credential_symlink_refused")
    result = {"status": "opik_offline_boundaries_passed", "checks": len(checks), "labels": checks,
              "network_requests": 0, "real_keys_read": False, "admission_sha256": digest(args.admission)}
    private_json(work / "receipt.json", result)
    print(json.dumps({"status": result["status"], "checks": len(checks), "receipt": str(work / "receipt.json")}))


if __name__ == "__main__":
    main()
