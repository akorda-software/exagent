defmodule ExAgent.Frame10JournalTest do
  use ExUnit.Case, async: true
  alias ExAgent.Continuation.{Frame, Outcome, Record, ToolEvidence}
  alias ExAgent.Frame10JournalFixture, as: F
  alias ExAgent.Message

  defp reduce(record, counts \\ %{}) do
    batch = F.batch(record)
    ToolEvidence.reduce_resolution(batch, ToolEvidence.calls(record, batch), record, counts)
  end

  test "synthetic coherent effect journal reads response order, not map order; gates stay closed" do
    record = F.new()
    assert :ok = Frame.validate(F.root(record))

    assert Enum.map(ToolEvidence.calls(record, F.batch(record)), & &1.tool_call_id) == [
             "z-first",
             "a-second"
           ]

    assert {%{}, nil} = reduce(record)
    refute ToolEvidence.evidence?(record)
    refute Record.execution?(record["execution"])
    refute ToolEvidence.transition?(F.root(record), F.root(record), "tool_resolution")
  end

  for {path, value} <- [
        {~w(execution effects model intent call_id), "other"},
        {~w(execution effects model intent payload run_id), "orphan"},
        {~w(execution effects model intent payload history_index), 0},
        {~w(execution effects model intent payload history_index), -1},
        {~w(execution effects model intent payload step), 2},
        {~w(execution effects model state), "intent"},
        {~w(execution effects model outcome data response_hash), String.duplicate("b", 64)}
      ] do
    test "model mutation rejected #{inspect(path)} = #{inspect(value)}" do
      record = put_in(F.new(), unquote(path), unquote(value))
      assert_raise MatchError, fn -> ToolEvidence.calls(record, F.batch(record)) end
    end
  end

  test "global duplicate request and unrelated orphan model cannot hide in a leaf view" do
    record = F.new()
    model = record["execution"]["effects"]["model"]

    for extra <- [model, put_in(model, ~w(intent payload run_id), "orphan")] do
      bad = put_in(record, ~w(execution effects extra), extra)
      assert_raise MatchError, fn -> ToolEvidence.calls(bad, F.batch(bad)) end
    end
  end

  test "supplied batches and call coverage must be exact; original call args are hash-bound" do
    record = F.new()

    assert_raise MatchError, fn ->
      ToolEvidence.calls(record, Map.put(F.batch(record), "request_id", "other"))
    end

    for {suffix, value} <- [
          {["calls", "z-first", "binding", "call_hash"], String.duplicate("b", 64)},
          {["calls", "z-first", "binding", "tool_name"], "other"}
        ] do
      bad = put_in(record, F.batch_path() ++ suffix, value)
      assert_raise MatchError, fn -> ToolEvidence.calls(bad, F.batch(bad)) end
    end

    {_, bad} = pop_in(record, F.batch_path() ++ ["calls", "z-first"])
    assert_raise MatchError, fn -> ToolEvidence.calls(bad, F.batch(bad)) end
  end

  test "ordered retry then success resets counts; caller reordering cannot authorize reduction" do
    record = put_in(F.new(), F.batch_path() ++ ~w(calls z-first control retry), true)
    assert {%{}, nil} = reduce(record)
    batch = F.batch(record)

    assert_raise MatchError, fn ->
      ToolEvidence.reduce_resolution(
        batch,
        Enum.reverse(ToolEvidence.calls(record, batch)),
        record,
        %{}
      )
    end

    bad = put_in(record, F.batch_path() ++ ~w(resolution tool_retries), %{"tool" => 1})
    assert_raise MatchError, fn -> reduce(bad) end
  end

  test "success then retry retains a retry; raw and final controls are not inferred from status" do
    record =
      F.new()
      |> put_in(F.batch_path() ++ ~w(calls a-second control retry), true)
      |> put_in(F.batch_path() ++ ~w(resolution tool_retries), %{"tool" => 1})

    assert {%{"tool" => 1}, nil} = reduce(record)
  end

  test "known fatal is sticky across success; retry exhaustion retains its ordered cause" do
    error = ToolEvidence.error(:known_failure)

    record =
      F.new()
      |> put_in(F.batch_path() ++ ~w(calls z-first control error), error)
      |> put_in(F.batch_path() ++ ~w(resolution error), error)

    assert {%{}, ^error} = reduce(record)

    exhausted =
      record
      |> put_in(F.batch_path() ++ ~w(calls z-first control retry), true)
      |> put_in(F.batch_path() ++ ~w(limits tool max_retries), 0)

    assert {%{}, {:unexpected_model_behavior, {:tool_retries_exhausted, "tool", ^error}}} =
             reduce(exhausted)

    assert_raise MatchError, fn -> reduce(exhausted, %{"tool" => 1}) end
  end

  test "effect raw/final hashes, binding, request and accounting are independent certificates" do
    record = F.new()
    id = ToolEvidence.effect_id("A", "request", "z-first")

    for {path, value} <- [
          {~w(intent payload model_request_id), "other"},
          {~w(intent payload run_id), "other"},
          {~w(intent payload args), %{"changed" => true}},
          {~w(outcome data raw_hash), String.duplicate("b", 64)},
          {~w(outcome data result_hash), String.duplicate("b", 64)},
          {~w(outcome data phase), "raw"},
          {~w(outcome status), "denied"},
          {["state"], "intent"}
        ] do
      bad = put_in(record, ["execution", "effects", id] ++ path, value)
      assert_raise MatchError, fn -> reduce(bad) end
    end

    {_, bad} = pop_in(record, F.batch_path() ++ ["observations", id])
    assert_raise MatchError, fn -> reduce(bad) end
  end

  test "consumption records exact adjacent returns, hash and original order" do
    record = F.new()

    parts =
      for call <- ToolEvidence.calls(record, F.batch(record)) do
        {:ok, [%Message.Request{parts: [part]}]} =
          Message.from_json(F.batch(record)["calls"][call.tool_call_id]["result"])

        part
      end

    request = %Message.Request{parts: parts}
    {:ok, hash} = Outcome.hash(Message.to_json([request]))
    path = F.root_path() ++ ~w(children A snapshot message_history)
    {:ok, messages} = Message.from_json(get_in(record, path))

    consumed =
      record
      |> put_in(path, Message.to_json(messages ++ [request]))
      |> put_in(F.root_path() ++ ~w(children A frame cursor), "request")
      |> put_in(F.root_path() ++ ~w(children A frame outcomes), %{})
      |> put_in(F.batch_path() ++ ["consumption"], %{"history_index" => 2, "returns_hash" => hash})

    assert {%{}, nil} = reduce(consumed)

    for {suffix, value} <- [
          {["consumption"], nil},
          {~w(consumption history_index), 1},
          {~w(consumption returns_hash), String.duplicate("b", 64)}
        ] do
      assert_raise MatchError, fn -> reduce(put_in(consumed, F.batch_path() ++ suffix, value)) end
    end

    bad =
      put_in(
        consumed,
        path,
        Message.to_json(messages ++ [%{request | parts: Enum.reverse(parts)}])
      )

    assert_raise MatchError, fn -> reduce(bad) end

    assert_raise MatchError, fn ->
      reduce(put_in(consumed, path, Message.to_json(messages ++ [request, request])))
    end
  end

  test "contributed accounting requires the exact ancestral operation; none cannot hide it" do
    record = F.new()
    root = F.root(record)
    model_op = hd(root["scope"]["operations"])
    op = %{model_op | "id" => ["tool", "request", "z-first"]}

    observation = %{
      "origin" => "tool_return",
      "presence" => "usage",
      "usage" => op["usage"],
      "application" => %{
        "status" => "contributed",
        "complete" => true,
        "ancestors" => op["ancestors"]
      }
    }

    scope = Map.update!(root["scope"], "operations", &(&1 ++ [op]))
    {:ok, own} = ExAgent.Continuation.ScopeLedger.node_data(scope, "A")
    id = ToolEvidence.effect_id("A", "request", "z-first")

    record =
      record
      |> put_in(F.root_path() ++ ["scope"], scope)
      |> put_in(F.root_path() ++ ~w(children A frame scope), own)
      |> put_in(F.batch_path() ++ ["observations", id], observation)

    assert :ok = Frame.validate(F.root(record))
    assert {%{}, nil} = reduce(record)

    for obs <- [
          elem(ToolEvidence.observe(nil), 0),
          put_in(observation, ~w(application complete), false),
          put_in(observation, ~w(application ancestors), %{})
        ] do
      assert_raise MatchError, fn ->
        reduce(put_in(record, F.batch_path() ++ ["observations", id], obs))
      end
    end

    missing =
      record
      |> put_in(F.root_path() ++ ~w(scope operations), [model_op])
      |> put_in(
        F.root_path() ++ ~w(children A frame scope),
        F.root(F.new())["children"]["A"]["frame"]["scope"]
      )

    assert :ok = Frame.validate(F.root(missing))
    assert_raise MatchError, fn -> reduce(missing) end
  end

  test "rejected accounting retains its confirmed source and exact fatal cause without contribution" do
    record = F.new()
    {obs, nil, :invalid_tool_accounting} = ToolEvidence.observe(:invalid)
    id = ToolEvidence.effect_id("A", "request", "z-first")

    record =
      record
      |> put_in(F.batch_path() ++ ["observations", id], obs)
      |> put_in(F.batch_path() ++ ~w(calls z-first control error), obs["application"]["error"])
      |> put_in(F.batch_path() ++ ~w(resolution error), obs["application"]["error"])

    assert :ok = Frame.validate(F.root(record))
    error = obs["application"]["error"]
    assert {%{}, ^error} = reduce(record)

    # It cannot become a successful resolution or hide an unrelated observation.
    for {suffix, value} <- [
          {~w(calls z-first control error), nil},
          {~w(resolution error), nil},
          {["observations", id, "origin"], "model_response"},
          {["observations", id, "application", "status"], "none"}
        ] do
      assert_raise MatchError, fn -> reduce(put_in(record, F.batch_path() ++ suffix, value)) end
    end
  end

  test "pending reduction never resets accumulated retry counts" do
    record = put_in(F.new(), F.batch_path() ++ ["resolution"], nil)
    assert {%{}, nil} = reduce(record)
    assert_raise MatchError, fn -> reduce(record, %{"tool" => 1}) end
  end

  for {state, raw?} <- [
        {"queued", false},
        {"preparing", false},
        {"prepared", false},
        {"approval", false},
        {"dispatching", false},
        {"dispatching", true},
        {"wrapping", true},
        {"blocked", false},
        {"blocked", true}
      ] do
    test "partial phase #{state} raw=#{raw?} retains exact effect/observation/outcome partition" do
      record = F.phase(F.new(), "z-first", unquote(state), unquote(raw?))
      assert :ok = Frame.validate(F.root(record))
      assert {%{}, nil} = reduce(record)
      refute ToolEvidence.evidence?(record)

      extra = F.new()["execution"]["effects"][ToolEvidence.effect_id("A", "request", "z-first")]
      bad = put_in(record, ~w(execution effects orphan), extra)
      assert_raise MatchError, fn -> reduce(bad) end

      bad =
        put_in(
          record,
          F.root_path() ++ ~w(children A frame outcomes ghost),
          F.batch(F.new())["calls"]["z-first"]["result"]
        )

      assert_raise MatchError, fn -> reduce(bad) end
    end
  end

  test "raw evidence cannot be omitted, advanced to final, rebound or detached" do
    record = F.phase(F.new(), "z-first", "wrapping", true)
    id = ToolEvidence.effect_id("A", "request", "z-first")

    for {path, value} <- [
          {["execution", "effects", id, "state"], "intent"},
          {["execution", "effects", id, "outcome", "data", "phase"], "final"},
          {["execution", "effects", id, "outcome", "data", "raw_hash"],
           String.duplicate("b", 64)},
          {["execution", "effects", id, "intent", "payload", "args"], %{"changed" => true}},
          {F.batch_path() ++ ["observations", id], nil},
          {F.root_path() ++ ~w(children A frame outcomes), %{}}
        ] do
      assert_raise MatchError, fn -> reduce(put_in(record, path, value)) end
    end
  end

  test "global accounting rejects orphan operations even outside the selected batch" do
    record = F.new()
    scope = F.root(record)["scope"]
    op = %{hd(scope["operations"]) | "id" => ["tool", "not-a-request", "not-a-call"]}
    scope = Map.update!(scope, "operations", &(&1 ++ [op]))
    {:ok, own} = ExAgent.Continuation.ScopeLedger.node_data(scope, "A")

    bad =
      record
      |> put_in(F.root_path() ++ ["scope"], scope)
      |> put_in(F.root_path() ++ ~w(children A frame scope), own)

    assert :ok = Frame.validate(F.root(bad))
    assert_raise MatchError, fn -> reduce(bad) end
  end

  test "historical retry counts and exact consumption are replayed across batches" do
    record =
      F.new()
      |> put_in(F.batch_path() ++ ~w(calls a-second control retry), true)
      |> put_in(F.batch_path() ++ ~w(resolution tool_retries), %{"tool" => 1})
      |> F.next_batch()

    current_path = F.root_path() ++ ["tool_batches", ToolEvidence.key("A", "request-2")]
    current = get_in(record, current_path)
    ordered = ToolEvidence.calls(record, current)
    assert {%{}, nil} = ToolEvidence.reduce_resolution(current, ordered, record, %{"tool" => 1})

    assert_raise MatchError, fn ->
      ToolEvidence.reduce_resolution(current, ordered, record, %{})
    end

    for {suffix, value} <- [
          {["consumption"], nil},
          {~w(consumption history_index), 4},
          {~w(consumption returns_hash), String.duplicate("b", 64)},
          {~w(resolution tool_retries), %{}},
          {~w(resolution error), ToolEvidence.error(:failure)}
        ] do
      bad = put_in(record, F.batch_path() ++ suffix, value)

      assert_raise MatchError, fn ->
        ToolEvidence.reduce_resolution(current, ordered, bad, %{"tool" => 1})
      end
    end

    pending = put_in(record, current_path ++ ["resolution"], nil)
    current = get_in(pending, current_path)

    assert {%{"tool" => 1}, nil} =
             ToolEvidence.reduce_resolution(current, ordered, pending, %{"tool" => 1})
  end

  test "historical function batches cannot disappear with their effects and admission entry" do
    record = F.new() |> F.next_batch()
    scope = F.root(record)["scope"]

    scope =
      scope
      |> Map.update!("batches", &Enum.reject(&1, fn b -> b["id"] == "request" end))
      |> Map.update!("nodes", fn nodes ->
        Map.new(nodes, fn {id, n} -> {id, %{n | "tools" => 2}} end)
      end)

    {:ok, own} = ExAgent.Continuation.ScopeLedger.node_data(scope, "A")

    record =
      record
      |> update_in(
        F.root_path() ++ ["tool_batches"],
        &Map.delete(&1, ToolEvidence.key("A", "request"))
      )
      |> put_in(F.root_path() ++ ["scope"], scope)
      |> put_in(F.root_path() ++ ~w(children A frame scope), own)
      |> update_in(["execution", "effects"], fn effects ->
        Map.reject(effects, fn {_, e} ->
          e["intent"]["kind"] == "tool" and
            e["intent"]["payload"]["model_request_id"] == "request"
        end)
      end)

    assert :ok = Frame.validate(F.root(record))
    current = F.root(record)["tool_batches"][ToolEvidence.key("A", "request-2")]
    assert_raise MatchError, fn -> ToolEvidence.calls(record, current) end
  end

  test "uncertain external intent has no fabricated raw observation or leaf return" do
    record = F.phase(F.new(), "z-first", "dispatching")
    id = ToolEvidence.effect_id("A", "request", "z-first")
    assert {%{}, nil} = reduce(record)
    assert Record.unresolved?(record["execution"])

    for state <- ["intent", "uncertain", "confirmed"] do
      bad = put_in(record, ["execution", "effects", id, "state"], state)
      assert_raise MatchError, fn -> reduce(bad) end
    end

    bad =
      put_in(record, F.batch_path() ++ ["observations", id], elem(ToolEvidence.observe(nil), 0))

    assert_raise MatchError, fn -> reduce(bad) end
  end
end
