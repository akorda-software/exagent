defmodule ExAgent.SequenceFrame9ValidationTest do
  use ExUnit.Case, async: true

  alias ExAgent.{ExecutionScope, UsageLimits}
  alias ExAgent.Continuation.{Authority, Frame, Record}
  alias ExAgent.Coordination.Composition

  # A fresh structural fixture, not a relabeled historical record. Frame validation
  # checks structure; Record evidence and producer transitions are separate gates.
  defp frame(statuses, cursor, opts \\ []) do
    model = %ExAgent.Models.Test{script: ["unused"]}
    ref = %{id: "fixture", version: "1"}

    steps =
      for id <- ~w(A B C) do
        %{
          id: id,
          agent: ExAgent.new(model: model),
          model_codec: %{
            dump: fn _ -> flunk("structural validation called codec") end,
            load: fn _, _ -> flunk("structural validation called codec") end
          },
          definition: ref,
          policy: ref,
          model_ref: ref,
          output_ref: ref
        }
      end

    assert {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)
    assert {:ok, binding} = Composition.binding(definition)
    assert {:ok, scope} = ExecutionScope.start_structural("root", [])
    on_exit(fn -> ExecutionScope.stop(scope) end)
    assert {:ok, authority} = ExecutionScope.authority(scope)

    {children, authorities} =
      statuses
      |> Enum.with_index()
      |> Enum.reduce(
        {%{}, %{"root" => Map.put(authority, "checkpoint_limit", Record.max_bytes())}},
        fn {status, index}, {children, authorities} ->
          id = "leaf-#{index}"
          step = Enum.at(binding["steps"], index)
          assert {:ok, leaf} = ExecutionScope.join(scope, id, model, [])
          assert {:ok, local} = ExecutionScope.export_node(leaf)
          assert {:ok, authority} = ExecutionScope.authority(leaf)
          input = if index == 0, do: "initial", else: Keyword.get(opts, :result, "portable")

          child = %{
            "parent_run_id" => "root",
            "link" => %{
              "kind" => "step",
              "step_id" => step["id"],
              "index" => index,
              "input" => input
            },
            "definition" => step["definition"],
            "policy" => step["policy"],
            "model_ref" => step["model_ref"],
            "output_ref" => step["output_ref"],
            "snapshot" => nil,
            "status" => status,
            "result" => if(status == "completed", do: Keyword.get(opts, :result, "portable")),
            "result_omitted" => nil,
            "frame" => %{
              "frame_version" => 3,
              "cursor" => if(status == "completed", do: "finish", else: "request"),
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
              "limits" => %{"output_retries" => 0, "usage" => Authority.usage(%UsageLimits{})},
              "permissions" => %{},
              "scope" => local,
              "outcomes" => %{},
              "output_fingerprint" => nil
            }
          }

          {Map.put(children, id, child), Map.put(authorities, id, Map.delete(authority, "usage"))}
        end
      )

    assert {:ok, ledger} = ExecutionScope.export_tree(scope)

    candidate = %{
      "frame_version" => 9,
      "kind" => "sequence",
      "cursor" => cursor,
      "run_id" => "root",
      "binding" => binding,
      "input" => "initial",
      "scope" => ledger,
      "children" => children,
      "output_resolutions" => %{},
      "tool_batches" => %{},
      "authority" => authorities
    }

    assert :ok = Frame.validate(candidate)
    candidate
  end

  for {statuses, cursor} <- [
        {[], "empty"},
        {["running"], "running"},
        {["completed"], "between_steps"},
        {["completed", "running"], "running"},
        {["completed", "completed"], "between_steps"},
        {["completed", "completed", "running"], "running"},
        {["completed", "completed", "completed"], "completed"}
      ] do
    test "ordered prefix #{inspect(statuses)} / #{cursor}" do
      frame = frame(unquote(statuses), unquote(cursor))
      assert :ok = Frame.validate(frame)
      assert :ok = Frame.validate(frame |> Jason.encode!() |> Jason.decode!())
    end
  end

  test "portable nil is a valid predecessor value" do
    assert :ok = Frame.validate(frame(["completed", "running"], "running", result: nil))
  end

  test "omission can close a prefix but cannot have a successor" do
    marker = ExAgent.Retention.marker(:checkpoint, 10, 1)
    one = frame(["completed"], "between_steps", result: nil)
    assert :ok = Frame.validate(put_in(one, ["children", "leaf-0", "result_omitted"], marker))
    two = frame(["completed", "running"], "running", result: nil)

    assert {:error, _} =
             Frame.validate(put_in(two, ["children", "leaf-0", "result_omitted"], marker))
  end

  for {field, value} <- [
        {~w(cursor), "completed"},
        {~w(cursor), "empty"},
        {~w(children leaf-1 link index), 0},
        {~w(children leaf-1 link index), 2},
        {~w(children leaf-1 link index), 1.0},
        {~w(children leaf-1 link step_id), "A"},
        {~w(children leaf-1 link input), "live output"},
        {~w(children leaf-0 status), "running"},
        {~w(children leaf-1 status), "paused"},
        {~w(children leaf-1 frame frame_version), 8},
        {~w(children leaf-1 parent_run_id), "leaf-0"},
        {~w(children leaf-1 output_ref id), "different"},
        {~w(children leaf-1 frame run_id), "leaf-0"}
      ] do
    test "rejects corruption #{Enum.join(field, ".")} = #{inspect(value)}" do
      candidate = frame(["completed", "running"], "running")
      assert {:error, _} = Frame.validate(put_in(candidate, unquote(field), unquote(value)))
    end
  end

  test "rejects duplicate root identity, missing authority, extra nodes and duplicate progress" do
    candidate = frame(["completed", "running"], "running")
    assert {:error, _} = Frame.validate(Map.put(candidate, "next_index", 2))

    assert {:error, _} =
             Frame.validate(update_in(candidate["authority"], &Map.delete(&1, "leaf-0")))

    assert {:error, _} =
             Frame.validate(
               update_in(candidate["scope"]["nodes"], &Map.put(&1, "orphan", &1["leaf-0"]))
             )

    assert {:error, _} =
             Frame.validate(
               put_in(candidate, ["children", "root"], candidate["children"]["leaf-0"])
             )
  end

  test "rejects output evidence for an unknown leaf or mismatched global request key" do
    candidate = frame(["completed", "running"], "running")

    for entry <- [
          %{"run_id" => "orphan", "request_id" => "request"},
          %{"run_id" => "leaf-0", "request_id" => "different"}
        ] do
      assert {:error, _} =
               Frame.validate(put_in(candidate, ["output_resolutions", "request"], entry))
    end
  end
end
