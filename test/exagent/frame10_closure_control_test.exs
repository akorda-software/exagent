defmodule ExAgent.Frame10ClosureControlTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Store, Message}
  alias ExAgent.Continuation.{Record, Outcome, ToolEvidence, RequestData}
  alias ExAgent.Message.Part
  alias ExAgent.Frame10OperationsFixture, as: F

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "control")}
  end

  defp through_dispatch(store, limit) do
    cmd =
      put_in(
        F.create(),
        ["payload", "execution", "progress", "runtime", "authority", "root", "checkpoint_limit"],
        limit
      )

    r = F.commit(store, nil, cmd)
    r = F.commit(store, r, F.claim())

    n =
      F.node(F.root(r), "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })

    r =
      F.op(store, r, "step_input", %{"node_id" => "B", "node" => n, "authority" => F.authority()})

    r = F.model(store, r, "B", "request", [F.call("plain", "call")])
    target = F.target("B", "request", "call")
    r = F.prepare(store, r, target, %{})
    F.op(store, r, "begin_effect", target)
  end

  test "reserved closure capacity remains usable for a bounded raw result", %{store: store} do
    r = through_dispatch(store, Record.max_bytes())
    limit = byte_size(Jason.encode!(r)) + Record.cleanup_reserve_bytes(r) + 1000
    other = Store.scoped({Store.ETS, __MODULE__}, "bounded")
    r = through_dispatch(other, limit)

    bytes =
      Outcome.encode(%Part.ToolReturn{
        tool_name: "plain",
        tool_call_id: "call",
        content: String.duplicate("x", 60_000)
      })

    assert byte_size(bytes) < F.root(r)["children"]["B"]["frame"]["tool_return_bytes"]

    payload =
      Map.merge(F.target("B", "request", "call"), %{
        "result" => bytes,
        "control" => %{"retry" => false, "error" => nil}
      })

    IO.inspect(
      %{
        checkpoint_limit: limit,
        encoded_before: byte_size(Jason.encode!(r)),
        reserve_before: Record.cleanup_reserve_bytes(r),
        result_bytes: byte_size(bytes)
      },
      label: "closure measurements"
    )

    answer =
      Store.transition(
        other,
        :agent,
        "conversation",
        r["revision"],
        F.worker(r, "outcome", payload)
      )

    if match?({:error, _}, answer),
      do: assert({:ok, r} == Store.load_record(other, :agent, "conversation"))

    assert {:ok, %{record: next}} = answer
    # Only JSON result slots consume closure reserve, not arbitrary row growth.
    credit = byte_size(Jason.encode!(bytes)) - 4
    assert Record.cleanup_reserve_bytes(next) < Record.cleanup_reserve_bytes(r) - credit + 1024
    assert Record.cleanup_reserve_bytes(next) >= 24 * 65_536 + 16_384 - credit
    assert {:ok, encoded} = Record.encode(next, {other.namespace, :agent, "conversation"})
    assert {:ok, ^next} = Record.decode(encoded, {other.namespace, :agent, "conversation"})
    next = F.op(other, next, "call_wrap", F.target("B", "request", "call"))
    next = F.op(other, next, "call_settle", payload)
    next = F.op(other, next, "tool_resolution", F.target("B", "request"))
    next = F.op(other, next, "batch_consume", F.target("B", "request"))
    assert F.root(next)["children"]["B"]["frame"]["cursor"] == "request"
    assert byte_size(Jason.encode!(next)) + Record.cleanup_reserve_bytes(next) <= limit
  end

  test "unknown child final is rejected atomically while wrapping remains unresolved", %{
    store: store
  } do
    {r, attach} = F.attached(store, F.started(store))
    r = F.op(store, r, "node_attach", attach)
    r = F.model(store, r, "D", "request-D", [%Part.Text{content: "X"}])
    r = F.op(store, r, "node_complete", %{"node_id" => "D"})
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

    assert {:error, :invalid_frame10_transition} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "call_settle", payload)
             )

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    assert Record.unresolved?(r["execution"])

    for operation <- ~w(tool_resolution batch_consume recover) do
      assert {:error, _} =
               Store.transition(
                 store,
                 :agent,
                 "conversation",
                 r["revision"],
                 F.worker(r, operation, F.target("B", "request-B"))
               )

      assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    end

    # Known final Y remains legal without changing child/raw X.
    known =
      Outcome.encode(%Part.ToolReturn{
        tool_name: "delegate",
        tool_call_id: "delegate",
        content: "Y"
      })

    next = F.op(store, r, "call_settle", Map.put(payload, "result", known))
    refute Record.unresolved?(next["execution"])
    assert F.root(next)["children"]["D"] == F.root(r)["children"]["D"]
    key = ToolEvidence.key("B", "request-B")

    assert F.root(next)["tool_batches"][key]["calls"]["delegate"]["raw"] ==
             F.root(r)["tool_batches"][key]["calls"]["delegate"]["raw"]

    # A coherent final/outcomes mutation must fail the global reader too, not
    # only the command phase guard; no external effect exists for this child.
    bad =
      next
      |> put_in(
        ["execution", "progress", "runtime", "tool_batches", key, "calls", "delegate", "result"],
        bytes
      )
      |> put_in(
        ["execution", "progress", "runtime", "children", "B", "frame", "outcomes", "delegate"],
        bytes
      )

    assert {:error, :invalid_record} =
             Record.validate(bad, {store.namespace, :agent, "conversation"})
  end

  test "omitted effect return cannot authorize new model context", %{store: store} do
    r = through_dispatch(store, Record.max_bytes())
    target = F.target("B", "request", "call")

    bytes =
      Outcome.encode(%Part.ToolReturn{
        tool_name: "plain",
        tool_call_id: "call",
        content: nil,
        payload_omitted: ExAgent.Retention.marker(:tool_return, 70_000, 65_536)
      })

    payload =
      Map.merge(target, %{"result" => bytes, "control" => %{"retry" => false, "error" => nil}})

    r = F.op(store, r, "outcome", payload)
    r = F.op(store, r, "call_wrap", target)
    r = F.op(store, r, "call_settle", payload)
    r = F.op(store, r, "tool_resolution", F.target("B", "request"))
    r = F.op(store, r, "batch_consume", F.target("B", "request"))
    {:ok, messages} = Message.from_json(F.root(r)["children"]["B"]["snapshot"]["message_history"])
    refute ExAgent.Retention.executable?(messages)
    node = F.root(r)["children"]["B"]

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
    payload = Map.put(F.target("B", "next-after-omission"), "request_data", data)

    assert {:error, :invalid_frame10_transition} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "begin_effect", payload)
             )

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    assert F.root(r)["children"]["B"]["frame"]["run_step"] == 1
  end

  test "original-record source reader cannot hide orphan tool effects", %{store: store} do
    r = through_dispatch(store, Record.max_bytes())
    batch = F.root(r)["tool_batches"][ToolEvidence.key("B", "request")]

    {_, effect} =
      Enum.find(r["execution"]["effects"], fn {_, e} -> e["intent"]["kind"] == "tool" end)

    bad = put_in(r, ["execution", "effects", "orphan"], effect)
    assert {:error, _} = Record.validate(bad, {store.namespace, :agent, "conversation"})
    assert_raise MatchError, fn -> ToolEvidence.calls(bad, batch) end
  end

  test "effect-backed unknown retains the existing rejection and unresolved intent", %{
    store: store
  } do
    r = through_dispatch(store, Record.max_bytes())

    bytes =
      Outcome.encode(%Part.ToolReturn{
        tool_name: "plain",
        tool_call_id: "call",
        content: nil,
        status: :unknown
      })

    payload =
      Map.merge(F.target("B", "request", "call"), %{
        "result" => bytes,
        "control" => %{"retry" => false, "error" => nil}
      })

    assert {:error, :invalid_record} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "outcome", payload)
             )

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    assert Record.unresolved?(r["execution"])
  end

  test "materialized closure keeps future slots and JSON cleanup boundary exact", %{store: store} do
    r = through_dispatch(store, Record.max_bytes())
    target = F.target("B", "request", "call")
    # Escapes exercise encoded JSON size, not just raw content length.
    bytes =
      Outcome.encode(%Part.ToolReturn{
        tool_name: "plain",
        tool_call_id: "call",
        content: String.duplicate("\"\\\n", 7_000)
      })

    assert byte_size(bytes) < 65_536

    payload =
      Map.merge(target, %{"result" => bytes, "control" => %{"retry" => false, "error" => nil}})

    raw = F.op(store, r, "outcome", payload)
    wrapped = F.op(store, raw, "call_wrap", target)
    settled = F.op(store, wrapped, "call_settle", payload)
    resolved = F.op(store, settled, "tool_resolution", F.target("B", "request"))
    consumed = F.op(store, resolved, "batch_consume", F.target("B", "request"))
    credit = byte_size(Jason.encode!(bytes)) - 4

    for {row, copies} <- [{raw, 1}, {wrapped, 1}, {settled, 3}, {resolved, 3}] do
      assert Record.cleanup_reserve_bytes(row) >= 24 * 65_536 + 16_384 - copies * credit
      threshold = byte_size(Jason.encode!(row)) + Record.cleanup_reserve_bytes(row)

      for delta <- [-1, 0, 1] do
        bounded =
          put_in(
            row,
            ["execution", "progress", "runtime", "authority", "root", "checkpoint_limit"],
            threshold + delta
          )

        assert byte_size(Jason.encode!(bounded)) == byte_size(Jason.encode!(row))
        expected = if delta < 0, do: {:error, :record_limit}, else: :ok
        assert Record.validate(bounded, {store.namespace, :agent, "conversation"}) == expected
      end
    end

    assert Record.cleanup_reserve_bytes(consumed) < Record.cleanup_reserve_bytes(resolved)
  end

  # Fixed-width receipts and equal-width namespaces make the actual CAS row costs
  # comparable. Include every admission prefix, not just the final dispatched row.
  defp raw_boundary_admission(store, limit) do
    alias ExAgent.Frame10OutputCapacityFixture, as: C

    create =
      put_in(
        F.create(),
        ~w(payload execution progress runtime authority root checkpoint_limit),
        limit
      )

    first = C.commit(store, nil, create)

    commands = [
      fn _ -> F.claim() end,
      fn r ->
        node =
          F.node(F.root(r), "B", "root", %{
            "kind" => "step",
            "step_id" => "B",
            "index" => 0,
            "input" => "root input"
          })

        F.worker(r, "step_input", %{
          "node_id" => "B",
          "node" => node,
          "authority" => F.authority()
        })
      end,
      fn r ->
        node = F.root(r)["children"]["B"]
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
        F.worker(r, "begin_effect", Map.put(F.target("B", "request"), "request_data", data))
      end,
      fn r ->
        F.worker(
          r,
          "outcome",
          Map.merge(F.target("B", "request"), %{
            "response" => Message.to_json([%Message.Response{parts: [F.call("plain", "call")]}]),
            "model_data" => nil
          })
        )
      end,
      fn r -> F.worker(r, "batch_begin", F.target("B", "request")) end,
      fn r -> F.worker(r, "call_prepare", F.target("B", "request", "call")) end,
      fn r ->
        F.worker(r, "call_prepared", Map.put(F.target("B", "request", "call"), "args", %{}))
      end
    ]

    {prepared, peak} =
      Enum.reduce(commands, {first, C.cost(first)}, fn command, {r, peak} ->
        next = C.commit(store, r, command.(r))
        {next, max(peak, C.cost(next))}
      end)

    dispatch =
      C.command(prepared, F.worker(prepared, "begin_effect", F.target("B", "request", "call")))

    {prepared, peak, dispatch}
  end

  test "raw byte boundary closes completely or rejects atomically" do
    alias ExAgent.Frame10OutputCapacityFixture, as: C
    reference = Store.scoped({Store.ETS, __MODULE__}, "raw-boundary-zz")
    {prepared, peak, command} = raw_boundary_admission(reference, Record.max_bytes())
    dispatched = F.commit(reference, prepared, command)
    cost = max(peak, C.cost(dispatched))
    limit = cost - byte_size(to_string(Record.max_bytes())) + byte_size(to_string(cost))
    part = %Part.ToolReturn{tool_name: "plain", tool_call_id: "call", content: ""}
    overhead = byte_size(Outcome.encode(part))

    for delta <- [-1, 0, 1] do
      namespace = "raw-boundary-" <> String.pad_leading(to_string(delta), 2, "0")
      other = Store.scoped({Store.ETS, __MODULE__}, namespace)
      {prepared, peak, command} = raw_boundary_admission(other, limit)
      r = F.commit(other, prepared, command)
      assert max(peak, C.cost(r)) <= limit
      bytes = Outcome.encode(%{part | content: String.duplicate("x", 65_536 + delta - overhead)})
      assert byte_size(bytes) == 65_536 + delta
      target = F.target("B", "request", "call")

      payload =
        Map.merge(target, %{"result" => bytes, "control" => %{"retry" => false, "error" => nil}})

      command = F.worker(r, "outcome", payload)

      if delta > 0 do
        assert {:error, :invalid_record} =
                 Store.transition(other, :agent, "conversation", r["revision"], command)

        assert {:ok, ^r} = Store.load_record(other, :agent, "conversation")
      else
        next = F.commit(other, r, command)
        next = F.op(other, next, "call_wrap", target)
        next = F.op(other, next, "call_settle", payload)
        next = F.op(other, next, "tool_resolution", F.target("B", "request"))
        next = F.op(other, next, "batch_consume", F.target("B", "request"))
        assert F.root(next)["children"]["B"]["frame"]["cursor"] == "request"
      end
    end
  end

  test "original raw boundary budget rejects precisely before tool dispatch" do
    store = Store.scoped({Store.ETS, __MODULE__}, "raw-boundary-old")
    {prepared, _, command} = raw_boundary_admission(store, 1_714_951)
    call = F.root(prepared)["tool_batches"][ToolEvidence.key("B", "request")]["calls"]["call"]
    assert call["state"] == "prepared"
    assert is_nil(call["source"])
    assert is_nil(call["raw"])

    assert Enum.all?(prepared["execution"]["effects"], fn {_, effect} ->
             effect["intent"]["kind"] == "model" and effect["state"] == "confirmed"
           end)

    assert {:error, :record_limit} =
             Store.transition(store, :agent, "conversation", prepared["revision"], command)

    assert {:ok, ^prepared} = Store.load_record(store, :agent, "conversation")
  end
end
