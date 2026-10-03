defmodule ExAgent.Observability.ReqLLMBridgeTest do
  use ExUnit.Case, async: false
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  alias ExAgent.Observability.OpenTelemetry
  alias ExAgent.Observability.ReqLLM, as: Integration
  @owner :exagent_req_llm_bridge_owner
  @handler "exagent-req-llm-bridge-negative-control"

  defmodule Processor do
    def on_start(_, span, _), do: span

    def on_end(span, _) do
      send(Process.whereis(:exagent_req_llm_bridge_owner), {:bridge_span, span})
      true
    end

    def force_flush(_), do: :ok
  end

  setup_all do
    old = Application.get_env(:opentelemetry, :processors)
    Application.put_env(:opentelemetry, :processors, [{Processor, %{}}])
    {:ok, started} = Application.ensure_all_started(:opentelemetry)
    assert :opentelemetry in started, "This fixture must own its SDK startup"

    on_exit(fn ->
      Application.stop(:opentelemetry)

      if old == nil,
        do: Application.delete_env(:opentelemetry, :processors),
        else: Application.put_env(:opentelemetry, :processors, old)
    end)

    :ok
  end

  setup do
    Process.register(self(), @owner)
    :otel_ctx.clear()
    # Do not detach the default handler: that could hide automatic attachment.
    refute Enum.any?(
             :telemetry.list_handlers([:req_llm, :request, :start]),
             &(&1.id == "req-llm-open-telemetry")
           )

    on_exit(fn ->
      ReqLLM.OpenTelemetry.detach(@handler)
      Integration.detach()
      :otel_ctx.clear()
    end)

    :ok
  end

  for surface <- [:sync, :stream], integrated? <- [false, true] do
    @surface surface
    @integrated integrated?
    test "#{surface}: integrated bridge #{@integrated} retains one generation observation" do
      if @integrated, do: assert(:ok == Integration.attach())
      {url, peer} = peer(@surface)

      model = model(url)

      agent =
        ExAgent.new(
          model: model,
          observability: OpenTelemetry.new(),
          model_settings: [max_tokens: 64],
          usage_limits: %ExAgent.UsageLimits{request_limit: 1}
        )

      pricing_calls = :atomics.new(1, [])

      estimate = fn _ ->
        :atomics.add(pricing_calls, 1, 1)
        0.25
      end

      result =
        case @surface do
          :sync ->
            assert {:ok, result} =
                     ExAgent.run(agent, "PRIVATE_BRIDGE_PROMPT", estimate_cost: estimate)

            result

          :stream ->
            events =
              ExAgent.run_stream(agent, "PRIVATE_BRIDGE_PROMPT", estimate_cost: estimate)
              |> Enum.to_list()

            assert [{:result, result}] =
                     Enum.filter(events, fn {kind, _} -> kind in [:result, :error] end)

            assert events
                   |> Enum.flat_map(fn
                     {:delta, text} -> [text]
                     _ -> []
                   end)
                   |> Enum.join() == result.output

            result
        end

      assert result.output == "TRACE_OK" and result.request_count == 1 and result.tool_calls == 0
      assert result.usage.input_tokens == 3 and result.usage.output_tokens == 2
      assert result.cost_cents == 0.25 and :atomics.get(pricing_calls, 1) == 1
      assert_receive {:fixture_request, payload}
      assert is_list(payload["messages"])
      assert :ok == Task.await(peer, 5_000)
      refute_receive {:fixture_request, _}, 0

      spans = collect(2)
      [run] = Enum.filter(spans, &(&1.attrs["exagent.operation"] == "run"))
      [model_span] = Enum.filter(spans, &(&1.attrs["exagent.operation"] == "model"))
      assert model_span.parent == run.id and model_span.trace == run.trace
      assert run.attrs["exagent.usage.request_count"] == 1
      generations = Enum.filter(spans, &Map.has_key?(&1.attrs, "gen_ai.usage.output_tokens"))
      assert length(generations) == 1

      assert Enum.sum(Enum.map(generations, & &1.attrs["gen_ai.usage.output_tokens"])) ==
               2

      assert model_span.attrs["exagent.usage.quality"] == "normalized"
      assert model_span.attrs["exagent.cost.cents"] == 0.25
      refute Map.has_key?(model_span.attrs, "gen_ai.usage.cost")
      assert model_span.attrs["exagent.usage.normalized_input_tokens"] == 3

      if @surface == :stream,
        do: assert(model_span.attrs["gen_ai.usage.input_tokens"] == 3),
        else: refute(Map.has_key?(model_span.attrs, "gen_ai.usage.input_tokens"))

      if @integrated do
        assert is_binary(model_span.attrs["exagent.req_llm.request_id"])
        assert model_span.attrs["gen_ai.request.max_tokens"] == 64
        assert model_span.attrs["server.address"] == "127.0.0.1"

        if @surface == :stream do
          assert model_span.attrs["gen_ai.request.stream"] == true
          assert model_span.attrs["gen_ai.response.time_to_first_chunk"] >= 0
        end
      end

      for item <- spans do
        attributes = inspect(item.attrs)
        refute attributes =~ "SYNTHETIC_BRIDGE_KEY"
        refute attributes =~ "PRIVATE_BRIDGE_PROMPT"
        refute attributes =~ "TRACE_OK"
      end

      refute_receive {:bridge_span, _}, 0
      assert OpenTelemetry.current_model_span() == nil
    end
  end

  for surface <- [:sync, :stream] do
    @surface surface
    test "#{surface}: incompatible stock bridge rejects before HTTP" do
      assert :ok == ReqLLM.OpenTelemetry.attach(@handler)
      {url, peer} = peer(@surface)
      agent = ExAgent.new(model: model(url), observability: OpenTelemetry.new())

      error =
        case @surface do
          :sync ->
            assert {:error, error} = ExAgent.run(agent, "PRIVATE_BRIDGE_PROMPT")
            error

          :stream ->
            assert [{:error, error}] =
                     Enum.to_list(ExAgent.run_stream(agent, "PRIVATE_BRIDGE_PROMPT"))

            error
        end

      assert {:model_request_failed,
              %ExAgent.RequestError{reason: {:observability_conflict, :req_llm_bridge}}} =
               error.reason

      refute_receive {:fixture_request, _}, 0
      Task.shutdown(peer, :brutal_kill)
      spans = collect(2)
      assert Enum.all?(spans, &(&1.attrs["exagent.status"] == "failed"))
      refute_receive {:bridge_span, _}, 0
    end
  end

  test "attach refuses a foreign bridge without detaching it" do
    assert :ok == ReqLLM.OpenTelemetry.attach(@handler)
    assert {:error, :conflicting_req_llm_bridge} = Integration.attach()
    assert Enum.any?(:telemetry.list_handlers([:req_llm, :request, :start]), &(&1.id == @handler))
  end

  test "a foreign ReqLLM bridge does not disable a Model that does not use ReqLLM" do
    assert :ok == ReqLLM.OpenTelemetry.attach(@handler)
    agent = ExAgent.new(model: "test", observability: OpenTelemetry.new())
    assert {:ok, _} = ExAgent.run(agent, "go")
    assert length(collect(2)) == 2
    refute_receive {:bridge_span, _}, 0
  end

  test "observability false leaves the application's stock bridge active" do
    assert :ok == ReqLLM.OpenTelemetry.attach(@handler)
    {url, peer} = peer(:sync)
    assert {:ok, _} = ExAgent.run(ExAgent.new(model: model(url), observability: false), "go")
    assert :ok == Task.await(peer, 5_000)
    [generation] = collect(1)
    refute Map.has_key?(generation.attrs, "exagent.operation")
    assert generation.attrs["gen_ai.usage.output_tokens"] == 2
    refute_receive {:bridge_span, _}, 0
  end

  test "two compatible bridge registrations are rejected before provider IO" do
    assert :ok == Integration.attach()
    assert :ok == ReqLLM.OpenTelemetry.attach(@handler, adapter: Integration)
    {url, peer} = peer(:sync)
    agent = ExAgent.new(model: model(url), observability: OpenTelemetry.new())
    assert {:error, error} = ExAgent.run(agent, "go")

    assert {:model_request_failed,
            %ExAgent.RequestError{reason: {:observability_conflict, :req_llm_bridge}}} =
             error.reason

    Task.shutdown(peer, :brutal_kill)
    refute_receive {:fixture_request, _}, 0
    assert length(collect(2)) == 2
  end

  test "standalone ReqLLM calls retain stock generation telemetry" do
    assert :ok == Integration.attach()
    assert {:error, :already_exists} == Integration.attach()
    {url, peer} = peer(:sync)

    assert {:ok, response} =
             ReqLLM.generate_text(model(url).model, "PRIVATE_BRIDGE_PROMPT",
               api_key: "SYNTHETIC_BRIDGE_KEY",
               base_url: url
             )

    assert ReqLLM.Response.text(response) == "TRACE_OK"
    assert_receive {:fixture_request, _}
    assert :ok == Task.await(peer, 5_000)
    [generation] = collect(1)
    refute Map.has_key?(generation.attrs, "exagent.operation")
    assert generation.attrs["gen_ai.usage.input_tokens"] == 3
    assert generation.attrs["gen_ai.usage.output_tokens"] == 2
    refute_receive {:bridge_span, _}, 0
  end

  test "standalone streaming retains stock timing and generation usage" do
    assert :ok == Integration.attach()
    {url, peer} = peer(:stream)

    assert {:ok, stream} =
             ReqLLM.stream_text(model(url).model, "direct",
               api_key: "SYNTHETIC_BRIDGE_KEY",
               base_url: url
             )

    assert {:ok, response} = ReqLLM.StreamResponse.process_stream(stream)
    assert ReqLLM.Response.text(response) == "TRACE_OK"
    assert :ok == Task.await(peer, 5_000)
    [generation] = collect(1)
    assert generation.attrs["gen_ai.usage.output_tokens"] == 2
    assert generation.attrs["gen_ai.response.time_to_first_chunk"] >= 0
    refute Map.has_key?(generation.attrs, "exagent.operation")
    refute_receive {:bridge_span, _}, 0
  end

  test "standalone adapter preserves native child span parentage and status" do
    parent = Integration.start_span("direct", %{}, [])

    child =
      Integration.start_child_span(
        parent,
        "execute_tool",
        %{"gen_ai.tool.name" => "search"},
        %{},
        []
      )

    Integration.set_status(child, :error, "synthetic failure", [])
    Integration.end_span(child, [])
    Integration.end_span(parent, [])
    [child_span, parent_span] = collect(2)
    assert child_span.parent == parent_span.id and child_span.trace == parent_span.trace
    assert child_span.attrs["gen_ai.tool.name"] == "search"
  end

  test "concurrent ExAgent and standalone calls keep independent span ownership" do
    assert :ok == Integration.attach()
    {owned_url, owned_peer} = peer(:sync, barrier: true)
    {direct_url, direct_peer} = peer(:sync, barrier: true)

    owned =
      Task.async(fn ->
        ExAgent.run(
          ExAgent.new(model: model(owned_url), observability: OpenTelemetry.new()),
          "go"
        )
      end)

    direct =
      Task.async(fn ->
        ReqLLM.generate_text(model(direct_url).model, "direct",
          api_key: "SYNTHETIC_BRIDGE_KEY",
          base_url: direct_url
        )
      end)

    assert_receive {:fixture_waiting, first}, 5_000
    assert_receive {:fixture_waiting, second}, 5_000
    assert first != second
    send(first, :reply)
    send(second, :reply)
    assert {:ok, result} = Task.await(owned, 5_000)
    assert {:ok, response} = Task.await(direct, 5_000)
    assert result.usage.output_tokens == 2 and ReqLLM.Response.usage(response).output_tokens == 2
    assert :ok == Task.await(owned_peer, 5_000)
    assert :ok == Task.await(direct_peer, 5_000)
    spans = collect(3)
    [ours] = Enum.filter(spans, &(&1.attrs["exagent.operation"] == "model"))
    [standalone] = Enum.reject(spans, &Map.has_key?(&1.attrs, "exagent.operation"))
    assert standalone.trace != ours.trace
    assert standalone.attrs["gen_ai.usage.output_tokens"] == 2
    assert ours.attrs["gen_ai.usage.output_tokens"] == 2
    refute_receive {:bridge_span, _}, 0
  end

  test "global raw telemetry cannot bypass ExAgent's content policy" do
    previous = Application.get_env(:req_llm, :telemetry)
    Application.put_env(:req_llm, :telemetry, payloads: :raw)
    journal = {__MODULE__, :journal}

    assert :ok ==
             :telemetry.attach_many(
               journal,
               [[:req_llm, :request, :start], [:req_llm, :request, :stop]],
               &__MODULE__.journal/4,
               self()
             )

    on_exit(fn ->
      :telemetry.detach(journal)

      if previous == nil,
        do: Application.delete_env(:req_llm, :telemetry),
        else: Application.put_env(:req_llm, :telemetry, previous)
    end)

    assert :ok == Integration.attach(content: :attributes, langfuse: true)
    {url, peer} = peer(:stream)
    agent = ExAgent.new(model: model(url), observability: OpenTelemetry.new())

    assert [{:result, _}] =
             ExAgent.run_stream(agent, "PRIVATE_BRIDGE_PROMPT")
             |> Enum.reject(fn {kind, _} -> kind == :delta end)

    assert :ok == Task.await(peer, 5_000)
    assert_receive {:req_journal, :start, start}
    assert_receive {:req_journal, :stop, stop}
    assert start.request_id == stop.request_id
    assert Map.keys(start) == [:request_id] and Map.keys(stop) == [:request_id]

    for item <- collect(2) do
      refute inspect(item.attrs) =~ "PRIVATE_BRIDGE_PROMPT"
      refute inspect(item.attrs) =~ "TRACE_OK"
    end
  end

  test "provider stop cannot turn an ExAgent incomplete terminal into success" do
    assert :ok == Integration.attach()
    {url, peer} = peer(:sync, finish: "length")
    agent = ExAgent.new(model: model(url), observability: OpenTelemetry.new())
    assert {:error, %ExAgent.RunError{}} = ExAgent.run(agent, "go")
    assert :ok == Task.await(peer, 5_000)
    spans = collect(2)
    [model_span] = Enum.filter(spans, &(&1.attrs["exagent.operation"] == "model"))
    assert model_span.attrs["exagent.status"] == "failed"
    refute_receive {:bridge_span, _}, 0
  end

  test "owned adapter callbacks cannot overwrite accounting, export raw errors or end the span" do
    operation = OpenTelemetry.start(OpenTelemetry.new(), :model, %{})
    OpenTelemetry.attributes(operation, %{"gen_ai.usage.output_tokens" => 2})

    OpenTelemetry.within(operation, fn ->
      owned = Integration.start_span("unused", %{}, [])

      assert :ok ==
               Integration.set_attributes(
                 owned,
                 %{
                   "req_llm.request_id" => "safe-id",
                   "gen_ai.usage.output_tokens" => 99,
                   "gen_ai.usage.cost" => 99.0,
                   "gen_ai.input.messages" => "PRIVATE_BRIDGE_PROMPT",
                   "gen_ai.response.id" => String.duplicate("x", 257),
                   "server.address" => "invalid@example",
                   "server.port" => 0,
                   "gen_ai.response.time_to_first_chunk" => -1
                 },
                 []
               )

      assert :ok == Integration.add_event(owned, :exception, %{message: "PRIVATE_ERROR"}, [])
      assert :ok == Integration.set_status(owned, :error, "PRIVATE_ERROR", [])
      assert owned == Integration.start_child_span(owned, "tool", %{}, %{}, [])
      assert :ok == Integration.end_span_at(owned, 0, [])
      assert :ok == Integration.end_span(owned, [])
      refute_receive {:bridge_span, _}, 0
    end)

    OpenTelemetry.finish(operation, {:ok, %{}})
    [model_span] = collect(1)
    assert model_span.attrs["gen_ai.usage.output_tokens"] == 2
    assert model_span.attrs["exagent.req_llm.request_id"] == "safe-id"
    assert model_span.attrs["exagent.status"] == "succeeded"
    refute Map.has_key?(model_span.attrs, "gen_ai.usage.cost")
    refute Map.has_key?(model_span.attrs, "gen_ai.response.id")
    refute inspect(model_span) =~ "PRIVATE_"
  end

  for sampler <- [:always_on, :always_off] do
    @sampler sampler
    test "named #{@sampler} tracer remains the owner; no default-provider fallback generation" do
      assert :ok == Integration.attach()
      resource = :otel_resource.create(%{})

      config = %{
        sampler: @sampler,
        id_generator: :otel_id_generator,
        deny_list: [],
        processors: [{Processor, %{}}]
      }

      {:ok, provider} = :otel_tracer_provider_sup.start(:bridge_named_provider, resource, config)
      on_exit(fn -> :supervisor.terminate_child(:otel_tracer_provider_sup, provider) end)
      tracer = :otel_tracer_provider.get_tracer(:bridge_named_provider, :exagent, "1", :undefined)
      {url, peer} = peer(:sync)
      agent = ExAgent.new(model: model(url), observability: OpenTelemetry.new(tracer: tracer))
      assert {:ok, _} = ExAgent.run(agent, "go")
      assert :ok == Task.await(peer, 5_000)

      if @sampler == :always_on,
        do: assert(length(collect(2)) == 2)

      refute_receive {:bridge_span, _}, 0
    end
  end

  for surface <- [:sync, :stream] do
    @surface surface
    test "#{surface}: owner death closes ExAgent spans and public prune clears upstream tracking" do
      assert :ok == Integration.attach()
      {url, peer} = peer(@surface, barrier: true)
      agent = ExAgent.new(model: model(url), observability: OpenTelemetry.new())

      {owner, monitor} =
        spawn_monitor(fn ->
          case @surface do
            :sync -> ExAgent.run(agent, "go")
            :stream -> Enum.to_list(ExAgent.run_stream(agent, "go"))
          end
        end)

      assert_receive {:fixture_waiting, _}, 5_000
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
      assert length(collect(2)) == 2
      Task.shutdown(peer, :brutal_kill)
      assert Integration.prune_stale_spans(0) == 1
      assert Integration.prune_stale_spans(0) == 0
      refute_receive {:bridge_span, _}, 0
    end
  end

  def journal([:req_llm, :request, kind], _, metadata, owner) do
    send(
      owner,
      {:req_journal, kind, Map.take(metadata, [:request_id, :request_payload, :response_payload])}
    )
  end

  defp model(url) do
    ExAgent.Models.ReqLLM.new(
      model: %{
        provider: :openai,
        id: "telemetry-fixture",
        extra: %{wire: %{protocol: "openai_chat"}},
        capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
      },
      api_key: "SYNTHETIC_BRIDGE_KEY",
      base_url: url,
      tool_profile: :chat_tools_v1,
      total_timeout: 5_000
    )
  end

  defp collect(0), do: []

  defp collect(count) do
    receive do
      {:bridge_span, value} ->
        [
          %{
            id: span(value, :span_id),
            trace: span(value, :trace_id),
            parent: span(value, :parent_span_id),
            attrs:
              Map.new(:otel_attributes.map(span(value, :attributes)), fn {key, value} ->
                {to_string(key), value}
              end)
          }
          | collect(count - 1)
        ]
    after
      1_000 -> flunk("Native spans did not finish within the fixture bound")
    end
  end

  defp peer(surface, opts \\ []) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()

    task =
      Task.async(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listener, 5_000)
          body = request(socket, "")
          send(owner, {:fixture_request, Jason.decode!(body)})

          if opts[:barrier] do
            send(owner, {:fixture_waiting, self()})

            receive do
              :reply -> :ok
            after
              5_000 -> flunk("Concurrent request did not reach its response barrier")
            end
          end

          usage = %{"prompt_tokens" => 3, "completion_tokens" => 2, "total_tokens" => 5}

          {type, bytes} =
            case surface do
              :sync ->
                {"application/json",
                 Jason.encode!(%{
                   "id" => "bridge",
                   "model" => "telemetry-fixture",
                   "choices" => [
                     %{
                       "index" => 0,
                       "message" => %{"role" => "assistant", "content" => "TRACE_OK"},
                       "finish_reason" => opts[:finish] || "stop"
                     }
                   ],
                   "usage" => usage
                 })}

              :stream ->
                first = %{
                  "id" => "bridge",
                  "model" => "telemetry-fixture",
                  "choices" => [
                    %{"index" => 0, "delta" => %{"content" => "TRACE_OK"}, "finish_reason" => nil}
                  ]
                }

                last = %{
                  "id" => "bridge",
                  "model" => "telemetry-fixture",
                  "choices" => [%{"index" => 0, "delta" => %{}, "finish_reason" => "stop"}],
                  "usage" => usage
                }

                {"text/event-stream",
                 "data: " <>
                   Jason.encode!(first) <>
                   "\n\ndata: " <> Jason.encode!(last) <> "\n\ndata: [DONE]\n\n"}
            end

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n" <>
                bytes
            )

          :gen_tcp.close(socket)
          :ok
        after
          :gen_tcp.close(listener)
        end
      end)

    on_exit(fn -> :gen_tcp.close(listener) end)
    {"http://127.0.0.1:#{port}/v1", task}
  end

  defp request(socket, bytes) do
    case :binary.split(bytes, "\r\n\r\n") do
      [headers, body] ->
        [_, length] = Regex.run(~r/content-length: (\d+)/i, headers)
        if byte_size(body) >= String.to_integer(length), do: body, else: more(socket, bytes)

      _ ->
        more(socket, bytes)
    end
  end

  defp more(socket, bytes) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
    request(socket, bytes <> chunk)
  end
end
