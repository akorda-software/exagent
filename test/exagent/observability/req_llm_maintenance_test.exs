defmodule ExAgent.Observability.ReqLLMMaintenanceTest do
  use ExUnit.Case, async: false
  alias ExAgent.Observability.ReqLLM.Maintenance

  test "cadence and TTL must be explicit positive integers" do
    for options <- [
          [],
          [ttl_ms: 100],
          [interval_ms: 10],
          [ttl_ms: 0, interval_ms: 10],
          [ttl_ms: -1, interval_ms: 10],
          [ttl_ms: 100, interval_ms: 0],
          [ttl_ms: 100, interval_ms: 4_294_967_296],
          [ttl_ms: 1.0, interval_ms: 10],
          [ttl_ms: 100, interval_ms: 10, unknown: true],
          [ttl_ms: 100, ttl_ms: 200, interval_ms: 10],
          %{ttl_ms: 100, interval_ms: 10}
        ] do
      assert {:error, :invalid_maintenance_configuration} = Maintenance.start_link(options)
      assert Process.whereis(Maintenance) == nil
    end
  end

  test "a supervised dormant worker does not attach a bridge or install an SDK" do
    handlers = :telemetry.list_handlers([:req_llm, :request, :start])
    applications = Application.started_applications()
    worker = start_supervised!({Maintenance, ttl_ms: 100, interval_ms: 10})
    assert Process.whereis(Maintenance) == worker
    stats = await(fn -> Maintenance.stats() end, &(&1.ticks >= 2))
    assert stats.status == :detached
    assert stats.passes == 0 and stats.pruned_entries == 0
    assert handlers == :telemetry.list_handlers([:req_llm, :request, :start])
    assert applications == Application.started_applications()
    assert :ok == stop_supervised(Maintenance)
    refute Process.alive?(worker)
    assert {:error, :not_running} == Maintenance.stats()
  end

  test "supervision restarts the singleton and stale timer messages cannot trigger scans" do
    worker = start_supervised!({Maintenance, ttl_ms: 100, interval_ms: 60_000})
    before = Maintenance.stats()
    send(worker, {:timeout, make_ref(), :prune})
    assert before == Maintenance.stats()

    assert {:error, {:already_started, ^worker}} =
             Maintenance.start_link(ttl_ms: 100, interval_ms: 10)

    monitor = Process.monitor(worker)
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}

    replacement =
      await(fn -> Process.whereis(Maintenance) end, &(is_pid(&1) and &1 != worker))

    assert Process.alive?(replacement)
    assert %{ticks: 0, passes: 0, pruned_entries: 0, status: :waiting} = Maintenance.stats()
    assert :ok == stop_supervised(Maintenance)
    refute Process.alive?(replacement)
  end

  defp await(read, predicate) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    await(read, predicate, deadline)
  end

  defp await(read, predicate, deadline) do
    value = read.()

    cond do
      predicate.(value) ->
        value

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("maintenance condition timed out")

      true ->
        Process.sleep(5)
        await(read, predicate, deadline)
    end
  end
end
