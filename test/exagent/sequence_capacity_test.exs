defmodule ExAgent.SequenceCapacityTest do
  # This suite checks the historical frame-9 journal/receipt contract. Its fresh
  # sources are authentic CAS/codec-checked 9 records, resumed by the public API.
  # Producer-10 mixed C7, ACK, counters and delegation are tested independently.
  use ExUnit.Case, async: false

  alias ExAgent.{Continuation, Retention, RunError, Store}
  alias ExAgent.Continuation.{Frame, Record, Transition}
  alias ExAgent.Coordination.Composition

  # This adapter records the real Writer command and drops its ACK before commit.
  # All successful writes and all capacity probes use the real ETS CAS reducer.
  defmodule BoundaryStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, query), do: Store.ETS.scan_records(c.table, ns, query)

    def transition(c, key, revision, command) do
      frame = get_in(command, ["payload", "progress", "runtime"])

      hit =
        case c.boundary do
          :output_a ->
            command["operation"] == "step_output" and frame["cursor"] == "between_steps" and
              is_nil(frame["children"][Frame.active_step_id(frame)]["result_omitted"])

          :input_b ->
            command["operation"] == "step_input" and map_size(frame["children"]) == 2

          :intent_b ->
            command["operation"] == "begin_effect" and
              get_in(command, ["payload", "intent", "payload", "run_id"]) ==
                Frame.active_step_id(frame) and map_size(frame["children"]) == 2
        end

      if hit do
        send(c.owner, {:boundary, command})
        {:error, :boundary_ack_lost}
      else
        before = Store.ETS.load_record(c.table, key)
        result = Store.ETS.transition(c.table, key, revision, command)
        send(c.owner, {:committed, before, command, result})
        result
      end
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    :ok
  end

  for boundary <- [:output_a, :input_b, :intent_b] do
    @boundary boundary
    test "#{boundary}: public Writer checkpoint limit exact minus/at/plus gates the real command" do
      trial = fn limit -> capture(@boundary, limit) end
      assert {true, _} = trial.(512_000)
      exact = threshold(1, 512_000, trial)
      assert {false, rejected} = trial.(exact - 1)
      assert {true, accepted} = trial.(exact)
      assert {true, _} = trial.(exact + 1)
      assert accepted.continuation_checkpoint != nil

      accepted_frame =
        accepted.continuation_checkpoint["command"]["payload"]["progress"]["runtime"]

      a =
        Enum.find_value(accepted_frame["children"], fn {_, child} ->
          if child["link"]["step_id"] == "A", do: child
        end)

      assert a["result"] == String.duplicate("a", 30_000)
      assert a["result_omitted"] == nil

      if @boundary == :intent_b do
        assert exact > Retention.bytes(accepted.continuation_checkpoint)
        assert rejected.error_phase == :execute
      else
        assert exact == Retention.bytes(accepted.continuation_checkpoint)
        assert rejected.error_phase == if(@boundary == :output_a, do: :checkpoint, else: :prepare)
      end

      IO.inspect(
        %{
          boundary: @boundary,
          writer_limit: exact,
          dispatched_token_bytes: Retention.bytes(accepted.continuation_checkpoint),
          rejected_phase: rejected.error_phase
        },
        label: "SEQUENCE_WRITER_CAPACITY"
      )
    end

    @boundary boundary
    test "#{boundary}: real command JSON minus/exact/plus includes cleanup reserve and CAS replay" do
      c = capture(@boundary)
      {base, command} = prepare(c, 0)
      {:ok, %{record: projected}} = apply_command(c, base, command)
      room = Record.max_bytes() - measured(projected)
      assert room > 0

      for delta <- [-1, 0, 1] do
        # Metadata is inert host data, not invented structural/effect evidence.
        # IntentB's unchanged snapshot is committed by node_checkpoint first;
        # input/output commands carry metadata in their mutable snapshot.
        {before, candidate} = prepare(c, room + delta)
        assert {:ok, _} = Record.encode(before, c.key)
        install(c, before)

        if delta <= 0 do
          assert {:ok, %{record: after_record, replayed: false}} = cas(c, before, candidate)
          assert measured(after_record) == Record.max_bytes() + delta
          assert Record.cleanup_reserve_bytes(after_record) > 0
          assert Record.receipt_reserve(after_record["execution"]) > 0

          IO.inspect(
            %{
              boundary: @boundary,
              delta: delta,
              json: byte_size(Jason.encode!(after_record)),
              cleanup: Record.cleanup_reserve_bytes(after_record),
              receipts: map_size(after_record["receipts"]),
              reserve: Record.receipt_reserve(after_record["execution"])
            },
            label: "SEQUENCE_CAS_CAPACITY"
          )

          assert {:ok, %{record: ^after_record, replayed: true}} = cas(c, before, candidate)

          assert after_record["execution"]["progress"]["active_budget"] ==
                   before["execution"]["progress"]["active_budget"]

          cleanup(c, after_record)
        else
          assert {:error, :record_limit} = cas(c, before, candidate)
          assert {:ok, ^before} = Store.load_record(c.store, :agent, "run")
        end
      end

      assert_no_more_io()
    end

    @boundary boundary
    test "#{boundary}: checkpoint token minus/exact/plus reaches CAS only within public limit" do
      c = capture(@boundary)
      node = Frame.active_step_id(c.token["command"]["payload"]["progress"]["runtime"])

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

      base = put_in(c.token, path, "")
      room = Record.max_bytes() - Retention.bytes(base)

      for delta <- [-1, 0, 1] do
        token = put_in(base, path, String.duplicate("x", room + delta))
        assert Retention.bytes(token) == Record.max_bytes() + delta
        assert {:error, reason} = Continuation.retry_checkpoint(c.store, token)

        IO.inspect(
          %{boundary: @boundary, delta: delta, bytes: Retention.bytes(token), reason: reason},
          label: "SEQUENCE_TOKEN_CAPACITY"
        )

        if delta <= 0,
          do: assert(reason == :record_limit),
          else: assert(reason == :invalid_checkpoint_token)

        assert {:ok, current} = Store.load_record(c.store, :agent, "run")
        assert current == c.record
      end

      assert {:ok, %{record: committed, replayed: false}} =
               Continuation.retry_checkpoint(c.store, c.token)

      assert {:ok, %{record: ^committed, replayed: true}} =
               Continuation.retry_checkpoint(c.store, c.token)

      cleanup(c, committed)
      assert_no_more_io()
    end

    @boundary boundary
    @tag timeout: 120_000
    test "#{boundary}: actual checkpoint receipts preserve exact horizon and cleanup" do
      c = capture(@boundary)
      {:ok, %{record: projected}} = apply_command(c, c.record, c.command)
      reserve = Record.receipt_reserve(projected["execution"])
      target_count = 1024 - reserve - 2
      {seed, closing} = if @boundary == :input_b, do: c.before_output, else: {c.record, nil}
      install(c, seed)
      seed_count = target_count - if(closing, do: 1, else: 0)

      # Grow the journal using genuine no-change node checkpoints. No fabricated
      # receipts/revisions, no altered invariant functions or clock sleeps.
      before =
        Enum.reduce(1..(seed_count - map_size(seed["receipts"])), seed, fn n, record ->
          command = checkpoint(record, "receipt-#{n}")
          assert {:ok, %{record: next}} = cas(c, record, command)
          next
        end)

      for delta <- [-1, 0, 1] do
        # The three real prefixes differ by one actual receipt. Obtain the lower
        # prefix from the recorded predecessor rather than manufacturing a map.
        install(c, before)

        if @boundary == :output_a and delta == 1 do
          exact = add_receipts(c, before, 1)
          assert map_size(exact["receipts"]) + Record.receipt_reserve(exact["execution"]) == 1024
          # Output consumes its reserved receipt: an overfull predecessor cannot
          # be created through CAS. Reject the +1 checkpoint, keep output writable.
          assert {:error, :receipt_limit} = cas(c, exact, checkpoint(exact, "overfull"))
          assert {:ok, ^exact} = Store.load_record(c.store, :agent, "run")
          assert {:ok, %{record: committed}} = cas(c, exact, c.command)
          cleanup(c, committed)
        else
          prefix = add_receipts(c, before, delta + 1)

          prefix =
            if closing do
              assert {:ok, %{record: next}} = cas(c, prefix, closing)
              next
            else
              prefix
            end

          assert {:ok, _} = Record.encode(prefix, c.key)

          if delta <= 0 do
            assert {:ok, %{record: committed}} = cas(c, prefix, c.command)

            assert map_size(committed["receipts"]) +
                     Record.receipt_reserve(committed["execution"]) ==
                     1024 + delta

            assert {:ok, %{record: ^committed, replayed: true}} = cas(c, prefix, c.command)
            cleanup(c, committed)
          else
            assert {:error, :receipt_limit} = cas(c, prefix, c.command)
            assert {:ok, ^prefix} = Store.load_record(c.store, :agent, "run")
            cleanup(c, prefix)
          end
        end
      end

      assert_no_more_io()
    end
  end

  defp capture(boundary, limit \\ nil) do
    owner = self()
    ownership = :ets.new(:capacity_ownership, [:public])
    raw = Store.scoped({Store.ETS, __MODULE__}, "sequence-capacity")
    {:ok, physical} = Record.key({raw.namespace, :agent, "run"})
    :ets.delete(__MODULE__, physical)
    config = %{table: __MODULE__, owner: owner, boundary: boundary}
    store = Store.scoped({BoundaryStore, config}, raw.namespace)

    steps =
      for id <- ["A", "B", "C"] do
        %{
          id: id,
          agent:
            ExAgent.new(
              model: %ExAgent.Models.Test{
                script: [
                  fn _, _ ->
                    if id == "A" do
                      # Resume claims before opening the actual runtime Scope.
                      {:monitored_by, monitors} = Process.info(self(), :monitored_by)

                      scope =
                        Enum.find(monitors, fn pid ->
                          case Process.info(pid, :dictionary) do
                            {:dictionary, dictionary} ->
                              dictionary[:"$initial_call"] == {ExAgent.ExecutionScope, :init, 1}

                            _ ->
                              false
                          end
                        end)

                      assert is_pid(scope)
                      # Registration runs in the Writer, IO in a Model task.
                      # A private fixture cell passes the actual registered PID.
                      [{:writer, writer}] = :ets.lookup(ownership, :writer)
                      assert is_pid(writer)
                      send(owner, {:owned, writer, scope})
                    end

                    send(owner, {:io, id})
                    if limit && id == "A", do: String.duplicate("a", 30_000), else: id
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
            load: fn _, _ -> raise "no restore" end
          }
        }
      end

    steps =
      if limit do
        Enum.map(steps, fn
          %{id: "B"} = step ->
            Map.merge(step, %{
              input_version: "1",
              input: fn _, _ ->
                {:ok,
                 if(boundary == :input_b, do: String.duplicate("b", 100_000), else: "B input")}
              end
            })

          step ->
            step
        end)
      else
        steps
      end

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

    config = %{
      store: store,
      id: "run",
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 600_000,
      active_time_limit_ms: 600_000,
      on_writer: fn writer ->
        true = :ets.insert(ownership, {:writer, writer})
        :ok
      end
    }

    config = if limit, do: Map.put(config, :max_checkpoint_bytes, limit), else: config

    outcome =
      try do
        ExAgent.LegacyStructuralFixture.run(definition, "initial", continuation: config)
      after
        :ets.delete(ownership)
      end

    assert {:error, %RunError{partial: result}} = outcome

    if limit do
      hit =
        receive do
          {:boundary, _} -> true
        after
          0 -> false
        end

      drain_probe()
      {hit, result}
    else
      captured(raw, boundary, result)
    end
  end

  defp captured(raw, boundary, result) do
    assert_receive {:boundary, command}
    assert_receive {:io, "A"}
    assert_receive {:owned, writer, scope}

    for pid <- [writer, scope] do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
    end

    assert_no_more_io()
    assert result.continuation_checkpoint["command"] == command
    assert {:ok, record} = Store.load_record(raw, :agent, "run")
    key = {raw.namespace, :agent, "run"}
    assert :ok = Record.validate(record, key)

    %{
      store: raw,
      key: key,
      record: record,
      command: command,
      token: result.continuation_checkpoint,
      boundary: boundary,
      before_output: before_output(nil)
    }
  end

  defp prepare(c, padding) do
    install(c, c.record)
    node = Frame.active_step_id(c.command["payload"]["progress"]["runtime"])
    path = ["progress", "runtime", "children", node, "snapshot", "metadata", "padding"]
    command = Map.update!(c.command, "payload", &put_in(&1, path, String.duplicate("x", padding)))

    if c.boundary in [:input_b, :output_a] do
      {c.record, command}
    else
      check = checkpoint(c.record, "metadata")
      check = update_in(check["payload"], &put_in(&1, path, String.duplicate("x", padding)))
      assert {:ok, %{record: before}} = cas(c, c.record, check)
      {before, command}
    end
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
          "node_id" => Frame.active_step_id(e["progress"]["runtime"]),
          "snapshot" => record["snapshot"],
          "progress" => e["progress"]
        })
    }
  end

  defp add_receipts(_c, record, 0), do: record

  defp add_receipts(c, record, n) do
    Enum.reduce(1..n, record, fn i, r ->
      assert {:ok, %{record: next}} = cas(c, r, checkpoint(r, "extra-#{i}"))
      next
    end)
  end

  defp apply_command(c, record, command),
    do:
      Transition.apply(
        record,
        c.key,
        record["revision"],
        command,
        System.system_time(:millisecond)
      )

  defp cas(c, record, command),
    do: Store.transition(c.store, :agent, "run", record["revision"], command)

  defp measured(record),
    do: byte_size(Jason.encode!(record)) + Record.cleanup_reserve_bytes(record)

  defp install(c, record) do
    {:ok, bytes} = Record.encode(record, c.key)
    {:ok, key} = Record.key(c.key)
    :ets.insert(__MODULE__, {key, bytes})
  end

  defp cleanup(c, record) do
    command = %{
      "record_id" => record["record_id"],
      "operation_id" => String.duplicate(<<1>>, 512),
      "actor_id" => String.duplicate(<<2>>, 512),
      "operation" => "cancel",
      "payload" => %{}
    }

    assert {:ok, %{record: cancelled, replayed: false}} = cas(c, record, command)

    if Record.unresolved?(record["execution"]) do
      assert cancelled["execution"]["state"] == "uncertain"
      assert Record.receipt_reserve(cancelled["execution"]) > 0
      assert cancelled["execution"]["effects"] == record["execution"]["effects"]
    else
      assert cancelled["execution"]["state"] == "cancelled"
      assert Record.receipt_reserve(cancelled["execution"]) == 0
    end

    assert {:ok, _} = Record.encode(cancelled, c.key)

    assert cancelled["execution"]["progress"]["active_budget"]["remaining_ms"] ==
             record["execution"]["progress"]["active_budget"]["remaining_ms"]

    assert {:ok, %{record: ^cancelled, replayed: true}} = cas(c, record, command)
  end

  defp assert_no_more_io do
    refute_receive {:io, _}, 0
  end

  defp before_output(found) do
    receive do
      {:committed, {:ok, before}, %{"operation" => "step_output"} = command, {:ok, _}} ->
        before_output({before, command})

      {:committed, _, _, _} ->
        before_output(found)
    after
      0 -> found
    end
  end

  defp threshold(low, high, _) when low == high, do: low

  defp threshold(low, high, trial) do
    mid = div(low + high, 2)

    case trial.(mid) do
      {true, _} -> threshold(low, mid, trial)
      {false, _} -> threshold(mid + 1, high, trial)
    end
  end

  defp drain_probe do
    receive do
      {:owned, writer, scope} ->
        for pid <- [writer, scope] do
          ref = Process.monitor(pid)
          assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
        end

        drain_probe()

      {:committed, _, _, _} ->
        drain_probe()

      {:io, "A"} ->
        drain_probe()
    after
      0 -> assert_no_more_io()
    end
  end
end
