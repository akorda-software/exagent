# Independent JSON acceptance, with no scenario execution:
# elixir -pa '_build/test/lib/jason/ebin' ...exs c0|evals|load /absolute/report.json
Code.require_file("../../examples/testing_audit_harness.exs", __DIR__)
[kind, path] = System.argv()
report = path |> File.read!() |> Jason.decode!()

errors =
  case kind do
    "c0" -> ExAgent.TestingAuditHarness.c0(report)
    "evals" -> ExAgent.TestingAuditHarness.evals(report)
    "load" -> ExAgent.TestingAuditHarness.load(report)
  end

IO.puts(Jason.encode!(%{passed: errors == [], validation_errors: errors}, pretty: true))
if errors != [], do: System.halt(1)
