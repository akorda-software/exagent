defmodule ExAgent.DelegationRuntimeMatrixTest do
  use ExUnit.Case, async: false
  alias ExAgent.Coordination.Composition
  alias ExAgent.Continuation.Record
  alias ExAgent.Message.Part.ToolCall
  alias ExAgent.{Continuation, RunError, Store, Tool}

  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, namespace, query), do: Store.ETS.scan_records(c.table, namespace, query)

    def transition(c, key, revision, command) do
      mode =
        Agent.get_and_update(c.fault, fn
          {operation, mode} = fault ->
            if command["operation"] == operation and
                 (operation not in ["begin_effect", "outcome"] or
                    not is_nil(command["payload"]["call_id"])),
               do: {mode, nil},
               else: {nil, fault}

          nil ->
            {nil, nil}
        end)

      reply =
        if mode == :before,
          do: {:error, :before_commit},
          else: Store.ETS.transition(c.table, key, revision, command)

      if mode == :after, do: {:error, :lost_ack}, else: reply
    end
  end

  defmodule Wrapper do
    use ExAgent.Capability
    defstruct [:owner]

    def after_tool_execute(%{owner: owner}, _, _, result) do
      send(owner, :wrapped)
      result
    end
  end

  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp codec,
    do: %{
      dump: fn m -> {:ok, %{"index" => m.index}} end,
      load: fn m, data -> {:ok, %{m | index: data["index"]}} end
    }

  defp step(id, agent),
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

  defp paused(c) do
    dir = Path.join("/tmp/opencode", "delegation-matrix-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    effects = Path.join(dir, "effects.txt")
    {definition, catalog} = ExAgent.DelegationRuntimeFixture.host(effects)

    assert {:ok, %{status: :paused}} =
             Composition.run(definition, "input",
               continuation: c.config,
               delegate_definitions: catalog
             )

    {:ok, record} = Store.load_record(c.store, :agent, "run")
    {definition, catalog, effects, record}
  end

  defp approve(c, record) do
    Enum.reduce(Map.keys(record["execution"]["progress"]["approvals"]), record, fn id, r ->
      if r["execution"]["progress"]["approvals"][id]["decision"] do
        r
      else
        {:ok, %{record: next}} = ExAgent.SequenceApprovalFixture.decide(c.store, r, id)
        next
      end
    end)
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    store = Store.scoped({Store.ETS, __MODULE__}, "delegation-matrix")

    config = %{
      store: store,
      id: "run",
      policy: ref("policy"),
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000
    }

    %{store: store, config: config}
  end

  for operation <- ~w(begin_effect call_settle), mode <- [:before, :after] do
    @tag operation: operation, mode: mode
    test "#{operation} #{mode}: exact checkpoint retry never dispatches or replays callbacks",
         c do
      owner = self()
      fault = start_supervised!({Agent, fn -> {c.operation, c.mode} end})
      store = Store.scoped({FaultStore, %{table: __MODULE__, fault: fault}}, c.store.namespace)

      tool =
        Tool.new(
          name: "effect",
          takes_ctx: false,
          call: fn _ ->
            send(owner, :effect)
            {:ok, "done"}
          end
        )

      agent =
        ExAgent.new(
          tools: [tool],
          capabilities: [%Wrapper{owner: owner}],
          model: %ExAgent.Models.Test{
            script: [
              {:tool_calls, [call("effect", "one")]},
              fn _, _ ->
                send(owner, :forbidden_next_model)
                "done"
              end
            ]
          }
        )

      {:ok, definition} = Composition.new(id: "ack", version: "1", steps: [step("A", agent)])

      assert {:error, %RunError{partial: partial}} =
               Composition.run(definition, "input", continuation: %{c.config | store: store})

      token = partial.continuation_checkpoint
      assert partial.error_phase == :checkpoint and token["command"]["operation"] == c.operation

      if c.operation == "call_settle" do
        assert_receive :effect
        assert_receive :wrapped
      else
        refute_receive :effect
        refute_receive :wrapped
      end

      refute_receive :forbidden_next_model
      assert {:ok, %{record: retried}} = Continuation.retry_checkpoint(store, token)

      assert {:ok, %{record: ^retried, replayed: true}} =
               Continuation.retry_checkpoint(store, token)

      assert :ok = Record.validate(retried, {c.store.namespace, :agent, "run"})
      assert retried["execution"]["state"] == "claimed"
      refute_receive :effect
      refute_receive :wrapped
      refute_receive :forbidden_next_model

      assert {:error, %RunError{}} =
               Composition.resume(definition, ExAgent.SequenceApprovalFixture.reference(retried),
                 continuation: %{c.config | store: store}
               )

      assert {:ok, ^retried} = Store.load_record(store, :agent, "run")
    end
  end

  test "two independent delegates complete once, including a typed child", c do
    owner = self()

    typed =
      ExAgent.new(
        output: ExAgent.ContinuationNativeFixture.CountOutput,
        model: %ExAgent.Models.Test{
          script: [{:tool_calls, [call("final_result", "final", %{"count" => 7})]}]
        }
      )

    text = ExAgent.new(model: %ExAgent.Models.Test{script: ["E result"]})

    tools =
      for name <- ~w(D E) do
        ExAgent.Coordination.delegation_tool(fn _, _ -> flunk("durable builder") end,
          name: name,
          prompt_arg: "task",
          continuation: %{
            definition: ref(name),
            policy: ref("policy"),
            model_ref: ref("model"),
            model_codec: codec()
          }
        )
      end

    agent =
      ExAgent.new(
        tools: tools,
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls,
             [call("D", "one", %{"task" => "typed"}), call("E", "two", %{"task" => "text"})]},
            "parent done"
          ]
        }
      )

    catalog =
      for {name, child} <- [{"D", typed}, {"E", text}] do
        %{
          definition: ref(name),
          policy: ref("policy"),
          model_ref: ref("model"),
          load: fn _, _ ->
            send(owner, {:load, name})
            {:ok, child, [], %{model_codec: codec()}}
          end
        }
      end

    {:ok, definition} = Composition.new(id: "multiple", version: "1", steps: [step("A", agent)])

    assert {:ok, %{status: :completed, output: "parent done"} = result} =
             Composition.run(definition, "input",
               continuation: c.config,
               delegate_definitions: catalog
             )

    assert result.request_count == 4 and result.tool_calls == 2
    for name <- ~w(D E), do: assert_receive({:load, ^name})
    refute_receive {:load, _}
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    root = record["execution"]["progress"]["runtime"]
    assert map_size(root["children"]) == 3
    assert Enum.any?(root["children"], fn {_, child} -> child["result"] == %{"count" => 7} end)
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})

    assert {:ok, ^result} =
             Composition.resume(definition, result.continuation, continuation: c.config)

    refute_receive {:load, _}
  end

  test "partial decisions and mismatched catalog references reject without callback or claim",
       c do
    {definition, catalog, effects, record} = paused(c)
    before = File.read!(effects)
    [id | _] = Map.keys(record["execution"]["progress"]["approvals"])
    {:ok, %{record: partial}} = ExAgent.SequenceApprovalFixture.decide(c.store, record, id)

    assert {:error, %RunError{reason: :unsupported_composition_boundary}} =
             Composition.resume(definition, ExAgent.SequenceApprovalFixture.reference(partial),
               continuation: c.config,
               delegate_definitions: catalog
             )

    assert {:ok, ^partial} = Store.load_record(c.store, :agent, "run")
    ready = approve(c, partial)

    bad =
      Enum.map(
        catalog,
        &%{
          &1
          | model_ref: ref("different-model"),
            load: fn _, _ -> flunk("mismatched loader") end
        }
      )

    assert {:error, %RunError{reason: :continuation_delegation_definition_missing}} =
             Composition.resume(definition, ExAgent.SequenceApprovalFixture.reference(ready),
               continuation: c.config,
               delegate_definitions: bad
             )

    assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
    assert File.read!(effects) == before
  end

  test "two real resumers produce one CAS winner and execute the approved suffix once", c do
    {definition, catalog, effects, record} = paused(c)
    ready = approve(c, record)
    owner = self()

    catalog =
      Enum.map(catalog, fn entry ->
        %{
          entry
          | load: fn ctx, args ->
              send(owner, :loaded_child)
              entry.load.(ctx, args)
            end
        }
      end)

    config =
      Map.put(c.config, :on_writer, fn writer ->
        send(owner, {:winner_writer, writer})
        :ok
      end)

    tasks =
      for _ <- 1..2,
          do:
            Task.async(fn ->
              Composition.resume(definition, ExAgent.SequenceApprovalFixture.reference(ready),
                continuation: config,
                delegate_definitions: catalog
              )
            end)

    outcomes = Enum.map(tasks, &Task.await(&1, 30_000))
    assert Enum.count(outcomes, &match?({:ok, %{status: :completed}}, &1)) == 1
    assert Enum.count(outcomes, &match?({:error, %RunError{}}, &1)) == 1
    assert_receive :loaded_child
    refute_receive :loaded_child
    assert_receive {:winner_writer, writer}
    refute Process.alive?(writer)
    refute_receive {:winner_writer, _}
    lines = String.split(File.read!(effects), "\n", trim: true)

    for label <- ["A", "B", "D", "ASK:ask1", "ASK:ask2", "after:delegate", "C"],
        do: assert(Enum.count(lines, &(&1 == label)) == 1)

    {:ok, completed} = Store.load_record(c.store, :agent, "run")
    assert :ok = Record.validate(completed, {c.store.namespace, :agent, "run"})
  end

  test "current deadline and deny policy constrain approved nested calls", c do
    {definition, catalog, effects, record} = paused(c)
    ready = approve(c, record)
    before = File.read!(effects)

    assert {:error, %RunError{}} =
             Composition.resume(definition, ExAgent.SequenceApprovalFixture.reference(ready),
               continuation: c.config,
               delegate_definitions: catalog,
               root_options: [deadline: System.monotonic_time(:millisecond) - 1]
             )

    assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
    assert File.read!(effects) == before

    result =
      Composition.resume(definition, ExAgent.SequenceApprovalFixture.reference(ready),
        continuation: c.config,
        delegate_definitions: catalog,
        root_options: [
          permissions: ExAgent.Permissions.new!(default: :allow, rules: [{"ask", :deny}])
        ]
      )

    assert {:ok, %{status: :completed}} = result
    lines = String.split(File.read!(effects), "\n", trim: true)
    refute "ASK:ask1" in lines or "ASK:ask2" in lines
    {:ok, denied} = Store.load_record(c.store, :agent, "run")
    assert :ok = Record.validate(denied, {c.store.namespace, :agent, "run"})
  end

  test "a smaller current slot rejects confirmed delegated raw before wrapping", c do
    owner = self()
    output = String.duplicate("x", 8_192)
    ask = Tool.new(name: "ask", takes_ctx: false, call: fn _ -> {:ok, "approved"} end)

    child =
      ExAgent.new(
        tools: [ask],
        model: %ExAgent.Models.Test{
          script: [{:tool_calls, [call("ask", "ask")]}, output]
        }
      )

    delegate =
      ExAgent.Coordination.delegation_tool(fn _, _ -> flunk("builder") end,
        name: "delegate",
        prompt_arg: "task",
        continuation: %{
          definition: ref("D"),
          policy: ref("policy"),
          model_ref: ref("model"),
          model_codec: codec()
        }
      )

    parent =
      ExAgent.new(
        tools: [delegate],
        capabilities: [%Wrapper{owner: owner}],
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls, [call("delegate", "one", %{"task" => "input"})]},
            fn _, _ ->
              send(owner, :forbidden_model)
              "parent"
            end
          ]
        }
      )

    catalog = [
      %{
        definition: ref("D"),
        policy: ref("policy"),
        model_ref: ref("model"),
        load: fn _, _ ->
          {:ok, child,
           [permissions: ExAgent.Permissions.new!(default: :allow, rules: [{"ask", :ask}])],
           %{model_codec: codec()}}
        end
      }
    ]

    {:ok, definition} =
      Composition.new(id: "current-slot", version: "1", steps: [step("B", parent)])

    assert {:ok, %{status: :paused}} =
             Composition.run(definition, "input",
               continuation: c.config,
               delegate_definitions: catalog
             )

    {:ok, paused} = Store.load_record(c.store, :agent, "run")
    ready = approve(c, paused)

    assert {:error, %RunError{partial: partial}} =
             Composition.resume(
               definition,
               ExAgent.SequenceApprovalFixture.reference(ready),
               continuation: c.config,
               delegate_definitions: catalog,
               step_options: %{"B" => [max_payload_bytes: 4_096]}
             )

    refute_receive :wrapped
    refute_receive :forbidden_model
    assert partial.request_count == 3 and partial.tool_calls == 2
    assert_current_slot_failure(c, output)
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    children = record["execution"]["progress"]["runtime"]["children"]

    assert Enum.any?(children, fn {_, n} ->
             n["link"]["kind"] == "delegate" and
               n["status"] == "completed" and n["result"] == output
           end)
  end

  test "explicit recovery retains ordinary raw and applies the smaller current slot before wrapping",
       c do
    owner = self()
    output = String.duplicate("x", 8_192)
    fault = start_supervised!({Agent, fn -> {"outcome", :after} end})
    store = Store.scoped({FaultStore, %{table: __MODULE__, fault: fault}}, c.store.namespace)
    config = %{c.config | store: store, lease_ms: 5_000}

    tool =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        call: fn _ ->
          send(owner, :effect)
          {:ok, output, %ExAgent.Message.Usage{input_tokens: 1, output_tokens: 2}}
        end
      )

    agent =
      ExAgent.new(
        tools: [tool],
        capabilities: [%Wrapper{owner: owner}],
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls, [call("effect", "one")]},
            fn _, _ ->
              send(owner, :forbidden_model)
              "parent"
            end
          ]
        }
      )

    {:ok, definition} =
      Composition.new(id: "recover-slot", version: "1", steps: [step("B", agent)])

    assert {:error, %RunError{partial: partial}} =
             Composition.run(definition, "input", continuation: config)

    assert_receive :effect
    refute_receive :wrapped

    assert {:ok, %{record: acknowledged}} =
             Continuation.retry_checkpoint(store, partial.continuation_checkpoint)

    Process.sleep(
      max(acknowledged["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)
    )

    assert {:ok, %{record: ready}} =
             Continuation.recover(store, "run",
               record_id: acknowledged["record_id"],
               revision: acknowledged["revision"],
               operation_id: "recover",
               actor: "host",
               authorize: fn a, _, _ -> {:ok, a} end
             )

    assert ready["execution"]["state"] == "ready"

    assert {:error, %RunError{partial: result}} =
             Composition.resume(
               definition,
               ExAgent.SequenceApprovalFixture.reference(ready),
               continuation: config,
               step_options: %{"B" => [max_payload_bytes: 4_096]}
             )

    assert result.request_count == 1 and result.tool_calls == 1
    refute_receive :effect
    refute_receive :wrapped
    refute_receive :forbidden_model
    assert_current_slot_failure(%{c | store: store}, output)
    {:ok, record} = Store.load_record(store, :agent, "run")
    operations = record["execution"]["progress"]["runtime"]["scope"]["operations"]
    assert Enum.count(operations, fn op -> hd(op["id"]) == "tool" end) == 1
  end

  defp assert_current_slot_failure(c, output) do
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["state"] == "failed"
    root = record["execution"]["progress"]["runtime"]
    batch = Enum.find(Map.values(root["tool_batches"]), &Map.has_key?(&1["calls"], "one"))
    phase = batch["calls"]["one"]
    {:ok, [raw]} = ExAgent.Message.from_json(phase["raw"]["result"])
    assert hd(raw.parts).content == output
    {:ok, [final]} = ExAgent.Message.from_json(phase["result"])
    assert hd(final.parts).content == nil
    assert hd(final.parts).payload_omitted["limit"] == 4_096
    assert phase["control"]["error"]["code"] == "retention_limit_exceeded"
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})
    assert {:ok, %{record: ^record}} = Continuation.get(c.store, "run")
  end

  for typed <- [false, true] do
    @tag typed: typed
    test "oversized confirmed delegated result typed=#{typed} fails canonically before the parent wrapper",
         c do
      owner = self()

      child =
        if c.typed do
          ExAgent.new(
            output: ExAgent.DelegationRuntimeFixture.LargeOutput,
            model: %ExAgent.Models.Test{
              script: [
                {:tool_calls,
                 [call("final_result", "final", %{"value" => String.duplicate("x", 70_000)})]}
              ]
            }
          )
        else
          ExAgent.new(model: %ExAgent.Models.Test{script: [String.duplicate("x", 70_000)]})
        end

      descriptor = %{
        definition: ref("D"),
        policy: ref("policy"),
        model_ref: ref("model"),
        model_codec: codec()
      }

      tool =
        ExAgent.Coordination.delegation_tool(fn _, _ -> flunk("builder") end,
          name: "delegate",
          prompt_arg: "task",
          continuation: descriptor
        )

      agent =
        ExAgent.new(
          tools: [tool],
          capabilities: [%Wrapper{owner: owner}],
          model: %ExAgent.Models.Test{
            script: [
              {:tool_calls, [call("delegate", "one", %{"task" => "input"})]},
              fn _, _ ->
                send(owner, :forbidden_model)
                "parent"
              end
            ]
          }
        )

      catalog = [
        %{
          definition: ref("D"),
          policy: ref("policy"),
          model_ref: ref("model"),
          load: fn _, _ ->
            {:ok, child, [], %{model_codec: codec()}}
          end
        }
      ]

      {:ok, definition} =
        Composition.new(id: "retained-child", version: "1", steps: [step("A", agent)])

      assert {:error, %RunError{}} =
               Composition.run(definition, "input",
                 continuation: c.config,
                 delegate_definitions: catalog
               )

      refute_receive :wrapped
      refute_receive :forbidden_model
      {:ok, record} = Store.load_record(c.store, :agent, "run")
      assert record["execution"]["state"] == "failed"
      root = record["execution"]["progress"]["runtime"]

      child =
        Enum.find_value(root["children"], fn {_, child} ->
          if child["link"]["kind"] == "delegate", do: child
        end)

      assert child["status"] == "failed" and child["error"]["code"] == "retention_limit_exceeded"
      assert child["error"]["omitted"]["limit"] == 65_536
      assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})
      assert {:ok, %{record: ^record}} = Continuation.get(c.store, "run")
      child_id = child["frame"]["run_id"]

      corrupted =
        put_in(
          record,
          ["execution", "progress", "runtime", "children", child_id, "error", "omitted", "bytes"],
          1
        )

      assert {:error, _} = Record.validate(corrupted, {c.store.namespace, :agent, "run"})
    end
  end
end
