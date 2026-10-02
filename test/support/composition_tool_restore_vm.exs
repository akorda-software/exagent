alias ExAgent.CompositionToolRestoreFixture, as: F
alias ExAgent.{Message, Store}
alias ExAgent.Continuation.Record
[file, mode] = System.argv()
{:ok, _} = Application.ensure_all_started(:exagent)
{:ok, _} = Store.ETS.start_link(table: :tool_restore_vm)
bytes = File.read!(file)
record = Jason.decode!(bytes)
[ns, _, id] = record["key"]
key = {ns, :agent, id}
{:ok, ^record} = Record.decode(bytes, key)
{:ok, physical} = Record.key(key)
true = :ets.insert(:tool_restore_vm, {physical, bytes})
[child] = Map.values(record["execution"]["progress"]["runtime"]["children"])
n = child["frame"]["run_step"]
script = List.duplicate(F.text(), n) ++ [if(mode == "retry", do: F.output(9), else: F.text())]
typed = mode in ["success", "retry", "fatal"]

definition =
  F.definition(
    script: script,
    trap: true,
    new_index: n,
    output_type: if(typed, do: F.Output, else: :text),
    capabilities: [%F.Hooks{owner: self(), trap_tools: true}]
  )

config = F.config(:tool_restore_vm, definition, lease_ms: 60_000)
Process.put(:tool_restore_observer, self())
if mode == "success", do: Process.put(:tool_restore_schema_trap, true)
result = F.resume(record, config, definition)

partial =
  case {mode, result} do
    {"fatal", {:error, %ExAgent.RunError{reason: %{"code" => "tool_hook_failed"}, partial: p}}} ->
      p

    {_, {:ok, p}} ->
      p
  end

true = partial.tool_calls == 1
true = partial.usage_status == :partial
true = partial.cost_cents == nil

true =
  partial.usage.accounting["cost"]["subtotal_cents"] ==
    child["snapshot"]["usage"]["accounting"]["cost"]["subtotal_cents"]

true = partial.request_count == n + if(mode in ["batch", "retry"], do: 1, else: 0)

receive do
  {:tool, _} -> raise "historical effect"
  {:tool_hook, _, _} -> raise "historical tool hook"
  :mapping -> raise "historical mapping"
after
  0 -> :ok
end

{:ok, saved} = Store.load_record(config.store, :agent, config.id)

true =
  Enum.all?(
    record["execution"]["progress"]["runtime"]["scope"]["operations"],
    &(&1 in saved["execution"]["progress"]["runtime"]["scope"]["operations"])
  )

true = Message.Usage.validate(partial.usage) == :ok

IO.puts(
  "FRAME8_RESTORE_VM #{mode} calls=#{partial.tool_calls} requests=#{partial.request_count} historical=0"
)
