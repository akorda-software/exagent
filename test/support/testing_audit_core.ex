defmodule ExAgent.Test.TestingAuditCore do
  @moduledoc false
  import ExUnit.Assertions

  # Shared by external acceptance and its offline positive/negative controls.
  # Deltas are provisional: only the terminal output is compared to the answer.
  def assert_successful_text_stream(events, expected_output, model_name) do
    {deltas, terminal} = Enum.split_while(events, &match?({:delta, _}, &1))
    assert [{:result, result}] = terminal
    assert Enum.all?(deltas, fn {:delta, text} -> is_binary(text) end)
    assert Enum.map_join(deltas, fn {:delta, text} -> text end) != ""
    assert result.output == expected_output
    assert result.status == :succeeded
    assert result.usage_status == :complete
    assert is_integer(result.usage.input_tokens) and result.usage.input_tokens > 0
    assert is_integer(result.usage.output_tokens) and result.usage.output_tokens > 0
    assert ExAgent.Model.model_name(result.model) == model_name
    result
  end

  # The mock owns no Port. Its lifetime belongs to the creating test instead.
  # Register cleanup before returning the PID, including for failed assertions.
  def start_owned_mock(handle_sent) do
    owner = self()
    pid = spawn(fn -> mock_loop(Process.monitor(owner), handle_sent) end)
    ExUnit.Callbacks.on_exit(fn -> stop_and_assert_down(pid) end)
    pid
  end

  def stop_and_assert_down(pid) do
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
  end

  defp mock_loop(owner_monitor, handle_sent) do
    receive do
      {:sent, _, _} = sent ->
        handle_sent.(sent)
        mock_loop(owner_monitor, handle_sent)

      {:DOWN, ^owner_monitor, :process, _, _} ->
        :ok
    end
  end
end
