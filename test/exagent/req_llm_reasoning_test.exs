defmodule ExAgent.ReqLLMReasoningTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Message, Model, Tool}
  alias ExAgent.Models.ReqLLM, as: Adapter

  defmodule Total do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:total, :integer)
    end

    def changeset(struct, attrs) do
      struct
      |> Ecto.Changeset.cast(attrs, [:total])
      |> Ecto.Changeset.validate_required([:total])
    end
  end

  @detail %{
    "type" => "reasoning.text",
    "text" => "Need the code first.",
    "signature" => "sig-1",
    "format" => "anthropic-claude-v1",
    "index" => 0
  }

  # `replies` is a list of wire messages; each request consumes the next one.
  defp model(replies, opts \\ []) do
    owner = self()
    counter = start_supervised!({Agent, fn -> 0 end}, id: make_ref())

    transport = fn request ->
      n = Agent.get_and_update(counter, &{&1, &1 + 1})
      send(owner, {:http, n, Jason.decode!(IO.iodata_to_binary(request.body))})

      {message, finish} =
        Enum.at(replies, n, {%{"role" => "assistant", "content" => "x"}, "stop"})

      body = %{
        "id" => "fixture-#{n}",
        "model" => "reasoning-fixture",
        "choices" => [%{"index" => 0, "message" => message, "finish_reason" => finish}],
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
            id: "reasoning-fixture",
            capabilities: %{
              tools: %{enabled: true},
              reasoning: %{enabled: true, effort: %{supported: true, values: ["low", "high"]}}
            },
            extra: %{wire: %{protocol: "openai_chat"}}
          },
          api_key: "synthetic",
          base_url: "https://fixture.invalid/v1",
          tool_profile: :openrouter_chat_tools_v1,
          reasoning_mode: :enabled,
          provider_options: [openrouter_provider: %{only: ["anthropic"], allow_fallbacks: false}],
          http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
        ],
        opts
      )
    )
  end

  defp call(id, name, args, extra \\ %{}) do
    Map.merge(
      %{
        "role" => "assistant",
        "content" => nil,
        "tool_calls" => [
          %{
            "id" => id,
            "type" => "function",
            "function" => %{"name" => name, "arguments" => Jason.encode!(%{"arguments" => args})}
          }
        ]
      },
      extra
    )
  end

  defp text(content), do: {%{"role" => "assistant", "content" => content}, "stop"}

  defp tool do
    owner = self()

    Tool.new(
      name: "lookup",
      parameters_json_schema: %{
        type: "object",
        properties: %{city: %{type: "string"}},
        required: ["city"],
        additionalProperties: false
      },
      call: fn _ctx, args ->
        send(owner, {:effect, args})
        "417"
      end
    )
  end

  defp reasoning_call do
    {call("c1", "lookup", %{"city" => "Valencia"}, %{
       "reasoning" => "Need the code first.",
       "reasoning_details" => [@detail]
     }), "tool_calls"}
  end

  test "enabled reasoning survives the tool loop and is replayed with its signature" do
    agent =
      ExAgent.new(
        model: model([reasoning_call(), text("417")], reasoning_effort: :high),
        tools: [tool()]
      )

    assert {:ok, result} = ExAgent.run(agent, "go")
    assert result.output == "417" and result.request_count == 2
    assert_receive {:effect, %{"city" => "Valencia"}}

    assert_receive {:http, 0, first}
    assert Map.get(first, "tool_choice", "auto") == "auto"
    assert first["reasoning_effort"] == "high"

    assert_receive {:http, 1, second}
    assistant = Enum.find(second["messages"], &(&1["role"] == "assistant"))

    assert [%{"signature" => "sig-1", "text" => "Need the code first."}] =
             assistant["reasoning_details"]

    [response | _] = Enum.filter(result.messages, &match?(%Message.Response{}, &1))
    assert response.continuation["reasoning_mode"] == "enabled"
    assert [%{"signature" => "sig-1"}] = response.continuation["reasoning_details"]
    assert Enum.any?(response.parts, &match?(%Message.Part.Thinking{}, &1))
    assert Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages}
    assert Model.profile(agent.model).supports_thinking
  end

  test "forced tool choices become auto, and the loop still requires the output tool" do
    agent =
      ExAgent.new(
        model:
          model([
            text("The total is 706."),
            {call("o1", "final_result", %{"total" => 706}), "tool_calls"}
          ]),
        output: Total,
        output_retries: 1
      )

    assert {:ok, %{output: %Total{total: 706}, request_count: 2}} = ExAgent.run(agent, "go")
    assert_receive {:http, 0, b0}
    assert Map.get(b0, "tool_choice", "auto") == "auto"
    assert_receive {:http, 1, b1}
    assert Map.get(b1, "tool_choice", "auto") == "auto"
  end

  test "final step with an output tool is not forced either" do
    agent =
      ExAgent.new(
        model:
          model([
            reasoning_call(),
            {call("o1", "final_result", %{"total" => 417}), "tool_calls"}
          ]),
        tools: [tool()],
        output: Total,
        max_steps: 2,
        on_max_steps: :final
      )

    assert {:ok, %{output: %Total{total: 417}}} = ExAgent.run(agent, "go")
    assert_receive {:http, 1, last}
    assert Map.get(last, "tool_choice", "auto") == "auto"
  end

  test "disabled mode keeps forced choices and still rejects exposed reasoning" do
    disabled = [
      reasoning_mode: nil,
      model: %{
        provider: :openrouter,
        id: "reasoning-fixture",
        capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
        extra: %{wire: %{protocol: "openai_chat"}}
      }
    ]

    typed =
      ExAgent.new(
        model: model([{call("o1", "final_result", %{"total" => 1}), "tool_calls"}], disabled),
        output: Total
      )

    assert {:ok, _} = ExAgent.run(typed, "go")
    assert_receive {:http, 0, %{"tool_choice" => "required"}}

    exposed = ExAgent.new(model: model([reasoning_call()], disabled), tools: [tool()])

    assert {:error,
            %ExAgent.RunError{
              reason:
                {:model_request_failed,
                 %ExAgent.RequestError{reason: {:unsupported, :tool_profile_content}}}
            }} = ExAgent.run(exposed, "go")

    refute_receive {:effect, _}, 0
  end

  test "admission rejects unqualified enabled configurations before IO" do
    no_reasoning = %{
      provider: :openrouter,
      id: "reasoning-fixture",
      capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
      extra: %{wire: %{protocol: "openai_chat"}}
    }

    openai_reasoning = %{
      provider: :openai,
      id: "reasoning-fixture",
      capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: true}},
      extra: %{wire: %{protocol: "openai_chat"}}
    }

    # Not a qualified tools profile at all: the loop refuses tools before IO.
    # OpenAI Chat does not return reasoning to replay, so enabled is routed-only.
    for opts <- [
          [tool_profile: :chat_tools_v1, provider_options: []],
          [tool_profile: :chat_tools_v1, provider_options: [], model: openai_reasoning],
          [model: no_reasoning]
        ] do
      refute Model.profile(model([], opts)).supports_tools
      agent = ExAgent.new(model: model([], opts), tools: [tool()])

      assert {:error, %ExAgent.RunError{reason: {:unsupported, :tools}}} =
               ExAgent.run(agent, "go")
    end

    # Qualified tools, invalid reasoning options: the adapter rejects before IO.
    cases = [
      {[reasoning_effort: :medium], {:unsupported, :reasoning_effort}},
      {[reasoning_effort: :extreme], {:invalid_option, :reasoning_effort}},
      {[reasoning_mode: nil, model: no_reasoning, reasoning_effort: :low],
       {:invalid_option, :reasoning_effort}}
    ]

    for {opts, reason} <- cases do
      agent = ExAgent.new(model: model([], opts), tools: [tool()])

      assert {:error,
              %ExAgent.RunError{
                reason: {:model_request_failed, %ExAgent.RequestError{reason: ^reason}}
              }} = ExAgent.run(agent, "go"),
             inspect(opts)
    end

    refute_receive {:http, _, _}, 0
  end

  test "history from another reasoning mode is foreign" do
    disabled = [
      reasoning_mode: nil,
      model: %{
        provider: :openrouter,
        id: "reasoning-fixture",
        capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
        extra: %{wire: %{protocol: "openai_chat"}}
      }
    ]

    first =
      ExAgent.new(
        model:
          model([{call("c1", "lookup", %{"city" => "A"}), "tool_calls"}, text("ok")], disabled),
        tools: [tool()]
      )

    assert {:ok, %{messages: history}} = ExAgent.run(first, "go")

    strict = ExAgent.new(model: model([text("later")]), tools: [tool()])

    assert {:error,
            %ExAgent.RunError{
              reason:
                {:model_request_failed,
                 %ExAgent.RequestError{reason: :continuation_mode_mismatch}}
            }} = ExAgent.run(strict, "again", message_history: history)

    portable =
      ExAgent.new(model: model([text("later")], foreign_history: :portable), tools: [tool()])

    assert {:ok, %{output: "later"}} = ExAgent.run(portable, "again", message_history: history)
  end

  test "modes without reasoning still accept text responses that carry no continuation" do
    openai = [
      reasoning_mode: nil,
      tool_profile: :chat_tools_v1,
      provider_options: [],
      model: %{
        provider: :openai,
        id: "reasoning-fixture",
        capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
        extra: %{wire: %{protocol: "openai_chat"}}
      }
    ]

    # An application-seeded greeting, or history from a Test/custom model.
    history = [
      Message.new_request([%Message.Part.User{content: "hi"}]),
      %Message.Response{parts: [%Message.Part.Text{content: "hello"}]}
    ]

    agent = ExAgent.new(model: model([text("ok")], openai), tools: [tool()])
    assert {:ok, %{output: "ok"}} = ExAgent.run(agent, "again", message_history: history)
    assert_receive {:http, 0, %{"messages" => messages}}
    assert Enum.any?(messages, &(&1["role"] == "assistant" and &1["content"] == "hello"))
  end

  test "the continuation binding records the enabled mode" do
    assert {:ok, binding} = Adapter.continuation_binding(model([]))
    assert binding["reasoning_mode"] == "enabled"
    assert binding["capabilities"]["reasoning"] == %{"enabled" => true}
  end
end
