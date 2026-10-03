defmodule ExAgent.ContinuationBindingModel do
  @moduledoc false
  @behaviour ExAgent.Model
  defstruct [:binding, :observer, script: [], index: 0]
  def model_name(_), do: "test"
  def system(_), do: "test"
  def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}
  def validate_resume(_, _, _, _), do: :ok

  def continuation_binding(model) do
    if model.observer, do: send(model.observer, :binding_called)
    {:ok, model.binding}
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
