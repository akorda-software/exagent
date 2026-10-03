defmodule ExAgent.Continuation.Transition do
  @moduledoc false
  alias ExAgent.Continuation.Record
  alias ExAgent.Continuation.{Approval, Budget, Outcome, Frame, Retry}
  alias ExAgent.Tool.JSON

  @operations ~w(create create_cancelled start claim checkpoint node_checkpoint step_input step_output output_resolution output_consume tool_resolution delegation_outcome begin_effect outcome resolve_call finalize_call recover reconcile reconcile_model retry_effect acknowledge_history finish expire cancel delete pause decide reset_snapshot fence_admission batch_begin call_prepare call_prepared call_wait call_wrap call_settle call_reject node_attach node_suspend node_complete frontier_open batch_consume flow_select_begin flow_select flow_merge_begin flow_merge flow_branch_done flow_host_failed)
  @command_fields ~w(record_id operation operation_id actor_id payload)

  # The adapter invokes this while holding its write boundary and supplies UTC ms.
  # A receipt precedes CAS checks: the result is evidence of a past commit, never
  # a new permission for external IO. The returned record is the current record.
  def apply(current, key, expected, command, now) do
    with {:ok, _} <- Record.key(key),
         {:ok, command} <- command(command),
         true <- Record.timestamp?(now),
         {:ok, digest} <- digest(key, expected, command),
         :ok <- current_valid(current, key),
         :ok <- lifetime(current, command) do
      case receipt(current, command, digest) do
        {:ok, receipt} -> {:ok, %{record: current, receipt: receipt, replayed: true}}
        {:error, _} = error -> error
        :new -> change(current, key, expected, command, digest, now)
      end
    else
      false -> {:error, :invalid_time}
      {:error, _} = error -> error
    end
  end

  def command(command) do
    with {:ok, command} <- JSON.normalize(command),
         true <- Record.exact?(command, @command_fields),
         true <- command["operation"] in @operations,
         true <-
           Record.text?(command["operation_id"]) and Record.text?(command["actor_id"]) and
             Record.text?(command["record_id"]),
         true <- is_map(command["payload"]),
         {:ok, bytes} <- Record.canonical(command),
         true <- byte_size(bytes) <= Record.max_bytes() do
      {:ok, command}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp expected_data(:absent), do: "absent"
  defp expected_data(value), do: value

  def digest(key, expected, command),
    do:
      Record.digest(%{
        "key" => Record.key_data(key),
        "expected" => expected_data(expected),
        "command" => command
      })

  defp lifetime(nil, _), do: :ok

  defp lifetime(current, command),
    do:
      if(current["record_id"] == command["record_id"], do: :ok, else: {:error, :record_mismatch})

  defp current_valid(nil, _), do: :ok
  defp current_valid(current, key), do: Record.validate(current, key)
  defp receipt(nil, _, _), do: :new

  defp receipt(current, command, digest) do
    case current["receipts"][command["operation_id"]] do
      nil -> :new
      %{"digest" => ^digest} = receipt -> {:ok, receipt}
      _ -> {:error, :operation_conflict}
    end
  end

  defp change(nil, key, :absent, %{"operation" => operation, "payload" => p} = c, digest, now)
       when operation in ~w(create create_cancelled) do
    with true <- Record.exact?(p, ~w(snapshot execution)),
         {:ok, execution} <-
           initial_execution(p["execution"], now, operation == "create_cancelled"),
         {:ok, _} <- Record.execution_snapshot(p["snapshot"], key, execution),
         true <- operation != "create_cancelled" or aborted_execution?(execution) do
      execution =
        if operation == "create_cancelled",
          do: %{execution | "state" => "cancelled"},
          else: execution

      record = %{
        "record_version" => execution["execution_version"],
        "record_id" => c["record_id"],
        "key" => Record.key_data(key),
        "revision" => 0,
        "snapshot" => p["snapshot"],
        "execution" => execution,
        "receipts" => %{},
        "created_at" => now,
        "updated_at" => now
      }

      commit(record, key, c, digest, now)
    else
      false -> {:error, :invalid_command}
      {:error, _} = error -> error
    end
  end

  defp change(nil, _, _, _, _, _), do: {:error, :not_found}

  defp change(current, key, expected, c, digest, now) do
    cond do
      current["revision"] !== expected ->
        {:error, :conflict}

      now < current["updated_at"] ->
        {:error, :clock_regressed}

      c["operation"] in ~w(create create_cancelled) ->
        {:error, :conflict}

      map_size(current["receipts"]) >= 1024 and c["operation"] != "delete" ->
        {:error, :receipt_limit}

      true ->
        with {:ok, changed} <- reduce_command(current, c, now),
             :ok <- budget_not_regressed(current, changed, c["operation"]),
             :ok <- approvals_not_regressed(current, changed, c["operation"]),
             :ok <- snapshot_not_regressed(current, changed) do
          if changed == :delete,
            do: {:ok, %{record: nil, receipt: nil, replayed: false}},
            else: commit(changed, key, c, digest, now)
        end
    end
  end

  defp reduce_command(
         %{"execution" => %{"progress" => %{"runtime" => %{"frame_version" => version}}}} = r,
         command,
         now
       )
       when version in [10, 11] do
    case command["operation"] do
      "claim" ->
        reduce(r, "claim", command["payload"], now)

      "recover" ->
        reduce(r, "recover", command["payload"], now)

      "decide" ->
        if command["payload"]["decision"] == "approve",
          do: decide(r, command["payload"], command["actor_id"], now),
          else: {:error, :unsupported_structural_operation}

      operation when operation in ~w(delete reset_snapshot) ->
        if r["execution"]["state"] in ~w(completed failed),
          do: reduce(r, operation, command["payload"], now),
          else: {:error, :unsupported_structural_operation}

      operation ->
        reduce10(r, operation, command["payload"], now)
    end
  end

  defp reduce_command(%{"record_version" => 2} = r, command, now) do
    operation = command["operation"]

    stepped? =
      r["execution"]["progress"]["runtime"]["cursor"] != "empty" and
        r["execution"]["progress"]["runtime"]["frame_version"] in [5, 6, 7, 8, 9]

    allowed =
      ~w(claim recover cancel expire delete step_input) ++
        if(stepped?,
          do:
            ~w(step_output output_resolution tool_resolution begin_effect outcome node_checkpoint resolve_call finalize_call) ++
              if(r["execution"]["progress"]["runtime"]["frame_version"] == 9,
                do: ~w(pause decide),
                else: []
              ),
          else: []
        )

    if operation in allowed do
      result =
        if operation == "decide",
          do: decide(r, command["payload"], command["actor_id"], now),
          else: reduce(r, operation, command["payload"], now)

      with {:ok, next} <- result,
           :ok <- structural_transition(r, next, operation),
           do: {:ok, next}
    else
      {:error, :unsupported_structural_operation}
    end
  end

  defp reduce_command(r, %{"operation" => "decide"} = command, now),
    do: decide(r, command["payload"], command["actor_id"], now)

  defp reduce_command(r, %{"operation" => "retry_effect"} = command, now),
    do: retry_effect(r, command["payload"], command["actor_id"], now, command["operation_id"])

  defp reduce_command(r, %{"operation" => "acknowledge_history"} = command, now),
    do: acknowledge_history(r, command["payload"], command["actor_id"], now)

  defp reduce_command(r, command, now),
    do: reduce(r, command["operation"], command["payload"], now)

  defp structural_transition(_, :delete, _), do: :ok

  defp structural_transition(old, new, operation) when operation in ~w(pause decide) do
    before = old["execution"]["progress"]
    after_progress = new["execution"]["progress"]
    added = Map.drop(after_progress["approvals"], Map.keys(Map.get(before, "approvals", %{})))

    if old["snapshot"] === new["snapshot"] and
         Map.drop(before, ~w(approvals active_budget)) ===
           Map.drop(after_progress, ~w(approvals active_budget)) and
         (operation == "decide" or
            match?({:ok, _}, Frame.approval_boundary(old, added))),
       do: :ok,
       else: {:error, :invalid_step_transition}
  end

  defp structural_transition(old, new, operation)
       when operation in ~w(claim recover cancel expire),
       do:
         if(old["execution"]["progress"]["runtime"] === new["execution"]["progress"]["runtime"],
           do: :ok,
           else: {:error, :invalid_step_transition}
         )

  defp structural_transition(old, new, operation),
    do:
      Frame.step_transition(
        old["execution"]["progress"]["runtime"],
        new["execution"]["progress"]["runtime"],
        operation
      )

  defp initial_execution(e, now, terminal? \\ false)

  defp initial_execution(e, now, terminal?) when is_map(e) do
    structural? = e["kind"] == "composition"

    fields =
      ~w(continuation_id run_id request_id definition policy model_ref deadline_at expires_at progress)

    fields = if structural?, do: (fields -- ~w(request_id model_ref)) ++ ["kind"], else: fields

    execution =
      Map.merge(e, %{
        "execution_version" => if(structural?, do: 2, else: 1),
        "state" => "ready",
        "owner_id" => nil,
        "attempt_id" => nil,
        "fence" => 0,
        "lease_until" => nil,
        "effects" => %{}
      })

    cond do
      not Record.exact?(e, fields) or not Record.execution?(execution) or
        (e["progress"]["runtime"]["frame_version"] in [10, 11] and
           (terminal? or e["progress"]["runtime"]["cursor"] != "empty" or
              e["progress"]["runtime"]["frontier"] != %{
                "epoch" => 0,
                "state" => "open",
                "reason" => nil,
                "fatal" => nil
              })) or
          Map.has_key?(execution["progress"], "approvals") ->
        {:error, :invalid_execution}

      not terminal? and expired?(execution, now) ->
        {:error, :expired}

      true ->
        {:ok, execution}
    end
  end

  defp initial_execution(_, _, _), do: {:error, :invalid_execution}

  defp aborted_execution?(execution) do
    case execution["progress"] do
      %{"runtime" => %{"abort_frame_version" => _} = frame} = progress ->
        Record.exact?(progress, ~w(runtime)) and
          ExAgent.Continuation.Frame.valid_abort?(frame) and
          frame["run_id"] === execution["run_id"]

      _ ->
        false
    end
  end

  defp commit(record, key, command, digest, now) do
    revision = record["revision"] + 1

    receipt = %{
      "digest" => digest,
      "revision" => revision,
      "operation" => command["operation"],
      "actor_id" => command["actor_id"],
      "attempt_id" =>
        if(command["operation"] == "claim", do: command["payload"]["attempt_id"], else: nil),
      "continuation_id" => record["execution"]["continuation_id"],
      "run_id" => record["execution"]["run_id"],
      "state" => record["execution"]["state"]
    }

    record = %{
      record
      | "revision" => revision,
        "updated_at" => now,
        "receipts" => Map.put(record["receipts"], command["operation_id"], receipt)
    }

    if map_size(record["receipts"]) + Record.receipt_reserve(record["execution"]) > 1024 do
      {:error, :receipt_limit}
    else
      with {:ok, _} <- Record.encode(record, key),
           do: {:ok, %{record: record, receipt: receipt, replayed: false}}
    end
  end

  defp reduce(r, "start", p, now) do
    with true <- Record.exact?(p, ~w(execution)),
         true <- r["execution"]["state"] in ~w(completed denied expired cancelled),
         :ok <- retained_history(r["execution"]),
         {:ok, execution} <- initial_execution(p["execution"], now),
         false <-
           Enum.any?(r["receipts"], fn {_, receipt} ->
             receipt["continuation_id"] == execution["continuation_id"] or
               receipt["run_id"] == execution["run_id"]
           end) do
      {:ok, put_execution(r, %{execution | "fence" => r["execution"]["fence"] + 1})}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_start}
    end
  end

  defp reduce(r, "claim", p, now) do
    e = r["execution"]

    extended? =
      Record.exact?(p, ~w(owner_id attempt_id lease_until deadline_at expires_at active_limit_ms))

    effective =
      if extended? do
        e
        |> Map.put("deadline_at", earlier(e["deadline_at"], p["deadline_at"]))
        |> Map.put("expires_at", earlier(e["expires_at"], p["expires_at"]))
      else
        e
      end

    cond do
      not (Record.exact?(p, ~w(owner_id attempt_id lease_until)) or extended?) or
        (extended? and
           (not Record.nullable_timestamp?(p["deadline_at"]) or
              not Record.nullable_timestamp?(p["expires_at"]) or
              not (is_nil(p["active_limit_ms"]) or Record.positive?(p["active_limit_ms"])))) or
        not Record.text?(p["owner_id"]) or not Record.text?(p["attempt_id"]) or
        not Record.timestamp?(p["lease_until"]) or p["lease_until"] <= now ->
        {:error, :invalid_command}

      e["state"] != "ready" ->
        {:error, :invalid_transition}

      expired?(effective, now) ->
        {:error, :expired}

      reused_attempt?(r, p) ->
        {:error, :attempt_reused}

      true ->
        with {:ok, progress} <- Budget.claim(Budget.tighten(e["progress"], p["active_limit_ms"])) do
          {:ok,
           put_execution(
             r,
             Map.merge(
               effective,
               Map.merge(Map.take(p, ~w(owner_id attempt_id lease_until)), %{
                 "state" => "claimed",
                 "fence" => e["fence"] + 1,
                 "progress" => progress
               })
             )
           )}
        end
    end
  end

  defp reduce(r, "checkpoint", p, now) do
    with :ok <- worker(r, p, ~w(snapshot progress), now),
         :ok <- no_running(r),
         true <- is_map(p["progress"]) do
      {:ok,
       r |> Map.put("snapshot", p["snapshot"]) |> put_in(["execution", "progress"], p["progress"])}
    else
      false -> {:error, :invalid_command}
      {:error, _} = error -> error
    end
  end

  defp reduce(r, "pause", p, now) do
    with :ok <- worker(r, p, ~w(snapshot progress), now),
         :ok <- no_running(r),
         false <- expired?(r["execution"], now),
         true <- is_map(p["progress"]) and Approval.collection?(p["progress"]["approvals"]),
         true <- valid_pause_approvals?(r, p["progress"]["approvals"]) do
      r =
        r
        |> Map.put("snapshot", p["snapshot"])
        |> put_in(["execution", "progress"], Budget.confirm_refund(p["progress"], now))

      {:ok, put_execution(r, release(r["execution"], "pending"))}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_pause}
    end
  end

  defp reduce(r, "node_checkpoint", p, now) do
    old = r["execution"]["progress"]

    with :ok <- worker(r, p, ~w(node_id snapshot progress), now),
         true <- p["snapshot"] === r["snapshot"],
         true <- Map.delete(old, "runtime") === Map.delete(p["progress"], "runtime"),
         :ok <- Frame.node_transition(old["runtime"], p["progress"]["runtime"], p["node_id"]),
         false <-
           Enum.any?(r["execution"]["effects"], fn {_, effect} ->
             effect["state"] == "running" and
               effect["intent"]["payload"]["run_id"] == p["node_id"]
           end),
         next = put_in(r, ["execution", "progress"], p["progress"]),
         :ok <- Frame.validate_child_binding(next, p["node_id"]) do
      {:ok, next}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_node_checkpoint}
    end
  end

  defp reduce(r, operation, p, now)
       when operation in ~w(step_input step_output output_resolution tool_resolution) do
    terminal? = operation == "step_output" and p["progress"]["runtime"]["cursor"] == "completed"

    changed_fields =
      if terminal?, do: ~w(runtime active_budget), else: ["runtime"]

    with true <- r["record_version"] == 2,
         :ok <- worker(r, p, ~w(node_id snapshot progress), now),
         false <- expired?(r["execution"], now),
         true <- p["snapshot"] === r["snapshot"],
         true <-
           Map.drop(r["execution"]["progress"], changed_fields) ===
             Map.drop(p["progress"], changed_fields),
         true <- Frame.active_step_id(p["progress"]["runtime"]) === p["node_id"],
         :ok <- no_running(r),
         :ok <-
           Frame.step_transition(
             r["execution"]["progress"]["runtime"],
             p["progress"]["runtime"],
             operation
           ) do
      progress =
        if terminal?,
          do: Budget.confirm_refund(p["progress"], now),
          else: p["progress"]

      next = put_in(r, ["execution", "progress"], progress)

      next =
        if terminal?,
          do: put_execution(next, release(next["execution"], "completed")),
          else: next

      {:ok, next}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_step_transition}
    end
  end

  defp reduce(r, "delegation_outcome", p, now) do
    progress = r["execution"]["progress"]
    old = progress["runtime"]
    child = get_in(old, ["children", p["node_id"]])

    with :ok <- worker(r, p, ~w(node_id snapshot progress), now),
         %{"status" => "completed", "call" => call} <- child,
         true <- p["snapshot"] === r["snapshot"],
         true <- Map.delete(progress, "runtime") === Map.delete(p["progress"], "runtime"),
         current = p["progress"]["runtime"],
         outcome = current["children"][p["node_id"]]["outcome"],
         true <- Record.outcome?(outcome) and Outcome.valid?(outcome["data"]),
         parent = Frame.node(current, child["parent_run_id"]),
         %ExAgent.Message.Part.ToolReturn{} = part <- Frame.outcome(parent, call["call_id"]),
         true <- part.status == :succeeded and part.tool_name == call["tool_name"],
         true <- Outcome.hash(part) == {:ok, outcome["data"]["result_hash"]},
         true <- delegation_phase?(child, outcome, part),
         expected =
           old
           |> Frame.put_node(
             child["parent_run_id"],
             Frame.put_outcome(Frame.node(old, child["parent_run_id"]), part)
           )
           |> put_in(["children", p["node_id"], "outcome"], outcome)
           |> put_in(["children", p["node_id"], "parent_result"], Outcome.encode(part)),
         true <- current === expected do
      {:ok, put_in(r, ["execution", "progress"], p["progress"])}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_delegation_outcome}
    end
  end

  defp reduce(r, "begin_effect", p, now) do
    extended? = Map.has_key?(p, "progress") or Map.has_key?(p, "snapshot")
    fields = if extended?, do: ~w(effect_id intent snapshot progress), else: ~w(effect_id intent)

    with :ok <- worker(r, p, fields, now),
         false <- expired?(r["execution"], now),
         true <- Record.text?(p["effect_id"]) and Record.intent?(p["intent"]),
         false <- Map.has_key?(r["execution"]["effects"], p["effect_id"]) do
      effect = %{"intent" => p["intent"], "state" => "running", "outcome" => nil}
      next = put_in(r, ["execution", "effects", p["effect_id"]], effect)

      if extended? do
        with true <-
               (p["intent"]["kind"] == "model" and
                  p["intent"]["payload"]["phase"] == "model_dispatch" and
                  is_map(p["intent"]["payload"]["request_data"])) or
                 (p["intent"]["kind"] == "tool" and
                    is_map(Retry.incoming(r["execution"], p["effect_id"]))),
             :ok <- Frame.validate(p["progress"]["runtime"]),
             next =
               next
               |> Map.put("snapshot", p["snapshot"])
               |> put_in(["execution", "progress"], p["progress"]),
             :ok <- Frame.graph_evidence(next) do
          {:ok, next}
        else
          {:error, _} = error -> error
          _ -> {:error, :invalid_model_intent}
        end
      else
        {:ok, next}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_effect}
    end
  end

  defp reduce(r, "outcome", p, now) do
    with :ok <- worker(r, p, ~w(effect_id outcome snapshot progress), now),
         :ok <- effect_running(r, p["effect_id"]),
         true <- Record.outcome?(p["outcome"]) and is_map(p["progress"]) do
      {:ok, save_outcome(r, p)}
    else
      false -> {:error, :invalid_command}
      {:error, _} = error -> error
    end
  end

  defp reduce(r, "resolve_call", p, now) do
    with :ok <- worker(r, p, ~w(effect_id intent outcome snapshot progress), now),
         true <- Record.text?(p["effect_id"]) and Record.intent?(p["intent"]),
         true <-
           p["intent"]["kind"] == "tool" and p["intent"]["payload"]["phase"] == "pre_dispatch",
         false <- Map.has_key?(r["execution"]["effects"], p["effect_id"]),
         true <- Record.outcome?(p["outcome"]) and Outcome.valid?(p["outcome"]["data"]),
         true <- p["outcome"]["status"] in ~w(validation_error denied not_executed unknown),
         true <-
           p["outcome"]["data"]["phase"] == "final" and
             p["outcome"]["data"]["raw_hash"] === p["outcome"]["data"]["result_hash"] and
             is_map(p["progress"]) do
      effect = %{"intent" => p["intent"], "state" => "confirmed", "outcome" => p["outcome"]}
      r = put_in(r, ["execution", "effects", p["effect_id"]], effect)
      {:ok, save_outcome(r, p)}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_resolution}
    end
  end

  defp reduce(r, "finalize_call", p, now) do
    previous = get_in(r, ["execution", "effects", p["effect_id"], "outcome"])

    with :ok <- worker(r, p, ~w(effect_id outcome snapshot progress), now),
         %{"state" => "confirmed", "intent" => %{"kind" => "tool"}} <-
           r["execution"]["effects"][p["effect_id"]],
         true <-
           Record.outcome?(p["outcome"]) and Outcome.valid?(previous["data"]) and
             Outcome.valid?(p["outcome"]["data"]),
         true <- previous["data"]["phase"] == "raw" and p["outcome"]["data"]["phase"] == "final",
         true <-
           p["outcome"]["status"] === previous["status"] and
             p["outcome"]["data"]["raw_hash"] === previous["data"]["raw_hash"],
         true <- is_map(p["progress"]) do
      {:ok, save_outcome(r, p)}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_finalization}
    end
  end

  defp reduce(r, "recover", p, now) do
    e = r["execution"]

    cond do
      p != %{} ->
        {:error, :invalid_command}

      e["state"] != "claimed" or e["lease_until"] > now ->
        {:error, :invalid_transition}

      true ->
        state =
          if unresolved?(e),
            do: "uncertain",
            else: if(expired?(e, now), do: "expired", else: "ready")

        e = put_in(e["progress"], Budget.abandon(e["progress"]))
        {:ok, put_execution(r, release(e, state))}
    end
  end

  defp reduce(r, "reconcile", p, _now) do
    cond do
      not Record.exact?(p, ~w(effect_id outcome snapshot progress)) ->
        {:error, :invalid_command}

      r["execution"]["state"] != "uncertain" ->
        {:error, :invalid_transition}

      not Record.outcome?(p["outcome"]) or p["outcome"]["status"] == "unknown" or
          not is_map(p["progress"]) ->
        {:error, :invalid_command}

      true ->
        with :ok <- effect_unresolved(r, p["effect_id"]) do
          r = save_outcome(r, p)
          state = if unresolved?(r["execution"]), do: "uncertain", else: "ready"
          {:ok, put_in(r, ["execution", "state"], state)}
        end
    end
  end

  defp reduce(r, "reconcile_model", p, _now) do
    with true <- Record.exact?(p, ~w(effect_id outcome snapshot progress)),
         true <- r["execution"]["state"] in ~w(uncertain ready),
         %{"intent" => %{"kind" => "model", "payload" => intent}} = effect <-
           r["execution"]["effects"][p["effect_id"]],
         true <-
           effect["state"] == "running" or effect["outcome"]["status"] == "unknown" or
             effect["outcome"]["data"]["state_available"] === false,
         true <-
           Record.outcome?(p["outcome"]) and p["outcome"]["status"] == "succeeded" and
             Outcome.model_valid?(p["outcome"]["data"]) and
             p["outcome"]["data"]["state_available"],
         :ok <- Frame.validate(p["progress"]["runtime"]),
         frame = Frame.node(p["progress"]["runtime"], intent["run_id"]),
         true <-
           frame["cursor"] == "response" and
             frame["model_request_id"] == effect["intent"]["call_id"],
         true <-
           Record.digest(frame["model_data"]) == {:ok, p["outcome"]["data"]["model_state_hash"]} do
      next = save_outcome(r, p)

      {:ok,
       put_in(
         next,
         ["execution", "state"],
         if(unresolved?(next["execution"]), do: "uncertain", else: "ready")
       )}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_model_reconciliation}
    end
  end

  defp reduce(r, "finish", p, now) do
    with :ok <- worker(r, p, ~w(snapshot progress), now),
         :ok <- no_running(r),
         true <- is_map(p["progress"]) do
      r =
        r
        |> Map.put("snapshot", p["snapshot"])
        |> put_in(["execution", "progress"], Budget.confirm_refund(p["progress"], now))

      {:ok, put_execution(r, release(r["execution"], "completed"))}
    else
      false -> {:error, :invalid_command}
      {:error, _} = error -> error
    end
  end

  defp reduce(r, "expire", p, now) do
    cond do
      p != %{} ->
        {:error, :invalid_command}

      r["execution"]["state"] not in ~w(ready pending) or not expired?(r["execution"], now) ->
        {:error, :invalid_transition}

      true ->
        {:ok, put_execution(r, release(r["execution"], "expired"))}
    end
  end

  defp reduce(r, "fence_admission", p, _now) do
    if Record.exact?(p, ~w(run_id)) and Record.text?(p["run_id"]) and
         r["execution"]["state"] in ~w(completed denied expired cancelled) and
         not unresolved?(r["execution"]) and p["run_id"] != r["execution"]["run_id"] do
      {:ok,
       put_in(r, ["execution", "progress", "admission_fence"], %{
         "version" => 1,
         "run_id" => p["run_id"]
       })}
    else
      {:error, :invalid_transition}
    end
  end

  defp reduce(r, "reset_snapshot", p, _now) do
    if Record.exact?(p, ~w(snapshot)) and
         r["execution"]["state"] in ~w(completed denied expired cancelled) and
         not unresolved?(r["execution"]) and is_map(p["snapshot"]) and
         p["snapshot"]["message_history"] == "[]" and
         p["snapshot"]["revision"] === r["snapshot"]["revision"] + 1 do
      {:ok, Map.put(r, "snapshot", p["snapshot"])}
    else
      {:error, :invalid_transition}
    end
  end

  defp reduce(r, "delete", p, _now) do
    if Record.exact?(p, ~w(before)) and Record.timestamp?(p["before"]) and
         r["updated_at"] < p["before"] and
         (r["execution"]["state"] in ~w(completed denied expired cancelled) or
            (r["execution"]["state"] == "failed" and
               r["execution"]["progress"]["runtime"]["frame_version"] in [10, 11])) and
         not unresolved?(r["execution"]) and not Retry.retention_blocked?(r["execution"]),
       do: {:ok, :delete},
       else: {:error, :active_or_retained}
  end

  defp reduce(r, "cancel", p, _now) do
    if p == %{} and r["execution"]["state"] in ~w(ready claimed pending) do
      state = if unresolved?(r["execution"]), do: "uncertain", else: "cancelled"

      e =
        put_in(r["execution"]["progress"], Budget.abandon(r["execution"]["progress"]))[
          "execution"
        ]

      {:ok, put_execution(r, release(e, state))}
    else
      {:error, :invalid_transition}
    end
  end

  defp reduce(_, _, _, _), do: {:error, :invalid_transition}

  # Narrow data-only operations. Callback results are trusted command inputs;
  # every mutation is assembled here and certified before Store saves anything.
  defp reduce10(r, operation, p, now) do
    root = r["execution"]["progress"]["runtime"]
    version = root["frame_version"]

    fields =
      case operation do
        op when op in ~w(flow_select_begin flow_merge_begin) and version == 11 ->
          []

        "flow_select" when version == 11 ->
          ~w(selected)

        "flow_merge" when version == 11 ->
          ~w(result elapsed_ms)

        "flow_branch_done" when version == 11 ->
          ~w(branch_id)

        "flow_host_failed" when version == 11 ->
          ~w(error marker elapsed_ms)

        "step_input" ->
          ~w(node_id node authority)

        "node_attach" ->
          ~w(run_id request_id call_id node_id node authority)

        "begin_effect" ->
          if(Map.has_key?(p, "call_id"),
            do: ~w(run_id request_id call_id),
            else: ~w(run_id request_id request_data)
          )

        "outcome" ->
          if(Map.has_key?(p, "call_id"),
            do:
              ~w(run_id request_id call_id result control) ++
                if(Map.has_key?(p, "usage"), do: ["usage"], else: []) ++
                if(Map.has_key?(p, "observation"), do: ["observation"], else: []),
            else: ~w(run_id request_id response model_data)
          )

        "batch_begin" ->
          ~w(run_id request_id)

        "call_prepared" ->
          ~w(run_id request_id call_id args)

        "call_reject" ->
          ~w(run_id request_id call_id reason error)

        "call_settle" ->
          ~w(run_id request_id call_id result control)

        op when op in ~w(call_prepare call_wait call_wrap) ->
          ~w(run_id request_id call_id)

        op when op in ~w(tool_resolution batch_consume) ->
          ~w(run_id request_id)

        "output_resolution" ->
          ~w(run_id request_id resolution)

        "output_consume" ->
          ~w(run_id request_id)

        op when op in ~w(node_suspend node_complete) ->
          ~w(node_id)

        "step_output" ->
          ~w(node_id elapsed_ms)

        op when op in ~w(pause finish) ->
          ~w(elapsed_ms)

        "frontier_open" ->
          []

        _ ->
          nil
      end

    with true <- is_list(fields),
         :ok <- worker(r, p, ["epoch" | fields], now),
         false <- expired?(r["execution"], now),
         true <- p["epoch"] === root["frontier"]["epoch"],
         true <-
           version != 11 or
             operation not in ~w(begin_effect call_prepare call_prepared node_attach batch_begin) or
             not Map.has_key?(root["flow"]["failures"], Frame.branch_id11(root, p["run_id"])),
         true <-
           is_nil(root["frontier"]["fatal"]) or
             operation in ~w(outcome call_settle output_resolution finish flow_branch_done),
         true <- operation == "frontier_open" or root["frontier"]["state"] != "quiescent",
         {:ok, next} <- mutate10(r, operation, p, now) do
      {:ok,
       if(root["frame_version"] == 11,
         do: close_call_fatal11(next),
         else: close_call_fatal10(next)
       )}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_frame10_transition}
    end
  rescue
    _ -> {:error, :invalid_frame10_transition}
  end

  defp close_call_fatal11(record) do
    root = root10(record)
    failures = ExAgent.Continuation.ToolEvidence.branch_fatals11(record)
    record = put_root10(record, put_in(root, ["flow", "failures"], failures))

    if root["binding"]["failure_policy"] == "fail_fast",
      do: close_call_fatal10(record),
      else: record
  end

  defp close_call_fatal10(record) do
    root = root10(record)

    case {root["cursor"], ExAgent.Continuation.ToolEvidence.selected_call_fatal10(record)} do
      {_, nil} ->
        record

      {cursor, fatal} when cursor != "failed" ->
        frontier = %{
          "epoch" =>
            root["frontier"]["epoch"] + if(root["frontier"]["state"] == "open", do: 1, else: 0),
          "state" => "draining",
          "reason" => "fatal",
          "fatal" => fatal
        }

        put_root10(record, Map.put(root, "frontier", frontier))

      _ ->
        record
    end
  end

  defp mutate10(r, "finish", p, now) do
    root = root10(r)
    true = Record.counter?(p["elapsed_ms"]) and Frame.call_fatal_closable10?(r)
    error = root["frontier"]["fatal"]["error"]

    children =
      Map.new(root["children"], fn {id, node} ->
        {id,
         if(node["status"] in ~w(completed failed),
           do: node,
           else: node |> Map.put("status", "cancelled") |> Map.put("error", error)
         )}
      end)

    batches =
      Map.new(root["tool_batches"], fn {id, batch} ->
        calls =
          Map.new(batch["calls"], fn {call_id, call} ->
            {call_id,
             if(call["state"] == "settled",
               do: call,
               else: call |> Map.put("state", "blocked") |> Map.put("blocked_by", "fatal")
             )}
          end)

        {id, Map.put(batch, "calls", calls)}
      end)

    root =
      root
      |> Map.put("children", children)
      |> Map.put("tool_batches", batches)
      |> Map.put("cursor", "failed")
      |> put_in(["frontier", "state"], "quiescent")

    root =
      if root["frame_version"] == 11, do: put_in(root, ["flow", "phase"], "failed"), else: root

    r = put_root10(r, root)

    progress =
      r["execution"]["progress"] |> Budget.refund(p["elapsed_ms"]) |> Budget.confirm_refund(now)

    {:ok, put_execution(r, release(%{r["execution"] | "progress" => progress}, "failed"))}
  end

  defp mutate10(r, operation, p, _now) when operation in ~w(step_input node_attach) do
    root = root10(r)
    node = p["node"]
    id = p["node_id"]
    true = Record.text?(id) and not Map.has_key?(root["children"], id)

    true =
      node["status"] == "running" and node["frame"]["run_step"] == 0 and
        node["frame"]["cursor"] == "request" and is_nil(node["frame"]["model_request_id"])

    true = node["frame"]["outcomes"] == %{}

    root =
      if operation == "step_input" do
        true =
          root["frontier"]["state"] == "open" and
            if(root["frame_version"] == 11,
              do:
                root["flow"]["phase"] == "running" and root["cursor"] == "running" and
                  node["link"]["step_id"] in root["flow"]["selected"],
              else: root["cursor"] in ~w(empty between_steps)
            )

        true = node["link"]["kind"] == "step" and node["parent_run_id"] == root["run_id"]
        Map.put(root, "cursor", "running")
      else
        call = call10(root, p)
        true = call["state"] == "prepared" and is_nil(call["source"])
        :ok = resources10(root, p["run_id"], :reserved)

        true =
          node["parent_run_id"] == p["run_id"] and
            node["link"] ===
              Map.merge(call["binding"], %{
                "kind" => "delegate",
                "parent_request_id" => p["request_id"],
                "call_id" => p["call_id"]
              })

        put_call10(root, p, %{
          call
          | "state" => "child",
            "source" => %{"kind" => "child", "id" => id}
        })
      end

    scope =
      put_in(root["scope"], ["nodes", id], %{
        "parent_run_id" => node["parent_run_id"],
        "requests" => 0,
        "tools" => 0
      })

    root = root |> put_in(["children", id], node) |> put_in(["authority", id], p["authority"])
    {:ok, put_root10(r, Frame.with_scope(root, scope))}
  end

  defp mutate10(r, "begin_effect", %{"call_id" => _} = p, _now) do
    root = root10(r)
    call = call10(root, p)
    true = call["state"] == "prepared" and root["frontier"]["state"] in ~w(open draining)
    :ok = resources10(root, p["run_id"], :reserved)

    descriptor =
      Frame.request_data10(r, p["run_id"], p["request_id"])["tool_descriptors"][
        call["binding"]["tool_name"]
      ]

    false = Map.has_key?(descriptor, "delegation")
    id = ExAgent.Continuation.ToolEvidence.effect_id(p["run_id"], p["request_id"], p["call_id"])
    false = Map.has_key?(r["execution"]["effects"], id)

    intent = %{
      "kind" => "tool",
      "call_id" => p["call_id"],
      "payload" =>
        Map.merge(call["binding"], %{
          "run_id" => p["run_id"],
          "model_request_id" => p["request_id"],
          "phase" => "dispatch"
        })
    }

    root =
      put_call10(root, p, %{
        call
        | "state" => "dispatching",
          "source" => %{"kind" => "effect", "id" => id}
      })

    {:ok,
     r
     |> put_root10(root)
     |> put_in(["execution", "effects", id], %{
       "intent" => intent,
       "state" => "running",
       "outcome" => nil
     })}
  end

  defp mutate10(r, "begin_effect", p, _now) do
    root = root10(r)
    node = root["children"][p["run_id"]]

    true =
      (root["frontier"]["state"] == "open" or
         (root["frame_version"] == 11 and root["frontier"]["reason"] == "approval")) and
        node["status"] == "running"

    true =
      root["frame_version"] != 11 or
        not Map.has_key?(root["flow"]["failures"], Frame.branch_id11(root, p["run_id"]))

    true = node["frame"]["cursor"] == "request" and node["frame"]["outcomes"] == %{}
    true = ExAgent.Continuation.RequestData.valid10?(p["request_data"])
    :ok = resources10(root, p["run_id"], :request)

    true =
      Record.digest(node["frame"]["model_data"]) == {:ok, p["request_data"]["model_state_hash"]}

    true =
      Enum.all?(r["execution"]["effects"], fn {_, e} ->
        e["intent"]["call_id"] != p["request_id"]
      end)

    step = node["frame"]["run_step"] + 1
    {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"])
    true = ExAgent.Retention.executable?(messages)

    intent = %{
      "kind" => "model",
      "call_id" => p["request_id"],
      "payload" => %{
        "run_id" => p["run_id"],
        "phase" => "model_dispatch",
        "step" => step,
        "history_index" => length(messages),
        "request_data" => p["request_data"]
      }
    }

    id =
      "model-" <> elem(Record.digest([p["run_id"], p["request_id"], "model", p["request_id"]]), 1)

    ancestors = ancestors10(root["scope"], p["run_id"])

    op = %{
      "id" => ["model", p["request_id"]],
      "run_id" => p["run_id"],
      "usage" => nil,
      "terminal_usage" => nil,
      "complete" => false,
      "ancestors" => Map.new(ancestors, &{&1, nil})
    }

    scope =
      root["scope"]
      |> update_in(["operations"], &(&1 ++ [op]))
      |> count10(ancestors, "requests", 1)

    node =
      node
      |> put_in(["frame", "run_step"], step)
      |> put_in(["snapshot", "revision"], step)
      |> put_in(["frame", "model_request_id"], p["request_id"])
      # The attached input precedes request preparation. Bind the effective
      # request in the same CAS as its intent, not a pre-preparation inventory or
      # an attempt-local timeout. The certificate also checks every prior request,
      # so this cannot silently replace a previously confirmed binding.
      |> put_in(["frame", "selected_tools"], p["request_data"]["tools"])
      |> put_in(["frame", "settings"], p["request_data"]["settings"])
      |> put_in(["frame", "output_fingerprint"], p["request_data"]["output_fingerprint"])

    root = root |> put_in(["children", p["run_id"]], node) |> Frame.with_scope(scope)

    {:ok,
     r
     |> put_root10(root)
     |> put_in(["execution", "effects", id], %{
       "intent" => intent,
       "state" => "running",
       "outcome" => nil
     })}
  end

  defp mutate10(r, "outcome", %{"call_id" => _} = p, _now) do
    root = root10(r)
    call = call10(root, p)
    true = call["state"] == "dispatching" and is_nil(call["raw"])
    part = part10(p["result"])
    true = is_nil(part.usage)
    {:ok, outcome} = Outcome.new(part, "raw")
    call = %{call | "raw" => %{"result" => p["result"], "control" => p["control"]}}
    root = root |> put_call10(p, call) |> observe10(p, p["result"])

    {:ok,
     r
     |> put_root10(root)
     |> put_in(["execution", "effects", call["source"]["id"], "outcome"], outcome)
     |> put_in(["execution", "effects", call["source"]["id"], "state"], "confirmed")}
  end

  defp mutate10(r, "outcome", p, _now) do
    root = root10(r)
    node = root["children"][p["run_id"]]

    {id, effect} =
      Enum.find(r["execution"]["effects"], fn {_, e} ->
        e["intent"]["kind"] == "model" and e["intent"]["call_id"] == p["request_id"] and
          e["intent"]["payload"]["run_id"] == p["run_id"]
      end)

    true = effect["state"] == "running" and node["status"] == "running"
    {:ok, [%ExAgent.Message.Response{} = response]} = ExAgent.Message.from_json(p["response"])
    {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"])

    slot =
      case node["frame"]["limits"] do
        %{"max_history_bytes" => history_limit, "max_payload_bytes" => payload_limit} ->
          {:ok, slot} =
            ExAgent.Retention.durable_slots(
              messages,
              response,
              p["run_id"],
              history_limit,
              payload_limit
            )

          slot

        _ ->
          node["frame"]["tool_return_bytes"]
      end

    node =
      node
      |> put_in(["snapshot", "message_history"], ExAgent.Message.to_json(messages ++ [response]))
      |> put_in(["frame", "model_data"], p["model_data"])
      |> put_in(["frame", "cursor"], "response")
      |> put_in(["frame", "tool_return_bytes"], slot)

    scope =
      update_in(root["scope"], ["operations"], fn ops ->
        Enum.map(ops, fn op ->
          if op["id"] == ["model", p["request_id"]] and op["run_id"] == p["run_id"],
            do: contribution10(op, response.usage, true),
            else: op
        end)
      end)

    root = root |> put_in(["children", p["run_id"]], node) |> Frame.with_scope(scope)

    {:ok,
     r
     |> put_root10(root)
     |> put_in(["execution", "effects", id], %{
       effect
       | "state" => "confirmed",
         "outcome" => Outcome.model(response, p["model_data"])
     })}
  end

  defp mutate10(r, "batch_begin", p, _now) do
    root = root10(r)
    node = root["children"][p["run_id"]]

    true =
      (root["frontier"]["state"] == "open" or
         (root["frame_version"] == 11 and root["frontier"]["state"] == "draining" and
            root["frontier"]["reason"] == "approval")) and node["status"] == "running" and
        node["frame"]["cursor"] == "response"

    true = node["frame"]["model_request_id"] == p["request_id"]
    key = batch_key10(p)
    false = Map.has_key?(root["tool_batches"], key)
    {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"])
    calls = ExAgent.Message.Response.tool_calls(List.last(messages))
    :ok = resources10(root, p["run_id"], {:batch, length(calls)})
    data = Frame.request_data10(r, p["run_id"], p["request_id"])

    limits =
      Map.new(calls, fn call ->
        {call.tool_name,
         %{
           "schema_hash" => data["tools"][call.tool_name],
           "max_retries" => get_in(data, ["tool_descriptors", call.tool_name, "max_retries"]) || 0
         }}
      end)

    batch = %{
      "run_id" => p["run_id"],
      "request_id" => p["request_id"],
      "limits" => limits,
      "calls" =>
        Map.new(
          calls,
          &{&1.tool_call_id,
           %{
             "state" => "queued",
             "binding" => nil,
             "source" => nil,
             "raw" => nil,
             "result" => nil,
             "control" => nil,
             "blocked_by" => nil
           }}
        ),
      "observations" => %{},
      "resolution" => nil,
      "consumption" => nil
    }

    scope =
      root["scope"]
      |> update_in(
        ["batches"],
        &(&1 ++ [%{"id" => p["request_id"], "run_id" => p["run_id"], "count" => length(calls)}])
      )
      |> count10(ancestors10(root["scope"], p["run_id"]), "tools", length(calls))

    root =
      root
      |> put_in(["tool_batches", key], batch)
      |> put_in(["children", p["run_id"], "frame", "cursor"], "batch")
      |> Frame.with_scope(scope)

    {:ok, put_root10(r, root)}
  end

  defp mutate10(r, operation, p, _now)
       when operation in ~w(call_prepare call_prepared call_wait call_wrap call_settle) do
    root = root10(r)
    call = call10(root, p)
    true = root["children"][p["run_id"]]["status"] == "running"

    {call, root, r} =
      case operation do
        "call_prepare" ->
          true = call["state"] == "queued"
          {%{call | "state" => "preparing"}, root, r}

        "call_prepared" ->
          true =
            call["state"] == "preparing" or
              (call["state"] == "approval" and
                 (root["frontier"]["state"] == "open" or
                    (root["frame_version"] == 11 and
                       root["frontier"]["state"] == "draining" and
                       root["frontier"]["reason"] == "approval" and
                       is_nil(root["frontier"]["fatal"]))) and
                 Frame.authorized10?(
                   r,
                   p["run_id"],
                   p["request_id"],
                   p["call_id"],
                   call["binding"]
                 ))

          batch = root["tool_batches"][batch_key10(p)]

          original =
            Enum.find(
              ExAgent.Continuation.ToolEvidence.calls(r, batch),
              &(&1.tool_call_id == p["call_id"])
            )

          binding = %{
            "tool_name" => original.tool_name,
            "args" => p["args"],
            "schema_hash" => batch["limits"][original.tool_name]["schema_hash"],
            "call_hash" => elem(Outcome.call_hash(original), 1)
          }

          true = call["state"] != "approval" or binding === call["binding"]

          {%{call | "state" => "prepared", "binding" => binding}, root, r}

        "call_wait" ->
          true = call["state"] == "prepared"
          true = Frame.permission10(r, p["run_id"], call["binding"]["tool_name"]) == :ask

          frontier =
            if root["frontier"]["state"] == "open",
              do: %{
                "epoch" => root["frontier"]["epoch"] + 1,
                "state" => "draining",
                "reason" => "approval",
                "fatal" => nil
              },
              else: root["frontier"]

          {%{call | "state" => "approval"}, Map.put(root, "frontier", frontier), r}

        "call_wrap" ->
          true = call["state"] in ~w(dispatching child) and not is_nil(call["raw"])
          {%{call | "state" => "wrapping"}, root, r}

        "call_settle" ->
          true = call["state"] == "wrapping" and not is_nil(call["raw"])
          part = part10(p["result"])
          true = is_nil(part.usage) and part.status != :unknown
          {:ok, raw_hash} = Outcome.hash(call["raw"]["result"])
          {:ok, outcome} = Outcome.new(part, "final", raw_hash)
          true = call["source"]["kind"] in ~w(effect child)

          r =
            if call["source"]["kind"] == "effect",
              do: put_in(r, ["execution", "effects", call["source"]["id"], "outcome"], outcome),
              else: r

          root =
            put_in(
              root,
              ["children", p["run_id"], "frame", "outcomes", p["call_id"]],
              p["result"]
            )

          {%{call | "state" => "settled", "result" => p["result"], "control" => p["control"]},
           root, r}
      end

    {:ok, put_root10(r, put_call10(root, p, call))}
  end

  defp mutate10(r, "call_reject", p, _now) do
    root = root10(r)
    call = call10(root, p)
    batch = root["tool_batches"][batch_key10(p)]

    original =
      Enum.find(
        ExAgent.Continuation.ToolEvidence.calls(r, batch),
        &(&1.tool_call_id == p["call_id"])
      )

    prepared = p["reason"] in ~w(permission_denied admission_error)

    true =
      call["state"] == if(prepared, do: "prepared", else: "preparing") or
        (call["state"] == "approval" and p["reason"] == "permission_denied" and
           Frame.permission10(r, p["run_id"], original.tool_name) != :allow)

    data = Frame.request_data10(r, p["run_id"], p["request_id"])
    true = p["reason"] != "unknown_tool" or is_nil(data["tool_descriptors"][original.tool_name])

    true =
      p["reason"] != "permission_denied" or
        Frame.permission10(r, p["run_id"], original.tool_name) != :allow

    {:ok, raw} = ExAgent.Continuation.ToolEvidence.host_raw10(p["reason"], original, p["error"])

    source =
      if prepared,
        do: %{"kind" => "host", "reason" => p["reason"]},
        else: %{
          "kind" => "host",
          "phase" => "unprepared",
          "reason" => p["reason"],
          "tool_name" => original.tool_name,
          "call_hash" => elem(Outcome.call_hash(original), 1)
        }

    call = %{
      call
      | "state" => "settled",
        "source" => source,
        "raw" => raw,
        "result" => raw["result"],
        "control" => raw["control"]
    }

    id = ExAgent.Continuation.ToolEvidence.effect_id(p["run_id"], p["request_id"], p["call_id"])

    root =
      root
      |> put_call10(p, call)
      |> put_in(
        ["tool_batches", batch_key10(p), "observations", id],
        ExAgent.Continuation.ToolEvidence.pre_dispatch()
      )
      |> put_in(["children", p["run_id"], "frame", "outcomes", p["call_id"]], raw["result"])

    {:ok, put_root10(r, root)}
  end

  # Trusted producer attestations: validation/hook callbacks are not rerun by
  # transitions or Record.decode. Identity, phase, history and limits are checked
  # here and by the global certificate before the CAS can commit.
  defp mutate10(r, "output_resolution", p, _now) do
    root = root10(r)
    node = root["children"][p["run_id"]]
    request = p["request_id"]
    entry = p["resolution"]

    true = node["status"] == "running" and node["frame"]["cursor"] == "response"
    true = node["frame"]["model_request_id"] === request
    true = entry["run_id"] === p["run_id"] and entry["request_id"] === request
    true = is_nil(root["output_resolutions"][request])
    true = is_nil(root["tool_batches"][batch_key10(p)])
    {:ok, _} = ExAgent.Continuation.OutputResolution.output_config(entry)
    true = is_nil(entry["result_omitted"]) or node["link"]["kind"] == "step"

    true = entry["decision"] in ~w(succeeded retry)
    used = node["frame"]["output_retries_used"]
    limit = node["frame"]["limits"]["output_retries"]
    true = used <= limit
    exhausted = entry["decision"] == "retry" and used == limit
    true = is_nil(root["frontier"]["fatal"]) or exhausted
    root = put_in(root, ["output_resolutions", request], entry)

    if exhausted do
      {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"])
      {:ok, [message]} = ExAgent.Message.from_json(entry["parts"])

      node =
        node
        |> Map.put("status", "failed")
        |> Map.put("error", ExAgent.Continuation.OutputResolution.exhaustion_error10())
        |> put_in(["snapshot", "message_history"], ExAgent.Message.to_json(messages ++ [message]))

      if node["link"]["kind"] == "delegate" do
        complete_delegate10(r, root, node, %{"node_id" => p["run_id"]})
      else
        {:ok, put_root10(r, put_in(root, ["children", p["run_id"]], node))}
      end
    else
      {:ok, put_root10(r, root)}
    end
  end

  defp mutate10(r, "output_consume", p, _now) do
    root = root10(r)
    node = root["children"][p["run_id"]]
    entry = root["output_resolutions"][p["request_id"]]
    true = node["status"] == "running" and node["frame"]["cursor"] == "response"
    true = node["frame"]["model_request_id"] === p["request_id"]
    true = entry["decision"] == "retry" and entry["run_id"] === p["run_id"]
    true = node["frame"]["output_retries_used"] < node["frame"]["limits"]["output_retries"]
    {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"])
    {:ok, [message]} = ExAgent.Message.from_json(entry["parts"])

    node =
      node
      |> put_in(["snapshot", "message_history"], ExAgent.Message.to_json(messages ++ [message]))
      |> put_in(["frame", "cursor"], "request")
      |> update_in(["frame", "output_retries_used"], &(&1 + 1))

    {:ok, put_root10(r, put_in(root, ["children", p["run_id"]], node))}
  end

  defp mutate10(r, operation, p, now) when operation in ~w(node_complete step_output) do
    root = root10(r)
    node = root["children"][p["node_id"]]

    true =
      node["status"] == "running" and
        node["link"]["kind"] == if(operation == "step_output", do: "step", else: "delegate") and
        node["frame"]["cursor"] == "response"

    if operation == "step_output" do
      true =
        Record.counter?(p["elapsed_ms"]) and
          (root["frontier"]["state"] == "open" or
             (root["frame_version"] == 11 and root["frontier"]["reason"] == "approval"))

      true = root["frame_version"] == 11 or Frame.active_step_id(root) == p["node_id"]
    end

    true =
      Enum.all?(root["children"], fn {_, n} ->
        n["parent_run_id"] != p["node_id"] or n["status"] == "completed"
      end)

    {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"])
    response = List.last(messages)

    entry = root["output_resolutions"][node["frame"]["model_request_id"]]

    {result, omitted, messages} =
      if is_nil(entry) do
        true =
          response.parts != [] and
            Enum.all?(response.parts, &match?(%ExAgent.Message.Part.Text{}, &1))

        {:ok, fingerprint} =
          Frame.output_fingerprint(%{
            output_mode: :text,
            allow_text_output: true,
            output_object: nil,
            output_tools: []
          })

        true = node["frame"]["output_fingerprint"] === fingerprint
        {ExAgent.Message.Response.text(response), nil, messages}
      else
        true = entry["decision"] == "succeeded"
        # A sequence may ACK a completed, unrepresentable typed value and report
        # its checkpoint omission. Delegated completion must still have raw data.
        true = operation == "step_output" or is_nil(entry["result_omitted"])
        {:ok, [message]} = ExAgent.Message.from_json(entry["parts"])
        {entry["result"], entry["result_omitted"], messages ++ [message]}
      end

    node =
      node
      |> Map.put("status", "completed")
      |> Map.put("result", result)
      |> Map.put("result_omitted", omitted)
      |> put_in(["snapshot", "message_history"], ExAgent.Message.to_json(messages))
      |> put_in(["frame", "cursor"], "finish")

    node =
      case ExAgent.Continuation.ToolEvidence.child_retention_error10(root, node, result) do
        nil ->
          node

        error ->
          node
          |> Map.put("status", "failed")
          |> Map.put("result", nil)
          |> Map.put("result_omitted", nil)
          |> Map.put("error", error)
          |> put_in(["frame", "cursor"], "response")
      end

    if operation == "step_output" do
      terminal? =
        root["frame_version"] == 10 and
          node["link"]["index"] == length(root["binding"]["steps"]) - 1

      root =
        root
        |> put_in(["children", p["node_id"]], node)
        |> Map.put(
          "cursor",
          if(root["frame_version"] == 11,
            do: "running",
            else: if(terminal?, do: "completed", else: "between_steps")
          )
        )

      r = put_root10(r, root)

      if terminal? do
        true = not Record.unresolved?(r["execution"])

        progress =
          r["execution"]["progress"]
          |> Budget.refund(p["elapsed_ms"])
          |> Budget.confirm_refund(now)

        {:ok, put_execution(r, release(%{r["execution"] | "progress" => progress}, "completed"))}
      else
        {:ok, r}
      end
    else
      complete_delegate10(r, root, node, p)
    end
  end

  defp mutate10(r, "tool_resolution", p, _now) do
    root = root10(r)
    batch = root["tool_batches"][batch_key10(p)]

    true =
      is_nil(batch["resolution"]) and
        Enum.all?(batch["calls"], fn {_, c} -> c["state"] == "settled" end)

    calls = ExAgent.Continuation.ToolEvidence.calls(r, batch)

    controls =
      Enum.map(calls, fn call ->
        c = batch["calls"][call.tool_call_id]
        {call.tool_name, part10(c["result"]).status, c["control"]["retry"], c["control"]["error"]}
      end)

    {counts, error} =
      ExAgent.Continuation.ToolEvidence.reduce(
        controls,
        root["children"][p["run_id"]]["frame"]["tool_retries"],
        batch["limits"]
      )

    true = root["frame_version"] == 11 or is_nil(error)

    root =
      root
      |> put_in(["tool_batches", batch_key10(p), "resolution"], %{
        "tool_retries" => counts,
        "error" =>
          if(is_map(error), do: error, else: ExAgent.Continuation.ToolEvidence.error(error))
      })
      |> put_in(["children", p["run_id"], "frame", "tool_retries"], counts)

    {:ok, put_root10(r, root)}
  end

  defp mutate10(r, "batch_consume", p, _now) do
    root = root10(r)
    batch = root["tool_batches"][batch_key10(p)]

    true =
      not is_nil(batch["resolution"]) and is_nil(batch["resolution"]["error"]) and
        is_nil(batch["consumption"])

    calls = ExAgent.Continuation.ToolEvidence.calls(r, batch)
    parts = Enum.map(calls, &part10(batch["calls"][&1.tool_call_id]["result"]))
    request = %ExAgent.Message.Request{parts: parts}
    node = root["children"][p["run_id"]]
    {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"])

    consumption = %{
      "history_index" => length(messages),
      "returns_hash" => elem(Outcome.hash(ExAgent.Message.to_json([request])), 1)
    }

    node =
      node
      |> put_in(["snapshot", "message_history"], ExAgent.Message.to_json(messages ++ [request]))
      |> put_in(["frame", "cursor"], "request")
      |> put_in(["frame", "outcomes"], %{})

    root =
      root
      |> put_in(["tool_batches", batch_key10(p), "consumption"], consumption)
      |> put_in(["children", p["run_id"]], node)

    {:ok, put_root10(r, root)}
  end

  defp mutate10(r, "node_suspend", p, _now) do
    root = root10(r)
    true = root["frontier"]["state"] == "draining" and root["frontier"]["reason"] == "approval"
    true = root["children"][p["node_id"]]["status"] == "running"

    true =
      Enum.all?(root["children"], fn {_, n} ->
        n["parent_run_id"] != p["node_id"] or n["status"] in ~w(suspended completed) or
          (root["frame_version"] == 11 and n["status"] in ~w(failed cancelled))
      end)

    true =
      Enum.all?(r["execution"]["effects"], fn {_, e} ->
        e["intent"]["payload"]["run_id"] != p["node_id"] or e["state"] == "confirmed"
      end)

    true =
      Enum.all?(root["tool_batches"], fn {_, b} ->
        b["run_id"] != p["node_id"] or
          Enum.all?(b["calls"], fn {_, c} -> c["state"] in ~w(approval child settled) end)
      end)

    {:ok, put_root10(r, put_in(root, ["children", p["node_id"], "status"], "suspended"))}
  end

  defp mutate10(r, "pause", p, now) do
    root = root10(r)
    true = root["frontier"]["state"] == "draining" and root["frontier"]["reason"] == "approval"
    true = Record.counter?(p["elapsed_ms"])

    true =
      Enum.all?(root["children"], fn {_, n} ->
        n["status"] in ~w(suspended completed) or
          (root["frame_version"] == 11 and n["status"] in ~w(failed cancelled))
      end)

    true = not Record.unresolved?(r["execution"])

    approvals =
      for {_, b} <- root["tool_batches"],
          {id, c} <- b["calls"],
          c["state"] == "approval",
          into: %{} do
        child = root["children"][b["run_id"]]

        aid =
          "approval-" <> elem(Record.digest([b["run_id"], b["request_id"], "approval", id]), 1)

        {:ok, approval} =
          Approval.new(
            Map.merge(Map.take(c["binding"], ~w(tool_name args schema_hash)), %{
              "id" => aid,
              "run_id" => b["run_id"],
              "call_id" => id,
              "definition" => child["definition"],
              "policy" => child["policy"],
              "requested_revision" => r["revision"] + 1
            })
          )

        {aid, approval}
      end

    true = map_size(approvals) > 0
    old = Map.get(r["execution"]["progress"], "approvals", %{})
    true = MapSet.disjoint?(MapSet.new(Map.keys(old)), MapSet.new(Map.keys(approvals)))
    root = put_in(root, ["frontier", "state"], "quiescent")
    r = put_root10(r, root)

    progress =
      r["execution"]["progress"]
      |> Map.put("approvals", Map.merge(old, approvals))
      |> Budget.refund(p["elapsed_ms"])
      |> Budget.confirm_refund(now)

    {:ok, put_execution(r, release(%{r["execution"] | "progress" => progress}, "pending"))}
  end

  defp mutate10(r, "frontier_open", _p, _now) do
    root = root10(r)
    true = root["frontier"]["state"] == "quiescent"

    true =
      Enum.all?(r["execution"]["progress"]["approvals"], fn {_, a} -> Approval.approved?(a) end)

    root =
      root
      |> put_in(["frontier", "state"], "open")
      |> put_in(["frontier", "reason"], nil)
      |> update_in(["children"], fn children ->
        Map.new(children, fn {id, n} ->
          {id, if(n["status"] == "suspended", do: %{n | "status" => "running"}, else: n)}
        end)
      end)

    # Approvals do not themselves dispatch calls or authorize callback replay.
    {:ok, put_root10(r, root)}
  end

  defp mutate10(r, "flow_select_begin", _p, _now) do
    root = root10(r)

    true =
      root["frame_version"] == 11 and root["flow"]["phase"] == "idle" and
        root["frontier"]["state"] == "open"

    {:ok, put_root10(r, put_in(root, ["flow", "phase"], "selecting"))}
  end

  defp mutate10(r, "flow_select", p, _now) do
    root = root10(r)
    true = root["frame_version"] == 11 and root["flow"]["phase"] == "selecting"
    ids = Enum.map(root["binding"]["steps"], & &1["id"])
    selected = p["selected"]

    true =
      is_list(selected) and selected != [] and selected === Enum.filter(ids, &(&1 in selected))

    true =
      (root["binding"]["kind"] == "parallel" and selected === ids) or
        (root["binding"]["kind"] == "router" and length(selected) == 1)

    root =
      root
      |> put_in(["flow", "phase"], "running")
      |> put_in(["flow", "selected"], selected)
      |> Map.put("cursor", "running")

    {:ok, put_root10(r, root)}
  end

  defp mutate10(r, "flow_branch_done", p, _now) do
    root = root10(r)
    true = root["frame_version"] == 11 and Frame.branch_closable11?(r, p["branch_id"])
    fatal = root["flow"]["failures"][p["branch_id"]]

    ids =
      root["children"]
      |> Enum.filter(fn {id, _} -> Frame.branch_id11(root, id) == p["branch_id"] end)
      |> Enum.map(&elem(&1, 0))

    children =
      Map.new(root["children"], fn {id, n} ->
        {id,
         if id in ids and n["status"] not in ~w(completed failed) do
           n
           |> Map.put("status", if(n["link"]["kind"] == "step", do: "failed", else: "cancelled"))
           |> Map.put("error", fatal["error"])
         else
           n
         end}
      end)

    batches =
      Map.new(root["tool_batches"], fn {id, b} ->
        calls =
          if b["run_id"] in ids,
            do:
              Map.new(b["calls"], fn {cid, c} ->
                {cid,
                 if(c["state"] == "settled",
                   do: c,
                   else: c |> Map.put("state", "blocked") |> Map.put("blocked_by", "fatal")
                 )}
              end),
            else: b["calls"]

        {id, Map.put(b, "calls", calls)}
      end)

    root = root |> Map.put("children", children) |> Map.put("tool_batches", batches)
    {:ok, put_root10(r, root)}
  end

  defp mutate10(r, "flow_merge_begin", _p, _now) do
    root = root10(r)

    true =
      root["frame_version"] == 11 and root["flow"]["phase"] == "running" and
        Frame.terminal_branches11?(root)

    true = root["frontier"]["state"] == "open" and not Record.unresolved?(r["execution"])
    true = root["binding"]["failure_policy"] == "collect" or root["flow"]["failures"] == %{}
    {:ok, put_root10(r, put_in(root, ["flow", "phase"], "merging"))}
  end

  defp mutate10(r, "flow_merge", p, now) do
    root = root10(r)

    true =
      root["frame_version"] == 11 and root["flow"]["phase"] == "merging" and
        Frame.terminal_branches11?(root)

    true = Record.counter?(p["elapsed_ms"])
    {:ok, result} = JSON.normalize(p["result"])

    true =
      result === p["result"] and
        byte_size(Jason.encode!(result)) <= root["binding"]["max_result_bytes"]

    root =
      root
      |> put_in(["flow", "phase"], "completed")
      |> put_in(["flow", "result"], result)
      |> Map.put("cursor", "completed")

    r = put_root10(r, root)
    true = not Record.unresolved?(r["execution"])

    progress =
      r["execution"]["progress"] |> Budget.refund(p["elapsed_ms"]) |> Budget.confirm_refund(now)

    {:ok, put_execution(r, release(%{r["execution"] | "progress" => progress}, "completed"))}
  end

  defp mutate10(r, "flow_host_failed", p, now) do
    root = root10(r)
    true = root["frame_version"] == 11 and root["flow"]["phase"] in ~w(selecting merging)
    true = Record.counter?(p["elapsed_ms"]) and Frame.host_closable11?(r)
    true = not is_nil(p["error"]) and ExAgent.Continuation.ToolEvidence.error?(p["error"])
    true = ExAgent.Retention.marker!(p["marker"]) === p["marker"]
    true = p["error"]["omitted"] === p["marker"]

    true =
      is_nil(p["marker"]) or
        (root["flow"]["phase"] == "merging" and p["marker"]["boundary"] == "output" and
           p["marker"]["limit"] === root["binding"]["max_result_bytes"] and
           p["marker"]["bytes"] > p["marker"]["limit"])

    phase = root["flow"]["phase"]

    root =
      root
      |> put_in(["flow", "phase"], "failed")
      |> put_in(["flow", "host_error"], %{"phase" => phase, "error" => p["error"]})
      |> put_in(["flow", "result_omitted"], p["marker"])
      |> Map.put("cursor", "failed")
      |> Map.put("frontier", %{
        "epoch" => root["frontier"]["epoch"] + 1,
        "state" => "quiescent",
        "reason" => "fatal",
        "fatal" => %{"kind" => "root", "error" => p["error"]}
      })

    r = put_root10(r, root)

    progress =
      r["execution"]["progress"] |> Budget.refund(p["elapsed_ms"]) |> Budget.confirm_refund(now)

    {:ok, put_execution(r, release(%{r["execution"] | "progress" => progress}, "failed"))}
  end

  defp mutate10(_, _, _, _), do: {:error, :unsupported_structural_operation}

  defp complete_delegate10(r, root, node, p) do
    target = %{
      "run_id" => node["parent_run_id"],
      "request_id" => node["link"]["parent_request_id"],
      "call_id" => node["link"]["call_id"]
    }

    call = call10(root, target)
    true = call["state"] == "child" and is_nil(call["raw"])

    tool_call = %ExAgent.Message.Part.ToolCall{
      tool_name: node["link"]["tool_name"],
      tool_call_id: node["link"]["call_id"]
    }

    {:ok, raw} = ExAgent.Continuation.ToolEvidence.child_raw10(node, tool_call)

    root =
      root
      |> put_in(["children", p["node_id"]], node)
      |> put_call10(target, %{call | "raw" => raw})
      |> observe10(target, raw["result"])

    {:ok, put_root10(r, root)}
  end

  defp root10(r), do: r["execution"]["progress"]["runtime"]

  defp put_root10(r, root) do
    root = Frame.with_scope(root, root["scope"])

    root =
      update_in(root, ["children"], fn children ->
        Map.new(children, fn {id, child} ->
          {id, put_in(child, ["snapshot", "usage"], Frame.usage10(root["scope"], id))}
        end)
      end)

    put_in(r, ["execution", "progress", "runtime"], root)
  end

  defp batch_key10(p), do: ExAgent.Continuation.ToolEvidence.key(p["run_id"], p["request_id"])
  defp call10(root, p), do: root["tool_batches"][batch_key10(p)]["calls"][p["call_id"]]

  defp put_call10(root, p, call),
    do: put_in(root, ["tool_batches", batch_key10(p), "calls", p["call_id"]], call)

  defp part10(bytes) do
    {:ok, [%ExAgent.Message.Request{parts: [%ExAgent.Message.Part.ToolReturn{} = part]}]} =
      ExAgent.Message.from_json(bytes)

    true = Outcome.encode(part) === bytes
    part
  end

  defp observe10(root, p, bytes) do
    id = ExAgent.Continuation.ToolEvidence.effect_id(p["run_id"], p["request_id"], p["call_id"])
    # ToolReturn history deliberately omits usage. The fenced outcome command
    # carries the independent input observation; no wrapper or replay reapplies it.
    {observation, usage} =
      if Map.has_key?(p, "observation") do
        observation = p["observation"]
        true = is_nil(p["usage"])
        true = ExAgent.Continuation.ToolEvidence.observation?(observation)
        true = observation["origin"] == "tool_return"
        true = observation["application"]["status"] == "rejected"
        true = p["control"]["retry"] === false
        true = p["control"]["error"]["code"] == "invalid_tool_result"
        {observation, nil}
      else
        input = if is_nil(p["usage"]), do: nil, else: ExAgent.Message.Usage.from_map!(p["usage"])
        {observation, usage, nil} = ExAgent.Continuation.ToolEvidence.observe(input)
        {observation, usage}
      end

    {root, observation} =
      if is_nil(usage) do
        {root, observation}
      else
        operation =
          contribution10(
            %{
              "id" => ["tool", p["request_id"], p["call_id"]],
              "run_id" => p["run_id"],
              "usage" => nil,
              "terminal_usage" => nil,
              "complete" => false,
              "ancestors" => Map.new(ancestors10(root["scope"], p["run_id"]), &{&1, nil})
            },
            usage,
            false
          )

        root = update_in(root, ["scope", "operations"], &(&1 ++ [operation]))

        application = %{
          "status" => "contributed",
          "complete" => operation["complete"],
          "ancestors" => operation["ancestors"]
        }

        {root, Map.put(observation, "application", application)}
      end

    root
    |> put_in(
      ["tool_batches", batch_key10(p), "observations", id],
      observation
    )
    |> put_in(["children", p["run_id"], "frame", "outcomes", p["call_id"]], bytes)
  end

  defp contribution10(operation, usage, confirmed_nil) do
    alias ExAgent.Message.Usage

    if not is_nil(usage) do
      :ok = Usage.validate(usage)
      :ok = ExAgent.Retention.usage_error(usage)
    end

    data = if is_nil(usage), do: nil, else: Usage.to_map(Usage.qualify(usage))

    %{
      operation
      | "usage" => data,
        "terminal_usage" => data,
        "complete" => if(is_nil(usage), do: confirmed_nil, else: Usage.complete?(usage)),
        "ancestors" => Map.new(operation["ancestors"], fn {id, _} -> {id, data} end)
    }
  end

  # Retrospective thresholds use the existing pure checks. Already admitted
  # requests/tools are never readmitted when confirming outcomes or wrappers.
  defp resources10(root, run, admission) do
    alias ExAgent.{UsageLimits, Message.Usage}

    Enum.each(ancestors10(root["scope"], run), fn id ->
      limits = ExAgent.Continuation.Authority.limits_load(limits10(root, id))
      node = root["scope"]["nodes"][id]
      {:ok, usage} = ExAgent.Continuation.ScopeLedger.usage(root["scope"], id)

      cost =
        if limits.accounting == :estimated,
          do: usage.accounting["cost"]["subtotal_cents"],
          else: Usage.estimated_cost(usage)

      check = if admission == :request, do: limits, else: %{limits | request_limit: nil}
      :ok = UsageLimits.check_before_request(check, usage, node["requests"], cost)

      case admission do
        {:batch, count} -> :ok = UsageLimits.check_tool_calls(limits, node["tools"], count)
        :reserved -> :ok = UsageLimits.check_tool_calls(limits, node["tools"], 0)
        :request -> :ok
      end

      if limits.accounting == :estimated and UsageLimits.metric_limits?(limits) do
        true =
          Enum.any?(ancestors10(root["scope"], id), fn ancestor ->
            is_integer(limits10(root, ancestor)["request_limit"])
          end)
      end
    end)

    :ok
  end

  defp limits10(root, id),
    do:
      if(id == root["run_id"],
        do: root["authority"][id]["usage"],
        else: root["children"][id]["frame"]["limits"]["usage"]
      )

  defp ancestors10(scope, id) do
    case scope["nodes"][id]["parent_run_id"] do
      nil -> [id]
      parent -> ancestors10(scope, parent) ++ [id]
    end
  end

  defp count10(scope, ids, field, count),
    do: Enum.reduce(ids, scope, fn id, s -> update_in(s, ["nodes", id, field], &(&1 + count)) end)

  defp retry_effect(r, payload, actor, now, operation_id) do
    with false <- expired?(r["execution"], now),
         {:ok, execution} <- Retry.authorize(r, payload, actor, now, operation_id) do
      state = if Record.unresolved?(execution), do: "uncertain", else: "ready"
      {:ok, %{r | "execution" => Map.put(execution, "state", state)}}
    else
      true -> {:error, :expired}
      {:error, _} = error -> error
    end
  end

  defp acknowledge_history(r, payload, actor, now) do
    with true <- Record.exact?(payload, ~w(evidence_hash allow_evidence_deletion)),
         true <- payload["allow_evidence_deletion"] === true,
         true <- r["execution"]["state"] in ~w(completed denied expired cancelled),
         %{evidence_hash: hash} <- Retry.summary(r["execution"]),
         true <- hash === payload["evidence_hash"] do
      ack = %{"version" => 1, "evidence_hash" => hash, "actor_id" => actor, "at" => now}
      {:ok, put_in(r, ["execution", "progress", "historical_retention_ack"], ack)}
    else
      _ -> {:error, :invalid_history_acknowledgement}
    end
  end

  defp retained_history(execution),
    do:
      if(Retry.retention_blocked?(execution),
        do: {:error, :historical_uncertainty_retained},
        else: :ok
      )

  defp valid_pause_approvals?(r, approvals) do
    previous = Map.get(r["execution"]["progress"], "approvals", %{})
    added = Map.drop(approvals, Map.keys(previous))

    map_size(added) > 0 and
      Enum.all?(previous, fn {id, value} -> approvals[id] === value end) and
      Enum.all?(added, fn {_, a} ->
        is_nil(a["decision"]) and a["requested_revision"] == r["revision"] + 1
      end)
  end

  defp delegation_phase?(
         %{"outcome" => nil} = child,
         %{"status" => "succeeded", "data" => %{"phase" => "raw"} = data},
         part
       ) do
    raw = %{part | content: child["result"], usage: nil, payload_omitted: nil}
    Outcome.hash(raw) == {:ok, data["raw_hash"]} and data["raw_hash"] === data["result_hash"]
  end

  defp delegation_phase?(
         %{"outcome" => %{"status" => status, "data" => %{"phase" => "raw"} = old}},
         %{"status" => status, "data" => %{"phase" => "final"} = data},
         _
       ),
       do: old["raw_hash"] === data["raw_hash"]

  defp delegation_phase?(_, _, _), do: false

  defp decide(r, p, actor_id, now) do
    e = r["execution"]
    approval = get_in(e, ["progress", "approvals", p["approval_id"]])

    cond do
      not Record.exact?(p, ~w(approval_id payload_hash decision)) or
          p["decision"] not in ~w(approve deny) ->
        {:error, :invalid_command}

      e["state"] != "pending" ->
        {:error, :invalid_transition}

      expired?(e, now) ->
        {:error, :expired}

      not is_map(approval) or approval["payload_hash"] != p["payload_hash"] ->
        {:error, :approval_mismatch}

      not is_nil(approval["decision"]) ->
        {:error, :decision_conflict}

      true ->
        decision = %{"action" => p["decision"], "actor_id" => actor_id, "at" => now}
        e = put_in(e, ["progress", "approvals", p["approval_id"], "decision"], decision)

        state =
          cond do
            p["decision"] == "deny" -> "denied"
            Approval.pending_count(e["progress"]) == 0 -> "ready"
            true -> "pending"
          end

        {:ok, put_execution(r, %{e | "state" => state})}
    end
  end

  defp approvals_not_regressed(_, :delete, _), do: :ok
  defp approvals_not_regressed(_, _, operation) when operation in ~w(start decide), do: :ok

  defp approvals_not_regressed(old, new, operation) do
    previous = Map.get(old["execution"]["progress"], "approvals", %{})
    current = Map.get(new["execution"]["progress"], "approvals", %{})

    if is_map(current) and
         (operation == "pause" or Enum.sort(Map.keys(current)) == Enum.sort(Map.keys(previous))) and
         Enum.all?(previous, fn {id, approval} -> current[id] === approval end),
       do: :ok,
       else: {:error, :approval_regressed}
  end

  defp budget_not_regressed(_, :delete, _), do: :ok

  defp budget_not_regressed(old, new, "step_output") do
    operation = if new["execution"]["state"] == "completed", do: "finish", else: "node_checkpoint"
    budget_not_regressed(old, new, operation)
  end

  defp budget_not_regressed(old, new, operation)
       when operation in ~w(flow_merge flow_host_failed),
       do: budget_not_regressed(old, new, "finish")

  defp budget_not_regressed(old, new, operation) do
    if Budget.transition?(old["execution"]["progress"], new["execution"]["progress"], operation),
      do: :ok,
      else: {:error, :active_budget_regressed}
  end

  defp snapshot_not_regressed(_, :delete), do: :ok

  defp snapshot_not_regressed(old, new) do
    if is_map(new["snapshot"]) and
         Map.get(new["snapshot"], "revision", 0) >= Map.get(old["snapshot"], "revision", 0),
       do: :ok,
       else: {:error, :snapshot_revision_regressed}
  end

  defp reused_attempt?(r, p),
    do: Enum.any?(r["receipts"], fn {_, receipt} -> receipt["attempt_id"] == p["attempt_id"] end)

  defp worker(r, p, fields, now) do
    e = r["execution"]

    cond do
      not Record.exact?(p, ~w(owner_id attempt_id fence) ++ fields) ->
        {:error, :invalid_command}

      e["state"] != "claimed" or Enum.any?(~w(owner_id attempt_id fence), &(p[&1] !== e[&1])) ->
        {:error, :stale_owner}

      e["lease_until"] <= now ->
        {:error, :lease_expired}

      true ->
        :ok
    end
  end

  defp expired?(e, now),
    do: Enum.any?(~w(deadline_at expires_at), &(is_integer(e[&1]) and e[&1] <= now))

  defp earlier(nil, b), do: b
  defp earlier(a, nil), do: a
  defp earlier(a, b), do: min(a, b)

  defp unresolved?(e),
    do: Record.unresolved?(e)

  defp no_running(r),
    do: if(unresolved?(r["execution"]), do: {:error, :execution_uncertain}, else: :ok)

  defp effect_running(r, id) do
    case r["execution"]["effects"][id] do
      %{"state" => "running"} -> :ok
      _ -> {:error, :invalid_effect}
    end
  end

  defp effect_unresolved(r, id) do
    case r["execution"]["effects"][id] do
      %{"state" => "running"} -> :ok
      %{"outcome" => %{"status" => "unknown"}} -> :ok
      _ -> {:error, :invalid_effect}
    end
  end

  defp save_outcome(r, p) do
    r =
      r |> Map.put("snapshot", p["snapshot"]) |> put_in(["execution", "progress"], p["progress"])

    r =
      r
      |> put_in(["execution", "effects", p["effect_id"], "state"], "confirmed")
      |> put_in(["execution", "effects", p["effect_id"], "outcome"], p["outcome"])

    if p["outcome"]["status"] == "unknown",
      do: put_execution(r, release(r["execution"], "uncertain")),
      else: r
  end

  defp release(e, state),
    do: %{
      e
      | "state" => state,
        "owner_id" => nil,
        "attempt_id" => nil,
        "lease_until" => nil,
        "fence" => e["fence"] + 1
    }

  defp put_execution(r, e), do: %{r | "execution" => e}
end
