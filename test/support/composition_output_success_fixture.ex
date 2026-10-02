defmodule ExAgent.CompositionOutputSuccessFixture.Output do
  use Ecto.Schema
  @primary_key false
  @derive {Jason.Encoder, only: [:count]}
  embedded_schema do
    field(:count, :integer)
  end

  def changeset(value, attrs) do
    if owner = Process.get(:output_success_observer), do: send(owner, {:changeset, attrs})

    value
    |> Ecto.Changeset.cast(attrs, [:count])
    |> Ecto.Changeset.validate_required([:count])
  end
end
