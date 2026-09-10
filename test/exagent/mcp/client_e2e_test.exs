defmodule ExAgent.MCP.ClientE2ETest do
  use ExUnit.Case, async: false

  alias ExAgent.MCP.Client
  alias ExAgent.Tool

  # A real end-to-end test of the stdio transport: spawns a tiny MCP server
  # (python) over a Port and exercises the full handshake → tools/list →
  # tools/call path. Skipped per-test when python3 isn't on PATH.
  @moduletag :mcp_e2e

  setup do
    if System.find_executable("python3") == nil do
      {:skip, "python3 not available"}
    else
      :ok
    end
  end

  test "spawns a server over stdio, lists tools, calls a tool" do
    python = System.find_executable("python3")
    script = python_mock_server()

    path =
      Path.join(System.tmp_dir!(), "exagent_mcp_mock_#{:erlang.unique_integer([:positive])}.py")

    File.write!(path, script)
    on_exit(fn -> File.rm(path) end)

    {:ok, client} =
      Client.start_link(command: python, args: [path], timeout: 5_000)

    port = :sys.get_state(client).transport_ref

    assert {:ok, [%Tool{name: "greet"} = tool]} = Client.tools(client)
    assert tool.description == "Greet someone"

    assert {:ok, "hi Ada"} = Client.call_tool(client, "greet", %{"name" => "Ada"})
    assert :ok = Client.close(client)
    assert Port.info(port) == nil
  end

  test "a real stdio process exit drains pending requests and permits safe close" do
    python = System.find_executable("python3")

    script = """
    import sys, json
    for line in sys.stdin:
        req = json.loads(line)
        if req.get("method") == "initialize":
            print(json.dumps({"jsonrpc": "2.0", "id": req["id"],
                              "result": {"capabilities": {}}}), flush=True)
        elif req.get("method") == "tools/list":
            sys.exit(7)
    """

    {:ok, client} = Client.start_link(command: python, args: ["-u", "-c", script], timeout: 5_000)
    port = :sys.get_state(client).transport_ref
    assert {:error, {:server_exited, 7}} = Client.tools(client)
    state = :sys.get_state(client)
    assert state.pending == %{}
    assert state.monitors == %{}
    refute state.ready
    assert {:error, :not_ready} = Client.tools(client)
    assert :ok = Client.close(client)
    assert Port.info(port) == nil
  end

  test "abnormal death of the owned Port returns errors without killing Client" do
    # Deliberately unlinked from this test: a regression must not kill the test
    # before it can report the missing controlled reply.
    {:ok, client} = GenServer.start(Client, waiting_server_opts())
    on_exit(fn -> if Process.alive?(client), do: Client.close(client) end)
    client_monitor = Process.monitor(client)
    tag = make_ref()
    send(client, {:"$gen_call", {self(), tag}, :tools})
    state = :sys.get_state(client)
    [{id, entry}] = Map.to_list(state.pending)
    port = state.transport_ref

    :erlang.exit(port, :kill)
    assert_receive {^tag, {:error, {:port_exited, :killed}}}, 2_000
    assert %{ready: false, pending: pending, monitors: monitors} = :sys.get_state(client)
    assert pending == %{}
    assert monitors == %{}
    assert Process.read_timer(entry.timer) == false
    refute_receive {:DOWN, ^client_monitor, :process, ^client, _}, 0

    send(client, {port, {:exit_status, 1}})
    send(client, {port, :eof})
    send(client, {:EXIT, port, :killed})

    send(
      client,
      {port, {:data, Jason.encode!(%{"id" => id, "result" => %{"tools" => []}}) <> "\n"}}
    )

    assert {:error, :not_ready} = Client.tools(client)
    refute_receive {^tag, _duplicate}, 0
    assert :ok = Client.close(client)
    assert_receive {:DOWN, ^client_monitor, :process, ^client, :normal}, 1_000
    assert Port.info(port) == nil
  end

  test "abnormal Port death is handled while initialize is waiting" do
    parent = self()
    worker = :proc_lib.spawn(fn -> initialize_waiting_port(parent) end)
    on_exit(fn -> if Process.alive?(worker), do: Process.exit(worker, :kill) end)
    monitor = Process.monitor(worker)
    assert_receive {:initialize_sent, ^worker, port}, 2_000
    :erlang.exit(port, :kill)
    assert_receive {:initialize_result, ^worker, {:stop, {:port_exited, :killed}}}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    assert Port.info(port) == nil
  end

  test "parent shutdown during initialize is not swallowed by Port exit trapping" do
    test = self()

    owner =
      spawn(fn ->
        :proc_lib.spawn_link(fn -> initialize_waiting_port(test) end)

        receive do
          :shutdown -> exit(:shutdown)
        end
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert_receive {:initialize_sent, worker, port}, 2_000
    worker_monitor = Process.monitor(worker)
    send(owner, :shutdown)
    assert_receive {:initialize_result, ^worker, {:stop, :shutdown}}, 2_000
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :normal}, 1_000
    assert Port.info(port) == nil
  end

  test "a supervisor can still shut down a ready Port-owning Client" do
    {:ok, supervisor} =
      Supervisor.start_link([{Client, waiting_server_opts()}], strategy: :one_for_one)

    on_exit(fn -> if Process.alive?(supervisor), do: Supervisor.stop(supervisor) end)
    [{_, client, :worker, _}] = Supervisor.which_children(supervisor)
    monitor = Process.monitor(client)
    tag = make_ref()
    send(client, {:"$gen_call", {self(), tag}, :tools})
    port = :sys.get_state(client).transport_ref

    Supervisor.stop(supervisor)
    assert_receive {^tag, {:error, {:client_stopped, :shutdown}}}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^client, :shutdown}, 1_000
    assert Port.info(port) == nil
  end

  defp waiting_server_opts do
    script = """
    import sys, json
    for line in sys.stdin:
        req = json.loads(line)
        if req.get("method") == "initialize":
            print(json.dumps({"id": req["id"], "result": {}}), flush=True)
    """

    [command: System.find_executable("python3"), args: ["-u", "-c", script], timeout: 10_000]
  end

  defp initialize_waiting_port(parent) do
    port =
      Port.open(
        {:spawn_executable, System.find_executable("python3")},
        [
          :binary,
          :use_stdio,
          :stream,
          :exit_status,
          args: ["-u", "-c", "import sys\nfor line in sys.stdin:\n    pass\n"]
        ]
      )

    send_fun = fn ^port, data ->
      true = Port.command(port, data)
      send(parent, {:initialize_sent, self(), port})
    end

    result = Client.init(transport: {send_fun, port}, timeout: 10_000)
    send(parent, {:initialize_result, self(), result})
  end

  # A minimal MCP server: reads newline-delimited JSON-RPC on stdin, replies on
  # stdout. Handles initialize / tools/list / tools/call.
  defp python_mock_server do
    """
    import sys, json
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue
        rid = req.get("id")
        if rid is None:
            continue  # notification, no reply
        m = req.get("method")
        if m == "initialize":
            r = {"capabilities": {}}
        elif m == "tools/list":
            r = {"tools": [{"name": "greet", "description": "Greet someone",
                            "inputSchema": {"type": "object",
                                            "properties": {"name": {"type": "string"}}}}]}
        elif m == "tools/call":
            name = (req.get("params", {}).get("arguments") or {}).get("name", "")
            r = {"content": [{"type": "text", "text": "hi " + name}]}
        else:
            r = {}
        sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": rid, "result": r}) + "\\n")
        sys.stdout.flush()
    """
  end
end
