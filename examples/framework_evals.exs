# Deterministic offline framework evals (two generic domains, no LLM or judge):
#   EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/framework_evals.exs
#   EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/framework_evals.exs --json /tmp/framework-evals.json
# Exit 1 on failed criteria. Use --json for machine input: framework diagnostics
# may precede the JSON printed to stdout (the failed checkpoint is intentional).
Code.require_file("framework_scenarios.exs", __DIR__)

defmodule ExAgent.FrameworkEvals do
  alias ExAgent.FrameworkScenarios, as: Scenarios

  def run do
    %{
      version: 1,
      scope:
        "deterministic framework contracts, not model intelligence or real-backend acceptance",
      seed: 131_415,
      input: Scenarios.input(),
      source_sha256: Scenarios.provenance(),
      cases: [Scenarios.reading_eval(), Scenarios.effect_eval(), Scenarios.negative_controls()]
    }
    |> then(fn report -> Map.put(report, :passed, Enum.all?(report.cases, & &1.passed)) end)
  end
end

{opts, [], []} = OptionParser.parse(System.argv(), strict: [json: :string])
report = ExAgent.FrameworkEvals.run()
encoded = Jason.encode!(report, pretty: true)
if opts[:json], do: File.write!(opts[:json], encoded <> "\n")
IO.puts(encoded)
if not report.passed, do: System.halt(1)
