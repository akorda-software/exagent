defmodule ExAgent.Models.OpenCode do
  @moduledoc """
  [OpenCode Zen / Go](https://opencode.ai/docs/zen) provider.

  OpenCode's hosted gateway speaks the OpenAI Chat Completions wire format, so
  it reuses `ExAgent.Providers.OpenAIChat`. There are **two plans** that share
  the same host but use *different* base URLs — picking the wrong one is the
  classic gotcha (a Go key against the Zen endpoint returns `CreditsError`):

    * **Go** (`:go`, the default) — flat-rate subscription ($10/mo) with rolling
      quotas (per 5h / week / month). Endpoint: `https://opencode.ai/zen/go/v1`.
      Requests report `"cost": "0"`.
    * **Zen** (`:zen`) — pay-as-you-go, billed per token from a prepaid balance.
      Endpoint: `https://opencode.ai/zen/v1`.

  Both share the same model ids and auth scheme (`Bearer` API key), so the only
  difference is the base URL — selected by the `:plan` option (or
  `OPENCODE_PLAN`). The same `OPENCODE_API_KEY` env var feeds both; just make
  sure the plan matches the key you pasted.

  Model ids are the bare Zen slugs (NOT the `opencode/<id>` form used in the
  OpenCode TUI config). For example, the OpenRouter slug
  `deepseek/deepseek-v4-flash` becomes `deepseek-v4-flash` here:

      # Go subscription (default):
      model = ExAgent.Models.OpenCode.new(model: "deepseek-v4-flash")

      # Zen pay-as-you-go:
      model = ExAgent.Models.OpenCode.new(model: "deepseek-v4-flash", plan: :zen)

  The full model catalogue (DeepSeek, GLM, Kimi, Qwen, MiniMax, plus the free
  tiers) is listed at `https://opencode.ai/zen/v1/models`.
  """
  @behaviour ExAgent.Model

  defstruct [:model, :api_key, :base_url, plan: :go, extra_headers: []]

  @type plan :: :go | :zen
  @type t :: %__MODULE__{
          model: String.t(),
          api_key: String.t() | nil,
          base_url: String.t() | nil,
          plan: plan(),
          extra_headers: [{String.t(), String.t()}]
        }

  @go_base_url "https://opencode.ai/zen/go/v1"
  @zen_base_url "https://opencode.ai/zen/v1"

  @doc """
  Build an OpenCode (Zen/Go) model.

  Options:

    * `:model`    — the Zen model slug, e.g. `"deepseek-v4-flash"`.
    * `:api_key`  — falls back to `OPENCODE_API_KEY`.
    * `:plan`     — `:go` (default) or `:zen`; selects the base URL. Overridable
      via the `OPENCODE_PLAN` env var (`go` / `zen`).
    * `:base_url` — overrides the plan-derived URL (proxies / custom gateways).
    * `:app_title`/`:app_url` — accepted for call-site parity with
      `OpenRouter.new/1` but ignored (no attribution headers here).
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    plan = opts[:plan] |> plan_from_env() |> normalize_plan()

    opts =
      opts
      |> Keyword.put_new(:api_key, System.get_env("OPENCODE_API_KEY"))
      |> Keyword.put_new_lazy(:base_url, fn -> base_url(plan) end)
      |> Keyword.drop([:app_title, :app_url, :plan])

    struct!(__MODULE__, Keyword.put(opts, :plan, plan))
  end

  @doc "The base URL for a given plan."
  @spec base_url(plan()) :: String.t()
  def base_url(:go), do: @go_base_url
  def base_url(:zen), do: @zen_base_url

  # nil -> honor OPENCODE_PLAN; an explicit value wins.
  defp plan_from_env(nil), do: System.get_env("OPENCODE_PLAN")
  defp plan_from_env(plan), do: plan

  defp normalize_plan(nil), do: :go
  defp normalize_plan(:go), do: :go
  defp normalize_plan(:zen), do: :zen

  defp normalize_plan("go"), do: :go
  defp normalize_plan("zen"), do: :zen

  defp normalize_plan(other) when is_binary(other) do
    other |> String.downcase() |> then(&if(&1 == "zen", do: :zen, else: :go))
  end

  @impl true
  def request(model, messages, settings, params),
    do: ExAgent.Providers.OpenAIChat.request(model, messages, settings, params)

  @impl true
  def request_stream(model, messages, settings, params),
    do: ExAgent.Providers.OpenAIChat.request_stream(model, messages, settings, params)

  @impl true
  def model_name(%__MODULE__{model: model}), do: model
  @impl true
  def system(_), do: "opencode"
  @impl true
  def profile(_),
    do: %ExAgent.ModelProfile{
      supports_tools: true,
      supports_json_schema_output: true,
      supports_thinking: false
    }
end
