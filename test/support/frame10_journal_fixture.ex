defmodule ExAgent.Frame10JournalFixture do
  @moduledoc false
  alias ExAgent.Continuation.{Authority, Outcome, Record, ScopeLedger, ToolEvidence}
  alias ExAgent.Coordination.Composition
  alias ExAgent.Message
  alias ExAgent.Message.{Part, Usage}

  # Synthetic Frame10 journal fragment, not a producer trace or executable Record.
  # Real portable frames, model response hashes and ledger entries are constructed
  # together; no historical fixture/version/status is coerced into a positive.
  def new do
    ref = %{id: "synthetic", version: "1"}

    step = %{
      id: "A",
      agent: ExAgent.new(model: %ExAgent.Models.Test{script: []}),
      definition: ref,
      policy: ref,
      model_ref: ref,
      output_ref: ref,
      model_codec: %{dump: fn _ -> raise "no codec" end, load: fn _, _ -> raise "no codec" end}
    }

    {:ok, definition} = Composition.new(id: "journal", version: "1", steps: [step])
    {:ok, binding} = Composition.binding(definition)
    schema = String.duplicate("a", 64)

    calls =
      for id <- ["z-first", "a-second"],
          do: %Part.ToolCall{tool_name: "tool", tool_call_id: id, args: %{}, kind: :function}

    response = %Message.Response{parts: calls}
    messages = [%Message.Request{parts: [%Part.User{content: "input"}], run_id: "A"}, response]
    usage = %Usage{input_tokens: 1, output_tokens: 1} |> Usage.qualify() |> Usage.to_map()

    op = %{
      "id" => ["model", "request"],
      "run_id" => "A",
      "usage" => usage,
      "terminal_usage" => usage,
      "complete" => true,
      "ancestors" => %{"root" => usage, "A" => usage}
    }

    scope = %{
      "scope_version" => 2,
      "root_run_id" => "root",
      "nodes" => %{
        "root" => %{"parent_run_id" => nil, "requests" => 1, "tools" => 2},
        "A" => %{"parent_run_id" => "root", "requests" => 1, "tools" => 2}
      },
      "operations" => [op],
      "batches" => [%{"run_id" => "A", "id" => "request", "count" => 2}],
      "retry_batches" => []
    }

    {:ok, leaf_scope} = ScopeLedger.node_data(scope, "A")
    limits = Authority.usage(%ExAgent.UsageLimits{})

    leaf = %{
      "frame_version" => 3,
      "cursor" => "batch",
      "run_id" => "A",
      "first_new_message_index" => 0,
      "run_step" => 1,
      "model_request_id" => "request",
      "tool_retries" => %{},
      "output_retries_used" => 0,
      "tool_return_bytes" => 65_536,
      "selected_tools" => %{"tool" => schema},
      "model_data" => nil,
      "model_binding" => nil,
      "settings" => %{},
      "limits" => %{"output_retries" => 1, "usage" => limits},
      "permissions" => %{},
      "scope" => leaf_scope,
      "outcomes" => %{},
      "output_fingerprint" => nil
    }

    node =
      Map.merge(
        hd(binding["steps"]) |> Map.take(~w(definition policy model_ref output_ref)),
        %{
          "parent_run_id" => "root",
          "link" => %{"kind" => "step", "step_id" => "A", "index" => 0, "input" => "input"},
          "frame" => leaf,
          "snapshot" => %{"message_history" => Message.to_json(messages)},
          "status" => "running",
          "result" => nil,
          "result_omitted" => nil,
          "error" => nil
        }
      )

    authority = %{
      "policies" => [%{"default" => "allow", "rules" => []}],
      "deadline_at" => nil,
      "max_concurrent_requests" => nil
    }

    data =
      Map.new(calls, fn call ->
        part = %Part.ToolReturn{
          tool_name: call.tool_name,
          tool_call_id: call.tool_call_id,
          content: "done",
          status: :succeeded
        }

        bytes = Outcome.encode(part)
        control = %{"retry" => false, "error" => nil}

        {call.tool_call_id,
         %{
           "state" => "settled",
           "binding" => %{
             "tool_name" => "tool",
             "args" => %{},
             "schema_hash" => schema,
             "call_hash" => elem(Outcome.call_hash(call), 1)
           },
           "source" => %{
             "kind" => "effect",
             "id" => ToolEvidence.effect_id("A", "request", call.tool_call_id)
           },
           "raw" => %{"result" => bytes, "control" => control},
           "result" => bytes,
           "control" => control,
           "blocked_by" => nil
         }}
      end)

    batch = %{
      "run_id" => "A",
      "request_id" => "request",
      "limits" => %{"tool" => %{"schema_hash" => schema, "max_retries" => 1}},
      "calls" => data,
      "observations" =>
        Map.new(calls, fn c ->
          {ToolEvidence.effect_id("A", "request", c.tool_call_id),
           elem(ToolEvidence.observe(nil), 0)}
        end),
      "resolution" => %{"tool_retries" => %{}, "error" => nil},
      "consumption" => nil
    }

    root = %{
      "frame_version" => 10,
      "kind" => "sequence",
      "cursor" => "running",
      "run_id" => "root",
      "binding" => binding,
      "input" => "input",
      "children" => %{
        "A" =>
          put_in(node, ["frame", "outcomes"], Map.new(data, fn {id, c} -> {id, c["result"]} end))
      },
      "scope" => scope,
      "tool_batches" => %{ToolEvidence.key("A", "request") => batch},
      "output_resolutions" => %{},
      "authority" => %{
        "root" =>
          Map.merge(authority, %{"usage" => limits, "checkpoint_limit" => Record.max_bytes()}),
        "A" => authority
      },
      "frontier" => %{"epoch" => 0, "state" => "open", "reason" => nil, "fatal" => nil}
    }

    effects =
      Map.new(calls, fn call ->
        c = data[call.tool_call_id]
        {:ok, [%Message.Request{parts: [part]}]} = Message.from_json(c["result"])
        {:ok, outcome} = Outcome.new(part, "final")

        {c["source"]["id"],
         %{
           "state" => "confirmed",
           "intent" => %{
             "kind" => "tool",
             "call_id" => call.tool_call_id,
             "payload" =>
               Map.merge(c["binding"], %{
                 "run_id" => "A",
                 "model_request_id" => "request",
                 "phase" => "dispatch"
               })
           },
           "outcome" => outcome
         }}
      end)

    model = %{
      "state" => "confirmed",
      "intent" => %{
        "kind" => "model",
        "call_id" => "request",
        "payload" => %{"run_id" => "A", "step" => 1, "history_index" => 1}
      },
      "outcome" => Outcome.model(response, nil)
    }

    %{
      "execution" => %{
        "progress" => %{"runtime" => root},
        "effects" => Map.put(effects, "model", model)
      }
    }
  end

  def output(consumed \\ false) do
    record = new()

    tool = %ExAgent.Tool{
      name: "final_result",
      description: "Output",
      parameters_json_schema: %{"type" => "object"},
      kind: :output,
      takes_ctx: false,
      call: nil
    }

    params = %ExAgent.ModelRequestParameters{
      output_mode: :tool,
      output_tools: [tool],
      allow_text_output: false,
      output_object: nil
    }

    {:ok, descriptor} = ExAgent.Continuation.Frame.output_descriptor(params)
    {:ok, fingerprint} = Record.digest(descriptor)

    call = %Part.ToolCall{
      tool_name: "final_result",
      tool_call_id: "output",
      args: %{},
      kind: :function
    }

    response = %Message.Response{parts: [call]}

    retry = %Message.Request{
      parts: [
        %Part.Retry{tool_name: "final_result", tool_call_id: "output", content: "invalid output"}
      ]
    }

    bytes = Message.to_json([retry])

    entry = %{
      "output_resolution_version" => 1,
      "run_id" => "A",
      "request_id" => "request",
      "descriptor" => descriptor,
      "call_id" => "output",
      "decision" => "retry",
      "parts" => bytes,
      "parts_hash" => elem(Outcome.hash(bytes), 1),
      "result" => nil,
      "result_omitted" => nil
    }

    messages =
      [%Message.Request{parts: [%Part.User{content: "input"}], run_id: "A"}, response] ++
        if(consumed, do: [retry], else: [])

    scope =
      root(record)["scope"]
      |> Map.put("batches", [])
      |> put_in(["nodes", "root", "tools"], 0)
      |> put_in(["nodes", "A", "tools"], 0)

    {:ok, leaf_scope} = ScopeLedger.node_data(scope, "A")

    root =
      root(record)
      |> Map.put("scope", scope)
      |> Map.put("tool_batches", %{})
      |> Map.put("output_resolutions", %{"request" => entry})
      |> put_in(["children", "A", "frame", "scope"], leaf_scope)
      |> put_in(
        ["children", "A", "frame", "cursor"],
        if(consumed, do: "request", else: "response")
      )
      |> put_in(["children", "A", "frame", "selected_tools"], %{})
      |> put_in(["children", "A", "frame", "outcomes"], %{})
      |> put_in(["children", "A", "frame", "output_fingerprint"], fingerprint)
      |> put_in(["children", "A", "frame", "output_retries_used"], if(consumed, do: 1, else: 0))
      |> put_in(["children", "A", "snapshot", "message_history"], Message.to_json(messages))
      |> put_in(["children", "A", "status"], "suspended")
      |> Map.put("frontier", %{
        "epoch" => 1,
        "state" => "draining",
        "reason" => "approval",
        "fatal" => nil
      })

    model =
      record["execution"]["effects"]["model"]
      |> Map.put("outcome", Outcome.model(response, nil))
      |> put_in(["intent", "payload", "request_data"], %{"output_fingerprint" => fingerprint})

    record
    |> put_in(root_path(), root)
    |> put_in(["execution", "effects"], %{"model" => model})
  end

  # A second real synthetic model position; the previous batch's return request
  # is retained verbatim. No record/frame version or status coercion.
  def next_batch(record) do
    previous = batch(record)
    ordered = ToolEvidence.calls(record, previous)

    parts =
      for c <- ordered do
        {:ok, [%Message.Request{parts: [part]}]} =
          Message.from_json(previous["calls"][c.tool_call_id]["result"])

        part
      end

    returns = %Message.Request{parts: parts}
    bytes = Message.to_json([returns])

    previous =
      Map.put(previous, "consumption", %{
        "history_index" => 2,
        "returns_hash" => elem(Outcome.hash(bytes), 1)
      })

    fresh = new()
    current = batch(fresh)

    current = %{
      current
      | "request_id" => "request-2",
        "calls" =>
          Map.new(current["calls"], fn {id, c} ->
            {id, put_in(c, ["source", "id"], ToolEvidence.effect_id("A", "request-2", id))}
          end),
        "observations" =>
          Map.new(ordered, fn c ->
            {ToolEvidence.effect_id("A", "request-2", c.tool_call_id),
             elem(ToolEvidence.observe(nil), 0)}
          end)
    }

    {:ok, messages} =
      Message.from_json(root(record)["children"]["A"]["snapshot"]["message_history"])

    response = List.last(messages)
    scope = root(record)["scope"]
    op = %{hd(scope["operations"]) | "id" => ["model", "request-2"]}

    scope =
      scope
      |> Map.update!("operations", &(&1 ++ [op]))
      |> Map.update!("batches", &(&1 ++ [%{"run_id" => "A", "id" => "request-2", "count" => 2}]))
      |> Map.update!("nodes", fn nodes ->
        Map.new(nodes, fn {id, n} -> {id, %{n | "requests" => 2, "tools" => 4}} end)
      end)

    {:ok, own} = ScopeLedger.node_data(scope, "A")

    extra =
      Map.new(fresh["execution"]["effects"], fn
        {"model", e} ->
          {"model-2",
           e
           |> put_in(["intent", "call_id"], "request-2")
           |> put_in(["intent", "payload", "step"], 2)
           |> put_in(["intent", "payload", "history_index"], 3)}

        {_id, e} ->
          {ToolEvidence.effect_id("A", "request-2", e["intent"]["call_id"]),
           put_in(e, ["intent", "payload", "model_request_id"], "request-2")}
      end)

    record
    |> put_in(batch_path(), previous)
    |> put_in(root_path() ++ ["tool_batches", ToolEvidence.key("A", "request-2")], current)
    |> put_in(root_path() ++ ["scope"], scope)
    |> put_in(root_path() ++ ~w(children A frame scope), own)
    |> put_in(root_path() ++ ~w(children A frame run_step), 2)
    |> put_in(root_path() ++ ~w(children A frame model_request_id), "request-2")
    |> put_in(
      root_path() ++ ~w(children A snapshot message_history),
      Message.to_json(messages ++ [returns, response])
    )
    |> update_in(["execution", "effects"], &Map.merge(&1, extra))
  end

  def phase(record, call_id, state, raw? \\ false) do
    path = batch_path() ++ ["calls", call_id]
    call = get_in(record, path)
    id = ToolEvidence.effect_id("A", "request", call_id)
    source? = state in ~w(dispatching wrapping blocked)

    next = %{
      call
      | "state" => state,
        "binding" => if(state not in ~w(queued preparing), do: call["binding"]),
        "source" => if(source?, do: call["source"]),
        "raw" => if(raw?, do: call["raw"]),
        "result" => nil,
        "control" => nil,
        "blocked_by" => if(state == "blocked", do: "fatal")
    }

    effects = record["execution"]["effects"]

    effects =
      if source? do
        outcome =
          if raw? do
            {:ok, [%Message.Request{parts: [part]}]} = Message.from_json(call["raw"]["result"])
            elem(Outcome.new(part, "raw"), 1)
          end

        Map.put(effects, id, %{
          effects[id]
          | "state" => if(raw?, do: "confirmed", else: "running"),
            "outcome" => outcome
        })
      else
        Map.delete(effects, id)
      end

    record =
      record
      |> put_in(path, next)
      |> put_in(batch_path() ++ ["resolution"], nil)
      |> put_in(["execution", "effects"], effects)

    record =
      if raw? do
        record
      else
        record
        |> update_in(batch_path() ++ ["observations"], &Map.delete(&1, id))
        |> update_in(root_path() ++ ~w(children A frame outcomes), &Map.delete(&1, call_id))
      end

    if state == "blocked" do
      put_in(record, root_path() ++ ["frontier"], %{
        "epoch" => 1,
        "state" => "draining",
        "reason" => "fatal",
        "fatal" => %{"kind" => "root", "error" => ToolEvidence.error(:failure)}
      })
    else
      record
    end
  end

  def root(record), do: record["execution"]["progress"]["runtime"]
  def batch(record), do: root(record)["tool_batches"][ToolEvidence.key("A", "request")]

  def batch_path,
    do: ~w(execution progress runtime tool_batches) ++ [ToolEvidence.key("A", "request")]

  def root_path, do: ~w(execution progress runtime)
end
