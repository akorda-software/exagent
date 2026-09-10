defmodule ExAgent.ToolValidationTest do
  use ExUnit.Case, async: true

  alias ExAgent.Tool

  defmodule ExecutableSchema do
    def json_schema do
      Process.put(:schema_executions, Process.get(:schema_executions, 0) + 1)
      %{"type" => "object"}
    end

    def __jsv__(_request, builder) do
      Process.put(:schema_executions, Process.get(:schema_executions, 0) + 1)
      {:nocast, builder}
    end
  end

  defp tool(schema) do
    Tool.new(
      name: "record",
      parameters_json_schema: schema,
      takes_ctx: false,
      call: fn args ->
        Process.put(:tool_effects, Process.get(:tool_effects, 0) + 1)
        {:ok, args}
      end
    )
  end

  defp invoke(tool, args) do
    with {:ok, original} <- Tool.validate_args(tool, args), do: tool.call.(original)
  end

  defp object do
    %{
      type: "object",
      properties: %{count: %{type: "integer", minimum: 1}},
      required: ["count"],
      additionalProperties: false
    }
  end

  test "type, required, minimum and extra-property errors prevent every callable effect" do
    tool = tool(object())

    for args <- [%{count: "bad"}, %{}, %{count: 0}, %{count: 2, extra: true}] do
      assert {:error, [_ | _] = errors} = invoke(tool, args)
      assert Process.get(:tool_effects, 0) == 0
      assert {:ok, _} = Jason.encode(errors)

      assert Enum.all?(
               errors,
               &match?(
                 %{path: p, keyword: k, message: m}
                 when is_binary(p) and is_binary(k) and is_binary(m),
                 &1
               )
             )
    end

    assert {:ok, %{count: 2}} = invoke(tool, %{count: 2})
    assert Process.get(:tool_effects) == 1
  end

  test "prepared validator is reused, excluded from definitions and invalidated by schema edits" do
    assert {:ok, prepared} = Tool.prepare(tool(object()))
    assert {:ok, ^prepared} = Tool.prepare(prepared)
    assert Tool.definition(prepared) == Tool.definition(tool(object()))
    assert {:ok, %{"count" => 2}} = Tool.validate_args(prepared, %{"count" => 2})

    changed = %{
      prepared
      | parameters_json_schema: %{type: "object", properties: %{count: %{type: "string"}}}
    }

    assert {:error, _} = Tool.validate_args(changed, %{count: 2})
    assert {:ok, %{count: "now a string"}} = Tool.validate_args(changed, %{count: "now a string"})
  end

  test "values and original atom/string keys survive nested validation without defaults or casts" do
    schema = %{
      type: "object",
      properties: %{
        nested: %{type: "object", properties: %{n: %{type: "integer"}}},
        omitted: %{type: "string", default: "not inserted"}
      }
    }

    args = %{nested: %{"n" => 2.0}}
    assert {:ok, original} = invoke(tool(schema), args)
    assert original === args
    assert {:error, _} = invoke(tool(schema), %{nested: %{n: "2"}})
    assert Process.get(:tool_effects) == 1
  end

  test "local refs, nested arrays and escaped error paths" do
    schema = %{
      "$defs" => %{"positive" => %{"type" => "integer", "minimum" => 1}},
      "type" => "object",
      "properties" => %{
        "a/b~" => %{"type" => "array", "items" => %{"$ref" => "#/$defs/positive"}}
      }
    }

    assert {:ok, _} = Tool.validate_args(tool(schema), %{"a/b~" => [1, 2]})
    assert {:error, errors} = Tool.validate_args(tool(schema), %{"a/b~" => [1, "bad"]})
    assert Enum.any?(errors, &(&1.path == "/a~1b~0/1"))
  end

  test "nested resources and recursive local refs are supported" do
    schema = %{
      "$id" => "https://example.test/tree",
      "$defs" => %{
        "node" => %{
          "$id" => "node",
          "type" => "object",
          "properties" => %{"child" => %{"$ref" => "#"}, "value" => %{"type" => "integer"}}
        }
      },
      "$ref" => "node"
    }

    assert {:ok, _} = Tool.validate_args(tool(schema), %{value: 1, child: %{value: 2}})
    assert {:error, _} = Tool.validate_args(tool(schema), %{value: 1, child: %{value: "bad"}})
  end

  test "draft 7, boolean schemas and unconstrained additional properties" do
    draft7 = Map.put(object(), "$schema", "http://json-schema.org/draft-07/schema#")
    assert {:ok, _} = Tool.validate_args(tool(draft7), %{count: 1})
    assert {:ok, %{extra: true}} = Tool.validate_args(tool(true), %{extra: true})
    assert {:error, _} = Tool.validate_args(tool(false), %{})
    assert {:ok, %{extra: true}} = Tool.validate_args(tool(%{}), %{extra: true})
  end

  test "invalid schemas fail preparation and cannot execute a callable" do
    for schema <- [
          nil,
          [],
          %{type: "not-a-type"},
          %{required: "count"},
          %{minimum: "one"},
          %{required: ["a", "a"]},
          %{properties: %{child: 42}}
        ] do
      assert {:error, {:invalid_tool_schema, [_ | _]}} = Tool.prepare(tool(schema))
      assert {:error, [_ | _]} = invoke(tool(schema), %{})
      assert Process.get(:tool_effects, 0) == 0
    end
  end

  test "unresolved network, file and unknown dialect references reject" do
    for schema <- [
          %{"$ref" => "https://127.0.0.1:1/schema"},
          %{"$ref" => "file:///tmp/exagent-schema.json"},
          %{"$schema" => "https://example.test/custom-dialect"}
        ] do
      assert {:error, {:invalid_tool_schema, [_ | _]}} = Tool.prepare(tool(schema))
    end
  end

  test "non-JSON arguments and ambiguous keys never reach the callable" do
    for args <- [
          %{count: :value},
          %{count: self()},
          %{count: make_ref()},
          %{count: fn -> :ok end},
          %{count: {1, 2}},
          %{count: ~D[2026-09-09]},
          %{count: <<255>>},
          %{count: [1 | 2]},
          %{1 => "bad key"},
          %{"count" => 1, count: 2},
          %{nested: %{"x" => 1, x: 2}},
          [],
          "{}",
          ~D[2026-09-09]
        ] do
      assert {:error, [_ | _]} = invoke(tool(%{}), args)
      assert Process.get(:tool_effects, 0) == 0
    end
  end

  test "schema normalization rejects key collisions and non-JSON terms" do
    for schema <- [
          %{"type" => "object", type: "string"},
          %{default: self()},
          %{properties: %{x: fn -> :ok end}}
        ] do
      assert {:error, {:invalid_tool_schema, [_ | _]}} = Tool.prepare(tool(schema))
    end
  end

  test "both cast keywords are blocked before their build-time callback" do
    module = Atom.to_string(ExecutableSchema)

    for key <- ["x-jsv-cast", "jsv-cast"],
        schema <- [
          %{key => [module, "tag"], "type" => "object"},
          %{"properties" => %{"nested" => %{key => [module, "tag"]}}},
          %{"$defs" => %{"hidden" => %{key => [module, "tag"]}}}
        ] do
      assert {:error, {:invalid_tool_schema, [error]}} = Tool.prepare(tool(schema))
      assert error.message =~ "Executable schema casts"
      assert Process.get(:schema_executions, 0) == 0
    end
  end

  test "module references and module dialects never call json_schema" do
    ref = "jsv:module:" <> Atom.to_string(ExecutableSchema)

    for key <- ["$ref", "$dynamicRef", "$schema", "$id"],
        schema <- [%{key => ref}, %{"properties" => %{"x" => %{key => ref}}}] do
      assert {:error, {:invalid_tool_schema, [error]}} = Tool.prepare(tool(schema))
      assert error.message =~ "Module schema references"
      assert Process.get(:schema_executions, 0) == 0
    end
  end

  test "literal data and property names may contain executable-looking keywords" do
    data = %{
      "x-jsv-cast" => [Atom.to_string(ExecutableSchema)],
      "$ref" => "jsv:module:" <> Atom.to_string(ExecutableSchema)
    }

    for keyword <- ["const", "enum", "default", "examples"] do
      value = if keyword in ["enum", "examples"], do: [data], else: data
      assert {:ok, prepared} = Tool.prepare(tool(%{keyword => value}))
      assert {:ok, ^data} = Tool.validate_args(prepared, data)
      assert Process.get(:schema_executions, 0) == 0
    end

    schema = %{
      "properties" => %{"x-jsv-cast" => %{"type" => "string"}, "$ref" => %{"type" => "string"}}
    }

    assert {:ok, _} =
             Tool.validate_args(tool(schema), %{"x-jsv-cast" => "safe", "$ref" => "safe"})
  end

  test "references into literal data cannot smuggle executable schemas" do
    cast = %{"x-jsv-cast" => [Atom.to_string(ExecutableSchema)]}
    module = %{"$ref" => "jsv:module:" <> Atom.to_string(ExecutableSchema)}

    for literal <- [cast, module], keyword <- ["const", "default"] do
      schema = %{keyword => literal, "$ref" => "#/" <> keyword}
      assert {:error, {:invalid_tool_schema, [_ | _]}} = Tool.prepare(tool(schema))
      assert Process.get(:schema_executions, 0) == 0
    end

    schema = %{"default" => %{"type" => "object"}, "$ref" => "#/default"}
    assert {:ok, _} = Tool.validate_args(tool(schema), %{})
  end

  test "encoded pointer keys and anchors cannot bypass the executable-schema boundary" do
    cast = %{"x-jsv-cast" => [Atom.to_string(ExecutableSchema)]}

    for ref <- ["#/default/a%2Fb", "#/default/a~1b"] do
      schema = %{"default" => %{"a/b" => cast}, "$ref" => ref}
      assert {:error, {:invalid_tool_schema, [_ | _]}} = Tool.prepare(tool(schema))
      assert Process.get(:schema_executions, 0) == 0
    end

    schema = %{"default" => Map.put(cast, "$dynamicAnchor", "hidden"), "$dynamicRef" => "#hidden"}
    assert {:error, {:invalid_tool_schema, [_ | _]}} = Tool.prepare(tool(schema))
    assert Process.get(:schema_executions, 0) == 0
  end

  test "JSON-encodable results preserve valid structs and atoms but reject failed encodings" do
    for result <- [nil, true, 2, 2.5, "ok", :ok, %{key: [:ok, nil]}, ~D[2026-09-09]] do
      assert {:ok, original} = Tool.validate_result(tool(%{}), result)
      assert original === result
    end

    for result <- [
          self(),
          make_ref(),
          fn -> :ok end,
          {:ok, 1},
          %{nested: self()},
          <<255>>,
          %{"key" => 1, key: 2},
          %{nested: %{"key" => 1, key: 2}}
        ] do
      assert {:error, [%{keyword: "json"}]} = Tool.validate_result(tool(%{}), result)
    end
  end

  test "uniqueItems compares JSON numbers recursively without changing arguments" do
    for draft <- [
          "https://json-schema.org/draft/2020-12/schema",
          "http://json-schema.org/draft-07/schema#"
        ] do
      schema = %{
        "$schema" => draft,
        "properties" => %{"xs" => %{"type" => "array", "uniqueItems" => true}}
      }

      for values <- [[1, 1.0], [%{n: 1}, %{"n" => 1.0}], [[1], [1.0]], [0, -0.0]] do
        assert {:error, errors} = invoke(tool(schema), %{xs: values})
        assert Enum.any?(errors, &(&1.keyword == "uniqueItems"))
      end

      assert Process.get(:tool_effects, 0) == 0
    end

    args = %{
      xs: [1, 1.5, true, "1", %{n: 2}, %{n: 3}, 9_007_199_254_740_993, 9_007_199_254_740_992.0]
    }

    assert {:ok, original} = invoke(tool(%{properties: %{xs: %{uniqueItems: true}}}), args)
    assert original === args
  end

  test "string lengths count Unicode codepoints in both dialects and compositions" do
    for draft <- [
          "https://json-schema.org/draft/2020-12/schema",
          "http://json-schema.org/draft-07/schema#"
        ] do
      mk = fn constraint ->
        tool(%{"$schema" => draft, "properties" => %{"s" => %{"allOf" => [constraint]}}})
      end

      assert {:error, errors} = invoke(mk.(%{"maxLength" => 1}), %{s: "e\u0301"})
      assert Enum.any?(errors, &(&1.keyword == "maxLength" and &1.path == "/s"))
      assert {:ok, %{s: "e\u0301"}} = invoke(mk.(%{"minLength" => 2}), %{s: "e\u0301"})
      assert {:ok, %{s: "😀"}} = invoke(mk.(%{"maxLength" => 1}), %{s: "😀"})
    end
  end

  test "nested dialects must agree with the root even when reached through literals" do
    for draft <- ["https://example.test/custom", "http://json-schema.org/draft-07/schema"],
        schema <- [
          %{
            "$defs" => %{"child" => %{"$id" => "https://example.test/child", "$schema" => draft}}
          },
          %{"default" => %{"$schema" => draft}, "$ref" => "#/default"}
        ] do
      assert {:error, {:invalid_tool_schema, errors}} = Tool.prepare(tool(schema))
      assert Enum.any?(errors, &(&1.keyword == "$schema"))
    end

    assert {:ok, _} =
             Tool.prepare(
               tool(%{
                 "properties" => %{
                   "x" => %{
                     "$schema" => "https://json-schema.org/draft/2020-12/schema#",
                     "type" => "integer"
                   }
                 }
               })
             )

    assert {:ok, _} = Tool.prepare(tool(%{"const" => %{"$schema" => "literal-data"}}))
  end

  test "results reject invalid encoded JSON and duplicate keys even inside raw fragments" do
    for raw <- ["not-json", "{} {}", ~s({"key":1,"key":2}), ~s({"key":1,"\\u006bey":2})],
        result <- [Jason.Fragment.new(raw), %{nested: [Jason.Fragment.new(raw)]}] do
      assert {:error, [%{keyword: "json"}]} = Tool.validate_result(tool(%{}), result)
    end

    result = %{nested: Jason.Fragment.new(~s({"key":[1,true,null]})), date: ~D[2026-09-09]}
    assert {:ok, original} = Tool.validate_result(tool(%{}), result)
    assert original === result
  end

  test "pointer targets inherit the dialect restriction of hidden resource ancestors" do
    schema = %{
      "default" => %{
        "$id" => "https://example.test/hidden",
        "$schema" => "https://example.test/unsupported",
        "properties" => %{"n" => %{"type" => "integer"}}
      },
      "$ref" => "#/default/properties/n"
    }

    assert {:error, {:invalid_tool_schema, errors}} = Tool.prepare(tool(schema))
    assert Enum.any?(errors, &(&1.keyword == "$schema"))
  end

  test "encoder exceptions, throws and exits become owned JSON errors" do
    for encode <- [
          fn _ -> raise "bad encoder" end,
          fn _ -> throw(:failed) end,
          fn _ -> exit(:failed) end
        ] do
      assert {:error, [%{keyword: "json", path: ""}]} =
               Tool.validate_result(tool(%{}), Jason.Fragment.new(encode))
    end
  end

  test "inert defaults are literal JSON while referenced defaults retain their schemas" do
    schema = %{
      "type" => "object",
      "default" => %{"$id" => 42},
      "properties" => %{
        "x" => %{"default" => %{"$anchor" => false}, "type" => "integer"}
      }
    }

    assert {:ok, prepared} = Tool.prepare(tool(schema))
    assert Tool.definition(prepared).parameters == schema
    assert {:ok, %{}} = invoke(prepared, %{})
    assert {:error, _} = invoke(prepared, %{x: "bad"})

    assert {:error, _} =
             Tool.validate_args(
               tool(%{"default" => %{"type" => "integer"}, "$ref" => "#/default"}),
               %{}
             )
  end

  test "build projection preserves property names, shared literals and referenced defaults" do
    data = %{"default" => %{"$id" => 42}}
    assert {:ok, ^data} = Tool.validate_args(tool(%{"const" => data}), data)
    assert {:error, _} = Tool.validate_args(tool(%{"properties" => %{"default" => false}}), data)

    schema = %{"default" => %{"const" => data}, "$ref" => "#/default"}
    assert {:ok, ^data} = Tool.validate_args(tool(schema), data)
    assert {:error, _} = Tool.validate_args(tool(schema), %{"default" => %{}})

    schema = %{
      "default" => %{"schema" => %{"properties" => %{"n" => %{"type" => "integer"}}}},
      "$ref" => "#/default/schema"
    }

    assert {:ok, %{n: 1}} = Tool.validate_args(tool(schema), %{n: 1})
    assert {:error, _} = Tool.validate_args(tool(schema), %{n: "bad"})
  end

  test "JSV 0.22 callbacks are reachable without preflight but blocked for every literal reference" do
    module = Atom.to_string(ExecutableSchema)

    for unsafe <- [%{"x-jsv-cast" => [module]}, %{"$ref" => "jsv:module:" <> module}] do
      Process.put(:schema_executions, 0)
      assert {:ok, _} = JSV.build(unsafe, resolver: [], atoms: false)
      assert Process.get(:schema_executions) > 0
      Process.put(:schema_executions, 0)

      for keyword <- ["default", "const", "enum", "examples"] do
        array? = keyword in ["enum", "examples"]
        value = if array?, do: [unsafe], else: unsafe
        ref = "#/" <> keyword <> if(array?, do: "/0", else: "")

        assert {:error, {:invalid_tool_schema, _}} =
                 Tool.prepare(tool(%{keyword => value, "$ref" => ref}))

        assert Process.get(:schema_executions) == 0
      end
    end
  end
end
