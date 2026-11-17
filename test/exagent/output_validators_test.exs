defmodule ExAgent.OutputValidatorsTest do
  use ExUnit.Case, async: true

  alias ExAgent.Judge
  alias ExAgent.Message.{Part, Request, Response, Transcript}
  alias ExAgent.Models.Test
  alias ExAgent.Tool

  defmodule Total do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:total, :integer)
    end

    def changeset(struct, attrs) do
      struct
      |> Ecto.Changeset.cast(attrs, [:total])
      |> Ecto.Changeset.validate_required([:total])
    end
  end

  defp call(name, id, args), do: %Part.ToolCall{tool_name: name, tool_call_id: id, args: args}

  defp retries(messages) do
    for %Request{parts: parts} <- messages, %Part.Retry{} = retry <- parts, do: retry
  end

  defp last_user_text(messages) do
    messages
    |> Enum.flat_map(fn
      %Request{parts: parts} -> for %Part.User{content: c} <- parts, do: c
      _ -> []
    end)
    |> List.last()
  end

  describe "output_validators" do
    test "a retry sends feedback to the model and the run continues" do
      owner = self()

      check = fn output, ctx ->
        send(owner, {:checked, output, length(ctx.messages)})
        if output =~ "42", do: :ok, else: {:retry, "Include the total."}
      end

      agent =
        ExAgent.new(
          model: %Test{script: ["about forty", "The total is 42."]},
          output_validators: [check]
        )

      assert {:ok, %{output: "The total is 42.", messages: messages}} = ExAgent.run(agent, "sum")
      assert [%Part.Retry{content: "Include the total.", tool_call_id: nil}] = retries(messages)
      assert_receive {:checked, "about forty", 2}
      assert_receive {:checked, "The total is 42.", 4}
    end

    test "validators run in order and may replace the output" do
      trim = fn output, _ctx -> {:ok, String.trim(output)} end
      upper = fn output, _ctx -> {:ok, String.upcase(output)} end
      agent = ExAgent.new(model: %Test{script: ["  done  "]}, output_validators: [trim, upper])

      assert {:ok, %{output: "DONE"}} = ExAgent.run(agent, "go")
    end

    test "an error fails the run and exhausted retries fail it as before" do
      reject = fn _output, _ctx -> {:error, :unsafe} end
      agent = ExAgent.new(model: %Test{script: ["x"]}, output_validators: [reject])

      assert {:error, %ExAgent.RunError{reason: {:output_validation_failed, :unsafe}}} =
               ExAgent.run(agent, "go")

      never = fn _output, _ctx -> {:retry, "Try again."} end

      agent =
        ExAgent.new(
          model: %Test{script: ["a", "b", "c"]},
          output_validators: [never],
          output_retries: 1
        )

      assert {:error,
              %ExAgent.RunError{
                reason: {:unexpected_model_behavior, {:output_retries_exhausted, "Try again."}}
              }} =
               ExAgent.run(agent, "go")
    end

    test "raised ModelRetry retries; other exceptions fail the run" do
      retry_once = fn output, _ctx ->
        if output == "first", do: raise(ExAgent.ModelRetry, "Again."), else: :ok
      end

      agent =
        ExAgent.new(model: %Test{script: ["first", "second"]}, output_validators: [retry_once])

      assert {:ok, %{output: "second"}} = ExAgent.run(agent, "go")

      boom = fn _output, _ctx -> raise "bug" end
      agent = ExAgent.new(model: %Test{script: ["x"]}, output_validators: [boom])

      assert {:error,
              %ExAgent.RunError{reason: {:output_validation_failed, {:validator_raised, "bug"}}}} =
               ExAgent.run(agent, "go")

      for fun <- [fn _, _ -> exit(:boom) end, fn _, _ -> throw(:boom) end] do
        agent = ExAgent.new(model: %Test{script: ["x"]}, output_validators: [fun])

        assert {:error,
                %ExAgent.RunError{
                  reason: {:output_validation_failed, {:validator_raised, reason}}
                }} = ExAgent.run(agent, "go")

        assert reason in ["exit: :boom", "throw: :boom"]
      end
    end

    test "typed output retries through the output tool call" do
      positive = fn %Total{total: total}, _ctx ->
        if total > 0, do: :ok, else: {:retry, "The total must be positive."}
      end

      script = [
        {:tool_calls, [call("final_result", "o1", %{"total" => -1})]},
        {:tool_calls, [call("final_result", "o2", %{"total" => 5})]}
      ]

      agent =
        ExAgent.new(model: %Test{script: script}, output: Total, output_validators: [positive])

      assert {:ok, %{output: %Total{total: 5}, messages: messages}} = ExAgent.run(agent, "sum")

      assert [%Part.Retry{content: "The total must be positive.", tool_call_id: "o1"}] =
               retries(messages)
    end

    test "a rejected typed output is recorded as rejected, not as never executed" do
      reject = fn _output, _ctx -> {:error, :unsafe} end
      script = [{:tool_calls, [call("final_result", "o1", %{"total" => 1})]}]

      agent =
        ExAgent.new(model: %Test{script: script}, output: Total, output_validators: [reject])

      assert {:error,
              %ExAgent.RunError{reason: {:output_validation_failed, :unsafe}, partial: partial}} =
               ExAgent.run(agent, "sum")

      assert [
               %Part.ToolReturn{
                 tool_call_id: "o1",
                 status: :failed,
                 content: "Output rejected by a validator."
               }
             ] =
               for(%Request{parts: p} <- partial.messages, %Part.ToolReturn{} = r <- p, do: r)
    end

    test "durable compositions reject validators on text output instead of losing them" do
      start_supervised!({ExAgent.Store.ETS, table: __MODULE__})
      store = ExAgent.Store.scoped({ExAgent.Store.ETS, __MODULE__}, "validators")
      upper = fn output, _ctx -> {:ok, String.upcase(output)} end

      step = %{
        id: "A",
        agent: ExAgent.new(model: %Test{script: ["lower"]}, output_validators: [upper]),
        definition: %{id: "leaf", version: "1"},
        policy: %{id: "policy", version: "1"},
        model_ref: %{id: "model", version: "1"},
        output_ref: %{id: "output", version: "1"},
        model_codec: %{
          dump: fn m -> {:ok, %{"index" => m.index}} end,
          load: fn m, d -> {:ok, %{m | index: d["index"]}} end
        }
      }

      {:ok, definition} =
        ExAgent.Coordination.Composition.new(id: "sequence", version: "1", steps: [step])

      config = %{
        store: store,
        id: "durable-text",
        policy: %{"id" => "policy", "version" => "1"},
        durability: :ephemeral,
        expires_at: nil,
        lease_ms: 60_000,
        active_time_limit_ms: 60_000
      }

      assert {:error, error} =
               ExAgent.Coordination.Composition.run(definition, "initial", continuation: config)

      assert inspect(error) =~ "output_validators_without_output_tool"
    end

    test "invalid validators are rejected" do
      assert_raise ArgumentError, fn ->
        ExAgent.new(model: "test", output_validators: [fn x -> x end])
      end

      assert_raise ArgumentError, fn -> ExAgent.new(model: "test", output_validators: :nope) end
    end
  end

  describe "Judge" do
    test "the output reviewer sends its feedback and accepts the revision" do
      owner = self()

      reviewer =
        %Test{
          script: [
            fn messages, _params ->
              prompt = last_user_text(messages)
              send(owner, {:review, prompt})
              if prompt =~ "<answer>\nTotal: 42", do: "PASS", else: "FAIL: State the total."
            end
          ]
        }

      check = Judge.output_validator(model: reviewer, criteria: "States the total.")

      tool =
        Tool.new(
          name: "sum",
          parameters_json_schema: %{type: "object"},
          call: fn _, _ -> "42" end
        )

      script = [{:tool_calls, [call("sum", "s1", %{})]}, "Done.", "Total: 42"]
      agent = ExAgent.new(model: %Test{script: script}, tools: [tool], output_validators: [check])

      assert {:ok, %{output: "Total: 42", messages: messages}} = ExAgent.run(agent, "add it up")
      assert [%Part.Retry{content: feedback}] = retries(messages)
      assert feedback =~ "State the total."

      assert_receive {:review, first}
      assert first =~ "Criteria:\nStates the total."
      assert first =~ "User: add it up"
      assert first =~ "Tool sum returned: 42"
      assert first =~ "<answer>\nDone.\n</answer>"
    end

    test "a reviewer failure accepts by default or fails when asked to" do
      broken = %Test{script: ["I am not sure."]}

      agent = fn opts ->
        ExAgent.new(
          model: %Test{script: ["x"]},
          output_validators: [Judge.output_validator([model: broken, criteria: "c"] ++ opts)]
        )
      end

      assert {:ok, %{output: "x"}} = ExAgent.run(agent.([]), "go")

      assert {:error,
              %ExAgent.RunError{
                reason: {:output_validation_failed, {:judge_failed, :invalid_verdict}}
              }} =
               ExAgent.run(agent.(on_error: :fail), "go")
    end

    test "the output reviewer sees a bounded answer; approver options are checked" do
      owner = self()

      reviewer = %Test{
        script: [
          fn messages, _ ->
            send(
              owner,
              {:review, inspect(messages, limit: :infinity, printable_limit: :infinity)}
            )

            "PASS"
          end
        ]
      }

      check = Judge.output_validator(model: reviewer, criteria: "c", max_transcript_bytes: 2_000)
      big = String.duplicate("a", 100_000)
      agent = ExAgent.new(model: %Test{script: [big]}, output_validators: [check])

      assert {:ok, %{output: ^big}} = ExAgent.run(agent, "go")
      assert_receive {:review, review}
      assert byte_size(review) < 20_000

      assert_raise ArgumentError, fn ->
        Judge.approver(model: reviewer, policy: "p", timeout: 0)
      end
    end

    test "the approver allows, denies and escalates tool calls" do
      owner = self()

      reviewer = %Test{
        script: [
          fn messages, _ ->
            prompt = last_user_text(messages)

            cond do
              prompt =~ "/tmp/" -> "ALLOW inside /tmp"
              prompt =~ "rm -rf" -> "**DENY** destructive"
              true -> "ASK not covered"
            end
          end
        ]
      }

      approve =
        Judge.approver(
          model: reviewer,
          policy: "Writes only inside /tmp.",
          escalate: fn call -> send(owner, {:escalated, call.args}) && :deny end
        )

      assert approve.(call("write", "1", %{"path" => "/tmp/a"})) == :approve
      assert approve.(call("shell", "2", %{"cmd" => "rm -rf /"})) == :deny
      assert approve.(call("write", "3", %{"path" => "/etc/x"})) == :deny
      assert_receive {:escalated, %{"path" => "/etc/x"}}
      refute_receive {:escalated, _}

      write =
        Tool.new(
          name: "write",
          parameters_json_schema: %{type: "object"},
          call: fn _, _ -> "written" end
        )

      perms = ExAgent.Permissions.new!(rules: [{"write", :ask}])

      script = [
        {:tool_calls,
         [call("write", "w1", %{"path" => "/tmp/b"}), call("write", "w2", %{"path" => "/home/x"})]},
        "ok"
      ]

      agent = ExAgent.new(model: %Test{script: script}, tools: [write])

      assert {:ok, %{messages: messages}} =
               ExAgent.run(agent, "go", permissions: perms, approve: approve)

      assert [
               %Part.ToolReturn{tool_call_id: "w1", status: :succeeded},
               %Part.ToolReturn{tool_call_id: "w2", status: :denied}
             ] =
               for(%Request{parts: p} <- messages, %Part.ToolReturn{} = r <- p, do: r)
    end

    test "verdicts are parsed leniently but only known labels count" do
      labels = ~w(PASS FAIL)
      assert {:ok, "PASS", ""} = Judge.parse("**PASS**", labels)
      assert {:ok, "FAIL", "add sources"} = Judge.parse("Fail - add sources", labels)
      assert {:ok, "PASS", ""} = Judge.parse("pass.", labels)
      assert {:ok, "FAIL", "missing total"} = Judge.parse("Verdict: FAIL — missing total", labels)
      assert {:ok, "FAIL", ""} = Judge.parse("Result: **FAIL**", labels)

      # Regressions: a leading word that merely starts like a label is not a verdict.
      for reply <- [
            "Maybe",
            "",
            "Pass-fail check: FAIL",
            "pass/fail: FAIL",
            "PASS?\nFAIL: no",
            "FAILED"
          ] do
        assert {:error, :invalid_verdict} = Judge.parse(reply, labels), reply
      end

      for reply <- ["Allow? No: DENY", "Allow-list does not cover this. DENY", "Allowed"] do
        assert {:error, :invalid_verdict} = Judge.parse(reply, ~w(ALLOW DENY ASK)), reply
      end
    end

    test "a reply in another format is asked again once" do
      reviewer = %Test{
        script: [
          fn messages, _ ->
            prompt = last_user_text(messages)

            cond do
              prompt =~ "<answer>\ntotal 3" -> "PASS"
              prompt =~ "did not follow the format" -> "FAIL: add the total"
              true -> "The answer looks incomplete."
            end
          end
        ]
      }

      check = Judge.output_validator(model: reviewer, criteria: "c")
      agent = ExAgent.new(model: %Test{script: ["x", "total 3"]}, output_validators: [check])

      assert {:ok, %{output: "total 3", messages: messages}} = ExAgent.run(agent, "go")
      assert [%Part.Retry{content: feedback}] = retries(messages)
      assert feedback =~ "add the total"
    end

    test "an answer is not accepted unreviewed when the run's limits stop the reviewer" do
      reviewer = %Test{script: ["FAIL: wrong"]}
      check = Judge.output_validator(model: reviewer, criteria: "c")
      limits = %ExAgent.UsageLimits{request_limit: 1}

      agent =
        ExAgent.new(model: %Test{script: ["x"]}, output_validators: [check], usage_limits: limits)

      assert {:error,
              %ExAgent.RunError{
                reason:
                  {:output_validation_failed, {:judge_failed, {:usage_limit_exceeded, _, _}}}
              }} =
               ExAgent.run(agent, "go")

      slow = %Test{script: [fn _, _ -> Process.sleep(300) && "PASS" end]}
      check = Judge.output_validator(model: slow, criteria: "c")
      agent = ExAgent.new(model: %Test{script: ["x"]}, output_validators: [check])
      deadline = System.monotonic_time(:millisecond) + 150

      assert {:error, %ExAgent.RunError{reason: reason}} =
               ExAgent.run(agent, "go", deadline: deadline)

      assert reason in [
               :deadline_exceeded,
               {:output_validation_failed, {:judge_failed, :deadline_exceeded}}
             ]
    end
  end

  describe "Advisor" do
    test "the agent consults the advisor with a transcript, within a use limit" do
      owner = self()

      advisor_model = %Test{
        script: [
          fn messages, _ ->
            send(owner, {:advisor_prompt, last_user_text(messages)})
            "Check the invoice dates first."
          end
        ]
      }

      advisor = ExAgent.Tool.Advisor.new(model: advisor_model, max_uses: 1)

      script = [
        {:tool_calls, [call("consult_advisor", "a1", %{"question" => "What should I check?"})]},
        {:tool_calls, [call("consult_advisor", "a2", %{"question" => "And then?"})]},
        "Checked the dates."
      ]

      agent = ExAgent.new(model: %Test{script: script}, tools: [advisor])

      assert {:ok, %{output: "Checked the dates.", messages: messages, usage: usage}} =
               ExAgent.run(agent, "audit invoices")

      assert [first, second] =
               for(%Request{parts: p} <- messages, %Part.ToolReturn{} = r <- p, do: r.content)

      assert first == "Check the invoice dates first."
      assert second =~ "advisor limit"

      assert_receive {:advisor_prompt, prompt}
      assert prompt =~ "User: audit invoices"
      assert prompt =~ "The agent asks:\nWhat should I check?"
      refute_receive {:advisor_prompt, _}

      # The advisor's request is counted in the run's usage (3 executor + 1 advisor requests).
      assert usage.input_tokens == 4
    end

    test "parallel calls in one response respect max_uses" do
      owner = self()
      advisor_model = %Test{script: [fn _, _ -> send(owner, :consulted) && "advice" end]}
      advisor = ExAgent.Tool.Advisor.new(model: advisor_model, max_uses: 1)
      calls = for n <- 1..3, do: call("consult_advisor", "a#{n}", %{"question" => "q#{n}"})
      agent = ExAgent.new(model: %Test{script: [{:tool_calls, calls}, "done"]}, tools: [advisor])

      assert {:ok, %{messages: messages}} = ExAgent.run(agent, "go")
      assert_receive :consulted
      refute_receive :consulted, 50

      assert ["advice", limit, limit] =
               for(%Request{parts: p} <- messages, %Part.ToolReturn{} = r <- p, do: r.content)

      assert limit =~ "advisor limit"
    end

    test "a slow advisor is not cut by the run's tool_timeout" do
      slow = %Test{script: [fn _, _ -> Process.sleep(300) && "Check the logs." end]}
      advisor = ExAgent.Tool.Advisor.new(model: slow)
      assert advisor.timeout == 125_000

      script = [{:tool_calls, [call("consult_advisor", "a1", %{"question" => "q"})]}, "done"]
      agent = ExAgent.new(model: %Test{script: script}, tools: [advisor], tool_timeout: 100)

      assert {:ok, %{output: "done", messages: messages}} = ExAgent.run(agent, "go")
      assert Enum.any?(messages, &(inspect(&1) =~ "Check the logs."))
      assert_raise ArgumentError, fn -> ExAgent.Tool.Advisor.new(model: slow, timeout: 0) end
    end

    test "a failing advisor does not fail the run" do
      advisor = ExAgent.Tool.Advisor.new(model: %Test{script: [fn _, _ -> raise "down" end]})

      script = [
        {:tool_calls, [call("consult_advisor", "a1", %{"question" => "q"})]},
        "done alone"
      ]

      agent = ExAgent.new(model: %Test{script: script}, tools: [advisor])

      assert {:ok, %{output: "done alone", messages: messages}} = ExAgent.run(agent, "go")

      assert [%Part.ToolReturn{status: :succeeded, content: note}] =
               for(%Request{parts: p} <- messages, %Part.ToolReturn{} = r <- p, do: r)

      assert note =~ "The advisor is unavailable"
      assert note =~ "Continue on your own."
    end

    test "invalid options are rejected" do
      assert_raise ArgumentError, fn -> ExAgent.Tool.Advisor.new(model: "test", max_uses: 0) end
      assert_raise KeyError, fn -> ExAgent.Tool.Advisor.new([]) end
    end
  end

  test "transcripts keep the current task in a multi-turn conversation" do
    big = String.duplicate("y", 3_000)

    messages = [
      %Request{parts: [%Part.User{content: "OLD TASK"}]},
      %Response{parts: [%Part.Text{content: "old answer"}]},
      %Request{parts: [%Part.User{content: "CURRENT TASK"}]},
      %Request{parts: [%Part.ToolReturn{tool_name: "a", tool_call_id: "1", content: big}]},
      %Request{parts: [%Part.ToolReturn{tool_name: "b", tool_call_id: "2", content: big}]}
    ]

    text = Transcript.render(messages, 4_096)
    assert byte_size(text) <= 4_096
    assert text =~ "User: CURRENT TASK"
    assert text =~ "Tool b returned"
    assert text =~ "entries omitted"
  end

  test "transcripts are bounded, keep the task and skip provider replay data" do
    messages = [
      %Request{parts: [%Part.User{content: "Find the bug."}]},
      %Response{
        parts: [
          %Part.Thinking{content: "secret reasoning", signature: "sig"},
          %Part.Text{content: "Looking."}
        ]
      }
      | for n <- 1..200 do
          %Request{
            parts: [
              %Part.ToolReturn{
                tool_name: "read",
                tool_call_id: "r#{n}",
                content: String.duplicate("x", 300)
              }
            ]
          }
        end
    ]

    text = Transcript.render(messages, 4_000)
    assert byte_size(text) <= 4_000
    assert text =~ ~r/^User: Find the bug\./
    assert text =~ ~r/\[\d+ entries omitted\]/
    refute text =~ "secret reasoning"
    assert String.ends_with?(text, String.duplicate("x", 300))
  end
end
