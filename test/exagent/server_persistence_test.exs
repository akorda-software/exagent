defmodule ExAgent.ServerPersistenceTest do
  # Persistence shares the app-wide ExAgent.Store.ETS table; use unique ids.
  use ExUnit.Case, async: true

  alias ExAgent.{Models.Test, Server, Store}

  describe "rehydration on start" do
    test "a server started against an existing snapshot restores history + usage" do
      id = unique_id("rehydrate")
      on_exit(fn -> Store.delete_agent_snapshot({ExAgent.Store.ETS, ExAgent.Store.ETS}, id) end)

      # First server: chat twice, then stop cleanly. Each run checkpoints.
      {:ok, a} =
        Server.start_link(
          agent: ExAgent.new(model: %Test{script: ["one", "two"]}, instructions: "be brief"),
          agent_id: id,
          store: :ets
        )

      assert {:ok, _} = Server.chat(a, "first")
      assert {:ok, _} = Server.chat(a, "second")
      assert length(Server.history(a)) == 4
      history = Server.history(a)
      usage = Server.usage(a)

      :ok = GenServer.stop(a, :normal)

      # A fresh server with the same id+store rehydrates the conversation.
      {:ok, b} =
        Server.start_link(
          agent: ExAgent.new(model: %Test{label: "fresh"}, instructions: "be brief"),
          agent_id: id,
          store: :ets
        )

      assert Server.history(b) == history
      assert Server.usage(b) == usage
      assert {:ok, %{output: "fresh"}} = Server.chat(b, "third")
      assert Enum.take(Server.history(b), 4) == history
      GenServer.stop(b)
    end

    test "starting with a store but no prior snapshot just starts empty" do
      id = unique_id("empty")
      on_exit(fn -> Store.delete_agent_snapshot({ExAgent.Store.ETS, ExAgent.Store.ETS}, id) end)

      {:ok, server} =
        Server.start_link(
          agent: ExAgent.new(model: %Test{label: "hi"}),
          agent_id: id,
          store: :ets
        )

      assert Server.history(server) == []
      assert Server.usage(server).input_tokens == 0

      GenServer.stop(server, :normal)
    end
  end

  describe "crash recovery under the DynamicSupervisor" do
    test "a killed supervised server restarts with its history intact" do
      id = unique_id("crash")
      name = :"agent_#{id}"

      {:ok, pid} =
        ExAgent.AgentSupervisor.start_agent(
          agent:
            ExAgent.new(
              model: %Test{script: ["turn one", "turn two", "turn three"]},
              instructions: "you are a DM"
            ),
          agent_id: id,
          store: :ets,
          name: name
        )

      on_exit(fn ->
        ExAgent.Test.TestingAuditRuntime.stop_restarted_agent(pid, name)
        Store.delete_agent_snapshot({ExAgent.Store.ETS, ExAgent.Store.ETS}, id)
      end)

      assert {:ok, _} = Server.chat(name, "roll initiative")
      assert {:ok, _} = Server.chat(name, "open the door")
      assert length(Server.history(name)) == 4
      history = Server.history(name)
      usage = Server.usage(name)

      # Crash the server. The DynamicSupervisor (restart: :transient) brings it
      # back; the new process rehydrates history/usage from the store.
      monitor = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 1000
      assert wait_for_restart(name, pid)

      # New pid, same registered name, conversation preserved.
      assert Process.whereis(name) != pid
      assert Server.history(name) == history
      assert Server.usage(name) == usage

      # It keeps working — a new chat threads onto the restored history. Note
      # the MODEL restarts from the live template (its script index is NOT
      # persisted), so this returns the template's first scripted reply.
      assert {:ok, %{output: "turn one"}} = Server.chat(name, "loot the room")
      assert length(Server.history(name)) == 6
    end
  end

  # ---------------------------------------------------------------------------
  defp unique_id(prefix), do: "#{prefix}_#{:erlang.unique_integer([:positive])}"

  defp wait_for_restart(name, original, tries \\ 100) do
    cond do
      tries <= 0 ->
        false

      Process.whereis(name) not in [nil, original] and restart_ready?(name) ->
        true

      true ->
        Process.sleep(5)
        wait_for_restart(name, original, tries - 1)
    end
  end

  defp restart_ready?(name) do
    try do
      %{status: _} = Server.health(name)
      true
    rescue
      _ -> false
    catch
      :exit, _ -> false
    end
  end
end
