defmodule ExAgent.ProviderUsageContractTest do
  # Req's injected adapter is VM-wide; each test restores it before other tests run.
  use ExUnit.Case, async: false

  alias ExAgent.{Message, RunError, Tool, UsageLimits}
  alias ExAgent.Message.{Part, Usage}
  alias ExAgent.Models.{Anthropic, OpenAI}

  setup do
    previous = Req.default_options()
    on_exit(fn -> Req.default_options(previous) end)
    %{journal: start_supervised!({Agent, fn -> [] end})}
  end

  for provider <- [:openai, :anthropic], mode <- [:sync, :stream_text, :public_stream] do
    @tag provider: provider, mode: mode
    test "#{provider} #{mode} keeps incomplete usage unknown before further budgeted effects",
         c do
      for {reported, subtotal} <- [
            {%{input: 7}, {7, 0}},
            {%{output: 3}, {0, 3}},
            {%{input: 7, output: nil}, {7, 0}},
            {%{input: nil, output: 3}, {0, 3}},
            {%{}, {0, 0}},
            {nil, {0, 0}}
          ] do
        install(c.provider, reported, c.journal)
        agent = agent(c.provider, c.journal)

        assert {:error, %RunError{partial: result}} = run(agent, c.mode)
        assert result.usage_status == :partial
        assert result.cost_status == :unknown
        assert result.cost_cents == nil
        assert {result.usage.input_tokens, result.usage.output_tokens} == subtotal
        assert result.request_count == 1
        assert result.tool_calls == 0

        assert [%Part.ToolReturn{status: :not_executed, tool_call_id: "effect-1"}] =
                 returns(result)

        assert Agent.get(c.journal, & &1) == [:request]
      end
    end
  end

  test "complete usage and explicit zero admit the same effect in all three modes", c do
    for provider <- [:openai, :anthropic],
        mode <- [:sync, :stream_text, :public_stream],
        reported <- [%{input: 7, output: 3}, %{input: 0, output: 0}] do
      install(provider, reported, c.journal)
      assert {:ok, result} = run(agent(provider, c.journal), mode)
      assert result.output == "done"
      assert result.usage_status == :complete
      assert result.cost_status == :known
      assert result.cost_cents == reported.input + reported.output

      assert {result.usage.input_tokens, result.usage.output_tokens} ==
               {reported.input, reported.output}

      assert result.request_count == 2
      assert result.tool_calls == 1
      assert [%Part.ToolReturn{status: :succeeded, content: "saved"}] = returns(result)
      assert Agent.get(c.journal, &Enum.reverse/1) == [:request, :effect, :request]
    end
  end

  test "parser dimensions remain nil rather than inferred from total or cache details" do
    openai =
      ExAgent.Providers.OpenAIChat.parse_response(
        %{
          "choices" => [],
          "usage" => %{"total_tokens" => 10, "prompt_tokens_details" => %{"cached_tokens" => 7}}
        },
        %ExAgent.Providers.OpenAIChat.Config{system: "openai"}
      )

    assert %Usage{
             input_tokens: nil,
             output_tokens: nil,
             details: %{"total_tokens" => 10, "cached_tokens" => 7}
           } = openai.usage

    anthropic =
      ExAgent.Providers.Anthropic.parse_response(
        %{
          "content" => [],
          "usage" => %{"cache_read_input_tokens" => 7, "cache_creation_input_tokens" => 3}
        },
        %ExAgent.Providers.Anthropic.Config{system: "anthropic"}
      )

    assert %Usage{
             input_tokens: nil,
             output_tokens: nil,
             details: %{"cache_read_input_tokens" => 7, "cache_creation_input_tokens" => 3}
           } = anthropic.usage
  end

  defp agent(provider, journal) do
    model =
      case provider do
        :openai ->
          %OpenAI{model: "offline", api_key: "offline", base_url: "http://unused.invalid"}

        :anthropic ->
          %Anthropic{model: "offline", api_key: "offline", base_url: "http://unused.invalid"}
      end

    tool =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        call: fn _ ->
          Agent.update(journal, &[:effect | &1])
          "saved"
        end
      )

    ExAgent.new(model: model, tools: [tool], usage_limits: %UsageLimits{max_budget_cents: 100})
  end

  defp run(agent, mode) do
    opts = [estimate_cost: fn _, usage -> usage.input_tokens + usage.output_tokens end]

    case mode do
      :sync ->
        ExAgent.run(agent, "go", opts)

      :stream_text ->
        ExAgent.run(agent, "go", opts ++ [stream_text: true])

      :public_stream ->
        # Tool-only first responses produce no deltas; keep the complete event
        # list so another terminal or an unexpected preview cannot hide a failure.
        case Enum.to_list(ExAgent.run_stream(agent, "go", opts)) do
          [{:delta, "done"}, {:result, result}] -> {:ok, result}
          [{:error, %RunError{}} = error] -> error
        end
    end
  end

  defp install(provider, reported, journal) do
    Agent.update(journal, fn _ -> [] end)

    Req.default_options(
      adapter: fn request ->
        Agent.update(journal, &[:request | &1])
        body = Jason.decode!(request.body)
        final? = Enum.any?(body["messages"], &(&1["role"] == "assistant"))
        usage = wire_usage(provider, if(final?, do: %{input: 0, output: 0}, else: reported))
        {response, events} = reply(provider, usage, final?)

        if body["stream"] do
          Enum.reduce_while(events, {request, Req.Response.new(status: 200)}, fn event, acc ->
            data = if event == :done, do: "[DONE]", else: Jason.encode!(event)
            request.into.({:data, "data: " <> data <> "\n\n"}, acc)
          end)
        else
          {request, Req.Response.new(status: 200, body: response)}
        end
      end
    )
  end

  defp wire_usage(_, nil), do: nil

  defp wire_usage(provider, reported) do
    keys =
      if provider == :openai,
        do: %{input: "prompt_tokens", output: "completion_tokens"},
        else: %{input: "input_tokens", output: "output_tokens"}

    Map.new(reported, fn {key, value} -> {Map.fetch!(keys, key), value} end)
  end

  defp reply(:openai, usage, final?) do
    message =
      if final?,
        do: %{"content" => "done"},
        else: %{
          "tool_calls" => [
            %{
              "id" => "effect-1",
              "type" => "function",
              "function" => %{"name" => "effect", "arguments" => "{}"}
            }
          ]
        }

    delta =
      if final?,
        do: message,
        else:
          Map.update!(
            message,
            "tool_calls",
            &Enum.map(&1, fn call -> Map.put(call, "index", 0) end)
          )

    finish = if final?, do: "stop", else: "tool_calls"

    response = %{
      "model" => "offline",
      "choices" => [%{"message" => message, "finish_reason" => finish}],
      "usage" => usage
    }

    events = [
      %{
        "model" => "offline",
        "choices" => [%{"delta" => delta, "finish_reason" => finish}],
        "usage" => usage
      },
      :done
    ]

    {response, events}
  end

  defp reply(:anthropic, usage, final?) do
    block =
      if final?,
        do: %{"type" => "text", "text" => "done"},
        else: %{"type" => "tool_use", "id" => "effect-1", "name" => "effect", "input" => %{}}

    finish = if final?, do: "end_turn", else: "tool_use"

    response = %{
      "model" => "offline",
      "content" => [block],
      "stop_reason" => finish,
      "usage" => usage
    }

    events = [
      %{"type" => "message_start", "message" => %{"model" => "offline", "usage" => usage}},
      %{"type" => "content_block_start", "index" => 0, "content_block" => block},
      %{"type" => "content_block_stop", "index" => 0},
      %{"type" => "message_delta", "delta" => %{"stop_reason" => finish}},
      %{"type" => "message_stop"}
    ]

    {response, events}
  end

  defp returns(result),
    do: for(%Part.ToolReturn{} = part <- Message.parts(result.messages), do: part)
end
