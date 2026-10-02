defmodule ExAgent.Frame10SuccessFixture do
  @moduledoc false
  import ExUnit.Assertions
  alias ExAgent.Frame10OperationsFixture, as: F
  alias ExAgent.Frame10OutputCASFixture, as: O
  alias ExAgent.Frame10OutputCapacityFixture, as: C
  alias ExAgent.Continuation.{Frame, Outcome, OutputResolution, Record, RequestData, ToolEvidence}
  alias ExAgent.{Message, Store}

  def create do
    command = F.create()
    step = hd(command["payload"]["execution"]["progress"]["runtime"]["binding"]["steps"])

    steps =
      Enum.with_index(~w(A B C), fn id, index ->
        step
        |> Map.put("id", id)
        |> Map.put("input_kind", if(index == 0, do: "initial", else: "previous_output"))
      end)

    binding =
      command["payload"]["execution"]["progress"]["runtime"]["binding"]
      |> Map.put("steps", steps)
      |> Map.delete("fingerprint")

    {:ok, hash} = Record.digest(binding)
    binding = Map.put(binding, "fingerprint", hash)

    command
    |> put_in(["payload", "execution", "progress", "runtime", "binding"], binding)
    |> put_in(["payload", "snapshot", "binding"], binding)
  end

  # A real admission prefix with fixed-width receipts, not an inserted journal.
  def terminal_admission(store, limit, typed, padding, terminal \\ true) do
    command =
      put_in(
        F.create(),
        ~w(payload execution progress runtime authority root checkpoint_limit),
        limit
      )

    command =
      if terminal do
        command
      else
        binding = command["payload"]["execution"]["progress"]["runtime"]["binding"]

        next =
          hd(binding["steps"])
          |> Map.merge(%{"id" => "C", "input_kind" => "host", "input_version" => "mapping-1"})

        binding =
          binding |> Map.put("steps", binding["steps"] ++ [next]) |> Map.delete("fingerprint")

        {:ok, hash} = Record.digest(binding)
        binding = Map.put(binding, "fingerprint", hash)

        command
        |> put_in(~w(payload execution progress runtime binding), binding)
        |> put_in(~w(payload snapshot binding), binding)
      end

    r = C.commit(store, nil, command)
    r = C.commit(store, r, F.claim())

    params =
      if typed,
        do: O.params(),
        else: %{
          output_mode: :text,
          allow_text_output: true,
          output_object: nil,
          output_tools: [],
          instructions: []
        }

    node =
      F.node(F.root(r), "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })

    {:ok, fingerprint} = Frame.output_fingerprint(params)
    node = put_in(node, ~w(frame output_fingerprint), fingerprint)

    r =
      C.op(store, r, "step_input", %{
        "node_id" => "B",
        "node" => node,
        "authority" => F.authority()
      })

    node = F.root(r)["children"]["B"]
    {:ok, messages} = Message.from_json(node["snapshot"]["message_history"])

    state = %{
      prepared_tools: Map.new(F.tools(), &{&1.name, &1}),
      settings: %ExAgent.ModelSettings{},
      request_messages: nil,
      messages: messages,
      params: params
    }

    {:ok, data} = RequestData.capture(state, node["frame"], %{model_ref: F.ref()}, F.root(r))
    r = C.op(store, r, "begin_effect", Map.put(F.target("B", "final"), "request_data", data))

    parts =
      if typed,
        do: [
          %Message.Part.ToolCall{
            tool_name: "answer",
            tool_call_id: "output",
            kind: :output,
            args: %{"n" => 42}
          }
        ],
        else: [%Message.Part.Text{content: padding}]

    command =
      F.worker(
        r,
        "outcome",
        Map.merge(F.target("B", "final"), %{
          "response" => Message.to_json([%Message.Response{parts: parts}]),
          "model_data" => nil
        })
      )

    if typed do
      r = C.commit(store, r, command)

      part = %Message.Part.ToolReturn{
        tool_name: "answer",
        tool_call_id: "output",
        status: :succeeded,
        content: "ok"
      }

      {:ok, entry} =
        OutputResolution.new(
          %{params: params, run_id: "B", model_request_id: "final"},
          "succeeded",
          [part],
          %{"n" => 42, "padding" => padding},
          65_536
        )

      {r,
       C.command(
         r,
         F.worker(r, "output_resolution", Map.put(F.target("B", "final"), "resolution", entry))
       )}
    else
      {r, C.command(r, command)}
    end
  end

  def attach_step(store, r, id, index, input) do
    node =
      F.node(F.root(r), id, "root", %{
        "kind" => "step",
        "step_id" => id,
        "index" => index,
        "input" => input
      })

    node = put_in(node, ["frame", "tool_return_bytes"], 4096)
    F.op(store, r, "step_input", %{"node_id" => id, "node" => node, "authority" => F.authority()})
  end

  def complete_step(store, r, id, elapsed \\ 0),
    do: F.op(store, r, "step_output", %{"node_id" => id, "elapsed_ms" => elapsed})

  def prefix(store) do
    r = F.commit(store, nil, create())
    r = F.commit(store, r, F.claim())
    r = attach_step(store, r, "A", 0, "root input")
    r = F.model(store, r, "A", "A-tools", [F.call("plain", "effect-A")])
    r = F.settled(store, r, F.target("A", "A-tools", "effect-A"), "A effect")
    r = consume(store, r, "A", "A-tools")
    r = F.model(store, r, "A", "A-final", [%Message.Part.Text{content: "A output"}])
    r = complete_step(store, r, "A")
    attach_step(store, r, "B", 1, "A output")
  end

  def draining(store) do
    r = prefix(store)
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
      Enum.reduce(~w(D E), r, fn id, r ->
        target = F.target("B", "request-B", id)
        r = F.prepare(store, r, target, args)

        binding =
          F.root(r)["tool_batches"][ToolEvidence.key("B", "request-B")]["calls"][id]["binding"]

        link =
          Map.merge(binding, %{
            "kind" => "delegate",
            "parent_request_id" => "request-B",
            "call_id" => id
          })

        node = F.node(F.root(r), id, "B", link) |> put_in(["frame", "tool_return_bytes"], 4096)

        {node, authority} =
          if id == "D" do
            {:ok, fingerprint} = Frame.output_fingerprint(O.params())
            {put_in(node, ["frame", "output_fingerprint"], fingerprint), F.authority()}
          else
            {node,
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
          Map.merge(target, %{"node_id" => id, "node" => node, "authority" => authority})
        )
      end)

    r = F.model(store, r, "E", "request-E", [F.call("plain", "one"), F.call("plain", "two")])
    r = Enum.reduce(~w(one two), r, &F.prepare(store, &2, F.target("E", "request-E", &1), %{}))
    r = F.commit(store, r, O.request(r, "invalid"))
    r = Enum.reduce(~w(one two), r, &F.op(store, &2, "call_wait", F.target("E", "request-E", &1)))

    r =
      O.response(
        store,
        r,
        "invalid",
        Message.Usage.qualify(%Message.Usage{input_tokens: 2, output_tokens: 1})
      )

    r = F.commit(store, r, O.resolution(r, "retry"))
    F.op(store, r, "output_consume", F.target("D", "invalid"))
  end

  def reclaim(store, r) do
    r = Enum.reduce(~w(D E B), r, &F.op(store, &2, "node_suspend", %{"node_id" => &1}))
    r = F.op(store, r, "pause", %{"elapsed_ms" => 13})
    paused = r

    assert {:error, _} =
             Store.transition(
               store,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "step_output", %{"node_id" => "B", "elapsed_ms" => 0})
             )

    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")

    r =
      Enum.reduce(~w(partial ready), r, fn id, r ->
        {approval_id, approval} =
          Enum.find(r["execution"]["progress"]["approvals"], fn {_, a} ->
            is_nil(a["decision"])
          end)

        assert {:ok, _} =
                 ExAgent.Continuation.decide(store, "conversation", :approve,
                   record_id: r["record_id"],
                   revision: r["revision"],
                   operation_id: id,
                   approval_id: approval_id,
                   payload_hash: approval["payload_hash"],
                   actor: :host,
                   authorize: fn _, _, _ -> {:ok, "host"} end
                 )

        assert {:ok, r} = Store.load_record(store, :agent, "conversation")
        key = {store.namespace, :agent, "conversation"}
        assert {:ok, bytes} = Record.encode(r, key)
        assert {:ok, ^r} = Record.decode(bytes, key)
        r
      end)

    r = F.commit(store, r, F.claim("reclaimed"))
    {F.op(store, r, "frontier_open"), paused}
  end

  def finish_children(store, r) do
    r = O.model(store, r, "valid")
    r = F.commit(store, r, O.resolution(r, "succeeded"))
    r = F.op(store, r, "node_complete", %{"node_id" => "D"})
    r = wrap(store, r, "D", "wrapper Y")

    r =
      Enum.reduce(~w(one two), r, fn id, r ->
        target = F.target("E", "request-E", id)
        r = F.op(store, r, "call_prepared", Map.put(target, "args", %{}))
        r = F.op(store, r, "begin_effect", target)

        result =
          Outcome.encode(%Message.Part.ToolReturn{
            tool_name: "plain",
            tool_call_id: id,
            status: :succeeded,
            content: id
          })

        payload =
          Map.merge(target, %{
            "result" => result,
            "control" => %{"retry" => false, "error" => nil}
          })

        r = F.op(store, r, "outcome", payload)
        r = F.op(store, r, "call_wrap", target)
        F.op(store, r, "call_settle", payload)
      end)

    r = consume(store, r, "E", "request-E")
    r = F.model(store, r, "E", "E-final", [%Message.Part.Text{content: "E output"}])
    r = F.op(store, r, "node_complete", %{"node_id" => "E"})
    r = wrap(store, r, "E", "E wrapper")
    r = consume(store, r, "B", "request-B")
    F.model(store, r, "B", "B-final", [%Message.Part.Text{content: "B output"}])
  end

  def consume(store, r, run, request) do
    r = F.op(store, r, "tool_resolution", F.target(run, request))
    F.op(store, r, "batch_consume", F.target(run, request))
  end

  def wrap(store, r, id, content) do
    target = F.target("B", "request-B", id)
    r = F.op(store, r, "call_wrap", target)

    result =
      Outcome.encode(%Message.Part.ToolReturn{
        tool_name: "delegate",
        tool_call_id: id,
        status: :succeeded,
        content: content
      })

    F.op(
      store,
      r,
      "call_settle",
      Map.merge(target, %{"result" => result, "control" => %{"retry" => false, "error" => nil}})
    )
  end
end
