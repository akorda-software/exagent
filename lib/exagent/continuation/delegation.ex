defmodule ExAgent.Continuation.Delegation do
  @moduledoc false
  alias ExAgent.Continuation.Record

  @enforce_keys [:delegate, :prompt_arg, :options, :config]
  defstruct [:delegate, :prompt_arg, :options, :config]

  def new(delegate, prompt_arg, options, config),
    do: %__MODULE__{delegate: delegate, prompt_arg: prompt_arg, options: options, config: config}

  def descriptor_data(nil), do: {:ok, nil}

  def descriptor_data(%__MODULE__{config: config, prompt_arg: prompt_arg}) do
    with true <- is_map(config) and Record.text?(prompt_arg),
         true <- Enum.all?([:definition, :policy, :model_ref], &Record.reference?(config[&1])),
         %{dump: dump, load: load} <- config[:model_codec],
         true <- is_function(dump, 1) and is_function(load, 2) do
      {:ok,
       %{
         "descriptor_version" => 1,
         "prompt_arg" => prompt_arg,
         "definition" => config.definition,
         "policy" => config.policy,
         "model_ref" => config.model_ref
       }}
    else
      _ -> {:error, :invalid_delegation_descriptor}
    end
  end

  def descriptor_data(_), do: {:error, :invalid_delegation_descriptor}

  def resolve(%__MODULE__{} = descriptor, context, args) do
    with {:ok, _} <- descriptor_data(descriptor),
         %ExAgent{} = agent <- agent(descriptor.delegate, context, args),
         prompt when is_binary(prompt) <- argument(args, descriptor.prompt_arg) do
      {:ok, agent, prompt, descriptor.options, descriptor.config}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_delegation_definition}
    end
  rescue
    _ -> {:error, :invalid_delegation_definition}
  catch
    _, _ -> {:error, :invalid_delegation_definition}
  end

  @leaf_options ~w(deps model_settings prepend_instructions max_payload_bytes max_history_bytes on_event on_progress permissions approve estimate_cost deadline max_concurrent_requests permission_floor permission_floors)a

  def catalog?(entries) when is_list(entries) and length(entries) <= 255 do
    Enum.all?(entries, fn entry ->
      Record.exact?(entry, [:definition, :policy, :model_ref, :load]) and
        Enum.all?([:definition, :policy, :model_ref], &Record.reference?(entry[&1])) and
        is_function(entry.load, 2)
    end) and
      length(Enum.uniq_by(entries, &Map.take(&1, [:definition, :policy, :model_ref]))) ==
        length(entries)
  end

  def catalog?(_), do: false

  def lookup(entries, descriptor) do
    with {:ok, data} <- descriptor_data(descriptor),
         entry when not is_nil(entry) <-
           Enum.find(entries, fn entry ->
             Enum.all?(
               [:definition, :policy, :model_ref],
               &(entry[&1] === data[Atom.to_string(&1)])
             )
           end) do
      {:ok, entry}
    else
      _ -> {:error, :continuation_delegation_definition_missing}
    end
  end

  def resolve10(descriptor, entry, context, args) do
    with {:ok, _} <- descriptor_data(descriptor),
         true <- catalog?([entry]),
         {:ok, %ExAgent{} = agent, opts, %{model_codec: codec} = codecs} <-
           entry.load.(context, args),
         true <- Record.exact?(codecs, [:model_codec]),
         true <-
           Record.exact?(codec, [:dump, :load]) and is_function(codec.dump, 1) and
             is_function(codec.load, 2),
         true <- leaf_options?(opts) and leaf_options?(descriptor.options),
         prompt when is_binary(prompt) <- argument(args, descriptor.prompt_arg),
         {:ok, options} <- restrict_options(descriptor.options, opts) do
      {:ok, agent, prompt, options,
       Map.put(Map.take(entry, [:definition, :policy, :model_ref]), :model_codec, codec)}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_delegation_definition}
    end
  rescue
    _ -> {:error, :invalid_delegation_definition}
  catch
    _, _ -> {:error, :invalid_delegation_definition}
  end

  defp leaf_options?(opts) when is_list(opts),
    do:
      Keyword.keyword?(opts) and
        length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
        Enum.all?(Keyword.keys(opts), &(&1 in @leaf_options))

  defp leaf_options?(_), do: false

  defp restrict_options(original, current) do
    # Non-authority values are loader configuration; all authority is conjunctive.
    policies =
      for key <- [:permissions, :permission_floor], p = original[key], not is_nil(p), do: p

    opts = Keyword.merge(original, current)

    opts =
      Keyword.put(
        opts,
        :permission_floors,
        policies ++
          Keyword.get(original, :permission_floors, []) ++
          Keyword.get(current, :permission_floors, [])
      )

    opts =
      Enum.reduce(
        [:deadline, :max_concurrent_requests, :max_payload_bytes, :max_history_bytes],
        opts,
        fn key, opts ->
          case ExAgent.Continuation.Authority.minimum(original[key], current[key]) do
            nil -> opts
            value -> Keyword.put(opts, key, value)
          end
        end
      )

    with :ok <- ExAgent.ExecutionScope.validate_structural_options(opts), do: {:ok, opts}
  end

  defp agent(%ExAgent{} = agent, _, _), do: agent
  defp agent(builder, context, args) when is_function(builder, 2), do: builder.(context, args)

  defp argument(args, key) do
    Enum.find_value(args, fn
      {^key, value} -> value
      {name, value} when is_atom(name) -> if Atom.to_string(name) == key, do: value
      _ -> nil
    end)
  end
end
