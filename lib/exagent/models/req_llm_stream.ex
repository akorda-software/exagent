defmodule ExAgent.Models.ReqLLMStream do
  @moduledoc false
  alias ExAgent.Observability.OpenTelemetry
  alias ReqLLM.StreamResponse

  @chunk_bytes 65_536
  @response_bytes 1_048_576
  @chunks 4096
  @shutdown_grace 100

  # A demand acknowledges the previous delta, not receipt in an unbounded mailbox.
  # The producer owns creation and consumption so death before handle registration
  # still uses the backend's ordinary linked-owner lifecycle.
  def new(operation, timeout) do
    Stream.resource(fn -> open(operation, timeout) end, &next/1, &close/1)
  end

  def process(stream, emit) do
    key = make_ref()
    Process.put(key, {0, 0})

    try do
      StreamResponse.process_stream(stream,
        on_chunk: fn chunk ->
          {count, bytes} = Process.get(key)
          size = :erlang.external_size(chunk)

          cond do
            size > @chunk_bytes -> fail!({:stream_limit, :chunk_bytes})
            count + 1 > @chunks -> fail!({:stream_limit, :chunks})
            bytes + size > @response_bytes -> fail!({:stream_limit, :response_bytes})
            true -> Process.put(key, {count + 1, bytes + size})
          end
        end,
        on_result: fn text -> emit.({:text_delta, text}) end
      )
    after
      Process.delete(key)
      close_backend(stream)
    end
  end

  defp open(operation, timeout) do
    owner = self()
    ref = make_ref()
    context = OpenTelemetry.capture_context()
    deadline = now() + timeout

    {guardian, monitor} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, true)
        owner_monitor = Process.monitor(owner)
        guardian = self()

        worker =
          spawn_link(fn ->
            receive do
              {^ref, :start} ->
                register = fn stream ->
                  send(guardian, {ref, :register, stream})
                  receive do: ({^ref, :registered} -> :ok)
                end

                emit = fn event ->
                  send(owner, {ref, :delta, event})
                  receive do: ({^ref, :demand} -> :ok)
                end

                result =
                  try do
                    OpenTelemetry.with_context(context, fn -> operation.(register, emit) end)
                  catch
                    _, _ -> error(:model_request_failed)
                  end

                send(guardian, {ref, :result, result, now()})
            end
          end)

        send(owner, {ref, :ready, worker})

        guard(%{
          owner: owner,
          owner_monitor: owner_monitor,
          worker: worker,
          ref: ref,
          deadline: deadline,
          stream: nil,
          result: nil
        })
      end)

    receive do
      {^ref, :ready, worker} ->
        %{
          guardian: guardian,
          monitor: monitor,
          worker: worker,
          ref: ref,
          first: true,
          done: false
        }

      {:DOWN, ^monitor, :process, ^guardian, _} ->
        %{guardian: guardian, monitor: nil, ref: ref, done: false, failed: true}
    end
  end

  defp next(%{done: true} = state), do: {:halt, state}
  defp next(%{failed: true} = state), do: {[error(:model_request_failed)], %{state | done: true}}

  defp next(state) do
    %{ref: ref, guardian: guardian, monitor: monitor} = state

    if state.first,
      do: send(guardian, {ref, :start}),
      else: send(state.worker, {ref, :demand})

    receive do
      {^ref, :delta, event} ->
        {[event], %{state | first: false}}

      {^ref, :terminal, event} ->
        {[event], %{state | done: true}}

      {:DOWN, ^monitor, :process, ^guardian, _} ->
        {[error(:model_request_failed)], %{state | done: true, monitor: nil}}
    end
  end

  defp guard(state) do
    %{ref: ref, owner: owner, owner_monitor: owner_monitor, worker: worker} = state

    receive do
      {^ref, :start} ->
        if Process.alive?(owner) and remaining(state.deadline) > 0 do
          send(worker, {ref, :start})
          guard(state)
        else
          finish(state, error({:timeout, :total}))
        end

      {^ref, :register, stream} ->
        send(worker, {ref, :registered})
        guard(%{state | stream: stream})

      {^ref, :result, result, completed_at} ->
        result = if completed_at < state.deadline, do: result, else: error({:timeout, :total})
        guard(%{state | result: result})

      {:EXIT, ^worker, reason} ->
        close_backend(state.stream)

        result =
          if reason == :normal and state.result,
            do: state.result,
            else: error(:model_request_failed)

        send(owner, {ref, :terminal, result})

      {^ref, :close} ->
        stop(state)

      {:DOWN, ^owner_monitor, :process, ^owner, _} ->
        stop(state)
    after
      remaining(state.deadline) -> finish(state, error({:timeout, :total}))
    end
  end

  defp finish(state, result) do
    stop(state)
    send(state.owner, {state.ref, :terminal, result})
  end

  defp stop(state) do
    Process.exit(state.worker, :shutdown)

    receive do
      {:EXIT, worker, _} when worker == state.worker -> :ok
    after
      @shutdown_grace ->
        Process.exit(state.worker, :kill)
        receive do: ({:EXIT, worker, _} when worker == state.worker -> :ok)
    end

    close_backend(state.stream)
  end

  defp close(%{monitor: nil} = state), do: flush(state.ref)

  defp close(state) do
    send(state.guardian, {state.ref, :close})
    monitor = state.monitor
    receive do: ({:DOWN, ^monitor, :process, _, _} -> :ok)
    flush(state.ref)
  end

  defp close_backend(nil), do: :ok

  defp close_backend(stream) do
    StreamResponse.close(stream)
  catch
    :exit, _ -> :ok
  end

  defp flush(ref) do
    receive do
      {^ref, _, _} -> flush(ref)
    after
      0 -> :ok
    end
  end

  defp error(reason), do: {:error, %ExAgent.RequestError{provider: :req_llm, reason: reason}}
  defp fail!(reason), do: throw({:req_llm_adapter, reason})
  defp now, do: System.monotonic_time(:millisecond)
  defp remaining(deadline), do: max(deadline - now(), 0)
end
