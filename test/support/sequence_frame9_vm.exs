# Fresh OS/BEAM; the previous attempt contributes only JSON bytes.
alias ExAgent.Store
alias ExAgent.Continuation.Record
alias ExAgent.Coordination.Composition
[file] = System.argv()
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :sequence9_vm)
store = Store.scoped({Store.ETS, :sequence9_vm}, "sequence9")
key = {store.namespace, :agent, "sequence"}
{:ok, physical} = Record.key(key)

steps =
  for id <- ["A", "B", "C"] do
    %{
      id: id,
      agent:
        ExAgent.new(model: %ExAgent.Models.Test{script: [fn _, _ -> raise "no Model IO" end]}),
      model_codec: %{dump: fn _ -> raise "no dump" end, load: fn _, _ -> raise "no load" end},
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"}
    }
  end

{:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

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

for record <- Jason.decode!(File.read!(file)) do
  bytes = Jason.encode!(record)
  {:ok, ^record} = Record.decode(bytes, key)
  true = :ets.insert(:sequence9_vm, {physical, bytes})
  reference = %{id: "sequence", record_id: record["record_id"], revision: record["revision"]}
  result = ExAgent.resume_composition_step(definition, reference, continuation: config)

  case record["execution"]["state"] do
    "completed" -> {:ok, %{status: :completed, output: "C output"}} = result
    "claimed" -> {:error, :unsupported_composition_boundary} = result
  end

  {:ok, ^record} = Store.load_record(store, :agent, "sequence")
end

IO.puts("FRAME9_VM completed data_only intermediate rejected")
