defmodule ExAgent.Frame10OutputCapacityFixture do
  @moduledoc false
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Frame10OutputCASFixture, as: O
  alias ExAgent.Continuation.{Frame, Outcome, Record, RequestData, ToolEvidence}
  alias ExAgent.{Message, ModelSettings}

  # Fixed-width receipt IDs make the real JSON capacity boundary reproducible
  # across independently created rows. No stored row or invariant is patched.
  def command(r, command) do
    revision = if r, do: r["revision"] + 1, else: 1

    Map.put(
      command,
      "operation_id",
      "capacity-" <> String.pad_leading(to_string(revision), 8, "0")
    )
  end

  def commit(s, r, c), do: F.commit(s, r, command(r, c))
  def op(s, r, name, payload), do: commit(s, r, F.worker(r, name, payload))
  def cost(r), do: byte_size(Jason.encode!(r)) + Record.cleanup_reserve_bytes(r)

  def attached(s, limit, ids \\ ["D"]) do
    c =
      put_in(
        F.create(),
        ~w(payload execution progress runtime authority root checkpoint_limit),
        limit
      )

    r = commit(s, nil, c)
    r = commit(s, r, F.claim())

    n =
      F.node(F.root(r), "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })

    r = op(s, r, "step_input", %{"node_id" => "B", "node" => n, "authority" => F.authority()})
    args = %{"task" => "child input"}
    calls = Enum.map(ids, &F.call("delegate", &1, args))

    r =
      model(s, r, "B", "parent", calls, %{
        output_mode: :text,
        allow_text_output: true,
        output_object: nil,
        output_tools: [],
        instructions: []
      })

    r = op(s, r, "batch_begin", F.target("B", "parent"))

    Enum.reduce(ids, r, fn id, r ->
      target = F.target("B", "parent", id)
      r = op(s, r, "call_prepare", target)
      r = op(s, r, "call_prepared", Map.put(target, "args", args))
      binding = F.root(r)["tool_batches"][ToolEvidence.key("B", "parent")]["calls"][id]["binding"]

      link =
        Map.merge(binding, %{
          "kind" => "delegate",
          "parent_request_id" => "parent",
          "call_id" => id
        })

      {:ok, fingerprint} = Frame.output_fingerprint(O.params())
      node = F.node(F.root(r), id, "B", link)

      node =
        node
        |> put_in(~w(frame output_fingerprint), fingerprint)
        |> put_in(~w(frame limits output_retries), 3)

      op(
        s,
        r,
        "node_attach",
        Map.merge(target, %{"node_id" => id, "node" => node, "authority" => F.authority()})
      )
    end)
  end

  def response(s, r, run \\ "D", request \\ "typed") do
    call = %Message.Part.ToolCall{
      tool_name: "answer",
      tool_call_id: "output",
      kind: :output,
      args: %{"n" => "invalid"}
    }

    model(s, r, run, request, [call], O.params())
  end

  defp model(s, r, run, request, parts, params) do
    node = F.root(r)["children"][run]
    {:ok, messages} = Message.from_json(node["snapshot"]["message_history"])

    state = %{
      prepared_tools: Map.new(F.tools(), &{&1.name, &1}),
      settings: %ModelSettings{},
      request_messages: nil,
      messages: messages,
      params: params
    }

    {:ok, data} = RequestData.capture(state, node["frame"], %{model_ref: F.ref()}, F.root(r))
    r = op(s, r, "begin_effect", Map.put(F.target(run, request), "request_data", data))

    op(
      s,
      r,
      "outcome",
      Map.merge(F.target(run, request), %{
        "response" => Message.to_json([%Message.Response{parts: parts}]),
        "model_data" => nil
      })
    )
  end

  def resolution(r, decision, padding, run \\ "D") do
    request = F.root(r)["children"][run]["frame"]["model_request_id"]
    c = O.resolution(r, decision)
    c = c |> put_in(~w(payload run_id), run) |> put_in(~w(payload request_id), request)

    c =
      c
      |> put_in(~w(payload resolution run_id), run)
      |> put_in(~w(payload resolution request_id), request)

    c =
      if decision == "succeeded" do
        put_in(c, ~w(payload resolution result), %{"n" => 42, "padding" => padding})
      else
        parts =
          Message.to_json([
            %Message.Request{
              parts: [
                %Message.Part.Retry{tool_name: "answer", tool_call_id: "output", content: padding}
              ]
            }
          ])

        {:ok, hash} = Outcome.hash(parts)

        c
        |> put_in(~w(payload resolution parts), parts)
        |> put_in(~w(payload resolution parts_hash), hash)
      end

    command(r, c)
  end

  def consume(s, r, decision, run \\ "D")

  def consume(s, r, "retry", run) do
    request = F.root(r)["children"][run]["frame"]["model_request_id"]
    op(s, r, "output_consume", F.target(run, request))
  end

  def consume(s, r, "succeeded", run), do: op(s, r, "node_complete", %{"node_id" => run})

  def wrap(s, r, run \\ "D") do
    target = F.target("B", "parent", run)
    r = op(s, r, "call_wrap", target)
    raw = F.root(r)["tool_batches"][ToolEvidence.key("B", "parent")]["calls"][run]["raw"]
    op(s, r, "call_settle", Map.merge(target, raw))
  end
end
