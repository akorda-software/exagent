defmodule G2.InputBudget do
  use ExAgent.Capability
  @limit 16_384
  def measure(state) do
    messages = state.request_messages || state.messages

    tool = fn t ->
      %{
        name: t.name,
        description: t.description,
        parameters: %{
          type: "object",
          required: ["arguments"],
          additionalProperties: false,
          properties: %{arguments: t.parameters_json_schema}
        }
      }
    end

    projection = %{
      messages_json: ExAgent.Message.to_json(messages),
      instructions: Enum.map(state.params.instructions, & &1.content),
      function_tools: Enum.map(state.params.function_tools, tool),
      output_tools: Enum.map(state.params.output_tools, tool),
      native_schema: if(state.params.output_object, do: state.params.output_object.json_schema)
    }

    {byte_size(Jason.encode!(projection)), length(messages)}
  end

  def before_model_request(_, state) do
    {bytes, count} = measure(state)
    accepted = bytes <= @limit and count <= 10

    File.write!(
      G2.path("input-metrics.jsonl"),
      Jason.encode!(%{bytes: bytes, messages: count, accepted: accepted}) <> "\n",
      [:append]
    )

    unless accepted, do: raise("synthetic input budget exceeded before model IO")
    state
  end
end
