# A fresh OS/BEAM receives only JSON; all executable configuration is host-owned.
alias ExAgent.{Message, Store, Tool}
alias ExAgent.Continuation.Record
alias ExAgent.Coordination.Composition
[file] = System.argv()
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :output_retry_vm)
store = Store.scoped({Store.ETS, :output_retry_vm}, "retry")
key = {store.namespace, :agent, "sequence"}
bytes = File.read!(file)
{:ok, record} = Record.decode(bytes, key)
{:ok, physical} = Record.key(key)
true = :ets.insert(:output_retry_vm, {physical, bytes})
Process.put(:output_retry_observer, self())
Process.put(:output_retry_trap, :historical)
[child] = Map.values(record["execution"]["progress"]["runtime"]["children"])
n = child["frame"]["run_step"]

historical_cost =
  Enum.reduce(record["execution"]["progress"]["runtime"]["scope"]["operations"], 0, fn op,
                                                                                       total ->
    total +
      (get_in(op, ["ancestors", child["frame"]["run_id"], "accounting", "cost", "cents"]) || 0)
  end)

entry =
  record["execution"]["progress"]["runtime"]["output_resolutions"][
    child["frame"]["model_request_id"]
  ]

success = entry["decision"] == "succeeded"
if success, do: Process.put(:output_retry_trap, :empty)

model = %ExAgent.Models.Test{
  script:
    List.duplicate(fn _, _ -> raise "historical Model replay" end, n) ++
      [
        fn _, params ->
          nil = params.idempotency_key
          if success, do: raise("success requested Model")

          Message.new_response(
            [
              %Message.Part.ToolCall{
                tool_call_id: "second",
                tool_name: "final_result",
                args: %{"count" => 9}
              }
            ],
            finish_reason: :tool_calls,
            usage: %Message.Usage{input_tokens: 5, output_tokens: 4}
          )
        end
      ]
}

step = %{
  id: "A",
  agent:
    ExAgent.new(
      model: model,
      output_type: ExAgent.CompositionOutputRetryFixture.Output,
      output_retries: n,
      max_steps: n + 1,
      usage_limits: %ExAgent.UsageLimits{request_limit: n + 1},
      tools: [
        Tool.new(
          name: "sibling",
          parameters_json_schema: %{type: "object"},
          call: fn _, _ -> raise "sibling replay" end
        )
      ]
    ),
  model_codec: %{
    dump: fn m -> {:ok, %{"index" => m.index}} end,
    load: fn m, data -> {:ok, %{m | index: data["index"]}} end
  },
  definition: %{id: "leaf", version: "1"},
  policy: %{id: "policy", version: "1"},
  model_ref: %{id: "model", version: "1"},
  output_ref: %{id: "output", version: "1"}
}

{:ok, definition} = Composition.new(id: "sequence", version: "1", steps: [step])

config = %{
  kind: :composition,
  composition: definition,
  store: store,
  id: "sequence",
  definition: %{"id" => "sequence", "version" => "1"},
  policy: %{"id" => "policy", "version" => "1"},
  durability: :ephemeral,
  expires_at: nil,
  lease_ms: 60_000
}

reference = %{id: "sequence", record_id: record["record_id"], revision: record["revision"]}

{:ok, result} =
  ExAgent.resume_composition_step(definition, reference,
    continuation: config,
    estimate_cost: fn _ -> 5 end,
    root_options: [estimate_cost: fn _, _ -> 11 end]
  )

complete_cost = child["snapshot"]["usage"]["accounting"]["cost"]["availability"] == "available"

if success do
  true = result.output == entry["result"]
  true = result.request_count == n
  true = result.cost_cents == if(complete_cost, do: historical_cost, else: nil)
  true = result.usage.accounting["cost"]["subtotal_cents"] == historical_cost
else
  %{count: 9} = result.output
  true = result.request_count == n + 1
  true = result.cost_cents == if(complete_cost, do: historical_cost + 5, else: nil)
  true = result.usage.accounting["cost"]["subtotal_cents"] == historical_cost + 5
  empty = %{}
  receive do: ({:changeset, ^empty} -> :ok)
  receive do: ({:changeset, %{"count" => 9}} -> :ok)
end

receive do
  {:changeset, _} -> raise "extra validation"
after
  0 -> :ok
end

{:ok, final} = Store.load_record(store, :agent, "sequence")
"completed" = final["execution"]["state"]
{:ok, _} = Record.encode(final, key)

IO.puts(
  "NEW_VM_RETRY_COMPLETED historical=0 reflection=#{if(success, do: 0, else: 1)} new_validation=#{if(success, do: 0, else: 1)} requests=#{result.request_count}"
)
