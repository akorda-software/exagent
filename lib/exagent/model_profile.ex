defmodule ExAgent.ModelProfile do
  @moduledoc """
  Declaration of what a given model/provider supports, so callers
  and future capabilities can negotiate gracefully per model — e.g. whether the
  provider can do native JSON-schema output, forced tool calls, or extended
  thinking.

  Every model returns one via the optional `c:ExAgent.Model.profile/1`
  callback; providers that don't implement it get a permissive default.

  The core enforces `supports_tools` for function tools and tool-based structured
  output. It rejects unsupported requirements instead of silently downgrading.
  Native JSON and thinking flags remain advisory for features not selected by
  the current tool-output mode; `supports_json_schema_output: false` therefore
  does not disable Ecto output through a tool. Streaming requires the optional
  model callback and is not required for a synchronous custom model.
  """

  @type output_mode :: :text | :tool | :native | :prompted | :auto

  defstruct supports_tools: true,
            supports_json_schema_output: true,
            supports_json_object_output: true,
            supports_thinking: false,
            default_output_mode: :tool

  @type t :: %__MODULE__{
          supports_tools: boolean(),
          supports_json_schema_output: boolean(),
          supports_json_object_output: boolean(),
          supports_thinking: boolean(),
          default_output_mode: output_mode()
        }
end
