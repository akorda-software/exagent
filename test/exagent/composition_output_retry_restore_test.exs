defmodule ExAgent.CompositionOutputRetryRestoreTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, ExecutionScope, Message, Store}
  alias ExAgent.Continuation.{Record, Writer}
  alias ExAgent.Coordination.Composition
  alias ExAgent.CompositionOutputRetryFixture.{Output, LargeOutput}

  defmodule ChangedOutput do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:count, :string)
    end
  end

  defmodule NoEncoder do
    use Ecto.Schema
    @primary_key false
    embedded_schema do
      field(:count, :integer)
    end
  end

  defmodule SchemaTrap do
    def __schema__(_), do: raise("historical schema reflection")
    def changeset(_, _), do: raise("historical validation")
  end

  defmodule Hooks do
    use ExAgent.Capability
    defstruct [:owner, :fail, :historic_descriptor]

    def before_model_request(%{fail: :block_pre} = cap, state) do
      send(cap.owner, {:preintent, self(), state.execution_scope.pid})
      receive do: (:continue -> state)
    end

    def before_model_request(%{historic_descriptor: true}, state) do
      tools =
        Enum.map(state.params.output_tools, fn tool ->
          description = String.trim_leading(tool.description || "", "historical:")

          %{
            tool
            | description:
                if(state.run_step < 4, do: "historical:" <> description, else: description)
          }
        end)

      %{state | params: %{state.params | output_tools: tools}}
    end

    def before_model_request(_, state), do: state

    def after_model_request(cap, state) do
      send(cap.owner, {:after_model, state.run_step})
      if cap.fail == true, do: raise("new response hook failed"), else: state
    end
  end

  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, k), do: Store.ETS.load_record(c.table, k)
    def scan_records(c, n, q), do: Store.ETS.scan_records(c.table, n, q)

    def transition(c, k, r, command) do
      op = command["operation"]
      send(c.owner, {:operation, op})
      if op == "claim", do: send(c.owner, {:claim_writer, self()})
      fault = Agent.get(c.fault, & &1)

      fault =
        case fault do
          :unavailable ->
            if op == "outcome" and
                 get_in(command, ["payload", "outcome", "data", "state_available"]) == false,
               do: {op, :after},
               else: nil

          {:resolution, target, side} ->
            entries = get_in(command, ["payload", "progress", "runtime", "output_resolutions"])

            if op == "output_resolution" and map_size(entries) == target,
              do: {op, side},
              else: nil

          other ->
            other
        end

      if fault == :barrier and op == "claim" do
        send(c.owner, {:claim_waiting, self()})
        receive do: (:commit -> :ok)
      end

      if fault == {op, :before} do
        {:error, :ack_lost}
      else
        result = Store.ETS.transition(c.table, k, r, command)
        if fault == {op, :after}, do: {:error, :ack_lost}, else: result
      end
    end
  end

  setup c do
    start_supervised!({Store.ETS, table: __MODULE__})
    owner = self()
    Process.put(:output_retry_observer, owner)
    prefix = c[:prefix] || if(c[:chain], do: [:invalid, :text, :invalid], else: [])
    target = 1 + Enum.count(prefix, &(&1 == :invalid))

    fault =
      start_supervised!(
        {Agent,
         fn ->
           if c[:unavailable] do
             :unavailable
           else
             if c[:stop_operation],
               do: {c[:stop_operation], c[:ack] || :after},
               else: {:resolution, target, c[:ack] || :after}
           end
         end}
      )

    store = Store.scoped({FaultStore, %{table: __MODULE__, fault: fault, owner: owner}}, "retry")

    model = %ExAgent.Models.Test{
      script:
        Enum.map(prefix, fn kind ->
          fn _, _ ->
            send(owner, {:historical_model, kind})

            if kind == :text do
              Message.new_response([%Message.Part.Text{content: "not structured"}],
                finish_reason: :stop
              )
            else
              calls = if kind == :tool, do: [], else: [call("first", %{"count" => "invalid"})]

              Message.new_response(
                calls ++
                  [
                    %Message.Part.ToolCall{
                      tool_call_id: "sibling",
                      tool_name: "sibling",
                      args: %{}
                    }
                  ],
                finish_reason: :tool_calls,
                usage: %Message.Usage{input_tokens: 3, output_tokens: 2}
              )
            end
          end
        end) ++
          [
            fn _, _ ->
              send(owner, :model1)

              calls = [call("first", c[:first_args] || %{"count" => c[:first] || "invalid"})]

              calls =
                if c[:siblings],
                  do:
                    [
                      %Message.Part.ToolCall{
                        tool_call_id: "sibling",
                        tool_name: "sibling",
                        args: %{}
                      }
                      | calls
                    ] ++ [call("extra", %{"count" => 99})],
                  else: calls

              Message.new_response(calls,
                finish_reason: :tool_calls,
                usage: %Message.Usage{input_tokens: 3, output_tokens: 2}
              )
            end,
            fn _, _ ->
              send(owner, :model2)

              if c[:block_model] do
                send(owner, {:model_waiting, self()})
                receive do: (:continue -> :ok)
              end

              calls =
                if c[:second_tool],
                  do: [
                    %Message.Part.ToolCall{
                      tool_call_id: "new-sibling",
                      tool_name: "sibling",
                      args: %{}
                    }
                  ],
                  else: [call("second", %{"count" => c[:second] || 9})]

              Message.new_response(calls,
                finish_reason: :tool_calls,
                usage: %Message.Usage{input_tokens: 5, output_tokens: 4}
              )
            end,
            fn _, _ ->
              send(owner, :model3)

              Message.new_response([call("third", %{"count" => 10})],
                finish_reason: :tool_calls,
                usage: %Message.Usage{input_tokens: 5, output_tokens: 4}
              )
            end
          ]
    }

    model =
      if c[:bound],
        do:
          struct(ExAgent.CompositionOutputRetryFixture.Model,
            script: model.script,
            observer: owner
          ),
        else: model

    step = %{
      id: "A",
      agent:
        ExAgent.new(
          model: model,
          output_type: c[:output_type] || Output,
          tools: [
            ExAgent.Tool.new(
              name: "sibling",
              parameters_json_schema: %{type: "object"},
              call: fn _, _ ->
                send(owner, :sibling_effect)
                if c[:executed_prefix], do: "done", else: raise("sibling executed")
              end
            )
          ],
          capabilities: [%Hooks{owner: owner, historic_descriptor: c[:historic_descriptor]}],
          output_retries: c[:retries] || 1 + length(prefix),
          max_steps: c[:steps] || 2 + length(prefix),
          usage_limits: %ExAgent.UsageLimits{request_limit: c[:requests] || 2 + length(prefix)}
        ),
      model_codec: %{
        dump: fn m ->
          if c[:unavailable] == true and m.index == length(prefix) + 1,
            do: {:error, :model_data_unavailable},
            else: {:ok, %{"index" => m.index}}
        end,
        load: fn m, d ->
          send(owner, :codec)
          {:ok, %{m | index: d["index"]}}
        end
      },
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"}
    }

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [step])

    {:ok, scope} =
      ExecutionScope.start_structural(
        "root",
        Keyword.merge(
          [
            estimate_cost: fn _, _ -> 7 end,
            usage_limits: %ExAgent.UsageLimits{request_limit: c[:root_requests]}
          ],
          c[:original_root] || []
        )
      )

    config = %{
      kind: :composition,
      composition: definition,
      store: store,
      id: "sequence",
      definition: %{"id" => "sequence", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      active_time_limit_ms: c[:budget],
      max_checkpoint_bytes: c[:checkpoint_limit] || 8_388_608,
      lease_ms: 1_000
    }

    # Explicit legacy-9 source; current producer-10 has separate runtime coverage.
    {:ok, writer, _} =
      ExAgent.LegacyStructuralFixture.open(
        %{run_id: "root", execution_scope: scope, input: "original"},
        config
      )

    assert {:error, %ExAgent.RunError{reason: {:continuation_checkpoint_failed, :ack_lost}}} =
             ExAgent.run_composition_step(
               writer,
               definition,
               "A",
               Keyword.merge([estimate_cost: fn _ -> 3 end], c[:original_leaf] || [])
             )

    token = Writer.pending(writer).token
    Writer.stop(writer)
    ExecutionScope.stop(scope)
    {:ok, record} = Store.load_record(store, :agent, "sequence")
    {:ok, bytes} = Record.encode(record, {store.namespace, :agent, "sequence"})
    {:ok, ^record} = Record.decode(bytes, {store.namespace, :agent, "sequence"})
    Agent.update(fault, fn _ -> nil end)

    unless c[:unrecovered] do
      Process.sleep(
        max(0, record["execution"]["lease_until"] - System.system_time(:millisecond) + 1)
      )
    end

    ready =
      if c[:unrecovered] do
        record
      else
        assert {:ok, %{record: recovered}} =
                 Continuation.recover(store, "sequence",
                   record_id: record["record_id"],
                   revision: record["revision"],
                   operation_id: "recover",
                   actor: "admin",
                   authorize: fn a, _, _ -> {:ok, a} end
                 )

        recovered
      end

    drain()

    %{
      store: store,
      definition: definition,
      record: ready,
      fault: fault,
      token: token,
      config: %{config | lease_ms: 60_000},
      reference: %{id: "sequence", record_id: ready["record_id"], revision: ready["revision"]}
    }
  end

  defp call(id, args),
    do: %Message.Part.ToolCall{tool_call_id: id, tool_name: "final_result", args: args}

  defp drain do
    receive do
      _ -> drain()
    after
      0 -> :ok
    end
  end

  defp resume(c, opts \\ []),
    do:
      ExAgent.resume_composition_step(
        c.definition,
        c.reference,
        Keyword.merge(
          [
            continuation: c.config,
            estimate_cost: fn _ -> 5 end,
            root_options: [estimate_cost: fn _, _ -> 11 end]
          ],
          opts
        )
      )

  test "consumes first retry and admits a NEW request in the existing loop", c do
    Process.put(:output_retry_trap, :historical)
    assert {:ok, result} = resume(c)
    assert result.output.count == 9
    empty = %{}
    assert_receive {:changeset, ^empty}
    refute_receive {:changeset, ^empty}, 0
    refute_receive {:changeset, %{"count" => "invalid"}}, 0
    assert_receive {:changeset, %{"count" => 9}}
    assert_receive :model2
    refute_receive :model1, 0
    {:ok, final} = Store.load_record(c.store, :agent, "sequence")
    assert final["execution"]["state"] == "completed"
    frame = final["execution"]["progress"]["runtime"]
    [child] = Map.values(frame["children"])
    assert child["frame"]["output_retries_used"] == 1
    assert length(frame["scope"]["operations"]) == 2
    [old] = Map.values(c.record["execution"]["progress"]["runtime"]["output_resolutions"])

    {:ok, [_, _, %Message.Request{parts: parts}, _, _]} =
      Message.from_json(child["snapshot"]["message_history"])

    assert Message.to_json([%Message.Request{parts: parts}]) == old["parts"]
  end

  defp with_agent(c, fun) do
    [step] = c.definition.steps
    %{c | definition: %{c.definition | steps: [%{step | agent: fun.(step.agent)}]}}
  end

  defp stored(c) do
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    record
  end

  defp no_new_io do
    refute_receive :model1, 0
    refute_receive :model2, 0
    refute_receive :sibling_effect, 0
    refute_receive {:after_model, _}, 0
    refute_receive {:historical_model, _}, 0
  end

  defp recover_again(c, record) do
    Process.sleep(
      max(0, record["execution"]["lease_until"] - System.system_time(:millisecond) + 1)
    )

    assert {:ok, %{record: ready}} =
             Continuation.recover(c.store, "sequence",
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "recover-#{record["revision"]}",
               actor: "admin",
               authorize: fn a, _, _ -> {:ok, a} end
             )

    %{c | record: ready, reference: %{c.reference | revision: ready["revision"]}}
  end

  @tag siblings: true
  test "siblings retain exact order and never execute", c do
    assert {:ok, _} = resume(c)
    [entry] = Map.values(c.record["execution"]["progress"]["runtime"]["output_resolutions"])
    {:ok, [%Message.Request{parts: parts}]} = Message.from_json(entry["parts"])
    assert Enum.map(parts, & &1.tool_call_id) == ["first", "extra", "sibling"]
    [child] = Map.values(stored(c)["execution"]["progress"]["runtime"]["children"])

    {:ok, [_, _, %Message.Request{parts: actual}, _, _]} =
      Message.from_json(child["snapshot"]["message_history"])

    assert actual == parts
    refute_receive :sibling_effect, 0
  end

  for chain <- [false, true] do
    @tag chain: chain
    test "chain=#{chain}: schema change fails after claim before new IO", c do
      assert {:error, :continuation_output_changed} =
               resume(with_agent(c, &%{&1 | output_type: ChangedOutput}))

      assert stored(c)["execution"]["state"] == "claimed"
      assert_receive :codec
      no_new_io()
    end
  end

  for chain <- [false, true] do
    @tag chain: chain
    test "chain=#{chain}: reflection exception cleans up writer and scope", c do
      Process.put(:output_retry_trap, :empty)
      {:monitored_by, before} = Process.info(self(), :monitored_by)
      assert {:error, :continuation_output_changed} = resume(c)
      assert_receive {:claim_writer, writer}
      refute Process.alive?(writer)
      assert_receive {:schema_monitors, monitors}
      owned = monitors -- before
      assert length(owned) >= 2
      assert Enum.all?(owned, &(not Process.alive?(&1)))
      no_new_io()
    end
  end

  test "new args are validated and fail guard no longer suppresses future returns", c do
    owner = self()
    c = with_agent(c, &%{&1 | capabilities: [%Hooks{owner: owner, fail: true}]})
    assert {:error, %ExAgent.RunError{partial: partial}} = resume(c)
    assert_receive :model2
    assert_receive {:after_model, 2}

    assert Enum.any?(partial.messages, fn
             %Message.Request{parts: parts} ->
               Enum.any?(
                 parts,
                 &match?(
                   %Message.Part.ToolReturn{tool_call_id: "second", status: :not_executed},
                   &1
                 )
               )

             _ ->
               false
           end)
  end

  test "new validation trap is active", c do
    Process.put(:output_retry_trap, :new)
    assert {:error, %ExAgent.RunError{}} = resume(c)
    assert_receive {:changeset, %{"count" => 9}}
    assert_receive :model2
  end

  for chain <- [false, true] do
    @tag chain: chain
    test "chain=#{chain}: refs and profiles reject data-only before claim", c do
      [step] = c.definition.steps

      changes =
        for key <- [:definition, :policy, :model_ref, :output_ref],
            do: Map.update!(step, key, &Map.put(&1, "version", "2"))

      changes =
        changes ++
          [
            %{step | agent: %{step.agent | output_type: :text}},
            %{step | agent: %{step.agent | output_mode: :native}}
          ]

      for changed <- changes do
        assert {:error, _} = resume(%{c | definition: %{c.definition | steps: [changed]}})
        assert stored(c) == c.record
      end

      refute_receive :codec, 0
      refute_receive {:changeset, _}, 0
      no_new_io()
    end
  end

  for chain <- [false, true] do
    @tag chain: chain
    test "chain=#{chain}: two claimants race through CAS; only winner configures schema and requests",
         c do
      Agent.update(c.fault, fn _ -> :barrier end)
      owner = self()

      tasks =
        for _ <- 1..2,
            do:
              Task.async(fn ->
                Process.put(:output_retry_observer, owner)
                resume(c)
              end)

      assert_receive {:claim_waiting, one}, 5_000
      assert_receive {:claim_waiting, two}, 5_000
      refute_receive :codec, 0
      refute_receive {:changeset, _}, 0
      send(one, :commit)
      send(two, :commit)
      results = Enum.map(tasks, &Task.await(&1, 10_000))
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, _}, &1)) == 1
      empty = %{}
      assert_receive {:changeset, ^empty}
      refute_receive {:changeset, ^empty}, 0
      assert_receive :model2
      refute_receive :model2, 0
    end
  end

  for source <- [:original, :current], limit <- [:requests, :steps, :retries] do
    @tag [
      {if(source == :original, do: limit, else: :unused), if(limit == :retries, do: 0, else: 1)}
    ]
    test "#{source} #{limit} admission remains restrictive", c do
      c =
        if unquote(source) == :current do
          with_agent(c, fn a ->
            case unquote(limit) do
              :requests -> %{a | usage_limits: %ExAgent.UsageLimits{request_limit: 1}}
              :steps -> %{a | max_steps: 1}
              :retries -> %{a | output_retries: 0}
            end
          end)
        else
          c
        end

      assert {:error, %ExAgent.RunError{reason: reason}} = resume(c)

      if unquote(limit) == :retries do
        assert {:unexpected_model_behavior, {:output_retries_exhausted, content}} = reason
        [entry] = Map.values(c.record["execution"]["progress"]["runtime"]["output_resolutions"])
        {:ok, [%Message.Request{parts: [retry]}]} = Message.from_json(entry["parts"])
        assert content == retry.content
      end

      no_new_io()
      assert map_size(stored(c)["execution"]["effects"]) == 1
    end
  end

  test "historical root and leaf prices unchanged; new request uses new estimators", c do
    assert {:ok, result} = resume(c)
    assert result.request_count == 2
    assert result.cost_cents == 8
    old = c.record["execution"]["progress"]["runtime"]["scope"]["operations"]
    frame = stored(c)["execution"]["progress"]["runtime"]
    [leaf] = Map.keys(frame["children"])
    operations = frame["scope"]["operations"]
    assert Enum.all?(old, &(&1 in operations))
    [new] = operations -- old
    assert new["ancestors"]["root"]["accounting"]["cost"]["cents"] == 11
    assert new["ancestors"][leaf]["accounting"]["cost"]["cents"] == 5
  end

  for chain <- [false, true],
      op <- ["claim", "begin_effect", "outcome", "output_resolution", "step_output"],
      side <- [:before, :after] do
    @tag chain: chain
    test "chain=#{chain}: #{op} ACK #{side}: retry persists data only and later restore remains bounded",
         c do
      Agent.update(c.fault, fn _ -> {unquote(op), unquote(side)} end)
      result = resume(c, continuation: %{c.config | lease_ms: 1_000})

      token =
        case result do
          {:error, {:composition_claim_failed, _, token}} -> token
          {:error, %ExAgent.RunError{partial: partial}} -> partial.continuation_checkpoint
        end

      assert is_map(token)
      Agent.update(c.fault, fn _ -> nil end)
      drain()
      token = token |> Jason.encode!() |> Jason.decode!()
      assert {:ok, %{record: record}} = Continuation.retry_checkpoint(c.store, token)
      assert {:ok, %{replayed: true}} = Continuation.retry_checkpoint(c.store, token)
      no_new_io()
      refute_receive :codec, 0
      refute_receive {:changeset, _}, 0
      ref = %{c.reference | revision: record["revision"]}

      if unquote(op) == "step_output" do
        assert {:ok, %{output: %{"count" => 9}}} = resume(%{c | reference: ref})
      else
        assert {:error, :composition_not_ready} = resume(%{c | reference: ref})
      end

      if unquote(op) == "begin_effect" do
        frame = record["execution"]["progress"]["runtime"]
        [child] = Map.values(frame["children"])
        assert child["frame"]["output_retries_used"] == if(c[:chain], do: 4, else: 1)
        assert child["frame"]["model_request_id"] != hd(Map.keys(frame["output_resolutions"]))
        assert map_size(record["execution"]["effects"]) == if(c[:chain], do: 5, else: 2)
      end

      if unquote(op) == "output_resolution" do
        recovered = recover_again(c, record)
        assert {:ok, %{output: %{"count" => 9}}} = resume(recovered)
        no_new_io()
        refute_receive {:changeset, _}, 0
      end

      if unquote(op) in ["begin_effect", "outcome"] do
        recovered = recover_again(c, record)
        assert {:error, reason} = resume(recovered)
        assert reason in [:composition_not_ready, :unsupported_composition_boundary]
        no_new_io()
        refute_receive :codec, 0
      end
    end
  end

  test "expired deadline and too-small checkpoint reject preclaim", c do
    assert {:error, :deadline_exceeded} =
             resume(c, deadline: System.monotonic_time(:millisecond) - 1)

    assert {:error, :checkpoint_limit} =
             resume(c, continuation: %{c.config | max_checkpoint_bytes: 1})

    assert stored(c) == c.record
    no_new_io()
  end

  @tag budget: 1_000
  test "abandoned active budget is not refunded", c do
    assert {:error, :active_budget_exhausted} =
             resume(c, continuation: %{c.config | active_time_limit_ms: 100_000})

    no_new_io()
  end

  test "caller cannot select or override private attestation/cache", c do
    assert {:ok, %{output: %Output{count: 9}}} =
             resume(c,
               continuation_output_retry: %{},
               continuation_output_config: {:text, [], true, nil},
               continuation_output_success: %{"result" => "injected"}
             )

    assert_receive :model2
  end

  for {chain, first, requests, reflection} <- [
        {false, nil, 2, 1},
        {true, nil, 5, 1},
        {true, 7, 4, 0}
      ] do
    @tag chain: chain, first: first
    test "chain=#{chain} first=#{first}: fresh OS BEAM consumes real JSON with historical callbacks zero",
         c do
      path = Path.join("/tmp/opencode", "output-retry-#{System.unique_integer([:positive])}.json")
      {:ok, bytes} = Record.encode(c.record, {c.store.namespace, :agent, "sequence"})
      File.write!(path, bytes)
      on_exit(fn -> File.rm(path) end)
      paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

      args =
        ["--erl", "+S 2:2"] ++
          Enum.flat_map(paths, &["-pa", &1]) ++
          ["test/support/composition_output_retry_vm.exs", path]

      {output, status} =
        System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)

      assert status == 0, output

      assert output =~
               "NEW_VM_RETRY_COMPLETED historical=0 reflection=#{unquote(reflection)} new_validation=#{unquote(reflection)} requests=#{unquote(requests)}"

      no_new_io()
    end
  end

  for chain <- [false, true], delta <- [0, -1] do
    @tag chain: chain
    test "chain=#{chain}: history consumption exact #{delta} bytes and protection before append",
         c do
      frame = c.record["execution"]["progress"]["runtime"]
      [child] = Map.values(frame["children"])
      entry = frame["output_resolutions"][child["frame"]["model_request_id"]]
      {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])
      {:ok, [%Message.Request{parts: parts}]} = Message.from_json(entry["parts"])

      full =
        messages ++
          [
            %Message.Request{
              parts: parts,
              run_id: child["frame"]["run_id"],
              timestamp: DateTime.utc_now()
            }
          ]

      # Stop at request2 intent to isolate consumption, before a larger response2.
      Agent.update(c.fault, fn _ -> {"begin_effect", :before} end)

      assert {:error, %ExAgent.RunError{partial: partial}} =
               resume(c, max_history_bytes: :erlang.external_size(full) + unquote(delta))

      if unquote(delta) == 0 do
        assert is_map(partial.continuation_checkpoint)
        assert length(partial.messages) == length(messages) + 1
      else
        assert partial.continuation_checkpoint == nil
        assert partial.messages == messages
      end

      assert stored(c)["execution"]["progress"]["runtime"]["output_resolutions"] ==
               frame["output_resolutions"]

      no_new_io()
    end
  end

  for chain <- [false, true] do
    @tag chain: chain
    test "chain=#{chain}: receipt and JSON+cleanup exact/+1 limits derive from actual new request projection",
         c do
      Agent.update(c.fault, fn _ -> {"begin_effect", :after} end)
      assert {:error, %ExAgent.RunError{}} = resume(c)
      record = stored(c)
      key = {c.store.namespace, :agent, "sequence"}
      reserve = Record.receipt_reserve(record["execution"])
      sample = record["receipts"] |> Map.values() |> hd()
      count = 1024 - reserve

      exact = %{
        record
        | "receipts" => Map.new(1..count, &{"r#{&1}", sample}),
          "revision" => count
      }

      assert {:ok, _} = Record.encode(exact, key)

      assert {:error, _} =
               Record.encode(
                 %{
                   exact
                   | "receipts" => Map.put(exact["receipts"], "over", sample),
                     "revision" => count + 1
                 },
                 key
               )

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

      record = put_in(record, path, "")

      remaining =
        Record.max_bytes() - byte_size(Jason.encode!(record)) -
          Record.cleanup_reserve_bytes(record)

      exact = put_in(record, path, String.duplicate("x", remaining))
      assert {:ok, _} = Record.encode(exact, key)
      assert {:error, :record_limit} = Record.encode(update_in(exact, path, &(&1 <> "x")), key)
      no_new_io()
    end
  end

  for side <- [:before, :after] do
    @tag ack: side, unrecovered: true
    test "first resolution ACK #{side} uses exact data-only token before recovery", c do
      assert {:error, :composition_not_ready} = resume(c)
      assert {:ok, %{record: confirmed}} = Continuation.retry_checkpoint(c.store, c.token)
      assert {:ok, %{replayed: true}} = Continuation.retry_checkpoint(c.store, c.token)
      no_new_io()
      refute_receive :codec, 0
      refute_receive {:changeset, _}, 0
      assert {:ok, %{output: %Output{count: 9}}} = resume(recover_again(c, confirmed))
    end
  end

  @tag ack: :before
  test "missing attestation cannot replay historical validation", c do
    assert {:error, :unsupported_composition_boundary} = resume(c)
    refute_receive :codec, 0
    refute_receive {:changeset, _}, 0
    no_new_io()
  end

  for chain <- [false, true] do
    @tag chain: chain
    test "chain=#{chain}: owner killed before intent leaves original attestation and releases runtime processes",
         c do
      parent = self()
      c = with_agent(c, &%{&1 | capabilities: [%Hooks{owner: parent, fail: :block_pre}]})

      {pid, monitor} =
        spawn_monitor(fn -> resume(c, continuation: %{c.config | lease_ms: 1_000}) end)

      assert_receive {:preintent, ^pid, scope}, 5_000
      assert_receive {:claim_writer, writer}
      wm = Process.monitor(writer)
      sm = Process.monitor(scope)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
      assert_receive {:DOWN, ^wm, :process, ^writer, _}, 5_000
      assert_receive {:DOWN, ^sm, :process, ^scope, _}, 5_000
      record = stored(c)

      assert record["execution"]["progress"]["runtime"] ==
               c.record["execution"]["progress"]["runtime"]

      assert map_size(record["execution"]["effects"]) == if(c[:chain], do: 4, else: 1)
      no_new_io()
      c = recover_again(c, record) |> with_agent(&%{&1 | capabilities: []})
      assert {:ok, _} = resume(c)
      assert_receive :model2
      refute_receive :model1, 0
    end
  end

  @tag second: "invalid"
  test "interrupted second retry restores and exhausts its original counter", c do
    Agent.update(c.fault, fn _ -> {"output_resolution", :after} end)
    assert {:error, %ExAgent.RunError{}} = resume(c, continuation: %{c.config | lease_ms: 1_000})
    record = stored(c)
    assert map_size(record["execution"]["progress"]["runtime"]["output_resolutions"]) == 2
    Agent.update(c.fault, fn _ -> nil end)
    c = recover_again(c, record)
    drain()

    assert {:error,
            %ExAgent.RunError{
              reason: {:unexpected_model_behavior, {:output_retries_exhausted, _}}
            }} = resume(c)

    no_new_io()
    assert_receive :codec
  end

  test "codec load failure cannot admit another request", c do
    [step] = c.definition.steps
    codec = %{step.model_codec | load: fn _, _ -> {:error, :codec_failed} end}
    c = %{c | definition: %{c.definition | steps: [%{step | model_codec: codec}]}}
    assert {:error, _} = resume(c)
    no_new_io()
  end

  for chain <- [false, true], location <- [:host, :codec] do
    @tag bound: true, chain: chain
    test "chain=#{chain}: Model binding mismatch #{location} retains pre/post-codec checks", c do
      [step] = c.definition.steps

      step =
        if unquote(location) == :host do
          %{
            step
            | agent: %{step.agent | model: %{step.agent.model | binding: %{"version" => "2"}}}
          }
        else
          %{
            step
            | model_codec: %{
                step.model_codec
                | load: fn m, d ->
                    {:ok, %{m | index: d["index"], binding: %{"version" => "2"}}}
                  end
              }
          }
        end

      assert {:error, _} = resume(%{c | definition: %{c.definition | steps: [step]}})
      no_new_io()
      refute_receive {:changeset, _}, 0
    end
  end

  for chain <- [false, true] do
    @tag bound: true, chain: chain
    test "chain=#{chain}: Model.validate_resume is preserved after restored configuration", c do
      c = with_agent(c, &%{&1 | model: %{&1.model | invalid: true}})
      assert {:error, :model_resume_rejected} = resume(c)
      assert_receive :validate_resume
      no_new_io()
    end
  end

  @tag second: "invalid", retries: 2, steps: 3, requests: 3
  test "live loop may consume retry2 and request3 normally", c do
    assert {:ok, %{output: %Output{count: 10}, request_count: 3}} = resume(c)
    assert_receive :model2
    assert_receive :model3
    frame = stored(c)["execution"]["progress"]["runtime"]
    [child] = Map.values(frame["children"])
    assert child["frame"]["output_retries_used"] == 2
    assert length(frame["scope"]["operations"]) == 3
  end

  for origin <- [:original, :current] do
    @tag root_requests: if(origin == :original, do: 1, else: 2)
    test "#{origin} root request1 cap forbids request2", c do
      options =
        if unquote(origin) == :current,
          do: [root_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 1}]],
          else: []

      assert {:error, %ExAgent.RunError{reason: {:usage_limit_exceeded, :request_limit, 1}}} =
               resume(c, options)

      no_new_io()
    end
  end

  for place <- [:root, :leaf] do
    test "current #{place} budget admits no new request and preserves historical ledger", c do
      limits = %ExAgent.UsageLimits{max_budget_cents: 0}

      {c, options} =
        if unquote(place) == :root,
          do: {c, [root_options: [usage_limits: limits]]},
          else: {with_agent(c, &%{&1 | usage_limits: limits}), []}

      assert {:error, %ExAgent.RunError{}} = resume(c, options)

      assert stored(c)["execution"]["progress"]["runtime"]["scope"] ==
               c.record["execution"]["progress"]["runtime"]["scope"]

      no_new_io()
    end
  end

  test "corrupt evidence and expanded positions fail decode/preclaim", c do
    record = c.record
    key = {c.store.namespace, :agent, "sequence"}
    {:ok, physical} = Record.key(key)
    path = ["execution", "progress", "runtime"]
    frame = get_in(record, path)
    [id] = Map.keys(frame["children"])
    [{request, entry}] = Map.to_list(frame["output_resolutions"])

    entries =
      for {k, v} <- [
            {"decision", "succeeded"},
            {"run_id", "wrong"},
            {"request_id", "wrong"},
            {"parts_hash", String.duplicate("0", 64)},
            {"call_id", "wrong"},
            {"parts", "[]"}
          ],
          do: put_in(frame, ["output_resolutions", request], Map.put(entry, k, v))

    mutations =
      entries ++
        [
          put_in(frame, ["children", id, "frame", "run_step"], 2),
          put_in(frame, ["children", id, "frame", "cursor"], "batch"),
          put_in(frame, ["output_resolutions", "extra"], entry),
          put_in(frame, ["scope", "operations"], [])
        ]

    for mutation <- mutations do
      bytes = Jason.encode!(put_in(record, path, mutation))
      assert {:error, _} = Record.decode(bytes, key)
      :ets.insert(__MODULE__, {physical, bytes})
      assert {:error, _} = resume(c)
    end

    refute_receive :codec, 0
    refute_receive {:operation, "claim"}, 0
    no_new_io()
  end

  for chain <- [false, true],
      source <- [:current, :original],
      place <- [:root, :leaf],
      slot <- [:permission_floor, :permission_floors] do
    policy = %ExAgent.Permissions{default: :deny}
    restriction = [{slot, if(slot == :permission_floor, do: policy, else: [policy])}]
    @tag second_tool: true, chain: chain
    @tag original_root: if(source == :original and place == :root, do: restriction, else: [])
    @tag original_leaf: if(source == :original and place == :leaf, do: restriction, else: [])
    test "chain=#{chain}: #{source} #{place} #{slot} denies a NEW tool after consumption", c do
      restriction = unquote(Macro.escape(restriction))

      opts =
        if unquote(source) == :current do
          if unquote(place) == :root, do: [root_options: restriction], else: restriction
        else
          [
            permissions: %ExAgent.Permissions{default: :allow},
            root_options: [permissions: %ExAgent.Permissions{default: :allow}]
          ]
        end

      assert {:error, %ExAgent.RunError{partial: partial}} = resume(c, opts)
      assert_receive :model2
      refute_receive :sibling_effect, 0

      assert Enum.any?(partial.messages, fn
               %Message.Request{parts: parts} ->
                 Enum.any?(
                   parts,
                   &match?(
                     %Message.Part.ToolReturn{tool_call_id: "new-sibling", status: :denied},
                     &1
                   )
                 )

               _ ->
                 false
             end)
    end
  end

  for chain <- [false, true] do
    @tag chain: chain
    test "chain=#{chain}: checkpoint token exact/+1 uses the real new-intent payload and remains data-only",
         c do
      Agent.update(c.fault, fn _ -> {"begin_effect", :before} end)
      assert {:error, %ExAgent.RunError{partial: partial}} = resume(c)
      token = partial.continuation_checkpoint
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

      token = put_in(token, path, "")
      remaining = Record.max_bytes() - ExAgent.Retention.bytes(token)
      exact = put_in(token, path, String.duplicate("x", remaining))
      assert ExAgent.Retention.bytes(exact) == Record.max_bytes()
      drain()
      assert {:error, reason} = Continuation.retry_checkpoint(c.store, exact)
      refute reason == :invalid_checkpoint_token

      assert {:error, :invalid_checkpoint_token} =
               Continuation.retry_checkpoint(c.store, update_in(exact, path, &(&1 <> "x")))

      no_new_io()
      refute_receive :codec, 0
      refute_receive {:changeset, _}, 0
    end
  end

  for chain <- [false, true] do
    @tag block_model: true, chain: chain
    test "chain=#{chain}: real owner death after intent makes new request uncertain without replay",
         c do
      {pid, monitor} =
        spawn_monitor(fn -> resume(c, continuation: %{c.config | lease_ms: 1_000}) end)

      assert_receive {:model_waiting, model_worker}, 5_000
      assert_receive {:claim_writer, writer}
      wm = Process.monitor(writer)
      mm = Process.monitor(model_worker)
      record = stored(c)
      assert map_size(record["execution"]["effects"]) == if(c[:chain], do: 5, else: 2)
      assert Enum.any?(Map.values(record["execution"]["effects"]), &(&1["state"] != "confirmed"))
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
      assert_receive {:DOWN, ^wm, :process, ^writer, _}, 5_000
      assert_receive {:DOWN, ^mm, :process, ^model_worker, _}, 5_000
      c = recover_again(c, stored(c))
      assert c.record["execution"]["state"] == "uncertain"
      drain()
      assert {:error, :composition_not_ready} = resume(c)
      no_new_io()
      refute_receive :codec, 0
    end
  end

  @tag chain: true, historic_descriptor: true
  test "mixed confirmed chain consumes current retry, not a historical same-call-ID entry", c do
    frame = c.record["execution"]["progress"]["runtime"]
    [child] = Map.values(frame["children"])
    assert child["frame"]["run_step"] == 4
    assert child["frame"]["output_retries_used"] == 3
    assert map_size(frame["output_resolutions"]) == 3
    assert Enum.all?(Map.values(frame["output_resolutions"]), &(&1["call_id"] == "first"))
    current = child["frame"]["model_request_id"]

    assert Enum.all?(Map.delete(frame["output_resolutions"], current), fn {_, entry} ->
             entry["descriptor"] != frame["output_resolutions"][current]["descriptor"]
           end)

    Process.put(:output_retry_trap, :historical)
    assert {:ok, %{output: %Output{count: 9}, request_count: 5}} = resume(c)
    assert_receive :model2
    refute_receive :model1, 0
    refute_receive {:historical_model, _}, 0
    refute_receive :sibling_effect, 0
    refute_receive {:changeset, %{"count" => "invalid"}}, 0
    empty = %{}
    assert_receive {:changeset, ^empty}
    refute_receive {:changeset, ^empty}, 0
    final = stored(c)["execution"]["progress"]["runtime"]
    [child] = Map.values(final["children"])
    assert child["frame"]["output_retries_used"] == 4
    assert Enum.all?(frame["scope"]["operations"], &(&1 in final["scope"]["operations"]))
  end

  @tag chain: true, first: 7
  test "success after mixed retries closes data-only with no schema or new request", c do
    c = with_agent(c, &%{&1 | output_type: SchemaTrap})
    Process.put(:output_retry_trap, :empty)
    old = c.record["execution"]["progress"]["runtime"]

    assert {:ok, %{output: %{"count" => 7}, request_count: 4}} =
             resume(c,
               estimate_cost: fn _ -> raise "repricing" end,
               root_options: [estimate_cost: fn _, _ -> raise "repricing root" end]
             )

    no_new_io()
    refute_receive {:changeset, _}, 0
    refute_receive {:historical_model, _}, 0
    assert stored(c)["execution"]["progress"]["runtime"]["scope"] == old["scope"]
  end

  @tag chain: true, second: "invalid", retries: 5, steps: 6, requests: 6
  test "multiple interruptions restore retry4 then retry5 then confirmed success6", c do
    Process.put(:output_retry_trap, :historical)

    c =
      Enum.reduce([5, 6], c, fn step, c ->
        Agent.update(c.fault, fn _ -> {"output_resolution", :after} end)

        assert {:error, %ExAgent.RunError{partial: partial}} =
                 resume(c, continuation: %{c.config | lease_ms: 1_000})

        Agent.update(c.fault, fn _ -> nil end)
        token = partial.continuation_checkpoint |> Jason.encode!() |> Jason.decode!()
        drain()

        assert {:ok, %{record: record, replayed: true}} =
                 Continuation.retry_checkpoint(c.store, token)

        no_new_io()
        refute_receive {:changeset, _}, 0
        [child] = Map.values(record["execution"]["progress"]["runtime"]["children"])
        assert child["frame"]["run_step"] == step
        assert child["frame"]["output_retries_used"] == step - 1
        recover_again(c, record)
      end)

    drain()
    Process.put(:output_retry_trap, :empty)
    assert {:ok, %{output: %{"count" => 10}, request_count: 6}} = resume(c)
    no_new_io()
    refute_receive {:changeset, _}, 0
    refute_receive :model3, 0
    final = stored(c)
    drain()

    assert {:ok, %{output: %{"count" => 10}}} =
             resume(%{c | reference: %{c.reference | revision: final["revision"]}})

    refute_receive :codec, 0
    no_new_io()
  end

  for source <- [:original, :current],
      limit <- [:retries, :steps, :requests],
      delta <- [-1, 0, 1] do
    value = if(limit == :retries, do: 4, else: 5) + delta
    @tag chain: true
    @tag [{if(source == :original, do: limit, else: :unused), value}]
    test "chain #{source} #{limit} required delta=#{delta} preserves counter and admission", c do
      c =
        if unquote(source) == :current do
          with_agent(c, fn a ->
            case unquote(limit) do
              :retries ->
                %{a | output_retries: unquote(value)}

              :steps ->
                %{a | max_steps: unquote(value)}

              :requests ->
                %{a | usage_limits: %ExAgent.UsageLimits{request_limit: unquote(value)}}
            end
          end)
        else
          c
        end

      if unquote(delta) < 0 do
        assert {:error, %ExAgent.RunError{reason: reason}} = resume(c)

        case unquote(limit) do
          :retries ->
            assert {:unexpected_model_behavior, {:output_retries_exhausted, content}} = reason
            frame = c.record["execution"]["progress"]["runtime"]
            [child] = Map.values(frame["children"])
            entry = frame["output_resolutions"][child["frame"]["model_request_id"]]
            {:ok, [%Message.Request{parts: [retry]}]} = Message.from_json(entry["parts"])
            assert content == retry.content

          :steps ->
            assert reason == {:max_steps_exceeded, 4}

          :requests ->
            assert reason == {:usage_limit_exceeded, :request_limit, 4}
        end

        no_new_io()
        assert map_size(stored(c)["execution"]["effects"]) == 4
      else
        assert {:ok, %{request_count: 5}} = resume(c)
        assert_receive :model2
      end
    end
  end

  for {retries, steps, expected} <- [{3, 4, :retry}, {4, 4, :steps}, {4, 5, :requests}] do
    @tag chain: true
    test "chain exhaustion before maxsteps before admission: #{expected}", c do
      c =
        with_agent(
          c,
          &%{
            &1
            | output_retries: unquote(retries),
              max_steps: unquote(steps),
              usage_limits: %ExAgent.UsageLimits{request_limit: 4}
          }
        )

      assert {:error, %ExAgent.RunError{reason: reason}} = resume(c)

      case unquote(expected) do
        :retry -> assert {:unexpected_model_behavior, {:output_retries_exhausted, _}} = reason
        :steps -> assert reason == {:max_steps_exceeded, 4}
        :requests -> assert reason == {:usage_limit_exceeded, :request_limit, 4}
      end

      no_new_io()
    end
  end

  @tag chain: true
  test "chain historical evidence corruption rejects both decode and real CAS with positive token control",
       c do
    Agent.update(c.fault, fn _ -> {"begin_effect", :before} end)
    assert {:error, %ExAgent.RunError{partial: partial}} = resume(c)
    token = partial.continuation_checkpoint
    record = stored(c)
    Agent.update(c.fault, fn _ -> nil end)
    frame = c.record["execution"]["progress"]["runtime"]
    [id] = Map.keys(frame["children"])
    current = frame["children"][id]["frame"]["model_request_id"]
    [{old, old_entry} | _] = Map.to_list(Map.delete(frame["output_resolutions"], current))

    mutations = [
      fn f -> update_in(f, ["output_resolutions"], &Map.delete(&1, old)) end,
      fn f -> put_in(f, ["output_resolutions", "duplicate"], old_entry) end,
      fn f -> put_in(f, ["output_resolutions", old, "parts_hash"], String.duplicate("0", 64)) end,
      fn f -> put_in(f, ["output_resolutions", old, "decision"], "succeeded") end,
      fn f -> put_in(f, ["output_resolutions", old, "request_id"], current) end,
      fn f -> update_in(f, ["children", id, "frame", "output_retries_used"], &(&1 + 1)) end,
      fn f -> update_in(f, ["children", id, "frame", "output_retries_used"], &(&1 - 1)) end,
      fn f ->
        update_in(f, ["children", id, "snapshot", "message_history"], fn bytes ->
          {:ok, messages} = Message.from_json(bytes)
          [a, b, c, d | rest] = messages
          Message.to_json([a, d, c, b | rest])
        end)
      end,
      fn f -> put_in(f, ["children", id, "frame", "model_data"], %{"index" => 99}) end,
      fn f -> update_in(f, ["scope", "operations"], &tl/1) end
    ]

    for mutate <- mutations do
      bad = update_in(c.record, ["execution", "progress", "runtime"], mutate)

      assert {:error, _} =
               Record.decode(Jason.encode!(bad), {c.store.namespace, :agent, "sequence"})

      command =
        update_in(token["command"], ["payload", "progress", "runtime"], mutate)
        |> Map.put("operation_id", "mutation-#{System.unique_integer([:positive])}")

      assert {:error, _} =
               Store.transition(c.store, :agent, "sequence", record["revision"], command)

      assert stored(c) == record
    end

    Agent.update(c.fault, fn _ -> nil end)
    drain()
    assert {:ok, _} = Continuation.retry_checkpoint(c.store, token)
    no_new_io()
    refute_receive {:changeset, _}, 0
  end

  @tag chain: true, ack: :before
  test "historical attestations do not authorize a current unattested outcome", c do
    assert map_size(c.record["execution"]["progress"]["runtime"]["output_resolutions"]) == 2
    assert {:error, :unsupported_composition_boundary} = resume(c)
    refute_receive :codec, 0
    refute_receive {:operation, "claim"}, 0
    no_new_io()
  end

  @tag prefix: [:text, :text, :text], ack: :before
  test "unattested textN chain stays excluded", c do
    assert c.record["execution"]["progress"]["runtime"]["output_resolutions"] == %{}
    assert {:error, :unsupported_composition_boundary} = resume(c)
    no_new_io()
  end

  @tag prefix: [:tool], executed_prefix: true, first: 7
  test "authentic completed tool prefix consumes current success data-only", c do
    assert Enum.any?(
             Map.values(c.record["execution"]["effects"]),
             &(&1["intent"]["kind"] == "tool")
           )

    assert Enum.all?(Map.values(c.record["execution"]["effects"]), &(&1["state"] == "confirmed"))
    before = c.record["execution"]["progress"]["runtime"]
    [child] = Map.values(before["children"])
    entry = before["output_resolutions"][child["frame"]["model_request_id"]]
    {:ok, history} = Message.from_json(child["snapshot"]["message_history"])
    {:ok, [%Message.Request{parts: parts}]} = Message.from_json(entry["parts"])
    Process.put(:output_retry_trap, :empty)

    assert {:ok,
            %{output: %{"count" => 7}, request_count: 2, tool_calls: 1, cost_cents: 6} = result} =
             resume(c)

    assert length(result.messages) == length(history) + 1
    assert Enum.take(result.messages, length(history)) == history
    assert List.last(result.messages).parts == parts
    assert Message.Usage.to_map(result.usage) == child["snapshot"]["usage"]
    final = stored(c)
    assert final["execution"]["state"] == "completed"
    assert final["execution"]["progress"]["runtime"]["scope"] == before["scope"]
    assert_receive :codec
    refute_receive :codec, 0
    refute_receive {:changeset, _}, 0
    no_new_io()
  end

  @tag chain: true, first: 7, output_type: NoEncoder
  test "chain current omitted output stays preclaim and cannot rescue historical data", c do
    assert {:error, {:composition_output_omitted, _}} = resume(c)
    refute_receive {:operation, "claim"}, 0
    refute_receive :codec, 0
    no_new_io()
  end

  @tag chain: true, output_type: LargeOutput, checkpoint_limit: 280_000
  @tag first_args: %{"count" => 7, "value" => String.duplicate("x", 100_000)}
  test "chain terminal-copy omission preserves attestation but completed stays an omission error",
       c do
    assert {:error, %ExAgent.RunError{}} = resume(c)
    completed = stored(c)
    frame = completed["execution"]["progress"]["runtime"]
    assert frame["cursor"] == "completed"
    [child] = Map.values(frame["children"])
    entry = frame["output_resolutions"][child["frame"]["model_request_id"]]
    assert entry["result"] == %{"count" => 7, "value" => String.duplicate("x", 100_000)}
    assert entry["result_omitted"] == nil
    assert child["result"] == nil
    marker = child["result_omitted"]

    assert marker ==
             ExAgent.Retention.marker(
               :checkpoint,
               ExAgent.Retention.bytes(entry["result"]),
               marker["limit"]
             )

    assert {:error, {:composition_output_omitted, ^marker}} =
             resume(%{c | reference: %{c.reference | revision: completed["revision"]}})

    no_new_io()
  end

  for delta <- [-1, 0, 1] do
    @tag chain: true, first: 7
    test "chain success portable payload exact delta=#{delta}", c do
      result =
        resume(c, max_payload_bytes: :erlang.external_size(%{"count" => 7}) + unquote(delta))

      if unquote(delta) < 0,
        do: assert(match?({:error, _}, result)),
        else: assert(match?({:ok, _}, result))

      no_new_io()
      refute_receive {:changeset, _}, 0
    end
  end

  @tag prefix: [:tool], executed_prefix: true, stop_operation: "finalize_call", ack: :before
  test "authentic raw tool outcome is not promoted to an executable chain", c do
    assert Enum.any?(
             Map.values(c.record["execution"]["effects"]),
             &(&1["intent"]["kind"] == "tool")
           )

    assert {:error, reason} = resume(c)
    assert reason in [:composition_not_ready, :unsupported_composition_boundary]
    refute_receive :codec, 0
    no_new_io()
  end

  @tag chain: true, unavailable: true
  test "authentic confirmed Model with unavailable state remains nonexecutable", c do
    assert Enum.any?(Map.values(c.record["execution"]["effects"]), fn effect ->
             effect["state"] == "confirmed" and
               effect["outcome"]["data"]["state_available"] == false
           end)

    assert {:error, :unsupported_composition_boundary} = resume(c)
    refute_receive :codec, 0
    no_new_io()
  end

  @tag chain: true, first: 7
  test "confirmed chain success needs no new admission despite stricter current limits", c do
    c =
      with_agent(
        c,
        &%{
          &1
          | output_retries: 0,
            max_steps: 1,
            usage_limits: %ExAgent.UsageLimits{request_limit: 0, max_budget_cents: 0}
        }
      )

    assert {:ok, %{output: %{"count" => 7}, request_count: 4}} =
             resume(c,
               root_options: [
                 usage_limits: %ExAgent.UsageLimits{request_limit: 0, max_budget_cents: 0}
               ]
             )

    no_new_io()
    refute_receive {:changeset, _}, 0
  end

  for source <- [:original, :current], limit <- [4, 5, 6] do
    @tag chain: true, root_requests: if(source == :original, do: limit, else: nil)
    test "chain #{source} root request limit #{limit} intersects admission without redebit", c do
      opts =
        if unquote(source) == :current,
          do: [root_options: [usage_limits: %ExAgent.UsageLimits{request_limit: unquote(limit)}]],
          else: []

      if unquote(limit) == 4 do
        assert {:error, %ExAgent.RunError{reason: {:usage_limit_exceeded, :request_limit, 4}}} =
                 resume(c, opts)

        no_new_io()
      else
        assert {:ok, %{request_count: 5}} = resume(c, opts)
        assert_receive :model2
      end
    end
  end

  for chain <- [false, true] do
    @tag chain: chain
    test "chain=#{chain}: new-intent checkpoint J exact/-1 derives from actual reserve projections",
         c do
      key = {c.store.namespace, :agent, "sequence"}
      {:ok, physical} = Record.key(key)
      {:ok, bytes} = Record.encode(c.record, key)
      Agent.update(c.fault, fn _ -> {"begin_effect", :before} end)

      trial = fn limit ->
        :ets.insert(__MODULE__, {physical, bytes})
        resume(c, continuation: %{c.config | max_checkpoint_bytes: limit})
      end

      admitted? = fn
        {:error,
         %ExAgent.RunError{
           partial: %{continuation_checkpoint: %{"command" => %{"operation" => "begin_effect"}}}
         }} ->
          true

        _ ->
          false
      end

      assert admitted?.(trial.(Record.max_bytes()))

      search = fn search, low, high ->
        if low == high do
          low
        else
          mid = div(low + high, 2)

          if admitted?.(trial.(mid)),
            do: search.(search, low, mid),
            else: search.(search, mid + 1, high)
        end
      end

      exact = search.(search, 1, Record.max_bytes())
      result = trial.(exact)
      assert {:error, %ExAgent.RunError{partial: partial}} = result
      assert admitted?.(result)
      assert ExAgent.Retention.bytes(partial.continuation_checkpoint) <= exact
      refute admitted?.(trial.(exact - 1))
      no_new_io()

      IO.inspect(
        %{
          j: exact,
          minus_one: exact - 1,
          token: ExAgent.Retention.bytes(partial.continuation_checkpoint)
        },
        label: "OUTPUT_RETRY_J_BOUNDARY"
      )
    end
  end
end
