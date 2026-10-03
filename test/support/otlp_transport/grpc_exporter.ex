defmodule OTLPTransportProbe.GrpcExporter do
  @moduledoc """
  Experimental application-owned recipe using published native conversion and
  gRPC client APIs. This fixture is not an ExAgent exporter or a cloud acceptance.

  Exporter callbacks share the processor's bounded worker. Every batch owns one
  channel and an independent owner monitor; request failure never retries it.
  Credentials, if needed by a consumer, must be resolved in init, outside supervised
  arguments. This synthetic fixture accepts only a loopback endpoint.
  """
  @behaviour :otel_exporter_traces

  @impl true
  def init(opts) do
    %{port: port, observer: observer} = Application.fetch_env!(:otlp_transport_probe, :transport)
    true = is_integer(port) and port in 1..65_535
    true = is_pid(observer)
    {:ok, %{port: port, observer: observer, timeout: Map.get(opts, :timeout_ms, 250)}}
  end

  @impl true
  def export(table, resource, state) do
    case :otel_otlp_traces.to_proto(table, resource) do
      :empty -> :ok
      request -> export_request(request, state)
    end
  end

  @impl true
  def shutdown(_state), do: :ok

  defp export_request(request, state) do
    count = Enum.sum(for r <- request.resource_spans, s <- r.scope_spans, do: length(s.spans))
    request_bytes = :erlang.external_size(request)

    if count in 1..8 and request_bytes <= 65_536 do
      owner = self()
      token = make_ref()
      guard = spawn(fn -> own_channel(owner, token, state) end)

      receive do
        {^token, :ready, name, channel} ->
          send(state.observer, {:transport_channel, owner, guard, channel})

          outcome =
            try do
              ctx = :ctx.with_deadline_after(state.timeout, :millisecond)
              :opentelemetry_trace_service.export(ctx, request, %{channel: name})
            catch
              _, _ -> {:error, :callback_failure}
            end

          {result, counters} = classify(outcome, count)
          send(guard, {token, :close})

          receive do
            {^token, :closed} ->
              send(
                state.observer,
                {:transport_result, Map.put(counters, :request_external_bytes, request_bytes)}
              )

              result
          after
            1_500 ->
              send(
                state.observer,
                {:transport_result, %{sent: count, unknown: count, cleanup_failed: 1}}
              )

              :failed_not_retryable
          end

        {^token, :init_failed} ->
          send(state.observer, {:transport_result, %{sent: 0, unknown: count, init_failed: 1}})
          :failed_not_retryable
      after
        1_500 -> :failed_not_retryable
      end
    else
      send(state.observer, {:transport_result, %{sent: 0, unknown: count, oversized: 1}})
      :failed_not_retryable
    end
  end

  defp own_channel(owner, token, state) do
    ref = Process.monitor(owner)
    name = {__MODULE__, token}

    case :grpcbox_channel.start_link(name, [{:http, ~c"127.0.0.1", state.port, []}], %{
           sync_start: true
         }) do
      {:ok, channel} ->
        Process.unlink(channel)
        send(owner, {token, :ready, name, channel})

        receive do
          {^token, :close} -> :ok
          {:DOWN, ^ref, :process, ^owner, _} -> :ok
        end

        # The public default stop/1 uses force_delete; stop/2 with :shutdown also
        # shuts subchannels/connections. Own only this per-batch channel.
        :ok = :grpcbox_channel.stop(name, :shutdown)
        send(owner, {token, :closed})

      _ ->
        send(owner, {token, :init_failed})
    end
  end

  defp classify({:ok, response, _metadata}, count) when is_map(response) do
    bytes = :erlang.external_size(response)
    partial = Map.get(response, :partial_success, %{})
    rejected = Map.get(partial, :rejected_spans, 0)
    warning = if Map.get(partial, :error_message, "") == "", do: 0, else: 1

    if bytes <= 65_536 and is_integer(rejected) and rejected in 0..count do
      result = if rejected == 0, do: :ok, else: :failed_not_retryable

      {result,
       %{
         sent: count,
         reported_accepted: count - rejected,
         rejected: rejected,
         unknown: 0,
         warning: warning,
         response_external_bytes: bytes
       }}
    else
      {:failed_not_retryable,
       %{sent: count, unknown: count, invalid_response: 1, response_external_bytes: bytes}}
    end
  end

  defp classify(outcome, count) do
    timeout = if outcome == {:error, :timeout}, do: 1, else: 0
    {:failed_not_retryable, %{sent: count, unknown: count, failed: 1, timeout: timeout}}
  end
end
