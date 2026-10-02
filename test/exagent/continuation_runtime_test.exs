defmodule ExAgent.ContinuationRuntimeTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, Permissions, Store, Tool}
  alias ExAgent.Message.{Part, Response}

  defmodule EffectiveArgs do
    use ExAgent.Capability
    defstruct [:args]
    def before_tool_execute(%{args: args}, _, call), do: %{call | args: args}
  end

  defmodule AfterTool do
    use ExAgent.Capability
    defstruct [:owner, :mode]

    def after_tool_execute(hook, _, %{tool_name: "first"}, {:ok, part}) do
      send(hook.owner, :after_first)

      case hook.mode do
        :transform ->
          {:ok, %{part | content: "transformed"}}

        :fail ->
          raise "after hook failed"

        :block ->
          receive do
            :continue_hook -> {:ok, part}
          end

        :large ->
          {:ok, %{part | content: String.duplicate("h", 200_000)}}

        :identity ->
          {:ok, part}
      end
    end

    def after_tool_execute(_, _, _, result), do: result
  end

  defmodule TypedOutput do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key false
    embedded_schema do
      field(:count, :integer)
    end

    def changeset(data, args),
      do:
        data
        |> cast(args, [:count])
        |> validate_required([:count])
        |> validate_number(:count, greater_than: 0)
  end

  defmodule NativeModel do
    @behaviour ExAgent.Model
    defstruct [:owner, script: [], index: 0]
    def model_name(_), do: "native-fixture"
    def system(_), do: "synthetic"

    def profile(_),
      do: %ExAgent.ModelProfile{supports_tools: true, supports_json_schema_output: true}

    def validate_resume(_, _, _, _), do: :ok

    def request(model, messages, settings, params) do
      send(model.owner, {:native_request, model.index})

      {:ok, response, next} =
        ExAgent.Models.Test.request(
          %ExAgent.Models.Test{script: model.script, index: model.index},
          messages,
          settings,
          params
        )

      {:ok, response, %{model | index: next.index}}
    end
  end

  defmodule NoResumeModel do
    @behaviour ExAgent.Model
    defstruct [:owner, index: 0]
    def model_name(_), do: "no-resume"
    def system(_), do: "custom"

    def request(model, _, _, _) do
      send(model.owner, :unsupported_model_io)
      {:ok, %Response{parts: [%Part.Text{content: "ordinary"}]}, model}
    end
  end

  defmodule FaultStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record({table, _}, key), do: Store.ETS.load_record(table, key)

    def scan_records({table, _}, namespace, query),
      do: Store.ETS.scan_records(table, namespace, query)

    def transition({table, fault}, key, revision, command) do
      mode =
        Agent.get_and_update(fault, fn
          {op, mode} = fault ->
            matches =
              command["operation"] == op or
                (op == :tool_outcome and
                   command["operation"] == "outcome" and
                   String.starts_with?(command["payload"]["effect_id"], "tool-"))

            if matches, do: {mode, :ok}, else: {:ok, fault}

          :ok ->
            {:ok, :ok}
        end)

      case mode do
        :before ->
          {:error, :save_failed}

        :after ->
          {:ok, _} = Store.ETS.transition(table, key, revision, command)
          {:error, :ack_lost}

        :ok ->
          Store.ETS.transition(table, key, revision, command)
      end
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "runtime")}
  end

  test "root pause releases its processes and resume restores model cursor and exact accounting",
       %{store: store} do
    owner = self()
    agent = agent(owner)
    config = config(store)
    opts = [continuation: config, permissions: Permissions.new!(default: :ask)]
    task = Task.async(fn -> ExAgent.run(agent, "synthetic", opts) end)
    assert {:ok, paused} = Task.await(task)
    assert paused.status == :paused
    assert paused.output == nil
    assert paused.request_count == 1
    assert paused.tool_calls == 1
    assert_receive :model_first
    refute_receive :effect
    refute Process.alive?(task.pid)
    assert {:ok, %{status: :pending, record: record}} = Continuation.get(store, "conversation")
    assert record["execution"]["progress"]["runtime"]["frame_version"] == 3
    assert record["execution"]["progress"]["runtime"]["scope"]["scope_version"] == 2
    assert record["execution"]["owner_id"] == nil
    refute Jason.encode!(record) =~ "#PID"
    reference = approve(store, record, paused.continuation)
    assert {:ok, result} = ExAgent.resume(agent, reference, opts)
    assert result.status == :succeeded
    assert result.output == "done"
    assert result.run_id == paused.run_id
    assert is_binary(paused.attempt_id) and is_binary(result.attempt_id)
    assert result.attempt_id != paused.attempt_id
    assert result.request_count == 2
    assert result.tool_calls == 1
    assert_receive :effect
    assert_receive :model_second
    refute_receive :model_first
    refute_receive :effect
    assert {:ok, %{status: :completed}} = Continuation.get(store, "conversation")
  end

  test "accepted root1 bytes resume without replay and the next checkpoint writes scope2", %{
    store: store
  } do
    # Actual paused bytes emitted by the accepted f394 Frame/Writer in another VM,
    # not a downcast manufactured from the new frame2 writer.
    record =
      File.read!(Path.expand("../fixtures/continuation-root1-f394.json", __DIR__))
      |> Jason.decode!()

    assert record["execution"]["progress"]["runtime"]["frame_version"] == 1
    import_record(store, record)

    reference = %{
      id: "conversation",
      record_id: record["record_id"],
      revision: record["revision"]
    }

    reference = approve(store, record, reference)

    assert {:ok, result} =
             ExAgent.resume(agent(self()), reference,
               continuation: config(store),
               permissions: Permissions.new!(default: :ask)
             )

    assert result.status == :succeeded
    assert result.request_count == 2
    assert result.tool_calls == 1
    assert_receive :effect
    assert_receive :model_second
    refute_receive :model_first
    refute_receive :effect
    assert {:ok, %{record: completed}} = Continuation.get(store, "conversation")
    assert completed["execution"]["progress"]["runtime"]["frame_version"] == 3
    assert completed["execution"]["progress"]["runtime"]["scope"]["scope_version"] == 2
  end

  test "scope2 graph corruption and root1 downcast reject before host rehydration", %{
    store: store
  } do
    owner = self()
    opts = [continuation: config(store), permissions: Permissions.new!(default: :ask)]
    {:ok, paused} = ExAgent.run(agent(owner), "synthetic", opts)
    assert_receive :model_first
    {:ok, %{record: pending}} = Continuation.get(store, "conversation")
    reference = approve(store, pending, paused.continuation)
    {:ok, %{record: record}} = Continuation.get(store, "conversation")
    scope = record["execution"]["progress"]["runtime"]["scope"]
    [operation] = scope["operations"]
    root = scope["root_run_id"]
    path = ["execution", "progress", "runtime"]

    broken_scopes = [
      put_in(scope, ["nodes", root, "parent_run_id"], root),
      put_in(scope, ["nodes", root, "parent_run_id"], "absent"),
      put_in(scope, ["nodes", root, "requests"], 0),
      Map.put(scope, "operations", [operation, operation]),
      Map.put(scope, "operations", [Map.put(operation, "ancestors", %{})]),
      Map.put(scope, "batches", scope["batches"] ++ scope["batches"])
    ]

    corruptions =
      Enum.map(broken_scopes, &put_in(record, path ++ ["scope"], &1)) ++
        [put_in(record, path ++ ["frame_version"], 1)]

    codec = config(store).model_codec

    watched =
      put_in(opts, [:continuation, :model_codec, :load], fn model, data ->
        send(owner, :rehydrated)
        codec.load.(model, data)
      end)

    for corrupt <- corruptions do
      import_record(store, corrupt)

      assert {:error, %{reason: :invalid_continuation_frame}} =
               ExAgent.resume(agent(owner), reference, watched)

      refute_receive :rehydrated
      refute_receive :effect
      refute_receive :model_second
    end

    import_record(store, record)
    assert {:ok, %{status: :succeeded}} = ExAgent.resume(agent(owner), reference, watched)
    assert_receive :rehydrated
    assert_receive :effect
    assert_receive :model_second
  end

  test "definition or effective schema change cannot spend a persisted approval", %{store: store} do
    agent = agent(self())
    opts = [continuation: config(store), permissions: Permissions.new!(default: :ask)]
    {:ok, paused} = ExAgent.run(agent, "synthetic", opts)
    {:ok, %{record: record}} = Continuation.get(store, "conversation")
    reference = approve(store, record, paused.continuation)
    changed = put_in(opts, [:continuation, :definition, "version"], "2")

    assert {:error, %{reason: :continuation_definition_changed}} =
             ExAgent.resume(agent, reference, changed)

    tool = hd(agent.tools)

    modified = %{
      agent
      | tools: [%{tool | parameters_json_schema: %{"type" => "object", "required" => ["new"]}}]
    }

    assert {:error, %{reason: :continuation_tools_changed}} =
             ExAgent.resume(modified, reference, opts)

    refute_receive :effect

    assert {:ok, %{status: :approved, record: after_record}} =
             Continuation.get(store, "conversation")

    assert after_record["revision"] == reference.revision
  end

  test "stream pause is terminal and continuation is a new lazy stream", %{store: store} do
    agent = agent(self())
    opts = [continuation: config(store), permissions: Permissions.new!(default: :ask)]
    stream = ExAgent.run_stream(agent, "synthetic", opts)
    refute_receive :model_first
    assert [{:result, %{status: :paused} = paused}] = Enum.to_list(stream)
    {:ok, %{record: r}} = Continuation.get(store, "conversation")
    reference = approve(store, r, paused.continuation)
    next = ExAgent.resume_stream(agent, reference, opts)
    refute_receive :effect
    events = Enum.to_list(next)

    assert [{:result, %{status: :succeeded, output: "done"}}] =
             Enum.filter(events, &match?({:result, _}, &1))

    assert_receive :effect
    refute_receive :effect
  end

  test "two resumers cross a restore barrier but only one dispatches", %{store: store} do
    owner = self()
    agent = agent(owner)
    cfg = config(store)
    opts = [continuation: cfg, permissions: Permissions.new!(default: :ask)]
    {:ok, paused} = ExAgent.run(agent, "synthetic", opts)
    {:ok, %{record: r}} = Continuation.get(store, "conversation")
    reference = approve(store, r, paused.continuation)
    load = cfg.model_codec.load

    cfg =
      put_in(cfg, [:model_codec, :load], fn model, data ->
        send(owner, {:loaded, self()})

        receive do
          :go -> load.(model, data)
        end
      end)

    tasks =
      for _ <- 1..2,
          do:
            Task.async(fn ->
              ExAgent.resume(agent, reference, Keyword.put(opts, :continuation, cfg))
            end)

    assert_receive {:loaded, a}
    assert_receive {:loaded, b}
    send(a, :go)
    send(b, :go)
    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, %{status: :succeeded}}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
    assert_receive :effect
    refute_receive :effect
  end

  test "current permission can deny a previously approved exact call", %{store: store} do
    agent = agent(self())
    opts = [continuation: config(store), permissions: Permissions.new!(default: :ask)]
    {:ok, paused} = ExAgent.run(agent, "synthetic", opts)
    {:ok, %{record: r}} = Continuation.get(store, "conversation")
    reference = approve(store, r, paused.continuation)

    assert {:ok, result} =
             ExAgent.resume(
               agent,
               reference,
               Keyword.put(opts, :permissions, Permissions.new!(default: :deny))
             )

    assert result.status == :succeeded
    refute_receive :effect

    assert Enum.any?(result.messages, fn
             %ExAgent.Message.Request{parts: parts} ->
               Enum.any?(parts, &match?(%Part.ToolReturn{status: :denied}, &1))

             _ ->
               false
           end)
  end

  test "failed pause save exposes exact data-only retry without another model/tool call", %{
    store: store
  } do
    for mode <- [:before, :after] do
      id = "conversation-#{mode}"
      {:ok, fault} = Agent.start_link(fn -> {"pause", mode} end)
      faulty = Store.scoped({FaultStore, {__MODULE__, fault}}, "runtime")
      cfg = %{config(faulty) | id: id}
      opts = [continuation: cfg, permissions: Permissions.new!(default: :ask)]
      base = agent(self())

      bound = %{
        base
        | model: %ExAgent.ContinuationBindingModel{
            script: base.model.script,
            binding: %{"mode" => "none"},
            observer: self()
          }
      }

      assert {:error, error} = ExAgent.run(bound, "synthetic", opts)
      token = error.partial.continuation_checkpoint
      assert is_map(token)
      assert token["command"]["operation"] == "pause"
      assert error.partial.status == :failed
      assert_receive :model_first
      refute_receive :effect
      assert drain_binding_calls() > 0

      assert token["command"]["payload"]["progress"]["runtime"]["model_binding"] == %{
               "mode" => "none"
             }

      assert {:ok, %{record: paused}} = Continuation.retry_checkpoint(store, token)
      assert paused["execution"]["state"] == "pending"

      assert {:ok, %{record: ^paused, replayed: true}} =
               Continuation.retry_checkpoint(store, token)

      refute_receive :model_first
      refute_receive :effect
      refute_receive :binding_called, 0
      Agent.stop(fault)
    end
  end

  test "confirmed sibling is not replayed when its pending batch sibling resumes", %{store: store} do
    owner = self()

    first =
      Tool.new(
        name: "first",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :first_effect)
          {:ok, "first saved"}
        end
      )

    second =
      Tool.new(
        name: "second",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :second_effect)
          {:ok, "second saved"}
        end
      )

    model = %ExAgent.Models.Test{
      script: [
        {:tool_calls,
         [
           %Part.ToolCall{tool_name: "first", tool_call_id: "a", args: %{}},
           %Part.ToolCall{tool_name: "second", tool_call_id: "b", args: %{}}
         ]},
        "done"
      ]
    }

    agent = ExAgent.new(model: model, tools: [first, second])

    opts = [
      continuation: config(store),
      permissions: Permissions.new!(default: :allow, rules: [{"second", :ask}])
    ]

    assert {:ok, %{status: :paused} = paused} = ExAgent.run(agent, "batch", opts)
    assert_receive :first_effect
    refute_receive :second_effect
    {:ok, %{record: r}} = Continuation.get(store, "conversation")
    assert map_size(r["execution"]["progress"]["runtime"]["outcomes"]) == 1
    ref = approve(store, r, paused.continuation)
    assert {:ok, result} = ExAgent.resume(agent, ref, opts)
    assert result.tool_calls == 2
    assert result.request_count == 2
    assert_receive :second_effect
    refute_receive :first_effect
    refute_receive :second_effect
  end

  test "owner death during an effect requires host reconciliation and never replays confirmed IO",
       %{store: store} do
    owner = self()
    {:ok, journal} = Agent.start_link(fn -> 0 end)

    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          Agent.update(journal, &(&1 + 1))
          send(owner, {:effect_entered, self()})

          receive do
            :finish -> {:ok, "saved"}
          end
        end
      )

    original = agent(owner)
    original = %{original | tools: [tool]}
    cfg = %{config(store) | active_time_limit_ms: nil, lease_ms: 500}
    opts = [continuation: cfg]
    {pid, monitor} = spawn_monitor(fn -> ExAgent.run(original, "crash", opts) end)
    assert_receive {:effect_entered, task}, 2_000
    task_monitor = Process.monitor(task)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    assert_receive {:DOWN, ^task_monitor, :process, ^task, _}, 2_000
    {:ok, %{record: r}} = Continuation.get(store, "conversation")
    wait_until(r["execution"]["lease_until"])

    assert {:ok, %{record: uncertain}} =
             Continuation.recover(store, "conversation", administrative(r, "recover"))

    assert uncertain["execution"]["state"] == "uncertain"

    [{effect_id, _}] =
      Enum.filter(uncertain["execution"]["effects"], fn {_, e} ->
        e["intent"]["kind"] == "tool"
      end)

    assert {:ok, %{record: ready}} =
             Continuation.reconcile(
               store,
               "conversation",
               effect_id,
               %{"status" => "succeeded", "data" => "saved"},
               administrative(uncertain, "reconcile")
             )

    ref = %{id: "conversation", record_id: ready["record_id"], revision: ready["revision"]}
    assert {:ok, %{status: :succeeded}} = ExAgent.resume(original, ref, opts)
    assert Agent.get(journal, & &1) == 1
    Agent.stop(journal)
  end

  @tag timeout: 60_000
  test "new VM resumes only from disk bytes and a newly constructed trusted definition" do
    dir = Path.join(System.tmp_dir!(), "exagent-r5-vm-#{System.unique_integer([:positive])}")
    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    elixir = System.find_executable("elixir")
    paths = Path.wildcard(Path.join([File.cwd!(), "_build", "test", "lib", "*", "ebin"]))
    beam_args = Enum.flat_map(paths, &["-pa", &1])

    common =
      [
        "-i",
        "HOME=" <> System.user_home!(),
        "PATH=" <> System.get_env("PATH"),
        "LANG=C.UTF-8",
        "ERL_FLAGS=+S 8:8",
        "EXAGENT_OFFLINE=1",
        elixir
      ] ++
        beam_args ++
        ["test/support/continuation_restart_probe.exs"]

    {pause_output, 0} =
      System.cmd("/usr/bin/env", common ++ ["pause", dir], stderr_to_stdout: true)

    assert pause_output =~ "PAUSED_ACK"
    assert File.read!(Path.join(dir, "effects.txt")) == "model-first\n"

    {resume_output, 0} =
      System.cmd("/usr/bin/env", common ++ ["resume", dir], stderr_to_stdout: true)

    assert resume_output =~ "RESUMED_ONCE"
    assert File.read!(Path.join(dir, "effects.txt")) == "model-first\neffect\nmodel-second\n"
  end

  test "human wait does not debit active time and resume does not replenish the remaining balance",
       %{store: store} do
    cfg = %{config(store) | active_time_limit_ms: 1_000}
    opts = [continuation: cfg, permissions: Permissions.new!(default: :ask)]
    agent = agent(self())
    {:ok, paused} = ExAgent.run(agent, "wait", opts)
    {:ok, %{record: before_wait}} = Continuation.get(store, "conversation")
    balance = before_wait["execution"]["progress"]["active_budget"]["remaining_ms"]
    assert balance > 0 and balance <= 1_000
    # Deliberate human-wait stimulus exceeds the entire active-time allocation.
    receive do
    after
      1_100 -> :ok
    end

    {:ok, %{record: after_wait}} = Continuation.get(store, "conversation")
    assert after_wait["execution"]["progress"]["active_budget"]["remaining_ms"] == balance
    ref = approve(store, after_wait, paused.continuation)
    assert {:ok, %{status: :succeeded}} = ExAgent.resume(agent, ref, opts)
    {:ok, %{record: finished}} = Continuation.get(store, "conversation")
    assert finished["execution"]["progress"]["active_budget"]["remaining_ms"] <= balance
  end

  test "owner killed after claim but before model IO cannot recover free active time", %{
    store: store
  } do
    owner = self()
    cfg = %{config(store) | lease_ms: 500, active_time_limit_ms: 1_000}

    opts = [
      continuation: cfg,
      on_event: fn
        %{type: :run_started} ->
          send(owner, :claimed_before_io)

          receive do
            :go -> :ok
          end

        _ ->
          :ok
      end
    ]

    {pid, monitor} = spawn_monitor(fn -> ExAgent.run(agent(owner), "kill", opts) end)
    assert_receive :claimed_before_io, 2_000
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    {:ok, %{record: r}} = Continuation.get(store, "conversation")
    assert r["execution"]["effects"] == %{}
    assert r["execution"]["progress"]["active_budget"]["remaining_ms"] == 0
    wait_until(r["execution"]["lease_until"])

    {:ok, %{record: ready}} =
      Continuation.recover(store, "conversation", administrative(r, "recover"))

    assert ready["execution"]["state"] == "ready"
    ref = %{id: "conversation", record_id: ready["record_id"], revision: ready["revision"]}

    assert {:error, %{reason: {:continuation_checkpoint_failed, :active_budget_exhausted}}} =
             ExAgent.resume(agent(owner), ref, continuation: cfg)

    refute_receive :model_first
    refute_receive :effect
  end

  test "restored qualified ledger is not repriced and retains original request budget", %{
    store: store
  } do
    owner = self()
    {:ok, prices} = Agent.start_link(fn -> 0 end)

    price = fn _ ->
      Agent.update(prices, &(&1 + 1))
      1.25
    end

    a = agent(owner)
    usage = %ExAgent.Message.Usage{input_tokens: 3, output_tokens: 2}

    model = %ExAgent.Models.Test{
      script: [
        %Response{
          parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}],
          usage: usage
        },
        %Response{parts: [%Part.Text{content: "done"}], usage: usage}
      ]
    }

    a = %{a | model: model, usage_limits: %ExAgent.UsageLimits{request_limit: 2}}

    opts = [
      continuation: config(store),
      permissions: Permissions.new!(default: :ask),
      estimate_cost: price
    ]

    {:ok, paused} = ExAgent.run(a, "accounting", opts)
    assert paused.cost_cents == 1.25
    assert Agent.get(prices, & &1) == 1
    {:ok, %{record: r}} = Continuation.get(store, "conversation")
    ref = approve(store, r, paused.continuation)

    {:ok, result} =
      ExAgent.resume(%{a | usage_limits: %ExAgent.UsageLimits{request_limit: 100}}, ref, opts)

    assert result.cost_cents == 2.5
    assert result.usage.input_tokens == 6
    assert result.request_count == 2
    assert Agent.get(prices, & &1) == 2
    assert result.usage.accounting["cost"]["quality"] == "estimated"
    Agent.stop(prices)
  end

  test "posteffect checkpoint overflow retains success and omission, never a second model request",
       %{store: store} do
    owner = self()
    original = agent(owner)

    tool = %{
      hd(original.tools)
      | call: fn _, _ ->
          send(owner, :effect)
          {:ok, String.duplicate("x", 200_000)}
        end
    }

    original = %{original | tools: [tool]}
    cfg = Map.put(config(store), :max_checkpoint_bytes, 80_000)
    assert {:error, error} = ExAgent.run(original, "oversized", continuation: cfg)
    assert_receive :effect
    refute_receive :effect
    refute_receive :model_second

    returns =
      ExAgent.Message.parts(error.partial.messages)
      |> Enum.filter(&match?(%Part.ToolReturn{}, &1))

    assert [
             %Part.ToolReturn{
               status: :succeeded,
               content: nil,
               payload_omitted: %{"boundary" => "checkpoint"}
             }
           ] = returns

    {:ok, %{record: r}} = Continuation.get(store, "conversation")

    assert Enum.any?(r["execution"]["effects"], fn {_, e} ->
             e["intent"]["kind"] == "tool" and e["outcome"]["status"] == "succeeded"
           end)

    assert byte_size(Jason.encode!(r)) < 20_000
    assert error.partial.retention.record_bytes == :erlang.external_size(r)
    assert error.partial.retention.record_json_bytes == byte_size(Jason.encode!(r))
    assert error.partial.retention.checkpoint_bytes == 0
  end

  test "failed outcome save retries captured persistence after a real effect without replay", %{
    store: store
  } do
    for mode <- [:before, :after] do
      {:ok, fault} = Agent.start_link(fn -> {:tool_outcome, mode} end)
      faulty = Store.scoped({FaultStore, {__MODULE__, fault}}, "runtime")
      cfg = %{config(faulty) | id: "outcome-#{mode}"}
      assert {:error, error} = ExAgent.run(agent(self()), "effect then save", continuation: cfg)
      assert_receive :model_first
      assert_receive :effect
      refute_receive :model_second
      token = error.partial.continuation_checkpoint
      assert token["command"]["operation"] == "outcome"
      assert error.partial.retention.checkpoint_bytes == :erlang.external_size(token)

      measured =
        Map.take(error.partial, [
          :output,
          :messages,
          :new_messages,
          :pending_response,
          :usage,
          :continuation_checkpoint
        ])

      assert error.partial.retention.data_bytes == :erlang.external_size(measured)
      assert {:ok, %{record: record}} = Continuation.retry_checkpoint(store, token)

      assert Enum.any?(record["execution"]["effects"], fn {_, e} ->
               e["intent"]["kind"] == "tool" and e["outcome"]["status"] == "succeeded"
             end)

      assert {:ok, %{replayed: true}} = Continuation.retry_checkpoint(store, token)
      refute_receive :effect
      refute_receive :model_first
      refute_receive :model_second
      Agent.stop(fault)
    end
  end

  test "the complete dirty token is charged at exact J and J-minus-one rejects before Store IO",
       %{store: store} do
    {:ok, fault} = Agent.start_link(fn -> {"create", :before} end)
    faulty = Store.scoped({FaultStore, {__MODULE__, fault}}, "runtime")
    cfg = config(faulty)
    base = agent(self())

    original = %{
      base
      | model: %ExAgent.ContinuationBindingModel{
          script: base.model.script,
          binding: String.duplicate("x", 4094)
        }
    }

    {:error, first} = ExAgent.run(original, "token", continuation: cfg)
    token = first.partial.continuation_checkpoint
    j = :erlang.external_size(token)
    assert j > :erlang.external_size(token["command"])
    assert first.partial.retention.checkpoint_bytes == j
    Agent.update(fault, fn _ -> {"create", :before} end)

    {:error, exact} =
      ExAgent.run(original, "token", continuation: Map.put(cfg, :max_checkpoint_bytes, j))

    assert :erlang.external_size(exact.partial.continuation_checkpoint) == j
    assert Agent.get(fault, & &1) == :ok
    Agent.update(fault, fn _ -> {"create", :before} end)

    {:error, rejected} =
      ExAgent.run(original, "token", continuation: Map.put(cfg, :max_checkpoint_bytes, j - 1))

    assert rejected.reason == :continuation_frame_limit
    assert rejected.partial.continuation_checkpoint == nil
    assert Agent.get(fault, & &1) == {"create", :before}
    refute_receive :model_first
    refute_receive :effect

    for invalid <- [
          Map.put(token, "token_version", 2),
          Map.put(token, "namespace", "other"),
          Map.put(token, "expected_revision", "future"),
          Map.put(token, "extra", true)
        ] do
      assert {:error, :invalid_checkpoint_token} = Continuation.retry_checkpoint(store, invalid)
    end

    assert {:error, :not_found} = Store.load_record(store, :agent, "conversation")
    assert {:ok, %{record: record}} = Continuation.retry_checkpoint(store, token)
    assert record["execution"]["state"] == "ready"
    refute_receive :model_first
    refute_receive :effect
    Agent.stop(fault)
  end

  test "JSON record cap remains independent of a representable EFT checkpoint", %{store: store} do
    {:ok, fault} = Agent.start_link(fn -> {"create", :before} end)
    faulty = Store.scoped({FaultStore, {__MODULE__, fault}}, "runtime")
    {:error, sample_error} = ExAgent.run(agent(self()), "", continuation: config(faulty))
    token = sample_error.partial.continuation_checkpoint

    {:ok, %{record: sample}} =
      ExAgent.Continuation.Transition.apply(
        nil,
        {"runtime", :agent, "conversation"},
        :absent,
        token["command"],
        System.system_time(:millisecond)
      )

    room =
      ExAgent.Continuation.Record.max_bytes() - byte_size(Jason.encode!(sample)) -
        ExAgent.Continuation.Record.cleanup_reserve_bytes(sample)

    # One control byte becomes six bytes in history JSON, seven in envelope JSON.
    input = String.duplicate(<<1>>, div(room, 7) + 1)
    assert {:error, error} = ExAgent.run(agent(self()), input, continuation: config(store))
    assert error.reason == {:continuation_checkpoint_failed, :record_limit}
    assert error.partial.retention.checkpoint_bytes <= 8 * 1024 * 1024
    assert error.partial.retention.checkpoint_bytes > 7_000_000
    assert {:error, :not_found} = Store.load_record(store, :agent, "conversation")
    refute_receive :model_first
    refute_receive :effect
    Agent.stop(fault)
  end

  @tag :capture_log
  test "stock ReqLLM resumes envelope once and revalidates endpoint binding before tool IO", %{
    store: store
  } do
    owner = self()
    count = start_supervised!({Agent, fn -> 0 end}, id: :stock_http)

    adapter = fn request ->
      index = Agent.get_and_update(count, &{&1, &1 + 1})
      body = Jason.decode!(IO.iodata_to_binary(request.body))
      send(owner, {:stock_http, index, body})

      {message, finish} =
        if index == 0 do
          {%{
             "role" => "assistant",
             "tool_calls" => [
               %{
                 "id" => "call",
                 "type" => "function",
                 "function" => %{"name" => "effect", "arguments" => ~s({"arguments":{}})}
               }
             ]
           }, "tool_calls"}
        else
          {%{"role" => "assistant", "content" => "done"}, "stop"}
        end

      response = %{
        "id" => "stock",
        "model" => "r5-fixture",
        "choices" => [%{"index" => 0, "message" => message, "finish_reason" => finish}],
        "usage" => %{"prompt_tokens" => 2, "completion_tokens" => 1, "total_tokens" => 3}
      }

      {request,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: Jason.encode!(response)
       )}
    end

    model =
      ExAgent.Models.ReqLLM.new(
        model: %{
          provider: :openai,
          id: "r5-fixture",
          extra: %{wire: %{protocol: "openai_chat"}},
          capabilities: %{tools: %{enabled: true}, reasoning: %{enabled: false}}
        },
        api_key: "synthetic-key",
        base_url: "https://fixture.invalid/v1",
        tool_profile: :chat_tools_v1,
        http_options: [adapter: ExAgent.Test.ReqTransport.bind(adapter)]
      )

    a = %{agent(owner) | model: model}

    cfg = %{
      config(store)
      | model_codec: %{
          dump: fn _ -> {:ok, %{}} end,
          load: fn template, %{} -> {:ok, template} end
        }
    }

    opts = [continuation: cfg, permissions: Permissions.new!(default: :ask)]
    assert {:ok, %{status: :paused} = paused} = ExAgent.run(a, "stock", opts)
    assert Agent.get(count, & &1) == 1
    refute_receive :effect
    {:ok, %{record: r}} = Continuation.get(store, "conversation")
    refute Jason.encode!(r) =~ "synthetic-key"
    reference = approve(store, r, paused.continuation)
    changed = %{a | model: %{model | base_url: "https://another.invalid/v1"}}

    assert {:error, %{reason: %ExAgent.RequestError{reason: :continuation_target_mismatch}}} =
             ExAgent.resume(changed, reference, opts)

    refute_receive :effect
    assert Agent.get(count, & &1) == 1
    assert {:ok, result} = ExAgent.resume(a, reference, opts)
    assert result.status == :succeeded
    assert result.request_count == 2
    assert result.usage.accounting["quality"] == "normalized"
    assert_receive :effect
    refute_receive :effect
    assert_receive {:stock_http, 1, body}
    assistant = Enum.find(body["messages"], &(&1["role"] == "assistant"))

    assert Jason.decode!(hd(assistant["tool_calls"])["function"]["arguments"]) == %{
             "arguments" => %{}
           }
  end

  test "a custom model without continuation preflight remains ordinary-only and fails before durable IO",
       %{store: store} do
    a = ExAgent.new(model: %NoResumeModel{owner: self()})
    assert {:ok, %{output: "ordinary"}} = ExAgent.run(a, "ordinary")
    assert_receive :unsupported_model_io

    assert {:error, %{reason: :model_continuation_preflight_required}} =
             ExAgent.run(a, "durable", continuation: config(store))

    refute_receive :unsupported_model_io
    assert {:error, :not_found} = Store.load_record(store, :agent, "conversation")
  end

  test "approval canonical binding distinguishes integer and float but ignores JSON object key order",
       %{store: store} do
    for {namespace, original, changed, allowed} <- [
          {"numeric", %{"n" => 1}, %{"n" => 1.0}, false},
          {"ordered", Map.new([{"a", 1}, {"b", 2}]), Map.new([{"b", 2}, {"a", 1}]), true}
        ] do
      scoped = %{store | namespace: namespace}
      a = %{agent(self()) | capabilities: [%EffectiveArgs{args: original}]}
      opts = [continuation: config(scoped), permissions: Permissions.new!(default: :ask)]
      {:ok, paused} = ExAgent.run(a, "binding", opts)
      assert_receive :model_first
      {:ok, %{record: r}} = Continuation.get(scoped, "conversation")
      ref = approve(scoped, r, paused.continuation)
      result = ExAgent.resume(%{a | capabilities: [%EffectiveArgs{args: changed}]}, ref, opts)

      if allowed do
        assert {:ok, %{status: :succeeded}} = result
        assert_receive :effect
        assert_receive :model_second
      else
        assert {:error, %{reason: :approval_payload_changed}} = result
        refute_receive :effect
        refute_receive :model_second
      end
    end
  end

  test "corrupt cursor and orphan success cannot skip pending effects or overwrite the imported record",
       %{store: store} do
    for mutation <- [:cursor, :outcome] do
      scoped = %{store | namespace: Atom.to_string(mutation)}
      a = agent(self())
      opts = [continuation: config(scoped), permissions: Permissions.new!(default: :ask)]
      {:ok, paused} = ExAgent.run(a, "corrupt", opts)
      assert_receive :model_first
      {:ok, %{record: r}} = Continuation.get(scoped, "conversation")
      ref = approve(scoped, r, paused.continuation)
      {:ok, %{record: approved}} = Continuation.get(scoped, "conversation")

      forged =
        ExAgent.Message.to_json([
          %ExAgent.Message.Request{
            parts: [
              %Part.ToolReturn{
                tool_name: "effect",
                tool_call_id: "call",
                status: :succeeded,
                content: "forged"
              }
            ]
          }
        ])

      corrupt =
        case mutation do
          :cursor ->
            put_in(approved, ["execution", "progress", "runtime", "cursor"], "request")

          :outcome ->
            put_in(approved, ["execution", "progress", "runtime", "outcomes"], %{"call" => forged})
        end

      import_record(scoped, corrupt)
      assert {:error, _} = ExAgent.resume(a, ref, opts)
      refute_receive :effect
      refute_receive :model_second
      assert {:ok, ^corrupt} = Store.load_record(scoped, :agent, "conversation")
    end
  end

  test "current tool limit validates historical reservations without charging them twice", %{
    store: store
  } do
    for limit <- [0, 1] do
      scoped = %{store | namespace: "limit-#{limit}"}
      a = %{agent(self()) | usage_limits: %ExAgent.UsageLimits{tool_calls_limit: 1}}
      opts = [continuation: config(scoped), permissions: Permissions.new!(default: :ask)]
      {:ok, paused} = ExAgent.run(a, "limit", opts)
      assert_receive :model_first
      {:ok, %{record: r}} = Continuation.get(scoped, "conversation")
      ref = approve(scoped, r, paused.continuation)

      result =
        ExAgent.resume(
          %{a | usage_limits: %ExAgent.UsageLimits{tool_calls_limit: limit}},
          ref,
          opts
        )

      if limit == 1 do
        assert {:ok, %{tool_calls: 1, status: :succeeded}} = result
        assert_receive :effect
        assert_receive :model_second
      else
        assert {:error, _} = result
        refute_receive :effect
        refute_receive :model_second
      end
    end
  end

  test "native and tool Ecto output survive approval and apply final changeset with counted retry",
       %{
         store: store
       } do
    for mode <- [:native, :tool] do
      scoped = %{store | namespace: "typed-#{mode}"}
      base = agent(self())

      outputs =
        for count <- [0, 7] do
          if mode == :native,
            do: Jason.encode!(%{"count" => count}),
            else:
              {:tool_calls,
               [
                 %Part.ToolCall{
                   tool_name: "final_result",
                   tool_call_id: "output-#{count}",
                   args: %{"count" => count}
                 }
               ]}
        end

      model = %NativeModel{
        owner: self(),
        script: [
          {:tool_calls, [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}]}
          | outputs
        ]
      }

      a = ExAgent.new(model: model, tools: base.tools, output: TypedOutput, output_mode: mode)
      opts = [continuation: config(scoped), permissions: Permissions.new!(default: :ask)]
      assert {:ok, %{status: :paused} = paused} = ExAgent.run(a, "typed", opts)
      assert_receive {:native_request, 0}
      {:ok, %{record: r}} = Continuation.get(scoped, "conversation")
      ref = approve(scoped, r, paused.continuation)

      assert {:ok, %{output: %TypedOutput{count: 7}, request_count: 3, tool_calls: 1}} =
               ExAgent.resume(a, ref, opts)

      assert_receive :effect
      assert_receive {:native_request, 1}
      assert_receive {:native_request, 2}
      refute_receive :effect
    end
  end

  test "pre-dispatch denied and invalid outcomes have journal evidence and survive resume without execution",
       %{store: store} do
    owner = self()

    for kind <- [:denied, :invalid] do
      scoped = %{store | namespace: "resolved-#{kind}"}

      schema =
        if kind == :invalid,
          do: %{
            "type" => "object",
            "required" => ["n"],
            "properties" => %{"n" => %{"type" => "integer"}}
          },
          else: %{"type" => "object"}

      first =
        Tool.new(
          name: "first",
          parameters_json_schema: schema,
          call: fn _, _ ->
            send(owner, :forbidden_first)
            "bad"
          end
        )

      second =
        Tool.new(
          name: "second",
          parameters_json_schema: %{"type" => "object"},
          call: fn _, _ ->
            send(owner, :second_effect)
            "ok"
          end
        )

      model = %ExAgent.Models.Test{
        script: [
          {:tool_calls,
           [
             %Part.ToolCall{tool_name: "first", tool_call_id: "first-call", args: %{}},
             %Part.ToolCall{tool_name: "second", tool_call_id: "second-call", args: %{}}
           ]},
          "done"
        ]
      }

      a = ExAgent.new(model: model, tools: [first, second])

      permissions =
        Permissions.new!(
          default: :ask,
          rules: [{"first", if(kind == :denied, do: :deny, else: :allow)}]
        )

      opts = [continuation: config(scoped), permissions: permissions]
      assert {:ok, %{status: :paused} = paused} = ExAgent.run(a, "resolutions", opts)
      {:ok, %{record: r}} = Continuation.get(scoped, "conversation")
      [resolution] = for {_, e} <- r["execution"]["effects"], e["intent"]["kind"] == "tool", do: e
      assert resolution["intent"]["payload"]["phase"] == "pre_dispatch"
      assert resolution["outcome"]["data"]["phase"] == "final"
      refute_receive :forbidden_first
      ref = approve(scoped, r, paused.continuation)
      assert {:ok, %{status: :succeeded, tool_calls: 2}} = ExAgent.resume(a, ref, opts)
      assert_receive :second_effect
      refute_receive :forbidden_first
      refute_receive :second_effect
    end
  end

  test "transformed after-hook outcome is finalized atomically and never replays hook or effect",
       %{store: store} do
    owner = self()

    first =
      Tool.new(
        name: "first",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :first_effect)
          "raw"
        end
      )

    second =
      Tool.new(
        name: "second",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :second_effect)
          "second"
        end
      )

    model = %ExAgent.Models.Test{
      script: [
        {:tool_calls,
         [
           %Part.ToolCall{tool_name: "first", tool_call_id: "first-call", args: %{}},
           %Part.ToolCall{tool_name: "second", tool_call_id: "second-call", args: %{}}
         ]},
        fn messages, _ ->
          assert Enum.any?(
                   ExAgent.Message.parts(messages),
                   &match?(%Part.ToolReturn{tool_name: "first", content: "transformed"}, &1)
                 )

          "done"
        end
      ]
    }

    a =
      ExAgent.new(
        model: model,
        tools: [first, second],
        capabilities: [%AfterTool{owner: owner, mode: :transform}]
      )

    opts = [
      continuation: config(store),
      permissions: Permissions.new!(default: :allow, rules: [{"second", :ask}])
    ]

    {:ok, paused} = ExAgent.run(a, "after", opts)
    assert_receive :first_effect
    assert_receive :after_first
    {:ok, %{record: r}} = Continuation.get(store, "conversation")
    [effect] = for {_, e} <- r["execution"]["effects"], e["intent"]["kind"] == "tool", do: e
    assert effect["outcome"]["data"]["phase"] == "final"
    assert effect["outcome"]["data"]["raw_hash"] != effect["outcome"]["data"]["result_hash"]
    ref = approve(store, r, paused.continuation)
    assert {:ok, %{status: :succeeded}} = ExAgent.resume(a, ref, opts)
    assert_receive :second_effect
    refute_receive :first_effect
    refute_receive :after_first
  end

  test "identity, failed and oversized after hooks preserve confirmed status and explicit phase",
       %{store: store} do
    for mode <- [:identity, :fail, :large] do
      scoped = %{store | namespace: "after-#{mode}"}
      cfg = Map.put(config(scoped), :max_checkpoint_bytes, 80_000)
      result = ExAgent.run(after_agent(self(), mode), "after", continuation: cfg)
      assert_receive :first_effect
      assert_receive :after_first
      {:ok, %{record: record}} = Continuation.get(scoped, "conversation")

      [effect] =
        for {_, e} <- record["execution"]["effects"], e["intent"]["kind"] == "tool", do: e

      assert effect["outcome"]["status"] == "succeeded"
      assert effect["outcome"]["data"]["phase"] == "final"

      if mode == :identity do
        assert {:ok, %{status: :succeeded}} = result
        assert effect["outcome"]["data"]["raw_hash"] == effect["outcome"]["data"]["result_hash"]
      else
        assert {:error, error} = result
        assert error.partial.request_count == 1

        if mode == :large do
          assert [
                   %Part.ToolReturn{
                     status: :succeeded,
                     content: nil,
                     payload_omitted: %{"boundary" => "checkpoint"}
                   }
                 ] =
                   Enum.filter(
                     ExAgent.Message.parts(error.partial.messages),
                     &match?(%Part.ToolReturn{}, &1)
                   )

          assert byte_size(Jason.encode!(record)) < 20_000
        end
      end

      refute_receive :first_effect
    end
  end

  test "owner death between raw ACK and final hook retains raw data without replaying effect or hook",
       %{store: store} do
    owner = self()
    a = after_agent(owner, :block)
    cfg = %{config(store) | active_time_limit_ms: nil, lease_ms: 500}
    {pid, monitor} = spawn_monitor(fn -> ExAgent.run(a, "raw", continuation: cfg) end)
    assert_receive :first_effect
    assert_receive :after_first
    {:ok, %{record: raw}} = Continuation.get(store, "conversation")
    [effect] = for {_, e} <- raw["execution"]["effects"], e["intent"]["kind"] == "tool", do: e
    assert effect["outcome"]["data"]["phase"] == "raw"
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    wait_until(raw["execution"]["lease_until"])

    {:ok, %{record: recovered}} =
      Continuation.recover(store, "conversation", administrative(raw, "recover-raw"))

    reference = %{
      id: "conversation",
      record_id: recovered["record_id"],
      revision: recovered["revision"]
    }

    assert {:ok, %{status: :succeeded, tool_calls: 1, request_count: 2}} =
             ExAgent.resume(a, reference, continuation: cfg)

    refute_receive :first_effect
    refute_receive :after_first
  end

  test "lost finalization ACK retries data only and resumes from final content without a hook replay",
       %{store: store} do
    {:ok, fault} = Agent.start_link(fn -> {"finalize_call", :after} end)
    faulty = Store.scoped({FaultStore, {__MODULE__, fault}}, "runtime")
    a = after_agent(self(), :transform)
    cfg = %{config(faulty) | active_time_limit_ms: nil, lease_ms: 500}
    assert {:error, error} = ExAgent.run(a, "final ACK", continuation: cfg)
    assert_receive :first_effect
    assert_receive :after_first
    assert error.partial.continuation_checkpoint["command"]["operation"] == "finalize_call"

    assert {:ok, %{record: committed, replayed: true}} =
             Continuation.retry_checkpoint(store, error.partial.continuation_checkpoint)

    wait_until(committed["execution"]["lease_until"])

    {:ok, %{record: recovered}} =
      Continuation.recover(store, "conversation", administrative(committed, "recover-final"))

    reference = %{
      id: "conversation",
      record_id: recovered["record_id"],
      revision: recovered["revision"]
    }

    assert {:ok, result} = ExAgent.resume(a, reference, continuation: cfg)

    assert Enum.any?(
             ExAgent.Message.parts(result.messages),
             &match?(%Part.ToolReturn{content: "transformed"}, &1)
           )

    refute_receive :first_effect
    refute_receive :after_first
    Agent.stop(fault)
  end

  defp after_agent(owner, mode) do
    tool =
      Tool.new(
        name: "first",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :first_effect)
          "raw"
        end
      )

    model = %ExAgent.Models.Test{
      script: [
        {:tool_calls,
         [%Part.ToolCall{tool_name: "first", tool_call_id: "first-call", args: %{}}]},
        "done"
      ]
    }

    ExAgent.new(model: model, tools: [tool], capabilities: [%AfterTool{owner: owner, mode: mode}])
  end

  defp import_record(store, record) do
    key = {store.namespace, :agent, "conversation"}
    {:ok, bytes} = ExAgent.Continuation.Record.encode(record, key)
    {:ok, physical} = ExAgent.Continuation.Record.key(key)
    :ets.insert(__MODULE__, {physical, bytes})
  end

  defp drain_binding_calls(count \\ 0) do
    receive do
      :binding_called -> drain_binding_calls(count + 1)
    after
      0 -> count
    end
  end

  defp administrative(record, operation),
    do: [
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: operation,
      actor: :host,
      authorize: fn :host, _, _ -> {:ok, "operator"} end
    ]

  defp wait_until(time) do
    receive do
    after
      max(time - System.system_time(:millisecond), 0) -> :ok
    end
  end

  defp agent(owner) do
    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, :effect)
          {:ok, "saved"}
        end
      )

    model = %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          send(owner, :model_first)
          %Response{parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}]}
        end,
        fn _, _ ->
          send(owner, :model_second)
          "done"
        end
      ]
    }

    ExAgent.new(model: model, tools: [tool])
  end

  defp config(store),
    do: %{
      store: store,
      id: "conversation",
      durability: :ephemeral,
      expires_at: nil,
      deadline_at: nil,
      lease_ms: 60_000,
      active_time_limit_ms: 30_000,
      definition: %{"id" => "fixture", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      model_ref: %{"id" => "test-model", "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }

  defp approve(store, record, reference) do
    [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    {:ok, %{record: approved}} =
      Continuation.decide(store, "conversation", :approve,
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "approve",
        approval_id: id,
        payload_hash: approval["payload_hash"],
        actor: :trusted,
        authorize: fn :trusted, :approve, _ -> {:ok, "human"} end
      )

    %{reference | revision: approved["revision"]}
  end
end
