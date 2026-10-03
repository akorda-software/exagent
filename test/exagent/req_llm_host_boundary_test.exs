defmodule ExAgent.ReqLLMHostBoundaryTest do
  use ExUnit.Case, async: true

  alias ReqLLM.{Context, Response}

  # This is the dependency boundary selected for the future Model adapter, not
  # acceptance of an ExAgent ReqLLM adapter. Only the transport is synthetic.
  @model %{provider: :openai, id: "exagent-host-fixture", base_url: "https://fixture.invalid/v1"}

  test "explicit off-catalog model performs one interaction and exposes canonical output" do
    owner = self()

    opts = transport(owner, completion(%{"role" => "assistant", "content" => "accepted"}))
    assert {:ok, model} = ReqLLM.model(@model)
    assert model.id == "exagent-host-fixture"
    assert {:ok, response} = ReqLLM.generate_text(model, "synthetic input", opts)

    assert_receive {:request, request}
    assert request.url.host == "fixture.invalid"
    assert request.url.path == "/v1/chat/completions"
    assert Req.Request.get_header(request, "authorization") == ["Bearer synthetic-not-a-key"]
    body = Jason.decode!(IO.iodata_to_binary(request.body))
    assert body["model"] == "exagent-host-fixture"
    assert [%{"role" => "user", "content" => "synthetic input"}] = body["messages"]

    assert %{type: :final_answer, text: "accepted", finish_reason: :stop} =
             Response.classify(response)

    assert %{input_tokens: 9, output_tokens: 2} = Response.usage(response)

    assert %{response_id: "fixture-response", model: "exagent-host-fixture"} =
             Response.call_metadata(response)

    assert [_ | _] = Response.output_items(response)
    refute_receive {:request, _}, 0
  end

  test "tool inspection and appending host results execute no callback or follow-up request" do
    owner = self()

    tool =
      ReqLLM.Tool.new!(
        name: "lookup",
        description: "Synthetic lookup",
        parameter_schema: [id: [type: :string, required: true]],
        callback: fn args ->
          send(owner, {:unauthorized_effect, args})
          {:ok, "must not run"}
        end
      )

    body =
      completion(
        %{
          "role" => "assistant",
          "content" => nil,
          "tool_calls" => [
            %{
              "id" => "call-exact",
              "type" => "function",
              "function" => %{"name" => "lookup", "arguments" => ~s({"id":"synthetic"})}
            }
          ]
        },
        "tool_calls"
      )

    assert {:ok, context} = Context.normalize("request a lookup")
    opts = Keyword.put(transport(owner, body), :tools, [tool])
    assert {:ok, response} = ReqLLM.generate_text(@model, context, opts)
    assert_receive {:request, request}

    assert [%{"function" => %{"name" => "lookup"}}] =
             Jason.decode!(IO.iodata_to_binary(request.body))["tools"]

    assert %{
             type: :tool_calls,
             tool_calls: [%{id: "call-exact", name: "lookup", arguments: %{"id" => "synthetic"}}]
           } = Response.classify(response)

    assert [call] = Response.tool_calls(response)
    assert call.id == "call-exact"
    result = Context.tool_result("call-exact", "lookup", "host-owned result")
    assert {:ok, continued} = Context.append_tool_exchange(context, response, [result])
    assert Enum.map(continued.messages, & &1.role) == [:user, :assistant, :tool]
    assert List.last(continued.messages).tool_call_id == "call-exact"
    assert {:error, _} = Context.append_tool_exchange(context, response, [])
    refute_receive {:unauthorized_effect, _}, 0
    refute_receive {:request, _}, 0
  end

  test "HTTP failure remains an error with transport retries explicitly disabled" do
    opts = transport(self(), %{"error" => %{"message" => "synthetic rejection"}}, 429)
    assert {:error, error} = ReqLLM.generate_text(@model, "synthetic failure", opts)
    assert %{status: 429} = error
    assert_receive {:request, _}
    refute_receive {:request, _}, 0
  end

  defp transport(owner, body, status \\ 200) do
    [
      api_key: "synthetic-not-a-key",
      max_retries: 0,
      req_http_options: [
        retry: false,
        adapter:
          ExAgent.Test.ReqTransport.bind(fn request ->
            send(owner, {:request, request})

            {request,
             Req.Response.new(
               status: status,
               headers: [{"content-type", "application/json"}],
               body: Jason.encode!(body)
             )}
          end)
      ]
    ]
  end

  defp completion(message, finish_reason \\ "stop") do
    %{
      "id" => "fixture-response",
      "model" => "exagent-host-fixture",
      "choices" => [%{"index" => 0, "message" => message, "finish_reason" => finish_reason}],
      "usage" => %{"prompt_tokens" => 9, "completion_tokens" => 2, "total_tokens" => 11}
    }
  end
end
