defmodule OTLPTransportProbe.VMWorker do
  @moduledoc false
  def run do
    # This owned IPC carries arbitrary packet4/ETF bytes. A UTF-8 IO device
    # can wait for another codepoint byte even before reading a complete header.
    :ok = :io.setopts(:standard_io, [:binary, {:encoding, :latin1}])
    :ok = :logger.set_primary_config(:level, :none)
    [port, count, deadline, fault] = System.argv()
    port = String.to_integer(port)
    count = String.to_integer(count)
    deadline = String.to_integer(deadline)
    # Loading published converter modules admits only their existing atoms to
    # safe ETF decode. The generated encoder is called only inside the public
    # gRPC client, never directly by this recipe.
    true = Code.ensure_loaded?(:otel_otlp_traces)
    true = Code.ensure_loaded?(:otel_otlp_common)
    {:ok, _} = Application.ensure_all_started(:grpcbox)
    <<length::unsigned-big-32>> = IO.binread(:stdio, 4)
    true = length in 1..65_536
    payload = IO.binread(:stdio, length)
    true = is_binary(payload) and byte_size(payload) == length
    request = :erlang.binary_to_term(payload, [:safe])
    ^count = Enum.sum(for r <- request.resource_spans, s <- r.scope_spans, do: length(s.spans))
    name = {__MODULE__, make_ref()}

    {:ok, _channel} =
      :grpcbox_channel.start_link(name, [{:http, ~c"127.0.0.1", port, []}], %{sync_start: true})

    if fault == "before_rpc_hold", do: Process.sleep(10_000)

    outcome =
      :opentelemetry_trace_service.export(
        :ctx.with_deadline_after(deadline, :millisecond),
        request,
        %{channel: name}
      )

    receipt = classify(outcome, count)

    receipt =
      if fault == "shutdown_block" do
        # A public OTP control stalls only this recipe's own shutdown worker.
        # Suspending a gen_statem channel does NOT block its system stop, so do
        # not claim that this control reproduces an internal grpcbox hang.
        {closer, _} =
          spawn_monitor(fn ->
            receive do
              :stop -> :grpcbox_channel.stop(name, :shutdown)
            after
              10_000 -> :ok
            end
          end)

        true = :erlang.suspend_process(closer)
        send(closer, :stop)
        {:status, :suspended} = Process.info(closer, :status)

        Map.merge(receipt, %{
          stop_blocked: true,
          stop_control: "owned_shutdown_worker_suspended",
          grpcbox_internal_hang_reproduced: false
        })
      else
        receipt
      end

    body = :json.encode(receipt) |> IO.iodata_to_binary()
    true = byte_size(body) in 1..4_096
    :ok = IO.binwrite(:stdio, <<byte_size(body)::unsigned-big-32, body::binary>>)
    # Keep the registered leader alive until its owning launcher kills/reaps
    # the group. Even this fallback wait is finite; no long-lived helper thread.
    Process.sleep(10_000)
  end

  defp classify({:ok, response, _}, count) when is_map(response) do
    bytes = :erlang.external_size(response)
    partial = Map.get(response, :partial_success, %{})
    rejected = Map.get(partial, :rejected_spans, 0)
    warning = Map.get(partial, :error_message, "") != ""

    if bytes <= 65_536 and is_integer(rejected) and rejected in 0..count do
      %{
        result: if(rejected == 0, do: "ok", else: "partial"),
        sent: count,
        reported_accepted: count - rejected,
        rejected: rejected,
        unknown: 0,
        warning: warning,
        response_external_bytes: bytes
      }
    else
      %{
        result: "failed",
        sent: count,
        reported_accepted: 0,
        rejected: 0,
        unknown: count,
        invalid_response: true,
        response_external_bytes: bytes
      }
    end
  end

  defp classify(outcome, count) do
    %{
      result: "failed",
      sent: count,
      reported_accepted: 0,
      rejected: 0,
      unknown: count,
      rpc_timeout: outcome == {:error, :timeout}
    }
  end
end

OTLPTransportProbe.VMWorker.run()
