defmodule ExAgent.ToolEvidenceProducerTest do
  use ExUnit.Case, async: false
  alias ExAgent.{ExecutionScope, Message, Store, Tool}
  alias ExAgent.Continuation.{CompositionRestore, Record, ToolEvidence, Writer}
  alias ExAgent.Coordination.Composition

  defmodule Tap do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, q), do: Store.ETS.scan_records(c.table, ns, q)

    def transition(c, key, rev, command) do
      current =
        case Store.ETS.load_record(c.table, key) do
          {:ok, record} -> record
          _ -> nil
        end

      boundary =
        case command do
          %{
            "operation" => "outcome",
            "payload" => %{"outcome" => %{"data" => %{"runtime_outcome_version" => 1}}}
          } ->
            :raw

          %{"operation" => "finalize_call"} ->
            :final

          %{"operation" => "tool_resolution"} ->
            :control

          %{
            "operation" => "node_checkpoint",
            "payload" => %{"progress" => %{"runtime" => %{"tool_batches" => batches}}}
          }
          when map_size(batches) > 0 ->
            :batch

          %{
            "operation" => "begin_effect",
            "payload" => %{"intent" => %{"kind" => "model", "payload" => %{"step" => 2}}}
          } ->
            :next_intent

          _ ->
            nil
        end

      result =
        if c.fault == {boundary, :before},
          do: {:error, :test_ack_lost},
          else: Store.ETS.transition(c.table, key, rev, command)

      send(c.owner, {:transition, key, rev, command, current, result})
      if c.fault == {boundary, :after}, do: {:error, :test_ack_lost}, else: result
    end
  end

  defmodule After do
    use ExAgent.Capability
    defstruct [:owner, :fail, :delay]

    def after_tool_execute(cap, _ctx, _call, result) do
      send(cap.owner, :after_hook)
      if cap.delay, do: Process.sleep(cap.delay)
      if cap.fail, do: raise("private-configuration-sentinel"), else: result
    end
  end

  defmodule Switch do
    use ExAgent.Capability

    def before_model_request(_cap, state) do
      if state.run_step >= 2 do
        tools =
          Enum.map(state.params.function_tools, fn tool ->
            %{
              tool
              | max_retries: 3,
                parameters_json_schema: %{"type" => "object", "description" => "request-two"}
            }
          end)

        %{state | params: %{state.params | function_tools: tools}}
      else
        state
      end
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    :ok
  end

  defp fixture(usage, opts \\ []) do
    owner = opts[:event_owner] || self()

    tool =
      Tool.new(
        name: "effect",
        max_retries: 1,
        parameters_json_schema: %{"type" => "object"},
        call: fn _, args ->
          send(owner, {:effect, args})

          if opts[:call] do
            opts[:call].(args)
          else
            if is_nil(usage), do: {:ok, "done"}, else: {:ok, "done", usage}
          end
        end
      )

    call = %Message.Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}

    response =
      Message.new_response(opts[:calls] || [call],
        usage: %Message.Usage{input_tokens: 1, output_tokens: 1}
      )

    model = %ExAgent.Models.Test{
      script:
        opts[:script] ||
          [
            response,
            fn _, _ ->
              send(owner, :next_model)

              Message.new_response([%Message.Part.Text{content: "done"}],
                usage: %Message.Usage{input_tokens: 1, output_tokens: 1}
              )
            end
          ]
    }

    step = %{
      id: "A",
      agent:
        ExAgent.new(
          model: model,
          tools: [tool],
          tool_timeout: opts[:tool_timeout] || 30_000,
          capabilities:
            [%After{owner: owner, fail: opts[:hook_fatal], delay: opts[:hook_delay]}] ++
              (opts[:capabilities] || [])
        ),
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, d -> {:ok, %{m | index: d["index"]}} end
      },
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"}
    }

    {:ok, definition} = Composition.new(id: "evidence", version: "1", steps: [step])

    store =
      Store.scoped({Tap, %{table: __MODULE__, owner: owner, fault: opts[:fault]}}, "evidence")

    {:ok, scope} = ExecutionScope.start_structural("root", [])

    config = %{
      kind: :composition,
      composition: definition,
      store: store,
      id: "evidence",
      definition: %{"id" => "evidence", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 60_000,
      max_checkpoint_bytes: opts[:max_checkpoint_bytes] || Record.max_bytes()
    }

    # Explicit legacy-9 source; current producer-10 has separate runtime coverage.
    {:ok, writer, _} =
      ExAgent.LegacyStructuralFixture.open(
        %{run_id: "root", execution_scope: scope, input: "probe"},
        config
      )

    send(owner, {:writer_processes, writer, scope.pid})

    try do
      result =
        ExAgent.run_composition_step(
          writer,
          definition,
          "A",
          Keyword.take(opts, [:tool_timeout, :max_checkpoint_bytes, :permissions])
        )

      send(owner, {:pending_token, Writer.pending(writer).token})

      {:ok, record} = Store.load_record(store, :agent, "evidence")
      {result, record, store}
    after
      Writer.stop(writer)
      ExecutionScope.stop(scope)
    end
  end

  @tag :causal
  test "authentic new root retains independent accounting and ordered control" do
    {result, record, store} = fixture(%Message.Usage{input_tokens: 7, output_tokens: 11})
    assert {:ok, _} = result
    root = record["execution"]["progress"]["runtime"]
    assert root["frame_version"] == 9
    [batch] = Map.values(root["tool_batches"])
    [observation] = Map.values(batch["observations"])
    assert observation["presence"] == "usage"
    assert observation["usage"]["input_tokens"] == 7
    assert observation["application"]["status"] == "contributed"
    assert length(batch["resolution"]["calls"]) == 1
    assert ToolEvidence.evidence?(record)

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})

    assert {:ok, :completed} = CompositionRestore.boundary(record)
  end

  for kind <- [nil, :unknown, :zero, :partial, :cost] do
    @kind kind
    test "qualified observation #{@kind} preserves input and external ancestor projections" do
      usage =
        case @kind do
          nil ->
            nil

          :unknown ->
            Message.Usage.qualify(nil)

          :zero ->
            %Message.Usage{input_tokens: 0, output_tokens: 0}

          :partial ->
            Message.Usage.partial(%Message.Usage{input_tokens: 3, output_tokens: 4})

          :cost ->
            Message.Usage.with_cost(
              %Message.Usage{input_tokens: 3, output_tokens: 4},
              17,
              "estimator",
              true
            )
        end

      assert {{:ok, _}, record, store} = fixture(usage)
      [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])
      [obs] = Map.values(batch["observations"])
      assert obs["presence"] == if(is_nil(usage), do: "nil", else: "usage")

      if usage do
        assert obs["usage"] == Message.Usage.to_map(usage)
        assert map_size(obs["application"]["ancestors"]) == 2

        assert obs["application"]["complete"] ==
                 (is_integer(usage.input_tokens) and is_integer(usage.output_tokens))

        for {_, projection} <- obs["application"]["ancestors"] do
          assert projection["accounting"]["cost"]["cents"] == nil
        end
      end

      assert {:ok, ^record} =
               Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})

      assert_receive :after_hook
      assert_receive :next_model
    end
  end

  for kind <- [:invalid, :omitted, :nonportable, :oversized] do
    @kind kind
    test "negative #{@kind} is durable before application and remains partial after refresh" do
      usage =
        case @kind do
          :invalid ->
            %Message.Usage{input_tokens: -1, output_tokens: 2}

          :omitted ->
            %Message.Usage{
              input_tokens: 3,
              output_tokens: 4,
              payload_omitted: ExAgent.Retention.marker(:usage, 9000, 4096)
            }

          :nonportable ->
            %Message.Usage{
              input_tokens: 3,
              output_tokens: 4,
              details: %{"private" => fn -> :secret end}
            }

          :oversized ->
            %Message.Usage{
              input_tokens: 3,
              output_tokens: 4,
              details: %{"large" => String.duplicate("x", 10000)}
            }
        end

      assert {{:error, error}, record, store} = fixture(usage)
      assert error.partial.usage_status == :partial
      assert error.partial.cost_cents == nil
      root = record["execution"]["progress"]["runtime"]
      [batch] = Map.values(root["tool_batches"])
      [obs] = Map.values(batch["observations"])
      assert obs["presence"] == "omitted"
      assert obs["application"]["status"] == "rejected"
      assert obs["application"]["error"]["omitted"]
      [child] = Map.values(root["children"])
      assert child["snapshot"]["usage"]["accounting"]["availability"]["input"] == "partial"
      assert Enum.all?(root["scope"]["operations"], &match?(["model", _], &1["id"]))
      assert batch["resolution"]["calls"] |> hd() |> Map.fetch!("error")

      assert {:ok, ^record} =
               Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})

      refute_receive :after_hook
      refute_receive :next_model

      [id] = Map.keys(root["children"])

      false_complete =
        record
        |> put_in(
          [
            "execution",
            "progress",
            "runtime",
            "children",
            id,
            "snapshot",
            "usage",
            "accounting",
            "availability",
            "input"
          ],
          "available"
        )
        |> put_in(
          [
            "execution",
            "progress",
            "runtime",
            "children",
            id,
            "snapshot",
            "usage",
            "accounting",
            "availability",
            "output"
          ],
          "available"
        )

      assert {:error, _} =
               Record.decode(Jason.encode!(false_complete), {store.namespace, :agent, "evidence"})
    end
  end

  test "Scope input receipts are idempotent for nil/rejected/contributed and conflicting input never replaces an operation" do
    owner = self()

    {:ok, root} =
      ExecutionScope.start_structural("root",
        estimate_cost: fn _, _ ->
          send(owner, :external_reprice)
          17
        end
      )

    {:ok, leaf} = ExecutionScope.join(root, "leaf", %ExAgent.Models.Test{}, [])

    try do
      :ok = ExecutionScope.admit_request(leaf, "request", %ExAgent.Models.Test{})
      :ok = ExecutionScope.admit_tools(leaf, "request", 3)

      for {id, usage} <- [
            {"nil", nil},
            {"bad", %Message.Usage{input_tokens: -1, output_tokens: nil}},
            {"ok", %Message.Usage{input_tokens: 2, output_tokens: 3}}
          ] do
        key = {"request", id}
        first = ExecutionScope.observe_tool(leaf, key, usage)
        assert {:ok, _, _} = first
        assert ^first = ExecutionScope.observe_tool(leaf, key, usage)

        assert {:error, :tool_accounting_conflict} =
                 ExecutionScope.observe_tool(leaf, key, %Message.Usage{
                   input_tokens: 9,
                   output_tokens: 9
                 })
      end

      assert {:ok, tree} = ExecutionScope.export_tree(root)
      assert [op] = Enum.filter(tree["operations"], &match?(["tool", _, _], &1["id"]))
      assert op["usage"]["input_tokens"] == 2
      assert {:ok, %{usage_status: :partial}} = ExecutionScope.snapshot(leaf)
      assert {:ok, %{usage_status: :partial}} = ExecutionScope.snapshot(root)
      refute_receive :external_reprice
    after
      ExecutionScope.stop(root)
    end
  end

  test "hook fatal after a succeeded raw return persists error without leaking exception data" do
    assert {{:error, _}, record, store} =
             fixture(%Message.Usage{input_tokens: 3, output_tokens: 4}, hook_fatal: true)

    [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])
    [control] = batch["resolution"]["calls"]
    assert control["error"]["code"] == "tool_hook_failed"
    refute Jason.encode!(record) =~ "private-configuration-sentinel"

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})

    refute_receive :next_model
  end

  for order <- [[:retry, :ok], [:ok, :retry], [:retry, :retry, :ok]] do
    @order order
    test "control follows Model call order #{inspect(order)}, not finish order" do
      calls =
        Enum.with_index(@order)
        |> Enum.map(fn {mode, i} ->
          %Message.Part.ToolCall{
            tool_name: "effect",
            tool_call_id: "call-#{i}",
            args: %{"mode" => Atom.to_string(mode), "delay" => (length(@order) - i) * 10}
          }
        end)

      callback = fn args ->
        Process.sleep(args["delay"])
        if args["mode"] == "retry", do: {:retry, "correct"}, else: {:ok, "done"}
      end

      {result, record, store} = fixture(nil, calls: calls, call: callback)
      [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])

      assert Enum.map(batch["resolution"]["calls"], & &1["retry"]) ==
               Enum.map(@order, &(&1 == :retry))

      if @order == [:retry, :retry, :ok],
        do: assert(match?({:error, _}, result)),
        else: assert(match?({:ok, _}, result))

      [child] = Map.values(record["execution"]["progress"]["runtime"]["children"])

      assert child["frame"]["tool_retries"] ==
               if(@order == [:ok, :retry], do: %{"effect" => 1}, else: %{})

      assert {:ok, ^record} =
               Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})
    end
  end

  test "rejected accounting retains accepted concurrent sibling accounting and quiesces" do
    calls =
      Enum.map(
        ["bad", "good"],
        &%Message.Part.ToolCall{tool_name: "effect", tool_call_id: &1, args: %{"mode" => &1}}
      )

    callback = fn args ->
      if args["mode"] == "good", do: Process.sleep(30)

      {:ok, "done",
       %Message.Usage{
         input_tokens: if(args["mode"] == "good", do: 7, else: -1),
         output_tokens: 11
       }}
    end

    assert {{:error, error}, record, store} = fixture(nil, calls: calls, call: callback)
    assert error.partial.usage_status == :partial
    root = record["execution"]["progress"]["runtime"]
    [batch] = Map.values(root["tool_batches"])

    assert Enum.sort(Enum.map(batch["observations"], fn {_, o} -> o["application"]["status"] end)) ==
             ["contributed", "rejected"]

    assert length(batch["resolution"]["calls"]) == 2
    assert [op] = Enum.filter(root["scope"]["operations"], &match?(["tool", _, _], &1["id"]))
    assert op["usage"]["input_tokens"] == 7

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})

    assert_receive :after_hook
    refute_receive :after_hook
    refute_receive :next_model
  end

  defp transitions(acc \\ []) do
    receive do
      {:transition, key, rev, command, current, result} ->
        transitions([{key, rev, command, current, result} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "pre-dispatch denial is explicit nil evidence, not a tool return or contribution" do
    assert {{:ok, _}, record, store} =
             fixture(nil, permissions: ExAgent.Permissions.new!(default: :deny))

    [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])
    assert [ToolEvidence.pre_dispatch()] == Map.values(batch["observations"])

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})

    refute_receive {:effect, _}
  end

  test "reused call IDs and historical schemas bind to their own request limits" do
    call = %Message.Part.ToolCall{tool_name: "effect", tool_call_id: "same", args: %{}}
    response = Message.new_response([call])

    assert {{:ok, _}, record, store} =
             fixture(%Message.Usage{input_tokens: 7, output_tokens: 11},
               script: [response, response, "done"],
               capabilities: [Switch]
             )

    root = record["execution"]["progress"]["runtime"]
    batches = Map.values(root["tool_batches"])
    assert length(batches) == 2
    assert Enum.sort(Enum.map(batches, & &1["limits"]["effect"]["max_retries"])) == [1, 3]
    assert length(Enum.uniq(Enum.map(batches, & &1["limits"]["effect"]["schema_hash"]))) == 2
    assert length(Enum.uniq(Enum.flat_map(batches, &Map.keys(&1["observations"])))) == 2

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})
  end

  test "portable controls enforce exact fields and codec bounds without serializing live errors" do
    valid = ToolEvidence.reservation_error()
    assert byte_size(Jason.encode!(valid)) == 4096
    assert ToolEvidence.error?(valid)

    refute ToolEvidence.error?(
             put_in(valid, ["details", "reservation"], valid["details"]["reservation"] <> "x")
           )

    refute ToolEvidence.error?(%{valid | "message" => String.duplicate("x", 513)})
    refute ToolEvidence.error?(Map.put(valid, "exception", "private"))
    refute ToolEvidence.error?(Map.delete(valid, "omitted"))
    refute ToolEvidence.error?(%{valid | "code" => "new_unsupported_code"})
    safe = ToolEvidence.error({:tool_hook_failed, "effect", fn -> :private end})
    assert ToolEvidence.error?(safe)
    assert safe["details"] == nil
  end

  test "qualification expansion is a durable omission, never an unrecorded helper error" do
    usage = %Message.Usage{
      input_tokens: 1,
      output_tokens: 1,
      details: %{"large" => String.duplicate("x", 3500)}
    }

    assert ExAgent.Retention.bytes(usage) < ExAgent.Retention.usage_bytes()
    assert {{:error, error}, record, store} = fixture(usage)
    assert error.partial.usage_status == :partial
    [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])
    [obs] = Map.values(batch["observations"])
    assert obs["application"]["status"] == "rejected"

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})
  end

  test "batch-wide reservation rejects before every concurrent effect" do
    calls =
      Enum.map(
        1..20,
        &%Message.Part.ToolCall{tool_name: "effect", tool_call_id: "call-#{&1}", args: %{}}
      )

    assert {{:error, _}, record, _} = fixture(nil, calls: calls, max_checkpoint_bytes: 100_000)
    refute_receive {:effect, _}

    assert Enum.all?(record["execution"]["effects"], fn {_, effect} ->
             effect["intent"]["kind"] == "model"
           end)
  end

  test "pending batch reserves control plus every not-yet-dispatched call receipt" do
    assert {{:error, _}, record, _} = fixture(nil, fault: {:batch, :after})

    {_, _, _, before, _} =
      Enum.find(transitions(), fn {_, _, c, _, _} -> c["operation"] == "node_checkpoint" end)

    assert Record.receipt_reserve(record["execution"]) ==
             Record.receipt_reserve(before["execution"]) + 4

    [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])
    assert batch["observations"] == %{} and is_nil(batch["resolution"])
    refute_receive {:effect, _}
  end

  test "timeout after raw preserves accepted accounting and a fatal control even for succeeded status" do
    assert {{:error, _}, record, store} =
             fixture(%Message.Usage{input_tokens: 7, output_tokens: 11},
               hook_delay: 500,
               tool_timeout: 100
             )

    [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])
    [obs] = Map.values(batch["observations"])
    assert obs["application"]["status"] == "contributed"
    [control] = batch["resolution"]["calls"]
    assert control["error"]["code"] == "tool_execution_failed"

    assert record["execution"]["effects"][control["effect_id"]]["outcome"]["status"] ==
             "succeeded"

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})

    refute_receive :next_model
  end

  test "timeout without raw retains uncertainty without fabricating a nil observation or resolution" do
    callback = fn _ ->
      Process.sleep(500)
      {:ok, "late"}
    end

    assert {{:error, _}, record, store} = fixture(nil, call: callback, tool_timeout: 100)
    [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])
    assert batch["observations"] == %{} and is_nil(batch["resolution"])

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})

    refute_receive :next_model
  end

  test "owner death after raw retains evidence and terminates owned Writer and Scope" do
    parent = self()

    task =
      Task.async(fn ->
        fixture(%Message.Usage{input_tokens: 7, output_tokens: 11},
          event_owner: parent,
          hook_delay: 5000
        )
      end)

    assert_receive {:writer_processes, writer, scope}, 1000
    writer_monitor = Process.monitor(writer)
    scope_monitor = Process.monitor(scope)
    assert_receive :after_hook, 1000
    Task.shutdown(task, :brutal_kill)
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, _}, 1000
    assert_receive {:DOWN, ^scope_monitor, :process, ^scope, _}, 1000
    key = {"evidence", :agent, "evidence"}
    assert {:ok, record} = Store.ETS.load_record(__MODULE__, key)
    [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])
    assert map_size(batch["observations"]) == 1 and is_nil(batch["resolution"])
    [effect] = Map.keys(batch["observations"])
    assert record["execution"]["effects"][effect]["outcome"]["data"]["phase"] == "raw"
    assert {:ok, ^record} = Record.decode(Jason.encode!(record), key)
  end

  for boundary <- [:raw, :final, :control] do
    @boundary boundary
    test "#{boundary} record has exact codec and cleanup limits and receipt horizon" do
      assert {{:error, _}, record, store} =
               fixture(%Message.Usage{input_tokens: 7, output_tokens: 11},
                 fault: {@boundary, :after}
               )

      key = {store.namespace, :agent, "evidence"}
      [id] = Map.keys(record["execution"]["progress"]["runtime"]["children"])

      path = [
        "execution",
        "progress",
        "runtime",
        "children",
        id,
        "snapshot",
        "metadata",
        "padding"
      ]

      padded = put_in(record, path, "")

      count =
        Record.max_bytes() - byte_size(Jason.encode!(padded)) -
          Record.cleanup_reserve_bytes(padded)

      exact = put_in(padded, path, String.duplicate("x", count))

      assert byte_size(Jason.encode!(exact)) + Record.cleanup_reserve_bytes(exact) ==
               Record.max_bytes()

      assert {:ok, _} = Record.encode(exact, key)
      assert {:ok, _} = Record.encode(put_in(padded, path, String.duplicate("x", count - 1)), key)

      assert {:error, :record_limit} =
               Record.encode(put_in(padded, path, String.duplicate("x", count + 1)), key)

      reserve = Record.receipt_reserve(record["execution"])
      sample = record["receipts"] |> Map.values() |> hd()
      receipt_count = 1024 - reserve

      exact = %{
        record
        | "revision" => receipt_count,
          "receipts" => Map.new(1..receipt_count, &{"receipt-#{&1}", sample})
      }

      assert :ok = Record.validate(exact, key)

      assert {:error, _} =
               Record.validate(
                 %{
                   exact
                   | "revision" => receipt_count + 1,
                     "receipts" => Map.put(exact["receipts"], "extra", sample)
                 },
                 key
               )
    end

    test "#{boundary} pending token uses the exact public codec boundary before real CAS" do
      assert {{:error, _}, current, store} =
               fixture(%Message.Usage{input_tokens: 7, output_tokens: 11},
                 fault: {@boundary, :before}
               )

      assert_receive {:pending_token, token}
      assert is_map(token)
      raw_store = Store.scoped({Store.ETS, __MODULE__}, store.namespace)
      [id] = Map.keys(token["command"]["payload"]["progress"]["runtime"]["children"])

      path = [
        "command",
        "payload",
        "progress",
        "runtime",
        "children",
        id,
        "snapshot",
        "metadata",
        "padding"
      ]

      base = put_in(token, path, "")
      padding = Record.max_bytes() - ExAgent.Retention.bytes(base)
      exact = put_in(base, path, String.duplicate("x", padding))
      assert ExAgent.Retention.bytes(exact) == Record.max_bytes()
      # At/below the token boundary the real CAS is reached and rejects the
      # oversized/altered progress. One byte above must reject the token itself.
      for candidate <- [put_in(base, path, String.duplicate("x", padding - 1)), exact] do
        assert {:error, reason} = ExAgent.Continuation.retry_checkpoint(raw_store, candidate)
        refute reason == :invalid_checkpoint_token
        assert {:ok, ^current} = Store.load_record(store, :agent, "evidence")
      end

      assert {:error, :invalid_checkpoint_token} =
               ExAgent.Continuation.retry_checkpoint(
                 raw_store,
                 put_in(base, path, String.duplicate("x", padding + 1))
               )

      assert {:ok, %{replayed: false}} = ExAgent.Continuation.retry_checkpoint(raw_store, token)
      assert {:ok, %{replayed: true}} = ExAgent.Continuation.retry_checkpoint(raw_store, token)
    end
  end

  test "confirmed Frame8 tools with final control select consumption after legitimate recovery" do
    assert {{:error, _}, record, store} = fixture(nil, fault: {:control, :after})
    key = {store.namespace, :agent, "evidence"}

    command = %{
      "record_id" => record["record_id"],
      "operation" => "recover",
      "operation_id" => "recover",
      "actor_id" => "admin",
      "payload" => %{}
    }

    assert {:ok, %{record: recovered}} =
             ExAgent.Continuation.Transition.apply(
               record,
               key,
               record["revision"],
               command,
               record["execution"]["lease_until"] + 1
             )

    assert {:ok, {:confirmed_tool_history, {:confirmed_tool_batch, selection}, 0}} =
             CompositionRestore.boundary(recovered)

    assert selection.count == 1
    assert selection.fatal == nil

    assert [%Message.Part.ToolReturn{content: "done", usage: nil, status: :succeeded}] =
             selection.parts
  end

  @tag :tmp_dir
  test "authentic Frame8 accounting and control decode in a fresh VM without execution", c do
    assert {{:ok, _}, record, _} = fixture(%Message.Usage{input_tokens: 7, output_tokens: 11})

    path =
      Path.join(c.tmp_dir, "tool-evidence-vm-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(record))
    on_exit(fn -> File.rm(path) end)

    code =
      "[path] = System.argv(); bytes = File.read!(path); r = Jason.decode!(bytes); [ns, _, id] = r[\"key\"]; {:ok, ^r} = ExAgent.Continuation.Record.decode(bytes, {ns, :agent, id}); true = ExAgent.Continuation.ToolEvidence.evidence?(r); IO.puts(\"FRAME8_DECODE_ONLY\")"

    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))
    args = ["--erl", "+S 2:2"] ++ Enum.flat_map(paths, &["-pa", &1]) ++ ["-e", code, path]
    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "FRAME8_DECODE_ONLY"
  end

  test "authentic historical Frame7 tool bytes retain their reader and transition semantics" do
    dir = "test/fixtures/continuation/frame7_evidence"
    bytes = File.read!(Path.join(dir, "frame7-tools-current.json"))
    record = Jason.decode!(bytes)
    [ns, _, id] = record["key"]
    key = {ns, :agent, id}
    assert {:ok, ^record} = Record.decode(bytes, key)
    command = File.read!(Path.join(dir, "frame7-tools-output-command.json")) |> Jason.decode!()

    assert {:ok, %{record: next}} =
             ExAgent.Continuation.Transition.apply(
               record,
               key,
               record["revision"],
               command,
               record["updated_at"]
             )

    assert next["execution"]["progress"]["runtime"]["frame_version"] == 7
    refute Map.has_key?(next["execution"]["progress"]["runtime"], "tool_batches")
  end

  test "authentic historical Frame7 text resumes through Writer without relabeling its lifetime" do
    bytes = File.read!("test/fixtures/continuation/frame7_evidence/frame7-text-outcome.json")
    record = Jason.decode!(bytes)
    [ns, _, id] = record["key"]
    key = {ns, :agent, id}
    assert {:ok, ^record} = Record.decode(bytes, key)
    {:ok, physical} = Record.key(key)
    :ets.insert(__MODULE__, {physical, bytes})
    store = Store.scoped({Store.ETS, __MODULE__}, ns)

    assert {:ok, %{record: recovered}} =
             ExAgent.Continuation.recover(store, id,
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "recover-legacy",
               actor: "administrator",
               authorize: fn actor, _, _ -> {:ok, actor} end
             )

    step = %{
      id: "A",
      agent: ExAgent.new(model: %ExAgent.Models.Test{script: []}),
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, d -> {:ok, %{m | index: d["index"]}} end
      },
      input: fn input, _ -> {:ok, input} end,
      input_version: "1",
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"}
    }

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [step])
    reference = %{id: id, record_id: recovered["record_id"], revision: recovered["revision"]}

    continuation = %{
      store: store,
      id: id,
      definition: %{"id" => "sequence", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      expires_at: nil,
      durability: :ephemeral,
      lease_ms: 60_000
    }

    assert {:ok, _} =
             ExAgent.resume_composition_step(definition, reference, continuation: continuation)

    assert {:ok, saved} = Store.load_record(store, :agent, id)
    assert saved["execution"]["progress"]["runtime"]["frame_version"] == 7
    refute Map.has_key?(saved["execution"]["progress"]["runtime"], "tool_batches")
  end

  for boundary <- [:raw, :final, :control, :next_intent], phase <- [:before, :after] do
    @boundary boundary
    @phase phase
    test "ACK #{@phase} #{@boundary} retains an authentic decodable boundary with no repeated effect" do
      assert {{:error, _}, record, store} =
               fixture(%Message.Usage{input_tokens: 7, output_tokens: 11},
                 fault: {@boundary, @phase}
               )

      assert_receive {:effect, _}
      refute_receive {:effect, _}

      assert {:ok, ^record} =
               Record.decode(Jason.encode!(record), {store.namespace, :agent, "evidence"})

      [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])

      if @boundary == :raw and @phase == :before do
        assert batch["observations"] == %{}
      else
        assert map_size(batch["observations"]) == 1
      end

      if (@boundary == :control and @phase == :after) or @boundary == :next_intent,
        do: assert(batch["resolution"]),
        else: assert(is_nil(batch["resolution"]))

      if @boundary == :raw, do: refute_receive(:after_hook)
      refute_receive :next_model
    end
  end

  for mutation <- [
        :delete_observation,
        :delete_both,
        :usage,
        :quality,
        :source,
        :terminal,
        :complete,
        :ancestors,
        :control_hash,
        :control_order,
        :counter,
        :limit
      ] do
    @mutation mutation
    test "decode and real CAS reject #{@mutation} without replacing the saved row" do
      assert {{:error, _}, original, store} =
               fixture(%Message.Usage{input_tokens: 7, output_tokens: 11},
                 fault: {:control, :before}
               )

      {key, rev, command, current, _} =
        Enum.find(transitions(), fn {_, _, c, _, _} -> c["operation"] == "tool_resolution" end)

      assert current == original
      root = command["payload"]["progress"]["runtime"]
      [batch_key] = Map.keys(root["tool_batches"])
      batch = root["tool_batches"][batch_key]
      [effect] = Map.keys(batch["observations"])
      obs_path = ["tool_batches", batch_key, "observations", effect]

      root =
        case @mutation do
          :delete_observation ->
            put_in(root, ["tool_batches", batch_key, "observations"], %{})

          :delete_both ->
            root
            |> put_in(["tool_batches", batch_key, "observations"], %{})
            |> update_in(
              ["scope", "operations"],
              &Enum.reject(&1, fn op -> match?(["tool", _, _], op["id"]) end)
            )
            |> then(&ExAgent.Continuation.Frame.with_scope(&1, &1["scope"]))

          :usage ->
            put_in(root, obs_path ++ ["usage", "input_tokens"], 99)

          :quality ->
            put_in(root, obs_path ++ ["usage", "accounting", "quality"], "normalized")

          :source ->
            put_in(root, obs_path ++ ["usage", "accounting", "source"], "req_llm")

          :terminal ->
            update_in(
              root,
              ["scope", "operations"],
              &Enum.map(&1, fn op ->
                if match?(["tool", _, _], op["id"]),
                  do: put_in(op, ["terminal_usage", "input_tokens"], 99),
                  else: op
              end)
            )

          :complete ->
            put_in(root, obs_path ++ ["application", "complete"], false)

          :ancestors ->
            put_in(root, obs_path ++ ["application", "ancestors"], %{})

          :control_hash ->
            update_in(root, ["tool_batches", batch_key, "resolution", "calls"], fn [call] ->
              [%{call | "result_hash" => String.duplicate("0", 64)}]
            end)

          :control_order ->
            update_in(root, ["tool_batches", batch_key, "resolution", "calls"], &(&1 ++ &1))

          :counter ->
            put_in(root, ["children", batch["run_id"], "frame", "tool_retries"], %{"effect" => 17})

          :limit ->
            put_in(root, ["tool_batches", batch_key, "limits", "effect", "max_retries"], 50)
        end

      bad = put_in(command, ["payload", "progress", "runtime"], root)

      if @mutation != :limit do
        candidate = put_in(current, ["execution", "progress", "runtime"], root)
        assert {:error, _} = Record.decode(Jason.encode!(candidate), key)
      end

      assert {:error, _} = Store.ETS.transition(__MODULE__, key, rev, bad)
      assert {:ok, ^current} = Store.load_record(store, :agent, "evidence")

      assert {:ok, %{replayed: false, record: saved}} =
               Store.ETS.transition(__MODULE__, key, rev, command)

      assert {:ok, %{replayed: true, record: ^saved}} =
               Store.ETS.transition(__MODULE__, key, rev, command)

      assert {:error, :conflict} =
               Store.ETS.transition(__MODULE__, key, rev, %{command | "operation_id" => "other"})
    end
  end
end
