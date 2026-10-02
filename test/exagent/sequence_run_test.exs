defmodule ExAgent.SequenceRunTest do
  use ExUnit.Case, async: false
  alias ExAgent.Coordination.Composition
  alias ExAgent.Continuation.Record, as: ContinuationRecord
  alias ExAgent.{RunError, Store}
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  defmodule Processor do
    def on_start(_, span, _), do: span

    def on_end(span, owner) do
      send(owner, {:closed_span, span})
      true
    end

    def force_flush(_), do: :ok
  end

  defmodule OmittedOutput do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:count, :integer)
    end
  end

  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, query), do: Store.ETS.scan_records(c.table, ns, query)

    def transition(c, key, revision, command) do
      current = command["operation"]

      fault =
        Agent.get_and_update(c.fault, fn
          {^current, mode} -> {mode, nil}
          other -> {nil, other}
        end)

      result =
        if fault == :before,
          do: {:error, :before_commit},
          else: Store.ETS.transition(c.table, key, revision, command)

      if fault == :hold do
        send(c.owner, {:held_input, self()})

        receive do
          :release_input -> :ok
        end
      end

      if fault == :after, do: {:error, :lost_ack}, else: result
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    store = Store.scoped({Store.ETS, __MODULE__}, "sequence-api")
    owner = self()

    steps =
      for id <- ["A", "B", "C"] do
        %{
          id: id,
          agent:
            ExAgent.new(
              model: %ExAgent.Models.Test{
                script: [
                  fn _, _ ->
                    {:ok, record} = Store.load_record(store, :agent, "run")
                    send(owner, {:io, id, record})
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
            load: fn _, _ -> raise "completed projection cannot load" end
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
      active_time_limit_ms: 60_000,
      on_writer: fn writer ->
        send(owner, {:writer, writer})
        :ok
      end
    }

    %{definition: definition, config: config, store: store}
  end

  test "API runs three leaves, returns confirmed portable result and closes owned runtime", c do
    assert {:ok, result} = Composition.run(c.definition, "initial", continuation: c.config)
    assert result.status == :completed
    assert result.output == "C output"
    assert result.model == nil and result.messages == [] and result.new_messages == []
    assert result.request_count == 3 and result.tool_calls == 0
    assert Enum.map(result.steps, & &1.input) == ["initial", "A output", "B output"]
    assert Enum.all?(result.steps, &(&1.status == :completed and length(&1.messages) == 2))
    assert_receive {:writer, writer}
    refute Process.alive?(writer)
    for id <- ["A", "B", "C"], do: assert_receive({:io, ^id, _})
    assert {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert :ok = ContinuationRecord.validate(record, {"sequence-api", :agent, "run"})
    restore_config = Map.put(c.config, :definition, %{"id" => "sequence", "version" => "1"})

    assert {:ok, inspected} =
             ExAgent.resume_composition_step(c.definition, result.continuation,
               continuation: restore_config
             )

    assert inspected == result
    refute_receive {:io, _, _}
    refute_receive {:writer, _}
  end

  test "completed public result equals fresh VM inspection from JSON with all callbacks forbidden",
       c do
    assert {:ok, result} = Composition.run(c.definition, "initial", continuation: c.config)
    {:ok, record} = Store.load_record(c.store, :agent, "run")

    path =
      Path.join("/tmp/opencode", "sequence-api-vm-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(%{record: record, result: result}))
    on_exit(fn -> File.rm(path) end)
    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++ ["test/support/sequence_run_vm.exs", path]

    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "SEQUENCE_API_VM exact completed projection, no callbacks"
  end

  test "authentic historical Frame8 lifetime stays8 through current Writer completion", _c do
    store = Store.scoped({Store.ETS, __MODULE__}, "legacy8-sequence")
    bytes = File.read!("test/fixtures/continuation/frame8-input-sequence.json")
    key = {"legacy8-sequence", :agent, "legacy8"}
    {:ok, record} = ContinuationRecord.decode(bytes, key)
    assert record["execution"]["progress"]["runtime"]["frame_version"] == 8
    {:ok, physical} = ContinuationRecord.key(key)
    :ets.insert(__MODULE__, {physical, bytes})

    step = %{
      id: "A",
      agent: ExAgent.new(model: %ExAgent.Models.Test{script: ["legacy completed"]}),
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"},
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, d -> {:ok, %{m | index: d["index"]}} end
      }
    }

    {:ok, definition} = Composition.new(id: "legacy8", version: "1", steps: [step])

    config = %{
      store: store,
      id: "legacy8",
      definition: %{"id" => "legacy8", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000
    }

    reference = %{id: "legacy8", record_id: record["record_id"], revision: record["revision"]}

    assert {:ok, %{output: "legacy completed"}} =
             ExAgent.resume_composition_step(definition, reference, continuation: config)

    {:ok, completed} = Store.load_record(store, :agent, "legacy8")
    assert completed["execution"]["state"] == "completed"
    assert completed["execution"]["progress"]["runtime"]["frame_version"] == 8
    assert :ok = ContinuationRecord.validate(completed, key)
  end

  test "mapping receives committed portable prefix and failure leaves successors not started",
       c do
    owner = self()

    steps =
      Enum.map(c.definition.steps, fn
        %{id: "B"} = step ->
          Map.merge(step, %{
            input_version: "1",
            input: fn initial, outputs ->
              send(owner, {:mapping, initial, outputs})
              {:error, :no_input}
            end
          })

        step ->
          step
      end)

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

    assert {:error, %RunError{reason: :invalid_composition_input, partial: result}} =
             Composition.run(definition, "initial", continuation: c.config)

    assert result.error_phase == :mapping and result.error_step_id == "B"
    assert result.status == :failed and is_nil(result.output)
    assert Enum.map(result.steps, & &1.status) == [:completed, :not_started, :not_started]
    assert result.request_count == 1
    assert_receive {:mapping, "initial", %{"A" => "A output"}}
    assert_receive {:writer, writer}
    refute Process.alive?(writer)
    assert {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["state"] == "claimed"
    assert record["execution"]["progress"]["runtime"]["cursor"] == "between_steps"
    refute_receive {:io, "B", _}
  end

  test "strict options reject injection, duplicates, unknown IDs and derived contradictions before IO",
       c do
    bad = [
      [],
      [continuation: nil],
      [continuation: c.config, unknown: true],
      [continuation: c.config, continuation: c.config],
      [continuation: c.config, step_options: %{"missing" => []}],
      [continuation: c.config, step_options: %{"B" => [run_id: "injected"]}],
      [continuation: c.config, step_options: %{"B" => [deadline: 1, deadline: 2]}],
      [continuation: c.config, root_options: [execution_scope: self()]],
      [continuation: Map.put(c.config, :kind, :leaf)],
      [continuation: Map.put(c.config, :definition, %{"id" => "wrong", "version" => "1"})]
    ]

    for opts <- bad do
      assert {:error, %RunError{partial: %{error_phase: :open, run_id: nil, output: nil}}} =
               Composition.run(c.definition, "initial", opts)
    end

    refute_receive {:writer, _}
    refute_receive {:io, _, _}
  end

  test "root quota stops successor and keeps confirmed totals without a fictitious terminal", c do
    owner = self()

    steps =
      Enum.map(c.definition.steps, fn
        %{id: "B"} = step ->
          Map.merge(step, %{
            input_version: "1",
            input: fn _, _ ->
              send(owner, :unexpected_mapping)
              {:ok, "input"}
            end
          })

        step ->
          step
      end)

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

    assert {:error,
            %RunError{reason: {:usage_limit_exceeded, :request_limit, 1}, partial: result}} =
             Composition.run(definition, "initial",
               continuation: c.config,
               root_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 1}]
             )

    assert result.request_count == 1
    assert result.error_step_id == "B"
    assert result.error_phase == :prepare
    assert Enum.map(result.steps, & &1.status) == [:completed, :not_started, :not_started]
    assert_receive {:writer, writer}
    refute Process.alive?(writer)
    refute_receive {:io, "B", _}
    refute_receive :unexpected_mapping
  end

  for mode <- [:text, :typed, :tools] do
    @tag mode: mode
    test "#{mode}: public API preserves portable mapping and fresh history", c do
      owner = self()
      mode = c.mode

      steps =
        Enum.map(c.definition.steps, fn step ->
          tool =
            ExAgent.Tool.new(
              name: "effect",
              parameters_json_schema: %{"type" => "object"},
              call: fn _, _ ->
                send(owner, {:effect, step.id})
                {:ok, "done"}
              end
            )

          call = %ExAgent.Message.Part.ToolCall{
            tool_name: if(mode == :typed, do: "final_result", else: "effect"),
            tool_call_id: "reused",
            args: if(mode == :typed, do: %{"count" => 7}, else: %{})
          }

          script =
            case mode do
              :text -> ["text"]
              :typed -> [{:tool_calls, [call]}]
              :tools -> [{:tool_calls, [call]}, "text"]
            end

          agent =
            ExAgent.new(
              model: %ExAgent.Models.Test{script: script},
              tools: if(mode == :tools, do: [tool], else: []),
              output:
                if(mode == :typed, do: ExAgent.ContinuationNativeFixture.CountOutput, else: :text)
            )

          step = %{step | agent: agent}

          if step.id == "B",
            do:
              Map.merge(step, %{
                input_version: "1",
                input: fn initial, outputs ->
                  send(owner, {:mapped, initial, outputs})
                  {:ok, nil}
                end
              }),
            else: step
        end)

      {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)
      assert {:ok, result} = Composition.run(definition, "initial", continuation: c.config)
      expected = if mode == :typed, do: %{"count" => 7}, else: "text"
      assert result.output == expected
      assert_receive {:mapped, "initial", %{"A" => ^expected}}
      assert Enum.at(result.steps, 1).input == nil
      assert Enum.at(result.steps, 2).input == expected
      assert result.request_count == if(mode == :tools, do: 6, else: 3)
      assert result.usage.input_tokens == result.request_count
      assert result.usage.output_tokens == result.request_count

      if mode == :tools do
        assert result.tool_calls == 3
        for id <- ["A", "B", "C"], do: assert_receive({:effect, ^id})
      end
    end
  end

  for operation <- ["step_output", "step_input", "begin_effect"], mode <- [:before, :after] do
    test "#{operation} #{mode}: only ACKed state is projected and token retry performs no IO",
         c do
      operation = unquote(operation)
      mode = unquote(mode)
      fault = start_supervised!({Agent, fn -> {operation, mode} end})
      store = Store.scoped({FaultStore, %{table: __MODULE__, fault: fault}}, "sequence-api")
      config = %{c.config | store: store}

      assert {:error, %RunError{partial: result}} =
               Composition.run(c.definition, "initial", continuation: config)

      assert is_map(result.continuation_checkpoint)
      assert result.error_phase == :checkpoint
      assert result.status == :failed and result.output == nil
      assert result.usage_status == :partial
      assert Enum.at(result.steps, 1).status == :not_started
      assert_receive {:writer, writer}
      refute Process.alive?(writer)

      assert {:ok, _} =
               ExAgent.Continuation.retry_checkpoint(store, result.continuation_checkpoint)

      assert {:ok, _} =
               ExAgent.Continuation.retry_checkpoint(store, result.continuation_checkpoint)

      refute_receive {:io, "B", _}
      if operation != "step_output", do: refute_receive({:io, "A", _})
    end
  end

  test "preparation failure on B reports committed A and no B attachment", c do
    assert {:error, %RunError{partial: result}} =
             Composition.run(c.definition, "initial",
               continuation: c.config,
               step_options: %{"B" => [max_history_bytes: 1]}
             )

    assert result.error_phase == :prepare and result.error_step_id == "B"
    assert Enum.map(result.steps, & &1.status) == [:completed, :not_started, :not_started]
    refute_receive {:io, "B", _}
  end

  test "oversized mapping input fails between steps with A intact", c do
    steps =
      Enum.map(c.definition.steps, fn
        %{id: "B"} = step ->
          Map.merge(step, %{
            input_version: "1",
            input: fn _, _ ->
              {:ok, String.duplicate("x", 8_388_609)}
            end
          })

        step ->
          step
      end)

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

    assert {:error, %RunError{partial: result}} =
             Composition.run(definition, "initial", continuation: c.config)

    assert result.error_phase == :mapping and result.error_step_id == "B"
    assert Enum.map(result.steps, & &1.status) == [:completed, :not_started, :not_started]
    refute_receive {:io, "B", _}
  end

  test "late nonpreemptible mapping cannot reset the root deadline or attach B", c do
    owner = self()
    deadline = System.monotonic_time(:millisecond) + 1_500

    steps =
      Enum.map(c.definition.steps, fn
        %{id: "B"} = step ->
          Map.merge(step, %{
            input_version: "1",
            input: fn _, _ ->
              send(owner, {:deadline_mapping, self()})

              receive do
                :return_input -> {:ok, "late"}
              end
            end
          })

        step ->
          step
      end)

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

    task =
      Task.async(fn ->
        Composition.run(definition, "initial",
          continuation: c.config,
          root_options: [deadline: deadline]
        )
      end)

    assert_receive {:deadline_mapping, mapper}, 1_000

    Process.send_after(
      self(),
      :deadline_reached,
      max(0, deadline - System.monotonic_time(:millisecond))
    )

    assert_receive :deadline_reached, 2_000
    assert System.monotonic_time(:millisecond) >= deadline
    send(mapper, :return_input)
    assert {:error, %RunError{reason: :deadline_exceeded, partial: result}} = Task.await(task)
    assert result.error_step_id == "B" and result.error_phase == :prepare
    assert Enum.map(result.steps, & &1.status) == [:completed, :not_started, :not_started]
    refute_receive {:io, "B", _}
  end

  test "deadline exhausted after A ACK rejects preparation before B mapping", c do
    owner = self()
    deadline = System.monotonic_time(:millisecond) + 1_500
    fault = start_supervised!({Agent, fn -> {"step_output", :hold} end})

    store =
      Store.scoped({FaultStore, %{table: __MODULE__, fault: fault, owner: owner}}, "sequence-api")

    steps =
      Enum.map(c.definition.steps, fn
        %{id: "B"} = step ->
          Map.merge(step, %{
            input_version: "1",
            input: fn _, _ ->
              send(owner, :unexpected_mapping)
              {:ok, "B"}
            end
          })

        step ->
          step
      end)

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

    task =
      Task.async(fn ->
        Composition.run(definition, "initial",
          continuation: %{c.config | store: store},
          root_options: [deadline: deadline]
        )
      end)

    assert_receive {:held_input, writer}, 1_000
    {:ok, before} = Store.load_record(c.store, :agent, "run")
    assert before["execution"]["progress"]["runtime"]["cursor"] == "between_steps"

    Process.send_after(
      self(),
      :deadline_reached,
      max(0, deadline - System.monotonic_time(:millisecond))
    )

    assert_receive :deadline_reached, 2_000
    assert System.monotonic_time(:millisecond) >= deadline
    send(writer, :release_input)
    assert {:error, %RunError{reason: :deadline_exceeded, partial: result}} = Task.await(task)
    assert result.error_phase == :prepare and result.error_step_id == "B"
    assert Enum.map(result.steps, & &1.status) == [:completed, :not_started, :not_started]
    assert result.request_count == 1 and result.continuation_checkpoint == nil
    assert {:ok, ^before} = Store.load_record(c.store, :agent, "run")
    refute_receive :unexpected_mapping
    refute_receive {:io, "B", _}
  end

  for mapping_failure <- [:error, :raise, :invalid] do
    @tag mapping_failure: mapping_failure
    test "genuine mapping #{mapping_failure} stays bounded and is not admission", c do
      steps =
        Enum.map(c.definition.steps, fn
          %{id: "B"} = step ->
            Map.merge(step, %{
              input_version: "1",
              input: fn _, _ ->
                payload = String.duplicate("sensitive mapping payload", 10_000)

                case c.mapping_failure do
                  :error -> {:error, payload}
                  :raise -> raise payload
                  :invalid -> payload
                end
              end
            })

          step ->
            step
        end)

      {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

      assert {:error, %RunError{reason: :invalid_composition_input, partial: result}} =
               Composition.run(definition, "initial", continuation: c.config)

      assert result.error_phase == :mapping and result.error_step_id == "B"
      assert Enum.map(result.steps, & &1.status) == [:completed, :not_started, :not_started]
      assert result.continuation_checkpoint == nil
      refute_receive {:io, "B", _}
    end
  end

  test "rejected tool accounting in B preserves confirmed subtotal as partial", c do
    owner = self()

    tool =
      ExAgent.Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :effect)
          {:ok, "done", %ExAgent.Message.Usage{input_tokens: -1, output_tokens: 2}}
        end
      )

    steps =
      Enum.map(c.definition.steps, fn
        %{id: "B"} = step ->
          %{
            step
            | agent:
                ExAgent.new(
                  tools: [tool],
                  model: %ExAgent.Models.Test{
                    script: [
                      {:tool_calls,
                       [
                         %ExAgent.Message.Part.ToolCall{
                           tool_name: "effect",
                           tool_call_id: "same",
                           args: %{}
                         }
                       ]}
                    ]
                  }
                )
          }

        step ->
          step
      end)

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

    assert {:error, %RunError{partial: result}} =
             Composition.run(definition, "initial", continuation: c.config)

    assert_receive :effect
    assert result.error_step_id == "B"
    assert result.usage_status == :partial and result.cost_status == :unknown
    assert result.request_count == 2 and result.tool_calls == 1
    assert Enum.map(result.steps, & &1.status) == [:completed, :running, :not_started]
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    projected = Composition.project(definition, record, c.config)
    assert projected.usage_status == :partial
    assert projected.usage.input_tokens == result.usage.input_tokens
    assert :ok = ContinuationRecord.validate(record, {"sequence-api", :agent, "run"})
    refute_receive {:io, "C", _}
  end

  test "C7 all-pending B pauses after ACK without callable or successor", c do
    owner = self()

    tool =
      ExAgent.Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :forbidden_effect)
          {:ok, "done"}
        end
      )

    steps =
      Enum.map(c.definition.steps, fn
        %{id: "B"} = step ->
          %{
            step
            | agent:
                ExAgent.new(
                  tools: [tool],
                  model: %ExAgent.Models.Test{
                    script: [
                      {:tool_calls,
                       [
                         %ExAgent.Message.Part.ToolCall{
                           tool_name: "effect",
                           tool_call_id: "ask",
                           args: %{}
                         }
                       ]}
                    ]
                  }
                )
          }

        step ->
          step
      end)

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

    assert {:ok, result} =
             Composition.run(definition, "initial",
               continuation: c.config,
               root_options: [permissions: ExAgent.Permissions.new!(default: :ask)]
             )

    assert result.status == :paused and result.error_step_id == nil
    assert result.output == nil and result.continuation_checkpoint == nil
    assert Enum.map(result.steps, & &1.status) == [:completed, :paused, :not_started]
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["state"] == "pending"
    assert record["revision"] == result.continuation.revision
    refute_receive :forbidden_effect
    refute_receive {:io, "C", _}
  end

  test "omitted final output is an error although the durable cursor is completed", c do
    steps =
      Enum.map(c.definition.steps, fn
        %{id: "C"} = step ->
          %{
            step
            | agent:
                ExAgent.new(
                  output: OmittedOutput,
                  model: %ExAgent.Models.Test{
                    script: [
                      {:tool_calls,
                       [
                         %ExAgent.Message.Part.ToolCall{
                           tool_name: "final_result",
                           tool_call_id: "final",
                           args: %{"count" => 1}
                         }
                       ]}
                    ]
                  }
                )
          }

        step ->
          step
      end)

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

    assert {:error, %RunError{partial: result}} =
             Composition.run(definition, "initial", continuation: c.config)

    assert result.output == nil and result.status == :failed
    assert result.error_step_id == "C"
    assert result.error_phase == :checkpoint
    assert Enum.all?(result.steps, &(&1.status == :completed))
    assert is_map(List.last(result.steps).output_omitted)
    {:ok, record} = Store.load_record(c.store, :agent, "run")
    assert record["execution"]["state"] == "completed"
    assert record["execution"]["progress"]["runtime"]["cursor"] == "completed"
  end

  test "open checkpoint failure still retains its exact token and closes Writer", c do
    fault = start_supervised!({Agent, fn -> {"claim", :after} end})
    store = Store.scoped({FaultStore, %{table: __MODULE__, fault: fault}}, "sequence-api")
    config = %{c.config | store: store}

    assert {:error, %RunError{partial: result}} =
             Composition.run(c.definition, "initial", continuation: config)

    assert result.error_phase == :open and result.error_step_id == nil
    assert result.continuation_checkpoint != nil
    assert Enum.all?(result.steps, &(&1.status == :not_started))
    assert_receive {:writer, writer}
    refute Process.alive?(writer)
    refute_receive {:io, _, _}
  end

  test "Writer loss during open returns an unknown confirmed prefix without a Store-only token",
       c do
    owner = self()
    fault = start_supervised!({Agent, fn -> {"claim", :hold} end})

    store =
      Store.scoped({FaultStore, %{table: __MODULE__, fault: fault, owner: owner}}, "sequence-api")

    {runner, monitor} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, true)

        send(
          owner,
          {:lost_result,
           Composition.run(c.definition, "initial", continuation: %{c.config | store: store})}
        )
      end)

    assert_receive {:held_input, writer}, 5_000
    {:ok, before} = Store.load_record(c.store, :agent, "run")
    ref = Process.monitor(writer)
    Process.exit(writer, :kill)
    assert_receive {:DOWN, ^ref, :process, ^writer, :killed}, 5_000

    assert_receive {:lost_result,
                    {:error, %RunError{reason: :continuation_owner_lost, partial: result}}},
                   5_000

    assert_receive {:DOWN, ^monitor, :process, ^runner, :normal}, 5_000
    assert result.error_phase == :open
    assert result.run_id == nil and result.continuation == nil
    assert result.continuation_checkpoint == nil and result.usage_status == :partial
    assert Enum.all?(result.steps, &(&1.status == :not_started))
    assert {:ok, ^before} = Store.load_record(c.store, :agent, "run")
    refute_receive {:io, _, _}
  end

  for read <- [:confirmed_record, :pending] do
    @tag lost_read: read
    test "Writer loss at #{read} never projects an error tuple or invents a token", c do
      owner = self()
      target = c.lost_read

      config = %{
        c.config
        | on_writer: fn writer ->
            # A sys debug barrier observes the real GenServer request before handling;
            # it neither changes replies nor replaces any admission/CAS invariant.
            :ok =
              :sys.install(
                writer,
                {fn state, event, _ ->
                   case event do
                     {:in, {:"$gen_call", _, ^target}}
                     when target == :confirmed_record or state == true ->
                       send(owner, {:read_barrier, self()})

                       receive do
                         :release_read -> :ok
                       end

                       state

                     {:in, {:"$gen_call", _, :confirmed_record}} ->
                       true

                     _ ->
                       state
                   end
                 end, false}
              )

            :ok
          end
      }

      {runner, monitor} =
        spawn_monitor(fn ->
          Process.flag(:trap_exit, true)

          send(
            owner,
            {:lost_result, Composition.run(c.definition, "initial", continuation: config)}
          )
        end)

      assert_receive {:read_barrier, writer}, 5_000
      {:ok, before} = Store.load_record(c.store, :agent, "run")
      assert before["execution"]["progress"]["runtime"]["cursor"] == "between_steps"
      ref = Process.monitor(writer)
      Process.exit(writer, :kill)
      assert_receive {:DOWN, ^ref, :process, ^writer, :killed}, 5_000

      assert_receive {:lost_result,
                      {:error, %RunError{reason: :continuation_owner_lost, partial: result}}},
                     5_000

      assert_receive {:DOWN, ^monitor, :process, ^runner, :normal}, 5_000
      assert result.error_phase == :execute and result.error_step_id == "A"
      assert result.continuation_checkpoint == nil and result.usage_status == :partial
      assert result.output == nil

      if target == :pending do
        assert Enum.map(result.steps, & &1.status) == [:completed, :not_started, :not_started]
        assert result.request_count == 1 and result.continuation.revision == before["revision"]
      else
        assert Enum.all?(result.steps, &(&1.status == :not_started))
        assert result.request_count == 0 and result.continuation.revision < before["revision"]
      end

      assert {:ok, ^before} = Store.load_record(c.store, :agent, "run")
      refute_receive {:io, "B", _}
    end
  end

  for stage <- [:mapping, :model] do
    @tag loss_stage: stage
    test "trapping caller preserves only previously received ACKs when Writer dies in B #{stage}",
         c do
      owner = self()

      barrier = fn ->
        send(owner, {:loss_barrier, self()})

        receive do
          :release_loss -> :ok
        end
      end

      steps =
        Enum.map(c.definition.steps, fn
          %{id: "A"} = step ->
            %{
              step
              | agent:
                  ExAgent.new(
                    model: %ExAgent.Models.Test{
                      script: [
                        fn _, _ ->
                          send(owner, {:first_model, self()})

                          receive do
                            :release_first -> "A output"
                          end
                        end
                      ]
                    }
                  )
            }

          %{id: "B"} = step ->
            if c.loss_stage == :mapping do
              Map.merge(step, %{
                input_version: "1",
                input: fn _, _ ->
                  barrier.()
                  {:ok, "B"}
                end
              })
            else
              %{
                step
                | agent:
                    ExAgent.new(
                      model: %ExAgent.Models.Test{
                        script: [
                          fn _, _ ->
                            barrier.()
                            "B"
                          end
                        ]
                      }
                    )
              }
            end

          step ->
            step
        end)

      {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

      {runner, monitor} =
        spawn_monitor(fn ->
          Process.flag(:trap_exit, true)

          send(
            owner,
            {:lost_result, Composition.run(definition, "initial", continuation: c.config)}
          )
        end)

      assert_receive {:writer, writer}, 5_000
      assert_receive {:first_model, first}, 5_000
      scope = :sys.get_state(writer).scope.pid
      scope_ref = Process.monitor(scope)
      send(first, :release_first)
      assert_receive {:loss_barrier, blocked}, 5_000
      {:ok, before} = Store.load_record(c.store, :agent, "run")
      writer_ref = Process.monitor(writer)
      Process.exit(writer, :kill)
      assert_receive {:DOWN, ^writer_ref, :process, ^writer, :killed}, 5_000
      send(blocked, :release_loss)

      assert_receive {:lost_result,
                      {:error, %RunError{reason: :continuation_owner_lost, partial: result}}},
                     5_000

      assert_receive {:DOWN, ^monitor, :process, ^runner, :normal}, 5_000
      assert_receive {:DOWN, ^scope_ref, :process, ^scope, _}, 5_000
      assert result.error_phase == :execute and result.error_step_id == "B"
      assert Enum.map(result.steps, & &1.status) == [:completed, :not_started, :not_started]
      assert result.request_count == 1 and result.usage_status == :partial
      assert result.output == nil and result.continuation_checkpoint == nil
      assert result.continuation.revision < before["revision"] or c.loss_stage == :mapping
      assert {:ok, ^before} = Store.load_record(c.store, :agent, "run")
      refute_receive {:io, "C", _}
    end
  end

  for stage <- [:after_a, :input_b, :model_b] do
    @tag stage: stage
    test "owner killed at #{stage}: Writer and Scope terminate, recovery never refunds or replays",
         c do
      owner = self()
      fault = start_supervised!({Agent, fn -> nil end})

      store =
        Store.scoped(
          {FaultStore, %{table: __MODULE__, fault: fault, owner: owner}},
          "sequence-api"
        )

      steps =
        Enum.map(c.definition.steps, fn
          %{id: "B"} = step ->
            step =
              if c.stage == :model_b do
                model = %ExAgent.Models.Test{
                  script: [
                    fn _, _ ->
                      send(owner, {:held_model, self()})

                      receive do
                        :release_model -> "B"
                      end
                    end
                  ]
                }

                %{step | agent: ExAgent.new(model: model)}
              else
                step
              end

            Map.merge(step, %{
              input_version: "1",
              input: fn _, outputs ->
                if c.stage == :after_a do
                  send(owner, {:held_mapping, self()})

                  receive do
                    :release_mapping -> :ok
                  end
                end

                if c.stage == :input_b, do: Agent.update(fault, fn _ -> {"step_input", :hold} end)
                {:ok, outputs["A"]}
              end
            })

          step ->
            step
        end)

      {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)
      config = %{c.config | store: store}
      runner = spawn(fn -> Composition.run(definition, "initial", continuation: config) end)
      runner_ref = Process.monitor(runner)
      assert_receive {:writer, writer}
      writer_ref = Process.monitor(writer)
      assert_receive {:io, "A", _}, 2_000
      # Query while A executes, before the Writer blocks in the next host boundary.
      # Scope identity is also available through the root's owner monitor.
      scope = scope_owned_by(runner)
      scope_ref = Process.monitor(scope)

      model =
        case c.stage do
          :after_a ->
            assert_receive {:held_mapping, ^writer}, 2_000
            nil

          :input_b ->
            assert_receive {:held_input, ^writer}, 2_000
            nil

          :model_b ->
            assert_receive {:held_model, pid}, 2_000
            {pid, Process.monitor(pid)}
        end

      {:ok, before} = Store.load_record(store, :agent, "run")
      Process.exit(runner, :kill)
      assert_receive {:DOWN, ^runner_ref, :process, ^runner, :killed}
      assert_receive {:DOWN, ^writer_ref, :process, ^writer, _}
      assert_receive {:DOWN, ^scope_ref, :process, ^scope, _}

      if model do
        {pid, ref} = model
        assert_receive {:DOWN, ^ref, :process, ^pid, _}
      end

      assert {:ok, ^before} = Store.load_record(store, :agent, "run")

      command = %{
        "record_id" => before["record_id"],
        "operation_id" => "recover",
        "actor_id" => "host",
        "operation" => "recover",
        "payload" => %{}
      }

      assert {:ok, %{record: recovered}} =
               ExAgent.Continuation.Transition.apply(
                 before,
                 {"sequence-api", :agent, "run"},
                 before["revision"],
                 command,
                 before["execution"]["lease_until"] + 1
               )

      assert recovered["execution"]["state"] ==
               if(c.stage == :model_b, do: "uncertain", else: "ready")

      budget = recovered["execution"]["progress"]["active_budget"]

      assert budget["remaining_ms"] ==
               before["execution"]["progress"]["active_budget"]["remaining_ms"]

      refute_receive {:io, "C", _}
    end
  end

  defp scope_owned_by(owner) do
    {:monitored_by, monitors} = Process.info(owner, :monitored_by)

    Enum.find(monitors, fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dictionary} ->
          dictionary[:"$initial_call"] == {ExAgent.ExecutionScope, :init, 1}

        _ ->
          false
      end
    end) || flunk("root Scope must monitor the owner")
  end

  test "root trace owns three leaf spans and no fictitious root Model generation", c do
    old = Application.get_env(:opentelemetry, :processors)
    Application.put_env(:opentelemetry, :processors, [])
    {:ok, started} = Application.ensure_all_started(:opentelemetry)

    on_exit(fn ->
      if :opentelemetry in started, do: Application.stop(:opentelemetry)

      if old == nil,
        do: Application.delete_env(:opentelemetry, :processors),
        else: Application.put_env(:opentelemetry, :processors, old)
    end)

    :otel_ctx.clear()
    provider_name = :sequence_run_test

    {:ok, provider} =
      :otel_tracer_provider_sup.start(provider_name, :otel_resource.create(%{}), %{
        sampler: :always_on,
        id_generator: :otel_id_generator,
        deny_list: [],
        processors: [{Processor, self()}]
      })

    try do
      tracer = :otel_tracer_provider.get_tracer(provider_name, :exagent, "1", :undefined)
      tracing = ExAgent.Observability.OpenTelemetry.new(tracer: tracer)

      assert {:ok, result} =
               Composition.run(c.definition, "initial",
                 continuation: c.config,
                 observability: tracing
               )

      spans =
        for _ <- 1..7 do
          assert_receive {:closed_span, record}

          %{
            id: span(record, :span_id),
            parent: span(record, :parent_span_id),
            attrs: :otel_attributes.map(span(record, :attributes))
          }
        end

      runs = Enum.filter(spans, &(&1.attrs["exagent.operation"] == "run"))
      assert length(runs) == 4
      root = Enum.find(runs, &(&1.attrs["exagent.run_id"] == result.run_id))
      assert root.attrs["exagent.attempt_id"] == result.attempt_id
      assert root.attrs["exagent.usage.request_count"] == 3
      leaves = Enum.reject(runs, &(&1.id == root.id))
      assert Enum.all?(leaves, &(&1.parent == root.id))
      models = Enum.filter(spans, &(&1.attrs["exagent.operation"] == "model"))
      assert length(models) == 3
      assert Enum.all?(models, fn m -> Enum.any?(leaves, &(&1.id == m.parent)) end)
      {:ok, stored} = Store.load_record(c.store, :agent, "run")
      refute Jason.encode!(stored) =~ "trace_context"
    after
      :supervisor.terminate_child(:otel_tracer_provider_sup, provider)
    end
  end
end
