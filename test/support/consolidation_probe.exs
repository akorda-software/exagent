# Development diagnostic, deliberately outside the default ExUnit suite.
# EXAGENT_OFFLINE=1 MIX_ENV=test mix run test/support/consolidation_probe.exs --bench
# A false invariant is a known consolidation gap, not a passing regression test.
# Benchmarks use TestModel only; worker memory samples are not peak BEAM memory.
unless Mix.env() == :test and System.get_env("EXAGENT_OFFLINE") == "1" do
  raise "run with EXAGENT_OFFLINE=1 MIX_ENV=test"
end

ExUnit.start(autorun: false)

defmodule ExAgent.ConsolidationProbe.FailingStore do
  @behaviour ExAgent.Store

  @impl true
  def save_agent_snapshot(owner, _snapshot) do
    send(owner, :save_attempted)
    {:error, :probe_store_unavailable}
  end

  @impl true
  def load_agent_snapshot(_, _), do: {:error, :not_found}
  @impl true
  def list_agent_snapshots(_), do: []
  @impl true
  def delete_agent_snapshot(_, _), do: :ok
end

defmodule ExAgent.ConsolidationProbe do
  alias ExAgent.{Coordination, Message, Permissions, Server, Tool, UsageLimits}
  alias ExAgent.Message.Part
  alias ExAgent.Models.Test

  def run do
    probes = [
      {:stream_parity, &stream_parity/0},
      {:sse, &sse/0},
      {:tool_arguments, &tool_arguments/0},
      {:permissions, &permissions/0},
      {:delegation, &delegation/0},
      {:partial_failure, &partial_failure/0},
      {:checkpoint, &checkpoint/0}
    ]

    results =
      Map.new(probes, fn {name, probe} ->
        result =
          Task.async(fn ->
            try do
              probe.()
            rescue
              error -> %{probe_error: Exception.format(:error, error, __STACKTRACE__)}
            end
          end)
          |> Task.await(15_000)

        {name, result}
      end)

    report = %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      probes: results
    }

    report =
      if "--bench" in System.argv(),
        do: Map.put(report, :benchmarks, benchmarks()),
        else: report

    IO.puts(Jason.encode!(report, pretty: true))
  end

  defp stream_parity do
    agent = structured_agent()
    {:ok, normal} = ExAgent.run(agent, "look up a record")
    streamed = agent |> ExAgent.run_stream("look up a record") |> Enum.to_list()
    {:result, result} = Enum.find(streamed, &match?({:result, _}, &1))
    live = ExAgent.run(agent, "look up a record", stream_text: true)

    %{
      same_output: normal.output == result.output,
      stream_has_final_model: Map.has_key?(result, :model),
      normal_steps: normal.run_step,
      normal_output: inspect(normal.output),
      stream_output: inspect(result.output),
      live_loop_result: inspect(live, limit: 10)
    }
  end

  defp sse do
    ref = make_ref()
    control = {:unrelated_control, make_ref()}

    # The consolidated helper consumes byte chunks rather than an already-open
    # Req.Response.Async. Keep the same two CRLF frames and unrelated message;
    # clean HTTP EOF is now distinct from an OpenAI [DONE] sentinel.
    chunks =
      Stream.resource(
        fn -> ["data: {\"n\":1}\r\n\r\ndata: {\"n\":2}\r\n\r\n"] end,
        fn
          [] -> {:halt, []}
          [chunk | rest] -> {[chunk], rest}
        end,
        fn _ -> send(self(), {:closed, ref}) end
      )

    send(self(), control)
    events = ExAgent.Providers.SSE.stream(chunks, timeout: 100) |> Enum.to_list()

    %{
      preserves_unrelated_message: received?(control),
      decodes_crlf_frames: events == [%{"n" => 1}, %{"n" => 2}, :eof],
      closes_source_resource: received?({:closed, ref}),
      events: inspect(events)
    }
  end

  defp tool_arguments do
    with_counter(fn counter ->
      tool = effect_tool(counter)

      tool = %{
        tool
        | parameters_json_schema: %{
            "type" => "object",
            "properties" => %{"count" => %{"type" => "integer"}},
            "required" => ["count"]
          }
      }

      agent =
        ExAgent.new(
          model: %Test{script: [calls(tool.name, %{"count" => "bad"}), "done"]},
          tools: [tool]
        )

      result = ExAgent.run(agent, "record")
      count = Agent.get(counter, & &1)
      %{invalid_arguments_blocked: count == 0, effects: count, result: outcome(result)}
    end)
  end

  defp permissions do
    with_counter(fn counter ->
      rejected =
        try do
          Permissions.new!(default: :approve)
          false
        rescue
          ArgumentError -> true
        end

      tool = effect_tool(counter)
      agent = ExAgent.new(model: %Test{script: [calls(tool.name), "done"]}, tools: [tool])
      result = ExAgent.run(agent, "record", permissions: %Permissions{default: :approve})
      count = Agent.get(counter, & &1)

      %{
        constructor_rejects_invalid_action: rejected,
        invalid_action_blocks_effect: count == 0,
        effects: count,
        result: outcome(result)
      }
    end)
  end

  defp delegation do
    with_counter(fn effects ->
      {:ok, requests} = Agent.start_link(fn -> 0 end)

      try do
        child_tool = effect_tool(effects)

        child =
          ExAgent.new(
            model: %Test{
              script: [
                count_request(requests, calls(child_tool.name)),
                count_request(requests, "child done")
              ]
            },
            tools: [child_tool]
          )

        parent =
          ExAgent.new(
            model: %Test{
              script: [
                count_request(requests, calls("delegate", %{"prompt" => "record"})),
                "parent done"
              ]
            },
            tools: [Coordination.delegation_tool(child)],
            usage_limits: %UsageLimits{request_limit: 1}
          )

        permissions = Permissions.new!(default: :deny, rules: [{"delegate", :allow}])
        result = ExAgent.run(parent, "record", permissions: permissions)
        count = Agent.get(requests, & &1)

        %{
          descendant_authority_restricted: Agent.get(effects, & &1) == 0,
          tree_within_parent_request_limit: count <= 1,
          requests_including_child: count,
          effects: Agent.get(effects, & &1),
          result: inspect(result, limit: 10)
        }
      after
        Agent.stop(requests)
      end
    end)
  end

  defp partial_failure do
    with_counter(fn counter ->
      {:ok, server} = Server.start_link(agent: failing_agent(counter))

      try do
        first = Server.chat(server, "record")
        second = Server.chat(server, "explicit caller retry")
        history = Server.history(server)
        usage = Server.usage(server)

        %{
          completed_effect_visible_in_history:
            Enum.any?(Message.parts(history), &match?(%Part.ToolReturn{}, &1)),
          consumed_usage_preserved: usage.input_tokens > 0,
          effects_after_two_explicit_attempts: Agent.get(counter, & &1),
          history_length: length(history),
          recorded_input_tokens: usage.input_tokens,
          results: [outcome(first), outcome(second)]
        }
      after
        GenServer.stop(server)
      end
    end)
  end

  defp checkpoint do
    {:ok, server} =
      Server.start_link(
        agent: ExAgent.new(model: %Test{}),
        store: {__MODULE__.FailingStore, self()}
      )

    try do
      {result, log} =
        ExUnit.CaptureLog.with_log(fn ->
          result = Server.chat(server, "hello")
          Server.health(server)
          result
        end)

      %{
        save_attempted: received?(:save_attempted),
        save_error_observable: log != "" or match?({:error, _}, result),
        log: log,
        caller_result: outcome(result)
      }
    after
      GenServer.stop(server)
    end
  end

  defp benchmarks do
    with_counter(fn counter ->
      for {name, agent, expected} <- [
            {"structured_read", structured_agent(), "ok"},
            {"effect_then_failure", failing_agent(counter), "error"}
          ],
          concurrency <- [1, 8] do
        Enum.each(1..20, fn _ -> ^expected = outcome(ExAgent.run(agent, "warmup")) end)
        start = System.monotonic_time(:microsecond)

        samples =
          Task.async_stream(
            1..200,
            fn _ ->
              started = System.monotonic_time(:microsecond)
              result = ExAgent.run(agent, "measure")
              ^expected = outcome(result)
              elapsed = System.monotonic_time(:microsecond) - started
              {:memory, bytes} = Process.info(self(), :memory)
              {:message_queue_len, queued} = Process.info(self(), :message_queue_len)
              {elapsed, bytes, queued}
            end,
            max_concurrency: concurrency,
            timeout: 10_000
          )
          |> Enum.map(fn {:ok, sample} -> sample end)

        total = System.monotonic_time(:microsecond) - start
        durations = samples |> Enum.map(&elem(&1, 0)) |> Enum.sort()

        %{
          scenario: name,
          concurrency: concurrency,
          iterations: length(samples),
          p50_us: Enum.at(durations, 99),
          p95_us: Enum.at(durations, 189),
          wall_us: total,
          runs_per_second: Float.round(length(samples) * 1_000_000 / max(total, 1), 1),
          max_worker_memory_after_bytes: samples |> Enum.map(&elem(&1, 1)) |> Enum.max(),
          max_worker_mailbox_after: samples |> Enum.map(&elem(&1, 2)) |> Enum.max()
        }
      end
    end)
  end

  defp structured_agent do
    lookup = Tool.new(name: "lookup", takes_ctx: false, call: fn _ -> {:ok, "record found"} end)

    ExAgent.new(
      model: %Test{
        script: [
          calls("lookup"),
          calls("final_result", %{
            "category" => "other",
            "priority" => 1,
            "summary" => "record found"
          })
        ]
      },
      tools: [lookup],
      output: ExAgent.Test.Ticket,
      max_steps: 3
    )
  end

  defp failing_agent(counter) do
    tool = effect_tool(counter)

    ExAgent.new(
      model: %Test{
        script: [calls(tool.name), fn _, _ -> raise "simulated downstream failure" end]
      },
      tools: [tool]
    )
  end

  defp effect_tool(counter) do
    Tool.new(
      name: "record_effect",
      takes_ctx: false,
      call: fn _ ->
        Agent.update(counter, &(&1 + 1))
        {:ok, "recorded"}
      end
    )
  end

  defp calls(name, args \\ %{}),
    do: {:tool_calls, [%Part.ToolCall{tool_name: name, tool_call_id: "#{name}-1", args: args}]}

  defp outcome({:ok, _}), do: "ok"
  defp outcome({:error, _}), do: "error"

  defp count_request(counter, item) do
    fn _, _ ->
      Agent.update(counter, &(&1 + 1))
      item
    end
  end

  defp with_counter(fun) do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    try do
      fun.(counter)
    after
      Agent.stop(counter)
    end
  end

  defp received?(message) do
    receive do
      ^message -> true
    after
      0 -> false
    end
  end
end

ExAgent.ConsolidationProbe.run()
