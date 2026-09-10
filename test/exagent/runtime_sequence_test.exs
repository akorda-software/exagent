defmodule ExAgent.RuntimeSequenceTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias ExAgent.{CheckpointError, Message, RunError, Server, Tool}
  alias ExAgent.Message.{Part, Usage}

  # All observations cross public Model/Tool/Store/PubSub boundaries. In
  # particular, the oracle neither reads Server.State nor reuses its queue code.
  defmodule Journal do
    @behaviour ExAgent.Store
    @behaviour ExAgent.PubSub

    def save_agent_snapshot(journal, snapshot) do
      mode = Agent.get_and_update(journal, &{&1.mode, %{&1 | saves: &1.saves ++ [snapshot]}})

      case mode do
        :ok ->
          bytes = ExAgent.Server.Snapshot.serialize(snapshot)
          Agent.update(journal, &%{&1 | bytes: bytes})

        :error ->
          {:error, :sequence_disk_full}

        :raise ->
          raise "sequence store unavailable"
      end
    end

    def load_agent_snapshot(journal, _) do
      case Agent.get(journal, & &1.bytes) do
        nil -> {:error, :not_found}
        bytes -> ExAgent.Server.Snapshot.deserialize(bytes)
      end
    end

    def save_session_snapshot(_, _), do: {:error, :unused}
    def load_session_snapshot(_, _), do: {:error, :not_found}
    def list_agent_snapshots(_), do: []
    def delete_agent_snapshot(_, _), do: :ok
    def subscribe(_, _), do: :ok

    def broadcast(journal, _, event) do
      Agent.update(journal, &%{&1 | events: &1.events ++ [event]})

      if event.type in [:run_finished, :run_failed, :server_request_cancelled] do
        send(Agent.get(journal, & &1.owner), {:terminal, event.request_id})
      end

      :ok
    end
  end

  defmodule EffectModel do
    @behaviour ExAgent.Model
    defstruct [:journal]

    def request(model, messages, _, _) do
      parts = Message.parts(messages)
      %Part.User{content: id} = Enum.find(Enum.reverse(parts), &match?(%Part.User{}, &1))
      answer? = match?(%Part.ToolReturn{}, List.last(parts))
      phase = if answer?, do: :answer, else: :tool
      Agent.update(model.journal, &%{&1 | requests: &1.requests ++ [{id, phase}]})

      content =
        if answer? do
          %{owner: owner, server: server} = Agent.get(model.journal, & &1)
          # The sync loop has already sent its tool-progress subtotal. A call
          # from the same producer establishes receipt before abort/worker DOWN.
          Server.health(server)
          send(owner, {:ready, id, self()})

          receive do
            :complete -> [%Part.Text{content: id}]
          end
        else
          [%Part.ToolCall{tool_name: "record", tool_call_id: id, args: %{"id" => id}}]
        end

      {:ok,
       Message.new_response(content,
         usage:
           if(answer?,
             do: %Usage{input_tokens: 5, output_tokens: 3},
             else: %Usage{input_tokens: 2, output_tokens: 1}
           ),
         model_name: "sequence"
       ), model}
    end

    def request_stream(model, messages, settings, params) do
      Stream.flat_map([:start], fn _ ->
        {:ok, response, next} = request(model, messages, settings, params)
        text = Message.Response.text(response)
        deltas = if text == "", do: [], else: [{:text_delta, text}]
        deltas ++ [{:response, response, next}]
      end)
    end

    def model_name(_), do: "sequence"
    def system(_), do: "test"
  end

  for seed <- [7_031, 28_042, 91_117] do
    @tag sequence_seed: seed
    test "bounded Server sequence seed #{seed}" do
      :rand.seed(:exsss, {unquote(seed), 17, 29})
      ctx = fixture()
      expected = empty_model()
      assert_state(ctx, expected)

      {ctx, expected} =
        Enum.reduce(1..64, {ctx, expected}, fn step, {ctx, expected} ->
          command = choose_command(expected)
          next = transition(ctx, expected, command, "#{unquote(seed)}-#{step}")
          {ctx, expected} = next
          assert_state(ctx, expected, {unquote(seed), step, command})
          next
        end)

      # At most one dirty revision plus an active run and two queued entries.
      {ctx, expected} = settle(ctx, expected, 4)
      assert expected.active == nil
      assert expected.queue == []
      assert expected.dirty == false
      assert_state(ctx, expected)
    end
  end

  test "owner loss after an effect restores only the last confirmed revision and drops volatile queue" do
    ctx = fixture()
    {ctx, expected} = transition(ctx, empty_model(), :send_message, "confirmed")
    {ctx, expected} = transition(ctx, expected, {:finish, :complete, :ok}, nil)
    {ctx, expected} = transition(ctx, expected, :send_message, "unconfirmed-effect")
    {ctx, expected} = transition(ctx, expected, :steer, "volatile-tail")
    assert_state(ctx, expected)
    worker_ref = Process.monitor(ctx.worker)
    owner_ref = Process.monitor(ctx.server)
    Process.exit(ctx.server, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, _, :killed}, 1000
    assert_receive {:DOWN, ^worker_ref, :process, _, :killed}, 1000

    before = Agent.get(ctx.journal, & &1)
    restored = start_server(ctx.journal, ctx.agent, ctx.id)
    assert :ok = Server.checkpoint(restored)

    assert %{status: :idle, pending: 0, persistence: %{revision: 1, status: :confirmed}} =
             Server.health(restored)

    assert history(Server.history(restored)) == completed_history([{"confirmed", :complete}])
    assert_usage(Server.usage(restored), [{"confirmed", :complete}], "restored")
    assert_response_usage(Server.history(restored), [{"confirmed", :complete}], "restored")
    after_restore = Agent.get(ctx.journal, & &1)
    assert after_restore.bytes == before.bytes
    assert_snapshot_json(after_restore.bytes, [{"confirmed", :complete}], ctx.id, "restored")
    assert after_restore.requests == before.requests
    assert after_restore.effects == ["confirmed", "unconfirmed-effect"]
    assert after_restore.saves == before.saves
    assert terminals(after_restore.events) == terminals(before.events)
    assert Enum.map(terminals(before.events), &elem(&1, 0)) == ["confirmed"]
  end

  defp fixture do
    owner = self()

    journal =
      start_supervised!(
        {Agent,
         fn ->
           %{
             owner: owner,
             server: nil,
             mode: :ok,
             bytes: nil,
             requests: [],
             effects: [],
             saves: [],
             events: []
           }
         end}
      )

    tool =
      Tool.new(
        name: "record",
        takes_ctx: false,
        parameters_json_schema: %{
          "type" => "object",
          "properties" => %{"id" => %{"type" => "string"}},
          "required" => ["id"]
        },
        call: fn %{"id" => id} ->
          Agent.update(journal, &%{&1 | effects: &1.effects ++ [id]})
          {:ok, "recorded:" <> id}
        end
      )

    agent = ExAgent.new(model: %EffectModel{journal: journal}, tools: [tool])
    id = "sequence-#{System.unique_integer([:positive])}"
    server = start_server(journal, agent, id)
    %{server: server, journal: journal, agent: agent, id: id, worker: nil}
  end

  defp start_server(journal, agent, id) do
    server =
      start_supervised!(
        Supervisor.child_spec(
          {Server,
           agent: agent,
           agent_id: id,
           max_pending: 2,
           store: {Journal, journal},
           pubsub: {Journal, journal}},
          id: make_ref(),
          restart: :temporary
        )
      )

    Agent.update(journal, &%{&1 | server: server})
    server
  end

  defp empty_model do
    %{active: nil, queue: [], started: [], completed: [], terminals: [], saves: [], dirty: false}
  end

  defp choose_command(%{dirty: true}) do
    Enum.random([
      :chat,
      :send_message,
      :steer,
      :stream,
      :reset,
      :set_model,
      {:retry, :error},
      {:retry, :raise},
      {:retry, :ok},
      {:retry, :ok}
    ])
  end

  defp choose_command(%{active: nil}),
    do: Enum.random([:chat, :send_message, :steer, :stream, {:retry, :ok}])

  defp choose_command(%{active: {_, kind}}) do
    endings = for mode <- [:ok, :error, :raise], do: {:finish, :complete, mode}
    # Streaming worker ownership is already covered independently. Abrupt loss
    # here targets the Server-owned sync worker, whose readiness pid is exact.
    endings =
      if kind == :stream,
        do: endings,
        else:
          endings ++
            [
              {:finish, :abort, :error},
              {:finish, :crash, :raise},
              {:finish, :abort, :ok}
            ]

    Enum.random([:chat, :stream, :send_message, :steer, {:retry, :ok}] ++ endings)
  end

  defp transition(ctx, %{dirty: true} = expected, command, id)
       when command in [:chat, :send_message, :steer, :stream, :reset, :set_model] do
    revision = length(expected.completed)

    result =
      case command do
        :reset -> Server.reset(ctx.server)
        :set_model -> Server.set_model(ctx.server, ctx.agent.model)
        _ -> apply(Server, command, [ctx.server, id, [request_id: id]])
      end

    assert {:error, %CheckpointError{revision: ^revision}} = result
    {ctx, expected}
  end

  defp transition(ctx, expected, command, id)
       when command in [:chat, :send_message, :steer, :stream] do
    cond do
      expected.active == nil ->
        if command == :chat do
          owner = self()

          start_supervised!(
            Supervisor.child_spec(
              {Task,
               fn ->
                 send(owner, {:chat_reply, id, Server.chat(ctx.server, id, request_id: id)})
               end},
              id: make_ref()
            )
          )
        else
          assert {:ok, ^id} = apply(Server, command, [ctx.server, id, [request_id: id]])
        end

        expected = activate(expected, {id, command})
        {ready(ctx, id), expected}

      command in [:chat, :stream] ->
        assert {:error, :busy} = apply(Server, command, [ctx.server, id, [request_id: id]])
        {ctx, expected}

      length(expected.queue) == 2 ->
        assert {:error, :queue_full} = apply(Server, command, [ctx.server, id, [request_id: id]])
        {ctx, expected}

      true ->
        assert {:ok, ^id} = apply(Server, command, [ctx.server, id, [request_id: id]])
        entry = {id, command}

        queue =
          if command == :steer, do: [entry | expected.queue], else: expected.queue ++ [entry]

        {ctx, %{expected | queue: queue}}
    end
  end

  defp transition(ctx, expected, {:retry, mode}, _) do
    Agent.update(ctx.journal, &%{&1 | mode: mode})
    result = Server.checkpoint(ctx.server)

    cond do
      expected.active != nil ->
        assert result == {:error, :busy}
        {ctx, expected}

      not expected.dirty ->
        assert result == :ok
        {ctx, expected}

      true ->
        revision = length(expected.completed)

        if mode == :ok,
          do: assert(result == :ok),
          else: assert({:error, %CheckpointError{revision: ^revision}} = result)

        expected = %{expected | saves: expected.saves ++ [revision], dirty: mode != :ok}
        maybe_drain(ctx, expected)
    end
  end

  defp transition(ctx, expected, {:finish, outcome, mode}, _) do
    {id, kind} = expected.active
    Agent.update(ctx.journal, &%{&1 | mode: mode})

    case outcome do
      :complete -> send(ctx.worker, :complete)
      :abort -> assert :ok = Server.abort(ctx.server)
      :crash -> Process.exit(ctx.worker, :kill)
    end

    assert_receive {:terminal, ^id}, 1000

    if kind == :chat do
      assert_receive {:chat_reply, ^id, reply}, 1000

      case {mode, outcome} do
        {:ok, :complete} -> assert {:ok, %{output: ^id}} = reply
        {:ok, _} -> assert {:error, %RunError{}} = reply
        {_, :complete} -> assert {:error, %CheckpointError{result: {:ok, %{output: ^id}}}} = reply
        {_, _} -> assert {:error, %CheckpointError{result: {:error, %RunError{}}}} = reply
      end
    end

    revision = length(expected.completed) + 1

    type =
      cond do
        outcome == :abort -> :server_request_cancelled
        outcome == :complete and mode == :ok -> :run_finished
        true -> :run_failed
      end

    persistence = if mode == :ok, do: :confirmed, else: :unconfirmed

    expected = %{
      expected
      | active: nil,
        dirty: mode != :ok,
        completed: expected.completed ++ [{id, outcome}],
        saves: expected.saves ++ [revision],
        terminals: expected.terminals ++ [{id, type, revision, persistence}]
    }

    maybe_drain(%{ctx | worker: nil}, expected)
  end

  defp activate(expected, {id, _} = active),
    do: %{expected | active: active, started: expected.started ++ [id]}

  defp maybe_drain(ctx, %{dirty: false, queue: [entry | rest]} = expected) do
    expected = activate(%{expected | queue: rest}, entry)
    {ready(ctx, elem(entry, 0)), expected}
  end

  defp maybe_drain(ctx, expected), do: {ctx, expected}

  defp ready(ctx, id) do
    assert_receive {:ready, ^id, worker}, 1000
    %{ctx | worker: worker}
  end

  defp settle(ctx, %{dirty: false, active: nil} = expected, _), do: {ctx, expected}
  defp settle(_, _, 0), do: flunk("bounded sequence failed to settle")

  defp settle(ctx, expected, budget) do
    command = if expected.dirty, do: {:retry, :ok}, else: {:finish, :complete, :ok}
    {ctx, expected} = transition(ctx, expected, command, nil)
    assert_state(ctx, expected)
    settle(ctx, expected, budget - 1)
  end

  defp assert_state(ctx, expected, trace \\ :final) do
    health = Server.health(ctx.server)
    label = inspect(trace)
    assert health.status == if(expected.active, do: :running, else: :idle), label
    assert health.pending == length(expected.queue), label
    assert health.persistence.revision == length(expected.completed), label

    assert health.persistence.status == if(expected.dirty, do: :unconfirmed, else: :confirmed),
           label

    assert history(Server.history(ctx.server)) == completed_history(expected.completed), label
    assert_response_usage(Server.history(ctx.server), expected.completed, label)
    assert_usage(Server.usage(ctx.server), expected.completed, label)

    observed = Agent.get(ctx.journal, & &1)
    assert observed.effects == expected.started, label

    assert observed.requests == Enum.flat_map(expected.started, &[{&1, :tool}, {&1, :answer}]),
           label

    assert Enum.map(observed.saves, & &1.revision) == expected.saves, label
    assert terminals(observed.events) == expected.terminals, label
    seqs = Enum.map(observed.events, & &1.seq)
    assert seqs == Enum.to_list(1..length(seqs)//1), label

    if observed.saves != [] do
      attempted = List.last(observed.saves)
      assert {:ok, messages} = ExAgent.Server.Snapshot.messages(attempted), label
      assert history(messages) == completed_history(expected.completed), label
      assert_response_usage(messages, expected.completed, label)
      assert_usage(ExAgent.Server.Snapshot.usage_struct(attempted), expected.completed, label)
      assert_json_history(attempted.message_history, expected.completed, label)
    end

    if observed.bytes do
      {:ok, saved} = ExAgent.Server.Snapshot.deserialize(observed.bytes)
      {:ok, messages} = ExAgent.Server.Snapshot.messages(saved)

      confirmed =
        if expected.dirty, do: length(expected.completed) - 1, else: length(expected.completed)

      assert saved.revision == confirmed, label

      completed = Enum.take(expected.completed, confirmed)
      assert history(messages) == completed_history(completed), label
      assert_response_usage(messages, completed, label)
      assert_usage(ExAgent.Server.Snapshot.usage_struct(saved), completed, label)
      assert_snapshot_json(observed.bytes, completed, ctx.id, label)
    end
  end

  defp terminals(events) do
    for event <- events,
        event.type in [:run_finished, :run_failed, :server_request_cancelled] do
      {event.request_id, event.type, event.payload.persistence.revision,
       event.payload.persistence.status}
    end
  end

  defp history(messages) do
    Enum.map(Message.parts(messages), fn
      %Part.User{content: id} ->
        {:user, id}

      %Part.ToolCall{tool_call_id: id, tool_name: name, args: args, kind: kind} ->
        {:call, id, name, args, kind}

      %Part.ToolReturn{tool_call_id: id, tool_name: name, content: content, status: status} ->
        {:effect, id, name, content, status}

      %Part.Text{content: id} ->
        {:answer, id}
    end)
  end

  defp completed_history(completed) do
    Enum.flat_map(completed, fn {id, outcome} ->
      parts = [
        {:user, id},
        {:call, id, "record", %{"id" => id}, :function},
        {:effect, id, "record", "recorded:" <> id, :succeeded}
      ]

      if outcome == :complete, do: parts ++ [{:answer, id}], else: parts
    end)
  end

  # Distinct fixture budgets detect input/output swaps and a lost final response.
  defp expected_response_usage(completed) do
    Enum.flat_map(completed, fn {_, outcome} ->
      if outcome == :complete, do: [{2, 1}, {5, 3}], else: [{2, 1}]
    end)
  end

  defp expected_usage(completed) do
    Enum.reduce(expected_response_usage(completed), {0, 0}, fn {i, o}, {isum, osum} ->
      {isum + i, osum + o}
    end)
  end

  defp assert_usage(usage, completed, label),
    do: assert({usage.input_tokens, usage.output_tokens} == expected_usage(completed), label)

  defp assert_response_usage(messages, completed, label) do
    actual =
      for %Message.Response{usage: usage} <- messages,
          do: {usage.input_tokens, usage.output_tokens}

    assert actual == expected_response_usage(completed), label
  end

  # Read the JSON with Jason alone, independently of Snapshot/Message decoders.
  # Ignore nondeterministic timestamps, but retain every fixture payload field.
  defp assert_snapshot_json(bytes, completed, id, label) do
    raw = Jason.decode!(bytes)
    assert raw["agent_id"] == id, label
    assert raw["revision"] == length(completed), label
    {input, output} = expected_usage(completed)

    assert Map.take(raw["usage"], ["input_tokens", "output_tokens"]) ==
             %{"input_tokens" => input, "output_tokens" => output},
           label

    assert_json_history(raw["message_history"], completed, label)
  end

  defp assert_json_history(binary, completed, label) do
    raw = Jason.decode!(binary)
    keys = ~w(__type__ tool_call_id tool_name args kind content status)
    actual = for message <- raw, part <- message["parts"], do: Map.take(part, keys)

    expected =
      Enum.flat_map(completed, fn {id, outcome} ->
        parts = [
          %{"__type__" => "user", "content" => id},
          %{
            "__type__" => "tool_call",
            "tool_call_id" => id,
            "tool_name" => "record",
            "args" => %{"id" => id},
            "kind" => "function"
          },
          %{
            "__type__" => "tool_return",
            "tool_call_id" => id,
            "tool_name" => "record",
            "content" => "recorded:" <> id,
            "status" => "succeeded"
          }
        ]

        if outcome == :complete,
          do: parts ++ [%{"__type__" => "text", "content" => id}],
          else: parts
      end)

    assert actual == expected, label

    usage =
      for %{"__type__" => "response", "usage" => u} <- raw,
          do: {u["input_tokens"], u["output_tokens"]}

    assert usage == expected_response_usage(completed), label
  end
end
