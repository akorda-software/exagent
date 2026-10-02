#!/usr/bin/env python3
"""Prepare an exact private A10 source, then explicitly admit one Langfuse wave."""
import argparse
import ctypes
import io
import json
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

sys.dont_write_bytecode = True
from api import BoundaryError, EU, credentials, digest, private_json

COLLECTOR_SHA = "910a66b1210e09143260914ef0634b4d234c789f23efc34bc9c7a3c0480324fa"
SOURCE = Path(__file__).resolve().parent
PROFILE = {"max_traces": 1, "spans_per_trace": 32, "native_etf_bytes_per_trace": 65_536,
           "http_payload_bytes": 65_536, "callback_batch_spans": 8, "concurrency": 1,
           "retries": 0, "queue_spans": 64, "collector_lifetime_ms": 30_000,
           "collector_stop_ms": 2_000, "rpc_deadline_ms": 1_200,
           "batch_deadline_ms": 2_000, "api_gets": 20, "api_seconds": 30,
           "identity_gets": 1, "identity_deadline_seconds": 3, "observations_gets": 19,
           "observations_deadline_seconds": 27}
MAX_LOG = 1_048_576
MAX_LINE = 65_536
RECIPE = ("isolated_exporter.ex", "vm_launcher.py", "vm_worker.exs", "collector.py", "collector.yaml")
OWNED = []


def require(test, code):
    if not test:
        raise BoundaryError(code)


def safe_name(value):
    require(bool(re.fullmatch(r"[a-zA-Z0-9_-]{1,80}", value or "")), "public_name_shape")
    return value


def closed_env(tooling=None, project=None, elixir_bin=None, erlang_bin=None, rebar=None):
    env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
           "PYTHONDONTWRITEBYTECODE": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
           "GIT_CONFIG_SYSTEM": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
    if tooling is not None:
        env.update({"PATH": f"{erlang_bin}:{elixir_bin}:/usr/bin:/bin", "MIX_HOME": str(tooling),
                    "MIX_ARCHIVES": str(tooling / "archives"), "HEX_HOME": str(tooling / "hex"),
                    "HEX_OFFLINE": "1", "REBAR_CACHE_DIR": str(tooling / "rebar"),
                    "MIX_REBAR3": str(rebar), "MIX_BUILD_PATH": str(project / "_build"),
                    "MIX_DEPS_PATH": str(project / "deps"), "EXAGENT_OFFLINE": "1", "MIX_ENV": "test",
                    "ERL_FLAGS": f'+S 4:4 +fnu -home {tooling / "erlang"}',
                    "OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT": "64", "OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT": "128",
                    "OTEL_SPAN_EVENT_COUNT_LIMIT": "8", "OTEL_SPAN_LINK_COUNT_LIMIT": "4",
                    "OTEL_EVENT_ATTRIBUTE_COUNT_LIMIT": "16", "OTEL_LINK_ATTRIBUTE_COUNT_LIMIT": "16"})
    return env


