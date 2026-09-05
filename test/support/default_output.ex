defmodule ExAgent.Test.DefaultOutput do
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:count, :integer)
  end
end
