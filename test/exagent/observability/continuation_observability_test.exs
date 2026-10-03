defmodule ExAgent.Observability.ContinuationObservabilityTest do
  use ExUnit.Case, async: false
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  alias ExAgent.{Continuation, Permissions, Server, Store, Tool}
  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Observability.OpenTelemetry, as: OTel
  @provider :continuation_observability_test

  defmodule Processor do
    def on_start(_, span, _), do: span

    def on_end(span, owner) do
      send(owner, {:closed_span, span})
      true
    end

    def force_flush(_), do: :ok
  end

  defmodule PauseFaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(table, key), do: Store.ETS.load_record(table, key)
    def scan_records(table, ns, query), do: Store.ETS.scan_records(table, ns, query)
    def transition(_, _, _, %{"operation" => "pause"}), do: {:error, :save_failed}

    def transition(table, key, revision, command),
      do: Store.ETS.transition(table, key, revision, command)
  end

  setup_all do
    old = Application.get_env(:opentelemetry, :processors)
    Application.put_env(:opentelemetry, :processors, [])
    {:ok, started} = Application.ensure_all_started(:opentelemetry)

    on_exit(fn ->
      if :opentelemetry in started, do: Application.stop(:opentelemetry)

      if old == nil,
        do: Application.delete_env(:opentelemetry, :processors),
        else: Application.put_env(:opentelemetry, :processors, old)
    end)

    :ok
  end

  setup do
    :otel_ctx.clear()
    resource = :otel_resource.create(%{})

    config = %{
      sampler: :always_on,
      id_generator: :otel_id_generator,
      deny_list: [],
      processors: [{Processor, self()}]
    }

    {:ok, provider} = :otel_tracer_provider_sup.start(@provider, resource, config)
    on_exit(fn -> :supervisor.terminate_child(:otel_tracer_provider_sup, provider) end)
    tracer = :otel_tracer_provider.get_tracer(@provider, :exagent, "1", :undefined)
    start_supervised!({Store.ETS, table: __MODULE__})
    %{tracing: OTel.new(tracer: tracer), store: Store.scoped({Store.ETS, __MODULE__}, "otel-c7")}
  end

  for mode <- [:sync, :stream, :server] do
    @tag mode: mode
    test "#{mode}: durable pause and resume close one run span per attempt without replay", ctx do
      mode = ctx.mode
      agent = agent(self(), ctx.tracing)
      opts = [continuation: config(ctx.store), permissions: Permissions.new!(default: :ask)]

      {paused, resume} =
        if mode == :server do
          server =
            start_supervised!(
              {Server,
               agent: agent,
               agent_id: "conversation",
               namespace: "otel-c7",
               store: {Store.ETS, __MODULE__},
               continuation: Map.drop(config(ctx.store), [:store, :id])}
            )

          {:ok, paused} = Server.chat(server, "private-prompt", opts)
          {paused, fn _reference -> Server.resume(server, opts) end}
        else
          paused =
            if mode == :sync do
              {:ok, paused} = ExAgent.run(agent, "private-prompt", opts)
              paused
            else
              events = Enum.to_list(ExAgent.run_stream(agent, "private-prompt", opts))
              assert {:result, paused} = List.last(events)
              paused
            end

          {paused,
           fn reference ->
             if mode == :stream do
               assert {:result, result} =
                        ExAgent.resume_stream(agent, reference, opts)
                        |> Enum.to_list()
                        |> List.last()

               {:ok, result}
             else
               ExAgent.resume(agent, reference, opts)
             end
           end}
        end

      assert paused.status == :paused
      assert paused.request_count == 1
      assert paused.tool_calls == 1
      assert_receive :model_first
      refute_receive :effect, 0
      first_spans = closed_spans()
      [first] = runs(first_spans)
      assert first.attrs["exagent.status"] == "paused"
      assert first.attrs["exagent.attempt_id"] == paused.attempt_id
      assert first.end_time > first.start_time
      refute first.attrs["error.type"]
      refute match?({:status, :error, _}, first.status)
      assert first.attrs["exagent.usage.request_count"] == 1
      assert first.attrs["exagent.usage.tool_calls"] == 1
      assert first.attrs["exagent.continuation.record_id"] == paused.continuation.record_id
      assert first.attrs["exagent.continuation.revision"] == paused.continuation.revision
      assert first.attrs["exagent.continuation.id"] == "conversation"

      {:ok, %{record: pending}} = Continuation.get(ctx.store, "conversation")

      {:ok, %{record: approved}} =
        Continuation.decide(ctx.store, "conversation", :approve, decision(pending))

      assert closed_spans() == []
      reference = %{paused.continuation | revision: approved["revision"]}
      assert {:ok, result} = resume.(reference)
      assert result.status == :succeeded
      assert result.run_id == paused.run_id
      assert result.attempt_id != paused.attempt_id
      assert result.continuation.record_id == paused.continuation.record_id
      assert result.request_count == 2
      assert result.tool_calls == 1
      assert_receive :effect
      assert_receive :model_second
      refute_receive :model_first, 0
      refute_receive :effect, 0
      second_spans = closed_spans()
      [second] = runs(second_spans)
      assert second.id != first.id
      assert second.attrs["exagent.status"] == "succeeded"
      assert second.attrs["exagent.run_id"] == first.attrs["exagent.run_id"]
      assert second.attrs["exagent.attempt_id"] == result.attempt_id

      assert second.attrs["exagent.continuation.record_id"] ==
               first.attrs["exagent.continuation.record_id"]

      assert second.attrs["exagent.usage.request_count"] == 2
      assert second.attrs["exagent.usage.tool_calls"] == 1

      assert Enum.count(first_spans ++ second_spans, &(&1.attrs["exagent.operation"] == "model")) ==
               2

      refute inspect(first_spans ++ second_spans) =~ "private-"
    end
  end

  test "pause persistence failure closes failed, without a false durable pause", ctx do
    store = Store.scoped({PauseFaultStore, __MODULE__}, "otel-c7")

    assert {:error, _} =
             ExAgent.run(agent(self(), ctx.tracing), "private-prompt",
               continuation: config(store),
               permissions: Permissions.new!(default: :ask)
             )

    assert_receive :model_first
    refute_receive :effect, 0
    [run] = runs(closed_spans())
    assert run.attrs["exagent.status"] == "failed"
    assert run.attrs["error.type"]
    assert run.end_time > run.start_time
    {:ok, %{status: status}} = Continuation.get(store, "conversation")
    refute status == :pending
  end

  test "finish releases the recording watcher for a paused operation", ctx do
    operation = OTel.start(ctx.tracing, :run, %{})
    monitor = Process.monitor(operation.watcher)
    OTel.finish(operation, {:ok, %{status: :paused}})
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    [run] = closed_spans()
    assert run.attrs["exagent.status"] == "paused"
    assert run.end_time > run.start_time
    OTel.finish(operation, {:ok, %{status: :paused}})
    assert closed_spans() == []
  end

  test "only bounded validated public continuation identity becomes attributes", ctx do
    valid = %{
      version: 1,
      id: "conversation",
      record_id: "record",
      run_id: "run",
      revision: 9,
      attempt_id: "attempt",
      actor: "private-actor",
      token: "private-token",
      record: %{payload: "private-record"},
      payload: "private-payload"
    }

    operation = OTel.start(ctx.tracing, :run, %{})
    OTel.run_result(operation, {:ok, %{continuation: valid, attempt_id: "attempt"}})
    OTel.finish(operation, {:ok, %{}})
    [run] = closed_spans()

    assert Map.take(
             run.attrs,
             Enum.map(
               [:version, :id, :record_id, :run_id, :revision, :attempt_id],
               &("exagent.continuation." <> Atom.to_string(&1))
             )
           ) == %{
             "exagent.continuation.version" => 1,
             "exagent.continuation.id" => "conversation",
             "exagent.continuation.record_id" => "record",
             "exagent.continuation.run_id" => "run",
             "exagent.continuation.revision" => 9,
             "exagent.continuation.attempt_id" => "attempt"
           }

    refute inspect(run.attrs) =~ "private-"

    for key <- [:id, :record_id, :run_id, :attempt_id],
        value <- ["", "bad\nidentity", <<255>>, String.duplicate("a", 257), %{}, 17] do
      assert OTel.ids(%{attempt_id: value}) == %{}
      operation = OTel.start(ctx.tracing, :run, %{})
      OTel.run_result(operation, {:ok, %{continuation: Map.put(valid, key, value)}})
      OTel.finish(operation, {:ok, %{}})
      [invalid] = closed_spans()
      refute Enum.any?(Map.keys(invalid.attrs), &String.starts_with?(&1, "exagent.continuation."))
    end

    for bad <- [%{valid | version: 2}, %{valid | revision: "9"}, %{valid | revision: -1}] do
      operation = OTel.start(ctx.tracing, :run, %{})
      OTel.run_result(operation, {:ok, %{continuation: bad}})
      OTel.finish(operation, {:ok, %{}})
      [invalid] = closed_spans()
      refute Enum.any?(Map.keys(invalid.attrs), &String.starts_with?(&1, "exagent.continuation."))
    end
  end

  test "struct and forged struct references are omitted without losing run correlation", ctx do
    reference = public_reference()

    malformed = [
      %Response{parts: []},
      Map.merge(%Response{parts: []}, reference)
      | Enum.map([Response, nil, false, "forged", 17, %{}, make_ref()], fn marker ->
          Map.put(reference, :__struct__, marker)
        end)
    ]

    for ref <- malformed, do: assert_reference_omitted(ctx, ref)
  end

  test "continuation version is strictly integer one", ctx do
    for version <- [1.0, "1", nil, true, 0, 2, [], %{}] do
      assert_reference_omitted(ctx, %{public_reference() | version: version})
    end

    attrs = project_reference(ctx, public_reference())
    assert attrs["exagent.continuation.version"] === 1
    assert attrs["exagent.continuation.revision"] === 1
  end

  test "unsupported reference shapes and field types are omitted without exceptions", ctx do
    reference = public_reference()

    for ref <- [
          nil,
          [],
          [version: 1],
          {:reference, reference},
          self(),
          make_ref(),
          fn -> reference end,
          "reference",
          1,
          %{},
          Map.new(reference, fn {key, value} -> {Atom.to_string(key), value} end)
        ] do
      assert_reference_omitted(ctx, ref)
    end

    for key <- [:version, :id, :record_id, :run_id, :revision] do
      assert_reference_omitted(ctx, Map.delete(reference, key))
    end

    for key <- [:id, :record_id, :run_id, :revision, :attempt_id] do
      assert_reference_omitted(ctx, Map.put(reference, key, %Response{parts: []}))
    end

    assert_reference_omitted(ctx, %{reference | revision: 1.0})

    for ref <- [Map.delete(reference, :attempt_id), %{reference | attempt_id: nil}] do
      attrs = project_reference(ctx, ref)
      assert attrs["exagent.continuation.record_id"] == "record"
      refute Map.has_key?(attrs, "exagent.continuation.attempt_id")
    end
  end

  defp public_reference do
    %{
      version: 1,
      id: "conversation",
      record_id: "record",
      run_id: "run",
      revision: 1,
      attempt_id: "attempt"
    }
  end

  defp assert_reference_omitted(ctx, reference) do
    attrs = project_reference(ctx, reference)
    assert attrs["exagent.run_id"] == "valid-run"
    assert attrs["exagent.attempt_id"] == "valid-attempt"
    refute Enum.any?(Map.keys(attrs), &String.starts_with?(&1, "exagent.continuation."))
  end

  defp project_reference(ctx, reference) do
    operation = OTel.start(ctx.tracing, :run, %{})

    try do
      OTel.run_result(
        operation,
        {:ok, %{continuation: reference, run_id: "valid-run", attempt_id: "valid-attempt"}}
      )
    after
      OTel.finish(operation, {:ok, %{}})
    end

    [run] = closed_spans()
    run.attrs
  end

  defp closed_spans(acc \\ []) do
    receive do
      {:closed_span, record} ->
        closed_spans([
          %{
            id: span(record, :span_id),
            attrs: :otel_attributes.map(span(record, :attributes)),
            status: span(record, :status),
            start_time: span(record, :start_time),
            end_time: span(record, :end_time)
          }
          | acc
        ])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp runs(spans), do: Enum.filter(spans, &(&1.attrs["exagent.operation"] == "run"))

  defp agent(owner, tracing) do
    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :effect)
          {:ok, "private-result"}
        end
      )

    model = %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          send(owner, :model_first)

          %Response{
            parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}],
            usage: %Usage{input_tokens: 3, output_tokens: 2}
          }
        end,
        fn _, _ ->
          send(owner, :model_second)

          %Response{
            parts: [%Part.Text{content: "private-output"}],
            usage: %Usage{input_tokens: 3, output_tokens: 2}
          }
        end
      ]
    }

    ExAgent.new(model: model, tools: [tool], observability: tracing)
  end

  defp config(store),
    do: %{
      store: store,
      id: "conversation",
      durability: :ephemeral,
      expires_at: nil,
      deadline_at: nil,
      lease_ms: 60_000,
      active_time_limit_ms: 30_000,
      definition: %{"id" => "fixture", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      model_ref: %{"id" => "test-model", "version" => "1"},
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, %{"index" => i} -> {:ok, %{m | index: i}} end
      }
    }

  defp decision(record) do
    [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    [
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: "approve",
      approval_id: id,
      payload_hash: approval["payload_hash"],
      actor: "private-actor",
      authorize: fn "private-actor", :approve, _ -> {:ok, "private-human"} end
    ]
  end
end
