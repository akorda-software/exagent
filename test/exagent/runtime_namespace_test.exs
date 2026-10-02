defmodule ExAgent.RuntimeNamespaceTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Event, Message, PubSub, Server, Session, Store}
  alias ExAgent.Server.Snapshot
  alias ExAgent.Session.Participant

  # One shared backend, keyed exactly as an external snapshot-only Store would
  # be. The journal deliberately survives every runtime owner in each test.
  defmodule Journal do
    @behaviour ExAgent.Store
    @behaviour ExAgent.PubSub
    def save_agent_snapshot(pid, snapshot),
      do: save(pid, :agent, snapshot.agent_id, Snapshot.serialize(snapshot))

    def load_agent_snapshot(pid, id), do: load(pid, :agent, id, Snapshot)
    def delete_agent_snapshot(pid, id), do: delete(pid, :agent, id)

    def save_session_snapshot(pid, snapshot),
      do: save(pid, :session, snapshot.session_id, ExAgent.Session.Snapshot.serialize(snapshot))

    def load_session_snapshot(pid, id), do: load(pid, :session, id, ExAgent.Session.Snapshot)
    def delete_session_snapshot(pid, id), do: delete(pid, :session, id)

    def list_agent_snapshots(pid) do
      Agent.get(pid, & &1.data)
      |> Enum.flat_map(fn
        {{:agent, _}, bytes} ->
          case Snapshot.deserialize(bytes) do
            {:ok, snap} -> [snap]
            _ -> []
          end

        _ ->
          []
      end)
    end

    def subscribe(_, _), do: :ok

    def broadcast(pid, topic, event) do
      Agent.update(pid, &%{&1 | events: &1.events ++ [{topic, event}]})

      if event.type in [:run_finished, :run_failed, :server_request_cancelled],
        do: send(Agent.get(pid, & &1.owner), {:terminal, event.namespace, event.request_id})

      :ok
    end

    defp save(pid, kind, id, bytes) do
      Agent.update(pid, fn state ->
        %{state | data: Map.put(state.data, {kind, id}, bytes), io: state.io + 1}
      end)

      :ok
    end

    defp load(pid, kind, id, codec) do
      bytes =
        Agent.get_and_update(pid, fn state ->
          {Map.get(state.data, {kind, id}), %{state | io: state.io + 1}}
        end)

      if bytes, do: codec.deserialize(bytes), else: {:error, :not_found}
    end

    defp delete(pid, kind, id) do
      Agent.update(pid, fn state ->
        %{state | data: Map.delete(state.data, {kind, id}), io: state.io + 1}
      end)

      :ok
    end
  end

  defmodule Model do
    @behaviour ExAgent.Model
    defstruct [:owner, :label, block: false]

    def request(model, messages, _, _) do
      prompt =
        messages
        |> Message.parts()
        |> Enum.filter(&is_struct(&1, Message.Part.User))
        |> List.last()
        |> Map.fetch!(:content)

      if model.owner, do: send(model.owner, {:request, model.label, prompt, self()})

      if model.block do
        receive do
          :release -> :ok
        end
      end

      {:ok, Message.new_response([%Message.Part.Text{content: "#{model.label}:#{prompt}"}]),
       model}
    end

    def request_stream(_, _, _, _), do: []
    def model_name(_), do: "namespace-fixture"
    def system(_), do: "test"
  end

  setup do
    owner = self()
    journal = start_supervised!({Agent, fn -> %{data: %{}, events: [], io: 0, owner: owner} end})
    %{journal: journal, store: {Journal, journal}}
  end

  test "same conversation ID in A, B and legacy restores only its own history and events", ctx do
    id = "shared:/雪"

    for ns <- [nil, "A:/雪", "B"] do
      label = ns || "legacy"
      server = server(ctx, id, ns, %Model{label: label})
      assert {:ok, %{output: output}} = Server.chat(server, label)
      assert output == "#{label}:#{label}"
      history = Server.history(server)
      GenServer.stop(server)
      restored = server(ctx, id, ns, %Model{label: "replacement"})
      assert Server.history(restored) == history
      assert Server.health(restored).namespace == ns
      assert {:ok, snap} = Store.load_agent_snapshot(Store.scoped(ctx.store, ns), id)
      assert snap.agent_id == id

      assert [^id] =
               Enum.map(Store.list_agent_snapshots(Store.scoped(ctx.store, ns)), & &1.agent_id)
    end

    events = Agent.get(ctx.journal, & &1.events)
    terminals = Enum.filter(events, fn {_, event} -> event.type == :run_finished end)
    assert length(terminals) == 3
    assert MapSet.size(MapSet.new(terminals, &elem(&1, 0))) == 3

    for {topic, event} <- events do
      assert topic == Event.agent_topic(id, event.namespace)
      assert event.agent_id == id
      assert Jason.decode!(Jason.encode!(event))["namespace"] == event.namespace
    end

    assert Event.agent_topic(id, nil) == Event.agent_topic(id)
  end

  test "Session restores trusted live refs separately and mutations/events remain scoped", ctx do
    id = "same-session"

    for ns <- ["A", "B"] do
      server = server(ctx, "same-agent", ns, %Model{label: ns})

      roster = [
        Participant.new(id: "human", kind: :human),
        Participant.new(id: "bot", kind: :agent, ref: server)
      ]

      session = session(ctx, id, ns, roster)
      assert {:ok, "human"} = Session.start(session)

      assert {:ok, %{"value" => ^ns}, "bot"} =
               Session.take_turn(session, "human", fn state -> Map.put(state, "value", ns) end)

      assert {:ok, "human"} = Session.handoff(session, "human")
      GenServer.stop(session)
      restored = session(ctx, id, ns, roster)
      assert Session.read_state(restored) == %{"value" => ns}
      bot = Enum.find(Session.participants(restored), &(&1.id == "bot"))
      assert bot.ref == server
      assert Server.health(bot.ref).namespace == Session.health(restored).namespace
      assert {:ok, %{output: output}} = Server.chat(bot.ref, "trusted")
      assert output == "#{ns}:trusted"
    end

    session_events =
      Agent.get(ctx.journal, & &1.events) |> Enum.filter(fn {_, e} -> e.source == :session end)

    assert Enum.any?(session_events, fn {_, e} -> e.namespace == "A" end)
    assert Enum.any?(session_events, fn {_, e} -> e.namespace == "B" end)

    assert Enum.all?(session_events, fn {topic, e} ->
             topic == Event.session_topic(id, e.namespace)
           end)

    snapshots =
      for {{:session, key}, bytes} <- Agent.get(ctx.journal, & &1.data),
          into: %{},
          do: {Jason.decode!(bytes)["shared_state"]["value"], {key, bytes}}

    {key_a, _} = snapshots["A"]
    {_, bytes_b} = snapshots["B"]
    Agent.update(ctx.journal, &%{&1 | data: Map.put(&1.data, {:session, key_a}, bytes_b)})

    assert {:error, :snapshot_id_mismatch} =
             Store.load_session_snapshot(Store.scoped(ctx.store, "A"), id)

    assert :ok = Store.delete_session_snapshot(Store.scoped(ctx.store, "A"), id)
    assert {:error, :not_found} = Store.load_session_snapshot(Store.scoped(ctx.store, "A"), id)
    assert {:ok, _} = Store.load_session_snapshot(Store.scoped(ctx.store, "B"), id)
  end

  test "injective keys, list/delete isolation and payload mismatch fail closed", ctx do
    pairs = [{"a:b", "c"}, {"a", "b:c"}, {"雪", "exagent.scope.v1:raw"}, {"a", ""}]

    for {ns, id} <- pairs do
      assert :ok =
               Store.save_agent_snapshot(Store.scoped(ctx.store, ns), Snapshot.new(agent_id: id))
    end

    assert map_size(Agent.get(ctx.journal, & &1.data)) == length(pairs)
    assert Store.list_agent_snapshots(ctx.store) == []

    assert Enum.sort(
             Enum.map(Store.list_agent_snapshots(Store.scoped(ctx.store, "a")), & &1.agent_id)
           ) == ["", "b:c"]

    assert :ok = Store.delete_agent_snapshot(Store.scoped(ctx.store, "a:b"), "c")
    assert {:ok, _} = Store.load_agent_snapshot(Store.scoped(ctx.store, "a"), "b:c")

    [{{:agent, key}, _} | _] = Map.to_list(Agent.get(ctx.journal, & &1.data))
    # Backend returns a structurally valid snapshot under the wrong key. None of
    # namespace, kind, local ID or a legacy ID may be substituted on restore.
    for wrong <- ["legacy", "exagent.scope.v1:invalid", key <> "x"] do
      Agent.update(
        ctx.journal,
        &%{
          &1
          | data:
              Map.new(&1.data, fn {k, _} ->
                {k, Snapshot.serialize(Snapshot.new(agent_id: wrong))}
              end)
        }
      )

      assert {:error, :snapshot_id_mismatch} =
               Store.load_agent_snapshot(Store.scoped(ctx.store, "a"), "b:c")
    end
  end

  test "reserved legacy IDs and conflicting descriptors fail before backend IO", ctx do
    id = "exagent.scope.v1:reserved"
    before = Agent.get(ctx.journal, & &1.io)

    assert {:error, :reserved_runtime_id} =
             Store.save_agent_snapshot(ctx.store, Snapshot.new(agent_id: id))

    assert {:error, :reserved_runtime_id} = Store.load_agent_snapshot(ctx.store, id)
    assert {:error, :reserved_runtime_id} = Store.delete_agent_snapshot(ctx.store, id)
    scoped = Store.scoped(ctx.store, "A")
    assert Store.scoped(scoped, "A") == scoped
    assert_raise ArgumentError, "store namespace mismatch", fn -> Store.scoped(scoped, "B") end
    assert_raise ArgumentError, "store namespace mismatch", fn -> Store.scoped(scoped, nil) end

    for ns <- [:untrusted_atom, "", <<255>>] do
      assert_raise ArgumentError, "invalid namespace", fn -> Store.scoped(ctx.store, ns) end
    end

    assert Agent.get(ctx.journal, & &1.io) == before
  end

  test "valid other-tenant agent payload cannot restore and scoped ETS preserves logical IDs",
       ctx do
    for ns <- ["A", "B"] do
      assert :ok =
               Store.save_agent_snapshot(
                 Store.scoped(ctx.store, ns),
                 Snapshot.new(agent_id: "same", metadata: %{"tenant" => ns})
               )
    end

    snapshots =
      for {{:agent, key}, bytes} <- Agent.get(ctx.journal, & &1.data),
          into: %{},
          do: {Jason.decode!(bytes)["metadata"]["tenant"], {key, bytes}}

    {key_a, _} = snapshots["A"]
    {_, bytes_b} = snapshots["B"]
    Agent.update(ctx.journal, &%{&1 | data: Map.put(&1.data, {:agent, key_a}, bytes_b)})

    assert {:error, :snapshot_id_mismatch} =
             Store.load_agent_snapshot(Store.scoped(ctx.store, "A"), "same")

    assert Store.list_agent_snapshots(Store.scoped(ctx.store, "A")) == []

    assert {:ok, %Snapshot{agent_id: "same"}} =
             Store.load_agent_snapshot(Store.scoped(ctx.store, "B"), "same")

    ns = "ets/#{System.unique_integer([:positive])}"
    scoped = Store.scoped(:ets, ns)
    on_exit(fn -> Store.delete_agent_snapshot(scoped, "same") end)
    assert :ok = Store.save_agent_snapshot(scoped, Snapshot.new(agent_id: "same"))
    assert {:ok, %Snapshot{agent_id: "same"}} = Store.load_agent_snapshot(scoped, "same")
    assert [%Snapshot{agent_id: "same"}] = Store.list_agent_snapshots(scoped)
    assert_raise ArgumentError, fn -> String.to_existing_atom(ns) end
  end

  @tag timeout: 10_000
  test "16 namespaces saturate independent queues with 48 terminals and no crossed history",
       ctx do
    servers =
      for n <- 1..16, into: %{} do
        ns = "load:#{n}"

        {ns,
         server(ctx, "shared", ns, %Model{owner: self(), label: ns, block: true}, max_pending: 2)}
      end

    workers =
      for {ns, pid} <- servers do
        assert {:ok, _} = Server.send_message(pid, "first")
        assert_receive {:request, ^ns, "first", worker}, 1000
        assert {:ok, _} = Server.send_message(pid, "last")
        assert {:ok, _} = Server.steer(pid, "priority")
        assert {:error, :queue_full} = Server.send_message(pid, "rejected")
        assert %{pending: 2, status: :running} = Server.health(pid)
        worker
      end

    for worker <- workers, do: send(worker, :release)

    for prompt <- ["priority", "last"] do
      for _ <- 1..16 do
        assert_receive {:request, _ns, ^prompt, worker}, 1000
        send(worker, :release)
      end
    end

    for _ <- 1..48, do: assert_receive({:terminal, _, _}, 1000)

    for {ns, pid} <- servers do
      assert %{pending: 0, status: :idle} = Server.health(pid)
      parts = Message.parts(Server.history(pid))
      outputs = for %Message.Part.Text{content: text} <- parts, do: text
      assert outputs == ["#{ns}:first", "#{ns}:priority", "#{ns}:last"]
    end

    terminals =
      Agent.get(ctx.journal, & &1.events)
      |> Enum.filter(fn {_, e} ->
        e.type in [:run_finished, :run_failed, :server_request_cancelled]
      end)

    assert length(terminals) == 48
    assert MapSet.size(MapSet.new(terminals, fn {_, e} -> {e.namespace, e.request_id} end)) == 48

    assert Enum.all?(terminals, fn {topic, e} ->
             topic == Event.agent_topic("shared", e.namespace)
           end)
  end

  test "Local PubSub scoped subscription does not receive another namespace", ctx do
    id = "pubsub-#{System.unique_integer([:positive])}"
    pubsub = PubSub.normalize(:local)
    :ok = PubSub.subscribe(pubsub, Event.agent_topic(id, "A"))
    b = server(ctx, id, "B", %Model{label: "B"}, pubsub: pubsub)
    assert {:ok, _} = Server.chat(b, "B")
    refute_receive {:exagent_event, _}, 20
    a = server(ctx, id, "A", %Model{label: "A"}, pubsub: pubsub)
    assert {:ok, _} = Server.chat(a, "A")
    assert_receive {:exagent_event, %Event{namespace: "A", agent_id: ^id}}, 1000
  end

  defp server(ctx, id, ns, model, extra \\ []) do
    opts =
      Keyword.merge(
        [
          agent: ExAgent.new(model: model),
          agent_id: id,
          namespace: ns,
          store: ctx.store,
          pubsub: {Journal, ctx.journal}
        ],
        extra
      )

    start_supervised!(Supervisor.child_spec({Server, opts}, id: make_ref(), restart: :temporary))
  end

  defp session(ctx, id, ns, roster) do
    start_supervised!(
      Supervisor.child_spec(
        {Session,
         session_id: id,
         namespace: ns,
         participants: roster,
         shared_state: %{},
         store: ctx.store,
         pubsub: {Journal, ctx.journal}},
        id: make_ref(),
        restart: :temporary
      )
    )
  end
end
