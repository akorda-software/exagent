defmodule ExAgent.RuntimeIdentity do
  @moduledoc false
  @prefix "exagent.scope.v1:"

  def validate(namespace, id) do
    cond do
      not (is_nil(namespace) or
               (is_binary(namespace) and namespace != "" and String.valid?(namespace))) ->
        {:error, :invalid_namespace}

      not is_binary(id) or not String.valid?(id) ->
        {:error, :invalid_runtime_id}

      is_nil(namespace) and reserved?(id) ->
        {:error, :reserved_runtime_id}

      true ->
        :ok
    end
  end

  def key(namespace, kind, id) when kind in [:agent, :session] do
    with :ok <- validate(namespace, id) do
      if is_nil(namespace) do
        {:ok, id}
      else
        {:ok,
         @prefix <>
           Base.url_encode64(Jason.encode!([namespace, Atom.to_string(kind), id]), padding: false)}
      end
    end
  end

  def decode(@prefix <> encoded = key) do
    with {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, [namespace, kind, id]} <- Jason.decode(json),
         true <- is_binary(namespace) and namespace != "",
         kind when not is_nil(kind) <-
           Enum.find([:agent, :session], &(Atom.to_string(&1) == kind)),
         {:ok, ^key} <- key(namespace, kind, id) do
      {:ok, {namespace, kind, id}}
    else
      _ -> {:error, :invalid_scoped_identity}
    end
  end

  def decode(_), do: {:error, :invalid_scoped_identity}

  def reserved?(id) when is_binary(id), do: String.starts_with?(id, @prefix)
  def reserved?(_), do: false
end
