defmodule ExAgent.CompositionOutputSuccessRestoreTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, ExecutionScope, Message, Store, Tool}
  alias ExAgent.Continuation.{Record, Writer}
  alias ExAgent.Coordination.Composition
  alias ExAgent.CompositionOutputSuccessFixture.Output

  defmodule NoEncoder do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:count, :integer)
    end
  end

  defmodule SchemaTrap do
    def __schema__(_) do
      send(self(), :schema_reflection)
      raise "schema reflection forbidden"
    end

    def changeset(_, _) do
      send(self(), :schema_changeset)
      raise "changeset forbidden"
    end
  end

  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, k), do: Store.ETS.load_record(c.table, k)
    def scan_records(c, n, q), do: Store.ETS.scan_records(c.table, n, q)

    def transition(c, k, r, command) do
      fault = Agent.get(c.fault, & &1)
      op = command["operation"]
      send(c.owner, {:operation, op})

      if op == "claim" and fault == :barrier do
        send(c.owner, {:claim_waiting, self()})
        receive do: (:commit -> :ok)
      end

      if fault == {op, :before} do
        {:error, :ack_lost}
      else
        result = Store.ETS.transition(c.table, k, r, command)
        if fault == {op, :after}, do: {:error, :ack_lost}, else: result
      end
    end
  end

  defmodule Hooks do
    use ExAgent.Capability
    defstruct [:owner]

    def after_model_request(cap, state) do
      send(cap.owner, :after_model)
      state
    end
  end

  setup context do
    start_supervised!({Store.ETS, table: __MODULE__})
    owner = self()
    Process.put(:output_success_observer, owner)
    fault = start_supervised!({Agent, fn -> {"output_resolution", context[:ack] || :after} end})

    store =
      Store.scoped(
        {FaultStore, %{table: __MODULE__, fault: fault, owner: owner}},
        "output-success"
      )

    calls = context[:calls] || [call("chosen", "final_result", %{"count" => 7})]

    model = %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          send(owner, :model_io)

          Message.new_response(calls,
            usage: %Message.Usage{input_tokens: 3, output_tokens: 2},
            finish_reason: :tool_calls
          )
        end
      ]
    }

    tool =
      Tool.new(
        name: "sibling",
        parameters_json_schema: %{type: "object"},
        call: fn _, _ ->
          send(owner, :tool_effect)
          raise "sibling executed"
        end
      )

    step = %{
      id: "A",
      agent:
        ExAgent.new(
          model: model,
          output_type: context[:output_type] || Output,
          tools: [tool],
          capabilities: [%Hooks{owner: owner}],
          usage_limits: %ExAgent.UsageLimits{request_limit: 1}
        ),
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, d ->
          send(owner, :codec_load)
          {:ok, %{m | index: d["index"]}}
        end
      },
      input: fn i, _ ->
        send(owner, :mapping)
        {:ok, i}
      end,
      input_version: "1",
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"}
    }

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [step])

    {:ok, scope} =
      ExecutionScope.start_structural("root",
        usage_limits: %ExAgent.UsageLimits{request_limit: 1},
        estimate_cost: fn _, _ -> 7 end
      )

    config = %{
      kind: :composition,
      composition: definition,
      store: store,
      id: "sequence",
      definition: %{"id" => "sequence", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      active_time_limit_ms: context[:budget],
      max_checkpoint_bytes: context[:checkpoint_limit] || 8_388_608,
      lease_ms: 1_000
    }

    # Explicit legacy-9 source; current producer-10 has separate runtime coverage.
    {:ok, writer, _} =
      ExAgent.LegacyStructuralFixture.open(
        %{run_id: "root", execution_scope: scope, input: "original"},
        config
      )

    assert {:error, %ExAgent.RunError{reason: {:continuation_checkpoint_failed, :ack_lost}}} =
             ExAgent.run_composition_step(writer, definition, "A", estimate_cost: fn _ -> 3 end)

    assert_receive :mapping
    assert_receive :model_io
    assert_receive :after_model

    if (context[:output_type] || Output) == Output,
      do: assert_receive({:changeset, %{"count" => _}})

    token = Writer.pending(writer).token
    Writer.stop(writer)
    ExecutionScope.stop(scope)
    {:ok, record} = Store.load_record(store, :agent, "sequence")
    {:ok, bytes} = Record.encode(record, {store.namespace, :agent, "sequence"})
    {:ok, ^record} = Record.decode(bytes, {store.namespace, :agent, "sequence"})
    Agent.update(fault, fn _ -> nil end)
    drain()

    %{
      store: store,
      definition: definition,
      config:
        Map.put(%{config | lease_ms: 60_000}, :on_writer, fn _ ->
          send(owner, :registered)
          :ok
        end),
      record: record,
      bytes: bytes,
      fault: fault,
      token: token
    }
  end

  defp call(id, name, args),
    do: %Message.Part.ToolCall{tool_call_id: id, tool_name: name, args: args}

  defp drain do
    receive do
      _ -> drain()
    after
      0 -> :ok
    end
  end

  defp recover(c) do
    Process.sleep(
      max(0, c.record["execution"]["lease_until"] - System.system_time(:millisecond) + 1)
    )

    assert {:ok, %{record: r}} =
             Continuation.recover(c.store, "sequence",
               record_id: c.record["record_id"],
               revision: c.record["revision"],
               operation_id: "recover-output",
               actor: "admin",
               authorize: fn a, _, _ -> {:ok, a} end
             )

    %{id: "sequence", record_id: r["record_id"], revision: r["revision"]}
  end

  defp resume(c, reference, extra \\ []) do
    ExAgent.resume_composition_step(
      c.definition,
      reference,
      Keyword.merge(
        [
          continuation: c.config,
          estimate_cost: fn _ -> raise "leaf repriced" end,
          root_options: [estimate_cost: fn _, _ -> raise "root repriced" end]
        ],
        extra
      )
    )
  end

  defp no_effects do
    refute_receive {:changeset, _}, 0
    refute_receive :model_io, 0
    refute_receive :after_model, 0
    refute_receive :mapping, 0
    refute_receive :tool_effect, 0
    refute_receive {:operation, "output_resolution"}, 0
    refute_receive :schema_reflection, 0
    refute_receive :schema_changeset, 0
  end

  defp assert_closed(c, reference) do
    assert {:ok, result} = resume(c, reference)
    assert result.output === %{"count" => 7}
    refute is_struct(result.output)
    assert_receive :codec_load
    assert_receive :registered
    no_effects()
    {:ok, final} = Store.load_record(c.store, :agent, "sequence")
    before = c.record["execution"]["progress"]["runtime"]
    after_frame = final["execution"]["progress"]["runtime"]
    assert after_frame["scope"] == before["scope"]
    assert after_frame["output_resolutions"] == before["output_resolutions"]
    assert after_frame["authority"] == before["authority"]
    [entry] = Map.values(before["output_resolutions"])
    [child] = Map.values(after_frame["children"])

    {:ok, [_, _, %Message.Request{parts: parts}]} =
      Message.from_json(child["snapshot"]["message_history"])

    assert Message.to_json([%Message.Request{parts: parts}]) == entry["parts"]
    assert final["execution"]["state"] == "completed"

    assert {:ok, %{output: %{"count" => 7}}} =
             resume(c, %{reference | revision: final["revision"]})

    refute_receive :codec_load, 0
    refute_receive :registered, 0
    no_effects()
  end

  test "confirmed real Ecto success closes with portable map and exact attested returns", c do
    assert_closed(c, recover(c))
  end

  @tag calls: [
         %Message.Part.ToolCall{tool_call_id: "fn-first", tool_name: "sibling", args: %{}},
         %Message.Part.ToolCall{
           tool_call_id: "chosen",
           tool_name: "final_result",
           args: %{"count" => 7}
         },
         %Message.Part.ToolCall{
           tool_call_id: "extra",
           tool_name: "final_result",
           args: %{"count" => 99}
         },
         %Message.Part.ToolCall{tool_call_id: "fn-last", tool_name: "sibling", args: %{}}
       ]
  test "first output and interleaved siblings consume all attested parts once in original attested order",
       c do
    [entry] = Map.values(c.record["execution"]["progress"]["runtime"]["output_resolutions"])
    {:ok, [%Message.Request{parts: parts}]} = Message.from_json(entry["parts"])
    assert Enum.map(parts, & &1.tool_call_id) == ["chosen", "extra", "fn-first", "fn-last"]

    assert Enum.map(parts, & &1.status) == [
             :succeeded,
             :not_executed,
             :not_executed,
             :not_executed
           ]

    assert_closed(c, recover(c))
  end

  test "same declared version does not inspect changed host schema or changeset", c do
    [step] = c.definition.steps

    c = %{
      c
      | definition: %{
          c.definition
          | steps: [%{step | agent: %{step.agent | output_type: SchemaTrap}}]
        }
    }

    assert_closed(c, recover(c))
  end

  test "two fresh claimants reach CAS; only winner gets codec and registration", c do
    reference = recover(c)
    Agent.update(c.fault, fn _ -> :barrier end)
    owner = self()

    tasks =
      for _ <- 1..2,
          do:
            Task.async(fn ->
              Process.put(:output_success_observer, owner)
              resume(c, reference)
            end)

    assert_receive {:claim_waiting, one}, 5_000
    assert_receive {:claim_waiting, two}, 5_000
    refute_receive :codec_load, 0
    refute_receive :registered, 0
    send(one, :commit)
    send(two, :commit)
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, %{output: %{"count" => 7}}}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
    assert_receive :codec_load
    assert_receive :registered
    refute_receive :codec_load, 0
    refute_receive :registered, 0
    no_effects()
  end

  @tag ack: :before
  test "resolution absent before ACK cannot consume until exact token commits then explicit recovery",
       c do
    reference = %{
      id: "sequence",
      record_id: c.record["record_id"],
      revision: c.record["revision"]
    }

    assert {:error, :composition_not_ready} = resume(c, reference)
    {:ok, %{record: ready}} = Continuation.retry_checkpoint(c.store, c.token)
    assert_receive {:operation, "output_resolution"}
    assert map_size(ready["execution"]["progress"]["runtime"]["output_resolutions"]) == 1
    no_effects()
    assert_closed(%{c | record: ready}, recover(%{c | record: ready}))
  end

  @tag ack: :before
  test "missing attestation after recovery rejects before codec and claim", c do
    assert {:error, :unsupported_composition_boundary} = resume(c, recover(c))
    refute_receive :codec_load, 0
    refute_receive :registered, 0
    no_effects()
  end

  test "resolution ACK after commit token only acknowledges data", c do
    assert {:ok, %{replayed: true, record: claimed}} =
             Continuation.retry_checkpoint(c.store, c.token)

    assert_receive {:operation, "output_resolution"}
    reference = %{id: "sequence", record_id: claimed["record_id"], revision: claimed["revision"]}
    assert {:error, :composition_not_ready} = resume(c, reference)
    refute_receive :codec_load, 0
    no_effects()
    assert_closed(c, recover(c))
  end

  for side <- [:before, :after] do
    test "step_output ACK #{side} replays exact command; returns never duplicated", c do
      reference = recover(c)
      Agent.update(c.fault, fn _ -> {"step_output", unquote(side)} end)
      assert {:error, %ExAgent.RunError{partial: partial}} = resume(c, reference)
      assert_receive :codec_load
      assert_receive :registered
      no_effects()
      Agent.update(c.fault, fn _ -> nil end)
      token = partial.continuation_checkpoint
      # Real portable retry token, not retained process state.
      token = token |> Jason.encode!() |> Jason.decode!()
      assert {:ok, %{record: completed}} = Continuation.retry_checkpoint(c.store, token)

      assert {:ok, %{replayed: true, record: ^completed}} =
               Continuation.retry_checkpoint(c.store, token)

      assert completed["execution"]["state"] == "completed"
      [child] = Map.values(completed["execution"]["progress"]["runtime"]["children"])
      [entry] = Map.values(completed["execution"]["progress"]["runtime"]["output_resolutions"])

      {:ok, [_, _, %Message.Request{parts: parts}]} =
        Message.from_json(child["snapshot"]["message_history"])

      assert Message.to_json([%Message.Request{parts: parts}]) == entry["parts"]

      assert {:ok, %{output: %{"count" => 7}}} =
               resume(c, %{reference | revision: completed["revision"]})

      refute_receive :codec_load, 0
      refute_receive :registered, 0
      no_effects()
    end
  end

  test "host versioned refs and text/native profiles reject before callbacks or claim", c do
    reference = recover(c)
    [step] = c.definition.steps

    changed_refs =
      for key <- [:definition, :policy, :model_ref, :output_ref],
          do: Map.update!(step, key, &%{&1 | "version" => "changed"})

    changed_profiles =
      for agent <- [
            %{step.agent | output_type: :text},
            %{step.agent | output_mode: :native, output_type: SchemaTrap}
          ],
          do: %{step | agent: agent}

    for changed <- changed_refs ++ changed_profiles do
      assert {:error, _} =
               resume(%{c | definition: %{c.definition | steps: [changed]}}, reference)

      {:ok, record} = Store.load_record(c.store, :agent, "sequence")
      assert record["revision"] == reference.revision
    end

    refute_receive :codec_load, 0
    refute_receive :registered, 0
    no_effects()
  end

  test "corrupt request/run/call/descriptor/parts/hash/position and duplicate evidence reject preclaim",
       c do
    reference = recover(c)
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    path = ["execution", "progress", "runtime"]
    frame = get_in(record, path)
    [id] = Map.keys(frame["children"])
    [{request, entry}] = Map.to_list(frame["output_resolutions"])
    {:ok, physical} = Record.key({c.store.namespace, :agent, "sequence"})

    entries =
      for {k, v} <- [
            {"run_id", "wrong"},
            {"request_id", "wrong"},
            {"call_id", "wrong"},
            {"descriptor", put_in(entry["descriptor"], ["mode"], "native")},
            {"parts", "[]"},
            {"parts_hash", String.duplicate("0", 64)},
            {"decision", "retry"},
            {"result_omitted", ExAgent.Retention.marker(:checkpoint, 20, 1)}
          ],
          do: put_in(frame, ["output_resolutions", request], Map.put(entry, k, v))

    mutations =
      entries ++
        [
          put_in(frame, ["output_resolutions", "duplicate"], entry),
          put_in(frame, ["children", id, "frame", "model_data"], %{"index" => 999}),
          put_in(frame, ["children", id, "frame", "run_step"], 2),
          put_in(frame, ["children", id, "frame", "cursor"], "batch"),
          put_in(frame, ["scope", "operations"], [])
        ]

    for invalid <- mutations do
      bytes = Jason.encode!(put_in(record, path, invalid))
      assert {:error, _} = Record.decode(bytes, {c.store.namespace, :agent, "sequence"})
      :ets.insert(__MODULE__, {physical, bytes})
      assert {:error, _} = resume(c, reference)
    end

    refute_receive :codec_load, 0
    refute_receive :registered, 0
    no_effects()
  end

  test "attested omission returns explicit error before claim even with a retained resolution",
       c do
    reference = recover(c)
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    [request] = Map.keys(record["execution"]["progress"]["runtime"]["output_resolutions"])
    marker = ExAgent.Retention.marker(:checkpoint, 100, 1)
    path = ["execution", "progress", "runtime", "output_resolutions", request]
    record = update_in(record, path, &%{&1 | "result" => nil, "result_omitted" => marker})
    key = {c.store.namespace, :agent, "sequence"}
    assert {:ok, bytes} = Record.encode(record, key)
    {:ok, physical} = Record.key(key)
    :ets.insert(__MODULE__, {physical, bytes})
    assert {:error, {:composition_output_omitted, ^marker}} = resume(c, reference)
    {:ok, unchanged} = Store.load_record(c.store, :agent, "sequence")
    assert unchanged == record
    refute_receive :codec_load, 0
    refute_receive :registered, 0
    no_effects()
  end

  test "codec dump differing from confirmed evidence cannot close", c do
    reference = recover(c)
    [step] = c.definition.steps
    codec = %{step.model_codec | dump: fn _ -> {:ok, %{"index" => 999}} end}
    c = %{c | definition: %{c.definition | steps: [%{step | model_codec: codec}]}}
    assert {:error, _} = resume(c, reference)
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    refute record["execution"]["state"] == "completed"
    no_effects()
  end

  test "root and leaf historical prices and usage remain distinct without a second debit", c do
    assert {:ok, result} = resume(c, recover(c))

    assert result.request_count == 1 and result.usage.input_tokens == 3 and
             result.usage.output_tokens == 2

    assert result.cost_cents == 3
    {:ok, completed} = Store.load_record(c.store, :agent, "sequence")
    old = c.record["execution"]["progress"]["runtime"]["scope"]
    assert completed["execution"]["progress"]["runtime"]["scope"] == old
    [op] = old["operations"]
    [leaf] = Map.keys(c.record["execution"]["progress"]["runtime"]["children"])
    assert op["ancestors"]["root"]["accounting"]["cost"]["cents"] == 7
    assert op["ancestors"][leaf]["accounting"]["cost"]["cents"] == 3
    no_effects()
  end

  test "logical deadline and checkpoint cap reject preclaim", c do
    reference = recover(c)

    assert {:error, :deadline_exceeded} =
             resume(c, reference, deadline: System.monotonic_time(:millisecond) - 1)

    assert {:error, :checkpoint_limit} =
             resume(c, reference, continuation: Map.put(c.config, :max_checkpoint_bytes, 1))

    refute_receive :codec_load, 0
    refute_receive :registered, 0
    no_effects()
  end

  @tag budget: 1_000
  test "crashed reservation is spent, not refilled at success consumption", c do
    assert {:error, :active_budget_exhausted} =
             resume(c, recover(c), continuation: %{c.config | active_time_limit_ms: 100_000})

    refute_receive :codec_load, 0
    refute_receive :registered, 0
    no_effects()
  end

  for delta <- [0, -1] do
    test "portable output payload exact #{delta} bytes retains existing limit", c do
      result =
        resume(c, recover(c),
          max_payload_bytes: :erlang.external_size(%{"count" => 7}) + unquote(delta)
        )

      if unquote(delta) == 0,
        do: assert(match?({:ok, _}, result)),
        else: assert(match?({:error, _}, result))

      no_effects()
    end
  end

  test "receipt and JSON plus cleanup reserve exact and one-over remain bounded", c do
    key = {c.store.namespace, :agent, "sequence"}
    record = c.record
    assert Record.receipt_reserve(record["execution"]) == 5
    sample = record["receipts"] |> Map.values() |> hd()
    exact = %{record | "receipts" => Map.new(1..1019, &{"r#{&1}", sample}), "revision" => 1019}
    assert {:ok, _} = Record.encode(exact, key)
    over = %{exact | "receipts" => Map.put(exact["receipts"], "over", sample), "revision" => 1020}
    assert {:error, _} = Record.encode(over, key)
    [id] = Map.keys(record["execution"]["progress"]["runtime"]["children"])
    path = ["execution", "progress", "runtime", "children", id, "snapshot", "metadata", "padding"]
    record = put_in(record, path, "")

    remaining =
      Record.max_bytes() - byte_size(Jason.encode!(record)) - Record.cleanup_reserve_bytes(record)

    exact = put_in(record, path, String.duplicate("x", remaining))
    assert {:ok, _} = Record.encode(exact, key)
    assert {:error, :record_limit} = Record.encode(update_in(exact, path, &(&1 <> "x")), key)
    no_effects()
  end

  @tag :tmp_dir
  test "new OS BEAM consumes authentic JSON with schema/model/hook/mapping/tool traps", c do
    path = Path.join(c.tmp_dir, "output-success-#{System.unique_integer([:positive])}.json")
    File.write!(path, c.bytes)
    on_exit(fn -> File.rm(path) end)
    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++
        ["test/support/composition_output_success_vm.exs", path]

    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output

    assert output =~
             "NEW_VM_OUTPUT_COMPLETED portable-map schema=0 changeset=0 model=0 mapping=0 after_model=0 sibling=0"

    no_effects()
  end

  @tag output_type: NoEncoder
  test "real validated nonportable result blocks before claim without inventing nil success", c do
    reference = recover(c)
    [entry] = Map.values(c.record["execution"]["progress"]["runtime"]["output_resolutions"])
    marker = entry["result_omitted"]
    assert is_map(marker) and is_nil(entry["result"])
    assert {:error, {:composition_output_omitted, ^marker}} = resume(c, reference)
    refute_receive :codec_load, 0
    refute_receive :registered, 0
    no_effects()
  end

  @tag output_type: ExAgent.CompositionEvidenceFixture.LargeOutput
  @tag checkpoint_limit: 256_000
  @tag calls: [
         %Message.Part.ToolCall{
           tool_call_id: "chosen",
           tool_name: "final_result",
           args: %{"value" => String.duplicate("x", 100_000)}
         }
       ]
  test "portable attested result with omitted terminal copy remains a retention error, not rescued success",
       c do
    reference = recover(c)
    assert {:error, %ExAgent.RunError{}} = resume(c, reference)
    {:ok, completed} = Store.load_record(c.store, :agent, "sequence")
    frame = completed["execution"]["progress"]["runtime"]
    assert frame["cursor"] == "completed"
    [child] = Map.values(frame["children"])
    [entry] = Map.values(frame["output_resolutions"])
    assert entry["result"] == %{"value" => String.duplicate("x", 100_000)}
    assert entry["result_omitted"] == nil
    assert child["result"] == nil and is_map(child["result_omitted"])

    assert child["result_omitted"] ==
             ExAgent.Retention.marker(
               :checkpoint,
               ExAgent.Retention.bytes(entry["result"]),
               child["result_omitted"]["limit"]
             )

    assert {:error, {:composition_output_omitted, _}} =
             resume(c, %{reference | revision: completed["revision"]})

    no_effects()
  end

  for delta <- [0, -1] do
    test "history including attested returns exact #{delta} bytes is enforced without replay",
         c do
      frame = c.record["execution"]["progress"]["runtime"]
      [child] = Map.values(frame["children"])
      [entry] = Map.values(frame["output_resolutions"])
      {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])
      {:ok, [%Message.Request{parts: parts}]} = Message.from_json(entry["parts"])

      full =
        messages ++
          [
            %Message.Request{
              parts: parts,
              run_id: child["frame"]["run_id"],
              timestamp: DateTime.utc_now()
            }
          ]

      result =
        resume(c, recover(c), max_history_bytes: :erlang.external_size(full) + unquote(delta))

      if unquote(delta) == 0 do
        assert {:ok, %{output: %{"count" => 7}}} = result
      else
        assert {:error, _} = result
        {:ok, record} = Store.load_record(c.store, :agent, "sequence")

        assert record["execution"]["progress"]["runtime"]["output_resolutions"] ==
                 frame["output_resolutions"]

        refute record["execution"]["state"] == "completed"
      end

      no_effects()
    end
  end

  for place <- [:root, :leaf] do
    test "current #{place} limits narrow future admission without repricing confirmed output",
         c do
      reference = recover(c)

      limits = %ExAgent.UsageLimits{
        request_limit: 0,
        input_tokens_limit: 0,
        output_tokens_limit: 0
      }

      {c, opts} =
        if unquote(place) == :root do
          {c,
           [root_options: [usage_limits: limits, estimate_cost: fn _, _ -> raise "repricing" end]]}
        else
          [step] = c.definition.steps

          {%{
             c
             | definition: %{
                 c.definition
                 | steps: [%{step | agent: %{step.agent | usage_limits: limits}}]
               }
           }, []}
        end

      assert {:ok, %{output: %{"count" => 7}, request_count: 1}} = resume(c, reference, opts)
      no_effects()
    end
  end

  @tag calls: [
         %Message.Part.ToolCall{
           tool_call_id: "chosen",
           tool_name: "final_result",
           args: %{"count" => "invalid"}
         }
       ]
  test "authentic retry consumes but cannot exceed original request limit", c do
    [entry] = Map.values(c.record["execution"]["progress"]["runtime"]["output_resolutions"])
    assert entry["decision"] == "retry"

    assert {:error, %ExAgent.RunError{reason: {:usage_limit_exceeded, :request_limit, 1}}} =
             resume(c, recover(c))

    assert_receive :codec_load
    assert_receive :registered
    empty = %{}
    assert_receive {:changeset, ^empty}
    no_effects()
  end

  test "terminal command cannot rewrite attested portable result through CAS or decode", c do
    reference = recover(c)
    Agent.update(c.fault, fn _ -> {"step_output", :before} end)
    assert {:error, %ExAgent.RunError{partial: partial}} = resume(c, reference)
    Agent.update(c.fault, fn _ -> nil end)
    {:ok, current} = Store.load_record(c.store, :agent, "sequence")
    token = partial.continuation_checkpoint
    command = token["command"]
    [request] = Map.keys(current["execution"]["progress"]["runtime"]["output_resolutions"])

    for field <- ["result", "result_omitted"] do
      value =
        if field == "result",
          do: %{"count" => 99},
          else: ExAgent.Retention.marker(:checkpoint, 100, 1)

      changed =
        command
        |> put_in(["payload", "progress", "runtime", "output_resolutions", request, field], value)
        |> Map.put("operation_id", "corrupt-" <> field)

      assert {:error, _} =
               Store.transition(c.store, :agent, "sequence", current["revision"], changed)

      complete =
        current
        |> put_in(["execution", "progress"], changed["payload"]["progress"])
        |> put_in(["execution", "state"], "completed")

      assert {:error, _} =
               Record.decode(Jason.encode!(complete), {c.store.namespace, :agent, "sequence"})
    end

    assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
    no_effects()
  end
end
