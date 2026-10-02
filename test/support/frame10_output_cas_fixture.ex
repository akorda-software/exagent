defmodule ExAgent.Frame10OutputCASFixture do
  @moduledoc false
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Continuation.{Frame, OutputResolution, RequestData}
  alias ExAgent.{Message, ModelSettings, Tool}
  alias ExAgent.Message.Part

  def params do
    tool = %Tool{
      name: "answer",
      description: "typed answer",
      kind: :output,
      takes_ctx: false,
      parameters_json_schema: %{
        "type" => "object",
        "properties" => %{"n" => %{"type" => "integer"}}
      },
      call: fn _ -> raise "no validation callback in CAS fixture" end
    }

    %{
      output_mode: :tool,
      allow_text_output: false,
      output_object: nil,
      output_tools: [tool],
      instructions: []
    }
  end

  def attached(store, retries \\ 1) do
    {r, payload} = F.attached(store, F.started(store))
    {:ok, fingerprint} = Frame.output_fingerprint(params())

    payload =
      payload
      |> put_in(["node", "frame", "output_fingerprint"], fingerprint)
      |> put_in(["node", "frame", "limits", "output_retries"], retries)

    F.op(store, r, "node_attach", payload)
  end

  def request(r, request) do
    node = F.root(r)["children"]["D"]
    {:ok, messages} = Message.from_json(node["snapshot"]["message_history"])

    state = %{
      prepared_tools: Map.new(F.tools(), &{&1.name, &1}),
      settings: %ModelSettings{},
      request_messages: nil,
      messages: messages,
      params: params()
    }

    {:ok, data} = RequestData.capture(state, node["frame"], %{model_ref: F.ref()}, F.root(r))
    F.worker(r, "begin_effect", Map.put(F.target("D", request), "request_data", data))
  end

  def model(store, r, request, usage \\ nil) do
    r = F.commit(store, r, request(r, request))
    response(store, r, request, usage)
  end

  def response(store, r, request, usage \\ nil) do
    call = %Part.ToolCall{
      tool_name: "answer",
      tool_call_id: "output",
      kind: :output,
      args: %{"n" => "invalid"}
    }

    F.op(
      store,
      r,
      "outcome",
      Map.merge(F.target("D", request), %{
        "response" => Message.to_json([%Message.Response{parts: [call], usage: usage}]),
        "model_data" => nil
      })
    )
  end

  def draining(store) do
    r = F.started(store)
    args = %{"task" => "child input"}

    r =
      F.model(store, r, "B", "request-B", [
        F.call("delegate", "D", args),
        F.call("delegate", "E", args),
        F.call("plain", "settled")
      ])

    r =
      F.settled(
        store,
        r,
        F.target("B", "request-B", "settled"),
        "sibling",
        Message.Usage.qualify(%Message.Usage{input_tokens: 1, output_tokens: 1})
      )

    r =
      Enum.reduce(["D", "E"], r, fn id, r ->
        target = F.target("B", "request-B", id)
        r = F.prepare(store, r, target, args)

        binding =
          F.root(r)["tool_batches"][ExAgent.Continuation.ToolEvidence.key("B", "request-B")][
            "calls"
          ][id]["binding"]

        link =
          Map.merge(binding, %{
            "kind" => "delegate",
            "parent_request_id" => "request-B",
            "call_id" => id
          })

        n = F.node(F.root(r), id, "B", link)

        {n, authority} =
          if id == "D" do
            {:ok, fingerprint} = Frame.output_fingerprint(params())
            {put_in(n, ["frame", "output_fingerprint"], fingerprint), F.authority()}
          else
            {n,
             update_in(
               F.authority(),
               ["policies"],
               &(&1 ++ [%{"default" => "ask", "rules" => []}])
             )}
          end

        F.op(
          store,
          r,
          "node_attach",
          Map.merge(target, %{"node_id" => id, "node" => n, "authority" => authority})
        )
      end)

    r = F.model(store, r, "E", "request-E", [F.call("plain", "one"), F.call("plain", "two")])
    r = F.prepare(store, r, F.target("E", "request-E", "one"), %{})
    r = F.prepare(store, r, F.target("E", "request-E", "two"), %{})
    r = F.commit(store, r, request(r, "invalid"))
    r = F.op(store, r, "call_wait", F.target("E", "request-E", "one"))
    r = F.op(store, r, "call_wait", F.target("E", "request-E", "two"))

    response(
      store,
      r,
      "invalid",
      Message.Usage.qualify(%Message.Usage{input_tokens: 2, output_tokens: 1})
    )
  end

  # Already-observed callback result is a trusted command input, not recomputed
  # from the raw arguments, and not evidence of real runtime hook execution.
  def resolution(r, decision) do
    request = F.root(r)["children"]["D"]["frame"]["model_request_id"]

    {part, result} =
      case decision do
        "retry" ->
          {%Part.Retry{tool_name: "answer", tool_call_id: "output", content: "expected integer"},
           nil}

        "succeeded" ->
          {%Part.ToolReturn{
             tool_name: "answer",
             tool_call_id: "output",
             status: :succeeded,
             content: "ok"
           }, %{"n" => 42}}
      end

    {:ok, entry} =
      OutputResolution.new(
        %{params: params(), run_id: "D", model_request_id: request},
        decision,
        [part],
        result,
        65_536
      )

    F.worker(r, "output_resolution", Map.put(F.target("D", request), "resolution", entry))
  end
end
