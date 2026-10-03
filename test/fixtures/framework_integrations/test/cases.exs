defmodule FrameworkIntegrations.Migration do
  use Ecto.Migration
  def up, do: Oban.Migration.up()
  def down, do: Oban.Migration.down()
end

defmodule FrameworkIntegrations.Cases do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias ExAgent.{Continuation, Event, Server}
  alias FrameworkIntegrations.{Host, Repo, Worker}
  @endpoint FrameworkIntegrations.Endpoint
  @oban FrameworkIntegrations.Oban

  setup_all do
    assert System.fetch_env!("EXAGENT_FRAMEWORK_EXECUTE") == "1"
    {:ok, _} = Application.ensure_all_started(:phoenix)

    repo =
      start_supervised!(
        {Repo,
         socket_dir: System.fetch_env!("EXAGENT_FRAMEWORK_SOCKET"),
         username: System.fetch_env!("EXAGENT_FRAMEWORK_USER"),
         database: "framework_integrations",
         pool_size: 4,
         port: 5432,
         log: false,
         after_connect: {Postgrex, :query!, ["SET statement_timeout=5000", []]}}
      )

    assert is_pid(repo)
    :ok = ExAgent.Store.Postgres.migrate(Repo, "fixture_records")

    Repo.query!(
      "CREATE TABLE fixture_observations (reference text NOT NULL, kind text NOT NULL)",
      []
    )

    :ok = Ecto.Migrator.up(Repo, 1, FrameworkIntegrations.Migration, log: false)
    start_supervised!({Phoenix.PubSub, name: FrameworkIntegrations.PubSub})
    start_supervised!(%{id: Host, start: {Agent, :start_link, [fn -> %{} end, [name: Host]]}})
    start_supervised!(@endpoint)

    observe(
      "versions",
      Map.new(
        [:exagent, :phoenix, :phoenix_live_view, :phoenix_pubsub, :oban, :ecto_sql, :postgrex],
        fn app ->
          {Atom.to_string(app), app |> Application.spec(:vsn) |> to_string()}
        end
      )
    )

    :ok
  end

  @tag :liveview
  test "routed connected LiveView admits a stream, authorizes an exact decision, and resumes asynchronously" do
    target = live_target("live-authorized", "alpha")

    :ok =
      Phoenix.PubSub.subscribe(
        target.pubsub,
        Event.agent_topic(target.agent_id, target.namespace)
      )

    {:ok, view, html} = connect_view(target.reference)
    refute html =~ "synthetic-private"
    assert element(view, "#run") |> render_click() =~ "admitted"
    pending = wait_status(view, "pending")
    assert pending =~ "approve-"
    assert pending =~ "Approve: effect {}"
    assert Host.counts(target.reference) == %{"request" => 1, "effect" => 0}

    assert_received {:exagent_event,
                     %Event{
                       namespace: "alpha",
                       agent_id: "live-authorized",
                       request_id: request_id
                     }}

    assert is_binary(request_id)
    assert element(view, "button[phx-click=approve]") |> render_click() =~ "approved"
    assert {:ok, %{status: :approved}} = Server.continuation(target.server)
    assert Host.counts(target.reference)["effect"] == 0
    element(view, "#resume") |> render_click()
    completed = render_async(view, 5_000)
    assert completed =~ "synthetic completed output"
    assert completed =~ "resume completed"
    assert completed =~ ~s(id="continuation-status">completed)
    refute completed =~ "synthetic-private"
    assert {:ok, %{status: :completed, record: record}} = Server.continuation(target.server)
    assert Host.counts(target.reference) == %{"request" => 2, "effect" => 1}
    assert text_count(completed, "deltas") > 0
    assert element(view, "#resume") |> render_click() =~ "resume rejected"
    assert Host.counts(target.reference) == %{"request" => 2, "effect" => 1}

    observe("live-authorized", %{
      counts: Host.counts(target.reference),
      request_id: request_id,
      record_id: record["record_id"],
      revision: record["revision"],
      deltas: text_count(completed, "deltas"),
      live_view_connection: "routed LiveViewTest channel",
      resume: "start_async + public Server.resume"
    })
  end

  @tag :liveview
  test "unauthenticated, viewer, cross-namespace and stale client decisions have zero tool effects" do
    a = live_target("live-boundary", "alpha")
    b = live_target("live-boundary", "beta")
    {:ok, owner, _} = connect_view(a.reference)
    element(owner, "#run") |> render_click()
    original = wait_status(owner, "pending")
    params = decision(original)
    {:ok, anonymous, html} = live(build_conn(), "/continuation")
    assert html =~ "unauthorized"
    assert render_click(anonymous, "approve", params) =~ "unauthorized"
    assert render_click(anonymous, "run", %{"options" => %{"approve" => true}}) =~ "run rejected"
    {:ok, viewer, _} = connect_view(a.reference, "viewer")
    assert render_click(viewer, "approve", params) =~ "decision rejected"
    {:ok, other_namespace, _} = connect_view(b.reference)
    assert render_click(other_namespace, "approve", params) =~ "decision rejected"
    assert render_click(owner, "approve", Map.put(params, "revision", "1")) =~ "decision rejected"

    assert render_click(owner, "approve", Map.put(params, "payload_hash", "changed")) =~
             "decision rejected"

    assert render_click(owner, "approve", Map.put(params, "namespace", "beta")) =~
             "decision rejected"

    assert {:ok, %{status: :pending}} = Server.continuation(a.server)
    assert Host.counts(a.reference) == %{"request" => 1, "effect" => 0}
    assert Host.counts(b.reference) == %{"request" => 0, "effect" => 0}

    observe("live-authority", %{
      alpha: Host.counts(a.reference),
      beta: Host.counts(b.reference),
      rejected: [
        "anonymous",
        "viewer",
        "cross-namespace",
        "stale-revision",
        "changed-payload",
        "extra-namespace"
      ]
    })
  end

  @tag :liveview
  test "reconnect restores history health and persisted approval despite missed PubSub and a fresh emitter" do
    target = live_target("live-reconnect", "alpha")
    {:ok, view, _} = connect_view(target.reference)
    element(view, "#run") |> render_click()
    wait_status(view, "pending")
    old_emitter = Server.health(target.server).emitter_id
    history = Server.history(target.server)
    GenServer.stop(view.pid, :normal)
    stop_supervised!({:exagent_server, {target.namespace, target.agent_id}})
    restarted = start_server(target)
    Host.server(target.reference, restarted)
    assert Server.history(restarted) == history
    assert Server.health(restarted).emitter_id != old_emitter
    assert Host.counts(target.reference) == %{"request" => 1, "effect" => 0}
    {:ok, reconnected, html} = connect_view(target.reference)
    assert html =~ ~s(id="continuation-status">pending)
    assert text_count(html, "history-count") == length(history)
    assert decision(html)["record_id"] == decision(render(reconnected))["record_id"]
    params = decision(html)
    health = Server.health(restarted)
    {:ok, %{record: record}} = Server.continuation(restarted)

    event =
      Event.new(
        type: :text_delta,
        seq: 1,
        emitter_id: health.emitter_id,
        namespace: "alpha",
        agent_id: target.agent_id,
        request_id: record["execution"]["request_id"],
        payload: %{text: "synthetic-delta"}
      )

    for changed <- [
          %{event | namespace: "beta"},
          %{event | agent_id: "other"},
          %{event | emitter_id: old_emitter},
          %{event | request_id: "other"},
          %{event | version: 2}
        ] do
      Phoenix.PubSub.broadcast(
        target.pubsub,
        Event.agent_topic(target.agent_id, "alpha"),
        {:exagent_event, changed}
      )
    end

    refute render(reconnected) =~ "synthetic-delta"
    topic = Event.agent_topic(target.agent_id, "alpha")
    Phoenix.PubSub.broadcast(target.pubsub, topic, {:exagent_event, event})
    assert render(reconnected) =~ "synthetic-delta"
    Phoenix.PubSub.broadcast(target.pubsub, topic, {:exagent_event, event})
    assert text_count(render(reconnected), "deltas") == 1
    assert render_click(reconnected, "approve", params) =~ "approved"
    element(reconnected, "#resume") |> render_click()
    assert render_async(reconnected, 5_000) =~ "synthetic completed output"
    GenServer.stop(reconnected.pid, :normal)
    {:ok, completed, html} = connect_view(target.reference)
    assert html =~ ~s(id="continuation-status">completed)
    assert html =~ "synthetic completed output"
    assert text_count(html, "history-count") == length(Server.history(restarted))
    assert Host.counts(target.reference) == %{"request" => 2, "effect" => 1}
    refute render(completed) =~ "synthetic-private"

    observe("live-reconnect", %{
      old_emitter: old_emitter,
      new_emitter: health.emitter_id,
      counts: Host.counts(target.reference),
      missed_events_recovered_by: ["history", "health", "continuation"],
      filtered: ["namespace", "agent", "emitter", "request", "version", "duplicate-seq"]
    })
  end

  @tag :liveview
  test "revoked host identity cannot resume an approved persisted run" do
    target = live_target("live-revoked", "alpha")
    {:ok, view, _} = connect_view(target.reference)
    element(view, "#run") |> render_click()
    wait_status(view, "pending")
    element(view, "button[phx-click=approve]") |> render_click()
    Host.disable(target.reference)
    assert element(view, "#resume") |> render_click() =~ "unauthorized"
    assert {:ok, %{status: :approved}} = Server.continuation(target.server)
    assert Host.counts(target.reference) == %{"request" => 1, "effect" => 0}

    observe("live-revoked", %{
      counts: Host.counts(target.reference),
      state: "approved; host resolution denied"
    })
  end

  @tag :oban
  test "SQL jobs survive Oban supervisor restart and repeated pending/completed deliveries do not replay" do
    target = Host.put("job-delivery", "alpha")
    oban = start_oban()
    {:ok, first} = Oban.insert(@oban, Worker.new(%{"reference" => target.reference}))
    assert Repo.get!(Oban.Job, first.id).state == "available"
    stop_supervised!(:fixture_oban)
    refute Process.alive?(oban)
    start_oban()
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :continuations)
    assert Repo.get!(Oban.Job, first.id).state == "completed"

    assert {:ok, %{status: :pending}} =
             Continuation.get(target.continuation.store, target.agent_id)

    assert Host.counts(target.reference) == %{"request" => 1, "effect" => 0}
    :ok = Oban.retry_job(@oban, first.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :continuations)
    assert Repo.get!(Oban.Job, first.id).attempt == 2
    assert Host.counts(target.reference) == %{"request" => 1, "effect" => 0}
    {:ok, %{record: record}} = Continuation.get(target.continuation.store, target.agent_id)
    [{approval_id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])
    {:ok, context} = Host.open(%{"session_ref" => target.reference, "access" => "owner"})

    assert {:ok, _} =
             Continuation.decide(target.continuation.store, target.agent_id, :approve,
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "job-approval",
               approval_id: approval_id,
               payload_hash: approval["payload_hash"],
               actor: context.actor,
               authorize: fn actor, action, requested ->
                 Host.authorize(context, actor, action, requested)
               end
             )

    :ok = Oban.retry_job(@oban, first.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :continuations)

    assert {:ok, %{status: :completed, record: completed}} =
             Continuation.get(target.continuation.store, target.agent_id)

    assert Host.counts(target.reference) == %{"request" => 2, "effect" => 1}
    :ok = Oban.retry_job(@oban, first.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :continuations)
    {:ok, duplicate} = Oban.insert(@oban, Worker.new(%{"reference" => target.reference}))
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :continuations)
    assert Repo.get!(Oban.Job, first.id).attempt == 4
    assert Repo.get!(Oban.Job, duplicate.id).attempt == 1
    assert Host.counts(target.reference) == %{"request" => 2, "effect" => 1}
    {:ok, %{record: unchanged}} = Continuation.get(target.continuation.store, target.agent_id)
    assert unchanged == completed

    %{rows: rows} =
      Repo.query!(
        "SELECT id,state,attempt,args FROM oban_jobs WHERE args->>'reference'=$1 ORDER BY id",
        [target.reference]
      )

    observe("oban-delivery", %{
      counts: Host.counts(target.reference),
      jobs: rows,
      deliveries: 5,
      engine: "Oban.Engines.Basic; controlled public drain_queue",
      supervisor_restart: true,
      durable_record_unchanged_on_completed_redelivery: true
    })
  end

  @tag :oban
  test "Oban cancels invalid, unauthorized and extra authority fields without model/tool IO" do
    target = Host.put("job-authority", "alpha")
    start_oban()

    for args <- [
          %{"reference" => "missing"},
          %{"reference" => target.reference, "actor" => "owner"},
          %{"reference" => target.reference, "options" => %{"approve" => true}},
          %{"reference" => 1}
        ] do
      {:ok, job} = Oban.insert(@oban, Worker.new(args))
      assert %{failure: 0, cancelled: 1} = Oban.drain_queue(@oban, queue: :continuations)
      assert Repo.get!(Oban.Job, job.id).state == "cancelled"
      assert Repo.get!(Oban.Job, job.id).attempt == 1
    end

    Host.disable(target.reference)
    {:ok, job} = Oban.insert(@oban, Worker.new(%{"reference" => target.reference}))
    assert %{cancelled: 1} = Oban.drain_queue(@oban, queue: :continuations)
    assert Repo.get!(Oban.Job, job.id).state == "cancelled"
    assert Host.counts(target.reference) == %{"request" => 0, "effect" => 0}

    observe("oban-authority", %{
      counts: Host.counts(target.reference),
      cancelled_sql_jobs: 5,
      default_max_attempts: 1,
      no_input_atomization: true
    })
  end

  defp live_target(id, namespace) do
    target = Host.put(id, namespace)
    server = start_server(target)
    Host.server(target.reference, server)
    %{target | server: server}
  end

  defp start_server(target) do
    child =
      Supervisor.child_spec(
        {Server,
         agent: target.agent,
         agent_id: target.agent_id,
         namespace: target.namespace,
         store: {ExAgent.Store.Postgres, {Repo, table: "fixture_records"}},
         continuation: target.continuation,
         pubsub: {ExAgent.PubSub.Phoenix, target.pubsub}},
        id: {:exagent_server, {target.namespace, target.agent_id}}
      )

    start_supervised!(child)
  end

  defp connect_view(reference, access \\ "owner") do
    build_conn()
    |> Plug.Test.init_test_session(%{session_ref: reference, access: access})
    |> live("/continuation")
  end

  defp decision(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("button[phx-click=approve]")
    |> List.first()
    |> elem(1)
    |> Enum.flat_map(fn
      {"phx-value-" <> key, value} -> [{key, value}]
      _ -> []
    end)
    |> Map.new()
  end

  defp text_count(html, id) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#" <> id)
    |> Floki.text()
    |> String.to_integer()
  end

  defp wait_status(view, expected, tries \\ 250)
  defp wait_status(_view, _expected, 0), do: flunk("persisted status did not settle")

  defp wait_status(view, expected, tries) do
    html = render(view)

    if html =~ ~s(id="continuation-status">#{expected}) do
      html
    else
      Process.sleep(10)
      wait_status(view, expected, tries - 1)
    end
  end

  defp oban_options do
    [
      name: @oban,
      repo: Repo,
      engine: Oban.Engines.Basic,
      queues: false,
      plugins: false,
      peer: false,
      notifier: Oban.Notifiers.PG,
      stager: [interval: :infinity],
      testing: :disabled
    ]
  end

  defp start_oban,
    do: start_supervised!(Supervisor.child_spec({Oban, oban_options()}, id: :fixture_oban))

  defp observe(label, data) do
    path = Path.join(System.fetch_env!("EXAGENT_FRAMEWORK_ARTIFACTS"), label <> ".json")
    File.write!(path, Jason.encode!(data, pretty: true))
  end
end