class Owned:
    """Only groups created and registered by this owner may be signalled."""
    def __init__(self, argv, *, cwd, env, stdout=subprocess.DEVNULL, stdin=subprocess.DEVNULL):
        # Process-local Linux ownership: adopt only our children's orphans. The
        # group-specific wait below cannot reap another registered owner's child.
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(36, 1, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), "owned_subreaper")
        self.closed = False
        mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
        try:
            def child():
                signal.pthread_sigmask(signal.SIG_SETMASK, mask)
            self.process = subprocess.Popen(argv, cwd=cwd, env=env, stdin=stdin, stdout=stdout,
                                            stderr=subprocess.DEVNULL, start_new_session=True,
                                            preexec_fn=child)
            self.group = self.process.pid
            require(os.getpgid(self.group) == self.group, "owned_group_registration")
            self.registered = True
            OWNED.append(self)
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, mask)

    def alive(self):
        # Do not reap/recycle the group leader while it remains a signal target.
        return os.waitid(os.P_PID, self.process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is None

    def stop(self, grace=2):
        if self.closed:
            return self.process.returncode
        require(self.process.returncode is None, "owned_leader_reaped_before_cleanup")
        try:
            os.killpg(self.group, signal.SIGTERM)
        except ProcessLookupError:
            pass
        until = time.monotonic() + grace
        while self.alive() and time.monotonic() < until:
            time.sleep(min(0.005, max(0, until - time.monotonic())))
        # The leader is still live or an unreaped zombie, pinning the registered
        # group ID. Reclaim remaining members before the leader may be recycled.
        try:
            os.killpg(self.group, signal.SIGKILL)
        except ProcessLookupError:
            pass
        reap_until = time.monotonic() + 1
        self.process.wait(timeout=max(0, reap_until - time.monotonic()))
        while time.monotonic() < reap_until:
            try:
                pid, _ = os.waitpid(-self.group, os.WNOHANG)
            except ChildProcessError:
                self.closed = True
                return self.process.returncode
            if not pid:
                time.sleep(0.005)
        raise BoundaryError("owned_group_cleanup_unconfirmed")


class ScalarLogs:
    """Drain an owned bounded FIFO; store no raw lines or remote error strings."""
    def __init__(self, path):
        os.mkfifo(path, 0o600)
        self.fd = os.open(path, os.O_RDWR | os.O_NONBLOCK | os.O_NOFOLLOW)
        self.buffer = bytearray()
        self.bytes = 0
        self.lines = 0
        self.partial_events = 0
        self.dropped_spans = 0
        self.other_events = 0
        self.transport_timeout_events = 0
        self.http_error_statuses = []

    def drain(self):
        while True:
            try:
                raw = os.read(self.fd, 65_536)
            except BlockingIOError:
                break
            if not raw:
                break
            self.bytes += len(raw)
            require(self.bytes <= MAX_LOG, "collector_log_limit")
            self.buffer.extend(raw)
            while b"\n" in self.buffer:
                line, _, rest = self.buffer.partition(b"\n")
                self.buffer = bytearray(rest)
                require(len(line) <= MAX_LINE, "collector_log_line_limit")
                try:
                    value = json.loads(line)
                except (ValueError, UnicodeError):
                    raise BoundaryError("collector_log_json") from None
                require(isinstance(value, dict), "collector_log_shape")
                self.lines += 1
                if value.get("msg") == "Partial success response":
                    lost = value.get("dropped_spans")
                    require(type(lost) is int and 0 <= lost <= 32, "collector_partial_shape")
                    self.partial_events += 1
                    self.dropped_spans += lost
                else:
                    self.other_events += 1
                    # Keep only bounded failure classifications; never retain
                    # the remote error string or response body.
                    error = value.get("error")
                    if isinstance(error, str):
                        if any(label in error for label in ("context deadline exceeded", "Client.Timeout", "i/o timeout")):
                            self.transport_timeout_events += 1
                        status = re.search(r"HTTP Status Code (\d{3})(?:\D|$)", error)
                        if status and 400 <= int(status[1]) <= 599 and len(self.http_error_statuses) < 8:
                            self.http_error_statuses.append(int(status[1]))
            require(len(self.buffer) <= MAX_LINE, "collector_log_line_limit")

    def finish(self):
        self.drain()
        require(not self.buffer, "collector_log_truncated")
        return {"bytes_processed_in_memory": self.bytes, "events": self.lines,
                "partial_events": self.partial_events, "dropped_spans": self.dropped_spans,
                "other_events": self.other_events, "raw_logs_retained": False,
                "transport_timeout_events": self.transport_timeout_events,
                "http_error_statuses": self.http_error_statuses,
                "loss_is_backend_warning_not_ack": True}

    def close(self):
        os.close(self.fd)


class Collector:
    def __init__(self, admission, work, endpoint, authorization=None, *, headers=None):
        self.work = work
        self.log = None
        self.owner = None
        self.frames = bytearray()
        self.ready = None
        self.closed = None
        self.config = work / "collector-private.yaml"
        config_created = False
        try:
            self.log = ScalarLogs(work / "collector.fifo")
            template = (Path(admission["recipe"]) / "collector.yaml").read_text()
            if admission.get("backend") == "opik":
                require(admission["profile"].get("http_timeout_ms") == 3_000, "opik_http_timeout_profile")
                require(template.count("    timeout: 500ms\n") == 1, "collector_timeout_template")
                template = template.replace("    timeout: 500ms\n", "    timeout: 3000ms\n")
            if headers is None:
                headers = {"x-langfuse-ingestion-version": "4"}
                if authorization:
                    headers["Authorization"] = authorization
            require(all(isinstance(k, str) and re.fullmatch(r"[A-Za-z0-9_-]+", k) and
                        isinstance(v, str) and not any(c in v for c in "\r\n")
                        for k, v in headers.items()), "collector_header_shape")
            template = template.replace("    encoding: proto\n", "    encoding: proto\n    headers:\n" +
                                        "".join("      " + k + ": " + json.dumps(v) + "\n" for k, v in headers.items()))
            template = template.replace("      encoding: json\n", "      encoding: json\n      output_paths: [" +
                                        json.dumps(str(work / "collector.fifo")) + "]\n      error_output_paths: [/dev/null]\n")
            descriptor = os.open(self.config, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            config_created = True
            with os.fdopen(descriptor, "w") as file:
                file.write(template)
            self.owner = Owned(["/usr/bin/python3", str(Path(admission["recipe"]) / "collector.py"), "--run",
                                "--binary", admission["collector_binary"], "--config", str(self.config),
                                "--log", "/dev/null", "--http-endpoint", endpoint,
                                "--lifetime-ms", str(admission["profile"]["collector_lifetime_ms"]),
                                "--stop-ms", str(admission["profile"]["collector_stop_ms"])],
                               cwd=work, env=closed_env(), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
            os.set_blocking(self.owner.process.stdout.fileno(), False)
        except BaseException:
            try:
                if self.owner is not None:
                    self.owner.process.stdin.close()
                    self.owner.stop(grace=3)
                    self.owner.process.stdout.close()
            finally:
                if self.log is not None:
                    self.log.close()
                if config_created:
                    self.config.unlink(missing_ok=True)
            raise

    def pump(self):
        self.log.drain()
        try:
            data = os.read(self.owner.process.stdout.fileno(), 8_192)
        except BlockingIOError:
            data = b""
        self.frames.extend(data)
        require(len(self.frames) <= 8_200, "collector_packet_limit")
        while len(self.frames) >= 4:
            size = struct.unpack("!I", self.frames[:4])[0]
            require(size <= 4_096, "collector_packet_limit")
            if len(self.frames) < 4 + size:
                break
            value = json.loads(self.frames[4:4 + size])
            del self.frames[:4 + size]
            require(isinstance(value, dict), "collector_packet_shape")
            if value.get("type") == "ready" and self.ready is None:
                require(value.get("registered") is True, "collector_group_unregistered")
                self.ready = value
            elif value.get("type") == "closed" and self.closed is None:
                self.closed = value
            else:
                raise BoundaryError("collector_packet_sequence")

    def start(self):
        until = time.monotonic() + 4
        while time.monotonic() < until and self.ready is None and self.closed is None:
            self.pump()
            time.sleep(0.01)
        require(self.ready is not None and self.closed is None, "collector_not_ready")
        return self.ready["grpc_port"]

    def stop(self):
        try:
            if self.owner.process.stdin is not None:
                try:
                    self.owner.process.stdin.write(struct.pack("!I", 5) + b"STOP\n")
                    self.owner.process.stdin.flush()
                except (BrokenPipeError, OSError):
                    pass
                try:
                    self.owner.process.stdin.close()
                except BrokenPipeError:
                    pass
            until = time.monotonic() + 4
            while time.monotonic() < until and (self.closed is None or self.owner.alive()):
                self.pump()
                time.sleep(0.01)
            self.pump()
            # The reviewed launcher owns Collector's separate group. Closing the
            # pipe/TERM asks it to clean that group before this owner reaps it.
            if self.owner.alive():
                self.owner.stop(grace=3)
                self.pump()
            else:
                self.owner.stop(grace=0)
            scalars = self.log.finish()
            require(self.closed is not None and self.closed.get("group_closed") is True,
                    "collector_cleanup_unconfirmed")
            require(self.closed.get("reason") in ("stop", "owner_closed"), "collector_lifecycle_failure")
            return {"owner": self.closed, "loss_logs": scalars}
        finally:
            self.log.close()
            self.owner.process.stdout.close()
            self.config.unlink(missing_ok=True)


def wait_owned(owner, *, seconds, tick=lambda: None):
    until = time.monotonic() + seconds
    try:
        while time.monotonic() < until:
            tick()
            if not owner.alive():
                return owner.stop(grace=0)
            time.sleep(0.01)
        raise BoundaryError("owned_command_deadline")
    finally:
        owner.stop()


def package_files(path):
    # Public Hex archive format only; this is never an OTLP parser/encoder.
    with tarfile.open(path) as outer:
        member = outer.getmember("contents.tar.gz")
        require(member.isfile() and member.size <= 20_000_000, "package_contents_limit")
        raw = outer.extractfile(member).read()
    result = {}
    expanded = 0
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as inner:
        for member in inner.getmembers():
            name = Path(member.name)
            require(not name.is_absolute() and ".." not in name.parts and (member.isfile() or member.isdir()),
                    "package_member_boundary")
            if member.isfile():
                require(member.size <= 10_000_000, "package_file_limit")
                require(not any(part.startswith(".env") for part in name.parts), "package_secret_file_refused")
                expanded += member.size
                require(expanded <= 67_108_864, "package_expanded_limit")
                result[member.name] = inner.extractfile(member).read()
    require(result and len(result) <= 2_000, "package_file_count")
    return result


def tree_hashes(root):
    result = {}
    for path in sorted(root.rglob("*")):
        if path.is_file() and not any(part.startswith(".env") or part == "__pycache__" for part in path.parts):
            require(not path.is_symlink(), "private_source_symlink")
            result[str(path.relative_to(root))] = digest(path)
    require(len(result) <= 20_000, "private_source_file_count")
    return result


def verify_admission(admission):
    require(admission["status"] == "prepared_for_explicit_wave", "admission_not_ready")
    require(digest(admission["package"]) == admission["tar_sha256"], "package_changed")
    require(digest(admission["collector_binary"]) == COLLECTOR_SHA, "collector_changed")
    require(tree_hashes(Path(admission["project"])) == admission["project_hashes"], "private_consumer_changed")
    require(tree_hashes(Path(admission["harness"])) == admission["harness_hashes"], "harness_changed")
    require(tree_hashes(Path(admission["recipe"])) == admission["recipe_hashes"], "recipe_changed")
    require(digest(admission["flow_plugin"]) == admission["flow_plugin_sha256"], "flow_plugin_changed")
    for path, sha in admission["tool_hashes"].items():
        require(digest(path) == sha, "tool_changed")


def native_env(admission, work, mode, wave, grpc_port=None):
    project, tooling = Path(admission["project"]), Path(admission["tooling"])
    env = closed_env(tooling, project, Path(admission["elixir_bin"]), Path(admission["erlang_bin"]),
                     Path(admission["rebar3"]))
    env.update({"LF_MODE": mode, "LF_MAX_TRACES": str(admission["profile"]["max_traces"]),
                "LF_ISOLATED_EXPORTER": str(Path(admission["recipe"]) / "isolated_exporter.ex"),
                "LF_FLOW_PLUGIN": admission["flow_plugin"], "LF_TAR_SHA256": admission["tar_sha256"],
                "LF_WAVE": wave, "LF_MANIFEST": str(work / "native-manifest.json"),
                "LF_NATIVE_REPORT": str(work / "native-report.json"), "LF_PYTHON": "/usr/bin/python3",
                "LF_ELIXIR": str(Path(admission["elixir_bin"]) / "elixir"),
                "LF_BEAM_PATH": str(project / "_build/lib/*/ebin"),
                "LF_VM_LAUNCHER": str(Path(admission["recipe"]) / "vm_launcher.py"),
                "LF_VM_WORKER": str(Path(admission["recipe"]) / "vm_worker.exs")})
    if grpc_port:
        env["LF_GRPC_PORT"] = str(grpc_port)
    if admission.get("backend") == "opik":
        env["LF_REQUEST_PROFILE"] = str(Path(admission["harness"]) / "opik_profile.exs")
        env.update(LF_BATCH_DEADLINE_MS=str(admission["profile"]["batch_deadline_ms"]),
                   LF_RPC_DEADLINE_MS=str(admission["profile"]["rpc_deadline_ms"]),
                   LF_EXPORT_TIMEOUT_MS=str(admission["profile"]["export_timeout_ms"]))
    return env


def native(admission, work, *, wave, collector=None):
    descriptor = os.open(work / "native-manifest.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(descriptor)
    descriptor = os.open(work / "native-report.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(descriptor)
    mode = "live" if collector else "preview"
    port = collector.start() if collector else None
    paths = sorted((Path(admission["project"]) / "_build/lib").glob("*/ebin"))
    require(paths and all(path.is_dir() for path in paths), "private_beam_path")
    argv = [str(Path(admission["elixir_bin"]) / "elixir")]
    for path in paths:
        argv.extend(["-pa", str(path)])
    argv.append(str(Path(admission["harness"]) / "producer.exs"))
    with (work / "producer.log").open("xb") as log:
        owner = Owned(argv, cwd=Path(admission["project"]), env=native_env(admission, work, mode, wave, port), stdout=log)
        code = wait_owned(owner, seconds=admission["profile"].get("native_deadline_seconds", 24),
                          tick=collector.pump if collector else lambda: None)
    require(code == 0, "native_phase_exit")
    manifest = json.loads((work / "native-manifest.json").read_text())
    result = json.loads((work / "native-report.json").read_text())
    require(manifest["source_tar_sha256"] == admission["tar_sha256"] and manifest["wave"] == wave,
            "native_source_receipt")
    return manifest, result


def prepare(args):
    backend = getattr(args, "backend", "langfuse")
    require(backend in ("langfuse", "opik"), "prepare_backend")
    if backend == "opik":
        safe_name(args.workspace)
    required = (args.consumer, args.package, args.tar_sha256, args.collector_binary,
                args.elixir_bin, args.erlang_bin, args.rebar3, args.archives, args.project_id)
    require(all(required), "prepare_arguments")
    safe_name(args.project_id)
    require(args.max_traces in (1, 2), "trace_count_admission")
    origin = args.consumer.resolve()
    require(str(origin).startswith("/tmp/"), "private_consumer_required")
    require(digest(args.package) == args.tar_sha256, "package_checksum")
    require(digest(args.collector_binary) == COLLECTOR_SHA, "official_collector_checksum")
    require(origin.is_dir() and (origin / "mix.exs").is_file(), "private_mix_consumer")
    for path in origin.rglob("*"):
        if path.is_symlink():
            require(path.resolve().is_relative_to(origin), "external_private_link")
    work = Path(tempfile.mkdtemp(prefix="langfuse-prepare-", dir=args.work))
    work.chmod(0o700)
    project = work / "project"
    shutil.copytree(origin, project, ignore=shutil.ignore_patterns("__pycache__", ".env", ".env.*"))
    packaged = project / args.package_source
    require(packaged.resolve().is_relative_to(project), "package_source_boundary")
    contents = package_files(args.package)
    for name, raw in contents.items():
        file = packaged / name
        require(file.is_file() and file.read_bytes() == raw, "package_source_mismatch")
    recipe = work / "recipe"
    recipe.mkdir()
    for name in RECIPE:
        shutil.copy2(packaged / "examples/otlp_transport" / name, recipe / name)
    harness = work / "harness"
    harness.mkdir()
    for path in SOURCE.iterdir():
        if path.suffix in (".py", ".exs"):
            shutil.copy2(path, harness / path.name)
    plugin = work / "flow_pipeline.exs"
    shutil.copy2(packaged / "examples/flow_pipeline.exs", plugin)
    binary = work / "otelcol"
    shutil.copy2(args.collector_binary, binary)
    binary.chmod(0o700)
    package = work / "candidate.tar"
    shutil.copy2(args.package, package)
    tooling = work / "tooling"
    shutil.copytree(args.archives, tooling / "archives")
    (tooling / "erlang").mkdir()
    env = closed_env(tooling, project, args.elixir_bin.resolve(), args.erlang_bin.resolve(), args.rebar3.resolve())
    with (work / "compile.log").open("xb") as log:
        owner = Owned([str(args.elixir_bin.resolve() / "mix"), "compile", "--no-deps-check", "--warnings-as-errors"],
                      cwd=project, env=env, stdout=log)
        code = wait_owned(owner, seconds=90)
    require(code == 0, "private_compile_exit")
    admission = {"status": "preparing", "project": str(project), "tooling": str(tooling), "recipe": str(recipe),
                 "harness": str(harness), "flow_plugin": str(plugin), "package": str(package),
                 "tar_sha256": args.tar_sha256, "collector_binary": str(binary), "collector_sha256": COLLECTOR_SHA,
                 "project_id": args.project_id, "base": EU, "profile": {**PROFILE, "max_traces": args.max_traces},
                 "elixir_bin": str(args.elixir_bin.resolve()), "erlang_bin": str(args.erlang_bin.resolve()),
                 "rebar3": str(args.rebar3.resolve()), "origin_freeze": str(origin),
                 "origin_is_candidate_only_if_parent_seals_it": True, "ui_accepted": False,
                 "package_source_files": len(contents)}
    if backend == "opik":
        admission.update(backend="opik", base="https://www.comet.com/opik", workspace=args.workspace,
                         project_name="exagent", request_projection="opik_metadata_native_v1")
        admission["profile"].update(api_gets=5, api_seconds=12, observations_gets=4,
                                    observations_deadline_seconds=7, max_posts=5, http_timeout_ms=3_000,
                                    rpc_deadline_ms=3_500, batch_deadline_ms=5_000,
                                    export_timeout_ms=20_000, native_deadline_seconds=28,
                                    collector_lifetime_ms=30_000)
    local = work / "local-preflight"
    local.mkdir(mode=0o700)
    fixture = Owned(["/usr/bin/python3", str(harness / "http_fixture.py"), "--run", "--backend", backend,
                     "--workspace", admission.get("workspace", "synthetic"),
                     "--ready", str(local / "fixture-ready.json"), "--report", str(local / "fixture.json")],
                    cwd=local, env=closed_env())
    collector = None
    try:
        until = time.monotonic() + 2
        while not (local / "fixture-ready.json").exists() and time.monotonic() < until:
            time.sleep(0.01)
        require((local / "fixture-ready.json").exists(), "fixture_not_ready")
        port = json.loads((local / "fixture-ready.json").read_text())["port"]
        route = "/api/v1/private/otel/v1/traces" if backend == "opik" else "/api/public/otel/v1/traces"
        headers = {"projectName": "exagent", "Comet-Workspace": args.workspace} if backend == "opik" else None
        collector = Collector(admission, local, f"http://127.0.0.1:{port}" + route, headers=headers)
        manifest, result = native(admission, local, wave="local-preflight", collector=collector)
        lifecycle = collector.stop()
        collector = None
        if manifest["status"] != "native_admitted":
            fixture.stop()
            admission["status"] = "blocked_profile"
            admission["local"] = {"manifest": manifest, "native": result, "collector": lifecycle}
        else:
            require(result["status"] == "native_phase_complete", "native_local_export_failed")
            require(wait_owned(fixture, seconds=7) == 0, "fixture_exit")
            wire = json.loads((local / "fixture.json").read_text())
            require(wire["total_requests"] == len(result["transport_receipts"]) and wire["total_requests"] in range(1, 9),
                    "local_http_request_count")
            require(all(r["bytes"] <= 65_536 and r["authorization_absent"] and
                        (r["opik_headers_verified"] if backend == "opik" else r["ingestion_version"] == "4")
                        for r in wire["requests"]), "local_http_limits")
            require(lifecycle["loss_logs"]["partial_events"] == 0 and lifecycle["loss_logs"]["other_events"] == 0,
                    "local_collector_warnings")
            admission["status"] = "prepared_for_explicit_wave"
            admission["local"] = {"manifest": manifest, "native": result, "collector": lifecycle, "http_fixture": wire}
    finally:
        if collector:
            collector.stop()
        fixture.stop()
    admission.update({"project_hashes": tree_hashes(project), "harness_hashes": tree_hashes(harness),
                      "recipe_hashes": tree_hashes(recipe), "flow_plugin_sha256": digest(plugin),
                      "tool_hashes": {str(path): digest(path) for path in
                                      (args.elixir_bin.resolve() / "elixir", args.elixir_bin.resolve() / "mix",
                                       args.erlang_bin.resolve() / "erl", args.rebar3.resolve())},
                      "credentials_read": False, "cloud_writes": 0,
                      "compile_warning_lines": sum("warning:" in line for line in (work / "compile.log").read_text().splitlines())})
    path = work / "admission.json"
    private_json(path, admission)
    print(json.dumps({"status": admission["status"], "admission": str(path), "admission_sha256": digest(path),
                      "trace_spans": [t["span_count"] for t in manifest["traces"]],
                      "trace_etf_bytes": [t["native_etf_bytes"] for t in manifest["traces"]], "cloud_writes": 0}))
    return admission


def metrics(collector):
    url = f'http://127.0.0.1:{collector.ready["metrics_port"]}/metrics'
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url, timeout=1) as response:
        raw = response.read(524_289)
    require(len(raw) <= 524_288, "collector_metrics_limit")
    names = {"otelcol_receiver_accepted_spans", "otelcol_receiver_refused_spans",
             "otelcol_exporter_sent_spans", "otelcol_exporter_send_failed_spans"}
    totals = {name: 0 for name in names}
    for line in raw.decode("utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        name = line.split("{", 1)[0].split(" ", 1)[0]
        if name in names:
            value = float(line.rsplit(" ", 1)[1])
            require(value >= 0 and value.is_integer(), "collector_metric_shape")
            totals[name] += int(value)
    return {"counters": totals, "ack_is_not_durable_ingestion": True,
            "partial_rejections_may_increment_sent_spans": True}


def live(args):
    require(all((args.admission, args.admission_sha256, args.wave, args.credentials_file)), "wave_arguments")
    safe_name(args.wave)
    require(digest(args.admission) == args.admission_sha256, "admission_checksum")
    admission = json.loads(args.admission.read_text())
    verify_admission(admission)
    work = Path(tempfile.mkdtemp(prefix="langfuse-wave-", dir=args.work))
    work.chmod(0o700)
    # Persist source and scope before reading secrets or starting an exporter.
    source = {"wave": args.wave, "admission_sha256": args.admission_sha256,
              "tar_sha256": admission["tar_sha256"], "profile": admission["profile"],
              "project_id": admission["project_id"], "base": admission["base"],
              "harness_hashes": admission["harness_hashes"], "recipe_hashes": admission["recipe_hashes"],
              "flow_plugin_sha256": admission["flow_plugin_sha256"], "collector_sha256": COLLECTOR_SHA,
              "trace_ids_fresh_at_runtime": True, "ui_accepted": False}
    private_json(work / "source-before-write.json", source)
    scope = Owned(["/usr/bin/python3", str(Path(admission["harness"]) / "poll.py"), "--run", "--scope-only",
                   "--credentials-file", str(args.credentials_file.resolve()), "--report", str(work / "project-scope.json"),
                   "--project-id", admission["project_id"], "--base", EU], cwd=work, env=closed_env())
    require(wait_owned(scope, seconds=3) == 0, "project_scope_failed_before_write")
    project_identity = json.loads((work / "project-scope.json").read_text())
    authorization = credentials(args.credentials_file)
    collector = Collector(admission, work, EU + "/api/public/otel/v1/traces", authorization)
    del authorization
    manifest = None
    native_result = None
    bridge_metrics = None
    failure = None
    try:
        manifest, native_result = native(admission, work, wave=args.wave, collector=collector)
        bridge_metrics = metrics(collector)
    except BoundaryError as error:
        failure = str(error)
    finally:
        lifecycle = collector.stop()
    receipt = {"source": source, "native": native_result, "collector_metrics": bridge_metrics,
               "collector": lifecycle, "project_identity": project_identity,
               "ui_accepted": False, "scope": "native_cloud_api_only"}
    if manifest and manifest["status"] == "native_admitted":
        receipt["trace_ids"] = [t["trace_id"] for t in manifest["traces"]]
        receipt["ui_links"] = [EU + "/project/" + admission["project_id"] + "/traces/" + trace_id
                               for trace_id in receipt["trace_ids"]]
        owner = Owned(["/usr/bin/python3", str(Path(admission["harness"]) / "poll.py"), "--run",
                       "--manifest", str(work / "native-manifest.json"),
                       "--credentials-file", str(args.credentials_file.resolve()),
                       "--report", str(work / "api.json"), "--project-id", admission["project_id"], "--base", EU,
                       "--seconds", "27", "--max-gets", "19"],
                      cwd=work, env=closed_env())
        try:
            code = wait_owned(owner, seconds=27)
            receipt["api"] = (json.loads((work / "api.json").read_text())
                              if (work / "api.json").is_file()
                              else {"status": "api_failed_private_boundary"})
        except BoundaryError as error:
            receipt["api"] = {"status": str(error)}
    else:
        receipt["api"] = {"status": "not_polled_without_new_native_manifest"}
    verified = (failure is None and native_result and native_result["status"] == "native_phase_complete" and
                receipt["api"]["status"] == "native_api_rows_verified_only" and
                lifecycle["loss_logs"]["partial_events"] == 0 and lifecycle["loss_logs"]["other_events"] == 0)
    receipt["status"] = "native_api_verified_ui_pending" if verified else "native_api_not_qualified"
    receipt["failure_code"] = failure
    private_json(work / "receipt.json", receipt)
    print(json.dumps({"status": receipt["status"], "receipt": str(work / "receipt.json"),
                      "trace_ids": receipt.get("trace_ids", []), "ui_links": receipt.get("ui_links", []),
                      "ui_accepted": False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare", action="store_true")
    mode.add_argument("--run", action="store_true")
    for name in ("consumer", "package", "collector-binary", "elixir-bin", "erlang-bin", "rebar3", "archives", "work",
                 "admission", "credentials-file"):
        parser.add_argument("--" + name, type=Path)
    parser.add_argument("--tar-sha256")
    parser.add_argument("--package-source", default=".")
    parser.add_argument("--project-id")
    parser.add_argument("--max-traces", type=int, default=1, choices=(1, 2))
    parser.add_argument("--admission-sha256")
    parser.add_argument("--wave")
    args = parser.parse_args()
    if not (args.prepare or args.run):
        print("Skipped: explicitly choose --prepare or --run. No source, credentials or network access.")
        return
    os.umask(0o077)
    def interrupted(_signal, _frame):
        raise BoundaryError("owner_interrupted")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    args.work = (args.work or Path("/tmp")).resolve()
    require(args.work.is_relative_to(Path("/tmp")), "private_work_parent_required")
    args.work.mkdir(parents=True, exist_ok=True, mode=0o700)
    if args.prepare:
        prepare(args)
    else:
        live(args)


if __name__ == "__main__":
    try:
        main()
    except BoundaryError as error:
        print(json.dumps({"status": "failed", "code": str(error)}))
        raise SystemExit(1)
    except (Exception, KeyboardInterrupt):
        print('{"status":"failed","code":"private_owner_failure"}')
        raise SystemExit(1)
    finally:
        # No target is derived from /proc, a filename, argv, or a remote ID.
        # All entries are the still-owned leaders from this process's Popen.
        signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
        for owner in reversed(OWNED):
            owner.stop(grace=3)
