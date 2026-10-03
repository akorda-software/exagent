defmodule ExAgent.Frame10OutputResolutionTest do
  use ExUnit.Case, async: true
  alias ExAgent.Continuation.{Frame, OutputResolution, ToolEvidence}
  alias ExAgent.Frame10JournalFixture, as: F
  alias ExAgent.Message

  defp evidence(record) do
    child = F.root(record)["children"]["A"]
    {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])
    OutputResolution.evidence?(record, child, messages, [record["execution"]["effects"]["model"]])
  end

  test "synthetic suspended response and consumed retry retain real request and cursor" do
    for consumed <- [false, true] do
      record = F.output(consumed)
      assert :ok = Frame.validate(F.root(record))
      assert evidence(record)
      refute ToolEvidence.evidence?(record)
      assert F.root(record)["children"]["A"]["frame"]["model_request_id"] == "request"
    end
  end

  test "running response attestation remains valid before and after retry consumption" do
    for consumed <- [false, true] do
      record =
        F.output(consumed)
        |> put_in(F.root_path() ++ ~w(children A status), "running")

      assert evidence(record)
    end
  end

  for {path, value} <- [
        {~w(children A frame output_retries_used), 0},
        {~w(children A frame output_retries_used), 2},
        {~w(children A frame limits output_retries), 0},
        {~w(children A frame cursor), "response"},
        {~w(children A frame run_step), 2},
        {~w(children A frame model_request_id), "fictitious-successor"},
        {~w(output_resolutions request parts_hash), String.duplicate("a", 64)}
      ] do
    test "consumed retry corruption #{inspect(path)} = #{inspect(value)}" do
      record = put_in(F.output(true), F.root_path() ++ unquote(path), unquote(value))
      refute evidence(record)
    end
  end

  test "caller cannot provide alternate child, messages or journal models" do
    record = F.output()
    child = F.root(record)["children"]["A"]
    {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])
    models = [record["execution"]["effects"]["model"]]

    refute OutputResolution.evidence?(
             record,
             Map.put(child, "status", "running"),
             messages,
             models
           )

    refute OutputResolution.evidence?(record, child, tl(messages), models)
    refute OutputResolution.evidence?(record, child, messages, [])

    bad =
      put_in(
        record,
        ~w(execution effects model outcome data response_hash),
        String.duplicate("b", 64)
      )

    refute evidence(bad)
  end

  test "orphan entries and duplicate host requests cannot hide behind local projection" do
    record = F.output()
    entry = F.root(record)["output_resolutions"]["request"]
    refute evidence(put_in(record, F.root_path() ++ ~w(output_resolutions orphan), entry))

    refute evidence(
             put_in(
               record,
               ~w(execution effects duplicate),
               record["execution"]["effects"]["model"]
             )
           )
  end

  test "failed generic error is not accepted as output exhaustion evidence" do
    error = ToolEvidence.error(:failure)

    record =
      F.output(true)
      |> put_in(F.root_path() ++ ~w(children A status), "failed")
      |> put_in(F.root_path() ++ ~w(children A error), error)
      |> put_in(F.root_path() ++ ["frontier"], %{
        "epoch" => 1,
        "state" => "quiescent",
        "reason" => "fatal",
        "fatal" => %{"kind" => "node", "run_id" => "A", "error" => error}
      })
      |> put_in(F.root_path() ++ ["cursor"], "failed")

    assert :ok = Frame.validate(F.root(record))
    refute evidence(record)
  end
end
