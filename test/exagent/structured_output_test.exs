defmodule ExAgent.StructuredOutputTest do
  use ExUnit.Case, async: true

  alias ExAgent
  alias ExAgent.Message.Part
  alias ExAgent.Test.WeatherReport

  @valid_args ~s({"city":"Madrid","temp_c":22.0,"condition":"sunny"})
  @invalid_args ~s({"city":"Madrid","temp_c":200})

  defmodule MappedEnums do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:numeric, Ecto.Enum, values: [pending: 0, done: 1])
      field(:named, Ecto.Enum, values: [pending: "P", done: "D"])
    end

    def changeset(s, a),
      do: s |> cast(a, [:numeric, :named]) |> validate_required([:numeric, :named])
  end

  defmodule EnumFollowingModel do
    @behaviour ExAgent.Model
    defstruct []

    @impl true
    def model_name(_), do: "enum-following-model"
    @impl true
    def system(_), do: "test"
    @impl true
    def profile(_),
      do: %ExAgent.ModelProfile{supports_tools: true, supports_json_schema_output: true}

    @impl true
    def request(model, _messages, _settings, params) do
      schema =
        case params.output_mode do
          :tool -> hd(params.output_tools).parameters_json_schema
          :native -> params.output_object.json_schema
        end

      data =
        Map.new(schema.properties, fn {field, definition} -> {field, hd(definition.enum)} end)

      part =
        case params.output_mode do
          :tool -> %Part.ToolCall{tool_name: "final_result", args: data}
          :native -> %Part.Text{content: Jason.encode!(data)}
        end

      {:ok, ExAgent.Message.new_response([part]), model}
    end
  end

  test "following mapped enum schemas succeeds in one request in tool and native modes" do
    for mode <- [:tool, :native] do
      agent =
        ExAgent.new(model: %EnumFollowingModel{}, output: MappedEnums, output_mode: mode)

      assert {:ok, %{output: %MappedEnums{numeric: :pending, named: :pending}} = result} =
               ExAgent.run(agent, "Return a status")

      assert result.request_count == 1
      refute find_part(result.messages, Part.Retry)
    end
  end

  describe "structured output via the output tool" do
    test "valid output call → returns a validated struct" do
      model = %ExAgent.Models.Test{
        script: [
          {:tool_calls, [%Part.ToolCall{tool_name: "final_result", args: @valid_args}]}
        ]
      }

      agent = ExAgent.new(model: model, output: WeatherReport)

      assert {:ok, %{output: %WeatherReport{} = wr}} = ExAgent.run(agent, "weather?")
      assert wr.city == "Madrid"
      assert wr.temp_c == 22.0
      assert wr.condition == :sunny
    end

    test "invalid output → retry → then valid succeeds, and a Retry part is recorded" do
      model = %ExAgent.Models.Test{
        script: [
          {:tool_calls,
           [%Part.ToolCall{tool_name: "final_result", args: @invalid_args, tool_call_id: "out1"}]},
          {:tool_calls,
           [%Part.ToolCall{tool_name: "final_result", args: @valid_args, tool_call_id: "out2"}]}
        ]
      }

      agent = ExAgent.new(model: model, output: WeatherReport, output_retries: 2)

      assert {:ok, %{output: wr, messages: messages}} = ExAgent.run(agent, "weather?")

      assert wr.temp_c == 22.0

      # The first invalid attempt should have produced a tool-scoped retry so
      # provider history can be replayed without a dangling tool call.
      assert %Part.Retry{tool_name: "final_result", tool_call_id: "out1"} =
               find_part(messages, ExAgent.Message.Part.Retry)
    end

    test "invalid output that never recovers → error after retries exhausted" do
      model = %ExAgent.Models.Test{
        script: [
          {:tool_calls, [%Part.ToolCall{tool_name: "final_result", args: @invalid_args}]},
          {:tool_calls, [%Part.ToolCall{tool_name: "final_result", args: @invalid_args}]}
        ]
      }

      agent = ExAgent.new(model: model, output: WeatherReport, output_retries: 1)

      assert {:error,
              %ExAgent.RunError{
                reason: {:unexpected_model_behavior, {:output_retries_exhausted, _}}
              }} =
               ExAgent.run(agent, "weather?")
    end

    test "text response in structured mode is ignored, model asked to call the tool" do
      model = %ExAgent.Models.Test{
        script: [
          "I think the weather is fine.",
          {:tool_calls, [%Part.ToolCall{tool_name: "final_result", args: @valid_args}]}
        ]
      }

      agent = ExAgent.new(model: model, output: WeatherReport, output_retries: 3)

      assert {:ok, %{output: %WeatherReport{city: "Madrid"}}} = ExAgent.run(agent, "weather?")
    end
  end

  defp find_part(messages, mod) do
    matcher = fn
      %struct{} = part -> if struct == mod, do: part, else: nil
      _ -> nil
    end

    Enum.find_value(messages, fn
      %ExAgent.Message.Request{parts: parts} -> Enum.find_value(parts, matcher)
      %ExAgent.Message.Response{parts: parts} -> Enum.find_value(parts, matcher)
      _ -> nil
    end)
  end
end
