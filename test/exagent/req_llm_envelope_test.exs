defmodule ExAgent.ReqLLMEnvelopeTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Message, Model, ModelRequestParameters, ModelSettings, Tool}
  alias ExAgent.Message.Part
  alias ExAgent.Models.ReqLLM, as: Adapter

  @empty %{"type" => "object", "properties" => %{}, "additionalProperties" => false}
  @schema %{
    "type" => "object",
    "properties" => %{"value" => %{"type" => "integer"}},
    "required" => ["value"],
    "additionalProperties" => false
  }

  defmodule EmptyOutput do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
    end

    def changeset(data, attrs), do: Ecto.Changeset.cast(data, attrs, [])
  end

  defmodule TypedOutput do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:value, :string)

      embeds_one :child, Child, primary_key: false do
        field(:enabled, :boolean)
      end

      embeds_many :rows, Row, primary_key: false do
        field(:name, :string)
      end
    end

    def changeset(data, attrs) do
      data
      |> cast(attrs, [:value])
      |> cast_embed(:child, with: &cast(&1, &2, [:enabled]))
      |> cast_embed(:rows, with: &cast(&1, &2, [:name]))
      |> validate_change(:value, fn :value, value ->
        if value == "bad", do: [value: "not accepted"], else: []
      end)
    end
  end

  defmodule Observe do
    use ExAgent.Capability

    def before_tool_execute(_, ctx, call) do
      send(ctx.deps.owner, {:hook, call})

      case ctx.deps[:rewrite] do
        :args -> %{call | args: %{"value" => "bad"}}
        :name -> %{call | tool_name: "other"}
        :id -> %{call | tool_call_id: "other-id"}
        :valid -> %{call | args: %{"value" => 9}}
        _ -> call
      end
    end
  end

  defp spec do
    %{
      provider: :openai,
      id: "envelope-fixture",
      extra: %{wire: %{protocol: "openai_chat"}},
      capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
    }
  end

  defp model(bodies, opts \\ []) do
    {call_metadata, opts} = Keyword.pop(opts, :call_metadata, :unchanged)
    {fixture_adapter, opts} = Keyword.pop(opts, :fixture_adapter, ExAgent.Test.ReqTransport)
    owner = self()
    counter = start_supervised!({Agent, fn -> 0 end}, id: make_ref())

    transport = fn request ->
      request =
        if call_metadata == :unchanged do
          request
        else
          Req.Request.append_response_steps(request,
            expose_call_metadata: fn {req, response} ->
              %ReqLLM.Response{} = backend = response.body

              calls =
                Enum.map(
                  ReqLLM.Response.tool_calls(backend),
                  &ReqLLM.ToolCall.put_metadata(&1, call_metadata)
                )

              {req,
               %{response | body: %{backend | message: %{backend.message | tool_calls: calls}}}}
            end
          )
        end

      index = Agent.get_and_update(counter, &{&1, &1 + 1})

      send(
        owner,
        {:request, index, request.url.path, Jason.decode!(IO.iodata_to_binary(request.body))}
      )

      {status, body} =
        case Enum.fetch!(bodies, index) do
          {status, body} -> {status, body}
          body -> {200, body}
        end

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
          tool_profile: :chat_tools_v1,
          api_key: "synthetic",
          base_url: "https://fixture.invalid/v1",
          http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport, fixture_adapter)]
        ],
        opts
      )
    )
  end

  defp tool(schema \\ @schema, name \\ "effect") do
    owner = self()

    Tool.new(
      name: name,
      parameters_json_schema: schema,
      call: fn ctx, args ->
        send(owner, {:effect, name, ctx.tool_call_id, args})
        %{"result" => args}
      end
    )
  end

  defp call(args, name \\ "effect", id \\ "call-1") do
    %{"id" => id, "type" => "function", "function" => %{"name" => name, "arguments" => args}}
  end

  defp response(calls, finish \\ "tool_calls") do
    %{
      "id" => "reply",
      "model" => "envelope-fixture",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{"role" => "assistant", "content" => "prefix", "tool_calls" => calls},
          "finish_reason" => finish
        }
      ]
    }
  end

  defp final, do: response([], "stop")
  defp wire(args), do: Jason.encode!(%{"arguments" => args})

  defp params(schema \\ @schema) do
    %ModelRequestParameters{
      function_tools: [Tool.new(name: "effect", parameters_json_schema: schema)]
    }
  end

  defp prompt, do: Message.new_request([%Part.User{content: "go"}])

  test "mandatory envelope guidance reaches the model once without replacing caller instructions" do
    caller =
      Message.new_request([
        %Part.System{content: "Caller-owned policy."},
        %Part.User{content: "go"}
      ])

    m = model([final(), final(), final()])

    assert {:ok, _, _} = Model.request(m, [caller], %ModelSettings{}, %ModelRequestParameters{})
    assert_receive {:request, 0, _, plain}
    assert Enum.map(plain["messages"], & &1["role"]) == ["system", "user"]
    refute Jason.encode!(plain["messages"]) =~ "one outer JSON object"

    for index <- [1, 2] do
      assert {:ok, _, _} = Model.request(m, [caller], %ModelSettings{}, params(@empty))
      assert_receive {:request, ^index, _, body}
      [guidance | original] = body["messages"]
      assert guidance["role"] == "system"
      encoded = Jason.encode!(guidance["content"])
      assert encoded =~ "one outer JSON object"
      assert encoded =~ "declared parameters"
      assert encoded =~ Jason.encode!(~s({"arguments": {}})) |> String.trim("\"")
      assert original == plain["messages"]

      assert Enum.count(
               body["messages"],
               &(Jason.encode!(&1["content"]) =~ "one outer JSON object")
             ) == 1

      assert [tool] = body["tools"]
      assert tool["function"]["parameters"]["required"] == ["arguments"]
      assert tool["function"]["parameters"]["additionalProperties"] == false
    end

    refute_receive {:effect, _, _, _}, 0
  end

  test "public response metadata: historical diagnostics survive but every explicit error rejects before effects" do
    # Public Req response steps expose synthetic semantic metadata after stock
    # decoding. TCP tests separately prove real fragment/loss diagnostics.
    for metadata <- [
          %{error: {:args_lost, :json_decode_error}},
          %{error: {:args_lost, :missing_fragments}},
          %{"error" => "args_lost"},
          %{error: "unknown error"},
          %{error: false},
          %{"error" => ""},
          %{:error => nil, "error" => "unknown error"},
          %{:error => false, "error" => nil}
        ] do
      m = model([response([call(wire(%{"value" => 7}))])], call_metadata: metadata)

      assert {:error,
              %ExAgent.RunError{
                reason:
                  {:model_request_failed, %ExAgent.RequestError{reason: :invalid_tool_arguments}},
                partial: partial
              }} =
               ExAgent.run(ExAgent.new(model: m, tools: [tool()], capabilities: [Observe]), "go",
                 deps: %{owner: self()}
               )

      assert partial.request_count == 1
      assert_receive {:request, 0, _, _}
      refute_receive {:request, 1, _, _}, 0
      refute_receive {:hook, _}, 0
      refute_receive {:effect, _, _, _}, 0
    end

    for metadata <- [
          %{invalid_arguments: true, unparseable_arguments: true, raw_arguments: "{"},
          %{
            "invalid_arguments" => true,
            "unparseable_arguments" => true,
            "raw_arguments" => "",
            "error" => nil
          },
          %{error: nil}
        ] do
      m = model([response([call(wire(%{"value" => 7}))]), final()], call_metadata: metadata)
      assert {:ok, result} = ExAgent.run(ExAgent.new(model: m, tools: [tool()]), "go")
      assert result.request_count == 2
      assert_receive {:effect, "effect", "call-1", %{"value" => 7}}
      refute_receive {:effect, _, _, _}, 0

      [call] =
        result.messages
        |> Enum.filter(&match?(%Message.Response{}, &1))
        |> Enum.flat_map(&Message.Response.tool_calls/1)

      assert Map.drop(call.metadata, ["arguments_codec"]) ==
               Map.new(metadata, fn {k, v} -> {to_string(k), v} end)

      assert Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages}
      assert_receive {:request, 0, _, _}
      assert_receive {:request, 1, _, _}
      refute_receive {:request, _, _, _}, 0
    end

    m =
      model([response([call(wire(%{"value" => 7}))])],
        call_metadata: %{diagnostic: {:opaque, :tuple}}
      )

    assert {:error, %ExAgent.RequestError{reason: :invalid_message_or_options}} =
             Model.request(m, [prompt()], nil, params())
  end

  test "public run uses logical hooks/DI, exact IDs/order and once-wrapped second turn" do
    m =
      model([
        response([call(wire(%{"value" => 7})), call(wire(%{"value" => 8}), "effect", "call-2")]),
        final()
      ])

    agent = ExAgent.new(model: m, tools: [tool()], capabilities: [Observe])
    assert {:ok, result} = ExAgent.run(agent, "go", deps: %{owner: self()})
    assert result.output == "prefix"
    assert_receive {:hook, %Part.ToolCall{args: %{"value" => 7}, tool_call_id: "call-1"}}
    assert_receive {:effect, "effect", "call-1", %{"value" => 7}}
    assert_receive {:effect, "effect", "call-2", %{"value" => 8}}
    refute_receive {:effect, _, _, _}, 0
    assert_receive {:request, 0, "/v1/chat/completions", payload}
    assert [%{"function" => definition}] = payload["tools"]
    assert definition["parameters"]["required"] == ["arguments"]
    assert definition["parameters"]["properties"]["arguments"] == @schema
    refute Map.has_key?(definition, "strict")
    assert_receive {:request, 1, "/v1/chat/completions", next}
    assistant = Enum.find(next["messages"], &(&1["role"] == "assistant"))
    assert Enum.map(assistant["tool_calls"], & &1["id"]) == ["call-1", "call-2"]

    assert Enum.map(assistant["tool_calls"], &Jason.decode!(&1["function"]["arguments"])) == [
             %{"arguments" => %{"value" => 7}},
             %{"arguments" => %{"value" => 8}}
           ]

    assert Enum.filter(next["messages"], &(&1["role"] == "tool"))
           |> Enum.map(& &1["tool_call_id"]) == ["call-1", "call-2"]

    response =
      Enum.find(result.messages, &match?(%Message.Response{parts: [_, %Part.ToolCall{} | _]}, &1))

    assert response.continuation["version"] == 2
    assert response.continuation["arguments_codec"] == "exagent.arguments/1"
    assert Message.from_json(Message.to_json([response])) == {:ok, [response]}
  end

  test "public run rejects invalid envelopes and logical schemas before hook or effect" do
    for args <- [
          "[]",
          "[{}]",
          "null",
          "true",
          "1",
          "\"x\"",
          "{}",
          "{\"arguments\":{}",
          "{\"arguments\":[]}",
          "{\"other\":{}}",
          "{\"arguments\":{},\"extra\":true}",
          wire(%{"value" => "bad"})
        ] do
      m = model([response([call(args)])])

      assert {:error, _} =
               ExAgent.run(ExAgent.new(model: m, tools: [tool()], capabilities: [Observe]), "go",
                 deps: %{owner: self()}
               )

      assert_receive {:request, 0, _, _}
      refute_receive {:request, 1, _, _}, 0
      refute_receive {:hook, _}, 0
      refute_receive {:effect, _, _, _}, 0
    end
  end

  test "empty logical tool and boolean true schema accept objects; false rejects" do
    for schema <- [@empty, true] do
      m = model([response([call(wire(%{}))]), final()])
      assert {:ok, _} = ExAgent.run(ExAgent.new(model: m, tools: [tool(schema)]), "go")
      assert_receive {:effect, "effect", "call-1", %{}}
    end

    m = model([response([call(wire(%{}))])])
    assert {:error, _} = ExAgent.run(ExAgent.new(model: m, tools: [tool(false)]), "go")
    refute_receive {:effect, _, _, _}, 0
  end

  test "effective hook arguments revalidate and qualified identity cannot change" do
    for rewrite <- [:args, :name, :id] do
      m = model([response([call(wire(%{"value" => 7}))]), final()])

      agent =
        ExAgent.new(model: m, tools: [tool(), tool(@schema, "other")], capabilities: [Observe])

      ExAgent.run(agent, "go", deps: %{owner: self(), rewrite: rewrite})
      assert_receive {:hook, %Part.ToolCall{args: %{"value" => 7}}}
      refute_receive {:effect, _, _, _}, 0
    end

    m = model([response([call(wire(%{"value" => 7}))]), final()])

    assert {:ok, _} =
             ExAgent.run(ExAgent.new(model: m, tools: [tool()], capabilities: [Observe]), "go",
               deps: %{owner: self(), rewrite: :valid}
             )

    assert_receive {:effect, "effect", "call-1", %{"value" => 9}}
  end

  test "subset preserves nested optional/default/arrays/enums/nulls and rejects refs preIO" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "optional" => %{"type" => "integer", "default" => 42},
        "nested" => %{
          "type" => "object",
          "properties" => %{"flag" => %{"type" => "boolean"}},
          "additionalProperties" => false
        },
        "rows" => %{"type" => "array", "items" => %{"enum" => [nil, "ok"]}},
        "anything" => true,
        "never" => false
      },
      "additionalProperties" => false
    }

    args = %{"nested" => %{"flag" => true}, "rows" => [nil, "ok"]}
    m = model([response([call(wire(args))])])
    assert {:ok, result, _} = Model.request(m, [prompt()], nil, params(schema))
    assert [%Part.Text{}, %Part.ToolCall{args: ^args}] = result.parts
    assert_receive {:request, 0, _, payload}

    assert get_in(payload, [
             "tools",
             Access.at(0),
             "function",
             "parameters",
             "properties",
             "arguments"
           ]) == schema

    for fragment <- [
          %{"$ref" => "#"},
          %{"$ref" => "#/$defs/x"},
          %{"$ref" => "https://fixture.invalid/schema"},
          %{"$ref" => "file:///tmp/x"},
          %{"$defs" => %{"x" => true}},
          %{"$id" => "local"},
          %{"$anchor" => "x"},
          %{"$dynamicRef" => "#x"},
          %{"$dynamicAnchor" => "x"},
          %{"$schema" => "https://json-schema.org/draft/2020-12/schema"}
        ] do
      m = model([])
      assert {:error, _} = Model.request(m, [prompt()], nil, params(Map.merge(@schema, fragment)))
      refute_receive {:request, _, _, _}, 0
    end
  end

  test "history requires explicit codec and valid logical maps and stays once wrapped" do
    m = model([response([call(wire(%{"value" => 7}))]), final()])
    assert {:ok, response, _} = Model.request(m, [prompt()], nil, params())
    assert_receive {:request, 0, _, _}
    assert {:ok, [restored]} = Message.from_json(Message.to_json([response]))

    history = [
      prompt(),
      restored,
      Message.new_request([
        %Part.ToolReturn{tool_name: "effect", tool_call_id: "call-1", content: "ok"}
      ])
    ]

    assert {:ok, _, _} = Model.request(m, history, nil, params())
    assert_receive {:request, 1, _, payload}

    [assistant] = Enum.filter(payload["messages"], &(&1["role"] == "assistant"))

    assert assistant["tool_calls"]
           |> hd()
           |> get_in(["function", "arguments"])
           |> Jason.decode!() == %{"arguments" => %{"value" => 7}}

    [text, call] = restored.parts

    for invalid <- [
          %{restored | continuation: nil},
          %{restored | parts: [text, %{call | args: "[]"}]},
          %{restored | parts: [text, %{call | metadata: %{}}]},
          %{restored | parts: [text, %{call | args: %{}}]}
        ] do
      assert {:error, _} = Model.request(model([]), [invalid], nil, params())
      refute_receive {:request, _, _, _}, 0
    end
  end

  test "Ecto final_result accepts empty/embed/null and retries a changeset rejection once" do
    m = model([response([call(wire(%{}), "final_result")])])

    assert {:ok, %{output: %EmptyOutput{}}} =
             ExAgent.run(ExAgent.new(model: m, output_type: EmptyOutput), "go")

    for args <- [
          %{"value" => nil, "child" => nil, "rows" => []},
          %{"value" => "ok", "child" => %{"enabled" => true}, "rows" => [%{"name" => "x"}]}
        ] do
      m = model([response([call(wire(args), "final_result")])])

      assert {:ok, %{output: %TypedOutput{}}} =
               ExAgent.run(ExAgent.new(model: m, output_type: TypedOutput), "go")
    end

    m =
      model([
        response([call(wire(%{"value" => "bad"}), "final_result")]),
        response([call(wire(%{"value" => "ok"}), "final_result", "call-2")])
      ])

    assert {:ok, %{output: %TypedOutput{value: "ok"}}} =
             ExAgent.run(ExAgent.new(model: m, output_type: TypedOutput), "go")

    assert_receive {:request, 1, _, payload}

    assert Enum.any?(
             payload["messages"],
             &(&1["role"] == "tool" and &1["tool_call_id"] == "call-1")
           )

    refute_receive {:request, 2, _, _}, 0
  end

  test "restored qualified continuation is bound to provider model and endpoint before IO" do
    m = model([response([call(wire(%{"value" => 7}))])])
    assert {:ok, response, _} = Model.request(m, [prompt()], nil, params())
    assert_receive {:request, 0, _, _}
    assert {:ok, [restored]} = Message.from_json(Message.to_json([response]))

    for {key, value} <- [
          {"provider", "google"},
          {"model", "another-model"},
          {"endpoint", "https://another.invalid/v1"}
        ] do
      foreign = %{restored | continuation: Map.put(restored.continuation, key, value)}
      assert {:error, _} = Model.request(model([]), [foreign], nil, params())
      refute_receive {:request, _, _, _}, 0
    end

    for changed <- [
          model([], model: %{spec() | id: "another-model"}),
          model([], base_url: "https://another.invalid/v1")
        ] do
      assert {:error, _} = Model.request(changed, [restored], nil, params())
      refute_receive {:request, _, _, _}, 0
    end
  end

  test "qualified internal tool choice follows text permission and native output rejects preIO" do
    for {allow_text, choice} <- [{true, "auto"}, {false, "required"}] do
      assert {:ok, _, _} =
               Model.request(model([final()]), [prompt()], nil, %{
                 params()
                 | allow_text_output: allow_text
               })

      assert_receive {:request, 0, _, payload}
      assert payload["tool_choice"] == choice
      assert [%{"function" => definition}] = payload["tools"]
      assert definition["parameters"]["properties"]["arguments"] == @schema
      refute Map.has_key?(definition, "strict")
    end

    assert {:ok, _} =
             ExAgent.run(
               ExAgent.new(
                 model: model([response([call(wire(%{}), "final_result")])]),
                 output_type: EmptyOutput,
                 output_mode: :tool
               ),
               "go"
             )

    assert_receive {:request, 0, _, ecto_payload}
    assert ecto_payload["tool_choice"] == "required"

    assert {:error, _} =
             Model.request(model([]), [prompt()], nil, %{params() | output_mode: :native})

    refute_receive {:request, _, _, _}, 0
  end

  test "terminal failures, no hidden retry, reserved options and unqualified APIs stay closed" do
    for finish <- ["length", "content_filter", "incomplete", "unknown", nil] do
      assert {:error, _} =
               ExAgent.run(
                 ExAgent.new(
                   model: model([response([call(wire(%{}))], finish)]),
                   tools: [tool(@empty)]
                 ),
                 "go"
               )

      refute_receive {:effect, _, _, _}, 0
      assert_receive {:request, 0, _, _}
    end

    m = model([{429, %{"error" => %{"message" => "synthetic secret"}}}])
    assert {:error, error} = Model.request(m, [prompt()], nil, params())
    refute inspect(error) =~ "synthetic secret"
    assert_receive {:request, 0, _, _}
    refute_receive {:request, 1, _, _}, 0

    for model_spec <- [
          put_in(spec(), [:extra, :wire, :protocol], "openai_responses"),
          Map.delete(spec(), :extra),
          put_in(spec(), [:capabilities, :tools, :strict], true),
          put_in(spec(), [:capabilities, :reasoning, :enabled], true),
          %{spec() | provider: :google}
        ] do
      assert {:error, _} = Model.request(model([], model: model_spec), [prompt()], nil, params())
      refute_receive {:request, _, _, _}, 0
    end

    for key <- [:json_repair, :max_retries, :tools, :strict] do
      assert {:error, _} =
               Model.request(
                 model([]),
                 [prompt()],
                 %ModelSettings{extra: %{key => true}},
                 params()
               )

      refute_receive {:request, _, _, _}, 0
    end
  end

  test "permissions bind the validated effective call and deny or ask cannot execute it" do
    for policy <- [:deny, :ask] do
      m = model([response([call(wire(%{"value" => 7}))]), final()])
      permissions = ExAgent.Permissions.new!(rules: [{"effect", policy}])
      agent = ExAgent.new(model: m, tools: [tool()], capabilities: [Observe])
      ExAgent.run(agent, "go", deps: %{owner: self(), rewrite: :valid}, permissions: permissions)

      assert_receive {:hook,
                      %Part.ToolCall{
                        tool_name: "effect",
                        tool_call_id: "call-1",
                        args: %{"value" => 7}
                      }}

      refute_receive {:effect, _, _, _}, 0
    end

    m = model([response([call(wire(%{"value" => 7}))]), final()])
    owner = self()

    approve = fn call ->
      send(owner, {:approval, call})
      :approve
    end

    permissions = ExAgent.Permissions.new!(rules: [{"effect", :ask}])

    assert {:ok, _} =
             ExAgent.run(ExAgent.new(model: m, tools: [tool()], capabilities: [Observe]), "go",
               deps: %{owner: owner, rewrite: :valid},
               permissions: permissions,
               approve: approve
             )

    assert_receive {:approval,
                    %Part.ToolCall{
                      args: %{"value" => 9},
                      tool_call_id: "call-1",
                      tool_name: "effect"
                    }}

    assert_receive {:effect, "effect", "call-1", %{"value" => 9}}
    refute_receive {:effect, _, _, _}, 0
  end

  test "an allowed delegated call does not authorize its child model selected tool" do
    child =
      ExAgent.new(
        model:
          model([response([call(wire(%{"value" => 7}))]), final()],
            fixture_adapter: ExAgent.Test.ReqTransport.Child
          ),
        tools: [tool()]
      )

    child_transport = ExAgent.Test.ReqTransport.capture(ExAgent.Test.ReqTransport.Child)

    delegate =
      Tool.new(
        name: "delegate",
        parameters_json_schema: @empty,
        call: fn ctx, _ ->
          ExAgent.Test.ReqTransport.bind(child_transport, ExAgent.Test.ReqTransport.Child)
          {:ok, result} = ExAgent.run_child(ctx, child, "child")
          result.output
        end
      )

    parent =
      ExAgent.new(
        model: model([response([call(wire(%{}), "delegate")]), final()]),
        tools: [delegate]
      )

    policy = ExAgent.Permissions.new!(default: :deny, rules: [{"delegate", :allow}])
    assert {:ok, _} = ExAgent.run(parent, "go", permissions: policy)
    refute_receive {:effect, _, _, _}, 0
  end

  test "Server snapshot restore and compaction retain codec and never replay completed effects" do
    alias ExAgent.{Server, Store}
    m = model([response([call(wire(%{"value" => 7}))]), final(), final(), final()])
    owner = self()

    compaction = %ExAgent.Compaction.Capability{
      compactor: ExAgent.Compaction.Summary,
      opts: [
        threshold_tokens: 0,
        keep_recent: 3,
        summarize: fn old ->
          send(owner, {:compacted, old})
          "old context"
        end
      ]
    }

    agent = ExAgent.new(model: m, tools: [tool()], capabilities: [compaction])
    id = "envelope-#{System.unique_integer([:positive])}"
    store = {ExAgent.Store.ETS, ExAgent.Store.ETS}
    on_exit(fn -> Store.delete_agent_snapshot(store, id) end)

    server =
      start_supervised!({Server, agent: agent, agent_id: id, store: store}, id: :envelope_server)

    :ok = ExAgent.Test.ReqTransport.allow(server)

    assert {:ok, first} = Server.chat(server, "first")
    assert first.request_count == 2
    assert_receive {:effect, "effect", "call-1", %{"value" => 7}}
    assert {:ok, snapshot} = Store.load_agent_snapshot(store, id)
    bytes = ExAgent.Server.Snapshot.serialize(snapshot)
    assert bytes =~ "exagent.arguments/1"
    refute bytes =~ "synthetic"
    history = Server.history(server)
    assert :ok = stop_supervised(:envelope_server)

    restored =
      start_supervised!({Server, agent: agent, agent_id: id, store: store},
        id: :restored_envelope_server
      )

    :ok = ExAgent.Test.ReqTransport.allow(restored)

    assert Server.history(restored) == history
    assert {:ok, second} = Server.chat(restored, "second")
    assert second.request_count == 1
    assert {:ok, third} = Server.chat(restored, "third")
    assert third.request_count == 1
    assert_receive {:compacted, _}
    refute_receive {:effect, _, _, _}, 0
    assert Enum.take(Server.history(restored), length(history)) == history
  end
end
