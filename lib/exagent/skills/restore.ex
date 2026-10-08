defmodule ExAgent.Skills.Restore do
  @moduledoc """
  Capability that restores loaded skills removed from the request projection.

  `ExAgent.new/1` appends it after the agent's own capabilities when `:skills` is
  set (see `ExAgent.Skills`), so it runs after compaction. When an earlier
  capability set a `request_messages` projection that no longer contains a
  loaded skill's `load_skill` result, it inserts those results again as one
  user-level message, in the same position as a compaction summary: before the
  first message that is not instructions-only. Without a projection it does
  nothing. The canonical history is never changed, and the restored text is not
  counted by a compaction threshold that ran before it.
  """

  use ExAgent.Capability

  alias ExAgent.Compaction.Projection
  alias ExAgent.Message.{Part, Request}

  @impl true
  def before_model_request(_restore, %{request_messages: nil} = state), do: state

  def before_model_request(_restore, state) do
    # Compared by returned content, so a capability that rewrites call
    # arguments in the projection does not cause repeated restores.
    present =
      for %Request{parts: parts} <- state.request_messages,
          %Part.ToolReturn{tool_name: "load_skill", content: content} <- parts,
          into: MapSet.new(),
          do: content

    case Enum.reject(ExAgent.Skills.loaded_returns(state.messages), &(elem(&1, 1) in present)) do
      [] ->
        state

      missing ->
        text =
          "Skills loaded earlier in this conversation (restored after context " <>
            "compaction; their instructions still apply):\n\n" <>
            Enum.map_join(missing, "\n\n", &elem(&1, 1))

        %{state | request_messages: Projection.insert_context(state.request_messages, text)}
    end
  end
end
