defmodule ExAgent.EvalTest do
  use ExUnit.Case, async: true

  alias ExAgent.Eval
  alias ExAgent.Eval.{Case, Report}
  alias ExAgent.Message.Part
  alias ExAgent.Models.Test, as: TestModel

  # Answers from the user's text: "capital of X" -> fixed answers.
  defp echo_model do
    %TestModel{
      script:
        List.duplicate(
          fn messages, _ ->
            text =
              for %ExAgent.Message.Request{parts: parts} <- messages,
                  %Part.User{content: c} <- parts,
                  is_binary(c),
                  reduce: "",
                  do: (_ -> c)

            cond do
              text =~ "France" -> "The capital is Paris."
              text =~ "Spain" -> "The capital is Madrid."
              true -> "I don't know."
            end
          end,
          50
        )
    }
  end

  defp cases do
    [
      Case.new("france", "Capital of France?", expected: "Paris"),
      Case.new("spain", "Capital of Spain?", expected: "Madrid"),
      Case.new("peru", "Capital of Peru?", expected: "Lima")
    ]
  end

  test "scores each case and summarizes" do
    agent = ExAgent.new(model: echo_model())
    report = Eval.run(agent, cases(), evaluators: [Eval.contains(), Eval.matches(~r/capital/i)])

    assert %Report{results: [france, spain, peru], summary: summary} = report
    assert france.passed and spain.passed
    refute peru.passed

    assert [
             %{name: "contains", score: +0.0, passed: false, reason: "missing: Lima"},
             %{name: "matches", passed: false}
           ] = peru.scores

    assert summary.runs == 3
    assert summary.passed == 2
    assert_in_delta summary.pass_rate, 2 / 3, 1.0e-9
    assert summary.cases == %{"france" => 1.0, "spain" => 1.0, "peru" => 0.0}
    assert summary.evaluators["contains"].pass_rate == 2 / 3
    assert summary.input_tokens == 3
    assert summary.requests == 3
    assert summary.errors == 0
    assert is_integer(summary.duration_ms.p95)

    text = Report.format(report)
    assert text =~ "Eval: 2/3 passed (67%)"
    assert text =~ "FAIL peru #1: contains (missing: Lima); matches"
  end

  test "repeat, concurrency, custom evaluators, thresholds and skip" do
    counter = :counters.new(1, [])

    target = fn input, opts ->
      :counters.add(counter, 1, 1)
      assert opts[:deps] == %{tenant: "t1"}
      ExAgent.run(ExAgent.new(model: echo_model()), input, opts)
    end

    length_score =
      Eval.evaluator("short", fn %{output: o} -> {min(1.0, 20 / String.length(o)), "len"} end,
        threshold: 0.9
      )

    skipper = Eval.evaluator("skips", fn _ -> :skip end)

    report =
      Eval.run(target, cases(),
        evaluators: [length_score, skipper],
        repeat: 2,
        concurrency: 3,
        run_opts: [deps: %{tenant: "t1"}]
      )

    assert :counters.get(counter, 1) == 6
    assert length(report.results) == 6

    assert Enum.map(report.results, &{&1.case, &1.attempt}) |> Enum.take(2) == [
             {"france", 1},
             {"france", 2}
           ]

    # "The capital is Paris." is 21 characters: 20/21 >= 0.9.
    assert Enum.all?(report.results, & &1.passed)
    assert %{name: "skips", score: nil, passed: nil} = Enum.at(hd(report.results).scores, 1)
    refute Map.has_key?(report.summary.evaluators, "skips")
  end

  test "failed, raising and slow runs fail without stopping the eval" do
    target = fn
      "boom", _ -> raise "exploded"
      "slow", _ -> Process.sleep(1_000)
      "error", _ -> {:error, :nope}
      "odd", _ -> :what
      input, opts -> ExAgent.run(ExAgent.new(model: echo_model()), input, opts)
    end

    bad_evaluator = Eval.evaluator("raises", fn _ -> raise "eval bug" end)

    report =
      Eval.run(
        target,
        [
          Case.new("boom", "boom"),
          Case.new("slow", "slow"),
          Case.new("error", "error"),
          Case.new("odd", "odd"),
          Case.new("ok", "Capital of France?")
        ],
        evaluators: [bad_evaluator],
        timeout: 200
      )

    assert [boom, slow, error, odd, ok] = report.results
    assert {:raised, "exploded"} = boom.error
    assert slow.error == :timeout
    assert error.error == :nope
    assert {:invalid_target_result, :what} = odd.error

    assert [%{name: "raises", score: +0.0, passed: false, reason: "evaluator raised: eval bug"}] =
             ok.scores

    refute Enum.any?(report.results, & &1.passed)
    assert report.summary.errors == 4
    assert report.summary.cost_cents == nil
  end

  test "equals and tool_called" do
    lookup = ExAgent.Tool.new(name: "lookup", call: fn _ctx, _args -> "found" end)

    script = [
      {:tool_calls,
       [%Part.ToolCall{tool_name: "lookup", tool_call_id: "1", args: %{"id" => "7"}}]},
      "  ok  "
    ]

    agent = ExAgent.new(model: %TestModel{script: script}, tools: [lookup])

    report =
      Eval.run(agent, [Case.new("one", "go", expected: "OK")],
        evaluators: [
          Eval.equals(case_sensitive: false),
          Eval.tool_called("lookup", args: &(&1["id"] == "7"), times: 1),
          Eval.tool_called("delete")
        ]
      )

    assert [%{passed: true}, %{passed: true}, %{passed: false, reason: "called 0 times"}] =
             hd(report.results).scores
  end

  test "judge grades with a reviewer model" do
    owner = self()

    reviewer = %TestModel{
      script:
        List.duplicate(
          fn messages, _ ->
            [%{parts: parts} | _] = messages

            prompt =
              Enum.find_value(parts, fn
                %Part.User{content: c} -> c
                _ -> nil
              end)

            send(owner, {:judged, prompt})
            if prompt =~ "Paris", do: "PASS", else: "FAIL: wrong capital"
          end,
          10
        )
    }

    report =
      Eval.run(
        ExAgent.new(model: echo_model()),
        Enum.take(cases(), 2) ++ [Case.new("x", "Capital of Peru?")],
        evaluators: [Eval.judge(model: reviewer, criteria: "Names the right capital.")]
      )

    assert [%{passed: true}, %{passed: false}, %{passed: false}] = report.results
    assert [%{reason: "wrong capital"}] = Enum.at(report.results, 1).scores

    prompts =
      for _ <- 1..3 do
        assert_receive {:judged, prompt}
        prompt
      end

    prompt = Enum.find(prompts, &(&1 =~ "France"))
    assert prompt =~ "Criteria:\nNames the right capital."
    assert prompt =~ "<task>\nCapital of France?\n</task>"
    assert prompt =~ "<key_content>\nParis\n</key_content>"
    assert prompt =~ "<transcript>\nUser: Capital of France?"
    assert prompt =~ "<answer>\nThe capital is Paris.\n</answer>"
  end

  test "the judge sees tool results, so looked-up facts count as supported" do
    owner = self()

    lookup =
      ExAgent.Tool.new(name: "lookup", call: fn _ctx, _args -> "order 7: 3 items, 120 EUR" end)

    script = [
      {:tool_calls, [%Part.ToolCall{tool_name: "lookup", tool_call_id: "1", args: %{}}]},
      "Order 7 has 3 items and costs 120 EUR."
    ]

    reviewer = %TestModel{
      script: [
        fn [%{parts: parts} | _], _ ->
          send(
            owner,
            {:judged, Enum.find_value(parts, &(match?(%Part.User{}, &1) && &1.content))}
          )

          "PASS"
        end
      ]
    }

    agent = ExAgent.new(model: %TestModel{script: script}, tools: [lookup])

    Eval.run(agent, [Case.new("t", "Total of order 7?", expected: "120 EUR")],
      evaluators: [Eval.judge(model: reviewer, criteria: "Accurate.")]
    )

    assert_receive {:judged, prompt}
    assert prompt =~ "Tool lookup returned"
    assert prompt =~ "order 7: 3 items, 120 EUR"
  end

  test "compare lists regressions and improvements" do
    base = Eval.run(ExAgent.new(model: echo_model()), cases(), evaluators: [Eval.contains()])

    worse = %TestModel{script: List.duplicate("The capital is Paris. Also Lima.", 10)}
    candidate = Eval.run(ExAgent.new(model: worse), cases(), evaluators: [Eval.contains()])

    assert %{
             regressed: [{"spain", 1.0, +0.0}],
             improved: [{"peru", +0.0, 1.0}],
             pass_rate_delta: delta
           } =
             Report.compare(base, candidate)

    assert delta == 0.0
  end

  describe "review regressions" do
    test "function targets with minimal results, exits and throws" do
      bad = Eval.evaluator("exits", fn _ -> exit(:eval_exit) end, threshold: 0)

      target = fn
        "minimal", _ -> {:ok, %{output: "x"}}
        "exit", _ -> exit(:boom)
        "throw", _ -> throw(:boom)
        "nil error", _ -> {:error, nil}
      end

      report =
        Eval.run(
          target,
          [
            Case.new("minimal", "minimal"),
            Case.new("exit", "exit"),
            Case.new("throw", "throw"),
            Case.new("nil error", "nil error")
          ],
          evaluators: [bad]
        )

      assert [minimal, exited, thrown, nil_error] = report.results
      assert minimal.output == "x" and is_nil(minimal.input_tokens)

      assert [%{passed: false, score: +0.0, reason: "evaluator exit: :eval_exit"}] =
               minimal.scores

      refute minimal.passed
      assert exited.error == {:exit, :boom}
      assert thrown.error == {:throw, :boom}
      assert nil_error.error == :error and not nil_error.passed
    end

    @tag :capture_log
    test "a crash linked to the target fails that run, not the caller" do
      target = fn
        "linked", _ ->
          spawn_link(fn -> exit(:boom) end)
          Process.sleep(200)
          {:ok, %{output: "never"}}

        input, opts ->
          ExAgent.run(ExAgent.new(model: echo_model()), input, opts)
      end

      report =
        Eval.run(target, [Case.new("linked", "linked"), Case.new("ok", "Capital of France?")])

      assert [%{error: {:exit, :boom}, passed: false}, %{error: nil, passed: true}] =
               report.results
    end

    test "a slow evaluator never discards a finished run" do
      slow = Eval.evaluator("slow", fn _ -> Process.sleep(300) && true end)
      agent = ExAgent.new(model: echo_model())
      [c | _] = cases()

      ok = Eval.run(agent, [c], evaluators: [slow], timeout: 100)
      assert [%{passed: true, error: nil, input_tokens: 1}] = ok.results

      late = Eval.run(agent, [c], evaluators: [slow], evaluator_timeout: 50)

      assert [%{passed: false, error: nil, output: "The capital is Paris.", input_tokens: 1} = r] =
               late.results

      assert [%{name: "slow", passed: false, reason: "evaluators timed out"}] = r.scores
    end

    test "failed runs keep the usage they spent" do
      failing = ExAgent.Tool.new(name: "fails", call: fn _ctx, _args -> {:error, "down"} end)
      script = [{:tool_calls, [%Part.ToolCall{tool_name: "fails", tool_call_id: "1", args: %{}}]}]
      agent = ExAgent.new(model: %TestModel{script: script}, tools: [failing])

      report = Eval.run(agent, [Case.new("f", "go")])

      assert [%{error: {:tool_execution_failed, "fails", "down"}, input_tokens: 1, requests: 1}] =
               report.results

      assert report.summary.input_tokens == 1 and report.summary.requests == 1
    end

    test "contains handles empty and numeric expectations; tool args may be JSON text" do
      lookup = ExAgent.Tool.new(name: "lookup", call: fn _ctx, _args -> "120" end)

      script = [
        {:tool_calls,
         [%Part.ToolCall{tool_name: "lookup", tool_call_id: "1", args: ~s({"id":"7"})}]},
        "Total: 120"
      ]

      agent = ExAgent.new(model: %TestModel{script: script}, tools: [lookup])
      only = Eval.evaluator("ok tuple", fn _ -> {true, nil} end)

      report =
        Eval.run(agent, [Case.new("n", "go", expected: 120)],
          evaluators: [
            Eval.contains(),
            Eval.tool_called("lookup", args: &(&1["id"] == "7")),
            only
          ]
        )

      assert [
               %{
                 passed: true,
                 scores: [%{score: 1.0}, %{passed: true}, %{passed: true, reason: nil}]
               }
             ] =
               report.results

      empty = Eval.run(agent, [Case.new("e", "go", expected: [])], evaluators: [Eval.contains()])
      assert [%{scores: [%{name: "contains", score: nil, passed: nil}]}] = empty.results
    end

    test "duplicate names, bad options and compare with added and removed cases" do
      agent = ExAgent.new(model: echo_model())

      assert_raise ArgumentError, ~r/unique/, fn ->
        Eval.run(agent, [Case.new("a", "x"), Case.new("a", "y")])
      end

      assert_raise ArgumentError, fn -> Eval.run(agent, cases(), run_opts: :bad) end
      assert_raise ArgumentError, fn -> Eval.run(agent, cases(), evaluators: Eval.contains()) end

      base = Eval.run(agent, Enum.take(cases(), 2), evaluators: [Eval.contains()])
      candidate = Eval.run(agent, Enum.drop(cases(), 1), evaluators: [Eval.contains()])

      assert %{added: ["peru"], removed: ["france"], regressed: [], improved: []} =
               Report.compare(base, candidate)
    end

    test "the judge prompt bounds each field and shows images as placeholders" do
      owner = self()

      reviewer = %TestModel{
        script: [
          fn [%{parts: parts} | _], _ ->
            send(
              owner,
              {:judged, Enum.find_value(parts, &(match?(%Part.User{}, &1) && &1.content))}
            )

            "PASS"
          end
        ]
      }

      big = String.duplicate("a", 50_000)
      agent = ExAgent.new(model: %TestModel{script: [big]})

      input = [
        %{"type" => "text", "text" => "Describe"},
        %{"type" => "image", "data" => String.duplicate("Q", 40_000), "media_type" => "image/png"}
      ]

      Eval.run(agent, [Case.new("img", input, expected: big)],
        evaluators: [Eval.judge(model: reviewer, criteria: "c", max_transcript_bytes: 4_000)]
      )

      assert_receive {:judged, prompt}
      assert prompt =~ "<task>\nDescribe [image]\n</task>"
      refute prompt =~ "QQQQ"
      assert byte_size(prompt) < 4 * 4_000
    end
  end

  test "invalid arguments raise" do
    agent = ExAgent.new(model: echo_model())
    assert_raise ArgumentError, fn -> Eval.run(agent, [:nope]) end
    assert_raise ArgumentError, fn -> Eval.run(agent, cases(), concurrency: 0) end
    assert_raise ArgumentError, fn -> Eval.run(agent, cases(), evaluators: [fn _ -> true end]) end
    assert_raise ArgumentError, fn -> Eval.run(:agent, cases()) end
    assert_raise ArgumentError, fn -> Eval.evaluator("x", fn _ -> true end, threshold: 2) end
    assert_raise ArgumentError, fn -> Eval.judge(model: "test", criteria: "") end

    assert_raise ArgumentError, fn ->
      Eval.judge(model: "test", criteria: "c", max_transcript_bytes: 10)
    end

    assert_raise ArgumentError, fn -> Case.new("x", "y", run_opts: :bad) end
  end
end
