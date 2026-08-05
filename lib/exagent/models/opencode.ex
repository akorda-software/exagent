defmodule ExAgent.Models.OpenCode do
  @moduledoc """
  [OpenCode Zen / Go](https://opencode.ai/docs/zen) provider.

  OpenCode's hosted gateway speaks the OpenAI Chat Completions wire format, so
  it reuses `ExAgent.Providers.OpenAIChat`. The only differences from OpenAI
  are the base URL (`https://opencode.ai/zen/v1`) and the env key
  (`OPENCODE_API_KEY`).

  Both subscription plans share this gateway:

    * **OpenCode Go** — flat-rate ($10/mo) plan, the low-cost pick.
    * **OpenCode Zen** — pay-as-you-go, billed per token.

  They are indistinguishable on the wire: same endpoint, same model ids; the
  plan is selected by which API key you supply. So a single adapter covers both.

  Model ids are the bare Zen slugs (NOT the `opencode/<id>` form used in the
  OpenCode TUI config). For example, the OpenRouter slug
  `deepseek/deepseek-v4-flash` becomes `deepseek-v4-flash` here:

      model = ExAgent.Models.OpenCode.new(model: "deepseek-v4-flash")

  The full model catalogue (DeepSeek, GLM, Kimi, Qwen, MiniMax, plus the free
  tiers) is listed at `https://opencode.ai/zen/v1/models`.
  """
  @behaviour ExAgent.Model

  defstruct [:model, :api_key, :base_url, extra_headers: []]

  @type t :: %__MODULE__{
          model: String.t(),
          api_key: String.t() | nil,
          base_url: String.t() | nil,
          extra_headers: [{String.t(), String.t()}]
        }

  @default_base_url "https://opencode.ai/zen/v1"

  @doc """
  Build an OpenCode (Zen/Go) model.

  Options:

    * `:model`    — the Zen model slug, e.g. `"deepseek-v4-flash"`.
    * `:api_key`  — falls back to `OPENCODE_API_KEY`.
    * `:base_url` — defaults to `#{@default_base_url}`.
    * `:app_title`/`:app_url` — accepted for call-site parity with
      `OpenRouter.new/1` but ignored (no attribution headers here).
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    opts =
      opts
      |> Keyword.put_new(:api_key, System.get_env("OPENCODE_API_KEY"))
      |> Keyword.put_new(:base_url, @default_base_url)
      |> Keyword.drop([:app_title, :app_url])

    struct!(__MODULE__, opts)
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
