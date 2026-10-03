defmodule ExAgent.ReqLLMNoneTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Message, Model, ModelRequestParameters, ModelSettings, Tool}
  alias ExAgent.Models.ReqLLM, as: Adapter

  defmodule EmptyOutput do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
    end

    def changeset(data, attrs), do: Ecto.Changeset.cast(data, attrs, [])
  end

  defp model(url) do
    Adapter.new(
      model: %{
        provider: :openai,
        id: "none-fixture",
        extra: %{wire: %{protocol: "openai_chat"}},
        capabilities: %{
          tools: %{enabled: true},
          reasoning: %{
            enabled: true,
            effort: %{supported: true, values: ["high", "none"]},
            thinking: %{supported: true, disable_supported: true}
          }
        }
      },
      api_key: "synthetic",
      base_url: url,
      tool_profile: :chat_tools_v1,
      total_timeout: 8000
    )
    |> Map.put(:reasoning_mode, :none)
  end

  defp tool do
    owner = self()

    Tool.new(
      name: "effect",
      parameters_json_schema: %{
        "type" => "object",
        "properties" => %{"value" => %{"type" => "integer"}},
        "required" => ["value"],
        "additionalProperties" => false
      },
      call: fn ctx, args ->
        send(owner, {:effect, ctx.tool_call_id, args})
        "receipt"
      end
    )
  end

  for stream? <- [false, true] do
    @stream stream?
    test "explicit none public execution maps bounded settings and preserves history: #{@stream}" do
      {url, peer} = peer([:tool, :text])

      agent =
        ExAgent.new(model: model(url), tools: [tool()], model_settings: [max_tokens: 256])

      assert {:ok, result} = ExAgent.run(agent, "go", stream_text: @stream)
      assert result.output == "done" and result.request_count == 2 and result.tool_calls == 1
      assert_receive {:effect, "none-call", %{"value" => 7}}
      refute_receive {:effect, _, _}, 0
      assert_receive {:request, ^peer, 0, first}
      assert first["reasoning_effort"] == "none"
      assert first["max_completion_tokens"] == 256
      refute Map.has_key?(first, "max_tokens")
      refute Map.has_key?(first, "temperature")
      assert_receive {:request, ^peer, 1, second}
      assistant = Enum.find(second["messages"], &(&1["role"] == "assistant"))

      assert [%{"id" => "none-call", "function" => %{"arguments" => args}}] =
               assistant["tool_calls"]

      assert Jason.decode!(args) == %{"arguments" => %{"value" => 7}}

      for %Message.Response{continuation: continuation} <- result.messages do
        assert continuation["version"] == 3
        assert continuation["reasoning_mode"] == "none"
      end

      assert Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages}
      refute_receive {:request, ^peer, _, _}, 0
    end
  end

  test "none requires truthful explicit disable/effort capabilities and rejects configuration before IO" do
    {url, peer} = peer(List.duplicate(:text, 40))
    base = model(url)

    invalid = [
      %{base | reasoning_mode: :low},
      %{base | reasoning_mode: nil},
      %{base | tool_profile: nil},
      put_in(base.model.capabilities.reasoning.enabled, false),
      put_in(base.model.capabilities.reasoning.effort.supported, false),
      put_in(base.model.capabilities.reasoning.effort.values, ["high", "low"]),
      put_in(base.model.capabilities.reasoning.thinking.disable_supported, false),
      %{base | provider_options: [max_completion_tokens: 1]},
      %{base | provider_options: [reasoning_effort: :none]}
    ]

    for bad <- invalid do
      assert {:error, _} = Model.request(bad, [], %ModelSettings{}, %ModelRequestParameters{})

      assert [{:error, _}] =
               Model.request_stream(bad, [], %ModelSettings{}, %ModelRequestParameters{})
               |> Enum.to_list()
    end

    for settings <- [
          %ModelSettings{temperature: 0.0},
          %ModelSettings{max_tokens: 0},
          %ModelSettings{max_tokens: 4097},
          %ModelSettings{max_tokens: 1.5},
          %ModelSettings{extra: %{reasoning: %{enabled: false}}}
        ] do
      assert {:error, _} = Model.request(base, [], settings, %ModelRequestParameters{})

      assert [{:error, _}] =
               Model.request_stream(base, [], settings, %ModelRequestParameters{})
               |> Enum.to_list()
    end

    refute_receive {:request, ^peer, _, _}, 0
    refute_receive {:effect, _, _}, 0
  end

  test "none mode binding is normalized, nonsecret, order-independent and sensitive to target/config" do
    base = model("https://fixture.invalid/v1")
    assert {:ok, binding} = Model.continuation_binding(base)
    assert binding["reasoning_mode"] == "none" and binding["version"] == 1
    refute Jason.encode!(binding) =~ "synthetic"

    assert Model.continuation_binding(
             put_in(base.model.capabilities.reasoning.effort.values, ["none", "high", "none"])
           ) == {:ok, binding}

    assert Model.continuation_binding(%{base | api_key: "different-secret"}) == {:ok, binding}

    for changed <- [
          %{base | base_url: "https://other.invalid/v1"},
          put_in(base.model.id, "other"),
          %{base | output_profile: :chat_json_schema_v1},
          %{base | reasoning_mode: nil}
        ] do
      refute Model.continuation_binding(changed) == {:ok, binding}
    end

    assert {:error, _} =
             Model.continuation_binding(
               put_in(base.model.capabilities.reasoning.thinking.disable_supported, false)
             )

    for endpoint <- [
          "https://user:password" <> "@" <> "fixture.invalid/v1",
          "https://fixture.invalid/v1?key=synthetic"
        ] do
      assert {:error, :invalid_model_continuation_binding} =
               Model.continuation_binding(%{base | base_url: endpoint})
    end

    refute Model.profile(base).supports_thinking
    assert Model.profile(base).supports_tools
  end

  test "message v3 requires the same effective mode; legacy and downcast history reject before IO" do
    {url, peer} = peer([:text])
    base = model(url)

    assert {:ok, response, _} =
             Model.request(base, [], %ModelSettings{}, %ModelRequestParameters{})

    assert_receive {:request, ^peer, 0, payload}
    assert payload["max_completion_tokens"] == 4096

    legacy = %{
      response
      | continuation:
          response.continuation |> Map.delete("reasoning_mode") |> Map.put("version", 2)
    }

    default = %{put_in(base.model.capabilities.reasoning.enabled, false) | reasoning_mode: nil}

    for {candidate, previous} <- [
          {base, legacy},
          {base, %{response | continuation: nil}},
          {default, response}
        ] do
      assert {:error, %ExAgent.RequestError{reason: :continuation_mode_mismatch}} =
               Model.request(candidate, [previous], %ModelSettings{}, %ModelRequestParameters{})
    end

    refute_receive {:request, ^peer, _, _}, 0
  end

  test "native empty Ecto output uses none and the same bounded token authority on both surfaces" do
    for stream? <- [false, true] do
      {url, peer} = peer(["{}"])

      agent =
        ExAgent.new(
          model: %{model(url) | output_profile: :chat_json_schema_v1},
          output: EmptyOutput,
          output_mode: :native
        )

      assert {:ok, %{output: %EmptyOutput{}, request_count: 1}} =
               ExAgent.run(agent, "go", stream_text: stream?)

      assert_receive {:request, ^peer, 0, payload}
      assert payload["response_format"]["type"] == "json_schema"
      assert payload["reasoning_effort"] == "none"
      assert payload["max_completion_tokens"] == 4096
      refute Map.has_key?(payload, "max_tokens")
      refute_receive {:effect, _, _}, 0
    end
  end

  for routing_mode <- [:openai_none, :openrouter_none, :openrouter_disabled] do
    @routing_mode routing_mode
    test "#{routing_mode} approval resume binds configuration with an empty app codec" do
      {store, config} = continuation()
      {url, peer} = peer([:tool, :text])
      base = routed_model(model(url), @routing_mode)
      agent = ExAgent.new(model: base, tools: [tool()])

      opts = [
        continuation: config,
        stream_text: true,
        permissions: ExAgent.Permissions.new!(default: :ask)
      ]

      assert {:ok, %{status: :paused} = paused} = ExAgent.run(agent, "go", opts)
      assert_receive {:request, ^peer, 0, _}
      refute_receive {:effect, _, _}, 0
      {:ok, %{record: record}} = ExAgent.Continuation.get(store, "conversation")

      assert record["execution"]["progress"]["runtime"]["model_binding"]["reasoning_mode"] ==
               if(@routing_mode == :openrouter_disabled, do: "disabled", else: "none")

      [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

      {:ok, %{record: approved}} =
        ExAgent.Continuation.decide(
          store,
          "conversation",
          :approve,
          admin(record, "approve") ++ [approval_id: id, payload_hash: approval["payload_hash"]]
        )

      reference = %{paused.continuation | revision: approved["revision"]}
      assert_changed_before_claim(agent, base, reference, config, store, approved)

      assert {:ok, %{status: :succeeded, request_count: 2, tool_calls: 1} = result} =
               ExAgent.resume(agent, reference, opts)

      assert_receive {:effect, "none-call", %{"value" => 7}}
      assert_receive {:request, ^peer, 1, _}
      assert Message.from_json(Message.to_json(result.messages)) == {:ok, result.messages}
      assert {:error, _} = ExAgent.resume(agent, reference, opts)
      refute_receive {:effect, _, _}, 0
      refute_receive {:request, ^peer, _, _}, 0
    end

    test "#{routing_mode} first uncertain request binds configuration before any response" do
      {store, config} = continuation()
      config = %{config | lease_ms: 200}
      {url, peer} = peer([:block, :text])
      base = routed_model(model(url), @routing_mode)
      agent = ExAgent.new(model: base)
      {:ok, runner} = Task.start(fn -> ExAgent.run(agent, "go", continuation: config) end)
      assert_receive {:request, ^peer, 0, _}, 5000
      monitor = Process.monitor(runner)
      Process.exit(runner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^runner, :killed}
      {:ok, %{record: record}} = ExAgent.Continuation.get(store, "conversation")

      Process.sleep(
        max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)
      )

      {:ok, %{record: record}} =
        ExAgent.Continuation.recover(store, "conversation", admin(record, "recover"))

      {:ok, history} = Message.from_json(record["snapshot"]["message_history"])
      refute Enum.any?(history, &match?(%Message.Response{}, &1))
      {:ok, %{retryable_effects: [binding]}} = ExAgent.Continuation.get(store, "conversation")

      retry_opts = [
        operation_id: "retry",
        actor: :host,
        authorize: fn :host, _, _ -> {:ok, "operator"} end,
        idempotency_key: "none-key",
        accept_duplicate_risk: true
      ]

      assert {:error, _} =
               ExAgent.Continuation.retry_effect(
                 store,
                 "conversation",
                 binding,
                 Keyword.put(retry_opts, :authorize, fn _, _, _ -> :deny end)
               )

      {:ok, %{record: authorized}} =
        ExAgent.Continuation.retry_effect(store, "conversation", binding, retry_opts)

      reference = %{
        id: "conversation",
        record_id: authorized["record_id"],
        revision: authorized["revision"]
      }

      assert_changed_before_claim(agent, base, reference, config, store, authorized)

      assert {:ok, %{output: "done", request_count: 2, tool_calls: 0}} =
               ExAgent.resume(agent, reference, continuation: config)

      assert_receive {:request, ^peer, 1, payload}

      if base.reasoning_mode == :none,
        do: assert(payload["reasoning_effort"] == "none"),
        else: refute(Map.has_key?(payload, "reasoning_effort"))

      refute_receive {:request, ^peer, _, _}, 0
      refute_receive {:effect, _, _}, 0
    end
  end

  defp routed_model(model, :openai_none), do: model

  defp routed_model(model, mode) do
    model = %{
      model
      | tool_profile: :openrouter_chat_tools_v1,
        provider_options: [openrouter_provider: %{only: ["decart"], allow_fallbacks: false}]
    }

    model = put_in(model.model.provider, :openrouter)

    if mode == :openrouter_disabled,
      do: %{put_in(model.model.capabilities.reasoning, %{enabled: false}) | reasoning_mode: nil},
      else: model
  end

  defp assert_changed_before_claim(agent, base, reference, config, store, record) do
    changed_models = [
      %{base | reasoning_mode: if(base.reasoning_mode, do: nil, else: :none)},
      %{base | base_url: "https://other.invalid/v1"},
      put_in(base.model.id, "other"),
      %{
        base
        | model: %{
            base.model
            | capabilities: %{tools: %{enabled: false}, reasoning: %{enabled: false}}
          }
      }
    ]

    changed_models =
      if base.tool_profile == :openrouter_chat_tools_v1,
        do: [
          %{base | provider_options: [openrouter_provider: %{only: ["io-net"]}]} | changed_models
        ],
        else: changed_models

    for changed <- changed_models do
      assert {:error, _} =
               ExAgent.resume(%{agent | model: changed}, reference, continuation: config)

      {:ok, %{record: unchanged}} = ExAgent.Continuation.get(store, "conversation")
      assert unchanged == record
      refute_receive :none_codec_load, 0
      refute_receive {:effect, _, _}, 0
    end
  end

  defp continuation do
    start_supervised!({ExAgent.Store.ETS, table: __MODULE__})
    store = ExAgent.Store.scoped({ExAgent.Store.ETS, __MODULE__}, "none")
    owner = self()

    config = %{
      store: store,
      id: "conversation",
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000,
      definition: %{"id" => "none", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      model_ref: %{"id" => "none-model", "version" => "1"},
      model_codec: %{
        dump: fn _ -> {:ok, %{}} end,
        load: fn model, %{} ->
          send(owner, :none_codec_load)
          {:ok, model}
        end
      }
    }

    {store, config}
  end

  defp admin(record, op),
    do: [
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: op,
      actor: :host,
      authorize: fn :host, _, _ -> {:ok, "operator"} end
    ]

  test "none Ecto-tool and empty-start arguments remain schema-authoritative with terminal/loss negatives" do
    for stream? <- [false, true] do
      {url, peer} =
        peer([%{args: ~s({"arguments":{}}), name: "final_result", finish: "tool_calls"}])

      agent = ExAgent.new(model: model(url), output: EmptyOutput, output_mode: :tool)

      assert {:ok, %{output: %EmptyOutput{}, request_count: 1}} =
               ExAgent.run(agent, "go", stream_text: stream?)

      assert_receive {:request, ^peer, 0, payload}
      assert payload["reasoning_effort"] == "none"
      assert payload["tool_choice"] == "required"
    end

    for reply <- [
          %{args: ~s({"arguments":{"value":7}}), name: "effect", finish: "length"},
          %{args: "[]", name: "effect", finish: "tool_calls"},
          :loss
        ] do
      {url, peer} = peer([reply])
      agent = ExAgent.new(model: model(url), tools: [tool()])

      assert {:error, %ExAgent.RunError{partial: %{request_count: 1}}} =
               ExAgent.run(agent, "go", stream_text: true)

      assert_receive {:request, ^peer, 0, %{"stream" => true}}
      refute_receive {:effect, _, _}, 0
      refute_receive {:request, ^peer, _, _}, 0
    end
  end

  test "none still rejects public reasoning continuation before a valid sibling tool effect" do
    owner = self()

    transport = fn request ->
      request =
        Req.Request.append_response_steps(request,
          exposed_reasoning: fn {req, response} ->
            backend = response.body

            {req,
             %{
               response
               | body: %{backend | message: %{backend.message | reasoning_details: [%{}]}}
             }}
          end
        )

      send(owner, :reasoning_request)
      {_, body} = wire(:tool, false)

      {request,
       Req.Response.new(status: 200, headers: [{"content-type", "application/json"}], body: body)}
    end

    base = %{
      model("https://fixture.invalid/v1")
      | http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
    }

    assert {:error,
            %ExAgent.RunError{
              reason:
                {:model_request_failed,
                 %ExAgent.RequestError{reason: {:unsupported, :tool_profile_content}}}
            }} = ExAgent.run(ExAgent.new(model: base, tools: [tool()]), "go")

    assert_receive :reasoning_request
    refute_receive {:effect, _, _}, 0
  end

  test "real public incomplete finish takes precedence over unprojectable tool arguments without effects" do
    valid = ~s({"arguments":{"value":7}})
    truncated = ~s({"arguments":{"value":)

    for stream? <- [false, true],
        {args, finish, expected, projected?} <- [
          {truncated, "length", {:incomplete_response, :length}, false},
          {valid, "length", {:incomplete_response, :length}, true},
          {truncated, "tool_calls", :invalid_tool_arguments, false},
          {truncated, "content_filter", {:incomplete_response, :content_filter}, false},
          {truncated, "unknown", {:incomplete_response, :error}, false}
        ] do
      {url, peer} =
        peer([
          %{
            args: args,
            name: "effect",
            finish: finish,
            usage: %{prompt_tokens: 3, completion_tokens: 16, total_tokens: 19}
          }
        ])

      agent = ExAgent.new(model: model(url), tools: [tool()], model_settings: [max_tokens: 16])

      assert {:error, %ExAgent.RunError{reason: {:model_request_failed, error}, partial: partial}} =
               ExAgent.run(agent, "go", stream_text: stream?)

      assert error.reason == expected
      assert partial.request_count == 1 and partial.tool_calls == 0

      if projected? do
        assert error.partial_response.finish_reason == :length
        assert error.partial_response.usage.input_tokens == 3
        assert error.partial_response.usage.output_tokens == 16

        assert [%Message.Part.ToolCall{args: %{"value" => 7}}] =
                 Message.Response.tool_calls(error.partial_response)
      else
        assert error.partial_response == nil
      end

      assert_receive {:request, ^peer, 0, payload}
      assert payload["stream"] == true == stream?
      refute_receive {:request, ^peer, _, _}, 0
      refute_receive {:effect, _, _}, 0
    end
  end

  defp peer(replies) do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    peer =
      spawn(fn ->
        Enum.with_index(replies, fn reply, index ->
          {:ok, socket} = :gen_tcp.accept(listener, 8000)
          request = read_request(socket, "")
          send(owner, {:request, self(), index, request})

          if reply == :block do
            {:error, :closed} = :gen_tcp.recv(socket, 0, 5000)
          else
            {kind, bytes} = wire(reply, request["stream"] == true)

            :ok =
              :gen_tcp.send(
                socket,
                "HTTP/1.1 200 OK\r\nContent-Type: #{kind}\r\nContent-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n" <>
                  bytes
              )

            :gen_tcp.close(socket)
          end
        end)

        :gen_tcp.close(listener)
      end)

    on_exit(fn ->
      Process.exit(peer, :kill)
      :gen_tcp.close(listener)
    end)

    {"http://127.0.0.1:#{port}/v1", peer}
  end

  defp call(args),
    do: %{id: "none-call", type: "function", function: %{name: "effect", arguments: args}}

  defp wire(%{args: args, name: name, finish: finish} = reply, false) do
    call = put_in(call(args), [:function, :name], name)

    {"application/json",
     Jason.encode!(
       %{
         id: "none",
         model: "none-fixture",
         choices: [
           %{
             index: 0,
             message: %{role: "assistant", content: nil, tool_calls: [call]},
             finish_reason: finish
           }
         ]
       }
       |> fixture_usage(reply)
     )}
  end

  defp wire(%{args: args, name: name, finish: finish} = reply, true) do
    initial = put_in(call(""), [:function, :name], name) |> Map.put(:index, 0)

    {"text/event-stream",
     frame(%{tool_calls: [initial]}) <>
       frame(%{tool_calls: [%{index: 0, function: %{arguments: args}}]}) <>
       frame(%{}, finish, reply[:usage]) <> "data: [DONE]\n\n"}
  end

  defp wire(:loss, true) do
    {"text/event-stream",
     frame(%{tool_calls: [Map.put(call(~s({"arguments":{"value":7}})), :index, 0)]}) <>
       frame(%{tool_calls: [%{index: 0, function: %{arguments: "!"}}]}) <>
       frame(%{}, "tool_calls") <> "data: [DONE]\n\n"}
  end

  defp wire(reply, false) do
    message =
      if reply == :tool,
        do: %{role: "assistant", content: nil, tool_calls: [call(~s({"arguments":{"value":7}}))]},
        else: %{role: "assistant", content: if(is_binary(reply), do: reply, else: "done")}

    {"application/json",
     Jason.encode!(%{
       id: "none",
       model: "none-fixture",
       choices: [
         %{
           index: 0,
           message: message,
           finish_reason: if(reply == :tool, do: "tool_calls", else: "stop")
         }
       ]
     })}
  end

  defp wire(reply, true) do
    initial =
      if reply == :tool do
        frame(%{tool_calls: [Map.put(call(""), :index, 0)]}) <>
          frame(%{
            tool_calls: [%{index: 0, function: %{arguments: ~s({"arguments":{"value":7}})}}]
          })
      else
        frame(%{content: if(is_binary(reply), do: reply, else: "done")})
      end

    {"text/event-stream",
     initial <>
       frame(%{}, if(reply == :tool, do: "tool_calls", else: "stop")) <> "data: [DONE]\n\n"}
  end

  defp fixture_usage(data, reply),
    do: if(Map.has_key?(reply, :usage), do: Map.put(data, :usage, reply.usage), else: data)

  defp frame(delta, finish \\ nil, usage \\ nil),
    do:
      "data: " <>
        Jason.encode!(
          %{
            id: "none",
            model: "none-fixture",
            choices: [%{index: 0, delta: delta, finish_reason: finish}]
          }
          |> then(fn data -> if usage, do: Map.put(data, :usage, usage), else: data end)
        ) <> "\n\n"

  defp read_request(socket, bytes) do
    case :binary.split(bytes, "\r\n\r\n") do
      [headers, body] ->
        [_, length] = Regex.run(~r/content-length: (\d+)/i, headers)
        missing = String.to_integer(length) - byte_size(body)

        if missing > 0 do
          {:ok, more} = :gen_tcp.recv(socket, missing, 5000)
          Jason.decode!(body <> more)
        else
          Jason.decode!(body)
        end

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
        read_request(socket, bytes <> more)
    end
  end
end
