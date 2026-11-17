defmodule ExAgent.ToolOutputLimitTest do
  use ExUnit.Case, async: true

  alias ExAgent.Message.{Part, Request}
  alias ExAgent.Tool
  alias ExAgent.Tool.OutputLimit

  defp tool(name, result) do
    Tool.new(
      name: name,
      parameters_json_schema: %{type: "object"},
      takes_ctx: false,
      call: fn _ -> result end
    )
  end

  defp run(tools, calls, limit) do
    script = [
      {:tool_calls, Enum.map(calls, &%Part.ToolCall{tool_name: &1, tool_call_id: &1, args: %{}})},
      "done"
    ]

    agent =
      ExAgent.new(
        model: %ExAgent.Models.Test{script: script},
        tools: tools,
        capabilities: [limit]
      )

    assert {:ok, %{output: "done", messages: messages}} = ExAgent.run(agent, "go")

    for %Request{parts: parts} <- messages,
        %Part.ToolReturn{} = p <- parts,
        into: %{},
        do: {p.tool_name, p}
  end

  test "large text keeps its beginning and end with a notice, within max_bytes" do
    big = "BEGIN " <> String.duplicate("x", 5_000) <> " END"

    returns =
      run(
        [tool("log", big), tool("small", "ok")],
        ["log", "small"],
        OutputLimit.new(max_bytes: 1_000)
      )

    content = returns["log"].content
    assert returns["log"].status == :succeeded
    assert byte_size(content) <= 1_000
    assert String.starts_with?(content, "BEGIN ")
    assert String.ends_with?(content, " END")

    assert content =~
             ~r/\[\.\.\. \d+ of #{byte_size(big)} bytes omitted from this tool result\. \.\.\.\]/

    assert returns["small"].content == "ok"
  end

  test "multibyte text is cut on character boundaries" do
    big = String.duplicate("ñ€😀", 2_000)

    for keep <- [:head_tail, :head, :tail], max <- [256, 301, 777] do
      out = OutputLimit.shorten(big, OutputLimit.new(max_bytes: max, keep: keep))
      assert String.valid?(out) and byte_size(out) <= max, inspect({keep, max})
    end
  end

  test "structured results are limited as their JSON encoding" do
    rows = for i <- 1..500, do: %{"id" => i, "name" => "row #{i}"}
    returns = run([tool("query", rows)], ["query"], OutputLimit.new(max_bytes: 600, keep: :head))

    content = returns["query"].content
    assert is_binary(content) and byte_size(content) <= 600
    assert String.starts_with?(content, ~s([{"id":1,))
  end

  test "on_truncate receives the full result and its hint reaches the model" do
    owner = self()
    big = String.duplicate("line\n", 1_000)

    limit =
      OutputLimit.new(
        max_bytes: 512,
        on_truncate: fn info ->
          send(owner, {:full, info})
          "Full output stored as out-1; call read_output to page through it."
        end
      )

    returns = run([tool("cmd", big)], ["cmd"], limit)
    assert_receive {:full, %{tool_name: "cmd", tool_call_id: "cmd", content: ^big, bytes: 5_000}}
    assert returns["cmd"].content =~ "Full output stored as out-1"
    assert byte_size(returns["cmd"].content) <= 512
  end

  test "a long on_truncate hint is cut so the result still fits" do
    limit = OutputLimit.new(max_bytes: 256, on_truncate: fn _ -> String.duplicate("é", 400) end)
    returns = run([tool("big", String.duplicate("a", 10_000))], ["big"], limit)
    content = returns["big"].content
    assert byte_size(content) <= 256 and String.valid?(content)
    assert content =~ "bytes omitted"
  end

  test "only selected tools and successful results are limited" do
    big = String.duplicate("y", 2_000)
    limit = OutputLimit.new(max_bytes: 300, tools: ["limited"])
    returns = run([tool("limited", big), tool("free", big)], ["limited", "free"], limit)

    assert byte_size(returns["limited"].content) <= 300
    assert returns["free"].content == big

    failed = %Part.ToolReturn{tool_name: "x", tool_call_id: "x", status: :failed, content: big}

    assert {:ok, ^failed} =
             OutputLimit.after_tool_execute(
               OutputLimit.new(max_bytes: 300),
               %{},
               failed,
               {:ok, failed}
             )

    assert {:error, :e} =
             OutputLimit.after_tool_execute(OutputLimit.new(), %{}, failed, {:error, :e})
  end

  test "invalid options are rejected" do
    for opts <- [[max_bytes: 10], [keep: :middle], [tools: [:atom]], [on_truncate: fn -> nil end]] do
      assert_raise ArgumentError, fn -> OutputLimit.new(opts) end
    end
  end
end
