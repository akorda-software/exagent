defmodule ExAgent.Providers.StreamTransportTest do
  use ExUnit.Case, async: false

  alias ExAgent.Providers.StreamTransport
  alias ExAgent.Models.OpenAI
  alias ExAgent.ModelRequestParameters

  setup do
    previous = Req.default_options()
    on_exit(fn -> Req.default_options(previous) end)
    :ok
  end

  defp synthetic(chunks, parent) do
    Req.default_options(
      adapter: fn request ->
        send(parent, {:http_worker, self()})

        Enum.reduce_while(
          Enum.with_index(chunks),
          {request, Req.Response.new(status: 200)},
          fn {chunk, index}, {req, resp} ->
            send(parent, {:callback, index})
            request.into.({:data, chunk}, {req, resp})
          end
        )
      end
    )
  end

  defp transport(opts \\ []),
    do: StreamTransport.stream([url: "http://unused.invalid", method: :get], opts)

  test "creation is lazy; halt cancels worker and preserves unrelated messages" do
    synthetic(["one", "two", "three"], self())
    stream = transport()
    refute_received {:http_worker, _}
    send(self(), {:unrelated, "keep"})
    assert [{:data, "one"}] = Enum.take(stream, 1)
    assert_receive {:http_worker, worker}
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}
    assert_receive {:unrelated, "keep"}
    refute_received {_, :item, _}
  end

  test "a suspended consumer admits one chunk and no firehose backlog" do
    synthetic(Enum.map(1..1000, &Integer.to_string/1), self())

    {:suspended, first, continuation} =
      Enumerable.reduce(transport(), {:cont, nil}, fn item, _ -> {:suspend, item} end)

    assert first == {:data, "1"}
    assert_receive {:http_worker, worker}
    assert_receive {:callback, 0}
    # One callback can hold the next bounded chunk while it waits for demand.
    assert_receive {:callback, 1}
    refute_receive {:callback, 2}, 20
    refute_received {_, :item, _}
    assert {:halted, nil} = continuation.({:halt, nil})
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}
  end

  test "downstream raise cleans the actual HTTP worker" do
    synthetic(["one", "two"], self())

    assert_raise RuntimeError, "downstream", fn ->
      Enum.each(transport(), fn _ -> raise "downstream" end)
    end

    assert_receive {:http_worker, worker}
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}
    refute_received {_, :item, _}
  end

  test "provider-level downstream raise closes transport across decoder continuations" do
    frame =
      "data: " <> Jason.encode!(%{"choices" => [%{"delta" => %{"content" => "one"}}]}) <> "\n\n"

    synthetic([frame, frame], self())
    model = %OpenAI{model: "offline", api_key: "offline"}

    assert_raise RuntimeError, "consumer failed", fn ->
      model
      |> OpenAI.request_stream([], nil, %ModelRequestParameters{})
      |> Enum.each(fn _ -> raise "consumer failed" end)
    end

    assert_receive {:http_worker, worker}
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}
    refute_received {_, :item, _}
  end

  test "each enumeration starts a fresh provider request with one final model terminal" do
    frame =
      "data: " <>
        Jason.encode!(%{
          "choices" => [
            %{
              "delta" => %{"content" => "ok"},
              "finish_reason" => "stop"
            }
          ]
        }) <> "\n\ndata: [DONE]\n\n"

    synthetic([frame], self())
    model = %OpenAI{model: "offline", api_key: "offline"}
    stream = OpenAI.request_stream(model, [], nil, %ModelRequestParameters{})

    for _ <- 1..2 do
      assert [{:text_delta, "ok"}, {:response, _, ^model}] = Enum.to_list(stream)
      assert_receive {:http_worker, worker}
      monitor = Process.monitor(worker)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}
    end

    refute_received {:http_worker, _}
  end

  test "owner death cleans suspended transport without an after callback" do
    parent = self()
    synthetic(["one", "two"], parent)

    owner =
      spawn(fn ->
        {:suspended, _, _continuation} =
          Enumerable.reduce(transport(), {:cont, nil}, fn item, _ -> {:suspend, item} end)

        send(parent, :suspended)

        receive do
          :never -> :ok
        end
      end)

    assert_receive {:http_worker, worker}
    monitor = Process.monitor(worker)
    assert_receive :suspended
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}
  end

  test "byte limit is a terminal error, and callback chunks are split into bounded handoffs" do
    synthetic([String.duplicate("x", 100_000)], self())
    chunks = Enum.to_list(transport())
    assert Enum.map(chunks, fn {:data, data} -> byte_size(data) end) == [65_536, 34_464]

    assert [{:error, {:stream_limit, :max_response_bytes}}] =
             Enum.to_list(transport(max_response_bytes: 3))
  end

  test "inactivity expires a suspended stream with a single observable error" do
    synthetic(["one", "two"], self())

    {:suspended, _, continuation} =
      Enumerable.reduce(transport(timeout: 30), {:cont, nil}, fn item, _ -> {:suspend, item} end)

    assert_receive {:http_worker, worker}
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 500
    # Resuming yields the guardian's tagged failure, never a success/EOF.
    assert {:suspended, {:error, _}, continuation} = continuation.({:cont, nil})
    continuation.({:halt, nil})
  end

  test "provider creation is lazy, carries HTTP status/identity, and never retries or redirects" do
    parent = self()

    Req.default_options(
      adapter: fn request ->
        send(parent, {:options, request.options})
        {request, Req.Response.new(status: 429, body: "rate limited")}
      end
    )

    model = %OpenAI{model: "offline", api_key: "offline"}
    stream = OpenAI.request_stream(model, [], nil, %ModelRequestParameters{})
    refute_received {:options, _}

    assert [{:error, %ExAgent.RequestError{status: 429, provider: :openai, reason: :http_error}}] =
             Enum.to_list(stream)

    assert_receive {:options, %{retry: false, redirect: false}}
    refute_received {:options, _}
  end

  test "Finch HTTP callback resource closes a local TCP stream on halt" do
    {url, server} = local_stream(self())
    stream = StreamTransport.stream(url: url, method: :get, finch: ExAgent.Finch)
    assert [{:data, "chunk"}] = Enum.take(stream, 1)
    assert_receive {:connection_closed, ^server}, 2000
  end

  test "response limit applies before an oversized declared HTTP chunk completes" do
    # A malicious peer need not complete its advertised 256 MiB chunk. Mint must
    # deliver partial body bytes so our limit can stop the request after 128 bytes.
    {url, server} = local_stream(self(), "10000000\r\n" <> String.duplicate("x", 128))

    stream =
      StreamTransport.stream(
        [url: url, method: :get, finch: ExAgent.Finch, receive_timeout: 500],
        max_response_bytes: 64
      )

    assert [{:error, {:stream_limit, :max_response_bytes}}] = Enum.to_list(stream)
    assert_receive {:connection_closed, ^server}, 2000
  end

  defp local_stream(parent, body \\ "5\r\nchunk\r\n") do
    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :raw,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(listener)

    server =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        :gen_tcp.close(listener)
        read_headers(socket, "")

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n" <>
              "Transfer-Encoding: chunked\r\n\r\n" <> body
          )

        case :gen_tcp.recv(socket, 0, 2000) do
          {:error, :closed} -> send(parent, {:connection_closed, self()})
          other -> send(parent, {:unexpected_socket_result, other})
        end

        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(server, :kill)
    end)

    {"http://127.0.0.1:#{port}/stream", server}
  end

  defp read_headers(socket, buffer) do
    if String.contains?(buffer, "\r\n\r\n") do
      :ok
    else
      {:ok, bytes} = :gen_tcp.recv(socket, 0, 2000)
      read_headers(socket, buffer <> bytes)
    end
  end
end
