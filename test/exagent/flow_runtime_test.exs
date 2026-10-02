defmodule ExAgent.FlowRuntimeTest do
  use ExUnit.Case, async: false
  alias ExAgent.Coordination.Flow
  alias ExAgent.Continuation.{Frame, Record}
  alias ExAgent.{Store, Tool}
  alias ExAgent.Message.Part.ToolCall

  defmodule FatalWrapper do
    use ExAgent.Capability
    defstruct []
    def after_tool_execute(_, _, _, _), do: raise("confirmed wrapper failure")
  end

  defmodule UnportableOutput do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:value, :integer)
    end

    def changeset(output, args), do: Ecto.Changeset.cast(output, args, [:value])
  end

  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp codec,
    do: %{
      dump: fn m -> {:ok, %{"index" => m.index}} end,
      load: fn m, d -> {:ok, %{m | index: d["index"]}} end
    }

  defp agent(script, tools \\ []),
    do: ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: tools)

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

  defp call(name, id, args \\ %{}), do: %ToolCall{tool_name: name, tool_call_id: id, args: args}

  defp effect(owner, name, result \\ "raw") do
    Tool.new(
      name: name,
      takes_ctx: false,
      parameters_json_schema: %{"type" => "object"},
      call: fn _ ->
        send(owner, {:effect, name, self()})
        {:ok, result}
      end
    )
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    store = Store.scoped({Store.ETS, __MODULE__}, "flow-runtime")

    %{
      store: store,
      config: %{
        store: store,
        id: "flow",
        policy: ref("policy"),
        durability: :ephemeral,
        expires_at: nil,
        lease_ms: 600_000
      }
    }
  end

  test "router checkpoints trusted selection and terminal projection is data only", c do
    owner = self()

    {:ok, d} =
      Flow.new(
        id: "route",
        version: "1",
        kind: :router,
        select_version: "1",
        select: fn input ->
          send(owner, {:selected, input})
          "B"
        end,
        branches: [
          branch("A", agent([{:tool_calls, [call("a", "a")]}, "A"], [effect(owner, "a")])),
          branch("B", agent([{:tool_calls, [call("b", "b")]}, "B"], [effect(owner, "b")]))
        ]
      )

    assert {:ok, result} = Flow.run(d, "root", continuation: c.config)
    assert result.status == :completed

    assert result.output == [
             %{
               "id" => "B",
               "status" => "completed",
               "output" => "B",
               "output_omitted" => nil,
               "error" => nil
             }
           ]

    assert result.request_count == 2 and result.tool_calls == 1
    assert_receive {:selected, "root"}
    assert_receive {:effect, "b", pid}
    refute Process.alive?(pid)
    refute_receive {:effect, "a", _}
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
    frame = record["execution"]["progress"]["runtime"]
    assert frame["frame_version"] == 11 and frame["flow"]["selected"] == ["B"]
    assert :ok = Frame.validate(frame)

    assert {:ok, same} =
             Flow.resume(
               %{d | select: fn _ -> flunk("selection replay") end},
               result.continuation,
               continuation: c.config
             )

    assert same.output == result.output
    assert {:ok, ^record} = Store.load_record(c.store, :agent, "flow")
  end

  test "parallel branches retain independent root input and deterministic outcome order", c do
    owner = self()

    branches =
      for id <- ~w(A B C),
          do:
            branch(
              id,
              agent([{:tool_calls, [call(id, id)]}, id <> " final"], [effect(owner, id)])
            )

    {:ok, d} =
      Flow.new(
        id: "parallel",
        version: "1",
        kind: :parallel,
        max_concurrency: 2,
        branches: branches
      )

    assert {:ok, result} = Flow.run(d, "root", continuation: c.config)
    assert result.status == :completed and Enum.map(result.output, & &1["id"]) == ~w(A B C)
    assert result.request_count == 6 and result.tool_calls == 3
    assert Enum.map(result.steps, & &1.input) == ["root", "root", "root"]
    for id <- ~w(A B C), do: assert_receive({:effect, ^id, _})
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
  end

  test "branch worker concurrency is bounded while two model requests are really in flight", c do
    owner = self()

    branches =
      for id <- ~w(A B C D) do
        branch(
          id,
          agent([
            fn _, _ ->
              send(owner, {:model_inflight, id, self()})

              receive do
                :release -> id
              end
            end
          ])
        )
      end

    {:ok, d} =
      Flow.new(
        id: "concurrency",
        version: "1",
        kind: :parallel,
        max_concurrency: 2,
        branches: branches
      )

    task = Task.async(fn -> Flow.run(d, "root", continuation: c.config) end)
    assert_receive {:model_inflight, "A", a}, 5000
    assert_receive {:model_inflight, "B", b}, 5000
    refute_receive {:model_inflight, _, _}, 100
    send(b, :release)
    assert_receive {:model_inflight, "C", cc}, 5000
    send(cc, :release)
    assert_receive {:model_inflight, "D", dd}, 5000
    send(dd, :release)
    send(a, :release)
    assert {:ok, result} = Task.await(task, 30_000)
    assert result.request_count == 4 and result.tool_calls == 0
    assert Enum.map(result.output, & &1["output"]) == ~w(A B C D)
    for pid <- [a, b, cc, dd], do: refute(Process.alive?(pid))
  end

  for delta <- [0, 1] do
    @tag delta: delta
    test "merged portable result bound exact/+1 #{delta} has data or marker, without replay", c do
      owner = self()

      {:ok, d} =
        Flow.new(
          id: "merge-limit",
          version: "1",
          kind: :parallel,
          branches: [branch("A", agent(["A"]))],
          max_result_bytes: 4096,
          merge_version: "1",
          merge: fn _ ->
            send(owner, :merged)
            String.duplicate("x", 4094 + c.delta)
          end
        )

      outcome = Flow.run(d, "root", continuation: c.config)
      assert_receive :merged
      {:ok, record} = Store.load_record(c.store, :agent, "flow")
      assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})

      if c.delta == 0 do
        assert {:ok, %{output: result, status: :completed}} = outcome
        assert byte_size(Jason.encode!(result)) == 4096
      else
        assert {:error, %ExAgent.RunError{partial: partial}} = outcome
        assert record["execution"]["state"] == "failed"
        assert partial.output == nil
        assert partial.output_omitted == ExAgent.Retention.marker(:output, 4097, 4096)

        assert record["execution"]["progress"]["runtime"]["flow"]["host_error"]["phase"] ==
                 "merging"
      end

      reference = %{
        version: 1,
        id: "flow",
        record_id: record["record_id"],
        revision: record["revision"],
        run_id: record["execution"]["run_id"]
      }

      same =
        Flow.resume(%{d | merge: fn _ -> flunk("merge replay") end}, reference,
          continuation: c.config
        )

      assert elem(same, 0) == elem(outcome, 0)
      refute_receive :merged
      assert {:ok, ^record} = Store.load_record(c.store, :agent, "flow")
    end
  end

  test "unknown route rejects before agent IO and closes a confirmed host failure", c do
    owner = self()

    {:ok, d} =
      Flow.new(
        id: "bad-route",
        version: "1",
        kind: :router,
        select_version: "1",
        select: fn _ -> "untrusted" end,
        branches: [
          branch(
            "A",
            agent([
              fn _, _ ->
                send(owner, :model)
                "A"
              end
            ])
          )
        ]
      )

    assert {:error, %ExAgent.RunError{reason: :invalid_flow_selection, partial: result}} =
             Flow.run(d, "root", continuation: c.config)

    assert result.request_count == 0 and result.tool_calls == 0
    refute_receive :model
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert record["execution"]["state"] == "failed"
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
  end

  test "fail_fast preserves a completed sibling, closes certified failure and never admits the queued branch",
       c do
    owner = self()

    a = %{
      agent([{:tool_calls, [call("effect", "a")]}], [effect(owner, "effect")])
      | capabilities: [%FatalWrapper{}]
    }

    {:ok, d} =
      Flow.new(
        id: "fail-fast",
        version: "1",
        kind: :parallel,
        max_concurrency: 1,
        branches: [
          branch("done", agent(["done"])),
          branch("A", a),
          branch(
            "never",
            agent([
              fn _, _ ->
                send(owner, :forbidden)
                "never"
              end
            ])
          )
        ]
      )

    assert {:error, %ExAgent.RunError{partial: result}} =
             Flow.run(d, "root", continuation: c.config)

    assert result.request_count == 2 and result.tool_calls == 1
    assert Enum.map(result.branches, & &1["status"]) == ~w(completed failed not_started)
    assert_receive {:effect, "effect", _}
    refute_receive :forbidden
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert record["execution"]["state"] == "failed"
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
  end

  test "collect keeps a confirmed failed branch alongside C7 delegated pause and resumes no old effects",
       c do
    owner = self()

    slow =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        parameters_json_schema: %{"type" => "object"},
        call: fn _ ->
          send(owner, {:blocked_effect, self()})

          receive do
            :release -> {:ok, "A raw"}
          end
        end
      )

    a = %{
      agent([{:tool_calls, [call("effect", "a")]}, "forbidden"], [slow])
      | capabilities: [%FatalWrapper{}]
    }

    ask = effect(owner, "ask")
    d_agent = agent([{:tool_calls, [call("ask", "d")]}, "D final"], [ask])

    delegate =
      ExAgent.Coordination.delegation_tool(fn _, _ -> flunk("durable builder") end,
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
      agent([{:tool_calls, [call("delegate", "b", %{"task" => "D input"})]}, "B final"], [
        delegate
      ])

    {:ok, flow} =
      Flow.new(
        id: "collect",
        version: "1",
        kind: :parallel,
        failure_policy: :collect,
        max_concurrency: 2,
        branches: [branch("A", a), branch("B", b), branch("C", agent(["C final"]))]
      )

    catalog = [
      %{
        definition: ref("D"),
        policy: ref("policy"),
        model_ref: ref("model"),
        load: fn _, _ ->
          {:ok, d_agent,
           [permissions: ExAgent.Permissions.new!(default: :allow, rules: [{"ask", :ask}])],
           %{model_codec: codec()}}
        end
      }
    ]

    task =
      Task.async(fn ->
        Flow.run(flow, "root", continuation: c.config, delegate_definitions: catalog)
      end)

    assert_receive {:blocked_effect, pid}, 5000
    send(pid, :release)
    assert {:ok, paused} = Task.await(task, 30_000)
    assert paused.status == :paused
    refute Process.alive?(pid)
    refute_receive {:effect, "ask", _}
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
    frame = record["execution"]["progress"]["runtime"]
    assert map_size(frame["flow"]["failures"]) == 1
    assert frame["flow"]["failures"]["A"]["kind"] == "call"
    assert Enum.any?(paused.branches, &(&1["id"] == "A" and &1["status"] == "failed"))

    record =
      Enum.reduce(Map.keys(record["execution"]["progress"]["approvals"]), record, fn id, r ->
        {:ok, %{record: next}} =
          ExAgent.Continuation.decide(c.store, "flow", :approve,
            record_id: r["record_id"],
            revision: r["revision"],
            operation_id: "approve-#{r["revision"]}",
            actor: "human",
            authorize: fn actor, _, _ -> {:ok, actor} end,
            approval_id: id,
            payload_hash: r["execution"]["progress"]["approvals"][id]["payload_hash"]
          )

        next
      end)

    reference = %{paused.continuation | revision: record["revision"]}

    assert {:ok, completed} =
             Flow.resume(flow, reference, continuation: c.config, delegate_definitions: catalog)

    assert completed.status == :completed
    assert Enum.map(completed.output, & &1["id"]) == ~w(A B C)
    assert Enum.map(completed.output, & &1["status"]) == ~w(failed completed completed)
    assert completed.request_count == 6 and completed.tool_calls == 3
    assert_receive {:effect, "ask", _}
    refute_receive {:blocked_effect, _}
    refute_receive {:effect, _, _}
    {:ok, closed} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(closed, {c.store.namespace, :agent, "flow"})
  end

  test "collect certifies exhausted ordinary retry from the canonical batch reducer", c do
    owner = self()

    tool =
      Tool.new(
        name: "retry",
        takes_ctx: false,
        max_retries: 0,
        parameters_json_schema: %{"type" => "object"},
        call: fn _ ->
          send(owner, :retry_effect)
          raise ExAgent.ModelRetry, "confirmed retryable result"
        end
      )

    a = agent([{:tool_calls, [call("retry", "r")]}], [tool])

    {:ok, d} =
      Flow.new(
        id: "collect-retry",
        version: "1",
        kind: :parallel,
        failure_policy: :collect,
        branches: [branch("A", a), branch("B", agent(["B"]))]
      )

    assert {:ok, result} = Flow.run(d, "root", continuation: c.config)
    assert result.status == :completed
    assert Enum.map(result.output, & &1["status"]) == ~w(failed completed)
    assert result.request_count == 2 and result.tool_calls == 1
    assert_receive :retry_effect
    refute_receive :retry_effect
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
    assert record["execution"]["progress"]["runtime"]["flow"]["failures"]["A"]["kind"] == "batch"
  end

  for delta <- [0, 1] do
    @tag delta: delta
    test "branch portable output bound #{delta} preserves confirmed source and produces exact value or marker",
         c do
      {:ok, d} =
        Flow.new(
          id: "branch-limit",
          version: "1",
          kind: :parallel,
          failure_policy: :collect,
          max_branch_result_bytes: 4096,
          branches: [
            branch("A", agent([String.duplicate("x", 4094 + c.delta)])),
            branch("B", agent(["B"]))
          ]
        )

      assert {:ok, result} = Flow.run(d, "root", continuation: c.config)
      [a, b] = result.output
      assert b["output"] == "B"

      if c.delta == 0 do
        assert a["status"] == "completed" and byte_size(Jason.encode!(a["output"])) == 4096
      else
        assert a["status"] == "failed" and a["output"] == nil
        assert a["output_omitted"] == ExAgent.Retention.marker(:output, 4097, 4096)
      end

      assert result.request_count == 2 and result.tool_calls == 0
      {:ok, record} = Store.load_record(c.store, :agent, "flow")
      assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
    end
  end

  test "collect A8 crosses two fresh VMs and an actual crash after D final before parent wrapper",
       _c do
    alias ExAgent.DelegationRuntimeFixture, as: F
    dir = Path.join("/tmp/opencode", "flow-vm-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    path = Path.join(dir, "record.json")
    effects = Path.join(dir, "effects.txt")
    store = Store.scoped({Store.ETS, __MODULE__}, "delegation-runtime")
    {definition, catalog} = ExAgent.FlowRuntimeFixture.host(effects)

    assert {:ok, %{status: :paused}} =
             Flow.run(definition, "root",
               continuation: F.config(store),
               delegate_definitions: catalog
             )

    {:ok, record} = Store.load_record(store, :agent, "run")

    approved =
      Enum.reduce(Map.keys(record["execution"]["progress"]["approvals"]), record, fn id, r ->
        {:ok, %{record: next}} = ExAgent.SequenceApprovalFixture.decide(store, r, id)
        next
      end)

    File.write!(path, Jason.encode!(approved))
    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++ ["test/support/flow_runtime_vm.exs", path, effects]

    {out, status} =
      System.cmd(System.find_executable("elixir"), args ++ ["crash"], stderr_to_stdout: true)

    assert status == 71, out
    crashed = Jason.decode!(File.read!(path))
    assert :ok = Record.validate(crashed, {"delegation-runtime", :agent, "run"})

    assert crashed["execution"]["state"] == "claimed" and
             not Record.unresolved?(crashed["execution"])

    assert crashed["execution"]["progress"]["runtime"]["flow"]["failures"]["A"]["kind"] == "call"

    {out, status} =
      System.cmd(System.find_executable("elixir"), args ++ ["recover"], stderr_to_stdout: true)

    assert status == 0, out
    assert out =~ "FLOW_VM completed"
    lines = String.split(File.read!(effects), "\n", trim: true)

    for label <-
          ~w(A B D C ASK:ask1 ASK:ask2 before:a before:b before:d before:delegate before:ask1 before:ask2 after:a after:b after:d after:delegate after:ask1 after:ask2),
        do: assert(Enum.count(lines, &(&1 == label)) == 1)
  end

  test "typed branch outcome is retained and merged by definition order", c do
    typed =
      ExAgent.new(
        output: ExAgent.ContinuationNativeFixture.CountOutput,
        model: %ExAgent.Models.Test{
          script: [{:tool_calls, [call("final_result", "typed", %{"count" => 7})]}]
        }
      )

    {:ok, d} =
      Flow.new(
        id: "typed",
        version: "1",
        kind: :parallel,
        branches: [branch("typed", typed), branch("text", agent(["text"]))]
      )

    assert {:ok, result} = Flow.run(d, "root", continuation: c.config)
    assert Enum.map(result.output, & &1["output"]) == [%{"count" => 7}, "text"]
    assert result.request_count == 2 and result.tool_calls == 0
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
  end

  test "unportable typed result preserves confirmed output attestation and fails only its collected branch",
       c do
    typed =
      ExAgent.new(
        output: UnportableOutput,
        model: %ExAgent.Models.Test{
          script: [{:tool_calls, [call("final_result", "typed", %{"value" => 7})]}]
        }
      )

    {:ok, d} =
      Flow.new(
        id: "typed-omission",
        version: "1",
        kind: :parallel,
        failure_policy: :collect,
        branches: [branch("typed", typed), branch("text", agent(["text"]))]
      )

    assert {:ok, result} = Flow.run(d, "root", continuation: c.config)
    [a, b] = result.branches
    assert a["status"] == "failed" and a["output"] == nil
    assert a["output_omitted"]["boundary"] == "checkpoint"
    assert a["error"]["omitted"] == a["output_omitted"]
    assert b["output"] == "text"
    assert result.request_count == 2 and result.tool_calls == 0
    {:ok, record} = Store.load_record(c.store, :agent, "flow")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
    [entry] = Map.values(record["execution"]["progress"]["runtime"]["output_resolutions"])
    assert entry["decision"] == "succeeded" and entry["result"] == nil and entry["result_omitted"]
  end

  for sibling <- [:known, :unknown] do
    @tag sibling: sibling
    test "fail_fast drains #{sibling} admitted sibling without new wrapper or Model IO", c do
      owner = self()

      tool = fn id ->
        Tool.new(
          name: "effect",
          takes_ctx: false,
          parameters_json_schema: %{"type" => "object"},
          call: fn _ ->
            send(owner, {:inflight, id, self()})

            receive do
              :release ->
                if id == "B" and c.sibling == :unknown, do: raise("uncertain external effect")
                id <> " raw"
            end
          end
        )
      end

      a = %{
        agent([{:tool_calls, [call("effect", "a")]}], [tool.("A")])
        | capabilities: [%FatalWrapper{}]
      }

      b =
        agent(
          [
            {:tool_calls, [call("effect", "b")]},
            fn _, _ ->
              send(owner, :forbidden_model)
              "forbidden"
            end
          ],
          [tool.("B")]
        )

      {:ok, d} =
        Flow.new(
          id: "fatal-drain",
          version: "1",
          kind: :parallel,
          max_concurrency: 2,
          branches: [
            branch("A", a),
            branch("B", b),
            branch(
              "C",
              agent([
                fn _, _ ->
                  send(owner, :queued_model)
                  "C"
                end
              ])
            )
          ]
        )

      config = Map.merge(c.config, %{lease_ms: 2000, active_time_limit_ms: 5000})
      task = Task.async(fn -> Flow.run(d, "root", continuation: config) end)
      assert_receive {:inflight, "A", apid}, 5000
      assert_receive {:inflight, "B", bpid}, 5000
      send(apid, :release)
      await_fatal(c.store, 500)
      send(bpid, :release)
      assert {:error, %ExAgent.RunError{partial: result}} = Task.await(task, 30_000)
      assert result.request_count == 2 and result.tool_calls == 2
      refute Process.alive?(apid)
      refute Process.alive?(bpid)
      refute_receive :forbidden_model
      refute_receive :queued_model
      {:ok, record} = Store.load_record(c.store, :agent, "flow")
      assert :ok = Record.validate(record, {c.store.namespace, :agent, "flow"})
      frame = record["execution"]["progress"]["runtime"]
      bcall = Enum.find_value(frame["tool_batches"], fn {_, batch} -> batch["calls"]["b"] end)

      if c.sibling == :known do
        {:ok, [%ExAgent.Message.Request{parts: [raw]}]} =
          ExAgent.Message.from_json(bcall["raw"]["result"])

        assert record["execution"]["state"] == "failed"
        assert bcall["state"] == "blocked" and bcall["result"] == nil
        assert raw.content == "B raw" and raw.status == :succeeded
        assert record["execution"]["progress"]["active_budget"]["reserved_ms"] == nil
      else
        assert record["execution"]["state"] == "claimed" and
                 Record.unresolved?(record["execution"])

        assert bcall["raw"] == nil and bcall["result"] == nil

        effect =
          Enum.find(
            Map.values(record["execution"]["effects"]),
            &(&1["intent"]["kind"] == "tool" and &1["intent"]["call_id"] == "b")
          )

        assert effect["state"] == "running" and effect["outcome"] == nil
        assert record["execution"]["progress"]["active_budget"]["remaining_ms"] == 0
        assert record["execution"]["progress"]["active_budget"]["reserved_ms"] > 0

        receive do
        after
          max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0) -> :ok
        end

        {:ok, %{record: uncertain}} =
          ExAgent.Continuation.recover(c.store, "flow",
            record_id: record["record_id"],
            revision: record["revision"],
            operation_id: "recover-fatal",
            actor: "host",
            authorize: fn actor, _, _ -> {:ok, actor} end
          )

        assert uncertain["execution"]["state"] == "uncertain"
        assert uncertain["execution"]["effects"] == record["execution"]["effects"]

        assert uncertain["execution"]["progress"]["runtime"] ==
                 record["execution"]["progress"]["runtime"]

        assert uncertain["execution"]["progress"]["active_budget"]["remaining_ms"] == 0

        ref = %{
          version: 1,
          id: "flow",
          record_id: uncertain["record_id"],
          revision: uncertain["revision"],
          run_id: uncertain["execution"]["run_id"]
        }

        assert {:error, %ExAgent.RunError{}} = Flow.resume(d, ref, continuation: config)
        assert {:ok, ^uncertain} = Store.load_record(c.store, :agent, "flow")
        refute_receive {:inflight, _, _}
      end
    end
  end

  defp await_fatal(store, left) when left > 0 do
    {:ok, record} = Store.load_record(store, :agent, "flow")

    if record["execution"]["progress"]["runtime"]["frontier"]["reason"] != "fatal" do
      receive do
      after
        10 -> :ok
      end

      await_fatal(store, left - 1)
    end
  end

  defp await_fatal(_, _), do: flunk("fatal ACK was not observed")
end
