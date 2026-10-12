defmodule ExAgent.Models.ReqLLMPromptCache do
  @moduledoc false

  # Prompt caching is a cost optimization: it never changes history, tools or
  # continuation binding. OpenRouter forwards explicit `cache_control`
  # breakpoints (Anthropic/Gemini routes); OpenAI caches automatically and
  # accepts a stable routing key.

  @ttls ["5m", "1h"]

  @doc "Validates the `:prompt_cache` option for the resolved provider before IO."
  def resolve!(disabled, _provider) when disabled in [nil, false], do: nil
  def resolve!(true, provider), do: resolve!([], provider)

  def resolve!(opts, :openrouter) when is_list(opts) do
    allowed!(opts, [:ttl])

    case opts[:ttl] do
      nil -> %{cache_control: %{type: "ephemeral"}}
      ttl when ttl in @ttls -> %{cache_control: %{type: "ephemeral", ttl: ttl}}
      _ -> fail!({:invalid_option, :prompt_cache})
    end
  end

  def resolve!(opts, :openai) when is_list(opts) do
    allowed!(opts, [:key])

    case opts[:key] do
      nil -> %{}
      key when is_binary(key) and byte_size(key) in 1..256 -> %{key: key}
      _ -> fail!({:invalid_option, :prompt_cache})
    end
  end

  def resolve!(opts, _provider) when is_list(opts), do: fail!({:unsupported, :prompt_cache})
  def resolve!(_, _), do: fail!({:invalid_option, :prompt_cache})

  @doc "Adds the OpenAI cache key to the request's provider options."
  def put_key(opts, %{key: key}),
    do:
      Keyword.update(
        opts,
        :provider_options,
        [prompt_cache_key: key],
        &Keyword.put(&1, :prompt_cache_key, key)
      )

  def put_key(opts, _cache), do: opts

  @doc """
  Marks the last system message and the newest message, so each request reuses
  the prefix cached by the previous one.
  """
  def put_breakpoints(%{messages: messages} = context, %{cache_control: control}) do
    system = messages |> Enum.reverse() |> Enum.find_index(&(&1.role == :system))

    marks =
      Enum.uniq(List.wrap(system && length(messages) - 1 - system) ++ [length(messages) - 1])

    messages =
      Enum.reduce(marks, messages, fn index, acc ->
        List.update_at(acc, index, &mark(&1, control))
      end)

    %{context | messages: messages}
  end

  def put_breakpoints(context, _cache), do: context

  defp mark(%{content: [_ | _] = parts} = message, control) do
    parts =
      List.update_at(parts, -1, fn part ->
        %{part | metadata: Map.put(part.metadata || %{}, :cache_control, control)}
      end)

    %{message | content: parts}
  end

  defp mark(message, _control), do: message

  defp allowed!(opts, keys) do
    unless Keyword.keyword?(opts) and Keyword.keys(opts) == Enum.uniq(Keyword.keys(opts)) and
             Enum.all?(Keyword.keys(opts), &(&1 in keys)),
           do: fail!({:unsupported_options, :prompt_cache})
  end

  defp fail!(reason), do: throw({:req_llm_adapter, reason})
end
