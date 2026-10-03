defmodule ExAgent.Observability.ReqLLMBridgeTest do
  use ExUnit.Case, async: false
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  alias ExAgent.Observability.OpenTelemetry
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
      :otel_ctx.clear()
    end)

    :ok
  end

  for surface <- [:sync, :stream], upstream? <- [false, true] do
    @surface surface
    @upstream upstream?
    test "#{surface}: explicit ReqLLM bridge #{@upstream} has one HTTP request and #{if upstream?, do: 2, else: 1} generation observations" do
      if @upstream, do: assert(:ok == ReqLLM.OpenTelemetry.attach(@handler))
      {url, peer} = peer(@surface)

      model =
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

      agent =
        ExAgent.new(
          model: model,
          observability: OpenTelemetry.new(),
          model_settings: [max_tokens: 64],
          usage_limits: %ExAgent.UsageLimits{request_limit: 1}
        )

      result =
        case @surface do
          :sync ->
            assert {:ok, result} = ExAgent.run(agent, "PRIVATE_BRIDGE_PROMPT")
            result

          :stream ->
            events = ExAgent.run_stream(agent, "PRIVATE_BRIDGE_PROMPT") |> Enum.to_list()

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
      assert_receive {:fixture_request, payload}
      assert is_list(payload["messages"])
      assert :ok == Task.await(peer, 5_000)
      refute_receive {:fixture_request, _}, 0

      spans = collect(if(@upstream, do: 3, else: 2))
      [run] = Enum.filter(spans, &(&1.attrs["exagent.operation"] == "run"))
      [model_span] = Enum.filter(spans, &(&1.attrs["exagent.operation"] == "model"))
      assert model_span.parent == run.id and model_span.trace == run.trace
      assert run.attrs["exagent.usage.request_count"] == 1
      generations = Enum.filter(spans, &Map.has_key?(&1.attrs, "gen_ai.usage.output_tokens"))
      assert length(generations) == if(@upstream, do: 2, else: 1)

      assert Enum.sum(Enum.map(generations, & &1.attrs["gen_ai.usage.output_tokens"])) ==
               if(@upstream, do: 4, else: 2)

      assert model_span.attrs["exagent.usage.quality"] == "normalized"
      assert model_span.attrs["exagent.usage.normalized_input_tokens"] == 3

      if @surface == :stream,
        do: assert(model_span.attrs["gen_ai.usage.input_tokens"] == 3),
        else: refute(Map.has_key?(model_span.attrs, "gen_ai.usage.input_tokens"))

      if @upstream do
        [upstream] = Enum.reject(generations, &(&1.id == model_span.id))
        assert upstream.parent == model_span.id and upstream.trace == model_span.trace
        assert upstream.attrs["gen_ai.usage.input_tokens"] == 3
      end

      for item <- spans do
        attributes = inspect(item.attrs)
        refute attributes =~ "SYNTHETIC_BRIDGE_KEY"
        refute attributes =~ "PRIVATE_BRIDGE_PROMPT"
        refute attributes =~ "TRACE_OK"
      end

      refute_receive {:bridge_span, _}, 0
    end
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

  defp peer(surface) do
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
                       "finish_reason" => "stop"
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
