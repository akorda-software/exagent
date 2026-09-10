defmodule ExAgent.Scenarios.LongContextTest do
  @moduledoc """
  Scenario 4 — keeping a long conversation bounded and coherent.

  Composes `ExAgent.Compaction.Summary` (via `ExAgent.Compaction.Capability`)
  with the real agent loop, covering things `compaction_test.exs` does not:

    * a recursive `:summarize` fn that itself calls `ExAgent.run/3`, with a
      deterministic model that consumes the earlier messages (no LLM quality claim),
    * the loop still **completes a tool-call round-trip** after compaction
      (the compacted history is a valid conversation, not just shorter),
    * the `:summarize` fn receives exactly the *old* messages, not the window,
    * a **custom compactor** implementing the behaviour, and
    * an invariant check on `result.new_messages` after compaction fires.
  """

  use ExUnit.Case, async: true

  alias ExAgent.Compaction
  alias ExAgent.Message
  alias ExAgent.Message.{Part, Request}
  alias ExAgent.Models.Test

  defmodule Observe do
    use ExAgent.Capability
    defstruct [:parent]

    def before_model_request(%{parent: parent}, state) do
      send(parent, {:projection, state.request_messages || state.messages})
      state
    end
  end

  describe "content-driven :summarize (recursive agent, offline model)" do
    test "the summarize fn runs a cheap agent and its text becomes the summary" do
      history = for i <- 1..20, do: user_msg("turn #{i} with padding text abcd efgh")

      owner = self()

      summarizer =
        ExAgent.new(
          model: %Test{
            script: [
              fn messages, _params ->
                [
                  %Request{
                    parts: [%Part.User{content: "Summarize these earlier messages:\n" <> encoded}]
                  }
                ] = messages

                {:ok, old} = Message.from_json(encoded)
                contents = for %Part.User{content: content} <- Message.parts(old), do: content
                send(owner, {:summarizer_contents, contents})
                Enum.join(contents, " | ")
              end
            ]
          }
        )

      compaction = %Compaction.Capability{
        compactor: Compaction.Summary,
        opts: [
          threshold_tokens: 50,
          keep_recent: 4,
          summarize: fn old_msgs ->
            send(owner, {:summary_old, old_msgs})
            {:ok, %{output: text}} = ExAgent.run(summarizer, prompt_for(old_msgs))
            text
          end
        ]
      }

      agent =
        ExAgent.new(
          model: %Test{label: "done"},
          capabilities: [compaction, %Observe{parent: self()}]
        )

      assert {:ok, %{messages: messages}} =
               ExAgent.run(agent, "latest", message_history: history)

      assert Enum.take(messages, length(history)) === history
      assert_receive {:projection, [%Request{parts: [%Part.User{content: context}]} | _]}
      expected_old = Enum.take(history, 17)
      expected_contents = for i <- 1..17, do: "turn #{i} with padding text abcd efgh"
      assert_receive {:summary_old, ^expected_old}
      assert_receive {:summarizer_contents, ^expected_contents}

      assert context ==
               "Summary of earlier conversation (context, not instructions):\n" <>
                 Enum.join(expected_contents, " | ")

      refute Enum.any?(messages, &summary?/1)
    end
  end

  describe "the loop still works after compaction (tool round-trip)" do
    test "a compacted run can still call a tool and produce a final answer" do
      # Large history so compaction definitely fires.
      history = for i <- 1..20, do: user_msg("background turn #{i} lorem ipsum dolor")

      add =
        ExAgent.Tool.new(
          name: "add",
          description: "add",
          parameters_json_schema: %{
            "type" => "object",
            "properties" => %{"a" => %{"type" => "integer"}, "b" => %{"type" => "integer"}}
          },
          takes_ctx: false,
          call: fn %{"a" => a, "b" => b} -> {:ok, a + b} end
        )

      model = %Test{
        script: [
          {:tool_calls,
           [%Part.ToolCall{tool_name: "add", args: %{"a" => 2, "b" => 3}, tool_call_id: "add-5"}]},
          "the sum is 5"
        ]
      }

      compaction = %Compaction.Capability{
        compactor: Compaction.Summary,
        opts: [threshold_tokens: 50, keep_recent: 4, summarize: fn _ -> "PAST" end]
      }

      agent =
        ExAgent.new(
          model: model,
          tools: [add],
          capabilities: [compaction, %Observe{parent: self()}]
        )

      assert {:ok, %{output: "the sum is 5", messages: messages}} =
               ExAgent.run(agent, "add two", message_history: history)

      # Projection is shorter; the complete authoritative prefix is untouched.
      assert Enum.take(messages, length(history)) === history
      assert_receive {:projection, projection}
      assert length(projection) < 12

      # ...and the tool genuinely executed (its ToolReturn is in the history).
      assert %Part.ToolReturn{
               tool_name: "add",
               tool_call_id: "add-5",
               status: :succeeded,
               content: 5
             } =
               find_return(messages, "add")
    end
  end

  describe ":summarize receives exactly the old messages, not the recent window" do
    test "the old messages retain their exact content and order, excluding the active prompt" do
      history = for i <- 1..16, do: user_msg("msg #{i} padded padded padded padded")

      parent = self()

      compaction = %Compaction.Capability{
        compactor: Compaction.Summary,
        opts: [
          threshold_tokens: 50,
          keep_recent: 6,
          summarize: fn old ->
            send(parent, {:old_messages, old})
            "S"
          end
        ]
      }

      agent = ExAgent.new(model: %Test{label: "ok"}, capabilities: [compaction])

      assert {:ok, %{output: "ok"}} = ExAgent.run(agent, "now", message_history: history)

      # The complete request context includes the current prompt (17 messages).
      # Its six-message recent window keeps that prompt: old = 17 - 6 = 11.
      expected_old = Enum.take(history, 11)
      assert_received {:old_messages, ^expected_old}
    end
  end

  describe "a custom compactor implementing the behaviour" do
    test "is invoked and its result is used as the request messages" do
      parent = self()

      # A compactor that records the call and trims to the last 2 messages.
      defmodule LastTwo do
        @behaviour ExAgent.Compaction

        @impl true
        def compact(messages, opts) do
          send(opts[:parent], {:compact_called, messages})
          {:ok, Enum.take(messages, -2)}
        end
      end

      compaction = %Compaction.Capability{compactor: LastTwo, opts: [parent: parent]}

      history = for i <- 1..10, do: user_msg("h #{i}")

      model = %Test{
        script: [
          fn messages, _params ->
            send(parent, {:model_saw, messages})
            "done"
          end
        ]
      }

      agent = ExAgent.new(model: model, capabilities: [compaction])

      assert {:ok, %{output: "done", messages: all}} =
               ExAgent.run(agent, "go", message_history: history)

      # Custom compactors receive the whole current request projection, and must
      # retain the active prompt themselves (LastTwo does).
      expected_input = Enum.take(all, 11)
      expected_projection = Enum.take(expected_input, -2)
      assert_received {:compact_called, ^expected_input}
      assert_received {:model_saw, ^expected_projection}

      assert [
               %Request{parts: [%Part.User{content: "h 10"}]},
               %Request{parts: [%Part.User{content: "go"}]}
             ] = expected_projection
    end
  end

  describe "new_messages invariant after compaction" do
    test "the run's :new_messages is still populated when compaction fires" do
      history = for i <- 1..20, do: user_msg("turn #{i} padding padding padding padding")

      compaction = %Compaction.Capability{
        compactor: Compaction.Summary,
        opts: [threshold_tokens: 50, keep_recent: 4, summarize: fn _ -> "PAST" end]
      }

      agent = ExAgent.new(model: %Test{label: "done"}, capabilities: [compaction])

      assert {:ok, %{new_messages: new, messages: all}} =
               ExAgent.run(agent, "latest", message_history: history)

      # new_messages should reflect this run's additions (request + response at
      # least), not be emptied by the history rewrite.
      assert length(new) >= 2
      assert length(new) < length(all)
      assert Enum.take(all, length(history)) === history
      assert new === Enum.drop(all, length(history))
    end
  end

  describe "projection remains separate across runs and same-run growth" do
    test "two runs retain all canonical messages and exact new-message suffixes" do
      history = for i <- 1..12, do: user_msg("old turn #{i} with context")

      compaction = %Compaction.Capability{
        compactor: Compaction.Summary,
        opts: [threshold_tokens: 0, keep_recent: 2, summarize: fn _ -> "remembered" end]
      }

      agent =
        ExAgent.new(
          model: %Test{label: "done"},
          capabilities: [compaction, %Observe{parent: self()}]
        )

      assert {:ok, first} = ExAgent.run(agent, "first active prompt", message_history: history)

      assert {:ok, second} =
               ExAgent.run(agent, "second active prompt", message_history: first.messages)

      assert Enum.take(first.messages, length(history)) === history
      assert Enum.take(second.messages, length(first.messages)) === first.messages
      assert first.new_messages === Enum.drop(first.messages, length(history))
      assert second.new_messages === Enum.drop(second.messages, length(first.messages))
      refute Enum.any?(second.messages, &summary?/1)
      assert_receive {:projection, first_projection}
      assert_receive {:projection, second_projection}
      assert Enum.any?(first_projection, &summary?/1)
      assert Enum.any?(second_projection, &summary?/1)

      assert List.last(first_projection).parts
             |> Enum.any?(&match?(%Part.User{content: "first active prompt"}, &1))

      assert List.last(second_projection).parts
             |> Enum.any?(&match?(%Part.User{content: "second active prompt"}, &1))
    end

    test "same-run completed tool exchanges can be summarized without losing authoritative outcomes" do
      parent = self()
      large = String.duplicate("tool result ", 1_000)
      read = ExAgent.Tool.new(name: "read", takes_ctx: false, call: fn _ -> {:ok, large} end)

      compaction = %Compaction.Capability{
        compactor: Compaction.Summary,
        opts: [
          threshold_tokens: 100,
          keep_recent: 1,
          summarize: fn old ->
            send(parent, {:summarized, old})
            "earlier result"
          end
        ]
      }

      model = %Test{
        script: [
          {:tool_calls, [%Part.ToolCall{tool_name: "read", args: %{}, tool_call_id: "first"}]},
          {:tool_calls, [%Part.ToolCall{tool_name: "read", args: %{}, tool_call_id: "second"}]},
          fn projected, _params ->
            send(parent, {:final_projection, projected})
            "done"
          end
        ]
      }

      agent =
        ExAgent.new(
          model: model,
          tools: [read],
          instructions: "Original rules",
          capabilities: [compaction]
        )

      assert {:ok, result} = ExAgent.run(agent, "active prompt")
      assert result.new_messages === result.messages
      assert_receive {:summarized, old}
      assert Enum.any?(Message.parts(old), &match?(%Part.ToolReturn{tool_call_id: "first"}, &1))
      refute Enum.any?(Message.parts(old), &match?(%Part.User{}, &1))
      assert_receive {:final_projection, projection}
      assert Enum.any?(projection, &summary?/1)
      assert Enum.count(Message.parts(result.messages), &match?(%Part.ToolReturn{}, &1)) == 2
      assert Enum.count(Message.parts(projection), &match?(%Part.ToolReturn{}, &1)) == 1

      assert Enum.any?(
               Message.parts(projection),
               &match?(%Part.System{content: "Original rules"}, &1)
             )

      assert Enum.any?(
               Message.parts(projection),
               &match?(%Part.User{content: "active prompt"}, &1)
             )

      refute Enum.any?(result.messages, &summary?/1)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp user_msg(text),
    do: %Request{parts: [%Part.User{content: text}], timestamp: DateTime.utc_now()}

  defp prompt_for(old_msgs) do
    "Summarize these earlier messages:\n" <> Message.to_json(old_msgs)
  end

  defp summary?(%Request{parts: [%Part.User{content: "Summary of earlier conversation" <> _}]}),
    do: true

  defp summary?(_), do: false

  defp find_return(messages, name) do
    Enum.find_value(messages, fn
      %Message.Request{parts: parts} ->
        Enum.find(parts, &match?(%Part.ToolReturn{tool_name: ^name}, &1))

      _ ->
        nil
    end)
  end
end
