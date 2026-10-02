defmodule ExAgent.ReqLLMSafetyTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Message, Model, ModelRequestParameters, Tool}
  alias ExAgent.Models.ReqLLM, as: Adapter
  alias Message.Part

  defp spec(provider \\ :openai),
    do: %{
      provider: provider,
      id: "safety-fixture",
      capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
    }

  defp model(bodies, opts \\ []) do
    owner = self()
    counter = start_supervised!({Agent, fn -> 0 end}, id: make_ref())

    transport = fn req ->
      index = Agent.get_and_update(counter, &{&1, &1 + 1})
      send(owner, {:request, index})

      {req,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: Jason.encode!(Enum.fetch!(bodies, index))
       )}
    end

    Adapter.new(
      Keyword.merge(
        [
          model: spec(),
          api_key: "synthetic",
          base_url: "https://fixture.invalid/v1",
          http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
        ],
        opts
      )
    )
  end

  defp reply(arguments) do
    %{
      "id" => "safety",
      "model" => "safety-fixture",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              %{
                "id" => "call-1",
                "type" => "function",
                "function" => %{"name" => "effect", "arguments" => arguments}
              }
            ]
          },
          "finish_reason" => "tool_calls"
        }
      ]
    }
  end

  defp final,
    do: %{
      "id" => "safety",
      "model" => "safety-fixture",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{"role" => "assistant", "content" => "done"},
          "finish_reason" => "stop"
        }
      ]
    }

  defp tool do
    owner = self()

    Tool.new(
      name: "effect",
      description: "Synthetic effect",
      takes_ctx: false,
      parameters_json_schema: %{"type" => "object", "additionalProperties" => false},
      call: fn args ->
        send(owner, {:effect, args})
        "ok"
      end
    )
  end

  defp stock(model) do
    ReqLLM.generate_text(model.model, "synthetic",
      api_key: model.api_key,
      base_url: model.base_url,
      max_retries: 0,
      req_http_options: model.http_options
    )
  end

  # Stock-version tripwire, not the desired contract: when upstream preserves
  # identity, replace this characterization and reconsider the admission guard.
  @tag :req_llm_characterization
  test "stock loses array versus object argument identity before public host boundary" do
    m = model([reply("[]"), reply("{}")])
    assert {:ok, array} = stock(m)
    assert {:ok, object} = stock(m)
    assert [a] = ReqLLM.Response.tool_calls(array)
    assert [b] = ReqLLM.Response.tool_calls(object)
    assert a.function.arguments == "{}"
    assert b.function.arguments == "{}"
    assert ReqLLM.ToolCall.metadata(a) == %{}
    assert ReqLLM.ToolCall.metadata(b) == %{}
  end

  test "non-object stock tool arguments cannot trigger an empty-object-compatible effect" do
    m = model([reply("[]"), final()])
    assert {:error, _} = ExAgent.run(ExAgent.new(model: m, tools: [tool()]), "go")
    refute_receive {:effect, _}, 0
    refute_receive {:request, _}, 0
  end

  test "even a valid stock object tool path is unavailable until argument provenance is faithful" do
    m = model([reply("{}"), final()])
    assert {:error, _} = ExAgent.run(ExAgent.new(model: m, tools: [tool()]), "go")
    refute_receive {:effect, _}, 0
    refute_receive {:request, _}, 0

    assert {:error, _} =
             Model.request(
               m,
               [
                 Message.new_response([
                   %Part.ToolCall{tool_name: "effect", tool_call_id: "call-1", args: "{}"}
                 ])
               ],
               nil,
               %ModelRequestParameters{}
             )

    refute_receive {:request, _}, 0
  end

  test "disabled reasoning is not advertised as supported thinking" do
    m = model([])
    refute Model.profile(m).supports_thinking

    enabled = %{
      m
      | model:
          Map.put(m.model, :capabilities, %{
            reasoning: %{enabled: true, thinking: %{supported: true}}
          })
    }

    assert Model.profile(enabled).supports_thinking

    disabled = %{
      m
      | model:
          Map.put(m.model, :capabilities, %{
            reasoning: %{enabled: true, thinking: %{supported: false}}
          })
    }

    refute Model.profile(disabled).supports_thinking
    anthropic = %{enabled | model: Map.put(enabled.model, :provider, :anthropic)}
    refute Model.profile(anthropic).supports_thinking
    assert {:error, _} = Model.request(anthropic, [], nil, %ModelRequestParameters{})
    refute_receive {:request, _}, 0
  end

  test "custom Model validation still rejects arrays and accepts valid empty objects" do
    for {args, effect?} <- [{"[]", false}, {"{}", true}] do
      call = %Part.ToolCall{tool_name: "effect", tool_call_id: "call-1", args: args}
      m = %ExAgent.Models.Test{script: [{:tool_calls, [call]}, "done"]}
      assert {:ok, _} = ExAgent.run(ExAgent.new(model: m, tools: [tool()]), "go")
      if effect?, do: assert_receive({:effect, %{}}), else: refute_receive({:effect, _}, 0)
    end
  end

  @tag :req_llm_characterization
  test "stock Anthropic loses redacted reasoning, so thinking requests must reject before IO" do
    body = %{
      "id" => "redacted",
      "type" => "message",
      "role" => "assistant",
      "model" => "safety-fixture",
      "content" => [
        %{"type" => "redacted_thinking", "data" => "opaque-redacted-block"},
        %{"type" => "text", "text" => "done"}
      ],
      "stop_reason" => "end_turn",
      "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
    }

    m = model([body, body], model: spec(:anthropic))
    assert {:ok, stock} = stock(m)
    refute Jason.encode!(stock) =~ "opaque-redacted-block"
    assert_receive {:request, 0}
    m = %{m | provider_options: [thinking: %{type: "enabled", budget_tokens: 1024}]}

    assert {:error, _} =
             Model.request(
               m,
               [Message.new_request([%Part.User{content: "go"}])],
               nil,
               %ModelRequestParameters{}
             )

    refute_receive {:request, _}, 0
  end
end
