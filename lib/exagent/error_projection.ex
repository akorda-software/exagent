defmodule ExAgent.ErrorProjection do
  @moduledoc false

  # Export deliberately selected diagnostic fields, never a live struct dump.
  def reason(value), do: project(value, 0)
  def message(value) when is_binary(value), do: value
  def message(value), do: value |> reason() |> inspect()

  # Exportable diagnostics are stricter than the runtime/UI projection above:
  # even plain string causes and tuple members can contain application secrets.
  def diagnostic(%ExAgent.RunError{reason: reason}), do: diagnostic(reason)
  def diagnostic(%ExAgent.CheckpointError{reason: reason}), do: diagnostic(reason)

  def diagnostic(%ExAgent.RequestError{} = error) do
    %{
      type: "request_error",
      provider: provider(error.provider),
      status: if(is_integer(error.status) and error.status in 100..599, do: error.status)
    }
    |> Map.reject(fn {_, value} -> is_nil(value) end)
  end

  def diagnostic(%module{}), do: %{type: Atom.to_string(module)}

  def diagnostic(value) when is_tuple(value) do
    parts = Tuple.to_list(value)

    nested =
      Enum.find(parts, &(is_struct(&1, ExAgent.RequestError) or is_struct(&1, ExAgent.RunError)))

    if nested, do: diagnostic(nested), else: diagnostic(List.first(parts))
  end

  def diagnostic(value) when is_atom(value) and not is_nil(value),
    do: %{type: Atom.to_string(value)}

  def diagnostic(_), do: %{type: "operation_failed"}

  defp project(_, depth) when depth >= 8, do: "opaque"

  defp project(%ExAgent.RequestError{} = error, depth) do
    %{
      exception: "Elixir.ExAgent.RequestError",
      provider: provider(error.provider),
      status: if(is_integer(error.status) and error.status in 100..599, do: error.status),
      reason: category(error.reason, depth + 1)
    }
  end

  defp project(%ExAgent.RunError{reason: reason}, depth),
    do: %{exception: "Elixir.ExAgent.RunError", reason: project(reason, depth + 1)}

  defp project(%module{}, _), do: %{exception: Atom.to_string(module)}

  defp project(value, depth) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.take(16) |> Enum.map(&project(&1, depth + 1))

  defp project(value, _) when value in [nil, true, false], do: value
  defp project(value, _) when is_atom(value), do: Atom.to_string(value)
  defp project(value, _) when is_binary(value) or is_number(value), do: value
  defp project(_, _), do: "opaque"

  # Provider reasons are categories, not arbitrary response strings or configs.
  defp category(_, depth) when depth >= 8, do: "opaque"
  defp category(value, _) when value in [nil, true, false], do: value
  defp category(value, _) when is_atom(value), do: Atom.to_string(value)
  defp category(value, _) when is_number(value), do: value

  defp category(value, depth) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.take(16) |> Enum.map(&category(&1, depth + 1))

  defp category(_, _), do: "opaque"

  defp provider(nil), do: nil
  defp provider(value) when is_atom(value), do: value |> Atom.to_string() |> provider()

  defp provider(value) when is_binary(value) do
    if byte_size(value) <= 64 and Regex.match?(~r/\A[A-Za-z0-9_.:-]+\z/, value),
      do: value,
      else: nil
  end

  defp provider(_), do: nil
end
