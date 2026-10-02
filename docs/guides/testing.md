# Test your integration

Use TestModel for deterministic application tests. Reserve provider, database and
tracing acceptance for the profiles that actually need those systems. A passing
offline test establishes your local behavior; it does not establish a backend's
wire compatibility.

## Assert on the public result

```elixir
defmodule DocumentationAgentTest do
  use ExUnit.Case, async: true

  test "returns the validated final output" do
    agent = ExAgent.new(model: %ExAgent.Models.Test{label: "Ready"})
    assert {:ok, result} = ExAgent.run(agent, "Start")
    assert result.status == :succeeded
    assert result.output == "Ready"
    assert result.request_count == 1
  end
end
```

This is an application test: put it in your app's `test/` directory and run
`mix test`. The model never accesses the network. Use `script:` for sequential
responses, `{:tool_calls, calls}` for tool invocation, and a function
`fn messages, params -> response end` when you need to inspect the actual request.

## Make effects observable

For a tool, inject a dependency that records invocations or sends a message to
the test owner. Assert on the actual arguments, number of effects and result,
including failure paths. [Tools and output](tools-and-output.md) contains a
scripted two-request tool run you can adapt.

Useful cases include invalid arguments before an effect, a provider failure
after an effect, budget exhaustion, cancellation, a checkpoint failure and a
duplicate approval/job wake-up. Avoid using elapsed sleeps as proof of ordering;
make the relevant admission or effect boundary observable.

## Run the package's local routine

When contributing to **this repository**, run the complete local gate before
committing or pushing a runtime change:

```bash
bin/check
```

It runs format, strict compilation and finite probes, the complete offline suite,
ExDoc and TAR/isolation checks. `bin/check --package-consumers` adds clean package
consumer graphs. Tooling setup and exact commands are in
[Verification](../development/verification.md) and
[Environment](../development/environment.md). Do not change global Hex settings
to repair a project-local tool problem.

For a documentation-only change, use the documentation gate described below;
the accepted full runtime suite does not need a routine rerun. GitHub's six-job
compatibility workflow is manual on the candidate branch and becomes manual on
`main` when the PR is integrated. It is retained for explicit compatibility runs.

## Read exclusions correctly

The accepted offline suite has **2,176 passes, zero failures and 28 excluded tests**:

| Filter | Cases | Why excluded offline |
|---|---|---|
| `integration` | 22 | Real-provider chat/tools/stream/structured-output requests. |
| `postgres` | 6 | A real database is required. |

An excluded test's body does not run. It is not a passing test, a timeout or a
measurement of external compatibility. A timeout in a selected test is a failure.
Real acceptance is recorded separately in [Support status](../status.md).

## Check documentation examples

The repository's `test/support/documentation_probe.exs` selects the actual
Markdown codeblocks and executes their local contracts in a disposable VM:

```bash
EXAGENT_OFFLINE=1 elixir -pa '_build/test/lib/*/ebin' test/support/documentation_probe.exs
```

Compile the checkout first using the local environment guide. Setup blocks for
credentials, configuration and external dependencies are explicitly parsed or
resolved without external IO; they are not counted as live acceptance. New
task-guide examples are exercised by the same probe. Build the site with
`mix docs --warnings-as-errors` and inspect the generated pages and links.

API: `ExAgent.Models.Test`,
`ExAgent.RunError`.
