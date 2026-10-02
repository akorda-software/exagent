defmodule ExAgent.Frame10ExhaustionCapacityFixture do
  @moduledoc false
  import ExUnit.Assertions
  alias ExAgent.{Message, Retention}
  alias ExAgent.Message.Part
  alias ExAgent.Continuation.{Frame, OutputResolution, Record, RequestData, ToolEvidence}
  alias ExAgent.Frame10FatalCapacityFixture, as: F
  alias ExAgent.Frame10OutputCASFixture, as: O

  def params(size) do
    p = O.params()
    [tool] = p.output_tools
    {:ok, descriptor} = Frame.output_descriptor(p)
    padding = if size == :max, do: 65_536 - byte_size(Jason.encode!(descriptor)), else: 0

    %{
      p
      | output_tools: [%{tool | description: tool.description <> String.duplicate("x", padding)}]
    }
  end

  def id(label, opts) do
    if opts[:large_ids], do: String.duplicate(<<1>>, 512 - byte_size(label)) <> label, else: label
  end

  def runs(opts), do: Enum.map(1..Keyword.get(opts, :nodes, 1), &id("D#{&1}", opts))
  def cost(r), do: byte_size(Jason.encode!(r)) + Record.cleanup_reserve_bytes(r)

  def diagnostic(opts) do
    reason =
      case Keyword.get(opts, :diagnostic, :control) do
        :control -> [String.duplicate(<<1>>, 4000)]
        :unicode -> [String.duplicate("雪\"\\\n", 550)]
        :small -> ["invalid"]
      end

    assert Retention.reason(reason) == reason
    assert Retention.bytes(reason) <= 4096
    Jason.encode!(%{"errors" => reason})
  end

  def source(s, limit, opts) do
    Process.put(:limit, limit)
    Process.put(:rows, [])
    r = F.commit(s, nil, F.create())
    r = F.commit(s, r, F.claim())

    node =
      F.node(F.root(r), "B", "root", %{
        "kind" => "step",
        "step_id" => "B",
        "index" => 0,
        "input" => "root input"
      })
      |> put_in(~w(frame tool_return_bytes), Keyword.get(opts, :tool_limit, 4096))

    r =
      F.op(s, r, "step_input", %{"node_id" => "B", "node" => node, "authority" => F.authority()})

    args = %{"task" => "input"}
    ids = runs(opts)
    done = if opts[:completed], do: ["done"], else: []
    plains = Enum.map(Enum.to_list(1..Keyword.get(opts, :siblings, 0)//1), &"plain-#{&1}")

    calls =
      Enum.map(ids ++ done, &F.call("delegate", &1, args)) ++
        Enum.map(plains, &F.call("plain", &1))

    r = F.model(s, r, "B", "parent", calls)

    r =
      Enum.reduce(ids ++ done, r, fn run, r ->
        target = F.target("B", "parent", run)
        r = F.prepare(s, r, target, args)

        binding =
          F.root(r)["tool_batches"][ToolEvidence.key("B", "parent")]["calls"][run]["binding"]

        link =
          Map.merge(binding, %{
            "kind" => "delegate",
            "parent_request_id" => "parent",
            "call_id" => run
          })

        n = F.node(F.root(r), run, "B", link)

        n =
          if run != "done" or opts[:completed] == :typed do
            {:ok, fingerprint} = Frame.output_fingerprint(params(opts[:descriptor]))

            n
            |> put_in(~w(frame output_fingerprint), fingerprint)
            |> put_in(~w(frame limits output_retries), Keyword.get(opts, :retries, 0))
          else
            n
          end

        F.op(
          s,
          r,
          "node_attach",
          Map.merge(target, %{"node_id" => run, "node" => n, "authority" => F.authority()})
        )
      end)

    r =
      case opts[:completed] do
        :plain ->
          r = F.model(s, r, "done", "done-response", [%Part.Text{content: "partial 雪"}], false)
          F.op(s, r, "node_complete", %{"node_id" => "done"})

        :typed ->
          r = response(s, r, "done", "done-response", opts)
          r = resolve(s, r, "done", opts, "succeeded")
          completed = F.op(s, r, "node_complete", %{"node_id" => "done"})
          assert cost(completed) <= cost(r)
          completed

        _ ->
          r
      end

    r =
      if opts[:settled] do
        F.settled(s, r, F.target("B", "parent", hd(plains)), "materialized 雪")
      else
        r
      end

    r =
      Enum.reduce(Enum.to_list(1..Keyword.get(opts, :retries, 0)//1), r, fn i, r ->
        Enum.reduce(ids, r, fn run, r ->
          request = id("#{String.last(run)}-retry-#{i}", opts)
          r = response(s, r, run, request, opts)
          r = resolve(s, r, run, opts)
          F.op(s, r, "output_consume", F.target(run, request))
        end)
      end)

    Enum.reduce(ids, r, fn run, r ->
      response(s, r, run, id("#{String.last(run)}-terminal", opts), opts)
    end)
  end

  def response(s, r, run, request, opts) do
    node = F.root(r)["children"][run]
    {:ok, messages} = Message.from_json(node["snapshot"]["message_history"])

    state = %{
      prepared_tools: Map.new(F.tools(), &{&1.name, &1}),
      settings: %ExAgent.ModelSettings{},
      request_messages: nil,
      messages: messages,
      params: params(opts[:descriptor])
    }

    {:ok, data} = RequestData.capture(state, node["frame"], %{model_ref: F.ref()}, F.root(r))
    r = F.op(s, r, "begin_effect", Map.put(F.target(run, request), "request_data", data))

    call = %Part.ToolCall{
      tool_name: "answer",
      tool_call_id: id("output", opts),
      kind: :output,
      args: %{"n" => "invalid"}
    }

    siblings =
      Enum.map(
        Enum.to_list(1..Keyword.get(opts, :output_siblings, 0)//1),
        &F.call("plain", id("stub-#{&1}", opts))
      )

    F.op(
      s,
      r,
      "outcome",
      Map.merge(F.target(run, request), %{
        "response" => Message.to_json([%Message.Response{parts: [call | siblings]}]),
        "model_data" => nil
      })
    )
  end

  def resolve(s, r, run, opts, decision \\ "retry") do
    request = F.root(r)["children"][run]["frame"]["model_request_id"]

    part =
      if decision == "retry" do
        %Part.Retry{
          tool_name: "answer",
          tool_call_id: id("output", opts),
          content: diagnostic(opts)
        }
      else
        %Part.ToolReturn{
          tool_name: "answer",
          tool_call_id: id("output", opts),
          status: :succeeded,
          content: "ok"
        }
      end

    stubs =
      Enum.map(Enum.to_list(1..Keyword.get(opts, :output_siblings, 0)//1), fn i ->
        %Part.ToolReturn{
          tool_name: "plain",
          tool_call_id: id("stub-#{i}", opts),
          status: :not_executed,
          content: "Tool not executed - a final result was already processed."
        }
      end)

    {:ok, entry} =
      OutputResolution.new(
        %{params: params(opts[:descriptor]), run_id: run, model_request_id: request},
        decision,
        [part | stubs],
        if(decision == "succeeded", do: %{"n" => 42}),
        65_536
      )

    F.op(s, r, "output_resolution", Map.put(F.target(run, request), "resolution", entry))
  end

  def close(s, r, opts, order \\ nil) do
    Enum.reduce(order || runs(opts), r, fn run, before ->
      after_record = resolve(s, before, run, opts)
      parent_batch = F.root(after_record)["tool_batches"][ToolEvidence.key("B", "parent")]

      assert byte_size(parent_batch["calls"][run]["raw"]["result"]) <=
               Keyword.get(opts, :tool_limit, 4096)

      assert cost(after_record) <= cost(before)
      assert F.root(after_record)["scope"] == F.root(before)["scope"]
      assert after_record["execution"]["effects"] == before["execution"]["effects"]

      for {key, batch} <- F.root(before)["tool_batches"],
          {call_id, call} <- batch["calls"],
          call_id != run do
        assert F.root(after_record)["tool_batches"][key]["calls"][call_id] == call
      end

      for {other, node} <- F.root(before)["children"], other != run do
        actual = F.root(after_record)["children"][other]

        if other == F.root(before)["children"][run]["parent_run_id"] do
          # Only the selected child's canonical outcome is appended to its parent.
          assert update_in(actual, ["frame", "outcomes"], &Map.delete(&1, run)) == node
        else
          assert actual == node
        end
      end

      after_record
    end)
    |> then(fn before ->
      r = F.op(s, before, "finish", %{"elapsed_ms" => 17})
      assert cost(r) <= cost(before)
      assert r["execution"]["state"] == "failed"
      assert r["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_983
      r
    end)
  end
end
