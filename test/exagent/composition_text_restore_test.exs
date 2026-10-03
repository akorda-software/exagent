defmodule ExAgent.CompositionTextRestoreTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, ExecutionScope, Store}
  alias ExAgent.Continuation.{Record, Writer}
  alias ExAgent.Coordination.Composition

  defmodule SchemaTrap do
    def __schema__(_) do
      send(self(), :ecto_schema)
      raise "schema must not be inspected"
    end
  end

  defmodule CountOutput do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:count, :integer)
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

  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, k), do: Store.ETS.load_record(c.table, k)
    def scan_records(c, n, q), do: Store.ETS.scan_records(c.table, n, q)

    def transition(c, k, r, command) do
      fault = Agent.get(c.fault, & &1)
      op = command["operation"]

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

  setup context do
    start_supervised!({Store.ETS, table: __MODULE__})
    owner = self()

    fault =
      start_supervised!(
        {Agent, fn -> {context[:fault_operation] || "outcome", context[:ack] || :after} end}
      )

    store =
      Store.scoped({FaultStore, %{table: __MODULE__, fault: fault, owner: owner}}, "restore-text")

    model = %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          send(owner, :model_io)

          ExAgent.Message.new_response(
            context[:parts] ||
              [%ExAgent.Message.Part.Text{content: context[:text] || "confirmed text"}],
            usage: context[:usage] || %ExAgent.Message.Usage{input_tokens: 3, output_tokens: 2},
            finish_reason: context[:finish_reason]
          )
        end
      ]
    }

    step = %{
      id: "A",
      agent:
        ExAgent.new(
          model: model,
          output_type: context[:output_type] || :text,
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
    token = Writer.pending(writer).token
    Writer.stop(writer)
    ExecutionScope.stop(scope)
    {:ok, record} = Store.load_record(store, :agent, "sequence")
    {:ok, bytes} = Record.encode(record, {store.namespace, :agent, "sequence"})
    {:ok, ^record} = Record.decode(bytes, {store.namespace, :agent, "sequence"})
    Agent.update(fault, fn _ -> nil end)

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

  defp recover(c) do
    Process.sleep(
      max(0, c.record["execution"]["lease_until"] - System.system_time(:millisecond) + 1)
    )

    assert {:ok, %{record: r}} =
             Continuation.recover(c.store, "sequence",
               record_id: c.record["record_id"],
               revision: c.record["revision"],
               operation_id: "recover-text",
               actor: "admin",
               authorize: fn actor, _, _ -> {:ok, actor} end
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
          estimate_cost: fn _ -> raise "repricing" end,
          root_options: [estimate_cost: fn _, _ -> raise "root repricing" end]
        ],
        extra
      )
    )
  end

  test "first confirmed text closes with consumed request_limit1, unchanged historical ledger and no replay",
       c do
    before = c.record["execution"]["progress"]["runtime"]["scope"]
    assert {:ok, %{output: "confirmed text", run_step: 1}} = resume(c, recover(c))
    assert_receive :codec_load
    assert_receive :registered
    refute_receive :after_model
    refute_receive :model_io
    refute_receive :mapping
    {:ok, r} = Store.load_record(c.store, :agent, "sequence")
    assert r["execution"]["state"] == "completed"
    assert r["execution"]["progress"]["runtime"]["scope"] == before
    [op] = before["operations"]
    assert op["ancestors"]["root"]["accounting"]["cost"]["cents"] == 7
    leaf = hd(Map.keys(r["execution"]["progress"]["runtime"]["children"]))
    assert op["ancestors"][leaf]["accounting"]["cost"]["cents"] == 3
    reference = %{id: "sequence", record_id: r["record_id"], revision: r["revision"]}
    assert {:ok, %{status: :completed, output: "confirmed text"}} = resume(c, reference)
    refute_receive :codec_load
  end

  test "two resumers reach claim barrier; loser invokes no codec or registration", c do
    reference = recover(c)
    Agent.update(c.fault, fn _ -> :barrier end)
    tasks = for _ <- 1..2, do: Task.async(fn -> resume(c, reference) end)
    assert_receive {:claim_waiting, one}, 5_000
    assert_receive {:claim_waiting, two}, 5_000
    refute_receive :codec_load
    send(one, :commit)
    send(two, :commit)
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
    assert_receive :codec_load
    assert_receive :registered
    refute_receive :codec_load
    refute_receive :registered
    refute_receive :after_model
    refute_receive :model_io
    refute_receive :mapping
  end

  @tag ack: :before
  test "response ACK before commit is uncertainty, never executable", c do
    assert {:error, _} = resume(c, recover(c))
    refute_receive :codec_load
    refute_receive :model_io
  end

  test "host typed and native profiles reject before claim or codec", c do
    reference = recover(c)

    for agent <- [
          %{hd(c.definition.steps).agent | output_type: SchemaTrap},
          %{hd(c.definition.steps).agent | output_mode: :native}
        ] do
      step = %{hd(c.definition.steps) | agent: agent}
      assert {:error, _} = resume(%{c | definition: %{c.definition | steps: [step]}}, reference)
      refute_receive :codec_load
      refute_receive :ecto_schema
      {:ok, r} = Store.load_record(c.store, :agent, "sequence")
      assert r["revision"] == reference.revision
    end
  end

  @tag :tmp_dir
  test "portable confirmed response closes in a new BEAM using only real JSON bytes", c do
    path = Path.join(c.tmp_dir, "text-restore-#{System.unique_integer([:positive])}.json")
    File.write!(path, c.bytes)
    on_exit(fn -> File.rm(path) end)
    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++
        ["test/support/composition_text_restore_vm.exs", path]

    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "NEW_VM_TEXT_COMPLETED model=0 mapping=0 after_model=0 tool=0"
    refute_receive :codec_load
    refute_receive :model_io
  end

  for reason <- [:length, :content_filter, :unknown, :incomplete, :error, :tool_calls] do
    @tag finish_reason: reason
    test "confirmed #{reason} response remains excluded before callbacks", c do
      assert {:error, :unsupported_composition_boundary} = resume(c, recover(c))
      refute_receive :codec_load
      refute_receive :registered
      refute_receive :model_io
    end
  end

  @tag text: ""
  test "empty confirmed response cannot trigger a retry", c do
    assert {:error, :unsupported_composition_boundary} = resume(c, recover(c))
    refute_receive :codec_load
    refute_receive :registered
    refute_receive :model_io
  end

  test "corrupt bindings, fingerprint, model state, history, ledger and node reject pre-callback",
       c do
    reference = recover(c)
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    path = ["execution", "progress", "runtime"]
    frame = get_in(record, path)
    [id] = Map.keys(frame["children"])
    {:ok, physical} = Record.key({c.store.namespace, :agent, "sequence"})

    mutations = [
      put_in(frame, ["binding", "id"], "changed"),
      put_in(frame, ["children", id, "model_ref", "version"], "changed"),
      put_in(frame, ["children", id, "frame", "output_fingerprint"], String.duplicate("0", 64)),
      put_in(frame, ["children", id, "frame", "model_data"], %{"index" => 999}),
      put_in(frame, ["children", id, "snapshot", "message_history"], "[]"),
      put_in(frame, ["scope", "operations"], []),
      put_in(frame, ["children", id, "parent_run_id"], "missing"),
      put_in(frame, ["children", id, "frame", "cursor"], "batch"),
      put_in(frame, ["children", id, "frame", "run_step"], 2),
      put_in(frame, ["output_resolutions"], %{"invented" => %{}})
    ]

    for invalid <- mutations do
      :ets.insert(__MODULE__, {physical, Jason.encode!(put_in(record, path, invalid))})
      assert {:error, _} = resume(c, reference)
    end

    refute_receive :codec_load
    refute_receive :registered
    refute_receive :model_io
  end

  for side <- [:before, :after] do
    test "claim ACK #{side} token persists only; old receipts cannot execute", c do
      reference = recover(c)
      Agent.update(c.fault, fn _ -> {"claim", unquote(side)} end)
      assert {:error, {:composition_claim_failed, _, token}} = resume(c, reference)
      refute_receive :codec_load
      refute_receive :registered
      Agent.update(c.fault, fn _ -> nil end)
      assert {:ok, %{record: claimed}} = Continuation.retry_checkpoint(c.store, token)
      ref = %{reference | revision: claimed["revision"]}
      assert {:error, :composition_not_ready} = resume(c, ref)

      assert {:ok, %{replayed: true, record: ^claimed}} =
               Continuation.retry_checkpoint(c.store, c.token)

      assert {:error, :composition_not_ready} = resume(c, ref)
      refute_receive :codec_load
      refute_receive :model_io
    end

    test "output ACK #{side} retries only the exact write and completed query is data-only", c do
      reference = recover(c)
      Agent.update(c.fault, fn _ -> {"step_output", unquote(side)} end)
      assert {:error, %ExAgent.RunError{partial: partial}} = resume(c, reference)
      assert_receive :codec_load
      assert_receive :registered
      Agent.update(c.fault, fn _ -> nil end)

      assert {:ok, %{record: completed}} =
               Continuation.retry_checkpoint(c.store, partial.continuation_checkpoint)

      assert completed["execution"]["state"] == "completed"
      ref = %{reference | revision: completed["revision"]}
      assert {:ok, %{status: :completed, output: "confirmed text"}} = resume(c, ref)
      refute_receive :codec_load
      refute_receive :registered
      refute_receive :model_io
      refute_receive :after_model
    end
  end

  test "response outcome exact token after commit only acknowledges persistence", c do
    assert {:ok, %{replayed: true, record: claimed}} =
             Continuation.retry_checkpoint(c.store, c.token)

    reference = %{id: "sequence", record_id: claimed["record_id"], revision: claimed["revision"]}
    assert {:error, :composition_not_ready} = resume(c, reference)
    refute_receive :codec_load
    refute_receive :registered
    refute_receive :model_io
  end

  for place <- [:root, :leaf] do
    test "current #{place} admission limit never reprices or re-admits historical usage", c do
      limits = %ExAgent.UsageLimits{input_tokens_limit: 2}
      reference = recover(c)

      {c, opts} =
        if unquote(place) == :root do
          {c, [root_options: [usage_limits: limits]]}
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

      assert {:ok, %{request_count: 1, output: "confirmed text"}} = resume(c, reference, opts)
      {:ok, completed} = Store.load_record(c.store, :agent, "sequence")

      assert completed["execution"]["progress"]["runtime"]["scope"] ==
               c.record["execution"]["progress"]["runtime"]["scope"]

      refute_receive :model_io
      refute_receive :after_model
    end
  end

  test "current deadline and checkpoint limit reject before callbacks", c do
    reference = recover(c)

    assert {:error, :deadline_exceeded} =
             resume(c, reference, deadline: System.monotonic_time(:millisecond) - 1)

    assert {:error, :checkpoint_limit} =
             resume(c, reference, continuation: Map.put(c.config, :max_checkpoint_bytes, 1))

    refute_receive :codec_load
    refute_receive :registered
  end

  for kind <- [:max_history_bytes, :max_payload_bytes] do
    test "current #{kind} too narrow prevents closure without replay", c do
      assert {:error, _} = resume(c, recover(c), [{unquote(kind), 1}])
      {:ok, r} = Store.load_record(c.store, :agent, "sequence")
      refute r["execution"]["state"] == "completed"
      refute_receive :model_io
      refute_receive :after_model
    end
  end

  @tag budget: 1_000
  test "crash consumes the active reservation; recovery cannot refill it", c do
    assert {:error, :active_budget_exhausted} =
             resume(c, recover(c), continuation: %{c.config | active_time_limit_ms: 100_000})

    refute_receive :codec_load
    refute_receive :registered
  end

  for delta <- [0, -1] do
    test "history boundary #{delta} bytes uses current retention without replay", c do
      [child] = Map.values(c.record["execution"]["progress"]["runtime"]["children"])
      {:ok, messages} = ExAgent.Message.from_json(child["snapshot"]["message_history"])
      exact = :erlang.external_size(messages)
      result = resume(c, recover(c), max_history_bytes: exact + unquote(delta))

      if unquote(delta) == 0 do
        assert {:ok, %{output: "confirmed text"}} = result
      else
        assert {:error, _} = result
      end

      refute_receive :model_io
      refute_receive :after_model
    end
  end

  @tag usage:
         ExAgent.Message.Usage.normalized(%{
           input_tokens: 3,
           output_tokens: 2,
           cached_tokens: 1,
           reasoning_tokens: 1,
           input_includes_cached: true,
           add_reasoning_to_cost: false
         })
  test "normalized historical quality, details and independently priced ancestors survive exactly",
       c do
    assert {:ok, result} = resume(c, recover(c))
    assert result.usage.input_tokens == 3
    assert result.usage.output_tokens == 2
    assert result.usage.accounting["quality"] == "normalized"
    assert result.usage.accounting["provider_presence"] == "unknown"
    assert result.usage.details["cached_tokens"] == 1
    assert result.usage.details["reasoning_tokens"] == 1
    assert result.cost_cents == 3
    {:ok, completed} = Store.load_record(c.store, :agent, "sequence")

    assert completed["execution"]["progress"]["runtime"]["scope"] ==
             c.record["execution"]["progress"]["runtime"]["scope"]

    refute_receive :model_io
    refute_receive :after_model
  end

  @tag parts: [%ExAgent.Message.Part.ToolCall{tool_name: "effect", tool_call_id: "c", args: %{}}]
  test "confirmed tool response is not mistaken for text consumption", c do
    assert {:error, :unsupported_composition_boundary} = resume(c, recover(c))
    refute_receive :codec_load
    refute_receive :registered
    refute_receive :model_io
  end

  test "omitted but verifiable response is inspectable, never executable", c do
    reference = recover(c)
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    frame = record["execution"]["progress"]["runtime"]
    [id] = Map.keys(frame["children"])
    [effect] = Map.keys(record["execution"]["effects"])
    path = ["execution", "progress", "runtime", "children", id, "snapshot", "message_history"]
    {:ok, [input, response]} = ExAgent.Message.from_json(get_in(record, path))
    response = %{response | payload_omitted: ExAgent.Retention.marker(:response, 2000, 1000)}
    {:ok, hash} = ExAgent.Continuation.Outcome.hash(ExAgent.Message.to_json([response]))

    record =
      record
      |> put_in(path, ExAgent.Message.to_json([input, response]))
      |> put_in(["execution", "effects", effect, "outcome", "data", "response_hash"], hash)

    key = {c.store.namespace, :agent, "sequence"}
    assert {:ok, bytes} = Record.encode(record, key)
    {:ok, physical} = Record.key(key)
    :ets.insert(__MODULE__, {physical, bytes})
    assert {:error, :unsupported_composition_boundary} = resume(c, reference)
    refute_receive :codec_load
    refute_receive :registered
  end

  test "nondeterministic codec cannot relax confirmed model-state evidence", c do
    reference = recover(c)
    [step] = c.definition.steps
    codec = %{step.model_codec | load: fn model, _ -> {:ok, %{model | index: 999}} end}
    c = %{c | definition: %{c.definition | steps: [%{step | model_codec: codec}]}}
    assert {:error, _} = resume(c, reference)
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    refute record["execution"]["state"] == "completed"

    assert record["execution"]["progress"]["runtime"]["scope"] ==
             c.record["execution"]["progress"]["runtime"]["scope"]

    refute_receive :model_io
    refute_receive :after_model
  end

  for delta <- [0, -1] do
    test "output payload exact #{delta} bytes is enforced on consumption", c do
      result =
        resume(c, recover(c),
          max_payload_bytes: :erlang.external_size("confirmed text") + unquote(delta)
        )

      if unquote(delta) == 0 do
        assert {:ok, %{output: "confirmed text"}} = result
      else
        assert {:error, _} = result
      end

      refute_receive :model_io
      refute_receive :after_model
    end
  end

  test "response frame keeps exact receipt and JSON cleanup headroom plus one guards", c do
    record = c.record
    key = {c.store.namespace, :agent, "sequence"}
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
    refute_receive :codec_load
  end

  for reason <- [:stop, :end_turn] do
    @tag finish_reason: reason
    test "normal #{reason} confirmed text closes without another effect", c do
      assert {:ok, %{output: "confirmed text", request_count: 1}} = resume(c, recover(c))
      refute_receive :model_io
      refute_receive :after_model
    end
  end

  for {value, status} <- [{7, "succeeded"}, {"invalid", "retry"}] do
    @tag output_type: CountOutput
    @tag fault_operation: "output_resolution"
    @tag parts: [
           %ExAgent.Message.Part.ToolCall{
             tool_name: "final_result",
             tool_call_id: "out",
             args: %{"count" => value}
           }
         ]
    test "authentic #{status} output preserves omission or new-request admission", c do
      resolutions = c.record["execution"]["progress"]["runtime"]["output_resolutions"]
      assert map_size(resolutions) == 1
      result = resume(c, recover(c))

      if unquote(status) == "succeeded" do
        assert {:error, {:composition_output_omitted, _}} = result
        refute_receive :codec_load
        refute_receive :registered
      else
        assert {:error, %ExAgent.RunError{reason: {:usage_limit_exceeded, :request_limit, 1}}} =
                 result

        assert_receive :codec_load
        assert_receive :registered
      end

      refute_receive :model_io
      refute_receive :after_model
    end
  end
end
