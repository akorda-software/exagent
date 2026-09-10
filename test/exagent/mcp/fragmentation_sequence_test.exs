Code.require_file("../../support/protocol_fragmentation.exs", __DIR__)

defmodule ExAgent.MCP.FragmentationSequenceTest do
  use ExUnit.Case, async: true

  alias ExAgent.MCP.Client
  alias ExAgent.Test.ProtocolFragmentation, as: Fragments

  test "timeout or caller death mid-UTF8 frame cannot redirect its late suffix to a new request" do
    for seed <- Fragments.seeds(), cancellation <- [:timeout, :death] do
      {client, ref} = client(seed)
      {caller, tag, old_id, entry} = pending(client, ref, cancellation == :death)
      old_wire = response(old_id, "tardío 😊")
      {utf8, _} = :binary.match(old_wire, "😊")
      {prefix, suffix} = :erlang.split_binary(old_wire, utf8 + 2)
      deliver(client, ref, Fragments.partition(prefix, seed))
      assert :sys.get_state(client).buffer == prefix

      case cancellation do
        :timeout ->
          send(client, {:timeout, entry.timer, {:request_timeout, old_id}})
          assert_receive {^tag, {:error, :timeout}}, 1_000

        :death ->
          # The trace is a barrier for Client's actual monitor DOWN, not merely
          # evidence that this test observed the same caller's death first.
          :erlang.trace(client, true, [:receive])
          Process.exit(caller, :kill)
          monitor = entry.monitor

          assert_receive {:trace, ^client, :receive,
                          {:DOWN, ^monitor, :process, ^caller, :killed}},
                         1_000

          :erlang.trace(client, false, [:receive])
      end

      clean(client, [entry])
      # Cancellation clears request ownership, not the shared framing carry.
      assert :sys.get_state(client).buffer == prefix
      {_, live_tag, live_id, live_entry} = pending(client, ref)
      assert live_id > old_id
      marker = make_ref()
      send(self(), {:unrelated, marker})

      wire = suffix <> notification() <> response(live_id, "vigente ñ😊") <> old_wire
      deliver(client, ref, Fragments.partition(wire, seed))
      send(client, {:timeout, entry.timer, {:request_timeout, old_id}})
      send(client, {:timeout, live_entry.timer, {:request_timeout, live_id}})

      assert_receive {^live_tag, {:ok, "vigente ñ😊"}}, 1_000
      clean(client, [entry, live_entry])
      assert %{ready: true, buffer: ""} = :sys.get_state(client)
      refute_received {^live_tag, _}
      refute_received {^tag, _}
      assert_receive {:unrelated, ^marker}, 0
      close(client)
    end
  end

  test "multisplit concatenated responses commit before UTF8 truncation or an oversized tail closes once" do
    for seed <- Fragments.seeds(), ending <- [:eof, :oversized_partial, :oversized_complete] do
      {client, ref} = client(seed)
      {_, first_tag, first_id, first_entry} = pending(client, ref)
      {_, second_tag, second_id, second_entry} = pending(client, ref)
      {_, waiting_tag, waiting_id, waiting_entry} = pending(client, ref)

      tail =
        case ending do
          :eof -> "{\"unfinished\":\"" <> <<0xF0, 0x9F>>
          :oversized_partial -> String.duplicate("x", 129)
          :oversized_complete -> String.duplicate("x", 129) <> "\n"
        end

      wire =
        notification() <>
          response(second_id, "segundo 😊") <> response(first_id, "primero á") <> tail

      deliver(client, ref, Fragments.partition(wire, seed))

      reason =
        if ending == :eof do
          assert :sys.get_state(client).buffer == tail
          send(client, {ref, :eof})
          :eof
        else
          {:frame_too_large, 128}
        end

      assert_receive {^second_tag, {:ok, "segundo 😊"}}, 1_000
      assert_receive {^first_tag, {:ok, "primero á"}}, 1_000
      assert_receive {^waiting_tag, {:error, ^reason}}, 1_000
      clean(client, [first_entry, second_entry, waiting_entry])
      assert %{ready: false, buffer: ""} = :sys.get_state(client)

      deliver(client, ref, Fragments.partition(response(waiting_id, "late 😊"), seed))
      send(client, {ref, :eof})
      send(client, {:timeout, waiting_entry.timer, {:request_timeout, waiting_id}})
      assert {:error, :not_ready} = Client.tools(client)
      refute_received {^first_tag, _}
      refute_received {^second_tag, _}
      refute_received {^waiting_tag, _}
      close(client)
    end
  end

  # Reuse Client's documented transport seam and the controlled-send pattern
  # from ClientTest; no external server, alternate client or protocol decoder.
  defp client(seed) do
    parent = self()
    ref = make_ref()

    send_fun = fn ^ref, data ->
      case Jason.decode!(IO.iodata_to_binary(data)) do
        %{"method" => "initialize", "id" => id} ->
          wire =
            Jason.encode!(%{
              "jsonrpc" => "2.0",
              "id" => id,
              "result" => %{"serverInfo" => %{"name" => "ñ😊"}}
            }) <> "\n"

          deliver(self(), ref, Fragments.partition(wire, seed))

        %{"id" => _} = request ->
          send(parent, {:outbound, self(), ref, request})

        _ ->
          :ok
      end
    end

    {:ok, client} =
      Client.start_link(transport: {send_fun, ref}, timeout: 5_000, max_frame_bytes: 128)

    on_exit(fn -> if Process.alive?(client), do: Client.close(client) end)
    {client, ref}
  end

  defp pending(client, ref, separate_caller? \\ false) do
    tag = make_ref()

    caller =
      if separate_caller? do
        spawn(fn ->
          send(client, {:"$gen_call", {self(), tag}, {:call_tool, "record", %{}}})

          receive do
            :stop -> :ok
          end
        end)
      else
        send(client, {:"$gen_call", {self(), tag}, {:call_tool, "record", %{}}})
        self()
      end

    if separate_caller?,
      do: on_exit(fn -> if Process.alive?(caller), do: Process.exit(caller, :kill) end)

    assert_receive {:outbound, ^client, ^ref, %{"id" => id}}, 1_000
    entry = Map.fetch!(:sys.get_state(client).pending, id)
    {caller, tag, id, entry}
  end

  defp response(id, text),
    do:
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => %{"content" => [%{"text" => text}]}
      }) <> "\n"

  defp notification, do: Jason.encode!(%{"jsonrpc" => "2.0", "method" => "noop"}) <> "\n"

  defp deliver(client, ref, chunks), do: Enum.each(chunks, &send(client, {ref, {:data, &1}}))

  defp clean(client, entries) do
    state = :sys.get_state(client)
    assert state.pending == %{}
    assert state.monitors == %{}
    assert {:monitors, []} = Process.info(client, :monitors)
    for entry <- entries, do: assert(Process.read_timer(entry.timer) == false)
  end

  defp close(client) do
    monitor = Process.monitor(client)
    assert :ok = Client.close(client)
    assert_receive {:DOWN, ^monitor, :process, ^client, :normal}, 1_000
  end
end
