defmodule ExAgent.Observability.ReqLLM do
  @moduledoc """
  Application-owned ReqLLM tracing with one generation span per request.

  Attach once during application startup, after configuring the host SDK:

      :ok = ExAgent.Observability.ReqLLM.attach()

  This uses ReqLLM's public bridge and adapter behaviour. Inside an observed
  ExAgent Model request, it enriches the existing Model span with bounded request
  attributes and streaming timing. It does not create or end another span,
  overwrite execution accounting/status, or capture provider content/errors.
  ReqLLM's optional metrics remain available when the host supplies its meter APIs.
  Outside that context, all callbacks delegate to ReqLLM's stock OTel adapter.

  `:content` and `:langfuse` options apply to standalone ReqLLM calls. ExAgent's
  adapter always requests metadata-only telemetry; its own explicit redactor
  continues to control opt-in content. SDK, exporter and handlers belong to the
  application; this module does not start them or replace foreign handlers.

  Replace a previous `ReqLLM.OpenTelemetry.attach/2` with this attach, rather than
  registering both. Observed ExAgent adapter requests reject conflicting stock
  bridges before provider IO. Configure handlers at startup, not during requests.
  Arbitrary third-party instrumentations are outside this ownership check.

  ReqLLM's bridge tracks requests in its own ETS table. Abrupt worker termination
  can leave entries without a terminal event; long-lived hosts must periodically
  call `prune_stale_spans/1` with their chosen TTL. Pruning does not finish spans;
  ExAgent's watcher independently closes its own span. The SDK's shutdown/VM death
  and the upstream tracking lifecycle retain their documented limitations.
  """

  @behaviour ReqLLM.OpenTelemetry.Adapter
  alias ReqLLM.OpenTelemetry, as: Bridge
  alias ReqLLM.OpenTelemetry.OTelAdapter, as: Native
  alias ExAgent.Observability.OpenTelemetry

  @handler __MODULE__
  @fields [
    {:"req_llm.request_id", "exagent.req_llm.request_id", :label},
    {:"gen_ai.response.id", "gen_ai.response.id", :label},
    {:"gen_ai.response.model", "gen_ai.response.model", :label},
    {:"server.address", "server.address", :label},
    {:"server.port", "server.port", :port},
    {:"gen_ai.request.max_tokens", "gen_ai.request.max_tokens", :integer},
    {:"gen_ai.request.stream", "gen_ai.request.stream", :boolean},
    {:"gen_ai.response.time_to_first_chunk", "gen_ai.response.time_to_first_chunk", :seconds}
  ]

  @doc "Attach the single integrated bridge; never detach an application's foreign bridge."
  def attach(opts \\ []) do
    unless Keyword.keyword?(opts) and
             length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
             Enum.all?(opts, fn {key, _} -> key in [:content, :langfuse, :metrics] end),
           do: raise(ArgumentError, "invalid ReqLLM observability options")

    ExAgent.Observability.ReqLLM.Metrics.validate!(Keyword.get(opts, :metrics, false))

    if Enum.any?(bridges(), &(&1.id != @handler)) do
      {:error, :conflicting_req_llm_bridge}
    else
      Bridge.attach(@handler, Keyword.put(opts, :adapter, __MODULE__))
    end
  end

  @doc "Detach only the integrated handler and its upstream in-flight entries."
  def detach, do: Bridge.detach(@handler)

  @doc "Prune the integrated bridge's upstream entries using the host's TTL in milliseconds."
  def prune_stale_spans(ttl_ms), do: Bridge.prune_stale_spans(@handler, ttl_ms)

  @doc false
  def check_ownership do
    if OpenTelemetry.current_model_span() do
      case bridges() do
        [] ->
          :ok

        [%{config: config}] ->
          if Keyword.keyword?(config) and Keyword.get(config, :adapter) == __MODULE__,
            do: :ok,
            else: {:error, {:observability_conflict, :req_llm_bridge}}

        _ ->
          {:error, {:observability_conflict, :req_llm_bridge}}
      end
    else
      :ok
    end
  end

  defp bridges do
    Enum.filter(:telemetry.list_handlers([:req_llm, :request, :start]), fn handler ->
      handler.function == (&Bridge.handle_event/4)
    end)
  end

  @impl true
  defdelegate available?(), to: Native
  @impl true
  defdelegate metrics_available?(), to: ExAgent.Observability.ReqLLM.Metrics
  @impl true
  defdelegate record_histogram(record, config), to: ExAgent.Observability.ReqLLM.Metrics

  @impl true
  def start_span(name, attrs, config) do
    case OpenTelemetry.current_model_span() do
      nil ->
        Native.start_span(name, attrs, config)

      span ->
        owned = {:exagent_model, span}
        set_attributes(owned, attrs, config)
        owned
    end
  end

  @impl true
  def set_attributes({:exagent_model, span}, attrs, config) do
    selected =
      Enum.reduce(@fields, %{}, fn {key, target, kind}, acc ->
        value = Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

        case scalar(value, kind) do
          nil -> acc
          value -> Map.put(acc, target, value)
        end
      end)

    Native.set_attributes(span, selected, config)
  end

  def set_attributes(span, attrs, config), do: Native.set_attributes(span, attrs, config)

  @impl true
  def add_event({:exagent_model, _}, _, _, _), do: :ok
  def add_event(span, name, attrs, config), do: Native.add_event(span, name, attrs, config)

  @impl true
  def set_status({:exagent_model, _}, _, _, _), do: :ok

  def set_status(span, status, message, config),
    do: Native.set_status(span, status, message, config)

  @impl true
  def end_span({:exagent_model, _}, _), do: :ok
  def end_span(span, config), do: Native.end_span(span, config)

  @impl true
  def start_child_span({:exagent_model, _} = parent, _, _, _, _), do: parent

  def start_child_span(parent, name, attrs, opts, config),
    do: Native.start_child_span(parent, name, attrs, opts, config)

  @impl true
  def end_span_at({:exagent_model, _}, _, _), do: :ok
  def end_span_at(span, time, config), do: Native.end_span_at(span, time, config)

  defp scalar(value, :label), do: OpenTelemetry.label(value)
  defp scalar(value, :port) when is_integer(value) and value in 1..65_535, do: value
  defp scalar(value, :integer) when is_integer(value) and value >= 0, do: value
  defp scalar(value, :boolean) when is_boolean(value), do: value
  defp scalar(value, :seconds) when is_number(value) and value >= 0, do: value
  defp scalar(_, _), do: nil
end
