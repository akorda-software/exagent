defmodule ExAgent.ServerPayloadLimitsTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Event, Message, Server}
  alias ExAgent.Models.Test

  defmodule Events do
    @behaviour ExAgent.PubSub
    def subscribe(_, _), do: :ok
    def broadcast(owner, _, event), do: send(owner, {:event, event}) && :ok
  end

  test "input admission accepts the exact external byte limit and rejects one more preIO" do
    owner = self()

    model = %Test{
      script: [
        fn _, _ ->
          send(owner, :model_called)
          "ok"
        end
      ]
    }

    opts = [trace_context: nil]
    limit = :erlang.external_size({"x", opts})
    server = server(model, max_input_bytes: limit)

    assert {:error, {:input_too_large, %{bytes: bytes, limit: ^limit}}} =
             Server.chat(server, "xx", opts)

    assert bytes == limit + 1
    refute_receive :model_called, 20
    assert {:ok, _} = Server.chat(server, "x", opts)
    assert_receive :model_called
  end

  test "pending byte saturation is exact and abort/dequeue release charged bytes" do
    owner = self()
    model = %Test{script: [blocked(owner), blocked(owner), "done"]}
    opts = [trace_context: nil, request_id: "queued"]
    bytes = :erlang.external_size({"queued", opts})
    server = server(model, max_pending: 4, max_pending_bytes: bytes)
    assert {:ok, "active"} = Server.send_message(server, "first", request_id: "active")
    # This is a readiness barrier, not a 100ms latency contract under async load.
    assert_receive {:ready, _}, 1000
    assert {:ok, "queued"} = Server.send_message(server, "queued", opts)
    assert %{pending: 1, pending_bytes: ^bytes} = Server.health(server)
    assert {:error, :queue_full} = Server.steer(server, "queued", opts)
    assert :ok = Server.abort(server)
    assert_receive {:ready, worker}
    assert %{pending: 0, pending_bytes: 0} = Server.health(server)
    send(worker, :release)
    terminal("queued")
    assert %{pending: 0, pending_bytes: 0, status: :idle} = Server.health(server)
    short = server(%Test{script: [blocked(owner)]}, max_pending_bytes: bytes - 1)
    assert {:ok, _} = Server.send_message(short, "first")
    assert_receive {:ready, _}
    assert {:error, :queue_full} = Server.send_message(short, "queued", opts)
    assert %{pending_bytes: 0} = Server.health(short)
    assert :ok = Server.abort(short)
  end

  test "expired queued deadline returns a terminal without IO and releases all queue bytes" do
    owner = self()

    model = %Test{
      script: [
        blocked(owner),
        fn _, _ ->
          send(owner, :unexpected_io)
          "bad"
        end
      ]
    }

    server = server(model)
    assert {:ok, "active"} = Server.send_message(server, "first", request_id: "active")
    assert_receive {:ready, worker}

    assert {:ok, "expired"} =
             Server.send_message(server, "second",
               request_id: "expired",
               deadline: System.monotonic_time(:millisecond) - 1
             )

    assert Server.health(server).pending_bytes > 0
    send(worker, :release)
    event = terminal("expired")
    assert event.type == :run_failed
    refute_receive :unexpected_io, 20
    assert %{pending_bytes: 0, pending: 0, status: :idle} = Server.health(server)
  end

  test "history threshold is exact and current input is checked again before queued IO" do
    owner = self()
    history = [Message.new_request([%Message.Part.User{content: "history"}])]
    bytes = :erlang.external_size(history)

    model = %Test{
      script: [
        fn _, _ ->
          send(owner, {:ready, self()})

          receive do
            :release -> String.duplicate("x", 7500)
          end
        end,
        fn _, _ ->
          send(owner, :unexpected_io)
          "bad"
        end
      ]
    }

    exact = server(model, max_history_bytes: bytes)

    assert {:ok, "first"} =
             Server.send_message(exact, "first", message_history: history, request_id: "first")

    # R3.4 now includes the current prompt/instructions in H. Exact prior history
    # is admitted by Server, but cannot be enlarged; it stays intact on failure.
    assert %Event{type: :run_failed} = terminal("first")
    assert Server.history(exact) == history
    refute_receive {:ready, _}, 20

    growing = server(model, max_history_bytes: 10_000)

    assert {:ok, "growing"} =
             Server.send_message(growing, "first",
               message_history: history,
               request_id: "growing"
             )

    assert_receive {:ready, worker}

    assert {:ok, "second"} =
             Server.send_message(growing, String.duplicate("q", 2000), request_id: "second")

    send(worker, :release)
    assert %Event{type: :run_failed} = terminal("second")
    refute_receive :unexpected_io, 20
    assert %{pending_bytes: 0} = Server.health(growing)
    assert :erlang.external_size(Server.history(growing)) <= 10_000
    assert length(Server.history(growing)) == 3
    below = server(%Test{}, max_history_bytes: bytes - 1)

    assert {:error, {:history_too_large, %{bytes: ^bytes}}} =
             Server.chat(below, "first", message_history: history)
  end

  defp blocked(owner) do
    fn _, _ ->
      send(owner, {:ready, self()})

      receive do
        :release -> "done"
      end
    end
  end

  defp terminal(id) do
    receive do
      {:event, %Event{request_id: ^id, type: type} = event}
      when type in [:run_finished, :run_failed, :server_request_cancelled] ->
        event
    after
      1000 -> flunk("missing terminal for #{id}")
    end
  end

  defp server(model, extra \\ []) do
    opts = Keyword.merge([agent: ExAgent.new(model: model), pubsub: {Events, self()}], extra)
    start_supervised!(Supervisor.child_spec({Server, opts}, id: make_ref(), restart: :temporary))
  end
end
