defmodule ExAgent.Models.ReqLLM do
  @moduledoc """
  Model adapter over ReqLLM's public one-interaction APIs.

  `:model` accepts a catalogue string or an explicit model spec. Supply `:api_key`
  explicitly; `:base_url` selects an instance/gateway. Anthropic also accepts
  explicit `:auth_token` (Bearer), which takes precedence over `:api_key` through
  stock public OAuth options without enabling subscription behavior. Neither mode
  reads credentials from the environment. Model capabilities for tools
  and image input must be declared in the spec when absent from the catalogue.

  `:http_options` currently accepts `:adapter` (trusted transport injection) and
  `:receive_timeout`. `:provider_options` accepts Anthropic version/top-k,
  stop sequences and Responses `:store` (use `false` for stateless continuation).
  Other options fail explicitly, never override auth, tools,
  history, model or retries. Native JSON output requires the separate explicit
  `output_profile: :chat_json_schema_v1` alongside `tool_profile: :chat_tools_v1`.
  It sends a reference-free object schema via the public `response_format` option,
  with `strict: false`, preserving optional fields and inert defaults. Set the
  agent's `output_mode: :native` with an Ecto module; local schema validation and
  the actual changeset are authoritative, with counted corrective retries.
  Streaming is
  limited to the explicit `:chat_tools_v1` profile below and rejects HTTP `:adapter`
  injection (stock streaming uses its own public transport path).

  Public ReqLLM Response metrics retain this adapter's conservative normalized
  accounting contract. ReqLLM 1.26 adds usage-presence metadata, but its complete
  provider/surface semantics are not qualified as observed host accounting. Metrics are
  exposed as `Usage.accounting` quality `"normalized"`, including zero; unavailable
  metrics remain nil. Public USD totals are estimates converted once to cents.
  Strict metric limits reject this declared normalized contract before IO. Opt in
  to `UsageLimits.accounting: :estimated` with a finite effective request limit
  for retrospective thresholds; neither mode promises an invoice or monetary cap.

  Tools and Ecto tool output require `tool_profile: :chat_tools_v1`, explicit
  `extra: %{wire: %{protocol: "openai_chat"}}` model metadata, tools enabled and
   reasoning disabled, or explicit `reasoning_mode: :none` with truthful reasoning
   enabled, effort supported with `"none"` among its values, and
   thinking.disable_supported=true. None mode sends public reasoning_effort:none,
   requires nil temperature, and maps the sole ModelSettings.max_tokens authority
   (1..4096, default4096) to max_completion_tokens without a duplicate canonical key.
   It rejects exposed reasoning and does not qualify reasoning continuation.
   This non-strict profile validates a mandatory
  wire envelope and a reference-free logical schema subset locally. Defaults remain
  inert and optional fields stay optional. Strict tools and additional provider
  options reject. Callers/hooks use logical objects; continuation2 and call metadata
   identify `exagent.arguments/1`. None mode writes continuation3 with an explicit
   reasoning_mode binding and rejects legacy/different-mode response history.
   Persisted none execution additionally exposes a static, nonsecret Model binding
   checked before and after app-codec load, even before a first response exists.
   Pre-envelope call history rejects, without repair
  or migration by guessing. Other profiles retain the temporary tools guard because
  stock normalization can turn non-object arguments into `{}`. This is offline
  qualification only; consult design8.23 and migration. Custom Model and Test
  remain independent. Anthropic thinking-enabled
  requests and response continuation remain unqualified. ReqLLM 1.26 preserves
  opaque redacted provider blocks; this adapter rejects them explicitly until a
  complete canonical round-trip is qualified;
  accepting the `:thinking` option for validation does not enable that route.

  Receive timeout precedence is request `ModelSettings.timeout`, instance
  `http_options[:receive_timeout]`, then 60 seconds. This is not a total deadline.
  Stock ReqLLM also uses this value as its pool-checkout default; the adapter does
  not expose a separate pool option.
  `:total_timeout` is an optional positive millisecond budget for this single
  buffered ReqLLM operation. Nil inherits the public ReqLLM application default
  (normally infinity). A host guardian applies that deadline and owns one linked
  worker; ReqLLM's internal total timeout is disabled to avoid orphaned nolink HTTP
  work on caller death. Success, exception, timeout and caller death terminate the
  owned worker. This is distinct from the run deadline, does not undo effects and
  does not guarantee cleanup of arbitrary external callback descendants.
  Instructions come from the supplied canonical/projected message history;
  `ModelRequestParameters.instructions` is not independently prepended.

  Streaming is lazy, consumes `ReqLLM.StreamResponse.process_stream/2` once, and
  shares buffered schema/history/response validation. Deltas are provisional;
  only a validated complete terminal authorizes tools or final output. Each new
  enumeration starts one new interaction. Halt, exception, deadline and owner
  death close the public backend response and terminate owned work.

  The qualified stream profile admits at most 4096 public chunks, 65,536 bytes
  per chunk and 1,048,576 bytes summed across chunks, measured **after decode**
  using `:erlang.external_size/1` (serialized representation, not heap size).
  The rejecting chunk has already been allocated upstream. The bridge holds one
  unacknowledged delta; the upstream collector retains O(response) data, and
  upstream queues/accumulators can run ahead. This is not end-to-end backpressure
  or a hard RAM/predecode limit. Canonical input/history and caller-retained events
  are separate; scope request/concurrency/deadline limits remain app-configured.

  Streaming requests default to `max_tokens: 4096` when unset and reject explicit
  values outside 1..4096 before IO. Streaming `total_timeout: nil` means 60,000ms,
  unlike buffered's inherited default; explicit values must be in 1..300,000ms for
  this qualified profile. Slow-consumer waiting counts toward that deadline.
  Completion is timestamped before delivery, preserving timely queued results and
  rejecting late completion even if the guardian timer was delayed. Cancellation
  cannot undo effects from previously completed interactions. Errors without a
  public usage snapshot remain unavailable; this profile does not certify a live
  provider or all ReqLLM models.

  Native stream objects exposed by stock become canonical JSON Text history;
  original JSON whitespace/key ordering is not promised. Any publicly exposed
  refusal rejects. Stock Chat 1.26 can discard a wire refusal field alongside
  valid JSON content, so that content can still produce a locally valid output;
  refusal detection is not a wire-fidelity guarantee. A refusal without valid
  output, malformed/non-object JSON and incomplete terminals never succeed.
  Native output with qualified function tools is supported; tools retain their
  envelope, authority and effect accounting. Provider strict enforcement and
  `parallel_tool_calls: false` are not promised. This is offline qualification,
  pending fresh review/live acceptance as recorded in the roadmap.
  """
  @behaviour ExAgent.Model
  alias Elixir.ReqLLM, as: Backend
  alias ExAgent.{Message, ModelProfile, ModelSettings, RequestError}
  alias Message.{Part, Continuation}
  alias Backend.Message, as: BackendMessage
  alias Backend.Message.ContentPart, as: Content
  alias ExAgent.Models.ReqLLMEnvelope, as: Envelope

  @derive {Inspect, except: [:api_key, :auth_token, :http_options]}
  defstruct [
    :model,
    :api_key,
    :auth_token,
    :base_url,
    :total_timeout,
    :tool_profile,
    :output_profile,
    :reasoning_mode,
    provider_options: [],
    http_options: []
  ]

  @type t :: %__MODULE__{
          model: String.t() | map() | tuple(),
          api_key: String.t() | nil,
          auth_token: String.t() | nil,
          base_url: String.t() | nil,
          total_timeout: pos_integer() | nil,
          tool_profile: :chat_tools_v1 | nil,
          output_profile: :chat_json_schema_v1 | nil,
          reasoning_mode: :none | nil,
          provider_options: keyword(),
          http_options: keyword()
        }
  @spec new(keyword()) :: t()
  def new(opts), do: struct!(__MODULE__, opts)

  @impl true
  def model_name(model) do
    case Backend.model(model.model) do
      {:ok, resolved} -> resolved.id
      _ -> "unresolved"
    end
  end

  @impl true
  def system(model) do
    case Backend.model(model.model) do
      {:ok, resolved} -> to_string(resolved.provider)
      _ -> "req_llm"
    end
  end

  @impl true
  def profile(model) do
    thinking =
      case Backend.model(model.model) do
        {:ok, resolved} ->
          model.reasoning_mode != :none and resolved.provider == :openai and
            get_in(resolved.capabilities || %{}, [:reasoning, :enabled]) == true and
            get_in(resolved.capabilities || %{}, [:reasoning, :thinking, :supported]) != false

        _ ->
          false
      end

    %ModelProfile{
      supports_tools: tools_supported?(model),
      supports_json_schema_output: native_supported?(model),
      supports_json_object_output: false,
      supports_thinking: thinking,
      accounting_quality: :normalized
    }
  end

  @impl true
  def request(model, messages, settings, params),
    do: interaction(model, messages, settings, params, :buffered)

  @impl true
  def validate_resume(model, messages, settings, params),
    do: interaction(model, messages, settings, params, :preflight)

  @impl true
  def continuation_binding(%{reasoning_mode: nil}), do: {:ok, nil}

  def continuation_binding(%{reasoning_mode: :none} = model) do
    with {:ok, resolved} <- Backend.model(model.model),
         true <- none_supported?(model, resolved),
         true <- valid_endpoint?(model.base_url || resolved.base_url),
         true <- model.output_profile in [nil, :chat_json_schema_v1] do
      {:ok,
       %{
         "version" => 1,
         "adapter" => "req_llm",
         "provider" => to_string(resolved.provider),
         "model" => resolved.id,
         "endpoint" => model.base_url || resolved.base_url,
         "tool_profile" => to_string(model.tool_profile),
         "output_profile" => if(model.output_profile, do: to_string(model.output_profile)),
         "reasoning_mode" => "none",
         "capabilities" => %{
           "tools" => Map.take(resolved.capabilities.tools, [:enabled, :strict]),
           "reasoning" => %{
             "enabled" => true,
             "disable_supported" => true,
             "effort_supported" => true,
             "effort_values" =>
               resolved.capabilities.reasoning.effort.values |> Enum.uniq() |> Enum.sort()
           },
           "protocol" => "openai_chat"
         }
       }}
    else
      _ -> {:error, :unsupported_reasoning_mode}
    end
  end

  def continuation_binding(_), do: {:error, :unsupported_reasoning_mode}

  defp interaction(model, messages, settings, params, mode) do
    with {:ok, resolved} <- Backend.model(model.model) do
      endpoint = model.base_url || resolved.base_url
      validate_config!(model, endpoint)
      validate_auth!(model, resolved)
      validate_reasoning_mode!(model, resolved)
      validate_tool_profile!(model, resolved)
      validate_output_profile!(model)
      validate_continuation_support!(model, resolved, messages)
      settings = settings || %ModelSettings{}
      settings = stream_settings!(model, settings, mode)
      settings = reasoning_settings!(model, settings)

      definitions =
        if tools_supported?(model),
          do: Envelope.prepare!(params.function_tools ++ params.output_tools),
          else: %{}

      opts = options!(model, settings, params, endpoint, definitions)
      context = context!(messages, resolved, endpoint, model, definitions)

      if mode == :preflight do
        :ok
      else
        case invoke(model, resolved, context, opts, mode) do
          {:ok, response} ->
            if response.finish_reason in [:stop, :tool_calls] do
              {:ok,
               response!(response, resolved, endpoint, model, definitions, params.output_mode),
               model}
            else
              {:error,
               %RequestError{
                 provider: resolved.provider,
                 reason: {:incomplete_response, response.finish_reason},
                 partial_response:
                   partial_response(
                     response,
                     resolved,
                     endpoint,
                     model,
                     definitions,
                     params.output_mode
                   )
               }}
            end

          {:error, error} ->
            {:error, safe_error(error, resolved.provider)}
        end
      end
    else
      {:error, _} -> {:error, %RequestError{provider: :req_llm, reason: :invalid_model}}
    end
  rescue
    _ in [ArgumentError, KeyError, FunctionClauseError] ->
      {:error, %RequestError{provider: :req_llm, reason: :invalid_message_or_options}}

    error ->
      {:error, safe_error(error, :req_llm)}
  catch
    {:req_llm_adapter, reason} -> {:error, %RequestError{provider: :req_llm, reason: reason}}
  end

  defp partial_response(response, resolved, endpoint, model, definitions, output_mode) do
    response!(response, resolved, endpoint, model, definitions, output_mode)
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  @impl true
  def request_stream(%{tool_profile: nil}, _, _, _), do: {:error, {:unsupported, :streaming}}

  def request_stream(model, messages, settings, params) do
    timeout = model.total_timeout || 60_000

    if is_integer(timeout) and timeout > 0 and timeout <= 300_000 do
      ExAgent.Models.ReqLLMStream.new(
        fn register, emit ->
          case interaction(model, messages, settings, params, {:stream, register, emit}) do
            {:ok, response, final_model} -> {:response, response, final_model}
            {:error, _} = error -> error
          end
        end,
        timeout
      )
    else
      {:error, %RequestError{provider: :req_llm, reason: {:invalid_option, :total_timeout}}}
    end
  end

  defp stream_settings!(_, settings, mode) when mode in [:buffered, :preflight], do: settings

  defp stream_settings!(model, settings, {:stream, _, _}) do
    unless tools_supported?(model), do: fail!({:unsupported, :streaming})

    if Keyword.has_key?(model.http_options, :adapter),
      do: fail!({:unsupported_options, :stream_http_adapter})

    max_tokens = settings.max_tokens || 4096

    unless is_integer(max_tokens) and max_tokens > 0 and max_tokens <= 4096,
      do: fail!({:invalid_option, :stream_max_tokens})

    %{settings | max_tokens: max_tokens}
  end

  defp invoke(model, resolved, context, opts, :buffered) do
    ExAgent.Models.ReqLLMBuffered.run(
      fn ->
        Backend.generate_text(resolved, context, Keyword.put(opts, :total_timeout, :infinity))
      end,
      model.total_timeout
    )
  end

  defp invoke(_, resolved, context, opts, {:stream, register, emit}) do
    case Backend.stream_text(resolved, context, Keyword.put(opts, :total_timeout, :infinity)) do
      {:ok, stream} ->
        register.(stream)
        ExAgent.Models.ReqLLMStream.process(stream, emit)

      {:error, _} = error ->
        error
    end
  end

  defp fail!(reason), do: throw({:req_llm_adapter, reason})

  defp tools_supported?(%{tool_profile: :chat_tools_v1} = model) do
    case Backend.model(model.model) do
      {:ok, resolved} -> chat_tools_model?(resolved, model.reasoning_mode)
      _ -> false
    end
  end

  defp tools_supported?(_), do: false

  defp native_supported?(%{output_profile: :chat_json_schema_v1} = model),
    do: tools_supported?(model)

  defp native_supported?(_), do: false

  defp validate_output_profile!(%{output_profile: nil}), do: :ok

  defp validate_output_profile!(model) do
    unless native_supported?(model), do: fail!({:unsupported, :output_profile})
  end

  defp chat_tools_model?(resolved, mode) do
    resolved.provider == :openai and
      reasoning_admitted?(resolved, mode) and
      get_in(resolved.capabilities || %{}, [:tools, :enabled]) == true and
      get_in(resolved.capabilities || %{}, [:tools, :strict]) != true and
      get_in(Continuation.metadata!(resolved.extra || %{}), ["wire", "protocol"]) == "openai_chat"
  end

  defp validate_tool_profile!(%{tool_profile: nil}, _), do: :ok

  defp validate_tool_profile!(%{tool_profile: :chat_tools_v1} = model, resolved) do
    unless chat_tools_model?(resolved, model.reasoning_mode),
      do: fail!({:unsupported, :tool_profile})
  end

  defp validate_tool_profile!(_, _), do: fail!({:unsupported, :tool_profile})

  defp reasoning_admitted?(resolved, nil),
    do: get_in(resolved.capabilities || %{}, [:reasoning, :enabled]) == false

  defp reasoning_admitted?(resolved, :none) do
    caps = resolved.capabilities || %{}

    get_in(caps, [:reasoning, :enabled]) == true and
      get_in(caps, [:reasoning, :effort, :supported]) == true and
      "none" in (get_in(caps, [:reasoning, :effort, :values]) || []) and
      get_in(caps, [:reasoning, :thinking, :disable_supported]) == true
  end

  defp reasoning_admitted?(_, _), do: false

  defp none_supported?(model, resolved),
    do: model.tool_profile == :chat_tools_v1 and chat_tools_model?(resolved, :none)

  defp validate_reasoning_mode!(%{reasoning_mode: nil}, _), do: :ok

  defp validate_reasoning_mode!(%{reasoning_mode: :none} = model, resolved) do
    unless none_supported?(model, resolved), do: fail!({:unsupported, :reasoning_mode})
  end

  defp validate_reasoning_mode!(_, _), do: fail!({:invalid_option, :reasoning_mode})

  defp reasoning_settings!(%{reasoning_mode: :none}, settings) do
    unless is_nil(settings.temperature), do: fail!({:invalid_option, :reasoning_none_temperature})
    max_tokens = settings.max_tokens || 4096

    unless is_integer(max_tokens) and max_tokens in 1..4096,
      do: fail!({:invalid_option, :reasoning_none_max_tokens})

    %{settings | max_tokens: max_tokens}
  end

  defp reasoning_settings!(_, settings), do: settings

  # Remove these temporary admission guards only after the public dependency
  # preserves argument identity and complete reasoning continuation data.
  defp validate_continuation_support!(model, %{provider: :anthropic} = resolved, messages) do
    if Keyword.has_key?(model.provider_options, :thinking) or
         get_in(resolved.capabilities || %{}, [:reasoning, :enabled]) != false or
         Enum.any?(messages, &match?(%Message.Response{}, &1)),
       do: fail!({:unsupported, :anthropic_reasoning_continuation})
  end

  defp validate_continuation_support!(_, _, _), do: :ok

  defp validate_config!(model, endpoint) do
    credential = if is_nil(model.auth_token), do: model.api_key, else: model.auth_token
    unless is_binary(credential) and credential != "", do: fail!(:missing_credentials)

    unless is_nil(model.total_timeout) or
             (is_integer(model.total_timeout) and model.total_timeout > 0),
           do: fail!({:invalid_option, :total_timeout})

    if endpoint do
      uri = URI.parse(endpoint)

      unless uri.scheme in ["http", "https"] and is_binary(uri.host) and
               is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment),
             do: fail!(:invalid_base_url)
    end

    allow_keys!(model.http_options, [:adapter, :receive_timeout], :http_options)

    allow_keys!(
      model.provider_options,
      [:thinking, :anthropic_version, :anthropic_top_k, :stop_sequences, :store],
      :provider_options
    )
  end

  defp valid_endpoint?(nil), do: true

  defp valid_endpoint?(endpoint) when is_binary(endpoint) do
    uri = URI.parse(endpoint)

    uri.scheme in ["http", "https"] and is_binary(uri.host) and
      is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment)
  end

  defp valid_endpoint?(_), do: false

  defp validate_auth!(%{auth_token: nil}, _), do: :ok
  defp validate_auth!(_, %{provider: :anthropic}), do: :ok
  defp validate_auth!(_, _), do: fail!({:unsupported, :auth_token})

  defp allow_keys!(opts, allowed, kind) do
    unless Keyword.keyword?(opts) and
             length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
             Enum.all?(Keyword.keys(opts), &(&1 in allowed)),
           do: fail!({:unsupported_options, kind})
  end

  defp options!(model, settings, params, endpoint, definitions) do
    if tools_supported?(model) and model.provider_options != [],
      do: fail!({:unsupported_options, :tool_profile})

    unless settings.extra == %{}, do: fail!({:unsupported_options, :extra})
    provider_options = output_options!(model, params)

    if params.function_tools ++ params.output_tools != [] and not profile(model).supports_tools,
      do: fail!({:unsupported, :tools})

    tools =
      Enum.map(params.function_tools ++ params.output_tools, fn tool ->
        Backend.Tool.new!(
          name: tool.name,
          description: tool.description || "",
          parameter_schema: Map.fetch!(definitions, tool.name).wire,
          strict: false,
          callback: fn _ -> {:error, :execution_owned_by_exagent} end
        )
      end)

    (auth_options(model) ++
       [
         base_url: endpoint,
         tools: tools,
         tool_choice: if(params.allow_text_output, do: :auto, else: :required),
         max_retries: 0,
         json_repair: false,
         total_timeout: model.total_timeout,
         on_unsupported: :error,
         provider_options: provider_options,
         req_http_options: retry_http_options!(model, params),
         max_tokens: settings.max_tokens,
         temperature: settings.temperature,
         top_p: settings.top_p,
         presence_penalty: settings.presence_penalty,
         frequency_penalty: settings.frequency_penalty,
         receive_timeout: settings.timeout || model.http_options[:receive_timeout] || 60_000
       ])
    |> Enum.reject(fn {_, value} -> is_nil(value) end)
    |> reasoning_options!(model, settings)
  end

  defp reasoning_options!(options, %{reasoning_mode: :none}, settings) do
    options
    |> Keyword.delete(:max_tokens)
    |> Keyword.put(:reasoning_effort, :none)
    |> Keyword.update!(
      :provider_options,
      &Keyword.put(&1, :max_completion_tokens, settings.max_tokens)
    )
  end

  defp reasoning_options!(options, _, _), do: options

  defp output_options!(model, %{output_mode: :native} = params) do
    unless native_supported?(model), do: fail!({:unsupported, :native_output})

    unless params.output_tools == [] and is_map(params.output_object),
      do: fail!({:unsupported, :native_output_contract})

    schema = Envelope.schema!(params.output_object.json_schema)
    unless is_map(schema), do: fail!({:unsupported, :native_schema_root})

    [
      response_format: %{
        type: "json_schema",
        json_schema: %{name: "final_result", strict: false, schema: schema}
      }
    ]
  end

  defp output_options!(model, %{output_mode: mode}) when mode in [:text, :tool, :auto],
    do: model.provider_options

  defp output_options!(_, _), do: fail!({:unsupported, :native_output})

  defp retry_http_options!(model, params) do
    http = model.http_options |> Keyword.delete(:receive_timeout) |> Keyword.put(:redirect, false)

    case params.idempotency_key do
      nil ->
        http

      key ->
        unless tools_supported?(model) and ExAgent.Continuation.Retry.key?(key),
          do: fail!({:unsupported, :idempotency_transport})

        Keyword.put(http, :headers, [{"idempotency-key", key}])
    end
  end

  defp auth_options(%{auth_token: nil, api_key: key}), do: [api_key: key]

  defp auth_options(%{auth_token: token}),
    do: [auth_mode: :oauth, access_token: token]

  defp context!(messages, resolved, endpoint, model, definitions) do
    unless ExAgent.Retention.executable?(messages), do: fail!(:omitted_payload_history)
    msgs = Enum.flat_map(messages, &message!(&1, resolved, endpoint, model, definitions))

    case Backend.Context.normalize(msgs) do
      {:ok, context} -> context
      {:error, _} -> fail!(:invalid_history)
    end
  end

  defp message!(%Message.Request{} = request, resolved, _, _, _) do
    prefix =
      if is_binary(request.instructions),
        do: [%BackendMessage{role: :system, content: [Content.text(request.instructions)]}],
        else: []

    prefix ++
      Enum.map(request.parts, fn
        %Part.System{content: text} ->
          %BackendMessage{role: :system, content: text_content!(text)}

        %Part.User{content: content} ->
          %BackendMessage{role: :user, content: user_content!(content, resolved)}

        %Part.ToolReturn{} = part ->
          tool_result(part.tool_call_id, part.tool_name, part.content, part.status != :succeeded)

        %Part.Retry{tool_call_id: id} = part when is_binary(id) ->
          tool_result(id, part.tool_name, part.content, true)

        %Part.Retry{content: content} ->
          %BackendMessage{role: :user, content: [Content.text(stringify(content))]}

        _ ->
          fail!({:unsupported, :request_part})
      end)
  end

  defp message!(%Message.Response{} = response, resolved, endpoint, model, definitions) do
    continuation = Continuation.validate!(response.continuation)

    unless (model.reasoning_mode == :none and
              match?(%{"version" => 3, "reasoning_mode" => "none"}, continuation)) or
             (is_nil(model.reasoning_mode) and not match?(%{"version" => 3}, continuation)),
           do: fail!(:continuation_mode_mismatch)

    if continuation &&
         (continuation["provider"] != to_string(resolved.provider) or
            continuation["model"] != resolved.id or continuation["endpoint"] != endpoint),
       do: fail!(:continuation_target_mismatch)

    {parts, calls} = Enum.split_with(response.parts, &(not match?(%Part.ToolCall{}, &1)))

    if (tools_supported?(model) and continuation) && continuation["reasoning_details"] != [],
      do: fail!({:unsupported, :tool_profile_content})

    if calls != [] do
      unless tools_supported?(model), do: fail!({:unsupported, :tool_argument_fidelity})

      unless match?(
               %{"version" => version, "arguments_codec" => "exagent.arguments/1"}
               when version in [2, 3],
               continuation
             ),
             do: fail!({:unsupported, :tool_history_codec})
    end

    content =
      Enum.map(parts, fn
        %Part.Text{} = part ->
          Content.text(part.content, part.metadata |> metadata!() |> put_if(:id, part.id))

        %Part.Thinking{} = part ->
          if tools_supported?(model), do: fail!({:unsupported, :tool_profile_content})

          Content.thinking(
            part.content,
            part.metadata
            |> metadata!()
            |> put_if(:id, part.id)
            |> put_if(:signature, part.signature)
          )

        _ ->
          fail!({:unsupported, :response_part})
      end)

    tool_calls =
      Enum.map(calls, fn call ->
        unless is_binary(call.tool_call_id) and call.tool_call_id != "",
          do: fail!(:missing_tool_call_id)

        Backend.ToolCall.new(
          call.tool_call_id,
          call.tool_name,
          Envelope.encode!(call, definitions)
        )
        |> Backend.ToolCall.put_metadata(metadata!(call.metadata))
      end)

    [
      %BackendMessage{
        role: :assistant,
        content: content,
        tool_calls: tool_calls,
        metadata: if(continuation, do: metadata!(continuation["message_metadata"]), else: %{}),
        reasoning_details:
          if(continuation,
            do: Enum.map(continuation["reasoning_details"], &reasoning!(&1, resolved)),
            else: nil
          )
      }
    ]
  end

  defp message!(_, _, _, _, _), do: fail!(:invalid_history)

  defp text_content!(text) when is_binary(text), do: [Content.text(text)]
  defp text_content!(_), do: fail!({:unsupported, :system_content})
  defp user_content!(text, _) when is_binary(text), do: [Content.text(text)]

  defp user_content!(parts, resolved) when is_list(parts) do
    Enum.map(parts, fn part ->
      part = Continuation.metadata!(part)

      case part do
        %{"type" => "text", "text" => text} when is_binary(text) and map_size(part) == 2 ->
          Content.text(text)

        %{"type" => "image_url", "url" => url} when is_binary(url) and map_size(part) == 2 ->
          image_allowed!(resolved)
          unless URI.parse(url).scheme in ["http", "https", "data"], do: fail!(:invalid_image_url)
          Content.image_url(url)

        %{"type" => "image", "data" => data, "media_type" => media}
        when is_binary(data) and is_binary(media) and map_size(part) == 3 ->
          image_allowed!(resolved)

          case Base.decode64(data) do
            {:ok, bytes} -> Content.image(bytes, media)
            :error -> fail!(:invalid_image_data)
          end

        _ ->
          fail!({:unsupported, :input_content})
      end
    end)
  end

  defp user_content!(_, _), do: fail!({:unsupported, :input_content})

  defp image_allowed!(resolved) do
    unless :image in ((resolved.modalities || %{})[:input] || []),
      do: fail!({:unsupported, :image_input})
  end

  defp tool_result(id, name, content, error?) do
    %BackendMessage{
      role: :tool,
      tool_call_id: id,
      name: name,
      content: [Content.text(stringify(content))],
      metadata: %{is_error: error?}
    }
  end

  defp stringify(text) when is_binary(text), do: text
  defp stringify(data), do: Jason.encode!(data)

  defp response!(response, resolved, endpoint, model, definitions, output_mode) do
    if output_mode == :native and Backend.Response.refusals(response) != [],
      do: fail!({:unsupported, :refused_output})

    if Backend.Response.tool_calls(response) != [] and not tools_supported?(model),
      do: fail!({:unsupported, :tool_argument_fidelity})

    %BackendMessage{} = message = response.message

    if tools_supported?(model) and
         ((message.reasoning_details || []) != [] or
            Enum.any?(message.content, fn part ->
              part.type != :text and not (output_mode == :native and part.type == :object)
            end)),
       do: fail!({:unsupported, :tool_profile_content})

    if resolved.provider == :anthropic and
         ((message.reasoning_details || []) != [] or
            Enum.any?(message.content, &(&1.type == :thinking))),
       do: fail!({:unsupported, :anthropic_reasoning_continuation})

    parts =
      Enum.map(message.content, fn
        %{type: :object, object: object} when output_mode == :native and is_map(object) ->
          %Part.Text{content: Jason.encode!(object)}

        %Content{type: :text, text: text, metadata: metadata} when is_binary(text) ->
          metadata = Continuation.metadata!(metadata)
          %Part.Text{content: text, id: metadata["id"], metadata: Map.delete(metadata, "id")}

        %Content{type: :thinking, text: text, metadata: metadata} ->
          metadata = Continuation.metadata!(metadata)

          %Part.Thinking{
            content: text || "",
            id: metadata["id"],
            signature: metadata["signature"],
            metadata: Map.drop(metadata, ["id", "signature"])
          }

        _ ->
          fail!({:unsupported, :output_content})
      end)

    calls =
      Enum.map(Backend.Response.tool_calls(response), fn call ->
        if Backend.ToolCall.builtin?(call) or Backend.ToolCall.provider_native?(call),
          do: fail!({:unsupported, :provider_owned_tool})

        %Part.ToolCall{
          tool_name: call.function.name,
          args: Envelope.decode!(call, definitions),
          tool_call_id: call.id,
          metadata:
            Backend.ToolCall.metadata(call)
            |> Continuation.metadata!()
            |> Map.put("arguments_codec", Envelope.codec())
        }
      end)

    ids = Enum.map(calls, & &1.tool_call_id)

    unless Enum.all?(ids, &(is_binary(&1) and &1 != "")) and length(ids) == length(Enum.uniq(ids)),
      do: fail!(:invalid_tool_call_ids)

    continuation = %{
      "version" => 1,
      "provider" => to_string(resolved.provider),
      "model" => resolved.id,
      "endpoint" => endpoint,
      "message_metadata" => Continuation.metadata!(message.metadata),
      "reasoning_details" => Enum.map(message.reasoning_details || [], &portable_reasoning/1)
    }

    continuation =
      if tools_supported?(model),
        do: continuation |> Map.put("version", 2) |> Map.put("arguments_codec", Envelope.codec()),
        else: continuation

    continuation =
      if model.reasoning_mode == :none,
        do: continuation |> Map.put("version", 3) |> Map.put("reasoning_mode", "none"),
        else: continuation

    Message.new_response(parts ++ calls,
      model_name: resolved.id,
      finish_reason: response.finish_reason,
      usage:
        ExAgent.Message.Usage.normalized(
          Backend.Response.usage(response),
          usage_currency(resolved)
        ),
      continuation: Continuation.validate!(continuation)
    )
  end

  defp usage_currency(%{pricing: pricing}) when is_map(pricing) do
    case Map.get(pricing, :components, Map.get(pricing, "components", [])) do
      [] -> "USD"
      _ -> Map.get(pricing, :currency, Map.get(pricing, "currency"))
    end
  end

  defp usage_currency(_), do: "USD"

  defp portable_reasoning(detail) do
    %{
      "text" => detail.text,
      "signature" => detail.signature,
      "encrypted" => detail.encrypted?,
      "provider" => if(detail.provider, do: to_string(detail.provider)),
      "format" => detail.format,
      "index" => detail.index,
      "provider_data" => Continuation.metadata!(detail.provider_data)
    }
  end

  defp reasoning!(data, resolved) do
    provider =
      Enum.find(
        [nil, resolved.provider, :openai, :anthropic, :google, :openrouter, :unknown],
        fn value -> if(value, do: to_string(value)) == data["provider"] end
      )

    if data["provider"] && is_nil(provider), do: fail!(:invalid_reasoning_provider)

    %BackendMessage.ReasoningDetails{
      text: data["text"],
      signature: data["signature"],
      encrypted?: data["encrypted"],
      provider: provider,
      format: data["format"],
      index: data["index"],
      provider_data: data["provider_data"]
    }
  end

  @metadata_keys ~w(response_id signature thought_signature id encrypted? redacted data is_error)a
  defp metadata!(data) do
    data = Continuation.metadata!(data)

    Enum.reduce(@metadata_keys, data, fn key, acc ->
      case Map.pop(acc, Atom.to_string(key)) do
        {nil, _} -> acc
        {value, rest} -> Map.put(rest, key, value)
      end
    end)
  end

  defp put_if(map, _, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp safe_error(%Backend.Error.API.Timeout{kind: :total}, provider),
    do: %RequestError{provider: provider, reason: {:timeout, :total}}

  defp safe_error(error, provider) do
    status = if is_map(error), do: Map.get(error, :status)
    %RequestError{provider: provider, status: status, reason: :model_request_failed}
  end
end
