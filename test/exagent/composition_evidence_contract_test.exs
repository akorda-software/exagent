defmodule ExAgent.CompositionEvidenceContractTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, ExecutionScope, Message, Store, Tool}
  alias ExAgent.Continuation.{Outcome, Record, Writer}
  alias ExAgent.Coordination.Composition
  alias ExAgent.Message.Part
  alias ExAgent.ContinuationNativeFixture.CountOutput
  alias ExAgent.CompositionEvidenceFixture.LargeOutput

  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, query), do: Store.ETS.scan_records(c.table, ns, query)

    def transition(c, key, revision, command) do
      fault_key =
        if command["operation"] == "outcome" and
             String.starts_with?(command["payload"]["effect_id"] || "", "tool-"),
           do: "tool_outcome",
           else: command["operation"]

      mode =
        Agent.get_and_update(c.fault, fn modes ->
          {Map.get(modes, fault_key), Map.delete(modes, fault_key)}
        end)

      if mode == :before do
        {:error, :before_commit}
      else
        result = Store.ETS.transition(c.table, key, revision, command)

        case result do
          {:ok, %{record: record}} -> send(c.owner, {:boundary, command["operation"], record})
          _ -> :ok
        end

        if mode == :after, do: {:error, :lost_ack}, else: result
      end
    end
  end

  defmodule Hook do
    use ExAgent.Capability
    defstruct [:mode]
    def before_tool_execute(%{mode: :veto}, _, _), do: raise("host veto")
    def before_tool_execute(_, _, call), do: call

    def after_tool_execute(%{mode: :transform}, _, _, {:ok, part}),
      do: {:ok, %{part | content: "transformed"}}

    def after_tool_execute(_, _, _, result), do: result
  end

  defmodule NoEncoderOutput do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:count, :integer)
    end
  end

  defmodule HugeDescriptor do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:value, :string)
    end

    def changeset(data, args),
      do:
        data
        |> Ecto.Changeset.cast(args, [:value])
        |> Ecto.Changeset.validate_inclusion(:value, [String.duplicate("d", 70_000)])
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    :ok
  end

  defp open(script, agent_opts, config_opts \\ []) do
    owner = self()
    id = "sequence-" <> Integer.to_string(System.unique_integer([:positive]))
    fault = start_supervised!({Agent, fn -> %{} end}, id: id)

    store =
      Store.scoped({FaultStore, %{table: __MODULE__, fault: fault, owner: owner}}, "evidence")

    model = %ExAgent.Models.Test{
      script:
        Enum.map(script, fn item ->
          fn _, _ ->
            send(owner, {:model_io, id})
            item
          end
        end)
    }

    agent = ExAgent.new(Keyword.put(agent_opts, :model, model))

    codec = %{
      dump: fn m -> {:ok, %{"index" => m.index}} end,
      load: fn m, data -> {:ok, %{m | index: data["index"]}} end
    }

    step = %{
      id: "A",
      agent: agent,
      model_codec: codec,
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"}
    }

    assert {:ok, definition} = Composition.new(id: id, version: "1", steps: [step])
    assert {:ok, scope} = ExecutionScope.start_structural("root", [])

    config =
      Map.merge(
        %{
          kind: :composition,
          composition: definition,
          store: store,
          id: id,
          definition: %{"id" => id, "version" => "1"},
          policy: %{"id" => "policy", "version" => "1"},
          durability: :ephemeral,
          expires_at: nil,
          lease_ms: 60_000
        },
        Map.new(config_opts)
      )

    # Explicit legacy-9 source; current producer-10 has separate runtime coverage.
    assert {:ok, writer, _} =
             ExAgent.LegacyStructuralFixture.open(
               %{run_id: "root", execution_scope: scope, input: "initial"},
               config
             )

    on_exit(fn ->
      Writer.stop(writer)
      ExecutionScope.stop(scope)
    end)

    %{
      store: store,
      writer: writer,
      scope: scope,
      definition: definition,
      config: config,
      id: id,
      fault: fault,
      agent: agent
    }
  end

  defp call(name \\ "effect", id \\ "call-1", args \\ %{}),
    do: %Part.ToolCall{tool_name: name, tool_call_id: id, args: args}

  defp tool(fun, name \\ "effect"),
    do: Tool.new(name: name, parameters_json_schema: %{"type" => "object"}, call: fun)

  defp run(c, opts \\ []), do: ExAgent.run_composition_step(c.writer, c.definition, "A", opts)

  defp saved(c) do
    assert {:ok, record} = Store.load_record(c.store, :agent, c.id)

    assert {:ok, ^record} =
             Record.decode(Jason.encode!(record), {c.store.namespace, :agent, c.id})

    record
  end

  defp restore_without_callbacks(c) do
    record = saved(c)
    reference = %{id: c.id, record_id: record["record_id"], revision: record["revision"]}
    [step] = c.definition.steps

    codec = %{
      dump: fn _ -> flunk("data-only dump") end,
      load: fn _, _ -> flunk("data-only load") end
    }

    agent = %{
      step.agent
      | model: %{step.agent.model | script: [fn -> flunk("data-only Model IO") end]}
    }

    definition = %{c.definition | steps: [%{step | model_codec: codec, agent: agent}]}
    config = Map.put(c.config, :on_writer, fn _ -> flunk("data-only registration") end)
    ExAgent.resume_composition_step(definition, reference, continuation: config)
  end

  defp boundaries(c, acc \\ []) do
    receive do
      {:boundary, operation, record} ->
        assert {:ok, ^record} =
                 Record.decode(Jason.encode!(record), {c.store.namespace, :agent, c.id})

        boundaries(c, [{operation, record} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  for order <- [[1, 2], [2, 1]] do
    test "parallel current/command remains coherent releasing #{inspect(order)}" do
      owner = self()

      tool =
        tool(fn _, %{"n" => n} ->
          send(owner, {:entered, n, self()})

          receive do
            :release -> :ok
          end

          send(owner, {:effect, n})
          {:ok, n}
        end)

      c =
        open(
          [
            {:tool_calls,
             [call("effect", "one", %{"n" => 1}), call("effect", "two", %{"n" => 2})]},
            "done"
          ],
          tools: [tool]
        )

      task = Task.async(fn -> run(c) end)
      assert_receive {:entered, 1, one}, 2_000
      assert_receive {:entered, 2, two}, 2_000
      record = saved(c)

      tools =
        Enum.filter(Map.values(record["execution"]["effects"]), &(&1["intent"]["kind"] == "tool"))

      assert length(tools) == 2
      assert Enum.all?(tools, &(&1["state"] == "running" and is_nil(&1["outcome"])))
      boundaries(c)

      [first, second] = unquote(order)
      pids = %{1 => one, 2 => two}
      send(pids[first], :release)
      assert_receive {:effect, ^first}
      assert_receive {:boundary, "outcome", raw}, 2_000

      assert Enum.any?(
               Map.values(raw["execution"]["effects"]),
               &(&1["intent"]["kind"] == "tool" and &1["outcome"]["data"]["phase"] == "raw")
             )

      assert {:ok, _} = Record.decode(Jason.encode!(raw), {c.store.namespace, :agent, c.id})
      send(pids[second], :release)
      assert {:ok, %{output: "done"}} = Task.await(task, 5_000)
      assert_receive {:effect, ^second}
      refute_receive {:effect, _}
      remaining = boundaries(c)

      assert Enum.any?(remaining, fn {_, record} ->
               phases =
                 for effect <- Map.values(record["execution"]["effects"]),
                     effect["intent"]["kind"] == "tool",
                     do: effect["outcome"]["data"]["phase"]

               "raw" in phases and "final" in phases
             end)
    end
  end

  for variant <- [:plain, :siblings, :multiple] do
    test "typed output #{variant} agrees with direct execution and has no sibling IO" do
      owner = self()
      out = call("final_result", "output", %{"count" => 7})

      calls =
        case unquote(variant) do
          :plain -> [out]
          :siblings -> [call(), out]
          :multiple -> [call(), out, call("final_result", "extra", %{"count" => 99})]
        end

      c =
        open([{:tool_calls, calls}],
          output_type: CountOutput,
          tools: [
            tool(fn _, _ ->
              send(owner, :sibling_io)
              {:ok, "bad"}
            end)
          ]
        )

      assert {:ok, %{output: %CountOutput{count: 7}}} = ExAgent.run(c.agent, "initial")
      assert {:ok, %{output: %CountOutput{count: 7}}} = run(c)
      refute_receive :sibling_io
      record = saved(c)
      root = record["execution"]["progress"]["runtime"]
      assert root["frame_version"] == 9
      assert map_size(root["output_resolutions"]) == 1
      assert map_size(record["execution"]["effects"]) == 1
      assert {:ok, totals} = ExecutionScope.snapshot(c.scope)
      assert totals.tool_calls == 0 and totals.request_count == 1
      assert "output_resolution" in Enum.map(boundaries(c), &elem(&1, 0))
    end
  end

  for exhausted <- [false, true] do
    test "invalid output with siblings #{if exhausted, do: "exhausts", else: "retries exactly once"}" do
      owner = self()
      invalid = {:tool_calls, [call("final_result", "same", %{"count" => 0}), call()]}
      valid = {:tool_calls, [call("final_result", "same", %{"count" => 7})]}

      c =
        open([invalid, valid],
          output_type: CountOutput,
          output_retries: if(unquote(exhausted), do: 0, else: 1),
          tools: [
            tool(fn _, _ ->
              send(owner, :sibling_io)
              {:ok, "bad"}
            end)
          ]
        )

      result = run(c)

      if unquote(exhausted),
        do:
          assert(
            {:error,
             %ExAgent.RunError{
               reason: {:unexpected_model_behavior, {:output_retries_exhausted, _}}
             }} = result
          ),
        else: assert({:ok, %{output: %CountOutput{count: 7}, run_step: 2}} = result)

      refute_receive :sibling_io
      root = saved(c)["execution"]["progress"]["runtime"]

      assert Enum.count(root["output_resolutions"], fn {_, e} -> e["decision"] == "retry" end) ==
               1

      assert map_size(root["output_resolutions"]) == if(unquote(exhausted), do: 1, else: 2)

      if unquote(exhausted) do
        :ok
      else
        record = saved(c)
        [id] = Map.keys(root["children"])

        bad =
          put_in(
            record,
            ["execution", "progress", "runtime", "children", id, "frame", "output_retries_used"],
            0
          )

        assert {:error, _} = Record.decode(Jason.encode!(bad), {c.store.namespace, :agent, c.id})
      end

      boundaries(c)
    end
  end

  test "text Retry without a call coexists with attested output retries" do
    c =
      open(
        [
          {:tool_calls, [call("final_result", "out", %{"count" => 0})]},
          "not structured",
          {:tool_calls, [call("final_result", "out", %{"count" => 7})]}
        ],
        output_type: CountOutput,
        output_retries: 2
      )

    assert {:ok, %{output: %CountOutput{count: 7}, run_step: 3}} = run(c)
    [child] = Map.values(saved(c)["execution"]["progress"]["runtime"]["children"])
    assert child["frame"]["output_retries_used"] == 2
    {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])

    assert Enum.any?(messages, fn
             %Message.Request{parts: parts} ->
               Enum.any?(parts, &match?(%Part.Retry{tool_call_id: nil}, &1))

             _ ->
               false
           end)

    boundaries(c)
  end

  test "reused function call IDs bind independently to each request and reject mixed evidence" do
    owner = self()

    c =
      open([{:tool_calls, [call()]}, {:tool_calls, [call()]}, "done"],
        tools: [
          tool(fn _, _ ->
            send(owner, :function_io)
            {:ok, "raw"}
          end)
        ]
      )

    assert {:ok, %{output: "done"}} = run(c)
    assert_receive :function_io
    assert_receive :function_io
    refute_receive :function_io
    record = saved(c)

    effects =
      Enum.filter(record["execution"]["effects"], fn {_, effect} ->
        effect["intent"]["kind"] == "tool"
      end)

    assert length(effects) == 2

    assert 2 ==
             effects
             |> Enum.map(fn {_, effect} -> effect["intent"]["payload"]["model_request_id"] end)
             |> Enum.uniq()
             |> length()

    [{id, _} | _] = effects

    for bad <- [
          put_in(
            record,
            ["execution", "effects", id, "intent", "payload", "model_request_id"],
            "unrelated"
          ),
          put_in(record, ["execution", "effects", id, "intent", "payload", "run_id"], "root"),
          put_in(
            record,
            ["execution", "effects", id, "intent", "payload", "schema_hash"],
            String.duplicate("0", 64)
          ),
          put_in(record, ["execution", "effects", id, "outcome", "data", "phase"], "raw")
        ] do
      assert {:error, _} = Record.decode(Jason.encode!(bad), {c.store.namespace, :agent, c.id})
    end

    boundaries(c)
  end

  for kind <- [:invalid_args, :unknown] do
    test "#{kind} is resolved before dispatch without fabricated tool IO" do
      owner = self()

      tool = %{
        tool(fn _, _ ->
          send(owner, :function_io)
          {:ok, "bad"}
        end)
        | parameters_json_schema: %{
            "type" => "object",
            "properties" => %{"n" => %{"type" => "integer"}},
            "required" => ["n"]
          }
      }

      requested =
        if unquote(kind) == :unknown,
          do: call("absent"),
          else: call("effect", "call", %{"n" => "bad"})

      c = open([{:tool_calls, [requested]}, "done"], tools: [tool])
      result = run(c)

      if unquote(kind) == :unknown,
        do: assert({:error, _} = result),
        else: assert({:ok, _} = result)

      refute_receive :function_io

      effects =
        Enum.filter(
          Map.values(saved(c)["execution"]["effects"]),
          &(&1["intent"]["kind"] == "tool")
        )

      assert [effect] = effects
      assert effect["intent"]["payload"]["phase"] == "pre_dispatch"
      assert effect["outcome"]["status"] == "validation_error"
      boundaries(c)
    end
  end

  test "real final_result function requires dispatch; output collision rejects before IO" do
    owner = self()

    fun =
      tool(
        fn _, _ ->
          send(owner, :function_io)
          {:ok, "real function"}
        end,
        "final_result"
      )

    c = open([{:tool_calls, [call("final_result")]}, "done"], tools: [fun])
    assert {:ok, %{output: "done"}} = run(c)
    assert_receive :function_io
    assert saved(c)["execution"]["progress"]["runtime"]["frame_version"] == 9
    boundaries(c)

    collision =
      open([{:tool_calls, [call("final_result")]}], tools: [fun], output_type: CountOutput)

    assert {:error, _} = run(collision)
    collision_id = collision.id
    refute_receive {:model_io, ^collision_id}
    refute_receive :function_io
    assert saved(collision)["execution"]["effects"] == %{}
  end

  test "output descriptor bound rejects preIO preserving only confirmed input" do
    c =
      open([{:tool_calls, [call("final_result", "out", %{"value" => "x"})]}],
        output_type: HugeDescriptor
      )

    assert {:error, %ExAgent.RunError{reason: :output_descriptor_too_large}} = run(c)
    id = c.id
    refute_receive {:model_io, ^id}
    assert {:ok, scope} = ExecutionScope.export_tree(c.scope)
    assert map_size(scope["nodes"]) == 2
    assert scope["operations"] == []
    assert Writer.pending(c.writer).token == nil
    assert saved(c)["execution"]["effects"] == %{}
  end

  test "nonportable validated output retains an attested omission without replay" do
    c =
      open([{:tool_calls, [call("final_result", "out", %{"count" => 7})]}],
        output_type: NoEncoderOutput
      )

    assert {:ok, %{output: %NoEncoderOutput{count: 7}}} = ExAgent.run(c.agent, "initial")
    assert {:error, _} = run(c)
    record = saved(c)
    root = record["execution"]["progress"]["runtime"]
    assert root["cursor"] == "completed"
    [entry] = Map.values(root["output_resolutions"])
    assert entry["result"] == nil and is_map(entry["result_omitted"])
    assert {:error, :omitted_payload_history} = run(c)
    assert {:error, {:composition_output_omitted, _}} = restore_without_callbacks(c)
    boundaries(c)
  end

  test "terminal capacity omission remains linked to its retained output attestation" do
    c =
      open(
        [
          {:tool_calls,
           [call("final_result", "out", %{"value" => String.duplicate("x", 100_000)})]}
        ],
        [output_type: LargeOutput],
        max_checkpoint_bytes: 256_000
      )

    assert {:error, _} = run(c)
    record = saved(c)
    root = record["execution"]["progress"]["runtime"]
    assert root["frame_version"] == 9
    assert root["cursor"] == "completed"
    [child] = Map.values(root["children"])
    assert is_map(child["result_omitted"]) and is_nil(child["result"])
    [entry] = Map.values(root["output_resolutions"])
    assert is_map(entry["result"]) and is_nil(entry["result_omitted"])
    assert Writer.pending(c.writer).token == nil
    assert {:error, {:composition_output_omitted, _}} = restore_without_callbacks(c)
    boundaries(c)
  end

  for mode <- [:before, :after], operation <- ["output_resolution", "step_output"] do
    test "#{operation} #{mode} ACK retry is data-only" do
      c =
        open([{:tool_calls, [call("final_result", "output", %{"count" => 7})]}],
          output_type: CountOutput
        )

      Agent.update(c.fault, &Map.put(&1, unquote(operation), unquote(mode)))
      assert {:error, _} = run(c)
      id = c.id
      assert_receive {:model_io, ^id}
      token = Writer.pending(c.writer).token
      assert token["command"]["operation"] == unquote(operation)
      assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
      assert {:ok, %{replayed: true}} = Continuation.retry_checkpoint(c.store, token)
      saved(c)

      case restore_without_callbacks(c) do
        {:error, :composition_not_ready} -> :ok
        {:ok, %{status: :completed}} -> assert unquote(operation) == "step_output"
      end

      refute_receive {:model_io, ^id}
      boundaries(c)
    end
  end

  for mode <- [:before, :after], operation <- ["tool_outcome", "finalize_call"] do
    test "#{operation} #{mode} ACK retries preserve known effects without IO" do
      owner = self()

      c =
        open([{:tool_calls, [call()]}, "done"],
          tools: [
            tool(fn _, _ ->
              send(owner, :function_io)
              {:ok, "raw"}
            end)
          ]
        )

      Agent.update(c.fault, &Map.put(&1, unquote(operation), unquote(mode)))
      assert {:error, _} = run(c)
      assert_receive :function_io
      token = Writer.pending(c.writer).token

      assert token["command"]["operation"] ==
               if(unquote(operation) == "tool_outcome", do: "outcome", else: unquote(operation))

      assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
      assert {:ok, %{replayed: true}} = Continuation.retry_checkpoint(c.store, token)
      saved(c)
      assert {:error, :composition_not_ready} = restore_without_callbacks(c)
      refute_receive :function_io
      boundaries(c)
    end
  end

  test "current writer tools before and after output Retry preserve independent provenance" do
    owner = self()

    c =
      open(
        [
          {:tool_calls, [call("effect", "reused")]},
          {:tool_calls, [call("final_result", "output-1", %{"count" => 0})]},
          {:tool_calls, [call("effect", "reused")]},
          {:tool_calls, [call("final_result", "output-1", %{"count" => 7})]}
        ],
        output_type: CountOutput,
        tools: [
          tool(fn _, _ ->
            send(owner, :mixed_effect)
            {:ok, "done"}
          end)
        ]
      )

    assert {:ok, %{output: %CountOutput{count: 7}, run_step: 4}} = run(c)
    assert_receive :mixed_effect
    assert_receive :mixed_effect
    refute_receive :mixed_effect
    record = saved(c)
    root = record["execution"]["progress"]["runtime"]
    assert root["frame_version"] == 9
    assert map_size(root["output_resolutions"]) == 2
    assert map_size(record["execution"]["effects"]) == 6
    assert {:ok, %{status: :completed}} = Writer.step_status(record, c.config, "A")
  end

  test "current writer reserves the exact child receipt horizon and rejects its invasion" do
    c =
      open([{:tool_calls, [call("final_result", "out", %{"count" => 7})]}],
        output_type: CountOutput
      )

    Agent.update(c.fault, &Map.put(&1, "output_resolution", :after))
    assert {:error, _} = run(c)
    record = saved(c)
    path = ["execution", "progress", "runtime"]
    assert get_in(record, path ++ ["frame_version"]) == 9
    [child] = Map.values(get_in(record, path ++ ["children"]))
    assert child["status"] == "running"

    frame5 =
      update_in(
        record,
        path,
        &(&1
          |> Map.drop(["output_resolutions", "authority", "tool_batches"])
          |> Map.put("frame_version", 5))
      )

    key = {c.store.namespace, :agent, c.id}
    assert :ok = Record.validate(frame5, key)
    assert Record.receipt_reserve(frame5["execution"]) == 5
    assert Record.receipt_reserve(record["execution"]) == 5
    assert Record.cleanup_reserve_bytes(record) == Record.cleanup_reserve_bytes(frame5)

    sample = record["receipts"] |> Map.values() |> hd()
    at_limit = 1024 - Record.receipt_reserve(record["execution"])
    assert at_limit == 1019

    exact = %{
      record
      | "receipts" => Map.new(1..at_limit, &{"receipt-#{&1}", sample}),
        "revision" => at_limit
    }

    assert :ok = Record.validate(exact, key)
    assert {:ok, _} = Record.encode(exact, key)

    over = %{
      exact
      | "receipts" => Map.put(exact["receipts"], "one-too-many", sample),
        "revision" => at_limit + 1
    }

    assert {:error, _} = Record.validate(over, key)
    assert {:error, _} = Record.encode(over, key)
    assert Writer.pending(c.writer).token["command"]["operation"] == "output_resolution"
  end

  test "current writer JSON fits exactly with child cleanup bytes and rejects plus one" do
    c =
      open([{:tool_calls, [call("final_result", "out", %{"count" => 7})]}],
        output_type: CountOutput
      )

    Agent.update(c.fault, &Map.put(&1, "output_resolution", :after))
    assert {:error, _} = run(c)
    record = saved(c)
    [id] = Map.keys(record["execution"]["progress"]["runtime"]["children"])
    path = ["execution", "progress", "runtime", "children", id, "snapshot", "metadata", "padding"]
    record = put_in(record, path, "")
    reserve = Record.cleanup_reserve_bytes(record)

    frame5 =
      update_in(
        record,
        ["execution", "progress", "runtime"],
        &(&1 |> Map.delete("output_resolutions") |> Map.put("frame_version", 5))
      )

    assert reserve == Record.cleanup_reserve_bytes(frame5)
    padding = Record.max_bytes() - byte_size(Jason.encode!(record)) - reserve
    exact = put_in(record, path, String.duplicate("x", padding))
    key = {c.store.namespace, :agent, c.id}

    assert byte_size(Jason.encode!(exact)) + Record.cleanup_reserve_bytes(exact) ==
             Record.max_bytes()

    assert {:ok, _} = Record.encode(exact, key)
    assert {:error, :record_limit} = Record.encode(update_in(exact, path, &(&1 <> "x")), key)
  end

  test "malformed output attestations reject without crashing the CAS boundary" do
    c =
      open([{:tool_calls, [call("final_result", "out", %{"count" => 7})]}],
        output_type: CountOutput
      )

    Agent.update(c.fault, &Map.put(&1, "output_resolution", :before))
    assert {:error, _} = run(c)
    token = Writer.pending(c.writer).token
    current = saved(c)
    [request] = Map.keys(token["command"]["payload"]["progress"]["runtime"]["output_resolutions"])

    for malformed <- [nil, 42, [], %{"run_id" => "wrong"}] do
      command =
        token["command"]
        |> put_in(["payload", "progress", "runtime", "output_resolutions", request], malformed)
        |> Map.put(
          "operation_id",
          "malformed-" <> Integer.to_string(System.unique_integer([:positive]))
        )

      assert {:error, _} = Store.transition(c.store, :agent, c.id, current["revision"], command)
      assert ^current = saved(c)
    end

    assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
  end

  test "output evidence mutations reject both real CAS and data-only decode" do
    c =
      open([{:tool_calls, [call("final_result", "output", %{"count" => 7}), call()]}],
        output_type: CountOutput
      )

    Agent.update(c.fault, &Map.put(&1, "step_output", :before))
    assert {:error, _} = run(c)
    token = Writer.pending(c.writer).token
    current = saved(c)
    [request] = Map.keys(current["execution"]["progress"]["runtime"]["output_resolutions"])
    command = token["command"]
    root_path = ["payload", "progress", "runtime"]

    mutations = [
      fn root -> put_in(root, ["output_resolutions", request, "call_id"], "wrong") end,
      fn root -> put_in(root, ["output_resolutions", request, "run_id"], "root") end,
      fn root ->
        put_in(root, ["output_resolutions", request, "descriptor", "allow_text"], "wrong")
      end,
      fn root -> mutate_resolution(root, request, 0) end,
      fn root -> mutate_resolution(root, request, 1) end
    ]

    for mutate <- mutations do
      changed =
        update_in(command, root_path, mutate)
        |> Map.put(
          "operation_id",
          "corrupt-" <> Integer.to_string(System.unique_integer([:positive]))
        )

      assert {:error, _} = Store.transition(c.store, :agent, c.id, current["revision"], changed)
      # Validate against an otherwise complete record, not merely CAS revision.
      complete = put_in(current, ["execution", "progress"], command["payload"]["progress"])
      complete = put_in(complete, ["execution", "state"], "completed")
      complete = update_in(complete, ["execution", "progress", "runtime"], mutate)

      assert {:error, _} =
               Record.decode(Jason.encode!(complete), {c.store.namespace, :agent, c.id})
    end

    assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
    record = saved(c)

    for mutate <- mutations do
      bad = update_in(record, ["execution", "progress", "runtime"], mutate)
      assert {:error, _} = Record.decode(Jason.encode!(bad), {c.store.namespace, :agent, c.id})
    end
  end

  defp mutate_resolution(root, request, index) do
    e = root["output_resolutions"][request]
    e = mutate_parts(e, index)
    {:ok, [%Message.Request{parts: parts}]} = Message.from_json(e["parts"])
    path = ["children", e["run_id"], "snapshot", "message_history"]
    {:ok, messages} = Message.from_json(get_in(root, path))
    messages = List.update_at(messages, -1, fn message -> %{message | parts: parts} end)

    root
    |> put_in(["output_resolutions", request], e)
    |> put_in(path, Message.to_json(messages))
  end

  defp mutate_parts(e, index) do
    {:ok, [%Message.Request{parts: parts}]} = Message.from_json(e["parts"])
    parts = List.update_at(parts, index, &%{&1 | content: "forged"})
    bytes = Message.to_json([%Message.Request{parts: parts}])
    {:ok, hash} = Outcome.hash(bytes)
    %{e | "parts" => bytes, "parts_hash" => hash}
  end

  for mode <- [:veto, :transform, :error, :retry, :timeout] do
    test "#{mode} retains dispatch versus pre-dispatch provenance" do
      owner = self()

      callback = fn _, _ ->
        send(owner, :function_io)

        case unquote(mode) do
          :error -> {:error, :expected}
          :retry -> {:retry, "try again"}
          :timeout -> Process.sleep(:infinity)
          _ -> {:ok, "raw"}
        end
      end

      c =
        open([{:tool_calls, [call()]}, "done"],
          tools: [tool(callback)],
          capabilities: [%Hook{mode: unquote(mode)}],
          tool_timeout: if(unquote(mode) == :timeout, do: 30, else: 5_000)
        )

      result = run(c)

      if unquote(mode) in [:transform, :retry],
        do: assert({:ok, _} = result),
        else: assert({:error, _} = result)

      if unquote(mode) == :veto,
        do: refute_receive(:function_io),
        else: assert_receive(:function_io)

      record = saved(c)

      effects =
        Enum.filter(Map.values(record["execution"]["effects"]), &(&1["intent"]["kind"] == "tool"))

      assert [effect] = effects

      assert effect["intent"]["payload"]["phase"] ==
               if(unquote(mode) == :veto, do: "pre_dispatch", else: "dispatch")

      if unquote(mode) == :transform do
        assert effect["outcome"]["data"]["raw_hash"] != effect["outcome"]["data"]["result_hash"]
      end

      boundaries(c)
    end
  end
end
