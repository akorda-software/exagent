defmodule ExAgent.StructuralRootPersistenceTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, ExecutionScope, Store}
  alias ExAgent.Continuation.{Checkpoint, Frame, Record, Transition, Writer}
  alias ExAgent.Coordination.Composition

  defmodule LostAckStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, namespace, query), do: Store.ETS.scan_records(c.table, namespace, query)

    def transition(c, key, expected, command) do
      result = Store.ETS.transition(c.table, key, expected, command)
      if Agent.get_and_update(c.fault, &{&1, false}), do: {:error, :lost_ack}, else: result
    end
  end

  test "lost create ACK retains only data and replays through Checkpoint before a fresh claim",
       c do
    fault = start_supervised!({Agent, fn -> true end})
    store = Store.scoped({LostAckStore, %{table: __MODULE__, fault: fault}}, c.store.namespace)
    config = %{c.config | store: store}

    assert {:ok, writer, {:error, {:continuation_checkpoint_failed, _}}} =
             Writer.open(c.run, config)

    on_exit(fn -> Writer.stop(writer) end)
    token = Writer.pending(writer).token |> Jason.encode!() |> Jason.decode!()
    assert token["command"]["operation"] == "create"
    assert token["command"]["payload"]["execution"]["kind"] == "composition"
    assert {:ok, ready} = Store.load_record(store, :agent, "root")
    assert ready["revision"] == 1
    assert ready["execution"]["state"] == "ready"
    assert {:error, :unsupported_structural_operation} = Writer.model_begin(writer, %{})
    Writer.stop(writer)
    assert {:ok, checkpoint} = Checkpoint.new(store, :agent, "root", :ephemeral)
    checkpoint = %{checkpoint | pending: {:absent, token["command"]}}

    assert {{:ok, %{record: ^ready, replayed: true}}, %{pending: nil}} =
             Checkpoint.retry(checkpoint)

    assert {:ok, next, claimed} = Writer.open(c.run, config, ready)
    on_exit(fn -> Writer.stop(next) end)
    assert claimed["record_id"] == ready["record_id"]
    assert claimed["revision"] == 2
    assert claimed["execution"]["state"] == "claimed"
  end

  test "input JSON and token bounds reject before callbacks, with cleanup reserve intact", c do
    {_, record} = open(c)
    key = {c.store.namespace, :agent, "root"}
    assert Record.cleanup_reserve_bytes(record) > 0
    base = put_in(record, ["execution", "progress", "runtime", "input"], "")

    remaining =
      Record.max_bytes() - byte_size(Jason.encode!(base)) - Record.cleanup_reserve_bytes(base)

    exact =
      put_in(
        base,
        ["execution", "progress", "runtime", "input"],
        String.duplicate("x", remaining)
      )

    assert :ok = Record.validate(exact, key)
    oversized = update_in(exact, ["execution", "progress", "runtime", "input"], &(&1 <> "x"))
    assert {:error, :record_limit} = Record.validate(oversized, key)

    config =
      %{c.config | id: "oversized"}
      |> Map.put(:on_writer, fn _ -> flunk("oversized input reached callback") end)

    assert {:error, _} =
             Writer.open(%{c.run | input: String.duplicate("x", Record.max_bytes())}, config)

    assert {:error, :not_found} = Store.load_record(c.store, :agent, "oversized")
  end

  test "a trusted agent Scope and a structural Scope with leaves cannot be used as an empty root",
       c do
    model = %ExAgent.Models.Test{}
    assert {:ok, agent_scope} = ExecutionScope.start("root-run", model, [])
    on_exit(fn -> ExecutionScope.stop(agent_scope) end)
    config = Map.put(c.config, :on_writer, fn _ -> flunk("invalid root reached callback") end)

    assert {:error, :invalid_structural_root} =
             Writer.open(%{c.run | execution_scope: agent_scope}, config)

    assert {:ok, _} = ExecutionScope.join(c.run.execution_scope, "leaf", model, [])
    assert {:error, :invalid_structural_root} = Writer.open(c.run, config)
    assert {:error, :not_found} = Store.load_record(c.store, :agent, "root")
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    store = Store.scoped({Store.ETS, __MODULE__}, "structural-root")
    callback = fn _ -> flunk("no root codec or leaf callback") end

    step = %{
      id: "A",
      agent: ExAgent.new(model: %ExAgent.Models.Test{}),
      definition: %{id: "agent", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"},
      model_codec: %{dump: callback, load: fn _, _ -> callback.(nil) end},
      input: fn _, _ -> callback.(nil) end,
      input_version: "1"
    }

    assert {:ok, definition} = Composition.new(id: "pipeline", version: "1", steps: [step])
    assert {:ok, scope} = ExecutionScope.start_structural("root-run", [])
    on_exit(fn -> ExecutionScope.stop(scope) end)

    config = %{
      kind: :composition,
      composition: definition,
      store: store,
      id: "root",
      definition: %{"id" => "pipeline", "version" => "1"},
      policy: %{"id" => "root-policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000
    }

    run = %{run_id: "root-run", execution_scope: scope, input: %{"hello" => [1, true]}}
    %{store: store, config: config, run: run, definition: definition}
  end

  test "empty structural root persists and claims through the existing Writer and Store", c do
    assert {:ok, config} = Writer.config(c.config)
    assert {:ok, writer, record} = Writer.open(c.run, config)
    on_exit(fn -> Writer.stop(writer) end)
    assert is_map(record)
    assert record["record_version"] == 2
    assert record["revision"] == 2
    assert record["execution"]["state"] == "claimed"
    assert record["execution"]["fence"] == 1
    assert Record.text?(record["execution"]["owner_id"])
    assert Record.text?(record["execution"]["attempt_id"])
    assert Record.text?(record["execution"]["continuation_id"])
    assert record["snapshot"]["revision"] == 0
    assert map_size(record["receipts"]) == 2
    assert record["execution"]["effects"] == %{}
    refute Map.has_key?(record["execution"], "model_ref")
    refute Map.has_key?(record["execution"], "request_id")
    frame = record["execution"]["progress"]["runtime"]
    assert frame["frame_version"] == 10
    assert frame["cursor"] == "empty"
    assert frame["input"] == c.run.input
    assert frame["scope"]["operations"] == []
    assert :ok = Composition.validate_binding(c.definition, frame["binding"])
    assert :ok = Frame.validate(frame)
    key = {c.store.namespace, :agent, "root"}
    assert {:ok, json} = Record.encode(record, key)
    assert {:ok, ^record} = Record.decode(json, key)
    assert {:ok, ^record} = Store.load_record(c.store, :agent, "root")
    assert {:ok, %{record: ^record}} = Continuation.get(c.store, "root")
    assert Writer.reference(writer).revision == 2
    assert Writer.pending(writer).token == nil
    assert {:error, _} = Record.snapshot(record["snapshot"], key)
    assert {:error, :invalid_transition} = Writer.open(c.run, config, record)
    assert {:ok, ^record} = Store.load_record(c.store, :agent, "root")
    Writer.stop(writer)
    refute Process.alive?(writer)
    assert {:ok, ^record} = Store.load_record(c.store, :agent, "root")
  end

  defp open(c) do
    assert {:ok, writer, record} = Writer.open(c.run, c.config)
    on_exit(fn -> Writer.stop(writer) end)
    assert is_map(record)
    {writer, record}
  end

  defp command(record, operation, payload) do
    %{
      "record_id" => record["record_id"],
      "operation" => operation,
      "operation_id" => "operation-#{System.unique_integer([:positive])}",
      "actor_id" => "host",
      "payload" => payload
    }
  end

  for failure <- [:receipt_limit, :expired] do
    test "reopening rejects stored #{failure} before registering an owner", c do
      {writer, record} = open(c)
      Writer.stop(writer)
      key = {c.store.namespace, :agent, "root"}

      assert {:ok, %{record: ready}} =
               Transition.apply(
                 record,
                 key,
                 record["revision"],
                 command(record, "recover", %{}),
                 record["execution"]["lease_until"]
               )

      now = System.system_time(:millisecond)
      ready = Map.put(ready, "updated_at", now)

      stored =
        case unquote(failure) do
          :receipt_limit ->
            receipt = ready["receipts"] |> Map.values() |> hd()
            Map.put(ready, "receipts", Map.new(1..1023, &{"receipt-#{&1}", receipt}))

          :expired ->
            put_in(ready, ["execution", "deadline_at"], now)
        end

      assert {:ok, json} = Record.encode(stored, key)
      assert {:ok, physical} = Record.key(key)
      assert :ets.insert(__MODULE__, {physical, json})
      assert {:ok, ^stored} = Store.load_record(c.store, :agent, "root")
      parent = self()

      config =
        Map.put(c.config, :on_writer, fn _ ->
          send(parent, :registered)
          :ok
        end)

      result = Writer.open(c.run, config, stored)

      case result do
        {:ok, pid, _} -> Writer.stop(pid)
        _ -> :ok
      end

      assert {:ok, ^stored} = Store.load_record(c.store, :agent, "root")
      refute_received :registered
      assert {:error, unquote(failure)} = result
    end
  end

  test "reserved execution and snapshot paths cannot activate a leaf", c do
    {writer, record} = open(c)
    assert {:error, :unsupported_structural_operation} = Writer.model_begin(writer, %{})

    assert {:error, :unsupported_structural_operation} =
             Writer.attach(writer, nil, nil, nil, nil, nil)

    assert {:error, :unsupported_structural_operation} = Writer.finish(writer, nil, "fake")
    assert {:error, :structural_root_requires_definition} = Writer.open(%{}, %{}, record)
    assert {:error, :structural_root_requires_definition} = Frame.restore(%{}, record, %{})

    for operation <- ~w(checkpoint start begin_effect node_checkpoint pause finish reset_snapshot) do
      # Admitted structural operations require a fenced frontier payload;
      # unrelated generic commands remain rejected by the command gate.
      expected =
        case operation do
          op when op in ~w(begin_effect pause finish) -> :invalid_command
          "reset_snapshot" -> :unsupported_structural_operation
          _ -> :invalid_frame10_transition
        end

      assert {:error, ^expected} =
               Store.transition(
                 c.store,
                 :agent,
                 "root",
                 record["revision"],
                 command(record, operation, %{})
               )
    end

    assert {:ok, ^record} = Store.load_record(c.store, :agent, "root")
  end

  test "future and nonempty root frames, mismatched IDs and snapshot bindings fail closed", c do
    {_, record} = open(c)
    key = {c.store.namespace, :agent, "root"}
    frame = record["execution"]["progress"]["runtime"]

    for invalid <- [
          Map.put(frame, "frame_version", 99),
          Map.put(frame, "cursor", "request"),
          Map.put(frame, "children", %{"fake" => %{}}),
          Map.put(frame, "outputs", %{}),
          Map.put(frame, "model_data", nil),
          Map.put(frame, "run_id", "other")
        ] do
      assert {:error, _} = Frame.validate(invalid)
      corrupt = put_in(record, ["execution", "progress", "runtime"], invalid)
      assert {:error, _} = Record.decode(Jason.encode!(corrupt), key)
    end

    for corrupt <- [
          put_in(record, ["execution", "run_id"], "other"),
          put_in(record, ["snapshot", "run_id"], "other"),
          put_in(record, ["snapshot", "revision"], 1),
          put_in(record, ["snapshot", "binding", "id"], "other"),
          put_in(record, ["execution", "request_id"], "fake"),
          put_in(record, ["execution", "model_ref"], %{"id" => "fake", "version" => "1"}),
          put_in(record, ["execution", "progress", "approvals"], %{})
        ] do
      assert {:error, _} = Record.decode(Jason.encode!(corrupt), key)
    end

    assert {:error, _} =
             Record.decode(Jason.encode!(record), {c.store.namespace, :session, "root"})
  end

  test "config, root input, limits and trusted binding reject before owner or leaf callbacks",
       c do
    config =
      Map.put(c.config, :on_writer, fn _ -> flunk("invalid opening reached owner callback") end)

    for invalid <- [
          Map.put(config, :model_ref, %{"id" => "fake", "version" => "1"}),
          Map.put(config, :model_codec, %{}),
          Map.put(config, :request_id, "fake"),
          Map.put(config, :kind, :unknown),
          Map.put(config, :lease_ms, 0),
          Map.put(config, :active_time_limit_ms, -1),
          Map.put(config, :max_checkpoint_bytes, 0),
          Map.put(config, :definition, %{"id" => "changed", "version" => "1"})
        ] do
      assert {:error, _} = Writer.open(c.run, invalid)
    end

    assert {:error, _} = Writer.open(%{c.run | input: self()}, config)
    assert {:error, _} = Writer.open(%{c.run | run_id: "wrong"}, config)

    assert {:error, :record_limit} =
             Writer.open(c.run, Map.put(config, :max_checkpoint_bytes, 1))

    assert {:error, :not_found} = Store.load_record(c.store, :agent, "root")
    {_, record} = open(c)

    assert {:error, :structural_root_changed} =
             Writer.open(%{c.run | input: "changed"}, config, record)

    assert {:error, :structural_root_changed} =
             Writer.open(c.run, put_in(config.policy["version"], "2"), record)

    changed = %{c.definition | version: "2"}

    assert {:ok, changed} =
             Composition.new(id: changed.id, version: changed.version, steps: changed.steps)

    changed_config = %{
      config
      | composition: changed,
        definition: %{"id" => changed.id, "version" => changed.version}
    }

    assert {:error, :structural_root_changed} = Writer.open(c.run, changed_config, record)
    assert {:ok, ^record} = Store.load_record(c.store, :agent, "root")
  end

  test "the same CAS, lease recovery, fencing and data-only checkpoint retry govern the root",
       c do
    # Historical root cancellation has its original 9 contract. Format 10
    # cancellation over a frontier remains guarded until independently proven.
    assert {:ok, writer, record} = ExAgent.LegacyStructuralFixture.open(c.run, c.config)
    on_exit(fn -> Writer.stop(writer) end)
    key = {c.store.namespace, :agent, "root"}
    recovery = command(record, "recover", %{})

    assert {:ok, %{record: ready}} =
             Transition.apply(record, key, 2, recovery, record["execution"]["lease_until"])

    assert ready["execution"]["state"] == "ready"
    assert ready["execution"]["fence"] > record["execution"]["fence"]

    claim =
      command(ready, "claim", %{
        "owner_id" => "new-owner",
        "attempt_id" => "new-attempt",
        "lease_until" => record["execution"]["lease_until"] + 60_000
      })

    assert {:ok, %{record: reclaimed}} =
             Transition.apply(ready, key, ready["revision"], claim, ready["updated_at"])

    assert reclaimed["execution"]["fence"] > ready["execution"]["fence"]
    assert reclaimed["execution"]["owner_id"] == "new-owner"

    assert {:error, :conflict} =
             Transition.apply(
               reclaimed,
               key,
               ready["revision"],
               %{claim | "operation_id" => "second-claim"},
               ready["updated_at"]
             )

    assert {:ok, checkpoint} = Checkpoint.new(c.store, :agent, "root", :ephemeral)
    cancel = command(record, "cancel", %{})
    assert {{:ok, result}, checkpoint} = Checkpoint.write(checkpoint, 2, cancel)
    assert result.record["execution"]["state"] == "cancelled"
    assert result.record["execution"]["owner_id"] == nil
    assert {{:ok, %{replayed: true, record: same}}, _} = Checkpoint.write(checkpoint, 2, cancel)
    assert same == result.record
    assert {:ok, %{record: ^same}} = Continuation.get(c.store, "root")
  end
end
