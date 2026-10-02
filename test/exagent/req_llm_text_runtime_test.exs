defmodule ExAgent.ReqLLMTextRuntimeTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log
  alias ExAgent.{Server, Session, Store, Message, CheckpointError}
  alias ExAgent.Observability.{OpenTelemetry, BoundedProcessor}
  require Record
  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))
  @provider :req_llm_textual_test_provider
  @processor :req_llm_textual_test_processor

  defmodule Exporter do
    def init(journal), do: {:ok, journal}

    def export(table, _resource, journal) do
      Agent.update(journal, &(&1 ++ :ets.tab2list(table)))
      :ok
    end

    def shutdown(_), do: :ok
  end

  defmodule Hook do
    use ExAgent.Capability

    def before_model_request(_, state) do
      send(state.deps.owner, {:hook, :before, state.run_id})
      state
    end

    def after_model_request(_, state) do
      send(state.deps.owner, {:hook, :after, state.run_id})
      state
    end

    def before_tool_execute(_, ctx, call) do
      send(ctx.deps.owner, {:logical_hook, ctx.deps.lane, call})
      call
    end
  end

  defmodule ComposedOutput do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:value, :string)
    end

    def changeset(data, attrs) do
      data
      |> cast(attrs, [:value])
      |> validate_change(:value, fn :value, value ->
        if value == "accepted", do: [], else: [value: "requires corrective retry"]
      end)
    end
  end

  defmodule FlakyStore do
    @behaviour Store
    def save_agent_snapshot(counter, snapshot) do
      attempt = Agent.get_and_update(counter, &{&1, &1 + 1})

      if attempt == 0,
        do: {:error, :synthetic_disk_failure},
        else: ExAgent.Store.ETS.save_agent_snapshot(ExAgent.Store.ETS, snapshot)
    end

    def load_agent_snapshot(_, id),
      do: ExAgent.Store.ETS.load_agent_snapshot(ExAgent.Store.ETS, id)

    def list_agent_snapshots(_), do: ExAgent.Store.ETS.list_agent_snapshots(ExAgent.Store.ETS)

    def delete_agent_snapshot(_, id),
      do: ExAgent.Store.ETS.delete_agent_snapshot(ExAgent.Store.ETS, id)

    def save_session_snapshot(_, snapshot),
      do: ExAgent.Store.ETS.save_session_snapshot(ExAgent.Store.ETS, snapshot)

    def load_session_snapshot(_, id),
      do: ExAgent.Store.ETS.load_session_snapshot(ExAgent.Store.ETS, id)

    def delete_session_snapshot(_, id),
      do: ExAgent.Store.ETS.delete_session_snapshot(ExAgent.Store.ETS, id)
  end

  setup do
    prior = Application.get_env(:opentelemetry, :processors)
    Application.put_env(:opentelemetry, :processors, [])
    {:ok, started} = Application.ensure_all_started(:opentelemetry)

    on_exit(fn ->
      if :opentelemetry in started, do: Application.stop(:opentelemetry)

      if prior == nil,
        do: Application.delete_env(:opentelemetry, :processors),
        else: Application.put_env(:opentelemetry, :processors, prior)
    end)

    journal = start_supervised!({Agent, fn -> [] end}, id: :trace_journal)
    resource = :otel_resource.create(%{"service.name" => "synthetic-textual-integration"})

    config = %{
      sampler: :always_on,
      id_generator: :otel_id_generator,
      deny_list: [],
      processors: [
        {BoundedProcessor,
         %{
           name: @processor,
           resource: resource,
           exporter: {Exporter, journal},
           max_queue_size: 128,
           max_export_batch_size: 32,
           scheduled_delay_ms: 10,
           exporting_timeout_ms: 1000
         }}
      ]
    }

    {:ok, provider} = :otel_tracer_provider_sup.start(@provider, resource, config)
    on_exit(fn -> :supervisor.terminate_child(:otel_tracer_provider_sup, provider) end)
    wait(fn -> match?(%{status: :ready}, BoundedProcessor.stats(@processor)) end)
    tracer = :otel_tracer_provider.get_tracer(@provider, :exagent, "1", :undefined)
    %{tracing: OpenTelemetry.new(tracer: tracer), journal: journal}
  end

  test "text crosses Server and Session checkpoints, restore, hooks, compaction and one span per request",
       ctx do
    parent = self()
    count = start_supervised!({Agent, fn -> 0 end}, id: :http_count)
    saves = start_supervised!({Agent, fn -> 0 end}, id: :save_count)
    prices = :atomics.new(1, [])
    handler = "req-llm-text-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:req_llm, :request, :start],
        fn _, _, metadata, owner ->
          send(owner, {:backend_start, metadata[:model]})
        end,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    transport = fn request ->
      i = Agent.get_and_update(count, &{&1, &1 + 1})
      send(parent, {:wire, i, Jason.decode!(IO.iodata_to_binary(request.body))})
      text = Enum.fetch!(["one", "two", "three"], i)

      {request,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body:
           Jason.encode!(%{
             "id" => "text-#{i}",
             "model" => "text-integration",
             "usage" => %{"prompt_tokens" => 3, "completion_tokens" => 2, "total_tokens" => 5},
             "choices" => [
               %{
                 "index" => 0,
                 "message" => %{"role" => "assistant", "content" => text},
                 "finish_reason" => "stop"
               }
             ]
           })
       )}
    end

    model =
      ExAgent.Models.ReqLLM.new(
        model: %{
          provider: :openai,
          id: "text-integration",
          extra: %{wire: %{protocol: "openai_chat"}}
        },
        api_key: "synthetic-never-checkpoint-key",
        base_url: "https://fixture.invalid/v1",
        http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
      )

    compaction = %ExAgent.Compaction.Capability{
      compactor: ExAgent.Compaction.Summary,
      opts: [
        threshold_tokens: 0,
        keep_recent: 1,
        summarize: fn old ->
          send(parent, {:compacted, length(old)})
          "SYNTHETIC SUMMARY"
        end
      ]
    }

    agent =
      ExAgent.new(
        model: model,
        instructions: "canonical rule",
        capabilities: [Hook, compaction],
        usage_limits: %ExAgent.UsageLimits{request_limit: 1},
        observability: ctx.tracing
      )

    aid = "req-text-agent-#{System.unique_integer([:positive])}"
    sid = "req-text-session-#{System.unique_integer([:positive])}"
    store = {FlakyStore, saves}

    on_exit(fn ->
      Store.delete_agent_snapshot(store, aid)
      Store.delete_session_snapshot(store, sid)
    end)

    server =
      start_supervised!({Server, agent: agent, agent_id: aid, store: store}, id: :first_server)

    :ok = ExAgent.Test.ReqTransport.allow(server)

    session = start_session(server, sid, store, ctx.tracing, :first_session)
    assert {:ok, "worker"} = Session.start(session)

    opts = [
      deps: %{owner: parent},
      session_id: sid,
      participant_id: "worker",
      estimate_cost: fn usage ->
        :atomics.add(prices, 1, 1)
        assert {usage.input_tokens, usage.output_tokens} == {3, 2}
        0.5
      end
    ]

    assert {:error, %CheckpointError{result: {:ok, first}, revision: 1}} =
             Server.chat(server, "first", opts)

    assert first.output == "one"
    assert first.usage_status == :complete
    assert Agent.get(count, & &1) == 1

    assert :atomics.get(prices, 1) == 1
    assert {:error, %CheckpointError{}} = Server.chat(server, "must not repeat", opts)
    assert :ok = Server.checkpoint(server)
    assert Agent.get(count, & &1) == 1

    assert {:ok, _, "worker"} =
             Session.take_turn(session, "worker", fn s ->
               {:ok, %{s | "outputs" => [first.output]}}
             end)

    assert {:ok, second} = Server.chat(server, "second", opts)

    assert {:ok, _, "worker"} =
             Session.take_turn(session, "worker", fn s ->
               {:ok, %{s | "outputs" => s["outputs"] ++ [second.output]}}
             end)

    history = Server.history(server)
    assert length(history) == 4

    assert Enum.all?(
             Enum.filter(history, &is_struct(&1, Message.Response)),
             &(&1.usage.accounting["quality"] == "normalized")
           )

    assert {:ok, snapshot} = Store.load_agent_snapshot(store, aid)
    refute ExAgent.Server.Snapshot.serialize(snapshot) =~ "synthetic-never-checkpoint-key"
    assert :ok = stop_supervised(:first_session)
    assert :ok = stop_supervised(:first_server)

    restored =
      start_supervised!({Server, agent: agent, agent_id: aid, store: store}, id: :restored_server)

    :ok = ExAgent.Test.ReqTransport.allow(restored)

    resumed_session = start_session(restored, sid, store, ctx.tracing, :restored_session)
    assert Server.history(restored) == history
    assert :atomics.get(prices, 1) == 2
    assert Session.read_state(resumed_session) == %{"outputs" => ["one", "two"]}
    assert Session.current(resumed_session) == "worker"
    assert [%{ref: ^restored}] = Session.participants(resumed_session)
    assert {:ok, third} = Server.chat(restored, "third", opts)
    assert third.output == "three"

    for result <- [first, second, third] do
      assert result.request_count == 1
      assert result.usage_status == :complete
      assert result.usage.accounting["quality"] == "normalized"
      assert result.cost_status == :known
      assert result.cost_cents == 0.5
      assert_receive {:hook, :before, id}
      assert_receive {:hook, :after, ^id}
      assert_receive {:backend_start, _}
    end

    assert Agent.get(count, & &1) == 3
    assert :atomics.get(prices, 1) == 3
    assert Server.usage(restored).input_tokens == 9
    assert Server.usage(restored).output_tokens == 6
    assert Server.usage(restored).accounting["cost"]["cents"] == 1.5
    refute_receive {:backend_start, _}, 0
    refute_receive {:hook, _, _}, 0
    assert_receive {:compacted, _}

    for i <- 0..2 do
      assert_receive {:wire, ^i, body}

      assert Enum.filter(body["messages"], &(&1["role"] == "system")) == [
               %{"role" => "system", "content" => "canonical rule"}
             ]

      if i == 2, do: assert(Jason.encode!(body["messages"]) =~ "SYNTHETIC SUMMARY")
    end

    assert Enum.take(Server.history(restored), 4) == history
    refute Message.to_json(Server.history(restored)) =~ "SYNTHETIC SUMMARY"
    assert %{persistence: %{status: :confirmed, revision: 3}} = Server.health(restored)

    :ok = BoundedProcessor.force_flush(@processor)

    wait(fn ->
      stats = BoundedProcessor.stats(@processor)
      stats.accepted > 0 and stats.accepted == stats.exported
    end)

    records = Agent.get(ctx.journal, & &1)
    attrs = Enum.map(records, &:otel_attributes.map(span(&1, :attributes)))
    model_spans = Enum.filter(attrs, &(&1["exagent.operation"] == "model"))
    run_spans = Enum.filter(attrs, &(&1["exagent.operation"] == "run"))
    assert length(model_spans) == 3
    assert length(run_spans) == 3
    assert Enum.count(attrs, &(&1["gen_ai.operation.name"] == "chat")) == 3
    assert length(Enum.uniq_by(records, &span(&1, :span_id))) == length(records)
    assert Enum.count(attrs, &(&1["exagent.operation"] == "compaction")) == 3
    assert Enum.all?(model_spans, &(&1["exagent.usage.status"] == "complete"))
    assert Enum.all?(model_spans ++ run_spans, &(&1["exagent.usage.quality"] == "normalized"))
    assert Enum.all?(model_spans ++ run_spans, &(&1["exagent.cost.quality"] == "estimated"))
    assert Enum.all?(run_spans, &(&1["exagent.cost.status"] == "known"))
    assert Enum.all?(model_spans, &(not Map.has_key?(&1, "gen_ai.usage.input_tokens")))
    refute inspect(records) =~ "synthetic-never-checkpoint-key"
    assert %{export_failed: 0, dropped_invalid: 0} = BoundedProcessor.stats(@processor)
  end

  test "qualified TCP delegation and Ecto retry survive Server stream checkpoint and Session restore",
       ctx do
    owner = self()
    prices = :atomics.new(1, [])
    saves = start_supervised!({Agent, fn -> 0 end}, id: :composed_saves)

    {child_model, child_wire} =
      tcp_model("child", [tool_reply("effect", "child-call", %{"n" => 7}), text_reply()])

    effect =
      ExAgent.Tool.new(
        name: "effect",
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"n" => %{"type" => "integer"}},
          "required" => ["n"],
          "additionalProperties" => false
        },
        call: fn run, args ->
          send(owner, {:composed_effect, run.deps.lane, run.tool_call_id, args})
          "effect confirmed"
        end
      )

    child = ExAgent.new(model: child_model, tools: [effect], capabilities: [Hook])

    delegate =
      ExAgent.Tool.new(
        name: "delegate",
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{},
          "additionalProperties" => false
        },
        call: fn run, %{} ->
          assert run.deps.lane == "parent"

          {:ok, result} =
            ExAgent.run_child(run, child, "child-only",
              deps: %{owner: owner, lane: "child"},
              stream_text: true
            )

          send(owner, {:child_result, result})
          result.output
        end
      )

    {parent_model, parent_wire} =
      tcp_model("parent", [
        tool_reply("delegate", "parent-call", %{}),
        tool_reply("final_result", "invalid-output", %{"value" => "rejected"}),
        tool_reply("final_result", "valid-output", %{"value" => "accepted"}),
        tool_reply("final_result", "restored-output", %{"value" => "accepted"})
      ])

    agent =
      ExAgent.new(
        model: parent_model,
        tools: [delegate],
        output_type: ComposedOutput,
        capabilities: [Hook],
        observability: ctx.tracing,
        usage_limits: %ExAgent.UsageLimits{
          request_limit: 5,
          tool_calls_limit: 2,
          accounting: :estimated,
          total_tokens_limit: 100
        }
      )

    aid = "composed-agent-#{System.unique_integer([:positive])}"
    sid = "composed-session-#{System.unique_integer([:positive])}"
    store = {FlakyStore, saves}

    on_exit(fn ->
      Store.delete_agent_snapshot(store, aid)
      Store.delete_session_snapshot(store, sid)
    end)

    server =
      start_supervised!({Server, agent: agent, agent_id: aid, store: store}, id: :composed_server)

    session = start_session(server, sid, store, ctx.tracing, :composed_session)
    assert {:ok, "worker"} = Session.start(session)

    opts = [
      deps: %{owner: owner, lane: "parent"},
      stream_text: true,
      session_id: sid,
      participant_id: "worker",
      estimate_cost: fn priced_model, usage ->
        assert {usage.input_tokens, usage.output_tokens} == {3, 2}
        assert priced_model in [parent_model, child_model]
        send(owner, {:priced_lane, if(priced_model == parent_model, do: :parent, else: :child)})
        :atomics.add(prices, 1, 1)
        0.5
      end
    ]

    assert {:error, %CheckpointError{result: {:ok, first}, revision: 1}} =
             Server.chat(server, "parent-only", opts)

    assert first.output == %ComposedOutput{value: "accepted"}
    assert {first.request_count, first.tool_calls} == {5, 2}
    assert {first.usage.input_tokens, first.usage.output_tokens} == {15, 10}
    assert first.usage.accounting["quality"] == "normalized"
    assert first.cost_cents == 2.5
    # Pricing is per operation and ancestor: parent3 + child2 * two ancestors.
    assert :atomics.get(prices, 1) == 7
    for _ <- 1..3, do: assert_receive({:priced_lane, :parent})
    for _ <- 1..4, do: assert_receive({:priced_lane, :child})
    refute_receive {:priced_lane, _}, 0
    assert_receive {:child_result, %{request_count: 2, tool_calls: 1}}
    assert_receive {:composed_effect, "child", "child-call", %{"n" => 7}}

    assert_receive {:logical_hook, "parent",
                    %Message.Part.ToolCall{tool_call_id: "parent-call", args: %{}}}

    assert_receive {:logical_hook, "child",
                    %Message.Part.ToolCall{tool_call_id: "child-call", args: %{"n" => 7}}}

    assert {:error, %CheckpointError{}} = Server.chat(server, "blocked", opts)
    assert :ok = Server.checkpoint(server)
    assert :atomics.get(prices, 1) == 7

    assert {:ok, _, "worker"} =
             Session.take_turn(session, "worker", fn state ->
               {:ok, %{state | "outputs" => [first.output.value]}}
             end)

    history = Server.history(server)
    assert {:ok, ^history} = Message.from_json(Message.to_json(history))
    assert {:ok, snapshot} = Store.load_agent_snapshot(store, aid)
    assert snapshot.version == 4
    refute ExAgent.Server.Snapshot.serialize(snapshot) =~ "synthetic-composed-key"
    assert :ok = stop_supervised(:composed_session)
    assert :ok = stop_supervised(:composed_server)

    restored =
      start_supervised!({Server, agent: agent, agent_id: aid, store: store},
        id: :composed_restored
      )

    resumed = start_session(restored, sid, store, ctx.tracing, :composed_session_restored)
    assert Server.history(restored) == history
    assert Server.usage(restored).input_tokens == 15
    assert :atomics.get(prices, 1) == 7
    assert Session.read_state(resumed) == %{"outputs" => ["accepted"]}
    assert [%{ref: ^restored}] = Session.participants(resumed)
    assert {:ok, second} = Server.chat(restored, "new-turn", opts)
    assert {second.request_count, second.tool_calls} == {1, 0}
    assert :atomics.get(prices, 1) == 8
    assert_receive {:priced_lane, :parent}
    refute_receive {:priced_lane, _}, 0
    assert Server.usage(restored).input_tokens == 18
    assert Server.usage(restored).accounting["cost"]["cents"] == 3.0
    refute_receive {:composed_effect, _, _, _}, 0

    for i <- 0..3 do
      assert_receive {:composed_wire, ^parent_wire, ^i, payload}, 5000
      assert payload["model"] == "parent"
      assert payload["stream"] == true
      assert payload["tool_choice"] == "required"
      refute Jason.encode!(payload) =~ "child-only"
      if i >= 1, do: assert_wire_call(payload, "parent-call", %{})
      if i >= 2, do: assert_wire_call(payload, "invalid-output", %{"value" => "rejected"})
    end

    for i <- 0..1 do
      assert_receive {:composed_wire, ^child_wire, ^i, payload}, 5000
      assert payload["model"] == "child"
      assert payload["tool_choice"] == "auto"
      refute Jason.encode!(payload) =~ "parent-only"
      if i == 1, do: assert_wire_call(payload, "child-call", %{"n" => 7})
    end

    refute_receive {:composed_wire, _, _, _}, 0
    :ok = BoundedProcessor.force_flush(@processor)

    wait(fn ->
      stats = BoundedProcessor.stats(@processor)
      stats.accepted > 0 and stats.accepted == stats.exported
    end)

    attrs =
      Agent.get(
        ctx.journal,
        &Enum.map(&1, fn s -> :otel_attributes.map(span(s, :attributes)) end)
      )

    generations = Enum.filter(attrs, &(&1["gen_ai.operation.name"] == "chat"))
    assert length(generations) == 6
    assert Enum.all?(generations, &(&1["exagent.usage.quality"] == "normalized"))
    assert Enum.all?(generations, &(&1["exagent.cost.quality"] == "estimated"))
    assert Enum.all?(generations, &(&1["exagent.usage.normalized_input_tokens"] == 3))
    assert Enum.all?(generations, &(&1["exagent.usage.provider_presence"] == "unknown"))
    assert Enum.all?(generations, &(&1["exagent.usage.input_tokens_semantics"] == "inclusive"))
    assert Enum.all?(generations, &(&1["gen_ai.usage.output_tokens"] == 2))
    refute inspect(attrs) =~ "synthetic-composed-key"
  end

  test "Server public stream keeps ancestor denial and normalized unavailable cost in events and OTel",
       ctx do
    owner = self()

    {child_model, child_peer} =
      tcp_model("denied-child", [tool_reply("effect", "denied-call", %{}), text_reply()])

    effect =
      ExAgent.Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :forbidden_effect)
          "must not happen"
        end
      )

    child = ExAgent.new(model: child_model, tools: [effect])

    delegate =
      ExAgent.Tool.new(
        name: "delegate",
        parameters_json_schema: %{"type" => "object"},
        call: fn run, _ ->
          {:ok, result} =
            ExAgent.run_child(run, child, "restricted-child",
              stream_text: true,
              permissions: ExAgent.Permissions.new!(default: :allow)
            )

          send(owner, {:denied_child, result})
          result.output
        end
      )

    {parent_model, parent_peer} =
      tcp_model("denied-parent", [tool_reply("delegate", "delegate-call", %{}), text_reply()])

    agent =
      ExAgent.new(
        model: parent_model,
        tools: [delegate],
        observability: ctx.tracing,
        usage_limits: %ExAgent.UsageLimits{request_limit: 4, tool_calls_limit: 2}
      )

    aid = "denied-stream-#{System.unique_integer([:positive])}"
    server = start_supervised!({Server, agent: agent, agent_id: aid, pubsub: :local})
    :ok = ExAgent.PubSub.subscribe({ExAgent.PubSub.Local, []}, ExAgent.Event.agent_topic(aid))

    assert {:ok, request_id} =
             Server.stream(server, "restricted-parent",
               permissions:
                 ExAgent.Permissions.new!(default: :deny, rules: [{"delegate", :allow}])
             )

    assert_receive {:exagent_event,
                    %ExAgent.Event{type: :run_finished, request_id: ^request_id, payload: payload}},
                   10_000

    assert {payload.request_count, payload.tool_calls} == {4, 2}
    assert payload.usage["input_tokens"] == 12
    assert payload.usage["accounting"]["quality"] == "normalized"
    assert payload.usage["accounting"]["cost"]["availability"] == "unavailable"
    assert payload.cost_status == :unknown
    assert payload.cost_cents == nil
    assert Server.usage(server).accounting["cost"]["cents"] == nil
    assert_receive {:denied_child, child_result}
    assert {child_result.request_count, child_result.tool_calls} == {2, 1}

    returns =
      for %Message.Request{parts: parts} <- child_result.messages,
          %Message.Part.ToolReturn{} = part <- parts,
          do: part

    assert [%Message.Part.ToolReturn{tool_call_id: "denied-call", status: :denied}] = returns
    refute_receive :forbidden_effect, 0

    for peer <- [parent_peer, child_peer], i <- 0..1 do
      assert_receive {:composed_wire, ^peer, ^i, _}, 5000
    end

    refute_receive {:composed_wire, _, _, _}, 0
    :ok = BoundedProcessor.force_flush(@processor)

    wait(fn ->
      stats = BoundedProcessor.stats(@processor)
      stats.accepted > 0 and stats.accepted == stats.exported
    end)

    attrs =
      Agent.get(
        ctx.journal,
        &Enum.map(&1, fn s -> :otel_attributes.map(span(s, :attributes)) end)
      )

    generations = Enum.filter(attrs, &(&1["gen_ai.operation.name"] == "chat"))
    assert length(generations) == 4
    assert Enum.all?(generations, &(&1["exagent.usage.quality"] == "normalized"))
    assert Enum.all?(generations, &(&1["exagent.cost.quality"] == "estimated"))
    assert Enum.all?(generations, &(&1["exagent.cost.availability"] == "unavailable"))
    refute Enum.any?(generations, &Map.has_key?(&1, "exagent.cost.cents"))
  end

  defp assert_wire_call(payload, id, args) do
    calls = Enum.flat_map(payload["messages"], &(&1["tool_calls"] || []))
    assert [call] = Enum.filter(calls, &(&1["id"] == id))
    assert Jason.decode!(call["function"]["arguments"]) == %{"arguments" => args}

    assert Enum.count(payload["messages"], &(&1["role"] == "tool" and &1["tool_call_id"] == id)) ==
             1
  end

  defp tool_reply(name, id, args),
    do:
      {%{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => id,
             "type" => "function",
             "function" => %{"name" => name, "arguments" => Jason.encode!(%{"arguments" => args})}
           }
         ]
       }, "tool_calls"}

  defp text_reply, do: {%{"role" => "assistant", "content" => "child completed"}, "stop"}

  defp tcp_model(lane, replies) do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :raw,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(listener)

    peer =
      spawn(fn ->
        Enum.with_index(replies, fn {message, finish}, i ->
          {:ok, socket} = :gen_tcp.accept(listener, 10_000)
          payload = socket |> tcp_request("") |> Jason.decode!()
          send(owner, {:composed_wire, self(), i, payload})

          delta =
            Map.delete(message, "role")
            |> Map.update(
              "tool_calls",
              [],
              &Enum.with_index(&1, fn call, index -> Map.put(call, "index", index) end)
            )

          frame = fn data -> "data: " <> Jason.encode!(data) <> "\n\n" end

          bytes =
            frame.(%{
              "id" => "#{lane}-#{i}",
              "model" => lane,
              "choices" => [%{"index" => 0, "delta" => delta, "finish_reason" => nil}]
            }) <>
              frame.(%{
                "id" => "#{lane}-#{i}",
                "model" => lane,
                "choices" => [%{"index" => 0, "delta" => %{}, "finish_reason" => finish}]
              }) <>
              frame.(%{
                "choices" => [],
                "usage" => %{"prompt_tokens" => 3, "completion_tokens" => 2, "total_tokens" => 5}
              }) <> "data: [DONE]\n\n"

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n" <>
                bytes
            )

          :gen_tcp.close(socket)
        end)

        :gen_tcp.close(listener)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(peer, :kill)
    end)

    model =
      ExAgent.Models.ReqLLM.new(
        model: %{
          provider: :openai,
          id: lane,
          extra: %{wire: %{protocol: "openai_chat"}},
          capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
        },
        tool_profile: :chat_tools_v1,
        api_key: "synthetic-composed-key",
        base_url: "http://127.0.0.1:#{port}/v1",
        total_timeout: 8000
      )

    {model, peer}
  end

  defp tcp_request(socket, bytes) do
    case :binary.split(bytes, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length: (\d+)/i, headers)
        if byte_size(body) >= String.to_integer(size), do: body, else: tcp_more(socket, bytes)

      _ ->
        tcp_more(socket, bytes)
    end
  end

  defp tcp_more(socket, bytes) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5000)
    tcp_request(socket, bytes <> chunk)
  end

  defp start_session(server, sid, store, tracing, name) do
    start_supervised!(
      {Session,
       session_id: sid,
       store: store,
       observability: tracing,
       shared_state: %{"outputs" => []},
       participants: [ExAgent.Session.Participant.new(id: "worker", ref: server)]},
      id: name
    )
  end

  defp wait(fun, attempts \\ 300)
  defp wait(_fun, 0), do: flunk("bounded condition did not settle")

  defp wait(fun, n),
    do:
      if(fun.(),
        do: :ok,
        else:
          (
            Process.sleep(5)
            wait(fun, n - 1)
          )
      )
end
