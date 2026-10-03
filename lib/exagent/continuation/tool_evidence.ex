defmodule ExAgent.Continuation.ToolEvidence do
  @moduledoc false
  alias ExAgent.{Message, Retention}
  alias ExAgent.Message.Usage
  alias ExAgent.Continuation.{Frame, Outcome, Record}
  alias ExAgent.Tool.JSON

  def key(run, request), do: elem(Record.digest([run, request]), 1)

  def effect_id(run, request, call),
    do: "tool-" <> elem(Record.digest([run, request, "tool", call]), 1)

  def batch(run) do
    limits =
      Map.new(Message.Response.tool_calls(List.last(run.messages)), fn call ->
        tool = run.prepared_tools[call.tool_name]
        hash = if tool, do: elem(Frame.fingerprint(tool), 1)

        {call.tool_name,
         %{"schema_hash" => hash, "max_retries" => if(tool, do: tool.max_retries, else: 0)}}
      end)

    %{
      "run_id" => run.run_id,
      "request_id" => run.model_request_id,
      "limits" => limits,
      "observations" => %{},
      "resolution" => nil
    }
  end

  def pre_dispatch,
    do: %{
      "origin" => "pre_dispatch",
      "presence" => "nil",
      "usage" => nil,
      "application" => %{"status" => "none"}
    }

  # Independent input observation, before any retention substitution or ledger write.
  def observe(nil),
    do:
      {%{
         "origin" => "tool_return",
         "presence" => "nil",
         "usage" => nil,
         "application" => %{"status" => "none"}
       }, nil, nil}

  def observe(input) do
    with :ok <- Usage.validate(input),
         {retained, error} <- Retention.usage(Usage.qualify(input)),
         {:ok, data} <- JSON.normalize(Usage.to_map(retained)),
         {:ok, _} <- JSON.encoded_result(data),
         {normalized, normalized_error} <- Retention.usage(Usage.from_map!(data)),
         data = Usage.to_map(normalized) do
      if error || normalized_error || normalized.payload_omitted do
        rejected(input, data, normalized.payload_omitted)
      else
        {%{
           "origin" => "tool_return",
           "presence" => "usage",
           "usage" => data,
           "application" => nil
         }, Usage.from_map!(data), nil}
      end
    else
      _ -> rejected(input, nil, nil)
    end
  rescue
    _ -> rejected(input, nil, nil)
  end

  defp rejected(input, data, marker) do
    marker = marker || Retention.marker(:usage, Retention.bytes(input), Retention.usage_bytes())

    error = %{
      "code" => "invalid_tool_result",
      "message" => "Tool accounting was rejected.",
      "details" => nil,
      "omitted" => marker
    }

    {%{
       "origin" => "tool_return",
       "presence" => "omitted",
       "usage" => data,
       "application" => %{"status" => "rejected", "error" => error}
     }, nil, :invalid_tool_accounting}
  end

  def error(nil), do: nil

  def error(reason) do
    code =
      case reason do
        {:tool_hook_failed, _, _} -> "tool_hook_failed"
        {:tool_execution_failed, _, _} -> "tool_execution_failed"
        {:invalid_tool_result, _, _} -> "invalid_tool_result"
        :invalid_tool_accounting -> "invalid_tool_result"
        {:retention_limit_exceeded, _} -> "retention_limit_exceeded"
        {:checkpoint_failed, _} -> "checkpoint_failed"
        _ -> "runtime_error"
      end

    omitted =
      case reason do
        {:retention_limit_exceeded, %{boundary: b, bytes: n, limit: l}} ->
          Retention.marker(b, n, l)

        _ ->
          nil
      end

    %{
      "code" => code,
      "message" => "Tool batch control failed.",
      "details" => nil,
      "omitted" => omitted
    }
  end

  def error?(nil), do: true

  def error?(e) do
    Record.exact?(e, ~w(code message details omitted)) and
      e["code"] in ~w(tool_hook_failed tool_execution_failed invalid_tool_result retention_limit_exceeded checkpoint_failed runtime_error) and
      is_binary(e["message"]) and String.valid?(e["message"]) and byte_size(e["message"]) <= 512 and
      (is_nil(e["details"]) or is_map(e["details"])) and
      Retention.marker!(e["omitted"]) === e["omitted"] and
      JSON.normalize(e) == {:ok, e} and byte_size(Jason.encode!(e)) <= 4096
  rescue
    _ -> false
  end

  # Version10 only: persisted portable errors deliberately determine the raw
  # bytes. The future producer must use this same projection, not reason_msg/1.
  # No callbacks, retention substitution, schema validation or wrapper execution.
  def child_raw10(child, %Message.Part.ToolCall{} = call) do
    with true <- Record.text?(call.tool_call_id) and Record.text?(call.tool_name),
         true <- child_terminal10?(child) do
      case child["status"] do
        "completed" ->
          if is_nil(child["result_omitted"]),
            do: {:ok, raw10(call, :succeeded, child["result"], nil)},
            else: {:error, :child_result_omitted}

        "failed" ->
          {:ok, raw10(call, :failed, child["error"]["message"], child["error"])}

        "cancelled" ->
          {:error, :child_cancelled}
      end
    else
      _ -> {:error, :invalid_child_terminal}
    end
  rescue
    _ -> {:error, :invalid_child_terminal}
  end

  def child_raw10(_, _), do: {:error, :invalid_child_terminal}

  @doc false
  def child_retention_error10(root, child, result) do
    link = child["link"]

    cond do
      root["frame_version"] == 11 and link["kind"] == "step" ->
        entry = root["output_resolutions"][child["frame"]["model_request_id"]]
        limit = root["binding"]["max_branch_result_bytes"]
        bytes = byte_size(Jason.encode!(result))

        marker =
          entry["result_omitted"] ||
            if(bytes > limit, do: Retention.marker(:output, bytes, limit))

        if marker,
          do: %{
            "code" => "retention_limit_exceeded",
            "message" => "Branch result exceeded its portable output slot.",
            "details" => nil,
            "omitted" => marker
          }

      link["kind"] == "delegate" ->
        call = %Message.Part.ToolCall{tool_name: link["tool_name"], tool_call_id: link["call_id"]}
        bytes = byte_size(raw10(call, :succeeded, result, nil)["result"])
        limit = root["children"][child["parent_run_id"]]["frame"]["tool_return_bytes"]

        if bytes > limit do
          %{
            "code" => "retention_limit_exceeded",
            "message" => "Delegated result exceeded the parent tool slot.",
            "details" => nil,
            "omitted" => Retention.marker(:tool_return, bytes, limit)
          }
        end

      true ->
        nil
    end
  end

  # Only a complete, confirmed text or typed-output preimage can prove this
  # failure. Arbitrary node errors, absent Model state and omitted typed values
  # cannot substitute for that source or reopen a parent wrapper.
  @doc false
  def terminal_retention10?(record, child) do
    root = record["execution"]["progress"]["runtime"]
    frame = child["frame"]
    {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])

    model =
      Enum.find(Map.values(record["execution"]["effects"]), fn effect ->
        effect["intent"]["kind"] == "model" and
          effect["intent"]["call_id"] == frame["model_request_id"] and
          effect["intent"]["payload"]["run_id"] == frame["run_id"]
      end)

    index = model["intent"]["payload"]["history_index"]
    response = Enum.at(messages, index)
    entry = root["output_resolutions"][frame["model_request_id"]]

    {result, position} =
      if entry do
        {entry["result"],
         entry["decision"] == "succeeded" and
           (is_nil(entry["result_omitted"]) or
              (root["frame_version"] == 11 and child["link"]["kind"] == "step")) and
           length(messages) == index + 2 and
           Message.to_json([List.last(messages)]) === entry["parts"]}
      else
        {Message.Response.text(response),
         length(messages) == index + 1 and response.parts != [] and
           Enum.all?(response.parts, &match?(%Message.Part.Text{}, &1))}
      end

    error = child_retention_error10(root, child, result)

    root["frame_version"] in [10, 11] and root["children"][frame["run_id"]] === child and
      (child["link"]["kind"] == "delegate" or
         (root["frame_version"] == 11 and child["link"]["kind"] == "step")) and
      child["status"] == "failed" and
      frame["cursor"] == "response" and
      position and model["state"] == "confirmed" and model["outcome"]["status"] == "succeeded" and
      model["outcome"]["data"]["state_available"] === true and
      Outcome.hash(Message.to_json([response])) ==
        {:ok, model["outcome"]["data"]["response_hash"]} and
      not is_nil(error) and child["error"] === error
  rescue
    _ -> false
  end

  defp raw10(call, status, content, error) do
    %{
      "result" =>
        Outcome.encode(%Message.Part.ToolReturn{
          tool_name: call.tool_name,
          tool_call_id: call.tool_call_id,
          status: status,
          content: content
        }),
      "control" => %{"retry" => false, "error" => error}
    }
  end

  defp child_terminal10?(child) do
    Enum.all?(~w(status result result_omitted error frame), &Map.has_key?(child, &1)) and
      Retention.marker!(child["result_omitted"]) === child["result_omitted"] and
      (is_nil(child["result_omitted"]) or is_nil(child["result"])) and
      case child["status"] do
        "completed" ->
          child["frame"]["cursor"] == "finish" and is_nil(child["error"]) and
            JSON.normalize(child["result"]) === {:ok, child["result"]}

        status when status in ~w(failed cancelled) ->
          child["frame"]["cursor"] != "finish" and is_nil(child["result"]) and
            is_nil(child["result_omitted"]) and not is_nil(child["error"]) and
            error?(child["error"])

        _ ->
          false
      end
  end

  # SOURCE certificate only; it does not attest wrapper callbacks, final control,
  # global authority or admission. Original journal required, never a legacy view.
  def child_source10?(record, batch, id) do
    root = record["execution"]["progress"]["runtime"]
    c = batch["calls"][id]
    child = root["children"][c["source"]["id"]]
    effect = effect_id(batch["run_id"], batch["request_id"], id)

    owners =
      for b <- Map.values(root["tool_batches"]),
          {_, candidate} <- b["calls"],
          candidate["source"] === c["source"],
          do: candidate

    root["frame_version"] in [10, 11] and
      root["tool_batches"][key(batch["run_id"], batch["request_id"])] === batch and
      c["source"]["kind"] == "child" and source10?(c["source"], id, c, batch, root) and
      child["frame"]["run_id"] === c["source"]["id"] and call10?(id, c, batch, root) and
      Frame.validate(child["frame"]) == :ok and
      (child_terminal10?(child) or
         (child["status"] in ~w(running suspended) and child["frame"]["cursor"] != "finish" and
            Enum.all?(~w(result result_omitted error), &is_nil(child[&1])))) and
      length(owners) == 1 and not Map.has_key?(record["execution"]["effects"], effect) and
      not Enum.any?(root["scope"]["operations"], fn op ->
        op["run_id"] == batch["run_id"] and op["id"] == ["tool", batch["request_id"], id]
      end) and
      if is_nil(c["raw"]) do
        child["status"] in ~w(running suspended cancelled) and
          is_nil(batch["observations"][effect]) and
          (child["status"] != "cancelled" or
             (child_terminal10?(child) and c["state"] == "blocked" and
                phase10?(c, root, batch)))
      else
        call = %Message.Part.ToolCall{tool_name: c["binding"]["tool_name"], tool_call_id: id}

        child_raw10(child, call) === {:ok, c["raw"]} and
          batch["observations"][effect] === elem(observe(nil), 0)
      end
  rescue
    _ -> false
  end

  # Host reasons are phase-specific trusted observations, never reconstructed
  # from collapsed portable errors. Global admission has stricter fatal guards.
  def host_source10?(record, batch, id) do
    root = record["execution"]["progress"]["runtime"]
    c = batch["calls"][id]
    effect = effect_id(batch["run_id"], batch["request_id"], id)
    call = Enum.find(model_calls10(record, batch), &(&1.tool_call_id == id))
    source = c["source"]
    reason = source["reason"]
    prepared = source["phase"] != "unprepared"

    binding_valid =
      if prepared do
        source === %{"kind" => "host", "reason" => reason} and binding10?(c["binding"], batch)
      else
        is_nil(c["binding"]) and
          source === %{
            "kind" => "host",
            "phase" => "unprepared",
            "reason" => reason,
            "tool_name" => call.tool_name,
            "call_hash" => elem(Outcome.call_hash(call), 1)
          }
      end

    root["frame_version"] in [10, 11] and
      root["tool_batches"][key(batch["run_id"], batch["request_id"])] === batch and
      binding_valid and host_reason10?(record, batch, call, c) and
      host_raw10(reason, call, c["raw"]["control"]["error"]) === {:ok, c["raw"]} and
      c["result"] === c["raw"]["result"] and c["control"] === c["raw"]["control"] and
      c["state"] == "settled" and is_nil(c["blocked_by"]) and
      batch["observations"][effect] === pre_dispatch() and
      not Map.has_key?(record["execution"]["effects"], effect) and
      not Enum.any?(root["scope"]["operations"], fn op ->
        op["run_id"] == batch["run_id"] and op["id"] == ["tool", batch["request_id"], id]
      end)
  rescue
    _ -> false
  end

  def host_raw10("permission_denied", call, nil),
    do: {:ok, raw10(call, :denied, "Tool #{inspect(call.tool_name)} is not permitted.", nil)}

  def host_raw10(reason, call, error)
      when reason in ~w(before_hook_error unknown_tool malformed_args args_validation_error preparation_retention admission_error) do
    if not is_nil(error) and error?(error) do
      retry = reason in ~w(unknown_tool malformed_args args_validation_error)

      raw =
        raw10(
          call,
          if(retry, do: :validation_error, else: :not_executed),
          error["message"],
          error
        )

      {:ok, put_in(raw, ["control", "retry"], retry)}
    else
      {:error, :invalid_host_source}
    end
  end

  def host_raw10(_, _, _), do: {:error, :invalid_host_source}

  defp host_reason10?(record, batch, call, c) do
    data = Frame.request_data10(record, batch["run_id"], batch["request_id"])
    descriptor = data["tool_descriptors"][call.tool_name]

    case c["source"]["reason"] do
      "unknown_tool" ->
        is_map(data) and is_nil(descriptor)

      reason when reason in ~w(malformed_args args_validation_error) ->
        # The fenced preparing -> rejected transition attests the observed failure
        # AFTER before-hooks. Original args prove identity, not effective args.
        # Unprepared calls deliberately have no effective binding to replay.
        is_map(descriptor)

      _ ->
        true
    end
  end

  # The same ordered reducer handles live errors and their portable counterparts.
  def reduce(controls, retries, limits) do
    Enum.reduce(controls, {retries, nil}, fn {name, status, retry, error}, {counts, fatal} ->
      {counts, error} =
        if retry do
          used = Map.get(counts, name, 0) + 1
          counts = Map.put(counts, name, used)

          if used > limits[name]["max_retries"],
            do: {counts, {:unexpected_model_behavior, {:tool_retries_exhausted, name, error}}},
            else: {counts, nil}
        else
          {if(status in [:succeeded, "succeeded"], do: Map.delete(counts, name), else: counts),
           error}
        end

      {counts, fatal || error}
    end)
  end

  def observation?(o) do
    Record.exact?(o, ~w(origin presence usage application)) and
      o["origin"] in ~w(tool_return pre_dispatch) and
      case {o["presence"], o["application"]} do
        {"nil", %{"status" => "none"} = a} ->
          map_size(a) == 1 and is_nil(o["usage"])

        {"usage", %{"status" => "contributed"} = a} ->
          o["origin"] == "tool_return" and Record.exact?(a, ~w(status complete ancestors)) and
            is_boolean(a["complete"]) and is_map(a["ancestors"]) and usage?(o["usage"], false) and
            Enum.all?(a["ancestors"], fn {id, usage} ->
              Record.text?(id) and usage?(usage, false)
            end)

        {"omitted", %{"status" => "rejected"} = a} ->
          o["origin"] == "tool_return" and Record.exact?(a, ~w(status error)) and
            not is_nil(a["error"]) and error?(a["error"]) and
            (is_nil(o["usage"]) or usage?(o["usage"], true)) and
            (not is_nil(a["error"]["omitted"]) or not is_nil(o["usage"]["payload_omitted"]))

        _ ->
          false
      end
  rescue
    _ -> false
  end

  defp usage?(data, omitted) do
    usage = Usage.from_map!(data)

    Usage.to_map(usage) === data and JSON.normalize(data) == {:ok, data} and
      Retention.bytes(usage) <= Retention.usage_bytes() and
      (omitted or Retention.usage_error(usage) == :ok)
  rescue
    _ -> false
  end

  def valid?(%{"frame_version" => durable_version} = frame) when durable_version in [10, 11] do
    is_map(frame["tool_batches"]) and
      Enum.all?(frame["tool_batches"], fn {id, b} ->
        Record.exact?(b, ~w(run_id request_id limits observations calls resolution consumption)) and
          Record.text?(b["run_id"]) and Record.text?(b["request_id"]) and
          Map.has_key?(frame["children"], b["run_id"]) and id == key(b["run_id"], b["request_id"]) and
          is_map(b["limits"]) and map_size(b["limits"]) > 0 and
          Enum.all?(b["limits"], fn {name, limit} ->
            Record.text?(name) and Record.exact?(limit, ~w(schema_hash max_retries)) and
              (is_nil(limit["schema_hash"]) or hash?(limit["schema_hash"])) and
              Record.counter?(limit["max_retries"])
          end) and is_map(b["calls"]) and map_size(b["calls"]) > 0 and
          Enum.all?(b["calls"], fn {call, data} -> call10?(call, data, b, frame) end) and
          is_map(b["observations"]) and
          Enum.all?(b["observations"], fn {id, obs} ->
            observation?(obs) and
              Enum.any?(b["calls"], fn {call, c} ->
                id == effect_id(b["run_id"], b["request_id"], call) and not is_nil(c["raw"])
              end)
          end) and resolution10?(b) and consumption10?(b)
      end)
  rescue
    _ -> false
  end

  def valid?(frame) do
    is_map(frame["tool_batches"]) and
      Enum.all?(frame["tool_batches"], fn {id, b} ->
        Record.exact?(b, ~w(run_id request_id limits observations resolution)) and
          Record.text?(b["run_id"]) and Record.text?(b["request_id"]) and
          id == key(b["run_id"], b["request_id"]) and
          is_map(b["limits"]) and map_size(b["limits"]) > 0 and
          Enum.all?(b["limits"], fn {name, limit} ->
            Record.text?(name) and Record.exact?(limit, ~w(schema_hash max_retries)) and
              (is_nil(limit["schema_hash"]) or hash?(limit["schema_hash"])) and
              Record.counter?(limit["max_retries"])
          end) and is_map(b["observations"]) and
          Enum.all?(b["observations"], fn {effect, obs} ->
            Record.text?(effect) and observation?(obs)
          end) and
          resolution?(b["resolution"])
      end)
  rescue
    _ -> false
  end

  defp hash?(h),
    do: is_binary(h) and byte_size(h) == 64 and String.match?(h, ~r/\A[0-9a-f]{64}\z/)

  defp call10?(id, c, batch, root) do
    identity = c["binding"] || Map.take(c["source"] || %{}, ["tool_name"])

    Record.text?(id) and Record.exact?(c, ~w(state binding source raw result control blocked_by)) and
      (is_nil(c["binding"]) or binding10?(c["binding"], batch)) and
      (is_nil(c["source"]) or source10?(c["source"], id, c, batch, root)) and
      (is_nil(c["raw"]) or
         (Record.exact?(c["raw"], ~w(result control)) and not is_nil(c["source"]) and
            return10?(c["raw"]["result"], id, identity) and control10?(c["raw"]["control"]))) and
      (is_nil(c["result"]) or return10?(c["result"], id, identity)) and
      (is_nil(c["control"]) or control10?(c["control"])) and
      phase10?(c, root, batch)
  end

  defp binding10?(binding, batch) do
    Record.exact?(binding, ~w(tool_name args schema_hash call_hash)) and
      Record.text?(binding["tool_name"]) and is_map(binding["args"]) and
      hash?(binding["schema_hash"]) and hash?(binding["call_hash"]) and
      binding["schema_hash"] === batch["limits"][binding["tool_name"]]["schema_hash"]
  end

  defp source10?(%{"kind" => "effect"} = source, id, c, batch, _root) do
    Record.exact?(source, ~w(kind id)) and not is_nil(c["binding"]) and
      source["id"] === effect_id(batch["run_id"], batch["request_id"], id)
  end

  defp source10?(%{"kind" => "child"} = source, id, c, batch, root) do
    child = root["children"][source["id"]]

    Record.exact?(source, ~w(kind id)) and Record.text?(source["id"]) and
      not is_nil(c["binding"]) and child["parent_run_id"] === batch["run_id"] and
      child["link"]["kind"] == "delegate" and
      child["link"]["parent_request_id"] === batch["request_id"] and
      child["link"]["call_id"] === id and
      Map.take(child["link"] || %{}, ~w(tool_name args schema_hash call_hash)) === c["binding"] and
      (is_nil(c["raw"]) or child["status"] in ~w(completed failed cancelled))
  end

  defp source10?(%{"kind" => "host", "phase" => "unprepared"} = source, _, c, _, _) do
    Record.exact?(source, ~w(kind phase reason tool_name call_hash)) and is_nil(c["binding"]) and
      Record.text?(source["tool_name"]) and hash?(source["call_hash"]) and
      source["reason"] in ~w(before_hook_error unknown_tool malformed_args args_validation_error preparation_retention)
  end

  defp source10?(%{"kind" => "host", "reason" => reason} = source, _, c, _, _)
       when reason in ~w(permission_denied admission_error) do
    Record.exact?(source, ~w(kind reason)) and not is_nil(c["binding"])
  end

  # No other source shape can replace preparation evidence with a fake intent.
  defp source10?(_, _, _, _, _), do: false

  defp control10?(c),
    do: Record.exact?(c, ~w(retry error)) and is_boolean(c["retry"]) and error?(c["error"])

  defp return10?(bytes, id, binding) when is_binary(bytes) do
    with {:ok, [%Message.Request{parts: [%Message.Part.ToolReturn{} = part]}]} <-
           Message.from_json(bytes) do
      part.tool_call_id === id and part.tool_name === binding["tool_name"] and
        Outcome.encode(part) === bytes
    else
      _ -> false
    end
  end

  defp return10?(_, _, _), do: false

  defp phase10?(c, root, batch) do
    unfinished = is_nil(c["result"]) and is_nil(c["control"])
    unblocked = is_nil(c["blocked_by"])
    bound = not is_nil(c["binding"])

    case c["state"] do
      state when state in ~w(queued preparing) ->
        Enum.all?(~w(binding source raw result control blocked_by), &is_nil(c[&1]))

      state when state in ~w(prepared approval) ->
        bound and unfinished and unblocked and is_nil(c["source"]) and is_nil(c["raw"])

      "dispatching" ->
        bound and unfinished and unblocked and c["source"]["kind"] == "effect"

      "child" ->
        bound and unfinished and unblocked and c["source"]["kind"] == "child"

      "wrapping" ->
        bound and unfinished and unblocked and not is_nil(c["raw"])

      "settled" ->
        (bound or c["source"]["phase"] == "unprepared") and unblocked and not is_nil(c["raw"]) and
          not is_nil(c["result"]) and
          not is_nil(c["control"])

      "blocked" ->
        unfinished and c["blocked_by"] == "fatal" and
          (root["frontier"]["reason"] == "fatal" or
             (root["frame_version"] == 11 and
                Map.has_key?(root["flow"]["failures"], Frame.branch_id11(root, batch["run_id"]))))

      _ ->
        false
    end
  end

  defp resolution10?(%{"resolution" => nil}), do: true

  defp resolution10?(%{"resolution" => r} = batch) do
    Record.exact?(r, ~w(tool_retries error)) and is_map(r["tool_retries"]) and error?(r["error"]) and
      Enum.all?(r["tool_retries"], fn {name, count} ->
        Record.text?(name) and Record.counter?(count)
      end) and
      Enum.all?(batch["calls"], fn {_, c} -> c["state"] == "settled" end)
  end

  defp consumption10?(%{"consumption" => nil}), do: true

  defp consumption10?(%{"consumption" => c} = batch) do
    Record.exact?(c, ~w(history_index returns_hash)) and Record.counter?(c["history_index"]) and
      hash?(c["returns_hash"]) and
      not is_nil(batch["resolution"]) and is_nil(batch["resolution"]["error"])
  end

  defp resolution?(nil), do: true

  defp resolution?(r) do
    Record.exact?(r, ~w(calls settle_error)) and is_list(r["calls"]) and error?(r["settle_error"]) and
      Enum.all?(r["calls"], fn c ->
        Record.exact?(c, ~w(effect_id result_hash retry error)) and Record.text?(c["effect_id"]) and
          hash?(c["result_hash"]) and is_boolean(c["retry"]) and error?(c["error"])
      end)
  end

  def schema(record, run, request, name, fallback) do
    root = record["execution"]["progress"]["runtime"]

    if root["frame_version"] in [8, 9],
      do: get_in(root, ["tool_batches", key(run, request), "limits", name, "schema_hash"]),
      else: fallback
  end

  def calls(
        %{
          "execution" => %{
            "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
          }
        } =
          record,
        batch
      )
      when durable_version in [10, 11] do
    # This is an internal journal reader, not admission of a Frame10 execution.
    # Never manufacture a legacy record or trust a caller-supplied batch copy.
    true = Frame.validate(root) == :ok
    true = root["tool_batches"][key(batch["run_id"], batch["request_id"])] === batch
    true = model_coverage10?(record)
    true = tool_partition10?(record)
    model_calls10(record, batch)
  end

  def calls(record, batch) do
    model =
      record["execution"]["effects"]
      |> Map.values()
      |> Enum.find(fn effect ->
        effect["intent"]["kind"] == "model" and effect["intent"]["call_id"] == batch["request_id"] and
          effect["intent"]["payload"]["run_id"] == batch["run_id"]
      end)

    child = record["execution"]["progress"]["runtime"]["children"][batch["run_id"]]
    {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])
    Message.Response.tool_calls(Enum.at(messages, model["intent"]["payload"]["history_index"]))
  end

  defp model_calls10(record, batch) do
    root = record["execution"]["progress"]["runtime"]

    [model] =
      Enum.filter(Map.values(record["execution"]["effects"]), fn effect ->
        effect["intent"]["kind"] == "model" and
          effect["intent"]["call_id"] == batch["request_id"] and
          effect["intent"]["payload"]["run_id"] == batch["run_id"]
      end)

    true = model["state"] == "confirmed" and model["outcome"]["status"] == "succeeded"

    {:ok, messages} =
      Message.from_json(root["children"][batch["run_id"]]["snapshot"]["message_history"])

    response = Enum.at(messages, model["intent"]["payload"]["history_index"])
    calls = Message.Response.tool_calls(response)
    ids = Enum.map(calls, & &1.tool_call_id)
    true = calls != [] and length(ids) == length(Enum.uniq(ids))
    true = Enum.all?(calls, &(&1.kind == :function))
    true = Enum.sort(ids) === Enum.sort(Map.keys(batch["calls"]))
    true = MapSet.new(calls, & &1.tool_name) == MapSet.new(Map.keys(batch["limits"]))

    true =
      Enum.all?(calls, fn call ->
        binding = batch["calls"][call.tool_call_id]["binding"]

        is_nil(binding) or
          (binding["tool_name"] === call.tool_name and
             Outcome.call_hash(call) == {:ok, binding["call_hash"]})
      end)

    calls
  end

  defp model_coverage10?(record) do
    root = record["execution"]["progress"]["runtime"]

    models =
      Enum.filter(Map.values(record["execution"]["effects"]), &(&1["intent"]["kind"] == "model"))

    requests = Enum.map(models, & &1["intent"]["call_id"])
    admitted = root["scope"]["batches"]

    length(requests) == length(Enum.uniq(requests)) and
      Enum.all?(models, &Map.has_key?(root["children"], &1["intent"]["payload"]["run_id"])) and
      length(admitted) == map_size(root["tool_batches"]) and
      MapSet.new(admitted, &key(&1["run_id"], &1["id"])) ==
        MapSet.new(Map.keys(root["tool_batches"])) and
      Enum.all?(admitted, fn b ->
        batch = root["tool_batches"][key(b["run_id"], b["id"])]
        length(model_calls10(record, batch)) === b["count"]
      end) and
      Enum.all?(root["children"], fn {run, child} ->
        own =
          models
          |> Enum.filter(&(&1["intent"]["payload"]["run_id"] == run))
          |> Enum.sort_by(& &1["intent"]["payload"]["step"])

        {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])

        confirmed =
          Enum.filter(
            own,
            &(&1["state"] == "confirmed" and &1["outcome"]["status"] == "succeeded")
          )

        positions = for {%Message.Response{}, i} <- Enum.with_index(messages), do: i

        child["frame"]["run_step"] === length(own) and
          child["frame"]["scope"]["requests"] === length(own) and
          child["frame"]["model_request_id"] === get_in(List.last(own), ["intent", "call_id"]) and
          Enum.map(own, & &1["intent"]["payload"]["step"]) === Enum.to_list(1..length(own)//1) and
          positions === Enum.map(confirmed, & &1["intent"]["payload"]["history_index"]) and
          Enum.all?(confirmed, fn model ->
            index = model["intent"]["payload"]["history_index"]
            data = model["outcome"]["data"]
            response = Enum.at(messages, index)
            request = model["intent"]["call_id"]
            batch = root["tool_batches"][key(run, request)]
            output = root["output_resolutions"][request]

            requires_batch =
              match?(%Message.Response{}, response) and
                Message.Response.tool_calls(response) != [] and is_nil(output) and
                (index < length(messages) - 1 or child["frame"]["cursor"] == "batch")

            Record.counter?(index) and match?(%Message.Response{}, response) and
              (not requires_batch or not is_nil(batch)) and
              (is_nil(output) or is_nil(batch)) and
              Outcome.model_valid?(data) and
              Outcome.hash(Message.to_json([response])) == {:ok, data["response_hash"]}
          end)
      end)
  rescue
    _ -> false
  end

  def pending_receipts(%{
        "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
      })
      when durable_version in [10, 11] do
    Enum.reduce(root["tool_batches"], 0, fn {_, batch}, total ->
      total + if(is_nil(batch["consumption"]), do: 2 + 8 * map_size(batch["calls"]), else: 0)
    end)
  end

  def pending_receipts(e) do
    root = e["progress"]["runtime"]

    Enum.reduce(Map.get(root || %{}, "tool_batches", %{}), 0, fn {_, b}, count ->
      if is_nil(b["resolution"]) do
        admitted =
          Enum.find(
            root["scope"]["batches"],
            &(&1["run_id"] == b["run_id"] and &1["id"] == b["request_id"])
          )

        existing =
          Enum.count(e["effects"], fn {id, effect} ->
            effect["intent"]["kind"] == "tool" and
              id == effect_id(b["run_id"], b["request_id"], effect["intent"]["call_id"])
          end)

        count + 1 + 3 * max(admitted["count"] - existing, 0)
      else
        count
      end
    end)
  end

  def reservation_usage do
    # Pick the largest escaped binary which fits the actual retained Usage term.
    base =
      Usage.qualify(%Usage{input_tokens: 0, output_tokens: 0, details: %{"reservation" => ""}})

    size = max(Retention.usage_bytes() - Retention.bytes(base), 0)
    %{base | details: %{"reservation" => String.duplicate(<<1>>, size)}}
  end

  def reservation_error do
    base = %{
      "code" => "retention_limit_exceeded",
      "message" => String.duplicate(<<1>>, 512),
      "details" => %{"reservation" => ""},
      "omitted" => Retention.marker(:checkpoint, 9_223_372_036_854_775_807, 67_108_864)
    }

    put_in(
      base,
      ["details", "reservation"],
      String.duplicate("x", 4096 - byte_size(Jason.encode!(base)))
    )
  end

  # The grammar is deliberately not a certificate of ordered model responses,
  # canonical effect outcomes, accounting, consumption or callback quiescence.
  defp evidence10?(
         %{
           "execution" => %{
             "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
           }
         } =
           record
       )
       when durable_version in [10, 11] do
    record["execution"]["state"] in ~w(ready claimed pending uncertain expired completed failed) and
      Enum.all?(record["execution"]["effects"], fn {_, effect} ->
        effect["intent"]["kind"] != "model" or
          ExAgent.Continuation.RequestData.valid10?(effect["intent"]["payload"]["request_data"])
      end) and valid?(root) and model_coverage10?(record) and tool_partition10?(record) and
      Enum.all?(root["tool_batches"], fn {_, batch} ->
        Enum.all?(batch["calls"], fn {_, c} ->
          known_result10?(c["result"]) and
            (is_nil(c["raw"]["control"]["error"]) or
               c["raw"]["control"]["retry"] === true or
               raw_fatal10?(c) or
               (c["source"]["kind"] == "host" and c["state"] == "settled") or
               (c["source"]["kind"] == "child" and
                  (ExAgent.Continuation.OutputResolution.terminal_exhaustion10?(
                     record,
                     root["children"][c["source"]["id"]]
                   ) or terminal_retention10?(record, root["children"][c["source"]["id"]]))))
        end)
      end) and
      Enum.all?(root["children"], fn {run, child} ->
        models =
          record["execution"]["effects"]
          |> Map.values()
          |> Enum.filter(
            &(&1["intent"]["kind"] == "model" and &1["intent"]["payload"]["run_id"] == run)
          )
          |> Enum.sort_by(& &1["intent"]["payload"]["step"])

        counts =
          Enum.reduce(models, %{}, fn model, counts ->
            case root["tool_batches"][key(run, model["intent"]["call_id"])] do
              nil ->
                counts

              batch ->
                {next, error} = reduce_resolution(batch, calls(record, batch), record, counts)
                true = durable_version == 11 or is_nil(error)
                next
            end
          end)

        counts === child["frame"]["tool_retries"]
      end)
  rescue
    _ -> false
  end

  # A known, confirmed effect's raw fatal control forbids its wrapper. Unknown
  # effects and arbitrary node/root error strings remain outside this certificate.
  @doc false
  def raw_fatal10?(c) do
    c["source"]["kind"] == "effect" and is_map(c["raw"]) and
      c["raw"]["control"]["retry"] === false and
      not is_nil(c["raw"]["control"]["error"]) and known_result10?(c["raw"]["result"])
  end

  # Node ranks before its own calls, by structural path. A final control, when
  # present, owns the call's decision; raw and wrapper never authorize replay.
  # Call positions come from the confirmed response, never map/arrival order.
  def selected_call_fatal10(record) do
    ranked_call_fatals10(record)
    |> Enum.min_by(&elem(&1, 0), fn -> nil end)
    |> case do
      nil -> nil
      {_, fatal} -> fatal
    end
  end

  @doc false
  def branch_fatals11(record) do
    root = record["execution"]["progress"]["runtime"]

    ranked_call_fatals10(record)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(%{}, fn {_, fatal}, acc ->
      Map.put_new(acc, Frame.branch_id11(root, fatal["run_id"]), fatal)
    end)
  end

  defp ranked_call_fatals10(record) do
    root = record["execution"]["progress"]["runtime"]

    nodes =
      Enum.flat_map(root["children"], fn {run, child} ->
        if ExAgent.Continuation.OutputResolution.terminal_exhaustion10?(record, child) or
             terminal_retention10?(record, child) do
          [
            {{fatal_path10(record, run), -1, -1},
             %{"kind" => "node", "run_id" => run, "error" => child["error"]}}
          ]
        else
          []
        end
      end)

    root["tool_batches"]
    |> Enum.flat_map(fn {_, batch} ->
      ordered = model_calls10(record, batch)

      batch_fatal =
        if root["frame_version"] == 11 and not is_nil(batch["resolution"]["error"]) do
          [
            {{fatal_path10(record, batch["run_id"]),
              request_step10(record, batch["run_id"], batch["request_id"]), length(ordered)},
             %{
               "kind" => "batch",
               "run_id" => batch["run_id"],
               "request_id" => batch["request_id"],
               "error" => batch["resolution"]["error"]
             }}
          ]
        else
          []
        end

      ordered
      |> Enum.with_index()
      |> Enum.flat_map(fn {call, index} ->
        phase = batch["calls"][call.tool_call_id]
        control = phase["control"] || phase["raw"]["control"]

        if (phase["state"] == "settled" or raw_fatal10?(phase)) and
             control["retry"] === false and not is_nil(control["error"]) do
          rank =
            {fatal_path10(record, batch["run_id"]),
             request_step10(record, batch["run_id"], batch["request_id"]), index}

          [
            {rank,
             %{
               "kind" => "call",
               "run_id" => batch["run_id"],
               "request_id" => batch["request_id"],
               "call_id" => call.tool_call_id,
               "error" => control["error"]
             }}
          ]
        else
          []
        end
      end)
      |> Kernel.++(batch_fatal)
    end)
    |> Kernel.++(nodes)
  end

  defp fatal_path10(record, run) do
    root = record["execution"]["progress"]["runtime"]
    node = root["children"][run]
    link = node["link"]

    if link["kind"] == "step" do
      [link["index"]]
    else
      parent = node["parent_run_id"]
      batch = root["tool_batches"][key(parent, link["parent_request_id"])]

      position =
        Enum.find_index(model_calls10(record, batch), &(&1.tool_call_id == link["call_id"]))

      fatal_path10(record, parent) ++
        [request_step10(record, parent, link["parent_request_id"]), position]
    end
  end

  defp request_step10(record, run, request) do
    record["execution"]["effects"]
    |> Map.values()
    |> Enum.find(fn effect ->
      effect["intent"]["kind"] == "model" and effect["intent"]["call_id"] == request and
        effect["intent"]["payload"]["run_id"] == run
    end)
    |> get_in(["intent", "payload", "step"])
  end

  def evidence?(
        %{"execution" => %{"progress" => %{"runtime" => %{"frame_version" => durable_version}}}} =
          record
      )
      when durable_version in [10, 11], do: evidence10?(record)

  def evidence?(
        %{"execution" => %{"progress" => %{"runtime" => %{"frame_version" => version} = root}}} =
          record
      )
      when version in [8, 9] do
    batches = root["tool_batches"]
    expected = MapSet.new(root["scope"]["batches"], &key(&1["run_id"], &1["id"]))

    MapSet.new(Map.keys(batches)) == expected and
      Enum.all?(root["children"], fn {run, child} ->
        {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])

        models =
          record["execution"]["effects"]
          |> Map.values()
          |> Enum.filter(
            &(&1["intent"]["kind"] == "model" and &1["intent"]["payload"]["run_id"] == run)
          )
          |> Enum.sort_by(& &1["intent"]["payload"]["step"])

        {counts, valid} =
          Enum.reduce(models, {%{}, true}, fn model, {counts, valid} ->
            request = model["intent"]["call_id"]

            case batches[key(run, request)] do
              nil ->
                {counts, valid}

              batch ->
                calls =
                  Message.Response.tool_calls(
                    Enum.at(messages, model["intent"]["payload"]["history_index"])
                  )

                consumed =
                  child["frame"]["model_request_id"] != request or child["status"] == "completed"

                {next, fatal} = reduce_resolution(batch, calls, record, counts)

                {next,
                 valid and batch_evidence?(batch, calls, record) and
                   (not consumed or (not is_nil(batch["resolution"]) and is_nil(fatal)))}
            end
          end)

        valid and counts === child["frame"]["tool_retries"] and
          (not rejected?(root, run) or
             (not Usage.complete?(Usage.from_map!(child["snapshot"]["usage"])) and
                is_nil(child["snapshot"]["usage"]["accounting"]["cost"]["cents"])))
      end)
  rescue
    _ -> false
  end

  def evidence?(_), do: true

  def rejected?(root, run) do
    Enum.any?(root["tool_batches"], fn {_, batch} ->
      batch["run_id"] == run and
        Enum.any?(batch["observations"], fn {_, obs} ->
          obs["application"]["status"] == "rejected"
        end)
    end)
  end

  def reduce_resolution(
        batch,
        ordered,
        %{
          "execution" => %{
            "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
          }
        } =
          record,
        counts
      )
      when durable_version in [10, 11] do
    true = calls(record, batch) === ordered
    true = historical_retries10(record, batch) === counts
    reduce_batch10(batch, ordered, record, root, counts)
  end

  def reduce_resolution(%{"resolution" => nil}, _, _, counts), do: {counts, nil}

  def reduce_resolution(batch, calls, record, counts) do
    controls =
      Enum.zip(calls, batch["resolution"]["calls"])
      |> Enum.map(fn {call, control} ->
        effect = record["execution"]["effects"][control["effect_id"]]
        {call.tool_name, effect["outcome"]["status"], control["retry"], control["error"]}
      end)

    {next, fatal} = reduce(controls, counts, batch["limits"])
    {next, fatal || batch["resolution"]["settle_error"]}
  end

  defp reduce_batch10(batch, ordered, record, root, counts) do
    if is_nil(batch["resolution"]) do
      {counts, nil}
    else
      controls =
        Enum.map(ordered, fn call ->
          c = batch["calls"][call.tool_call_id]
          true = settled_effect10?(record, batch, call, c)
          {:ok, [%Message.Request{parts: [part]}]} = Message.from_json(c["result"])
          {call.tool_name, part.status, c["control"]["retry"], c["control"]["error"]}
        end)

      {next, fatal} = reduce(controls, counts, batch["limits"])
      portable = if is_map(fatal), do: fatal, else: error(fatal)
      true = batch["resolution"] === %{"tool_retries" => next, "error" => portable}
      true = consumption_evidence10?(record, batch, ordered)
      child = root["children"][batch["run_id"]]

      true =
        child["frame"]["model_request_id"] == batch["request_id"] or
          (not is_nil(batch["consumption"]) and is_nil(fatal))

      {next, fatal}
    end
  end

  # Uncertainty recovery is outside the admitted Frame10 subset, including child
  # finals with no external effect whose status could otherwise carry this gate.
  defp known_result10?(nil), do: true

  defp known_result10?(bytes) do
    case Message.from_json(bytes) do
      {:ok, [%Message.Request{parts: [%Message.Part.ToolReturn{status: status}]}]} ->
        status != :unknown

      _ ->
        false
    end
  end

  # Every predecessor batch must have consumed exactly its own adjacent returns.
  # Replaying the same reducer from the first model request makes caller counts
  # a checked input, rather than an alternate source of historical truth.
  defp historical_retries10(record, batch) do
    root = record["execution"]["progress"]["runtime"]

    models =
      record["execution"]["effects"]
      |> Map.values()
      |> Enum.filter(
        &(&1["intent"]["kind"] == "model" and
            &1["intent"]["payload"]["run_id"] == batch["run_id"])
      )
      |> Enum.sort_by(& &1["intent"]["payload"]["step"])
      |> Enum.take_while(&(&1["intent"]["call_id"] != batch["request_id"]))

    Enum.reduce(models, %{}, fn model, counts ->
      case root["tool_batches"][key(batch["run_id"], model["intent"]["call_id"])] do
        nil ->
          counts

        previous ->
          true = not is_nil(previous["resolution"]) and not is_nil(previous["consumption"])
          ordered = model_calls10(record, previous)
          {next, nil} = reduce_batch10(previous, ordered, record, root, counts)
          next
      end
    end)
  end

  # Partition the ORIGINAL journal, including calls which have not settled yet.
  # A local batch view must not conceal orphan effects, accounting or leaf returns.
  defp tool_partition10?(record) do
    root = record["execution"]["progress"]["runtime"]
    batches = Map.values(root["tool_batches"])

    sources =
      for b <- batches,
          {id, c} <- b["calls"],
          c["source"]["kind"] == "effect",
          do: {effect_id(b["run_id"], b["request_id"], id), b, id, c}

    effects =
      for {id, e} <- record["execution"]["effects"], e["intent"]["kind"] == "tool", do: id

    expected_ops =
      for b <- batches,
          {id, _c} <- b["calls"],
          b["observations"][effect_id(b["run_id"], b["request_id"], id)]["application"]["status"] ==
            "contributed",
          do: {b["run_id"], ["tool", b["request_id"], id]}

    ops =
      for op <- root["scope"]["operations"],
          match?(["tool" | _], op["id"]),
          do: {op["run_id"], op["id"]}

    Enum.sort(effects) === Enum.sort(Enum.map(sources, &elem(&1, 0))) and
      Enum.sort(ops) === Enum.sort(expected_ops) and
      Enum.all?(sources, fn {_, b, id, c} -> effect_call10?(record, b, id, c) end) and
      Enum.all?(batches, fn b ->
        Enum.all?(b["calls"], fn {id, c} ->
          obs = b["observations"][effect_id(b["run_id"], b["request_id"], id)]

          case c["source"]["kind"] do
            nil -> is_nil(obs)
            "effect" -> true
            "child" -> child_source10?(record, b, id)
            "host" -> host_source10?(record, b, id)
            _ -> false
          end
        end)
      end) and
      Enum.all?(root["children"], fn {run, child} ->
        current = root["tool_batches"][key(run, child["frame"]["model_request_id"])]

        expected =
          if current && is_nil(current["consumption"]) do
            for {id, c} <- current["calls"],
                bytes = c["result"] || c["raw"]["result"],
                not is_nil(bytes),
                into: %{},
                do: {id, bytes}
          else
            %{}
          end

        child["frame"]["outcomes"] === expected
      end)
  rescue
    _ -> false
  end

  # The narrow call_settle transition owns final-wrapper attestation. A generic
  # receipt never proves a target call; source/raw and final are separate fields.
  defp settled_effect10?(record, batch, call, c) do
    c["state"] == "settled" and
      case c["source"]["kind"] do
        "effect" ->
          effect_call10?(record, batch, call.tool_call_id, c)

        "host" ->
          host_source10?(record, batch, call.tool_call_id)

        "child" ->
          record["execution"]["state"] in ~w(ready claimed pending uncertain expired completed failed) and
            ExAgent.Continuation.RequestData.valid10?(
              Frame.request_data10(record, batch["run_id"], batch["request_id"])
            ) and
            child_source10?(record, batch, call.tool_call_id)

        _ ->
          false
      end
  end

  defp effect_call10?(record, batch, call_id, c) do
    run = batch["run_id"]
    request = batch["request_id"]
    id = effect_id(run, request, call_id)
    effect = record["execution"]["effects"][id]
    payload = effect["intent"]["payload"]
    data = effect["outcome"]["data"]
    root = record["execution"]["progress"]["runtime"]
    obs = batch["observations"][id]

    ops =
      Enum.filter(root["scope"]["operations"], fn op ->
        op["run_id"] == run and op["id"] == ["tool", request, call_id]
      end)

    c["source"] === %{"kind" => "effect", "id" => id} and
      effect["intent"]["kind"] == "tool" and effect["intent"]["call_id"] == call_id and
      payload["run_id"] == run and payload["model_request_id"] == request and
      payload["phase"] == "dispatch" and
      Map.take(payload, ~w(tool_name args schema_hash call_hash)) === c["binding"] and
      if is_nil(c["raw"]) do
        c["state"] in ~w(dispatching blocked) and effect["state"] == "running" and
          is_nil(effect["outcome"]) and is_nil(obs) and ops == []
      else
        bytes = c["result"] || c["raw"]["result"]
        {:ok, [%Message.Request{parts: [part]}]} = Message.from_json(bytes)
        phase = if c["state"] == "settled", do: "final", else: "raw"

        effect["state"] == "confirmed" and Outcome.valid?(data) and data["phase"] == phase and
          Outcome.hash(c["raw"]["result"]) == {:ok, data["raw_hash"]} and
          Outcome.hash(bytes) == {:ok, data["result_hash"]} and
          effect["outcome"]["status"] == Atom.to_string(part.status) and
          observation?(obs) and obs["origin"] == "tool_return" and
          obs["application"]["status"] in ~w(none contributed rejected) and length(ops) <= 1 and
          accounting10?(obs, List.first(ops), run, request, call_id)
      end
  rescue
    _ -> false
  end

  defp consumption_evidence10?(record, batch, ordered) do
    root = record["execution"]["progress"]["runtime"]
    child = root["children"][batch["run_id"]]
    {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])

    model =
      Enum.find(Map.values(record["execution"]["effects"]), fn e ->
        e["intent"]["kind"] == "model" and e["intent"]["call_id"] == batch["request_id"]
      end)

    index = model["intent"]["payload"]["history_index"] + 1

    if is_nil(batch["consumption"]) do
      length(messages) == index and child["frame"]["model_request_id"] == batch["request_id"]
    else
      parts =
        Enum.map(ordered, fn call ->
          {:ok, [%Message.Request{parts: [part]}]} =
            Message.from_json(batch["calls"][call.tool_call_id]["result"])

          part
        end)

      expected = Message.to_json([%Message.Request{parts: parts}])
      {:ok, hash} = Outcome.hash(expected)

      batch["consumption"] === %{"history_index" => index, "returns_hash" => hash} and
        Message.to_json([Enum.at(messages, index)]) === expected and
        (child["frame"]["model_request_id"] != batch["request_id"] or
           (length(messages) == index + 1 and child["frame"]["cursor"] == "request" and
              child["frame"]["outcomes"] == %{}))
    end
  rescue
    _ -> false
  end

  defp batch_evidence?(batch, calls, record) do
    run = batch["run_id"]
    request = batch["request_id"]
    effects = record["execution"]["effects"]
    root = record["execution"]["progress"]["runtime"]
    ids = Enum.map(calls, &effect_id(run, request, &1.tool_call_id))

    ops =
      Enum.filter(
        root["scope"]["operations"],
        &(&1["run_id"] == run and match?(["tool", ^request | _], &1["id"]))
      )

    MapSet.new(Map.keys(batch["limits"])) == MapSet.new(calls, & &1.tool_name) and
      Enum.all?(batch["observations"], fn {id, obs} ->
        effect = effects[id]
        op = Enum.find(ops, &(&1["id"] == ["tool", request, effect["intent"]["call_id"]]))

        id in ids and effect["state"] == "confirmed" and
          (obs["origin"] != "pre_dispatch" or
             effect["intent"]["payload"]["phase"] == "pre_dispatch") and
          (obs["origin"] != "tool_return" or effect["intent"]["payload"]["phase"] == "dispatch") and
          accounting?(obs, op, run, request, effect["intent"]["call_id"])
      end) and
      Enum.all?(ids, fn id ->
        effects[id]["state"] != "confirmed" or Map.has_key?(batch["observations"], id)
      end) and
      Enum.all?(ops, fn op ->
        ["tool", ^request, call] = op["id"]

        batch["observations"][effect_id(run, request, call)]["application"]["status"] ==
          "contributed"
      end) and
      (is_nil(batch["resolution"]) or
         (Enum.map(batch["resolution"]["calls"], & &1["effect_id"]) == ids and
            Enum.all?(batch["resolution"]["calls"], fn c ->
              effect = effects[c["effect_id"]]

              effect["state"] == "confirmed" and effect["outcome"]["data"]["phase"] == "final" and
                effect["outcome"]["data"]["result_hash"] == c["result_hash"] and
                Map.has_key?(batch["observations"], c["effect_id"]) and
                (batch["observations"][c["effect_id"]]["application"]["status"] != "rejected" or
                   (c["retry"] == false and not is_nil(c["error"])))
            end)))
  end

  # Frame10 records availability completeness, rather than inferring it from
  # integer subtotals. Legacy certificates retain their historical semantics.
  defp accounting10?(
         %{"application" => %{"status" => "contributed"} = a, "usage" => usage} = obs,
         op,
         run,
         request,
         call
       ) do
    a["complete"] === Usage.complete?(Usage.from_map!(usage)) and
      Enum.all?(a["ancestors"], fn {_, value} -> value === usage end) and
      accounting_operation?(obs, op, run, request, call)
  end

  defp accounting10?(obs, op, _, _, _),
    do:
      is_nil(op) and
        ((obs["presence"] == "nil" and obs["application"] === %{"status" => "none"}) or
           (obs["presence"] == "omitted" and obs["application"]["status"] == "rejected"))

  defp accounting?(
         %{"application" => %{"status" => "contributed"} = a, "usage" => usage} = obs,
         op,
         run,
         request,
         call
       ) do
    a["complete"] == (is_integer(usage["input_tokens"]) and is_integer(usage["output_tokens"])) and
      accounting_operation?(obs, op, run, request, call)
  end

  defp accounting?(_, op, _, _, _), do: is_nil(op)

  defp accounting_operation?(
         %{"application" => %{"status" => "contributed"} = a, "usage" => usage},
         op,
         run,
         request,
         call
       ) do
    op === %{
      "id" => ["tool", request, call],
      "run_id" => run,
      "usage" => usage,
      "terminal_usage" => usage,
      "complete" => a["complete"],
      "ancestors" => a["ancestors"]
    }
  end

  def transition?(%{"frame_version" => durable_version}, _, _) when durable_version in [10, 11],
    do: false

  def transition?(_, %{"frame_version" => durable_version}, _) when durable_version in [10, 11],
    do: false

  def transition?(old, new, operation) do
    if old["frame_version"] in [8, 9] do
      previous = old["tool_batches"]
      current = new["tool_batches"]
      additions = Map.drop(current, Map.keys(previous))

      Enum.all?(previous, fn {key, before} ->
        after_batch = current[key]

        is_map(after_batch) and
          Map.drop(before, ~w(observations resolution)) ===
            Map.drop(after_batch, ~w(observations resolution)) and
          Map.take(after_batch["observations"], Map.keys(before["observations"])) ===
            before["observations"] and
          (before["observations"] === after_batch["observations"] or
             (operation in ~w(outcome resolve_call) and
                map_size(after_batch["observations"]) == map_size(before["observations"]) + 1)) and
          (before["resolution"] === after_batch["resolution"] or
             (operation == "tool_resolution" and is_nil(before["resolution"]) and
                not is_nil(after_batch["resolution"])))
      end) and
        (additions == %{} or
           (operation == "node_checkpoint" and map_size(additions) == 1 and
              Enum.all?(additions, fn {_, b} ->
                b["observations"] == %{} and is_nil(b["resolution"])
              end)))
    else
      new["frame_version"] not in [8, 9]
    end
  rescue
    _ -> false
  end
end
