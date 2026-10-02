defmodule ExAgent.OutputSchemaContractTest do
  # Code unloading and Req defaults affect the VM, so these tests are serial.
  use ExUnit.Case, async: false

  alias ExAgent.OutputSchema
  alias ExAgent.Test.{NestedOptionalOutput, OptionalOutput, ReceiptItem}

  test "original schema API and default tool mode are preserved with explicit native selection" do
    assert OutputSchema.__info__(:functions) == [json_schema: 1, validate: 2]
    assert %ExAgent{output_type: :text, observability: nil} = ExAgent.new(model: "test")

    assert %ExAgent{output_type: OptionalOutput, output_mode: :tool} =
             ExAgent.new(model: "test", output: OptionalOutput)

    assert %ExAgent{output_type: OptionalOutput} =
             ExAgent.new(model: "test", output_type: OptionalOutput)

    assert Enum.sort(Map.keys(Map.from_struct(%ExAgent{}))) ==
             [
               :capabilities,
               :instructions,
               :max_history_bytes,
               :max_payload_bytes,
               :max_steps,
               :model,
               :name,
               :observability,
               :output_mode,
               :output_retries,
               :output_type,
               :settings,
               :tool_timeout,
               :tools,
               :usage_limits
             ]
  end

  test "reflection loads schema callbacks on first use, including embeds" do
    expected = OutputSchema.json_schema(OptionalOutput)
    unload_schema(OptionalOutput)
    unload_schema(ReceiptItem)

    assert OutputSchema.json_schema(OptionalOutput) == expected
    assert function_exported?(OptionalOutput, :changeset, 2)
    assert function_exported?(ReceiptItem, :changeset, 2)
  end

  test "validation loads the changeset even before schema generation" do
    unload_schema(OptionalOutput)
    assert {:ok, %{__struct__: OptionalOutput}} = OutputSchema.validate(OptionalOutput, %{})
    assert {:error, errors} = OutputSchema.validate(OptionalOutput, %{"score" => -1})
    assert Enum.any?(errors, &(&1.field == :score))
  end

  describe "agent emits enveloped final_result through stock ReqLLM (offline adapter)" do
    setup context do
      previous = Req.default_options()
      parent = self()

      Req.default_options(
        adapter:
          ExAgent.Test.ReqTransport.bind(fn request ->
            send(parent, {:body, Jason.decode!(request.body)})

            response = %{
              "model" => "offline",
              "choices" => [
                %{
                  "finish_reason" => "tool_calls",
                  "message" => %{
                    "role" => "assistant",
                    "content" => nil,
                    "tool_calls" => [
                      %{
                        "id" => "out1",
                        "type" => "function",
                        "function" => %{
                          "name" => "final_result",
                          "arguments" => Jason.encode!(%{"arguments" => context.output_args})
                        }
                      }
                    ]
                  }
                }
              ]
            }

            {request, Req.Response.new(status: 200, body: response)}
          end)
      )

      on_exit(fn -> Req.default_options(previous) end)
      :ok
    end

    for {schema_module, args} <- [
          {OptionalOutput, %{"note" => nil, "detail" => %{"name" => "x", "quantity" => nil}}},
          {NestedOptionalOutput, %{"detail" => %{}, "items" => [%{}]}}
        ] do
      @tag output_args: args
      test "#{inspect(schema_module)}: emitted tool reflects Ecto and preserves run results",
           context do
        model =
          ExAgent.Models.ReqLLM.new(
            model: %{
              provider: :openai,
              id: "offline",
              capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}},
              extra: %{wire: %{protocol: "openai_chat"}}
            },
            api_key: "offline",
            tool_profile: :chat_tools_v1
          )

        agent = ExAgent.new(model: model, output: unquote(schema_module))

        assert {:ok, result} = ExAgent.run(agent, "return structured data")

        assert {:ok, expected} =
                 OutputSchema.validate(unquote(schema_module), context.output_args)

        assert result.output == expected

        assert Enum.all?(
                 [:messages, :model, :new_messages, :output, :run_step, :usage],
                 &Map.has_key?(result, &1)
               )

        assert result.status == :succeeded
        assert is_binary(result.run_id)
        assert result.root_run_id == result.run_id
        assert result.parent_run_id == nil
        assert result.request_count == 1

        assert result.model == model
        assert result.run_step == 1
        assert result.new_messages == result.messages
        assert %ExAgent.Message.Usage{} = result.usage

        assert_receive {:body, body}
        assert body["tool_choice"] == "required"
        assert [tool] = body["tools"]
        assert tool["type"] == "function"
        assert tool["function"]["name"] == "final_result"

        envelope = tool["function"]["parameters"]
        assert envelope["required"] == ["arguments"]
        assert envelope["additionalProperties"] == false
        schema = envelope["properties"]["arguments"]

        assert schema ==
                 OutputSchema.json_schema(unquote(schema_module))
                 |> Jason.encode!()
                 |> Jason.decode!()

        if unquote(schema_module == OptionalOutput) do
          assert schema["required"] == []

          assert schema["properties"]["note"] == %{
                   "anyOf" => [
                     %{"type" => "string", "enum" => ["short", "long"]},
                     %{"type" => "null"}
                   ]
                 }
        else
          assert schema["required"] == ["items", "detail"]
          assert schema["properties"]["detail"]["type"] == "object"
          assert schema["properties"]["detail"]["required"] == []
          assert schema["properties"]["items"]["type"] == "array"
          assert schema["properties"]["items"]["items"] == schema["properties"]["detail"]
        end
      end
    end
  end

  defp unload_schema(mod) do
    Code.ensure_loaded!(mod)
    on_exit(fn -> Code.ensure_loaded!(mod) end)
    :code.purge(mod)
    assert :code.delete(mod)
    assert :code.is_loaded(mod) == false
    refute function_exported?(mod, :changeset, 2)
  end
end
