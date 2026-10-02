defmodule ExAgent.Frame10GrammarTest do
  use ExUnit.Case, async: true

  alias ExAgent.Continuation.{Authority, Frame, Outcome, Record, ToolEvidence}
  alias ExAgent.Coordination.Composition
  alias ExAgent.Message.Part.ToolReturn

  # Synthetic grammar fixtures, deliberately NOT journals or recoverable runs.
  # No effects/response evidence, callback execution, producer10 or VM delegation
  # is claimed. Historical fixtures are never relabeled to manufacture positives.
  defp fixture do
    ref = %{id: "fixture", version: "1"}

    step = %{
      id: "A",
      agent: ExAgent.new(model: %ExAgent.Models.Test{script: []}),
      definition: ref,
      policy: ref,
      model_ref: ref,
      output_ref: ref,
      model_codec: %{
        dump: fn _ -> flunk("codec called") end,
        load: fn _, _ -> flunk("codec called") end
      }
    }

    {:ok, definition} =
      Composition.new(id: "typed", version: "1", steps: [step, %{step | id: "B"}])

    {:ok, binding} = Composition.binding(definition)

    authority = %{
      "policies" => [%{"default" => "allow", "rules" => []}],
      "deadline_at" => nil,
      "max_concurrent_requests" => nil
    }

    usage = Authority.usage(%ExAgent.UsageLimits{})

    root = %{
      "frame_version" => 10,
      "kind" => "sequence",
      "cursor" => "empty",
      "run_id" => "root",
      "binding" => binding,
      "input" => "initial",
      "children" => %{},
      "tool_batches" => %{},
      "output_resolutions" => %{},
      "scope" => %{
        "scope_version" => 2,
        "root_run_id" => "root",
        "nodes" => %{"root" => ledger_node(nil)},
        "operations" => [],
        "batches" => [],
        "retry_batches" => []
      },
      "authority" => %{
        "root" =>
          Map.merge(authority, %{"usage" => usage, "checkpoint_limit" => Record.max_bytes()})
      },
      "frontier" => %{"epoch" => 0, "state" => "open", "reason" => nil, "fatal" => nil}
    }

    add_step(root, "A", 0)
  end

  defp ledger_node(parent), do: %{"parent_run_id" => parent, "requests" => 0, "tools" => 0}

  defp add_node(root, id, parent, link, refs) do
    authority = Map.drop(root["authority"]["root"], ~w(usage checkpoint_limit))

    leaf = %{
      "frame_version" => 3,
      "cursor" => "request",
      "run_id" => id,
      "first_new_message_index" => 0,
      "run_step" => 0,
      "model_request_id" => nil,
      "tool_retries" => %{},
      "output_retries_used" => 0,
      "tool_return_bytes" => 65_536,
      "selected_tools" => %{},
      "model_data" => nil,
      "model_binding" => nil,
      "settings" => %{},
      "limits" => %{"output_retries" => 0, "usage" => root["authority"]["root"]["usage"]},
      "permissions" => %{},
      "scope" => %{
        "scope_version" => 1,
        "run_id" => id,
        "requests" => 0,
        "tools" => 0,
        "operations" => [],
        "batches" => %{}
      },
      "outcomes" => %{},
      "output_fingerprint" => nil
    }

    node =
      Map.merge(refs, %{
        "parent_run_id" => parent,
        "link" => link,
        "frame" => leaf,
        "snapshot" => nil,
        "status" => "running",
        "result" => nil,
        "result_omitted" => nil,
        "error" => nil
      })

    root
    |> put_in(["children", id], node)
    |> put_in(["authority", id], authority)
    |> put_in(["scope", "nodes", id], ledger_node(parent))
    |> Map.put("cursor", "running")
  end

  defp add_step(root, id, index) do
    step = Enum.at(root["binding"]["steps"], index)
    input = if index == 0, do: root["input"], else: root["children"]["A"]["result"]

    add_node(
      root,
      id,
      "root",
      %{"kind" => "step", "step_id" => step["id"], "index" => index, "input" => input},
      Map.take(step, ~w(definition policy model_ref output_ref))
    )
  end

  defp call(state \\ "queued") do
    %{
      "state" => state,
      "binding" => nil,
      "source" => nil,
      "raw" => nil,
      "result" => nil,
      "control" => nil,
      "blocked_by" => nil
    }
  end

  defp call_binding do
    %{
      "tool_name" => "tool",
      "args" => %{"prompt" => "delegate input"},
      "schema_hash" => String.duplicate("a", 64),
      "call_hash" => String.duplicate("b", 64)
    }
  end

  defp batch(root, run, call_id, data) do
    request = "request-" <> run
    key = ToolEvidence.key(run, request)

    b = %{
      "run_id" => run,
      "request_id" => request,
      "limits" => %{
        "tool" => %{"schema_hash" => call_binding()["schema_hash"], "max_retries" => 2}
      },
      "observations" => %{},
      "calls" => Map.put(get_in(root, ["tool_batches", key, "calls"]) || %{}, call_id, data),
      "resolution" => nil,
      "consumption" => nil
    }

    put_in(root, ["tool_batches", key], b)
  end

  defp call_path(run \\ "A", id \\ "call"),
    do: ["tool_batches", ToolEvidence.key(run, "request-" <> run), "calls", id]

  defp delegate(root, parent \\ "A", id \\ "D", call_id \\ "call") do
    bound = call_binding()
    c = %{call("child") | "binding" => bound, "source" => %{"kind" => "child", "id" => id}}
    root = batch(root, parent, call_id, c)

    refs =
      Map.take(root["children"][parent], ~w(definition policy model_ref))
      |> Map.put("output_ref", nil)

    link =
      Map.merge(bound, %{
        "kind" => "delegate",
        "parent_request_id" => "request-" <> parent,
        "call_id" => call_id
      })

    add_node(root, id, parent, link, refs)
  end

  defp settled(root) do
    result =
      Outcome.encode(%ToolReturn{
        tool_name: "tool",
        tool_call_id: "call",
        content: "done",
        status: :succeeded
      })

    control = %{"retry" => false, "error" => nil}

    c = %{
      call("settled")
      | "binding" => call_binding(),
        "source" => %{
          "kind" => "effect",
          "id" => ToolEvidence.effect_id("A", "request-A", "call")
        },
        "raw" => %{"result" => result, "control" => control},
        "result" => result,
        "control" => control
    }

    batch(root, "A", "call", c)
  end

  test "typed tree roundtrip and no runtime admission" do
    root = fixture() |> delegate() |> delegate("D", "grandchild")
    assert :ok = Frame.validate(root)
    assert :ok = Frame.validate(root |> Jason.encode!() |> Jason.decode!())
    execution = %{"progress" => %{"runtime" => root}, "effects" => %{}}
    refute Record.execution?(execution)
    refute ToolEvidence.evidence?(%{"execution" => execution})
    refute ToolEvidence.transition?(root, root, "node_checkpoint")
    assert {:error, _} = Frame.node_transition(root, root, "A")

    for version <- [7, 8, 9],
        do: assert({:error, _} = Frame.validate(Map.put(root, "frame_version", version)))
  end

  test "valid legacy execution envelope cannot admit the new internal grammar" do
    legacy =
      File.read!(Path.join(__DIR__, "../fixtures/continuation/frame8-input-sequence.json"))
      |> Jason.decode!()

    assert Record.execution?(legacy["execution"])
    # Negative version-dispatch test, not a relabeled positive journal fixture.
    candidate = put_in(legacy["execution"], ["progress", "runtime"], fixture())
    refute Record.execution?(candidate)
  end

  test "child raw is forbidden until the linked child is closed" do
    root = fixture() |> delegate()
    raw = get_in(settled(fixture()), call_path() ++ ["raw"])
    root = put_in(root, call_path() ++ ["raw"], raw)
    assert {:error, _} = Frame.validate(root)

    root =
      root
      |> put_in(["children", "D", "status"], "completed")
      |> put_in(["children", "D", "frame", "cursor"], "finish")
      |> put_in(["children", "D", "result"], "done")

    assert :ok = Frame.validate(root)
    assert :ok = Frame.validate(put_in(root, call_path() ++ ["state"], "wrapping"))
  end

  test "step prefix ignores delegate nodes and uses root input/predecessor only" do
    root = fixture()

    root =
      root
      |> put_in(["children", "A", "status"], "completed")
      |> put_in(["children", "A", "frame", "cursor"], "finish")
      |> put_in(["children", "A", "result"], "step-output")

    root = root |> add_step("B", 1) |> delegate("B", "D")
    assert :ok = Frame.validate(root)
    assert Frame.active_step_id(root) == "B"
    assert {"D", _} = Frame.child_for(root, "B", "request-B", "call")
    assert Frame.child_for(root, "A", "request-B", "call") == nil

    assert {:error, _} =
             Frame.validate(put_in(root, ["children", "B", "link", "input"], "delegate input"))

    assert {:error, _} = Frame.validate(put_in(root, ["children", "D", "link", "index"], 1))
  end

  for {path, value} <- [
        {~w(children A parent_run_id), "D"},
        {~w(children D parent_run_id), "missing"},
        {~w(children D frame run_id), "A"},
        {~w(children D output_ref), %{"id" => "new", "version" => "1"}},
        {~w(children D link parent_request_id), "wrong"},
        {~w(children D link call_id), "wrong"},
        {~w(children D link call_hash), "bad"},
        {~w(children D link args), []},
        {~w(children D definition id), ""},
        {~w(children A link index), 0.0},
        {~w(children A link input), "not initial"},
        {~w(children D status), "paused"},
        {~w(children D result), "invented"},
        {~w(children D frame cursor), "finish"},
        {~w(frontier epoch), -1},
        {~w(frontier reason), "approval"},
        {~w(frontier extra), true},
        {~w(children D extra), true},
        {~w(scope nodes D parent_run_id), "root"}
      ] do
    test "rejects typed corruption #{inspect(path)}" do
      root = fixture() |> delegate()
      assert :ok = Frame.validate(root)

      assert {:error, _} =
               Frame.validate(put_in(root, unquote(path), unquote(Macro.escape(value))))
    end
  end

  test "identities cover authority and ledger exactly; delegate call source is unique" do
    root = fixture() |> delegate()

    for path <- [~w(authority D), ~w(scope nodes D)] do
      {_, bad} = pop_in(root, path)
      assert {:error, _} = Frame.validate(bad)
    end

    assert {:error, _} =
             Frame.validate(put_in(root, ["children", "duplicate"], root["children"]["D"]))

    assert {:error, _} = Frame.validate(put_in(root, ["children", "root"], root["children"]["A"]))
  end

  test "root depth zero: sixteen accepted, seventeen rejected" do
    root =
      Enum.reduce(2..16, fixture(), fn depth, root ->
        delegate(root, if(depth == 2, do: "A", else: "D#{depth - 1}"), "D#{depth}")
      end)

    assert :ok = Frame.validate(root)
    assert {:error, _} = Frame.validate(delegate(root, "D16", "D17"))
  end

  test "nonroot node cap accepts 255 and rejects 256 with a connected graph" do
    root =
      Enum.reduce(1..254, fixture(), fn n, root -> delegate(root, "A", "D#{n}", "call#{n}") end)

    assert :ok = Frame.validate(root)
    assert {:error, _} = Frame.validate(delegate(root, "A", "D255", "call255"))
  end

  test "closed or suspended ancestors cannot conceal running descendants" do
    root = fixture() |> delegate()
    assert {:error, _} = Frame.validate(put_in(root, ["children", "A", "status"], "suspended"))

    root =
      root
      |> put_in(["children", "A", "status"], "completed")
      |> put_in(["children", "A", "frame", "cursor"], "finish")
      |> Map.put("cursor", "between_steps")

    assert {:error, _} = Frame.validate(root)
  end

  test "queued, preparing, prepared and approval preserve phase-specific nulls" do
    for state <- ~w(queued preparing prepared approval) do
      c =
        if state in ~w(prepared approval),
          do: %{call(state) | "binding" => call_binding()},
          else: call(state)

      root = batch(fixture(), "A", "call", c)
      assert :ok = Frame.validate(root)

      assert {:error, _} =
               Frame.validate(
                 put_in(root, call_path() ++ ["control"], %{"retry" => false, "error" => nil})
               )
    end
  end

  test "raw and final controls travel together; canonical effect source and encoded identity" do
    root = settled(fixture())
    assert :ok = Frame.validate(root)

    for {path, value} <- [
          {["raw"], nil},
          {["control"], nil},
          {["raw", "control"], nil},
          {["raw", "control", "retry"], "false"},
          {["source", "id"], "other"},
          {["result"], "not encoded"},
          {["binding", "schema_hash"], String.duplicate("c", 64)},
          {["state"], "approval"},
          {["blocked_by"], "fatal"}
        ] do
      assert {:error, _} = Frame.validate(put_in(root, call_path() ++ path, value))
    end

    other =
      Outcome.encode(%ToolReturn{
        tool_name: "tool",
        tool_call_id: "another",
        content: "done",
        status: :succeeded
      })

    assert {:error, _} = Frame.validate(put_in(root, call_path() ++ ["result"], other))
  end

  test "partial raw effect and wrapping have no invented final settlement" do
    root =
      settled(fixture())
      |> put_in(call_path() ++ ["result"], nil)
      |> put_in(call_path() ++ ["control"], nil)

    for state <- ~w(dispatching wrapping) do
      current = put_in(root, call_path() ++ ["state"], state)
      assert :ok = Frame.validate(current)

      assert {:error, _} =
               Frame.validate(put_in(current, call_path() ++ ["source", "kind"], "child"))
    end
  end

  test "callback uncertainty is version-discriminated and not external evidence" do
    for state <- ~w(preparing wrapping) do
      root =
        if state == "preparing",
          do: batch(fixture(), "A", "call", call(state)),
          else:
            settled(fixture())
            |> put_in(call_path() ++ ["state"], state)
            |> put_in(call_path() ++ ["result"], nil)
            |> put_in(call_path() ++ ["control"], nil)

      assert :ok = Frame.validate(root)
      e = %{"progress" => %{"runtime" => root}, "effects" => %{}}
      assert Record.unresolved?(e)
      refute Record.unresolved?(put_in(e, ["progress", "runtime", "frame_version"], 9))
    end
  end

  test "quiescent rejects running nodes and callback markers without falsifying leaf cursor" do
    root =
      fixture()
      |> put_in(["frontier"], %{
        "epoch" => 1,
        "state" => "quiescent",
        "reason" => "approval",
        "fatal" => nil
      })

    assert {:error, _} = Frame.validate(root)
    root = put_in(root, ["children", "A", "status"], "suspended")
    assert :ok = Frame.validate(root)
    assert root["children"]["A"]["frame"]["cursor"] == "request"
    assert {:error, _} = Frame.validate(batch(root, "A", "call", call("preparing")))
  end

  test "fatal root/node/call variants have exact keys and grounded identities" do
    error = ToolEvidence.error(:known_failure)

    root =
      settled(fixture())
      |> put_in(["frontier"], %{
        "epoch" => 1,
        "state" => "draining",
        "reason" => "fatal",
        "fatal" => %{"kind" => "root", "error" => error}
      })

    assert :ok = Frame.validate(root)
    assert {:error, _} = Frame.validate(put_in(root, ["frontier", "fatal", "run_id"], "root"))

    node =
      root
      |> put_in(["children", "A", "status"], "failed")
      |> put_in(["children", "A", "error"], error)
      |> put_in(["frontier", "state"], "quiescent")
      |> Map.put("cursor", "failed")
      |> put_in(["frontier", "fatal"], %{"kind" => "node", "run_id" => "A", "error" => error})

    assert :ok = Frame.validate(node)
    assert {:error, _} = Frame.validate(put_in(node, ["frontier", "fatal", "run_id"], "unknown"))

    call =
      root
      |> put_in(call_path() ++ ["control", "error"], error)
      |> put_in(["frontier", "fatal"], %{
        "kind" => "call",
        "run_id" => "A",
        "request_id" => "request-A",
        "call_id" => "call",
        "error" => error
      })

    assert :ok = Frame.validate(call)
    assert {:error, _} = Frame.validate(put_in(call, call_path() ++ ["control", "retry"], true))
  end

  test "blocked retains raw but cannot invent final control or claim no prior effect" do
    root =
      settled(fixture())
      |> put_in(["frontier"], %{
        "epoch" => 1,
        "state" => "draining",
        "reason" => "fatal",
        "fatal" => %{"kind" => "root", "error" => ToolEvidence.error(:fatal)}
      })
      |> put_in(call_path() ++ ["state"], "blocked")
      |> put_in(call_path() ++ ["blocked_by"], "fatal")
      |> put_in(call_path() ++ ["result"], nil)
      |> put_in(call_path() ++ ["control"], nil)

    assert :ok = Frame.validate(root)
    assert root["tool_batches"][ToolEvidence.key("A", "request-A")]["calls"]["call"]["raw"]

    assert {:error, _} =
             Frame.validate(
               put_in(root, call_path() ++ ["control"], %{"retry" => false, "error" => nil})
             )
  end

  test "resolution requires all settled and consumption requires nonfatal resolution" do
    key = ToolEvidence.key("A", "request-A")

    root =
      settled(fixture())
      |> put_in(["tool_batches", key, "resolution"], %{"tool_retries" => %{}, "error" => nil})
      |> put_in(["tool_batches", key, "consumption"], %{
        "history_index" => 2,
        "returns_hash" => String.duplicate("c", 64)
      })

    assert :ok = Frame.validate(root)
    assert {:error, _} = Frame.validate(put_in(root, ["tool_batches", key, "resolution"], nil))

    assert {:error, _} =
             Frame.validate(
               put_in(
                 root,
                 ["tool_batches", key, "resolution", "error"],
                 ToolEvidence.error(:fatal)
               )
             )

    assert {:error, _} = Frame.validate(put_in(root, call_path(), call()))
  end
end
