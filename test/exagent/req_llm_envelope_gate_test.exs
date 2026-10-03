defmodule ExAgent.ReqLLMEnvelopeGateTest do
  use ExUnit.Case, async: false
  alias ExAgent.Tool

  @empty %{"type" => "object", "properties" => %{}, "additionalProperties" => false}
  @object %{
    "type" => "object",
    "properties" => %{"value" => %{"type" => "integer"}},
    "required" => ["value"],
    "additionalProperties" => false
  }
  @invalid [
    "[]",
    "[{}]",
    "null",
    "\"text\"",
    "1",
    "true",
    "false",
    "{}",
    "{\"arguments\":{}",
    "{\"arguments\":[]}",
    "{\"other\":{}}",
    "{\"arguments\":{},\"extra\":1}",
    "{\"arguments\":null}"
  ]

  defp spec do
    %{
      provider: :openai,
      id: "envelope-gate",
      extra: %{wire: %{protocol: "openai_chat"}},
      capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
    }
  end

  defp envelope(schema) do
    %{
      "type" => "object",
      "properties" => %{"arguments" => schema},
      "required" => ["arguments"],
      "additionalProperties" => false
    }
  end

  defp tools(schema) do
    owner = self()

    logical =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        parameters_json_schema: schema,
        call: fn args ->
          send(owner, {:effect, args})
          :ok
        end
      )

    {:ok, logical} = Tool.prepare(logical)
    {:ok, outer} = Tool.prepare(%{logical | parameters_json_schema: envelope(schema)})

    upstream =
      ReqLLM.Tool.new!(
        name: "effect",
        description: "Gate effect",
        strict: false,
        parameter_schema: envelope(schema),
        callback: fn _ ->
          send(owner, :upstream_callback)
          {:error, :noop}
        end
      )

    {logical, outer, upstream}
  end

  # This gate-only host boundary consumes public semantic arguments. It is not
  # installed in the adapter and cannot lift its admission guards.
  defp effect({:ok, response}, logical, outer) do
    with true <- response.finish_reason in [:stop, :tool_calls],
         [call] <- ReqLLM.Response.tool_calls(response),
         true <- call.id == "call-gate" and call.function.name == logical.name,
         false <- ReqLLM.ToolCall.builtin?(call) or ReqLLM.ToolCall.provider_native?(call),
         metadata = ReqLLM.ToolCall.metadata(call),
         false <- metadata[:invalid_arguments] == true or metadata["invalid_arguments"] == true,
         {:ok, decoded} <- Jason.decode(call.function.arguments),
         {:ok, %{"arguments" => args}} <- Tool.validate_args(outer, decoded),
         {:ok, ^args} <- Tool.validate_args(logical, args) do
      logical.call.(args)
      {:ok, call.id, args}
    else
      _ -> :rejected
    end
  end

  defp effect(_, _, _), do: :rejected

  defp body(arguments, finish) do
    %{
      "id" => "gate",
      "model" => "envelope-gate",
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              %{
                "id" => "call-gate",
                "type" => "function",
                "function" => %{"name" => "effect", "arguments" => arguments}
              }
            ]
          },
          "finish_reason" => finish
        }
      ]
    }
  end

  defp request(:buffered, arguments, finish, upstream) do
    owner = self()

    adapter = fn req ->
      send(owner, {:payload, Jason.decode!(IO.iodata_to_binary(req.body))})

      {req,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: Jason.encode!(body(arguments, finish))
       )}
    end

    ReqLLM.generate_text(spec(), "synthetic",
      api_key: "synthetic",
      base_url: "https://fixture.invalid/v1",
      tools: [upstream],
      max_retries: 0,
      json_repair: false,
      req_http_options: [adapter: ExAgent.Test.ReqTransport.bind(adapter)]
    )
  end

  defp request(mode, arguments, finish, upstream) when mode in [:stream, :fragmented] do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :raw,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(listener)

    peer =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        :gen_tcp.close(listener)
        payload = read_request(socket, "")
        send(owner, {:payload, Jason.decode!(payload)})

        call = %{
          "index" => 0,
          "id" => "call-gate",
          "type" => "function",
          "function" => %{"name" => "effect"}
        }

        bytes =
          if mode == :stream do
            frame(%{"tool_calls" => [put_in(call, ["function", "arguments"], arguments)]})
          else
            frame(%{"tool_calls" => [call]}) <>
              Enum.map_join(String.codepoints(arguments), fn fragment ->
                frame(%{
                  "tool_calls" => [%{"index" => 0, "function" => %{"arguments" => fragment}}]
                })
              end)
          end

        bytes = bytes <> if(finish, do: frame(%{}, finish) <> "data: [DONE]\n\n", else: "")

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n" <>
              bytes
          )

        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(peer, :kill)
    end)

    {:ok, stream} =
      ReqLLM.stream_text(spec(), "synthetic",
        api_key: "synthetic",
        base_url: "http://127.0.0.1:#{port}/v1",
        tools: [upstream],
        max_retries: 0,
        json_repair: false,
        receive_timeout: 5000,
        total_timeout: 8000
      )

    monitor = Process.monitor(stream.metadata_handle)

    result =
      ReqLLM.StreamResponse.process_stream(stream,
        on_chunk: fn chunk -> send(owner, {:public_chunk, chunk}) end
      )

    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    result
  end

  defp read_request(socket, bytes) do
    case :binary.split(bytes, "\r\n\r\n") do
      [headers, body] ->
        [_, length] = Regex.run(~r/content-length: (\d+)/i, headers)
        missing = String.to_integer(length) - byte_size(body)

        if missing > 0 do
          {:ok, rest} = :gen_tcp.recv(socket, missing, 5000)
          body <> rest
        else
          body
        end

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
        read_request(socket, bytes <> more)
    end
  end

  defp frame(delta, finish \\ nil) do
    "data: " <>
      Jason.encode!(%{
        "id" => "gate",
        "model" => "envelope-gate",
        "choices" => [%{"index" => 0, "delta" => delta, "finish_reason" => finish}]
      }) <> "\n\n"
  end

  for mode <- [:buffered, :stream, :fragmented] do
    test "#{mode}: required envelope rejects invalid arguments before effects" do
      {logical, outer, upstream} = tools(@empty)

      for arguments <- @invalid do
        result = request(unquote(mode), arguments, "tool_calls", upstream)

        assert effect(result, logical, outer) == :rejected,
               "accepted #{inspect(arguments)} via #{unquote(mode)}: #{inspect(result)}"

        refute_receive {:effect, _}, 0
        refute_receive :upstream_callback, 0
      end
    end

    test "#{mode}: empty and nonempty logical controls execute exactly once with IDs and payload" do
      for {schema, args} <- [{@empty, %{}}, {@object, %{"value" => 7}}] do
        {logical, outer, upstream} = tools(schema)

        result =
          request(unquote(mode), Jason.encode!(%{"arguments" => args}), "tool_calls", upstream)

        assert effect(result, logical, outer) == {:ok, "call-gate", args}
        assert_receive {:effect, ^args}
        refute_receive {:effect, _}, 0
        refute_receive :upstream_callback, 0
        assert_receive {:payload, payload}
        assert [%{"function" => definition}] = payload["tools"]
        assert definition["parameters"] == envelope(schema)
        refute Map.has_key?(definition, "strict")
      end
    end

    test "#{mode}: complete tool JSON cannot authorize an incomplete terminal" do
      {logical, outer, upstream} = tools(@empty)

      for finish <- ["length", "content_filter", "incomplete", "unknown", nil] do
        result = request(unquote(mode), "{\"arguments\":{}}", finish, upstream)

        assert effect(result, logical, outer) == :rejected,
               "accepted terminal #{inspect(finish)} via #{unquote(mode)}: #{inspect(result)}"

        refute_receive {:effect, _}, 0
      end
    end
  end
end
