# Deterministic job recipe, runnable without Oban, Phoenix, SQL or credentials:
#   EXAGENT_OFFLINE=1 mix run examples/continuation_job.exs
# The application's queue calls dispatch/4 with a trusted template/configuration.
Code.require_file("continuation_integrations/job_dispatch.ex", __DIR__)

defmodule ExAgent.Examples.ContinuationJob.Demo do
  import ExUnit.Assertions
  alias ExAgent.Examples.ContinuationJob
  alias ExAgent.{Continuation, Permissions, Store, Tool}
  alias ExAgent.Message.Part

  def run do
    {:ok, snapshots} = Store.ETS.start_link(table: __MODULE__.Snapshots)
    {:ok, counter} = Agent.start_link(fn -> %{requests: 0, effects: 0} end)

    try do
      store = Store.scoped({Store.ETS, __MODULE__.Snapshots}, "synthetic-job")
      config = config(store)
      options = [permissions: Permissions.new!(default: :ask)]
      template = fn -> agent(counter) end

      assert {:ok, %{status: :paused}} =
               ContinuationJob.dispatch(template.(), "synthetic", config, options)

      assert Agent.get(counter, & &1) == %{requests: 1, effects: 0}

      assert {:ok, %{job_action: :await_approval}} =
               ContinuationJob.dispatch(template.(), "queue retry", config, options)

      assert Agent.get(counter, & &1) == %{requests: 1, effects: 0}
      assert {:ok, %{record: record}} = Continuation.get(store, config.id)
      [{approval_id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

      decision = [
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "synthetic-approval",
        approval_id: approval_id,
        payload_hash: approval["payload_hash"],
        actor: :unauthorized,
        authorize: fn
          :authenticated_owner, :approve, _ -> {:ok, "synthetic-owner"}
          _, _, _ -> {:error, :unauthorized}
        end
      ]

      assert {:error, :unauthorized} = Continuation.decide(store, config.id, :approve, decision)
      assert Agent.get(counter, & &1) == %{requests: 1, effects: 0}

      assert {:ok, _} =
               Continuation.decide(
                 store,
                 config.id,
                 :approve,
                 Keyword.put(decision, :actor, :authenticated_owner)
               )

      assert {:ok, result} =
               ContinuationJob.dispatch(
                 template.(),
                 "queue retry after approval",
                 config,
                 options
               )

      assert result.status == :succeeded
      assert result.output == "done"
      assert result.request_count == 2 and result.tool_calls == 1
      assert Agent.get(counter, & &1) == %{requests: 2, effects: 1}

      assert {:ok, %{job_action: :terminal, status: :completed}} =
               ContinuationJob.dispatch(template.(), "duplicate completed job", config, options)

      assert Agent.get(counter, & &1) == %{requests: 2, effects: 1}

      IO.puts("PASS continuation job: approval authority, cursor and duplicate dispatch")
    after
      Agent.stop(counter)
      GenServer.stop(snapshots)
    end
  end

  defp agent(counter) do
    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        max_retries: 0,
        call: fn _, _ ->
          Agent.update(counter, &Map.update!(&1, :effects, fn count -> count + 1 end))
          {:ok, "saved"}
        end
      )

    script = [
      fn _, _ ->
        Agent.update(counter, &Map.update!(&1, :requests, fn count -> count + 1 end))

        %ExAgent.Message.Response{
          parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "one", args: %{}}]
        }
      end,
      fn _, _ ->
        Agent.update(counter, &Map.update!(&1, :requests, fn count -> count + 1 end))
        "done"
      end
    ]

    ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: [tool])
  end

  defp config(store),
    do: %{
      store: store,
      id: "job",
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 30_000,
      active_time_limit_ms: 20_000,
      definition: %{"id" => "job-template", "version" => "1"},
      policy: %{"id" => "job-policy", "version" => "1"},
      model_ref: %{"id" => "test", "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }
end

ExAgent.Examples.ContinuationJob.Demo.run()
