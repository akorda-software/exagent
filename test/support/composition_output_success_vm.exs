# No captured model/closures cross this OS/BEAM boundary: only Record JSON.
alias ExAgent.{Continuation, Store, Tool}
alias ExAgent.Continuation.Record
alias ExAgent.Coordination.Composition
[file] = System.argv()
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :output_success_vm)
store = Store.scoped({Store.ETS, :output_success_vm}, "output-success")
key = {store.namespace, :agent, "sequence"}
bytes = File.read!(file)
{:ok, record} = Record.decode(bytes, key)
{:ok, physical} = Record.key(key)
true = :ets.insert(:output_success_vm, {physical, bytes})
Process.sleep(max(0, record["execution"]["lease_until"] - System.system_time(:millisecond) + 1))

{:ok, %{record: ready}} =
  Continuation.recover(store, "sequence",
    record_id: record["record_id"],
    revision: record["revision"],
    operation_id: "vm-recover",
    actor: "admin",
    authorize: fn actor, _, _ -> {:ok, actor} end
  )

defmodule OutputSuccessVMHooks do
  use ExAgent.Capability
  defstruct []
  def after_model_request(_, _), do: raise("after_model replay")
end

defmodule OutputSuccessVMSchema do
  def changeset(_, _), do: raise("changeset replay")
  def __schema__(_), do: raise("schema reflection replay")
end

model = %ExAgent.Models.Test{
  script: [fn _, _ -> raise "Model replay" end, fn _, _ -> raise "Model replay" end]
}

tool =
  Tool.new(
    name: "sibling",
    parameters_json_schema: %{type: "object"},
    call: fn _, _ -> raise "sibling replay" end
  )

step = %{
  id: "A",
  agent:
    ExAgent.new(
      model: model,
      output_type: OutputSuccessVMSchema,
      tools: [tool],
      capabilities: [struct(OutputSuccessVMHooks)],
      usage_limits: %ExAgent.UsageLimits{request_limit: 1}
    ),
  model_codec: %{
    dump: fn m -> {:ok, %{"index" => m.index}} end,
    load: fn m, data -> {:ok, %{m | index: data["index"]}} end
  },
  input: fn _, _ -> raise "mapping replay" end,
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

{:ok, %{output: result, usage: usage, run_step: 1}} =
  ExAgent.resume_composition_step(definition, reference,
    continuation: config,
    estimate_cost: fn _ -> raise "repricing leaf" end,
    root_options: [estimate_cost: fn _, _ -> raise "repricing root" end]
  )

true = result === %{"count" => 7}
false = is_struct(result)
3 = usage.input_tokens
2 = usage.output_tokens
{:ok, completed} = Store.load_record(store, :agent, "sequence")
"completed" = completed["execution"]["state"]
before = record["execution"]["progress"]["runtime"]
after_frame = completed["execution"]["progress"]["runtime"]
true = before["scope"] == after_frame["scope"]
true = before["output_resolutions"] == after_frame["output_resolutions"]
{:ok, _} = Record.encode(completed, key)

IO.puts(
  "NEW_VM_OUTPUT_COMPLETED portable-map schema=0 changeset=0 model=0 mapping=0 after_model=0 sibling=0"
)
