defmodule ExAgent.OnMaxStepsTest do
  use ExUnit.Case, async: true

  alias ExAgent.Message.{Part, Request}
  alias ExAgent.Models.Test
  alias ExAgent.Tool

  defp lookup(owner) do
    Tool.new(
      name: "lookup",
      parameters_json_schema: %{"type" => "object", "properties" => %{}},
      call: fn _ctx, _args ->
        send(owner, :tool_ran)
        "data"
      end
    )
  end

  defp call, do: {:tool_calls, [%Part.ToolCall{tool_name: "lookup", args: %{}}]}

  defp observe(owner, item) do
    fn messages, params ->
      send(owner, {:request, params.final_step, List.last(messages)})
      item
    end
  end

  test "the last allowed step asks for a final answer without keeping the notice" do
    agent =
      ExAgent.new(
        model: %Test{script: [observe(self(), call()), observe(self(), "answer")]},
        tools: [lookup(self())],
        max_steps: 2,
        on_max_steps: :final
      )

    assert {:ok, %{output: "answer", run_step: 2} = result} = ExAgent.run(agent, "go")
    assert_receive {:request, false, %Request{parts: [%Part.User{}]}}
    assert_receive :tool_ran

    assert_receive {:request, true, %Request{parts: [%Part.User{content: "The step limit" <> _}]}}

    refute Enum.any?(result.messages, fn message ->
             match?(%Request{parts: [%Part.User{content: "The step limit" <> _}]}, message)
           end)
  end

  test "a function call in the final step is not executed" do
    agent =
      ExAgent.new(
        model: %Test{script: [call(), call()]},
        tools: [lookup(self())],
        max_steps: 2,
        on_max_steps: :final
      )

    assert {:error, %ExAgent.RunError{reason: {:max_steps_exceeded, 2}, partial: partial}} =
             ExAgent.run(agent, "go")

    assert_receive :tool_ran
    refute_receive :tool_ran, 0
    assert partial.tool_calls == 1

    # The unexecuted call is answered so the history stays replayable.
    assert %Request{parts: [%Part.ToolReturn{status: :not_executed}]} =
             List.last(partial.messages)
  end

  defmodule FinalProbe do
    use ExAgent.Capability
    defstruct [:owner]

    @impl true
    def before_model_request(%__MODULE__{owner: owner}, state) do
      send(owner, {:capability_sees, state.params.final_step})
      state
    end
  end

  test "capabilities see the final step before the request" do
    agent =
      ExAgent.new(
        model: %Test{script: [call(), "answer"]},
        tools: [lookup(self())],
        capabilities: [%FinalProbe{owner: self()}],
        max_steps: 2,
        on_max_steps: :final
      )

    assert {:ok, %{output: "answer"}} = ExAgent.run(agent, "go")
    assert_receive {:capability_sees, false}
    assert_receive {:capability_sees, true}
  end

  test "the default keeps failing without a final request" do
    agent =
      ExAgent.new(
        model: %Test{script: [observe(self(), call())]},
        tools: [lookup(self())],
        max_steps: 1
      )

    assert agent.on_max_steps == :error

    assert {:error, %ExAgent.RunError{reason: {:max_steps_exceeded, 1}}} =
             ExAgent.run(agent, "go")

    assert_receive {:request, false, _}
    assert_receive :tool_ran
  end

  test "invalid values are rejected when building the agent" do
    assert_raise ArgumentError, ~r/on_max_steps/, fn ->
      ExAgent.new(model: "test", on_max_steps: :summarize)
    end
  end
end
