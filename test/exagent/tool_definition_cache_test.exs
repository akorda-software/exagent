defmodule ExAgent.ToolDefinitionCacheTest do
  use ExUnit.Case, async: true

  alias ExAgent.{Message, RunError, Tool}
  alias ExAgent.Message.Part
  alias ExAgent.Models.Test, as: TestModel

  test "a reused definition still validates every call and never changes its schema" do
    owner = self()
    tool = value_tool(owner, "integer")
    agent = ExAgent.new(model: model_with_value(7), tools: [tool])

    for _ <- 1..2 do
      assert {:ok, result} = ExAgent.run(agent, "go")
      assert_receive {:effect, %{"value" => 7}}
      assert Message.to_json(result.messages) =~ "7"
    end

    invalid_call = %{agent | model: model_with_value("bad")}
    assert {:ok, result} = ExAgent.run(invalid_call, "go")
    assert [%Part.ToolReturn{status: :validation_error}] = returns(result)
    refute_receive {:effect, _}
    assert Tool.definition(hd(agent.tools)) == Tool.definition(tool)
  end

  test "changing a definition schema rebuilds validation instead of trusting a stale validator" do
    agent = ExAgent.new(model: model_with_value(7), tools: [value_tool(self(), "integer")])
    changed_tool = %{hd(agent.tools) | parameters_json_schema: schema("string")}
    changed = %{agent | tools: [changed_tool], model: model_with_value("new schema")}

    assert {:ok, result} = ExAgent.run(changed, "go")
    assert [%Part.ToolReturn{status: :succeeded}] = returns(result)
    assert_receive {:effect, %{"value" => "new schema"}}

    assert {:ok, result} = ExAgent.run(%{changed | model: model_with_value(7)}, "go")
    assert [%Part.ToolReturn{status: :validation_error}] = returns(result)
    refute_receive {:effect, _}

    assert {:ok, _} = ExAgent.run(agent, "go")
    assert_receive {:effect, %{"value" => 7}}
  end

  test "invalid schemas stay operational errors before the first model request" do
    owner = self()
    initial = value_tool(owner, "integer")
    invalid_schema = %{"type" => "not-a-json-schema-type"}

    model = %TestModel{
      script: [
        fn _, _ ->
          send(owner, :model_requested)
          "unexpected"
        end
      ]
    }

    # Both a newly supplied invalid schema and a changed cached definition use
    # the same preflight failure timing, with no constructor exception.
    invalid_agent =
      ExAgent.new(model: model, tools: [%{initial | parameters_json_schema: invalid_schema}])

    valid_agent = ExAgent.new(model: model, tools: [initial])

    changed_agent = %{
      valid_agent
      | tools: [%{hd(valid_agent.tools) | parameters_json_schema: invalid_schema}]
    }

    for agent <- [invalid_agent, changed_agent] do
      assert {:error, %RunError{reason: {:invalid_tool_schema, [_ | _]}, partial: partial}} =
               ExAgent.run(agent, "go")

      assert partial.run_step == 0
      assert partial.request_count == 0
      refute_receive :model_requested
      refute_receive {:effect, _}
    end
  end

  test "prepared definitions retain the JSON provider projection" do
    owner = self()
    tool = value_tool(owner, "integer")
    expected = Tool.definition(tool)

    model = %TestModel{
      script: [
        fn _, params ->
          wire = Enum.map(params.function_tools, &Tool.definition/1)
          send(owner, {:wire, Jason.encode!(wire)})
          "done"
        end
      ]
    }

    agent = ExAgent.new(model: model, tools: [tool])
    assert {:ok, result} = ExAgent.run(agent, "go")
    assert_receive {:wire, json}
    assert json == Jason.encode!([expected])
    refute json =~ "prepared_validator"
    refute Message.to_json(result.messages) =~ "prepared_validator"
  end

  defp schema(type),
    do: %{
      "type" => "object",
      "properties" => %{"value" => %{"type" => type}},
      "required" => ["value"]
    }

  defp value_tool(owner, type),
    do:
      Tool.new(
        name: "value",
        takes_ctx: false,
        parameters_json_schema: schema(type),
        call: fn args ->
          send(owner, {:effect, args})
          {:ok, args}
        end
      )

  defp model_with_value(value),
    do: %TestModel{
      script: [
        {:tool_calls, [%Part.ToolCall{tool_name: "value", args: %{"value" => value}}]},
        "done"
      ]
    }

  defp returns(result),
    do: Enum.filter(Message.parts(result.messages), &match?(%Part.ToolReturn{}, &1))
end
