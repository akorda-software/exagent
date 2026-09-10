# Invoked by native_otlp_test.exs in a fresh VM with the compiled test code paths.
# Also runnable after compilation:
# EXAGENT_OFFLINE=1 elixir --erl '+S 2:2' -pa '_build/test/lib/*/ebin' \
#   test/support/native_otlp_probe.exs wire
# Scenarios: wire | generic_endpoint | failures | lifecycle

defmodule ExAgent.Test.NativeOTLPProbe do
  import ExUnit.Assertions
  alias ExAgent.Observability.{BoundedProcessor, OpenTelemetry}
  alias ExAgent.Test.NativeOTLPReceiver, as: Receiver
  alias ExAgent.Models.Test, as: TestModel
  alias ExAgent.Message.Part.ToolCall
  require Record
  @span_fields Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @span_fields)
  @scope_keypos Enum.find_index(@span_fields, &(elem(&1, 0) == :instrumentation_scope)) + 2

  @provider :native_otlp_provider
  @processor :native_otlp_processor
  @header "native-otlp-header-sentinel"
  @prompt "native-otlp-prompt-sentinel"
  @argument "native-otlp-argument-sentinel"
  @output "native-otlp-output-sentinel"
  @dependency "native-otlp-dependency-sentinel"
  @model "native-otlp-model-sentinel"
  @pb :opentelemetry_exporter_trace_service_pb

  def boot do
    # Never consult inherited exporter/resource credentials or remote endpoints.
    # This is the child VM's environment only; the parent VM is untouched.
    for {key, _} <- System.get_env(), String.starts_with?(key, "OTEL_") do
      System.delete_env(key)
    end

    Application.put_env(:opentelemetry, :processors, [])
    {:ok, _} = Application.ensure_all_started(:exagent)
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:opentelemetry)
    :ok = Application.load(:opentelemetry_exporter)
    assert to_string(Application.spec(:opentelemetry_exporter, :vsn)) == "1.10.0"
    assert to_string(Application.spec(:opentelemetry, :vsn)) == "1.7.0"
    assert to_string(Application.spec(:opentelemetry_api, :vsn)) == "1.5.0"
  end

  def wire(generic?) do
    with_fixture(generic?, 2000, fn fixture ->
      {agent, effects} = agent(fixture.tracing)
      {:ok, result} = run_agent(agent)
      assert result.output == @output
      assert :atomics.get(effects, 1) == 1
      assert :atomics.get(effects, 2) == 2
      assert BoundedProcessor.force_flush(@processor) == :ok
      {handler, request} = request(fixture.receiver)
      spans = assert_wire(request, fixture.path, result.run_id)
      assert length(spans) == 4
      assert BoundedProcessor.stats(@processor).exported == 0
      reply(handler, 200)
      stats = wait_stats(&(&1.exported == 4))
      assert stats.accepted == 4
      assert stats.retained == 0
      assert stats.batches_exported == 1
      assert stats.export_failed == 0
      assert stats.export_timed_out == 0
      assert :atomics.get(effects, 1) == 1
      report(%{path: request.path, spans: length(spans), stats: stats})
    end)
  end

  def failures do
    for failure <- [401, 403, 429, 503, :close, :delay, :partial_success] do
      with_fixture(false, 1500, fn fixture ->
        {agent, effects} = agent(fixture.tracing)
        {:ok, first} = run_agent(agent)
        :ok = BoundedProcessor.force_flush(@processor)
        {first_handler, first_request} = request(fixture.receiver)
        assert_wire(first_request, fixture.path, first.run_id)

        # Causal barrier: the real httpc request has reached the receiver, which
        # has sent no response. Another run (including its effect) still finishes.
        second_task = Task.async(fn -> run_agent(agent) end)
        {:ok, second} = Task.await(second_task, 1000)
        assert second.output == @output
        assert :atomics.get(effects, 1) == 2
        assert :atomics.get(effects, 2) == 4
        held = BoundedProcessor.stats(@processor)
        assert held.accepted == 8
        assert held.in_flight == 4
        assert held.exported == 0
        assert held.export_failed == 0
        assert held.export_timed_out == 0
        :ok = BoundedProcessor.force_flush(@processor)

        case failure do
          status when is_integer(status) ->
            reply(first_handler, status, "synthetic rejection")

          :close ->
            Receiver.close(first_handler)
            assert_receive {:native_otlp_closed, ^first_handler}, 1000

          :delay ->
            wait_stats(&(&1.export_timed_out == 4))

          :partial_success ->
            body =
              @pb.encode_msg(
                %{partial_success: %{rejected_spans: 4, error_message: "synthetic rejection"}},
                :export_trace_service_response
              )

            assert %{partial_success: %{rejected_spans: 4}} =
                     @pb.decode_msg(body, :export_trace_service_response)

            reply(first_handler, 200, body)
        end

        {second_handler, second_request} = request(fixture.receiver)
        assert_wire(second_request, fixture.path, second.run_id)

        if failure == :delay do
          # A late successful HTTP response cannot turn a timed-out callback into
          # a delivery acknowledgement, nor trigger another execution of the run.
          reply(first_handler, 200)
          assert BoundedProcessor.stats(@processor).export_timed_out == 4
        end

        reply(second_handler, 200)
        stats = wait_stats(&(&1.retained == 0 and &1.status == :ready))
        assert stats.accepted == 8
        assert stats.exported == if(failure == :partial_success, do: 8, else: 4)
        assert stats.export_timed_out == if(failure == :delay, do: 4, else: 0)
        assert stats.export_failed == if(failure in [:delay, :partial_success], do: 0, else: 4)
        assert stats.batches_exported + stats.batches_failed + stats.batches_timed_out == 2
        assert :atomics.get(effects, 1) == 2
        assert :atomics.get(effects, 2) == 4

        # A flush after completion cannot replay either batch. Observe a bounded
        # quiet window only after the causal terminal/counter barrier above.
        :ok = BoundedProcessor.force_flush(@processor)
        refute_receive {:native_otlp_request, _, _, _}, 40
        report(%{failure: failure, effects: 2, requests: 2, stats: stats})
      end)
    end
  end

  def lifecycle do
    {:ok, unrelated} = :inets.start(:httpc, profile: :native_otlp_unrelated)
    {:ok, receiver} = Receiver.start_link()
    port = Receiver.port(receiver)
    configure_exporter("http://127.0.0.1:#{port}", false)
    baseline_profiles = profiles()
    cold = resources(port)
    direct_native_export(receiver)
    stop_profiles(profiles() -- baseline_profiles)
    eventually(fn -> client_sockets(port) == [] end)
    report(%{phase: "native_warmup", cold: cold, warmed: resources(port)})
    baseline = resources(port)

    # Direct native callbacks, no ExAgent processor, isolate profile retention's
    # origin. Each runner exports one SDK record, shuts down normally, then dies.
    for cycle <- 1..3 do
      direct_native_export(receiver)
      assert length(profiles() -- baseline_profiles) == cycle
      eventually(fn -> client_sockets(port) == [] end)
      report(%{phase: "native_shutdown", cycle: cycle, resources: resources(port)})
    end

    stop_profiles(profiles() -- baseline_profiles)
    assert MapSet.new(profiles()) == MapSet.new(baseline_profiles)
    assert Process.alive?(unrelated)

    report(%{
      phase: "native_owned_profile_cleanup",
      baseline: baseline,
      resources: resources(port)
    })

    # The processor deadline bounds its callback, not the native HTTP operation.
    # Observe both ends of TCP while retaining the response, then stop only the
    # profiles this dedicated, serial VM can prove it created.
    bounded_baseline = resources(port)

    for cycle <- 1..3 do
      {:ok, processor, config} = BoundedProcessor.start_link(processor_config(250))
      wait_stats(&(&1.status == :ready))
      state = :sys.get_state(processor)
      old_worker = state.worker
      old_monitor = Process.monitor(old_worker)
      owned = processor_processes(processor, state)
      assert BoundedProcessor.on_end(native_span(), config) == true
      assert BoundedProcessor.force_flush(config) == :ok
      {handler, _request} = request(receiver)
      assert length(client_sockets(port)) == 1
      worker_tables = Enum.filter(:ets.all(), &(:ets.info(&1, :owner) == old_worker))
      assert worker_tables != []
      before_timeout = resources(port)

      assert_receive {:DOWN, ^old_monitor, :process, ^old_worker, :killed}, 1500
      timed_out = wait_stats(&(&1.export_timed_out == 1 and &1.status == :ready))
      assert timed_out.exported == 0
      assert timed_out.retained == 0
      assert Enum.all?(worker_tables, &(:ets.info(&1) == :undefined))
      restarted_state = :sys.get_state(processor)
      assert restarted_state.worker != old_worker
      owned = Enum.uniq(owned ++ processor_processes(processor, restarted_state))

      # Private state inspection above measures our own processes/tables only.
      # Native profile discovery/cleanup below uses public OTP service APIs.
      assert length(profiles() -- baseline_profiles) == 2
      assert length(client_sockets(port)) == 1
      refute_receive {:native_otlp_peer_closed, ^handler}, 20
      after_timeout = resources(port)
      assert {:ok, final} = BoundedProcessor.shutdown(config)
      assert final.export_timed_out == 1
      eventually(fn -> Enum.all?(owned, &(not Process.alive?(&1))) end)
      assert :ets.info(state.handle.table) == :undefined
      assert :persistent_term.get({BoundedProcessor, @processor}, nil) == nil

      # Shutdown has removed ExAgent's resources but neither native profile nor
      # the still-outstanding client socket. This is a characterization, not a
      # claim that killing a runner cancels HTTP at either peer.
      assert length(profiles() -- baseline_profiles) == 2
      assert length(client_sockets(port)) == 1
      after_shutdown = resources(port)

      if cycle == 1 do
        # OTP29 profile shutdown alone removes the manager's ETS, not the
        # independently supervised in-flight handler. Preserve this failed
        # cleanup attempt as an explicit negative control.
        [{_, _, http_handler}] = outstanding_requests(profiles() -- baseline_profiles)
        http_monitor = Process.monitor(http_handler)
        stop_profiles(profiles() -- baseline_profiles)
        assert Process.alive?(http_handler)
        assert length(client_sockets(port)) == 1
        refute_receive {:native_otlp_peer_closed, ^handler}, 20
        report(%{phase: "profile_stop_is_not_request_cancellation", resources: resources(port)})
        Receiver.close(handler)
        assert_receive {:native_otlp_closed, ^handler}, 1000
        assert_receive {:DOWN, ^http_monitor, :process, ^http_handler, _}, 1000
      else
        # Public cancellation, with IDs observed BEFORE removing exclusively
        # owned profiles. info/1 is a version-specific debugging interface, not
        # a portable ownership API to embed in ExAgent's generic processor.
        cancel_requests(profiles() -- baseline_profiles)
        assert_receive {:native_otlp_peer_closed, ^handler}, 1000
        stop_profiles(profiles() -- baseline_profiles)
      end

      eventually(fn -> client_sockets(port) == [] end)
      assert MapSet.new(profiles()) == MapSet.new(baseline_profiles)
      assert Process.alive?(unrelated)

      report(%{
        phase: "bounded_timeout_restart_shutdown",
        cycle: cycle,
        before_timeout: before_timeout,
        after_timeout: after_timeout,
        after_shutdown: after_shutdown,
        after_owned_profile_cleanup: resources(port),
        owned_processes_recovered: length(owned),
        stats: final
      })
    end

    assert MapSet.new(profiles()) == MapSet.new(baseline_profiles)
    assert Process.alive?(unrelated)
    report(%{phase: "lifecycle_final", baseline: bounded_baseline, resources: resources(port)})
    Receiver.stop(receiver)
    stop_profiles([{unrelated, :native_otlp_unrelated}])
  end

  defp direct_native_export(receiver) do
    owner = self()

    {runner, ref} =
      spawn_monitor(fn ->
        {:ok, state} = :opentelemetry_exporter.init(%{})
        table = :ets.new(:native_otlp_direct, [:duplicate_bag, {:keypos, @scope_keypos}])
        true = :ets.insert(table, native_span())
        send(owner, {:native_direct_table, self(), table})
        :ok = :opentelemetry_exporter.export(table, resource(), state)
        :ok = :opentelemetry_exporter.shutdown(state)
        send(owner, {:native_direct_shutdown, self()})
      end)

    assert_receive {:native_direct_table, ^runner, table}, 1000
    {handler, request} = request(receiver)
    assert_native_types(request)
    reply(handler, 200)
    assert_receive {:native_direct_shutdown, ^runner}, 1000
    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}, 1000
    assert :ets.info(table) == :undefined
  end

  defp native_span do
    now = :opentelemetry.timestamp()

    span(
      trace_id: 1,
      span_id: 2,
      name: "native-lifecycle",
      kind: :internal,
      start_time: now,
      end_time: now,
      attributes:
        :otel_attributes.new(
          %{
            "test.true" => true,
            "test.false" => false,
            "test.string" => "control",
            "test.int" => 17
          },
          128,
          :infinity
        ),
      events: :otel_events.new(128, 128, :infinity),
      links: :otel_links.new([], 128, 128, :infinity),
      instrumentation_scope:
        :opentelemetry.instrumentation_scope(:exagent, "native-lifecycle", :undefined)
    )
  end

  defp assert_native_types(request) do
    assert %{resource_spans: [%{resource: resource, scope_spans: [%{spans: [exported]}]}]} =
             @pb.decode_msg(request.body, :export_trace_service_request)

    # Direct native export confirms this affects both span/resource values,
    # independently of ExAgent. Keep the string/int controls typed and exact.
    assert :otel_attributes.map(span(native_span(), :attributes))["test.true"] == true
    assert :otel_attributes.map(span(native_span(), :attributes))["test.false"] == false
    assert typed_attributes(exported)["test.true"] == {:string_value, "true"}
    assert typed_attributes(exported)["test.false"] == {:string_value, "false"}
    assert typed_attributes(exported)["test.string"] == {:string_value, "control"}
    assert typed_attributes(exported)["test.int"] == {:int_value, 17}
    assert :otel_attributes.map(:otel_resource.attributes(resource()))[:"test.synthetic"] == true
    assert typed_attributes(resource)["test.synthetic"] == {:string_value, "true"}
  end

  defp typed_attributes(%{attributes: attrs}) do
    Map.new(attrs, fn %{key: key, value: %{value: value}} -> {key, value} end)
  end

  defp processor_processes(pid, state) do
    guards =
      for worker <- [state.worker, state.observer],
          {:monitored_by, monitors} = Process.info(worker, :monitored_by),
          monitor <- monitors,
          monitor not in [self(), pid],
          do: monitor

    [pid, state.worker, state.observer | guards]
  end

  defp client_sockets(port) do
    Enum.filter(:erlang.ports(), fn socket ->
      case :inet.peername(socket) do
        {:ok, {{127, 0, 0, 1}, ^port}} -> true
        _ -> false
      end
    end)
  end

  defp resources(port) do
    pids = Process.list()

    monitors =
      Enum.reduce(pids, 0, fn pid, count ->
        case Process.info(pid, :monitors) do
          {:monitors, list} -> count + length(list)
          nil -> count
        end
      end)

    %{
      processes: length(pids),
      monitors: monitors,
      ets: length(:ets.all()),
      ports: length(:erlang.ports()),
      client_sockets: length(client_sockets(port)),
      httpc_profiles: length(profiles()),
      atoms: :erlang.system_info(:atom_count),
      httpc_handler_processes: length(:supervisor.which_children(:httpc_handler_sup)),
      httpc_handlers:
        Enum.reduce(profiles(), 0, fn {_, profile}, sum ->
          sum + length(Keyword.get(:httpc.info(profile), :handlers, []))
        end)
    }
  end

  defp outstanding_requests(profiles) do
    for {_, profile} <- profiles,
        {handler, requests, _info} <- Keyword.get(:httpc.info(profile), :handlers, []),
        request <- requests,
        do: {profile, request, handler}
  end

  defp cancel_requests(profiles) do
    for {profile, request, handler} <- outstanding_requests(profiles) do
      monitor = Process.monitor(handler)
      assert :httpc.cancel_request(request, profile) == :ok
      assert_receive {:DOWN, ^monitor, :process, ^handler, _}, 1000
    end
  end

  defp with_fixture(generic?, timeout, fun) do
    baseline_profiles = profiles()
    {:ok, receiver} = Receiver.start_link()
    path = if generic?, do: "/synthetic/v1/traces", else: "/synthetic/ingest"
    base = "http://127.0.0.1:#{Receiver.port(receiver)}"
    configure_exporter(base, generic?)
    {provider, tracing} = start_provider(timeout)

    try do
      fun.(%{receiver: receiver, path: path, tracing: tracing})
    after
      :supervisor.terminate_child(:otel_tracer_provider_sup, provider)
      cancel_requests(profiles() -- baseline_profiles)
      stop_profiles(profiles() -- baseline_profiles)
      Receiver.stop(receiver)
    end
  end

  defp configure_exporter(base, generic?) do
    Application.delete_env(:opentelemetry_exporter, :otlp_endpoint)
    Application.delete_env(:opentelemetry_exporter, :otlp_traces_endpoint)
    key = if generic?, do: :otlp_endpoint, else: :otlp_traces_endpoint
    path = if generic?, do: "/synthetic", else: "/synthetic/ingest"
    Application.put_env(:opentelemetry_exporter, key, base <> path)
    Application.put_env(:opentelemetry_exporter, :otlp_protocol, :http_protobuf)

    Application.put_env(:opentelemetry_exporter, :otlp_traces_headers, [
      {"x-synthetic-auth", @header}
    ])

    Application.put_env(:opentelemetry_exporter, :ssl_options, [])
  end

  defp resource,
    do: :otel_resource.create(%{"service.name" => "native-otlp-test", "test.synthetic" => true})

  defp processor_config(timeout) do
    %{
      name: @processor,
      resource: resource(),
      exporter: {:opentelemetry_exporter, %{}},
      max_queue_size: 32,
      max_export_batch_size: 16,
      scheduled_delay_ms: 60_000,
      exporting_timeout_ms: timeout,
      shutdown_timeout_ms: 500
    }
  end

  defp start_provider(timeout) do
    config = %{
      sampler: :always_on,
      id_generator: :otel_id_generator,
      deny_list: [],
      processors: [{BoundedProcessor, processor_config(timeout)}]
    }

    {:ok, provider} = :otel_tracer_provider_sup.start(@provider, resource(), config)
    wait_stats(&(&1.status == :ready))
    tracer = :otel_tracer_provider.get_tracer(@provider, :exagent, "native-otlp-test", :undefined)
    {provider, OpenTelemetry.new(tracer: tracer)}
  end

  defp agent(tracing) do
    effects = :atomics.new(2, [])

    tool =
      ExAgent.Tool.new(
        name: "record_effect",
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"value" => %{"type" => "string"}}
        },
        call: fn ctx, %{"value" => @argument} ->
          assert ctx.deps.private == @dependency
          :atomics.add(effects, 1, 1)
          @output
        end
      )

    agent =
      ExAgent.new(
        observability: tracing,
        tools: [tool],
        model: %TestModel{
          label: @model,
          script: [
            fn messages, _ ->
              assert Enum.any?(messages, fn message ->
                       Enum.any?(
                         message.parts,
                         &match?(%ExAgent.Message.Part.User{content: @prompt}, &1)
                       )
                     end)

              :atomics.add(effects, 2, 1)

              {:tool_calls,
               [
                 %ToolCall{
                   tool_name: "record_effect",
                   tool_call_id: "synthetic-call",
                   args: %{"value" => @argument}
                 }
               ]}
            end,
            fn messages, _ ->
              assert Enum.any?(messages, fn message ->
                       Enum.any?(
                         message.parts,
                         &match?(%ExAgent.Message.Part.ToolReturn{content: @output}, &1)
                       )
                     end)

              :atomics.add(effects, 2, 1)
              @output
            end
          ]
        }
      )

    {agent, effects}
  end

  defp run_agent(agent) do
    assert agent.model.label == @model
    assert {:ok, result} = ExAgent.run(agent, @prompt, deps: %{private: @dependency})
    assert result.model.label == @model
    {:ok, result}
  end

  defp request(receiver) do
    assert_receive {:native_otlp_request, ^receiver, handler, request}, 3000
    {handler, request}
  end

  defp reply(handler, status, body \\ <<>>) do
    Receiver.reply(handler, status, body)
    assert_receive {:native_otlp_replied, ^handler, :ok}, 1000
  end

  defp assert_wire(request, path, run_id) do
    assert request.method == :POST
    assert request.version == {1, 1}
    assert request.path == path
    assert request.headers["content-type"] == "application/x-protobuf"
    assert request.headers["x-synthetic-auth"] == @header
    assert request.headers["user-agent"] == "OTel-OTLP-Exporter-erlang/1.10.0"

    for sentinel <- [@header, @prompt, @argument, @output, @dependency, @model] do
      refute request.body =~ sentinel
    end

    assert %{resource_spans: [resource_spans]} =
             @pb.decode_msg(request.body, :export_trace_service_request)

    assert attributes(resource_spans.resource)["service.name"] == "native-otlp-test"
    # Boolean type fidelity is characterized separately by assert_native_types/1.
    assert [%{scope: scope, spans: spans} = scope_spans] = resource_spans.scope_spans
    assert scope.name == "exagent"
    assert scope.version == "native-otlp-test"
    assert Map.get(scope_spans, :schema_url, "") == ""
    assert length(spans) == 4

    by_operation = Enum.group_by(spans, &attributes(&1)["exagent.operation"])
    assert [run] = by_operation["run"]
    assert [tool] = by_operation["tool"]
    assert length(by_operation["model"]) == 2
    assert run.parent_span_id == <<>>
    assert byte_size(run.trace_id) == 16
    refute run.trace_id == <<0::128>>
    assert length(Enum.uniq_by(spans, & &1.span_id)) == 4
    assert attributes(run)["exagent.run_id"] == run_id
    assert attributes(run)["exagent.usage.request_count"] == 2
    assert attributes(run)["exagent.usage.tool_calls"] == 1
    refute Map.has_key?(attributes(run), "gen_ai.usage.input_tokens")
    assert attributes(tool)["exagent.tool_call_id"] == "synthetic-call"

    for span <- spans do
      attrs = attributes(span)
      assert byte_size(span.span_id) == 8
      refute span.span_id == <<0::64>>
      assert span.trace_id == run.trace_id
      assert span.end_time_unix_nano >= span.start_time_unix_nano
      assert attrs["exagent.profile"] == "exagent.gen_ai.v1"
      assert attrs["exagent.status"] == "succeeded"
      refute Enum.any?(Map.keys(attrs), &String.starts_with?(&1, "exagent.content."))
      if span != run, do: assert(span.parent_span_id == run.span_id)
    end

    for span <- by_operation["model"] do
      assert attributes(span)["gen_ai.request.model"] == "test"
      assert attributes(span)["gen_ai.usage.input_tokens"] == 1
      assert attributes(span)["gen_ai.usage.output_tokens"] == 1
    end

    spans
  end

  defp attributes(%{attributes: attrs}) do
    Map.new(attrs, fn %{key: key, value: %{value: {_type, value}}} -> {key, value} end)
  end

  defp wait_stats(predicate) do
    eventually(fn ->
      case BoundedProcessor.stats(@processor) do
        %{} = stats -> if predicate.(stats), do: stats
        _ -> nil
      end
    end)
  end

  defp eventually(fun, remaining \\ 600)
  defp eventually(fun, 0), do: assert(fun.(), "condition did not become true")

  defp eventually(fun, remaining) do
    case fun.() do
      value when value in [false, nil] ->
        Process.sleep(5)
        eventually(fun, remaining - 1)

      value ->
        value
    end
  end

  defp profiles do
    for {:httpc, pid, info} <- :inets.services_info(), do: {pid, Keyword.fetch!(info, :profile)}
  end

  # Safe ONLY in this dedicated VM: it serially owns every new profile observed
  # during fixture setup/export. Never infer ownership from a global diff in an
  # application that may concurrently start unrelated services.
  defp stop_profiles(profiles) do
    for {pid, _} <- profiles do
      ref = Process.monitor(pid)
      assert :inets.stop(:httpc, pid) == :ok
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
    end
  end

  defp report(value), do: IO.puts("NATIVE_OTLP_EVIDENCE " <> Jason.encode!(value))
end

# A VM-local watchdog bounds even a broken fixture. It cannot affect the parent
# test VM or any service on the host, and the VM's OS resources die with it.
spawn(fn ->
  receive do
  after
    20_000 ->
      IO.puts(:stderr, "native OTLP probe watchdog expired")
      System.halt(2)
  end
end)

[scenario] = System.argv()
ExAgent.Test.NativeOTLPProbe.boot()

case scenario do
  "wire" -> ExAgent.Test.NativeOTLPProbe.wire(false)
  "generic_endpoint" -> ExAgent.Test.NativeOTLPProbe.wire(true)
  "failures" -> ExAgent.Test.NativeOTLPProbe.failures()
  "lifecycle" -> ExAgent.Test.NativeOTLPProbe.lifecycle()
end

IO.puts("NATIVE_OTLP_OK #{scenario}")
