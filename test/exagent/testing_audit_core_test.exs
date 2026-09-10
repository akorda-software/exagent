defmodule ExAgent.TestingAuditCoreTest do
  use ExUnit.Case, async: true

  alias ExAgent.Message.Usage
  alias ExAgent.Test.TestingAuditCore

  test "external stream oracle accepts a complete result with provisional deltas" do
    result = result()

    assert TestingAuditCore.assert_successful_text_stream(
             [{:delta, "provisional preview"}, {:result, result}],
             "one two three four five",
             "test"
           ) == result
  end

  test "external stream oracle rejects failed, missing, duplicate and malformed terminals" do
    result = result()
    delta = {:delta, "one"}
    success = {:result, result}
    error = {:error, %ExAgent.RunError{reason: :truncated, partial: result}}

    for events <- [
          [delta, error],
          [delta],
          [delta, success, success],
          [delta, error, success],
          [delta, success, error],
          [success, delta],
          [success],
          [delta, {:result, %{result | output: "wrong answer"}}],
          [delta, {:result, %{result | status: :failed}}],
          [delta, {:result, %{result | usage_status: :partial}}],
          [delta, {:result, %{result | usage: %Usage{input_tokens: nil, output_tokens: 3}}}],
          [delta, {:result, %{result | usage: %Usage{input_tokens: 7, output_tokens: 0}}}],
          [delta, {:result, %{result | model: %ExAgent.Models.OpenAI{model: "wrong"}}}]
        ] do
      assert_raise ExUnit.AssertionError, fn ->
        TestingAuditCore.assert_successful_text_stream(events, "one two three four five", "test")
      end
    end
  end

  defp result do
    %{
      output: "one two three four five",
      status: :succeeded,
      usage_status: :complete,
      usage: %Usage{input_tokens: 7, output_tokens: 3},
      model: %ExAgent.Models.Test{}
    }
  end
end
