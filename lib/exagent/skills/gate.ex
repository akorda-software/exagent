defmodule ExAgent.Skills.Gate do
  @moduledoc """
  Capability that offers a skill's tools only after the skill is loaded.

  `ExAgent.new/1` places it before the agent's own capabilities when a skill has
  `:tools` (see `ExAgent.Skills`). Before each model request it omits every gated
  tool from `function_tools` until one of its skills has been loaded successfully
  in the conversation. Once loaded, the tool is offered again from the agent's
  tool inventory: the request tool set persists between steps, so a tool omitted
  on an earlier step must be put back explicitly.

  Omitted tools are not executable for that request. Capabilities that run later
  can still remove (or add) tools, so the gate is a disclosure mechanism, not a
  security boundary; use `ExAgent.Permissions` for authority.
  """

  use ExAgent.Capability

  @enforce_keys [:gates]
  defstruct [:gates]

  @typedoc "Gated tool name => names of the skills that unlock it."
  @type t :: %__MODULE__{gates: %{String.t() => [String.t()]}}

  @impl true
  def before_model_request(%__MODULE__{gates: gates}, state) when map_size(gates) > 0 do
    loaded = ExAgent.Skills.loaded(state.messages)
    open? = fn name -> Enum.any?(Map.fetch!(gates, name), &(&1 in loaded)) end
    gated? = &Map.has_key?(gates, &1.name)

    kept = Enum.reject(state.params.function_tools, &(gated?.(&1) and not open?.(&1.name)))
    present = MapSet.new(kept, & &1.name)

    opened =
      Enum.filter(state.agent.tools, fn tool ->
        gated?.(tool) and open?.(tool.name) and not MapSet.member?(present, tool.name)
      end)

    %{state | params: %{state.params | function_tools: kept ++ opened}}
  end

  def before_model_request(_gate, state), do: state
end
