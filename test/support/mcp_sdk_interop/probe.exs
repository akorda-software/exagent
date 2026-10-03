defmodule ExAgent.MCPSDKInterop.Probe do
  @moduledoc false
  import ExUnit.Assertions
  alias ExAgent.MCP.Client
  alias ExAgent.Message.Part
  alias ExAgent.Models.Test
  alias ExAgent.{Permissions, Tool}

  def run(config_path, selected) do
    config = config_path |> File.read!() |> Jason.decode!()
    assert System.get_env("EXAGENT_OFFLINE") == "1"
    assert Mix.env() == :test

    {:ok, pool} =
      Finch.start_link(
        name: __MODULE__.Finch,
        pools: %{default: [protocols: [:http1], size: 4, count: 1]}
      )

    try do
      config["profiles"]
      |> Enum.filter(&(&1["name"] == selected))
      |> Enum.each(&profile(&1, config))
    after
      Supervisor.stop(pool)
    end
  end

  defp profile(profile, config) do
    name = profile["name"]
    {:ok, client} = Client.start_link(options(profile, config))
    Process.unlink(client)
    before_state = :sys.get_state(client)
    port = before_state.transport_ref

    try do
      {:ok, tools} = Client.tools(client)
      assert Enum.sort(Enum.map(tools, & &1.name)) == ["echo", "fail", "large", "record"]
      record = Enum.find(tools, &(&1.name == "record"))
      {:ok, record} = Tool.prepare(record)
      schema = record.parameters_json_schema
      assert Enum.sort(schema["required"]) == ["text", "token"]
      assert Enum.sort(Map.keys(schema["properties"])) == ["text", "token"]
      assert schema["properties"]["text"]["type"] == "string"
      assert schema["properties"]["token"]["type"] == "string"

      text = "synthetic á🙂\nsecond line"
      echo_id = :sys.get_state(client).id
      {:ok, echo_text} = Client.call_tool(client, "echo", %{"text" => text})
      echo = Jason.decode!(echo_text)
      assert echo["text"] == text
      assert is_integer(echo["request_id"])
      assert echo["request_id"] == echo_id
      assert :sys.get_state(client).id == echo_id + 1

      before_calls = call_count(profile)

      for decision <- [:deny, :ask] do
        result = runtime(record, %{"token" => "blocked-#{decision}", "text" => text}, decision)
        assert result.status == :denied
        assert call_count(profile) == before_calls
      end

      invalid = runtime(record, %{"token" => "invalid", "text" => 42}, :allow)
      assert invalid.status == :validation_error
      assert call_count(profile) == before_calls

      allowed_id = :sys.get_state(client).id
      allowed = runtime(record, %{"token" => "allowed", "text" => text}, :allow)
      assert allowed.status == :succeeded
      allowed_json = Jason.decode!(allowed.content)
      assert allowed_json["token"] == "allowed"
      assert allowed_json["text"] == text
      assert is_integer(allowed_json["request_id"])
      assert allowed_json["request_id"] == allowed_id
      assert :sys.get_state(client).id == allowed_id + 1

      approved_id = :sys.get_state(client).id

      approved =
        runtime(record, %{"token" => "approved", "text" => text}, :ask,
          approve: fn _ -> :approve end
        )

      assert approved.status == :succeeded
      assert Jason.decode!(approved.content)["token"] == "approved"
      assert Jason.decode!(approved.content)["request_id"] == approved_id
      assert :sys.get_state(client).id == approved_id + 1
      assert call_count(profile) == before_calls + 2

      effects = journal(profile) |> Enum.filter(&(&1["event"] == "effect"))
      assert Enum.sort(Enum.map(effects, & &1["token"])) == ["allowed", "approved"]
      assert Enum.all?(effects, &(&1["text"] == text))
      assert length(Enum.uniq_by(effects, & &1["id"])) == 2

      {:error, failure} = Client.call_tool(client, "fail", %{})
      assert is_binary(failure)
      assert failure =~ "synthetic tool failure"

      if name != "stdio" do
        assert before_state.http.max_request_bytes == 65 * 1024
        assert before_state.http.max_response_bytes == 65 * 1024
        assert before_state.max_pending == 4
        assert before_state.http.max_tools == 4
        assert is_binary(before_state.session) == String.ends_with?(name, "-session")
        assert {:error, :response_byte_limit} = Client.call_tool(client, "large", %{})
        {:ok, recovered} = Client.call_tool(client, "echo", %{"text" => "after limit"})
        assert Jason.decode!(recovered)["text"] == "after limit"
      else
        assert before_state.max_frame_bytes == 8_388_608
        assert before_state.max_pending == 128
      end

      state = :sys.get_state(client)
      assert state.pending == %{}
      assert state.workers == %{}
      monitor = Process.monitor(client)
      assert :ok = Client.close(client)
      assert_receive {:DOWN, ^monitor, :process, ^client, :normal}, 2_000
      assert not Process.alive?(client)
      if is_port(port), do: assert(Port.info(port) == nil)

      requests = journal(profile) |> Enum.filter(&(&1["event"] == "request"))
      ids = requests |> Enum.map(& &1["id"]) |> Enum.reject(&is_nil/1)
      assert Enum.all?(ids, &is_integer/1)
      assert length(ids) == length(Enum.uniq(ids))
      initialized = Enum.filter(requests, &(&1["method"] == "notifications/initialized"))
      assert length(initialized) == 1

      result = %{
        profile: name,
        checks: [
          "discovery",
          "schema",
          "arguments",
          "IDs",
          "deny",
          "ask",
          "allow",
          "approval",
          "single effects",
          "tool error",
          "client cleanup"
        ],
        http_response_limit: name != "stdio",
        requests: length(ids),
        remote_effects: length(effects),
        runtime: %{elixir: System.version(), otp: System.otp_release()},
        transport_protocol: if(name == "stdio", do: "2024-11-05", else: "2025-06-18")
      }

      File.write!(profile["result"], Jason.encode!(result, pretty: true) <> "\n")
      IO.puts("MCP SDK INTEROP PASS " <> name)
    after
      if Process.alive?(client), do: Client.close(client)
    end
  end

  defp options(%{"name" => "stdio"} = profile, config) do
    [
      command: config["python"],
      args: ["-I", config["peer"], "--profile", "stdio", "--journal", profile["journal"]],
      cd: config["run_dir"],
      timeout: 5_000
    ]
  end

  defp options(profile, _config) do
    [
      transport: :streamable_http,
      url: profile["url"],
      finch: __MODULE__.Finch,
      timeout: 5_000,
      control_timeout: 2_000,
      max_pending: 4,
      max_request_bytes: 65 * 1024,
      max_response_bytes: 65 * 1024,
      max_line_bytes: 65 * 1024,
      max_event_bytes: 65 * 1024,
      max_tools: 4
    ]
  end

  defp runtime(tool, args, decision, options \\ []) do
    model = %Test{
      script: [
        {:tool_calls,
         [%Part.ToolCall{tool_name: tool.name, tool_call_id: "synthetic", args: args}]},
        "done"
      ]
    }

    agent = ExAgent.new(model: model, tools: [tool])
    permissions = Permissions.new!(rules: [{tool.name, decision}])

    assert {:ok, %{output: "done", messages: messages}} =
             ExAgent.run(
               agent,
               "synthetic request",
               Keyword.put(options, :permissions, permissions)
             )

    [result] = Enum.filter(ExAgent.Message.parts(messages), &match?(%Part.ToolReturn{}, &1))
    result
  end

  defp journal(profile) do
    profile["journal"]
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  defp call_count(profile) do
    Enum.count(journal(profile), &(&1["event"] == "request" and &1["method"] == "tools/call"))
  end
end

defmodule ExAgent.MCPSDKInterop.AcceptanceTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 30_000

  # This filename deliberately does not match *_test.exs: normal offline suites
  # never start peers or install an SDK. Only run.py explicitly selects it.
  config_path = System.fetch_env!("EXAGENT_MCP_SDK_CONFIG")
  profiles = config_path |> File.read!() |> Jason.decode!() |> Map.fetch!("profiles")

  for %{"name" => name} <- profiles do
    test "official SDK interop #{name}" do
      ExAgent.MCPSDKInterop.Probe.run(System.fetch_env!("EXAGENT_MCP_SDK_CONFIG"), unquote(name))
    end
  end
end
