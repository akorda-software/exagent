defmodule ExAgent.ServerCheckpointContractTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  alias ExAgent.{CheckpointError, Event, Message, PubSub, RunError, Server, Session, Store, Tool}
  alias ExAgent.Models.Test
  alias ExAgent.Message.{Part, Usage}
  alias ExAgent.Session.Participant

  setup do
    # Failed linked initialization sends EXIT on OTP; isolate expected restore
    # failures while asserting their returned causes and absence of Store writes.
    Process.flag(:trap_exit, true)
    :ok
  end

  defmodule ControlledStore do
    @behaviour Store
    def save_agent_snapshot(config, snapshot), do: save(config, :agent, snapshot)
    def save_session_snapshot(config, snapshot), do: save(config, :session, snapshot)
    def load_agent_snapshot(config, id), do: load(config, :agent, id)
    def load_session_snapshot(config, id), do: load(config, :session, id)
    def list_agent_snapshots(_), do: []
    def delete_agent_snapshot(_, _), do: :ok

    defp load(config, kind, id) do
      Agent.get(config, fn s ->
        s.load_error ||
          case Map.fetch(s.snapshots, {kind, id}) do
            {:ok, value} -> {:ok, value}
            :error -> {:error, :not_found}
          end
      end)
    end

    defp save(config, kind, snapshot) do
      %{owner: owner, mode: mode} =
        Agent.get_and_update(config, fn s ->
          {s, %{s | attempts: s.attempts ++ [snapshot]}}
        end)

      send(owner, {:save_attempt, kind, self(), snapshot})

      outcome =
        case mode do
          :gate ->
            receive do
              {:release_save, reply} -> reply
            end

          :raise ->
            raise "store unavailable"

          :exit ->
            exit(:store_unavailable)

          other ->
            other
        end

      if outcome == :ok do
        id = if kind == :agent, do: snapshot.agent_id, else: snapshot.session_id
        mod = snapshot.__struct__
        {:ok, decoded} = snapshot |> mod.serialize() |> mod.deserialize()
        Agent.update(config, &put_in(&1, [:snapshots, {kind, id}], decoded))
      end

      outcome
    end
  end

  defp store(mode \\ :ok) do
    owner = self()

    start_supervised!(
      {Agent,
       fn -> %{owner: owner, mode: mode, load_error: nil, snapshots: %{}, attempts: []} end}
    )
  end

  defp mode(store, mode), do: Agent.update(store, &%{&1 | mode: mode})
  defp opts(store), do: [store: {ControlledStore, store}]

  defp server(store, model \\ %Test{label: "answer"}) do
    start_supervised!({Server, [agent: ExAgent.new(model: model), pubsub: :local] ++ opts(store)})
  end

  defp subscribe(server) do
    id = :sys.get_state(server).agent_id
    :ok = PubSub.subscribe({ExAgent.PubSub.Local, []}, Event.agent_topic(id))
  end

  test "sync reply and terminal wait for Store confirmation" do
    store = store(:gate)
    server = server(store)
    subscribe(server)
    caller = Task.async(fn -> Server.chat(server, "go") end)
    assert_receive {:save_attempt, :agent, owner, %{revision: 1}}
    assert Task.yield(caller, 0) == nil
    refute_receive {:exagent_event, %Event{type: :run_finished}}
    send(owner, {:release_save, :ok})
    assert {:ok, %{output: "answer"}} = Task.await(caller)
    assert_receive {:exagent_event, %Event{type: :run_finished, payload: payload}}
    assert payload.persistence.status == :confirmed
    refute_receive {:exagent_event, %Event{type: :run_finished}}
  end

  for failure <- [{:error, :disk_full}, :raise, :exit, :invalid_return] do
    test "save #{inspect(failure)} preserves result and retries only saving" do
      store = store(unquote(Macro.escape(failure)))
      parent = self()

      model = %Test{
        script: [
          fn ->
            send(parent, :model_called)
            "completed"
          end
        ]
      }

      server = server(store, model)

      assert {:error, %CheckpointError{result: {:ok, %{output: "completed"}}, revision: 1}} =
               Server.chat(server, "go")

      assert_receive :model_called
      assert length(Server.history(server)) == 2
      assert %{persistence: %{status: :unconfirmed}} = Server.health(server)
      assert {:error, %CheckpointError{}} = Server.chat(server, "do not repeat")
      assert {:error, %CheckpointError{}} = Server.reset(server)
      assert {:error, %CheckpointError{}} = Server.send_message(server, "not admitted")
      mode(store, :ok)
      assert :ok = Server.checkpoint(server)
      assert :ok = Server.checkpoint(server)
      assert %{persistence: %{status: :confirmed, revision: 1}} = Server.health(server)
      assert length(Agent.get(store, & &1.attempts)) == 2
      refute_receive :model_called
    end
  end

  test "dirty checkpoint suspends already admitted queue without repeating a terminal" do
    store = store({:error, :offline})
    parent = self()

    model = %Test{
      script: [
        fn ->
          send(parent, {:first_worker, self()})

          receive do
            :release -> "first"
          end
        end,
        "second"
      ]
    }

    server = server(store, model)
    subscribe(server)
    assert {:ok, first} = Server.send_message(server, "first")
    assert_receive {:first_worker, worker}
    assert {:ok, second} = Server.send_message(server, "second")
    send(worker, :release)
    assert_receive {:exagent_event, %Event{type: :run_failed, request_id: ^first}}

    assert %{status: :idle, pending: 1, persistence: %{status: :unconfirmed}} =
             Server.health(server)

    mode(store, :ok)
    assert :ok = Server.checkpoint(server)
    assert_receive {:exagent_event, %Event{type: :run_finished, request_id: ^second}}

    for type <- [:run_finished, :run_failed] do
      refute_receive {:exagent_event, %Event{type: ^type, request_id: ^first}}
    end

    assert length(Server.history(server)) == 4
  end

  test "tool progress survives model failure, checkpoint and restart" do
    store = store()
    parent = self()

    tool =
      Tool.new(
        name: "record",
        takes_ctx: false,
        call: fn _ ->
          send(parent, :effect)
          {:ok, "recorded"}
        end
      )

    model = %Test{
      script: [
        {:tool_calls, [%Part.ToolCall{tool_name: "record", tool_call_id: "call1", args: %{}}]},
        fn -> raise "model offline" end
      ]
    }

    id = "partial-#{System.unique_integer([:positive])}"

    {:ok, server} =
      Server.start_link(
        [agent: ExAgent.new(model: model, tools: [tool]), agent_id: id] ++ opts(store)
      )

    assert {:error, %RunError{partial: partial}} = Server.chat(server, "record")
    assert_receive :effect
    assert Enum.any?(Message.parts(Server.history(server)), &match?(%Part.ToolReturn{}, &1))
    assert Server.usage(server).input_tokens == partial.usage.input_tokens
    assert :sys.get_state(server).model == partial.model
    GenServer.stop(server)

    {:ok, restored} =
      Server.start_link([agent: ExAgent.new(model: %Test{}), agent_id: id] ++ opts(store))

    assert Server.history(restored) == partial.messages
    assert Server.usage(restored).input_tokens > 0
    GenServer.stop(restored)
    refute_receive :effect
  end

  test "async output and usage details are preserved without exposing model" do
    store = store()

    response =
      Message.new_response([%Part.Text{content: "complete"}],
        usage: %Usage{input_tokens: 3, output_tokens: 2, details: %{"cached_tokens" => 2}},
        model_name: "test"
      )

    server = server(store, %Test{script: [response]})
    subscribe(server)
    assert {:ok, id} = Server.stream(server, "go")

    assert_receive {:exagent_event,
                    %Event{type: :run_finished, request_id: ^id, payload: payload}}

    assert payload.output == "complete"
    assert payload.usage["details"]["cached_tokens"] == 2
    refute Map.has_key?(payload, :model)
    assert Server.usage(server).details["cached_tokens"] == 2
    [snapshot] = Agent.get(store, & &1.attempts)
    assert snapshot.usage["details"]["cached_tokens"] == 2
    assert is_binary(Jason.encode!(payload))
  end

  test "Session take_turn saves exactly the complete next turn and retry does not rerun change" do
    store = store()

    session =
      start_supervised!(
        {Session,
         [
           shared_state: %{"n" => 0},
           participants: [Participant.new(id: "a"), Participant.new(id: "b")]
         ] ++ opts(store)}
      )

    assert {:ok, "a"} = Session.start(session)
    before = length(Agent.get(store, & &1.attempts))
    mode(store, {:error, :offline})
    parent = self()

    assert {:error, %CheckpointError{result: {:ok, %{"n" => 1}, "b"}}} =
             Session.take_turn(session, "a", fn state ->
               send(parent, :changed)
               {:ok, %{state | "n" => 1}}
             end)

    assert_receive :changed
    assert Session.current(session) == "b"
    assert Session.read_state(session) == %{"n" => 1}
    attempts = Agent.get(store, & &1.attempts)
    assert length(attempts) == before + 1
    assert List.last(attempts).current == "b"
    assert {:error, %CheckpointError{}} = Session.end_turn(session, "b")
    assert {:error, %CheckpointError{}} = Session.join(session, id: "c")
    mode(store, :ok)
    assert :ok = Session.checkpoint(session)
    assert length(Agent.get(store, & &1.attempts)) == before + 2
    refute_receive :changed
  end

  test "load failures do not start empty or save replacements" do
    store = store()
    Agent.update(store, &%{&1 | load_error: {:error, :offline}})

    assert {:error, {:restore_failed, :offline}} =
             Server.start_link([agent: ExAgent.new(model: %Test{})] ++ opts(store))

    assert {:error, {:restore_failed, :offline}} = Session.start_link(opts(store))
    assert Agent.get(store, & &1.attempts) == []
  end

  test "custom Store structs with future version or wrong id fail startup without replacement" do
    store = store()

    for snapshot <- [
          %ExAgent.Server.Snapshot{agent_id: "same", version: 999},
          %ExAgent.Server.Snapshot{agent_id: "other"}
        ] do
      Agent.update(store, &%{&1 | snapshots: %{{:agent, "same"} => snapshot}})

      assert {:error, {:restore_failed, _}} =
               Server.start_link(
                 [agent: ExAgent.new(model: %Test{}), agent_id: "same"] ++ opts(store)
               )

      assert Agent.get(store, & &1.attempts) == []
      assert Agent.get(store, & &1.snapshots[{:agent, "same"}]) == snapshot
    end
  end

  test "restoring a Session with another policy fails instead of mixing states" do
    store = store()
    id = "policy-#{System.unique_integer([:positive])}"
    options = [session_id: id, participants: [Participant.new(id: "a")]] ++ opts(store)
    {:ok, first} = Session.start_link(options)
    assert {:ok, "a"} = Session.start(first)
    GenServer.stop(first)
    before = Agent.get(store, & &1.attempts)

    assert {:error, {:restore_failed, :snapshot_policy_mismatch}} =
             Session.start_link(Keyword.put(options, :policy, :initiative))

    assert Agent.get(store, & &1.attempts) == before
  end

  for winner <- [:completion, :abort] do
    test "#{winner} wins when its decisive message was queued first" do
      store = store()
      parent = self()

      model = %Test{
        script: [
          fn ->
            send(parent, {:working, self()})

            receive do
              :release -> "complete"
            end
          end
        ]
      }

      server = server(store, model)
      subscribe(server)
      assert {:ok, request_id} = Server.send_message(server, "go")
      assert_receive {:working, worker}
      worker_ref = Process.monitor(worker)
      tag = make_ref()
      :sys.suspend(server)
      if unquote(winner == :abort), do: send(server, {:"$gen_call", {self(), tag}, :abort})
      send(worker, :release)
      assert_receive {:DOWN, ^worker_ref, :process, ^worker, :normal}
      if unquote(winner == :completion), do: send(server, {:"$gen_call", {self(), tag}, :abort})
      :sys.resume(server)
      assert_receive {^tag, :ok}

      expected =
        unquote(if winner == :completion, do: :run_finished, else: :server_request_cancelled)

      assert_receive {:exagent_event, %Event{type: ^expected, request_id: ^request_id}}
      assert %{status: :idle} = Server.health(server)

      for type <- [:run_finished, :run_failed, :server_request_cancelled] do
        refute_receive {:exagent_event, %Event{type: ^type, request_id: ^request_id}}
      end
    end
  end

  test "error/event projection contains JSON output and progress but no live model" do
    partial = %{
      output: %{"ticket" => %{"id" => 7}},
      messages: [],
      new_messages: [],
      model: %{api_key: "LIVE-MODEL-MUST-NOT-APPEAR"},
      usage: %Usage{input_tokens: 1, output_tokens: 2},
      run_id: "run",
      run_step: 1,
      status: :failed
    }

    payload = Event.error_payload(%RunError{reason: :offline, partial: partial})
    assert payload.partial.output == %{"ticket" => %{"id" => 7}}
    refute Jason.encode!(payload) =~ "LIVE-MODEL-MUST-NOT-APPEAR"
    refute Map.has_key?(payload.partial, :model)
  end

  test "C4 projection preserves approved scalar identities/counts and unknown cost" do
    metadata = %{
      root_run_id: "root",
      parent_run_id: nil,
      model_request_id: "request",
      request_count: 2,
      tool_calls: 1,
      cost_cents: nil,
      cost_status: :unknown
    }

    result =
      Map.merge(metadata, %{
        output: "ok",
        messages: [],
        usage: nil,
        execution_scope: self(),
        model: %{api_key: "secret"}
      })

    payload = Event.result_payload(result)
    assert Map.take(payload, Map.keys(metadata)) == metadata
    assert payload.cost_cents == nil
    refute Map.has_key?(payload, :execution_scope)
    refute Map.has_key?(payload, :model)
    assert is_binary(Jason.encode!(payload))

    invalid = %{
      result
      | root_run_id: self(),
        request_count: -1,
        tool_calls: "1",
        cost_cents: %{model: "secret"},
        cost_status: :invalid
    }

    rejected = Event.result_payload(invalid)

    for key <- [:root_run_id, :request_count, :tool_calls, :cost_cents, :cost_status],
        do: refute(Map.has_key?(rejected, key))
  end

  test "invalid protocol trees from Store fail startup without replacing the snapshot" do
    store = store()

    for history <- [
          "[null]",
          ~s([{"__type__":"text","content":"orphan"}]),
          ~s([{"__type__":"request","parts":[null]}]),
          ~s([{"__type__":"response","parts":[{"__type__":"request","parts":[]}]}])
        ] do
      snapshot = %ExAgent.Server.Snapshot{agent_id: "tree", message_history: history}
      Agent.update(store, &%{&1 | snapshots: %{{:agent, "tree"} => snapshot}})

      assert {:error, {:restore_failed, :invalid_history}} =
               Server.start_link(
                 [agent: ExAgent.new(model: %Test{}), agent_id: "tree"] ++ opts(store)
               )

      assert Agent.get(store, & &1.attempts) == []
      assert Agent.get(store, & &1.snapshots[{:agent, "tree"}]) == snapshot
    end
  end

  test "RequestError.model nested in run/checkpoint errors never reaches Event or health JSON" do
    secret = "NESTED-REQUEST-MODEL-SENTINEL"

    request_error = %ExAgent.RequestError{
      provider: :openai,
      reason: :timeout,
      model: struct(ExAgent.Models.OpenAI, api_key: secret)
    }

    partial = %{
      output: nil,
      messages: [],
      new_messages: [],
      model: request_error.model,
      usage: %Usage{input_tokens: 0, output_tokens: 0},
      run_id: "nested",
      status: :failed
    }

    run_error = %RunError{reason: {:model_request_failed, request_error}, partial: partial}

    checkpoint_error = %CheckpointError{
      operation: :agent,
      reason: {:backend_failed, request_error},
      result: {:error, run_error},
      revision: 1
    }

    health =
      ExAgent.RuntimeCheckpoint.health(%{
        store: {ControlledStore, nil},
        revision: 1,
        checkpoint_error: checkpoint_error
      })

    for payload <- [Event.error_payload(run_error), Event.error_payload(checkpoint_error), health] do
      encoded = Jason.encode!(payload)
      refute encoded =~ secret
      refute encoded =~ "api_key"
    end

    refute Map.has_key?(health.error, :result)
  end

  test "supervisor observer handoff remains restorable after failed save and checkpoint-only retry" do
    store = store()
    id = "retry-observer-#{System.unique_integer([:positive])}"

    options =
      [
        session_id: id,
        participants: Enum.map(["s", "a", "observer"], &Participant.new(id: &1)),
        policy: {:supervisor, supervisor: "s", workers: ["a"]}
      ] ++ opts(store)

    {:ok, first} = Session.start_link(options)
    assert {:ok, "s"} = Session.start(first)
    mode(store, {:error, :offline})

    assert {:error, %CheckpointError{result: {:ok, "observer"}}} =
             Session.handoff(first, "observer")

    assert Session.current(first) == "observer"
    mode(store, :ok)
    assert :ok = Session.checkpoint(first)
    GenServer.stop(first)
    assert {:ok, restored} = Session.start_link(options)
    assert Session.current(restored) == "observer"
    assert {:ok, "a"} = Session.end_turn(restored, "observer")
    GenServer.stop(restored)
  end
end
