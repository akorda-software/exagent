defmodule ExAgent.Models.OpenCode do
  @moduledoc """
  OpenCode Zen/Go gateway using the OpenAI Chat Completions protocol.

  The Go plan (`:go`, default) uses `https://opencode.ai/zen/go/v1`; Zen
  (`:zen`) uses `https://opencode.ai/zen/v1`. Both authenticate using Bearer
  `OPENCODE_API_KEY`, but the selected plan must match the key's entitlement.
  Model IDs are bare gateway slugs, for example `deepseek-v4-flash`.

      ExAgent.Models.OpenCode.new(model: "deepseek-v4-flash", plan: :zen)

  This constructor and plan selection are integrated from upstream commits
  97ebc37, f134f1d and a31b306; streaming uses the current final-model contract.
  """
  @behaviour ExAgent.Model

  defstruct [:model, :api_key, :base_url, plan: :go, extra_headers: [], stream_options: []]

  @type plan :: :go | :zen
  @type t :: %__MODULE__{
          model: String.t(),
          api_key: String.t() | nil,
          base_url: String.t() | nil,
          plan: plan(),
          extra_headers: [{String.t(), String.t()}],
          stream_options: keyword()
        }

  @doc """
  Build an OpenCode model. Options:

    * `:model` — bare model slug.
    * `:api_key` — defaults to `OPENCODE_API_KEY`.
    * `:plan` — `:go` or `:zen` (also case-insensitive, trimmed strings).
      An explicit plan wins over `OPENCODE_PLAN`; absent/blank defaults to Go.
      Unknown values raise instead of silently choosing a billing endpoint.
    * `:base_url` — override the plan-derived URL.
    * `:extra_headers` — additional request headers.
    * `:app_title`/`:app_url` — accepted for OpenRouter call-site parity, ignored.
    * `:stream_options` — local limits from `ExAgent.Providers.StreamTransport`.
  """
  def new(opts) when is_list(opts) do
    plan = opts[:plan] |> plan_from_env() |> normalize_plan()

    opts =
      opts
      |> Keyword.put_new(:api_key, System.get_env("OPENCODE_API_KEY"))
      |> Keyword.put_new_lazy(:base_url, fn -> base_url(plan) end)
      |> Keyword.drop([:app_title, :app_url, :plan])

    struct!(__MODULE__, Keyword.put(opts, :plan, plan))
  end

  @doc "The base URL for a plan, independent of environment configuration."
  @spec base_url(plan()) :: String.t()
  def base_url(:go), do: "https://opencode.ai/zen/go/v1"
  def base_url(:zen), do: "https://opencode.ai/zen/v1"

  defp plan_from_env(nil), do: System.get_env("OPENCODE_PLAN")
  defp plan_from_env(plan), do: plan
  defp normalize_plan(nil), do: :go
  defp normalize_plan(:go), do: :go
  defp normalize_plan(:zen), do: :zen

  defp normalize_plan(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "" -> :go
      "go" -> :go
      "zen" -> :zen
      _ -> raise ArgumentError, "unknown OPENCODE_PLAN #{inspect(value)} (expected :go or :zen)"
    end
  end

  defp normalize_plan(value),
    do: raise(ArgumentError, "unknown :plan #{inspect(value)} (expected :go or :zen)")

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
