#!/usr/bin/env python3
"""Opt-in route delta using physical freeze004 and official release artifacts."""
import argparse
import ast
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile

COLLECTOR_ARCHIVE_SHA256 = "f99929987a915d3c6b2c9b15bc4938c5cea903a37a3f49e478024a0fa0772339"
EXPORTER_ARCHIVE_SHA256 = "24833c5f54d0996a454793383a5a8526750cbacc5c03e5be54b593fe7d47fb0a"


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run", action="store_true")
    p.add_argument("--freeze", type=Path)
    p.add_argument("--artifacts", type=Path)
    p.add_argument("--work", type=Path)
    p.add_argument("--elixir-bin", type=Path)
    p.add_argument("--erlang-bin", type=Path)
    p.add_argument("--rebar3", type=Path)
    args = p.parse_args()
    if not args.run:
        print("Skipped: opt in with --run. No freeze/artifact/configuration access.")
        return
    if not all((args.freeze, args.artifacts, args.elixir_bin, args.erlang_bin, args.rebar3)):
        raise SystemExit("Require explicit freeze004, verified artifacts and tooling paths")
    sys.dont_write_bytecode = True
    source = Path(__file__).resolve().parent
    root = source.parents[2]
    recipe = root / "examples/otlp_transport"
    spec = importlib.util.spec_from_file_location("collector_probe_tools", source / "run.py")
    helpers = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helpers)
    freeze = args.freeze.resolve()
    artifacts = args.artifacts.resolve()
    old_report = json.loads((freeze.parent / "report.json").read_text())
    if old_report["status"] != "exagent_native_loopback_vm_recipe_only":
        raise SystemExit("Require the qualified physical freeze004, not mutable ROOT")
    for entry in freeze.rglob("*"):
        if entry.is_symlink() and not entry.resolve().is_relative_to(freeze):
            raise SystemExit(f"Refusing external frozen-source/build link: {entry}")
    parent = args.work.resolve() if args.work else Path(tempfile.mkdtemp(prefix="exagent-collector-"))
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="route-", dir=parent))
    project = work / "project"
    # Follow only already-validated private build symlinks into physical copies.
    shutil.copytree(freeze, project, ignore=shutil.ignore_patterns("__pycache__", ".env", ".env.*"))
    tooling = work / "tooling"
    shutil.copytree(freeze.parent / "tooling/archives", tooling / "archives")
    (tooling / "erlang").mkdir()
    downloads = artifacts / "downloads"
    collector_archive = downloads / "otelcol_0.162.0_linux_amd64.tar.gz"
    exporter_archive = downloads / "opentelemetry_exporter-1.11.0.tar"
    if digest(collector_archive) != COLLECTOR_ARCHIVE_SHA256 or digest(exporter_archive) != EXPORTER_ARCHIVE_SHA256:
        raise SystemExit("Official artifact checksum mismatch")
    binary = work / "otelcol"
    with tarfile.open(collector_archive) as archive:
        member = archive.getmember("otelcol")
        assert member.isfile() and member.size <= 200_000_000
        binary.write_bytes(archive.extractfile(member).read())
    binary.chmod(0o755)
    dependency = project / "deps/opentelemetry_exporter"
    # Only this newly created private copy is replaced, never freeze004 or ROOT.
    shutil.rmtree(dependency)
    dependency.mkdir()
    with tarfile.open(exporter_archive) as archive:
        contents = archive.extractfile("contents.tar.gz").read()
    with tarfile.open(fileobj=io.BytesIO(contents), mode="r:gz") as archive:
        assert all(m.isfile() or m.isdir() for m in archive.getmembers())
        assert all(not Path(m.name).is_absolute() and ".." not in Path(m.name).parts for m in archive.getmembers())
        archive.extractall(dependency, filter="data")
    provenance = json.loads((artifacts / "provenance.json").read_text())
    assert digest(binary) == provenance["collector"]["binary_sha256"]
    comparisons = {}
    for name in ("otel_otlp_traces.erl", "otel_otlp_common.erl", "opentelemetry_trace_service.erl", "opentelemetry_exporter.erl"):
        original = freeze / "deps/opentelemetry_exporter/src" / name
        released = dependency / "src" / name
        comparisons[name] = {"equal": digest(original) == digest(released),
                             "pin004_sha256": digest(original), "release_sha256": digest(released)}
    assert comparisons["otel_otlp_traces.erl"]["equal"] and comparisons["otel_otlp_common.erl"]["equal"]
    shutil.copy2(source / "collector_probe.exs", project / "collector_probe.exs")
    shutil.copy2(source / "collector_lifecycle.py", project / "collector_lifecycle.py")
    # Established fixture uses the public OTP HTTP parser; only it invokes the
    # upstream generated private PB decoder/encoder to inspect synthetic traffic.
    shutil.copy2(root / "test/support/native_otlp_receiver.ex", project / "native_otlp_receiver.ex")
    for name in ("collector.py", "collector.yaml"):
        shutil.copy2(recipe / name, project / name)
    for name in ("collector.py", "collector_lifecycle.py", "vm_launcher.py"):
        ast.parse((project / name).read_text(), filename=name)
    env = {"PATH": f"{args.erlang_bin.resolve()}:{args.elixir_bin.resolve()}:/usr/bin:/bin",
           "MIX_HOME": str(tooling), "MIX_ARCHIVES": str(tooling / "archives"),
           "HEX_HOME": str(tooling / "hex"), "HEX_OFFLINE": "1",
           "REBAR_CACHE_DIR": str(tooling / "rebar"), "MIX_REBAR3": str(args.rebar3.resolve()),
           "MIX_BUILD_PATH": str(project / "_build"), "MIX_DEPS_PATH": str(project / "deps"),
           "EXAGENT_OFFLINE": "1", "MIX_ENV": "test", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
           "ERL_FLAGS": f'+S 4:4 +fnu -home {tooling / "erlang"}',
           "OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT": "64", "OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT": "128",
           "OTEL_SPAN_EVENT_COUNT_LIMIT": "8", "OTEL_SPAN_LINK_COUNT_LIMIT": "4",
           "OTEL_EVENT_ATTRIBUTE_COUNT_LIMIT": "16", "OTEL_LINK_ATTRIBUTE_COUNT_LIMIT": "16",
           "PROBE_REPORT": str(work / "report.json"),
           "PROBE_ELIXIR": str(args.elixir_bin.resolve() / "elixir"), "PROBE_PYTHON": "/usr/bin/python3",
           "PROBE_BEAM_PATH": str(project / "_build/lib/*/ebin"), "PROBE_COLLECTOR": str(binary),
           "PROBE_WORK": str(work)}
    helpers.run([str(binary), "--version"], project, env, work / "collector-version.log", timeout=5)
    helpers.run(["mix", "deps.compile", "opentelemetry_exporter", "--force"], project, env, work / "compile-release.log")
    helpers.run(["mix", "compile", "--no-deps-check", "--warnings-as-errors"], project, env, work / "compile.log")
    helpers.run(["/usr/bin/python3", "collector_lifecycle.py", "--run", "--launcher", str(project / "collector.py"),
                 "--binary", str(binary), "--config", str(project / "collector.yaml"),
                 "--work", str(work), "--report", str(work / "lifecycle.json")],
                project, env, work / "lifecycle.log", timeout=30)
    helpers.run(["mix", "run", "--no-compile", "--no-start", "collector_probe.exs"],
                project, env, work / "probe.log", timeout=90)
    report = json.loads((work / "report.json").read_text())
    report.update({"consumer": str(project), "provenance": provenance,
                   "collector_owner_controls": json.loads((work / "lifecycle.json").read_text()),
                   "commands": [json.loads(line) for line in (work / "commands.jsonl").read_text().splitlines()],
                   "warning_lines": {name: sum("warning:" in line for line in (work / name).read_text().splitlines())
                                     for name in ("compile-release.log", "compile.log", "probe.log")},
                   "release_comparison": comparisons,
                   "origin004_report_sha256": digest(freeze.parent / "report.json"),
                   "origin004_freeze_sha256": old_report["freeze_manifest_sha256"],
                   "origin004_is_final_candidate": False,
                   "source_hashes": {
                       "test/support/otlp_transport/run_collector.py": digest(Path(__file__).resolve()),
                       "test/support/otlp_transport/collector_probe.exs": digest(project / "collector_probe.exs"),
                       "test/support/otlp_transport/collector_lifecycle.py": digest(project / "collector_lifecycle.py"),
                       "test/support/native_otlp_receiver.ex": digest(project / "native_otlp_receiver.ex"),
                       "examples/otlp_transport/collector.py": digest(project / "collector.py"),
                       "examples/otlp_transport/collector.yaml": digest(project / "collector.yaml")},
                   "tooling_delta": "HOME/CODEX_HOME never reassigned; explicit Mix/Hex/Rebar directories and Erlang -home",
                   "origin004_receipts_preserved_as_historical_bytes": True})
    (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "report": str(work / "report.json"),
                      "cases": len(report["cases"]), "cycles": len(report["cycles"])}, indent=2))


if __name__ == "__main__":
    main()
