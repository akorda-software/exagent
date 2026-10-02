defmodule ExAgent.Frame10FatalCapacityTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 600_000
  alias ExAgent.Frame10FatalCapacityFixture, as: F
  alias ExAgent.{Store, Message}
  alias ExAgent.Continuation.{Record, ToolEvidence, Outcome}
  alias Message.Part

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    :ok
  end

  defp attach(s, r, parent, id) do
    t = F.target(parent, "req-" <> parent, id)
    r = F.prepare(s, r, t, %{"task" => "child input"})

    b =
      F.root(r)["tool_batches"][ToolEvidence.key(parent, "req-" <> parent)]["calls"][id][
        "binding"
      ]

    link =
      Map.merge(b, %{
        "kind" => "delegate",
        "parent_request_id" => "req-" <> parent,
        "call_id" => id
      })

    node = F.node(F.root(r), id, parent, link)

    F.op(
      s,
      r,
      "node_attach",
      Map.merge(t, %{"node_id" => id, "node" => node, "authority" => F.authority()})
    )
  end

  defp payload(run, id, error \\ nil) do
    Map.merge(F.target(run, "req-" <> run, id), %{
      "result" => bounded_return(id, "plain"),
      "control" => %{"retry" => false, "error" => error}
    })
  end

  defp bounded_return(id, tool) do
    part = %Part.ToolReturn{
      tool_name: tool,
      tool_call_id: id,
      content: String.duplicate(Process.get(:text, "\"\\\n"), 120),
      status: :succeeded
    }

    bytes = Outcome.encode(part)

    bytes =
      Outcome.encode(%{
        part
        | content: part.content <> String.duplicate("x", 4096 - byte_size(bytes))
      })

    assert byte_size(bytes) == 4096
    bytes
  end

  defp error do
    error = %{
      ToolEvidence.error(:failure)
      | "message" => String.duplicate(<<1>>, 512),
        "details" => %{"pad" => ""}
    }

    error =
      put_in(
        error,
        ["details", "pad"],
        String.duplicate("x", 4096 - byte_size(Jason.encode!(error)))
      )

    assert byte_size(Jason.encode!(error)) == 4096
    error
  end

  defp wrap(s, r, run, id) do
    t = F.target(run, "req-" <> run, id)
    r = F.prepare(s, r, t, %{})
    r = F.op(s, r, "begin_effect", t)
    r = F.op(s, r, "outcome", payload(run, id))
    F.op(s, r, "call_wrap", t)
  end

  defp flow(ns, limit, source \\ :effect) do
    Process.put(:limit, limit)
    Process.put(:rows, [])
    s = Store.scoped({Store.ETS, __MODULE__}, ns)
    r = F.started(s)
    d = "z" <> String.duplicate(<<3>>, 24)
    e = "a" <> String.duplicate(<<4>>, 24)

    r =
      F.model(s, r, "B", "req-B", [
        F.call("delegate", d),
        F.call("delegate", e),
        F.call("plain", "late")
      ])

    r = attach(s, r, "B", d)
    r = attach(s, r, "B", e)

    r =
      F.model(s, r, d, "req-" <> d, [
        F.call("delegate", "grand-done"),
        F.call("plain", "done-tool")
      ])

    r = attach(s, r, d, "grand-done")

    r =
      F.model(
        s,
        r,
        "grand-done",
        "g-text",
        [%Part.Text{content: String.duplicate("\"\\\n", 250)}],
        false
      )

    r = F.op(s, r, "node_complete", %{"node_id" => "grand-done"})
    t = F.target(d, "req-" <> d, "grand-done")
    r = F.op(s, r, "call_wrap", t)

    raw =
      F.root(r)["tool_batches"][ToolEvidence.key(d, "req-" <> d)]["calls"]["grand-done"]["raw"]

    r = F.op(s, r, "call_settle", Map.merge(t, raw))
    r = F.settled(s, r, F.target(d, "req-" <> d, "done-tool"))
    r = F.op(s, r, "tool_resolution", F.target(d, "req-" <> d))
    r = F.op(s, r, "batch_consume", F.target(d, "req-" <> d))
    r = F.model(s, r, d, "d-text", [%Part.Text{content: String.duplicate("\"\\\n", 250)}], false)
    r = F.op(s, r, "node_complete", %{"node_id" => d})
    tool = if source == :effect, do: "plain", else: "delegate"
    r = F.model(s, r, e, "req-" <> e, [F.call(tool, "fatal"), F.call("delegate", "idle")])
    r = attach(s, r, e, "idle")
    r = wrap(s, r, "B", "late")

    r =
      if source == :effect do
        wrap(s, r, e, "fatal")
      else
        r = attach(s, r, e, "fatal")
        r = F.model(s, r, "fatal", "fatal-text", [%Part.Text{content: "child"}], false)
        r = F.op(s, r, "node_complete", %{"node_id" => "fatal"})
        F.op(s, r, "call_wrap", F.target(e, "req-" <> e, "fatal"))
      end

    source_rows = Process.get(:rows)

    before_fatal = r
    final = payload(e, "fatal", error()) |> Map.put("result", bounded_return("fatal", tool))
    r = F.op(s, r, "call_settle", final)

    assert Record.receipt_reserve(r["execution"]) ==
             Record.receipt_reserve(before_fatal["execution"]) - 1

    assert F.root(r)["scope"] === F.root(before_fatal)["scope"]

    for {key, batch} <- F.root(before_fatal)["tool_batches"], {id, call} <- batch["calls"] do
      assert F.root(r)["tool_batches"][key]["calls"][id]["raw"] === call["raw"]
    end

    assert {:error, _} =
             Store.transition(
               s,
               :agent,
               "conversation",
               r["revision"],
               F.worker(r, "finish", %{"elapsed_ms" => 0})
             )

    r = F.op(s, r, "call_settle", payload("B", "late"))
    before = r
    r = F.op(s, r, "finish", %{"elapsed_ms" => 29})
    assert r["execution"]["state"] == "failed"

    for id <- [d, "grand-done"],
        do: assert(F.root(r)["children"][id] === F.root(before)["children"][id])

    assert F.root(r)["children"][e]["status"] == "cancelled"
    assert F.root(r)["children"]["idle"]["status"] == "cancelled"

    if source == :child,
      do: assert(F.root(r)["children"]["fatal"] === F.root(before_fatal)["children"]["fatal"])

    assert F.root(r)["scope"] === F.root(before)["scope"]
    assert r["execution"]["effects"] === before["execution"]["effects"]
    assert F.root(r)["input"] == "root input"
    assert r["execution"]["progress"]["active_budget"]["remaining_ms"] == 59_971
    {:ok, r, source_rows, Process.get(:rows), s}
  catch
    {:rejected, _, _, _} = e -> e
  end

  defp boundary(kind) do
    {:ok, _, sources, _rows, _} = flow("independent-R", Record.max_bytes(), kind)
    {source_cmd, _, source} = Enum.max_by(sources, &elem(&1, 2))
    bound = source - byte_size(to_string(Record.max_bytes())) + byte_size(to_string(source))
    IO.inspect({kind, source_cmd["operation"], bound}, label: "source peak before fatal")

    observations =
      for {limit, ns} <- [
            {bound - 1, "independent-L"},
            {bound, "independent-E"},
            {bound + 1, "independent-H"}
          ] do
        result =
          case flow(ns, limit, kind) do
            {:rejected, cmd, {:error, :record_limit}, previous} ->
              {limit, cmd["operation"], cmd["payload"]["call_id"], previous["revision"],
               F.root(previous)["frontier"]["fatal"]}

            {:ok, r, _, _, _} ->
              {limit, r["execution"]["state"]}
          end

        IO.inspect(result, label: "boundary result")
        result
      end

    assert {negative, operation, _, _, nil} = hd(observations)
    assert negative == bound - 1
    assert operation == source_cmd["operation"]
    # Contract: admitted wrapper can confirm its bounded final fatal; no after-sink threshold.
    assert Enum.at(observations, 1) == {bound, "failed"}
    assert Enum.at(observations, 2) == {bound + 1, "failed"}
  end

  for {source, text} <- [{:effect, "\"\\\n"}, {:child, "漢é🌍"}, {:effect, "plain"}] do
    test "source±1 and roomy closure: #{source}/#{text}" do
      Process.put(:text, unquote(text))
      boundary(unquote(source))
    end
  end

  test "final control spends only its own exact JSON growth; raw, sibling and future slots remain" do
    rows =
      for {ns, error} <- [{"nil", nil}, {"error", error()}] do
        Process.put(:limit, Record.max_bytes())
        Process.put(:rows, [])
        s = Store.scoped({Store.ETS, __MODULE__}, ns)
        r = F.started(s)
        r = F.model(s, r, "B", "req-B", [F.call("plain", "one"), F.call("plain", "two")])
        r = wrap(s, r, "B", "one")
        r = wrap(s, r, "B", "two")
        before = r
        final = payload("B", "one", error) |> put_in(["control", "retry"], true)
        r = F.op(s, r, "call_settle", final)

        assert Record.receipt_reserve(r["execution"]) ==
                 Record.receipt_reserve(before["execution"]) - 1

        assert F.root(r)["scope"] === F.root(before)["scope"]
        key = ToolEvidence.key("B", "req-B")

        assert F.root(r)["tool_batches"][key]["calls"]["two"] ===
                 F.root(before)["tool_batches"][key]["calls"]["two"]

        assert F.root(r)["tool_batches"][key]["calls"]["one"]["raw"] ===
                 F.root(before)["tool_batches"][key]["calls"]["one"]["raw"]

        assert F.root(r)["frontier"] === F.root(before)["frontier"]
        assert Record.cleanup_reserve_bytes(r) >= 0
        next = F.op(s, r, "call_settle", payload("B", "two"))

        assert Record.receipt_reserve(next["execution"]) ==
                 Record.receipt_reserve(r["execution"]) - 1

        assert Record.cleanup_reserve_bytes(next) >= 0
        r
      end

    [nil_row, error_row] = rows

    assert Record.cleanup_reserve_bytes(nil_row) - Record.cleanup_reserve_bytes(error_row) ==
             4096 - 4

    assert byte_size(Jason.encode!(error_row)) - byte_size(Jason.encode!(nil_row)) == 4096 - 4 + 2
  end

  defp success_flow(ns, limit) do
    Process.put(:limit, limit)
    Process.put(:rows, [])
    s = Store.scoped({Store.ETS, __MODULE__}, ns)
    r = F.started(s)
    r = F.model(s, r, "B", "req-B", [F.call("delegate", "child"), F.call("plain", "effect")])
    r = attach(s, r, "B", "child")
    r = F.model(s, r, "child", "text", [%Part.Text{content: "child output"}], false)
    r = F.op(s, r, "node_complete", %{"node_id" => "child"})
    r = F.op(s, r, "call_wrap", F.target("B", "req-B", "child"))
    r = wrap(s, r, "B", "effect")
    sources = Process.get(:rows)
    before = r
    final = payload("B", "child") |> Map.put("result", bounded_return("child", "delegate"))
    r = F.op(s, r, "call_settle", final)

    assert Record.receipt_reserve(r["execution"]) ==
             Record.receipt_reserve(before["execution"]) - 1

    r = F.op(s, r, "call_settle", payload("B", "effect"))

    assert Record.receipt_reserve(r["execution"]) ==
             Record.receipt_reserve(before["execution"]) - 2

    settled = r
    r = F.op(s, r, "tool_resolution", F.target("B", "req-B"))

    assert Record.receipt_reserve(r["execution"]) ==
             Record.receipt_reserve(settled["execution"]) - 1

    r = F.op(s, r, "batch_consume", F.target("B", "req-B"))
    assert F.root(r)["children"]["B"]["frame"]["cursor"] == "request"
    assert F.root(r)["children"]["child"] === F.root(before)["children"]["child"]
    assert F.root(r)["scope"]["nodes"] === F.root(before)["scope"]["nodes"]
    assert is_nil(F.root(r)["frontier"]["fatal"])
    assert Record.cleanup_reserve_bytes(r) >= 0
    assert Record.receipt_reserve(r["execution"]) >= 0
    {:ok, r, sources}
  catch
    {:rejected, command, reason, previous} = rejected ->
      IO.inspect({command["operation"], reason, previous["revision"]},
        label: "successful source rejection"
      )

      rejected
  end

  test "successful child/effect wrappers retain capacity through consumption at source exact" do
    Process.put(:text, "漢é🌍")
    {:ok, _, sources} = success_flow("success-R", Record.max_bytes())
    {cmd, _, source} = Enum.max_by(sources, &elem(&1, 2))
    limit = source - byte_size(to_string(Record.max_bytes())) + byte_size(to_string(source))

    assert {:rejected, rejected, {:error, :record_limit}, _} =
             success_flow("success-L", limit - 1)

    assert rejected["operation"] == cmd["operation"]
    assert {:ok, _, _} = success_flow("success-E", limit)
    assert {:ok, _, _} = success_flow("success-H", limit + 1)
  end

  test "failed original-record certificate rejects hidden histories, sources and state forgery" do
    {:ok, r, _, _, s} = flow("independent-M", Record.max_bytes())
    root = F.root(r)

    {model_id, _} =
      Enum.find(r["execution"]["effects"], fn {_, e} -> e["intent"]["kind"] == "model" end)

    key = {s.namespace, :agent, "conversation"}

    mutations = [
      update_in(r, ["execution", "effects"], &Map.delete(&1, model_id)),
      put_in(
        r,
        [
          "execution",
          "effects",
          model_id,
          "intent",
          "payload",
          "request_data",
          "request_version"
        ],
        1
      ),
      put_in(r, ~w(execution progress runtime children idle status), "completed"),
      put_in(r, ~w(execution progress runtime children B snapshot message_history), "[]"),
      put_in(r, ~w(execution progress runtime scope nodes root requests), 0),
      put_in(r, ~w(execution progress runtime frontier fatal error message), "forged"),
      put_in(r, ["execution", "effects", model_id, "outcome", "status"], "unknown")
    ]

    for invalid <- mutations,
        do: assert({:error, :invalid_record} == Record.validate(invalid, key))

    assert map_size(root["children"]) == 5

    for op <- ~w(finish recover cancel expire frontier_open) do
      assert {:error, _} =
               Store.transition(
                 s,
                 :agent,
                 "conversation",
                 r["revision"],
                 F.worker(r, op, %{"elapsed_ms" => 0})
               )

      assert {:ok, ^r} = Store.load_record(s, :agent, "conversation")
    end

    assert {:error, :active_or_retained} =
             Store.transition(
               s,
               :agent,
               "conversation",
               r["revision"],
               F.command("delete", %{"before" => r["updated_at"]})
             )
  end
end
