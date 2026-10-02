defmodule ExAgent.SequenceApprovalTest do
  # This suite checks the historical frame-9 journal/receipt contract. Its fresh
  # sources are authentic CAS/codec-checked 9 records, resumed by the public API.
  # Producer-10 mixed C7, ACK, counters and delegation are tested independently.
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, Store}
  alias ExAgent.Continuation.Record
  alias ExAgent.Coordination.Composition
  alias ExAgent.SequenceApprovalFixture, as: F

  defmodule EffectiveArgs do
    use ExAgent.Capability
    defstruct [:suffix]

    def before_tool_execute(%{suffix: suffix}, _, call),
      do: %{call | args: Map.update!(call.args, "label", &(&1 <> suffix))}
  end

  defmodule ObservedModel do
    @behaviour ExAgent.Model
    defstruct [:owner, script: [], index: 0]
    def system(_), do: "test"
    def model_name(_), do: "test"
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}
    def validate_resume(_, _, _, _), do: :ok

    def request(model, messages, settings, params) do
      send(model.owner, {:approved_model_io, settings.timeout})

      {:ok, response, next} =
        ExAgent.Models.Test.request(
          %ExAgent.Models.Test{script: model.script, index: model.index},
          messages,
          settings,
          params
        )

      {:ok, response, %{model | index: next.index}}
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    control = start_supervised!({Agent, fn -> nil end})

    store =
      Store.scoped(
        {F.Journal, %{table: __MODULE__, control: control, owner: self()}},
        "sequence-approval"
      )

    effects = "/tmp/opencode/sequence-approval-effects-#{System.unique_integer([:positive])}"
    File.write!(effects, "")
    on_exit(fn -> File.rm(effects) end)

    %{
      store: store,
      control: control,
      effects: effects,
      definition: F.definition(effects),
      config: F.config(store)
    }
  end

  defp pause(c) do
    assert {:ok, %{status: :paused} = result} =
             ExAgent.LegacyStructuralFixture.run(
               c.definition,
               "input",
               [continuation: c.config] ++ F.options()
             )

    assert {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert File.read!(c.effects) == "A\n"
    assert result.continuation.revision == record["revision"]
    record
  end

  defp approve(c, pending) do
    Enum.reduce(Map.keys(pending["execution"]["progress"]["approvals"]), pending, fn id, record ->
      assert {:ok, %{record: next}} = F.decide(c.store, record, id)
      next
    end)
  end

  defp resume(c, record, extras \\ []) do
    Composition.resume(
      c.definition,
      F.reference(record),
      Keyword.merge([continuation: c.config] ++ F.options(), extras)
    )
  end

  test "partial decisions, denied inspection and pending resume reject before callbacks or claim",
       c do
    pending = pause(c)
    [first, second] = Map.keys(pending["execution"]["progress"]["approvals"])
    config = Map.put(c.config, :on_writer, fn _ -> flunk("claim callback") end)

    for record <- [pending] do
      assert {:error, %ExAgent.RunError{reason: :composition_not_ready, partial: partial}} =
               resume(c, record, continuation: config)

      assert partial.error_phase == :open
      assert partial.status == :failed
      assert Enum.map(partial.steps, & &1.status) == [:completed, :paused, :not_started]
    end

    assert {:ok, %{record: partial}} = F.decide(c.store, pending, first)
    assert partial["execution"]["state"] == "pending"

    assert {:error, %ExAgent.RunError{reason: :composition_not_ready}} =
             resume(c, partial, continuation: config)

    assert {:ok, %{record: denied}} = F.decide(c.store, partial, second, :deny)
    assert {:ok, %{status: :denied, record: ^denied}} = Continuation.get(c.store, "run")

    assert {:error, %ExAgent.RunError{reason: :composition_not_ready}} =
             resume(c, denied, continuation: config)

    assert {:ok, ^denied} = Store.load_record(c.store, :agent, "run")
    assert File.read!(c.effects) == "A\n"
  end

  for mode <- [:before, :after] do
    test "pause #{mode} commit: last confirmed B and real Store-only token", c do
      Agent.update(c.control, fn _ -> {"pause", unquote(mode)} end)

      assert {:error, %ExAgent.RunError{partial: partial}} =
               ExAgent.LegacyStructuralFixture.run(
                 c.definition,
                 "input",
                 [continuation: c.config] ++ F.options()
               )

      assert partial.status == :failed
      assert partial.error_phase == :checkpoint
      assert partial.error_step_id == "B"
      assert Enum.map(partial.steps, & &1.status) == [:completed, :running, :not_started]
      token = partial.continuation_checkpoint
      assert token["command"]["operation"] == "pause"
      assert {:ok, stored} = Store.load_record(c.store, :agent, "run")

      assert stored["execution"]["state"] ==
               if(unquote(mode) == :before, do: "claimed", else: "pending")

      assert partial.continuation.revision < stored["revision"] or unquote(mode) == :before
      assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
      assert {:ok, %{status: :pending}} = Continuation.get(c.store, "run")
      assert File.read!(c.effects) == "A\n"
    end

    test "decision #{mode} commit has exact actor/hash/op receipt and no execution", c do
      pending = pause(c)
      id = hd(Map.keys(pending["execution"]["progress"]["approvals"]))
      Agent.update(c.control, fn _ -> {"decide", unquote(mode)} end)
      assert {:error, _} = F.decide(c.store, pending, id)
      assert {:ok, %{record: decided}} = F.decide(c.store, pending, id)
      assert {:ok, %{record: ^decided, replayed: true}} = F.decide(c.store, pending, id)
      assert {:error, :operation_conflict} = F.decide(c.store, pending, id, :deny)
      assert decided["execution"]["progress"]["approvals"][id]["decision"]["actor_id"] == "human"
      assert decided["snapshot"] === pending["snapshot"]

      assert decided["execution"]["progress"]["active_budget"] ===
               pending["execution"]["progress"]["active_budget"]

      assert File.read!(c.effects) == "A\n"
    end

    test "claim #{mode} commit never dispatches B; retry token only persists", c do
      ready = approve(c, pause(c))
      Agent.update(c.control, fn _ -> {"claim", unquote(mode)} end)
      assert {:error, %ExAgent.RunError{partial: partial}} = resume(c, ready)
      assert partial.continuation.revision == ready["revision"]
      assert partial.continuation_checkpoint["command"]["operation"] == "claim"
      assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
      assert File.read!(c.effects) == "A\n"
    end
  end

  test "two fresh resumers share the same revision; loser runs no owner callback", c do
    ready = approve(c, pause(c))
    owner = self()

    config =
      Map.put(c.config, :on_writer, fn _ ->
        send(owner, :owner_callback)
        :ok
      end)

    Agent.update(c.control, fn _ -> {"claim", :barrier} end)
    first = Task.async(fn -> resume(c, ready, continuation: config) end)
    assert_receive {:before, "claim", held}, 5000
    assert {:ok, %{status: :completed}} = resume(c, ready, continuation: config)
    send(held, :release)

    assert {:error, %ExAgent.RunError{reason: {:continuation_checkpoint_failed, :conflict}}} =
             Task.await(first, 5000)

    assert_receive :owner_callback
    refute_receive :owner_callback
    assert ["A", b1, b2, "C"] = String.split(File.read!(c.effects), "\n", trim: true)
    assert Enum.sort([b1, b2]) == ["B1", "B2"]
  end

  test "finite budget pause refunds whole attempt; human wait exceeds original budget and lease",
       c do
    c = %{
      c
      | config:
          Map.merge(c.config, %{
            active_time_limit_ms: 2000,
            lease_ms: 2000,
            expires_at: System.system_time(:millisecond) + 30_000
          })
    }

    pending = pause(c)
    budget = pending["execution"]["progress"]["active_budget"]
    assert budget["remaining_ms"] > 0
    assert budget["remaining_ms"] < 2000
    authority = pending["execution"]["progress"]["runtime"]["authority"]

    receive do
    after
      2100 -> :ok
    end

    ready = approve(c, pending)
    assert {:ok, %{status: :completed}} = resume(c, ready)
    assert {:ok, final} = Store.load_record(c.store, :agent, "run")

    assert Map.take(final["execution"]["progress"]["runtime"]["authority"], Map.keys(authority)) ===
             authority

    assert final["execution"]["progress"]["active_budget"]["remaining_ms"] <
             budget["remaining_ms"]

    assert File.read!(c.effects) |> String.ends_with?("C\n")
  end

  test "global approval corruption and fake pause receipt rejected before callbacks", c do
    ready = approve(c, pause(c))
    [id | _] = Map.keys(ready["execution"]["progress"]["approvals"])
    approval = ready["execution"]["progress"]["approvals"][id]

    for change <- [
          %{"tool_name" => "missing"},
          %{"schema_hash" => String.duplicate("f", 64)},
          %{"requested_revision" => ready["revision"] + 1},
          %{"requested_revision" => 1},
          %{"call_id" => "wrong"},
          %{"run_id" => ready["execution"]["run_id"]}
        ] do
      attributes =
        approval |> Map.drop(~w(approval_version payload_hash decision)) |> Map.merge(change)

      {:ok, changed} = ExAgent.Continuation.Approval.new(attributes)
      changed = Map.put(changed, "decision", approval["decision"])
      invalid = put_in(ready, ["execution", "progress", "approvals", id], changed)

      assert {:error, :invalid_record} =
               Record.validate(invalid, {"sequence-approval", :agent, "run"})
    end

    invalid =
      update_in(ready, ["receipts"], fn receipts ->
        Map.reject(receipts, fn {_, r} -> r["operation"] == "pause" end)
      end)

    assert {:error, :invalid_record} =
             Record.validate(invalid, {"sequence-approval", :agent, "run"})

    assert File.read!(c.effects) == "A\n"
  end

  for operation <- ~w(begin_effect outcome step_output step_input), mode <- [:before, :after] do
    test "#{operation} B/C #{mode} commit: real token persists without replay", c do
      ready = approve(c, pause(c))
      Agent.update(c.control, fn _ -> {unquote(operation), unquote(mode)} end)
      assert {:error, %ExAgent.RunError{partial: partial}} = resume(c, ready)
      assert partial.error_phase == :checkpoint
      assert partial.continuation_checkpoint["command"]["operation"] == unquote(operation)
      effects = File.read!(c.effects)
      refute effects =~ "C\n"
      assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
      assert File.read!(c.effects) == effects
      assert {:ok, record} = Store.load_record(c.store, :agent, "run")
      assert :ok = Record.validate(record, {"sequence-approval", :agent, "run"})

      assert record["execution"]["progress"]["approvals"] ===
               ready["execution"]["progress"]["approvals"]
    end
  end

  test "effective post-hook args approved and reproduced, never replaced with model original",
       c do
    [a, b, last] = c.definition.steps
    b = %{b | agent: %{b.agent | capabilities: [%EffectiveArgs{suffix: "-effective"}]}}
    c = %{c | definition: %{c.definition | steps: [a, b, last]}}
    pending = pause(c)

    assert Enum.all?(pending["execution"]["progress"]["approvals"], fn {_, approval} ->
             String.ends_with?(approval["args"]["label"], "-effective")
           end)

    ready = approve(c, pending)
    assert {:ok, %{status: :completed}} = resume(c, ready)
    assert File.read!(c.effects) =~ "B1-effective\n"
    assert File.read!(c.effects) =~ "B2-effective\n"
  end

  test "changed effective args reject before tool effects even after approval", c do
    ready = approve(c, pause(c))
    [a, b, last] = c.definition.steps
    b = %{b | agent: %{b.agent | capabilities: [%EffectiveArgs{suffix: "-changed"}]}}

    assert {:error, %ExAgent.RunError{}} =
             resume(%{c | definition: %{c.definition | steps: [a, b, last]}}, ready)

    assert File.read!(c.effects) == "A\n"
  end

  test "current deny prevails over approved tools", c do
    ready = approve(c, pause(c))

    assert {:ok, %{status: :completed}} =
             resume(c, ready,
               step_options: %{"B" => [permissions: ExAgent.Permissions.new!(default: :deny)]}
             )

    assert File.read!(c.effects) == "A\nC\n"
    {:ok, record} = Store.load_record(c.store, :agent, "run")

    tools =
      record["execution"]["effects"]
      |> Map.values()
      |> Enum.filter(
        &(&1["intent"]["kind"] == "tool" and &1["intent"]["call_id"] in ["b1", "b2"])
      )

    assert length(tools) == 2
    assert Enum.all?(tools, &(&1["outcome"]["status"] == "denied"))
  end

  test "mixed allow actually effects sibling then fails closed without pause or refund", c do
    [a, b, last] = c.definition.steps
    [tool] = b.agent.tools
    [{:tool_calls, [ask, free]}, text] = b.agent.model.script
    free = %{free | tool_name: "free"}

    b = %{
      b
      | agent: %{
          b.agent
          | tools: [tool, %{tool | name: "free"}],
            model: %{b.agent.model | script: [{:tool_calls, [ask, free]}, text]}
        }
    }

    definition = %{c.definition | steps: [a, b, last]}

    opts = [
      continuation: c.config,
      step_options: %{
        "B" => [permissions: ExAgent.Permissions.new!(default: :ask, rules: [{"free", :allow}])]
      }
    ]

    assert {:error, %ExAgent.RunError{}} =
             ExAgent.LegacyStructuralFixture.run(definition, "input", opts)

    assert File.read!(c.effects) == "A\nB2\n"
    assert {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["state"] == "claimed"
    refute Map.has_key?(record["execution"]["progress"], "approvals")
    refute Enum.any?(record["receipts"], fn {_, r} -> r["operation"] == "pause" end)
    assert :ok = Record.validate(record, {"sequence-approval", :agent, "run"})
  end

  for mode <- [:death, :rejected_accounting] do
    test "mixed pending and #{mode} preserves actual sibling effect without quiescent pause", c do
      [a, b, last] = c.definition.steps
      [tool] = b.agent.tools
      [{:tool_calls, [ask, free]}, text] = b.agent.model.script
      free = %{free | tool_name: "free"}
      effects = c.effects

      failing = %{
        tool
        | name: "free",
          call: fn _, _ ->
            File.write!(effects, "B2\n", [:append])

            case unquote(mode) do
              :death ->
                exit(:kill)

              :rejected_accounting ->
                {:ok,
                 %ExAgent.Message.Part.ToolReturn{
                   tool_name: "free",
                   tool_call_id: "b2",
                   status: :succeeded,
                   content: "done",
                   usage: %ExAgent.Message.Usage{input_tokens: -1, output_tokens: 0}
                 }}
            end
          end
      }

      b = %{
        b
        | agent: %{
            b.agent
            | tools: [tool, failing],
              model: %{b.agent.model | script: [{:tool_calls, [ask, free]}, text]}
          }
      }

      definition = %{c.definition | steps: [a, b, last]}

      assert {:error, %ExAgent.RunError{}} =
               ExAgent.LegacyStructuralFixture.run(definition, "input",
                 continuation: c.config,
                 step_options: %{
                   "B" => [
                     permissions:
                       ExAgent.Permissions.new!(default: :ask, rules: [{"free", :allow}])
                   ]
                 }
               )

      assert File.read!(c.effects) == "A\nB2\n"
      {:ok, record} = Store.load_record(c.store, :agent, "run")
      assert record["execution"]["state"] == "claimed"
      refute Enum.any?(record["receipts"], fn {_, r} -> r["operation"] == "pause" end)
      refute Map.has_key?(record["execution"]["progress"], "approvals")
      assert :ok = Record.validate(record, {"sequence-approval", :agent, "run"})
    end
  end

  test "approved claim owner callback held past original budget cannot dispatch", c do
    ready = approve(c, pause(c))
    owner = self()

    config =
      Map.merge(c.config, %{
        active_time_limit_ms: 500,
        on_writer: fn _ ->
          # Registration runs inside Writer. The original 500ms reservation
          # began before this callback, so this is an upper bound, not renewal.
          send(owner, {:owner_held, self(), System.monotonic_time(:millisecond) + 500})

          receive do
            :release -> :ok
          end
        end
      })

    task = Task.async(fn -> resume(c, ready, continuation: config) end)
    assert_receive {:owner_held, held, deadline}, 5000
    wait = max(deadline - System.monotonic_time(:millisecond) + 1, 0)

    receive do
    after
      wait -> :ok
    end

    send(held, :release)
    assert {:error, %ExAgent.RunError{}} = Task.await(task, 5000)
    assert File.read!(c.effects) == "A\n"
  end

  test "approved history permits safe recovered suffix and completed is data-only", c do
    c = %{c | config: Map.put(c.config, :lease_ms, 1000)}
    ready = approve(c, pause(c))
    Agent.update(c.control, fn _ -> {"step_output", :after} end)
    assert {:error, %ExAgent.RunError{partial: partial}} = resume(c, ready)
    assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
    {:ok, stored} = Store.load_record(c.store, :agent, "run")
    wait = max(stored["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

    receive do
    after
      wait -> :ok
    end

    assert {:ok, %{record: recovered}} =
             Continuation.recover(c.store, "run",
               record_id: stored["record_id"],
               revision: stored["revision"],
               operation_id: "recover",
               actor: "host",
               authorize: fn actor, _, _ -> {:ok, actor} end
             )

    assert {:ok, %{status: :completed}} = resume(c, recovered)
    {:ok, completed} = Store.load_record(c.store, :agent, "run")

    assert completed["execution"]["progress"]["approvals"] ===
             ready["execution"]["progress"]["approvals"]

    effects = File.read!(c.effects)
    config = Map.put(c.config, :on_writer, fn _ -> flunk("completed must not claim") end)
    assert {:ok, %{status: :completed}} = resume(c, completed, continuation: config)
    assert File.read!(c.effects) == effects
  end

  for operation <- ~w(claim begin_effect) do
    test "late #{operation} ACK after lease expires cannot authorize tool IO", c do
      ready = approve(c, pause(c))
      owner = self()

      config =
        Map.merge(c.config, %{
          lease_ms: 500,
          on_writer: fn _ ->
            send(owner, :writer_callback)
            :ok
          end
        })

      Agent.update(c.control, fn _ -> {unquote(operation), :ack_barrier} end)
      task = Task.async(fn -> resume(c, ready, continuation: config) end)
      assert_receive {:after, unquote(operation), held}, 5000
      {:ok, claimed} = Store.load_record(c.store, :agent, "run")
      wait = max(claimed["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

      receive do
      after
        wait -> :ok
      end

      send(held, :release)
      assert {:error, %ExAgent.RunError{}} = Task.await(task, 5000)
      assert File.read!(c.effects) == "A\n"
      if unquote(operation) == "claim", do: refute_receive(:writer_callback)
    end
  end

  for bound <- [:expires_at, :deadline_at] do
    test "persisted #{bound} remains restrictive across human wait", c do
      config = Map.put(c.config, unquote(bound), System.system_time(:millisecond) + 1500)
      c = %{c | config: config}
      ready = approve(c, pause(c))

      wait =
        max(
          ready["execution"][Atom.to_string(unquote(bound))] - System.system_time(:millisecond) +
            1,
          0
        )

      receive do
      after
        wait -> :ok
      end

      config =
        Map.merge(c.config, %{
          unquote(bound) => nil,
          :on_writer => fn _ -> flunk("expired callback") end
        })

      assert {:error, %ExAgent.RunError{}} = resume(c, ready, continuation: config)
      assert File.read!(c.effects) == "A\n"
      assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
    end
  end

  test "abandoned finite approved claim consumes its reserved remaining budget", c do
    c = %{c | config: Map.merge(c.config, %{lease_ms: 1000, active_time_limit_ms: 2000})}
    ready = approve(c, pause(c))
    Agent.update(c.control, fn _ -> {"claim", :after} end)
    assert {:error, %ExAgent.RunError{}} = resume(c, ready)
    {:ok, abandoned} = Store.load_record(c.store, :agent, "run")
    wait = max(abandoned["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

    receive do
    after
      wait -> :ok
    end

    assert {:ok, %{record: recovered}} =
             Continuation.recover(c.store, "run",
               record_id: abandoned["record_id"],
               revision: abandoned["revision"],
               operation_id: "recover-budget",
               actor: "host",
               authorize: fn actor, _, _ -> {:ok, actor} end
             )

    assert {:error, %ExAgent.RunError{}} = resume(c, recovered)
    assert File.read!(c.effects) == "A\n"
  end

  test "pause reducer preserves exact root snapshot/runtime and next requested revision", c do
    Agent.update(c.control, fn _ -> {"pause", :before} end)

    assert {:error, %ExAgent.RunError{partial: partial}} =
             ExAgent.LegacyStructuralFixture.run(
               c.definition,
               "input",
               [continuation: c.config] ++ F.options()
             )

    command = partial.continuation_checkpoint["command"]
    {:ok, before} = Store.load_record(c.store, :agent, "run")
    key = {"sequence-approval", :agent, "run"}
    now = System.system_time(:millisecond)
    id = hd(Map.keys(command["payload"]["progress"]["approvals"]))

    mutations = [
      put_in(command, ["payload", "snapshot", "revision"], 1),
      put_in(
        command,
        [
          "payload",
          "progress",
          "runtime",
          "scope",
          "nodes",
          before["execution"]["run_id"],
          "requests"
        ],
        0
      ),
      put_in(
        command,
        [
          "payload",
          "progress",
          "runtime",
          "authority",
          before["execution"]["run_id"],
          "deadline_at"
        ],
        0
      )
    ]

    for mutation <- mutations do
      assert {:error, _} =
               ExAgent.Continuation.Transition.apply(
                 before,
                 key,
                 before["revision"],
                 mutation,
                 now
               )
    end

    approval = command["payload"]["progress"]["approvals"][id]

    {:ok, fake} =
      approval
      |> Map.drop(~w(approval_version payload_hash decision))
      |> Map.put("requested_revision", before["revision"])
      |> ExAgent.Continuation.Approval.new()

    mutation = put_in(command, ["payload", "progress", "approvals", id], fake)

    assert {:error, :invalid_pause} =
             ExAgent.Continuation.Transition.apply(before, key, before["revision"], mutation, now)

    assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
    assert File.read!(c.effects) == "A\n"
  end

  test "decisions bind CAS, maximum actor, payload hash and operation identity", c do
    pending = pause(c)
    [first, second] = Map.keys(pending["execution"]["progress"]["approvals"])
    actor = String.duplicate("h", 512)

    opts = [
      record_id: pending["record_id"],
      revision: pending["revision"],
      operation_id: "same-operation",
      actor: actor,
      authorize: fn a, _, _ -> {:ok, a} end,
      approval_id: first,
      payload_hash: pending["execution"]["progress"]["approvals"][first]["payload_hash"]
    ]

    assert {:ok, %{record: partial}} = Continuation.decide(c.store, "run", :approve, opts)
    assert partial["execution"]["progress"]["approvals"][first]["decision"]["actor_id"] == actor

    for mutated <- [
          Keyword.put(opts, :actor, "other"),
          Keyword.put(opts, :payload_hash, String.duplicate("0", 64)),
          Keyword.put(opts, :approval_id, second)
        ] do
      assert {:error, :operation_conflict} =
               Continuation.decide(c.store, "run", :approve, mutated)
    end

    assert {:error, :conflict} = F.decide(c.store, pending, second)
    assert {:ok, %{record: ready}} = F.decide(c.store, partial, second)
    assert ready["execution"]["state"] == "ready"
    assert File.read!(c.effects) == "A\n"
  end

  test "global valid partial approved effects remain non-restorable after explicit recover", c do
    c = %{c | config: Map.put(c.config, :lease_ms, 1000)}
    ready = approve(c, pause(c))
    Agent.update(c.control, fn _ -> {"outcome", :after} end)
    assert {:error, %ExAgent.RunError{partial: partial}} = resume(c, ready)
    assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
    {:ok, stored} = Store.load_record(c.store, :agent, "run")
    assert :ok = Record.validate(stored, {"sequence-approval", :agent, "run"})
    wait = max(stored["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

    receive do
    after
      wait -> :ok
    end

    assert {:ok, %{record: recovered}} =
             Continuation.recover(c.store, "run",
               record_id: stored["record_id"],
               revision: stored["revision"],
               operation_id: "recover-partial",
               actor: "host",
               authorize: fn a, _, _ -> {:ok, a} end
             )

    effects = File.read!(c.effects)

    assert {:error, %ExAgent.RunError{}} =
             resume(c, recovered,
               continuation: Map.put(c.config, :on_writer, fn _ -> flunk("unsafe restore") end)
             )

    assert File.read!(c.effects) == effects
  end

  for operation <- ~w(pause claim begin_effect outcome step_output step_input) do
    @tag timeout: 180_000
    test "#{operation} public checkpoint admission at exact minus/at/plus one", c do
      operation = unquote(operation)
      ready = if operation != "pause", do: approve(c, pause(c))
      {:ok, physical} = Record.key({"sequence-approval", :agent, "run"})

      trial = fn limit ->
        if ready do
          :ets.insert(__MODULE__, {physical, Jason.encode!(ready)})
          File.write!(c.effects, "A\n")
        else
          :ets.delete(__MODULE__, physical)
          File.write!(c.effects, "")
        end

        drain_commands()
        Agent.update(c.control, fn _ -> {operation, :before} end)
        config = Map.put(c.config, :max_checkpoint_bytes, limit)

        result =
          if ready,
            do: resume(c, ready, continuation: config),
            else:
              ExAgent.LegacyStructuralFixture.run(
                c.definition,
                "input",
                [continuation: config] ++ F.options()
              )

        assert {:error, %ExAgent.RunError{partial: partial}} = result

        hit =
          receive do
            {:journal_command, %{"operation" => ^operation}} -> true
          after
            0 -> false
          end

        {hit, partial}
      end

      assert {true, _} = trial.(512_000)
      exact = threshold(1, 512_000, trial)
      assert {false, _} = trial.(exact - 1)
      assert {true, accepted} = trial.(exact)
      assert accepted.continuation_checkpoint["command"]["operation"] == operation
      assert ExAgent.Retention.bytes(accepted.continuation_checkpoint) <= exact
      assert {true, _} = trial.(exact + 1)

      IO.inspect(
        %{
          operation: operation,
          checkpoint_limit: exact,
          token_bytes: ExAgent.Retention.bytes(accepted.continuation_checkpoint)
        },
        label: "SEQUENCE_APPROVAL_CAPACITY"
      )
    end
  end

  defp threshold(low, high, _) when low == high, do: low

  defp threshold(low, high, trial) do
    middle = div(low + high, 2)

    case trial.(middle) do
      {true, _} -> threshold(low, middle, trial)
      {false, _} -> threshold(middle + 1, high, trial)
    end
  end

  defp drain_commands do
    receive do
      {:journal_command, _} -> drain_commands()
      {:journal, _, _} -> drain_commands()
    after
      0 -> :ok
    end
  end

  @tag timeout: 180_000
  test "real receipt horizon pause ±1 reserves two maximum-actor decisions and cancellation", c do
    c = %{c | config: Map.put(c.config, :lease_ms, 600_000)}
    Agent.update(c.control, fn _ -> {"pause", :before} end)

    assert {:error, %ExAgent.RunError{partial: partial}} =
             ExAgent.LegacyStructuralFixture.run(
               c.definition,
               "input",
               [continuation: c.config] ++ F.options()
             )

    original = partial.continuation_checkpoint["command"]
    {:ok, initial} = Store.load_record(c.store, :agent, "run")
    key = {"sequence-approval", :agent, "run"}

    {:ok, %{record: projected}} =
      ExAgent.Continuation.Transition.apply(
        initial,
        key,
        initial["revision"],
        original,
        System.system_time(:millisecond)
      )

    room = 1024 - map_size(projected["receipts"]) - Record.receipt_reserve(projected["execution"])

    base =
      Enum.reduce(1..(room - 1), initial, fn i, record ->
        command = node_checkpoint(record, "capacity-#{i}")

        assert {:ok, %{record: next}} =
                 Store.transition(c.store, :agent, "run", record["revision"], command)

        drain_commands()
        next
      end)

    for delta <- [-1, 0, 1] do
      {:ok, physical} = Record.key(key)
      :ets.insert(__MODULE__, {physical, Jason.encode!(base)})

      before =
        Enum.reduce(Enum.take(1..2, delta + 1), base, fn i, record ->
          assert {:ok, %{record: next}} =
                   Store.transition(
                     c.store,
                     :agent,
                     "run",
                     record["revision"],
                     node_checkpoint(record, "delta-#{i}")
                   )

          next
        end)

      approvals =
        Map.new(original["payload"]["progress"]["approvals"], fn {id, approval} ->
          {:ok, updated} =
            approval
            |> Map.drop(~w(approval_version payload_hash decision))
            |> Map.put("requested_revision", before["revision"] + 1)
            |> ExAgent.Continuation.Approval.new()

          {id, updated}
        end)

      command = put_in(original, ["payload", "progress", "approvals"], approvals)

      if delta <= 0 do
        assert {:ok, %{record: pending}} =
                 Store.transition(c.store, :agent, "run", before["revision"], command)

        assert map_size(pending["receipts"]) + Record.receipt_reserve(pending["execution"]) ==
                 1024 + delta

        ready =
          Enum.reduce(Map.keys(approvals), pending, fn id, r ->
            assert {:ok, %{record: next}} =
                     Continuation.decide(c.store, "run", :approve,
                       record_id: r["record_id"],
                       revision: r["revision"],
                       operation_id: "maxactor-#{r["revision"]}",
                       actor: String.duplicate(<<1>>, 512),
                       authorize: fn a, _, _ -> {:ok, a} end,
                       approval_id: id,
                       payload_hash: approvals[id]["payload_hash"]
                     )

            next
          end)

        assert {:error, %ExAgent.RunError{}} = resume(c, ready)
        {:ok, current} = Store.load_record(c.store, :agent, "run")

        assert {:ok, _} =
                 Store.transition(c.store, :agent, "run", current["revision"], %{
                   "record_id" => current["record_id"],
                   "operation_id" => "cancel-capacity",
                   "actor_id" => "host",
                   "operation" => "cancel",
                   "payload" => %{}
                 })
      else
        assert {:error, :receipt_limit} =
                 Store.transition(c.store, :agent, "run", before["revision"], command)

        assert {:ok, ^before} = Store.load_record(c.store, :agent, "run")
      end

      drain_commands()
    end

    assert File.read!(c.effects) == "A\n"
  end

  defp node_checkpoint(record, operation_id) do
    e = record["execution"]

    %{
      "record_id" => record["record_id"],
      "operation_id" => operation_id,
      "operation" => "node_checkpoint",
      "actor_id" => "capacity-host",
      "payload" =>
        Map.merge(Map.take(e, ~w(owner_id attempt_id fence)), %{
          "node_id" => ExAgent.Continuation.Frame.active_step_id(e["progress"]["runtime"]),
          "snapshot" => record["snapshot"],
          "progress" => e["progress"]
        })
    }
  end

  @tag timeout: 180_000
  test "pause JSON ±1 accounts for cleanup and two worst-case escaped decision actors", c do
    c = %{c | config: Map.put(c.config, :lease_ms, 600_000)}
    Agent.update(c.control, fn _ -> {"pause", :before} end)

    assert {:error, %ExAgent.RunError{partial: partial}} =
             ExAgent.LegacyStructuralFixture.run(
               c.definition,
               "input",
               [continuation: c.config] ++ F.options()
             )

    original = partial.continuation_checkpoint["command"]
    {:ok, initial} = Store.load_record(c.store, :agent, "run")
    key = {"sequence-approval", :agent, "run"}
    {:ok, physical} = Record.key(key)
    node = ExAgent.Continuation.Frame.active_step_id(initial["execution"]["progress"]["runtime"])

    prepare = fn padding ->
      :ets.insert(__MODULE__, {physical, Jason.encode!(initial)})
      checkpoint = node_checkpoint(initial, "metadata-padding")

      checkpoint =
        put_in(
          checkpoint,
          ["payload", "progress", "runtime", "children", node, "snapshot", "metadata", "padding"],
          String.duplicate("x", padding)
        )

      assert {:ok, %{record: before}} =
               Store.transition(c.store, :agent, "run", initial["revision"], checkpoint)

      approvals =
        Map.new(original["payload"]["progress"]["approvals"], fn {id, a} ->
          {:ok, a} =
            a
            |> Map.drop(~w(approval_version payload_hash decision))
            |> Map.put("requested_revision", before["revision"] + 1)
            |> ExAgent.Continuation.Approval.new()

          {id, a}
        end)

      command =
        original
        |> put_in(["payload", "progress", "runtime"], before["execution"]["progress"]["runtime"])
        |> put_in(["payload", "progress", "approvals"], approvals)

      drain_commands()
      {before, command}
    end

    {before, command} = prepare.(0)

    assert {:ok, %{record: projected}} =
             ExAgent.Continuation.Transition.apply(
               before,
               key,
               before["revision"],
               command,
               System.system_time(:millisecond)
             )

    measured = fn r -> byte_size(Jason.encode!(r)) + Record.cleanup_reserve_bytes(r) end
    room = Record.max_bytes() - measured.(projected)

    for delta <- [-1, 0, 1] do
      {before, command} = prepare.(room + delta)

      if delta <= 0 do
        assert {:ok, %{record: pending}} =
                 Store.transition(c.store, :agent, "run", before["revision"], command)

        assert measured.(pending) == Record.max_bytes() + delta

        Enum.reduce(Map.keys(pending["execution"]["progress"]["approvals"]), pending, fn id, r ->
          assert {:ok, %{record: next}} =
                   Continuation.decide(c.store, "run", :approve,
                     record_id: r["record_id"],
                     revision: r["revision"],
                     operation_id: String.duplicate(<<r["revision"]>>, 512),
                     actor: String.duplicate(<<1>>, 512),
                     authorize: fn a, _, _ -> {:ok, a} end,
                     approval_id: id,
                     payload_hash: r["execution"]["progress"]["approvals"][id]["payload_hash"]
                   )

          assert measured.(next) <= Record.max_bytes()
          next
        end)
      else
        assert {:error, :record_limit} =
                 Store.transition(c.store, :agent, "run", before["revision"], command)

        assert {:ok, ^before} = Store.load_record(c.store, :agent, "run")
      end

      drain_commands()
    end

    assert File.read!(c.effects) == "A\n"
  end

  for operation <- ~w(pause claim) do
    @tag timeout: 120_000
    test "#{operation} isolated token parse bound ±1 precedes real CAS validation", c do
      operation = unquote(operation)
      ready = if operation == "claim", do: approve(c, pause(c))
      Agent.update(c.control, fn _ -> {operation, :before} end)

      result =
        if ready,
          do: resume(c, ready),
          else:
            ExAgent.LegacyStructuralFixture.run(
              c.definition,
              "input",
              [continuation: c.config] ++ F.options()
            )

      assert {:error, %ExAgent.RunError{partial: partial}} = result
      original = partial.continuation_checkpoint
      assert original["command"]["operation"] == operation
      assert {:ok, baseline} = Store.load_record(c.store, :agent, "run")

      # An inert unknown payload field isolates the token parser. It deliberately
      # is NOT a valid pause/claim command and must never be described as a
      # successful oversized record commit. The real reducer remains in the path.
      path = ["command", "payload", "codec_probe_padding"]
      base = put_in(original, path, "")
      room = Record.max_bytes() - ExAgent.Retention.bytes(base)

      for delta <- [-1, 0, 1] do
        token = put_in(base, path, String.duplicate("x", room + delta))
        assert ExAgent.Retention.bytes(token) == Record.max_bytes() + delta
        drain_commands()
        assert {:error, reason} = Continuation.retry_checkpoint(c.store, token)

        if delta <= 0 do
          assert_receive {:journal_command, command}
          assert command === token["command"]
          refute reason == :invalid_checkpoint_token

          assert {:error, ^reason} =
                   Store.transition(c.store, :agent, "run", baseline["revision"], command)
        else
          assert reason == :invalid_checkpoint_token
          refute_receive {:journal_command, _}, 0
        end

        assert {:ok, ^baseline} = Store.load_record(c.store, :agent, "run")
        assert File.read!(c.effects) == "A\n"
        IO.inspect({operation, delta, reason}, label: "APPROVAL_TOKEN_PARSE_BOUND")
      end

      assert {:ok, %{record: committed, replayed: false}} =
               Continuation.retry_checkpoint(c.store, original)

      assert {:ok, %{record: ^committed, replayed: true}} =
               Continuation.retry_checkpoint(c.store, original)

      assert File.read!(c.effects) == "A\n"
    end
  end

  for change <- [:model_ref, :policy, :schema, :root_policy] do
    test "post-approval #{change} mismatch preserves authorization boundary", c do
      ready = approve(c, pause(c))
      [a, b, last] = c.definition.steps

      b =
        case unquote(change) do
          :model_ref ->
            %{b | model_ref: %{"id" => "other", "version" => "1"}}

          :policy ->
            %{b | policy: %{"id" => "other", "version" => "1"}}

          :schema ->
            [tool] = b.agent.tools
            schema = Map.put(tool.parameters_json_schema, "additionalProperties", false)
            %{b | agent: %{b.agent | tools: [%{tool | parameters_json_schema: schema}]}}

          :root_policy ->
            b
        end

      # Rebuild a coherent current definition, rather than corrupting its cached
      # fingerprint and accidentally testing only self-consistency.
      assert {:ok, definition} =
               Composition.new(
                 id: c.definition.id,
                 version: c.definition.version,
                 steps: [a, b, last]
               )

      owner = self()

      config =
        Map.put(c.config, :on_writer, fn _ ->
          send(owner, :mismatch_owner)
          :ok
        end)

      config =
        if unquote(change) == :root_policy,
          do: Map.put(config, :policy, %{"id" => "other", "version" => "1"}),
          else: config

      drain_commands()

      assert {:error, %ExAgent.RunError{} = error} =
               resume(%{c | definition: definition}, ready, continuation: config)

      assert File.read!(c.effects) == "A\n"

      if unquote(change) == :schema do
        # Tool reflection runs after fresh claim, in Frame.restore_tools/3.
        assert error.reason == :continuation_tools_changed
        assert_receive {:journal_command, %{"operation" => "claim"}}
        assert_receive :mismatch_owner
        assert {:ok, claimed} = Store.load_record(c.store, :agent, "run")
        assert claimed["revision"] == ready["revision"] + 1
        assert claimed["execution"]["state"] == "claimed"
        assert claimed["execution"]["effects"] === ready["execution"]["effects"]

        assert claimed["execution"]["progress"]["approvals"] ===
                 ready["execution"]["progress"]["approvals"]
      else
        refute_receive {:journal_command, %{"operation" => "claim"}}, 0
        refute_receive :mismatch_owner, 0
        assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
        assert {:ok, %{status: :completed}} = resume(c, ready)
      end

      if unquote(change) == :schema, do: assert(File.read!(c.effects) == "A\n")
    end
  end

  for changed <- [false, true] do
    test "current Model continuation binding after approval changed=#{changed}", c do
      [a, b, last] = c.definition.steps

      model = %ExAgent.ContinuationBindingModel{
        script: b.agent.model.script,
        binding: %{"endpoint" => "original", "model" => "synthetic"},
        observer: self()
      }

      b = %{b | agent: %{b.agent | model: model}}
      c = %{c | definition: %{c.definition | steps: [a, b, last]}}
      ready = approve(c, pause(c))
      drain_binding_notifications()

      if unquote(changed) do
        current = %{model | binding: %{"endpoint" => "changed", "model" => "synthetic"}}
        b = %{b | agent: %{b.agent | model: current}}

        assert {:error, %ExAgent.RunError{reason: :continuation_model_binding_changed}} =
                 resume(%{c | definition: %{c.definition | steps: [a, b, last]}}, ready)

        assert_receive :binding_called
        assert {:ok, claimed} = Store.load_record(c.store, :agent, "run")
        assert claimed["revision"] == ready["revision"] + 1
        assert claimed["execution"]["effects"] === ready["execution"]["effects"]

        assert claimed["execution"]["progress"]["approvals"] ===
                 ready["execution"]["progress"]["approvals"]

        assert File.read!(c.effects) == "A\n"
      else
        assert {:ok, %{status: :completed, request_count: 5, tool_calls: 3}} = resume(c, ready)
        assert_receive :binding_called
        assert File.read!(c.effects) |> String.ends_with?("C\n")
      end
    end
  end

  defp drain_binding_notifications do
    receive do
      :binding_called -> drain_binding_notifications()
    after
      0 -> :ok
    end
  end

  for boundary <- [:approved_tools, :next_model], bound <- [:budget, :lease, :timely] do
    @tag approval_boundary: boundary, approval_bound: bound
    test "approved resume observability #{boundary} #{bound} uses original attempt reservation",
         c do
      [a, b, last] = c.definition.steps

      b = %{
        b
        | agent: %{b.agent | model: %ObservedModel{owner: self(), script: b.agent.model.script}}
      }

      c = %{c | definition: %{c.definition | steps: [a, b, last]}}
      ready = approve(c, pause(c))
      assert_receive {:approved_model_io, _}
      refute_receive {:approved_model_io, _}, 0
      owner = self()
      boundary = c.approval_boundary
      bound = c.approval_bound

      gate =
        start_supervised!({Agent, fn -> if boundary == :approved_tools, do: 2, else: 1 end},
          id: :obs_gate
        )

      limit = if bound == :timely, do: 5000, else: 700

      config =
        if bound == :lease,
          do: Map.put(c.config, :lease_ms, limit),
          else: Map.put(c.config, :active_time_limit_ms, limit)

      obs =
        ExAgent.Observability.OpenTelemetry.new(
          content: true,
          redact: fn field, value ->
            hit =
              field == :input and
                case boundary do
                  :approved_tools -> is_map(value) and value["label"] in ["B1", "B2"]
                  :next_model -> is_list(value)
                end

            hold = hit and Agent.get_and_update(gate, fn n -> {n > 0, max(n - 1, 0)} end)

            if hold do
              send(owner, {:approved_observability, self(), System.monotonic_time(:millisecond)})

              receive do
                :release_observability -> :ok
              end
            end

            :drop
          end
        )

      task =
        Task.async(fn ->
          resume(c, ready,
            continuation: config,
            observability: obs
          )
        end)

      held =
        for _ <- 1..if(boundary == :approved_tools, do: 2, else: 1) do
          assert_receive {:approved_observability, pid, entered}, 5000
          {pid, entered}
        end

      assert {:ok, at_callback} = Store.load_record(c.store, :agent, "run")
      assert at_callback["execution"]["attempt_id"] != ready["execution"]["attempt_id"]

      assert at_callback["execution"]["progress"]["approvals"] ===
               ready["execution"]["progress"]["approvals"]

      refute_receive {:approved_model_io, _}, 0

      if bound != :lease do
        assert at_callback["execution"]["progress"]["active_budget"]["reserved_ms"] == limit
        assert at_callback["execution"]["progress"]["active_budget"]["remaining_ms"] == 0
      end

      before_effects = File.read!(c.effects)
      refute before_effects =~ "C\n"
      if boundary == :approved_tools, do: assert(before_effects == "A\n")

      wait =
        cond do
          bound == :timely ->
            50

          bound == :lease ->
            max(at_callback["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

          true ->
            max(
              Enum.max(Enum.map(held, &elem(&1, 1))) + limit - System.monotonic_time(:millisecond) +
                1,
              0
            )
        end

      receive do
      after
        wait -> :ok
      end

      Enum.each(held, fn {pid, _} -> send(pid, :release_observability) end)
      result = Task.await(task, 5000)

      if bound == :timely do
        assert {:ok, %{status: :completed, request_count: 5, tool_calls: 3}} = result
        assert_receive {:approved_model_io, timeout}
        assert timeout > 0 and timeout < limit
        refute_receive {:approved_model_io, _}, 0
        assert {:ok, final} = Store.load_record(c.store, :agent, "run")
        budget = final["execution"]["progress"]["active_budget"]
        assert budget["remaining_ms"] > 0 and budget["remaining_ms"] < limit
        assert budget["reserved_ms"] == nil
        assert ["A", b1, b2, "C"] = String.split(File.read!(c.effects), "\n", trim: true)
        assert Enum.sort([b1, b2]) == ["B1", "B2"]
      else
        assert {:error, %ExAgent.RunError{}} = result
        refute_receive {:approved_model_io, _}, 0
        assert File.read!(c.effects) == before_effects
        assert {:ok, after_callback} = Store.load_record(c.store, :agent, "run")

        assert after_callback["execution"]["progress"]["active_budget"] ===
                 at_callback["execution"]["progress"]["active_budget"]

        assert after_callback["execution"]["effects"] === at_callback["execution"]["effects"]
      end
    end
  end

  test "public pause, two decisions and fresh VM resume B then C", c do
    assert {:ok, paused} =
             ExAgent.LegacyStructuralFixture.run(
               c.definition,
               "input",
               [continuation: c.config] ++ F.options()
             )

    assert paused.status == :paused
    assert paused.output == nil
    assert paused.continuation_checkpoint == nil
    assert paused.error_step_id == nil
    assert paused.error_phase == nil
    assert Enum.map(paused.steps, & &1.status) == [:completed, :paused, :not_started]
    assert File.read!(c.effects) == "A\n"
    assert {:ok, %{status: :pending, record: pending}} = Continuation.get(c.store, "run")
    assert pending["revision"] == paused.continuation.revision
    assert :ok = Record.validate(pending, {"sequence-approval", :agent, "run"})
    approvals = pending["execution"]["progress"]["approvals"]
    assert map_size(approvals) == 2
    [first, second] = Map.keys(approvals)
    assert {:ok, %{record: partial}} = F.decide(c.store, pending, first)
    assert partial["execution"]["state"] == "pending"
    assert {:ok, %{record: ready}} = F.decide(c.store, partial, second)
    assert ready["execution"]["state"] == "ready"

    assert ready["execution"]["progress"]["runtime"] ===
             pending["execution"]["progress"]["runtime"]

    assert ready["snapshot"] === pending["snapshot"]
    assert File.read!(c.effects) == "A\n"
    path = c.effects <> ".json"
    File.write!(path, Jason.encode!(ready))
    on_exit(fn -> File.rm(path) end)
    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++
        ["test/support/sequence_approval_vm.exs", path, c.effects]

    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "SEQUENCE_APPROVAL_VM"
    assert ["A", b1, b2, "C"] = String.split(File.read!(c.effects), "\n", trim: true)
    assert Enum.sort([b1, b2]) == ["B1", "B2"]
  end
end
