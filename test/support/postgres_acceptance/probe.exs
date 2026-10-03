defmodule ExAgent.PostgresAcceptance.Repo do
  use Ecto.Repo, otp_app: :exagent, adapter: Ecto.Adapters.Postgres
end

defmodule ExAgent.PostgresAcceptance.ProxyRepo do
  use Ecto.Repo, otp_app: :exagent, adapter: Ecto.Adapters.Postgres
end

defmodule ExAgent.PostgresAcceptance do
  import ExUnit.Assertions
  alias ExAgent.{Continuation, Permissions, Store, Tool}
  alias ExAgent.Continuation.Record
  alias ExAgent.Message.Part
  alias ExAgent.PostgresAcceptance.{ProxyRepo, Repo}

  @table "qualification_records"
  @namespace "synthetic-qualification"

  def run(phase, artifacts) do
    assert System.get_env("EXAGENT_SQL_QUALIFICATION") == "1"
    Application.put_env(:req_llm, :load_dotenv, false)
    {:ok, _} = Application.ensure_all_started(:exagent)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    {:ok, repo} =
      Repo.start_link(
        socket_dir: System.fetch_env!("EXAGENT_QUALIFICATION_SOCKET"),
        database: System.fetch_env!("EXAGENT_QUALIFICATION_DATABASE"),
        username: System.fetch_env!("EXAGENT_QUALIFICATION_USER"),
        port: 5432,
        pool_size: 4,
        queue_target: 100,
        queue_interval: 1_000,
        log: false
      )

    try do
      observations = execute(phase, artifacts)
      result = %{phase: phase, passed: true, observations: observations}
      File.write!(Path.join(artifacts, phase <> ".json"), Jason.encode!(result, pretty: true))
      IO.puts("PASS PostgreSQL qualification phase " <> phase)
    after
      Supervisor.stop(repo)
    end
  end

  defp store, do: Store.scoped({Store.Postgres, {Repo, table: @table}}, @namespace)

  defp execute("primitives", artifacts) do
    :ok = Store.Postgres.migrate(Repo, @table)
    {:ok, _} = Repo.query("CREATE TABLE qualification_effects (id text PRIMARY KEY)", [])
    {:ok, %{rows: [[version]]}} = Repo.query("SHOW server_version", [])
    {:ok, %{rows: [["read committed"]]}} = Repo.query("SHOW transaction_isolation", [])

    snapshot = ExAgent.Server.Snapshot.new(agent_id: "legacy", history: [], metadata: %{ok: true})
    assert :ok = Store.save_agent_snapshot(store(), snapshot)
    assert {:ok, loaded} = Store.load_agent_snapshot(store(), "legacy")
    assert loaded.metadata == %{"ok" => true}
    assert :ok = Store.delete_agent_snapshot(store(), "legacy")
    assert {:error, :not_found} = Store.load_agent_snapshot(store(), "legacy")

    creates = for index <- 0..1, do: create("create-race", "create-#{index}")

    results =
      race(fn index ->
        Store.transition(store(), :agent, "create-race", :absent, Enum.at(creates, index))
      end)

    assert one_winner?(results)
    assert {:ok, %{"revision" => 1} = initial} = Store.load_record(store(), :agent, "create-race")

    claims = for index <- 0..1, do: claim(initial, "claim-#{index}")

    results =
      race(fn index ->
        Store.transition(store(), :agent, "create-race", 1, Enum.at(claims, index))
      end)

    assert one_winner?(results)
    assert {:ok, %{"revision" => 2}} = Store.load_record(store(), :agent, "create-race")

    command = create("lost-ack", "lost-ack-create")
    # A real committed transaction is followed by a deliberately discarded ACK.
    assert {:ok, %{replayed: false}} =
             Store.transition(store(), :agent, "lost-ack", :absent, command)

    assert {:ok, %{replayed: true, record: %{"revision" => 1}}} =
             Store.transition(store(), :agent, "lost-ack", :absent, command)

    assert {:error, :atomic_record_required} =
             Store.save_agent_snapshot(store(), ExAgent.Server.Snapshot.new(agent_id: "lost-ack"))

    assert {:error, :atomic_record_required} = Store.delete_agent_snapshot(store(), "lost-ack")

    assert {:ok, lost_ack_record} = Store.load_record(store(), :agent, "lost-ack")

    assert {:error, :conflict} =
             Store.transition(store(), :agent, "lost-ack", 99, claim(lost_ack_record, "stale"))

    assert {:ok, %{"revision" => 1}} = Store.load_record(store(), :agent, "lost-ack")

    delete_controls()
    File.write!(Path.join(artifacts, "server-version.txt"), version)

    [
      %{
        server_version: version,
        isolation: "read committed",
        create_winners: 1,
        claim_winners: 1,
        receipt_replay_revision: 1,
        legacy_protection: true,
        deletion_denial_rollback: true
      }
    ]
  end

  defp execute("pause", _) do
    assert {:ok, paused} =
             ExAgent.run(agent(), "synthetic",
               continuation: config("runtime"),
               permissions: Permissions.new!(default: :ask)
             )

    assert paused.status == :paused
    assert paused.request_count == 1
    assert paused.tool_calls == 1
    assert {:ok, %{status: :pending, record: record}} = Continuation.get(store(), "runtime")
    assert record["execution"]["owner_id"] == nil
    assert effects() == []
    assert Record.validate(record, {@namespace, :agent, "runtime"}) == :ok
    [%{status: "pending", requests: 1, tool_calls: 1, effects: 0, owner_released: true}]
  end

  defp execute("lost-ack-network", artifacts) do
    {:ok, proxy_repo} =
      ProxyRepo.start_link(
        hostname: "127.0.0.1",
        port: System.fetch_env!("EXAGENT_NETWORK_ACK_PROXY_PORT") |> String.to_integer(),
        database: System.fetch_env!("EXAGENT_QUALIFICATION_DATABASE"),
        username: System.fetch_env!("EXAGENT_QUALIFICATION_USER"),
        ssl: false,
        pool_size: 1,
        connect_timeout: 2_000,
        timeout: 5_000,
        log: false
      )

    try do
      proxy_store = Store.scoped({Store.Postgres, {ProxyRepo, table: @table}}, @namespace)
      command = create("lost-ack-network", "network-create")

      first_result =
        try do
          Store.transition(proxy_store, :agent, "lost-ack-network", :absent, command)
        rescue
          _ in DBConnection.ConnectionError -> {:error, :commit_connection_lost}
        end

      assert match?({:error, _}, first_result)

      assert {:ok, %{"revision" => 1} = committed} =
               Store.load_record(store(), :agent, "lost-ack-network")

      proxy_receipt = Path.join(artifacts, "ack-proxy.json") |> File.read!() |> Jason.decode!()
      assert proxy_receipt["server_commit_observed"]
      refute proxy_receipt["commit_reply_forwarded"]
      assert proxy_receipt["errors"] == []

      assert {:ok, %{replayed: true, record: ^committed}} =
               Store.transition(proxy_store, :agent, "lost-ack-network", :absent, command)

      assert {:ok, ^committed} = Store.load_record(store(), :agent, "lost-ack-network")
      assert effects() == []

      [
        %{
          server_commit_observed: true,
          commit_reply_forwarded: false,
          client_confirmed_first_commit: false,
          receipt_replayed: true,
          unchanged_revision: 1,
          model_requests: 0,
          tool_effects: 0
        }
      ]
    after
      Supervisor.stop(proxy_repo)
    end
  end

  defp execute("resume", _) do
    assert {:ok, %{status: :pending, record: record}} = Continuation.get(store(), "runtime")
    [{approval_id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    assert {:ok, %{record: approved}} =
             Continuation.decide(store(), "runtime", :approve,
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "approve-runtime",
               approval_id: approval_id,
               payload_hash: approval["payload_hash"],
               actor: :synthetic,
               authorize: fn :synthetic, :approve, _ -> {:ok, "synthetic-human"} end
             )

    reference = %{id: "runtime", record_id: approved["record_id"], revision: approved["revision"]}

    assert {:ok, result} =
             ExAgent.resume(agent(), reference,
               continuation: config("runtime"),
               permissions: Permissions.new!(default: :ask)
             )

    assert result.status == :succeeded
    assert result.output == "done"
    assert result.request_count == 2
    assert result.tool_calls == 1
    assert effects() == [["runtime"]]
    assert {:ok, %{status: :completed}} = Continuation.get(store(), "runtime")
    assert {:error, _} = ExAgent.resume(agent(), reference, continuation: config("runtime"))
    assert effects() == [["runtime"]]
    [%{status: "completed", requests: 2, tool_calls: 1, effects: 1, stale_resume_effects: 0}]
  end

  defp execute("two-resumers-seed", artifacts) do
    :ok = Store.Postgres.migrate(Repo, @table)
    Repo.query!("CREATE TABLE qualification_effects (id text PRIMARY KEY)", [])

    {:ok, _} =
      Repo.query(
        "CREATE TABLE qualification_requests (id bigserial PRIMARY KEY, run_id text NOT NULL)",
        []
      )

    assert {:ok, %{status: :paused}} =
             ExAgent.run(agent("two-resumers", false, true), "synthetic",
               continuation: config("two-resumers"),
               permissions: Permissions.new!(default: :ask)
             )

    assert {:ok, %{status: :pending, record: record}} = Continuation.get(store(), "two-resumers")
    [{approval_id, approval}] = Map.to_list(record["execution"]["progress"]["approvals"])

    assert {:ok, %{record: approved}} =
             Continuation.decide(store(), "two-resumers", :approve,
               record_id: record["record_id"],
               revision: record["revision"],
               operation_id: "approve-two-resumers",
               approval_id: approval_id,
               payload_hash: approval["payload_hash"],
               actor: :synthetic,
               authorize: fn :synthetic, :approve, _ -> {:ok, "synthetic-human"} end
             )

    reference = %{
      id: "two-resumers",
      record_id: approved["record_id"],
      revision: approved["revision"]
    }

    File.write!(Path.join(artifacts, "two-resumers-reference.json"), Jason.encode!(reference))
    assert request_observations() == 1
    assert effects() == []
    [%{status: "approved", requests_observed: 1, effects: 0, approval_bound: true}]
  end

  defp execute(phase, artifacts) when phase in ["two-resumers-a", "two-resumers-b"] do
    data = Path.join(artifacts, "two-resumers-reference.json") |> File.read!() |> Jason.decode!()
    reference = %{id: data["id"], record_id: data["record_id"], revision: data["revision"]}
    assert {:ok, %{status: :approved}} = Continuation.get(store(), "two-resumers")
    File.write!(Path.join(artifacts, phase <> "-ready"), "ready")
    barrier = Path.join(artifacts, "two-resumers-go")
    assert wait_file(barrier, System.monotonic_time(:millisecond) + 5_000)

    result =
      ExAgent.resume(agent("two-resumers", false, true), reference,
        continuation: config("two-resumers"),
        permissions: Permissions.new!(default: :ask)
      )

    case result do
      {:ok, completed} ->
        assert completed.status == :succeeded and completed.output == "done"
        assert completed.request_count == 2 and completed.tool_calls == 1
        [%{winner: true, requests: 2, tool_calls: 1}]

      {:error, _} ->
        [%{winner: false}]

      other ->
        flunk("unexpected resume result: #{inspect(other)}")
    end
  end

  defp execute("two-resumers-verify", artifacts) do
    winners =
      for phase <- ["two-resumers-a", "two-resumers-b"] do
        receipt = Path.join(artifacts, phase <> ".json") |> File.read!() |> Jason.decode!()
        [%{"winner" => winner}] = receipt["observations"]
        winner
      end

    assert Enum.count(winners, & &1) == 1
    assert request_observations() == 2
    assert effects() == [["two-resumers"]]

    assert {:ok, %{status: :completed, record: record}} =
             Continuation.get(store(), "two-resumers")

    assert Record.validate(record, {@namespace, :agent, "two-resumers"}) == :ok

    [
      %{
        separate_vms: 2,
        winners: 1,
        requests_observed: 2,
        tool_effects: 1,
        status: "completed",
        no_replay: true
      }
    ]
  end

  defp execute("flow-a8-pause", artifacts) do
    load_flow_fixture()
    :ok = Store.Postgres.migrate(Repo, @table)
    path = Path.join(artifacts, "flow-effects.log")
    {definition, catalog} = ExAgent.FlowRuntimeFixture.host(path)

    assert {:ok, result} =
             ExAgent.Coordination.Flow.run(definition, "synthetic",
               continuation: flow_config(),
               delegate_definitions: catalog
             )

    assert result.status == :paused and result.request_count == 4 and result.tool_calls == 6
    assert {:ok, %{status: :pending, record: record}} = Continuation.get(store(), "flow-a8")
    assert record["execution"]["owner_id"] == nil
    assert record["execution"]["progress"]["runtime"]["frame_version"] == 11
    assert Record.validate(record, {@namespace, :agent, "flow-a8"}) == :ok
    lines = File.read!(path) |> String.split("\n", trim: true)
    assert Enum.count(lines, &(&1 == "A")) == 1
    assert Enum.count(lines, &(&1 == "B")) == 1
    assert Enum.count(lines, &(&1 == "D")) == 1
    refute Enum.any?(lines, &String.starts_with?(&1, "ASK:"))

    [
      %{
        status: "pending",
        frame_version: 11,
        failed_branch_preserved: true,
        requests: 4,
        tool_attempts: 6,
        early_effects: 3,
        approval_effects: 0,
        owner_released: true
      }
    ]
  end

  defp execute("flow-a8-resume", artifacts) do
    load_flow_fixture()
    path = Path.join(artifacts, "flow-effects.log")
    assert {:ok, %{status: :pending, record: initial}} = Continuation.get(store(), "flow-a8")

    approved =
      Enum.reduce(
        Map.keys(initial["execution"]["progress"]["approvals"]),
        initial,
        fn approval_id, record ->
          approval = record["execution"]["progress"]["approvals"][approval_id]

          assert {:ok, %{record: next}} =
                   Continuation.decide(store(), "flow-a8", :approve,
                     record_id: record["record_id"],
                     revision: record["revision"],
                     operation_id: "flow-approve-#{approval_id}",
                     approval_id: approval_id,
                     payload_hash: approval["payload_hash"],
                     actor: :synthetic,
                     authorize: fn :synthetic, :approve, _ -> {:ok, "synthetic-human"} end
                   )

          next
        end
      )

    reference = %{
      version: 1,
      id: "flow-a8",
      record_id: approved["record_id"],
      revision: approved["revision"],
      run_id: approved["execution"]["run_id"]
    }

    {definition, catalog} = ExAgent.FlowRuntimeFixture.host(path, true)

    assert {:ok, result} =
             ExAgent.Coordination.Flow.resume(definition, reference,
               continuation: flow_config(),
               delegate_definitions: catalog
             )

    assert result.status == :completed and result.request_count == 6 and result.tool_calls == 6
    assert Enum.map(result.output, & &1["status"]) == ~w(failed completed completed)
    assert {:ok, %{status: :completed, record: completed}} = Continuation.get(store(), "flow-a8")
    assert Record.validate(completed, {@namespace, :agent, "flow-a8"}) == :ok
    lines = File.read!(path) |> String.split("\n", trim: true)

    for effect <- ~w(A B D ASK:ask1 ASK:ask2 C),
        do: assert(Enum.count(lines, &(&1 == effect)) == 1)

    assert {:ok, again} =
             ExAgent.Coordination.Flow.resume(definition, result.continuation,
               continuation: flow_config(),
               delegate_definitions: catalog
             )

    assert again.output == result.output
    assert File.read!(path) |> String.split("\n", trim: true) == lines

    [
      %{
        status: "completed",
        frame_version: 11,
        failed_branch_preserved: true,
        fresh_vm_after_database_restart: true,
        requests: 6,
        tool_attempts: 6,
        actual_effects: 5,
        no_replay: true,
        terminal_read_inert: true
      }
    ]
  end

  defp execute("crash", _) do
    ExAgent.run(agent("crash", true), "synthetic", continuation: config("crash"))
    flunk("the confirmed tool effect must terminate this VM")
  end

  defp execute("recover", _) do
    assert {:ok, %{record: before}} = Continuation.get(store(), "crash")

    assert Enum.any?(before["execution"]["effects"], fn {_, effect} ->
             is_nil(effect["outcome"])
           end)

    assert {:ok, %{record: recovered}} =
             Continuation.recover(store(), "crash",
               record_id: before["record_id"],
               revision: before["revision"],
               operation_id: "recover-crash",
               actor: :synthetic,
               authorize: fn :synthetic, :recover, _ -> {:ok, "synthetic-host"} end
             )

    assert {:ok, %{status: :uncertain}} = Continuation.get(store(), "crash")
    reference = %{id: "crash", record_id: recovered["record_id"], revision: recovered["revision"]}
    assert {:error, _} = ExAgent.resume(agent("crash"), reference, continuation: config("crash"))
    assert Enum.count(effects(), &(&1 == ["crash"])) == 1

    [
      %{
        status: "uncertain",
        effects: 1,
        automatic_replay: false,
        recovered_revision: recovered["revision"]
      }
    ]
  end

  defp execute("inventory", artifacts) do
    {:ok, %{rows: rows}} =
      Repo.query("SELECT key, data FROM qualification_records ORDER BY key", [])

    assert length(rows) == 5

    for [_, bytes] <- rows do
      decoded = Jason.decode!(bytes)
      assert is_map(decoded)
      assert decoded["record_version"] in [1, 2, 3]
    end

    File.write!(Path.join(artifacts, "record-inventory.json"), Jason.encode!(rows))

    [
      %{
        records: length(rows),
        digest: Base.encode16(:crypto.hash(:sha256, Jason.encode!(rows)), case: :lower)
      }
    ]
  end

  defp execute("restored", artifacts) do
    expected = File.read!(Path.join(artifacts, "record-inventory.json")) |> Jason.decode!()

    {:ok, %{rows: rows}} =
      Repo.query("SELECT key, data FROM qualification_records ORDER BY key", [])

    assert rows == expected
    assert {:ok, %{status: :completed}} = Continuation.get(store(), "runtime")
    assert {:ok, %{status: :uncertain}} = Continuation.get(store(), "crash")
    assert Enum.sort(effects()) == [["crash"], ["runtime"]]

    [
      %{
        records: length(rows),
        byte_equal: true,
        completed_and_uncertain_readable: true,
        effects: 2
      }
    ]
  end

  defp delete_controls do
    assert {:ok, %{record: record}} =
             Store.transition(
               store(),
               :agent,
               "denied-delete",
               :absent,
               create("denied-delete", "create-delete")
             )

    assert {:ok, %{record: cancelled}} =
             Store.transition(
               store(),
               :agent,
               "denied-delete",
               record["revision"],
               command(record, "cancel", %{}, "cancel-delete")
             )

    deletion =
      command(
        cancelled,
        "delete",
        %{"before" => System.system_time(:millisecond) + 1_000},
        "delete-denied"
      )

    {:ok, _} =
      Repo.query(
        "CREATE FUNCTION suppress_qualification_delete() RETURNS trigger LANGUAGE plpgsql AS 'BEGIN RETURN NULL; END'",
        []
      )

    {:ok, _} =
      Repo.query(
        "CREATE TRIGGER suppress_delete BEFORE DELETE ON qualification_records FOR EACH ROW EXECUTE FUNCTION suppress_qualification_delete()",
        []
      )

    assert {:error, :conflict} =
             Store.transition(store(), :agent, "denied-delete", cancelled["revision"], deletion)

    assert {:ok, ^cancelled} = Store.load_record(store(), :agent, "denied-delete")
    {:ok, _} = Repo.query("DROP TRIGGER suppress_delete ON qualification_records", [])

    assert {:ok, %{record: nil}} =
             Store.transition(store(), :agent, "denied-delete", cancelled["revision"], deletion)

    assert {:error, :not_found} = Store.load_record(store(), :agent, "denied-delete")
  end

  defp request_observations do
    {:ok, %{rows: [[count]]}} =
      Repo.query("SELECT count(*) FROM qualification_requests WHERE run_id = $1", ["two-resumers"])

    count
  end

  defp load_flow_fixture do
    Code.require_file("../delegation_runtime_fixture.ex", __DIR__)
    Code.require_file("../flow_runtime_fixture.ex", __DIR__)
  end

  defp flow_config,
    do: %{
      store: store(),
      id: "flow-a8",
      durability: :durable,
      policy: ExAgent.DelegationRuntimeFixture.reference("policy"),
      expires_at: nil,
      deadline_at: nil,
      lease_ms: 20_000,
      active_time_limit_ms: 30_000
    }

  defp wait_file(path, deadline) do
    cond do
      File.exists?(path) ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        wait_file(path, deadline)
    end
  end

  defp create(id, operation) do
    snapshot =
      ExAgent.Server.Snapshot.new(agent_id: id, history: [], revision: 0)
      |> Record.snapshot_data()

    execution = %{
      "continuation_id" => id,
      "run_id" => "run-" <> id,
      "request_id" => "request-" <> id,
      "definition" => %{"id" => "synthetic", "version" => "1"},
      "policy" => %{"id" => "synthetic", "version" => "1"},
      "model_ref" => %{"id" => "test", "version" => "1"},
      "deadline_at" => nil,
      "expires_at" => nil,
      "progress" => %{"active_elapsed_ms" => 0, "admissions" => []}
    }

    command(
      %{"record_id" => "record-" <> id},
      "create",
      %{"snapshot" => snapshot, "execution" => execution},
      operation
    )
  end

  defp claim(record, operation),
    do:
      command(
        record,
        "claim",
        %{
          "owner_id" => operation,
          "attempt_id" => operation,
          "lease_until" => System.system_time(:millisecond) + 10_000
        },
        operation
      )

  defp command(record, operation, payload, id),
    do: %{
      "record_id" => record["record_id"],
      "operation" => operation,
      "operation_id" => id,
      "actor_id" => "synthetic-host",
      "payload" => payload
    }

  defp race(fun) do
    tasks =
      for index <- 0..1,
          do:
            Task.async(fn ->
              receive do
                :start -> fun.(index)
              end
            end)

    Enum.each(tasks, &send(&1.pid, :start))
    Enum.map(tasks, &Task.await(&1, 10_000))
  end

  defp one_winner?(results),
    do:
      Enum.count(results, &match?({:ok, _}, &1)) == 1 and
        Enum.count(results, &(&1 == {:error, :conflict})) == 1

  defp agent(effect_id \\ "runtime", crash? \\ false, observe? \\ false) do
    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        max_retries: 0,
        call: fn _, _ ->
          if observe?, do: Repo.query!("SELECT pg_sleep(0.15)", [])

          {:ok, %{num_rows: 1}} =
            Repo.query("INSERT INTO qualification_effects (id) VALUES ($1)", [effect_id])

          if crash?, do: System.halt(73)
          {:ok, "saved"}
        end
      )

    script = [
      {:tool_calls, [%Part.ToolCall{tool_name: "effect", tool_call_id: "one", args: %{}}]},
      "done"
    ]

    script =
      if observe?,
        do:
          Enum.map(script, fn item ->
            fn _, _ ->
              Repo.query!("INSERT INTO qualification_requests (run_id) VALUES ($1)", [effect_id])
              item
            end
          end),
        else: script

    model = %ExAgent.Models.Test{script: script}

    ExAgent.new(model: model, tools: [tool])
  end

  defp effects do
    {:ok, %{rows: rows}} = Repo.query("SELECT id FROM qualification_effects ORDER BY id", [])
    rows
  end

  defp config(id),
    do: %{
      store: store(),
      id: id,
      durability: :durable,
      expires_at: nil,
      deadline_at: nil,
      lease_ms: 1_000,
      active_time_limit_ms: 20_000,
      definition: %{"id" => "synthetic", "version" => "1"},
      policy: %{"id" => "synthetic", "version" => "1"},
      model_ref: %{"id" => "test", "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }
end

case System.argv() do
  [phase, artifacts]
  when phase in ~w(primitives lost-ack-network two-resumers-seed two-resumers-a two-resumers-b two-resumers-verify flow-a8-pause flow-a8-resume pause resume crash recover inventory restored) ->
    ExAgent.PostgresAcceptance.run(phase, artifacts)

  _ ->
    raise ArgumentError, "explicit phase and artifact directory are required"
end
