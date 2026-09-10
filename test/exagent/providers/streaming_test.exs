defmodule ExAgent.Providers.StreamingTest do
  use ExUnit.Case, async: true

  alias ExAgent.Message.{Part, Response}
  alias ExAgent.Models.{OpenAI, Anthropic}
  alias ExAgent.Providers.{SSE, OpenAIChat}
  alias ExAgent.Providers.Anthropic, as: AnthropicProvider

  defp chunks(events) do
    events
    |> Enum.map(fn
      :done -> "data: [DONE]\r\n\r\n"
      map -> "data: " <> Jason.encode!(map) <> "\r\n\r\n"
    end)
    |> SSE.stream()
  end

  defp openai(delta, finish \\ nil) do
    %{
      "model" => "wire-model",
      "choices" => [%{"index" => 0, "delta" => delta, "finish_reason" => finish}]
    }
  end

  test "OpenAI assembles interleaved tool and name fragments, thinking and final usage" do
    model = %OpenAI{model: "configured", api_key: "offline"}

    events = [
      openai(%{"content" => "Before ", "reasoning_content" => "reason"}),
      openai(%{
        "tool_calls" => [
          %{
            "index" => 1,
            "id" => "b",
            "function" => %{"name" => "sec", "arguments" => "{\"b\":"}
          },
          %{
            "index" => 0,
            "id" => "a",
            "function" => %{"name" => "first", "arguments" => "{\"a\":"}
          }
        ]
      }),
      openai(
        %{
          "tool_calls" => [
            %{"index" => 0, "function" => %{"arguments" => "1}"}},
            %{"index" => 1, "function" => %{"name" => "ond", "arguments" => "2}"}}
          ],
          "content" => "tools"
        },
        "tool_calls"
      ),
      %{
        "choices" => [],
        "usage" => %{
          "prompt_tokens" => 5,
          "completion_tokens" => 3,
          "prompt_tokens_details" => %{"cached_tokens" => 4}
        }
      },
      :done
    ]

    assert [
             {:text_delta, "Before "},
             {:thinking_delta, "reason"},
             {:text_delta, "tools"},
             {:usage, _},
             {:response, response, ^model}
           ] = events |> chunks() |> OpenAIChat.adapt_stream(model) |> Enum.to_list()

    assert %Response{
             finish_reason: :tool_calls,
             model_name: "wire-model",
             parts: [
               %Part.Thinking{content: "reason"},
               %Part.Text{content: "Before tools"},
               %Part.ToolCall{tool_name: "first", tool_call_id: "a", args: "{\"a\":1}"},
               %Part.ToolCall{tool_name: "second", tool_call_id: "b", args: "{\"b\":2}"}
             ]
           } = response

    assert response.usage.input_tokens == 5
    assert response.usage.output_tokens == 3
    assert response.usage.details["cached_tokens"] == 4
  end

  test "OpenAI EOF, malformed JSON, bad tool JSON and provider error have no success terminal" do
    model = %OpenAI{model: "test", api_key: "offline"}

    sources = [
      chunks([openai(%{"content" => "partial"})]),
      SSE.stream(["data: bad\n\n"]),
      chunks([
        openai(
          %{
            "tool_calls" => [
              %{"index" => 0, "id" => "x", "function" => %{"name" => "g", "arguments" => "{"}}
            ]
          },
          "tool_calls"
        ),
        :done
      ]),
      chunks([
        openai(%{"content" => "partial"}),
        %{"error" => %{"message" => "overloaded"}},
        :done
      ]),
      chunks([openai(%{}), :done])
    ]

    for source <- sources do
      events = source |> OpenAIChat.adapt_stream(model) |> Enum.to_list()

      assert [{:error, %ExAgent.RequestError{provider: :openai, model: ^model}}] =
               Enum.filter(events, &match?({:error, _}, &1))

      refute Enum.any?(events, &match?({:response, _, _}, &1))
    end
  end

  test "terminal closes upstream without asking for another chunk" do
    parent = self()

    source =
      Stream.resource(
        fn -> 0 end,
        fn
          0 -> {[openai(%{"content" => "ok"}, "stop")], 1}
          1 -> {[:done], 2}
          2 -> flunk("adapter read past terminal")
        end,
        fn _ -> send(parent, :closed) end
      )

    model = %OpenAI{model: "m"}

    assert [{:text_delta, "ok"}, {:response, _, ^model}] =
             Enum.to_list(OpenAIChat.adapt_stream(source, model))

    assert_receive :closed
  end

  test "a decoder exception closes its latest suspended upstream exactly once" do
    parent = self()

    source =
      Stream.resource(fn -> 0 end, fn n -> {[n], n + 1} end, fn _ ->
        send(parent, :decoder_source_closed)
      end)

    stream =
      ExAgent.Providers.EventStream.transform(source, 0, fn
        0, _ -> {:cont, [:first], 1}
        1, _ -> raise "decoder failed"
      end)

    assert_raise RuntimeError, "decoder failed", fn -> Enum.to_list(stream) end
    assert_receive :decoder_source_closed
    refute_received :decoder_source_closed
  end

  defp start_message do
    %{
      "type" => "message_start",
      "message" => %{
        "model" => "claude-wire",
        "usage" => %{
          "input_tokens" => 9,
          "output_tokens" => 1,
          "cache_read_input_tokens" => 7,
          "cache_creation_input_tokens" => 2
        }
      }
    }
  end

  defp start_block(index, block),
    do: %{"type" => "content_block_start", "index" => index, "content_block" => block}

  defp delta(index, delta),
    do: %{"type" => "content_block_delta", "index" => index, "delta" => delta}

  defp stop(index), do: %{"type" => "content_block_stop", "index" => index}

  test "Anthropic preserves text at start, tool input fragments, thinking signatures and cache usage" do
    model = %Anthropic{model: "configured", api_key: "offline"}

    source =
      chunks([
        start_message(),
        start_block(0, %{"type" => "thinking", "thinking" => "think"}),
        delta(0, %{"type" => "thinking_delta", "thinking" => " more"}),
        delta(0, %{"type" => "signature_delta", "signature" => "sig"}),
        stop(0),
        start_block(1, %{"type" => "text", "text" => "initial"}),
        delta(1, %{"type" => "text_delta", "text" => " text"}),
        stop(1),
        start_block(2, %{
          "type" => "tool_use",
          "id" => "tool-1",
          "name" => "lookup",
          "input" => %{}
        }),
        delta(2, %{"type" => "input_json_delta", "partial_json" => "{\"city\":"}),
        delta(2, %{"type" => "input_json_delta", "partial_json" => "\"Madrid\"}"}),
        stop(2),
        %{
          "type" => "message_delta",
          "delta" => %{"stop_reason" => "tool_use"},
          "usage" => %{"output_tokens" => 15}
        },
        %{"type" => "message_stop"}
      ])

    events = source |> AnthropicProvider.adapt_stream(model) |> Enum.to_list()

    assert [
             {:usage, _},
             {:thinking_delta, "think"},
             {:thinking_delta, " more"},
             {:text_delta, "initial"},
             {:text_delta, " text"},
             {:usage, _},
             {:response, response, ^model}
           ] = events

    assert %Response{
             model_name: "claude-wire",
             finish_reason: :tool_calls,
             parts: [
               %Part.Thinking{content: "think more", signature: "sig"},
               %Part.Text{content: "initial text"},
               %Part.ToolCall{
                 tool_name: "lookup",
                 args: %{"city" => "Madrid"},
                 tool_call_id: "tool-1"
               }
             ]
           } = response

    assert response.usage.input_tokens == 9
    assert response.usage.output_tokens == 15

    assert response.usage.details == %{
             "cache_read_input_tokens" => 7,
             "cache_creation_input_tokens" => 2
           }
  end

  test "Anthropic accepts initial complete tool input and nested usage without losing stop_reason" do
    model = %Anthropic{model: "m"}

    source =
      chunks([
        start_message(),
        start_block(0, %{
          "type" => "tool_use",
          "id" => "id",
          "name" => "g",
          "input" => %{"x" => 1}
        }),
        stop(0),
        %{
          "type" => "message_delta",
          "delta" => %{"stop_reason" => "tool_use", "usage" => %{"output_tokens" => 4}}
        },
        %{"type" => "message_stop"}
      ])

    assert [{:usage, initial_usage}, {:usage, final_usage}, {:response, response, ^model}] =
             Enum.to_list(AnthropicProvider.adapt_stream(source, model))

    assert initial_usage.input_tokens == 9
    assert final_usage.input_tokens == 9
    assert final_usage.output_tokens == 4

    assert [%Part.ToolCall{args: %{"x" => 1}}] = response.parts
    assert response.finish_reason == :tool_calls
    assert response.usage.output_tokens == 4
  end

  test "Anthropic invalid ordering, partial JSON, provider error, and missing message_stop cannot succeed" do
    model = %Anthropic{model: "m"}

    streams = [
      [start_message()],
      [start_message(), delta(0, %{"type" => "text_delta", "text" => "x"})],
      [
        start_message(),
        start_block(0, %{"type" => "tool_use", "id" => "id", "name" => "g", "input" => %{}}),
        delta(0, %{"type" => "input_json_delta", "partial_json" => "{"}),
        stop(0)
      ],
      [
        start_message(),
        %{"type" => "error", "error" => %{"message" => "busy"}},
        %{"type" => "message_stop"}
      ],
      [
        start_message(),
        start_block(0, %{"type" => "text", "text" => "x"}),
        %{"type" => "message_stop"}
      ]
    ]

    for stream <- streams do
      events = stream |> chunks() |> AnthropicProvider.adapt_stream(model) |> Enum.to_list()

      assert [{:error, %ExAgent.RequestError{provider: :anthropic}}] =
               Enum.filter(events, &match?({:error, _}, &1))

      refute Enum.any?(events, &match?({:response, _, _}, &1))
    end
  end
end
