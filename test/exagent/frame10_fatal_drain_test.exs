defmodule ExAgent.Frame10FatalDrainTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Message, Store}
  alias ExAgent.Message.Part
  alias ExAgent.Continuation.{Outcome, Record, ToolEvidence}
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Frame10OutputCapacityFixture, as: C

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "fatal-drain10")}
  end

  defp result(id, error \\ nil) do
    Map.merge(F.target("B", "request-B", id), %{
      "result" =>
        Outcome.encode(%Part.ToolReturn{
          tool_name: "plain",
          tool_call_id: id,
          content: "exact #{id}",
          status: :succeeded
        }),
      "control" => %{"retry" => false, "error" => error}
    })
  end

  defp wrapping(store, record, id) do
    target = F.target("B", "request-B", id)
    record = F.prepare(store, record, target, %{})
    record = F.op(store, record, "begin_effect", target)
    record = F.op(store, record, "outcome", result(id))
    F.op(store, record, "call_wrap", target)
  end

  defp error(id), do: Map.put(ToolEvidence.error(:fatal_probe), "message", id)

  defp attach(store, record, parent, request, call, id) do
    target = F.target(parent, request, call)
    record = F.prepare(store, record, target, %{"task" => "child input"})

    binding =
      F.root(record)["tool_batches"][ToolEvidence.key(parent, request)]["calls"][call]["binding"]

    link =
      Map.merge(binding, %{
        "kind" => "delegate",
        "parent_request_id" => request,
        "call_id" => call
      })

    node =
      F.node(F.root(record), id, parent, link) |> put_in(["frame", "tool_return_bytes"], 4096)

    F.op(
      store,
      record,
      "node_attach",
      Map.merge(target, %{"node_id" => id, "node" => node, "authority" => F.authority()})
    )
  end

  defp nested_wrapping(store, record, run) do
    request = "request-#{run}"
    record = F.model(store, record, run, request, [F.call("plain", "one")])
    target = F.target(run, request, "one")
    record = F.prepare(store, record, target, %{})
    record = F.op(store, record, "begin_effect", target)
    payload = Map.merge(result("one"), target)
    record = F.op(store, record, "outcome", payload)
    F.op(store, record, "call_wrap", target)
  end

  defp reject(store, record, command) do
    assert {:error, _} =
             Store.transition(store, :agent, "conversation", record["revision"], command)

    assert {:ok, ^record} = Store.load_record(store, :agent, "conversation")
  end

  defp capacity_batch(store, limit) do
    create =
      put_in(
        F.create(),
        ~w(payload execution progress runtime authority root checkpoint_limit),
        limit
      )

    record = C.commit(store, nil, create)
    record = C.commit(store, record, F.claim())

    node =
      F.node(F.root(record), "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })

    record =
      C.op(store, record, "step_input", %{
        "node_id" => "B",
        "node" => node,
        "authority" => F.authority()
      })

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

    {:ok, data} =
      ExAgent.Continuation.RequestData.capture(
        state,
        F.root(record)["children"]["B"]["frame"],
        %{model_ref: F.ref()},
        F.root(record)
      )

    record =
      C.op(
        store,
        record,
        "begin_effect",
        Map.put(F.target("B", "request-B"), "request_data", data)
      )

    record =
      C.op(
        store,
        record,
        "outcome",
        Map.merge(F.target("B", "request-B"), %{
          "response" => Message.to_json([%Message.Response{parts: [F.call("plain", "one")]}]),
          "model_data" => nil
        })
      )

    record = C.op(store, record, "batch_begin", F.target("B", "request-B"))
    target = F.target("B", "request-B", "one")
    record = C.op(store, record, "call_prepare", target)
    record = C.op(store, record, "call_prepared", Map.put(target, "args", %{}))
    {record, C.command(record, F.worker(record, "begin_effect", target))}
  end

  test "dispatch boundary reserves frontier copy through fatal ACK without extra IO", %{
    store: store
  } do
    store = %{store | namespace: "fatal-capacity-ref"}
    {record, command} = capacity_batch(store, Record.max_bytes())
    record = F.commit(store, record, command)
    cost = C.cost(record)
    boundary = cost - byte_size(to_string(Record.max_bytes())) + byte_size(to_string(cost))

    for {delta, namespace} <- [
          {-1, "fatal-capacity-low"},
          {0, "fatal-capacity-eq0"},
          {1, "fatal-capacity-hi1"}
        ] do
      store = %{store | namespace: namespace}
      {record, command} = capacity_batch(store, boundary + delta)

      if delta == -1 do
        assert {:error, :record_limit} =
                 Store.transition(store, :agent, "conversation", record["revision"], command)

        assert {:ok, ^record} = Store.load_record(store, :agent, "conversation")
      else
        record = F.commit(store, record, command)
        target = F.target("B", "request-B", "one")
        record = C.op(store, record, "outcome", result("one"))
        record = C.op(store, record, "call_wrap", target)
        error = ToolEvidence.reservation_error()
        assert ToolEvidence.error?(error)
        assert byte_size(Jason.encode!(error)) == 4096
        record = C.op(store, record, "call_settle", result("one", error))
        assert F.root(record)["frontier"]["fatal"]["error"] === error
        assert C.cost(record) <= boundary + delta
      end
    end
  end

  for order <- [["first", "second"], ["second", "first"]] do
    test "confirmed selection uses original call order, arrival #{inspect(order)}", %{
      store: store
    } do
      order = unquote(order)

      record =
        F.model(store, F.started(store), "B", "request-B", [
          F.call("plain", "first"),
          F.call("plain", "second"),
          F.call("plain", "queued")
        ])

      record = wrapping(store, record, "first")
      record = wrapping(store, record, "second")
      before = record
      record = F.op(store, record, "call_settle", result(hd(order), error(hd(order))))
      assert F.root(record)["frontier"]["reason"] == "fatal"
      assert F.root(record)["frontier"]["epoch"] == 1
      assert Record.unresolved?(record["execution"])

      reject(
        store,
        record,
        F.worker(record, "call_prepare", F.target("B", "request-B", "queued"))
      )

      reject(
        store,
        record,
        F.worker(record, "step_output", %{"node_id" => "B", "elapsed_ms" => 0})
      )

      reject(store, record, F.worker(record, "pause", %{"elapsed_ms" => 0}))
      reject(store, record, F.worker(record, "recover"))

      command = F.worker(record, "call_settle", result(List.last(order), error(List.last(order))))
      expected = record["revision"]
      record = F.commit(store, record, command)
      assert F.root(record)["frontier"]["fatal"]["call_id"] == "first"
      assert F.root(record)["frontier"]["fatal"]["error"] == error("first")
      assert F.root(record)["frontier"]["epoch"] == 1
      assert F.root(record)["scope"] === F.root(before)["scope"]

      assert record["execution"]["progress"]["active_budget"] ===
               before["execution"]["progress"]["active_budget"]

      assert {:ok, %{replayed: true, record: ^record}} =
               Store.transition(store, :agent, "conversation", expected, command)

      reject(store, record, put_in(command, ["payload", "control", "error"], error("conflict")))
      reject(store, record, F.worker(record, "tool_resolution", F.target("B", "request-B")))

      key = {store.namespace, :agent, "conversation"}

      mutated =
        put_in(
          record,
          ["execution", "progress", "runtime", "frontier", "fatal", "call_id"],
          "second"
        )

      assert {:error, _} = Record.validate(mutated, key)

      mutated =
        put_in(
          record,
          ["execution", "progress", "runtime", "frontier"],
          F.root(before)["frontier"]
        )

      assert {:error, _} = Record.validate(mutated, key)
    end
  end

  test "admitted raw drains after close; no new wrapper, dispatch or fabricated final", %{
    store: store
  } do
    record =
      F.model(store, F.started(store), "B", "request-B", [
        F.call("plain", "fatal"),
        F.call("plain", "admitted"),
        F.call("plain", "prepared")
      ])

    record = wrapping(store, record, "fatal")
    record = F.prepare(store, record, F.target("B", "request-B", "admitted"), %{})
    record = F.op(store, record, "begin_effect", F.target("B", "request-B", "admitted"))
    record = F.prepare(store, record, F.target("B", "request-B", "prepared"), %{})
    record = F.op(store, record, "call_settle", result("fatal", error("fatal")))
    assert Record.unresolved?(record["execution"])

    reject(
      store,
      record,
      F.worker(record, "begin_effect", F.target("B", "request-B", "prepared"))
    )

    record = F.op(store, record, "outcome", result("admitted"))
    call = F.root(record)["tool_batches"][ToolEvidence.key("B", "request-B")]["calls"]["admitted"]
    assert call["raw"]["result"] == result("admitted")["result"]
    assert call["source"]["kind"] == "effect"
    assert call["state"] == "dispatching"
    assert is_nil(call["result"])
    reject(store, record, F.worker(record, "call_wrap", F.target("B", "request-B", "admitted")))
    reject(store, record, F.worker(record, "call_settle", result("admitted")))
    before = record
    record = F.op(store, record, "finish", %{"elapsed_ms" => 0})
    assert record["execution"]["state"] == "failed"
    assert record["execution"]["effects"] === before["execution"]["effects"]
    key = ToolEvidence.key("B", "request-B")
    blocked = F.root(record)["tool_batches"][key]["calls"]["admitted"]
    assert blocked === call |> Map.put("state", "blocked") |> Map.put("blocked_by", "fatal")

    invalid =
      put_in(
        record,
        ["execution", "progress", "runtime", "tool_batches", key, "calls", "admitted", "raw"],
        nil
      )

    assert {:error, :invalid_record} =
             Record.validate(invalid, {store.namespace, :agent, "conversation"})
  end

  test "unknown final is not confirmed fatal and preserves wrapping evidence", %{store: store} do
    record = F.model(store, F.started(store), "B", "request-B", [F.call("plain", "one")])
    record = wrapping(store, record, "one")

    unknown =
      Outcome.encode(%Part.ToolReturn{
        tool_name: "plain",
        tool_call_id: "one",
        content: "unknown",
        status: :unknown
      })

    reject(
      store,
      record,
      F.worker(record, "call_settle", Map.put(result("one", error("one")), "result", unknown))
    )

    assert is_nil(F.root(record)["frontier"]["fatal"])
    assert Record.unresolved?(record["execution"])

    assert {:ok, [%Message.Request{parts: [%Part.ToolReturn{status: :succeeded}]}]} =
             Message.from_json(result("one")["result"])
  end

  for arrival <- [["grandchild", "a-later"], ["a-later", "grandchild"]] do
    test "nested deterministic path ignores run ID and arrival #{inspect(arrival)}", %{
      store: store
    } do
      record =
        F.model(store, F.started(store), "B", "request-B", [
          F.call("delegate", "z-first", %{"task" => "child input"}),
          F.call("delegate", "a-second", %{"task" => "child input"})
        ])

      record = attach(store, record, "B", "request-B", "z-first", "z-earlier")
      record = attach(store, record, "B", "request-B", "a-second", "a-later")

      record =
        F.model(store, record, "z-earlier", "nested", [
          F.call("delegate", "deep", %{"task" => "child input"})
        ])

      record = attach(store, record, "z-earlier", "nested", "deep", "grandchild")
      record = nested_wrapping(store, record, "grandchild")
      record = nested_wrapping(store, record, "a-later")
      before = record

      record =
        Enum.reduce(unquote(arrival), record, fn run, record ->
          payload = Map.merge(result("one", error(run)), F.target(run, "request-#{run}", "one"))
          F.op(store, record, "call_settle", payload)
        end)

      assert F.root(record)["frontier"]["fatal"]["run_id"] == "grandchild"
      assert F.root(record)["scope"] === F.root(before)["scope"]
      assert F.root(record)["children"]["B"] === F.root(before)["children"]["B"]
      assert F.root(record)["children"]["z-earlier"] === F.root(before)["children"]["z-earlier"]
      reject(store, record, F.worker(record, "node_complete", %{"node_id" => "grandchild"}))
      reject(store, record, F.worker(record, "node_suspend", %{"node_id" => "B"}))
      key = {store.namespace, :agent, "conversation"}

      invalid =
        put_in(record, ~w(execution progress runtime frontier fatal), %{
          "kind" => "root",
          "error" => error("invented")
        })

      assert {:error, _} = Record.validate(invalid, key)
    end
  end

  test "fatal replaces approval drain without publishing approvals or refund", %{store: store} do
    record =
      F.model(store, F.started(store), "B", "request-B", [
        F.call("plain", "fatal"),
        F.call("delegate", "child", %{"task" => "child input"})
      ])

    record = wrapping(store, record, "fatal")
    target = F.target("B", "request-B", "child")
    record = F.prepare(store, record, target, %{"task" => "child input"})

    binding =
      F.root(record)["tool_batches"][ToolEvidence.key("B", "request-B")]["calls"]["child"][
        "binding"
      ]

    link =
      Map.merge(binding, %{
        "kind" => "delegate",
        "parent_request_id" => "request-B",
        "call_id" => "child"
      })

    node = F.node(F.root(record), "D", "B", link)

    authority =
      update_in(F.authority(), ["policies"], &(&1 ++ [%{"default" => "ask", "rules" => []}]))

    record =
      F.op(
        store,
        record,
        "node_attach",
        Map.merge(target, %{"node_id" => "D", "node" => node, "authority" => authority})
      )

    record = F.model(store, record, "D", "ask", [F.call("plain", "pending")])
    record = F.prepare(store, record, F.target("D", "ask", "pending"), %{})
    record = F.op(store, record, "call_wait", F.target("D", "ask", "pending"))
    before = record
    record = F.op(store, record, "call_settle", result("fatal", error("fatal")))
    assert F.root(record)["frontier"]["epoch"] == F.root(before)["frontier"]["epoch"]
    assert F.root(record)["frontier"]["reason"] == "fatal"

    assert record["execution"]["progress"]["approvals"] ===
             before["execution"]["progress"]["approvals"]

    assert record["execution"]["progress"]["active_budget"] ===
             before["execution"]["progress"]["active_budget"]

    assert F.root(record)["children"]["D"] === F.root(before)["children"]["D"]
    reject(store, record, F.worker(record, "pause", %{"elapsed_ms" => 20}))
  end

  test "completed child and exact raw survive a different fatal wrapper result", %{store: store} do
    record =
      F.model(store, F.started(store), "B", "request-B", [
        F.call("delegate", "child", %{"task" => "child input"}),
        F.call("plain", "fatal")
      ])

    record = attach(store, record, "B", "request-B", "child", "D")
    record = F.model(store, record, "D", "done", [%Part.Text{content: "child raw X"}])
    record = F.op(store, record, "node_complete", %{"node_id" => "D"})
    target = F.target("B", "request-B", "child")
    record = F.op(store, record, "call_wrap", target)
    record = wrapping(store, record, "fatal")
    before = record
    record = F.op(store, record, "call_settle", result("fatal", error("fatal")))

    payload =
      Map.merge(target, %{
        "result" =>
          Outcome.encode(%Part.ToolReturn{
            tool_name: "delegate",
            tool_call_id: "child",
            content: "wrapper Y",
            status: :failed
          }),
        "control" => %{"retry" => false, "error" => error("child-wrapper")}
      })

    record = F.op(store, record, "call_settle", payload)
    batch_key = ToolEvidence.key("B", "request-B")
    call = F.root(record)["tool_batches"][batch_key]["calls"]["child"]
    assert call["result"] === payload["result"]
    assert call["raw"] === F.root(before)["tool_batches"][batch_key]["calls"]["child"]["raw"]
    assert call["source"] === %{"kind" => "child", "id" => "D"}
    assert F.root(record)["children"]["D"] === F.root(before)["children"]["D"]
    assert F.root(record)["frontier"]["fatal"]["call_id"] == "child"

    assert F.root(record)["tool_batches"][batch_key]["observations"] ===
             F.root(before)["tool_batches"][batch_key]["observations"]

    reject(store, record, F.worker(record, "node_complete", %{"node_id" => "D"}))
    reject(store, record, F.worker(record, "cancel"))
  end

  test "already admitted Model observation drains with qualified usage but no new batch or request",
       %{store: store} do
    alias ExAgent.Continuation.RequestData
    alias ExAgent.Message.Usage

    record =
      F.model(store, F.started(store), "B", "request-B", [
        F.call("delegate", "child", %{"task" => "child input"}),
        F.call("plain", "fatal")
      ])

    record = attach(store, record, "B", "request-B", "child", "D")
    record = wrapping(store, record, "fatal")
    node = F.root(record)["children"]["D"]
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

    {:ok, data} = RequestData.capture(state, node["frame"], %{model_ref: F.ref()}, F.root(record))

    record =
      F.op(
        store,
        record,
        "begin_effect",
        Map.put(F.target("D", "admitted"), "request_data", data)
      )

    stale = F.worker(record, "call_settle", result("fatal", error("fatal")))
    record = F.commit(store, record, stale)

    reject(
      store,
      record,
      F.worker(record, "begin_effect", Map.put(F.target("D", "new"), "request_data", data))
    )

    usage =
      Usage.qualify(%Usage{input_tokens: 7, output_tokens: 2}) |> Usage.with_cost(3, "estimator")

    payload =
      Map.merge(F.target("D", "admitted"), %{
        "response" =>
          Message.to_json([
            %Message.Response{parts: [F.call("plain", "not-admitted")], usage: usage}
          ]),
        "model_data" => nil
      })

    command = F.worker(record, "outcome", payload)
    reject(store, record, put_in(command, ["payload", "epoch"], 0))
    reject(store, record, put_in(command, ["payload", "fence"], record["execution"]["fence"] - 1))
    record = F.commit(store, record, command)
    scope = F.root(record)["scope"]

    for run <- ["root", "B", "D"] do
      {:ok, sum} = ExAgent.Continuation.ScopeLedger.usage(scope, run)
      assert sum.input_tokens == 7
      assert sum.output_tokens == 2
      assert sum === Usage.sum(if(run == "D", do: [usage], else: [nil, usage]))
      assert sum.accounting["cost"]["subtotal_cents"] == 3
      assert sum.accounting["cost"]["cents"] == if(run == "D", do: 3, else: nil)
    end

    assert scope["nodes"]["root"]["requests"] == 2
    assert F.root(record)["children"]["D"]["frame"]["cursor"] == "response"
    reject(store, record, F.worker(record, "batch_begin", F.target("D", "admitted")))

    assert {:ok, %{replayed: true, record: ^record}} =
             Store.transition(store, :agent, "conversation", record["revision"] - 1, command)
  end
end
