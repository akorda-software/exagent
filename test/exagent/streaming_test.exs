defmodule ExAgent.StreamingTest do
  use ExUnit.Case, async: true

  alias ExAgent
  alias ExAgent.Message.{Part, Request}

  describe "ExAgent.run_stream/3 (offline via TestModel)" do
    test "emits text deltas then a final :result" do
      model = %ExAgent.Models.Test{label: "hello streaming world"}
      agent = ExAgent.new(model: model, instructions: "be brief")

      events = agent |> ExAgent.run_stream("hi") |> Enum.to_list()

      deltas = for {:delta, text} <- events, do: text
      assert Enum.join(deltas) == "hello streaming world"

      result =
        ExAgent.Test.TestingAuditCore.assert_successful_text_stream(
          events,
          "hello streaming world",
          "test"
        )

      assert result.model == model
      assert result.usage == %ExAgent.Message.Usage{input_tokens: 1, output_tokens: 1}
    end

    test "a full reduction retains the text and successful terminal" do
      model = %ExAgent.Models.Test{label: "one two three"}
      agent = ExAgent.new(model: model)

      {text, terminals} =
        ExAgent.run_stream(agent, "x")
        |> Enum.reduce({"", []}, fn
          {:delta, text}, {acc, terminals} -> {acc <> text, terminals}
          terminal, {acc, terminals} -> {acc, terminals ++ [terminal]}
        end)

      assert text == "one two three"
      assert [{:result, %{output: "one two three", status: :succeeded}}] = terminals
    end

    test "preserves instructions + user prompt in the streamed history" do
      model = %ExAgent.Models.Test{label: "ok"}
      agent = ExAgent.new(model: model, instructions: "be brief")

      {:result, %{messages: messages}} =
        ExAgent.run_stream(agent, "hi") |> Enum.to_list() |> List.last()

      assert [
               %Request{parts: [%Part.System{content: "be brief"}, %Part.User{content: "hi"}]},
               %ExAgent.Message.Response{}
             ] = messages
    end

    test "a :result still carries assembled usage" do
      model = %ExAgent.Models.Test{label: "tokens"}
      agent = ExAgent.new(model: model)

      {:result, %{usage: usage}} = ExAgent.run_stream(agent, "x") |> Enum.to_list() |> List.last()

      assert usage == %ExAgent.Message.Usage{input_tokens: 1, output_tokens: 1}
    end
  end
end
