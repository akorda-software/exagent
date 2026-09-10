# Compiled project/support paths, disposable VM, no Mix/dependency mutation:
# EXAGENT_OFFLINE=1 elixir --erl '+S 2:2' -pa '_build/test/lib/*/ebin' \
#   test/support/native_otlp_scenario_probe.exs composed
# Scenarios: composed | queued_failures | privacy
# Reuses the frozen N01 TCP receiver and C6's deterministic Test model, public
# capabilities, delegation and runtime APIs. No second transport implementation.

defmodule ExAgent.Test.NativeOTLPScenarioProbe do
  import ExUnit.Assertions
  alias ExAgent.Observability.{BoundedProcessor, OpenTelemetry}
  alias ExAgent.Test.NativeOTLPReceiver, as: Receiver
  alias ExAgent.Models.Test, as: TestModel
  alias ExAgent.Message.{Part, Request, Response, Usage}
  alias ExAgent.{Server, Tool, RunError}

  @provider :native_otlp_scenario_provider
  @processor :native_otlp_scenario_processor
  @logger_keys [:otel_trace_id, :otel_span_id, :otel_trace_flags]
  @sentinels Map.new(
               [
                 :prompt,
                 :argument,
                 :result,
                 :output,
                 :dependency,
                 :model,
                 :error,
                 :header,
                 :baggage
               ],
               &{&1, "N04_N12_PRIVATE_#{&1}_9d0a"}
             )

  def sentinel(key), do: Map.fetch!(@sentinels, key)

  defmodule Observe do
    use ExAgent.Capability
    import ExUnit.Assertions
    alias ExAgent.Test.NativeOTLPScenarioProbe, as: Probe

    def before_model_request(_, state) do
      assert state.deps.private == Probe.sentinel(:dependency)
      assert state.model.label == Probe.sentinel(:model)
      if state.observability, do: Probe.assert_active_context(state.deps)
      :atomics.add(state.deps.counts, 2, 1)
      state
    end

    def after_model_request(_, state) do
      if state.deps[:record_generations] do
        send(
          state.deps.owner,
          {:generation_identity, state.deps.counts, state.run_id, state.run_step,
           state.model_request_id}
        )
      end

      if state.deps[:fail_after_model] == true and state.run_step == 2 do
        assert ExAgent.Message.Response.text(List.last(state.messages)) == Probe.sentinel(:output)
        send(state.deps.owner, {:after_model_observed, Probe.sentinel(:error)})
        raise Probe.sentinel(:error)
      end

      state
    end
  end

  defmodule FailingOnceStore do
    def load_agent_snapshot(_, _), do: {:error, :not_found}

    def save_agent_snapshot(state, snapshot) do
      Agent.get_and_update(state, fn {count, owner} ->
        send(owner, {:scenario_saved, snapshot})

        result =
          if count == 0,
            do: {:error, ExAgent.Test.NativeOTLPScenarioProbe.sentinel(:error)},
            else: :ok

        {result, {count + 1, owner}}
      end)
    end
  end

  defmodule LogSink do
    def log(event, %{config: %{owner: owner}}), do: send(owner, {:scenario_log, event})
  end

  def boot do
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

    :ok =
      :logger.add_handler(:native_otlp_scenario_logs, LogSink, %{
        level: :all,
        config: %{owner: self()}
      })

    :ok =
      :telemetry.attach_many(
        :native_otlp_scenario_diagnostics,
        [
          [:exagent, :observability, :failure],
          [:exagent, :observability, :content_dropped],
          [:exagent, :observability, :processor]
        ],
        &__MODULE__.diagnostic/4,
        self()
      )
  end

  def diagnostic(event, measurements, metadata, owner),
    do: send(owner, {:scenario_diagnostic, event, measurements, metadata})

  def composed do
    with_fixture(fn fixture ->
      # Compare the same ledger/execution with tracing off and on, rather than
      # treating the trace projection as an independent source of billing truth.
      baseline = composed_run(nil, nil)

      {observed, caller} =
        in_caller(fixture.tracer, "composed", fn _ ->
          composed_run(fixture.tracing, fixture.tracer)
        end)

      assert observed.result.usage == baseline.result.usage
      assert observed.result.cost_cents == baseline.result.cost_cents
      assert observed.estimates == baseline.estimates
      assert observed.requests == baseline.requests
      assert observed.effects == baseline.effects
      assert observed.result.request_count == 4
      assert observed.result.tool_calls == 3
      assert observed.result.usage.input_tokens == 43
      assert observed.result.usage.output_tokens == 8
      assert_in_delta observed.result.cost_cents, 0.51, 0.000001
      assert observed.effects == 1
      assert observed.corrections == 2
      assert observed.summaries == 3
      assert observed.deltas > 1

      spans = collect(fixture, 16)

      assert counts(spans) == %{
               nil => 1,
               "run" => 2,
               "model" => 4,
               "tool" => 3,
               "delegation" => 1,
               "compaction" => 3,
               "checkpoint" => 2
             }

      assert Enum.all?(spans, &(&1.trace_id == trace_id(caller)))
      root = Enum.find(kind(spans, :run), &(&1.attrs["exagent.run_id"] == observed.result.run_id))
      child = Enum.find(kind(spans, :run), &(&1.id != root.id))
      [delegation] = kind(spans, :delegation)
      delegate = Enum.find(kind(spans, :tool), &(&1.attrs["gen_ai.tool.name"] == "delegate"))
      assert root.parent_id == span_id(caller)
      assert root.attrs["exagent.status"] == "failed"
      assert child.attrs["exagent.status"] == "succeeded"
      assert delegation.parent_id == delegate.id
      assert child.parent_id == delegation.id
      assert child.attrs["exagent.parent_run_id"] == observed.result.run_id
      assert child.attrs["exagent.root_run_id"] == observed.result.run_id
      assert Enum.all?(kind(spans, :tool), &(&1.parent_id == root.id))

      assert Enum.count(kind(spans, :tool), &(&1.attrs["exagent.status"] == "validation_error")) ==
               1

      for model <- kind(spans, :model) do
        parent = if model.attrs["exagent.run_id"] == observed.result.run_id, do: root, else: child
        assert model.parent_id == parent.id
        assert model.attrs["exagent.model_request_id"] != nil
        assert model.attrs["gen_ai.request.model"] == "test"
        assert model.attrs["exagent.status"] == "succeeded"

        for {key, value} <- model.attrs, String.starts_with?(key, "gen_ai.usage.") do
          assert model.types[key] == {:int_value, value}
        end
      end

      assert length(Enum.uniq_by(kind(spans, :model), & &1.attrs["exagent.model_request_id"])) ==
               4

      assert Enum.sum(Enum.map(kind(spans, :model), & &1.attrs["gen_ai.usage.input_tokens"])) ==
               43

      assert Enum.sum(Enum.map(kind(spans, :model), & &1.attrs["gen_ai.usage.output_tokens"])) ==
               8

      assert_in_delta Enum.sum(Enum.map(kind(spans, :model), & &1.attrs["exagent.cost.cents"])),
                      0.51,
                      0.000001

      assert root.attrs["exagent.usage.input_tokens"] == 43
      assert child.attrs["exagent.usage.input_tokens"] == 5

      assert root.attrs["exagent.usage.output_tokens"] == 8
      assert child.attrs["exagent.usage.output_tokens"] == 2
      assert_in_delta child.attrs["exagent.cost.cents"], 0.07, 0.000001

      # Correlate a fixture-authored table through public hook identities, never
      # through sorting spans or reusing their reported usage as the expectation.
      assert_generation_accounting(spans, observed.generations, %{
        {observed.result.run_id, 1} => {10, 2, 0.12, %{cache_read: 4}},
        {observed.result.run_id, 2} => {8, 1, 0.09, %{}},
        {observed.result.run_id, 3} => {20, 3, 0.23, %{cache_read: 8, cache_write: 2}},
        {child.attrs["exagent.run_id"], 1} => {5, 2, 0.07, %{cache_read: 2, reasoning: 1}}
      })

      for span <- spans -- kind(spans, :model) do
        refute Map.has_key?(span.attrs, "gen_ai.usage.input_tokens")
        refute Map.has_key?(span.attrs, "gen_ai.usage.output_tokens")
      end

      for compact <- kind(spans, :compaction) do
        assert compact.parent_id == root.id
        # Known 1.10 boolean type loss, deliberately not a bool fidelity claim.
        assert compact.attrs["exagent.compaction.changed"] in ["true", "false"]
      end

      [changed] =
        Enum.filter(kind(spans, :compaction), &(&1.attrs["exagent.compaction.changed"] == "true"))

      assert changed.attrs["exagent.compaction.output_messages"] <
               changed.attrs["exagent.compaction.input_messages"]

      [failed] = Enum.filter(kind(spans, :checkpoint), &(&1.attrs["exagent.status"] == "failed"))

      [retry] =
        Enum.filter(kind(spans, :checkpoint), &(&1.attrs["exagent.status"] == "succeeded"))

      assert failed.parent_id == root.id
      assert failed.end_time <= root.end_time
      assert retry.parent_id == span_id(caller)
      assert retry.attrs["exagent.checkpoint.retry"] == "true"
      assert retry.start_time >= root.end_time
      refute Enum.any?(spans, &String.contains?(&1.name, "delta"))
      assert :atomics.get(observed.counts, 3) == observed.estimates
      assert_private_diagnostics()

      report(%{
        scenario: :composed,
        spans: length(spans),
        requests: observed.requests,
        effects: observed.effects,
        summary_callbacks: observed.summaries,
        changed_compactions: 1,
        deltas: observed.deltas,
        estimator_calls_disabled: baseline.estimates,
        estimator_calls_enabled: observed.estimates,
        cost_cents: observed.result.cost_cents
      })
    end)
  end

  def queued_failures do
    with_fixture(fn fixture ->
      owner = self()
      a_counts = :atomics.new(3, [])
      b_counts = :atomics.new(3, [])
      sequence = :atomics.new(1, [])

      script = fn messages, _ ->
        case :atomics.add_get(sequence, 1, 1) do
          1 ->
            assert_user(messages, sentinel(:prompt))

            response_parts(
              [call("effect", "queued-effect", %{"value" => sentinel(:argument)})],
              10,
              2,
              %{cached_tokens: 4}
            )

          2 ->
            assert_user(messages, sentinel(:prompt))
            send(owner, {:queued_blocked, self()})
            receive do: (:never -> response("unreachable", 1, 1))

          3 ->
            assert_user(messages, sentinel(:prompt) <> " B")
            response(sentinel(:output), 3, 1)
        end
      end

      agent =
        ExAgent.new(
          model: %TestModel{label: sentinel(:model), script: [script, script]},
          tools: [effect_tool()],
          capabilities: [Observe],
          observability: fixture.tracing
        )

      id = "native_queued_#{System.unique_integer([:positive])}"
      :ok = ExAgent.PubSub.Local.subscribe([], ExAgent.Event.agent_topic(id))
      {:ok, server} = Server.start_link(agent: agent, agent_id: id, pubsub: :local, store: :ets)

      {{:ok, first_id}, first_caller} =
        in_caller(fixture.tracer, "caller_a", fn parent ->
          Server.send_message(server, sentinel(:prompt),
            deps:
              Map.merge(deps(a_counts, "a"), %{
                expected_trace: trace_id(parent),
                record_generations: true
              }),
            estimate_cost: estimator(a_counts)
          )
        end)

      assert_receive {:queued_blocked, worker}, 2000
      monitor = Process.monitor(worker)
      before_abort = :sys.get_state(server).current.progress
      estimates_before_abort = :atomics.get(a_counts, 3)
      assert before_abort.request_count == 1
      assert before_abort.usage.input_tokens == 10
      assert before_abort.usage.output_tokens == 2
      assert_in_delta before_abort.cost_cents, 0.12, 0.000001

      {{:ok, second_id}, second_caller} =
        in_caller(fixture.tracer, "caller_b", fn parent ->
          Server.send_message(server, sentinel(:prompt) <> " B",
            deps:
              Map.merge(deps(b_counts, "b"), %{
                expected_trace: trace_id(parent),
                record_generations: true
              }),
            estimate_cost: estimator(b_counts)
          )
        end)

      assert Server.health(server).pending == 1
      assert trace_id(first_caller) != trace_id(second_caller)
      assert :ok = Server.abort(server)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2000

      assert_receive {:exagent_event,
                      %ExAgent.Event{
                        type: :server_request_cancelled,
                        request_id: ^first_id,
                        payload: %{partial: partial}
                      }},
                     2000

      assert_receive {:exagent_event,
                      %ExAgent.Event{type: :run_finished, request_id: ^second_id}},
                     2000

      assert :atomics.get(a_counts, 1) == 1
      assert :atomics.get(a_counts, 2) == 2
      assert :atomics.get(a_counts, 3) == estimates_before_abort
      assert :atomics.get(b_counts, 1) == 0
      assert :atomics.get(b_counts, 2) == 1
      assert partial.usage_status == :partial
      assert partial.usage["input_tokens"] == 10
      assert partial.usage["output_tokens"] == 2
      assert partial.cost_status == :unknown
      assert partial.cost_cents == before_abort.cost_cents
      assert Server.health(server).status == :idle
      assert clean_server_context?(server)
      GenServer.stop(server)

      spans = collect(fixture, 10)

      assert counts(spans) == %{
               nil => 2,
               "run" => 2,
               "model" => 3,
               "tool" => 1,
               "checkpoint" => 2
             }

      first = Enum.find(kind(spans, :run), &(&1.attrs["exagent.request_id"] == first_id))
      second = Enum.find(kind(spans, :run), &(&1.attrs["exagent.request_id"] == second_id))
      assert first.parent_id == span_id(first_caller)
      assert second.parent_id == span_id(second_caller)
      assert first.trace_id == trace_id(first_caller)
      assert second.trace_id == trace_id(second_caller)
      assert first.trace_id != second.trace_id
      assert first.attrs["exagent.status"] == "cancelled"
      assert first.attrs["exagent.usage.status"] == "partial"
      assert first.attrs["exagent.usage.input_tokens"] == 10
      assert first.attrs["exagent.usage.output_tokens"] == 2
      assert first.attrs["exagent.usage.source"] == "last_progress"
      assert first.attrs["exagent.cost.status"] == "unknown"
      refute Map.has_key?(first.attrs, "exagent.cost.cents")
      assert_in_delta first.attrs["exagent.cost.known_subtotal_cents"], 0.12, 0.000001
      assert second.attrs["exagent.status"] == "succeeded"
      assert second.attrs["exagent.usage.input_tokens"] == 3
      assert second.attrs["exagent.usage.output_tokens"] == 1
      assert_in_delta second.attrs["exagent.cost.cents"], 0.04, 0.000001

      for span <- kind(spans, :model) ++ kind(spans, :tool) ++ kind(spans, :checkpoint) do
        run = if span.trace_id == first.trace_id, do: first, else: second
        assert span.trace_id == run.trace_id
        assert span.parent_id == run.id
      end

      [incomplete] =
        Enum.filter(kind(spans, :model), &(&1.attrs["exagent.status"] == "cancelled"))

      assert incomplete.attrs["exagent.usage.status"] == "partial"
      refute Map.has_key?(incomplete.attrs, "gen_ai.usage.output_tokens")

      refute Enum.any?(incomplete.attrs, fn {key, _} ->
               String.starts_with?(key, "gen_ai.usage.cache_")
             end)

      assert_generation_accounting(
        spans,
        generation_ids(a_counts, 1) ++ generation_ids(b_counts, 1),
        %{
          {first.attrs["exagent.run_id"], 1} => {10, 2, 0.12, %{cache_read: 4}},
          {second.attrs["exagent.run_id"], 1} => {3, 1, 0.04, %{}}
        }
      )

      report(%{
        scenario: :queued_abort,
        spans: length(spans),
        traces: 2,
        effects: 1,
        known_subtotal_cents: 0.12,
        cost_status: :unknown
      })

      after_hook_failure(fixture)
      assert_private_diagnostics()
    end)
  end

  defp after_hook_failure(fixture) do
    counts = :atomics.new(3, [])

    agent =
      ExAgent.new(
        observability: fixture.tracing,
        capabilities: [Observe],
        tools: [effect_tool()],
        model: %TestModel{
          label: sentinel(:model),
          script: [
            response_parts(
              [call("effect", "hook-effect", %{"value" => sentinel(:argument)})],
              10,
              2
            ),
            response(sentinel(:output), 2, 1)
          ]
        }
      )

    {{:error, %RunError{reason: reason, partial: partial}}, parent} =
      in_caller(fixture.tracer, "after_hook", fn _ ->
        ExAgent.run(agent, sentinel(:prompt),
          deps:
            Map.merge(deps(counts, "hook"), %{fail_after_model: true, record_generations: true}),
          estimate_cost: estimator(counts),
          on_progress: fn progress ->
            assert progress.model.label == sentinel(:model)
            send(self(), :rich_progress_observed_model)
          end
        )
      end)

    assert {:execution_failed, %RuntimeError{message: error}} = reason
    assert error == sentinel(:error)
    assert_receive {:after_model_observed, ^error}, 1000
    assert_receive :rich_progress_observed_model, 1000
    assert :atomics.get(counts, 1) == 1
    assert :atomics.get(counts, 2) == 2
    assert partial.usage_status == :complete
    assert partial.usage.input_tokens == 12
    assert partial.usage.output_tokens == 3
    assert partial.cost_status == :known
    assert_in_delta partial.cost_cents, 0.15, 0.000001

    assert Enum.any?(
             parts(partial.new_messages),
             &match?(%Part.ToolReturn{status: :succeeded, tool_call_id: "hook-effect"}, &1)
           )

    estimates = :atomics.get(counts, 3)
    spans = collect(fixture, 5)
    [run] = kind(spans, :run)
    [tool] = kind(spans, :tool)
    assert run.parent_id == span_id(parent)
    assert run.attrs["exagent.status"] == "failed"
    assert run.attrs["error.type"] != nil
    assert tool.attrs["exagent.status"] == "succeeded"
    assert Enum.all?(kind(spans, :model), &(&1.attrs["exagent.status"] == "succeeded"))
    assert Enum.all?(spans, &(&1.trace_id == trace_id(parent)))
    assert_in_delta run.attrs["exagent.cost.cents"], 0.15, 0.000001
    assert run.attrs["exagent.usage.input_tokens"] == 12
    assert run.attrs["exagent.usage.output_tokens"] == 3

    assert_generation_accounting(spans, generation_ids(counts, 2), %{
      {partial.run_id, 1} => {10, 2, 0.12, %{}},
      {partial.run_id, 2} => {2, 1, 0.03, %{}}
    })

    assert :atomics.get(counts, 3) == estimates

    report(%{
      scenario: :after_model_hook_failure,
      spans: length(spans),
      effects: 1,
      requests: 2,
      confirmed_cost_cents: 0.15
    })
  end

  def privacy do
    with_fixture(fn fixture ->
      for {mode, tenant} <- [
            {:off, "off"},
            {:stateful, "redactor_a"},
            {:stateful, "redactor_b"},
            {:raise, "raise"},
            {:oversize_return, "oversize_return"},
            {:oversize_input, "oversize_input"}
          ] do
        owner = self()
        count = :atomics.new(1, [])
        observations = :ets.new(:scenario_redaction_observations, [:set, :public])

        redactor = fn field, value ->
          current = :otel_tracer.current_span_ctx()
          assert current != :undefined
          assert Logger.metadata()[:otel_trace_id] == :otel_span.hex_trace_id(current)
          assert :otel_ctx.get_value(:baggage) == :undefined
          number = :atomics.add_get(count, 1, 1)
          allowed = "#{tenant}-#{number}-#{field}"
          true = :ets.insert(observations, {number, field, value, allowed, trace_id(current)})

          case mode do
            :raise -> raise sentinel(:error)
            :oversize_return -> {:ok, sentinel(:output) <> String.duplicate("x", 80)}
            _ -> {:ok, allowed}
          end
        end

        tracing =
          if mode == :off,
            do: fixture.tracing,
            else:
              OpenTelemetry.new(
                tracer: fixture.tracer,
                content: true,
                redact: redactor,
                max_content_bytes: 64,
                max_content_input_bytes: if(mode == :oversize_input, do: 8, else: 4096)
              )

        counts = :atomics.new(3, [])
        agent = privacy_agent(tracing)

        {{:ok, result}, parent} =
          in_caller(fixture.tracer, tenant, fn span ->
            ExAgent.run(agent, sentinel(:prompt),
              deps: Map.put(deps(counts, tenant), :expected_trace, trace_id(span)),
              on_progress: fn progress ->
                assert progress.model.label == sentinel(:model)
                send(owner, {:rich_model_observed, tenant})
              end,
              on_event: fn
                %ExAgent.RunEvent{type: :tool_call_started, data: %{args: args}} ->
                  assert args == %{"value" => sentinel(:argument)}
                  send(owner, {:rich_args_observed, tenant})

                _ ->
                  :ok
              end
            )
          end)

        assert result.output == sentinel(:output)
        assert result.model.label == sentinel(:model)
        assert_receive {:rich_model_observed, ^tenant}, 1000
        assert_receive {:rich_args_observed, ^tenant}, 1000
        assert :atomics.get(counts, 1) == 1
        assert :atomics.get(counts, 2) == 2
        spans = collect(fixture, 5)
        assert Enum.all?(spans, &(&1.trace_id == trace_id(parent)))

        content =
          for span <- spans,
              {key, value} <- span.attrs,
              String.starts_with?(key, "exagent.content."),
              do: value

        seen = :ets.tab2list(observations)
        drops = assert_private_diagnostics()

        case mode do
          :off ->
            assert seen == []
            assert content == []
            assert drops == 0

          :stateful ->
            # Run/tool plus both model requests each expose bounded input/output.
            assert length(seen) == 8
            assert length(content) == 8
            assert MapSet.new(content) == MapSet.new(Enum.map(seen, &elem(&1, 3)))
            assert Enum.any?(seen, &(elem(&1, 2) == sentinel(:prompt)))
            assert Enum.any?(seen, &(elem(&1, 2) == %{"value" => sentinel(:argument)}))
            assert Enum.any?(seen, &(elem(&1, 2) == sentinel(:result)))
            assert Enum.any?(seen, &(elem(&1, 2) == sentinel(:output)))
            assert Enum.all?(seen, &(elem(&1, 4) == trace_id(parent)))
            assert Enum.all?(content, &String.starts_with?(&1, tenant <> "-"))
            assert drops == 0

          :oversize_input ->
            assert [{1, :output, "", allowed, _}] = seen
            assert content == [allowed]
            assert drops == 7

          failure when failure in [:raise, :oversize_return] ->
            assert length(seen) == 8
            assert content == []
            assert drops == 8
        end

        report(%{
          scenario: :privacy,
          mode: mode,
          caller: tenant,
          spans: length(spans),
          redactor_calls: length(seen),
          permitted_attributes: length(content),
          content_dropped: drops
        })

        :ets.delete(observations)
      end

      empty_context(fixture)
      abrupt_owner_cleanup(fixture)
      assert_private_diagnostics()
    end)
  end

  defp privacy_agent(tracing) do
    ExAgent.new(
      observability: tracing,
      tools: [effect_tool()],
      capabilities: [Observe],
      model: %TestModel{
        label: sentinel(:model),
        script: [
          fn messages, _ ->
            assert_user(messages, sentinel(:prompt))

            response_parts(
              [call("effect", "private-effect", %{"value" => sentinel(:argument)})],
              1,
              1
            )
          end,
          fn messages, _ ->
            assert Enum.any?(parts(messages), fn
                     %Part.ToolReturn{content: value} -> value == sentinel(:result)
                     _ -> false
                   end)

            response(sentinel(:output), 1, 1)
          end
        ]
      }
    )
  end

  defp empty_context(fixture) do
    empty = OpenTelemetry.capture_context()
    counts = :atomics.new(3, [])

    agent =
      ExAgent.new(
        observability: fixture.tracing,
        capabilities: [Observe],
        model: %TestModel{
          label: sentinel(:model),
          script: [
            fn messages, _ ->
              assert_user(messages, sentinel(:prompt))
              response(sentinel(:output), 1, 1)
            end
          ]
        }
      )

    {{:ok, result}, parent} =
      in_caller(fixture.tracer, "empty_context", fn parent ->
        prior_keys = Logger.metadata() |> Keyword.take(@logger_keys) |> Map.new()

        result =
          OpenTelemetry.with_context(empty, fn ->
            assert :otel_tracer.current_span_ctx() == :undefined
            assert Keyword.take(Logger.metadata(), @logger_keys) == []
            assert Logger.metadata()[:tenant] == "empty_context"
            Logger.metadata(application_change: "preserved")
            result = ExAgent.run(agent, sentinel(:prompt), deps: deps(counts, "empty"))
            assert :otel_tracer.current_span_ctx() == :undefined
            assert Keyword.take(Logger.metadata(), @logger_keys) == []
            result
          end)

        assert :otel_tracer.current_span_ctx() == parent
        assert Logger.metadata() |> Keyword.take(@logger_keys) |> Map.new() == prior_keys
        assert Logger.metadata()[:application_change] == "preserved"
        result
      end)

    assert result.output == sentinel(:output)
    spans = collect(fixture, 3)
    [run] = kind(spans, :run)
    [model] = kind(spans, :model)
    assert run.parent_id == <<>>
    assert run.trace_id != trace_id(parent)
    assert model.parent_id == run.id
    assert model.trace_id == run.trace_id

    report(%{
      scenario: :empty_context,
      spans: length(spans),
      traces: 2,
      logger_change_preserved: true
    })
  end

  defp abrupt_owner_cleanup(fixture) do
    owner = self()
    counts = :atomics.new(3, [])

    tool =
      Tool.new(
        name: "block",
        parameters_json_schema: object_schema(),
        call: fn ctx, args ->
          assert ctx.deps.private == sentinel(:dependency)
          assert ctx.model.label == sentinel(:model)
          assert args == %{"value" => sentinel(:argument)}
          assert_active_context(ctx.deps)
          :atomics.add(counts, 1, 1)
          send(owner, {:abrupt_tool_entered, self()})
          receive do: (:never -> sentinel(:result))
        end
      )

    agent =
      ExAgent.new(
        observability: fixture.tracing,
        tools: [tool],
        capabilities: [Observe],
        model: %TestModel{
          label: sentinel(:model),
          script: [
            response_parts(
              [call("block", "abrupt-effect", %{"value" => sentinel(:argument)})],
              1,
              1
            )
          ]
        }
      )

    {_, parent} =
      in_caller(fixture.tracer, "abrupt", fn parent ->
        context = OpenTelemetry.capture_context()
        run_deps = Map.put(deps(counts, "abrupt"), :expected_trace, trace_id(parent))

        {runner, monitor} =
          spawn_monitor(fn ->
            OpenTelemetry.with_context(context, fn ->
              ExAgent.run(agent, sentinel(:prompt), deps: run_deps)
            end)
          end)

        assert_receive {:abrupt_tool_entered, tool_pid}, 2000
        tool_monitor = Process.monitor(tool_pid)
        Process.exit(runner, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^runner, :killed}, 2000
        assert_receive {:DOWN, ^tool_monitor, :process, ^tool_pid, _}, 2000
        assert :atomics.get(counts, 1) == 1
        assert :atomics.get(counts, 2) == 1
      end)

    spans = collect(fixture, 4)
    assert counts(spans) == %{nil => 1, "run" => 1, "model" => 1, "tool" => 1}
    assert Enum.all?(spans, &(&1.trace_id == trace_id(parent)))
    [run] = kind(spans, :run)
    [model] = kind(spans, :model)
    [tool] = kind(spans, :tool)
    assert run.attrs["exagent.status"] == "cancelled"
    assert tool.attrs["exagent.status"] == "cancelled"
    assert model.attrs["exagent.status"] == "succeeded"
    assert tool.parent_id == run.id
    assert model.parent_id == run.id
    assert :atomics.get(counts, 1) == 1

    report(%{
      scenario: :abrupt_owner,
      spans: length(spans),
      effects: 1,
      runner_and_tool_down: true
    })
  end

  defp effect_tool do
    Tool.new(
      name: "effect",
      parameters_json_schema: object_schema(),
      call: fn ctx, args ->
        assert args == %{"value" => sentinel(:argument)}
        assert ctx.deps.private == sentinel(:dependency)
        assert ctx.model.label == sentinel(:model)
        assert_active_context(ctx.deps)
        :atomics.add(ctx.deps.counts, 1, 1)
        sentinel(:result)
      end
    )
  end

  defp composed_run(tracing, _tracer) do
    owner = self()
    counts = :atomics.new(5, [])
    deps = Map.put(deps(counts, "composed"), :record_generations, true)

    echo =
      Tool.new(
        name: "echo",
        parameters_json_schema: object_schema(),
        call: fn ctx, args ->
          assert args == %{"value" => sentinel(:argument)}
          assert ctx.deps.private == sentinel(:dependency)
          assert ctx.model.label == sentinel(:model)
          if tracing, do: assert_active_context(ctx.deps)
          attempt = :atomics.add_get(counts, 4, 1)

          if attempt == 1 do
            send(owner, {:parallel_ready, :echo, self()})
            receive do: (:continue -> :ok)
            raise ExAgent.ModelRetry, sentinel(:error)
          end

          :atomics.add(counts, 1, 1)
          sentinel(:result)
        end
      )

    child =
      ExAgent.new(
        model: %TestModel{
          label: sentinel(:model),
          script: [
            fn messages, _ ->
              assert_user(messages, sentinel(:prompt))
              send(owner, {:parallel_ready, :child, self()})
              receive do: (:continue -> :ok)
              response(sentinel(:result), 5, 2, %{cached_tokens: 2, reasoning_tokens: 1})
            end
          ]
        },
        capabilities: [Observe]
      )

    compact = %ExAgent.Compaction.Capability{
      compactor: ExAgent.Compaction.Summary,
      opts: [
        threshold_tokens: 0,
        keep_recent: 0,
        summarize: fn old ->
          assert_user(old, "old synthetic history")
          # Compact old history once, then preserve the live correction/tool
          # exchange. keep_recent: 0 alone would intentionally summarize it too.
          if :atomics.add_get(counts, 5, 1) == 1,
            do: "bounded synthetic summary",
            else: {:no_change}
        end
      ]
    }

    history = [
      %Request{parts: [%Part.User{content: "old synthetic history"}]},
      response("old synthetic output", 1, 1)
    ]

    agent =
      ExAgent.new(
        observability: tracing,
        capabilities: [compact, Observe],
        tools: [echo, ExAgent.Coordination.delegation_tool(child)],
        model: %TestModel{
          label: sentinel(:model),
          script: [
            fn messages, _ ->
              assert_user(messages, sentinel(:prompt))

              response_parts(
                [
                  call("echo", "echo-1", %{"value" => sentinel(:argument)}),
                  call("delegate", "delegate-1", %{"prompt" => sentinel(:prompt)})
                ],
                10,
                2,
                %{cached_tokens: 4}
              )
            end,
            fn messages, _ ->
              assert Enum.any?(
                       parts(messages),
                       &match?(
                         %Part.ToolReturn{tool_call_id: "echo-1", status: :validation_error},
                         &1
                       )
                     )

              response_parts([call("echo", "echo-2", %{"value" => sentinel(:argument)})], 8, 1)
            end,
            fn messages, _ ->
              assert Enum.any?(parts(messages), fn
                       %Part.ToolReturn{content: value} -> value == sentinel(:result)
                       _ -> false
                     end)

              response(sentinel(:output) <> " streamed words", 20, 3, %{
                cached_tokens: 8,
                cache_creation_input_tokens: 2
              })
            end
          ]
        }
      )

    {:ok, store} = Agent.start_link(fn -> {0, owner} end)
    {:ok, server} = Server.start_link(agent: agent, store: {FailingOnceStore, store})
    context = OpenTelemetry.capture_context()
    deltas = :atomics.new(1, [])
    deps = Map.put(deps, :on_text_delta, fn _ -> :atomics.add(deltas, 1, 1) end)

    task =
      Task.async(fn ->
        OpenTelemetry.with_context(context, fn ->
          Server.chat(server, sentinel(:prompt),
            message_history: history,
            stream_text: true,
            deps: deps,
            estimate_cost: estimator(counts)
          )
        end)
      end)

    assert_receive {:parallel_ready, :echo, echo_pid}, 2000
    assert_receive {:parallel_ready, :child, child_pid}, 2000
    assert echo_pid != child_pid
    send(echo_pid, :continue)
    send(child_pid, :continue)

    assert {:error, %ExAgent.CheckpointError{reason: reason, revision: 1, result: {:ok, result}}} =
             Task.await(task, 5000)

    assert reason == sentinel(:error)
    assert result.output == sentinel(:output) <> " streamed words"
    assert Enum.take(result.messages, 2) == history
    assert_receive {:scenario_saved, first}, 1000
    before_retry = :atomics.get(counts, 3)
    assert :ok = Server.checkpoint(server)
    assert_receive {:scenario_saved, second}, 1000
    assert Map.delete(first, :saved_at) == Map.delete(second, :saved_at)
    assert :atomics.get(counts, 3) == before_retry
    assert clean_server_context?(server)
    GenServer.stop(server)
    Agent.stop(store)

    %{
      result: result,
      generations: generation_ids(counts, 4),
      counts: counts,
      effects: :atomics.get(counts, 1),
      requests: :atomics.get(counts, 2),
      estimates: before_retry,
      corrections: :atomics.get(counts, 4),
      summaries: :atomics.get(counts, 5),
      deltas: :atomics.get(deltas, 1)
    }
  end

  def assert_active_context(deps) do
    context = :otel_tracer.current_span_ctx()
    assert context != :undefined
    assert :otel_ctx.get_value(:baggage) == :undefined
    metadata = Logger.metadata()
    assert metadata[:otel_trace_id] == :otel_span.hex_trace_id(context)
    assert metadata[:otel_span_id] == :otel_span.hex_span_id(context)
    if deps[:expected_trace], do: assert(trace_id(context) == deps.expected_trace)
    :ok
  end

  defp deps(counts, tenant),
    do: %{owner: self(), private: sentinel(:dependency), counts: counts, tenant: tenant}

  defp estimator(counts),
    do: fn usage ->
      :atomics.add(counts, 3, 1)
      (usage.input_tokens + usage.output_tokens) / 100
    end

  defp generation_ids(counts, count) do
    for _ <- 1..count do
      assert_receive {:generation_identity, ^counts, run_id, step, request_id}, 1000
      assert is_binary(request_id)
      {{run_id, step}, request_id}
    end
  end

  defp assert_generation_accounting(spans, identities, expected) do
    assert Enum.sort(Enum.map(identities, &elem(&1, 0))) == Enum.sort(Map.keys(expected))
    assert length(Enum.uniq_by(identities, &elem(&1, 1))) == map_size(expected)
    models = Enum.filter(kind(spans, :model), &(&1.attrs["exagent.status"] == "succeeded"))
    assert length(models) == map_size(expected)

    expected_by_request =
      Map.new(identities, fn {{run_id, _} = key, request_id} ->
        {{run_id, request_id}, Map.fetch!(expected, key)}
      end)

    assert Enum.sort(
             Enum.map(models, &{&1.attrs["exagent.run_id"], &1.attrs["exagent.model_request_id"]})
           ) ==
             Enum.sort(Map.keys(expected_by_request))

    for model <- models do
      key = {model.attrs["exagent.run_id"], model.attrs["exagent.model_request_id"]}
      {input, output, cost, details} = Map.fetch!(expected_by_request, key)

      expected_usage =
        Map.new(details, fn
          {:cache_read, n} -> {"gen_ai.usage.cache_read.input_tokens", n}
          {:cache_write, n} -> {"gen_ai.usage.cache_write.input_tokens", n}
          {:reasoning, n} -> {"exagent.usage.reasoning_tokens", n}
        end)
        |> Map.merge(%{
          "gen_ai.usage.input_tokens" => input,
          "gen_ai.usage.output_tokens" => output
        })

      actual_usage =
        Map.filter(model.attrs, fn {name, _} ->
          String.starts_with?(name, "gen_ai.usage.") or name == "exagent.usage.reasoning_tokens"
        end)

      assert actual_usage == expected_usage, "generation accounting #{inspect(key)}"
      assert_in_delta model.attrs["exagent.cost.cents"], cost, 0.000001
    end
  end

  defp object_schema,
    do: %{"type" => "object", "properties" => %{"value" => %{"type" => "string"}}}

  defp call(name, id, args),
    do: %Part.ToolCall{tool_name: name, tool_call_id: id, args: args}

  defp response(text, input, output, details \\ %{}),
    do: response_parts([%Part.Text{content: text}], input, output, details)

  defp response_parts(parts, input, output, details \\ %{}),
    do: %Response{
      parts: parts,
      usage: %Usage{input_tokens: input, output_tokens: output, details: details}
    }

  defp parts(messages), do: Enum.flat_map(messages, & &1.parts)

  defp assert_user(messages, content),
    do: assert(Enum.any?(parts(messages), &match?(%Part.User{content: ^content}, &1)))

  defp trace_id(span), do: <<:otel_span.trace_id(span)::128>>
  defp span_id(span), do: <<:otel_span.span_id(span)::64>>

  defp kind(spans, kind),
    do: Enum.filter(spans, &(&1.attrs["exagent.operation"] == to_string(kind)))

  defp counts(spans), do: Enum.frequencies_by(spans, & &1.attrs["exagent.operation"])

  defp in_caller(tracer, tenant, fun) do
    old_context = :otel_ctx.get_current()
    old_keys = Logger.metadata() |> Keyword.take(@logger_keys)
    Logger.metadata(tenant: tenant)
    parent = :otel_tracer.start_span(%{}, tracer, "caller " <> tenant, %{})

    native =
      :otel_tracer.set_current_span(%{}, parent)
      |> :otel_ctx.set_value(:baggage, %{private: sentinel(:baggage)})

    result =
      OpenTelemetry.with_context(%OpenTelemetry.Context{native: native}, fn ->
        assert :otel_ctx.get_value(:baggage) == %{private: sentinel(:baggage)}
        captured = OpenTelemetry.capture_context()
        assert :otel_ctx.get_value(captured.native, :baggage, :undefined) == :undefined
        result = fun.(parent)
        assert :otel_tracer.current_span_ctx() == parent
        assert Logger.metadata()[:tenant] == tenant
        result
      end)

    :otel_span.end_span(parent)
    assert :otel_ctx.get_current() == old_context
    assert Logger.metadata() |> Keyword.take(@logger_keys) == old_keys
    {result, parent}
  end

  defp clean_server_context?(server) do
    owner = self()
    ref = make_ref()

    :sys.replace_state(server, fn state ->
      send(owner, {ref, :otel_tracer.current_span_ctx(), Logger.metadata()})
      state
    end)

    assert_receive {^ref, context, metadata}, 1000
    context == :undefined and Keyword.take(metadata, @logger_keys) == []
  end

  defp with_fixture(fun) do
    old_profiles = :inets.services()
    {:ok, receiver} = Receiver.start_link()

    Application.put_env(
      :opentelemetry_exporter,
      :otlp_traces_endpoint,
      "http://127.0.0.1:#{Receiver.port(receiver)}/scenario/v1/traces"
    )

    Application.put_env(:opentelemetry_exporter, :otlp_protocol, :http_protobuf)

    Application.put_env(:opentelemetry_exporter, :otlp_traces_headers, [
      {"x-synthetic-auth", sentinel(:header)}
    ])

    Application.put_env(:opentelemetry_exporter, :ssl_options, [])
    resource = :otel_resource.create(%{"service.name" => "native-otlp-scenario"})

    config = %{
      sampler: :always_on,
      id_generator: :otel_id_generator,
      deny_list: [],
      processors: [
        {BoundedProcessor,
         %{
           name: @processor,
           resource: resource,
           exporter: {:opentelemetry_exporter, %{}},
           max_queue_size: 256,
           max_export_batch_size: 128,
           scheduled_delay_ms: 60_000,
           exporting_timeout_ms: 3000,
           shutdown_timeout_ms: 500
         }}
      ]
    }

    {:ok, provider} = :otel_tracer_provider_sup.start(@provider, resource, config)
    eventually(fn -> BoundedProcessor.stats(@processor).status == :ready end)
    tracer = :otel_tracer_provider.get_tracer(@provider, :exagent, "native-scenario", :undefined)

    try do
      fun.(%{receiver: receiver, tracer: tracer, tracing: OpenTelemetry.new(tracer: tracer)})
    after
      :supervisor.terminate_child(:otel_tracer_provider_sup, provider)
      # This VM alone serially owns the newly created profiles. Normal scenarios
      # finish every request before cleanup; N03 separately covers timeout limits.
      for {:httpc, pid} <- :inets.services() -- old_profiles, do: :inets.stop(:httpc, pid)
      Receiver.stop(receiver)
    end
  end

  defp collect(fixture, expected) do
    prior = BoundedProcessor.stats(@processor).exported
    eventually(fn -> BoundedProcessor.stats(@processor).accepted == prior + expected end)
    :ok = BoundedProcessor.force_flush(@processor)
    assert_receive {:native_otlp_request, receiver, handler, request}, 3000
    assert receiver == fixture.receiver
    assert request.method == :POST
    assert request.path == "/scenario/v1/traces"
    assert request.headers["content-type"] == "application/x-protobuf"
    assert request.headers["x-synthetic-auth"] == sentinel(:header)
    for secret <- Map.values(@sentinels), do: refute(request.body =~ secret)

    assert %{
             resource_spans: [
               %{resource: resource, scope_spans: [%{scope: scope, spans: raw} = scoped]}
             ]
           } =
             :opentelemetry_exporter_trace_service_pb.decode_msg(
               request.body,
               :export_trace_service_request
             )

    assert attrs(resource)["service.name"] == "native-otlp-scenario"
    assert scope.name == "exagent"
    assert scope.version == "native-scenario"
    assert Map.get(scoped, :schema_url, "") == ""
    assert length(raw) == expected

    spans =
      Enum.map(
        raw,
        &%{
          id: &1.span_id,
          trace_id: &1.trace_id,
          parent_id: &1.parent_span_id,
          name: &1.name,
          attrs: attrs(&1),
          types: types(&1),
          start_time: &1.start_time_unix_nano,
          end_time: &1.end_time_unix_nano
        }
      )

    assert length(Enum.uniq_by(spans, & &1.id)) == expected

    for span <- spans do
      assert byte_size(span.id) == 8 and span.id != <<0::64>>
      assert byte_size(span.trace_id) == 16 and span.trace_id != <<0::128>>
      assert span.start_time <= span.end_time

      if span.attrs["exagent.operation"],
        do: assert(span.attrs["exagent.profile"] == "exagent.gen_ai.v1")
    end

    Receiver.reply(handler, 200)
    assert_receive {:native_otlp_replied, ^handler, :ok}, 1000
    eventually(fn -> BoundedProcessor.stats(@processor).exported == prior + expected end)
    assert BoundedProcessor.stats(@processor).retained == 0
    assert BoundedProcessor.stats(@processor).export_failed == 0
    assert BoundedProcessor.stats(@processor).export_timed_out == 0
    spans
  end

  defp attrs(%{attributes: attrs}),
    do: Map.new(attrs, fn %{key: key, value: %{value: {_, value}}} -> {key, value} end)

  defp types(%{attributes: attrs}),
    do: Map.new(attrs, fn %{key: key, value: %{value: value}} -> {key, value} end)

  defp assert_private_diagnostics(drops \\ 0) do
    receive do
      {:scenario_log, value} ->
        for secret <- Map.values(@sentinels),
            do: refute(inspect(value, limit: :infinity, printable_limit: :infinity) =~ secret)

        assert_private_diagnostics(drops)

      {:scenario_diagnostic, event, measurements, metadata} ->
        for secret <- Map.values(@sentinels),
            do:
              refute(
                inspect({event, measurements, metadata},
                  limit: :infinity,
                  printable_limit: :infinity
                ) =~ secret
              )

        dropped =
          if event == [:exagent, :observability, :content_dropped],
            do: measurements.count,
            else: 0

        assert_private_diagnostics(drops + dropped)
    after
      20 -> drops
    end
  end

  defp eventually(fun, remaining \\ 600)
  defp eventually(fun, 0), do: assert(fun.(), "scenario barrier timed out")

  defp eventually(fun, remaining) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(5)
          eventually(fun, remaining - 1)
        )
  end

  defp report(value), do: IO.puts("NATIVE_OTLP_SCENARIO_EVIDENCE " <> Jason.encode!(value))
end

spawn(fn ->
  receive do
  after
    30_000 ->
      IO.puts(:stderr, "native OTLP scenario watchdog expired")
      System.halt(2)
  end
end)

[scenario] = System.argv()
ExAgent.Test.NativeOTLPScenarioProbe.boot()

case scenario do
  "composed" -> ExAgent.Test.NativeOTLPScenarioProbe.composed()
  "queued_failures" -> ExAgent.Test.NativeOTLPScenarioProbe.queued_failures()
  "privacy" -> ExAgent.Test.NativeOTLPScenarioProbe.privacy()
end

IO.puts("NATIVE_OTLP_SCENARIO_OK #{scenario}")
