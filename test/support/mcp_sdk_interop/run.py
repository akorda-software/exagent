"""Opt-in official SDK MCP interop. With no profile, no subprocess or network runs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path
from typing import Any


SDK_VERSION = "2.2.0"
SDK_WHEEL = "mcp-2.2.0-py3-none-any.whl"
SDK_SHA256 = "bde982589473a060ae145e3406e9a5333fe538c97229ba841f5a7f92be004f81"
TYPES_WHEEL = "mcp_types-2.2.0-py3-none-any.whl"
TYPES_SHA256 = "ea476b73ee86709ab5abc9452385ed36cc05907e582355622e294595c9a04f13"
PROFILES = ("stdio", "http-json-session", "http-json-stateless", "http-sse-session", "http-sse-stateless")
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def dump(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean_environment(run_dir: Path) -> dict[str, str]:
    # Explicit tooling inputs only. Do not copy provider credentials, auth, .env,
    # project selectors, proxy settings, Python injection, or global pip settings.
    env = {
        "PATH": os.environ.get("PATH", os.defpath),
        "LANG": "C.UTF-8",
        "PYTHONNOUSERSITE": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
        "PIP_CONFIG_FILE": os.devnull,
        "EXAGENT_OFFLINE": "1",
        "MIX_ENV": "test",
        "MIX_HOME": str(run_dir / "mix-home"),
        "MIX_ARCHIVES": str(run_dir / "mix-archives"),
        "HEX_HOME": str(run_dir / "hex"),
        "HEX_OFFLINE": "1",
        "REBAR_CACHE_DIR": str(run_dir / "rebar"),
        "ERL_FLAGS": "+S 4:4 +fnu -home " + str(run_dir / "home"),
        "MIX_BUILD_PATH": str(ROOT / "_build"),
    }
    for key in ("MIX_ARCHIVES", "MIX_REBAR3", "MIX_BUILD_PATH", "MIX_DEPS_PATH"):
        if key in os.environ:
            value = Path(os.environ[key]).expanduser()
            if not value.is_absolute():
                raise ValueError(f"{key} must be an explicit absolute tooling path")
            env[key] = str(value)
    (run_dir / "home").mkdir()
    return env


def command(argv: list[str], log: Path, env: dict[str, str], timeout: int = 180) -> None:
    with log.open("w", encoding="utf-8") as stream:
        process = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except BaseException:
            stop(process)
            log.with_suffix(log.suffix + ".exit").write_text(str(process.returncode) + "\n", encoding="utf-8")
            raise
    log.with_suffix(log.suffix + ".exit").write_text(str(code) + "\n", encoding="utf-8")
    if code != 0:
        raise RuntimeError(f"Command failed (exit {code}); inspect {log}")


def stop(process: subprocess.Popen[Any]) -> bool:
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
            return False
    return process.returncode == 0


def sdk_environment(run_dir: Path, env: dict[str, str], wheelhouse: Path | None) -> Path:
    venv = run_dir / "venv"
    command([sys.executable, "-I", "-m", "venv", str(venv)], run_dir / "venv.log", env)
    python = venv / "bin" / "python"
    wheels = run_dir / "wheels"
    wheels.mkdir()
    source = ["--index-url", "https://pypi.org/simple"]
    if wheelhouse:
        source = ["--no-index", "--find-links", str(wheelhouse.resolve(strict=True))]
    command(
        [str(python), "-I", "-m", "pip", "--isolated", "download", "--no-cache-dir",
         "--only-binary=:all:", *source, "--dest", str(wheels), f"mcp=={SDK_VERSION}"],
        run_dir / "download.log", env,
    )
    for name, expected in ((SDK_WHEEL, SDK_SHA256), (TYPES_WHEEL, TYPES_SHA256)):
        wheel = wheels / name
        if not wheel.is_file() or sha(wheel) != expected:
            raise RuntimeError(f"Official wheel {name} SHA256 differs from its published PyPI digest")
    command(
        [str(python), "-I", "-m", "pip", "--isolated", "install", "--no-cache-dir", "--no-index",
         "--find-links", str(wheels), f"mcp=={SDK_VERSION}"], run_dir / "install.log", env,
    )
    command([str(python), "-I", "-m", "pip", "--isolated", "check"], run_dir / "pip-check.log", env)
    command([str(python), "-I", "-m", "pip", "--isolated", "freeze"], run_dir / "dependencies.txt", env)

    # Verify the installed SDK files against the authenticated wheel, rather than
    # trusting a version string or editable install. Nothing in site-packages is edited.
    purelib = next((venv / "lib").glob("python*/site-packages"))
    files = {}
    for wheel_name, prefix in ((SDK_WHEEL, "mcp/"), (TYPES_WHEEL, "mcp_types/")):
        with zipfile.ZipFile(wheels / wheel_name) as archive:
            for name in archive.namelist():
                if name.startswith(prefix) and not name.endswith("/"):
                    installed = purelib / name
                    digest = hashlib.sha256(archive.read(name)).hexdigest()
                    if not installed.is_file() or sha(installed) != digest:
                        raise RuntimeError(f"Installed SDK differs from official wheel: {name}")
                    files[name] = digest
    dump(run_dir / "sdk-provenance.json", {
        "package": "mcp", "version": SDK_VERSION, "wheel": SDK_WHEEL,
        "wheel_sha256": SDK_SHA256, "installed_files": files,
        "types_wheel": TYPES_WHEEL, "types_wheel_sha256": TYPES_SHA256,
        "source": "https://pypi.org/project/mcp/2.2.0/#files",
        "publishing_repository": "https://github.com/modelcontextprotocol/python-sdk",
        "dependencies": "dependencies.txt", "dependency_versions_are_sdk_resolver_output": True,
    })
    command(
        [str(python), "-I", str(HERE / "peer.py"), "--profile", "stdio",
         "--journal", str(run_dir / "schema-check.jsonl"), "--check"],
        run_dir / "sdk-api-check.log", env,
    )
    return python


def read_journal(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


def wait_ready(process: subprocess.Popen[Any], path: Path) -> dict[str, Any]:
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"SDK HTTP peer exited before readiness (exit {process.returncode})")
        if path.is_file():
            try:
                return json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                pass  # An in-progress readiness write is not a profile fallback.
        time.sleep(0.02)
    raise TimeoutError("SDK HTTP peer readiness deadline")


def manifest() -> dict[str, str]:
    files = list((ROOT / "lib").rglob("*.ex"))
    files += [ROOT / "mix.exs", ROOT / "mix.lock", ROOT / "README.md",
              ROOT / "config" / "test.exs", ROOT / "test" / "test_helper.exs"]
    files += [HERE / "probe.exs", HERE / "peer.py", HERE / "run.py"]
    return {str(path.relative_to(ROOT)): sha(path) for path in sorted(files)}


def response_messages(body: str, content_type: str) -> list[dict[str, Any]]:
    # Audit untouched SDK output using the public JSON/SSE framing. This never
    # participates in serving a peer or in ExAgent's transport implementation.
    if content_type.startswith("application/json"):
        return [json.loads(body)] if body else []
    if content_type.startswith("text/event-stream"):
        messages = []
        for event in body.replace("\r\n", "\n").split("\n\n"):
            data = "\n".join(line[5:].lstrip(" ") for line in event.split("\n") if line.startswith("data:"))
            if data:
                messages.append(json.loads(data))
        return messages
    return []


def assert_profile(profile: dict[str, Any]) -> dict[str, Any]:
    result = json.loads(Path(profile["result"]).read_text(encoding="utf-8"))
    entries = read_journal(Path(profile["journal"]))
    starts = [entry for entry in entries if entry["event"] == "start"]
    if len(starts) != 1 or starts[0]["profile"] != profile["name"] or starts[0]["sdk"] != {"mcp": SDK_VERSION, "mcp-types": SDK_VERSION}:
        raise AssertionError("Peer profile or SDK identity mismatch")
    requests = [entry for entry in entries if entry["event"] == "request"]
    ids = [entry["id"] for entry in requests if entry["id"] is not None]
    if not all(type(value) is int for value in ids) or len(ids) != len(set(ids)):
        raise AssertionError("SDK request IDs must be unique exact integers")
    effects = [entry for entry in entries if entry["event"] == "effect"]
    if sorted(entry["token"] for entry in effects) != ["allowed", "approved"]:
        raise AssertionError("Expected exactly one effect for each allowed/approved token")
    initialize = [entry for entry in requests if entry["method"] == "initialize"]
    if len(initialize) != 1 or initialize[0]["params"]["protocolVersion"] != result["transport_protocol"]:
        raise AssertionError("Requested MCP version differs from selected profile")
    if any(entry["protocol"] != result["transport_protocol"] for entry in requests if entry["method"] in ("tools/list", "tools/call")):
        raise AssertionError("SDK tool context negotiated another MCP revision")
    if profile["name"] == "stdio":
        return {**result, "wire_http_responses": 0}

    sessionful = profile["name"].endswith("-session")
    expected_type = "application/json" if "-json-" in profile["name"] else "text/event-stream"
    responses = [entry for entry in entries if entry["event"] == "http"]
    wire_ids = [json.loads(entry["request_body"])["id"] for entry in responses
                if entry["request_body"] and "id" in json.loads(entry["request_body"])]
    if sorted(wire_ids) != sorted(ids) or len(responses) != len(ids) + 1 + int(sessionful):
        raise AssertionError("SDK HTTP observations must cover every request, initialized and close")
    init_session = None
    terminal_responses = 0
    for entry in responses:
        headers = dict(entry["response_headers"])
        sent_headers = dict(entry["request_headers"])
        body = json.loads(entry["request_body"]) if entry["request_body"] else {}
        method = body.get("method")
        if entry["verb"] == "GET":
            raise AssertionError("Unexpected spontaneous GET/reconnect")
        if method == "initialize":
            init_session = headers.get("mcp-session-id")
            if bool(init_session) != sessionful:
                raise AssertionError("SDK session negotiation differs from selected profile")
        elif entry["verb"] == "POST" or entry["verb"] == "DELETE":
            if sent_headers.get("mcp-protocol-version") != "2025-06-18":
                raise AssertionError("Post-handshake MCP version header missing or changed")
        if method == "notifications/initialized" and (entry["status"] != 202 or entry["response_body"]):
            raise AssertionError("Initialized must have an empty 202 response")
        if "id" in body:
            if entry["status"] != 200 or not headers.get("content-type", "").startswith(expected_type):
                raise AssertionError("SDK JSON/SSE profile response mismatch")
            # A deliberately oversized response may be cancelled before its ASGI
            # event completes. Its Client error/recovery is asserted in probe.exs.
            if body.get("params", {}).get("name") != "large":
                messages = response_messages(entry["response_body"], headers["content-type"])
                terminals = [message for message in messages if "result" in message or "error" in message]
                if len(terminals) != 1 or type(terminals[0].get("id")) is not int or terminals[0]["id"] != body["id"]:
                    raise AssertionError("SDK terminal response ID differs from its request")
                if method == "initialize" and terminals[0]["result"]["protocolVersion"] != "2025-06-18":
                    raise AssertionError("SDK negotiated another MCP version")
                terminal_responses += 1
    if sessionful:
        if not init_session:
            raise AssertionError("No negotiated HTTP session")
        subsequent = [entry for entry in responses if json.loads(entry["request_body"] or "{}").get("method") != "initialize"]
        if any(dict(entry["request_headers"]).get("mcp-session-id") != init_session for entry in subsequent):
            raise AssertionError("HTTP session was not stable across calls and DELETE")
    elif any("mcp-session-id" in dict(entry["request_headers"]) for entry in responses):
        raise AssertionError("Stateless profile sent a session")
    deletes = [entry for entry in responses if entry["verb"] == "DELETE"]
    if len(deletes) != int(sessionful) or any(entry["status"] != 200 for entry in deletes):
        raise AssertionError("Sessionful close must perform one successful SDK DELETE")
    return {**result, "wire_http_responses": terminal_responses, "sdk_delete": sessionful}


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", action="append", choices=(*PROFILES, "all"), help="Explicit opt-in; repeat for selected profiles")
    parser.add_argument("--list", action="store_true", help="List profiles without subprocesses, writes or network")
    parser.add_argument("--prepare-only", action="store_true", help="Install/check SDK privately; does not run interop or Mix")
    parser.add_argument("--wheelhouse", type=Path, help="Local complete wheelhouse; prohibits network during SDK setup")
    parser.add_argument("--artifacts-parent", type=Path, help="Existing directory for a fresh run; default is the OS temp directory")
    parser.add_argument("--timeout", type=int, default=180, help="Mix runtime deadline in seconds (default: 180)")
    args = parser.parse_args()
    if args.list:
        print("\n".join(PROFILES))
        return 0
    if not args.profile:
        parser.print_help()
        print("No profile selected; no Mix, SDK installation or network executed.")
        return 2
    if os.name != "posix":
        parser.error("This runner requires POSIX process groups and Elixir stdio Ports")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    # Give TERM the same owned-child cleanup as Ctrl-C. The default action would
    # abandon peer process groups. SIGKILL cannot promise launcher cleanup.
    def interrupted(_signum: int, _frame: Any) -> None:
        raise KeyboardInterrupt("Runner terminated")

    signal.signal(signal.SIGTERM, interrupted)
    selected = list(PROFILES) if "all" in args.profile else list(dict.fromkeys(args.profile))
    run_dir = Path(tempfile.mkdtemp(prefix="exagent-mcp-sdk-", dir=args.artifacts_parent))
    print(f"MCP SDK artifacts: {run_dir}", flush=True)
    peers: list[tuple[subprocess.Popen[Any], dict[str, Any], Any]] = []
    report: dict[str, Any] = {"sdk": SDK_VERSION, "selected_profiles": selected, "interop_attempted": False,
                              "interop_executed": False, "passed": False}
    code = 1
    try:
        env = clean_environment(run_dir)
        python = sdk_environment(run_dir, env, args.wheelhouse)
        if args.prepare_only:
            report["prepared"] = True
            print("SDK provenance/API/schema preparation passed; interop not executed.", flush=True)
            code = 0
        else:
            mix = shutil.which("mix", path=env["PATH"])
            if mix is None:
                raise RuntimeError("mix is not available on the explicitly inherited runtime PATH")
            if not Path(env["MIX_ARCHIVES"]).is_dir():
                raise RuntimeError("Supply an existing isolated MIX_ARCHIVES; see docs/development/environment.md")
            profiles = []
            for name in selected:
                directory = run_dir / name
                directory.mkdir()
                profile = {"name": name, "journal": str(directory / "peer.jsonl"), "result": str(directory / "result.json")}
                if name != "stdio":
                    ready = directory / "ready.json"
                    stream = (directory / "peer.log").open("w", encoding="utf-8")
                    peer = subprocess.Popen(
                        [str(python), "-I", str(HERE / "peer.py"), "--profile", name,
                         "--journal", profile["journal"], "--ready", str(ready)],
                        cwd=run_dir, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True,
                    )
                    peers.append((peer, profile, stream))
                    endpoint = wait_ready(peer, ready)
                    profile.update(endpoint)
                profiles.append(profile)
            config = run_dir / "run.json"
            dump(config, {"run_dir": str(run_dir), "python": str(python), "peer": str(HERE / "peer.py"), "profiles": profiles})
            sources = manifest()
            dump(run_dir / "sources-before.json", sources)
            report["interop_attempted"] = True
            command(
                [mix, "test", str((HERE / "probe.exs").relative_to(ROOT)), "--seed", "0", "--warnings-as-errors"],
                run_dir / "mix.log", {**env, "EXAGENT_MCP_SDK_CONFIG": str(config)}, timeout=args.timeout,
            )
            after = manifest()
            dump(run_dir / "sources-after.json", after)
            if after != sources:
                raise AssertionError("Runtime/harness sources changed during the run; evidence identity is invalid")
            # Flush final ASGI observations before auditing; cleanup health is
            # still checked in finally and can turn an otherwise passing run red.
            for peer, _profile, _stream in peers:
                stop(peer)
            report["profiles"] = [assert_profile(profile) for profile in profiles]
            code = 0
    except BaseException as error:
        report["error"] = f"{type(error).__name__}: {error}"
        print(report["error"], file=sys.stderr, flush=True)
    finally:
        cleanup = []
        for peer, profile, stream in reversed(peers):
            healthy = stop(peer)
            stream.close()
            ready = json.loads((Path(profile["journal"]).parent / "ready.json").read_text()) if "url" in profile else None
            listener_closed = True
            if ready:
                port = int(ready["url"].split(":")[2].split("/")[0])
                with socket.socket() as probe:
                    probe.settimeout(0.5)
                    listener_closed = probe.connect_ex(("127.0.0.1", port)) != 0
            cleanup.append({"profile": profile["name"], "pid": peer.pid, "exit": peer.returncode,
                            "clean_exit": healthy, "listener_closed": listener_closed})
            if not healthy or not listener_closed:
                code = 1
        stdio_journal = run_dir / "stdio" / "peer.jsonl"
        if stdio_journal.is_file():
            start = next((entry for entry in read_journal(stdio_journal) if entry["event"] == "start"), None)
            if start:
                deadline = time.monotonic() + 5
                while alive(start["pid"]) and time.monotonic() < deadline:
                    time.sleep(0.02)
                gone = not alive(start["pid"])
                cleanup.append({"profile": "stdio", "pid": start["pid"], "process_closed": gone})
                if not gone:
                    os.kill(start["pid"], signal.SIGKILL)
                    code = 1
        report["cleanup"] = cleanup
        executed = []
        for name in selected:
            journal = run_dir / name / "peer.jsonl"
            if journal.is_file():
                try:
                    if any(entry["event"] == "request" and entry["method"] == "initialize"
                           for entry in read_journal(journal)):
                        executed.append(name)
                except (json.JSONDecodeError, UnicodeDecodeError) as error:
                    report["journal_error"] = f"{name}: {type(error).__name__}"
                    code = 1
        report["executed_profiles"] = executed
        report["interop_executed"] = bool(executed)
        report["passed"] = code == 0 and report["interop_executed"]
        report["exit"] = code
        dump(run_dir / "report.json", report)
    if report["passed"]:
        print(f"MCP SDK INTEROP PASS {len(selected)}/{len(selected)} profiles; cleanup verified. Report: {run_dir / 'report.json'}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
