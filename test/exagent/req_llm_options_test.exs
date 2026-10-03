defmodule ExAgent.ReqLLMOptionsTest do
  use ExUnit.Case, async: true
  alias ExAgent.{Message, Model, ModelSettings, ModelRequestParameters, RequestError}
  alias ExAgent.Models.ReqLLM, as: Adapter

  defp fixture(opts \\ []) do
    owner = self()

    transport = fn request ->
      send(owner, {:wire, request, Jason.decode!(IO.iodata_to_binary(request.body))})

      {request,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body:
           Jason.encode!(%{
             "id" => "options",
             "model" => "options-model",
             "choices" => [
               %{
                 "index" => 0,
                 "message" => %{"role" => "assistant", "content" => "ok"},
                 "finish_reason" => "stop"
               }
             ]
           })
       )}
    end

    Adapter.new(
      Keyword.merge(
        [
          model: %{provider: :openai, id: "options-model", base_url: "https://spec.invalid/v1"},
          api_key: "synthetic-instance-a",
          base_url: "https://instance.invalid/v1",
          http_options: [adapter: ExAgent.Test.ReqTransport.bind(transport)]
        ],
        opts
      )
    )
  end

  defp request(model, settings \\ nil),
    do:
      Model.request(
        model,
        [Message.new_request([%Message.Part.User{content: "synthetic"}])],
        settings,
        %ModelRequestParameters{}
      )

  test "nil settings preserve provider generation defaults and receive default60s" do
    assert {:ok, _, _} = request(fixture())
    assert_receive {:wire, req, body}
    assert req.options.receive_timeout == 60_000

    for key <- ~w(max_tokens temperature top_p presence_penalty frequency_penalty),
        do: refute(Map.has_key?(body, key))

    assert req.options.max_retries == 0
    assert req.options.redirect == false
  end

  test "HTTP instance receive default is honored, explicit ModelSettings timeout wins" do
    model = fixture()
    model = %{model | http_options: Keyword.put(model.http_options, :receive_timeout, 113)}
    assert {:ok, _, _} = request(model)
    assert_receive {:wire, req, _}
    assert req.options.receive_timeout == 113
    assert req.options.finch[:pool_timeout] == 113
    assert {:ok, _, _} = request(model, %ModelSettings{timeout: 227})
    assert_receive {:wire, req, _}
    assert req.options.receive_timeout == 227
    assert req.options.finch[:pool_timeout] == 227
  end

  test "run settings override agent values without erasing nonnil defaults; auth/gateway are isolated" do
    model = fixture()

    agent =
      ExAgent.new(
        model: model,
        model_settings: [temperature: 0.25, max_tokens: 31, timeout: 271]
      )

    settings = %ModelSettings{
      max_tokens: 17,
      top_p: 0.7,
      presence_penalty: -0.2,
      frequency_penalty: 0.1
    }

    assert {:ok, _} = ExAgent.run(agent, "synthetic", model_settings: settings)
    assert_receive {:wire, req, body}

    assert Map.take(body, ~w(max_tokens temperature top_p presence_penalty frequency_penalty)) ==
             %{
               "max_tokens" => 17,
               "temperature" => 0.25,
               "top_p" => 0.7,
               "presence_penalty" => -0.2,
               "frequency_penalty" => 0.1
             }

    assert req.options.receive_timeout == 271
    assert req.url.host == "instance.invalid"
    assert Req.Request.get_header(req, "authorization") == ["Bearer synthetic-instance-a"]
    other = %{model | api_key: "synthetic-instance-b", base_url: "https://other.invalid/v1"}
    assert {:ok, _, _} = request(other)
    assert_receive {:wire, req, _}
    assert req.url.host == "other.invalid"
    assert Req.Request.get_header(req, "authorization") == ["Bearer synthetic-instance-b"]
    assert {:ok, _, _} = request(%{model | base_url: nil})
    assert_receive {:wire, req, _}
    assert req.url.host == "spec.invalid"
    assert Req.Request.get_header(req, "authorization") == ["Bearer synthetic-instance-a"]
  end

  test "invalid typed settings and reserved options reject before IO without reflecting values" do
    model = fixture()

    for settings <- [
          %ModelSettings{max_tokens: 0},
          %ModelSettings{temperature: "synthetic-secret"},
          %ModelSettings{top_p: []},
          %ModelSettings{timeout: -1},
          %ModelSettings{timeout: "synthetic-secret"},
          %ModelSettings{extra: %{"model" => "override"}}
        ] do
      assert {:error, %RequestError{} = error} = request(model, settings)
      refute inspect(error) =~ "synthetic-secret"
    end

    for key <- [:headers, :auth, :retry, :redirect, :url, :body, :pool_timeout, :total_timeout] do
      assert {:error, %RequestError{}} =
               request(%{model | http_options: [{key, "synthetic-secret"}]})
    end

    for value <- [0, -1, :infinity, "synthetic-secret"] do
      assert {:error, %RequestError{reason: {:invalid_option, :total_timeout}} = error} =
               request(%{model | total_timeout: value})

      refute inspect(error) =~ "synthetic-secret"
    end

    refute_receive {:wire, _, _}, 0
  end

  test "canonical and projected system instructions are not duplicated from definition metadata" do
    model = fixture()
    assert {:ok, _} = ExAgent.run(ExAgent.new(model: model, instructions: "canonical rule"), "go")
    assert_receive {:wire, _, body}

    assert Enum.filter(body["messages"], &(&1["role"] == "system")) ==
             [%{"role" => "system", "content" => "canonical rule"}]

    history = [
      Message.new_request([
        %Message.Part.System{content: "projected rule"},
        %Message.Part.User{content: "go"}
      ])
    ]

    params = %ModelRequestParameters{
      instructions: [%Message.Part.System{content: "definition metadata"}]
    }

    assert {:ok, _, _} = Model.request(model, history, nil, params)
    assert_receive {:wire, _, body}

    assert Enum.filter(body["messages"], &(&1["role"] == "system")) ==
             [%{"role" => "system", "content" => "projected rule"}]
  end

  test "provider option values and foreign namespace are validated, not merged into wire extra" do
    model = fixture()

    for opts <- [
          [store: "synthetic-secret"],
          [anthropic_top_k: 3],
          [openai: [store: false]],
          [store: true, store: false],
          [api_key: "synthetic-secret"]
        ] do
      assert {:error, %RequestError{} = error} = request(%{model | provider_options: opts})
      refute inspect(error) =~ "synthetic-secret"
    end

    refute_receive {:wire, _, _}, 0
  end
end
