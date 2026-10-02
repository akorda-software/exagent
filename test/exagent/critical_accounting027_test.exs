defmodule ExAgent.CriticalAccounting027Test do
  use ExUnit.Case, async: false
  alias ExAgent.{ExecutionScope, Message, RunError, Tool, UsageLimits}
  alias ExAgent.Message.{Part, Usage}

  defmodule SparseTerminalModel do
    @behaviour ExAgent.Model
    defstruct [:journal, :terminal_usage, terminal_mode: :response, index: 0]
    def system(_), do: "offline-review"
    def model_name(_), do: "cumulative-then-sparse"
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}

    def request(model, _, _, _) do
      Agent.update(model.journal, &Map.update!(&1, :requests, fn n -> n + 1 end))

      response =
        if model.index == 0 do
          Message.new_response(
            [%Part.ToolCall{tool_name: "effect", tool_call_id: "effect-1", args: %{}}],
            usage: model.terminal_usage
          )
        else
          Message.new_response([%Part.Text{content: "done"}],
            usage: %Usage{input_tokens: 0, output_tokens: 0}
          )
        end

      {:ok, response, %{model | index: model.index + 1}}
    end

    def request_stream(model, history, settings, params) do
      Stream.resource(
        fn ->
          {:ok, response, next} = request(model, history, settings, params)

          terminal =
            if model.terminal_mode == :error,
              do:
                {:error,
                 %ExAgent.RequestError{
                   provider: :offline_review,
                   reason: :synthetic_failure,
                   partial_response: response
                 }},
              else: {:response, response, next}

          if model.index == 0,
            do: [{:usage, %Usage{input_tokens: 1, output_tokens: 1}}, terminal],
            else: [{:response, response, next}]
        end,
        fn
          [] -> {:halt, []}
          [event | rest] -> {[event], rest}
        end,
        fn _ -> Agent.update(model.journal, &Map.update!(&1, :closed, fn n -> n + 1 end)) end
      )
    end
  end

  test "a non-nil sparse terminal must preserve the previously known estimated subtotal" do
    model = %ExAgent.Models.Test{}

    {:ok, scope} =
      ExecutionScope.start("sparse-terminal", model,
        usage_limits: limits(),
        estimate_cost: &price/1
      )

    on_exit(fn -> ExecutionScope.stop(scope) end)
    assert :ok = ExecutionScope.admit_request(scope, "request-1", model)

    assert :ok =
             ExecutionScope.record_usage(scope, "request-1", %Usage{
               input_tokens: 1,
               output_tokens: 1
             })

    assert {:ok, before} = ExecutionScope.snapshot(scope)
    assert before.usage.accounting["cost"]["subtotal_cents"] == 11.0

    assert :ok =
             ExecutionScope.record_usage(
               scope,
               "request-1",
               %Usage{input_tokens: nil, output_tokens: nil},
               true
             )

    assert :ok = ExecutionScope.finish_request(scope, "request-1")
    assert {:ok, after_terminal} = ExecutionScope.snapshot(scope)

    IO.puts(
      "CRITICAL027_LEDGER " <>
        Jason.encode!(%{
          before_subtotal: before.usage.accounting["cost"]["subtotal_cents"],
          after_subtotal: after_terminal.usage.accounting["cost"]["subtotal_cents"],
          after_cost_availability: after_terminal.usage.accounting["cost"]["availability"],
          request_count: after_terminal.request_count
        })
    )

    assert after_terminal.request_count == 1
    assert after_terminal.cost_cents == nil
    assert after_terminal.usage.accounting["cost"]["subtotal_cents"] == 11.0
    assert after_terminal.usage.accounting["cost"]["availability"] == "partial"

    assert {:error, {:usage_limit_exceeded, :budget_cents, 11.0}} =
             ExecutionScope.admit_tools(scope, "request-1", 1)
  end

  test "public stream sparse terminal cannot erase known budget usage and authorize an effect" do
    journal = start_supervised!({Agent, fn -> %{requests: 0, effects: 0, closed: 0} end})
    agent = agent(journal, %Usage{input_tokens: nil, output_tokens: nil})

    actual = ExAgent.run(agent, "go", stream_text: true, estimate_cost: &price/1)
    counts("sparse-terminal", actual, journal)

    assert {:error,
            %RunError{reason: {:usage_limit_exceeded, :budget_cents, 11.0}, partial: partial}} =
             actual

    assert partial.request_count == 1
    assert partial.tool_calls == 0
    assert partial.usage.accounting["cost"]["subtotal_cents"] == 11.0
    assert Agent.get(journal, & &1) == %{requests: 1, effects: 0, closed: 1}
  end

  test "a failed streamed delegate retains its already known price in the ancestor ledger" do
    journal =
      start_supervised!({Agent, fn -> %{requests: 0, effects: 0, closed: 0, subtotals: []} end})

    child =
      ExAgent.new(
        model: %SparseTerminalModel{
          journal: journal,
          terminal_usage: %Usage{input_tokens: nil, output_tokens: nil},
          terminal_mode: :error
        }
      )

    delegate =
      Tool.new(
        name: "delegate",
        takes_ctx: true,
        max_retries: 0,
        call: fn ctx, _ ->
          ExAgent.run_child(ctx, child, "child",
            stream_text: true,
            on_progress: fn partial ->
              subtotal = partial.usage.accounting["cost"]["subtotal_cents"]

              Agent.update(
                journal,
                &Map.update!(&1, :subtotals, fn seen -> [subtotal | seen] end)
              )
            end
          )
        end
      )

    parent_model = %ExAgent.Models.Test{
      script: [
        Message.new_response(
          [
            %Part.ToolCall{tool_name: "delegate", tool_call_id: "delegate-1", args: %{}}
          ],
          usage: %Usage{input_tokens: 0, output_tokens: 0}
        )
      ]
    }

    parent = ExAgent.new(model: parent_model, tools: [delegate], usage_limits: limits())

    actual = ExAgent.run(parent, "go", estimate_cost: fn _, usage -> price(usage) end)
    counts("failed-delegate", actual, journal)
    assert {:error, %RunError{partial: partial}} = actual
    assert partial.request_count == 2
    assert partial.tool_calls == 1
    assert partial.usage.accounting["cost"]["subtotal_cents"] == 11.0

    assert Agent.get(journal, &Map.take(&1, [:requests, :effects, :closed])) == %{
             requests: 1,
             effects: 0,
             closed: 1
           }

    assert 11.0 in Agent.get(journal, & &1.subtotals)
  end

  test "control: terminal nil retains known subtotal and already blocks the effect" do
    journal = start_supervised!({Agent, fn -> %{requests: 0, effects: 0, closed: 0} end})

    assert {:error,
            %RunError{reason: {:usage_limit_exceeded, :budget_cents, 11.0}, partial: partial}} =
             ExAgent.run(agent(journal, nil), "go", stream_text: true, estimate_cost: &price/1)

    assert partial.request_count == 1
    assert partial.tool_calls == 0
    assert Agent.get(journal, & &1) == %{requests: 1, effects: 0, closed: 1}
  end

  test "control: an explicit complete zero replaces an earlier snapshot rather than adding it" do
    journal = start_supervised!({Agent, fn -> %{requests: 0, effects: 0, closed: 0} end})

    assert {:ok, result} =
             ExAgent.run(agent(journal, %Usage{input_tokens: 0, output_tokens: 0}), "go",
               stream_text: true,
               estimate_cost: &price/1
             )

    assert result.request_count == 2
    assert result.tool_calls == 1
    assert result.usage.accounting["cost"]["subtotal_cents"] == 0.0
    assert Agent.get(journal, & &1) == %{requests: 2, effects: 1, closed: 2}
  end

  defp agent(journal, terminal_usage) do
    effect =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        call: fn _ ->
          Agent.update(journal, &Map.update!(&1, :effects, fn n -> n + 1 end))
          "saved"
        end
      )

    ExAgent.new(
      model: %SparseTerminalModel{journal: journal, terminal_usage: terminal_usage},
      tools: [effect],
      usage_limits: limits()
    )
  end

  defp limits,
    do: %UsageLimits{accounting: :estimated, request_limit: 3, max_budget_cents: 10}

  defp price(usage), do: (usage.input_tokens + usage.output_tokens) * 5.5

  defp counts(label, actual, journal) do
    {status, result} =
      case actual do
        {:ok, result} -> {:ok, result}
        {:error, %RunError{partial: result}} -> {:error, result}
      end

    IO.puts(
      "CRITICAL027_RESULT " <>
        Jason.encode!(%{
          case: label,
          status: status,
          counters: Agent.get(journal, & &1),
          request_count: result.request_count,
          tool_calls: result.tool_calls,
          cost: result.usage.accounting["cost"]
        })
    )
  end
end
