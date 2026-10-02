#!/usr/bin/env python3
"""Opt-in qualification in a new, runner-owned native PostgreSQL cluster."""
import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


RESUMER_PHASES = ("two-resumers-seed", "two-resumers-a", "two-resumers-b", "two-resumers-verify")
FLOW_PHASES = ("flow-a8-pause", "flow-a8-resume")
PHASES = ("primitives", "lost-ack-network") + RESUMER_PHASES + FLOW_PHASES + ("pause", "resume", "crash", "recover", "inventory", "restored")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_manifest(project):
    paths = [project / "mix.exs", project / "mix.lock"]
    paths += sorted((project / "lib").rglob("*.ex"))
    paths += sorted((project / "config").rglob("*.exs"))
    for path in paths:
        if path.is_symlink():
            raise RuntimeError("source symlink is not an isolated qualification input")
    return {str(path.relative_to(project)): digest(path) for path in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--list", action="store_true")
    focused = parser.add_mutually_exclusive_group()
    focused.add_argument("--network-ack-only", action="store_true",
                         help="qualify the new network fault with its primitive bootstrap only")
    focused.add_argument("--resumers-only", action="store_true",
                         help="qualify two actual resumers in separate VMs after bootstrap")
    focused.add_argument("--flow-only", action="store_true",
                         help="qualify SQL Flow11 collect/delegation/approval in fresh VMs")
    parser.add_argument("--project", type=Path, help="independently owned physical checkout/consumer")
    parser.add_argument("--pg-bin", type=Path, help="native PostgreSQL bin directory")
    parser.add_argument("--artifacts-parent", type=Path, default=Path(tempfile.gettempdir()))
    args = parser.parse_args()
    if args.list:
        print("\n".join(PHASES))
        return 0
    if not args.execute or not args.project or not args.pg_bin:
        parser.error("--execute, --project and --pg-bin are required; no default service is used")

    project = args.project.resolve(strict=True)
    if project == Path(__file__).resolve().parents[3]:
        parser.error("use a physical isolated project, never the shared checkout/build")
    pg_bin = args.pg_bin.resolve(strict=True)
    for executable in ("postgres", "initdb", "pg_ctl", "createdb", "pg_dump", "pg_restore", "psql"):
        if not (pg_bin / executable).is_file():
            parser.error("missing PostgreSQL executable " + executable)
    probe = project / "test/support/postgres_acceptance/probe.exs"
    proxy = project / "test/support/postgres_acceptance/ack_loss_proxy.py"
    if not probe.is_file() or not proxy.is_file():
        parser.error("project does not contain the qualification probe and owned fault proxy")
    flow_fixtures = [project / "test/support" / name for name in
                     ("delegation_runtime_fixture.ex", "flow_runtime_fixture.ex")]
    needs_flow = not (args.network_ack_only or args.resumers_only)
    if needs_flow and not all(path.is_file() and not path.is_symlink() for path in flow_fixtures):
        parser.error("Flow profile requires exact physical host fixture sources")
    for directory in (project / "lib", project / "deps", project / "config"):
        if not directory.is_dir() or directory.is_symlink():
            parser.error("project sources and dependencies must be physical directories")
    if not os.environ.get("MIX_ARCHIVES") or not os.environ.get("MIX_REBAR3"):
        parser.error("provide existing isolated MIX_ARCHIVES and MIX_REBAR3; no global bootstrap")
    archives_source = Path(os.environ["MIX_ARCHIVES"])
    rebar_source = Path(os.environ["MIX_REBAR3"])
    if not archives_source.is_dir() or not rebar_source.is_file():
        parser.error("isolated MIX_ARCHIVES and MIX_REBAR3 must exist")
    if any(path.is_symlink() for path in archives_source.rglob("*")):
        parser.error("isolated archive source cannot contain symlinks")
    work = Path(tempfile.mkdtemp(prefix="exagent-pg-", dir=args.artifacts_parent))
    work.chmod(0o700)
    socket_dir = work / "socket"
    socket_dir.mkdir(mode=0o700)
    if len(str(socket_dir).encode()) > 90:
        parser.error("artifact parent makes the Unix socket path too long")
    data = work / "data"
    username = getpass.getuser()
    source_before = source_manifest(project)
    source_file = work / "source-manifest.json"
    source_file.write_text(json.dumps(source_before, indent=2) + "\n")
    report = {"passed": False, "project": str(project), "artifacts": str(work),
              "probe_sha256": digest(probe), "commands": [], "phases": {}, "cleanup": False,
              "proxy_sha256": digest(proxy),
              "selected_phases": list(PHASES[:2] if args.network_ack_only else
                                      ("primitives",) + RESUMER_PHASES if args.resumers_only else
                                      ("primitives",) + FLOW_PHASES if args.flow_only else PHASES),
              "flow_fixture_hashes": {str(path.relative_to(project)): digest(path)
                                      for path in flow_fixtures} if needs_flow else {},
              "driver_sha256": digest(Path(__file__)), "source_manifest_sha256": digest(source_file),
              "source_files": len(source_before), "mix_lock_sha256": digest(project / "mix.lock"),
              "transport": "private Unix socket; TCP disabled", "database": "qualification",
              "limits": {"vm_timeout_seconds": 45, "build_timeout_seconds": 300,
                         "sql_statement_timeout_ms": 5000,
                         "repo_pool_size": 4, "concurrent_cas": 2, "vm_schedulers": 4}}
    tooling = work / "tooling"
    tooling.mkdir()
    shutil.copytree(archives_source, tooling / "archives")
    shutil.copy2(rebar_source, tooling / "rebar3")
    for name in ("mix", "hex", "rebar", "xdg", "erlang"):
        (tooling / name).mkdir()
    # Inherited build/project selectors cannot redirect writes to the shared host.
    allowed = ("PATH", "LANG", "LC_ALL")
    env = {key: os.environ[key] for key in allowed if key in os.environ}
    env.update({"EXAGENT_OFFLINE": "1", "MIX_ENV": "test", "HEX_OFFLINE": "1",
                "ERL_FLAGS": "+S 4:4 +fnu -home " + str(tooling / "erlang"),
                "EXAGENT_SQL_QUALIFICATION": "1",
                "EXAGENT_QUALIFICATION_SOCKET": str(socket_dir),
                "EXAGENT_QUALIFICATION_DATABASE": "qualification",
                "EXAGENT_QUALIFICATION_USER": username,
                "MIX_HOME": str(tooling / "mix"), "MIX_ARCHIVES": str(tooling / "archives"),
                "HEX_HOME": str(tooling / "hex"), "REBAR_CACHE_DIR": str(tooling / "rebar"),
                "MIX_REBAR3": str(tooling / "rebar3"), "MIX_DEPS_PATH": str(project / "deps"),
                "MIX_BUILD_PATH": str(work / "build"), "XDG_CONFIG_HOME": str(tooling / "xdg"),
                "XDG_CACHE_HOME": str(tooling / "xdg")})
    pg_env = {key: value for key, value in env.items() if key in ("PATH", "LANG", "LC_ALL")}
    pg_env.update({"PGHOST": str(socket_dir), "PGPORT": "5432", "PGUSER": username})
    processes = set()
    owned_children = []

    def command(label, argv, child_env=env, expected=0, timeout=45):
        log = work / (label + ".log")
        started = time.monotonic()
        with log.open("wb") as output:
            process = subprocess.Popen([str(arg) for arg in argv], cwd=project, env=child_env,
                                       stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            processes.add(process)
            owned_children.append(process)
            try:
                status = process.wait(timeout=timeout)
            except BaseException as error:
                # An interrupted wait must retain ownership until the child is
                # killed and reaped, just like a declared deadline expiry.
                if process.returncode is None:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=3)
                report["commands"].append({"label": label, "argv": [str(arg) for arg in argv],
                                           "exit": process.returncode, "expected_exit": expected,
                                           "seconds": time.monotonic() - started,
                                           "timeout_seconds": timeout, "interrupted_by": type(error).__name__,
                                           "child_closed": process.returncode is not None,
                                           "log_sha256": digest(log)})
                if isinstance(error, subprocess.TimeoutExpired):
                    raise RuntimeError(label + " exceeded its declared deadline") from None
                raise
            finally:
                if process.returncode is not None:
                    processes.discard(process)
        report["commands"].append({"label": label, "argv": [str(arg) for arg in argv],
                                   "exit": status, "expected_exit": expected,
                                   "seconds": time.monotonic() - started, "timeout_seconds": timeout,
                                   "child_closed": process.returncode is not None,
                                   "log_sha256": digest(log)})
        (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        if status != expected:
            raise RuntimeError(f"{label}: expected exit {expected}, got {status}; see {log}")

    def phase(name, database="qualification", expected=0, extra_env=None):
        phase_env = dict(env, EXAGENT_QUALIFICATION_DATABASE=database)
        phase_env.update(extra_env or {})
        command(name, ["mix", "run", "--no-compile", "--no-start", str(probe), name, str(work)], phase_env, expected)
        if expected == 0:
            receipt = json.loads((work / (name + ".json")).read_text())
            if not receipt["passed"] or receipt["phase"] != name or not receipt["observations"]:
                raise RuntimeError("invalid phase receipt " + name)
            report["phases"][name] = receipt
        else:
            report["phases"][name] = {"confirmed_vm_exit": expected}

    def network_fault():
        log = work / "ack-proxy.log"
        with log.open("wb") as output:
            process = subprocess.Popen(
                [sys.executable, str(proxy), "--socket", str(socket_dir),
                 "--artifacts", str(work)], cwd=project, env=env,
                stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            processes.add(process)
            owned_children.append(process)
            try:
                port_file = work / "ack-proxy-port.txt"
                deadline = time.monotonic() + 3
                while not port_file.exists():
                    if process.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("owned ACK proxy did not become ready")
                    time.sleep(0.02)
                port = int(port_file.read_text())
                if not 1 <= port <= 65535:
                    raise RuntimeError("invalid proxy port")
                phase("lost-ack-network", extra_env={"EXAGENT_NETWORK_ACK_PROXY_PORT": str(port)})
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=3)
                processes.discard(process)
                report["proxy_exit"] = process.returncode
                receipt_file = work / "ack-proxy.json"
                if receipt_file.exists():
                    report["proxy"] = json.loads(receipt_file.read_text())
        if (process.returncode != 0 or not report.get("proxy", {}).get("closed")
                or report.get("proxy", {}).get("errors")):
            raise RuntimeError("owned ACK proxy did not close cleanly")

    def resumer_race():
        command("createdb-resumers", [pg_bin / "createdb", "qualification_resumers"], pg_env)
        phase("two-resumers-seed", "qualification_resumers")
        running = []
        try:
            for name in RESUMER_PHASES[1:3]:
                child_env = dict(env, EXAGENT_QUALIFICATION_DATABASE="qualification_resumers")
                log = work / (name + ".log")
                output = log.open("wb")
                # Bootstrap/seed compiled this frozen, owned build. The two
                # concurrent VMs now read it without racing Mix compilers.
                argv = ["mix", "run", "--no-compile", "--no-start", str(probe), name, str(work)]
                process = subprocess.Popen(argv, cwd=project, env=child_env, stdout=output,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                processes.add(process)
                owned_children.append(process)
                running.append((name, process, output, log, argv, time.monotonic()))
            ready_until = time.monotonic() + 4
            while not all((work / (name + "-ready")).exists() for name, *_ in running):
                if any(process.poll() is not None for _, process, *_ in running) or time.monotonic() >= ready_until:
                    raise RuntimeError("separate resumers failed their ready barrier")
                time.sleep(0.01)
            (work / "two-resumers-go").write_text("start\n")
            for name, process, output, log, argv, started in running:
                status = process.wait(timeout=10)
                output.close()
                processes.discard(process)
                report["commands"].append({"label": name, "argv": argv, "exit": status,
                                           "expected_exit": 0, "seconds": time.monotonic() - started,
                                           "log_sha256": digest(log)})
                if status != 0:
                    raise RuntimeError(f"{name}: exit {status}; see {log}")
                receipt = json.loads((work / (name + ".json")).read_text())
                if not receipt["passed"] or receipt["phase"] != name or not receipt["observations"]:
                    raise RuntimeError("invalid resumer receipt " + name)
                report["phases"][name] = receipt
        finally:
            for name, process, output, log, argv, started in running:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=3)
                processes.discard(process)
                output.close()
                if not any(entry["label"] == name for entry in report["commands"]):
                    report["commands"].append({"label": name, "argv": argv,
                                               "exit": process.returncode, "expected_exit": 0,
                                               "seconds": time.monotonic() - started,
                                               "log_sha256": digest(log)})
        phase("two-resumers-verify", "qualification_resumers")

    def flow_continuation():
        command("createdb-flow", [pg_bin / "createdb", "qualification_flow"], pg_env)
        phase("flow-a8-pause", "qualification_flow")
        command("restart-flow", [pg_bin / "pg_ctl", "-D", data, "-m", "fast", "-w", "restart"], pg_env)
        phase("flow-a8-resume", "qualification_flow")

    cluster_started = False
    try:
        # A fresh owned build is prepared once, before any cluster or phase IO.
        # Compilation has its own finite budget; the45s VM oracles stay intact.
        command("bootstrap-compile", ["mix", "compile", "--warnings-as-errors"], timeout=300)
        command("postgres-version", [pg_bin / "postgres", "--version"], pg_env)
        command("initdb", [pg_bin / "initdb", "-D", data, "--no-locale", "--encoding=UTF8", "--auth=trust"], pg_env)
        # These settings affect only this newly created private data directory.
        with (data / "postgresql.conf").open("a") as config:
            config.write("\nlisten_addresses = ''\nunix_socket_permissions = 0700\nstatement_timeout = '5s'\n")
        command("start", [pg_bin / "pg_ctl", "-D", data, "-l", work / "postgres.log", "-o", "-k " + str(socket_dir), "-w", "start"], pg_env)
        cluster_started = True
        command("createdb", [pg_bin / "createdb", "qualification"], pg_env)
        command("statement-timeout", [pg_bin / "psql", "-X", "-At", "-d", "qualification",
                                      "-c", "SHOW statement_timeout"], pg_env)
        observed_timeout = (work / "statement-timeout.log").read_text().strip()
        if observed_timeout != "5s":
            raise RuntimeError("private cluster statement_timeout differs from its declared5s")
        report["sql_statement_timeout_observed"] = observed_timeout
        phase("primitives")
        if not args.resumers_only and not args.flow_only:
            network_fault()
        if not args.network_ack_only and not args.flow_only:
            resumer_race()
        if needs_flow:
            flow_continuation()
        if not args.network_ack_only and not args.resumers_only and not args.flow_only:
            phase("pause")
            command("restart", [pg_bin / "pg_ctl", "-D", data, "-m", "fast", "-w", "restart"], pg_env)
            phase("resume")
            phase("crash", expected=73)
            time.sleep(1.2)
            phase("recover")
            phase("inventory")
            backup = work / "synthetic.dump"
            command("backup", [pg_bin / "pg_dump", "-Fc", "-d", "qualification", "-f", backup], pg_env)
            command("createdb-restored", [pg_bin / "createdb", "qualification_restored"], pg_env)
            command("restore", [pg_bin / "pg_restore", "--exit-on-error", "-d", "qualification_restored", backup], pg_env)
            phase("restored", "qualification_restored")
            report["backup_sha256"] = digest(backup)
        if (digest(probe) != report["probe_sha256"] or digest(proxy) != report["proxy_sha256"]
                or source_manifest(project) != source_before
                or any(digest(project / name) != expected for name, expected in report["flow_fixture_hashes"].items())):
            raise RuntimeError("source or probe changed during qualification")
        report["passed"] = True
    except BaseException as error:
        report["error"] = str(error)
        report["passed"] = False
    finally:
        for process in list(processes):
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=3)
        if cluster_started or (data / "postmaster.pid").exists():
            try:
                command("stop", [pg_bin / "pg_ctl", "-D", data, "-m", "immediate", "-w", "stop"], pg_env)
                report["cleanup"] = not (data / "postmaster.pid").exists()
            except BaseException as error:
                report["cleanup_error"] = str(error)
                report["passed"] = False
        report["owned_child_processes"] = [
            {"pid": process.pid, "exit": process.returncode, "closed": process.returncode is not None}
            for process in owned_children]
        report["owned_child_processes_closed"] = all(child["closed"] for child in report["owned_child_processes"])
        report["cleanup"] = report["cleanup"] and report["owned_child_processes_closed"]
        if not report["cleanup"]:
            report["passed"] = False
        (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"passed": report["passed"], "cleanup": report["cleanup"],
                          "report": str(work / "report.json")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
