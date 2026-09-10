defmodule ExAgent.SessionSequenceTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias ExAgent.{CheckpointError, Session}
  alias ExAgent.Session.{Participant, Snapshot, TurnPolicy}

  defmodule ByteStore do
    @behaviour ExAgent.Store

    def save_session_snapshot(store, snapshot) do
      bytes = Snapshot.serialize(snapshot)
      mode = Agent.get_and_update(store, &{&1.mode, %{&1 | attempts: &1.attempts ++ [bytes]}})

      case mode do
        :ok -> Agent.update(store, &%{&1 | bytes: bytes})
        :error -> {:error, :sequence_disk_full}
        :raise -> raise "sequence store unavailable"
      end
    end

    def load_session_snapshot(store, _) do
      Agent.update(store, &%{&1 | loads: &1.loads + 1})

      case Agent.get(store, & &1) do
        %{load: :raise} -> raise "sequence load failed"
        %{load: :exit} -> exit(:sequence_load_failed)
        %{load: :error} -> {:error, :sequence_load_failed}
        %{bytes: nil} -> {:error, :not_found}
        %{bytes: bytes} -> Snapshot.deserialize(bytes)
      end
    end

    def save_agent_snapshot(_, _), do: {:error, :unused}
    def load_agent_snapshot(_, _), do: {:error, :not_found}
    def list_agent_snapshots(_), do: []
    def delete_agent_snapshot(_, _), do: :ok
  end

  defmodule CodecPolicy do
    @behaviour TurnPolicy
    defstruct actor: "a"
    def init(_), do: %__MODULE__{}
    def next_participant(state, _), do: {:ok, state.actor, state}
    def can_act?(state, id, _), do: state.actor == id
    def snapshot(state), do: {:ok, 1, %{"actor" => state.actor, "mode" => "ok"}}

    def restore_snapshot(1, data, _) do
      case data["mode"] do
        "raise" -> raise "codec failure"
        "throw" -> throw(:codec_failure)
        "exit" -> exit(:codec_failure)
        "wrong_struct" -> {:ok, %TurnPolicy.RoundRobin{}}
        "invalid_return" -> :ok
        "error" -> {:error, :codec_refused}
        "ok" -> {:ok, %__MODULE__{actor: data["actor"]}}
      end
    end
  end

  for seed <- [8_013, 28_042, 61_009] do
    @tag sequence_seed: seed
    test "Session roster/round/checkpoint sequence seed #{seed}" do
      :rand.seed(:exsss, {unquote(seed), 31, 53})
      store = store()
      id = "session-sequence-#{unquote(seed)}"
      expected = initial_model()
      session = start_session(store, id, expected)
      assert_state(session, store, expected)

      {session, expected} =
        Enum.reduce(1..48, {session, expected}, fn step, {session, expected} ->
          command = if step == 1, do: :start, else: choose(expected)
          mode = if rem(step, 13) == 0, do: Enum.random([:error, :raise]), else: :ok
          expected = execute(session, store, expected, command, step, mode)
          assert_state(session, store, expected, {unquote(seed), step, command})
          expected = recover(session, store, expected, step)

          if rem(step, 12) == 0 do
            # A real stop/start reads serialized Store bytes. Alternate v2 and
            # legacy v1 bytes while preserving the independent planned round.
            session =
              restart(session, store, id, expected, if(rem(step, 24) == 0, do: 1, else: 2))

            assert_state(session, store, expected, {unquote(seed), step, :restore})
            {session, expected}
          else
            {session, expected}
          end
        end)

      expected = execute(session, store, expected, :close, 49, :ok)
      expected = execute(session, store, expected, :close, 50, :ok)
      assert_state(session, store, expected)
      assert {:error, {:not_running, :closed}} = Session.join(session, id: "resurrect")

      assert {:error, {:not_running, :closed}} =
               Session.take_turn(session, expected.actor, fn _ ->
                 Agent.update(store, &%{&1 | changes: &1.changes + 1})
               end)

      session = restart(session, store, id, expected, 2)
      assert_state(session, store, expected)
    end
  end

  test "codec and load failures preserve original bytes, then a trusted successful restore can mutate" do
    Process.flag(:trap_exit, true)
    store = store()
    base = coded_bytes()

    cases =
      for mode <- ["raise", "throw", "exit", "wrong_struct", "invalid_return", "error"] do
        {"codec #{mode}", put_in(base, ["policy_state", "mode"], mode), :ok}
      end

    cases = cases ++ for mode <- [:error, :raise, :exit], do: {"load #{mode}", base, mode}

    for {label, data, load} <- cases do
      bytes = Jason.encode!(data)
      Agent.update(store, &%{&1 | bytes: bytes, load: load})

      assert {:error, {:restore_failed, _}} =
               Session.start_link(
                 session_id: "codec-sequence",
                 policy: CodecPolicy,
                 store: {ByteStore, store}
               ),
             label

      assert Agent.get(store, & &1.bytes) == bytes, label
      assert Agent.get(store, & &1.attempts) == [], label
    end

    Agent.update(store, &%{&1 | bytes: Jason.encode!(base), load: :ok})

    session =
      start_supervised!(
        {Session, session_id: "codec-sequence", policy: CodecPolicy, store: {ByteStore, store}}
      )

    assert Session.current(session) == "a"
    assert :ok = Session.pause(session)
    assert %{persistence: %{revision: 5, status: :confirmed}} = Session.health(session)
    assert length(Agent.get(store, & &1.attempts)) == 1
  end

  test "adversarial Store bytes cannot choose modules or overwrite a recoverable checkpoint" do
    Process.flag(:trap_exit, true)
    store = store()
    base = coded_bytes()
    bytes = Jason.encode!(base)
    unknown = "Elixir.SequenceUntrusted#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    corruptions = [
      binary_part(bytes, 0, byte_size(bytes) - 1),
      Jason.encode!(%{base | "version" => 999}),
      Jason.encode!(%{base | "session_id" => "wrong-id"}),
      Jason.encode!(%{base | "policy_mod" => unknown}),
      Jason.encode!(%{base | "policy_version" => 999}),
      Jason.encode!(%{base | "policy_state" => %{"__struct__" => unknown}})
    ]

    for poisoned <- corruptions do
      Agent.update(store, &%{&1 | bytes: poisoned})

      assert {:error, {:restore_failed, _}} =
               Session.start_link(
                 session_id: "codec-sequence",
                 policy: CodecPolicy,
                 store: {ByteStore, store}
               )

      assert Agent.get(store, & &1.bytes) == poisoned
      assert Agent.get(store, & &1.attempts) == []
      assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    end

    Agent.update(store, &%{&1 | bytes: bytes})

    session =
      start_supervised!(
        {Session, session_id: "codec-sequence", policy: CodecPolicy, store: {ByteStore, store}}
      )

    assert Session.read_state(session) == %{"n" => 12}
    assert Session.current(session) == "a"
    assert :ok = Session.checkpoint(session)
    assert Agent.get(store, & &1.bytes) == bytes
    assert Agent.get(store, & &1.attempts) == []
  end

  defp coded_bytes do
    %{
      "version" => 2,
      "revision" => 4,
      "session_id" => "codec-sequence",
      "participants" => [%{"id" => "a", "kind" => "human"}],
      "shared_state" => %{"n" => 12},
      "status" => "running",
      "current" => "a",
      "policy_mod" => Atom.to_string(CodecPolicy),
      "policy_version" => 1,
      "policy_state" => %{"actor" => "a", "mode" => "ok"}
    }
  end

  defp store do
    start_supervised!(
      {Agent,
       fn ->
         %{mode: :ok, load: :ok, bytes: nil, attempts: [], changes: 0, loads: 0}
       end}
    )
  end

  # A round is a list of people still owed a turn, not an implementation index.
  # A handoff changes only the actor; adding/removing people edits that owed list.
  defp initial_model do
    %{
      order: ["a", "b", "c"],
      due: ["a", "b", "c"],
      actor: nil,
      status: :created,
      roster: Map.new(["a", "b", "c"], &{&1, {nil, %{}}}),
      n: 0,
      revision: 0,
      attempts: [],
      changes: 0,
      dirty: false,
      durable: nil
    }
  end

  defp start_session(store, id, expected) do
    participants =
      Enum.map(expected.order, fn id ->
        {ref, metadata} = Map.fetch!(expected.roster, id)
        Participant.new(id: id, ref: ref, metadata: metadata)
      end)

    start_supervised!(
      Supervisor.child_spec(
        {Session,
         session_id: id,
         participants: participants,
         shared_state: %{"n" => 0},
         store: {ByteStore, store}},
        id: make_ref(),
        restart: :temporary
      )
    )
  end

  defp choose(expected) do
    common = [
      {:join, Enum.random(["a", "b", "c", "d", "e"])},
      {:join, Enum.random(expected.order)},
      :invalid_turn
    ]

    choices =
      case expected.status do
        :running ->
          [:turn, :turn, :end_turn, :pause, {:handoff, Enum.random(expected.order)}]

        :paused ->
          [:resume, :resume, :invalid_turn]
      end

    choices =
      if length(expected.order) > 1,
        do: [{:leave, Enum.random(expected.order)} | choices],
        else: choices

    Enum.random(common ++ choices)
  end

  defp execute(session, store, expected, command, stamp, mode) do
    Agent.update(store, &%{&1 | mode: mode})
    {reply, candidate, writes, changes} = model_step(expected, command, stamp)
    actual = invoke(session, store, expected, command, stamp)

    if writes == 1 do
      revision = expected.revision + 1

      if mode == :ok do
        assert actual == reply
      else
        assert {:error, %CheckpointError{revision: ^revision, result: ^reply}} = actual
      end

      candidate = %{
        candidate
        | revision: revision,
          attempts: expected.attempts ++ [revision],
          changes: expected.changes + changes,
          dirty: mode != :ok
      }

      if mode == :ok, do: %{candidate | durable: view(candidate)}, else: candidate
    else
      assert actual == reply
      candidate
    end
  end

  defp invoke(session, store, expected, :turn, _) do
    Session.take_turn(session, expected.actor, fn state ->
      Agent.update(store, &%{&1 | changes: &1.changes + 1})
      {:ok, Map.update!(state, "n", &(&1 + 1))}
    end)
  end

  defp invoke(session, store, _, :invalid_turn, _) do
    Session.take_turn(session, "ghost", fn _ ->
      Agent.update(store, &%{&1 | changes: &1.changes + 1})
      %{"n" => -1000}
    end)
  end

  defp invoke(session, _, expected, :end_turn, _), do: Session.end_turn(session, expected.actor)
  defp invoke(session, _, _, {:handoff, id}, _), do: Session.handoff(session, id)
  defp invoke(session, _, _, {:leave, id}, _), do: Session.leave(session, id)

  defp invoke(session, _, _, {:join, id}, stamp),
    do: Session.join(session, id: id, ref: {:live, stamp}, metadata: %{"stamp" => stamp})

  defp invoke(session, _, _, command, _), do: apply(Session, command, [session])

  defp model_step(expected, :start, _) do
    next = advance(%{expected | status: :running})
    {{:ok, next.actor}, next, 1, 0}
  end

  defp model_step(expected, {:join, id}, stamp) do
    candidate = %{
      expected
      | roster: Map.put(expected.roster, id, {{:live, stamp}, %{"stamp" => stamp}})
    }

    candidate =
      if id in expected.order,
        do: candidate,
        else: %{candidate | order: expected.order ++ [id], due: expected.due ++ [id]}

    {:ok, candidate, 1, 0}
  end

  defp model_step(expected, {:leave, id}, _) do
    candidate = %{
      expected
      | order: List.delete(expected.order, id),
        due: List.delete(expected.due, id),
        roster: Map.delete(expected.roster, id)
    }

    candidate =
      if expected.actor == id do
        candidate = %{candidate | actor: nil}
        if expected.status == :running, do: advance(candidate), else: candidate
      else
        candidate
      end

    {:ok, candidate, 1, 0}
  end

  defp model_step(expected, :invalid_turn, _) do
    reason = if expected.status == :paused, do: :paused, else: :not_your_turn
    {{:error, reason}, expected, 0, 0}
  end

  defp model_step(expected, command, _) when command in [:turn, :end_turn] do
    next = advance(expected)

    if command == :turn do
      next = %{next | n: expected.n + 1}
      {{:ok, %{"n" => next.n}, next.actor}, next, 1, 1}
    else
      {{:ok, next.actor}, next, 1, 0}
    end
  end

  defp model_step(expected, {:handoff, id}, _), do: {{:ok, id}, %{expected | actor: id}, 1, 0}
  defp model_step(expected, :pause, _), do: {:ok, %{expected | status: :paused}, 1, 0}

  defp model_step(expected, :resume, _) do
    next = %{expected | status: :running}
    {:ok, if(next.actor, do: next, else: advance(next)), 1, 0}
  end

  defp model_step(%{status: :closed} = expected, :close, _), do: {:ok, expected, 0, 0}
  defp model_step(expected, :close, _), do: {:ok, %{expected | status: :closed}, 1, 0}

  defp advance(%{due: []} = expected), do: advance(%{expected | due: expected.order})
  defp advance(%{due: [actor | rest]} = expected), do: %{expected | actor: actor, due: rest}

  defp recover(_, _, %{dirty: false} = expected, _), do: expected

  defp recover(session, store, expected, step) do
    revision = expected.revision

    for command <- [{:join, "blocked"}, :invalid_turn, :close] do
      assert {:error, %CheckpointError{revision: ^revision}} =
               invoke(session, store, expected, command, step)

      assert_state(session, store, expected, {step, :blocked, command})
    end

    Agent.update(store, &%{&1 | mode: :raise})
    assert {:error, %CheckpointError{revision: ^revision}} = Session.checkpoint(session)
    expected = %{expected | attempts: expected.attempts ++ [revision]}
    assert_state(session, store, expected, {step, :retry_failed})

    Agent.update(store, &%{&1 | mode: :ok})
    assert :ok = Session.checkpoint(session)

    expected = %{
      expected
      | attempts: expected.attempts ++ [revision],
        dirty: false,
        durable: view(expected)
    }

    assert_state(session, store, expected, {step, :retry_confirmed})
    assert :ok = Session.checkpoint(session)
    assert_state(session, store, expected, {step, :clean_checkpoint})
    expected
  end

  defp restart(session, store, id, expected, version) do
    loads = Agent.get(store, & &1.loads)
    GenServer.stop(session)
    before = Agent.get(store, & &1)

    if version == 1 do
      Agent.update(store, fn s ->
        data = Jason.decode!(s.bytes)

        legacy =
          data
          |> Map.put("version", 1)
          |> Map.update!("policy_state", &Map.put(&1, "__struct__", data["policy_mod"]))

        %{s | bytes: Jason.encode!(legacy)}
      end)
    end

    restored = start_session(store, id, expected)
    assert Agent.get(store, & &1.loads) == loads + 1
    assert Agent.get(store, & &1.attempts) == before.attempts
    assert Agent.get(store, & &1.changes) == before.changes
    restored
  end

  defp view(expected),
    do: Map.take(expected, [:order, :due, :actor, :status, :n, :revision])

  defp assert_state(session, store, expected, trace \\ :final) do
    label = inspect(trace)
    assert Session.status(session) == expected.status, label
    assert Session.current(session) == expected.actor, label
    assert Session.read_state(session) == %{"n" => expected.n}, label
    roster = Map.new(Session.participants(session), &{&1.id, {&1.ref, &1.metadata}})
    assert roster == expected.roster, label
    health = Session.health(session).persistence
    assert health.revision == expected.revision, label
    assert health.status == if(expected.dirty, do: :unconfirmed, else: :confirmed), label
    observed = Agent.get(store, & &1)
    assert observed.changes == expected.changes, label
    assert Enum.map(observed.attempts, &Jason.decode!(&1)["revision"]) == expected.attempts, label

    if observed.attempts != [] do
      assert_snapshot(List.last(observed.attempts), view(expected), label)
    end

    if expected.durable, do: assert_snapshot(observed.bytes, expected.durable, label)
  end

  defp assert_snapshot(bytes, expected, label) do
    assert {:ok, saved} = Snapshot.deserialize(bytes), label
    assert saved.revision == expected.revision, label
    assert saved.current == expected.actor, label
    assert saved.status == expected.status, label
    assert saved.shared_state == %{"n" => expected.n}, label
    assert Enum.sort(Enum.map(saved.participants, & &1.id)) == Enum.sort(expected.order), label
    assert saved.policy_state["ids"] == expected.order, label
    # Observe the persisted cursor, but calculate expectations from the owed
    # round model rather than the runtime's index arithmetic or private state.
    assert Enum.drop(saved.policy_state["ids"], saved.policy_state["index"]) == expected.due,
           label

    assert saved.policy_state["current"] == expected.actor, label
  end
end
