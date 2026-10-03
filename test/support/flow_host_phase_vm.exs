alias ExAgent.{Continuation, Store}
alias ExAgent.Continuation.Record
alias ExAgent.Coordination.Flow
alias ExAgent.DelegationRuntimeFixture, as: F
[path, effects, phase, mode] = System.argv()
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :flow_host_phase_vm)
store = Store.scoped({F.Journal, %{table: :flow_host_phase_vm, path: path}}, "flow-host-vm")
config = Map.merge(F.config(store), %{id: "flow", lease_ms: 800, active_time_limit_ms: 5000})

callback = fn label, value ->
  if mode == "recover", do: raise("uncertain callback repeated")
  File.write!(effects, label <> "\n", [:append])
  if phase == label, do: :erlang.halt(73)
  value
end

agent =
  ExAgent.new(
    model: %ExAgent.Models.Test{
      script: [
        fn _, _ ->
          if mode == "recover", do: raise("confirmed Model repeated")
          File.write!(effects, "model\n", [:append])
          "A"
        end
      ]
    }
  )

branch = %{
  id: "A",
  agent: agent,
  definition: F.reference("A"),
  policy: F.reference("policy"),
  model_ref: F.reference("model"),
  output_ref: F.reference("output"),
  model_codec: F.codec()
}

{:ok, definition} =
  Flow.new(
    id: "host-vm",
    version: "1",
    kind: :router,
    select_version: "1",
    select: fn _ -> callback.("selecting", "A") end,
    merge_version: "1",
    merge: fn outcomes -> callback.("merging", outcomes) end,
    branches: [branch]
  )

if mode == "run" do
  Flow.run(definition, "root", continuation: config)
  raise "crash was not reached"
else
  record = Jason.decode!(File.read!(path))
  F.import(:flow_host_phase_vm, record)
  :ok = Record.validate(record, {"flow-host-vm", :agent, "flow"})
  ^phase = record["execution"]["progress"]["runtime"]["flow"]["phase"]
  true = Record.unresolved?(record["execution"])

  receive do
  after
    max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0) -> :ok
  end

  {:ok, %{record: uncertain}} =
    Continuation.recover(store, "flow",
      record_id: record["record_id"],
      revision: record["revision"],
      operation_id: "recover",
      actor: "host",
      authorize: fn actor, _, _ -> {:ok, actor} end
    )

  "uncertain" = uncertain["execution"]["state"]
  true = uncertain["execution"]["effects"] === record["execution"]["effects"]

  true =
    uncertain["execution"]["progress"]["runtime"] === record["execution"]["progress"]["runtime"]

  0 = uncertain["execution"]["progress"]["active_budget"]["remaining_ms"]
  nil = uncertain["execution"]["progress"]["active_budget"]["refund_at"]

  {:error, %ExAgent.RunError{}} =
    Flow.resume(definition, ExAgent.SequenceApprovalFixture.reference(uncertain),
      continuation: config
    )

  {:ok, ^uncertain} = Store.load_record(store, :agent, "flow")
  IO.puts("FLOW_HOST uncertain without callback replay or budget refund")
end
