defmodule ExAgent.OutputSchemaTest do
  use ExUnit.Case, async: true

  alias ExAgent.OutputSchema
  alias ExAgent.Test.{Receipt, Ticket, WeatherReport}

  describe "json_schema/1" do
    test "schemas without changeset keep the existing all-required fallback" do
      schema = OutputSchema.json_schema(ExAgent.Test.DefaultOutput)
      assert schema.required == ["name", "count"]
      assert schema.properties == %{"name" => %{type: "string"}, "count" => %{type: "integer"}}
      assert {:error, _} = OutputSchema.validate(ExAgent.Test.DefaultOutput, %{})

      assert {:error, _} =
               OutputSchema.validate(ExAgent.Test.DefaultOutput, %{"name" => nil, "count" => 1})

      assert {:ok, _} =
               OutputSchema.validate(ExAgent.Test.DefaultOutput, %{"name" => "x", "count" => 1})
    end

    test "optional embeds_one allows null but embeds_many keeps Ecto array semantics" do
      schema = OutputSchema.json_schema(ExAgent.Test.OptionalOutput)
      assert %{anyOf: [detail, %{type: "null"}]} = schema.properties["detail"]
      assert detail.required == ["name"]
      assert detail.properties["name"] == %{type: "string"}
      assert detail.properties["quantity"] == %{anyOf: [%{type: "number"}, %{type: "null"}]}
      assert detail.properties["unit_price"] == %{anyOf: [%{type: "number"}, %{type: "null"}]}
      assert %{type: "array", items: ^detail} = schema.properties["items"]

      assert {:ok, _} =
               OutputSchema.validate(ExAgent.Test.OptionalOutput, %{
                 "detail" => nil,
                 "items" => []
               })

      assert {:error, _} = OutputSchema.validate(ExAgent.Test.OptionalOutput, %{"items" => nil})

      assert {:error, _} =
               OutputSchema.validate(ExAgent.Test.OptionalOutput, %{"detail" => %{"name" => nil}})

      assert {:ok, _} =
               OutputSchema.validate(ExAgent.Test.OptionalOutput, %{
                 "detail" => %{"name" => "x", "quantity" => nil}
               })
    end

    test "an all-optional changeset permits omission and null, retaining constraints" do
      schema = OutputSchema.json_schema(ExAgent.Test.OptionalOutput)
      assert schema.required == []

      assert schema.properties["status"] == %{
               anyOf: [%{type: "string", enum: ["ready", "waiting"]}, %{type: "null"}]
             }

      assert schema.properties["note"] == %{
               anyOf: [%{type: "string", enum: ["short", "long"]}, %{type: "null"}]
             }

      assert schema.properties["score"] == %{
               anyOf: [%{type: "integer", minimum: 0}, %{type: "null"}]
             }

      assert schema.properties["tags"] == %{
               anyOf: [%{type: "array", items: %{type: "string"}}, %{type: "null"}]
             }

      assert {:ok, _} = OutputSchema.validate(ExAgent.Test.OptionalOutput, %{})

      assert {:ok, _} =
               OutputSchema.validate(
                 ExAgent.Test.OptionalOutput,
                 %{"note" => nil, "status" => nil, "score" => nil, "tags" => nil}
               )

      assert {:error, _} = OutputSchema.validate(ExAgent.Test.OptionalOutput, %{"score" => -1})

      assert {:error, _} =
               OutputSchema.validate(ExAgent.Test.OptionalOutput, %{"status" => "bad"})
    end

    test "optional null does not relax required fields" do
      schema = OutputSchema.json_schema(WeatherReport)
      assert schema.properties["city"] == %{type: "string"}

      assert {:ok, _} =
               OutputSchema.validate(
                 WeatherReport,
                 %{"city" => "Madrid", "temp_c" => 20, "condition" => nil}
               )

      assert {:error, _} =
               OutputSchema.validate(
                 WeatherReport,
                 %{"city" => nil, "temp_c" => 20}
               )

      assert %{anyOf: [_, %{type: "null"}]} = schema.properties["condition"]
    end

    test "derives properties and required from an Ecto schema" do
      schema = OutputSchema.json_schema(WeatherReport)

      assert schema.type == "object"

      # temp_c carries the validate_number constraints now (greater/less than →
      # exclusiveMinimum / exclusiveMaximum), so the model can comply.
      assert schema.properties == %{
               "city" => %{type: "string"},
               "temp_c" => %{type: "number", exclusiveMinimum: -100, exclusiveMaximum: 100},
               "condition" => %{
                 anyOf: [%{type: "string", enum: ["sunny", "rainy", "cloudy"]}, %{type: "null"}]
               }
             }

      # validate_required([:city, :temp_c]) → only those two are required
      assert schema.required == ["city", "temp_c"]
    end

    test "reflects validate_inclusion as an enum and validate_number as min/max" do
      schema = OutputSchema.json_schema(Ticket)

      assert schema.properties["category"] == %{
               type: "string",
               enum: ["billing", "bug", "feature", "other"]
             }

      assert schema.properties["priority"] == %{
               type: "integer",
               minimum: 1,
               maximum: 5
             }
    end

    test "embeds_many derives an array of nested object schemas" do
      schema = OutputSchema.json_schema(Receipt)

      assert schema.properties["items"] == %{
               type: "array",
               items: %{
                 type: "object",
                 properties: %{
                   "name" => %{type: "string"},
                   "quantity" => %{anyOf: [%{type: "number"}, %{type: "null"}]},
                   "unit_price" => %{anyOf: [%{type: "number"}, %{type: "null"}]}
                 },
                 required: ["name"]
               }
             }

      assert "items" in schema.required
    end

    test "snapshot: an empty required list and nullable properties reflect the changeset" do
      detail = %{
        type: "object",
        properties: %{
          "name" => %{type: "string"},
          "quantity" => %{anyOf: [%{type: "number"}, %{type: "null"}]},
          "unit_price" => %{anyOf: [%{type: "number"}, %{type: "null"}]}
        },
        required: ["name"]
      }

      expected = %{
        type: "object",
        properties: %{
          "note" => %{anyOf: [%{type: "string", enum: ["short", "long"]}, %{type: "null"}]},
          "status" => %{anyOf: [%{type: "string", enum: ["ready", "waiting"]}, %{type: "null"}]},
          "score" => %{anyOf: [%{type: "integer", minimum: 0}, %{type: "null"}]},
          "tags" => %{anyOf: [%{type: "array", items: %{type: "string"}}, %{type: "null"}]},
          "detail" => %{anyOf: [detail, %{type: "null"}]},
          "items" => %{type: "array", items: detail}
        },
        required: []
      }

      assert OutputSchema.json_schema(ExAgent.Test.OptionalOutput) == expected
    end

    test "required embeds stay non-null while nested optional fields follow their changesets" do
      schema = OutputSchema.json_schema(ExAgent.Test.NestedOptionalOutput)
      child = OutputSchema.json_schema(ExAgent.Test.OptionalOutput)

      assert schema.required == ["items", "detail"]
      assert child.required == []

      assert schema.properties == %{
               "detail" => child,
               "items" => %{type: "array", items: child}
             }

      assert {:ok, _} =
               OutputSchema.validate(ExAgent.Test.NestedOptionalOutput, %{
                 "detail" => %{},
                 "items" => [%{}]
               })

      for attrs <- [
            %{},
            %{"detail" => nil, "items" => [%{}]},
            %{"detail" => %{}, "items" => nil},
            %{"detail" => %{}, "items" => []}
          ] do
        assert {:error, _} = OutputSchema.validate(ExAgent.Test.NestedOptionalOutput, attrs)
      end
    end
  end

  describe "validate/2" do
    test "valid data → struct with cast atoms for enum" do
      assert {:ok, %WeatherReport{} = wr} =
               OutputSchema.validate(WeatherReport, %{
                 "city" => "Madrid",
                 "temp_c" => 22.0,
                 "condition" => "sunny"
               })

      assert wr.city == "Madrid"
      assert wr.temp_c == 22.0
      assert wr.condition == :sunny
    end

    test "out-of-range number fails validation" do
      assert {:error, errors} =
               OutputSchema.validate(WeatherReport, %{"city" => "X", "temp_c" => 200})

      assert Enum.any?(errors, &(&1.field == :temp_c))
    end

    test "missing required field fails" do
      assert {:error, errors} = OutputSchema.validate(WeatherReport, %{"temp_c" => 10.0})
      assert Enum.any?(errors, &(&1.field == :city))
    end

    test "unknown enum value fails" do
      assert {:error, errors} =
               OutputSchema.validate(WeatherReport, %{
                 "city" => "X",
                 "temp_c" => 1.0,
                 "condition" => "stormy"
               })

      assert Enum.any?(errors, &(&1.field == :condition))
    end
  end
end
