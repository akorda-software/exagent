defmodule ExAgent.ReqLLMModelTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Message, Model, ModelRequestParameters, ModelSettings, RequestError, Tool}
  alias ExAgent.Message.Part
  alias ExAgent.Models.ReqLLM, as: Adapter

  defmodule TypedOutput do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:value, :string)
    end

    def changeset(data, attrs), do: data |> cast(attrs, [:value]) |> validate_required([:value])
  end

  defp spec(provider \\ :openai) do
    %{
      provider: provider,
      id: "exagent-fixture",
      capabilities: %{tools: %{enabled: true}},
      modalities: %{input: [:text, :image], output: [:text]}
    }
  end

  defp model(responses, opts \\ []) do
    counter = start_supervised!({Agent, fn -> 0 end}, id: make_ref())
    owner = self()

    adapter = fn request ->
      index = Agent.get_and_update(counter, &{&1, &1 + 1})
      send(owner, {:http, index, request, Jason.decode!(IO.iodata_to_binary(request.body))})
      {status, body} = Enum.fetch!(responses, index)

      {request,
       Req.Response.new(
         status: status,
         headers: [{"content-type", "application/json"}],
         body: Jason.encode!(body)
       )}
    end

    Adapter.new(
      Keyword.merge(
        [
          model: spec(),
          api_key: "synthetic-key",
          base_url: "https://fixture.invalid/v1",
          http_options: [adapter: ExAgent.Test.ReqTransport.bind(adapter)]
        ],
        opts
      )
    )
  end

  defp chat(message, finish \\ "stop") do
    {200,
     %{
       "id" => "response-id",
       "model" => "exagent-fixture",
       "choices" => [%{"index" => 0, "message" => message, "finish_reason" => finish}],
       "usage" => %{"prompt_tokens" => 9, "completion_tokens" => 2, "total_tokens" => 11}
     }}
  end

  defp text(value), do: chat(%{"role" => "assistant", "content" => value})

  defp tool_call(id, args \\ ~s({"id":"safe"})),
    do: %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => "lookup", "arguments" => args}
    }

  defp request(content \\ "hello"), do: Message.new_request([%Part.User{content: content}])
  defp params, do: %ModelRequestParameters{}

  defp tool(owner),
    do:
      Tool.new(
        name: "lookup",
        description: "Synthetic effect",
        takes_ctx: false,
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"id" => %{"type" => "string"}},
          "required" => ["id"]
        },
        call: fn args ->
          send(owner, {:effect, args})
          %{"found" => args["id"]}
        end
      )

  test "Model dispatch uses explicit model/gateway, settings, finish reason and normalized usage" do
    model = model([text("ok")])

    assert {:ok, response, ^model} =
             Model.request(model, [request()], %ModelSettings{temperature: 0.2}, params())

    assert Message.Response.text(response) == "ok"
    assert response.finish_reason == :stop
    assert response.usage.accounting["quality"] == "normalized"
    assert response.usage.accounting["provider_presence"] == "unknown"
    assert response.continuation["provider"] == "openai"
    assert_receive {:http, 0, wire, body}
    assert body["temperature"] == 0.2
    assert body["model"] == "exagent-fixture"
    assert wire.url.host == "fixture.invalid"
    assert Req.Request.get_header(wire, "authorization") == ["Bearer synthetic-key"]
    refute inspect(response) =~ "synthetic-key"

    assert [{:error, {:unsupported, :streaming}}] =
             Enum.to_list(Model.request_stream(model, [], nil, params()))

    refute_receive {:http, _, _, _}, 0
  end

  test "stock cache read/write aliases remain distinct without double-counting input or reasoning" do
    {status, body} = text("cached response")

    body =
      Map.put(body, "usage", %{
        "prompt_tokens" => 10,
        "completion_tokens" => 2,
        "total_tokens" => 12,
        "prompt_tokens_details" => %{"cached_tokens" => 3, "cache_write_tokens" => 2},
        "completion_tokens_details" => %{"reasoning_tokens" => 1}
      })

    model = model([{status, body}, {status, body}])

    assert {:ok, stock} =
             ReqLLM.generate_text(model.model, "hello",
               api_key: model.api_key,
               base_url: model.base_url,
               max_retries: 0,
               req_http_options: model.http_options
             )

    public = ReqLLM.Response.usage(stock)
    assert public.cached_tokens == 3
    assert public.cache_creation_tokens == 2
    normalized = ReqLLM.Usage.normalize(public)
    assert normalized.cache_read_tokens == public.cached_tokens
    assert normalized.cache_write_tokens == public.cache_creation_tokens

    assert {:ok, response, _} = Model.request(model, [request()], nil, params())
    assert {response.usage.input_tokens, response.usage.output_tokens} == {10, 2}
    assert response.usage.details["cached_tokens"] == 3
    assert response.usage.details["cache_creation_input_tokens"] == 2
    assert response.usage.details["reasoning_tokens"] == 1
    assert response.usage.accounting["quality"] == "normalized"
    assert response.usage.accounting["provider_presence"] == "unknown"
    assert_receive {:http, 0, _, _}
    assert_receive {:http, 1, _, _}
    refute_receive {:http, _, _, _}, 0
  end

  test "run rejects tool batches before IO until stock argument fidelity is available" do
    first =
      chat(
        %{
          "role" => "assistant",
          "content" => nil,
          "tool_calls" => [tool_call("call-a"), tool_call("call-b")]
        },
        "tool_calls"
      )

    model = model([first, text("finished")])
    agent = ExAgent.new(model: model, tools: [tool(self())])
    assert {:error, _} = ExAgent.run(agent, "lookup twice")
    refute_receive {:effect, _}, 0
    refute_receive {:http, _, _, _}, 0
  end

  test "HTTP failure returns a sanitized error without hidden retries" do
    model = model([{429, %{"error" => %{"message" => "synthetic-key must not escape"}}}])

    assert {:error, %ExAgent.RunError{} = error} =
             ExAgent.run(ExAgent.new(model: model), "go")

    assert_receive {:http, 0, _, _}
    refute_receive {:effect, _}, 0
    refute_receive {:http, _, _, _}, 0
    refute inspect(error.reason) =~ "synthetic-key"
    assert error.partial.status == :failed
  end

  test "Ecto tool output is rejected before IO on the unsafe stock tool path" do
    final = %{
      "id" => "output-1",
      "type" => "function",
      "function" => %{"name" => "final_result", "arguments" => ~s({"value":"typed"})}
    }

    model =
      model([
        chat(%{"role" => "assistant", "content" => nil, "tool_calls" => [final]}, "tool_calls")
      ])

    assert {:error, _} =
             ExAgent.run(ExAgent.new(model: model, output: TypedOutput), "typed please")

    refute_receive {:http, _, _, _}, 0
  end

  test "truncated tool response cannot execute an effect" do
    model =
      model([
        chat(
          %{"role" => "assistant", "content" => nil, "tool_calls" => [tool_call("incomplete")]},
          "length"
        )
      ])

    assert {:error, %ExAgent.RunError{}} =
             ExAgent.run(ExAgent.new(model: model), "go")

    assert_receive {:http, 0, _, _}
    refute_receive {:effect, _}, 0
    refute_receive {:http, _, _, _}, 0
  end

  test "normalized usage can be estimated without claiming observed tokens or a free invoice" do
    agent = ExAgent.new(model: model([text("done")]))

    assert {:ok, result} =
             ExAgent.run(agent, "go",
               estimate_cost:
                 ExAgent.CostGuard.estimator(%{input_per_1k_cents: 1, output_per_1k_cents: 1})
             )

    assert_receive {:http, 0, _, _}
    assert result.usage_status == :complete
    assert result.usage.accounting["quality"] == "normalized"
    assert result.usage.accounting["provider_presence"] == "unknown"
    assert result.cost_status == :known
    assert is_number(result.cost_cents)
    assert result.usage.accounting["cost"]["quality"] == "estimated"
    assert result.usage.accounting["cost"]["source"] == "estimator"
    refute_receive {:effect, _}, 0
  end

  test "unsupported or reserved options and modalities reject before transport" do
    model = model([])

    for settings <- [
          %ModelSettings{extra: %{"api_key" => "override"}},
          %ModelSettings{extra: %{"tools" => []}}
        ] do
      assert {:error, %RequestError{}} = Model.request(model, [request()], settings, params())
    end

    for content <- [
          [%{"type" => "video_url", "url" => "https://fixture.invalid/video"}],
          [%{"type" => "file", "data" => "secret"}]
        ] do
      assert {:error, %RequestError{reason: {:unsupported, :input_content}}} =
               Model.request(model, [request(content)], nil, params())
    end

    assert {:error, %RequestError{}} =
             Model.request(
               %{model | http_options: [auth: {:bearer, "override"}]},
               [],
               nil,
               params()
             )

    refute_receive {:http, _, _, _}, 0
  end

  test "image input stays portable and undeclared image support rejects before IO" do
    image = %{
      "type" => "image",
      "data" => Base.encode64(<<1, 2, 3>>),
      "media_type" => "image/png"
    }

    history = [request([%{"type" => "text", "text" => "describe"}, image])]
    assert {:ok, ^history} = history |> Message.to_json() |> Message.from_json()
    model = model([text("image seen")])
    assert {:ok, _, _} = Model.request(model, history, nil, params())
    assert_receive {:http, 0, _, body}

    assert [
             %{
               "content" => [
                 %{"type" => "text"},
                 %{"type" => "image_url", "image_url" => %{"url" => url}}
               ]
             }
           ] = body["messages"]

    assert url == "data:image/png;base64,AQID"
    no_image = %{model | model: %{spec() | modalities: %{input: [:text], output: [:text]}}}

    assert {:error, %RequestError{reason: {:unsupported, :image_input}}} =
             Model.request(no_image, history, nil, params())

    refute_receive {:http, _, _, _}, 0
  end

  test "signed snapshot data is retained but stock Anthropic continuation rejects before IO" do
    model = model([], model: spec(:anthropic))

    response =
      Message.new_response([%Part.Thinking{content: "reasoning", signature: "signed-token"}],
        finish_reason: :stop,
        continuation: %{
          "version" => 1,
          "provider" => "anthropic",
          "model" => "exagent-fixture",
          "endpoint" => "https://fixture.invalid/v1",
          "message_metadata" => %{},
          "reasoning_details" => []
        }
      )

    history = [request(), response, request("continue")]
    snapshot = ExAgent.Server.Snapshot.new(agent_id: "synthetic", history: history)

    assert {:ok, restored} =
             snapshot
             |> ExAgent.Server.Snapshot.serialize()
             |> ExAgent.Server.Snapshot.deserialize()

    assert {:ok, ^history} = ExAgent.Server.Snapshot.messages(restored)
    assert {:ok, decoded} = Message.from_json(restored.message_history)

    assert {:error, %RequestError{reason: {:unsupported, :anthropic_reasoning_continuation}}} =
             Model.request(model, decoded, nil, params())

    refute_receive {:http, _, _, _}, 0
  end

  test "catalogue Responses reasoning-only ID and encrypted content survive continuation" do
    body = %{
      "id" => "resp-1",
      "object" => "response",
      "status" => "completed",
      "model" => "gpt-4o-mini",
      "output" => [
        %{
          "id" => "reason-1",
          "type" => "reasoning",
          "encrypted_content" => "opaque-reasoning",
          "summary" => [%{"type" => "summary_text", "text" => "summary"}]
        },
        %{
          "id" => "item-1",
          "type" => "message",
          "role" => "assistant",
          "content" => [%{"type" => "output_text", "text" => "done", "annotations" => []}]
        }
      ],
      "usage" => %{"input_tokens" => 9, "output_tokens" => 2, "total_tokens" => 11}
    }

    model =
      model([{200, body}, {200, body}],
        model: "openai:gpt-4o-mini",
        provider_options: [store: false]
      )

    assert {:ok, response, _} = Model.request(model, [request()], nil, params())
    assert [] = Message.Response.tool_calls(response)

    assert [%{"signature" => "opaque-reasoning", "provider_data" => %{"id" => "reason-1"}}] =
             response.continuation["reasoning_details"]

    history = [
      request(),
      response,
      request("continue")
    ]

    assert {:ok, restored} = history |> Message.to_json() |> Message.from_json()
    assert {:ok, _, _} = Model.request(model, restored, nil, params())
    assert_receive {:http, 0, first, _}
    assert first.url.path == "/v1/responses"
    assert_receive {:http, 1, _, next}

    assert Enum.any?(
             next["input"],
             &(&1["type"] == "reasoning" and &1["id"] == "reason-1" and
                 &1["encrypted_content"] == "opaque-reasoning")
           )

    refute Map.has_key?(next, "previous_response_id")
  end

  test "stock Google signature loss is characterized and adapter tools fail closed before IO" do
    body = %{
      "candidates" => [
        %{
          "content" => %{
            "role" => "model",
            "parts" => [
              %{
                "functionCall" => %{"name" => "lookup", "args" => %{"id" => "safe"}},
                "thoughtSignature" => "google-signature"
              }
            ]
          },
          "finishReason" => "STOP"
        }
      ],
      "usageMetadata" => %{
        "promptTokenCount" => 9,
        "candidatesTokenCount" => 2,
        "totalTokenCount" => 11
      }
    }

    model = model([{200, body}], model: spec(:google))
    # Removal criterion for the temporary guard: a public upstream path must
    # retain the supplied signature. This characterizes stock, not desired API.
    assert {:ok, response} =
             ReqLLM.generate_text(model.model, "synthetic",
               api_key: model.api_key,
               base_url: model.base_url,
               max_retries: 0,
               req_http_options: model.http_options
             )

    assert [call] = ReqLLM.Response.tool_calls(response)
    assert call.function.name == "lookup"
    assert ReqLLM.ToolCall.metadata(call) == %{}
    assert response.message.reasoning_details == nil
    assert_receive {:http, 0, _, _}
    refute Model.profile(model).supports_tools

    assert {:error, %RequestError{reason: {:unsupported, :tools}}} =
             Model.request(model, [request()], nil, %{params() | function_tools: [tool(self())]})

    refute_receive {:http, _, _, _}, 0
    refute_receive {:effect, _}, 0
  end

  test "continuation versions and nonportable metadata reject in codec" do
    response =
      Message.new_response(
        [%Part.Text{content: "ok", metadata: %{"nested" => %{"id" => "text-id"}}}],
        continuation: %{
          "version" => 1,
          "provider" => "openai",
          "model" => "m",
          "endpoint" => nil,
          "message_metadata" => %{},
          "reasoning_details" => []
        }
      )

    assert {:ok, [^response]} = [response] |> Message.to_json() |> Message.from_json()
    corrupt = Message.to_json([response]) |> String.replace("\"version\":1", "\"version\":999")
    assert {:error, {:invalid_message, _}} = Message.from_json(corrupt)

    assert_raise ArgumentError, fn ->
      Message.to_json([
        %{response | parts: [%Part.Text{content: "bad", metadata: %{pid: self()}}]}
      ])
    end
  end
end
