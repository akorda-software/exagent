defmodule ExAgent.ReqLLMOpenRouterRoutingTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Message, Model, ModelSettings, ModelRequestParameters, Tool}
  alias ExAgent.Models.ReqLLM, as: Adapter

  defp model(opts \\ []) do
    owner = self()
    counter = start_supervised!({Agent, fn -> 0 end}, id: make_ref())

    transport = fn request ->
      n = Agent.get_and_update(counter, &{&1, &1 + 1})
      send(owner, {:http, n, Jason.decode!(IO.iodata_to_binary(request.body))})

      message =
        if n == 0,
          do: %{
            "role" => "assistant",
            "tool_calls" => [
              %{
                "id" => "routed-call",
                "type" => "function",
                "function" => %{
                  "name" => "effect",
                  "arguments" => Jason.encode!(%{"arguments" => %{"value" => 7}})
                }
              }
            ]
          },
          else: %{"role" => "assistant", "content" => "done"}

      body = %{
        "id" => "fixture",
        "model" => "routed-fixture",
        "choices" => [
          %{
            "index" => 0,
            "message" => message,
            "finish_reason" => if(n == 0, do: "tool_calls", else: "stop")
          }
        ],
        "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
      }

      {request,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: Jason.encode!(body)
       )}
    end

    Adapter.new(
      Keyword.merge(
        [
          model: %{
            provider: :openrouter,
            id: "routed-fixture",
            capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
            extra: %{wire: %{protocol: "openai_chat"}}
          },
          api_key: "synthetic",
          base_url: "https://fixture.invalid/v1",
          tool_profile: :openrouter_chat_tools_v1,
          provider_options: [
            openrouter_provider: %{order: ["decart"], only: ["decart"], allow_fallbacks: false},
            app_title: "fixture"
          ],
          http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
        ],
        opts
      )
    )
  end

  defp tool do
    owner = self()

    Tool.new(
      name: "effect",
      parameters_json_schema: %{
        type: "object",
        properties: %{value: %{type: "integer"}},
        required: ["value"],
        additionalProperties: false
      },
      call: fn _ctx, args ->
        send(owner, {:effect, args})
        "receipt"
      end
    )
  end

  test "explicit stock OpenRouter routing survives the full envelope loop and tool history" do
    agent = ExAgent.new(model: model(), tools: [tool()], model_settings: [max_tokens: 200])
    assert {:ok, result} = ExAgent.run(agent, "go")
    assert result.output == "done" and result.request_count == 2
    assert_receive {:effect, %{"value" => 7}}
    refute_receive {:effect, _}, 0

    for n <- 0..1 do
      assert_receive {:http, ^n, body}

      assert body["provider"] == %{
               "order" => ["decart"],
               "only" => ["decart"],
               "allow_fallbacks" => false
             }

      assert body["model"] == "routed-fixture"

      assert body["tools"] |> hd() |> get_in(["function", "parameters", "required"]) == [
               "arguments"
             ]
    end

    assert Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages}
  end

  test "reasoning none routes without a duplicate budget or temperature" do
    m = model(reasoning_mode: :none)

    m =
      put_in(m.model.capabilities.reasoning, %{
        enabled: true,
        effort: %{supported: true, values: ["none"]},
        thinking: %{disable_supported: true}
      })

    assert {:ok, _} =
             ExAgent.run(
               ExAgent.new(model: m, tools: [tool()], model_settings: [max_tokens: 128]),
               "go"
             )

    assert_receive {:http, 0, body}
    assert body["reasoning_effort"] == "none"
    assert body["max_tokens"] == 128
    refute Map.has_key?(body, "max_completion_tokens")
    refute Map.has_key?(body, "temperature")
    assert {:ok, binding} = Model.continuation_binding(m)
    refute Jason.encode!(binding) =~ "synthetic"

    assert Model.continuation_binding(%{
             m
             | provider_options: [openrouter_provider: %{only: ["io-net"]}]
           }) != {:ok, binding}
  end

  test "ordinary routed executions bind routing before IO and reject rerouted history" do
    m = model()
    other = %{m | provider_options: [openrouter_provider: %{only: ["io-net"]}]}
    assert {:ok, binding} = Model.continuation_binding(m)
    assert is_map(binding)
    assert Model.continuation_binding(other) != {:ok, binding}
    refute Jason.encode!(binding) =~ "synthetic"

    assert {:ok, result} = ExAgent.run(ExAgent.new(model: m, tools: [tool()]), "go")
    for n <- 0..1, do: assert_receive({:http, ^n, _})
    assert_receive {:effect, _}
    assert Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages}

    assert {:error, %ExAgent.RequestError{reason: :continuation_routing_mismatch}} =
             Model.validate_resume(
               other,
               result.messages,
               %ModelSettings{},
               %ModelRequestParameters{function_tools: [tool()]}
             )

    refute_receive {:http, _, _}, 0
    refute_receive {:effect, _}, 0
  end

  test "old Chat and unqualified OpenRouter profiles remain closed" do
    for m <- [model(tool_profile: :chat_tools_v1), model(tool_profile: nil)] do
      assert {:error, _} =
               Model.request(m, [], %ModelSettings{}, %ModelRequestParameters{
                 function_tools: [tool()]
               })
    end

    native = model(output_profile: :chat_json_schema_v1)

    assert {:error, _} =
             Model.request(native, [], %ModelSettings{}, %ModelRequestParameters{
               output_mode: :native,
               output_object: %{json_schema: %{type: "object"}}
             })

    refute_receive {:http, _, _}, 0
    refute_receive {:effect, _}, 0
  end

  test "routing is bounded and cannot carry unrelated wire settings" do
    for options <- [
          [openrouter_provider: %{model: "other"}],
          [openrouter_provider: %{only: []}],
          [openrouter_provider: %{only: [1]}],
          [openrouter_provider: %{allow_fallbacks: "false"}],
          [openrouter_provider: %{only: List.duplicate("x", 33)}],
          [openrouter_provider: %{only: [String.duplicate("x", 129)]}],
          [openrouter_provider: %{only: ["decart"]}, reasoning_effort: :none],
          [openrouter_provider: %{only: ["decart"]}, store: true]
        ] do
      assert {:error, _} =
               Model.request(
                 model(provider_options: options),
                 [],
                 %ModelSettings{},
                 %ModelRequestParameters{function_tools: [tool()]}
               )
    end

    refute_receive {:http, _, _}, 0
  end
end
