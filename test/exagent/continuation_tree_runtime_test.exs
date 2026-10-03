defmodule ExAgent.ContinuationTreeRuntimeTest do
  use ExUnit.Case, async: false

  alias ExAgent.{
    Continuation,
    Coordination,
    Event,
    Message,
    Permissions,
    Server,
    Session,
    Store,
    Tool
  }

  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Session.Participant
  alias ExAgent.ContinuationNativeFixture.CountOutput

  defmodule OtherOutput do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:other, :integer)
    end

    def changeset(data, args), do: data |> cast(args, [:other]) |> validate_required([:other])
  end

  defmodule NativeModel do
    @behaviour ExAgent.Model
    defstruct [:owner, script: [], index: 0]
    def model_name(_), do: "native-tree"
    def system(_), do: "synthetic"

    def profile(_),
      do: %ExAgent.ModelProfile{supports_tools: true, supports_json_schema_output: true}

    def validate_resume(_, _, _, _), do: :ok

    def request(model, messages, settings, params) do
      send(model.owner, {:native_mode, params.output_mode})

      {:ok, response, next} =
        ExAgent.Models.Test.request(
          %ExAgent.Models.Test{script: model.script, index: model.index},
          messages,
          settings,
          params
        )

      {:ok, response, %{model | index: next.index}}
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})

    %{
      store: {Store.ETS, __MODULE__},
      scoped: Store.scoped({Store.ETS, __MODULE__}, "tree-runtime")
    }
  end

  test "delegated Server stream pauses after ACK and drains its retained queue only after correlated resume",
       %{store: store} do
    :ok =
      ExAgent.PubSub.subscribe(
        {ExAgent.PubSub.Local, []},
        Event.agent_topic("agent", "tree-runtime")
      )

    server =
      start_supervised!({Server, server_options(store, self()) ++ [pubsub: ExAgent.PubSub.Local]})

    {:ok, request_id} = Server.stream(server, "first")

    assert_receive {:exagent_event,
                    %Event{type: :run_paused, request_id: ^request_id, run_id: run_id}},
                   2_000

    assert Server.health(server).status == :paused
    {:ok, %{status: :pending, record: record}} = Server.continuation(server)
    assert map_size(record["execution"]["progress"]["runtime"]["children"]) == 1
    assert_receive {:effect, "sibling"}
    refute_receive {:effect, "child-effect"}
    refute_receive {:exagent_event, %Event{type: :run_finished}}
    assert {:error, :continuation_pending} = Server.reset(server)
    assert {:ok, _} = Server.send_message(server, "queued")
    assert Server.health(server).pending == 1
    {:ok, _} = Server.decide(server, :approve, decision(record))

    assert {:ok, %{status: :succeeded, run_id: ^run_id, request_count: 4, tool_calls: 3}} =
             Server.resume(server, stream_text: true)

    assert_receive {:effect, "child-effect"}

    assert_receive {:exagent_event,
                    %Event{
                      type: :run_finished,
                      request_id: ^request_id,
                      run_id: ^run_id,
                      payload: %{output: "root done"}
                    }},
                   2_000

    assert_receive {:exagent_event, %Event{type: :run_finished, payload: %{output: "queued"}}},
                   2_000

    assert Server.health(server).status == :idle
    assert Server.usage(server).input_tokens == 5
    refute_receive {:effect, _}
  end

  test "bound Session and Server restart keep a child pending and complete the logical turn once",
       %{store: store, scoped: scoped} do
    server_opts = server_options(store, self())
    {:ok, server} = Server.start_link(server_opts)

    opts = [
      session_id: "session",
      namespace: "tree-runtime",
      store: store,
      participants: [Participant.new(id: "worker", kind: :agent, ref: :host_handle)],
      shared_state: %{"count" => 0},
      continuations: %{"worker" => %{store: scoped, id: "agent"}}
    ]

    {:ok, session} = Session.start_link(opts)
    {:ok, "worker"} = Session.start(session)

    assert {:error, {:session_continuation_pending, "worker", _}} =
             Session.take_turn(session, "worker", fn _ -> Server.chat(server, "first") end)

    assert Session.read_state(session) == %{"count" => 0}
    assert {:error, {:session_continuation_pending, _, _}} = Session.end_turn(session, "worker")
    assert_receive {:model, :root, 0}
    assert_receive {:model, :child, 0}
    assert_receive {:effect, "sibling"}
    GenServer.stop(session)
    GenServer.stop(server)
    {:ok, server} = Server.start_link(server_options(store, self()))
    {:ok, session} = Session.start_link(opts)
    assert {:ok, %{status: :pending}} = Session.continuation(session, "worker")
    assert Server.health(server).status == :paused
    refute_receive {:model, _, _}
    refute_receive {:effect, _}
    assert :ok = Session.pause(session)
    assert :ok = Session.resume(session)
    {:ok, %{record: record}} = Server.continuation(server)
    {:ok, _} = Server.decide(server, :approve, decision(record))
    assert {:ok, %{status: :succeeded}} = Server.resume(server)
    {:ok, %{reference: reference, status: :completed}} = Session.continuation(session, "worker")

    assert {:ok, %{"count" => 1}, "worker"} =
             Session.complete_turn(session, "worker", reference, fn _ -> %{"count" => 1} end)

    assert_receive {:effect, "child-effect"}
    assert_receive {:model, :child, 1}
    assert_receive {:model, :root, 1}
    GenServer.stop(session)
    {:ok, session} = Session.start_link(opts)
    assert :ok = Server.reset(server)
    {:ok, %{reference: reset_reference}} = Session.continuation(session, "worker")

    assert {:error, :invalid_session_continuation_reference} =
             Session.complete_turn(session, "worker", reset_reference, fn _ ->
               flunk("duplicate turn")
             end)

    assert Session.read_state(session) == %{"count" => 1}
    refute_receive {:effect, _}
    GenServer.stop(session)
    GenServer.stop(server)
  end

  test "native child restores its host validator, rejects changed output and accounts a real validation retry",
       %{scoped: store} do
    agent = tree(self(), CountOutput)

    config =
      Map.merge(refs("root"), %{
        store: store,
        id: "agent",
        durability: :ephemeral,
        expires_at: nil,
        lease_ms: 60_000
      })

    {:ok, %{status: :paused} = paused} = ExAgent.run(agent, "native", continuation: config)
    assert_receive {:model, :root, 0}
    assert_receive {:model, :child, 0}
    assert_receive {:native_mode, :native}
    {:ok, %{record: record}} = Continuation.get(store, "agent")
    {:ok, %{record: approved}} = Continuation.decide(store, "agent", :approve, decision(record))
    reference = %{paused.continuation | revision: approved["revision"]}

    assert {:error, %{reason: :continuation_output_changed}} =
             ExAgent.resume(tree(self(), OtherOutput), reference, continuation: config)

    refute_receive {:effect, "child-effect"}
    refute_receive {:model, :child, _}
    assert {:ok, result} = ExAgent.resume(agent, reference, continuation: config)
    assert result.request_count == 5 and result.tool_calls == 3
    assert_receive {:effect, "child-effect"}
    assert_receive {:model, :child, 1}
    assert_receive {:model, :child, 2}

    returns =
      for %Part.ToolReturn{tool_name: "delegate", content: value} <-
            Message.parts(result.messages),
          do: Jason.decode!(Jason.encode!(value))

    assert returns == [%{"count" => 1}]
    {:ok, %{record: completed}} = Continuation.get(store, "agent")
    [{_, child}] = Map.to_list(completed["execution"]["progress"]["runtime"]["children"])
    assert child["frame"]["output_retries_used"] == 1
    refute_receive {:effect, "child-effect"}
  end

  test "deny and cancel retain confirmed siblings and require reset across Server restart", %{
    store: store
  } do
    for action <- [:deny, :cancel] do
      opts = server_options(store, self()) |> Keyword.put(:agent_id, Atom.to_string(action))
      {:ok, server} = Server.start_link(opts)
      {:ok, %{status: :paused}} = Server.chat(server, "first")
      assert_receive {:model, :root, 0}
      assert_receive {:model, :child, 0}
      assert_receive {:effect, "sibling"}
      {:ok, _} = Server.send_message(server, "volatile queue")
      {:ok, %{record: record}} = Server.continuation(server)

      command =
        decision(record)
        |> Keyword.put(:operation_id, Atom.to_string(action))
        |> Keyword.put(:authorize, fn :host, _, _ -> {:ok, "human"} end)

      assert {:ok, _} = Server.decide(server, action, command)
      assert Server.health(server).status == :reset_required
      assert Server.health(server).pending == 1
      assert {:error, :continuation_pending} = Server.chat(server, "blocked")
      refute_receive {:effect, "child-effect"}
      refute_receive {:model, :root, 1}
      GenServer.stop(server)
      {:ok, server} = Server.start_link(opts)
      assert Server.health(server).status == :reset_required
      assert Server.health(server).pending == 0
      assert :ok = Server.reset(server)
      assert {:ok, %{output: "root done"}} = Server.chat(server, "new explicit run")
      assert_receive {:model, :root, 1}
      refute_receive {:effect, _}
      GenServer.stop(server)
    end
  end

  defp server_options(store, owner),
    do: [
      agent: tree(owner),
      agent_id: "agent",
      namespace: "tree-runtime",
      store: store,
      continuation:
        Map.merge(refs("root"), %{durability: :ephemeral, expires_at: nil, lease_ms: 60_000})
    ]

  defp tree(owner, output \\ :text) do
    outputs = if output == :text, do: ["child done"], else: ["{\"count\":0}", "{\"count\":1}"]

    child_model =
      model(owner, :child, [
        %Response{
          parts: [%Part.ToolCall{tool_name: "child-effect", tool_call_id: "shared", args: %{}}]
        }
        | outputs
      ])

    child_model =
      if output == :text,
        do: child_model,
        else: %NativeModel{owner: owner, script: child_model.script}

    child =
      ExAgent.new(
        model: child_model,
        tools: [tool(owner, "child-effect")],
        output_type: output,
        output_mode: if(output == :text, do: :tool, else: :native)
      )

    delegate =
      Coordination.delegation_tool(child,
        name: "delegate",
        continuation: refs("child"),
        permissions: Permissions.new!(default: :ask)
      )

    root_model =
      model(owner, :root, [
        %Response{
          parts: [
            %Part.ToolCall{
              tool_name: "delegate",
              tool_call_id: "delegate",
              args: %{"prompt" => "child"}
            },
            %Part.ToolCall{tool_name: "sibling", tool_call_id: "shared", args: %{}}
          ]
        },
        "root done",
        "queued"
      ])

    ExAgent.new(model: root_model, tools: [delegate, tool(owner, "sibling")])
  end

  defp tool(owner, name),
    do:
      Tool.new(
        name: name,
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, {:effect, name})
          "done"
        end
      )

  defp model(owner, label, script),
    do: %ExAgent.Models.Test{
      script:
        Enum.with_index(script, fn value, index ->
          fn _, _ ->
            send(owner, {:model, label, index})

            response =
              if is_binary(value), do: %Response{parts: [%Part.Text{content: value}]}, else: value

            %{response | usage: %Usage{input_tokens: 1, output_tokens: 1}}
          end
        end)
    }

  defp refs(id),
    do: %{
      definition: %{"id" => id, "version" => "1"},
      policy: %{"id" => id, "version" => "1"},
      model_ref: %{"id" => id, "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }

  defp decision(record) do
    [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    [
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: "approve-#{record["revision"]}",
      approval_id: id,
      payload_hash: approval["payload_hash"],
      actor: :host,
      authorize: fn :host, :approve, _ -> {:ok, "human"} end
    ]
  end
end
