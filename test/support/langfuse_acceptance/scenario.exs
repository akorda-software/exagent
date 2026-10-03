defmodule LangfuseAcceptance.Scenario do
  @moduledoc "Public deterministic A10 scenes; requiring this file performs no IO."
  import ExUnit.Assertions
  alias ExAgent.{Permissions, Server, Store, Tool}
  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Observability.OpenTelemetry

  @sentinels ~w(LF015_PRIVATE_PROMPT LF015_PRIVATE_ARGUMENT LF015_PRIVATE_OUTPUT LF015_PRIVATE_ERROR LF015_PRIVATE_ACTOR LF015_PRIVATE_AUTHORIZATION LF015_PRIVATE_MODEL)
  def sentinels, do: @sentinels

  defmodule FailingOnceStore do
    def load_agent_snapshot(_, _), do: {:error, :not_found}

    def save_agent_snapshot(state, snapshot) do
      Agent.get_and_update(state, fn %{saves: saves} = current ->
        result = if saves == 0, do: {:error, "LF015_PRIVATE_ERROR"}, else: :ok
        {result, %{current | saves: saves + 1, snapshots: [snapshot | current.snapshots]}}
      end)
    end
  end

  def execute(tracing, context, group) do
    flow =
      if group in ~w(all flow) do
        result = ExAgent.Examples.FlowPipeline.execute(tracing, context)
        assert result.request_count == 7 and result.tool_calls == 3 and result.effects_count == 2

        %{
          scenes: ~w(router parallel delegation),
          request_count: 7,
          tool_calls: 3,
          effects: 2,
          run_ids: result.run_ids,
          roots: [result.router.run_id, result.parallel.run_id]
        }
      end

    recovery =
      if group in ~w(all recovery) do
        corrective = corrective(tracing, context)
        approval = approval(tracing, context)

        %{
          scenes: ~w(corrective_retry checkpoint_failure_retry pause_approve_resume),
          request_count: corrective.request_count + approval.request_count,
          tool_calls: corrective.tool_calls + approval.tool_calls,
          effects: corrective.effects + approval.effects,
          run_ids: [corrective.run_id, approval.run_id],
          corrective: corrective,
          approval: approval
        }
      end

    selected = Enum.reject([flow, recovery], &is_nil/1)

    %{
      scenes: Enum.flat_map(selected, & &1.scenes),
      request_count: Enum.sum(Enum.map(selected, & &1.request_count)),
      tool_calls: Enum.sum(Enum.map(selected, & &1.tool_calls)),
      effects: Enum.sum(Enum.map(selected, & &1.effects)),
      run_ids: Enum.flat_map(selected, & &1.run_ids),
      parts: selected
    }
  end

  defp corrective(tracing, context) do
    counts = :atomics.new(4, [])

    tool =
      Tool.new(
        name: "corrective_effect",
        takes_ctx: false,
        parameters_json_schema: schema(),
        call: fn %{"value" => "LF015_PRIVATE_ARGUMENT"} ->
          if :atomics.add_get(counts, 2, 1) == 1,
            do: raise(ExAgent.ModelRetry, "LF015_PRIVATE_ERROR")

          :atomics.add(counts, 3, 1)
          "LF015_PRIVATE_OUTPUT"
        end
      )

    agent =
      ExAgent.new(
        observability: tracing,
        tools: [tool],
        model:
          model(counts, [
            fn _, _ -> response([call("corrective_effect", "first")], 3, 1) end,
            fn messages, _ ->
              assert Enum.any?(
                       parts(messages),
                       &match?(
                         %Part.ToolReturn{tool_call_id: "first", status: :validation_error},
                         &1
                       )
                     )

              response([call("corrective_effect", "corrected")], 2, 1)
            end,
            fn _, _ -> response([%Part.Text{content: "LF015_PRIVATE_OUTPUT"}], 4, 2) end
          ])
      )

    {:ok, store} = Agent.start_link(fn -> %{saves: 0, snapshots: []} end)
    {:ok, server} = Server.start_link(agent: agent, store: {FailingOnceStore, store})

    try do
      assert {:error, %ExAgent.CheckpointError{result: {:ok, result}}} =
               OpenTelemetry.with_context(context, fn ->
                 Server.chat(server, "LF015_PRIVATE_PROMPT",
                   estimate_cost: fn usage ->
                     :atomics.add(counts, 4, 1)
                     (usage.input_tokens + usage.output_tokens) / 100
                   end
                 )
               end)

      assert :atomics.get(counts, 1) == 3 and :atomics.get(counts, 2) == 2 and
               :atomics.get(counts, 3) == 1

      before = :atomics.get(counts, 4)
      assert :ok = OpenTelemetry.with_context(context, fn -> Server.checkpoint(server) end)
      %{saves: 2, snapshots: [second, first]} = Agent.get(store, & &1)
      assert Map.delete(first, :saved_at) == Map.delete(second, :saved_at)

      assert :atomics.get(counts, 1) == 3 and :atomics.get(counts, 3) == 1 and
               :atomics.get(counts, 4) == before

      assert result.request_count == 3 and result.tool_calls == 2

      %{
        run_id: result.run_id,
        request_count: 3,
        tool_calls: 2,
        effects: 1,
        corrections: 2,
        saves: 2,
        estimate_calls: before,
        estimated_cost_cents: result.cost_cents,
        billing_receipt: false
      }
    after
      GenServer.stop(server, :normal, 1_000)
      Agent.stop(store)
    end
  end

  defp approval(tracing, context) do
    {:ok, owner} = Store.ETS.start_link(table: :langfuse_acceptance_approval)
    store = Store.scoped({Store.ETS, :langfuse_acceptance_approval}, "a10-approval")
    counts = :atomics.new(4, [])

    make = fn ->
      tool =
        Tool.new(
          name: "approved_effect",
          takes_ctx: false,
          parameters_json_schema: schema(),
          call: fn _ ->
            :atomics.add(counts, 3, 1)
            "LF015_PRIVATE_OUTPUT"
          end
        )

      ExAgent.new(
        observability: tracing,
        tools: [tool],
        model:
          model(counts, [
            fn _, _ -> response([call("approved_effect", "approval-call")], 2, 1) end,
            fn _, _ -> response([%Part.Text{content: "LF015_PRIVATE_OUTPUT"}], 3, 1) end
          ])
      )
    end

    options = [
      trace_context: context,
      permissions: Permissions.new!(default: :ask),
      continuation: %{
        store: store,
        id: "approval",
        durability: :ephemeral,
        expires_at: nil,
        lease_ms: 30_000,
        active_time_limit_ms: 10_000,
        definition: ref("approval"),
        policy: ref("policy"),
        model_ref: ref("test-model"),
        model_codec: %{
          dump: fn m -> {:ok, %{"index" => m.index}} end,
          load: fn m, %{"index" => i} -> {:ok, %{m | index: i}} end
        }
      }
    ]

    try do
      assert {:ok, paused} = ExAgent.run(make.(), "LF015_PRIVATE_PROMPT", options)
      assert paused.status == :paused and :atomics.get(counts, 3) == 0
      {:ok, %{record: record}} = ExAgent.Continuation.get(store, "approval")
      [{approval_id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

      {:ok, %{record: approved}} =
        ExAgent.Continuation.decide(store, "approval", :approve,
          record_id: record["record_id"],
          revision: record["revision"],
          operation_id: "approve",
          approval_id: approval_id,
          payload_hash: approval["payload_hash"],
          actor: "LF015_PRIVATE_ACTOR",
          authorize: fn "LF015_PRIVATE_ACTOR", :approve, _ ->
            {:ok, "LF015_PRIVATE_AUTHORIZATION"}
          end
        )

      reference = %{paused.continuation | revision: approved["revision"]}
      assert {:ok, resumed} = ExAgent.resume(make.(), reference, options)
      assert resumed.run_id == paused.run_id and resumed.attempt_id != paused.attempt_id

      assert resumed.status == :succeeded and resumed.request_count == 2 and
               resumed.tool_calls == 1

      assert :atomics.get(counts, 1) == 2 and :atomics.get(counts, 3) == 1

      %{
        run_id: resumed.run_id,
        request_count: 2,
        tool_calls: 1,
        effects: 1,
        paused_attempt: paused.attempt_id,
        resumed_attempt: resumed.attempt_id,
        record_id: record["record_id"],
        storage: "owned_ephemeral_ETS",
        restart_between_host_vms: false
      }
    after
      GenServer.stop(owner, :normal, 1_000)
    end
  end

  defp model(counts, functions) do
    %ExAgent.Models.Test{
      label: "LF015_PRIVATE_MODEL",
      script:
        Enum.map(functions, fn function ->
          fn messages, params ->
            :atomics.add(counts, 1, 1)
            function.(messages, params)
          end
        end)
    }
  end

  defp schema, do: %{"type" => "object", "properties" => %{"value" => %{"type" => "string"}}}
  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp call(name, id),
    do: %Part.ToolCall{
      tool_name: name,
      tool_call_id: id,
      args: %{"value" => "LF015_PRIVATE_ARGUMENT"}
    }

  defp response(parts, input, output),
    do: %Response{parts: parts, usage: %Usage{input_tokens: input, output_tokens: output}}

  defp parts(messages), do: Enum.flat_map(messages, & &1.parts)
end
