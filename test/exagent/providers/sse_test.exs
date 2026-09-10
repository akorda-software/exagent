defmodule ExAgent.Providers.SSETest do
  use ExUnit.Case, async: true
  alias ExAgent.Providers.SSE

  test "LF, CRLF and CR with every possible fragmentation boundary" do
    for newline <- ["\n", "\r\n", "\r"] do
      wire =
        ":comment#{newline}event: message#{newline}data: {#{newline}" <>
          "data: \"text\": \"á😊\"}#{newline}#{newline}" <>
          "data: [DONE]#{newline}#{newline}"

      for split <- 0..byte_size(wire) do
        {first, last} = :erlang.split_binary(wire, split)
        assert Enum.to_list(SSE.stream([first, last])) == [%{"text" => "á😊"}, :done]
      end

      bytes = for <<byte <- wire>>, do: <<byte>>
      assert Enum.to_list(SSE.stream(bytes)) == [%{"text" => "á😊"}, :done]
    end
  end

  test "malformed JSON, JSON non-object and truncated frames fail explicitly" do
    for wire <- ["data: nope\n\n", "data: []\n\n", "data:\n\n"] do
      assert [{:error, :invalid_sse_json}] = Enum.to_list(SSE.stream([wire]))
    end

    for wire <- ["data: {}", "data: {}\n", "data: {\"x\":"] do
      assert [{:error, :truncated_sse_frame}] = Enum.to_list(SSE.stream([wire]))
    end
  end

  test "clean EOF is separate from explicit DONE; duplicate terminals cannot succeed twice" do
    assert [%{}, :eof] = Enum.to_list(SSE.stream(["data: {}\n\n"]))
    assert [:eof] = Enum.to_list(SSE.stream([]))
    assert [:done] = Enum.to_list(SSE.stream(["data: [DONE]\n\ndata: [DONE]\n\n"]))
    assert [{:error, :offline}] = Enum.to_list(SSE.stream([{:error, :offline}]))
  end

  test "frame, incomplete buffer, and cumulative response limits are observable" do
    assert [{:error, {:stream_limit, :max_frame_bytes}}] =
             Enum.to_list(SSE.stream(["data: {}\n\n"], max_frame_bytes: 5))

    assert [{:error, {:stream_limit, :max_buffer_bytes}}] =
             Enum.to_list(SSE.stream(["data: ", "{}"], max_buffer_bytes: 7))

    assert [%{}, {:error, {:stream_limit, :max_response_bytes}}] =
             Enum.to_list(SSE.stream(["data: {}\n\n", "data: {}\n\n"], max_response_bytes: 15))

    assert [{:error, {:stream_limit, :max_frame_bytes}}] =
             Enum.to_list(SSE.stream([":" <> String.duplicate("x", 12)], max_frame_bytes: 10))
  end

  test "invalid options reject on enumeration" do
    stream = SSE.stream([], max_frame_bytes: -1)
    assert_raise ArgumentError, fn -> Enum.to_list(stream) end
  end
end
