# Phoenix, LiveView and Oban continuation recipes

These application recipes complete the framework integration part of R7.5 using
public ExAgent APIs. Phoenix and Oban remain consumer dependencies. The generic
[job dispatch recipe](continuation-jobs.md) keeps the same implementation and API;
its module now lives in
[`job_dispatch.ex`](https://github.com/akorda-software/exagent/blob/main/examples/continuation_integrations/job_dispatch.ex), and
the runnable `examples/continuation_job.exs` requires that file relative to itself.

## Consumer wiring

Copy the three `.ex` recipes from `examples/continuation_integrations/` into the
consumer's compilation paths. They are examples, not modules compiled into the
ExAgent application. The verified profile fixes Phoenix **1.8.15**, LiveView
**1.2.12**, Phoenix.PubSub **2.3.0** and Oban **2.24.1**. The fixture additionally
fixes Ecto SQL **3.14.0** and Postgrex **0.22.4**; its resolved lock records every
other dependency. Bring a host Repo and migrations for durable C7 records and
Oban's tables. Neither recipe starts a database or owns application credentials.

```elixir
defmodule MyAppWeb.ContinuationLive do
  use ExAgent.Examples.ContinuationLive, host: MyApp.ContinuationHost
end

defmodule MyApp.Workers.Continuation do
  use ExAgent.Examples.ContinuationWorker, host: MyApp.ContinuationHost
end

# Existing host supervision/configuration:
{Phoenix.PubSub, name: MyApp.PubSub}
{Oban, repo: MyApp.Repo, queues: [continuations: 4]}
# Server opts include trusted namespace, Store and continuation configuration:
pubsub: {ExAgent.PubSub.Phoenix, MyApp.PubSub}
```

Define the host module explicitly at compile time. Do not resolve a module,
template, actor, permission policy or current options from client/job JSON.
`MyApp.ContinuationHost` implements these functions:

| Function | Host responsibility and return |
| --- | --- |
| `open(session)` | Authenticate the application session and authorize this conversation. Return `{:ok, %{actor: authenticated_context, reference: opaque_host_reference}}`, or an error. |
| `live_target(context, action)` | Reauthorize current access for `:view`, `:stream`, `:decision` or `:resume`. Resolve `server`, `namespace`, `agent_id`, `pubsub` and, for execution, trusted `prompt` and fresh keyword `options`. Return `{:ok, target}`, or an error. |
| `authorize(context, actor, decision, requested)` | Enforce current principal/tenant/business authority over the exact requested persisted record. Return `{:ok, bounded_actor_id}` or an error; passed to public `Server.decide/3`. |
| `present_history(history)` | Produce authorized, appropriately redacted text from `Server.history/1`. Only this presentation is rendered. |
| `present_approval(approval)` | Present the persisted tool name and arguments so the authenticated user can understand the requested effect. Apply the host's redaction policy; the bound payload hash remains unchanged. |
| `job_target(reference)` | Authenticate/authorize the queue service principal and resolve current `agent`, `prompt`, `continuation` and keyword `options` for the opaque reference. Return `{:ok, target}`, or an error. |

The synthetic fixture's session lookup is a test double for host authentication;
copying its `access` label is not a production authentication strategy. A real
host checks the signed session/current account, binds references to tenant and
owner, and constrains the queue service principal. Job references are selectors,
not authorization credentials.

## LiveView behavior and recovery

[`live_view.ex`](https://github.com/akorda-software/exagent/blob/main/examples/continuation_integrations/live_view.ex) subscribes
only after an authorized connected mount. Its private socket state holds the
actor and resolved host target; render assigns contain status, presented history,
opaque correlation/approval bindings and provisional text. The browser cannot
supply executable configuration or override run options.

`Server.stream/3` returns `{:ok, request_id}` for admission. The recipe keeps that
ID and handles `{:exagent_event, %ExAgent.Event{}}` from real Phoenix.PubSub.
Events must match envelope version, trusted namespace, agent ID, current emitter,
admitted/persisted request ID and increasing sequence. Duplicates and foreign
attempts are ignored. Sequence belongs to one emitter; it is not a durable cursor
or a cryptographic peer identity. Restrict access to the host PubSub bus, and apply
the application's text presentation/retention policy to rendered model content.

An approval click carries the exact record ID, revision, approval ID, payload
hash and per-view operation ID. These values must still match the persisted
pending approval and the currently presented binding; then the host authorizer
and the C7 compare-and-swap enforce the decision. Extra keys and stale or changed
bindings fail before model/tool IO. The operation ID remains stable while that
approval revision is displayed. A rejected/lost reply requires a refresh; this
minimal UI does not promise replay of a decision acknowledgement after reconnect.

Approve persists a decision and performs no effects. Resume is a separate host
authorized event, runs synchronous `Server.resume/2` through LiveView
`start_async/3`, and refreshes when it finishes. Closing the view ends the caller
task; the Server still owns admitted work. Host cancellation uses public
`Server.abort/1` when explicitly desired.

Every mount and explicit refresh queries `Server.history/1`, `Server.health/1`
and `Server.continuation/1`. Reconnection therefore recovers persisted history,
current status and approvals even when PubSub messages were lost. A recreated
Server has a new emitter. The host may resolve that new owner, but the namespace,
agent identity and PubSub instance must remain bound to the existing view.
Neither mounting nor refreshing resumes pending work. Checkpoint errors and
uncertainty require explicit host recovery; the recipe never automatically
re-executes an attempt from those conditions.

## Oban behavior

[`oban_worker.ex`](https://github.com/akorda-software/exagent/blob/main/examples/continuation_integrations/oban_worker.ex)
accepts exactly `%{"reference" => binary_reference}`. The host lookup owns all
authority/configuration. It calls the shared `ContinuationJob.dispatch/4`:
new work runs once, pending work waits for a separate approval, ready/approved
work resumes its cursor, and terminal duplicates return without replay.

The worker returns `:ok` for pending/terminal/success receipts. A host resolves
and inserts a new delivery after a committed approval; `:ok` while pending does
not schedule polling or grant permission. Errors, an in-progress attempt or
uncertainty return `{:cancel, reason}` and stop automatic retries. The worker
defaults to `max_attempts: 1`. An operator resolves the host condition before
explicitly inserting/retrying a job. Oban job uniqueness is optional; C7, not
uniqueness, guards the persisted execution cursor. A Store/Oban commit does not
make external tool effects transactional or exactly once.

## Opt-in verification

The harness lives under `test/support/framework_integrations/`, with an isolated
consumer fixture under `test/fixtures/framework_integrations/`. Its `cases.exs`
filename deliberately avoids ordinary ExAgent ExUnit discovery. No profile or
`--list` lists selectors without starting Mix, installing, networking or opening
a database. With a profile it creates physical copies from an explicit stable
core freeze and these new recipes, uses private build/dependency/tooling paths,
and fetches official Hex packages and their maintained native build artifacts
only during preparation. LiveViewTest uses pinned `lazy_html` **0.1.13**. It reads no `.env`,
global auth configuration or provider credentials.

```bash
MIX_ARCHIVES=/absolute/private/tooling/archives \
MIX_REBAR3=/absolute/private/tooling/rebar3 \
python3 -I test/support/framework_integrations/run.py \
  --profile all \
  --base-project /absolute/private/exagent-freeze \
  --pg-bin /absolute/postgresql/bin \
  --artifacts-parent /tmp
```

Select `liveview`, `oban-postgres` or `all`. The harness requires existing isolated
Hex/Rebar tooling and a native PostgreSQL installation; it does not bootstrap
global tools or use a default service. PostgreSQL **17.4** was supplied for this
qualification. Each run creates its own mode-0700 cluster/socket, disables TCP,
uses the explicit `framework_integrations` database and stops its own server in a
finite cleanup block. SQL statements are limited to five seconds and the Repo
pool to four connections. Preparation/cases/cleanup have separate deadlines.

The receipt records actual versions, source/lock hashes, command exits, counted
requests/effects, SQL job states/attempts, correlation and cleanup. A compile
failure leaves `interop_executed: false`; absent observations or version mismatch
fail the selected profile. There are no backend fallbacks or success skips.

LiveView qualification uses a routed HTTP render and a real **LiveViewTest
channel connection**, with handler/events, `start_async` and reconnect. It is
stronger than invoking callbacks directly; it does not test a JavaScript browser
or a TCP/WebSocket listener. The endpoint's HTTP server stays disabled.

The SQL Oban profile uses stock **Oban.Engines.Basic**, real inserts, public
`drain_queue/2`, `retry_job/2` and supervisor restart. Delivery is deliberately
bounded and driven synchronously through that public execution mechanism. It
qualifies durable rows and controlled re-delivery, not distributed producer
leadership, production queue throughput or cloud failover. C7 is backed by the
real SQL Store in these cases. Framework integration evidence does not replace
the separate core SQL recovery/backend/release acceptance gates.

The selected SQL profile also launches two separate VMs: the first terminates
with expected exit **73** immediately after a confirmed synthetic SQL tool
effect, leaving an unresolved C7 intent and an executing Oban job. After the
one-second lease expires, a fresh VM explicitly calls `Continuation.recover/3`.
The record becomes uncertain. A trusted operator cancels/retries the abandoned
queue delivery through public Oban APIs; the worker then cancels that delivery,
preserving the uncertain record and the original one-request/one-effect counts.

The common candidate019 qualification (2026-10-01) passes six real
LiveViewTest/Oban cases and those two VM phases: expected crash73, recovery0,
one request/one effect preserved and all owned processes/cluster closed.
All152 distributed files match the common TAR. The [roadmap](roadmap.md) records
the receipt identity; this qualifies the controlled delivery/channel profile
described here, with its existing browser, throughput and failover limits.
This demonstrates the recipe's recovery boundary without silently replaying.

The finite acceptance batch is six ExUnit cases (four routed LiveView cases and
two SQL Oban cases), the unchanged generic demo, and those two crash/recovery
phases. A profile selects its own cases/phases; exclusions are explicitly reported
by ExUnit. An `all` receipt requires every scenario observation and no selected
case failure. The receipt's counted effects describe the synthetic test effect,
not a promise of exactly-once execution for arbitrary external systems.

API references: [LiveView lifecycle and async](https://phoenix-live-view.hexdocs.pm/1.2.12/Phoenix.LiveView.html),
[LiveViewTest](https://phoenix-live-view.hexdocs.pm/1.2.12/Phoenix.LiveViewTest.html),
[LiveView routing/auth boundaries](https://phoenix-live-view.hexdocs.pm/1.2.12/Phoenix.LiveView.Router.html),
[Phoenix.PubSub](https://phoenix-pubsub.hexdocs.pm/2.3.0/Phoenix.PubSub.html),
[Oban Worker](https://oban.hexdocs.pm/2.24.1/Oban.Worker.html),
[Oban public delivery APIs](https://oban.hexdocs.pm/2.24.1/Oban.html).
