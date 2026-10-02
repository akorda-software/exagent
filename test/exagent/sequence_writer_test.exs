defmodule ExAgent.SequenceWriterTest do
  use ExUnit.Case, async: false
  alias ExAgent.{ExecutionScope, Store}
  alias ExAgent.Continuation.{Record, Writer}
  alias ExAgent.Coordination.Composition

  defmodule NoEncoderOutput do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:count, :integer)
    end
  end

  defmodule ObservedStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, query), do: Store.ETS.scan_records(c.table, ns, query)

    def transition(c, key, expected, command) do
      fault =
        Agent.get_and_update(c.fault, fn modes ->
          {Map.get(modes, command["operation"]), Map.delete(modes, command["operation"])}
        end)

      result =
        if fault == :before,
          do: {:error, :before_commit},
          else: Store.ETS.transition(c.table, key, expected, command)

      send(c.owner, {:transition, command, result})
      if fault == :after, do: {:error, :lost_ack}, else: result
    end
  end

  setup context do
    start_supervised!({Store.ETS, table: __MODULE__})
    fault = start_supervised!({Agent, fn -> %{} end})

    store =
      Store.scoped(
        {ObservedStore, %{table: __MODULE__, owner: self(), fault: fault}},
        "sequence9"
      )

    owner = self()

    steps =
      for id <- ["A", "B", "C"] do
        model = %ExAgent.Models.Test{
          script: [
            fn _, _ ->
              {:ok, record} = Store.load_record(store, :agent, "sequence")
              send(owner, {:io, id, record})

              if context[:typed],
                do:
                  {:tool_calls,
                   [
                     %ExAgent.Message.Part.ToolCall{
                       tool_name: "final_result",
                       tool_call_id: "reused",
                       args: %{"count" => 7}
                     }
                   ]},
                else: id <> " output"
            end
          ]
        }

        tool =
          ExAgent.Tool.new(
            name: "effect",
            parameters_json_schema: %{"type" => "object"},
            call: fn _, _ ->
              send(owner, {:effect, id})
              {:ok, id}
            end
          )

        model =
          if context[:tools],
            do: %{
              model
              | script: [
                  {:tool_calls,
                   [
                     %ExAgent.Message.Part.ToolCall{
                       tool_name: "effect",
                       tool_call_id: "reused",
                       args: %{}
                     }
                   ]}
                  | model.script
                ]
            },
            else: model

        model =
          if context[:retry],
            do: %{
              model
              | script: [
                  {:tool_calls,
                   [
                     %ExAgent.Message.Part.ToolCall{
                       tool_name: "final_result",
                       tool_call_id: "reused",
                       args: %{"count" => "invalid"}
                     }
                   ]}
                  | model.script
                ]
            },
            else: model

        step = %{
          id: id,
          agent:
            ExAgent.new(
              model: model,
              tools: if(context[:tools], do: [tool], else: []),
              output:
                cond do
                  context[:omitted] -> NoEncoderOutput
                  context[:typed] -> ExAgent.ContinuationNativeFixture.CountOutput
                  true -> :text
                end
            ),
          model_codec: %{
            dump: fn m -> {:ok, %{"index" => m.index}} end,
            load: fn m, d -> {:ok, %{m | index: d["index"]}} end
          },
          definition: %{id: "leaf", version: "1"},
          policy: %{id: "policy", version: "1"},
          model_ref: %{id: "model", version: "1"},
          output_ref: %{id: "output", version: "1"}
        }

        if context[:mapped] == true and id == "B" do
          Map.merge(step, %{
            input_version: "1",
            input: fn initial, outputs ->
              {:ok, record} = Store.load_record(store, :agent, "sequence")
              send(owner, {:mapping, initial, outputs, record})

              if context[:mapping_gate] do
                send(owner, {:mapping_blocked, self()})

                receive do
                  :release_mapping -> :ok
                end
              end

              if context[:mapping_error],
                do: {:error, :mapping_failed},
                else: {:ok, %{"from" => outputs["A"]}}
            end
          })
        else
          step
        end
      end

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)
    {:ok, scope} = ExecutionScope.start_structural("root", Map.get(context, :scope_options, []))

    config = %{
      kind: :composition,
      composition: definition,
      store: store,
      id: "sequence",
      definition: %{"id" => "sequence", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000,
      active_time_limit_ms: 60_000
    }

    # Explicit legacy-9 source; current producer-10 has separate runtime coverage.
    {:ok, writer, claim} =
      ExAgent.LegacyStructuralFixture.open(
        %{run_id: "root", execution_scope: scope, input: "initial"},
        config
      )

    on_exit(fn ->
      Writer.stop(writer)
      ExecutionScope.stop(scope)
    end)

    %{
      store: store,
      definition: definition,
      scope: scope,
      writer: writer,
      claim: claim,
      config: config,
      fault: fault
    }
  end

  test "one Writer and Scope persist A then B then C with one terminal refund", c do
    assert is_map(c.claim)

    Enum.reduce(["A", "B", "C"], c.claim, fn id, before ->
      assert {:ok, %{output: output}} = ExAgent.run_composition_step(c.writer, c.definition, id)
      assert output == id <> " output"
      assert_receive {:io, ^id, input_record}
      assert :ok == Record.validate(input_record, {"sequence9", :agent, "sequence"})
      {:ok, after_record} = Store.load_record(c.store, :agent, "sequence")
      assert :ok == Record.validate(after_record, {"sequence9", :agent, "sequence"})
      runtime = after_record["execution"]["progress"]["runtime"]
      assert runtime["frame_version"] == 9
      assert after_record["record_id"] == c.claim["record_id"]

      assert Map.take(
               runtime["children"],
               Map.keys(before["execution"]["progress"]["runtime"]["children"])
             ) == before["execution"]["progress"]["runtime"]["children"]

      if id != "C" do
        assert runtime["cursor"] == "between_steps"

        assert Map.drop(after_record["execution"], ["progress", "effects"]) ==
                 Map.drop(c.claim["execution"], ["progress", "effects"])

        assert after_record["execution"]["progress"]["active_budget"] ==
                 c.claim["execution"]["progress"]["active_budget"]
      else
        assert runtime["cursor"] == "completed"
        assert after_record["execution"]["state"] == "completed"
      end

      after_record
    end)

    {:ok, final} = Store.load_record(c.store, :agent, "sequence")

    children =
      final["execution"]["progress"]["runtime"]["children"]
      |> Map.values()
      |> Enum.sort_by(& &1["link"]["index"])

    assert Enum.map(children, & &1["link"]["input"]) == ["initial", "A output", "B output"]

    assert {:ok, %{output: "C output"}} =
             ExAgent.run_composition_step(c.writer, c.definition, "C")

    assert {:ok, ^final} = Store.load_record(c.store, :agent, "sequence")
    refute_receive {:io, _, _}
  end

  test "out of order requests cannot attach or execute", c do
    assert {:error, :composition_step_unavailable} =
             ExAgent.run_composition_step(c.writer, c.definition, "B")

    assert {:ok, stored} = Store.load_record(c.store, :agent, "sequence")
    assert stored == c.claim
    refute_receive {:io, _, _}
  end

  @tag tools: true, scope_options: [permissions: ExAgent.Permissions.new!(default: :deny)]
  test "real sequence denial retains predispatch evidence and no callable effects", c do
    for id <- ["A", "B", "C"],
        do: assert({:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, id))

    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    frame = record["execution"]["progress"]["runtime"]
    assert map_size(frame["tool_batches"]) == 3

    for batch <- Map.values(frame["tool_batches"]) do
      assert Map.values(batch["observations"]) == [
               ExAgent.Continuation.ToolEvidence.pre_dispatch()
             ]
    end

    assert :ok = Record.validate(record, {"sequence9", :agent, "sequence"})
    result = Composition.project(c.definition, record, c.config)
    assert result.status == :completed and result.request_count == 6
    refute_receive {:effect, _}
  end

  @tag tools: true, typed: true
  test "real completed sequence rejects orphan evidence, removed attestations and foreign effects",
       c do
    for id <- ["A", "B", "C"],
        do: assert({:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, id))

    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    frame = record["execution"]["progress"]["runtime"]
    {request, resolution} = Enum.at(frame["output_resolutions"], 0)
    {effect, data} = Enum.at(record["execution"]["effects"], 0)

    corruptions = [
      put_in(
        record,
        ["execution", "progress", "runtime", "output_resolutions", "orphan"],
        resolution
      ),
      update_in(
        record,
        ["execution", "progress", "runtime", "output_resolutions"],
        &Map.delete(&1, request)
      ),
      put_in(
        record,
        ["execution", "effects", effect],
        put_in(data, ["intent", "payload", "run_id"], "foreign")
      )
    ]

    for corrupt <- corruptions,
        do:
          assert(
            {:error, _} = Record.decode(Jason.encode!(corrupt), {"sequence9", :agent, "sequence"})
          )

    assert {:ok, ^record} = Store.load_record(c.store, :agent, "sequence")
  end

  test "descriptor ticket prevents a second descriptor until released", c do
    assert {:ok, ticket} = Writer.step_descriptor(c.writer, c.definition, "A")
    assert ticket.index == 0
    assert ticket.revision == c.claim["revision"]

    assert {:error, :composition_step_unavailable} =
             Writer.step_descriptor(c.writer, c.definition, "A")

    assert :ok = Writer.release_step(c.writer, ticket.ticket)
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
  end

  @tag mapped: true
  test "mapping observes only portable committed outputs and the intermediate Store record", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    {:ok, after_a} = Store.load_record(c.store, :agent, "sequence")
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "B")
    assert_receive {:mapping, "initial", %{"A" => "A output"}, ^after_a}
    assert after_a["execution"]["progress"]["runtime"]["cursor"] == "between_steps"
    refute_receive {:mapping, _, _, _}
  end

  test "cross-PID ticket cannot be released or attached and two requesters have one winner", c do
    parent = self()

    requesters =
      for _ <- 1..2 do
        spawn(fn ->
          receive do
            :go -> :ok
          end

          reply = Writer.step_descriptor(c.writer, c.definition, "A")
          send(parent, {:ticket_result, self(), reply})

          receive do
            :stop -> :ok
          end
        end)
      end

    Enum.each(requesters, &send(&1, :go))

    replies =
      for _ <- 1..2 do
        assert_receive {:ticket_result, pid, reply}
        {pid, reply}
      end

    assert [{winner, {:ok, descriptor}}] = Enum.filter(replies, &match?({_, {:ok, _}}, &1))
    assert Enum.count(replies, &match?({_, {:error, :composition_step_unavailable}}, &1)) == 1

    assert {:error, :invalid_composition_step_ticket} =
             Writer.release_step(c.writer, descriptor.ticket)

    assert {:error, _} = Writer.attach_step(c.writer, descriptor.ticket, %{}, [])
    assert {:ok, stored} = Store.load_record(c.store, :agent, "sequence")
    assert stored == c.claim
    Enum.each(requesters, &send(&1, :stop))
    ref = Process.monitor(winner)
    assert_receive {:DOWN, ^ref, :process, ^winner, _}
  end

  @tag mapped: true, mapping_gate: true
  test "requester death while mapping clears its reservation without attaching or running", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    {:ok, before} = Store.load_record(c.store, :agent, "sequence")
    caller = spawn(fn -> Writer.step_descriptor(c.writer, c.definition, "B") end)
    ref = Process.monitor(caller)
    assert_receive {:mapping_blocked, writer}
    assert writer == c.writer
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, ^caller, :killed}
    send(writer, :release_mapping)
    assert Enum.any?(1..100, fn _ -> is_nil(:sys.get_state(writer).step_ticket) end)
    assert {:ok, ^before} = Store.load_record(c.store, :agent, "sequence")
    refute_receive {:io, "B", _}
  end

  @tag mapped: true, mapping_error: true
  test "mapping error retains the root claim and A without adding B", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    {:ok, before} = Store.load_record(c.store, :agent, "sequence")

    assert {:error, :invalid_composition_input} =
             ExAgent.run_composition_step(c.writer, c.definition, "B")

    assert {:ok, ^before} = Store.load_record(c.store, :agent, "sequence")
    assert :sys.get_state(c.writer).step_ticket == nil
    refute_receive {:io, "B", _}
  end

  for mode <- [:before, :after] do
    @tag mapped: true
    test "output A ACK #{mode} blocks mapping B and token retry is Store-only", c do
      Agent.update(c.fault, &Map.put(&1, "step_output", unquote(mode)))
      assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
      token = Writer.pending(c.writer).token
      assert is_map(token)

      assert {:error, :composition_step_unavailable} =
               ExAgent.run_composition_step(c.writer, c.definition, "B")

      refute_receive {:mapping, _, _, _}
      assert {:ok, _} = ExAgent.Continuation.retry_checkpoint(c.store, token)
      refute_receive {:mapping, _, _, _}
      refute_receive {:io, "B", _}
      {:ok, stored} = Store.load_record(c.store, :agent, "sequence")
      assert stored["execution"]["state"] == "claimed"
      assert stored["execution"]["progress"]["runtime"]["cursor"] == "between_steps"

      assert stored["execution"]["progress"]["active_budget"] ==
               c.claim["execution"]["progress"]["active_budget"]
    end
  end

  for mode <- [:before, :after], operation <- ["step_input", "begin_effect"] do
    @tag mapped: true
    test "B #{operation} ACK #{mode} never authorizes Model IO or another mapping", c do
      assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
      Agent.update(c.fault, &Map.put(&1, unquote(operation), unquote(mode)))
      assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "B")
      assert_receive {:mapping, _, _, _}
      token = Writer.pending(c.writer).token
      assert is_map(token)
      assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "B")
      refute_receive {:mapping, _, _, _}
      refute_receive {:io, "B", _}
      assert {:ok, _} = ExAgent.Continuation.retry_checkpoint(c.store, token)
      refute_receive {:io, "B", _}
      refute_receive {:mapping, _, _, _}
      {:ok, stored} = Store.load_record(c.store, :agent, "sequence")
      assert :ok = Record.validate(stored, {"sequence9", :agent, "sequence"})
    end
  end

  @tag tools: true, typed: true, mapped: true
  test "typed tools A B C share one journal and repeat provider IDs without crossing evidence",
       c do
    for id <- ["A", "B", "C"] do
      assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, id)
      assert_receive {:effect, ^id}
      assert_receive {:io, ^id, _}
      refute_receive {:effect, ^id}
      {:ok, stored} = Store.load_record(c.store, :agent, "sequence")

      assert {:ok, ^stored} =
               Record.decode(Jason.encode!(stored), {"sequence9", :agent, "sequence"})
    end

    assert_receive {:mapping, "initial", %{"A" => %{"count" => 7}}, _}
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    root = record["execution"]["progress"]["runtime"]
    assert map_size(root["tool_batches"]) == 3
    assert map_size(root["output_resolutions"]) == 3
    assert map_size(record["execution"]["effects"]) == 9
    assert length(root["scope"]["operations"]) == 6

    assert {:ok, %{status: :completed, output: %{"count" => 7}}} =
             ExAgent.resume_composition_step(c.definition, Writer.reference(c.writer),
               continuation: c.config
             )

    refute_receive {:effect, _}
    refute_receive {:io, _, _}
  end

  test "multi-leaf active restore rejects when only A is persisted before any host codec", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    ref = Writer.reference(c.writer)
    {:ok, before} = Store.load_record(c.store, :agent, "sequence")

    assert {:error, :unsupported_composition_boundary} =
             ExAgent.resume_composition_step(c.definition, ref, continuation: c.config)

    assert {:ok, ^before} = Store.load_record(c.store, :agent, "sequence")
  end

  test "terminal receipt replay preserves refund exactly", c do
    for id <- ["A", "B", "C"],
        do: assert({:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, id))

    {:ok, final} = Store.load_record(c.store, :agent, "sequence")
    command = final_command()

    assert {:ok, %{replayed: true, record: ^final}} =
             Store.transition(c.store, :agent, "sequence", final["revision"] - 1, command)

    assert {:ok, ^final} = Store.load_record(c.store, :agent, "sequence")
  end

  @tag typed: true, omitted: true, mapped: true
  test "omitted A closes intermediate without refund and blocks any successor mapping", c do
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    root = record["execution"]["progress"]["runtime"]
    assert root["cursor"] == "between_steps"
    assert record["execution"]["state"] == "claimed"
    [child] = Map.values(root["children"])
    assert is_map(child["result_omitted"])

    assert record["execution"]["progress"]["active_budget"] ==
             c.claim["execution"]["progress"]["active_budget"]

    assert :ok = Record.validate(record, {"sequence9", :agent, "sequence"})
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "B")
    refute_receive {:mapping, _, _, _}
    assert {:ok, ^record} = Store.load_record(c.store, :agent, "sequence")
  end

  test "another VM validates intermediate and projects completed bytes without callbacks", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    {:ok, intermediate} = Store.load_record(c.store, :agent, "sequence")

    for id <- ["B", "C"],
        do: assert({:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, id))

    {:ok, completed} = Store.load_record(c.store, :agent, "sequence")
    path = Path.join("/tmp/opencode", "sequence9-vm-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!([intermediate, completed]))
    on_exit(fn -> File.rm(path) end)
    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++ ["test/support/sequence_frame9_vm.exs", path]

    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "FRAME9_VM completed data_only intermediate rejected"
  end

  @tag mapped: true
  test "known receipt exhaustion prevents successor mapping without reducing completed reserve",
       c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    sample = record["receipts"] |> Map.values() |> hd()
    count = 1024 - Record.receipt_reserve(record["execution"])

    exhausted = %{
      record
      | "receipts" => Map.new(1..count, &{"capacity-#{&1}", sample}),
        "revision" => count
    }

    assert :ok = Record.validate(exhausted, {"sequence9", :agent, "sequence"})
    # A valid high-revision boundary, without pretending these copied receipts
    # are additional executed steps. Only the pre-mapping admission is exercised.
    :sys.replace_state(c.writer, &%{&1 | record: exhausted})
    assert {:error, :record_limit} = ExAgent.run_composition_step(c.writer, c.definition, "B")
    refute_receive {:mapping, _, _, _}
    assert :sys.get_state(c.writer).step_ticket == nil
    assert {:ok, ^record} = Store.load_record(c.store, :agent, "sequence")
  end

  test "N greater than one rejects active restore at the very first input ACK", c do
    Agent.update(c.fault, &Map.put(&1, "step_input", :after))
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    [child] = Map.values(record["execution"]["progress"]["runtime"]["children"])
    assert child["frame"]["run_step"] == 0
    assert record["execution"]["effects"] == %{}
    reference = %{id: "sequence", record_id: record["record_id"], revision: record["revision"]}

    assert {:error, :unsupported_composition_boundary} =
             ExAgent.resume_composition_step(c.definition, reference, continuation: c.config)

    assert {:ok, ^record} = Store.load_record(c.store, :agent, "sequence")
    refute_receive {:io, _, _}
  end

  defp final_command do
    receive do
      {:transition, %{"operation" => "step_output"} = command, {:ok, %{record: record}}} ->
        if record["execution"]["state"] == "completed", do: command, else: final_command()

      {:transition, _, _} ->
        final_command()
    after
      0 -> flunk("missing terminal command")
    end
  end

  @tag mapped: true, scope_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 1}]
  test "root quota exhausted by A blocks mapping B before admission", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    {:ok, before} = Store.load_record(c.store, :agent, "sequence")

    assert {:error, {:usage_limit_exceeded, :request_limit, 1}} =
             ExAgent.run_composition_step(c.writer, c.definition, "B")

    refute_receive {:mapping, _, _, _}
    refute_receive {:io, "B", _}
    assert {:ok, ^before} = Store.load_record(c.store, :agent, "sequence")
  end

  @tag tools: true
  test "all-pending ask pauses durably without tool effect or successor", c do
    assert {:ok, %{status: :paused} = result} =
             ExAgent.run_composition_step(c.writer, c.definition, "A",
               permissions: ExAgent.Permissions.new!(default: :ask)
             )

    refute_receive {:effect, _}
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    assert record["execution"]["state"] == "pending"
    assert record["revision"] == result.continuation.revision
    assert record["execution"]["progress"]["runtime"]["cursor"] == "running"
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "B")
    assert :ok = Record.validate(record, {"sequence9", :agent, "sequence"})
  end

  @tag tools: true, typed: true, retry: true
  test "output retry counters and repeated call IDs stay leaf-local throughout the sequence", c do
    for id <- ["A", "B", "C"] do
      assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, id)
    end

    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    root = record["execution"]["progress"]["runtime"]
    assert map_size(record["execution"]["effects"]) == 12
    assert map_size(root["output_resolutions"]) == 6

    for {_, child} <- root["children"] do
      assert child["frame"]["run_step"] == 3
      assert child["frame"]["output_retries_used"] == 1
      assert child["frame"]["scope"]["requests"] == 3
    end

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {"sequence9", :agent, "sequence"})
  end

  test "CAS rejects wrong active node and mutation of completed A in B input", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    {:ok, before} = Store.load_record(c.store, :agent, "sequence")
    [a] = Map.keys(before["execution"]["progress"]["runtime"]["children"])
    Agent.update(c.fault, &Map.put(&1, "step_input", :before))
    assert {:error, _} = ExAgent.run_composition_step(c.writer, c.definition, "B")
    command = Writer.pending(c.writer).token["command"]
    key = {"sequence9", :agent, "sequence"}
    now = System.system_time(:millisecond)

    assert {:error, _} =
             ExAgent.Continuation.Transition.apply(
               before,
               key,
               before["revision"],
               put_in(command, ["payload", "node_id"], a),
               now
             )

    corrupt =
      put_in(command, ["payload", "progress", "runtime", "children", a, "result"], "forged")

    assert {:error, _} =
             ExAgent.Continuation.Transition.apply(before, key, before["revision"], corrupt, now)

    assert {:ok, %{record: valid}} =
             ExAgent.Continuation.Transition.apply(before, key, before["revision"], command, now)

    assert :ok = Record.validate(valid, key)
    assert {:ok, ^before} = Store.load_record(c.store, :agent, "sequence")
  end

  test "decode rejects premature terminal state and preserves the completed iff invariant", c do
    assert {:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, "A")
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    invalid = put_in(record, ["execution", "progress", "runtime", "cursor"], "completed")
    assert {:error, _} = Record.decode(Jason.encode!(invalid), {"sequence9", :agent, "sequence"})

    for id <- ["B", "C"],
        do: assert({:ok, _} = ExAgent.run_composition_step(c.writer, c.definition, id))

    {:ok, final} = Store.load_record(c.store, :agent, "sequence")

    invalid =
      update_in(
        final,
        ["execution"],
        &Map.merge(
          &1,
          Map.take(c.claim["execution"], ~w(state owner_id attempt_id fence lease_until))
        )
      )

    assert {:error, _} = Record.decode(Jason.encode!(invalid), {"sequence9", :agent, "sequence"})
  end
end
