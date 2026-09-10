defmodule ExAgent.SchemaTest do
  use ExUnit.Case, async: true

  alias ExAgent.Schema

  defmodule MapTools do
    use ExAgent.Tools

    deftool configure(_ctx, opts :: map()) do
      {:ok, opts}
    end
  end

  describe "from_type/1 (scalars)" do
    test "String.t() / binary() / string() -> string" do
      assert Schema.from_type(quote(do: String.t())) == %{type: "string"}
      assert Schema.from_type(quote(do: binary())) == %{type: "string"}
      assert Schema.from_type(quote(do: string())) == %{type: "string"}
    end

    test "integer family" do
      assert Schema.from_type(quote(do: integer())) == %{type: "integer"}
      assert Schema.from_type(quote(do: pos_integer())) == %{type: "integer", minimum: 1}
      assert Schema.from_type(quote(do: non_neg_integer())) == %{type: "integer", minimum: 0}
    end

    test "float / number" do
      assert Schema.from_type(quote(do: float())) == %{type: "number"}
      assert Schema.from_type(quote(do: number())) == %{type: "number"}
    end

    test "map() reflects an object, including deftool parameters" do
      assert Schema.from_type(quote(do: map())) == %{type: "object"}
      tool = MapTools.tool(:configure)
      assert tool.parameters_json_schema.properties["opts"] == %{type: "object"}
      assert {:ok, _} = ExAgent.Tool.validate_args(tool, %{opts: %{enabled: true}})
      assert {:error, _} = ExAgent.Tool.validate_args(tool, %{opts: "not an object"})
    end

    test "boolean / atom" do
      assert Schema.from_type(quote(do: boolean())) == %{type: "boolean"}
      assert Schema.from_type(quote(do: atom())) == %{type: "string"}
    end

    test "annotated form unwraps to the type" do
      # `city :: String.t()`
      annotated = quote(do: city :: String.t())
      assert Schema.from_type(annotated) == %{type: "string"}
    end

    test "list of a type -> array" do
      assert Schema.from_type(quote(do: [String.t()])) ==
               %{type: "array", items: %{type: "string"}}
    end

    test "atom union -> string enum" do
      assert Schema.from_type(quote(do: :spam | :not_spam)) ==
               %{type: "string", enum: ["spam", "not_spam"]}
    end

    test "type unions and nullable branches are schemas, not enum AST values" do
      assert Schema.from_type(quote(do: integer() | String.t())) ==
               %{anyOf: [%{type: "integer"}, %{type: "string"}]}

      schema = Schema.from_type(quote(do: integer() | nil))
      assert schema == %{anyOf: [%{type: "integer"}, %{enum: [nil]}]}
      tool = ExAgent.Tool.new(parameters_json_schema: %{properties: %{value: schema}})
      assert {:ok, _} = ExAgent.Tool.validate_args(tool, %{value: 1})
      assert {:ok, _} = ExAgent.Tool.validate_args(tool, %{value: nil})
      assert {:error, _} = ExAgent.Tool.validate_args(tool, %{value: "1"})
    end

    test "literal unions preserve numeric, boolean, null and string JSON types" do
      assert Schema.from_type(quote(do: 1 | 2)) == %{enum: [1, 2]}
      assert Schema.from_type(quote(do: true | false | nil)) == %{enum: [true, false, nil]}
      assert Schema.from_type(quote(do: :ok | 1 | nil)) == %{enum: ["ok", 1, nil]}
    end

    test "unknown / any -> unconstrained" do
      assert Schema.from_type(quote(do: any())) == %{}
      assert Schema.from_type(quote(do: some_custom_type())) == %{}
      assert Schema.from_type(nil) == %{}
    end
  end

  describe "object_schema/1" do
    test "builds object with properties and required" do
      params = [
        {:city, quote(do: String.t())},
        {:days, quote(do: integer())}
      ]

      assert Schema.object_schema(params) == %{
               type: "object",
               properties: %{"city" => %{type: "string"}, "days" => %{type: "integer"}},
               required: ["city", "days"]
             }
    end

    test "empty params -> empty object" do
      assert Schema.object_schema([]) == %{type: "object", properties: %{}, required: []}
    end

    test "untyped param -> unconstrained property" do
      assert Schema.object_schema([{:x, nil}]) == %{
               type: "object",
               properties: %{"x" => %{}},
               required: ["x"]
             }
    end
  end
end
