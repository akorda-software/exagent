defmodule ExAgent.Store.PostgresTest do
  use ExUnit.Case, async: false

  # The repo is started once in test_helper.exs; the whole module is skipped
  # (:postgres excluded) when Postgres isn't available.
  @moduletag :postgres

  alias ExAgent.Message.Usage
  alias ExAgent.Server.Snapshot
  alias ExAgent.Store

  @repo ExAgent.TestRepo
  @store {ExAgent.Store.Postgres, @repo}

  describe "Postgres — save / load / delete" do
    test "round-trips a snapshot keyed by agent_id" do
      id = unique_id("pg_rt")
      on_exit(fn -> Store.delete_agent_snapshot(@store, id) end)
      history = history()

      snap =
        Snapshot.new(
          agent_id: id,
          history: history,
          usage: %Usage{input_tokens: 2, output_tokens: 3},
          metadata: %{scene: "tavern"}
        )

      assert :ok = Store.save_agent_snapshot(@store, snap)
      assert {:ok, loaded} = Store.load_agent_snapshot(@store, id)
      assert loaded.agent_id == id
      assert loaded.usage == %{"input_tokens" => 2, "output_tokens" => 3, "details" => %{}}
      assert loaded.metadata == %{"scene" => "tavern"}

      {:ok, messages} = Snapshot.messages(loaded)
      assert messages == history

      assert :ok = Store.delete_agent_snapshot(@store, id)
      assert {:error, :not_found} = Store.load_agent_snapshot(@store, id)
    end

    test "overwrites the same id and lists entries" do
      a = unique_id("pg_a")
      b = unique_id("pg_b")

      on_exit(fn ->
        Store.delete_agent_snapshot(@store, a)
        Store.delete_agent_snapshot(@store, b)
      end)

      Store.save_agent_snapshot(@store, Snapshot.new(agent_id: a, history: [], usage: nil))
      Store.save_agent_snapshot(@store, Snapshot.new(agent_id: b, history: [], usage: nil))

      ids = @store |> Store.list_agent_snapshots() |> Enum.map(& &1.agent_id)
      assert a in ids and b in ids

      Store.save_agent_snapshot(
        @store,
        Snapshot.new(
          agent_id: a,
          history: history(),
          usage: %Usage{input_tokens: 9, output_tokens: 0}
        )
      )

      assert {:ok, loaded} = Store.load_agent_snapshot(@store, a)
      assert loaded.usage == %{"input_tokens" => 9, "output_tokens" => 0, "details" => %{}}

      Store.delete_agent_snapshot(@store, a)
      Store.delete_agent_snapshot(@store, b)
    end

    test "persists only JSON-safe state (no closures)" do
      id = unique_id("pg_leak")

      bad = Snapshot.new(agent_id: id, history: [], metadata: %{capture: fn -> :secret end})

      # The adapter's strict codec raises; the Store dispatcher contains it.
      assert {:error, {:exception, %Protocol.UndefinedError{}}} =
               Store.save_agent_snapshot(@store, bad)

      assert {:error, :not_found} = Store.load_agent_snapshot(@store, id)
    end
  end

  describe "Server rehydration via Postgres" do
    test "a killed supervised agent restarts with its history intact" do
      id = unique_id("pg_crash")
      name = :"pg_agent_#{id}"

      {:ok, pid} =
        ExAgent.AgentSupervisor.start_agent(
          agent: ExAgent.new(model: %ExAgent.Models.Test{label: "ok"}, instructions: "be brief"),
          agent_id: id,
          store: @store,
          name: name
        )

      on_exit(fn ->
        ExAgent.Test.TestingAuditRuntime.stop_restarted_agent(pid, name)
        Store.delete_agent_snapshot(@store, id)
      end)

      assert {:ok, _} = ExAgent.Server.chat(name, "turn one")
      assert {:ok, _} = ExAgent.Server.chat(name, "turn two")
      assert length(ExAgent.Server.history(name)) == 4

      monitor = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 1000
      assert wait_for_restart(name, pid)

      assert Process.whereis(name) != pid
      assert length(ExAgent.Server.history(name)) == 4
    end
  end

  # ---------------------------------------------------------------------------
  defp history do
    {:ok, %{messages: messages}} =
      ExAgent.run(ExAgent.new(model: "test", instructions: "hi"), "hello")

    messages
  end

  defp unique_id(prefix), do: "#{prefix}_#{:erlang.unique_integer([:positive])}"

  # PG-backed restart + rehydrate can take longer under DB contention when the
  # full suite runs concurrently; allow up to ~2s.
  defp wait_for_restart(name, original, tries \\ 400) do
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
      %{status: _} = ExAgent.Server.health(name)
      true
    rescue
      _ -> false
    catch
      :exit, _ -> false
    end
  end
end
