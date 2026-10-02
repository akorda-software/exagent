defmodule ExAgent.Frame10AccountingTest do
  use ExUnit.Case, async: true
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Continuation.{Frame, Outcome, Record, ScopeLedger, ToolEvidence}
  alias ExAgent.{Message, Store}
  alias ExAgent.Message.{Part, Usage}

  # Trusted synthetic callback inputs, real ETS/CAS and encode/decode on every ACK.
  # No producer10, live callbacks, VM restart or upstream billing claim.
  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "accounting10")}
  end

  defp priced(n),
    do:
      Usage.qualify(%Usage{input_tokens: n, output_tokens: 1}) |> Usage.with_cost(n, "estimator")

  defp boundary_usage(:max_budget_cents, delta),
    do: Usage.with_cost(priced(1), 10 + delta, "estimator")

  defp boundary_usage(:total_tokens_limit, delta),
    do: Usage.qualify(%Usage{input_tokens: 9 + delta, output_tokens: 1})

  defp scope(r), do: F.root(r)["scope"]
  defp batch(r, run, request), do: F.root(r)["tool_batches"][ToolEvidence.key(run, request)]

  defp payload(target, usage) do
    Map.merge(target, %{
      "result" =>
        Outcome.encode(%Part.ToolReturn{
          tool_name: "plain",
          tool_call_id: target["call_id"],
          content: "raw",
          status: :succeeded
        }),
      "control" => %{"retry" => false, "error" => nil},
      "usage" => Usage.to_map(usage)
    })
  end

  defp reject(store, r, command) do
    assert {:error, _} = Store.transition(store, :agent, "conversation", r["revision"], command)
    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end

  defp consume(store, r, run, request) do
    r = F.op(store, r, "tool_resolution", F.target(run, request))
    F.op(store, r, "batch_consume", F.target(run, request))
  end

  defp started_limits(store, limits, checkpoint_limit \\ Record.max_bytes()) do
    command =
      put_in(
        F.create(),
        ["payload", "execution", "progress", "runtime", "authority", "root", "usage"],
        ExAgent.Continuation.Authority.usage(limits)
      )

    command =
      put_in(
        command,
        ["payload", "execution", "progress", "runtime", "authority", "root", "checkpoint_limit"],
        checkpoint_limit
      )

    r = F.commit(store, nil, command)
    r = F.commit(store, r, F.claim())

    node =
      F.node(F.root(r), "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })

    F.op(store, r, "step_input", %{"node_id" => "B", "node" => node, "authority" => F.authority()})
  end

  defp model_command(r, run, request) do
    root = F.root(r)
    node = root["children"][run]
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
      ExAgent.Continuation.RequestData.capture(state, node["frame"], %{model_ref: F.ref()}, root)

    F.worker(r, "begin_effect", Map.put(F.target(run, request), "request_data", data))
  end

  test "orphan/missing/duplicate/status/digest/availability/ancestor mutations reject globally",
       %{store: store} do
    r = F.model(store, F.started(store), "B", "B1", [F.call("plain", "one")], true, priced(2))
    r = F.settled(store, r, F.target("B", "B1", "one"), "raw", priced(3))
    root = F.root(r)
    key = ToolEvidence.key("B", "B1")
    effect = ToolEvidence.effect_id("B", "B1", "one")

    model =
      Enum.find_value(r["execution"]["effects"], fn {id, e} ->
        if e["intent"]["kind"] == "model", do: id
      end)

    bad_roots = [
      update_in(root, ["scope", "operations"], &Enum.drop(&1, -1)),
      update_in(root, ["scope", "operations"], &(&1 ++ [List.last(&1)])),
      update_in(root, ["scope", "operations"], fn ops ->
        List.update_at(ops, 1, &put_in(&1, ["id"], ["tool", "B1", "orphan"]))
      end),
      put_in(root, ["tool_batches", key, "observations"], %{}),
      put_in(
        root,
        ["tool_batches", key, "observations", effect, "application", "status"],
        "none"
      ),
      put_in(
        root,
        ["tool_batches", key, "observations", effect, "application", "complete"],
        false
      ),
      put_in(
        root,
        [
          "tool_batches",
          key,
          "observations",
          effect,
          "usage",
          "accounting",
          "availability",
          "input"
        ],
        "partial"
      ),
      update_in(root, ["scope", "operations"], fn ops ->
        List.update_at(ops, 1, &put_in(&1, ["ancestors", "root", "input_tokens"], 99))
      end)
    ]

    for bad <- bad_roots do
      assert {:error, _} =
               Record.validate(
                 put_in(r, ["execution", "progress", "runtime"], bad),
                 {store.namespace, :agent, "conversation"}
               )
    end

    for id <- [effect, model],
        field <- if(id == effect, do: ["raw_hash", "result_hash"], else: ["response_hash"]) do
      bad =
        put_in(
          r,
          ["execution", "effects", id, "outcome", "data", field],
          String.duplicate("f", 64)
        )

      assert {:error, _} = Record.validate(bad, {store.namespace, :agent, "conversation"})
    end

    # Even reprojecting all snapshots cannot legitimize repricing an ancestor.
    bad =
      update_in(root, ["scope", "operations"], fn ops ->
        List.update_at(ops, 1, fn op ->
          put_in(op, ["ancestors", "root"], Usage.to_map(priced(99)))
        end)
      end)

    bad = Frame.with_scope(bad, bad["scope"])

    bad =
      update_in(bad, ["children"], fn nodes ->
        Map.new(nodes, fn {id, node} ->
          {id, put_in(node, ["snapshot", "usage"], Frame.usage10(bad["scope"], id))}
        end)
      end)

    assert {:error, _} =
             Record.validate(
               put_in(r, ["execution", "progress", "runtime"], bad),
               {store.namespace, :agent, "conversation"}
             )
  end

  for delta <- [-1, 0, 1] do
    test "retrospective token/cost cap at exact #{delta} uses existing >= threshold, preserves outcome",
         %{store: store} do
      delta = unquote(delta)

      limits = %ExAgent.UsageLimits{
        request_limit: 5,
        total_tokens_limit: 10,
        max_budget_cents: 10,
        accounting: :estimated
      }

      r = started_limits(store, limits)

      usage =
        Usage.qualify(%Usage{input_tokens: 9 + delta, output_tokens: 1})
        |> Usage.with_cost(10 + delta, "estimator")

      r = F.model(store, r, "B", "B1", [F.call("plain", "one")], false, usage)
      cmd = F.worker(r, "batch_begin", F.target("B", "B1"))

      if delta < 0 do
        r = F.commit(store, r, cmd)
        r = F.settled(store, r, F.target("B", "B1", "one"), "raw", priced(1))
        r = consume(store, r, "B", "B1")
        reject(store, r, model_command(r, "B", "B2"))
      else
        reject(store, r, cmd)
      end

      assert hd(scope(r)["operations"])["usage"] === Usage.to_map(usage)
    end
  end

  test "request/tool reservations are enforced once and strict normalized accounting blocks later effects",
       %{store: store} do
    r = started_limits(store, %ExAgent.UsageLimits{request_limit: 1, tool_calls_limit: 1})
    r = F.model(store, r, "B", "B1", [F.call("plain", "one")], true, priced(1))
    r = F.settled(store, r, F.target("B", "B1", "one"), "raw", priced(1))
    r = consume(store, r, "B", "B1")
    assert scope(r)["nodes"]["root"]["requests"] == 1
    assert scope(r)["nodes"]["root"]["tools"] == 1
    reject(store, r, model_command(r, "B", "B2"))
    other = Store.scoped({Store.ETS, __MODULE__}, "strict")
    r = started_limits(other, %ExAgent.UsageLimits{request_limit: 5, total_tokens_limit: 100})

    r =
      F.model(
        other,
        r,
        "B",
        "B1",
        [F.call("plain", "one")],
        false,
        Usage.normalized(%{input_tokens: 2, output_tokens: 1})
      )

    reject(other, r, F.worker(r, "batch_begin", F.target("B", "B1")))
  end

  for delta <- [-1, 0, 1] do
    test "tool usage retention exact #{delta} and CAS JSON/closure receipts", %{store: store} do
      delta = unquote(delta)
      r = F.model(store, F.started(store), "B", "B1", [F.call("plain", "one")], true, priced(1))
      target = F.target("B", "B1", "one")
      r = F.prepare(store, r, target, %{})
      r = F.op(store, r, "begin_effect", target)
      base = ToolEvidence.reservation_usage()
      size = byte_size(base.details["reservation"]) + delta
      usage = %{base | details: %{"reservation" => String.duplicate(<<1>>, size)}}
      assert ExAgent.Retention.bytes(usage) == ExAgent.Retention.usage_bytes() + delta
      cmd = F.worker(r, "outcome", payload(target, usage))

      if delta > 0 do
        reject(store, r, cmd)
      else
        r = F.commit(store, r, cmd)
        assert {:ok, json} = Record.encode(r, {store.namespace, :agent, "conversation"})
        assert byte_size(json) < Record.max_bytes()
        # Real admitted row, exact total capacity includes closure and receipt reserve.
        needed = byte_size(Jason.encode!(r)) + Record.cleanup_reserve_bytes(r)

        for adjustment <- [-1, 0, 1] do
          bounded =
            put_in(
              r,
              ["execution", "progress", "runtime", "authority", "root", "checkpoint_limit"],
              needed + adjustment
            )

          # The limit itself has the same decimal width here.
          measured = byte_size(Jason.encode!(bounded)) + Record.cleanup_reserve_bytes(bounded)

          bounded =
            put_in(
              bounded,
              ["execution", "progress", "runtime", "authority", "root", "checkpoint_limit"],
              measured + adjustment
            )

          if adjustment < 0,
            do:
              assert(
                Record.validate(bounded, {store.namespace, :agent, "conversation"}) ==
                  {:error, :record_limit}
              ),
            else:
              assert(Record.validate(bounded, {store.namespace, :agent, "conversation"}) == :ok)
        end

        saved = scope(r)
        r = F.op(store, r, "call_wrap", target)
        r = F.op(store, r, "call_settle", Map.delete(payload(target, usage), "usage"))
        r = consume(store, r, "B", "B1")
        assert scope(r) === saved
      end
    end
  end

  test "ScopeLedger allnil/mixed/complete/partial uses existing sum and retains quality", %{
    store: store
  } do
    r = F.model(store, F.started(store), "B", "B1", [F.call("plain", "one")])
    assert :ok = ScopeLedger.validate(scope(r))
    assert {:ok, absent} = ScopeLedger.usage(scope(r), "root")
    assert absent === Usage.qualify(nil)

    for usage <- [
          priced(3),
          Usage.partial(priced(3)),
          Usage.normalized(%{input_tokens: 3, output_tokens: 2})
        ] do
      data = Usage.to_map(usage)

      op = %{
        "id" => ["tool", "B1", "one"],
        "run_id" => "B",
        "usage" => data,
        "terminal_usage" => data,
        "complete" => Usage.complete?(usage),
        "ancestors" => %{"root" => data, "B" => data}
      }

      mixed = update_in(scope(r), ["operations"], &(&1 ++ [op]))
      assert :ok = ScopeLedger.validate(mixed)
      assert {:ok, total} = ScopeLedger.usage(mixed, "root")
      assert total === Usage.sum([nil, usage])

      complete =
        put_in(mixed, ["operations"], [
          Map.merge(
            hd(mixed["operations"]),
            Map.take(op, ~w(usage terminal_usage complete ancestors))
          )
        ])

      assert {:ok, ^usage} = ScopeLedger.usage(complete, "root")
    end
  end

  test "partial Model report and normalized public cost keep qualification, units and provenance",
       %{store: store} do
    reports = [
      Usage.partial(priced(3)),
      Usage.normalized(%{
        input_tokens: 4,
        output_tokens: 2,
        total_cost: 0.03,
        input_includes_cached: false
      }),
      Usage.normalized(%{input_tokens: 4, total_cost: 0.03}, "EUR")
    ]

    for {usage, index} <- Enum.with_index(reports) do
      store = %{store | namespace: "reports-#{index}"}

      r =
        F.model(
          store,
          F.started(store),
          "B",
          "B1",
          [%Part.Text{content: "synthetic"}],
          true,
          usage
        )

      operation = hd(scope(r)["operations"])
      assert operation["complete"] == Usage.complete?(usage)
      assert operation["usage"] === Usage.to_map(usage)

      for id <- ["root", "B"] do
        assert {:ok, ^usage} = ScopeLedger.usage(scope(r), id)
        assert operation["ancestors"][id] === Usage.to_map(usage)
      end

      assert F.root(r)["children"]["B"]["snapshot"]["usage"] === Usage.to_map(usage)
    end
  end

  for dimension <- [:total_tokens_limit, :max_budget_cents], delta <- [-1, 0, 1] do
    test "independent #{dimension} boundary #{delta}", %{store: store} do
      dimension = unquote(dimension)
      delta = unquote(delta)

      limits =
        struct!(ExAgent.UsageLimits, [
          {dimension, 10},
          {:request_limit, 5},
          {:accounting, :estimated}
        ])

      r = started_limits(store, limits)

      usage = boundary_usage(dimension, delta)

      r = F.model(store, r, "B", "B1", [F.call("plain", "one")], false, usage)
      command = F.worker(r, "batch_begin", F.target("B", "B1"))
      if delta < 0, do: F.commit(store, r, command), else: reject(store, r, command)
    end
  end

  for count <- [1, 2, 3] do
    test "tool quota exact +/-1 reserves batch once, count #{count}", %{store: store} do
      count = unquote(count)
      r = started_limits(store, %ExAgent.UsageLimits{request_limit: 1, tool_calls_limit: 2})

      r =
        F.model(
          store,
          r,
          "B",
          "B1",
          Enum.map(1..count, &F.call("plain", "call#{&1}")),
          false,
          priced(1)
        )

      command = F.worker(r, "batch_begin", F.target("B", "B1"))

      if count > 2 do
        reject(store, r, command)
      else
        admitted = F.commit(store, r, command)

        assert {:ok, %{record: ^admitted, replayed: true}} =
                 Store.transition(store, :agent, "conversation", r["revision"], command)

        closed =
          Enum.reduce(1..count, admitted, fn id, r ->
            F.settled(store, r, F.target("B", "B1", "call#{id}"), "raw", priced(1))
          end)

        closed = consume(store, closed, "B", "B1")
        assert scope(closed)["nodes"]["root"]["tools"] == count
        assert scope(closed)["nodes"]["root"]["requests"] == 1
      end
    end
  end

  test "retained usage remains rejected by existing ledger retention guard", %{store: store} do
    r =
      F.model(
        store,
        F.started(store),
        "B",
        "B1",
        [%Part.Text{content: "synthetic"}],
        true,
        priced(1)
      )

    marker =
      ExAgent.Retention.marker(
        :usage,
        ExAgent.Retention.usage_bytes() + 1,
        ExAgent.Retention.usage_bytes()
      )

    usage = Usage.to_map(%{priced(1) | payload_omitted: marker})

    changed =
      update_in(scope(r), ["operations"], fn [op] ->
        [
          %{
            op
            | "usage" => usage,
              "terminal_usage" => usage,
              "ancestors" => %{"root" => usage, "B" => usage}
          }
        ]
      end)

    assert {:error, :invalid_scope_checkpoint} = ScopeLedger.validate(changed)
    assert {:error, :invalid_scope_checkpoint} = ScopeLedger.usage(changed, "root")
  end

  test "valid usage exceeding actual checkpoint capacity rejects CAS with zero partial mutations",
       %{store: store} do
    r = started_limits(store, %ExAgent.UsageLimits{}, 1_750_000)
    r = F.model(store, r, "B", "B1", [F.call("plain", "one")], true, priced(1))
    target = F.target("B", "B1", "one")
    r = F.prepare(store, r, target, %{})
    r = F.op(store, r, "begin_effect", target)
    command = F.worker(r, "outcome", payload(target, ToolEvidence.reservation_usage()))

    assert {:error, :record_limit} =
             Store.transition(store, :agent, "conversation", r["revision"], command)

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    # Smaller valid contribution can close the same admitted call; no replay/readmission.
    p = payload(target, priced(1))
    r = F.op(store, r, "outcome", p)
    r = F.op(store, r, "call_wrap", target)
    r = F.op(store, r, "call_settle", Map.delete(p, "usage"))
    r = consume(store, r, "B", "B1")
    assert scope(r)["nodes"]["root"]["tools"] == 1
  end

  test "nested mixed contributions pause/two decisions/reclaim, finish D and wrapperY without double contribution",
       %{store: store} do
    usage =
      Usage.normalized(%{input_tokens: 7, output_tokens: 3}) |> Usage.with_cost(2, "estimator")

    {r, attach} = F.attached(store, F.started(store))

    attach =
      update_in(
        attach,
        ["authority", "policies"],
        &(&1 ++ [%{"default" => "ask", "rules" => [["^plain$", "", "allow"]]}])
      )

    r = F.op(store, r, "node_attach", attach)

    r =
      F.model(
        store,
        r,
        "D",
        "D1",
        [
          F.call("plain", "paid"),
          F.call("delegate", "one", %{"task" => "one"}),
          F.call("delegate", "two", %{"task" => "two"})
        ],
        true,
        usage
      )

    tool = Usage.partial(priced(4))
    r = F.settled(store, r, F.target("D", "D1", "paid"), "paid", tool)

    for id <- ["root", "B", "D"] do
      assert {:ok, total} = ScopeLedger.usage(scope(r), id)
      expected = if id == "D", do: Usage.sum([usage, tool]), else: Usage.sum([nil, usage, tool])
      assert total === expected
    end

    r =
      Enum.reduce(["one", "two"], r, fn id, r ->
        target = F.target("D", "D1", id)
        r = F.prepare(store, r, target, %{"task" => id})
        F.op(store, r, "call_wait", target)
      end)

    r = F.op(store, r, "node_suspend", %{"node_id" => "D"})
    r = F.op(store, r, "node_suspend", %{"node_id" => "B"})
    before = scope(r)
    r = F.op(store, r, "pause", %{"elapsed_ms" => 1})

    r =
      Enum.reduce(r["execution"]["progress"]["approvals"], r, fn {id, a}, r ->
        F.commit(
          store,
          r,
          F.command("decide", %{
            "approval_id" => id,
            "payload_hash" => a["payload_hash"],
            "decision" => "approve"
          })
        )
      end)

    r = F.commit(store, r, F.claim("second"))
    r = F.op(store, r, "frontier_open")
    assert scope(r) === before

    r =
      Enum.reduce(["one", "two"], r, fn id, r ->
        target = F.target("D", "D1", id)
        r = F.op(store, r, "call_prepared", Map.put(target, "args", %{"task" => id}))

        link =
          Map.merge(batch(r, "D", "D1")["calls"][id]["binding"], %{
            "kind" => "delegate",
            "parent_request_id" => "D1",
            "call_id" => id
          })

        child = F.node(F.root(r), id, "D", link)
        authority = F.root(r)["authority"]["D"]

        r =
          F.op(
            store,
            r,
            "node_attach",
            Map.merge(target, %{"node_id" => id, "node" => child, "authority" => authority})
          )

        r = F.model(store, r, id, "request-" <> id, [%Part.Text{content: id}], true, priced(1))
        r = F.op(store, r, "node_complete", %{"node_id" => id})
        saved = scope(r)
        raw = batch(r, "D", "D1")["calls"][id]["raw"]
        r = F.op(store, r, "call_wrap", target)
        r = F.op(store, r, "call_settle", Map.merge(target, raw))
        assert scope(r) === saved
        r
      end)

    r = consume(store, r, "D", "D1")
    r = F.model(store, r, "D", "D2", [%Part.Text{content: "X"}], true, priced(2))
    r = F.op(store, r, "node_complete", %{"node_id" => "D"})
    before = scope(r)
    target = F.target("B", "request-B", "delegate")
    r = F.op(store, r, "call_wrap", target)

    final =
      Outcome.encode(%Part.ToolReturn{
        tool_name: "delegate",
        tool_call_id: "delegate",
        content: "Y",
        status: :succeeded
      })

    r =
      F.op(
        store,
        r,
        "call_settle",
        Map.merge(target, %{"result" => final, "control" => %{"retry" => false, "error" => nil}})
      )

    r = consume(store, r, "B", "request-B")
    assert scope(r) === before
    assert length(scope(r)["operations"]) == 6
    assert Enum.count(scope(r)["operations"], &match?(["tool" | _], &1["id"])) == 1
    assert scope(r)["nodes"]["root"]["requests"] == 5
    assert scope(r)["nodes"]["root"]["tools"] == 4

    for id <- ["root", "B", "D"] do
      assert {:ok, total} = ScopeLedger.usage(scope(r), id)
      usages = [usage, tool, priced(1), priced(1), priced(2)]
      assert total === Usage.sum(if id == "D", do: usages, else: [nil | usages])
    end

    r = F.model(store, r, "B", "B2", [%Part.Text{content: "continued"}], true, priced(1))
    assert Enum.take(scope(r)["operations"], 6) === before["operations"]
  end

  test "partial tool operation replay/CAS loss cannot redebit; raw final consumption preserve accounting",
       %{store: store} do
    r = F.model(store, F.started(store), "B", "B1", [F.call("plain", "one")], true, priced(1))
    target = F.target("B", "B1", "one")
    r = F.prepare(store, r, target, %{})
    r = F.op(store, r, "begin_effect", target)
    p = payload(target, Usage.partial(priced(5)))
    cmd = F.worker(r, "outcome", p)
    assert {:error, _} = Store.transition(store, :agent, "conversation", r["revision"] - 1, cmd)
    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    raw = F.commit(store, r, cmd)

    assert {:ok, %{record: ^raw, replayed: true}} =
             Store.transition(store, :agent, "conversation", r["revision"], cmd)

    assert List.last(scope(raw)["operations"])["complete"] == false
    reject(store, raw, F.worker(raw, "outcome", p))
    r = F.op(store, raw, "call_wrap", target)
    reject(store, r, F.worker(r, "call_settle", p))
    r = F.op(store, r, "call_settle", Map.delete(p, "usage"))
    r = consume(store, r, "B", "B1")
    assert scope(r) === scope(raw)

    assert {:ok, %{record: ^r, replayed: true}} =
             Store.transition(store, :agent, "conversation", raw["revision"] - 1, cmd)
  end

  test "rejected accounting preserves already confirmed progress and leaves current intent unresolved",
       %{store: store} do
    r =
      F.model(
        store,
        F.started(store),
        "B",
        "B1",
        [F.call("plain", "prior"), F.call("plain", "one")],
        true,
        priced(1)
      )

    r = F.settled(store, r, F.target("B", "B1", "prior"), "paid", priced(3))
    target = F.target("B", "B1", "one")
    r = F.prepare(store, r, target, %{})
    r = F.op(store, r, "begin_effect", target)

    retained =
      Usage.to_map(%Usage{
        input_tokens: 1,
        output_tokens: 1,
        details: %{"large" => String.duplicate("x", ExAgent.Retention.usage_bytes() + 1)}
      })

    for usage <- [%{"input_tokens" => -1}, retained] do
      p = Map.put(payload(target, priced(1)), "usage", usage)
      reject(store, r, F.worker(r, "outcome", p))
    end

    assert length(scope(r)["operations"]) == 2
    assert batch(r, "B", "B1")["calls"]["prior"]["state"] == "settled"
    assert batch(r, "B", "B1")["calls"]["one"]["state"] == "dispatching"
  end

  test "zero nonnil Model usage is real observed usage; outcome receipt replay is not another application",
       %{store: store} do
    r = F.started(store)
    r = F.commit(store, r, model_command(r, "B", "B1"))
    usage = Usage.qualify(%Usage{input_tokens: 0, output_tokens: 0})
    response = %Message.Response{parts: [%Part.Text{content: "synthetic"}], usage: usage}

    p =
      Map.merge(F.target("B", "B1"), %{
        "response" => Message.to_json([response]),
        "model_data" => nil
      })

    cmd = F.worker(r, "outcome", p)
    next = F.commit(store, r, cmd)
    assert hd(scope(next)["operations"])["usage"] === Usage.to_map(usage)

    assert {:ok, %{record: ^next, replayed: true}} =
             Store.transition(store, :agent, "conversation", r["revision"], cmd)

    reject(store, next, F.worker(next, "outcome", p))

    changed =
      put_in(cmd, ["payload", "response"], Message.to_json([%{response | usage: priced(99)}]))

    reject(store, next, changed)
  end

  test "contributed child usage cannot be injected into wrapper history or settlement command", %{
    store: store
  } do
    {r, attach} = F.attached(store, F.started(store))
    r = F.op(store, r, "node_attach", attach)
    r = F.model(store, r, "D", "D1", [%Part.Text{content: "X"}], true, priced(2))
    r = F.op(store, r, "node_complete", %{"node_id" => "D"})
    target = F.target("B", "request-B", "delegate")
    r = F.op(store, r, "call_wrap", target)

    result =
      Outcome.encode(%Part.ToolReturn{
        tool_name: "delegate",
        tool_call_id: "delegate",
        content: "Y",
        status: :succeeded
      })

    p = Map.merge(target, %{"result" => result, "control" => %{"retry" => false, "error" => nil}})
    reject(store, r, F.worker(r, "call_settle", Map.put(p, "usage", Usage.to_map(priced(2)))))
    [json] = Jason.decode!(result)
    [part] = json["parts"]

    bytes =
      Jason.encode!([%{json | "parts" => [Map.put(part, "usage", Usage.to_map(priced(2)))]}])

    reject(store, r, F.worker(r, "call_settle", Map.put(p, "result", bytes)))
    before = scope(r)
    r = F.op(store, r, "call_settle", p)
    assert scope(r) === before
  end
end
