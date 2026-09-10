# Deterministic regression for the empty-selection/flush-reset interleaving.
# Run in a disposable VM after dependencies have been compiled by the normal
# offline gate, from the repository root:
#
# EXAGENT_OFFLINE=1 elixir -pa _build/test/lib/opentelemetry/ebin -pa _build/test/lib/opentelemetry_api/ebin -pa _build/test/lib/telemetry/ebin test/support/observability_processor_probe.exs
#
# This compiles ONLY the processor source in memory, with a one-shot scheduling
# pause. It writes no BEAMs, modifies no production source, starts no application
# tracer/provider, and calls no external service. The exporter is a local fake.
# Unlike the public callback tests, this forces the exact otherwise-unobservable
# instruction interleaving; it is not a probabilistic concurrency stress test.

source_path = Path.expand("../../lib/exagent/observability/bounded_processor.ex", __DIR__)
source = File.read!(source_path)
reset = ":atomics.put(state.handle.counters, @flush, 0)"

unless length(String.split(source, reset)) == 2 do
  raise "expected exactly one flush-reset scheduling anchor; review this probe after refactoring"
end

unless :code.is_loaded(ExAgent.Observability.BoundedProcessor) == false do
  raise "run the probe in its isolated elixir VM, without loading the ExAgent application"
end

pause_before_reset = """
case Process.delete(:exagent_probe_empty_selection) do
  nil -> :ok
  probe_owner ->
    send(probe_owner, {:empty_selection_before_reset, self()})
    receive do: (:resume_probe_reset -> :ok)
end
#{reset}
"""

Code.compile_string(String.replace(source, reset, pause_before_reset), source_path)
{:ok, _} = Application.ensure_all_started(:telemetry)
ExUnit.start(seed: 0, max_cases: 1)

defmodule ExAgent.Observability.ProcessorSchedulingProbe do
  use ExUnit.Case, async: false
  require Record

  alias ExAgent.Observability.BoundedProcessor, as: Processor

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  defmodule Exporter do
    def init(owner), do: {:ok, owner}

    def export(table, _resource, owner) do
      send(owner, {:probe_batch, self(), :ets.tab2list(table)})
      receive do: (:complete_probe_batch -> :ok)
    end

    def shutdown(_owner), do: :ok
  end

  test "flush between empty select and reset drains every admitted batch without a second request" do
    opts = %{
      name: :exagent_flush_scheduling_probe,
      exporter: {Exporter, self()},
      resource: :local_probe,
      max_queue_size: 4,
      max_export_batch_size: 1,
      scheduled_delay_ms: 60_000,
      exporting_timeout_ms: 5000
    }

    {:ok, manager, config} = Processor.start_link(opts)
    Process.unlink(manager)

    on_exit(fn ->
      send(manager, :resume_probe_reset)
      Processor.shutdown(config)
    end)

    assert eventually(fn -> Processor.stats(config).status == :ready end)
    owner = self()

    :sys.replace_state(manager, fn state ->
      Process.put(:exagent_probe_empty_selection, owner)
      state
    end)

    assert Processor.force_flush(config) == :ok
    assert_receive {:empty_selection_before_reset, ^manager}, 1000

    for id <- [1, 2] do
      record = span(trace_id: 1, span_id: id, name: "probe", instrumentation_scope: :probe)
      assert Processor.on_end(record, config) == true
    end

    # The previous flush bit is still 1, so this request coalesces. No tick can
    # rescue it in the assertion window, and no subsequent flush is issued.
    assert Processor.force_flush(config) == :ok
    send(manager, :resume_probe_reset)
    assert_receive {:probe_batch, worker, [first]}, 1000
    send(worker, :complete_probe_batch)
    assert_receive {:probe_batch, ^worker, [second]}, 1000
    assert Enum.sort([span(first, :span_id), span(second, :span_id)]) == [1, 2]
    send(worker, :complete_probe_batch)

    assert eventually(fn ->
             stats = Processor.stats(config)
             stats.retained == 0 and stats.exported == 2
           end)
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(5)
      eventually(fun, attempts - 1)
    end
  end
end
