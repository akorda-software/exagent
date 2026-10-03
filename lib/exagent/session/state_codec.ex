defmodule ExAgent.Session.StateCodec do
  @moduledoc """
  Optional codec for application state at the Session checkpoint boundary.

  Configure `shared_state_codec: MyCodec` on `Session.start_link/1`. The module
  is supplied by the host, never by stored data. `encode/1` must return
  `{:ok, json_data}`; `decode/1` receives JSON data only after the complete
  snapshot and roster have been validated and returns `{:ok, application_state}`.
  Callbacks must be pure and must not include credentials in the persisted data.
  The codec module and application structs are never inferred from a snapshot.
  Callback failures return generic errors without exposing the supplied state.
  Successful decode still precedes the policy's separate restore validation.
  Without a codec, the existing JSON representation remains unchanged.
  """

  @callback encode(term()) :: {:ok, term()} | {:error, term()}
  @callback decode(term()) :: {:ok, term()} | {:error, term()}

  @doc false
  def validate(nil), do: :ok

  def validate(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :encode, 1) and
         function_exported?(module, :decode, 1),
       do: :ok,
       else: {:error, :invalid_shared_state_codec}
  end

  def validate(_), do: {:error, :invalid_shared_state_codec}

  @doc false
  def dump!(nil, state), do: state

  def dump!(module, state) do
    case invoke(module, :encode, state) do
      {:ok, data} -> ExAgent.SnapshotData.json(data)
      {:error, _} -> raise ArgumentError, "shared state codec failed to encode"
    end
  end

  @doc false
  def load(nil, data), do: {:ok, data}
  def load(module, data), do: invoke(module, :decode, data)

  defp invoke(module, callback, value) do
    case apply(module, callback, [value]) do
      {:ok, _} = result -> result
      {:error, _} -> {:error, :shared_state_codec_failed}
      _ -> {:error, :invalid_shared_state_codec_return}
    end
  rescue
    _ -> {:error, :shared_state_codec_failed}
  catch
    _, _ -> {:error, :shared_state_codec_failed}
  end
end
