defmodule ExAgent.R2BaseContractTest do
  use ExUnit.Case, async: true

  alias ExAgent.{Message, ModelProfile, RunError, Tool}
  alias ExAgent.Message.Part

  defmodule Undeclared do
    @behaviour ExAgent.Model
    defstruct [:owner]
    def model_name(_), do: "undeclared"
    def system(_), do: "custom"

    def request(model, _, _, _) do
      send(model.owner, :model_called)
      {:ok, Message.new_response([%Part.Text{content: "done"}]), model}
    end
  end

  defmodule Rewrite do
    use ExAgent.Capability
    defstruct [:field, :value]
    def before_tool_execute(cap, _, call), do: Map.put(call, cap.field, cap.value)
  end

  defmodule Select do
    use ExAgent.Capability

    def before_model_request(_, state) do
      %{state | params: %{state.params | function_tools: []}}
    end
  end

  defmodule RequestModel do
    @behaviour ExAgent.Model
    defstruct [:owner, index: 0]
    def model_name(_), do: "request-selected"
    def system(_), do: "custom"
    def profile(_), do: %ModelProfile{supports_tools: true}

    def request(model, messages, _, params) do
      send(
        model.owner,
        {:request, model.index, messages, Enum.map(params.function_tools, & &1.name)}
      )

      parts =
        if model.index == 0,
          do: [
            %Part.ToolCall{
              tool_name: "selected",
              tool_call_id: "selected-call",
              args: %{"n" => 3}
            }
          ],
          else: [%Part.Text{content: "done"}]

      {:ok, Message.new_response(parts), %{model | index: model.index + 1}}
    end
  end

  defmodule PerRequest do
    use ExAgent.Capability
    defstruct [:label, :fail]

    def before_model_request(cap, state) do
      send(state.deps.owner, {:before, cap.label, state.deps.tag, state.run_step})
      if cap.fail == :before, do: raise("before request")

      if cap.label == :select do
        %{
          state
          | model: %RequestModel{owner: state.deps.owner, index: state.run_step - 1},
            params: %{state.params | function_tools: [state.deps.tool]}
        }
      else
        state
      end
    end

    def after_model_request(cap, state) do
      send(state.deps.owner, {:after, cap.label, state.deps.tag, state.run_step})
      if cap.fail == :after, do: raise("after request")
      state
    end

    def before_tool_execute(_, ctx, call) do
      send(ctx.deps.owner, {:tool_context, ctx.tool_name, ctx.tool_call_id, ctx.deps.tag})
      call
    end
  end

  defmodule BeforeFailure do
    use ExAgent.Capability
    def before_tool_execute(_, _, _), do: raise("before effect")
  end

  test "request selection composes in order with isolated DI and populated tool context" do
    owner = self()

    agent =
      ExAgent.new(
        model: %Undeclared{owner: owner},
        capabilities: [%PerRequest{label: :select}, %PerRequest{label: :observe}]
      )

    for tag <- [:one, :two] do
      tool =
        Tool.new(
          name: "selected",
          takes_ctx: true,
          parameters_json_schema: %{
            "type" => "object",
            "properties" => %{"n" => %{"type" => "integer"}},
            "required" => ["n"]
          },
          call: fn ctx, args ->
            send(owner, {:effect, ctx.deps.tag, args})
            "saved"
          end
        )

      assert {:ok, %{output: "done", request_count: 2}} =
               ExAgent.run(agent, "go", deps: %{owner: owner, tag: tag, tool: tool})

      # Receive without selective patterns: an inverted hook order must fail,
      # not be hidden by searching ahead in the mailbox.
      events =
        for _ <- 1..13 do
          assert_receive event
          event
        end

      assert [
               {:before, :select, ^tag, 1},
               {:before, :observe, ^tag, 1},
               {:request, 0, _, ["selected"]},
               {:after, :select, ^tag, 1},
               {:after, :observe, ^tag, 1},
               {:tool_context, "selected", "selected-call", ^tag},
               {:tool_context, "selected", "selected-call", ^tag},
               {:effect, ^tag, %{"n" => 3}},
               {:before, :select, ^tag, 2},
               {:before, :observe, ^tag, 2},
               {:request, 1, _, ["selected"]},
               {:after, :select, ^tag, 2},
               {:after, :observe, ^tag, 2}
             ] = events

      refute_receive _, 0
    end

    assert agent.tools == []
    assert agent.model == %Undeclared{owner: owner}
  end

  test "before-tool failure reports no execution rather than uncertain IO" do
    owner = self()
    tool = Tool.new(name: "selected", takes_ctx: false, call: fn _ -> send(owner, :effect) end)

    agent =
      ExAgent.new(
        model: %RequestModel{owner: owner},
        tools: [tool],
        capabilities: [BeforeFailure]
      )

    assert {:error, %RunError{partial: partial}} = ExAgent.run(agent, "go")
    assert [%Part.ToolReturn{status: :not_executed}] = returns(partial)
    refute_receive :effect
    refute_receive {:request, 1, _, _}, 0
  end

  test "pre and post model hook failures preserve the last confirmed boundary" do
    for {phase, requests} <- [before: 0, after: 1] do
      agent =
        ExAgent.new(
          model: %Undeclared{owner: self()},
          capabilities: [%PerRequest{label: :observe, fail: phase}]
        )

      assert {:error, %RunError{partial: partial}} =
               ExAgent.run(agent, "go", deps: %{owner: self(), tag: phase})

      assert partial.request_count == requests
      assert Enum.count(partial.messages, &is_struct(&1, Message.Response)) == requests
      assert partial.status == :failed
    end
  end

  test "invalid selected callable rejects before a model attempt" do
    for call <- [nil, fn -> :wrong_arity end] do
      tool = Tool.new(name: "invalid", takes_ctx: false, call: call)
      agent = ExAgent.new(model: %RequestModel{owner: self()}, tools: [tool])

      assert {:error,
              %RunError{reason: {:invalid_tool_callable, "invalid"}, partial: %{request_count: 0}}} =
               ExAgent.run(agent, "go")

      refute_receive {:request, _, _, _}, 0
    end
  end

  test "custom tool hooks cannot replace identity even without envelope metadata" do
    owner = self()

    tool = fn name ->
      Tool.new(
        name: name,
        description: "effect",
        parameters_json_schema: %{},
        takes_ctx: false,
        call: fn _ ->
          send(owner, :effect)
          "ok"
        end
      )
    end

    for {field, value} <- [tool_name: "other", metadata: %{"forged" => true}, kind: :provider],
        mode <- [:sync, :stream] do
      agent =
        ExAgent.new(
          model: %ExAgent.Models.Test{
            script: [
              {:tool_calls,
               [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}]},
              "done"
            ]
          },
          tools: [tool.("effect"), tool.("other")],
          capabilities: [%Rewrite{field: field, value: value}]
        )

      assert {:error, %RunError{reason: :tool_call_identity_changed, partial: partial}} =
               run(agent, mode)

      assert [%Part.ToolReturn{tool_name: "effect", tool_call_id: "call", status: :not_executed}] =
               returns(partial)

      refute_receive :effect
    end
  end

  test "undeclared model capabilities never authorize tools or promise native output" do
    model = %Undeclared{owner: self()}

    assert %ModelProfile{
             supports_tools: false,
             supports_json_schema_output: false,
             supports_json_object_output: false
           } = ExAgent.Model.profile(model)

    tool =
      Tool.new(
        name: "effect",
        description: "effect",
        parameters_json_schema: %{},
        takes_ctx: false,
        call: fn _ -> "ok" end
      )

    assert {:error, %RunError{reason: {:unsupported, :tools}, partial: %{request_count: 0}}} =
             ExAgent.run(ExAgent.new(model: model, tools: [tool]), "go")

    refute_receive :model_called
    assert {:ok, %{output: "done"}} = ExAgent.run(ExAgent.new(model: model), "go")
    assert_receive :model_called
  end

  test "tools omitted by request selection cannot execute from the definition inventory" do
    owner = self()

    tool =
      Tool.new(
        name: "effect",
        description: "effect",
        parameters_json_schema: %{},
        takes_ctx: false,
        call: fn _ ->
          send(owner, :effect)
          "ok"
        end
      )

    agent =
      ExAgent.new(
        model: %ExAgent.Models.Test{
          script: [
            {:tool_calls,
             [
               %Part.ToolCall{
                 tool_name: "effect",
                 tool_call_id: "call",
                 args: %{}
               }
             ]}
          ]
        },
        tools: [tool],
        capabilities: [Select]
      )

    assert {:error, %RunError{partial: partial}} = ExAgent.run(agent, "go")
    assert [%Part.ToolReturn{status: :validation_error}] = returns(partial)
    refute_receive :effect
  end

  defp run(agent, :sync), do: ExAgent.run(agent, "go")
  defp run(agent, :stream), do: agent |> ExAgent.run_stream("go") |> Enum.to_list() |> List.last()

  defp returns(result),
    do:
      for(
        %Message.Request{parts: parts} <- result.messages,
        %Part.ToolReturn{} = part <- parts,
        do: part
      )
end
