defmodule ExAgent.ToolRepeatGuardTest do
  use ExUnit.Case, async: true

  alias ExAgent.Message.{Part, Request}
  alias ExAgent.Models.Test
  alias ExAgent.Tool
  alias ExAgent.Tool.RepeatGuard

  defp search do
    Tool.new(
      name: "search",
      parameters_json_schema: %{type: "object", properties: %{q: %{type: "string"}}},
      takes_ctx: false,
      call: fn %{"q" => q} -> "no results for #{q}" end
    )
  end

  defp search(q, id),
    do: {:tool_calls, [%Part.ToolCall{tool_name: "search", tool_call_id: id, args: %{"q" => q}}]}

  # Records the last request message of every model call.
  defp spy(script) do
    owner = self()

    %Test{
      script:
        Enum.map(script, fn item ->
          fn messages, _params ->
            send(owner, {:request, messages})
            item
          end
        end)
    }
  end

  defp requests do
    receive do
      {:request, messages} -> [messages | requests()]
    after
      0 -> []
    end
  end

  defp note(%Request{parts: [%Part.User{content: "Runtime note" <> _ = note}]}), do: note
  defp note(_message), do: nil

  defp notes(requests \\ requests()), do: Enum.map(requests, &note(List.last(&1)))

  test "the model is told about a repeated identical call from the threshold on" do
    script = [
      search("x", "1"),
      search("x", "2"),
      search("y", "3"),
      search("x", "4"),
      search("x", "5"),
      search("y", "6"),
      "done"
    ]

    agent = ExAgent.new(model: spy(script), tools: [search()], capabilities: [RepeatGuard.new()])
    assert {:ok, %{output: "done", messages: messages}} = ExAgent.run(agent, "find it")

    # Requests 1..7: a note follows the third and fourth identical call only,
    # never a different call.
    requests = requests()
    assert [nil, nil, nil, nil, n4, n5, nil] = notes(requests)
    assert n4 =~ "`search` 3 times"
    assert n5 =~ "`search` 4 times"

    # Earlier notes stay in place, so each request extends the previous one.
    parts = fn messages -> Enum.map(messages, & &1.parts) end

    for [previous, next] <- Enum.chunk_every(requests, 2, 1, :discard),
        do: assert(List.starts_with?(parts.(next), parts.(previous)))

    assert requests |> List.last() |> Enum.map(&note/1) |> Enum.count(& &1) == 2

    # The canonical history never records the note.
    refute Enum.any?(messages, fn
             %Request{parts: parts} ->
               Enum.any?(parts, &match?(%Part.User{content: "Runtime note" <> _}, &1))

             _ ->
               false
           end)
  end

  test "counting restarts at each user message and ignores unwatched tools" do
    script = [search("x", "1"), search("x", "2"), "first"]

    agent =
      ExAgent.new(
        model: spy(script),
        tools: [search()],
        capabilities: [RepeatGuard.new(warn_at: 2)]
      )

    assert {:ok, %{messages: history}} = ExAgent.run(agent, "one")
    assert [nil, nil, note] = notes()
    assert note =~ "2 times"

    again =
      ExAgent.new(
        model: spy([search("x", "3"), "second"]),
        tools: [search()],
        capabilities: [RepeatGuard.new(warn_at: 2)]
      )

    assert {:ok, _} = ExAgent.run(again, "two", message_history: history)
    assert [nil, nil] = notes()

    unwatched =
      ExAgent.new(
        model: spy(script),
        tools: [search()],
        capabilities: [RepeatGuard.new(warn_at: 2, tools: ["other"])]
      )

    assert {:ok, _} = ExAgent.run(unwatched, "one")
    assert [nil, nil, nil] = notes()
  end

  test "invalid options are rejected" do
    for opts <- [[warn_at: 1], [warn_at: "3"], [tools: :some]] do
      assert_raise ArgumentError, fn -> RepeatGuard.new(opts) end
    end
  end
end
