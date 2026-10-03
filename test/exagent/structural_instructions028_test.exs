defmodule ExAgent.StructuralInstructions028Test do
  use ExUnit.Case, async: false

  alias ExAgent.{Continuation, Message, Store, UsageLimits}
  alias ExAgent.Continuation.Record
  alias ExAgent.Coordination.{Composition, Flow}

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    {:ok, store: Store.scoped({Store.ETS, __MODULE__}, "instructions028")}
  end

  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp branch(id, owner) do
    %{
      id: id,
      agent:
        ExAgent.new(
          instructions: ["System for #{id}", "Second system for #{id}"],
          model: %ExAgent.Models.Test{
            script: [
              fn messages, _ ->
                send(owner, {:model_called, id, hd(messages)})
                "OUTPUT_#{id}"
              end
            ]
          }
        ),
      definition: ref(id),
      policy: ref("policy"),
      model_ref: ref("test-model"),
      output_ref: ref("text"),
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, data -> {:ok, %{model | index: data["index"]}} end
      }
    }
  end

  defp definition(:sequence, steps) do
    {:ok, definition} = Composition.new(id: "definition", version: "1", steps: steps)
    {Composition, definition}
  end

  defp definition(:router, steps) do
    {:ok, definition} =
      Flow.new(
        id: "definition",
        version: "1",
        kind: :router,
        branches: steps,
        select_version: "1",
        select: fn _ -> "B" end
      )

    {Flow, definition}
  end

  defp definition(:parallel, steps) do
    {:ok, definition} =
      Flow.new(
        id: "definition",
        version: "1",
        kind: :parallel,
        branches: steps,
        max_concurrency: 2
      )

    {Flow, definition}
  end

  for kind <- [:sequence, :router, :parallel] do
    @tag kind: kind
    test "#{kind} retains system prefixes and completed reads perform no Model IO", context do
      kind = context.kind
      steps = [branch("A", self()), branch("B", self())]

      {module, definition} = definition(kind, steps)

      options = [
        continuation: %{
          store: context.store,
          id: "record",
          policy: ref("root-policy"),
          durability: :ephemeral,
          expires_at: nil,
          lease_ms: 180_000,
          active_time_limit_ms: 120_000
        },
        root_options: [usage_limits: %UsageLimits{request_limit: 4, tool_calls_limit: 3}]
      ]

      assert {:ok, result} = module.run(definition, "BOUND_INPUT", options)
      expected = if kind == :router, do: ["B"], else: ["A", "B"]
      assert result.status == :completed
      assert result.request_count == length(expected)
      assert result.tool_calls == 0

      for id <- expected do
        assert_receive {:model_called, ^id, %Message.Request{parts: parts}}

        assert [
                 %Message.Part.System{content: first},
                 %Message.Part.System{content: second},
                 %Message.Part.User{content: input}
               ] = parts

        assert first == "System for #{id}"
        assert second == "Second system for #{id}"
        assert input == if(kind == :sequence and id == "B", do: "OUTPUT_A", else: "BOUND_INPUT")
      end

      assert {:ok, %{status: :completed, record: record}} =
               Continuation.get(context.store, "record")

      assert :ok = Record.validate(record, {context.store.namespace, :agent, "record"})
      assert {:ok, again} = module.resume(definition, result.continuation, options)
      assert again.output == result.output
      assert again.request_count == result.request_count
      refute_receive {:model_called, _, _}

      # Data-only reads still reject a second user input or a system block after
      # the bound user. No tool/Model callback is involved in these corruptions.
      runtime = record["execution"]["progress"]["runtime"]
      {node_id, node} = Enum.at(runtime["children"], 0)
      [initial | rest] = Jason.decode!(node["snapshot"]["message_history"])
      [system1, system2, user] = initial["parts"]

      for parts <- [[system1, system2, user, user], [system1, user, system2]] do
        corrupt =
          put_in(
            record,
            [
              "execution",
              "progress",
              "runtime",
              "children",
              node_id,
              "snapshot",
              "message_history"
            ],
            Jason.encode!([%{initial | "parts" => parts} | rest])
          )

        assert {:error, :invalid_record} =
                 Record.validate(corrupt, {context.store.namespace, :agent, "record"})
      end
    end
  end
end
