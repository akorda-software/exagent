defmodule ExAgent.MCPSchemaBoundaryTest do
  use ExUnit.Case, async: true

  alias ExAgent.{Message, RunError, Tool}
  alias ExAgent.Message.Part
  alias ExAgent.MCP.Client

  defmodule Executable do
    def json_schema do
      :ets.update_counter(__MODULE__, :callbacks, 1)
      %{"type" => "object"}
    end

    def __jsv__(_, builder) do
      :ets.update_counter(__MODULE__, :callbacks, 1)
      {:nocast, builder}
    end
  end

  setup do
    %{journal: start_supervised!({Agent, fn -> [] end})}
  end

  test "false survives discovery and primary inputSchema takes precedence over its alias", c do
    for fields <- [
          %{"inputSchema" => false},
          %{"input_schema" => false},
          %{"inputSchema" => false, "input_schema" => %{"type" => "object"}}
        ] do
      {client, tool} = discover(fields, c.journal)
      assert tool.parameters_json_schema === false
      assert {:ok, result} = run(tool, %{}, c.journal)
      assert [%Part.ToolReturn{status: :validation_error}] = returns(result)
      assert events(c.journal) == [:model, :model]
      close(client)
    end
  end

  test "present nil, invalid and executable schemas reject before model or remote effects", c do
    table = :ets.new(Executable, [:named_table, :public])
    :ets.insert(table, {:callbacks, 0})
    module = Atom.to_string(Executable)

    # Both callbacks really execute without preflight. Reset the observer before
    # checking the same serialized schemas arriving through tools/list.
    unsafe = [%{"x-jsv-cast" => [module]}, %{"$ref" => "jsv:module:" <> module}]

    for schema <- unsafe do
      assert {:ok, _} = JSV.build(schema, resolver: [], atoms: false)
      assert :ets.lookup_element(table, :callbacks, 2) > 0
      :ets.insert(table, {:callbacks, 0})
    end

    for fields <-
          [
            %{"inputSchema" => nil},
            %{"input_schema" => nil},
            %{"inputSchema" => nil, "input_schema" => %{"type" => "object"}},
            %{"inputSchema" => %{"type" => "not-a-type"}}
          ] ++ Enum.map(unsafe, &%{"inputSchema" => &1}) do
      {client, tool} = discover(fields, c.journal)

      assert {:error, %RunError{reason: {:invalid_tool_schema, _}, partial: result}} =
               run(tool, %{}, c.journal)

      assert result.request_count == 0
      assert events(c.journal) == []
      assert :ets.lookup_element(table, :callbacks, 2) == 0
      close(client)
    end
  end

  test "object validation, alias selection and absent-only fallback retain positive remote calls",
       c do
    schema = %{
      "type" => "object",
      "properties" => %{"value" => %{"type" => "integer"}},
      "required" => ["value"]
    }

    for fields <- [
          %{"inputSchema" => schema},
          %{"input_schema" => schema},
          %{"inputSchema" => schema, "input_schema" => false}
        ] do
      {client, tool} = discover(fields, c.journal)
      assert tool.parameters_json_schema == schema
      assert {:ok, result} = run(tool, %{"value" => 7}, c.journal)
      assert [%Part.ToolReturn{status: :succeeded, content: "saved"}] = returns(result)

      assert events(c.journal) == [
               :model,
               {:remote, %{"name" => "record", "arguments" => %{"value" => 7}}},
               :model
             ]

      assert {:ok, result} = run(tool, %{"value" => "7"}, c.journal)
      assert [%Part.ToolReturn{status: :validation_error}] = returns(result)
      assert events(c.journal) == [:model, :model]
      close(client)
    end

    {client, tool} = discover(%{}, c.journal)
    assert tool.parameters_json_schema == %{type: "object", properties: %{}}
    assert {:ok, result} = run(tool, %{}, c.journal)
    assert [%Part.ToolReturn{status: :succeeded, content: "saved"}] = returns(result)

    assert events(c.journal) == [
             :model,
             {:remote, %{"name" => "record", "arguments" => %{}}},
             :model
           ]

    close(client)
  end

  defp discover(fields, journal) do
    ref = make_ref()
    spec = Map.merge(%{"name" => "record"}, fields)

    send_fun = fn ^ref, bytes ->
      request = bytes |> IO.iodata_to_binary() |> Jason.decode!()

      result =
        case request["method"] do
          "initialize" ->
            %{"capabilities" => %{}}

          "tools/list" ->
            %{"tools" => [spec]}

          "tools/call" ->
            Agent.update(journal, &[{:remote, request["params"]} | &1])
            %{"content" => [%{"type" => "text", "text" => "saved"}]}

          _ ->
            nil
        end

      if request["id"] != nil do
        send(
          self(),
          {ref, {:data, Jason.encode!(%{"id" => request["id"], "result" => result}) <> "\n"}}
        )
      end

      :ok
    end

    client =
      start_supervised!(
        Supervisor.child_spec({Client, transport: {send_fun, ref}}, id: ref, restart: :temporary)
      )

    assert {:ok, [%Tool{} = tool]} = Client.tools(client)
    {client, tool}
  end

  defp run(tool, args, journal) do
    Agent.update(journal, fn _ -> [] end)

    model = %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          Agent.update(journal, &[:model | &1])

          {:tool_calls,
           [%Part.ToolCall{tool_name: "record", args: args, tool_call_id: "remote-1"}]}
        end,
        fn _, _ ->
          Agent.update(journal, &[:model | &1])
          "done"
        end
      ]
    }

    ExAgent.run(ExAgent.new(model: model, tools: [tool]), "go")
  end

  defp events(journal), do: Agent.get(journal, &Enum.reverse/1)

  defp returns(result),
    do: for(%Part.ToolReturn{} = part <- Message.parts(result.messages), do: part)

  defp close(client) do
    monitor = Process.monitor(client)
    assert :ok = Client.close(client)
    assert_receive {:DOWN, ^monitor, :process, ^client, :normal}, 1000
  end
end
