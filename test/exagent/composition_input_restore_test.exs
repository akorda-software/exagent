defmodule ExAgent.CompositionInputRestoreTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, ExecutionScope, Store}
  alias ExAgent.Continuation.{Record, Writer}
  alias ExAgent.Coordination.Composition

  defmodule InputStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record(c, key), do: Store.ETS.load_record(c.table, key)
    def scan_records(c, ns, query), do: Store.ETS.scan_records(c.table, ns, query)

    def transition(c, key, revision, command) do
      if command["operation"] == "claim" and Agent.get(c.barrier, & &1) do
        send(c.owner, {:claim_waiting, self()})

        receive do
          :commit_claim -> :ok
        end
      end

      result = Store.ETS.transition(c.table, key, revision, command)

      if command["operation"] == "claim" and Agent.get(c.fault, & &1) == "claim_after" do
        send(c.owner, {:claim_committed, self()})

        receive do
          :release_ack -> :ok
        end
      end

      if command["operation"] == Agent.get(c.fault, & &1), do: {:error, :ack_lost}, else: result
    end
  end

  setup context do
    start_supervised!({Store.ETS, table: __MODULE__})
    owner = self()
    barrier = start_supervised!({Agent, fn -> false end})
    fault = start_supervised!({Agent, fn -> "step_input" end}, id: :fault)

    store =
      Store.scoped(
        {InputStore, %{table: __MODULE__, barrier: barrier, fault: fault, owner: owner}},
        "restore-input"
      )

    model = %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          send(owner, :model_io)
          "restored"
        end
      ]
    }

    {model, tools} =
      if context[:tool_loop] do
        tool =
          ExAgent.Tool.new(
            name: "effect",
            parameters_json_schema: %{"type" => "object"},
            call: fn _, _ ->
              send(owner, :tool_effect)
              {:ok, "done"}
            end
          )

        {%{
           model
           | script: [
               {:tool_calls,
                [
                  %ExAgent.Message.Part.ToolCall{
                    tool_name: "effect",
                    tool_call_id: "call-1",
                    args: %{}
                  }
                ]},
               "restored"
             ]
         }, [tool]}
      else
        {model, []}
      end

    step = %{
      id: "A",
      agent:
        ExAgent.new(
          model: model,
          tools: tools,
          usage_limits: context[:leaf_limits] || %ExAgent.UsageLimits{}
        ),
      model_codec: %{
        dump: fn m -> {:ok, %{"index" => m.index}} end,
        load: fn m, d ->
          send(owner, :codec_load)
          {:ok, %{m | index: d["index"]}}
        end
      },
      input: fn input, _ ->
        send(owner, :mapping)
        {:ok, input}
      end,
      input_version: "1",
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"}
    }

    {:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [step])
    root_options = context[:root_options] || []

    root_options =
      if context[:logical_ms],
        do:
          Keyword.put(
            root_options,
            :deadline,
            System.monotonic_time(:millisecond) + context.logical_ms
          ),
        else: root_options

    {:ok, scope} = ExecutionScope.start_structural("root", root_options)

    config = %{
      kind: :composition,
      composition: definition,
      store: store,
      id: "sequence",
      definition: %{"id" => "sequence", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      durability: :ephemeral,
      expires_at: nil,
      lease_ms: 50,
      active_time_limit_ms: context[:budget]
    }

    # Explicit legacy-9 source; current producer-10 has separate runtime coverage.
    {:ok, writer, _} =
      ExAgent.LegacyStructuralFixture.open(
        %{run_id: "root", execution_scope: scope, input: "original"},
        config
      )

    assert {:error, _} =
             ExAgent.run_composition_step(writer, definition, "A", context[:leaf_options] || [])

    assert_receive :mapping
    refute_receive :model_io
    token = Writer.pending(writer).token
    Writer.stop(writer)
    ExecutionScope.stop(scope)
    {:ok, record} = Store.load_record(store, :agent, "sequence")
    reference = %{id: "sequence", record_id: record["record_id"], revision: record["revision"]}
    {:ok, bytes} = Record.encode(record, {store.namespace, :agent, "sequence"})
    {:ok, ^record} = Record.decode(bytes, {store.namespace, :agent, "sequence"})

    %{
      store: store,
      definition: definition,
      config: %{config | lease_ms: 60_000},
      reference: reference,
      record: record,
      barrier: barrier,
      fault: fault,
      token: token
    }
  end

  defp recover(c) do
    assert {:ok, %{record: record}} =
             Continuation.recover(c.store, "sequence",
               record_id: c.record["record_id"],
               revision: c.record["revision"],
               operation_id: "recover-input",
               actor: "administrator",
               authorize: fn actor, _, _ -> {:ok, actor} end
             )

    %{id: "sequence", record_id: record["record_id"], revision: record["revision"]}
  end

  test "live claim rejects pre-codec; explicit recovery resumes confirmed input and completed reads are data-only",
       c do
    authority = c.record["execution"]["progress"]["runtime"]["authority"]
    assert Enum.all?(authority, fn {_, a} -> is_nil(a["deadline_at"]) end)
    assert is_integer(c.record["execution"]["lease_until"])

    assert {:error, :composition_not_ready} =
             ExAgent.resume_composition_step(c.definition, c.reference, continuation: c.config)

    refute_receive :codec_load
    reference = recover(c)

    assert {:ok, %{output: "restored"}} =
             ExAgent.resume_composition_step(c.definition, reference, continuation: c.config)

    assert_receive :codec_load
    assert_receive :model_io
    refute_receive :mapping
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    ref = %{id: "sequence", record_id: record["record_id"], revision: record["revision"]}

    assert {:ok, %{status: :completed, output: "restored"}} =
             ExAgent.resume_composition_step(c.definition, ref, continuation: c.config)

    refute_receive :codec_load
    refute_receive :model_io
  end

  test "two resumers race the same reference; only fresh claimant loads codec and performs IO",
       c do
    reference = recover(c)

    Agent.update(c.barrier, fn _ -> true end)

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          receive do
            :go ->
              ExAgent.resume_composition_step(c.definition, reference, continuation: c.config)
          end
        end)
      end

    Enum.each(tasks, &send(&1.pid, :go))
    assert_receive {:claim_waiting, first}, 5_000
    assert_receive {:claim_waiting, second}, 5_000
    refute_receive :codec_load
    send(first, :commit_claim)
    send(second, :commit_claim)
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
    assert_receive :codec_load
    assert_receive :model_io
    refute_receive :codec_load
    refute_receive :model_io
    refute_receive :mapping
  end

  @tag root_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 0}]
  test "original root zero request budget cannot be enlarged by current options", c do
    reference = recover(c)

    assert {:error, _} =
             ExAgent.resume_composition_step(c.definition, reference,
               continuation: c.config,
               root_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 100}]
             )

    refute_receive :model_io
  end

  test "current root zero request budget tightens original authority", c do
    reference = recover(c)

    assert {:error, _} =
             ExAgent.resume_composition_step(c.definition, reference,
               continuation: c.config,
               root_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 0}]
             )

    refute_receive :model_io
  end

  test "portable bytes restore in another BEAM without captures or original processes", c do
    path =
      Path.join("/tmp/opencode", "exagent-restore-vm-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(c.record))
    on_exit(fn -> File.rm(path) end)
    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++ ["test/support/composition_restore_vm.exs", path]

    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "NEW_VM_INPUT0_COMPLETED io=1"
    refute_receive :codec_load
    refute_receive :model_io
  end

  @tag budget: 10_000
  test "crashed active reservation is abandoned, never replenished", c do
    reference = recover(c)

    assert {:error, :active_budget_exhausted} =
             ExAgent.resume_composition_step(c.definition, reference,
               continuation: %{c.config | active_time_limit_ms: 100_000}
             )

    refute_receive :codec_load
    refute_receive :model_io
  end

  for location <- [:root, :leaf], action <- [:deny, :ask] do
    @tag tool_loop: true
    @tag root_options:
           if(location == :root,
             do: [permissions: %ExAgent.Permissions{default: action}],
             else: []
           )
    @tag leaf_options:
           if(location == :leaf,
             do: [permissions: %ExAgent.Permissions{default: action}],
             else: []
           )
    test "original #{location} #{action} remains effective against current allow", c do
      reference = recover(c)

      _ =
        ExAgent.resume_composition_step(c.definition, reference,
          continuation: c.config,
          permissions: %ExAgent.Permissions{default: :allow},
          root_options: [permissions: %ExAgent.Permissions{default: :allow}]
        )

      assert_receive :codec_load
      refute_receive :tool_effect
      {:ok, record} = Store.load_record(c.store, :agent, "sequence")

      assert Enum.any?(record["execution"]["effects"], fn {_, e} ->
               e["intent"]["kind"] == "model"
             end)

      if unquote(action) == :ask do
        ref = %{id: "sequence", record_id: record["record_id"], revision: record["revision"]}

        assert {:error, :composition_not_ready} =
                 ExAgent.resume_composition_step(c.definition, ref, continuation: c.config)

        refute_receive :codec_load
      end
    end
  end

  for location <- [:root, :leaf],
      slot <- [:permission_floor, :permission_floors],
      action <- [:deny, :ask],
      timing <- [:current, :original] do
    policy = %ExAgent.Permissions{
      default: :allow,
      rules: [{~r/.*/, :allow}, {~r/^effect$/, action}]
    }

    restriction = [{slot, if(slot == :permission_floor, do: policy, else: [policy])}]
    @tag tool_loop: true
    @tag root_options: if(timing == :original and location == :root, do: restriction, else: [])
    @tag leaf_options: if(timing == :original and location == :leaf, do: restriction, else: [])
    test "#{timing} #{location} #{slot} #{action} is conjunctive across integrated restore", c do
      reference = recover(c)
      allow = %ExAgent.Permissions{default: :allow}
      options = [permissions: allow, permission_floor: allow, permission_floors: [allow]]

      options =
        if unquote(timing) == :current,
          do: Keyword.merge(options, unquote(Macro.escape(restriction))),
          else: options

      opts = if unquote(location) == :root, do: [root_options: options], else: options

      _ =
        ExAgent.resume_composition_step(
          c.definition,
          reference,
          Keyword.put(opts, :continuation, c.config)
        )

      assert_receive :codec_load
      refute_receive :tool_effect
      {:ok, record} = Store.load_record(c.store, :agent, "sequence")

      assert Enum.any?(record["execution"]["effects"], fn {_, effect} ->
               effect["intent"]["kind"] == "model"
             end)

      path = ["execution", "progress", "runtime", "authority"]
      assert get_in(record, path) == get_in(c.record, path)

      if unquote(action) == :ask do
        ref = %{id: "sequence", record_id: record["record_id"], revision: record["revision"]}

        assert {:error, :composition_not_ready} =
                 ExAgent.resume_composition_step(c.definition, ref, continuation: c.config)

        refute_receive :codec_load
      end
    end
  end

  for location <- [:root, :leaf] do
    @tag tool_loop: true
    test "current #{location} deny tightens original allow", c do
      reference = recover(c)

      opts =
        if unquote(location) == :root,
          do: [root_options: [permissions: %ExAgent.Permissions{default: :deny}]],
          else: [permissions: %ExAgent.Permissions{default: :deny}]

      _ =
        ExAgent.resume_composition_step(
          c.definition,
          reference,
          Keyword.put(opts, :continuation, c.config)
        )

      assert_receive :codec_load
      refute_receive :tool_effect
    end
  end

  @tag leaf_limits: %ExAgent.UsageLimits{request_limit: 0}
  test "original leaf zero cannot be widened by replacing current agent limits", c do
    reference = recover(c)
    [step] = c.definition.steps

    definition = %{
      c.definition
      | steps: [
          %{step | agent: %{step.agent | usage_limits: %ExAgent.UsageLimits{request_limit: 10}}}
        ]
    }

    assert {:error, _} =
             ExAgent.resume_composition_step(definition, reference, continuation: c.config)

    refute_receive :model_io
  end

  @tag root_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 1}]
  @tag leaf_limits: %ExAgent.UsageLimits{request_limit: 1}
  test "exact one request limit completes with one ledger contribution, no repricing", c do
    reference = recover(c)

    assert {:ok, %{output: "restored", usage: usage}} =
             ExAgent.resume_composition_step(c.definition, reference, continuation: c.config)

    assert usage.input_tokens == 1
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    assert length(record["execution"]["progress"]["runtime"]["scope"]["operations"]) == 1
    assert_receive :model_io
    refute_receive :model_io
  end

  test "retrying the exact confirmed input receipt is data-only and does not authorize execution",
       c do
    # InputStore deliberately loses the ACK again after the replay; use the same
    # underlying atomic backend directly to observe the receipt without changing it.
    store = Store.scoped({Store.ETS, __MODULE__}, c.store.namespace)
    assert {:ok, %{replayed: true}} = Continuation.retry_checkpoint(store, c.token)

    assert {:error, :composition_not_ready} =
             ExAgent.resume_composition_step(c.definition, c.reference, continuation: c.config)

    refute_receive :codec_load
    refute_receive :model_io
  end

  test "replayed claim receipt cannot activate codecs or IO", c do
    reference = recover(c)
    Agent.update(c.fault, fn _ -> "claim" end)

    assert {:error, {:composition_claim_failed, _, token}} =
             ExAgent.resume_composition_step(c.definition, reference, continuation: c.config)

    assert token["command"]["operation"] == "claim"
    store = Store.scoped({Store.ETS, __MODULE__}, c.store.namespace)
    assert {:ok, %{replayed: true, record: claimed}} = Continuation.retry_checkpoint(store, token)
    ref = %{reference | revision: claimed["revision"]}

    assert {:error, :composition_not_ready} =
             ExAgent.resume_composition_step(c.definition, ref, continuation: c.config)

    refute_receive :codec_load
    refute_receive :model_io
  end

  test "current leaf request zero tightens the persisted unrestricted leaf", c do
    reference = recover(c)
    [step] = c.definition.steps

    definition = %{
      c.definition
      | steps: [
          %{step | agent: %{step.agent | usage_limits: %ExAgent.UsageLimits{request_limit: 0}}}
        ]
    }

    assert {:error, _} =
             ExAgent.resume_composition_step(definition, reference, continuation: c.config)

    refute_receive :model_io
  end

  @tag tool_loop: true
  @tag root_options: [
         permissions: %ExAgent.Permissions{default: :allow},
         permission_floor: %ExAgent.Permissions{default: :deny}
       ]
  test "original root floor remains conjunctive, not replaced by current allow", c do
    reference = recover(c)

    _ =
      ExAgent.resume_composition_step(c.definition, reference,
        continuation: c.config,
        root_options: [
          permissions: %ExAgent.Permissions{default: :allow},
          permission_floor: %ExAgent.Permissions{default: :allow}
        ]
      )

    assert_receive :codec_load
    refute_receive :tool_effect
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")

    assert Enum.any?(record["execution"]["effects"], fn {_, e} ->
             e["intent"]["kind"] == "model"
           end)
  end

  test "authentic legacy bytes remain readable, never inferred as execution authority", _c do
    for path <- Path.wildcard("test/fixtures/continuation/composition_legacy/*.json") do
      bytes = File.read!(path)
      [namespace, "agent", id] = Jason.decode!(bytes)["key"]
      assert {:ok, record} = Record.decode(bytes, {namespace, :agent, id})

      assert {:error, :composition_authority_missing} =
               ExAgent.Continuation.CompositionRestore.boundary(record)
    end

    refute_receive :codec_load
  end

  @tag logical_ms: 600
  test "original logical UTC deadline expires independently of a renewed lease", c do
    reference = recover(c)
    Process.sleep(650)

    assert {:error, :deadline_exceeded} =
             ExAgent.resume_composition_step(c.definition, reference, continuation: c.config)

    refute_receive :codec_load
    refute_receive :model_io
  end

  test "current logical deadline rejects before codec", c do
    reference = recover(c)

    assert {:error, :deadline_exceeded} =
             ExAgent.resume_composition_step(c.definition, reference,
               continuation: c.config,
               root_options: [deadline: System.monotonic_time(:millisecond) - 1]
             )

    refute_receive :codec_load
  end

  test "root captures its effective deadline even if an internal leaf hint is supplied", _c do
    deadline = System.monotonic_time(:millisecond) + 10_000

    {:ok, scope} =
      ExecutionScope.start_structural("actual-root", deadline: deadline, logical_deadline: nil)

    {:ok, authority} = ExecutionScope.authority(scope)
    assert is_integer(authority["deadline_at"])
    assert_in_delta authority["deadline_at"], System.system_time(:millisecond) + 10_000, 100
    ExecutionScope.stop(scope)
  end

  @tag tool_loop: true
  @tag root_options: [
         usage_limits: %ExAgent.UsageLimits{max_budget_cents: 100, accounting: :strict}
       ]
  test "original strict cost accounting cannot be weakened to estimated", c do
    reference = recover(c)

    assert {:error, _} =
             ExAgent.resume_composition_step(c.definition, reference,
               continuation: c.config,
               root_options: [
                 usage_limits: %ExAgent.UsageLimits{request_limit: 10, accounting: :estimated}
               ]
             )

    refute_receive :tool_effect
  end

  test "all numeric limits, strict accounting, concurrency and ordered floors intersect without widening",
       c do
    alias ExAgent.Continuation.Authority

    old = %ExAgent.UsageLimits{
      request_limit: 4,
      total_tokens_limit: 20,
      input_tokens_limit: 10,
      output_tokens_limit: 12,
      tool_calls_limit: 5,
      max_budget_cents: 8,
      accounting: :strict
    }

    current = %ExAgent.UsageLimits{
      request_limit: 2,
      total_tokens_limit: 30,
      input_tokens_limit: 6,
      output_tokens_limit: 20,
      tool_calls_limit: 3,
      max_budget_cents: 10,
      accounting: :estimated
    }

    policy = %ExAgent.Permissions{default: :deny, rules: [{~r/^effect$/, :ask}, {~r/.*/, :allow}]}

    {:ok, original} =
      ExecutionScope.start_structural("limits",
        usage_limits: old,
        permissions: policy,
        permission_floor: %ExAgent.Permissions{default: :ask},
        max_concurrent_requests: 2
      )

    {:ok, data} = ExecutionScope.authority(original)
    ExecutionScope.stop(original)

    opts =
      Authority.intersect(data, data["usage"],
        usage_limits: current,
        max_concurrent_requests: 5,
        permissions: %ExAgent.Permissions{default: :allow},
        permission_floors: [%ExAgent.Permissions{default: :deny}]
      )

    {:ok, scope} = ExecutionScope.start_structural("limits", opts)
    {:ok, effective} = ExecutionScope.authority(scope)
    ExecutionScope.stop(scope)

    assert effective["usage"] ==
             Authority.usage(%ExAgent.UsageLimits{
               request_limit: 2,
               total_tokens_limit: 20,
               input_tokens_limit: 6,
               output_tokens_limit: 12,
               tool_calls_limit: 3,
               max_budget_cents: 8,
               accounting: :strict
             })

    assert effective["max_concurrent_requests"] == 2
    assert Enum.take(effective["policies"], -length(data["policies"])) == data["policies"]

    assert data["policies"] |> hd() |> Map.fetch!("rules") == [
             ["^effect$", Regex.opts(~r/^effect$/), "ask"],
             [".*", Regex.opts(~r/.*/), "allow"]
           ]

    refute_receive :model_io
    assert c.record["execution"]["effects"] == %{}
  end

  for operation <- ["begin_effect", "outcome"] do
    test "#{operation} persisted frontier cannot be resumed by this input-only seam", c do
      reference = recover(c)
      Agent.update(c.fault, fn _ -> unquote(operation) end)

      assert {:error, _} =
               ExAgent.resume_composition_step(c.definition, reference, continuation: c.config)

      assert_receive :codec_load
      if unquote(operation) == "outcome", do: assert_receive(:model_io)
      {:ok, record} = Store.load_record(c.store, :agent, "sequence")
      ref = %{id: "sequence", record_id: record["record_id"], revision: record["revision"]}

      assert {:error, :composition_not_ready} =
               ExAgent.resume_composition_step(c.definition, ref, continuation: c.config)

      refute_receive :codec_load
      refute_receive :model_io
    end
  end

  test "owner killed after claim commit leaves no effects; only explicit administrative recovery reopens it",
       c do
    reference = recover(c)
    Agent.update(c.fault, fn _ -> "claim_after" end)

    {owner, monitor} =
      spawn_monitor(fn ->
        ExAgent.resume_composition_step(c.definition, reference,
          continuation: %{c.config | lease_ms: 50}
        )
      end)

    assert_receive {:claim_committed, writer}, 5_000
    writer_monitor = Process.monitor(writer)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, _}
    refute_receive :codec_load
    refute_receive :model_io
    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    assert record["execution"]["effects"] == %{}
    ref = %{id: "sequence", record_id: record["record_id"], revision: record["revision"]}

    assert {:error, :composition_not_ready} =
             ExAgent.resume_composition_step(c.definition, ref, continuation: c.config)

    Agent.update(c.fault, fn _ -> nil end)

    assert {:ok, %{record: ready}} =
             Continuation.recover(c.store, "sequence",
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "recover-dead-owner",
               actor: "admin",
               authorize: fn actor, _, _ -> {:ok, actor} end
             )

    reference = %{ref | revision: ready["revision"]}

    assert {:ok, %{output: "restored"}} =
             ExAgent.resume_composition_step(c.definition, reference, continuation: c.config)

    assert_receive :codec_load
    assert_receive :model_io
  end

  test "binding/reference/authority corruption reject before codec and registration", c do
    reference = recover(c)
    callback = fn _ -> send(self(), :registered) end
    config = Map.put(c.config, :on_writer, callback)

    assert {:error, _} =
             ExAgent.resume_composition_step(
               c.definition,
               %{reference | revision: reference.revision + 1},
               continuation: config
             )

    {:ok, record} = Store.load_record(c.store, :agent, "sequence")
    path = ["execution", "progress", "runtime"]
    frame = get_in(record, path)
    {:ok, physical} = Record.key({c.store.namespace, :agent, "sequence"})

    for invalid <- [
          Map.delete(frame, "authority"),
          put_in(frame, ["authority", "root", "policies"], []),
          put_in(frame, ["authority", "root", "usage", "request_limit"], -1),
          put_in(frame, ["binding", "id"], "other")
        ] do
      :ets.insert(__MODULE__, {physical, Jason.encode!(put_in(record, path, invalid))})

      assert {:error, _} =
               ExAgent.resume_composition_step(c.definition, reference, continuation: config)
    end

    refute_receive :codec_load
    refute_receive :model_io
    refute_receive :registered
  end
end
