# Test-only, single-writer disk fixture: exercises bytes across two fresh VMs.
# It is deliberately NOT a production Store or evidence of SQL/distributed CAS.
defmodule ContinuationRestartDisk do
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
        {:ok, r} -> r
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

defmodule ContinuationRestartTree do
  alias ExAgent.{Coordination, Message, Permissions, Tool}
  alias ExAgent.Message.{Part, Response, Usage}

  def refs(name),
    do: %{
      definition: %{"id" => name, "version" => "1"},
      policy: %{"id" => name, "version" => "1"},
      model_ref: %{"id" => "test", "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }

  def definition(write) do
    leaf =
      ExAgent.new(
        model: model(write, "leaf", [call("leaf-effect", "shared"), "leaf done"]),
        tools: [tool(write, "leaf-effect")]
      )

    leaf_tool =
      Coordination.delegation_tool(leaf,
        name: "leaf",
        continuation: refs("leaf"),
        permissions: Permissions.new!(default: :ask)
      )

    middle =
      ExAgent.new(
        model:
          model(write, "middle", [
            call("leaf", "shared", %{"prompt" => "leaf task"}),
            "middle done"
          ]),
        tools: [leaf_tool]
      )

    left =
      Coordination.delegation_tool(middle,
        name: "left",
        continuation: refs("middle"),
        estimate_cost: fn _ -> 7 end
      )

    right =
      ExAgent.new(
        model: model(write, "right", [call("right-effect", "shared"), "right done"]),
        tools: [tool(write, "right-effect")]
      )

    right_tool =
      Coordination.delegation_tool(right,
        name: "right",
        continuation: refs("right"),
        estimate_cost: fn _ -> 5 end
      )

    ExAgent.new(
      model:
        model(write, "root", [
          %Response{
            parts: [
              call("left", "left", %{"prompt" => "middle task"}),
              call("right", "right", %{"prompt" => "right task"}),
              call("sibling", "sibling")
            ]
          },
          "root done"
        ]),
      tools: [left, right_tool, tool(write, "sibling")]
    )
  end

  defp tool(write, name),
    do:
      Tool.new(
        name: name,
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          write.(name)
          "done"
        end
      )

  defp call(name, id, args \\ %{}),
    do: %Part.ToolCall{tool_name: name, tool_call_id: id, args: args}

  defp model(write, label, script) do
    %ExAgent.Models.Test{
      script:
        Enum.with_index(script, fn value, index ->
          fn _, _ ->
            write.("model-#{label}-#{index}")

            response =
              case value do
                %Part.ToolCall{} -> %Response{parts: [value]}
                %Response{} -> value
                text -> Message.new_response([%Part.Text{content: text}])
              end

            %{response | usage: %Usage{input_tokens: 1, output_tokens: 1}}
          end
        end)
    }
  end
end

[phase, directory] = System.argv()
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, disk} = GenServer.start_link(ContinuationRestartDisk, Path.join(directory, "record.json"))
store = ExAgent.Store.scoped({ContinuationRestartDisk, disk}, "restart-fixture")
journal = Path.join(directory, "effects.txt")
write = fn line -> File.write!(journal, line <> "\n", [:append]) end

tool =
  ExAgent.Tool.new(
    name: "effect",
    parameters_json_schema: %{"type" => "object"},
    call: fn _, _ ->
      write.("effect")
      {:ok, "saved"}
    end
  )

model = %ExAgent.Models.Test{
  script: [
    fn _, _ ->
      write.("model-first")

      {:tool_calls,
       [%ExAgent.Message.Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}]}
    end,
    fn _, _ ->
      write.("model-second")
      "done"
    end
  ]
}

agent = ExAgent.new(model: model, tools: [tool])

config = %{
  store: store,
  id: "conversation",
  durability: :durable,
  lease_ms: 60_000,
  expires_at: nil,
  deadline_at: nil,
  active_time_limit_ms: 30_000,
  definition: %{"id" => "restart", "version" => "1"},
  policy: %{"id" => "policy", "version" => "1"},
  model_ref: %{"id" => "model", "version" => "1"},
  model_codec: %{
    dump: fn m -> {:ok, %{"index" => m.index}} end,
    load: fn m, %{"index" => index} -> {:ok, %{m | index: index}} end
  }
}

opts = [continuation: config, permissions: ExAgent.Permissions.new!(default: :ask)]

{agent, opts} =
  if String.starts_with?(phase, "tree-") do
    config = Map.merge(config, ContinuationRestartTree.refs("root"))
    price = if phase == "tree-resume", do: 11, else: 2

    {ContinuationRestartTree.definition(write),
     [continuation: config, estimate_cost: fn _ -> price end]}
  else
    {agent, opts}
  end

case phase do
  "pause" ->
    {:ok, %{status: :paused, request_count: 1, tool_calls: 1}} =
      ExAgent.run(agent, "restart", opts)

    IO.puts("PAUSED_ACK")

  "resume" ->
    {:ok, %{status: :pending, record: r}} = ExAgent.Continuation.get(store, "conversation")
    [{id, approval}] = Map.to_list(r["execution"]["progress"]["approvals"])

    {:ok, %{record: approved}} =
      ExAgent.Continuation.decide(store, "conversation", :approve,
        record_id: r["record_id"],
        revision: r["revision"],
        operation_id: "approval",
        approval_id: id,
        payload_hash: approval["payload_hash"],
        actor: :host,
        authorize: fn :host, :approve, _ -> {:ok, "human"} end
      )

    ref = %{id: "conversation", record_id: approved["record_id"], revision: approved["revision"]}

    {:ok, %{status: :succeeded, output: "done", request_count: 2, tool_calls: 1}} =
      ExAgent.resume(agent, ref, opts)

    IO.puts("RESUMED_ONCE")

  "tree-pause" ->
    {:ok, %{status: :paused, request_count: 5, tool_calls: 6} = result} =
      ExAgent.run(agent, "tree", opts)

    10 = result.usage.accounting["cost"]["subtotal_cents"]
    {:ok, %{record: record}} = ExAgent.Continuation.get(store, "conversation")
    3 = map_size(record["execution"]["progress"]["runtime"]["children"])
    IO.puts("TREE_PAUSED_ACK")

  "tree-resume" ->
    {:ok, %{status: :pending, record: record}} = ExAgent.Continuation.get(store, "conversation")
    [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    {:ok, %{record: approved}} =
      ExAgent.Continuation.decide(store, "conversation", :approve,
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "tree-approval",
        approval_id: id,
        payload_hash: approval["payload_hash"],
        actor: :host,
        authorize: fn :host, :approve, _ -> {:ok, "human"} end
      )

    ref = %{id: "conversation", record_id: approved["record_id"], revision: approved["revision"]}

    {:ok, %{status: :succeeded, output: "root done", request_count: 8, tool_calls: 6} = result} =
      ExAgent.resume(agent, ref, opts)

    43 = result.usage.accounting["cost"]["subtotal_cents"]
    {:error, _} = ExAgent.resume(agent, ref, opts)
    IO.puts("TREE_RESUMED_ONCE")
end
