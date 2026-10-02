defmodule OpikAcceptance.Profile do
  @moduledoc """
  Optional application projection of the stock exporter's public OTLP map.
  Opik buckets unrecognised attributes into input and omits resource attributes.
  Its documented opik.metadata prefix keeps native diagnostics and types in
  metadata, without capturing content or changing native IDs/names/status/times.
  """
  @model_keys ~w(gen_ai.operation.name gen_ai.provider.name gen_ai.request.model
                 gen_ai.usage.input_tokens gen_ai.usage.output_tokens)

  def project(%{resource_spans: resources} = request) do
    resources =
      for resource <- resources do
        scopes =
          for scope <- resource.scope_spans do
            spans =
              for span <- scope.spans do
                native = span.attributes
                # No stringification: AnyValue retains the original scalar type.
                diagnostic = Enum.map(native, &prefix(&1, "opik.metadata."))

                resource_metadata =
                  Enum.map(resource.resource.attributes, &prefix(&1, "opik.metadata.resource."))

                # Only inference spans project usage into Opik's native llm fields.
                # Tools remain general with execute_tool + exagent.operation in
                # metadata; no fake arguments/result are added to force a type.
                model =
                  Enum.any?(
                    native,
                    &(&1.key == "exagent.operation" and
                        &1.value == %{value: {:string_value, "model"}})
                  )

                semantic = if model, do: Enum.filter(native, &(&1.key in @model_keys)), else: []
                attributes = diagnostic ++ resource_metadata ++ semantic
                true = length(attributes) <= 64
                %{span | attributes: attributes}
              end

            %{scope | spans: spans}
          end

        %{resource | scope_spans: scopes}
      end

    %{request | resource_spans: resources}
  end

  defp prefix(value, prefix), do: %{value | key: prefix <> value.key}
end
