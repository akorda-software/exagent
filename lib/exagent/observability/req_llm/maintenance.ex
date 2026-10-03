defmodule ExAgent.Observability.ReqLLM.Maintenance do
  @moduledoc """
  Optional application-supervised cleanup of the integrated ReqLLM bridge.

  Attach `ExAgent.Observability.ReqLLM` once after the host SDK is configured,
  then include this child in the application's supervision tree:

      {ExAgent.Observability.ReqLLM.Maintenance,
       ttl_ms: 120_000, interval_ms: 30_000}

  Both options are required positive integers in milliseconds. **Choose a TTL
  longer than every allowed live ReqLLM request**, including standalone calls,
  streaming and retries. Pruning is based on age, not process liveness. A shorter
  TTL can remove a live request's tracking and lose its terminal diagnostics.
  This child does not configure or enforce the application's request deadlines.

  One node-local worker periodically calls ReqLLM's public pruning API for the
  integrated handler only. It stays dormant when that handler is absent. It
  never attaches/detaches a bridge, starts an SDK, finishes a span or prunes
  another handler. Stopping the child leaves the host's tracing configuration
  intact. The next timer is scheduled after each pass, so scans do not overlap.

  `stats/0` exposes numeric cleanup counters and a fixed status, without request
  IDs, content or span data. Counters reset when supervision restarts the worker.
  ReqLLM scans its matching entries; its transient allocation and the overall
  table size are not a hard memory bound. Request admission remains host-owned.
  No child is installed automatically by ExAgent or
  `ExAgent.Observability.ReqLLM.attach/1`.
  """

  use GenServer
  alias ExAgent.Observability.ReqLLM, as: Integration

  @type stats :: %{
          ticks: non_neg_integer(),
          passes: non_neg_integer(),
          pruned_entries: non_neg_integer(),
          last_pruned_entries: non_neg_integer(),
          status: :waiting | :active | :detached
        }

  @doc "Start the singleton through the application's supervision tree."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    if valid?(options) do
      GenServer.start_link(__MODULE__, Map.new(options), name: __MODULE__)
    else
      {:error, :invalid_maintenance_configuration}
    end
  end

  @doc "Read this worker's counters; returns an error when it is not running."
  @spec stats() :: stats() | {:error, :not_running | :unavailable}
  def stats do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_running}
      pid -> GenServer.call(pid, :stats)
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @impl true
  def init(config) do
    state = %{
      ttl_ms: config.ttl_ms,
      interval_ms: config.interval_ms,
      ticks: 0,
      passes: 0,
      pruned_entries: 0,
      last_pruned_entries: 0,
      status: :waiting,
      timer: nil
    }

    {:ok, schedule(state)}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, Map.drop(state, [:ttl_ms, :interval_ms, :timer]), state}
  end

  @impl true
  def handle_info({:timeout, ref, :prune}, %{timer: ref} = state) do
    state = %{state | ticks: state.ticks + 1}

    state =
      if attached?() do
        count = Integration.prune_stale_spans(state.ttl_ms)

        %{
          state
          | passes: state.passes + 1,
            pruned_entries: state.pruned_entries + count,
            last_pruned_entries: count,
            status: :active
        }
      else
        %{state | last_pruned_entries: 0, status: :detached}
      end

    {:noreply, schedule(state)}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, state) do
    Process.cancel_timer(state.timer)
    :ok
  end

  defp schedule(state) do
    %{state | timer: :erlang.start_timer(state.interval_ms, self(), :prune)}
  end

  defp attached? do
    Enum.any?(:telemetry.list_handlers([:req_llm, :request, :start]), fn handler ->
      handler.id == Integration and
        handler.function == (&ReqLLM.OpenTelemetry.handle_event/4) and
        Keyword.keyword?(handler.config) and
        Keyword.get(handler.config, :adapter) == Integration
    end)
  end

  defp valid?(options) do
    Keyword.keyword?(options) and
      Enum.sort(Keyword.keys(options)) == [:interval_ms, :ttl_ms] and
      is_integer(options[:ttl_ms]) and options[:ttl_ms] > 0 and
      is_integer(options[:interval_ms]) and options[:interval_ms] in 1..4_294_967_295
  end
end
