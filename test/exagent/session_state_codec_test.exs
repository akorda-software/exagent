defmodule ExAgent.SessionStateCodecTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Session, Store}
  alias ExAgent.Session.Participant

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  defmodule State do
    defstruct count: 0
  end

  defmodule Codec do
    @behaviour ExAgent.Session.StateCodec
    def encode(%State{count: count}), do: {:ok, %{"count" => count}}
    def decode(%{"count" => count}) when is_integer(count), do: {:ok, %State{count: count}}
    def decode(_), do: {:error, :invalid_count}
  end

  defmodule Broken do
    def encode(_), do: {:ok, fn -> :not_json end}
    def decode(_), do: raise("secret diagnostic")
  end

  defmodule Watching do
    def encode(value), do: {:ok, value}

    def decode(value) do
      send(Process.whereis(__MODULE__), :decoded)
      {:ok, value}
    end
  end

  defmodule WrongIDStore do
    def load_session_snapshot(snapshot, _id), do: {:ok, snapshot}
  end

  defp opts(id, codec) do
    [
      session_id: id,
      store: :ets,
      shared_state_codec: codec,
      shared_state: %State{},
      participants: [Participant.new(id: "a"), Participant.new(id: "b")]
    ]
  end

  test "a trusted codec restores structs and the same scheduling cursor from JSON" do
    id = "codec-#{System.unique_integer([:positive])}"
    on_exit(fn -> Store.delete_session_snapshot({ExAgent.Store.ETS, ExAgent.Store.ETS}, id) end)
    {:ok, first} = Session.start_link(opts(id, Codec))
    assert {:ok, "a"} = Session.start(first)

    assert {:ok, %State{count: 1}, "b"} =
             Session.take_turn(first, "a", fn s -> {:ok, %{s | count: s.count + 1}} end)

    :ok = GenServer.stop(first)
    assert {:ok, raw} = Store.load_session_snapshot({ExAgent.Store.ETS, ExAgent.Store.ETS}, id)
    assert raw.shared_state == %{"count" => 1}
    refute ExAgent.Session.Snapshot.serialize(raw) =~ "Codec"
    {:ok, second} = Session.start_link(opts(id, Codec))
    assert Session.read_state(second) == %State{count: 1}
    assert Session.current(second) == "b"

    assert {:ok, %State{count: 2}, "a"} =
             Session.take_turn(second, "b", fn s -> {:ok, %{s | count: s.count + 1}} end)

    GenServer.stop(second)
  end

  test "invalid codecs are refused and failed encoding never silently persists state" do
    assert {:error, {:restore_failed, :invalid_shared_state_codec}} =
             Session.start_link(opts("invalid-codec", String))

    id = "bad-codec-#{System.unique_integer([:positive])}"
    {:ok, session} = Session.start_link(opts(id, Broken))
    assert {:error, %ExAgent.CheckpointError{}} = Session.start(session)
    assert Session.read_state(session) == %State{}
    assert Session.health(session).persistence.status == :unconfirmed

    assert {:error, :not_found} =
             Store.load_session_snapshot({ExAgent.Store.ETS, ExAgent.Store.ETS}, id)

    assert {:error, %ExAgent.CheckpointError{}} =
             Session.take_turn(session, "a", fn _ -> flunk("unconfirmed state cannot mutate") end)

    GenServer.stop(session)
  end

  test "a snapshot identity mismatch is rejected before invoking the configured decoder" do
    Process.register(self(), Watching)
    id = "watch-codec-#{System.unique_integer([:positive])}"
    {:ok, session} = Session.start_link(opts(id, Codec))
    assert {:ok, "a"} = Session.start(session)
    GenServer.stop(session)
    store = {ExAgent.Store.ETS, ExAgent.Store.ETS}
    assert {:ok, snapshot} = Store.load_session_snapshot(store, id)
    wrong = %{snapshot | session_id: "wrong-#{id}"}
    settings = opts(id, Watching) |> Keyword.put(:store, {WrongIDStore, wrong})
    assert {:error, {:restore_failed, :snapshot_id_mismatch}} = Session.start_link(settings)
    refute_receive :decoded, 0
    Store.delete_session_snapshot(store, id)
  end

  test "decoding failures disclose neither state nor callback exception details" do
    assert {:error, :shared_state_codec_failed} =
             ExAgent.Session.StateCodec.load(Broken, %{"secret" => "private"})

    assert {:error, :shared_state_codec_failed} =
             ExAgent.Session.StateCodec.load(Codec, %{"count" => "invalid"})
  end

  test "policy and continuation identities are checked before the application decoder" do
    Process.register(self(), Watching)
    id = "identity-codec-#{System.unique_integer([:positive])}"
    {:ok, session} = Session.start_link(opts(id, Codec))
    assert {:ok, "a"} = Session.start(session)
    GenServer.stop(session)
    store = {ExAgent.Store.ETS, ExAgent.Store.ETS}
    assert {:ok, snapshot} = Store.load_session_snapshot(store, id)

    wrong_policy = %{snapshot | policy_mod: "Untrusted.Stored.Policy"}
    settings = opts(id, Watching) |> Keyword.put(:store, {WrongIDStore, wrong_policy})
    assert {:error, {:restore_failed, :snapshot_policy_mismatch}} = Session.start_link(settings)
    refute_receive :decoded, 0

    start_supervised!({ExAgent.Store.ETS, table: __MODULE__})
    scope = Store.scoped({ExAgent.Store.ETS, __MODULE__}, "codec")

    prior =
      ExAgent.Session.Continuations.dump(%{
        continuation_bindings: %{"a" => %{store: scope, id: "prior-agent"}},
        continuation_state: %{}
      })

    settings =
      opts(id, Watching)
      |> Keyword.put(:store, {WrongIDStore, %{snapshot | version: 3, continuations: prior}})
      |> Keyword.put(:continuations, %{"a" => %{store: scope, id: "agent"}})

    assert {:error, {:restore_failed, :session_continuation_binding_changed}} =
             Session.start_link(settings)

    refute_receive :decoded, 0
    Store.delete_session_snapshot(store, id)
  end
end
