Code.require_file("../../support/protocol_fragmentation.exs", __DIR__)

defmodule ExAgent.Providers.ProtocolFragmentationTest do
  # Req defaults are VM-wide, as in StreamTransportTest's existing fake.
  use ExUnit.Case, async: false

  alias ExAgent.Message.{Part, Request, Response}
  alias ExAgent.Models.{Anthropic, OpenAI}
  alias ExAgent.Providers.SSE
  alias ExAgent.Test.ProtocolFragmentation, as: Fragments

  setup do
    previous = Req.default_options()
    on_exit(fn -> Req.default_options(previous) end)
    :ok
  end

  for provider <- [:openai, :anthropic] do
    @provider provider
    test "#{provider} multisplits retain sync/stream tool effects, model and both histories" do
      parent = self()
      model = model(@provider)

      tool =
        ExAgent.Tool.new(
          name: "record",
          takes_ctx: false,
          parameters_json_schema: %{
            "type" => "object",
            "properties" => %{"text" => %{"type" => "string"}},
            "required" => ["text"]
          },
          call: fn args ->
            send(parent, {:effect, args})
            "guardado ñ😊"
          end
        )

      agent = ExAgent.new(model: model, tools: [tool], instructions: "Sintético")
      history = [ExAgent.Message.new_request([%Part.User{content: "anterior"}])]
      opts = [message_history: history]

      install_conversation(@provider, hd(Fragments.seeds()))
      assert {:ok, baseline} = ExAgent.run(agent, "acción", opts)
      assert_receive {:effect, %{"text" => "á😊"}}, 1_000
      expected_requests = requests()
      assert length(expected_requests) == 2
      assert baseline.output == "Listo ñ😊"
      assert baseline.request_count == 2
      assert baseline.tool_calls == 1
      assert baseline.usage.input_tokens == 10
      assert baseline.usage.output_tokens == 6

      assert [%Part.ToolReturn{content: "guardado ñ😊", status: :succeeded}] =
               baseline.messages
               |> ExAgent.Message.parts()
               |> Enum.filter(&match?(%Part.ToolReturn{}, &1))

      for seed <- Fragments.seeds(), mode <- [:stream_text, :public_stream] do
        install_conversation(@provider, seed)

        result =
          case mode do
            :stream_text ->
              assert {:ok, result} = ExAgent.run(agent, "acción", opts ++ [stream_text: true])
              result

            :public_stream ->
              events = ExAgent.run_stream(agent, "acción", opts) |> Enum.to_list()
              assert [{:result, result}] = Enum.reject(events, &match?({:delta, _}, &1))

              assert Enum.map_join(events, fn
                       {:delta, text} -> text
                       _ -> ""
                     end) == "Listo ñ😊"

              result
          end

        assert_receive {:effect, %{"text" => "á😊"}}, 1_000
        refute_received {:effect, _}
        assert requests() == expected_requests
        assert result.model == model
        assert comparable(result) == comparable(baseline), "provider=#{@provider} seed=#{seed}"
      end
    end
  end

  test "EOF after complete tool arguments never commits an effect or a success in either stream API" do
    parent = self()

    tool =
      ExAgent.Tool.new(
        name: "record",
        takes_ctx: false,
        call: fn _ -> send(parent, :unexpected_effect) end
      )

    for provider <- [:openai, :anthropic], seed <- Fragments.seeds() do
      {_body, events} = reply(provider, false)
      # Arguments, finish reason and usage are present, but the required
      # provider terminal is missing. Such a response is still provisional.
      wire = events |> Enum.drop(-1) |> Enum.map_join(&frame/1)

      Req.default_options(
        adapter: fn request -> callback(request, Fragments.partition(wire, seed)) end
      )

      agent = ExAgent.new(model: model(provider), tools: [tool])
      assert {:error, sync_error} = ExAgent.run(agent, "go", stream_text: true)
      assert [{:error, stream_error}] = ExAgent.run_stream(agent, "go") |> Enum.to_list()

      for error <- [sync_error, stream_error] do
        assert %ExAgent.RunError{
                 reason:
                   {:model_request_failed,
                    %ExAgent.RequestError{reason: :missing_stream_terminal}},
                 partial: partial
               } = error

        assert partial.model == agent.model
        assert partial.request_count == 1
        assert partial.tool_calls == 0
        assert partial.status == :failed
        refute Enum.any?(partial.messages, &match?(%Response{}, &1))
      end

      assert comparable(sync_error.partial) == comparable(stream_error.partial)
      refute_received :unexpected_effect
    end
  end

  test "multisplit SSE preserves a valid prefix before malformed, UTF8-truncated and oversized tails" do
    for newline <- ["\n", "\r\n", "\r"], seed <- Fragments.seeds() do
      prefix = "data: {\"text\":\"á😊\"}#{newline}#{newline}"

      for {tail, reason, limits} <- [
            {"data: {\"x\":\"" <> <<0xF0, 0x9F>>, :truncated_sse_frame, []},
            {"data: []#{newline}#{newline}", :invalid_sse_json, []},
            {":" <> String.duplicate("x", 65), {:stream_limit, :max_frame_bytes},
             [max_frame_bytes: 64]},
            {":" <> String.duplicate("x", 65), {:stream_limit, :max_buffer_bytes},
             [max_buffer_bytes: 64]}
          ] do
        wire = prefix <> tail
        marker = make_ref()
        send(self(), {:unrelated, marker})

        source =
          Stream.resource(
            fn -> Fragments.partition(wire, seed) end,
            fn
              [] -> {:halt, []}
              [chunk | rest] -> {[chunk], rest}
            end,
            fn _ -> send(self(), {:closed, marker}) end
          )

        assert [%{"text" => "á😊"}, {:error, ^reason}] = Enum.to_list(SSE.stream(source, limits))
        assert_receive {:closed, ^marker}, 0
        refute_received {:closed, ^marker}
        assert_receive {:unrelated, ^marker}, 0
      end
    end
  end

  for finish <- [:resume, :halt, :death] do
    @finish finish
    test "public provider stream survives two fragmented suspensions then #{@finish}" do
      parent = self()
      token = make_ref()
      first = openai_chunk(%{"content" => "á😊"}) |> frame()
      second = openai_chunk(%{"content" => "ñ"}, "stop") |> frame()
      terminal = frame(:done)
      chunks = Fragments.partition(first, 37_556) ++ Fragments.partition(second, 106_033)
      # A final callback barrier is causal evidence that the HTTP worker is
      # waiting on demand while the consumer holds its second continuation.
      install_chunks(chunks ++ [terminal], token)

      {consumer, consumer_monitor} =
        spawn_monitor(fn ->
          send(self(), {:unrelated, token})
          foreign = make_ref()
          send(self(), {foreign, :item, :keep})
          stream = ExAgent.run_stream(ExAgent.new(model: model(:openai)), "go")

          {:suspended, {:delta, "á😊"}, continuation} =
            Enumerable.reduce(stream, {:cont, nil}, fn event, _ -> {:suspend, event} end)

          send(parent, {:paused, token, 1})

          receive do
            :next -> :ok
          end

          {:suspended, {:delta, "ñ"}, continuation} = continuation.({:cont, nil})
          send(parent, {:paused, token, 2})

          receive do
            :resume ->
              {:suspended, {:result, result}, continuation} = continuation.({:cont, nil})
              {:halted, nil} = continuation.({:cont, nil})
              send(parent, {:result, token, result})

            :halt ->
              {:halted, nil} = continuation.({:halt, nil})
          end

          receive do
            {:unrelated, ^token} -> :ok
          end

          receive do
            {^foreign, :item, :keep} -> :ok
          end

          send(parent, {:mailbox_preserved, token, Process.info(self(), :messages)})
        end)

      on_exit(fn -> if Process.alive?(consumer), do: Process.exit(consumer, :kill) end)
      assert_receive {:http_worker, ^token, worker}, 1_000
      worker_monitor = Process.monitor(worker)
      assert_receive {:paused, ^token, 1}, 1_000
      assert Process.alive?(worker)
      send(consumer, :next)
      assert_receive {:paused, ^token, 2}, 1_000
      assert_receive {:callback, ^token, index} when index == length(chunks), 1_000
      assert Process.alive?(worker)
      refute_received {:result, ^token, _}

      if @finish == :death do
        Process.exit(consumer, :kill)
      else
        send(consumer, @finish)
        assert_receive {:mailbox_preserved, ^token, {:messages, []}}, 1_000
      end

      assert_receive {:DOWN, ^consumer_monitor, :process, ^consumer, _}, 1_000
      assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}, 1_000

      if @finish == :resume do
        assert_receive {:result, ^token, %{output: "á😊ñ", request_count: 1}}, 0
      end

      refute_received {:result, ^token, _}
      refute_received {:http_worker, ^token, _}
    end
  end

  defp model(:openai),
    do: %OpenAI{model: "wire-model", api_key: "offline", base_url: "http://unused.invalid"}

  defp model(:anthropic),
    do: %Anthropic{model: "wire-model", api_key: "offline", base_url: "http://unused.invalid"}

  defp install_conversation(provider, seed) do
    parent = self()

    Req.default_options(
      adapter: fn request ->
        body = Jason.decode!(request.body)
        send(parent, {:request, Map.drop(body, ["stream", "stream_options"])})
        second? = Enum.any?(body["messages"], &(&1["role"] == "assistant"))
        {response, events} = reply(provider, second?)

        if body["stream"] do
          wire = Enum.map_join(events, &frame/1)
          callback(request, Fragments.partition(wire, seed))
        else
          {request, Req.Response.new(status: 200, body: response)}
        end
      end
    )
  end

  defp install_chunks(chunks, token) do
    parent = self()

    Req.default_options(
      adapter: fn request ->
        send(parent, {:http_worker, token, self()})

        Enum.reduce_while(Enum.with_index(chunks), {request, Req.Response.new(status: 200)}, fn
          {chunk, index}, acc ->
            send(parent, {:callback, token, index})
            request.into.({:data, chunk}, acc)
        end)
      end
    )
  end

  defp callback(request, chunks) do
    Enum.reduce_while(chunks, {request, Req.Response.new(status: 200)}, fn chunk, acc ->
      request.into.({:data, chunk}, acc)
    end)
  end

  defp reply(:openai, second?) do
    usage = %{"prompt_tokens" => 5, "completion_tokens" => 3}

    {message, events, finish} =
      if second? do
        {%{"content" => "Listo ñ😊"},
         [openai_chunk(%{"content" => "Listo "}), openai_chunk(%{"content" => "ñ😊"}, "stop")],
         "stop"}
      else
        call = %{
          "id" => "c1",
          "type" => "function",
          "function" => %{"name" => "record", "arguments" => "{\"text\":\"á😊\"}"}
        }

        first =
          %{call | "function" => %{"name" => "rec", "arguments" => "{\"text\":"}}
          |> Map.put("index", 0)

        last = %{"index" => 0, "function" => %{"name" => "ord", "arguments" => "\"á😊\"}"}}

        {%{"tool_calls" => [call]},
         [
           openai_chunk(%{"tool_calls" => [first]}),
           openai_chunk(%{"tool_calls" => [last]}, "tool_calls")
         ], "tool_calls"}
      end

    {%{
       "model" => "wire-model",
       "usage" => usage,
       "choices" => [%{"message" => message, "finish_reason" => finish}]
     }, events ++ [%{"choices" => [], "usage" => usage}, :done]}
  end

  defp reply(:anthropic, second?) do
    usage = %{"input_tokens" => 5, "output_tokens" => 3}

    {block, initial, deltas, finish} =
      if second? do
        {%{"type" => "text", "text" => "Listo ñ😊"}, %{"type" => "text", "text" => "Listo "},
         [%{"type" => "text_delta", "text" => "ñ😊"}], "end_turn"}
      else
        block = %{
          "type" => "tool_use",
          "id" => "c1",
          "name" => "record",
          "input" => %{"text" => "á😊"}
        }

        {block, %{block | "input" => %{}},
         [
           %{"type" => "input_json_delta", "partial_json" => "{\"text\":"},
           %{"type" => "input_json_delta", "partial_json" => "\"á😊\"}"}
         ], "tool_use"}
      end

    events =
      [
        %{
          "type" => "message_start",
          "message" => %{"model" => "wire-model", "usage" => %{usage | "output_tokens" => 0}}
        },
        %{"type" => "content_block_start", "index" => 0, "content_block" => initial}
      ] ++
        Enum.map(deltas, &%{"type" => "content_block_delta", "index" => 0, "delta" => &1}) ++
        [
          %{"type" => "content_block_stop", "index" => 0},
          %{
            "type" => "message_delta",
            "delta" => %{"stop_reason" => finish},
            "usage" => %{"output_tokens" => 3}
          },
          %{"type" => "message_stop"}
        ]

    {%{"model" => "wire-model", "content" => [block], "stop_reason" => finish, "usage" => usage},
     events}
  end

  defp openai_chunk(delta, finish \\ nil),
    do: %{
      "model" => "wire-model",
      "choices" => [%{"index" => 0, "delta" => delta, "finish_reason" => finish}]
    }

  defp frame(:done), do: "data: [DONE]\r\n\r\n"
  defp frame(event), do: "data: " <> Jason.encode!(event) <> "\r\n\r\n"

  defp requests(acc \\ []) do
    receive do
      {:request, body} -> requests([body | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # Timestamps and run IDs identify separate runs; every other message field,
  # including tool identity/status, usage, model name and args, must agree.
  defp comparable(result) do
    result
    |> Map.take([
      :output,
      :model,
      :usage,
      :status,
      :usage_status,
      :request_count,
      :tool_calls,
      :run_step
    ])
    |> Map.put(:messages, Enum.map(result.messages, &without_clock/1))
    |> Map.put(:new_messages, Enum.map(result.new_messages, &without_clock/1))
  end

  defp without_clock(%Request{} = message),
    do: %{message | timestamp: nil, run_id: nil, parts: Enum.map(message.parts, &without_clock/1)}

  defp without_clock(%Response{} = message), do: %{message | timestamp: nil}
  defp without_clock(%Part.User{} = part), do: %{part | timestamp: nil}
  defp without_clock(part), do: part
end
