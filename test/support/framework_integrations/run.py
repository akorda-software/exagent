#!/usr/bin/env python3
"""Opt-in real Phoenix/LiveView and Oban/PostgreSQL consumer qualification."""
from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PROFILES = ("liveview", "oban-postgres", "all")
VERSIONS = {"phoenix": "1.8.15", "phoenix_live_view": "1.2.12", "phoenix_pubsub": "2.3.0", "oban": "2.24.1"}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path: Path, data) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def copy_physical(source: Path, destination: Path) -> None:
    if source.is_symlink():
        raise ValueError("symbolic link is not a physical qualification input: " + str(source))
    if source.is_dir():
        destination.mkdir(parents=True, exist_ok=True)
        for child in sorted(source.iterdir()):
            if child.name in {".git", "_build", ".elixir_ls", ".ruff_cache", "__pycache__"} or child.name.startswith(".env"):
                continue
            copy_physical(child, destination / child.name)
    elif source.is_file():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def manifest(project: Path, directories=("lib", "config", "recipes", "test")) -> dict[str, str]:
    paths = [project / "mix.exs", project / "mix.lock", project / "README.md", project / "crash_probe.exs"]
    for directory in directories:
        paths += sorted((project / directory).rglob("*")) if (project / directory).is_dir() else []
    return {str(path.relative_to(project)): digest(path) for path in paths if path.is_file() and not path.is_symlink() and not path.name.startswith(".env")}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--base-project", type=Path, help="read-only physical ExAgent freeze, never the shared checkout")
    parser.add_argument("--pg-bin", type=Path, help="native PostgreSQL bin directory")
    parser.add_argument("--artifacts-parent", type=Path, default=Path(tempfile.gettempdir()))
    args = parser.parse_args()
    if args.list or not args.profile:
        print("\n".join(PROFILES))
        return 0
    if not args.base_project or not args.pg_bin:
        parser.error("explicit --base-project and --pg-bin are required")
    base = args.base_project.resolve(strict=True)
    if base == ROOT or ROOT in base.parents or base in ROOT.parents:
        parser.error("base must be an independent physical freeze outside the shared checkout")
    pg_bin = args.pg_bin.resolve(strict=True)
    for executable in ("postgres", "initdb", "pg_ctl", "createdb", "psql"):
        if not (pg_bin / executable).is_file():
            parser.error("missing native executable " + executable)
    archive_input = Path(os.environ.get("MIX_ARCHIVES", "/nonexistent"))
    rebar_input = Path(os.environ.get("MIX_REBAR3", "/nonexistent"))
    if not archive_input.is_absolute() or not archive_input.is_dir() or not rebar_input.is_absolute() or not rebar_input.is_file():
        parser.error("supply existing isolated absolute MIX_ARCHIVES and MIX_REBAR3 tooling paths")
    parent = args.artifacts_parent.resolve(strict=True)
    work = Path(tempfile.mkdtemp(prefix="framework12-", dir=parent))
    work.chmod(0o700)
    core, consumer, tooling = work / "core", work / "consumer", work / "tooling"
    socket_dir, data = work / "socket", work / "postgres"
    socket_dir.mkdir(mode=0o700)
    if len(str(socket_dir).encode()) > 90:
        parser.error("artifacts parent makes the private Unix socket path too long")
    report = {"passed": False, "interop_executed": False, "profile": args.profile,
              "artifacts": str(work), "base_project": str(base), "commands": [],
              "required_versions": VERSIONS, "cleanup": False,
              "driver_sha256": digest(Path(__file__)),
              "limits": {"network": "official Hex packages and their maintained native build artifacts during preparation; no model providers",
                         "dependency_seconds": 300, "compile_seconds": 600, "case_seconds": 90,
                         "sql_statement_timeout_ms": 5000, "repo_pool_size": 4,
                         "transport": "private mode-0700 Unix socket; TCP disabled"}}
    base_before = manifest(base, ("lib", "config", "examples"))
    dump(work / "base-source.json", base_before)
    report["base_source_sha256"] = digest(work / "base-source.json")
    for name in ("mix.exs", "mix.lock", "README.md", "LICENSE", ".formatter.exs", "lib", "config", "deps", "docs", "examples"):
        copy_physical(base / name, core / name)
    copy_physical(ROOT / "test/fixtures/framework_integrations", consumer)
    copy_physical(ROOT / "examples/continuation_integrations", consumer / "recipes")
    copy_physical(base / "deps", consumer / "deps")
    copy_physical(base / "mix.lock", consumer / "mix.lock")
    # The extraction is this objective's only edit of the accepted generic demo.
    copy_physical(ROOT / "examples/continuation_job.exs", core / "examples/continuation_job.exs")
    copy_physical(ROOT / "examples/continuation_integrations/job_dispatch.ex", core / "examples/continuation_integrations/job_dispatch.ex")
    copy_physical(archive_input, tooling / "archives")
    copy_physical(rebar_input, tooling / "rebar3")
    for directory in ("home", "mix", "hex", "rebar", "xdg", "erlang"):
        (tooling / directory).mkdir(parents=True, exist_ok=True)
    before = manifest(consumer)
    dump(work / "consumer-source-before.json", before)
    report["consumer_input_sha256"] = digest(work / "consumer-source-before.json")
    report["core_lock_sha256"] = digest(core / "mix.lock")
    env = {key: os.environ[key] for key in ("PATH", "LANG", "LC_ALL") if key in os.environ}
    env.update({"MIX_HOME": str(tooling / "mix"),
                "MIX_ARCHIVES": str(tooling / "archives"), "MIX_REBAR3": str(tooling / "rebar3"),
                "HEX_HOME": str(tooling / "hex"), "REBAR_CACHE_DIR": str(tooling / "rebar"),
                "XDG_CONFIG_HOME": str(tooling / "xdg"), "XDG_CACHE_HOME": str(tooling / "xdg"),
                "ERL_FLAGS": "+S 4:4 +fnu -home " + str(tooling / "home"),
                "EXAGENT_OFFLINE": "1", "MIX_ENV": "test", "MIX_BUILD_PATH": str(work / "build"),
                "MIX_DEPS_PATH": str(consumer / "deps"), "EXAGENT_FRAMEWORK_CORE": str(core),
                "EXAGENT_FRAMEWORK_EXECUTE": "1", "EXAGENT_FRAMEWORK_SOCKET": str(socket_dir),
                "EXAGENT_FRAMEWORK_USER": getpass.getuser(), "EXAGENT_FRAMEWORK_ARTIFACTS": str(work)})
    ca_file = Path("/etc/ssl/certs/ca-certificates.crt")
    if ca_file.is_file():
        env["HEX_CACERTS_PATH"] = str(ca_file)
    pg_env = {key: env[key] for key in ("PATH", "LANG", "LC_ALL") if key in env}
    pg_env.update({"PGHOST": str(socket_dir), "PGPORT": "5432", "PGUSER": getpass.getuser()})
    processes = set()
    server_pid = None

    def command(label, argv, child_env=env, cwd=consumer, timeout=90, expected=0):
        log = work / (label + ".log")
        with log.open("wb") as output:
            process = subprocess.Popen([str(arg) for arg in argv], cwd=cwd, env=child_env,
                                       stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            processes.add(process)
            started = time.monotonic()
            try:
                status = process.wait(timeout=timeout)
            except BaseException:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)
                raise
            finally:
                processes.discard(process)
        log.with_suffix(".exit").write_text(str(status) + "\n")
        report["commands"].append({"label": label, "argv": [str(arg) for arg in argv],
                                   "cwd": str(cwd), "exit": status, "expected": expected,
                                   "pid": process.pid, "process_exited": process.poll() is not None,
                                   "seconds": round(time.monotonic() - started, 3),
                                   "log": str(log), "log_sha256": digest(log)})
        dump(work / "report.json", report)
        print(label + " exit " + str(status), flush=True)
        if status != expected:
            raise RuntimeError(label + " failed; inspect " + str(log))

    try:
        command("versions", ["mix", "--version"])
        command("postgres-version", [pg_bin / "postgres", "--version"], pg_env)
        command("dependencies", ["mix", "deps.get"], timeout=300)
        report["consumer_lock_sha256"] = digest(consumer / "mix.lock")
        command("compile", ["mix", "compile", "--warnings-as-errors"], timeout=600)
        # Separate no-framework project/build proves the accepted demo extraction.
        demo_env = {**env, "MIX_BUILD_PATH": str(work / "demo-build"),
                    "MIX_DEPS_PATH": str(core / "deps"), "MIX_ENV": "prod", "HEX_OFFLINE": "1"}
        command("extracted-demo", ["mix", "run", "--no-start", "-e",
            'Application.put_env(:req_llm, :load_dotenv, false); {:ok, _} = Application.ensure_all_started(:exagent); Code.require_file("examples/continuation_job.exs")'],
            demo_env, cwd=core, timeout=600)
        command("initdb", [pg_bin / "initdb", "-D", data, "--no-locale", "--encoding=UTF8", "--auth=trust"], pg_env)
        options = shlex.join(["-c", "listen_addresses=", "-c", "unix_socket_permissions=0700",
                             "-c", "statement_timeout=5000", "-k", str(socket_dir), "-p", "5432"])
        command("postgres-start", [pg_bin / "pg_ctl", "-D", data, "-l", work / "postgres.log", "-o", options, "-w", "start"], pg_env, timeout=30)
        server_pid = int((data / "postmaster.pid").read_text().splitlines()[0])
        report["postgres_pid"] = server_pid
        command("createdb", [pg_bin / "createdb", "--maintenance-db=template1", "framework_integrations"], pg_env)
        command("postgres-settings", [pg_bin / "psql", "--dbname=framework_integrations", "--no-psqlrc", "-Atc",
                "SELECT current_database(), current_setting('server_version'), current_setting('listen_addresses'), current_setting('unix_socket_permissions')"], pg_env)
        argv = ["mix", "test", "test/cases.exs", "--seed", "0", "--warnings-as-errors"]
        if args.profile != "all":
            argv += ["--only", "liveview" if args.profile == "liveview" else "oban"]
        report["case_command_started"] = True
        command("cases", argv)
        if args.profile in ("oban-postgres", "all"):
            command("oban-crash", ["mix", "run", "crash_probe.exs", "crash"], expected=73)
            time.sleep(1.2)  # Declared 1-second claim expires; never an unbounded wait.
            command("oban-recover", ["mix", "run", "crash_probe.exs", "recover"])
        versions = json.loads((work / "versions.json").read_text())
        report["effective_versions"] = versions
        if any(versions.get(key) != value for key, value in VERSIONS.items()):
            raise RuntimeError("effective framework version differs from pinned profile")
        expected = []
        if args.profile in ("liveview", "all"):
            expected += ["live-authorized", "live-authority", "live-reconnect", "live-revoked"]
        if args.profile in ("oban-postgres", "all"):
            expected += ["oban-delivery", "oban-authority", "oban-uncertainty"]
        report["outputs"] = {label: json.loads((work / (label + ".json")).read_text()) for label in expected}
        after = manifest(consumer)
        dump(work / "consumer-source-after.json", after)
        report["consumer_source_stable"] = {k:v for k,v in before.items() if k != "mix.lock"} == {k:v for k,v in after.items() if k != "mix.lock"}
        report["base_source_stable"] = manifest(base, ("lib", "config", "examples")) == base_before
        report["passed"] = report["consumer_source_stable"] and report["base_source_stable"]
    except Exception as error:
        report["error"] = type(error).__name__ + ": " + str(error)
    finally:
        report["interop_executed"] = (work / "versions.json").exists()
        for process in processes:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)
        if (data / "postmaster.pid").exists():
            try:
                command("postgres-stop", [pg_bin / "pg_ctl", "-D", data, "-m", "fast", "-w", "stop"], pg_env, timeout=20)
            except Exception as error:
                report["cleanup_error"] = str(error)
        pid_alive = False
        if server_pid:
            try:
                os.kill(server_pid, 0)
                pid_alive = True
            except ProcessLookupError:
                pass
        report["cleanup_details"] = {"postgres_pid_alive": pid_alive,
                                     "postmaster_pid_file": (data / "postmaster.pid").exists(),
                                     "unix_socket_exists": (socket_dir / ".s.PGSQL.5432").exists(),
                                     "active_launcher_children": len(processes)}
        report["cleanup"] = not any(report["cleanup_details"].values())
        report["passed"] = report["passed"] and report["cleanup"]
        dump(work / "report.json", report)
        print(json.dumps({"passed": report["passed"], "interop_executed": report["interop_executed"],
                          "cleanup": report["cleanup"], "report": str(work / "report.json")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
