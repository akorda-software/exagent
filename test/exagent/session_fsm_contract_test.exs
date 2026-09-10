defmodule ExAgent.SessionFSMContractTest do
  use ExUnit.Case, async: true
  alias ExAgent.Session
  alias ExAgent.Session.{Participant, Snapshot, TurnPolicy}

  defmodule OpaquePolicy do
    @behaviour TurnPolicy
    defstruct ids: [], actor: nil, joins: 0
    def init(opts), do: %__MODULE__{ids: Enum.map(opts[:participants], & &1.id)}
    def next_participant(%{ids: []} = state, _), do: {:done, %{state | actor: nil}}

    def next_participant(state, _) do
      id = Enum.find(state.ids, &(&1 != state.actor)) || hd(state.ids)
      {:ok, id, %{state | actor: id}}
    end

    def can_act?(state, id, _), do: state.actor == id

    def participant_joined(state, p),
      do: %{state | ids: state.ids ++ [p.id], joins: state.joins + 1}

    def participant_left(state, id),
      do: %{
        state
        | ids: List.delete(state.ids, id),
          actor: if(state.actor == id, do: nil, else: state.actor)
      }
  end

  defmodule OpenPolicy do
    @behaviour TurnPolicy
    defstruct []
    def init(_), do: %__MODULE__{}
    def next_participant(state, %{participants: [p | _]}), do: {:ok, p.id, state}
    def can_act?(_, _, _), do: true
  end

  defmodule CodedPolicy do
    @behaviour TurnPolicy
    defstruct actor: nil
    def init(opts), do: %__MODULE__{actor: hd(opts[:participants]).id}
    def next_participant(state, _), do: {:ok, state.actor, state}
    def can_act?(state, id, _), do: id == state.actor
    def snapshot(state), do: {:ok, 1, %{actor: state.actor}}

    def restore_snapshot(1, %{"actor" => actor}, context) do
      if Enum.any?(context.participants, &(&1.id == actor)),
        do: {:ok, %__MODULE__{actor: actor}},
        else: {:error, :bad_actor}
    end
  end

  defmodule DataOnlyModule do
    def __struct__, do: raise("snapshot must not invoke this function")
  end

  defp p(id), do: Participant.new(id: id)

  defp session(policy \\ :round_robin, ids \\ ["a", "b", "c"]) do
    start_supervised!(
      {Session, policy: policy, participants: Enum.map(ids, &p/1), shared_state: %{}}
    )
  end

  for policy <- [:round_robin, :initiative] do
    test "#{policy}: pause/leave/resume selects once and remains paused until resume" do
      session = session(unquote(policy))
      assert {:ok, "a"} = Session.start(session)
      assert :ok = Session.pause(session)
      assert :ok = Session.leave(session, "a")
      assert Session.current(session) == nil
      assert Session.status(session) == :paused
      assert {:error, :paused} = Session.end_turn(session, "b")
      assert :ok = Session.resume(session)
      assert Session.current(session) == "b"
      assert {:ok, "c"} = Session.end_turn(session, "b")
    end

    test "#{policy}: removing before cursor after several rounds does not repeat actor" do
      session = session(unquote(policy))
      assert {:ok, "a"} = Session.start(session)
      for id <- ["a", "b", "c", "a"], do: assert({:ok, _} = Session.end_turn(session, id))
      assert Session.current(session) == "b"
      assert :ok = Session.leave(session, "a")
      assert {:ok, "c"} = Session.end_turn(session, "b")
    end

    test "#{policy}: append after wrap preserves next existing participant" do
      session = session(unquote(policy))
      assert {:ok, "a"} = Session.start(session)
      for id <- ["a", "b", "c"], do: assert({:ok, _} = Session.end_turn(session, id))
      assert :ok = Session.join(session, id: "d")
      assert {:ok, "b"} = Session.end_turn(session, "a")
      assert {:ok, "c"} = Session.end_turn(session, "b")
      assert {:ok, "d"} = Session.end_turn(session, "c")
    end

    test "#{policy}: handoff changes actor without moving planned cursor" do
      session = session(unquote(policy))
      assert {:ok, "a"} = Session.start(session)
      assert {:ok, "c"} = Session.handoff(session, "c")
      assert {:ok, "b"} = Session.end_turn(session, "c")
    end
  end

  test "join at the end-of-round boundary gives the appended participant a turn" do
    session = session()
    assert {:ok, "a"} = Session.start(session)
    assert {:ok, "b"} = Session.end_turn(session, "a")
    assert {:ok, "c"} = Session.end_turn(session, "b")
    assert :ok = Session.join(session, id: "d")
    assert {:ok, "d"} = Session.end_turn(session, "c")
  end

  test "supervisor worker cursor stays aligned after several rounds and removal" do
    session =
      session(
        {:supervisor, supervisor: "s", workers: ["a", "b", "c"]},
        ["s", "a", "b", "c"]
      )

    assert {:ok, "s"} = Session.start(session)

    for id <- ["s", "a", "s", "b", "s", "c", "s", "a", "s"],
        do: assert({:ok, _} = Session.end_turn(session, id))

    assert Session.current(session) == "b"
    assert :ok = Session.leave(session, "a")
    assert {:ok, "s"} = Session.end_turn(session, "b")
    assert {:ok, "c"} = Session.end_turn(session, "s")
  end

  test "repeat join updates ref/metadata without a second policy hook" do
    session = session(OpaquePolicy, ["a"])
    assert :ok = Session.join(session, id: "b", ref: :old)
    assert :ok = Session.join(session, id: "b", ref: :new, metadata: %{color: "blue"})
    assert :sys.get_state(session).policy_state.joins == 1
    assert Enum.find(Session.participants(session), &(&1.id == "b")).ref == :new
    assert {:error, :participant_kind_mismatch} = Session.join(session, id: "b", kind: :agent)
    assert :ok = Session.leave(session, "b")
    assert :sys.get_state(session).policy_state.ids == ["a"]
  end

  test "opaque custom handoff fails without mutation but already-authorized fallback works" do
    session = session(OpaquePolicy)
    assert {:ok, "a"} = Session.start(session)
    before = :sys.get_state(session)
    assert {:error, :unsupported_handoff} = Session.handoff(session, "b")
    assert :sys.get_state(session) == before
    assert {:ok, "a"} = Session.handoff(session, "a")
  end

  test "permissive custom admission still cannot authorize a ghost" do
    session = session(OpenPolicy)
    assert {:ok, _} = Session.start(session)
    assert {:error, :not_a_participant} = Session.handoff(session, "ghost")
    assert {:error, :not_your_turn} = Session.update_state(session, "ghost", fn _ -> :bad end)
    assert {:ok, "b"} = Session.handoff(session, "b")
    assert {:ok, %{ok: true}} = Session.update_state(session, "a", fn _ -> %{ok: true} end)
  end

  test "last paused participant leaving reaches done only on resume; terminal cannot resurrect" do
    session = session(:round_robin, ["a"])
    assert {:ok, "a"} = Session.start(session)
    assert :ok = Session.pause(session)
    assert :ok = Session.leave(session, "a")
    assert Session.status(session) == :paused
    assert :ok = Session.resume(session)
    assert Session.status(session) == :done
    assert {:error, {:not_running, :done}} = Session.join(session, id: "new")
    assert :ok = Session.close(session)
    assert {:error, {:not_running, :closed}} = Session.join(session, id: "new")
  end

  test "v1 reader migrates data against the trusted policy without executing module tags" do
    map = %{
      "version" => 1,
      "session_id" => "old",
      "participants" => [
        %{"id" => "a", "kind" => "human"},
        %{"id" => "b", "kind" => "human"},
        %{"id" => "c", "kind" => "human"}
      ],
      "status" => "running",
      "current" => "b",
      "policy_mod" => "Elixir.ExAgent.Session.TurnPolicy.RoundRobin",
      "policy_state" => %{
        "__struct__" => "Elixir.ExAgent.Session.TurnPolicy.RoundRobin",
        "ids" => ["a", "b", "c"],
        "index" => 5,
        "current" => "b"
      }
    }

    assert {:ok, snapshot} = Snapshot.deserialize(Jason.encode!(map))
    assert snapshot.version == 2
    context = %{shared_state: nil, participants: [p("a"), p("b"), p("c")]}
    assert {:ok, policy} = Snapshot.restore(snapshot, TurnPolicy.RoundRobin, context)
    assert policy.index == 2

    assert {:error, :snapshot_policy_mismatch} =
             Snapshot.restore(snapshot, TurnPolicy.Initiative, context)

    name = Atom.to_string(DataOnlyModule)
    data_only = %{map | "policy_mod" => name, "policy_state" => %{"__struct__" => name}}
    assert {:ok, opaque} = Snapshot.deserialize(Jason.encode!(data_only))
    assert is_map(opaque.policy_state)
    refute is_struct(opaque.policy_state)

    assert {:error, :snapshot_policy_mismatch} =
             Snapshot.restore(opaque, TurnPolicy.RoundRobin, context)
  end

  test "custom policy persistence is an explicit trusted codec" do
    id = "coded-#{System.unique_integer([:positive])}"
    opts = [session_id: id, policy: CodedPolicy, participants: [p("a")], store: :ets]
    {:ok, first} = Session.start_link(opts)
    assert {:ok, "a"} = Session.start(first)
    GenServer.stop(first)
    {:ok, second} = Session.start_link(opts)
    assert Session.current(second) == "a"
    assert {:ok, "a"} = Session.end_turn(second, "a")
    GenServer.stop(second)
    ExAgent.Store.delete_session_snapshot({ExAgent.Store.ETS, ExAgent.Store.ETS}, id)
  end

  test "supervisor handoff outside the worker cycle restores the accepted actor and cursor" do
    id = "observer-#{System.unique_integer([:positive])}"

    opts = [
      session_id: id,
      participants: Enum.map(["s", "a", "observer"], &p/1),
      policy: {:supervisor, supervisor: "s", workers: ["a"]},
      store: :ets
    ]

    on_exit(fn ->
      ExAgent.Store.delete_session_snapshot({ExAgent.Store.ETS, ExAgent.Store.ETS}, id)
    end)

    assert {:ok, first} = Session.start_link(opts)
    assert {:ok, "s"} = Session.start(first)
    assert {:ok, "observer"} = Session.handoff(first, "observer")
    assert %{persistence: %{status: :confirmed}} = Session.health(first)
    GenServer.stop(first)

    assert {:ok, restored} = Session.start_link(opts)
    assert Session.current(restored) == "observer"
    assert {:ok, "a"} = Session.end_turn(restored, "observer")
    GenServer.stop(restored)
  end

  test "future, malformed and invalid-current snapshots fail with controlled errors" do
    assert {:error, _} = Snapshot.deserialize("[]")
    assert {:error, _} = Snapshot.deserialize("null")

    assert {:error, {:unsupported_snapshot_version, 999}} =
             Snapshot.deserialize(~s({"version":999}))

    session = session()
    assert {:ok, "a"} = Session.start(session)
    map = Snapshot.new(:sys.get_state(session)) |> Snapshot.serialize() |> Jason.decode!()

    for changes <- [
          %{"current" => "ghost"},
          %{"status" => "corrupt"},
          %{"seq" => -1},
          %{"participants" => [%{"id" => "a", "kind" => "alien"}]}
        ] do
      assert {:error, _} = Snapshot.deserialize(Jason.encode!(Map.merge(map, changes)))
    end
  end
end
