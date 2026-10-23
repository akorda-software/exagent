defmodule ExAgent.OutputSchemaReflectionTest do
  use ExUnit.Case, async: true

  alias ExAgent.{OutputSchema, Tool}

  defmodule Inclusion do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:number, :integer)
      field(:fraction, :float)
      field(:flag, :boolean)
      field(:status, Ecto.Enum, values: [:ready, :waiting])
    end

    def changeset(s, a) do
      s
      |> cast(a, [:number, :fraction, :flag, :status])
      |> validate_required([:number, :fraction, :flag, :status])
      |> validate_inclusion(:number, [1, 2])
      |> validate_inclusion(:fraction, [0.5, 1.5])
      |> validate_inclusion(:flag, [true])
      |> validate_inclusion(:status, [:ready])
    end
  end

  defmodule Exclusion do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:number, :integer)
      field(:flag, :boolean)
      field(:status, Ecto.Enum, values: [:ready, :waiting])
    end

    def changeset(s, a) do
      s
      |> cast(a, [:number, :flag, :status])
      |> validate_required([:number, :flag, :status])
      |> validate_exclusion(:number, [1, 2])
      |> validate_exclusion(:flag, [false])
      |> validate_exclusion(:status, [:waiting])
    end
  end

  defmodule Length do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:text, :string)
      field(:code, :string)
      field(:items, {:array, :string})
      field(:pair, {:array, :string})
    end

    def changeset(s, a) do
      s
      |> cast(a, [:text, :code, :items, :pair])
      |> validate_required([:text, :code, :items, :pair])
      |> validate_length(:text, min: 2, max: 3, count: :codepoints)
      |> validate_length(:code, is: 2, count: :codepoints)
      |> validate_length(:items, min: 2, max: 3)
      |> validate_length(:pair, is: 2)
    end
  end

  defmodule CountModes do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:graphemes, :string)
      field(:bytes, :string)
    end

    def changeset(s, a) do
      s
      |> cast(a, [:graphemes, :bytes])
      |> validate_length(:graphemes, is: 1)
      |> validate_length(:bytes, is: 2, count: :bytes)
    end
  end

  defmodule BooleanEnumInclusion do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:status, Ecto.Enum, values: [true, false, :pending])
      field(:flag, :boolean)
    end

    def changeset(s, a) do
      s
      |> cast(a, [:status, :flag])
      |> validate_required([:status, :flag])
      |> validate_inclusion(:status, [true])
      |> validate_inclusion(:flag, [true])
    end
  end

  defmodule BooleanEnumExclusion do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:status, Ecto.Enum, values: [true, false, :pending])
      field(:flag, :boolean)
    end

    def changeset(s, a) do
      s
      |> cast(a, [:status, :flag])
      |> validate_required([:status, :flag])
      |> validate_exclusion(:status, [false])
      |> validate_exclusion(:flag, [false])
    end
  end

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

  defmodule MappedEnumConstraints do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:numeric_inclusion, Ecto.Enum, values: [pending: 0, done: 1])
      field(:numeric_exclusion, Ecto.Enum, values: [pending: 0, done: 1])
      field(:named_inclusion, Ecto.Enum, values: [pending: "P", done: "D"])
      field(:named_exclusion, Ecto.Enum, values: [pending: "P", done: "D"])
    end

    def changeset(s, a) do
      fields = [:numeric_inclusion, :numeric_exclusion, :named_inclusion, :named_exclusion]

      s
      |> cast(a, fields)
      |> validate_required(fields)
      |> validate_inclusion(:numeric_inclusion, [:done])
      |> validate_inclusion(:named_inclusion, [:done])
      |> validate_exclusion(:numeric_exclusion, [:pending])
      |> validate_exclusion(:named_exclusion, [:pending])
    end
  end

  defmodule CrossedStringEnum do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:status, Ecto.Enum, values: [foo: "bar", bar: "baz"])
      field(:included, Ecto.Enum, values: [foo: "bar", bar: "baz"])
      field(:excluded, Ecto.Enum, values: [foo: "bar", bar: "baz"])
    end

    def changeset(s, a) do
      s
      |> cast(a, [:status, :included, :excluded])
      |> validate_required([:status, :included, :excluded])
      |> validate_inclusion(:included, [:bar])
      |> validate_exclusion(:excluded, [:foo])
    end
  end

  # Fixed schemas vary keyword order and the order of chained validations.
  # No test-time option state or generated validator oracle.
  for {name, validations} <- [
        {"IsMinMax", [[is: 2, min: 1, max: 3]]},
        {"IsMaxMin", [[is: 2, max: 3, min: 1]]},
        {"MinIsMax", [[min: 1, is: 2, max: 3]]},
        {"MaxIsMin", [[max: 3, is: 2, min: 1]]},
        {"MinMaxIs", [[min: 1, max: 3, is: 2]]},
        {"MaxMinIs", [[max: 3, min: 1, is: 2]]},
        {"ConflictingMin", [[is: 2, min: 3, max: 4]]},
        {"ConflictingMax", [[min: 0, max: 1, is: 2]]},
        {"RangeThenExact", [[min: 1, max: 3], [is: 2]]},
        {"ExactThenRange", [[is: 2], [min: 1, max: 3]]},
        {"ConflictingCalls", [[is: 2], [min: 3]]}
      ] do
    defmodule Module.concat(__MODULE__, name) do
      use Ecto.Schema
      import Ecto.Changeset
      @primary_key false
      @length_validations validations
      embedded_schema do
        field(:text, :string)
        field(:items, {:array, :string})
      end

      def changeset(s, a) do
        changeset = s |> cast(a, [:text, :items]) |> validate_required([:text, :items])

        Enum.reduce(@length_validations, changeset, fn options, acc ->
          acc
          |> validate_length(:text, options ++ [count: :codepoints])
          |> validate_length(:items, options)
        end)
      end
    end
  end

  test "inclusion preserves native JSON types and existing atom enums" do
    schema = OutputSchema.json_schema(Inclusion)
    assert schema.properties["number"] == %{type: "integer", enum: [1, 2]}
    assert schema.properties["fraction"] == %{type: "number", enum: [0.5, 1.5]}
    assert schema.properties["flag"] == %{type: "boolean", enum: [true]}
    assert schema.properties["status"] == %{type: "string", enum: ["ready"]}
    data = %{"number" => 1, "fraction" => 0.5, "flag" => true, "status" => "ready"}
    assert_agreement(Inclusion, data, true)

    for {field, invalid} <- [
          {"number", 3},
          {"fraction", 2.5},
          {"flag", false},
          {"status", "waiting"}
        ] do
      assert_agreement(Inclusion, Map.put(data, field, invalid), false)
    end
  end

  test "exclusion rejects numeric, boolean and atom enum values in both contracts" do
    schema = OutputSchema.json_schema(Exclusion)
    assert schema.properties["number"].not == %{enum: [1, 2]}
    assert schema.properties["flag"].not == %{enum: [false]}
    assert schema.properties["status"].not == %{enum: ["waiting"]}
    data = %{"number" => 3, "flag" => true, "status" => "ready"}
    assert_agreement(Exclusion, data, true)

    for {field, invalid} <- [{"number", 1}, {"flag", false}, {"status", "waiting"}] do
      assert_agreement(Exclusion, Map.put(data, field, invalid), false)
    end
  end

  test "min max and exact lengths use array items and string codepoints" do
    schema = OutputSchema.json_schema(Length)

    assert schema.properties == %{
             "text" => %{type: "string", minLength: 2, maxLength: 3},
             "code" => %{type: "string", minLength: 2, maxLength: 2},
             "items" => %{type: "array", items: %{type: "string"}, minItems: 2, maxItems: 3},
             "pair" => %{type: "array", items: %{type: "string"}, minItems: 2, maxItems: 2}
           }

    data = %{"text" => "ab", "code" => "e\u0301", "items" => ["a", "b"], "pair" => ["x", "y"]}
    assert_agreement(Length, data, true)

    for {field, invalid} <- [
          {"text", "a"},
          {"text", "abcd"},
          {"code", "abc"},
          {"items", ["a"]},
          {"items", ["a", "b", "c", "d"]},
          {"pair", ["x", "y", "z"]}
        ] do
      assert_agreement(Length, Map.put(data, field, invalid), false)
    end
  end

  test "Ecto grapheme and byte counts remain authoritative beyond JSON's codepoint projection" do
    # JSON Schema has no grapheme/byte-length keyword. Keep that documented
    # approximation visible rather than pretending every count mode is exact.
    for attrs <- [%{"graphemes" => "e\u0301"}, %{"bytes" => "é"}] do
      assert {:ok, _} = OutputSchema.validate(CountModes, attrs)

      assert {:error, _} =
               Tool.validate_args(
                 Tool.new(parameters_json_schema: OutputSchema.json_schema(CountModes)),
                 attrs
               )
    end
  end

  test "boolean-named Ecto.Enum inclusion uses strings while primitive boolean stays boolean" do
    schema = OutputSchema.json_schema(BooleanEnumInclusion)

    assert schema.properties == %{
             "status" => %{type: "string", enum: ["true"]},
             "flag" => %{type: "boolean", enum: [true]}
           }

    data = %{"status" => "true", "flag" => true}
    assert_agreement(BooleanEnumInclusion, data, true)
    assert {:ok, %{status: true, flag: true}} = OutputSchema.validate(BooleanEnumInclusion, data)

    for {field, invalid} <- [{"status", "false"}, {"status", "pending"}, {"flag", false}] do
      assert_agreement(BooleanEnumInclusion, Map.put(data, field, invalid), false)
    end
  end

  test "boolean-named Ecto.Enum exclusion rejects its string without weakening native booleans" do
    schema = OutputSchema.json_schema(BooleanEnumExclusion)

    assert schema.properties == %{
             "status" => %{
               type: "string",
               enum: ["true", "false", "pending"],
               not: %{enum: ["false"]}
             },
             "flag" => %{type: "boolean", not: %{enum: [false]}}
           }

    for status <- ["true", "pending"] do
      assert_agreement(BooleanEnumExclusion, %{"status" => status, "flag" => true}, true)
    end

    assert_agreement(BooleanEnumExclusion, %{"status" => "false", "flag" => true}, false)
    assert_agreement(BooleanEnumExclusion, %{"status" => "pending", "flag" => false}, false)
  end

  test "integer and custom string enum mappings advertise castable typed values" do
    schema = OutputSchema.json_schema(MappedEnums)

    assert schema.properties == %{
             "numeric" => %{type: "integer", enum: [0, 1]},
             "named" => %{type: "string", enum: ["P", "D"]}
           }

    for numeric <- [0, 1], named <- ["P", "D"] do
      assert_agreement(MappedEnums, %{"numeric" => numeric, "named" => named}, true)
    end

    for numeric <- ["0", "1", "unknown"] do
      assert_agreement(MappedEnums, %{"numeric" => numeric, "named" => "D"}, false)
    end

    assert {:ok, %MappedEnums{numeric: :done, named: :done}} =
             OutputSchema.validate(MappedEnums, %{"numeric" => 1, "named" => "D"})

    # Changeset casting still accepts member names directly, even though
    # the model's advertised vocabulary uses the unambiguous storage values.
    assert {:ok, %MappedEnums{numeric: :done, named: :done}} =
             OutputSchema.validate(MappedEnums, %{"numeric" => "done", "named" => "done"})
  end

  test "mapped enum inclusion and exclusion use the same typed vocabulary" do
    schema = OutputSchema.json_schema(MappedEnumConstraints)

    assert schema.properties["numeric_inclusion"] == %{type: "integer", enum: [1]}
    assert schema.properties["named_inclusion"] == %{type: "string", enum: ["D"]}

    assert schema.properties["numeric_exclusion"] == %{
             type: "integer",
             enum: [0, 1],
             not: %{enum: [0]}
           }

    assert schema.properties["named_exclusion"] == %{
             type: "string",
             enum: ["P", "D"],
             not: %{enum: ["P"]}
           }

    data = %{
      "numeric_inclusion" => 1,
      "numeric_exclusion" => 1,
      "named_inclusion" => "D",
      "named_exclusion" => "D"
    }

    assert_agreement(MappedEnumConstraints, data, true)

    for {field, invalid} <- [
          {"numeric_inclusion", 0},
          {"numeric_exclusion", 0},
          {"named_inclusion", "P"},
          {"named_exclusion", "P"}
        ] do
      assert_agreement(MappedEnumConstraints, Map.put(data, field, invalid), false)
    end
  end

  test "crossed string mappings retain unambiguous outputs and constraints" do
    schema = OutputSchema.json_schema(CrossedStringEnum)
    assert schema.properties["status"] == %{type: "string", enum: ["bar", "baz"]}
    assert schema.properties["included"] == %{type: "string", enum: ["baz"]}

    assert schema.properties["excluded"] == %{
             type: "string",
             enum: ["bar", "baz"],
             not: %{enum: ["bar"]}
           }

    for {value, expected} <- [{"bar", :foo}, {"baz", :bar}] do
      data = %{"status" => value, "included" => "baz", "excluded" => "baz"}
      assert_agreement(CrossedStringEnum, data, true)

      assert {:ok, %{status: ^expected, included: :bar, excluded: :bar}} =
               OutputSchema.validate(CrossedStringEnum, data)
    end

    for field <- ["included", "excluded"] do
      data = Map.put(%{"status" => "baz", "included" => "baz", "excluded" => "baz"}, field, "bar")
      assert_agreement(CrossedStringEnum, data, false)
    end
  end

  test "all orderings of is min max preserve exact string and array acceptance" do
    for name <- ["IsMinMax", "IsMaxMin", "MinIsMax", "MaxIsMin", "MinMaxIs", "MaxMinIs"] do
      module = Module.concat(__MODULE__, name)

      assert OutputSchema.json_schema(module).properties == %{
               "text" => %{type: "string", minLength: 2, maxLength: 2},
               "items" => %{type: "array", items: %{type: "string"}, minItems: 2, maxItems: 2}
             }

      data = %{"text" => "e\u0301", "items" => ["a", "b"]}
      assert_agreement(module, data, true)

      for {field, invalid} <- [
            {"text", "a"},
            {"text", "abc"},
            {"items", ["a"]},
            {"items", ["a", "b", "c"]}
          ] do
        assert_agreement(module, Map.put(data, field, invalid), false)
      end
    end
  end

  test "matching is still enforces contradictory min or max just as Ecto does" do
    for {name, minimum, maximum, ecto_kind} <- [
          {"ConflictingMin", 3, 2, :min},
          {"ConflictingMax", 2, 1, :max},
          {"ConflictingCalls", 3, 2, :min}
        ] do
      module = Module.concat(__MODULE__, name)

      assert OutputSchema.json_schema(module).properties == %{
               "text" => %{type: "string", minLength: minimum, maxLength: maximum},
               "items" => %{
                 type: "array",
                 items: %{type: "string"},
                 minItems: minimum,
                 maxItems: maximum
               }
             }

      # At length two Ecto passes :is, then reports the incompatible bound.
      changeset = module.changeset(struct(module), %{"text" => "ab", "items" => ["a", "b"]})

      assert Enum.map(changeset.errors, fn {field, {_message, opts}} -> {field, opts[:kind]} end)
             |> Enum.sort() == [{:items, ecto_kind}, {:text, ecto_kind}]

      for size <- 1..4 do
        assert_agreement(
          module,
          %{"text" => String.duplicate("x", size), "items" => List.duplicate("x", size)},
          false
        )
      end
    end
  end

  test "chained length validations intersect in either call order for strings and arrays" do
    for name <- ["RangeThenExact", "ExactThenRange"] do
      module = Module.concat(__MODULE__, name)

      assert OutputSchema.json_schema(module).properties == %{
               "text" => %{type: "string", minLength: 2, maxLength: 2},
               "items" => %{type: "array", items: %{type: "string"}, minItems: 2, maxItems: 2}
             }

      data = %{"text" => "ab", "items" => ["a", "b"]}
      assert_agreement(module, data, true)

      for {field, invalid} <- [
            {"text", "a"},
            {"text", "abc"},
            {"items", ["a"]},
            {"items", ["a", "b", "c"]}
          ] do
        assert_agreement(module, Map.put(data, field, invalid), false)
      end
    end
  end

  defp assert_agreement(module, attrs, accepted?) do
    tool = Tool.new(parameters_json_schema: OutputSchema.json_schema(module))
    # Tool's JSV boundary includes the existing codepoint vocabulary correction;
    # neither expected acceptance nor field constraints come from that validator.
    assert match?({:ok, _}, OutputSchema.validate(module, attrs)) == accepted?
    assert match?({:ok, _}, Tool.validate_args(tool, attrs)) == accepted?
  end
end
