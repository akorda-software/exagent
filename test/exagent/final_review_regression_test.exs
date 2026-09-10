defmodule ExAgent.FinalReviewRegressionTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Coordination, Message, Model, RequestError, RunError, Tool}
  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Models.Test, as: TestModel

  defmodule Transform do
    use ExAgent.Capability
    defstruct [:parts, invalid: false]

    def after_model_request(cap, state) do
      replacement =
        if cap.invalid,
          do: :not_a_response,
          else: %{
            List.last(state.messages)
            | parts: cap.parts,
              usage: %Usage{input_tokens: 999, output_tokens: 999}
          }

      %{state | messages: List.replace_at(state.messages, -1, replacement)}
    end
  end

  defmodule Source do
    @behaviour ExAgent.Model
    defstruct [:owner, :tag, :usage, mode: :raise]
    def model_name(_), do: "review-source"
    def system(_), do: "test"
    def request(_, _, _, _), do: {:error, :stream_only}

    def request_stream(model, _, _, _) do
      Stream.resource(
        fn -> 0 end,
        fn
          0 when model.usage != nil ->
            {[{:usage, model.usage}], :delta_next}

          :delta_next ->
            {[{:text_delta, "first"}], 1}

          0 ->
            {[{:text_delta, "first"}], 1}

          1 ->
            case model.mode do
              :raise -> raise "source failed"
              :throw -> throw(:source_failed)
              :kill -> Process.exit(self(), :kill)
            end
        end,
        fn state -> send(model.owner, {:source_closed, model.tag, state}) end
      )
    end
  end

  defmodule ScopeSpy do
    use ExAgent.Capability
    defstruct [:owner]

    def before_model_request(cap, state) do
      send(cap.owner, {:stream_scope, state.execution_scope})
      state
    end
  end

  defmodule Failing do
    @behaviour ExAgent.Model
    defstruct [:error]
    def model_name(_), do: "review-error"
    def system(_), do: "test"
    def request(model, _, _, _), do: {:error, model.error}
  end

  defmodule Fast do
    @behaviour ExAgent.Model
    defstruct [:owner]
    def model_name(_), do: "fast"
    def system(_), do: "test"

    def request(model, _, _, _) do
      send(model.owner, {:fast_wait, self()})

      receive do
        :release -> :ok
      end

      {:ok,
       %Response{
         parts: [%Part.Text{content: "fast done"}],
         usage: %Usage{input_tokens: 7, output_tokens: 2}
       }, model}
    end
  end

  test "after_model_request output comes from the effective response in all three modes" do
    agent =
      ExAgent.new(
        model: %TestModel{script: ["raw"]},
        capabilities: [%Transform{parts: [%Part.Text{content: "redacted"}]}]
      )

    for mode <- [:sync, :stream_text, :public_stream] do
      assert {:ok, result} = run_mode(agent, mode)
      assert result.output == "redacted"
      assert Response.text(List.last(result.messages)) == "redacted"
      assert result.usage.input_tokens == 1
      assert List.last(result.messages).usage.input_tokens == 1
    end
  end

  test "removing a model tool call after the response prevents its old effect in all modes" do
    owner = self()

    tool =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        call: fn _ ->
          send(owner, :effect)
          "done"
        end
      )

    agent =
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("effect")]}, "old final"]},
        tools: [tool],
        capabilities: [%Transform{parts: [%Part.Text{content: "removed"}]}]
      )

    for mode <- [:sync, :stream_text, :public_stream] do
      assert {:ok, result} = run_mode(agent, mode)
      assert result.output == "removed"
      assert result.model.index == 1
      refute_receive :effect
      refute Enum.any?(Message.parts(result.messages), &match?(%Part.ToolReturn{}, &1))
    end
  end

  test "an invalid response transformation is a controlled error with valid partial history" do
    agent =
      ExAgent.new(model: %TestModel{script: ["raw"]}, capabilities: [%Transform{invalid: true}])

    for mode <- [:sync, :stream_text, :public_stream] do
      assert {:error, %RunError{partial: partial}} = run_mode(agent, mode)
      assert partial.status == :failed
      assert partial.usage.input_tokens == 1
      assert %Response{} = List.last(partial.messages)
    end
  end

  test "scope loss preserves the child subtotal and cost already delivered in root progress" do
    owner = self()

    wait =
      Tool.new(
        name: "wait",
        takes_ctx: false,
        call: fn _ ->
          send(owner, {:slow_wait, self()})

          receive do
            :release -> "done"
          end
        end
      )

    slow =
      ExAgent.new(
        model: %TestModel{script: [{:tool_calls, [call("wait")]}, "slow done"]},
        tools: [wait]
      )

    fast = ExAgent.new(model: %Fast{owner: owner})

    fast_builder = fn ctx, _ ->
      send(owner, {:scope, ctx.execution_scope})
      fast
    end

    tools = [
      Coordination.delegation_tool(fast_builder, name: "fast"),
      Coordination.delegation_tool(slow, name: "slow")
    ]

    agent =
      ExAgent.new(
        model: %TestModel{
          script: [
            {:tool_calls, [call("fast", %{"prompt" => "go"}), call("slow", %{"prompt" => "go"})]},
            "root done"
          ]
        },
        tools: tools
      )

    root =
      spawn(fn ->
        send(
          owner,
          {:root_result,
           ExAgent.run(agent, "go",
             estimate_cost: fn _, usage -> usage.input_tokens end,
             on_progress: &send(owner, {:progress, &1})
           )}
        )
      end)

    on_exit(fn -> if Process.alive?(root), do: Process.exit(root, :kill) end)
    assert_receive {:scope, scope}, 1_000
    assert_receive {:slow_wait, _}, 1_000
    assert_receive {:fast_wait, fast_pid}, 1_000
    send(fast_pid, :release)
    published = await_fast_progress()
    assert published.usage.input_tokens == 9
    assert published.request_count == 3
    assert published.cost_cents == 9
    Process.exit(scope.pid, :kill)
    assert_receive {:root_result, {:error, %RunError{partial: final}}}, 2_000
    assert final.usage == published.usage
    assert final.request_count == published.request_count
    assert final.tool_calls == published.tool_calls
    assert final.cost_cents == published.cost_cents
    assert final.cost_status == published.cost_status
    assert final.usage_status == :partial
    assert length(returns(final)) == 2
    assert Enum.count(returns(final), &(&1.status == :succeeded)) == 1
  end

  test "automatic telemetry and run! messages project provider errors without their live model" do
    owner = self()
    sentinel = "REQUEST_MODEL_PRIVATE_SENTINEL"

    error = %RequestError{
      provider: :openai,
      status: 429,
      reason: {:stream_limit, :max_response_bytes},
      body: %{secret: sentinel},
      model: struct(ExAgent.Models.OpenAI, model: "synthetic", api_key: sentinel)
    }

    agent = ExAgent.new(model: %Failing{error: error}, name: "review-private-error")
    id = "review-error-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        id,
        [:exagent, :run, :exception],
        fn _, _, metadata, _ ->
          if metadata.agent == "review-private-error",
            do: send(owner, {:telemetry_error, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(id) end)

    assert {:error, %RunError{reason: {:model_request_failed, ^error}}} = ExAgent.run(agent, "go")
    assert_receive {:telemetry_error, metadata}
    refute inspect(metadata) =~ sentinel
    assert inspect(metadata) =~ "openai"
    assert inspect(metadata) =~ "429"
    assert inspect(metadata) =~ "stream_limit"
    exception = assert_raise ExAgent.UnexpectedModelBehavior, fn -> ExAgent.run!(agent, "go") end
    refute Exception.message(exception) =~ sentinel
    assert exception.error.reason == {:model_request_failed, error}
  end

  test "stream failure retains its last published cost after the ledger disappears" do
    owner = self()
    source = %Source{owner: owner, usage: %Usage{input_tokens: 2, output_tokens: 1}}
    agent = ExAgent.new(model: source, capabilities: [%ScopeSpy{owner: owner}])

    stream =
      ExAgent.run_stream(agent, "go",
        estimate_cost: fn usage -> usage.input_tokens end,
        on_progress: &send(owner, {:stream_progress, &1})
      )

    reducer = fn
      {:delta, _} = event, acc -> {:suspend, [event | acc]}
      event, acc -> {:cont, [event | acc]}
    end

    assert {:suspended, events, continuation} = Enumerable.reduce(stream, {:cont, []}, reducer)
    assert_receive {:stream_scope, scope}
    published = await_stream_usage()
    assert published.cost_cents == 2
    Process.exit(scope.pid, :kill)

    assert {status, [{:error, %RunError{partial: partial}} | ^events]} =
             continuation.({:cont, events})

    assert status in [:done, :halted]

    assert partial.usage == published.usage
    assert partial.cost_cents == 2
    assert partial.request_count == 1
    assert partial.usage_status == :partial
  end

  test "a source continuation that raises or throws after a delta finalizes once" do
    for mode <- [:raise, :throw] do
      tag = make_ref()

      events =
        Model.request_stream(
          %Source{owner: self(), tag: tag, mode: mode},
          [],
          nil,
          %ExAgent.ModelRequestParameters{}
        )
        |> Enum.to_list()

      assert [{:text_delta, "first"}, {:error, _}] = events
      assert_receive {:source_closed, ^tag, 1}
      refute_receive {:source_closed, ^tag, _}
    end
  end

  test "normal halt still finalizes the suspended source once" do
    tag = make_ref()

    stream =
      Model.request_stream(
        %Source{owner: self(), tag: tag},
        [],
        nil,
        %ExAgent.ModelRequestParameters{}
      )

    assert [{:text_delta, "first"}] = Enum.take(stream, 1)
    assert_receive {:source_closed, ^tag, 1}
    refute_receive {:source_closed, ^tag, _}
  end

  test "worker DOWN closes normally without emergency killing the guardian" do
    consumer = stream_consumer(self(), :full)
    assert_receive {:guardian, ^consumer, guardian}, 1_000
    monitor = Process.monitor(guardian)

    on_exit(fn ->
      if Process.alive?(consumer), do: Process.exit(consumer, :kill)
      if Process.alive?(guardian), do: Process.exit(guardian, :kill)
    end)

    send(consumer, :continue_stream)
    assert_receive {:DOWN, ^monitor, :process, ^guardian, :normal}, 2_000
    assert_receive {:stream_result, [{:delta, "first"}, {:error, %RunError{}}]}, 2_000
  end

  test "a consumer dying after suspended worker error does not leave its guardian alive" do
    consumer = stream_consumer(self(), :suspend_error)
    assert_receive {:guardian, ^consumer, guardian}, 1_000

    on_exit(fn ->
      if Process.alive?(consumer), do: Process.exit(consumer, :kill)
      if Process.alive?(guardian), do: Process.exit(guardian, :kill)
    end)

    monitor = Process.monitor(guardian)
    send(consumer, :continue_stream)
    assert_receive {:suspended_error, ^consumer}, 1_000
    Process.exit(consumer, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^guardian, :normal}, 1_000
  end

  defp stream_consumer(owner, mode) do
    spawn(fn ->
      stream = ExAgent.run_stream(ExAgent.new(model: %Source{owner: owner, mode: :kill}), "go")

      reducer = fn
        {:delta, _} = event, acc ->
          {:monitors, monitors} = Process.info(self(), :monitors)
          [{:process, guardian}] = monitors
          send(owner, {:guardian, self(), guardian})

          receive do
            :continue_stream -> :ok
          end

          {:cont, [event | acc]}

        {:error, _} = event, acc ->
          if mode == :suspend_error, do: {:suspend, [event | acc]}, else: {:cont, [event | acc]}
      end

      case Enumerable.reduce(stream, {:cont, []}, reducer) do
        {status, events} when status in [:done, :halted] ->
          send(owner, {:stream_result, Enum.reverse(events)})

        {:suspended, _, _continuation} ->
          send(owner, {:suspended_error, self()})

          receive do
            :never -> :ok
          end
      end
    end)
  end

  defp await_fast_progress do
    receive do
      {:progress, result} ->
        if Enum.any?(returns(result), &(&1.tool_name == "fast" and &1.status == :succeeded)),
          do: result,
          else: await_fast_progress()
    after
      2_000 -> flunk("completed fast child was not published")
    end
  end

  defp await_stream_usage do
    receive do
      {:stream_progress, %{usage: %{input_tokens: 2}} = result} -> result
      {:stream_progress, _} -> await_stream_usage()
    after
      1_000 -> flunk("stream usage was not published")
    end
  end

  defp run_mode(agent, :sync), do: ExAgent.run(agent, "go")
  defp run_mode(agent, :stream_text), do: ExAgent.run(agent, "go", stream_text: true)

  defp run_mode(agent, :public_stream) do
    case ExAgent.run_stream(agent, "go") |> Enum.to_list() |> List.last() do
      {:result, result} -> {:ok, result}
      error -> error
    end
  end

  defp call(name, args \\ %{}), do: %Part.ToolCall{tool_name: name, args: args}

  defp returns(result),
    do: Enum.filter(Message.parts(result.messages), &match?(%Part.ToolReturn{}, &1))
end
