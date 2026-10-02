defmodule ExAgent.Continuation do
  @moduledoc """
  Administrative queries and host-authorized decisions for atomic records.

  Runtime pause/resume integration is separate. The host authorizes commands and
  owns templates, policies, credentials and effect dispatch. A Store receipt says
  a data transition committed, not that an external effect ran exactly once.
  """
  alias ExAgent.Store
  alias ExAgent.Continuation.Record

  @doc """
  Read one agent continuation from the trusted scoped Store, independently of its
  former runtime process. Returns data only, including the current record/revision.
  This query never authorizes execution or resolves executable configuration.
  """
  def get(store, id) do
    with {:ok, record} <- Store.load_record(store, :agent, id) do
      {:ok,
       %{
         status: status(record),
         record: record,
         retryable_effects: ExAgent.Continuation.Retry.bindings(record),
         historical_uncertainty: ExAgent.Continuation.Retry.summary(record["execution"])
       }}
    end
  end

  @doc """
  Persist an `:approve`, `:deny`, `:cancel` or `:expire` decision without executing IO
  on behalf of the agent. Deny terminates the pending execution, retaining effects.

  Required options are `:record_id`, `:revision`, `:operation_id`, `:actor` and
  `:authorize`. Approve/deny also require `:approval_id` and `:payload_hash`.
  The trusted `authorize.(actor, decision, target)` must return `{:ok, actor_id}`;
  all other returns and exceptions deny. Only that bounded string actor ID is
  persisted, never the actor context or callback. Target contains the current
  data record and exact requested binding; applications enforce tenant/business
  authorization here, not through model text.

  Reuse all binding options and operation ID to retry a lost ACK. A receipt proves
  the earlier transition committed, not permission for new model/tool effects.
  Opposite decisions and changed bindings cannot reuse an operation ID.
  """
  def decide(store, id, decision, opts) when is_list(opts) do
    with {:ok, operation, payload} <- decision_payload(decision, opts),
         true <- Record.text?(opts[:record_id]) and Record.text?(opts[:operation_id]),
         true <- Record.positive?(opts[:revision]) and Keyword.has_key?(opts, :actor),
         {:ok, record} <- Store.load_record(store, :agent, id),
         {:ok, actor_id} <-
           authorize(opts, decision, %{
             record: record,
             record_id: opts[:record_id],
             revision: opts[:revision],
             operation_id: opts[:operation_id],
             payload: payload
           }) do
      command = %{
        "record_id" => opts[:record_id],
        "operation_id" => opts[:operation_id],
        "operation" => operation,
        "actor_id" => actor_id,
        "payload" => payload
      }

      Store.transition(store, :agent, id, opts[:revision], command)
    else
      false -> {:error, :invalid_decision}
      {:error, _} = error -> error
    end
  end

  def decide(_, _, _, _), do: {:error, :invalid_decision}

  @doc """
  Retry only the exact data transition from a failed runtime checkpoint. Store
  configuration is supplied separately and never appears in the data-only token.
  A committed/replayed claim or effect-intent receipt does not authorize dispatch;
  inspect/recover the current record explicitly before requesting a new resume.
  """
  def retry_checkpoint(store, token) do
    with true <- Record.exact?(token, ~w(token_version namespace id expected_revision command)),
         true <- token["token_version"] == 1 and token["namespace"] == store.namespace,
         true <- ExAgent.Retention.bytes(token) <= Record.max_bytes(),
         expected =
           if(token["expected_revision"] == "absent",
             do: :absent,
             else: token["expected_revision"]
           ),
         true <- expected == :absent or Record.positive?(expected) do
      Store.transition(store, :agent, token["id"], expected, token["command"])
    else
      _ -> {:error, :invalid_checkpoint_token}
    end
  rescue
    _ -> {:error, :invalid_checkpoint_token}
  end

  @doc "Revoke an expired claim; unresolved effect intents become uncertain, never automatic retries."
  def recover(store, id, opts),
    do: administrative(store, id, :recover, opts, fn _ -> {:ok, %{}} end)

  @doc """
  Reconcile one uncertain tool effect using a host-confirmed outcome. The host must
  obtain the real external result (or prove non-execution); this API performs no
  external IO and does not roll back or retry the tool. Model recovery requires its
  explicit model-state/frame evidence and is not inferred from a tool outcome.
  Options use the same lifetime/revision/operation/actor/authorize binding as decide.
  """
  def reconcile(store, id, effect_id, outcome, opts) do
    administrative(store, id, :reconcile, opts, fn record ->
      effect = record["execution"]["effects"][effect_id]

      with %{"intent" => %{"kind" => "tool", "call_id" => call_id, "payload" => intent}} <- effect,
           false <- ExAgent.Continuation.Retry.retired?(record["execution"], effect_id),
           true <- Record.outcome?(outcome) and outcome["status"] != "unknown",
           {:ok, value} <- ExAgent.Tool.JSON.normalize(outcome["data"]),
           status when not is_nil(status) <-
             Enum.find(
               [:succeeded, :validation_error, :denied, :failed, :not_executed],
               &(Atom.to_string(&1) == outcome["status"])
             ) do
        part = %ExAgent.Message.Part.ToolReturn{
          tool_name: intent["tool_name"],
          tool_call_id: call_id,
          status: status,
          content: value
        }

        progress = record["execution"]["progress"]
        runtime = progress["runtime"]
        run_id = Map.get(intent, "run_id", runtime["run_id"])

        frame =
          ExAgent.Continuation.Frame.put_node(
            runtime,
            run_id,
            ExAgent.Continuation.Frame.put_outcome(
              ExAgent.Continuation.Frame.node(runtime, run_id),
              part
            )
          )

        {:ok, stored_outcome} = ExAgent.Continuation.Outcome.new(part, "final")

        {:ok,
         %{
           "effect_id" => effect_id,
           "outcome" => stored_outcome,
           "snapshot" => record["snapshot"],
           "progress" => Map.put(progress, "runtime", frame)
         }}
      else
        _ -> {:error, :invalid_reconciliation}
      end
    end)
  end

  defp administrative(store, id, operation, opts, payload) do
    with true <-
           is_list(opts) and Record.text?(opts[:record_id]) and Record.text?(opts[:operation_id]),
         true <- Record.positive?(opts[:revision]) and Keyword.has_key?(opts, :actor),
         {:ok, record} <- Store.load_record(store, :agent, id),
         {:ok, payload} <- payload.(record),
         {:ok, actor_id} <-
           authorize(opts, operation, %{
             record: record,
             record_id: opts[:record_id],
             revision: opts[:revision],
             operation_id: opts[:operation_id],
             payload: payload
           }) do
      Store.transition(store, :agent, id, opts[:revision], %{
        "record_id" => opts[:record_id],
        "operation_id" => opts[:operation_id],
        "operation" => Atom.to_string(operation),
        "actor_id" => actor_id,
        "payload" => payload
      })
    else
      false -> {:error, :invalid_decision}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :invalid_reconciliation}
  end

  @doc """
  Reconcile an uncertain Model request with host-confirmed effective (post-hook)
  response and portable model data. Evidence is `%{response: response,
  model_data: data}`; optional `:accounting` supplies already-qualified Usage maps
  for the exact ancestor IDs. Existing confirmed accounting is never repriced.

  In addition to the administrative actor/revision/authorize options, pass the
  trusted target `:agent` and its `:continuation` references/model codec. For a
  child this is that child's host definition, not code selected from stored data.
  Validation uses Model's no-IO resume preflight and the current output profile.
  No Model request or after-model hook is executed by this operation.
  """
  def reconcile_model(store, id, effect_id, evidence, opts) when is_list(opts) do
    config = opts[:continuation]

    if is_map(config) do
      config = config |> Map.put(:store, store) |> Map.put(:id, id)
      opts = Keyword.put(opts, :continuation, config)

      administrative(store, id, :reconcile_model, opts, fn record ->
        ExAgent.Continuation.ModelRecovery.payload(record, effect_id, evidence, opts)
      end)
    else
      {:error, :invalid_model_reconciliation}
    end
  end

  def reconcile_model(_, _, _, _, _), do: {:error, :invalid_model_reconciliation}

  @doc """
  Explicitly accept the risk of duplicating one uncertain effect and authorize a
  new linked attempt. Pass a binding returned in `get/2`'s `:retryable_effects` and
  the usual operation/actor/authorize options, plus `accept_duplicate_risk: true`
  and a nonsecret visible-ASCII `:idempotency_key` (at most512 bytes).

  This only records the decision; resume still needs a new claim and intent ACK.
  The original intent/outcome stays literally uncertain in historical evidence.
  A key's delivery to the tool context or Model callback/provider is not a claim
  that the external service deduplicates it, especially if the first call had no
  key. Context-free tools and unsupported Model transports reject retry before IO.
  """
  def retry_effect(store, id, binding, opts) when is_map(binding) and is_list(opts) do
    with {:ok, data} <- ExAgent.Tool.JSON.normalize(binding) do
      opts =
        opts
        |> Keyword.put(:record_id, data["record_id"])
        |> Keyword.put(:revision, data["revision"])

      administrative(store, id, :retry_effect, opts, fn record ->
        ExAgent.Continuation.Retry.command_payload(
          record,
          data,
          opts[:idempotency_key],
          opts[:operation_id],
          opts[:accept_duplicate_risk]
        )
      end)
    end
  end

  def retry_effect(_, _, _, _), do: {:error, :invalid_effect_retry}

  @doc """
  Explicitly allow later deletion/replacement of an exact terminal run's retained
  historical uncertainty. Requires administrative bindings/authorization, the
  `:evidence_hash` from `get/2` and `allow_evidence_deletion: true`. This is not an
  assertion that the old external effect was reconciled and does not delete data.
  Without it, start/prune cannot silently discard evidence retired by a retry.
  """
  def acknowledge_history(store, id, opts) do
    administrative(store, id, :acknowledge_history, opts, fn _ ->
      {:ok,
       %{
         "evidence_hash" => opts[:evidence_hash],
         "allow_evidence_deletion" => opts[:allow_evidence_deletion]
       }}
    end)
  end

  defp decision_payload(decision, opts) when decision in [:approve, :deny] do
    if Record.text?(opts[:approval_id]) and Record.text?(opts[:payload_hash]) do
      {:ok, "decide",
       %{
         "approval_id" => opts[:approval_id],
         "payload_hash" => opts[:payload_hash],
         "decision" => Atom.to_string(decision)
       }}
    else
      {:error, :invalid_decision}
    end
  end

  defp decision_payload(decision, _) when decision in [:cancel, :expire],
    do: {:ok, Atom.to_string(decision), %{}}

  defp decision_payload(_, _), do: {:error, :invalid_decision}

  defp authorize(opts, decision, target) do
    case opts[:authorize] do
      fun when is_function(fun, 3) ->
        case fun.(opts[:actor], decision, target) do
          {:ok, actor_id} ->
            if Record.text?(actor_id), do: {:ok, actor_id}, else: {:error, :unauthorized}

          _ ->
            {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  rescue
    _ -> {:error, :unauthorized}
  catch
    _, _ -> {:error, :unauthorized}
  end

  defp status(%{"execution" => %{"state" => "claimed", "effects" => effects} = execution}) do
    if Enum.any?(effects, fn {id, e} ->
         ExAgent.Continuation.Retry.active_uncertain?(execution, id, e)
       end),
       do: :executing,
       else: :claimed
  end

  defp status(%{"execution" => %{"state" => "ready", "progress" => progress}}),
    do: if(Map.has_key?(progress, "approvals"), do: :approved, else: :ready)

  defp status(%{"execution" => %{"state" => state}}),
    do:
      Enum.find(
        [:pending, :uncertain, :completed, :failed, :denied, :expired, :cancelled],
        &(Atom.to_string(&1) == state)
      )

  @doc """
  Delete eligible terminal records from one bounded page in the trusted namespace.
  Returns deleted and retained/conflicted identities plus the next scan cursor.
  Active/uncertain records are never deleted. Stop admissions and writers before
  using this for namespace removal; this is not a namespace-wide atomic operation.
  `before` is an exclusive UTC-millisecond retention cutoff. Actor is host supplied.
  """
  def prune_page(store, before, actor_id, query \\ %{}) do
    with true <-
           ExAgent.Continuation.Record.timestamp?(before) and
             ExAgent.Continuation.Record.text?(actor_id),
         {:ok, page} <- Store.scan_records(store, query) do
      results =
        Enum.map(page.records, fn record ->
          [_, kind, id] = record["key"]
          kind = Enum.find([:agent, :session], &(Atom.to_string(&1) == kind))

          command = %{
            "record_id" => record["record_id"],
            "operation" => "delete",
            "operation_id" => "delete-#{record["revision"]}",
            "actor_id" => actor_id,
            "payload" => %{"before" => before}
          }

          {record["key"], Store.transition(store, kind, id, record["revision"], command)}
        end)

      {:ok, %{results: results, cursor: page.cursor}}
    else
      false -> {:error, :invalid_retention}
      {:error, _} = error -> error
    end
  end
end
