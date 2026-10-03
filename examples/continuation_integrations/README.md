# Compile these recipes in the host application

`job_dispatch.ex` is the shared generic dispatch helper. `live_view.ex` and
`oban_worker.ex` compile only when the consumer brings Phoenix/LiveView or Oban.
They do not add framework dependencies to ExAgent. Configure an explicit host
module for identity, authorized target resolution and fresh execution options.

See [framework integrations](../../docs/development/framework-integrations.md)
for callback contracts, supervision, behavior, opt-in qualification and limits.
The deterministic generic demo remains runnable at
`EXAGENT_OFFLINE=1 mix run examples/continuation_job.exs`.
