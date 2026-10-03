defmodule ExAgent.FlowApprovalDrainTest do
  use ExUnit.Case, async: false

  alias ExAgent.Coordination.Flow
  alias ExAgent.Continuation.{Record, Transition}
  alias ExAgent.{Continuation, Permissions, Store, Tool}
  alias ExAgent.Message.Part.ToolCall

  defmodule FatalAfter do
    use ExAgent.Capability
    defstruct []
    def after_tool_execute(_, _, _, _), do: raise("confirmed A wrapper failure")
  end

  defmodule Journal do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, namespace, query), do: Store.ETS.scan_records(c.table, namespace, query)

    def transition(c, key, revision, command) do
      current =
        case load_record(c, key) do
          {:ok, record} -> record
          _ -> nil
        end

      frame = current && current["execution"]["progress"]["runtime"]
      payload = command["payload"]

      target =
        is_map(frame) and frame["frontier"]["epoch"] == 2 and
          frame["frontier"]["reason"] == "approval" and payload["call_id"] == "b1"

      mode =
        Agent.get_and_update(c.control, fn state ->
          state =
            if target and command["operation"] == "call_prepared",
              do: Map.put(state, :capture, {current, key, revision, command}),
              else: state

          if target and command["operation"] == state[:operation] and state[:used] != true,
            do: {state[:mode], Map.put(state, :used, true)},
            else: {nil, state}
        end)

      result =
        if mode == :before,
          do: {:error, :before_commit},
          else: Store.ETS.transition(c.table, key, revision, command)

      if mode == :after and match?({:ok, _}, result), do: {:error, :lost_ack}, else: result
    end
  end

  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp codec do
    %{
      dump: fn m -> {:ok, %{"index" => m.index}} end,
      load: fn m, d -> {:ok, %{m | index: d["index"]}} end
    }
  end

  defp call(name, id, args \\ %{}),
    do: %ToolCall{tool_name: name, tool_call_id: id, args: args}

  defp tool(owner, name) do
    Tool.new(
      name: name,
      takes_ctx: false,
      parameters_json_schema: %{"type" => "object"},
      call: fn _ ->
        send(owner, {:effect, name, self()})
        {:ok, "#{name} confirmed"}
      end
    )
  end

  defp branch(id, script, tools) do
    %{
      id: id,
      agent: ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: tools),
      definition: ref(id),
      policy: ref("policy"),
      model_ref: ref("model"),
      output_ref: ref("output"),
      model_codec: codec()
    }
  end

  defp definition(owner, opts \\ []) do
    initial = fn name, tool_call ->
      fn _, _ ->
        send(owner, {:initial_model, name, self()})

        receive do
          :release -> {:tool_calls, [tool_call]}
        after
          5000 -> raise("initial Model barrier expired")
        end
      end
    end

    a =
      branch(
        "A",
        [initial.("A", call("a1", "a1")), {:tool_calls, [call("a2", "a2")]}, "A done"],
        [tool(owner, "a1"), tool(owner, "a2")]
      )

    a = if opts[:fatal], do: %{a | agent: %{a.agent | capabilities: [%FatalAfter{}]}}, else: a
    b_tool = opts[:b_tool] || tool(owner, "b1")
    b_call = call(b_tool.name, "b1", opts[:b_args] || %{})
    b = branch("B", [initial.("B", b_call), "B done"], [b_tool])

    {:ok, flow} =
      Flow.new(
        id: "approval-drain",
        version: "1",
        kind: :parallel,
        failure_policy: if(opts[:fatal], do: :fail_fast, else: :collect),
        max_concurrency: 2,
        branches: [a, b]
      )

    flow
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

  defp stored(c) do
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
    record
  end

  defp approve_all(c, record) do
    Enum.reduce(record["execution"]["progress"]["approvals"], record, fn {id, approval},
                                                                         current ->
      if is_nil(approval["decision"]) do
        {:ok, %{record: next}} =
          Continuation.decide(c.store, "flow", :approve,
            record_id: current["record_id"],
            revision: current["revision"],
            operation_id: "approve-#{current["revision"]}",
            actor: "human",
            authorize: fn actor, _, _ -> {:ok, actor} end,
            approval_id: id,
            payload_hash: approval["payload_hash"]
          )

        next
      else
        current
      end
    end)
  end

  defp options(c),
    do: [
      continuation: c.config,
      step_options: %{"A" => [permissions: c.permissions], "B" => [permissions: c.permissions]}
    ]

  defp first_round(c, flow, opts) do
    task = Task.async(fn -> Flow.run(flow, "input", opts) end)
    assert_receive {:initial_model, "A", a}, 5000
    assert_receive {:initial_model, "B", b}, 5000
    send(a, :release)
    send(b, :release)
    assert {:ok, %{status: :paused, request_count: 2, tool_calls: 2}} = Task.await(task, 15_000)
    refute Process.alive?(a)
    refute Process.alive?(b)
    refute_receive {:effect, _, _}
    record = stored(c)
    assert map_size(record["execution"]["progress"]["approvals"]) == 2
    approve_all(c, record)
  end

  defp gated_resume(c, flow, ready, opts, event \\ :paused) do
    owner = self()
    gate = start_supervised!({Agent, fn -> true end}, id: :resume_gate)
    a_progress = fn result -> if result.status == event, do: send(owner, :a_drained) end

    b_progress = fn _ ->
      if Agent.get_and_update(gate, fn once -> {once, false} end) do
        send(owner, {:b_waiting, self()})

        receive do
          :release -> :ok
        after
          5000 -> raise("resume progress barrier expired")
        end
      end
    end

    step_options =
      opts[:step_options]
      |> Map.update!("A", &Keyword.put(&1, :on_progress, a_progress))
      |> Map.update!("B", &Keyword.put(&1, :on_progress, b_progress))

    task =
      Task.async(fn ->
        Flow.resume(flow, reference(ready), Keyword.put(opts, :step_options, step_options))
      end)

    assert_receive {:b_waiting, pid}, 5000
    assert_receive :a_drained, 5000
    assert_receive {:effect, "a1", effect_pid}
    refute Process.alive?(effect_pid)
    middle = stored(c)
    assert middle["execution"]["lease_until"] > System.system_time(:millisecond)
    assert middle["execution"]["progress"]["runtime"]["frontier"]["state"] == "draining"
    {task, pid, middle}
  end

  defp recover(c, stopped) do
    receive do
    after
      max(stopped["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0) -> :ok
    end

    {:ok, %{record: ready}} =
      Continuation.recover(c.store, "flow",
        record_id: stopped["record_id"],
        revision: stopped["revision"],
        operation_id: "recover-#{stopped["revision"]}",
        actor: "host",
        authorize: fn actor, _, _ -> {:ok, actor} end
      )

    ready
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    control = start_supervised!({Agent, fn -> %{} end}, id: :journal_control)
    store = Store.scoped({Journal, %{table: __MODULE__, control: control}}, "flow-approval-drain")

    %{
      store: store,
      control: control,
      permissions: Permissions.new!(default: :ask),
      config: %{
        store: store,
        id: "flow",
        policy: ref("policy"),
        durability: :ephemeral,
        expires_at: nil,
        lease_ms: 30_000
      }
    }
  end

  test "an approved branch drains its older ask after a sibling opens a new ask", c do
    flow = definition(self())
    opts = options(c)
    ready = first_round(c, flow, opts)
    {task, b, _} = gated_resume(c, flow, ready, opts)
    send(b, :release)
    assert {:ok, second} = Task.await(task, 15_000)
    assert second.status == :paused and second.request_count == 4 and second.tool_calls == 3
    refute Process.alive?(b)
    assert_receive {:effect, "b1", effect_pid}
    refute Process.alive?(effect_pid)
    refute_receive {:effect, _, _}
    pending = stored(c)
    approvals = pending["execution"]["progress"]["approvals"]
    assert map_size(approvals) == 3

    assert Map.take(approvals, Map.keys(ready["execution"]["progress"]["approvals"])) ===
             ready["execution"]["progress"]["approvals"]

    assert {:error, %ExAgent.RunError{reason: :continuation_conflict}} =
             Flow.resume(flow, reference(pending), opts)

    assert stored(c) === pending
    refute_receive {:effect, _, _}
    ready = approve_all(c, pending)
    assert {:ok, result} = Flow.resume(flow, reference(ready), opts)
    assert result.status == :completed and result.request_count == 5 and result.tool_calls == 3
    assert_receive {:effect, "a2", pid}
    refute Process.alive?(pid)
    refute_receive {:effect, _, _}
    assert stored(c)["execution"]["state"] == "completed"
  end

  test "current deny overrides an older approval while another branch awaits a new decision", c do
    flow = definition(self())
    opts = options(c)
    ready = first_round(c, flow, opts)

    deny_opts =
      Keyword.put(opts, :step_options, %{
        "A" => [permissions: c.permissions],
        "B" => [permissions: Permissions.new!(default: :deny)]
      })

    {task, b, _} = gated_resume(c, flow, ready, deny_opts)
    send(b, :release)
    assert {:ok, %{status: :paused}} = Task.await(task, 15_000)
    refute_receive {:effect, "b1", _}
    pending = stored(c)
    frame = pending["execution"]["progress"]["runtime"]

    [{_, batch}] =
      Enum.filter(frame["tool_batches"], fn {_, batch} -> Map.has_key?(batch["calls"], "b1") end)

    assert batch["calls"]["b1"]["source"] == %{"kind" => "host", "reason" => "permission_denied"}
    ready = approve_all(c, pending)
    assert {:ok, %{status: :completed}} = Flow.resume(flow, reference(ready), deny_opts)
    assert_receive {:effect, "a2", _}
    refute_receive {:effect, _, _}
    stored(c)
  end

  test "exact args, epoch, attempt, fence, suspended nodes and paused records still reject preparation",
       c do
    flow = definition(self())
    opts = options(c)
    ready = first_round(c, flow, opts)
    {task, b, _} = gated_resume(c, flow, ready, opts)
    send(b, :release)
    assert {:ok, %{status: :paused}} = Task.await(task, 15_000)
    {current, key, revision, command} = Agent.get(c.control, & &1.capture)
    now = current["updated_at"]
    assert :ok = Record.validate(current, key)
    assert {:ok, %{replayed: false}} = Transition.apply(current, key, revision, command, now)

    for {field, value} <- [
          {"args", %{"changed" => true}},
          {"epoch", 999},
          {"attempt_id", "old-attempt"},
          {"fence", 999},
          {"request_id", "other-request"}
        ] do
      changed = put_in(command, ["payload", field], value)
      assert {:error, _} = Transition.apply(current, key, revision, changed, now)
    end

    frame = current["execution"]["progress"]["runtime"]
    {a_id, a} = Enum.find(frame["children"], fn {_, node} -> node["link"]["step_id"] == "A" end)
    assert a["status"] == "suspended"

    suspended =
      command
      |> put_in(["payload", "run_id"], a_id)
      |> put_in(["payload", "request_id"], a["frame"]["model_request_id"])
      |> put_in(["payload", "call_id"], "a2")

    assert {:error, :invalid_frame10_transition} =
             Transition.apply(current, key, revision, suspended, now)

    pending = stored(c)

    assert {:error, :operation_conflict} =
             Transition.apply(pending, key, pending["revision"], command, pending["updated_at"])

    paused_command = Map.put(command, "operation_id", "paused-unauthorized")

    assert {:error, :stale_owner} =
             Transition.apply(
               pending,
               key,
               pending["revision"],
               paused_command,
               pending["updated_at"]
             )

    assert_receive {:effect, "b1", _}
    refute_receive {:effect, _, _}
    ready = approve_all(c, pending)
    assert {:ok, %{status: :completed}} = Flow.resume(flow, reference(ready), opts)
    assert_receive {:effect, "a2", _}
    refute_receive {:effect, _, _}
    closed = stored(c)
    closed_command = Map.put(command, "operation_id", "closed-unauthorized")

    assert {:error, :stale_owner} =
             Transition.apply(
               closed,
               key,
               closed["revision"],
               closed_command,
               closed["updated_at"]
             )
  end

  test "a confirmed fatal drain never admits an older approved sibling", c do
    flow = definition(self(), fatal: true)
    opts = options(c)
    ready = first_round(c, flow, opts)
    {task, b, middle} = gated_resume(c, flow, ready, opts, :failed)
    assert middle["execution"]["progress"]["runtime"]["frontier"]["reason"] == "fatal"
    send(b, :release)
    assert {:error, %ExAgent.RunError{partial: partial}} = Task.await(task, 15_000)
    assert partial.status == :failed
    refute Process.alive?(b)
    refute_receive {:effect, _, _}
    closed = stored(c)
    assert closed["execution"]["state"] == "failed"
    assert Enum.all?(closed["execution"]["effects"], fn {_, e} -> e["state"] == "confirmed" end)
  end

  for {operation, mode} <- [
        {"call_prepared", :before},
        {"call_prepared", :after},
        {"begin_effect", :after}
      ] do
    @tag operation: operation, fault_mode: mode
    test "#{operation} #{mode}: exact checkpoint replay performs no IO and explicit recovery preserves effect authority",
         c do
      flow = definition(self())

      opts =
        if c.operation == "begin_effect",
          do: options(%{c | config: Map.put(c.config, :active_time_limit_ms, 50_000)}),
          else: options(c)

      ready = first_round(c, flow, opts)
      Agent.update(c.control, &Map.merge(&1, %{operation: c.operation, mode: c.fault_mode}))

      resume_opts =
        Keyword.put(opts, :continuation, Map.put(opts[:continuation], :lease_ms, 10_000))

      {task, b, _} = gated_resume(c, flow, ready, resume_opts)
      send(b, :release)
      assert {:error, %ExAgent.RunError{partial: partial}} = Task.await(task, 15_000)
      refute Process.alive?(b)
      assert partial.continuation_checkpoint != nil
      stopped = stored(c)
      assert stopped["execution"]["state"] == "claimed"
      refute_receive {:effect, _, _}
      assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
      replayed = stored(c)
      refute_receive {:effect, _, _}

      if c.operation == "begin_effect" do
        assert Record.unresolved?(replayed["execution"])
        recovered = recover(c, replayed)
        assert recovered["execution"]["state"] == "uncertain"
        assert recovered["execution"]["effects"] === replayed["execution"]["effects"]
        budget = recovered["execution"]["progress"]["active_budget"]
        assert budget["limit_ms"] == 50_000 and budget["remaining_ms"] == 0
        assert budget["reserved_ms"] == nil and budget["refund_at"] == nil

        assert {:error, %ExAgent.RunError{reason: :continuation_conflict}} =
                 Flow.resume(flow, reference(recovered), opts)

        assert stored(c) === recovered
        refute_receive {:effect, _, _}
      else
        refute Record.unresolved?(replayed["execution"])
        recovered = recover(c, replayed)
        assert recovered["execution"]["state"] == "ready"
        assert recovered["execution"]["effects"] === replayed["execution"]["effects"]

        assert {:ok, %{status: :paused, request_count: 4, tool_calls: 3}} =
                 Flow.resume(flow, reference(recovered), opts)

        assert_receive {:effect, "b1", pid}
        refute Process.alive?(pid)
        refute_receive {:effect, _, _}
        pending = stored(c)
        ready = approve_all(c, pending)

        assert {:ok, %{status: :completed, request_count: 5, tool_calls: 3}} =
                 Flow.resume(flow, reference(ready), opts)

        assert_receive {:effect, "a2", _}
        refute_receive {:effect, _, _}
        closed = stored(c)

        assert Map.take(closed["execution"]["effects"], Map.keys(stopped["execution"]["effects"])) ===
                 stopped["execution"]["effects"]
      end
    end
  end

  test "an approved delegate can attach and pause its own ask during the newer sibling drain",
       c do
    owner = self()

    delegate =
      ExAgent.Coordination.delegation_tool(fn _, _ -> flunk("durable builder replay") end,
        name: "delegate",
        prompt_arg: "task",
        continuation: %{
          definition: ref("D"),
          policy: ref("policy"),
          model_ref: ref("model"),
          model_codec: codec()
        }
      )

    child =
      ExAgent.new(
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls, [call("d1", "d1")]},
            "D done"
          ]
        },
        tools: [tool(owner, "d1")]
      )

    catalog = [
      %{
        definition: ref("D"),
        policy: ref("policy"),
        model_ref: ref("model"),
        load: fn _, _ ->
          {:ok, child, [permissions: Permissions.new!(default: :ask)], %{model_codec: codec()}}
        end
      }
    ]

    flow = definition(owner, b_tool: delegate, b_args: %{"task" => "D input"})
    opts = Keyword.put(options(c), :delegate_definitions, catalog)
    ready = first_round(c, flow, opts)
    {task, b, _} = gated_resume(c, flow, ready, opts)
    send(b, :release)
    assert {:ok, %{status: :paused, request_count: 4, tool_calls: 4}} = Task.await(task, 15_000)
    refute Process.alive?(b)
    refute_receive {:effect, _, _}
    pending = stored(c)
    assert map_size(pending["execution"]["progress"]["approvals"]) == 4
    ready = approve_all(c, pending)

    assert {:ok, %{status: :completed, request_count: 7, tool_calls: 4}} =
             Flow.resume(flow, reference(ready), opts)

    assert_receive {:effect, "a2", pid_a}
    assert_receive {:effect, "d1", pid_d}
    refute Process.alive?(pid_a)
    refute Process.alive?(pid_d)
    refute_receive {:effect, _, _}
    stored(c)
  end
end
