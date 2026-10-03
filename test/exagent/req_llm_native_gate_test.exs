defmodule ExAgent.ReqLLMNativeGateTest do
  use ExUnit.Case, async: false

  @schema %{
    "type" => "object",
    "properties" => %{
      "name" => %{"type" => "string"},
      "optional" => %{"anyOf" => [%{"type" => "integer", "default" => 7}, %{"type" => "null"}]},
      "child" => %{"type" => "object", "properties" => %{}, "required" => []}
    },
    "required" => ["name"]
  }

  defp spec do
    %{
      provider: :openai,
      id: "native-gate",
      extra: %{wire: %{protocol: "openai_chat"}},
      capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
    }
  end

  defp opts do
    [
      api_key: "synthetic",
      max_retries: 0,
      json_repair: false,
      provider_options: [
        response_format: %{
          type: "json_schema",
          json_schema: %{name: "result", strict: false, schema: @schema}
        },
        openai_parallel_tool_calls: false
      ]
    ]
  end

  defp assert_payload(payload) do
    assert payload["response_format"] == %{
             "type" => "json_schema",
             "json_schema" => %{"name" => "result", "strict" => false, "schema" => @schema}
           }

    assert payload["tools"] in [nil, []]
    # Stock omits false through its option precedence; with no tools this flag
    # is immaterial, and the gate records the actual emitted payload.
    assert payload["parallel_tool_calls"] == nil
  end

  test "public buffered native format preserves schema and invalid JSON without repair" do
    owner = self()

    for text <- [
          ~s({"name":"Ada","optional":null,"child":{}}),
          ~s({"name":"Ada"}),
          "{}",
          "[]",
          "null",
          ~s({"name":)
        ] do
      adapter = fn req ->
        send(owner, {:payload, Jason.decode!(IO.iodata_to_binary(req.body))})

        body = %{
          id: "native",
          model: "native-gate",
          choices: [
            %{index: 0, message: %{role: "assistant", content: text}, finish_reason: "stop"}
          ]
        }

        {req,
         Req.Response.new(
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: Jason.encode!(body)
         )}
      end

      assert {:ok, response} =
               ReqLLM.generate_text(
                 spec(),
                 "synthetic",
                 opts() ++ [req_http_options: [adapter: ExAgent.Test.ReqTransport.bind(adapter)]]
               )

      assert ReqLLM.Response.text(response) == text
      assert ReqLLM.Response.tool_calls(response) == []
      assert_receive {:payload, payload}
      assert_payload(payload)
      refute_receive {:payload, _}, 10
    end
  end

  test "public one-view TCP streaming preserves native format, text and terminal" do
    for text <- [~s({"name":"Ada","optional":null,"child":{}}), "{}", "[]", "null", ~s({"name":)] do
      check_stream(text)
    end
  end

  test "stock Chat loses refusal alongside valid content in buffered and streaming public projections" do
    assert buffered_refusal(nil) == buffered_refusal("synthetic refusal")
    assert check_stream("{}", nil) == check_stream("{}", "synthetic refusal")
  end

  defp buffered_refusal(refusal) do
    adapter = fn req ->
      body = %{
        id: "native",
        model: "native-gate",
        choices: [
          %{
            index: 0,
            message: %{role: "assistant", content: "{}", refusal: refusal},
            finish_reason: "stop"
          }
        ]
      }

      {req,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: Jason.encode!(body)
       )}
    end

    assert {:ok, response} =
             ReqLLM.generate_text(
               spec(),
               "synthetic",
               opts() ++ [req_http_options: [adapter: ExAgent.Test.ReqTransport.bind(adapter)]]
             )

    assert ReqLLM.Response.text(response) == "{}"
    assert ReqLLM.Response.refusals(response) == []
    public_projection(response)
  end

  defp check_stream(text, refusal \\ nil) do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    peer =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        send(owner, {:payload, read_request(socket, "")})

        frames =
          frame(%{refusal: refusal}, nil) <>
            Enum.map_join(String.codepoints(text), &frame(%{content: &1}, nil))

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n" <>
              frames <> frame(%{}, "stop") <> "data: [DONE]\n\n"
          )

        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(peer, :kill)
    end)

    assert {:ok, stream} =
             ReqLLM.stream_text(
               spec(),
               "synthetic",
               opts() ++ [base_url: "http://127.0.0.1:#{port}/v1", receive_timeout: 5000]
             )

    monitor = Process.monitor(stream.metadata_handle)

    assert {:ok, response} =
             ReqLLM.StreamResponse.process_stream(stream,
               on_chunk: fn chunk -> send(owner, {:chunk, chunk}) end
             )

    # Stock's public stream Response exposes JSON objects as object content,
    # unlike buffered text. This is semantic preservation, not raw fidelity.
    case Jason.decode(text) do
      {:ok, object} when is_map(object) ->
        assert response.object == object
        assert [%{type: :object, object: ^object}] = response.message.content

      _ ->
        assert response.object == nil
        assert ReqLLM.Response.text(response) == text
    end

    assert response.finish_reason == :stop
    assert ReqLLM.Response.tool_calls(response) == []
    assert_receive {:payload, payload}
    assert_payload(payload)
    assert payload["stream"] == true
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert ReqLLM.Response.refusals(response) == []
    public_projection(response)
  end

  defp public_projection(response) do
    %{
      content: response.message.content,
      metadata: response.message.metadata,
      provider_meta: response.provider_meta,
      finish_reason: response.finish_reason,
      refusals: ReqLLM.Response.refusals(response),
      object: response.object,
      output_items: ReqLLM.Response.output_items(response)
    }
  end

  defp frame(delta, finish),
    do:
      "data: " <>
        Jason.encode!(%{
          id: "native",
          model: "native-gate",
          choices: [%{index: 0, delta: delta, finish_reason: finish}]
        }) <> "\n\n"

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
