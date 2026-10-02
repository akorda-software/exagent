defmodule ExAgent.Continuation.Frame do
  @moduledoc false
  alias ExAgent.{ExecutionScope, Message, Model, Permissions, Retention, Tool, UsageLimits}

  alias ExAgent.Continuation.{
    Approval,
    Authority,
    Outcome,
    OutputResolution,
    Record,
    ScopeLedger,
    ToolEvidence,
    Retry
  }

  alias ExAgent.Server.Snapshot
  alias ExAgent.Tool.JSON

  @fields ~w(frame_version cursor run_id first_new_message_index run_step model_request_id tool_retries output_retries_used tool_return_bytes selected_tools model_data settings limits permissions scope outcomes output_fingerprint)
  @limits [:max_steps, :max_payload_bytes, :max_history_bytes, :tool_timeout]

  def capture(state, config, cursor, children \\ %{}) do
    with {:ok, scope} <- ExecutionScope.export_node(state.execution_scope),
         {:ok, binding} <- Model.continuation_binding(state.model),
         {:ok, model_data} <- dump_model(state.model, config),
         {:ok, selected} <- inventory(Map.values(state.prepared_tools)),
         {:ok, settings} <- JSON.normalize(Map.from_struct(state.settings)),
         {:ok, limits} <- limits(state),
         {:ok, output_hash} <- output_fingerprint(state.params) do
      frame = %{
        "frame_version" => 3,
        "model_binding" => binding,
        "cursor" => cursor,
        "run_id" => state.run_id,
        "first_new_message_index" => state.first_new_message_index,
        "run_step" => state.run_step,
        "model_request_id" => state.model_request_id,
        "tool_retries" => state.tool_retries,
        "output_retries_used" => state.output_retries_used,
        "tool_return_bytes" => state.tool_return_bytes,
        "selected_tools" => selected,
        "model_data" => model_data,
        "settings" => settings,
        "limits" => limits,
        "permissions" => permissions(state.permissions),
        "scope" => scope,
        "outcomes" => %{},
        "output_fingerprint" => if(state.run_step == 0, do: nil, else: output_hash)
      }

      if state.parent_run_id do
        with :ok <- validate(frame), do: {:ok, frame}
      else
        with {:ok, tree} <- ExecutionScope.export_tree(state.execution_scope) do
          frame =
            frame
            |> Map.put("scope", tree)
            |> Map.put("children", children)

          with :ok <- validate(frame), do: {:ok, frame}
        end
      end
    end
  rescue
    _ -> {:error, :unrepresentable_continuation_frame}
  end

  def capture_structural(run, config) do
    with %{run_id: run_id, execution_scope: %ExecutionScope{} = scope, input: input} <- run,
         true <- scope.run_id === run_id and scope.root_run_id === run_id,
         {:error, :structural_scope_effect} <- ExecutionScope.check_request(scope),
         :ok <- ExecutionScope.check(scope),
         {:ok, binding} <- ExAgent.Coordination.Composition.binding(config.composition),
         {:ok, input} <- JSON.normalize(input),
         {:ok, _} <- JSON.encoded_result(input),
         {:ok, ledger} <- ExecutionScope.export_tree(scope),
         {:ok, authority} <- ExecutionScope.authority(scope),
         frame = %{
           "frame_version" => 10,
           "kind" => "sequence",
           "cursor" => "empty",
           "run_id" => run_id,
           "binding" => binding,
           "input" => input,
           "scope" => ledger,
           "children" => %{},
           "output_resolutions" => %{},
           "tool_batches" => %{},
           "frontier" => %{"epoch" => 0, "state" => "open", "reason" => nil, "fatal" => nil},
           "authority" => %{
             run_id =>
               Map.put(
                 authority,
                 "checkpoint_limit",
                 Map.get(config, :max_checkpoint_bytes, Record.max_bytes())
               )
           }
         },
         frame =
           (if Map.has_key?(binding, "flow_definition_version") do
              frame
              |> Map.put("frame_version", 11)
              |> Map.put("kind", "flow")
              |> Map.put("flow", %{
                "phase" => "idle",
                "selected" => [],
                "failures" => %{},
                "host_error" => nil,
                "result" => nil,
                "result_omitted" => nil
              })
            else
              frame
            end),
         :ok <- validate(frame) do
      {:ok, frame}
    else
      _ -> {:error, :invalid_structural_root}
    end
  end

  defp validate_sequence(frame) do
    with true <-
           Record.exact?(
             frame,
             ~w(frame_version kind cursor run_id binding input scope children output_resolutions tool_batches authority)
           ),
         true <- frame["kind"] == "sequence" and Record.text?(frame["run_id"]),
         :ok <- ExAgent.Coordination.Composition.validate_stored(frame["binding"]),
         :ok <- ScopeLedger.validate(frame["scope"]),
         true <- frame["scope"]["root_run_id"] === frame["run_id"],
         true <- is_map(frame["children"]) and is_map(frame["output_resolutions"]),
         true <- Authority.valid?(frame) and ToolEvidence.valid?(frame),
         true <-
           Enum.all?(frame["tool_batches"], fn {_, batch} ->
             Map.has_key?(frame["children"], batch["run_id"])
           end),
         true <- sequence_prefix?(frame),
         true <-
           Enum.sort(Map.keys(frame["scope"]["nodes"])) ===
             Enum.sort([frame["run_id"] | Map.keys(frame["children"])]),
         true <-
           Enum.all?(~w(operations batches retry_batches), fn key ->
             Enum.all?(frame["scope"][key], &Map.has_key?(frame["children"], &1["run_id"]))
           end),
         true <- Enum.all?(frame["children"], fn {id, child} -> valid_step?(id, child, frame) end),
         true <- output_coverage?(frame),
         {:ok, normalized} <- JSON.normalize(frame),
         true <- normalized === frame,
         true <- byte_size(Jason.encode!(frame)) <= Record.max_bytes() do
      :ok
    else
      _ -> {:error, :invalid_continuation_frame}
    end
  rescue
    _ -> {:error, :invalid_continuation_frame}
  end

  defp sequence_prefix?(frame) do
    children = frame["children"] |> Map.values() |> Enum.sort_by(& &1["link"]["index"])
    count = length(children)
    total = length(frame["binding"]["steps"])
    indices = if count == 0, do: [], else: Enum.to_list(0..(count - 1))

    count <= total and Enum.map(children, & &1["link"]["index"]) === indices and
      Enum.all?(Enum.drop(children, -1), fn child ->
        child["status"] == "completed" and is_nil(child["result_omitted"])
      end) and
      case frame["cursor"] do
        "empty" ->
          count == 0 and frame["output_resolutions"] == %{} and frame["tool_batches"] == %{}

        "running" ->
          count > 0 and List.last(children)["status"] == "running"

        "between_steps" ->
          count > 0 and count < total and List.last(children)["status"] == "completed"

        "completed" ->
          count == total and Enum.all?(children, &(&1["status"] == "completed"))

        _ ->
          false
      end
  end

  defp output_coverage?(frame) do
    Enum.all?(frame["output_resolutions"], fn {request, entry} ->
      is_map(entry) and Record.text?(request) and entry["request_id"] === request and
        Map.has_key?(frame["children"], entry["run_id"])
    end)
  end

  # Grammar is independent of the narrower Record10 certificate below. Neither
  # grammar nor command-level quiescence certifies live worker termination.
  def validate(%{"frame_version" => 11} = frame) do
    with true <-
           Record.exact?(
             frame,
             ~w(frame_version kind cursor run_id binding input scope children output_resolutions tool_batches authority frontier flow)
           ),
         true <- frame["kind"] == "flow" and Record.text?(frame["run_id"]),
         :ok <- ExAgent.Coordination.Flow.validate_stored(frame["binding"]),
         :ok <- durable_tree11(frame),
         true <- flow11?(frame),
         true <- frontier11?(frame),
         {:ok, normalized} <- JSON.normalize(frame),
         true <- normalized === frame,
         true <- byte_size(Jason.encode!(frame)) <= Record.max_bytes() do
      :ok
    else
      _ -> {:error, :invalid_continuation_frame}
    end
  rescue
    _ -> {:error, :invalid_continuation_frame}
  end

  def validate(%{"frame_version" => 10} = frame) do
    with true <-
           Record.exact?(
             frame,
             ~w(frame_version kind cursor run_id binding input scope children output_resolutions tool_batches authority frontier)
           ),
         true <- frame["kind"] == "sequence" and Record.text?(frame["run_id"]),
         :ok <- ExAgent.Coordination.Composition.validate_stored(frame["binding"]),
         true <- is_map(frame["children"]) and map_size(frame["children"]) <= 255,
         true <- not Map.has_key?(frame["children"], frame["run_id"]),
         true <- Enum.all?(Map.keys(frame["children"]), &path10?(&1, frame, MapSet.new(), 0)),
         :ok <- ScopeLedger.validate(frame["scope"]),
         true <- frame["scope"]["root_run_id"] === frame["run_id"],
         true <-
           Enum.sort(Map.keys(frame["scope"]["nodes"])) ===
             Enum.sort([frame["run_id"] | Map.keys(frame["children"])]),
         true <- Authority.valid?(frame),
         true <-
           Enum.all?(~w(operations batches retry_batches), fn key ->
             Enum.all?(frame["scope"][key], &Map.has_key?(frame["children"], &1["run_id"]))
           end),
         true <- Enum.all?(frame["children"], fn {id, node} -> node10?(id, node, frame) end),
         true <- prefix10?(frame),
         true <- ToolEvidence.valid?(frame),
         true <- frontier10?(frame),
         true <- is_map(frame["output_resolutions"]) and output_coverage?(frame),
         {:ok, normalized} <- JSON.normalize(frame),
         true <- normalized === frame,
         true <- byte_size(Jason.encode!(frame)) <= Record.max_bytes() do
      :ok
    else
      _ -> {:error, :invalid_continuation_frame}
    end
  rescue
    _ -> {:error, :invalid_continuation_frame}
  end

  def validate(%{"frame_version" => 9} = frame), do: validate_sequence(frame)

  def validate(%{"frame_version" => 8} = frame) do
    if ToolEvidence.valid?(frame),
      do: validate(frame |> Map.delete("tool_batches") |> Map.put("frame_version", 7)),
      else: {:error, :invalid_tool_evidence}
  end

  def validate(%{"frame_version" => 7} = frame) do
    with true <-
           Record.exact?(
             frame,
             ~w(frame_version kind cursor run_id binding input scope children output_resolutions authority)
           ),
         true <- is_map(frame["children"]) and is_map(frame["output_resolutions"]),
         true <- Authority.valid?(frame),
         true <- byte_size(Jason.encode!(frame)) <= Record.max_bytes() do
      legacy = Map.delete(frame, "authority")

      if frame["cursor"] == "empty" do
        with true <- frame["children"] == %{} and frame["output_resolutions"] == %{},
             do:
               validate(
                 legacy
                 |> Map.drop(~w(children output_resolutions))
                 |> Map.put("frame_version", 4)
               )
      else
        if frame["output_resolutions"] == %{},
          do: validate(legacy |> Map.delete("output_resolutions") |> Map.put("frame_version", 5)),
          else: validate(Map.put(legacy, "frame_version", 6))
      end
    else
      _ -> {:error, :invalid_composition_authority}
    end
  rescue
    _ -> {:error, :invalid_composition_authority}
  end

  def validate(%{"frame_version" => 4} = frame) do
    with true <- Record.exact?(frame, ~w(frame_version kind cursor run_id binding input scope)),
         true <- frame["kind"] === "sequence" and frame["cursor"] === "empty",
         true <- Record.text?(frame["run_id"]),
         :ok <- ExAgent.Coordination.Composition.validate_stored(frame["binding"]),
         :ok <- ScopeLedger.validate(frame["scope"]),
         scope = frame["scope"],
         true <- scope["root_run_id"] === frame["run_id"],
         true <- Map.keys(scope["nodes"]) === [frame["run_id"]],
         true <- Enum.all?(~w(operations batches retry_batches), &(scope[&1] === [])),
         {:ok, normalized} <- JSON.normalize(frame),
         true <- normalized === frame,
         {:ok, _} <- JSON.encoded_result(frame),
         true <- byte_size(Jason.encode!(frame)) <= Record.max_bytes() do
      :ok
    else
      _ -> {:error, :invalid_continuation_frame}
    end
  end

  def validate(%{"frame_version" => version} = frame) when version in [5, 6] do
    with true <-
           Record.exact?(
             frame,
             ~w(frame_version kind cursor run_id binding input scope children) ++
               if(version == 6, do: ["output_resolutions"], else: [])
           ),
         true <-
           version == 5 or
             (is_map(frame["output_resolutions"]) and map_size(frame["output_resolutions"]) > 0),
         true <- frame["kind"] == "sequence" and frame["cursor"] in ~w(running completed),
         true <- Record.text?(frame["run_id"]),
         :ok <- ExAgent.Coordination.Composition.validate_stored(frame["binding"]),
         true <- length(frame["binding"]["steps"]) == 1,
         :ok <- ScopeLedger.validate(frame["scope"]),
         true <- frame["scope"]["root_run_id"] === frame["run_id"],
         true <- is_map(frame["children"]) and map_size(frame["children"]) == 1,
         true <-
           Enum.sort(Map.keys(frame["scope"]["nodes"])) ==
             Enum.sort([frame["run_id"] | Map.keys(frame["children"])]),
         true <-
           Enum.all?(~w(operations batches retry_batches), fn key ->
             Enum.all?(frame["scope"][key], &(&1["run_id"] != frame["run_id"]))
           end),
         true <- Enum.all?(frame["children"], fn {id, child} -> valid_step?(id, child, frame) end),
         {:ok, normalized} <- JSON.normalize(frame),
         true <- normalized === frame,
         true <- byte_size(Jason.encode!(frame)) <= Record.max_bytes() do
      :ok
    else
      _ -> {:error, :invalid_continuation_frame}
    end
  rescue
    _ -> {:error, :invalid_continuation_frame}
  end

  def validate(frame) do
    with true <-
           Record.exact?(
             frame,
             fields(frame)
           ) and frame["frame_version"] in [1, 2, 3],
         :ok <- scope_version(frame),
         true <- frame["cursor"] in ~w(request response batch finish),
         true <- Record.text?(frame["run_id"]),
         true <-
           Enum.all?(
             ~w(first_new_message_index run_step output_retries_used),
             &Record.counter?(frame[&1])
           ),
         true <- is_nil(frame["model_request_id"]) or Record.text?(frame["model_request_id"]),
         true <-
           Enum.all?(
             ~w(tool_retries selected_tools settings limits permissions scope outcomes),
             &is_map(frame[&1])
           ),
         true <- Retention.limit?(frame["tool_return_bytes"]),
         true <-
           Enum.all?(frame["tool_retries"], fn {name, count} ->
             Record.text?(name) and Record.counter?(count)
           end),
         true <- Record.counter?(frame["limits"]["output_retries"]),
         {:ok, normalized} <- JSON.normalize(frame),
         true <- normalized === frame,
         true <- byte_size(Jason.encode!(Map.get(frame, "model_binding"))) <= 4096,
         true <- byte_size(Jason.encode!(frame)) <= Record.max_bytes() do
      :ok
    else
      _ -> {:error, :invalid_continuation_frame}
    end
  end

  defp fields(%{"frame_version" => 3} = frame),
    do:
      @fields ++
        ["model_binding"] ++ if(Map.has_key?(frame, "children"), do: ["children"], else: [])

  defp fields(%{"frame_version" => 2}), do: @fields ++ ["children"]
  defp fields(_), do: @fields

  defp path10?(id, root, seen, depth) do
    cond do
      id === root["run_id"] ->
        depth <= 16

      depth >= 16 or MapSet.member?(seen, id) ->
        false

      not Record.text?(id) or not is_map(root["children"][id]) ->
        false

      true ->
        path10?(root["children"][id]["parent_run_id"], root, MapSet.put(seen, id), depth + 1)
    end
  end

  defp durable_tree11(frame) do
    with true <- is_map(frame["children"]) and map_size(frame["children"]) <= 255,
         false <- Map.has_key?(frame["children"], frame["run_id"]),
         true <- Enum.all?(Map.keys(frame["children"]), &path10?(&1, frame, MapSet.new(), 0)),
         :ok <- ScopeLedger.validate(frame["scope"]),
         true <- frame["scope"]["root_run_id"] === frame["run_id"],
         true <-
           Enum.sort(Map.keys(frame["scope"]["nodes"])) ===
             Enum.sort([frame["run_id"] | Map.keys(frame["children"])]),
         true <- Authority.valid?(frame),
         true <-
           Enum.all?(~w(operations batches retry_batches), fn k ->
             Enum.all?(frame["scope"][k], &Map.has_key?(frame["children"], &1["run_id"]))
           end),
         true <- Enum.all?(frame["children"], fn {id, node} -> node10?(id, node, frame) end),
         true <- ToolEvidence.valid?(frame),
         true <- is_map(frame["output_resolutions"]) and output_coverage?(frame) do
      :ok
    else
      _ -> {:error, :invalid_continuation_frame}
    end
  end

  defp flow11?(root) do
    f = root["flow"]
    ids = Enum.map(root["binding"]["steps"], & &1["id"])
    nodes = Enum.filter(root["children"], fn {_, n} -> n["link"]["kind"] == "step" end)
    selected = f["selected"]

    Record.exact?(f, ~w(phase selected failures host_error result result_omitted)) and
      is_list(selected) and selected === Enum.filter(ids, &(&1 in selected)) and
      length(selected) == MapSet.size(MapSet.new(selected)) and
      (selected == [] or root["binding"]["kind"] != "router" or length(selected) == 1) and
      (selected == [] or root["binding"]["kind"] != "parallel" or selected === ids) and
      length(nodes) == MapSet.size(MapSet.new(nodes, fn {_, n} -> n["link"]["step_id"] end)) and
      Enum.all?(nodes, fn {_, n} -> n["link"]["step_id"] in selected end) and
      Enum.all?(nodes, fn {_, n} ->
        n["status"] != "completed" or
          (is_nil(n["result_omitted"]) and
             byte_size(Jason.encode!(n["result"])) <= root["binding"]["max_branch_result_bytes"])
      end) and
      is_map(f["failures"]) and
      Enum.all?(f["failures"], fn {id, fatal} ->
        id in selected and fatal10?(fatal, root) and branch_id11(root, fatal["run_id"]) == id
      end) and
      Retention.marker!(f["result_omitted"]) === f["result_omitted"] and
      (is_nil(f["result_omitted"]) or is_nil(f["result"])) and
      (is_nil(f["result_omitted"]) or host_failure11?(root)) and
      (is_nil(f["host_error"]) or host_failure11?(root)) and
      case {f["phase"], root["cursor"]} do
        {phase, "empty"} when phase in ~w(idle selecting) ->
          root["children"] == %{} and selected == [] and is_nil(f["result"])

        {"running", "running"} ->
          selected != [] and is_nil(f["result"])

        {"merging", "running"} ->
          selected != [] and terminal_branches11?(root) and is_nil(f["result"])

        {"completed", "completed"} ->
          terminal_branches11?(root) and is_nil(f["result_omitted"]) and
            match?({:ok, _}, JSON.normalize(f["result"])) and
            byte_size(Jason.encode!(f["result"])) <= root["binding"]["max_result_bytes"]

        {"failed", "failed"} ->
          root["frontier"]["reason"] == "fatal" and
            (is_nil(f["host_error"]) or host_failure11?(root))

        _ ->
          false
      end
  end

  @doc false
  def branch_id11(root, id) do
    case root["children"][id] do
      %{"link" => %{"kind" => "step", "step_id" => branch}} -> branch
      %{"parent_run_id" => parent} -> branch_id11(root, parent)
      _ -> nil
    end
  end

  @doc false
  def terminal_branches11?(root) do
    Enum.all?(root["flow"]["selected"], fn id ->
      Enum.any?(root["children"], fn {_, n} ->
        n["link"]["step_id"] == id and n["status"] in ~w(completed failed cancelled)
      end)
    end)
  end

  defp frontier11?(root) do
    f = root["frontier"]

    Record.exact?(f, ~w(epoch state reason fatal)) and Record.counter?(f["epoch"]) and
      case {f["state"], f["reason"], f["fatal"]} do
        {"open", nil, nil} ->
          Enum.all?(root["children"], fn {_, n} ->
            n["status"] in ~w(running completed failed cancelled)
          end)

        {state, reason, fatal}
        when state in ~w(draining quiescent) and reason in ~w(approval fatal) ->
          f["epoch"] > 0 and
            if(reason == "approval", do: is_nil(fatal), else: fatal10?(fatal, root)) and
            (state != "quiescent" or
               Enum.all?(root["children"], fn {_, n} ->
                 n["status"] in ~w(suspended completed failed cancelled)
               end))

        _ ->
          false
      end
  end

  defp node10?(id, node, root) do
    Record.exact?(
      node,
      ~w(parent_run_id link definition policy model_ref output_ref frame snapshot status result result_omitted error)
    ) and
      Enum.all?(~w(definition policy model_ref), &Record.reference?(node[&1])) and
      node["parent_run_id"] === root["scope"]["nodes"][id]["parent_run_id"] and
      node["frame"]["frame_version"] === 3 and node["frame"]["run_id"] === id and
      not Map.has_key?(node["frame"], "children") and validate(node["frame"]) == :ok and
      node_scope_matches?(node["frame"]["scope"], root["scope"], id) and
      Retention.marker!(node["result_omitted"]) === node["result_omitted"] and
      (is_nil(node["result_omitted"]) or is_nil(node["result"])) and
      node_status10?(node) and descendants10?(id, node, root) and link10?(id, node, root)
  end

  defp descendants10?(id, node, root) do
    Enum.all?(root["children"], fn {_, child} ->
      child["parent_run_id"] != id or
        case node["status"] do
          "running" -> true
          "suspended" -> child["status"] in ~w(suspended completed failed cancelled)
          _ -> child["status"] in ~w(completed failed cancelled)
        end
    end)
  end

  defp node_status10?(node) do
    case node["status"] do
      "completed" ->
        node["frame"]["cursor"] == "finish" and is_nil(node["error"])

      status when status in ~w(running suspended) ->
        node["frame"]["cursor"] != "finish" and
          Enum.all?(~w(result result_omitted error), &is_nil(node[&1]))

      status when status in ~w(failed cancelled) ->
        node["frame"]["cursor"] != "finish" and is_nil(node["result"]) and
          is_nil(node["result_omitted"]) and not is_nil(node["error"]) and
          ToolEvidence.error?(node["error"])

      _ ->
        false
    end
  end

  defp link10?(_id, %{"link" => %{"kind" => "step"} = link} = node, root) do
    with true <- Record.exact?(link, ~w(kind step_id index input)),
         true <- Record.counter?(link["index"]),
         step when is_map(step) <- Enum.at(root["binding"]["steps"], link["index"]) do
      previous =
        Enum.find_value(root["children"], fn {_, n} ->
          if n["link"]["kind"] == "step" and n["link"]["index"] === link["index"] - 1, do: n
        end)

      input =
        if root["frame_version"] == 11 or link["index"] == 0,
          do: root["input"],
          else: previous["result"]

      node["parent_run_id"] === root["run_id"] and link["step_id"] === step["id"] and
        (step["input_kind"] == "host" or link["input"] === input) and
        Enum.all?(~w(definition policy model_ref output_ref), &(node[&1] === step[&1]))
    else
      _ -> false
    end
  end

  defp link10?(id, %{"link" => %{"kind" => "delegate"} = link} = node, root) do
    parent = node["parent_run_id"]
    batch = root["tool_batches"][ToolEvidence.key(parent, link["parent_request_id"])]
    call = batch["calls"][link["call_id"]]

    Record.exact?(link, ~w(kind parent_request_id call_id tool_name call_hash schema_hash args)) and
      Enum.all?(~w(parent_request_id call_id tool_name), &Record.text?(link[&1])) and
      is_nil(node["output_ref"]) and Map.has_key?(root["children"], parent) and
      call["source"] === %{"kind" => "child", "id" => id} and
      call["binding"] === Map.take(link, ~w(tool_name args schema_hash call_hash))
  end

  defp link10?(_, _, _), do: false

  defp prefix10?(root) do
    steps =
      root["children"]
      |> Map.values()
      |> Enum.filter(&(&1["link"]["kind"] == "step"))
      |> Enum.sort_by(& &1["link"]["index"])

    count = length(steps)
    total = length(root["binding"]["steps"])
    indices = if count == 0, do: [], else: Enum.to_list(0..(count - 1))

    count <= total and Enum.map(steps, & &1["link"]["index"]) === indices and
      Enum.all?(
        Enum.drop(steps, -1),
        &(&1["status"] == "completed" and is_nil(&1["result_omitted"]))
      ) and
      case root["cursor"] do
        "empty" ->
          root["children"] == %{} and root["tool_batches"] == %{} and
            root["output_resolutions"] == %{}

        "running" ->
          count > 0 and
            (List.last(steps)["status"] in ~w(running suspended) or
               (List.last(steps)["status"] == "failed" and
                  root["frontier"]["state"] == "draining" and
                  root["frontier"]["reason"] == "fatal"))

        "between_steps" ->
          count > 0 and count < total and List.last(steps)["status"] == "completed"

        "completed" ->
          count == total and
            Enum.all?(root["children"], fn {_, n} -> n["status"] == "completed" end)

        "failed" ->
          root["frontier"]["state"] == "quiescent" and root["frontier"]["reason"] == "fatal"

        _ ->
          false
      end
  end

  defp frontier10?(root) do
    f = root["frontier"]

    Record.exact?(f, ~w(epoch state reason fatal)) and Record.counter?(f["epoch"]) and
      case {f["state"], f["reason"], f["fatal"]} do
        {"open", nil, nil} ->
          Enum.all?(root["children"], fn {_, n} -> n["status"] in ~w(running completed) end)

        {state, reason, fatal}
        when state in ~w(draining quiescent) and reason in ~w(approval fatal) ->
          f["epoch"] > 0 and
            if(reason == "approval", do: is_nil(fatal), else: fatal10?(fatal, root)) and
            (state != "quiescent" or
               (Enum.all?(root["children"], fn {_, n} ->
                  n["status"] in ~w(suspended completed failed cancelled)
                end) and
                  Enum.all?(root["tool_batches"], fn {_, b} ->
                    Enum.all?(b["calls"], fn {_, c} ->
                      c["state"] not in ~w(preparing dispatching wrapping)
                    end)
                  end)))

        _ ->
          false
      end
  end

  defp fatal10?(fatal, root) do
    not is_nil(fatal["error"]) and ToolEvidence.error?(fatal["error"]) and
      case fatal["kind"] do
        "root" ->
          Record.exact?(fatal, ~w(kind error))

        "node" ->
          Record.exact?(fatal, ~w(kind run_id error)) and
            Map.has_key?(root["children"], fatal["run_id"]) and
            root["children"][fatal["run_id"]]["error"] === fatal["error"]

        "batch" ->
          batch = root["tool_batches"][ToolEvidence.key(fatal["run_id"], fatal["request_id"])]

          root["frame_version"] == 11 and Record.exact?(fatal, ~w(kind run_id request_id error)) and
            is_nil(batch["consumption"]) and not is_nil(batch["resolution"]["error"]) and
            batch["resolution"]["error"] === fatal["error"]

        "call" ->
          call =
            root["tool_batches"][ToolEvidence.key(fatal["run_id"], fatal["request_id"])]["calls"][
              fatal["call_id"]
            ]

          Record.exact?(fatal, ~w(kind run_id request_id call_id error)) and
            ((call["state"] == "settled" and call["control"]["retry"] === false and
                call["control"]["error"] === fatal["error"]) or
               (call["state"] in ~w(dispatching blocked) and
                  ToolEvidence.raw_fatal10?(call) and
                  call["raw"]["control"]["error"] === fatal["error"]))

        _ ->
          false
      end
  end

  def validate_binding(frame, model) do
    with {:ok, binding} <- Model.continuation_binding(model) do
      if binding === Map.get(frame, "model_binding"),
        do: :ok,
        else: {:error, :continuation_model_binding_changed}
    end
  end

  defp load_bound_model(template, frame, config) do
    with :ok <- validate_binding(frame, template),
         {:ok, model} <- load_model(template, frame["model_data"], config),
         :ok <- validate_binding(frame, model),
         do: {:ok, model}
  end

  defp scope_version(%{"frame_version" => 1, "scope" => %{"scope_version" => 1}}),
    do: :ok

  defp scope_version(%{"frame_version" => 3, "scope" => %{"scope_version" => 1}} = frame) do
    if Map.has_key?(frame, "children"), do: {:error, :invalid_continuation_frame}, else: :ok
  end

  defp scope_version(%{
         "frame_version" => version,
         "scope" => scope,
         "run_id" => run_id,
         "children" => children
       })
       when version in [2, 3] do
    with :ok <- ScopeLedger.validate(scope),
         true <- scope["root_run_id"] === run_id and is_map(children),
         true <- Enum.sort(Map.keys(scope["nodes"])) == Enum.sort([run_id | Map.keys(children)]),
         true <- Enum.all?(children, fn {id, child} -> valid_child?(id, child, scope) end),
         bindings =
           Enum.map(children, fn {_, child} ->
             {child["parent_run_id"], child["parent_request_id"], child["call"]["call_id"]}
           end),
         true <- length(bindings) == MapSet.size(MapSet.new(bindings)) do
      :ok
    else
      _ -> {:error, :invalid_continuation_frame}
    end
  end

  defp scope_version(_), do: {:error, :invalid_continuation_frame}

  defp valid_child?(id, child, scope) do
    Record.exact?(
      child,
      ~w(parent_run_id parent_request_id parent_response parent_result call definition policy model_ref deadline_at frame snapshot result result_omitted outcome status)
    ) and
      child["parent_run_id"] === scope["nodes"][id]["parent_run_id"] and
      Record.text?(child["parent_request_id"]) and
      is_binary(child["parent_response"]) and
      (is_nil(child["parent_result"]) or is_binary(child["parent_result"])) and
      Enum.all?(~w(definition policy model_ref), &Record.reference?(child[&1])) and
      Record.nullable_timestamp?(child["deadline_at"]) and
      child["status"] in ~w(running paused completed) and
      Record.exact?(child["call"], ~w(call_id tool_name args schema_hash call_hash)) and
      Enum.all?(~w(call_id tool_name schema_hash call_hash), &Record.text?(child["call"][&1])) and
      is_map(child["call"]["args"]) and child["frame"]["run_id"] === id and
      child["frame"]["frame_version"] in [1, 3] and not Map.has_key?(child["frame"], "children") and
      validate(child["frame"]) == :ok and
      node_scope_matches?(child["frame"]["scope"], scope, id) and
      ((child["status"] == "completed" and child["frame"]["cursor"] == "finish") or
         (child["status"] != "completed" and is_nil(child["parent_result"]) and
            is_nil(child["result"]) and
            is_nil(child["result_omitted"]) and is_nil(child["outcome"])))
  end

  defp valid_step?(id, child, root) do
    index = if root["frame_version"] == 9, do: child["link"]["index"], else: 0
    step = Enum.at(root["binding"]["steps"], index)

    previous =
      Enum.find_value(root["children"], fn {_, c} ->
        if c["link"]["index"] == index - 1, do: c
      end)

    input = if index == 0, do: root["input"], else: previous["result"]

    Record.exact?(
      child,
      ~w(parent_run_id link definition policy model_ref output_ref frame snapshot status result result_omitted)
    ) and
      Record.text?(id) and child["parent_run_id"] === root["run_id"] and
      root["scope"]["nodes"][id]["parent_run_id"] === root["run_id"] and
      Record.exact?(child["link"], ~w(kind step_id index input)) and
      child["link"]["kind"] === "step" and child["link"]["index"] === index and
      child["link"]["step_id"] === step["id"] and
      (step["input_kind"] == "host" or child["link"]["input"] === input) and
      Enum.all?(~w(definition policy model_ref output_ref), &(child[&1] === step[&1])) and
      child["frame"]["frame_version"] === 3 and child["frame"]["run_id"] === id and
      not Map.has_key?(child["frame"], "children") and validate(child["frame"]) == :ok and
      node_scope_matches?(child["frame"]["scope"], root["scope"], id) and
      Retention.marker!(child["result_omitted"]) === child["result_omitted"] and
      (is_nil(child["result_omitted"]) or is_nil(child["result"])) and
      ((child["status"] == "running" and root["cursor"] == "running" and is_nil(child["result"]) and
          (root["frame_version"] != 9 or is_nil(child["result_omitted"]))) or
         (child["status"] == "completed" and
            (root["frame_version"] == 9 or root["cursor"] == "completed") and
            child["frame"]["cursor"] == "finish"))
  end

  # Immutable definition/input/link boundaries are checked on every mutation,
  # not just when a self-consistent record is decoded.
  def step_transition(previous, current, "tool_resolution") do
    with true <-
           previous["frame_version"] in [8, 9] and
             current["frame_version"] == previous["frame_version"],
         :ok <- validate(current),
         true <- ToolEvidence.transition?(previous, current, "tool_resolution"),
         changes =
           Enum.filter(current["tool_batches"], fn {key, batch} ->
             batch !== previous["tool_batches"][key]
           end),
         [{key, batch}] <- changes,
         true <-
           is_nil(previous["tool_batches"][key]["resolution"]) and not is_nil(batch["resolution"]),
         id = batch["run_id"],
         expected =
           previous
           |> Map.put("tool_batches", current["tool_batches"])
           |> put_in(
             ["children", id, "frame", "tool_retries"],
             current["children"][id]["frame"]["tool_retries"]
           ),
         true <- current === expected do
      :ok
    else
      _ -> {:error, :invalid_tool_resolution}
    end
  rescue
    _ -> {:error, :invalid_tool_resolution}
  end

  def step_transition(previous, current, "output_resolution") do
    with :ok <- validate(current),
         true <-
           (previous["frame_version"] in [5, 6] and current["frame_version"] == 6) or
             (previous["frame_version"] in [7, 8, 9] and
                current["frame_version"] == previous["frame_version"]),
         true <-
           Map.drop(previous, ~w(frame_version output_resolutions)) ===
             Map.drop(current, ~w(frame_version output_resolutions)),
         old = Map.get(previous, "output_resolutions", %{}),
         new = current["output_resolutions"],
         true <- map_size(new) == map_size(old) + 1,
         true <- Map.take(new, Map.keys(old)) === old,
         true <- OutputResolution.addition?(previous, current) do
      :ok
    else
      _ -> {:error, :invalid_output_resolution}
    end
  end

  def step_transition(%{"frame_version" => 9} = previous, current, operation) do
    with :ok <- validate(current),
         true <- current["frame_version"] === 9,
         true <- ToolEvidence.transition?(previous, current, operation),
         true <-
           Map.drop(previous, ~w(cursor scope children authority tool_batches)) ===
             Map.drop(current, ~w(cursor scope children authority tool_batches)),
         true <- authority_transition?(previous, current, operation),
         id when is_binary(id) <- active_step_id(current),
         child = current["children"][id] do
      if operation == "step_input" do
        valid =
          previous["cursor"] in ["empty", "between_steps"] and current["cursor"] == "running" and
            map_size(current["children"]) == map_size(previous["children"]) + 1 and
            Map.take(current["children"], Map.keys(previous["children"])) === previous["children"] and
            child["frame"]["run_step"] == 0 and child["frame"]["cursor"] == "request" and
            Map.drop(current["scope"], ["nodes"]) === Map.drop(previous["scope"], ["nodes"]) and
            Map.take(current["scope"]["nodes"], Map.keys(previous["scope"]["nodes"])) ===
              previous["scope"]["nodes"]

        if valid, do: :ok, else: {:error, :invalid_step_transition}
      else
        old = previous["children"][id]

        mutable =
          if operation == "step_output",
            do: ~w(frame snapshot status result result_omitted),
            else: ~w(frame snapshot)

        terminal_cursor =
          if map_size(current["children"]) == length(current["binding"]["steps"]),
            do: "completed",
            else: "between_steps"

        valid =
          previous["cursor"] == "running" and id === active_step_id(previous) and
            Map.delete(previous["children"], id) === Map.delete(current["children"], id) and
            Map.drop(old, mutable) === Map.drop(child, mutable) and old["status"] == "running" and
            (old["frame"]["run_step"] != 0 or child["frame"]["run_step"] != 0 or
               child["frame"]["model_data"] === old["frame"]["model_data"]) and
            if(operation == "step_output",
              do:
                current["cursor"] == terminal_cursor and child["status"] == "completed" and
                  old["frame"]["cursor"] in ~w(response batch) and
                  Enum.all?(
                    ~w(model_request_id run_step model_data),
                    &(child["frame"][&1] === old["frame"][&1])
                  ),
              else: current["cursor"] == "running"
            )

        if valid, do: :ok, else: {:error, :invalid_step_transition}
      end
    else
      _ -> {:error, :invalid_step_transition}
    end
  rescue
    _ -> {:error, :invalid_step_transition}
  end

  def step_transition(previous, current, operation) do
    with :ok <- validate(current),
         true <- ToolEvidence.transition?(previous, current, operation),
         true <-
           Map.drop(previous, ~w(frame_version cursor scope children authority tool_batches)) ===
             Map.drop(current, ~w(frame_version cursor scope children authority tool_batches)),
         true <- authority_transition?(previous, current, operation),
         [{id, child}] <- Map.to_list(current["children"]) do
      case operation do
        "step_input" ->
          if ((previous["frame_version"] == 4 and current["frame_version"] == 5) or
                (previous["frame_version"] in [7, 8] and
                   current["frame_version"] == previous["frame_version"] and
                   previous["cursor"] == "empty")) and
               child["frame"]["run_step"] == 0 and current["scope"]["operations"] == [] and
               current["cursor"] == "running", do: :ok, else: {:error, :invalid_step_transition}

        _ ->
          old = previous["children"][id]

          mutable =
            if operation == "step_output",
              do: ~w(frame snapshot status result result_omitted),
              else: ~w(frame snapshot)

          valid =
            previous["frame_version"] in [5, 6, 7, 8] and
              current["frame_version"] == previous["frame_version"] and
              Map.keys(previous["children"]) == [id] and
              Map.drop(old, mutable) === Map.drop(child, mutable) and old["status"] == "running" and
              (old["frame"]["run_step"] != 0 or child["frame"]["run_step"] != 0 or
                 child["frame"]["model_data"] === old["frame"]["model_data"]) and
              if(operation == "step_output",
                do:
                  current["cursor"] == "completed" and
                    old["frame"]["cursor"] in ~w(response batch) and
                    child["frame"]["model_request_id"] === old["frame"]["model_request_id"] and
                    child["frame"]["run_step"] === old["frame"]["run_step"] and
                    child["frame"]["model_data"] === old["frame"]["model_data"],
                else: current["cursor"] == previous["cursor"]
              )

          if valid, do: :ok, else: {:error, :invalid_step_transition}
      end
    else
      _ -> {:error, :invalid_step_transition}
    end
  rescue
    _ -> {:error, :invalid_step_transition}
  end

  defp authority_transition?(%{"frame_version" => version} = old, current, operation)
       when version in [7, 8, 9] do
    original = old["authority"]

    if operation == "step_input" do
      Map.take(current["authority"], Map.keys(original)) === original
    else
      current["authority"] === original and
        Enum.all?(old["children"], fn {id, child} ->
          child["frame"]["limits"] === current["children"][id]["frame"]["limits"]
        end)
    end
  end

  defp authority_transition?(_, current, _), do: current["frame_version"] not in [7, 8, 9]

  def active_step_id(%{"frame_version" => 10} = frame) do
    frame["children"]
    |> Enum.filter(fn {_, node} -> node["link"]["kind"] == "step" end)
    |> Enum.max_by(fn {_, node} -> node["link"]["index"] end, fn -> nil end)
    |> case do
      {id, _} -> id
      nil -> nil
    end
  end

  def active_step_id(frame) do
    case Enum.max_by(frame["children"], fn {_, c} -> c["link"]["index"] end, fn -> nil end) do
      {id, _} -> id
      nil -> nil
    end
  end

  def structural_evidence(
        %{"execution" => %{"progress" => %{"runtime" => %{"frame_version" => version} = root}}} =
          record
      )
      when version in [10, 11] do
    e = record["execution"]

    with :ok <- validate(root),
         true <-
           if(version == 11,
             do: call_fatal_frontier11?(record),
             else: call_fatal_frontier10?(record)
           ),
         true <- root["cursor"] in ~w(empty running between_steps completed failed),
         true <- root["cursor"] == "completed" == (e["state"] == "completed"),
         true <- root["cursor"] == "failed" == (e["state"] == "failed"),
         true <- if(version == 11, do: failed_closure11?(record), else: failed_closure10?(record)),
         true <- successful_closure10?(record),
         true <- root["scope"]["retry_batches"] == [],
         true <- OutputResolution.coverage?(record),
         true <-
           root["frontier"]["state"] != "quiescent" or
             (not Record.unresolved?(e) and
                Enum.all?(root["tool_batches"], fn {_, b} ->
                  Enum.all?(b["calls"], fn {_, c} ->
                    c["state"] in ~w(approval child settled blocked)
                  end)
                end)),
         true <-
           e["state"] in ~w(claimed completed) or
             recovered_flow_drain11?(e) or
             (e["state"] in ~w(ready uncertain expired) and root["frontier"]["state"] == "open") or
             (e["state"] == "ready" and root["cursor"] == "empty") or
             root["frontier"]["state"] == "quiescent",
         :ok <- graph_evidence(record),
         true <- ToolEvidence.evidence?(record),
         true <- approvals10?(record),
         true <-
           Enum.all?(root["children"], fn {id, child} ->
             child["status"] in ~w(running suspended completed failed cancelled) and
               node_evidence10?(record, id, child)
           end) do
      :ok
    else
      _ -> {:error, :invalid_step_evidence}
    end
  rescue
    _ -> {:error, :invalid_step_evidence}
  end

  def structural_evidence(record), do: structural_evidence_legacy(record)

  defp call_fatal_frontier11?(record) do
    root = record["execution"]["progress"]["runtime"]

    root["flow"]["failures"] === ToolEvidence.branch_fatals11(record) and
      if host_failure11?(root) do
        record["execution"]["state"] == "failed" and root["frontier"]["state"] == "quiescent"
      else
        if root["binding"]["failure_policy"] == "fail_fast" and root["flow"]["failures"] != %{} do
          call_fatal_frontier10?(record)
        else
          is_nil(root["frontier"]["fatal"]) and root["frontier"]["reason"] != "fatal"
        end
      end
  end

  defp host_failure11?(root) do
    h = root["flow"]["host_error"]
    marker = root["flow"]["result_omitted"]

    Record.exact?(h, ~w(phase error)) and h["phase"] in ~w(selecting merging) and
      not is_nil(h["error"]) and ToolEvidence.error?(h["error"]) and
      h["error"]["omitted"] === marker and
      (is_nil(marker) or
         (h["phase"] == "merging" and marker["boundary"] == "output" and
            marker["limit"] === root["binding"]["max_result_bytes"] and
            marker["bytes"] > marker["limit"])) and
      root["flow"]["phase"] == "failed" and
      root["frontier"]["fatal"] === %{"kind" => "root", "error" => h["error"]} and
      if h["phase"] == "selecting",
        do: root["children"] == %{} and root["flow"]["selected"] == [],
        else: terminal_branches11?(root)
  end

  @doc false
  def host_closable11?(record) do
    root = record["execution"]["progress"]["runtime"]

    root["frame_version"] == 11 and
      Enum.all?(record["execution"]["effects"], fn {_, e} ->
        e["state"] == "confirmed" and e["outcome"]["status"] != "unknown"
      end) and
      Enum.all?(root["tool_batches"], fn {_, b} ->
        Enum.all?(b["calls"], fn {_, c} -> c["state"] in ~w(settled blocked) end)
      end)
  end

  defp failed_closure11?(record) do
    root = record["execution"]["progress"]["runtime"]

    Enum.all?(root["children"], fn {id, n} ->
      n["status"] not in ~w(failed cancelled) or branch_failure11?(root, id, n) or
        (record["execution"]["state"] == "failed" and n["status"] == "cancelled" and
           n["error"] === root["frontier"]["fatal"]["error"])
    end) and
      Enum.all?(root["tool_batches"], fn {_, b} ->
        Enum.all?(b["calls"], fn {_, c} ->
          c["state"] != "blocked" or
            Map.has_key?(root["flow"]["failures"], branch_id11(root, b["run_id"])) or
            record["execution"]["state"] == "failed"
        end)
      end) and
      (record["execution"]["state"] != "failed" or call_fatal_closable10?(record) or
         (host_failure11?(root) and host_closable11?(record)))
  end

  defp branch_failure11?(root, id, node) do
    fatal = root["flow"]["failures"][branch_id11(root, id)]
    is_map(fatal) and fatal10?(fatal, root) and node["error"] === fatal["error"]
  end

  @doc false
  def branch_closable11?(record, branch) do
    root = record["execution"]["progress"]["runtime"]
    fatal = root["flow"]["failures"][branch]

    is_map(fatal) and fatal10?(fatal, root) and branch_drained11?(record, branch)
  end

  @doc false
  def branch_drained11?(record, branch) do
    root = record["execution"]["progress"]["runtime"]

    root["frame_version"] == 11 and
      Enum.all?(record["execution"]["effects"], fn {_, e} ->
        branch_id11(root, e["intent"]["payload"]["run_id"]) != branch or
          (e["state"] == "confirmed" and e["outcome"]["status"] != "unknown")
      end) and
      Enum.all?(root["tool_batches"], fn {_, b} ->
        branch_id11(root, b["run_id"]) != branch or
          Enum.all?(b["calls"], fn {_, c} ->
            c["state"] not in ~w(preparing wrapping) and
              (c["state"] != "dispatching" or not is_nil(c["raw"]))
          end)
      end)
  end

  defp call_fatal_frontier10?(record) do
    root = record["execution"]["progress"]["runtime"]

    case ToolEvidence.selected_call_fatal10(record) do
      nil ->
        is_nil(root["frontier"]["fatal"]) and root["frontier"]["reason"] != "fatal"

      fatal ->
        root["frontier"]["fatal"] === fatal and root["frontier"]["reason"] == "fatal" and
          ({root["frontier"]["state"], record["execution"]["state"]} in [
             {"draining", "claimed"},
             {"quiescent", "failed"}
           ] or recovered_flow_drain11?(record["execution"])) and
          Enum.all?(root["tool_batches"], fn {_, batch} ->
            Enum.all?(batch["calls"], fn {_, call} ->
              is_nil(call["control"]["error"]) or call["control"]["retry"] === true or
                (is_nil(batch["resolution"]) and is_nil(batch["consumption"]) and
                   root["children"][batch["run_id"]]["frame"]["model_request_id"] ==
                     batch["request_id"])
            end)
          end)
    end
  end

  @doc false
  def recovered_flow_drain11?(e) do
    root = e["progress"]["runtime"]

    reason =
      case root["frontier"]["reason"] do
        "fatal" ->
          root["binding"]["failure_policy"] == "fail_fast" and root["flow"]["failures"] != %{}

        "approval" ->
          is_nil(root["frontier"]["fatal"]) and
            Enum.any?(root["tool_batches"], fn {_, b} ->
              Enum.any?(b["calls"], fn {_, c} -> c["state"] == "approval" end)
            end)

        _ ->
          false
      end

    root["frame_version"] == 11 and e["state"] in ~w(ready uncertain) and
      root["flow"]["phase"] == "running" and root["frontier"]["state"] == "draining" and reason and
      e["state"] == "uncertain" == Record.unresolved?(e)
  end

  # Trusted CAS inputs certify persisted phases, not a live worker/PID drain.
  @doc false
  def call_fatal_closable10?(record) do
    root = record["execution"]["progress"]["runtime"]

    root["frame_version"] in [10, 11] and root["frontier"]["reason"] == "fatal" and
      is_map(ToolEvidence.selected_call_fatal10(record)) and
      Enum.all?(record["execution"]["effects"], fn {_, effect} ->
        effect["state"] == "confirmed" and effect["outcome"]["status"] != "unknown"
      end) and
      Enum.all?(root["tool_batches"], fn {_, batch} ->
        Enum.all?(batch["calls"], fn {_, call} ->
          call["state"] not in ~w(preparing wrapping) and
            (call["state"] != "dispatching" or not is_nil(call["raw"]))
        end)
      end)
  end

  defp failed_closure10?(record) do
    root = record["execution"]["progress"]["runtime"]

    if record["execution"]["state"] == "failed" do
      call_fatal_closable10?(record) and
        Enum.all?(root["children"], fn {_, node} ->
          node["status"] == "completed" or OutputResolution.terminal_exhaustion10?(record, node) or
            ToolEvidence.terminal_retention10?(record, node) or
            (node["status"] == "cancelled" and
               node["error"] === root["frontier"]["fatal"]["error"])
        end) and
        Enum.all?(root["tool_batches"], fn {_, batch} ->
          Enum.all?(batch["calls"], fn {_, call} -> call["state"] in ~w(settled blocked) end)
        end) and
        is_nil(record["execution"]["progress"]["active_budget"]["reserved_ms"]) and
        is_nil(record["execution"]["progress"]["active_budget"]["refund_at"])
    else
      Enum.all?(root["children"], fn {_, node} -> node["status"] != "cancelled" end) and
        Enum.all?(root["tool_batches"], fn {_, batch} ->
          Enum.all?(batch["calls"], fn {_, call} -> call["state"] != "blocked" end)
        end)
    end
  end

  defp successful_closure10?(record) do
    root = record["execution"]["progress"]["runtime"]

    Enum.all?(root["tool_batches"], fn {_, batch} ->
      root["children"][batch["run_id"]]["status"] != "completed" or
        (is_map(batch["consumption"]) and is_map(batch["resolution"]) and
           is_nil(batch["resolution"]["error"]) and
           Enum.all?(batch["calls"], fn {_, call} -> call["state"] == "settled" end))
    end) and
      (root["cursor"] != "completed" or
         (root["frontier"]["state"] == "open" and not Record.unresolved?(record["execution"]) and
            is_nil(record["execution"]["progress"]["active_budget"]["reserved_ms"]) and
            is_nil(record["execution"]["progress"]["active_budget"]["refund_at"])))
  end

  defp node_evidence10?(record, id, child) do
    root = record["execution"]["progress"]["runtime"]
    frame = child["frame"]

    true =
      Record.positive?(frame["tool_return_bytes"]) and
        frame["tool_return_bytes"] <= Record.max_bytes()

    {:ok, snapshot} =
      Record.snapshot(child["snapshot"], {hd(record["key"]), :agent, Enum.at(record["key"], 2)})

    {:ok, messages} = Snapshot.messages(snapshot)
    [%Message.Request{run_id: ^id, parts: first_parts} | _] = messages
    # init_state/3 preserves the template's system instructions in this first
    # canonical request. Only that prefix may precede the single bound input.
    [%Message.Part.User{content: input}] =
      Enum.drop_while(first_parts, &match?(%Message.Part.System{}, &1))

    models =
      record["execution"]["effects"]
      |> Map.values()
      |> Enum.filter(
        &(&1["intent"]["kind"] == "model" and &1["intent"]["payload"]["run_id"] == id)
      )
      |> Enum.sort_by(& &1["intent"]["payload"]["step"])

    expected_input =
      case child["link"]["kind"] do
        "step" ->
          child["link"]["input"]

        "delegate" ->
          data =
            request_data10(record, child["parent_run_id"], child["link"]["parent_request_id"])

          descriptor = data["tool_descriptors"][child["link"]["tool_name"]]["delegation"]
          true = is_map(descriptor)
          true = Enum.all?(~w(definition policy model_ref), &(descriptor[&1] === child[&1]))
          child["link"]["args"][descriptor["prompt_arg"]]
      end

    true =
      input === expected_input and
        (child["link"]["kind"] == "step" or is_binary(expected_input))

    true =
      frame["first_new_message_index"] === 0 and
        child["snapshot"]["revision"] === frame["run_step"]

    true = authority_node10?(root, id)

    confirmed = Enum.filter(models, &(&1["state"] == "confirmed"))
    true = OutputResolution.evidence?(record, child, messages, confirmed)

    true =
      Enum.with_index(models)
      |> Enum.all?(fn {model, index} ->
        p = model["intent"]["payload"]

        op =
          Enum.find(
            root["scope"]["operations"],
            &(&1["run_id"] == id and &1["id"] == ["model", model["intent"]["call_id"]])
          )

        model_accounting10?(op, model, Enum.at(messages, p["history_index"])) and
          if index == 0 do
            p["history_index"] === 1
          else
            previous = Enum.at(models, index - 1)
            prior = previous["intent"]
            batch = root["tool_batches"][ToolEvidence.key(id, prior["call_id"])]
            output = root["output_resolutions"][prior["call_id"]]

            previous["state"] == "confirmed" and
              (not is_nil(batch["consumption"]) or output["decision"] == "retry") and
              p["history_index"] === prior["payload"]["history_index"] + 2 and
              p["request_data"]["model_state_hash"] ===
                previous["outcome"]["data"]["model_state_hash"]
          end
      end)

    true = child["snapshot"]["usage"] === usage10(root["scope"], id)

    true =
      Enum.all?(models, fn model ->
        p = model["intent"]["payload"]
        data = p["request_data"]

        Record.exact?(p, ~w(phase run_id step history_index request_data)) and
          ExAgent.Continuation.RequestData.valid10?(data) and
          data["model_ref"] === child["model_ref"] and
          data["messages"] === Message.to_json(Enum.take(messages, p["history_index"])) and
          ExAgent.Retention.executable?(Enum.take(messages, p["history_index"])) and
          data["tools"] === frame["selected_tools"] and data["settings"] === frame["settings"] and
          data["output_fingerprint"] === frame["output_fingerprint"] and
          model["state"] in ~w(running confirmed) and
          (model["state"] == "running" or
             (model["outcome"]["status"] == "succeeded" and
                model["outcome"]["data"]["state_available"] === true))
      end)

    true =
      Enum.all?(root["tool_batches"], fn {_, batch} ->
        batch["run_id"] != id or batch_bindings10?(record, batch)
      end)

    case List.last(models) do
      nil ->
        length(messages) == 1 and frame["cursor"] == "request" and frame["outcomes"] == %{} and
          child["status"] in ~w(running suspended cancelled)

      model ->
        p = model["intent"]["payload"]
        confirmed = model["state"] == "confirmed"

        hash =
          if confirmed,
            do: model["outcome"]["data"]["model_state_hash"],
            else: p["request_data"]["model_state_hash"]

        true = Record.digest(frame["model_data"]) == {:ok, hash}
        batch = root["tool_batches"][ToolEvidence.key(id, model["intent"]["call_id"])]
        output = root["output_resolutions"][model["intent"]["call_id"]]

        cond do
          child["status"] == "failed" ->
            terminal =
              is_nil(batch) and
                ((OutputResolution.terminal_exhaustion10?(record, child) and
                    length(messages) == p["history_index"] + 2) or
                   ToolEvidence.terminal_retention10?(record, child))

            branch =
              root["frame_version"] == 11 and branch_failure11?(root, id, child) and
                ((frame["cursor"] == "batch" and is_map(batch) and
                    length(messages) == p["history_index"] + 1) or
                   (frame["cursor"] == "response" and is_nil(batch) and
                      length(messages) in [p["history_index"] + 1, p["history_index"] + 2]))

            confirmed and (terminal or branch)

          child["status"] == "completed" ->
            response = Enum.at(messages, p["history_index"])

            confirmed and frame["cursor"] == "finish" and is_nil(batch) and
              if is_nil(output) do
                length(messages) == p["history_index"] + 1 and
                  response.parts != [] and
                  Enum.all?(response.parts, &match?(%Message.Part.Text{}, &1)) and
                  child["result"] === Message.Response.text(response)
              else
                output["decision"] == "succeeded" and
                  length(messages) == p["history_index"] + 2
              end

          not confirmed ->
            child["status"] == "running" and frame["cursor"] == "request" and
              p["history_index"] == length(messages) and is_nil(batch)

          not is_nil(batch["consumption"]) ->
            frame["cursor"] == "request" and child["status"] in ~w(running suspended cancelled) and
              length(messages) == p["history_index"] + 2

          output["decision"] == "retry" and frame["cursor"] == "request" ->
            child["status"] in ~w(running suspended cancelled) and
              length(messages) == p["history_index"] + 2

          not is_nil(batch) ->
            frame["cursor"] == "batch" and child["status"] in ~w(running suspended cancelled) and
              length(messages) == p["history_index"] + 1

          true ->
            frame["cursor"] == "response" and child["status"] in ~w(running suspended cancelled) and
              length(messages) == p["history_index"] + 1
        end
    end
  end

  # Preserve the established empty/absent snapshot projection; once any observed
  # usage exists, ScopeLedger owns the exact ancestral sum (including nil coverage).
  def usage10(scope, id) do
    if Enum.any?(scope["operations"], &(not is_nil(&1["ancestors"][id]))) do
      {:ok, usage} = ScopeLedger.usage(scope, id)
      Message.Usage.to_map(usage)
    else
      ExAgent.SnapshotData.usage_map(nil)
    end
  end

  defp model_accounting10?(op, model, response) do
    usage = if model["state"] == "confirmed", do: response.usage
    data = if is_nil(usage), do: nil, else: Message.Usage.to_map(usage)

    complete =
      model["state"] == "confirmed" and
        (is_nil(usage) or Message.Usage.complete?(usage))

    is_map(op) and op["usage"] === data and op["terminal_usage"] === data and
      op["complete"] === complete and
      Enum.all?(op["ancestors"], fn {_, value} -> value === data end)
  end

  def request_data10(record, run, request) do
    Enum.find_value(record["execution"]["effects"], fn {_, effect} ->
      if effect["intent"]["kind"] == "model" and effect["intent"]["call_id"] == request and
           effect["intent"]["payload"]["run_id"] == run,
         do: effect["intent"]["payload"]["request_data"]
    end)
  end

  defp batch_bindings10?(record, batch) do
    data = request_data10(record, batch["run_id"], batch["request_id"])

    Enum.all?(batch["limits"], fn {name, limit} ->
      d = data["tool_descriptors"][name]

      limit["schema_hash"] === data["tools"][name] and
        limit["max_retries"] === if(d, do: d["max_retries"], else: 0)
    end) and
      Enum.all?(batch["calls"], fn {id, c} ->
        limit =
          record["execution"]["progress"]["runtime"]["children"][batch["run_id"]]["frame"][
            "tool_return_bytes"
          ]

        true =
          Enum.all?([c["result"], c["raw"]["result"]], &(is_nil(&1) or byte_size(&1) <= limit))

        true =
          Enum.all?([c["result"], c["raw"]["result"]], fn bytes ->
            if is_nil(bytes),
              do: true,
              else:
                match?(
                  {:ok, [%Message.Request{parts: [%Message.Part.ToolReturn{usage: nil}]}]},
                  Message.from_json(bytes)
                )
          end)

        if is_nil(c["binding"]) do
          true
        else
          b = c["binding"]
          d = data["tool_descriptors"][b["tool_name"]]

          is_map(d) and d["kind"] == "function" and
            (c["source"]["kind"] not in ~w(effect child) or
               authorized10?(record, batch["run_id"], batch["request_id"], id, b)) and
            ExAgent.Tool.validate_args(
              %ExAgent.Tool{parameters_json_schema: d["definition"]["parameters"]},
              b["args"]
            ) == {:ok, b["args"]}
        end
      end)
  end

  def permission10(record, run, name) do
    actions =
      Enum.map(record["execution"]["progress"]["runtime"]["authority"][run]["policies"], fn p ->
        p |> Authority.policy_load() |> ExAgent.Permissions.decide(name)
      end)

    cond do
      :deny in actions -> :deny
      :ask in actions -> :ask
      true -> :allow
    end
  end

  def authorized10?(record, run, request, id, binding) do
    case permission10(record, run, binding["tool_name"]) do
      :allow ->
        true

      :deny ->
        false

      :ask ->
        key = journal_id(run, request, "approval", id)
        approval = record["execution"]["progress"]["approvals"][key]

        ExAgent.Continuation.Approval.approved?(approval) and
          Map.take(approval, ~w(tool_name args schema_hash)) ===
            Map.take(binding, ~w(tool_name args schema_hash))
    end
  end

  defp authority_node10?(root, id) do
    child = root["children"][id]
    parent = root["authority"][child["parent_run_id"]]
    own = root["authority"][id]

    parent_usage =
      if child["parent_run_id"] == root["run_id"],
        do: parent["usage"],
        else: root["children"][child["parent_run_id"]]["frame"]["limits"]["usage"]

    Enum.all?(parent["policies"], &(&1 in own["policies"])) and
      bounded10?(own["deadline_at"], parent["deadline_at"]) and
      bounded10?(own["max_concurrent_requests"], parent["max_concurrent_requests"]) and
      Enum.all?(parent_usage, fn {key, value} ->
        current = child["frame"]["limits"]["usage"][key]

        if key == "accounting",
          do: value != "strict" or current == "strict",
          else: bounded10?(current, value)
      end)
  end

  defp bounded10?(_, nil), do: true
  defp bounded10?(nil, _), do: false
  defp bounded10?(current, original), do: current <= original

  defp approvals10?(record) do
    root = record["execution"]["progress"]["runtime"]
    approvals = Map.get(record["execution"]["progress"], "approvals", %{})

    Enum.all?(approvals, fn {id, a} ->
      a["requested_revision"] <= record["revision"] and
        Enum.any?(record["receipts"], fn {_, receipt} ->
          receipt["operation"] == "pause" and receipt["revision"] == a["requested_revision"]
        end) and
        Enum.any?(root["tool_batches"], fn {_, batch} ->
          c = batch["calls"][a["call_id"]]

          approval_binding?(record, batch, id, a) and c["binding"]["args"] === a["args"] and
            (c["state"] in ~w(approval blocked) or ExAgent.Continuation.Approval.approved?(a))
        end)
    end) and
      (record["execution"]["state"] != "pending" or
         Enum.all?(root["tool_batches"], fn {_, b} ->
           Enum.all?(b["calls"], fn {id, c} ->
             c["state"] != "approval" or
               Map.has_key?(approvals, journal_id(b["run_id"], b["request_id"], "approval", id))
           end)
         end))
  end

  defp structural_evidence_legacy(record) do
    root = record["execution"]["progress"]["runtime"]

    with :ok <- graph_evidence(record),
         true <- structural_approvals?(record),
         true <- OutputResolution.coverage?(record),
         true <- ToolEvidence.evidence?(record),
         true <- root["cursor"] != "completed" or record["execution"]["state"] == "completed",
         true <-
           Enum.all?(root["children"], fn {_id, child} ->
             case Record.snapshot(
                    child["snapshot"],
                    {hd(record["key"]), :agent, Enum.at(record["key"], 2)}
                  ) do
               {:ok, snapshot} ->
                 case Snapshot.messages(snapshot) do
                   {:ok, [%Message.Request{parts: parts, run_id: run_id} | _] = messages} ->
                     run_id === child["frame"]["run_id"] and
                       child["frame"]["first_new_message_index"] === 0 and
                       child["snapshot"]["revision"] === child["frame"]["run_step"] and
                       step_model_evidence?(record, child, messages) and
                       Enum.any?(parts, fn
                         %Message.Part.User{content: content} ->
                           content === child["link"]["input"]

                         _ ->
                           false
                       end)

                   _ ->
                     false
                 end

               _ ->
                 false
             end
           end) do
      :ok
    else
      _ -> {:error, :invalid_step_evidence}
    end
  rescue
    _ -> {:error, :invalid_step_evidence}
  end

  # Global approval validity is deliberately weaker than restore admissibility:
  # a claimed row with a partially executed approved batch is still a valid journal.
  defp structural_approvals?(record) do
    e = record["execution"]
    root = e["progress"]["runtime"]
    approvals = Map.get(e["progress"], "approvals", %{})

    Enum.all?(approvals, fn {id, approval} ->
      approval["requested_revision"] <= record["revision"] and
        Enum.any?(record["receipts"], fn {_, receipt} ->
          receipt["operation"] == "pause" and receipt["state"] == "pending" and
            receipt["revision"] == approval["requested_revision"] and
            receipt["continuation_id"] == e["continuation_id"] and
            receipt["run_id"] == e["run_id"]
        end) and
        Enum.any?(root["tool_batches"] || %{}, fn {_, batch} ->
          approval_binding?(record, batch, id, approval)
        end)
    end) and
      (e["state"] != "pending" or
         Enum.all?(approvals, fn {_, a} -> a["decision"]["action"] != "deny" end)) and
      (e["state"] not in ~w(pending denied) or
         match?(
           {:ok, _},
           approval_boundary(
             record,
             Map.filter(approvals, fn {_, a} -> a["run_id"] == active_step_id(root) end)
           )
         ))
  end

  defp approval_binding?(record, batch, id, approval) do
    root = record["execution"]["progress"]["runtime"]
    child = root["children"][batch["run_id"]]

    approval["run_id"] == batch["run_id"] and
      id == journal_id(batch["run_id"], batch["request_id"], "approval", approval["call_id"]) and
      approval["definition"] === child["definition"] and
      approval["policy"] === child["policy"] and
      is_binary(approval["schema_hash"]) and
      approval["schema_hash"] === child["frame"]["selected_tools"][approval["tool_name"]] and
      approval["schema_hash"] === batch["limits"][approval["tool_name"]]["schema_hash"] and
      Enum.any?(ToolEvidence.calls(record, batch), fn call ->
        call.tool_call_id == approval["call_id"] and call.tool_name == approval["tool_name"]
      end)
  end

  # Shared certificate for Writer's post-settle all-pending boundary and restore.
  # Bindings contain effective post-hook arguments, not the original model args.
  def approval_boundary(record, bindings) do
    e = record["execution"]
    root = e["progress"]["runtime"]
    id = active_step_id(root)
    child = root["children"][id]
    leaf = child["frame"]
    request = leaf["model_request_id"]
    batches = Map.filter(root["tool_batches"] || %{}, fn {_, b} -> b["run_id"] == id end)

    with 9 <- root["frame_version"],
         "running" <- root["cursor"],
         "running" <- child["status"],
         "batch" <- leaf["cursor"],
         1 <- leaf["run_step"],
         true <- leaf["outcomes"] == %{} and leaf["tool_retries"] == %{},
         true <- Retry.plans(e) == %{} and not Record.unresolved?(e),
         [{_, batch}] <- Map.to_list(batches),
         true <- batch["request_id"] == request,
         nil <- batch["resolution"],
         true <- batch["observations"] == %{},
         true <- not Map.has_key?(root["output_resolutions"], request),
         true <-
           Enum.all?(e["effects"], fn {_, effect} ->
             effect["intent"]["payload"]["run_id"] != id or effect["intent"]["kind"] == "model"
           end),
         true <-
           Enum.all?(root["scope"]["operations"], fn op ->
             op["run_id"] != id or op["id"] == ["model", request]
           end),
         true <- Enum.all?(root["scope"]["retry_batches"], &(&1["run_id"] != id)),
         calls when calls != [] <- ToolEvidence.calls(record, batch),
         true <- Enum.all?(calls, &(&1.kind == :function)),
         true <- length(Enum.uniq_by(calls, & &1.tool_call_id)) == length(calls),
         true <- leaf["scope"]["batches"] === %{request => length(calls)},
         true <- is_map(bindings) and map_size(bindings) == length(calls),
         true <-
           Enum.all?(calls, fn call ->
             key = journal_id(id, request, "approval", call.tool_call_id)
             binding = bindings[key]
             is_map(binding) and approval_binding?(record, batch, key, binding)
           end) do
      {:ok, calls}
    else
      _ -> {:error, :unsupported_composition_boundary}
    end
  rescue
    _ -> {:error, :unsupported_composition_boundary}
  end

  defp step_model_evidence?(record, child, messages) do
    frame = child["frame"]

    models =
      record["execution"]["effects"]
      |> Map.values()
      |> Enum.filter(
        &(&1["intent"]["kind"] == "model" and
            &1["intent"]["payload"]["run_id"] == frame["run_id"])
      )
      |> Enum.sort_by(& &1["intent"]["payload"]["step"])

    count = length(models)
    positions = Enum.map(models, & &1["intent"]["payload"]["step"])
    expected = if count == 0, do: [], else: Enum.to_list(1..count)

    confirmed =
      Enum.filter(
        models,
        &(&1["state"] == "confirmed" and &1["outcome"]["status"] == "succeeded")
      )

    response_indices = for {%Message.Response{}, index} <- Enum.with_index(messages), do: index

    frame["run_step"] === count and frame["scope"]["requests"] === count and
      positions === expected and
      response_indices === Enum.map(confirmed, & &1["intent"]["payload"]["history_index"]) and
      Enum.all?(
        Enum.drop(models, -1),
        &(&1 in confirmed and &1["outcome"]["data"]["state_available"])
      ) and
      step_cursor_evidence?(frame, List.last(models), messages, child["status"]) and
      OutputResolution.evidence?(record, child, messages, confirmed) and
      step_batch_evidence?(record, frame, messages, confirmed) and
      step_tool_evidence?(record, frame, messages, confirmed) and
      Enum.all?(confirmed, fn effect ->
        response = Enum.at(messages, effect["intent"]["payload"]["history_index"])
        data = effect["outcome"]["data"]

        match?(%Message.Response{}, response) and Outcome.model_valid?(data) and
          Outcome.hash(Message.to_json([response])) == {:ok, data["response_hash"]}
      end)
  end

  defp step_batch_evidence?(record, frame, messages, models) do
    resolutions = Map.get(record["execution"]["progress"]["runtime"], "output_resolutions", %{})

    expected =
      for model <- models,
          request = model["intent"]["call_id"],
          index = model["intent"]["payload"]["history_index"],
          calls = Message.Response.tool_calls(Enum.at(messages, index)),
          calls != [],
          not Map.has_key?(resolutions, request),
          index < length(messages) - 1 or
            (request == frame["model_request_id"] and frame["cursor"] == "batch"),
          into: %{},
          do: {request, length(calls)}

    frame["scope"]["batches"] === expected
  end

  defp step_tool_evidence?(record, frame, messages, models) do
    # Bind results to the request that introduced the call, not just a reusable
    # provider call ID. Confirmed batch outcomes may precede message history.
    {_, evidence} =
      Enum.reduce(Enum.with_index(messages), {nil, %{}}, fn
        {%Message.Response{} = response, index}, {_, evidence} ->
          model = Enum.find(models, &(&1["intent"]["payload"]["history_index"] == index))
          request = model["intent"]["call_id"]
          {{request, Message.Response.tool_calls(response)}, evidence}

        {%Message.Request{parts: parts}, _}, {batch, evidence} ->
          evidence =
            Enum.reduce(parts, evidence, fn
              %module{tool_call_id: id} = part, acc
              when module in [Message.Part.ToolReturn, Message.Part.Retry] and not is_nil(id) ->
                {request, calls} = batch
                call = Enum.find(calls, &(&1.tool_call_id == part.tool_call_id))
                true = not is_nil(call)
                key = {request, part.tool_call_id}
                false = Map.has_key?(acc, key)
                Map.put(acc, key, {call, Outcome.encode(part), :history})

              _, acc ->
                acc
            end)

          {batch, evidence}
      end)

    evidence =
      Enum.reduce(frame["outcomes"], evidence, fn {id, bytes}, acc ->
        request = frame["model_request_id"]
        model = Enum.find(models, &(&1["intent"]["call_id"] == request))
        response = Enum.at(messages, model["intent"]["payload"]["history_index"])
        call = Enum.find(Message.Response.tool_calls(response), &(&1.tool_call_id == id))
        true = not is_nil(call)
        false = Map.has_key?(acc, {request, id})
        Map.put(acc, {request, id}, {call, bytes, :batch})
      end)

    matched =
      Enum.map(evidence, fn {{request, id}, {call, bytes, source}} ->
        effect_id =
          Retry.active_id(record["execution"], journal_id(frame["run_id"], request, "tool", id))

        effect = record["execution"]["effects"][effect_id]
        own = %{frame | "model_request_id" => request, "outcomes" => %{id => bytes}}

        if OutputResolution.matches?(record, frame["run_id"], request, id, bytes) do
          true = source == :history and is_nil(effect)
          nil
        else
          true = journal_matches?(effect, call, bytes, own, record)
          true = source == :batch or effect["outcome"]["data"]["phase"] == "final"
          effect_id
        end
      end)

    calls =
      for model <- models,
          response = Enum.at(messages, model["intent"]["payload"]["history_index"]),
          call <- Message.Response.tool_calls(response),
          into: %{},
          do:
            {journal_id(frame["run_id"], model["intent"]["call_id"], "tool", call.tool_call_id),
             call}

    Enum.all?(record["execution"]["effects"], fn {id, effect} ->
      intent = effect["intent"]

      if intent["kind"] == "tool" and
           tool_belongs_to?(record, id, intent, frame["run_id"], models) do
        call = calls[Retry.canonical_id(record["execution"], id)]
        payload = intent["payload"]

        not is_nil(call) and payload["tool_name"] === call.tool_name and
          Outcome.call_hash(call) == {:ok, payload["call_hash"]} and
          payload["schema_hash"] ===
            ToolEvidence.schema(
              record,
              frame["run_id"],
              payload["model_request_id"] || request_for_effect(record, id),
              call.tool_name,
              frame["selected_tools"][call.tool_name]
            ) and
          (effect["state"] != "confirmed" or Retry.retired?(record["execution"], id) or
             id in matched)
      else
        true
      end
    end)
  end

  defp tool_belongs_to?(record, id, intent, run, models) do
    canonical = Retry.canonical_id(record["execution"], id)

    Enum.any?(models, fn model ->
      canonical == journal_id(run, model["intent"]["call_id"], "tool", intent["call_id"])
    end)
  end

  defp step_cursor_evidence?(frame, nil, messages, status) do
    frame["cursor"] == "request" and is_nil(frame["model_request_id"]) and
      status == "running" and length(messages) == 1 and frame["outcomes"] == %{}
  end

  defp step_cursor_evidence?(frame, effect, messages, status) do
    intent = effect["intent"]
    data = effect["outcome"]["data"]
    succeeded = effect["state"] == "confirmed" and effect["outcome"]["status"] == "succeeded"
    index = intent["payload"]["history_index"]

    hash =
      if succeeded and data["state_available"],
        do: data["model_state_hash"],
        else: intent["payload"]["request_data"]["model_state_hash"]

    frame["model_request_id"] === intent["call_id"] and
      Record.digest(frame["model_data"]) == {:ok, hash} and
      case frame["cursor"] do
        "request" ->
          status == "running" and frame["outcomes"] == %{} and
            not Map.has_key?(frame["scope"]["batches"], frame["model_request_id"]) and
            ((not succeeded and index === length(messages)) or
               (succeeded and data["state_available"] == false and index === length(messages) - 1))

        "response" ->
          succeeded and data["state_available"] and index === length(messages) - 1 and
            not Map.has_key?(frame["scope"]["batches"], frame["model_request_id"]) and
            frame["outcomes"] == %{} and status == "running"

        "batch" ->
          succeeded and data["state_available"] and index === length(messages) - 1 and
            Message.Response.tool_calls(List.last(messages)) != [] and status == "running" and
            frame["scope"]["batches"][frame["model_request_id"]] ===
              length(Message.Response.tool_calls(List.last(messages)))

        "finish" ->
          succeeded and data["state_available"] and status == "completed" and
            open_calls(messages) == []
      end
  end

  defp node_scope_matches?(own, scope, id) do
    with {:ok, expected} <- ScopeLedger.node_data(scope, id) do
      Map.delete(own, "operations") === Map.delete(expected, "operations") and
        MapSet.new(own["operations"]) == MapSet.new(expected["operations"]) and
        length(own["operations"]) == length(expected["operations"])
    else
      _ -> false
    end
  end

  def node(frame, run_id) do
    if frame["run_id"] == run_id, do: frame, else: get_in(frame, ["children", run_id, "frame"])
  end

  def put_node(frame, run_id, node) do
    if frame["run_id"] == run_id,
      do: node,
      else: put_in(frame, ["children", run_id, "frame"], node)
  end

  def child_for(%{"frame_version" => durable_version} = frame, run_id, request_id, call_id)
      when durable_version in [10, 11] do
    Enum.find(frame["children"], fn {_, child} ->
      child["link"]["kind"] == "delegate" and child["parent_run_id"] == run_id and
        child["link"]["parent_request_id"] == request_id and child["link"]["call_id"] == call_id
    end)
  end

  def child_for(frame, run_id, request_id, call_id) do
    Enum.find(Map.get(frame, "children", %{}), fn {_, child} ->
      child["parent_run_id"] == run_id and child["parent_request_id"] == request_id and
        child["call"]["call_id"] == call_id
    end)
  end

  def with_scope(%{"children" => _} = frame, scope) do
    children =
      Map.new(frame["children"], fn {id, child} ->
        {:ok, own} = ScopeLedger.node_data(scope, id)
        {id, put_in(child, ["frame", "scope"], own)}
      end)

    frame |> Map.put("scope", scope) |> Map.put("children", children)
  end

  def with_scope(frame, scope), do: Map.put(frame, "scope", scope)

  def child_record(record, id) do
    child = record["execution"]["progress"]["runtime"]["children"][id]

    execution =
      record["execution"]
      |> Map.merge(Map.take(child, ~w(definition policy model_ref)))
      |> Map.put("run_id", id)
      |> Map.put("state", if(child["status"] == "completed", do: "completed", else: "ready"))
      |> put_in(["progress", "runtime"], child["frame"])

    %{record | "execution" => execution, "snapshot" => child["snapshot"]}
    |> Map.put(:trusted_tree_record, record)
  end

  def node_transition(previous, current, id) do
    with %{"children" => old} <- previous,
         %{"children" => children} <- current,
         true <- id != current["run_id"] and Map.has_key?(children, id),
         :ok <- validate(current),
         true <- ToolEvidence.transition?(previous, current, "node_checkpoint"),
         true <-
           Map.drop(previous, ~w(scope children tool_batches)) ===
             Map.drop(current, ~w(scope children tool_batches)),
         true <-
           Enum.sort(Map.keys(Map.delete(old, id))) ==
             Enum.sort(Map.keys(Map.delete(children, id))),
         true <-
           Enum.all?(Map.delete(old, id), fn {key, child} ->
             without_scope(child) === without_scope(children[key])
           end),
         true <-
           is_nil(old[id]) or
             Map.drop(old[id], ~w(frame snapshot status result result_omitted)) ===
               Map.drop(children[id], ~w(frame snapshot status result result_omitted)),
         true <- is_nil(old[id]) or old[id]["status"] != "completed" or old[id] === children[id] do
      :ok
    else
      _ -> {:error, :invalid_node_checkpoint}
    end
  end

  defp without_scope(child), do: put_in(child, ["frame", "scope"], nil)

  def validate_child_binding(
        %{
          "execution" => %{
            "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
          }
        } = record,
        id
      )
      when durable_version in [10, 11] do
    if Map.has_key?(root["children"], id),
      do: structural_evidence(record),
      else: {:error, :invalid_composition_node}
  end

  def validate_child_binding(
        %{"execution" => %{"progress" => %{"runtime" => %{"frame_version" => 9} = root}}},
        id
      ) do
    if id === active_step_id(root), do: validate(root), else: {:error, :invalid_step_binding}
  end

  def validate_child_binding(
        %{"execution" => %{"progress" => %{"runtime" => %{"frame_version" => version}}}} = record,
        id
      )
      when version in [5, 6, 7, 8] do
    root = record["execution"]["progress"]["runtime"]
    if valid_step?(id, root["children"][id], root), do: :ok, else: {:error, :invalid_step_binding}
  end

  def validate_child_binding(record, id) do
    runtime = record["execution"]["progress"]["runtime"]
    child = runtime["children"][id]
    parent_id = child["parent_run_id"]
    parent = node(runtime, parent_id)

    snapshot =
      if parent_id == runtime["run_id"],
        do: record["snapshot"],
        else: runtime["children"][parent_id]["snapshot"]

    request = child["parent_request_id"]
    {:ok, digest} = Record.digest([parent_id, request, "model", request])
    effect = record["execution"]["effects"]["model-" <> digest]

    with true <- is_map(parent) and effect["state"] == "confirmed",
         {:ok, messages} <- Message.from_json(snapshot["message_history"]),
         {:ok, [%Message.Response{} = response]} <- Message.from_json(child["parent_response"]),
         true <-
           Outcome.hash(Message.to_json([response])) ==
             {:ok, effect["outcome"]["data"]["response_hash"]},
         %Message.Part.ToolCall{} = call <-
           Enum.find(
             Message.Response.tool_calls(response),
             &(&1.tool_call_id == child["call"]["call_id"])
           ),
         true <- call.tool_name == child["call"]["tool_name"],
         true <- Outcome.call_hash(call) == {:ok, child["call"]["call_hash"]},
         true <-
           parent["model_request_id"] != request or
             parent["selected_tools"][call.tool_name] == child["call"]["schema_hash"],
         :ok <- delegation_position(child, parent, messages, effect) do
      :ok
    else
      _ -> {:error, :continuation_delegation_mismatch}
    end
  rescue
    _ -> {:error, :continuation_delegation_mismatch}
  end

  defp delegation_position(child, parent, messages, effect) do
    call = child["call"]

    current? =
      parent["model_request_id"] == child["parent_request_id"] and parent["cursor"] == "batch"

    bytes =
      if current? do
        parent["outcomes"][call["call_id"]]
      else
        case Enum.at(messages, effect["intent"]["payload"]["history_index"] + 1) do
          %Message.Request{parts: parts} ->
            case Enum.find(
                   parts,
                   fn
                     %Message.Part.ToolReturn{tool_call_id: id} -> id == call["call_id"]
                     _ -> false
                   end
                 ) do
              %Message.Part.ToolReturn{} = part -> Outcome.encode(part)
              _ -> child["parent_result"]
            end

          _ ->
            child["parent_result"]
        end
      end

    case child["outcome"] do
      nil ->
        if current? and is_nil(bytes), do: :ok, else: {:error, :continuation_delegation_mismatch}

      %{"status" => "succeeded", "data" => data} ->
        raw = %Message.Part.ToolReturn{
          tool_name: call["tool_name"],
          tool_call_id: call["call_id"],
          status: :succeeded,
          content: child["result"]
        }

        if child["status"] == "completed" and is_binary(bytes) and
             bytes === child["parent_result"] and Outcome.valid?(data) and
             Outcome.hash(raw) == {:ok, data["raw_hash"]} and
             Outcome.hash(bytes) == {:ok, data["result_hash"]},
           do: :ok,
           else: {:error, :continuation_delegation_mismatch}

      _ ->
        {:error, :continuation_delegation_mismatch}
    end
  end

  def restore_scope(scope, %{"scope" => %{"scope_version" => 1} = data}),
    do: ExecutionScope.restore(scope, data)

  def restore_scope(scope, %{"scope" => %{"scope_version" => 2} = data}),
    do: ExecutionScope.restore_tree(scope, data)

  def export_scope(scope, %{"scope" => %{"scope_version" => 1}}), do: ExecutionScope.export(scope)

  def export_scope(scope, %{"scope" => %{"scope_version" => 2}}),
    do: ExecutionScope.export_tree(scope)

  defp position_scope(%{"scope" => %{"scope_version" => 1} = data}),
    do: {:ok, %{requests: data["requests"], batches: data["batches"]}}

  defp position_scope(%{"scope" => %{"scope_version" => 2} = data, "run_id" => run_id}),
    do: ScopeLedger.node_position(data, run_id)

  def restore(_, %{"record_version" => 2}, _),
    do: {:error, :structural_root_requires_definition}

  def restore(state, record, config) do
    restore_node(state, record, config)
  end

  # The agent Record2 guard above remains intact. This entry validates the parent
  # record before projecting a leaf; it never changes the persisted record format.
  def restore_composition_node(state, record, config, id) do
    with :ok <- Record.validate(record, {config.store.namespace, :agent, config.id}),
         %{"frame_version" => version} when version in [7, 8, 9, 10, 11] <-
           record["execution"]["progress"]["runtime"],
         :ok <- validate_child_data(record, id) do
      restore_node(state, child_record(record, id), config)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_composition_node}
    end
  end

  defp restore_node(state, record, config) do
    frame = record["execution"]["progress"]["runtime"]

    with :ok <- validate(frame),
         :ok <- restore_graph(record, frame),
         :ok <- children_valid(record, frame),
         :ok <- outcomes_valid(frame),
         true <- frame["run_id"] == record["execution"]["run_id"],
         true <-
           Enum.all?(
             [:definition, :policy, :model_ref],
             &(config[&1] == record["execution"][Atom.to_string(&1)])
           ),
         {:ok, snapshot} <-
           Record.snapshot(record["snapshot"], {config.store.namespace, :agent, config.id}),
         {:ok, messages} <- Snapshot.messages(snapshot),
         :ok <- executable(messages),
         :ok <- restore_position(record, frame, messages),
         {:ok, model} <- load_bound_model(state.agent.model, frame, config),
         {:ok, tools} <- restore_tools(state.agent.tools, frame["selected_tools"], config),
         {:ok, permission_floor} <- restore_permissions(frame["permissions"]),
         {:ok, usage_limits} <- restore_limits(state.usage_limits, frame["limits"]["usage"]) do
      state =
        Enum.reduce(@limits, state, fn key, acc ->
          Map.put(acc, key, minimum(Map.fetch!(state, key), frame["limits"][Atom.to_string(key)]))
        end)

      settings =
        Map.new(Map.keys(Map.from_struct(state.settings)), fn key ->
          value =
            if key == :timeout and
                 get_in(record, [
                   :trusted_tree_record,
                   "execution",
                   "progress",
                   "runtime",
                   "frame_version"
                 ]) in [10, 11] do
              state.settings.timeout
            else
              Map.fetch!(frame["settings"], Atom.to_string(key))
            end

          {key, value}
        end)

      state = %{
        state
        | model: model,
          messages: messages,
          run_id: frame["run_id"],
          root_run_id: frame["run_id"],
          first_new_message_index: frame["first_new_message_index"],
          run_step: frame["run_step"],
          model_request_id: frame["model_request_id"],
          tool_retries: frame["tool_retries"],
          output_retries_used: frame["output_retries_used"],
          tool_return_bytes:
            if(
              get_in(record, [
                :trusted_tree_record,
                "execution",
                "progress",
                "runtime",
                "frame_version"
              ]) in [10, 11],
              do: min(frame["tool_return_bytes"], state.max_payload_bytes),
              else: frame["tool_return_bytes"]
            ),
          usage_limits: usage_limits,
          usage: Snapshot.usage_struct(snapshot),
          settings: struct!(ExAgent.ModelSettings, settings),
          prepared_tools: tools,
          continuation_retry: Retry.model_plan(record["execution"], frame)
      }

      state = %{
        state
        | agent: %{
            state.agent
            | output_retries: min(state.agent.output_retries, frame["limits"]["output_retries"])
          }
      }

      {:ok, state, frame, permission_floor}
    else
      false -> {:error, :continuation_definition_changed}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :invalid_continuation_frame}
  end

  defp restore_graph(
         %{
           trusted_tree_record:
             %{
               "execution" => %{
                 "progress" => %{"runtime" => %{"frame_version" => durable_version}}
               }
             } = original
         },
         _
       )
       when durable_version in [10, 11], do: structural_evidence(original)

  defp restore_graph(record, _),
    do: graph_evidence(Map.get(record, :trusted_tree_record, record))

  # Leaf projections are private rehydration inputs, never independently valid
  # Record10 authorities. Check them against the fully certified original tree.
  defp restore_position(
         %{
           trusted_tree_record:
             %{
               "execution" => %{
                 "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
               }
             } = original
         } = view,
         leaf,
         messages
       )
       when durable_version in [10, 11] do
    node = root["children"][leaf["run_id"]]

    with true <- leaf === node["frame"] and view["snapshot"] === node["snapshot"],
         {:ok, ^messages} <- Message.from_json(node["snapshot"]["message_history"]),
         :ok <- structural_evidence(original),
         do: :ok
  end

  defp restore_position(record, frame, messages) do
    with :ok <- position_consistent(record, frame, messages),
         do: outcomes_consistent(record, frame, messages)
  end

  defp children_valid(record, %{"children" => children}) do
    Enum.reduce_while(children, :ok, fn {id, _}, :ok ->
      case validate_child_data(record, id) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp children_valid(_, _), do: :ok

  defp tree_runtime(record) do
    record = Map.get(record, :trusted_tree_record, record)
    record["execution"]["progress"]["runtime"]
  end

  # Validate the reverse edges too: a self-consistent smaller graph must never
  # hide a committed child request/approval and turn it into a new delegation.
  def graph_evidence(record) do
    runtime = record["execution"]["progress"]["runtime"]
    root = runtime["run_id"]
    children = Map.get(runtime, "children", %{})
    ids = MapSet.new([root | Map.keys(children)])
    scope = runtime["scope"]

    operations =
      if scope["scope_version"] == 1,
        do: Enum.map(scope["operations"], &Map.put(&1, "run_id", root)),
        else: scope["operations"]

    requests =
      for op <- operations,
          match?(["model", _], op["id"]),
          into: MapSet.new(),
          do: {op["run_id"], Enum.at(op["id"], 1)}

    models =
      Enum.filter(record["execution"]["effects"], fn {_, effect} ->
        effect["intent"]["kind"] == "model"
      end)

    with true <- Retry.valid?(record["execution"]),
         true <-
           Enum.all?(models, fn {id, effect} ->
             intent = effect["intent"]
             run = intent["payload"]["run_id"]
             request = intent["call_id"]

             MapSet.member?(ids, run) and MapSet.member?(requests, {run, request}) and
               intent["payload"]["phase"] == "model_dispatch" and
               id == journal_id(run, request, "model", request)
           end),
         {:ok, tools} <- journal_tools(record, models),
         true <-
           Enum.all?(operations, fn op ->
             case op["id"] do
               ["model", request] ->
                 Enum.any?(models, fn {_, effect} ->
                   effect["intent"]["call_id"] == request and
                     effect["intent"]["payload"]["run_id"] == op["run_id"]
                 end) or
                   (runtime["frame_version"] == 1 and
                      match?(
                        %{"cursor" => "request", "model_request_id" => ^request},
                        node(runtime, op["run_id"])
                      )) or
                   Enum.any?(
                     Map.get(record["execution"]["progress"], "legacy_model_admissions", []),
                     &(&1 === %{"run_id" => op["run_id"], "request_id" => request})
                   )

               ["tool", request, call] ->
                 MapSet.member?(tools, {op["run_id"], request, call})

               ["tool", request, call, attempt] ->
                 MapSet.member?(tools, {op["run_id"], request, call}) and
                   match?(
                     %{"intent" => %{"kind" => "tool", "call_id" => ^call}},
                     record["execution"]["effects"][attempt]
                   ) and
                   Enum.any?(
                     Map.get(scope, "retry_batches", []),
                     &(&1 === %{
                         "id" => attempt,
                         "run_id" => op["run_id"],
                         "request_id" => request
                       })
                   )

               _ ->
                 false
             end
           end),
         true <-
           Enum.all?(Map.get(scope, "retry_batches", []), fn batch ->
             plan = Retry.incoming(record["execution"], batch["id"])

             is_map(plan) and plan["kind"] == "tool" and plan["node_id"] == batch["run_id"] and
               plan["request_id"] == batch["request_id"] and
               Map.has_key?(record["execution"]["effects"], batch["id"])
           end),
         true <-
           Enum.all?(Map.get(record["execution"]["progress"], "approvals", %{}), fn {id, approval} ->
             run = approval["run_id"]
             refs = if run == root, do: record["execution"], else: children[run]

             MapSet.member?(ids, run) and approval["definition"] === refs["definition"] and
               approval["policy"] === refs["policy"] and
               Enum.any?(models, fn {_, effect} ->
                 request = effect["intent"]["call_id"]

                 effect["intent"]["payload"]["run_id"] == run and
                   id == journal_id(run, request, "approval", approval["call_id"])
               end)
           end) do
      :ok
    else
      _ -> {:error, :continuation_orphaned_evidence}
    end
  rescue
    _ -> {:error, :continuation_orphaned_evidence}
  end

  defp journal_tools(record, models) do
    Enum.reduce_while(record["execution"]["effects"], {:ok, MapSet.new()}, fn
      {_, %{"intent" => %{"kind" => "model"}}}, acc ->
        {:cont, acc}

      {id, %{"intent" => %{"kind" => "tool", "call_id" => call, "payload" => payload}}},
      {:ok, tools} ->
        canonical_id = Retry.canonical_id(record["execution"], id)

        candidates =
          for {_, model} <- models,
              run = model["intent"]["payload"]["run_id"],
              request = model["intent"]["call_id"],
              canonical_id == journal_id(run, request, "tool", call),
              do: {run, request, call}

        case candidates do
          [{run, request, ^call} = binding] ->
            retry_reserved? =
              is_nil(payload["retry_of"]) or
                Enum.any?(
                  Map.get(
                    record["execution"]["progress"]["runtime"]["scope"],
                    "retry_batches",
                    []
                  ),
                  &(&1 === %{"id" => id, "run_id" => run, "request_id" => request})
                )

            if payload["phase"] in ~w(dispatch pre_dispatch) and
                 retry_reserved? and
                 (not Map.has_key?(payload, "run_id") or payload["run_id"] == run) and
                 (not Map.has_key?(payload, "model_request_id") or
                    payload["model_request_id"] == request),
               do: {:cont, {:ok, MapSet.put(tools, binding)}},
               else: {:halt, {:error, :continuation_orphaned_evidence}}

          _ ->
            {:halt, {:error, :continuation_orphaned_evidence}}
        end

      _, _ ->
        {:halt, {:error, :continuation_orphaned_evidence}}
    end)
  end

  defp journal_id(run, request, kind, call) do
    {:ok, hash} = Record.digest([run, request, kind, call])
    kind <> "-" <> hash
  end

  defp validate_child_data(record, id) do
    child_record = child_record(record, id)
    frame = child_record["execution"]["progress"]["runtime"]
    [namespace, "agent", key] = record["key"]
    child = record["execution"]["progress"]["runtime"]["children"][id]

    with true <- is_nil(child["result_omitted"]),
         :ok <- validate_child_binding(record, id),
         {:ok, snapshot} <- Record.snapshot(child_record["snapshot"], {namespace, :agent, key}),
         {:ok, messages} <- Snapshot.messages(snapshot),
         :ok <- executable(messages),
         :ok <- restore_position(child_record, frame, messages) do
      :ok
    else
      false -> {:error, :omitted_payload_history}
      {:error, _} = error -> error
    end
  end

  def inventory(tools) do
    Enum.reduce_while(tools, {:ok, %{}}, fn tool, {:ok, acc} ->
      case fingerprint(tool) do
        {:ok, hash} -> {:cont, {:ok, Map.put(acc, tool.name, hash)}}
        error -> {:halt, error}
      end
    end)
  end

  def output_fingerprint(params) do
    with {:ok, descriptor} <- output_descriptor(params), do: Record.digest(descriptor)
  end

  def output_descriptor(params),
    do:
      JSON.normalize(%{
        "mode" => Atom.to_string(params.output_mode),
        "allow_text" => params.allow_text_output,
        "object" =>
          if(is_map(params.output_object),
            do: Map.drop(params.output_object, [:module, "module"]),
            else: params.output_object
          ),
        "tools" => Enum.map(params.output_tools, &Tool.definition/1)
      })

  def validate_output(nil, _), do: :ok

  def validate_output(%{"output_fingerprint" => nil, "run_step" => 0} = frame, _) do
    case position_scope(frame) do
      {:ok, %{requests: 0}} -> :ok
      _ -> {:error, :continuation_output_changed}
    end
  end

  def validate_output(frame, params) do
    if output_fingerprint(params) == {:ok, frame["output_fingerprint"]},
      do: :ok,
      else: {:error, :continuation_output_changed}
  end

  def put_outcome(frame, part),
    do:
      put_in(
        frame,
        ["outcomes", part.tool_call_id],
        Message.to_json([%Message.Request{parts: [part]}])
      )

  def outcomes(frame) do
    Map.new(frame["outcomes"], fn {id, bytes} ->
      {:ok, [%Message.Request{parts: [%Message.Part.ToolReturn{tool_call_id: ^id} = part]}]} =
        Message.from_json(bytes)

      :ok = executable([%Message.Request{parts: [part]}])
      {id, part}
    end)
  end

  def outcome(frame, id) do
    case frame["outcomes"][id] do
      nil ->
        nil

      bytes ->
        with {:ok,
              [%Message.Request{parts: [%Message.Part.ToolReturn{tool_call_id: ^id} = part]}]} <-
               Message.from_json(bytes),
             :ok <- executable([%Message.Request{parts: [part]}]) do
          part
        else
          {:error, _} = error -> error
          _ -> {:error, :invalid_continuation_frame}
        end
    end
  end

  defp outcomes_valid(frame) do
    Enum.reduce_while(frame["outcomes"], :ok, fn {id, _}, :ok ->
      case outcome(frame, id) do
        %Message.Part.ToolReturn{} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp outcomes_consistent(record, %{"cursor" => "batch"} = frame, messages) do
    case List.last(messages) do
      %Message.Response{} = response ->
        Enum.reduce_while(Message.Response.tool_calls(response), :ok, fn call, :ok ->
          {:ok, digest} =
            Record.digest([frame["run_id"], frame["model_request_id"], "tool", call.tool_call_id])

          effect =
            record["execution"]["effects"][
              Retry.active_id(record["execution"], "tool-" <> digest)
            ]

          bytes = frame["outcomes"][call.tool_call_id]

          tree = tree_runtime(record)

          delegated =
            child_for(tree, frame["run_id"], frame["model_request_id"], call.tool_call_id)

          cond do
            match?({_, %{"outcome" => outcome}} when not is_nil(outcome), delegated) and
                is_nil(bytes) ->
              {:halt, {:error, :continuation_outcome_unavailable}}

            effect && effect["state"] == "confirmed" && is_nil(bytes) ->
              {:halt, {:error, :continuation_outcome_unavailable}}

            bytes &&
                not (journal_matches?(effect, call, bytes, frame, record) or
                         delegation_matches?(record, frame, call, bytes)) ->
              {:halt, {:error, :continuation_outcome_mismatch}}

            true ->
              {:cont, :ok}
          end
        end)

      _ ->
        {:error, :invalid_continuation_frame}
    end
  end

  defp outcomes_consistent(_, _, _), do: :ok

  defp position_consistent(record, frame, messages) do
    {:ok, scope} = position_scope(frame)
    effects = record["execution"]["effects"]
    model_id = frame["model_request_id"]
    {:ok, digest} = Record.digest([frame["run_id"], model_id, "model", model_id])

    model_effect =
      if Retry.model_plan(record["execution"], frame), do: nil, else: effects["model-" <> digest]

    calls =
      case List.last(messages) do
        %Message.Response{} = r -> Message.Response.tool_calls(r)
        _ -> []
      end

    open = open_calls(messages)
    model_ok = model_effect && model_matches?(model_effect, frame, messages)

    cursor_ok =
      case frame["cursor"] do
        "request" ->
          open == [] and frame["outcomes"] == %{} and is_nil(model_effect) and
            not Map.has_key?(scope.batches, model_id)

        "response" ->
          match?(%Message.Response{}, List.last(messages)) and open === calls and
            frame["outcomes"] == %{} and model_ok and
            not Map.has_key?(scope.batches, model_id)

        "batch" ->
          calls != [] and open === calls and model_ok and
            scope.batches[model_id] === length(calls) and
            Enum.all?(Map.keys(frame["outcomes"]), fn id ->
              Enum.any?(calls, &(&1.tool_call_id == id))
            end)

        "finish" ->
          record["execution"]["state"] == "completed" and open == []
      end

    if cursor_ok and frame["first_new_message_index"] <= length(messages) and
         scope.requests === frame["run_step"] and
         approvals_position?(record, frame, calls),
       do: :ok,
       else: {:error, :invalid_continuation_position}
  rescue
    _ -> {:error, :invalid_continuation_position}
  end

  defp model_matches?(effect, frame, messages) do
    data = effect["outcome"]["data"]
    payload = effect["intent"]["payload"]
    response = List.last(messages)

    effect["state"] == "confirmed" and effect["outcome"]["status"] == "succeeded" and
      Outcome.model_valid?(data) and data["state_available"] and
      payload["run_id"] == frame["run_id"] and payload["step"] === frame["run_step"] and
      payload["history_index"] === length(messages) - 1 and
      Outcome.hash(Message.to_json([response])) == {:ok, data["response_hash"]} and
      Record.digest(frame["model_data"]) == {:ok, data["model_state_hash"]}
  end

  defp approvals_position?(record, frame, calls) do
    approvals = Map.get(record["execution"]["progress"], "approvals", %{})

    Enum.all?(approvals, fn {approval_id, approval} ->
      if approval["run_id"] == frame["run_id"] and Approval.approved?(approval) do
        request =
          Enum.find_value(record["execution"]["effects"], fn {_, effect} ->
            id = effect["intent"]["call_id"]
            {:ok, hash} = Record.digest([frame["run_id"], id, "approval", approval["call_id"]])
            if effect["intent"]["kind"] == "model" and approval_id == "approval-" <> hash, do: id
          end)

        if request do
          {:ok, hash} = Record.digest([frame["run_id"], request, "tool", approval["call_id"]])

          case record["execution"]["effects"][
                 Retry.active_id(record["execution"], "tool-" <> hash)
               ] do
            %{"state" => "confirmed"} ->
              true

            _ ->
              tree = tree_runtime(record)

              confirmed_child? =
                case child_for(tree, frame["run_id"], request, approval["call_id"]) do
                  {_, %{"status" => "completed", "outcome" => %{"data" => data}}} ->
                    Outcome.valid?(data)

                  _ ->
                    false
                end

              confirmed_child? or
                (frame["cursor"] == "batch" and frame["model_request_id"] == request and
                   Enum.any?(
                     calls,
                     &(&1.tool_call_id == approval["call_id"] and
                         &1.tool_name == approval["tool_name"])
                   ))
          end
        else
          false
        end
      else
        true
      end
    end)
  end

  defp journal_matches?(%{"state" => "confirmed"} = effect, call, bytes, frame, record) do
    # Evidence remains verifiable when retention forbids executing these bytes.
    {:ok, [%Message.Request{parts: [%Message.Part.ToolReturn{} = part]}]} =
      Message.from_json(bytes)

    payload = effect["intent"]["payload"]
    data = effect["outcome"]["data"]
    {:ok, call_hash} = Outcome.call_hash(call)

    {:ok, approval_hash} =
      Record.digest([frame["run_id"], frame["model_request_id"], "approval", call.tool_call_id])

    approval =
      get_in(record, ["execution", "progress", "approvals", "approval-" <> approval_hash])

    base =
      match?(%Message.Part.ToolReturn{}, part) and effect["intent"]["kind"] == "tool" and
        effect["intent"]["call_id"] === call.tool_call_id and
        payload["tool_name"] === call.tool_name and
        payload["call_hash"] === call_hash and
        payload["schema_hash"] ===
          ToolEvidence.schema(
            record,
            frame["run_id"],
            frame["model_request_id"],
            call.tool_name,
            frame["selected_tools"][call.tool_name]
          ) and
        part.tool_name === call.tool_name and
        effect["outcome"]["status"] === Atom.to_string(part.status) and
        Outcome.valid?(data) and Outcome.hash(bytes) == {:ok, data["result_hash"]}

    case payload["phase"] do
      "pre_dispatch" ->
        base and part.status in [:validation_error, :denied, :not_executed, :unknown]

      "dispatch" ->
        base and is_map(payload["args"]) and
          (is_nil(approval) or
             (Approval.approved?(approval) and
                Record.digest(payload["args"]) == Record.digest(approval["args"])))

      _ ->
        false
    end
  end

  defp journal_matches?(_, _, _, _, _), do: false

  defp request_for_effect(record, id) do
    root = record["execution"]["progress"]["runtime"]

    Enum.find_value(Map.get(root, "tool_batches", %{}), fn {_, batch} ->
      if Map.has_key?(batch["observations"], id), do: batch["request_id"]
    end)
  end

  defp delegation_matches?(record, frame, call, bytes) do
    runtime = tree_runtime(record)

    case child_for(runtime, frame["run_id"], frame["model_request_id"], call.tool_call_id) do
      {_,
       %{"status" => "completed", "outcome" => %{"status" => "succeeded", "data" => data}} = child} ->
        raw = %Message.Part.ToolReturn{
          tool_name: call.tool_name,
          tool_call_id: call.tool_call_id,
          status: :succeeded,
          content: child["result"]
        }

        Outcome.valid?(data) and Outcome.hash(raw) == {:ok, data["raw_hash"]} and
          Outcome.hash(bytes) == {:ok, data["result_hash"]} and
          Outcome.call_hash(call) == {:ok, child["call"]["call_hash"]}

      _ ->
        false
    end
  end

  @doc false
  def open_batch?(messages), do: open_calls(messages) != []

  defp open_calls(messages) do
    Enum.reduce(messages, [], fn
      %Message.Response{} = response, open ->
        open ++ Message.Response.tool_calls(response)

      %Message.Request{parts: parts}, open ->
        Enum.reduce(parts, open, fn
          %module{tool_call_id: id}, pending
          when module in [Message.Part.ToolReturn, Message.Part.Retry] and not is_nil(id) ->
            case Enum.split_while(pending, &(&1.tool_call_id != id)) do
              {before, [_ | rest]} -> before ++ rest
              _ -> raise ArgumentError, "unpaired tool result"
            end

          _, pending ->
            pending
        end)
    end)
  end

  defp executable(messages),
    do: if(Retention.executable?(messages), do: :ok, else: {:error, :omitted_payload_history})

  def fingerprint(tool) do
    with {:ok, data} <- fingerprint_data(tool), do: Record.digest(data)
  end

  def fingerprint_data(tool) do
    with {:ok, delegation} <- ExAgent.Continuation.Delegation.descriptor_data(tool.delegation),
         {:ok, binding} <- execution_binding(tool.execution_binding) do
      data = %{
        "definition" => Tool.definition(tool),
        "kind" => Atom.to_string(tool.kind),
        "takes_ctx" => tool.takes_ctx,
        "max_retries" => tool.max_retries
      }

      data = if delegation, do: Map.put(data, "delegation", delegation), else: data
      data = if binding, do: Map.put(data, "execution_binding", binding), else: data
      JSON.normalize(data)
    end
  end

  defp execution_binding(nil), do: {:ok, nil}
  defp execution_binding(:unbound), do: {:error, :tool_continuation_binding_required}

  defp execution_binding(data) do
    if ExAgent.MCP.Binding.valid?(data),
      do: {:ok, data},
      else: {:error, :invalid_tool_continuation_binding}
  end

  def dump_model(model, %{model_codec: %{dump: dump}}) when is_function(dump, 1) do
    with {:ok, data} <- dump.(model), {:ok, data} <- JSON.normalize(data), do: {:ok, data}
  rescue
    _ -> {:error, :model_state_not_persistable}
  end

  def dump_model(_, _), do: {:error, :model_checkpoint_codec_required}

  def aborted(model, run_id, config) do
    with {:ok, binding} <- Model.continuation_binding(model),
         {:ok, data} <- dump_model(model, config),
         true <- Record.text?(run_id) do
      {:ok,
       %{
         "abort_frame_version" => 2,
         "run_id" => run_id,
         "model_data" => data,
         "model_binding" => binding
       }}
    else
      false -> {:error, :invalid_abort_frame}
      {:error, _} = error -> error
    end
  end

  def model_from_record(
        template,
        %{
          "execution" => %{
            "state" => "cancelled",
            "effects" => effects,
            "progress" => %{"runtime" => %{"abort_frame_version" => version} = frame}
          }
        } = record,
        config
      )
      when map_size(effects) == 0 and version in [1, 2] do
    with true <- valid_abort?(frame),
         true <- frame["run_id"] === record["execution"]["run_id"],
         true <-
           Enum.all?(
             [:definition, :policy, :model_ref],
             &(config[&1] == record["execution"][Atom.to_string(&1)])
           ),
         {:ok, model} <- load_bound_model(template, frame, config) do
      {:ok, model}
    else
      false -> {:error, :invalid_abort_frame}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :invalid_abort_frame}
  end

  def model_from_record(template, record, config) do
    frame = record["execution"]["progress"]["runtime"]

    with :ok <- validate(frame),
         :ok <- graph_evidence(record),
         true <-
           Enum.all?(
             [:definition, :policy, :model_ref],
             &(config[&1] == record["execution"][Atom.to_string(&1)])
           ),
         {:ok, model} <- load_bound_model(template, frame, config) do
      {:ok, model}
    else
      false -> {:error, :continuation_definition_changed}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :model_state_not_restorable}
  end

  defp load_model(model, data, %{model_codec: %{load: load}}) when is_function(load, 2) do
    case load.(model, data) do
      {:ok, %_{} = restored} -> {:ok, restored}
      _ -> {:error, :model_state_not_restorable}
    end
  end

  defp load_model(_, _, _), do: {:error, :model_checkpoint_codec_required}

  def valid_abort?(frame) do
    fields =
      ~w(abort_frame_version run_id model_data) ++
        if(frame["abort_frame_version"] == 2, do: ["model_binding"], else: [])

    frame["abort_frame_version"] in [1, 2] and Record.exact?(frame, fields) and
      byte_size(Jason.encode!(Map.get(frame, "model_binding"))) <= 4096
  rescue
    _ -> false
  end

  def delegation_tool(tools, call, config) do
    with {:ok, restored} <-
           restore_tools(tools, %{call["tool_name"] => call["schema_hash"]}, config),
         do: {:ok, restored[call["tool_name"]]}
  end

  defp restore_tools(tools, selected, config) do
    tools =
      case config[:rehydrate_tools] do
        nil -> tools
        fun when is_function(fun, 1) -> fun.(selected)
      end

    available = Map.new(tools, &{&1.name, &1})

    Enum.reduce_while(selected, {:ok, %{}}, fn {name, hash}, {:ok, acc} ->
      with %Tool{} = tool <- available[name],
           {:ok, ^hash} <- fingerprint(tool),
           {:ok, tool} <- Tool.prepare(tool) do
        {:cont, {:ok, Map.put(acc, name, tool)}}
      else
        _ -> {:halt, {:error, :continuation_tools_changed}}
      end
    end)
  end

  defp limits(state) do
    usage = state.usage_limits || %UsageLimits{}
    data = Map.new(@limits, &{Atom.to_string(&1), Map.fetch!(state, &1)})
    usage = Map.from_struct(usage) |> Map.update!(:accounting, &Atom.to_string/1)

    JSON.normalize(
      data
      |> Map.put("usage", usage)
      |> Map.put("output_retries", state.agent.output_retries)
    )
  end

  defp restore_limits(current, stored) do
    current = current || %UsageLimits{}

    data =
      Map.new(Map.from_struct(current), fn {key, value} ->
        old = Map.fetch!(stored, Atom.to_string(key))

        value =
          if key == :accounting do
            if value == :strict or old == "strict", do: :strict, else: :estimated
          else
            minimum(value, old)
          end

        {key, value}
      end)

    limits = struct!(UsageLimits, data)
    with :ok <- UsageLimits.validate(limits), do: {:ok, limits}
  end

  defp permissions(nil), do: %{"default" => "allow", "rules" => []}

  defp permissions(%Permissions{} = p),
    do: %{
      "default" => Atom.to_string(p.default),
      "rules" =>
        Enum.map(p.rules, fn {r, action} ->
          [Regex.source(r), Regex.opts(r), Atom.to_string(action)]
        end)
    }

  defp restore_permissions(data) do
    true = Record.exact?(data, ~w(default rules)) and data["default"] in ~w(allow ask deny)
    action = fn name -> Enum.find([:allow, :ask, :deny], &(Atom.to_string(&1) == name)) end

    rules =
      Enum.map(data["rules"], fn [pattern, options, name] ->
        true = name in ~w(allow ask deny)
        {Regex.compile!(pattern, options), action.(name)}
      end)

    {:ok, %Permissions{default: action.(data["default"]), rules: rules}}
  end

  defp minimum(nil, b), do: b
  defp minimum(a, nil), do: a
  defp minimum(a, b), do: min(a, b)
end
