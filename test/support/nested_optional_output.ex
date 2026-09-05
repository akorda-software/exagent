defmodule ExAgent.Test.NestedOptionalOutput do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_one(:detail, ExAgent.Test.OptionalOutput)
    embeds_many(:items, ExAgent.Test.OptionalOutput)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:detail, required: true)
    |> cast_embed(:items, required: true)
  end
end
