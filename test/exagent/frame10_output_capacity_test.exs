defmodule ExAgent.Frame10OutputCapacityTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Store, Message}
  alias ExAgent.Continuation.Record
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Frame10OutputCapacityFixture, as: C

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    :ok
  end

  defp store(id), do: Store.scoped({Store.ETS, __MODULE__}, "capacity-" <> id)

  defp prepare(s, limit) do
    s |> C.attached(limit) |> then(&C.response(s, &1))
  end

  defp reject(s, r, c) do
    assert {:error, :record_limit} = Store.transition(s, :agent, "conversation", r["revision"], c)
    assert {:ok, ^r} = Store.load_record(s, :agent, "conversation")
  end

  for decision <- ["retry", "succeeded"], escaped <- [false, true] do
    test "#{decision} reserves mandatory copies at the actual JSON boundary ±1 (escaped=#{escaped})" do
      decision = unquote(decision)

      padding =
        if unquote(escaped),
          do: String.duplicate("\"\\\n\u0001", 2_000),
          else: String.duplicate("x", 60_000)

      s = store("measure")
      before = prepare(s, Record.max_bytes())
      admitted = C.commit(s, before, C.resolution(before, decision, padding))
      boundary = C.cost(admitted)
      # All namespaces and checkpoint numbers have equal encoded widths; all
      # receipt IDs have fixed widths. Derive the limit from the actual reserve.
      for {suffix, delta} <- [{"minus01", -1}, {"exact00", 0}, {"plus001", 1}] do
        other = store(suffix)
        r = prepare(other, boundary + delta)
        c = C.resolution(r, decision, padding)

        if delta == -1 do
          reject(other, r, c)
        else
          ack = C.commit(other, r, c)
          assert C.cost(ack) == boundary
          reserve = Record.cleanup_reserve_bytes(ack)

          assert {:ok, %{record: ^ack, replayed: true}} =
                   Store.transition(other, :agent, "conversation", r["revision"], c)

          assert Record.cleanup_reserve_bytes(ack) == reserve
          # Spend the worst-case escaped receipt IDs, not incidental fixture slack.
          consume =
            if decision == "retry",
              do: F.worker(ack, "output_consume", F.target("D", "typed")),
              else: F.worker(ack, "node_complete", %{"node_id" => "D"})

          consume =
            Map.merge(consume, %{
              "operation_id" => String.duplicate(<<1>>, 512),
              "actor_id" => String.duplicate(<<2>>, 512)
            })

          next = F.commit(other, ack, consume)
          assert C.cost(next) <= C.cost(ack)
          assert F.root(next)["scope"] === F.root(ack)["scope"]
          assert Record.cleanup_reserve_bytes(next) < reserve

          if decision == "succeeded" do
            wrapped = C.wrap(other, next)
            assert F.root(wrapped)["scope"] === F.root(ack)["scope"]
          else
            assert F.root(next)["children"]["D"]["frame"]["output_retries_used"] == 1
          end
        end
      end
    end
  end

  test "the original fixed limits reject precisely attestation with unchanged baseline" do
    for {decision, limit, suffix} <- [
          {"retry", 1_788_510, "retry"},
          {"succeeded", 1_788_564, "typed"}
        ] do
      s = store(suffix)
      r = prepare(s, limit)
      reject(s, r, C.resolution(r, decision, String.duplicate("x", 60_000)))
      positive = store(suffix <> "-positive")
      r = prepare(positive, Record.max_bytes())
      r = C.commit(positive, r, C.resolution(r, decision, String.duplicate("x", 60_000)))
      next = C.consume(positive, r, decision)
      assert F.root(next)["scope"] === F.root(r)["scope"]
    end
  end

  test "escaped JSON and historical retries release credit instead of charging every attestation again" do
    s = store("escaped")
    r = prepare(s, Record.max_bytes())
    padding = String.duplicate("\"\\\n\u0001", 2_000)

    for {decision, index} <- [{"retry", 1}, {"retry", 2}, {"succeeded", 3}], reduce: r do
      r ->
        r =
          if F.root(r)["children"]["D"]["frame"]["cursor"] == "request",
            do: C.response(s, r, "D", "again-#{index}"),
            else: r

        c = C.resolution(r, decision, padding)
        entry = c["payload"]["resolution"]
        assert byte_size(entry["parts"]) < 65_536
        assert byte_size(Jason.encode!(entry["result"])) < 65_536
        ack = C.commit(s, r, c)
        next = C.consume(s, ack, decision)
        assert C.cost(next) <= C.cost(ack)
        assert F.root(next)["scope"] === F.root(ack)["scope"]

        if decision == "retry",
          do: assert(Record.cleanup_reserve_bytes(next) == Record.cleanup_reserve_bytes(r))

        {:ok, messages} =
          Message.from_json(F.root(next)["children"]["D"]["snapshot"]["message_history"])

        assert length(messages) == 1 + 2 * index
        assert map_size(F.root(next)["output_resolutions"]) == index

        next
    end
  end

  test "simultaneous sibling attestations have disjoint credits and close with unchanged accounting" do
    s = store("siblings")
    r = C.attached(s, Record.max_bytes(), ["D", "E"])
    r = C.response(s, r, "D", "typed-D")
    r = C.response(s, r, "E", "typed-E")
    d = C.resolution(r, "succeeded", String.duplicate("x", 60_000))
    r = C.commit(s, r, d)
    e = C.resolution(r, "retry", String.duplicate("\n", 20_000), "E")
    ack = C.commit(s, r, e)
    scope = F.root(ack)["scope"]
    e_before = F.root(ack)["children"]["E"]
    next = C.consume(s, ack, "succeeded")
    assert F.root(next)["children"]["E"] === e_before
    assert C.cost(next) <= C.cost(ack)
    consumed = C.consume(s, next, "retry", "E")
    assert C.cost(consumed) <= C.cost(next)
    wrapped = C.wrap(s, consumed)
    assert F.root(wrapped)["scope"] === scope
    assert F.root(wrapped)["output_resolutions"] === F.root(ack)["output_resolutions"]
  end
end
