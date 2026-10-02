defmodule ExAgent.CompositionToolRestoreTest do
  use ExUnit.Case, async: false
  alias ExAgent.CompositionToolRestoreFixture, as: F
  alias ExAgent.{Message, Store}
  alias ExAgent.Continuation.{Record, CompositionRestore}

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    :ok
  end

  @tag :causal
  test "resolved current batch consumes returns and drives only the next Model" do
    {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :after})
    ready = F.recover(record, config)
    definition = F.definition(trap: true, new_index: 1)
    config = F.config(__MODULE__, definition)
    flush()
    assert {:ok, result} = F.resume(ready, config, definition)
    assert result.output == "done"
    assert_received {:model, 1}
    refute_received {:model, 0}
    refute_received {:tool, _}
    assert {:ok, saved} = Store.load_record(config.store, :agent, config.id)
    assert :ok = Record.validate(saved, {config.store.namespace, :agent, config.id})

    returns =
      for %Message.Request{parts: parts} <- result.messages,
          %Message.Part.ToolReturn{} = part <- parts,
          do: part

    assert length(returns) == 1
  end

  @tag :causal
  test "consumed tool prefix closes a confirmed terminal text without replay" do
    {_, record, config, _} = F.capture(__MODULE__, fault: {"step_output", :before})
    ready = F.recover(record, config)
    definition = F.definition(trap: true)
    config = F.config(__MODULE__, definition)
    flush()
    assert {:ok, %{output: "done"}} = F.resume(ready, config, definition)
    refute_received {:model, _}
    refute_received {:tool, _}
  end

  for actions <- [["retry", "success"], ["success", "retry"], ["retry", "retry", "success"]] do
    @actions actions
    test "current batch control keeps ordered #{inspect(actions)} and protected lifetime counters" do
      calls = Enum.with_index(@actions, &F.call("call#{&2}", &1))
      script = [F.response(calls), F.text()]

      {_, record, config, _} =
        F.capture(__MODULE__, script: script, fault: {"tool_resolution", :after})

      ready = F.recover(record, config)

      hooks = [
        %F.Hooks{owner: self(), mutate: true, trap_tools: true},
        %F.Hooks{owner: self(), mutate: false, trap_tools: true}
      ]

      definition = F.definition(script: script, trap: true, new_index: 1, capabilities: hooks)
      config = F.config(__MODULE__, definition)
      flush()
      result = F.resume(ready, config, definition)

      if @actions == ["retry", "retry", "success"] do
        assert {:error,
                %ExAgent.RunError{
                  reason:
                    {:unexpected_model_behavior,
                     {:tool_retries_exhausted, "effect", %{"code" => "runtime_error"}}},
                  partial: partial
                }} = result

        assert length(returns(partial)) == 3
        refute_received {:model, _}
        refute_received {:hook, _, _, _, _}
      else
        assert {:ok, result} = result
        assert length(returns(result)) == 2
        expected = if @actions == ["success", "retry"], do: %{"effect" => 1}, else: %{}

        for phase <- [:before, :after] do
          assert_received {:hook, ^phase, false,
                           %{
                             tool_calls: 2,
                             tool_retries: ^expected,
                             run_step: 2,
                             max_steps: 10,
                             output_retries_used: 0
                           }, 2}
        end
      end

      refute_received {:tool, _}
      refute_received {:tool_hook, _, _}
    end
  end

  for typed <- [false, true] do
    @typed typed
    test "first portable fatal survives succeeded siblings typed=#{typed}" do
      type = if @typed, do: F.Output, else: :text
      script = [F.response([F.call("fatal1"), F.call("fatal2"), F.call("success")]), F.text()]

      {_, record, config, _} =
        F.capture(__MODULE__,
          script: script,
          output_type: type,
          capabilities: [%F.Hooks{owner: self(), fatal: ["fatal1", "fatal2"]}]
        )

      ready = F.recover(record, config)
      definition = F.definition(script: script, output_type: type, trap: true)
      [batch] = Map.values(record["execution"]["progress"]["runtime"]["tool_batches"])
      assert Enum.map(batch["resolution"]["calls"], &is_nil(&1["error"])) == [false, false, true]
      config = F.config(__MODULE__, definition)
      flush()

      assert {:error,
              %ExAgent.RunError{reason: %{"code" => "tool_hook_failed"}, partial: partial}} =
               F.resume(ready, config, definition)

      assert length(returns(partial)) == 3
      assert Enum.all?(returns(partial), &(&1.status == :succeeded))
      refute_received {:model, _}
      refute_received {:tool, _}
      {:ok, unchanged} = Store.load_record(config.store, :agent, config.id)

      assert unchanged["execution"]["progress"]["runtime"]["tool_batches"] ==
               record["execution"]["progress"]["runtime"]["tool_batches"]

      assert unchanged["execution"]["state"] == "claimed"
    end
  end

  for decision <- [:success, :retry] do
    @decision decision
    test "tool prefix consumes current output #{@decision} without historical validation" do
      value = if @decision == :success, do: 9, else: "invalid"
      script = [F.response([F.call("one", "retry")]), F.output(value), F.output(9)]

      {_, record, config, _} =
        F.capture(__MODULE__,
          script: script,
          output_type: F.Output,
          fault: {"output_resolution", :after}
        )

      ready = F.recover(record, config)

      hooks = [
        %F.Hooks{owner: self(), mutate: true, trap_tools: true},
        %F.Hooks{owner: self(), mutate: false, trap_tools: true}
      ]

      definition =
        F.definition(
          script: script,
          output_type: F.Output,
          trap: true,
          new_index: 2,
          capabilities: hooks
        )

      config = F.config(__MODULE__, definition)
      flush()
      Process.put(:tool_restore_observer, self())
      Process.put(:tool_restore_args_trap, %{"count" => value})
      if @decision == :success, do: Process.put(:tool_restore_schema_trap, true)
      assert {:ok, result} = F.resume(ready, config, definition)

      assert result.output ==
               if(@decision == :success, do: %{"count" => 9}, else: %F.Output{count: 9})

      assert length(returns(result)) == if(@decision == :success, do: 2, else: 3)
      refute_received {:tool, _}
      refute_received {:model, 0}
      refute_received {:model, 1}

      if @decision == :retry do
        for phase <- [:before, :after] do
          assert_received {:hook, ^phase, false,
                           %{
                             tool_calls: 1,
                             tool_retries: %{"effect" => 1},
                             output_retries_used: 1,
                             run_step: 3
                           }, 2}
        end
      else
        refute_received {:changeset, _}
      end
    end
  end

  test "historical output retry cannot mask the actual resolved tool batch" do
    script = [F.output("invalid"), F.response([F.call("one", "retry")]), F.output(9)]

    {_, record, config, _} =
      F.capture(__MODULE__,
        script: script,
        output_type: F.Output,
        fault: {"tool_resolution", :after}
      )

    ready = F.recover(record, config)
    definition = F.definition(script: script, output_type: F.Output, trap: true, new_index: 2)
    config = F.config(__MODULE__, definition)
    flush()
    Process.put(:tool_restore_args_trap, %{"count" => "invalid"})
    assert {:ok, %{output: %F.Output{count: 9}} = result} = F.resume(ready, config, definition)
    assert length(returns(result)) == 3
    assert_received {:model, 2}
    refute_received {:tool, _}
  end

  for fault <- [{"tool_resolution", :before}, {"finalize_call", :before}, {"outcome", :before}] do
    @fault fault
    test "unresolved evidence #{@fault |> inspect()} stays blocked" do
      {_, record, config, _} = F.capture(__MODULE__, fault: @fault)
      ready = F.recover(record, config)
      flush()
      assert {:error, _} = F.resume(ready, F.config(__MODULE__, F.definition()), F.definition())
      refute_received :codec
      refute_received {:model, _}
      refute_received {:tool, _}
    end
  end

  test "rejected accounting stays blocked with confirmed control" do
    {_, record, config, _} =
      F.capture(__MODULE__, usage: %Message.Usage{input_tokens: -1, output_tokens: 1})

    ready = F.recover(record, config)
    assert {:error, :unsupported_composition_boundary} = CompositionRestore.boundary(ready)
  end

  test "previous retry count is reduced once for current batch with reused call ID and historical schema" do
    script = [
      F.response([F.call("same", "retry")]),
      F.response([F.call("same", "retry")]),
      F.text()
    ]

    fault = fn command ->
      batches = get_in(command, ["payload", "progress", "runtime", "tool_batches"]) || %{}

      if command["operation"] == "tool_resolution" and map_size(batches) == 2,
        do: {"tool_resolution", :after}
    end

    {_, record, config, _} =
      F.capture(__MODULE__, script: script, fault: fault, capabilities: [F.HistoricalSchema])

    ready = F.recover(record, config)
    definition = F.definition(script: script, trap: true)
    flush()

    assert {:error,
            %ExAgent.RunError{
              reason:
                {:unexpected_model_behavior,
                 {:tool_retries_exhausted, "effect", %{"code" => "runtime_error"}}},
              partial: result
            }} =
             F.resume(ready, F.config(__MODULE__, definition), definition)

    assert result.tool_calls == 2
    assert Enum.map(returns(result), & &1.tool_call_id) == ["same", "same"]
    refute_received {:model, _}
    refute_received {:tool, _}
  end

  for n <- [1, 2] do
    @n n
    test "typed fatal reflection failure #{@n} preserves confirmed bytes without stubs" do
      {_, record, config, _} =
        F.capture(__MODULE__,
          output_type: F.Output,
          capabilities: [%F.Hooks{owner: self(), fatal: ["one"]}]
        )

      ready = F.recover(record, config)
      definition = F.definition(output_type: F.OutputProxy, trap: true)
      Process.put(:tool_restore_reflections, 0)
      Process.put(:tool_restore_fail_reflection, @n)
      flush()
      result = F.resume(ready, F.config(__MODULE__, definition), definition)

      if @n == 1 do
        assert {:error, :invalid_continuation_configuration} = result
      else
        assert {:error, %ExAgent.RunError{partial: partial}} = result
        assert returns(partial) == []
        [child] = Map.values(ready["execution"]["progress"]["runtime"]["children"])
        {:ok, history} = Message.from_json(child["snapshot"]["message_history"])
        assert partial.messages == history
      end

      {:ok, saved} = Store.load_record(config.store, :agent, config.id)

      assert saved["execution"]["progress"]["runtime"] ==
               ready["execution"]["progress"]["runtime"]

      refute_received {:tool, _}
      refute_received {:model, _}
    end
  end

  for delta <- [-1, 0, 1] do
    @delta delta
    test "confirmed batch append history exact #{@delta} preserves evidence" do
      {_, record, config, _} =
        F.capture(__MODULE__, capabilities: [%F.Hooks{owner: self(), fatal: ["one"]}])

      ready = F.recover(record, config)

      {:ok, {:confirmed_tool_history, {:confirmed_tool_batch, selection}, 0}} =
        CompositionRestore.boundary(ready)

      [child] = Map.values(ready["execution"]["progress"]["runtime"]["children"])
      {:ok, messages} = Message.from_json(child["snapshot"]["message_history"])

      complete =
        messages ++
          [
            %Message.Request{
              parts: selection.parts,
              run_id: child["frame"]["run_id"],
              timestamp: DateTime.utc_now()
            }
          ]

      exact = ExAgent.Retention.bytes(complete)
      definition = F.definition(trap: true)
      flush()

      assert {:error, %ExAgent.RunError{reason: reason, partial: result}} =
               F.resume(ready, F.config(__MODULE__, definition), definition,
                 max_history_bytes: exact + @delta
               )

      if @delta == -1 do
        assert {:retention_limit_exceeded, %{boundary: :history, bytes: ^exact}} = reason
        assert result.messages == messages
        assert returns(result) == []
      else
        assert %{"code" => "tool_hook_failed"} = reason
        assert length(returns(result)) == 1
      end

      refute_received {:tool, _}
      refute_received {:model, _}
    end
  end

  for {usage, index} <-
        Enum.with_index([
          nil,
          %Message.Usage{input_tokens: nil, output_tokens: nil},
          %Message.Usage{input_tokens: 0, output_tokens: 0},
          %Message.Usage{input_tokens: 7, output_tokens: nil},
          %Message.Usage{input_tokens: 7, output_tokens: 11},
          Message.Usage.partial(%Message.Usage{input_tokens: 3, output_tokens: 4}),
          Message.Usage.with_cost(
            %Message.Usage{input_tokens: 3, output_tokens: 4},
            17,
            "estimator",
            true
          )
        ]) do
    @usage usage
    test "confirmed prefix accounting profile #{index} retains exact ledger without repricing" do
      {_, record, config, _} =
        F.capture(__MODULE__,
          usage: @usage,
          fault: {"step_output", :before},
          root_options: [estimate_cost: fn _, _ -> 7 end],
          run_options: [estimate_cost: fn _ -> 3 end]
        )

      ready = F.recover(record, config)
      before_scope = ready["execution"]["progress"]["runtime"]["scope"]
      definition = F.definition(trap: true)
      config = F.config(__MODULE__, definition)
      flush()

      assert {:ok, result} =
               F.resume(ready, config, definition,
                 estimate_cost: fn _ -> raise "repricing leaf" end,
                 root_options: [estimate_cost: fn _, _ -> raise "repricing root" end]
               )

      assert result.request_count == 2
      assert result.tool_calls == 1
      assert Enum.all?(returns(result), &is_nil(&1.usage))
      {:ok, saved} = Store.load_record(config.store, :agent, config.id)
      assert saved["execution"]["progress"]["runtime"]["scope"] == before_scope
      [child] = Map.values(ready["execution"]["progress"]["runtime"]["children"])
      assert Message.Usage.to_map(result.usage) == child["snapshot"]["usage"]
      refute_received {:tool, _}
      refute_received {:model, _}
    end
  end

  for boundary <- [:close, :fatal, :drive], limit <- [0, 1, 2] do
    @boundary boundary
    @limit limit
    test "current quota #{@limit} at #{@boundary} distinguishes consumed history from new admission" do
      opts =
        case @boundary do
          :close -> [fault: {"step_output", :before}]
          :fatal -> [capabilities: [%F.Hooks{owner: self(), fatal: ["one"]}]]
          :drive -> [fault: {"tool_resolution", :after}]
        end

      {_, record, config, _} = F.capture(__MODULE__, opts)
      ready = F.recover(record, config)
      limits = %ExAgent.UsageLimits{request_limit: @limit, tool_calls_limit: 0}
      definition = F.definition(trap: true, new_index: 1, usage_limits: limits)
      config = F.config(__MODULE__, definition)
      flush()
      result = F.resume(ready, config, definition, root_options: [usage_limits: limits])

      case @boundary do
        :close ->
          assert {:ok, %{output: "done", request_count: 2}} = result

        :fatal ->
          assert {:error, %ExAgent.RunError{reason: %{"code" => "tool_hook_failed"}}} = result

        :drive ->
          if @limit == 2 do
            assert {:ok, %{request_count: 2}} = result
            assert_received {:model, 1}
          else
            assert {:error, %ExAgent.RunError{}} = result
            refute_received {:model, _}
          end
      end

      refute_received {:tool, _}
    end
  end

  test "max_retries fingerprint change still rejects confirmed batch" do
    {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :after})
    ready = F.recover(record, config)
    definition = F.definition(max_retries: 2)
    flush()

    assert {:error, :continuation_tools_changed} =
             F.resume(ready, F.config(__MODULE__, definition), definition)

    refute_received {:model, _}
    refute_received {:tool, _}
  end

  for source <- [:current, :original],
      place <- [:root, :leaf],
      slot <- [:permission_floor, :permission_floors],
      action <- [:deny, :ask] do
    @source source
    @place place
    @slot slot
    @action action
    test "#{source} #{place} #{slot} #{action} restricts only NEW tool after historical batch" do
      policy = ExAgent.Permissions.new!(rules: [{"*", :allow}, {"new_effect", @action}])
      restriction = [{@slot, if(@slot == :permission_floor, do: policy, else: [policy])}]
      new_call = %{F.call("new", "new") | tool_name: "new_effect"}
      script = [F.response([F.call("one")]), F.response([new_call]), F.text()]
      opts = [script: script, new_tool: true, fault: {"tool_resolution", :after}]

      opts =
        if @source == :original,
          do:
            Keyword.put(
              opts,
              if(@place == :root, do: :root_options, else: :run_options),
              restriction
            ),
          else: opts

      {_, record, config, _} = F.capture(__MODULE__, opts)
      ready = F.recover(record, config)
      definition = F.definition(script: script, new_tool: true, trap: true, new_index: 1)

      resume_opts =
        if @source == :current,
          do: if(@place == :root, do: [root_options: restriction], else: restriction),
          else: [
            permissions: %ExAgent.Permissions{default: :allow},
            root_options: [permissions: %ExAgent.Permissions{default: :allow}]
          ]

      flush()

      response = F.resume(ready, F.config(__MODULE__, definition), definition, resume_opts)

      result =
        if @action == :deny do
          assert {:ok, %{output: "done"} = result} = response
          result
        else
          assert {:error, %ExAgent.RunError{partial: result}} = response
          result
        end

      assert_received {:model, 1}
      refute_received {:tool, _}

      status = if @action == :deny, do: :denied, else: :not_executed

      assert Enum.any?(
               returns(result),
               &match?(%Message.Part.ToolReturn{tool_call_id: "new", status: ^status}, &1)
             )

      assert hd(returns(result)).status == :succeeded
    end
  end

  for deadline <- [:leaf, :root] do
    @deadline deadline
    test "#{deadline} expired current logical deadline blocks before claim" do
      {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :after})
      ready = F.recover(record, config)
      definition = F.definition(trap: true)
      opts = [deadline: System.monotonic_time(:millisecond) - 1]
      opts = if @deadline == :root, do: [root_options: opts], else: opts
      flush()

      assert {:error, :deadline_exceeded} =
               F.resume(ready, F.config(__MODULE__, definition), definition, opts)

      refute_received :codec
      assert {:ok, ^ready} = Store.load_record(config.store, :agent, config.id)
    end
  end

  test "two claimants reach the same revision barrier with one winner and no historical IO" do
    {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :after})
    ready = F.recover(record, config)
    definition = F.definition(trap: true, new_index: 1)

    config =
      F.config(__MODULE__, definition, barrier: {"claim", :before, self()}, lease_ms: 60_000)

    flush()
    tasks = for _ <- 1..2, do: Task.async(fn -> F.resume(ready, config, definition) end)
    assert_receive {:barrier, p1, r1, "claim", :before}, 5_000
    assert_receive {:barrier, p2, r2, "claim", :before}, 5_000
    send(p1, {r1, :release})
    send(p2, {r2, :release})
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
    assert_received :codec
    refute_received :codec
    assert_received {:model, 1}
    refute_received {:model, _}
    refute_received {:tool, _}
  end

  for operation <- ["claim", {:model, 2}, "step_output"], phase <- [:before, :after] do
    @operation operation
    @phase phase
    test "restore #{@operation |> inspect()} ACK #{@phase} retries only persistence" do
      {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :after})
      ready = F.recover(record, config)
      definition = F.definition(trap: true, new_index: 1)
      config = F.config(__MODULE__, definition, fault: {@operation, @phase}, lease_ms: 60_000)
      flush()
      result = F.resume(ready, config, definition)

      token =
        case result do
          {:error, %ExAgent.RunError{partial: partial}} -> partial.continuation_checkpoint
          {:error, {:composition_claim_failed, _, token}} -> token
        end

      assert is_map(token)
      raw = Store.scoped({Store.ETS, __MODULE__}, config.store.namespace)
      flush()
      token = token |> Jason.encode!() |> Jason.decode!()
      assert {:ok, %{replayed: replayed}} = ExAgent.Continuation.retry_checkpoint(raw, token)
      assert replayed == (@phase == :after)
      assert {:ok, %{replayed: true}} = ExAgent.Continuation.retry_checkpoint(raw, token)
      refute_received :codec
      refute_received {:model, _}
      refute_received {:tool, _}
      {:ok, saved} = Store.load_record(raw, :agent, config.id)
      assert :ok = Record.validate(saved, {raw.namespace, :agent, config.id})
    end
  end

  for mode <- ["text", "batch", "success", "retry", "fatal"] do
    @mode mode
    @tag :tmp_dir
    test "fresh OS BEAM consumes #{@mode} from JSON with no historical callbacks", c do
      opts =
        case @mode do
          "text" ->
            [fault: {"step_output", :before}]

          "batch" ->
            [fault: {"tool_resolution", :after}]

          "fatal" ->
            [output_type: F.Output, capabilities: [%F.Hooks{owner: self(), fatal: ["one"]}]]

          mode ->
            [
              output_type: F.Output,
              script: [
                F.response([F.call("one")]),
                F.output(if(mode == "success", do: 9, else: "invalid"))
              ],
              fault: {"output_resolution", :after}
            ]
        end

      opts =
        opts ++
          [
            usage: Message.Usage.partial(%Message.Usage{input_tokens: 7, output_tokens: 11}),
            root_options: [estimate_cost: fn _, _ -> 7 end],
            run_options: [estimate_cost: fn _ -> 3 end]
          ]

      {_, record, config, _} = F.capture(__MODULE__, opts)
      ready = F.recover(record, config)

      file =
        Path.join(c.tmp_dir, "frame8-tool-vm-#{System.unique_integer([:positive])}.json")

      File.write!(file, Jason.encode!(ready))
      on_exit(fn -> File.rm(file) end)
      paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

      args =
        Enum.flat_map(paths, &["-pa", &1]) ++
          ["test/support/composition_tool_restore_vm.exs", file, @mode]

      {output, exit} =
        System.cmd(System.find_executable("elixir"), args,
          stderr_to_stdout: true,
          env: [{"ERL_FLAGS", "+S 2:2"}]
        )

      assert exit == 0, output
      assert output =~ "FRAME8_RESTORE_VM #{@mode} calls=1"
    end
  end

  for phase <- [:before, :after] do
    @phase phase
    test "owner kill #{@phase} new intent preserves fences and terminates owned processes" do
      {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :after})
      ready = F.recover(record, config)
      definition = F.definition(trap: true, new_index: 1, capabilities: [%F.Hooks{owner: self()}])
      config = F.config(__MODULE__, definition, barrier: {"begin_effect", @phase, self()})
      flush()
      {owner, owner_ref} = spawn_monitor(fn -> F.resume(ready, config, definition) end)
      assert_receive {:owned, writer, scope}, 5_000
      assert_receive {:barrier, ^writer, ref, "begin_effect", @phase}, 5_000
      writer_ref = Process.monitor(writer)
      scope_ref = Process.monitor(scope)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^owner_ref, :process, ^owner, :killed}, 5_000
      send(writer, {ref, :release})
      assert_receive {:DOWN, ^writer_ref, :process, ^writer, _}, 5_000
      assert_receive {:DOWN, ^scope_ref, :process, ^scope, _}, 5_000
      {:ok, interrupted} = Store.load_record(config.store, :agent, config.id)
      recovered = F.recover(interrupted, F.config(__MODULE__, definition))

      if @phase == :after do
        assert recovered["execution"]["state"] == "uncertain"
        assert {:error, :composition_not_ready} = CompositionRestore.boundary(recovered)
      else
        assert {:ok, {:confirmed_tool_history, {:confirmed_tool_batch, _}, 0}} =
                 CompositionRestore.boundary(recovered)
      end

      refute_received {:model, _}
      refute_received {:tool, _}
    end
  end

  for fatal <- [false, true] do
    @fatal fatal
    test "Writer control seam preserves settle_error behind first fatal=#{fatal}" do
      {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :before})
      ready = F.recover(record, config)
      definition = F.definition(trap: true)
      config = F.config(__MODULE__, definition)
      {:ok, config} = ExAgent.Continuation.Writer.config(config)
      {:ok, writer, claimed} = ExAgent.Continuation.Writer.claim_composition(ready, config)
      [child] = Map.values(claimed["execution"]["progress"]["runtime"]["children"])
      frame = child["frame"]
      parts = Map.values(ExAgent.Continuation.Frame.outcomes(frame))

      run = %{
        run_id: frame["run_id"],
        model_request_id: frame["model_request_id"],
        tool_retries: frame["tool_retries"]
      }

      error = if @fatal, do: {:tool_hook_failed, "effect", :sentinel}, else: nil

      assert :ok =
               ExAgent.Continuation.Writer.tool_resolution(
                 writer,
                 run,
                 parts,
                 [{false, error}],
                 {:checkpoint_failed, :sentinel}
               )

      ExAgent.Continuation.Writer.stop(writer)
      {:ok, resolved} = Store.load_record(config.store, :agent, config.id)
      ready = F.recover(resolved, config)
      flush()
      code = if @fatal, do: "tool_hook_failed", else: "checkpoint_failed"

      assert {:error, %ExAgent.RunError{reason: %{"code" => ^code}, partial: result}} =
               F.resume(ready, config, definition)

      assert length(returns(result)) == 1
      refute_received {:model, _}
      refute_received {:tool, _}
    end
  end

  test "coherent retry-limit rewrite can decode but cannot mutate accepted Store evidence" do
    {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :before})

    assert_receive {:transition, key, revision, %{"operation" => "tool_resolution"} = command,
                    {:ok, ^record}, {:error, _}}

    {:ok, %{record: projected}} =
      ExAgent.Continuation.Transition.apply(
        record,
        key,
        revision,
        command,
        System.system_time(:millisecond)
      )

    [batch] = Map.keys(projected["execution"]["progress"]["runtime"]["tool_batches"])

    changed =
      put_in(
        projected,
        [
          "execution",
          "progress",
          "runtime",
          "tool_batches",
          batch,
          "limits",
          "effect",
          "max_retries"
        ],
        2
      )

    assert {:ok, ^changed} = Record.decode(Jason.encode!(changed), key)
    changed_command = put_in(command, ["payload", "progress"], changed["execution"]["progress"])
    raw = Store.scoped({Store.ETS, __MODULE__}, config.store.namespace)
    assert {:error, _} = Store.transition(raw, :agent, config.id, revision, changed_command)
    assert {:ok, ^record} = Store.load_record(raw, :agent, config.id)
    assert {:ok, _} = Store.transition(raw, :agent, config.id, revision, command)
  end

  for operation <- [{:model, 2}, "step_output"] do
    @operation operation
    test "restore #{@operation |> inspect()} token and JSON+cleanup and receipts exact plus-minus one" do
      {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :after})
      ready = F.recover(record, config)
      definition = F.definition(trap: true, new_index: 1)
      config = F.config(__MODULE__, definition, fault: {@operation, :before}, lease_ms: 60_000)
      assert {:error, %ExAgent.RunError{partial: partial}} = F.resume(ready, config, definition)
      token = partial.continuation_checkpoint
      assert is_map(token)
      {:ok, current} = Store.load_record(config.store, :agent, config.id)
      raw = Store.scoped({Store.ETS, __MODULE__}, config.store.namespace)
      key = {raw.namespace, :agent, config.id}
      [run] = Map.keys(token["command"]["payload"]["progress"]["runtime"]["children"])

      path = [
        "command",
        "payload",
        "progress",
        "runtime",
        "children",
        run,
        "snapshot",
        "metadata",
        "padding"
      ]

      base = put_in(token, path, "")
      padding = Record.max_bytes() - ExAgent.Retention.bytes(base)

      for delta <- [-1, 0, 1] do
        candidate = put_in(base, path, String.duplicate("x", padding + delta))
        assert ExAgent.Retention.bytes(candidate) == Record.max_bytes() + delta
        assert {:error, reason} = ExAgent.Continuation.retry_checkpoint(raw, candidate)

        if delta == 1,
          do: assert(reason == :invalid_checkpoint_token),
          else: refute(reason == :invalid_checkpoint_token)

        assert {:ok, ^current} = Store.load_record(raw, :agent, config.id)
      end

      flush()

      assert {:ok, %{record: saved, replayed: false}} =
               ExAgent.Continuation.retry_checkpoint(raw, token)

      assert {:ok, %{replayed: true}} = ExAgent.Continuation.retry_checkpoint(raw, token)
      refute_received {:model, _}
      refute_received {:tool, _}
      sample = saved["receipts"] |> Map.values() |> hd()
      count = 1024 - Record.receipt_reserve(saved["execution"])

      for delta <- [-1, 0, 1] do
        candidate = %{
          saved
          | "receipts" => Map.new(1..(count + delta), &{"r#{&1}", sample}),
            "revision" => count + delta
        }

        if delta == 1,
          do: assert(match?({:error, _}, Record.encode(candidate, key))),
          else: assert(match?({:ok, _}, Record.encode(candidate, key)))
      end

      path = [
        "execution",
        "progress",
        "runtime",
        "children",
        run,
        "snapshot",
        "metadata",
        "padding"
      ]

      base = put_in(saved, path, "")

      padding =
        Record.max_bytes() - byte_size(Jason.encode!(base)) - Record.cleanup_reserve_bytes(base)

      for delta <- [-1, 0, 1] do
        candidate = put_in(base, path, String.duplicate("x", padding + delta))

        assert byte_size(Jason.encode!(candidate)) + Record.cleanup_reserve_bytes(candidate) ==
                 Record.max_bytes() + delta

        if delta == 1,
          do: assert(Record.encode(candidate, key) == {:error, :record_limit}),
          else: assert(match?({:ok, _}, Record.encode(candidate, key)))
      end
    end
  end

  test "legacy7 tools remain blocked using unmodified historical bytes" do
    file = "test/fixtures/continuation/frame7_evidence/frame7-tools-current.json"
    record = file |> File.read!() |> Jason.decode!()
    [ns, _, id] = record["key"]
    assert :ok = Record.validate(record, {ns, :agent, id})

    command = %{
      "record_id" => record["record_id"],
      "operation" => "recover",
      "operation_id" => "legacy-recover",
      "actor_id" => "host",
      "payload" => %{}
    }

    assert {:ok, %{record: ready}} =
             ExAgent.Continuation.Transition.apply(
               record,
               {ns, :agent, id},
               record["revision"],
               command,
               record["execution"]["lease_until"] + 1
             )

    assert {:error, :unsupported_composition_boundary} = CompositionRestore.boundary(ready)
  end

  test "reverse task finish order retains Model call order and retry reset on restore" do
    parent = self()
    script = [F.response([F.call("retry", "retry"), F.call("success")]), F.text()]

    task =
      Task.async(fn ->
        F.capture(__MODULE__,
          script: script,
          owner: parent,
          tool_barrier: true,
          capabilities: [%F.Hooks{owner: parent}],
          fault: {"tool_resolution", :after}
        )
      end)

    assert_receive {:tool_barrier, p1, %{"action" => "retry"}}, 5_000
    assert_receive {:tool_barrier, p2, %{"action" => "success"}}, 5_000
    send(p2, :release)
    assert_receive {:tool_hook, :after, "success"}, 5_000
    send(p1, :release)
    {_, record, config, _} = Task.await(task, 5_000)
    ready = F.recover(record, config)

    definition =
      F.definition(
        script: script,
        trap: true,
        new_index: 1,
        capabilities: [%F.Hooks{owner: parent}]
      )

    flush()
    assert {:ok, result} = F.resume(ready, F.config(__MODULE__, definition), definition)
    assert Enum.map(returns(result), & &1.tool_call_id) == ["retry", "success"]
    assert_received {:hook, :before, false, %{tool_retries: %{}, tool_calls: 2}, 2}
    refute_received {:tool, _}
  end

  test "kill during new Model IO leaves uncertainty and terminates Model Writer and Scope" do
    {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :after})
    ready = F.recover(record, config)
    parent = self()

    blocked = fn _, _ ->
      send(parent, {:model_waiting, self()})

      receive do
        :release -> F.text()
      end
    end

    definition =
      F.definition(
        script: [F.text(), blocked],
        trap: true,
        new_index: 1,
        capabilities: [%F.Hooks{owner: parent}]
      )

    config = F.config(__MODULE__, definition)
    flush()
    {owner, monitor} = spawn_monitor(fn -> F.resume(ready, config, definition) end)
    assert_receive {:owned, writer, scope}, 5_000
    assert_receive {:model_waiting, model}, 5_000
    refs = for pid <- Enum.uniq([writer, scope, model]), do: {pid, Process.monitor(pid)}
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 5_000

    for {pid, ref} <- refs do
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5_000
    end

    {:ok, interrupted} = Store.load_record(config.store, :agent, config.id)
    recovered = F.recover(interrupted, config)
    assert recovered["execution"]["state"] == "uncertain"
    flush()
    assert {:error, :composition_not_ready} = F.resume(recovered, config, definition)
    refute_received {:model, _}
    refute_received {:tool, _}
  end

  test "new intent admission J threshold is exact under real restore commands" do
    {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :after})
    ready = F.recover(record, config)
    definition = F.definition(trap: true, new_index: 1)
    config = F.config(__MODULE__, definition, fault: {{:model, 2}, :before}, lease_ms: 60_000)
    key = {config.store.namespace, :agent, config.id}
    {:ok, physical} = Record.key(key)
    {:ok, bytes} = Record.encode(ready, key)
    # Each candidate is an isolated restoration of the same authentic backup;
    # actual claim/admission/CAS and retention run for every candidate.
    trial = fn limit ->
      :ets.insert(__MODULE__, {physical, bytes})
      flush()
      result = F.resume(ready, %{config | max_checkpoint_bytes: limit}, definition)
      refute_received {:model, _}
      refute_received {:tool, _}

      case result do
        {:error,
         %ExAgent.RunError{
           partial: %{
             continuation_checkpoint: %{"command" => %{"operation" => "begin_effect"}} = token
           }
         }} ->
          {:admitted, token}

        {:error, _} ->
          :rejected
      end
    end

    exact = bisect(1, 300_000, fn n -> match?({:admitted, _}, trial.(n)) end)
    assert :rejected = trial.(exact - 1)
    assert {:admitted, token} = trial.(exact)
    assert ExAgent.Retention.bytes(token) <= exact
    assert {:admitted, _} = trial.(exact + 1)

    IO.puts(
      "FRAME8_RESTORE_J exact=#{exact} token=#{ExAgent.Retention.bytes(token)} minus_one=#{exact - 1}"
    )
  end

  test "current retry extends previous counter exactly once as observed by both protected hooks" do
    script = [
      F.response([F.call("same", "retry")]),
      F.response([F.call("same", "retry")]),
      F.text()
    ]

    fault = fn command ->
      batches = get_in(command, ["payload", "progress", "runtime", "tool_batches"]) || %{}

      if command["operation"] == "tool_resolution" and map_size(batches) == 2,
        do: {"tool_resolution", :after}
    end

    {_, record, config, _} = F.capture(__MODULE__, script: script, max_retries: 3, fault: fault)
    ready = F.recover(record, config)

    definition =
      F.definition(
        script: script,
        max_retries: 3,
        trap: true,
        new_index: 2,
        capabilities: [
          %F.Hooks{owner: self(), mutate: true},
          %F.Hooks{owner: self(), mutate: false}
        ]
      )

    flush()
    assert {:ok, %{tool_calls: 2}} = F.resume(ready, F.config(__MODULE__, definition), definition)

    for phase <- [:before, :after] do
      assert_received {:hook, ^phase, false,
                       %{tool_calls: 2, tool_retries: %{"effect" => 2}, run_step: 3}, 2}
    end

    refute_received {:tool, _}
  end

  test "multiple interruptions consume each current batch once and preserve prior control" do
    script = [F.response([F.call("same")]), F.response([F.call("same", "second")]), F.text()]

    {_, record, config, _} =
      F.capture(__MODULE__, script: script, fault: {"tool_resolution", :after})

    ready = F.recover(record, config)
    definition = F.definition(script: script, trap: true, new_index: 1, allow_actions: ["second"])
    fault_config = F.config(__MODULE__, definition, fault: {"tool_resolution", :after})
    flush()

    assert {:error, %ExAgent.RunError{partial: partial}} =
             F.resume(ready, fault_config, definition)

    assert_received {:tool, %{"action" => "second"}}
    refute_received {:tool, _}
    raw = Store.scoped({Store.ETS, __MODULE__}, config.store.namespace)
    flush()

    assert {:ok, %{record: second, replayed: true}} =
             ExAgent.Continuation.retry_checkpoint(raw, partial.continuation_checkpoint)

    refute_received {:tool, _}
    refute_received {:model, _}
    ready = F.recover(second, F.config(__MODULE__, definition))
    definition = F.definition(script: script, trap: true, new_index: 2)
    flush()

    assert {:ok, %{tool_calls: 2, request_count: 3} = result} =
             F.resume(ready, F.config(__MODULE__, definition), definition)

    assert Enum.map(returns(result), & &1.tool_call_id) == ["same", "same"]
    refute_received {:tool, _}
    assert_received {:model, 2}
    refute_received {:model, _}
  end

  test "output siblings are consumed as attested data and never counted as function calls" do
    output = %{F.output(9) | parts: F.output(9).parts ++ [F.call("skipped1"), F.call("skipped2")]}
    script = [F.response([F.call("one")]), output]

    {_, record, config, _} =
      F.capture(__MODULE__,
        script: script,
        output_type: F.Output,
        fault: {"output_resolution", :after}
      )

    ready = F.recover(record, config)
    definition = F.definition(script: script, output_type: F.Output, trap: true)
    flush()
    Process.put(:tool_restore_schema_trap, true)

    assert {:ok, %{tool_calls: 1} = result} =
             F.resume(ready, F.config(__MODULE__, definition), definition)

    assert Enum.map(returns(result), & &1.status) == [
             :succeeded,
             :succeeded,
             :not_executed,
             :not_executed
           ]

    refute_received {:tool, _}
    refute_received {:model, _}
  end

  test "selection retires after append so NEW failed response gets only its own stubs" do
    script = [F.response([F.call("old")]), F.response([F.call("new")])]

    {_, record, config, _} =
      F.capture(__MODULE__, script: script, fault: {"tool_resolution", :after})

    ready = F.recover(record, config)

    definition =
      F.definition(
        script: script,
        trap: true,
        new_index: 1,
        capabilities: [%F.Hooks{owner: self(), fail_after: 2}]
      )

    flush()

    assert {:error, %ExAgent.RunError{partial: partial}} =
             F.resume(ready, F.config(__MODULE__, definition), definition)

    assert Enum.map(returns(partial), &{&1.tool_call_id, &1.status}) == [
             {"old", :succeeded},
             {"new", :not_executed}
           ]

    refute_received {:tool, _}
  end

  for place <- [:root, :leaf] do
    @place place
    test "original #{@place} exhausted request limit cannot be widened for new drive" do
      limits = %ExAgent.UsageLimits{request_limit: 1}
      opts = [fault: {"tool_resolution", :after}]

      opts =
        if @place == :root,
          do: Keyword.put(opts, :root_options, usage_limits: limits),
          else: Keyword.put(opts, :usage_limits, limits)

      {_, record, config, _} = F.capture(__MODULE__, opts)
      ready = F.recover(record, config)

      definition =
        F.definition(
          trap: true,
          new_index: 1,
          usage_limits: %ExAgent.UsageLimits{request_limit: 5}
        )

      flush()

      assert {:error, %ExAgent.RunError{partial: partial}} =
               F.resume(ready, F.config(__MODULE__, definition), definition,
                 root_options: [usage_limits: %ExAgent.UsageLimits{request_limit: 5}]
               )

      assert partial.request_count == 1
      assert length(returns(partial)) == 1
      refute_received {:model, _}
      refute_received {:tool, _}
    end
  end

  test "current max_steps prevents new drive after consuming confirmed batch once" do
    {_, record, config, _} = F.capture(__MODULE__, fault: {"tool_resolution", :after})
    ready = F.recover(record, config)
    definition = F.definition(trap: true, new_index: 1, max_steps: 1)
    flush()

    assert {:error, %ExAgent.RunError{partial: partial}} =
             F.resume(ready, F.config(__MODULE__, definition), definition)

    assert partial.tool_calls == 1
    assert length(returns(partial)) == 1
    refute_received {:model, _}
    refute_received {:tool, _}
  end

  for delta <- [-1, 0, 1] do
    @delta delta
    test "output payload after consumed tool prefix exact #{@delta}" do
      {_, record, config, _} = F.capture(__MODULE__, fault: {"step_output", :before})
      ready = F.recover(record, config)
      definition = F.definition(trap: true)
      exact = ExAgent.Retention.bytes("done")
      flush()

      result =
        F.resume(ready, F.config(__MODULE__, definition), definition,
          max_payload_bytes: exact + @delta
        )

      if @delta == -1 do
        assert {:error,
                %ExAgent.RunError{
                  reason: {:retention_limit_exceeded, %{boundary: :output, bytes: ^exact}}
                }} = result
      else
        assert {:ok, %{output: "done"}} = result
      end

      refute_received {:model, _}
      refute_received {:tool, _}
    end
  end

  defp bisect(low, high, _) when low == high, do: low

  defp bisect(low, high, predicate) do
    mid = div(low + high, 2)
    if predicate.(mid), do: bisect(low, mid, predicate), else: bisect(mid + 1, high, predicate)
  end

  for mutation <- [
        :observation,
        :observation_and_operation,
        :usage,
        :control,
        :counter,
        :limits,
        :hash,
        :history
      ] do
    @mutation mutation
    test "decode and real CAS reject #{@mutation} corruption without overwriting row" do
      {_, record, config, _} =
        F.capture(__MODULE__,
          usage: %Message.Usage{input_tokens: 7, output_tokens: 11},
          fault: {"tool_resolution", :before}
        )

      assert_receive {:transition, key, revision, %{"operation" => "tool_resolution"} = command,
                      {:ok, ^record}, {:error, _}}

      progress = command["payload"]["progress"]
      changed_progress = corrupt(progress, @mutation)
      bad_command = put_in(command, ["payload", "progress"], changed_progress)

      {:ok, %{record: projected}} =
        ExAgent.Continuation.Transition.apply(
          record,
          key,
          revision,
          command,
          System.system_time(:millisecond)
        )

      bad_record = put_in(projected, ["execution", "progress"], changed_progress)
      assert {:error, _} = Record.decode(Jason.encode!(bad_record), key)
      raw = Store.scoped({Store.ETS, __MODULE__}, config.store.namespace)
      assert {:error, _} = Store.transition(raw, :agent, config.id, revision, bad_command)
      assert {:ok, ^record} = Store.load_record(raw, :agent, config.id)
      assert {:ok, %{record: saved}} = Store.transition(raw, :agent, config.id, revision, command)

      assert {:ok, %{replayed: true, record: ^saved}} =
               Store.transition(raw, :agent, config.id, revision, command)

      stale = %{command | "operation_id" => command["operation_id"] <> "-stale"}
      assert {:error, :conflict} = Store.transition(raw, :agent, config.id, revision, stale)
    end
  end

  defp corrupt(progress, mutation) do
    root = progress["runtime"]
    [{batch_id, batch}] = Map.to_list(root["tool_batches"])
    [{effect, observation}] = Map.to_list(batch["observations"])
    [run] = Map.keys(root["children"])

    case mutation do
      :observation ->
        put_in(progress, ["runtime", "tool_batches", batch_id, "observations"], %{})

      :observation_and_operation ->
        progress
        |> put_in(["runtime", "tool_batches", batch_id, "observations"], %{})
        |> update_in(
          ["runtime", "scope", "operations"],
          &Enum.reject(&1, fn op -> hd(op["id"]) == "tool" end)
        )

      :usage ->
        put_in(
          progress,
          ["runtime", "tool_batches", batch_id, "observations", effect, "usage", "input_tokens"],
          observation["usage"]["input_tokens"] + 1
        )

      :control ->
        put_in(progress, ["runtime", "tool_batches", batch_id, "resolution", "calls"], [])

      :counter ->
        put_in(progress, ["runtime", "children", run, "frame", "tool_retries"], %{"effect" => 1})

      :limits ->
        put_in(
          progress,
          ["runtime", "tool_batches", batch_id, "limits", "effect", "schema_hash"],
          String.duplicate("0", 64)
        )

      :hash ->
        update_in(progress, ["runtime", "tool_batches", batch_id, "resolution", "calls"], fn [c] ->
          [%{c | "result_hash" => String.duplicate("0", 64)}]
        end)

      :history ->
        update_in(
          progress,
          ["runtime", "children", run, "snapshot", "message_history"],
          &String.replace(&1, "success", "changed")
        )
    end
  end

  defp returns(result) do
    for %Message.Request{parts: parts} <- result.messages,
        part <- parts,
        is_struct(part, Message.Part.ToolReturn) or is_struct(part, Message.Part.Retry),
        do: part
  end

  for kind <- [:unknown_tool, :omitted_return, :unavailable_model] do
    @kind kind
    test "authentic #{@kind} evidence remains nonexecutable before codecs" do
      opts =
        case @kind do
          :unknown_tool ->
            [tool_failure: true]

          :omitted_return ->
            [value: String.duplicate("x", 6_000), run_options: [max_payload_bytes: 4_096]]

          :unavailable_model ->
            [unavailable_at: 2]
        end

      {_, record, config, _} = F.capture(__MODULE__, opts)
      ready = F.recover(record, config)
      assert :ok = Record.validate(ready, {config.store.namespace, :agent, config.id})
      definition = F.definition(trap: true)
      flush()

      reason =
        if @kind == :unavailable_model do
          assert ready["execution"]["state"] == "ready"
          :unsupported_composition_boundary
        else
          assert ready["execution"]["state"] == "uncertain"
          :composition_not_ready
        end

      assert {:error, ^reason} =
               F.resume(ready, F.config(__MODULE__, definition), definition)

      refute_received :codec
      refute_received :mapping
      refute_received {:model, _}
      refute_received {:tool, _}
    end
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
