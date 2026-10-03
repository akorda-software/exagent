defmodule ExAgent.Scenarios.MCPHTTPAuthorityPreflightTest do
  use ExUnit.Case, async: true

  alias ExAgent.Continuation.Frame
  alias ExAgent.MCP.Protocol

  test "unbound MCP closures stay ordinary tools but cannot authorize durable effects" do
    spec = %{
      "name" => "lookup",
      "inputSchema" => %{"type" => "object", "properties" => %{}}
    }

    first_target = {"https://first.example.invalid/mcp", "principal-one"}
    second_target = {"https://second.example.invalid/mcp", "principal-two"}
    first = Protocol.to_tool(spec, fn _, _ -> {:ok, first_target} end)
    second = Protocol.to_tool(spec, fn _, _ -> {:ok, second_target} end)

    assert first.call.(%{}) != second.call.(%{})
    assert {:error, :tool_continuation_binding_required} = Frame.fingerprint(first)
    assert {:error, :tool_continuation_binding_required} = Frame.fingerprint(second)
  end
end

defmodule ExAgent.Scenarios.MCPHTTPAuthorityTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  alias ExAgent.MCP.Client
  alias ExAgent.Test.MCPHTTPServer, as: HTTPServer
  alias ExAgent.Message.Part
  alias ExAgent.Models.Test
  alias ExAgent.{Permissions, Server, CheckpointError}

  defmodule SaveStore do
    @behaviour ExAgent.Store
    def load_agent_snapshot(_, _), do: {:error, :not_found}

    def save_agent_snapshot(pid, snapshot) do
      Agent.get_and_update(pid, fn {mode, saves} -> {mode, {mode, [snapshot | saves]}} end)
    end

    def list_agent_snapshots(_), do: []
    def delete_agent_snapshot(_, _), do: :ok
    def load_session_snapshot(_, _), do: {:error, :not_found}
    def save_session_snapshot(_, _), do: {:error, :unsupported}
  end

  setup do
    remote = start_supervised!({HTTPServer, owner: self()})

    start_supervised!(
      {Finch, name: __MODULE__.Pool, pools: %{default: [protocols: [:http1], size: 4]}}
    )

    {:ok, client} =
      Client.start_link(
        transport: :streamable_http,
        url: HTTPServer.url(remote),
        finch: __MODULE__.Pool,
        timeout: 2_000
      )

    Process.unlink(client)

    on_exit(fn ->
      ref = Process.monitor(client)
      if Process.alive?(client), do: Process.exit(client, :kill)
      assert_receive {:DOWN, ^ref, :process, ^client, _}, 2_000
    end)

    {:ok, [tool]} = Client.tools(client)
    %{remote: remote, client: client, tool: tool}
  end

  defp effects(remote),
    do: Enum.filter(HTTPServer.journal(remote), &match?(%{json: %{"method" => "tools/call"}}, &1))

  defp model(args \\ %{"text" => "effect"}) do
    %Test{
      script: [
        {:tool_calls, [%Part.ToolCall{tool_name: "echo", tool_call_id: "one", args: args}]},
        "done"
      ]
    }
  end

  test "normal Tool boundary applies allow/ask/deny before HTTP effects", ctx do
    for decision <- [:deny, :ask] do
      agent = ExAgent.new(model: model(), tools: [ctx.tool])

      assert {:ok, _} =
               ExAgent.run(agent, "go",
                 permissions: Permissions.new!(rules: [{"echo", decision}])
               )

      assert effects(ctx.remote) == []
    end

    agent = ExAgent.new(model: model(), tools: [ctx.tool])

    assert {:ok, _} =
             ExAgent.run(agent, "go",
               permissions: Permissions.new!(rules: [{"echo", :ask}]),
               approve: fn _ ->
                 assert effects(ctx.remote) == []
                 :approve
               end
             )

    assert length(effects(ctx.remote)) == 1

    assert {:ok, _} =
             ExAgent.run(agent, "go", permissions: Permissions.new!(rules: [{"echo", :allow}]))

    assert length(effects(ctx.remote)) == 2
  end

  test "invalid arguments and unrepresentable schema never reach remote tools", ctx do
    agent = ExAgent.new(model: model(%{"text" => 42}), tools: [ctx.tool])
    ExAgent.run(agent, "go")
    assert effects(ctx.remote) == []
    parent = self()

    observer = %Test{
      script: [
        fn ->
          send(parent, :model_executed)
          "unused"
        end
      ]
    }

    tool = %{ctx.tool | parameters_json_schema: %{"$ref" => "https://example.invalid/schema"}}
    assert {:error, _} = ExAgent.run(ExAgent.new(model: observer, tools: [tool]), "go")
    refute_received :model_executed
    assert effects(ctx.remote) == []
  end

  test "checkpoint failure preserves a real HTTP effect and retry saves only", ctx do
    store = start_supervised!({Agent, fn -> {{:error, :offline}, []} end})
    agent = ExAgent.new(model: model(), tools: [ctx.tool])
    server = start_supervised!({Server, agent: agent, store: {SaveStore, store}})

    assert {:error, %CheckpointError{result: {:ok, %{output: "done"}}, revision: 1}} =
             Server.chat(server, "go")

    assert length(effects(ctx.remote)) == 1
    assert {:error, %CheckpointError{}} = Server.chat(server, "must not replay")
    Agent.update(store, fn {_, saves} -> {:ok, saves} end)
    assert :ok = Server.checkpoint(server)
    assert :ok = Server.checkpoint(server)
    assert length(effects(ctx.remote)) == 1
    assert {:ok, [saved, attempted]} = Agent.get(store, & &1)
    assert saved.revision == attempted.revision
    assert saved.message_history == attempted.message_history
  end
end
