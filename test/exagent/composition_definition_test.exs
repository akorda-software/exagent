defmodule ExAgent.CompositionDefinitionTest do
  use ExUnit.Case, async: true

  alias ExAgent.Coordination.Composition
  alias ExAgent.Continuation.Record

  defp ref(id), do: %{id: id, version: "1"}

  defp step(id) do
    %{
      id: id,
      agent: ExAgent.new(model: %ExAgent.Models.Test{}),
      definition: ref(id),
      policy: ref("policy"),
      model_ref: ref("model"),
      output_ref: ref("output"),
      model_codec: %{
        dump: fn _ -> raise "dump called" end,
        load: fn _, _ -> raise "load called" end
      }
    }
  end

  defp options(steps \\ [step("a"), step("b")]),
    do: [id: "extract-review", version: "1", steps: steps]

  test "constructs a sequence and emits only an explicit bounded portable definition" do
    assert {:ok, definition} = Composition.new(options())
    assert {:ok, binding} = Composition.binding(definition)
    assert binding["composition_definition_version"] == 1
    assert binding["kind"] == "sequence"
    assert binding["id"] == "extract-review"
    assert Enum.map(binding["steps"], & &1["id"]) == ["a", "b"]
    assert Enum.map(binding["steps"], & &1["input_kind"]) == ["initial", "previous_output"]
    assert Jason.decode!(Jason.encode!(binding)) == binding
    assert {:ok, binding["fingerprint"]} == Record.digest(Map.delete(binding, "fingerprint"))
    assert :ok = Composition.validate_binding(definition, binding)
    refute Map.has_key?(binding, "model")
    refute Map.has_key?(hd(binding["steps"]), "agent")
    assert function_exported?(Composition, :run, 3)
    assert function_exported?(Composition, :resume, 2)
  end

  test "construction and binding validation never invoke trusted callbacks" do
    mapping = fn _, _ -> raise "mapping called" end
    mapped = Map.merge(step("b"), %{input: mapping, input_version: "mapping-v1"})
    assert {:ok, definition} = Composition.new(options([step("a"), mapped]))
    assert {:ok, binding} = Composition.binding(definition)
    assert List.last(binding["steps"])["input_kind"] == "host"
    assert List.last(binding["steps"])["input_version"] == "mapping-v1"
    assert :ok = Composition.validate_binding(definition, binding)
  end

  test "truncated definition structs reject without raising" do
    assert {:ok, definition} = Composition.new(options())
    assert {:ok, binding} = Composition.binding(definition)

    truncated =
      [%{__struct__: Composition}] ++
        Enum.map([:id, :version, :steps, :fingerprint], &Map.delete(definition, &1))

    for invalid <- truncated do
      assert {:error, :invalid_composition_definition} = Composition.binding(invalid)

      assert {:error, :invalid_composition_definition} =
               Composition.validate_binding(invalid, binding)
    end
  end

  test "canonical references ignore map key representation and insertion order" do
    a = step("a")
    b = %{a | policy: %{"version" => "1", "id" => "policy"}}
    assert {:ok, first} = Composition.new(options([a]))
    assert {:ok, second} = Composition.new(options([b]))
    assert Composition.binding(first) == Composition.binding(second)
  end

  test "identity, order and every declared reference version bind the definition" do
    assert {:ok, original} = Composition.new(options())
    assert {:ok, binding} = Composition.binding(original)

    variants = [
      Keyword.put(options(), :id, "other"),
      Keyword.put(options(), :version, "2"),
      options([step("b"), step("a")])
    ]

    variants =
      variants ++
        for key <- [:definition, :policy, :model_ref, :output_ref] do
          options([Map.update!(step("a"), key, &Map.put(&1, :version, "2")), step("b")])
        end

    for opts <- variants do
      assert {:ok, changed} = Composition.new(opts)

      assert {:error, :composition_definition_changed} =
               Composition.validate_binding(changed, binding)
    end
  end

  test "mapping version changes fingerprint; callbacks themselves are not serialized or hashed" do
    first = Map.merge(step("a"), %{input: fn _, _ -> :first end, input_version: "1"})
    second = %{first | input: fn _, _ -> :second end}
    assert {:ok, a} = Composition.new(options([first]))
    assert {:ok, b} = Composition.new(options([second]))
    assert Composition.binding(a) == Composition.binding(b)
    assert {:ok, c} = Composition.new(options([%{second | input_version: "2"}]))
    assert {:ok, binding} = Composition.binding(a)
    assert {:error, :composition_definition_changed} = Composition.validate_binding(c, binding)
  end

  test "rejects invalid, ambiguous and unsupported top-level configuration" do
    for opts <- [
          nil,
          %{},
          [{:id, "x"} | :improper],
          [id: "x", id: "y", version: "1", steps: [step("a")]],
          Keyword.put(options(), :id, ""),
          Keyword.put(options(), :id, <<255>>),
          Keyword.put(options(), :version, 1),
          Keyword.put(options(), :kind, :router),
          Keyword.put(options(), :kind, :parallel),
          Keyword.put(options(), :failure_policy, :collect),
          Keyword.put(options(), :unknown, true),
          options([]),
          options([step("a"), step("a")]),
          options([nil]),
          options([step("a") | :improper])
        ] do
      assert {:error, :invalid_composition_definition} = Composition.new(opts)
    end
  end

  test "rejects malformed steps, refs, codec and unversioned mapping without callbacks" do
    a = step("a")

    for invalid <- [
          Map.delete(a, :output_ref),
          Map.put(a, :agent, fn -> a.agent end),
          Map.put(a, :policy, %{id: "p", version: "1", authority: :allow}),
          Map.put(a, :policy, %{:id => "p", "id" => "q", :version => "1"}),
          Map.put(a, :model_codec, %{dump: fn _ -> nil end}),
          Map.put(a, :model_codec, %{dump: fn -> nil end, load: fn _, _ -> nil end}),
          Map.put(a, :input, fn _, _ -> nil end),
          Map.put(a, :input_version, "1"),
          Map.merge(a, %{input: fn _ -> nil end, input_version: "1"}),
          Map.put(a, :deps, self()),
          Map.put(a, "id", "other")
        ] do
      assert {:error, :invalid_composition_definition} = Composition.new(options([invalid]))
    end
  end

  test "identifier boundary is 512 UTF-8 bytes, not characters" do
    assert {:ok, _} = Composition.new(Keyword.put(options(), :id, String.duplicate("é", 256)))

    assert {:error, :invalid_composition_definition} =
             Composition.new(Keyword.put(options(), :id, String.duplicate("é", 256) <> "x"))
  end

  test "step cardinality and encoded binding bytes are independently bounded" do
    assert {:error, :invalid_composition_definition} =
             Composition.new(options(for n <- 1..256, do: step(Integer.to_string(n))))

    large =
      for n <- 1..100, do: %{step(Integer.to_string(n)) | policy: ref(String.duplicate("x", 512))}

    assert {:error, :composition_definition_too_large} = Composition.new(options(large))
  end

  test "full encoded binding accepts exactly 65536 bytes and rejects one additional byte" do
    steps = for n <- 1..128, do: %{step(Integer.to_string(n)) | policy: ref("x")}
    assert {:ok, base} = Composition.new(options(steps))
    assert {:ok, binding} = Composition.binding(base)
    gap = 65_536 - byte_size(Jason.encode!(binding))
    assert gap > 0

    {padded, 0} =
      Enum.map_reduce(steps, gap, fn step, remaining ->
        extra = min(remaining, 511)
        {%{step | policy: ref(String.duplicate("x", 1 + extra))}, remaining - extra}
      end)

    assert {:ok, exact} = Composition.new(options(padded))
    assert {:ok, exact_binding} = Composition.binding(exact)
    assert byte_size(Jason.encode!(exact_binding)) == 65_536
    assert :ok = Composition.validate_binding(exact, exact_binding)

    over = List.update_at(padded, -1, &%{&1 | policy: ref("xx")})
    assert {:error, :composition_definition_too_large} = Composition.new(options(over))
  end

  test "255 minimal steps are accepted independently of the encoded size limit" do
    steps =
      for n <- 1..255 do
        Enum.reduce(
          [:definition, :policy, :model_ref, :output_ref],
          step(Integer.to_string(n)),
          fn key, acc ->
            Map.put(acc, key, ref("x"))
          end
        )
      end

    assert {:ok, definition} = Composition.new(options(steps))
    assert {:ok, binding} = Composition.binding(definition)
    assert length(binding["steps"]) == 255
  end

  test "unknown versions, extra fields, corrupted hash and malformed bindings reject" do
    assert {:ok, definition} = Composition.new(options())
    assert {:ok, binding} = Composition.binding(definition)

    for bad <- [
          nil,
          %{},
          Map.put(binding, "composition_definition_version", 2),
          Map.put(binding, "kind", "router"),
          Map.put(binding, "authority", "allow"),
          Map.put(binding, "fingerprint", String.duplicate("0", 64)),
          Map.put(binding, "steps", []),
          Map.put(binding, "steps", [hd(binding["steps"]) | :improper]),
          put_in(binding, ["steps", Access.at(0), "input_kind"], "previous_output"),
          put_in(binding, ["steps", Access.at(0), "agent"], "Elixir.Untrusted")
        ] do
      assert {:error, :invalid_composition_binding} =
               Composition.validate_binding(definition, bad)
    end
  end

  test "even rehashed malformed bindings cannot become definitions or authority" do
    assert {:ok, definition} = Composition.new(options())
    assert {:ok, binding} = Composition.binding(definition)
    bad = put_in(binding, ["steps", Access.at(0), "policy"], %{"id" => "p"})
    assert {:ok, hash} = Record.digest(Map.delete(bad, "fingerprint"))

    assert {:error, :invalid_composition_binding} =
             Composition.validate_binding(definition, Map.put(bad, "fingerprint", hash))

    assert {:error, :invalid_composition_definition} = Composition.binding(binding)

    assert {:error, :invalid_composition_definition} =
             Composition.binding(%{definition | id: "tampered"})
  end

  test "semantic corruption rejects even with a recomputed digest" do
    assert {:ok, definition} = Composition.new(options())
    assert {:ok, binding} = Composition.binding(definition)

    for bad <- [
          Map.put(binding, "composition_definition_version", 1.0),
          Map.put(binding, "steps", [hd(binding["steps"]), hd(binding["steps"])]),
          put_in(binding, ["steps", Access.at(0), "input_kind"], "previous_output"),
          put_in(binding, ["steps", Access.at(1), "input_kind"], "initial"),
          put_in(binding, ["steps", Access.at(0), "input_kind"], "host"),
          put_in(binding, ["steps", Access.at(0), "input_version"], "unattached-version"),
          put_in(binding, ["steps", Access.at(0), "model_ref", "module"], "Untrusted")
        ] do
      assert {:ok, hash} = Record.digest(Map.delete(bad, "fingerprint"))
      hashed = Map.put(bad, "fingerprint", hash)

      assert {:error, :invalid_composition_binding} =
               Composition.validate_binding(definition, hashed)
    end
  end

  test "a correctly hashed changed reference is data, not permission to replace host configuration" do
    assert {:ok, definition} = Composition.new(options())
    assert {:ok, binding} = Composition.binding(definition)
    changed = put_in(binding, ["steps", Access.at(0), "policy", "version"], "2")
    assert {:ok, hash} = Record.digest(Map.delete(changed, "fingerprint"))

    assert {:error, :composition_definition_changed} =
             Composition.validate_binding(definition, Map.put(changed, "fingerprint", hash))
  end
end
