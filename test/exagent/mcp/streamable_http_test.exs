defmodule ExAgent.MCP.StreamableHTTPPreflightTest do
  use ExUnit.Case, async: true

  # Characterize public seams before implementing a transport. These tests do
  # not send requests or certify Streamable HTTP interoperability.
  @url "https://mcp.example.invalid/mcp"

  test "public pool metrics do not distinguish HTTP1-only from mixed ALPN" do
    for {name, protocols} <- [
          {__MODULE__.HTTP1, [:http1]},
          {__MODULE__.Mixed, [:http1, :http2]}
        ] do
      start_supervised!(
        {Finch,
         name: name, pools: %{@url => [protocols: protocols, size: 1, start_pool_metrics?: true]}},
        id: name
      )

      assert {:ok, [_]} = Finch.get_pool_status(name, @url)
      assert {:ok, [%Finch.HTTP1.PoolMetrics{}]} = Finch.get_pool_status(name, @url)
      assert {:ok, pid} = Finch.find_pool(name, Finch.Pool.new(@url))
      assert is_pid(pid)
    end
  end

  test "start_pool success does not prove requested options were applied to an existing pool" do
    name = __MODULE__.Existing

    start_supervised!(
      {Finch,
       name: name, pools: %{@url => [protocols: [:http1, :http2], start_pool_metrics?: false]}}
    )

    assert :ok =
             Finch.start_pool(name, Finch.Pool.new(@url),
               protocols: [:http1],
               start_pool_metrics?: true
             )

    assert {:error, :not_found} = Finch.get_pool_status(name, @url)
  end

  test "public build does not accept a per-request protocol selector" do
    assert_raise ArgumentError, fn ->
      Finch.build(:post, @url, [], "{}", protocols: [:http1])
    end
  end
end

