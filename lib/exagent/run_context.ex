defmodule ExAgent.RunContext do
  @moduledoc """
  The context object threaded through dynamic instructions, tool calls and
  output validators during a single run.

  It carries the user-supplied `deps`, the model, the full message history, the
  accumulated token `usage`, per-tool retry counters and the current
  step/position info. The `:deps` value is application-defined; document its
  expected shape with `@spec` in your tools.

  `execution_scope` is an opaque, ephemeral handle for `ExAgent.run_child/4`.
  Run/parent/root identities and `model_request_id` correlate work without
  treating model request counts as local loop steps. Never serialize the handle.
  `observability` and `trace_context` are likewise ephemeral; framework delegation
  explicitly carries them across task boundaries and restores prior context.
  """

  alias ExAgent.{Message, Model}

  defstruct deps: nil,
            run_id: nil,
            execution_scope: nil,
            root_run_id: nil,
            parent_run_id: nil,
            observability: nil,
            trace_context: nil,
            model_request_id: nil,
            model: nil,
            prompt: nil,
            messages: [],
            usage: %ExAgent.Message.Usage{input_tokens: 0, output_tokens: 0},
            retries: %{},
            run_step: 0,
            # tool-call-local fields (set when invoking a tool)
            tool_name: nil,
            tool_call_id: nil,
            retry: 0,
            max_retries: 1,
            metadata: %{}

  @type t :: %__MODULE__{
          deps: term(),
          run_id: String.t() | nil,
          execution_scope: ExAgent.ExecutionScope.t() | nil,
          root_run_id: String.t() | nil,
          parent_run_id: String.t() | nil,
          observability: ExAgent.Observability.OpenTelemetry.t() | nil,
          trace_context: term(),
          model_request_id: String.t() | nil,
          model: Model.model(),
          prompt: String.t() | nil,
          messages: [Message.t()],
          usage: Message.Usage.t(),
          retries: %{String.t() => non_neg_integer()},
          run_step: non_neg_integer(),
          tool_name: String.t() | nil,
          tool_call_id: String.t() | nil,
          retry: non_neg_integer(),
          max_retries: non_neg_integer(),
          metadata: map()
        }

  @doc "Build a fresh context for a run."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct!(__MODULE__, opts)
  end
end
