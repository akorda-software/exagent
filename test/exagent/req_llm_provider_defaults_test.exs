defmodule ExAgent.ReqLLMProviderDefaultsTest do
  use ExUnit.Case, async: false

  alias ExAgent.{Message, Model, ModelRequestParameters, RequestError}
  alias ExAgent.Models.ReqLLM, as: Adapter
  alias ExAgent.Test.MCPHTTPServer, as: HTTPServer

  @reason {:unsupported_options, :provider_defaults}

  setup do
    for provider <- [:openai, :openrouter] do
      previous = Application.fetch_env(:req_llm, provider)
      Application.delete_env(:req_llm, provider)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:req_llm, provider, value)
          :error -> Application.delete_env(:req_llm, provider)
        end
      end)
    end

    server = start_supervised!({HTTPServer, owner: self(), handler: &reply/1})
    %{server: server, url: HTTPServer.url(server)}
  end

  test "inherited routing, auth and other options reject before every execution and binding",
       ctx do
    for kind <- [:plain, :chat, :none, :router, :router_none],
        source <- [:configuration, :metadata],
        key <- [:provider_options, "provider_options"],
        defaults <- [
          %{"openrouter_provider" => %{"only" => ["synthetic-secret"]}},
          %{"api_key" => "synthetic-secret"},
          %{"openai_stream_transport" => "websocket"},
          "synthetic-secret"
        ] do
      model = model(kind, ctx.url)
      provider = model.model.provider

      model =
        case source do
          :configuration ->
            Application.put_env(:req_llm, provider, %{key => defaults})
            model

          :metadata ->
            put_in(model.model.extra[key], defaults)
        end

      assert_blocked(model)
      assert HTTPServer.journal(ctx.server) == []
      Application.delete_env(:req_llm, provider)
    end
  end

  test "keyword configuration and shadowed nonempty defaults also reject", ctx do
    model = model(:router, ctx.url)

    for config <- [
          [provider_options: [openrouter_provider: %{only: ["synthetic-secret"]}]],
          %{"provider_options" => %{"api_key" => "synthetic-secret"}, provider_options: []}
        ] do
      Application.put_env(:req_llm, :openrouter, config)
      assert_blocked(model)
    end

    assert HTTPServer.journal(ctx.server) == []
  end

  test "empty defaults preserve explicit routing, credentials and continuation binding", ctx do
    model = %{
      model(:router, ctx.url)
      | provider_options: [
          openrouter_provider: %{only: ["fixture"], allow_fallbacks: false},
          app_title: "fixture"
        ]
    }

    assert {:ok, binding} = Adapter.continuation_binding(model)

    for key <- [:provider_options, "provider_options"], value <- [nil, [], %{}] do
      Application.put_env(:req_llm, :openrouter, %{key => value})
      model = put_in(model.model.extra[key], value)
      assert Adapter.continuation_binding(model) == {:ok, binding}
      assert :ok = Model.validate_resume(model, messages(), nil, params())
      assert {:ok, response, _} = Model.request(model, messages(), nil, params())
      assert Message.Response.text(response) == "ok"

      events = model |> Model.request_stream(messages(), nil, params()) |> Enum.to_list()
      assert {:response, response, _} = List.last(events)
      assert Message.Response.text(response) == "ok"

      for request <- HTTPServer.journal(ctx.server) do
        assert request.headers["authorization"] == "Bearer synthetic-instance"
        assert request.json["provider"] == %{"only" => ["fixture"], "allow_fallbacks" => false}
      end
    end
  end

  defp assert_blocked(model) do
    assert {:error, %RequestError{reason: @reason} = error} =
             Model.request(model, messages(), nil, params())

    refute inspect(error) =~ "synthetic-secret"

    assert {:error, %RequestError{reason: @reason}} =
             Model.validate_resume(model, messages(), nil, params())

    assert {:error, @reason} = Adapter.continuation_binding(model)
    assert {:error, :invalid_model_continuation_binding} = Model.continuation_binding(model)

    if model.tool_profile do
      assert [{:error, %RequestError{reason: @reason}}] =
               model |> Model.request_stream(messages(), nil, params()) |> Enum.to_list()
    end
  end

  defp model(kind, url) do
    router? = kind in [:router, :router_none]
    none? = kind in [:none, :router_none]

    reasoning =
      if none?,
        do: %{
          enabled: true,
          effort: %{supported: true, values: ["none", "high"]},
          thinking: %{supported: true, disable_supported: true}
        },
        else: %{enabled: false}

    Adapter.new(
      model: %{
        provider: if(router?, do: :openrouter, else: :openai),
        id: "defaults-fixture",
        capabilities: %{tools: %{enabled: true}, reasoning: reasoning},
        extra: %{wire: %{protocol: "openai_chat"}}
      },
      tool_profile:
        cond do
          kind == :plain -> nil
          router? -> :openrouter_chat_tools_v1
          true -> :chat_tools_v1
        end,
      reasoning_mode: if(none?, do: :none),
      api_key: "synthetic-instance",
      base_url: url,
      total_timeout: 5000
    )
  end

  defp messages, do: [Message.new_request([%Message.Part.User{content: "synthetic"}])]
  defp params, do: %ModelRequestParameters{}

  defp reply(%{json: %{"model" => id} = request}) do
    if request["stream"] do
      frame = fn delta, finish ->
        "data: " <>
          Jason.encode!(%{
            id: "defaults",
            model: id,
            choices: [%{index: 0, delta: delta, finish_reason: finish}]
          }) <> "\n\n"
      end

      {200, [{"content-type", "text/event-stream"}],
       frame.(%{role: "assistant", content: "ok"}, nil) <>
         frame.(%{}, "stop") <> "data: [DONE]\n\n"}
    else
      body = %{
        id: "defaults",
        model: id,
        choices: [
          %{index: 0, message: %{role: "assistant", content: "ok"}, finish_reason: "stop"}
        ]
      }

      {200, [{"content-type", "application/json"}], Jason.encode!(body)}
    end
  end
end
