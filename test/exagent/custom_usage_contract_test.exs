defmodule ExAgent.CustomUsageContractTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Message, RunError, Tool, UsageLimits}
  alias ExAgent.Message.{Part, Usage}

  for mode <- [:sync, :stream_text, :public_stream] do
    test "custom #{mode} preserves partial reported dimensions before budgeted effects" do
      for {input, output} <- [{7, nil}, {nil, 3}, {nil, nil}] do
        journal = start_supervised!({Agent, fn -> [] end}, id: make_ref())
        usage = %Usage{input_tokens: input, output_tokens: output}
        assert {:error, %RunError{partial: result}} = run(usage, journal, unquote(mode))
        assert result.usage_status == :partial
        assert result.cost_status == :unknown
        assert result.cost_cents == nil
        assert {result.usage.input_tokens, result.usage.output_tokens} == {input, output}
        assert result.usage.accounting["quality"] == "reported"
        assert result.usage.accounting["provider_presence"] == "unknown"
        assert result.request_count == 1
        assert result.tool_calls == 0

        assert [%Part.ToolReturn{status: :not_executed, tool_call_id: "effect-1"}] =
                 returns(result)

        assert Agent.get(journal, & &1) == [:request]
      end
    end
  end

  test "custom complete and explicit zero reported usage admit exactly one effect in all modes" do
    for mode <- [:sync, :stream_text, :public_stream], {input, output} <- [{7, 3}, {0, 0}] do
      journal = start_supervised!({Agent, fn -> [] end}, id: make_ref())

      assert {:ok, result} =
               run(%Usage{input_tokens: input, output_tokens: output}, journal, mode)

      assert result.output == "done"
      assert result.usage_status == :complete
      assert result.cost_status == :known
      assert result.cost_cents == input + output
      assert {result.usage.input_tokens, result.usage.output_tokens} == {input, output}
      assert result.request_count == 2
      assert result.tool_calls == 1
      assert [%Part.ToolReturn{status: :succeeded, content: "saved"}] = returns(result)
      assert Agent.get(journal, &Enum.reverse/1) == [:request, :effect, :request]
    end
  end

  defp run(usage, journal, mode) do
    model = %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          Agent.update(journal, &[:request | &1])

          Message.new_response(
            [%Part.ToolCall{tool_name: "effect", tool_call_id: "effect-1", args: %{}}],
            usage: usage
          )
        end,
        fn _, _ ->
          Agent.update(journal, &[:request | &1])

          Message.new_response([%Part.Text{content: "done"}],
            usage: %Usage{input_tokens: 0, output_tokens: 0}
          )
        end
      ]
    }

    tool =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        call: fn _ ->
          Agent.update(journal, &[:effect | &1])
          "saved"
        end
      )

    agent =
      ExAgent.new(model: model, tools: [tool], usage_limits: %UsageLimits{max_budget_cents: 100})

    opts = [estimate_cost: fn _, u -> u.input_tokens + u.output_tokens end]

    case mode do
      :sync ->
        ExAgent.run(agent, "go", opts)

      :stream_text ->
        ExAgent.run(agent, "go", opts ++ [stream_text: true])

      :public_stream ->
        case Enum.to_list(ExAgent.run_stream(agent, "go", opts)) do
          [{:delta, "done"}, {:result, result}] -> {:ok, result}
          [{:error, %RunError{}} = error] -> error
        end
    end
  end

  defp returns(result) do
    for %Message.Request{parts: parts} <- result.messages,
        %Part.ToolReturn{} = part <- parts,
        do: part
  end
end
