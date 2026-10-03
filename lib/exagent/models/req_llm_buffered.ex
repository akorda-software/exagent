defmodule ExAgent.Models.ReqLLMBuffered do
  @moduledoc false
  alias ExAgent.Observability.OpenTelemetry

  # Own the operation, not ReqLLM internals. A linked worker waits until both
  # monitors exist and the caller acknowledges readiness; the guardian survives
  # caller death long enough to kill and reap that worker.
  def run(fun, timeout) do
    timeout = timeout || Application.get_env(:req_llm, :total_timeout, :infinity)

    unless timeout == :infinity or (is_integer(timeout) and timeout > 0),
      do: fail!({:invalid_option, :total_timeout})

    deadline = if timeout == :infinity, do: :infinity, else: now() + timeout
    context = OpenTelemetry.capture_context()
    owner = self()
    ref = make_ref()

    {guardian, monitor} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, true)
        owner_monitor = Process.monitor(owner)
        guardian = self()

        worker =
          spawn_link(fn ->
            receive do
              {^ref, :start} ->
                result =
                  try do
                    {:value, OpenTelemetry.with_context(context, fun)}
                  catch
                    _, _ -> :failed
                  end

                send(guardian, {ref, :result, result, now()})
            end
          end)

        send(owner, {ref, :ready})
        guard(owner, owner_monitor, worker, ref, deadline, :waiting, nil)
      end)

    receive do
      {^ref, :ready} ->
        send(guardian, {ref, :start})
        await(guardian, monitor, ref)

      {:DOWN, ^monitor, :process, ^guardian, _} ->
        fail!(:model_request_failed)
    end
  end

  defp await(guardian, monitor, ref) do
    receive do
      {^ref, :result, result} ->
        Process.demonitor(monitor, [:flush])

        case result do
          {:value, value} -> value
          :timeout -> fail!({:timeout, :total})
          :failed -> fail!(:model_request_failed)
        end

      {:DOWN, ^monitor, :process, ^guardian, _} ->
        fail!(:model_request_failed)
    end
  end

  defp guard(owner, owner_monitor, worker, ref, deadline, state, result) do
    receive do
      {^ref, :start} when state == :waiting ->
        if Process.alive?(owner) and remaining(deadline) != 0 do
          send(worker, {ref, :start})
          guard(owner, owner_monitor, worker, ref, deadline, :running, result)
        else
          stop(worker)
          send(owner, {ref, :result, :timeout})
        end

      {:DOWN, ^owner_monitor, :process, ^owner, _} ->
        stop(worker)

      {^ref, :result, value, completed_at} ->
        value = if deadline == :infinity or completed_at < deadline, do: value, else: :timeout
        guard(owner, owner_monitor, worker, ref, deadline, state, value)

      {:EXIT, ^worker, reason} ->
        value = if reason == :normal and result != nil, do: result, else: :failed
        send(owner, {ref, :result, value})
    after
      remaining(deadline) ->
        stop(worker)
        send(owner, {ref, :result, :timeout})
    end
  end

  defp stop(worker) do
    Process.exit(worker, :kill)

    receive do
      {:EXIT, ^worker, _} -> :ok
    end
  end

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - now(), 0)
  defp now, do: System.monotonic_time(:millisecond)
  defp fail!(reason), do: throw({:req_llm_adapter, reason})
end
