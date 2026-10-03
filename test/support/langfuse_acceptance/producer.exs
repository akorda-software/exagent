# Private consumer entrypoint. The Python owner chooses preview/live after its
# admission checks. No credential is passed to this VM, its environment or argv.
Code.require_file(System.fetch_env!("LF_ISOLATED_EXPORTER"))
Code.require_file(System.fetch_env!("LF_FLOW_PLUGIN"))
Code.require_file(Path.expand("scenario.exs", __DIR__))
Code.require_file(Path.expand("admission_exporter.exs", __DIR__))

defmodule LangfuseAcceptance.Producer do
  import ExUnit.Assertions
  alias ExAgent.Observability.{BoundedProcessor, OpenTelemetry}
  alias LangfuseAcceptance.Scenario
  @provider :langfuse_acceptance_provider
  @processor :langfuse_acceptance_processor

  def run do
    mode = System.fetch_env!("LF_MODE")
    assert mode in ~w(preview live)
    max_traces = System.fetch_env!("LF_MAX_TRACES") |> String.to_integer()
    assert max_traces in 1..2

    request_profile =
      case System.get_env("LF_REQUEST_PROFILE") do
        nil ->
          nil

        path ->
          [{module, _}] = Code.require_file(path)
          module
      end

    Application.put_env(:opentelemetry, :processors, [])
    Application.put_env(:req_llm, :load_dotenv, false)

    for app <- [:inets, :grpcbox, :opentelemetry, :exagent],
        do: assert(match?({:ok, _}, Application.ensure_all_started(app)))

    assert Application.load(:opentelemetry_exporter) in [
             :ok,
             {:error, {:already_loaded, :opentelemetry_exporter}}
           ]

    assert to_string(Application.spec(:opentelemetry_exporter, :vsn)) == "1.11.0"
    true = Code.ensure_loaded?(:otel_otlp_traces)
    true = Code.ensure_loaded?(:opentelemetry_trace_service)

    if mode == "live" do
      Application.put_env(:otlp_isolated_probe, :transport, %{
        port: System.fetch_env!("LF_GRPC_PORT") |> String.to_integer(),
        observer: self(),
        python: System.fetch_env!("LF_PYTHON"),
        elixir: System.fetch_env!("LF_ELIXIR"),
        beam_path: System.fetch_env!("LF_BEAM_PATH"),
        launcher: System.fetch_env!("LF_VM_LAUNCHER"),
        worker: System.fetch_env!("LF_VM_WORKER"),
        request_profile: request_profile,
        gate: :atomics.new(1, signed: false)
      })
    end

    resource =
      :otel_resource.create(%{
        "service.name" => "exagent-a10-acceptance",
        "test.synthetic" => true,
        "test.false" => false
      })

    # 64 is the finite preview ceiling for detecting an over-budget candidate;
    # live admission still rejects >32 spans or >64KiB for any individual trace.
    config = %{
      name: @processor,
      resource: resource,
      exporter:
        {LangfuseAcceptance.AdmissionExporter,
         %{
           mode: mode,
           observer: self(),
           max_traces: max_traces,
           sentinels: Scenario.sentinels(),
           request_profile: request_profile
         }},
      max_queue_size: 64,
      max_export_batch_size: 64,
      scheduled_delay_ms: 60_000,
      exporting_timeout_ms:
        System.get_env("LF_EXPORT_TIMEOUT_MS", "16000") |> String.to_integer(),
      shutdown_timeout_ms: 1_000
    }

    {:ok, provider} =
      :otel_tracer_provider_sup.start(@provider, resource, %{
        sampler: :always_on,
        id_generator: :otel_id_generator,
        deny_list: [],
        processors: [{BoundedProcessor, config}]
      })

    assert wait(fn -> match?(%{status: :ready}, BoundedProcessor.stats(@processor)) end, 2_000)
    tracer = :otel_tracer_provider.get_tracer(@provider, :exagent, "a10-acceptance", :undefined)
    tracing = OpenTelemetry.new(tracer: tracer)
    groups = if max_traces == 1, do: ["all"], else: ["flow", "recovery"]

    try do
      results = for group <- groups, do: application_trace(tracer, tracing, group)
      scenes = Enum.flat_map(results, & &1.scenes)

      assert Enum.sort(scenes) ==
               Enum.sort(
                 ~w(router parallel delegation corrective_retry checkpoint_failure_retry pause_approve_resume)
               )

      exact = %{
        request_count: Enum.sum(Enum.map(results, & &1.request_count)),
        tool_calls: Enum.sum(Enum.map(results, & &1.tool_calls)),
        effects: Enum.sum(Enum.map(results, & &1.effects))
      }

      assert exact == %{request_count: 12, tool_calls: 6, effects: 4}
      :ok = BoundedProcessor.force_flush(@processor)
      assert_receive {:native_admission, worker, token, within_budget, summary}, 3_000
      before = BoundedProcessor.stats(@processor)
      lossless = before.dropped_queue_full == 0 and before.dropped_invalid == 0
      admitted = within_budget and lossless

      manifest =
        Map.merge(summary, %{
          status: if(admitted, do: "native_admitted", else: "blocked_profile"),
          mode: mode,
          scenes: scenes,
          exact: exact,
          results: results,
          preexport_processor: before,
          source_tar_sha256: System.fetch_env!("LF_TAR_SHA256"),
          wave: System.fetch_env!("LF_WAVE"),
          transport_written: false
        })

      # This complete native admission is persisted before the first network write.
      File.write!(System.fetch_env!("LF_MANIFEST"), Jason.encode!(manifest))
      assert_native(manifest)

      send(
        worker,
        {if(admitted, do: :native_admission_ack, else: :native_admission_reject), token}
      )

      assert wait(
               fn -> BoundedProcessor.stats(@processor).in_flight == 0 end,
               (System.get_env("LF_EXPORT_TIMEOUT_MS", "16000") |> String.to_integer()) + 500
             )

      receipts = drain_receipts([])
      {:ok, final} = BoundedProcessor.shutdown(@processor)

      report = %{
        status:
          if(admitted and final.export_failed == 0,
            do: "native_phase_complete",
            else: "native_phase_failed"
          ),
        mode: mode,
        exact: exact,
        span_count: summary.span_count,
        processor: final,
        transport_receipts: receipts,
        trace_ids: Enum.map(summary.traces, & &1.trace_id),
        prewrite_manifest: System.fetch_env!("LF_MANIFEST"),
        ui_accepted: false,
        c7_restart_between_host_vms: false,
        versions: %{
          elixir: System.version(),
          otp: to_string(:erlang.system_info(:otp_release)),
          erts: to_string(:erlang.system_info(:version)),
          packages:
            Map.new(
              [
                :exagent,
                :opentelemetry,
                :opentelemetry_api,
                :opentelemetry_exporter,
                :grpcbox,
                :mint
              ],
              fn app ->
                {app,
                 case Application.spec(app, :vsn) do
                   nil -> "not_loaded"
                   version -> to_string(version)
                 end}
              end
            )
        }
      }

      if mode == "preview", do: assert(receipts == [])

      if mode == "live" and report.status == "native_phase_complete" do
        assert length(receipts) in 1..8
        assert Enum.all?(receipts, &(&1["group_closed"] and &1["result"] == "ok"))
        assert Enum.sum(Enum.map(receipts, & &1["sent"])) == summary.span_count
      end

      File.write!(System.fetch_env!("LF_NATIVE_REPORT"), Jason.encode!(report))
      IO.puts("NATIVE_A10 " <> report.status)
    after
      :supervisor.terminate_child(:otel_tracer_provider_sup, provider)
    end
  end

  def report_failure(stack) do
    # This VM receives no credentials. Still emit only a fixed code and public
    # source location, never an exception value, request, snapshot or stack dump.
    location =
      Enum.find(stack, fn {module, _, _, _} ->
        module in [__MODULE__, Scenario, LangfuseAcceptance.AdmissionExporter]
      end)

    facts =
      case location do
        {module, function, _, info} ->
          %{module: Atom.to_string(module), function: Atom.to_string(function), line: info[:line]}

        nil ->
          %{}
      end

    IO.puts("NATIVE_A10 failed_private_boundary " <> Jason.encode!(facts))
  end

  defp application_trace(tracer, tracing, group) do
    root =
      :otel_tracer.start_span(%{}, tracer, "exagent.a10.application", %{
        attributes: %{
          "test.synthetic" => true,
          "test.false" => false,
          "langfuse.trace.name" => "exagent-native-a10",
          "exagent.acceptance.group" => group
        }
      })

    token = :otel_ctx.attach(:otel_tracer.set_current_span(%{}, root))

    try do
      context = OpenTelemetry.capture_context()
      Scenario.execute(tracing, context, group)
    after
      :otel_span.end_span(root)
      :otel_ctx.detach(token)
    end
  end

  defp assert_native(manifest) do
    spans = Enum.flat_map(manifest.traces, & &1.spans)
    models = Enum.filter(spans, &(&1.attributes["exagent.operation"] == "model"))
    assert length(models) == 12
    assert length(Enum.uniq_by(models, & &1.attributes["exagent.model_request_id"])) == 12
    assert Enum.all?(models, &(&1.attributes["exagent.usage.accounting_source"] == "model"))

    assert Enum.all?(
             models,
             &(&1.attributes["exagent.usage.input_tokens_semantics"] == "inclusive")
           )

    assert Enum.all?(models, &(&1.attributes["gen_ai.request.model"] == "test"))
    tools = Enum.filter(spans, &(&1.attributes["exagent.operation"] == "tool"))
    assert length(tools) == 7
    assert Enum.count(tools, &(&1.level == "ERROR")) == 1
    checkpoint = Enum.filter(spans, &(&1.attributes["exagent.operation"] == "checkpoint"))
    assert Enum.count(checkpoint, &(&1.attributes["exagent.status"] == "failed")) == 1
    assert Enum.count(checkpoint, &(&1.attributes["exagent.checkpoint.retry"] == true)) == 1
    [delegation] = Enum.filter(spans, &(&1.attributes["exagent.operation"] == "delegation"))
    by_id = Map.new(spans, &{&1.id, &1})
    assert by_id[delegation.parent_id].attributes["exagent.operation"] == "tool"

    assert Enum.count(
             spans,
             &(&1.parent_id == delegation.id and &1.attributes["exagent.operation"] == "run")
           ) == 1

    flow = Enum.flat_map(manifest.results, & &1.parts) |> Enum.find(&Map.has_key?(&1, :roots))
    [router_id, parallel_id] = flow.roots

    [router] =
      Enum.filter(
        spans,
        &(&1.attributes["exagent.run_id"] == router_id and
            &1.attributes["exagent.operation"] == "run")
      )

    [parallel] =
      Enum.filter(
        spans,
        &(&1.attributes["exagent.run_id"] == parallel_id and
            &1.attributes["exagent.operation"] == "run")
      )

    assert Enum.count(
             spans,
             &(&1.parent_id == router.id and &1.attributes["exagent.operation"] == "run")
           ) == 1

    assert Enum.count(
             spans,
             &(&1.parent_id == parallel.id and &1.attributes["exagent.operation"] == "run")
           ) == 2

    paused =
      Enum.filter(
        spans,
        &(&1.attributes["exagent.operation"] == "run" and
            &1.attributes["exagent.status"] == "paused")
      )

    assert [first] = paused
    assert first.level == "DEFAULT"

    assert [resumed] =
             Enum.filter(spans, fn s ->
               s.attributes["exagent.operation"] == "run" and
                 s.attributes["exagent.run_id"] == first.attributes["exagent.run_id"] and
                 s.id != first.id
             end)

    assert resumed.attributes["exagent.status"] == "succeeded"
    assert resumed.attributes["exagent.attempt_id"] != first.attributes["exagent.attempt_id"]

    assert resumed.attributes["exagent.continuation.record_id"] ==
             first.attributes["exagent.continuation.record_id"]

    for trace <- manifest.traces do
      assert trace.resource_attributes["test.synthetic"] === true
      assert trace.resource_attributes["test.false"] === false
    end
  end

  defp drain_receipts(acc) do
    receive do
      {:isolated_receipt, receipt} -> drain_receipts([receipt | acc])
      {:isolated_port, _, _, _, _} -> drain_receipts(acc)
      {:isolated_lease, _} -> drain_receipts(acc)
      {:isolated_group, _} -> drain_receipts(acc)
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp wait(fun, timeout), do: wait_until(fun, System.monotonic_time(:millisecond) + timeout)

  defp wait_until(fun, until) do
    if fun.(),
      do: true,
      else:
        if(System.monotonic_time(:millisecond) >= until,
          do: false,
          else:
            (
              Process.sleep(5)
              wait_until(fun, until)
            )
        )
  end
end

try do
  LangfuseAcceptance.Producer.run()
rescue
  _ ->
    LangfuseAcceptance.Producer.report_failure(__STACKTRACE__)
    System.halt(1)
catch
  _, _ ->
    LangfuseAcceptance.Producer.report_failure(__STACKTRACE__)
    System.halt(1)
end
