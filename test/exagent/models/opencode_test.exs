defmodule ExAgent.Models.OpenCodeTest do
  use ExUnit.Case, async: false
  alias ExAgent.Models.OpenCode
  alias ExAgent.Model

  setup do
    keys = ["OPENCODE_PLAN", "OPENCODE_API_KEY"]
    previous = Map.new(keys, &{&1, System.get_env(&1)})
    Enum.each(keys, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    :ok
  end

  test "default Go and explicit Zen have distinct endpoints" do
    go = OpenCode.new(model: "deepseek-v4-flash", api_key: "offline")
    zen = OpenCode.new(model: "deepseek-v4-flash", plan: :zen, api_key: "offline")
    assert {go.plan, go.base_url} == {:go, "https://opencode.ai/zen/go/v1"}
    assert {zen.plan, zen.base_url} == {:zen, "https://opencode.ai/zen/v1"}
    assert OpenCode.base_url(:go) == go.base_url
    assert OpenCode.base_url(:zen) == zen.base_url
  end

  test "environment fallback, normalized plans, explicit overrides and parity options" do
    System.put_env("OPENCODE_PLAN", "zen")
    System.put_env("OPENCODE_API_KEY", "offline-env")
    assert %OpenCode{plan: :zen, api_key: "offline-env"} = OpenCode.new(model: "m")

    assert %OpenCode{
             plan: :go,
             api_key: "explicit",
             base_url: "http://proxy/v1",
             extra_headers: [{"x-test", "1"}]
           } =
             OpenCode.new(
               model: "m",
               plan: " Go ",
               api_key: "explicit",
               base_url: "http://proxy/v1",
               extra_headers: [{"x-test", "1"}],
               app_title: "ignored",
               app_url: "ignored"
             )

    System.put_env("OPENCODE_PLAN", "")
    assert OpenCode.new(model: "m").plan == :go
    assert OpenCode.new(model: "m", plan: "ZEN").plan == :zen
  end

  test "invalid plans fail loudly for atoms, strings and environment" do
    for plan <- [:wrong, "zne", 5] do
      assert_raise ArgumentError, fn -> OpenCode.new(model: "m", plan: plan) end
    end

    System.put_env("OPENCODE_PLAN", "wrong")
    assert_raise ArgumentError, fn -> OpenCode.new(model: "m") end
    assert OpenCode.new(model: "m", plan: :zen).plan == :zen
  end

  test "identity, profile and resolver" do
    assert {:ok, %OpenCode{plan: :go, model: "slug"} = model} = Model.resolve("opencode:slug")
    assert Model.model_name(model) == "slug"
    assert Model.system(model) == "opencode"
    assert Model.profile(model).supports_tools
    refute Model.profile(model).supports_thinking
  end

  test "new streaming contract returns stateless final model and labels errors opencode" do
    model = OpenCode.new(model: "m", api_key: "offline")

    source = [
      %{"choices" => [%{"delta" => %{"content" => "ok"}, "finish_reason" => "stop"}]},
      :done
    ]

    assert [{:text_delta, "ok"}, {:response, _, ^model}] =
             Enum.to_list(ExAgent.Providers.OpenAIChat.adapt_stream(source, model))

    assert [{:error, %ExAgent.RequestError{provider: :opencode, reason: :missing_credentials}}] =
             Enum.to_list(
               OpenCode.request_stream(
                 %{model | api_key: ""},
                 [],
                 nil,
                 %ExAgent.ModelRequestParameters{}
               )
             )
  end
end
