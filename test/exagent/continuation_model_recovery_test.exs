defmodule ExAgent.ContinuationModelRecoveryTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, Store}
  alias ExAgent.Message.{Part, Response, Usage}

  defmodule JournalModel do
    @behaviour ExAgent.Model
    defstruct [:owner, :label, :binding, mode: :block, index: 0]
    def model_name(_), do: "recovery-fixture"
    def system(_), do: "synthetic"
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: false}
    def continuation_binding(model), do: {:ok, model.binding}

    def validate_resume(_, messages, _, _) do
      if match?(%Response{}, List.last(messages)) and
           Response.text(List.last(messages)) == "invalid-profile",
         do: {:error, :fixture_profile_rejected},
         else: :ok
    end

    def request(model, _, _, _) do
      response = %Response{
        parts: [%Part.Text{content: "raw"}],
        usage: %Usage{input_tokens: 2, output_tokens: 3}
      }

      if model.label,
        do: send(model.owner, {:node_model_effect, model.label, self(), model.index, response}),
        else: send(model.owner, {:model_effect, self(), model.index, response})

      if model.mode == :block,
        do:
          (receive do
             :release_model -> :ok
           end)

      {:ok, response, %{model | index: model.index + 1}}
    end
  end

  defmodule AfterModel do
    use ExAgent.Capability
    defstruct [:owner]

    def after_model_request(hook, state) do
      send(hook.owner, :after_model)

      %{
        state
        | messages:
            List.update_at(state.messages, -1, &%{&1 | parts: [%Part.Text{content: "effective"}]})
      }
    end
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "model-recovery")}
  end

  test "first uncertain request binds current template before codec can conceal a changed configuration",
       %{store: store} do
    original = %JournalModel{owner: self(), binding: %{"target" => "original", "mode" => "none"}}
    agent = ExAgent.new(model: original)
    owner = self()

    config = %{
      config(store)
      | model_codec: %{
          dump: fn _ -> {:ok, %{}} end,
          load: fn _model, %{} ->
            send(owner, :binding_codec_load)
            {:ok, original}
          end
        }
    }

    {:ok, runner} = Task.start(fn -> ExAgent.run(agent, "input", continuation: config) end)
    assert_receive {:model_effect, ^runner, 0, response}, 2_000
    monitor = Process.monitor(runner)
    Process.exit(runner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^runner, :killed}
    record = recover(store)
    [{effect_id, _}] = Enum.to_list(record["execution"]["effects"])
    evidence = %{response: response, model_data: %{}}

    for binding <- [
          nil,
          %{"target" => "other", "mode" => "none"},
          %{"target" => "original", "mode" => "changed"}
        ] do
      changed = %{agent | model: %{original | binding: binding}}
      opts = admin(record, "binding-reconcile") ++ [agent: changed, continuation: config]

      assert {:error, _} =
               Continuation.reconcile_model(store, "conversation", effect_id, evidence, opts)

      refute_receive :binding_codec_load, 0
      {:ok, %{record: unchanged}} = Continuation.get(store, "conversation")
      assert unchanged == record
      refute_receive {:model_effect, _, _, _}, 0
    end

    opts = admin(record, "binding-reconcile") ++ [agent: agent, continuation: config]

    bad_codec =
      put_in(config, [:model_codec, :load], fn _, _ -> {:ok, %{original | binding: nil}} end)

    assert {:error, _} =
             Continuation.reconcile_model(
               store,
               "conversation",
               effect_id,
               evidence,
               Keyword.put(opts, :continuation, bad_codec)
             )

    assert {:ok, %{record: reconciled}} =
             Continuation.reconcile_model(store, "conversation", effect_id, evidence, opts)

    reference = %{
      id: "conversation",
      record_id: reconciled["record_id"],
      revision: reconciled["revision"]
    }

    assert {:ok, %{output: "raw", request_count: 1}} =
             ExAgent.resume(agent, reference, continuation: config)

    refute_receive {:model_effect, _, _, _}, 0
  end

  test "binding 4096 JSON bytes is accepted, 4097 rejects before Model IO, and absent callbacks stay nil",
       %{store: store} do
    exact = String.duplicate("x", 4094)
    assert byte_size(Jason.encode!(exact)) == 4096
    original = %JournalModel{owner: self(), mode: :return, binding: exact}
    assert ExAgent.Model.continuation_binding(original) == {:ok, exact}
    assert ExAgent.Model.continuation_binding(%ExAgent.Models.Test{}) == {:ok, nil}

    assert {:error, :model_continuation_binding_too_large} =
             ExAgent.Model.continuation_binding(%{original | binding: exact <> "x"})

    for invalid <- [self(), fn -> :secret end, {:secret, "not portable"}] do
      assert {:error, :invalid_model_continuation_binding} =
               ExAgent.Model.continuation_binding(%{original | binding: invalid})
    end

    assert {:error, _} =
             ExAgent.run(ExAgent.new(model: %{original | binding: exact <> "x"}), "input",
               continuation: config(store)
             )

    refute_receive {:model_effect, _, _, _}, 0

    assert {:ok, %{output: "raw"}} =
             ExAgent.run(ExAgent.new(model: original), "input", continuation: config(store))

    assert_receive {:model_effect, _, 0, _}
    assert {:ok, %{record: record}} = Continuation.get(store, "conversation")
    assert record["execution"]["progress"]["runtime"]["model_binding"] == exact
    assert record["execution"]["progress"]["runtime"]["frame_version"] == 3
  end

  test "uncertain Model response/state reconcile validates host binding without repeating Model or hook",
       %{store: store} do
    agent =
      ExAgent.new(model: %JournalModel{owner: self()}, capabilities: [%AfterModel{owner: self()}])

    config = config(store)
    {:ok, runner} = Task.start(fn -> ExAgent.run(agent, "input", continuation: config) end)
    assert_receive {:model_effect, ^runner, 0, response}, 2_000
    monitor = Process.monitor(runner)
    Process.exit(runner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^runner, :killed}
    record = recover(store)
    assert record["execution"]["state"] == "uncertain"
    [{effect_id, _}] = Enum.to_list(record["execution"]["effects"])
    effective = %{response | parts: [%Part.Text{content: "effective"}]}
    evidence = %{response: effective, model_data: %{"index" => 1}}
    opts = admin(record, "reconcile-model") ++ [agent: agent, continuation: config]

    invalid = [
      {evidence, Keyword.put(opts, :authorize, fn _, _, _ -> :deny end)},
      {evidence, Keyword.put(opts, :revision, record["revision"] - 1)},
      {evidence,
       Keyword.put(opts, :continuation, put_in(config, [:definition, "version"], "changed"))},
      {%{evidence | model_data: %{"index" => 1, "discarded" => true}}, opts},
      {%{evidence | response: %{effective | parts: [%Part.Text{content: "invalid-profile"}]}},
       opts},
      {Map.put(evidence, :accounting, %{
         "unknown-node" => Usage.to_map(%Usage{input_tokens: 2, output_tokens: 3})
       }), opts}
    ]

    for {bad, bad_opts} <- invalid do
      assert {:error, _} =
               Continuation.reconcile_model(store, "conversation", effect_id, bad, bad_opts)

      {:ok, %{record: unchanged}} = Continuation.get(store, "conversation")
      assert unchanged["revision"] == record["revision"]
      refute_receive {:model_effect, _, _, _}
      refute_receive :after_model
    end

    assert {:ok, %{record: reconciled}} =
             Continuation.reconcile_model(store, "conversation", effect_id, evidence, opts)

    assert reconciled["execution"]["state"] == "ready"

    reference = %{
      id: "conversation",
      record_id: reconciled["record_id"],
      revision: reconciled["revision"]
    }

    assert {:ok, result} = ExAgent.resume(agent, reference, continuation: config)
    assert result.output == "effective"
    assert result.model.index == 1
    assert result.request_count == 1
    assert result.usage.input_tokens == 2 and result.usage.output_tokens == 3
    assert result.usage.accounting["cost"]["availability"] == "unavailable"
    refute_receive {:model_effect, _, _, _}
    refute_receive :after_model
  end

  test "known Model effect with unavailable portable state is repaired explicitly without replaying after-model",
       %{store: store} do
    agent =
      ExAgent.new(
        model: %JournalModel{owner: self(), mode: :return},
        capabilities: [%AfterModel{owner: self()}]
      )

    config = config(store)

    broken =
      put_in(config, [:model_codec, :dump], fn
        %{index: 0} -> {:ok, %{"index" => 0}}
        _ -> {:error, :fixture_codec_unavailable}
      end)

    assert {:error, _} = ExAgent.run(agent, "input", continuation: broken)
    assert_receive {:model_effect, _, 0, response}
    assert_receive :after_model
    record = recover(store)
    [{effect_id, effect}] = Enum.to_list(record["execution"]["effects"])
    assert effect["state"] == "confirmed"
    assert effect["outcome"]["data"]["state_available"] == false

    evidence = %{
      response: %{response | parts: [%Part.Text{content: "effective"}]},
      model_data: %{"index" => 1}
    }

    assert {:ok, %{record: reconciled}} =
             Continuation.reconcile_model(
               store,
               "conversation",
               effect_id,
               evidence,
               admin(record, "restore-model-data") ++ [agent: agent, continuation: config]
             )

    reference = %{
      id: "conversation",
      record_id: reconciled["record_id"],
      revision: reconciled["revision"]
    }

    assert {:ok, %{output: "effective", request_count: 1}} =
             ExAgent.resume(agent, reference, continuation: config)

    refute_receive {:model_effect, _, _, _}
    refute_receive :after_model
  end

  test "two uncertain child Models reconcile independently and neither child Model is replayed",
       %{store: store} do
    owner = self()

    definitions =
      Map.new(["left", "right"], fn label ->
        child = ExAgent.new(model: %JournalModel{owner: owner, label: label})

        refs =
          config(store)
          |> Map.take([:definition, :policy, :model_ref, :model_codec])
          |> put_in([:definition, "id"], label)

        {label, {child, refs}}
      end)

    tools =
      Enum.map(definitions, fn {label, {child, refs}} ->
        ExAgent.Coordination.delegation_tool(child, name: label, continuation: refs)
      end)

    calls =
      for label <- ["left", "right"],
          do: %Part.ToolCall{tool_name: label, tool_call_id: label, args: %{"prompt" => label}}

    root =
      ExAgent.new(
        model: %ExAgent.Models.Test{script: [%Response{parts: calls}, "done"]},
        tools: tools
      )

    config = %{config(store) | lease_ms: 500}
    {:ok, runner} = Task.start(fn -> ExAgent.run(root, "input", continuation: config) end)

    received =
      for label <- ["left", "right"] do
        assert_receive {:node_model_effect, ^label, pid, 0, response}, 2_000
        {label, pid, response}
      end

    monitors = Enum.map([runner | Enum.map(received, &elem(&1, 1))], &{&1, Process.monitor(&1)})
    Process.exit(runner, :kill)

    for {pid, monitor} <- monitors,
        do: assert_receive({:DOWN, ^monitor, :process, ^pid, _}, 2_000)

    record = recover(store)
    assert record["execution"]["state"] == "uncertain"

    record =
      Enum.reduce(received, record, fn {label, _, response}, current ->
        runtime = current["execution"]["progress"]["runtime"]

        {node_id, _} =
          Enum.find(runtime["children"], fn {_, node} -> node["definition"]["id"] == label end)

        {effect_id, _} =
          Enum.find(current["execution"]["effects"], fn {_, effect} ->
            effect["intent"]["payload"]["run_id"] == node_id
          end)

        {child, refs} = definitions[label]

        evidence = %{
          response: %{response | parts: [%Part.Text{content: label <> " done"}]},
          model_data: %{"index" => 1}
        }

        assert {:ok, %{record: reconciled}} =
                 Continuation.reconcile_model(
                   store,
                   "conversation",
                   effect_id,
                   evidence,
                   admin(current, "reconcile-#{label}") ++ [agent: child, continuation: refs]
                 )

        assert reconciled["execution"]["state"] ==
                 if(label == "left", do: "uncertain", else: "ready")

        reconciled
      end)

    reference = %{
      id: "conversation",
      record_id: record["record_id"],
      revision: record["revision"]
    }

    assert {:ok, %{output: "done", request_count: 4, tool_calls: 2}} =
             ExAgent.resume(root, reference, continuation: config)

    refute_receive {:node_model_effect, _, _, _, _}
  end

  defp recover(store) do
    {:ok, %{record: record}} = Continuation.get(store, "conversation")

    Process.sleep(
      max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)
    )

    {:ok, %{record: recovered}} =
      Continuation.recover(store, "conversation", admin(record, "recover"))

    recovered
  end

  defp admin(record, op),
    do: [
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: op,
      actor: :host,
      authorize: fn :host, _, _ -> {:ok, "operator"} end
    ]

  defp config(store),
    do: %{
      store: store,
      id: "conversation",
      durability: :ephemeral,
      expires_at: nil,
      deadline_at: nil,
      lease_ms: 200,
      active_time_limit_ms: nil,
      definition: %{"id" => "fixture", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      model_ref: %{"id" => "journal-model", "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} when is_integer(index) and index >= 0 ->
          {:ok, %{model | index: index}}
        end
      }
    }
end
