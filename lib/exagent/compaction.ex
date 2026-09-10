defmodule ExAgent.Compaction do
  @moduledoc """
  Behaviour for reducing the conversation context sent to a model.

  A compactor takes the current request projection `[Message.t()]` and returns a
  compacted list, `{:no_change}` (leave it alone), or an error. The built-in
  `ExAgent.Compaction.Summary` replaces older messages with an LLM-generated
  summary while keeping the most recent ones verbatim.

  Compaction is wired into a run as a **capability** (see
  `ExAgent.Compaction.Capability`) that fires on the `before_model_request`
  hook. It changes only `request_messages`: the authoritative history remains
  append-only and `new_messages` remains its real suffix. Compaction is opt-in and
  does not guarantee that pinned context fits a provider's context window.
  """

  alias ExAgent.Message

  @type messages :: [Message.t()]
  @type opts :: keyword()

  @callback compact(messages(), opts()) ::
              {:ok, messages()} | {:no_change} | {:error, term()}

  @doc """
  A rough context estimate using content bytes / 4 plus message/part overhead.

  Includes instructions, text, thinking/signatures, tool names, arguments,
  returns and retries. It can under- or over-estimate model tokens, especially
  for different tokenizers, languages and multimodal content; it is not a usage
  or billing counter. The built-in capability also includes advertised tool
  definitions when using this default estimate. Supply `:token_counter` for a
  model-specific estimate.
  """
  @spec estimate_tokens(messages()) :: non_neg_integer()
  def estimate_tokens(messages), do: ExAgent.Compaction.Estimate.messages(messages)
end

defmodule ExAgent.Compaction.Summary do
  @moduledoc """
  A compactor that summarizes older messages and keeps a recent window verbatim.

  When the history exceeds `:threshold_tokens` (estimated via
  `ExAgent.Compaction.estimate_tokens/1` by default), everything older than the
  last `:keep_recent` messages is eligible for the caller's `:summarize` function.
  Complete tool exchanges, original instructions, and the latest user request are
  preserved. The recent window expands to avoid splitting calls from results or
  retries. Older completed exchanges within the current run are also eligible.

  The summary is ordinary user-level context inserted before the active user
  request, never a new System instruction. Pinned messages may exceed the target
  window, and a summary is not guaranteed to reduce the model-specific token count.
  Context without an identifiable user request is left unchanged.

  ## Options

    * `:threshold_tokens` — non-negative threshold (default `4000`); compact once
      the estimate exceeds it.
    * `:keep_recent` — non-negative minimum trailing messages kept verbatim
      (default `6`); zero still retains instructions and the active user request.
    * `:summarize` — `(old_messages -> summary_text)`. Required to compact; if
      absent, the projection is left untouched. May also return `{:no_change}`
      or `{:error, reason}`; other non-string results are rejected.
    * `:token_counter` — `(messages -> non_neg_integer())`, default
      `ExAgent.Compaction.estimate_tokens/1`.

  `:summarize` may perform external IO. The callback's model requests, tokens and
  costs are not automatically observable or charged to this run by this API.
  Repeated model requests can invoke it repeatedly; applications must not treat
  compaction as an exactly-once side effect.

  ## Wiring

      compaction = %ExAgent.Compaction.Capability{
        compactor: ExAgent.Compaction.Summary,
        opts: [
          threshold_tokens: 6000,
          keep_recent: 8,
          summarize: fn old ->
            {:ok, %{output: text}} = ExAgent.run(summarizer_agent, summarize_prompt(old))
            text
          end
        ]
      }

      ExAgent.new(model: "anthropic:claude-3-5-haiku", capabilities: [compaction])
  """

  @behaviour ExAgent.Compaction

  alias ExAgent.Compaction
  alias ExAgent.Compaction.Projection

  @impl true
  def compact(messages, opts) do
    threshold = opts[:threshold_tokens] || 4000
    keep = opts[:keep_recent] || 6
    summarize = opts[:summarize]
    counter = opts[:token_counter] || (&Compaction.estimate_tokens/1)

    cond do
      is_nil(summarize) ->
        {:no_change}

      not is_function(summarize, 1) or not is_function(counter, 1) or
        not is_integer(threshold) or threshold < 0 or not is_integer(keep) or keep < 0 ->
        {:error, :invalid_compaction_options}

      true ->
        with {:ok, old, retained} <- Projection.partition(messages, keep) do
          estimate = counter.(messages)

          cond do
            not is_integer(estimate) or estimate < 0 -> {:error, :invalid_token_estimate}
            old == [] or estimate <= threshold -> {:no_change}
            true -> summarize(old, retained, messages, summarize)
          end
        end
    end
  rescue
    error -> {:error, {:compaction_failed, error}}
  catch
    :throw, :exagent_stream_cancelled -> throw(:exagent_stream_cancelled)
    kind, reason -> {:error, {:compaction_failed, {kind, reason}}}
  end

  defp summarize(old, retained, original, summarize) do
    case summarize.(old) do
      text when is_binary(text) ->
        if String.valid?(text) do
          candidate = Projection.insert_summary(retained, text)
          with :ok <- Projection.validate(original, candidate), do: {:ok, candidate}
        else
          {:error, :invalid_summary}
        end

      {:no_change} ->
        {:no_change}

      {:error, _} = error ->
        error

      _ ->
        {:error, :invalid_summary}
    end
  end
