defmodule ExAgent.Models.OpenCodeTest do
  use ExUnit.Case, async: true

  alias ExAgent.Model
  alias ExAgent.Models.OpenCode

  describe "new/1 — plan & base URL" do
    test "Go is the default plan and uses the zen/go/v1 endpoint" do
      model = OpenCode.new(model: "deepseek-v4-flash")
      assert model.plan == :go
      assert model.base_url == "https://opencode.ai/zen/go/v1"
    end

    test "plan: :zen uses the zen/v1 endpoint (pay-as-you-go)" do
      model = OpenCode.new(model: "deepseek-v4-flash", plan: :zen)
      assert model.plan == :zen
      assert model.base_url == "https://opencode.ai/zen/v1"
    end

    test "OPENCODE_PLAN env overrides the default plan" do
      without_env("OPENCODE_PLAN", fn ->
        System.put_env("OPENCODE_PLAN", "zen")
        model = OpenCode.new(model: "deepseek-v4-flash")
        assert model.plan == :zen
        assert model.base_url == "https://opencode.ai/zen/v1"
      end)
    end

    test "explicit :base_url overrides the plan-derived URL" do
      model = OpenCode.new(model: "m", base_url: "https://proxy.example/v1")
      assert model.base_url == "https://proxy.example/v1"
    end
  end

  describe "new/1 — credentials & parity options" do
    test "api_key falls back to OPENCODE_API_KEY" do
      without_env("OPENCODE_API_KEY", fn ->
        System.put_env("OPENCODE_API_KEY", "sk-test-123")
        model = OpenCode.new(model: "deepseek-v4-flash")
        assert model.api_key == "sk-test-123"
      end)
    end

    test "explicit api_key overrides the env var" do
      System.put_env("OPENCODE_API_KEY", "sk-from-env")
      model = OpenCode.new(model: "glm-5.2", api_key: "sk-explicit")
      assert model.api_key == "sk-explicit"
    after
      System.delete_env("OPENCODE_API_KEY")
    end

    test "app_title/app_url are accepted (call-site parity with OpenRouter) and ignored" do
      model =
        OpenCode.new(
          model: "deepseek-v4-flash",
          app_title: "dragones",
          app_url: "https://dragones.test"
        )

      assert model.model == "deepseek-v4-flash"
      assert model.extra_headers == []
    end
  end

  describe "base_url/1" do
    test "go -> zen/go/v1, zen -> zen/v1" do
      assert OpenCode.base_url(:go) == "https://opencode.ai/zen/go/v1"
      assert OpenCode.base_url(:zen) == "https://opencode.ai/zen/v1"
    end
  end

  describe "behaviour callbacks" do
    test "model_name/1 returns the bare slug" do
      assert Model.model_name(%OpenCode{model: "deepseek-v4-flash"}) == "deepseek-v4-flash"
    end

    test "system/1 identifies the provider" do
      assert Model.system(%OpenCode{model: "x"}) == "opencode"
    end

    test "profile/1 advertises tools + json-schema output" do
      profile = Model.profile(%OpenCode{model: "x"})
      assert profile.supports_tools
      assert profile.supports_json_schema_output
    end
  end

  describe "Model.resolve/1" do
    test "\"opencode:<slug>\" builds a Go-plan OpenCode model by default" do
      assert {:ok, %OpenCode{model: "deepseek-v4-flash"} = model} =
               Model.resolve("opencode:deepseek-v4-flash")

      assert model.plan == :go
      assert model.base_url == "https://opencode.ai/zen/go/v1"
    end
  end

  defp without_env(key, fun) do
    previous = System.get_env(key)
    System.delete_env(key)

    try do
      fun.()
    after
      case previous do
        nil -> System.delete_env(key)
        value -> System.put_env(key, value)
      end
    end
  end
end
