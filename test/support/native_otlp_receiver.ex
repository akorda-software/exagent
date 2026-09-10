defmodule ExAgent.Test.NativeOTLPReceiver do
  @moduledoc false
  use GenServer

  # Deliberately a small HTTP/1.1 fixture, not an OTLP client or a collector.
  # Every request is held until the test explicitly replies or closes it.
  @max_body 65_536

  def start_link, do: GenServer.start_link(__MODULE__, self())
  def port(receiver), do: GenServer.call(receiver, :port)
  def stop(receiver), do: GenServer.stop(receiver)

  def reply(handler, status, body \\ <<>>), do: send(handler, {:reply, status, body})
  def close(handler), do: send(handler, :close)

  @impl true
  def init(owner) do
    Process.flag(:trap_exit, true)
    monitor = Process.monitor(owner)

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])

    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listener)
    server = self()
    acceptor = spawn_link(fn -> accept(listener, server, owner) end)
    {:ok, %{listener: listener, port: port, acceptor: acceptor, handlers: [], monitor: monitor}}
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  @impl true
  def handle_info({:handler, handler}, state) do
    Process.link(handler)
    {:noreply, %{state | handlers: [handler | state.handlers]}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{monitor: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:EXIT, pid, :normal}, state),
    do: {:noreply, %{state | handlers: List.delete(state.handlers, pid)}}

  def handle_info({:EXIT, _, reason}, state), do: {:stop, {:fixture_exit, reason}, state}

  @impl true
  def terminate(_, state) do
    :gen_tcp.close(state.listener)
    Enum.each([state.acceptor | state.handlers], &Process.exit(&1, :kill))
  end

  defp accept(listener, server, owner) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        handler = spawn(fn -> await_socket(server, owner) end)
        :ok = :gen_tcp.controlling_process(socket, handler)
        send(server, {:handler, handler})
        send(handler, {:socket, socket})
        accept(listener, server, owner)

      {:error, :closed} ->
        :ok
    end
  end

  defp await_socket(server, owner) do
    monitor = Process.monitor(server)

    receive do
      {:socket, socket} ->
        try do
          :ok = :inet.setopts(socket, packet: :http_bin)

          {:ok, {:http_request, method, {:abs_path, path}, version}} =
            :gen_tcp.recv(socket, 0, 2000)

          headers = headers(socket, %{}, 0)
          length = headers |> Map.fetch!("content-length") |> String.to_integer()
          true = length in 1..@max_body
          :ok = :inet.setopts(socket, packet: :raw)
          {:ok, body} = :gen_tcp.recv(socket, length, 2000)
          :ok = :inet.setopts(socket, active: :once)

          send(
            owner,
            {:native_otlp_request, server, self(),
             %{method: method, path: path, version: version, headers: headers, body: body}}
          )

          respond(socket, owner, monitor)
        after
          :gen_tcp.close(socket)
        end

      {:DOWN, ^monitor, :process, ^server, _} ->
        :ok
    after
      2000 -> exit(:socket_handoff_timeout)
    end
  end

  defp headers(socket, result, count) when count < 64 do
    case :gen_tcp.recv(socket, 0, 2000) do
      {:ok, :http_eoh} ->
        result

      {:ok, {:http_header, _, name, _, value}} ->
        headers(socket, Map.put(result, String.downcase(to_string(name)), value), count + 1)
    end
  end

  defp respond(socket, owner, monitor) do
    receive do
      {:reply, status, body} when byte_size(body) <= @max_body ->
        result =
          :gen_tcp.send(socket, [
            "HTTP/1.1 #{status} Synthetic\r\n",
            "content-type: application/x-protobuf\r\nconnection: close\r\n",
            "content-length: #{byte_size(body)}\r\n\r\n",
            body
          ])

        send(owner, {:native_otlp_replied, self(), result})

      :close ->
        send(owner, {:native_otlp_closed, self()})

      {:tcp_closed, ^socket} ->
        send(owner, {:native_otlp_peer_closed, self()})

      {:tcp_error, ^socket, reason} ->
        send(owner, {:native_otlp_peer_closed, self(), reason})

      {:DOWN, ^monitor, :process, _, _} ->
        :ok
    after
      10_000 -> exit(:unanswered_fixture_request)
    end
  end
end
