defmodule ExAgent.FlowRuntimeFixture do
  alias ExAgent.Coordination.Flow
  alias ExAgent.DelegationRuntimeFixture

  defmodule FatalAfter do
    use ExAgent.Capability
    defstruct []
    def after_tool_execute(_, _, _, _), do: raise("confirmed A wrapper failure")
  end

  def host(path, fresh? \\ false) do
    {sequence, catalog} = DelegationRuntimeFixture.host(path, fresh?)
    [a | rest] = sequence.steps
    a = %{a | agent: %{a.agent | capabilities: a.agent.capabilities ++ [%FatalAfter{}]}}

    {:ok, flow} =
      Flow.new(
        id: "flow-vm",
        version: "1",
        kind: :parallel,
        max_concurrency: 3,
        failure_policy: :collect,
        branches: [a | rest]
      )

    {flow, catalog}
  end
end
