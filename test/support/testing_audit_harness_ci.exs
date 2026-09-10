# Finite CI command recorder. Run with plain elixir after setup-beam/deps.get:
# EXAGENT_OFFLINE=1 MIX_ENV=test elixir ...exs suite|harness /absolute/evidence
# GNU timeout supplies child-process deadlines on the Ubuntu CI runners.
unless System.get_env("EXAGENT_OFFLINE") == "1" and System.get_env("MIX_ENV") == "test",
  do: raise("CI gates require EXAGENT_OFFLINE=1 MIX_ENV=test")

[mode, evidence] = System.argv()
true = mode in ["suite", "harness"]
evidence = Path.expand(evidence)
File.mkdir_p!(evidence)
beam = Path.expand("_build/test/lib")

commands =
  if mode == "suite" do
    [
      {"compile", "mix", ["compile", "--force", "--warnings-as-errors"]},
      {"format", "mix", ["format", "--check-formatted"]},
      {"test", "mix", ["test", "--warnings-as-errors", "--seed", "37556"]}
    ]
  else
    [
      {"compile", "mix", ["compile", "--force", "--warnings-as-errors"]},
      {"c0", "mix",
       ["run", "test/support/consolidation_probe.exs", "--json", Path.join(evidence, "c0.json")]},
      {"docs", "elixir", ["-pa", beam <> "/*/ebin", "test/support/documentation_probe.exs"]},
      {"r3", "elixir",
       [
         "-pa",
         beam <> "/opentelemetry/ebin",
         "-pa",
         beam <> "/opentelemetry_api/ebin",
         "-pa",
         beam <> "/telemetry/ebin",
         "test/support/observability_processor_probe.exs"
       ]},
      {"evals", "mix",
       ["run", "examples/framework_evals.exs", "--json", Path.join(evidence, "evals.json")]},
      {"load", "mix",
       [
         "run",
         "test/support/framework_load_probe.exs",
         "--smoke",
         "--json",
         Path.join(evidence, "load.json")
       ]}
    ]
  end

results =
  Enum.map(commands, fn {name, executable, args} ->
    IO.puts("GATE #{name}: #{executable} #{Enum.join(args, " ")}")

    {output, status} =
      System.cmd("timeout", ["--kill-after=10s", "300s", executable | args],
        stderr_to_stdout: true
      )

    File.write!(Path.join(evidence, name <> ".log"), output)
    IO.write(output)

    result = %{
      gate: name,
      command: [executable | args],
      exit_code: status,
      warning_lines:
        output |> String.split("\n") |> Enum.filter(&Regex.match?(~r/\bwarning:/i, &1))
    }

    File.write!(
      Path.join(evidence, name <> ".term"),
      inspect(result, pretty: true, limit: :infinity) <> "\n"
    )

    result
  end)

sources =
  for path <-
        Path.wildcard("{lib,test,examples}/**/*.{ex,exs,template}") ++
          ["mix.exs", "mix.lock", ".github/workflows/ci.yml"],
      do: {path, Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)}

beams =
  for path <- Path.wildcard(beam <> "/exagent/ebin/*.beam"),
      do: {path, Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)}

report = %{
  elixir: System.version(),
  otp: System.otp_release(),
  build_path: beam,
  offline: System.get_env("EXAGENT_OFFLINE"),
  mix_env: System.get_env("MIX_ENV"),
  results: results,
  source_sha256: Map.new(sources),
  beam_sha256: Map.new(beams)
}

File.write!(
  Path.join(evidence, "summary.term"),
  inspect(report, pretty: true, limit: :infinity) <> "\n"
)

if Enum.any?(results, &(&1.exit_code != 0)), do: System.halt(1)
