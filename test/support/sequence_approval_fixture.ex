defmodule ExAgent.SequenceApprovalFixture do
  alias ExAgent.Coordination.Composition
  alias ExAgent.Message.Part.ToolCall

  defmodule Journal do
    alias ExAgent.Store
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, query), do: Store.ETS.scan_records(c.table, ns, query)

    def transition(c, key, revision, command) do
      operation = command["operation"]
      send(c.owner, {:journal_command, command})

      fault =
        Agent.get_and_update(c.control, fn
          {^operation, mode} -> {mode, nil}
          other -> {nil, other}
        end)

      if fault == :barrier do
        send(c.owner, {:before, operation, self()})

        receive do
          :release -> :ok
        end
      end

      result =
        if fault == :before,
          do: {:error, :before_commit},
          else: Store.ETS.transition(c.table, key, revision, command)

      send(c.owner, {:journal, operation, result})

      if fault == :ack_barrier do
        send(c.owner, {:after, operation, self()})

        receive do
          :release -> :ok
        end
      end

      if fault == :after, do: {:error, :lost_ack}, else: result
    end
  end

  def definition(effects, fresh \\ false) do
    steps =
      for id <- ~w(A B C) do
        tool =
          ExAgent.Tool.new(
            name: "effect",
            parameters_json_schema: %{
              "type" => "object",
              "properties" => %{"label" => %{"type" => "string"}},
              "required" => ["label"]
            },
            call: fn _, args ->
              if fresh and id == "A", do: raise("historical tool")
              File.write!(effects, args["label"] <> "\n", [:append])
              {:ok, "done"}
            end
          )

        script =
          case id do
            "A" ->
              [
                {:tool_calls,
                 [%ToolCall{tool_name: "effect", tool_call_id: "a", args: %{"label" => "A"}}]},
                "A output"
              ]

            "B" ->
              [
                {:tool_calls,
                 [
                   %ToolCall{tool_name: "effect", tool_call_id: "b1", args: %{"label" => "B1"}},
                   %ToolCall{tool_name: "effect", tool_call_id: "b2", args: %{"label" => "B2"}}
                 ]},
                "B output"
              ]

            "C" ->
              [
                fn _, _ ->
                  File.write!(effects, "C\n", [:append])
                  "C output"
                end
              ]
          end

        %{
          id: id,
          agent: ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: [tool]),
          definition: %{id: "leaf", version: "1"},
          policy: %{id: "policy", version: "1"},
          model_ref: %{id: "model", version: "1"},
          output_ref: %{id: "output", version: "1"},
          model_codec: %{
            dump: fn m ->
              if fresh and id == "A", do: raise("historical dump")
              {:ok, %{"index" => m.index}}
            end,
            load: fn m, data ->
              if fresh and id == "A", do: raise("historical load")
              {:ok, %{m | index: data["index"]}}
            end
          }
        }
      end

    {:ok, definition} = Composition.new(id: "sequence-approval", version: "1", steps: steps)
    definition
  end

  def config(store),
    do: %{
      store: store,
      id: "run",
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000
    }

  def options,
    do: [
      step_options: %{
        "B" => [permissions: ExAgent.Permissions.new!(default: :ask)]
      }
    ]

  def reference(record),
    do: %{
      version: 1,
      id: "run",
      record_id: record["record_id"],
      revision: record["revision"],
      run_id: record["execution"]["run_id"]
    }

  def decide(store, record, id, action \\ :approve) do
    ExAgent.Continuation.decide(store, "run", action,
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: "decision-#{record["revision"]}",
      actor: "human",
      authorize: fn actor, _, _ -> {:ok, actor} end,
      approval_id: id,
      payload_hash: record["execution"]["progress"]["approvals"][id]["payload_hash"]
    )
  end
end
