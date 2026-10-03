# Only JSON crosses this fresh VM boundary; all host callbacks raise.
alias ExAgent.Coordination.Composition
alias ExAgent.Continuation.Record
alias ExAgent.Store
[path] = System.argv()
%{"record" => record, "result" => expected} = Jason.decode!(File.read!(path))
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :sequence_api_vm)
store = Store.scoped({Store.ETS, :sequence_api_vm}, "sequence-api")
key = {"sequence-api", :agent, "run"}
{:ok, physical} = Record.key(key)
{:ok, ^record} = Record.decode(Jason.encode!(record), key)
true = :ets.insert(:sequence_api_vm, {physical, Jason.encode!(record)})

steps =
  for id <- ["A", "B", "C"] do
    %{
      id: id,
      agent: ExAgent.new(model: %ExAgent.Models.Test{script: [fn _, _ -> raise "no IO" end]}),
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"},
      model_codec: %{dump: fn _ -> raise "no dump" end, load: fn _, _ -> raise "no load" end}
    }
  end

{:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

config = %{
  store: store,
  id: "run",
  definition: %{"id" => "sequence", "version" => "1"},
  policy: %{"id" => "policy", "version" => "1"},
  durability: :ephemeral,
  expires_at: nil,
  lease_ms: 60_000,
  active_time_limit_ms: 60_000,
  on_writer: fn _ -> raise "no claim" end
}

reference = %{id: "run", record_id: record["record_id"], revision: record["revision"]}

{:ok, projected} =
  ExAgent.resume_composition_step(definition, reference,
    continuation: config,
    root_options: [estimate_cost: fn _, _ -> raise "no estimator" end]
  )

^expected = projected |> Jason.encode!() |> Jason.decode!()
{:ok, ^record} = Store.load_record(store, :agent, "run")
IO.puts("SEQUENCE_API_VM exact completed projection, no callbacks")
