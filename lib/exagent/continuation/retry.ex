defmodule ExAgent.Continuation.Retry do
  @moduledoc false
  alias ExAgent.Continuation.Record

  @fields ~w(retry_version original_effect_id new_effect_id node_id kind request_id new_request_id idempotency_key intent_hash actor_id at operation_id authorized_revision)
  @binding ~w(version record_id revision run_id node_id effect_id intent_hash)

  def plans(execution), do: Map.get(execution["progress"], "effect_retries", %{})
  def key?(key), do: Record.text?(key) and Regex.match?(~r/\A[\x21-\x7e]+\z/, key)

  def literal_uncertain?(effect),
    do:
      is_map(effect) and
        (effect["state"] == "running" or effect["outcome"]["status"] == "unknown")

  def retired?(execution, id), do: Map.has_key?(plans(execution), id)

  def active_uncertain?(execution, id, effect),
    do: literal_uncertain?(effect) and not retired?(execution, id)

  def active_id(execution, id) do
    case plans(execution)[id] do
      nil -> id
      plan -> active_id(execution, plan["new_effect_id"])
    end
  end

  def canonical_id(execution, id) do
    case Enum.find(plans(execution), fn {_, plan} -> plan["new_effect_id"] == id end) do
      nil -> id
      {original, _} -> canonical_id(execution, original)
    end
  end

  def incoming(execution, id) do
    Enum.find_value(plans(execution), fn {_, plan} -> if plan["new_effect_id"] == id, do: plan end)
  end

  def binding(record, id) do
    with {:ok, node, _} <- location(record["execution"], id),
         {:ok, hash} <- Record.digest(record["execution"]["effects"][id]["intent"]) do
      {:ok,
       %{
         version: 1,
         record_id: record["record_id"],
         revision: record["revision"],
         run_id: record["execution"]["run_id"],
         node_id: node,
         effect_id: id,
         intent_hash: hash
       }}
    end
  end

  def bindings(record) do
    for {id, effect} <- record["execution"]["effects"],
        active_uncertain?(record["execution"], id, effect),
        {:ok, binding} <- [binding(record, id)],
        do: binding
  end

  def command_payload(record, binding, key, operation_id, accepted?) do
    with {:ok, binding} <- ExAgent.Tool.JSON.normalize(binding),
         true <- Record.exact?(binding, @binding) and binding["version"] == 1,
         true <- accepted? === true and key?(key),
         true <-
           binding["record_id"] == record["record_id"] and
             binding["run_id"] == record["execution"]["run_id"],
         {:ok, node, request} <- location(record["execution"], binding["effect_id"]),
         true <- node == binding["node_id"],
         effect = record["execution"]["effects"][binding["effect_id"]],
         true <- Record.digest(effect["intent"]) == {:ok, binding["intent_hash"]},
         true <-
           is_nil(effect["intent"]["payload"]["idempotency_key"]) or
             effect["intent"]["payload"]["idempotency_key"] === key,
         {:ok, digest} <- Record.digest([record["record_id"], binding["effect_id"], operation_id]),
         kind = effect["intent"]["kind"],
         new_request = if(kind == "model", do: "model-retry-" <> digest),
         {:ok, model_hash} <- Record.digest([node, new_request, "model", new_request]) do
      {:ok,
       %{
         "binding" => binding,
         "accept_duplicate_risk" => true,
         "idempotency_key" => key,
         "request_id" => request,
         "new_request_id" => new_request,
         "new_effect_id" =>
           if(kind == "model", do: "model-" <> model_hash, else: "tool-retry-" <> digest)
       }}
    else
      _ -> {:error, :invalid_effect_retry}
    end
  end

  def authorize(record, payload, actor, now, operation_id) do
    binding = payload["binding"]
    effect = record["execution"]["effects"][binding["effect_id"]]

    with true <-
           Record.exact?(
             payload,
             ~w(binding accept_duplicate_risk idempotency_key request_id new_request_id new_effect_id)
           ),
         true <- Record.exact?(binding, @binding) and binding["version"] == 1,
         true <-
           binding["record_id"] == record["record_id"] and
             binding["revision"] == record["revision"] and
             binding["run_id"] == record["execution"]["run_id"],
         true <-
           record["execution"]["state"] == "uncertain" and
             active_uncertain?(record["execution"], binding["effect_id"], effect),
         true <- payload["accept_duplicate_risk"] === true and key?(payload["idempotency_key"]),
         {:ok, node, request} <- location(record["execution"], binding["effect_id"]),
         true <- node == binding["node_id"] and request == payload["request_id"],
         true <- Record.digest(effect["intent"]) == {:ok, binding["intent_hash"]},
         true <-
           effect["intent"]["kind"] != "model" or
             request_available?(record["execution"], effect),
         true <- not Map.has_key?(record["execution"]["effects"], payload["new_effect_id"]) do
      plan = %{
        "retry_version" => 1,
        "original_effect_id" => binding["effect_id"],
        "new_effect_id" => payload["new_effect_id"],
        "node_id" => node,
        "kind" => effect["intent"]["kind"],
        "request_id" => request,
        "new_request_id" => payload["new_request_id"],
        "idempotency_key" => payload["idempotency_key"],
        "intent_hash" => binding["intent_hash"],
        "actor_id" => actor,
        "at" => now,
        "operation_id" => operation_id,
        "authorized_revision" => record["revision"]
      }

      execution =
        put_in(
          record["execution"],
          ["progress", "effect_retries"],
          Map.put(plans(record["execution"]), binding["effect_id"], plan)
        )

      if valid?(execution), do: {:ok, execution}, else: {:error, :invalid_effect_retry}
    else
      _ -> {:error, :invalid_effect_retry}
    end
  rescue
    _ -> {:error, :invalid_effect_retry}
  end

  def valid?(execution) do
    links = plans(execution)

    is_map(links) and map_size(links) <= 256 and
      length(Enum.uniq(Enum.map(links, fn {_, p} -> p["new_effect_id"] end))) == map_size(links) and
      Enum.all?(links, fn {id, plan} ->
        effect = execution["effects"][id]

        Record.exact?(plan, @fields) and plan["retry_version"] == 1 and
          plan["original_effect_id"] == id and
          Record.text?(plan["new_effect_id"]) and Record.text?(plan["actor_id"]) and
          Record.text?(plan["operation_id"]) and Record.positive?(plan["authorized_revision"]) and
          Record.timestamp?(plan["at"]) and
          key?(plan["idempotency_key"]) and
          location(execution, id) == {:ok, plan["node_id"], plan["request_id"]} and
          effect["intent"]["kind"] == plan["kind"] and
          Record.digest(effect["intent"]) == {:ok, plan["intent_hash"]} and
          (is_nil(effect["intent"]["payload"]["idempotency_key"]) or
             effect["intent"]["payload"]["idempotency_key"] === plan["idempotency_key"]) and
          ((plan["kind"] == "model" and Record.text?(plan["new_request_id"])) or
             (plan["kind"] == "tool" and is_nil(plan["new_request_id"]))) and
          new_id_valid?(plan) and
          path_valid?(links, id, MapSet.new()) and
          new_intent_valid?(execution["effects"][plan["new_effect_id"]], effect, plan)
      end)
  rescue
    _ -> false
  end

  defp path_valid?(links, id, seen) do
    not MapSet.member?(seen, id) and
      (not Map.has_key?(links, id) or
         path_valid?(links, links[id]["new_effect_id"], MapSet.put(seen, id)))
  end

  defp new_intent_valid?(nil, _, _), do: true

  defp new_intent_valid?(%{"intent" => intent}, original, plan) do
    payload = intent["payload"]

    intent["kind"] == plan["kind"] and payload["run_id"] == plan["node_id"] and
      payload["retry_of"] == plan["original_effect_id"] and
      payload["idempotency_key"] === plan["idempotency_key"] and
      if plan["kind"] == "tool" do
        intent["call_id"] == original["intent"]["call_id"] and
          payload["phase"] == "dispatch" and payload["model_request_id"] == plan["request_id"] and
          Map.take(payload, ~w(tool_name args schema_hash call_hash)) ===
            Map.take(original["intent"]["payload"], ~w(tool_name args schema_hash call_hash))
      else
        intent["call_id"] == plan["new_request_id"] and
          payload["phase"] == "model_dispatch" and
          payload["step"] == original["intent"]["payload"]["step"] + 1 and
          payload["history_index"] == original["intent"]["payload"]["history_index"] and
          payload["request_data"] === original["intent"]["payload"]["request_data"]
      end
  end

  defp new_id_valid?(%{"kind" => "model"} = plan) do
    {:ok, hash} =
      Record.digest([plan["node_id"], plan["new_request_id"], "model", plan["new_request_id"]])

    plan["new_effect_id"] == "model-" <> hash and plan["new_request_id"] != plan["request_id"]
  end

  defp new_id_valid?(%{"kind" => "tool"} = plan),
    do: Regex.match?(~r/\Atool-retry-[0-9a-f]{64}\z/, plan["new_effect_id"])

  def location(execution, id) do
    effect = execution["effects"][id]

    case effect do
      %{
        "intent" => %{
          "kind" => "model",
          "call_id" => request,
          "payload" => %{"phase" => "model_dispatch", "run_id" => node}
        }
      } ->
        {:ok, node, request}

      %{
        "intent" => %{
          "kind" => "tool",
          "payload" => %{"phase" => "dispatch", "run_id" => node, "model_request_id" => request}
        }
      } ->
        {:ok, node, request}

      %{"intent" => %{"kind" => "tool", "call_id" => call, "payload" => %{"phase" => "dispatch"}}} ->
        Enum.find_value(execution["effects"], {:error, :invalid_retry_binding}, fn
          {_,
           %{
             "intent" => %{
               "kind" => "model",
               "call_id" => request,
               "payload" => %{"run_id" => node}
             }
           }} ->
            {:ok, hash} = Record.digest([node, request, "tool", call])
            if id == "tool-" <> hash, do: {:ok, node, request}

          _ ->
            nil
        end)

      _ ->
        {:error, :invalid_retry_binding}
    end
  end

  def request_available?(_execution, effect) do
    is_map(effect["intent"]["payload"]["request_data"])
  end

  def model_plan(execution, frame) do
    if frame["cursor"] == "request" do
      request = frame["model_request_id"]
      {:ok, hash} = Record.digest([frame["run_id"], request, "model", request])

      case plans(execution)["model-" <> hash] do
        %{"kind" => "model"} = plan ->
          original = execution["effects"][plan["original_effect_id"]]

          if not Map.has_key?(execution["effects"], plan["new_effect_id"]) and
               request_available?(execution, original),
             do: %{
               "plan" => plan,
               "data" => original["intent"]["payload"]["request_data"]
             }

        _ ->
          nil
      end
    end
  end

  def pending_receipts(execution) do
    Enum.reduce(plans(execution), 0, fn {_, plan}, total ->
      if Map.has_key?(execution["effects"], plan["new_effect_id"]),
        do: total,
        else: total + if(plan["kind"] == "tool", do: 3, else: 2)
    end)
  end

  def pending_slots(execution),
    do:
      Enum.count(plans(execution), fn {_, plan} ->
        not Map.has_key?(execution["effects"], plan["new_effect_id"])
      end)

  def summary(execution) do
    entries =
      for {id, plan} <- plans(execution),
          literal_uncertain?(execution["effects"][id]),
          do: {id, plan, execution["effects"][id]}

    if entries == [] do
      nil
    else
      {:ok, hash} =
        Record.digest(
          Enum.map(Enum.sort(entries), fn {id, plan, effect} ->
            %{"effect_id" => id, "retry" => plan, "original" => effect}
          end)
        )

      %{
        version: 1,
        count: length(entries),
        evidence_hash: hash,
        retention_acknowledged:
          get_in(execution, ["progress", "historical_retention_ack", "evidence_hash"]) === hash
      }
    end
  end

  def retention_blocked?(execution) do
    case summary(execution) do
      nil -> false
      %{retention_acknowledged: acknowledged} -> not acknowledged
    end
  end

  def authorizations_valid?(record) do
    [namespace, kind, id] = record["key"]
    kind = Enum.find([:agent, :session], &(Atom.to_string(&1) == kind))

    Enum.all?(plans(record["execution"]), fn {original, plan} ->
      binding = %{
        "version" => 1,
        "record_id" => record["record_id"],
        "revision" => plan["authorized_revision"],
        "run_id" => record["execution"]["run_id"],
        "node_id" => plan["node_id"],
        "effect_id" => original,
        "intent_hash" => plan["intent_hash"]
      }

      payload = %{
        "binding" => binding,
        "accept_duplicate_risk" => true,
        "idempotency_key" => plan["idempotency_key"],
        "request_id" => plan["request_id"],
        "new_request_id" => plan["new_request_id"],
        "new_effect_id" => plan["new_effect_id"]
      }

      command = %{
        "record_id" => record["record_id"],
        "operation" => "retry_effect",
        "operation_id" => plan["operation_id"],
        "actor_id" => plan["actor_id"],
        "payload" => payload
      }

      receipt = record["receipts"][plan["operation_id"]]

      is_map(receipt) and receipt["operation"] == "retry_effect" and
        receipt["revision"] === plan["authorized_revision"] + 1 and
        receipt["actor_id"] === plan["actor_id"] and
        receipt["run_id"] === record["execution"]["run_id"] and
        ExAgent.Continuation.Transition.digest(
          {namespace, kind, id},
          plan["authorized_revision"],
          command
        ) == {:ok, receipt["digest"]}
    end)
  rescue
    _ -> false
  end
end
