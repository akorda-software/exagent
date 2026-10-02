defmodule ExAgent.Coordination.Composition do
  import Kernel, except: [binding: 1]

  @moduledoc """
  Experimental trusted-host definition of a bounded agent sequence.

  `run/3` executes a durable, fail-fast sequence in one attempt. `resume/3` restores
  admitted ready boundaries without replaying completed steps. No agent, mapping, model codec or other callback runs
  during construction or binding validation.

  Definitions contain live host agents/codecs and must not be serialized. Only
  `binding/1` returns portable data. That binding cannot reconstruct a definition,
  grant authority, or prove that host code has not changed under the same version.
  Hosts must version agent definitions (including instructions/tools/settings),
  policy, model/codec, output contracts and input mappings when their meaning changes.
  Runtime Model bindings and tool inventories remain separate admission checks.
  """

  alias ExAgent.Continuation.Record
  alias ExAgent.Continuation.{Authority, CompositionRestore, ScopeLedger, ToolEvidence, Writer}
  alias ExAgent.{ExecutionScope, Retention, RunError}
  alias ExAgent.Message.Usage
  alias ExAgent.Observability.OpenTelemetry, as: Observability
  alias ExAgent.Tool.JSON

  @enforce_keys [:id, :version, :steps, :fingerprint]
  defstruct [:id, :version, :steps, :fingerprint]

  @opaque t :: %__MODULE__{
            id: String.t(),
            version: String.t(),
            steps: [map()],
            fingerprint: String.t()
          }

  @references [:definition, :policy, :model_ref, :output_ref]
  @step_keys [:id, :agent, :model_codec | @references]
  @binding_keys ~w(composition_definition_version kind id version steps fingerprint)
  @step_binding_keys ~w(id definition policy model_ref output_ref input_kind input_version)
  @max_steps 255
  @max_binding_bytes 65_536

  @root_options ~w(usage_limits permissions approve estimate_cost deadline max_concurrent_requests permission_floor permission_floors)a
  @leaf_options ~w(deps model_settings prepend_instructions max_payload_bytes max_history_bytes on_event on_progress permissions approve estimate_cost deadline max_concurrent_requests permission_floor permission_floors)a

  @doc """
  Execute a sequence using a required `:continuation` Writer configuration.

  Optional `:root_options` restrict the shared scope; `:step_options` maps step IDs
  to ordinary run options. `:observability` and `:trace_context` are ephemeral.
  Returns a portable confirmed result, or a RunError with the confirmed partial.
  A failed checkpoint retains its retry token; retrying it never executes a step.
  """
  def run(definition, input, opts \\ []) do
    with {:ok, identity} <- binding(definition),
         :ok <- run_options(definition, opts),
         {:ok, config} <- run_config(definition, identity, opts[:continuation]) do
      root_opts = Keyword.get(opts, :root_options, [])
      bound = Writer.bind_deadline(Keyword.put(root_opts, :continuation, config))
      config = bound[:continuation]
      # A claim's lease/budget bounds this attempt, not durable root authority.
      # Writer checks those bounds before/after mapping and at every effect CAS.
      utc = System.system_time(:millisecond)
      now = System.monotonic_time(:millisecond)

      logical =
        for key <- [:deadline_at, :expires_at],
            is_integer(config[key]),
            do: now + config[key] - utc

      deadline = Enum.reduce(logical, root_opts[:deadline], &Authority.minimum/2)
      root_opts = Keyword.put(root_opts, :deadline, deadline)
      id = "run_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

      Observability.around(
        Observability.configuration(nil, opts),
        :run,
        Observability.ids(%{run_id: id, root_run_id: id}),
        opts[:trace_context],
        fn operation ->
          result = open_scope(definition, input, config, root_opts, opts, id, operation)
          Observability.run_result(operation, result)
          result
        end
      )
    else
      {:error, reason} -> failure(definition, nil, nil, nil, reason, nil, :open)
    end
  end

  @doc """
  Resume a ready durable sequence from its exact public continuation reference.

  Administrative recovery is explicit (`ExAgent.Continuation.recover/3`); this
  function never recovers an expired claim or refreshes a reference. Confirmed
  completed steps are data only. Options match `run/3`.
  """
  def resume(definition, reference, opts \\ []) do
    with {:ok, identity} <- binding(definition),
         :ok <- run_options(definition, opts),
         :ok <- ExecutionScope.validate_structural_options(Keyword.get(opts, :root_options, [])),
         {:ok, config} <- run_config(definition, identity, opts[:continuation]),
         bound =
           Writer.bind_deadline(
             Keyword.put(Keyword.get(opts, :root_options, []), :continuation, config)
           ),
         config = bound[:continuation],
         {:ok, boundary, record, config, step, status} <-
           CompositionRestore.sequence_preflight(definition, reference, config, opts) do
      if boundary == :completed do
        result = project(definition, record, config)

        case Enum.find(result.steps, & &1.output_omitted) do
          nil ->
            {:ok, result}

          omitted ->
            failure(
              definition,
              record,
              config,
              nil,
              {:composition_output_omitted, omitted.output_omitted},
              omitted.id,
              :checkpoint
            )
        end
      else
        resume_claim(definition, record, config, opts, boundary, step, status)
      end
    else
      {:error, reason, record, config} ->
        failure(definition, record, config, nil, reason, nil, :open)

      {:error, reason} ->
        failure(definition, nil, nil, nil, reason, nil, :open)
    end
  end

  defp resume_claim(definition, baseline, config, opts, boundary, step, status) do
    case Writer.claim_composition(baseline, config) do
      {:ok, writer, record} ->
        try do
          frame = record["execution"]["progress"]["runtime"]
          original = frame["authority"][frame["run_id"]]
          root_opts = Authority.intersect(original, original["usage"], opts[:root_options] || [])

          case ExecutionScope.start_structural(frame["run_id"], root_opts) do
            {:ok, root} ->
              try do
                with {:ok, deadline} <- Writer.attempt_deadline(writer),
                     :ok <- CompositionRestore.admission(record, boundary, step, opts),
                     :ok <- CompositionRestore.check_deadline(deadline),
                     :ok <- Writer.bind_composition_scope(writer, root),
                     :ok <-
                       Writer.delegate_definitions(
                         writer,
                         Keyword.get(opts, :delegate_definitions, [])
                       ),
                     :ok <- CompositionRestore.check_deadline(deadline),
                     :ok <-
                       if(is_nil(status),
                         do: ExecutionScope.restore_composition_tree(root, frame),
                         else: :ok
                       ) do
                  Observability.around(
                    Observability.configuration(nil, opts),
                    :run,
                    Observability.ids(%{
                      run_id: root.run_id,
                      root_run_id: root.run_id,
                      attempt_id: record["execution"]["attempt_id"]
                    }),
                    opts[:trace_context],
                    fn operation ->
                      restore =
                        if status,
                          do: %{
                            root: root,
                            step: step,
                            status: status,
                            boundary: boundary,
                            record: record
                          },
                          else: nil

                      result =
                        execute_steps(
                          definition,
                          config,
                          writer,
                          opts,
                          operation,
                          record,
                          restore
                        )

                      Observability.run_result(operation, result)
                      result
                    end
                  )
                else
                  {:error, reason} ->
                    failure(definition, record, config, nil, reason, step.id, :open)
                end
              after
                ExecutionScope.stop(root)
              end

            {:error, reason} ->
              failure(definition, record, config, nil, reason, step.id, :open)
          end
        after
          Writer.stop(writer)
        end

      {:error, {:composition_claim_failed, error, token}} ->
        reason =
          case error do
            {:error, reason} -> reason
            other -> other
          end

        failure(
          definition,
          baseline,
          config,
          Writer.record_metadata(baseline, config, token),
          reason,
          step.id,
          if(token, do: :checkpoint, else: :open)
        )

      {:error, reason} ->
        failure(definition, baseline, config, nil, reason, step.id, :open)
    end
  end

  @doc false
  def run_options(definition, opts) do
    with true <-
           options?(
             opts,
             ~w(continuation root_options step_options delegate_definitions observability trace_context)a
           ),
         true <-
           ExAgent.Continuation.Delegation.catalog?(Keyword.get(opts, :delegate_definitions, [])),
         true <- options?(Keyword.get(opts, :root_options, []), @root_options),
         steps = Keyword.get(opts, :step_options, %{}),
         true <- is_map(steps) and not is_struct(steps),
         true <-
           Enum.all?(steps, fn {id, options} ->
             Enum.any?(definition.steps, &(&1.id == id)) and options?(options, @leaf_options)
           end),
         true <-
           is_nil(opts[:observability]) or opts[:observability] == false or
             is_struct(opts[:observability], Observability),
         true <-
           is_nil(opts[:trace_context]) or
             is_struct(opts[:trace_context], Observability.Context) do
      :ok
    else
      _ -> {:error, :invalid_composition_options}
    end
  end

  defp options?(opts, allowed) when is_list(opts) do
    Keyword.keyword?(opts) and length(opts) == MapSet.size(MapSet.new(Keyword.keys(opts))) and
      Enum.all?(Keyword.keys(opts), &(&1 in allowed)) and
      (is_nil(opts[:deadline]) or is_integer(opts[:deadline]))
  end

  defp options?(_, _), do: false

  @doc false
  def run_config(definition, identity, config) when is_map(config) and not is_struct(config) do
    derived = %{
      kind: :composition,
      composition: definition,
      definition: Map.take(identity, ~w(id version))
    }

    if Enum.all?(derived, fn {key, value} ->
         not Map.has_key?(config, key) or config[key] === value
       end),
       do: Writer.config(Map.merge(config, derived)),
       else: {:error, :invalid_continuation_configuration}
  end

  def run_config(_, _, _), do: {:error, :invalid_continuation_configuration}

  defp open_scope(definition, input, config, root_opts, opts, id, operation) do
    case ExecutionScope.start_structural(id, root_opts) do
      {:ok, scope} ->
        try do
          open_writer(definition, input, config, opts, scope, operation)
        after
          ExecutionScope.stop(scope)
        end

      {:error, reason} ->
        failure(definition, nil, config, nil, reason, nil, :open)
    end
  end

  defp open_writer(definition, input, config, opts, scope, operation) do
    case Writer.open(%{run_id: scope.run_id, execution_scope: scope, input: input}, config) do
      {:ok, writer, opened} ->
        try do
          opened =
            case Writer.delegate_definitions(writer, Keyword.get(opts, :delegate_definitions, [])) do
              :ok -> opened
              error -> error
            end

          case opened do
            {:error, reason} ->
              failure_from_writer(definition, config, writer, reason, nil, :open)

            record ->
              Observability.attributes(
                operation,
                Observability.ids(%{attempt_id: record["execution"]["attempt_id"]})
              )

              execute_steps(definition, config, writer, opts, operation, record)
          end
        after
          Writer.stop(writer)
        end

      {:error, reason} ->
        failure(definition, nil, config, nil, reason, nil, :open)
    end
  end

  defp execute_steps(definition, config, writer, opts, operation, opened, restore \\ nil) do
    completed =
      opened["execution"]["progress"]["runtime"]["children"]
      |> Map.values()
      |> Enum.filter(&(&1["status"] == "completed"))
      |> Enum.map(& &1["link"]["step_id"])

    steps = Enum.reject(definition.steps, &(&1.id in completed))

    Enum.reduce_while(steps, {nil, opened}, fn step, {_, confirmed} ->
      leaf_opts =
        Keyword.get(opts, :step_options, %{})
        |> Map.get(step.id, [])
        |> Keyword.put(:trace_context, Observability.context(operation))
        |> Keyword.merge(Keyword.take(opts, [:observability]))

      restoring = not is_nil(restore) and restore.step.id == step.id

      outcome =
        if restoring do
          safe_restore(writer, restore, config, step, leaf_opts)
        else
          safe_step(writer, definition, step.id, leaf_opts)
        end

      {outcome, record, pending} = step_confirmation(writer, outcome, confirmed)

      case outcome do
        {:ok, %{status: :paused}} ->
          {:halt, {:ok, project(definition, record, config, pending)}}

        {:ok, _} ->
          result = project(definition, record, config, pending)
          omitted = Enum.find(result.steps, & &1.output_omitted)

          if omitted do
            {:halt,
             failure(
               definition,
               record,
               config,
               pending,
               {:composition_output_omitted, omitted.output_omitted},
               step.id,
               :checkpoint
             )}
          else
            {:cont, {{:ok, result}, record}}
          end

        {:error, error} ->
          phase = error_phase(record, step.id, pending, error)

          phase =
            if restoring and phase == :execute and not is_struct(error, RunError) and
                 error != :continuation_owner_lost, do: :prepare, else: phase

          {:halt, failure(definition, record, config, pending, error, step.id, phase)}
      end
    end)
    |> case do
      {{:ok, result}, _} -> {:ok, result}
      error -> error
    end
  end

  # Keep only records actually received from Writer. Owner loss cannot authorize
  # a Store read or reconstruction of a pending command/token from live output.
  defp step_confirmation(writer, outcome, confirmed) do
    case Writer.confirmed_record(writer) do
      {:error, reason} ->
        {{:error, reason}, confirmed, nil}

      record ->
        case Writer.pending(writer) do
          {:error, reason} -> {{:error, reason}, record, nil}
          pending -> {outcome, record, pending}
        end
    end
  end

  defp safe_step(writer, definition, id, opts) do
    ExAgent.run_composition_step(writer, definition, id, opts)
  rescue
    error -> {:error, {:composition_step_failed, Retention.reason(error)}}
  catch
    kind, reason -> {:error, {:composition_step_failed, Retention.reason({kind, reason})}}
  end

  defp safe_restore(writer, restore, config, step, opts) do
    ExAgent.restore_composition_step(
      writer,
      restore.root,
      restore.record,
      config,
      step,
      restore.status,
      restore.boundary,
      opts
    )
  rescue
    error -> {:error, {:composition_step_failed, Retention.reason(error)}}
  catch
    kind, reason -> {:error, {:composition_step_failed, Retention.reason({kind, reason})}}
  end

  defp error_phase(_, _, %{token: token}, _) when not is_nil(token), do: :checkpoint
  defp error_phase(_, _, _, %RunError{reason: :continuation_frame_limit}), do: :checkpoint

  defp error_phase(_, _, _, %RunError{reason: {:continuation_checkpoint_failed, _}}),
    do: :checkpoint

  defp error_phase(_, _, _, :invalid_composition_input), do: :mapping
  defp error_phase(_, _, _, :continuation_owner_lost), do: :execute

  defp error_phase(record, id, _, error) do
    child =
      Enum.find_value(
        record["execution"]["progress"]["runtime"]["children"] || %{},
        fn {_, child} -> if child["link"]["step_id"] == id, do: child end
      )

    cond do
      child && child["result_omitted"] -> :checkpoint
      child || match?(%RunError{}, error) -> :execute
      true -> :prepare
    end
  end

  defp failure_from_writer(definition, config, writer, reason, id, phase) do
    {{:error, reason}, record, pending} =
      step_confirmation(writer, {:error, reason}, nil)

    failure(definition, record, config, pending, reason, id, phase)
  end

  defp failure(definition, record, config, pending, reason, id, phase) do
    reason =
      case reason do
        %RunError{reason: reason} -> reason
        reason -> reason
      end

    partial = project(definition, record, config, pending)

    partial = %{
      partial
      | status: if(reason == :cancelled, do: :cancelled, else: :failed),
        output: nil,
        error_step_id: id,
        error_phase: phase
    }

    partial =
      if phase == :execute or reason == :continuation_owner_lost or
           (is_map(pending) and not is_nil(pending[:token])),
         do: partial_usage(partial),
         else: partial

    {:error, %RunError{reason: Retention.reason(reason), partial: partial}}
  end

  # Common data-only projection. Callers validate external records first; execution
  # supplies only the Writer's last ACK, never a potentially newer Store row.
  @doc false
  def project(definition, record, config, pending \\ nil) do
    pending = pending || if(config, do: Writer.record_metadata(record, config))
    frame = if record, do: record["execution"]["progress"]["runtime"]
    children = if frame, do: frame["children"], else: %{}

    steps =
      if (is_struct(definition, __MODULE__) or is_struct(definition, ExAgent.Coordination.Flow)) and
           (not is_nil(record) or match?({:ok, _}, binding(definition))),
         do: definition.steps,
         else: []

    steps =
      Enum.with_index(steps, fn step, index ->
        found = Enum.find(children, fn {_, child} -> child["link"]["step_id"] == step.id end)
        {id, child} = found || {nil, nil}

        messages =
          if child do
            {:ok, snapshot} =
              ExAgent.Server.Snapshot.deserialize(Jason.encode!(child["snapshot"]))

            {:ok, messages} = ExAgent.Server.Snapshot.messages(snapshot)
            messages
          else
            []
          end

        %{
          id: step.id,
          index: index,
          run_id: id,
          status:
            cond do
              is_nil(child) -> :not_started
              child["status"] == "completed" -> :completed
              record["execution"]["state"] in ["pending", "denied"] -> :paused
              true -> :running
            end,
          input: if(child, do: child["link"]["input"]),
          output: if(child, do: child["result"]),
          output_omitted: if(child, do: child["result_omitted"]),
          messages: messages
        }
      end)

    root = if frame, do: frame["run_id"]

    usage =
      if frame do
        {:ok, usage} = ScopeLedger.usage(frame["scope"], root)
        usage
      else
        Usage.sum([])
      end

    complete =
      frame && frame["cursor"] == "completed" && Enum.all?(steps, &is_nil(&1.output_omitted))

    counts = if frame, do: frame["scope"]["nodes"][root], else: %{}
    attempt = confirmed_attempt(record)

    reference =
      if record do
        %{
          version: 1,
          id: config.id,
          record_id: record["record_id"],
          revision: record["revision"],
          run_id: root,
          attempt_id: attempt
        }
      end

    cost = Usage.estimated_cost(usage)

    result = %{
      status:
        cond do
          complete -> :completed
          record && record["execution"]["state"] == "pending" -> :paused
          true -> :failed
        end,
      output: if(complete, do: List.last(steps).output),
      model: nil,
      messages: [],
      new_messages: [],
      run_id: root,
      root_run_id: root,
      parent_run_id: nil,
      steps: steps,
      usage: usage,
      usage_status: if(Usage.complete?(usage), do: :complete, else: :partial),
      request_count: counts["requests"] || 0,
      tool_calls: counts["tools"] || 0,
      cost_cents: cost,
      cost_status: if(is_number(cost), do: :known, else: :unknown),
      continuation: reference,
      continuation_checkpoint: if(is_map(pending), do: pending[:token]),
      attempt_id: attempt,
      error_step_id: nil,
      error_phase: nil
    }

    result =
      if frame &&
           (Enum.any?(frame["scope"]["operations"], &(not &1["complete"])) or
              Enum.any?(Map.keys(children), &ToolEvidence.rejected?(frame, &1))),
         do: partial_usage(result),
         else: result

    if is_map(pending) do
      result
      |> Map.put(:max_checkpoint_bytes, pending.max_bytes)
      |> Map.put(:continuation_retention, %{
        record_bytes: pending.record_bytes,
        record_json_bytes: pending.record_json_bytes
      })
      |> Map.put(:effect_attempts, pending.effect_attempts)
      |> Map.put(:historical_uncertainty, pending.historical_uncertainty)
    else
      result
    end
  end

  defp partial_usage(result),
    do: %{
      result
      | usage: Usage.partial(result.usage),
        usage_status: :partial,
        cost_cents: nil,
        cost_status: :unknown
    }

  defp confirmed_attempt(nil), do: nil

  defp confirmed_attempt(record) do
    record["execution"]["attempt_id"] ||
      record["receipts"]
      |> Map.values()
      |> Enum.filter(&(&1["operation"] == "claim"))
      |> Enum.max_by(& &1["revision"], fn -> %{} end)
      |> Map.get("attempt_id")
  end

  @doc """
  Validate a sequence definition without executing user code.

  Required keyword options: `:id`, `:version` (nonempty UTF-8 strings, at most
  512 bytes each), and `:steps` (1..255 atom-keyed maps with unique IDs).
  Optional `kind: :sequence` and `failure_policy: :fail_fast` are the only
  supported choices. Unknown or duplicate options are rejected.

  Each step requires `:id`, an `ExAgent` struct in `:agent`, versioned references
  `:definition`, `:policy`, `:model_ref`, `:output_ref`, and `:model_codec` with
  `dump/1` and `load/2` functions. References use the existing `%{id: ..., version:
  ...}` convention (string keys also accepted). A mapping requires both `:input`
  (a pure arity-2 function) and `:input_version` (a version string). It will receive
  the initial input and confirmed outputs by step ID when execution is integrated.
  Without mapping, the first input is initial input and successors use prior output.

  The complete encoded identity binding, including fingerprint, is limited to
  65,536 JSON bytes. This is a definition limit, not a runtime journal reservation.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, atom()}
  def new(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         keys = Keyword.keys(opts),
         true <- length(keys) == MapSet.size(MapSet.new(keys)),
         true <- Enum.all?(keys, &(&1 in [:id, :version, :steps, :kind, :failure_policy])),
         true <- Keyword.get(opts, :kind, :sequence) == :sequence,
         true <- Keyword.get(opts, :failure_policy, :fail_fast) == :fail_fast,
         {:ok, steps, binding} <- build(opts[:id], opts[:version], opts[:steps]) do
      {:ok,
       %__MODULE__{
         id: opts[:id],
         version: opts[:version],
         steps: steps,
         fingerprint: binding["fingerprint"]
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_composition_definition}
    end
  end

  def new(_), do: {:error, :invalid_composition_definition}

  @doc """
  Return the explicitly versioned portable identity of a trusted definition.

  This is not an executable continuation frame. It contains no functions, agent
  structs, model state, credentials, dependency objects or tracing context. Host
  references themselves must be nonsecret. A mutated definition is revalidated.
  """
  @spec binding(t()) :: {:ok, map()} | {:error, atom()}
  def binding(%__MODULE__{id: id, version: version, steps: steps, fingerprint: fingerprint}) do
    with {:ok, _, binding} <- build(id, version, steps),
         true <- binding["fingerprint"] === fingerprint do
      {:ok, binding}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_composition_definition}
    end
  end

  def binding(%{__struct__: ExAgent.Coordination.Flow} = definition),
    do: ExAgent.Coordination.Flow.binding(definition)

  def binding(_), do: {:error, :invalid_composition_definition}

  @doc """
  Validate stored identity against a freshly supplied trusted definition, without IO.

  Malformed/future bindings reject as `:invalid_composition_binding`; well-formed
  changed identities reject as `:composition_definition_changed`. Never load host
  definitions or resolve modules from the stored binding. This check alone is not
  runtime admission, approval, or validation of a continuation's journal/ledger.
  """
  @spec validate_binding(t(), term()) :: :ok | {:error, atom()}
  def validate_binding(definition, stored) do
    with {:ok, current} <- binding(definition),
         :ok <- validate_stored(stored) do
      if current === stored, do: :ok, else: {:error, :composition_definition_changed}
    end
  end

  defp build(id, version, steps) do
    with true <- Record.text?(id) and Record.text?(version),
         true <- bounded_steps?(steps),
         {:ok, normalized} <- normalize_steps(steps),
         true <- unique_ids?(normalized),
         data = %{
           "composition_definition_version" => 1,
           "kind" => "sequence",
           "id" => id,
           "version" => version,
           "steps" => Enum.with_index(normalized, &step_binding/2)
         },
         {:ok, hash} <- Record.digest(data),
         binding = Map.put(data, "fingerprint", hash),
         :ok <- within_limit(binding) do
      {:ok, normalized, binding}
    else
      {:error, :composition_definition_too_large} = error -> error
      _ -> {:error, :invalid_composition_definition}
    end
  end

  defp bounded_steps?(steps) when is_list(steps) and length(steps) in 1..@max_steps, do: true
  defp bounded_steps?(_), do: false

  defp unique_ids?(steps), do: MapSet.size(MapSet.new(steps, & &1.id)) == length(steps)

  defp normalize_steps(steps) do
    Enum.reduce_while(steps, {:ok, []}, fn step, {:ok, acc} ->
      case normalize_step(step) do
        {:ok, step} -> {:cont, {:ok, [step | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, steps} -> {:ok, Enum.reverse(steps)}
      error -> error
    end
  end

  defp normalize_step(step) when is_map(step) do
    mapped? = Map.has_key?(step, :input)
    keys = @step_keys ++ if(mapped?, do: [:input, :input_version], else: [])

    with true <- Record.exact?(step, keys),
         true <- Record.text?(step.id) and is_struct(step.agent, ExAgent),
         true <- Record.exact?(step.model_codec, [:dump, :load]),
         true <- is_function(step.model_codec.dump, 1) and is_function(step.model_codec.load, 2),
         true <- not mapped? or (is_function(step.input, 2) and Record.text?(step.input_version)),
         {:ok, refs} <- normalize_references(Map.take(step, @references)) do
      {:ok, Map.merge(step, refs)}
    else
      _ -> {:error, :invalid_composition_definition}
    end
  end

  defp normalize_step(_), do: {:error, :invalid_composition_definition}

  defp normalize_references(refs) do
    Enum.reduce_while(refs, {:ok, %{}}, fn {key, ref}, {:ok, acc} ->
      with true <- is_map(ref) and map_size(ref) == 2,
           true <- Enum.all?(Map.values(ref), &Record.text?/1),
           {:ok, ref} <- JSON.normalize(ref),
           true <- Record.reference?(ref) do
        {:cont, {:ok, Map.put(acc, key, ref)}}
      else
        _ -> {:halt, {:error, :invalid_composition_definition}}
      end
    end)
  end

  defp step_binding(step, index) do
    references = Map.new(@references, &{Atom.to_string(&1), Map.fetch!(step, &1)})

    Map.merge(references, %{
      "id" => step.id,
      "input_kind" =>
        if(Map.has_key?(step, :input),
          do: "host",
          else: if(index == 0, do: "initial", else: "previous_output")
        ),
      "input_version" => Map.get(step, :input_version)
    })
  end

  @doc false
  def validate_stored(%{"flow_definition_version" => _} = stored),
    do: ExAgent.Coordination.Flow.validate_stored(stored)

  def validate_stored(stored) do
    with true <- Record.exact?(stored, @binding_keys),
         true <- stored["composition_definition_version"] === 1 and stored["kind"] === "sequence",
         true <- Record.text?(stored["id"]) and Record.text?(stored["version"]),
         true <- bounded_steps?(stored["steps"]),
         true <-
           Enum.with_index(stored["steps"])
           |> Enum.all?(fn {step, i} -> stored_step?(step, i) end),
         ids = Enum.map(stored["steps"], & &1["id"]),
         true <- MapSet.size(MapSet.new(ids)) == length(ids),
         hash = stored["fingerprint"],
         true <- is_binary(hash) and byte_size(hash) == 64,
         :ok <- within_limit(stored),
         {:ok, ^hash} <- Record.digest(Map.delete(stored, "fingerprint")) do
      :ok
    else
      _ -> {:error, :invalid_composition_binding}
    end
  end

  defp stored_step?(step, index) do
    Record.exact?(step, @step_binding_keys) and Record.text?(step["id"]) and
      Enum.all?(@references, &Record.reference?(step[Atom.to_string(&1)])) and
      case step["input_kind"] do
        "host" ->
          Record.text?(step["input_version"])

        kind ->
          kind == if(index == 0, do: "initial", else: "previous_output") and
            is_nil(step["input_version"])
      end
  end

  defp within_limit(binding) do
    if byte_size(Jason.encode!(binding)) <= @max_binding_bytes,
      do: :ok,
      else: {:error, :composition_definition_too_large}
  end
end
