defmodule ExAgent.ToolSearchTest do
  use ExUnit.Case, async: true

  alias ExAgent.Message.{Part, Request}
  alias ExAgent.Models.Test
  alias ExAgent.Tool
  alias ExAgent.Tool.Search

  defp tool(name, description) do
    owner = self()

    Tool.new(
      name: name,
      description: description,
      parameters_json_schema: %{type: "object"},
      call: fn _ctx, _args ->
        send(owner, {:called, name})
        "#{name} ok"
      end
    )
  end

  defp catalogue do
    [
      tool("read_file", "Read a text file from the workspace."),
      tool("write_file", "Write text to a file in the workspace."),
      tool("list_issues", "List open issues in the tracker."),
      tool("create_invoice", "Create a customer invoice."),
      tool("sendEmail", "Send an email message to a contact.")
    ]
  end

  defp call(name, id, args \\ %{}),
    do: %Part.ToolCall{tool_name: name, tool_call_id: id, args: args}

  # Each model call reports the tool names it was offered.
  defp spy(script) do
    owner = self()

    %Test{
      script:
        Enum.map(script, fn item ->
          fn _messages, params ->
            send(owner, {:offered, Enum.map(params.function_tools, & &1.name)})
            item
          end
        end)
    }
  end

  defp offered(acc \\ []) do
    receive do
      {:offered, names} -> offered([names | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "deferred tools are offered only after a search finds them" do
    search = Search.new(deferred: catalogue(), max_results: 2)
    lookup = tool("lookup_order", "Look up an order.")

    script = [
      {:tool_calls, [call("search_tools", "s1", %{"query" => "write files"})]},
      {:tool_calls, [call("write_file", "w1")]},
      {:tool_calls, [call("search_tools", "s2", %{"query" => "send email"})]},
      "done"
    ]

    agent =
      ExAgent.new(
        model: spy(script),
        tools: [lookup | Search.tools(search)],
        capabilities: [search]
      )

    assert {:ok, %{output: "done", messages: messages}} = ExAgent.run(agent, "save notes")
    assert_receive {:called, "write_file"}

    assert [
             ["lookup_order", "search_tools"],
             ["lookup_order", "search_tools", "write_file", "read_file"],
             ["lookup_order", "search_tools", "write_file", "read_file"],
             ["lookup_order", "search_tools", "write_file", "read_file", "sendEmail"]
           ] = offered()

    [first | _] =
      for %Request{parts: parts} <- messages,
          %Part.ToolReturn{tool_name: "search_tools"} = p <- parts,
          do: p

    assert [%{"name" => "write_file"}, %{"name" => "read_file"}] = first.content["tools"]

    # Loaded tools come from the history, so a later run keeps them.
    again =
      ExAgent.new(
        model: spy(["ok"]),
        tools: [lookup | Search.tools(search)],
        capabilities: [search]
      )

    assert {:ok, _} = ExAgent.run(again, "more", message_history: messages)
    assert [["lookup_order", "search_tools", "write_file", "read_file", "sendEmail"]] = offered()
  end

  test "tools load even when another capability rewrites the search result" do
    long = String.duplicate("Create a customer invoice with lines, taxes and due date. ", 8)
    invoices = tool("create_invoice", long)
    others = Enum.reject(catalogue(), &(&1.name == "create_invoice"))
    search = Search.new(deferred: [invoices | others], max_results: 2)
    limit = ExAgent.Tool.OutputLimit.new(max_bytes: 256)

    script = [
      {:tool_calls, [call("search_tools", "s1", %{"query" => "invoice for a customer"})]},
      {:tool_calls, [call("create_invoice", "c1")]},
      "done"
    ]

    agent =
      ExAgent.new(model: spy(script), tools: Search.tools(search), capabilities: [search, limit])

    assert {:ok, %{output: "done", messages: messages}} = ExAgent.run(agent, "bill them")

    assert [%Part.ToolReturn{content: shortened} | _] =
             for(%Request{parts: p} <- messages, %Part.ToolReturn{} = r <- p, do: r)

    assert is_binary(shortened)
    assert_receive {:called, "create_invoice"}
    assert [["search_tools"], ["search_tools", "create_invoice"], _] = offered()
  end

  test "an unloaded deferred tool cannot be called" do
    search = Search.new(deferred: catalogue())
    script = [{:tool_calls, [call("create_invoice", "c1")]}, "gave up"]

    agent =
      ExAgent.new(
        model: %Test{script: script},
        tools: Search.tools(search),
        capabilities: [search],
        tool_retries: 1
      )

    _ = ExAgent.run(agent, "bill them")
    refute_receive {:called, "create_invoice"}
  end

  test "ranking uses names, descriptions, exact names and plural folding" do
    search = Search.new(deferred: catalogue(), max_results: 3)
    run = fn query -> search.tool.call.(%{"query" => query}) end

    assert %{"tools" => [%{"name" => "list_issues"} | _]} = run.("issue")
    assert %{"tools" => [%{"name" => "create_invoice"}]} = run.("invoices for a customer")
    assert %{"tools" => [%{"name" => "sendEmail"}]} = run.("email")
    assert %{"tools" => [%{"name" => "read_file"}]} = run.("read_file")

    assert %{"tools" => [%{"name" => "read_file"}, %{"name" => "sendEmail"}]} =
             run.("sendEmail, read_file")

    assert %{"tools" => [], "message" => message} = run.("weather forecast")
    assert message =~ "read_file, write_file, list_issues, create_invoice, sendEmail"
  end

  test "invalid options are rejected" do
    [one | _] = catalogue()

    for opts <- [
          [deferred: []],
          [deferred: [one, one]],
          [deferred: [one], name: "read_file"],
          [deferred: [one], max_results: 0],
          [deferred: [%Tool{name: "o", kind: :output}]]
        ] do
      assert_raise ArgumentError, fn -> Search.new(opts) end
    end
  end
end
