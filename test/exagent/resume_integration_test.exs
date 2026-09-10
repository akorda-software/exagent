defmodule ExAgent.ResumeIntegrationTest do
  use ExUnit.Case, async: true

  # The headline persistence feature: serialize a run's history, deserialize it,
  # and continue the same conversation in a fresh run via message_history:.
  alias ExAgent.{Message, Tool}
  alias ExAgent.Message.Part

  test "serialize → deserialize → resume continues the same conversation" do
    effects = :atomics.new(1, [])

    echo =
      Tool.new(
        name: "echo",
        description: "echo",
        parameters_json_schema: %{type: "object"},
        takes_ctx: false,
        call: fn %{"x" => x} ->
          :atomics.add(effects, 1, 1)
          {:ok, x}
        end
      )

    # First run: model calls echo("hello"), then finishes.
    model1 = %ExAgent.Models.Test{
      script: [
        {:tool_calls,
         [%Part.ToolCall{tool_name: "echo", tool_call_id: "echo-once", args: %{"x" => "hello"}}]},
        "first answer"
      ]
    }

    agent = ExAgent.new(model: model1, tools: [echo])
    {:ok, %{messages: history, output: "first answer"}} = ExAgent.run(agent, "greet")

    # Persist to JSON and back (simulating PG/Redis/file round-trip).
    json = Message.to_json(history)
    assert byte_size(json) > 0
    {:ok, restored} = Message.from_json(json)
    assert restored == history

    # Second run continues from the restored history: the model receives it, and
    # its new_messages are appended (not the whole thing again).
    parent = self()

    model2 = %ExAgent.Models.Test{
      script: [
        fn messages, _params ->
          send(parent, {:history_seen, messages})

          assert [
                   %Part.ToolReturn{
                     tool_call_id: "echo-once",
                     tool_name: "echo",
                     content: value,
                     status: :succeeded
                   }
                 ] =
                   Enum.filter(Message.parts(messages), &match?(%Part.ToolReturn{}, &1))

          "second answer: " <> value
        end
      ]
    }

    agent2 = ExAgent.new(model: model2, tools: [echo])

    {:ok, %{output: "second answer: hello", new_messages: new, messages: all}} =
      ExAgent.run(agent2, "follow up", message_history: restored)

    # the model on the second run saw the restored history (+ the new user prompt)
    assert_received {:history_seen, seen}
    assert Enum.take(seen, length(restored)) == restored
    assert %Message.Request{parts: [%Part.User{content: "follow up"}]} = List.last(seen)
    assert length(seen) == length(restored) + 1

    # new_messages is only this run's additions, not the whole conversation
    assert new == Enum.drop(all, length(restored))
    assert Enum.take(all, length(restored)) == restored
    assert length(new) == 2
    assert length(all) == length(restored) + 2
    assert :atomics.get(effects, 1) == 1
  end
end
