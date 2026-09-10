defmodule ExAgent.Test.TestingAuditRuntime do
  @moduledoc false
  import ExUnit.Assertions
  alias ExAgent.Message
  alias ExAgent.Message.{Part, Usage}

  # Fixed application data, not expected values obtained from the codec under test.
  def history do
    timestamp = ~U[2026-09-10 08:00:00Z]

    [
      Message.new_request(
        [
          %Part.System{content: "be concise", dynamic_ref: "rules-v2"},
          %Part.User{content: "hi", timestamp: timestamp}
        ],
        timestamp: timestamp,
        run_id: "run-fixture",
        conversation_id: "conversation-fixture"
      ),
      Message.new_response(
        [
          %Part.Thinking{content: "synthetic thought", signature: "signature-fixture"},
          %Part.ToolCall{
            tool_name: "lookup",
            tool_call_id: "lookup-17",
            kind: :function,
            args: %{"record" => 17, "nested" => %{"enabled" => true}}
          }
        ],
        timestamp: timestamp,
        model_name: "fixture-model",
        finish_reason: :tool_calls,
        usage: %Usage{input_tokens: 3, output_tokens: 2, details: %{"cached_tokens" => 1}}
      ),
      Message.new_request(
        [
          %Part.ToolReturn{
            tool_name: "lookup",
            tool_call_id: "lookup-17",
            status: :succeeded,
            content: %{"record" => 17, "values" => [2, 7], "note" => "café"}
          }
        ],
        timestamp: timestamp
      ),
      Message.new_response([%Part.Text{content: "record 17: 9"}],
        timestamp: timestamp,
        model_name: "fixture-model",
        finish_reason: :stop,
        usage: %Usage{
          input_tokens: 5,
          output_tokens: 4,
          details: %{"output" => %{"reasoning_tokens" => 2}}
        }
      )
    ]
  end

  # Terminate the original child first: even if its EXIT is still queued in the
  # DynamicSupervisor, this prevents a later restart from escaping cleanup.
  def stop_restarted_agent(original, name) do
    stop_child(original)
    if current = Process.whereis(name), do: stop_child(current)
    assert Process.whereis(name) == nil
  end

  defp stop_child(pid) do
    monitor = Process.monitor(pid)

    case ExAgent.AgentSupervisor.stop_agent(pid) do
      :ok -> assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1000
      {:error, :not_found} -> Process.demonitor(monitor, [:flush])
    end
  end
end
