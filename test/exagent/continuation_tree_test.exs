defmodule ExAgent.ContinuationTreeTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, Coordination, Permissions, Store, Tool}
  alias ExAgent.Message.{Part, Response}

  defmodule BoundModel do
    @behaviour ExAgent.Model
    defstruct [:binding, script: [], index: 0]
    def model_name(_), do: "test"
    def system(_), do: "test"
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}
    def validate_resume(_, _, _, _), do: :ok
    def continuation_binding(model), do: {:ok, model.binding}

    def request(model, messages, settings, params) do
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

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "tree")}
  end

  test "public delegated pause retains confirmed sibling and resumes without parent callable or double admission",
       %{store: store} do
    owner = self()

    child =
      ExAgent.new(
        model: %BoundModel{
          binding: %{"target" => "child"},
          script: model(owner, :child, [call("child-effect", "child-call"), "child done"]).script
        },
        tools: [tool(owner, "child-effect")]
      )

    delegate =
      Coordination.delegation_tool(child,
        name: "delegate",
        permissions: Permissions.new!(default: :ask),
        continuation: refs("child")
      )

    delegate = %{
      delegate
      | call: fn _, _ ->
          send(owner, :parent_callable)
          raise "parent callable replay"
        end
    }

    root =
      ExAgent.new(
        model:
          model(owner, :root, [
            %Response{
              parts: [
                call("delegate", "delegate-call", %{"prompt" => "child task"}),
                call("sibling", "sibling-call")
              ]
            },
            "root done"
          ]),
        tools: [delegate, tool(owner, "sibling")]
      )

    config =
      Map.merge(refs("root"), %{
        store: store,
        id: "conversation",
        durability: :ephemeral,
        expires_at: nil,
        deadline_at: nil,
        lease_ms: 60_000,
        active_time_limit_ms: 30_000
      })

    task = Task.async(fn -> ExAgent.run(root, "root task", continuation: config) end)
    assert {:ok, paused} = Task.await(task, 10_000)
    assert paused.status == :paused
    refute Process.alive?(task.pid)
    assert paused.request_count == 2
    assert paused.tool_calls == 3
    assert_receive {:model, :root, 0}
    assert_receive {:model, :child, 0}
    assert_receive {:effect, "sibling"}
    refute_receive {:effect, "child-effect"}
    refute_receive :parent_callable
    {:ok, %{record: record, status: :pending}} = Continuation.get(store, "conversation")
    frame = record["execution"]["progress"]["runtime"]
    assert frame["frame_version"] == 3
    assert map_size(frame["children"]) == 1
    [{child_id, node}] = Map.to_list(frame["children"])
    assert node["status"] == "paused"
    assert node["parent_run_id"] == paused.run_id
    assert node["frame"]["run_id"] == child_id

    assert Enum.all?(record["execution"]["effects"], fn {_, effect} ->
             effect["state"] == "confirmed"
           end)

    refute Enum.any?(record["execution"]["effects"], fn {_, effect} ->
             effect["intent"]["call_id"] == "delegate-call"
           end)

    [{approval_id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])
    assert approval["run_id"] == child_id

    {:ok, %{record: approved}} =
      Continuation.decide(store, "conversation", :approve,
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "approve-child",
        approval_id: approval_id,
        payload_hash: approval["payload_hash"],
        actor: :host,
        authorize: fn :host, :approve, _ -> {:ok, "human"} end
      )

    reference = %{paused.continuation | revision: approved["revision"]}
    bad_child = %{child | model: %{child.model | binding: %{"target" => "other"}}}
    bad_delegate = %{delegate | delegation: %{delegate.delegation | delegate: bad_child}}
    bad_root = %{root | tools: [bad_delegate, tool(owner, "sibling")]}
    assert {:error, _} = ExAgent.resume(bad_root, reference, continuation: config)
    assert {:ok, %{record: unchanged}} = Continuation.get(store, "conversation")
    assert unchanged == approved
    refute_receive {:model, _, _}, 0
    refute_receive {:effect, _}, 0
    assert {:ok, result} = ExAgent.resume(root, reference, continuation: config)
    assert result.status == :succeeded
    assert result.output == "root done"
    assert result.request_count == 4
    assert result.tool_calls == 3
    assert_receive {:effect, "child-effect"}
    assert_receive {:model, :child, 1}
    assert_receive {:model, :root, 1}
    refute_receive {:effect, "sibling"}
    refute_receive {:effect, "child-effect"}
    refute_receive {:model, _, 0}
    refute_receive :parent_callable
  end

  test "authentic admission writer tree2 bytes resume with nil binding but cannot acquire a new binding",
       %{store: store} do
    record =
      File.read!(Path.expand("../fixtures/continuation-tree2-admission.json", __DIR__))
      |> Jason.decode!()

    assert record["execution"]["progress"]["runtime"]["frame_version"] == 2
    refute Map.has_key?(record["execution"]["progress"]["runtime"], "model_binding")
    import_record(store, record)

    child =
      ExAgent.new(
        model: model(self(), :child, [call("child-effect", "child-call"), "child done"]),
        tools: [tool(self(), "child-effect")]
      )

    delegate =
      Coordination.delegation_tool(child,
        name: "delegate",
        permissions: Permissions.new!(default: :ask),
        continuation: refs("child")
      )

    root =
      ExAgent.new(
        model:
          model(self(), :root, [
            call("delegate", "delegate-call", %{"prompt" => "child task"}),
            "root done"
          ]),
        tools: [delegate]
      )

    config =
      Map.merge(refs("root"), %{
        store: store,
        id: "conversation",
        durability: :ephemeral,
        expires_at: nil,
        lease_ms: 60_000
      })

    reference =
      approve(store, record, %{
        id: "conversation",
        record_id: record["record_id"],
        revision: record["revision"]
      })

    acquired = %{root | model: %BoundModel{script: root.model.script, binding: %{"new" => true}}}

    assert {:error, %{reason: :continuation_model_binding_changed}} =
             ExAgent.resume(acquired, reference, continuation: config)

    refute_receive {:model, _, _}, 0

    assert {:ok, %{output: "root done", request_count: 4, tool_calls: 2}} =
             ExAgent.resume(root, reference, continuation: config)

    assert_receive {:effect, "child-effect"}
    assert_receive {:model, :child, 1}
    assert_receive {:model, :root, 1}
    refute_receive {:model, _, 0}, 0
    refute_receive {:effect, _}, 0
    {:ok, %{record: completed}} = Continuation.get(store, "conversation")
    assert completed["execution"]["progress"]["runtime"]["frame_version"] == 3
  end

  defp refs(id),
    do: %{
      definition: %{"id" => id, "version" => "1"},
      policy: %{"id" => id <> "-policy", "version" => "1"},
      model_ref: %{"id" => "test", "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }

  test "two children and depth two keep colliding call IDs and per-ancestor prices distinct", %{
    store: store
  } do
    owner = self()
    {root, config} = deep_tree(owner, store)

    old_price = fn _ ->
      send(owner, :old_price)
      2
    end

    {:ok, paused} = ExAgent.run(root, "tree", continuation: config, estimate_cost: old_price)
    assert paused.status == :paused
    assert paused.request_count == 5
    assert paused.tool_calls == 6
    assert paused.usage.accounting["cost"]["subtotal_cents"] == 10
    for _ <- 1..5, do: assert_receive(:old_price)
    refute_receive :old_price
    assert_receive {:effect, "right-effect"}
    assert_receive {:effect, "sibling"}
    refute_receive {:effect, "leaf-effect"}
    {:ok, %{record: pending}} = Continuation.get(store, "conversation")
    assert map_size(pending["execution"]["progress"]["runtime"]["children"]) == 3
    reference = approve(store, pending, paused.continuation)

    new_price = fn _ ->
      send(owner, :new_price)
      11
    end

    assert {:ok, result} =
             ExAgent.resume(root, reference, continuation: config, estimate_cost: new_price)

    assert result.output == "root done"
    assert result.request_count == 8
    assert result.tool_calls == 6
    assert result.usage.accounting["cost"]["subtotal_cents"] == 43
    for _ <- 1..3, do: assert_receive(:new_price)
    refute_receive :new_price
    refute_receive :old_price
    assert_receive {:effect, "leaf-effect"}
    refute_receive {:effect, "right-effect"}
    refute_receive {:effect, "sibling"}
    {:ok, %{record: completed, status: :completed}} = Continuation.get(store, "conversation")
    children = completed["execution"]["progress"]["runtime"]["children"]

    assert Enum.all?(children, fn {_, node} ->
             node["status"] == "completed" and node["outcome"]["data"]["phase"] == "final"
           end)

    assert Enum.count(completed["execution"]["effects"], fn {_, e} ->
             e["intent"]["kind"] == "tool" and e["intent"]["call_id"] == "shared-call"
           end) == 2
  end

  test "restored reservations revalidate root and intermediate limits without a new debit", %{
    store: store
  } do
    {root, config} = deep_tree(self(), store)
    {:ok, paused} = ExAgent.run(root, "tree", continuation: config)
    {:ok, %{record: record}} = Continuation.get(store, "conversation")
    reference = approve(store, record, paused.continuation)

    variants = [
      {[root_limits: %ExAgent.UsageLimits{tool_calls_limit: 5}],
       {:usage_limit_exceeded, :tool_calls, 6}},
      {[middle_limits: %ExAgent.UsageLimits{tool_calls_limit: 1}],
       {:usage_limit_exceeded, :tool_calls, 2}},
      {[middle_limits: %ExAgent.UsageLimits{request_limit: 1}],
       {:usage_limit_exceeded, :requests, 2}},
      {[middle_deadline: System.monotonic_time(:millisecond) - 1], :deadline_exceeded}
    ]

    for {options, reason} <- variants do
      {restricted, _} = deep_tree(self(), store, options)

      assert {:error, %{reason: ^reason}} =
               ExAgent.resume(restricted, reference, continuation: config)

      refute_receive {:effect, "leaf-effect"}
      refute_receive {:model, :leaf, 1}
      {:ok, %{record: unchanged}} = Continuation.get(store, "conversation")
      assert unchanged["revision"] == reference.revision
    end

    assert {:ok, result} = ExAgent.resume(root, reference, continuation: config)
    assert result.request_count == 8 and result.tool_calls == 6
    assert_receive {:effect, "leaf-effect"}
    refute_receive {:effect, "leaf-effect"}
  end

  test "corrupt delegated graph, linked journal and parent/child outcomes reject before model IO",
       %{store: store} do
    {root, config} = deep_tree(self(), store)
    {:ok, paused} = ExAgent.run(root, "tree", continuation: config)
    {:ok, %{record: pending}} = Continuation.get(store, "conversation")
    reference = approve(store, pending, paused.continuation)
    {:ok, %{record: record}} = Continuation.get(store, "conversation")
    frame = record["execution"]["progress"]["runtime"]

    {right, right_node} =
      Enum.find(frame["children"], fn {_, n} -> n["definition"]["id"] == "right" end)

    {middle, _} = Enum.find(frame["children"], fn {_, n} -> n["definition"]["id"] == "middle" end)
    {leaf, _} = Enum.find(frame["children"], fn {_, n} -> n["definition"]["id"] == "leaf" end)
    path = ["execution", "progress", "runtime"]

    corruptions = [
      update_in(record, path ++ ["children"], &Map.delete(&1, leaf)),
      put_in(record, path ++ ["children", leaf, "parent_run_id"], leaf),
      put_in(record, path ++ ["scope", "nodes", middle, "parent_run_id"], leaf),
      put_in(record, path ++ ["children", leaf, "parent_request_id"], "unknown-request"),
      put_in(record, path ++ ["children", right, "parent_result"], nil),
      put_in(record, path ++ ["children", right, "result"], "forged"),
      put_in(
        record,
        path ++ ["outcomes"],
        Map.delete(frame["outcomes"], right_node["call"]["call_id"])
      ),
      put_in(record, path ++ ["children", leaf, "frame", "run_step"], 0),
      put_in(record, path ++ ["children", leaf, "frame", "model_data"], %{"index" => 0})
    ]

    for corrupt <- corruptions do
      import_record(store, corrupt)
      assert {:error, _} = ExAgent.resume(root, reference, continuation: config)
      refute_receive {:effect, "leaf-effect"}
      refute_receive {:model, :leaf, 1}
      refute_receive {:model, :middle, 1}
    end

    import_record(store, record)
    assert {:ok, %{status: :succeeded}} = ExAgent.resume(root, reference, continuation: config)
  end

  test "human wait does not preserve a dead lease as a child deadline and all child workers are gone",
       %{store: store} do
    {root, config} = deep_tree(self(), store)
    config = %{config | lease_ms: 1_000}
    {:ok, paused} = ExAgent.run(root, "tree", continuation: config)

    for label <- [:middle, :leaf, :right] do
      assert_receive {:model_pid, ^label, pid}
      refute Process.alive?(pid)
    end

    {:ok, %{record: record}} = Continuation.get(store, "conversation")

    assert Enum.all?(record["execution"]["progress"]["runtime"]["children"], fn {_, node} ->
             is_nil(node["deadline_at"])
           end)

    Process.sleep(1_050)
    reference = approve(store, record, paused.continuation)
    assert {:ok, %{status: :succeeded}} = ExAgent.resume(root, reference, continuation: config)
  end

  test "reverse journal and approval edges reject deletion of an otherwise coherent subtree", %{
    store: store
  } do
    {root, config} = deep_tree(self(), store)
    {:ok, paused} = ExAgent.run(root, "tree", continuation: config)
    assert_receive {:model, :leaf, 0}
    {:ok, %{record: pending}} = Continuation.get(store, "conversation")
    reference = approve(store, pending, paused.continuation)
    {:ok, %{record: record}} = Continuation.get(store, "conversation")
    frame = record["execution"]["progress"]["runtime"]
    {leaf, node} = Enum.find(frame["children"], fn {_, n} -> n["definition"]["id"] == "leaf" end)
    middle = node["parent_run_id"]
    scope = frame["scope"]

    nodes =
      scope["nodes"]
      |> Map.delete(leaf)
      |> Map.update!(
        middle,
        &%{&1 | "requests" => &1["requests"] - 1, "tools" => &1["tools"] - 1}
      )
      |> Map.update!(
        frame["run_id"],
        &%{&1 | "requests" => &1["requests"] - 1, "tools" => &1["tools"] - 1}
      )

    scope = %{
      scope
      | "nodes" => nodes,
        "operations" => Enum.reject(scope["operations"], &(&1["run_id"] == leaf)),
        "batches" => Enum.reject(scope["batches"], &(&1["run_id"] == leaf))
    }

    pruned = %{frame | "children" => Map.delete(frame["children"], leaf), "scope" => scope}
    assert :ok = ExAgent.Continuation.Frame.validate(pruned)
    corrupt = put_in(record, ["execution", "progress", "runtime"], pruned)

    approval_only =
      update_in(corrupt, ["execution", "effects"], fn effects ->
        Map.reject(effects, fn {_, e} -> e["intent"]["payload"]["run_id"] == leaf end)
      end)

    for variant <- [corrupt, approval_only] do
      import_record(store, variant)

      assert {:error, %{reason: :continuation_orphaned_evidence}} =
               ExAgent.resume(root, reference, continuation: config)

      refute_receive {:model, :leaf, 0}
      refute_receive {:effect, "leaf-effect"}
    end

    import_record(store, record)
    assert {:ok, %{status: :succeeded}} = ExAgent.resume(root, reference, continuation: config)
  end

  test "two resumers cannot dispatch the same delegated leaf", %{store: store} do
    owner = self()

    leaf_call = fn ctx, _ ->
      send(owner, {:leaf_entered, self(), ctx.continuation, ctx.execution_scope.pid})

      receive do
        :release_leaf -> "done"
      end
    end

    {root, config} = deep_tree(owner, store, leaf_call: leaf_call)
    {:ok, paused} = ExAgent.run(root, "tree", continuation: config)
    {:ok, %{record: pending}} = Continuation.get(store, "conversation")
    reference = approve(store, pending, paused.continuation)
    first = Task.async(fn -> ExAgent.resume(root, reference, continuation: config) end)
    assert_receive {:leaf_entered, leaf, _, _}, 2_000

    assert {:error, %{reason: :continuation_conflict}} =
             ExAgent.resume(root, reference, continuation: config)

    send(leaf, :release_leaf)

    assert {:ok, %{status: :succeeded, request_count: 8, tool_calls: 6}} =
             Task.await(first, 5_000)

    refute_receive {:leaf_entered, _, _, _}
  end

  test "owner death fences the single writer and child effect reconciles at its own node", %{
    store: store
  } do
    owner = self()

    leaf_call = fn ctx, _ ->
      send(owner, {:leaf_entered, self(), ctx.continuation, ctx.execution_scope.pid})

      receive do
        :release_leaf -> "done"
      end
    end

    {root, config} = deep_tree(owner, store, leaf_call: leaf_call)
    config = %{config | lease_ms: 1_000, active_time_limit_ms: nil}
    {:ok, paused} = ExAgent.run(root, "tree", continuation: config)
    {:ok, %{record: pending}} = Continuation.get(store, "conversation")
    reference = approve(store, pending, paused.continuation)
    {:ok, runner} = Task.start(fn -> ExAgent.resume(root, reference, continuation: config) end)
    assert_receive {:leaf_entered, leaf, writer, scope}, 2_000
    monitors = Enum.map([runner, leaf, writer, scope], &{&1, Process.monitor(&1)})
    Process.exit(runner, :kill)

    for {pid, monitor} <- monitors,
        do: assert_receive({:DOWN, ^monitor, :process, ^pid, _}, 2_000)

    {:ok, %{record: abandoned}} = Continuation.get(store, "conversation")

    Process.sleep(
      max(abandoned["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)
    )

    {:ok, %{record: uncertain}} =
      Continuation.recover(store, "conversation", admin(abandoned, "recover-tree"))

    assert uncertain["execution"]["state"] == "uncertain"

    [{effect_id, effect}] =
      Enum.filter(uncertain["execution"]["effects"], fn {_, e} -> e["state"] == "running" end)

    leaf_id = effect["intent"]["payload"]["run_id"]

    assert uncertain["execution"]["progress"]["runtime"]["children"][leaf_id]["definition"]["id"] ==
             "leaf"

    {:ok, %{record: reconciled}} =
      Continuation.reconcile(
        store,
        "conversation",
        effect_id,
        %{"status" => "succeeded", "data" => "done"},
        admin(uncertain, "reconcile-leaf")
      )

    assert reconciled["execution"]["state"] == "ready"

    assert is_binary(
             reconciled["execution"]["progress"]["runtime"]["children"][leaf_id]["frame"][
               "outcomes"
             ]["shared-call"]
           )

    assert is_nil(reconciled["execution"]["progress"]["runtime"]["outcomes"]["shared-call"])
    reference = %{reference | revision: reconciled["revision"]}

    assert {:ok, %{status: :succeeded, request_count: 8, tool_calls: 6}} =
             ExAgent.resume(root, reference, continuation: config)

    refute_receive {:leaf_entered, _, _, _}
  end

  @tag :tmp_dir
  test "a new VM rebuilds depth-two delegation only from disk bytes and trusted definitions", c do
    dir = Path.join(c.tmp_dir, "exagent-tree-vm-#{System.unique_integer([:positive])}")
    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    elixir = System.find_executable("elixir")
    paths = Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"]))

    args =
      [
        "-i",
        "HOME=" <> System.user_home!(),
        "PATH=" <> System.get_env("PATH"),
        "LANG=C.UTF-8",
        "ERL_FLAGS=+S 8:8",
        "EXAGENT_OFFLINE=1",
        "HEX_OFFLINE=1",
        elixir
      ] ++ Enum.flat_map(paths, &["-pa", &1]) ++ ["test/support/continuation_restart_probe.exs"]

    {output, 0} = System.cmd("/usr/bin/env", args ++ ["tree-pause", dir], stderr_to_stdout: true)
    assert output =~ "TREE_PAUSED_ACK"

    first =
      File.read!(Path.join(dir, "effects.txt"))
      |> String.split("\n", trim: true)
      |> Enum.frequencies()

    assert map_size(first) == 7 and Enum.all?(first, fn {_, count} -> count == 1 end)
    refute Map.has_key?(first, "leaf-effect")
    bytes = File.read!(Path.join(dir, "record.json"))
    refute bytes =~ "#PID"
    refute bytes =~ "#Function"
    {output, 0} = System.cmd("/usr/bin/env", args ++ ["tree-resume", dir], stderr_to_stdout: true)
    assert output =~ "TREE_RESUMED_ONCE"

    effects =
      File.read!(Path.join(dir, "effects.txt"))
      |> String.split("\n", trim: true)
      |> Enum.frequencies()

    assert map_size(effects) == 11 and Enum.all?(effects, fn {_, count} -> count == 1 end)

    assert effects["leaf-effect"] == 1 and effects["right-effect"] == 1 and
             effects["sibling"] == 1
  end

  defp admin(record, operation),
    do: [
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: operation,
      actor: :host,
      authorize: fn :host, _, _ -> {:ok, "human"} end
    ]

  defp import_record(store, record) do
    key = {store.namespace, :agent, "conversation"}
    {:ok, bytes} = ExAgent.Continuation.Record.encode(record, key)
    {:ok, physical} = ExAgent.Continuation.Record.key(key)
    :ets.insert(__MODULE__, {physical, bytes})
  end

  defp deep_tree(owner, store, opts \\ []) do
    leaf_effect = tool(owner, "leaf-effect")

    leaf_effect =
      if opts[:leaf_call], do: %{leaf_effect | call: opts[:leaf_call]}, else: leaf_effect

    leaf =
      ExAgent.new(
        model: model(owner, :leaf, [call("leaf-effect", "shared-call"), "leaf done"]),
        tools: [leaf_effect]
      )

    leaf_tool =
      Coordination.delegation_tool(leaf,
        name: "leaf",
        continuation: refs("leaf"),
        permissions: Permissions.new!(default: :ask)
      )

    middle =
      ExAgent.new(
        model:
          model(owner, :middle, [
            call("leaf", "shared-call", %{"prompt" => "leaf"}),
            "middle done"
          ]),
        tools: [leaf_tool],
        usage_limits: Keyword.get(opts, :middle_limits)
      )

    left =
      Coordination.delegation_tool(middle,
        name: "left",
        continuation: refs("middle"),
        estimate_cost: fn _ -> 7 end,
        permissions: Keyword.get(opts, :middle_permissions),
        deadline: Keyword.get(opts, :middle_deadline)
      )

    right =
      ExAgent.new(
        model: model(owner, :right, [call("right-effect", "shared-call"), "right done"]),
        tools: [tool(owner, "right-effect")]
      )

    right_tool =
      Coordination.delegation_tool(right,
        name: "right",
        continuation: refs("right"),
        estimate_cost: fn _ -> 5 end
      )

    root =
      ExAgent.new(
        model:
          model(owner, :root, [
            %Response{
              parts: [
                call("left", "left-call", %{"prompt" => "left"}),
                call("right", "right-call", %{"prompt" => "right"}),
                call("sibling", "sibling-call")
              ]
            },
            "root done"
          ]),
        tools: [left, right_tool, tool(owner, "sibling")],
        usage_limits: Keyword.get(opts, :root_limits)
      )

    config =
      Map.merge(refs("root"), %{
        store: store,
        id: "conversation",
        durability: :ephemeral,
        expires_at: nil,
        deadline_at: nil,
        lease_ms: 60_000,
        active_time_limit_ms: 30_000
      })

    {root, config}
  end

  defp approve(store, record, reference) do
    [{id, approval}] =
      Enum.filter(record["execution"]["progress"]["approvals"], fn {_, a} ->
        is_nil(a["decision"])
      end)

    {:ok, %{record: approved}} =
      Continuation.decide(store, "conversation", :approve,
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "approval-#{record["revision"]}",
        approval_id: id,
        payload_hash: approval["payload_hash"],
        actor: :host,
        authorize: fn :host, :approve, _ -> {:ok, "human"} end
      )

    %{reference | revision: approved["revision"]}
  end

  defp tool(owner, name),
    do:
      Tool.new(
        name: name,
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          send(owner, {:effect, name})
          "done"
        end
      )

  defp call(name, id, args \\ %{}),
    do: %Part.ToolCall{tool_name: name, tool_call_id: id, args: args}

  defp model(owner, label, outputs) do
    script =
      Enum.with_index(outputs, fn output, index ->
        fn _, _ ->
          send(owner, {:model, label, index})
          send(owner, {:model_pid, label, self()})

          response =
            case output do
              %Part.ToolCall{} -> %Response{parts: [output]}
              %Response{} -> output
              text when is_binary(text) -> %Response{parts: [%Part.Text{content: text}]}
            end

          %{response | usage: %ExAgent.Message.Usage{input_tokens: 1, output_tokens: 1}}
        end
      end)

    %ExAgent.Models.Test{script: script}
  end
end
