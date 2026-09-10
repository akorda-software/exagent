# Offline bootstrap-boundary and diagnostic regressions, with synthetic /tmp data:
#   elixir test/support/package_acceptance_isolation.exs /absolute/package.tar
# No install/download/build command is executed by these controls.

defmodule PackageAcceptance.Isolation do
  import ExUnit.Assertions

  def main(tar) do
    base = "/tmp/opencode/exagent-night-package-isolation-#{System.os_time(:nanosecond)}"
    File.mkdir!(base)
    host = Path.join(base, "fake-host")
    File.mkdir!(host)
    sentinel = Path.join(host, "sentinel")
    File.write!(sentinel, "must not change")
    foreign = Path.join(host, "foreign.exs")
    File.write!(foreign, ~s[IO.puts("FOREIGN_PROJECT_EXECUTED"); System.halt(77)\n])
    original_host = inventory(host)
    runner = Path.expand("package_acceptance.exs", __DIR__)

    original =
      File.read!(runner)
      |> replace!(
        ~s[Code.require_file("../../examples/testing_audit_harness.exs", __DIR__)],
        ~s[Code.require_file(#{inspect(Path.expand("../../examples/testing_audit_harness.exs", __DIR__))})]
      )

    env = [
      {"MIX_HOME", Path.join(host, "mix")},
      {"MIX_ARCHIVES", Path.join(host, "archives")},
      {"MIX_ESCRIPTS", Path.join(host, "escripts")},
      {"MIX_REBAR3", Path.join(host, "rebar3")},
      {"MIX_EXS", foreign},
      {"MIX_INSTALL_RESTORE_PROJECT_DIR", host},
      {"MIX_INSTALL_DIR", Path.join(host, "install")},
      {"MIX_TARGET", "external_target"},
      {"MIX_ENV", "prod"},
      {"MIX_PATH", Path.join(host, "code")},
      {"MIX_QUIET", "1"},
      {"HEX_HOME", Path.join(host, "hex")},
      {"XDG_CACHE_HOME", Path.join(host, "cache")},
      {"XDG_CONFIG_HOME", Path.join(host, "config")},
      {"XDG_DATA_HOME", Path.join(host, "data")},
      {"REBAR_CACHE_DIR", Path.join(host, "rebar-cache")},
      {"REBAR_GLOBAL_CONFIG_DIR", Path.join(host, "rebar-config")}
    ]

    # Exercise the CLI with help in the positive; the second bootstrap halts.
    # Even an accidentally removed guard cannot install anything in this copy.
    safe =
      original
      |> replace!(
        ~s|command!(base, "tooling-hex", ["local.hex", "--force"], env)|,
        ~s|command!(base, "tooling-hex", ["help"], env)|
      )
      |> replace!(
        ~s|command!(base, "tooling-rebar", ["local.rebar", "--force"], env)|,
        "System.halt(0)"
      )

    for {label, needle, reason} <- [
          {"archives", ~s|{"MIX_ARCHIVES", Path.join(base, "mix-home/archives")},|,
           "non-isolated destination: archives"},
          {"project", ~s|{"MIX_EXS", nil},|, "non-isolated selector: MIX_EXS"},
          {"restore", ~s|{"MIX_INSTALL_RESTORE_PROJECT_DIR", nil},|,
           "non-isolated selector: MIX_INSTALL_RESTORE_PROJECT_DIR"},
          {"target", ~s|{"MIX_TARGET", "host"},|, "non-isolated selector: MIX_TARGET"}
        ] do
      copy = write_copy(base, "without-#{label}", replace!(safe, needle, ""))
      work = base <> "-negative-#{label}"
      assert run(base, label, copy, tar, work, env, []) == 1
      assert File.read!(Path.join(work, "tooling-preflight.log")) =~ reason
      refute File.exists?(Path.join(work, "tooling-hex.log"))
      refute File.read!(Path.join(work, "tooling-preflight.log")) =~ "FOREIGN_PROJECT_EXECUTED"
    end

    work = base <> "-positive"
    assert run(base, "positive", runner, tar, work, env, ["--prepare-only"]) == 0

    assert File.read!(Path.join(work, "tooling-preflight.log")) =~
             "verified effective CLI project: none"

    refute File.exists?(Path.join(work, "tooling-hex.log"))

    warning =
      replace!(
        original,
        ~s|Mix.CLI.main(["help"])|,
        ~s|IO.warn("preflight diagnostic control"); Mix.CLI.main(["help"])|
      )

    copy = write_copy(base, "preflight-warning", warning)
    work = base <> "-preflight-warning"
    assert run(base, "preflight-warning", copy, tar, work, env, ["--prepare-only"]) == 1

    assert File.read!(Path.join(work, "phase-tooling-preflight.term")) =~
             "preflight diagnostic control"

    refute File.exists?(Path.join(work, "tooling-hex.log"))

    copy = write_copy(base, "help", safe)
    work = base <> "-help"
    assert run(base, "help", copy, tar, work, env, []) == 0
    assert File.read!(Path.join(work, "tooling-hex.log")) =~ "mix help"
    refute File.read!(Path.join(work, "tooling-hex.log")) =~ "FOREIGN_PROJECT_EXECUTED"

    local_project = """
    IO.puts("SYNTHETIC_LOCAL_PROJECT_EXECUTED")
    defmodule SyntheticLocal.MixProject do
      use Mix.Project
      def project, do: [app: :synthetic_local, version: "0.0.0", deps: []]
    end
    """

    local =
      replace!(
        safe,
        ~s|command!(base, "tooling-hex", ["help"], env)|,
        ~s|File.write!(Path.join(base, "mix.exs"), #{inspect(local_project)}); command!(base, "tooling-hex", ["help"], env)|
      )

    copy = write_copy(base, "local-project", local)
    work = base <> "-local-project"
    assert run(base, "local-project", copy, tar, work, env, []) == 0
    assert File.read!(Path.join(work, "tooling-hex.log")) =~ "SYNTHETIC_LOCAL_PROJECT_EXECUTED"
    refute File.read!(Path.join(work, "tooling-hex.log")) =~ "FOREIGN_PROJECT_EXECUTED"

    # The guard is also required at command time, not only during preflight.
    poisoned =
      replace!(
        safe,
        ~s|command!(base, "tooling-hex", ["help"], env)|,
        ~s|command!(base, "tooling-hex", ["help"], env ++ [{"MIX_EXS", #{inspect(foreign)}}])|
      )

    copy = write_copy(base, "late-selector", poisoned)
    work = base <> "-late-selector"
    assert run(base, "late-selector", copy, tar, work, env, []) == 1
    assert File.read!(Path.join(work, "tooling-hex.log")) =~ "non-isolated selector: MIX_EXS"
    refute File.read!(Path.join(work, "tooling-hex.log")) =~ "FOREIGN_PROJECT_EXECUTED"

    outside = Path.join(base, "fake-external-target")
    File.mkdir!(outside)
    File.write!(Path.join(outside, "sentinel"), "unchanged")
    link = base <> "-linked-parent"
    dangling = base <> "-dangling"
    File.ln_s!(outside, link)
    File.ln_s!(Path.join(base, "missing-target"), dangling)

    for {label, work} <- [
          {"ancestor", Path.join(link, "new-work")},
          {"symlink", link},
          {"dangling", dangling},
          {"existing", base}
        ] do
      assert run(base, label, runner, tar, work, env, ["--prepare-only"]) == 1
      assert File.read!(Path.join(base, label <> ".log")) =~ "work-dir"
    end

    assert File.read_link!(link) == outside
    assert File.read_link!(dangling) == Path.join(base, "missing-target")
    assert inventory(outside) == %{"sentinel" => "unchanged"}
    refute File.exists?(Path.join(base, "missing-target"))
    assert inventory(host) == original_host

    # Substitute only child task output, preserving the runner's real phase
    # recording and strict decision. This is diagnostic classification evidence,
    # not a package compile/runtime pass. Preflight still uses the real CLI.
    replay =
      original
      |> replace!(
        ~s[Path.expand("../fixtures/package_acceptance", __DIR__)],
        inspect(Path.expand("../fixtures/package_acceptance", __DIR__))
      )
      |> replace!(~s|script = project_guard() <> "Mix.CLI.main(System.argv())\\n"|, """
        warning = if System.get_env("ISOLATION_WARNING_PHASE") == name, do: "synthetic.erl:1: Warning: diagnostic control\\n", else: ""
        artifact = cond do
          name == "graph" -> ~s[File.write!("graph.term", "synthetic graph evidence"); ]
          name == "smoke" ->
            # Deliberately synthetic diagnostic replay, not executed contracts.
            data = %{tests: Enum.map(ExAgent.TestingAuditHarness.package_names("none"), &%{name: &1, module: "PackageAcceptanceTest", state: nil})}
            stats = %{total: 6, failures: 0, excluded: 0, skipped: 0}
            ~s|File.write!("runtime-results.etf", | <> inspect(:erlang.term_to_binary(data), limit: :infinity) <> "); " <>
              ~s|File.write!("runtime-stats.etf", | <> inspect(:erlang.term_to_binary(stats), limit: :infinity) <> "); "
          true -> ""
        end
        script = artifact <> "IO.write(" <> inspect(warning) <> ")"
      """)

    copy = write_copy(base, "diagnostics", replay)

    for phase <- [
          "clean",
          "tooling-hex",
          "tooling-rebar",
          "deps-get",
          "compile-edge",
          "compile",
          "graph",
          "smoke"
        ] do
      work = base <> "-diagnostic-#{phase}"
      expected = if phase == "clean", do: 0, else: 1

      assert run(
               base,
               "diagnostic-#{phase}",
               copy,
               tar,
               work,
               env ++ [{"ISOLATION_WARNING_PHASE", phase}],
               ["--mode", "none"]
             ) == expected

      summary = File.read!(Path.join(work, "summary.term"))
      assert summary =~ "runtime_contracts: :passed"
      assert File.read!(Path.join([work, "none", "graph.term"])) == "synthetic graph evidence"
      assert File.read!(Path.join([work, "none", "phase-graph.term"])) =~ ~s|phase: "graph"|

      if phase != "clean" do
        assert summary =~ ~s|warning_phases: "#{phase}"|
        assert summary =~ "Warning: diagnostic control"
      end
    end

    assert inventory(host) == original_host

    IO.puts(
      "PASS: guarded CLI, project/tooling selectors, symlinks, and strict diagnostics; fake-host unchanged"
    )

    IO.puts("Evidence: #{base}")
  end

  defp replace!(source, needle, replacement) do
    assert length(:binary.matches(source, needle)) == 1,
           "update fault injection after runner refactor: #{needle}"

    String.replace(source, needle, replacement)
  end

  defp write_copy(base, name, source) do
    path = Path.join(base, name <> ".exs")
    File.write!(path, source)
    path
  end

  defp run(base, name, script, tar, work, env, args) do
    {output, status} =
      System.cmd(
        "elixir",
        [script, "--tar", Path.expand(tar), "--work-dir", work] ++ args,
        env: env,
        stderr_to_stdout: true
      )

    File.write!(Path.join(base, name <> ".log"), output)
    status
  end

  defp inventory(dir), do: Map.new(File.ls!(dir), &{&1, File.read!(Path.join(dir, &1))})
end

[tar] = System.argv()
PackageAcceptance.Isolation.main(tar)
