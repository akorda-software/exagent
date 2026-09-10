defmodule ExAgent.Providers.OpenAIChat do
  @moduledoc """
  Shared implementation for any provider that speaks the OpenAI **Chat
  Completions** wire format (`/v1/chat/completions`). This covers OpenAI itself
  and OpenRouter (and DeepSeek, Groq, Together, etc.).

  The two directions every provider needs:

    * **encode** — our `Message` history → the `messages` array the API expects
      (roles `system` / `user` / `assistant` / `tool`), and our `Tool` list →
      the `tools` array.
    * **decode** — the API JSON response back into our `Message.Response` with
      `TextPart` / `ToolCallPart` parts and `Usage`.

  Providers are thin structs carrying `{:model, :api_key, :base_url,
  :extra_headers}`; `request/4` reads those fields generically, so the same code
  drives `%OpenAI{}` and `%OpenRouter{}`.
  """

  alias ExAgent.{Message, ModelSettings, ModelRequestParameters, Tool}
  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Providers.{SSE, StreamTransport, EventStream}

  @default_timeout 60_000

  @doc "Perform a (non-streaming) chat-completions request."
  @spec request(struct(), [Message.t()], ModelSettings.t() | nil, ModelRequestParameters.t()) ::
          {:ok, Response.t(), struct()} | {:error, term()}
  def request(model, messages, settings, params) do
    config = config(model)

    with :ok <- ensure_credentials(config) do
      body = build_body(config, messages, settings, params)
      headers = build_headers(config)

      http_opts = [
        url: String.trim_trailing(config.base_url, "/") <> "/chat/completions",
        method: :post,
        headers: headers,
        json: body,
        retry: false,
        redirect: false,
        finch: ExAgent.Finch,
        receive_timeout: settings_timeout(settings) || @default_timeout
      ]

      case Req.request(http_opts) do
        {:ok, %{status: 200, body: resp_body}} ->
          case parse_body(resp_body, config) do
            {:ok, resp} -> {:ok, resp, model}
            {:error, _} = e -> e
          end

        {:ok, %{status: status, body: body}} ->
          {:error,
           %ExAgent.RequestError{
             provider: config.provider,
             status: status,
             reason: :http_error,
             body: body
           }}

        {:error, %{reason: :timeout} = exception} ->
          {:error,
           %ExAgent.RequestError{
             provider: config.provider,
             reason: :timeout,
             body: inspect(exception)
           }}

        {:error, exception} ->
          {:error,
           %ExAgent.RequestError{
             provider: config.provider,
             reason: :request_failed,
             body: inspect(exception)
           }}
      end
    end
  end

  defp ensure_credentials(%{api_key: nil, provider: provider}),
    do: {:error, %ExAgent.RequestError{provider: provider, reason: :missing_credentials}}

  defp ensure_credentials(%{api_key: "", provider: provider}),
    do: {:error, %ExAgent.RequestError{provider: provider, reason: :missing_credentials}}

  defp ensure_credentials(_), do: :ok

  defp settings_timeout(%ModelSettings{timeout: t}), do: t
  defp settings_timeout(_), do: nil

  @doc false
  # Pure body classification used by `request/4` — kept public so it can be
  # unit-tested without a network (provider error bodies vs. normal responses).
  @spec parse_body(map(), struct()) ::
          {:ok, Response.t()} | {:error, ExAgent.RequestError.t()}
  def parse_body(%{"error" => error}, config) do
    {:error,
     %ExAgent.RequestError{
       provider: config.provider,
       reason: :provider_error,
       body: if(is_map(error), do: error["message"] || inspect(error), else: error)
     }}
  end

  def parse_body(body, config), do: {:ok, parse_response(body, config)}

  @doc """
  Perform a streaming chat-completions request. Returns a lazy stream of:

    * `{:text_delta, binary}` — incremental text,
    * `{:thinking_delta, binary}` — optional reasoning content,
    * `{:usage, Usage.t()}` — latest per-request usage snapshot (not an additive delta),
    * `{:response, Response.t(), final_model}` — the single final assembled response,
    * `{:error, reason}` on failure.
  """
  @spec request_stream(
          struct(),
          [Message.t()],
          ModelSettings.t() | nil,
          ModelRequestParameters.t()
        ) ::
          Enumerable.t()
  def request_stream(model, messages, settings, params) do
    Stream.flat_map([:start], fn _ ->
      config = config(model)
      opts = StreamTransport.options!(Map.get(model, :stream_options, []))

      case ensure_credentials(config) do
        :ok ->
          body =
            build_body(config, messages, settings, params)
            |> Map.put("stream", true)
            |> Map.put("stream_options", %{"include_usage" => true})

          [
            url: String.trim_trailing(config.base_url, "/") <> "/chat/completions",
            method: :post,
            headers: build_headers(config),
            json: body,
            finch: ExAgent.Finch,
            receive_timeout: settings_timeout(settings) || @default_timeout
          ]
          |> StreamTransport.stream(opts)
          |> SSE.stream(opts)
          |> adapt_stream(model)

        {:error, _} = error ->
          [error]
      end
    end)
  end

  @doc false
  def adapt_stream(sse, model) do
    acc = %{
      text: "",
      thinking: "",
      usage: nil,
      model: model.model,
      tool_calls: %{},
      finish_reason: nil
    }

    EventStream.transform(sse, acc, fn event, acc -> stream_step(event, acc, model) end)
  end

  defp stream_step(:done, acc, model) do
    cond do
      is_nil(acc.finish_reason) -> stream_error(:missing_finish_reason, acc, model)
      not valid_stream_tools?(acc.tool_calls) -> stream_error(:invalid_tool_arguments, acc, model)
      true -> {:halt, [{:response, build_streamed_response(acc), model}], acc}
    end
  end

  defp stream_step(:eof, acc, model), do: stream_error(:missing_stream_terminal, acc, model)
  defp stream_step({:error, reason}, acc, model), do: stream_error(reason, acc, model)

  defp stream_step(%{"error" => error}, acc, model),
    do: stream_error({:provider_error, error}, acc, model)

  defp stream_step(%{"choices" => choices} = chunk, acc, model) when is_list(choices) do
    choice = List.first(choices) || %{}
    delta = if is_map(choice), do: choice["delta"] || %{}, else: nil

    if is_map(delta) do
      text = delta["content"] || ""
      thinking = delta["reasoning_content"] || delta["reasoning"] || ""
      calls = delta["tool_calls"] || []

      with true <-
             is_binary(text) and is_binary(thinking) and is_list(calls) and
               (is_nil(chunk["usage"]) or is_map(chunk["usage"])) and
               (is_nil(chunk["model"]) or is_binary(chunk["model"])) and
               (is_nil(choice["finish_reason"]) or is_binary(choice["finish_reason"])),
           {:ok, tools} <- append_stream_tools(calls, acc.tool_calls) do
        acc = %{
          acc
          | text: acc.text <> text,
            thinking: acc.thinking <> thinking,
            usage: merge_stream_usage(acc.usage, chunk["usage"]),
            tool_calls: tools,
            model: chunk["model"] || acc.model,
            finish_reason: choice["finish_reason"] || acc.finish_reason
        }

        usage_events = if is_map(chunk["usage"]), do: [{:usage, parse_usage(acc.usage)}], else: []

        events =
          delta_event(:text_delta, text) ++ delta_event(:thinking_delta, thinking) ++ usage_events

        {:cont, events, acc}
      else
        _ -> stream_error(:invalid_stream_chunk, acc, model)
      end
    else
      stream_error(:invalid_stream_chunk, acc, model)
    end
  end

  defp stream_step(%{"usage" => usage} = chunk, acc, model) when is_map(usage) do
    if Map.has_key?(chunk, "choices"),
      do: stream_error(:invalid_stream_chunk, acc, model),
      else: stream_step(Map.put(chunk, "choices", []), acc, model)
  end

  defp stream_step(_, acc, model), do: stream_error(:invalid_stream_chunk, acc, model)

  defp append_stream_tools(calls, initial) do
    Enum.reduce_while(calls, {:ok, initial}, fn
      %{"index" => index} = call, {:ok, tools} when is_integer(index) and index >= 0 ->
        fun = call["function"] || %{}
        old = Map.get(tools, index, %{id: nil, name: nil, arguments: ""})

        if is_map(fun) and (is_nil(fun["arguments"]) or is_binary(fun["arguments"])) and
             (is_nil(fun["name"]) or is_binary(fun["name"])) and
             (is_nil(call["id"]) or is_binary(call["id"])) and
             (is_nil(old.id) or is_nil(call["id"]) or old.id == call["id"]) do
          entry = %{
            id: call["id"] || old.id,
            name: if(is_nil(fun["name"]), do: old.name, else: (old.name || "") <> fun["name"]),
            arguments: old.arguments <> (fun["arguments"] || "")
          }

          {:cont, {:ok, Map.put(tools, index, entry)}}
        else
          {:halt, :error}
        end

      _, _ ->
        {:halt, :error}
    end)
  end

  defp valid_stream_tools?(tools) do
    Enum.all?(tools, fn {_, tool} ->
      is_binary(tool.name) and tool.name != "" and is_binary(tool.id) and tool.id != "" and
        match?({:ok, args} when is_map(args), Jason.decode(tool.arguments))
    end)
  end

  defp merge_stream_usage(old, new) when is_map(new), do: Map.merge(old || %{}, new)
  defp merge_stream_usage(old, _), do: old
  defp delta_event(_, ""), do: []
  defp delta_event(type, text), do: [{type, text}]

  defp stream_error(reason, acc, model) do
    {reason, status, body} =
      case reason do
        {:http_error, status, body} -> {:http_error, status, body}
        {:provider_error, body} -> {:provider_error, nil, body}
        %{reason: :timeout} = exception -> {:timeout, nil, inspect(exception)}
        %_{} = exception -> {:request_failed, nil, inspect(exception)}
        reason -> {reason, nil, nil}
      end

    error = %ExAgent.RequestError{
      provider: config(model).provider,
      reason: reason,
      status: status,
      body: body,
      partial_response: partial_stream_response(acc),
      model: model
    }

    {:halt, [{:error, error}], acc}
  end

  defp partial_stream_response(%{text: "", thinking: "", usage: nil, tool_calls: calls})
       when map_size(calls) == 0, do: nil

  defp partial_stream_response(acc), do: build_streamed_response(acc)

  defp build_streamed_response(acc) do
    text_part = if acc.text == "", do: [], else: [%Part.Text{content: acc.text}]

    tool_call_parts =
      acc.tool_calls
      |> Enum.sort_by(fn {idx, _} -> idx end)
      |> Enum.map(fn {_idx, e} ->
        %Part.ToolCall{
          tool_name: e.name,
          # `arguments` is a JSON string accumulated across chunks; ExAgent's
          # decode_args parses it via Part.ToolCall.args_as_map/1, so we keep
          # the raw string here (matching the non-streaming path).
          args: e.arguments,
          tool_call_id: e.id,
          kind: :function
        }
      end)

    thinking_part = if acc.thinking == "", do: [], else: [%Part.Thinking{content: acc.thinking}]
    parts = thinking_part ++ text_part ++ tool_call_parts
    finish = parse_finish_reason(acc.finish_reason)

    Message.new_response(parts,
      usage: acc.usage && parse_usage(acc.usage),
      model_name: acc.model,
      finish_reason: finish
    )
  end

  defmodule Config do
    @moduledoc false
    defstruct [:model, :api_key, :base_url, :system, provider: :openai, extra_headers: []]

    @type t :: %__MODULE__{
            model: String.t(),
            api_key: String.t() | nil,
            base_url: String.t(),
            system: String.t(),
            provider: atom(),
            extra_headers: [{String.t(), String.t()}]
          }
  end

  # Extract a Config from a provider struct (OpenAI/OpenRouter share the fields).
  defp config(%{
         __struct__: mod,
         model: model,
         api_key: key,
         base_url: base,
         extra_headers: extra
       }) do
    %Config{
      model: model,
      api_key: key || env_key(mod),
      base_url: base || default_base_url(mod),
      system: Atom.to_string(mod) |> String.split(".") |> List.last() |> String.downcase(),
      provider: provider(mod),
      extra_headers: extra || []
    }
  end

  defp provider(ExAgent.Models.OpenAI), do: :openai
  defp provider(ExAgent.Models.OpenRouter), do: :openrouter
  defp provider(ExAgent.Models.OpenCode), do: :opencode
  defp provider(_), do: :openai

  defp env_key(ExAgent.Models.OpenAI), do: System.get_env("OPENAI_API_KEY")
  defp env_key(ExAgent.Models.OpenRouter), do: System.get_env("OPENROUTER_API_KEY")
  defp env_key(ExAgent.Models.OpenCode), do: System.get_env("OPENCODE_API_KEY")
  defp env_key(_), do: nil

  defp default_base_url(ExAgent.Models.OpenAI), do: "https://api.openai.com/v1"
  defp default_base_url(ExAgent.Models.OpenRouter), do: "https://openrouter.ai/api/v1"
  defp default_base_url(ExAgent.Models.OpenCode), do: ExAgent.Models.OpenCode.base_url(:go)
  defp default_base_url(_), do: "https://api.openai.com/v1"

  # ----- request body ------------------------------------------------------
  defp build_body(%Config{model: model}, messages, settings, params) do
    tools = build_tools(params)

    %{}
    |> maybe_put("tool_choice", tool_choice(params, tools))
    |> put_extra(settings)
    |> Map.put("model", model)
    |> Map.put("messages", to_openai_messages(messages))
    |> maybe_put("stream", false)
    |> put_settings(settings)
    |> maybe_put("tools", tools)
  end

  # Normalize top-level JSON keys before merging so atom keys cannot bypass the
  # protected fields or produce duplicate JSON keys. Explicit strings win if
  # both forms are present. Typed non-nil settings are applied afterwards.
  defp put_extra(body, %ModelSettings{extra: extra}) do
    normalized =
      Map.new(extra, fn {key, value} ->
        key = to_string(key)
        {key, Map.get(extra, key, value)}
      end)

    Map.merge(body, Map.drop(normalized, ["model", "messages", "tools", "stream"]))
  end

  defp put_extra(body, nil), do: body

  defp build_headers(%Config{api_key: key, extra_headers: extra}) do
    auth = [{"authorization", "Bearer " <> key}]

    [{"content-type", "application/json"} | auth ++ extra]
  end

  defp put_settings(body, %ModelSettings{} = s) do
    body
    |> maybe_put("max_tokens", s.max_tokens)
    |> maybe_put("temperature", s.temperature)
    |> maybe_put("top_p", s.top_p)
    |> maybe_put("presence_penalty", s.presence_penalty)
    |> maybe_put("frequency_penalty", s.frequency_penalty)
  end

  defp put_settings(body, nil), do: body

  defp tool_choice(%ModelRequestParameters{output_mode: :tool}, _), do: "required"
  defp tool_choice(_, nil), do: nil
  defp tool_choice(_, _), do: "auto"

  # ----- tools -------------------------------------------------------------
  @doc "Encode a list of `Tool` into the OpenAI `tools` payload (or `nil`)."
  @spec encode_tools([Tool.t()]) :: [map()] | nil
  def encode_tools(tools) when is_list(tools) do
    case Enum.map(tools, &encode_tool/1) do
      [] -> nil
      list -> list
    end
  end

  defp encode_tool(%Tool{} = t) do
    %{
      "type" => "function",
      "function" => %{
        "name" => t.name,
        "description" => t.description,
        "parameters" => t.parameters_json_schema
      }
    }
  end

  defp build_tools(%ModelRequestParameters{function_tools: f, output_tools: o}) do
    encode_tools(f ++ o)
  end

  # ----- encode: messages → openai ----------------------------------------
  @spec to_openai_messages([Message.t()]) :: [map()]
  def to_openai_messages(messages) do
    Enum.flat_map(messages, &encode_message/1)
  end

  defp encode_message(%Message.Request{parts: parts}) do
    Enum.flat_map(parts, &encode_request_part/1)
  end

  defp encode_message(%Message.Response{parts: parts}) do
    [encode_assistant(parts)]
  end

  defp encode_request_part(%Part.System{content: content}),
    do: [%{"role" => "system", "content" => content_to_string(content)}]

  defp encode_request_part(%Part.User{content: content}),
    do: [%{"role" => "user", "content" => content_to_string(content)}]

  defp encode_request_part(%Part.ToolReturn{
         tool_name: name,
         content: content,
         tool_call_id: id
       }),
       do: [
         %{"role" => "tool", "tool_call_id" => id || name, "content" => encode_content(content)}
       ]

  defp encode_request_part(%Part.Retry{content: content, tool_name: nil}),
    do: [%{"role" => "user", "content" => retry_text(content, nil)}]

  defp encode_request_part(%Part.Retry{content: content, tool_name: name, tool_call_id: id}),
    do: [
      %{
        "role" => "tool",
        "tool_call_id" => id || name,
        "content" => retry_text(content, name)
      }
    ]

  defp encode_assistant(parts) do
    text =
      parts
      |> Enum.filter(&match?(%Part.Text{}, &1))
      |> Enum.map_join(& &1.content)

    tool_calls =
      parts
      |> Enum.filter(&match?(%Part.ToolCall{}, &1))
      |> Enum.map(&encode_tool_call/1)

    assistant = %{"role" => "assistant"}
    assistant = if text == "", do: assistant, else: Map.put(assistant, "content", text)
    if tool_calls == [], do: assistant, else: Map.put(assistant, "tool_calls", tool_calls)
  end

  defp encode_tool_call(%Part.ToolCall{tool_name: name, args: args, tool_call_id: id}) do
    %{
      "id" => id || name,
      "type" => "function",
      "function" => %{"name" => name, "arguments" => args_json(args)}
    }
  end

  defp args_json(nil), do: "{}"
  defp args_json(args) when is_binary(args), do: args
  defp args_json(args) when is_map(args), do: Jason.encode!(args)

  defp encode_content(content) when is_binary(content), do: content
  defp encode_content(content), do: Jason.encode!(content)

  defp content_to_string(content) when is_binary(content), do: content
  defp content_to_string(content), do: Jason.encode!(content)

  defp retry_text(content, nil), do: format_retry(content)

  defp retry_text(content, name),
    do: "Error calling tool #{name}: " <> format_retry(content)

  defp format_retry(content) when is_binary(content), do: content
  defp format_retry(errors) when is_list(errors), do: Jason.encode!(%{"errors" => errors})
  defp format_retry(other), do: inspect(other)

  # ----- decode: response → our structs -----------------------------------
  # Providers (OpenAI, OpenRouter, Azure, DeepSeek, …) occasionally return a
  # 200 with an empty/absent `choices` (content-filter short-circuits, beta
  # headers, malformed upstream routing). Treat that as an empty response
  # rather than crashing the run with a FunctionClauseError.
  @spec parse_response(map(), struct()) :: Response.t()
  def parse_response(%{"choices" => [choice | _]} = body, %Config{system: system}) do
    message = Map.get(choice, "message", %{})
    finish_reason = parse_finish_reason(Map.get(choice, "finish_reason"))

    text_parts =
      case Map.get(message, "content") do
        nil -> []
        "" -> []
        content -> [%Part.Text{content: content}]
      end

    tool_parts =
      message
      |> Map.get("tool_calls")
      |> Kernel.||([])
      |> Enum.flat_map(fn
        %{"function" => %{"name" => _, "arguments" => _}} = entry -> [parse_tool_call(entry)]
        _ -> []
      end)

    %Response{
      parts: thinking_parts(message) ++ text_parts ++ tool_parts,
      usage: parse_usage(body["usage"]),
      model_name: body["model"] || system,
      finish_reason: finish_reason,
      timestamp: DateTime.utc_now()
    }
  end

  def parse_response(body, %Config{system: system}) do
    # Empty/absent choices → an empty response the loop treats as "nothing to
    # say" (retry_or_fail). Better than crashing the caller.
    %Response{
      parts: [],
      usage: parse_usage(body["usage"]),
      model_name: body["model"] || system,
      finish_reason: parse_finish_reason(nil),
      timestamp: DateTime.utc_now()
    }
  end

  # Map known finish reasons to atoms; never mint atoms from arbitrary provider
  # input (avoids atom-table growth via a hostile/buggy proxy).
  @finish_reasons %{
    "stop" => :stop,
    "length" => :length,
    "tool_calls" => :tool_calls,
    "content_filter" => :content_filter,
    "function_call" => :function_call
  }
  defp parse_finish_reason(nil), do: nil
  defp parse_finish_reason(reason), do: Map.get(@finish_reasons, reason, :unknown)

  defp parse_tool_call(%{
         "id" => id,
         "function" => %{"name" => name, "arguments" => args}
       }) do
    %Part.ToolCall{tool_name: name, args: args, tool_call_id: id, kind: :function}
  end

  defp thinking_parts(message) do
    case message["reasoning_content"] || message["reasoning"] do
      text when is_binary(text) and text != "" -> [%Part.Thinking{content: text}]
      _ -> []
    end
  end

  # Build a Usage from whichever token keys are present; some proxies/prefill
  # endpoints report only prompt_tokens. Missing dimensions stay nil so the
  # execution scope can retain known subtotals without certifying zero cost.
  # Keep scalar fields in `details`
  # (sum_details assumes numeric values) — including cached_tokens extracted from
  # prompt_tokens_details, so callers can measure prompt-caching wins.
  defp parse_usage(nil), do: nil

  defp parse_usage(%{} = u) do
    input = Map.get(u, "prompt_tokens")
    output = Map.get(u, "completion_tokens")

    details =
      %{"total_tokens" => Map.get(u, "total_tokens")}
      |> maybe_put("cached_tokens", cached_tokens(u))
      |> maybe_put("reasoning_tokens", reasoning_tokens(u))
      |> maybe_put("cost", Map.get(u, "cost"))

    %Usage{input_tokens: input, output_tokens: output, details: details}
  end

  defp parse_usage(_), do: nil

  defp cached_tokens(%{"prompt_tokens_details" => %{"cached_tokens" => n}}), do: n
  defp cached_tokens(%{"cached_tokens" => n}), do: n
  defp cached_tokens(_), do: nil

  defp reasoning_tokens(%{"completion_tokens_details" => %{"reasoning_tokens" => n}}), do: n
  defp reasoning_tokens(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end
