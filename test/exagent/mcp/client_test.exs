defmodule ExAgent.MCP.ClientTest do
  use ExUnit.Case, async: true

  alias ExAgent.MCP.Client
  alias ExAgent.Tool
  alias ExAgent.Test.TestingAuditCore

  # A deterministic in-process "MCP server". The client's send_fun routes bytes
  # here as {:sent, bin, from}; it replies with {ref, {:data, resp}} to `from`.
  # `respond` is (method, params) -> {:ok, result} | {:error, err} | {:chunks, fun}.
  defp start_mock(ref, respond) do
    TestingAuditCore.start_owned_mock(fn {:sent, bin, from} ->
      req = bin |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()

      unless req["id"] == nil do
        case respond.(req["method"], Map.get(req, "params", %{})) do
          {:ok, result} -> send_resp(ref, from, req["id"], result)
          {:error, err} -> send(ref, from, req["id"], "error", err)
          :noreply -> :ok
          {:chunks, fun} -> Enum.each(fun.(req["id"]), &send(from, {ref, {:data, &1}}))
        end
      end
    end)
  end

  defp send_resp(ref, from, id, result), do: send(ref, from, id, "result", result)

  defp send(ref, from, id, kind, body) do
    send(
      from,
      {ref, {:data, Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, kind => body}) <> "\n"}}
    )
  end

  defp client_with(ref, mock, opts \\ []) do
    send_fun = fn _r, bin -> send(mock, {:sent, bin, self()}) end

    Client.start_link(
      Keyword.merge([transport: {send_fun, ref}, command: "mock", timeout: 1_000], opts)
    )
  end

  defp default_respond do
    fn
      "initialize", _ ->
        {:ok, %{"capabilities" => %{}, "serverInfo" => %{"name" => "mock"}}}

      "tools/list", _ ->
        {:ok,
         %{
           "tools" => [
             %{
               "name" => "greet",
               "description" => "Greet someone",
               "inputSchema" => %{
                 "type" => "object",
                 "properties" => %{"name" => %{"type" => "string"}},
                 "required" => ["name"]
               }
             }
           ]
         }}

      "tools/call", %{"arguments" => %{"name" => name}} ->
        {:ok, %{"content" => [%{"type" => "text", "text" => "hi " <> name}]}}
    end
  end

  # Requests remain unanswered until the test supplies the winning terminal
  # message. The observed request and :sys.get_state form scheduling barriers.
  defp controlled_client(opts \\ []) do
    parent = self()
    ref = make_ref()

    send_fun = fn ^ref, data ->
      request = data |> IO.iodata_to_binary() |> Jason.decode!()

      case request do
        %{"method" => "initialize", "id" => id} ->
          send_resp(ref, self(), id, %{"capabilities" => %{}})

        %{"id" => _} ->
          send(parent, {:outbound, self(), ref, request})

        _ ->
          :ok
      end
    end

    {:ok, client} =
      Client.start_link(Keyword.merge([transport: {send_fun, ref}, timeout: 5_000], opts))

    on_exit(fn -> if Process.alive?(client), do: Client.close(client) end)
    {client, ref}
  end

  defp pending_request(client, request \\ :tools) do
    task =
      Task.async(fn ->
        case request do
          :tools -> Client.tools(client)
          {:call, name} -> Client.call_tool(client, name, %{})
        end
      end)

    assert_receive {:outbound, ^client, ref, %{"id" => id}}, 1_000
    state = :sys.get_state(client)
    {task, ref, id, Map.fetch!(state.pending, id)}
  end

  defp assert_clean(client, entries) do
    assert :sys.get_state(client).pending == %{}
    assert :sys.get_state(client).monitors == %{}

    for entry <- entries do
      assert Process.read_timer(entry.timer) == false
    end

    assert {:monitors, []} = Process.info(client, :monitors)
  end

  describe "pending ownership" do
    test "internal timeout returns an error and late replies cannot complete another request" do
      {client, ref} = controlled_client()
      {task, ^ref, id, entry} = pending_request(client)
      send(client, {:timeout, entry.timer, {:request_timeout, id}})
      assert {:error, :timeout} = Task.await(task)
      assert_clean(client, [entry])

      {next, ^ref, next_id, next_entry} = pending_request(client)
      assert next_id > id
      send_resp(ref, client, id, %{"tools" => [%{"name" => "late"}]})
      send(client, {:timeout, entry.timer, {:request_timeout, id}})
      assert Map.has_key?(:sys.get_state(client).pending, next_id)
      send_resp(ref, client, next_id, %{"tools" => []})
      assert {:ok, []} = Task.await(next)
      assert_clean(client, [next_entry])
    end

    test "the actual scheduled deadline expires without a GenServer.call timeout exit" do
      {client, ref} = controlled_client(timeout: 50)
      task = Task.async(fn -> Client.tools(client) end)
      assert_receive {:outbound, ^client, ^ref, _}, 1_000
      assert {:error, :timeout} = Task.await(task, 2_000)
      assert_clean(client, [])
    end

    test "a response wins once and stale timers or duplicate replies are ignored" do
      {client, ref} = controlled_client()
      {task, ^ref, id, entry} = pending_request(client)
      send_resp(ref, client, id, %{"tools" => []})
      send(client, {:timeout, entry.timer, {:request_timeout, id}})
      send_resp(ref, client, id, %{"tools" => [%{"name" => "duplicate"}]})
      assert {:ok, []} = Task.await(task)
      assert_clean(client, [entry])
    end

    test "the first processed terminal replies exactly once, even without call-alias filtering" do
      for winner <- [:response, :timeout] do
        {client, ref} = controlled_client()
        tag = make_ref()
        send(client, {:"$gen_call", {self(), tag}, :tools})
        assert_receive {:outbound, ^client, ^ref, %{"id" => id}}, 1_000
        entry = Map.fetch!(:sys.get_state(client).pending, id)

        terminal = fn
          :response -> send_resp(ref, client, id, %{"tools" => []})
          :timeout -> send(client, {:timeout, entry.timer, {:request_timeout, id}})
        end

        terminal.(winner)
        terminal.(:response)
        terminal.(:timeout)
        expected = if winner == :response, do: {:ok, []}, else: {:error, :timeout}
        assert_receive {^tag, ^expected}, 1_000
        assert_clean(client, [entry])
        refute_receive {^tag, _duplicate_reply}, 0
      end
    end

    test "caller death clears its monitor and timer without waiting for the deadline" do
      {client, ref} = controlled_client()
      caller = spawn(fn -> Client.tools(client) end)
      assert_receive {:outbound, ^client, ^ref, %{"id" => id}}, 1_000
      entry = Map.fetch!(:sys.get_state(client).pending, id)
      monitor = entry.monitor
      :erlang.trace(client, true, [:receive])

      Process.exit(caller, :kill)

      assert_receive {:trace, ^client, :receive, {:DOWN, ^monitor, :process, ^caller, :killed}},
                     1_000

      assert_clean(client, [entry])
      :erlang.trace(client, false, [:receive])

      send_resp(ref, client, id, %{"tools" => []})
      assert :sys.get_state(client).pending == %{}
    end

    test "multiple pending requests from one caller have independent cleanup" do
      {client, ref} = controlled_client()

      caller =
        spawn(fn ->
          send(client, {:"$gen_call", {self(), make_ref()}, :tools})
          send(client, {:"$gen_call", {self(), make_ref()}, :tools})

          receive do
            :stop -> :ok
          end
        end)

      assert_receive {:outbound, ^client, ^ref, %{"id" => first}}, 1_000
      assert_receive {:outbound, ^client, ^ref, %{"id" => second}}, 1_000
      assert first != second
      entries = Map.values(:sys.get_state(client).pending)
      assert length(entries) == 2
      :erlang.trace(client, true, [:receive])
      Process.exit(caller, :kill)

      for %{monitor: monitor} <- entries do
        assert_receive {:trace, ^client, :receive, {:DOWN, ^monitor, :process, ^caller, :killed}},
                       1_000
      end

      assert_clean(client, entries)
      :erlang.trace(client, false, [:receive])
    end

    test "remote calls remain concurrent and out-of-order replies retain ownership" do
      {client, ref} = controlled_client()
      {first, ^ref, first_id, first_entry} = pending_request(client, {:call, "first"})
      {second, ^ref, second_id, second_entry} = pending_request(client, {:call, "second"})
      assert map_size(:sys.get_state(client).pending) == 2

      send_resp(ref, client, second_id, %{"content" => [%{"text" => "second"}]})
      assert {:ok, "second"} = Task.await(second)
      assert Map.keys(:sys.get_state(client).pending) == [first_id]
      send_resp(ref, client, first_id, %{"content" => [%{"text" => "first"}]})
      assert {:ok, "first"} = Task.await(first)
      assert_clean(client, [first_entry, second_entry])
    end

    test "error responses finalize once and free request resources" do
      {client, ref} = controlled_client()
      {task, ^ref, id, entry} = pending_request(client)
      send(ref, client, id, "error", %{"code" => -32601, "message" => "unsupported"})
      assert {:error, %{"code" => -32601}} = Task.await(task)
      assert_clean(client, [entry])
    end

    test "transport exit drains all pending requests and late data cannot revive readiness" do
      {client, ref} = controlled_client()
      {first, ^ref, first_id, first_entry} = pending_request(client)
      {second, ^ref, second_id, second_entry} = pending_request(client, {:call, "effect"})
      send(client, {ref, {:exit_status, 7}})
      assert {:error, {:server_exited, 7}} = Task.await(first)
      assert {:error, {:server_exited, 7}} = Task.await(second)
      assert_clean(client, [first_entry, second_entry])

      send(client, {ref, {:exit_status, 7}})
      send_resp(ref, client, first_id, %{"tools" => []})
      send_resp(ref, client, second_id, %{"content" => [%{"text" => "late"}]})
      send(client, {ref, {:data, "partial late data"}})
      assert {:error, :not_ready} = Client.tools(client)
      assert %{ready: false, pending: %{}, buffer: ""} = :sys.get_state(client)
      assert :ok = Client.close(client)
    end

    test "both EOF transport message forms drain pending state" do
      for eof <- [:eof, {:eof, :closed}] do
        {client, ref} = controlled_client()
        {task, ^ref, _id, entry} = pending_request(client)
        send(client, {ref, eof})
        assert {:error, :eof} = Task.await(task)
        assert_clean(client, [entry])
        assert {:error, :not_ready} = Client.tools(client)
      end
    end

    test "close replies to outstanding callers before the client terminates" do
      {client, ref} = controlled_client()
      {first, ^ref, _id, first_entry} = pending_request(client)
      {second, ^ref, _id, second_entry} = pending_request(client)
      monitor = Process.monitor(client)
      assert :ok = Client.close(client)
      assert {:error, :closed} = Task.await(first)
      assert {:error, :closed} = Task.await(second)
      assert_receive {:DOWN, ^monitor, :process, ^client, :normal}, 1_000
      assert Process.read_timer(first_entry.timer) == false
      assert Process.read_timer(second_entry.timer) == false
    end

    test "max_pending rejects before sending and frees capacity after finalization" do
      {client, ref} = controlled_client(max_pending: 1)
      {task, ^ref, id, entry} = pending_request(client)
      assert {:error, :busy} = Client.tools(client)
      refute_receive {:outbound, ^client, ^ref, _}, 0
      assert :sys.get_state(client).id == id + 1

      send_resp(ref, client, id, %{"tools" => []})
      assert {:ok, []} = Task.await(task)
      assert_clean(client, [entry])
      {next, ^ref, next_id, _entry} = pending_request(client)
      send_resp(ref, client, next_id, %{"tools" => []})
      assert {:ok, []} = Task.await(next)
    end

    test "oversized complete and partial frames close the transport and empty its buffer" do
      for suffix <- ["", "\n"] do
        {client, ref} = controlled_client(max_frame_bytes: 128)
        {task, ^ref, _id, entry} = pending_request(client)
        send(client, {ref, {:data, String.duplicate("x", 100)}})
        assert byte_size(:sys.get_state(client).buffer) == 100
        send(client, {ref, {:data, String.duplicate("x", 29) <> suffix}})
        assert {:error, {:frame_too_large, 128}} = Task.await(task)
        assert_clean(client, [entry])
        assert %{ready: false, buffer: ""} = :sys.get_state(client)
      end
    end

    test "many small frames in one chunk are not mistaken for a single oversized frame" do
      {client, ref} = controlled_client(max_frame_bytes: 128)
      {task, ^ref, id, _entry} = pending_request(client)

      notification =
        Jason.encode!(%{"jsonrpc" => "2.0", "method" => "noop", "params" => %{}}) <> "\n"

      response =
        Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => %{"tools" => []}}) <> "\n"

      send(client, {ref, {:data, String.duplicate(notification, 10) <> response}})
      assert {:ok, []} = Task.await(task)
      assert :sys.get_state(client).ready
    end

    test "complete response prefixes survive an oversized tail regardless of chunk boundaries" do
      for chunked? <- [false, true], suffix <- ["", "\n"] do
        {client, ref} = controlled_client(max_frame_bytes: 128)
        {first, ^ref, first_id, first_entry} = pending_request(client, {:call, "first"})
        {second, ^ref, second_id, second_entry} = pending_request(client, {:call, "second"})
        {waiting, ^ref, _id, waiting_entry} = pending_request(client)

        prefix =
          Enum.map_join([first_id, second_id], fn id ->
            Jason.encode!(%{
              "jsonrpc" => "2.0",
              "id" => id,
              "result" => %{"content" => [%{"text" => "committed"}]}
            }) <> "\n"
          end)

        tail = String.duplicate("x", 129) <> suffix

        if chunked? do
          send(client, {ref, {:data, prefix}})
          assert map_size(:sys.get_state(client).pending) == 1
          send(client, {ref, {:data, tail}})
        else
          send(client, {ref, {:data, prefix <> tail}})
        end

        assert {:ok, "committed"} = Task.await(first)
        assert {:ok, "committed"} = Task.await(second)
        assert {:error, {:frame_too_large, 128}} = Task.await(waiting)
        assert_clean(client, [first_entry, second_entry, waiting_entry])
        assert %{ready: false, buffer: ""} = :sys.get_state(client)
      end
    end

    test "foreign transport frames cannot fulfill a pending request" do
      {client, ref} = controlled_client()
      {task, ^ref, id, _entry} = pending_request(client)
      send_resp(make_ref(), client, id, %{"tools" => [%{"name" => "foreign"}]})
      assert Map.has_key?(:sys.get_state(client).pending, id)
      send_resp(ref, client, id, %{"tools" => []})
      assert {:ok, []} = Task.await(task)
    end

    test "encoding failure returns an error without sending or leaking request ownership" do
      {client, ref} = controlled_client()
      assert {:error, {:encode_failed, _}} = Client.call_tool(client, "effect", %{pid: self()})
      refute_receive {:outbound, ^client, ^ref, _}, 0
      assert_clean(client, [])
      assert :sys.get_state(client).id == 2
    end

    test "malformed result mapping still finalizes the pending request" do
      {client, ref} = controlled_client()
      {task, ^ref, id, entry} = pending_request(client)
      send_resp(ref, client, id, %{"tools" => [123]})
      assert {:error, {:invalid_response, _}} = Task.await(task)
      assert_clean(client, [entry])
    end
  end

  describe "handshake and send boundary" do
    test "initialize before an oversized tail is recognized in one or multiple chunks" do
      parent = self()

      for chunked? <- [false, true] do
        ref = make_ref()

        send_fun = fn ^ref, data ->
          case Jason.decode!(IO.iodata_to_binary(data)) do
            %{"id" => id} ->
              notification = Jason.encode!(%{"method" => "noop", "params" => %{}}) <> "\n"
              response = Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => %{}}) <> "\n"
              prefix = notification <> response <> notification
              tail = String.duplicate("x", 129)
              chunks = if chunked?, do: [prefix, tail], else: [prefix <> tail]
              Enum.each(chunks, &send(self(), {ref, {:data, &1}}))

            %{"method" => "notifications/initialized"} ->
              send(parent, {:initialized, ref})
          end
        end

        assert {:ok, client} = Client.start_link(transport: {send_fun, ref}, max_frame_bytes: 128)
        assert_receive {:initialized, ^ref}, 1_000
        assert {:error, :not_ready} = Client.tools(client)
        assert %{ready: false, pending: %{}, buffer: ""} = :sys.get_state(client)
        assert :ok = Client.close(client)
      end
    end

    test "initialize is bound to its ref and leaves foreign messages in the mailbox" do
      ref = make_ref()
      foreign = make_ref()
      marker = make_ref()
      partial = "{\"jsonrpc\""

      send_fun = fn ^ref, data ->
        case Jason.decode!(IO.iodata_to_binary(data)) do
          %{"id" => id} ->
            send_resp(foreign, self(), id, %{"wrong" => true})
            send(self(), {:unrelated, marker})

            response =
              Jason.encode!(%{
                "jsonrpc" => "2.0",
                "id" => id,
                "result" => %{"capabilities" => %{}}
              })

            send(self(), {ref, {:data, response <> "\n" <> partial}})

          _ ->
            :ok
        end
      end

      assert {:ok, state} = Client.init(transport: {send_fun, ref})
      assert state.ready
      assert state.buffer == partial
      assert_receive {^foreign, {:data, _}}, 0
      assert_receive {:unrelated, ^marker}, 0
    end

    test "a foreign initialize response alone cannot complete the handshake" do
      ref = make_ref()
      foreign = make_ref()

      send_fun = fn ^ref, data ->
        %{"id" => id} = Jason.decode!(IO.iodata_to_binary(data))
        send_resp(foreign, self(), id, %{"capabilities" => %{}})
      end

      assert {:stop, :timeout} = Client.init(transport: {send_fun, ref}, timeout: 10)
      assert_receive {^foreign, {:data, _}}, 0
    end

    test "transport exit and oversized input fail initialize promptly" do
      for {message, expected} <- [
            {{:exit_status, 4}, {:server_exited, 4}},
            {:eof, :eof},
            {{:data, String.duplicate("x", 129)}, {:frame_too_large, 128}}
          ] do
        ref = make_ref()
        send_fun = fn ^ref, _data -> send(self(), {ref, message}) end
        assert {:stop, ^expected} = Client.init(transport: {send_fun, ref}, max_frame_bytes: 128)
      end
    end

    test "send errors, false, exceptions, throws and exits clean up and do not reuse IDs" do
      parent = self()
      ref = make_ref()

      send_fun = fn ^ref, data ->
        request = Jason.decode!(IO.iodata_to_binary(data))

        case request do
          %{"method" => "initialize", "id" => id} ->
            send_resp(ref, self(), id, %{"capabilities" => %{}})

          %{"method" => "tools/call", "id" => id, "params" => %{"name" => name}} ->
            send(parent, {:attempted, id})

            case name do
              "error" -> {:error, :unconfirmed}
              "false" -> false
              "raise" -> raise "send failure"
              "throw" -> throw(:send_failure)
              "exit" -> exit(:send_failure)
              "ok" -> send_resp(ref, self(), id, %{"content" => [%{"text" => "ok"}]})
            end

          _ ->
            :ok
        end
      end

      {:ok, client} = Client.start_link(transport: {send_fun, ref})
      on_exit(fn -> if Process.alive?(client), do: Client.close(client) end)

      for {name, id} <- Enum.with_index(["error", "false", "raise", "throw", "exit"], 1) do
        assert {:error, {:send_failed, _}} = Client.call_tool(client, name, %{})
        assert_receive {:attempted, ^id}, 0
        assert_clean(client, [])
      end

      assert {:ok, "ok"} = Client.call_tool(client, "ok", %{})
      assert_receive {:attempted, 6}, 0
      assert_clean(client, [])
    end

    test "a failed initialized notification does not mark the client ready" do
      ref = make_ref()

      send_fun = fn ^ref, data ->
        case Jason.decode!(IO.iodata_to_binary(data)) do
          %{"id" => id} -> send_resp(ref, self(), id, %{"capabilities" => %{}})
          _ -> {:error, :closed}
        end
      end

      assert {:stop, {:send_failed, :closed}} = Client.init(transport: {send_fun, ref})
    end

    test "invalid lifecycle limits fail before transport sends" do
      parent = self()
      ref = make_ref()
      send_fun = fn _, _ -> send(parent, :unexpected_send) end

      for key <- [:timeout, :max_pending, :max_frame_bytes],
          value <- [nil, 0, -1, :infinity, "5"] do
        assert {:stop, {:invalid_option, ^key}} =
                 Client.init([{key, value}, {:transport, {send_fun, ref}}])
      end

      refute_receive :unexpected_send, 0
    end
  end

  describe "stdio client (mock transport)" do
    test "handshakes, lists tools, and calls a tool end-to-end" do
      ref = make_ref()
      mock = start_mock(ref, default_respond())
      {:ok, client} = client_with(ref, mock)

      assert {:ok, [%Tool{name: "greet", description: "Greet someone"} = tool]} =
               Client.tools(client)

      # The discovered tool forwards to the server.
      assert tool.call.(%{"name" => "Ada"}) == {:ok, "hi Ada"}
      assert {:ok, "hi Bo"} = Client.call_tool(client, "greet", %{"name" => "Bo"})
    end

    test "handshake reassembles an initialize response split across chunks" do
      # Regression: await_response used to do `{lines, ""} = split_lines(chunk)`,
      # crashing when the initialize frame was split mid-line (a partial chunk
      # with no trailing newline). Now it buffers like the post-init path.
      ref = make_ref()

      respond = fn
        "initialize", _ ->
          {:chunks,
           fn id ->
             full =
               Jason.encode!(%{
                 "jsonrpc" => "2.0",
                 "id" => id,
                 "result" => %{"capabilities" => %{}, "serverInfo" => %{"name" => "split"}}
               }) <> "\n"

             # Split at an arbitrary byte boundary that is NOT a newline.
             <<a::binary-size(20), b::binary>> = full
             [a, b]
           end}

        "tools/list", _ ->
          {:ok, %{"tools" => []}}
      end

      mock = start_mock(ref, respond)
      {:ok, client} = client_with(ref, mock)

      # start_link completed the handshake across the split chunks.
      assert {:ok, []} = Client.tools(client)
    end

    test "reassembles a response split across data chunks (line buffering)" do
      ref = make_ref()

      respond = fn
        "initialize", _ ->
          {:ok, %{"capabilities" => %{}}}

        "tools/list", _ ->
          {:chunks,
           fn id ->
             full =
               Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => %{"tools" => []}}) <>
                 "\n"

             <<a::binary-size(15), b::binary>> = full
             [a, b]
           end}
      end

      mock = start_mock(ref, respond)
      {:ok, client} = client_with(ref, mock)

      assert {:ok, []} = Client.tools(client)
    end

    test "an error response surfaces as {:error, _}" do
      ref = make_ref()

      respond = fn
        "initialize", _ -> {:ok, %{"capabilities" => %{}}}
        "tools/list", _ -> {:error, %{"code" => -32601, "message" => "not supported"}}
      end

      mock = start_mock(ref, respond)
      {:ok, client} = client_with(ref, mock)

      assert {:error, %{"code" => -32601}} = Client.tools(client)
    end

    test "a tools/call with isError becomes an error" do
      ref = make_ref()

      respond = fn
        "initialize", _ ->
          {:ok, %{"capabilities" => %{}}}

        "tools/list", _ ->
          {:ok, %{"tools" => [%{"name" => "boom"}]}}

        "tools/call", _ ->
          {:ok, %{"isError" => true, "content" => [%{"type" => "text", "text" => "kaboom"}]}}
      end

      mock = start_mock(ref, respond)
      {:ok, client} = client_with(ref, mock)

      assert {:error, "kaboom"} = Client.call_tool(client, "boom", %{})
    end

    test "transport exit fails pending callers and leaves the client available for close" do
      ref = make_ref()
      parent = self()

      respond = fn
        "initialize", _ ->
          {:ok, %{"capabilities" => %{}}}

        "tools/list", _ ->
          send(parent, {:saw, :tools_list})
          :noreply
      end

      mock = start_mock(ref, respond)
      {:ok, client} = client_with(ref, mock)

      # A tools call that the mock never answers (it only notifies the test).
      task = Task.async(fn -> Client.tools(client) end)
      assert_receive {:saw, :tools_list}, 100

      send(client, {ref, {:exit_status, 1}})

      assert {:error, {:server_exited, 1}} = Task.await(task, 500)
      assert Process.alive?(client)
      Client.close(client)
    end
  end
end
