# Executed in a new OS/BEAM process. Its only previous-run input is JSON bytes.
alias ExAgent.{Continuation, Store}
alias ExAgent.Continuation.Record
alias ExAgent.Coordination.Composition
[file] = System.argv()
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :restore_vm)
store = Store.scoped({Store.ETS, :restore_vm}, "restore-input")
key = {store.namespace, :agent, "sequence"}
bytes = File.read!(file)
{:ok, record} = Record.decode(bytes, key)
{:ok, physical} = Record.key(key)
true = :ets.insert(:restore_vm, {physical, bytes})

{:ok, %{record: ready}} =
  Continuation.recover(store, "sequence",
    record_id: record["record_id"],
    revision: record["revision"],
    operation_id: "vm-recover",
    actor: "admin",
    authorize: fn actor, _, _ -> {:ok, actor} end
  )

model = %ExAgent.Models.Test{
  script: [
    fn _, _ ->
      Process.put(:io_count, Process.get(:io_count, 0) + 1)
      "restored in new VM"
    end
  ]
}

step = %{
  id: "A",
  agent: ExAgent.new(model: model),
  model_codec: %{
    dump: fn m -> {:ok, %{"index" => m.index}} end,
    load: fn m, data -> {:ok, %{m | index: data["index"]}} end
  },
  input: fn _, _ -> raise "confirmed mapping must never execute" end,
  input_version: "1",
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

reference = %{id: "sequence", record_id: ready["record_id"], revision: ready["revision"]}

{:ok, %{output: "restored in new VM"}} =
  ExAgent.resume_composition_step(definition, reference, continuation: config)

1 = Process.get(:io_count)
{:ok, completed} = Store.load_record(store, :agent, "sequence")
"completed" = completed["execution"]["state"]
{:ok, _} = Record.encode(completed, key)
IO.puts("NEW_VM_INPUT0_COMPLETED io=1")
