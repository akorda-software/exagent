defmodule ExAgent.SequenceResumeTest do
  # This suite checks the historical frame-9 journal/receipt contract. Its fresh
  # sources are authentic CAS/codec-checked 9 records, resumed by the public API.
  # Producer-10 mixed C7, ACK, counters and delegation are tested independently.
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, ExecutionScope, RunError, Store}
  alias ExAgent.Continuation.Record
  alias ExAgent.Coordination.Composition

  defmodule HeldPreflight do
    @behaviour ExAgent.Model
    defstruct [:owner, :control, script: [], index: 0]

    def system(_), do: "test"
    def model_name(_), do: "test"
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}

    def validate_resume(model, _, _, _) do
      if Agent.get(model.control, & &1) == :hold_preflight do
        send(model.owner, {:held_preflight, self()})

        receive do
          :release -> :ok
        end
      end

      :ok
    end

    def request(model, messages, settings, params) do
      test = %ExAgent.Models.Test{script: model.script, index: model.index}
      {:ok, response, next} = ExAgent.Models.Test.request(test, messages, settings, params)
      {:ok, response, %{model | index: next.index}}
    end
  end

  defmodule Journal do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, query), do: Store.ETS.scan_records(c.table, ns, query)

    def transition(c, key, revision, command) do
      operation = command["operation"]
      children = get_in(command, ["payload", "progress", "runtime", "children"]) || %{}
      child = children |> Map.values() |> Enum.max_by(& &1["link"]["index"], fn -> %{} end)
      step = child["link"]["step_id"]

      fault =
        Agent.get_and_update(c.control, fn
          {^operation, mode} -> {mode, nil}
          {^operation, ^step, mode} -> {mode, nil}
          other -> {nil, other}
        end)

      if fault == :barrier do
        send(c.owner, {:claim_barrier, self()})

        receive do
          :release -> :ok
        end
      end

      result =
        if fault == :before,
          do: {:error, :before_commit},
          else: Store.ETS.transition(c.table, key, revision, command)

      if fault == :ack_barrier do
        send(c.owner, {:claim_ack_barrier, self()})

        receive do
          :release -> :ok
        end
      end

      if fault in [:before, :after], do: send(c.owner, {:fault_boundary, operation, step})

      if fault == :after, do: {:error, :lost_ack}, else: result
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    control = start_supervised!({Agent, fn -> nil end})
    owner = self()
    effects = "/tmp/opencode/sequence-resume-effects-#{System.unique_integer([:positive])}"
    File.write!(effects, "")
    on_exit(fn -> File.rm(effects) end)

    store =
      Store.scoped(
        {Journal, %{table: __MODULE__, control: control, owner: owner}},
        "resume-sequence"
      )

    steps =
      for id <- ~w(A B C) do
        %{
          id: id,
          agent:
            ExAgent.new(
              model: %ExAgent.Models.Test{
                script: [
                  fn _, _ ->
                    File.write!(effects, id <> "\n", [:append])
                    send(owner, {:effect, id})
                    id <> " output"
                  end
                ]
              }
            ),
          definition: %{id: "leaf", version: "1"},
          policy: %{id: "policy", version: "1"},
          model_ref: %{id: "model", version: "1"},
          output_ref: %{id: "output", version: "1"},
          model_codec: %{
            dump: fn m -> {:ok, %{"index" => m.index}} end,
            load: fn m, d ->
              send(owner, {:load, id})
              {:ok, %{m | index: d["index"]}}
            end
          }
        }
      end

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

    config = %{
      store: store,
      id: "run",
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000,
      on_writer: fn pid ->
        send(owner, {:writer, pid})
        :ok
      end
    }

    %{definition: definition, config: config, store: store, control: control, effects: effects}
  end

  defp reference(record),
    do: %{
      version: 1,
      id: "run",
      record_id: record["record_id"],
      revision: record["revision"],
      run_id: record["execution"]["run_id"]
    }

  defp recover(c) do
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    wait = max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

    receive do
    after
      wait -> :ok
    end

    assert {:ok, %{record: ready}} =
             Continuation.recover(c.store, "run",
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "recover",
               actor: "host",
               authorize: fn actor, _, _ -> {:ok, actor} end
             )

    ready
  end

  defp stopped(c, mode, opts \\ []) do
    Agent.update(c.control, fn _ -> mode end)

    assert {:error, %RunError{}} =
             ExAgent.LegacyStructuralFixture.run(
               c.definition,
               "initial",
               Keyword.merge(opts, continuation: %{c.config | lease_ms: 1_000})
             )

    assert_receive {:writer, pid}
    refute Process.alive?(pid)
    recover(c)
  end

  for {label, fault} <- [
        {"betweenA", {"step_output", "A", :after}},
        {"inputB", {"step_input", "B", :after}},
        {"terminalB", {"outcome", "B", :after}}
      ] do
    test "fresh VM #{label}: real A effect once and only suffix", c do
      ready = stopped(c, unquote(Macro.escape(fault)))
      assert File.read!(c.effects) == if(unquote(label) == "terminalB", do: "A\nB\n", else: "A\n")
      path = c.effects <> ".json"
      File.write!(path, Jason.encode!(ready))
      on_exit(fn -> File.rm(path) end)
      paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

      args =
        ["--erl", "+S 2:2"] ++
          Enum.flat_map(paths, &["-pa", &1]) ++
          ["test/support/sequence_resume_vm.exs", path, c.effects]

      {output, status} =
        System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)

      assert status == 0, output
      assert output =~ "SEQUENCE_RESUME_VM"
      assert File.read!(c.effects) == "A\nB\nC\n"
    end
  end

  for {operation, step} <- [
        {"claim", nil},
        {"step_output", "B"},
        {"step_input", "C"},
        {"begin_effect", "C"}
      ] do
    test "resume capacity ±1 at #{operation}/#{step}: real Writer command and bounded token", c do
      ready = stopped(c, {"outcome", "B", :after})
      assert_receive {:fault_boundary, "outcome", "B"}
      key = {c.store.namespace, :agent, "run"}
      {:ok, physical} = Record.key(key)
      {:ok, bytes} = Record.encode(ready, key)
      operation = unquote(operation)
      step = unquote(step)

      trial = fn limit ->
        true = :ets.insert(__MODULE__, {physical, bytes})
        Agent.update(c.control, fn _ -> {operation, step, :before} end)

        assert {:error, %RunError{partial: partial}} =
                 Composition.resume(
                   c.definition,
                   reference(ready),
                   continuation: Map.put(c.config, :max_checkpoint_bytes, limit)
                 )

        hit =
          receive do
            {:fault_boundary, ^operation, ^step} -> true
          after
            0 -> false
          end

        assert File.read!(c.effects) == "A\nB\n"

        if partial.continuation_checkpoint do
          assert ExAgent.Retention.bytes(partial.continuation_checkpoint) <= limit
        end

        {hit, partial}
      end

      assert {true, _} = trial.(512_000)
      threshold = capacity_threshold(1, 512_000, trial)
      assert {false, _} = trial.(threshold - 1)
      assert {true, at} = trial.(threshold)
      assert {true, _} = trial.(threshold + 1)
      assert at.error_phase == :checkpoint
      assert at.continuation_checkpoint["command"]["operation"] == operation

      IO.inspect(
        %{
          operation: operation,
          step: step,
          exact: threshold,
          token: ExAgent.Retention.bytes(at.continuation_checkpoint)
        },
        label: "RESUME_CAPACITY"
      )
    end
  end

  defp capacity_threshold(low, high, _) when low == high, do: low

  defp capacity_threshold(low, high, trial) do
    middle = div(low + high, 2)

    case trial.(middle) do
      {true, _} -> capacity_threshold(low, middle, trial)
      {false, _} -> capacity_threshold(middle + 1, high, trial)
    end
  end

  test "terminal B output ACK is required before C input and IO", c do
    ready = stopped(c, {"outcome", "B", :after})
    Agent.update(c.control, fn _ -> {"step_output", "B", :after} end)

    assert {:error, %RunError{partial: partial}} =
             Composition.resume(
               c.definition,
               reference(ready),
               continuation: c.config
             )

    assert partial.error_phase == :checkpoint
    assert Enum.map(partial.steps, & &1.status) == [:completed, :running, :not_started]
    assert File.read!(c.effects) == "A\nB\n"
    assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
    assert File.read!(c.effects) == "A\nB\n"
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["progress"]["runtime"]["cursor"] == "between_steps"
  end

  test "completed tool/retry prefix preserved while typed success B feeds C", c do
    alias ExAgent.Message.Part.ToolCall
    output = ExAgent.CompositionOutputSuccessFixture.Output
    effect = c.effects

    tool =
      ExAgent.Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          File.write!(effect, "A\n", [:append])
          {:ok, "done"}
        end
      )

    [a, b, last] = c.definition.steps

    a = %{
      a
      | agent:
          ExAgent.new(
            tools: [tool],
            model: %ExAgent.Models.Test{
              script: [
                {:tool_calls,
                 [%ToolCall{tool_name: "effect", tool_call_id: "reused-provider-id", args: %{}}]},
                "A output"
              ]
            }
          )
    }

    b = %{
      b
      | agent:
          ExAgent.new(
            output_type: output,
            model: %ExAgent.Models.Test{
              script: [
                {:tool_calls,
                 [
                   %ToolCall{
                     tool_name: "final_result",
                     tool_call_id: "reused-provider-id",
                     args: %{}
                   }
                 ]},
                {:tool_calls,
                 [
                   %ToolCall{
                     tool_name: "final_result",
                     tool_call_id: "reused-provider-id",
                     args: %{"count" => 7}
                   }
                 ]}
              ]
            }
          )
    }

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [a, b, last])
    c = %{c | definition: definition}
    # The first typed resolution is retry; stop only the succeeded attestation.
    Agent.update(c.control, fn _ -> {"step_output", "B", :before} end)

    assert {:error, _} =
             ExAgent.LegacyStructuralFixture.run(definition, "initial",
               continuation: %{c.config | lease_ms: 1_000}
             )

    assert_receive {:writer, _}
    ready = recover(c)
    before = ready["execution"]["progress"]["runtime"]

    a_id =
      Enum.find_value(before["children"], fn {id, ch} ->
        if ch["link"]["step_id"] == "A", do: id
      end)

    assert {:ok, result} =
             Composition.resume(definition, reference(ready), continuation: c.config)

    assert Enum.at(result.steps, 2).input == %{"count" => 7}
    assert result.request_count == 5 and result.tool_calls == 1
    assert File.read!(c.effects) == "A\nC\n"
    assert_receive {:load, "B"}
    refute_receive {:load, "A"}
    {:ok, completed} = Store.load_record(c.store, :agent, "run")
    after_frame = completed["execution"]["progress"]["runtime"]
    assert after_frame["children"][a_id] == before["children"][a_id]

    assert Map.take(after_frame["tool_batches"], Map.keys(before["tool_batches"])) ==
             before["tool_batches"]

    assert :ok = Record.validate(completed, {c.store.namespace, :agent, "run"})
  end

  test "owner killed during resumed mapping closes Writer and Scope; no successor input", c do
    owner = self()

    steps =
      Enum.map(c.definition.steps, fn
        %{id: "B"} = step ->
          Map.merge(step, %{
            input_version: "1",
            input: fn _, _ ->
              send(owner, {:mapping_held, self()})

              receive do
                :release_mapping -> {:ok, "B"}
              end
            end
          })

        step ->
          step
      end)

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)
    c = %{c | definition: definition}
    ready = stopped(c, {"step_output", :after})

    caller =
      spawn(fn -> Composition.resume(definition, reference(ready), continuation: c.config) end)

    assert_receive {:writer, writer}
    assert_receive {:mapping_held, ^writer}
    {:monitored_by, watchers} = Process.info(caller, :monitored_by)

    scope =
      Enum.find(watchers, fn pid ->
        case Process.info(pid, :dictionary) do
          {:dictionary, dict} -> dict[:"$initial_call"] == {ExAgent.ExecutionScope, :init, 1}
          _ -> false
        end
      end)

    assert is_pid(scope)
    monitors = for pid <- [caller, writer, scope], do: {pid, Process.monitor(pid)}
    Process.exit(caller, :kill)
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1000)
    assert File.read!(c.effects) == "A\n"
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["progress"]["runtime"]["cursor"] == "between_steps"
    assert map_size(record["execution"]["progress"]["runtime"]["children"]) == 1
  end

  test "resumed terminal checkpoint token ±1 enforces public bound before CAS", c do
    ready = stopped(c, {"outcome", "B", :after})
    Agent.update(c.control, fn _ -> {"step_output", "B", :before} end)

    assert {:error, %RunError{partial: partial}} =
             Composition.resume(
               c.definition,
               reference(ready),
               continuation: c.config
             )

    token = partial.continuation_checkpoint
    frame = token["command"]["payload"]["progress"]["runtime"]
    node = ExAgent.Continuation.Frame.active_step_id(frame)

    path = [
      "command",
      "payload",
      "progress",
      "runtime",
      "children",
      node,
      "snapshot",
      "metadata",
      "padding"
    ]

    base = put_in(token, path, "")
    room = Record.max_bytes() - ExAgent.Retention.bytes(base)
    {:ok, before} = Store.load_record(c.store, :agent, "run")

    for delta <- [-1, 0, 1] do
      candidate = put_in(base, path, String.duplicate("x", room + delta))
      assert ExAgent.Retention.bytes(candidate) == Record.max_bytes() + delta
      assert {:error, reason} = Continuation.retry_checkpoint(c.store, candidate)
      assert reason == if(delta <= 0, do: :record_limit, else: :invalid_checkpoint_token)
      assert {:ok, ^before} = Store.load_record(c.store, :agent, "run")
      assert File.read!(c.effects) == "A\nB\n"
    end
  end

  test "completed typed retry history is inert while terminal text B advances", c do
    alias ExAgent.Message.Part.ToolCall
    [a, b, last] = c.definition.steps

    a = %{
      a
      | agent:
          ExAgent.new(
            output_type: ExAgent.CompositionOutputSuccessFixture.Output,
            model: %ExAgent.Models.Test{
              script: [
                {:tool_calls,
                 [%ToolCall{tool_name: "final_result", tool_call_id: "same", args: %{}}]},
                {:tool_calls,
                 [
                   %ToolCall{
                     tool_name: "final_result",
                     tool_call_id: "same",
                     args: %{"count" => 7}
                   }
                 ]}
              ]
            }
          )
    }

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [a, b, last])
    c = %{c | definition: definition}
    ready = stopped(c, {"outcome", "B", :after})

    forbidden = %{
      dump: fn _ -> raise "history dump" end,
      load: fn _, _ -> raise "history load" end
    }

    a = %{a | model_codec: forbidden}
    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [a, b, last])

    assert {:ok, result} =
             Composition.resume(definition, reference(ready),
               continuation: c.config,
               step_options: %{"A" => [on_event: fn _ -> raise "history event" end]}
             )

    assert result.request_count == 4
    assert hd(result.steps).output == %{"count" => 7}
    assert File.read!(c.effects) == "B\nC\n"
    assert_receive {:load, "B"}
    refute_receive {:load, "A"}
  end

  test "historical prices retained exactly with new estimator only on suffix", c do
    steps =
      Enum.map(c.definition.steps, fn step ->
        put_in(step, [:agent, Access.key(:model), Access.key(:label)], step.id)
      end)

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)
    c = %{c | definition: definition}
    ready = stopped(c, {"step_output", :after}, root_options: [estimate_cost: fn _, _ -> 7 end])
    owner = self()

    assert {:ok, result} =
             Composition.resume(c.definition, reference(ready),
               continuation: c.config,
               root_options: [
                 estimate_cost: fn model, _ ->
                   send(owner, {:estimated, model.label})
                   99
                 end
               ]
             )

    assert result.cost_cents == 205
    assert_receive {:estimated, "B"}
    assert_receive {:estimated, "C"}
    refute_receive {:estimated, "A"}
  end

  test "current expired TTL and incompatible binding reject without claim or codec", c do
    ready = stopped(c, {"step_input", :after})

    assert {:error, %RunError{reason: :expired}} =
             Composition.resume(
               c.definition,
               reference(ready),
               continuation: %{c.config | expires_at: System.system_time(:millisecond) - 1}
             )

    {:ok, changed} = Composition.new(id: "sequence", version: "2", steps: c.definition.steps)

    assert {:error, %RunError{reason: :composition_definition_changed, partial: partial}} =
             Composition.resume(changed, reference(ready), continuation: c.config)

    assert partial.continuation == nil
    assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
    refute_receive {:writer, _}
    refute_receive {:load, _}
    assert File.read!(c.effects) == ""
  end

  test "active typed retry resumes B and then C without replaying A", c do
    alias ExAgent.Message.Part.ToolCall
    [a, b, last] = c.definition.steps

    b = %{
      b
      | agent:
          ExAgent.new(
            output_type: ExAgent.CompositionOutputSuccessFixture.Output,
            model: %ExAgent.Models.Test{
              script: [
                {:tool_calls,
                 [%ToolCall{tool_name: "final_result", tool_call_id: "same", args: %{}}]},
                {:tool_calls,
                 [
                   %ToolCall{
                     tool_name: "final_result",
                     tool_call_id: "same",
                     args: %{"count" => 7}
                   }
                 ]}
              ]
            }
          )
    }

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [a, b, last])
    c = %{c | definition: definition}
    ready = stopped(c, {"output_resolution", "B", :after})

    assert {:ok, result} =
             Composition.resume(definition, reference(ready), continuation: c.config)

    assert result.status == :completed
    assert Enum.at(result.steps, 1).output == %{"count" => 7}
    assert {:ok, completed} = Store.load_record(c.store, :agent, "run")
    assert completed["execution"]["fence"] == ready["execution"]["fence"] + 2
    assert File.read!(c.effects) == "A\nC\n"
    assert_receive {:load, "B"}
    refute_receive {:load, "A"}
  end

  test "active terminal text after tools resumes without replaying B tool", c do
    alias ExAgent.Message.Part.ToolCall
    [a, b, last] = c.definition.steps
    path = c.effects

    tool =
      ExAgent.Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          File.write!(path, "B\n", [:append])
          {:ok, "done"}
        end
      )

    b = %{
      b
      | agent:
          ExAgent.new(
            tools: [tool],
            model: %ExAgent.Models.Test{
              script: [
                {:tool_calls, [%ToolCall{tool_name: "effect", tool_call_id: "same", args: %{}}]},
                "B output"
              ]
            }
          )
    }

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [a, b, last])
    c = %{c | definition: definition}
    ready = stopped(c, {"step_output", "B", :before})

    assert {:ok, result} =
             Composition.resume(definition, reference(ready), continuation: c.config)

    assert result.status == :completed
    assert Enum.at(result.steps, 1).output == "B output"
    assert {:ok, completed} = Store.load_record(c.store, :agent, "run")
    assert completed["execution"]["fence"] == ready["execution"]["fence"] + 2
    assert File.read!(c.effects) == "A\nB\nC\n"
    assert_receive {:load, "B"}
    refute_receive {:load, "A"}
  end

  test "global orphan evidence is rejected before local active classification", c do
    ready = stopped(c, {"outcome", "B", :after})
    [effect | _] = Map.keys(ready["execution"]["effects"])

    invalid =
      put_in(ready, ["execution", "effects", effect, "intent", "payload", "run_id"], "orphan")

    {:ok, physical} = Record.key({c.store.namespace, :agent, "run"})
    true = :ets.insert(__MODULE__, {physical, Jason.encode!(invalid)})

    assert {:error, %RunError{partial: partial}} =
             Composition.resume(c.definition, reference(ready), continuation: c.config)

    assert partial.continuation == nil
    assert File.read!(c.effects) == "A\nB\n"
    refute_receive {:writer, _}
    refute_receive {:load, _}
  end

  test "unresolved Model intent recovers uncertain and never executes", c do
    ready = stopped(c, {"begin_effect", "B", :after})
    assert ready["execution"]["state"] == "uncertain"

    assert {:error, %RunError{reason: :composition_not_ready}} =
             Composition.resume(c.definition, reference(ready), continuation: c.config)

    assert File.read!(c.effects) == "A\n"
    refute_receive {:writer, _}
    refute_receive {:load, _}
  end

  test "empty ready resumes after failed claim without admin recovery", c do
    Agent.update(c.control, fn _ -> {"claim", :before} end)

    assert {:error, %RunError{}} =
             ExAgent.LegacyStructuralFixture.run(c.definition, "initial", continuation: c.config)

    {:ok, ready} = Store.load_record(c.store, :agent, "run")
    assert ready["execution"]["state"] == "ready"
    assert ready["execution"]["progress"]["runtime"]["cursor"] == "empty"

    assert {:ok, result} =
             Composition.resume(c.definition, reference(ready), continuation: c.config)

    assert result.request_count == 3
    assert File.read!(c.effects) == "A\nB\nC\n"
  end

  test "expired historical leaf deadline does not block suffix; current root deadline does", c do
    ready =
      stopped(c, {"step_output", :after},
        step_options: %{"A" => [deadline: System.monotonic_time(:millisecond) + 500]}
      )

    assert {:error, %RunError{reason: :deadline_exceeded, partial: partial}} =
             Composition.resume(c.definition, reference(ready),
               continuation: c.config,
               root_options: [deadline: System.monotonic_time(:millisecond) - 1]
             )

    assert partial.continuation.revision == ready["revision"]
    assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")

    assert {:ok, result} =
             Composition.resume(c.definition, reference(ready), continuation: c.config)

    assert result.request_count == 3
    assert File.read!(c.effects) == "A\nB\nC\n"
  end

  test "current root deadline is enforced by CAS after a delayed claim", c do
    ready = stopped(c, {"step_input", :after})
    Agent.update(c.control, fn _ -> {"claim", :barrier} end)
    deadline = System.monotonic_time(:millisecond) + 1_000

    caller =
      Task.async(fn ->
        Composition.resume(c.definition, reference(ready),
          continuation: c.config,
          root_options: [deadline: deadline]
        )
      end)

    assert_receive {:claim_barrier, writer}

    receive do
    after
      max(deadline - System.monotonic_time(:millisecond) + 1, 0) -> :ok
    end

    send(writer, :release)

    assert {:error,
            %RunError{reason: {:continuation_checkpoint_failed, :expired}, partial: partial}} =
             Task.await(caller)

    assert partial.error_phase == :checkpoint
    assert partial.continuation.revision == ready["revision"]
    assert partial.continuation_checkpoint["command"]["payload"]["deadline_at"] != nil
    assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
    refute_receive {:writer, _}
    refute_receive {:load, _}
    assert File.read!(c.effects) == ""
  end

  test "late successful claim ACK rechecks current leaf deadline before owner and codec", c do
    ready = stopped(c, {"step_input", :after})
    Agent.update(c.control, fn _ -> {"claim", :ack_barrier} end)
    deadline = System.monotonic_time(:millisecond) + 1_000

    caller =
      Task.async(fn ->
        Composition.resume(c.definition, reference(ready),
          continuation: c.config,
          step_options: %{"A" => [deadline: deadline]}
        )
      end)

    assert_receive {:claim_ack_barrier, writer}

    receive do
    after
      max(deadline - System.monotonic_time(:millisecond) + 1, 0) -> :ok
    end

    send(writer, :release)
    assert {:error, %RunError{reason: :deadline_exceeded, partial: partial}} = Task.await(caller)
    assert partial.error_phase == :open
    assert partial.continuation.revision == ready["revision"] + 1
    assert partial.continuation_checkpoint == nil
    refute_receive {:writer, _}
    refute_receive {:load, _}
    assert File.read!(c.effects) == ""
  end

  test "claim ACK delivered after lease expiry grants no owner or codec", c do
    ready = stopped(c, {"step_input", :after})
    Agent.update(c.control, fn _ -> {"claim", :ack_barrier} end)

    caller =
      Task.async(fn ->
        Composition.resume(c.definition, reference(ready),
          continuation: %{c.config | lease_ms: 1_000}
        )
      end)

    assert_receive {:claim_ack_barrier, writer}
    {:ok, claimed} = Store.load_record(c.store, :agent, "run")
    wait = max(claimed["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

    receive do
    after
      wait -> :ok
    end

    send(writer, :release)
    assert {:error, %RunError{reason: :lease_expired, partial: partial}} = Task.await(caller)
    assert partial.error_phase == :open
    assert partial.continuation.revision == claimed["revision"]
    assert partial.continuation_checkpoint == nil
    assert {:ok, ^claimed} = Store.load_record(c.store, :agent, "run")
    refute_receive {:writer, _}
    refute_receive {:load, _}
    assert File.read!(c.effects) == ""
  end

  test "unlimited history can be tightened to finite resumed budget and refunded once", c do
    ready = stopped(c, {"outcome", "B", :after})
    assert ready["execution"]["progress"]["active_budget"]["limit_ms"] == nil
    config = Map.put(c.config, :active_time_limit_ms, 60_000)

    assert {:ok, result} =
             Composition.resume(c.definition, reference(ready), continuation: config)

    {:ok, completed} = Store.load_record(c.store, :agent, "run")
    budget = completed["execution"]["progress"]["active_budget"]
    assert budget["limit_ms"] == 60_000
    assert budget["remaining_ms"] > 0 and budget["remaining_ms"] <= 60_000
    assert budget["reserved_ms"] == nil and budget["refund_at"] == nil

    assert {:ok, ^result} =
             Composition.resume(c.definition, result.continuation, continuation: config)

    assert {:ok, ^completed} = Store.load_record(c.store, :agent, "run")
    assert File.read!(c.effects) == "A\nB\nC\n"
  end

  for {options, reason} <- [
        {[usage_limits: :invalid], :invalid_usage_limits},
        {[permission_floors: :invalid], :invalid_execution_scope_options},
        {[max_concurrent_requests: 0], :invalid_execution_scope_options},
        {[estimate_cost: :invalid], :invalid_execution_scope_options}
      ] do
    test "invalid root values #{inspect(options)} reject before durable claim", c do
      ready = stopped(c, {"step_output", "A", :after})
      assert_receive {:effect, "A"}

      assert {:error, %RunError{reason: unquote(reason)}} =
               Composition.resume(c.definition, reference(ready),
                 continuation: Map.put(c.config, :active_time_limit_ms, 600),
                 root_options: unquote(Macro.escape(options))
               )

      assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
      refute_receive {:writer, _}
      refute_receive {:load, _}
      refute_receive {:effect, _}
      assert File.read!(c.effects) == "A\n"
    end
  end

  test "model-unaware root estimator rejects before claim without invocation", c do
    ready = stopped(c, {"step_output", "A", :after})
    assert_receive {:effect, "A"}
    owner = self()

    estimator = fn _ ->
      send(owner, :unexpected_estimator)
      0
    end

    assert {:error, %RunError{reason: :structural_scope_requires_model_aware_estimator}} =
             Composition.resume(c.definition, reference(ready),
               continuation: Map.put(c.config, :active_time_limit_ms, 600),
               root_options: [estimate_cost: estimator]
             )

    assert {:ok, ^ready} = Store.load_record(c.store, :agent, "run")
    refute_receive :unexpected_estimator
    refute_receive {:writer, _}
    refute_receive {:load, _}
    refute_receive {:effect, _}
    assert File.read!(c.effects) == "A\n"
  end

  for held <- [:owner, :codec, :preflight, :successor_preflight] do
    test "finite attempt origin survives held #{held} before active IO", c do
      assert_held_budget(c, unquote(held))
    end
  end

  defp assert_held_budget(c, held) do
    successor? = held == :successor_preflight
    held = if successor?, do: :preflight, else: held
    owner = self()

    definition =
      if held == :preflight do
        Map.update!(c.definition, :steps, fn steps ->
          Enum.map(steps, fn step ->
            model = %HeldPreflight{
              owner: owner,
              control: c.control,
              script: step.agent.model.script
            }

            put_in(step.agent.model, model)
          end)
        end)
      else
        c.definition
      end

    c = %{c | definition: definition}
    ready = stopped(c, {if(successor?, do: "step_output", else: "step_input"), "A", :after})
    if successor?, do: assert_receive({:effect, "A"})

    hold = fn ->
      send(owner, {:held_budget, self()})

      receive do
        :release -> :ok
      end
    end

    definition =
      if held == :codec do
        update_in(definition.steps, fn [first | rest] ->
          first =
            put_in(first.model_codec.load, fn m, d ->
              hold.()
              {:ok, %{m | index: d["index"]}}
            end)

          [first | rest]
        end)
      else
        definition
      end

    config = Map.put(c.config, :active_time_limit_ms, 600)

    config =
      if held == :owner, do: Map.put(config, :on_writer, fn _ -> hold.() end), else: config

    if held == :preflight, do: Agent.update(c.control, fn _ -> :hold_preflight end)

    caller =
      Task.async(fn ->
        Composition.resume(definition, reference(ready), continuation: config)
      end)

    callback =
      if held == :preflight do
        assert_receive {:held_preflight, pid}
        pid
      else
        assert_receive {:held_budget, pid}
        pid
      end

    assert {:ok, claimed} = Store.load_record(c.store, :agent, "run")
    assert claimed["execution"]["progress"]["active_budget"]["reserved_ms"] == 600

    # Real elapsed budget, after the callback barrier proves the claim ACK.
    receive do
    after
      601 -> :ok
    end

    send(callback, :release)

    assert {:error, %RunError{reason: :deadline_exceeded, partial: partial}} =
             Task.await(caller)

    assert partial.continuation.revision == claimed["revision"]
    assert partial.continuation_checkpoint == nil
    assert {:ok, ^claimed} = Store.load_record(c.store, :agent, "run")
    refute_receive {:effect, _}
    if held == :owner, do: refute_receive({:load, _})
    assert File.read!(c.effects) == if(successor?, do: "A\n", else: "")
  end

  test "finite budget starts at fresh ACK, while delayed ACK still retains lease bounds", c do
    ready = stopped(c, {"step_input", "A", :after})
    Agent.update(c.control, fn _ -> {"claim", :ack_barrier} end)

    caller =
      Task.async(fn ->
        Composition.resume(c.definition, reference(ready),
          continuation: Map.put(c.config, :active_time_limit_ms, 600)
        )
      end)

    assert_receive {:claim_ack_barrier, writer}
    assert {:ok, claimed} = Store.load_record(c.store, :agent, "run")
    assert claimed["execution"]["progress"]["active_budget"]["reserved_ms"] == 600

    receive do
    after
      601 -> :ok
    end

    send(writer, :release)
    assert {:ok, result} = Task.await(caller)
    assert result.request_count == 3
    assert File.read!(c.effects) == "A\nB\nC\n"
    assert {:ok, completed} = Store.load_record(c.store, :agent, "run")
    budget = completed["execution"]["progress"]["active_budget"]
    assert budget["reserved_ms"] == nil
    assert budget["remaining_ms"] > 0 and budget["remaining_ms"] <= 600
  end

  test "killing resumed Model B closes all owned processes and retains uncertain intent", c do
    owner = self()
    [a, b, last] = c.definition.steps

    b = %{
      b
      | agent:
          ExAgent.new(
            model: %ExAgent.Models.Test{
              script: [
                fn _, _ ->
                  send(owner, {:model_held, self()})

                  receive do
                    :release_model -> "B output"
                  end
                end
              ]
            }
          )
    }

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [a, b, last])
    c = %{c | definition: definition}
    ready = stopped(c, {"step_input", "B", :after})

    caller =
      spawn(fn ->
        Composition.resume(definition, reference(ready),
          continuation: %{c.config | lease_ms: 1_000}
        )
      end)

    assert_receive {:writer, writer}
    assert_receive {:model_held, model}
    {:monitored_by, watchers} = Process.info(caller, :monitored_by)

    scope =
      Enum.find(watchers, fn pid ->
        case Process.info(pid, :dictionary) do
          {:dictionary, dict} -> dict[:"$initial_call"] == {ExAgent.ExecutionScope, :init, 1}
          _ -> false
        end
      end)

    assert is_pid(scope)

    monitors =
      for pid <- Enum.uniq([caller, writer, scope, model]), do: {pid, Process.monitor(pid)}

    Process.exit(caller, :kill)
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1000)
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    wait = max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)

    receive do
    after
      wait -> :ok
    end

    assert {:ok, %{record: uncertain}} =
             Continuation.recover(c.store, "run",
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "recover-model",
               actor: "host",
               authorize: fn actor, _, _ -> {:ok, actor} end
             )

    assert uncertain["execution"]["state"] == "uncertain"
    assert File.read!(c.effects) == "A\n"

    assert {:error, %RunError{reason: :composition_not_ready}} =
             Composition.resume(
               definition,
               reference(uncertain),
               continuation: c.config
             )
  end

  test "between steps recovers only suffix, exact accounting and completed data-only", c do
    ready = stopped(c, {"step_output", :after})
    assert_receive {:effect, "A"}

    assert {:ok, result} =
             Composition.resume(c.definition, reference(ready), continuation: c.config)

    assert result.output == "C output" and result.request_count == 3
    assert Enum.map(result.steps, & &1.input) == ["initial", "A output", "B output"]
    assert_receive {:effect, "B"}
    assert_receive {:effect, "C"}
    refute_receive {:effect, "A"}
    refute_receive {:load, _}
    assert_receive {:writer, pid}
    refute Process.alive?(pid)

    assert {:ok, ^result} =
             Composition.resume(c.definition, result.continuation,
               continuation: c.config,
               root_options: [deadline: System.monotonic_time(:millisecond) - 1]
             )

    refute_receive {:writer, _}
    refute_receive {:effect, _}
  end

  test "confirmed input restores active codec only and does not remap", c do
    ready = stopped(c, {"step_input", :after})

    assert {:ok, result} =
             Composition.resume(c.definition, reference(ready), continuation: c.config)

    assert result.request_count == 3
    assert_receive {:load, "A"}
    for id <- ~w(A B C), do: assert_receive({:effect, ^id})
    refute_receive {:load, _}
  end

  test "claim ACK loss keeps preclaim baseline and token; token retry performs no IO", c do
    ready = stopped(c, {"step_output", :after})
    assert_receive {:effect, "A"}
    Agent.update(c.control, fn _ -> {"claim", :after} end)

    assert {:error, %RunError{partial: partial}} =
             Composition.resume(
               c.definition,
               reference(ready),
               continuation: c.config
             )

    assert partial.error_phase == :checkpoint
    assert partial.continuation.revision == ready["revision"]
    assert partial.usage_status == :partial
    assert is_map(partial.continuation_checkpoint)
    refute_receive {:writer, _}
    refute_receive {:effect, _}
    refute_receive {:load, _}
    assert {:ok, _} = Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)
    refute_receive {:effect, _}
  end

  test "finite abandoned budget rejects without owner or codec", c do
    c = %{c | config: Map.put(c.config, :active_time_limit_ms, 60_000)}
    ready = stopped(c, {"step_input", :after})

    assert {:error, %RunError{reason: :active_budget_exhausted, partial: %{error_phase: :open}}} =
             Composition.resume(c.definition, reference(ready), continuation: c.config)

    refute_receive {:writer, _}
    refute_receive {:load, _}
    refute_receive {:effect, _}
  end

  test "closed-tree import is atomic, exact, owner-bound and cannot reactivate history", c do
    ready = stopped(c, {"step_output", :after})
    frame = ready["execution"]["progress"]["runtime"]
    {:ok, root} = ExecutionScope.start_structural(frame["run_id"], [])
    on_exit(fn -> ExecutionScope.stop(root) end)
    before = :sys.get_state(root.pid)

    assert {:error, :invalid_scope_checkpoint} =
             Task.async(fn ->
               ExecutionScope.restore_composition_tree(root, frame)
             end)
             |> Task.await()

    [leaf] = Map.keys(frame["children"])
    invalid = put_in(frame, ["scope", "nodes"], Map.delete(frame["scope"]["nodes"], leaf))

    assert {:error, :invalid_scope_checkpoint} =
             ExecutionScope.restore_composition_tree(root, invalid)

    assert :sys.get_state(root.pid) == before
    assert :ok = ExecutionScope.restore_composition_tree(root, frame)
    state = :sys.get_state(root.pid)
    [{token, closed}] = Enum.reject(state.nodes, fn {_, n} -> n.structural end)
    refute closed.active or closed.structural
    assert closed.monitor == nil and closed.guardian == nil and closed.approve == nil
    handle = %{root | token: token, run_id: leaf, parent_run_id: root.run_id}
    assert {:error, :execution_scope_closed} = ExecutionScope.check(handle)

    assert {:error, :duplicate_run_id} =
             ExecutionScope.join(root, leaf, %ExAgent.Models.Test{}, [])

    assert {:ok, restored} = ExecutionScope.export_tree(root)
    assert restored == frame["scope"]

    assert {:error, :invalid_scope_checkpoint} =
             ExecutionScope.restore_composition_tree(root, frame)
  end

  test "two claimants one CAS winner; loser has no codec, mapping or writer callback", c do
    ready = stopped(c, {"step_input", :after})
    Agent.update(c.control, fn _ -> {"claim", :barrier} end)

    first =
      Task.async(fn ->
        Composition.resume(c.definition, reference(ready), continuation: c.config)
      end)

    assert_receive {:claim_barrier, waiting}

    second =
      Task.async(fn ->
        Composition.resume(c.definition, reference(ready), continuation: c.config)
      end)

    assert {:ok, result} = Task.await(second)
    send(waiting, :release)
    assert {:error, %RunError{}} = Task.await(first)
    assert result.request_count == 3
    assert File.read!(c.effects) == "A\nB\nC\n"
    assert_receive {:writer, pid}
    refute Process.alive?(pid)
    assert_receive {:load, "A"}
    refute_receive {:writer, _}
    refute_receive {:load, _}
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert :ok = Record.validate(record, {c.store.namespace, :agent, "run"})
  end

  test "historical root request quota blocks suffix without historical callbacks", c do
    ready = stopped(c, {"step_output", :after})

    assert {:error,
            %RunError{reason: {:usage_limit_exceeded, :request_limit, 1}, partial: partial}} =
             Composition.resume(c.definition, reference(ready),
               continuation: c.config,
               root_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 1}]
             )

    assert partial.error_phase == :prepare and partial.error_step_id == "B"
    assert partial.request_count == 1
    assert File.read!(c.effects) == "A\n"
    refute_receive {:load, _}
  end

  test "claimed is not auto-recovered; strict refs and options reject before callbacks", c do
    Agent.update(c.control, fn _ -> {"step_output", :after} end)

    assert {:error, _} =
             ExAgent.LegacyStructuralFixture.run(c.definition, "initial", continuation: c.config)

    assert_receive {:writer, _}
    assert_receive {:effect, "A"}
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    ref = reference(record)

    assert {:error, %RunError{reason: :composition_not_ready}} =
             Composition.resume(c.definition, ref, continuation: c.config)

    for invalid <- [
          Map.delete(ref, :version),
          %{ref | version: 1.0},
          Map.put(ref, :token, "x"),
          Map.put(ref, :attempt_id, 3)
        ] do
      assert {:error, %RunError{reason: :invalid_composition_restore}} =
               Composition.resume(c.definition, invalid, continuation: c.config)
    end

    assert {:error, %RunError{reason: :continuation_conflict}} =
             Composition.resume(c.definition, %{ref | revision: ref.revision + 1},
               continuation: c.config
             )

    assert {:error, %RunError{reason: :invalid_composition_options}} =
             Composition.resume(c.definition, ref,
               continuation: c.config,
               step_options: %{"A" => [run_id: "x"]}
             )

    assert {:ok, ^record} = Store.load_record(c.store, :agent, "run")
    refute_receive {:writer, _}
  end
end
