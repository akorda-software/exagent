defmodule ExAgent.ToolExecutionControlsTest do
  use ExUnit.Case, async: true

  alias ExAgent.Message.{Part, Request}
  alias ExAgent.Tool

  # Each call records how many calls were running when it started and ended.
  defp tool(name, opts) do
    owner = self()
    active = Keyword.fetch!(opts, :active)
    sleep = Keyword.get(opts, :sleep, 60)

    Tool.new(
      [
        name: name,
        parameters_json_schema: %{type: "object"},
        takes_ctx: false,
        call: fn args ->
          running = :atomics.add_get(active, 1, 1)
          send(owner, {:started, name, args["n"], running})
          Process.sleep(sleep)
          send(owner, {:finished, name, args["n"], :atomics.get(active, 1)})
          :atomics.sub(active, 1, 1)
          "#{name}-#{args["n"]}"
        end
      ] ++ Keyword.drop(opts, [:active, :sleep])
    )
  end

  defp call(name, n),
    do: %Part.ToolCall{tool_name: name, tool_call_id: "#{name}#{n}", args: %{"n" => n}}

  defp returns(messages) do
    for %Request{parts: parts} <- messages,
        %Part.ToolReturn{} = part <- parts,
        do: {part.tool_call_id, part.status, part.content}
  end

  defp events(acc \\ []) do
    receive do
      {kind, name, n, running} when kind in [:started, :finished] ->
        events([{kind, "#{name}#{n}", running} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "an exclusive call runs alone while parallel calls around it overlap" do
    active = :atomics.new(1, [])
    read = tool("read", active: active)
    write = tool("write", active: active, concurrency: :exclusive)

    script = [
      {:tool_calls,
       [call("read", 1), call("read", 2), call("write", 3), call("read", 4), call("read", 5)]},
      "done"
    ]

    agent = ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: [read, write])
    assert {:ok, %{output: "done", messages: messages}} = ExAgent.run(agent, "go")

    # The model sees results in its own call order.
    assert Enum.map(returns(messages), &elem(&1, 0)) == ~w(read1 read2 write3 read4 read5)

    order = events()
    index = fn event -> Enum.find_index(order, &match?(^event, Tuple.delete_at(&1, 2))) end

    # Both groups of reads overlap; the write starts after read1/read2 finished
    # and finishes before read4/read5 start.
    for id <- ~w(read1 read2), do: assert(index.({:finished, id}) < index.({:started, "write3"}))
    for id <- ~w(read4 read5), do: assert(index.({:finished, "write3"}) < index.({:started, id}))
    assert Enum.find(order, &match?({:started, "write3", _}, &1)) == {:started, "write3", 1}
    assert Enum.find(order, &match?({:finished, "write3", _}, &1)) == {:finished, "write3", 1}

    assert Enum.any?(order, fn
             {:finished, id, 2} when id in ["read1", "read2"] -> true
             _ -> false
           end)
  end

  test "a per-tool timeout kills only that tool's call" do
    active = :atomics.new(1, [])
    fast = tool("fast", active: active, sleep: 10)
    slow = tool("slow", active: active, sleep: 5_000, timeout: 50)

    script = [{:tool_calls, [call("fast", 1), call("slow", 2)]}, "recovered"]

    agent =
      ExAgent.new(
        model: %ExAgent.Models.Test{script: script},
        tools: [fast, slow],
        tool_timeout: 10_000
      )

    {elapsed, result} = :timer.tc(fn -> ExAgent.run(agent, "go") end, :millisecond)

    assert {:error, %ExAgent.RunError{partial: %{messages: messages}}} = result
    assert elapsed < 2_000

    assert [{"fast1", :succeeded, "fast-1"}, {"slow2", :unknown, _}] = returns(messages)
  end

  test "a per-tool timeout may extend the agent default" do
    active = :atomics.new(1, [])
    patient = tool("patient", active: active, sleep: 150, timeout: 2_000)

    agent =
      ExAgent.new(
        model: %ExAgent.Models.Test{script: [{:tool_calls, [call("patient", 1)]}, "done"]},
        tools: [patient],
        tool_timeout: 50
      )

    assert {:ok, %{output: "done", messages: messages}} = ExAgent.run(agent, "go")
    assert [{"patient1", :succeeded, "patient-1"}] = returns(messages)
  end

  test "parallel calls with different timeouts still run together" do
    active = :atomics.new(1, [])
    docs = tool("docs", active: active, sleep: 150, timeout: 2_000)
    other = tool("other", active: active, sleep: 150)

    script = [
      {:tool_calls, [call("docs", 1), call("other", 2), call("docs", 3), call("other", 4)]},
      "done"
    ]

    agent = ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: [docs, other])

    {elapsed, {:ok, %{messages: messages}}} =
      :timer.tc(fn -> ExAgent.run(agent, "go") end, :millisecond)

    assert elapsed < 450
    assert Enum.any?(events(), &match?({:finished, _, 4}, &1))
    assert Enum.map(returns(messages), &elem(&1, 0)) == ~w(docs1 other2 docs3 other4)
  end

  test "in a mixed group only the call past its own timeout is killed" do
    active = :atomics.new(1, [])
    slow = tool("slow", active: active, sleep: 5_000, timeout: 60)
    patient = tool("patient", active: active, sleep: 200, timeout: 2_000)
    script = [{:tool_calls, [call("slow", 1), call("patient", 2)]}, "recovered"]

    agent = ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: [slow, patient])
    {elapsed, result} = :timer.tc(fn -> ExAgent.run(agent, "go") end, :millisecond)

    assert {:error, %ExAgent.RunError{partial: %{messages: messages}}} = result
    assert elapsed < 2_000
    assert [{"slow1", :unknown, _}, {"patient2", :succeeded, "patient-2"}] = returns(messages)
  end

  test "a grouped call that traps exits is still stopped at its own timeout" do
    trap =
      Tool.new(
        name: "trap",
        parameters_json_schema: %{type: "object"},
        takes_ctx: false,
        timeout: 100,
        call: fn _ ->
          Process.flag(:trap_exit, true)
          Process.sleep(1_500)
          "trap-done"
        end
      )

    active = :atomics.new(1, [])
    patient = tool("patient", active: active, sleep: 50, timeout: 3_000)
    script = [{:tool_calls, [call("trap", 1), call("patient", 2)]}, "recovered"]

    agent = ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: [trap, patient])
    {elapsed, result} = :timer.tc(fn -> ExAgent.run(agent, "go") end, :millisecond)

    assert {:error,
            %ExAgent.RunError{
              reason: {:tool_execution_failed, "trap", {:exit, :timeout}},
              partial: %{messages: messages}
            }} = result

    assert elapsed < 1_000
    assert [{"trap1", :unknown, _}, {"patient2", :succeeded, "patient-2"}] = returns(messages)
  end

  test "default tools keep one concurrent batch" do
    active = :atomics.new(1, [])
    read = tool("read", active: active, sleep: 100)

    script = [{:tool_calls, Enum.map(1..4, &call("read", &1))}, "done"]
    agent = ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: [read])

    {elapsed, {:ok, _}} = :timer.tc(fn -> ExAgent.run(agent, "go") end, :millisecond)
    assert elapsed < 350
    assert Enum.any?(events(), &match?({:finished, _, 4}, &1))
  end

  test "invalid execution controls are rejected when the tool or agent is built" do
    base = [name: "t", parameters_json_schema: %{type: "object"}, call: fn _, _ -> :ok end]

    for bad <- [[timeout: 0], [timeout: :infinity], [concurrency: :serial]] do
      assert_raise ArgumentError, fn -> Tool.new(base ++ bad) end

      assert_raise ArgumentError, fn ->
        ExAgent.new(model: "test", tools: [struct!(Tool, base ++ bad)])
      end
    end
  end

  test "execution controls do not change the definition sent to the model" do
    base = [name: "t", parameters_json_schema: %{type: "object"}, call: fn _, _ -> :ok end]

    assert Tool.definition(Tool.new(base)) ==
             Tool.definition(Tool.new(base ++ [timeout: 10, concurrency: :exclusive]))
  end
end
