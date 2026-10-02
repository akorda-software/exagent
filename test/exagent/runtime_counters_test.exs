defmodule ExAgent.RuntimeCountersTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Capabilities, Tool}
  alias ExAgent.Message.Part

  defmodule Change do
    use ExAgent.Capability
    defstruct []
    def before_model_request(_, state), do: change(:before, state)
    def after_model_request(_, state), do: change(:after, state)

    defp change(hook, state) do
      if state.deps.hook == hook do
        send(state.deps.owner, {:confirmed, hook, state})
        state.deps.change.(state)
      else
        state
      end
    end
  end

  defmodule Observe do
    use ExAgent.Capability
    defstruct []
    def before_model_request(_, state), do: observe(:before, state)
    def after_model_request(_, state), do: observe(:after, state)

    defp observe(hook, state) do
      send(state.deps.owner, {:observed, hook, state})
      state
    end
  end

  defmodule Generic do
    use ExAgent.Capability
    def before_model_request(_, state), do: Map.put(state, :tool_retries, :host)
    def after_model_request(_, state), do: Map.put(state, :run_step, :host)
  end

  defp call(id, mode) do
    {:tool_calls,
     [%Part.ToolCall{tool_name: "effect", tool_call_id: id, args: %{"mode" => mode}}]}
  end

  defp tool(max \\ 1) do
    owner = self()

    Tool.new(
      name: "effect",
      max_retries: max,
      parameters_json_schema: %{
        "type" => "object",
        "properties" => %{"mode" => %{"type" => "string"}}
      },
      call: fn _, args ->
        send(owner, {:effect, args["mode"]})
        if args["mode"] == "retry", do: {:retry, "again"}, else: {:ok, "done"}
      end
    )
  end

  defp run(script, hook, change, opts \\ []) do
    agent =
      ExAgent.new(
        model: %ExAgent.Models.Test{script: script},
        tools: [tool()],
        capabilities: Keyword.get(opts, :caps, [Change, %Observe{}]),
        output_type: Keyword.get(opts, :output_type, :text),
        max_steps: Keyword.get(opts, :max_steps, 5),
        usage_limits: Keyword.get(opts, :usage_limits),
        output_retries: 1
      )

    ExAgent.run(agent, "input", deps: %{owner: self(), hook: hook, change: change})
  end

  defp counters(state) do
    {state.tool_retries, state.output_retries_used, state.run_step, state.tool_calls,
     state.max_steps, state.agent.output_retries}
  end

  defp caps(:module), do: [Change, %Observe{}]
  defp caps(:struct), do: [%Change{}, Observe]
  defp value(:reset), do: %{}
  defp value(:foreign), do: %{"foreign" => 4}
  defp alter(state, :tool_retries), do: %{state | tool_retries: %{"foreign" => 99}}
  defp alter(state, :output_retries), do: %{state | agent: %{state.agent | output_retries: 99}}
  defp alter(state, key), do: Map.replace!(state, key, 99)

  for hook <- [:before, :after],
      field <- [
        :tool_retries,
        :output_retries_used,
        :run_step,
        :tool_calls,
        :max_steps,
        :output_retries
      ],
      form <- [:module, :struct] do
    test "#{hook} #{field} preserved between callbacks (#{form}) through retry and reset" do
      hook = unquote(hook)
      field = unquote(field)
      caps = caps(unquote(form))
      change = &alter(&1, field)

      assert {:ok, %{output: "done"}} =
               run([call("a", "retry"), call("b", "ok"), "done"], hook, change, caps: caps)

      for {step, retries, calls} <- [{1, %{}, 0}, {2, %{"effect" => 1}, 1}, {3, %{}, 2}] do
        assert_receive {:confirmed, ^hook, confirmed}
        assert_receive {:observed, ^hook, observed}
        assert counters(confirmed) == {retries, 0, step, calls, 5, 1}
        assert counters(observed) == counters(confirmed)
      end

      assert_receive {:effect, "retry"}
      assert_receive {:effect, "ok"}
      refute_receive {:effect, _}
    end
  end

  for hook <- [:before, :after], mutation <- [:reset, :foreign] do
    @tag :causal
    test "causal #{hook} tool counter #{mutation} cannot reach the next callback" do
      hook = unquote(hook)
      value = value(unquote(mutation))
      change = fn state -> %{state | tool_retries: value} end
      assert {:ok, _} = run([call("a", "retry"), "done"], hook, change)
      assert_receive {:observed, ^hook, %{run_step: 1}}
      assert_receive {:observed, ^hook, %{run_step: 2, tool_retries: %{"effect" => 1}}}
    end
  end

  test "generic maps retain transformations without runtime fields being invented" do
    assert Capabilities.before_model_request([Generic], %{}) == %{tool_retries: :host}

    assert Capabilities.after_model_request([Generic], %{agent: nil}) == %{
             agent: nil,
             run_step: :host
           }
  end

  for hook <- [:before, :after] do
    test "#{hook} cannot replenish exhausted tool retries" do
      change = fn state -> %{state | tool_retries: %{}} end

      assert {:error, error} =
               run([call("a", "retry"), call("b", "retry"), "extra"], unquote(hook), change)

      assert inspect(error.reason) =~ "tool_retries_exhausted"
      assert error.partial.request_count == 2
      assert_receive {:effect, "retry"}
      assert_receive {:effect, "retry"}
      refute_receive {:effect, _}
    end

    test "#{hook} cannot replenish max_steps or run_step" do
      change = fn state -> %{state | run_step: 0, max_steps: 100} end

      assert {:error, %{reason: {:max_steps_exceeded, 1}, partial: partial}} =
               run([call("a", "ok"), "extra"], unquote(hook), change, max_steps: 1)

      assert partial.request_count == 1
      assert partial.run_step == 1
      assert partial.tool_calls == 1
    end

    test "#{hook} cannot replenish tool_calls under a real admission limit" do
      change = fn state -> %{state | tool_calls: 0} end

      assert {:error, error} =
               run([call("a", "ok"), call("b", "ok"), "extra"], unquote(hook), change,
                 usage_limits: %ExAgent.UsageLimits{tool_calls_limit: 1}
               )

      assert inspect(error.reason) =~ "tool_calls"
      assert error.partial.tool_calls == 1
      assert_receive {:effect, "ok"}
      refute_receive {:effect, _}
    end

    test "#{hook} cannot replenish used output retries or the configured output limit" do
      owner = self()

      invalid = fn _, _ ->
        send(owner, :model_io)
        "not typed"
      end

      change = fn state ->
        %{state | output_retries_used: 0, agent: %{state.agent | output_retries: 100}}
      end

      assert {:error, error} =
               run([invalid, invalid, invalid], unquote(hook), change,
                 output_type: ExAgent.CompositionOutputSuccessFixture.Output
               )

      assert inspect(error.reason) =~ "output_retries_exhausted"
      assert error.partial.request_count == 2
      assert_receive :model_io
      assert_receive :model_io
      refute_receive :model_io
      assert_receive {:observed, _, %{output_retries_used: 1, run_step: 2}}
    end

    test "#{hook} invalid results are not repaired and later hooks and tool IO do not run" do
      owner = self()

      script = fn _, _ ->
        send(owner, :model_io)
        call("a", "ok")
      end

      for change <- [
            fn _ -> nil end,
            fn _ -> %{} end,
            fn s -> %{s | agent: nil} end,
            fn s -> %{s | agent: Map.delete(s.agent, :output_retries)} end,
            fn s -> Map.delete(s, :tool_retries) end,
            fn _ -> raise "bad callback" end
          ] do
        assert {:error, _} = run([script], unquote(hook), change)
        refute_receive {:observed, unquote(hook), _}
        refute_receive {:effect, _}
      end

      if unquote(hook) == :before, do: refute_received(:model_io)
    end
  end

  test "legitimate selection, agent edits, projection and response transformations survive" do
    owner = self()

    selected = %ExAgent.Models.Test{
      script: [
        fn messages, params ->
          send(owner, {:selected_io, messages, params.function_tools})
          "original"
        end
      ]
    }

    projection = [ExAgent.Message.new_request([%Part.User{content: "projected"}])]
    selected_tool = %{tool() | max_retries: 7}

    change = fn s ->
      %{
        s
        | model: selected,
          request_messages: projection,
          settings: %{s.settings | temperature: 0.25},
          params: %{s.params | function_tools: [selected_tool]},
          agent: %{
            s.agent
            | instructions: [%Part.System{content: "host edit"}],
              output_retries: 99
          }
      }
    end

    assert {:ok, %{output: "original"}} = run(["unused"], :before, change)
    assert_receive {:selected_io, ^projection, [%{max_retries: 7}]}
    assert_receive {:observed, :before, observed}
    assert observed.agent.instructions == [%Part.System{content: "host edit"}]
    assert observed.agent.output_retries == 1
    assert observed.settings.temperature == 0.25

    rewrite = fn s ->
      response = List.last(s.messages)

      %{
        s
        | messages:
            List.replace_at(s.messages, -1, %{
              response
              | parts: [%Part.Text{content: "rewritten"}]
            })
      }
    end

    assert {:ok, %{output: "rewritten"}} = run(["original"], :after, rewrite)
  end
end
