Code.require_file("../../examples/testing_audit_harness.exs", __DIR__)

defmodule ExAgent.TestingAuditHarnessTest do
  use ExUnit.Case, async: true
  alias ExAgent.TestingAuditHarness, as: Gate

  test "C0 requires the complete fourteen-invariant manifest and rejects probe errors" do
    probes =
      Map.new(Gate.c0_manifest(), fn {name, fields} -> {name, Map.new(fields, &{&1, true})} end)

    assert Enum.sum(Enum.map(probes, fn {_, values} -> map_size(values) end)) == 14
    assert Gate.c0(%{"probes" => probes}) == []
    refute Gate.c0(%{"probes" => %{}}) == []
    refute Gate.c0(%{"probes" => Map.delete(probes, "checkpoint")}) == []

    refute Gate.c0(%{
             "probes" => put_in(probes, ["checkpoint", "probe_error"], "failed callback")
           }) == []

    refute Gate.c0(%{"probes" => put_in(probes, ["checkpoint", "save_error_observable"], false)}) ==
             []

    refute Gate.c0(%{"probes" => put_in(probes, ["checkpoint", "save_error_observable"], "true")}) ==
             []
  end

  test "eval validator rejects empty, missing, duplicate, unknown names and missing criteria" do
    cases =
      for {name, fields} <- Gate.eval_manifest(),
          do: %{"name" => name, "criteria" => Map.new(fields, &{&1, true})}

    assert Gate.evals(%{"cases" => cases}) == []

    for invalid <- [
          [],
          tl(cases),
          [hd(cases) | cases],
          [%{} | tl(cases)],
          [put_in(hd(cases), ["criteria"], %{}) | tl(cases)],
          [put_in(hd(cases), ["name"], "unreviewed") | tl(cases)]
        ] do
      refute Gate.evals(%{"cases" => invalid}) == []
    end
  end

  test "load validator independently rejects compensated drops, corrupt percentiles and missing samples" do
    row = %{
      "phase" => "load",
      "case" => "simple",
      "concurrency" => 1,
      "tracing" => true,
      "samples" => 4,
      "correct" => 4,
      "warmup" => 2,
      "warmup_correct" => true,
      "raw_latency_us" => [40, 10, 30, 20],
      "latency_us" => %{"p50" => 20, "p95" => 40, "p99" => 40, "max" => 40},
      "ledger_per_run" => %{
        "status" => "succeeded",
        "request_count" => 1,
        "tool_calls" => 0,
        "usage_status" => "complete",
        "cost_status" => "unknown",
        "cost_cents" => nil,
        "usage" => %{"input_tokens" => 3, "output_tokens" => 2}
      },
      "processor_before" => counters(4),
      "processor_delta" => counters(8),
      "processor_after" => counters(12),
      "cleanup" => %{"passed" => true, "task_children" => 0, "local_exported" => 12}
    }

    assert Gate.load_row(row, 4, 2) == []
    # This observation satisfied the old accepted+dropped == expected gate.
    drop = put_in(row, ["processor_delta"], Map.merge(counters(7), %{"dropped_queue_full" => 1}))
    assert Enum.any?(Gate.load_row(drop, 4, 2), &String.contains?(&1, "zero-loss"))
    refute Gate.load_row(put_in(row, ["latency_us", "p95"], 30), 4, 2) == []
    refute Gate.load_row(put_in(row, ["raw_latency_us"], [40, 10, 20]), 4, 2) == []
    refute Gate.load_row(put_in(row, ["raw_latency_us"], []), 4, 2) == []
    refute Gate.load(%{"rows" => [], "soaks" => [], "preset" => %{}, "smoke" => true}) == []
  end

  defp counters(n),
    do: %{
      "accepted" => n,
      "exported" => n,
      "dropped_queue_full" => 0,
      "export_failed" => 0,
      "export_timed_out" => 0
    }
end
