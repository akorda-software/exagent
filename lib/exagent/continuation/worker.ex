defmodule ExAgent.Continuation.Worker do
  @moduledoc false
  alias ExAgent.{ExecutionScope, Retention}
  alias ExAgent.Continuation.Writer

  # Registration precedes callbacks, including observability and resolver/codec
  # work inside a delegated call. Only a result ACK AND the exact monitored DOWN
  # retire a worker. Guardians are owned here and drained before publishing done.
  def run(%{continuation_version: durable_version} = run, role, call_id, fun)
      when durable_version in [10, 11] do
    with {:ok, identity} <- Writer.worker_begin(run.continuation, run, role, call_id),
         {:ok, guardian} <- ExecutionScope.watch_worker(run.execution_scope) do
      monitor = Process.monitor(guardian)

      result =
        try do
          fun.()
        after
          send(guardian, :finished)

          receive do
            {:DOWN, ^monitor, :process, ^guardian, _} -> :ok
          end
        end

      case Writer.worker_done(run.continuation, identity) do
        :ok -> result
        {:error, reason} -> exit(Retention.reason(reason))
      end
    else
      {:error, reason} -> exit(Retention.reason(reason))
    end
  end

  def run(_, _, _, fun), do: fun.()
end