end

defmodule ExAgent.Compaction.Capability do
  @moduledoc """
  A capability that compacts only the projection sent by `before_model_request`.

  It accepts the current `request_messages` override, or the full authoritative
  history when no override exists, so it can compact growth within a run without
  undoing an earlier capability's redaction. It never changes `messages` or
  `first_new_message_index`. Errors, no-change and invalid projections leave the
  incoming state unchanged; stream cancellation is propagated.

  Custom compactors retain `compact/2`, but must preserve original instructions,
  the latest user request and complete, unmodified tool exchanges. They must not
  insert new System instructions. With the built-in Summary/default counter,
  advertised function/output tool schemas also contribute to the rough estimate.
  A supplied `:token_counter` retains its one-argument interface and owns its
  entire estimate; capture tool definitions in its closure when needed.

  Add it to an agent's `:capabilities`:

      %ExAgent.Compaction.Capability{
        compactor: ExAgent.Compaction.Summary,
        opts: [threshold_tokens: 6000, keep_recent: 8, summarize: &my_summarize/1]
      }
  """

  use ExAgent.Capability

  defstruct [:compactor, :opts]

  @impl true
  def before_model_request(%__MODULE__{compactor: mod, opts: opts} = _cap, state) do
    source = state.request_messages || state.messages
    opts = counter_options(mod, opts || [], state)

    result =
      ExAgent.Observability.OpenTelemetry.around(
        Map.get(state, :observability),
        :compaction,
        ExAgent.Observability.OpenTelemetry.ids(state),
        Map.get(state, :trace_context),
        fn operation ->
          with {:ok, _groups} <- ExAgent.Compaction.Projection.groups(source),
               {:ok, compacted} <- mod.compact(source, opts),
               :ok <- ExAgent.Compaction.Projection.validate(source, compacted) do
            ExAgent.Observability.OpenTelemetry.attributes(operation, %{
              "exagent.compaction.changed" => compacted != source,
              "exagent.compaction.input_messages" => length(source),
              "exagent.compaction.output_messages" => length(compacted)
            })

            {:ok, compacted}
          else
            {:no_change} ->
              ExAgent.Observability.OpenTelemetry.attributes(operation, %{
                "exagent.compaction.changed" => false
              })

              {:no_change}

            other ->
              other
          end
        end
      )

    with {:ok, compacted} <- result do
      %{state | request_messages: compacted}
    else
      _ -> state
    end
  rescue
    _ -> state
  catch
    :throw, :exagent_stream_cancelled -> throw(:exagent_stream_cancelled)
    _, _ -> state
  end

  defp counter_options(ExAgent.Compaction.Summary, opts, state) do
    if opts[:token_counter] do
      opts
    else
      params = Map.get(state, :params) || %{}
      tools = Map.get(params, :function_tools, []) ++ Map.get(params, :output_tools, [])
      overhead = ExAgent.Compaction.Estimate.tools(tools)
      Keyword.put(opts, :token_counter, &(ExAgent.Compaction.estimate_tokens(&1) + overhead))
    end
  end

  defp counter_options(_mod, opts, _state), do: opts
end
