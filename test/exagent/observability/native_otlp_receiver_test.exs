defmodule ExAgent.Observability.NativeOTLPReceiverTest do
  # Fault propagation terminates a GenServer through the global Logger; serialize
  # with the other OTLP lifecycle tests rather than racing async failure logging.
  use ExUnit.Case, async: false
  alias ExAgent.Test.NativeOTLPReceiver, as: Receiver

  defp connect(receiver) do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, Receiver.port(receiver), [:binary, active: false])

    on_exit(fn -> :gen_tcp.close(socket) end)
    socket
  end

  defp registration(acceptor, receiver) do
    assert_receive {:trace, ^acceptor, :send, message, ^receiver}

    case message do
      {:handler, handler} -> handler
      {:"$gen_call", _, {:handler, handler}} -> handler
    end
  end

  test "registration is acknowledged before HTTP processing; normal completion keeps receiver alive" do
    {:ok, receiver} = Receiver.start_link()
    acceptor = :sys.get_state(receiver).acceptor
    port = Receiver.port(receiver)
    :erlang.trace(acceptor, true, [:send])
    :sys.suspend(receiver)

    handler =
      try do
        {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
        on_exit(fn -> :gen_tcp.close(socket) end)
        :ok = :gen_tcp.send(socket, "POST /v1/traces HTTP/1.1\r\ncontent-length: 1\r\n\r\nx")
        handler = registration(acceptor, receiver)
        # The registration has reached a deliberately suspended owner. HTTP cannot
        # become visible (and complete the handler) before ownership is established.
        refute_receive {:native_otlp_request, ^receiver, ^handler, _}, 100
        handler
      after
        :sys.resume(receiver)
        :erlang.trace(acceptor, false, [:send])
      end

    assert_receive {:native_otlp_request, ^receiver, ^handler, %{body: "x"}}
    assert receiver in elem(Process.info(handler, :links), 1)
    monitor = Process.monitor(handler)
    Receiver.reply(handler, 200)
    assert_receive {:native_otlp_replied, ^handler, :ok}
    assert_receive {:DOWN, ^monitor, :process, ^handler, :normal}
    assert is_integer(Receiver.port(receiver))
    Receiver.stop(receiver)
  end

  test "owner death during registration cleans the handler and socket" do
    {:ok, receiver} = Receiver.start_link()
    Process.unlink(receiver)
    acceptor = :sys.get_state(receiver).acceptor
    port = Receiver.port(receiver)
    :erlang.trace(acceptor, true, [:send])
    :sys.suspend(receiver)
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    handler = registration(acceptor, receiver)
    monitor = Process.monitor(handler)
    acceptor_monitor = Process.monitor(acceptor)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^handler, _}
    assert_receive {:DOWN, ^acceptor_monitor, :process, ^acceptor, _}
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
    :gen_tcp.close(socket)
  end

  test "a registered handler failure still propagates instead of being ignored" do
    {:ok, receiver} = Receiver.start_link()
    Process.unlink(receiver)
    socket = connect(receiver)
    :ok = :gen_tcp.send(socket, "POST /v1/traces HTTP/1.1\r\ncontent-length: 1\r\n\r\nx")
    assert_receive {:native_otlp_request, ^receiver, handler, _}
    monitor = Process.monitor(receiver)
    Process.exit(handler, :synthetic_handler_failure)

    assert_receive {:DOWN, ^monitor, :process, ^receiver,
                    {:fixture_exit, :synthetic_handler_failure}}

    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1000)
  end
end
