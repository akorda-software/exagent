defmodule ExAgent.RetentionContractTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Message, RunError, Server, Tool}
  alias ExAgent.Message.{Part, Request, Response, Usage}

  defmodule Model do
    @behaviour ExAgent.Model
    defstruct [:journal, script: [], deltas: []]
    def model_name(_), do: "retention-fixture"
    def system(_), do: "test"
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}

    def request(m, history, _, _) do
      Agent.update(m.journal, &[{:request, self()} | &1])
      [r | rest] = m.script

      r =
        cond do
          is_function(r, 0) -> r.()
          is_function(r, 1) -> r.(history)
          true -> r
        end

      case r do
        {:error, _} = error -> error
        _ -> {:ok, r, %{m | script: rest}}
      end
    end

    def request_stream(m, history, settings, params) do
      Stream.resource(
        fn ->
          case request(m, history, settings, params) do
            {:ok, r, next} -> m.deltas ++ [{:response, r, next}]
            {:error, _} = error -> [error]
          end
        end,
        fn
          [] -> {:halt, []}
          [x | rest] -> {[x], rest}
        end,
        fn _ -> Agent.update(m.journal, &[:closed | &1]) end
      )
    end
  end

  defmodule InflateModel do
    use ExAgent.Capability

    def after_model_request(_, state) do
      r = List.last(state.messages)

      %{
        state
        | messages:
            List.replace_at(state.messages, -1, %{
              r
              | parts: [%Part.Text{content: String.duplicate("x", 100_000)}]
            })
      }
    end
  end

  defmodule InflateTool do
    use ExAgent.Capability

    def after_tool_execute(_, _, _, {:ok, part}),
      do: {:ok, %{part | content: String.duplicate("x", 100_000)}}

    def after_tool_execute(_, _, _, other), do: other
  end

  defmodule TimeoutAfterTool do
    use ExAgent.Capability

    def after_tool_execute(_, _, %{tool_call_id: "confirmed-timeout"}, _) do
      receive do
        :never -> :never
      end
    end

    def after_tool_execute(_, _, _, result), do: result
  end

  defmodule InflateError do
    use ExAgent.Capability
    def after_tool_execute(_, _, _, _), do: {:error, String.duplicate("private", 20_000)}
  end

  defmodule Events do
    @behaviour ExAgent.PubSub
    def subscribe(_, _), do: :ok
    def broadcast(owner, _, event), do: send(owner, {:retention_event, event}) && :ok
  end

  setup do
    {:ok, journal} = Agent.start_link(fn -> [] end)
    %{journal: journal}
  end

  defp response(parts),
    do: %Response{parts: parts, usage: Usage.qualify(%Usage{input_tokens: 2, output_tokens: 3})}

  defp text(text), do: response([%Part.Text{content: text}])
  defp call(id), do: %Part.ToolCall{tool_name: "effect", tool_call_id: id, args: %{}}

  defp agent(journal, responses, value, opts \\ []) do
    tool =
      Tool.new(
        name: "effect",
        takes_ctx: false,
        parameters_json_schema: %{"type" => "object", "properties" => %{}},
        call: fn _ ->
          Agent.update(journal, &[:effect | &1])
          if is_function(value, 0), do: value.(), else: {:ok, value}
        end
      )

    ExAgent.new(
      Keyword.merge([model: %Model{journal: journal, script: responses}, tools: [tool]], opts)
    )
  end

  defp count(journal, type),
    do:
      Enum.count(Agent.get(journal, & &1), fn
        {^type, _} -> true
        ^type -> true
        _ -> false
      end)

  defp returns(partial),
    do: Enum.filter(Message.parts(partial.messages), &is_struct(&1, Part.ToolReturn))

  defp public(partial), do: Map.delete(partial, :model)
  defp size(x), do: :erlang.external_size(x)
  defp terminal(agent, :sync, opts), do: ExAgent.run(agent, "go", opts)

  defp terminal(agent, :stream_text, opts),
    do: ExAgent.run(agent, "go", [stream_text: true] ++ opts)

  defp terminal(agent, :stream, opts) do
    case Enum.to_list(ExAgent.run_stream(agent, "go", opts)) |> List.last() do
      {:result, value} -> {:ok, value}
      {:error, error} -> {:error, error}
    end
  end

  test "Response exact serialized limit succeeds and one extra byte rejects before tools", %{
    journal: j
  } do
    r = text("ok")
    a = agent(j, [r], nil)
    assert {:ok, %{output: "ok"}} = ExAgent.run(a, "go", max_payload_bytes: size(r))

    assert {:error,
            %RunError{reason: {:retention_limit_exceeded, %{boundary: :response}}, partial: p}} =
             ExAgent.run(a, "go", max_payload_bytes: size(r) - 1)

    assert p.request_count == 1
    assert p.pending_response.payload_omitted["version"] == 1
    assert p.pending_response.parts == []

    r = response([call("effect-1"), %Part.Text{content: String.duplicate("s", 10_000)}])

    assert {:error, %RunError{}} =
             ExAgent.run(agent(j, [r], "done"), "go", max_payload_bytes: 5000)

    assert count(j, :effect) == 0
  end

  test "one confirmed oversized effect is omitted, bounded and never replayed across surfaces", %{
    journal: j
  } do
    for surface <- [:sync, :stream_text, :stream] do
      a =
        agent(
          j,
          [response([call("effect-1")]), text("must not happen")],
          String.duplicate("secret", 20_000),
          max_payload_bytes: 8192,
          max_history_bytes: 16_384
        )

      assert {:error, %RunError{reason: {:retention_limit_exceeded, _}, partial: p}} =
               terminal(a, surface, [])

      assert [
               %Part.ToolReturn{
                 status: :succeeded,
                 content: nil,
                 tool_call_id: "effect-1",
                 payload_omitted: marker
               }
             ] = returns(p)

      assert marker["boundary"] == "tool_return"
      assert p.request_count == 1
      assert p.usage.input_tokens == 2
      assert size(p.messages) <= 16_384
      assert size(public(p)) <= 2 * 16_384 + 8192 + 65_536
      refute inspect(public(p)) =~ "secret"

      assert {:error, %RunError{reason: :omitted_payload_history}} =
               ExAgent.run(a, "again", message_history: p.messages)
    end

    assert count(j, :effect) == 3
    assert count(j, :request) == 3
    assert count(j, :closed) == 2
  end

  test "canonical history reservation rejects batch before any effect", %{journal: j} do
    a = agent(j, [response([call("a"), call("b")])], "small", max_history_bytes: 1024)

    assert {:error,
            %RunError{reason: {:retention_limit_exceeded, %{boundary: :history}}, partial: p}} =
             ExAgent.run(a, "go")

    assert p.tool_calls == 0
    assert count(j, :effect) == 0
    assert size(p.messages) <= 1024
  end

  test "parallel oversized outcomes retain every confirmed identity under aggregate H", %{
    journal: j
  } do
    a =
      agent(j, [response(Enum.map(1..4, &call("call-#{&1}")))], String.duplicate("x", 32_000),
        max_payload_bytes: 16_384,
        max_history_bytes: 24_576
      )

    assert {:error, %RunError{partial: p}} = ExAgent.run(a, "go")
    assert count(j, :effect) == 4
    assert count(j, :request) == 1
    assert Enum.map(returns(p), & &1.tool_call_id) == Enum.map(1..4, &"call-#{&1}")
    assert Enum.all?(returns(p), &(&1.status == :succeeded && &1.payload_omitted))
    assert size(p.messages) <= 24_576
  end

  test "after hooks cannot inflate retained output or erase a confirmed effect", %{journal: j} do
    a =
      agent(j, [response([call("model-hook")])], "ok",
        capabilities: [InflateModel],
        max_payload_bytes: 8192
      )

    assert {:error, %RunError{reason: {:retention_limit_exceeded, _}}} = ExAgent.run(a, "go")
    assert count(j, :effect) == 0

    a =
      agent(j, [response([call("tool-hook")])], "ok",
        capabilities: [InflateTool],
        max_payload_bytes: 8192
      )

    assert {:error, %RunError{partial: p}} = ExAgent.run(a, "go")

    assert [%Part.ToolReturn{status: :succeeded, content: nil, payload_omitted: marker}] =
             returns(p)

    assert marker["bytes"] > 8192
    assert count(j, :effect) == 1
  end

  test "oversized usage drops details explicitly while preserving known metrics and source", %{
    journal: j
  } do
    usage = %Usage{
      input_tokens: 7,
      output_tokens: 9,
      details: %{"private" => String.duplicate("secret", 2000)}
    }

    a = agent(j, [%{text("ok") | usage: usage}], nil)

    assert {:error,
            %RunError{reason: {:retention_limit_exceeded, %{boundary: :usage}}, partial: p}} =
             ExAgent.run(a, "go")

    assert p.usage.input_tokens == 7
    assert p.usage.output_tokens == 9
    assert p.usage.accounting["quality"] == "reported"
    assert p.usage.payload_omitted["version"] == 1
    assert size(p.usage) <= 4096
    refute inspect(public(p)) =~ "secret"
  end

  test "oversized tool usage preserves confirmed effect without another model request", %{
    journal: j
  } do
    usage = %Usage{
      input_tokens: 7,
      output_tokens: 9,
      details: %{"private" => String.duplicate("x", 5000)}
    }

    a = agent(j, [response([call("u")])], fn -> {:ok, "ok", usage} end, max_payload_bytes: 16_384)
    assert {:error, %RunError{partial: p}} = ExAgent.run(a, "go")
    assert [%Part.ToolReturn{status: :succeeded, usage: u}] = returns(p)
    assert u.payload_omitted["version"] == 1
    assert p.usage.input_tokens == 9
    assert p.usage.output_tokens == 12
    assert count(j, :effect) == 1
    assert count(j, :request) == 1
  end

  test "omission survives JSON and snapshot4; restore never executes omitted history", %{
    journal: j
  } do
    a =
      agent(j, [response([call("stored")])], String.duplicate("x", 20_000),
        max_payload_bytes: 8192
      )

    assert {:error, %RunError{partial: p}} = ExAgent.run(a, "go")
    json = Message.to_json(p.messages)
    assert json =~ "tool_return_omitted_v1"
    assert {:ok, messages} = Message.from_json(json)
    assert List.last(messages).parts |> hd() |> Map.fetch!(:payload_omitted)
    snapshot = ExAgent.Server.Snapshot.new(agent_id: "bounded", history: messages, usage: p.usage)
    assert snapshot.version == 4

    assert {:ok, restored} =
             snapshot
             |> ExAgent.Server.Snapshot.serialize()
             |> ExAgent.Server.Snapshot.deserialize()

    assert {:ok, messages} = ExAgent.Server.Snapshot.messages(restored)

    assert {:error, %RunError{reason: :omitted_payload_history}} =
             ExAgent.run(a, "go", message_history: messages)

    assert count(j, :effect) == 1
    assert {:error, _} = Message.from_json(String.replace(json, "\"version\":1", "\"version\":2"))
  end

  test "Server current-run history is bounded with the confirmed outcome", %{journal: j} do
    a =
      agent(j, [response([call("server")])], String.duplicate("x", 65_536),
        max_payload_bytes: 8192
      )

    {:ok, server} = Server.start_link(agent: a, max_history_bytes: 16_384)
    on_exit(fn -> if Process.alive?(server), do: GenServer.stop(server) end)
    assert {:error, %RunError{partial: p}} = Server.chat(server, "go")
    assert size(Server.history(server)) <= 16_384
    assert returns(p) |> hd() |> Map.fetch!(:status) == :succeeded
    assert count(j, :effect) == 1
    assert count(j, :request) == 1
  end

  test "custom streaming is bounded before publishing oversized deltas and cleans up", %{
    journal: j
  } do
    m = %Model{
      journal: j,
      script: [text("done")],
      deltas: [{:text_delta, String.duplicate("secret", 20_000)}]
    }

    a = ExAgent.new(model: m)

    assert [
             {:error,
              %RunError{reason: {:retention_limit_exceeded, %{boundary: :stream}}, partial: p}}
           ] = Enum.to_list(ExAgent.run_stream(a, "go"))

    assert count(j, :closed) == 1
    refute inspect(public(p)) =~ "secret"
  end

  test "input external size boundary is exact and rejected history never reaches Model", %{
    journal: j
  } do
    history = [%Request{parts: [%Part.User{content: String.duplicate("x", 1000)}]}]
    a = agent(j, [text("ok")], nil)

    assert {:error,
            %RunError{reason: {:retention_limit_exceeded, %{boundary: :input}}, partial: p}} =
             ExAgent.run(a, "go", message_history: history, max_history_bytes: 1000)

    assert p.messages == []
    assert p.request_count == 0
    assert count(j, :request) == 0
  end

  test "ToolReturn exact P boundary and +1 preserve effect status", %{journal: j} do
    value = String.duplicate("x", 5000)
    part = %Part.ToolReturn{tool_name: "effect", tool_call_id: "exact", content: value}
    p = size(part)
    a = agent(j, [response([call("exact")]), text("done")], value)
    assert {:ok, result} = ExAgent.run(a, "go", max_payload_bytes: p)
    assert [%Part.ToolReturn{content: ^value, payload_omitted: nil}] = returns(result)
    assert {:error, %RunError{partial: partial}} = ExAgent.run(a, "go", max_payload_bytes: p - 1)

    assert [%Part.ToolReturn{status: :succeeded, content: nil, payload_omitted: marker}] =
             returns(partial)

    assert marker["bytes"] == p
    assert marker["limit"] == p - 1
    assert count(j, :effect) == 2
  end

  test "mixed parallel completion, multiple oversized returns and timeout preserve all outcomes",
       %{journal: j} do
    calls = Enum.map(["big-a", "big-b", "small", "confirmed-timeout", "uncertain"], &call/1)

    tool =
      Tool.new(
        name: "effect",
        takes_ctx: true,
        parameters_json_schema: %{"type" => "object", "properties" => %{}},
        call: fn ctx, _ ->
          Agent.update(j, &[{:effect_id, ctx.tool_call_id} | &1])

          case ctx.tool_call_id do
            "uncertain" ->
              receive do
                :never -> :never
              end

            "big-" <> _ ->
              {:ok, String.duplicate("x", 50_000)}

            _ ->
              {:ok, "small"}
          end
        end
      )

    a =
      ExAgent.new(
        model: %Model{journal: j, script: [response(calls)]},
        tools: [tool],
        tool_timeout: 100,
        max_history_bytes: 40_960,
        max_payload_bytes: 8192,
        capabilities: [TimeoutAfterTool]
      )

    assert {:error, %RunError{partial: p}} = ExAgent.run(a, "go")

    assert Enum.map(returns(p), &{&1.tool_call_id, &1.status}) ==
             [
               {"big-a", :succeeded},
               {"big-b", :succeeded},
               {"small", :succeeded},
               {"confirmed-timeout", :succeeded},
               {"uncertain", :unknown}
             ]

    assert Enum.count(returns(p), & &1.payload_omitted) == 2
    assert count(j, :effect_id) == 5
    assert count(j, :request) == 1
    assert p.tool_calls == 5
    assert size(p.messages) <= 40_960
  end

  test "Usage exact 4096 boundary succeeds and +1 omits only arbitrary details", %{journal: j} do
    base = Usage.qualify(%Usage{input_tokens: 4, output_tokens: 6, details: %{"padding" => ""}})
    padding = 4096 - size(base)
    usage = %{base | details: %{"padding" => String.duplicate("x", padding)}}
    assert size(usage) == 4096
    a = agent(j, [%{text("ok") | usage: usage}], nil)
    assert {:ok, p} = ExAgent.run(a, "go")
    assert p.usage.payload_omitted == nil
    usage = %{usage | details: %{"padding" => String.duplicate("x", padding + 1)}}

    assert {:error, %RunError{partial: p}} =
             ExAgent.run(agent(j, [%{text("ok") | usage: usage}], nil), "go")

    assert p.usage.input_tokens == 4
    assert p.usage.payload_omitted["bytes"] == 4097
    assert p.usage.accounting["availability"]["input"] == "available"
  end

  test "oversized numeric dimension becomes unavailable, never observed zero", %{journal: j} do
    usage = %Usage{input_tokens: Integer.pow(2, 40_000), output_tokens: 3}

    assert {:error, %RunError{partial: p}} =
             ExAgent.run(agent(j, [%{text("ok") | usage: usage}], nil), "go")

    assert p.usage.input_tokens == nil
    assert p.usage.output_tokens == 3
    assert p.usage.accounting["availability"]["input"] == "unavailable"
    assert p.usage.accounting["availability"]["output"] == "available"
    assert p.usage.payload_omitted
    assert p.request_count == 1
    assert size(p.usage) <= 4096
  end

  test "current partial and terminal projections expose exact measured bytes", %{journal: j} do
    parent = self()
    a = agent(j, [response([call("measure")]), text("done")], "small")
    assert {:ok, p} = ExAgent.run(a, "go", on_progress: &send(parent, {:progress, &1}))
    data = Map.take(p, [:output, :messages, :new_messages, :pending_response, :usage])
    assert p.retention.data_bytes == size(data)
    assert p.retention.history_bytes == size(p.messages)
    assert p.retention.measurement == :erlang_external_term
    assert_receive {:progress, progress}

    assert progress.retention.data_bytes <=
             2 * progress.retention.max_history_bytes +
               progress.retention.max_payload_bytes + progress.retention.control_reserve_bytes
  end

  test "aggregate canonical history exact H and +1 are independent of individual P", %{journal: j} do
    target = 4096

    fill = fn messages ->
      base = text("")
      padding = target - size(messages ++ [base])
      %{base | parts: [%Part.Text{content: String.duplicate("x", padding)}]}
    end

    a = agent(j, [fill], nil)
    assert {:ok, p} = ExAgent.run(a, "go", max_history_bytes: target)
    assert size(p.messages) == target

    assert {:error,
            %RunError{reason: {:retention_limit_exceeded, %{boundary: :history}}, partial: p}} =
             ExAgent.run(a, "go", max_history_bytes: target - 1)

    assert size(p.messages) <= target - 1
    assert count(j, :effect) == 0
  end

  test "oversized after-hook errors never retain original and confirmed content survives", %{
    journal: j
  } do
    a = agent(j, [response([call("error")])], "confirmed", capabilities: [InflateError])

    assert {:error,
            %RunError{reason: {:retention_limit_exceeded, %{boundary: :error}}, partial: p} =
              error} = ExAgent.run(a, "go")

    assert [%Part.ToolReturn{status: :succeeded, content: "confirmed"}] = returns(p)
    refute inspect(%{error | partial: public(p)}) =~ "private"
    assert count(j, :effect) == 1
    assert count(j, :request) == 1
  end

  test "incomplete partial oversized Response and unknown terminal never authorize tools", %{
    journal: j
  } do
    for surface <- [:sync, :stream_text, :stream] do
      r = response([call("never"), %Part.Text{content: String.duplicate("private", 10_000)}])

      error = %ExAgent.RequestError{
        provider: :test,
        reason: :incomplete_stream,
        partial_response: r
      }

      a = agent(j, [{:error, error}], "must not happen", max_payload_bytes: 8192)
      assert {:error, %RunError{partial: p}} = terminal(a, surface, [])
      assert p.pending_response.payload_omitted
      assert p.usage_status == :partial
      assert p.usage.input_tokens == 2
      refute inspect(public(p)) =~ "private"
      a = agent(j, [%{response([call("unknown")]) | finish_reason: :unknown}], "bad")

      assert {:error, %RunError{reason: {:incomplete_model_response, :unknown}}} =
               terminal(a, surface, [])
    end

    assert count(j, :effect) == 0
    assert count(j, :request) == 6
  end

  test "Server stream persists omission through real ETS bytes and restored template cannot replay",
       %{journal: j} do
    table = :ets.new(:retention_restore, [:set, :public])

    a =
      agent(j, [response([call("persisted")])], String.duplicate("private", 10_000),
        max_payload_bytes: 8192
      )

    opts = [
      agent: a,
      agent_id: "bounded",
      store: {ExAgent.Store.ETS, table},
      pubsub: {Events, self()},
      max_history_bytes: 16_384
    ]

    {:ok, server} = Server.start_link(opts)
    assert {:ok, id} = Server.stream(server, "go")

    assert_receive {:retention_event,
                    %ExAgent.Event{type: :run_failed, request_id: ^id, payload: payload}},
                   1000

    assert ["retention_limit_exceeded", %{boundary: "tool_return", bytes: bytes, limit: limit}] =
             payload.reason

    assert bytes > limit
    assert size(payload) <= 16 * (2 * 16_384 + 8192 + 65_536)
    assert size(Server.history(server)) <= 16_384

    assert {:ok, snapshot} =
             ExAgent.Store.load_agent_snapshot({ExAgent.Store.ETS, table}, "bounded")

    assert snapshot.version == 4
    refute snapshot.message_history =~ "private"
    GenServer.stop(server)
    {:ok, restored} = Server.start_link(opts)

    assert {:error, %RunError{reason: :omitted_payload_history, partial: p}} =
             Server.chat(restored, "resume")

    assert [%Part.ToolReturn{status: :succeeded, payload_omitted: marker}] = returns(p)
    assert marker["version"] == 1
    assert p.request_count == 0
    assert count(j, :effect) == 1
    assert count(j, :request) == 1
    GenServer.stop(restored)
  end

  test "oversized estimator result is unavailable and marked without repricing", %{journal: j} do
    estimator = fn _ ->
      Agent.update(j, &[:price | &1])
      Integer.pow(2, 40_000)
    end

    a = agent(j, [text("ok")], nil)

    assert {:error,
            %RunError{reason: {:retention_limit_exceeded, %{boundary: :usage}}, partial: p}} =
             ExAgent.run(a, "go", estimate_cost: estimator)

    assert p.usage.input_tokens == 2
    assert p.cost_cents == nil
    assert p.cost_status == :unknown
    assert p.usage.accounting["cost"]["source"] == "estimator"
    assert p.usage.accounting["cost"]["availability"] == "unavailable"
    assert p.usage.payload_omitted
    assert count(j, :price) == 1

    assert {:error, %RunError{reason: :omitted_payload_history}} =
             ExAgent.run(a, "again", message_history: p.messages, estimate_cost: estimator)

    assert count(j, :price) == 1
    assert count(j, :request) == 1
  end

  test "canonical aliases and large metrics that fit survive arbitrary metadata omission", %{
    journal: j
  } do
    large = Integer.pow(2, 16_000)

    usage = %Usage{
      input_tokens: large,
      output_tokens: 3,
      details: %{"cache_read_input_tokens" => 7, "private" => String.duplicate("x", 5000)}
    }

    assert {:error, %RunError{partial: p}} =
             ExAgent.run(agent(j, [%{text("ok") | usage: usage}], nil), "go")

    assert p.usage.input_tokens == large
    assert p.usage.output_tokens == 3
    assert p.usage.details["cached_tokens"] == 7
    assert p.usage.accounting["availability"]["cache_read"] == "available"
    assert p.usage.accounting["availability"]["input"] == "available"
    assert size(p.usage) <= 4096
  end

  test "separately bounded request metrics cannot overflow retained Scope or Server aggregates",
       %{journal: j} do
    large = Integer.pow(2, 20_000)
    first = %Usage{input_tokens: large, output_tokens: nil}
    last = %Usage{input_tokens: nil, output_tokens: large}
    assert size(Usage.qualify(first)) < 4096
    assert size(Usage.qualify(last)) < 4096

    a =
      agent(
        j,
        [%{response([call("aggregate")]) | usage: first}, %{text("done") | usage: last}],
        "ok"
      )

    assert {:error,
            %RunError{reason: {:retention_limit_exceeded, %{boundary: :usage}}, partial: p}} =
             ExAgent.run(a, "go")

    assert p.request_count == 2
    assert p.usage.input_tokens == large
    assert p.usage.output_tokens == nil
    assert p.usage_status == :partial
    assert size(p.usage) <= 4096
    assert [%Part.ToolReturn{status: :succeeded, content: "ok"}] = returns(p)

    a = agent(j, [%{text("first") | usage: first}, %{text("last") | usage: last}], nil)
    {:ok, server} = Server.start_link(agent: a)
    assert {:ok, %{output: "first"}} = Server.chat(server, "one")

    assert {:error,
            %RunError{reason: {:retention_limit_exceeded, %{boundary: :usage}}, partial: p}} =
             Server.chat(server, "two")

    assert p.output == "last"
    assert size(Server.usage(server)) <= 4096
    assert Server.usage(server).payload_omitted
    assert {:error, {:retention_limit_exceeded, _}} = Server.chat(server, "again")
    assert count(j, :request) == 4
    assert count(j, :effect) == 1
    GenServer.stop(server)
  end
end
