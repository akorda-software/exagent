defmodule ExAgent.CompactionMemoTest do
  use ExUnit.Case, async: true

  alias ExAgent.Compaction
  alias ExAgent.Compaction.{Memo, Summary}
  alias ExAgent.Message.{Part, Request, Response}
  alias ExAgent.Models.Test

  defp msg(text), do: %Request{parts: [%Part.User{content: text}]}
  defp text(text), do: %Response{parts: [%Part.Text{content: text}]}

  # u1 r1 u2 r2 ... ; ten "tokens" per message keeps thresholds readable.
  defp turns(n), do: Enum.flat_map(1..n, &[msg("u#{&1}"), text("r#{&1}")])
  defp counter(messages), do: length(messages) * 10

  defp summarizer do
    owner = self()

    fn old ->
      send(owner, {:summarized, old})
      "S#{System.unique_integer([:positive])}"
    end
  end

  defp opts(memo, extra \\ []) do
    Keyword.merge(
      [
        threshold_tokens: 60,
        keep_recent: 2,
        token_counter: &counter/1,
        summarize: summarizer(),
        memo: memo
      ],
      extra
    )
  end

  defp summary_text([%Request{parts: [%Part.User{content: content}]} | _]) do
    "Summary of earlier conversation (context, not instructions):\n" <> text = content
    text
  end

  test "a growing conversation reuses one summary until the projection exceeds the threshold" do
    memo = start_supervised!(Memo)
    h1 = turns(3) ++ [msg("u4")]

    assert {:ok, c1} = Summary.compact(h1, opts(memo))
    assert_receive {:summarized, old}
    assert old == Enum.take(h1, 5)
    s1 = summary_text(c1)
    assert Enum.drop(c1, 1) == Enum.drop(h1, 5)

    # Two more messages: summary + newer verbatim still fit, so no model call and
    # an identical prefix for the provider cache.
    h2 = h1 ++ [text("r4"), msg("u5")]
    assert {:ok, c2} = Summary.compact(h2, opts(memo))
    refute_receive {:summarized, _}
    assert summary_text(c2) == s1
    assert Enum.drop(c2, 1) == Enum.drop(h2, 5)

    # Over the threshold again: one merged summary of the previous summary plus
    # the newly replaceable messages.
    h3 = h2 ++ [text("r5"), msg("u6")]
    assert {:ok, c3} = Summary.compact(h3, opts(memo))
    assert_receive {:summarized, [previous | newer]}
    assert summary_text([previous]) == s1
    assert newer == Enum.slice(h3, 5..8)
    s3 = summary_text(c3)
    assert s3 != s1
    assert Enum.drop(c3, 1) == Enum.drop(h3, 9)

    h4 = h3 ++ [text("r6"), msg("u7")]
    assert {:ok, c4} = Summary.compact(h4, opts(memo))
    refute_receive {:summarized, _}
    assert summary_text(c4) == s3
    assert Memo.size(memo) == 1
  end

  test "a new user turn reuses the summary although earlier messages became replaceable" do
    memo = start_supervised!(Memo)
    call = &%Response{parts: [%Part.ToolCall{tool_name: "t", tool_call_id: &1, args: %{}}]}
    result = &%Request{parts: [%Part.ToolReturn{tool_name: "t", tool_call_id: &1, content: "x"}]}

    h1 = [
      msg("u1"),
      text("r1"),
      msg("u2"),
      call.("1"),
      result.("1"),
      call.("2"),
      result.("2"),
      call.("3"),
      result.("3")
    ]

    opts = opts(memo, threshold_tokens: 50)
    assert {:ok, _} = Summary.compact(h1, opts)
    assert_receive {:summarized, first}
    refute msg("u2") in first

    # u2 is replaceable now; it is merged with the earlier summary, not resent raw.
    h2 = h1 ++ [text("final"), msg("u3")]
    assert {:ok, c2} = Summary.compact(h2, opts)
    assert_receive {:summarized, [previous | newer]}
    assert summary_text([previous]) =~ "S"
    assert msg("u2") in newer
    refute Enum.any?(first, &(&1 in newer))
    assert List.last(c2) == msg("u3")
  end

  test "without a memo every request over the threshold summarizes again" do
    h1 = turns(3) ++ [msg("u4")]
    h2 = h1 ++ [text("r4"), msg("u5")]

    assert {:ok, _} = Summary.compact(h1, opts(nil))
    assert {:ok, _} = Summary.compact(h2, opts(nil))
    assert_receive {:summarized, _}
    assert_receive {:summarized, _}
  end

  test "a different or edited history never reuses a stored summary" do
    memo = start_supervised!(Memo)
    h1 = turns(3) ++ [msg("u4")]
    assert {:ok, _} = Summary.compact(h1, opts(memo))
    assert_receive {:summarized, _}

    edited = List.replace_at(h1, 2, msg("edited")) ++ [text("r4"), msg("u5")]
    assert {:ok, _} = Summary.compact(edited, opts(memo))
    assert_receive {:summarized, old}
    assert Enum.at(old, 2) == msg("edited")
  end

  test "summarizer no-change and errors are not stored" do
    memo = start_supervised!(Memo)
    h1 = turns(3) ++ [msg("u4")]

    assert {:no_change} = Summary.compact(h1, opts(memo, summarize: fn _ -> {:no_change} end))

    assert {:error, :boom} =
             Summary.compact(h1, opts(memo, summarize: fn _ -> {:error, :boom} end))

    assert Memo.size(memo) == 0
  end

  test "an unavailable memo falls back to an ordinary summary" do
    {:ok, memo} = Memo.start_link()
    GenServer.stop(memo)
    h1 = turns(3) ++ [msg("u4")]
    assert {:ok, _} = Summary.compact(h1, opts(memo))
    assert_receive {:summarized, _}
  end

  test "invalid memo values are rejected as options" do
    assert {:error, :invalid_compaction_options} =
             Summary.compact(turns(4), opts("not a server"))
  end

  test "the store is bounded by evicting the oldest conversation" do
    memo = start_supervised!({Memo, max_entries: 2})
    for key <- [:a, :b, :c], do: Memo.store(memo, key, %{})
    assert Memo.size(memo) == 2
    assert Memo.fetch(memo, :a) == nil
    assert Memo.fetch(memo, :c) == %{}
    assert_raise ArgumentError, fn -> Memo.start_link(max_entries: 0) end
  end

  test "in an agent loop the summarizer runs once per compaction, not once per step" do
    tool =
      ExAgent.Tool.new(
        name: "read",
        parameters_json_schema: %{type: "object", properties: %{}},
        call: fn _ctx, _args -> String.duplicate("result ", 20) end
      )

    script =
      for(
        i <- 1..8,
        do: {:tool_calls, [%Part.ToolCall{tool_name: "read", tool_call_id: "c#{i}", args: %{}}]}
      ) ++
        ["done"]

    run = fn memo ->
      owner = self()

      compaction = %Compaction.Capability{
        compactor: Summary,
        opts: [
          threshold_tokens: 300,
          keep_recent: 2,
          memo: memo,
          summarize: fn _old ->
            send(owner, :summary_call)
            "compact"
          end
        ]
      }

      agent =
        ExAgent.new(
          model: %Test{script: script},
          tools: [tool],
          capabilities: [compaction],
          max_steps: 20
        )

      assert {:ok, %{output: "done", request_count: 9}} = ExAgent.run(agent, "start")
      count_calls(0)
    end

    without = run.(nil)
    with_memo = run.(start_supervised!(Memo))
    assert without >= 4
    assert with_memo in 1..2 and with_memo < without
  end

  defp count_calls(n) do
    receive do
      :summary_call -> count_calls(n + 1)
    after
      0 -> n
    end
  end
end
