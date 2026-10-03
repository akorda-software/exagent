defmodule ExAgent.Test.MCPHTTPServer do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  def url(server), do: GenServer.call(server, :url)
  def journal(server), do: GenServer.call(server, :journal)
  def handler(server, fun), do: GenServer.call(server, {:handler, fun})
  def release(worker, response), do: send(worker, {:response, response})

  def json(id, result, headers \\ []),
    do:
      {200, [{"content-type", "application/json"} | headers],
       Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result})}

  def initialize(id, session \\ "fixture-session") do
    json(
      id,
      %{
        "protocolVersion" => "2025-06-18",
        "capabilities" => %{"tools" => %{}},
        "serverInfo" => %{"name" => "fixture", "version" => "1"}
      },
      [{"mcp-session-id", session}]
    )
  end

  def normal(%{method: "DELETE"}), do: {405, [], ""}
  def normal(%{json: %{"method" => "initialize", "id" => id}}), do: initialize(id)

  def normal(%{json: %{"method" => "tools/list", "id" => id}}),
    do:
      json(id, %{
        "tools" => [
          %{
            "name" => "echo",
            "inputSchema" => %{
              "type" => "object",
              "properties" => %{"text" => %{"type" => "string"}},
              "required" => ["text"]
            }
          }
        ]
      })

  def normal(%{json: %{"method" => "tools/call", "id" => id, "params" => params}}),
    do:
      json(id, %{
        "content" => [%{"type" => "text", "text" => params["arguments"]["text"] || "ok"}]
      })

  def normal(_), do: {202, [], ""}

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok, socket} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :raw,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(socket)
    server = self()
    acceptor = spawn_link(fn -> accept(socket, server) end)

    {:ok,
     %{
       socket: socket,
       acceptor: acceptor,
       owner: Keyword.fetch!(opts, :owner),
       handler: Keyword.get(opts, :handler, &normal/1),
       port: port,
       journal: [],
       workers: MapSet.new()
     }}
  end

  @impl true
  def handle_call(:url, _, state), do: {:reply, "http://127.0.0.1:#{state.port}/mcp", state}
  def handle_call(:journal, _, state), do: {:reply, Enum.reverse(state.journal), state}
  def handle_call({:handler, fun}, _, state), do: {:reply, :ok, %{state | handler: fun}}

  def handle_call({:request, request, worker}, _, state) do
    send(state.owner, {:mcp_request, self(), worker, request})
    response = state.handler.(request)
    {:reply, response, %{state | journal: [request | state.journal]}}
  end

  def handle_call({:worker, worker}, _, state) do
    Process.monitor(worker)
    {:reply, :ok, %{state | workers: MapSet.put(state.workers, worker)}}
  end

  @impl true
  def handle_info({:socket_closed, worker}, state) do
    send(state.owner, {:mcp_socket_closed, self(), worker})
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, worker, _}, state),
    do: {:noreply, %{state | workers: MapSet.delete(state.workers, worker)}}

  def handle_info({:EXIT, _, _}, state), do: {:noreply, state}

  @impl true
  def terminate(_, state) do
    :gen_tcp.close(state.socket)
    Process.exit(state.acceptor, :kill)
    Enum.each(state.workers, &Process.exit(&1, :kill))
  end

  defp accept(listener, server) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        worker =
          spawn(fn ->
            receive do
              {:socket, sock} -> connection(sock, server)
            end
          end)

        :ok = GenServer.call(server, {:worker, worker})
        :ok = :gen_tcp.controlling_process(socket, worker)
        send(worker, {:socket, socket})
        accept(listener, server)

      {:error, :closed} ->
        :ok
    end
  end

  defp connection(socket, server) do
    try do
      {:ok, head, rest} = headers(socket, "")
      [request_line | header_lines] = String.split(head, "\r\n")
      [method, path, version] = String.split(request_line, " ")

      headers =
        Map.new(header_lines, fn line ->
          [name, value] = String.split(line, ":", parts: 2)
          {String.downcase(name), String.trim(value)}
        end)

      length = String.to_integer(Map.get(headers, "content-length", "0"))
      {:ok, body} = body(socket, rest, length)

      request = %{
        method: method,
        path: path,
        version: version,
        headers: headers,
        body: body,
        json: if(body == "", do: nil, else: Jason.decode!(body))
      }

      response = GenServer.call(server, {:request, request, self()})
      respond(socket, response)
    after
      :gen_tcp.close(socket)
      send(server, {:socket_closed, self()})
    end
  end

  defp headers(socket, bytes) do
    case :binary.split(bytes, "\r\n\r\n") do
      [head, rest] ->
        {:ok, head, rest}

      [_] ->
        with {:ok, chunk} <- :gen_tcp.recv(socket, 0, 5_000), do: headers(socket, bytes <> chunk)
    end
  end

  defp body(_, bytes, length) when byte_size(bytes) >= length,
    do: {:ok, binary_part(bytes, 0, length)}

  defp body(socket, bytes, length) do
    with {:ok, chunk} <- :gen_tcp.recv(socket, 0, 5_000), do: body(socket, bytes <> chunk, length)
  end

  defp respond(socket, :hold) do
    :inet.setopts(socket, active: :once)

    receive do
      {:response, response} ->
        :inet.setopts(socket, active: false)
        respond(socket, response)

      {:tcp_closed, ^socket} ->
        :ok

      {:tcp_error, ^socket, _} ->
        :ok
    after
      10_000 -> :ok
    end
  end

  defp respond(_socket, :disconnect), do: :ok

  defp respond(socket, {:stream, chunks, tail}) do
    :ok =
      :gen_tcp.send(
        socket,
        "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\ntransfer-encoding: chunked\r\nconnection: close\r\n\r\n"
      )

    Enum.each(chunks, fn chunk ->
      :gen_tcp.send(socket, [Integer.to_string(byte_size(chunk), 16), "\r\n", chunk, "\r\n"])
    end)

    if tail == :hold, do: respond(socket, :hold), else: :gen_tcp.send(socket, "0\r\n\r\n")
  end

  defp respond(socket, {status, headers, body}) do
    :gen_tcp.send(socket, [
      "HTTP/1.1 #{status} Fixture\r\n",
      Enum.map(headers, fn {k, v} -> [k, ": ", v, "\r\n"] end),
      "content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
      body
    ])
  end
end
