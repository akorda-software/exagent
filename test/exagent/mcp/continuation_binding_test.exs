defmodule ExAgent.MCP.ContinuationBindingTest do
  use ExUnit.Case, async: false
  alias ExAgent.Continuation.Frame
  alias ExAgent.MCP.Client
  alias ExAgent.Test.MCPHTTPServer, as: HTTPServer
  alias ExAgent.{Continuation, Permissions, Store}
  alias ExAgent.Message.Part

  setup do
    first = start_supervised!({HTTPServer, owner: self()})
    second = start_supervised!({HTTPServer, owner: self()}, id: :second)

    start_supervised!(
      {Finch, name: __MODULE__.Pool, pools: %{default: [protocols: [:http1], size: 4]}}
    )

    start_supervised!({Store.ETS, table: __MODULE__})
    %{first: first, second: second, store: Store.scoped({Store.ETS, __MODULE__}, "mcp-binding")}
  end

  defp identity(principal \\ "account-one"),
    do: %{
      endpoint: %{"id" => "synthetic-service", "version" => "1"},
      principal: %{"id" => principal, "version" => "1"}
    }

  defp tool(remote, identity \\ identity(), credentials \\ "first-secret") do
    {:ok, client} =
      Client.start_link(
        transport: :streamable_http,
        url: HTTPServer.url(remote),
        finch: __MODULE__.Pool,
        timeout: 2_000,
        headers: [{"authorization", "Bearer " <> credentials}],
        continuation_binding: identity
      )

    Process.unlink(client)
    on_exit(fn -> if Process.alive?(client), do: GenServer.stop(client, :normal) end)
    {:ok, [tool]} = Client.tools(client)
    {client, tool}
  end

  defp agent(tool) do
    owner = self()

    model = %ExAgent.Models.Test{
      script: [
        fn ->
          send(owner, :model_first)

          {:tool_calls,
           [%Part.ToolCall{tool_name: "echo", tool_call_id: "one", args: %{"text" => "effect"}}]}
        end,
        fn ->
          send(owner, :model_second)
          "done"
        end
      ]
    }

    ExAgent.new(model: model, tools: [tool])
  end

  defp opts(store),
    do: [
      permissions: Permissions.new!(default: :ask),
      continuation: %{
        store: store,
        id: "conversation",
        durability: :ephemeral,
        expires_at: nil,
        deadline_at: nil,
        lease_ms: 60_000,
        active_time_limit_ms: 30_000,
        definition: %{"id" => "mcp-agent", "version" => "1"},
        policy: %{"id" => "policy", "version" => "1"},
        model_ref: %{"id" => "test-model", "version" => "1"},
        model_codec: %{
          dump: fn model -> {:ok, %{"index" => model.index}} end,
          load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
        }
      }
    ]

  defp approve(store, paused) do
    {:ok, %{status: :pending, record: record}} = Continuation.get(store, "conversation")
    [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    {:ok, %{record: approved}} =
      Continuation.decide(store, "conversation", :approve,
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "approve",
        approval_id: id,
        payload_hash: approval["payload_hash"],
        actor: :trusted,
        authorize: fn :trusted, :approve, _ -> {:ok, "human"} end
      )

    %{paused.continuation | revision: approved["revision"]}
  end

  defp effects(remote),
    do: Enum.filter(HTTPServer.journal(remote), &match?(%{json: %{"method" => "tools/call"}}, &1))

  test "different HTTP endpoint or host principal cannot share a durable fingerprint", ctx do
    {_, first} = tool(ctx.first)
    {_, other_endpoint} = tool(ctx.second)
    {_, other_principal} = tool(ctx.first, identity("account-two"))
    assert ExAgent.Tool.definition(first) == ExAgent.Tool.definition(other_endpoint)
    assert ExAgent.Tool.definition(first) == ExAgent.Tool.definition(other_principal)
    assert {:ok, original} = Frame.fingerprint(first)
    assert {:ok, endpoint_hash} = Frame.fingerprint(other_endpoint)
    assert {:ok, principal_hash} = Frame.fingerprint(other_principal)
    refute original == endpoint_hash
    refute original == principal_hash
  end

  test "approval refuses changed target before model or tool IO and remains usable by original",
       ctx do
    {_, first} = tool(ctx.first)
    {_, changed} = tool(ctx.second)
    original = agent(first)
    opts = opts(ctx.store)
    assert {:ok, %{status: :paused} = paused} = ExAgent.run(original, "go", opts)
    assert_receive :model_first
    reference = approve(ctx.store, paused)
    first_before = length(HTTPServer.journal(ctx.first))
    second_before = length(HTTPServer.journal(ctx.second))

    assert {:error, %{reason: :continuation_tools_changed}} =
             ExAgent.resume(agent(changed), reference, opts)

    refute_received :model_second
    assert length(HTTPServer.journal(ctx.first)) == first_before
    assert length(HTTPServer.journal(ctx.second)) == second_before
    assert effects(ctx.first) == [] and effects(ctx.second) == []
    assert {:ok, %{status: :approved}} = Continuation.get(ctx.store, "conversation")

    assert {:ok, %{status: :succeeded, output: "done", request_count: 2, tool_calls: 1}} =
             ExAgent.resume(original, reference, opts)

    assert_receive :model_second
    assert length(effects(ctx.first)) == 1 and effects(ctx.second) == []
    refute_received :model_first
  end

  test "principal change rejects before IO while same-principal credential rotation resumes once",
       ctx do
    {client, original_tool} = tool(ctx.first)
    {_, wrong_principal} = tool(ctx.first, identity("account-two"), "wrong-secret")
    {_, rotated} = tool(ctx.first, identity(), "rotated-secret")
    assert {:ok, original_hash} = Frame.fingerprint(original_tool)
    assert Frame.fingerprint(rotated) == {:ok, original_hash}
    assert ExAgent.Tool.definition(rotated) == ExAgent.Tool.definition(original_tool)
    opts = opts(ctx.store)
    assert {:ok, %{status: :paused} = paused} = ExAgent.run(agent(original_tool), "go", opts)
    assert_receive :model_first
    reference = approve(ctx.store, paused)
    {:ok, %{record: before_record}} = Continuation.get(ctx.store, "conversation")
    bytes = Jason.encode!(before_record)

    for private <- [
          "first-secret",
          "rotated-secret",
          "wrong-secret",
          "fixture-session",
          "#PID",
          HTTPServer.url(ctx.first)
        ] do
      refute bytes =~ private
    end

    before = length(HTTPServer.journal(ctx.first))

    assert {:error, %{reason: :continuation_tools_changed}} =
             ExAgent.resume(agent(wrong_principal), reference, opts)

    assert length(HTTPServer.journal(ctx.first)) == before
    refute_received :model_second
    assert {:ok, %{record: ^before_record}} = Continuation.get(ctx.store, "conversation")
    assert :ok = GenServer.stop(client, :normal)

    assert {:ok, %{status: :succeeded, request_count: 2, tool_calls: 1}} =
             ExAgent.resume(agent(rotated), reference, opts)

    [effect] = effects(ctx.first)
    assert effect.headers["authorization"] == "Bearer rotated-secret"
    assert_receive :model_second
    refute_received :model_first
    assert {:error, _} = ExAgent.resume(agent(rotated), reference, opts)
    assert length(effects(ctx.first)) == 1
    {:ok, %{status: :completed, record: complete}} = Continuation.get(ctx.store, "conversation")
    refute Jason.encode!(complete) =~ "rotated-secret"
  end

  test "bound approval preserves schema and tighter authority", ctx do
    {_, bound} = tool(ctx.first)
    opts = opts(ctx.store)
    assert {:ok, %{status: :paused} = paused} = ExAgent.run(agent(bound), "go", opts)
    assert_receive :model_first
    reference = approve(ctx.store, paused)
    before = length(HTTPServer.journal(ctx.first))
    changed = %{bound | parameters_json_schema: %{"type" => "object", "required" => ["new"]}}

    assert {:error, %{reason: :continuation_tools_changed}} =
             ExAgent.resume(agent(changed), reference, opts)

    assert length(HTTPServer.journal(ctx.first)) == before
    refute_received :model_second
    restricted = Keyword.put(opts, :permissions, Permissions.new!(default: :deny))

    assert {:ok, %{status: :succeeded} = result} =
             ExAgent.resume(agent(bound), reference, restricted)

    assert effects(ctx.first) == []

    assert [%Part.ToolReturn{status: :denied}] =
             for(
               message <- result.messages,
               part <- message.parts,
               match?(%Part.ToolReturn{}, part),
               do: part
             )

    assert_receive :model_second
    refute_received :model_first
  end

  test "unbound MCP is ordinary-usable but fails closed before durable model/tool IO", ctx do
    {_, unbound} = tool(ctx.first, nil)
    assert {:error, :tool_continuation_binding_required} = Frame.fingerprint(unbound)
    before = length(HTTPServer.journal(ctx.first))

    assert {:error, %{reason: :tool_continuation_binding_required}} =
             ExAgent.run(agent(unbound), "go", opts(ctx.store))

    refute_received :model_first
    assert length(HTTPServer.journal(ctx.first)) == before
    assert {:ok, record} = Store.load_record(ctx.store, :agent, "conversation")
    assert record["execution"]["effects"] == %{}
    assert record["execution"]["progress"]["runtime"]["scope"]["operations"] == []

    assert {:ok, %{output: "done"}} =
             ExAgent.run(agent(unbound), "ordinary",
               permissions: Permissions.new!(default: :allow)
             )

    assert length(effects(ctx.first)) == 1
  end

  test "invalid private identities and credentialized target reject before transport IO", ctx do
    basic = [transport: :streamable_http, url: HTTPServer.url(ctx.first), finch: __MODULE__.Pool]

    for bad <- [
          [continuation_binding: %{endpoint: identity().endpoint}],
          [continuation_binding: %{identity() | principal: %{"id" => "account"}}],
          [continuation_binding: Map.put(identity(), :token, "private-secret")],
          [
            continuation_binding: identity(),
            url: HTTPServer.url(ctx.first) <> "?token=private-secret"
          ],
          [continuation_binding: identity(), url: HTTPServer.url(ctx.first) <> "#fragment"],
          [continuation_binding: identity(), url: "http://user:private-secret@127.0.0.1:1/mcp"]
        ] do
      assert {:stop, :invalid_mcp_continuation_binding} = Client.init(Keyword.merge(basic, bad))
    end

    assert HTTPServer.journal(ctx.first) == []
  end

  test "local fingerprints stay byte-identical; public URI aliases bind equally but paths differ" do
    local = ExAgent.Tool.new(name: "local", takes_ctx: false, call: fn _ -> "ok" end)

    old = %{
      "definition" => ExAgent.Tool.definition(local),
      "kind" => "function",
      "takes_ctx" => false,
      "max_retries" => 1
    }

    assert {:ok, normalized} = ExAgent.Tool.JSON.normalize(old)
    assert Frame.fingerprint_data(local) == {:ok, normalized}
    assert Frame.fingerprint(local) == ExAgent.Continuation.Record.digest(normalized)
    config = [transport: :streamable_http, continuation_binding: identity()]

    assert {:ok, first} =
             ExAgent.MCP.Binding.from_options(config ++ [url: "https://EXAMPLE.invalid:443"])

    assert {:ok, ^first} =
             ExAgent.MCP.Binding.from_options(config ++ [url: "https://example.invalid/"])

    assert {:ok, changed} =
             ExAgent.MCP.Binding.from_options(config ++ [url: "https://example.invalid/other"])

    refute first == changed
    refute Map.has_key?(first, "url")
  end

  test "stdio discovery binds host references and the confirmed protocol without executable/env data" do
    owner = self()
    transport_ref = make_ref()

    send_fun = fn ^transport_ref, bytes ->
      request = Jason.decode!(IO.iodata_to_binary(bytes))
      send(owner, {:stdio_sent, request["method"]})

      result =
        case request["method"] do
          "initialize" ->
            %{"protocolVersion" => "2024-11-05", "capabilities" => %{}}

          "tools/list" ->
            %{"tools" => [%{"name" => "echo", "inputSchema" => %{"type" => "object"}}]}

          "tools/call" ->
            %{"content" => [%{"type" => "text", "text" => "done"}]}

          _ ->
            nil
        end

      if request["id"] != nil,
        do:
          send(
            self(),
            {transport_ref,
             {:data, Jason.encode!(%{"id" => request["id"], "result" => result}) <> "\n"}}
          )
    end

    {:ok, client} =
      Client.start_link(
        transport: {send_fun, transport_ref},
        continuation_binding: identity(),
        command: "private-command",
        args: ["private-arg"],
        env: [{"TOKEN", "private-env"}]
      )

    on_exit(fn -> if Process.alive?(client), do: Client.close(client) end)
    assert {:ok, [bound]} = Client.tools(client)
    assert {:ok, descriptor} = Frame.fingerprint_data(bound)
    assert descriptor["execution_binding"]["transport"] == "stdio"
    assert descriptor["execution_binding"]["protocol_version"] == "2024-11-05"

    for private <- ["private-command", "private-arg", "private-env", "#PID", "#Reference"] do
      refute Jason.encode!(descriptor) =~ private
    end

    assert bound.call.(%{}) == {:ok, "done"}
    assert :ok = Client.close(client)
    assert_receive {:stdio_sent, "initialize"}
    assert_receive {:stdio_sent, "notifications/initialized"}
    assert_receive {:stdio_sent, "tools/list"}
    assert_receive {:stdio_sent, "tools/call"}

    mismatched = fn ref, bytes ->
      request = Jason.decode!(IO.iodata_to_binary(bytes))
      send(owner, {:mismatch_sent, request["method"]})

      send(
        self(),
        {ref,
         {:data,
          Jason.encode!(%{
            "id" => request["id"],
            "result" => %{"protocolVersion" => "2025-06-18"}
          }) <> "\n"}}
      )
    end

    assert {:stop, :mcp_protocol_binding_mismatch} =
             Client.init(transport: {mismatched, make_ref()}, continuation_binding: identity())

    assert_receive {:mismatch_sent, "initialize"}
    refute_receive {:mismatch_sent, "notifications/initialized"}, 0
    refute_receive {:mismatch_sent, "tools/list"}, 0
  end

  test "transport/protocol/reference changes are in the durable fingerprint" do
    spec = %{"name" => "echo", "inputSchema" => %{"type" => "object"}}
    assert {:ok, stdio} = ExAgent.MCP.Binding.from_options(continuation_binding: identity())

    assert {:ok, changed_protocol} =
             ExAgent.MCP.Binding.from_options(
               continuation_binding: identity(),
               protocol_version: "2025-06-18"
             )

    assert {:ok, http} =
             ExAgent.MCP.Binding.from_options(
               continuation_binding: identity(),
               transport: :streamable_http,
               url: "https://example.invalid/mcp"
             )

    original = ExAgent.MCP.Protocol.to_tool(spec, fn _, _ -> "ordinary" end, stdio)
    assert {:ok, hash} = Frame.fingerprint(original)

    for changed <- [
          changed_protocol,
          http,
          put_in(stdio, ["endpoint", "version"], "2"),
          put_in(stdio, ["principal", "version"], "2")
        ] do
      tool = ExAgent.MCP.Protocol.to_tool(spec, fn _, _ -> "ordinary" end, changed)
      assert ExAgent.Tool.definition(tool) == ExAgent.Tool.definition(original)
      assert {:ok, other_hash} = Frame.fingerprint(tool)
      refute hash == other_hash
    end

    assert {:error, :tool_continuation_binding_required} =
             Frame.fingerprint(ExAgent.MCP.Protocol.to_tool(spec, fn _, _ -> "ordinary" end))

    assert {:error, :tool_continuation_binding_required} =
             Frame.fingerprint(ExAgent.MCP.Protocol.to_tool(spec, fn _, _ -> "ordinary" end, nil))
  end

  test "RequestData2 validates exact bound descriptors, independently of matching digests", ctx do
    alias ExAgent.Frame10OperationsFixture, as: F
    alias ExAgent.Continuation.{Record, RequestData}
    record = F.started(ctx.store)
    root = F.root(record)
    node = root["children"]["B"]
    {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"])
    {_, bound} = tool(ctx.first)

    run = %{
      prepared_tools: %{bound.name => bound},
      settings: %ExAgent.ModelSettings{},
      request_messages: nil,
      messages: messages,
      params: %{
        output_mode: :text,
        allow_text_output: true,
        output_object: nil,
        output_tools: [],
        instructions: []
      }
    }

    assert {:ok, data} = RequestData.capture(run, node["frame"], %{model_ref: F.ref()}, root)
    assert RequestData.valid10?(data)
    descriptor = data["tool_descriptors"][bound.name]
    assert descriptor["execution_binding"] == bound.execution_binding

    for invalid <- [
          Map.put(bound.execution_binding, "binding_version", 1.0),
          Map.put(bound.execution_binding, "credentials", "synthetic-private"),
          Map.delete(bound.execution_binding, "principal"),
          Map.put(bound.execution_binding, "target_hash", "bad"),
          Map.put(bound.execution_binding, "protocol_version", "other")
        ] do
      descriptor = Map.put(descriptor, "execution_binding", invalid)
      {:ok, digest} = Record.digest(descriptor)

      corrupt =
        data
        |> put_in(["tool_descriptors", bound.name], descriptor)
        |> put_in(["tools", bound.name], digest)

      refute RequestData.valid10?(corrupt)
    end
  end

  @tag timeout: 60_000
  test "fresh VMs restore approval bytes, reject retargeting and rotate same-principal credentials once",
       ctx do
    artifacts = System.get_env("EXAGENT_MCP_BINDING_ARTIFACTS")

    directory =
      Path.join(
        artifacts || System.tmp_dir!(),
        "mcp-binding-vm-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    unless artifacts, do: on_exit(fn -> File.rm_rf!(directory) end)

    handler = fn
      %{json: %{"method" => "initialize", "id" => id}} ->
        HTTPServer.initialize(id, "session-#{System.unique_integer([:positive])}")

      request ->
        HTTPServer.normal(request)
    end

    HTTPServer.handler(ctx.first, handler)
    HTTPServer.handler(ctx.second, handler)
    build_lib = :code.lib_dir(:exagent) |> to_string() |> Path.dirname()
    beams = Path.wildcard(Path.join([build_lib, "*", "ebin"]))
    assert Enum.any?(beams, &(Path.basename(Path.dirname(&1)) == "exagent"))

    common =
      [
        "-i",
        "PATH=" <> System.get_env("PATH"),
        "HOME=" <> System.user_home!(),
        "LANG=C.UTF-8",
        "ERL_FLAGS=+S 4:4",
        "EXAGENT_OFFLINE=1",
        System.find_executable("elixir")
      ] ++
        Enum.flat_map(beams, &["-pa", &1]) ++ ["test/support/mcp_binding_vm.exs"]

    phase = fn name, remote ->
      {output, code} =
        System.cmd("/usr/bin/env", common ++ [name, directory, HTTPServer.url(remote)],
          stderr_to_stdout: true
        )

      assert code == 0, output
      File.read!(Path.join(directory, name <> ".json")) |> Jason.decode!()
    end

    paused = phase.("pause", ctx.first)
    assert paused["status"] == "paused" and paused["client_closed"]
    assert effects(ctx.first) == [] and effects(ctx.second) == []
    assert File.read!(Path.join(directory, "models.txt")) == "model-first\n"
    pending_bytes = File.read!(Path.join(directory, "record.json"))

    for private <- [
          "synthetic-first-secret",
          "synthetic-rotated-secret",
          "session-",
          "#PID",
          HTTPServer.url(ctx.first)
        ] do
      refute pending_bytes =~ private
    end

    assert phase.("approve", ctx.first)["status"] == "approved"
    approved_bytes = File.read!(Path.join(directory, "record.json"))

    for {name, remote} <- [{"wrong-target", ctx.second}, {"wrong-principal", ctx.first}] do
      assert phase.(name, remote)["status"] == "rejected"
      assert File.read!(Path.join(directory, "record.json")) == approved_bytes
      assert File.read!(Path.join(directory, "models.txt")) == "model-first\n"
      assert effects(ctx.first) == [] and effects(ctx.second) == []
    end

    resumed = phase.("resume", ctx.first)

    assert resumed["status"] == "succeeded" and resumed["client_closed"] and
             resumed["pool_closed"]

    assert resumed["run_id"] == paused["run_id"]
    assert resumed["request_count"] == 2 and resumed["tool_calls"] == 1
    assert File.read!(Path.join(directory, "models.txt")) == "model-first\nmodel-second\n"
    [effect] = effects(ctx.first)
    assert effect.headers["authorization"] == "Bearer synthetic-rotated-secret"
    assert effects(ctx.second) == []
    finalized = File.read!(Path.join(directory, "record.json"))
    refute finalized =~ "synthetic-rotated-secret"
    refute finalized =~ "session-"
    assert Jason.decode!(finalized)["execution"]["state"] == "completed"

    File.write!(
      Path.join(directory, "verified.json"),
      Jason.encode!(%{vm_phases: 5, effects: 1, request_count: 2, tool_calls: 1})
    )
  end
end
