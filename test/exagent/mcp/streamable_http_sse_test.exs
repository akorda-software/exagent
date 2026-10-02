defmodule ExAgent.MCP.StreamableHTTPSSETest do
  use ExUnit.Case, async: true
  alias ExAgent.MCP.StreamableHTTP.{SSE, Message}
  alias ExAgent.MCP.StreamableHTTP, as: HTTP

  test "all byte partitions preserve CRLF, CR, UTF8 and multidata" do
    bytes = "\uFEFF:comment\r\nid: ignored\ndata: 雪\r\ndata: two\r\n\r\n"

    for split <- 0..byte_size(bytes) do
      {a, b} = :erlang.split_binary(bytes, split)
      assert {:ok, state, first} = SSE.feed(SSE.new(100, 100), a)
      assert {:ok, state, second} = SSE.feed(state, b)
      assert first ++ second == ["雪\ntwo"]
      assert :ok = SSE.finish(state)
    end
  end

  test "partial carry does not retain a large backing binary" do
    backing = String.duplicate("x", 100_000) <> "data: partial"
    part = binary_part(backing, 100_000, 13)
    assert {:ok, state, []} = SSE.feed(SSE.new(100, 100), part)
    assert state.line == "data: partial"
    assert :binary.referenced_byte_size(state.line) == byte_size(state.line)
    assert {:ok, _, ["雪"]} = SSE.feed(SSE.new(100, 100), "\uFEFFdata: 雪\n\n")
  end

  test "event-at-a-time oracle yields terminal before any suffix at every byte partition" do
    terminal = "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"text\":\"雪\"}}\r\n\r\n"

    for suffix <- [
          <<255, 10>>,
          String.duplicate(":", 257),
          "data: malformed\n\n",
          "data: " <> String.duplicate("x", 200) <> "\n\n"
        ] do
      bytes = terminal <> suffix

      for split <- 0..byte_size(bytes) do
        {a, b} = :erlang.split_binary(bytes, split)

        result =
          Enum.reduce_while([a, b], SSE.new(256, 128), fn chunk, state ->
            case SSE.next(state, chunk) do
              {:more, state} -> {:cont, state}
              {:event, _, event, _} -> {:halt, Message.decode(event, 1)}
            end
          end)

        assert result == {:result, %{"text" => "雪"}}
      end
    end
  end

  test "yielded remainder resumes CRLF and validates errors before the next event" do
    assert {:event, state, "one", rest} =
             SSE.next(SSE.new(256, 128), "data: one\r\n\r\ndata: two\r\n\r\n" <> <<255, 10>>)

    assert {:event, state, "two", rest} = SSE.next(state, rest)
    assert {:error, :invalid_sse_utf8} = SSE.next(state, rest)
    assert {:error, :sse_line_limit} = SSE.next(SSE.new(8, 128), "data: long\n\n")
    assert {:error, :sse_event_limit} = SSE.next(SSE.new(256, 2), "data: one\n\n")
  end

  test "line and event exact limits, plus one, partial retention, invalid UTF8 and EOF" do
    assert {:ok, _, ["123"]} = SSE.feed(SSE.new(9, 3), "data: 123\n\n")
    assert {:error, :sse_line_limit} = SSE.feed(SSE.new(8, 100), "data: 1234\n\n")
    assert {:error, :sse_event_limit} = SSE.feed(SSE.new(100, 3), "data: 1234\n\n")
    assert {:ok, _, ["1\n2"]} = SSE.feed(SSE.new(100, 3), "data: 1\ndata: 2\n\n")
    assert {:error, :sse_event_limit} = SSE.feed(SSE.new(100, 2), "data: 1\ndata: 2\n\n")
    assert {:ok, partial, []} = SSE.feed(SSE.new(9, 10), "data: 123")
    assert {:error, :incomplete_sse} = SSE.finish(partial)
    assert {:error, :sse_line_limit} = SSE.feed(partial, "45")
    assert {:error, :invalid_sse_utf8} = SSE.feed(SSE.new(100, 100), <<"data: ", 255, 10>>)
  end

  test "configuration rejects credentials in URL, reserved headers and injection without echoing values" do
    base = [url: "https://example.invalid/mcp", finch: __MODULE__.Pool]
    assert {:ok, _} = HTTP.config(base)

    for opts <- [
          [url: "https://user:secret@example.invalid/mcp"],
          [url: "https://example.invalid/mcp#fragment"],
          [headers: [{"MCP-Session-ID", "secret"}]],
          [headers: [{"Authorization", "secret\r\nx: y"}]],
          [max_controls: 0],
          [headers: [{"Content-Type", "application/json"}]],
          [max_header_bytes: 1, headers: [{"x", "y"}]]
        ] do
      assert {:error, :invalid_http_configuration} = HTTP.config(Keyword.merge(base, opts))
    end
  end

  test "JSONRPC requires exact IDs and sanitizes remote error payload" do
    assert {:error, :response_id_mismatch} =
             Message.decode(~s({"jsonrpc":"2.0","id":1.0,"result":{}}), 1)

    assert {:error, {:jsonrpc_error, -1}} =
             Message.decode(
               ~s({"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":"secret","data":"secret"}}),
               1
             )

    assert {:error, :invalid_jsonrpc} = Message.decode("secret-not-json", 1)
  end
end
