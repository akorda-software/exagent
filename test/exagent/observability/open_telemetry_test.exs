defmodule ExAgent.Observability.OpenTelemetryTest do
  use ExUnit.Case, async: false
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  alias ExAgent.Observability.{OpenTelemetry, BoundedProcessor}
  alias ExAgent.{Server, Session, Tool, RunError}
  alias ExAgent.Models.Test, as: TestModel
  alias ExAgent.Message.{Response, Usage, Part}

  @provider :exagent_instrumentation_test
  @processor :exagent_instrumentation_export
  @secret "synthetic_C6_SECRET_94e7"

  defmodule Exporter do
    def init(pid), do: {:ok, pid}

    def export(table, resource, pid) do
      send(pid, {:otel_batch, :ets.tab2list(table), resource})
      :ok
    end

    def shutdown(_), do: :ok
  end

  defmodule FailingModel do
    @behaviour ExAgent.Model
    defstruct [:secret]

    def request(model, _, _, _),
      do:
        {:error,
         %ExAgent.RequestError{
           provider: :openai,
           status: 503,
           reason: {:http_error, model.secret},
           model: model
         }}

    def model_name(_), do: "failing"
    def system(_), do: "openai"
  end

  defmodule FlakyStore do
    def load_agent_snapshot(_, _), do: {:error, :not_found}

    def save_agent_snapshot(agent, snapshot) do
      Agent.get_and_update(agent, fn {count, pid} ->
        send(pid, {:saved, snapshot})
        result = if count == 0, do: {:error, "synthetic_C6_SECRET_94e7"}, else: :ok
        {result, {count + 1, pid}}
      end)
    end
  end

  defmodule Output do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:answer, :string)
    end

    def changeset(value, attrs),
      do:
        value
        |> Ecto.Changeset.cast(attrs, [:answer])
        |> Ecto.Changeset.validate_required([:answer])
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
    resource = :otel_resource.create(%{"service.name" => "application-owned"})

    config = %{
      sampler: :always_on,
      id_generator: :otel_id_generator,
      deny_list: [],
      processors: [
        {BoundedProcessor,
         %{
           name: @processor,
           resource: resource,
           exporter: {Exporter, self()},
           max_queue_size: 256,
           max_export_batch_size: 64,
           scheduled_delay_ms: 10,
           exporting_timeout_ms: 1000
         }}
      ]
    }

    {:ok, provider} = :otel_tracer_provider_sup.start(@provider, resource, config)
    wait_ready()
    tracer = :otel_tracer_provider.get_tracer(@provider, :exagent, "1", :undefined)
    global = :opentelemetry.get_tracer()

    on_exit(fn ->
      :supervisor.terminate_child(:otel_tracer_provider_sup, provider)
    end)

    %{
      tracing: OpenTelemetry.new(tracer: tracer),
      tracer: tracer,
      global: global,
      resource: resource
    }
  end

  test "native hierarchy spans parallel tools, a delegated run and explicit retry without duplicate accounting",
       %{tracing: tracing, tracer: tracer, global: global, resource: resource} do
    parent = self()
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    echo =
      Tool.new(
        name: "echo",
        parameters_json_schema: %{"type" => "object"},
        call: fn _ctx, _args ->
          number = Agent.get_and_update(calls, &{&1, &1 + 1})

          if number == 0 do
            send(parent, {:parallel, :tool, self()})

            receive do
              :continue -> :ok
            end

            raise ExAgent.ModelRetry, "correct the input"
          end

          "echoed"
        end
      )

    child =
      ExAgent.new(
        model: %TestModel{
          script: [
            fn _, _ ->
              send(parent, {:parallel, :child, self()})

              receive do
                :continue -> :ok
              end

              response("child", 10, 2, %{cached_tokens: 4, reasoning_tokens: 1})
            end
          ]
        }
      )

    agent =
      ExAgent.new(
        observability: tracing,
        tools: [echo, ExAgent.Coordination.delegation_tool(child)],
        model: %TestModel{
          script: [
            {:tool_calls,
             [call("echo", "echo-1"), call("delegate", "delegate-1", %{"prompt" => "subtask"})]},
            {:tool_calls, [call("echo", "echo-2")]},
            response("done", 20, 3, %{cached_tokens: 8})
          ]
        }
      )

    estimator_calls = :atomics.new(1, [])

    estimate = fn usage ->
      :atomics.add(estimator_calls, 1, 1)
      (usage.input_tokens + usage.output_tokens) / 100
    end

    {result, application_span} =
      in_app_span(tracer, fn _ ->
        context = OpenTelemetry.capture_context()

        task =
          Task.async(fn ->
            ExAgent.run(agent, @secret,
              trace_context: context,
              estimate_cost: estimate,
              deps: %{secret: @secret}
            )
          end)

        assert_receive {:parallel, :tool, tool}, 2000
        assert_receive {:parallel, :child, child}, 2000
        send(tool, :continue)
        send(child, :continue)
        Task.await(task)
      end)

    assert {:ok, %{output: "done", request_count: 4, tool_calls: 3} = result} = result
    assert :atomics.get(estimator_calls, 1) == 10
    assert Agent.get(calls, & &1) == 2
    spans = collect(11)
    assert length(Enum.uniq_by(spans, & &1.id)) == 11
    assert Enum.all?(spans, &(&1.trace_id == :otel_span.trace_id(application_span)))
    runs = kind(spans, :run)
    models = kind(spans, :model)
    tools = kind(spans, :tool)
    assert length(runs) == 2
    assert length(models) == 4
    assert length(tools) == 3
    assert length(kind(spans, :delegation)) == 1
    root = Enum.find(runs, &(&1.attrs["exagent.run_id"] == result.run_id))
    child = Enum.find(runs, &(&1.id != root.id))
    [delegation] = kind(spans, :delegation)
    delegate_tool = Enum.find(tools, &(&1.attrs["gen_ai.tool.name"] == "delegate"))
    assert root.parent_id == :otel_span.span_id(application_span)
    assert delegation.parent_id == delegate_tool.id
    assert child.parent_id == delegation.id
    assert child.attrs["exagent.parent_run_id"] == result.run_id
    assert Enum.all?(tools, &(&1.parent_id == root.id))
    assert Enum.all?(models, &(&1.parent_id in Enum.map(runs, fn run -> run.id end)))

    assert Enum.all?(runs ++ tools, fn span ->
             not Map.has_key?(span.attrs, "gen_ai.usage.input_tokens")
           end)

    assert Enum.sum(Enum.map(models, & &1.attrs["gen_ai.usage.input_tokens"])) ==
             result.usage.input_tokens

    assert_in_delta Enum.sum(Enum.map(models, & &1.attrs["exagent.cost.cents"])),
                    result.cost_cents,
                    0.00001

    assert Enum.any?(models, &(&1.attrs["gen_ai.usage.cache_read.input_tokens"] == 8))
    assert Enum.any?(tools, &(&1.attrs["exagent.status"] == "validation_error"))
    # Each generation ends before any subsequent tool can start.
    first =
      Enum.find(
        models,
        &(&1.attrs["exagent.run_id"] == result.run_id and &1.attrs["exagent.run_step"] == 1)
      )

    assert Enum.all?(tools, &(&1.start_time >= first.end_time))
    refute inspect(spans) =~ @secret
    assert :opentelemetry.get_tracer() == global
    assert :otel_tracer_provider.resource(@provider) == resource
  end

  test "lazy enumeration captures its caller, halting closes one model and one run", %{
    tracing: tracing,
    tracer: tracer
  } do
    agent = ExAgent.new(model: %TestModel{label: "one two three"}, observability: tracing)
    stream = ExAgent.run_stream(agent, @secret)
    refute_receive {:otel_batch, _, _}, 30
    {events, app} = in_app_span(tracer, fn _ -> Enum.take(stream, 1) end)
    assert [{:delta, _}] = events
    spans = collect(3)
    [run] = kind(spans, :run)
    [model] = kind(spans, :model)
    assert run.parent_id == :otel_span.span_id(app)
    assert model.parent_id == run.id
    assert run.attrs["exagent.status"] == "cancelled"
    assert model.attrs["exagent.status"] == "cancelled"
    refute_receive {:otel_batch, _, _}, 30
  end

  test "normal stream and errors have one terminal and safe diagnostics", %{tracing: tracing} do
    success =
      ExAgent.run_stream(ExAgent.new(model: %TestModel{}, observability: tracing), @secret)
      |> Enum.to_list()

    assert Enum.count(success, &match?({:result, _}, &1)) == 1
    assert Enum.count(success, &match?({:error, _}, &1)) == 0
    assert length(collect(2)) == 2
    agent = ExAgent.new(model: %FailingModel{secret: @secret}, observability: tracing)
    assert {:error, %RunError{}} = ExAgent.run(agent, @secret)
    spans = collect(2)
    assert Enum.all?(spans, &(&1.attrs["exagent.status"] == "failed"))
    assert Enum.all?(spans, &(&1.attrs["error.status"] == 503))
    assert Enum.all?(spans, &(&1.attrs["error.type"] == "request_error"))
    refute inspect(spans) =~ @secret
  end

  test "configuration defaults omit content; opt-in redacts before attributes and fails closed",
       %{tracer: tracer} do
    for redactor <- [
          fn _, value ->
            {:ok,
             String.replace(
               if(is_binary(value), do: value, else: Jason.encode!(value)),
               @secret,
               "[redacted]"
             )}
          end,
          fn _, _ -> raise @secret end,
          fn _, _ -> {:ok, String.duplicate("x", 128)} end,
          fn _, _ -> {:ok, <<255>>} end
        ] do
      config =
        OpenTelemetry.new(tracer: tracer, content: true, redact: redactor, max_content_bytes: 96)

      agent = ExAgent.new(model: %TestModel{label: @secret}, observability: config)
      assert {:ok, %{output: @secret}} = ExAgent.run(agent, @secret)
      spans = collect(2)
      refute inspect(spans) =~ @secret

      assert Enum.all?(spans, fn span ->
               Enum.all?(span.attrs, fn {key, value} ->
                 not String.starts_with?(key, "exagent.content.") or byte_size(value) <= 96
               end)
             end)
    end

    assert_raise ArgumentError, fn -> OpenTelemetry.new(content: true) end

    config =
      OpenTelemetry.new(
        tracer: tracer,
        content: true,
        max_content_input_bytes: 8,
        redact: fn _, _ ->
          send(self(), :redactor_called)
          {:ok, "safe"}
        end
      )

    assert {:ok, _} =
             ExAgent.run(
               ExAgent.new(model: %TestModel{label: @secret}, observability: config),
               @secret
             )

    spans = collect(2)
    refute_receive :redactor_called

    assert Enum.all?(spans, fn span ->
             Enum.all?(Map.keys(span.attrs), &(not String.starts_with?(&1, "exagent.content.")))
           end)
  end

  test "context and logger are restored on success, throw and failure, with no baggage export", %{
    tracing: tracing,
    tracer: tracer
  } do
    Logger.metadata(tenant: "original")
    logger = :logger.get_process_metadata()
    empty = :otel_ctx.get_current()

    for exit_kind <- [:ok, :throw, :error] do
      parent = :otel_tracer.start_span(%{}, tracer, "application", %{})

      native =
        :otel_tracer.set_current_span(%{}, parent)
        |> :otel_ctx.set_value(:baggage, %{"secret" => @secret})

      context = %OpenTelemetry.Context{native: native, config: tracing}

      try do
        OpenTelemetry.with_context(context, fn ->
          assert {:ok, _} = ExAgent.run(ExAgent.new(model: %TestModel{}), @secret)

          case exit_kind do
            :ok -> :ok
            :throw -> throw(:test_throw)
            :error -> raise @secret
          end
        end)
      catch
        :throw, :test_throw -> :ok
        :error, %RuntimeError{message: @secret} -> :ok
      end

      :otel_span.end_span(parent)
      assert :otel_ctx.get_current() == empty
      assert :logger.get_process_metadata() == logger
      refute inspect(collect(3)) =~ @secret
    end
  end

  test "Server queues retain each admitting caller and checkpoint is inside the unique run", %{
    tracing: tracing,
    tracer: tracer
  } do
    parent = self()

    model = %TestModel{
      script: [
        fn _, _ ->
          send(parent, {:working, self()})

          receive do
            :continue -> :ok
          end

          "first"
        end,
        "second"
      ]
    }

    id = "otel_queue_#{System.unique_integer([:positive])}"

    server =
      start_supervised!(
        {Server,
         agent_id: id, agent: ExAgent.new(model: model), observability: tracing, store: :ets}
      )

    {_, app_a} = in_app_span(tracer, fn _ -> Server.send_message(server, "first") end)
    assert_receive {:working, worker}, 2000

    {{:ok, queued}, app_b} =
      in_app_span(tracer, fn _ -> Server.send_message(server, "second") end)

    send(worker, :continue)
    spans = collect(8)
    runs = kind(spans, :run)
    assert length(runs) == 2
    first = Enum.find(runs, &(&1.attrs["exagent.request_id"] != queued))
    second = Enum.find(runs, &(&1.attrs["exagent.request_id"] == queued))
    assert first.parent_id == :otel_span.span_id(app_a)
    assert second.parent_id == :otel_span.span_id(app_b)

    for checkpoint <- kind(spans, :checkpoint) do
      run = Enum.find(runs, &(&1.id == checkpoint.parent_id))
      assert run
      assert checkpoint.end_time <= run.end_time
    end

    assert Server.health(server).status == :idle
    assert clean_process_context?(server)
    assert {:ok, snapshot} = ExAgent.Store.load_agent_snapshot(ExAgent.Store.normalize(:ets), id)
    refute inspect(snapshot) =~ "OpenTelemetry"
    # Restore produces a new execution/trace, never a stale persisted span.
    stop_supervised({:exagent_server, id})

    restored =
      start_supervised!(
        {Server,
         agent_id: id,
         agent: ExAgent.new(model: %TestModel{}),
         observability: tracing,
         store: :ets}
      )

    assert {:ok, _} = Server.chat(restored, "restored")
    [run] = collect(3) |> kind(:run)
    assert run.parent_id in [0, :undefined]
  end

  test "restoring OTel Logger keys preserves application metadata changes", %{tracer: tracer} do
    Logger.metadata(tenant: "before", otel_trace_id: "old-trace")

    {_, _} =
      in_app_span(tracer, fn _ ->
        Logger.metadata(tenant: "after", application_key: "new")
      end)

    metadata = Logger.metadata()
    assert metadata[:tenant] == "after"
    assert metadata[:application_key] == "new"
    assert metadata[:otel_trace_id] == "old-trace"
    refute Keyword.has_key?(metadata, :otel_span_id)
    assert length(collect(1)) == 1
  end

  test "tool exceptions and timeouts close spans without replay or raw error attributes", %{
    tracing: tracing
  } do
    for {name, callback} <- [
          {"failure", fn _, _ -> {:error, @secret} end},
          {"timeout", fn _, _ -> Process.sleep(:infinity) end}
        ] do
      tool = Tool.new(name: name, parameters_json_schema: %{"type" => "object"}, call: callback)

      agent =
        ExAgent.new(
          model: %TestModel{script: [{:tool_calls, [call(name, name <> "-1")]}]},
          tools: [tool],
          observability: tracing,
          tool_timeout: 20
        )

      assert {:error, %RunError{partial: partial}} = ExAgent.run(agent, @secret)
      assert partial.request_count == 1
      spans = collect(3)
      [run] = kind(spans, :run)
      [tool] = kind(spans, :tool)
      assert run.attrs["exagent.status"] == "failed"
      assert tool.attrs["exagent.status"] in ["failed", "cancelled"]
      refute inspect(spans) =~ @secret
    end
  end

  test "checkpoint failure and retry-save are observable without replay or raw errors", %{
    tracing: tracing,
    tracer: tracer
  } do
    parent = self()
    {:ok, store} = Agent.start_link(fn -> {0, parent} end)

    model = %TestModel{
      script: [
        fn _, _ ->
          send(parent, :checkpoint_model_called)
          "checkpointed result"
        end
      ]
    }

    server =
      start_supervised!(
        {Server,
         agent: ExAgent.new(model: model), observability: tracing, store: {FlakyStore, store}}
      )

    assert {:error, %ExAgent.CheckpointError{revision: 1, result: {:ok, result}}} =
             Server.chat(server, "hello")

    assert result.output == "checkpointed result"
    assert_receive :checkpoint_model_called, 2000
    assert_receive {:saved, first}, 2000
    spans = collect(3)
    [checkpoint] = kind(spans, :checkpoint)
    [run] = kind(spans, :run)
    assert checkpoint.attrs["exagent.status"] == "failed"
    assert run.attrs["exagent.status"] == "failed"
    refute inspect(spans) =~ @secret
    {:ok, app} = in_app_span(tracer, fn _ -> Server.checkpoint(server) end)
    assert_receive {:saved, second}, 2000
    # Each save attempt gets a fresh saved_at; the logical revision and every
    # persisted data field must be identical, and retry must not replay the model.
    assert first.revision == 1
    assert Map.delete(first, :saved_at) == Map.delete(second, :saved_at)
    assert %DateTime{} = first.saved_at
    assert %DateTime{} = second.saved_at
    assert Server.history(server) == result.messages
    assert Server.usage(server) == result.usage
    refute_receive :checkpoint_model_called
    spans = collect(2)
    [retry] = kind(spans, :checkpoint)
    assert retry.parent_id == :otel_span.span_id(app)
    assert retry.attrs["exagent.checkpoint.retry"]
    assert kind(spans, :model) == []
    assert clean_process_context?(server)
  end

  test "Server abort and killed one-shot owner close active native spans", %{tracing: tracing} do
    parent = self()

    agent =
      ExAgent.new(
        model: %TestModel{
          script: [
            fn _, _ ->
              send(parent, {:blocked, self()})

              receive do
                :never -> "done"
              end
            end
          ]
        },
        observability: tracing
      )

    server = start_supervised!({Server, agent: agent})
    assert {:ok, _} = Server.send_message(server, @secret)
    assert_receive {:blocked, _}, 2000
    assert :ok = Server.abort(server)
    spans = collect(2)
    assert Enum.all?(spans, &(&1.attrs["exagent.status"] == "cancelled"))
    {pid, monitor} = spawn_monitor(fn -> ExAgent.run(agent, @secret) end)
    assert_receive {:blocked, ^pid}, 2000
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, _, _, :killed}, 2000
    spans = collect(2)
    assert Enum.all?(spans, &(&1.attrs["exagent.status"] == "cancelled"))
    refute_receive {:otel_batch, _, _}, 30
  end

  @tag :c6_review
  test "abort during first request projects incomplete usage without a known total cost", %{
    tracing: tracing
  } do
    assert_synthetic_terminal(tracing, 0, :abort)
  end

  @tag :c6_review
  test "worker crash during first request projects incomplete usage without a known total cost",
       %{tracing: tracing} do
    assert_synthetic_terminal(tracing, 0, :crash)
  end

  @tag :c6_review
  test "abort during later request retains the confirmed subtotal without asserting a total", %{
    tracing: tracing
  } do
    assert_synthetic_terminal(tracing, 1, :abort)
  end

  @tag :c6_review
  test "worker crash during later request retains the confirmed subtotal without asserting a total",
       %{tracing: tracing} do
    assert_synthetic_terminal(tracing, 1, :crash)
  end

  @tag :c6_review
  test "a normal core failure preserves its confirmed usage and known cost projection", %{
    tracing: tracing
  } do
    tool =
      Tool.new(
        name: "fail",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ -> {:error, :expected_failure} end
      )

    response = %Response{
      parts: [call("fail", "fail-1")],
      usage: %Usage{input_tokens: 10, output_tokens: 2}
    }

    server =
      start_supervised!(
        {Server,
         agent:
           ExAgent.new(
             model: %TestModel{script: [response]},
             tools: [tool],
             observability: tracing
           )}
      )

    assert {:error, %RunError{partial: partial}} =
             Server.chat(server, "request",
               estimate_cost: fn usage -> (usage.input_tokens + usage.output_tokens) / 100 end
             )

    [run] = collect(3) |> kind(:run)
    assert partial.usage_status == :complete
    assert run.attrs["exagent.usage.status"] == "complete"
    assert run.attrs["exagent.cost.status"] == "known"
    assert_in_delta run.attrs["exagent.cost.cents"], 0.12, 0.00001
    refute Map.has_key?(run.attrs, "exagent.cost.known_subtotal_cents")
    refute Map.has_key?(run.attrs, "exagent.usage.source")
  end

  @tag :c6_review
  test "empty context clears owned Logger keys inside attachment and restores enclosing span", %{
    tracer: tracer
  } do
    empty = OpenTelemetry.capture_context()
    Logger.metadata(tenant: "before")

    {_, _} =
      in_app_span(tracer, fn _ ->
        keys = [:otel_span_id, :otel_trace_id, :otel_trace_flags]
        prior_ids = Logger.metadata() |> Keyword.take(keys) |> Map.new()
        assert map_size(prior_ids) == 3
        prior_span = :otel_tracer.current_span_ctx()

        OpenTelemetry.with_context(empty, fn ->
          assert :otel_tracer.current_span_ctx() == :undefined
          for key <- keys, do: refute(Keyword.has_key?(Logger.metadata(), key))
          assert Logger.metadata()[:tenant] == "before"
          Logger.metadata(tenant: "inside", app_key: "new")
        end)

        assert :otel_tracer.current_span_ctx() == prior_span
        assert Logger.metadata() |> Keyword.take(keys) |> Map.new() == prior_ids
        assert Logger.metadata()[:tenant] == "inside"
        assert Logger.metadata()[:app_key] == "new"
      end)

    assert Logger.metadata()[:tenant] == "inside"
    refute Keyword.has_key?(Logger.metadata(), :otel_span_id)
    assert length(collect(1)) == 1
  end

  @tag :c6_review
  test "oversized integers, including nested values, never reach the content redactor", %{
    tracer: tracer
  } do
    parent = self()

    tracing =
      OpenTelemetry.new(
        tracer: tracer,
        content: true,
        max_content_input_bytes: 64,
        redact: fn field, _value ->
          send(parent, {:content_redactor_called, field})
          {:ok, "safe"}
        end
      )

    huge = Integer.pow(10, 1000)

    for value <- [huge, -huge, %{"n" => huge}] do
      OpenTelemetry.around(tracing, :tool, %{}, nil, fn operation ->
        OpenTelemetry.content(operation, :input, value)
      end)

      refute_receive {:content_redactor_called, :input}
      [span] = collect(1)
      refute Map.has_key?(span.attrs, "exagent.content.input")
    end

    for value <- [42, -42, 1.25, %{"n" => 42}] do
      OpenTelemetry.around(tracing, :tool, %{}, nil, fn operation ->
        OpenTelemetry.content(operation, :input, value)
      end)

      assert_receive {:content_redactor_called, :input}
      [span] = collect(1)
      assert span.attrs["exagent.content.input"] == "safe"
    end
  end

  test "compaction and Session transitions produce operation spans with restored context", %{
    tracing: tracing,
    tracer: tracer
  } do
    compaction = %ExAgent.Compaction.Capability{
      compactor: ExAgent.Compaction.Summary,
      opts: [threshold_tokens: 0, keep_recent: 0, summarize: fn _ -> "short summary" end]
    }

    history = [
      %ExAgent.Message.Request{parts: [%Part.User{content: "old"}]},
      response("old response", 1, 1)
    ]

    agent = ExAgent.new(model: %TestModel{}, observability: tracing, capabilities: [compaction])
    assert {:ok, result} = ExAgent.run(agent, "active", message_history: history)
    assert Enum.take(result.messages, 2) == history
    spans = collect(3)
    [compaction] = kind(spans, :compaction)
    [run] = kind(spans, :run)
    assert compaction.parent_id == run.id
    assert compaction.attrs["exagent.compaction.changed"]

    session =
      start_supervised!(
        {Session,
         session_id: "otel_session_#{System.unique_integer([:positive])}",
         observability: tracing,
         store: :ets}
      )

    {_, app} = in_app_span(tracer, fn _ -> Session.join(session, id: "human", kind: :human) end)
    spans = collect(2)
    [checkpoint] = kind(spans, :checkpoint)
    assert checkpoint.parent_id == :otel_span.span_id(app)
    assert checkpoint.attrs["exagent.checkpoint.operation"] == "session"
    assert clean_process_context?(session)
  end

  test "Anthropic exclusive cache and OpenAI inclusive cache map without changing reported usage",
       %{tracing: tracing} do
    for {model, usage, expected} <- [
          {%ExAgent.Models.Anthropic{},
           %Usage{
             input_tokens: 20,
             output_tokens: 10,
             details: %{cache_read_input_tokens: 60, cache_creation_input_tokens: 20}
           }, 100},
          {%ExAgent.Models.OpenAI{},
           %Usage{input_tokens: 100, output_tokens: 10, details: %{cached_tokens: 60}}, 100},
          {%FailingModel{}, %Usage{input_tokens: 100, output_tokens: 10}, nil}
        ] do
      OpenTelemetry.around(tracing, :model, %{}, nil, fn operation ->
        OpenTelemetry.model_result(
          operation,
          {:ok, %{usage: usage, usage_status: :complete, cost_cents: 0.3, cost_status: :known}},
          model
        )
      end)

      [span] = collect(1)
      assert span.attrs["gen_ai.usage.input_tokens"] == expected
      assert span.attrs["exagent.usage.reported_input_tokens"] == usage.input_tokens
      assert span.attrs["exagent.cost.cents"] == 0.3
    end
  end

  test "disabled instrumentation does not replace tracer or create spans", %{
    tracing: tracing,
    global: global
  } do
    agent = ExAgent.new(model: %TestModel{}, observability: tracing)
    assert {:ok, _} = ExAgent.run(agent, @secret, observability: false)
    refute_receive {:otel_batch, _, _}, 30
    assert :opentelemetry.get_tracer() == global
  end

  test "structured output validation spans end before the correcting model request", %{
    tracing: tracing
  } do
    agent =
      ExAgent.new(
        model: %TestModel{
          script: [
            {:tool_calls, [call("final_result", "out-1", %{})]},
            {:tool_calls, [call("final_result", "out-2", %{"answer" => "done"})]}
          ]
        },
        output: Output,
        observability: tracing
      )

    assert {:ok, %{output: %Output{answer: "done"}, request_count: 2}} =
             ExAgent.run(agent, "answer")

    spans = collect(5)
    [run] = kind(spans, :run)
    tools = kind(spans, :tool)
    assert length(tools) == 2
    assert Enum.all?(tools, &(&1.parent_id == run.id))
    first = Enum.find(tools, &(&1.attrs["exagent.tool_call_id"] == "out-1"))
    assert first.attrs["exagent.status"] == "failed"
    second_request = Enum.find(kind(spans, :model), &(&1.attrs["exagent.run_step"] == 2))
    assert first.end_time <= second_request.start_time
    assert second_request.parent_id == run.id
  end

  defp in_app_span(tracer, fun) do
    span = :otel_tracer.start_span(%{}, tracer, "application", %{})
    context = %OpenTelemetry.Context{native: :otel_tracer.set_current_span(%{}, span)}

    try do
      {OpenTelemetry.with_context(context, fn -> fun.(span) end), span}
    after
      :otel_span.end_span(span)
    end
  end

  defp assert_synthetic_terminal(tracing, completed_requests, terminal) do
    parent = self()
    estimate_calls = :atomics.new(1, [])

    estimate = fn usage ->
      :atomics.add(estimate_calls, 1, 1)
      (usage.input_tokens + usage.output_tokens) / 100
    end

    blocked = fn _, _ ->
      send(parent, {:review_request_waiting, self()})

      receive do
        :continue -> "done"
      end
    end

    script =
      if completed_requests == 0 do
        [blocked]
      else
        [
          %Response{
            parts: [call("advance", "advance-1")],
            usage: %Usage{input_tokens: 10, output_tokens: 2}
          },
          blocked
        ]
      end

    tool =
      Tool.new(
        name: "advance",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ -> "ok" end
      )

    agent = ExAgent.new(model: %TestModel{script: script}, tools: [tool], observability: tracing)
    id = "review_terminal_#{System.unique_integer([:positive])}"
    :ok = ExAgent.PubSub.Local.subscribe([], ExAgent.Event.agent_topic(id))
    server = start_supervised!({Server, agent: agent, agent_id: id, pubsub: :local})
    caller = Task.async(fn -> Server.chat(server, "request", estimate_cost: estimate) end)
    assert_receive {:review_request_waiting, worker}, 2000

    # The provider is now in flight, but the last published subtotal predates its
    # admission. Keep its numbers while making uncertainty explicit in all channels.
    before = :sys.get_state(server).current.progress
    assert before.request_count == completed_requests
    assert before.usage_status == :complete
    before_estimates = :atomics.get(estimate_calls, 1)

    case terminal do
      :abort -> assert :ok = Server.abort(server)
      :crash -> Process.exit(worker, :kill)
    end

    assert {:error, %RunError{partial: partial}} = Task.await(caller)
    assert partial.usage == before.usage
    assert partial.usage_status == :partial
    assert partial.cost_status == :unknown
    assert partial.cost_cents == before.cost_cents
    assert :atomics.get(estimate_calls, 1) == before_estimates

    event_type = if terminal == :abort, do: :server_request_cancelled, else: :run_failed

    assert_receive {:exagent_event,
                    %ExAgent.Event{type: ^event_type, payload: %{partial: event_partial}}},
                   2000

    assert event_partial.usage_status == :partial
    assert event_partial.cost_status == :unknown
    assert event_partial.cost_cents == before.cost_cents
    assert event_partial.usage["input_tokens"] == before.usage.input_tokens
    assert event_partial.usage["output_tokens"] == before.usage.output_tokens
    assert event_partial.request_count == before.request_count

    spans = collect(if(completed_requests == 0, do: 2, else: 4))
    [run] = kind(spans, :run)
    assert run.attrs["exagent.status"] == if(terminal == :abort, do: "cancelled", else: "failed")
    assert run.attrs["exagent.usage.status"] == "partial"
    assert run.attrs["exagent.usage.source"] == "last_progress"
    assert run.attrs["exagent.cost.status"] == "unknown"
    refute Map.has_key?(run.attrs, "exagent.cost.cents")
    assert run.attrs["exagent.cost.known_subtotal_cents"] == before.cost_cents
    assert run.attrs["exagent.usage.input_tokens"] == before.usage.input_tokens
    assert run.attrs["exagent.usage.output_tokens"] == before.usage.output_tokens
    assert run.attrs["exagent.usage.request_count"] == before.request_count
    assert Enum.count(kind(spans, :model), &(&1.attrs["exagent.usage.status"] == "partial")) == 1
  end

  defp collect(count, acc \\ [])
  defp collect(count, acc) when length(acc) == count, do: acc

  defp collect(count, acc) when length(acc) < count do
    receive do
      {:otel_batch, spans, _resource} -> collect(count, acc ++ Enum.map(spans, &decode/1))
    after
      3000 -> flunk("expected #{count} spans, received #{inspect(acc)}")
    end
  end

  defp collect(count, acc), do: flunk("expected #{count} spans, got #{length(acc)}")

  defp decode(record) do
    %{
      id: span(record, :span_id),
      trace_id: span(record, :trace_id),
      parent_id: span(record, :parent_span_id),
      name: span(record, :name),
      attrs: :otel_attributes.map(span(record, :attributes)),
      start_time: span(record, :start_time),
      end_time: span(record, :end_time)
    }
  end

  defp kind(spans, name),
    do: Enum.filter(spans, &(&1.attrs["exagent.operation"] == Atom.to_string(name)))

  defp response(text, input, output, details \\ %{}),
    do: %Response{
      parts: [%Part.Text{content: text}],
      usage: %Usage{input_tokens: input, output_tokens: output, details: details}
    }

  defp call(name, id, args \\ %{}),
    do: %Part.ToolCall{tool_name: name, tool_call_id: id, args: args}

  defp clean_process_context?(pid) do
    caller = self()
    ref = make_ref()

    :sys.replace_state(pid, fn state ->
      send(caller, {ref, :otel_ctx.get_current(), :logger.get_process_metadata()})
      state
    end)

    receive do
      {^ref, context, metadata} ->
        :otel_tracer.current_span_ctx(context) == :undefined and
          (metadata == :undefined or not Map.has_key?(metadata, :otel_span_id))
    after
      1000 -> false
    end
  end

  defp wait_ready(attempts \\ 200)
  defp wait_ready(0), do: flunk("processor did not become ready")

  defp wait_ready(attempts) do
    case BoundedProcessor.stats(@processor) do
      %{status: :ready} ->
        :ok

      _ ->
        Process.sleep(5)
        wait_ready(attempts - 1)
    end
  end
end
