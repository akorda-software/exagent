defmodule ExAgent.RetentionLoadTest do
  use ExUnit.Case, async: false
  alias ExAgent.Message.{Part, Response, Usage}
  @h 16_384
  @p 8192
  @data_bound 2 * @h + @p + 65_536

  defmodule SlowModel do
    @behaviour ExAgent.Model
    defstruct [:observer, :id, :journal]
    def model_name(_), do: "bounded-slow-fixture"
    def system(_), do: "test"
    def request(_, _, _, _), do: {:error, :stream_only}

    def request_stream(m, _, _, _) do
      Stream.resource(
        fn ->
          send(m.observer, {:worker, m.id, self()})
          0
        end,
        fn
          n when n < 2 ->
            Agent.update(m.journal, &Map.update!(&1, :deltas, fn c -> c + 1 end))
            {[{:text_delta, String.duplicate("x", 256)}], n + 1}

          2 ->
            r = %Response{
              parts: [%Part.Text{content: String.duplicate("x", 512)}],
              usage: %Usage{input_tokens: 1, output_tokens: 1}
            }

            {[{:response, r, m}], 3}

          3 ->
            {:halt, 3}
        end,
        fn _ ->
          Agent.update(m.journal, &Map.update!(&1, :closed, fn c -> c + 1 end))
        end
      )
    end
  end

  defmodule MultistepModel do
    @behaviour ExAgent.Model
    defstruct [:observer, :journal, step: 0]
    def model_name(_), do: "bounded-multistep"
    def system(_), do: "test"
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}
    def request(_, _, _, _), do: {:error, :stream_only}

    def request_stream(m, _, _, _) do
      Stream.resource(
        fn ->
          send(m.observer, {:multistep_worker, self()})
          Agent.update(m.journal, &Map.update!(&1, :requests, fn n -> n + 1 end))
          next = %{m | step: m.step + 1}
          usage = %Usage{input_tokens: 1, output_tokens: 1}

          if m.step < 2 do
            [
              {:response,
               %Response{
                 parts: [
                   %Part.ToolCall{tool_name: "payload", tool_call_id: "s#{m.step}", args: %{}}
                 ],
                 usage: usage
               }, next}
            ]
          else
            List.duplicate({:text_delta, String.duplicate("x", 1024)}, 6) ++
              [
                {:response,
                 %Response{
                   parts: [%Part.Text{content: String.duplicate("x", 6144)}],
                   usage: usage
                 }, next}
              ]
          end
        end,
        fn
          [] -> {:halt, []}
          [event | rest] -> {[event], rest}
        end,
        fn _ -> Agent.update(m.journal, &Map.update!(&1, :closed, fn n -> n + 1 end)) end
      )
    end
  end

  @tag timeout: 10_000
  test "finite slow-consumer waves retain one bridge snapshot and release every worker" do
    parent = self()

    {:ok, journal} =
      Agent.start_link(fn -> %{deltas: 0, closed: 0, data: 0, history: 0, event: 0} end)

    for wave <- 1..3 do
      tasks =
        for id <- 1..8 do
          Task.async(fn ->
            model = %SlowModel{observer: parent, id: id, journal: journal}
            agent = ExAgent.new(model: model, max_history_bytes: @h, max_payload_bytes: @p)

            progress = fn p ->
              Agent.update(journal, fn stats ->
                %{
                  stats
                  | data: max(stats.data, p.retention.data_bytes),
                    history: max(stats.history, p.retention.history_bytes)
                }
              end)
            end

            stream = ExAgent.run_stream(agent, "go", on_progress: progress)

            {:suspended, [{:delta, first}], continuation} =
              Enumerable.reduce(stream, {:cont, []}, fn event, acc ->
                {:suspend, [event | acc]}
              end)

            send(parent, {:suspended, id, self(), byte_size(first)})

            receive do
              :resume ->
                {status, events} = drain(continuation, [{:delta, first}])
                true = status in [:done, :halted]
                [{:result, result} | _] = events
                bytes = result |> ExAgent.Event.result_payload() |> :erlang.external_size()
                Agent.update(journal, &%{&1 | event: max(&1.event, bytes)})
                :completed

              :halt ->
                {:halted, _} = continuation.({:halt, []})
                :cancelled
            end
          end)
        end

      workers =
        for _ <- 1..8 do
          assert_receive {:worker, id, worker}, 1000
          {id, worker, Process.monitor(worker)}
        end

      callers =
        for _ <- 1..8 do
          assert_receive {:suspended, id, caller, 256}, 1000
          {id, caller}
        end

      assert Agent.get(journal, & &1.deltas) == (wave - 1) * 12 + 8

      for {_, worker, _} <- workers do
        assert Process.alive?(worker)
        assert {:message_queue_len, queued} = Process.info(worker, :message_queue_len)
        assert queued <= 1
        assert {:memory, memory} = Process.info(worker, :memory)
        assert memory <= 16 * 1024 * 1024
      end

      for {id, caller} <- callers, do: send(caller, if(id <= 4, do: :resume, else: :halt))
      outcomes = Enum.map(tasks, &Task.await(&1, 1000))
      assert Enum.frequencies(outcomes) == %{completed: 4, cancelled: 4}

      for {_, worker, ref} <- workers,
          do: assert_receive({:DOWN, ^ref, :process, ^worker, _}, 1000)

      assert Agent.get(journal, & &1.closed) == wave * 8
    end

    stats = Agent.get(journal, & &1)
    assert stats.deltas == 36
    assert stats.closed == 24
    assert stats.history <= @h
    assert stats.data <= @data_bound
    assert stats.event <= 16 * @data_bound
    IO.inspect(stats, label: "R3.4 finite smoke serialized maxima/counters")
  end

  defp drain(continuation, events) do
    case continuation.({:cont, events}) do
      {:suspended, events, continuation} -> drain(continuation, events)
      terminal -> terminal
    end
  end

  @tag timeout: 10_000
  test "three steps retain cumulative near-limit history with confirmed effects and cleanup" do
    h = 24_576

    {:ok, journal} =
      Agent.start_link(fn ->
        %{requests: 0, effects: 0, closed: 0, history: 0, data: 0, memory: 0, context: 0}
      end)

    tool =
      ExAgent.Tool.new(
        name: "payload",
        takes_ctx: true,
        parameters_json_schema: %{"type" => "object", "properties" => %{}},
        call: fn ctx, _ ->
          bytes = ctx |> Map.take([:messages, :usage]) |> :erlang.external_size()
          Agent.update(journal, &%{&1 | effects: &1.effects + 1, context: max(&1.context, bytes)})
          {:ok, String.duplicate("x", 6144)}
        end
      )

    agent =
      ExAgent.new(
        model: %MultistepModel{observer: self(), journal: journal},
        tools: [tool],
        max_payload_bytes: @p,
        max_history_bytes: h
      )

    progress = fn p ->
      {:memory, memory} = Process.info(self(), :memory)

      Agent.update(
        journal,
        &%{
          &1
          | history: max(&1.history, p.retention.history_bytes),
            data: max(&1.data, p.retention.data_bytes),
            memory: max(&1.memory, memory)
        }
      )
    end

    events = Enum.to_list(ExAgent.run_stream(agent, "go", on_progress: progress))
    assert {:result, result} = List.last(events)
    assert result.request_count == 3
    assert result.tool_calls == 2
    assert_receive {:multistep_worker, worker}
    ref = Process.monitor(worker)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
    stats = Agent.get(journal, & &1)
    assert stats.requests == 3 and stats.effects == 2 and stats.closed == 3
    assert stats.history > 0.8 * h and stats.history <= h
    assert stats.data <= 2 * h + @p + 65_536
    assert stats.context <= h + 4096
    assert stats.memory <= 32 * 1024 * 1024
    IO.inspect(stats, label: "R3.4 S3 serialized maxima and observed worker RAM")
  end
end
