defmodule ExAgent.Frame10CausalControlsTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Store, Message, Continuation}
  alias ExAgent.Message.Part
  alias ExAgent.Continuation.{Record, Outcome, ToolEvidence, RequestData}
  alias ExAgent.Frame10OperationsFixture, as: F

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "independent")}
  end

  defp reject(store, r, cmd) do
    assert {:error, _} = Store.transition(store, :agent, "conversation", r["revision"], cmd)
    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end

  defp terminal_child(store) do
    {r, attach} = F.attached(store, F.started(store))
    r = F.op(store, r, "node_attach", attach)
    r = F.model(store, r, "D", "request-D", [%Part.Text{content: "X"}])
    F.op(store, r, "node_complete", %{"node_id" => "D"})
  end

  defp data(r, run) do
    node = F.root(r)["children"][run]
    {:ok, messages} = Message.from_json(node["snapshot"]["message_history"])

    state = %{
      prepared_tools: Map.new(F.tools(), &{&1.name, &1}),
      settings: %ExAgent.ModelSettings{},
      request_messages: nil,
      messages: messages,
      params: %{
        output_mode: :text,
        allow_text_output: true,
        output_object: nil,
        output_tools: [],
        instructions: []
      }
    }

    {:ok, data} = RequestData.capture(state, node["frame"], %{model_ref: F.ref()}, F.root(r))
    data
  end

  test "observed schema failure after args-changing hook is representable", %{store: store} do
    original = %{"task" => "valid original"}
    delegate = Enum.find(F.tools(), &(&1.name == "delegate"))
    assert {:ok, ^original} = ExAgent.Tool.validate_args(delegate, original)
    assert {:error, _} = ExAgent.Tool.validate_args(delegate, %{})
    r = F.model(store, F.started(store), "B", "request", [F.call("delegate", "call", original)])
    target = F.target("B", "request", "call")
    r = F.op(store, r, "call_prepare", target)
    # Trusted worker observed before-hook replacing args by %{}, then schema error.
    # Sealed unprepared shape deliberately has no binding/effective args.
    payload =
      Map.merge(target, %{
        "reason" => "args_validation_error",
        "error" => ToolEvidence.error(:args_validation_error)
      })

    cmd = F.worker(r, "call_reject", payload)

    assert {:ok, %{record: next}} =
             Store.transition(store, :agent, "conversation", r["revision"], cmd)

    assert {:ok, bytes} = Record.encode(next, {store.namespace, :agent, "conversation"})
    assert {:ok, ^next} = Record.decode(bytes, {store.namespace, :agent, "conversation"})
    assert_host_failure(store, r, next, original, "delegate", payload)
  end

  test "observed malformed effective args after hook are representable", %{store: store} do
    r = F.model(store, F.started(store), "B", "request", [F.call("plain", "call", %{})])
    target = F.target("B", "request", "call")
    r = F.op(store, r, "call_prepare", target)
    # Hook may change args, not name/kind/id, to malformed JSON.
    payload =
      Map.merge(target, %{
        "reason" => "malformed_args",
        "error" => ToolEvidence.error(:malformed_args)
      })

    reject(store, r, F.worker(r, "call_reject", Map.put(payload, "reason", "unknown_tool")))

    assert {:ok, %{record: next}} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "call_reject", payload)
             )

    assert_host_failure(store, r, next, %{}, "plain", payload)
  end

  defp assert_host_failure(store, before, next, args, name, payload) do
    key = ToolEvidence.key("B", "request")
    call = F.root(next)["tool_batches"][key]["calls"]["call"]
    assert call["state"] == "settled"
    assert call["binding"] == nil

    assert call["source"] == %{
             "kind" => "host",
             "phase" => "unprepared",
             "reason" => payload["reason"],
             "tool_name" => name,
             "call_hash" => elem(Outcome.call_hash(F.call(name, "call", args)), 1)
           }

    assert call["control"] == %{"retry" => true, "error" => payload["error"]}
    assert call["raw"] == %{"result" => call["result"], "control" => call["control"]}

    assert {:ok,
            [
              %Message.Request{
                parts: [
                  %Part.ToolReturn{
                    status: :validation_error,
                    tool_name: ^name,
                    tool_call_id: "call",
                    usage: nil
                  }
                ]
              }
            ]} = Message.from_json(call["result"])

    assert next["execution"]["effects"] == before["execution"]["effects"]
    assert F.root(next)["scope"] == F.root(before)["scope"]
    refute Record.unresolved?(next["execution"])
    assert {:ok, bytes} = Record.encode(next, {store.namespace, :agent, "conversation"})
    assert {:ok, ^next} = Record.decode(bytes, {store.namespace, :agent, "conversation"})
    path = ["execution", "progress", "runtime", "tool_batches", key, "calls", "call"]

    for bad <- [
          put_in(next, path ++ ["source", "call_hash"], String.duplicate("0", 64)),
          put_in(next, path ++ ["source", "tool_name"], "other"),
          put_in(next, path ++ ["binding"], %{"args" => %{}}),
          next
          |> put_in(path ++ ["control", "retry"], false)
          |> put_in(path ++ ["raw", "control", "retry"], false)
        ] do
      assert {:error, :invalid_record} =
               Record.validate(bad, {store.namespace, :agent, "conversation"})
    end

    reject(store, next, F.worker(next, "call_reject", payload))
  end

  test "unknown child final cannot bypass globally closed uncertainty", %{store: store} do
    r = terminal_child(store)
    target = F.target("B", "request-B", "delegate")
    r = F.op(store, r, "call_wrap", target)

    bytes =
      Outcome.encode(%Part.ToolReturn{
        tool_name: "delegate",
        tool_call_id: "delegate",
        content: nil,
        status: :unknown
      })

    payload =
      Map.merge(target, %{"result" => bytes, "control" => %{"retry" => false, "error" => nil}})

    reject(store, r, F.worker(r, "call_settle", payload))
  end

  test "observed zero Model usage contributes once; injected child wrapper usage rejects", %{
    store: store
  } do
    usage = %Message.Usage{input_tokens: 0, output_tokens: 0}
    r = F.started(store)
    r = F.op(store, r, "begin_effect", Map.put(F.target("B", "r"), "request_data", data(r, "B")))

    next =
      F.commit(
        store,
        r,
        F.worker(
          r,
          "outcome",
          Map.merge(F.target("B", "r"), %{
            "response" =>
              Message.to_json([
                %Message.Response{parts: [%Part.Text{content: "text"}], usage: usage}
              ]),
            "model_data" => nil
          })
        )
      )

    expected_usage = Message.Usage.to_map(usage)
    assert not is_nil(hd(F.root(next)["scope"]["operations"])["usage"])
    assert expected_usage["input_tokens"] === 0
    assert expected_usage["output_tokens"] === 0
    assert expected_usage["accounting"]["availability"]["input"] == "available"
    assert expected_usage["accounting"]["availability"]["output"] == "available"

    assert F.root(next)["scope"]["operations"] === [
             %{
               "id" => ["model", "r"],
               "run_id" => "B",
               "usage" => expected_usage,
               "terminal_usage" => expected_usage,
               "complete" => true,
               "ancestors" => %{"root" => expected_usage, "B" => expected_usage}
             }
           ]

    assert F.root(next)["scope"]["nodes"] === F.root(r)["scope"]["nodes"]

    for id <- ["root", "B"] do
      assert F.root(next)["scope"]["nodes"][id]["requests"] === 1
      assert F.root(next)["scope"]["nodes"][id]["tools"] === 0
    end

    other = Store.scoped({Store.ETS, __MODULE__}, "usage-child")
    r = terminal_child(other)
    target = F.target("B", "request-B", "delegate")
    r = F.op(other, r, "call_wrap", target)
    # ToolReturn usage is runtime-only and intentionally omitted by Outcome.encode.
    # Inject explicit nonnil usage into incoming command JSON instead.
    bytes =
      Outcome.encode(%Part.ToolReturn{
        tool_name: "delegate",
        tool_call_id: "delegate",
        content: "Y"
      })

    [json] = Jason.decode!(bytes)
    [part] = json["parts"]

    bytes =
      Jason.encode!([
        Map.put(json, "parts", [Map.put(part, "usage", Message.Usage.to_map(usage))])
      ])

    reject(
      other,
      r,
      F.worker(
        r,
        "call_settle",
        Map.merge(target, %{"result" => bytes, "control" => %{"retry" => false, "error" => nil}})
      )
    )
  end

  test "immutable terminal and root input, unsupported operations and owner fences", %{
    store: store
  } do
    r = terminal_child(store)

    for op <-
          ~w(checkpoint node_checkpoint cancel expire recover reconcile reconcile_model retry_effect output_resolution finish step_output) do
      reject(store, r, F.worker(r, op))
    end

    for field <- ~w(owner_id attempt_id fence epoch) do
      cmd = F.worker(r, "call_wrap", F.target("B", "request-B", "delegate"))

      cmd =
        update_in(cmd, ["payload", field], fn v ->
          if is_integer(v), do: v + 1, else: v <> "-stale"
        end)

      reject(store, r, cmd)
    end

    reject(
      store,
      r,
      F.worker(
        r,
        "call_wrap",
        Map.put(F.target("B", "request-B", "delegate"), "input", "changed")
      )
    )

    reject(store, r, F.worker(r, "node_complete", %{"node_id" => "D"}))
    assert F.root(r)["input"] == "root input"
    key = {store.namespace, :agent, "conversation"}

    for bad <- [
          put_in(r, ["execution", "progress", "runtime", "children", "D", "status"], "cancelled"),
          put_in(
            r,
            ["execution", "progress", "runtime", "scope", "nodes", "root", "requests"],
            0
          ),
          put_in(
            r,
            ["execution", "progress", "runtime", "children", "B", "frame", "outcomes"],
            %{}
          ),
          put_in(r, ["execution", "run_id"], "other"),
          Map.put(r, "record_version", 1)
        ] do
      assert {:error, _} = Record.validate(bad, key)
    end
  end

  test "public decisions bound and authorized; approved call reclaims without replay", %{
    store: store
  } do
    r = F.op(store, F.awaiting_pause(store), "pause", %{"elapsed_ms" => 9})
    [{id, approval} | _] = Map.to_list(r["execution"]["progress"]["approvals"])

    options = [
      record_id: r["record_id"],
      revision: r["revision"],
      operation_id: "decision-probe",
      approval_id: id,
      payload_hash: approval["payload_hash"],
      actor: :human
    ]

    assert {:error, :unauthorized} = Continuation.decide(store, "conversation", :approve, options)

    reject(
      store,
      r,
      F.command("decide", %{
        "approval_id" => id,
        "payload_hash" => "wrong",
        "decision" => "approve"
      })
    )

    for _ <- 1..2 do
      {:ok, current} = Store.load_record(store, :agent, "conversation")

      {id, a} =
        Enum.find(current["execution"]["progress"]["approvals"], fn {_, a} ->
          is_nil(a["decision"])
        end)

      opts =
        Keyword.merge(options,
          revision: current["revision"],
          operation_id: id,
          approval_id: id,
          payload_hash: a["payload_hash"],
          authorize: fn :human, :approve, _ -> {:ok, "admin-reviewer"} end
        )

      assert {:ok, _} = Continuation.decide(store, "conversation", :approve, opts)
      {:ok, current} = Store.load_record(store, :agent, "conversation")
      assert {:ok, bytes} = Record.encode(current, {store.namespace, :agent, "conversation"})
      assert {:ok, ^current} = Record.decode(bytes, {store.namespace, :agent, "conversation"})
    end

    {:ok, r} = Store.load_record(store, :agent, "conversation")
    r = F.commit(store, r, F.claim("reclaim-reviewer"))
    r = F.op(store, r, "frontier_open")
    target = F.target("D", "request-D", "one")
    reject(store, r, F.worker(r, "call_prepared", Map.put(target, "args", %{"changed" => true})))
    r = F.op(store, r, "call_prepared", Map.put(target, "args", %{}))
    cmd = F.worker(r, "begin_effect", target)
    next = F.commit(store, r, cmd)

    assert {:ok, %{record: ^next, replayed: true}} =
             Store.transition(store, :agent, "conversation", r["revision"], cmd)

    reject(store, next, F.worker(next, "begin_effect", target))

    assert Enum.all?(next["execution"]["progress"]["approvals"], fn {_, a} ->
             a["decision"]["actor_id"] == "admin-reviewer"
           end)
  end
end
