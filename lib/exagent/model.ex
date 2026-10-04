defmodule ExAgent.ModelRequestParameters do
  @moduledoc """
  The per-request contract handed to a model. It bundles the tools the agent
  has prepared (function tools + output tools), the negotiated output mode, and
  the structured-output schema (if any).

  The struct is deliberately minimal for now and grows as we add tool/output
  features.
  """
  alias ExAgent.{Tool, Message}

  @type output_mode :: :text | :tool | :native | :prompted | :auto
  @type output_object :: %{json_schema: map(), module: module() | nil}

  defstruct function_tools: [],
            output_tools: [],
            output_mode: :text,
            allow_text_output: true,
            output_object: nil,
            idempotency_key: nil,
            instructions: [],
            tool_call_deltas: false

  @type t :: %__MODULE__{
          function_tools: [Tool.t()],
          output_tools: [Tool.t()],
          output_mode: output_mode(),
          allow_text_output: boolean(),
          output_object: output_object() | nil,
          idempotency_key: String.t() | nil,
          instructions: [Message.Part.System.t()],
          tool_call_deltas: boolean()
        }
end

defmodule ExAgent.Model do
  @moduledoc """
  Behaviour that every provider model implements.

  A "model" is any struct whose module `@behaviour`s `ExAgent.Model`. The
  struct carries the model's own state (base URL, API key, configured
  options…). Callers never invoke a provider module directly — they go through
  the dispatch functions in this module (`request/4`, `request_stream/4`, …),
  which resolve the implementer from the struct's `__struct__`.

  This uses Elixir behaviours plus struct dispatch so providers can stay small
  and explicit.
  """

  alias ExAgent.{Message, ModelSettings, ModelRequestParameters}

  @type model :: struct()
  @type messages :: [Message.t()]

  @doc """
  Make a non-streaming request and return a full `Message.Response`.

  Implementations return the (possibly updated) model struct alongside the
  response. Real providers return the model unchanged; stateful models (e.g.
  the script-driven `Test`) thread their internal state through the run this
  way, avoiding globals.
  """
  @callback request(
              model :: model(),
              messages,
              ModelSettings.t() | nil,
              ModelRequestParameters.t()
            ) :: {:ok, Message.Response.t(), model()} | {:error, term()}

  @doc """
  Make a lazy streaming request. Events are `{:text_delta, binary}`, optional
  `{:thinking_delta, binary}` (separate from output text), optional
  `{:usage, cumulative_request_usage}`, and exactly one terminal
  `{:response, response, final_model}` or `{:error, reason}`. Usage snapshots
  replace earlier snapshots for this request; they are not additive deltas.
  When `params.tool_call_deltas` is true, implementations may also emit
  `{:tool_call_delta, %{index: index, name: name_or_nil, fragment: binary}}`
  as tool-call arguments are generated: the first event for an index carries
  the tool name, later ones carry raw argument JSON fragments. They are a
  preview only; the terminal response stays authoritative.
  Implementations must release resources when enumeration halts. A stream
  ending without a terminal is a protocol error. Implementations may return
  `{:error, _}` directly when streaming is unsupported.
  """
  @callback request_stream(
              model :: model(),
              messages,
              ModelSettings.t() | nil,
              ModelRequestParameters.t()
            ) :: Enumerable.t() | {:error, term()}

  @callback model_name(model()) :: String.t()
  @callback system(model()) :: String.t()

  @doc """
  Declares capabilities (optional; extra capabilities default to false). The core rejects
  function tools and tool-based structured output when `supports_tools` is false.
   Explicit native output requires `supports_json_schema_output: true` before
   request admission. Native JSON/thinking flags do not describe tool-output mode and
  are not used to silently downgrade it. Streaming requires its own callback.
  """
  @callback profile(model()) :: ExAgent.ModelProfile.t()

  @doc """
  Optional no-IO preflight required by persisted continuation. Validate restored
  logical history, provider/endpoint binding and codec/settings using the trusted
  current model and tool inventory. Never dispatch a request from this callback.
  Ordinary run/request consumers do not require it.
  """
  @callback validate_resume(model(), messages, ModelSettings.t(), ModelRequestParameters.t()) ::
              :ok | {:error, term()}

  @doc """
  Optional static configuration binding for persisted continuation, without IO.

  Return `{:ok, json_data}` (at most 4096 encoded JSON bytes) or `{:error, reason}`.
  Exclude credentials, transient state and runtime counters. The normalized value
  must be deterministic across equivalent configurations. Absent callbacks return
  `{:ok, nil}`. Frame restore checks both the trusted template and app-codec result;
  a changed binding rejects before resuming effects, including a first uncertain
  Model request with no response history. Callback errors are normalized, not echoed.
  """
  @callback continuation_binding(model()) :: {:ok, term()} | {:error, term()}

  @optional_callbacks [request_stream: 4, profile: 1, validate_resume: 4, continuation_binding: 1]

  @doc "Returns the bounded, portable static continuation binding; no Model IO."
  def continuation_binding(%mod{} = model) do
    _ = Code.ensure_loaded(mod)

    result =
      if function_exported?(mod, :continuation_binding, 1),
        do: mod.continuation_binding(model),
        else: {:ok, nil}

    with {:ok, data} <- result,
         {:ok, data} <- ExAgent.Tool.JSON.normalize(data) do
      if byte_size(Jason.encode!(data)) <= 4096,
        do: {:ok, data},
        else: {:error, :model_continuation_binding_too_large}
    else
      _ -> {:error, :invalid_model_continuation_binding}
    end
  rescue
    _ -> {:error, :invalid_model_continuation_binding}
  catch
    _, _ -> {:error, :invalid_model_continuation_binding}
  end

  @doc false
  def validate_resume(%mod{} = model, messages, settings, params) do
    _ = Code.ensure_loaded(mod)

    if function_exported?(mod, :validate_resume, 4) do
      case mod.validate_resume(model, messages, settings, params) do
        :ok -> :ok
        {:error, _} = error -> error
        _ -> {:error, :invalid_model_continuation_preflight}
      end
    else
      {:error, :model_continuation_preflight_required}
    end
  rescue
    _ -> {:error, :invalid_model_continuation_preflight}
  catch
    _, _ -> {:error, :invalid_model_continuation_preflight}
  end

  # --- dispatch ------------------------------------------------------------
  @spec request(model(), messages, ModelSettings.t() | nil, ModelRequestParameters.t()) ::
          {:ok, Message.Response.t(), model()} | {:error, term()}
  def request(%mod{} = model, messages, settings, params) do
    if ExAgent.Retention.executable?(messages),
      do: mod.request(model, messages, settings, params),
      else: {:error, :omitted_payload_history}
  end

  @spec request_stream(model(), messages, ModelSettings.t() | nil, ModelRequestParameters.t()) ::
          Enumerable.t()
  def request_stream(%mod{} = model, messages, settings, params) do
    Stream.resource(
      fn ->
        {:open,
         fn ->
           Code.ensure_loaded(mod)

           if not ExAgent.Retention.executable?(messages) do
             [{:error, :omitted_payload_history}]
           else
             if function_exported?(mod, :request_stream, 4) do
               case mod.request_stream(model, messages, settings, params) do
                 {:error, _} = error -> [error]
                 stream -> stream
               end
             else
               [{:error, {:unsupported, :streaming}}]
             end
           end
         end}
      end,
      &stream_next/1,
      &stream_close/1
    )
  end

  defp stream_next({:done, _} = state), do: {:halt, state}

  defp stream_next(state) do
    reduced =
      case state do
        {:open, open} -> Enumerable.reduce(open.(), {:cont, nil}, &suspend_event/2)
        {:next, continuation} -> continuation.({:cont, nil})
      end

    case reduced do
      {:suspended, event, continuation} ->
        case event do
          {:text_delta, text} when is_binary(text) ->
            {[event], {:next, continuation}}

          {:thinking_delta, text} when is_binary(text) ->
            {[event], {:next, continuation}}

          {:usage, %Message.Usage{}} ->
            {[event], {:next, continuation}}

          {:tool_call_delta, %{index: i, fragment: f}} when is_integer(i) and is_binary(f) ->
            {[event], {:next, continuation}}

          {:response, %Message.Response{}, %_{}} ->
            {[event], {:done, continuation}}

          {:error, _} ->
            {[event], {:done, continuation}}

          other ->
            {[{:error, {:invalid_stream_event, other}}], {:done, continuation}}
        end

      {status, _} when status in [:done, :halted] ->
        {[{:error, :incomplete_stream}], {:done, nil}}
    end
  rescue
    # A resumed source owns cleanup when its reduction raises. Its previous
    # continuation has been consumed and must never receive a second halt.
    error -> {[{:error, error}], {:done, nil}}
  catch
    kind, reason -> {[{:error, {kind, reason}}], {:done, nil}}
  end

  defp suspend_event(event, _), do: {:suspend, event}

  defp stream_close({_, continuation}) when is_function(continuation, 1) do
    continuation.({:halt, nil})
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp stream_close(_), do: :ok

  @spec model_name(model()) :: String.t()
  def model_name(%mod{} = model), do: mod.model_name(model)

  @spec system(model()) :: String.t()
  def system(%mod{} = model), do: mod.system(model)

  @spec profile(model()) :: ExAgent.ModelProfile.t()
  def profile(%mod{} = model) do
    Code.ensure_loaded(mod)

    if function_exported?(mod, :profile, 1) do
      mod.profile(model)
    else
      %ExAgent.ModelProfile{}
    end
  end

  @doc """
  Resolve a custom Model struct, Test label, or stock ReqLLM model spec.

  Custom structs are returned unchanged. Catalogue strings, explicit maps, stock
  tuples and `LLMDB.Model` specs resolve through public `ReqLLM.model/1` and use
  `ExAgent.Models.ReqLLM`. Catalogue membership does not enable tools or streaming.
  Pass instance credentials and an explicitly qualified profile with `resolve/2`,
  or construct `ExAgent.Models.ReqLLM` directly. No credentials are read from the
  environment by this resolver. `opencode:` and `zai:` shortcuts require explicit
  spec/endpoint/auth migration; they never silently choose another provider.
  """
  @spec resolve(model() | String.t() | map() | tuple(), keyword()) ::
          {:ok, model()} | {:error, term()}
  def resolve(spec, opts \\ [])
  def resolve(%LLMDB.Model{} = spec, opts), do: resolve_backend(spec, opts)
  def resolve(%_{} = model, []), do: {:ok, model}
  def resolve(%_{}, _), do: {:error, :custom_model_options}
  def resolve("test:" <> rest, []), do: {:ok, %ExAgent.Models.Test{label: rest}}
  def resolve("test", []), do: {:ok, %ExAgent.Models.Test{}}
  def resolve("opencode:" <> _ = spec, opts), do: resolve_shortcut(spec, opts, :opencode)
  def resolve("zai:" <> _ = spec, opts), do: resolve_shortcut(spec, opts, :zai)
  def resolve(spec, opts), do: resolve_backend(spec, opts)

  defp resolve_shortcut(spec, opts, provider) do
    case ReqLLM.model(spec) do
      {:ok, resolved} -> resolve_backend(resolved, opts)
      {:error, _} -> {:error, {:explicit_model_required, provider}}
    end
  end

  defp resolve_backend(spec, opts) do
    with true <- valid_spec_shape?(spec),
         true <-
           Keyword.keyword?(opts) and not Keyword.has_key?(opts, :model) and
             length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))),
         {:ok, resolved} <- ReqLLM.model(spec) do
      {:ok, ExAgent.Models.ReqLLM.new(Keyword.put(opts, :model, resolved))}
    else
      _ -> {:error, :invalid_model_spec_or_options}
    end
  rescue
    _ in [ArgumentError, KeyError] -> {:error, :invalid_model_spec_or_options}
  end

  defp valid_spec_shape?({provider, id, []}), do: is_atom(provider) and is_binary(id)
  defp valid_spec_shape?({_, _, _}), do: false

  defp valid_spec_shape?({provider, [{key, id}]}),
    do: is_atom(provider) and key in [:id, :model] and is_binary(id)

  defp valid_spec_shape?({_, _}), do: false
  defp valid_spec_shape?(_), do: true
end
