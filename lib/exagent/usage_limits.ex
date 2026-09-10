defmodule ExAgent.UsageLimits do
  @moduledoc """
  Execution-tree safety net: each run's limits also constrain its framework
  descendants. Admission is serialized by `ExAgent.ExecutionScope`; these
  functions provide the pure checks. Token/cost thresholds are retrospective,
  so already in-flight requests can exceed them.

  Any `nil` field is unchecked. When a limit is exceeded the run terminates with
    a `RunError` with reason `{:usage_limit_exceeded, which, value}`.

  * `request_limit` / `total_tokens_limit` / `input_tokens_limit` /
    `output_tokens_limit` — checked before each model request.
  * `tool_calls_limit` — checked before a batch of tool calls is executed
    (pydanticAI semantics: if the model returned parallel calls that would
    exceed the limit, none run).
  * `max_budget_cents` — checked before each model request against an estimated
    cost (see `ExAgent.CostGuard`). Requires an `:estimate_cost` run option.

  ## Example

      alias ExAgent.{CostGuard, UsageLimits}

      agent =
        ExAgent.new(
          model: "openai:gpt-4o",
          usage_limits: %UsageLimits{
            request_limit: 5,
            total_tokens_limit: 2000,
            tool_calls_limit: 10,
            max_budget_cents: 25
          }
        )

      pricing = CostGuard.estimator(%{input_per_1k_cents: 250, output_per_1k_cents: 1000})
      ExAgent.run(agent, "research this", estimate_cost: pricing)
  """

  @enforce_keys []
  defstruct request_limit: nil,
            total_tokens_limit: nil,
            input_tokens_limit: nil,
            output_tokens_limit: nil,
            tool_calls_limit: nil,
            max_budget_cents: nil

  @type t :: %__MODULE__{
          request_limit: non_neg_integer() | nil,
          total_tokens_limit: non_neg_integer() | nil,
          input_tokens_limit: non_neg_integer() | nil,
          output_tokens_limit: non_neg_integer() | nil,
          tool_calls_limit: non_neg_integer() | nil,
          max_budget_cents: number() | nil
        }

  @doc "Validate nonnegative integral counters and a nonnegative monetary threshold."
  def validate(nil), do: :ok

  def validate(%__MODULE__{} = limits) do
    counters = [
      :request_limit,
      :total_tokens_limit,
      :input_tokens_limit,
      :output_tokens_limit,
      :tool_calls_limit
    ]

    invalid =
      Enum.find(counters, fn field ->
        value = Map.fetch!(limits, field)
        not (is_nil(value) or (is_integer(value) and value >= 0))
      end)

    cond do
      invalid ->
        {:error, {:invalid_usage_limit, invalid}}

      not (is_nil(limits.max_budget_cents) or
               (is_number(limits.max_budget_cents) and limits.max_budget_cents >= 0)) ->
        {:error, {:invalid_usage_limit, :max_budget_cents}}

      true ->
        :ok
    end
  end

  def validate(_), do: {:error, :invalid_usage_limits}

  @doc """
  Check the request/token/budget limits against accumulated `usage`, the
  upcoming request count, and the estimated `cost_cents`. Returns `:ok` or
  `{:error, {:usage_limit_exceeded, which, value}}`.

  `request_count` is the number of model requests already issued (0 before the
  first). `cost_cents` is the known estimate so far, or `nil` when unknown; an
  enabled monetary budget rejects unknown cost.
  """
  @spec check_before_request(t(), ExAgent.Message.Usage.t(), non_neg_integer(), number() | nil) ::
          :ok | {:error, term()}
  def check_before_request(%__MODULE__{} = limits, usage, request_count, cost_cents \\ nil) do
    total = (usage.input_tokens || 0) + (usage.output_tokens || 0)

    cond do
      limits.max_budget_cents != nil and not is_number(cost_cents) ->
        {:error, :cost_unknown}

      exceeds?(limits.request_limit, request_count) ->
        {:error, {:usage_limit_exceeded, :request_limit, request_count}}

      exceeds?(limits.total_tokens_limit, total) ->
        {:error, {:usage_limit_exceeded, :total_tokens, total}}

      exceeds?(limits.input_tokens_limit, usage.input_tokens || 0) ->
        {:error, {:usage_limit_exceeded, :input_tokens, usage.input_tokens || 0}}

      exceeds?(limits.output_tokens_limit, usage.output_tokens || 0) ->
        {:error, {:usage_limit_exceeded, :output_tokens, usage.output_tokens || 0}}

      exceeds?(limits.max_budget_cents, cost_cents) ->
        {:error, {:usage_limit_exceeded, :budget_cents, cost_cents}}

      true ->
        :ok
    end
  end

  @doc """
  Check the `tool_calls_limit` before executing a batch of `incoming` tool
  calls. Returns `:ok` or `{:error, {:usage_limit_exceeded, :tool_calls, n}}`.

  `executed` is the number of tool calls already run this run. Following
  pydanticAI, if `executed + incoming` would exceed the limit, none of the
  incoming calls are executed.
  """
  @spec check_tool_calls(t(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, {:usage_limit_exceeded, :tool_calls, non_neg_integer()}}
  def check_tool_calls(%__MODULE__{tool_calls_limit: nil}, _executed, _incoming), do: :ok

  def check_tool_calls(%__MODULE__{tool_calls_limit: limit}, executed, incoming) do
    total = executed + incoming

    if total > limit do
      {:error, {:usage_limit_exceeded, :tool_calls, total}}
    else
      :ok
    end
  end

  defp exceeds?(nil, _), do: false
  defp exceeds?(limit, value), do: value >= limit
end

defmodule ExAgent.CostGuard do
  @moduledoc """
  Helpers for turning token usage into an estimated cost, used together with
  the `max_budget_cents` field of `ExAgent.UsageLimits`.

  ExAgent does **not** ship a pricing table (model prices change constantly and
  vary by vendor). You bring the prices that matter to you as a map and
  `CostGuard.estimator/1` builds the `(usage -> cents)` function you pass to
  `ExAgent.run/3` via the `:estimate_cost` option.

  ## Example

      pricing = ExAgent.CostGuard.estimator(%{
        input_per_1k_cents: 250,
        output_per_1k_cents: 1000
      })

      ExAgent.run(agent, "go", estimate_cost: pricing)
  """

  alias ExAgent.Message.Usage

  @type pricing :: %{
          optional(:input_per_1k_cents) => number(),
          optional(:output_per_1k_cents) => number()
        }

  @doc """
  Build a cost estimator `(Usage.t() -> fractional cents)` from a pricing map.

  Prices are per **1000 tokens**, in **cents** (`250` means $2.50 per 1K,
  or $2500 per 1M tokens). Fractions are preserved rather than truncating every
  small request to zero. Missing rates remain unknown when their token direction
  is used; they do not imply a free provider.
  """
  @spec estimator(pricing()) :: (Usage.t() -> non_neg_integer() | float() | :unknown)
  def estimator(pricing) when is_map(pricing) do
    in_per_1k = Map.get(pricing, :input_per_1k_cents)
    out_per_1k = Map.get(pricing, :output_per_1k_cents)

    for rate <- [in_per_1k, out_per_1k] do
      unless is_nil(rate) or (is_number(rate) and rate >= 0),
        do: raise(ArgumentError, "token prices must be nonnegative numbers")
    end

    fn %Usage{} = usage ->
      input = usage.input_tokens
      output = usage.output_tokens

      cond do
        not is_integer(input) or not is_integer(output) -> :unknown
        input > 0 and in_per_1k == nil -> :unknown
        output > 0 and out_per_1k == nil -> :unknown
        true -> (input * (in_per_1k || 0) + output * (out_per_1k || 0)) / 1000
      end
    end
  end

  @doc "Evaluate legacy homogeneous or model-aware pricing without losing unknown/error states."
  def estimate(estimator, model, usage) do
    value =
      cond do
        is_function(estimator, 2) -> estimator.(model, usage)
        is_function(estimator, 1) -> estimator.(usage)
        true -> :unknown
      end

    case value do
      value when is_number(value) and value >= 0 -> {:ok, value}
      :unknown -> :unknown
      nil -> :unknown
      {:error, reason} -> {:error, {:cost_estimation_failed, reason}}
      _ -> {:error, :invalid_cost_estimate}
    end
  rescue
    error -> {:error, {:cost_estimation_failed, error}}
  catch
    kind, reason -> {:error, {:cost_estimation_failed, {kind, reason}}}
  end
end
