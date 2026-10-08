defmodule ExAgent do
  @external_resource "README.md"

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.at(1)

  alias ExAgent.{Model, ModelSettings, ModelRequestParameters, RunContext, Tool}
  alias ExAgent.Message.{Part, Request, Response, Usage}
  alias ExAgent.ExecutionScope
  alias ExAgent.Retention
  alias ExAgent.Observability.OpenTelemetry, as: Observability

  defstruct model: nil,
            instructions: [],
            output_type: :text,
            output_mode: :tool,
            tools: [],
            settings: %ModelSettings{},
            output_retries: 1,
            tool_timeout: 30_000,
            max_steps: 50,
            max_payload_bytes: 1_048_576,
            max_history_bytes: 8_388_608,
            usage_limits: nil,
            capabilities: [],
            name: nil,
            observability: nil

  @type output_type :: :text | module()
  @type t :: %__MODULE__{
          model: Model.model(),
          instructions: [Part.System.t()],
          output_type: output_type(),
          output_mode: :tool | :native,
          tools: [Tool.t()],
          settings: ModelSettings.t(),
          output_retries: non_neg_integer(),
          tool_timeout: pos_integer(),
          max_steps: pos_integer(),
          max_payload_bytes: pos_integer(),
          max_history_bytes: pos_integer(),
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

  Ecto output defaults to `output_mode: :tool`. Explicit `:native` sends a
  separate JSON schema to a model declaring native support; the actual changeset
  still validates the final object. There is no automatic fallback between modes.

  Valid tool schemas are prepared once on the reusable definition. Invalid
  schemas still fail as operational `RunError`s when running the agent; each
  run also checks that a prepared validator matches the tool's current schema.

  Retention defaults are `max_payload_bytes: 1_048_576` and
  `max_history_bytes: 8_388_608`, configurable from1 through64MiB. They measure
  uncompressed Erlang external term size after decode, not live RAM. A tool may
  already have performed its effect when its returned payload exceeds a limit:
  its outcome/identity are preserved with an explicit `payload_omitted` marker
  and a terminal RunError. Such history cannot be executed again automatically.

  `:skills` takes a list of `ExAgent.Skill`s that the model loads on demand. It
  adds a `load_skill` tool (plus `read_skill_file` and the skills' gated tools),
  an `ExAgent.Skills.Gate` before `:capabilities` when a skill has tools, and
  `ExAgent.Skills.Restore` after them; see `ExAgent.Skills`. Invalid skills or
  clashing tool names raise `ArgumentError`.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    opts = ExAgent.Skills.expand(opts)

    model =
      case Keyword.fetch!(opts, :model) do
        %_{} = m -> m
        spec -> resolve_model!(spec)
      end

    %__MODULE__{
      model: model,
      instructions: to_instructions(Keyword.get(opts, :instructions)),
      output_type: Keyword.get(opts, :output, Keyword.get(opts, :output_type, :text)),
      output_mode: Keyword.get(opts, :output_mode, :tool),
      tools: prepare_definition_tools(Keyword.get(opts, :tools, [])),
      settings: ModelSettings.new(Keyword.get(opts, :model_settings, [])),
      output_retries: Keyword.get(opts, :output_retries, 1),
      tool_timeout: Keyword.get(opts, :tool_timeout, 30_000),
      max_steps: Keyword.get(opts, :max_steps, 50),
      max_payload_bytes: Keyword.get(opts, :max_payload_bytes, 1_048_576),
      max_history_bytes: Keyword.get(opts, :max_history_bytes, 8_388_608),
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
  defp output_config(%__MODULE__{output_type: :text, output_mode: :tool}),
    do: {:text, [], true, nil}

  defp output_config(%__MODULE__{output_type: mod, output_mode: :native})
       when is_atom(mod) and mod not in [:text, nil] do
    {:native, [], true, %{json_schema: ExAgent.OutputSchema.json_schema(mod), module: mod}}
  end

  defp output_config(%__MODULE__{output_type: mod, output_mode: :tool}) when is_atom(mod) do
    tool = %Tool{
      name: @output_tool_name,
      description: "Return the final answer as structured data.",
      parameters_json_schema: ExAgent.OutputSchema.json_schema(mod),
      kind: :output,
      takes_ctx: false,
      call: nil
    }

    {:tool, [tool], false, nil}
  end

  defp output_config(_), do: raise(ArgumentError, "unsupported output mode or output type")

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
    * `:max_payload_bytes`, `:max_history_bytes` — finite overrides of the
      definition's postdecode retention bounds. Results expose `:retention`
      measurements of history and public data, excluding live model/configuration.
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
    opts = ExAgent.Continuation.Writer.bind_deadline(opts)
    state = init_state(agent, prompt, opts)

    admission =
      with :ok <- retention_input(state),
           {:ok, _} <- ExAgent.Continuation.Writer.config(opts[:continuation]),
           do: :ok

    case admission do
      :ok ->
        run_retained(state, opts)

      {:error, reason} ->
        previous = Keyword.get(opts, :message_history, [])

        previous =
          if Retention.limit?(state.max_history_bytes) and
               Retention.bytes(previous) <= state.max_history_bytes, do: previous, else: []

        fail(
          %{state | messages: previous, first_new_message_index: length(previous), prompt: nil},
          reason
        )
    end
  end

  @doc "Resume a persisted approval from an explicitly supplied trusted agent and configuration."
  def resume(agent, reference, opts \\ []) do
    opts = ExAgent.Continuation.Writer.bind_deadline(opts)
    state = init_state(agent, nil, opts)

    with {:ok, config} when not is_nil(config) <-
           ExAgent.Continuation.Writer.config(opts[:continuation]),
         true <- reference.id == config.id,
         {:ok, record} <- ExAgent.Store.load_record(config.store, :agent, config.id),
         true <-
           record["record_id"] == reference.record_id and record["revision"] == reference.revision,
         true <- record["execution"]["state"] == "ready",
         {:ok, state, frame, floor} <- ExAgent.Continuation.Frame.restore(state, record, config),
         state = %{state | continuation_frame: frame},
         {:ok, state} <- restore_children(state, record, config),
         :ok <- continuation_model_preflight(state),
         :ok <- retention_input(state) do
      state = %{state | continuation_frame: frame}

      opts =
        opts |> Keyword.put(:continuation_record, record) |> Keyword.put(:permission_floor, floor)

      run_retained(state, opts)
    else
      false -> fail(state, :continuation_conflict)
      {:error, reason} -> fail(state, reason)
      _ -> fail(state, :invalid_continuation_configuration)
    end
  end

  @doc false
  def validate_model_reconciliation(%__MODULE__{} = agent, record, config) when is_map(config) do
    initial = init_state(agent, nil, [])

    with {:ok, state, frame, _} <- ExAgent.Continuation.Frame.restore(initial, record, config),
         {:ok, data} <- ExAgent.Continuation.Frame.dump_model(state.model, config),
         true <- data === frame["model_data"],
         state = %{state | continuation_frame: frame},
         :ok <- continuation_model_preflight(state),
         {mode, outputs, allow_text, object} = output_config(state.agent),
         params = %ModelRequestParameters{
           function_tools: Map.values(state.prepared_tools),
           output_tools: outputs,
           output_mode: mode,
           output_object: object,
           allow_text_output: allow_text,
           instructions: state.agent.instructions
         },
         {:ok, state} <- prepare_request_output(%{state | params: params}),
         :ok <- check_model_requirements(state),
         :ok <- Retention.check(List.last(state.messages), state.max_payload_bytes, :response),
         :ok <- retention_input(state) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_model_reconciliation}
    end
  rescue
    _ -> {:error, :invalid_model_reconciliation}
  end

  def validate_model_reconciliation(_, _, _), do: {:error, :invalid_model_reconciliation}

  defp run_retained(state, opts) do
    agent = state.agent
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
      {:ok, %{status: :paused} = res} ->
        emit(
          %{state | run_step: res.run_step},
          :run_paused,
          Map.merge(
            %{continuation: res.continuation},
            Map.take(res, [:historical_uncertainty, :attempt_id])
          )
        )

      {:ok, %{usage: usage, run_step: steps} = res} ->
        emit(
          %{state | run_step: steps},
          :run_finished,
          Map.merge(
            %{
              output: res.output,
              usage: usage,
              steps: steps
            },
            Map.take(res, [:historical_uncertainty, :attempt_id])
          )
        )

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
    if Map.get(parent, :continuation) do
      {:error, :continuation_child_descriptor_required}
    else
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
  end

  @doc false
  def resume_composition_step(definition, reference, opts \\ []) do
    alias ExAgent.Continuation.{CompositionRestore, Writer}

    with {:ok, boundary, record, config, step, status} <-
           CompositionRestore.preflight(definition, reference, opts) do
      case boundary do
        :completed ->
          if status.output_omitted,
            do: {:error, {:composition_output_omitted, status.output_omitted}},
            else: {:ok, ExAgent.Coordination.Composition.project(definition, record, config)}

        boundary ->
          with {:ok, writer, claimed} <- Writer.claim_composition(record, config) do
            try do
              restore_composition_input(writer, claimed, config, step, status, boundary, opts)
            after
              Writer.stop(writer)
            end
          end
      end
    end
  end

  defp restore_composition_input(writer, record, config, step, status, boundary, opts) do
    alias ExAgent.Continuation.Authority
    frame = record["execution"]["progress"]["runtime"]
    root_id = frame["run_id"]
    original = frame["authority"][root_id]
    root_opts = Authority.intersect(original, original["usage"], opts[:root_options] || [])

    with {:ok, root} <- ExecutionScope.start_structural(root_id, root_opts) do
      try do
        restore_composition_step(writer, root, record, config, step, status, boundary, opts)
      after
        ExecutionScope.stop(root)
      end
    end
  end

  @doc false
  def restore_composition_step(writer, root, record, config, step, status, boundary, opts) do
    with {:ok, deadline} <- ExAgent.Continuation.Writer.attempt_deadline(writer),
         :ok <- ExAgent.Continuation.CompositionRestore.check_deadline(deadline) do
      if boundary == :structural_tree do
        prepare_composition_tree(writer, root, record, config, step, status, opts, deadline)
      else
        prepare_composition_step(
          writer,
          root,
          record,
          config,
          step,
          status,
          boundary,
          opts,
          deadline
        )
      end
    end
  end

  defp prepare_composition_tree(
         writer,
         root,
         %{
           "execution" => %{"progress" => %{"runtime" => %{"frame_version" => 10} = frame}}
         } = record,
         config,
         step,
         status,
         opts,
         deadline
       ) do
    alias ExAgent.Continuation.{CompositionRestore, Writer}

    ids =
      frame["children"]
      |> Enum.filter(fn {_, n} -> n["status"] in ~w(suspended running) end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort_by(&structural_restore_depth(frame, &1))

    prepared =
      Enum.reduce_while(ids, {:ok, %{}}, fn id, {:ok, nodes} ->
        with :ok <- CompositionRestore.check_deadline(deadline),
             {:ok, agent, prompt, node_opts, leaf_config, parent} <-
               structural_restore_host(id, frame, nodes, root, step, config, opts),
             {:ok, node} <-
               structural_restore_node(
                 id,
                 agent,
                 prompt,
                 node_opts,
                 leaf_config,
                 parent,
                 record,
                 writer,
                 deadline
               ) do
          {:cont, {:ok, Map.put(nodes, id, node)}}
        else
          error -> {:halt, error}
        end
      end)

    with {:ok, nodes} <- prepared,
         :ok <- CompositionRestore.check_deadline(deadline),
         :ok <- ExecutionScope.restore_composition_tree(root, frame),
         :ok <- CompositionRestore.check_deadline(deadline),
         :ok <- Writer.restore_nodes10(writer, root, nodes),
         :ok <- CompositionRestore.check_deadline(deadline) do
      node = nodes[status.run_id]
      run_retained(node.state, node.options)
    end
  end

  defp structural_restore_depth(frame, id) do
    if id == frame["run_id"],
      do: 0,
      else: 1 + structural_restore_depth(frame, frame["children"][id]["parent_run_id"])
  end

  @doc false
  def prepare_flow_restore(writer, root, record, config, definition, opts) do
    alias ExAgent.Continuation.{CompositionRestore, Writer}
    frame = record["execution"]["progress"]["runtime"]

    ids =
      frame["children"]
      |> Enum.filter(fn {_, n} -> n["status"] in ~w(suspended running) end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort_by(&structural_restore_depth(frame, &1))

    with :ok <- CompositionRestore.flow_admission(record, opts),
         {:ok, deadline} <- Writer.attempt_deadline(writer),
         :ok <- CompositionRestore.check_deadline(deadline),
         {:ok, nodes} <-
           Enum.reduce_while(ids, {:ok, %{}}, fn id, {:ok, nodes} ->
             branch = ExAgent.Continuation.Frame.branch_id11(frame, id)
             step = Enum.find(definition.steps, &(&1.id == branch))
             leaf_opts = Map.get(opts[:step_options] || %{}, branch, [])

             with :ok <- CompositionRestore.flow_admission(record, opts),
                  :ok <- CompositionRestore.check_deadline(deadline),
                  {:ok, agent, prompt, node_opts, leaf_config, parent} <-
                    structural_restore_host(id, frame, nodes, root, step, config, leaf_opts),
                  {:ok, node} <-
                    structural_restore_node(
                      id,
                      agent,
                      prompt,
                      node_opts,
                      leaf_config,
                      parent,
                      record,
                      writer,
                      deadline
                    ) do
               {:cont, {:ok, Map.put(nodes, id, node)}}
             else
               error -> {:halt, error}
             end
           end),
         :ok <- CompositionRestore.flow_admission(record, opts),
         :ok <- CompositionRestore.check_deadline(deadline),
         :ok <- ExecutionScope.restore_composition_tree(root, frame),
         :ok <- CompositionRestore.flow_admission(record, opts),
         :ok <- Writer.restore_nodes10(writer, root, nodes) do
      branches =
        for {id, node} <- nodes,
            frame["children"][id]["link"]["kind"] == "step",
            into: %{},
            do: {frame["children"][id]["link"]["step_id"], node}

      {:ok, branches}
    end
  end

  @doc false
  def run_flow_restored(node, opts) do
    run_retained(
      node.state,
      Keyword.merge(node.options, Keyword.take(opts, [:observability, :trace_context]))
    )
  end

  defp structural_restore_host(id, frame, nodes, root, step, config, opts) do
    node = frame["children"][id]

    case node["link"]["kind"] do
      "step" ->
        if node["link"]["step_id"] == step.id do
          leaf_config =
            Map.merge(config, Map.take(step, [:definition, :policy, :model_ref, :model_codec]))

          {:ok, step.agent, node["link"]["input"], opts, leaf_config, root}
        else
          {:error, :invalid_composition_restore}
        end

      "delegate" ->
        parent = nodes[node["parent_run_id"]].state
        tool = parent.prepared_tools[node["link"]["tool_name"]]

        with {:ok, agent, prompt, child_opts, child_config} <-
               resolve_delegate(
                 parent,
                 tool.delegation,
                 build_context(parent),
                 node["link"]["args"]
               ),
             true <-
               Enum.all?(
                 [:definition, :policy, :model_ref],
                 &(child_config[&1] === node[Atom.to_string(&1)])
               ) do
          {:ok, agent, prompt, child_options(parent, child_opts), Map.merge(config, child_config),
           parent.execution_scope}
        else
          {:error, _} = error -> error
          _ -> {:error, :continuation_definition_changed}
        end
    end
  end

  defp structural_restore_node(id, agent, prompt, opts, config, parent, record, writer, deadline) do
    alias ExAgent.Continuation.{Authority, CompositionRestore, Frame}
    root = record["execution"]["progress"]["runtime"]

    opts =
      Authority.intersect(
        root["authority"][id],
        root["children"][id]["frame"]["limits"]["usage"],
        Keyword.put(opts, :usage_limits, agent.usage_limits)
      )

    opts =
      opts
      |> Keyword.put(:logical_deadline, opts[:deadline])
      |> Keyword.put(:deadline, Authority.minimum(opts[:deadline], deadline))

    with :ok <- CompositionRestore.check_deadline(opts[:deadline]),
         initial <-
           init_state(
             agent,
             prompt,
             Keyword.drop(opts, [:run_id, :continuation, :execution_scope, :message_history])
           ),
         :ok <- CompositionRestore.check_deadline(opts[:deadline]),
         {:ok, state, leaf, floor} <- Frame.restore_composition_node(initial, record, config, id),
         state = %{state | continuation_frame: leaf},
         :ok <- CompositionRestore.check_deadline(opts[:deadline]),
         :ok <- continuation_model_preflight(state),
         :ok <- retention_input(state),
         :ok <- CompositionRestore.check_deadline(opts[:deadline]),
         opts =
           opts
           |> Keyword.put(:usage_limits, state.usage_limits)
           |> Keyword.update(:permission_floors, [floor], &(&1 ++ [floor])),
         {:ok, scope} <- ExecutionScope.join(parent, id, state.model, opts) do
      state = %{
        state
        | execution_scope: scope,
          continuation: writer,
          continuation_version: root["frame_version"],
          root_run_id: root["run_id"],
          parent_run_id: root["children"][id]["parent_run_id"],
          attempt_id: record["execution"]["attempt_id"]
      }

      {:ok, %{state: state, options: opts, config: config}}
    end
  end

  defp prepare_composition_step(
         writer,
         root,
         record,
         config,
         step,
         status,
         boundary,
         opts,
         deadline
       ) do
    alias ExAgent.Continuation.{Authority, CompositionRestore, Frame, Writer}
    frame = record["execution"]["progress"]["runtime"]
    root_id = frame["run_id"]

    opts =
      Keyword.drop(opts, [
        :root_options,
        :continuation,
        :execution_scope,
        :parent_context,
        :message_history
      ])

    opts =
      Authority.intersect(
        frame["authority"][status.run_id],
        status.frame["limits"]["usage"],
        Keyword.put(opts, :usage_limits, step.agent.usage_limits)
      )

    opts = Keyword.put(opts, :logical_deadline, opts[:deadline])

    opts =
      Keyword.put(
        opts,
        :deadline,
        Authority.minimum(opts[:deadline], deadline)
      )

    leaf_config =
      Map.merge(config, Map.take(step, [:definition, :policy, :model_ref, :model_codec]))

    initial = init_state(step.agent, status.input, opts)

    {initial, boundary} =
      case boundary do
        {:confirmed_tool_history, current, count} -> {%{initial | tool_calls: count}, current}
        _ -> {initial, boundary}
      end

    initial =
      case boundary do
        {:confirmed_output_success, entry} -> %{initial | continuation_output_success: entry}
        {:confirmed_output_retry, entry} -> %{initial | continuation_output_retry: entry}
        {:confirmed_tool_batch, selection} -> %{initial | continuation_tool_batch: selection}
        _ -> initial
      end

    with :ok <- CompositionRestore.check_deadline(opts[:deadline]),
         {:ok, state, leaf_frame, floor} <-
           Frame.restore_composition_node(initial, record, leaf_config, status.run_id),
         :ok <- CompositionRestore.check_deadline(opts[:deadline]),
         state = %{state | continuation_frame: leaf_frame},
         {:ok, state} <- prepare_restored_output_retry(state),
         :ok <- CompositionRestore.check_deadline(opts[:deadline]),
         :ok <- continuation_model_preflight(state),
         :ok <- CompositionRestore.check_deadline(opts[:deadline]),
         :ok <- retention_input(state),
         :ok <- CompositionRestore.check_deadline(opts[:deadline]),
         opts =
           opts
           |> Keyword.put(:usage_limits, state.usage_limits)
           # Keep the current singular floor; persisted permissions are an
           # additional conjunct, never a replacement for host authority.
           |> Keyword.update(:permission_floors, [floor], &(&1 ++ [floor])),
         {:ok, scope} <- ExecutionScope.join(root, state.run_id, state.model, opts) do
      try do
        with :ok <- ExecutionScope.restore_composition_tree(root, frame),
             :ok <- ExecutionScope.check(scope),
             state = %{
               state
               | execution_scope: scope,
                 parent_run_id: root_id,
                 root_run_id: root_id,
                 continuation_frame: leaf_frame
             },
             {:ok, state} <- Writer.restore_step(writer, root, state, leaf_config, opts),
             :ok <- ExecutionScope.check(scope) do
          run_retained(state, opts)
        end
      after
        ExecutionScope.finish_run(scope)
      end
    end
  end

  @doc false
  def run_composition_step(writer, definition, step_id, opts \\ []) do
    alias ExAgent.Continuation.Writer

    case Writer.step_descriptor(writer, definition, step_id) do
      {:ok, descriptor} ->
        try do
          opts =
            opts
            |> Keyword.put(:logical_deadline, opts[:deadline])
            |> Keyword.drop([
              :run_id,
              :execution_scope,
              :continuation,
              :message_history,
              :parent_context
            ])
            |> Keyword.put(:parent_context, descriptor.parent)
            |> Keyword.update(:deadline, descriptor.deadline, fn
              nil -> descriptor.deadline
              value -> min(value, descriptor.deadline)
            end)

          state = init_state(descriptor.step.agent, descriptor.input, opts)

          with :ok <- ExAgent.Continuation.CompositionRestore.check_deadline(opts[:deadline]),
               :ok <- continuation_model_preflight(state),
               :ok <- retention_input(state),
               :ok <- ExAgent.Continuation.CompositionRestore.check_deadline(opts[:deadline]),
               {:ok, state} <-
                 Writer.attach_step(
                   writer,
                   descriptor.ticket,
                   state,
                   Keyword.put(opts, :usage_limits, state.usage_limits)
                 ) do
            run_retained(state, opts)
          end
        after
          # Only this owner's still-unattached reservation can be released.
          # attach consumes it before attempting CAS, including uncertain ACKs.
          Writer.release_step(writer, descriptor.ticket)
        end

      {:completed, output} ->
        {:ok, %{status: :completed, output: output}}

      error ->
        error
    end
  end

  defp execute_scoped(
         %{
           continuation: writer,
           execution_scope: %ExecutionScope{} = scope,
           parent_run_id: parent
         } = state,
         _opts
       )
       when is_pid(writer) and not is_nil(parent) do
    try do
      state = progress(state)
      emit(state, :run_started, %{prompt: state.prompt})
      protect(state, fn -> prepare_run(state) end)
    after
      ExecutionScope.finish_run(scope)
    end
  end

  defp execute_scoped(state, opts) do
    scope_options =
      opts
      |> Keyword.take([
        :permissions,
        :approve,
        :estimate_cost,
        :deadline,
        :max_concurrent_requests,
        :permission_floor
      ])
      |> Keyword.put(:usage_limits, state.usage_limits)
      |> Keyword.put(:deadline, ExAgent.Continuation.Writer.deadline(opts))

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
          with {:ok, state} <- restore_scope(state),
               {:ok, state} <- open_continuation(state, opts) do
            try do
              state = progress(state)
              emit(state, :run_started, %{prompt: state.prompt})

              case state.continuation_error do
                nil -> protect(state, fn -> prepare_run(state) end)
                reason -> fail(state, reason)
              end
            after
              ExAgent.Continuation.Writer.stop(state.continuation)
            end
          else
            {:error, reason} -> fail(state, reason)
          end
        after
          ExecutionScope.finish_run(scope)
          if scope.parent_run_id == nil, do: ExecutionScope.stop(scope)
        end

      {:error, reason} ->
        fail(state, reason)
    end
  end

  defp restore_scope(%{continuation_frame: nil} = state), do: {:ok, state}

  defp restore_scope(state) do
    with {:ok, nodes} <- join_restored_nodes(state, state.continuation_nodes, %{}),
         :ok <-
           ExAgent.Continuation.Frame.restore_scope(
             state.execution_scope,
             state.continuation_frame
           ),
         :ok <- check_restored_batch(state),
         :ok <-
           Enum.reduce_while(nodes, :ok, fn {_, node}, :ok ->
             case check_restored_batch(node.state) do
               :ok -> {:cont, :ok}
               error -> {:halt, error}
             end
           end) do
      {:ok, %{state | continuation_nodes: nodes}}
    end
  end

  defp check_restored_batch(%{continuation_frame: %{"cursor" => "batch"}} = state),
    do: ExecutionScope.check_reserved_tools(state.execution_scope, state.model_request_id)

  defp check_restored_batch(_), do: :ok

  defp join_restored_nodes(_, pending, joined) when map_size(pending) == 0, do: {:ok, joined}

  defp join_restored_nodes(root, pending, joined) do
    case Enum.find(pending, fn {_, node} ->
           node.state.parent_run_id == root.run_id or
             Map.has_key?(joined, node.state.parent_run_id)
         end) do
      nil ->
        {:error, :invalid_continuation_tree}

      {id, node} ->
        parent =
          if node.state.parent_run_id == root.run_id,
            do: root,
            else: joined[node.state.parent_run_id].state

        with {:ok, scope} <-
               ExecutionScope.join(parent.execution_scope, id, node.state.model, node.options) do
          node = %{node | state: %{node.state | execution_scope: scope}}
          join_restored_nodes(root, Map.delete(pending, id), Map.put(joined, id, node))
        end
    end
  end

  defp restore_children(state, record, config) do
    children = Map.get(record["execution"]["progress"]["runtime"], "children", %{})

    with {:ok, nodes} <- restore_child_nodes(state, record, config, children, %{}),
         do: {:ok, %{state | continuation_nodes: nodes}}
  end

  defp restore_child_nodes(_, _, _, pending, nodes) when map_size(pending) == 0, do: {:ok, nodes}

  defp restore_child_nodes(root, record, config, pending, nodes) do
    case Enum.find(pending, fn {_, child} ->
           child["parent_run_id"] == root.run_id or Map.has_key?(nodes, child["parent_run_id"])
         end) do
      nil ->
        {:error, :invalid_continuation_tree}

      {id, child} ->
        parent =
          if child["parent_run_id"] == root.run_id,
            do: root,
            else: nodes[child["parent_run_id"]].state

        parent_config =
          if parent.run_id == root.run_id, do: config, else: nodes[parent.run_id].config

        with {:ok, %Tool{delegation: %ExAgent.Continuation.Delegation{} = descriptor}} <-
               ExAgent.Continuation.Frame.delegation_tool(
                 parent.agent.tools,
                 child["call"],
                 parent_config
               ),
             {:ok, agent, prompt, options, child_config} <-
               ExAgent.Continuation.Delegation.resolve(
                 descriptor,
                 build_context(parent),
                 child["call"]["args"]
               ),
             child_config =
               Map.merge(
                 config,
                 Map.take(child_config, [
                   :definition,
                   :policy,
                   :model_ref,
                   :model_codec,
                   :rehydrate_tools
                 ])
               ),
             options = child_options(parent, options),
             initial = init_state(agent, prompt, options),
             {:ok, restored, frame, floor} <-
               ExAgent.Continuation.Frame.restore(
                 initial,
                 ExAgent.Continuation.Frame.child_record(record, id),
                 child_config
               ),
             restored = %{
               restored
               | parent_run_id: parent.run_id,
                 root_run_id: root.run_id,
                 continuation_frame: frame
             },
             :ok <- continuation_model_preflight(restored),
             :ok <- retention_input(restored) do
          deadline =
            if child["deadline_at"],
              do:
                System.monotonic_time(:millisecond) + child["deadline_at"] -
                  System.system_time(:millisecond)

          deadline =
            Enum.reject([deadline, options[:deadline]], &is_nil/1) |> Enum.min(fn -> nil end)

          options =
            options
            |> Keyword.put(:permission_floor, floor)
            |> Keyword.put(:usage_limits, restored.usage_limits)
            |> Keyword.put(:deadline, deadline)

          node = %{state: restored, config: child_config, options: options}

          restore_child_nodes(
            root,
            record,
            config,
            Map.delete(pending, id),
            Map.put(nodes, id, node)
          )
        else
          {:error, _} = error -> error
          _ -> {:error, :continuation_delegation_changed}
        end
    end
  end

  defp child_options(parent, options) do
    options
    |> Keyword.drop([:run_id, :execution_scope, :continuation, :message_history])
    |> Keyword.put_new(:deps, parent.deps)
    |> Keyword.put(:parent_context, parent)
    |> Keyword.put(:trace_context, parent.trace_context)
    |> Keyword.put(:observability, parent.observability)
  end

  defp open_continuation(state, opts) do
    case opts[:continuation] do
      nil ->
        {:ok, state}

      config ->
        with :ok <- continuation_model_preflight(state),
             {:ok, pid, data} <-
               ExAgent.Continuation.Writer.open(state, config, opts[:continuation_record]) do
          error =
            case data do
              {:error, reason} -> reason
              _ -> nil
            end

          attempt = if is_map(data), do: data["execution"]["attempt_id"]
          {:ok, %{state | continuation: pid, continuation_error: error, attempt_id: attempt}}
        end
    end
  end

  defp continuation_model_preflight(state) do
    {mode, outputs, allow_text, object} = run_output_config(state)

    tools =
      if state.continuation_frame && state.run_step > 0,
        do: Map.values(state.prepared_tools),
        else: state.agent.tools

    params = %ModelRequestParameters{
      function_tools: tools,
      output_tools: outputs,
      output_mode: mode,
      output_object: object,
      allow_text_output: allow_text,
      instructions: state.agent.instructions
    }

    restored =
      if state.continuation_retry,
        do:
          ExAgent.Continuation.RequestData.restore(
            %{state | params: params},
            state.continuation_retry["data"]
          ),
        else: {:ok, %{state | params: params}}

    with :ok <- ExAgent.Continuation.Frame.validate_output(state.continuation_frame, params),
         {:ok, state} <- restored do
      params =
        if state.continuation_retry,
          do: %{
            state.params
            | idempotency_key: state.continuation_retry["plan"]["idempotency_key"]
          },
          else: state.params

      Model.validate_resume(
        state.model,
        state.request_messages || state.messages,
        state.settings,
        params
      )
    end
  rescue
    _ -> {:error, :invalid_continuation_configuration}
  end

  @doc "Run synchronously and return the output value directly, raising on error."
  @spec run!(t(), String.t(), keyword()) :: term()
  def run!(agent, prompt, opts \\ []) do
    case run(agent, prompt, opts) do
      {:ok, %{status: :paused}} -> raise ExAgent.UnexpectedModelBehavior, :run_paused
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

  @doc "Open a new lazy stream for a persisted continuation; the earlier paused stream stays terminal."
  def resume_stream(agent, reference, opts \\ []),
    do: ExAgent.RunStream.resume(agent, reference, opts)

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
              max_payload_bytes: 1_048_576,
              max_history_bytes: 8_388_608,
              tool_return_bytes: 1_048_576,
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
              continuation: nil,
              continuation_version: nil,
              continuation_frame: nil,
              continuation_nodes: %{},
              continuation_retry: nil,
              continuation_error: nil,
              attempt_id: nil,
              prepared_tools: %{},
              prepared_output: nil,
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
              stream_text: false,
              continuation_output_success: nil,
              continuation_output_retry: nil,
              continuation_tool_batch: nil,
              continuation_output_config: nil
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
      max_payload_bytes: Keyword.get(opts, :max_payload_bytes, agent.max_payload_bytes),
      max_history_bytes: Keyword.get(opts, :max_history_bytes, agent.max_history_bytes),
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

  defp run_output_config(%Run{continuation_output_success: %{} = entry}) do
    {:ok, config} = ExAgent.Continuation.OutputResolution.output_config(entry)
    config
  end

  defp run_output_config(%Run{continuation_output_config: config}) when not is_nil(config),
    do: config

  defp run_output_config(state), do: output_config(state.agent)

  # Selected only by the validated composition boundary, after the winning claim.
  # Cache executable HOST configuration, never reconstructed callbacks from JSON.
  defp prepare_restored_output_retry(%Run{continuation_output_retry: %{} = entry} = state) do
    {mode, tools, text, object} = config = output_config(state.agent)

    params = %ModelRequestParameters{
      output_mode: mode,
      output_tools: tools,
      allow_text_output: text,
      output_object: object
    }

    with {:ok, descriptor} <- ExAgent.Continuation.Frame.output_descriptor(params),
         true <- descriptor === entry["descriptor"],
         :ok <- ExAgent.Continuation.Frame.validate_output(state.continuation_frame, params) do
      {:ok, %{state | continuation_output_config: config}}
    else
      _ -> {:error, :continuation_output_changed}
    end
  rescue
    _ -> {:error, :invalid_continuation_configuration}
  catch
    _, _ -> {:error, :invalid_continuation_configuration}
  end

  defp prepare_restored_output_retry(state), do: {:ok, state}

  defp prepare_run(state) do
    {mode, outputs, allow_text, object} = run_output_config(state)

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
        selected? = state.continuation_frame && state.run_step > 0
        tools = if selected?, do: state.prepared_tools, else: tools

        params = %ModelRequestParameters{
          function_tools:
            if(selected?,
              do: Map.values(tools),
              else: Enum.map(state.agent.tools, &Map.fetch!(tools, &1.name))
            ),
          output_tools: outputs,
          output_mode: mode,
          output_object: object,
          allow_text_output: allow_text,
          instructions: state.agent.instructions
        }

        state = %{state | params: params, prepared_tools: tools}

        case {state.continuation_frame, state.continuation_retry} do
          {%{"cursor" => "batch"}, nil} when not is_nil(state.continuation_tool_batch) ->
            selection = state.continuation_tool_batch

            state =
              append_returns(
                %{state | tool_calls: state.tool_calls + selection.count},
                selection.parts
              )

            if selection.fatal,
              do: fail(state, selection.fatal),
              else: drive(%{state | continuation_frame: nil})

          {%{"cursor" => "response"}, nil} when not is_nil(state.continuation_output_retry) ->
            entry = state.continuation_output_retry

            {:ok, [%Request{parts: [%Part.Retry{} = retry | stubs]}]} =
              ExAgent.Message.from_json(entry["parts"])

            retry_or_fail(state, retry.content, retry, stubs)

          {%{"cursor" => "response"}, nil} when not is_nil(state.continuation_output_success) ->
            entry = state.continuation_output_success
            {:ok, [%Request{parts: parts}]} = ExAgent.Message.from_json(entry["parts"])
            succeed(entry["result"], append_returns(state, parts))

          {%{"cursor" => "request"}, %{} = retry} ->
            prepare_model_retry(state, retry)

          {%{"cursor" => cursor}, _} when cursor in ["response", "batch"] ->
            case prepare_request_output(state) do
              {:ok, state} -> handle_response(List.last(state.messages), state)
              {:error, reason} -> fail(state, reason)
            end

          _ ->
            drive(state)
        end

      {:error, reason} ->
        fail(state, reason)
    end
  end

  defp retention_input(state) do
    cond do
      not Retention.limit?(state.max_payload_bytes) or
          not Retention.limit?(state.max_history_bytes) ->
        {:error, :invalid_retention_limits}

      not Retention.executable?(state.messages) ->
        {:error, :omitted_payload_history}

      true ->
        Retention.check(state.messages, state.max_history_bytes, :input)
    end
  end

  defp prepare_model_retry(state, retry) do
    with true <- state.run_step < state.max_steps,
         :ok <- check_usage_limits(state),
         {:ok, state} <- ExAgent.Continuation.RequestData.restore(state, retry["data"]) do
      state = %{
        state
        | run_step: state.run_step + 1,
          params: %{state.params | idempotency_key: retry["plan"]["idempotency_key"]}
      }

      emit(state, :run_step_started, %{step: state.run_step})
      request_step(state)
    else
      false -> fail(state, {:max_steps_exceeded, state.max_steps})
      {:error, reason} -> fail(state, reason)
    end
  end

  defp retained_transform(transformed, confirmed, response_transform? \\ false) do
    transformed = %{
      transformed
      | max_payload_bytes: confirmed.max_payload_bytes,
        max_history_bytes: confirmed.max_history_bytes,
        tool_return_bytes: confirmed.tool_return_bytes,
        pending_response: confirmed.pending_response,
        continuation: confirmed.continuation,
        continuation_frame: confirmed.continuation_frame
    }

    prefix =
      if response_transform?, do: Enum.drop(confirmed.messages, -1), else: confirmed.messages

    with true <- Enum.take(transformed.messages, length(prefix)) == prefix,
         :ok <- Retention.check(transformed.messages, confirmed.max_history_bytes, :hook),
         :ok <-
           Retention.check(transformed.request_messages, confirmed.max_history_bytes, :projection),
         true <- Retention.executable?(transformed.messages) do
      {:ok, transformed}
    else
      false -> {:error, :invalid_canonical_history_transform}
      error -> error
    end
  end

  # ----- the loop ----------------------------------------------------------
  # Emit a loop event to the optional :on_event sink. No-op when unset, so the
  # pure one-shot path is unaffected. `state` is read for run_id/step context.
  defp emit(%Run{on_event: nil}, _type, _data), do: :ok

  defp emit(%Run{on_event: fun} = state, type, data) when is_function(fun, 1) do
    data = if state.attempt_id, do: Map.put(data, :attempt_id, state.attempt_id), else: data
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
          state = %{
            state
            | run_step: state.run_step + 1,
              params: %{state.params | idempotency_key: nil}
          }

          emit(state, :run_step_started, %{step: state.run_step})
          state = progress(state)

          protect(state, fn ->
            transformed = ExAgent.Capabilities.before_model_request(state.capabilities, state)

            case retained_transform(transformed, state) do
              {:ok, transformed} -> request_step(transformed)
              {:error, reason} -> fail(state, reason)
            end
          end)

        {:error, reason} ->
          fail(state, reason)
      end
    end)
  end

  defp request_step(state) do
    state = refresh_scope(state)

    protect(state, fn ->
      with {:ok, state} <- prepare_request_tools(state),
           {:ok, state} <- prepare_request_output(state),
           :ok <- check_model_requirements(state),
           true <-
             is_nil(state.continuation) or
               Retention.executable?(state.request_messages || state.messages),
           :ok <-
             if(state.continuation,
               do:
                 Model.validate_resume(
                   state.model,
                   state.request_messages || state.messages,
                   state.settings,
                   state.params
                 ),
               else: :ok
             ) do
        request_model(state)
      else
        {:error, reason} -> fail(state, reason)
        false -> fail(state, :omitted_payload_history)
      end
    end)
  end

  defp prepare_request_tools(state) do
    Enum.reduce_while(state.params.function_tools, {:ok, %{}}, fn tool, {:ok, tools} ->
      with %Tool{} <- tool,
           false <-
             Map.has_key?(tools, tool.name) or
               Enum.any?(state.params.output_tools, &(&1.name == tool.name)),
           :ok <- validate_callable(tool),
           {:ok, prepared} <- Tool.prepare(tool) do
        {:cont, {:ok, Map.put(tools, tool.name, prepared)}}
      else
        true -> {:halt, {:error, {:duplicate_tool_name, tool.name}}}
        {:error, reason} -> {:halt, {:error, reason}}
        _ -> {:halt, {:error, :invalid_tool_definition}}
      end
    end)
    |> case do
      {:ok, tools} ->
        params = %{
          state.params
          | function_tools: Enum.map(state.params.function_tools, &Map.fetch!(tools, &1.name))
        }

        {:ok, %{state | params: params, prepared_tools: tools}}

      error ->
        error
    end
  end

  defp validate_callable(%Tool{takes_ctx: true, call: call}) when is_function(call, 2), do: :ok
  defp validate_callable(%Tool{takes_ctx: false, call: call}) when is_function(call, 1), do: :ok
  defp validate_callable(tool), do: {:error, {:invalid_tool_callable, tool.name}}

  defp prepare_request_output(%Run{params: %{output_mode: :native}} = state) do
    case state.params do
      %{output_object: %{json_schema: schema}, output_tools: []} when is_map(schema) ->
        validator = state.prepared_output || Tool.new(name: @output_tool_name)

        case Tool.prepare(%{validator | parameters_json_schema: schema}) do
          {:ok, prepared} -> {:ok, %{state | prepared_output: prepared}}
          {:error, {:invalid_tool_schema, errors}} -> {:error, {:invalid_output_schema, errors}}
        end

      _ ->
        {:error, :invalid_output_configuration}
    end
  end

  defp prepare_request_output(state), do: {:ok, %{state | prepared_output: nil}}

  defp check_model_requirements(state) do
    tools? = state.params.function_tools != [] or state.params.output_tools != []
    native? = state.params.output_mode == :native

    case Model.profile(state.model) do
      %ExAgent.ModelProfile{supports_json_schema_output: supported}
      when native? and supported != true ->
        {:error, {:unsupported, :native_output}}

      %ExAgent.ModelProfile{supports_tools: false} when tools? ->
        {:error, {:unsupported, :tools}}

      %ExAgent.ModelProfile{supports_tools: supported} when is_boolean(supported) ->
        :ok

      _ ->
        {:error, :invalid_model_profile}
    end
  end

  defp request_model(state) do
    id =
      if state.continuation_retry,
        do: state.continuation_retry["plan"]["new_request_id"],
        else: new_id("model_request")

    admission =
      if state.continuation,
        do: :ok,
        else: ExecutionScope.admit_request(state.execution_scope, id, state.model)

    case admission do
      :ok ->
        timeout = ExecutionScope.remaining_timeout(state.execution_scope, state.settings.timeout)

        state = %{
          state
          | model_request_id: id,
            admitted_requests: state.admitted_requests + 1,
            settings: %{state.settings | timeout: timeout}
        }

        try do
          case ExAgent.Continuation.Writer.model_begin(state.continuation, state) do
            :ok ->
              perform_model_request(%{state | continuation_retry: nil, continuation_frame: nil})

            {:error, reason} ->
              fail(state, reason)
          end
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

        # A durable intent ACK confirms the journal, not current execution authority.
        # It (and observability callbacks) may have waited past the bound deadline.
        # Check without charging another admission, then shrink the original timeout.
        response =
          case ExecutionScope.check(state.execution_scope) do
            :ok ->
              timeout =
                ExecutionScope.remaining_timeout(state.execution_scope, state.settings.timeout)

              state = %{state | settings: %{state.settings | timeout: timeout}}

              if state.stream_text,
                do: drive_stream(state.model, messages, state.settings, state.params, state),
                else: request_sync(state, messages)

            {:error, reason} ->
              fail(state, reason)
          end

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
      {:ok, %Response{} = response, %_{} = model} ->
        bounded_model_response(state, response, model)

      {:error, reason} ->
        request_failed(state, reason)

      other ->
        request_failed(state, {:invalid_model_result, other})
    end
  rescue
    error -> request_failed(state, error)
  catch
    kind, reason -> request_failed(state, {kind, reason})
  end

  defp bounded_model_response(state, response, model) do
    {usage, usage_error} = Retention.usage(response.usage)

    case Retention.check(response, state.max_payload_bytes, :response) do
      :ok when is_nil(usage_error) ->
        {:ok, response, model}

      check ->
        error = usage_error || elem(check, 1)
        ExecutionScope.record_usage(state.execution_scope, state.model_request_id, usage, true)
        omitted = Retention.omit_response(response, state.max_payload_bytes)
        fail(%{state | model: model, pending_response: omitted}, error)
    end
  end

  defp accept_response(state, response, model, accounting) do
    # Release the model slot before hooks can delegate and before tools execute.
    ExecutionScope.finish_request(state.execution_scope, state.model_request_id)

    response =
      case ExecutionScope.request_snapshot(state.execution_scope, state.model_request_id) do
        {:ok, snapshot} ->
          %{
            response
            | usage: snapshot.usage,
              payload_omitted: response.payload_omitted || snapshot.usage.payload_omitted
          }

        _ ->
          response
      end

    state = %{
      state
      | model: model,
        request_messages: nil,
        pending_response: nil,
        usage: merge_usage(state.usage, response.usage),
        usage_status: if(response.usage, do: state.usage_status, else: :partial)
    }

    state = refresh_scope(state)

    with {:ok, response} <- identify_calls(response),
         :ok <- Retention.check(response, state.max_payload_bytes, :response),
         {:ok, slot} <-
           response_slots(
             state,
             state.messages,
             response,
             state.run_id,
             state.max_history_bytes,
             state.max_payload_bytes
           ) do
      state = %{state | tool_return_bytes: slot}
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
                    :ok ->
                      case ExAgent.Continuation.Writer.model_done(
                             transformed.continuation,
                             transformed
                           ) do
                        :ok -> handle_response(effective, transformed)
                        {:error, reason} -> fail(transformed, reason)
                      end

                    {:error, reason} ->
                      fail(transformed, reason)
                  end
                end)

              {:error, reason} ->
                fail(state, reason)
            end
          end)

        {:error, reason} ->
          fail(state, reason)
      end
    else
      {:error, reason} ->
        # Invalid identity cannot be repaired by executing or inventing a
        # successful history. Keep the raw response separately for diagnosis.
        fail(
          %{state | pending_response: Retention.omit_response(response, state.max_payload_bytes)},
          reason
        )
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

      with {:ok, transformed} <- retained_transform(transformed, confirmed, true),
           :ok <- Retention.check(response, confirmed.max_payload_bytes, :response),
           {:ok, slot} <-
             response_slots(
               confirmed,
               Enum.drop(transformed.messages, -1),
               response,
               confirmed.run_id,
               confirmed.max_history_bytes,
               confirmed.max_payload_bytes
             ) do
        {:ok, response, progress(%{transformed | tool_return_bytes: slot})}
      end
    else
      _ -> {:error, :invalid_model_response_transform}
    end
  end

  defp effective_response(_, _, _), do: {:error, :invalid_model_response_transform}

  defp response_slots(state, messages, response, run_id, history_limit, payload_limit) do
    if state.continuation_version in [10, 11],
      do: Retention.durable_slots(messages, response, run_id, history_limit, payload_limit),
      else: Retention.slots(messages, response, run_id, history_limit, payload_limit)
  end

  defp valid_response_part?(%Part.Text{content: text}), do: is_binary(text)
  defp valid_response_part?(%Part.Thinking{content: text}), do: is_binary(text)
  defp valid_response_part?(%Part.ToolCall{tool_name: name}), do: is_binary(name)
  defp valid_response_part?(_), do: false

  defp drive_stream(model, messages, settings, params, state) do
    on_delta = deps_on_text_delta(state.deps)
    on_tool_delta = deps_on_tool_call_delta(state.deps)
    params = if on_tool_delta, do: %{params | tool_call_deltas: true}, else: params

    initial = %{
      text: [],
      thinking: [],
      usage: nil,
      scope_snapshot: state.scope_snapshot,
      bytes: 0,
      chunks: 0
    }

    outcome =
      model
      |> Model.request_stream(messages, settings, params)
      |> Enum.reduce_while(initial, fn
        {:text_delta, chunk}, acc when is_binary(chunk) ->
          case stream_chunk(state, acc, chunk) do
            {:error, reason} ->
              {:halt, fail(stream_partial(state, acc), reason)}

            :ok ->
              acc = %{acc | text: [chunk | acc.text]}
              acc = %{acc | bytes: acc.bytes + byte_size(chunk), chunks: acc.chunks + 1}
              acc = stream_progress(state, acc)
              if on_delta, do: safe_apply(on_delta, chunk)

              try do
                emit(state, :text_delta, %{text: chunk})
                {:cont, acc}
              catch
                :throw, :exagent_stream_cancelled ->
                  {:halt, fail(stream_partial(state, acc), :cancelled)}
              end
          end

        # Argument previews never enter the partial response; the terminal
        # response carries the authoritative tool calls.
        {:tool_call_delta, %{} = delta}, acc ->
          if on_tool_delta, do: safe_apply(on_tool_delta, delta)
          {:cont, acc}

        {:usage, %Usage{} = usage}, acc ->
          {usage, error} = Retention.usage(usage)
          acc = %{acc | usage: usage}
          ExecutionScope.record_usage(state.execution_scope, state.model_request_id, usage)
          acc = stream_progress(state, acc)
          if error, do: {:halt, fail(stream_partial(state, acc), error)}, else: {:cont, acc}

        {:thinking_delta, chunk}, acc when is_binary(chunk) ->
          case stream_chunk(state, acc, chunk) do
            {:error, reason} ->
              {:halt, fail(stream_partial(state, acc), reason)}

            :ok ->
              acc = %{acc | thinking: [chunk | acc.thinking]}
              acc = %{acc | bytes: acc.bytes + byte_size(chunk), chunks: acc.chunks + 1}
              acc = stream_progress(state, acc)
              emit(state, :thinking_delta, %{text: chunk})
              {:cont, acc}
          end

        {:response, %Response{} = resp, final_model}, acc ->
          terminal =
            case bounded_model_response(state, resp, final_model) do
              {:ok, resp, final_model} ->
                {:stream_response, resp, final_model, acc.scope_snapshot, true}

              error ->
                error
            end

          {:halt, terminal}

        {:error, reason}, acc ->
          {:halt, request_failed(stream_partial(state, acc), reason)}
      end)

    case outcome do
      %{} = acc -> request_failed(stream_partial(state, acc), :incomplete_stream)
      terminal -> terminal
    end
  end

  defp stream_chunk(state, acc, chunk) do
    limit = min(state.max_payload_bytes, 1_048_576)

    cond do
      byte_size(chunk) > 65_536 ->
        {:error, Retention.error(:stream, byte_size(chunk), 65_536)}

      acc.bytes + byte_size(chunk) > limit ->
        {:error, Retention.error(:stream, acc.bytes + byte_size(chunk), limit)}

      acc.chunks >= 4096 ->
        {:error, Retention.error(:stream, acc.chunks + 1, 4096)}

      true ->
        :ok
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
        raw = reason.partial_response
        {bounded_usage, _} = Retention.usage(raw.usage)

        response =
          if Retention.check(raw, state.max_payload_bytes, :response) == :ok,
            do: %{raw | usage: bounded_usage},
            else: Retention.omit_response(raw, state.max_payload_bytes)

        previous = if state.pending_response, do: state.pending_response.usage, else: nil
        usage = replace_request_usage(state.usage, previous, response.usage)
        %{state | pending_response: response, usage: usage}
      else
        state
      end

    record_failed_request(state)

    reason =
      if reason.partial_response,
        do: %{reason | partial_response: state.pending_response},
        else: reason

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

  defp deps_on_tool_call_delta(%{on_tool_call_delta: fun}) when is_function(fun, 1), do: fun
  defp deps_on_tool_call_delta(_), do: nil

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

      response.finish_reason in [:unknown, :incomplete, :error] ->
        fail(state, {:incomplete_model_response, response.finish_reason})

      tool_calls != [] ->
        handle_tool_calls(tool_calls, state)

      state.params.output_mode == :native ->
        finalize_native(text, state)

      state.params.allow_text_output and text != "" ->
        finalize_text(text, state)

      true ->
        retry_or_fail(state, actionable_hint(state))
    end
  end

  defp actionable_hint(%Run{params: %{output_tools: [_ | _]}}),
    do: "Please call the #{@output_tool_name} tool to return your answer."

  defp actionable_hint(%Run{}), do: "Please respond."

  defp finalize_native(text, state) do
    validation =
      with {:ok, data} when is_map(data) <- Jason.decode(text),
           {:ok, ^data} <- Tool.validate_args(state.prepared_output, data) do
        ExAgent.OutputSchema.validate(state.agent.output_type, data)
      else
        _ ->
          {:error, "Return a JSON object matching the output schema, without fences or repair."}
      end

    case validation do
      {:ok, data} -> succeed(data, state)
      {:error, errors} -> retry_or_fail(state, errors)
    end
  end

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
            {parts, controls, state} = execute_function_tools(fn_calls, state)

            {parts, checkpoint_error} =
              ExAgent.Continuation.Writer.settle(state.continuation, state, parts)

            inputs =
              Enum.zip(parts, controls)
              |> Enum.map(fn {part, {retry, error}} ->
                {part.tool_name, part.status, retry, error}
              end)

            limits = ExAgent.Continuation.ToolEvidence.batch(state)["limits"]

            {retries, error} =
              ExAgent.Continuation.ToolEvidence.reduce(inputs, state.tool_retries, limits)

            resolution =
              ExAgent.Continuation.Writer.tool_resolution(
                state.continuation,
                state,
                parts,
                controls,
                checkpoint_error
              )

            resolution_error =
              case resolution do
                :ok -> nil
                {:error, reason} -> reason
              end

            error = error || checkpoint_error || resolution_error

            state =
              Enum.reduce(parts, state, fn part, st ->
                %{st | usage: merge_usage(st.usage, part.usage)}
              end)

            state = %{
              state
              | tool_calls: state.tool_calls + length(fn_calls),
                tool_retries: retries
            }

            cond do
              error ->
                fail(append_returns(state, Enum.reject(parts, &(&1.status == :pending))), error)

              Enum.any?(parts, &(&1.status == :pending)) ->
                pause_run(state, parts)

              true ->
                case consume_tool_batch(state) do
                  :ok ->
                    state = append_returns(%{state | continuation_frame: nil}, parts)
                    drive(state)

                  {:error, reason} ->
                    fail(state, reason)
                end
            end

          {:error, reason} ->
            parts = Enum.map(fn_calls, &tool_return(&1, :not_executed, reason_msg(reason)))
            fail(append_returns(state, parts), reason)
        end
    end
  end

  defp check_tool_calls_limit(%{continuation_frame: %{"cursor" => "batch"}} = state, _),
    do: ExecutionScope.check_reserved_tools(state.execution_scope, state.model_request_id)

  defp check_tool_calls_limit(state, incoming) do
    if state.continuation,
      do: ExAgent.Continuation.Writer.batch(state.continuation, state),
      else: ExecutionScope.admit_tools(state.execution_scope, state.model_request_id, incoming)
  end

  defp consume_tool_batch(%Run{continuation_version: durable_version} = state)
       when durable_version in [10, 11],
       do: ExAgent.Continuation.Writer.consume10(state.continuation, state, "batch_consume")

  defp consume_tool_batch(_), do: :ok

  defp pause_run(state, parts) do
    state = refresh_scope(state)

    case ExAgent.Continuation.Writer.pause(state.continuation, state, parts) do
      {:ok, reference} ->
        reference = Map.put(reference, :attempt_id, state.attempt_id)
        paused = result(nil, state, :paused) |> Map.put(:continuation, reference)
        notify_progress(state, paused)

        if is_nil(state.parent_run_id),
          do: emit(state, :approval_requested, %{continuation: reference})

        {:ok, paused}

      {:error, reason} ->
        fail(state, reason)
    end
  end

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

      case ExAgent.Continuation.Writer.output_resolution(
             state.continuation,
             state,
             "succeeded",
             parts,
             data
           ) do
        :ok -> succeed(data, append_returns(state, parts))
        {:error, reason} -> fail(state, reason)
      end
    else
      {:error, errors} ->
        retry = %Part.Retry{
          content: reason_msg(errors),
          tool_name: call.tool_name,
          tool_call_id: id
        }

        stubs = Enum.map(siblings, &stub_return/1)

        case ExAgent.Continuation.Writer.output_resolution(
               state.continuation,
               state,
               "retry",
               [retry | stubs],
               nil
             ) do
          :ok -> retry_or_fail(state, errors, retry, stubs)
          {:error, reason} -> fail(state, reason)
        end
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

          if state.continuation_version not in [10, 11],
            do: ExecutionScope.watch_worker(state.execution_scope)

          results =
            ExAgent.Continuation.Worker.run(state, :producer, nil, fn ->
              try do
                Task.async_stream(
                  calls,
                  fn call ->
                    ExAgent.Continuation.Worker.run(state, :tool, call.tool_call_id, fn ->
                      start = System.monotonic_time()

                      outcome =
                        try do
                          watched =
                            if state.continuation_version in [10, 11],
                              do: {:ok, nil},
                              else: ExecutionScope.watch_worker(state.execution_scope)

                          case watched do
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
                                  ctx = %{
                                    base_ctx
                                    | trace_context: Observability.context(operation)
                                  }

                                  outcome =
                                    run_tool_raw(call, ctx, state, owner, batch_ref, operation)

                                  {part, _, _} = outcome

                                  if part.status == :succeeded,
                                    do: Observability.content(operation, :output, part.content)

                                  outcome
                                end
                              )

                            {:error, reason} ->
                              {tool_return(call, :not_executed, reason_msg(reason)), false,
                               reason}
                          end
                        catch
                          kind, reason ->
                            {tool_return(call, :unknown, reason_msg(reason)), false,
                             {:tool_execution_failed, call.tool_name, {kind, reason}}}
                        end

                      {Retention.tool_outcome(outcome, state.tool_return_bytes),
                       System.monotonic_time() - start}
                    end)
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
            end)

          send(owner, {:exagent_batch, batch_ref, results})
        end,
        [:monitor]
      )

    watch_batch_owner(owner, producer)

    {results, confirmed, state} =
      try do
        {results, confirmed, state, down?} =
          await_tool_batch(batch_ref, monitor, calls, state, %{})

        if state.continuation_version in [10, 11] do
          unless down? do
            receive do
              {:DOWN, ^monitor, :process, ^producer, _} -> :ok
            end
          end

          case ExAgent.Continuation.Writer.drain_node(state.continuation, state.run_id) do
            :ok -> :ok
            {:error, reason} -> throw({:exagent_retention, state, reason})
          end
        end

        {results, confirmed, state}
      after
        Process.unlink(producer)
        if Process.alive?(producer), do: Process.exit(producer, :kill)
        Process.demonitor(monitor, [:flush])
      end

    {parts, controls} =
      Enum.reduce(results, {[], []}, fn {task_result, call}, {parts, controls} ->
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

        {parts ++ [part], controls ++ [{retry?, error}]}
      end)

    {parts, controls, state}
  end

  defp await_tool_batch(ref, monitor, calls, state, confirmed) do
    receive do
      {:exagent_tool_confirmed, ^ref, task, part, _effect_attempt, observed_usage} ->
        persistence =
          ExAgent.Continuation.Writer.observed_outcome(
            state.continuation,
            state,
            part,
            observed_usage
          )

        {part, persistence} =
          case persistence do
            {:omitted, retained, reason} -> {retained, {:error, reason}}
            other -> {part, other}
          end

        confirmed = Map.put(confirmed, part.tool_call_id, part)
        state = batch_progress(state, calls, confirmed)
        send(task, {ref, :confirmed, part.tool_call_id, part, persistence})
        await_tool_batch(ref, monitor, calls, state, confirmed)

      {:exagent_batch, ^ref, results} ->
        {results, confirmed, state, false}

      {:DOWN, ^monitor, :process, _, reason} ->
        {Enum.map(calls, &{{:exit, reason}, &1}), confirmed, state, true}
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

  defp run_tool_raw(
         original,
         ctx,
         %Run{continuation_version: durable_version} = state,
         _owner,
         _batch_ref,
         operation
       )
       when durable_version in [10, 11], do: run_tool10(original, ctx, state, operation)

  defp run_tool_raw(original, ctx, state, owner, batch_ref, operation) do
    case ExAgent.Continuation.Writer.saved(
           state.continuation,
           state.run_id,
           original.tool_call_id
         ) do
      %Part.ToolReturn{} = part ->
        {part, false, nil}

      nil ->
        run_unsaved_tool(original, ctx, state, owner, batch_ref, operation)

      {:error, reason} ->
        {tool_return(original, :not_executed, reason_msg(reason)), false, reason}
    end
  end

  defp run_tool10(original, ctx, state, operation) do
    alias ExAgent.Continuation.Writer

    with {:ok, phase} <- Writer.call10(state.continuation, state, original.tool_call_id) do
      cond do
        phase["state"] == "settled" ->
          decode_outcome10(phase["result"], phase["control"])

        phase["state"] in ["preparing", "wrapping", "blocked"] ->
          {tool_return(original, :unknown, "Unconfirmed callback control"), false,
           :execution_uncertain}

        phase["raw"] ->
          wrap_tool10(original, ctx, state, phase)

        phase["state"] == "child" ->
          execute_tool10(original, ctx, state, operation, phase["binding"]["args"])

        phase["state"] in ["prepared", "approval"] ->
          execute_tool10(original, ctx, state, operation, phase["binding"]["args"])

        phase["state"] == "queued" ->
          with :ok <-
                 Writer.phase10(state.continuation, state, original.tool_call_id, "call_prepare"),
               :ok <- check_callback10(state) do
            case before_tool_call(state.capabilities, ctx, original) do
              {:ok, effective} -> prepare_tool10(original, effective, ctx, state, operation)
              {:error, error} -> reject_tool10(original, state, "before_hook_error", error)
            end
          else
            {:error, reason} ->
              {tool_return(original, :unknown, reason_msg(reason)), false, reason}
          end
      end
    else
      {:error, reason} -> {tool_return(original, :unknown, reason_msg(reason)), false, reason}
    end
  end

  defp prepare_tool10(original, effective, ctx, state, operation) do
    tool = find_tool(state, effective.tool_name)

    cond do
      is_nil(tool) ->
        reject_tool10(original, state, "unknown_tool", {:unknown_tool, effective.tool_name})

      true ->
        case decode_args(effective) do
          {:error, reason} ->
            reject_tool10(original, state, "malformed_args", reason)

          {:ok, args} ->
            case Retention.check(effective, state.max_payload_bytes, :hook) do
              {:error, reason} ->
                reject_tool10(original, state, "preparation_retention", reason)

              :ok ->
                case Tool.validate_args(tool, args) do
                  {:error, reason} ->
                    reject_tool10(original, state, "args_validation_error", reason)

                  {:ok, args} ->
                    with {:ok, args} <- Tool.JSON.normalize(args),
                         :ok <-
                           ExAgent.Continuation.Writer.phase10(
                             state.continuation,
                             state,
                             original.tool_call_id,
                             "call_prepared",
                             %{"args" => args}
                           ) do
                      execute_tool10(original, ctx, state, operation, args)
                    else
                      {:error, reason} ->
                        {tool_return(original, :unknown, reason_msg(reason)), false, reason}
                    end
                end
            end
        end
    end
  end

  defp reject_tool10(call, state, reason, error) do
    alias ExAgent.Continuation.{ToolEvidence, Writer}

    with :ok <-
           Writer.phase10(state.continuation, state, call.tool_call_id, "call_reject", %{
             "reason" => reason,
             "error" => ToolEvidence.error(error)
           }),
         {:ok, phase} <- Writer.call10(state.continuation, state, call.tool_call_id) do
      decode_outcome10(phase["result"], phase["control"])
    else
      {:error, reason} -> {tool_return(call, :unknown, reason_msg(reason)), false, reason}
    end
  end

  defp execute_tool10(original, ctx, state, operation, args) do
    alias ExAgent.Continuation.{ToolEvidence, Writer}
    tool = find_tool(state, original.tool_name)
    call = %{original | args: args}

    ctx =
      put_tool_info(
        ctx,
        call.tool_name,
        call.tool_call_id,
        Map.get(state.tool_retries, call.tool_name, 0),
        max_retries(tool)
      )

    permission = Writer.admit(state.continuation, state, call, tool)

    cond do
      permission == :pending ->
        {tool_return(call, :pending, nil), false, nil}

      permission == :deny ->
        reject_tool10(original, state, "permission_denied", nil)

      permission != :allow ->
        {tool_return(call, :unknown, reason_msg(permission)), false, permission}

      true ->
        with :ok <- check_callback10(state) do
          Observability.content(operation, :input, args)

          emit(state, :tool_call_started, %{
            tool_name: call.tool_name,
            tool_call_id: call.tool_call_id,
            args: args
          })

          outcome =
            if tool.delegation,
              do: delegated_outcome(tool, ctx, state, call),
              else: invoke_outcome(tool, ctx, call, args)

          {part, retry, error} = Retention.durable_tool_outcome(outcome, state.tool_return_bytes)

          if part.status == :pending do
            {part, retry, error}
          else
            persisted =
              if tool.delegation do
                :ok
              else
                with {:ok, observation, accounting} <-
                       ExecutionScope.observe_tool(
                         state.execution_scope,
                         {state.model_request_id, call.tool_call_id},
                         elem(outcome, 0).usage
                       ) do
                  control_error =
                    if match?({:error, _}, accounting),
                      do: :invalid_tool_accounting,
                      else: error

                  data = %{
                    "result" => ExAgent.Continuation.Outcome.encode(%{part | usage: nil}),
                    "control" => %{
                      "retry" => if(match?({:error, _}, accounting), do: false, else: retry),
                      "error" => ToolEvidence.error(control_error)
                    }
                  }

                  data =
                    cond do
                      observation["application"]["status"] == "rejected" ->
                        Map.put(data, "observation", observation)

                      elem(outcome, 0).usage ->
                        Map.put(data, "usage", Usage.to_map(elem(outcome, 0).usage))

                      true ->
                        data
                    end

                  Writer.phase10(state.continuation, state, call.tool_call_id, "outcome", data)
                end
              end

            with :ok <- persisted,
                 {:ok, phase} <- Writer.call10(state.continuation, state, call.tool_call_id) do
              cond do
                is_map(phase["raw"]) and phase["raw"]["control"]["retry"] == false and
                    not is_nil(phase["raw"]["control"]["error"]) ->
                  decode_outcome10(phase["raw"]["result"], phase["raw"]["control"])

                is_map(phase["raw"]) ->
                  wrap_tool10(call, ctx, state, phase)

                true ->
                  {part, false, error || :execution_uncertain}
              end
            else
              {:error, reason} -> {part, false, reason}
              other -> {part, false, other}
            end
          end
        else
          {:error, reason} -> {tool_return(call, :unknown, reason_msg(reason)), false, reason}
        end
    end
  end

  defp wrap_tool10(call, ctx, state, phase) do
    alias ExAgent.Continuation.{ToolEvidence, Writer}
    raw = decode_outcome10(phase["raw"]["result"], phase["raw"]["control"])

    with :ok <- Writer.phase10(state.continuation, state, call.tool_call_id, "call_wrap"),
         :ok <- check_callback10(state) do
      {part, retry, error} =
        case Retention.durable_tool_outcome(raw, state.tool_return_bytes) do
          {_, _, {:retention_limit_exceeded, _}} = rejected ->
            rejected

          _ ->
            raw
            |> after_tool_outcome(state.capabilities, ctx, call, find_tool(state, call.tool_name))
            |> Retention.durable_tool_outcome(state.tool_return_bytes)
        end

      data = %{
        "result" => ExAgent.Continuation.Outcome.encode(%{part | usage: nil}),
        "control" => %{"retry" => retry, "error" => ToolEvidence.error(error)}
      }

      case Writer.phase10(state.continuation, state, call.tool_call_id, "call_settle", data) do
        :ok -> {part, retry, error}
        {:error, reason} -> {part, false, reason}
      end
    else
      {:error, reason} -> {elem(raw, 0), false, reason}
    end
  end

  defp decode_outcome10(bytes, control) do
    {:ok, [%Request{parts: [part]}]} = ExAgent.Message.from_json(bytes)
    {part, control["retry"], control["error"]}
  end

  defp check_callback10(state) do
    with :ok <- ExecutionScope.check(state.execution_scope),
         {:ok, deadline} <- ExAgent.Continuation.Writer.attempt_deadline(state.continuation),
         do: ExAgent.Continuation.CompositionRestore.check_deadline(deadline)
  end

  defp run_unsaved_tool(original, ctx, state, owner, batch_ref, operation) do
    ctx =
      put_tool_info(
        ctx,
        original.tool_name,
        original.tool_call_id,
        Map.get(state.tool_retries, original.tool_name, 0),
        max_retries(find_tool(state, original.tool_name))
      )

    case before_tool_call(state.capabilities, ctx, original) do
      {:ok, call} ->
        execute_effective_call(call, ctx, state, owner, batch_ref, operation)

      {:error, reason} ->
        {tool_return(original, :not_executed, reason_msg(reason)), false, reason}
    end
  end

  defp before_tool_call(caps, ctx, original) do
    call = ExAgent.Capabilities.before_tool_execute(caps, ctx, original)

    if match?(%Part.ToolCall{}, call) and call.tool_call_id == original.tool_call_id and
         call.tool_name == original.tool_name and call.kind == original.kind and
         call.metadata == original.metadata,
       do: {:ok, call},
       else: {:error, :tool_call_identity_changed}
  rescue
    reason -> {:error, {:tool_hook_failed, original.tool_name, reason}}
  catch
    kind, reason -> {:error, {:tool_hook_failed, original.tool_name, {kind, reason}}}
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
           :ok <- Retention.check(call, state.max_payload_bytes, :hook),
           {:ok, args} <- Tool.validate_args(tool, args) do
        {:ok, args}
      else
        nil -> {:error, {:unknown_tool, call.tool_name}}
        {:error, reason} -> {:error, reason}
      end

    case args do
      {:error, {:retention_limit_exceeded, _} = reason} ->
        {tool_return(call, :not_executed, reason_msg(reason)), false, reason}

      {:error, reason} ->
        {tool_return(call, :validation_error, reason_msg(reason)), true, reason}

      {:ok, args} ->
        call = %{call | args: args}
        Observability.content(operation, :input, args)

        permission =
          if state.continuation,
            do: ExAgent.Continuation.Writer.admit(state.continuation, state, call, tool),
            else: permitted?(state, call.tool_name, call)

        {permission, ctx, effect_attempt} =
          case permission do
            {:allow, key, id} -> {:allow, %{ctx | idempotency_key: key}, id}
            other -> {other, ctx, nil}
          end

        cond do
          permission == :pending ->
            {tool_return(call, :pending, nil), false, nil}

          match?({:error, _}, permission) ->
            {tool_return(call, :not_executed, reason_msg(elem(permission, 1))), false,
             elem(permission, 1)}

          permission != :allow ->
            {tool_return(call, :denied, "Tool #{inspect(call.tool_name)} is not permitted."),
             false, nil}

          true ->
            emit(state, :tool_call_started, %{
              tool_name: call.tool_name,
              tool_call_id: call.tool_call_id,
              args: args
            })

            outcome =
              if state.continuation && tool.delegation,
                do: delegated_outcome(tool, ctx, state, call),
                else: invoke_outcome(tool, ctx, call, args)

            observed_usage = elem(outcome, 0).usage
            outcome = Retention.tool_outcome(outcome, state.tool_return_bytes)
            {part, _, _} = outcome

            if part.status == :pending do
              outcome
            else
              send(
                owner,
                {:exagent_tool_confirmed, batch_ref, self(), part, effect_attempt, observed_usage}
              )

              {part, persistence} =
                receive do
                  {^batch_ref, :confirmed, id, retained, result} when id == part.tool_call_id ->
                    {retained, result}
                end

              outcome = put_elem(outcome, 0, part)

              cond do
                match?({:error, _}, persistence) ->
                  {part, false, elem(persistence, 1)}

                part.payload_omitted || (part.usage && part.usage.payload_omitted) ->
                  outcome

                true ->
                  outcome
                  |> after_tool_outcome(state.capabilities, ctx, call, tool)
                  |> Retention.tool_outcome(state.tool_return_bytes)
              end
            end
        end
    end
  end

  defp delegated_outcome(tool, ctx, parent, call) do
    writer = parent.continuation

    result =
      case ExAgent.Continuation.Writer.child(writer, parent, call) do
        {:completed, value} ->
          {:ok, %{status: :succeeded, output: value}}

        {:resume, node} ->
          observe_durable_delegation(parent, ctx, fn trace ->
            state = %{node.state | continuation: writer, attempt_id: parent.attempt_id}
            run_retained(state, Keyword.put(node.options, :trace_context, trace))
          end)

        nil ->
          observe_durable_delegation(parent, ctx, fn trace ->
            with {:ok, agent, prompt, options, config} <-
                   resolve_delegate(parent, tool.delegation, ctx, call.args),
                 options = child_options(%{parent | trace_context: trace}, options),
                 state = init_state(agent, prompt, options),
                 :ok <- continuation_model_preflight(state),
                 :ok <- retention_input(state),
                 scope_options = Keyword.put(options, :usage_limits, state.usage_limits),
                 {:ok, state} <-
                   ExAgent.Continuation.Writer.attach(
                     writer,
                     parent,
                     state,
                     call,
                     config,
                     scope_options
                   ) do
              run_retained(state, options)
            end
          end)

        {:error, _} = error ->
          error
      end

    case result do
      {:ok, %{status: :paused}} ->
        {tool_return(call, :pending, nil), false, nil}

      {:ok, %{status: :succeeded, output: value}} ->
        case Tool.validate_result(tool, value) do
          {:ok, value} ->
            {tool_return(call, :succeeded, value), false, nil}

          {:error, reason} ->
            {tool_return(call, :unknown, reason_msg(reason)), false,
             {:invalid_tool_result, tool.name, reason}}
        end

      {:error, reason} ->
        {tool_return(call, :failed, reason_msg(reason)), false, reason}
    end
  end

  defp observe_durable_delegation(parent, ctx, execute) do
    Observability.around(
      parent.observability,
      :delegation,
      Observability.ids(ctx),
      ctx.trace_context,
      fn operation -> execute.(Observability.context(operation)) end
    )
  end

  defp resolve_delegate(
         %Run{continuation_version: durable_version} = parent,
         descriptor,
         ctx,
         args
       )
       when durable_version in [10, 11] do
    with {:ok, entry} <-
           ExAgent.Continuation.Writer.delegate_definition(parent.continuation, descriptor),
         :ok <- check_callback10(parent),
         do: ExAgent.Continuation.Delegation.resolve10(descriptor, entry, ctx, args)
  end

  defp resolve_delegate(_, descriptor, ctx, args),
    do: ExAgent.Continuation.Delegation.resolve(descriptor, ctx, args)

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

  defp reason_msg(reason), do: bounded_reason_msg(Retention.reason(reason))

  defp bounded_reason_msg(reason) when is_binary(reason), do: reason

  defp bounded_reason_msg(reasons) when is_list(reasons),
    do: Jason.encode!(%{"errors" => reasons})

  defp bounded_reason_msg(reason), do: inspect(safe_reason(reason))

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

    case if(state.continuation_version in [10, 11],
           do: ExAgent.Continuation.Writer.consume10(state.continuation, state, "output_consume"),
           else: :ok
         ) do
      :ok -> drive(state)
      {:error, reason} -> fail(state, reason)
    end
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
         continuation: continuation,
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
      continuation: continuation,
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

  defp merge_usage(%Usage{} = acc, %Usage{} = resp), do: Usage.add(acc, resp)

  defp append(messages, message), do: messages ++ [message]

  defp append_returns(state, []), do: state

  defp append_returns(state, parts) do
    request =
      if state.continuation_version in [10, 11],
        # Frame10 consumes the canonical attested request, including its absent
        # timestamp/run ID. A fresh live timestamp would change RequestData2's
        # history relative to the just-acknowledged journal.
        do: %Request{parts: parts},
        else: %Request{parts: parts, run_id: state.run_id, timestamp: DateTime.utc_now()}

    updated = %{
      state
      | messages: append(state.messages, request)
    }

    case Retention.check(updated.messages, state.max_history_bytes, :history) do
      :ok -> progress(%{updated | continuation_output_retry: nil, continuation_tool_batch: nil})
      {:error, reason} -> throw({:exagent_retention, state, reason})
    end
  end

  defp protect(state, fun) do
    fun.()
  rescue
    error -> fail(state, {:execution_failed, error})
  catch
    :throw, {:exagent_retention, confirmed, reason} -> fail(confirmed, reason)
    :throw, :exagent_stream_cancelled -> fail(state, :cancelled)
    kind, reason -> fail(state, {:execution_failed, {kind, reason}})
  end

  defp fail(state, reason) do
    reason = Retention.reason(reason)

    if state.continuation_version in [10, 11],
      do: ExAgent.Continuation.Writer.failed(state.continuation, state)

    # Resolve complete calls whose execution never began (e.g. model hook,
    # truncation, or admission failures). Incomplete responses stay separate.
    missing =
      if state.continuation_version in [10, 11] || state.continuation_output_success ||
           state.continuation_output_retry ||
           state.continuation_tool_batch do
        # These calls already have immutable attested returns. If retention
        # prevents appending them, preserve the confirmed history in the error;
        # do not fabricate contradictory stubs (or overflow again in fail/2).
        []
      else
        state.messages
        |> Enum.drop(state.first_new_message_index)
        |> unresolved_calls()
        |> Enum.map(&tool_return(&1, :not_executed, "Run stopped before tool execution"))
      end

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
    case Retention.check(output, state.max_payload_bytes, :output) do
      {:error, reason} -> fail(state, reason)
      :ok -> retained_success(output, state)
    end
  end

  defp retained_success(output, state) do
    state = refresh_scope(state)

    case ExAgent.Continuation.Writer.finish(state.continuation, state, output) do
      :ok -> confirmed_success(output, state)
      {:error, reason} -> fail(state, reason)
    end
  end

  defp confirmed_success(output, state) do
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

  defp notify_progress(%Run{on_progress: fun}, result) when is_function(fun, 1) do
    fun.(result)
  rescue
    _ -> :ok
  catch
    :throw, :exagent_stream_cancelled -> throw(:exagent_stream_cancelled)
    _, _ -> :ok
  end

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
        snapshot =
          case state.scope_snapshot do
            %{usage: usage} = snapshot ->
              %{
                snapshot
                | usage: Usage.partial(usage),
                  usage_status: :partial,
                  cost_cents: nil,
                  cost_status: :unknown
              }

            other ->
              other
          end

        %{
          state
          | usage_status: :partial,
            usage: Usage.partial(state.usage),
            scope_snapshot: snapshot
        }
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
    |> continuation_result(state)
    |> retention_metrics(state)
  end

  defp continuation_result(result, %{continuation: nil}), do: result

  defp continuation_result(result, state) do
    result = Map.put(result, :attempt_id, state.attempt_id)

    result =
      case ExAgent.Continuation.Writer.reference(state.continuation) do
        %{} = reference ->
          Map.put(result, :continuation, Map.put(reference, :attempt_id, state.attempt_id))

        _ ->
          result
      end

    case ExAgent.Continuation.Writer.pending(state.continuation) do
      %{token: token, max_bytes: limit, record_bytes: rb, record_json_bytes: jb} = metadata ->
        result
        |> Map.put(:continuation_checkpoint, token)
        |> Map.put(:max_checkpoint_bytes, limit)
        |> Map.put(:continuation_retention, %{record_bytes: rb, record_json_bytes: jb})
        |> Map.put(:effect_attempts, Map.get(metadata, :effect_attempts, %{}))
        |> then(fn result ->
          if metadata[:historical_uncertainty],
            do: Map.put(result, :historical_uncertainty, metadata.historical_uncertainty),
            else: result
        end)

      _ ->
        result
    end
  end

  defp retention_metrics(result, state) do
    data =
      Map.take(result, [
        :output,
        :messages,
        :new_messages,
        :pending_response,
        :usage,
        :continuation_checkpoint
      ])

    measurements = %{
      version: 1,
      measurement: :erlang_external_term,
      data_bytes: Retention.bytes(data),
      history_bytes: Retention.bytes(result.messages),
      max_history_bytes: state.max_history_bytes,
      max_payload_bytes: state.max_payload_bytes,
      control_reserve_bytes: Retention.control_bytes()
    }

    measurements =
      if Map.has_key?(result, :continuation_checkpoint) do
        measurements
        |> Map.merge(result.continuation_retention)
        |> Map.merge(%{
          checkpoint_bytes:
            if(result.continuation_checkpoint,
              do: Retention.bytes(result.continuation_checkpoint),
              else: 0
            ),
          max_checkpoint_bytes: result.max_checkpoint_bytes
        })
      else
        measurements
      end

    result |> Map.delete(:continuation_retention) |> Map.put(:retention, measurements)
  end
end
