#!/usr/bin/env python3
"""Opt-in OTLP transport probe; all compilation belongs to a private consumer."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


OFFICIAL_REPOSITORY = "https://github.com/open-telemetry/opentelemetry-erlang.git"
OFFICIAL_REVISION = "9cb8b3627cf68aeb0df7b3243378f0c2520cff66"
LOCAL_DEPENDENCIES = (
    "opentelemetry_api", "opentelemetry", "grpcbox", "ctx", "acceptor_pool",
    "chatterbox", "hpack", "gproc", "tls_certificate_check", "ssl_verify_fun", "telemetry",
)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, cwd, env, artifact, timeout=180):
    with artifact.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            exit_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # This group was created above and contains only this owned command.
            # It also closes a stuck private BEAM/Rebar child, never a host VM.
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise SystemExit(f"Command exceeded {timeout}s; owned process group closed: {artifact}")
    receipt = artifact.parent / "commands.jsonl"
    with receipt.open("a", encoding="utf-8") as log:
        log.write(json.dumps({"command": command, "cwd": str(cwd),
                              "exit": exit_code, "log": str(artifact)}) + "\n")
    if exit_code:
        print(artifact.read_text(encoding="utf-8"))
        raise SystemExit(f"Command failed ({exit_code}); see {artifact}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="enable private build and loopback IO")
    parser.add_argument("--work", type=Path, help="new or existing parent for a fresh consumer")
    parser.add_argument("--official-checkout", type=Path,
                        help="existing untouched official checkout at the pinned revision")
    parser.add_argument("--hex-archive", type=Path,
                        help="official Hex archive directory to copy into the private home")
    parser.add_argument("--elixir-bin", type=Path, help="directory containing mix/elixir")
    parser.add_argument("--erlang-bin", type=Path, help="directory containing erl")
    parser.add_argument("--rebar3", type=Path)
    args = parser.parse_args()
    if not args.run:
        print("Skipped: opt in with --run. No build, network or configuration access.")
        return

    root = Path(__file__).resolve().parents[3]
    parent = args.work.resolve() if args.work else Path(tempfile.mkdtemp(prefix="exagent-otlp-"))
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="consumer-", dir=parent))
    project = work / "project"
    dependencies = project / "deps"
    dependencies.mkdir(parents=True)
    ignored = shutil.ignore_patterns("_build", ".git", "ebin", ".fetch", "__pycache__")
    for name in LOCAL_DEPENDENCIES:
        source = root / "deps" / name
        if not source.is_dir():
            raise SystemExit(f"Missing local source {source}; resolve root dependencies separately")
        shutil.copytree(source, dependencies / name, ignore=ignored)

    upstream = args.official_checkout.resolve() if args.official_checkout else work / "upstream"
    git_env = {"PATH": "/usr/bin:/bin",
               "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
    if not args.official_checkout:
        upstream.mkdir()
        run(["git", "init"], upstream, git_env, work / "upstream-init.log")
        run(["git", "remote", "add", "origin", OFFICIAL_REPOSITORY],
            upstream, git_env, work / "upstream-remote.log")
        run(["git", "fetch", "--depth", "1", "origin", OFFICIAL_REVISION],
            upstream, git_env, work / "upstream-fetch.log")
        run(["git", "checkout", "--detach", OFFICIAL_REVISION], upstream,
            git_env, work / "upstream-checkout.log")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=upstream,
                                       env=git_env, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain"],
                                    cwd=upstream, env=git_env, text=True)
    if revision != OFFICIAL_REVISION or dirty:
        raise SystemExit("The upstream checkout must be untouched at the exact official revision")
    shutil.copytree(upstream / "apps/opentelemetry_exporter",
                    dependencies / "opentelemetry_exporter", ignore=ignored)

    source = Path(__file__).resolve().parent
    (project / "lib").mkdir()
    shutil.copy2(source / "grpc_exporter.ex", project / "lib/grpc_exporter.ex")
    shutil.copy2(root / "lib/exagent/observability/bounded_processor.ex",
                 project / "lib/bounded_processor.ex")
    shutil.copy2(source / "probe.exs", project / "probe.exs")
    deps = ",\n".join(f'{{:{name}, path: "deps/{name}", override: true, runtime: false}}'
                       for name in (*LOCAL_DEPENDENCIES, "opentelemetry_exporter"))
    (project / "mix.exs").write_text(
        'defmodule OTLPProbe.MixProject do\n'
        '  use Mix.Project\n'
        '  def project, do: [app: :otlp_transport_probe, version: "0.0.0", '
        'elixir: ">= 1.18.0", deps: deps()]\n'
        '  def application, do: [extra_applications: [:logger]]\n'
        f'  defp deps, do: [{deps}]\n'
        'end\n', encoding="utf-8")

    tooling = work / "tooling"
    tooling.mkdir()
    (tooling / "erlang").mkdir()
    (tooling / "archives").mkdir()
    if args.hex_archive:
        shutil.copytree(args.hex_archive.resolve(), tooling / "archives" / args.hex_archive.name)
    path_parts = [str(p.resolve()) for p in (args.erlang_bin, args.elixir_bin) if p]
    env = {"PATH": ":".join((*path_parts, "/usr/bin", "/bin")),
           "MIX_HOME": str(tooling),
           "MIX_ARCHIVES": str(tooling / "archives"), "HEX_HOME": str(tooling / "hex"),
           "HEX_OFFLINE": "1", "REBAR_CACHE_DIR": str(tooling / "rebar"),
           "MIX_BUILD_PATH": str(project / "_build"), "MIX_DEPS_PATH": str(dependencies),
           "EXAGENT_OFFLINE": "1", "MIX_ENV": "test",
           "ERL_FLAGS": f'+S 4:4 +fnu -home {tooling / "erlang"}', "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
           "PROBE_REPORT": str(work / "report.json")}
    if args.rebar3:
        env["MIX_REBAR3"] = str(args.rebar3.resolve())
    run(["mix", "deps.get"], project, env, work / "deps.log")
    run(["mix", "compile", "--warnings-as-errors"], project, env, work / "compile.log")
    run(["mix", "run", "--no-start", "probe.exs"], project, env, work / "probe.log", timeout=45)
    report = json.loads((work / "report.json").read_text(encoding="utf-8"))
    report["consumer"] = str(project)
    report["official_revision"] = revision
    report["source_hashes"] = {
        "test/support/otlp_transport/grpc_exporter.ex": sha256(project / "lib/grpc_exporter.ex"),
        "test/support/otlp_transport/probe.exs": sha256(project / "probe.exs"),
        "test/support/otlp_transport/run.py": sha256(Path(__file__).resolve()),
        "lib/exagent/observability/bounded_processor.ex": sha256(project / "lib/bounded_processor.ex"),
    }
    (work / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "report": str(work / "report.json"),
                      "cases": len(report["cases"]), "cleanup_cycles": len(report["cycles"]),
                      "versions": report["versions"], "official_revision": revision}, indent=2))


if __name__ == "__main__":
    main()
