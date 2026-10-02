# Fresh BEAM receives only a JSON journal and a real append-only effect file.
alias ExAgent.Coordination.Composition
alias ExAgent.Continuation.Record
alias ExAgent.Store
[path, effects] = System.argv()
record = Jason.decode!(File.read!(path))
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :sequence_resume_vm)
store = Store.scoped({Store.ETS, :sequence_resume_vm}, "resume-sequence")
key = {"resume-sequence", :agent, "run"}
{:ok, physical} = Record.key(key)
{:ok, ^record} = Record.decode(Jason.encode!(record), key)
true = :ets.insert(:sequence_resume_vm, {physical, Jason.encode!(record)})

steps =
  for id <- ~w(A B C) do
    %{
      id: id,
      agent:
        ExAgent.new(
          model: %ExAgent.Models.Test{
            script: [
              fn _, _ ->
                if id == "A", do: raise("historical model executed")
                File.write!(effects, id <> "\n", [:append])
                id <> " output"
              end
            ]
          }
        ),
      definition: %{id: "leaf", version: "1"},
      policy: %{id: "policy", version: "1"},
      model_ref: %{id: "model", version: "1"},
      output_ref: %{id: "output", version: "1"},
      model_codec: %{
        dump: fn m ->
          if id == "A", do: raise("historical dump")
          {:ok, %{"index" => m.index}}
        end,
        load: fn m, data ->
          if id == "A", do: raise("historical load")
          {:ok, %{m | index: data["index"]}}
        end
      }
    }
  end

{:ok, definition} = Composition.new(id: "sequence", version: "1", steps: steps)

config = %{
  store: store,
  id: "run",
  policy: %{"id" => "policy", "version" => "1"},
  durability: :ephemeral,
  expires_at: nil,
  lease_ms: 60_000
}

ref = %{
  version: 1,
  id: "run",
  record_id: record["record_id"],
  revision: record["revision"],
  run_id: record["execution"]["run_id"]
}

{:ok, result} =
  Composition.resume(definition, ref,
    continuation: config,
    step_options: %{"A" => [on_event: fn _ -> raise "historical callback" end]}
  )

"C output" = result.output
3 = result.request_count
"A\nB\nC\n" = File.read!(effects)
{:ok, completed} = Store.load_record(store, :agent, "run")
:ok = Record.validate(completed, key)
IO.puts("SEQUENCE_RESUME_VM A once; suffix only; exact ledger")
