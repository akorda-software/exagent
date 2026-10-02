defmodule ExAgent.StructuralScopeTest do
  use ExUnit.Case, async: true

  alias ExAgent.{ExecutionScope, Permissions, UsageLimits}
  alias ExAgent.Continuation.ScopeLedger
  alias ExAgent.Message.{Part, Response, Usage}

  defmodule Leaf do
    @behaviour ExAgent.Model
    defstruct [:owner, :label]
    def system(_), do: "structural-scope-test"
    def model_name(model), do: model.label

    def request(model, _, _, _) do
      send(model.owner, {:request, model.label})

      {:ok,
       %Response{
         parts: [%Part.Text{content: model.label}],
         usage: %Usage{input_tokens: 2, output_tokens: 3}
       }, model}
    end
  end

  defp root(opts \\ []) do
    assert {:ok, scope} = ExecutionScope.start_structural("sequence", opts)
    on_exit(fn -> ExecutionScope.stop(scope) end)
    scope
  end

  defp request(scope, model, id) do
    assert :ok = ExecutionScope.admit_request(scope, id, model)

    assert :ok =
             ExecutionScope.record_usage(
               scope,
               id,
               %Usage{input_tokens: 2, output_tokens: 3},
               true
             )

    assert :ok = ExecutionScope.finish_request(scope, id)
    assert :ok = ExecutionScope.admit_tools(scope, id, 1)
  end

  test "empty adhesion cleanup cannot remove a different parent, descendant or operation" do
    scope = root()
    model = %Leaf{owner: self(), label: "A"}
    assert {:ok, leaf} = ExecutionScope.join(scope, "leaf", model, [])
    assert {:ok, other} = ExecutionScope.join(scope, "other", model, [])
    assert {:error, :scope_child_not_empty} = ExecutionScope.discard_empty_child(other, leaf)
    assert {:ok, child} = ExecutionScope.join(leaf, "child", model, [])
    assert {:error, :scope_child_not_empty} = ExecutionScope.discard_empty_child(scope, leaf)
    assert :ok = ExecutionScope.discard_empty_child(leaf, child)
    assert :ok = ExecutionScope.discard_empty_child(scope, leaf)
    request(other, model, "request")
    assert {:ok, before} = ExecutionScope.export_tree(scope)
    assert {:error, :scope_child_not_empty} = ExecutionScope.discard_empty_child(scope, other)
    assert {:ok, ^before} = ExecutionScope.export_tree(scope)
  end

  test "structural root executes two original leaf loops without a root request or history" do
    scope = root(usage_limits: %UsageLimits{request_limit: 2})
    parent = %{execution_scope: scope, run_id: scope.run_id}

    results =
      for label <- ["A", "B"] do
        agent = ExAgent.new(model: %Leaf{owner: self(), label: label})
        assert {:ok, result} = ExAgent.run_child(parent, agent, "input")
        assert result.output == label
        assert result.parent_run_id == "sequence"
        assert_receive {:request, ^label}
        result
      end

    assert {:ok, total} = ExecutionScope.snapshot(scope)
    assert total.request_count == 2
    assert total.usage.input_tokens == 4
    assert total.usage.output_tokens == 6
    assert Enum.all?(results, &(&1.request_count == 1))
    assert {:ok, data} = ExecutionScope.export_tree(scope)
    assert :ok = ScopeLedger.validate(data)
    assert {:ok, %{requests: 0, batches: %{}}} = ScopeLedger.node_position(data, "sequence")
    assert length(data["operations"]) == 2
    assert Enum.all?(data["operations"], &(&1["run_id"] != "sequence"))

    agent = ExAgent.new(model: %Leaf{owner: self(), label: "C"})
    assert {:error, %ExAgent.RunError{}} = ExAgent.run_child(parent, agent, "blocked")
    refute_receive {:request, "C"}
  end

  test "root rejects all own effect admissions before model or estimator callbacks" do
    scope = root(estimate_cost: fn _, _ -> flunk("root must not price an effect") end)
    assert {:error, :structural_scope_effect} = ExecutionScope.check_request(scope)

    assert {:error, :structural_scope_effect} =
             ExecutionScope.admit_request(scope, "fake", :not_a_model)

    assert {:error, :structural_scope_effect} = ExecutionScope.admit_tools(scope, "fake", 1)

    assert {:error, :structural_scope_effect} =
             ExecutionScope.admit_retry_tool(scope, "retry", "fake")

    assert {:error, :structural_scope_effect} =
             ExecutionScope.contribute(scope, {"fake", "call"}, %Usage{
               input_tokens: 1,
               output_tokens: 0
             })

    assert {:ok, data} = ExecutionScope.export_tree(scope)
    assert data["operations"] == []
    assert data["batches"] == []
    assert data["retry_batches"] == []
    assert :ok = ExecutionScope.check(scope)
  end

  test "JSON restore preserves one ledger and historical ancestor prices without callbacks" do
    scope = root(estimate_cost: fn _, _ -> 7 end)
    model = %Leaf{owner: self(), label: "A"}
    assert {:ok, leaf} = ExecutionScope.join(scope, "A", model, estimate_cost: fn _ -> 3 end)
    request(leaf, model, "request-A")
    assert {:ok, before} = ExecutionScope.snapshot(scope)
    assert {:ok, saved} = ExecutionScope.export_tree(scope)
    bytes = Jason.encode!(saved)
    ExecutionScope.stop(scope)

    restored =
      root(estimate_cost: fn _, _ -> flunk("historical price must not be recomputed") end)

    assert {:ok, leaf2} = ExecutionScope.join(restored, "A", model, estimate_cost: fn _ -> 99 end)
    assert :ok = ExecutionScope.restore_tree(restored, Jason.decode!(bytes))
    assert {:ok, ^before} = ExecutionScope.snapshot(restored)
    assert :ok = ExecutionScope.check_reserved_tools(leaf2, "request-A")
    assert {:ok, ^saved} = ExecutionScope.export_tree(restored)
    assert {:error, :invalid_scope_checkpoint} = ExecutionScope.restore_tree(restored, saved)
  end

  test "structural restore rejects a coherent legacy root operation atomically" do
    model = %Leaf{owner: self(), label: "legacy"}
    assert {:ok, legacy} = ExecutionScope.start("sequence", model, [])
    on_exit(fn -> ExecutionScope.stop(legacy) end)
    request(legacy, model, "root-request")
    assert {:ok, data} = ExecutionScope.export_tree(legacy)
    assert :ok = ScopeLedger.validate(data)
    scope = root()
    assert {:ok, before} = ExecutionScope.snapshot(scope)
    assert {:error, :invalid_scope_checkpoint} = ExecutionScope.restore_tree(scope, data)
    assert {:ok, ^before} = ExecutionScope.snapshot(scope)
    assert {:ok, local} = ExecutionScope.export(legacy)
    assert {:error, :invalid_scope_checkpoint} = ExecutionScope.restore(scope, local)
    assert {:error, :unsupported_continuation_tree} = ExecutionScope.export(scope)
  end

  test "current ancestor authority and deadline remain effective for leaves" do
    scope = root(permissions: %Permissions{default: :deny})
    model = %Leaf{owner: self(), label: "A"}

    assert {:ok, child} =
             ExecutionScope.join(scope, "A", model, permissions: %Permissions{default: :allow})

    assert ExecutionScope.decision(child, "effect") == :deny
    expired = root(deadline: System.monotonic_time(:millisecond) - 1)
    assert {:error, _} = ExecutionScope.join(expired, "A", model, [])
  end

  test "model-less root rejects model-specific unary pricing rather than inventing identity" do
    assert {:error, :structural_scope_requires_model_aware_estimator} =
             ExecutionScope.start_structural("sequence", estimate_cost: fn _ -> 1 end)
  end

  test "competing leaves share the last ancestor slot with a barrier and no synthetic debit" do
    scope = root(usage_limits: %UsageLimits{request_limit: 1})
    owner = self()

    tasks =
      for label <- ["A", "B"] do
        Task.async(fn ->
          model = %Leaf{owner: owner, label: label}
          {:ok, leaf} = ExecutionScope.join(scope, label, model, [])
          send(owner, {:ready, self()})

          receive do
            :admit -> ExecutionScope.admit_request(leaf, label, model)
          end
        end)
      end

    for _ <- tasks do
      assert_receive {:ready, _}, 1_000
    end

    for task <- tasks, do: send(task.pid, :admit)
    replies = Enum.map(tasks, &Task.await/1)
    assert Enum.count(replies, &(&1 == :ok)) == 1

    assert Enum.count(replies, &match?({:error, {:usage_limit_exceeded, :request_limit, 1}}, &1)) ==
             1

    assert {:ok, total} = ExecutionScope.snapshot(scope)
    assert total.request_count == 1
  end

  test "restored aggregate is checked against current restrictions before new leaf admission" do
    scope = root()
    model = %Leaf{owner: self(), label: "A"}
    assert {:ok, leaf} = ExecutionScope.join(scope, "A", model, [])
    request(leaf, model, "request-A")
    assert {:ok, data} = ExecutionScope.export_tree(scope)

    restored =
      root(
        usage_limits: %UsageLimits{request_limit: 1},
        permissions: %Permissions{default: :deny}
      )

    assert {:ok, leaf2} = ExecutionScope.join(restored, "A", model, [])
    assert :ok = ExecutionScope.restore_tree(restored, data)
    assert :deny = ExecutionScope.decision(leaf2, "effect")
    assert {:ok, next} = ExecutionScope.join(restored, "B", model, [])

    assert {:error, {:usage_limit_exceeded, :request_limit, 1}} =
             ExecutionScope.admit_request(next, "request-B", model)

    assert {:ok, after_rejection} = ExecutionScope.export_tree(restored)
    assert after_rejection["operations"] == data["operations"]
  end
end
