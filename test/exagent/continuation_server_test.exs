defmodule ExAgent.ContinuationServerTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Event, Permissions, Server, Store, Tool}
  alias ExAgent.Message.{Part, Response, Usage}

  defmodule DeferredCommitStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record({table, _}, key), do: Store.ETS.load_record(table, key)

    def scan_records({table, _}, namespace, query),
      do: Store.ETS.scan_records(table, namespace, query)

    def transition({table, control}, key, revision, command) do
      defer =
        Agent.get_and_update(control, fn data ->
          if data.block == command["operation"],
            do: {{true, data.owner}, %{data | block: nil}},
            else: {false, data}
        end)

      case defer do
        {true, owner} ->
          caller = self()
          ref = make_ref()

          external =
            spawn(fn ->
              receive do
                :commit ->
                  result = Store.ETS.transition(table, key, revision, command)
                  send(caller, {ref, result})
                  send(owner, {:deferred_result, command["operation"], result})

                :commit_without_ack ->
                  result = Store.ETS.transition(table, key, revision, command)
                  send(owner, {:committed_without_ack, command["operation"], result})

                  receive do
                    :release_ack -> :ok
                  end

                  send(caller, {ref, result})
                  send(owner, {:deferred_ack, command["operation"]})
              end
            end)

          send(owner, {:deferred_commit, command["operation"], external, caller})

          receive do
            {^ref, result} -> result
          end

        false ->
          Store.ETS.transition(table, key, revision, command)
      end
    end
  end

  defmodule BlockingCreateStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record({table, _}, key), do: Store.ETS.load_record(table, key)

    def scan_records({table, _}, namespace, query),
      do: Store.ETS.scan_records(table, namespace, query)

    def transition({table, owner}, key, revision, command) do
      if command["operation"] == "create" do
        send(owner, {:creating_record, self()})

        receive do
          :release_create -> :ok
        end
      end

      Store.ETS.transition(table, key, revision, command)
    end
  end

  defmodule BarrierFaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}

    def load_record({table, control, _}, key),
      do: DeferredCommitStore.load_record({table, control}, key)

    def scan_records({table, control, _}, namespace, query),
      do: DeferredCommitStore.scan_records({table, control}, namespace, query)

    def transition({table, control, fault}, key, revision, command) do
      mode =
        if command["operation"] in ["create_cancelled", "fence_admission"],
          do: Agent.get_and_update(fault, &{&1, :ok}),
          else: :ok

      case mode do
        :before ->
          {:error, :save_failed}

        :after ->
          {:ok, _} = DeferredCommitStore.transition({table, control}, key, revision, command)
          {:error, :ack_lost}

        :ok ->
          DeferredCommitStore.transition({table, control}, key, revision, command)
      end
    end
  end

  defmodule ResetFaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record({table, _}, key), do: Store.ETS.load_record(table, key)

    def scan_records({table, _}, namespace, query),
      do: Store.ETS.scan_records(table, namespace, query)

    def transition({table, fault}, key, revision, command) do
      mode =
        if command["operation"] == "reset_snapshot",
          do: Agent.get_and_update(fault, &{&1, :ok}),
          else: :ok

      mode =
        case mode do
          {:measure, action, owner} ->
            {namespace, :agent, id} = key

            token = %{
              "token_version" => 1,
              "namespace" => namespace,
              "id" => id,
              "expected_revision" => revision,
              "command" => command
            }

            send(owner, {:reset_token_bytes, :erlang.external_size(token)})
            action

          action ->
            action
        end

      case mode do
        :before ->
          {:error, :save_failed}

        :after ->
          {:ok, _} = Store.ETS.transition(table, key, revision, command)
          {:error, :ack_lost}

        :ok ->
          Store.ETS.transition(table, key, revision, command)
      end
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: {Store.ETS, __MODULE__}}
  end

  test "Server pauses after atomic ACK, blocks mutations and retains queued work until resume", %{
    store: store
  } do
    owner = self()

    :ok =
      ExAgent.PubSub.subscribe(
        {ExAgent.PubSub.Local, []},
        Event.agent_topic("conversation", "server-c7")
      )

    server =
      start_supervised!(
        {Server,
         agent: agent(owner),
         agent_id: "conversation",
         namespace: "server-c7",
         store: store,
         continuation: config(),
         pubsub: ExAgent.PubSub.Local}
      )

    opts = [permissions: Permissions.new!(default: :ask)]
    assert {:ok, %{status: :paused} = paused} = Server.chat(server, "first", opts)
    assert Server.health(server).status == :paused
    assert Server.health(server).persistence.mode == :atomic
    assert_receive {:exagent_event, %Event{type: :run_paused, payload: payload}}
    assert payload.continuation.record_id == paused.continuation.record_id
    refute_receive {:exagent_event, %Event{type: :run_finished}}
    assert {:error, :continuation_pending} = Server.chat(server, "blocked")
    assert {:error, :continuation_pending} = Server.reset(server)
    assert {:error, :continuation_pending} = Server.set_model(server, %ExAgent.Models.Test{})
    assert {:ok, _} = Server.send_message(server, "queued")
    assert Server.health(server).pending == 1
    assert_receive {:model, 0}
    refute_receive {:model, 1}
    refute_receive :effect
    assert {:ok, %{status: :pending, record: r}} = Server.continuation(server)
    assert {:ok, _} = Server.decide(server, :approve, decision(r))
    assert Server.health(server).status == :paused

    assert {:ok, %{status: :succeeded, request_count: 2, tool_calls: 1}} =
             Server.resume(server, opts)

    assert_receive :effect
    assert_receive {:model, 1}
    assert_receive {:model, 2}, 2_000

    assert_receive {:exagent_event, %Event{type: :run_finished, payload: %{output: "queued"}}},
                   2_000

    assert Server.health(server).status == :idle
    assert Server.usage(server).input_tokens == 9
    scoped = Store.scoped(store, "server-c7")
    {:ok, record} = Store.load_record(scoped, :agent, "conversation")
    assert record["snapshot"]["usage"]["input_tokens"] == 9
    assert record["execution"]["state"] == "completed"
    refute_receive :effect
  end

  test "Server process restart restores pending data and model without executing IO", %{
    store: store
  } do
    opts = [
      agent: agent(self()),
      agent_id: "conversation",
      namespace: "server-c7",
      store: store,
      continuation: config()
    ]

    {:ok, server} = Server.start_link(opts)

    {:ok, %{status: :paused}} =
      Server.chat(server, "first", permissions: Permissions.new!(default: :ask))

    assert_receive {:model, 0}
    GenServer.stop(server)
    {:ok, restored} = Server.start_link(opts)
    assert Server.health(restored).status == :paused
    assert {:ok, %{record: r}} = Server.continuation(restored)
    refute_receive {:model, _}
    refute_receive :effect
    assert {:ok, _} = Server.decide(restored, :approve, decision(r))

    assert {:ok, %{status: :succeeded}} =
             Server.resume(restored, permissions: Permissions.new!(default: :ask))

    assert_receive :effect
    assert_receive {:model, 1}
    refute_receive {:model, 0}
    assert Server.usage(restored).input_tokens == 6
    GenServer.stop(restored)
  end

  test "terminal atomic reset keeps execution evidence and restores empty conversation", %{
    store: store
  } do
    opts = [
      agent: agent(self()),
      agent_id: "reset",
      namespace: "server-c7",
      store: store,
      continuation: config()
    ]

    {:ok, server} = Server.start_link(opts)
    assert {:ok, %{status: :succeeded}} = Server.chat(server, "first")
    assert_receive :effect
    {:ok, %{record: before}} = Server.continuation(server)
    assert :ok = Server.reset(server)
    assert Server.history(server) == []
    assert Server.usage(server).input_tokens == 0
    {:ok, %{record: after_reset}} = Server.continuation(server)
    assert after_reset["record_id"] == before["record_id"]
    assert after_reset["execution"] == before["execution"]
    assert after_reset["revision"] > before["revision"]
    GenServer.stop(server)
    {:ok, restored} = Server.start_link(opts)
    assert Server.history(restored) == []
    assert Server.usage(restored).input_tokens == 0
    assert {:ok, %{output: "queued"}} = Server.chat(restored, "new conversation")
    refute_receive :effect
    GenServer.stop(restored)
  end

  test "failed reset freezes mutation and retries the identical data command only", %{
    store: {_, table}
  } do
    for mode <- [:before, :after] do
      {:ok, fault} = Agent.start_link(fn -> mode end)
      id = "reset-#{mode}"

      opts = [
        agent: agent(self()),
        agent_id: id,
        namespace: "server-c7",
        store: {ResetFaultStore, {table, fault}},
        continuation: config()
      ]

      {:ok, server} = Server.start_link(opts)
      assert {:ok, _} = Server.chat(server, "first")
      assert_receive :effect
      assert_receive {:model, 0}
      assert_receive {:model, 1}
      {:ok, %{record: original}} = Server.continuation(server)
      assert {:error, %ExAgent.CheckpointError{result: :ok}} = Server.reset(server)
      assert Server.health(server).persistence.dirty
      assert {:error, :checkpoint_pending} = Server.reset(server)
      assert {:error, :checkpoint_pending} = Server.chat(server, "blocked")
      assert {:error, :checkpoint_pending} = Server.send_message(server, "blocked queue")
      assert {:error, :checkpoint_pending} = Server.set_model(server, %ExAgent.Models.Test{})
      assert {:error, :checkpoint_pending} = Server.resume(server)
      assert {:error, :checkpoint_pending} = Server.decide(server, :cancel, [])
      {:ok, %{record: inspected}} = Server.continuation(server)
      assert inspected["revision"] == original["revision"] + if(mode == :after, do: 1, else: 0)
      assert {:ok, %{record: saved, replayed: replayed}} = Server.checkpoint(server)
      assert replayed == (mode == :after)
      assert saved["revision"] == original["revision"] + 1
      assert saved["execution"] == original["execution"]
      assert Server.history(server) == []
      assert Server.health(server).status == :idle
      refute Server.health(server).persistence.dirty
      assert :ok = Server.checkpoint(server)
      {:ok, %{record: ^saved}} = Server.continuation(server)
      refute_receive :effect
      refute_receive {:model, _}
      GenServer.stop(server)
      Agent.stop(fault)
    end
  end

  test "reset_snapshot rejects active and uncertain records without mutating evidence", %{
    store: store
  } do
    {:ok, server} =
      Server.start_link(
        agent: agent(self()),
        agent_id: "reset-deny",
        namespace: "server-c7",
        store: store,
        continuation: config()
      )

    assert {:ok, %{status: :paused}} =
             Server.chat(server, "first", permissions: Permissions.new!(default: :ask))

    scoped = Store.scoped(store, "server-c7")
    {:ok, %{record: pending}} = Server.continuation(server)

    reject = fn record ->
      snapshot =
        ExAgent.Server.Snapshot.new(
          agent_id: "reset-deny",
          history: [],
          usage: Usage.sum([]),
          revision: record["snapshot"]["revision"] + 1
        )

      command = %{
        "record_id" => record["record_id"],
        "operation" => "reset_snapshot",
        "operation_id" => "reject-#{record["revision"]}",
        "actor_id" => "host",
        "payload" => %{"snapshot" => ExAgent.Continuation.Record.snapshot_data(snapshot)}
      }

      assert {:error, :invalid_transition} =
               Store.transition(scoped, :agent, "reset-deny", record["revision"], command)

      assert {:ok, ^record} = Store.load_record(scoped, :agent, "reset-deny")
    end

    reject.(pending)
    assert {:ok, %{record: ready}} = Server.decide(server, :approve, decision(pending))
    reject.(ready)

    command = fn record, operation, payload ->
      Store.transition(scoped, :agent, "reset-deny", record["revision"], %{
        "record_id" => record["record_id"],
        "operation" => operation,
        "operation_id" => "#{operation}-#{record["revision"]}",
        "actor_id" => "host",
        "payload" => payload
      })
    end

    worker = %{
      "owner_id" => "owner",
      "attempt_id" => "attempt",
      "fence" => ready["execution"]["fence"] + 1
    }

    assert {:ok, %{record: claimed}} =
             command.(ready, "claim", %{
               "owner_id" => "owner",
               "attempt_id" => "attempt",
               "lease_until" => System.system_time(:millisecond) + 60_000
             })

    reject.(claimed)

    assert {:ok, %{record: running}} =
             command.(
               claimed,
               "begin_effect",
               Map.merge(worker, %{
                 "effect_id" => "uncertain-effect",
                 "intent" => %{"kind" => "tool", "call_id" => "external", "payload" => %{}}
               })
             )

    assert {:ok, %{record: uncertain}} = command.(running, "cancel", %{})
    assert uncertain["execution"]["state"] == "uncertain"
    reject.(uncertain)
    assert {:error, :continuation_pending} = Server.reset(server)
    GenServer.stop(server)
  end

  test "denial or cancellation keeps queued work blocked until explicit terminal reset", %{
    store: store
  } do
    for action <- [:deny, :cancel] do
      id = "terminal-#{action}"

      :ok =
        ExAgent.PubSub.subscribe({ExAgent.PubSub.Local, []}, Event.agent_topic(id, "server-c7"))

      opts = [
        agent: agent(self()),
        agent_id: id,
        namespace: "server-c7",
        store: store,
        continuation: config(),
        pubsub: ExAgent.PubSub.Local
      ]

      {:ok, server} = Server.start_link(opts)

      assert {:ok, %{status: :paused}} =
               Server.chat(server, "first", permissions: Permissions.new!(default: :ask))

      assert_receive {:model, 0}
      assert {:ok, _} = Server.send_message(server, "queued")
      {:ok, %{record: pending}} = Server.continuation(server)

      options =
        decision(pending)
        |> Keyword.put(:operation_id, Atom.to_string(action))
        |> Keyword.put(:authorize, fn :host, ^action, _ -> {:ok, "human"} end)

      assert {:ok, %{record: terminal}} = Server.decide(server, action, options)

      assert terminal["execution"]["state"] ==
               if(action == :deny, do: "denied", else: "cancelled")

      assert Server.health(server).status == :reset_required
      assert Server.health(server).pending == 1
      assert {:error, :continuation_pending} = Server.chat(server, "bypass")
      assert {:error, :continuation_pending} = Server.stream(server, "bypass")
      refute_receive {:model, 1}
      refute_receive :effect
      assert :ok = Server.reset(server)
      assert_receive {:model, 1}, 1_000

      assert_receive {:exagent_event,
                      %Event{type: :run_finished, agent_id: ^id, payload: %{output: "done"}}},
                     1_000

      assert Server.health(server).pending == 0
      assert Server.health(server).status == :idle
      refute_receive :effect
      GenServer.stop(server)
    end
  end

  test "restart derives reset-required from cancelled persisted history", %{store: store} do
    opts = [
      agent: agent(self()),
      agent_id: "terminal-restart",
      namespace: "server-c7",
      store: store,
      continuation: config()
    ]

    {:ok, server} = Server.start_link(opts)

    assert {:ok, %{status: :paused}} =
             Server.chat(server, "first", permissions: Permissions.new!(default: :ask))

    assert_receive {:model, 0}
    {:ok, %{record: pending}} = Server.continuation(server)

    options =
      decision(pending)
      |> Keyword.put(:operation_id, "cancel")
      |> Keyword.put(:authorize, fn :host, :cancel, _ -> {:ok, "human"} end)

    assert {:ok, _} = Server.decide(server, :cancel, options)
    GenServer.stop(server)
    {:ok, restored} = Server.start_link(opts)
    assert Server.health(restored).status == :reset_required
    assert {:error, :continuation_pending} = Server.chat(restored, "bypass")
    refute_receive {:model, _}
    assert :ok = Server.reset(restored)
    assert {:ok, %{output: "done"}} = Server.chat(restored, "explicit next run")
    refute_receive :effect
    GenServer.stop(restored)
  end

  test "reset checks the complete retry token at J exact and J minus one before Store", %{
    store: {_, table}
  } do
    owner = self()
    {:ok, fault} = Agent.start_link(fn -> {:measure, :before, owner} end)

    opts = [
      agent: agent(owner),
      agent_id: "reset-cap",
      namespace: "server-c7",
      store: {ResetFaultStore, {table, fault}},
      continuation: config()
    ]

    {:ok, server} = Server.start_link(opts)
    {:ok, _} = Server.chat(server, "go")
    assert {:error, %ExAgent.CheckpointError{}} = Server.reset(server)
    assert_receive {:reset_token_bytes, bytes}
    GenServer.stop(server)
    Agent.update(fault, fn _ -> {:measure, :ok, owner} end)

    {:ok, small} =
      Server.start_link(
        Keyword.put(opts, :continuation, Map.put(config(), :max_checkpoint_bytes, bytes - 1))
      )

    assert {:error,
            {:retention_limit_exceeded, %{boundary: :checkpoint, bytes: ^bytes, limit: limit}}} =
             Server.reset(small)

    assert limit == bytes - 1
    refute_receive {:reset_token_bytes, _}
    GenServer.stop(small)

    {:ok, exact} =
      Server.start_link(
        Keyword.put(opts, :continuation, Map.put(config(), :max_checkpoint_bytes, bytes))
      )

    assert :ok = Server.reset(exact)
    assert_receive {:reset_token_bytes, ^bytes}
    GenServer.stop(exact)
    Agent.stop(fault)
  end

  test "terminal reset respects encoded record and receipt caps without discarding evidence", %{
    store: store
  } do
    alias ExAgent.Continuation.{Record, Transition}

    {:ok, server} =
      Server.start_link(
        agent: agent(self()),
        agent_id: "reset-record-cap",
        namespace: "server-c7",
        store: store,
        continuation: config()
      )

    {:ok, _} = Server.chat(server, "go")
    :ok = Server.reset(server)
    {:ok, %{record: base}} = Server.continuation(server)
    GenServer.stop(server)
    key = {"server-c7", :agent, "reset-record-cap"}
    now = System.system_time(:millisecond)

    command = %{
      "record_id" => base["record_id"],
      "operation" => "reset_snapshot",
      "operation_id" => "reset-cap",
      "actor_id" => "host",
      "payload" => %{"snapshot" => Map.update!(base["snapshot"], "revision", &(&1 + 1))}
    }

    base = put_in(base, ["execution", "progress", "capacity_padding"], "")
    {:ok, %{record: projected}} = Transition.apply(base, key, base["revision"], command, now)
    gap = Record.max_bytes() - byte_size(Jason.encode!(projected))

    exact =
      put_in(base, ["execution", "progress", "capacity_padding"], String.duplicate("x", gap))

    assert :ok = Record.validate(exact, key)
    assert {:ok, %{record: full}} = Transition.apply(exact, key, exact["revision"], command, now)
    assert byte_size(Jason.encode!(full)) == Record.max_bytes()
    assert full["execution"] == exact["execution"]

    too_large =
      put_in(exact, ["execution", "progress", "capacity_padding"], String.duplicate("x", gap + 1))

    assert :ok = Record.validate(too_large, key)

    assert {:error, :record_limit} =
             Transition.apply(too_large, key, too_large["revision"], command, now)

    receipt = base["receipts"] |> Map.values() |> hd()
    filled = %{base | "revision" => 1023, "receipts" => Map.new(1..1023, &{"r#{&1}", receipt})}
    assert :ok = Record.validate(filled, key)
    assert {:ok, %{record: last}} = Transition.apply(filled, key, 1023, command, now)
    assert map_size(last["receipts"]) == 1024
    assert last["execution"] == filled["execution"]
    assert {:ok, %{replayed: true}} = Transition.apply(last, key, 1023, command, now)

    assert {:error, :receipt_limit} =
             Transition.apply(last, key, 1024, Map.put(command, "operation_id", "another"), now)
  end

  test "abort pending is persisted and idempotent without erasing the open batch", %{store: store} do
    {:ok, server} =
      Server.start_link(
        agent: agent(self()),
        agent_id: "abort-pending",
        namespace: "server-c7",
        store: store,
        continuation: config()
      )

    {:ok, %{status: :paused}} =
      Server.chat(server, "go", permissions: Permissions.new!(default: :ask))

    assert :ok = Server.abort(server)
    assert {:ok, %{status: :cancelled, record: cancelled}} = Server.continuation(server)
    assert Server.health(server).status == :reset_required
    assert :ok = Server.abort(server)
    assert {:ok, %{record: ^cancelled}} = Server.continuation(server)
    refute_receive :effect
    GenServer.stop(server)
  end

  test "abort during effect preserves uncertainty and cleans the owned tool", %{store: store} do
    owner = self()
    base = agent(owner)
    [tool] = base.tools

    tool = %{
      tool
      | call: fn _, _ ->
          send(owner, {:effect_in_flight, self()})

          receive do
            :release_effect -> {:ok, "done"}
          end
        end
    }

    {:ok, server} =
      Server.start_link(
        agent: %{base | tools: [tool]},
        agent_id: "abort-effect",
        namespace: "server-c7",
        store: store,
        continuation: config()
      )

    caller = Task.async(fn -> Server.chat(server, "go") end)
    assert_receive {:effect_in_flight, effect}, 1_000
    monitor = Process.monitor(effect)
    assert :ok = Server.abort(server)
    assert {:error, %ExAgent.RunError{reason: :aborted}} = Task.await(caller)
    assert_receive {:DOWN, ^monitor, :process, ^effect, _}, 1_000
    assert {:ok, %{status: :uncertain, record: record}} = Server.continuation(server)
    assert Enum.any?(record["execution"]["effects"], fn {_, e} -> e["state"] == "running" end)
    assert {:error, :continuation_pending} = Server.reset(server)
    assert Server.health(server).status == :blocked
    refute_receive {:model, 1}
    GenServer.stop(server)
  end

  test "abort before initial record dispatch kills the writer instead of allowing a late create",
       %{store: {_, table}} do
    base = agent(self())

    bound = %{
      base
      | model: %ExAgent.ContinuationBindingModel{
          script: base.model.script,
          binding: %{"mode" => "none"}
        }
    }

    {:ok, server} =
      Server.start_link(
        agent: bound,
        agent_id: "abort-create",
        namespace: "server-c7",
        store: {BlockingCreateStore, {table, self()}},
        continuation: config()
      )

    caller = Task.async(fn -> Server.chat(server, "go") end)
    assert_receive {:creating_record, writer}, 1_000
    on_exit(fn -> if Process.alive?(writer), do: Process.exit(writer, :kill) end)
    monitor = Process.monitor(writer)
    assert :ok = Server.abort(server)
    assert {:error, %ExAgent.RunError{reason: :aborted}} = Task.await(caller)
    assert_receive {:DOWN, ^monitor, :process, ^writer, _}, 1_000
    assert {:ok, %{status: :cancelled, record: cancelled}} = Server.continuation(server)
    assert cancelled["execution"]["effects"] == %{}
    assert cancelled["execution"]["progress"]["runtime"]["abort_frame_version"] == 2
    assert cancelled["execution"]["progress"]["runtime"]["model_binding"] == %{"mode" => "none"}
    scoped = Store.scoped({Store.ETS, table}, "server-c7")
    cfg = Map.merge(config(), %{store: scoped, id: "abort-create"})

    assert {:error, :continuation_model_binding_changed} =
             ExAgent.Continuation.Frame.model_from_record(
               %{bound.model | binding: nil},
               cancelled,
               cfg
             )

    assert {:ok, _} = ExAgent.Continuation.Frame.model_from_record(bound.model, cancelled, cfg)
    assert Server.health(server).status == :idle
    refute_receive {:model, _}
    refute_receive :effect
    GenServer.stop(server)
  end

  for operation <- ["create", "start"] do
    @deferred_operation operation
    test "abort cancels #{@deferred_operation} that committed before its ACK reached the writer",
         %{store: {_, table}} do
      operation = @deferred_operation
      owner = self()
      {:ok, control} = Agent.start_link(fn -> %{owner: owner, block: nil} end)

      opts = [
        agent: agent(owner),
        agent_id: "inverse-#{operation}",
        namespace: "server-c7",
        store: {DeferredCommitStore, {table, control}},
        continuation: config()
      ]

      {:ok, server} = Server.start_link(opts)

      if operation == "start" do
        {:ok, _} = Server.chat(server, "first")
        assert_receive {:model, 0}
        assert_receive {:model, 1}
        assert_receive :effect
      end

      Agent.update(control, &%{&1 | block: operation})
      caller = Task.async(fn -> Server.chat(server, "abort before ack") end)
      assert_receive {:deferred_commit, ^operation, external, writer}, 1_000
      on_exit(fn -> if Process.alive?(external), do: Process.exit(external, :kill) end)
      monitor = Process.monitor(writer)
      send(external, :commit_without_ack)
      assert_receive {:committed_without_ack, ^operation, {:ok, _}}, 1_000
      assert :ok = Server.abort(server)
      assert {:error, %ExAgent.RunError{partial: %{run_id: run_id}}} = Task.await(caller)
      assert_receive {:DOWN, ^monitor, :process, ^writer, _}, 1_000
      assert {:ok, %{status: :cancelled, record: record}} = Server.continuation(server)
      assert record["execution"]["run_id"] == run_id
      assert record["execution"]["effects"] == %{}
      send(external, :release_ack)
      assert_receive {:deferred_ack, ^operation}
      assert {:ok, %{record: ^record}} = Server.continuation(server)
      refute_receive {:model, _}
      refute_receive :effect
      GenServer.stop(server)
      {:ok, restarted} = Server.start_link(opts)
      assert Server.health(restarted).status == :idle
      assert {:ok, _} = Server.chat(restarted, "new explicit run")
      GenServer.stop(restarted)
      Agent.stop(control)
    end

    test "abort fences an already-dispatched #{operation} whose Store commit arrives later", %{
      store: {_, table}
    } do
      operation = @deferred_operation
      owner = self()
      {:ok, control} = Agent.start_link(fn -> %{owner: owner, block: nil} end)
      id = "deferred-#{operation}"

      opts = [
        agent: agent(owner),
        agent_id: id,
        namespace: "server-c7",
        store: {DeferredCommitStore, {table, control}},
        continuation: config()
      ]

      {:ok, server} = Server.start_link(opts)

      previous =
        if operation == "start" do
          assert {:ok, _} = Server.chat(server, "first completed")
          assert_receive {:model, 0}
          assert_receive {:model, 1}
          assert_receive :effect
          {:ok, %{record: record}} = Server.continuation(server)
          record
        end

      Agent.update(control, &%{&1 | block: operation})
      caller = Task.async(fn -> Server.chat(server, "must be aborted") end)
      assert_receive {:deferred_commit, ^operation, external, writer}, 1_000
      on_exit(fn -> if Process.alive?(external), do: Process.exit(external, :kill) end)
      monitor = Process.monitor(writer)
      assert :ok = Server.abort(server)

      assert {:error, %ExAgent.RunError{reason: :aborted, partial: %{run_id: aborted_id}}} =
               Task.await(caller)

      assert_receive {:DOWN, ^monitor, :process, ^writer, _}, 1_000
      assert Process.alive?(external)
      send(external, :commit)
      assert_receive {:deferred_result, ^operation, result}, 1_000
      assert {:error, reason} = result
      assert reason in [:conflict, :record_mismatch]
      assert {:ok, %{record: fenced}} = Server.continuation(server)

      if previous do
        assert fenced["snapshot"] == previous["snapshot"]
        assert fenced["execution"]["effects"] == previous["execution"]["effects"]
        assert fenced["execution"]["progress"]["admission_fence"]["run_id"] == aborted_id
      else
        assert fenced["execution"]["run_id"] == aborted_id
        assert fenced["execution"]["state"] == "cancelled"
        assert fenced["execution"]["effects"] == %{}
      end

      refute_receive {:model, _}
      refute_receive :effect
      GenServer.stop(server)
      {:ok, restarted} = Server.start_link(opts)
      assert Server.health(restarted).status == :idle
      assert {:ok, %{status: :succeeded}} = Server.chat(restarted, "new explicit run")
      GenServer.stop(restarted)
      Agent.stop(control)
    end
  end

  test "abrupt Server death while Store holds an ACK leaves inspectable data and never auto-resumes",
       %{store: {_, table}} do
    owner = self()
    {:ok, control} = Agent.start_link(fn -> %{owner: owner, block: "create"} end)

    opts = [
      agent: agent(owner),
      agent_id: "dead-server-ack",
      namespace: "server-c7",
      store: {DeferredCommitStore, {table, control}},
      continuation: config()
    ]

    {:ok, server} = Server.start_link(opts)
    Process.unlink(server)

    caller =
      Task.async(fn ->
        try do
          Server.chat(server, "unacknowledged")
        catch
          :exit, reason -> {:exit, reason}
        end
      end)

    assert_receive {:deferred_commit, "create", external, writer}, 1_000
    on_exit(fn -> if Process.alive?(external), do: Process.exit(external, :kill) end)
    monitor = Process.monitor(writer)
    send(external, :commit_without_ack)
    assert_receive {:committed_without_ack, "create", {:ok, _}}, 1_000
    Process.exit(server, :kill)
    assert {:exit, _} = Task.await(caller)
    assert_receive {:DOWN, ^monitor, :process, ^writer, _}, 1_000
    {:ok, restored} = Server.start_link(opts)
    assert Server.health(restored).status == :paused
    assert {:error, :continuation_pending} = Server.chat(restored, "cannot skip")
    assert :ok = Server.abort(restored)
    send(external, :release_ack)
    assert_receive {:deferred_ack, "create"}
    assert {:ok, %{status: :cancelled}} = Server.continuation(restored)
    refute_receive {:model, _}
    refute_receive :effect
    GenServer.stop(restored)
    Agent.stop(control)
  end

  for operation <- ["create", "start"], failure <- [:before, :after] do
    @barrier_operation operation
    @barrier_failure failure
    @barrier_replayed failure == :after
    test "abort #{@barrier_operation} barrier #{@barrier_failure} commit retries only its exact data command",
         %{store: {_, table}} do
      operation = @barrier_operation
      failure = @barrier_failure
      owner = self()
      {:ok, control} = Agent.start_link(fn -> %{owner: owner, block: nil} end)
      {:ok, fault} = Agent.start_link(fn -> failure end)

      opts = [
        agent: agent(owner),
        agent_id: "barrier-#{operation}-#{failure}",
        namespace: "server-c7",
        store: {BarrierFaultStore, {table, control, fault}},
        continuation: config()
      ]

      {:ok, server} = Server.start_link(opts)

      if operation == "start" do
        {:ok, _} = Server.chat(server, "first")
        assert_receive {:model, 0}
        assert_receive {:model, 1}
        assert_receive :effect
      end

      Agent.update(control, &%{&1 | block: operation})
      caller = Task.async(fn -> Server.chat(server, "abort dirty") end)
      assert_receive {:deferred_commit, ^operation, external, _}, 1_000
      on_exit(fn -> if Process.alive?(external), do: Process.exit(external, :kill) end)
      assert {:error, %ExAgent.CheckpointError{result: :ok}} = Server.abort(server)
      assert {:error, %ExAgent.RunError{reason: :aborted}} = Task.await(caller)
      assert Server.health(server).persistence.dirty
      assert {:error, :checkpoint_pending} = Server.chat(server, "blocked")
      assert {:error, :checkpoint_pending} = Server.reset(server)
      assert {:ok, %{replayed: replayed, record: record}} = Server.checkpoint(server)
      assert replayed == @barrier_replayed
      assert :ok = Server.checkpoint(server)
      send(external, :commit)
      assert_receive {:deferred_result, ^operation, {:error, _}}, 1_000
      assert {:ok, %{record: ^record}} = Server.continuation(server)
      refute_receive {:model, _}
      refute_receive :effect
      GenServer.stop(server)
      {:ok, restored} = Server.start_link(opts)
      assert Server.health(restored).status == :idle
      GenServer.stop(restored)
      Agent.stop(fault)
      Agent.stop(control)
    end
  end

  test "Server stream registers its nested writer and resumes as a new correlated attempt", %{
    store: store
  } do
    id = "stream-writer"
    :ok = ExAgent.PubSub.subscribe({ExAgent.PubSub.Local, []}, Event.agent_topic(id, "server-c7"))

    {:ok, server} =
      Server.start_link(
        agent: agent(self()),
        agent_id: id,
        namespace: "server-c7",
        store: store,
        continuation: config(),
        pubsub: ExAgent.PubSub.Local
      )

    opts = [permissions: Permissions.new!(default: :ask)]
    assert {:ok, request_id} = Server.stream(server, "go", opts)

    assert_receive {:exagent_event,
                    %Event{type: :run_paused, request_id: ^request_id, run_id: run_id}},
                   2_000

    assert Server.health(server).status == :paused
    {:ok, %{record: record}} = Server.continuation(server)
    assert {:ok, _} = Server.decide(server, :approve, decision(record))

    assert {:ok, %{status: :succeeded, run_id: ^run_id}} =
             Server.resume(server, Keyword.put(opts, :stream_text, true))

    assert_receive :effect

    assert_receive {:exagent_event,
                    %Event{type: :run_finished, request_id: ^request_id, run_id: ^run_id}},
                   2_000

    refute_receive :effect
    GenServer.stop(server)
  end

  test "oversized abort model codec rejects the full token before Store and cannot acknowledge cancellation",
       %{store: {_, table}} do
    owner = self()
    {:ok, control} = Agent.start_link(fn -> %{owner: owner, block: "create"} end)
    {:ok, codec_mode} = Agent.start_link(fn -> :small end)

    cfg =
      config()
      |> Map.put(:max_checkpoint_bytes, 10_000)
      |> put_in([:model_codec, :dump], fn m ->
        pad =
          if Agent.get(codec_mode, & &1) == :large, do: String.duplicate("x", 12_000), else: ""

        {:ok, %{"index" => m.index, "padding" => pad}}
      end)

    {:ok, server} =
      Server.start_link(
        agent: agent(owner),
        agent_id: "abort-j",
        namespace: "server-c7",
        store: {DeferredCommitStore, {table, control}},
        continuation: cfg
      )

    caller = Task.async(fn -> Server.chat(server, "blocked create") end)
    assert_receive {:deferred_commit, "create", external, _}, 1_000
    on_exit(fn -> if Process.alive?(external), do: Process.exit(external, :kill) end)
    Agent.update(codec_mode, fn _ -> :large end)

    assert {:error,
            {:retention_limit_exceeded, %{boundary: :checkpoint, bytes: bytes, limit: 10_000}}} =
             Server.abort(server)

    assert bytes > 10_000
    assert {:error, %ExAgent.RunError{reason: :aborted}} = Task.await(caller)
    assert Server.health(server).status == :blocked
    assert {:error, :not_found} = Server.continuation(server)
    send(external, :commit)
    assert_receive {:deferred_result, "create", {:ok, _}}, 1_000
    # Explicit abort can now cancel the known row; this is not a Model/tool retry.
    assert :ok = Server.abort(server)
    assert {:ok, %{status: :cancelled}} = Server.continuation(server)
    refute_receive {:model, _}
    refute_receive :effect
    GenServer.stop(server)
    Agent.stop(codec_mode)
    Agent.stop(control)
  end

  test "closed admission frames cannot claim or resume; barrier JSON and receipts are bounded", %{
    store: store
  } do
    alias ExAgent.Continuation.{Record, Transition}
    scoped = Store.scoped(store, "server-c7")
    id = "barrier-caps"
    key = {"server-c7", :agent, id}
    cfg = config()

    execution = %{
      "continuation_id" => "closed",
      "run_id" => "aborted",
      "request_id" => "request",
      "definition" => cfg.definition,
      "policy" => cfg.policy,
      "model_ref" => cfg.model_ref,
      "deadline_at" => nil,
      "expires_at" => nil,
      "progress" => %{
        "runtime" => %{
          "abort_frame_version" => 1,
          "run_id" => "aborted",
          "model_data" => %{"index" => 0, "padding" => ""}
        }
      }
    }

    snapshot =
      ExAgent.Server.Snapshot.new(agent_id: id, history: [], usage: Usage.sum([]), revision: 0)
      |> Record.snapshot_data()

    create = %{
      "record_id" => "closed-life",
      "operation_id" => "closed-create",
      "actor_id" => "host",
      "operation" => "create_cancelled",
      "payload" => %{"snapshot" => snapshot, "execution" => execution}
    }

    assert {:ok, %{record: base}} = Store.transition(scoped, :agent, id, :absent, create)
    assert base["execution"]["state"] == "cancelled"
    assert Record.receipt_reserve(base["execution"]) == 0

    claim = %{
      "record_id" => "closed-life",
      "operation_id" => "claim",
      "actor_id" => "host",
      "operation" => "claim",
      "payload" => %{
        "owner_id" => "owner",
        "attempt_id" => "attempt",
        "lease_until" => System.system_time(:millisecond) + 60_000
      }
    }

    assert {:error, :invalid_transition} = Store.transition(scoped, :agent, id, 1, claim)
    ref = %{id: id, record_id: base["record_id"], revision: 1}

    assert {:error, %ExAgent.RunError{}} =
             ExAgent.resume(agent(self()), ref,
               continuation: Map.merge(cfg, %{store: scoped, id: id})
             )

    assert {:ok, ^base} = Store.load_record(scoped, :agent, id)
    refute_receive {:model, _}
    refute_receive :effect
    now = System.system_time(:millisecond)
    gap = Record.max_bytes() - byte_size(Jason.encode!(base))

    exact_create =
      put_in(
        create,
        ["payload", "execution", "progress", "runtime", "model_data", "padding"],
        String.duplicate("x", gap)
      )

    assert {:ok, %{record: exact}} =
             Transition.apply(nil, key, :absent, exact_create, base["created_at"])

    assert byte_size(Jason.encode!(exact)) == Record.max_bytes()

    too_big =
      update_in(
        exact_create,
        ["payload", "execution", "progress", "runtime", "model_data", "padding"],
        &(&1 <> "x")
      )

    assert {:error, :record_limit} =
             Transition.apply(nil, key, :absent, too_big, base["created_at"])

    fence = %{
      "record_id" => "closed-life",
      "operation_id" => String.duplicate(<<1>>, 512),
      "actor_id" => String.duplicate(<<1>>, 512),
      "operation" => "fence_admission",
      "payload" => %{"run_id" => String.duplicate(<<1>>, 512)}
    }

    {:ok, %{record: projection}} = Transition.apply(base, key, 1, fence, now)
    fence_gap = Record.max_bytes() - byte_size(Jason.encode!(projection))

    padded =
      put_in(
        base,
        ["execution", "progress", "runtime", "model_data", "padding"],
        String.duplicate("x", fence_gap)
      )

    assert {:ok, %{record: fenced}} = Transition.apply(padded, key, 1, fence, now)
    assert byte_size(Jason.encode!(fenced)) == Record.max_bytes()

    assert {:error, :record_limit} =
             Transition.apply(
               update_in(
                 padded,
                 ["execution", "progress", "runtime", "model_data", "padding"],
                 &(&1 <> "x")
               ),
               key,
               1,
               fence,
               now
             )

    receipt = base["receipts"]["closed-create"]
    filled = %{base | "revision" => 1023, "receipts" => Map.new(1..1023, &{"r#{&1}", receipt})}
    assert {:ok, %{record: last}} = Transition.apply(filled, key, 1023, fence, now)
    assert map_size(last["receipts"]) == 1024
    assert {:ok, %{replayed: true}} = Transition.apply(last, key, 1023, fence, now)

    assert {:error, :receipt_limit} =
             Transition.apply(last, key, 1024, Map.put(fence, "operation_id", "another"), now)
  end

  test "a losing dirty barrier stays blocked and needs authoritative reconciliation, not a changed retry command",
       %{store: {_, table}} do
    owner = self()
    {:ok, control} = Agent.start_link(fn -> %{owner: owner, block: "create"} end)
    {:ok, fault} = Agent.start_link(fn -> :before end)

    opts = [
      agent: agent(owner),
      agent_id: "dirty-barrier-race",
      namespace: "server-c7",
      store: {BarrierFaultStore, {table, control, fault}},
      continuation: config()
    ]

    {:ok, server} = Server.start_link(opts)
    caller = Task.async(fn -> Server.chat(server, "abort conflict") end)
    assert_receive {:deferred_commit, "create", external, _}, 1_000
    on_exit(fn -> if Process.alive?(external), do: Process.exit(external, :kill) end)
    assert {:error, %ExAgent.CheckpointError{}} = Server.abort(server)
    assert {:error, %ExAgent.RunError{partial: %{run_id: target}}} = Task.await(caller)
    send(external, :commit)
    assert_receive {:deferred_result, "create", {:ok, _}}, 1_000
    assert {:error, :record_mismatch} = Server.checkpoint(server)
    assert Server.health(server).persistence.dirty
    assert Server.health(server).status == :blocked
    assert {:error, :checkpoint_pending} = Server.chat(server, "must not skip")
    {:ok, %{record: record}} = Server.continuation(server)
    scoped = Store.scoped({Store.ETS, table}, "server-c7")
    assert record["execution"]["run_id"] == target

    assert {:ok, _} =
             ExAgent.Continuation.decide(scoped, "dirty-barrier-race", :cancel,
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "host-reconciliation",
               actor: :host,
               authorize: fn :host, :cancel, %{record: r} ->
                 if r["execution"]["run_id"] == target,
                   do: {:ok, "operator"},
                   else: {:error, :wrong_run}
               end
             )

    # Reload the authoritative row explicitly; volatile queued requests are not replayed.
    GenServer.stop(server)
    {:ok, restored} = Server.start_link(opts)
    assert {:ok, %{status: :cancelled}} = Server.continuation(restored)
    assert Server.health(restored).status == :idle
    refute_receive {:model, _}
    refute_receive :effect
    GenServer.stop(restored)
    Agent.stop(fault)
    Agent.stop(control)
  end

  defp config,
    do: %{
      durability: :ephemeral,
      lease_ms: 60_000,
      expires_at: nil,
      deadline_at: nil,
      active_time_limit_ms: 30_000,
      definition: %{"id" => "server-agent", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      model_ref: %{"id" => "test", "version" => "1"},
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, %{"index" => index} -> {:ok, %{m | index: index}} end
      }
    }

  defp agent(owner) do
    usage = %Usage{input_tokens: 3, output_tokens: 2}

    model = %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          send(owner, {:model, 0})

          %Response{
            parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}],
            usage: usage
          }
        end,
        fn _, _ ->
          send(owner, {:model, 1})
          %Response{parts: [%Part.Text{content: "done"}], usage: usage}
        end,
        fn _, _ ->
          send(owner, {:model, 2})
          %Response{parts: [%Part.Text{content: "queued"}], usage: usage}
        end
      ]
    }

    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :effect)
          {:ok, "saved"}
        end
      )

    ExAgent.new(model: model, tools: [tool])
  end

  defp decision(record) do
    [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    [
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: "approve",
      approval_id: id,
      payload_hash: approval["payload_hash"],
      actor: :host,
      authorize: fn :host, :approve, _ -> {:ok, "human"} end
    ]
  end
end
