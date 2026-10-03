defmodule ExAgent.Continuation.CompositionRestore do
  @moduledoc false
  alias ExAgent.Continuation.{Authority, Frame, Record, ToolEvidence, Writer}
  alias ExAgent.Message

  def flow_preflight(definition, reference, config, opts) do
    with :ok <- public_reference(reference),
         true <- reference.id == config.id,
         {:ok, record} <- ExAgent.Store.load_record(config.store, :agent, config.id),
         true <-
           record["record_id"] == reference.record_id and record["revision"] == reference.revision and
             record["execution"]["run_id"] == reference.run_id,
         :ok <- Record.validate(record, {config.store.namespace, :agent, config.id}),
         root = record["execution"]["progress"]["runtime"],
         true <- root["frame_version"] == 11,
         :ok <- ExAgent.Coordination.Composition.validate_binding(definition, root["binding"]),
         true <- record["execution"]["policy"] === config.policy,
         terminal = record["execution"]["state"] in ~w(completed failed),
         true <-
           terminal or
             (record["execution"]["state"] == "ready" and
                root["flow"]["phase"] in ~w(idle running) and
                not Record.unresolved?(record["execution"])),
         true <-
           terminal or
             Enum.all?(Map.get(record["execution"]["progress"], "approvals", %{}), fn {_, a} ->
               ExAgent.Continuation.Approval.approved?(a)
             end),
         true <-
           terminal or
             Enum.all?(root["children"], fn {_, n} ->
               n["status"] not in ~w(running suspended) or n["link"]["kind"] == "step" or
                 Enum.any?(opts[:delegate_definitions] || [], fn entry ->
                   Enum.all?(
                     [:definition, :policy, :model_ref],
                     &(entry[&1] === n[Atom.to_string(&1)])
                   )
                 end)
             end),
         :ok <-
           if(terminal,
             do: :ok,
             else: flow_time(record, opts)
           ),
         config =
           Map.put(
             config,
             :max_checkpoint_bytes,
             Authority.minimum(
               config[:max_checkpoint_bytes],
               root["authority"][root["run_id"]]["checkpoint_limit"]
             )
           ),
         :ok <- read_limit(record, config) do
      {:ok, record, config}
    else
      {:error, _} = error -> error
      _ -> {:error, :continuation_conflict}
    end
  rescue
    _ -> {:error, :invalid_composition_restore}
  end

  @doc false
  def flow_admission(record, opts) do
    with :ok <- flow_time(record, opts) do
      execution = record["execution"]
      now = System.system_time(:millisecond)

      cond do
        is_integer(execution["lease_until"]) and execution["lease_until"] <= now ->
          {:error, :lease_expired}

        Enum.any?(
          ~w(deadline_at expires_at),
          &(is_integer(execution[&1]) and execution[&1] <= now)
        ) ->
          {:error, :expired}

        true ->
          :ok
      end
    end
  end

  defp flow_time(record, opts) do
    root = record["execution"]["progress"]["runtime"]

    active =
      Enum.filter(root["flow"]["selected"], fn id ->
        node =
          Enum.find_value(root["children"], fn {_, n} -> if n["link"]["step_id"] == id, do: n end)

        is_nil(node) or node["status"] in ~w(running suspended)
      end)

    with :ok <- logical_time(record, :structural_tree, root_options: opts[:root_options]) do
      Enum.reduce_while(active, :ok, fn id, :ok ->
        leaf = Map.get(opts[:step_options] || %{}, id, [])

        case logical_time(record, :structural_tree, leaf) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  def sequence_preflight(definition, reference, config, opts) do
    with :ok <- public_reference(reference),
         true <- reference.id == config.id,
         {:ok, record} <- ExAgent.Store.load_record(config.store, :agent, config.id),
         true <-
           record["record_id"] == reference.record_id and
             record["revision"] == reference.revision and
             record["execution"]["run_id"] == reference.run_id,
         :ok <- Record.validate(record, {config.store.namespace, :agent, config.id}),
         frame = record["execution"]["progress"]["runtime"],
         :ok <- ExAgent.Coordination.Composition.validate_binding(definition, frame["binding"]),
         true <- record["execution"]["policy"] === config.policy,
         {:ok, boundary} <- checked(sequence_boundary(record), record, config),
         :ok <- checked(structural_catalog(record, boundary, opts), record, config),
         step_count = Enum.count(frame["children"], fn {_, c} -> c["link"]["kind"] == "step" end),
         index =
           if(frame["cursor"] == "running",
             do: step_count - 1,
             else: min(step_count, length(definition.steps) - 1)
           ),
         step = Enum.at(definition.steps, index),
         :ok <- host_boundary(boundary, step),
         leaf_opts = Map.get(Keyword.get(opts, :step_options, %{}), step.id, []),
         :ok <-
           checked(
             logical_time(
               record,
               boundary,
               Keyword.put(leaf_opts, :root_options, opts[:root_options])
             ),
             record,
             config
           ),
         root = frame["authority"][frame["run_id"]],
         config =
           Map.put(
             config,
             :max_checkpoint_bytes,
             Authority.minimum(config[:max_checkpoint_bytes], root["checkpoint_limit"])
           ),
         :ok <- checked(read_limit(record, config), record, config) do
      status =
        if frame["cursor"] == "running" do
          {:ok, status} = Writer.step_status(record, config, step.id)
          status
        else
          nil
        end

      {:ok, boundary, record, config, step, status}
    else
      {:error, _, _, _} = error -> error
      {:error, _} = error -> error
      _ -> {:error, :continuation_conflict}
    end
  rescue
    _ -> {:error, :invalid_composition_restore}
  end

  defp checked({:error, reason}, record, config), do: {:error, reason, record, config}
  defp checked(result, _, _), do: result

  # A successful CAS is not permission to consume a late ACK after the attempt's
  # time bounds. Keep the confirmed claim, but reject before any host callback.
  def admission(record, boundary, step, opts) do
    leaf_opts = Map.get(Keyword.get(opts, :step_options, %{}), step.id, [])

    with :ok <-
           logical_time(
             record,
             boundary,
             Keyword.put(leaf_opts, :root_options, opts[:root_options])
           ) do
      execution = record["execution"]
      now = System.system_time(:millisecond)

      cond do
        is_integer(execution["lease_until"]) and execution["lease_until"] <= now ->
          {:error, :lease_expired}

        Enum.any?(
          ~w(deadline_at expires_at),
          &(is_integer(execution[&1]) and execution[&1] <= now)
        ) ->
          {:error, :expired}

        true ->
          :ok
      end
    end
  end

  defp read_limit(record, config) do
    if byte_size(Jason.encode!(record)) <= config.max_checkpoint_bytes,
      do: :ok,
      else: {:error, :checkpoint_limit}
  end

  defp public_reference(ref) when is_map(ref) and not is_struct(ref) do
    keys = [:version, :id, :record_id, :revision, :run_id]

    if Enum.sort(Map.keys(ref)) in [Enum.sort(keys), Enum.sort([:attempt_id | keys])] and
         ref.version === 1 and is_integer(ref.revision) and ref.revision > 0 and
         Enum.all?([ref.id, ref.record_id, ref.run_id], &Record.text?/1) and
         (is_nil(ref[:attempt_id]) or Record.text?(ref.attempt_id)),
       do: :ok,
       else: {:error, :invalid_composition_restore}
  end

  defp public_reference(_), do: {:error, :invalid_composition_restore}

  defp structural_boundary(%{
         "execution" => %{
           "state" => "completed",
           "progress" => %{"runtime" => %{"frame_version" => 10, "cursor" => "completed"}}
         }
       }),
       do: {:ok, :completed}

  defp structural_boundary(%{
         "execution" => %{"progress" => %{"runtime" => %{"frame_version" => 10} = root}} = e
       }) do
    approvals = Map.get(e["progress"], "approvals", %{})

    paused? =
      root["frontier"] == %{
        "state" => "quiescent",
        "reason" => "approval",
        "fatal" => nil,
        "epoch" => root["frontier"]["epoch"]
      }

    open? = root["frontier"]["state"] == "open" and is_nil(root["frontier"]["fatal"])

    if e["state"] == "ready" and root["cursor"] == "running" and (paused? or open?) and
         not Record.unresolved?(e) and (not paused? or approvals != %{}) and
         Enum.all?(approvals, fn {_, a} -> ExAgent.Continuation.Approval.approved?(a) end) and
         Enum.all?(root["children"], fn {_, n} ->
           n["status"] in ~w(completed suspended running)
         end) do
      {:ok, :structural_tree}
    else
      {:error, :unsupported_composition_boundary}
    end
  end

  defp structural_catalog(record, :structural_tree, opts) do
    catalog = Keyword.get(opts, :delegate_definitions, [])

    present =
      Enum.all?(record["execution"]["progress"]["runtime"]["children"], fn {_, node} ->
        node["status"] == "completed" or node["link"]["kind"] == "step" or
          Enum.any?(catalog, fn entry ->
            Enum.all?(
              [:definition, :policy, :model_ref],
              &(entry[&1] === node[Atom.to_string(&1)])
            )
          end)
      end)

    if present, do: :ok, else: {:error, :continuation_delegation_definition_missing}
  end

  defp structural_catalog(_, _, _), do: :ok

  defp sequence_boundary(
         %{
           "execution" => %{"progress" => %{"runtime" => %{"frame_version" => 10}}}
         } = record
       ),
       do: structural_boundary(record)

  defp sequence_boundary(record) do
    frame = record["execution"]["progress"]["runtime"]

    cond do
      frame["frame_version"] not in [7, 8, 9] ->
        {:error, :composition_authority_missing}

      record["execution"]["state"] == "completed" ->
        boundary(record)

      record["execution"]["state"] != "ready" ->
        {:error, :composition_not_ready}

      frame["frame_version"] != 9 ->
        boundary(record)

      frame["cursor"] in ["empty", "between_steps"] ->
        if Enum.any?(frame["children"], fn {_, c} -> c["result_omitted"] != nil end),
          do: {:error, :unsupported_composition_boundary},
          else: {:ok, :between_steps}

      frame["cursor"] == "running" ->
        case sequence_active(record, frame) do
          {:error, _} = error ->
            if length(frame["binding"]["steps"]) == 1, do: boundary(record), else: error

          result ->
            result
        end

      true ->
        {:error, :unsupported_composition_boundary}
    end
  end

  defp sequence_active(record, frame) do
    if ExAgent.Continuation.Retry.plans(record["execution"]) == %{},
      do: sequence_active_evidence(record, frame),
      else: {:error, :unsupported_composition_boundary}
  end

  defp sequence_active_evidence(record, frame) do
    [{id, child}] = Enum.filter(frame["children"], fn {_, c} -> c["status"] == "running" end)
    # Global Record validation precedes this local classification: filtering never
    # conceals orphan effects, broken prefix evidence or ledger corruption.
    view = own_evidence(record, id)
    approvals = view.approvals

    cond do
      approvals != %{} and
        Enum.all?(approvals, fn {_, a} -> ExAgent.Continuation.Approval.approved?(a) end) and
          match?({:ok, _}, Frame.approval_boundary(record, approvals)) ->
        {:ok, :approved_tool_batch}

      not consumed_approvals?(record, view) ->
        {:error, :unsupported_composition_boundary}

      view.tool_batches != %{} ->
        tool_boundary(record, child, view)

      view.effects == %{} ->
        input_boundary(child, view.operations)

      child["frame"]["cursor"] == "response" and
          view.output_resolutions[child["frame"]["model_request_id"]]["decision"] in [
            "retry",
            "succeeded"
          ] ->
        output_boundary(child, view)

      child["frame"]["cursor"] == "response" and
          is_nil(frame["output_resolutions"][child["frame"]["model_request_id"]]) ->
        text_boundary(child, view)

      true ->
        {:error, :unsupported_composition_boundary}
    end
  end

  # This is a private evidence view, never a Frame/Record passed to validators.
  defp own_evidence(record, id) do
    execution = record["execution"]
    frame = execution["progress"]["runtime"]

    %{
      effects:
        Map.filter(execution["effects"], fn {_, e} -> e["intent"]["payload"]["run_id"] == id end),
      operations: Enum.filter(frame["scope"]["operations"], &(&1["run_id"] == id)),
      batches: Enum.filter(frame["scope"]["batches"], &(&1["run_id"] == id)),
      retry_batches: Enum.filter(frame["scope"]["retry_batches"], &(&1["run_id"] == id)),
      tool_batches: Map.filter(frame["tool_batches"], fn {_, b} -> b["run_id"] == id end),
      output_resolutions:
        Map.filter(frame["output_resolutions"], fn {_, e} -> e["run_id"] == id end),
      approvals:
        Map.filter(Map.get(execution["progress"], "approvals", %{}), fn {_, a} ->
          a["run_id"] == id
        end)
    }
  end

  defp consumed_approvals?(record, view) do
    Enum.all?(view.approvals, fn {id, approval} ->
      matches =
        Enum.filter(view.tool_batches, fn {_, batch} ->
          id ==
            "approval-" <>
              elem(
                Record.digest([
                  batch["run_id"],
                  batch["request_id"],
                  "approval",
                  approval["call_id"]
                ]),
                1
              )
        end)

      ExAgent.Continuation.Approval.approved?(approval) and
        case matches do
          [{_, batch}] ->
            Enum.any?(
              ToolEvidence.calls(record, batch),
              &(&1.tool_call_id == approval["call_id"])
            ) and
              final_batch?(record, batch)

          _ ->
            false
        end
    end)
  end

  defp final_batch?(record, batch) do
    calls = ToolEvidence.calls(record, batch)
    resolution = batch["resolution"]

    ids =
      Enum.map(
        calls,
        &ToolEvidence.effect_id(batch["run_id"], batch["request_id"], &1.tool_call_id)
      )

    is_map(resolution) and Enum.map(resolution["calls"], & &1["effect_id"]) == ids and
      Enum.all?(resolution["calls"], fn entry ->
        effect = record["execution"]["effects"][entry["effect_id"]]
        observation = batch["observations"][entry["effect_id"]]

        effect["state"] == "confirmed" and effect["intent"]["kind"] == "tool" and
          effect["outcome"]["data"]["phase"] == "final" and
          effect["outcome"]["status"] not in ["pending", "unknown"] and
          effect["outcome"]["data"]["result_hash"] == entry["result_hash"] and
          observation["application"]["status"] in ["none", "contributed"] and
          observation["presence"] != "omitted"
      end)
  end

  def preflight(definition, reference, opts) do
    with {:ok, config} when not is_nil(config) <-
           Writer.config(
             Map.merge(opts[:continuation] || %{}, %{kind: :composition, composition: definition})
           ),
         true <- reference.id == config.id,
         {:ok, record} <- ExAgent.Store.load_record(config.store, :agent, config.id),
         true <-
           record["record_id"] == reference.record_id and record["revision"] == reference.revision,
         :ok <- Record.validate(record, {config.store.namespace, :agent, config.id}),
         {:ok, boundary} <- boundary(record),
         step when not is_nil(step) <- restore_step(definition, boundary),
         {:ok, status} <- Writer.step_status(record, config, step.id),
         :ok <- host_boundary(boundary, step),
         :ok <- logical_time(record, boundary, opts) do
      root =
        record["execution"]["progress"]["runtime"]["authority"][record["execution"]["run_id"]]

      config =
        Map.put(
          config,
          :max_checkpoint_bytes,
          Authority.minimum(config[:max_checkpoint_bytes], root["checkpoint_limit"])
        )

      with true <- byte_size(Jason.encode!(record)) <= config.max_checkpoint_bytes do
        {:ok, boundary, record, config, step, status}
      else
        _ -> {:error, :checkpoint_limit}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :continuation_conflict}
    end
  rescue
    _ -> {:error, :invalid_composition_restore}
  end

  defp restore_step(definition, :completed), do: List.last(definition.steps)
  defp restore_step(%{steps: [step]}, _), do: step
  defp restore_step(_, _), do: nil

  defp logical_time(_, :completed, _), do: :ok

  defp logical_time(record, _, opts) do
    frame = record["execution"]["progress"]["runtime"]
    utc = System.system_time(:millisecond)
    now = System.monotonic_time(:millisecond)

    expired =
      Enum.any?(frame["authority"], fn {id, a} ->
        relevant =
          id == frame["run_id"] or frame["children"][id]["status"] in ~w(running suspended)

        relevant and is_integer(a["deadline_at"]) and a["deadline_at"] <= utc
      end)

    current = [opts[:deadline], (opts[:root_options] || [])[:deadline]]

    if expired or Enum.any?(current, &(is_integer(&1) and &1 <= now)),
      do: {:error, :deadline_exceeded},
      else: :ok
  end

  def boundary(%{
        "execution" => %{
          "state" => "completed",
          "progress" => %{"runtime" => %{"frame_version" => 10, "cursor" => "completed"}}
        }
      }),
      do: {:ok, :completed}

  def boundary(record) do
    execution = record["execution"]
    frame = execution["progress"]["runtime"]

    cond do
      frame["frame_version"] not in [7, 8, 9] ->
        {:error, :composition_authority_missing}

      execution["state"] == "completed" and frame["cursor"] == "completed" ->
        {:ok, :completed}

      length(frame["binding"]["steps"]) != 1 ->
        {:error, :unsupported_composition_boundary}

      execution["state"] != "ready" ->
        {:error, :composition_not_ready}

      frame["cursor"] != "running" ->
        {:error, :unsupported_composition_boundary}

      frame["frame_version"] in [8, 9] and frame["tool_batches"] != %{} ->
        tool_boundary(record, frame)

      frame["output_resolutions"] != %{} ->
        output_boundary(execution, frame)

      execution["effects"] != %{} ->
        text_boundary(execution, frame)

      true ->
        input_boundary(frame)
    end
  end

  # Record.validate has already bound every call, observation and resolution to
  # the journal/history. Replay only the pure control reducer, never tool machinery.
  defp tool_boundary(record, frame) do
    execution = record["execution"]

    with [%{"status" => "running"} = child] <- Map.values(frame["children"]),
         true <- Map.get(execution["progress"], "approvals", %{}) == %{},
         true <- ExAgent.Continuation.Retry.plans(execution) == %{} do
      tool_boundary(record, child, legacy_evidence(execution, frame))
    else
      _ -> {:error, :unsupported_composition_boundary}
    end
  end

  defp tool_boundary(record, %{"frame" => leaf} = child, view) do
    with true <- leaf["cursor"] in ["response", "batch"],
         true <- view.retry_batches == [],
         true <-
           Enum.all?(view.effects, fn {_, effect} ->
             case effect do
               %{
                 "state" => "confirmed",
                 "intent" => %{"kind" => "model"},
                 "outcome" => %{"status" => "succeeded", "data" => %{"state_available" => true}}
               } ->
                 true

               %{
                 "state" => "confirmed",
                 "intent" => %{"kind" => "tool"},
                 "outcome" => %{"status" => status, "data" => %{"phase" => "final"}}
               } ->
                 status not in ["unknown", "pending"]

               _ ->
                 false
             end
           end),
         true <-
           Enum.all?(view.tool_batches, fn {_, b} -> final_batch?(record, b) end),
         {:ok, messages} <- Message.from_json(child["snapshot"]["message_history"]),
         true <- ExAgent.Retention.executable?(messages),
         {:ok, counts, prefix_count, current} <- tool_control(record, view, leaf),
         true <- counts === leaf["tool_retries"],
         {:ok, boundary} <- tool_current(view.output_resolutions, leaf, messages, current) do
      {:ok, {:confirmed_tool_history, boundary, prefix_count}}
    else
      {:error, {:composition_output_omitted, _}} = error -> error
      _ -> {:error, :unsupported_composition_boundary}
    end
  end

  defp tool_control(record, view, leaf) do
    view.effects
    |> Map.values()
    |> Enum.filter(&(&1["intent"]["kind"] == "model"))
    |> Enum.sort_by(& &1["intent"]["payload"]["step"])
    |> Enum.reduce_while({:ok, %{}, 0, nil}, fn model, {:ok, counts, total, current} ->
      request = model["intent"]["call_id"]

      case view.tool_batches[ToolEvidence.key(leaf["run_id"], request)] do
        nil ->
          {:cont, {:ok, counts, total, current}}

        batch ->
          calls = ToolEvidence.calls(record, batch)
          {next, fatal} = ToolEvidence.reduce_resolution(batch, calls, record, counts)

          if request == leaf["model_request_id"] do
            parts = Enum.map(calls, &Frame.outcome(leaf, &1.tool_call_id))
            selection = %{parts: parts, fatal: fatal, count: length(calls)}
            {:cont, {:ok, next, total, selection}}
          else
            if is_nil(fatal),
              do: {:cont, {:ok, next, total + length(calls), current}},
              else: {:halt, :error}
          end
      end
    end)
  end

  defp tool_current(_, %{"cursor" => "batch"}, _, %{parts: parts} = current) do
    if Enum.all?(parts, &is_struct(&1, Message.Part.ToolReturn)) and
         ExAgent.Retention.executable?([%Message.Request{parts: parts}]),
       do: {:ok, {:confirmed_tool_batch, current}},
       else: {:error, :unsupported_composition_boundary}
  end

  defp tool_current(resolutions, %{"cursor" => "response"} = leaf, messages, nil) do
    case resolutions[leaf["model_request_id"]] do
      nil ->
        {:ok, fingerprint} =
          Record.digest(%{"mode" => "text", "allow_text" => true, "object" => nil, "tools" => []})

        response = List.last(messages)

        if leaf["output_fingerprint"] == fingerprint and is_struct(response, Message.Response) and
             response.finish_reason in [nil, :stop, :end_turn] and
             Message.Response.tool_calls(response) == [] and Message.Response.text(response) != "",
           do: {:ok, :confirmed_text_response},
           else: {:error, :unsupported_composition_boundary}

      entry ->
        output_entry(entry, List.last(messages))
    end
  end

  defp tool_current(_, _, _, _), do: {:error, :unsupported_composition_boundary}

  defp output_entry(entry, response) do
    with true <- entry["decision"] in ["retry", "succeeded"],
         {:ok, _} <- ExAgent.Continuation.OutputResolution.output_config(entry),
         true <- response.finish_reason in [nil, :stop, :end_turn, :tool_calls] do
      case {entry["decision"], entry["result_omitted"]} do
        {"retry", nil} -> {:ok, {:confirmed_output_retry, entry}}
        {"succeeded", nil} -> {:ok, {:confirmed_output_success, entry}}
        {_, marker} -> {:error, {:composition_output_omitted, marker}}
      end
    else
      _ -> {:error, :unsupported_composition_boundary}
    end
  end

  defp host_boundary({:confirmed_tool_history, boundary, _}, step),
    do: host_boundary(boundary, step)

  defp host_boundary(:approved_tool_batch, %{agent: %{output_mode: :tool}}), do: :ok
  defp host_boundary(:approved_tool_batch, _), do: {:error, :unsupported_composition_boundary}

  defp host_boundary({:confirmed_tool_batch, _}, %{agent: %{output_mode: :tool}}), do: :ok

  defp host_boundary({:confirmed_tool_batch, _}, _),
    do: {:error, :unsupported_composition_boundary}

  defp host_boundary(:confirmed_text_response, %{agent: %{output_type: :text, output_mode: :tool}}),
       do: :ok

  defp host_boundary(:confirmed_text_response, _),
    do: {:error, :unsupported_composition_boundary}

  defp host_boundary(
         {:confirmed_output_success, _},
         %{agent: %{output_type: mod, output_mode: :tool}}
       )
       when is_atom(mod) and mod not in [:text, nil], do: :ok

  defp host_boundary({:confirmed_output_success, _}, _),
    do: {:error, :unsupported_composition_boundary}

  defp host_boundary(
         {:confirmed_output_retry, _},
         %{agent: %{output_type: mod, output_mode: :tool}}
       )
       when is_atom(mod) and mod not in [:text, nil], do: :ok

  defp host_boundary({:confirmed_output_retry, _}, _),
    do: {:error, :unsupported_composition_boundary}

  defp host_boundary(_, _), do: :ok

  # Only called after Record.validate has proved the attestation's provenance,
  # selection, exact parts and request/model/ledger binding. No schema reflection.
  defp output_boundary(%{"progress" => _} = execution, frame) do
    with [%{"status" => "running"} = child] <- Map.values(frame["children"]),
         true <- Map.get(execution["progress"], "approvals", %{}) == %{},
         true <- ExAgent.Continuation.Retry.plans(execution) == %{} do
      output_boundary(child, legacy_evidence(execution, frame))
    else
      _ -> {:error, :unsupported_composition_boundary}
    end
  end

  defp output_boundary(%{"frame" => leaf} = child, view) do
    with true <- leaf["cursor"] == "response" and leaf["run_step"] >= 1,
         true <-
           Enum.all?(Map.values(view.effects), fn effect ->
             match?(
               %{
                 "state" => "confirmed",
                 "intent" => %{"kind" => "model"},
                 "outcome" => %{"status" => "succeeded", "data" => %{"state_available" => true}}
               },
               effect
             )
           end),
         true <-
           leaf["outcomes"] == %{} and leaf["tool_retries"] == %{},
         true <-
           Enum.all?(view.operations, &match?(%{"id" => ["model", _]}, &1)),
         true <-
           view.batches == [] and view.retry_batches == [],
         %{"decision" => decision} = entry <-
           view.output_resolutions[leaf["model_request_id"]],
         true <- decision in ["succeeded", "retry"],
         {:ok, _} <- ExAgent.Continuation.OutputResolution.output_config(entry),
         {:ok, messages} <-
           Message.from_json(child["snapshot"]["message_history"]),
         true <- ExAgent.Retention.executable?(messages),
         %Message.Response{} = response <- List.last(messages),
         true <- response.finish_reason in [nil, :stop, :end_turn, :tool_calls] do
      case {decision, entry["result_omitted"]} do
        {"retry", nil} -> {:ok, {:confirmed_output_retry, entry}}
        {"succeeded", nil} -> {:ok, {:confirmed_output_success, entry}}
        {_, marker} -> {:error, {:composition_output_omitted, marker}}
      end
    else
      _ -> {:error, :unsupported_composition_boundary}
    end
  end

  # Record.validate already proves journal/ledger/history/model-state bindings.
  # Classify only the finite, effect-free-to-consume response subset here.
  defp text_boundary(%{"progress" => _} = execution, frame) do
    with [%{"status" => "running"} = child] <- Map.values(frame["children"]),
         true <- Map.get(execution["progress"], "approvals", %{}) == %{},
         true <- ExAgent.Continuation.Retry.plans(execution) == %{} do
      text_boundary(child, legacy_evidence(execution, frame))
    else
      _ -> {:error, :unsupported_composition_boundary}
    end
  end

  defp text_boundary(%{"frame" => leaf} = child, view) do
    with [
           %{
             "state" => "confirmed",
             "intent" => %{"kind" => "model"},
             "outcome" => %{"status" => "succeeded", "data" => %{"state_available" => true}}
           }
         ] <-
           Map.values(view.effects),
         true <- leaf["cursor"] == "response" and leaf["run_step"] == 1,
         true <-
           leaf["outcomes"] == %{} and leaf["tool_retries"] == %{} and
             leaf["output_retries_used"] == 0,
         [%{"id" => ["model", request]}] <- view.operations,
         true <-
           request == leaf["model_request_id"] and view.batches == [] and
             view.retry_batches == [],
         {:ok, fingerprint} <-
           Record.digest(%{
             "mode" => "text",
             "allow_text" => true,
             "object" => nil,
             "tools" => []
           }),
         true <- leaf["output_fingerprint"] == fingerprint,
         {:ok, [%Message.Request{}, %Message.Response{} = response] = messages} <-
           Message.from_json(child["snapshot"]["message_history"]),
         true <- ExAgent.Retention.executable?(messages),
         true <-
           Enum.all?(messages, fn message ->
             Enum.all?(message.parts, fn part ->
               not (is_struct(part, Message.Part.ToolCall) or
                      is_struct(part, Message.Part.ToolReturn) or
                      is_struct(part, Message.Part.Retry))
             end)
           end),
         true <-
           response.finish_reason in [nil, :stop, :end_turn] and
             Message.Response.tool_calls(response) == [] and
             Message.Response.text(response) != "" do
      {:ok, :confirmed_text_response}
    else
      _ -> {:error, :unsupported_composition_boundary}
    end
  end

  defp input_boundary(frame) do
    case Map.values(frame["children"]) do
      [child] -> input_boundary(child, frame["scope"]["operations"])
      _ -> {:error, :unsupported_composition_boundary}
    end
  end

  defp input_boundary(child, operations) do
    case child do
      %{"status" => "running", "frame" => %{"cursor" => "request", "run_step" => 0}} ->
        if operations == [],
          do: {:ok, :input_confirmed},
          else: {:error, :unsupported_composition_boundary}

      _ ->
        {:error, :unsupported_composition_boundary}
    end
  end

  defp legacy_evidence(execution, frame) do
    %{
      effects: execution["effects"],
      operations: frame["scope"]["operations"],
      batches: frame["scope"]["batches"],
      retry_batches: frame["scope"]["retry_batches"],
      tool_batches: frame["tool_batches"],
      output_resolutions: frame["output_resolutions"],
      approvals: Map.get(execution["progress"], "approvals", %{})
    }
  end

  def check_deadline(deadline) do
    if is_integer(deadline) and System.monotonic_time(:millisecond) >= deadline,
      do: {:error, :deadline_exceeded},
      else: :ok
  end

  # Called once at the fresh claim ACK, sharing Writer's elapsed/refund origin.
  def attempt_deadline(record, started_at) do
    e = record["execution"]
    now = System.monotonic_time(:millisecond)
    utc = System.system_time(:millisecond)
    budget = e["progress"]["active_budget"]["reserved_ms"]

    times =
      for k <- ~w(lease_until deadline_at expires_at), is_integer(e[k]), do: now + e[k] - utc

    Enum.min(times ++ if(is_integer(budget), do: [started_at + budget], else: []))
  end
end
