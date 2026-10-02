defmodule ExAgent.ContinuationRetryTransportTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Message, Model, ModelSettings, ModelRequestParameters}
  alias ExAgent.Models.ReqLLM, as: Adapter

  @specification %{
    provider: :openai,
    id: "retry-http",
    extra: %{wire: %{protocol: "openai_chat"}},
    capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
  }

  test "stock ReqLLM carries the public idempotency key to actual buffered and streaming HTTP" do
    for stream? <- [false, true] do
      {url, peer} = peer(stream?, self())

      model =
        Adapter.new(
          model: @specification,
          api_key: "synthetic",
          base_url: url,
          tool_profile: :chat_tools_v1
        )

      messages = [Message.new_request([%Message.Part.User{content: "synthetic"}])]
      params = %ModelRequestParameters{idempotency_key: "host-owned-key"}
      assert :ok = Model.validate_resume(model, messages, %ModelSettings{}, params)
      refute_receive {:wire_key, _, _}

      if stream? do
        events =
          Model.request_stream(model, messages, %ModelSettings{timeout: 2_000}, params)
          |> Enum.to_list()

        assert Enum.any?(events, &match?({:response, %Message.Response{}, _}, &1))
        refute Enum.any?(events, &match?({:error, _}, &1))
      else
        assert {:ok, response, _} =
                 Model.request(model, messages, %ModelSettings{timeout: 2_000}, params)

        assert Message.Response.text(response) == "done"
      end

      assert_receive {:wire_key, "host-owned-key", body}
      assert body["model"] == "retry-http"
      refute Map.has_key?(body, "idempotency_key")
      assert :ok = Task.await(peer, 5_000)
    end
  end

  test "unqualified profile and header control characters reject before transport" do
    owner = self()

    adapter = fn request ->
      send(owner, :unexpected_transport)
      {request, Req.Response.new(status: 500)}
    end

    model =
      Adapter.new(
        model: @specification,
        api_key: "synthetic",
        base_url: "http://127.0.0.1:1/v1",
        http_options: [adapter: ExAgent.Test.ReqTransport.bind(adapter)]
      )

    messages = [Message.new_request([%Message.Part.User{content: "synthetic"}])]

    for candidate <- [model, %{model | tool_profile: :chat_tools_v1}],
        key <- ["key\r\ninjected: value", ""] do
      assert {:error, _} =
               Model.request(candidate, messages, %ModelSettings{}, %ModelRequestParameters{
                 idempotency_key: key
               })
    end

    assert {:error, _} =
             Model.request(model, messages, %ModelSettings{}, %ModelRequestParameters{
               idempotency_key: "valid-key"
             })

    refute_receive :unexpected_transport
  end

  defp peer(stream?, owner) do
    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :http_bin,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        :gen_tcp.close(listener)
        {:ok, {:http_request, :POST, _, _}} = :gen_tcp.recv(socket, 0, 5_000)
        headers = headers(socket, %{})
        :ok = :inet.setopts(socket, packet: :raw)
        {:ok, body} = :gen_tcp.recv(socket, String.to_integer(headers["content-length"]), 5_000)
        send(owner, {:wire_key, headers["idempotency-key"], Jason.decode!(body)})
        {type, response} = response(stream?)

        :ok =
          :gen_tcp.send(socket, [
            "HTTP/1.1 200 OK\r\ncontent-type: ",
            type,
            "\r\ncontent-length: ",
            Integer.to_string(byte_size(response)),
            "\r\nconnection: close\r\n\r\n",
            response
          ])

        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    {"http://127.0.0.1:#{port}/v1", task}
  end

  defp headers(socket, headers) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, :http_eoh} ->
        headers

      {:ok, {:http_header, _, name, _, value}} ->
        headers(socket, Map.put(headers, String.downcase(to_string(name)), to_string(value)))
    end
  end

  defp response(false) do
    {"application/json",
     Jason.encode!(%{
       id: "reply",
       model: "retry-http",
       choices: [
         %{index: 0, message: %{role: "assistant", content: "done"}, finish_reason: "stop"}
       ],
       usage: %{prompt_tokens: 1, completion_tokens: 1, total_tokens: 2}
     })}
  end

  defp response(true) do
    chunks = [
      %{
        id: "reply",
        object: "chat.completion.chunk",
        model: "retry-http",
        choices: [%{index: 0, delta: %{role: "assistant", content: "done"}, finish_reason: nil}]
      },
      %{
        id: "reply",
        object: "chat.completion.chunk",
        model: "retry-http",
        choices: [%{index: 0, delta: %{}, finish_reason: "stop"}],
        usage: %{prompt_tokens: 1, completion_tokens: 1, total_tokens: 2}
      }
    ]

    {"text/event-stream",
     Enum.map_join(chunks, "", &("data: " <> Jason.encode!(&1) <> "\n\n")) <> "data: [DONE]\n\n"}
  end
end
