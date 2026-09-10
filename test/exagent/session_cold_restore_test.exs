defmodule ExAgent.SessionColdRestoreTest do
  use ExUnit.Case, async: false
  alias ExAgent.Session
  alias ExAgent.Session.{Participant, Snapshot}
  alias ExAgent.Test.ColdSessionPolicy

  defmodule ReadOnlyStore do
    @behaviour ExAgent.Store
    def load_session_snapshot({_owner, snapshot}, _id), do: {:ok, snapshot}
    def save_session_snapshot({owner, _snapshot}, _value), do: send(owner, :unexpected_save)
    def save_agent_snapshot(_, _), do: {:error, :unused}
    def load_agent_snapshot(_, _), do: {:error, :not_found}
    def list_agent_snapshots(_), do: []
    def delete_agent_snapshot(_, _), do: :ok
  end

  defp snapshot(mod) do
    %Snapshot{
      session_id: "cold",
      participants: [%{id: "a", kind: :human}],
      status: :running,
      current: "a",
      policy_mod: Atom.to_string(mod),
      policy_state: %{"actor" => "a"}
    }
  end

  defp start(mod) do
    Session.start_link(
      session_id: "cold",
      policy: mod,
      participants: [Participant.new(id: "a")],
      store: {ReadOnlyStore, {self(), snapshot(mod)}}
    )
  end

  test "a trusted persisted custom policy is loaded from its BEAM on cold restore" do
    assert {:module, ColdSessionPolicy} = Code.ensure_loaded(ColdSessionPolicy)
    assert is_list(:code.which(ColdSessionPolicy))
    on_exit(fn -> Code.ensure_loaded(ColdSessionPolicy) end)
    :code.purge(ColdSessionPolicy)
    assert :code.delete(ColdSessionPolicy)
    :code.purge(ColdSessionPolicy)
    assert :code.is_loaded(ColdSessionPolicy) == false

    assert {:ok, session} = start(ColdSessionPolicy)
    assert Session.current(session) == "a"
    assert :code.is_loaded(ColdSessionPolicy) != false
    GenServer.stop(session)
    refute_received :unexpected_save
  end

  test "missing trusted module and existing module without codec fail without writes" do
    Process.flag(:trap_exit, true)
    missing = ExAgent.Test.NonexistentSessionPolicy
    assert {:error, {:restore_failed, {:policy_module_unavailable, ^missing, _}}} = start(missing)
    assert {:error, {:restore_failed, :unsupported_policy_snapshot}} = start(String)
    refute_received :unexpected_save
  end
end
