defmodule ExAgent.CompositionOutputRetryFixture.Output do
  use Ecto.Schema
  @primary_key false
  @derive {Jason.Encoder, only: [:count]}
  embedded_schema do
    field(:count, :integer)
  end

  def changeset(value, attrs) do
    if owner = Process.get(:output_retry_observer) do
      send(owner, {:changeset, attrs})

      if attrs == %{},
        do: send(owner, {:schema_monitors, elem(Process.info(self(), :monitored_by), 1)})
    end

    case {Process.get(:output_retry_trap), attrs} do
      {:historical, %{"count" => "invalid"}} -> raise "historical args revalidated"
      {:empty, attrs} when map_size(attrs) == 0 -> raise "reflection failed"
      {:new, %{"count" => 9}} -> raise "new args validation"
      _ -> :ok
    end

    value
    |> Ecto.Changeset.cast(attrs, [:count])
    |> Ecto.Changeset.validate_required([:count])
  end
end

defmodule ExAgent.CompositionOutputRetryFixture.LargeOutput do
  use Ecto.Schema
  @primary_key false
  @derive {Jason.Encoder, only: [:count, :value]}
  embedded_schema do
    field(:count, :integer)
    field(:value, :string)
  end

  def changeset(value, attrs),
    do:
      value
      |> Ecto.Changeset.cast(attrs, [:count, :value])
      |> Ecto.Changeset.validate_required([:count])
end

defmodule ExAgent.CompositionOutputRetryFixture.Model do
  @behaviour ExAgent.Model
  defstruct [:observer, binding: %{"version" => "1"}, invalid: false, script: [], index: 0]
  def model_name(_), do: "test"
  def system(_), do: "test"
  def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}
  def continuation_binding(model), do: {:ok, model.binding}

  def validate_resume(model, _, _, _) do
    if model.observer, do: send(model.observer, :validate_resume)
    if model.invalid, do: {:error, :model_resume_rejected}, else: :ok
  end

  def request(model, messages, settings, params) do
    {:ok, response, next} =
      ExAgent.Models.Test.request(
        %ExAgent.Models.Test{script: model.script, index: model.index},
        messages,
        settings,
        params
      )

    {:ok, response, %{model | index: next.index}}
  end
end
