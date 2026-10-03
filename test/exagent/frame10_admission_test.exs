defmodule ExAgent.Frame10AdmissionTest do
  use ExUnit.Case, async: false
  alias ExAgent.Store
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Continuation.{Frame, Record, RequestData, ToolEvidence}

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "admission10")}
  end

  test "RequestData2 exact preimage, normalization, hashes; legacy capture bytes unchanged", %{
    store: store
  } do
    r = F.started(store)
    node = F.root(r)["children"]["B"]
    {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"])

    run = %{
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

    config = %{model_ref: F.ref()}
    assert {:ok, legacy} = RequestData.capture(run, node["frame"], config)

    assert {:ok, ^legacy} =
             RequestData.capture(run, node["frame"], config, %{"frame_version" => 9})

    assert legacy["request_version"] == 1
    assert not Map.has_key?(legacy, "tool_descriptors")
    assert {:ok, data} = RequestData.capture(run, node["frame"], config, F.root(r))

    assert {:error, :unrepresentable_model_request} =
             RequestData.capture(run, node["frame"], config, %{"frame_version" => 10})

    assert RequestData.valid10?(data)
    assert Map.delete(data, "tool_descriptors") |> Map.put("request_version", 1) == legacy
    assert data["tool_descriptors"]["delegate"]["delegation"]["prompt_arg"] == "task"
    refute Map.has_key?(data["tool_descriptors"]["plain"], "delegation")

    for tool <- F.tools() do
      {:ok, delegation} = ExAgent.Continuation.Delegation.descriptor_data(tool.delegation)

      old = %{
        "definition" => ExAgent.Tool.definition(tool),
        "kind" => Atom.to_string(tool.kind),
        "takes_ctx" => tool.takes_ctx,
        "max_retries" => tool.max_retries
      }

      old = if delegation, do: Map.put(old, "delegation", delegation), else: old
      assert Frame.fingerprint(tool) == Record.digest(old)
    end

    for bad <- [
          put_in(data, ["tool_descriptors", "plain", "delegation"], nil),
          put_in(data, ["tool_descriptors", "delegate", "delegation", "prompt_arg"], "prompt"),
          update_in(data, ["tool_descriptors"], &Map.delete(&1, "plain")),
          put_in(data, ["tool_descriptors", "delegate", "delegation", "definition"], %{
            "id" => "bad"
          }),
          put_in(data, ["tools", "plain"], String.duplicate("f", 64)),
          Map.put(data, "extra", true)
        ],
        do: refute(RequestData.valid10?(bad))

    state = Map.put(run, :continuation_frame, node["frame"])
    assert {:ok, restored} = RequestData.restore(state, data, F.root(r))
    assert restored.request_messages == messages
    assert {:error, :retry_model_request_changed} = RequestData.restore(state, data)

    assert {:error, :retry_model_request_changed} =
             RequestData.restore(state, data, %{"frame_version" => 9})
  end

  test "non-default delegated input, references and schema cannot be forged at attach", %{
    store: store
  } do
    {r, attach} = F.attached(store, F.started(store))

    wrong_history =
      ExAgent.Message.to_json([
        %ExAgent.Message.Request{
          run_id: "D",
          parts: [
            %ExAgent.Message.Part.User{content: "wrong input"}
          ]
        }
      ])

    for bad <- [
          put_in(attach, ["node", "snapshot", "message_history"], wrong_history),
          put_in(attach, ["node", "definition", "id"], "other"),
          put_in(attach, ["node", "link", "schema_hash"], String.duplicate("0", 64)),
          put_in(attach, ["node", "frame", "tool_return_bytes"], nil),
          put_in(attach, ["node", "link", "args", "task"], "wrong input"),
          put_in(attach, ["authority", "policies"], [
            %{"default" => "allow", "rules" => [["other", "", "allow"]]}
          ]),
          Map.put(attach, "sibling", %{})
        ] do
      assert {:error, _} =
               Store.transition(
                 store,
                 :agent,
                 "conversation",
                 r["revision"],
                 F.worker(r, "node_attach", bad)
               )

      assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    end

    r = F.op(store, r, "node_attach", attach)
    assert {:ok, bytes} = Record.encode(r, {store.namespace, :agent, "conversation"})
    assert {:ok, ^r} = Record.decode(bytes, {store.namespace, :agent, "conversation"})
  end

  test "closure capacity rejects batch before any tool callback markers or fake settled call", %{
    store: store
  } do
    r = F.commit(store, nil, F.create())
    r = F.commit(store, r, F.claim())

    n =
      F.node(F.root(r), "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })
      |> put_in(["frame", "tool_return_bytes"], 300_000)

    r =
      F.op(store, r, "step_input", %{"node_id" => "B", "node" => n, "authority" => F.authority()})

    r = F.model(store, r, "B", "request", [F.call("plain", "one"), F.call("plain", "two")], false)

    assert {:error, :record_limit} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "batch_begin", F.target("B", "request"))
             )

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    assert F.root(r)["tool_batches"] == %{}
    assert length(F.root(r)["scope"]["batches"]) == 0
  end

  test "fatal and output_failed remain globally rejected; preparing cannot be replayed", %{
    store: store
  } do
    r = F.model(store, F.started(store), "B", "request", [F.call("plain", "one")])
    target = F.target("B", "request", "one")
    r = F.op(store, r, "call_prepare", target)
    assert Record.unresolved?(r["execution"])

    assert {:error, _} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "call_prepare", target)
             )

    key = {store.namespace, :agent, "conversation"}

    fatal =
      put_in(r, ["execution", "progress", "runtime", "frontier"], %{
        "epoch" => 1,
        "state" => "draining",
        "reason" => "fatal",
        "fatal" => %{"kind" => "root", "error" => ToolEvidence.error(:fatal)}
      })

    assert {:error, :invalid_record} = Record.validate(fatal, key)

    assert {:error, :invalid_record} =
             Record.validate(put_in(r, ["execution", "state"], "failed"), key)

    assert {:error, _} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "pause", %{"elapsed_ms" => 0})
             )

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end

  test "host decode and schema failures retain original hashes without invented binding", _ do
    for {reason, name, args} <- [
          {"malformed_args", "plain", "{broken"},
          {"args_validation_error", "delegate", %{}}
        ] do
      store = Store.scoped({Store.ETS, __MODULE__}, reason)
      original = F.call(name, "call", args)
      r = F.model(store, F.started(store), "B", "request", [original])
      target = F.target("B", "request", "call")
      r = F.op(store, r, "call_prepare", target)
      error = ToolEvidence.error({:validation, reason})

      r =
        F.op(store, r, "call_reject", Map.merge(target, %{"reason" => reason, "error" => error}))

      call = F.root(r)["tool_batches"][ToolEvidence.key("B", "request")]["calls"]["call"]
      assert call["binding"] == nil

      assert call["source"]["call_hash"] ==
               elem(ExAgent.Continuation.Outcome.call_hash(original), 1)

      assert call["control"] == %{"retry" => true, "error" => error}

      assert {:ok, [%ExAgent.Message.Request{parts: [part]}]} =
               ExAgent.Message.from_json(call["result"])

      assert part.status == :validation_error
      assert part.content == error["message"]
    end
  end

  test "host hook/retention fatal retains canonical no-effect source and closes without replay",
       _ do
    for reason <- ~w(before_hook_error preparation_retention admission_error) do
      store = Store.scoped({Store.ETS, __MODULE__}, reason)
      r = F.model(store, F.started(store), "B", "request", [F.call("plain", "call")])
      target = F.target("B", "request", "call")

      r =
        if reason == "admission_error",
          do: F.prepare(store, r, target, %{}),
          else: F.op(store, r, "call_prepare", target)

      payload =
        Map.merge(target, %{"reason" => reason, "error" => ToolEvidence.error(:bounded_failure)})

      assert {:ok, %{record: rejected}} =
               Store.transition(
                 store,
                 :agent,
                 "conversation",
                 r["revision"],
                 F.worker(r, "call_reject", payload)
               )

      assert {:ok, ^rejected} = Store.load_record(store, :agent, "conversation")

      call =
        rejected["execution"]["progress"]["runtime"]["tool_batches"][
          ToolEvidence.key("B", "request")
        ]["calls"]["call"]

      assert call["state"] == "settled" and call["source"]["kind"] == "host"

      refute Map.has_key?(
               rejected["execution"]["effects"],
               ToolEvidence.effect_id("B", "request", "call")
             )

      assert Record.unresolved?(r["execution"]) == (reason != "admission_error")

      assert {:ok, %{record: closed}} =
               Store.transition(
                 store,
                 :agent,
                 "conversation",
                 rejected["revision"],
                 F.worker(rejected, "finish", %{"elapsed_ms" => 0})
               )

      assert closed["execution"]["state"] == "failed"
    end
  end

  test "prepared permission denial retains legacy projection; dispatch under deny cannot commit",
       %{store: store} do
    r = F.commit(store, nil, F.create())
    r = F.commit(store, r, F.claim())

    node =
      F.node(F.root(r), "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })

    authority =
      update_in(F.authority(), ["policies"], &(&1 ++ [%{"default" => "deny", "rules" => []}]))

    r =
      F.op(store, r, "step_input", %{"node_id" => "B", "node" => node, "authority" => authority})

    r = F.model(store, r, "B", "request", [F.call("plain", "call")])
    target = F.target("B", "request", "call")
    r = F.prepare(store, r, target, %{})

    assert {:error, :invalid_record} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "begin_effect", target)
             )

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")

    r =
      F.op(
        store,
        r,
        "call_reject",
        Map.merge(target, %{"reason" => "permission_denied", "error" => nil})
      )

    call = F.root(r)["tool_batches"][ToolEvidence.key("B", "request")]["calls"]["call"]
    assert is_map(call["binding"])
    assert call["source"] == %{"kind" => "host", "reason" => "permission_denied"}

    assert {:ok, [%ExAgent.Message.Request{parts: [part]}]} =
             ExAgent.Message.from_json(call["result"])

    assert part.status == :denied
    assert part.content == "Tool \"plain\" is not permitted."
    assert call["control"] == %{"retry" => false, "error" => nil}
    assert map_size(r["execution"]["effects"]) == 1
    r = F.op(store, r, "tool_resolution", F.target("B", "request"))
    _ = F.op(store, r, "batch_consume", F.target("B", "request"))
  end
end
