defmodule ExAgent.Test.OptionalOutput do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:note, :string)
    field(:status, Ecto.Enum, values: [:ready, :waiting])
    field(:score, :integer)
    field(:tags, {:array, :string})
    embeds_one(:detail, ExAgent.Test.ReceiptItem)
    embeds_many(:items, ExAgent.Test.ReceiptItem)
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:note, :status, :score, :tags])
    |> validate_inclusion(:note, ["short", "long"])
    |> validate_number(:score, greater_than_or_equal_to: 0)
    |> cast_embed(:detail)
    |> cast_embed(:items)
  end
end
