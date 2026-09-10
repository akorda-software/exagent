defmodule ExAgent.RuntimeCheckpoint do
  @moduledoc false
  require Logger
  alias ExAgent.{CheckpointError, Event, Store}
  alias ExAgent.Observability.OpenTelemetry, as: Observability

  def commit(state, operation, result, snapshot_fun, trace_opts \\ []) do
    state = %{state | revision: state.revision + 1}
    save(state, operation, result, snapshot_fun, trace_opts)
  end

  def retry(%{checkpoint_error: nil} = state, _snapshot_fun), do: {:ok, state}

  def retry(%{checkpoint_error: error} = state, snapshot_fun) do
    case save(state, error.operation, error.result, snapshot_fun, []) do
      {_result, %{checkpoint_error: nil} = state} -> {:ok, state}
      {result, state} -> {result, state}
    end
  end

  def blocked(state), do: {:error, state.checkpoint_error}

  def health(state) do
    %{
      status:
        cond do
          is_nil(state.store) -> :disabled
          is_nil(state.checkpoint_error) -> :confirmed
          true -> :unconfirmed
        end,
      revision: state.revision,
      error:
        if(state.checkpoint_error,
          do:
            state.checkpoint_error
            |> Event.error_payload()
            |> Map.take([:type, :operation, :reason, :revision]),
          else: nil
        )
    }
  end

  defp save(%{store: nil} = state, _operation, result, _snapshot_fun, _trace_opts),
    do: {result, %{state | checkpoint_error: nil}}

  defp save(state, operation, result, snapshot_fun, trace_opts) do
    config = Observability.configuration(Map.get(state, :observability), trace_opts)

    attrs =
      Observability.ids(state)
      |> Map.merge(%{
        "exagent.checkpoint.operation" => Atom.to_string(operation),
        "exagent.checkpoint.revision" => state.revision,
        "exagent.checkpoint.retry" => state.checkpoint_error != nil
      })

    outcome =
      Observability.around(config, :checkpoint, attrs, trace_opts[:trace_context], fn _span ->
        Store.protect(
          fn ->
            snapshot = snapshot_fun.(state)

            case operation do
              :agent -> Store.save_agent_snapshot(state.store, snapshot)
              :session -> Store.save_session_snapshot(state.store, snapshot)
            end
          end,
          :save
        )
      end)

    case outcome do
      :ok ->
        {result, %{state | checkpoint_error: nil}}

      {:error, reason} ->
        error = %CheckpointError{
          operation: operation,
          reason: reason,
          result: result,
          revision: state.revision
        }

        Logger.warning("exagent checkpoint failed",
          operation: operation,
          revision: state.revision,
          reason: inspect(ExAgent.ErrorProjection.diagnostic(reason))
        )

        {{:error, error}, %{state | checkpoint_error: error}}
    end
  end
end
