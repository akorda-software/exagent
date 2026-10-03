defmodule ExAgent.ContinuationTreeBoundariesTest do
  use ExUnit.Case, async: false
  alias ExAgent.{Continuation, Coordination, Message, Permissions, Retention, Store, Tool}
  alias ExAgent.Continuation.Record
  alias ExAgent.Message.{Part, Response, Usage}

  defmodule TraceStore do
    def capabilities(_), do: %{continuation: :atomic, durability: :ephemeral}
    def load_record({table, _}, key), do: Store.ETS.load_record(table, key)

    def scan_records({table, _}, namespace, query),
      do: Store.ETS.scan_records(table, namespace, query)

    def transition({table, control}, {namespace, _, id} = key, revision, command) do
      token = %{
        "token_version" => 1,
        "namespace" => namespace,
        "id" => id,
        "expected_revision" => if(revision == :absent, do: "absent", else: revision),
        "command" => command
      }

      mode =
        Agent.get_and_update(control, fn data ->
          matched = matches?(command, data.fault)
          mode = if matched, do: elem(data.fault, 2), else: :ok

          {mode,
           %{
             data
             | fault: if(matched, do: nil, else: data.fault),
               sizes: [Retention.bytes(token) | data.sizes]
           }
           |> Map.put(:last_command, command)}
        end)

      case mode do
        :before ->
          {:error, :fixture_before_commit}

        :after ->
          {:ok, _} = Store.ETS.transition(table, key, revision, command)
          {:error, :fixture_ack_lost}

        :ok ->
          Store.ETS.transition(table, key, revision, command)
      end
    end

    defp matches?(_, nil), do: false

    defp matches?(
           %{"operation" => "begin_effect", "payload" => %{"intent" => %{"kind" => "model"}}},
           {"begin_effect", "model", _}
         ),
         do: true

    defp matches?(
           %{"operation" => "node_checkpoint", "payload" => payload},
           {"node_checkpoint", "completed", _}
         ),
         do:
           get_in(payload, ["progress", "runtime", "children", payload["node_id"], "status"]) ==
             "completed"

    defp matches?(
           %{"operation" => "delegation_outcome", "payload" => payload},
           {"delegation_outcome", phase, _}
         ),
         do:
           get_in(payload, [
             "progress",
             "runtime",
             "children",
             payload["node_id"],
             "outcome",
             "data",
             "phase"
           ]) == phase

    defp matches?(_, _), do: false
  end

  defmodule AfterDelegate do
    use ExAgent.Capability
    defstruct [:control]

    def after_tool_execute(hook, _, %{tool_name: "delegate"}, {:ok, part}) do
      Agent.update(hook.control, fn data ->
        update_in(data.calls, &Map.update(&1, :hook, 1, fn n -> n + 1 end))
      end)

      {:ok, %{part | content: "hooked"}}
    end

    def after_tool_execute(_, _, _, result), do: result
  end

  setup do
    start_supervised!({Store.ETS, table: __MODULE__})
    control = start_supervised!({Agent, fn -> %{fault: nil, sizes: [], calls: %{}} end})
    store = Store.scoped({TraceStore, {__MODULE__, control}}, "tree-boundary")
    %{store: store, control: control}
  end

  test "complete token J has a public exact threshold and its minus-one rejects before child Model IO",
       ctx do
    trial = fn limit ->
      :ets.delete_all_objects(__MODULE__)
      Agent.update(ctx.control, fn _ -> %{fault: nil, sizes: [], calls: %{}} end)

      result =
        ExAgent.run(agent(ctx.control, true), "input", continuation: config(ctx.store, limit))

      {result, Agent.get(ctx.control, & &1)}
    end

    assert {{:ok, %{status: :paused}}, _} = trial.(Record.max_bytes())
    exact = threshold(1, Record.max_bytes(), trial)
    assert {{:ok, %{status: :paused}}, trace} = trial.(exact)
    assert trace.calls[{:model, :root, 0}] == 1 and trace.calls[{:model, :child, 0}] == 1
    assert Enum.all?(trace.sizes, &(&1 <= exact))

    IO.inspect(%{j: exact, minus_one: exact - 1, largest_dispatched_token: Enum.max(trace.sizes)},
      label: "TREE_J_BOUNDARY"
    )

    assert {{:error, _}, rejected} = trial.(exact - 1)
    assert rejected.calls[{:model, :root, 0}] == 1
    refute Map.has_key?(rejected.calls, {:model, :child, 0})
    refute Map.has_key?(rejected.calls, :effect)
  end

  test "tree JSON plus cleanup fits exactly 8MiB and administrative closure still fits", ctx do
    {:ok, %{status: :paused}} =
      ExAgent.run(agent(ctx.control, true), "input", continuation: config(ctx.store))

    {:ok, %{record: record}} = Continuation.get(ctx.store, "agent")
    record = put_in(record, ["snapshot", "metadata", "padding"], "")
    reserve = Record.cleanup_reserve_bytes(record)
    padding = Record.max_bytes() - byte_size(Jason.encode!(record)) - reserve
    exact = put_in(record, ["snapshot", "metadata", "padding"], String.duplicate("x", padding))
    key = {ctx.store.namespace, :agent, "agent"}

    assert byte_size(Jason.encode!(exact)) + Record.cleanup_reserve_bytes(exact) ==
             Record.max_bytes()

    IO.inspect(
      %{
        json: byte_size(Jason.encode!(exact)),
        cleanup_reserve: Record.cleanup_reserve_bytes(exact),
        cap: Record.max_bytes()
      },
      label: "TREE_JSON_BOUNDARY"
    )

    assert {:ok, _} = Record.encode(exact, key)
    over = update_in(exact, ["snapshot", "metadata", "padding"], &(&1 <> "x"))
    assert {:error, :record_limit} = Record.encode(over, key)
    import_record(ctx.store, exact)
    actor = String.duplicate(<<1>>, 512)

    {:ok, %{record: approved}} =
      Continuation.decide(
        ctx.store,
        "agent",
        :approve,
        decision(exact)
        |> Keyword.put(:operation_id, actor)
        |> Keyword.put(:authorize, fn :host, _, _ -> {:ok, actor} end)
      )

    assert {:ok, %{record: cancelled}} =
             Continuation.decide(ctx.store, "agent", :cancel, admin(approved, "cancel"))

    assert cancelled["execution"]["state"] == "cancelled"
    assert cancelled["execution"]["effects"] === record["execution"]["effects"]
    assert byte_size(Jason.encode!(cancelled)) <= Record.max_bytes()
    refute Map.has_key?(Agent.get(ctx.control, & &1.calls), :effect)
  end

  test "tree receipt horizon rejects new claims at capacity but preserves approve/cancel cleanup",
       ctx do
    {:ok, %{status: :paused}} =
      ExAgent.run(agent(ctx.control, true), "input", continuation: config(ctx.store))

    {:ok, %{record: record}} = Continuation.get(ctx.store, "agent")
    count = 1024 - Record.receipt_reserve(record["execution"])
    template = record["receipts"] |> Map.values() |> hd()
    receipts = Map.new(1..count, fn n -> {"receipt-#{n}", %{template | "revision" => n}} end)
    exact = %{record | "revision" => count, "receipts" => receipts}
    assert map_size(exact["receipts"]) + Record.receipt_reserve(exact["execution"]) == 1024

    IO.inspect(
      %{
        receipts: map_size(exact["receipts"]),
        reserve: Record.receipt_reserve(exact["execution"]),
        cap: 1024
      },
      label: "TREE_RECEIPT_BOUNDARY"
    )

    assert {:ok, _} = Record.encode(exact, {ctx.store.namespace, :agent, "agent"})

    over = %{
      exact
      | "revision" => count + 1,
        "receipts" => Map.put(receipts, "extra", %{template | "revision" => count + 1})
    }

    assert {:error, :invalid_record} = Record.encode(over, {ctx.store.namespace, :agent, "agent"})
    import_record(ctx.store, exact)

    {:ok, %{record: approved}} =
      Continuation.decide(ctx.store, "agent", :approve, decision(exact))

    reference = %{id: "agent", record_id: approved["record_id"], revision: approved["revision"]}

    assert {:error, _} =
             ExAgent.resume(agent(ctx.control, true), reference, continuation: config(ctx.store))

    assert {:ok, %{record: cancelled}} =
             Continuation.decide(ctx.store, "agent", :cancel, admin(approved, "cancel"))

    assert cancelled["execution"]["state"] == "cancelled"
    refute Map.has_key?(Agent.get(ctx.control, & &1.calls), :effect)
  end

  test "lost ACK before or after delegated raw/final and child finish retries only exact data",
       ctx do
    for {operation, phase} <- [
          {"node_checkpoint", "completed"},
          {"delegation_outcome", "raw"},
          {"delegation_outcome", "final"}
        ],
        mode <- [:before, :after] do
      :ets.delete_all_objects(__MODULE__)

      Agent.update(ctx.control, fn _ ->
        %{fault: {operation, phase, mode}, sizes: [], calls: %{}}
      end)

      config = config(ctx.store)
      agent = agent(ctx.control, false)
      assert {:error, %{partial: partial}} = ExAgent.run(agent, "input", continuation: config)
      assert is_map(partial.continuation_checkpoint)
      before = Agent.get(ctx.control, & &1.calls)
      assert {:ok, _} = Continuation.retry_checkpoint(ctx.store, partial.continuation_checkpoint)

      assert {:ok, %{replayed: true}} =
               Continuation.retry_checkpoint(ctx.store, partial.continuation_checkpoint)

      assert Agent.get(ctx.control, & &1.calls) == before
      ready = recover(ctx.store)
      reference = %{id: "agent", record_id: ready["record_id"], revision: ready["revision"]}

      assert {:ok, %{request_count: 3, tool_calls: 1} = result} =
               ExAgent.resume(agent, reference, continuation: config)

      expected = if phase == "raw", do: "child done", else: "hooked"

      assert [%Part.ToolReturn{content: ^expected}] =
               for(
                 part <- Message.parts(result.messages),
                 match?(%Part.ToolReturn{}, part),
                 do: part
               )

      calls = Agent.get(ctx.control, & &1.calls)

      assert calls[{:model, :root, 0}] == 1 and calls[{:model, :child, 0}] == 1 and
               calls[{:model, :root, 1}] == 1

      assert Map.get(calls, :hook, 0) == if(phase == "raw", do: 0, else: 1)
    end
  end

  test "replaying an atomic Model intent ACK never dispatches it; an explicit retry is required",
       ctx do
    for mode <- [:before, :after] do
      :ets.delete_all_objects(__MODULE__)

      Agent.update(ctx.control, fn _ ->
        %{fault: {"begin_effect", "model", mode}, sizes: [], calls: %{}}
      end)

      config = config(ctx.store)
      agent = agent(ctx.control, false)
      {:error, %{partial: partial}} = ExAgent.run(agent, "input", continuation: config)
      assert Agent.get(ctx.control, & &1.calls) == %{}
      assert {:ok, _} = Continuation.retry_checkpoint(ctx.store, partial.continuation_checkpoint)
      assert Agent.get(ctx.control, & &1.calls) == %{}
      uncertain = recover(ctx.store)
      assert uncertain["execution"]["state"] == "uncertain"

      reference = %{
        id: "agent",
        record_id: uncertain["record_id"],
        revision: uncertain["revision"]
      }

      assert {:error, _} = ExAgent.resume(agent, reference, continuation: config)
      {:ok, %{retryable_effects: [binding]}} = Continuation.get(ctx.store, "agent")

      {:ok, %{record: ready}} =
        Continuation.retry_effect(ctx.store, "agent", binding,
          operation_id: "explicit-retry",
          actor: :host,
          authorize: fn :host, _, _ -> {:ok, "human"} end,
          idempotency_key: "model-key",
          accept_duplicate_risk: true
        )

      assert {:ok, %{request_count: 4, historical_uncertainty: %{count: 1}}} =
               ExAgent.resume(agent, %{reference | revision: ready["revision"]},
                 continuation: config
               )

      calls = Agent.get(ctx.control, & &1.calls)
      assert calls[{:model, :root, 0}] == 1 and calls[{:model, :child, 0}] == 1
    end
  end

  test "explicit retry reserves its additional receipts before authorizing new IO", ctx do
    original = uncertain_model(ctx)

    for {count, expected} <- [{1021, :rejected}, {1020, :accepted}] do
      template = original["receipts"] |> Map.values() |> hd()
      receipts = Map.new(1..count, fn n -> {"receipt-#{n}", %{template | "revision" => n}} end)
      record = %{original | "revision" => count, "receipts" => receipts}
      import_record(ctx.store, record)
      {:ok, %{retryable_effects: [binding]}} = Continuation.get(ctx.store, "agent")
      result = Continuation.retry_effect(ctx.store, "agent", binding, retry_options())

      case expected do
        :rejected ->
          assert {:error, :receipt_limit} = result

        :accepted ->
          assert {:ok, %{record: authorized}} = result

          assert map_size(authorized["receipts"]) +
                   Record.receipt_reserve(authorized["execution"]) == 1024

          assert {:ok, _} =
                   Continuation.decide(ctx.store, "agent", :cancel, admin(authorized, "cancel"))
      end

      assert Agent.get(ctx.control, & &1.calls) == %{}
    end
  end

  test "retry authorization JSON growth is measured with its future cleanup at exact and plus-one",
       ctx do
    original = uncertain_model(ctx)
    {:ok, %{retryable_effects: [binding]}} = Continuation.get(ctx.store, "agent")

    {:ok, %{record: sample}} =
      Continuation.retry_effect(ctx.store, "agent", binding, retry_options())

    command = Agent.get(ctx.control, & &1.last_command)
    key = {ctx.store.namespace, :agent, "agent"}
    base = put_in(original, ["snapshot", "metadata", "padding"], "")

    {:ok, %{record: projected}} =
      ExAgent.Continuation.Transition.apply(
        base,
        key,
        base["revision"],
        command,
        sample["updated_at"]
      )

    padding =
      Record.max_bytes() - byte_size(Jason.encode!(projected)) -
        Record.cleanup_reserve_bytes(projected)

    exact = put_in(base, ["snapshot", "metadata", "padding"], String.duplicate("x", padding))

    {:ok, %{record: at_cap}} =
      ExAgent.Continuation.Transition.apply(
        exact,
        key,
        exact["revision"],
        command,
        sample["updated_at"]
      )

    assert byte_size(Jason.encode!(at_cap)) + Record.cleanup_reserve_bytes(at_cap) ==
             Record.max_bytes()

    over = update_in(exact, ["snapshot", "metadata", "padding"], &(&1 <> "x"))

    assert {:error, :record_limit} =
             ExAgent.Continuation.Transition.apply(
               over,
               key,
               over["revision"],
               command,
               sample["updated_at"]
             )

    import_record(ctx.store, exact)

    assert {:ok, %{record: authorized}} =
             Continuation.retry_effect(ctx.store, "agent", binding, retry_options())

    assert {:ok, _} =
             Continuation.decide(ctx.store, "agent", :cancel, admin(authorized, "cancel"))

    assert Agent.get(ctx.control, & &1.calls) == %{}

    IO.inspect(
      %{
        json: byte_size(Jason.encode!(at_cap)),
        cleanup_reserve: Record.cleanup_reserve_bytes(at_cap),
        cap: Record.max_bytes()
      },
      label: "RETRY_JSON_BOUNDARY"
    )
  end

  defp uncertain_model(ctx) do
    Agent.update(ctx.control, &%{&1 | fault: {"begin_effect", "model", :after}})

    assert {:error, _} =
             ExAgent.run(agent(ctx.control, false), "input", continuation: config(ctx.store))

    record = recover(ctx.store)
    assert record["execution"]["state"] == "uncertain"
    assert Agent.get(ctx.control, & &1.calls) == %{}
    record
  end

  defp retry_options,
    do: [
      operation_id: "retry-capacity",
      actor: :host,
      authorize: fn :host, _, _ -> {:ok, "human"} end,
      idempotency_key: "key",
      accept_duplicate_risk: true
    ]

  defp threshold(low, high, _) when low == high, do: low

  defp threshold(low, high, trial) do
    middle = div(low + high, 2)

    case trial.(middle) do
      {{:ok, %{status: :paused}}, _} -> threshold(low, middle, trial)
      _ -> threshold(middle + 1, high, trial)
    end
  end

  defp recover(store) do
    {:ok, %{record: record}} = Continuation.get(store, "agent")

    Process.sleep(
      max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0)
    )

    {:ok, %{record: recovered}} =
      Continuation.recover(store, "agent", admin(record, "recover-#{record["revision"]}"))

    recovered
  end

  defp import_record(store, record) do
    key = {store.namespace, :agent, "agent"}
    {:ok, bytes} = Record.encode(record, key)
    {:ok, physical} = Record.key(key)
    :ets.insert(__MODULE__, {physical, bytes})
  end

  defp admin(record, operation),
    do: [
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: operation,
      actor: :host,
      authorize: fn :host, _, _ -> {:ok, "human"} end
    ]

  defp decision(record) do
    [{id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])
    admin(record, "approve") ++ [approval_id: id, payload_hash: approval["payload_hash"]]
  end

  defp refs(id),
    do: %{
      definition: %{"id" => id, "version" => "1"},
      policy: %{"id" => id, "version" => "1"},
      model_ref: %{"id" => id, "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }

  defp config(store, limit \\ 8_388_608),
    do:
      Map.merge(refs("root"), %{
        store: store,
        id: "agent",
        durability: :ephemeral,
        lease_ms: 500,
        expires_at: nil,
        active_time_limit_ms: nil,
        max_checkpoint_bytes: limit
      })

  defp agent(control, ask?) do
    effect =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        call: fn _, _ ->
          count(control, :effect)
          "effect"
        end
      )

    child_script =
      if ask?,
        do: [
          %Response{
            parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "call", args: %{}}]
          },
          "child done"
        ],
        else: ["child done"]

    child = ExAgent.new(model: model(control, :child, child_script), tools: [effect])

    delegate =
      Coordination.delegation_tool(child,
        name: "delegate",
        continuation: refs("child"),
        permissions: Permissions.new!(default: if(ask?, do: :ask, else: :allow))
      )

    ExAgent.new(
      model:
        model(control, :root, [
          %Response{
            parts: [
              %Part.ToolCall{
                tool_name: "delegate",
                tool_call_id: "call",
                args: %{"prompt" => "child"}
              }
            ]
          },
          "done"
        ]),
      tools: [delegate],
      capabilities: [%AfterDelegate{control: control}]
    )
  end

  defp model(control, label, script),
    do: %ExAgent.Models.Test{
      script:
        Enum.with_index(script, fn value, index ->
          fn _, _ ->
            count(control, {:model, label, index})

            response =
              if is_binary(value), do: %Response{parts: [%Part.Text{content: value}]}, else: value

            %{response | usage: %Usage{input_tokens: 1, output_tokens: 1}}
          end
        end)
    }

  defp count(control, key),
    do:
      Agent.update(control, fn data ->
        update_in(data.calls, &Map.update(&1, key, 1, fn n -> n + 1 end))
      end)
end
