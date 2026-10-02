defmodule ExAgent.ModelResolutionTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Message, Model, ModelRequestParameters, RequestError}
  alias ExAgent.Models.ReqLLM, as: Adapter

  @chat %{
    provider: :openai,
    id: "outside-catalogue",
    capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
    extra: %{wire: %{protocol: "openai_chat"}}
  }

  test "environment credentials never authorize an unconfigured instance" do
    for name <- [
          "OPENAI_API_KEY",
          "ANTHROPIC_API_KEY",
          "ANTHROPIC_AUTH_TOKEN",
          "ZAI_API_KEY",
          "OPENCODE_API_KEY"
        ] do
      previous = System.get_env(name)
      System.put_env(name, "synthetic-environment-only")

      on_exit(fn ->
        if previous, do: System.put_env(name, previous), else: System.delete_env(name)
      end)
    end

    for provider <- [:openai, :anthropic] do
      {:ok, model} = Model.resolve(%{provider: provider, id: "outside-catalogue"})
      assert model.api_key == nil
      assert model.auth_token == nil
      assert {:error, %RequestError{reason: :missing_credentials}} = request(model)
    end
  end

  test "custom/Test structs remain independent; stock specs use a single backend" do
    custom = %ExAgent.Models.Test{label: "custom-state", index: 2}
    assert {:ok, ^custom} = Model.resolve(custom)
    assert {:ok, %ExAgent.Models.Test{label: "label"}} = Model.resolve("test:label")
    assert {:ok, %ExAgent.Models.Test{}} = Model.resolve("test")
    assert {:error, :custom_model_options} = Model.resolve(custom, api_key: "synthetic")

    for spec <- ["openai:gpt-4o", {:openai, id: "gpt-4o"}, @chat, ReqLLM.model!(@chat)] do
      assert {:ok, %Adapter{} = model} = Model.resolve(spec, api_key: "synthetic")
      assert model.api_key == "synthetic"
      assert Model.system(model) == "openai"
      refute Model.profile(model).supports_tools
    end

    assert {:ok, model} = Model.resolve(@chat, tool_profile: :chat_tools_v1)
    assert Model.profile(model).supports_tools
    assert Model.model_name(model) == "outside-catalogue"
    assert {:error, %RequestError{reason: :missing_credentials}} = request(model)
    assert {:error, :invalid_model_spec_or_options} = Model.resolve("unknown-provider:missing")
    assert {:error, :invalid_model_spec_or_options} = Model.resolve(@chat, model: "override")
    assert {:error, :invalid_model_spec_or_options} = Model.resolve(@chat, headers: [])

    assert {:error, :invalid_model_spec_or_options} =
             Model.resolve(@chat, api_key: "a", api_key: "b")

    assert {:error, :invalid_model_spec_or_options} =
             Model.resolve({:openai, "gpt-4o", [base_url: "http://ignored.invalid"]})

    assert {:error, :invalid_model_spec_or_options} =
             Model.resolve({:openai, id: "gpt-4o", model: "other"})

    assert {:ok, %Adapter{}} = Model.resolve({:openai, "gpt-4o", []})
  end

  test "shortcuts never reinterpret endpoint, plan, model or tool qualification" do
    assert {:error, {:explicit_model_required, :opencode}} = Model.resolve("opencode:slug")
    assert {:ok, stock_zai} = Model.resolve("zai:glm-4.5-air")
    assert Model.system(stock_zai) == "zai"
    assert stock_zai.base_url == nil
    refute Model.profile(stock_zai).supports_tools
    assert {:ok, dynamic_zai} = Model.resolve(%{provider: :zai, id: "outside-catalogue"})
    assert Model.system(dynamic_zai) == "zai"
    assert Model.model_name(dynamic_zai) == "outside-catalogue"

    for spec <- [
          %{provider: :openrouter, id: "openai/gpt-4o"},
          %{provider: :openai, id: "gpt-4o"},
          put_in(@chat, [:capabilities, :reasoning, :enabled], true),
          put_in(@chat, [:extra, :wire, :protocol], "openai_responses")
        ] do
      assert {:ok, model} =
               Model.resolve(spec, api_key: "synthetic", tool_profile: :chat_tools_v1)

      refute Model.profile(model).supports_tools
      assert {:error, %RequestError{reason: {:unsupported, :tool_profile}}} = request(model)
    end
  end

  test "stock HTTP bearer and x-api-key preserve instance precedence and exact gateway path" do
    for {provider, prefix, opts, expected_header} <- [
          {:openai, "/zen/go/v1", [api_key: "go-instance"], "authorization: Bearer go-instance"},
          {:openai, "/zen/v1", [api_key: "zen-instance"], "authorization: Bearer zen-instance"},
          {:openrouter, "/api/v1", [api_key: "router-instance"],
           "authorization: Bearer router-instance"},
          {:anthropic, "/api/anthropic", [api_key: "ignored", auth_token: "zai-instance"],
           "authorization: Bearer zai-instance"},
          {:anthropic, "", [api_key: "anthropic-instance"], "x-api-key: anthropic-instance"}
        ] do
      url = peer(provider, prefix)
      id = if provider == :openrouter, do: "openai/exact-slug", else: "exact-slug"
      spec = %{provider: provider, id: id, capabilities: %{reasoning: %{enabled: false}}}
      assert {:ok, model} = Model.resolve(spec, opts ++ [base_url: url])
      assert {:ok, response, ^model} = request(model)
      assert Message.Response.text(response) == "ok"
      history = Message.to_json([response])
      for credential <- Keyword.values(opts), do: refute(history =~ credential)
      assert_receive {:request, headers, body}, 1000
      path = if provider == :anthropic, do: "/v1/messages", else: "/chat/completions"
      assert headers =~ "POST #{prefix}#{path} HTTP/1.1"
      assert headers =~ expected_header
      assert body["model"] == id
      refute headers =~ "ignored"
      refute headers =~ "beta=true"
      refute headers =~ "x-app:"
      if provider != :anthropic or opts[:auth_token], do: refute(headers =~ "x-api-key:")
      if provider == :anthropic and !opts[:auth_token], do: refute(headers =~ "authorization:")
      refute inspect(model) =~ Keyword.get(opts, :api_key, "never-disclose")
      if opts[:auth_token], do: refute(inspect(model) =~ opts[:auth_token])
    end
  end

  test "public authentication errors do not reflect response secrets or credential fields" do
    secret = "synthetic-auth-secret"

    url =
      peer(:anthropic, "/api/anthropic", fn _ ->
        body =
          Jason.encode!(%{
            "type" => "error",
            "error" => %{"type" => "authentication_error", "message" => secret}
          })

        "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
          body
      end)

    model =
      Adapter.new(
        model: %{
          provider: :anthropic,
          id: "exact-slug",
          capabilities: %{reasoning: %{enabled: false}}
        },
        auth_token: secret,
        base_url: url
      )

    assert {:error, %RequestError{status: 401, provider: :anthropic} = error} = request(model)
    refute inspect(error) =~ secret
    assert error.body == nil
    assert error.model == nil
    refute inspect(model) =~ secret
    assert_receive {:request, headers, _}
    assert headers =~ "authorization: Bearer " <> secret
  end

  test "auth cannot be overridden through settings or provider options; invalid modes fail preIO" do
    model = Adapter.new(model: @chat, api_key: "synthetic", auth_token: "wrong-provider")
    assert {:error, %RequestError{reason: {:unsupported, :auth_token}}} = request(model)

    for opts <- [[access_token: "override"], [auth_mode: :oauth], [api_key: "override"]] do
      model = %{model | auth_token: nil, provider_options: opts}

      assert {:error, %RequestError{reason: {:unsupported_options, :provider_options}}} =
               request(model)
    end

    assert {:error, %RequestError{reason: :missing_credentials}} =
             request(%{model | auth_token: ""})
  end

  test "HTTP chunk-size garbage cannot authorize buffered or streamed tools; valid extensions work" do
    for mode <- [:buffered, :stream], size <- ["5ZZZZZ", "5 9", "0ZZZZ"] do
      url =
        peer(:openai, "/v1", fn _ ->
          "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n" <>
            size <> "\r\nhello\r\n0\r\n\r\n"
        end)

      model =
        Adapter.new(
          model: @chat,
          api_key: "synthetic",
          base_url: url,
          tool_profile: :chat_tools_v1
        )

      effects = :atomics.new(1, [])

      tool =
        ExAgent.Tool.new(
          name: "effect",
          parameters_json_schema: %{"type" => "object", "properties" => %{}},
          takes_ctx: false,
          call: fn _ -> :atomics.add(effects, 1, 1) end
        )

      agent = ExAgent.new(model: model, tools: [tool])

      assert {:error, %ExAgent.RunError{}} =
               ExAgent.run(agent, "go", stream_text: mode == :stream)

      assert :atomics.get(effects, 1) == 0
      assert_receive {:request, _, _}
    end

    url =
      peer(:openai, "/v1", fn response ->
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n" <>
          Integer.to_string(byte_size(response), 16) <>
          ";name=value\r\n" <> response <> "\r\n0\r\n\r\n"
      end)

    assert {:ok, response, _} =
             request(Adapter.new(model: @chat, api_key: "synthetic", base_url: url))

    assert Message.Response.text(response) == "ok"
    assert_receive {:request, _, _}
  end

  test "malformed JSON and missing provider terminal return public errors without tool effects" do
    for body <- [
          "{",
          "null",
          "[]",
          Jason.encode!(%{"choices" => []}),
          Jason.encode!(%{"model" => "exact-slug"})
        ] do
      url =
        peer(:openai, "/v1", fn _ ->
          "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
            body
        end)

      model =
        Adapter.new(
          model: @chat,
          api_key: "synthetic",
          base_url: url,
          tool_profile: :chat_tools_v1
        )

      effects = :atomics.new(1, [])

      tool =
        ExAgent.Tool.new(
          name: "effect",
          parameters_json_schema: %{"type" => "object"},
          takes_ctx: false,
          call: fn _ -> :atomics.add(effects, 1, 1) end
        )

      assert {:error, %ExAgent.RunError{}} =
               ExAgent.run(ExAgent.new(model: model, tools: [tool]), "go")

      assert :atomics.get(effects, 1) == 0
      assert_receive {:request, _, _}
    end
  end

  defp request(model) do
    Model.request(
      model,
      [Message.new_request([%Message.Part.User{content: "synthetic"}])],
      nil,
      %ModelRequestParameters{}
    )
  end

  defp peer(provider, prefix, wire \\ nil) do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 3000)
        {headers, body} = receive_request(socket, "")
        send(owner, {:request, headers, Jason.decode!(body)})

        response =
          if provider == :anthropic do
            %{
              "id" => "auth",
              "type" => "message",
              "role" => "assistant",
              "model" => "exact-slug",
              "content" => [%{"type" => "text", "text" => "ok"}],
              "stop_reason" => "end_turn",
              "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
            }
          else
            %{
              "id" => "auth",
              "model" => "exact-slug",
              "choices" => [
                %{
                  "index" => 0,
                  "message" => %{"role" => "assistant", "content" => "ok"},
                  "finish_reason" => "stop"
                }
              ]
            }
          end
          |> Jason.encode!()

        bytes =
          if wire,
            do: wire.(response),
            else:
              "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(response)}\r\nConnection: close\r\n\r\n" <>
                response

        :ok = :gen_tcp.send(socket, bytes)

        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    "http://127.0.0.1:#{port}#{prefix}"
  end

  defp receive_request(socket, buffer) do
    case String.split(buffer, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length: (\d+)/i, headers)
        length = String.to_integer(size)
        if byte_size(body) >= length, do: {headers, body}, else: receive_more(socket, buffer)

      _ ->
        receive_more(socket, buffer)
    end
  end

  defp receive_more(socket, buffer) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 3000)
    receive_request(socket, buffer <> chunk)
  end
end
