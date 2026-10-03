defmodule OTLPTransportProbe.HTTPWorker do
  @moduledoc false
  def run do
    :ok = :io.setopts(:standard_io, [:binary, {:encoding, :latin1}])
    :ok = :logger.set_primary_config(:level, :none)
    [_port, count, _deadline, fault] = System.argv()
    count = String.to_integer(count)
    Application.put_env(:opentelemetry, :processors, [])
    {:ok, _} = Application.ensure_all_started(:opentelemetry_exporter)
    # Published native SDK/exporter callbacks and record include. No private
    # encoder or exporter state inspection; opaque resource is passed through.
    for module <- [
          :otel_otlp_traces,
          :otel_otlp_common,
          :otel_resource,
          :otel_attributes,
          :otel_events,
          :otel_links,
          :otel_span
        ],
        do: true = Code.ensure_loaded?(module)

    <<length::unsigned-big-32>> = IO.binread(:stdio, 4)
    true = length in 1..65_536
    bytes = IO.binread(:stdio, length)
    true = is_binary(bytes) and byte_size(bytes) == length
    # This finite IPC comes only from the application's own native SDK callback,
    # never from storage or a network input. Native SDK records can contain atoms
    # created by that host's instrumentation; :safe would reject them in a fresh
    # VM. Admit them only here, within the disposable VM and 64KiB packet limit.
    # No module/callback is selected from these records. The launcher discards
    # worker diagnostics and reclaims this VM's atom table on every outcome.
    %{spans: spans, resource: resource, exporter_opts: opts} = :erlang.binary_to_term(bytes)
    ^count = length(spans)
    fields = Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
    keypos = Enum.find_index(fields, &(elem(&1, 0) == :instrumentation_scope)) + 2
    table = :ets.new(__MODULE__, [:duplicate_bag, {:keypos, keypos}])
    true = :ets.insert(table, spans)

    for {key, value} <- opts do
      true =
        key in [
          :otlp_traces_endpoint,
          :otlp_traces_headers,
          :otlp_traces_compression,
          :ssl_options
        ]

      Application.put_env(:opentelemetry_exporter, key, value)
    end

    Application.put_env(:opentelemetry_exporter, :otlp_traces_protocol, :http_protobuf)
    {:ok, state} = :otel_exporter_traces_otlp.init(%{protocol: :http_protobuf})
    if fault == "before_rpc_hold", do: Process.sleep(10_000)
    outcome = :otel_exporter_traces_otlp.export(table, resource, state)
    # Stock HTTP callback discards the response body, including partial_success.
    # A successful status is transport acceptance; never report span acceptance.
    receipt = %{
      result: if(outcome == :ok, do: "transport_ok", else: "failed"),
      http_status_success: outcome == :ok,
      sent: count,
      reported_accepted: 0,
      rejected: 0,
      unknown: count
    }

    :ok = :otel_exporter_traces_otlp.shutdown(state)
    body = :json.encode(receipt) |> IO.iodata_to_binary()
    :ok = IO.binwrite(:stdio, <<byte_size(body)::unsigned-big-32, body::binary>>)
    # Launcher kills and reaps this entire owned VM even after normal shutdown.
    # Therefore HTTP profile, pending request, socket and generated atoms die too.
    Process.sleep(10_000)
  end
end

OTLPTransportProbe.HTTPWorker.run()
