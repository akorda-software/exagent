defmodule ExAgent.Observability.ReqLLMMetricsTest do
  use ExUnit.Case, async: false
  require Record

  Record.defrecordp(
    :metric,
    Record.extract(:metric,
      from_lib: "opentelemetry_experimental/include/otel_metrics.hrl"
    )
  )

  Record.defrecordp(
    :histogram,
    Record.extract(:histogram,
      from_lib: "opentelemetry_experimental/include/otel_metrics.hrl"
    )
  )

  Record.defrecordp(
    :point,
    :histogram_datapoint,
    Record.extract(:histogram_datapoint,
      from_lib: "opentelemetry_experimental/include/otel_metrics.hrl"
    )
  )

  alias ExAgent.Observability.ReqLLM, as: Integration
  alias ExAgent.Observability.ReqLLM.Metrics
  alias ReqLLM.OpenTelemetry.Metrics, as: Mapper

  defmodule Exporter do
    @behaviour :otel_exporter_metrics
    def init(owner) do
      send(owner, {:reader, self()})
      {:ok, owner}
    end

    def export(metrics, _resource, owner) do
      send(owner, {:metrics, metrics})
      :ok
    end

    def shutdown(_), do: :ok
  end

  defmodule SpanProcessor do
    def on_start(_, span, _), do: span

    def on_end(span, %{owner: owner}) do
      send(owner, {:restart_span, span})
      true
    end

    def force_flush(_), do: :ok
  end

  setup do
    old = Application.get_env(:opentelemetry_experimental, :readers)
    processors = Application.get_env(:opentelemetry, :processors)
    Application.put_env(:opentelemetry, :processors, [])

    Application.put_env(:opentelemetry_experimental, :readers, [
      %{module: :otel_metric_reader, config: %{exporter: {Exporter, self()}}}
    ])

    {:ok, started} = Application.ensure_all_started(:opentelemetry_experimental)
    assert :opentelemetry_experimental in started
    assert_receive {:reader, reader}

    on_exit(fn ->
      Integration.detach()
      Application.stop(:opentelemetry_experimental)
      for app <- Enum.reverse(started), do: Application.stop(app)

      if old,
        do: Application.put_env(:opentelemetry_experimental, :readers, old),
        else: Application.delete_env(:opentelemetry_experimental, :readers)

      if processors,
        do: Application.put_env(:opentelemetry, :processors, processors),
        else: Application.delete_env(:opentelemetry, :processors)
    end)

    %{reader: reader}
  end

  defp collect(reader) do
    :ok = :otel_metric_reader.call_collect(reader)

    receive do
      {:metrics, metrics} -> metrics
    after
      100 -> []
    end
  end

  defp points(metrics, name) do
    for m <- metrics,
        metric(m, :name) == name,
        p <- histogram(metric(m, :data), :datapoints),
        do: p
  end

  test "public reader exports all four histograms with normalized token units and finite dimensions",
       %{reader: reader} do
    assert Metrics.metrics_available?()

    metadata = %{
      operation: :chat,
      provider: :openai,
      model: %{id: "fixture"},
      mode: :stream,
      usage: %{input_tokens: 3, output_tokens: 2},
      streaming: %{time_to_first_chunk: System.convert_time_unit(250, :millisecond, :native)}
    }

    duration = System.convert_time_unit(1000, :millisecond, :native)

    for record <- Mapper.stop(metadata, duration),
        do: Integration.record_histogram(record, metrics: [models: ["fixture"]])

    metrics = collect(reader)
    assert length(metrics) == 4
    [operation] = points(metrics, :"gen_ai.client.operation.duration")
    assert point(operation, :count) == 1
    assert point(operation, :sum) == 1.0
    [ttfc] = points(metrics, :"gen_ai.client.operation.time_to_first_chunk")
    assert point(ttfc, :sum) == 0.25
    [tpoc] = points(metrics, :"gen_ai.client.operation.time_per_output_chunk")
    assert point(tpoc, :sum) == 0.375
    tokens = points(metrics, :"gen_ai.client.token.usage")
    assert Enum.sort(Enum.map(tokens, &point(&1, :sum))) == [2, 3]
    assert Enum.all?(tokens, &(point(&1, :count) == 1))

    for p <- tokens do
      assert point(p, :attributes)["exagent.accounting.quality"] == "normalized"
      assert point(p, :attributes)["gen_ai.request.model"] == "fixture"
    end

    assert Enum.find(metrics, &(metric(&1, :name) == :"gen_ai.client.token.usage"))
           |> metric(:unit) == "{token}"
  end

  test "default off, malformed and unknown records do not produce instruments", %{reader: reader} do
    [record | _] = Mapper.stop(%{model: "fixture"}, 1)
    :ok = Metrics.record_histogram(record, [])

    for bad <- [
          %{record | name: "user-supplied-name"},
          %{record | value: -1},
          %{record | value: "secret"},
          %{},
          %{record | attributes: []}
        ] do
      assert :ok == Metrics.record_histogram(bad, metrics: [models: ["fixture"]])
    end

    assert collect(reader) == []
    assert_raise ArgumentError, fn -> Integration.attach(metrics: true) end

    assert_raise ArgumentError, fn ->
      Integration.attach(metrics: [models: List.duplicate("a", 33)])
    end
  end

  test "untrusted attributes collapse to two finite model labels and a fixed error label",
       %{reader: reader} do
    for index <- 1..100 do
      [record] =
        Mapper.exception(%{model: "private-model-#{index}", exception: "private-error"}, 1)

      record = put_in(record.attributes["request_id"], "private-id-#{index}")
      Metrics.record_histogram(record, metrics: [models: ["fixture"]])
    end

    metrics = collect(reader)
    [p] = points(metrics, :"gen_ai.client.operation.duration")
    assert point(p, :count) == 100
    assert point(p, :attributes) == %{"gen_ai.request.model" => "other", "error.type" => "error"}
    refute inspect(metrics) =~ "private-"
  end

  test "SDK restart recreates public instruments and stopped SDK calls are harmless", %{
    reader: reader
  } do
    [record | _] = Mapper.stop(%{model: "fixture"}, 1)
    Metrics.record_histogram(record, metrics: [models: ["fixture"]])
    assert [_] = collect(reader)
    :ok = Application.stop(:opentelemetry_experimental)
    assert :ok == Metrics.record_histogram(record, metrics: [models: ["fixture"]])
    {:ok, _} = Application.ensure_all_started(:opentelemetry_experimental)
    assert_receive {:reader, new_reader}
    Metrics.record_histogram(record, metrics: [models: ["fixture"]])
    assert [metric] = collect(new_reader)
    assert [p] = histogram(metric(metric, :data), :datapoints)
    assert point(p, :count) == 1
  end

  test "the single integrated bridge records one buffered request without duplicate metrics",
       %{reader: reader} do
    assert :ok == Integration.attach(metrics: [models: ["fixture"]])
    owner = self()

    transport = fn request ->
      send(owner, :request)

      body =
        Jason.encode!(%{
          "id" => "fixture",
          "model" => "fixture",
          "choices" => [
            %{
              "index" => 0,
              "message" => %{"role" => "assistant", "content" => "done"},
              "finish_reason" => "stop"
            }
          ],
          "usage" => %{"prompt_tokens" => 3, "completion_tokens" => 2, "total_tokens" => 5}
        })

      {request,
       Req.Response.new(status: 200, headers: [{"content-type", "application/json"}], body: body)}
    end

    model =
      ExAgent.Models.ReqLLM.new(
        model: %{
          provider: :openai,
          id: "fixture",
          capabilities: %{reasoning: %{enabled: false}, tools: %{enabled: true}},
          extra: %{wire: %{protocol: "openai_chat"}}
        },
        api_key: "synthetic",
        tool_profile: :chat_tools_v1,
        base_url: "https://fixture.invalid/v1",
        http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
      )

    assert {:ok, %{request_count: 1} = result} =
             ExAgent.run(
               ExAgent.new(
                 model: model,
                 observability: ExAgent.Observability.OpenTelemetry.new()
               ),
               "PRIVATE_PROMPT"
             )

    assert result.output == "done"
    assert result.usage.input_tokens == 3
    assert_receive :request
    refute_receive :request, 0
    metrics = collect(reader)
    [duration] = points(metrics, :"gen_ai.client.operation.duration")
    assert point(duration, :count) == 1

    assert Enum.sort(Enum.map(points(metrics, :"gen_ai.client.token.usage"), &point(&1, :sum))) ==
             [2, 3]

    refute inspect(metrics) =~ "PRIVATE_PROMPT"

    assert length(
             :telemetry.list_handlers([:req_llm, :request, :start])
             |> Enum.filter(&(&1.id == Integration))
           ) == 1
  end

  test "default ExAgent tracing follows a restarted application-owned SDK" do
    agent = ExAgent.new(model: "test", observability: ExAgent.Observability.OpenTelemetry.new())
    assert {:ok, _} = ExAgent.run(agent, "before")
    :ok = Application.stop(:opentelemetry_experimental)
    :ok = Application.stop(:opentelemetry)
    Application.put_env(:opentelemetry, :processors, [{SpanProcessor, %{owner: self()}}])
    {:ok, _} = Application.ensure_all_started(:opentelemetry)
    assert {:ok, _} = ExAgent.run(agent, "after")
    assert_receive {:restart_span, _}
    assert_receive {:restart_span, _}
    refute_receive {:restart_span, _}, 0
  end
end
