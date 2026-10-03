defmodule ExAgent.SequenceActiveEvidenceTest do
  # This suite checks the historical frame-9 journal/receipt contract. Its fresh
  # sources are authentic CAS/codec-checked 9 records, resumed by the public API.
  # Producer-10 mixed C7, ACK, counters and delegation are tested independently.
  use ExUnit.Case, async: false
  @moduletag :tmp_dir
  alias ExAgent.{Continuation, Store, SequenceApprovalFixture}
  alias ExAgent.SequenceActiveEvidenceFixture, as: F
  alias ExAgent.Coordination.Composition
  alias ExAgent.Continuation.Record
  alias ExAgent.CompositionToolRestoreFixture, as: T

  setup %{tmp_dir: tmp_dir} do
    start_supervised!({Store.ETS, table: __MODULE__})
    control = start_supervised!({Agent, fn -> nil end})

    store =
      Store.scoped(
        {SequenceApprovalFixture.Journal, %{table: __MODULE__, control: control, owner: self()}},
        "sequence-approval"
      )

    path = Path.join(tmp_dir, "sequence-active-#{System.unique_integer([:positive])}")
    File.write!(path, "")

    on_exit(fn ->
      File.rm(path)
      File.rm(path <> ".json")
    end)

    %{
      store: store,
      control: control,
      effects: path,
      config: %{SequenceApprovalFixture.config(store) | lease_ms: 3000}
    }
  end

  defp capture_tools(c, opts) do
    arm = %F.Arm{
      control: c.control,
      operation: opts[:operation] || "tool_resolution",
      mode: opts[:mode] || :after,
      step: opts[:step] || 1
    }

    opts = Keyword.update(opts, :capabilities, [arm], &[arm | &1])
    definition = F.tool_definition(c.effects, opts)

    assert {:error, %ExAgent.RunError{partial: partial}} =
             ExAgent.LegacyStructuralFixture.run(definition, "input", continuation: c.config)

    if not is_nil(partial.continuation_checkpoint) and Keyword.get(opts, :retry_checkpoint, true) do
      assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
    end

    ready = F.recover(c.store)
    assert :ok = Record.validate(ready, {"sequence-approval", :agent, "run"})
    ready
  end

  for actions <- [["retry", "success"], ["success", "retry"], ["retry", "retry", "success"]] do
    @actions actions
    test "active B ordered control #{inspect(actions)} counts only once with closed A", c do
      calls = Enum.with_index(@actions, &T.call("call#{&2}", &1))
      script = [T.response(calls), T.text()]
      ready = capture_tools(c, script: script)
      flush()

      definition =
        F.tool_definition(c.effects,
          script: script,
          trap: true,
          new_index: 1,
          capabilities: [%T.Hooks{owner: self(), trap_tools: true}]
        )

      result =
        Composition.resume(definition, SequenceApprovalFixture.reference(ready),
          continuation: c.config
        )

      if @actions == ["retry", "retry", "success"] do
        assert {:error,
                %ExAgent.RunError{
                  reason:
                    {:unexpected_model_behavior,
                     {:tool_retries_exhausted, "effect", %{"code" => "runtime_error"}}}
                }} = result

        assert File.read!(c.effects) == "A\n"
        refute_received {:model, _}
        assert {:ok, failed} = Store.load_record(c.store, :agent, "run")
        assert failed["execution"]["state"] == "claimed"
      else
        assert {:ok, result} = result
        assert result.tool_calls == 1 + length(@actions)
        assert result.request_count == 5
        expected = if @actions == ["success", "retry"], do: %{"effect" => 1}, else: %{}
        assert_received {:hook, :before, false, %{tool_calls: 2, tool_retries: ^expected}, 2}
        assert File.read!(c.effects) == "A\nC\n"
      end

      refute_received {:tool, _}
      refute_received {:tool_hook, _, _}
    end
  end

  test "prefix and current batch sharing call ID retain retry counts and select actual batch",
       c do
    script = [T.response([T.call("a", "retry")]), T.response([T.call("a", "retry")]), T.text()]
    ready = capture_tools(c, script: script, step: 2, max_retries: 3)
    flush()

    definition =
      F.tool_definition(c.effects,
        script: script,
        trap: true,
        new_index: 2,
        max_retries: 3,
        capabilities: [%T.Hooks{owner: self(), trap_tools: true}]
      )

    assert {:ok, result} =
             Composition.resume(definition, SequenceApprovalFixture.reference(ready),
               continuation: c.config
             )

    assert result.tool_calls == 3
    assert result.request_count == 6
    assert_received {:hook, :before, false, %{tool_calls: 2, tool_retries: %{"effect" => 2}}, 2}
    refute_received {:tool, _}
    refute_received {:model, 0}
    refute_received {:model, 1}
  end

  for decision <- [:retry, :success] do
    @decision decision
    test "B prefix then attested output #{decision} consumes only actual response", c do
      value = if @decision == :retry, do: "invalid", else: 9
      script = [T.response([T.call("one", "retry")]), T.output(value), T.output(9)]

      ready =
        capture_tools(c, script: script, operation: "output_resolution", output_type: T.Output)

      flush()

      definition =
        F.tool_definition(c.effects,
          script: script,
          trap: true,
          new_index: 2,
          output_type: T.Output,
          capabilities: [%T.Hooks{owner: self(), trap_tools: true}]
        )

      Process.put(:tool_restore_args_trap, %{"count" => value})

      assert {:ok, result} =
               Composition.resume(definition, SequenceApprovalFixture.reference(ready),
                 continuation: c.config
               )

      assert Enum.at(result.steps, 1).output == %{"count" => 9}
      assert result.tool_calls == 2
      assert result.request_count == if(@decision == :retry, do: 6, else: 5)

      if @decision == :retry do
        assert_received {:hook, :before, false,
                         %{tool_calls: 1, output_retries_used: 1, tool_retries: %{"effect" => 1}},
                         2}
      end

      refute_received {:tool, _}
      refute_received {:model, 0}
      refute_received {:model, 1}
    end
  end

  test "old output retry attestation cannot mask current B tool batch", c do
    script = [T.output("invalid"), T.response([T.call("one", "retry")]), T.output(9)]
    ready = capture_tools(c, script: script, step: 2, output_type: T.Output)
    flush()

    definition =
      F.tool_definition(c.effects,
        script: script,
        trap: true,
        new_index: 2,
        output_type: T.Output
      )

    Process.put(:tool_restore_args_trap, %{"count" => "invalid"})

    assert {:ok, result} =
             Composition.resume(definition, SequenceApprovalFixture.reference(ready),
               continuation: c.config
             )

    assert Enum.at(result.steps, 1).output == %{"count" => 9}
    assert result.tool_calls == 2
    assert result.request_count == 6
    assert_received {:model, 2}
    refute_received {:tool, _}
  end

  for deny <- [false, true] do
    @deny deny
    test "consumed public approvals remain historical after currentdeny=#{deny}", c do
      definition = SequenceApprovalFixture.definition(c.effects)

      assert {:ok, %{status: :paused}} =
               ExAgent.LegacyStructuralFixture.run(
                 definition,
                 "input",
                 [continuation: c.config] ++ SequenceApprovalFixture.options()
               )

      {:ok, pending} = Store.load_record(c.store, :agent, "run")

      approved =
        Enum.reduce(Map.keys(pending["execution"]["progress"]["approvals"]), pending, fn id,
                                                                                         record ->
          assert {:ok, %{record: next}} = SequenceApprovalFixture.decide(c.store, record, id)
          next
        end)

      options =
        if @deny,
          do: [step_options: %{"B" => [permissions: ExAgent.Permissions.new!(default: :deny)]}],
          else: SequenceApprovalFixture.options()

      Agent.update(c.control, fn _ -> {"tool_resolution", :after} end)

      assert {:error, %ExAgent.RunError{partial: partial}} =
               Composition.resume(
                 definition,
                 SequenceApprovalFixture.reference(approved),
                 [continuation: c.config] ++ options
               )

      assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
      ready = F.recover(c.store)
      effects = File.read!(c.effects)

      assert {:ok, result} =
               Composition.resume(
                 SequenceApprovalFixture.definition(c.effects, true),
                 SequenceApprovalFixture.reference(ready),
                 [continuation: c.config] ++ SequenceApprovalFixture.options()
               )

      assert result.request_count == 5
      assert result.tool_calls == 3
      assert File.read!(c.effects) == effects <> "C\n"
      if @deny, do: assert(effects == "A\n")
      {:ok, completed} = Store.load_record(c.store, :agent, "run")

      assert completed["execution"]["progress"]["approvals"] ===
               approved["execution"]["progress"]["approvals"]

      assert Map.take(completed["execution"]["effects"], Map.keys(ready["execution"]["effects"])) ===
               ready["execution"]["effects"]
    end
  end

  test "two claimants at a resolved active B have one winner and no loser callbacks", c do
    ready = capture_tools(c, [])
    flush()
    Agent.update(c.control, fn _ -> {"claim", :ack_barrier} end)
    owner = self()

    config =
      Map.put(c.config, :on_writer, fn _ ->
        send(owner, {:active_owner, self()})
        :ok
      end)

    definition = F.tool_definition(c.effects, trap: true, new_index: 1, owner: owner)

    first =
      Task.async(fn ->
        Composition.resume(definition, SequenceApprovalFixture.reference(ready),
          continuation: config
        )
      end)

    assert_receive {:after, "claim", writer}, 2000

    assert {:error, %ExAgent.RunError{}} =
             Composition.resume(definition, SequenceApprovalFixture.reference(ready),
               continuation: config
             )

    refute_received {:active_owner, _}
    send(writer, :release)
    assert {:ok, result} = Task.await(first, 5000)
    assert result.status == :completed
    assert_receive {:active_owner, _}
    refute_received {:active_owner, _}
    assert File.read!(c.effects) == "A\nC\n"
    refute_received {:tool, _}
  end

  for operation <- ["claim", "begin_effect"] do
    @operation operation
    test "late #{@operation} ACK on resolved B grants no Model IO", c do
      ready = capture_tools(c, [])
      flush()
      Agent.update(c.control, fn _ -> {@operation, :ack_barrier} end)
      owner = self()
      definition = F.tool_definition(c.effects, trap: true, new_index: 1, owner: owner)

      task =
        Task.async(fn ->
          Composition.resume(definition, SequenceApprovalFixture.reference(ready),
            continuation: %{c.config | lease_ms: 1000}
          )
        end)

      assert_receive {:after, @operation, writer}, 2000
      {:ok, claimed} = Store.load_record(c.store, :agent, "run")
      wait = max(claimed["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

      receive do
      after
        wait -> :ok
      end

      send(writer, :release)
      assert {:error, %ExAgent.RunError{}} = Task.await(task, 5000)
      assert File.read!(c.effects) == "A\n"
      refute_received {:model, _}
      refute_received {:tool, _}
      {:ok, stored} = Store.load_record(c.store, :agent, "run")
      assert stored["execution"]["state"] == "claimed"
    end
  end

  for operation <- ["claim", "begin_effect", "step_output", "step_input"] do
    @operation operation
    test "#{operation} lost ACK after active B yields a real Store-only retry token", c do
      ready = capture_tools(c, [])
      flush()
      Agent.update(c.control, fn _ -> {@operation, :after} end)
      definition = F.tool_definition(c.effects, trap: true, new_index: 1)

      assert {:error, %ExAgent.RunError{partial: partial}} =
               Composition.resume(
                 definition,
                 SequenceApprovalFixture.reference(ready),
                 continuation: c.config
               )

      token = partial.continuation_checkpoint
      assert token["command"]["operation"] == @operation
      before = File.read!(c.effects)
      flush()
      assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
      assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
      assert File.read!(c.effects) == before
      assert before == "A\n"
      refute_received {:model, _}
      refute_received {:tool, _}
      {:ok, stored} = Store.load_record(c.store, :agent, "run")
      assert :ok = Record.validate(stored, {"sequence-approval", :agent, "run"})
    end
  end

  test "globally valid final effects without batch resolution still reject before claim", c do
    ready = capture_tools(c, mode: :before, retry_checkpoint: false)
    definition = F.tool_definition(c.effects, trap: true)

    assert {:error, %ExAgent.RunError{reason: :unsupported_composition_boundary}} =
             Composition.resume(
               definition,
               SequenceApprovalFixture.reference(ready),
               continuation: Map.put(c.config, :on_writer, fn _ -> flunk("unexpected claim") end)
             )

    assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
    assert File.read!(c.effects) == "A\n"
  end

  for mutation <- [:orphan, :result_hash, :historical_fatal] do
    @mutation mutation
    test "global #{mutation} mutation cannot hide behind own B evidence", c do
      ready = capture_tools(c, [])
      frame = ready["execution"]["progress"]["runtime"]
      {id, a} = Enum.find(frame["children"], fn {_, child} -> child["status"] == "completed" end)

      invalid =
        case @mutation do
          :orphan ->
            {effect, _} =
              Enum.find(ready["execution"]["effects"], fn {_, e} ->
                e["intent"]["payload"]["run_id"] == id
              end)

            put_in(
              ready,
              ["execution", "effects", effect, "intent", "payload", "run_id"],
              "orphan"
            )

          :result_hash ->
            {batch, value} = Enum.find(frame["tool_batches"], fn {_, b} -> b["run_id"] == id end)
            [entry] = value["resolution"]["calls"]

            put_in(
              ready,
              ["execution", "progress", "runtime", "tool_batches", batch, "resolution", "calls"],
              [%{entry | "result_hash" => String.duplicate("0", 64)}]
            )

          :historical_fatal ->
            assert a["status"] == "completed"
            {batch, value} = Enum.find(frame["tool_batches"], fn {_, b} -> b["run_id"] == id end)
            [entry] = value["resolution"]["calls"]

            error = %{
              "code" => "tool_hook_failed",
              "message" => "historical fatal",
              "details" => nil,
              "omitted" => nil
            }

            put_in(
              ready,
              ["execution", "progress", "runtime", "tool_batches", batch, "resolution", "calls"],
              [%{entry | "error" => error}]
            )
        end

      key = {"sequence-approval", :agent, "run"}
      assert {:error, _} = Record.decode(Jason.encode!(invalid), key)
      {:ok, physical} = Record.key(key)
      true = :ets.insert(__MODULE__, {physical, Jason.encode!(invalid)})
      flush()
      definition = F.tool_definition(c.effects, trap: true)

      assert {:error, %ExAgent.RunError{partial: partial}} =
               Composition.resume(
                 definition,
                 SequenceApprovalFixture.reference(invalid),
                 continuation: c.config
               )

      assert partial.continuation == nil
      refute_received {:journal_command, _}
      refute_received :codec
      refute_received {:model, _}
      assert File.read!(c.effects) == "A\n"
    end
  end

  test "current portable fatal keeps confirmed tool data without Model or C or refund", c do
    script = [T.response([T.call("fatal"), T.call("success")]), T.text()]

    ready =
      capture_tools(c, script: script, capabilities: [%T.Hooks{owner: self(), fatal: ["fatal"]}])

    flush()
    definition = F.tool_definition(c.effects, script: script, trap: true)

    assert {:error, %ExAgent.RunError{reason: %{"code" => "tool_hook_failed"}}} =
             Composition.resume(
               definition,
               SequenceApprovalFixture.reference(ready),
               continuation: c.config
             )

    refute_received {:model, _}
    refute_received {:tool, _}
    {:ok, claimed} = Store.load_record(c.store, :agent, "run")
    assert claimed["execution"]["state"] == "claimed"
    assert claimed["execution"]["effects"] === ready["execution"]["effects"]

    assert claimed["execution"]["progress"]["runtime"] ===
             ready["execution"]["progress"]["runtime"]

    assert File.read!(c.effects) == "A\n"
    refute_received {:journal_command, %{"operation" => "finish"}}
  end

  test "abandoned finite active B reservation is not refunded by evidence restore", c do
    c = %{c | config: Map.put(c.config, :active_time_limit_ms, 10000)}
    ready = capture_tools(c, [])
    definition = F.tool_definition(c.effects, trap: true)
    flush()

    assert {:error, %ExAgent.RunError{}} =
             Composition.resume(
               definition,
               SequenceApprovalFixture.reference(ready),
               continuation: c.config
             )

    refute_received {:model, _}
    refute_received {:tool, _}
    assert File.read!(c.effects) == "A\n"
  end

  for n <- [1, 2] do
    @n n
    test "typed host preparation #{@n} precedes consuming current fatal B", c do
      ready =
        capture_tools(c,
          output_type: T.Output,
          capabilities: [%T.Hooks{owner: self(), fatal: ["one"]}]
        )

      definition = F.tool_definition(c.effects, output_type: T.OutputProxy, trap: true)
      Process.put(:tool_restore_reflections, 0)
      Process.put(:tool_restore_fail_reflection, @n)
      flush()

      assert {:error, %ExAgent.RunError{reason: reason}} =
               Composition.resume(
                 definition,
                 SequenceApprovalFixture.reference(ready),
                 continuation: c.config
               )

      refute match?(%{"code" => "tool_hook_failed"}, reason)
      {:ok, saved} = Store.load_record(c.store, :agent, "run")

      assert saved["execution"]["progress"]["runtime"] ===
               ready["execution"]["progress"]["runtime"]

      refute_received {:model, _}
      refute_received {:tool, _}
      assert File.read!(c.effects) == "A\n"
    end
  end

  defp consumed(c, definition, options \\ SequenceApprovalFixture.options()) do
    assert {:ok, %{status: :paused}} =
             ExAgent.LegacyStructuralFixture.run(
               definition,
               "input",
               [continuation: c.config] ++ SequenceApprovalFixture.options()
             )

    {:ok, pending} = Store.load_record(c.store, :agent, "run")

    approved =
      Enum.reduce(Map.keys(pending["execution"]["progress"]["approvals"]), pending, fn id,
                                                                                       record ->
        assert {:ok, %{record: next}} = SequenceApprovalFixture.decide(c.store, record, id)
        next
      end)

    Agent.update(c.control, fn _ -> {"tool_resolution", :after} end)

    assert {:error, %ExAgent.RunError{partial: partial}} =
             Composition.resume(
               definition,
               SequenceApprovalFixture.reference(approved),
               [continuation: c.config] ++ options
             )

    assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
    F.recover(c.store)
  end

  for change <- [:model_ref, :policy, :root_policy, :schema] do
    @change change
    @tag :active_matrix
    test "consumed approvals current #{@change} mismatch preserves history", c do
      original = SequenceApprovalFixture.definition(c.effects)
      ready = consumed(c, original)
      [a, b, last] = original.steps

      b =
        case @change do
          :model_ref ->
            %{b | model_ref: %{"id" => "changed", "version" => "1"}}

          :policy ->
            %{b | policy: %{"id" => "changed", "version" => "1"}}

          :schema ->
            [tool] = b.agent.tools

            %{
              b
              | agent: %{
                  b.agent
                  | tools: [
                      %{
                        tool
                        | parameters_json_schema:
                            Map.put(tool.parameters_json_schema, "additionalProperties", false)
                      }
                    ]
                }
            }

          :root_policy ->
            b
        end

      assert {:ok, definition} =
               Composition.new(id: original.id, version: original.version, steps: [a, b, last])

      config =
        if @change == :root_policy,
          do: Map.put(c.config, :policy, %{"id" => "changed", "version" => "1"}),
          else: c.config

      before = File.read!(c.effects)
      flush()

      assert {:error, %ExAgent.RunError{} = error} =
               Composition.resume(definition, SequenceApprovalFixture.reference(ready),
                 continuation: config
               )

      assert File.read!(c.effects) == before
      {:ok, after_record} = Store.load_record(c.store, :agent, "run")
      assert after_record["execution"]["effects"] === ready["execution"]["effects"]

      assert after_record["execution"]["progress"]["approvals"] ===
               ready["execution"]["progress"]["approvals"]

      if @change == :schema do
        assert error.reason == :continuation_tools_changed
        assert after_record["revision"] == ready["revision"] + 1
        assert_received {:journal_command, %{"operation" => "claim"}}
      else
        assert after_record === ready
        refute_received {:journal_command, %{"operation" => "claim"}}

        assert {:ok, %{status: :completed}} =
                 Composition.resume(original, SequenceApprovalFixture.reference(ready),
                   continuation: c.config
                 )
      end
    end
  end

  for changed <- [false, true] do
    @changed changed
    @tag :active_matrix
    test "consumed approvals actual model binding changed=#{changed}", c do
      original = SequenceApprovalFixture.definition(c.effects)
      [a, b, last] = original.steps

      model = %ExAgent.ContinuationBindingModel{
        script: b.agent.model.script,
        binding: %{"endpoint" => "original"},
        observer: self()
      }

      b = %{b | agent: %{b.agent | model: model}}
      original = %{original | steps: [a, b, last]}
      ready = consumed(c, original)
      before = File.read!(c.effects)
      flush()
      current = if @changed, do: %{model | binding: %{"endpoint" => "changed"}}, else: model
      b = %{b | agent: %{b.agent | model: current}}

      result =
        Composition.resume(
          %{original | steps: [a, b, last]},
          SequenceApprovalFixture.reference(ready),
          continuation: c.config
        )

      assert_received :binding_called

      if @changed do
        assert {:error, %ExAgent.RunError{reason: :continuation_model_binding_changed}} = result
        assert File.read!(c.effects) == before
        {:ok, saved} = Store.load_record(c.store, :agent, "run")
        assert saved["revision"] == ready["revision"] + 1
        assert saved["execution"]["effects"] === ready["execution"]["effects"]
      else
        assert {:ok, %{request_count: 5, tool_calls: 3}} = result
        assert File.read!(c.effects) == before <> "C\n"
      end
    end
  end

  for deny <- [false, true] do
    @deny deny
    @tag :active_matrix
    test "consumed effective args differ from model original with predispatch deny=#{deny}", c do
      original = SequenceApprovalFixture.definition(c.effects)
      [a, b, last] = original.steps
      b = %{b | agent: %{b.agent | capabilities: [%F.EffectiveArgs{}]}}
      original = %{original | steps: [a, b, last]}

      options =
        if @deny,
          do: [step_options: %{"B" => [permissions: ExAgent.Permissions.new!(default: :deny)]}],
          else: SequenceApprovalFixture.options()

      ready = consumed(c, original, options)

      assert Enum.all?(
               Map.values(ready["execution"]["progress"]["approvals"]),
               &String.ends_with?(&1["args"]["label"], "-effective")
             )

      before = File.read!(c.effects)

      if @deny,
        do: assert(before == "A\n"),
        else: assert(before =~ "B1-effective\n" and before =~ "B2-effective\n")

      assert {:ok, %{request_count: 5, tool_calls: 3}} =
               Composition.resume(
                 original,
                 SequenceApprovalFixture.reference(ready),
                 [continuation: c.config] ++ SequenceApprovalFixture.options()
               )

      assert File.read!(c.effects) == before <> "C\n"
      {:ok, saved} = Store.load_record(c.store, :agent, "run")

      assert saved["execution"]["progress"]["approvals"] ===
               ready["execution"]["progress"]["approvals"]

      assert Map.take(saved["execution"]["effects"], Map.keys(ready["execution"]["effects"])) ===
               ready["execution"]["effects"]
    end
  end

  for boundary <- [:model, :tool], bound <- [:budget, :lease, :timely] do
    @boundary boundary
    @bound bound
    @tag :active_observability
    test "active history observability #{@boundary} #{@bound} rechecks dispatch authority", c do
      script = [T.response([T.call("old")]), T.response([T.call("new", "fresh")]), T.text()]
      ready = capture_tools(c, script: script)
      flush()
      owner = self()
      gate = start_supervised!({Agent, fn -> true end}, id: :observability_gate)
      limit = if @bound == :timely, do: 5000, else: 700

      config =
        if @bound == :lease,
          do: %{c.config | lease_ms: limit},
          else: Map.put(c.config, :active_time_limit_ms, limit)

      obs =
        ExAgent.Observability.OpenTelemetry.new(
          content: true,
          redact: fn field, value ->
            hit =
              field == :input and
                if(@boundary == :model,
                  do: is_list(value),
                  else: is_map(value) and value["action"] == "fresh"
                )

            if hit and Agent.get_and_update(gate, fn open -> {open, false} end) do
              send(owner, {:active_observation, self(), System.monotonic_time(:millisecond)})

              receive do
                :release_observation -> :ok
              end
            end

            :drop
          end
        )

      definition =
        F.tool_definition(c.effects,
          script: script,
          trap: true,
          new_index: 1,
          allow_actions: ["fresh"],
          owner: owner
        )

      task =
        Task.async(fn ->
          Composition.resume(definition, SequenceApprovalFixture.reference(ready),
            continuation: config,
            observability: obs
          )
        end)

      assert_receive {:active_observation, pid, entered}, 5000
      {:ok, at_callback} = Store.load_record(c.store, :agent, "run")
      assert at_callback["execution"]["attempt_id"] != ready["execution"]["attempt_id"]
      if @boundary == :model, do: refute_received({:model, _}), else: assert_received({:model, 1})
      refute_received {:tool, _}

      wait =
        case @bound do
          :timely ->
            0

          :lease ->
            max(at_callback["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

          :budget ->
            max(entered + limit - System.monotonic_time(:millisecond) + 1, 0)
        end

      receive do
      after
        wait -> :ok
      end

      send(pid, :release_observation)
      result = Task.await(task, 5000)

      if @bound == :timely do
        assert {:ok, %{request_count: 6, tool_calls: 3}} = result
        assert_received {:tool, %{"action" => "fresh"}}
        refute_received {:tool, _}
        assert File.read!(c.effects) == "A\nC\n"
        {:ok, final} = Store.load_record(c.store, :agent, "run")
        budget = final["execution"]["progress"]["active_budget"]
        assert budget["reserved_ms"] == nil
        assert budget["remaining_ms"] > 0 and budget["remaining_ms"] < limit
      else
        assert {:error, %ExAgent.RunError{}} = result
        refute_received {:model, _}
        refute_received {:tool, _}
        assert File.read!(c.effects) == "A\n"
        {:ok, saved} = Store.load_record(c.store, :agent, "run")
        assert saved["execution"]["effects"] === at_callback["execution"]["effects"]

        assert saved["execution"]["progress"]["active_budget"] ===
                 at_callback["execution"]["progress"]["active_budget"]
      end
    end
  end

  for {usage, index} <-
        Enum.with_index([
          %ExAgent.Message.Usage{input_tokens: 7, output_tokens: nil},
          ExAgent.Message.Usage.partial(%ExAgent.Message.Usage{
            input_tokens: 3,
            output_tokens: 4
          }),
          ExAgent.Message.Usage.with_cost(
            %ExAgent.Message.Usage{input_tokens: 3, output_tokens: 4},
            17,
            "estimator",
            true
          )
        ]) do
    @usage usage
    @tag :active_ledger
    test "active contributed tool ledger profile #{index} is imported exactly without redebit",
         c do
      ready = capture_tools(c, usage: @usage)
      frame = ready["execution"]["progress"]["runtime"]
      old_scope = frame["scope"]

      {b_id, b} =
        Enum.find(frame["children"], fn {_, child} -> child["link"]["step_id"] == "B" end)

      own_batch =
        Enum.find_value(frame["tool_batches"], fn {_, batch} ->
          if batch["run_id"] == b_id, do: batch
        end)

      assert [entry] = own_batch["resolution"]["calls"]

      assert own_batch["observations"][entry["effect_id"]]["application"]["status"] ==
               "contributed"

      definition = F.tool_definition(c.effects, trap: true, new_index: 1)
      flush()

      assert {:ok, result} =
               Composition.resume(definition, SequenceApprovalFixture.reference(ready),
                 continuation: c.config,
                 root_options: [
                   estimate_cost: fn _, usage ->
                     assert usage.input_tokens != @usage.input_tokens
                     13
                   end
                 ]
               )

      assert result.request_count == 5
      assert result.tool_calls == 2
      {:ok, final} = Store.load_record(c.store, :agent, "run")
      new_scope = final["execution"]["progress"]["runtime"]["scope"]

      for key <- ~w(operations batches retry_batches) do
        for historical <- old_scope[key] do
          assert Enum.count(new_scope[key], &(&1 === historical)) == 1
        end
      end

      assert Map.take(final["execution"]["effects"], Map.keys(ready["execution"]["effects"])) ===
               ready["execution"]["effects"]

      completed_b = final["execution"]["progress"]["runtime"]["children"][b_id]

      assert completed_b["snapshot"]["usage"]["input_tokens"] ==
               b["snapshot"]["usage"]["input_tokens"] + 1

      refute_received {:tool, _}
      assert File.read!(c.effects) == "A\nC\n"
    end
  end

  for phase <- [:barrier, :ack_barrier] do
    @phase phase
    @tag :active_ownership
    test "active owner kill #{@phase} of new intent distinguishes ready from uncertain", c do
      ready = capture_tools(c, [])
      flush()
      parent = self()

      definition =
        F.tool_definition(c.effects,
          trap: true,
          new_index: 1,
          owner: parent,
          capabilities: [%T.Hooks{owner: parent}]
        )

      Agent.update(c.control, fn _ -> {"begin_effect", @phase} end)

      {owner, ref} =
        spawn_monitor(fn ->
          Composition.resume(definition, SequenceApprovalFixture.reference(ready),
            continuation: c.config
          )
        end)

      assert_receive {:owned, writer, scope}, 5000
      event = if @phase == :barrier, do: :before, else: :after
      assert_receive {^event, "begin_effect", ^writer}, 5000
      monitors = for pid <- [writer, scope], do: {pid, Process.monitor(pid)}
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^ref, :process, ^owner, :killed}, 5000
      send(writer, :release)

      for {pid, monitor} <- monitors,
          do: assert_receive({:DOWN, ^monitor, :process, ^pid, _}, 5000)

      recovered = F.recover(c.store)
      refute_received {:model, _}
      refute_received {:tool, _}

      if @phase == :ack_barrier do
        assert recovered["execution"]["state"] == "uncertain"

        assert {:error, %ExAgent.RunError{reason: :composition_not_ready}} =
                 Composition.resume(definition, SequenceApprovalFixture.reference(recovered),
                   continuation: c.config
                 )

        assert File.read!(c.effects) == "A\n"
      else
        assert recovered["execution"]["state"] == "ready"

        assert {:ok, %{request_count: 5, tool_calls: 2}} =
                 Composition.resume(definition, SequenceApprovalFixture.reference(recovered),
                   continuation: c.config
                 )

        assert File.read!(c.effects) == "A\nC\n"
      end
    end
  end

  @tag :active_corruption
  test "consumed approval IDs receipts revisions bindings and global retry plans cannot hide in history",
       c do
    definition = SequenceApprovalFixture.definition(c.effects)
    ready = consumed(c, definition)
    [id | _] = Map.keys(ready["execution"]["progress"]["approvals"])
    approval = ready["execution"]["progress"]["approvals"][id]

    changes = [
      %{"id" => "approval-wrong"},
      %{"call_id" => "a"},
      %{"run_id" => ready["execution"]["run_id"]},
      %{"requested_revision" => ready["revision"] + 1},
      %{"requested_revision" => 1},
      %{"schema_hash" => String.duplicate("f", 64)},
      %{"policy" => %{"id" => "other", "version" => "1"}},
      %{"definition" => %{"id" => "other", "version" => "1"}},
      %{"args" => %{"label" => "different"}}
    ]

    mutations =
      Enum.map(changes, fn change ->
        {:ok, changed} =
          ExAgent.Continuation.Approval.new(
            approval
            |> Map.drop(~w(approval_version payload_hash decision))
            |> Map.merge(change)
          )

        changed = Map.put(changed, "decision", approval["decision"])
        put_in(ready, ["execution", "progress", "approvals", id], changed)
      end)

    mutations =
      mutations ++
        [
          update_in(
            ready,
            ["receipts"],
            &Map.reject(&1, fn {_, r} -> r["operation"] == "pause" end)
          ),
          put_in(ready, ["execution", "progress", "effect_retries"], %{
            "orphan-in-closed-A" => %{}
          })
        ]

    before = File.read!(c.effects)
    key = {"sequence-approval", :agent, "run"}
    {:ok, physical} = Record.key(key)

    for invalid <- mutations do
      assert {:error, :invalid_record} = Record.validate(invalid, key)
      :ets.insert(__MODULE__, {physical, Jason.encode!(invalid)})
      flush()

      assert {:error, %ExAgent.RunError{}} =
               Composition.resume(definition, SequenceApprovalFixture.reference(invalid),
                 continuation: c.config
               )

      refute_received {:journal_command, _}
      assert File.read!(c.effects) == before
    end
  end

  for operation <- ["finalize_call", "outcome"] do
    @operation operation
    @tag :active_uncertain
    test "active B #{@operation} checkpoint before commit remains raw or uncertain", c do
      ready = capture_tools(c, operation: @operation, mode: :before, retry_checkpoint: false)

      if @operation == "finalize_call" do
        assert Enum.any?(ready["execution"]["effects"], fn {_, effect} ->
                 effect["intent"]["kind"] == "tool" and
                   effect["outcome"]["data"]["phase"] == "raw"
               end)
      else
        assert ready["execution"]["state"] == "uncertain"
      end

      flush()
      definition = F.tool_definition(c.effects, trap: true)

      assert {:error, %ExAgent.RunError{}} =
               Composition.resume(definition, SequenceApprovalFixture.reference(ready),
                 continuation: c.config
               )

      refute_received {:journal_command, _}
      refute_received {:model, _}
      refute_received {:tool, _}
      assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
      assert File.read!(c.effects) == "A\n"
    end
  end

  @tag :active_capacity
  test "active B new intent public checkpoint capacity minus exact plus retains history", c do
    ready = capture_tools(c, [])
    definition = F.tool_definition(c.effects, trap: true, new_index: 1)

    trial = fn limit ->
      install(ready)
      flush()
      Agent.update(c.control, fn _ -> {"begin_effect", :before} end)

      result =
        Composition.resume(definition, SequenceApprovalFixture.reference(ready),
          continuation: Map.put(c.config, :max_checkpoint_bytes, limit)
        )

      refute_received {:model, _}
      refute_received {:tool, _}
      assert File.read!(c.effects) == "A\n"

      case result do
        {:error,
         %ExAgent.RunError{
           partial: %{
             continuation_checkpoint: %{"command" => %{"operation" => "begin_effect"}} = token
           }
         }} ->
          {:admitted, token}

        {:error, %ExAgent.RunError{}} ->
          :rejected
      end
    end

    assert {:admitted, _} = trial.(300_000)
    exact = threshold(1, 300_000, fn n -> match?({:admitted, _}, trial.(n)) end)
    assert :rejected = trial.(exact - 1)
    assert {:admitted, token} = trial.(exact)
    assert ExAgent.Retention.bytes(token) <= exact
    assert {:admitted, _} = trial.(exact + 1)

    IO.inspect(%{public_checkpoint_limit: exact, token_bytes: ExAgent.Retention.bytes(token)},
      label: "ACTIVE_CHECKPOINT_CAPACITY"
    )
  end

  @tag :active_capacity
  test "active B isolated token parser minus exact plus is separate from valid CAS", c do
    ready = capture_tools(c, [])
    definition = F.tool_definition(c.effects, trap: true, new_index: 1)
    Agent.update(c.control, fn _ -> {"begin_effect", :before} end)

    assert {:error, %ExAgent.RunError{partial: partial}} =
             Composition.resume(definition, SequenceApprovalFixture.reference(ready),
               continuation: c.config
             )

    original = partial.continuation_checkpoint
    assert original["command"]["operation"] == "begin_effect"
    {:ok, before} = Store.load_record(c.store, :agent, "run")
    path = ["command", "payload", "codec_probe_padding"]
    base = put_in(original, path, "")
    room = Record.max_bytes() - ExAgent.Retention.bytes(base)

    for delta <- [-1, 0, 1] do
      token = put_in(base, path, String.duplicate("x", room + delta))
      assert ExAgent.Retention.bytes(token) == Record.max_bytes() + delta
      flush()
      assert {:error, reason} = Continuation.retry_checkpoint(c.store, token)

      if delta <= 0 do
        assert_received {:journal_command, command}
        assert command === token["command"]
        assert reason != :invalid_checkpoint_token

        assert {:error, ^reason} =
                 Store.transition(c.store, :agent, "run", before["revision"], command)
      else
        assert reason == :invalid_checkpoint_token
        refute_received {:journal_command, _}
      end

      assert {:ok, ^before} = Store.load_record(c.store, :agent, "run")
      IO.inspect({delta, reason}, label: "ACTIVE_TOKEN_PARSE")
    end

    assert {:ok, %{record: committed, replayed: false}} =
             Continuation.retry_checkpoint(c.store, original)

    assert {:ok, %{record: ^committed, replayed: true}} =
             Continuation.retry_checkpoint(c.store, original)

    assert File.read!(c.effects) == "A\n"
  end

  @tag :active_fencing
  test "active B tool exception leaves an unresolved dispatch and never replays", c do
    ready = capture_tools(c, tool_failure: true)
    assert ready["execution"]["state"] == "uncertain"

    assert Enum.any?(ready["execution"]["effects"], fn {_, effect} ->
             effect["intent"]["kind"] == "tool" and effect["state"] == "running" and
               is_nil(effect["outcome"])
           end)

    flush()

    assert {:error, %ExAgent.RunError{reason: :composition_not_ready}} =
             Composition.resume(
               F.tool_definition(c.effects, trap: true),
               SequenceApprovalFixture.reference(ready),
               continuation: c.config
             )

    assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
    refute_received {:journal_command, _}
    refute_received {:model, _}
    refute_received {:tool, _}
    assert File.read!(c.effects) == "A\n"
  end

  @tag :active_fencing
  test "late live Model result after explicit recovery cannot confirm an old active owner", c do
    ready = capture_tools(c, [])
    flush()
    parent = self()

    blocked = fn _, _ ->
      send(parent, {:active_model_waiting, self()})

      receive do
        :release_model -> T.text()
      end
    end

    definition =
      F.tool_definition(c.effects,
        script: [T.text(), blocked],
        trap: true,
        new_index: 1,
        owner: parent,
        capabilities: [%T.Hooks{owner: parent}]
      )

    task =
      Task.async(fn ->
        Composition.resume(definition, SequenceApprovalFixture.reference(ready),
          continuation: %{c.config | lease_ms: 1000}
        )
      end)

    assert_receive {:owned, writer, scope}, 5000
    assert_receive {:active_model_waiting, model}, 5000
    monitors = for pid <- [writer, scope], do: {pid, Process.monitor(pid)}
    recovered = F.recover(c.store)
    assert recovered["execution"]["state"] == "uncertain"
    send(model, :release_model)
    assert {:error, %ExAgent.RunError{}} = Task.await(task, 5000)
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 5000)
    assert {:ok, ^recovered} = Store.load_record(c.store, :agent, "run")
    flush()

    assert {:error, %ExAgent.RunError{reason: :composition_not_ready}} =
             Composition.resume(definition, SequenceApprovalFixture.reference(recovered),
               continuation: c.config
             )

    refute_received {:journal_command, _}
    refute_received {:model, _}
    refute_received {:tool, _}
    assert File.read!(c.effects) == "A\n"
    assert {:ok, %{retryable_effects: [binding]}} = Continuation.get(c.store, "run")

    assert {:error, :unsupported_structural_operation} =
             Continuation.retry_effect(c.store, "run", binding,
               operation_id: "explicit-retry",
               actor: "host",
               authorize: fn actor, _, _ -> {:ok, actor} end,
               accept_duplicate_risk: true,
               idempotency_key: "synthetic-visible-key"
             )

    # Structural administrative retries are deliberately not a supported producer.
    # The global malformed-plan probe above exercises rejection before selection.
    refute_received {:model, _}
    assert {:ok, ^recovered} = Store.load_record(c.store, :agent, "run")
  end

  @tag :active_inflight_kill
  test "owner killed during active new Model IO terminates owned processes and keeps uncertain intent",
       c do
    ready = capture_tools(c, [])
    flush()
    parent = self()

    blocked = fn _, _ ->
      send(parent, {:active_model_waiting, self()})

      receive do
        :release_model -> T.text()
      end
    end

    definition =
      F.tool_definition(c.effects,
        script: [T.text(), blocked],
        trap: true,
        new_index: 1,
        owner: parent,
        capabilities: [%T.Hooks{owner: parent}]
      )

    {owner, monitor} =
      spawn_monitor(fn ->
        Composition.resume(definition, SequenceApprovalFixture.reference(ready),
          continuation: c.config
        )
      end)

    assert_receive {:owned, writer, scope}, 5000
    assert_receive {:active_model_waiting, model}, 5000
    monitors = for pid <- Enum.uniq([writer, scope, model]), do: {pid, Process.monitor(pid)}
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 5000
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 5000)
    recovered = F.recover(c.store)
    assert recovered["execution"]["state"] == "uncertain"
    flush()

    assert {:error, %ExAgent.RunError{reason: :composition_not_ready}} =
             Composition.resume(definition, SequenceApprovalFixture.reference(recovered),
               continuation: c.config
             )

    refute_received {:model, _}
    refute_received {:tool, _}
    assert File.read!(c.effects) == "A\n"
  end

  @tag :active_history
  test "active confirmed batch append history minus exact plus preserves fatal evidence", c do
    ready = capture_tools(c, capabilities: [%T.Hooks{owner: self(), fatal: ["one"]}])
    definition = F.tool_definition(c.effects, trap: true)

    config =
      Map.merge(c.config, %{
        kind: :composition,
        composition: definition,
        definition: %{"id" => definition.id, "version" => definition.version},
        max_checkpoint_bytes: Record.max_bytes()
      })

    assert {:ok, {:confirmed_tool_history, {:confirmed_tool_batch, selection}, 0}, _, _, _, _} =
             ExAgent.Continuation.CompositionRestore.sequence_preflight(
               definition,
               SequenceApprovalFixture.reference(ready),
               config,
               []
             )

    b =
      Enum.find_value(ready["execution"]["progress"]["runtime"]["children"], fn {_, child} ->
        if child["link"]["step_id"] == "B", do: child
      end)

    {:ok, messages} = ExAgent.Message.from_json(b["snapshot"]["message_history"])

    complete =
      messages ++
        [
          %ExAgent.Message.Request{
            parts: selection.parts,
            run_id: b["frame"]["run_id"],
            timestamp: DateTime.utc_now()
          }
        ]

    exact = ExAgent.Retention.bytes(complete)

    for delta <- [-1, 0, 1] do
      install(ready)
      flush()

      assert {:error, %ExAgent.RunError{reason: reason, partial: result}} =
               Composition.resume(definition, SequenceApprovalFixture.reference(ready),
                 continuation: c.config,
                 step_options: %{"B" => [max_history_bytes: exact + delta]}
               )

      if delta == -1 do
        assert {:retention_limit_exceeded, %{boundary: :history, bytes: ^exact}} = reason
      else
        assert %{"code" => "tool_hook_failed"} = reason
      end

      # Composition exposes the confirmed checkpoint, including on operational failure.
      assert Enum.find(result.steps, &(&1.id == "B")).messages == messages

      {:ok, stored} = Store.load_record(c.store, :agent, "run")
      assert stored["execution"]["effects"] === ready["execution"]["effects"]
      refute_received {:model, _}
      refute_received {:tool, _}
      assert File.read!(c.effects) == "A\n"
    end

    IO.inspect(exact, label: "ACTIVE_HISTORY_LIMIT")
  end

  defp active_claim(c) do
    ready = capture_tools(c, [])
    Agent.update(c.control, fn _ -> {"begin_effect", :before} end)

    assert {:error, %ExAgent.RunError{}} =
             Composition.resume(
               F.tool_definition(c.effects, trap: true, new_index: 1),
               SequenceApprovalFixture.reference(ready),
               continuation: %{c.config | lease_ms: 600_000}
             )

    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["state"] == "claimed"
    flush()
    record
  end

  defp checkpoint(record, id) do
    e = record["execution"]

    %{
      "record_id" => record["record_id"],
      "operation_id" => id,
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

  defp cas(c, record, command),
    do: Store.transition(c.store, :agent, "run", record["revision"], command)

  defp measured(record),
    do: byte_size(Jason.encode!(record)) + Record.cleanup_reserve_bytes(record)

  defp cleanup(c, record) do
    command = %{
      "record_id" => record["record_id"],
      "operation_id" => String.duplicate(<<1>>, 512),
      "actor_id" => String.duplicate(<<2>>, 512),
      "operation" => "cancel",
      "payload" => %{}
    }

    assert {:ok, %{record: cancelled, replayed: false}} = cas(c, record, command)
    assert cancelled["execution"]["state"] == "cancelled"
    assert cancelled["execution"]["effects"] === record["execution"]["effects"]

    assert cancelled["execution"]["progress"]["active_budget"] ===
             record["execution"]["progress"]["active_budget"]

    assert {:ok, _} = Record.encode(cancelled, {"sequence-approval", :agent, "run"})
    assert {:ok, %{record: ^cancelled, replayed: true}} = cas(c, record, command)
  end

  @tag :active_json
  test "active B genuine JSON checkpoint plus cleanup reserve minus exact plus uses CAS", c do
    original = active_claim(c)
    node = ExAgent.Continuation.Frame.active_step_id(original["execution"]["progress"]["runtime"])
    path = ["payload", "progress", "runtime", "children", node, "snapshot", "metadata", "padding"]
    base = put_in(checkpoint(original, "json-capacity"), path, "")

    assert {:ok, %{record: projected}} =
             ExAgent.Continuation.Transition.apply(
               original,
               {"sequence-approval", :agent, "run"},
               original["revision"],
               base,
               System.system_time(:millisecond)
             )

    room = Record.max_bytes() - measured(projected)

    for delta <- [-1, 0, 1] do
      install(original)
      command = put_in(base, path, String.duplicate("x", room + delta))

      if delta <= 0 do
        assert {:ok, %{record: committed, replayed: false}} = cas(c, original, command)
        assert measured(committed) == Record.max_bytes() + delta
        assert Record.cleanup_reserve_bytes(committed) > 0
        assert {:ok, %{record: ^committed, replayed: true}} = cas(c, original, command)

        IO.inspect(
          %{
            delta: delta,
            json: byte_size(Jason.encode!(committed)),
            cleanup: Record.cleanup_reserve_bytes(committed),
            receipts: map_size(committed["receipts"])
          },
          label: "ACTIVE_JSON_CAPACITY"
        )

        cleanup(c, committed)
      else
        assert {:error, :record_limit} = cas(c, original, command)
        assert {:ok, ^original} = Store.load_record(c.store, :agent, "run")
      end
    end

    assert File.read!(c.effects) == "A\n"
    refute_received {:model, _}
    refute_received {:tool, _}
  end

  @tag :active_receipts
  @tag timeout: 300_000
  test "active B real checkpoint receipt horizon minus exact plus retains cleanup", c do
    original = active_claim(c)
    reserve = Record.receipt_reserve(original["execution"])
    target = 1024 - reserve - 1

    before =
      Enum.reduce(1..(target - map_size(original["receipts"])), original, fn n, record ->
        assert {:ok, %{record: next}} = cas(c, record, checkpoint(record, "receipt-#{n}"))
        next
      end)

    assert map_size(before["receipts"]) + Record.receipt_reserve(before["execution"]) == 1023
    assert {:ok, %{record: exact}} = cas(c, before, checkpoint(before, "receipt-exact"))
    assert map_size(exact["receipts"]) + Record.receipt_reserve(exact["execution"]) == 1024
    assert {:error, :receipt_limit} = cas(c, exact, checkpoint(exact, "receipt-plus-one"))
    assert {:ok, ^exact} = Store.load_record(c.store, :agent, "run")

    for record <- [before, exact] do
      install(record)
      cleanup(c, record)
    end

    IO.inspect(%{exact: map_size(exact["receipts"]), reserved: reserve},
      label: "ACTIVE_RECEIPT_CAPACITY"
    )

    assert File.read!(c.effects) == "A\n"
    refute_received {:model, _}
    refute_received {:tool, _}
  end

  defp threshold(low, high, _) when low == high, do: low

  defp threshold(low, high, trial) do
    mid = div(low + high, 2)
    if trial.(mid), do: threshold(low, mid, trial), else: threshold(mid + 1, high, trial)
  end

  defp install(record) do
    key = {"sequence-approval", :agent, "run"}
    {:ok, bytes} = Record.encode(record, key)
    {:ok, physical} = Record.key(key)
    :ets.insert(__MODULE__, {physical, bytes})
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  test "public approvals survive resolved batch and output retry across two fresh VMs", c do
    definition = F.definition(c.effects)

    assert {:ok, %{status: :paused}} =
             ExAgent.LegacyStructuralFixture.run(
               definition,
               "input",
               [continuation: c.config, root_options: [estimate_cost: fn _, _ -> 7 end]] ++
                 SequenceApprovalFixture.options()
             )

    assert {:ok, %{record: pending}} = Continuation.get(c.store, "run")
    assert map_size(pending["execution"]["progress"]["approvals"]) == 2
    assert File.read!(c.effects) == "A\n"

    approved =
      Enum.reduce(Map.keys(pending["execution"]["progress"]["approvals"]), pending, fn id, r ->
        assert {:ok, %{record: next}} = SequenceApprovalFixture.decide(c.store, r, id)
        next
      end)

    Agent.update(c.control, fn _ -> {"tool_resolution", :after} end)

    assert {:error, %ExAgent.RunError{partial: partial}} =
             Composition.resume(
               definition,
               SequenceApprovalFixture.reference(approved),
               [
                 continuation: c.config,
                 root_options: [estimate_cost: fn _, _ -> flunk("historical repricing") end]
               ] ++ SequenceApprovalFixture.options()
             )

    assert partial.continuation_checkpoint["command"]["operation"] == "tool_resolution"
    assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
    ready = F.recover(c.store)
    assert :ok = Record.validate(ready, {"sequence-approval", :agent, "run"})

    assert ready["execution"]["progress"]["approvals"] ===
             approved["execution"]["progress"]["approvals"]

    path = c.effects <> ".json"
    File.write!(path, Jason.encode!(ready))
    historical = ready["execution"]["effects"]

    for phase <- ["retry", "finish"] do
      paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

      args =
        ["--erl", "+S 2:2"] ++
          Enum.flat_map(paths, &["-pa", &1]) ++
          ["test/support/sequence_active_evidence_vm.exs", path, c.effects, phase]

      {output, status} =
        System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)

      assert status == 0, output
      assert output =~ "ACTIVE_EVIDENCE_#{phase}"
      next = Jason.decode!(File.read!(path))
      assert Map.take(next["execution"]["effects"], Map.keys(historical)) === historical

      assert next["execution"]["progress"]["approvals"] ===
               approved["execution"]["progress"]["approvals"]
    end

    assert ["A", b1, b2, "C"] = String.split(File.read!(c.effects), "\n", trim: true)
    assert Enum.sort([b1, b2]) == ["B1", "B2"]
  end
end
