defmodule ExAgent.ReqLLMOutputTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Message, ModelRequestParameters, ModelSettings, RunError}
  alias ExAgent.Message.{Part, Response}
  alias ExAgent.Models.ReqLLM, as: Model

  defmodule Empty do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
    end

    def changeset(data, attrs), do: Ecto.Changeset.cast(data, attrs, [])
  end

  defmodule Child do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:note, :string)
    end

    def changeset(data, attrs), do: Ecto.Changeset.cast(data, attrs, [:note])
  end

  defmodule Output do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:value, :string)
      field(:optional, :integer, default: 7)
      embeds_one(:child, Child)
      embeds_many(:children, Child)
    end

    def changeset(data, attrs) do
      data
      |> cast(attrs, [:value, :optional])
      |> cast_embed(:child)
      |> cast_embed(:children)
      |> validate_change(:value, fn :value, v ->
        if v == "accepted", do: [], else: [value: "conditional Ecto rule"]
      end)
    end
  end

  defp model(url) do
    Model.new(
      model: %{
        provider: :openai,
        id: "r23-output",
        extra: %{wire: %{protocol: "openai_chat"}},
        capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
      },
      api_key: "synthetic",
      base_url: url,
      tool_profile: :chat_tools_v1,
      output_profile: :chat_json_schema_v1,
      total_timeout: 5000
    )
  end

  defp execute(agent, :sync, opts), do: ExAgent.run(agent, "synthetic", opts)

  defp execute(agent, :stream_text, opts),
    do: ExAgent.run(agent, "synthetic", Keyword.put(opts, :stream_text, true))

  defp execute(agent, :stream, opts) do
    events = agent |> ExAgent.run_stream("synthetic", opts) |> Enum.to_list()
    terminals = Enum.filter(events, fn {type, _} -> type in [:result, :error] end)
    assert [terminal] = terminals

    assert List.last(events) == terminal

    case terminal do
      {:result, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  defp native?(:native), do: true
  defp native?(_), do: false

  test "tool/native: empty and embedded/null outputs have parity with exact effective schema" do
    for mode <- [:tool, :native],
        surface <- [:sync, :stream_text, :stream],
        {schema, data} <- [
          {Empty, %{}},
          {Output,
           %{
             "value" => "accepted",
             "optional" => nil,
             "child" => %{"note" => nil},
             "children" => [%{"note" => "hi"}]
           }},
          {Output, %{"child" => nil}}
        ] do
      {url, journal} = peer([reply(mode, data)])
      agent = ExAgent.new(model: model(url), output: schema, output_mode: mode)
      assert {:ok, result} = execute(agent, surface, [])
      assert result.output.__struct__ == schema
      assert result.request_count == 1
      assert result.tool_calls == 0
      [payload] = Agent.get(journal, & &1)

      expected =
        schema |> ExAgent.OutputSchema.json_schema() |> Jason.encode!() |> Jason.decode!()

      if native?(mode) do
        assert payload["response_format"]["json_schema"]["schema"] == expected
        assert payload["response_format"]["json_schema"]["strict"] == false
        assert payload["tools"] in [nil, []]
        [response] = Enum.filter(result.messages, &match?(%Response{}, &1))
        assert Jason.decode!(Response.text(response)) == data
      else
        [tool] = payload["tools"]
        assert tool["function"]["parameters"]["properties"]["arguments"] == expected
        assert tool["function"]["parameters"]["required"] == ["arguments"]
        assert tool["function"]["strict"] in [nil, false]
        [response] = Enum.filter(result.messages, &match?(%Response{}, &1))

        assert [
                 %Part.ToolCall{
                   args: ^data,
                   metadata: %{"arguments_codec" => "exagent.arguments/1"}
                 }
               ] = Response.tool_calls(response)
      end

      if schema == Output do
        assert result.output.optional == Map.get(data, "optional", 7)
      end
    end
  end

  test "tool/native: changeset-only failure retries exactly once with history and qualified usage" do
    for mode <- [:tool, :native], surface <- [:sync, :stream_text, :stream] do
      {url, journal} =
        peer([reply(mode, %{"value" => "rejected"}), reply(mode, %{"value" => "accepted"})])

      agent = ExAgent.new(model: model(url), output: Output, output_mode: mode)
      assert {:ok, result} = execute(agent, surface, [])
      assert result.output.value == "accepted"
      assert result.request_count == 2
      assert result.usage.accounting["quality"] == "normalized"
      assert result.usage.input_tokens == 6
      assert result.usage.output_tokens == 4
      assert result.tool_calls == 0
      [_, second] = Agent.get(journal, & &1)

      assert Enum.any?(second["messages"], fn m ->
               Jason.encode!(m) =~ "conditional Ecto rule"
             end)

      [assistant] = Enum.filter(second["messages"], &(&1["role"] == "assistant"))

      if native?(mode) do
        assert Jason.decode!(assistant["content"]) == %{"value" => "rejected"}
      else
        [call] = assistant["tool_calls"]

        assert Jason.decode!(call["function"]["arguments"]) == %{
                 "arguments" => %{"value" => "rejected"}
               }
      end

      assert {:ok, restored} = result.messages |> Message.to_json() |> Message.from_json()
      assert restored == result.messages
    end
  end

  test "native never repairs invalid object, null, embeds or incomplete/refused output" do
    for surface <- [:sync, :stream_text, :stream],
        content <- [
          "[]",
          "[{}]",
          "null",
          "1",
          "true",
          "\"text\"",
          "{",
          ~s({"child":[]}),
          ~s({"children":null})
        ] do
      {url, journal} = peer([%{text: content}])

      agent =
        ExAgent.new(model: model(url), output: Output, output_mode: :native, output_retries: 0)

      assert {:error, %RunError{partial: partial}} = execute(agent, surface, [])
      assert partial.request_count == 1
      assert length(Agent.get(journal, & &1)) == 1
    end

    for surface <- [:sync, :stream], finish <- ["length", "content_filter", "unknown"] do
      {url, _} = peer([%{text: "{}", finish: finish}])
      agent = ExAgent.new(model: model(url), output: Empty, output_mode: :native)
      assert {:error, %RunError{}} = execute(agent, surface, [])
    end

    for surface <- [:sync, :stream] do
      {url, _} = peer([%{text: nil, refusal: "cannot comply"}])

      agent =
        ExAgent.new(model: model(url), output: Empty, output_mode: :native, output_retries: 0)

      assert {:error, %RunError{}} = execute(agent, surface, [])
    end

    {url, _} = peer([%{text: "{}", eof: true}])
    agent = ExAgent.new(model: model(url), output: Empty, output_mode: :native)
    assert {:error, %RunError{}} = execute(agent, :stream, [])
  end

  test "native missing profile and unrepresentable schema reject before transport" do
    owner = self()

    transport = fn _ ->
      send(owner, :io)
      raise "must not run"
    end

    base = %{
      model("https://fixture.invalid/v1")
      | http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
    }

    agent = ExAgent.new(model: %{base | output_profile: nil}, output: Empty, output_mode: :native)

    assert {:error,
            %RunError{reason: {:unsupported, :native_output}, partial: %{request_count: 0}}} =
             ExAgent.run(agent, "test")

    for schema <- [
          %{"$ref" => "#"},
          %{"type" => "object", "$defs" => %{}},
          %{"type" => "array"},
          %{"type" => "object", "properties" => %{"x" => %{"$ref" => "https://invalid/schema"}}}
        ] do
      params = %ModelRequestParameters{
        output_mode: :native,
        output_object: %{json_schema: schema, module: nil}
      }

      assert {:error, _} =
               Model.request(
                 base,
                 [Message.new_request([%Part.User{content: "test"}])],
                 %ModelSettings{},
                 params
               )
    end

    refute_receive :io

    params = %ModelRequestParameters{
      output_mode: :native,
      output_object: %{json_schema: %{type: "object", properties: %{}}, module: nil}
    }

    messages = [Message.new_request([%Part.User{content: "test"}])]

    for incompatible <- [
          %{base | output_profile: :unknown},
          %{base | tool_profile: nil},
          %{base | provider_options: [openai_json_schema_strict: true]},
          %{base | model: put_in(base.model, [:capabilities, :tools, :strict], true)},
          %{base | model: put_in(base.model, [:capabilities, :reasoning, :enabled], true)}
        ] do
      assert {:error, _} = Model.request(incompatible, messages, %ModelSettings{}, params)
    end

    assert {:error, _} =
             Model.request(base, messages, %ModelSettings{extra: %{strict: true}}, params)

    refute_receive :io
  end

  test "documented public-semantic limit: valid JSON survives a refusal field discarded by stock" do
    for surface <- [:sync, :stream] do
      {url, _} = peer([%{text: "{}", refusal: "synthetic refusal"}])
      agent = ExAgent.new(model: model(url), output: Empty, output_mode: :native)

      assert {:ok, %{output: %Empty{}, request_count: 1, tool_calls: 0}} =
               execute(agent, surface, [])
    end
  end

  test "host rejects a refusal retained in public response metadata before any sibling effect" do
    # Stock Chat drops the wire field, as characterized separately. This public
    # Req response-step fixture tests the host guard on an exposed signal; it
    # does not qualify wire-refusal fidelity or replace the stock/TCP gates.
    owner = self()

    transport = fn request ->
      request =
        Req.Request.append_response_steps(request,
          expose_refusal: fn {req, response} ->
            %ReqLLM.Response{} = backend = response.body
            backend = %{backend | provider_meta: %{refusal: "retained public refusal"}}
            assert ReqLLM.Response.refusals(backend) != []
            {req, %{response | body: backend}}
          end
        )

      {request,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: Jason.encode!(body(%{arguments: ~s({"arguments":{}}), name: "effect"}))
       )}
    end

    tool =
      ExAgent.Tool.new(
        name: "effect",
        takes_ctx: false,
        parameters_json_schema: %{type: "object", properties: %{}},
        call: fn _ -> send(owner, :refusal_effect) end
      )

    model = %{
      model("https://fixture.invalid/v1")
      | http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
    }

    agent = ExAgent.new(model: model, output: Empty, output_mode: :native, tools: [tool])

    assert {:error,
            %RunError{
              reason:
                {:model_request_failed,
                 %ExAgent.RequestError{reason: {:unsupported, :refused_output}}}
            }} = ExAgent.run(agent, "refused")

    refute_receive :refusal_effect
  end

  test "native with function tools preserves envelope, one effect, retry and next-turn continuation" do
    owner = self()

    tool =
      ExAgent.Tool.new(
        name: "effect",
        takes_ctx: false,
        parameters_json_schema: %{type: "object", properties: %{}, additionalProperties: false},
        call: fn args ->
          send(owner, {:effect, args})
          "confirmed"
        end
      )

    for surface <- [:sync, :stream_text, :stream] do
      {url, journal} =
        peer([
          %{arguments: ~s({"arguments":{}}), name: "effect", empty_start: true},
          reply(:native, %{"value" => "rejected"}),
          reply(:native, %{"value" => "accepted"}),
          reply(:native, %{"value" => "accepted", "child" => nil})
        ])

      agent = ExAgent.new(model: model(url), output: Output, output_mode: :native, tools: [tool])
      assert {:ok, result} = execute(agent, surface, [])
      assert result.request_count == 3
      assert result.tool_calls == 1
      assert result.usage.input_tokens == 9
      assert_receive {:effect, %{}}
      refute_receive {:effect, _}, 10
      assert {:ok, history} = result.messages |> Message.to_json() |> Message.from_json()
      assert {:ok, continued} = execute(agent, surface, message_history: history)
      assert continued.request_count == 1
      refute_receive {:effect, _}, 10
      [first, second, third, fourth] = Agent.get(journal, & &1)

      for payload <- [first, second, third, fourth] do
        assert payload["response_format"]["json_schema"]["strict"] == false
        assert [function] = payload["tools"]
        assert function["function"]["name"] == "effect"
        assert function["function"]["parameters"]["required"] == ["arguments"]
        assert payload["tool_choice"] == "auto"
      end

      [prior_call | _] = Enum.filter(fourth["messages"], &Map.has_key?(&1, "tool_calls"))
      assert [call] = prior_call["tool_calls"]
      assert Jason.decode!(call["function"]["arguments"]) == %{"arguments" => %{}}
    end
  end

  test "invalid tool envelope beside native output never authorizes an effect" do
    owner = self()

    tool =
      ExAgent.Tool.new(
        name: "effect",
        takes_ctx: false,
        parameters_json_schema: %{type: "object", properties: %{}},
        call: fn _ -> send(owner, :effect) end
      )

    for surface <- [:sync, :stream],
        arguments <- ["[]", "null", "{}", ~s({"arguments":[]}), ~s({"arguments":)] do
      {url, _} = peer([%{arguments: arguments, name: "effect"}])
      agent = ExAgent.new(model: model(url), output: Empty, output_mode: :native, tools: [tool])
      assert {:error, %RunError{}} = execute(agent, surface, [])
      refute_receive :effect, 10
    end
  end

  test "retry exhaustion and host request limit preserve counted partials" do
    for mode <- [:tool, :native], surface <- [:sync, :stream] do
      {url, journal} =
        peer([reply(mode, %{"value" => "rejected"}), reply(mode, %{"value" => "rejected"})])

      agent = ExAgent.new(model: model(url), output: Output, output_mode: mode, output_retries: 1)

      assert {:error,
              %RunError{
                reason: {:unexpected_model_behavior, {:output_retries_exhausted, _}},
                partial: partial
              }} = execute(agent, surface, [])

      assert partial.request_count == 2
      assert partial.usage.input_tokens == 6
      assert length(Agent.get(journal, & &1)) == 2

      {url, journal} = peer([reply(mode, %{"value" => "rejected"})])
      agent = %{agent | model: model(url), usage_limits: %ExAgent.UsageLimits{request_limit: 1}}
      assert {:error, %RunError{partial: partial}} = execute(agent, surface, [])
      assert partial.request_count == 1
      assert length(Agent.get(journal, & &1)) == 1
    end
  end

  defp reply(:native, data), do: %{text: Jason.encode!(data)}
  defp reply(:tool, data), do: %{arguments: Jason.encode!(%{arguments: data})}

  defp peer(replies) do
    journal = start_supervised!({Agent, fn -> [] end}, id: make_ref())

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn(fn ->
        Enum.each(replies, fn reply ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          payload = read_request(socket, "")
          Agent.update(journal, &(&1 ++ [payload]))
          bytes = if payload["stream"], do: stream_body(reply), else: Jason.encode!(body(reply))
          type = if payload["stream"], do: "text/event-stream", else: "application/json"

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n" <>
                bytes
            )

          :gen_tcp.close(socket)
        end)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(pid, :kill)
    end)

    {"http://127.0.0.1:#{port}/v1", journal}
  end

  defp body(reply) do
    message =
      if reply[:arguments],
        do: %{role: "assistant", content: nil, tool_calls: [call(reply.arguments, reply[:name])]},
        else: %{role: "assistant", content: reply[:text], refusal: reply[:refusal]}

    %{
      id: "r23",
      model: "r23-output",
      choices: [
        %{
          index: 0,
          message: message,
          finish_reason: reply[:finish] || if(reply[:arguments], do: "tool_calls", else: "stop")
        }
      ],
      usage: %{prompt_tokens: 3, completion_tokens: 2, total_tokens: 5}
    }
  end

  defp call(args, name),
    do: %{
      id: "output-call",
      type: "function",
      function: %{name: name || "final_result", arguments: args}
    }

  defp stream_body(reply) do
    delta =
      if reply[:arguments],
        do: %{tool_calls: [Map.put(call(reply.arguments, reply[:name]), :index, 0)]},
        else: %{content: reply[:text], refusal: reply[:refusal]}

    finish = reply[:finish] || if(reply[:arguments], do: "tool_calls", else: "stop")

    initial = frame(%{choices: [%{index: 0, delta: delta, finish_reason: nil}]})

    initial =
      if reply[:empty_start] do
        initial_call = Map.put(call("", reply[:name]), :index, 0)

        frame(%{choices: [%{index: 0, delta: %{tool_calls: [initial_call]}, finish_reason: nil}]}) <>
          frame(%{
            choices: [
              %{
                index: 0,
                delta: %{tool_calls: [%{index: 0, function: %{arguments: reply.arguments}}]},
                finish_reason: nil
              }
            ]
          })
      else
        initial
      end

    if reply[:eof] do
      initial
    else
      initial <>
        frame(%{
          choices: [%{index: 0, delta: %{}, finish_reason: finish}],
          usage: %{prompt_tokens: 3, completion_tokens: 2, total_tokens: 5}
        }) <> "data: [DONE]\n\n"
    end
  end

  defp frame(data),
    do: "data: " <> Jason.encode!(Map.merge(%{id: "r23", model: "r23-output"}, data)) <> "\n\n"

  defp read_request(socket, bytes) do
    case :binary.split(bytes, "\r\n\r\n") do
      [headers, body] ->
        [_, length] = Regex.run(~r/content-length: (\d+)/i, headers)
        missing = String.to_integer(length) - byte_size(body)

        if missing > 0 do
          {:ok, rest} = :gen_tcp.recv(socket, missing, 5000)
          Jason.decode!(body <> rest)
        else
          Jason.decode!(body)
        end

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
        read_request(socket, bytes <> more)
    end
  end
end
