defmodule ExAgent.Tool.ValidationVocabulary do
  @moduledoc false

  # JSV 0.22 still counts graphemes and distinguishes integer/float map keys.
  # Override only these three keywords through its vocabulary extension point.
  # Retire this adapter when upstream passes the corresponding Tool regressions.
  alias JSV.Vocabulary.V202012.Validation, as: Upstream
  use JSV.Vocabulary, priority: 300

  @impl true
  defdelegate init_validators(opts), to: Upstream
  @impl true
  defdelegate handle_keyword(pair, acc, builder, schema), to: Upstream
  @impl true
  defdelegate finalize_validators(acc), to: Upstream

  @impl true
  def validate(data, validators, context) do
    JSV.Validator.reduce(validators, data, context, &validate_keyword/3)
  end

  defp validate_keyword({keyword, bound}, data, context)
       when keyword in [:minLength, :maxLength] and is_binary(data) do
    length = codepoint_length(data, 0)
    valid = if keyword == :minLength, do: length >= bound, else: length <= bound

    if valid do
      {:ok, data, context}
    else
      {:error, JSV.Validator.with_error(context, keyword, data, [])}
    end
  end

  defp validate_keyword({:uniqueItems, true}, data, context) when is_list(data) do
    keys = Enum.map(data, &number_key/1)

    if MapSet.size(MapSet.new(keys)) == length(keys) do
      {:ok, data, context}
    else
      {:error, JSV.Validator.with_error(context, :uniqueItems, data, [])}
    end
  end

  defp validate_keyword(keyword, data, context), do: Upstream.validate(data, [keyword], context)

  defp codepoint_length(<<_::utf8, rest::binary>>, n), do: codepoint_length(rest, n + 1)
  defp codepoint_length(<<>>, n), do: n

  defp number_key(value) when is_float(value) do
    integer = trunc(value)
    if value == integer, do: integer, else: value
  end

  defp number_key(value) when is_list(value), do: Enum.map(value, &number_key/1)

  defp number_key(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {k, number_key(v)} end)

  defp number_key(value), do: value

  @impl true
  def format_error(:uniqueItems, _, _), do: "Array items must be unique JSON values"
  def format_error(:minLength, _, _), do: "String has fewer Unicode codepoints than minLength"
  def format_error(:maxLength, _, _), do: "String has more Unicode codepoints than maxLength"
end
