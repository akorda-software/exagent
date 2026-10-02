defmodule ExAgent.Frame10SourceFixture do
  @moduledoc false
  alias ExAgent.Continuation.{ScopeLedger, ToolEvidence}
  alias ExAgent.Frame10JournalFixture, as: F
  alias ExAgent.Message

  # Coherent synthetic source journal, not a producer, VM or atomicity proof.
  def child(status \\ "completed") do
    record = F.new()
    c = F.batch(record)["calls"]["z-first"]
    root = F.root(record)

    scope =
      put_in(root["scope"], ["nodes", "D"], %{
        "parent_run_id" => "A",
        "requests" => 0,
        "tools" => 0
      })

    {:ok, own} = ScopeLedger.node_data(scope, "D")

    frame =
      Map.merge(root["children"]["A"]["frame"], %{
        "run_id" => "D",
        "scope" => own,
        "cursor" => if(status == "completed", do: "finish", else: "request"),
        "run_step" => 0,
        "model_request_id" => nil,
        "outcomes" => %{}
      })

    child =
      Map.merge(root["children"]["A"], %{
        "parent_run_id" => "A",
        "output_ref" => nil,
        "frame" => frame,
        "snapshot" => %{"message_history" => Message.to_json([])},
        "link" =>
          Map.merge(c["binding"], %{
            "kind" => "delegate",
            "parent_request_id" => "request",
            "call_id" => "z-first"
          }),
        "status" => status,
        "result" => if(status == "completed", do: %{"exact" => [nil, 3, "value"]}),
        "result_omitted" => nil,
        "error" => if(status != "completed", do: ToolEvidence.error(:failure))
      })

    call = %Message.Part.ToolCall{tool_name: "tool", tool_call_id: "z-first"}

    raw =
      case ToolEvidence.child_raw10(child, call) do
        {:ok, raw} -> raw
        {:error, :child_cancelled} -> nil
      end

    c = %{
      c
      | "source" => %{"kind" => "child", "id" => "D"},
        "raw" => raw,
        "state" => if(raw, do: "wrapping", else: "blocked"),
        "result" => nil,
        "control" => nil,
        "blocked_by" => if(raw, do: nil, else: "fatal")
    }

    record =
      record
      |> put_in(F.root_path() ++ ["scope"], scope)
      |> put_in(F.root_path() ++ ["children", "D"], child)
      |> put_in(F.root_path() ++ ["authority", "D"], root["authority"]["A"])
      |> put_in(F.batch_path() ++ ["calls", "z-first"], c)
      |> put_in(F.batch_path() ++ ["resolution"], nil)
      |> update_in(
        ["execution", "effects"],
        &Map.delete(&1, ToolEvidence.effect_id("A", "request", "z-first"))
      )

    record =
      if status == "failed" do
        put_in(record, F.root_path() ++ ["frontier"], %{
          "epoch" => 1,
          "state" => "draining",
          "reason" => "fatal",
          "fatal" => %{"kind" => "node", "run_id" => "D", "error" => child["error"]}
        })
      else
        record
      end

    if raw do
      put_in(record, F.root_path() ++ ~w(children A frame outcomes z-first), raw["result"])
    else
      record
      |> update_in(
        F.batch_path() ++ ["observations"],
        &Map.delete(&1, ToolEvidence.effect_id("A", "request", "z-first"))
      )
      |> update_in(F.root_path() ++ ~w(children A frame outcomes), &Map.delete(&1, "z-first"))
      |> put_in(F.root_path() ++ ["frontier"], %{
        "epoch" => 1,
        "state" => "draining",
        "reason" => "fatal",
        "fatal" => %{"kind" => "root", "error" => child["error"]}
      })
    end
  end

  def host do
    record = F.new()

    bytes =
      ExAgent.Continuation.Outcome.encode(%Message.Part.ToolReturn{
        tool_name: "tool",
        tool_call_id: "z-first",
        status: :denied,
        content: "Tool \"tool\" is not permitted."
      })

    control = %{"retry" => false, "error" => nil}
    id = ToolEvidence.effect_id("A", "request", "z-first")

    record
    |> put_in(F.batch_path() ++ ~w(calls z-first source), %{
      "kind" => "host",
      "reason" => "permission_denied"
    })
    |> put_in(F.batch_path() ++ ~w(calls z-first raw), %{"result" => bytes, "control" => control})
    |> put_in(F.batch_path() ++ ~w(calls z-first result), bytes)
    |> put_in(F.batch_path() ++ ~w(calls z-first control), control)
    |> put_in(F.batch_path() ++ ["observations", id], ToolEvidence.pre_dispatch())
    |> put_in(F.root_path() ++ ~w(children A frame outcomes z-first), bytes)
    |> update_in(["execution", "effects"], &Map.delete(&1, id))
  end
end
