defmodule ExAgent.Frame10FailedClosureTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, Store}
  alias ExAgent.Continuation.{Outcome, Record, ToolEvidence}
  alias ExAgent.Message.Part
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Frame10SuccessFixture, as: S
  alias ExAgent.Frame10OutputCASFixture, as: O
  alias ExAgent.Frame10OutputCapacityFixture, as: C

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "failed-close10")}
  end

  defp payload(id, error \\ nil) do
    Map.merge(F.target("B", "request-B", id), %{
      "result" =>
        Outcome.encode(%Part.ToolReturn{
          tool_name: "plain",
          tool_call_id: id,
          content: id,
          status: :succeeded
        }),
      "control" => %{"retry" => false, "error" => error}
    })
  end

  defp wrapping(store, r, id, run \\ "B") do
    target = F.target(run, "request-#{run}", id)
    r = F.prepare(store, r, target, %{})
    r = F.op(store, r, "begin_effect", target)
    r = F.op(store, r, "outcome", Map.merge(payload(id), target))
    F.op(store, r, "call_wrap", target)
  end

  defp reject(store, r, command) do
    assert {:error, _} = Store.transition(store, :agent, "conversation", r["revision"], command)
    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end

  defp attach(store, r, id, parent \\ "B") do
    request = "request-#{parent}"
    target = F.target(parent, request, id)
    r = F.prepare(store, r, target, %{"task" => "child input"})

    binding =
      F.root(r)["tool_batches"][ToolEvidence.key(parent, request)]["calls"][id]["binding"]

    link =
      Map.merge(binding, %{
        "kind" => "delegate",
        "parent_request_id" => request,
        "call_id" => id
      })

    node = F.node(F.root(r), id, parent, link) |> put_in(["frame", "tool_return_bytes"], 4096)

    F.op(
      store,
      r,
      "node_attach",
      Map.merge(target, %{"node_id" => id, "node" => node, "authority" => F.authority()})
    )
  end

  test "confirmed call fatal closes through CAS, preserves evidence and refunds once", %{
    store: store
  } do
    r = F.started(store)
    r = F.model(store, r, "B", "request-B", [F.call("plain", "fatal"), F.call("plain", "queued")])
    r = wrapping(store, r, "fatal")
    error = ToolEvidence.error(:failure)
    r = F.op(store, r, "call_settle", payload("fatal", error))
    before = r
    command = F.worker(r, "finish", %{"elapsed_ms" => 17})
    r = F.commit(store, r, command)
    assert r["execution"]["state"] == "failed"
    assert F.root(r)["frontier"]["fatal"]["error"] == error
    assert F.root(r)["children"]["B"]["status"] == "cancelled"
    batch = ToolEvidence.key("B", "request-B")

    assert F.root(r)["tool_batches"][batch]["calls"]["fatal"] ==
             F.root(before)["tool_batches"][batch]["calls"]["fatal"]

    assert F.root(r)["tool_batches"][batch]["calls"]["queued"]["state"] == "blocked"
    assert is_nil(F.root(r)["tool_batches"][batch]["calls"]["queued"]["result"])
    assert r["execution"]["effects"] == before["execution"]["effects"]
    assert r["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_983
    assert is_nil(r["execution"]["owner_id"])
    assert {:ok, %{status: :failed, record: ^r}} = Continuation.get(store, "conversation")

    assert {:ok, %{replayed: true}} =
             Store.transition(store, :agent, "conversation", before["revision"], command)

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    reject(store, r, F.worker(r, "finish", %{"elapsed_ms" => 17}))
    reject(store, r, %{command | "payload" => Map.put(command["payload"], "elapsed_ms", 18)})
    reject(store, r, F.claim())

    for path <- [
          ~w(execution progress runtime frontier fatal error message),
          ~w(execution progress runtime children B error message)
        ] do
      assert {:error, _} =
               Record.validate(
                 put_in(r, path, "forged"),
                 {"failed-close10", :agent, "conversation"}
               )
    end

    reset = F.command("reset_snapshot", %{"snapshot" => Map.put(r["snapshot"], "revision", 1)})
    reject(store, r, reset)
    delete = F.command("delete", %{"before" => r["updated_at"] + 1})
    assert {:ok, _} = Store.transition(store, :agent, "conversation", r["revision"], delete)
    assert {:error, :not_found} = Store.load_record(store, :agent, "conversation")
  end

  test "admitted effect must drain; raw is retained blocked without a new wrapper", %{
    store: store
  } do
    r = F.started(store)
    r = F.model(store, r, "B", "request-B", [F.call("plain", "fatal"), F.call("plain", "effect")])
    r = wrapping(store, r, "fatal")
    target = F.target("B", "request-B", "effect")
    r = F.prepare(store, r, target, %{})
    r = F.op(store, r, "begin_effect", target)
    stale = F.worker(r, "finish", %{"elapsed_ms" => 3})
    r = F.op(store, r, "call_settle", payload("fatal", ToolEvidence.error(:failure)))
    reject(store, r, F.worker(r, "finish", %{"elapsed_ms" => 3}))
    assert {:ok, %{record: ^r}} = Continuation.get(store, "conversation")
    r = F.op(store, r, "outcome", payload("effect"))
    reject(store, r, stale)
    reject(store, r, F.worker(r, "call_wrap", target))
    before = r
    r = F.op(store, r, "finish", %{"elapsed_ms" => 3})
    batch = ToolEvidence.key("B", "request-B")
    old = F.root(before)["tool_batches"][batch]["calls"]["effect"]

    assert F.root(r)["tool_batches"][batch]["calls"]["effect"] ==
             old |> Map.put("state", "blocked") |> Map.put("blocked_by", "fatal")

    assert r["execution"]["effects"] == before["execution"]["effects"]
    assert F.root(r)["scope"] == F.root(before)["scope"]
  end

  test "preparing remains ambiguous and wrappers must settle before closure in either arrival order",
       %{store: store} do
    for {suffix, order} <- [{"a", ["two", "one"]}, {"b", ["one", "two"]}] do
      store = %{store | namespace: "failed-order-#{suffix}"}
      r = F.started(store)
      r = F.model(store, r, "B", "request-B", [F.call("plain", "one"), F.call("plain", "two")])
      r = wrapping(store, r, "one")
      r = wrapping(store, r, "two")
      [first, last] = order

      r =
        F.op(
          store,
          r,
          "call_settle",
          payload(first, Map.put(ToolEvidence.error(:failure), "message", first))
        )

      reject(store, r, F.worker(r, "finish", %{"elapsed_ms" => 0}))

      r =
        F.op(
          store,
          r,
          "call_settle",
          payload(last, Map.put(ToolEvidence.error(:failure), "message", last))
        )

      r = F.op(store, r, "finish", %{"elapsed_ms" => 0})
      assert F.root(r)["frontier"]["fatal"]["call_id"] == "one"
      assert F.root(r)["frontier"]["fatal"]["error"]["message"] == "one"
    end

    r = F.started(store)

    r =
      F.model(store, r, "B", "request-B", [F.call("plain", "fatal"), F.call("plain", "ambiguous")])

    r = wrapping(store, r, "fatal")
    r = F.op(store, r, "call_prepare", F.target("B", "request-B", "ambiguous"))
    r = F.op(store, r, "call_settle", payload("fatal", ToolEvidence.error(:failure)))
    reject(store, r, F.worker(r, "finish", %{"elapsed_ms" => 0}))
    assert {:ok, %{record: ^r}} = Continuation.get(store, "conversation")
  end

  test "completed child and raw remain immutable; an unstarted child and prepared call cancel without outcomes",
       %{store: store} do
    r = F.started(store)

    r =
      F.model(store, r, "B", "request-B", [
        F.call("plain", "fatal"),
        F.call("delegate", "done"),
        F.call("delegate", "idle"),
        F.call("plain", "prepared")
      ])

    r = attach(store, r, "done")
    r = attach(store, r, "idle")
    r = F.model(store, r, "done", "request-done", [%Part.Text{content: "confirmed child"}], false)
    r = F.op(store, r, "node_complete", %{"node_id" => "done"})
    r = F.prepare(store, r, F.target("B", "request-B", "prepared"), %{})
    r = wrapping(store, r, "fatal")
    r = F.op(store, r, "call_settle", payload("fatal", ToolEvidence.error(:failure)))
    before = r
    r = F.op(store, r, "finish", %{"elapsed_ms" => 0})
    assert F.root(r)["children"]["done"] == F.root(before)["children"]["done"]
    assert F.root(r)["children"]["idle"]["status"] == "cancelled"
    assert F.root(r)["children"]["idle"]["frame"] == F.root(before)["children"]["idle"]["frame"]
    batch = ToolEvidence.key("B", "request-B")

    for id <- ["done", "idle", "prepared"] do
      old = F.root(before)["tool_batches"][batch]["calls"][id]

      assert F.root(r)["tool_batches"][batch]["calls"][id] ==
               old |> Map.put("state", "blocked") |> Map.put("blocked_by", "fatal")
    end

    assert F.root(r)["tool_batches"][batch]["observations"] ==
             F.root(before)["tool_batches"][batch]["observations"]

    assert r["execution"]["effects"] == before["execution"]["effects"]

    # A completed child always materialized raw + observation + leaf outcome in
    # the same ACK; deleting all three cannot masquerade as unstarted cancellation.
    invalid =
      r
      |> put_in(
        ["execution", "progress", "runtime", "tool_batches", batch, "calls", "done", "raw"],
        nil
      )
      |> update_in(
        ["execution", "progress", "runtime", "tool_batches", batch, "observations"],
        &Map.delete(&1, ToolEvidence.effect_id("B", "request-B", "done"))
      )
      |> update_in(
        ~w(execution progress runtime children B frame outcomes),
        &Map.delete(&1, "done")
      )

    assert {:error, :invalid_record} =
             Record.validate(invalid, {store.namespace, :agent, "conversation"})
  end

  test "pause reclaim fatal preserves confirmed prefix, typed retry and qualified accounting without a second refund",
       %{store: store} do
    {r, paused} = S.reclaim(store, S.draining(store))
    target = F.target("E", "request-E", "one")
    r = F.op(store, r, "call_prepared", Map.put(target, "args", %{}))
    r = F.op(store, r, "begin_effect", target)
    data = payload("one") |> Map.merge(target)
    r = F.op(store, r, "outcome", data)
    r = F.op(store, r, "call_wrap", target)
    data = put_in(data, ["control", "error"], ToolEvidence.error(:failure))
    r = F.op(store, r, "call_settle", data)
    before = r
    r = F.op(store, r, "finish", %{"elapsed_ms" => 19})
    assert paused["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_987
    assert r["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_968
    assert F.root(r)["children"]["A"] == F.root(before)["children"]["A"]
    assert F.root(r)["children"]["A"]["result"] == "A output"
    refute Map.has_key?(F.root(r)["children"], "C")
    assert is_nil(F.root(r)["children"]["B"]["result"])
    assert F.root(r)["scope"] == F.root(before)["scope"]
    assert F.root(r)["output_resolutions"] == F.root(before)["output_resolutions"]
    assert r["execution"]["progress"]["approvals"] == before["execution"]["progress"]["approvals"]
  end

  test "admitted Model drains after fatal but cannot authorize another batch or output callback",
       %{store: store} do
    r = S.draining(store)
    {r, _} = S.reclaim(store, r)
    r = F.commit(store, r, O.request(r, "admitted"))
    target = F.target("E", "request-E", "one")
    r = F.op(store, r, "call_prepared", Map.put(target, "args", %{}))
    r = F.op(store, r, "begin_effect", target)
    data = Map.merge(payload("one"), target)
    r = F.op(store, r, "outcome", data)
    r = F.op(store, r, "call_wrap", target)

    r =
      F.op(
        store,
        r,
        "call_settle",
        put_in(data, ["control", "error"], ToolEvidence.error(:failure))
      )

    reject(store, r, F.worker(r, "finish", %{"elapsed_ms" => 1}))
    r = O.response(store, r, "admitted")
    reject(store, r, O.resolution(r, "succeeded"))
    reject(store, r, F.worker(r, "batch_begin", F.target("D", "admitted")))
    before = r
    r = F.op(store, r, "finish", %{"elapsed_ms" => 1})
    assert r["execution"]["effects"] == before["execution"]["effects"]
    assert F.root(r)["children"]["D"]["snapshot"] == F.root(before)["children"]["D"]["snapshot"]
    assert F.root(r)["children"]["D"]["result"] == nil
    assert Record.cleanup_reserve_bytes(r) == 0
  end

  test "nested siblings close with the structural first fatal independent of settlement arrival",
       %{store: store} do
    for {suffix, order} <- [{"a", ["E", "D"]}, {"b", ["D", "E"]}] do
      store = %{store | namespace: "failed-nested-#{suffix}"}
      r = F.started(store)
      r = F.model(store, r, "B", "request-B", [F.call("delegate", "D"), F.call("delegate", "E")])
      r = attach(store, r, "D")
      r = attach(store, r, "E")
      r = F.model(store, r, "D", "request-D", [F.call("plain", "fatal"), F.call("delegate", "G")])
      r = attach(store, r, "G", "D")
      r = F.model(store, r, "E", "request-E", [F.call("plain", "fatal")])
      r = wrapping(store, r, "fatal", "D")
      r = wrapping(store, r, "fatal", "E")

      r =
        Enum.reduce(order, r, fn run, r ->
          p =
            Map.merge(
              payload("fatal", Map.put(ToolEvidence.error(:failure), "message", run)),
              F.target(run, "request-#{run}", "fatal")
            )

          F.op(store, r, "call_settle", p)
        end)

      before = r
      r = F.op(store, r, "finish", %{"elapsed_ms" => 0})
      assert F.root(r)["frontier"]["fatal"]["run_id"] == "D"
      assert F.root(r)["frontier"]["fatal"]["error"]["message"] == "D"
      assert F.root(r)["children"]["G"]["status"] == "cancelled"
      assert F.root(r)["scope"] == F.root(before)["scope"]
      assert r["execution"]["effects"] == before["execution"]["effects"]
      assert Enum.all?(F.root(r)["children"], fn {_, n} -> is_nil(n["result"]) end)
      key = {store.namespace, :agent, "conversation"}
      effect_id = ToolEvidence.effect_id("D", "request-D", "fatal")

      assert {:error, :invalid_record} =
               Record.validate(
                 put_in(r, ["execution", "effects", effect_id, "state"], "running"),
                 key
               )

      assert {:error, :invalid_record} =
               Record.validate(
                 put_in(r, ["execution", "effects", effect_id, "outcome", "status"], "unknown"),
                 key
               )

      assert {:error, :invalid_record} =
               Record.validate(
                 put_in(r, ~w(execution progress runtime children G status), "completed"),
                 key
               )
    end
  end

  defp capacity_flow(store, limit) do
    target = F.target("B", "request-B", "fatal")

    error = %{
      ToolEvidence.error(:failure)
      | "message" => String.duplicate(<<1>>, 512),
        "details" => %{"padding" => ""}
    }

    error =
      put_in(
        error,
        ["details", "padding"],
        String.duplicate("x", 4096 - byte_size(Jason.encode!(error)))
      )

    assert byte_size(Jason.encode!(error)) == 4096
    assert ToolEvidence.error?(error)
    raw = payload("fatal")
    escaped = String.duplicate("\"\\\n", 4096)

    raw =
      Map.put(
        raw,
        "result",
        Outcome.encode(%Part.ToolReturn{
          tool_name: "plain",
          tool_call_id: "fatal",
          content: escaped,
          status: :succeeded
        })
      )

    steps = [
      fn _ ->
        put_in(
          F.create(),
          ~w(payload execution progress runtime authority root checkpoint_limit),
          limit
        )
      end,
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
        {:ok, messages} = ExAgent.Message.from_json(node["snapshot"]["message_history"])

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

        {:ok, data} =
          ExAgent.Continuation.RequestData.capture(
            state,
            node["frame"],
            %{model_ref: F.ref()},
            F.root(r)
          )

        F.worker(r, "begin_effect", Map.put(F.target("B", "request-B"), "request_data", data))
      end,
      fn r ->
        F.worker(
          r,
          "outcome",
          Map.merge(F.target("B", "request-B"), %{
            "response" =>
              ExAgent.Message.to_json([
                %ExAgent.Message.Response{parts: [F.call("plain", "fatal")]}
              ]),
            "model_data" => nil
          })
        )
      end,
      fn r -> F.worker(r, "batch_begin", F.target("B", "request-B")) end,
      fn r -> F.worker(r, "call_prepare", target) end,
      fn r -> F.worker(r, "call_prepared", Map.put(target, "args", %{})) end,
      fn r -> F.worker(r, "begin_effect", target) end,
      fn r -> F.worker(r, "outcome", raw) end,
      fn r -> F.worker(r, "call_wrap", target) end,
      fn r -> F.worker(r, "call_settle", put_in(raw, ["control", "error"], error)) end,
      fn r -> F.worker(r, "finish", %{"elapsed_ms" => 0}) end
    ]

    Enum.reduce_while(steps, {:ok, nil, []}, fn build, {:ok, r, rows} ->
      command = C.command(r, build.(r))

      command =
        if command["operation"] == "finish",
          do: %{
            command
            | "operation_id" => String.duplicate(<<1>>, 512),
              "actor_id" => String.duplicate(<<2>>, 512)
          },
          else: command

      case Store.transition(
             store,
             :agent,
             "conversation",
             if(r, do: r["revision"], else: :absent),
             command
           ) do
        {:ok, %{record: next}} ->
          key = {store.namespace, :agent, "conversation"}
          assert {:ok, bytes} = Record.encode(next, key)
          assert {:ok, ^next} = Record.decode(bytes, key)
          {:cont, {:ok, next, rows ++ [{command, next, C.cost(next)}]}}

        error ->
          assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
          {:halt, {:rejected, command, error, r, rows}}
      end
    end)
  end

  test "fatal closure capacity is reserved before dispatch with escaped maximum error and receipt, exact boundary ±1",
       %{store: store} do
    {:ok, _, rows} = capacity_flow(%{store | namespace: "failed-boundR"}, Record.max_bytes())
    {peak_command, _, peak} = Enum.max_by(rows, &elem(&1, 2))
    assert peak_command["operation"] == "begin_effect"
    assert peak_command["payload"]["call_id"] == "fatal"
    limit = peak - byte_size(to_string(Record.max_bytes())) + byte_size(to_string(peak))

    for {delta, suffix} <- [{-1, "L"}, {0, "E"}, {1, "H"}] do
      scoped = %{store | namespace: "failed-bound#{suffix}"}

      case capacity_flow(scoped, limit + delta) do
        {:rejected, command, {:error, :record_limit}, before, _} ->
          assert delta == -1
          assert command["operation"] == "begin_effect"
          assert command["payload"]["call_id"] == "fatal"
          assert map_size(before["execution"]["effects"]) == 1

        {:ok, r, actual} ->
          assert delta in [0, 1]
          assert r["execution"]["state"] == "failed"
          assert Record.cleanup_reserve_bytes(r) == 0
          assert Enum.all?(actual, &(elem(&1, 2) <= limit + delta))
          assert byte_size(Jason.encode!(F.root(r)["children"]["B"]["error"])) == 4096
          assert F.root(r)["children"]["B"]["result"] == nil
      end
    end
  end
end
