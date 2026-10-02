defmodule ExAgent.FlowAdmissionTest do
  use ExUnit.Case, async: false
  alias ExAgent.Coordination.Flow
  alias ExAgent.Continuation.Record
  alias ExAgent.{Continuation, Store}

  defmodule GateModel do
    @behaviour ExAgent.Model
    defstruct test: %ExAgent.Models.Test{}, index: 0, owner: nil, gate: nil
    def model_name(_), do: "gated-test"
    def system(_), do: "test"
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}

    def validate_resume(m, _, _, _) do
      if Agent.get_and_update(m.gate, fn hold -> {hold, false} end) do
        send(m.owner, {:before_attach, self()})

        receive do
          :release -> :ok
        end
      else
        :ok
      end
    end

    def request(m, messages, settings, params) do
      with {:ok, response, next} <-
             ExAgent.Models.Test.request(m.test, messages, settings, params),
           do: {:ok, response, %{m | test: next, index: next.index}}
    end
  end

  defmodule Journal do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, k), do: Store.ETS.load_record(c.table, k)
    def scan_records(c, ns, q), do: Store.ETS.scan_records(c.table, ns, q)

    def transition(c, k, revision, command) do
      operation = command["operation"]

      mode =
        Agent.get_and_update(c.control, fn
          {^operation, :barrier} -> {:barrier, {operation, :barrier}}
          {^operation, mode} -> {mode, nil}
          value -> {nil, value}
        end)

      result =
        if mode == :before,
          do: {:error, :before_commit},
          else: commit(c, k, revision, command, mode)

      if mode == :late do
        send(c.owner, {:late_ack, self()})

        receive do
          :release -> :ok
        end
      end

      if mode == :after, do: {:error, :lost_ack}, else: result
    end

    defp commit(c, k, revision, command, :barrier) do
      send(c.owner, {:claim_waiting, self()})

      receive do
        :commit -> Store.ETS.transition(c.table, k, revision, command)
      end
    end

    defp commit(c, k, revision, command, _),
      do: Store.ETS.transition(c.table, k, revision, command)
  end

  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp branch(owner),
    do: %{
      id: "A",
      agent:
        ExAgent.new(
          model: %ExAgent.Models.Test{
            script: [
              fn _, _ ->
                send(owner, :model)
                "A"
              end
            ]
          }
        ),
      definition: ref("A"),
      policy: ref("policy"),
      model_ref: ref("model"),
      output_ref: ref("output"),
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, d -> {:ok, %{m | index: d["index"]}} end
      }
    }

  defp definition(owner),
    do:
      elem(
        Flow.new(
          id: "admission",
          version: "1",
          kind: :router,
          select_version: "1",
          select: fn _ ->
            send(owner, :selected)
            "A"
          end,
          merge_version: "1",
          merge: fn outcomes ->
            send(owner, :merged)
            outcomes
          end,
          branches: [branch(owner)]
        ),
        1
      )

  defp reference(record),
    do: %{
      version: 1,
      id: "flow",
      record_id: record["record_id"],
      revision: record["revision"],
      run_id: record["execution"]["run_id"]
    }

  defp waiting_definition(owner) do
    tool =
      ExAgent.Tool.new(
        name: "ask",
        takes_ctx: true,
        parameters_json_schema: %{"type" => "object"},
        call: fn context, _ ->
          send(owner, {:effect, context.tool_call_id})
          "raw"
        end
      )

    calls =
      for id <- ~w(one two),
          do: %ExAgent.Message.Part.ToolCall{
            tool_name: "ask",
            tool_call_id: id,
            args: %{}
          }

    a =
      ExAgent.new(
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls, calls},
            fn _, _ ->
              send(owner, :after_approval_model)
              "A"
            end
          ]
        },
        tools: [tool]
      )

    b = %{
      branch(owner)
      | agent: a,
        model_codec: %{
          dump: fn m -> {:ok, %{"index" => m.index}} end,
          load: fn m, d ->
            send(owner, :codec_load)
            {:ok, %{m | index: d["index"]}}
          end
        }
    }

    {:ok, flow} =
      Flow.new(id: "wait", version: "1", kind: :parallel, failure_policy: :collect, branches: [b])

    flow
  end

  defp approve(store, record, id) do
    {:ok, %{record: next}} =
      Continuation.decide(store, "flow", :approve,
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "approve-#{record["revision"]}",
        actor: "human",
        authorize: fn actor, _, _ -> {:ok, actor} end,
        approval_id: id,
        payload_hash: record["execution"]["progress"]["approvals"][id]["payload_hash"]
      )

    next
  end

  defp wait_until(until) do
    receive do
    after
      max(until - System.system_time(:millisecond) + 1, 0) -> :ok
    end
  end

  defp recover(c, record) do
    wait_until(record["execution"]["lease_until"])

    {:ok, %{record: next}} =
      Continuation.recover(c.store, "flow",
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "recover-#{record["revision"]}",
        actor: "host",
        authorize: fn actor, _, _ -> {:ok, actor} end
      )

    next
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    control = start_supervised!({Agent, fn -> nil end})

    store =
      Store.scoped(
        {Journal, %{table: __MODULE__, control: control, owner: self()}},
        "flow-admission"
      )

    %{
      store: store,
      control: control,
      config: %{
        store: store,
        id: "flow",
        policy: ref("policy"),
        durability: :ephemeral,
        expires_at: nil,
        lease_ms: 1500
      }
    }
  end

  for operation <- ~w(flow_select_begin flow_select flow_merge_begin flow_merge),
      mode <- [:before, :after] do
    @tag operation: operation, mode: mode
    test "#{operation} #{mode}: exact ACK retry is data only and retains admitted host phase",
         c do
      d = definition(self())
      Agent.update(c.control, fn _ -> {c.operation, c.mode} end)

      assert {:error, %ExAgent.RunError{partial: partial}} =
               Flow.run(d, "root", continuation: c.config)

      token = partial.continuation_checkpoint
      assert token["command"]["operation"] == c.operation

      if c.operation == "flow_select_begin",
        do: refute_receive(:selected),
        else: assert_receive(:selected)

      if c.operation in ~w(flow_merge flow_merge_begin),
        do: assert_receive(:model),
        else: refute_receive(:model)

      if c.operation == "flow_merge", do: assert_receive(:merged), else: refute_receive(:merged)
      assert {:ok, %{record: retried}} = Continuation.retry_checkpoint(c.store, token)

      assert {:ok, %{record: ^retried, replayed: true}} =
               Continuation.retry_checkpoint(c.store, token)

      assert :ok = Record.validate(retried, {c.store.namespace, :agent, "flow"})
      refute_receive :selected
      refute_receive :model
      refute_receive :merged

      if c.operation == "flow_merge" do
        assert retried["execution"]["state"] == "completed"

        assert {:ok, %{status: :completed}} =
                 Flow.resume(d, reference(retried), continuation: c.config)
      else
        assert retried["execution"]["state"] == "claimed"

        assert {:error, %ExAgent.RunError{}} =
                 Flow.resume(d, reference(retried), continuation: c.config)
      end

      assert {:ok, ^retried} = Store.load_record(c.store, :agent, "flow")
    end
  end

  test "late host-admission ACK rejects before selector after the current deadline", c do
    owner = self()
    d = definition(owner)
    Agent.update(c.control, fn _ -> {"flow_select_begin", :late} end)
    deadline = System.monotonic_time(:millisecond) + 1500

    task =
      Task.async(fn ->
        Flow.run(d, "root", continuation: c.config, root_options: [deadline: deadline])
      end)

    assert_receive {:late_ack, pid}, 1000

    receive do
    after
      max(deadline - System.monotonic_time(:millisecond) + 1, 0) -> :ok
    end

    send(pid, :release)
    assert {:error, %ExAgent.RunError{reason: :deadline_exceeded}} = Task.await(task, 5000)
    refute_receive :selected
    refute_receive :model
    refute_receive :merged
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert record["execution"]["progress"]["runtime"]["flow"]["phase"] == "selecting"
    assert Record.unresolved?(record["execution"])
  end

  test "shared authority admits one Model request exactly and preserves partial after a rejected sibling",
       c do
    owner = self()

    {:ok, d} =
      Flow.new(
        id: "limit",
        version: "1",
        kind: :parallel,
        max_concurrency: 1,
        branches: [branch(owner), %{branch(owner) | id: "B", definition: ref("B")}]
      )

    assert {:error, %ExAgent.RunError{partial: result}} =
             Flow.run(d, "root",
               continuation: c.config,
               root_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 1}]
             )

    assert result.request_count == 1
    assert_receive :model
    refute_receive :model
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})

    assert Enum.count(record["execution"]["effects"], fn {_, e} ->
             e["intent"]["kind"] == "model"
           end) == 1
  end

  test "partial approval and changed binding reject before claim; two exact resumers give one CAS winner",
       c do
    d = waiting_definition(self())
    permissions = ExAgent.Permissions.new!(default: :ask)
    opts = [continuation: c.config, step_options: %{"A" => [permissions: permissions]}]
    assert {:ok, %{status: :paused}} = Flow.run(d, "root", opts)
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    [one, two] = Map.keys(record["execution"]["progress"]["approvals"]) |> Enum.sort()
    partial = approve(c.store, record, one)
    assert partial["execution"]["state"] == "pending"
    assert {:error, _} = Flow.resume(d, reference(partial), opts)
    assert {:ok, ^partial} = Store.load_record(c.store, :agent, "flow")
    ready = approve(c.store, partial, two)
    assert ready["execution"]["state"] == "ready"
    assert {:error, _} = Flow.resume(%{d | version: "changed"}, reference(ready), opts)
    refute_receive :codec_load
    refute_receive {:effect, _}
    assert {:ok, ^ready} = Store.load_record(c.store, :agent, "flow")
    Agent.update(c.control, fn _ -> {"claim", :barrier} end)
    tasks = for _ <- 1..2, do: Task.async(fn -> Flow.resume(d, reference(ready), opts) end)
    assert_receive {:claim_waiting, a}, 5000
    assert_receive {:claim_waiting, b}, 5000
    refute_receive :codec_load
    Agent.update(c.control, fn _ -> nil end)
    send(a, :commit)
    send(b, :commit)
    results = Enum.map(tasks, &Task.await(&1, 30_000))
    assert Enum.count(results, &match?({:ok, %{status: :completed}}, &1)) == 1
    assert Enum.count(results, &match?({:error, %ExAgent.RunError{}}, &1)) == 1
    assert_receive :codec_load
    refute_receive :codec_load
    for id <- ~w(one two), do: assert_receive({:effect, ^id})
    refute_receive {:effect, _}
    assert_receive :after_approval_model
    refute_receive :after_approval_model
    {:ok, closed} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(closed, {c.store.namespace, :agent, "flow"})
  end

  test "current deny still limits original approved ask without repeating Model history", c do
    d = waiting_definition(self())

    assert {:ok, %{status: :paused}} =
             Flow.run(d, "root",
               continuation: c.config,
               step_options: %{"A" => [permissions: ExAgent.Permissions.new!(default: :ask)]}
             )

    {:ok, record} = Store.load_record(c.store, :agent, "flow")

    ready =
      Enum.reduce(
        Map.keys(record["execution"]["progress"]["approvals"]),
        record,
        &approve(c.store, &2, &1)
      )

    assert {:ok, result} =
             Flow.resume(d, reference(ready),
               continuation: c.config,
               step_options: %{"A" => [permissions: ExAgent.Permissions.new!(default: :deny)]}
             )

    assert result.request_count == 2
    # The exact host counter counts admitted tool attempts, including denied
    # outcomes. The callback counter below is the separate no-effect proof.
    assert result.tool_calls == 2
    refute_receive {:effect, _}
    assert_receive :after_approval_model
    refute_receive :after_approval_model
    {:ok, record} = Store.load_record(c.store, :agent, "flow")

    tools =
      Enum.filter(
        Map.values(record["execution"]["effects"]),
        &(&1["intent"]["kind"] == "tool")
      )

    assert tools == []
    frame = record["execution"]["progress"]["runtime"]
    calls = Enum.flat_map(Map.values(frame["tool_batches"]), &Map.values(&1["calls"]))
    assert length(calls) == 2

    assert Enum.all?(
             calls,
             &(&1["source"] == %{"kind" => "host", "reason" => "permission_denied"})
           )

    for call <- calls do
      {:ok, [%ExAgent.Message.Request{parts: [part]}]} = ExAgent.Message.from_json(call["result"])
      assert part.status == :denied
    end
  end

  test "owner death with Model in flight keeps uncertainty, ledger and abandoned budget without replay",
       c do
    owner = self()

    a =
      ExAgent.new(
        model: %ExAgent.Models.Test{
          script: [
            fn _, _ ->
              send(owner, {:model_waiting, self()})

              receive do
                :never -> "forbidden"
              end
            end
          ]
        }
      )

    {:ok, d} =
      Flow.new(
        id: "uncertain",
        version: "1",
        kind: :parallel,
        failure_policy: :collect,
        branches: [%{branch(owner) | agent: a}]
      )

    config = Map.merge(c.config, %{lease_ms: 800, active_time_limit_ms: 5000})
    {pid, monitor} = spawn_monitor(fn -> Flow.run(d, "root", continuation: config) end)
    assert_receive {:model_waiting, worker}, 5000
    wm = Process.monitor(worker)
    {:ok, admitted} = Store.load_record(c.store, :agent, "flow")
    assert map_size(admitted["execution"]["effects"]) == 1
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    assert_receive {:DOWN, ^wm, :process, ^worker, _}, 5000
    uncertain = recover(c, admitted)
    assert uncertain["execution"]["state"] == "uncertain"
    assert uncertain["execution"]["effects"] == admitted["execution"]["effects"]
    assert uncertain["execution"]["progress"]["runtime"]["flow"]["failures"] == %{}
    budget = uncertain["execution"]["progress"]["active_budget"]
    assert budget["remaining_ms"] == 0 and budget["refund_at"] == nil

    assert {:error, %ExAgent.RunError{}} =
             Flow.resume(d, reference(uncertain), continuation: config)

    assert {:ok, ^uncertain} = Store.load_record(c.store, :agent, "flow")
    refute_receive {:model_waiting, _}
  end

  test "pause and finish refund one active claim; human wait and data-only terminal resume never recharge",
       c do
    d = waiting_definition(self())
    config = Map.put(c.config, :active_time_limit_ms, 2000)

    opts = [
      continuation: config,
      step_options: %{"A" => [permissions: ExAgent.Permissions.new!(default: :ask)]}
    ]

    assert {:ok, %{status: :paused}} = Flow.run(d, "root", opts)
    {:ok, paused} = Store.load_record(c.store, :agent, "flow")
    balance = paused["execution"]["progress"]["active_budget"]["remaining_ms"]
    assert balance in 1..2000
    assert paused["execution"]["progress"]["active_budget"]["reserved_ms"] == nil

    receive do
    after
      2100 -> :ok
    end

    {:ok, ^paused} = Store.load_record(c.store, :agent, "flow")

    ready =
      Enum.reduce(
        Map.keys(paused["execution"]["progress"]["approvals"]),
        paused,
        &approve(c.store, &2, &1)
      )

    assert {:ok, result} = Flow.resume(d, reference(ready), opts)
    {:ok, closed} = Store.load_record(c.store, :agent, "flow")
    budget = closed["execution"]["progress"]["active_budget"]
    assert budget["remaining_ms"] <= balance and budget["reserved_ms"] == nil
    assert budget["refund_at"] == nil
    assert {:ok, _} = Flow.resume(d, result.continuation, opts)
    assert {:ok, ^closed} = Store.load_record(c.store, :agent, "flow")
  end

  test "grammar rejects selection reorder, duplicate branches, orphan failure and result above persisted slot",
       c do
    {:ok, result} = Flow.run(definition(self()), "root", continuation: c.config)
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    frame = record["execution"]["progress"]["runtime"]
    [id] = Map.keys(frame["children"])

    bad = [
      put_in(record, ["execution", "progress", "runtime", "flow", "selected"], ["A", "A"]),
      put_in(record, ["execution", "progress", "runtime", "flow", "failures"], %{
        "missing" => %{"kind" => "root", "error" => nil}
      }),
      put_in(
        record,
        ["execution", "progress", "runtime", "children", id, "result"],
        String.duplicate("x", 65_536)
      ),
      put_in(
        record,
        ["execution", "progress", "runtime", "flow", "result"],
        String.duplicate("x", 65_536)
      ),
      put_in(
        record,
        ["execution", "progress", "runtime", "children", id, "link", "input"],
        "different"
      )
    ]

    for r <- bad,
        do:
          assert(
            Record.validate(r, {c.store.namespace, :agent, "flow"}) == {:error, :invalid_record}
          )

    assert result.request_count == 1
    assert {:ok, ^record} = Store.load_record(c.store, :agent, "flow")
  end

  test "constructor/binding reject invalid bounds, duplicate IDs, unknown graph and do not call host functions",
       _ do
    owner = self()
    d = definition(owner)
    assert {:ok, b} = Flow.binding(d)
    assert :ok = Flow.validate_stored(b)

    for opts <- [
          max_concurrency: 0,
          max_concurrency: 33,
          max_result_bytes: 0,
          max_result_bytes: 65_537,
          max_branch_result_bytes: 65_537
        ] do
      {key, value} = opts
      assert {:error, :invalid_flow_definition} = Flow.binding(Map.put(d, key, value))
    end

    assert {:error, :invalid_flow_definition} =
             Flow.new(id: "x", version: "1", kind: :graph, branches: [branch(owner)])

    assert {:error, :invalid_flow_definition} =
             Flow.new(
               id: "x",
               version: "1",
               kind: :parallel,
               branches: [branch(owner), branch(owner)]
             )

    assert {:error, :invalid_flow_definition} =
             Flow.new(
               id: "x",
               version: "1",
               kind: :parallel,
               branches: Enum.map(1..33, fn i -> %{branch(owner) | id: Integer.to_string(i)} end)
             )

    refute_receive :selected
    refute_receive :model
    refute_receive :merged
  end

  for phase <- ~w(selecting merging) do
    @tag phase: phase
    test "actual host #{phase} crash survives fresh-VM recovery as uncertainty without replay or refund",
         c do
      dir = Path.join("/tmp/opencode", "flow-host-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      path = Path.join(dir, "record.json")
      effects = Path.join(dir, "effects.txt")
      paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

      args =
        ["--erl", "+S 2:2"] ++
          Enum.flat_map(paths, &["-pa", &1]) ++
          ["test/support/flow_host_phase_vm.exs", path, effects, c.phase]

      {out, status} =
        System.cmd(System.find_executable("elixir"), args ++ ["run"], stderr_to_stdout: true)

      assert status == 73, out
      first = File.read!(effects)

      assert first ==
               if(c.phase == "selecting", do: "selecting\n", else: "selecting\nmodel\nmerging\n")

      {out, status} =
        System.cmd(System.find_executable("elixir"), args ++ ["recover"], stderr_to_stdout: true)

      assert status == 0, out
      assert out =~ "FLOW_HOST uncertain"
      assert File.read!(effects) == first
    end
  end

  test "32 declared branches reserve finite own slots and host ACK receipts before any Model IO",
       c do
    branches =
      for n <- 1..32, do: %{branch(self()) | id: "branch#{n}", definition: ref("branch#{n}")}

    {:ok, d} = Flow.new(id: "maximum", version: "1", kind: :parallel, branches: branches)
    Agent.update(c.control, fn _ -> {"flow_select_begin", :before} end)
    assert {:error, _} = Flow.run(d, "root", continuation: c.config)
    refute_receive :model
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
    assert Record.receipt_reserve(record["execution"]) >= 5
    assert byte_size(Jason.encode!(record)) + Record.cleanup_reserve_bytes(record) <= 8_388_608
    assert record["execution"]["effects"] == %{}
  end

  test "restored host omission requires its persisted merged slot and matching causal error", c do
    {:ok, d} =
      Flow.new(
        id: "host-limit",
        version: "1",
        kind: :parallel,
        branches: [branch(self())],
        max_result_bytes: 4096,
        merge_version: "1",
        merge: fn _ -> String.duplicate("x", 4095) end
      )

    assert {:error, %ExAgent.RunError{partial: partial}} =
             Flow.run(d, "root", continuation: c.config)

    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    root = record["execution"]["progress"]["runtime"]
    assert root["flow"]["host_error"]["error"]["omitted"] == partial.output_omitted
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})

    for marker <- [
          Map.put(partial.output_omitted, "boundary", "checkpoint"),
          Map.put(partial.output_omitted, "limit", 4095),
          Map.put(partial.output_omitted, "limit", 65536),
          Map.put(partial.output_omitted, "bytes", 4096)
        ] do
      bad =
        record
        |> put_in(["execution", "progress", "runtime", "flow", "result_omitted"], marker)
        |> put_in(
          ["execution", "progress", "runtime", "flow", "host_error", "error", "omitted"],
          marker
        )
        |> put_in(
          ["execution", "progress", "runtime", "frontier", "fatal", "error", "omitted"],
          marker
        )

      assert {:error, :invalid_record} = Record.validate(bad, {c.store.namespace, :agent, "flow"})
    end
  end

  for history <- [:unchosen, :completed] do
    @tag history: history
    test "current deadlines of #{history} branches do not block the active approved branch", c do
      waiting = waiting_definition(self())
      unused = %{branch(self()) | id: "unused", definition: ref("unused")}

      opts =
        if c.history == :unchosen,
          do: [
            kind: :router,
            select_version: "1",
            select: fn _ -> "A" end,
            branches: [hd(waiting.steps), unused]
          ],
          else: [kind: :parallel, max_concurrency: 1, branches: [unused, hd(waiting.steps)]]

      {:ok, d} = Flow.new([id: "deadline-data", version: "1"] ++ opts)
      permissions = ExAgent.Permissions.new!(default: :ask)
      config = Map.put(c.config, :lease_ms, 5000)

      assert {:ok, %{status: :paused}} =
               Flow.run(d, "root",
                 continuation: config,
                 step_options: %{"A" => [permissions: permissions]}
               )

      if c.history == :completed, do: assert_receive(:model), else: refute_receive(:model)
      {:ok, record} = Store.load_record(c.store, :agent, "flow")

      ready =
        Enum.reduce(
          Map.keys(record["execution"]["progress"]["approvals"]),
          record,
          &approve(c.store, &2, &1)
        )

      assert {:ok, result} =
               Flow.resume(d, reference(ready),
                 continuation: config,
                 root_options: [deadline: System.monotonic_time(:millisecond) + 5000],
                 step_options: %{
                   "A" => [permissions: permissions],
                   "unused" => [deadline: System.monotonic_time(:millisecond) - 1]
                 }
               )

      assert result.status == :completed
      assert result.request_count == if(c.history == :unchosen, do: 2, else: 3)
      assert result.tool_calls == 2
      refute_receive :model
      assert_receive :codec_load
      refute_receive :codec_load
    end
  end

  for deadline_scope <- [:root, :leaf, :delegate_root, :delegate_leaf] do
    @tag deadline_scope: deadline_scope
    test "late claim ACK checks the current #{deadline_scope} deadline before codec or callbacks",
         c do
      d = waiting_definition(self())
      [step] = d.steps
      permissions = ExAgent.Permissions.new!(default: :ask)
      owner = self()
      delegated? = c.deadline_scope in [:delegate_root, :delegate_leaf]

      {d, catalog} =
        if delegated? do
          child = step.agent

          tool =
            ExAgent.Coordination.delegation_tool(fn _, _ -> flunk("durable builder") end,
              name: "delegate",
              prompt_arg: "task",
              continuation: %{
                definition: ref("D"),
                policy: ref("policy"),
                model_ref: ref("model"),
                model_codec: step.model_codec
              }
            )

          call = %ExAgent.Message.Part.ToolCall{
            tool_name: "delegate",
            tool_call_id: "child",
            args: %{"task" => "D input"}
          }

          parent =
            ExAgent.new(
              model: %ExAgent.Models.Test{script: [{:tool_calls, [call]}, "A"]},
              tools: [tool]
            )

          {%{d | steps: [%{step | agent: parent}]},
           [
             %{
               definition: ref("D"),
               policy: ref("policy"),
               model_ref: ref("model"),
               load: fn _, _ ->
                 send(owner, :delegate_load)
                 {:ok, child, [permissions: permissions], %{model_codec: step.model_codec}}
               end
             }
           ]}
        else
          {d, []}
        end

      config = Map.put(c.config, :lease_ms, 5000)

      base_opts = [
        continuation: config,
        delegate_definitions: catalog,
        step_options: %{"A" => [permissions: if(delegated?, do: nil, else: permissions)]}
      ]

      assert {:ok, %{status: :paused}} = Flow.run(d, "root", base_opts)
      if delegated?, do: assert_receive(:delegate_load)
      {:ok, record} = Store.load_record(c.store, :agent, "flow")

      ready =
        Enum.reduce(
          Map.keys(record["execution"]["progress"]["approvals"]),
          record,
          &approve(c.store, &2, &1)
        )

      Agent.update(c.control, fn _ -> {"claim", :late} end)
      deadline = System.monotonic_time(:millisecond) + 1000

      opts =
        if c.deadline_scope in [:root, :delegate_root],
          do: Keyword.put(base_opts, :root_options, deadline: deadline),
          else:
            Keyword.put(base_opts, :step_options, %{
              "A" => [permissions: if(delegated?, do: nil, else: permissions), deadline: deadline]
            })

      task = Task.async(fn -> Flow.resume(d, reference(ready), opts) end)
      assert_receive {:late_ack, pid}, 5000
      {:ok, claimed} = Store.load_record(c.store, :agent, "flow")
      assert claimed["revision"] == ready["revision"] + 1
      assert claimed["execution"]["state"] == "claimed"

      receive do
      after
        max(deadline - System.monotonic_time(:millisecond) + 1, 0) -> :ok
      end

      send(pid, :release)

      assert {:error, %ExAgent.RunError{reason: :deadline_exceeded, partial: partial}} =
               Task.await(task, 10_000)

      assert partial.continuation.revision == claimed["revision"]
      assert partial.continuation_checkpoint == nil
      refute_receive :codec_load
      refute_receive :delegate_load
      refute_receive :after_approval_model
      refute_receive {:effect, _}
      assert {:ok, ^claimed} = Store.load_record(c.store, :agent, "flow")
    end
  end

  test "a selected worker without an attached node is deferred by the common approval boundary",
       c do
    owner = self()
    gate = start_supervised!({Agent, fn -> true end}, id: :pre_attach)

    tool =
      ExAgent.Tool.new(
        name: "ask",
        takes_ctx: true,
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :effect)
          "raw"
        end
      )

    call = %ExAgent.Message.Part.ToolCall{tool_name: "ask", tool_call_id: "a", args: %{}}

    a =
      ExAgent.new(
        model: %ExAgent.Models.Test{
          script: [
            fn _, _ ->
              send(owner, {:early_model, self()})

              receive do
                :release -> {:tool_calls, [call]}
              end
            end,
            "A"
          ]
        },
        tools: [tool]
      )

    b =
      ExAgent.new(
        model: %GateModel{
          owner: owner,
          gate: gate,
          test: %ExAgent.Models.Test{
            script: [
              fn _, _ ->
                send(owner, :model_b)
                "B"
              end
            ]
          }
        }
      )

    b_branch = %{
      branch(owner)
      | id: "B",
        definition: ref("B"),
        agent: b,
        model_codec: %{
          dump: fn m -> {:ok, %{"index" => m.index}} end,
          load: fn m, data ->
            {:ok, %{m | index: data["index"], test: %{m.test | index: data["index"]}}}
          end
        }
    }

    {:ok, d} =
      Flow.new(
        id: "pre-attach-ask",
        version: "1",
        kind: :parallel,
        branches: [%{branch(owner) | agent: a}, b_branch],
        max_concurrency: 2
      )

    permissions = ExAgent.Permissions.new!(default: :ask)

    opts = [
      continuation: Map.put(c.config, :lease_ms, 5000),
      step_options: %{"A" => [permissions: permissions]}
    ]

    task = Task.async(fn -> Flow.run(d, "root", opts) end)
    assert_receive {:before_attach, b_pid}, 5000
    assert_receive {:early_model, a_pid}, 5000
    send(a_pid, :release)
    await_approval(c.store, 500)
    send(b_pid, :release)
    assert {:ok, %{status: :paused} = paused} = Task.await(task, 10_000)
    assert paused.request_count == 1 and paused.tool_calls == 1
    assert Enum.find(paused.branches, &(&1["id"] == "B"))["status"] == "not_started"
    refute Process.alive?(a_pid)
    refute Process.alive?(b_pid)
    refute_receive :effect
    refute_receive :model_b
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert map_size(record["execution"]["progress"]["runtime"]["children"]) == 1
    [approval] = Map.keys(record["execution"]["progress"]["approvals"])
    ready = approve(c.store, record, approval)

    expired_opts =
      Keyword.put(opts, :step_options, %{
        "A" => [permissions: permissions],
        "B" => [deadline: System.monotonic_time(:millisecond) - 1]
      })

    assert {:error, %ExAgent.RunError{reason: :deadline_exceeded}} =
             Flow.resume(d, reference(ready), expired_opts)

    assert {:ok, ^ready} = Store.load_record(c.store, :agent, "flow")
    refute_receive :model_b
    refute_receive :effect
    assert {:ok, result} = Flow.resume(d, reference(ready), opts)
    assert result.request_count == 3 and result.tool_calls == 1
    assert_receive :effect
    assert_receive :model_b
    refute_receive :effect
    refute_receive :model_b
  end

  for operation <- ~w(call_wait node_suspend) do
    @tag operation: operation
    test "confirmed #{operation} with a lost ACK recovers the unfinished approval drain without replay",
         c do
      d = waiting_definition(self())
      [step] = d.steps
      [{:tool_calls, [call | _]}, finish] = step.agent.model.script
      model = %{step.agent.model | script: [{:tool_calls, [call]}, finish]}
      d = %{d | steps: [%{step | agent: %{step.agent | model: model}}]}
      permissions = ExAgent.Permissions.new!(default: :ask)
      Agent.update(c.control, fn _ -> {c.operation, :after} end)
      opts = [continuation: c.config, step_options: %{"A" => [permissions: permissions]}]
      assert {:error, %ExAgent.RunError{partial: partial}} = Flow.run(d, "root", opts)
      assert partial.continuation_checkpoint != nil
      {:ok, stopped} = Store.load_record(c.store, :agent, "flow")
      assert stopped["execution"]["state"] == "claimed"
      assert stopped["execution"]["progress"]["runtime"]["frontier"]["reason"] == "approval"
      assert stopped["execution"]["progress"]["runtime"]["frontier"]["state"] == "draining"
      refute Record.unresolved?(stopped["execution"])
      refute_receive {:effect, _}
      ready = recover(c, stopped)
      assert ready["execution"]["state"] == "ready"
      opts = Keyword.put(opts, :continuation, Map.put(c.config, :lease_ms, 5000))

      assert {:ok, %{status: :paused, request_count: 1, tool_calls: 1}} =
               Flow.resume(d, reference(ready), opts)

      refute_receive :after_approval_model
      refute_receive {:effect, _}
      {:ok, paused} = Store.load_record(c.store, :agent, "flow")
      [approval] = Map.keys(paused["execution"]["progress"]["approvals"])
      approved = approve(c.store, paused, approval)

      assert {:ok, %{status: :completed, request_count: 2, tool_calls: 1}} =
               Flow.resume(d, reference(approved), opts)

      assert_receive {:effect, "one"}
      assert_receive :after_approval_model
      refute_receive {:effect, _}
      refute_receive :after_approval_model
    end
  end

  for boundary <- [:ordinary, :delegate, :batch_before, :batch_after, :uncertain] do
    @tag boundary: boundary
    test "#{boundary}: an admitted Model returning after sibling ask retains a recoverable common boundary",
         c do
      owner = self()

      make_call = fn id ->
        %ExAgent.Message.Part.ToolCall{tool_name: "ask", tool_call_id: id, args: %{}}
      end

      tool =
        ExAgent.Tool.new(
          name: "ask",
          takes_ctx: true,
          parameters_json_schema: %{"type" => "object"},
          call: fn context, _ ->
            send(owner, {:effect, context.tool_call_id})
            "raw"
          end
        )

      a =
        ExAgent.new(
          model: %ExAgent.Models.Test{
            script: [
              fn _, _ ->
                send(owner, {:first_model, self()})

                receive do
                  :release -> {:tool_calls, [make_call.("a")]}
                end
              end,
              "A"
            ]
          },
          tools: [tool]
        )

      codec = branch(owner).model_codec

      delegate =
        ExAgent.Coordination.delegation_tool(fn _, _ -> flunk("durable builder") end,
          name: "delegate",
          prompt_arg: "task",
          continuation: %{
            definition: ref("D"),
            policy: ref("policy"),
            model_ref: ref("model"),
            model_codec: codec
          }
        )

      d_agent =
        ExAgent.new(
          model: %ExAgent.Models.Test{script: [{:tool_calls, [make_call.("d")]}, "D"]},
          tools: [tool]
        )

      b_call =
        if c.boundary == :delegate,
          do: %ExAgent.Message.Part.ToolCall{
            tool_name: "delegate",
            tool_call_id: "b",
            args: %{"task" => "D input"}
          },
          else: make_call.("b")

      b =
        ExAgent.new(
          model: %ExAgent.Models.Test{
            script: [
              fn _, _ ->
                send(owner, {:late_model, self()})

                receive do
                  :release -> {:tool_calls, [b_call]}
                end
              end,
              "B"
            ]
          },
          tools: [if(c.boundary == :delegate, do: delegate, else: tool)]
        )

      {:ok, d} =
        Flow.new(
          id: "approval-race",
          version: "1",
          kind: :parallel,
          max_concurrency: 2,
          branches: [
            %{branch(owner) | agent: a},
            %{branch(owner) | id: "B", definition: ref("B"), agent: b}
          ]
        )

      config =
        if c.boundary == :uncertain,
          do: Map.merge(c.config, %{lease_ms: 5000, active_time_limit_ms: 20_000}),
          else: Map.put(c.config, :lease_ms, if(c.boundary == :delegate, do: 15_000, else: 5000))

      permissions = ExAgent.Permissions.new!(default: :ask)

      catalog =
        if c.boundary == :delegate,
          do: [
            %{
              definition: ref("D"),
              policy: ref("policy"),
              model_ref: ref("model"),
              load: fn _, _ ->
                send(owner, :delegate_load)
                {:ok, d_agent, [permissions: permissions], %{model_codec: codec}}
              end
            }
          ],
          else: []

      opts = [
        continuation: config,
        delegate_definitions: catalog,
        step_options: %{
          "A" => [permissions: permissions],
          "B" => [permissions: if(c.boundary == :delegate, do: nil, else: permissions)]
        }
      ]

      task = Task.async(fn -> Flow.run(d, "root", opts) end)
      assert_receive {:late_model, pid}, 5000
      assert_receive {:first_model, first}, 5000
      send(first, :release)
      await_approval(c.store, 500)

      if c.boundary == :uncertain do
        await_suspension(c.store, "A", 500)
        Process.unlink(task.pid)
        monitor = Process.monitor(pid)
        Process.exit(task.pid, :kill)
        task_ref = task.ref
        task_pid = task.pid
        assert_receive {:DOWN, ^task_ref, :process, ^task_pid, :killed}, 5000
        assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5000
        {:ok, stopped} = Store.load_record(c.store, :agent, "flow")
        uncertain = recover(c, stopped)
        assert uncertain["execution"]["state"] == "uncertain"
        assert uncertain["execution"]["effects"] == stopped["execution"]["effects"]
        assert uncertain["execution"]["progress"]["active_budget"]["refund_at"] == nil
        assert {:error, %ExAgent.RunError{}} = Flow.resume(d, reference(uncertain), opts)
        assert {:ok, ^uncertain} = Store.load_record(c.store, :agent, "flow")
        refute_receive {:effect, _}
        refute_receive {:late_model, _}
      else
        if c.boundary in [:batch_before, :batch_after] do
          Agent.update(c.control, fn _ ->
            {"batch_begin", if(c.boundary == :batch_before, do: :before, else: :after)}
          end)
        end

        send(pid, :release)

        paused =
          if c.boundary in [:batch_before, :batch_after] do
            assert {:error, %ExAgent.RunError{partial: partial}} = Task.await(task, 30_000)
            assert partial.continuation_checkpoint != nil
            {:ok, stopped} = Store.load_record(c.store, :agent, "flow")
            refute Record.unresolved?(stopped["execution"])
            ready = recover(c, stopped)
            assert {:ok, %{status: :paused} = resumed} = Flow.resume(d, reference(ready), opts)
            resumed
          else
            assert {:ok, %{status: :paused} = paused} = Task.await(task, 30_000)
            paused
          end

        refute Process.alive?(pid)
        assert paused.request_count == if(c.boundary == :delegate, do: 3, else: 2)
        assert paused.tool_calls == if(c.boundary == :delegate, do: 3, else: 2)
        if c.boundary == :delegate, do: assert_receive(:delegate_load)
        refute_receive {:effect, _}
        {:ok, record} = Store.load_record(c.store, :agent, "flow")
        assert map_size(record["execution"]["progress"]["approvals"]) == 2

        ready =
          Enum.reduce(
            Map.keys(record["execution"]["progress"]["approvals"]),
            record,
            &approve(c.store, &2, &1)
          )

        assert {:ok, result} = Flow.resume(d, reference(ready), opts)
        assert result.request_count == if(c.boundary == :delegate, do: 6, else: 4)
        assert result.tool_calls == if(c.boundary == :delegate, do: 3, else: 2)

        for id <- if(c.boundary == :delegate, do: ~w(a d), else: ~w(a b)),
            do: assert_receive({:effect, ^id})

        refute_receive {:effect, _}
        refute_receive {:late_model, _}
      end
    end
  end

  defp await_approval(store, left) when left > 0 do
    {:ok, record} = Store.load_record(store, :agent, "flow")

    if record["execution"]["progress"]["runtime"]["frontier"]["reason"] != "approval" do
      receive do
      after
        10 -> :ok
      end

      await_approval(store, left - 1)
    end
  end

  defp await_approval(_, _), do: flunk("approval drain ACK was not observed")

  defp await_suspension(store, id, left) when left > 0 do
    {:ok, record} = Store.load_record(store, :agent, "flow")
    nodes = record["execution"]["progress"]["runtime"]["children"]

    unless Enum.any?(nodes, fn {_, node} ->
             node["link"]["step_id"] == id and node["status"] == "suspended"
           end) do
      receive do
      after
        10 -> :ok
      end

      await_suspension(store, id, left - 1)
    end
  end

  defp await_suspension(_, _, _), do: flunk("node_suspend ACK was not observed")
end
