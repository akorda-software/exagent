defmodule ExAgent.Continuation.OutputResolution do
  @moduledoc false
  alias ExAgent.{Message, Retention, Tool}
  alias ExAgent.Message.Part
  alias ExAgent.Continuation.{Frame, Outcome, Record}

  @fields ~w(output_resolution_version run_id request_id descriptor call_id decision parts parts_hash result result_omitted)

  # Descriptive tools for consuming an already validated result, never callable
  # tools or modules reconstructed from JSON. Require an exact roundtrip so no
  # descriptor field can be silently discarded before fingerprint validation.
  def output_config(%{
        "descriptor" =>
          %{
            "mode" => "tool",
            "allow_text" => false,
            "object" => nil,
            "tools" => [_ | _] = definitions
          } = descriptor
      }) do
    tools =
      Enum.map(definitions, fn d ->
        %Tool{
          name: d["name"],
          description: d["description"],
          parameters_json_schema: d["parameters"],
          kind: :output,
          takes_ctx: false,
          call: nil
        }
      end)

    params = %ExAgent.ModelRequestParameters{
      output_mode: :tool,
      output_tools: tools,
      allow_text_output: false,
      output_object: nil
    }

    if Frame.output_descriptor(params) == {:ok, descriptor},
      do: {:ok, {:tool, tools, false, nil}},
      else: {:error, :invalid_output_descriptor}
  end

  def output_config(_), do: {:error, :invalid_output_descriptor}

  def preflight(%{params: %{output_tools: []}}), do: :ok

  def preflight(run) do
    with {:ok, descriptor} <- Frame.output_descriptor(run.params) do
      if byte_size(Jason.encode!(descriptor)) <= 65_536,
        do: :ok,
        else: {:error, :output_descriptor_too_large}
    end
  end

  def new(run, decision, parts, output, limit) do
    with {:ok, descriptor} <- Frame.output_descriptor(run.params),
         bytes = Message.to_json([%Message.Request{parts: parts}]),
         {:ok, hash} <- Outcome.hash(bytes) do
      {result, omitted} =
        case Tool.JSON.encoded_result(output) do
          {:ok, _} ->
            value = output |> Jason.encode!() |> Jason.decode!()

            if Retention.check(value, limit, :checkpoint) == :ok,
              do: {value, nil},
              else: {nil, Retention.marker(:checkpoint, Retention.bytes(output), limit)}

          _ ->
            {nil, Retention.marker(:checkpoint, Retention.bytes(output), limit)}
        end

      {:ok,
       %{
         "output_resolution_version" => 1,
         "run_id" => run.run_id,
         "request_id" => run.model_request_id,
         "descriptor" => descriptor,
         "call_id" => hd(parts).tool_call_id,
         "decision" => decision,
         "parts" => bytes,
         "parts_hash" => hash,
         "result" => result,
         "result_omitted" => omitted
       }}
    end
  end

  def addition?(previous, current) do
    old = Map.get(previous, "output_resolutions", %{})

    case Map.to_list(Map.drop(current["output_resolutions"], Map.keys(old))) do
      [{request, %{"run_id" => run_id}}] when is_binary(request) and is_binary(run_id) ->
        child = previous["children"][run_id]

        is_map(child) and child["status"] == "running" and
          child["frame"]["cursor"] == "response" and
          child["frame"]["model_request_id"] === request

      _ ->
        false
    end
  end

  def evidence?(record, child, messages, models) do
    root = record["execution"]["progress"]["runtime"]

    entries =
      root
      |> Map.get("output_resolutions", %{})
      |> Map.filter(fn {_, entry} -> entry["run_id"] === child["frame"]["run_id"] end)

    retry_count =
      for %Message.Request{parts: parts} <- messages, %Part.Retry{} <- parts, reduce: 0 do
        count -> count + 1
      end

    terminal = terminal_exhaustion10?(record, child)

    counters =
      (root["frame_version"] not in [10, 11] and map_size(entries) == 0) or
        (child["frame"]["output_retries_used"] == retry_count - if(terminal, do: 1, else: 0) and
           child["frame"]["output_retries_used"] <= child["frame"]["limits"]["output_retries"])

    context?(root, record, child, messages, models) and coverage?(record) and counters and
      Enum.all?(entries, fn {request, entry} ->
        model = Enum.find(models, &(&1["intent"]["call_id"] == request))
        is_map(model) and valid?(entry, request, child, messages, model, root)
      end)
  rescue
    _ -> false
  end

  # Partitioning must not turn unknown leaves/requests into ignored evidence.
  # Host request IDs are global even though provider call IDs are request-local.
  def coverage?(record) do
    root = record["execution"]["progress"]["runtime"]

    models =
      record["execution"]["effects"]
      |> Map.values()
      |> Enum.filter(&(&1["intent"]["kind"] == "model"))

    requests = Enum.map(models, & &1["intent"]["call_id"])

    length(requests) == length(Enum.uniq(requests)) and
      Enum.all?(Map.get(root, "output_resolutions", %{}), fn {request, entry} ->
        is_map(entry) and entry["request_id"] === request and
          Map.has_key?(root["children"], entry["run_id"]) and
          Enum.any?(models, fn model ->
            model["intent"]["call_id"] === request and
              model["intent"]["payload"]["run_id"] === entry["run_id"] and
              model["state"] == "confirmed" and model["outcome"]["status"] == "succeeded"
          end)
      end)
  rescue
    _ -> false
  end

  def matches?(record, run, request, id, bytes) do
    entry = get_in(record, ["execution", "progress", "runtime", "output_resolutions", request])

    if is_map(entry) and entry["run_id"] == run do
      {:ok, [%Message.Request{parts: parts}]} = Message.from_json(entry["parts"])

      Enum.any?(
        parts,
        &(&1.tool_call_id == id and Outcome.hash(Outcome.encode(&1)) == Outcome.hash(bytes))
      )
    else
      false
    end
  end

  # Existing portable error grammar; the class comes from the complete output
  # certificate, never from a caller's error string/status. No callback decoding.
  def exhaustion_error10 do
    %{
      "code" => "runtime_error",
      "message" => "Output retries exhausted.",
      "details" => %{"reason" => "output_retries_exhausted"},
      "omitted" => nil
    }
  end

  def terminal_exhaustion10?(record, child) do
    root = record["execution"]["progress"]["runtime"]
    frame = child["frame"]
    entry = root["output_resolutions"][frame["model_request_id"]]
    {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])

    root["frame_version"] in [10, 11] and root["children"][frame["run_id"]] === child and
      child["status"] == "failed" and child["error"] === exhaustion_error10() and
      frame["cursor"] == "response" and
      frame["output_retries_used"] === frame["limits"]["output_retries"] and
      entry["decision"] == "retry" and entry["run_id"] === frame["run_id"] and
      entry["request_id"] === frame["model_request_id"] and
      match?(%Message.Request{}, List.last(messages)) and
      Message.to_json([List.last(messages)]) === entry["parts"]
  rescue
    _ -> false
  end

  # Version10 helpers consume the original tree and journal. A caller-provided
  # leaf, history or model projection cannot supply a second source of truth.
  # This validates an attestation position, not runtime admission/quiescence.
  defp context?(%{"frame_version" => durable_version} = root, record, child, messages, models)
       when durable_version in [10, 11] do
    run = child["frame"]["run_id"]

    own =
      record["execution"]["effects"]
      |> Map.values()
      |> Enum.filter(
        &(&1["intent"]["kind"] == "model" and &1["intent"]["payload"]["run_id"] == run)
      )
      |> Enum.sort_by(& &1["intent"]["payload"]["step"])

    confirmed =
      Enum.filter(own, &(&1["state"] == "confirmed" and &1["outcome"]["status"] == "succeeded"))

    positions = for {%Message.Response{}, index} <- Enum.with_index(messages), do: index

    Frame.validate(root) == :ok and root["children"][run] === child and
      Enum.all?(record["execution"]["effects"], fn {_, effect} ->
        effect["intent"]["kind"] != "model" or
          Map.has_key?(root["children"], effect["intent"]["payload"]["run_id"])
      end) and
      Message.from_json(child["snapshot"]["message_history"]) == {:ok, messages} and
      models === confirmed and child["frame"]["run_step"] === length(own) and
      child["frame"]["scope"]["requests"] === length(own) and
      child["frame"]["model_request_id"] === get_in(List.last(own), ["intent", "call_id"]) and
      Enum.map(own, & &1["intent"]["payload"]["step"]) === Enum.to_list(1..length(own)//1) and
      positions === Enum.map(confirmed, & &1["intent"]["payload"]["history_index"]) and
      Enum.all?(confirmed, fn model ->
        index = model["intent"]["payload"]["history_index"]
        data = model["outcome"]["data"]

        Record.counter?(index) and Outcome.model_valid?(data) and
          Outcome.hash(Message.to_json([Enum.at(messages, index)])) ==
            {:ok, data["response_hash"]}
      end)
  end

  defp context?(_, _, _, _, _), do: true

  defp valid?(e, request, child, messages, model, root) do
    frame = child["frame"]
    index = model["intent"]["payload"]["history_index"]
    response = Enum.at(messages, index)
    descriptor = e["descriptor"]

    with true <- Record.exact?(e, @fields) and e["output_resolution_version"] == 1,
         true <- e["run_id"] === frame["run_id"] and e["request_id"] === request,
         true <- e["decision"] in ~w(succeeded retry),
         true <- Record.exact?(descriptor, ~w(mode allow_text object tools)),
         true <- is_list(descriptor["tools"]) and descriptor["tools"] != [],
         true <- byte_size(Jason.encode!(descriptor)) <= 65_536,
         true <-
           Record.digest(descriptor) ==
             {:ok, model["intent"]["payload"]["request_data"]["output_fingerprint"]},
         names = Enum.map(descriptor["tools"], & &1["name"]),
         true <- Enum.all?(names, &Record.text?/1) and length(names) == length(Enum.uniq(names)),
         calls = Message.Response.tool_calls(response),
         {[selected | extra], siblings} <- Enum.split_with(calls, &(&1.tool_name in names)),
         true <- selected.tool_call_id === e["call_id"],
         {:ok, [%Message.Request{parts: [first | rest]}]} <- Message.from_json(e["parts"]),
         true <- e["parts"] === Message.to_json([%Message.Request{parts: [first | rest]}]),
         true <- Outcome.hash(e["parts"]) == {:ok, e["parts_hash"]},
         true <-
           first.tool_call_id === selected.tool_call_id and first.tool_name === selected.tool_name,
         true <- selected_part?(first, e["decision"]),
         true <-
           Enum.map(rest, &Outcome.encode/1) ===
             Enum.map(extra ++ siblings, &(&1 |> stub() |> Outcome.encode())),
         true <- Retention.marker!(e["result_omitted"]) === e["result_omitted"],
         true <- is_nil(e["result_omitted"]) or is_nil(e["result"]),
         true <- e["decision"] != "retry" or (is_nil(e["result"]) and is_nil(e["result_omitted"])),
         true <- supported10?(e, child, root),
         true <- position?(e, child, messages, index, root) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp supported10?(e, child, %{"frame_version" => durable_version})
       when durable_version in [10, 11] do
    frame = child["frame"]

    match?({:ok, _}, output_config(e)) and
      (is_nil(e["result_omitted"]) or child["link"]["kind"] == "step") and
      (e["decision"] != "retry" or frame["model_request_id"] != e["request_id"] or
         frame["cursor"] != "response" or
         frame["output_retries_used"] < frame["limits"]["output_retries"] or
         (child["status"] == "failed" and child["error"] === exhaustion_error10() and
            frame["output_retries_used"] === frame["limits"]["output_retries"]))
  end

  defp supported10?(_, _, _), do: true

  defp selected_part?(%Part.ToolReturn{} = part, "succeeded"),
    do:
      part.status == :succeeded and part.content == "ok" and is_nil(part.payload_omitted) and
        is_nil(part.usage)

  defp selected_part?(%Part.Retry{} = part, "retry"), do: is_binary(part.content)
  defp selected_part?(_, _), do: false

  defp stub(call),
    do: %Part.ToolReturn{
      tool_name: call.tool_name,
      tool_call_id: call.tool_call_id,
      content: "Tool not executed - a final result was already processed.",
      status: :not_executed
    }

  defp position?(e, child, messages, index, %{"frame_version" => durable_version} = root)
       when durable_version in [10, 11] do
    frame = child["frame"]
    current = frame["model_request_id"] == e["request_id"]

    cond do
      child["status"] in ~w(running suspended cancelled) and index == length(messages) - 1 ->
        current and frame["cursor"] == "response"

      child["status"] in ~w(running suspended cancelled) and current and e["decision"] == "retry" ->
        frame["cursor"] == "request" and length(messages) == index + 2 and
          frame["output_retries_used"] > 0 and
          match?(%Message.Request{}, Enum.at(messages, index + 1)) and
          Outcome.hash(Message.to_json([Enum.at(messages, index + 1)])) == {:ok, e["parts_hash"]}

      child["status"] == "failed" ->
        if current do
          frame["cursor"] == "response" and length(messages) == index + 2 and
            Message.to_json([Enum.at(messages, index + 1)]) === e["parts"] and
            ((e["decision"] == "retry" and child["error"] === exhaustion_error10() and
                frame["output_retries_used"] === frame["limits"]["output_retries"]) or
               (e["decision"] == "succeeded" and not is_nil(child["error"]) and
                  child["error"] ===
                    ExAgent.Continuation.ToolEvidence.child_retention_error10(
                      root,
                      child,
                      e["result"]
                    )))
        else
          position?(e, child, messages, index)
        end

      true ->
        position?(e, child, messages, index)
    end
  end

  defp position?(e, child, messages, index, _), do: position?(e, child, messages, index)

  defp position?(e, child, messages, index) do
    frame = child["frame"]

    if index == length(messages) - 1 do
      # Explicit bounded intermediate: validation is committed before the loop
      # appends returns. It is not an executed function or a terminal child.
      child["status"] == "running" and frame["cursor"] == "response" and
        frame["model_request_id"] == e["request_id"]
    else
      with %Message.Request{parts: parts} <- Enum.at(messages, index + 1),
           true <-
             Outcome.hash(Message.to_json([%Message.Request{parts: parts}])) ==
               {:ok, e["parts_hash"]} do
        case e["decision"] do
          "succeeded" ->
            child["status"] == "completed" and frame["cursor"] == "finish" and
              frame["model_request_id"] == e["request_id"] and length(messages) == index + 2 and
              result_matches?(child, e)

          "retry" ->
            frame["model_request_id"] != e["request_id"]
        end
      else
        _ -> false
      end
    end
  end

  defp result_matches?(child, e) do
    (child["result"] === e["result"] and child["result_omitted"] === e["result_omitted"]) or
      (is_nil(child["result"]) and is_nil(e["result_omitted"]) and
         is_map(child["result_omitted"]) and
         child["result_omitted"] ===
           Retention.marker(
             :checkpoint,
             Retention.bytes(e["result"]),
             child["result_omitted"]["limit"]
           ))
  end
end
