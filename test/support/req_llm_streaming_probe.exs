# Stock public-API characterization, not acceptance of an ExAgent stream adapter.
# EXAGENT_OFFLINE=1 elixir -pa '_build/test/lib/*/ebin' test/support/req_llm_streaming_probe.exs
# Limits/oracles were declared in docs/archive/2026-09-21-r1-streaming.md.
unless System.get_env("EXAGENT_OFFLINE") == "1", do: raise("offline probe only")
Application.put_env(:req_llm, :load_dotenv, false)
Application.put_env(:req_llm, :stream_pool_size, 1)
Application.put_env(:req_llm, :stream_pool_count, 1)
Application.put_env(:req_llm, :metadata_timeout, 10_000)
{:ok, _} = Application.ensure_all_started(:req_llm)
ExUnit.start(seed: 37556, timeout: 20_000)

defmodule ExAgent.ReqLLMStreamingProbe do
  use ExUnit.Case, async: false
  alias ReqLLM.StreamResponse, as: Response

  defp open(url) do
    ReqLLM.stream_text(%{provider: :openai, id: "stream-probe"}, "synthetic",
      api_key: "synthetic-not-a-key",
      base_url: url,
      max_retries: 0,
      receive_timeout: 10_000,
      total_timeout: 15_000
    )
  end

  defp frame(delta, finish \\ nil) do
    "data: " <>
      Jason.encode!(%{
        "id" => "probe",
        "model" => "stream-probe",
        "choices" => [%{"index" => 0, "delta" => delta, "finish_reason" => finish}]
      }) <> "\n\n"
  end

  defp terminal, do: frame(%{}, "stop") <> "data: [DONE]\n\n"
  defp observe(label, value), do: IO.inspect(value, label: "R14 #{label}", limit: :infinity)

  defp close(response) do
    Response.close(response)
  catch
    :exit, _ -> :already_closed
  end

  test "opening is eager, while an ordinary host closure can defer opening" do
    {url, peer} = peer()
    lazy_open = fn -> open(url) end
    refute_receive {:accepted, ^peer}, 50
    assert {:ok, response} = lazy_open.()
    on_exit(fn -> close(response) end)
    assert_receive {:accepted, ^peer}, 2000
    observe("network_before_enumeration", true)
    assert :ok = close(response)
    assert :closed = command(peer, :closed)
  end

  test "one events view completes once and explicit close terminates metadata handle" do
    {url, peer} = peer()
    assert {:ok, response} = open(url)
    on_exit(fn -> close(response) end)
    assert_receive {:accepted, ^peer}, 2000
    handle = response.metadata_handle
    assert is_pid(handle)
    monitor = Process.monitor(handle)
    assert :ok = command(peer, {:send, frame(%{"content" => "hello"}) <> terminal()})
    assert :ok = command(peer, :finish)
    events = response |> Response.events() |> Enum.to_list()
    types = Enum.map(events, & &1.type)
    observe("complete_events", types)
    assert hd(types) == :start
    assert Enum.count(types, &(&1 in [:finish, :error, :cancelled])) == 1
    assert :finish == List.last(types)
    observe("metadata_before_close", Response.finish_reason(response))
    close(response)
    assert_receive {:DOWN, ^monitor, :process, ^handle, _}, 2000
  end

  test "a 256KiB frame passes the stock chunk watermark intact before a slow consumer" do
    {url, peer} = peer()
    assert {:ok, response} = open(url)
    on_exit(fn -> close(response) end)
    assert_receive {:accepted, ^peer}, 2000
    before = :erlang.memory(:binary)
    payload = String.duplicate("x", 256 * 1024)
    assert :ok = command(peer, {:send, frame(%{"content" => payload})})

    # Consume exactly one view, suspending after each item; no materialization view.
    {:suspended, start, next} =
      Enumerable.reduce(Response.events(response), {:cont, nil}, &suspend/2)

    assert start.type == :start
    Process.sleep(50)
    {:suspended, delta, next} = next.({:cont, nil})
    assert delta.type == :text_delta

    observe("large_frame", %{
      decoded_bytes: byte_size(delta.data),
      proposed_frame_limit: 65_536,
      watermark_chunks: 500,
      vm_binary_delta: :erlang.memory(:binary) - before
    })

    assert byte_size(delta.data) == byte_size(payload)
    next.({:halt, nil})
    close(response)
    assert :closed = command(peer, :closed)
  end

  test "incomplete 512KiB frame is retained beyond proposed byte cap until caller closes" do
    {url, peer} = peer()
    assert {:ok, response} = open(url)
    on_exit(fn -> close(response) end)
    assert_receive {:accepted, ^peer}, 2000
    before = :erlang.memory(:binary)
    prefix = "data: {\"choices\":[{\"delta\":{\"content\":\""
    assert :ok = command(peer, {:send, prefix <> String.duplicate("x", 512 * 1024)})
    # A finite observation window, not proof of an arbitrary scheduling order.
    socket = command(peer, :closed)

    observe("unterminated_frame", %{
      sent_payload_bytes: 512 * 1024,
      socket_after_2s: socket,
      vm_binary_delta: :erlang.memory(:binary) - before,
      proposed_frame_limit: 65_536
    })

    assert socket == :timeout
    close(response)
    assert :closed = command(peer, :closed)
  end

  test "EOF and truncated tool arguments expose their actual terminal rather than running effects" do
    for {label, bytes} <- [
          {:eof_after_text, frame(%{"content" => "partial"})},
          {:truncated_json, "data: {\"choices\":["},
          {:partial_tool,
           frame(%{
             "tool_calls" => [
               %{
                 "index" => 0,
                 "id" => "call-probe",
                 "type" => "function",
                 "function" => %{"name" => "unsafe", "arguments" => "{\"arg\":"}
               }
             ]
           })}
        ] do
      {url, peer} = peer()
      assert {:ok, response} = open(url)
      on_exit(fn -> close(response) end)
      assert_receive {:accepted, ^peer}, 2000
      assert :ok = command(peer, {:send, bytes})
      assert :ok = command(peer, :finish)
      events = response |> Response.events() |> Enum.to_list()
      observe("truncation", %{case: label, events: Enum.map(events, &{&1.type, &1.data})})
      assert Enum.count(events, &(&1.type in [:finish, :error, :cancelled])) == 1
      close(response)
    end
  end

  test "halt of the sole view closes transport and metadata" do
    {url, peer} = peer()
    assert {:ok, response} = open(url)
    on_exit(fn -> close(response) end)
    assert_receive {:accepted, ^peer}, 2000
    monitor = Process.monitor(response.metadata_handle)
    assert :ok = command(peer, {:send, frame(%{"content" => "one"})})
    assert [%{type: :start}] = response |> Response.events() |> Enum.take(1)
    close(response)
    assert :closed = command(peer, :closed)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 2000
  end

  test "creator death before enumeration is distinguished from monitored consumer death" do
    for enumerate? <- [false, true] do
      {url, peer} = peer()
      parent = self()

      owner =
        spawn(fn ->
          {:ok, response} = open(url)
          send(parent, {:opened, self(), response})

          receive do
            :enumerate -> :ok
          end

          if enumerate? do
            {:suspended, _, _next} =
              Enumerable.reduce(Response.events(response), {:cont, nil}, &suspend/2)

            send(parent, {:consuming, self()})
          end

          receive do
            :never -> :ok
          end
        end)

      on_exit(fn -> Process.exit(owner, :kill) end)
      assert_receive {:opened, ^owner, response}, 2000
      on_exit(fn -> close(response) end)
      assert_receive {:accepted, ^peer}, 2000
      assert :ok = command(peer, {:send, frame(%{"content" => "started"})})
      send(owner, :enumerate)
      if enumerate?, do: assert_receive({:consuming, ^owner}, 2000)
      handle_monitor = Process.monitor(response.metadata_handle)
      Process.exit(owner, :kill)
      socket = command(peer, :closed)
      observe("owner_kill", %{enumerated: enumerate?, socket_after_2s: socket})
      assert socket in [:closed, :timeout]
      assert_receive {:DOWN, ^handle_monitor, :process, _, _}, 2000
      close(response)
    end
  end

  defp suspend(event, _), do: {:suspend, event}

  # Fixture HTTP framing only. Model SSE bytes are deliberately authored test data;
  # the only SSE parser/decoder under test is the actual ReqLLM implementation.
  defp peer do
    parent = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :raw,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        :gen_tcp.close(listener)
        read_request(socket, "")
        send(parent, {:accepted, self()})

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n"
          )

        serve(socket, 0)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(pid, :kill)
    end)

    {"http://127.0.0.1:#{port}/v1", pid}
  end

  defp read_request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length: (\d+)/i, headers)
        missing = String.to_integer(size) - byte_size(body)
        if missing > 0, do: {:ok, _} = :gen_tcp.recv(socket, missing, 2000)

      _ ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 2000)
        read_request(socket, buffer <> bytes)
    end
  end

  defp serve(socket, sent) do
    receive do
      {from, ref, {:send, bytes}} ->
        true = sent + byte_size(bytes) <= 1_048_576
        send(from, {ref, :gen_tcp.send(socket, bytes)})
        serve(socket, sent + byte_size(bytes))

      {from, ref, :closed} ->
        result =
          case :gen_tcp.recv(socket, 0, 2000) do
            {:error, :closed} -> :closed
            {:error, :timeout} -> :timeout
            other -> other
          end

        send(from, {ref, result})
        serve(socket, sent)

      {from, ref, :finish} ->
        :gen_tcp.close(socket)
        send(from, {ref, :ok})
    after
      18_000 -> :gen_tcp.close(socket)
    end
  end

  defp command(peer, command) do
    ref = make_ref()
    send(peer, {self(), ref, command})

    receive do
      {^ref, result} -> result
    after
      3000 -> flunk("peer command timeout")
    end
  end
end
