defmodule ExAgent.Frame10SourceTest do
  use ExUnit.Case, async: true
  alias ExAgent.Continuation.{Frame, Outcome, Record, ToolEvidence}
  alias ExAgent.Frame10JournalFixture, as: F
  alias ExAgent.Frame10SourceFixture, as: S
  alias ExAgent.Message

  defp certify(r), do: ToolEvidence.child_source10?(r, F.batch(r), "z-first")
  defp child(r), do: F.root(r)["children"]["D"]
  defp call, do: %Message.Part.ToolCall{tool_name: "tool", tool_call_id: "z-first"}

  for status <- ~w(completed failed cancelled) do
    test "synthetic #{status} source is coherent; global gates closed" do
      r = S.child(unquote(status))
      assert :ok = Frame.validate(F.root(r))
      assert certify(r)
      assert length(ToolEvidence.calls(r, F.batch(r))) == 2
      refute ToolEvidence.evidence?(r)
      refute Record.execution?(r["execution"])
      refute ToolEvidence.transition?(F.root(r), F.root(r), "tool_resolution")
    end
  end

  test "success is exact raw output, not the parent's eventual wrapper output" do
    r = S.child()
    assert {:ok, raw} = ToolEvidence.child_raw10(child(r), call())
    assert {:ok, [%Message.Request{parts: [part]}]} = Message.from_json(raw["result"])
    assert part.content === child(r)["result"]
    assert part.status == :succeeded
    assert part.usage == nil
    assert part.payload_omitted == nil
    assert Outcome.encode(part) === raw["result"]
    assert raw["control"] == %{"retry" => false, "error" => nil}

    transformed = Outcome.encode(%{part | content: "wrapper transformed"})

    r =
      r
      |> put_in(F.batch_path() ++ ~w(calls z-first state), "settled")
      |> put_in(F.batch_path() ++ ~w(calls z-first result), transformed)
      |> put_in(F.batch_path() ++ ~w(calls z-first control), raw["control"])

    assert certify(r)
    # This source certificate deliberately makes no final-wrapper claim.
    refute ToolEvidence.evidence?(r)
  end

  test "failed portable projection is explicitly lossy and preserves complete control" do
    a = ToolEvidence.error("first private reason")
    b = ToolEvidence.error("second private reason")
    assert a === b
    node = child(S.child("failed"))

    assert ToolEvidence.child_raw10(%{node | "error" => a}, call()) ===
             ToolEvidence.child_raw10(%{node | "error" => b}, call())

    error = %{
      a
      | "details" => %{"detail" => 7},
        "omitted" => ExAgent.Retention.marker(:usage, 9, 8)
    }

    assert {:ok, raw} = ToolEvidence.child_raw10(%{node | "error" => error}, call())
    assert raw["control"] === %{"retry" => false, "error" => error}
    assert {:ok, [%Message.Request{parts: [part]}]} = Message.from_json(raw["result"])
    assert part.content === error["message"]

    assert {part.tool_name, part.tool_call_id, part.status, part.usage, part.payload_omitted} ==
             {"tool", "z-first", :failed, nil, nil}
  end

  test "omitted success and cancelled children never fabricate a return" do
    node =
      child(S.child())
      |> Map.put("result", nil)
      |> Map.put("result_omitted", ExAgent.Retention.marker(:output, 9, 8))

    assert {:error, :child_result_omitted} = ToolEvidence.child_raw10(node, call())

    assert {:error, :child_cancelled} =
             ToolEvidence.child_raw10(child(S.child("cancelled")), call())
  end

  for {path, value} <- [
        {~w(parent_run_id), "wrong"},
        {~w(link parent_request_id), "wrong"},
        {~w(link call_id), "wrong"},
        {~w(link args), %{"altered" => true}},
        {~w(frame run_id), "wrong"},
        {~w(status), "failed"},
        {~w(result), "wrong raw output"},
        {~w(error), %{}}
      ] do
    test "child link/terminal mutation #{inspect(path)} rejects" do
      r =
        put_in(
          S.child(),
          F.root_path() ++ ["children", "D"] ++ unquote(path),
          unquote(Macro.escape(value))
        )

      refute certify(r)
    end
  end

  test "raw/control bytes, duplicate source, fake effect and accounting reject" do
    r = S.child()

    for {path, value} <- [
          {F.batch_path() ++ ~w(calls z-first raw control retry), true},
          {F.batch_path() ++ ~w(calls z-first raw result), "[]"},
          {F.batch_path() ++ ~w(calls a-second source), %{"kind" => "child", "id" => "D"}},
          {["execution", "effects", ToolEvidence.effect_id("A", "request", "z-first")], %{}},
          {F.batch_path() ++ ["observations", ToolEvidence.effect_id("A", "request", "z-first")],
           ToolEvidence.pre_dispatch()}
        ] do
      refute certify(put_in(r, path, value))
    end
  end

  test "failed child requires nonnil valid error and coherent terminal fields" do
    node = child(S.child("failed"))

    for bad <- [
          %{node | "error" => nil},
          %{node | "error" => %{}},
          %{node | "result" => "invented"},
          put_in(node, ~w(frame cursor), "finish")
        ] do
      assert {:error, :invalid_child_terminal} = ToolEvidence.child_raw10(bad, call())
    end
  end

  test "host denied is exact observed predispatch failure, not an external effect" do
    r = S.host()
    assert :ok = Frame.validate(F.root(r))
    assert ToolEvidence.host_source10?(r, F.batch(r), "z-first")
    ordered = ToolEvidence.calls(r, F.batch(r))
    assert {%{}, nil} = ToolEvidence.reduce_resolution(F.batch(r), ordered, r, %{})
    refute ToolEvidence.evidence?(r)
    refute Record.execution?(r["execution"])
    refute ToolEvidence.transition?(F.root(r), F.root(r), "tool_resolution")
  end

  test "host enum, retry, error, bytes and observation cannot be guessed" do
    r = S.host()

    for {path, value} <- [
          {~w(source reason), "success"},
          {~w(raw control retry), true},
          {~w(raw control error), ToolEvidence.error(:failure)},
          {~w(raw result), "[]"},
          {~w(state), "wrapping"}
        ] do
      bad = put_in(r, F.batch_path() ++ ~w(calls z-first) ++ path, value)
      refute ToolEvidence.host_source10?(bad, F.batch(bad), "z-first")
    end

    id = ToolEvidence.effect_id("A", "request", "z-first")
    bad = put_in(r, ["execution", "effects", id], %{})
    refute ToolEvidence.host_source10?(bad, F.batch(bad), "z-first")
  end

  test "effective host args are distinct from original response identity; no authority claim" do
    r = put_in(S.host(), F.batch_path() ++ ~w(calls z-first binding args), %{"effective" => true})
    assert ToolEvidence.host_source10?(r, F.batch(r), "z-first")
    assert length(ToolEvidence.calls(r, F.batch(r))) == 2

    bad =
      put_in(r, F.batch_path() ++ ~w(calls z-first binding call_hash), String.duplicate("b", 64))

    assert_raise MatchError, fn -> ToolEvidence.calls(bad, F.batch(bad)) end
    refute ToolEvidence.evidence?(r)
  end

  test "cancelled does not acquire a fabricated failed raw return" do
    r = S.child("cancelled")
    raw = F.batch(S.child("failed"))["calls"]["z-first"]["raw"]
    refute certify(put_in(r, F.batch_path() ++ ~w(calls z-first raw), raw))
    bad = put_in(r, F.batch_path() ++ ~w(calls z-first control), raw["control"])
    refute certify(bad)
  end
end
