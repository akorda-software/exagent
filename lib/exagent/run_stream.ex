defmodule ExAgent.RunStream do
  @moduledoc false

  # Only the next demand releases the worker past its last public event. This
  # bounds the bridge, not an adapter's independent HTTP push buffers.
  def new(agent, prompt, opts) do
    Stream.resource(
      fn -> open(agent, prompt, opts) end,
      &next/1,
      &close/1
    )
  end

  defp open(agent, prompt, opts) do
    opts = ExAgent.Observability.OpenTelemetry.options(opts)
    owner = self()
    ref = make_ref()

    {guardian, monitor} =
      spawn_monitor(fn ->
        owner_monitor = Process.monitor(owner)
        guardian = self()

        {worker, worker_monitor} =
          spawn_monitor(fn -> run(owner, guardian, ref, agent, prompt, opts) end)

        send(owner, {ref, :ready, worker})
        guard(owner, owner_monitor, worker, worker_monitor, ref, nil)
      end)

    receive do
      {^ref, :ready, worker} ->
        %{guardian: guardian, monitor: monitor, worker: worker, ref: ref, done: false}

      {:DOWN, ^monitor, :process, ^guardian, reason} ->
        exit({:stream_start_failed, reason})
    end
  end

  defp run(owner, guardian, ref, agent, prompt, opts) do
    await_demand(ref)
    event_sink = Keyword.get(opts, :on_event)
    progress_sink = Keyword.get(opts, :on_progress)

    on_event = fn event ->
      safe_call(event_sink, event)

      if event.type == :text_delta do
        send(owner, {ref, :event, {:delta, event.data.text}})
        await_demand(ref)
      end
    end

    on_progress = fn partial ->
      send(guardian, {ref, :progress, partial})
      safe_call(progress_sink, partial)
    end

    opts =
      opts
      |> Keyword.put(:stream_text, true)
      |> Keyword.put(:on_event, on_event)
      |> Keyword.put(:on_progress, on_progress)

    terminal =
      case ExAgent.run(agent, prompt, opts) do
        {:ok, result} -> {:result, result}
        {:error, error} -> {:error, error}
      end

    # Send via the guardian: its monitor cannot overtake this terminal and
    # manufacture a second outcome if the worker exits immediately afterwards.
    send(guardian, {ref, :terminal, terminal})
  catch
    :throw, :exagent_stream_cancelled -> :ok
  end

  defp await_demand(ref) do
    receive do
      {^ref, :demand} -> :ok
      {^ref, :cancel} -> throw(:exagent_stream_cancelled)
    end
  end

  defp next(%{done: true} = state), do: {:halt, state}

  defp next(state) do
    %{ref: ref, worker: worker, monitor: monitor, guardian: guardian} = state
    send(worker, {ref, :demand})

    receive do
      {^ref, :event, {:delta, _} = event} -> {[event], state}
      {^ref, :event, terminal} -> {[terminal], %{state | done: true}}
      {:DOWN, ^monitor, :process, ^guardian, reason} -> exit({:stream_owner_failed, reason})
    end
  end

  defp close(state) do
    send(state.guardian, {state.ref, :close})
    monitor = state.monitor

    receive do
      {:DOWN, ^monitor, :process, _, _} -> :ok
    after
      1_000 ->
        Process.exit(state.worker, :kill)
        Process.exit(state.guardian, :kill)
    end

    Process.demonitor(monitor, [:flush])
    flush(state.ref)
  end

  defp guard(owner, owner_monitor, worker, worker_monitor, ref, partial) do
    receive do
      {^ref, :progress, result} ->
        guard(owner, owner_monitor, worker, worker_monitor, ref, result)

      {^ref, :terminal, terminal} ->
        send(owner, {ref, :event, terminal})
        finished(owner_monitor, worker, worker_monitor, ref)

      {^ref, :close} ->
        cancel(worker, worker_monitor, ref)

      {:DOWN, ^owner_monitor, :process, ^owner, _} ->
        cancel(worker, worker_monitor, ref)

      {:DOWN, ^worker_monitor, :process, ^worker, reason} ->
        if partial do
          partial = %{partial | output: nil, status: :failed, usage_status: :partial}
          error = %ExAgent.RunError{reason: {:worker_exit, reason}, partial: partial}
          send(owner, {ref, :event, {:error, error}})
          # This monitor notification was consumed here; cancellation must not
          # wait for the same DOWN a second time.
          finished(owner_monitor, nil, nil, ref)
        else
          exit({:stream_worker_failed, reason})
        end
    end
  end

  defp finished(owner_monitor, worker, worker_monitor, ref) do
    receive do
      {^ref, :close} -> cancel(worker, worker_monitor, ref)
      {:DOWN, ^owner_monitor, :process, _, _} -> cancel(worker, worker_monitor, ref)
      {:DOWN, ^worker_monitor, :process, ^worker, _} -> finished(owner_monitor, nil, nil, ref)
      {^ref, :progress, _} -> finished(owner_monitor, worker, worker_monitor, ref)
    end
  end

  defp cancel(nil, _, _), do: :ok

  defp cancel(worker, monitor, ref) do
    send(worker, {ref, :cancel})

    receive do
      {:DOWN, ^monitor, :process, ^worker, _} -> :ok
    after
      100 ->
        Process.exit(worker, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^worker, _} -> :ok
        end
    end
  end

  defp flush(ref) do
    receive do
      {^ref, :event, _} -> flush(ref)
      {^ref, :ready, _} -> flush(ref)
    after
      0 -> :ok
    end
  end

  defp safe_call(fun, value) when is_function(fun, 1) do
    fun.(value)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp safe_call(_, _), do: :ok
end
