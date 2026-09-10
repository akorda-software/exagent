defmodule ExAgent.Permissions do
  @moduledoc """
  Per-tool admission control: `:allow`, `:ask` or `:deny`, matched against tool
  names with glob patterns — the same model opencode uses for tool safety.

  Rules are evaluated in order and the **last matching rule wins** (so put a
  catch-all `*` first, then more specific rules after it). Anything that matches
  no rule falls back to `:default` (`:allow` by default).

  `new!/1` rejects invalid configuration instead of silently granting access.
  `:approve` is a callback result, not a rule or default action. Only an explicit
  `:allow` decision, or `:ask` approved by its callback, authorizes execution.

  * `:allow` — run the tool.
  * `:deny` — never run it; the model receives a "permission denied" tool return
    so it can adapt.
  * `:ask` — require human approval. In a one-shot `ExAgent.run/3` you pass an
    `:approve` callback `(tool_call -> :approve | :deny)`; the run calls it (it
    may block on a PubSub round-trip in a LiveView). With no callback, `:ask`
    is treated as `:deny` (fail closed).

  ## Example

      perms =
        ExAgent.Permissions.new!(
          rules: [{"*", :deny}, {"read", :allow}, {"search_*", :allow}, {"bash", :ask}],
          default: :deny
        )

      ExAgent.Permissions.decide(perms, "bash")        #=> :ask
      ExAgent.Permissions.decide(perms, "search_web")  #=> :allow
      ExAgent.Permissions.decide(perms, "write")       #=> :deny
  """

  @type action :: :allow | :ask | :deny

  defstruct rules: [], default: :allow

  @type t :: %__MODULE__{
          # compiled {Regex.t(), action()} pairs, in evaluation order
          rules: [{Regex.t(), action()}],
          default: action()
        }

  @doc """
  Build a permissions set from `rules` (`[{glob_string, action}]`) and a
  `:default` action. Globs support `*` (any run of chars) and `?` (single char).

  Raises `ArgumentError` for unknown options, malformed rules, or actions other
  than `:allow`, `:ask` and `:deny`.
  """
  @spec new!(keyword()) :: t()
  def new!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "expected permissions options to be a keyword list"
    end

    opts = Keyword.validate!(opts, [:rules, :default])
    default = validate_action!(Keyword.get(opts, :default, :allow))

    rules =
      case Keyword.get(opts, :rules, []) do
        rules when is_list(rules) -> Enum.map(rules, &compile_rule!/1)
        _ -> raise ArgumentError, "expected :rules to be a list of {glob_string, action} pairs"
      end

    %__MODULE__{rules: rules, default: default}
  end

  @doc """
  Decide the action for a tool name (last matching rule wins, else default).

  An unknown selected action in a manually constructed or modified struct is
  treated as `:deny`. Prefer `new!/1` to reject invalid configuration up front.
  """
  @spec decide(t(), String.t()) :: action()
  def decide(%__MODULE__{rules: rules, default: default}, tool_name) when is_binary(tool_name) do
    action =
      Enum.reduce(rules, default, fn {regex, action}, acc ->
        if Regex.match?(regex, tool_name), do: action, else: acc
      end)

    if action in [:allow, :ask, :deny], do: action, else: :deny
  end

  @doc """
  Resolve an `:ask` decision through an optional `approve` callback.

  * `:allow` → `:allow`.
  * `:deny` → `:deny`.
  * `:ask` with a callback → calls it with `tool_call` and maps `:approve` to
    `:allow`, anything else to `:deny`.
  * `:ask` without a callable one-argument callback → `:deny` (fail closed).
  * An unknown action → `:deny` (fail closed).
  """
  @spec resolve(action(), term(), (term() -> :approve | term()) | nil) :: :allow | :deny
  def resolve(:allow, _tool_call, _approve), do: :allow

  def resolve(:ask, tool_call, approve) when is_function(approve, 1) do
    case approve.(tool_call) do
      :approve -> :allow
      _ -> :deny
    end
  end

  def resolve(_action, _tool_call, _approve), do: :deny

  defp validate_action!(action) when action in [:allow, :ask, :deny], do: action

  defp validate_action!(action) do
    raise ArgumentError,
          "expected a permission action (:allow, :ask or :deny), got: #{inspect(action)}"
  end

  defp compile_rule!({glob, action}) when is_binary(glob),
    do: {compile_glob(glob), validate_action!(action)}

  defp compile_rule!(rule) do
    raise ArgumentError, "expected a {glob_string, action} permission rule, got: #{inspect(rule)}"
  end

  defp compile_glob(glob) when is_binary(glob) do
    pattern =
      glob
      |> Regex.escape()
      |> String.replace("\\*", ".*")
      |> String.replace("\\?", ".")
      |> then(&"^#{&1}$")

    Regex.compile!(pattern)
  end
end
