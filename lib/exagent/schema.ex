defmodule ExAgent.Schema do
  @moduledoc """
  Convert Elixir type expressions (as written in `::` annotations / typespecs)
  into JSON Schema fragments — the foundation for `deftool` and structured
  output.

  This is deliberately a *subset*: it covers the common scalar/collection types
  a tool signature or output schema uses. Anything it can't resolve collapses to
  an unconstrained `%{}` ("any"), which is safe for the model and easy to spot.
  """

  @doc "Convert a single type AST node to a JSON Schema fragment."
  @spec from_type(Macro.t() | nil) :: map()
  # annotated form: `name :: type`
  def from_type({:"::", _, [_, type]}), do: from_type(type)

  # scalar zero-arity type calls: integer(), float(), ...
  def from_type({:integer, _, _}), do: %{type: "integer"}
  def from_type({:non_neg_integer, _, _}), do: %{type: "integer", minimum: 0}
  def from_type({:pos_integer, _, _}), do: %{type: "integer", minimum: 1}
  def from_type({:float, _, _}), do: %{type: "number"}
  def from_type({:number, _, _}), do: %{type: "number"}
  def from_type({:boolean, _, _}), do: %{type: "boolean"}
  def from_type({:atom, _, _}), do: %{type: "string"}
  def from_type({:binary, _, _}), do: %{type: "string"}
  def from_type({:string, _, _}), do: %{type: "string"}
  def from_type({:map, _, []}), do: %{type: "object"}
  def from_type({:any, _, _}), do: %{}

  # String.t() / Binary.t() → dot-call form on an alias
  def from_type({{:., _, [{:__aliases__, _, [:String]}, :t]}, _, _}), do: %{type: "string"}
  def from_type({{:., _, [{:__aliases__, _, [:Binary]}, :t]}, _, _}), do: %{type: "string"}

  # bare aliases used as type names: String, boolean, integer ...
  def from_type({:__aliases__, _, [:String]}), do: %{type: "string"}
  def from_type({:__aliases__, _, [:boolean]}), do: %{type: "boolean"}
  def from_type({:__aliases__, _, [:integer]}), do: %{type: "integer"}
  def from_type({:__aliases__, _, [:float]}), do: %{type: "number"}

  # list of one inner type → JSON array
  def from_type([inner]), do: %{type: "array", items: from_type(inner)}
  def from_type([]), do: %{type: "array"}

  # Literal unions retain enum ergonomics; type unions contain real schemas.
  def from_type({:|, _, [left, right]}) do
    parts = union_parts({:|, [], [left, right]})

    if Enum.all?(parts, &literal?/1) do
      values = Enum.map(parts, &to_enum_value/1)

      if Enum.all?(values, &is_binary/1),
        do: %{type: "string", enum: values},
        else: %{enum: values}
    else
      %{anyOf: Enum.map(parts, &union_schema/1)}
    end
  end

  # atom literal used as a type → its string form (loosely typed)
  def from_type(atom) when is_atom(atom) and not is_nil(atom), do: %{}

  def from_type(nil), do: %{}

  # anything else → unconstrained
  def from_type(_), do: %{}

  @doc """
  Build a JSON Schema `object` for a list of `{name, type_ast}` params.

  All params are marked `required` by default (tool signatures have no defaults
  in this iteration); the model is expected to supply every one.
  """
  @spec object_schema([{atom(), Macro.t() | nil}]) :: map()
  def object_schema(params) do
    properties =
      Map.new(params, fn {name, type} -> {Atom.to_string(name), from_type(type)} end)

    required = Enum.map(params, &Atom.to_string(elem(&1, 0)))
    %{type: "object", properties: properties, required: required}
  end

  defp union_parts({:|, _, [left, right]}), do: union_parts(left) ++ union_parts(right)
  defp union_parts(other), do: [other]

  defp literal?(value), do: is_atom(value) or is_binary(value) or is_number(value)

  defp union_schema(value) do
    if literal?(value), do: %{enum: [to_enum_value(value)]}, else: from_type(value)
  end

  defp to_enum_value(value) when is_boolean(value) or is_nil(value), do: value
  defp to_enum_value(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp to_enum_value(other), do: other
end
