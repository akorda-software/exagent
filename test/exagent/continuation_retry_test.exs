defmodule ExAgent.ContinuationRetryTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, Store, Tool}
  alias ExAgent.Message.{Part, Request, Response, Usage}

  defmodule SelectRequest do
    use ExAgent.Capability
    defstruct [:owner]

    def before_model_request(hook, state) do
      send(hook.owner, :before_model)

      %{
        state
        | request_messages: [%Request{parts: [%Part.User{content: "projected"}]}],
          params: %{
            state.params
            | instructions: [%Part.System{content: "selected"}],
              idempotency_key: "stable-model-key"
          }
      }
    end
  end

  defmodule RetryModel do
    @behaviour ExAgent.Model
    defstruct [:owner, :journal, index: 0]
    def model_name(_), do: "retry-model"
    def system(_), do: "synthetic"
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: false}
    def validate_resume(_, _, _, _), do: :ok

    def request(model, messages, _, params) do
      attempt = Agent.get_and_update(model.journal, &{&1 + 1, &1 + 1})

      send(
        model.owner,
        {:model_attempt, self(), attempt, params.idempotency_key,
         ExAgent.Message.to_json(messages), params.instructions}
      )

      if attempt == 1,
        do:
          (receive do
             :release -> :ok
           end)

      response = %Response{
        parts: [%Part.Text{content: "retried model"}],
        usage: %Usage{input_tokens: 2, output_tokens: 3}
      }

      {:ok, response, %{model | index: model.index + 1}}
    end
  end

  defmodule FloatArgs do
    use ExAgent.Capability
    defstruct []
    def before_tool_execute(_, _, call), do: %{call | args: %{"n" => 1.0}}
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    %{store: Store.scoped({Store.ETS, __MODULE__}, "retry")}
  end

  test "explicit tool retry delivers key, counts a new reservation, retains unknown cost and requires retention acknowledgement",
       %{store: store} do
    owner = self()

    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"n" => %{"type" => "number"}}
        },
        call: fn ctx, args ->
          send(owner, {:tool_attempt, self(), ctx.idempotency_key, args})

          if is_nil(ctx.idempotency_key),
            do:
              (receive do
                 :release -> :ok
               end)

          {:ok, "retried", %Usage{input_tokens: 1, output_tokens: 1}}
        end
      )

    model = %ExAgent.Models.Test{
      script: [
        %Response{
          parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{"n" => 1}}]
        },
        "done"
      ]
    }

    agent = ExAgent.new(model: model, tools: [tool])
    config = config(store)
    {:ok, runner} = Task.start(fn -> ExAgent.run(agent, "input", continuation: config) end)
    assert_receive {:tool_attempt, _, nil, %{"n" => 1}}, 2_000
    kill(runner)
    record = recover(store)
    {:ok, %{retryable_effects: [binding]}} = Continuation.get(store, "conversation")
    original = record["execution"]["effects"][binding.effect_id]

    opts = [
      operation_id: "retry-tool",
      actor: :host,
      authorize: &authorize/3,
      idempotency_key: "tool-key"
    ]

    assert {:error, :invalid_effect_retry} =
             Continuation.retry_effect(store, "conversation", binding, opts)

    assert {:ok, %{record: authorized}} =
             Continuation.retry_effect(
               store,
               "conversation",
               binding,
               Keyword.put(opts, :accept_duplicate_risk, true)
             )

    assert authorized["execution"]["state"] == "ready"
    assert authorized["execution"]["effects"][binding.effect_id] === original
    refute_receive {:tool_attempt, _, _, _}
    event = fn event -> send(owner, {:event, event.type, event.data}) end

    assert {:ok, result} =
             ExAgent.resume(agent, reference(authorized), continuation: config, on_event: event)

    assert result.output == "done"
    assert result.tool_calls == 2
    assert result.effect_attempts["tool"] == 2
    assert result.historical_uncertainty.count == 1
    assert result.usage_status == :partial
    assert_receive {:tool_attempt, _, "tool-key", %{"n" => 1}}
    assert_receive {:event, :run_finished, %{historical_uncertainty: %{count: 1}}}
    refute_receive {:tool_attempt, _, _, _}

    {:ok, %{record: completed, historical_uncertainty: risk}} =
      Continuation.get(store, "conversation")

    assert completed["execution"]["effects"][binding.effect_id] === original

    assert {:ok, %{replayed: true}} =
             Continuation.retry_effect(
               store,
               "conversation",
               binding,
               Keyword.put(opts, :accept_duplicate_risk, true)
             )

    refute_receive {:tool_attempt, _, _, _}
    {:ok, page} = Continuation.prune_page(store, completed["updated_at"] + 1, "host")
    assert [{_, {:error, :active_or_retained}}] = page.results
    assert {:error, _} = ExAgent.run(agent, "new run", continuation: config)
    refute_receive {:tool_attempt, _, _, _}

    assert {:ok, %{record: acknowledged}} =
             Continuation.acknowledge_history(
               store,
               "conversation",
               admin(completed, "ack-retention") ++
                 [evidence_hash: risk.evidence_hash, allow_evidence_deletion: true]
             )

    assert acknowledged["execution"]["effects"][binding.effect_id] === original
    {:ok, page} = Continuation.prune_page(store, acknowledged["updated_at"] + 1, "host")
    assert [{_, {:ok, _}}] = page.results
    assert {:error, :not_found} = Continuation.get(store, "conversation")
  end

  test "Model retry preserves the effective request and delivers its original key without repeating before-model",
       %{store: store} do
    owner = self()
    journal = start_supervised!({Agent, fn -> 0 end})

    agent =
      ExAgent.new(
        model: %RetryModel{owner: owner, journal: journal},
        capabilities: [%SelectRequest{owner: owner}]
      )

    config = config(store)

    {:ok, runner} =
      Task.start(fn -> ExAgent.run(agent, "canonical input", continuation: config) end)

    assert_receive :before_model
    assert_receive {:model_attempt, ^runner, 1, "stable-model-key", messages, instructions}, 2_000
    kill(runner)
    record = recover(store)
    {:ok, %{retryable_effects: [binding]}} = Continuation.get(store, "conversation")
    original = record["execution"]["effects"][binding.effect_id]

    opts = [
      operation_id: "retry-model",
      actor: :host,
      authorize: &authorize/3,
      idempotency_key: "stable-model-key",
      accept_duplicate_risk: true
    ]

    assert {:error, :invalid_effect_retry} =
             Continuation.retry_effect(
               store,
               "conversation",
               binding,
               Keyword.put(opts, :idempotency_key, "changed-key")
             )

    assert {:ok, %{record: authorized}} =
             Continuation.retry_effect(store, "conversation", binding, opts)

    price = fn _ ->
      send(owner, :priced_retry)
      11
    end

    assert {:ok, result} =
             ExAgent.resume(agent, reference(authorized),
               continuation: config,
               estimate_cost: price
             )

    assert result.output == "retried model" and result.model.index == 1
    assert result.request_count == 2
    assert result.effect_attempts["model"] == 2
    assert result.historical_uncertainty.count == 1
    assert result.usage_status == :partial
    assert result.usage.accounting["cost"]["availability"] == "partial"
    assert result.usage.accounting["cost"]["subtotal_cents"] == 11
    assert_receive {:model_attempt, _, 2, "stable-model-key", ^messages, ^instructions}
    assert_receive :priced_retry
    refute_receive :priced_retry
    refute_receive :before_model
    refute_receive {:model_attempt, _, _, _, _, _}
    {:ok, %{record: completed}} = Continuation.get(store, "conversation")
    assert completed["execution"]["effects"][binding.effect_id] === original

    assert {:ok, %{replayed: true}} =
             Continuation.retry_effect(store, "conversation", binding, opts)

    refute_receive {:model_attempt, _, _, _, _, _}
  end

  test "retry authorization is fenced across two callers and cannot reuse a receipt with another key",
       %{store: store} do
    {agent, config, record, binding, journal} = uncertain_tool(store, self())
    opts = retry_options("race-a", "same-key")

    assert {:error, :unauthorized} =
             Continuation.retry_effect(
               store,
               "conversation",
               binding,
               Keyword.put(opts, :authorize, fn _, _, _ -> :deny end)
             )

    assert {:error, _} =
             Continuation.retry_effect(
               store,
               "conversation",
               %{binding | revision: binding.revision - 1},
               opts
             )

    assert {:error, _} =
             Continuation.retry_effect(
               store,
               "conversation",
               %{binding | intent_hash: String.duplicate("0", 64)},
               opts
             )

    tasks =
      for operation <- ["race-a", "race-b"],
          do:
            Task.async(fn ->
              Continuation.retry_effect(
                store,
                "conversation",
                binding,
                retry_options(operation, "same-key")
              )
            end)

    results = Enum.map(tasks, &Task.await/1)
    assert [{:ok, %{record: authorized}}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert [{:error, :conflict}] = Enum.filter(results, &match?({:error, _}, &1))
    assert Agent.get(journal, & &1) == 1

    assert authorized["execution"]["effects"][binding.effect_id] ===
             record["execution"]["effects"][binding.effect_id]

    operation = Enum.find(["race-a", "race-b"], &Map.has_key?(authorized["receipts"], &1))

    assert {:error, :operation_conflict} =
             Continuation.retry_effect(
               store,
               "conversation",
               binding,
               retry_options(operation, "other-key")
             )

    assert {:ok, %{replayed: true}} =
             Continuation.retry_effect(
               store,
               "conversation",
               binding,
               retry_options(operation, "same-key")
             )

    key = {store.namespace, :agent, "conversation"}
    {:ok, physical} = ExAgent.Continuation.Record.key(key)
    {:ok, original_bytes} = ExAgent.Continuation.Record.encode(authorized, key)

    for {field, value} <- [
          {"idempotency_key", "tampered-key"},
          {"new_effect_id", binding.effect_id},
          {"operation_id", "missing-receipt"}
        ] do
      corrupt =
        put_in(
          authorized,
          ["execution", "progress", "effect_retries", binding.effect_id, field],
          value
        )

      :ets.insert(__MODULE__, {physical, Jason.encode!(corrupt)})

      assert {:error, %{reason: :invalid_record}} =
               ExAgent.resume(agent, reference(authorized), continuation: config)

      assert Agent.get(journal, & &1) == 1
    end

    :ets.insert(__MODULE__, {physical, original_bytes})

    assert {:ok, %{tool_calls: 2}} =
             ExAgent.resume(agent, reference(authorized), continuation: config)

    assert_receive {:counted_tool, _, 2, "same-key", %{"n" => 1}}
    assert Agent.get(journal, & &1) == 2
  end

  test "current effective arguments and ancestor tool budget reject retry before IO without spending its reservation twice",
       %{store: store} do
    {agent, config, _, binding, journal} = uncertain_tool(store, self())

    {:ok, %{record: authorized}} =
      Continuation.retry_effect(
        store,
        "conversation",
        binding,
        retry_options("authorize", "same-key")
      )

    changed = %{agent | capabilities: [%FloatArgs{}]}

    assert {:error, %{reason: :retry_payload_changed}} =
             ExAgent.resume(changed, reference(authorized), continuation: config)

    assert Agent.get(journal, & &1) == 1
    ready = recover(store)
    restricted = %{agent | usage_limits: %ExAgent.UsageLimits{tool_calls_limit: 1}}

    assert {:error, %{reason: {:usage_limit_exceeded, :tool_calls, 2}}} =
             ExAgent.resume(restricted, reference(ready), continuation: config)

    assert Agent.get(journal, & &1) == 1
    ready = recover(store)

    assert ready["execution"]["progress"]["runtime"]["scope"]["nodes"][
             ready["execution"]["run_id"]
           ]["tools"] == 1

    assert {:ok, %{tool_calls: 2}} = ExAgent.resume(agent, reference(ready), continuation: config)
    assert_receive {:counted_tool, _, 2, "same-key", %{"n" => 1}}
    assert Agent.get(journal, & &1) == 2
  end

  test "death after the new intent requires another explicit linked decision and keeps both uncertain originals",
       %{store: store} do
    {agent, config, record, binding, journal} = uncertain_tool(store, self(), [1, 2])

    {:ok, %{record: authorized}} =
      Continuation.retry_effect(
        store,
        "conversation",
        binding,
        retry_options("first-retry", "stable-key")
      )

    {:ok, runner} =
      Task.start(fn -> ExAgent.resume(agent, reference(authorized), continuation: config) end)

    assert_receive {:counted_tool, _, 2, "stable-key", %{"n" => 1}}, 2_000
    kill(runner)
    uncertain = recover(store)
    assert uncertain["execution"]["state"] == "uncertain"

    assert {:error, %{reason: :continuation_conflict}} =
             ExAgent.resume(agent, reference(uncertain), continuation: config)

    {:ok, %{retryable_effects: [second], historical_uncertainty: %{count: 1}}} =
      Continuation.get(store, "conversation")

    refute second.effect_id == binding.effect_id
    second_original = uncertain["execution"]["effects"][second.effect_id]

    assert {:error, :invalid_effect_retry} =
             Continuation.retry_effect(
               store,
               "conversation",
               second,
               retry_options("second-retry", "changed-key")
             )

    {:ok, %{record: authorized}} =
      Continuation.retry_effect(
        store,
        "conversation",
        second,
        retry_options("second-retry", "stable-key")
      )

    assert {:ok, result} = ExAgent.resume(agent, reference(authorized), continuation: config)
    assert result.tool_calls == 3 and result.effect_attempts["tool"] == 3
    assert result.historical_uncertainty.count == 2 and result.usage_status == :partial
    assert_receive {:counted_tool, _, 3, "stable-key", %{"n" => 1}}
    assert Agent.get(journal, & &1) == 3
    {:ok, %{record: completed}} = Continuation.get(store, "conversation")

    assert completed["execution"]["effects"][binding.effect_id] ===
             record["execution"]["effects"][binding.effect_id]

    assert completed["execution"]["effects"][second.effect_id] === second_original
  end

  test "retry does not replenish an abandoned active budget even when current configuration is looser",
       %{store: store} do
    {agent, config, _, binding, journal} =
      uncertain_tool(store, self(), [1], %{active_time_limit_ms: 1_000})

    {:ok, %{record: authorized}} =
      Continuation.retry_effect(
        store,
        "conversation",
        binding,
        retry_options("bounded-retry", "key")
      )

    for limit <- [nil, 10_000] do
      assert {:error, %{reason: :deadline_exceeded}} =
               ExAgent.resume(agent, reference(authorized),
                 continuation: %{config | active_time_limit_ms: limit}
               )

      assert Agent.get(journal, & &1) == 1
    end

    {:ok, %{record: unchanged}} = Continuation.get(store, "conversation")
    assert unchanged["revision"] == authorized["revision"]
  end

  test "UTC expiry after explicit authorization still prevents the new attempt", %{store: store} do
    expiry = System.system_time(:millisecond) + 1_000

    {agent, config, _, binding, journal} =
      uncertain_tool(store, self(), [1], %{expires_at: expiry})

    {:ok, %{record: authorized}} =
      Continuation.retry_effect(
        store,
        "conversation",
        binding,
        retry_options("expiring-retry", "key")
      )

    Process.sleep(max(expiry - System.system_time(:millisecond) + 1, 0))

    assert {:error, %{reason: :deadline_exceeded}} =
             ExAgent.resume(agent, reference(authorized), continuation: config)

    assert Agent.get(journal, & &1) == 1

    assert {:ok, %{record: expired}} =
             Continuation.decide(store, "conversation", :expire, admin(authorized, "expire"))

    assert expired["execution"]["state"] == "expired"
    assert ExAgent.Continuation.Retry.summary(expired["execution"]).count == 1
  end

  defp uncertain_tool(store, owner, blocked \\ [1], overrides \\ %{}) do
    journal = start_supervised!({Agent, fn -> 0 end})

    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"n" => %{"type" => "number"}}
        },
        call: fn ctx, args ->
          attempt = Agent.get_and_update(journal, &{&1 + 1, &1 + 1})
          send(owner, {:counted_tool, self(), attempt, ctx.idempotency_key, args})

          if attempt in blocked,
            do:
              (receive do
                 :release -> :ok
               end)

          {:ok, "done", %Usage{input_tokens: 1, output_tokens: 1}}
        end
      )

    model = %ExAgent.Models.Test{
      script: [
        %Response{
          parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{"n" => 1}}]
        },
        "done"
      ]
    }

    agent = ExAgent.new(model: model, tools: [tool])
    config = Map.merge(config(store), overrides)
    {:ok, runner} = Task.start(fn -> ExAgent.run(agent, "input", continuation: config) end)
    assert_receive {:counted_tool, _, 1, nil, %{"n" => 1}}, 2_000
    kill(runner)
    record = recover(store)
    {:ok, %{retryable_effects: [binding]}} = Continuation.get(store, "conversation")
    {agent, config, record, binding, journal}
  end

  defp retry_options(operation, key),
    do: [
      operation_id: operation,
      actor: :host,
      authorize: &authorize/3,
      idempotency_key: key,
      accept_duplicate_risk: true
    ]

  defp kill(pid) do
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 2_000
  end

  defp recover(store) do
    {:ok, %{record: record}} = Continuation.get(store, "conversation")

    Process.sleep(
      max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)
    )

    {:ok, %{record: recovered}} =
      Continuation.recover(store, "conversation", admin(record, "recover-#{record["revision"]}"))

    recovered
  end

  defp reference(record),
    do: %{id: "conversation", record_id: record["record_id"], revision: record["revision"]}

  defp authorize(:host, _, _), do: {:ok, "human"}

  defp admin(record, op),
    do: [
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: op,
      actor: :host,
      authorize: &authorize/3
    ]

  defp config(store),
    do: %{
      store: store,
      id: "conversation",
      durability: :ephemeral,
      expires_at: nil,
      deadline_at: nil,
      lease_ms: 300,
      active_time_limit_ms: nil,
      definition: %{"id" => "retry", "version" => "1"},
      policy: %{"id" => "policy", "version" => "1"},
      model_ref: %{"id" => "model", "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }
end
