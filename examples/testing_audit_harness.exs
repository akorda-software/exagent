# Explicit acceptance manifests, independent of the scenario/probe producers.
# Kept with the examples so packaged examples can run without checkout test files.
# Validators consume decoded JSON (string keys), never trust a producer's passed
# flag alone, and return diagnostic labels instead of discarding a failed report.
defmodule ExAgent.TestingAuditHarness do
  @c0 %{
    "stream_parity" => ~w(same_output stream_has_final_model),
    "sse" => ~w(preserves_unrelated_message decodes_crlf_frames closes_source_resource),
    "tool_arguments" => ~w(invalid_arguments_blocked),
    "permissions" => ~w(constructor_rejects_invalid_action invalid_action_blocks_effect),
    "delegation" => ~w(descendant_authority_restricted tree_within_parent_request_limit),
    "partial_failure" => ~w(completed_effect_visible_in_history consumed_usage_preserved),
    "checkpoint" => ~w(save_attempted save_error_observable)
  }
  @evals %{
    "typed_reading" =>
      ~w(typed_output_from_read one_explicit_retry no_unauthorized_effects inclusive_requests known_usage known_synthetic_cost checkpoint_confirmed actual_snapshot),
    "simulated_effect_recovery" =>
      ~w(one_effect_with_expected_value no_unauthorized_effects partial_effect_preserved explicit_retry_before_effect failed_request_counted usage_known_subtotal cost_honest dirty_blocks_replay checkpoint_only_retry restore_without_replay),
    "negative_controls" =>
      ~w(inherited_deny effect_counter_is_live schema_rejects_without_coercion ecto_rejects_invalid_output)
  }
  @saturation ~w(runs_finished_while_export_held finite_retention finite_batch loss_observed complete_local_accounting accepted_callbacks_completed observer_saw_bound cleanup)
  @package_common [
    "test consumer runtime contains only requested optional applications",
    "test one-shot, typed tool, lazy stream and ETS checkpoint restore from package",
    "test typed invalid input has zero effects and is not coerced",
    "test Ecto remains the final structured-output authority",
    "test model failure is one rich partial error in sync and stream"
  ]

  def c0_manifest, do: @c0
  def eval_manifest, do: @evals

  def c0(%{"probes" => probes}) when is_map(probes) do
    check(keys(probes) == keys(@c0), "C0 probe manifest") ++
      Enum.flat_map(@c0, fn {name, criteria} ->
        probe = Map.get(probes, name, %{})

        check(is_map(probe) and not Map.has_key?(probe, "probe_error"), "#{name}: probe_error") ++
          true_fields(probe, criteria, name)
      end)
  end

  def c0(_), do: ["C0 missing probes"]

  def evals(%{"cases" => cases}) when is_list(cases) do
    check(Enum.sort(Enum.map(cases, &field(&1, "name"))) == keys(@evals), "eval case manifest") ++
      Enum.flat_map(cases, &eval_case/1)
  end

  def evals(_), do: ["eval missing cases"]

  def eval_case(%{"name" => name, "criteria" => criteria}) do
    case Map.fetch(@evals, name) do
      {:ok, required} -> criteria_errors(criteria, required, name)
      :error -> ["unknown eval case: #{inspect(name)}"]
    end
  end

  def eval_case(_), do: ["eval missing name/criteria"]

  def package_names(mode) when mode in ~w(none api sdk exporter) do
    route =
      if mode in ~w(sdk exporter),
        do: "test app-owned native SDK exports package scenarios through its configured route",
        else: "test processor explicitly reports absent SDK"

    Enum.sort([route | @package_common])
  end

  def package_result(%{stats: stats, tests: tests}, mode) when is_map(stats) and is_list(tests) do
    check(
      Map.take(stats, [:total, :failures, :excluded, :skipped]) ==
        %{total: 6, failures: 0, excluded: 0, skipped: 0},
      "consumer ExUnit totals"
    ) ++
      check(
        Enum.sort(Enum.map(tests, &Map.get(&1, :name))) == package_names(mode),
        "consumer six-name manifest"
      ) ++
      check(
        Enum.all?(tests, &(&1[:module] == "PackageAcceptanceTest" and &1[:state] == nil)),
        "consumer test outcomes"
      )
  end

  def package_result(_, _), do: ["consumer missing structured ExUnit result"]

  def load(%{"rows" => rows, "soaks" => soaks, "preset" => preset, "smoke" => smoke} = report)
      when is_list(rows) and is_list(soaks) and is_map(preset) and is_boolean(smoke) do
    n = if smoke, do: 8, else: 200
    warmup = if smoke, do: 2, else: 32

    expected =
      for kind <- ~w(simple tools delegation),
          c <- [1, 8, 32],
          t <- [false, true],
          do: {"load", kind, c, t}

    soak_expected = for t <- [false, true], do: {"paced_soak", "delegation", 8, t}

    check(Enum.sort(Enum.map(rows, &row_key/1)) == Enum.sort(expected), "load row manifest") ++
      check(
        Enum.sort(Enum.map(soaks, &row_key/1)) == Enum.sort(soak_expected),
        "load soak manifest"
      ) ++
      check(
        preset["samples"] == n and preset["soak_samples"] == n and preset["warmup"] == warmup and
          preset["concurrency"] == [1, 8, 32] and preset["cases"] == ~w(simple tools delegation),
        "load preset"
      ) ++
      check(
        report["sources_unchanged"] == true and is_map(report["source_sha256"]) and
          map_size(report["source_sha256"]) > 0,
        "load source manifest"
      ) ++
      Enum.flat_map(rows ++ soaks, &load_row(&1, n, warmup)) ++
      saturation(report["saturation"], if(smoke, do: 8, else: 64))
  end

  def load(_), do: ["load missing report/manifest"]

  def load_row(row, n, warmup) when is_map(row) do
    kind = row["case"]

    {requests, tools, spans} =
      Map.get(
        %{"simple" => {1, 0, 2}, "tools" => {2, 1, 5}, "delegation" => {4, 2, 10}},
        kind,
        {0, 0, 0}
      )

    expected_ledger = %{
      "status" => "succeeded",
      "request_count" => requests,
      "tool_calls" => tools,
      "usage_status" => "complete",
      "cost_status" => "unknown",
      "cost_cents" => nil,
      "usage" => %{"input_tokens" => 3 * requests, "output_tokens" => 2 * requests}
    }

    label = inspect(row_key(row))
    tracing = row["tracing"] == true
    expected = if tracing, do: n * spans, else: 0
    before = if tracing, do: warmup * spans, else: 0

    check(
      n > 0 and row["samples"] == n and row["correct"] == n and row["warmup"] == warmup and
        row["warmup_correct"] == true,
      "#{label}: samples/correct"
    ) ++
      latency(row["raw_latency_us"], row["latency_us"], n, label) ++
      check(row["ledger_per_run"] == expected_ledger, "#{label}: ledger") ++
      counters(row["processor_delta"], expected, label <> " delta") ++
      counters(row["processor_before"], before, label <> " warmup") ++
      counters(row["processor_after"], before + expected, label <> " cumulative") ++
      check(
        field(row["cleanup"], "passed") == true and field(row["cleanup"], "task_children") == 0,
        "#{label}: cleanup"
      ) ++
      check(
        not tracing or field(row["cleanup"], "local_exported") == before + expected,
        "#{label}: exporter callback count"
      )
  end

  def load_row(_, _, _), do: ["load malformed row"]

  defp latency(raw, reported, n, label) when is_list(raw) and is_map(reported) do
    valid = length(raw) == n and n > 0 and Enum.all?(raw, &(is_integer(&1) and &1 >= 0))
    # Integer nearest rank, independently recomputed from raw observations.
    expected =
      if valid do
        sorted = Enum.sort(raw)

        Map.new([{"p50", 50}, {"p95", 95}, {"p99", 99}, {"max", 100}], fn {key, p} ->
          {key, Enum.at(sorted, div(n * p + 99, 100) - 1)}
        end)
      end

    check(valid and reported == expected, "#{label}: raw samples/percentiles")
  end

  defp latency(_, _, _, label), do: ["#{label}: missing raw samples/percentiles"]

  defp counters(data, expected, label) do
    check(
      is_map(data) and data["accepted"] == expected and data["exported"] == expected and
        data["dropped_queue_full"] == 0 and data["export_failed"] == 0 and
        data["export_timed_out"] == 0,
      "#{label}: zero-loss counters"
    )
  end

  defp saturation(%{"criteria" => criteria, "held" => held, "final" => final} = data, runs)
       when is_map(held) and is_map(final) do
    criteria_errors(criteria, @saturation, "saturation") ++
      check(
        data["runs"] == runs and held["retained"] == 32 and final["accepted"] == 32 and
          final["dropped_queue_full"] == 2 + runs * 10 - 32 and final["exported"] == 32 and
          final["retained"] == 0 and final["export_failed"] == 0 and
          final["export_timed_out"] == 0,
        "saturation: independent accounting"
      )
  end

  defp saturation(_, _), do: ["saturation missing observations"]

  defp row_key(row),
    do:
      {field(row, "phase"), field(row, "case"), field(row, "concurrency"), field(row, "tracing")}

  defp field(map, key) when is_map(map), do: Map.get(map, key)
  defp field(_, _), do: nil
  defp keys(map), do: map |> Map.keys() |> Enum.sort()
  defp check(true, _), do: []
  defp check(_, label), do: [label]

  defp criteria_errors(criteria, required, label) when is_map(criteria),
    do:
      check(keys(criteria) == Enum.sort(required), "#{label}: criteria manifest") ++
        true_fields(criteria, required, label)

  defp criteria_errors(_, _, label), do: ["#{label}: missing criteria"]

  defp true_fields(map, fields, label),
    do: Enum.flat_map(fields, &check(field(map, &1) === true, "#{label}.#{&1}"))
end
