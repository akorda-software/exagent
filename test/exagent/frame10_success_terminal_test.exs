defmodule ExAgent.Frame10SuccessTerminalTest do
  use ExUnit.Case, async: true
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Frame10SuccessFixture, as: S
  alias ExAgent.Frame10OutputCapacityFixture, as: C
  alias ExAgent.Frame10OutputCASFixture, as: O
  alias ExAgent.{Message, Store}
  alias ExAgent.Continuation.Record

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "success-terminal10")}
  end

  for typed <- [false, true], escaped <- [false, true], terminal <- [false, true] do
    test "mandatory completion copies fit after ACK at boundary +/-1 typed=#{typed} escaped=#{escaped} terminal=#{terminal}",
         %{store: store} do
      typed = unquote(typed)
      terminal = unquote(terminal)
      padding = String.duplicate(if(unquote(escaped), do: "\"\\\n", else: "x"), 3000)
      store = %{store | namespace: "capacity-reference"}
      {r, command} = S.terminal_admission(store, Record.max_bytes(), typed, padding, terminal)
      r = F.commit(store, r, command)
      cost = C.cost(r)
      boundary = cost - byte_size(to_string(Record.max_bytes())) + byte_size(to_string(cost))

      for {delta, namespace} <- [
            {-1, "capacity-minus-one"},
            {0, "capacity-equal-one"},
            {1, "capacity-plus--one"}
          ] do
        # Keep namespaces equal width: they are persisted bytes too.
        namespace = String.pad_trailing(namespace, 18, "x")
        target = %{store | namespace: namespace}
        {before, cmd} = S.terminal_admission(target, boundary + delta, typed, padding, terminal)

        if delta < 0 do
          assert {:error, :record_limit} =
                   Store.transition(target, :agent, "conversation", before["revision"], cmd)

          assert {:ok, ^before} = Store.load_record(target, :agent, "conversation")
        else
          admitted = F.commit(target, before, cmd)
          assert C.cost(admitted) == boundary

          assert {:ok, %{record: ^admitted, replayed: true}} =
                   Store.transition(target, :agent, "conversation", before["revision"], cmd)

          final = C.op(target, admitted, "step_output", %{"node_id" => "B", "elapsed_ms" => 0})
          assert final["execution"]["state"] == expected_state(terminal)
          expected = expected_result(typed, padding)
          assert F.root(final)["children"]["B"]["result"] === expected
          assert C.cost(final) <= boundary + delta
        end
      end
    end
  end

  defp expected_result(true, padding), do: %{"n" => 42, "padding" => padding}
  defp expected_result(false, padding), do: padding
  defp expected_state(true), do: "completed"
  defp expected_state(false), do: "claimed"

  defp reject(store, r, command) do
    assert {:error, _} = Store.transition(store, :agent, "conversation", r["revision"], command)
    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end

  test "root cannot close over an active child, raw source, wrapping or unconsumed batch", %{
    store: store
  } do
    r = O.attached(store)
    reject(store, r, F.worker(r, "step_output", %{"node_id" => "B", "elapsed_ms" => 0}))
    r = O.model(store, r, "typed")
    r = F.commit(store, r, O.resolution(r, "succeeded"))
    r = F.op(store, r, "node_complete", %{"node_id" => "D"})
    child = F.root(r)["children"]["D"]
    reject(store, r, F.worker(r, "step_output", %{"node_id" => "B", "elapsed_ms" => 0}))
    target = F.target("B", "request-B", "delegate")
    r = F.op(store, r, "call_wrap", target)
    reject(store, r, F.worker(r, "step_output", %{"node_id" => "B", "elapsed_ms" => 0}))

    raw =
      F.root(r)["tool_batches"][ExAgent.Continuation.ToolEvidence.key("B", "request-B")]["calls"][
        "delegate"
      ]["raw"]

    r = F.op(store, r, "call_settle", Map.merge(target, raw))
    r = F.op(store, r, "tool_resolution", F.target("B", "request-B"))
    reject(store, r, F.worker(r, "step_output", %{"node_id" => "B", "elapsed_ms" => 0}))
    assert F.root(r)["children"]["D"] === child
    reject(store, r, F.worker(r, "node_complete", %{"node_id" => "D"}))
  end

  test "host mapping is a persisted trusted input, never recomputed during decode", %{
    store: store
  } do
    step = %{
      agent: ExAgent.new(model: %ExAgent.Models.Test{}),
      definition: F.ref(),
      policy: F.ref(),
      model_ref: F.ref(),
      output_ref: F.ref(),
      model_codec: %{dump: fn _ -> raise "no dump" end, load: fn _, _ -> raise "no load" end}
    }

    a = Map.put(step, :id, "A")

    b =
      Map.merge(step, %{
        id: "B",
        input: fn _, _ -> raise "no mapping on data decode" end,
        input_version: "mapping-1"
      })

    {:ok, definition} =
      ExAgent.Coordination.Composition.new(id: "operations", version: "1", steps: [a, b])

    {:ok, binding} = ExAgent.Coordination.Composition.binding(definition)

    command =
      F.create()
      |> put_in(~w(payload execution progress runtime binding), binding)
      |> put_in(~w(payload snapshot binding), binding)

    r = F.commit(store, nil, command)
    r = F.commit(store, r, F.claim())
    r = S.attach_step(store, r, "A", 0, "root input")
    r = F.model(store, r, "A", "A-final", [%Message.Part.Text{content: "A confirmed"}])
    r = S.complete_step(store, r, "A")
    r = S.attach_step(store, r, "B", 1, "trusted mapped input")
    assert F.root(r)["children"]["B"]["link"]["input"] == "trusted mapped input"
    r = F.model(store, r, "B", "B-final", [%Message.Part.Text{content: "B confirmed"}])
    r = S.complete_step(store, r, "B")

    assert {:ok, %{status: :completed, record: ^r}} =
             ExAgent.Continuation.get(store, "conversation")

    assert ExAgent.Coordination.Composition.validate_binding(definition, F.root(r)["binding"]) ==
             :ok

    # The executable producer-10 now projects terminal data without callbacks.
    reference = %{
      version: 1,
      id: "conversation",
      record_id: r["record_id"],
      revision: r["revision"],
      run_id: "root"
    }

    config = %{
      store: store,
      id: "conversation",
      policy: F.ref(),
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000
    }

    assert {:ok, %{status: :completed, output: "B confirmed"}} =
             ExAgent.Coordination.Composition.resume(definition, reference, continuation: config)

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end

  test "A effect prefix survives nested mixed pause2, typed retry, wrapper, B and C closure", %{
    store: store
  } do
    r = S.draining(store)
    stale = F.worker(r, "step_output", %{"node_id" => "B", "elapsed_ms" => 0})
    reject(store, r, stale)
    prefix = F.root(r)["children"]["A"]
    {r, paused} = S.reclaim(store, r)
    reject(store, r, stale)

    assert {:error, _} =
             Store.transition(
               store,
               :agent,
               "conversation",
               paused["revision"],
               F.worker(paused, "step_output", %{"node_id" => "B", "elapsed_ms" => 0})
             )

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    assert paused["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_987
    assert r["execution"]["progress"]["active_budget"]["reserved_ms"] == 59_987
    r = S.finish_children(store, r)
    scope = F.root(r)["scope"]
    r = S.complete_step(store, r, "B")
    assert F.root(r)["cursor"] == "between_steps"
    assert F.root(r)["scope"] === scope
    r = S.attach_step(store, r, "C", 2, "B output")
    r = F.model(store, r, "C", "C-final", [%Message.Part.Text{content: "portable final"}])
    scope = F.root(r)["scope"]
    r = S.complete_step(store, r, "C", 19)
    assert r["execution"]["state"] == "completed"
    assert F.root(r)["children"]["A"] === prefix
    assert F.root(r)["input"] == "root input"
    assert F.root(r)["scope"] === scope
    assert F.root(r)["children"]["C"]["result"] == "portable final"
    assert r["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_968
    assert F.root(r)["scope"]["nodes"]["root"]["requests"] == 9
    assert F.root(r)["scope"]["nodes"]["B"]["requests"] == 6
    assert F.root(r)["scope"]["nodes"]["D"]["requests"] == 2
    assert F.root(r)["scope"]["nodes"]["root"]["tools"] == 6
    assert F.root(r)["scope"]["nodes"]["B"]["tools"] == 5
    assert F.root(r)["children"]["B"]["snapshot"]["usage"]["input_tokens"] == 3
    assert F.root(r)["children"]["B"]["snapshot"]["usage"]["output_tokens"] == 2

    assert {:ok, %{status: :completed, record: ^r, retryable_effects: []}} =
             ExAgent.Continuation.get(store, "conversation")

    key = {store.namespace, :agent, "conversation"}
    root_path = ~w(execution progress runtime)

    for {path, value} <- [
          {~w(input), "rewritten root"},
          {~w(children A result), "rewritten prefix"},
          {~w(children D status), "cancelled"},
          {~w(children D result), %{"n" => 999}},
          {~w(children C link input), "wrong mapping"},
          {~w(children C snapshot usage), %{}},
          {~w(children C frame model_data), %{"fake" => true}},
          {~w(scope nodes root requests), 10}
        ] do
      assert {:error, _} = Record.encode(put_in(r, root_path ++ path, value), key)
    end
  end

  test "plain last step closes the root atomically, refunds once, and is immutable", %{
    store: store
  } do
    r = F.started(store)
    r = F.model(store, r, "B", "final", [%Message.Part.Text{content: "done"}])
    scope = F.root(r)["scope"]
    budget = r["execution"]["progress"]["active_budget"]
    command = F.worker(r, "step_output", %{"node_id" => "B", "elapsed_ms" => 17})
    r = F.commit(store, r, command)
    assert r["execution"]["state"] == "completed"
    assert F.root(r)["cursor"] == "completed"
    assert F.root(r)["children"]["B"]["result"] == "done"
    assert F.root(r)["scope"] === scope

    assert r["execution"]["progress"]["active_budget"]["remaining_ms"] ==
             budget["reserved_ms"] - 17

    assert is_nil(r["execution"]["progress"]["active_budget"]["reserved_ms"])

    assert {:ok, %{record: ^r, replayed: true}} =
             Store.transition(store, :agent, "conversation", r["revision"] - 1, command)

    assert {:error, _} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               put_in(command, ~w(payload elapsed_ms), 18)
             )

    for op <- ~w(step_output cancel expire recover claim) do
      assert {:error, _} =
               Store.transition(
                 store,
                 :agent,
                 "conversation",
                 r["revision"],
                 F.worker(r, op, %{"node_id" => "B", "elapsed_ms" => 0})
               )

      assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
    end

    corrupted =
      put_in(r, ["execution", "progress", "runtime", "children", "B", "result"], "invented")

    assert {:error, _} = Record.encode(corrupted, {store.namespace, :agent, "conversation"})
  end
end
