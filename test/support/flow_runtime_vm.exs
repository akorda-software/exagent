alias ExAgent.{Store, Continuation, SequenceApprovalFixture}
alias ExAgent.Continuation.Record
alias ExAgent.Coordination.Flow
alias ExAgent.DelegationRuntimeFixture, as: JournalFixture
alias ExAgent.FlowRuntimeFixture, as: F
[path, effects, mode] = System.argv()
record = Jason.decode!(File.read!(path))
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :flow_runtime_vm)
JournalFixture.import(:flow_runtime_vm, record)

store =
  Store.scoped(
    {JournalFixture.Journal,
     %{table: :flow_runtime_vm, path: path, crash: if(mode == "crash", do: "before")}},
    "delegation-runtime"
  )

record =
  if mode == "recover" do
    receive do
    after
      max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0) -> :ok
    end

    {:ok, %{record: next}} =
      Continuation.recover(store, "run",
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "flow-explicit-recover",
        actor: "host",
        authorize: fn actor, _, _ -> {:ok, actor} end
      )

    "ready" = next["execution"]["state"]
    true = next["execution"]["progress"]["runtime"] === record["execution"]["progress"]["runtime"]
    next
  else
    record
  end

{definition, catalog} = F.host(effects, true)

{:ok, result} =
  Flow.resume(definition, SequenceApprovalFixture.reference(record),
    continuation: JournalFixture.config(store),
    delegate_definitions: catalog
  )

:completed = result.status
6 = result.request_count
6 = result.tool_calls
["failed", "completed", "completed"] = Enum.map(result.output, & &1["status"])
{:ok, completed} = Store.load_record(store, :agent, "run")
:ok = Record.validate(completed, {"delegation-runtime", :agent, "run"})

true =
  completed["execution"]["progress"]["approvals"] === record["execution"]["progress"]["approvals"]

IO.puts("FLOW_VM completed, failed and completed branches inert")
