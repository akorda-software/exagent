defmodule ExAgent.ToolsTest do
  use ExUnit.Case, async: true

  alias ExAgent.{RunContext, Tool}
  alias ExAgent.Message.Part
  alias ExAgent.Test.SampleTools

  defmodule ContextTools do
    use ExAgent.Tools

    deftool quote_total(ctx, quantity :: integer(), fee :: integer()) do
      send(ctx.deps.observer, {:macro_context, ctx, quantity, fee})
      {:ok, %{"tenant" => ctx.deps.tenant, "total" => ctx.deps.unit_price * quantity + fee}}
    end
  end

  describe "tools/0 (macro-defined)" do
    test "returns Tool structs with derived schemas and descriptions" do
      tools = SampleTools.tools()
      names = Enum.map(tools, & &1.name)
      assert names == ["get_weather", "add", "ping"]

      weather = SampleTools.tool(:get_weather)
      assert %Tool{} = weather
      assert weather.description == "Get the weather for a city."
      assert weather.takes_ctx == true

      assert weather.parameters_json_schema == %{
               type: "object",
               properties: %{"city" => %{type: "string"}, "days" => %{type: "integer"}},
               required: ["city", "days"]
             }

      add = SampleTools.tool(:add)
      assert add.takes_ctx == false

      assert add.parameters_json_schema.properties == %{
               "a" => %{type: "integer"},
               "b" => %{type: "integer"}
             }

      assert SampleTools.tool(:ping).parameters_json_schema == %{
               type: "object",
               properties: %{},
               required: []
             }
    end
  end

  describe "call closure" do
    test "maps string-keyed args to positional, with ctx" do
      quote = ContextTools.tool(:quote_total)
      ctx = %RunContext{deps: %{observer: self(), tenant: "direct", unit_price: 7}}

      assert quote.call.(ctx, %{"quantity" => 3, "fee" => 2}) ==
               {:ok, %{"tenant" => "direct", "total" => 23}}

      assert_receive {:macro_context, ^ctx, 3, 2}
    end

    test "plain tool maps args without ctx" do
      add = SampleTools.tool(:add)
      assert add.call.(%{"a" => 2, "b" => 3}) == {:ok, 5}
    end

    test "the real function is still callable directly" do
      assert SampleTools.add(2, 3) == {:ok, 5}
    end
  end

  describe "integration with the agent loop" do
    test "agent executes a macro-defined tool, then finalizes" do
      model = %ExAgent.Models.Test{
        script: [
          {:tool_calls, [%Part.ToolCall{tool_name: "add", args: ~s({"a":2,"b":40})}]},
          "the sum is ready"
        ]
      }

      agent = ExAgent.new(model: model, tools: SampleTools.tools())

      assert {:ok, %{output: "the sum is ready", messages: messages}} = ExAgent.run(agent, "add")

      assert %Part.ToolReturn{tool_name: "add", content: 42} =
               find_part(messages, ExAgent.Message.Part.ToolReturn)
    end

    test "deftool with ctx receives the RunContext" do
      quote = ContextTools.tool(:quote_total)

      model = %ExAgent.Models.Test{
        script: [
          {:tool_calls,
           [
             %Part.ToolCall{
               tool_name: "quote_total",
               tool_call_id: "quote-ctx",
               args: ~s({"quantity":4,"fee":3})
             }
           ]},
          fn messages, _params ->
            %Part.ToolReturn{content: %{"tenant" => tenant, "total" => total}} =
              find_part(messages, Part.ToolReturn)

            "#{tenant}: #{total}"
          end
        ]
      }

      deps = %{observer: self(), tenant: "loop", unit_price: 11}
      agent = ExAgent.new(model: model, tools: [quote])
      assert {:ok, %{output: "loop: 47"} = result} = ExAgent.run(agent, "quote", deps: deps)

      assert_receive {:macro_context, ctx, 4, 3}
      assert ctx.deps == deps
      assert ctx.run_id == result.run_id
      assert ctx.tool_call_id == "quote-ctx"
      assert ctx.tool_name == "quote_total"
      assert ctx.run_step == 1

      assert %Part.ToolReturn{
               tool_call_id: "quote-ctx",
               status: :succeeded,
               content: %{"tenant" => "loop", "total" => 47}
             } = find_part(result.messages, Part.ToolReturn)
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
