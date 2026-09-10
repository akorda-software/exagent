defmodule ExAgent do
  @external_resource "README.md"

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.at(1)

  alias ExAgent.{Model, ModelSettings, ModelRequestParameters, RunContext, Tool}
  alias ExAgent.Message.{Part, Request, Response, Usage}
  alias ExAgent.ExecutionScope
  alias ExAgent.Observability.OpenTelemetry, as: Observability

  defstruct model: nil,
            instructions: [],
            output_type: :text,
            tools: [],
            settings: %ModelSettings{},
            output_retries: 1,
            tool_timeout: 30_000,
            max_steps: 50,
            usage_limits: nil,
            capabilities: [],
            name: nil,
            observability: nil

  @type output_type :: :text | module()
  @type t :: %__MODULE__{
          model: Model.model(),
          instructions: [Part.System.t()],
          output_type: output_type(),
          tools: [Tool.t()],
          settings: ModelSettings.t(),
          output_retries: non_neg_integer(),
          tool_timeout: pos_integer(),
          max_steps: pos_integer(),
          usage_limits: ExAgent.UsageLimits.t() | nil,
          capabilities: [module() | struct()],
          name: String.t() | nil,
          observability: Observability.t() | nil
        }

  @type result :: %{
          output: term(),
          messages: [ExAgent.Message.t()],
          new_messages: [ExAgent.Message.t()],
          usage: Usage.t(),
          run_step: non_neg_integer(),
          model: Model.model(),
          run_id: String.t(),
          root_run_id: String.t(),
          parent_run_id: String.t() | nil,
          model_request_id: String.t() | nil,
          request_count: non_neg_integer(),
          tool_calls: non_neg_integer(),
          cost_cents: number() | nil,
          cost_status: :known | :unknown,
          status: :succeeded | :failed | :cancelled | :running,
          usage_status: :complete | :partial,
          pending_response: Response.t() | nil
        }

  @output_tool_name "final_result"

  # -------------------------------------------------------------------------
  # Construction
  # -------------------------------------------------------------------------
  @doc """
  Build an agent from options. Use `:output` for the output spec.

  Valid tool schemas are prepared once on the reusable definition. Invalid
  schemas still fail as operational `RunError`s when running the agent; each
  run also checks that a prepared validator matches the tool's current schema.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    model =
      case Keyword.fetch!(opts, :model) do
        %_{} = m -> m
        spec -> resolve_model!(spec)
      end

    %__MODULE__{
      model: model,
      instructions: to_instructions(Keyword.get(opts, :instructions)),
      output_type: Keyword.get(opts, :output, Keyword.get(opts, :output_type, :text)),
      tools: prepare_definition_tools(Keyword.get(opts, :tools, [])),
      settings: ModelSettings.new(Keyword.get(opts, :model_settings, [])),
      output_retries: Keyword.get(opts, :output_retries, 1),
      tool_timeout: Keyword.get(opts, :tool_timeout, 30_000),
      max_steps: Keyword.get(opts, :max_steps, 50),
      usage_limits: Keyword.get(opts, :usage_limits),
      capabilities: Keyword.get(opts, :capabilities, []),
      name: Keyword.get(opts, :name),
      observability: Keyword.get(opts, :observability)
    }
  end

  defp prepare_definition_tools(tools) when is_list(tools) do
    Enum.map(tools, fn
      %Tool{} = tool ->
        case Tool.prepare(tool) do
          {:ok, prepared} -> prepared
          {:error, _} -> tool
        end

      other ->
        other
    end)
  end

  defp prepare_definition_tools(tools), do: tools

  defp resolve_model!(spec) do
    case Model.resolve(spec) do
      {:ok, model} -> model
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  defp to_instructions(nil), do: []

  defp to_instructions(instructions) when is_binary(instructions),
    do: [%Part.System{content: instructions}]

  defp to_instructions(list) when is_list(list),
    do: Enum.map(list, &%Part.System{content: &1})

  # When output is an Ecto schema module, the model is forced to call an output
  # tool whose args are the schema; we validate those args (retry on failure).
  # For `:text` there's no output tool and free-text responses are allowed.
  defp output_config(%__MODULE__{output_type: :text}), do: {:text, [], true}

  defp output_config(%__MODULE__{output_type: mod}) when is_atom(mod) do
    tool = %Tool{
      name: @output_tool_name,
      description: "Return the final answer as structured data.",
      parameters_json_schema: ExAgent.OutputSchema.json_schema(mod),
      kind: :output,
      takes_ctx: false,
      call: nil
    }

    {:tool, [tool], false}
  end

  # -------------------------------------------------------------------------
  # Running
  # -------------------------------------------------------------------------
  @doc """
  Run the agent against `prompt`, returning `{:ok, result}` or `{:error, _}`.

  Operational errors contain an `ExAgent.RunError`: its `reason` is the cause
  and `partial` preserves history, usage and the last confirmed model. Retrying
  the prompt is a new execution and can repeat effects.

  Options:
    * `:deps`              — dependency value threaded into `RunContext`.
    * `:message_history`   — prior `Message.t()` list to continue from.
    * `:model_settings`    — per-run settings overrides.
    * `:stream_text`       — stream model text through the same agent loop.
    * `:estimate_cost`     — `(usage -> cents)` for a homogeneous model tree, or
      `(model, usage -> cents)` for model-aware pricing; nil/`:unknown` remains
      unknown. Monetary limits require a valid estimator before model admission.
    * `:deadline`          — optional absolute monotonic milliseconds; inherited
      descendants may only shorten it. Admission and native IO timeouts honor it,
      but arbitrary application callbacks are not preempted.
    * `:max_concurrent_requests` — optional positive cap, shared with descendants;
      saturated admission fails explicitly without adding a waiting queue.
    * `:on_progress`       — optional runtime callback receiving full result-shaped
      snapshots; these contain a live model and must not be exported as JSON.
      While a batch is in flight, unresolved calls have `status: :unknown` in
      these snapshots; final history replaces them with the collected outcomes.
    * `:observability`     — optional `ExAgent.Observability.OpenTelemetry` config;
      overrides the agent default. `false` disables instrumentation for this run.
    * `:trace_context`     — ephemeral context captured with the OTel adapter;
      use for application-owned process boundaries, never persisted snapshots.
  """
  @spec run(t(), String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def run(agent, prompt, opts \\ []) do
    state = init_state(agent, prompt, opts)
    config = Observability.configuration(agent.observability, opts)
    state = %{state | observability: config}

    case Keyword.get(opts, :observability_operation) do
      %Observability.Operation{} = operation ->
        Observability.within(operation, fn -> run_observed(state, opts, operation) end)

      _ ->
        Observability.around(
          config,
          :run,
          Observability.ids(state),
          opts[:trace_context],
          fn operation ->
            run_observed(state, opts, operation)
          end
        )
    end
  end

  defp run_observed(state, opts, operation) do
    agent = state.agent
    prompt = state.prompt
    state = %{state | trace_context: Observability.context(operation)}
    Observability.attributes(operation, %{"gen_ai.agent.name" => Observability.label(agent.name)})
    Observability.content(operation, :input, prompt)
    start = System.monotonic_time()

    ExAgent.Telemetry.execute([:run, :start], %{system_time: start}, %{
      agent: agent.name,
      prompt: prompt
    })

    result = protect(state, fn -> execute_scoped(state, opts) end)
    duration = System.monotonic_time() - start

    case result do
      {:ok, %{usage: usage, run_step: steps} = res} ->
        emit(%{state | run_step: steps}, :run_finished, %{
          output: res.output,
          usage: usage,
          steps: steps
        })

        ExAgent.Telemetry.execute([:run, :stop], %{duration: duration}, %{
          agent: agent.name,
          usage: usage,
          steps: steps
        })

      {:error, %ExAgent.RunError{} = error} ->
        emit(%{state | run_step: error.partial.run_step}, :run_failed, %{reason: error.reason})

        ExAgent.Telemetry.execute([:run, :exception], %{duration: duration}, %{
          agent: agent.name,
          reason: ExAgent.ErrorProjection.reason(error.reason)
        })
    end

    unless opts[:observability_operation], do: Observability.run_result(operation, result)
    result
  end

  @doc """
  Run an auxiliary/delegated agent under an existing run's execution scope.

  Accepts a `RunContext` or the state passed to a model capability. The helper
  inherits dependencies and fixes ancestry after caller options; a builder cannot
  replace the inherited scope. Child limits/policies add restrictions to all
  ancestors. Child progress is not forwarded as parent conversation history.
  """
  def run_child(%{execution_scope: %ExecutionScope{}} = parent, agent, prompt, opts \\ []) do
    opts =
      opts
      |> Keyword.drop([:parent_context, :execution_scope, :run_id])
      |> Keyword.put_new(:deps, Map.get(parent, :deps))
      |> Keyword.put(:parent_context, parent)
      |> Keyword.put(:trace_context, Map.get(parent, :trace_context))
      |> Keyword.put(:observability, Map.get(parent, :observability))

    config = Map.get(parent, :observability)

    Observability.around(
      config,
      :delegation,
      Observability.ids(parent),
      opts[:trace_context],
      fn operation ->
        run(agent, prompt, Keyword.put(opts, :trace_context, Observability.context(operation)))
      end
    )
  end

  defp execute_scoped(state, opts) do
    scope_options =
      opts
      |> Keyword.take([
        :permissions,
        :approve,
        :estimate_cost,
        :deadline,
        :max_concurrent_requests
      ])
      |> Keyword.put(:usage_limits, state.usage_limits)

    opened =
      case Keyword.get(opts, :parent_context) do
        nil ->
          ExecutionScope.start(state.run_id, state.model, scope_options)

        %{execution_scope: %ExecutionScope{} = parent} ->
          ExecutionScope.join(parent, state.run_id, state.model, scope_options)

        _ ->
          {:error, :invalid_parent_execution_scope}
      end

    case opened do
      {:ok, scope} ->
        state = %{
          state
          | execution_scope: scope,
            root_run_id: scope.root_run_id,
            parent_run_id: scope.parent_run_id
        }

        try do
          state = progress(state)
          emit(state, :run_started, %{prompt: state.prompt})
          protect(state, fn -> prepare_run(state) end)
        after
          ExecutionScope.finish_run(scope)
          if scope.parent_run_id == nil, do: ExecutionScope.stop(scope)
        end

      {:error, reason} ->
        fail(state, reason)
    end
  end

  @doc "Run synchronously and return the output value directly, raising on error."
  @spec run!(t(), String.t(), keyword()) :: term()
  def run!(agent, prompt, opts \\ []) do
    case run(agent, prompt, opts) do
      {:ok, %{output: out}} -> out
      {:error, reason} -> raise ExAgent.UnexpectedModelBehavior, reason
    end
  end

  @doc ~S"""
  Run the agent, returning a **lazy stream** of events as the model generates.

  This is the streaming variant. It yields:

    * `{:delta, binary}` — incremental output text (one per model text chunk),
    * `{:result, map}` — the final result once the stream completes.

  On failure it yields one `{:error, %ExAgent.RunError{}}` terminal. Deltas
  are provisional text from all model requests; the final output is validated
  by the same tools/output/hooks/limits loop as `run/3`.

  Each enumeration starts a new run. Halting enumeration or killing its owner
  cancels the owned worker; effects already performed are not rolled back.
  A suspended Enumerable continuation must be resumed or explicitly halted.
  """
  @spec run_stream(t(), String.t(), keyword()) :: Enumerable.t()
  def run_stream(agent, prompt, opts \\ []) do
    ExAgent.RunStream.new(agent, prompt, opts)
  end

  # ----- per-run state -----------------------------------------------------
  defmodule Run do
    @moduledoc false
    defstruct agent: nil,
              model: nil,
              messages: [],
              # index into `messages` where this run's new messages begin
              first_new_message_index: 0,
              usage: %ExAgent.Message.Usage{input_tokens: 0, output_tokens: 0},
              deps: nil,
              settings: nil,
              params: nil,
              prompt: nil,
              output_retries_used: 0,
              # per-tool-name failure counters (drives the per-tool retry budget)
              tool_retries: %{},
              tool_timeout: 30_000,
              usage_limits: nil,
              capabilities: [],
              # transient override of messages sent to the model (set by capabilities)
              request_messages: nil,
              run_step: 0,
              max_steps: 50,
              # optional event sink: (ExAgent.RunEvent.t() -> any()). No-op by
              # default so one-shot callers that don't pass :on_event pay nothing.
              on_event: nil,
              on_progress: nil,
              run_id: nil,
              execution_scope: nil,
              root_run_id: nil,
              parent_run_id: nil,
              observability: nil,
              trace_context: nil,
              model_request_id: nil,
              admitted_requests: 0,
              scope_snapshot: nil,
              usage_status: :complete,
              pending_response: nil,
              prepared_tools: %{},
              # number of tool calls executed so far this run (drives tool_calls_limit)
              tool_calls: 0,
              # optional (Usage.t() -> cents()) for max_budget_cents enforcement
              cost_estimator: nil,
              # optional ExAgent.Permissions.t() for per-tool admission control
              permissions: nil,
              # optional (tool_call -> :approve | :deny) for :ask permissions
              approve: nil,
              # when true, the loop consumes the model's stream and emits
              # :text_delta RunEvents so a UI can render tokens live. Tool
              # calls emitted mid-stream still feed the agentic loop normally.
              stream_text: false
  end

  defp init_state(agent, prompt, opts) do
    history = Keyword.get(opts, :message_history, [])

    settings =
      ModelSettings.merge(
        agent.settings,
        ModelSettings.new(Keyword.get(opts, :model_settings, []))
      )

    # On the first turn of a conversation we prepend the agent's system
    # instructions into the canonical history (so they survive serialization and
    # are seen by every subsequent run). When *continuing* an existing
    # conversation (non-empty history that already carries the instructions),
    # we only append the new user prompt — no duplicated system messages.
    prepend_instructions? = history == [] and Keyword.get(opts, :prepend_instructions, true)

    user = %Part.User{content: prompt, timestamp: DateTime.utc_now()}

    first_parts = if prepend_instructions?, do: agent.instructions ++ [user], else: [user]

    run_id = Keyword.get(opts, :run_id) || new_id("run")

    first_request = %Request{
      parts: first_parts,
      run_id: run_id,
      timestamp: DateTime.utc_now()
    }

    %Run{
      agent: agent,
      model: agent.model,
      messages: history ++ [first_request],
      first_new_message_index: length(history),
      deps: Keyword.get(opts, :deps),
      settings: settings,
      params: %ModelRequestParameters{},
      prompt: prompt,
      tool_timeout: agent.tool_timeout,
      max_steps: agent.max_steps,
      usage_limits: agent.usage_limits,
      capabilities: agent.capabilities,
      on_event: Keyword.get(opts, :on_event),
      on_progress: Keyword.get(opts, :on_progress),
      run_id: run_id,
      root_run_id: get_in(opts, [:parent_context, Access.key(:root_run_id)]) || run_id,
      parent_run_id: get_in(opts, [:parent_context, Access.key(:run_id)]),
      cost_estimator: Keyword.get(opts, :estimate_cost),
      permissions: Keyword.get(opts, :permissions),
      approve: Keyword.get(opts, :approve),
      stream_text: Keyword.get(opts, :stream_text, false)
    }
  end

  defp prepare_run(state) do
    {mode, outputs, allow_text} = output_config(state.agent)

    prepared =
      Enum.reduce_while(state.agent.tools, {:ok, %{}}, fn tool, {:ok, tools} ->
        cond do
          Map.has_key?(tools, tool.name) or Enum.any?(outputs, &(&1.name == tool.name)) ->
            {:halt, {:error, {:duplicate_tool_name, tool.name}}}

          true ->
            case Tool.prepare(tool) do
              {:ok, tool} -> {:cont, {:ok, Map.put(tools, tool.name, tool)}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
        end
      end)

    case prepared do
      {:ok, tools} ->
        params = %ModelRequestParameters{
          function_tools: Enum.map(state.agent.tools, &Map.fetch!(tools, &1.name)),
          output_tools: outputs,
          output_mode: mode,
          allow_text_output: allow_text,
          instructions: state.agent.instructions
        }

        drive(%{state | params: params, prepared_tools: tools})

      {:error, reason} ->
        fail(state, reason)
    end
  end

  # ----- the loop ----------------------------------------------------------
  # Emit a loop event to the optional :on_event sink. No-op when unset, so the
  # pure one-shot path is unaffected. `state` is read for run_id/step context.
  defp emit(%Run{on_event: nil}, _type, _data), do: :ok

  defp emit(%Run{on_event: fun} = state, type, data) when is_function(fun, 1) do
    event = ExAgent.RunEvent.new(type, run_id: state.run_id, step: state.run_step, data: data)
    fun.(event)
  rescue
    # A misbehaving event sink must never break a run.
    _ -> :ok
  catch
    :throw, :exagent_stream_cancelled -> throw(:exagent_stream_cancelled)
    _, _ -> :ok
  end

  defp drive(%Run{run_step: step, max_steps: max} = state) when step >= max,
    do: fail(state, {:max_steps_exceeded, max})

  defp drive(%Run{} = state) do
    state = refresh_scope(state)

    protect(state, fn ->
      case check_usage_limits(state) do
        :ok ->
          state = %{state | run_step: state.run_step + 1}
          emit(state, :run_step_started, %{step: state.run_step})
          state = progress(state)

          protect(state, fn ->
            state = ExAgent.Capabilities.before_model_request(state.capabilities, state)
            request_step(state)
          end)

        {:error, reason} ->
          fail(state, reason)
      end
    end)
  end

  defp request_step(state) do
    state = refresh_scope(state)

    protect(state, fn ->
      case check_model_requirements(state) do
        :ok -> request_model(state)
        {:error, reason} -> fail(state, reason)
      end
    end)
  end

  defp check_model_requirements(state) do
    tools? = state.params.function_tools != [] or state.params.output_tools != []

    case Model.profile(state.model) do
      %ExAgent.ModelProfile{supports_tools: false} when tools? -> {:error, {:unsupported, :tools}}
      %ExAgent.ModelProfile{supports_tools: supported} when is_boolean(supported) -> :ok
      _ -> {:error, :invalid_model_profile}
    end
  end

  defp request_model(state) do
    id = new_id("model_request")

    case ExecutionScope.admit_request(state.execution_scope, id, state.model) do
      :ok ->
        timeout = ExecutionScope.remaining_timeout(state.execution_scope, state.settings.timeout)

        state = %{
          state
          | model_request_id: id,
            admitted_requests: state.admitted_requests + 1,
            settings: %{state.settings | timeout: timeout}
        }

        try do
          perform_model_request(state)
        after
          ExecutionScope.finish_request(state.execution_scope, id)
        end

      {:error, reason} ->
        fail(state, reason)
    end
  end

  defp perform_model_request(state) do
    protect(state, fn ->
      messages = state.request_messages || state.messages

      {response, accounting} = observed_model_request(state, messages)

      case response do
        {:ok, %Response{} = response, model} ->
          accept_response(state, response, model, accounting)

        {:stream_response, %Response{} = response, model, snapshot, _complete?} ->
          accept_response(%{state | scope_snapshot: snapshot}, response, model, accounting)

        {:error, %ExAgent.RunError{}} = error ->
          error
      end
    end)
  end

  defp observed_model_request(state, messages) do
    attrs =
      Observability.ids(state)
      |> Map.merge(Observability.model_attributes(state.observability, state.model))
      |> Map.put("exagent.run_step", state.run_step)

    operation = Observability.start(state.observability, :model, attrs, state.trace_context)

    Observability.within(operation, fn ->
      try do
        if operation do
          Observability.messages(operation, messages)
        end

        response =
          if state.stream_text,
            do: drive_stream(state.model, messages, state.settings, state.params, state),
            else: request_sync(state, messages)

        accounting =
          case response do
            {:ok, %Response{} = result, _} ->
              Observability.content(operation, :output, Response.text(result))

              ExecutionScope.record_usage(
                state.execution_scope,
                state.model_request_id,
                result.usage,
                true
              )

            {:stream_response, %Response{} = result, _, _, complete?} ->
              Observability.content(operation, :output, Response.text(result))

              ExecutionScope.record_usage(
                state.execution_scope,
                state.model_request_id,
                result.usage,
                complete?
              )

            _ ->
              :ok
          end

        if operation do
          Observability.model_result(
            operation,
            ExecutionScope.request_snapshot(state.execution_scope, state.model_request_id),
            state.model
          )
        end

        Observability.finish(operation, response)
        {response, accounting}
      catch
        kind, reason ->
          Observability.finish(operation, {:error, reason})
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end)
  end

  defp request_sync(state, messages) do
    case Model.request(state.model, messages, state.settings, state.params) do
      {:ok, %Response{} = response, %_{} = model} -> {:ok, response, model}
      {:error, reason} -> request_failed(state, reason)
      other -> request_failed(state, {:invalid_model_result, other})
    end
  rescue
    error -> request_failed(state, error)
  catch
    kind, reason -> request_failed(state, {kind, reason})
  end

  defp accept_response(state, response, model, accounting) do
    # Release the model slot before hooks can delegate and before tools execute.
    ExecutionScope.finish_request(state.execution_scope, state.model_request_id)

    state = %{
      state
      | model: model,
        request_messages: nil,
        pending_response: nil,
        usage: merge_usage(state.usage, response.usage),
        usage_status: if(response.usage, do: state.usage_status, else: :partial)
    }

    state = refresh_scope(state)

    case identify_calls(response) do
      {:ok, response} ->
        state = %{state | messages: append(state.messages, response)}
        state = progress(state)

        case accounting do
          :ok ->
            protect(state, fn ->
              transformed = ExAgent.Capabilities.after_model_request(state.capabilities, state)

              case effective_response(transformed, response, state) do
                {:ok, effective, transformed} ->
                  protect(transformed, fn ->
                    case ExecutionScope.check(transformed.execution_scope) do
                      :ok -> handle_response(effective, transformed)
                      {:error, reason} -> fail(transformed, reason)
                    end
                  end)

                {:error, reason} ->
                  fail(state, reason)
              end
            end)

          {:error, reason} ->
            fail(state, reason)
        end

      {:error, reason} ->
        # Invalid identity cannot be repaired by executing or inventing a
        # successful history. Keep the raw response separately for diagnosis.
        fail(%{state | pending_response: response}, reason)
    end
  end

  defp effective_response(%Run{messages: messages} = transformed, original, confirmed)
       when is_list(messages) do
    with true <-
           Enum.all?(messages, fn
             %Request{parts: parts} when is_list(parts) -> true
             %Response{parts: parts} when is_list(parts) -> true
             _ -> false
           end),
         %Response{parts: parts} = response when is_list(parts) <- List.last(messages),
         true <- response == original or Enum.all?(parts, &valid_response_part?/1),
         {:ok, response} <- identify_calls(response) do
      # The hook controls content, not the provider's already reported bill or
      # truncation signal. Neither is recomputed from transformed text/tools.
      finish_reason =
        if original.finish_reason in [:length, :content_filter],
          do: original.finish_reason,
          else: response.finish_reason

      response = %{response | usage: original.usage, finish_reason: finish_reason}

      transformed = %{
        transformed
        | messages: List.replace_at(messages, -1, response),
          usage: confirmed.usage,
          usage_status: confirmed.usage_status,
          scope_snapshot: confirmed.scope_snapshot
      }

      {:ok, response, progress(transformed)}
    else
      _ -> {:error, :invalid_model_response_transform}
    end
  end

  defp effective_response(_, _, _), do: {:error, :invalid_model_response_transform}
  defp valid_response_part?(%Part.Text{content: text}), do: is_binary(text)
  defp valid_response_part?(%Part.Thinking{content: text}), do: is_binary(text)
  defp valid_response_part?(%Part.ToolCall{tool_name: name}), do: is_binary(name)
  defp valid_response_part?(_), do: false

  defp drive_stream(model, messages, settings, params, state) do
    on_delta = deps_on_text_delta(state.deps)

    initial = %{text: [], thinking: [], usage: nil, scope_snapshot: state.scope_snapshot}

    outcome =
      model
      |> Model.request_stream(messages, settings, params)
      |> Enum.reduce_while(initial, fn
        {:text_delta, chunk}, acc when is_binary(chunk) ->
          acc = %{acc | text: [chunk | acc.text]}
          acc = stream_progress(state, acc)
          if on_delta, do: safe_apply(on_delta, chunk)

          try do
            emit(state, :text_delta, %{text: chunk})
            {:cont, acc}
          catch
            :throw, :exagent_stream_cancelled ->
              {:halt, fail(stream_partial(state, acc), :cancelled)}
          end

        {:usage, %Usage{} = usage}, acc ->
          acc = %{acc | usage: usage}
          ExecutionScope.record_usage(state.execution_scope, state.model_request_id, usage)
          acc = stream_progress(state, acc)
          {:cont, acc}

        {:thinking_delta, chunk}, acc when is_binary(chunk) ->
          acc = %{acc | thinking: [chunk | acc.thinking]}
          acc = stream_progress(state, acc)
          emit(state, :thinking_delta, %{text: chunk})
          {:cont, acc}

        {:response, %Response{} = resp, final_model}, acc ->
          complete? = resp.usage != nil
          response = if complete?, do: resp, else: %{resp | usage: acc.usage}
          {:halt, {:stream_response, response, final_model, acc.scope_snapshot, complete?}}

        {:error, reason}, acc ->
          {:halt, request_failed(stream_partial(state, acc), reason)}
      end)

    case outcome do
      %{} = acc -> request_failed(stream_partial(state, acc), :incomplete_stream)
      terminal -> terminal
    end
  end

  defp stream_progress(state, acc) do
    captured = progress(stream_partial(state, acc))
    %{acc | scope_snapshot: captured.scope_snapshot}
  end

  defp stream_partial(state, %{text: [], thinking: [], usage: nil} = acc),
    do: %{state | usage_status: :partial, scope_snapshot: acc.scope_snapshot}

  defp stream_partial(state, acc) do
    response = %Response{
      parts:
        [%Part.Text{content: acc.text |> Enum.reverse() |> IO.iodata_to_binary()}] ++
          if(acc.thinking == [],
            do: [],
            else: [
              %Part.Thinking{content: acc.thinking |> Enum.reverse() |> IO.iodata_to_binary()}
            ]
          ),
      usage: acc.usage
    }

    %{
      state
      | pending_response: response,
        scope_snapshot: acc.scope_snapshot,
        usage: merge_usage(state.usage, acc.usage),
        usage_status: :partial
    }
  end

  defp request_failed(state, %ExAgent.RequestError{} = reason) do
    state = %{state | model: reason.model || state.model, usage_status: :partial}

    # The adapter's partial response replaces the provisional request snapshot.
    state =
      if reason.partial_response do
        previous = if state.pending_response, do: state.pending_response.usage, else: nil
        usage = replace_request_usage(state.usage, previous, reason.partial_response.usage)
        %{state | pending_response: reason.partial_response, usage: usage}
      else
        state
      end

    record_failed_request(state)
    fail(state, {:model_request_failed, reason})
  end

  defp request_failed(state, reason) do
    record_failed_request(state)
    fail(%{state | usage_status: :partial}, {:model_request_failed, reason})
  end

  defp record_failed_request(state) do
    usage = if state.pending_response, do: state.pending_response.usage
    ExecutionScope.record_usage(state.execution_scope, state.model_request_id, usage, false)
    ExecutionScope.finish_request(state.execution_scope, state.model_request_id)
  end

  defp identify_calls(%Response{} = response) do
    parts =
      Enum.map(response.parts, fn
        %Part.ToolCall{tool_call_id: nil} = call -> %{call | tool_call_id: new_id("call")}
        part -> part
      end)

    calls = Response.tool_calls(%{response | parts: parts})
    ids = Enum.map(calls, & &1.tool_call_id)

    cond do
      Enum.any?(ids, &(not is_binary(&1) or &1 == "")) -> {:error, :invalid_tool_call_id}
      length(ids) != length(Enum.uniq(ids)) -> {:error, :duplicate_tool_call_id}
      true -> {:ok, %{response | parts: parts}}
    end
  end

  defp deps_on_text_delta(%{on_text_delta: fun}) when is_function(fun, 1), do: fun
  defp deps_on_text_delta(_), do: nil

  defp safe_apply(fun, arg) do
    fun.(arg)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp check_usage_limits(state), do: ExecutionScope.check_request(state.execution_scope)

  # call_tools_node: decide what to do with the model's response.
  defp handle_response(%Response{} = response, %Run{} = state) do
    tool_calls = Response.tool_calls(response)
    text = Response.text(response)

    cond do
      response.finish_reason == :length ->
        fail(state, {:max_tokens_exceeded, response.model_name})

      response.finish_reason == :content_filter ->
        fail(state, {:content_filter, response.model_name})

      tool_calls != [] ->
        handle_tool_calls(tool_calls, state)

      state.params.allow_text_output and text != "" ->
        finalize_text(text, state)

      true ->
        retry_or_fail(state, actionable_hint(state))
    end
  end

  defp actionable_hint(%Run{params: %{output_tools: [_ | _]}}),
    do: "Please call the #{@output_tool_name} tool to return your answer."

  defp actionable_hint(%Run{}), do: "Please respond."

  # ----- tools -------------------------------------------------------------
  defp handle_tool_calls(tool_calls, %Run{} = state) do
    output_names = MapSet.new(state.params.output_tools, & &1.name)

    case Enum.split_with(tool_calls, &MapSet.member?(output_names, &1.tool_name)) do
      # The model occasionally emits MORE than one output call in one response.
      # Only the first is processed; the rest must still get ToolReturns so the
      # assistant→tool_result pairing stays 1:1 and the history replays cleanly
      # on the next provider request (OpenAI/Anthropic reject mismatched pairs).
      {[output_call | extra_output_calls], siblings} ->
        handle_output_call(output_call, extra_output_calls ++ siblings, state)

      {[], fn_calls} ->
        case check_tool_calls_limit(state, length(fn_calls)) do
          :ok ->
            {parts, retries, error, state} = execute_function_tools(fn_calls, state)

            state =
              Enum.reduce(parts, state, fn part, st ->
                %{st | usage: merge_usage(st.usage, part.usage)}
              end)

            state = %{
              state
              | tool_calls: state.tool_calls + length(fn_calls),
                tool_retries: retries
            }

            state = append_returns(state, parts)
            if error, do: fail(state, error), else: drive(state)

          {:error, reason} ->
            parts = Enum.map(fn_calls, &tool_return(&1, :not_executed, reason_msg(reason)))
            fail(append_returns(state, parts), reason)
        end
    end
  end

  defp check_tool_calls_limit(state, incoming),
    do: ExecutionScope.admit_tools(state.execution_scope, state.model_request_id, incoming)

  # The model returned the structured output: validate it, then finalize. A
  # `ToolReturn` is appended for the output call (plus stubs for any sibling
  # function calls) so the message history stays replayable on the next turn.
  defp handle_output_call(
         %Part.ToolCall{tool_call_id: id} = call,
         siblings,
         %Run{agent: %{output_type: mod}} = state
       )
       when is_atom(mod) and mod != :text do
    attributes =
      Observability.ids(state)
      |> Map.merge(%{
        "exagent.tool_call_id" => Observability.label(id),
        "gen_ai.tool.call.id" => Observability.label(id),
        "gen_ai.tool.name" => @output_tool_name,
        "exagent.tool.kind" => "output"
      })

    validation =
      Observability.around(
        state.observability,
        :tool,
        attributes,
        state.trace_context,
        fn operation ->
          with {:ok, args} <- decode_args(call) do
            Observability.content(operation, :input, args)
            ExAgent.OutputSchema.validate(mod, args)
          end
        end
      )

    with {:ok, data} <- validation do
      parts = [
        %Part.ToolReturn{tool_name: @output_tool_name, content: "ok", tool_call_id: id}
        | Enum.map(siblings, &stub_return/1)
      ]

      state = append_returns(state, parts)

      succeed(data, state)
    else
      {:error, errors} -> retry_or_fail(state, errors, call, Enum.map(siblings, &stub_return/1))
    end
  end

  defp stub_return(%Part.ToolCall{tool_name: name, tool_call_id: id}),
    do: %Part.ToolReturn{
      tool_name: name,
      content: "Tool not executed - a final result was already processed.",
      tool_call_id: id,
      status: :not_executed
    }

  # All admitted outcomes are collected before deciding whether to continue.
  # A task publishes its successful effect before running fallible after-hooks,
  # so even a timeout in that hook cannot erase the completed operation.
  defp execute_function_tools(calls, %Run{} = state) do
    base_ctx = build_context(state)
    owner = self()
    batch_ref = make_ref()
    state = batch_progress(state, calls, %{})

    {producer, monitor} =
      Process.spawn(
        fn ->
          Process.flag(:trap_exit, true)
          ExecutionScope.watch_worker(state.execution_scope)

          results =
            try do
              Task.async_stream(
                calls,
                fn call ->
                  start = System.monotonic_time()

                  outcome =
                    try do
                      case ExecutionScope.watch_worker(state.execution_scope) do
                        {:ok, _guardian} ->
                          attrs =
                            Map.put(
                              Observability.ids(state),
                              "exagent.tool_call_id",
                              Observability.label(call.tool_call_id)
                            )

                          Observability.around(
                            state.observability,
                            :tool,
                            attrs,
                            state.trace_context,
                            fn operation ->
                              ctx = %{base_ctx | trace_context: Observability.context(operation)}

                              outcome =
                                run_tool_raw(call, ctx, state, owner, batch_ref, operation)

                              {part, _, _} = outcome

                              if part.status == :succeeded,
                                do: Observability.content(operation, :output, part.content)

                              outcome
                            end
                          )

                        {:error, reason} ->
                          {tool_return(call, :not_executed, reason_msg(reason)), false, reason}
                      end
                    catch
                      kind, reason ->
                        {tool_return(call, :unknown, reason_msg(reason)), false,
                         {:tool_execution_failed, call.tool_name, {kind, reason}}}
                    end

                  {outcome, System.monotonic_time() - start}
                end,
                ordered: true,
                timeout:
                  ExecutionScope.remaining_timeout(state.execution_scope, state.tool_timeout),
                on_timeout: :kill_task
              )
              |> Enum.zip(calls)
            catch
              kind, reason -> Enum.map(calls, &{{:exit, {kind, reason}}, &1})
            end

          send(owner, {:exagent_batch, batch_ref, results})
        end,
        [:monitor]
      )

    watch_batch_owner(owner, producer)

    {results, confirmed, state} =
      try do
        await_tool_batch(batch_ref, monitor, calls, state, %{})
      after
        Process.unlink(producer)
        if Process.alive?(producer), do: Process.exit(producer, :kill)
        Process.demonitor(monitor, [:flush])
      end

    {parts, retries, error} =
      Enum.reduce(results, {[], state.tool_retries, nil}, fn {task_result, call},
                                                             {parts, retries, fatal} ->
        {{part, retry?, error}, duration} =
          case task_result do
            {:ok, {outcome, duration}} ->
              {outcome, duration}

            {:exit, reason} ->
              part =
                Map.get(confirmed, call.tool_call_id) ||
                  tool_return(call, :unknown, reason_msg(reason))

              {{part, false, {:tool_execution_failed, call.tool_name, {:exit, reason}}},
               System.convert_time_unit(state.tool_timeout, :millisecond, :native)}
          end

        {retries, error} =
          if retry? do
            used = Map.get(retries, part.tool_name, 0) + 1
            retries = Map.put(retries, part.tool_name, used)

            if used > max_retries(find_tool(state, part.tool_name)) do
              {retries,
               {:unexpected_model_behavior, {:tool_retries_exhausted, part.tool_name, error}}}
            else
              {retries, nil}
            end
          else
            retries =
              if part.status == :succeeded, do: Map.delete(retries, part.tool_name), else: retries

            {retries, error}
          end

        emit(state, :tool_call_finished, %{
          tool_name: part.tool_name,
          tool_call_id: part.tool_call_id,
          success: part.status == :succeeded,
          status: part.status,
          duration_ms: System.convert_time_unit(duration, :native, :millisecond)
        })

        ExAgent.Telemetry.execute([:tool, :stop], %{duration: duration}, %{
          tool_name: part.tool_name,
          agent: state.agent.name,
          success: part.status == :succeeded
        })

        {parts ++ [part], retries, fatal || error}
      end)

    {parts, retries, error, state}
  end

  defp await_tool_batch(ref, monitor, calls, state, confirmed) do
    receive do
      {:exagent_tool_confirmed, ^ref, task, part} ->
        ExecutionScope.contribute(
          state.execution_scope,
          {state.model_request_id, part.tool_call_id},
          part.usage
        )

        confirmed = Map.put(confirmed, part.tool_call_id, part)
        state = batch_progress(state, calls, confirmed)
        send(task, {ref, :confirmed, part.tool_call_id})
        await_tool_batch(ref, monitor, calls, state, confirmed)

      {:exagent_batch, ^ref, results} ->
        {results, confirmed, state}

      {:DOWN, ^monitor, :process, _, reason} ->
        {Enum.map(calls, &{{:exit, reason}, &1}), confirmed, state}
    end
  end

  defp watch_batch_owner(owner, producer) do
    spawn(fn ->
      owner_monitor = Process.monitor(owner)
      producer_monitor = Process.monitor(producer)

      receive do
        {:DOWN, ^owner_monitor, :process, ^owner, _} -> Process.exit(producer, :kill)
        {:DOWN, ^producer_monitor, :process, ^producer, _} -> :ok
      end
    end)
  end

  defp batch_progress(state, calls, confirmed) do
    parts =
      Enum.map(calls, fn call ->
        Map.get(confirmed, call.tool_call_id) ||
          tool_return(call, :unknown, "Tool batch is still in flight")
      end)

    captured = refresh_scope(state)

    snapshot = %{
      captured
      | tool_calls: state.tool_calls + length(calls),
        messages:
          append(state.messages, %Request{
            parts: parts,
            run_id: state.run_id,
            timestamp: DateTime.utc_now()
          })
    }

    notify_progress(snapshot, result(nil, snapshot, :running))
    # Keep only accounting on the waiting owner. Provisional tool resolutions
    # are a published projection, never appended repeatedly to canonical history.
    %{state | scope_snapshot: captured.scope_snapshot, usage_status: captured.usage_status}
  end

  defp run_tool_raw(original, ctx, state, owner, batch_ref, operation) do
    caps = state.capabilities
    call = ExAgent.Capabilities.before_tool_execute(caps, ctx, original)

    if not match?(%Part.ToolCall{}, call) or call.tool_call_id != original.tool_call_id do
      {tool_return(original, :not_executed, "A tool hook changed call identity"), false,
       :tool_call_identity_changed}
    else
      execute_effective_call(call, ctx, state, owner, batch_ref, operation)
    end
  end

  defp execute_effective_call(call, ctx, state, owner, batch_ref, operation) do
    tool = find_tool(state, call.tool_name)

    Observability.attributes(operation, %{
      "gen_ai.tool.call.id" => Observability.label(call.tool_call_id)
    })

    if tool,
      do:
        Observability.attributes(operation, %{
          "gen_ai.tool.name" => Observability.label(tool.name)
        })

    ctx =
      put_tool_info(
        ctx,
        call.tool_name,
        call.tool_call_id,
        Map.get(state.tool_retries, call.tool_name, 0),
        max_retries(tool)
      )

    args =
      with %Tool{} <- tool,
           {:ok, args} <- decode_args(call),
           {:ok, args} <- Tool.validate_args(tool, args) do
        {:ok, args}
      else
        nil -> {:error, {:unknown_tool, call.tool_name}}
        {:error, reason} -> {:error, reason}
      end

    case args do
      {:error, reason} ->
        {tool_return(call, :validation_error, reason_msg(reason)), true, reason}

      {:ok, args} ->
        call = %{call | args: args}
        Observability.content(operation, :input, args)

        if permitted?(state, call.tool_name, call) != :allow do
          {tool_return(call, :denied, "Tool #{inspect(call.tool_name)} is not permitted."), false,
           nil}
        else
          emit(state, :tool_call_started, %{
            tool_name: call.tool_name,
            tool_call_id: call.tool_call_id,
            args: args
          })

          outcome = invoke_outcome(tool, ctx, call, args)
          {part, _, _} = outcome
          send(owner, {:exagent_tool_confirmed, batch_ref, self(), part})

          receive do
            {^batch_ref, :confirmed, id} when id == part.tool_call_id -> :ok
          end

          after_tool_outcome(outcome, state.capabilities, ctx, call, tool)
        end
    end
  end

  defp invoke_outcome(tool, ctx, call, args) do
    case invoke(tool, ctx, args) do
      {:ok, value, usage} ->
        case Tool.validate_result(tool, value) do
          {:ok, value} ->
            {%{tool_return(call, :succeeded, value) | usage: usage}, false, nil}

          {:error, reason} ->
            {%{tool_return(call, :unknown, reason_msg(reason)) | usage: usage}, false,
             {:invalid_tool_result, tool.name, reason}}
        end

      {:retry, reason} ->
        {tool_return(call, :validation_error, reason_msg(reason)), true, reason}

      {:error, %ExAgent.RunError{partial: %{usage: %Usage{} = usage}} = reason} ->
        accounted =
          Map.has_key?(reason.partial, :run_id) and
            ExecutionScope.accounted?(ctx.execution_scope, reason.partial.run_id)

        {%{
           tool_return(call, :failed, reason_msg(reason))
           | usage: if(accounted, do: nil, else: usage)
         }, false, {:tool_execution_failed, tool.name, reason}}

      {:error, reason} ->
        {tool_return(call, :failed, reason_msg(reason)), false,
         {:tool_execution_failed, tool.name, reason}}

      {:unknown, reason} ->
        {tool_return(call, :unknown, reason_msg(reason)), false,
         {:tool_execution_failed, tool.name, reason}}
    end
  end

  defp after_tool_outcome({part, retry?, error} = outcome, caps, ctx, call, tool) do
    hook_result = if error, do: {:error, error}, else: {:ok, part}

    case ExAgent.Capabilities.after_tool_execute(caps, ctx, call, hook_result) do
      {:ok, %Part.ToolReturn{} = updated}
      when updated.tool_call_id == part.tool_call_id and updated.tool_name == part.tool_name ->
        case Tool.validate_result(tool, updated.content) do
          {:ok, _} -> {%{updated | usage: part.usage, status: part.status}, retry?, error}
          {:error, reason} -> {part, false, {:tool_hook_failed, tool.name, reason}}
        end

      ^hook_result ->
        outcome

      other ->
        {part, false, {:tool_hook_failed, tool.name, other}}
    end
  rescue
    reason -> {part, false, {:tool_hook_failed, tool.name, reason}}
  catch
    kind, reason -> {part, false, {:tool_hook_failed, tool.name, {kind, reason}}}
  end

  defp tool_return(call, status, content),
    do: %Part.ToolReturn{
      tool_name: call.tool_name,
      tool_call_id: call.tool_call_id,
      status: status,
      content: content
    }

  defp find_tool(%Run{prepared_tools: tools}, name), do: Map.get(tools, name)

  # Per-tool admission control. No permissions configured => everything allowed.
  defp permitted?(state, name, call),
    do: ExecutionScope.authorize(state.execution_scope, name, call)

  defp max_retries(nil), do: 0
  defp max_retries(%Tool{max_retries: m}), do: m

  defp decode_args(%Part.ToolCall{} = call) do
    case Part.ToolCall.args_as_map(call) do
      :empty -> {:ok, %{}}
      {:ok, map} when is_map(map) -> {:ok, map}
      {:error, _} = e -> e
    end
  end

  defp invoke(tool, ctx, args) do
    res =
      try do
        if tool.takes_ctx, do: tool.call.(ctx, args), else: tool.call.(args)
      rescue
        e in ExAgent.ModelRetry -> {:retry, e.message}
        e -> {:unknown, e}
      catch
        kind, reason -> {:unknown, {kind, reason}}
      end

    case res do
      {:ok, _value, %Usage{}} = ok -> ok
      {:ok, value} -> {:ok, value, nil}
      {:error, %ExAgent.ModelRetry{message: message}} -> {:retry, message}
      {:error, _} = e -> e
      {:retry, _} = retry -> retry
      {:unknown, _} = unknown -> unknown
      %ExAgent.ModelRetry{message: message} -> {:retry, message}
      value -> {:ok, value, nil}
    end
  end

  defp reason_msg(reason) when is_binary(reason), do: reason
  defp reason_msg(reasons) when is_list(reasons), do: Jason.encode!(%{"errors" => reasons})
  defp reason_msg(reason), do: inspect(safe_reason(reason))

  # Runtime errors can carry live model configuration. Never copy their partial
  # model into a tool result sent to a provider or serialized as conversation.
  defp safe_reason(%ExAgent.RunError{reason: reason}), do: safe_reason(reason)

  defp safe_reason(%ExAgent.RequestError{} = error),
    do: %{provider: error.provider, status: error.status, reason: safe_reason(error.reason)}

  defp safe_reason(reason) when is_tuple(reason),
    do: reason |> Tuple.to_list() |> Enum.map(&safe_reason/1) |> List.to_tuple()

  defp safe_reason(reason), do: reason

  # ----- finalising --------------------------------------------------------
  defp finalize_text(text, %Run{} = state) do
    succeed(text, state)
  end

  defp retry_or_fail(%Run{} = state, error) do
    retry_or_fail(state, error, %Part.Retry{content: reason_msg(error)}, [])
  end

  defp retry_or_fail(
         %Run{} = state,
         error,
         %Part.ToolCall{tool_name: tool_name, tool_call_id: tool_call_id},
         extra_parts
       ) do
    retry = %Part.Retry{
      content: reason_msg(error),
      tool_name: tool_name,
      tool_call_id: tool_call_id
    }

    retry_or_fail(state, error, retry, extra_parts)
  end

  defp retry_or_fail(
         %Run{output_retries_used: used, agent: %{output_retries: max}} = state,
         error,
         retry,
         extra_parts
       )
       when used >= max do
    state = append_returns(state, [retry | extra_parts])
    fail(state, {:unexpected_model_behavior, {:output_retries_exhausted, error}})
  end

  defp retry_or_fail(%Run{} = state, _error, %Part.Retry{} = retry, extra_parts) do
    state = %{state | output_retries_used: state.output_retries_used + 1}

    state = append_returns(state, [retry | extra_parts])

    drive(state)
  end

  # ----- helpers -----------------------------------------------------------
  defp build_context(%Run{
         deps: deps,
         model: model,
         messages: messages,
         usage: usage,
         prompt: prompt,
         run_id: run_id,
         execution_scope: execution_scope,
         root_run_id: root_run_id,
         parent_run_id: parent_run_id,
         observability: observability,
         trace_context: trace_context,
         model_request_id: model_request_id,
         run_step: run_step,
         tool_retries: retries
       }) do
    %RunContext{
      deps: deps,
      model: model,
      prompt: prompt,
      run_id: run_id,
      execution_scope: execution_scope,
      root_run_id: root_run_id,
      parent_run_id: parent_run_id,
      observability: observability,
      trace_context: trace_context,
      model_request_id: model_request_id,
      run_step: run_step,
      retries: retries,
      messages: messages,
      usage: usage
    }
  end

  defp put_tool_info(%RunContext{} = ctx, tool_name, tool_call_id, retry, max_retries) do
    %{
      ctx
      | tool_name: tool_name,
        tool_call_id: tool_call_id,
        retry: retry,
        max_retries: max_retries
    }
  end

  defp merge_usage(%Usage{} = acc, nil), do: acc

  defp merge_usage(%Usage{} = acc, %Usage{} = resp) do
    %Usage{
      input_tokens: acc.input_tokens + (resp.input_tokens || 0),
      output_tokens: acc.output_tokens + (resp.output_tokens || 0),
      details: sum_details(acc.details, resp.details)
    }
  end

  defp sum_details(a, b) do
    # Sum per-key, but only for numeric values — some providers nest maps in the
    # usage details (e.g. prompt_tokens_details), and adding those would crash.
    # Non-numeric values keep the latest (b's) value.
    Map.merge(a, b, fn _k, x, y ->
      cond do
        is_number(x) and is_number(y) -> x + y
        is_map(x) and is_map(y) -> sum_details(x, y)
        is_number(y) -> y
        is_number(x) -> x
        true -> y
      end
    end)
  end

  defp append(messages, message), do: messages ++ [message]

  defp append_returns(state, []), do: state

  defp append_returns(state, parts) do
    state = %{
      state
      | messages:
          append(state.messages, %Request{
            parts: parts,
            run_id: state.run_id,
            timestamp: DateTime.utc_now()
          })
    }

    progress(state)
  end

  defp protect(state, fun) do
    fun.()
  rescue
    error -> fail(state, {:execution_failed, error})
  catch
    :throw, :exagent_stream_cancelled -> fail(state, :cancelled)
    kind, reason -> fail(state, {:execution_failed, {kind, reason}})
  end

  defp fail(state, reason) do
    # Resolve complete calls whose execution never began (e.g. model hook,
    # truncation, or admission failures). Incomplete responses stay separate.
    missing =
      state.messages
      |> Enum.drop(state.first_new_message_index)
      |> unresolved_calls()
      |> Enum.map(&tool_return(&1, :not_executed, "Run stopped before tool execution"))

    state = state |> append_returns(missing) |> refresh_scope()
    status = if reason == :cancelled, do: :cancelled, else: :failed
    partial = result(nil, state, status)
    notify_progress(state, partial)
    {:error, %ExAgent.RunError{reason: reason, partial: partial}}
  end

  defp unresolved_calls(messages) do
    Enum.reduce(messages, [], fn
      %Response{} = response, pending ->
        pending ++ Response.tool_calls(response)

      %Request{parts: parts}, pending ->
        Enum.reduce(parts, pending, fn
          %Part.ToolReturn{tool_call_id: id}, pending -> resolve_call(pending, id)
          %Part.Retry{tool_call_id: id}, pending -> resolve_call(pending, id)
          _, pending -> pending
        end)
    end)
  end

  defp resolve_call(pending, id) do
    case Enum.split_while(pending, &(&1.tool_call_id != id)) do
      {before, [_ | after_call]} -> before ++ after_call
      {before, []} -> before
    end
  end

  defp succeed(output, state) do
    state = refresh_scope(state)
    result = result(output, state, :succeeded)
    notify_progress(state, result)
    emit(state, :run_step_finished, %{step: state.run_step})
    {:ok, result}
  end

  defp progress(state) do
    state = refresh_scope(state)
    notify_progress(state, result(nil, state, :running))
    state
  end

  defp notify_progress(%Run{on_progress: fun}, result) when is_function(fun, 1),
    do: safe_apply(fun, result)

  defp notify_progress(_, _), do: :ok

  defp replace_request_usage(acc, _previous, nil), do: acc

  defp replace_request_usage(acc, nil, current), do: merge_usage(acc, current)

  defp replace_request_usage(acc, previous, current) do
    negative = %Usage{
      input_tokens: -(previous.input_tokens || 0),
      output_tokens: -(previous.output_tokens || 0),
      details: negate_details(previous.details)
    }

    acc |> merge_usage(negative) |> merge_usage(current)
  end

  defp negate_details(details) do
    Map.new(details, fn {key, value} ->
      {key,
       cond do
         is_number(value) -> -value
         is_map(value) -> negate_details(value)
         true -> value
       end}
    end)
  end

  defp new_id(prefix),
    do: prefix <> "_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  defp refresh_scope(%Run{execution_scope: %ExecutionScope{} = scope} = state) do
    case ExecutionScope.snapshot(scope) do
      {:ok, snapshot} ->
        %{
          state
          | usage: snapshot.usage,
            usage_status: snapshot.usage_status,
            scope_snapshot: snapshot
        }

      _ ->
        %{state | usage_status: :partial}
    end
  end

  defp refresh_scope(state), do: state

  defp result(output, %Run{} = state, status) do
    new = Enum.drop(state.messages, state.first_new_message_index)

    result = %{
      output: output,
      messages: state.messages,
      new_messages: new,
      usage: state.usage,
      run_step: state.run_step,
      # The (possibly updated) model struct, so stateful models (e.g. the
      # script-driven Test) can be threaded across runs by the runtime layer.
      model: state.model,
      run_id: state.run_id,
      root_run_id: state.root_run_id || state.run_id,
      parent_run_id: state.parent_run_id,
      model_request_id: state.model_request_id,
      status: status,
      usage_status: state.usage_status,
      pending_response: state.pending_response,
      request_count: state.admitted_requests,
      tool_calls: state.tool_calls,
      cost_cents: nil,
      cost_status: :unknown
    }

    result
    |> Map.merge(state.scope_snapshot || %{})
    |> Map.put(:usage_status, state.usage_status)
  end
end
