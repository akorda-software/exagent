# Finite checks of CURRENT consumer fixtures against an explicitly supplied,
# already compiled package graph. No Mix/install; this is fixture investigation,
# not new package-byte/compile-order acceptance. Run with plain elixir:
# elixir ...exs --ebin '/absolute/frozen/sdk/lib/*/ebin' --mode sdk
Code.require_file("../../examples/testing_audit_harness.exs", __DIR__)

defmodule ExAgent.TestingAuditHarness.PackageProbe do
  import ExUnit.Assertions
  alias ExAgent.TestingAuditHarness, as: Gate

  def run(args) do
    {opts, [], []} = OptionParser.parse(args, strict: [ebin: :string, mode: :string])
    mode = Keyword.fetch!(opts, :mode)
    true = mode in ~w(sdk exporter)
    ebin = Path.expand(Keyword.fetch!(opts, :ebin))

    base =
      Path.join("/tmp/opencode", "testing_audit_harness_package_#{System.os_time(:nanosecond)}")

    File.mkdir!(base)
    fixtures = Path.expand("../fixtures/package_acceptance", __DIR__)

    scrub = for {key, _} <- System.get_env(), String.starts_with?(key, "OTEL_"), do: {key, nil}

    for control <- ~w(positive omitted excluded wrong-return ecto-bypass duplicate-span) do
      cwd = Path.join(base, control)
      File.mkdir!(cwd)

      for source <- Path.wildcard(Path.join(fixtures, "**/*.template")) do
        dest =
          Path.join(
            cwd,
            source |> Path.relative_to(fixtures) |> String.trim_trailing(".template")
          )

        File.mkdir_p!(Path.dirname(dest))
        File.cp!(source, dest)
      end

      test = Path.join(cwd, "test/package_test.exs")
      smoke = Path.join(cwd, "package_smoke.exs")
      tracing = Path.join(cwd, "package_tracing.exs")

      case control do
        "omitted" ->
          mutate!(
            test,
            ~s[test "Ecto remains the final structured-output authority" do],
            "def omitted_contract do"
          )

        "excluded" ->
          mutate!(
            test,
            ~s[test "Ecto remains the final structured-output authority" do],
            ~s[@tag :testing_audit_omitted\n  test "Ecto remains the final structured-output authority" do]
          )

        "wrong-return" ->
          mutate!(smoke, "{:ok, a + b}", "{:ok, a + b + 1}")

        "ecto-bypass" ->
          mutate!(
            smoke,
            ~s|if rem(value, 2) == 1, do: [], else: [answer: "must be odd"]|,
            "if is_integer(value), do: [], else: []"
          )

        "duplicate-span" ->
          mutate!(
            tracing,
            "assert_operations(observed, scenarios)",
            "assert_operations([hd(observed), hd(observed) | Enum.drop(observed, 2)], scenarios)"
          )

        "positive" ->
          :ok
      end

      script = """
      Application.put_env(:opentelemetry, :processors, [])
      {:ok, _} = Application.ensure_all_started(:exagent)
      {:ok, _} = Application.ensure_all_started(:opentelemetry)
      Code.require_file("test/test_helper.exs")
      ExUnit.configure(autorun: false, seed: 37556, exclude: [:testing_audit_omitted])
      Code.require_file("test/package_test.exs")
      result = ExUnit.run()
      IO.inspect(result, label: "REAL_EXUNIT_RESULT")
      System.halt(if result.failures == 0, do: 0, else: 1)
      """

      {output, status} =
        System.cmd("elixir", ["-pa", ebin, "-e", script],
          cd: cwd,
          env: scrub ++ [{"EXAGENT_OFFLINE", "1"}, {"PACKAGE_ACCEPTANCE_MODE", mode}],
          stderr_to_stdout: true
        )

      File.write!(Path.join(cwd, "run.log"), output)

      runtime =
        read_term(cwd, "runtime-results.etf")
        |> Map.put(:stats, read_term(cwd, "runtime-stats.etf"))

      errors = Gate.package_result(runtime, mode)

      File.write!(
        Path.join(cwd, "gate.term"),
        inspect(%{exit: status, errors: errors, stats: runtime.stats})
      )

      IO.inspect(%{control: control, exit: status, errors: errors, stats: runtime.stats})

      if control == "positive" do
        assert status == 0, output
        assert errors == []
      else
        assert errors != []
        if control in ~w(omitted excluded), do: assert(status == 0), else: assert(status == 1)
      end
    end

    IO.puts("PASS current-fixture controls on supplied existing BEAMs: #{base}")
  end

  defp read_term(cwd, file),
    do: cwd |> Path.join(file) |> File.read!() |> :erlang.binary_to_term()

  defp mutate!(path, needle, replacement) do
    source = File.read!(path)
    assert length(:binary.matches(source, needle)) == 1, "mutation anchor changed: #{needle}"
    File.write!(path, String.replace(source, needle, replacement))
  end
end

ExAgent.TestingAuditHarness.PackageProbe.run(System.argv())
