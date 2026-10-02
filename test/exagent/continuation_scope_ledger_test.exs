defmodule ExAgent.ContinuationScopeLedgerTest do
  use ExUnit.Case, async: true
  alias ExAgent.{ExecutionScope, Permissions, UsageLimits}
  alias ExAgent.Message.Usage

  defp tree(opts \\ []) do
    model = %ExAgent.Models.Test{}
    {:ok, root} = ExecutionScope.start("root", model, opts)
    {:ok, child} = ExecutionScope.join(root, "child", model, estimate_cost: fn _ -> 7 end)
    {:ok, leaf} = ExecutionScope.join(child, "leaf", model, [])
    {:ok, sibling} = ExecutionScope.join(root, "sibling", model, [])
    on_exit(fn -> ExecutionScope.stop(root) end)
    {root, child, leaf, sibling, model}
  end

  defp request(scope, model, id, tools) do
    :ok = ExecutionScope.admit_request(scope, id, model)
    :ok = ExecutionScope.record_usage(scope, id, %Usage{input_tokens: 2, output_tokens: 3}, true)
    :ok = ExecutionScope.finish_request(scope, id)
    :ok = ExecutionScope.admit_tools(scope, id, tools)
  end

  test "tree roundtrip preserves per-ancestor prices and exact reservations without repricing" do
    {root, child, leaf, sibling, model} = tree(estimate_cost: fn _ -> 2 end)
    request(root, model, "r", 2)
    request(leaf, model, "l", 1)
    request(sibling, model, "s", 0)

    :ok =
      ExecutionScope.contribute(leaf, {"l", "same-call"}, %Usage{
        input_tokens: 1,
        output_tokens: 1
      })

    before = Enum.map([root, child, leaf, sibling], &ExecutionScope.snapshot/1)
    assert {:ok, encoded} = ExecutionScope.export_tree(root)
    assert encoded["scope_version"] == 2
    assert :ok = ExAgent.Continuation.ScopeLedger.validate(encoded)

    assert {:ok, %{requests: 1, batches: %{"r" => 2}}} =
             ExAgent.Continuation.ScopeLedger.node_position(encoded, "root")

    assert {:ok, %{requests: 0, batches: %{}}} =
             ExAgent.Continuation.ScopeLedger.node_position(encoded, "child")

    assert {:ok, %{requests: 1, batches: %{"l" => 1}}} =
             ExAgent.Continuation.ScopeLedger.node_position(encoded, "leaf")

    # A root-only consumer must continue failing closed.
    assert {:error, :unsupported_continuation_tree} = ExecutionScope.export(root)

    owner = self()

    {r2, c2, l2, s2, _} =
      tree(
        estimate_cost: fn _ ->
          send(owner, :repriced)
          999
        end
      )

    assert :ok = ExecutionScope.restore_tree(r2, Jason.decode!(Jason.encode!(encoded)))
    assert Enum.map([r2, c2, l2, s2], &ExecutionScope.snapshot/1) == before
    refute_receive :repriced
    assert :ok = ExecutionScope.check_reserved_tools(l2, "l")
    assert Enum.map([r2, c2, l2, s2], &ExecutionScope.snapshot/1) == before
    assert {:error, :invalid_scope_checkpoint} = ExecutionScope.restore_tree(r2, encoded)
    assert {:ok, again} = ExecutionScope.export_tree(r2)
    assert again == encoded
  end

  test "tightened root and intermediate budgets apply to restored child reservations" do
    {root, _, leaf, _, model} = tree()
    request(root, model, "r", 1)
    request(leaf, model, "l", 1)
    {:ok, saved} = ExecutionScope.export_tree(root)
    {r2, _, l2, _, _} = tree(usage_limits: %UsageLimits{tool_calls_limit: 1})
    assert :ok = ExecutionScope.restore_tree(r2, saved)

    assert {:error, {:usage_limit_exceeded, :tool_calls, 2}} =
             ExecutionScope.check_reserved_tools(l2, "l")

    {:ok, r3} = ExecutionScope.start("root", model, [])
    on_exit(fn -> ExecutionScope.stop(r3) end)

    {:ok, c3} =
      ExecutionScope.join(r3, "child", model, usage_limits: %UsageLimits{request_limit: 0})

    {:ok, l3} = ExecutionScope.join(c3, "leaf", model, [])
    {:ok, _} = ExecutionScope.join(r3, "sibling", model, [])
    assert :ok = ExecutionScope.restore_tree(r3, saved)

    assert {:error, {:usage_limit_exceeded, :requests, 1}} =
             ExecutionScope.check_reserved_tools(l3, "l")
  end

  test "ledger cannot replace current ancestor permissions" do
    {root, _, leaf, _, model} = tree()
    request(leaf, model, "l", 1)
    {:ok, saved} = ExecutionScope.export_tree(root)
    {r2, _, l2, _, _} = tree(permissions: %Permissions{default: :deny})
    assert :ok = ExecutionScope.restore_tree(r2, saved)
    assert ExecutionScope.decision(l2, "effect") == :deny
  end

  test "corrupt ancestry, counters, duplicate identities and missing ancestor prices reject atomically" do
    {root, _, leaf, _, model} = tree()
    request(leaf, model, "l", 1)
    {:ok, saved} = ExecutionScope.export_tree(root)
    [operation] = saved["operations"]

    corruptions = [
      put_in(saved, ["nodes", "child", "parent_run_id"], "leaf"),
      put_in(saved, ["nodes", "leaf", "parent_run_id"], "missing"),
      put_in(saved, ["nodes", "root", "requests"], 0),
      put_in(saved, ["nodes", "child", "tools"], 0),
      Map.put(saved, "operations", [operation, operation]),
      Map.put(saved, "operations", [
        Map.put(operation, "ancestors", Map.delete(operation["ancestors"], "child"))
      ]),
      Map.put(saved, "batches", saved["batches"] ++ saved["batches"]),
      Map.put(saved, "scope_version", 3)
    ]

    {r2, _, _, _, _} = tree()
    assert {:ok, before} = ExecutionScope.snapshot(r2)

    for data <- corruptions do
      assert {:error, :invalid_scope_checkpoint} = ExAgent.Continuation.ScopeLedger.validate(data)
      assert {:error, :invalid_scope_checkpoint} = ExecutionScope.restore_tree(r2, data)
      assert {:ok, ^before} = ExecutionScope.snapshot(r2)
    end

    assert :ok = ExecutionScope.restore_tree(r2, saved)
  end
end
