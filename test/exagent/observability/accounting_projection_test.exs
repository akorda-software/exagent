defmodule ExAgent.Observability.AccountingProjectionTest do
  use ExUnit.Case, async: false
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))
  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Observability.OpenTelemetry, as: OTel
  @provider :accounting_projection_test

  defmodule Processor do
    def on_start(_, span, _), do: span

    def on_end(span, owner) do
      send(owner, {:accounting_span, span})
      true
    end

    def force_flush(_), do: :ok
  end

  defmodule Model do
    @behaviour ExAgent.Model
    defstruct [:usage, :owner]
    def model_name(_), do: "accounting-projection"
    def system(_), do: "synthetic"

    def request(model, _, _, _) do
      send(model.owner, :request)
      {:ok, %Response{parts: [%Part.Text{content: "private-output"}], usage: model.usage}, model}
    end
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
    %{tracing: OTel.new(tracer: tracer)}
  end

  test "missing accounting retains host count without invented model tokens or cost", ctx do
    assert {:ok, result} = run(nil, ctx.tracing)
    assert_receive :request
    [model, run] = closed_spans()
    assert model["exagent.operation"] == "model"
    assert run["exagent.operation"] == "run"
    assert run["exagent.usage.request_count"] == result.request_count
    assert result.request_count == 1
    assert run["exagent.usage.tool_calls"] == 0
    assert model["exagent.usage.input_availability"] == "unavailable"
    assert model["exagent.usage.output_availability"] == "unavailable"
    assert model["exagent.usage.provider_presence"] == "unknown"
    refute Map.has_key?(model, "gen_ai.usage.input_tokens")
    refute Map.has_key?(model, "gen_ai.usage.output_tokens")
    refute Map.has_key?(model, "exagent.cost.cents")
    refute Map.has_key?(run, "gen_ai.usage.input_tokens")
  end

  test "normalized zero stays available and normalized; estimator runs once per report", ctx do
    usage = Usage.normalized(%{input_tokens: 0, output_tokens: 0, input_includes_cached: true})
    calls = :atomics.new(1, [])

    estimator = fn _ ->
      :atomics.add(calls, 1, 1)
      0.25
    end

    assert {:ok, result} = run(usage, ctx.tracing, estimate_cost: estimator)
    assert :atomics.get(calls, 1) == 1
    assert result.cost_cents == 0.25
    [model, run] = closed_spans()

    for attrs <- [model, run] do
      assert attrs["exagent.usage.quality"] == "normalized"
      assert attrs["exagent.usage.accounting_source"] == "req_llm"
      assert attrs["exagent.usage.provider_presence"] == "unknown"
      assert attrs["exagent.usage.input_availability"] == "available"
      assert attrs["exagent.usage.output_availability"] == "available"
      assert attrs["exagent.cost.cents"] == 0.25
      assert attrs["exagent.cost.source"] == "estimator"
      refute Map.has_key?(attrs, "exagent.cost.known_subtotal_cents")
      refute Map.has_key?(attrs, "exagent.usage.reported_input_tokens")
    end

    assert model["gen_ai.usage.input_tokens"] == 0
    assert model["exagent.usage.normalized_input_tokens"] == 0
    assert run["exagent.usage.input_tokens"] == 0
    assert run["exagent.usage.request_count"] == 1
    refute Map.has_key?(run, "gen_ai.usage.input_tokens")
  end

  test "partial exclusive cache preserves available read without inventing inclusive input",
       ctx do
    usage =
      Usage.normalized(%{
        input_tokens: 5,
        output_tokens: 2,
        cached_tokens: 3,
        input_includes_cached: false
      })

    assert {:ok, result} = run(usage, ctx.tracing)
    [model, run] = closed_spans()
    assert model["exagent.usage.input_tokens_semantics"] == "exclusive_cache"
    assert model["exagent.usage.normalized_input_tokens"] == 5
    assert model["gen_ai.usage.cache_read.input_tokens"] == 3
    assert model["exagent.usage.cache_read_availability"] == "available"
    assert model["exagent.usage.cache_write_availability"] == "unavailable"
    refute Map.has_key?(model, "gen_ai.usage.cache_write.input_tokens")
    refute Map.has_key?(model, "gen_ai.usage.input_tokens")
    assert run["exagent.usage.input_tokens"] == result.usage.input_tokens
    assert result.usage.input_tokens == 5
    refute Map.has_key?(run, "gen_ai.usage.cache_read.input_tokens")
  end

  test "inclusive and complete exclusive cache normalize exactly once", ctx do
    for inclusive <- [true, false] do
      usage =
        Usage.normalized(%{
          input_tokens: 5,
          output_tokens: 2,
          cached_tokens: 3,
          cache_creation_tokens: 4,
          input_includes_cached: inclusive
        })

      assert {:ok, result} = run(usage, ctx.tracing)
      [model, run] = closed_spans()
      assert model["gen_ai.usage.input_tokens"] == if(inclusive, do: 5, else: 12)
      assert model["gen_ai.usage.cache_read.input_tokens"] == 3
      assert model["gen_ai.usage.cache_write.input_tokens"] == 4
      assert run["exagent.usage.input_tokens"] == result.usage.input_tokens
      assert result.usage.input_tokens == 5
      refute Map.has_key?(run, "gen_ai.usage.input_tokens")
    end
  end

  test "partial monetary subtotal is projected once without a complete total", ctx do
    owner = self()
    usage = Usage.normalized(%{input_tokens: 2, output_tokens: 1, total_cost: 0.001})

    agent =
      ExAgent.new(
        observability: ctx.tracing,
        model: %ExAgent.Models.Test{
          script: [
            %Response{
              parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}],
              usage: usage
            },
            %Response{parts: [%Part.Text{content: "done"}], usage: nil}
          ]
        },
        tools: [
          ExAgent.Tool.new(
            name: "effect",
            takes_ctx: false,
            call: fn _ ->
              send(owner, :effect)
              "ok"
            end
          )
        ]
      )

    assert {:ok, result} = ExAgent.run(agent, "go")
    assert_receive :effect
    spans = closed_spans()
    run = Enum.find(spans, &(&1["exagent.operation"] == "run"))
    assert result.cost_cents == nil
    assert result.usage.accounting["cost"]["availability"] == "partial"
    assert run["exagent.cost.known_subtotal_cents"] == 0.1
    refute Map.has_key?(run, "exagent.cost.cents")
    assert run["exagent.usage.request_count"] == 2
    assert run["exagent.usage.tool_calls"] == 1
    assert Enum.count(spans, &(&1["exagent.operation"] == "model")) == 2
  end

  defp run(usage, tracing, opts \\ []) do
    ExAgent.run(
      ExAgent.new(model: %Model{usage: usage, owner: self()}, observability: tracing),
      "private-prompt",
      opts
    )
  end

  defp closed_spans(acc \\ []) do
    receive do
      {:accounting_span, record} ->
        closed_spans([:otel_attributes.map(span(record, :attributes)) | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
