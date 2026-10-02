defmodule ExAgent.CompositionEvidenceFixture.LargeOutput do
  use Ecto.Schema
  @primary_key false
  @derive {Jason.Encoder, only: [:value]}
  embedded_schema do
    field(:value, :string)
  end
end
