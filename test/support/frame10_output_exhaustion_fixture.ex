defmodule ExAgent.Frame10OutputExhaustionFixture do
  @moduledoc false
  alias ExAgent.Frame10FatalCapacityFixture, as: F
  alias ExAgent.Frame10OutputCASFixture, as: O
  alias ExAgent.Frame10OutputCapacityFixture, as: C
  alias ExAgent.Continuation.{Frame, Outcome, OutputResolution, RequestData, ToolEvidence}
  alias ExAgent.{Message, Store}
  alias ExAgent.Message.Part

  def setup(store, order \\ ["D", "E"], limit \\ 8_388_608, pending_state \\ :running) do
    Process.put(:limit, limit)
    Process.put(:rows, [])
    r = F.started(store)
    args = %{"task" => "child input"}

    r =
      F.model(
        store,
        r,
        "B",
        "request-B",
        Enum.map(order ++ ["done"], &F.call("delegate", &1, args))
      )

    r =
      Enum.reduce(order ++ ["done"], r, fn id, r ->
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

        node = F.node(F.root(r), id, "B", link)

        node =
          if id == "D" do
            {:ok, fingerprint} = Frame.output_fingerprint(O.params())

            node
            |> put_in(~w(frame output_fingerprint), fingerprint)
            |> put_in(~w(frame limits output_retries), 0)
          else
            node
          end

        F.op(
          store,
          r,
          "node_attach",
          Map.merge(target, %{"node_id" => id, "node" => node, "authority" => F.authority()})
        )
      end)

    r =
      F.model(store, r, "done", "done-request", [%Part.Text{content: "confirmed partial"}], false)

    r = F.op(store, r, "node_complete", %{"node_id" => "done"})

    r =
      F.model(store, r, "E", "request-E", [F.call("plain", "fatal"), F.call("plain", "admitted")])

    fatal = F.target("E", "request-E", "fatal")
    r = F.prepare(store, r, fatal, %{})
    r = F.op(store, r, "begin_effect", fatal)
    r = F.op(store, r, "outcome", payload("fatal"))
    r = F.op(store, r, "call_wrap", fatal)
    admitted = F.target("E", "request-E", "admitted")

    r =
      if pending_state == :preparing do
        F.op(store, r, "call_prepare", admitted)
      else
        r = F.prepare(store, r, admitted, %{})
        F.op(store, r, "begin_effect", admitted)
      end

    r = F.commit(store, r, O.request(r, "invalid"))

    F.op(
      store,
      r,
      "outcome",
      Map.merge(F.target("D", "invalid"), %{
        "response" =>
          Message.to_json([
            %Message.Response{
              parts: [
                %Part.ToolCall{
                  tool_name: "answer",
                  tool_call_id: "output",
                  kind: :output,
                  args: %{"n" => "invalid"}
                }
              ]
            }
          ]),
        "model_data" => nil
      })
    )
  end

  def payload(id, error \\ nil) do
    Map.merge(F.target("E", "request-E", id), %{
      "result" =>
        Outcome.encode(%Part.ToolReturn{
          tool_name: "plain",
          tool_call_id: id,
          status: :succeeded,
          content: "raw " <> id
        }),
      "control" => %{"retry" => false, "error" => error}
    })
  end

  def exhaust(store, r, padding \\ String.duplicate(<<1>>, 4096)) do
    F.commit(store, r, C.resolution(r, "retry", padding))
  end

  def fatal(store, r),
    do: F.op(store, r, "call_settle", payload("fatal", ToolEvidence.reservation_error()))

  def drain(store, r), do: F.op(store, r, "outcome", payload("admitted"))
  def close(store, r), do: F.op(store, r, "finish", %{"elapsed_ms" => 29})

  def step_source(store, limit) do
    Process.put(:limit, limit)
    Process.put(:rows, [])
    r = F.commit(store, nil, F.create())
    r = F.commit(store, r, F.claim())

    node =
      F.node(F.root(r), "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })

    {:ok, fingerprint} = Frame.output_fingerprint(O.params())

    node =
      node
      |> put_in(~w(frame output_fingerprint), fingerprint)
      |> put_in(~w(frame limits output_retries), 0)

    r =
      F.op(store, r, "step_input", %{
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
      params: O.params()
    }

    {:ok, data} = RequestData.capture(state, node["frame"], %{model_ref: F.ref()}, F.root(r))
    request = String.duplicate("R", 512)
    r = F.op(store, r, "begin_effect", Map.put(F.target("B", request), "request_data", data))

    F.op(
      store,
      r,
      "outcome",
      Map.merge(F.target("B", request), %{
        "response" =>
          Message.to_json([
            %Message.Response{
              parts: [
                %Part.ToolCall{
                  tool_name: "answer",
                  tool_call_id: String.duplicate("C", 512),
                  kind: :output,
                  args: %{"n" => "invalid"}
                }
              ]
            }
          ]),
        "model_data" => nil
      })
    )
  end

  def step_exhaust(store, r) do
    request = F.root(r)["children"]["B"]["frame"]["model_request_id"]

    {:ok, entry} =
      OutputResolution.new(
        %{params: O.params(), run_id: "B", model_request_id: request},
        "retry",
        [
          %Part.Retry{
            tool_name: "answer",
            tool_call_id: String.duplicate("C", 512),
            content: String.duplicate(<<1>>, 4096)
          }
        ],
        nil,
        65_536
      )

    F.op(store, r, "output_resolution", Map.put(F.target("B", request), "resolution", entry))
  end

  def run(store, structural_order, arrivals, limit \\ 8_388_608) do
    r = setup(store, structural_order, limit)
    source = Process.get(:rows)

    r =
      Enum.reduce(arrivals, r, fn
        :node, r -> exhaust(store, r)
        :call, r -> fatal(store, r)
      end)

    r = drain(store, r)
    {close(store, r), source}
  end

  def reject(store, r, command) do
    import ExUnit.Assertions
    assert {:error, _} = Store.transition(store, :agent, "conversation", r["revision"], command)
    assert {:ok, ^r} = Store.load_record(store, :agent, "conversation")
  end
end
