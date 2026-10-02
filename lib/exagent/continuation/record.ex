defmodule ExAgent.Continuation.Record do
  @moduledoc """
  Experimental, data-only continuation envelope. Existing snapshot codecs remain
  authoritative for history and qualified usage. No stored value resolves a module,
  template, credential or callable. Application JSON must already be secret-free.

  Records are bounded to 8 MiB encoded JSON, 256 effect entries and 1024 receipts,
  reserving minimal cleanup receipts/bytes before admitting further work.
  Receipts live until the whole terminal record is explicitly deleted; reaching a
  bound rejects a write rather than evicting idempotency evidence.
  """
  alias ExAgent.{RuntimeIdentity, Tool.JSON}
  alias ExAgent.Server.Snapshot
  alias ExAgent.Session.Snapshot, as: SessionSnapshot
  alias ExAgent.Continuation.{Approval, Budget, Frame, Outcome}

  @max_bytes 8 * 1024 * 1024
  @max_timestamp 9_223_372_036_854_775_807
  @fields ~w(record_version record_id key revision snapshot execution receipts created_at updated_at)
  @execution_fields ~w(execution_version continuation_id run_id request_id definition policy model_ref state owner_id attempt_id fence lease_until deadline_at expires_at progress effects)
  @states ~w(ready claimed pending uncertain completed denied expired cancelled)

  def max_bytes, do: @max_bytes

  def key({namespace, kind, id}) when kind in [:agent, :session] do
    with true <- text?(namespace) and text?(id),
         {:ok, encoded} <- RuntimeIdentity.key(namespace, kind, id) do
      {:ok, {kind, encoded}}
    else
      _ -> {:error, :invalid_record_key}
    end
  end

  def key(_), do: {:error, :invalid_record_key}
  def key_data({namespace, kind, id}), do: [namespace, Atom.to_string(kind), id]

  def snapshot_data(%Snapshot{} = snapshot), do: Jason.decode!(Snapshot.serialize(snapshot))

  def snapshot_data(%SessionSnapshot{} = snapshot),
    do: Jason.decode!(SessionSnapshot.serialize(snapshot))

  def snapshot(data, {_, kind, id}) when is_map(data) do
    codec = if kind == :agent, do: Snapshot, else: SessionSnapshot

    with {:ok, snapshot} <- codec.deserialize(Jason.encode!(data)),
         {:ok, snapshot} <- codec.validate(snapshot, id) do
      {:ok, snapshot}
    end
  rescue
    _ -> {:error, :invalid_snapshot}
  end

  def snapshot(_, _), do: {:error, :invalid_snapshot}

  @doc false
  def execution_snapshot(data, key, %{"execution_version" => 2, "kind" => "composition"}),
    do: ExAgent.Continuation.StructuralSnapshot.validate(data, key)

  def execution_snapshot(data, key, _), do: snapshot(data, key)

  def encode(record, key) do
    with :ok <- validate(record, key),
         {:ok, json} <- Jason.encode(record),
         true <- byte_size(json) <= @max_bytes do
      {:ok, json}
    else
      false -> {:error, :record_limit}
      {:error, _} = error -> error
    end
  end

  def decode(json, key) when is_binary(json) and byte_size(json) <= @max_bytes do
    with {:ok, ordered} <- Jason.decode(json, objects: :ordered_objects),
         {:ok, _} <- JSON.encoded_result(ordered),
         {:ok, record} <- Jason.decode(json),
         :ok <- validate(record, key) do
      {:ok, record}
    else
      _ -> {:error, :invalid_record}
    end
  end

  def decode(_, _), do: {:error, :invalid_record}

  def validate(record, key) when is_map(record) do
    with {:ok, _} <- key(key),
         true <- exact?(record, @fields),
         true <- record_version?(record) and record["key"] == key_data(key),
         true <- text?(record["record_id"]),
         true <- positive?(record["revision"]),
         true <- timestamp?(record["created_at"]) and timestamp?(record["updated_at"]),
         true <- record["updated_at"] >= record["created_at"],
         {:ok, _} <- execution_snapshot(record["snapshot"], key, record["execution"]),
         true <- execution?(record["execution"]),
         true <- structural_consistent?(record),
         true <- receipts?(record["receipts"], record["revision"]),
         true <-
           record["execution"]["progress"]["runtime"]["frame_version"] in [10, 11] or
             Enum.all?(record["receipts"], fn {_, receipt} -> receipt["state"] != "failed" end),
         true <- ExAgent.Continuation.Retry.authorizations_valid?(record),
         true <- map_size(record["receipts"]) + receipt_reserve(record["execution"]) <= 1024,
         {:ok, normalized} <- JSON.normalize(record),
         true <- normalized === record do
      within_limit(record)
    else
      _ -> {:error, :invalid_record}
    end
  end

  def validate(_, _), do: {:error, :invalid_record}

  defp record_version?(%{"record_version" => 1, "execution" => %{"execution_version" => 1}}),
    do: true

  defp record_version?(%{
         "record_version" => 2,
         "execution" => %{"execution_version" => 2, "kind" => "composition"}
       }),
       do: true

  defp record_version?(_), do: false

  defp structural_consistent?(%{"record_version" => 2} = r),
    do:
      ExAgent.Continuation.StructuralSnapshot.consistent?(r["snapshot"], r["execution"]) and
        (r["execution"]["progress"]["runtime"]["frame_version"] == 4 or
           ExAgent.Continuation.Frame.structural_evidence(r) == :ok)

  defp structural_consistent?(_), do: true

  defp within_limit(record) do
    reserve = cleanup_reserve_bytes(record)
    root = record["execution"]["progress"]["runtime"]

    limit =
      if root["frame_version"] in [10, 11],
        do: min(@max_bytes, root["authority"][root["run_id"]]["checkpoint_limit"]),
        else: @max_bytes

    case Jason.encode(record) do
      {:ok, json} when byte_size(json) + reserve <= limit -> :ok
      {:ok, _} -> {:error, :record_limit}
      _ -> {:error, :invalid_record}
    end
  end

  @doc false
  def cleanup_reserve_bytes(%{
        "execution" => %{
          "state" => "failed",
          "progress" => %{"runtime" => %{"frame_version" => durable_version}}
        }
      })
      when durable_version in [10, 11], do: 0

  def cleanup_reserve_bytes(record) do
    e = record["execution"]
    {exhaustion_success, exhaustion_failed} = exhaustion_bytes10(e)

    cleanup_reserve_base(record) + flow_reserve11(e) + call_fatal_bytes10(e) +
      final_control_bytes10(e) +
      max(
        closure_bytes10(e) + output_bytes10(e) + exhaustion_success,
        failed_closure_bytes10(e) + exhaustion_failed
      )
  end

  defp flow_reserve11(%{"progress" => %{"runtime" => %{"frame_version" => 11} = root}} = e) do
    if e["state"] in ~w(completed failed) do
      0
    else
      ids =
        if root["flow"]["phase"] in ~w(idle selecting),
          do: Enum.map(root["binding"]["steps"], & &1["id"]),
          else: root["flow"]["selected"]

      future =
        Enum.count(ids, fn id ->
          not Enum.any?(root["children"], fn {_, n} ->
            n["link"]["step_id"] == id and n["status"] in ~w(completed failed cancelled)
          end)
        end)

      # These are encoded JSON value bounds, inserted as values once. They are
      # not strings containing JSON and receive no second escaping multiplier.
      # Fatal pointers contain three independently escaped 512-byte host IDs;
      # node/call terminal copies remain in the shared closure reservations.
      root["binding"]["max_result_bytes"] + 2 * 4116 + 256 +
        future * (root["binding"]["max_branch_result_bytes"] + 4116 + 3 * 6 * 512 + 128)
    end
  end

  defp flow_reserve11(_), do: 0

  # Two mutually exclusive terminal paths: successful result/history projections
  # OR structural cancellation/error copies. A failed tree cannot subsequently
  # consume tool/output history. Keep receipts and frontier projections independent
  # of both alternatives; materialized results remain charged in the actual row.
  defp failed_closure_bytes10(
         %{"progress" => %{"runtime" => %{"frame_version" => durable_version} = root}} = e
       )
       when durable_version in [10, 11] do
    if e["state"] in ~w(completed failed) do
      0
    else
      nodes =
        Enum.count(root["children"], fn {_, n} -> n["status"] not in ~w(completed failed) end)

      calls = Enum.reduce(root["tool_batches"], 0, fn {_, b}, n -> n + map_size(b["calls"]) end)
      nodes * (4096 + 16) + calls * 16 + 64
    end
  end

  defp failed_closure_bytes10(_), do: 0

  # A confirmed final control is also copied into the deterministic frontier.
  # Reserve that additional projection before admitting a batch; materialization
  # (including replacement by an earlier, larger error) spends the same slot.
  # Tool/control reservations remain independent and receive no second credit.
  defp call_fatal_bytes10(
         %{"progress" => %{"runtime" => %{"frame_version" => durable_version} = root}} = e
       )
       when durable_version in [10, 11] do
    if e["state"] not in ~w(completed failed) and map_size(root["children"]) > 0 do
      id = String.duplicate(<<1>>, 512)

      largest = %{
        "epoch" => root["frontier"]["epoch"] + 1,
        "state" => "draining",
        "reason" => "fatal",
        "fatal" => %{
          "kind" => "call",
          "run_id" => id,
          "request_id" => id,
          "call_id" => id,
          "error" => nil
        }
      }

      max(
        byte_size(Jason.encode!(largest)) + 4096 - 4 - byte_size(Jason.encode!(root["frontier"])),
        0
      )
    else
      0
    end
  end

  defp call_fatal_bytes10(_), do: 0

  # Only the current response has unmaterialized output slots. Historical entries
  # remain evidence, but their history/result bytes are already in the row.
  defp pending_outputs10(%{
         "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
       })
       when durable_version in [10, 11] do
    Enum.filter(root["output_resolutions"], fn {request, entry} ->
      node = root["children"][entry["run_id"]]
      frame = node["frame"]

      node["status"] != "failed" and frame["model_request_id"] == request and
        frame["cursor"] == "response"
    end)
  end

  defp pending_outputs10(_), do: []

  # Before admitting validation of an exhausted typed response, reserve its
  # attestation and diagnostic history together. Descriptor's existing JSON bound
  # is 65536; runtime reason/1 retains at most4096 term bytes. reason_msg can JSON
  # encode a list before Message encodes it again, hence reserve escaped diagnostic
  # text (not merely4096 raw content bytes). Sibling
  # identities/order are already known from the confirmed response, not guessed.
  # For each alternative A, exhausting node i materializes E_i and retires only
  # its own slot a_i. Any subset may exhaust first, so the compositional bound is
  # A + sum(max(E_i - a_i, 0)), not max(A, sum(E_i)). This is the maximum over
  # all subsets without enumerating them. A sibling's slot is never a credit.
  # Larger trusted inputs still face CAS limits.
  defp exhaustion_bytes10(
         %{"progress" => %{"runtime" => %{"frame_version" => durable_version} = root}} = e
       )
       when durable_version in [10, 11] do
    if e["state"] in ~w(completed failed) do
      {0, 0}
    else
      {:ok, plain} =
        ExAgent.Continuation.Frame.output_fingerprint(%{
          output_mode: :text,
          allow_text_output: true,
          output_object: nil,
          output_tools: []
        })

      Enum.reduce(root["children"], {0, 0}, fn {run, node}, {success, failed_bytes} = bytes ->
        f = node["frame"]

        if node["status"] in ~w(running suspended) and f["cursor"] == "response" and
             f["output_fingerprint"] != plain and
             f["output_retries_used"] == f["limits"]["output_retries"] and
             is_nil(root["output_resolutions"][f["model_request_id"]]) do
          {:ok, history} = ExAgent.Message.from_json(node["snapshot"]["message_history"])
          calls = ExAgent.Message.Response.tool_calls(List.last(history))

          # Any output call can be selected by the descriptor. Reserve the largest
          # candidate; the remaining calls have the existing canonical stub shape.
          descriptor_bytes =
            Enum.find_value(root["output_resolutions"], 65_536, fn {_, entry} ->
              if digest(entry["descriptor"]) == {:ok, f["output_fingerprint"]},
                do: byte_size(Jason.encode!(entry["descriptor"]))
            end)

          largest =
            Enum.map(calls, fn selected ->
              parts = [
                %ExAgent.Message.Part.Retry{
                  tool_name: selected.tool_name,
                  tool_call_id: selected.tool_call_id,
                  content: String.duplicate("\\u0001", 4096)
                }
                | Enum.map(List.delete(calls, selected), fn call ->
                    %ExAgent.Message.Part.ToolReturn{
                      tool_name: call.tool_name,
                      tool_call_id: call.tool_call_id,
                      status: :not_executed,
                      content: "Tool not executed - a final result was already processed."
                    }
                  end)
              ]

              parts = ExAgent.Message.to_json([%ExAgent.Message.Request{parts: parts}])

              entry = %{
                "output_resolution_version" => 1,
                "run_id" => run,
                "request_id" => f["model_request_id"],
                "descriptor" => nil,
                "call_id" => selected.tool_call_id,
                "decision" => "retry",
                "parts" => parts,
                "parts_hash" => String.duplicate("0", 64),
                "result" => nil,
                "result_omitted" => nil
              }

              byte_size(Jason.encode!(%{f["model_request_id"] => entry})) + descriptor_bytes - 4 +
                byte_size(Jason.encode!(parts))
            end)
            |> Enum.max(fn -> 0 end)

          # Charge this node's error and delegated raw/outcome/observation copies
          # independently too: sibling success slots may still dominate the max
          # after this node fails. Its own now-unusable success/cancellation slots
          # may retire, but are not borrowed to pay another node's terminal copies.
          error = ExAgent.Continuation.OutputResolution.exhaustion_error10()
          failed = %{node | "status" => "failed", "error" => error}
          raw = terminal_raw_bytes10(root, failed)
          copies = largest + raw + max(0, byte_size(Jason.encode!(error)) - 4)

          {success + max(0, copies - terminal_success_slot10(root, node)),
           failed_bytes + max(0, copies - (4096 + 16))}
        else
          bytes
        end
      end)
    end
  end

  defp exhaustion_bytes10(_), do: {0, 0}

  defp terminal_success_slot10(root, %{"link" => %{"kind" => "delegate"} = link} = node) do
    batch =
      root["tool_batches"][
        ExAgent.Continuation.ToolEvidence.key(node["parent_run_id"], link["parent_request_id"])
      ]

    closure_call_bytes10(root, batch, link["call_id"], batch["calls"][link["call_id"]])
  end

  defp terminal_success_slot10(_, _), do: 0

  defp terminal_raw_bytes10(_root, %{"link" => %{"kind" => "delegate"}} = node) do
    alias ExAgent.Continuation.ToolEvidence
    link = node["link"]

    {:ok, raw} =
      ToolEvidence.child_raw10(node, %ExAgent.Message.Part.ToolCall{
        tool_name: link["tool_name"],
        tool_call_id: link["call_id"]
      })

    {observation, nil, nil} = ToolEvidence.observe(nil)
    id = ToolEvidence.effect_id(node["parent_run_id"], link["parent_request_id"], link["call_id"])
    # Unlike successful output, failed-child closure retires its whole tool
    # result reserve. Do not credit its raw/outcome bytes against that reserve a
    # second time here. No sibling's result slot participates in this charge.
    byte_size(Jason.encode!(raw)) - 4 +
      byte_size(Jason.encode!(%{link["call_id"] => raw["result"]})) +
      byte_size(Jason.encode!(%{id => observation}))
  end

  defp terminal_raw_bytes10(_, _), do: 0

  defp pending_text10(%{
         "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
       })
       when durable_version in [10, 11] do
    for {_, node} <- root["children"],
        node["status"] in ~w(running suspended cancelled),
        node["frame"]["cursor"] == "response",
        is_nil(root["output_resolutions"][node["frame"]["model_request_id"]]),
        {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"]),
        response = List.last(messages),
        match?(%ExAgent.Message.Response{}, response),
        response.parts != [],
        Enum.all?(response.parts, &match?(%ExAgent.Message.Part.Text{}, &1)),
        do: {node, ExAgent.Message.Response.text(response)}
  end

  defp pending_text10(_), do: []

  defp output_bytes10(e) do
    root = e["progress"]["runtime"]

    text_bytes =
      Enum.reduce(pending_text10(e), 0, fn {node, result}, bytes ->
        bytes + max(0, byte_size(Jason.encode!(result)) - 4) +
          output_raw_bytes10(root, node, result)
      end)

    Enum.reduce(pending_outputs10(e), text_bytes, fn {_, entry}, bytes ->
      # Appending one canonical message to the nonempty encoded history grows its
      # JSON string by less than the encoded singleton string (array/quote overhead).
      history = byte_size(Jason.encode!(entry["parts"]))
      node = root["children"][entry["run_id"]]

      result =
        if entry["decision"] == "succeeded" do
          max(0, byte_size(Jason.encode!(entry["result"])) - 4) +
            max(0, byte_size(Jason.encode!(entry["result_omitted"])) - 4) +
            output_raw_bytes10(root, node, entry["result"])
        else
          0
        end

      bytes + history + result
    end)
  end

  defp output_raw_bytes10(root, %{"link" => %{"kind" => "delegate"}} = node, result) do
    alias ExAgent.Continuation.ToolEvidence
    link = node["link"]

    call = %ExAgent.Message.Part.ToolCall{
      tool_name: link["tool_name"],
      tool_call_id: link["call_id"]
    }

    completed =
      %{node | "status" => "completed", "result" => result}
      |> put_in(["frame", "cursor"], "finish")

    {:ok, raw} = ToolEvidence.child_raw10(completed, call)

    {observation, nil, nil} = ToolEvidence.observe(nil)
    id = ToolEvidence.effect_id(node["parent_run_id"], link["parent_request_id"], link["call_id"])
    limit = root["children"][node["parent_run_id"]]["frame"]["tool_return_bytes"]

    # The existing tool reserve owns raw.result and leaf.outcomes. Charge only
    # their growth ABOVE those two credits, plus actual container/observation
    # bytes. Singleton maps bound punctuation even when a sibling already exists.
    # Never use these credits for history or the child's typed result as well.
    byte_size(Jason.encode!(raw)) - 4 +
      byte_size(Jason.encode!(%{link["call_id"] => raw["result"]})) +
      byte_size(Jason.encode!(%{id => observation})) -
      2 * materialized_result_bytes10(raw["result"], limit)
  end

  defp output_raw_bytes10(_, _, _), do: 0

  defp closure_bytes10(%{
         "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
       })
       when durable_version in [10, 11] do
    Enum.reduce(root["tool_batches"], 0, fn {_, batch}, total ->
      if is_nil(batch["consumption"]) do
        # Four result projections, each bounded by 6*limit under JSON escaping.
        # Credit ONLY bytes already materialized in the three pre-consumption
        # result slots. The final control's share of the fixed metadata allowance
        # is reserved independently of the success/cancellation alternative below.
        # Keep future history, raw-control metadata and cleanup receipts intact.
        Enum.reduce(batch["calls"], total, fn {id, call}, bytes ->
          if call["source"]["kind"] == "child" and
               root["children"][call["source"]["id"]]["status"] == "failed" do
            # A certified exhausted child is already fatal: no parent wrapper or
            # history consumption can start. Its canonical raw/outcomes remain in
            # the actual row; no result slot is lent to a different live call.
            bytes
          else
            bytes + closure_call_bytes10(root, batch, id, call)
          end
        end)
      else
        total
      end
    end)
  end

  defp closure_bytes10(_), do: 0

  defp closure_call_bytes10(root, batch, id, call) do
    limit = root["children"][batch["run_id"]]["frame"]["tool_return_bytes"]

    materialized =
      Enum.sum(
        Enum.map(
          [
            call["raw"]["result"],
            call["result"],
            root["children"][batch["run_id"]]["frame"]["outcomes"][id]
          ],
          &materialized_result_bytes10(&1, limit)
        )
      )

    24 * limit + 16_384 - final_control_limit10() - materialized
  end

  # JSON error <=4096 plus {retry:false,error:...}, replacing null: 4116 bytes.
  # Carve this out of the existing 16384 per-call metadata allowance, rather than
  # charging it twice. It is shared by neither terminal alternative nor another
  # call. Materialization spends only this final slot, never raw or frontier.
  defp final_control_limit10(), do: 4116

  defp final_control_bytes10(%{
         "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
       })
       when durable_version in [10, 11] do
    Enum.reduce(root["tool_batches"], 0, fn {_, batch}, total ->
      if is_nil(batch["consumption"]) do
        Enum.reduce(batch["calls"], total, fn {_, call}, bytes ->
          bytes + final_control_limit10() - max(0, byte_size(Jason.encode!(call["control"])) - 4)
        end)
      else
        total
      end
    end)
  end

  defp final_control_bytes10(_), do: 0

  defp materialized_result_bytes10(bytes, limit) when is_binary(bytes),
    do: min(6 * limit, max(0, byte_size(Jason.encode!(bytes)) - 4))

  defp materialized_result_bytes10(_, _), do: 0

  defp cleanup_reserve_base(record) do
    e = record["execution"]
    steps = receipt_reserve(e)

    if steps == 0 do
      0
    else
      # Each UTF-8 identifier is at most 512 raw bytes, but JSON can expand each
      # byte to six (e.g. U+0001). Bound new operation/actor IDs at that maximum;
      # retained execution IDs are charged at their actual encoded size. Cleanup
      # never claims a new owner, so its receipt's attempt_id is always null.
      id = String.duplicate(<<1>>, 512)

      runtime? = runtime_resolution_pending?(e)

      receipt = %{
        "digest" => String.duplicate("0", 64),
        "revision" => record["revision"] + steps,
        "operation" =>
          if(map_size(tree_children(e)) > 0,
            do: "delegation_outcome",
            else: if(runtime?, do: "finalize_call", else: "reconcile")
          ),
        "actor_id" => id,
        "attempt_id" => nil,
        "continuation_id" => e["continuation_id"],
        "run_id" => e["run_id"],
        "state" => "uncertain"
      }

      # A singleton object bounds entry punctuation even in a nonempty map.
      # 128 further bytes cover a minimal {status, data: null} outcome (including
      # validation_error), running->confirmed, state growth and null owner fields.
      # Counter widths use the cleanup horizon, which cannot grow when one step
      # is consumed; updated_at is bounded to nonnegative signed-64-bit UTC ms.
      outcome_growth =
        if runtime? do
          full = %{
            "status" => "validation_error",
            "data" => %{
              "runtime_outcome_version" => 1,
              "phase" => "final",
              "raw_hash" => String.duplicate("f", 64),
              "result_hash" => String.duplicate("f", 64)
            }
          }

          model = %{
            "status" => "validation_error",
            "data" => %{
              "runtime_model_version" => 1,
              "response_hash" => String.duplicate("f", 64),
              "model_state_hash" => String.duplicate("f", 64),
              "state_available" => true
            }
          }

          max(byte_size(Jason.encode!(full)), byte_size(Jason.encode!(model))) -
            byte_size(Jason.encode!(%{"status" => "validation_error", "data" => nil}))
        else
          0
        end

      per_step =
        byte_size(Jason.encode!(%{id => receipt})) + 128 + outcome_growth +
          byte_size(Integer.to_string(e["fence"] + steps)) +
          byte_size(Integer.to_string(@max_timestamp))

      # A decision also grows its approval by a worst-case escaped actor ID,
      # action and UTC timestamp. Reserve that independently of its receipt.
      decision_growth = Approval.pending_count(e["progress"]) * (6 * 512 + 128)
      steps * per_step + decision_growth
    end
  end

  def execution?(
        %{
          "execution_version" => 2,
          "kind" => "composition",
          "progress" => %{"runtime" => %{"frame_version" => durable_version}}
        } = e
      )
      when durable_version in [10, 11] do
    fields = (@execution_fields -- ~w(request_id model_ref)) ++ ["kind"]

    exact?(e, fields) and Enum.all?(~w(continuation_id run_id), &text?(e[&1])) and
      Enum.all?(~w(definition policy), &reference?(e[&1])) and
      e["state"] in ~w(ready claimed pending uncertain expired completed failed) and
      counter?(e["fence"]) and
      nullable_timestamp?(e["deadline_at"]) and nullable_timestamp?(e["expires_at"]) and
      exact?(
        e["progress"],
        ~w(runtime active_budget) ++
          if(Map.has_key?(e["progress"], "approvals"), do: ["approvals"], else: [])
      ) and
      is_map(e["progress"]["active_budget"]) and Budget.valid?(e["progress"]["active_budget"]) and
      approvals?(e) and effects?(e["effects"]) and owner_fields?(e) and state_consistent?(e) and
      tree_slots?(e) and
      e["run_id"] === e["progress"]["runtime"]["run_id"] and
      e["definition"] === Map.take(e["progress"]["runtime"]["binding"], ~w(id version)) and
      (e["state"] in ~w(claimed completed) or
         Frame.recovered_flow_drain11?(e) or
         (e["state"] in ~w(ready uncertain expired) and
            e["progress"]["runtime"]["frontier"]["state"] == "open") or
         e["progress"]["runtime"]["cursor"] == "empty" or
         e["progress"]["runtime"]["frontier"]["state"] == "quiescent") and
      ExAgent.Continuation.Frame.validate(e["progress"]["runtime"]) == :ok
  rescue
    _ -> false
  end

  def execution?(%{"progress" => %{"runtime" => %{"frame_version" => durable_version}}})
      when durable_version in [10, 11], do: false

  def execution?(%{"execution_version" => 2, "kind" => "composition"} = e) do
    fields = (@execution_fields -- ~w(request_id model_ref)) ++ ["kind"]
    stepped? = get_in(e, ["progress", "runtime", "frame_version"]) in [5, 6, 7, 8, 9]

    progress_fields =
      ~w(runtime active_budget) ++
        if(Map.has_key?(e["progress"] || %{}, "approvals"), do: ["approvals"], else: []) ++
        if(Map.has_key?(e["progress"] || %{}, "outcome_usage_reserve"),
          do: ["outcome_usage_reserve"],
          else: []
        )

    exact?(e, fields) and Enum.all?(~w(continuation_id run_id), &text?(e[&1])) and
      Enum.all?(~w(definition policy), &reference?(e[&1])) and
      e["state"] in if(stepped?,
        do:
          if(e["progress"]["runtime"]["frame_version"] == 9,
            do: ~w(ready claimed pending denied uncertain cancelled expired completed),
            else: ~w(ready claimed uncertain cancelled expired completed)
          ),
        else: ~w(ready claimed cancelled expired)
      ) and counter?(e["fence"]) and
      nullable_timestamp?(e["deadline_at"]) and nullable_timestamp?(e["expires_at"]) and
      exact?(e["progress"], if(stepped?, do: progress_fields, else: ~w(runtime active_budget))) and
      is_map(e["progress"]["active_budget"]) and Budget.valid?(e["progress"]["active_budget"]) and
      approvals?(e) and
      (not Map.has_key?(e["progress"], "approvals") or
         e["progress"]["runtime"]["frame_version"] == 9) and
      ExAgent.Continuation.Frame.validate(e["progress"]["runtime"]) == :ok and
      if(stepped?,
        do:
          effects?(e["effects"]) and ExAgent.Continuation.Retry.valid?(e) and tree_slots?(e) and
            state_consistent?(e),
        else: e["effects"] === %{}
      ) and owner_fields?(e) and
      (e["progress"]["runtime"]["frame_version"] != 9 or
         e["state"] == "completed" == (e["progress"]["runtime"]["cursor"] == "completed"))
  rescue
    _ -> false
  end

  def execution?(e) when is_map(e) do
    exact?(e, @execution_fields) and e["execution_version"] == 1 and
      Enum.all?(~w(continuation_id run_id request_id), &text?(e[&1])) and
      Enum.all?(~w(definition policy model_ref), &reference?(e[&1])) and
      e["state"] in @states and counter?(e["fence"]) and
      nullable_timestamp?(e["deadline_at"]) and nullable_timestamp?(e["expires_at"]) and
      is_map(e["progress"]) and Budget.valid?(e["progress"]["active_budget"]) and
      approvals?(e) and effects?(e["effects"]) and ExAgent.Continuation.Retry.valid?(e) and
      tree_slots?(e) and owner_fields?(e) and
      state_consistent?(e)
  end

  def execution?(_), do: false

  defp owner_fields?(%{"state" => "claimed"} = e),
    do:
      text?(e["owner_id"]) and text?(e["attempt_id"]) and timestamp?(e["lease_until"]) and
        e["fence"] > 0

  defp owner_fields?(e),
    do: is_nil(e["owner_id"]) and is_nil(e["attempt_id"]) and is_nil(e["lease_until"])

  defp effects?(effects) when is_map(effects) and map_size(effects) <= 256 do
    Enum.all?(effects, fn {id, effect} ->
      text?(id) and is_map(effect) and
        exact?(effect, ~w(intent state outcome)) and
        intent?(effect["intent"]) and
        ((effect["state"] == "running" and is_nil(effect["outcome"])) or
           (effect["state"] == "confirmed" and outcome?(effect["outcome"])))
    end)
  end

  defp effects?(_), do: false

  def intent?(intent) when is_map(intent),
    do:
      exact?(intent, ~w(kind call_id payload)) and intent["kind"] in ~w(model tool) and
        text?(intent["call_id"]) and is_map(intent["payload"])

  def intent?(_), do: false

  def outcome?(outcome) when is_map(outcome),
    do:
      exact?(outcome, ~w(status data)) and
        outcome["status"] in ~w(succeeded validation_error denied failed not_executed unknown) and
        (not Outcome.tagged?(outcome["data"]) or Outcome.valid?(outcome["data"])) and
        (not Outcome.model_tagged?(outcome["data"]) or Outcome.model_valid?(outcome["data"]))

  def outcome?(_), do: false

  defp receipts?(receipts, revision) when is_map(receipts) and map_size(receipts) <= 1024 do
    Enum.all?(receipts, fn {id, r} ->
      text?(id) and is_map(r) and
        exact?(r, ~w(digest revision operation actor_id attempt_id continuation_id run_id state)) and
        is_binary(r["digest"]) and byte_size(r["digest"]) == 64 and
        positive?(r["revision"]) and r["revision"] <= revision and
        text?(r["operation"]) and text?(r["actor_id"]) and
        (is_nil(r["attempt_id"]) or text?(r["attempt_id"])) and
        text?(r["continuation_id"]) and text?(r["run_id"]) and r["state"] in ["failed" | @states]
    end)
  end

  defp receipts?(_, _), do: false

  def unresolved?(e),
    do:
      callback_uncertain?(e) or
        Enum.any?(e["effects"], fn {id, effect} ->
          ExAgent.Continuation.Retry.active_uncertain?(e, id, effect)
        end)

  defp callback_uncertain?(%{
         "progress" => %{"runtime" => %{"frame_version" => durable_version} = root}
       })
       when durable_version in [10, 11] do
    (durable_version == 11 and root["flow"]["phase"] in ~w(selecting merging)) or
      Enum.any?(root["tool_batches"], fn {_, batch} ->
        Enum.any?(batch["calls"], fn {_, call} -> call["state"] in ~w(preparing wrapping) end)
      end)
  end

  defp callback_uncertain?(_), do: false

  # Keep room to revoke an owner, reconcile every uncertain intent and close the
  # record. Admission must not use the receipts needed to save known outcomes.
  def receipt_reserve(%{"state" => state}) when state in ~w(completed denied expired cancelled),
    do: 0

  def receipt_reserve(%{
        "state" => "failed",
        "progress" => %{"runtime" => %{"frame_version" => durable_version}}
      })
      when durable_version in [10, 11], do: 0

  def receipt_reserve(e) do
    pending =
      Enum.reduce(e["effects"], 0, fn {id, effect}, count ->
        unresolved = ExAgent.Continuation.Retry.active_uncertain?(e, id, effect)

        raw_or_future =
          not ExAgent.Continuation.Retry.retired?(e, id) and runtime_effect?(effect) and
            (effect["state"] == "running" or effect["outcome"]["data"]["phase"] == "raw")

        count + if(unresolved, do: 1, else: 0) + if(raw_or_future, do: 1, else: 0)
      end)

    pending + tool_control_receipts(e) + tree_receipts(e) + flow_receipts11(e) +
      length(pending_outputs10(e)) +
      length(pending_text10(e)) +
      ExAgent.Continuation.Retry.pending_receipts(e) + 1 +
      if(e["state"] == "claimed", do: 1, else: 0) +
      Approval.pending_count(e["progress"])
  end

  defp flow_receipts11(%{"progress" => %{"runtime" => %{"frame_version" => 11} = root}}) do
    # Selection and merge each have an admission and a result ACK. Terminal
    # closure's receipt is already in the common pool; branch-failure closure
    # consumes one additional receipt per unresolved branch, never a sibling's.
    phases =
      case root["flow"]["phase"] do
        "idle" -> 3
        "selecting" -> 2
        "running" -> 1
        _ -> 0
      end

    unresolved =
      Enum.count(root["children"], fn {_, node} ->
        node["link"]["kind"] == "step" and node["status"] not in ~w(completed failed cancelled)
      end)

    phases + unresolved
  end

  defp flow_receipts11(_), do: 0

  defp runtime_effect?(effect),
    do:
      effect["intent"]["kind"] == "tool" and
        (effect["intent"]["payload"]["phase"] == "dispatch" or
           Outcome.tagged?(effect["outcome"]["data"]))

  defp tool_control_receipts(
         %{"progress" => %{"runtime" => %{"frame_version" => durable_version} = root}} = e
       )
       when durable_version in [10, 11] do
    # Effect-backed settlements spend their raw_or_future receipt in
    # receipt_reserve/1. Child/host sources have no such effect: spend exactly one
    # of their own eight control receipts when the final becomes materialized.
    # A confirmed batch resolution similarly spends one of its two receipts.
    # Consumed batches already release the whole pool; never credit them again.
    materialized =
      Enum.reduce(root["tool_batches"], 0, fn {_, batch}, total ->
        total +
          if is_nil(batch["consumption"]) do
            Enum.count(batch["calls"], fn {_, call} ->
              call["state"] == "settled" and call["source"]["kind"] != "effect"
            end) + if(is_nil(batch["resolution"]), do: 0, else: 1)
          else
            0
          end
      end)

    ExAgent.Continuation.ToolEvidence.pending_receipts(e) - materialized
  end

  defp tool_control_receipts(e) do
    ExAgent.Continuation.ToolEvidence.pending_receipts(e)
  end

  defp runtime_resolution_pending?(e),
    do:
      tree_receipts(e) > 0 or
        Enum.any?(e["effects"], fn {_, effect} ->
          (runtime_effect?(effect) or effect["intent"]["payload"]["phase"] == "model_dispatch") and
            (effect["state"] == "running" or effect["outcome"]["data"]["phase"] == "raw")
        end)

  defp tree_children(e) do
    case get_in(e, ["progress", "runtime"]) do
      %{"frame_version" => version, "children" => children}
      when version in [2, 3, 5, 6, 7, 8, 9, 10, 11] and is_map(children) ->
        children

      _ ->
        %{}
    end
  end

  defp tree_receipts(e) do
    Enum.reduce(tree_children(e), 0, fn {_, child}, n ->
      n +
        cond do
          child["status"] == "failed" and e["progress"]["runtime"]["frame_version"] in [10, 11] ->
            2

          child["status"] != "completed" ->
            3

          is_nil(child["outcome"]) ->
            2

          child["outcome"]["data"]["phase"] == "raw" ->
            1

          true ->
            0
        end
    end)
  end

  defp tree_slots?(e) do
    children = tree_children(e)

    unstarted =
      Enum.count(children, fn {id, _} ->
        not Enum.any?(e["effects"], fn {_, effect} ->
          effect["intent"]["kind"] == "model" and effect["intent"]["payload"]["run_id"] == id
        end)
      end)

    map_size(children) <= 256 and
      map_size(e["effects"]) + unstarted + ExAgent.Continuation.Retry.pending_slots(e) <= 256
  end

  defp approvals?(e) do
    case Map.fetch(e["progress"], "approvals") do
      :error ->
        e["state"] not in ~w(pending denied)

      {:ok, approvals} ->
        Approval.collection?(approvals) and
          case e["state"] do
            "pending" ->
              Approval.pending_count(e["progress"]) > 0

            "denied" ->
              Enum.any?(approvals, fn {_, a} -> a["decision"]["action"] == "deny" end)

            state when state in ~w(ready claimed completed) ->
              Enum.all?(approvals, fn {_, a} -> Approval.approved?(a) end)

            _ ->
              true
          end
    end
  end

  defp state_consistent?(%{"state" => "uncertain"} = e), do: unresolved?(e)

  defp state_consistent?(%{"state" => "claimed"} = e),
    do:
      not Enum.any?(e["effects"], fn {id, effect} ->
        effect["outcome"]["status"] == "unknown" and
          not ExAgent.Continuation.Retry.retired?(e, id)
      end)

  defp state_consistent?(e), do: not unresolved?(e)

  def reference?(r) when is_map(r),
    do: exact?(r, ~w(id version)) and text?(r["id"]) and text?(r["version"])

  def reference?(_), do: false
  def exact?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  def text?(value), do: is_binary(value) and byte_size(value) in 1..512 and String.valid?(value)
  def counter?(value), do: is_integer(value) and value >= 0
  def positive?(value), do: is_integer(value) and value > 0
  def timestamp?(value), do: is_integer(value) and value >= 0 and value <= @max_timestamp
  def nullable_timestamp?(value), do: is_nil(value) or timestamp?(value)

  @doc "Canonical JSON v1: sorted UTF-8 object keys; array order and 1 versus 1.0 preserved."
  def canonical(value) do
    # normalize already rejects colliding keys and non-JSON/invalid UTF-8 data.
    # Ordering that plain JSON tree cannot introduce duplicate object keys.
    with {:ok, value} <- JSON.normalize(value) do
      Jason.encode(ordered(value), maps: :strict)
    end
  end

  def digest(value) do
    with {:ok, bytes} <- canonical(value),
         do: {:ok, Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}
  end

  defp ordered(map) when is_map(map),
    do: %Jason.OrderedObject{
      values: map |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {k, v} -> {k, ordered(v)} end)
    }

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(value), do: value
end
