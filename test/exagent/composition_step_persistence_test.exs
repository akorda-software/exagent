defmodule ExAgent.CompositionStepPersistenceTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, ExecutionScope, Store}
  alias ExAgent.Continuation.{Record, Writer}
  alias ExAgent.Coordination.Composition

  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, namespace, query), do: Store.ETS.scan_records(c.table, namespace, query)

    def transition(c, key, expected, command) do
      mode =
        Agent.get_and_update(c.fault, fn modes ->
          {Map.get(modes, command["operation"]), Map.delete(modes, command["operation"])}
        end)

      if mode == :before do
        {:error, :before_commit}
      else
        result = Store.ETS.transition(c.table, key, expected, command)

        case result do
          {:ok, %{record: record}} -> send(c.observer, {:stored, command["operation"], record})
          _ -> :ok
        end

        if mode == :after, do: {:error, :lost_ack}, else: result
      end
    end
  end

  setup context do
    start_supervised!({Store.ETS, table: __MODULE__})
    fault = start_supervised!({Agent, fn -> %{} end})

    store =
      Store.scoped(
        {FaultStore, %{table: __MODULE__, fault: fault, observer: self()}},
        "step-test"
      )

    owner = self()

    model = %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          {:ok, record} = Store.load_record(store, :agent, "sequence")
          send(owner, {:model_io, record})
          Map.get(context, :output, "leaf output")
        end
      ]
    }

    {model, tools} =
      if context[:tool_loop] do
        tool =
          ExAgent.Tool.new(
            name: "effect",
            parameters_json_schema: %{"type" => "object"},
            call: fn _, _ ->
              send(owner, :tool_effect)
              Map.get(context, :tool_result, {:ok, "done"})
            end
          )

        {%{
           model
           | script: [
               {:tool_calls,
                [
                  %ExAgent.Message.Part.ToolCall{
                    tool_name: "effect",
                    tool_call_id: "call-1",
                    args: %{}
                  }
                ]},
               "leaf output"
             ]
         }, [tool]}
      else
        {model, []}
      end

    codec_fault =
      start_supervised!(
        {Agent,
         fn ->
           context[:codec_failure] == true or context[:codec_oversized] == true or
             context[:codec_owner_death] == true
         end},
        id: :codec_fault
      )

    codec = %{
      dump: fn model ->
        send(owner, :codec_dump)

        if Agent.get_and_update(codec_fault, fn fail -> {fail, false} end) do
          cond do
            context[:codec_oversized] ->
              {:ok, %{"index" => model.index, "padding" => String.duplicate("x", 512_000)}}

            context[:codec_owner_death] ->
              send(owner, {:capture_waiting, self()})

              receive do
                :continue_capture -> {:error, :transient_codec}
              end

            true ->
              {:error, :transient_codec}
          end
        else
          {:ok, %{"index" => model.index}}
        end
      end,
      load: fn model, data -> {:ok, %{model | index: data["index"]}} end
    }

    step = %{
      id: "A",
      agent: ExAgent.new(model: model, tools: tools),
      model_codec: codec,
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"}
    }

    step =
      if context[:mapped],
        do:
          Map.merge(step, %{
            input: fn input, %{} ->
              send(owner, :mapping)
              {:ok, "mapped:" <> input}
            end,
            input_version: "1"
          }),
        else: step

    assert {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [step])

    assert {:ok, scope} =
             ExecutionScope.start_structural("root", Map.get(context, :scope_options, []))

    on_exit(fn -> ExecutionScope.stop(scope) end)

    config = %{
      kind: :composition,
      composition: definition,
      store: store,
      id: "sequence",
      definition: %{"id" => "sequence", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: Map.get(context, :lease_ms, 60_000),
      active_time_limit_ms: context[:active_budget]
    }

    config =
      if context[:checkpoint_limit],
        do: Map.put(config, :max_checkpoint_bytes, context.checkpoint_limit),
        else: config

    # Explicit legacy-9 source; current producer-10 has separate runtime coverage.
    assert {:ok, writer, record} =
             ExAgent.LegacyStructuralFixture.open(
               %{run_id: "root", execution_scope: scope, input: "initial"},
               config
             )

    assert is_map(record)
    on_exit(fn -> Writer.stop(writer) end)

    %{
      store: store,
      scope: scope,
      writer: writer,
      definition: definition,
      config: config,
      fault: fault
    }
  end

  test "pre-attach retention rejection leaves step runnable", c do
    assert {:error, :invalid_retention_limits} =
             ExAgent.run_composition_step(c.writer, c.definition, "A", max_history_bytes: -1)

    assert Writer.pending(c.writer).token == nil
    refute_receive {:model_io, _}

    assert {:ok, %{output: "leaf output"}} =
             ExAgent.run_composition_step(c.writer, c.definition, "A")

    assert_receive {:model_io, _}
    refute_receive {:model_io, _}
  end

  @tag codec_failure: true
  test "failed capture removes only the uncommitted leaf and permits retry", c do
    assert {:ok, before} = ExecutionScope.export_tree(c.scope)
    assert {:error, :transient_codec} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert :sys.get_state(c.writer).step_ticket == nil
    assert Writer.pending(c.writer).token == nil
    assert {:ok, ^before} = ExecutionScope.export_tree(c.scope)
    refute_receive {:model_io, _}

    assert {:ok, %{output: "leaf output"}} =
             ExAgent.run_composition_step(c.writer, c.definition, "A")
  end

  @tag codec_oversized: true, checkpoint_limit: 256_000
  test "capacity failure before input write also discards only its empty adhesion", c do
    assert {:ok, before} = ExecutionScope.export_tree(c.scope)
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert Writer.pending(c.writer).token == nil
    assert {:ok, ^before} = ExecutionScope.export_tree(c.scope)
    refute_receive {:model_io, _}
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
  end

  @tag codec_owner_death: true
  test "owner death during failed capture does not strand an empty adhesion", c do
    {pid, monitor} =
      spawn_monitor(fn -> ExAgent.run_composition_step(c.writer, c.definition, "A") end)

    assert_receive {:capture_waiting, writer}
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    send(writer, :continue_capture)
    await_ticket_release(c.writer, 100)
    assert {:ok, ledger} = ExecutionScope.export_tree(c.scope)
    assert Map.keys(ledger["nodes"]) == ["root"]
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
  end

  @tag tool_loop: true, tool_result: {:error, :expected_failure}
  test "legitimate tool error outcomes retain verifiable history", c do
    assert {:error,
            %ExAgent.RunError{reason: {:tool_execution_failed, "effect", :expected_failure}}} =
             ExAgent.run_composition_step(c.writer, c.definition, "A")

    assert_receive :tool_effect
    validate_stored_boundaries(c, [])
  end

  @tag :tool_loop
  test "denied calls are journaled without requiring a dispatched tool effect", c do
    assert {:ok, _} =
             ExAgent.run_composition_step(c.writer, c.definition, "A",
               permissions: ExAgent.Permissions.new!(default: :deny)
             )

    refute_receive :tool_effect
    assert "resolve_call" in validate_stored_boundaries(c, [])
  end

  @tag tool_loop: true,
       tool_result: {:ok, String.duplicate("x", 512_000)},
       checkpoint_limit: 256_000
  test "omitted tool outcomes remain verifiable but are not replayed", c do
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert_receive :tool_effect
    refute_receive :tool_effect
    assert {:ok, record} = Store.load_record(c.store, :agent, "sequence")

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {c.store.namespace, :agent, "sequence"})

    validate_stored_boundaries(c, [])
  end

  @tag :tool_loop
  test "unexecuted tool return cannot complete an acknowledged model response", c do
    Agent.update(c.fault, &Map.put(&1, "outcome", :after))
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:ok, r} = Store.load_record(c.store, :agent, "sequence")
    [id] = Map.keys(r["execution"]["progress"]["runtime"]["children"])
    path = ["runtime", "children", id]
    assert map_size(r["execution"]["effects"]) == 1
    snapshot = get_in(r["execution"]["progress"], path ++ ["snapshot"])
    {:ok, messages} = ExAgent.Message.from_json(snapshot["message_history"])

    invented =
      ExAgent.Message.new_request(
        [
          %ExAgent.Message.Part.ToolReturn{
            tool_name: "effect",
            tool_call_id: "call-1",
            status: :succeeded,
            content: "invented"
          }
        ],
        run_id: id
      )

    progress =
      r["execution"]["progress"]
      |> put_in(["runtime", "cursor"], "completed")
      |> put_in(path ++ ["status"], "completed")
      |> put_in(path ++ ["frame", "cursor"], "finish")
      |> put_in(path ++ ["result"], "invented")
      |> put_in(
        path ++ ["snapshot", "message_history"],
        ExAgent.Message.to_json(messages ++ [invented])
      )

    command = %{
      "record_id" => r["record_id"],
      "operation_id" => "forged-tool-finish",
      "operation" => "step_output",
      "actor_id" => "probe",
      "payload" =>
        Map.merge(Map.take(r["execution"], ~w(owner_id attempt_id fence)), %{
          "node_id" => id,
          "snapshot" => r["snapshot"],
          "progress" => progress
        })
    }

    assert {:error, _} = Store.transition(c.store, :agent, "sequence", r["revision"], command)
    assert {:ok, ^r} = Store.load_record(c.store, :agent, "sequence")
    refute_receive :tool_effect
  end

  @tag :tool_loop
  test "a fabricated call-bound Retry cannot resolve an unexecuted function", c do
    Agent.update(c.fault, &Map.put(&1, "outcome", :after))
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:ok, r} = Store.load_record(c.store, :agent, "sequence")
    [id] = Map.keys(r["execution"]["progress"]["runtime"]["children"])
    path = ["runtime", "children", id]
    snapshot = get_in(r["execution"]["progress"], path ++ ["snapshot"])
    {:ok, messages} = ExAgent.Message.from_json(snapshot["message_history"])

    invented =
      ExAgent.Message.new_request(
        [
          %ExAgent.Message.Part.Retry{
            tool_name: "effect",
            tool_call_id: "call-1",
            content: "invented retry"
          }
        ],
        run_id: id
      )

    progress =
      r["execution"]["progress"]
      |> put_in(["runtime", "cursor"], "completed")
      |> put_in(path ++ ["status"], "completed")
      |> put_in(path ++ ["frame", "cursor"], "finish")
      |> put_in(path ++ ["result"], "invented")
      |> put_in(
        path ++ ["snapshot", "message_history"],
        ExAgent.Message.to_json(messages ++ [invented])
      )

    command = %{
      "record_id" => r["record_id"],
      "operation_id" => "forged-retry",
      "operation" => "step_output",
      "actor_id" => "probe",
      "payload" =>
        Map.merge(Map.take(r["execution"], ~w(owner_id attempt_id fence)), %{
          "node_id" => id,
          "snapshot" => r["snapshot"],
          "progress" => progress
        })
    }

    assert {:error, _} = Store.transition(c.store, :agent, "sequence", r["revision"], command)
    assert {:ok, ^r} = Store.load_record(c.store, :agent, "sequence")
    refute_receive :tool_effect
  end

  @tag :tool_loop
  test "tool history and journal outcomes require matching evidence in both directions", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:ok, r} = Store.load_record(c.store, :agent, "sequence")
    [id] = Map.keys(r["execution"]["progress"]["runtime"]["children"])
    path = ["execution", "progress", "runtime", "children", id, "snapshot", "message_history"]
    {:ok, messages} = ExAgent.Message.from_json(get_in(r, path))

    for change <- [:content, :remove, :duplicate, :retry] do
      changed =
        Enum.map(messages, fn
          %ExAgent.Message.Request{} = request ->
            %{
              request
              | parts:
                  Enum.flat_map(request.parts, fn
                    %ExAgent.Message.Part.ToolReturn{} = part ->
                      case change do
                        :content ->
                          [%{part | content: "corrupted"}]

                        :remove ->
                          []

                        :duplicate ->
                          [part, part]

                        :retry ->
                          [
                            %ExAgent.Message.Part.Retry{
                              tool_name: part.tool_name,
                              tool_call_id: part.tool_call_id,
                              content: "fabricated"
                            }
                          ]
                      end

                    part ->
                      [part]
                  end)
            }

          message ->
            message
        end)

      bad = put_in(r, path, ExAgent.Message.to_json(changed))

      assert {:error, _} =
               Record.decode(Jason.encode!(bad), {c.store.namespace, :agent, "sequence"})
    end
  end

  test "changed request id must not disable model hash evidence", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:ok, r} = Store.load_record(c.store, :agent, "sequence")
    [id] = Map.keys(r["execution"]["progress"]["runtime"]["children"])
    path = ["execution", "progress", "runtime", "children", id, "frame"]

    bad =
      r
      |> put_in(path ++ ["model_request_id"], "unrelated")
      |> put_in(path ++ ["model_data"], %{"index" => 999})

    assert {:error, _} = Writer.step_status(bad, c.config, "A")

    assert {:error, _} =
             Record.decode(Jason.encode!(bad), {c.store.namespace, :agent, "sequence"})
  end

  test "completed cursor cannot hide unexecuted leaf position", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:ok, r} = Store.load_record(c.store, :agent, "sequence")
    [id] = Map.keys(r["execution"]["progress"]["runtime"]["children"])
    path = ["execution", "progress", "runtime", "children", id]

    bad =
      r |> put_in(path ++ ["frame", "run_step"], 0) |> put_in(path ++ ["snapshot", "revision"], 0)

    assert {:error, _} = Writer.step_status(bad, c.config, "A")

    assert {:error, _} =
             Record.decode(Jason.encode!(bad), {c.store.namespace, :agent, "sequence"})
  end

  test "two CAS transitions cannot complete a leaf with no model journal", c do
    Agent.update(c.fault, &Map.put(&1, "step_input", :after))
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:ok, r} = Store.load_record(c.store, :agent, "sequence")
    [id] = Map.keys(r["execution"]["progress"]["runtime"]["children"])
    path = ["runtime", "children", id]

    progress =
      r["execution"]["progress"]
      |> put_in(path ++ ["frame", "run_step"], 1)
      |> put_in(path ++ ["snapshot", "revision"], 1)

    command = fn operation, progress ->
      %{
        "record_id" => r["record_id"],
        "operation_id" => operation <> "-probe",
        "operation" => operation,
        "actor_id" => "probe",
        "payload" =>
          Map.merge(Map.take(r["execution"], ~w(owner_id attempt_id fence)), %{
            "node_id" => id,
            "snapshot" => r["snapshot"],
            "progress" => progress
          })
      }
    end

    assert {:error, _} =
             Store.transition(
               c.store,
               :agent,
               "sequence",
               r["revision"],
               command.("node_checkpoint", progress)
             )

    progress =
      progress
      |> put_in(["runtime", "cursor"], "completed")
      |> put_in(path ++ ["status"], "completed")
      |> put_in(path ++ ["frame", "cursor"], "finish")
      |> put_in(path ++ ["result"], "invented")

    assert {:error, _} =
             Store.transition(
               c.store,
               :agent,
               "sequence",
               r["revision"],
               command.("step_output", progress)
             )

    assert {:ok, ^r} = Store.load_record(c.store, :agent, "sequence")
    refute_receive {:model_io, _}
  end

  test "reservation release is exact, owner-bound and cannot reopen dirty input", c do
    assert {:ok, first} = Writer.step_descriptor(c.writer, c.definition, "A")

    assert {:error, _} =
             Task.async(fn -> Writer.release_step(c.writer, first.ticket) end) |> Task.await()

    assert :ok = Writer.release_step(c.writer, first.ticket)
    assert {:ok, second} = Writer.step_descriptor(c.writer, c.definition, "A")
    assert {:error, _} = Writer.release_step(c.writer, first.ticket)

    assert {:error, :composition_step_unavailable} =
             Writer.step_descriptor(c.writer, c.definition, "A")

    assert :ok = Writer.release_step(c.writer, second.ticket)
    Agent.update(c.fault, &Map.put(&1, "step_input", :after))
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:error, _} = Writer.release_step(c.writer, second.ticket)
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    refute_receive {:model_io, _}
  end

  test "dead pre-attach owner and preflight exception release only their reservation", c do
    task = Task.async(fn -> Writer.step_descriptor(c.writer, c.definition, "A") end)
    assert {:ok, descriptor} = Task.await(task)
    await_ticket_release(c.writer, 100)
    assert {:error, _} = Writer.release_step(c.writer, descriptor.ticket)

    assert_raise Protocol.UndefinedError, fn ->
      ExAgent.run_composition_step(c.writer, c.definition, "A", model_settings: [extra: :invalid])
    end

    assert {:ok, %{output: "leaf output"}} =
             ExAgent.run_composition_step(c.writer, c.definition, "A")
  end

  defp await_ticket_release(writer, attempts) do
    if :sys.get_state(writer).step_ticket != nil and attempts > 0 do
      Process.sleep(1)
      await_ticket_release(writer, attempts - 1)
    else
      assert :sys.get_state(writer).step_ticket == nil
    end
  end

  @tag :tool_loop
  test "ordinary tool loop retains position evidence at every persisted boundary", c do
    assert {:ok, %{output: "leaf output"}} =
             ExAgent.run_composition_step(c.writer, c.definition, "A")

    assert_receive :tool_effect
    refute_receive :tool_effect
    assert {:ok, r} = Store.load_record(c.store, :agent, "sequence")
    assert map_size(r["execution"]["effects"]) == 3
    assert {:ok, ledger} = ExecutionScope.export_tree(c.scope)
    assert length(ledger["operations"]) == 2
    assert length(ledger["batches"]) == 1
    assert {:ok, totals} = ExecutionScope.snapshot(c.scope)
    assert totals.request_count == 2
    assert totals.tool_calls == 1
    operations = validate_stored_boundaries(c, [])

    assert Enum.all?(
             ~w(step_input begin_effect outcome node_checkpoint finalize_call step_output),
             &(&1 in operations)
           )
  end

  defp validate_stored_boundaries(c, operations) do
    receive do
      {:stored, operation, record} ->
        assert {:ok, ^record} =
                 Record.decode(Jason.encode!(record), {c.store.namespace, :agent, "sequence"})

        assert {:ok, _} = Writer.step_status(record, c.config, "A")
        validate_stored_boundaries(c, [operation | operations])
    after
      0 -> operations
    end
  end

  test "one real leaf runs only after input/link commit and output survives JSON", c do
    assert {:ok, result} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert result.output == "leaf output"
    assert_receive {:model_io, before_request}
    root = before_request["execution"]["progress"]["runtime"]
    assert root["frame_version"] == 9
    [{leaf_id, leaf}] = Map.to_list(root["children"])

    assert leaf["link"] == %{
             "kind" => "step",
             "step_id" => "A",
             "index" => 0,
             "input" => "initial"
           }

    refute Map.has_key?(leaf, "call")
    assert leaf["frame"]["frame_version"] == 3
    assert {:ok, %{record: saved}} = Continuation.get(c.store, "sequence")
    assert saved["execution"]["progress"]["runtime"]["cursor"] == "completed"

    assert saved["execution"]["progress"]["runtime"]["children"][leaf_id]["result"] ==
             "leaf output"

    saved_leaf = saved["execution"]["progress"]["runtime"]["children"][leaf_id]
    assert saved_leaf["frame"]["model_data"] == %{"index" => 1}

    assert {:ok, [request, response]} =
             ExAgent.Message.from_json(saved_leaf["snapshot"]["message_history"])

    assert request.run_id == leaf_id
    assert ExAgent.Message.Response.text(response) == "leaf output"
    refute Map.has_key?(saved["execution"], "request_id")
    refute Map.has_key?(saved["execution"], "model_ref")

    key = {c.store.namespace, :agent, "sequence"}
    assert {:ok, bytes} = Record.encode(saved, key)
    assert {:ok, ^saved} = Record.decode(bytes, key)
    assert {:ok, ledger} = ExecutionScope.export_tree(c.scope)
    assert length(ledger["operations"]) == 1
    assert Enum.all?(ledger["operations"], &(&1["run_id"] == leaf_id))
    assert {:ok, totals} = ExecutionScope.snapshot(c.scope)
    assert totals.request_count == 1
    assert totals.usage.input_tokens == 1
    assert totals.usage.output_tokens == 1

    assert {:ok, %{status: :completed, output: "leaf output"}} =
             Writer.step_status(saved, c.config, "A")

    assert {:ok, %{status: :completed, output: "leaf output"}} =
             ExAgent.run_composition_step(c.writer, c.definition, "A")

    refute_receive {:model_io, _}
  end

  for mode <- [:before, :after] do
    @tag mapped: true
    test "input #{mode} commit failure blocks all model IO; retry only persists exact input", c do
      Agent.update(c.fault, &Map.put(&1, "step_input", unquote(mode)))
      assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
      assert_receive :mapping
      refute_receive {:model_io, _}
      token = Writer.pending(c.writer).token |> Jason.encode!() |> Jason.decode!()
      assert token["command"]["operation"] == "step_input"
      assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
      refute_receive :mapping
      assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
      assert {:ok, %{record: record}} = Continuation.get(c.store, "sequence")

      assert {:ok, %{status: :input_confirmed, input: "mapped:initial"}} =
               Writer.step_status(record, c.config, "A")

      assert record["execution"]["effects"] == %{}
      assert record["execution"]["progress"]["runtime"]["scope"]["operations"] == []
      refute_receive {:model_io, _}
    end

    test "output #{mode} commit failure retries data only and does not rerun the leaf", c do
      Agent.update(c.fault, &Map.put(&1, "step_output", unquote(mode)))

      assert {:error, %ExAgent.RunError{}} =
               ExAgent.run_composition_step(c.writer, c.definition, "A")

      assert_receive {:model_io, _}
      token = Writer.pending(c.writer).token |> Jason.encode!() |> Jason.decode!()
      assert token["command"]["operation"] == "step_output"
      assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
      assert {:ok, %{record: record}} = Continuation.get(c.store, "sequence")

      assert {:ok, %{status: :completed, output: "leaf output"}} =
               Writer.step_status(record, c.config, "A")

      assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
      assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
      refute_receive {:model_io, _}
    end
  end

  @tag mapped: true
  test "changed step identity and host refs reject before codec/mapping/model callbacks", c do
    [step] = c.definition.steps

    for key <- [:definition, :policy, :model_ref, :output_ref] do
      changed_step = put_in(step, [key, "version"], "2")

      assert {:ok, changed} =
               Composition.new(
                 id: c.definition.id,
                 version: c.definition.version,
                 steps: [changed_step]
               )

      assert {:error, :composition_definition_changed} =
               ExAgent.run_composition_step(c.writer, changed, "A")
    end

    changed_step = %{step | input_version: "2"}

    assert {:ok, changed} =
             Composition.new(
               id: c.definition.id,
               version: c.definition.version,
               steps: [changed_step]
             )

    assert {:error, :composition_definition_changed} =
             ExAgent.run_composition_step(c.writer, changed, "A")

    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "unknown")
    refute_receive :codec_dump
    refute_receive :mapping
    refute_receive {:model_io, _}
  end

  test "link, leaf data and ledger/journal corruptions reject in both directions", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:ok, %{record: r}} = Continuation.get(c.store, "sequence")
    root = r["execution"]["progress"]["runtime"]
    [{id, _}] = Map.to_list(root["children"])
    [{effect_id, _}] = Map.to_list(r["execution"]["effects"])

    for frame <- [
          put_in(root, ["children", id, "link", "kind"], "delegation"),
          put_in(root, ["children", id, "link", "input"], "changed"),
          put_in(root, ["children", id, "output_ref", "version"], "2"),
          put_in(root, ["children", id, "frame", "model_data", "index"], 33),
          put_in(root, ["scope", "operations"], []),
          put_in(root, ["children"], %{}),
          put_in(root, ["scope", "operations", Access.at(0), "run_id"], "root")
        ] do
      invalid = put_in(r, ["execution", "progress", "runtime"], frame)

      assert {:error, _} =
               Record.decode(Jason.encode!(invalid), {c.store.namespace, :agent, "sequence"})
    end

    for invalid <- [
          put_in(r, ["execution", "effects"], %{}),
          put_in(
            r,
            ["execution", "effects", effect_id, "outcome", "data", "response_hash"],
            String.duplicate("0", 64)
          ),
          put_in(r, ["execution", "progress"], 42)
        ] do
      assert {:error, _} =
               Record.decode(Jason.encode!(invalid), {c.store.namespace, :agent, "sequence"})
    end
  end

  @tag scope_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 0}]
  test "real leaf admission obeys root limits and cannot replace inherited scope", c do
    assert {:error, _} =
             ExAgent.run_composition_step(c.writer, c.definition, "A",
               parent_context: %{},
               execution_scope: nil
             )

    refute_receive {:model_io, _}
    assert {:ok, ledger} = ExecutionScope.export_tree(c.scope)
    assert ledger["operations"] == []
  end

  @tag checkpoint_limit: 256_000, output: String.duplicate("x", 512_000)
  test "oversized leaf data fails bounded with no automatic second request", c do
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert_receive {:model_io, _}
    assert {:ok, %{record: r}} = Continuation.get(c.store, "sequence")
    assert byte_size(Jason.encode!(r)) < 256_000
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    refute_receive {:model_io, _}
  end

  @tag mapped: true, lease_ms: 200
  test "expired root lease prevents even a mapping callback", c do
    Process.sleep(250)
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    refute_receive :mapping
    refute_receive :codec_dump
    refute_receive {:model_io, _}
  end

  test "confirmed input alone cannot be forged into successful step output", c do
    Agent.update(c.fault, &Map.put(&1, "step_input", :after))
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:ok, %{record: record}} = Continuation.get(c.store, "sequence")
    progress = record["execution"]["progress"]
    [{id, _}] = Map.to_list(progress["runtime"]["children"])

    forged =
      progress
      |> put_in(["runtime", "cursor"], "completed")
      |> put_in(["runtime", "children", id, "status"], "completed")
      |> put_in(["runtime", "children", id, "result"], "invented")
      |> put_in(["runtime", "children", id, "frame", "cursor"], "finish")

    payload =
      Map.merge(
        Map.take(record["execution"], ~w(owner_id attempt_id fence)),
        %{"node_id" => id, "snapshot" => record["snapshot"], "progress" => forged}
      )

    command = %{
      "record_id" => record["record_id"],
      "operation_id" => "forged-finish",
      "operation" => "step_output",
      "actor_id" => "test",
      "payload" => payload
    }

    assert {:error, :invalid_step_transition} =
             Store.transition(c.store, :agent, "sequence", record["revision"], command)

    assert {:ok, ^record} = Store.load_record(c.store, :agent, "sequence")
    refute_receive {:model_io, _}
  end

  @tag active_budget: 5_000
  test "step completion uses the existing active-budget refund contract", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    budget = record["execution"]["progress"]["active_budget"]
    assert budget["limit_ms"] == 5_000
    assert budget["remaining_ms"] in 1..5_000
    assert budget["reserved_ms"] == nil
    assert budget["refund_at"] == nil
  end

  test "step results obey exact JSON J and reject nonportable data", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    assert {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    [id] = Map.keys(record["execution"]["progress"]["runtime"]["children"])
    path = ["execution", "progress", "runtime", "children", id, "result"]
    base = put_in(record, path, "")
    bytes = Record.max_bytes() - byte_size(Jason.encode!(base))
    exact = put_in(base, path, String.duplicate("x", bytes))
    key = {c.store.namespace, :agent, "sequence"}
    assert :ok = Record.validate(exact, key)
    assert {:error, :record_limit} = Record.validate(update_in(exact, path, &(&1 <> "x")), key)
    assert {:error, _} = Record.validate(put_in(base, path, self()), key)
  end
end
