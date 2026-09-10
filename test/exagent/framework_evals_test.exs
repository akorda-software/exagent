Code.require_file("../../examples/framework_scenarios.exs", __DIR__)

defmodule ExAgent.FrameworkEvalsTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  alias ExAgent.FrameworkScenarios, as: Scenarios

  test "typed reading traverses the delegate and persists the checked answer" do
    report = Scenarios.reading_eval()
    assert report.passed, inspect(report.criteria)
    assert report.evidence.output == %{total: 29, count: 4}
    assert report.evidence.observed.requests == 5
    assert report.evidence.ledger.cost_cents == 0.25
  end

  test "effect survives failed request and checkpoint-only recovery without replay" do
    report = Scenarios.effect_eval()
    assert report.passed, inspect(report.criteria)
    assert report.evidence.observed.effects == 1
    assert report.evidence.observed.requests == 6
    assert report.evidence.save_attempts == 2
    assert report.evidence.ledger.cost_cents == nil
  end

  test "negative fixtures exercise live effect wiring, inherited deny, JSV and Ecto" do
    report = Scenarios.negative_controls()
    assert report.passed, inspect(report.criteria)
    assert report.evidence.wiring_control_effects == 1
    assert report.evidence.unauthorized_effects_under_policy == 0
  end

  test "answers depend on tool data and the load oracle rejects incorrect output and double usage" do
    for kind <- [:tools, :delegation] do
      definition = Scenarios.definition(kind, values: [2, 7, 11])
      assert {:ok, result} = Scenarios.execute(definition)
      assert result.output == %Scenarios.Reading{total: 20, count: 3}
      assert Scenarios.correct?(definition, {:ok, result})

      refute Scenarios.correct?(
               definition,
               {:ok, %{result | output: %Scenarios.Reading{total: 29, count: 4}}}
             )

      refute Scenarios.correct?(
               definition,
               {:ok, %{result | request_count: result.request_count * 2}}
             )

      refute Scenarios.correct?(
               definition,
               {:ok,
                %{result | usage: %{result.usage | input_tokens: result.usage.input_tokens * 2}}}
             )
    end
  end
end
