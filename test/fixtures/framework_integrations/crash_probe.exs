defmodule FrameworkIntegrations.CrashProbe do
  import ExUnit.Assertions
  alias FrameworkIntegrations.{Host, Repo, Worker}
  alias ExAgent.Continuation
  @oban FrameworkIntegrations.CrashOban

  def run(phase) do
    assert System.fetch_env!("EXAGENT_FRAMEWORK_EXECUTE") == "1"

    {:ok, repo} =
      Repo.start_link(
        socket_dir: System.fetch_env!("EXAGENT_FRAMEWORK_SOCKET"),
        username: System.fetch_env!("EXAGENT_FRAMEWORK_USER"),
        database: "framework_integrations",
        pool_size: 4,
        port: 5432,
        log: false,
        after_connect: {Postgrex, :query!, ["SET statement_timeout=5000", []]}
      )

    {:ok, host} = Agent.start_link(fn -> %{} end, name: Host)

    {:ok, oban} =
      Oban.start_link(
        name: @oban,
        repo: Repo,
        engine: Oban.Engines.Basic,
        queues: false,
        plugins: false,
        peer: false,
        notifier: Oban.Notifiers.PG,
        stager: [interval: :infinity],
        testing: :disabled
      )

    try do
      execute(phase)
    after
      Supervisor.stop(oban)
      Agent.stop(host)
      Supervisor.stop(repo)
    end
  end

  defp execute("crash") do
    target = Host.put_crashing("job-uncertain", "alpha")
    {:ok, job} = Oban.insert(@oban, Worker.new(%{"reference" => target.reference}))

    File.write!(
      Path.join(System.fetch_env!("EXAGENT_FRAMEWORK_ARTIFACTS"), "crash-job.json"),
      Jason.encode!(%{id: job.id, reference: target.reference, expected_vm_exit: 73})
    )

    Oban.drain_queue(@oban, queue: :continuations)
    flunk("the confirmed synthetic SQL tool effect must terminate this VM")
  end

  defp execute("recover") do
    target = Host.put("job-uncertain", "alpha")
    assert Host.counts(target.reference) == %{"request" => 1, "effect" => 1}
    {:ok, %{record: before}} = Continuation.get(target.continuation.store, target.agent_id)

    assert Enum.any?(before["execution"]["effects"], fn {_, effect} ->
             is_nil(effect["outcome"])
           end)

    assert {:ok, _} =
             Continuation.recover(target.continuation.store, target.agent_id,
               record_id: before["record_id"],
               revision: before["revision"],
               operation_id: "host-recover-crashed-delivery",
               actor: :synthetic_operator,
               authorize: fn :synthetic_operator, :recover, _ ->
                 {:ok, "alpha/synthetic-operator"}
               end
             )

    assert {:ok, %{status: :uncertain, record: uncertain}} =
             Continuation.get(target.continuation.store, target.agent_id)

    %{rows: [[job_id]]} =
      Repo.query!("SELECT id FROM oban_jobs WHERE args->>'reference'=$1", [target.reference])

    job = Repo.get!(Oban.Job, job_id)
    assert job.state == "executing"
    # A trusted operator explicitly changes the abandoned queue delivery. C7
    # remains uncertain; the next actual delivery cancels instead of replaying.
    :ok = Oban.cancel_job(@oban, job.id)
    :ok = Oban.retry_job(@oban, job.id)
    assert %{cancelled: 1, failure: 0} = Oban.drain_queue(@oban, queue: :continuations)
    assert Repo.get!(Oban.Job, job.id).state == "cancelled"
    assert Repo.get!(Oban.Job, job.id).attempt == 2
    assert Host.counts(target.reference) == %{"request" => 1, "effect" => 1}

    assert {:ok, %{status: :uncertain, record: unchanged}} =
             Continuation.get(target.continuation.store, target.agent_id)

    assert unchanged == uncertain
    refute Jason.encode!(unchanged) =~ "synthetic-private"

    File.write!(
      Path.join(System.fetch_env!("EXAGENT_FRAMEWORK_ARTIFACTS"), "oban-uncertainty.json"),
      Jason.encode!(
        %{
          counts: Host.counts(target.reference),
          job_id: job.id,
          attempt: 2,
          job_state: "cancelled",
          continuation_state: "uncertain",
          record_id: unchanged["record_id"],
          revision: unchanged["revision"],
          fresh_vms: 2,
          expected_crash_exit: 73,
          repeated_effects: 0,
          explicit_operator_recovery: true,
          record_unchanged_on_redelivery: true
        },
        pretty: true
      )
    )

    IO.puts("PASS actual crashed Oban delivery: explicit C7 recovery, uncertainty, zero replay")
  end
end

case System.argv() do
  [phase] when phase in ~w(crash recover) -> FrameworkIntegrations.CrashProbe.run(phase)
  _ -> raise ArgumentError, "explicit crash/recover phase is required"
end
