defmodule ExAgent.ExecutionScopeTest do
  use ExUnit.Case, async: true

  alias ExAgent.{
    Coordination,
    CostGuard,
    ExecutionScope,
    Message,
    Permissions,
    RunError,
    Tool,
    UsageLimits
  }

  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Models.Test, as: TestModel

  defmodule Controlled do
    @behaviour ExAgent.Model
    defstruct [:owner, label: "controlled", wait: false, input: 7, output: 4, response: nil]
    def model_name(model), do: model.label
    def system(_), do: "test"

    def request(model, _, settings, _) do
      if model.owner,
        do: send(model.owner, {:model_started, model.label, self(), settings.timeout})

      if model.wait,
        do:
          (receive do
             :release -> :ok
           end)

      response =
        model.response ||
          %Response{
            parts: [%Part.Text{content: model.label}],
            usage: %Usage{input_tokens: model.input, output_tokens: model.output}
          }

      {:ok, response, model}
    end
  end

  test "two delegates compete atomically for the final request reservation" do
    owner = self()
    child = ExAgent.new(model: %Controlled{owner: owner, wait: true})
    parent = parent(child, ["a", "b"], usage_limits: %UsageLimits{request_limit: 2})
    task = Task.async(fn -> ExAgent.run(parent, "go") end)
    assert_receive {:model_started, "controlled", child_pid, _}, 1_000
    refute_receive {:model_started, _, _, _}
    send(child_pid, :release)
    assert {:error, %RunError{partial: result}} = Task.await(task)
    assert result.request_count == 2
    assert result.usage.input_tokens == 8
    assert result.usage.output_tokens == 6
    assert Enum.sort(Enum.map(returns(result), & &1.status)) == [:failed, :succeeded]
    refute_receive {:model_started, _, _, _}
  end

  test "parent request_limit one admits no delegated model even when the child raises its limit" do
    child =
      ExAgent.new(
        model: %Controlled{owner: self()},
        usage_limits: %UsageLimits{request_limit: 100}
      )

    agent = parent(child, ["delegate"], usage_limits: %UsageLimits{request_limit: 1})
    assert {:error, %RunError{partial: result}} = ExAgent.run(agent, "go")
    assert result.request_count == 1
    assert result.usage.input_tokens == 1
    refute_receive {:model_started, _, _, _}
  end

  test "atomic batch admission refuses all builders and effects when the batch cannot fit" do
    owner = self()

    builder = fn _, _ ->
      send(owner, :builder)
      ExAgent.new(model: "test")
    end

    agent = parent(builder, ["a", "b"], usage_limits: %UsageLimits{tool_calls_limit: 1})

    assert {:error, %RunError{reason: {:usage_limit_exceeded, :tool_calls, 2}, partial: result}} =
             ExAgent.run(agent, "go")

    refute_receive :builder
    assert Enum.map(returns(result), & &1.status) == [:not_executed, :not_executed]
    assert result.tool_calls == 0
  end

  test "ancestor tool budgets cover the child batch without preventing the last admitted parent tool" do
    owner = self()

    effect =
      tool("effect", fn _ ->
        send(owner, :effect)
        "done"
      end)

    child =
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("effect")]}, "done"]},
        tools: [effect],
        usage_limits: %UsageLimits{tool_calls_limit: 100}
      )

    agent = parent(child, ["delegate"], usage_limits: %UsageLimits{tool_calls_limit: 1})
    assert {:error, %RunError{partial: result}} = ExAgent.run(agent, "go")
    assert result.request_count == 2
    assert result.tool_calls == 1
    refute_receive :effect

    last_step =
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("effect")]}]},
        tools: [effect],
        usage_limits: %UsageLimits{request_limit: 1}
      )

    assert {:error, %RunError{reason: {:usage_limit_exceeded, :request_limit, 1}}} =
             ExAgent.run(last_step, "go")

    assert_receive :effect
  end

  test "allow on a delegated tool does not widen the authority of child operations" do
    owner = self()
    child = effect_child(owner)
    agent = parent(child, ["delegate"])
    policy = Permissions.new!(default: :deny, rules: [{"delegate", :allow}])
    assert {:ok, _} = ExAgent.run(agent, "go", permissions: policy)
    refute_receive :effect
  end

  test "each ancestral ask requires its own approver and child callbacks cannot substitute" do
    owner = self()
    root_policy = Permissions.new!(rules: [{"effect", :ask}])
    child_policy = Permissions.new!(rules: [{"effect", :ask}])

    child_approve = fn _ ->
      send(owner, {:approved, :child})
      :approve
    end

    child = effect_child(owner)
    agent = parent(child, ["delegate"], [], permissions: child_policy, approve: child_approve)

    assert {:ok, _} = ExAgent.run(agent, "go", permissions: root_policy)
    refute_receive :effect
    refute_receive {:approved, :child}

    root_approve = fn call ->
      assert call.tool_name == "effect"
      send(owner, {:approved, :parent})
      :approve
    end

    assert {:ok, _} = ExAgent.run(agent, "go", permissions: root_policy, approve: root_approve)
    assert_receive {:approved, :parent}
    assert_receive {:approved, :child}
    assert_receive :effect
  end

  test "deny wins before any ancestor approval is requested" do
    owner = self()
    root_policy = Permissions.new!(rules: [{"effect", :ask}])
    child_policy = Permissions.new!(rules: [{"effect", :deny}])
    agent = parent(effect_child(owner), ["delegate"], [], permissions: child_policy)

    assert {:ok, _} =
             ExAgent.run(agent, "go",
               permissions: root_policy,
               approve: fn _ ->
                 send(owner, :asked)
                 :approve
               end
             )

    refute_receive :asked
    refute_receive :effect
  end

  test "grandparent usage includes every request once, with explicit tree identities" do
    owner = self()
    leaf = ExAgent.new(model: "test")
    child = parent(leaf, ["leaf"])

    delegate =
      tool(
        "child",
        fn ctx, _ ->
          {:ok, result} =
            ExAgent.run_child(ctx, child, "go", execution_scope: :ignored, run_id: "ignored")

          send(owner, {:child_result, result})
          {:ok, result.output}
        end,
        true
      )

    root =
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("child")]}, "done"]},
        tools: [delegate]
      )

    assert {:ok, result} = ExAgent.run(root, "go")
    assert_receive {:child_result, child_result}
    assert result.request_count == 5
    assert result.usage.input_tokens == 5
    assert result.usage.output_tokens == 5
    assert child_result.request_count == 3
    assert child_result.root_run_id == result.run_id
    assert child_result.parent_run_id == result.run_id
    assert child_result.run_id not in [result.run_id, "ignored"]
  end

  test "failed child retains completed model usage without a second tool contribution" do
    child_model = %TestModel{script: [{:tool_calls, [call("fail")]}]}
    child = ExAgent.new(model: child_model, tools: [tool("fail", fn _ -> {:error, :failed} end)])
    assert {:error, %RunError{partial: result}} = ExAgent.run(parent(child, ["delegate"]), "go")
    assert result.request_count == 2
    assert result.usage.input_tokens == 2
    assert result.usage.output_tokens == 2
    assert [%Part.ToolReturn{usage: nil, status: :failed}] = returns(result)
  end

  test "monetary budgets reject missing, invalid and unknown estimators before model invocation" do
    model = %Controlled{owner: self()}
    agent = ExAgent.new(model: model, usage_limits: %UsageLimits{max_budget_cents: 10})

    for opts <- [
          [],
          [estimate_cost: :invalid],
          [estimate_cost: fn _ -> -1 end],
          [estimate_cost: fn _ -> :unknown end],
          [estimate_cost: fn _ -> raise "bad estimator" end]
        ] do
      assert {:error, %RunError{}} = ExAgent.run(agent, "go", opts)
      refute_receive {:model_started, _, _, _}
    end
  end

  test "legacy pricing cannot silently price a heterogeneous child using the parent rate" do
    child = ExAgent.new(model: %Controlled{owner: self()})
    agent = parent(child, ["delegate"], usage_limits: %UsageLimits{max_budget_cents: 100})

    assert {:error, %RunError{partial: result}} =
             ExAgent.run(agent, "go", estimate_cost: fn usage -> usage.input_tokens end)

    assert result.request_count == 1
    refute_receive {:model_started, _, _, _}

    price = fn model, usage ->
      if ExAgent.Model.model_name(model) == "controlled",
        do: usage.input_tokens * 2,
        else: usage.input_tokens
    end

    assert {:ok, result} = ExAgent.run(agent, "go", estimate_cost: price)
    assert_receive {:model_started, _, _, _}
    assert result.cost_cents == 16
    assert result.cost_status == :known
    assert result.request_count == 3
  end

  test "no estimator leaves cost unknown, not zero, and legacy tool usage is unpriced" do
    assert {:ok, result} = ExAgent.run(ExAgent.new(model: "test"), "go")
    assert result.cost_cents == nil
    assert result.cost_status == :unknown

    costly = tool("external", fn _ -> {:ok, "ok", %Usage{input_tokens: 9, output_tokens: 3}} end)

    agent =
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("external")]}, "done"]},
        tools: [costly]
      )

    assert {:ok, result} =
             ExAgent.run(agent, "go", estimate_cost: fn usage -> usage.input_tokens end)

    assert result.usage.input_tokens == 11
    assert result.cost_cents == nil
  end

  test "request snapshots/final and legacy contributions reconcile by identity" do
    model = %TestModel{}

    {:ok, scope} =
      ExecutionScope.start("root", model,
        estimate_cost: CostGuard.estimator(%{input_per_1k_cents: 1, output_per_1k_cents: 1})
      )

    on_exit(fn -> ExecutionScope.stop(scope) end)
    assert :ok = ExecutionScope.admit_request(scope, "request", model)
    assert :ok = ExecutionScope.record_usage(scope, "request", usage(1, 1))
    assert :ok = ExecutionScope.record_usage(scope, "request", usage(2, 3))
    assert :ok = ExecutionScope.record_usage(scope, "request", usage(5, 8), true)
    assert :ok = ExecutionScope.record_usage(scope, "request", usage(5, 8), true)
    assert :ok = ExecutionScope.finish_request(scope, "request")
    assert {:ok, snapshot} = ExecutionScope.snapshot(scope)
    assert snapshot.request_count == 1
    assert snapshot.usage == usage(5, 8)
    assert_in_delta snapshot.cost_cents, 0.013, 0.0000001

    assert :ok = ExecutionScope.contribute(scope, "tool", usage(3, 4))
    assert :ok = ExecutionScope.contribute(scope, "tool", usage(3, 4))
    assert {:ok, snapshot} = ExecutionScope.snapshot(scope)
    assert snapshot.usage == usage(8, 12)
    assert snapshot.cost_cents == nil
  end

  test "incomplete failed requests retain known usage and do not refund request admission" do
    model = %TestModel{}

    {:ok, scope} =
      ExecutionScope.start("root", model, usage_limits: %UsageLimits{request_limit: 1})

    on_exit(fn -> ExecutionScope.stop(scope) end)
    assert :ok = ExecutionScope.admit_request(scope, "request", model)
    assert :ok = ExecutionScope.record_usage(scope, "request", usage(2, 1))
    assert :ok = ExecutionScope.record_usage(scope, "request", usage(nil, nil))
    assert :ok = ExecutionScope.record_usage(scope, "request", nil, false)
    assert :ok = ExecutionScope.finish_request(scope, "request")
    assert {:ok, snapshot} = ExecutionScope.snapshot(scope)
    assert snapshot.usage == usage(2, 1)
    assert snapshot.usage_status == :partial

    assert {:error, {:usage_limit_exceeded, :request_limit, 1}} =
             ExecutionScope.admit_request(scope, "again", model)
  end

  test "model concurrency is fail-fast and the parent slot is released before delegation" do
    model = %TestModel{}
    {:ok, scope} = ExecutionScope.start("root", model, max_concurrent_requests: 1)
    on_exit(fn -> ExecutionScope.stop(scope) end)
    assert :ok = ExecutionScope.admit_request(scope, "first", model)

    assert {:error, {:concurrency_limit_exceeded, 1}} =
             ExecutionScope.admit_request(scope, "second", model)

    assert :ok = ExecutionScope.finish_request(scope, "first")
    assert :ok = ExecutionScope.admit_request(scope, "second", model)

    assert {:ok, result} =
             ExAgent.run(parent(ExAgent.new(model: "test"), ["delegate"]), "go",
               max_concurrent_requests: 1
             )

    assert result.request_count == 3
  end

  test "local max_steps remains separate from aggregate request limits" do
    agent = parent(ExAgent.new(model: "test"), ["delegate"], max_steps: 1)

    assert {:error, %RunError{reason: {:max_steps_exceeded, 1}, partial: result}} =
             ExAgent.run(agent, "go")

    assert result.run_step == 1
    assert result.request_count == 2
  end

  test "deadlines can only shorten and expired runs make no model invocation" do
    deadline = System.monotonic_time(:millisecond) + 5_000
    model = %TestModel{}
    {:ok, scope} = ExecutionScope.start("root", model, deadline: deadline)
    on_exit(fn -> ExecutionScope.stop(scope) end)
    assert {:ok, child} = ExecutionScope.join(scope, "child", model, deadline: deadline + 50_000)
    assert child.deadline == deadline
    assert ExecutionScope.remaining_timeout(child, 100_000) <= 5_000
    agent = ExAgent.new(model: %Controlled{owner: self()})

    assert {:error, %RunError{reason: :deadline_exceeded}} =
             ExAgent.run(agent, "go", deadline: System.monotonic_time(:millisecond) - 1)

    refute_receive {:model_started, _, _, _}
  end

  test "native counter and concurrency constraints reject before model invocation" do
    for {limits, opts} <- [
          {%UsageLimits{request_limit: -1}, []},
          {%UsageLimits{tool_calls_limit: 1.5}, []},
          {%UsageLimits{max_budget_cents: -0.1}, []},
          {nil, [max_concurrent_requests: 0]},
          {nil, [deadline: "later"]}
        ] do
      agent = ExAgent.new(model: %Controlled{owner: self()}, usage_limits: limits)
      assert {:error, %RunError{}} = ExAgent.run(agent, "go", opts)
      refute_receive {:model_started, _, _, _}
    end
  end

  test "fractional cent pricing preserves small operations and uses cents per thousand" do
    estimator = CostGuard.estimator(%{input_per_1k_cents: 250, output_per_1k_cents: 1000})
    assert estimator.(usage(1000, 0)) == 250
    assert estimator.(usage(1, 0)) == 0.25

    assert_in_delta Enum.sum(Enum.map(1..1000, fn _ -> estimator.(usage(1, 0)) end)),
                    250,
                    0.0000001

    assert CostGuard.estimator(%{}).(usage(1, 1)) == :unknown
    assert_raise ArgumentError, fn -> CostGuard.estimator(%{input_per_1k_cents: -1}) end
  end

  test "owner death closes the scope and cancels a blocked delegated model" do
    {run, scope, child} = blocked_tree(self())
    scope_monitor = Process.monitor(scope.pid)
    child_monitor = Process.monitor(child)
    Process.exit(run, :kill)
    assert_receive {:DOWN, ^scope_monitor, :process, _, _}, 1_000
    assert_receive {:DOWN, ^child_monitor, :process, _, _}, 1_000
  end

  test "scope loss cancels delegated work and the root returns a partial error" do
    {run, scope, child} = blocked_tree(self())
    child_monitor = Process.monitor(child)
    run_monitor = Process.monitor(run)
    Process.exit(scope.pid, :kill)
    assert_receive {:DOWN, ^child_monitor, :process, _, _}, 1_000
    assert_receive {:root_result, {:error, %RunError{}}}, 1_000
    assert_receive {:DOWN, ^run_monitor, :process, ^run, :normal}, 1_000
  end

  test "successful and failed root executions retire their ephemeral scopes" do
    owner = self()

    for fail? <- [false, true] do
      capture =
        tool(
          "capture",
          fn ctx, _ ->
            send(owner, {:scope, ctx.execution_scope})
            if fail?, do: {:error, :stop}, else: "ok"
          end,
          true
        )

      agent =
        ExAgent.new(
          model: %TestModel{script: [{:tool_calls, [call("capture")]}, "done"]},
          tools: [capture]
        )

      ExAgent.run(agent, "go")
      assert_receive {:scope, scope}
      refute Process.alive?(scope.pid)
      assert {:error, :execution_scope_closed} = ExecutionScope.check(scope)
    end
  end

  defp blocked_tree(owner) do
    child = ExAgent.new(model: %Controlled{owner: owner, wait: true})

    builder = fn ctx, _ ->
      send(owner, {:scope, ctx.execution_scope})
      child
    end

    agent = parent(builder, ["delegate"])
    run = spawn(fn -> send(owner, {:root_result, ExAgent.run(agent, "go")}) end)
    assert_receive {:scope, scope}, 1_000
    assert_receive {:model_started, _, child_pid, _}, 1_000
    {run, scope, child_pid}
  end

  defp effect_child(owner),
    do:
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("effect")]}, "done"]},
        tools: [
          tool("effect", fn _ ->
            send(owner, :effect)
            "done"
          end)
        ]
      )

  defp parent(child, names, agent_opts \\ [], child_opts \\ []) do
    tools = Enum.map(names, &Coordination.delegation_tool(child, [name: &1] ++ child_opts))

    model = %TestModel{
      script: [{:tool_calls, Enum.map(names, &call(&1, %{"prompt" => "child"}))}, "done"]
    }

    ExAgent.new([model: model, tools: tools] ++ agent_opts)
  end

  defp call(name, args \\ %{}), do: %Part.ToolCall{tool_name: name, args: args}

  defp tool(name, callback, ctx? \\ false),
    do:
      Tool.new(
        name: name,
        takes_ctx: ctx?,
        parameters_json_schema: %{"type" => "object"},
        call: callback
      )

  defp returns(result),
    do: Enum.filter(Message.parts(result.messages), &match?(%Part.ToolReturn{}, &1))

  defp usage(input, output), do: %Usage{input_tokens: input, output_tokens: output}
end
