defmodule ExAgent.ExecutionScopeSequenceTest do
  use ExUnit.Case, async: true

  alias ExAgent.{Message, Permissions, RunError, Tool, UsageLimits}
  alias ExAgent.Message.{Part, Response, Usage}

  # The oracle is a journal at the fake provider/callable/pricing boundaries,
  # independent of ExecutionScope's storage and accounting implementation.
  defmodule JournalModel do
    @behaviour ExAgent.Model
    defstruct [:journal, :path, :owner, :tag, :parts, wait: false, index: 0]
    def system(_), do: "scope-boundary"
    def model_name(model), do: Enum.join(model.path, "/")

    def request(model, _, _, _) do
      usage = %Usage{
        input_tokens: 1 + Enum.sum(model.path) + model.index,
        output_tokens: length(model.path),
        details: %{observed: %{requests: 1}}
      }

      Agent.update(model.journal, &[{:request, model.path, model.index, usage} | &1])

      if model.wait do
        send(model.owner, {:started, model.tag, model.path, self()})

        receive do
          :release -> :ok
        after
          5_000 -> raise "test provider release barrier timed out"
        end
      end

      parts = if model.index == 0, do: model.parts, else: [%Part.Text{content: "done"}]
      {:ok, %Response{parts: parts, usage: usage}, %{model | index: model.index + 1}}
    end
  end

  defmodule SwapModel do
    use ExAgent.Capability
    defstruct [:model]
    def before_model_request(cap, state), do: %{state | model: cap.model}
  end

  for constraint <- [:requests, :concurrency, :budget] do
    @constraint constraint
    test "seeded nested fanout obeys #{@constraint} before provider invocation" do
      journal = start_supervised!({Agent, fn -> [] end})

      for seed <- [9_109, 91_109] do
        Agent.update(journal, fn _ -> [] end)
        {depth, width, slots} = dimensions(seed)
        spec = tree(depth, width)
        tag = make_ref()
        owner = self()

        {limits, run_opts, admitted} =
          case @constraint do
            :requests ->
              {%UsageLimits{request_limit: depth + slots}, [], slots}

            :concurrency ->
              {nil, [max_concurrent_requests: slots], slots}

            :budget ->
              # While the first leaf is in flight its price is unknown; after
              # completion it exceeds the remaining one-cent allowance.
              prior = Enum.sum(for n <- 1..depth, do: n + 1 + n)
              {%UsageLimits{max_budget_cents: prior + 1}, [], 1}
          end

        opts = [journal: journal, owner: owner, tag: tag, gate: true, wait: true, max_steps: 1]
        agent = %{build(spec, opts) | usage_limits: limits}

        root =
          Task.async(fn ->
            ExAgent.run(agent, "go", run_opts ++ [estimate_cost: price(journal, [1])])
          end)

        ready = for _ <- 1..width, do: receive_ready(tag)
        Enum.each(permute(ready, seed), fn {_, pid} -> send(pid, :launch) end)
        attempts = for _ <- 1..width, do: receive_attempt(tag)
        started = for {:started, path, pid} <- attempts, do: {path, pid}
        rejected = for {:rejected, path, reason} <- attempts, do: {path, reason}
        assert length(started) == admitted
        assert length(rejected) == width - admitted

        for {_, reason} <- rejected do
          case @constraint do
            :requests -> assert reason == {:usage_limit_exceeded, :request_limit, depth + slots}
            :concurrency -> assert reason == {:concurrency_limit_exceeded, slots}
            :budget -> assert reason == :cost_unknown
          end
        end

        Enum.each(Enum.reverse(started), fn {_, pid} -> send(pid, :release) end)
        assert {:error, %RunError{partial: result}} = Task.await(root, 5_000)
        events = Agent.get(journal, & &1)
        requests = requests(events)
        assert length(requests) == depth + admitted
        assert result.request_count == length(requests)
        assert result.tool_calls == depth - 1 + width
        assert result.usage == sum_usage(requests)
        assert result.cost_cents == sum_price(requests)
        assert result.cost_status == :known
        assert result.usage_status == :complete

        assert Enum.sort(for {path, _, _} <- requests, length(path) == depth + 1, do: path) ==
                 Enum.sort(Enum.map(started, &elem(&1, 0)))

        assert_subtotals(events, result)
      end
    end
  end

  test "reordering a generated tree preserves inclusive usage and prices each operation per scope" do
    journal = start_supervised!({Agent, fn -> [] end})

    for seed <- [9_211, 92_211] do
      {depth, width, _} = dimensions(seed)
      spec = tree(depth, width)

      results =
        for reverse? <- [false, true] do
          Agent.update(journal, fn _ -> [] end)
          opts = [journal: journal, reverse: reverse?, own_price: true]

          assert {:ok, result} =
                   ExAgent.run(build(spec, opts), "go", estimate_cost: price(journal, [1]))

          events = Agent.get(journal, & &1)
          assert_subtotals(events, result)

          expected =
            for {path, index, usage} <- requests(events), n <- 1..length(path) do
              {Enum.take(path, n), path, index, usage}
            end

          priced =
            for {:priced, scope, path, index, usage} <- events,
                usage.input_tokens > 0,
                do: {scope, path, index, usage}

          assert Enum.sort(priced) == Enum.sort(expected)
          assert length(Enum.uniq(priced)) == length(priced)

          admission_prices =
            for {:priced, scope, path, index, usage} <- events,
                usage.input_tokens == 0 and usage.output_tokens == 0,
                do: {scope, path, index}

          assert Enum.sort(admission_prices) ==
                   Enum.sort(for {scope, path, index, _} <- expected, do: {scope, path, index})

          assert result.request_count == 2 * depth + width
          {result.usage, result.request_count, result.tool_calls, result.cost_cents}
        end

      assert hd(results) == List.last(results)
    end
  end

  test "seeded three-level authority intersections suppress all asks on deny and require each approver" do
    journal = start_supervised!({Agent, fn -> [] end})

    vectors = [
      [:ask, :allow, :ask],
      [:ask, :deny, :ask],
      [:allow, :ask, :ask],
      [:deny, :ask, :allow]
    ]

    for {actions, seed} <- Enum.zip(vectors, [9_301, 9_302, 9_303, 9_304]) do
      Agent.update(journal, fn _ -> [] end)
      actions = permute(actions, seed)
      spec = tree(2, 3)
      policy_opts = fn path -> authority(journal, path, Enum.at(actions, length(path) - 1)) end
      agent = build(spec, journal: journal, effects: true, node_opts: policy_opts)
      assert {:ok, result} = ExAgent.run(agent, "go", policy_opts.([1]))
      events = Agent.get(journal, & &1)
      effects = for {:effect, path} <- events, do: path
      asks = for {:asked, scope, name} <- events, do: {scope, name}

      if :deny in actions do
        assert effects == []
        assert asks == []
      else
        assert length(effects) == 3
        assert length(Enum.uniq(effects)) == 3

        expected =
          for path <- effects,
              {action, index} <- Enum.with_index(actions, 1),
              action == :ask,
              do: {Enum.take(path, index), "effect"}

        assert Enum.sort(asks) == Enum.sort(expected)
      end

      assert_subtotals(events, result, false)
    end
  end

  test "expired leaf deadlines reject a reordered fanout before model effects" do
    journal = start_supervised!({Agent, fn -> [] end})

    for seed <- [9_401, 9_402] do
      Agent.update(journal, fn _ -> [] end)
      {depth, width, _} = dimensions(seed)
      deadline = System.monotonic_time(:millisecond) - 1
      node_opts = fn path -> if length(path) == depth + 1, do: [deadline: deadline], else: [] end

      agent =
        build(tree(depth, width),
          journal: journal,
          max_steps: 1,
          node_opts: node_opts,
          reverse: rem(seed, 2) == 0
        )

      assert {:error, %RunError{partial: result}} = ExAgent.run(agent, "go")
      events = Agent.get(journal, & &1)
      assert length(requests(events)) == depth
      assert result.request_count == depth

      leaf_results =
        for {:result, path, outcome} <- events, length(path) == depth + 1, do: outcome

      assert length(leaf_results) == width

      assert Enum.all?(
               leaf_results,
               &match?(
                 {:error, %RunError{reason: :deadline_exceeded, partial: %{request_count: 0}}},
                 &1
               )
             )

      assert_subtotals(events, result, false)
    end
  end

  test "a before-request model rewrite must satisfy the ancestor estimator before invocation" do
    journal = start_supervised!({Agent, fn -> [] end})
    original = %JournalModel{journal: journal, path: [1], parts: [%Part.Text{content: "old"}]}
    replacement = %{original | path: [2], parts: [%Part.Text{content: "new"}]}

    agent =
      ExAgent.new(
        model: original,
        usage_limits: %UsageLimits{max_budget_cents: 100},
        capabilities: [%SwapModel{model: replacement}]
      )

    assert {:error, %RunError{reason: :cost_estimator_required, partial: rejected}} =
             ExAgent.run(agent, "go", estimate_cost: fn usage -> usage.input_tokens end)

    assert rejected.request_count == 0
    assert Agent.get(journal, & &1) == []
    assert {:ok, result} = ExAgent.run(agent, "go", estimate_cost: price(journal, [1]))
    events = Agent.get(journal, & &1)
    assert [{[2], 0, usage}] = requests(events)
    assert result.usage == usage
    assert result.cost_cents == 4
    assert result.output == "new"
    assert result.request_count == 1
  end

  defp build(spec, opts) do
    journal = Keyword.fetch!(opts, :journal)
    children = if opts[:reverse], do: Enum.reverse(spec.children), else: spec.children

    tools =
      Enum.map(children, fn child ->
        child_agent = build(child, opts)

        Tool.new(
          name: name(child.path),
          takes_ctx: true,
          parameters_json_schema: %{"type" => "object"},
          call: fn ctx, _ ->
            gated? = opts[:gate] && child.children == []

            if gated? do
              send(opts[:owner], {:ready, opts[:tag], child.path, self()})

              receive do
                :launch -> :ok
              after
                5_000 -> raise "test delegation launch barrier timed out"
              end
            end

            child_opts = if opts[:node_opts], do: opts[:node_opts].(child.path), else: []

            child_opts =
              if opts[:own_price],
                do: Keyword.put(child_opts, :estimate_cost, price(journal, child.path)),
                else: child_opts

            outcome = ExAgent.run_child(ctx, child_agent, "go", child_opts)
            Agent.update(journal, &[{:result, child.path, outcome} | &1])

            if gated? && match?({:error, _}, outcome) do
              {:error, error} = outcome
              send(opts[:owner], {:rejected, opts[:tag], child.path, error.reason})
            end

            case outcome do
              {:ok, result} -> {:ok, result.output}
              error -> error
            end
          end
        )
      end)

    tools =
      if children == [] && opts[:effects] do
        [
          Tool.new(
            name: "effect",
            takes_ctx: false,
            call: fn _ ->
              Agent.update(journal, &[{:effect, spec.path} | &1])
              "recorded"
            end
          )
        ]
      else
        tools
      end

    parts =
      if tools == [],
        do: [%Part.Text{content: "done"}],
        else:
          Enum.map(tools, &%Part.ToolCall{tool_name: &1.name, tool_call_id: &1.name, args: %{}})

    ExAgent.new(
      model: %JournalModel{
        journal: journal,
        path: spec.path,
        owner: opts[:owner],
        tag: opts[:tag],
        parts: parts,
        wait: opts[:wait] == true && children == []
      },
      tools: tools,
      max_steps: opts[:max_steps] || 3
    )
  end

  defp authority(journal, path, action) do
    [
      permissions: Permissions.new!(rules: [{"effect", action}]),
      approve: fn call ->
        Agent.update(journal, &[{:asked, path, call.tool_name} | &1])
        :approve
      end
    ]
  end

  defp price(journal, scope) do
    fn model, usage ->
      Agent.update(journal, &[{:priced, scope, model.path, model.index, usage} | &1])
      usage.input_tokens + usage.output_tokens
    end
  end

  defp assert_subtotals(events, root, priced? \\ true) do
    all = requests(events)

    outcomes = [
      {[1], root} | for({:result, path, outcome} <- events, do: {path, partial(outcome)})
    ]

    for {path, result} <- outcomes do
      included = Enum.filter(all, fn {child, _, _} -> Enum.take(child, length(path)) == path end)
      assert result.request_count == length(included)
      assert result.usage == sum_usage(included)
      if priced?, do: assert(result.cost_cents == sum_price(included))
      if path != [1], do: assert(result.root_run_id == root.run_id)
      calls = for %Part.ToolCall{tool_call_id: id} <- Message.parts(result.messages), do: id
      returns = for %Part.ToolReturn{tool_call_id: id} <- Message.parts(result.messages), do: id
      assert Enum.sort(calls) == Enum.sort(returns)
    end
  end

  defp partial({:ok, result}), do: result
  defp partial({:error, %RunError{partial: result}}), do: result

  defp requests(events),
    do: for({:request, path, index, usage} <- events, do: {path, index, usage})

  defp sum_usage(requests) do
    %Usage{
      input_tokens: Enum.sum(for {_, _, usage} <- requests, do: usage.input_tokens),
      output_tokens: Enum.sum(for {_, _, usage} <- requests, do: usage.output_tokens),
      details: if(requests == [], do: %{}, else: %{observed: %{requests: length(requests)}})
    }
  end

  defp sum_price(requests),
    do: Enum.sum(for {_, _, usage} <- requests, do: usage.input_tokens + usage.output_tokens)

  defp name(path), do: "node_" <> Enum.join(path, "_")
  defp tree(depth, width), do: tree([1], depth, width)

  defp tree(path, 1, width),
    do: %{path: path, children: for(n <- 1..width, do: %{path: path ++ [n], children: []})}

  defp tree(path, depth, width),
    do: %{path: path, children: [tree(path ++ [1], depth - 1, width)]}

  defp dimensions(seed) do
    state = :rand.seed_s(:exsss, {seed, 91, 11})
    {depth, state} = :rand.uniform_s(2, state)
    {width, state} = :rand.uniform_s(3, state)
    {slots, _} = :rand.uniform_s(2, state)
    {depth + 1, width + 2, slots}
  end

  defp permute(items, seed) do
    {ranked, _} =
      Enum.map_reduce(items, :rand.seed_s(:exsss, {seed, 9, 11}), fn item, state ->
        {rank, state} = :rand.uniform_s(state)
        {{rank, item}, state}
      end)

    ranked |> Enum.sort() |> Enum.map(&elem(&1, 1))
  end

  defp receive_ready(tag) do
    receive do
      {:ready, ^tag, path, pid} -> {path, pid}
    after
      2_000 -> flunk("nested fanout did not reach launch barrier")
    end
  end

  defp receive_attempt(tag) do
    receive do
      {:started, ^tag, path, pid} -> {:started, path, pid}
      {:rejected, ^tag, path, reason} -> {:rejected, path, reason}
    after
      2_000 -> flunk("leaf admission did not settle")
    end
  end
end