defmodule ExAgent.MCP.StreamableHTTPTest do
  use ExUnit.Case, async: true
  alias ExAgent.MCP.Client
  alias ExAgent.Test.MCPHTTPServer, as: Server

  setup do
    server = start_supervised!({Server, owner: self()})

    start_supervised!(
      {Finch, name: __MODULE__.Pool, pools: %{default: [protocols: [:http1], size: 8, count: 1]}}
    )

    %{server: server, url: Server.url(server)}
  end

  defp client(ctx, opts \\ []) do
    {:ok, client} =
      Client.start_link(
        Keyword.merge(
          [transport: :streamable_http, finch: __MODULE__.Pool, url: ctx.url, timeout: 2_000],
          opts
        )
      )

    Process.unlink(client)

    on_exit(fn ->
      monitor = Process.monitor(client)
      if Process.alive?(client), do: Process.exit(client, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^client, _}, 2_000
    end)

    client
  end

  defp calls(server),
    do: Enum.filter(Server.journal(server), &match?(%{json: %{"method" => "tools/call"}}, &1))

  defp response(id, text \\ "ok"),
    do: Server.json(id, %{"content" => [%{"type" => "text", "text" => text}]})

  defp intercept(server, fun) do
    Server.handler(server, fn
      %{json: %{"method" => "tools/call"}} = req -> fun.(req)
      req -> Server.normal(req)
    end)
  end

  defp sse(body), do: "data: " <> body <> "\n\n"

  defp partition(bytes, :coalesced), do: [bytes]

  defp partition(bytes, :fragmented),
    do:
      bytes |> :binary.bin_to_list() |> Enum.chunk_every(3) |> Enum.map(&:erlang.list_to_binary/1)

  defp partition(bytes, split) when is_integer(split) do
    {a, b} = :erlang.split_binary(bytes, split)
    Enum.reject([a, b], &(&1 == ""))
  end

  defp assert_sse_call(c, expected) do
    assert Client.call_tool(c, "echo", %{}) == expected
    assert_receive {:mcp_request, _, socket, %{json: %{"method" => "tools/call"}}}, 2_000
    assert_receive {:mcp_socket_closed, _, ^socket}, 2_000
    assert :sys.get_state(c).pending == %{}
  end

  test "SSE terminal ignores malformed, UTF8, line and event suffixes across TCP partitions",
       ctx do
    c = client(ctx, max_line_bytes: 256, max_event_bytes: 128)

    for suffix <- [
          <<255, 10>>,
          String.duplicate(":", 257) <> "\n\n",
          sse(String.duplicate("x", 129)),
          sse("malformed")
        ],
        mode <- [:coalesced, :fragmented, :terminal_split] do
      intercept(ctx.server, fn %{json: %{"id" => id}} ->
        {_, _, body} = response(id, "雪")
        terminal = sse(body)
        split = if mode == :terminal_split, do: byte_size(terminal), else: mode
        {:stream, partition(terminal <> suffix, split), :hold}
      end)

      assert_sse_call(c, {:ok, "雪"})
    end

    assert length(calls(ctx.server)) == 12
  end

  test "SSE response budget counts prefix through terminal, exact and minus one", ctx do
    c = client(ctx)

    for mode <- [:coalesced, :fragmented, :terminal_split], delta <- [0, -1] do
      id = :sys.get_state(c).id
      {_, _, body} = response(id, "雪")
      terminal = ":metadata\n" <> sse(body)

      :sys.replace_state(
        c,
        &%{&1 | http: %{&1.http | max_response_bytes: byte_size(terminal) + delta}}
      )

      intercept(ctx.server, fn _ ->
        split = if mode == :terminal_split, do: byte_size(terminal), else: mode
        {:stream, partition(terminal <> String.duplicate(":", 1024), split), :hold}
      end)

      expected = if delta == 0, do: {:ok, "雪"}, else: {:error, :response_byte_limit}
      assert_sse_call(c, expected)
    end
  end

  test "SSE errors before terminal and notification followed by malformed data still reject",
       ctx do
    c = client(ctx, max_line_bytes: 256, max_event_bytes: 128)
    notification = sse(~s({"jsonrpc":"2.0","method":"notifications/progress"}))

    for {prefix, error} <- [
          {<<255, 10>>, :invalid_sse_utf8},
          {String.duplicate(":", 257) <> "\n", :sse_line_limit},
          {sse(String.duplicate("x", 129)), :sse_event_limit},
          {notification <> sse("malformed"), :invalid_jsonrpc},
          {notification <> <<255, 10>>, :invalid_sse_utf8}
        ],
        mode <- [:coalesced, :fragmented] do
      intercept(ctx.server, fn %{json: %{"id" => id}} ->
        {_, _, body} = response(id)
        {:stream, partition(prefix <> sse(body), mode), :hold}
      end)

      assert_sse_call(c, {:error, error})
    end
  end

  test "SSE controls run in order before terminal only and their limits still win", ctx do
    c = client(ctx, max_controls: 1)
    ping = sse(~s({"jsonrpc":"2.0","id":"before","method":"ping"}))
    late = sse(~s({"jsonrpc":"2.0","id":"after","method":"ping"}))

    for mode <- [:coalesced, :fragmented], count <- [1, 2] do
      before =
        Enum.count(
          Server.journal(ctx.server),
          &match?(%{json: %{"id" => "before", "result" => %{}}}, &1)
        )

      intercept(ctx.server, fn %{json: %{"id" => id}} ->
        {_, _, body} = response(id)

        {:stream,
         partition(String.duplicate(ping, count) <> sse(body) <> late <> <<255, 10>>, mode),
         :hold}
      end)

      expected = if count == 1, do: {:ok, "ok"}, else: {:error, :control_count_limit}
      assert_sse_call(c, expected)
      journal = Server.journal(ctx.server)

      assert Enum.count(journal, &match?(%{json: %{"id" => "before", "result" => %{}}}, &1)) ==
               before + 1

      refute Enum.any?(journal, &match?(%{json: %{"id" => "after"}}, &1))
    end
  end

  test "SSE JSONRPC terminal error wins over later framing error", ctx do
    c = client(ctx)

    for mode <- [:coalesced, :fragmented] do
      intercept(ctx.server, fn %{json: %{"id" => id}} ->
        terminal =
          sse(
            Jason.encode!(%{
              "jsonrpc" => "2.0",
              "id" => id,
              "error" => %{"code" => -32603, "message" => "private"}
            })
          )

        {:stream, partition(terminal <> <<255, 10>>, mode), :hold}
      end)

      assert_sse_call(c, {:error, {:jsonrpc_error, -32603}})
    end
  end

  test "HTTP1 wire handshake, discovery, exact schema, session and close", ctx do
    c = client(ctx, headers: [{"authorization", "Bearer synthetic-a"}])
    assert {:ok, [tool]} = Client.tools(c)
    assert tool.parameters_json_schema["required"] == ["text"]
    assert {:ok, "héllo"} = tool.call.(%{"text" => "héllo"})
    assert :ok = Client.close(c)
    [init, ready, list, call, delete] = Server.journal(ctx.server)
    assert init.version == "HTTP/1.1"
    assert init.json["params"]["protocolVersion"] == "2025-06-18"
    refute Map.has_key?(init.headers, "mcp-session-id")
    refute Map.has_key?(init.headers, "mcp-protocol-version")
    assert ready.json["method"] == "notifications/initialized"

    for req <- [ready, list, call, delete] do
      assert req.headers["mcp-session-id"] == "fixture-session"
      assert req.headers["mcp-protocol-version"] == "2025-06-18"
      assert req.headers["authorization"] == "Bearer synthetic-a"
      refute Map.has_key?(req.headers, "last-event-id")
    end

    assert delete.method == "DELETE"
    assert Enum.count(Server.journal(ctx.server), &(&1.method == "GET")) == 0
  end

  test "two clients isolate auth and negotiated session; diagnostic state is redacted", ctx do
    Server.handler(ctx.server, fn
      %{json: %{"method" => "initialize", "id" => id}, headers: headers} ->
        Server.initialize(id, headers["authorization"])

      req ->
        Server.normal(req)
    end)

    a = client(ctx, headers: [{"authorization", "synthetic-a"}])
    b = client(ctx, headers: [{"authorization", "synthetic-b"}])
    assert {:ok, "A"} = Client.call_tool(a, "echo", %{"text" => "A"})
    assert {:ok, "B"} = Client.call_tool(b, "echo", %{"text" => "B"})

    for req <- calls(ctx.server),
        do: assert(req.headers["authorization"] == req.headers["mcp-session-id"])

    refute inspect(:sys.get_status(a)) =~ "synthetic-a"
  end

  test "SSE initialize and streamed responses support fragmented UTF8/CRLF/multidata", ctx do
    Server.handler(ctx.server, fn
      %{json: %{"method" => "initialize", "id" => id}} ->
        {_, _, body} = Server.initialize(id)
        {:stream, ["data: " <> body <> "\r\n\r\n"], :eof}

      %{json: %{"method" => "tools/call", "id" => id}} ->
        data =
          "data: {\"jsonrpc\":\"2.0\",\r\ndata: \"id\":#{id},\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"雪\"}]}}\r\n\r\n"

        {:stream, for(<<byte <- data>>, do: <<byte>>), :hold}

      req ->
        Server.normal(req)
    end)

    c = client(ctx)
    assert {:ok, "雪"} = Client.call_tool(c, "echo", %{})
    assert_receive {:mcp_request, _, worker, %{json: %{"method" => "tools/call"}}}, 2_000
    assert_receive {:mcp_socket_closed, _, ^worker}, 2_000
  end

  test "strict initialize protocol, session, and initialized202; no request replay", ctx do
    for bad <- [:version, :missing_info, :bad_session, :oversize_session, :ready_status] do
      Server.handler(ctx.server, fn
        %{json: %{"method" => "initialize", "id" => id}} ->
          case bad do
            :version ->
              Server.json(id, %{"protocolVersion" => "2024-11-05"})

            :missing_info ->
              Server.json(id, %{"protocolVersion" => "2025-06-18", "capabilities" => %{}})

            :bad_session ->
              Server.initialize(id, "contains space")

            :oversize_session ->
              Server.initialize(id, String.duplicate("x", 257))

            _ ->
              Server.initialize(id)
          end

        %{json: %{"method" => "notifications/initialized"}} ->
          {204, [], ""}

        req ->
          Server.normal(req)
      end)

      assert {:error, _} =
               Client.start_link(
                 transport: :streamable_http,
                 finch: __MODULE__.Pool,
                 url: ctx.url,
                 timeout: 2_000
               )
    end

    assert calls(ctx.server) == []

    assert Enum.count(
             Server.journal(ctx.server),
             &match?(%{json: %{"method" => "initialize"}}, &1)
           ) == 5
  end

  test "status errors are explicit without redirects, retries or leaked bodies", ctx do
    c = client(ctx)

    for {status, expected} <- [
          {301, {:http_status, 301}},
          {307, {:http_status, 307}},
          {401, :unauthorized},
          {403, :forbidden},
          {429, {:http_status, 429}},
          {503, {:http_status, 503}}
        ] do
      intercept(ctx.server, fn _ -> {status, [{"location", ctx.url}], "synthetic-secret"} end)
      assert {:error, ^expected} = Client.call_tool(c, "echo", %{})
    end

    assert length(calls(ctx.server)) == 6
  end

  test "rejects malformed JSONRPC, wrong exact IDs, mixed result/error and content types", ctx do
    c = client(ctx)

    for mode <- [
          :float_id,
          :string_id,
          :wrong_id,
          :version,
          :both,
          :bad_error,
          :bad_json,
          :type,
          :batch
        ] do
      intercept(ctx.server, fn %{json: %{"id" => id}} ->
        payload = %{"jsonrpc" => "2.0", "id" => id, "result" => %{"content" => []}}

        payload =
          case mode do
            :float_id -> Map.put(payload, "id", id / 1)
            :string_id -> Map.put(payload, "id", to_string(id))
            :wrong_id -> Map.put(payload, "id", -1)
            :version -> Map.put(payload, "jsonrpc", "1.0")
            :both -> Map.put(payload, "error", %{"code" => 1, "message" => "secret"})
            :bad_error -> payload |> Map.delete("result") |> Map.put("error", %{"code" => "bad"})
            :batch -> [payload]
            _ -> payload
          end

        {200, [{"content-type", if(mode == :type, do: "text/plain", else: "application/json")}],
         if(mode == :bad_json, do: "{synthetic-secret", else: Jason.encode!(payload))}
      end)

      assert {:error, reason} = Client.call_tool(c, "echo", %{})
      refute inspect(reason) =~ "synthetic-secret"
    end

    assert length(calls(ctx.server)) == 9
  end

  test "SSE EOF and disconnect fail without replay, progress does not complete", ctx do
    c = client(ctx)

    for response <- [
          :disconnect,
          {:stream, ["data: {"], :eof},
          {:stream, ["data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\n\n"],
           :eof}
        ] do
      intercept(ctx.server, fn _ -> response end)
      assert {:error, _} = Client.call_tool(c, "echo", %{})
    end

    assert length(calls(ctx.server)) == 3
  end

  test "discovery pagination and count reject rather than returning a truncated catalog", ctx do
    c = client(ctx, max_tools: 1)
    assert {:ok, [_]} = Client.tools(c)

    for result <- [
          %{"tools" => [], "nextCursor" => "next"},
          %{
            "tools" => [
              %{"name" => "a", "inputSchema" => %{}},
              %{"name" => "b", "inputSchema" => %{}}
            ]
          },
          %{"tools" => [%{"name" => "bad"}]}
        ] do
      Server.handler(ctx.server, fn req ->
        if req.json && req.json["method"] == "tools/list",
          do: Server.json(req.json["id"], result),
          else: Server.normal(req)
      end)

      assert {:error, _} = Client.tools(c)
    end
  end

  test "concurrent requests correlate exact workers and max_pending rejects before IO", ctx do
    c = client(ctx, max_pending: 2)
    intercept(ctx.server, fn _ -> :hold end)
    first = Task.async(fn -> Client.call_tool(c, "echo", %{"text" => "a"}) end)

    assert_receive {:mcp_request, _, one, %{json: %{"method" => "tools/call", "id" => id1}}},
                   2_000

    second = Task.async(fn -> Client.call_tool(c, "echo", %{"text" => "b"}) end)

    assert_receive {:mcp_request, _, two, %{json: %{"method" => "tools/call", "id" => id2}}},
                   2_000

    assert {:error, :busy} = Client.call_tool(c, "echo", %{})
    assert length(calls(ctx.server)) == 2
    Server.release(two, response(id2, "b"))
    assert {:ok, "b"} = Task.await(second)
    Server.release(one, response(id1, "a"))
    assert {:ok, "a"} = Task.await(first)
    assert :sys.get_state(c).pending == %{}
  end

  test "timeout closes socket and sends a bounded best-effort cancellation once", ctx do
    c = client(ctx)
    :sys.replace_state(c, &%{&1 | timeout: 100})
    intercept(ctx.server, fn _ -> :hold end)
    task = Task.async(fn -> Client.call_tool(c, "echo", %{}) end)

    assert_receive {:mcp_request, _, worker, %{json: %{"method" => "tools/call", "id" => id}}},
                   2_000

    assert {:error, :timeout} = Task.await(task)
    assert_receive {:mcp_socket_closed, _, ^worker}, 2_000

    assert_receive {:mcp_request, _, _,
                    %{
                      json: %{
                        "method" => "notifications/cancelled",
                        "params" => %{"requestId" => ^id}
                      }
                    }},
                   2_000

    assert length(calls(ctx.server)) == 1
    assert :sys.get_state(c).pending == %{}
  end

  test "caller death kills its worker and socket; client kill also cleans held IO", ctx do
    c = client(ctx)
    intercept(ctx.server, fn _ -> :hold end)
    caller = spawn(fn -> Client.call_tool(c, "echo", %{}) end)
    assert_receive {:mcp_request, _, socket_worker, %{json: %{"method" => "tools/call"}}}, 2_000
    [pending] = Map.values(:sys.get_state(c).pending)
    ref = Process.monitor(pending.worker)
    {:monitored_by, monitoring} = Process.info(pending.worker, :monitored_by)

    [guardian] =
      Enum.filter(monitoring, fn pid ->
        Process.info(pid, :current_function) ==
          {:current_function, {ExAgent.MCP.StreamableHTTP, :guard, 3}}
      end)

    guardian_ref = Process.monitor(guardian)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, _, _}, 2_000
    assert_receive {:DOWN, ^guardian_ref, :process, ^guardian, _}, 2_000
    assert_receive {:mcp_socket_closed, _, ^socket_worker}, 2_000
    assert_receive {:mcp_request, _, _, %{json: %{"method" => "notifications/cancelled"}}}, 2_000

    spawn(fn ->
      try do
        Client.call_tool(c, "echo", %{})
      catch
        :exit, _ -> :ok
      end
    end)

    assert_receive {:mcp_request, _, socket_worker2, %{json: %{"method" => "tools/call"}}}, 2_000
    [pending2] = Map.values(:sys.get_state(c).pending)
    ref2 = Process.monitor(pending2.worker)
    Process.exit(c, :kill)
    assert_receive {:DOWN, ^ref2, :process, _, _}, 2_000
    assert_receive {:mcp_socket_closed, _, ^socket_worker2}, 2_000
    assert length(calls(ctx.server)) == 2
  end

  test "close kills pending IO and DELETE405 is accepted", ctx do
    c = client(ctx)
    intercept(ctx.server, fn _ -> :hold end)
    task = Task.async(fn -> Client.call_tool(c, "echo", %{}) end)
    assert_receive {:mcp_request, _, worker, %{json: %{"method" => "tools/call"}}}, 2_000
    assert :ok = Client.close(c)
    assert {:error, :closed} = Task.await(task)
    assert_receive {:mcp_socket_closed, _, ^worker}, 2_000
    assert_receive {:mcp_request, _, _, %{method: "DELETE"}}, 2_000
  end

  test "404 invalidates generation and all pending; explicit reconnect never replays", ctx do
    c = client(ctx)
    intercept(ctx.server, fn _ -> :hold end)
    first = Task.async(fn -> Client.call_tool(c, "echo", %{}) end)
    assert_receive {:mcp_request, _, a, %{json: %{"method" => "tools/call"}}}, 2_000
    second = Task.async(fn -> Client.call_tool(c, "echo", %{}) end)
    assert_receive {:mcp_request, _, b, %{json: %{"method" => "tools/call"}}}, 2_000
    old = :sys.get_state(c)
    [{old_id, pending} | _] = Map.to_list(old.pending)
    Server.release(a, {404, [], ""})
    assert {:error, :session_expired} = Task.await(first)
    assert {:error, :session_expired} = Task.await(second)
    assert_receive {:mcp_socket_closed, _, ^b}, 2_000
    assert {:error, :not_ready} = Client.tools(c)
    assert :sys.get_state(c).session == nil
    assert :ok = Client.reconnect(c)
    send(c, {:mcp_http, old.generation, old_id, pending.worker, {:ok, %{}, "stale"}})
    assert :sys.get_state(c).session == "fixture-session"
    assert :sys.get_state(c).generation == old.generation + 1
    assert length(calls(ctx.server)) == 2
  end

  test "SSE ping and unsupported server requests get bounded responses; no sampling", ctx do
    c = client(ctx)

    intercept(ctx.server, fn %{json: %{"id" => id}} ->
      {_, _, final} = response(id)

      events =
        for method <- ["ping", "sampling/createMessage"],
            do:
              "data: " <>
                Jason.encode!(%{"jsonrpc" => "2.0", "id" => method, "method" => method}) <> "\n\n"

      {:stream, events ++ ["data: " <> final <> "\n\n"], :hold}
    end)

    assert {:ok, "ok"} = Client.call_tool(c, "echo", %{})
    journal = Server.journal(ctx.server)
    assert Enum.any?(journal, &match?(%{json: %{"id" => "ping", "result" => %{}}}, &1))

    assert Enum.any?(
             journal,
             &match?(
               %{json: %{"id" => "sampling/createMessage", "error" => %{"code" => -32601}}},
               &1
             )
           )

    assert length(calls(ctx.server)) == 1
  end

  test "response byte cap is inclusive and request byte cap prevents tool POST", ctx do
    c = client(ctx)
    {_, _, body} = response(1)

    :sys.replace_state(c, fn s -> %{s | http: %{s.http | max_response_bytes: byte_size(body)}} end)

    intercept(ctx.server, fn %{json: %{"id" => id}} -> response(id) end)
    assert {:ok, "ok"} = Client.call_tool(c, "echo", %{})

    :sys.replace_state(c, fn s ->
      %{s | http: %{s.http | max_response_bytes: byte_size(body) - 1}}
    end)

    assert {:error, :response_byte_limit} = Client.call_tool(c, "echo", %{})
    :sys.replace_state(c, fn s -> %{s | http: %{s.http | max_request_bytes: 1}} end)
    assert {:error, :request_byte_limit} = Client.call_tool(c, "echo", %{})
    assert length(calls(ctx.server)) == 2
  end

  test "control count and byte caps reject exact+1", ctx do
    c = client(ctx, max_controls: 1)
    event = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "notifications/progress"})

    intercept(ctx.server, fn %{json: %{"id" => id}} ->
      {_, _, final} = response(id)
      {:stream, ["data: " <> event <> "\n\ndata: " <> final <> "\n\n"], :eof}
    end)

    :sys.replace_state(c, fn s -> %{s | http: %{s.http | max_control_bytes: byte_size(event)}} end)

    assert {:ok, "ok"} = Client.call_tool(c, "echo", %{})

    :sys.replace_state(c, fn s ->
      %{s | http: %{s.http | max_control_bytes: byte_size(event) - 1}}
    end)

    assert {:error, :control_byte_limit} = Client.call_tool(c, "echo", %{})
    :sys.replace_state(c, fn s -> %{s | http: %{s.http | max_control_bytes: 65_536}} end)

    intercept(ctx.server, fn _ ->
      {:stream, ["data: " <> event <> "\n\ndata: " <> event <> "\n\n"], :eof}
    end)

    assert {:error, :control_count_limit} = Client.call_tool(c, "echo", %{})
  end

  test "deadline and socket cleanup remain effective while Client is suspended", ctx do
    c = client(ctx)
    :sys.replace_state(c, &%{&1 | timeout: 250})
    intercept(ctx.server, fn _ -> :hold end)
    task = Task.async(fn -> Client.call_tool(c, "echo", %{}) end)
    assert_receive {:mcp_request, _, socket_worker, %{json: %{"method" => "tools/call"}}}, 2_000
    [{id, pending}] = Map.to_list(:sys.get_state(c).pending)
    generation = :sys.get_state(c).generation
    worker = pending.worker
    ref = Process.monitor(worker)
    :ok = :sys.suspend(c)
    # The transport timeout and guardian share a deadline; either may finish first.
    assert_receive {:DOWN, ^ref, :process, ^worker, reason}, 2_000
    assert reason in [:normal, :killed]
    assert_receive {:mcp_socket_closed, _, ^socket_worker}, 2_000
    # Even a queued nominal success cannot outrun the absolute Client deadline.
    send(
      c,
      {:mcp_http, generation, id, pending.worker, {:ok, %{"content" => []}, "fixture-session"}}
    )

    :ok = :sys.resume(c)
    assert {:error, :timeout} = Task.await(task)
    assert :sys.get_state(c).pending == %{}
  end

  for winner <- [:transport, :guardian] do
    @winner winner
    test "suspended Client deadline with #{@winner} first closes IO and rejects late success",
         ctx do
      c = client(ctx)
      :sys.replace_state(c, &%{&1 | timeout: 250})
      intercept(ctx.server, fn _ -> :hold end)
      task = Task.async(fn -> Client.call_tool(c, "echo", %{}) end)
      assert_receive {:mcp_request, _, socket, %{json: %{"method" => "tools/call"}}}, 2_000
      state = :sys.get_state(c)
      [{id, pending}] = Map.to_list(state.pending)
      worker = pending.worker
      {:monitored_by, monitors} = Process.info(worker, :monitored_by)

      [guardian] =
        Enum.filter(monitors, fn pid ->
          Process.info(pid, :current_function) ==
            {:current_function, {ExAgent.MCP.StreamableHTTP, :guard, 3}}
        end)

      worker_ref = Process.monitor(worker)
      guardian_ref = Process.monitor(guardian)
      # Select the scheduler order without changing either deadline or IO behavior.
      delayed = if @winner == :transport, do: guardian, else: worker
      true = :erlang.suspend_process(delayed)

      try do
        :ok = :sys.suspend(c)
        reason = if @winner == :transport, do: :normal, else: :killed
        assert_receive {:DOWN, ^worker_ref, :process, ^worker, ^reason}, 2_000
        assert_receive {:mcp_socket_closed, _, ^socket}, 2_000

        send(
          c,
          {:mcp_http, state.generation, id, worker, {:ok, %{"content" => []}, "fixture-session"}}
        )

        :ok = :sys.resume(c)
        assert {:error, :timeout} = Task.await(task)
        assert :sys.get_state(c).pending == %{}
      after
        if Process.alive?(delayed), do: :erlang.resume_process(delayed)
        if Process.alive?(c), do: :sys.resume(c)
      end

      assert_receive {:DOWN, ^guardian_ref, :process, ^guardian, _}, 2_000
      refute Process.alive?(worker)
      refute Process.alive?(guardian)
    end
  end

  test "HTTP authority ignores stdio bytes and results from a different worker", ctx do
    c = client(ctx)
    intercept(ctx.server, fn _ -> :hold end)
    task = Task.async(fn -> Client.call_tool(c, "echo", %{}) end)

    assert_receive {:mcp_request, _, socket_worker,
                    %{json: %{"method" => "tools/call", "id" => id}}},
                   2_000

    {_, _, body} = response(id, "forged")
    send(c, {nil, {:data, body <> "\n"}})
    send(c, {:mcp_http, :sys.get_state(c).generation, id, self(), {:ok, %{"content" => []}, nil}})
    assert map_size(:sys.get_state(c).pending) == 1
    assert Task.yield(task, 0) == nil
    Server.release(socket_worker, response(id, "real"))
    assert {:ok, "real"} = Task.await(task)
  end

  test "owner kill during initialize closes socket and never sends cancellation", ctx do
    Server.handler(ctx.server, fn _ -> :hold end)

    owner =
      spawn(fn ->
        Client.start_link(
          transport: :streamable_http,
          url: ctx.url,
          finch: __MODULE__.Pool,
          name: __MODULE__.Initializing,
          timeout: 2_000
        )
      end)

    assert_receive {:mcp_request, _, socket_worker, %{json: %{"method" => "initialize"}}}, 2_000
    c = Process.whereis(__MODULE__.Initializing)
    ref = Process.monitor(c)
    [pending] = Map.values(:sys.get_state(c).pending)
    worker_ref = Process.monitor(pending.worker)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^ref, :process, ^c, _}, 2_000
    assert_receive {:DOWN, ^worker_ref, :process, _, _}, 2_000
    assert_receive {:mcp_socket_closed, _, ^socket_worker}, 2_000
    assert [%{json: %{"method" => "initialize"}}] = Server.journal(ctx.server)
  end

  test "stalled DELETE is bounded, closes its socket and stops Client", ctx do
    c = client(ctx, control_timeout: 100)

    Server.handler(ctx.server, fn
      %{method: "DELETE"} -> :hold
      req -> Server.normal(req)
    end)

    ref = Process.monitor(c)
    task = Task.async(fn -> Client.close(c) end)
    assert_receive {:mcp_request, _, socket_worker, %{method: "DELETE"}}, 2_000
    assert {:error, :timeout} = Task.await(task)
    assert_receive {:DOWN, ^ref, :process, ^c, :normal}, 2_000
    assert_receive {:mcp_socket_closed, _, ^socket_worker}, 2_000
  end

  test "cancel worker admission is capped and close kills stalled cancellation", ctx do
    c = client(ctx, max_control_workers: 1)
    :sys.replace_state(c, &%{&1 | timeout: 100})

    Server.handler(ctx.server, fn
      %{json: %{"method" => method}} when method in ["tools/call", "notifications/cancelled"] ->
        :hold

      req ->
        Server.normal(req)
    end)

    assert {:error, :timeout} = Client.call_tool(c, "echo", %{})

    assert_receive {:mcp_request, _, cancel_socket,
                    %{json: %{"method" => "notifications/cancelled"}}},
                   2_000

    assert {:error, :timeout} = Client.call_tool(c, "echo", %{})
    assert map_size(:sys.get_state(c).controls) == 1

    assert Enum.count(
             Server.journal(ctx.server),
             &match?(%{json: %{"method" => "notifications/cancelled"}}, &1)
           ) == 1

    assert :ok = Client.close(c)
    assert_receive {:mcp_socket_closed, _, ^cancel_socket}, 2_000
  end

  test "network SSE line/event limits reject beyond exact boundary", ctx do
    c = client(ctx)
    {_, _, body} = response(1)

    :sys.replace_state(c, fn s ->
      %{
        s
        | http: %{s.http | max_event_bytes: byte_size(body), max_line_bytes: byte_size(body) + 6}
      }
    end)

    intercept(ctx.server, fn %{json: %{"id" => id}} ->
      {_, _, data} = response(id)
      {:stream, ["data: " <> data <> "\n\n"], :hold}
    end)

    assert {:ok, "ok"} = Client.call_tool(c, "echo", %{})

    :sys.replace_state(c, fn s ->
      %{s | http: %{s.http | max_event_bytes: byte_size(body) - 1}}
    end)

    assert {:error, :sse_event_limit} = Client.call_tool(c, "echo", %{})

    :sys.replace_state(c, fn s ->
      %{
        s
        | http: %{s.http | max_event_bytes: byte_size(body), max_line_bytes: byte_size(body) + 5}
      }
    end)

    assert {:error, :sse_line_limit} = Client.call_tool(c, "echo", %{})
  end

  test "request byte boundary is inclusive; session/header bounds and duplicate keys are strict",
       ctx do
    c = client(ctx)

    bytes =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "echo", "arguments" => %{}}
      })

    :sys.replace_state(c, fn s -> %{s | http: %{s.http | max_request_bytes: byte_size(bytes)}} end)

    assert {:ok, "ok"} = Client.call_tool(c, "echo", %{})

    :sys.replace_state(c, fn s ->
      %{s | http: %{s.http | max_request_bytes: byte_size(bytes) - 1}}
    end)

    assert {:error, :request_byte_limit} = Client.call_tool(c, "echo", %{})
    :sys.replace_state(c, fn s -> %{s | http: %{s.http | max_request_bytes: 1_048_576}} end)

    intercept(ctx.server, fn %{json: %{"id" => id}} ->
      {200, [{"content-type", "application/json"}],
       "{\"jsonrpc\":\"2.0\",\"id\":#{id},\"id\":#{id},\"result\":{}}"}
    end)

    assert {:error, :duplicate_json_key} = Client.call_tool(c, "echo", %{})

    intercept(ctx.server, fn %{json: %{"id" => id}} ->
      {status, headers, body} = response(id)
      {status, [{"mcp-session-id", "changed"} | headers], body}
    end)

    assert {:error, :invalid_session_id} = Client.call_tool(c, "echo", %{})
    assert :sys.get_state(c).session == "fixture-session"
    :sys.replace_state(c, fn s -> %{s | http: %{s.http | max_header_bytes: 1}} end)
    assert {:error, :header_byte_limit} = Client.call_tool(c, "echo", %{})
  end

  test "stateless sessions still cancel; progress does not renew the total deadline", ctx do
    Server.handler(ctx.server, fn
      %{json: %{"method" => "initialize", "id" => id}} ->
        {status, headers, body} = Server.initialize(id)
        {status, List.keydelete(headers, "mcp-session-id", 0), body}

      %{json: %{"method" => "tools/call"}} ->
        event = "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\n\n"
        {:stream, [event, event, event], :hold}

      req ->
        Server.normal(req)
    end)

    c = client(ctx)
    :sys.replace_state(c, &%{&1 | timeout: 100})
    assert {:error, :timeout} = Client.call_tool(c, "echo", %{})
    assert_receive {:mcp_request, _, socket_worker, %{json: %{"method" => "tools/call"}}}, 2_000
    assert_receive {:mcp_socket_closed, _, ^socket_worker}, 2_000

    assert_receive {:mcp_request, _, _,
                    %{headers: headers, json: %{"method" => "notifications/cancelled"}}},
                   2_000

    refute Map.has_key?(headers, "mcp-session-id")
    assert :ok = Client.close(c)
    assert length(calls(ctx.server)) == 1
  end

  test "session and response header byte limits accept exact and reject plus one", ctx do
    session = String.duplicate("s", 256)

    Server.handler(ctx.server, fn
      %{json: %{"method" => "initialize", "id" => id}} -> Server.initialize(id, session)
      req -> Server.normal(req)
    end)

    c = client(ctx)
    assert :sys.get_state(c).session == session
    {_, headers, body} = response(1)

    all_headers =
      headers ++ [{"content-length", to_string(byte_size(body))}, {"connection", "close"}]

    size = Enum.reduce(all_headers, 0, fn {k, v}, n -> n + byte_size(k) + byte_size(v) end)
    :sys.replace_state(c, fn s -> %{s | http: %{s.http | max_header_bytes: size}} end)
    assert {:ok, "ok"} = Client.call_tool(c, "echo", %{})
    :sys.replace_state(c, fn s -> %{s | http: %{s.http | max_header_bytes: size - 1}} end)
    assert {:error, :header_byte_limit} = Client.call_tool(c, "echo", %{})
  end
end
