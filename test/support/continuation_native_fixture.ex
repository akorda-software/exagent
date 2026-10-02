defmodule ExAgent.ContinuationNativeFixture.CountOutput do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false
  @derive {Jason.Encoder, only: [:count]}
  embedded_schema do
    field(:count, :integer)
  end

  def changeset(data, args),
    do:
      data
      |> cast(args, [:count])
      |> validate_required([:count])
      |> validate_number(:count, greater_than: 0)
end
