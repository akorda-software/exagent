defmodule ExAgent.Observability.NativeOTLPTest do
  use ExUnit.Case, async: false

  # HTTP profiles, exporter environment and SDK state belong to a disposable VM.
  # In particular, the lifecycle characterization must not leak native profiles
  # or change application-owned tracing configuration in the ExUnit VM.
  @tag timeout: 30_000
  test "native HTTP protobuf preserves the full traces path, hierarchy and privacy" do
    probe("wire")
  end

  @tag timeout: 30_000
  test "native generic endpoint appends the signal path" do
    probe("generic_endpoint")
  end

  @tag timeout: 30_000
  test "native failures and partial success do not block runs or replay effects" do
    probe("failures")
  end

  @tag timeout: 30_000
  test "native HTTP lifecycle separates processor cleanup from surviving profiles and sockets" do
    probe("lifecycle")
  end

  defp probe(scenario) do
    paths = :code.get_path() |> Enum.flat_map(&["-pa", to_string(&1)])
    script = Path.expand("../../support/native_otlp_probe.exs", __DIR__)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++ paths ++ [script, scenario],
        stderr_to_stdout: true,
        env: [{"EXAGENT_OFFLINE", "1"}, {"MIX_ENV", "test"}]
      )

    assert status == 0, output
    assert output =~ "NATIVE_OTLP_OK #{scenario}\n", output
  end
end
