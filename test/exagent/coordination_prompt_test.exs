defmodule ExAgent.CoordinationPromptTest do
  use ExUnit.Case, async: true

  alias ExAgent.{Coordination, Message}
  alias ExAgent.Message.Part

  test "default and custom prompt keys preserve string/atom arguments and the builder context" do
    journal = start_supervised!({Agent, fn -> [] end})

    for {prompt_arg, args, prompt} <- [
          {"prompt", %{"prompt" => "string prompt"}, "string prompt"},
          {"prompt", %{prompt: "atom prompt"}, "atom prompt"},
          {"question", %{"question" => "custom string"}, "custom string"},
          {"question", %{question: "custom atom"}, "custom atom"}
        ] do
      assert {:ok, result} = run(journal, prompt_arg, args)
      events = Agent.get(journal, &Enum.reverse/1)

      assert [
               {:builder, ctx, original},
               {:child_prompt, ^prompt},
               {:parent_return, "seen: " <> ^prompt}
             ] = events

      assert original === args
      assert ctx.deps == %{tenant: "context sentinel"}
      assert ctx.run_id == result.run_id
      assert ctx.root_run_id == result.root_run_id
      assert ctx.tool_call_id == "delegate-1"
      assert result.request_count == 3
      assert result.usage.input_tokens == 3
    end
  end

  test "ambiguous keys reject before builder and delegated model, including custom prompt names" do
    journal = start_supervised!({Agent, fn -> [] end})

    for {prompt_arg, args} <- [
          {"prompt", %{"prompt" => "string", prompt: "atom"}},
          {"question", %{"question" => "string", question: "atom"}}
        ] do
      assert {:ok, result} = run(journal, prompt_arg, args)
      assert [{:parent_return, message}] = Agent.get(journal, &Enum.reverse/1)
      assert message =~ "uniqueKeys"
      assert result.request_count == 2

      assert [%Part.ToolReturn{status: :validation_error}] =
               Enum.filter(Message.parts(result.messages), &match?(%Part.ToolReturn{}, &1))
    end
  end

  test "a custom string prompt name never creates an atom during lookup" do
    journal = start_supervised!({Agent, fn -> [] end})
    key = "prompt_not_an_atom_" <> Integer.to_string(System.unique_integer([:positive]))
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    assert {:ok, _} = run(journal, key, %{key => "unique prompt"})
    assert {:child_prompt, "unique prompt"} in Agent.get(journal, & &1)
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
  end

  defp run(journal, prompt_arg, args) do
    Agent.update(journal, fn _ -> [] end)

    builder = fn ctx, original ->
      Agent.update(
        journal,
        &[{:builder, Map.take(ctx, [:deps, :run_id, :root_run_id, :tool_call_id]), original} | &1]
      )

      ExAgent.new(
        model: %ExAgent.Models.Test{
          script: [
            fn messages, _ ->
              prompt =
                messages
                |> Message.parts()
                |> Enum.find(&match?(%Part.User{}, &1))
                |> Map.fetch!(:content)

              Agent.update(journal, &[{:child_prompt, prompt} | &1])
              "seen: " <> prompt
            end
          ]
        }
      )
    end

    parent =
      ExAgent.new(
        tools: [Coordination.delegation_tool(builder, prompt_arg: prompt_arg)],
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls,
             [%Part.ToolCall{tool_name: "delegate", args: args, tool_call_id: "delegate-1"}]},
            fn messages, _ ->
              %Part.ToolReturn{content: value} =
                messages |> Message.parts() |> Enum.find(&match?(%Part.ToolReturn{}, &1))

              Agent.update(journal, &[{:parent_return, value} | &1])
              "done"
            end
          ]
        }
      )

    ExAgent.run(parent, "parent", deps: %{tenant: "context sentinel"})
  end
end
