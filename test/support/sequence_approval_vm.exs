alias ExAgent.{Store, SequenceApprovalFixture}
alias ExAgent.Continuation.Record
alias ExAgent.Coordination.Composition
[path, effects] = System.argv()
record = Jason.decode!(File.read!(path))
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :sequence_approval_vm)
store = Store.scoped({Store.ETS, :sequence_approval_vm}, "sequence-approval")
key = {"sequence-approval", :agent, "run"}
{:ok, physical} = Record.key(key)
{:ok, ^record} = Record.decode(Jason.encode!(record), key)
true = :ets.insert(:sequence_approval_vm, {physical, Jason.encode!(record)})

{:ok, result} =
  Composition.resume(
    SequenceApprovalFixture.definition(effects, true),
    SequenceApprovalFixture.reference(record),
    [continuation: SequenceApprovalFixture.config(store)] ++ SequenceApprovalFixture.options()
  )

:completed = result.status
"C output" = result.output
5 = result.request_count
3 = result.tool_calls
["A", b1, b2, "C"] = String.split(File.read!(effects), "\n", trim: true)
["B1", "B2"] = Enum.sort([b1, b2])
{:ok, completed} = Store.load_record(store, :agent, "run")
:ok = Record.validate(completed, key)

true =
  completed["execution"]["progress"]["approvals"] === record["execution"]["progress"]["approvals"]

IO.puts("SEQUENCE_APPROVAL_VM")
