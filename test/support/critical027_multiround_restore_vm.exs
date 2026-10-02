defmodule ExAgent.Critical027MultiroundRestoreVM do
  alias ExAgent.Coordination.Flow
  alias ExAgent.Continuation.Record
  alias ExAgent.{Continuation, Permissions, Store, Tool}

  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp branch(id, script, tools) do
    %{
      id: id,
      agent: ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: tools),
      definition: ref(id),
      policy: ref("policy"),
      model_ref: ref("model"),
      output_ref: ref("output"),
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, d -> {:ok, %{m | index: d["index"]}} end
      }
    }
  end

  defp tool(name) do
    owner = self()

    Tool.new(
      name: name,
      takes_ctx: false,
      parameters_json_schema: %{"type" => "object"},
      call: fn _ ->
        send(owner, {:effect, name})
        {:ok, "#{name} confirmed"}
      end
    )
  end

  defp reference(record) do
    %{
      version: 1,
      id: "flow",
      record_id: record["record_id"],
      revision: record["revision"],
      run_id: record["execution"]["run_id"]
    }
  end

  defp check(true), do: :ok
  defp check(_), do: raise("fresh VM continuation invariant failed")

  defp effect(name) do
    receive do
      {:effect, ^name} -> :ok
    after
      1000 -> raise("missing admitted fresh VM effect #{name}")
    end
  end

  def execute([input, output]) do
    Application.put_env(:req_llm, :load_dotenv, false)
    {:ok, _} = Application.ensure_all_started(:exagent)
    {:ok, owner} = Store.ETS.start_link(table: __MODULE__)
    store = Store.scoped({Store.ETS, __MODULE__}, "critical027-c7")
    key = {store.namespace, :agent, "flow"}
    record = input |> File.read!() |> Jason.decode!()
    :ok = Record.validate(record, key)
    check(record["execution"]["state"] == "ready")
    check(record["execution"]["progress"]["runtime"]["frontier"]["reason"] == "approval")
    {:ok, physical} = Record.key(key)
    true = :ets.insert(__MODULE__, {physical, Jason.encode!(record)})

    owner_pid = self()
    old_model = fn _, _ -> raise("already-confirmed Model was replayed") end

    final = fn id ->
      fn _, _ ->
        send(owner_pid, {:model, id})
        "#{id} done"
      end
    end

    a = branch("A", [old_model, old_model, final.("A")], [tool("a1"), tool("a2")])
    b = branch("B", [old_model, final.("B")], [tool("b1")])

    {:ok, flow} =
      Flow.new(
        id: "two-round-parallel",
        version: "1",
        kind: :parallel,
        failure_policy: :collect,
        max_concurrency: 2,
        branches: [a, b]
      )

    config = %{
      store: store,
      id: "flow",
      policy: ref("policy"),
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 30_000
    }

    permissions = Permissions.new!(default: :ask)

    opts = [
      continuation: config,
      step_options: %{"A" => [permissions: permissions], "B" => [permissions: permissions]}
    ]

    {:ok, paused} = Flow.resume(flow, reference(record), opts)
    check(paused.status == :paused)
    check(paused.request_count == 4 and paused.tool_calls == 3)
    effect("b1")

    receive do
      {:model, "B"} -> :ok
    after
      1000 -> raise("missing new B Model")
    end

    {:ok, pending} = Store.load_record(store, :agent, "flow")

    check(
      Map.take(pending["execution"]["effects"], Map.keys(record["execution"]["effects"])) ===
        record["execution"]["effects"]
    )

    approvals = pending["execution"]["progress"]["approvals"]
    check(map_size(approvals) == 3)
    [{id, approval}] = Enum.filter(approvals, fn {_, a} -> is_nil(a["decision"]) end)

    {:ok, %{record: ready}} =
      Continuation.decide(store, "flow", :approve,
        record_id: pending["record_id"],
        revision: pending["revision"],
        operation_id: "fresh-approve-#{pending["revision"]}",
        actor: "human",
        authorize: fn actor, _, _ -> {:ok, actor} end,
        approval_id: id,
        payload_hash: approval["payload_hash"]
      )

    {:ok, completed} = Flow.resume(flow, reference(ready), opts)
    check(completed.status == :completed)
    check(completed.request_count == 5 and completed.tool_calls == 3)
    effect("a2")

    receive do
      {:model, "A"} -> :ok
    after
      1000 -> raise("missing new A Model")
    end

    receive do
      {:effect, _} -> raise("repeated effect")
      {:model, _} -> raise("repeated Model")
    after
      0 -> :ok
    end

    {:ok, closed} = Store.load_record(store, :agent, "flow")
    :ok = Record.validate(closed, key)
    check(closed["execution"]["state"] == "completed")

    check(
      Map.take(closed["execution"]["effects"], Map.keys(record["execution"]["effects"])) ===
        record["execution"]["effects"]
    )

    GenServer.stop(owner)

    File.write!(
      output,
      Jason.encode!(%{
        passed: true,
        status: completed.status,
        request_count: completed.request_count,
        tool_calls: completed.tool_calls,
        effects_this_vm: 2,
        past_effects_preserved: true,
        replayed_past_models: 0,
        cleanup: not Process.alive?(owner),
        input_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(input)), case: :lower)
      })
    )
  end
end

ExAgent.Critical027MultiroundRestoreVM.execute(System.argv())
