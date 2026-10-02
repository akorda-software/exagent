defmodule LangfuseAcceptance.AdmissionExporter do
  @moduledoc """
  Application-owned admission around the public trace-exporter callback. Inspect
  the complete native SDK batch before any network write, then copy its opaque
  SDK rows into <=8-span batches for the unchanged isolated recipe. No OTLP codec.
  """
  @behaviour :otel_exporter_traces
  alias OTLPTransportProbe.IsolatedExporter

  def init(opts) do
    inner =
      if opts.mode == "live" do
        {:ok, state} =
          IsolatedExporter.init(%{
            deadline_ms: System.get_env("LF_BATCH_DEADLINE_MS", "2000") |> String.to_integer(),
            rpc_deadline_ms: System.get_env("LF_RPC_DEADLINE_MS", "1200") |> String.to_integer()
          })

        state
      end

    {:ok, Map.put(opts, :inner, inner)}
  end

  def shutdown(_state), do: :ok

  def export(table, resource, state) do
    request = :otel_otlp_traces.to_proto(table, resource)
    payload = :erlang.term_to_binary(request)
    spans = spans(request)
    ids = Enum.uniq(Enum.map(spans, & &1.trace_id))
    rows = :ets.tab2list(table)

    # The opaque row's trace identity is obtained through the public converter,
    # never by matching the SDK's private record layout.
    grouped = Enum.group_by(rows, &row_trace(&1, table, resource))
    # Opik mints its UUID from the first received batch's earliest timestamp.
    # Sort opaque rows via the published converter only for an explicit profile,
    # so the independent API oracle can derive that UUID from the native root.
    grouped =
      if state.request_profile do
        Map.new(grouped, fn {id, values} ->
          {id, Enum.sort_by(values, &row_start(&1, table, resource))}
        end)
      else
        grouped
      end

    traces =
      Enum.map(ids, fn id ->
        with_table(table, grouped[id], fn trace_table ->
          native = :otel_otlp_traces.to_proto(trace_table, resource)
          raw = :erlang.term_to_binary(native)

          projected_bytes =
            if state.request_profile,
              do: :erlang.external_size(state.request_profile.project(native)),
              else: byte_size(raw)

          trace_manifest(native, byte_size(raw), state.sentinels)
          |> Map.put(:projected_etf_bytes, projected_bytes)
        end)
      end)

    summary = %{
      trace_count: length(traces),
      span_count: length(spans),
      aggregate_etf_bytes: byte_size(payload),
      traces: traces,
      sentinels: state.sentinels,
      constraints: %{
        spans_per_trace: 32,
        native_etf_bytes_per_trace: 65_536,
        transport_concurrency: 1
      }
    }

    admitted =
      length(traces) in 1..state.max_traces and length(spans) == length(rows) and
        Enum.all?(
          traces,
          &(&1.span_count in 1..32 and &1.native_etf_bytes <= 65_536 and
              &1.projected_etf_bytes <= 65_536)
        )

    token = make_ref()
    send(state.observer, {:native_admission, self(), token, admitted, summary})

    receive do
      {:native_admission_ack, ^token} when admitted ->
        if state.mode == "preview" do
          :ok
        else
          Enum.reduce_while(ids, :ok, fn id, :ok ->
            result =
              Enum.reduce_while(Enum.chunk_every(grouped[id], 8), :ok, fn batch, :ok ->
                status =
                  with_table(table, batch, &IsolatedExporter.export(&1, resource, state.inner))

                if status == :ok, do: {:cont, :ok}, else: {:halt, :failed_not_retryable}
              end)

            if result == :ok, do: {:cont, :ok}, else: {:halt, :failed_not_retryable}
          end)
        end

      {:native_admission_reject, ^token} ->
        :failed_not_retryable
    after
      2_000 -> :failed_not_retryable
    end
  end

  defp row_trace(row, original, resource) do
    with_table(original, [row], fn table ->
      [span] = spans(:otel_otlp_traces.to_proto(table, resource))
      span.trace_id
    end)
  end

  defp row_start(row, original, resource) do
    with_table(original, [row], fn table ->
      [span] = spans(:otel_otlp_traces.to_proto(table, resource))
      span.start_time_unix_nano
    end)
  end

  defp with_table(original, rows, fun) do
    table =
      :ets.new(__MODULE__, [:ets.info(original, :type), {:keypos, :ets.info(original, :keypos)}])

    try do
      true = :ets.insert(table, rows)
      fun.(table)
    after
      :ets.delete(table)
    end
  end

  defp spans(%{resource_spans: resources}),
    do: for(resource <- resources, scope <- resource.scope_spans, span <- scope.spans, do: span)

  defp trace_manifest(request, bytes, sentinels) do
    payload = :erlang.term_to_binary(request)
    for sentinel <- sentinels, do: true = :binary.match(payload, sentinel) == :nomatch
    [%{resource: resource}] = request.resource_spans
    spans = spans(request)
    [trace_id] = Enum.uniq(Enum.map(spans, & &1.trace_id))
    known_ids = MapSet.new(Enum.map(spans, & &1.span_id))

    projected =
      for span <- spans do
        parent = Map.get(span, :parent_span_id, <<>>)
        true = parent == <<>> or MapSet.member?(known_ids, parent)
        attributes = attributes(span)
        false = Enum.any?(Map.keys(attributes), &String.starts_with?(&1, "exagent.content."))
        true = span.end_time_unix_nano >= span.start_time_unix_nano

        %{
          id: hex(span.span_id),
          parent_id: if(parent == <<>>, do: nil, else: hex(parent)),
          name: span.name,
          start_time_ms: div(span.start_time_unix_nano, 1_000_000),
          end_time_ms: div(span.end_time_unix_nano, 1_000_000),
          level:
            if(get_in(span, [:status, :code]) == :STATUS_CODE_ERROR, do: "ERROR", else: "DEFAULT"),
          attributes: attributes
        }
      end

    true = Enum.count(projected, &is_nil(&1.parent_id)) == 1
    true = length(projected) == MapSet.size(known_ids)
    start = Enum.min(Enum.map(spans, & &1.start_time_unix_nano)) |> div(1_000_000_000)
    finish = Enum.max(Enum.map(spans, & &1.end_time_unix_nano)) |> div(1_000_000_000)

    %{
      trace_id: hex(trace_id),
      span_count: length(spans),
      native_etf_bytes: bytes,
      resource_attributes: attributes(resource),
      from_start_time: DateTime.from_unix!(start - 2) |> DateTime.to_iso8601(),
      to_start_time: DateTime.from_unix!(finish + 2) |> DateTime.to_iso8601(),
      spans: projected
    }
  end

  defp attributes(%{attributes: values}),
    do: Map.new(values, fn %{key: key, value: %{value: {_type, value}}} -> {key, value} end)

  defp hex(value), do: Base.encode16(value, case: :lower)
end
