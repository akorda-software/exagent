defmodule ExAgent.Store.ETSClusterTest do
  use ExUnit.Case, async: false

  alias ExAgent.Server.Snapshot
  alias ExAgent.Store

  @moduletag timeout: 60_000
  @store {Store.ETS, Store.ETS}

  test "connected nodes can each start the application and keep independent stores" do
    {left, left_node} = peer("left")
    {right, right_node} = peer("right")
    connect(left, right, right_node)

    assert {:ok, _} = call(left, Application, :ensure_all_started, [:exagent])
    assert {:ok, _} = call(right, Application, :ensure_all_started, [:exagent])

    assert_local_stores(left, left_node, right, right_node)
  end

  test "joining already running nodes preserves each ETS owner and its snapshots" do
    {left, left_node} = peer("left")
    {right, right_node} = peer("right")
    assert [] = call(left, Node, :list, [])
    assert [] = call(right, Node, :list, [])
    assert {:ok, _} = call(left, Application, :ensure_all_started, [:exagent])
    assert {:ok, _} = call(right, Application, :ensure_all_started, [:exagent])

    left_owner = call(left, :ets, :info, [Store.ETS, :owner])
    right_owner = call(right, :ets, :info, [Store.ETS, :owner])
    save(left, "before-connect", "left")
    save(right, "before-connect", "right")

    connect(left, right, right_node)

    assert ^left_owner = call(left, :ets, :info, [Store.ETS, :owner])
    assert ^right_owner = call(right, :ets, :info, [Store.ETS, :owner])
    assert {:ok, %{metadata: %{"node" => "left"}}} = load(left, "before-connect")
    assert {:ok, %{metadata: %{"node" => "right"}}} = load(right, "before-connect")
    assert_local_stores(left, left_node, right, right_node)
  end

  defp peer(label) do
    {:ok, peer, node} =
      :peer.start_link(%{
        name: :peer.random_name(String.to_charlist("exagent_store_" <> label)),
        host: ~c"localhost",
        longnames: false,
        connection: :standard_io,
        args: [
          ~c"+S",
          ~c"2:2",
          ~c"-setcookie",
          ~c"exagent_store_cluster_fixture",
          ~c"-kernel",
          ~c"inet_dist_use_interface",
          ~c"{127,0,0,1}"
        ],
        wait_boot: 15_000
      })

    on_exit(fn ->
      if Process.alive?(peer), do: :peer.stop(peer)
    end)

    :ok = call(peer, :code, :add_paths, [:code.get_path()])
    :ok = call(peer, Application, :put_env, [:req_llm, :load_dotenv, false])
    {peer, node}
  end

  defp connect(left, right, right_node) do
    assert true == call(left, Node, :connect, [right_node])
    assert :ok == call(left, :global, :sync, [])
    assert :ok == call(right, :global, :sync, [])
  end

  defp assert_local_stores(left, left_node, right, right_node) do
    for {peer, expected_node, label} <- [{left, left_node, "left"}, {right, right_node, "right"}] do
      owner = call(peer, :ets, :info, [Store.ETS, :owner])
      assert is_pid(owner) and node(owner) == expected_node
      assert call(peer, Process, :alive?, [owner])

      assert %{continuation: :atomic, durability: :ephemeral} =
               call(peer, Store.ETS, :capabilities, [Store.ETS])

      save(peer, "same-id", label)
    end

    assert {:ok, %{metadata: %{"node" => "left"}}} = load(left, "same-id")
    assert {:ok, %{metadata: %{"node" => "right"}}} = load(right, "same-id")
    assert :ok = call(left, Store, :delete_agent_snapshot, [@store, "same-id"])
    assert {:error, :not_found} = load(left, "same-id")
    assert {:ok, _} = load(right, "same-id")
  end

  defp save(peer, id, label) do
    snapshot = Snapshot.new(agent_id: id, metadata: %{"node" => label})
    assert :ok = call(peer, Store, :save_agent_snapshot, [@store, snapshot])
  end

  defp load(peer, id), do: call(peer, Store, :load_agent_snapshot, [@store, id])
  defp call(peer, mod, fun, args), do: :peer.call(peer, mod, fun, args, 15_000)
end
