alias ExAgent.{Store, Continuation, SequenceApprovalFixture}
alias ExAgent.Continuation.Record
alias ExAgent.Coordination.Composition
alias ExAgent.DelegationRuntimeFixture, as: F
[path, effects, mode] = System.argv()
record = Jason.decode!(File.read!(path))
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :delegation_runtime_vm)
F.import(:delegation_runtime_vm, record)

store =
  Store.scoped(
    {F.Journal,
     %{
       table: :delegation_runtime_vm,
       path: path,
       crash:
         case mode do
           "crash" -> "before"
           "wrapping" -> "wrapping"
           _ -> nil
         end
     }},
    "delegation-runtime"
  )

record =
  if mode in ["recover", "uncertain"] do
    # One bounded lease-expiry wait, not retries, polling or lease renewal.
    receive do
    after
      max(record["execution"]["lease_until"] - System.system_time(:millisecond) + 1, 0) -> :ok
    end

    {:ok, %{record: next}} =
      Continuation.recover(store, "run",
        record_id: record["record_id"],
        revision: record["revision"],
        operation_id: "explicit-recover",
        actor: "host",
        authorize: fn actor, _, _ -> {:ok, actor} end
      )

    true = next["execution"]["progress"]["runtime"] === record["execution"]["progress"]["runtime"]
    expected = if mode == "uncertain", do: "uncertain", else: "ready"
    ^expected = next["execution"]["state"]
    next
  else
    record
  end

{definition, catalog} = F.host(effects, true)

if mode == "uncertain" do
  steps =
    for step <- definition.steps do
      %{
        step
        | model_codec: %{
            dump: fn _ -> raise("unexpected codec") end,
            load: fn _, _ -> raise("uncertain codec replay") end
          }
      }
    end

  catalog =
    for entry <- catalog, do: %{entry | load: fn _, _ -> raise("uncertain loader replay") end}

  {:error, %ExAgent.RunError{reason: :unsupported_composition_boundary}} =
    Composition.resume(%{definition | steps: steps}, SequenceApprovalFixture.reference(record),
      continuation: F.config(store),
      delegate_definitions: catalog
    )

  {:ok, ^record} = Store.load_record(store, :agent, "run")
  true = Record.unresolved?(record["execution"])
  IO.puts("DELEGATION_VM uncertain, zero callback replay")
  :erlang.halt(0)
end

{:ok, result} =
  Composition.resume(definition, SequenceApprovalFixture.reference(record),
    continuation: F.config(store),
    delegate_definitions: catalog
  )

:completed = result.status
"C final" = result.output
7 = result.request_count
6 = result.tool_calls
{:ok, completed} = Store.load_record(store, :agent, "run")
:ok = Record.validate(completed, {"delegation-runtime", :agent, "run"})

true =
  completed["execution"]["progress"]["approvals"] === record["execution"]["progress"]["approvals"]

IO.puts("DELEGATION_VM completed, confirmed prefixes inert")
