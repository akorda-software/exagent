defmodule ExAgent.Observability.ReqLLM.Metrics do
  @moduledoc """
  Optional histogram adapter for the published OTel experimental API 0.6.

  Enable through `ExAgent.Observability.ReqLLM.attach(metrics: [models: ["my-model"]])`.
  The application supplies and starts its metric SDK, reader and exporter. This
  module neither starts them nor adds another telemetry handler. Metrics default
  to off. Models outside the host's fixed allowlist become `"other"`; the only
  other dimensions are input/output token type and a fixed `"error"` label.
  Request IDs, endpoints, response model names and content are never dimensions.
  Token measurements retain ReqLLM's normalized accounting quality.

  Uses public get_meter/1, lookup_instrument/2, create_histogram/3 and record/5.
  No instrument cache survives an SDK restart. Missing/stopped SDKs drop metrics;
  failures in optional metrics never fail the request or detach tracing.
  """
  @instruments %{
    "gen_ai.client.operation.duration" => {:"gen_ai.client.operation.duration", "s"},
    "gen_ai.client.token.usage" => {:"gen_ai.client.token.usage", "{token}"},
    "gen_ai.client.operation.time_to_first_chunk" =>
      {:"gen_ai.client.operation.time_to_first_chunk", "s"},
    "gen_ai.client.operation.time_per_output_chunk" =>
      {:"gen_ai.client.operation.time_per_output_chunk", "s"}
  }

  @doc false
  def validate!(false), do: :ok

  def validate!(models: models) when is_list(models) and length(models) in 1..32 do
    unless Enum.all?(models, &(is_binary(&1) and byte_size(&1) in 1..256 and String.valid?(&1))) and
             length(models) == length(Enum.uniq(models)),
           do: raise(ArgumentError, "metrics require a fixed model allowlist of 1..32 labels")

    :ok
  end

  def validate!(_), do: raise(ArgumentError, "metrics require false or models: [labels]")

  @doc false
  def metrics_available? do
    Enum.all?(
      [
        {:opentelemetry, :instrumentation_scope, 3},
        {:otel_meter_provider, :get_meter, 1},
        {:otel_meter, :lookup_instrument, 2},
        {:otel_meter, :create_histogram, 3},
        {:otel_histogram, :record, 5},
        {:otel_ctx, :get_current, 0}
      ],
      fn {module, function, arity} ->
        Code.ensure_loaded?(module) and function_exported?(module, function, arity)
      end
    )
  end

  @doc false
  def record_histogram(%{name: name, value: value, attributes: attrs}, config)
      when is_map(attrs) do
    with [models: models] <- Keyword.get(config, :metrics, false),
         {instrument, unit} <- Map.get(@instruments, name),
         true <- valid_value?(value, unit),
         true <- metrics_available?() do
      scope =
        apply(:opentelemetry, :instrumentation_scope, [
          :exagent_req_llm,
          "1",
          "https://opentelemetry.io/schemas/1.37.0"
        ])

      meter = apply(:otel_meter_provider, :get_meter, [scope])

      if apply(:otel_meter, :lookup_instrument, [meter, instrument]) == :undefined do
        boundaries =
          if unit == "s",
            do: ReqLLM.OpenTelemetry.Metrics.duration_boundaries(),
            else: ReqLLM.OpenTelemetry.Metrics.token_boundaries()

        apply(:otel_meter, :create_histogram, [
          meter,
          instrument,
          %{unit: unit, advisory_params: %{explicit_bucket_boundaries: boundaries}}
        ])
      end

      model = Map.get(attrs, "gen_ai.request.model")
      dimensions = %{"gen_ai.request.model" => if(model in models, do: model, else: "other")}

      dimensions =
        if Map.has_key?(attrs, "error.type"),
          do: Map.put(dimensions, "error.type", "error"),
          else: dimensions

      dimensions = if unit == "{token}", do: token_dimensions(dimensions, attrs), else: dimensions

      if dimensions do
        apply(:otel_histogram, :record, [
          apply(:otel_ctx, :get_current, []),
          meter,
          instrument,
          value,
          dimensions
        ])
      end
    end

    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  def record_histogram(_, _), do: :ok

  defp valid_value?(value, "{token}"), do: is_integer(value) and value in 0..9_007_199_254_740_991
  defp valid_value?(value, "s"), do: is_number(value) and value >= 0 and value <= 1.0e12

  defp token_dimensions(dimensions, %{"gen_ai.token.type" => type})
       when type in ["input", "output"],
       do:
         dimensions
         |> Map.put("gen_ai.token.type", type)
         |> Map.put("exagent.accounting.quality", "normalized")

  defp token_dimensions(_, _), do: nil
end
