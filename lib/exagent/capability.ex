defmodule ExAgent.Capability do
  @moduledoc """
  Composable middleware that observes/transforms an agent run at well-defined
  points. This is ExAgent's "capabilities" spine, modelled the Elixir way: a
  behaviour whose callbacks default to no-ops via `use ExAgent.Capability`, so
  a capability overrides only the hooks it cares about.

  A capability is a module or a configured struct. That value is passed as the
  first argument to its callbacks, keeping configuration explicit without global
  state. Hooks compose in list order.

  ## Hooks (all optional)

    * `before_model_request(cap, state)` — return (possibly modified) `state`.
      Set `state.request_messages` to alter what's sent to the model without
      touching the canonical history (e.g. keep a sliding window, redact PII).
      Select `state.model`, `state.settings` and `state.params.function_tools`
      here. Selected tools are prepared and become this request's executable set;
      the wider agent inventory does not authorize omitted tools.
    * `after_model_request(cap, state)` — observe/modify state after the model
      responded (state already includes the new response + merged usage).
    * `before_tool_execute(cap, ctx, tool_call)` — observe or transform arguments,
      revalidated before authority. ID, name, kind and metadata are immutable for
      every Model; context includes call identity/retry fields.
    * `after_tool_execute(cap, ctx, tool_call, result)` — observe a tool result.

  Model after-hooks transform the effective response before tool admission;
  their output still passes validation, limits and ancestor authority.
  Before-tool exceptions report `:not_executed`; after-tool failures retain
  confirmed effects. Hooks are trusted host code, not a sandbox. Run identity,
  scope handles, prepared validators and accounting fields are internal and must
  not be replaced.

  In Model hooks, `tool_retries`, `output_retries_used`, `run_step`, `tool_calls`,
  `max_steps` and `agent.output_retries` are observable, runtime-owned values.
  Writes to these six fields are ignored: each callback's result restores the
  confirmed values before the next capability and before admission/persistence/IO.
  Configure limits before starting the run; callbacks cannot replenish budgets.
  Other valid agent/model/settings/tool selections and response/projection
  transformations remain supported, including selected tools' `max_retries`.
  This applies to actual runs, not generic maps passed to <code>ExAgent.Capabilities</code>.
  It is a behavioral change for the pending major; invalid callback results are
  not repaired into valid runs, and historical persisted counters are not migrated.

  ## Example

      defmodule MyApp.RedactPII do
        use ExAgent.Capability

        @impl true
        def before_model_request(_cap, state) do
          redacted = redact(state.messages)
          %{state | request_messages: redacted}
        end
      end

      ExAgent.new(model: "test", capabilities: [MyApp.RedactPII])
  """

  @type state :: map()

  @callback before_model_request(cap :: module(), state()) :: state()
  @callback after_model_request(cap :: module(), state()) :: state()
  @callback before_tool_execute(cap :: module(), map(), struct()) :: struct()
  @callback after_tool_execute(cap :: module(), map(), struct(), term()) :: term()

  @optional_callbacks [
    before_model_request: 2,
    after_model_request: 2,
    before_tool_execute: 3,
    after_tool_execute: 4
  ]

  defmacro __using__(_opts) do
    quote do
      @behaviour ExAgent.Capability

      def before_model_request(_cap, state), do: state
      def after_model_request(_cap, state), do: state
      def before_tool_execute(_cap, ctx, tool_call), do: tool_call
      def after_tool_execute(_cap, ctx, tool_call, result), do: result

      defoverridable before_model_request: 2,
                     after_model_request: 2,
                     before_tool_execute: 3,
                     after_tool_execute: 4
    end
  end
end

defmodule ExAgent.Capabilities do
  @moduledoc false
  # Reduces a list of capability modules over the run state / call / result,
  # calling each implemented hook. Capabilities compose in list order.

  @spec before_model_request([module()], map()) :: map()
  def before_model_request(caps, state) do
    Enum.reduce(caps, state, fn cap, acc ->
      call_if(cap, :before_model_request, [cap, acc], acc)
      |> runtime_counters(state)
    end)
  end

  @spec after_model_request([module()], map()) :: map()
  def after_model_request(caps, state) do
    Enum.reduce(caps, state, fn cap, acc ->
      call_if(cap, :after_model_request, [cap, acc], acc)
      |> runtime_counters(state)
    end)
  end

  # Restore only existing fields: malformed callback results must not acquire
  # defaults or be rebuilt as valid runs. Generic map pipelines remain generic.
  defp runtime_counters(transformed, %ExAgent.Run{} = confirmed) do
    %{
      transformed
      | tool_retries: confirmed.tool_retries,
        output_retries_used: confirmed.output_retries_used,
        run_step: confirmed.run_step,
        tool_calls: confirmed.tool_calls,
        max_steps: confirmed.max_steps,
        agent: %{transformed.agent | output_retries: confirmed.agent.output_retries}
    }
  end

  defp runtime_counters(transformed, _confirmed), do: transformed

  @spec before_tool_execute([module()], map(), struct()) :: struct()
  def before_tool_execute(caps, ctx, tool_call) do
    Enum.reduce(caps, tool_call, fn cap, acc ->
      call_if(cap, :before_tool_execute, [cap, ctx, acc], acc)
    end)
  end

  @spec after_tool_execute([module()], map(), struct(), term()) :: term()
  def after_tool_execute(caps, ctx, tool_call, result) do
    Enum.reduce(caps, result, fn cap, acc ->
      call_if(cap, :after_tool_execute, [cap, ctx, tool_call, acc], acc)
    end)
  end

  defp call_if(cap, fun, args, default) do
    mod = impl(cap)

    # `function_exported?/3` returns false if the module isn't loaded in the
    # current process (e.g. a Task spawned by Task.Supervisor that has the code
    # path but hasn't touched the module yet). Host-app capabilities defined in
    # their own modules routinely hit this in async tool/run paths — so force
    # a load before the check. Cheap when the module is already loaded.
    Code.ensure_loaded(mod)

    if function_exported?(mod, fun, length(args)) do
      apply(mod, fun, args)
    else
      default
    end
  end

  defp impl(mod) when is_atom(mod), do: mod
  defp impl(%{__struct__: mod}), do: mod
end
