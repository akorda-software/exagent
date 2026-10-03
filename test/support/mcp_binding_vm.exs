# Test-only, single-writer Store. It proves byte recovery across fresh VMs,
# not production durability, distributed CAS or SQL interoperability.
defmodule MCPBindingDisk do
  use GenServer
  alias ExAgent.Continuation.{Record, Transition}
  def capabilities(_), do: %{continuation: :atomic, durability: :durable}
  def load_record(pid, key), do: GenServer.call(pid, {:load, key})

  def transition(pid, key, revision, command),
    do: GenServer.call(pid, {:write, key, revision, command})

  def scan_records(_, _, _), do: {:error, :fixture_scan_not_implemented}
  def init(path), do: {:ok, path}
  def handle_call({:load, key}, _, path), do: {:reply, load(path, key), path}

  def handle_call({:write, key, revision, command}, _, path) do
    current =
      case load(path, key) do
        {:ok, record} -> record
        {:error, :not_found} -> nil
      end

    result = Transition.apply(current, key, revision, command, System.system_time(:millisecond))

    case result do
      {:ok, %{record: record}} ->
        {:ok, bytes} = Record.encode(record, key)
        :ok = File.write(path <> ".pending", bytes, [:binary])
        :ok = File.rename(path <> ".pending", path)

      _ ->
        :ok
    end

    {:reply, result, path}
  end

  defp load(path, key) do
    case File.read(path) do
      {:ok, bytes} -> Record.decode(bytes, key)
      {:error, :enoent} -> {:error, :not_found}
    end
  end
end

[phase, directory, url] = System.argv()
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, disk} = GenServer.start_link(MCPBindingDisk, Path.join(directory, "record.json"))
store = ExAgent.Store.scoped({MCPBindingDisk, disk}, "mcp-vm")

if phase == "approve" do
  {:ok, %{status: :pending, record: record}} = ExAgent.Continuation.get(store, "conversation")
  [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

  {:ok, %{record: approved}} =
    ExAgent.Continuation.decide(store, "conversation", :approve,
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: "human-approve",
      approval_id: id,
      payload_hash: approval["payload_hash"],
      actor: :host,
      authorize: fn :host, :approve, _ -> {:ok, "human"} end
    )

  File.write!(
    Path.join(directory, phase <> ".json"),
    Jason.encode!(%{status: "approved", revision: approved["revision"]})
  )

  IO.puts("MCP_APPROVAL_ACK")
else
  principal = if phase == "wrong-principal", do: "other-account", else: "account-one"

  credentials =
    if phase == "pause", do: "synthetic-first-secret", else: "synthetic-rotated-secret"

  {:ok, pool} =
    Finch.start_link(name: MCPBindingPool, pools: %{default: [protocols: [:http1], size: 4]})

  {:ok, client} =
    ExAgent.MCP.Client.start_link(
      transport: :streamable_http,
      url: url,
      finch: MCPBindingPool,
      timeout: 2_000,
      headers: [{"authorization", "Bearer " <> credentials}],
      continuation_binding: %{
        endpoint: %{"id" => "service", "version" => "1"},
        principal: %{"id" => principal, "version" => "1"}
      }
    )

  {:ok, [tool]} = ExAgent.MCP.Client.tools(client)
  write = fn line -> File.write!(Path.join(directory, "models.txt"), line <> "\n", [:append]) end

  model = %ExAgent.Models.Test{
    script: [
      fn ->
        write.("model-first")

        {:tool_calls,
         [
           %ExAgent.Message.Part.ToolCall{
             tool_name: "echo",
             tool_call_id: "call",
             args: %{"text" => "one-effect"}
           }
         ]}
      end,
      fn ->
        write.("model-second")
        "done"
      end
    ]
  }

  agent = ExAgent.new(model: model, tools: [tool])

  opts = [
    permissions: ExAgent.Permissions.new!(default: :ask),
    continuation: %{
      store: store,
      id: "conversation",
      durability: :durable,
      lease_ms: 60_000,
      active_time_limit_ms: 30_000,
      expires_at: nil,
      deadline_at: nil,
      definition: %{"id" => "mcp-vm", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      model_ref: %{"id" => "model", "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }
  ]

  summary =
    case phase do
      "pause" ->
        {:ok, %{status: :paused, request_count: 1, tool_calls: 1} = result} =
          ExAgent.run(agent, "go", opts)

        %{
          status: "paused",
          run_id: result.run_id,
          request_count: result.request_count,
          tool_calls: result.tool_calls
        }

      phase when phase in ["wrong-target", "wrong-principal", "resume"] ->
        {:ok, %{status: :approved, record: record}} =
          ExAgent.Continuation.get(store, "conversation")

        reference = %{
          id: "conversation",
          record_id: record["record_id"],
          revision: record["revision"]
        }

        case phase do
          "resume" ->
            {:ok, %{status: :succeeded, output: "done", request_count: 2, tool_calls: 1} = result} =
              ExAgent.resume(agent, reference, opts)

            {:error, _} = ExAgent.resume(agent, reference, opts)

            %{
              status: "succeeded",
              run_id: result.run_id,
              request_count: result.request_count,
              tool_calls: result.tool_calls
            }

          _ ->
            {:error, %{reason: :continuation_tools_changed}} =
              ExAgent.resume(agent, reference, opts)

            {:ok, %{record: ^record}} = ExAgent.Continuation.get(store, "conversation")

            %{
              status: "rejected",
              reason: "continuation_tools_changed",
              run_id: record["execution"]["run_id"]
            }
        end
    end

  :ok = GenServer.stop(client, :normal)
  :ok = Supervisor.stop(pool, :normal)
  false = Process.alive?(client)
  false = Process.alive?(pool)

  File.write!(
    Path.join(directory, phase <> ".json"),
    Jason.encode!(Map.merge(summary, %{client_closed: true, pool_closed: true}))
  )

  IO.puts("MCP_VM_" <> String.upcase(phase))
end
