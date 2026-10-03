# Public, offline A10 plugin. Requiring this file defines execute/2 without IO.
#   EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/flow_pipeline.exs --self-test
defmodule ExAgent.Examples.FlowPipeline do
  alias ExAgent.{Coordination, Store, Tool}
  alias ExAgent.Coordination.Flow
  alias ExAgent.Message.Part.ToolCall

  def execute(tracing, context) do
    {:ok, snapshots} = Store.ETS.start_link(table: __MODULE__.Snapshots)
    {:ok, counts} = Agent.start_link(fn -> %{requests: 0, effects: 0} end)

    try do
      store = Store.scoped({Store.ETS, __MODULE__.Snapshots}, "flow-pipeline")
      route = branch("selected", agent(counts, ["selected"], []))

      unused =
        branch(
          "unused",
          ExAgent.new(
            model: %ExAgent.Models.Test{
              script: [
                fn _, _ ->
                  raise "unchosen branch executed"
                end
              ]
            }
          )
        )

      {:ok, router} =
        Flow.new(
          id: "router",
          version: "1",
          kind: :router,
          select: fn _ -> "selected" end,
          select_version: "1",
          branches: [unused, route]
        )

      router_config = config(store, "router")

      {:ok, routed} =
        Flow.run(router, "root",
          continuation: router_config,
          observability: tracing,
          trace_context: context
        )

      {:ok, same_route} =
        Flow.resume(router, routed.continuation,
          continuation: router_config,
          observability: tracing,
          trace_context: context
        )

      true = routed.output === same_route.output

      a = agent(counts, [{:tool_calls, [call("effect", "a")]}, "A"], [effect(counts)])
      child = agent(counts, [{:tool_calls, [call("effect", "d")]}, "D"], [effect(counts)])

      delegate =
        Coordination.delegation_tool(fn _, _ -> raise "durable builder executed" end,
          name: "delegate",
          prompt_arg: "task",
          continuation: %{
            definition: ref("D"),
            policy: ref("policy"),
            model_ref: ref("model"),
            model_codec: codec()
          }
        )

      b =
        agent(counts, [{:tool_calls, [call("delegate", "b", %{"task" => "D input"})]}, "B"], [
          delegate
        ])

      catalog = [
        %{
          definition: ref("D"),
          policy: ref("policy"),
          model_ref: ref("model"),
          load: fn _, _ -> {:ok, child, [], %{model_codec: codec()}} end
        }
      ]

      {:ok, parallel} =
        Flow.new(
          id: "parallel",
          version: "1",
          kind: :parallel,
          max_concurrency: 2,
          failure_policy: :collect,
          branches: [branch("A", a), branch("B", b)]
        )

      parallel_config = config(store, "parallel")

      {:ok, fanned} =
        Flow.run(parallel, "root",
          continuation: parallel_config,
          delegate_definitions: catalog,
          observability: tracing,
          trace_context: context
        )

      {:ok, same_fan} =
        Flow.resume(parallel, fanned.continuation,
          continuation: parallel_config,
          observability: tracing,
          trace_context: context
        )

      true = fanned.output === same_fan.output
      %{requests: 7, effects: 2} = exact = Agent.get(counts, & &1)
      7 = routed.request_count + fanned.request_count
      3 = routed.tool_calls + fanned.tool_calls
      {:ok, router_record} = Store.load_record(store, :agent, "router")
      {:ok, parallel_record} = Store.load_record(store, :agent, "parallel")

      %{
        router: routed,
        parallel: fanned,
        request_count: 7,
        tool_calls: 3,
        effects_count: 2,
        exact: exact,
        run_ids:
          [routed.run_id, fanned.run_id] ++
            Enum.flat_map([router_record, parallel_record], fn record ->
              Map.keys(record["execution"]["progress"]["runtime"]["children"])
            end),
        records: [router_record, parallel_record]
      }
    after
      Agent.stop(counts)
      GenServer.stop(snapshots)
    end
  end

  defp agent(counts, script, tools) do
    script =
      Enum.map(script, fn result ->
        fn _, _ ->
          Agent.update(counts, &Map.update!(&1, :requests, fn n -> n + 1 end))
          result
        end
      end)

    ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: tools)
  end

  defp effect(counts),
    do:
      Tool.new(
        name: "effect",
        takes_ctx: false,
        parameters_json_schema: %{"type" => "object"},
        call: fn _ ->
          Agent.update(counts, &Map.update!(&1, :effects, fn n -> n + 1 end))
          "raw"
        end
      )

  defp call(name, id, args \\ %{}), do: %ToolCall{tool_name: name, tool_call_id: id, args: args}
  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp codec,
    do: %{
      dump: fn m -> {:ok, %{"index" => m.index}} end,
      load: fn m, data -> {:ok, %{m | index: data["index"]}} end
    }

  defp branch(id, agent),
    do: %{
      id: id,
      agent: agent,
      definition: ref(id),
      policy: ref("policy"),
      model_ref: ref("model"),
      output_ref: ref("output"),
      model_codec: codec()
    }

  defp config(store, id),
    do: %{
      store: store,
      id: id,
      policy: ref("policy"),
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 30_000
    }
end

if "--self-test" in System.argv() do
  %{request_count: 7, tool_calls: 3, effects_count: 2} =
    ExAgent.Examples.FlowPipeline.execute(nil, nil)

  IO.puts("PASS Flow router and fan-out/delegation/fan-in: 7 requests, 3 attempts, 2 effects")
end
