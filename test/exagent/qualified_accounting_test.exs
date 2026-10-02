defmodule ExAgent.QualifiedAccountingTest do
  use ExUnit.Case, async: true
  alias ExAgent.{ExecutionScope, Message, UsageLimits}
  alias ExAgent.Message.Usage
  alias ExAgent.Models.ReqLLM, as: Adapter

  defmodule ReportModel do
    @behaviour ExAgent.Model
    defstruct [:usage, :owner, index: 0]
    def system(_), do: "custom-report"
    def model_name(_), do: "sparse"
    # Logical tools are implemented; accounting remains unknown until reported.
    def profile(_), do: %ExAgent.ModelProfile{supports_tools: true}

    def request(model, _, _, _) do
      send(model.owner, :custom_request)

      parts =
        if model.index == 0,
          do: [
            %Message.Part.ToolCall{tool_name: "effect", tool_call_id: "custom-effect", args: %{}}
          ],
          else: [%Message.Part.Text{content: "done"}]

      {:ok, Message.new_response(parts, usage: model.usage), %{model | index: model.index + 1}}
    end
  end

  test "custom missing and sparse reports fail strict before effects while explicit zero and host-only execute" do
    owner = self()

    tool =
      ExAgent.Tool.new(
        name: "effect",
        takes_ctx: false,
        call: fn _ ->
          send(owner, :custom_effect)
          "ok"
        end
      )

    for usage <- [
          nil,
          %Usage{input_tokens: 0, output_tokens: nil},
          %Usage{input_tokens: nil, output_tokens: 0}
        ] do
      agent =
        ExAgent.new(
          model: %ReportModel{usage: usage, owner: owner},
          tools: [tool],
          usage_limits: %UsageLimits{request_limit: 2, total_tokens_limit: 10}
        )

      assert {:error,
              %ExAgent.RunError{reason: {:accounting_unavailable, _, :missing}, partial: partial}} =
               ExAgent.run(agent, "go")

      assert partial.request_count == 1
      assert_receive :custom_request
      refute_receive :custom_effect, 0

      assert {:ok, result} =
               ExAgent.run(%{agent | usage_limits: %UsageLimits{request_limit: 2}}, "go")

      assert_receive :custom_effect
      assert_receive :custom_request
      assert_receive :custom_request
      assert result.request_count == 2
      assert result.tool_calls == 1
      assert result.usage.accounting["quality"] == "reported"
      assert result.usage_status == :partial
    end

    agent =
      ExAgent.new(
        model: %ReportModel{usage: %Usage{input_tokens: 0, output_tokens: 0}, owner: owner},
        tools: [tool],
        usage_limits: %UsageLimits{request_limit: 2, total_tokens_limit: 10}
      )

    assert {:ok, result} = ExAgent.run(agent, "go")
    assert result.usage_status == :complete
    assert result.usage.input_tokens == 0
    assert_receive :custom_effect

    sparse = %{
      agent
      | model: %ReportModel{usage: %Usage{input_tokens: 0, output_tokens: nil}, owner: owner},
        usage_limits: %UsageLimits{request_limit: 2, input_tokens_limit: 10}
    }

    assert {:ok, result} = ExAgent.run(sparse, "go")
    assert result.usage_status == :partial
    assert result.usage.accounting["availability"]["input"] == "available"
    assert result.usage.accounting["availability"]["output"] == "unavailable"
    assert_receive :custom_effect
  end

  test "ancestor bound enables estimated child but child cannot downgrade strict parent" do
    model = model(:missing, self())

    {:ok, root} =
      ExecutionScope.start("bound", model, usage_limits: %UsageLimits{request_limit: 1})

    on_exit(fn -> ExecutionScope.stop(root) end)

    {:ok, child} =
      ExecutionScope.join(root, "estimated", model,
        usage_limits: %UsageLimits{accounting: :estimated, max_budget_cents: 5}
      )

    assert :ok = ExecutionScope.admit_request(child, "admitted", model)
    assert :ok = ExecutionScope.record_usage(child, "admitted", nil, true)

    assert {:error, {:usage_limit_exceeded, :request_limit, 1}} =
             ExecutionScope.admit_request(child, "over", model)

    {:ok, strict} =
      ExecutionScope.start("strict", model, usage_limits: %UsageLimits{input_tokens_limit: 10})

    on_exit(fn -> ExecutionScope.stop(strict) end)

    {:ok, child} =
      ExecutionScope.join(strict, "attempted-downgrade", model,
        usage_limits: %UsageLimits{
          accounting: :estimated,
          request_limit: 1,
          input_tokens_limit: 10
        }
      )

    assert {:error, {:accounting_unavailable, "input", :normalized_only}} =
             ExecutionScope.admit_request(child, "blocked", model)

    refute_receive :accounting_http, 0
  end

  test "estimated sibling competition keeps the last host admission atomic and policy alone is unconstrained" do
    model = model(:missing, self())

    {:ok, unconstrained} =
      ExecutionScope.start("policy-only", model,
        usage_limits: %UsageLimits{accounting: :estimated}
      )

    assert :ok = ExecutionScope.admit_request(unconstrained, "allowed", model)
    ExecutionScope.stop(unconstrained)

    {:ok, root} =
      ExecutionScope.start("atomic", model,
        usage_limits: %UsageLimits{
          accounting: :estimated,
          request_limit: 1,
          total_tokens_limit: 100
        }
      )

    on_exit(fn -> ExecutionScope.stop(root) end)
    {:ok, a} = ExecutionScope.join(root, "a", model, [])
    {:ok, b} = ExecutionScope.join(root, "b", model, [])

    tasks =
      for {scope, id} <- [{a, "a"}, {b, "b"}],
          do: Task.async(fn -> ExecutionScope.admit_request(scope, id, model) end)

    outcomes = Enum.map(tasks, &Task.await/1)
    assert Enum.count(outcomes, &(&1 == :ok)) == 1

    assert Enum.count(outcomes, &(&1 == {:error, {:usage_limit_exceeded, :request_limit, 1}})) ==
             1

    assert {:ok, %{request_count: 1}} = ExecutionScope.snapshot(root)
    refute_receive :accounting_http, 0
  end

  test "explicit callback precedence never falls back to upstream and missing estimates retain subtotal" do
    model = %ExAgent.Models.Test{}
    usage = Usage.normalized(%{input_tokens: 2, output_tokens: 3, total_cost: 0.001})

    for {callback, expected} <- [
          {nil, 0.1},
          {fn _ -> 0 end, 0},
          {fn _, _ -> 2 end, 2},
          {fn _ -> :unknown end, nil},
          {fn _ -> {:error, :unpriced} end, nil}
        ] do
      {:ok, scope} =
        ExecutionScope.start("price", model,
          estimate_cost: callback,
          usage_limits: %UsageLimits{
            accounting: :estimated,
            request_limit: 2,
            max_budget_cents: 10
          }
        )

      assert :ok = ExecutionScope.admit_request(scope, "one", model)
      assert :ok = ExecutionScope.record_usage(scope, "one", usage, true)
      assert {:ok, first} = ExecutionScope.snapshot(scope)
      assert first.cost_cents == expected

      assert first.usage.accounting["cost"]["source"] ==
               if(callback, do: "estimator", else: "req_llm")

      assert :ok = ExecutionScope.admit_request(scope, "two", model)
      assert :ok = ExecutionScope.record_usage(scope, "two", nil, true)
      assert {:ok, second} = ExecutionScope.snapshot(scope)
      assert second.cost_cents == nil
      assert second.usage.accounting["cost"]["subtotal_cents"] == expected
      ExecutionScope.stop(scope)
    end
  end

  test "version3 snapshot rejects missing corrupt future accounting and v2 preserves unknown values" do
    alias ExAgent.Server.Snapshot
    usage = Usage.normalized(%{input_tokens: 2, output_tokens: 3, total_cost: 0.001})
    snapshot = Snapshot.new(agent_id: "qualified", usage: usage)
    assert {:ok, restored} = snapshot |> Snapshot.serialize() |> Snapshot.deserialize()
    assert restored.version == 4
    assert Snapshot.usage_struct(restored) == usage

    for accounting <- [
          nil,
          %{},
          Map.put(usage.accounting, "version", 2),
          Map.put(usage.accounting, "secret", "forbidden")
        ] do
      bad = %{snapshot | usage: Map.put(snapshot.usage, "accounting", accounting)}
      assert {:error, :invalid_usage} = bad |> Snapshot.serialize() |> Snapshot.deserialize()
    end

    assert {:ok, old} = %{snapshot | version: 2} |> Snapshot.serialize() |> Snapshot.deserialize()
    assert old.usage["input_tokens"] == 2
    assert old.usage["accounting"]["quality"] == "unknown"
    assert old.usage["accounting"]["cost"]["cents"] == nil
  end

  defp model(wire_usage, owner) do
    adapter = fn request ->
      send(owner, :accounting_http)

      body = %{
        "id" => "accounting",
        "model" => "accounting-fixture",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{"role" => "assistant", "content" => "ok"},
            "finish_reason" => "stop"
          }
        ]
      }

      body = if wire_usage == :missing, do: body, else: Map.put(body, "usage", wire_usage)

      {request,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: Jason.encode!(body)
       )}
    end

    Adapter.new(
      model: %{
        provider: :openai,
        id: "accounting-fixture",
        extra: %{wire: %{protocol: "openai_chat"}},
        capabilities: %{tools: %{enabled: true}},
        modalities: %{input: [:text], output: [:text]}
      },
      api_key: "synthetic-key",
      base_url: "https://fixture.invalid/v1",
      http_options: [adapter: ExAgent.Test.ReqTransport.bind(adapter)]
    )
  end

  test "public stock normalization has the same quality for missing null sparse zero and positive metrics" do
    for wire <- [
          :missing,
          nil,
          %{},
          %{"prompt_tokens" => 4},
          %{"completion_tokens" => 2},
          %{"prompt_tokens" => 0, "completion_tokens" => 0, "total_tokens" => 0},
          %{"prompt_tokens" => 4, "completion_tokens" => 2, "total_tokens" => 6}
        ] do
      assert {:ok, result} =
               ExAgent.run(
                 ExAgent.new(
                   model: model(wire, self()),
                   usage_limits: %UsageLimits{request_limit: 1}
                 ),
                 "go"
               )

      assert_receive :accounting_http
      assert result.request_count == 1
      assert result.usage.accounting["quality"] == "normalized"
      assert result.usage.accounting["provider_presence"] == "unknown"
      assert result.usage.accounting["version"] == 1
      assert result.usage_status == :complete

      expected =
        case wire do
          %{"prompt_tokens" => input, "completion_tokens" => output} -> {input, output}
          _ -> {0, 0}
        end

      assert {result.usage.input_tokens, result.usage.output_tokens} == expected
    end
  end

  test "strict stock zero and positive both reject before IO, estimated needs host bound" do
    for wire <- [
          %{"prompt_tokens" => 0, "completion_tokens" => 0},
          %{"prompt_tokens" => 4, "completion_tokens" => 2}
        ] do
      agent = ExAgent.new(model: model(wire, self()))

      assert {:error, %ExAgent.RunError{reason: {:accounting_unavailable, _, :normalized_only}}} =
               ExAgent.run(%{agent | usage_limits: %UsageLimits{input_tokens_limit: 10}}, "go")

      assert {:error, %ExAgent.RunError{reason: :estimated_accounting_requires_request_limit}} =
               ExAgent.run(
                 %{
                   agent
                   | usage_limits: %UsageLimits{accounting: :estimated, input_tokens_limit: 10}
                 },
                 "go"
               )

      refute_receive :accounting_http

      assert {:ok, result} =
               ExAgent.run(
                 %{
                   agent
                   | usage_limits: %UsageLimits{
                       accounting: :estimated,
                       request_limit: 1,
                       max_budget_cents: 10
                     }
                 },
                 "go"
               )

      assert_receive :accounting_http
      assert result.usage.accounting["cost"]["quality"] == "estimated"
    end
  end

  test "normalization selects aliases once and qualifies cents without inventing price" do
    usage =
      Usage.normalized(%{
        input_tokens: 100,
        input: 999,
        output_tokens: 20,
        cached_tokens: 40,
        cached_input: 777,
        reasoning_tokens: 5,
        input_includes_cached: true,
        add_reasoning_to_cost: false,
        total_cost: 0.001,
        cost: %{total: 7}
      })

    assert usage.input_tokens + usage.output_tokens == 120
    assert usage.details["cached_tokens"] == 40
    assert usage.accounting["input_semantics"] == "inclusive"
    assert usage.accounting["reasoning_semantics"] == "included_in_output"
    assert Usage.estimated_cost(usage) == 0.1
    assert Usage.estimated_cost(Usage.normalized(%{total_cost: 0})) == 0
    assert Usage.estimated_cost(Usage.normalized(%{})) == nil
    assert Usage.estimated_cost(Usage.normalized(%{total_cost: -1, cost: %{total: 7}})) == nil
    assert Usage.sum([usage, usage]).accounting["version"] == 1
    assert Usage.sum([usage, nil]).accounting["availability"]["input"] == "partial"
  end

  test "real stock public cost with a priced explicit spec converts USD once and callback wins" do
    wire = %{"prompt_tokens" => 1000, "completion_tokens" => 500, "total_tokens" => 1500}

    for {rates, expected} <- [
          {%{input: 1.0, output: 2.0}, 0.2},
          {%{input: 0.0, output: 0.0}, 0.0}
        ] do
      original = model(wire, self())

      pricing = %{
        currency: "USD",
        components: [
          %{id: "token.input", kind: "token", unit: "token", per: 1_000_000, rate: rates.input},
          %{id: "token.output", kind: "token", unit: "token", per: 1_000_000, rate: rates.output}
        ]
      }

      priced = %{original | model: Map.put(original.model, :pricing, pricing)}
      assert {:ok, result} = ExAgent.run(ExAgent.new(model: priced), "go")
      assert_receive :accounting_http
      assert_in_delta result.cost_cents, expected, 0.000001
      assert result.usage.accounting["cost"]["quality"] == "estimated"
      assert result.usage.accounting["cost"]["source"] == "req_llm"

      assert {:ok, result} =
               ExAgent.run(ExAgent.new(model: priced), "go", estimate_cost: fn _ -> :unknown end)

      assert_receive :accounting_http
      assert result.cost_cents == nil
      assert result.usage.accounting["cost"]["source"] == "estimator"

      for currency <- ["EUR", nil] do
        uncertain = %{
          priced
          | model: Map.put(priced.model, :pricing, %{pricing | currency: currency})
        }

        assert {:ok, result} = ExAgent.run(ExAgent.new(model: uncertain), "go")
        assert_receive :accounting_http
        assert result.cost_cents == nil
        assert result.usage.accounting["cost"]["availability"] == "unavailable"
      end
    end
  end

  test "terminal nil seals while preserving cumulative subtotal and terminal duplicates do not reprice" do
    owner = self()
    model = %ExAgent.Models.Test{}

    {:ok, scope} =
      ExecutionScope.start("qualified", model,
        estimate_cost: fn _ ->
          send(owner, :priced)
          0.5
        end
      )

    on_exit(fn -> ExecutionScope.stop(scope) end)
    assert :ok = ExecutionScope.admit_request(scope, "one", model)
    refute_receive :priced

    assert :ok =
             ExecutionScope.record_usage(scope, "one", %Usage{input_tokens: 1, output_tokens: 1})

    assert_receive :priced
    assert :ok = ExecutionScope.record_usage(scope, "one", nil, true)
    refute_receive :priced
    assert :ok = ExecutionScope.record_usage(scope, "one", nil, true)
    refute_receive :priced

    assert {:error, :request_already_finalized} =
             ExecutionScope.record_usage(
               scope,
               "one",
               %Usage{input_tokens: 2, output_tokens: 3},
               true
             )

    assert {:ok, snapshot} = ExecutionScope.snapshot(scope)
    assert snapshot.usage.input_tokens == 1
    assert snapshot.usage_status == :partial
    assert snapshot.cost_cents == nil
    assert snapshot.usage.accounting["cost"]["subtotal_cents"] == 0.5
    assert snapshot.usage.accounting["availability"]["input"] == "partial"
    assert snapshot.request_count == 1
  end

  test "public estimated cost is independent of token availability and nil terminal preserves its subtotal" do
    model = %ExAgent.Models.Test{}

    for public <- [%{total_cost: 0.001}, %{input_tokens: 2, output_tokens: 3, total_cost: 0.001}] do
      {:ok, scope} = ExecutionScope.start("upstream-subtotal", model, [])
      assert :ok = ExecutionScope.admit_request(scope, "one", model)
      usage = Usage.normalized(public)
      assert :ok = ExecutionScope.record_usage(scope, "one", usage)
      assert {:ok, before} = ExecutionScope.snapshot(scope)
      assert before.usage.accounting["cost"]["subtotal_cents"] == 0.1
      assert :ok = ExecutionScope.record_usage(scope, "one", nil, true)
      assert {:ok, after_nil} = ExecutionScope.snapshot(scope)
      assert after_nil.cost_cents == nil
      assert after_nil.usage.accounting["cost"]["subtotal_cents"] == 0.1
      assert after_nil.usage.accounting["cost"]["availability"] == "partial"
      ExecutionScope.stop(scope)
    end

    {:ok, scope} = ExecutionScope.start("cost-only", model, [])
    assert :ok = ExecutionScope.admit_request(scope, "one", model)

    assert :ok =
             ExecutionScope.record_usage(
               scope,
               "one",
               Usage.normalized(%{total_cost: 0.001}),
               true
             )

    assert {:ok, %{cost_cents: 0.1, usage_status: :partial}} = ExecutionScope.snapshot(scope)
    ExecutionScope.stop(scope)
  end

  test "JSON retains accounting and old data remains unknown with preserved subtotal" do
    usage = Usage.normalized(%{input_tokens: 0, output_tokens: 3, total_cost: 0.001})
    history = [Message.new_response([], usage: usage)]
    assert {:ok, ^history} = history |> Message.to_json() |> Message.from_json()
    legacy = Usage.from_map!(%{"input_tokens" => 12, "output_tokens" => 0})
    assert legacy.input_tokens == 12
    assert legacy.accounting["source"] == "legacy_snapshot"
    assert legacy.accounting["quality"] == "unknown"
    refute Usage.complete?(legacy)

    assert_raise ArgumentError, fn ->
      Usage.from_map!(%{
        "input_tokens" => 1,
        "output_tokens" => 1,
        "accounting" => Map.put(usage.accounting, "version", 2)
      })
    end
  end

  test "aggregate details sum canonical counters once and omit metadata associatively across restore" do
    a = %Usage{
      input_tokens: 1,
      output_tokens: 1,
      details: %{cached_tokens: 2, price: 1, version: 1}
    }

    b = %{a | details: %{"cached_tokens" => 3, "price" => 2, "version" => 1}}
    c = %{a | details: %{"cache_read_input_tokens" => 4, "price" => 1, "version" => 1}}

    restored =
      Usage.add(a, b) |> Usage.to_map() |> Jason.encode!() |> Jason.decode!() |> Usage.from_map!()

    for total <- [Usage.sum([a, b, c]), Usage.add(a, Usage.add(b, c)), Usage.add(restored, c)] do
      assert total.details == %{"cached_tokens" => 9}
      assert total.accounting["availability"]["cache_read"] == "available"
      assert total.accounting["version"] == 1
      assert Usage.validate(total) == :ok
    end

    duplicate = %{
      a
      | details: %{"cached_tokens" => 2, "cache_read_input_tokens" => 200, cached_tokens: 100}
    }

    assert Usage.add(duplicate, b).details == %{"cached_tokens" => 5}
    assert Usage.sum([a]).details == a.details
  end
end
