defmodule ExAgent.Providers.StreamTransport do
  @moduledoc """
  Owned, demand-driven Req callback transport (no `into: :self` firehose).

  Each enumeration starts a private worker and guardian. A callback waits for
  demand before handing at most 64 KiB to the consumer; the next demand is the
  acknowledgement. The synchronous Finch callback cannot read further while
  waiting. The guardian kills HTTP work if the enumerator dies; halt/raise
  cleanup kills both and selectively drains only this resource's messages.

  Model `stream_options` are local keywords, never provider payload fields:
  `max_frame_bytes: 1_048_576`, `max_buffer_bytes: 1_048_576`,
  `max_response_bytes: 8_388_608`, `timeout: 60_000` (all positive integers).
  Timeout bounds waiting for demand as well as a consumer waiting for data.
  A suspended continuation is supported only within this inactivity timeout.
  Limits apply to raw callback bytes; streaming compression is not requested.
  Socket/library buffers are not
  a promise of zero buffering, but the consumer mailbox is not an unbounded queue.
  """

  @defaults [
    max_frame_bytes: 1_048_576,
    max_buffer_bytes: 1_048_576,
    max_response_bytes: 8_388_608,
    timeout: 60_000
  ]

  def options!(opts) do
    unless Keyword.keyword?(opts) and
             Enum.all?(opts, fn {key, value} ->
               Keyword.has_key?(@defaults, key) and is_integer(value) and value > 0
             end) do
      raise ArgumentError, "invalid stream_options: expected positive byte limits and timeout"
    end

    Keyword.merge(@defaults, opts)
  end

  def stream(http_opts, opts \\ []) do
    Stream.resource(
      fn -> start(http_opts, options!(opts)) end,
      &next/1,
      &close/1
    )
  end

  defp start(http_opts, opts) do
    owner = self()
    ref = make_ref()
    context = ExAgent.Observability.OpenTelemetry.capture_context()
    {guardian, monitor} = spawn_monitor(fn -> guard(owner, ref, http_opts, opts, context) end)

    receive do
      {^ref, :worker, worker} ->
        %{
          ref: ref,
          worker: worker,
          guardian: guardian,
          monitor: monitor,
          timeout: opts[:timeout],
          done: false
        }
    end
  end

  defp guard(owner, ref, http_opts, opts, context) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(owner)

    worker =
      spawn_link(fn ->
        ExAgent.Observability.OpenTelemetry.with_context(context, fn ->
          request(owner, ref, http_opts, opts)
        end)
      end)

    send(owner, {ref, :worker, worker})
    guard_loop(owner, owner_monitor, ref, worker, opts[:timeout])
  end

  defp guard_loop(owner, owner_monitor, ref, worker, timeout) do
    receive do
      {:DOWN, ^owner_monitor, :process, ^owner, _} ->
        Process.exit(worker, :kill)

      {:EXIT, ^worker, :normal} ->
        # Normal completion has already handed EOF/error to the consumer. Keep
        # the guardian alive until resource cleanup, but bound abandoned state.
        receive do
          {:DOWN, ^owner_monitor, :process, ^owner, _} -> :ok
        after
          timeout -> :ok
        end

      {:EXIT, ^worker, reason} ->
        send(owner, {ref, :item, {:error, {:stream_worker_exit, reason}}})
    end
  end

  defp request(owner, ref, http_opts, opts) do
    emit = fn item ->
      receive do
        {^ref, :demand} -> send(owner, {ref, :item, item})
      after
        opts[:timeout] -> exit(:stream_demand_timeout)
      end
    end

    callback = fn {:data, data}, {req, resp} ->
      total = Map.get(resp.private, :exagent_bytes, 0) + byte_size(data)
      resp = %{resp | private: Map.put(resp.private, :exagent_bytes, total)}

      cond do
        total > opts[:max_response_bytes] ->
          throw({:stream_error, {:stream_limit, :max_response_bytes}})

        resp.status == 200 ->
          emit_chunks(data, emit)
          {:cont, {req, resp}}

        true ->
          {:cont, {req, %{resp | body: (resp.body || "") <> data}}}
      end
    end

    result =
      try do
        http_opts =
          Keyword.merge(http_opts,
            into: callback,
            compressed: false,
            decode_body: false,
            retry: false,
            redirect: false
          )

        case Req.request(http_opts) do
          {:ok, %{status: 200}} -> :eof
          {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
          {:error, error} -> {:error, error}
        end
      rescue
        error -> {:error, error}
      catch
        :exit, :stream_demand_timeout -> exit(:stream_demand_timeout)
        :throw, {:stream_error, reason} -> {:error, reason}
        kind, reason -> {:error, {:transport_exit, kind, reason}}
      end

    emit.(result)
  end

  defp emit_chunks("", _emit), do: :ok
  defp emit_chunks(data, emit) when byte_size(data) <= 65_536, do: emit.({:data, data})

  defp emit_chunks(<<chunk::binary-size(65_536), rest::binary>>, emit) do
    emit.({:data, chunk})
    emit_chunks(rest, emit)
  end

  defp next(%{done: true} = state), do: {:halt, state}

  defp next(%{ref: ref, monitor: monitor} = state) do
    send(state.worker, {ref, :demand})

    receive do
      {^ref, :item, :eof} ->
        {:halt, %{state | done: true}}

      {^ref, :item, {:error, _} = error} ->
        {[error], %{state | done: true}}

      {^ref, :item, item} ->
        {[item], state}

      {:DOWN, ^monitor, :process, _, reason} ->
        {[{:error, {:stream_owner_exit, reason}}], %{state | done: true}}
    after
      state.timeout -> {[{:error, :timeout}], %{state | done: true}}
    end
  end

  defp close(state) do
    worker_monitor = Process.monitor(state.worker)
    guardian_monitor = Process.monitor(state.guardian)
    Process.exit(state.worker, :kill)
    Process.exit(state.guardian, :kill)

    receive do
      {:DOWN, ^worker_monitor, :process, _, _} -> :ok
    end

    receive do
      {:DOWN, ^guardian_monitor, :process, _, _} -> :ok
    end

    Process.demonitor(state.monitor, [:flush])
    drain(state.ref)
  end

  defp drain(ref) do
    receive do
      {^ref, _, _} -> drain(ref)
    after
      0 -> :ok
    end
  end
end
