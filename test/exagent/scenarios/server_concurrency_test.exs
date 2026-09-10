defmodule ExAgent.Scenarios.ServerConcurrencyTest do
  @moduledoc """
  Regression tests for ExAgent.Server concurrency edges:

    * stale progress, deltas, events, task results and DOWN messages must not
      corrupt an idle owner or its next active run,
    * abort racing with natural completion must not crash the server
      (terminate_child returns {:error, :not_found} when the task is already gone),
    * a pubsub backend returning {:error, _} must not crash the server.
  """

  use ExUnit.Case, async: true

  alias ExAgent.{Event, Message, Models.Test, PubSub, RunEvent, Server}
  alias ExAgent.Message.{Part, Usage}

  # Defined at top level so the `{ErrorPubSub, []}` tuple stores the full module
  # atom (a nested module would store only the short name and fail to resolve).
  #
  # A PubSub backend that always fails — proves the server is resilient.
  defmodule ErrorPubSub do
    @behaviour ExAgent.PubSub
    @impl true
    def broadcast(_config, _topic, _event), do: {:error, :boom}
    @impl true
    def subscribe(_config, _topic), do: {:error, :boom}
  end

  describe "stale stream messages do not corrupt a later run" do
    test "live message shapes from run A are ignored while idle and while run B is blocked" do
      owner = self()
      id = "stale-#{unique()}"
      name = :"testing_audit_stale_#{unique()}"

      blocked = fn label ->
        fn ->
          # Same-producer call acknowledges all preceding core events/progress.
          Server.health(name)
          send(owner, {:run_waiting, label, self()})
          receive do: (:release -> "answer-" <> label)
        end
      end

      server =
        start_supervised!(
          {Server,
           agent: ExAgent.new(model: %Test{script: [blocked.("a"), blocked.("b")]}),
           pubsub: :local,
           agent_id: id,
           name: name}
        )

      :ok = PubSub.subscribe({PubSub.Local, []}, Event.agent_topic(id))
      assert {:ok, request_a} = Server.send_message(server, "a")
      assert_receive {:run_waiting, "a", worker_a}, 1000
      old = :sys.get_state(server).current
      send(worker_a, :release)
      assert_receive {:exagent_event, %Event{type: :run_finished, request_id: ^request_a}}, 1000
      baseline = observed_state(server)
      discard_events()

      inject_stale(server, old)
      assert Server.health(server).status == :idle
      assert observed_state(server) == baseline
      refute_received {:exagent_event, _}

      assert {:ok, request_b} = Server.send_message(server, "b")
      assert_receive {:run_waiting, "b", worker_b}, 1000
      current = :sys.get_state(server).current
      refute current.run_id == old.run_id
      discard_events()
      inject_stale(server, old)
      assert Server.health(server).status == :running
      assert :sys.get_state(server).current == current
      assert observed_state(server) == baseline
      refute_received {:exagent_event, _}

      send(worker_b, :release)

      assert_receive {:exagent_event,
                      %Event{
                        type: :run_finished,
                        request_id: ^request_b,
                        payload: %{
                          output: "answer-b",
                          usage: %{"input_tokens" => 1, "output_tokens" => 1}
                        }
                      }},
                     1000

      assert Server.health(server).status == :idle
      assert :sys.get_state(server).model.index == 2
      assert Server.usage(server) == %Usage{input_tokens: 2, output_tokens: 2}

      assert Enum.map(Message.parts(Server.history(server)), &{&1.__struct__, &1.content}) ==
               [
                 {Part.User, "a"},
                 {Part.Text, "answer-a"},
                 {Part.User, "b"},
                 {Part.Text, "answer-b"}
               ]

      refute Message.to_json(Server.history(server)) =~ "STALE_SENTINEL"

      for type <- [:run_finished, :run_failed, :server_request_cancelled] do
        refute_received {:exagent_event, %Event{type: ^type}}
      end
    end
  end

  describe "abort racing with completion does not crash the server" do
    test "abort after a run already finished returns :ok and keeps the server alive" do
      {:ok, server} =
        start_server(model: %Test{label: "done"}, agent_id: "abort-race-#{unique()}")

      # Run to completion, then abort (task is gone by now).
      assert {:ok, _} = Server.chat(server, "go")
      assert :ok = Server.abort(server)
      assert %{status: :idle} = Server.health(server)
    end
  end

  describe "a pubsub backend returning {:error, _} does not crash the server" do
    test "the run still returns its result" do
      {:ok, server} =
        Server.start_link(
          agent: ExAgent.new(model: %Test{label: "ok"}),
          pubsub: {ErrorPubSub, []},
          agent_id: "pubsub-err-#{unique()}"
        )

      # The backend always errors; the run must still complete normally.
      assert {:ok, %{output: "ok"}} = Server.chat(server, "go")
      assert %{status: :idle} = Server.health(server)
    end
  end

  # ---------------------------------------------------------------------------
  defp unique, do: :erlang.unique_integer([:positive])

  defp start_server(opts) do
    model = Keyword.get(opts, :model, %Test{label: "hi"})
    agent = ExAgent.new(model: model)

    {:ok, pid} =
      Server.start_link(
        agent: agent,
        agent_id: Keyword.fetch!(opts, :agent_id),
        pubsub: Keyword.get(opts, :pubsub, :local)
      )

    _ = :sys.get_state(pid)
    {:ok, pid}
  end

  defp observed_state(server),
    do: {Server.history(server), Server.usage(server), :sys.get_state(server).model}

  defp inject_stale(server, old) do
    poisoned =
      Map.merge(old.progress, %{
        output: "STALE_SENTINEL",
        messages: [Message.new_request([%Part.User{content: "STALE_SENTINEL"}])],
        model: %Test{label: "STALE_SENTINEL", index: 99},
        usage: %Usage{input_tokens: 888, output_tokens: 999}
      })

    send(server, {:run_progress, old.run_id, poisoned})
    send(server, {:stream_delta, old.run_id, "STALE_SENTINEL"})

    send(
      server,
      {:run_event, RunEvent.new(:text_delta, run_id: old.run_id, data: %{text: "STALE_SENTINEL"})}
    )

    send(server, {old.ref, {:ok, poisoned}})
    send(server, {:DOWN, old.ref, :process, old.pid, :stale_failure})
  end

  defp discard_events do
    receive do
      {:exagent_event, _} -> discard_events()
    after
      0 -> :ok
    end
  end
end
