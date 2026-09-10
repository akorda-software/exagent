defmodule ExAgent.Observability.NativeOTLPScenarioTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 45_000

  test "composed streaming, parallel delegation, correction and checkpoints cross native OTLP" do
    probe("composed")
  end

  test "queued callers, cancellation and after-hook failure preserve trace and partial accounting" do
    probe("queued_failures")
  end

  test "content policy and caller context remain isolated at the native transport boundary" do
    probe("privacy")
  end

  defp probe(scenario) do
    paths = :code.get_path() |> Enum.flat_map(&["-pa", to_string(&1)])
    script = Path.expand("../../support/native_otlp_scenario_probe.exs", __DIR__)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++ paths ++ [script, scenario],
        stderr_to_stdout: true,
        env: [{"EXAGENT_OFFLINE", "1"}, {"MIX_ENV", "test"}]
      )

    assert status == 0, output
    refute Regex.match?(~r/(?:^|\n)\s*warning:/, output), output
    assert output =~ "NATIVE_OTLP_SCENARIO_OK #{scenario}\n", output
  end
end
