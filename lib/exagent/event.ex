defmodule ExAgent.Event do
  @moduledoc """
  Versioned, serializable event envelope — ExAgent's UI/runtime contract.

  `ExAgent.Event` is what LiveView, CLI frontends, channels, product logs and
  flow tests subscribe to. It is deliberately distinct from `:telemetry`, which
  stays the channel for technical observability (metrics, OTel, dashboards) and
  may be emitted in parallel.

  Events flow through `ExAgent.PubSub`. A subscriber receives messages shaped as
  `{:exagent_event, %ExAgent.Event{}}` on topics such as
  `"exagent:agent:<agent_id>"` (see `agent_topic/1`) and
  `"exagent:session:<session_id>"` (see `session_topic/1`).

  ## Fields

    * `version`     — envelope schema version (currently `1`).
    * `id`          — unique event id (`"evt_..."`).
    * `seq`         — monotonic within one emitter incarnation, not durable.
    * `type`        — one of the event types listed below.
    * `source`      — `:run`, `:server`, `:session`, `:coordination`, …
    * `occurred_at` — `DateTime.utc_now/0` at emission.
    * correlation   — `run_id`, `request_id`, `agent_id`, `session_id`,
                       `participant_id` (any may be `nil`).
    * `namespace`   — trusted application consumer scope; nil for legacy.
                      Logical conversation/participant IDs are local to it.
    * `payload`     — JSON-encodable map with event-specific data.
    * `metadata`    — free-form, JSON-encodable map.

  ## Event types

  Loop / run:

      :run_started · :run_finished · :run_failed
      :run_step_started · :run_step_finished
      :text_delta · :thinking_delta
      :tool_call_started · :tool_call_finished
      :usage_updated

  Server runtime:

      :server_request_queued · :server_request_cancelled
      :approval_requested

  Session / coordination (Phase 3+):

      :session_started · :participant_joined · :participant_left
      :session_turn_changed · :shared_state_updated · :session_closed

  Compaction (Phase 5):

      :compaction_started · :compaction_finished
  """

  @derive {Jason.Encoder,
           only: [
             :version,
             :emitter_id,
             :namespace,
             :id,
             :seq,
             :type,
             :source,
             :occurred_at,
             :run_id,
             :request_id,
             :agent_id,
             :session_id,
             :participant_id,
             :payload,
             :metadata
           ]}

  @enforce_keys [:id, :seq, :type, :occurred_at]
  defstruct version: 1,
            namespace: nil,
            emitter_id: nil,
            id: nil,
            seq: nil,
            type: nil,
            source: nil,
            occurred_at: nil,
            run_id: nil,
            request_id: nil,
            agent_id: nil,
            session_id: nil,
            participant_id: nil,
            payload: %{},
            metadata: %{}

  @type source :: :run | :server | :session | :coordination | atom()
  @type t :: %__MODULE__{
          version: pos_integer(),
          namespace: String.t() | nil,
          emitter_id: String.t() | nil,
          id: String.t(),
          seq: non_neg_integer(),
          type: atom(),
          source: source() | nil,
          occurred_at: DateTime.t(),
          run_id: String.t() | nil,
          request_id: String.t() | nil,
          agent_id: String.t() | nil,
          session_id: String.t() | nil,
          participant_id: String.t() | nil,
          payload: map(),
          metadata: map()
        }

  @doc """
  Build a new event, filling `id`/`occurred_at`/`version` defaults.

  `:type` and `:seq` are required (enforced); everything else is optional with
  sensible defaults. `payload`/`metadata` default to empty maps.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    opts =
      opts
      |> Keyword.put_new_lazy(:id, &generate_id/0)
      |> Keyword.put_new_lazy(:occurred_at, &DateTime.utc_now/0)
      |> Keyword.put_new(:version, 1)
      |> Keyword.put_new(:payload, %{})
      |> Keyword.put_new(:metadata, %{})

    struct!(__MODULE__, opts)
  end

  @doc "Recommended PubSub topic for an agent (`\"exagent:agent:<id>\"`)."
  @spec agent_topic(String.t() | nil) :: String.t()
  def agent_topic(nil), do: "exagent:agent"
  def agent_topic(agent_id), do: "exagent:agent:#{agent_id}"

  @doc "Agent topic scoped by a trusted application namespace; nil preserves the legacy topic."
  def agent_topic(agent_id, namespace), do: scoped_topic(:agent, agent_id, namespace)

  @doc "Recommended PubSub topic for a session (`\"exagent:session:<id>\"`)."
  @spec session_topic(String.t() | nil) :: String.t()
  def session_topic(nil), do: "exagent:session"
  def session_topic(session_id), do: "exagent:session:#{session_id}"

  @doc "Session topic scoped by a trusted application namespace; nil preserves the legacy topic."
  def session_topic(session_id, namespace), do: scoped_topic(:session, session_id, namespace)

  defp scoped_topic(kind, id, namespace) do
    case ExAgent.RuntimeIdentity.key(namespace, kind, id) do
      {:ok, key} -> "exagent:#{kind}:#{key}"
      {:error, reason} -> raise ArgumentError, "invalid topic identity: #{reason}"
    end
  end

  @doc "JSON projection of a result; deliberately excludes the live model."
  def result_payload(result) when is_map(result) do
    %{
      output: json_value(Map.get(result, :output)),
      output_kind: if(is_binary(Map.get(result, :output)), do: :text, else: :structured),
      output_text: if(is_binary(Map.get(result, :output)), do: result.output, else: nil),
      messages: messages_value(Map.get(result, :messages, [])),
      new_messages: messages_value(Map.get(result, :new_messages, [])),
      pending_response: response_value(Map.get(result, :pending_response)),
      usage: usage_value(Map.get(result, :usage)),
      run_id: Map.get(result, :run_id),
      status: Map.get(result, :status),
      usage_status: Map.get(result, :usage_status),
      run_step: Map.get(result, :run_step),
      steps: Map.get(result, :run_step)
    }
    |> Map.merge(result_metadata(result))
    |> continuation_payload(result)
    |> retention_payload(result)
  end

  defp retention_payload(payload, %{
         retention: %{version: 1, measurement: :erlang_external_term} = retention
       }) do
    keys = [
      :data_bytes,
      :history_bytes,
      :max_history_bytes,
      :max_payload_bytes,
      :control_reserve_bytes
    ]

    if Enum.all?(keys, &(is_integer(retention[&1]) and retention[&1] >= 0)),
      do: Map.put(payload, :retention, Map.take(retention, [:version, :measurement | keys])),
      else: payload
  end

  defp retention_payload(payload, _), do: payload

  @doc false
  def continuation_reference(ref) when is_map(ref) do
    required = [:id, :record_id, :run_id]

    if ref[:version] == 1 and is_integer(ref[:revision]) and ref.revision > 0 and
         Enum.all?(required, &ExAgent.Continuation.Record.text?(ref[&1])) and
         (is_nil(ref[:attempt_id]) or ExAgent.Continuation.Record.text?(ref[:attempt_id])) do
      Map.take(ref, [:version, :id, :record_id, :run_id, :revision, :attempt_id])
    end
  end

  def continuation_reference(_), do: nil

  defp continuation_payload(payload, result) do
    case continuation_reference(result[:continuation]) do
      nil -> payload
      ref -> Map.put(payload, :continuation, ref)
    end
  end

  # Explicit C4 scalar allowlist: scope/model and arbitrary runtime terms stay out.
  defp result_metadata(result) do
    Enum.reduce(
      [
        :root_run_id,
        :parent_run_id,
        :model_request_id,
        :attempt_id,
        :request_count,
        :tool_calls,
        :cost_cents,
        :cost_status
      ],
      %{},
      fn key, acc ->
        case Map.fetch(result, key) do
          {:ok, value} ->
            if valid_result_metadata?(key, value), do: Map.put(acc, key, value), else: acc

          :error ->
            acc
        end
      end
    )
  end

  defp valid_result_metadata?(:root_run_id, value), do: is_binary(value)
  defp valid_result_metadata?(:attempt_id, value), do: is_binary(value)

  defp valid_result_metadata?(key, value)
       when key in [:parent_run_id, :model_request_id],
       do: is_binary(value) or is_nil(value)

  defp valid_result_metadata?(key, value) when key in [:request_count, :tool_calls],
    do: is_integer(value) and value >= 0

  defp valid_result_metadata?(:cost_cents, value),
    do: is_nil(value) or (is_number(value) and value >= 0)

  defp valid_result_metadata?(:cost_status, value), do: value in [:known, :unknown]

  @doc "Structural error projection, never a dump of live runtime structs."
  def error_payload(%ExAgent.CheckpointError{} = error) do
    %{
      type: :checkpoint,
      operation: error.operation,
      reason: reason_payload(error.reason),
      revision: error.revision,
      result: outcome_payload(error.result)
    }
  end

  def error_payload(%{__struct__: ExAgent.RunError, reason: reason, partial: partial}),
    do: %{type: :run, reason: reason_payload(reason), partial: result_payload(partial)}

  def error_payload(reason), do: %{type: :runtime, reason: reason_payload(reason)}

  defp outcome_payload({:ok, result}) when is_map(result),
    do: %{status: :ok, result: result_payload(result)}

  defp outcome_payload({:error, reason}), do: %{status: :error, error: error_payload(reason)}
  defp outcome_payload(_), do: %{status: :applied}

  defp reason_payload(reason), do: ExAgent.ErrorProjection.reason(reason)

  defp messages_value(messages) do
    messages |> ExAgent.Message.to_json() |> Jason.decode!()
  rescue
    _ -> nil
  end

  defp response_value(nil), do: nil

  defp response_value(response) do
    case messages_value([response]) do
      [data] -> data
      _ -> nil
    end
  end

  defp usage_value(nil), do: nil

  defp usage_value(usage) do
    ExAgent.SnapshotData.usage_map(usage)
  rescue
    _ -> nil
  end

  defp json_value(value) do
    ExAgent.SnapshotData.json(value)
  rescue
    _ -> %{serialization_error: true}
  end

  @doc false
  def generate_id do
    "evt_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
