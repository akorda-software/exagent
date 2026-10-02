defmodule ExAgent.Continuation.ModelRecovery do
  @moduledoc false
  alias ExAgent.{Message, Retention}
  alias ExAgent.Continuation.{Frame, Outcome, ScopeLedger}
  alias ExAgent.Message.Usage

  def payload(record, effect_id, evidence, opts) do
    effect = record["execution"]["effects"][effect_id]
    runtime = record["execution"]["progress"]["runtime"]

    with %{"intent" => %{"kind" => "model", "call_id" => request, "payload" => intent}} <- effect,
         true <- intent["phase"] == "model_dispatch",
         :ok <- Frame.validate(runtime),
         %{} = frame <- Frame.node(runtime, intent["run_id"]),
         true <- frame["model_request_id"] == request and frame["run_step"] === intent["step"],
         true <-
           is_map(evidence) and
             Enum.sort(Map.keys(evidence)) in [
               [:model_data, :response],
               [:accounting, :model_data, :response]
             ],
         %Message.Response{} = response <- evidence[:response],
         true <- Retention.executable?([response]),
         {:ok, [%Message.Response{} = response]} <- Message.from_json(Message.to_json([response])),
         {:ok, model_data} <- ExAgent.Tool.JSON.normalize(evidence[:model_data]),
         {:ok, scope} <-
           ScopeLedger.reconcile_request(
             runtime["scope"],
             intent["run_id"],
             request,
             response.usage,
             evidence[:accounting]
           ),
         saved = node_snapshot(record, intent["run_id"]),
         {:ok, messages} <- Message.from_json(saved["message_history"]),
         true <- length(messages) in [intent["history_index"], intent["history_index"] + 1],
         prefix = Enum.take(messages, intent["history_index"]),
         true <- length(prefix) == intent["history_index"] do
      frame = frame |> Map.put("cursor", "response") |> Map.put("model_data", model_data)
      runtime = Frame.put_node(runtime, intent["run_id"], frame) |> Frame.with_scope(scope)
      saved = Map.put(saved, "message_history", Message.to_json(prefix ++ [response]))
      {snapshot, runtime} = put_snapshot(record, runtime, intent["run_id"], saved)
      {:ok, snapshot, runtime} = refresh_usage(snapshot, runtime, record["execution"]["progress"])
      progress = Map.put(record["execution"]["progress"], "runtime", runtime)
      outcome = Outcome.model(response, model_data)

      candidate =
        record
        |> Map.put("snapshot", snapshot)
        |> put_in(["execution", "progress"], progress)
        |> put_in(["execution", "effects", effect_id, "state"], "confirmed")
        |> put_in(["execution", "effects", effect_id, "outcome"], outcome)
        |> put_in(["execution", "state"], "ready")

      target =
        if intent["run_id"] == runtime["run_id"],
          do: candidate,
          else: Frame.child_record(candidate, intent["run_id"])

      with :ok <- ExAgent.validate_model_reconciliation(opts[:agent], target, opts[:continuation]) do
        {:ok,
         %{
           "effect_id" => effect_id,
           "outcome" => outcome,
           "snapshot" => snapshot,
           "progress" => progress
         }}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_model_reconciliation}
    end
  rescue
    _ -> {:error, :invalid_model_reconciliation}
  end

  defp node_snapshot(record, id) do
    runtime = record["execution"]["progress"]["runtime"]
    if id == runtime["run_id"], do: record["snapshot"], else: runtime["children"][id]["snapshot"]
  end

  defp put_snapshot(record, runtime, id, snapshot) do
    if id == runtime["run_id"],
      do: {snapshot, runtime},
      else: {record["snapshot"], put_in(runtime, ["children", id, "snapshot"], snapshot)}
  end

  defp refresh_usage(snapshot, runtime, progress) do
    with {:ok, usage} <- ScopeLedger.usage(runtime["scope"], runtime["run_id"]) do
      usage =
        if progress["conversation_usage"],
          do: Usage.add(Usage.from_map!(progress["conversation_usage"]), usage),
          else: usage

      :ok = Retention.usage_error(usage)
      snapshot = Map.put(snapshot, "usage", Usage.to_map(usage))

      runtime =
        if Map.has_key?(runtime, "children") do
          children =
            Map.new(runtime["children"], fn {id, child} ->
              {:ok, usage} = ScopeLedger.usage(runtime["scope"], id)
              {id, put_in(child, ["snapshot", "usage"], Usage.to_map(usage))}
            end)

          Map.put(runtime, "children", children)
        else
          runtime
        end

      {:ok, snapshot, runtime}
    end
  end
end
