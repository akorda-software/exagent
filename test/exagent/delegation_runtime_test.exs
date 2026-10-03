defmodule ExAgent.DelegationRuntimeTest do
  use ExUnit.Case, async: false
  alias ExAgent.Coordination.Composition
  alias ExAgent.Continuation.Record
  alias ExAgent.{Store, Tool}
  alias ExAgent.Message.Part.ToolCall

  defp ref(id), do: %{"id" => id, "version" => "1"}

  defp codec,
    do: %{
      dump: fn m -> {:ok, %{"index" => m.index}} end,
      load: fn m, data -> {:ok, %{m | index: data["index"]}} end
    }

  defp effect(owner, label) do
    Tool.new(
      name: "effect",
      takes_ctx: false,
      parameters_json_schema: %{"type" => "object"},
      call: fn _ ->
        send(owner, {:effect, label, self()})
        {:ok, label <> " raw"}
      end
    )
  end

  defp call(name, id, args \\ %{}), do: %ToolCall{tool_name: name, tool_call_id: id, args: args}

  defp agent(script, tools, payload_limit \\ 65_536),
    # A bounded durable slot must reserve its four JSON projections inside 8 MiB.
    # The ordinary 1 MiB payload default cannot fit even one worst-case call.
    do:
      ExAgent.new(
        model: %ExAgent.Models.Test{script: script},
        tools: tools,
        max_payload_bytes: payload_limit
      )

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

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    store = Store.scoped({Store.ETS, __MODULE__}, "delegation-runtime")

    config = %{
      store: store,
      id: "run",
      policy: ref("policy"),
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 600_000
    }

    %{store: store, config: config}
  end

  test "real loop A effect → B sibling/delegate D → C, one journal and no builder", c do
    owner = self()
    d = agent([{:tool_calls, [call("effect", "d")]}, "D final"], [effect(owner, "D")])

    descriptor = %{
      definition: ref("D"),
      policy: ref("policy"),
      model_ref: ref("model"),
      model_codec: codec()
    }

    delegate =
      ExAgent.Coordination.delegation_tool(fn _, _ -> raise "durable builder must not run" end,
        name: "delegate",
        prompt_arg: "task",
        continuation: descriptor
      )

    a = agent([{:tool_calls, [call("effect", "a")]}, "A final"], [effect(owner, "A")])

    b =
      agent(
        [
          {:tool_calls,
           [
             call("effect", "b"),
             call("delegate", "delegate", %{"task" => "D input", "prompt" => "wrong"})
           ]},
          "B final"
        ],
        [effect(owner, "B"), delegate]
      )

    last = agent(["C final"], [])

    {:ok, definition} =
      Composition.new(
        id: "real-delegation",
        version: "1",
        steps: [step("A", a), step("B", b), step("C", last)]
      )

    catalog = [
      %{
        definition: ref("D"),
        policy: ref("policy"),
        model_ref: ref("model"),
        load: fn _, args ->
          send(owner, {:loaded, args})
          {:ok, d, [], %{model_codec: codec()}}
        end
      }
    ]

    assert {:ok, result} =
             Composition.run(definition, "root input",
               continuation: c.config,
               delegate_definitions: catalog
             )

    assert result.status == :completed and result.output == "C final"
    assert result.request_count == 7 and result.tool_calls == 4
    assert Enum.map(result.steps, & &1.input) == ["root input", "A final", "B final"]
    for label <- ~w(A B D), do: assert_receive({:effect, ^label, _pid})
    assert_receive {:loaded, %{"task" => "D input", "prompt" => "wrong"}}
    refute_receive {:effect, _, _}
    assert {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})
    root = record["execution"]["progress"]["runtime"]
    assert root["frame_version"] == 10 and root["input"] == "root input"
    assert map_size(root["children"]) == 4

    assert Enum.count(record["execution"]["effects"], fn {_, e} ->
             e["intent"]["kind"] == "tool"
           end) == 3

    assert Enum.all?(root["tool_batches"], fn {_, b} -> not is_nil(b["consumption"]) end)

    # Terminal projection must not require the delegated host or reload any codec.
    closed_steps =
      Enum.map(definition.steps, fn step ->
        %{
          step
          | model_codec: %{
              dump: fn _ -> flunk("terminal dump") end,
              load: fn _, _ -> flunk("terminal load") end
            }
        }
      end)

    assert {:ok, projected} =
             Composition.resume(%{definition | steps: closed_steps}, result.continuation,
               continuation: c.config
             )

    assert projected.status == :completed and projected.output == "C final"
    assert projected.request_count == 7 and projected.tool_calls == 4
    refute_receive {:effect, _, _}
    refute_receive {:loaded, _}

    assert {:ok, ^record} = Store.load_record(c.store, :agent, "run")
  end

  defmodule Workers do
    use ExAgent.Capability
    defstruct [:owner]

    def before_tool_execute(%{owner: owner}, ctx, call) do
      send(owner, {:worker, ctx.run_id, call.tool_call_id, self()})
      call
    end
  end

  test "mixed nested asks drain their siblings and real workers before root pause ACK", c do
    owner = self()
    free = effect(owner, "D")

    ask = %{
      free
      | name: "ask",
        call: fn _ ->
          send(owner, {:ask_effect, self()})
          {:ok, "approved"}
        end
    }

    d =
      agent(
        [
          {:tool_calls, [call("effect", "d"), call("ask", "ask1"), call("ask", "ask2")]},
          "D final"
        ],
        [free, ask],
        16_384
      )

    d = %{d | capabilities: [%Workers{owner: owner}]}

    descriptor = %{
      definition: ref("D"),
      policy: ref("policy"),
      model_ref: ref("model"),
      model_codec: codec()
    }

    delegate =
      ExAgent.Coordination.delegation_tool(fn _, _ -> flunk("builder") end,
        name: "delegate",
        prompt_arg: "task",
        continuation: descriptor
      )

    a = agent([{:tool_calls, [call("effect", "a")]}, "A final"], [effect(owner, "A")])

    b =
      agent(
        [
          {:tool_calls,
           [call("effect", "b"), call("delegate", "delegate", %{"task" => "D input"})]},
          "B final"
        ],
        [effect(owner, "B"), delegate],
        16_384
      )

    b = %{b | capabilities: [%Workers{owner: owner}]}

    {:ok, definition} =
      Composition.new(
        id: "mixed-delegation",
        version: "1",
        steps: [step("A", a), step("B", b), step("C", agent(["C final"], []))]
      )

    catalog = [
      %{
        definition: ref("D"),
        policy: ref("policy"),
        model_ref: ref("model"),
        load: fn _, _ ->
          {:ok, d,
           [
             permissions: ExAgent.Permissions.new!(default: :allow, rules: [{"ask", :ask}]),
             on_event: fn
               %{type: :run_failed, data: %{reason: reason}} ->
                 send(owner, {:child_failed, reason})

               _ ->
                 :ok
             end
           ], %{model_codec: codec()}}
        end
      }
    ]

    outcome =
      Composition.run(definition, "root input",
        continuation: c.config,
        delegate_definitions: catalog
      )

    refute_receive {:child_failed, _}
    assert {:ok, result} = outcome

    assert result.status == :paused and result.output == nil
    assert result.request_count == 4 and result.tool_calls == 6
    assert Enum.map(result.steps, & &1.status) == [:completed, :paused, :not_started]
    for label <- ~w(A B D), do: assert_receive({:effect, ^label, _})

    for _ <- 1..5 do
      assert_receive {:worker, _, _, pid}
      refute Process.alive?(pid)
    end

    refute_receive {:effect, _, _}
    assert {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})
    assert result.continuation.revision == record["revision"]
    root = record["execution"]["progress"]["runtime"]
    assert root["frontier"]["state"] == "quiescent"
    assert Enum.count(root["children"], fn {_, n} -> n["status"] == "suspended" end) == 2
    assert map_size(record["execution"]["progress"]["approvals"]) == 2

    assert Enum.count(record["execution"]["effects"], fn {_, e} ->
             e["intent"]["kind"] == "tool"
           end) == 3

    assert is_nil(record["execution"]["progress"]["active_budget"]["reserved_ms"])
    refute_receive {:ask_effect, _}

    approved =
      Enum.reduce(Map.keys(record["execution"]["progress"]["approvals"]), record, fn id, r ->
        assert {:ok, %{record: next}} = ExAgent.SequenceApprovalFixture.decide(c.store, r, id)
        next
      end)

    refute_receive {:ask_effect, _}

    assert {:ok, resumed} =
             Composition.resume(definition, ExAgent.SequenceApprovalFixture.reference(approved),
               continuation: c.config,
               delegate_definitions: catalog
             )

    assert resumed.status == :completed and resumed.output == "C final"
    assert resumed.request_count == 7 and resumed.tool_calls == 6

    for _ <- 1..2 do
      assert_receive {:ask_effect, pid}
      refute Process.alive?(pid)
    end

    refute_receive {:ask_effect, _}
    refute_receive {:effect, _, _}
    refute_receive {:worker, _, _, _}
    refute_receive {:child_failed, _}
    assert {:ok, completed} = Store.load_record(c.store, :agent, "run")
    assert :ok = Record.validate(completed, {c.store.namespace, :agent, "run"})
    assert completed["execution"]["state"] == "completed"
  end

  @tag :tmp_dir
  test "two decisions, fresh VM child completion, crash before wrapper and explicit recovery",
       c do
    alias ExAgent.DelegationRuntimeFixture, as: F

    dir =
      Path.join(
        c.tmp_dir,
        "delegation-vm-" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "record.json")
    effects = Path.join(dir, "effects.txt")
    on_exit(fn -> File.rm_rf!(dir) end)
    {definition, catalog} = F.host(effects)

    assert {:ok, paused} =
             Composition.run(definition, "root input",
               continuation: c.config,
               delegate_definitions: catalog
             )

    assert paused.status == :paused
    assert {:ok, record} = Store.load_record(c.store, :agent, "run")

    approved =
      Enum.reduce(Map.keys(record["execution"]["progress"]["approvals"]), record, fn id, r ->
        assert {:ok, %{record: next}} = ExAgent.SequenceApprovalFixture.decide(c.store, r, id)
        next
      end)

    File.write!(path, Jason.encode!(approved))
    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++
        ["test/support/delegation_runtime_vm.exs", path, effects]

    assert {:error, %ExAgent.RunError{reason: :continuation_delegation_definition_missing}} =
             Composition.resume(definition, ExAgent.SequenceApprovalFixture.reference(approved),
               continuation: c.config
             )

    assert {:ok, ^approved} = Store.load_record(c.store, :agent, "run")

    {output, status} =
      System.cmd(System.find_executable("elixir"), args ++ ["crash"], stderr_to_stdout: true)

    assert status == 71, output
    crashed = Jason.decode!(File.read!(path))
    assert :ok = Record.validate(crashed, {c.store.namespace, :agent, "run"})
    assert crashed["execution"]["state"] == "claimed"
    root = crashed["execution"]["progress"]["runtime"]

    assert Enum.any?(root["children"], fn {_, n} ->
             n["link"]["kind"] == "delegate" and n["status"] == "completed"
           end)

    assert Enum.any?(root["tool_batches"], fn {_, b} ->
             is_map(b["calls"]["delegate"]) and b["calls"]["delegate"]["state"] == "child" and
               not is_nil(b["calls"]["delegate"]["raw"])
           end)

    assert not Record.unresolved?(crashed["execution"])
    refute "after:delegate" in String.split(File.read!(effects), "\n", trim: true)

    {output, status} =
      System.cmd(System.find_executable("elixir"), args ++ ["recover"], stderr_to_stdout: true)

    assert status == 0, output
    assert output =~ "DELEGATION_VM completed"
    lines = String.split(File.read!(effects), "\n", trim: true)

    assert Enum.sort(lines) ==
             Enum.sort(
               ~w(A B D C ASK:ask1 ASK:ask2 before:a before:b before:d before:delegate before:ask1 before:ask2 after:a after:b after:d after:delegate after:ask1 after:ask2)
             )
  end

  @tag :tmp_dir
  test "wrapper admission ACK without settlement stays uncertain in a fresh VM", c do
    alias ExAgent.DelegationRuntimeFixture, as: F

    dir =
      Path.join(
        c.tmp_dir,
        "delegation-uncertain-" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(dir)
    path = Path.join(dir, "record.json")
    effects = Path.join(dir, "effects.txt")
    on_exit(fn -> File.rm_rf!(dir) end)
    {definition, catalog} = F.host(effects)

    assert {:ok, %{status: :paused}} =
             Composition.run(definition, "root input",
               continuation: c.config,
               delegate_definitions: catalog
             )

    assert {:ok, pending} = Store.load_record(c.store, :agent, "run")

    approved =
      Enum.reduce(Map.keys(pending["execution"]["progress"]["approvals"]), pending, fn id, r ->
        assert {:ok, %{record: next}} = ExAgent.SequenceApprovalFixture.decide(c.store, r, id)
        next
      end)

    File.write!(path, Jason.encode!(approved))
    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++
        ["test/support/delegation_runtime_vm.exs", path, effects]

    {output, status} =
      System.cmd(System.find_executable("elixir"), args ++ ["wrapping"], stderr_to_stdout: true)

    assert status == 72, output
    wrapping = Jason.decode!(File.read!(path))
    assert Record.unresolved?(wrapping["execution"])
    previous = File.read!(effects)

    {output, status} =
      System.cmd(System.find_executable("elixir"), args ++ ["uncertain"], stderr_to_stdout: true)

    assert status == 0, output
    assert output =~ "DELEGATION_VM uncertain"
    assert File.read!(effects) == previous
  end
end
