alias ExAgent.{Continuation, Store, SequenceApprovalFixture}
alias ExAgent.SequenceActiveEvidenceFixture, as: F
alias ExAgent.Continuation.Record
alias ExAgent.Coordination.Composition
[path, effects, phase] = System.argv()
record = Jason.decode!(File.read!(path))
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :active_evidence_vm)

{:ok, control} =
  Agent.start_link(fn -> if phase == "retry", do: {"output_resolution", :after} end)

store =
  Store.scoped(
    {SequenceApprovalFixture.Journal,
     %{table: :active_evidence_vm, control: control, owner: self()}},
    "sequence-approval"
  )

key = {"sequence-approval", :agent, "run"}
{:ok, physical} = Record.key(key)
{:ok, ^record} = Record.decode(Jason.encode!(record), key)
true = :ets.insert(:active_evidence_vm, {physical, Jason.encode!(record)})
config = %{SequenceApprovalFixture.config(store) | lease_ms: 3000}

result =
  Composition.resume(
    F.definition(effects, true),
    SequenceApprovalFixture.reference(record),
    [
      continuation: config,
      root_options: [estimate_cost: fn _, _ -> if phase == "retry", do: 11, else: 13 end]
    ] ++ SequenceApprovalFixture.options()
  )

case phase do
  "retry" ->
    {:error, %ExAgent.RunError{partial: partial}} = result
    "output_resolution" = partial.continuation_checkpoint["command"]["operation"]
    {:ok, _} = Continuation.retry_checkpoint(store, partial.continuation_checkpoint)
    recovered = F.recover(store)

    true =
      recovered["execution"]["progress"]["approvals"] ===
        record["execution"]["progress"]["approvals"]

    [b] =
      Enum.filter(
        Map.values(recovered["execution"]["progress"]["runtime"]["children"]),
        &(&1["status"] == "running")
      )

    0 = b["frame"]["output_retries_used"]
    File.write!(path, Jason.encode!(recovered))

  "finish" ->
    {:ok, result} = result
    :completed = result.status
    "C output" = result.output
    %{"count" => 7} = Enum.at(result.steps, 1).output
    6 = result.request_count
    3 = result.tool_calls
    58 = result.cost_cents
    {:ok, completed} = Store.load_record(store, :agent, "run")
    :ok = Record.validate(completed, key)

    true =
      completed["execution"]["progress"]["approvals"] ===
        record["execution"]["progress"]["approvals"]

    File.write!(path, Jason.encode!(completed))
end

next = Jason.decode!(File.read!(path))
old_frame = record["execution"]["progress"]["runtime"]
next_frame = next["execution"]["progress"]["runtime"]

for {id, child} <- old_frame["children"], child["status"] == "completed" do
  true = next_frame["children"][id] === child
end

for operation <- old_frame["scope"]["operations"] do
  true = operation in next_frame["scope"]["operations"]
end

IO.puts("ACTIVE_EVIDENCE_#{phase}")
