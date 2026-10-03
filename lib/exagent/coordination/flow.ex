defmodule ExAgent.Coordination.Flow do
  import Kernel, except: [binding: 1]

  @moduledoc """
  A bounded, trusted host router or parallel fan-out/fan-in.

  A router's versioned `:select` callback returns one declared branch ID. A
  parallel flow admits every declared branch, with at most `:max_concurrency`
  live branch workers. Every branch receives the root input and may delegate
  through ordinary agent tools. Branches and their portable outcomes are ordered
  by definition, independently of completion order.

  `:failure_policy` is `:fail_fast` or `:collect`. Collect includes confirmed
  failures in the ordered outcomes; uncertain IO always blocks continuation.
  A versioned optional `:merge` callback receives the ordered portable outcomes.
  Without one, that list is the result. Selection and merge are admitted and
  checkpointed host phases: a crash after admission requires explicit recovery
  and never replays an uncertain callback.

  Selection and merge are pure trusted host callbacks. Put external effects in
  agent tools, where intent/outcome and approval are journaled. Their explicit
  versions identify the host code; change a version when its behavior changes.

  There are at most 32 branches, concurrency is 1..32 (default 4), and the merged
  result and each branch result have separate portable JSON limits of 65,536
  bytes (`:max_result_bytes` and `:max_branch_result_bytes`, which may be lowered). These
  limits do not guarantee admission of every branch/delegation depth into the
  existing 8 MiB journal. Ordinary scope authority and checkpoint admission apply.
  """

  alias ExAgent.Continuation.{Authority, CompositionRestore, Record, ToolEvidence, Worker, Writer}
  alias ExAgent.Coordination.Composition
  alias ExAgent.{ExecutionScope, Retention, RunError}
  alias ExAgent.Observability.OpenTelemetry, as: Observability
  alias ExAgent.Tool.JSON

  @enforce_keys [
    :id,
    :version,
    :kind,
    :steps,
    :max_concurrency,
    :failure_policy,
    :max_result_bytes,
    :max_branch_result_bytes,
    :fingerprint
  ]
  defstruct @enforce_keys ++ [:select, :select_version, :merge, :merge_version]

  @keys ~w(flow_definition_version kind id version steps max_concurrency failure_policy max_result_bytes max_branch_result_bytes select_version merge_version fingerprint)

  def new(opts) do
    with true <- is_list(opts) and Keyword.keyword?(opts),
         true <- length(opts) == MapSet.size(MapSet.new(Keyword.keys(opts))),
         true <-
           Enum.all?(
             Keyword.keys(opts),
             &(&1 in [
                 :id,
                 :version,
                 :kind,
                 :branches,
                 :max_concurrency,
                 :failure_policy,
                 :max_result_bytes,
                 :max_branch_result_bytes,
                 :select,
                 :select_version,
                 :merge,
                 :merge_version
               ])
           ),
         branches when is_list(branches) and length(branches) in 1..32 <- opts[:branches],
         {:ok, steps} <- normalize_branches(branches),
         definition = %__MODULE__{
           id: opts[:id],
           version: opts[:version],
           kind: opts[:kind],
           steps: steps,
           max_concurrency: Keyword.get(opts, :max_concurrency, 4),
           failure_policy: Keyword.get(opts, :failure_policy, :fail_fast),
           max_result_bytes: Keyword.get(opts, :max_result_bytes, 65_536),
           max_branch_result_bytes: Keyword.get(opts, :max_branch_result_bytes, 65_536),
           select: opts[:select],
           select_version: opts[:select_version],
           merge: opts[:merge],
           merge_version: opts[:merge_version],
           fingerprint: nil
         },
         {:ok, data} <- definition_data(definition),
         {:ok, fingerprint} <- Record.digest(data) do
      {:ok, %{definition | fingerprint: fingerprint}}
    else
      _ -> {:error, :invalid_flow_definition}
    end
  end

  defp normalize_branches(branches) do
    Enum.reduce_while(branches, {:ok, []}, fn branch, {:ok, acc} ->
      # Branch input is always the root input. Mapping belongs in the explicitly
      # versioned selector or in the agent, rather than a previous-output edge.
      case Composition.new(id: "branch", version: "1", steps: [branch]) do
        {:ok, %{steps: [step]}} when not is_map_key(step, :input) -> {:cont, {:ok, acc ++ [step]}}
        _ -> {:halt, {:error, :invalid_flow_definition}}
      end
    end)
  end

  def binding(%__MODULE__{} = definition) do
    with {:ok, data} <- definition_data(definition),
         {:ok, hash} <- Record.digest(data),
         true <- hash === definition.fingerprint,
         data = Map.put(data, "fingerprint", hash),
         :ok <- validate_stored(data) do
      {:ok, data}
    else
      _ -> {:error, :invalid_flow_definition}
    end
  end

  def binding(_), do: {:error, :invalid_flow_definition}

  defp definition_data(d) do
    with true <- Record.text?(d.id) and Record.text?(d.version),
         true <- d.kind in [:router, :parallel],
         true <- is_integer(d.max_concurrency) and d.max_concurrency in 1..32,
         true <- d.failure_policy in [:fail_fast, :collect],
         true <- is_integer(d.max_result_bytes) and d.max_result_bytes in 1..65_536,
         true <- is_integer(d.max_branch_result_bytes) and d.max_branch_result_bytes in 1..65_536,
         true <-
           (d.kind == :router and is_function(d.select, 1) and Record.text?(d.select_version)) or
             (d.kind == :parallel and is_nil(d.select) and is_nil(d.select_version)),
         true <-
           (is_nil(d.merge) and is_nil(d.merge_version)) or
             (is_function(d.merge, 1) and Record.text?(d.merge_version)),
         true <- is_list(d.steps) and length(d.steps) in 1..32,
         {:ok, steps} <- normalize_branches(d.steps),
         true <- length(steps) == MapSet.size(MapSet.new(steps, & &1.id)) do
      identities =
        Enum.map(steps, fn step ->
          {:ok, b} =
            Composition.binding(
              elem(Composition.new(id: "branch", version: "1", steps: [step]), 1)
            )

          b["steps"] |> hd() |> Map.put("input_kind", "initial")
        end)

      {:ok,
       %{
         "flow_definition_version" => 1,
         "kind" => Atom.to_string(d.kind),
         "id" => d.id,
         "version" => d.version,
         "steps" => identities,
         "max_concurrency" => d.max_concurrency,
         "failure_policy" => Atom.to_string(d.failure_policy),
         "max_result_bytes" => d.max_result_bytes,
         "max_branch_result_bytes" => d.max_branch_result_bytes,
         "select_version" => d.select_version,
         "merge_version" => d.merge_version
       }}
    else
      _ -> {:error, :invalid_flow_definition}
    end
  end

  @doc false
  def validate_stored(b) do
    with true <- Record.exact?(b, @keys),
         true <- b["flow_definition_version"] === 1 and b["kind"] in ~w(router parallel),
         true <- Record.text?(b["id"]) and Record.text?(b["version"]),
         true <- is_integer(b["max_concurrency"]) and b["max_concurrency"] in 1..32,
         true <- b["failure_policy"] in ~w(fail_fast collect),
         true <- is_integer(b["max_result_bytes"]) and b["max_result_bytes"] in 1..65_536,
         true <-
           is_integer(b["max_branch_result_bytes"]) and b["max_branch_result_bytes"] in 1..65_536,
         true <-
           (b["kind"] == "router" and Record.text?(b["select_version"])) or
             (b["kind"] == "parallel" and is_nil(b["select_version"])),
         true <- is_nil(b["merge_version"]) or Record.text?(b["merge_version"]),
         steps when is_list(steps) and length(steps) in 1..32 <- b["steps"],
         true <- Enum.all?(steps, &stored_branch?/1),
         true <- length(steps) == MapSet.size(MapSet.new(steps, & &1["id"])),
         hash = b["fingerprint"],
         true <- is_binary(hash) and byte_size(hash) == 64,
         {:ok, ^hash} <- Record.digest(Map.delete(b, "fingerprint")),
         true <- byte_size(Jason.encode!(b)) <= 65_536 do
      :ok
    else
      _ -> {:error, :invalid_composition_binding}
    end
  end

  defp stored_branch?(b) do
    Record.exact?(b, ~w(id definition policy model_ref output_ref input_kind input_version)) and
      Record.text?(b["id"]) and
      Enum.all?(~w(definition policy model_ref output_ref), &Record.reference?(b[&1])) and
      b["input_kind"] == "initial" and is_nil(b["input_version"])
  end

  def run(definition, input, opts \\ []) do
    with {:ok, identity} <- binding(definition),
         :ok <- Composition.run_options(definition, opts),
         {:ok, config} <- Composition.run_config(definition, identity, opts[:continuation]),
         root_opts = Keyword.get(opts, :root_options, []),
         bound = Writer.bind_deadline(Keyword.put(root_opts, :continuation, config)),
         config = bound[:continuation],
         {:ok, root} <-
           ExecutionScope.start_structural(new_id(), logical_options(root_opts, config)) do
      try do
        case Writer.open(%{run_id: root.run_id, execution_scope: root, input: input}, config) do
          {:ok, writer, _record} ->
            try do
              with :ok <- Writer.delegate_definitions(writer, opts[:delegate_definitions] || []) do
                execute(definition, root, writer, config, opts, %{})
              else
                {:error, reason} -> failure(definition, writer, config, reason)
              end
            after
              Writer.stop(writer)
            end

          {:error, reason} ->
            failure(definition, nil, config, reason)
        end
      after
        ExecutionScope.stop(root)
      end
    else
      {:error, reason} -> failure(definition, nil, nil, reason)
    end
  end

  def resume(definition, reference, opts \\ []) do
    with {:ok, identity} <- binding(definition),
         :ok <- Composition.run_options(definition, opts),
         :ok <- ExecutionScope.validate_structural_options(Keyword.get(opts, :root_options, [])),
         {:ok, config} <- Composition.run_config(definition, identity, opts[:continuation]),
         bound =
           Writer.bind_deadline(Keyword.put(opts[:root_options] || [], :continuation, config)),
         config = bound[:continuation],
         {:ok, record, config} <-
           CompositionRestore.flow_preflight(definition, reference, config, opts) do
      if record["execution"]["state"] in ~w(completed failed) do
        terminal(definition, record, config)
      else
        resume_claim(definition, record, config, opts)
      end
    else
      {:error, reason} -> failure(definition, nil, nil, reason)
    end
  end

  defp resume_claim(d, baseline, config, opts) do
    case Writer.claim_composition(baseline, config) do
      {:ok, writer, record} ->
        try do
          with :ok <- CompositionRestore.flow_admission(record, opts) do
            frame = record["execution"]["progress"]["runtime"]
            authority = frame["authority"][frame["run_id"]]

            root_opts =
              Authority.intersect(authority, authority["usage"], opts[:root_options] || [])

            case ExecutionScope.start_structural(frame["run_id"], root_opts) do
              {:ok, root} ->
                try do
                  with :ok <- Writer.bind_composition_scope(writer, root),
                       :ok <-
                         Writer.delegate_definitions(writer, opts[:delegate_definitions] || []),
                       {:ok, restored} <-
                         ExAgent.prepare_flow_restore(writer, root, record, config, d, opts) do
                    execute(d, root, writer, config, opts, restored)
                  else
                    {:error, reason} -> failure(d, writer, config, reason)
                  end
                after
                  ExecutionScope.stop(root)
                end

              {:error, reason} ->
                failure(d, writer, config, reason)
            end
          else
            {:error, reason} -> failure(d, writer, config, reason)
          end
        after
          Writer.stop(writer)
        end

      {:error, reason} ->
        failure(d, nil, config, reason, baseline)
    end
  end

  defp execute(d, root, writer, config, opts, restored) do
    Observability.around(
      Observability.configuration(nil, opts),
      :run,
      Observability.ids(%{run_id: root.run_id, root_run_id: root.run_id}),
      opts[:trace_context],
      fn operation ->
        result =
          with :ok <- select(d, writer),
               :ok <- branches(d, root, writer, opts, restored, operation),
               :ok <- Writer.flow_checkpoint(writer, "flow_drain", %{}) do
            record = Writer.confirmed_record(writer)

            if record["execution"]["state"] == "pending" do
              {:ok, project(d, record, config)}
            else
              merge(d, writer, config)
            end
          else
            {:error, reason} -> failure(d, writer, config, reason)
          end

        Observability.run_result(operation, result)
        result
      end
    )
  end

  defp select(d, writer) do
    frame = Writer.confirmed_record(writer)["execution"]["progress"]["runtime"]

    if frame["flow"]["phase"] == "idle" do
      with :ok <- Writer.flow_checkpoint(writer, "flow_select_begin", %{}) do
        case invoke_select(d, frame["input"]) do
          {:ok, selected} ->
            Writer.flow_checkpoint(writer, "flow_select", %{"selected" => selected})

          {:error, reason} ->
            with :ok <-
                   Writer.flow_checkpoint(writer, "flow_host_failed", %{
                     "error" => ToolEvidence.error(reason),
                     "marker" => nil
                   }),
                 do: {:error, reason}
        end
      end
    else
      if frame["flow"]["phase"] in ~w(running completed),
        do: :ok,
        else: {:error, :continuation_uncertain}
    end
  end

  defp invoke_select(%{kind: :parallel, steps: steps}, _), do: {:ok, Enum.map(steps, & &1.id)}

  defp invoke_select(%{select: select, steps: steps}, input) do
    id = select.(input)
    if Enum.any?(steps, &(&1.id === id)), do: {:ok, [id]}, else: {:error, :invalid_flow_selection}
  rescue
    e -> {:error, {:flow_selection_failed, Retention.reason(e)}}
  catch
    kind, reason -> {:error, {:flow_selection_failed, Retention.reason({kind, reason})}}
  end

  defp branches(d, root, writer, opts, restored, operation) do
    frame = Writer.confirmed_record(writer)["execution"]["progress"]["runtime"]

    queue =
      Enum.filter(d.steps, fn step ->
        step.id in frame["flow"]["selected"] and
          not Enum.any?(frame["children"], fn {_, n} ->
            n["link"]["step_id"] == step.id and
              (n["status"] in ~w(completed failed cancelled) or
                 (frame["frontier"]["state"] == "draining" and
                    frame["frontier"]["reason"] == "approval" and n["status"] == "suspended"))
          end)
      end)

    schedule(queue, %{}, nil, d, root, writer, opts, restored, operation)
  end

  defp schedule(queue, workers, error, d, root, writer, opts, restored, operation) do
    frame = Writer.confirmed_record(writer)["execution"]["progress"]["runtime"]

    stop =
      error != nil or
        (frame["frontier"]["reason"] == "approval" and
           not (queue != [] and is_map(restored[hd(queue).id]))) or
        (d.failure_policy == :fail_fast and frame["flow"]["failures"] != %{})

    {queue, workers} =
      if not stop and queue != [] and map_size(workers) < d.max_concurrency do
        [step | queue] = queue
        owner = self()

        {pid, monitor} =
          spawn_monitor(fn ->
            run = %{
              continuation_version: 11,
              continuation: writer,
              execution_scope: root,
              run_id: "branch:" <> step.id,
              model_request_id: nil
            }

            result =
              try do
                Worker.run(run, :branch, nil, fn ->
                  leaf_opts =
                    Map.get(opts[:step_options] || %{}, step.id, [])
                    |> Keyword.put(:observability, Observability.configuration(nil, opts))
                    |> Keyword.put(:trace_context, Observability.context(operation))

                  case restored[step.id] do
                    nil -> ExAgent.run_composition_step(writer, d, step.id, leaf_opts)
                    node -> ExAgent.run_flow_restored(node, leaf_opts)
                  end
                end)
              rescue
                e -> {:error, Retention.reason(e)}
              catch
                kind, reason -> {:error, Retention.reason({kind, reason})}
              end

            send(owner, {:flow_branch_result, self(), result})
          end)

        {queue, Map.put(workers, monitor, %{pid: pid, step: step.id, result: nil})}
      else
        {if(stop, do: [], else: queue), workers}
      end

    cond do
      queue != [] and not stop and map_size(workers) < d.max_concurrency ->
        schedule(queue, workers, error, d, root, writer, opts, restored, operation)

      map_size(workers) == 0 ->
        if error, do: {:error, error}, else: :ok

      true ->
        receive do
          {:flow_branch_result, pid, result} ->
            workers =
              Map.new(workers, fn {ref, w} ->
                {ref, if(w.pid == pid, do: %{w | result: result}, else: w)}
              end)

            schedule(queue, workers, error, d, root, writer, opts, restored, operation)

          {:DOWN, ref, :process, pid, reason} when is_map_key(workers, ref) ->
            %{pid: ^pid, step: id, result: result} = workers[ref]
            settled = Writer.flow_branch_done(writer, id)

            error =
              case {settled, result, reason} do
                {:ok, {:ok, _}, :normal} ->
                  error

                {:ok, {:error, _}, :normal} ->
                  error

                {{:error, r}, {:error, outcome}, _} ->
                  error || if(r == :continuation_uncertain, do: outcome, else: r)

                {{:error, r}, _, _} ->
                  error || r

                _ ->
                  error || :flow_branch_lost
              end

            schedule(
              queue,
              Map.delete(workers, ref),
              error,
              d,
              root,
              writer,
              opts,
              restored,
              operation
            )
        end
    end
  end

  defp merge(d, writer, config) do
    record = Writer.confirmed_record(writer)

    if record["execution"]["state"] == "failed" do
      terminal(d, record, config)
    else
      outcomes = portable_outcomes(record)

      with :ok <- Writer.flow_checkpoint(writer, "flow_merge_begin", %{}) do
        case invoke_merge(d, outcomes) do
          {:ok, output} ->
            with :ok <- Writer.flow_checkpoint(writer, "flow_merge", %{"result" => output}),
                 do: terminal(d, Writer.confirmed_record(writer), config)

          {:error, reason, marker} ->
            error =
              if marker,
                do:
                  ToolEvidence.error(Retention.error(:output, marker["bytes"], marker["limit"])),
                else: ToolEvidence.error(reason)

            with :ok <-
                   Writer.flow_checkpoint(writer, "flow_host_failed", %{
                     "error" => error,
                     "marker" => marker
                   }),
                 do: terminal(d, Writer.confirmed_record(writer), config)
        end
      end
      |> case do
        {:error, %RunError{}} = error -> error
        {:error, reason} -> failure(d, writer, config, reason)
        success -> success
      end
    end
  end

  defp invoke_merge(d, outcomes) do
    result = if d.merge, do: d.merge.(outcomes), else: outcomes

    with {:ok, value} <- JSON.normalize(result),
         {:ok, json} <- Record.canonical(value) do
      if byte_size(json) <= d.max_result_bytes,
        do: {:ok, value},
        else:
          {:error, :flow_result_limit,
           Retention.marker(:output, byte_size(json), d.max_result_bytes)}
    else
      _ -> {:error, :unrepresentable_flow_result, nil}
    end
  rescue
    e -> {:error, {:flow_merge_failed, Retention.reason(e)}, nil}
  catch
    kind, reason -> {:error, {:flow_merge_failed, Retention.reason({kind, reason})}, nil}
  end

  @doc false
  def portable_outcomes(record) do
    frame = record["execution"]["progress"]["runtime"]

    for step <- frame["binding"]["steps"], step["id"] in frame["flow"]["selected"] do
      node =
        Enum.find_value(frame["children"], fn {_, n} ->
          if n["link"]["step_id"] == step["id"], do: n
        end)

      %{
        "id" => step["id"],
        "status" => if(node, do: node["status"], else: "not_started"),
        "output" => if(node, do: node["result"]),
        "output_omitted" => if(node, do: node["result_omitted"] || node["error"]["omitted"]),
        "error" => if(node, do: node["error"])
      }
    end
  end

  @doc false
  def project(d, record, config, pending \\ nil) do
    base = Composition.project(d, record, config, pending)
    frame = if record, do: record["execution"]["progress"]["runtime"]

    outcomes = if record, do: portable_outcomes(record), else: []

    steps =
      Enum.map(base.steps, fn step ->
        case Enum.find(outcomes, &(&1["id"] == step.id)) do
          %{"status" => status, "output_omitted" => omitted}
          when status in ~w(failed cancelled) ->
            %{
              step
              | status: String.to_existing_atom(status),
                output_omitted: omitted
            }

          _ ->
            step
        end
      end)

    base
    |> Map.put(:steps, steps)
    |> Map.put(:branches, outcomes)
    |> Map.put(:output, if(frame && frame["cursor"] == "completed", do: frame["flow"]["result"]))
    |> Map.put(:output_omitted, if(frame, do: frame["flow"]["result_omitted"]))
  end

  defp terminal(d, record, config) do
    result = project(d, record, config)

    if record["execution"]["state"] == "completed",
      do: {:ok, result},
      else:
        {:error,
         %RunError{
           reason: record["execution"]["progress"]["runtime"]["frontier"]["fatal"]["error"],
           partial: result
         }}
  end

  defp failure(d, writer, config, reason, record \\ nil) do
    record = if writer, do: Writer.confirmed_record(writer), else: record
    pending = if writer, do: Writer.pending(writer)
    reason = if is_struct(reason, RunError), do: reason.reason, else: reason

    {:error,
     %RunError{reason: Retention.reason(reason), partial: project(d, record, config, pending)}}
  end

  defp new_id, do: "run_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  defp logical_options(opts, config) do
    utc = System.system_time(:millisecond)
    mono = System.monotonic_time(:millisecond)

    deadline =
      Enum.reduce([config[:deadline_at], config[:expires_at]], opts[:deadline], fn
        n, d when is_integer(n) -> Authority.minimum(d, mono + n - utc)
        _, d -> d
      end)

    Keyword.put(opts, :deadline, deadline)
  end
end
