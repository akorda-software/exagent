defmodule ExAgent.RetentionReviewRegressionTest do
  use ExUnit.Case, async: true
  alias ExAgent.{ExecutionScope, Message, RunError, Server}
  alias ExAgent.Message.{Part, Request, Response, Usage}
  alias ExAgent.Server.Snapshot

  defmodule Model do
    @behaviour ExAgent.Model
    defstruct [:owner, mode: :ok]
    def model_name(_), do: "retention-review"
    def system(_), do: "test"

    def request(model, _, _, _) do
      send(model.owner, {:requested, self()})

      case model.mode do
        :crash -> Process.exit(self(), {:decoded_failure, String.duplicate("SOURCE-", 30_000)})
        :small_crash -> Process.exit(self(), :small_failure)
        :error -> {:error, :small_failure}
        :large_error -> {:error, String.duplicate("SOURCE-", 30_000)}
        :ok -> {:ok, %Response{parts: [%Part.Text{content: "ok"}], usage: usage()}, model}
      end
    end

    def request_stream(m, h, s, p) do
      Stream.map([:request], fn _ ->
        case request(m, h, s, p) do
          {:ok, r, next} -> {:response, r, next}
          error -> error
        end
      end)
    end

    defp usage, do: %Usage{input_tokens: 1, output_tokens: 2}
  end

  defmodule Capture do
    use ExAgent.Capability

    def before_model_request(_, state) do
      Process.put(:retention_review_scope, state.execution_scope.pid)
      send(state.model.owner, {:scope, state.execution_scope.pid})
      state
    end
  end

  defmodule Transform do
    use ExAgent.Capability

    def after_model_request(_, state) do
      response = %{List.last(state.messages) | parts: [%Part.Text{content: "transformed"}]}

      %{
        state
        | messages: List.replace_at(state.messages, -1, response),
          pending_response: %Response{
            parts: [%Part.Text{content: String.duplicate("SOURCE-", 30_000)}]
          }
      }
    end
  end

  defmodule Events do
    @behaviour ExAgent.PubSub
    def subscribe(_, _), do: :ok
    def broadcast(owner, _, event), do: send(owner, {:event, event}) && :ok
  end

  defp agent(mode, capabilities \\ [Capture]) do
    ExAgent.new(
      model: %Model{owner: self(), mode: mode},
      capabilities: capabilities,
      max_payload_bytes: 8192,
      max_history_bytes: 16384
    )
  end

  defp absent(term),
    do: refute(:binary.match(:erlang.term_to_binary(term), "SOURCE-") != :nomatch)

  for surface <- [:stream, :server], mode <- [:crash, :small_crash, :error, :large_error] do
    test "#{surface} #{mode} bounds terminal errors and cleans the scope" do
      assert_terminal(unquote(surface), unquote(mode))
    end
  end

  defp assert_terminal(surface, mode) do
    a = agent(mode)

    outcome =
      if surface == :stream do
        ExAgent.run_stream(a, "go") |> Enum.to_list() |> List.last()
      else
        server =
          start_supervised!(
            {Server,
             agent: a,
             pubsub: {Events, self()},
             agent_id: "retention-#{System.unique_integer([:positive])}"}
          )

        Server.chat(server, "go")
      end

    assert {:error, %RunError{reason: reason, partial: partial} = error} = outcome
    assert :erlang.external_size(reason) <= 4096
    assert partial.status == :failed
    # Abrupt death preserves the last acknowledged progress, which predates
    # admission here; returned errors include the reconciled request count.
    assert partial.request_count == if(mode in [:crash, :small_crash], do: 0, else: 1)
    assert partial.tool_calls == 0
    absent(error)

    if mode in [:crash, :large_error],
      do: assert(match?({:retention_limit_exceeded, _}, reason))

    if mode == :error, do: assert(reason == {:model_request_failed, :small_failure})

    if mode == :small_crash,
      do:
        assert(
          reason == {if(surface == :stream, do: :worker_exit, else: :crashed), :small_failure}
        )

    assert_receive {:requested, _}
    refute_receive {:requested, _}
    assert_receive {:scope, scope}
    monitor = Process.monitor(scope)
    assert_receive {:DOWN, ^monitor, :process, ^scope, _}, 1000
    check_events()
  end

  defp check_events do
    receive do
      {:event, event} ->
        absent(event)
        check_events()
    after
      0 -> :ok
    end
  end

  test "ledger retains bounded pricing errors and duplicates neither reprice nor recount" do
    owner = self()
    model = %Model{owner: owner}
    usage = %Usage{input_tokens: 1, output_tokens: 2}

    for {mode, reason} <- [
          {:return, :small_failure},
          {:return, String.duplicate("SOURCE-", 30_000)},
          {:raise, String.duplicate("SOURCE-", 30_000)},
          {:throw, String.duplicate("SOURCE-", 30_000)}
        ] do
      {:ok, scope} =
        ExecutionScope.start("pricing", model,
          estimate_cost: fn _ ->
            send(owner, :priced)

            case mode do
              :return -> {:error, reason}
              :raise -> raise reason
              :throw -> throw(reason)
            end
          end
        )

      on_exit(fn -> ExecutionScope.stop(scope) end)
      assert :ok = ExecutionScope.admit_request(scope, "one", model)
      assert {:error, _} = result = ExecutionScope.record_usage(scope, "one", usage, true)
      assert_receive :priced
      assert :erlang.external_size(result) <= 4096

      if reason == :small_failure,
        do: assert(result == {:error, {:cost_estimation_failed, :small_failure}})

      assert :sys.get_state(scope.pid).operations["one"].record_result == result
      assert ExecutionScope.record_usage(scope, "one", usage, true) == result
      assert {:ok, before} = ExecutionScope.snapshot(scope)
      assert {:ok, _} = ExecutionScope.request_snapshot(scope, "one")
      assert :ok = ExecutionScope.finish_request(scope, "one")
      assert {:ok, after_finish} = ExecutionScope.snapshot(scope)
      assert before == after_finish
      assert before.request_count == 1
      assert before.usage.input_tokens == 1
      assert before.usage.output_tokens == 2
      assert before.usage.accounting["cost"]["availability"] == "unavailable"
      absent(result)
      absent(before)
      refute_receive :priced
      monitor = Process.monitor(scope.pid)
      ExecutionScope.stop(scope)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}
    end
  end

  test "public pricing failure bounds ledger before progress and closes scope" do
    owner = self()

    observer = fn p ->
      if scope = Process.get(:retention_review_scope) do
        for {_, operation} <- :sys.get_state(scope).operations do
          send(owner, {:record_result, operation.record_result})
        end
      end

      send(owner, {:progress, p})
    end

    assert {:error, %RunError{reason: {:retention_limit_exceeded, _}, partial: p} = error} =
             ExAgent.run(agent(:ok), "go",
               on_progress: observer,
               estimate_cost: fn _ ->
                 send(owner, :priced)
                 {:error, String.duplicate("SOURCE-", 30_000)}
               end
             )

    assert p.request_count == 1
    assert p.usage.input_tokens == 1
    assert p.usage.output_tokens == 2
    assert p.cost_cents == nil
    assert p.usage.accounting["cost"]["availability"] == "unavailable"
    absent(error)
    assert_receive {:record_result, {:error, _} = recorded}
    assert :erlang.external_size(recorded) <= 4096
    absent(recorded)
    check_progress()
    assert_receive :priced
    refute_receive :priced
    assert_receive {:scope, scope}
    monitor = Process.monitor(scope)
    assert_receive {:DOWN, ^monitor, :process, ^scope, _}, 1000
  end

  test "hook response transformation remains valid but cannot forge internal pending data" do
    owner = self()

    for stream? <- [false, true] do
      assert {:ok, result} =
               ExAgent.run(agent(:ok, [Capture, Transform]), "go",
                 stream_text: stream?,
                 on_progress: fn p -> send(owner, {:progress, p}) end
               )

      assert result.output == "transformed"
      assert result.pending_response == nil
      assert result.request_count == 1
      absent(result)
      check_progress()
    end
  end

  defp check_progress do
    receive do
      {:progress, p} ->
        assert p.retention.data_bytes <= 2 * 16384 + 8192 + 65536
        absent(p)
        check_progress()
    after
      0 -> :ok
    end
  end

  test "omitted nil stays JSON null through snapshot4 while legacy content encoding remains" do
    marker = %{"version" => 1, "boundary" => "tool_return", "bytes" => 210_000, "limit" => 8192}

    omitted = %Part.ToolReturn{
      tool_name: "effect",
      tool_call_id: "confirmed",
      content: nil,
      status: :succeeded,
      payload_omitted: marker
    }

    legacy = %{omitted | payload_omitted: nil}
    history = [%Request{parts: [omitted, legacy]}]
    assert {:ok, [%{parts: [restored, old]}]} = Message.from_json(Message.to_json(history))
    assert restored == omitted
    assert old.content == "nil"
    snapshot = Snapshot.new(agent_id: "omission", history: history)
    assert {:ok, %{version: 4} = snapshot} = Snapshot.deserialize(Snapshot.serialize(snapshot))
    assert {:ok, [%{parts: [^omitted, _]}]} = Snapshot.messages(snapshot)
  end
end
