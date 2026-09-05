defmodule ExAgent.ServerOwnershipTest do
  use ExUnit.Case, async: true

  alias ExAgent.{AgentSupervisor, Event, Models.Test, PubSub, Server, Tool}
  alias ExAgent.Message.Part

  for outcome <- [:complete, :abort, :crash, :owner_kill] do
    @tag :capture_log
    test "guardian is cleaned up after #{outcome}" do
      parent = self()

      model = %Test{
        script: [
          fn ->
            # Owner cancellation must work even if provider/user code traps exits.
            Process.flag(:trap_exit, unquote(outcome == :owner_kill))
            send(parent, {:working, self()})

            receive do
              :release -> "done"
            end
          end
        ]
      }

      server =
        start_supervised!(
          Supervisor.child_spec(
            {Server, agent: ExAgent.new(model: model), pubsub: :local},
            restart: :temporary
          )
        )

      :ok =
        PubSub.subscribe(
          {ExAgent.PubSub.Local, []},
          Event.agent_topic(:sys.get_state(server).agent_id)
        )

      assert {:ok, request_id} = Server.send_message(server, "go")
      assert_receive {:working, worker}
      {:monitored_by, monitors} = Process.info(worker, :monitored_by)
      assert [guardian] = List.delete(monitors, server)
      guardian_ref = Process.monitor(guardian)
      worker_ref = Process.monitor(worker)
      on_exit(fn -> Process.exit(worker, :kill) end)

      case unquote(outcome) do
        :complete -> send(worker, :release)
        :abort -> assert :ok = Server.abort(server)
        :crash -> Process.exit(worker, :kill)
        :owner_kill -> Process.exit(server, :kill)
      end

      assert_receive {:DOWN, ^worker_ref, :process, ^worker, _}, 1000
      assert_receive {:DOWN, ^guardian_ref, :process, ^guardian, _}, 1000

      if unquote(outcome == :complete) do
        assert_receive {:exagent_event, %Event{type: :run_finished, request_id: ^request_id}}
        assert %{status: :idle} = Server.health(server)
      end

      if unquote(outcome == :crash) do
        assert_receive {:exagent_event, %Event{type: :run_failed, request_id: ^request_id}}
        assert %{status: :idle} = Server.health(server)
      end
    end
  end

  for mode <- [:send_message, :stream], stop <- [:normal, :kill, :stop_agent] do
    test "#{stop} cancels the #{mode} worker" do
      parent = self()

      model = %Test{
        script: [
          fn ->
            send(parent, {:working, self()})

            receive do
              :release -> "done"
            end
          end
        ]
      }

      opts = [agent: ExAgent.new(model: model)]

      server =
        if unquote(stop) == :stop_agent do
          {:ok, pid} = AgentSupervisor.start_agent(opts)
          on_exit(fn -> AgentSupervisor.stop_agent(pid) end)
          pid
        else
          start_supervised!(Supervisor.child_spec({Server, opts}, restart: :temporary))
        end

      assert {:ok, _} = apply(Server, unquote(mode), [server, "go"])
      assert_receive {:working, worker}
      ref = Process.monitor(worker)
      on_exit(fn -> Process.exit(worker, :kill) end)

      case unquote(stop) do
        :normal -> GenServer.stop(server)
        :kill -> Process.exit(server, :kill)
        :stop_agent -> assert :ok = AgentSupervisor.stop_agent(server)
      end

      assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
    end
  end

  test "owner death cancels tool tasks too" do
    parent = self()

    tool =
      Tool.new(
        name: "block",
        takes_ctx: false,
        call: fn _ ->
          send(parent, {:tool, self()})

          receive do
            :release -> {:ok, "done"}
          end
        end
      )

    model = %Test{script: [{:tool_calls, [%Part.ToolCall{tool_name: "block", args: %{}}]}]}

    server =
      start_supervised!(
        Supervisor.child_spec(
          {Server, agent: ExAgent.new(model: model, tools: [tool])},
          restart: :temporary
        )
      )

    assert {:ok, _} = Server.send_message(server, "go")
    assert_receive {:tool, worker}
    ref = Process.monitor(worker)
    run = :sys.get_state(server).current.pid

    on_exit(fn ->
      Process.exit(run, :kill)
      Process.exit(worker, :kill)
    end)

    Process.exit(server, :kill)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
  end

  test "abort replies to chat, enforces busy, cancels worker and permits another run" do
    parent = self()

    model = %Test{
      script: [
        fn ->
          send(parent, {:working, self()})

          receive do
            :go -> "done"
          end
        end
      ]
    }

    server = start_supervised!({Server, agent: ExAgent.new(model: model), pubsub: :local})

    :ok =
      PubSub.subscribe(
        {ExAgent.PubSub.Local, []},
        Event.agent_topic(:sys.get_state(server).agent_id)
      )

    start_supervised!({Task, fn -> send(parent, {:chat_result, Server.chat(server, "go")}) end})
    assert_receive {:working, worker}
    ref = Process.monitor(worker)
    assert {:error, :busy} = Server.chat(server, "busy")
    assert {:error, :busy} = Server.stream(server, "busy")
    assert :ok = Server.abort(server)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
    assert_receive {:chat_result, {:error, :aborted}}
    assert_receive {:exagent_event, %Event{type: :server_request_cancelled}}
    assert %{status: :idle} = Server.health(server)
    assert :ok = Server.abort(server)
    assert :ok = Server.set_model(server, %Test{label: "new"})
    assert {:ok, %{output: "new"}} = Server.chat(server, "again")
  end
end
