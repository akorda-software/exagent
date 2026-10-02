#!/usr/bin/env python3
"""Opt-in physical ExAgent freeze and VM-owned native OTLP loopback probe."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run", action="store_true")
    p.add_argument("--work", type=Path)
    p.add_argument("--official-checkout", type=Path, required=False)
    p.add_argument("--hex-archive", type=Path)
    p.add_argument("--elixir-bin", type=Path)
    p.add_argument("--erlang-bin", type=Path)
    p.add_argument("--rebar3", type=Path)
    args = p.parse_args()
    if not args.run:
        print("Skipped: opt in with --run. No build, network or configuration access.")
        return
    source = Path(__file__).resolve().parent
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("isolated_probe_tools", source / "run.py")
    helpers = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helpers)
    root = source.parents[2]
    recipe = root / "examples/otlp_transport"
    parent = args.work.resolve() if args.work else Path(tempfile.mkdtemp(prefix="exagent-otlp-isolated-"))
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="isolated-", dir=parent))
    project = work / "project"
    deps = project / "deps"
    deps.mkdir(parents=True)
    ignored = shutil.ignore_patterns("_build", ".git", "ebin", ".fetch", "__pycache__", ".env", ".env.*")
    manifest = {}

    def copy_file(src, dst):
        src, dst = Path(src), Path(dst)
        if src.is_symlink():
            raise SystemExit(f"Refusing source symlink: {src}")
        before = helpers.sha256(src)
        shutil.copy2(src, dst)
        if helpers.sha256(dst) != before or helpers.sha256(src) != before:
            raise SystemExit(f"Source changed during this physical freeze: {src}")
        manifest[str(src.relative_to(root))] = before
        return str(dst)

    def copy_tree(src, dst):
        for entry in src.rglob("*"):
            if entry.is_symlink():
                raise SystemExit(f"Refusing source symlink: {entry}")
        shutil.copytree(src, dst, ignore=ignored, copy_function=copy_file)

    names = sorted(d.name for d in (root / "deps").iterdir() if d.is_dir()
                   and d.name != "opentelemetry_exporter")
    for name in names:
        copy_tree(root / "deps" / name, deps / name)
    snapshot = deps / "exagent"
    snapshot.mkdir()
    for directory in ("lib", "config"):
        copy_tree(root / directory, snapshot / directory)
    for name in ("mix.exs", "mix.lock", "README.md", "LICENSE"):
        copy_file(root / name, snapshot / name)
    # Detect a source mutation after copying too; this freeze is evidence only,
    # never a claim that another owner's evolving ROOT is the final candidate.
    changed = [name for name, digest in manifest.items() if helpers.sha256(root / name) != digest]
    if changed:
        raise SystemExit(f"Source changed while freezing: {changed[:8]}")
    (work / "freeze.json").write_text(json.dumps(manifest, indent=2) + "\n")

    upstream = args.official_checkout.resolve() if args.official_checkout else work / "upstream"
    git_env = {"PATH": "/usr/bin:/bin",
               "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
    if not args.official_checkout:
        upstream.mkdir()
        for command, log in [(["git", "init"], "init"),
                             (["git", "remote", "add", "origin", helpers.OFFICIAL_REPOSITORY], "remote"),
                             (["git", "fetch", "--depth", "1", "origin", helpers.OFFICIAL_REVISION], "fetch"),
                             (["git", "checkout", "--detach", helpers.OFFICIAL_REVISION], "checkout")]:
            helpers.run(command, upstream, git_env, work / f"upstream-{log}.log")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=upstream, env=git_env, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=upstream, env=git_env, text=True)
    if revision != helpers.OFFICIAL_REVISION or dirty:
        raise SystemExit("Require untouched official checkout at the exact pre-release pin")
    shutil.copytree(upstream / "apps/opentelemetry_exporter", deps / "opentelemetry_exporter", ignore=ignored)
    (project / "lib").mkdir()
    shutil.copy2(recipe / "isolated_exporter.ex", project / "lib/isolated_exporter.ex")
    shutil.copy2(source / "isolated_probe.exs", project / "isolated_probe.exs")
    for name in ("vm_launcher.py", "vm_worker.exs"):
        shutil.copy2(recipe / name, project / name)
    dependency_terms = ",\n".join(
        f'{{:{name}, path: "deps/{name}", override: true, runtime: false}}'
        for name in ["exagent", *names, "opentelemetry_exporter"])
    (project / "mix.exs").write_text(
        'defmodule OTLPIsolatedProbe.MixProject do\n  use Mix.Project\n'
        '  def project, do: [app: :otlp_isolated_probe, version: "0.0.0", elixir: ">= 1.18.0", deps: deps()]\n'
        '  def application, do: [extra_applications: [:logger]]\n'
        f'  defp deps, do: [{dependency_terms}]\nend\n')
    tooling = work / "tooling"
    (tooling / "archives").mkdir(parents=True)
    (tooling / "erlang").mkdir()
    if args.hex_archive:
        shutil.copytree(args.hex_archive.resolve(), tooling / "archives" / args.hex_archive.name)
    path_parts = [str(v.resolve()) for v in (args.erlang_bin, args.elixir_bin) if v]
    env = {"PATH": ":".join([*path_parts, "/usr/bin", "/bin"]),
           "MIX_HOME": str(tooling),
           "MIX_ARCHIVES": str(tooling / "archives"), "HEX_HOME": str(tooling / "hex"),
           "HEX_OFFLINE": "1", "REBAR_CACHE_DIR": str(tooling / "rebar"),
           "MIX_BUILD_PATH": str(project / "_build"), "MIX_DEPS_PATH": str(deps),
           "EXAGENT_OFFLINE": "1", "MIX_ENV": "test",
           "ERL_FLAGS": f'+S 4:4 +fnu -home {tooling / "erlang"}',
           "OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT": "64", "OTEL_SPAN_ATTRIBUTE_VALUE_LENGTH_LIMIT": "128",
           "OTEL_SPAN_EVENT_COUNT_LIMIT": "8", "OTEL_SPAN_LINK_COUNT_LIMIT": "4",
           "OTEL_EVENT_ATTRIBUTE_COUNT_LIMIT": "16", "OTEL_LINK_ATTRIBUTE_COUNT_LIMIT": "16",
           "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "PROBE_REPORT": str(work / "report.json"),
           "PROBE_ELIXIR": str(args.elixir_bin.resolve() / "elixir") if args.elixir_bin else shutil.which("elixir"),
           "PROBE_PYTHON": str(Path(shutil.which("python3")).resolve()),
           "PROBE_BEAM_PATH": str(project / "_build/lib/*/ebin")}
    if args.rebar3:
        env["MIX_REBAR3"] = str(args.rebar3.resolve())
    helpers.run(["mix", "deps.get"], project, env, work / "deps.log")
    helpers.run(["mix", "compile", "--warnings-as-errors"], project, env, work / "compile.log")
    helpers.run(["mix", "run", "--no-start", "isolated_probe.exs"], project, env, work / "probe.log", timeout=80)
    report = json.loads((work / "report.json").read_text())
    report.update({"consumer": str(project), "official_revision": revision,
                   "freeze_manifest_sha256": helpers.sha256(work / "freeze.json"),
                   "freeze_source_files": len(manifest), "freeze_is_final_candidate": False,
                   "source_hashes": {
                       **{f"test/support/otlp_transport/{name}": helpers.sha256(source / name)
                          for name in ("run_isolated.py", "run.py", "isolated_probe.exs")},
                       **{f"examples/otlp_transport/{name}": helpers.sha256(recipe / name)
                          for name in ("isolated_exporter.ex", "vm_launcher.py", "vm_worker.exs")}}})
    (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "report": str(work / "report.json"),
                      "cases": len(report["cases"]), "cycles": len(report["cycles"])}, indent=2))


if __name__ == "__main__":
    main()
