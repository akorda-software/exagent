defmodule ExAgent.Providers.Anthropic do
  @moduledoc """
  Implementation for providers that speak the **Anthropic Messages API**:
  `POST {base_url}/v1/messages`.

  The Anthropic wire format differs from OpenAI Chat Completions in several
  load-bearing ways, all handled here:

    * **`system` is top-level** — `SystemPrompt` parts are lifted out of the
      message stream and sent as the `system` parameter, not as a message.
    * **Content is an array of blocks** — every message body is a list of
      `{"type": "text" | "tool_use" | "tool_result", ...}` blocks.
    * **Tool calls** — the model emits `tool_use` blocks (with an `input` object,
      not a JSON string); the agent replies with `tool_result` blocks in a
      *user* message keyed by `tool_use_id`.
    * **Auth** — `x-api-key` (real Anthropic) or `Authorization: Bearer`
      (e.g. Z.AI's `/api/anthropic`), plus the `anthropic-version` header.

  Pointing this at Z.AI's Anthropic-compatible endpoint gives access to GLM
  models (`glm-4.5-air`, `glm-4.7`, `glm-5.2`, …) using the native format.
  """

  alias ExAgent.{Message, ModelSettings, ModelRequestParameters, Tool}
  alias ExAgent.Message.{Part, Response, Usage}
  alias ExAgent.Providers.{SSE, StreamTransport, EventStream}

  @anthropic_version "2023-06-01"
  @default_max_tokens 4096
  @default_timeout 60_000

  defmodule Config do
    @moduledoc false
    defstruct [:model, :api_key, :auth_token, :base_url, :system, cache: false]

    @type t :: %__MODULE__{
            model: String.t(),
            api_key: String.t() | nil,
            auth_token: String.t() | nil,
            base_url: String.t(),
            system: String.t(),
            cache: boolean()
          }
  end

  @doc "Perform a (non-streaming) Messages API request."
  @spec request(struct(), [Message.t()], ModelSettings.t() | nil, ModelRequestParameters.t()) ::
          {:ok, Response.t(), struct()} | {:error, term()}
  def request(model, messages, settings, params) do
    config = config(model)

    with :ok <- ensure_credentials(config) do
      body = build_body(model, messages, settings, params)
      do_request(config, body, settings, model)
    end
  end

  @doc false
  # Builds the Messages API request body. Public so the cache breakpoint layout
  # can be unit-tested without a network.
  def build_body(model, messages, settings, params) do
    config = config(model)
    {system, convo} = encode_messages(messages)
    tools = encode_tools(params)
    {system, tools} = apply_cache(system, tools, config.cache)

    %{}
    |> maybe_put("tool_choice", tool_choice(params))
    |> put_extra(settings)
    |> Map.put("model", config.model)
    |> Map.put("max_tokens", max_tokens(settings))
    |> maybe_put("system", system)
    |> Map.put("messages", convo)
    |> put_settings(settings)
    |> maybe_put("tools", tools)
  end

  # Anthropic prompt caching: a `cache_control: ephemeral` breakpoint on the
  # last system block and the last tool definition lets the provider reuse the
  # cached prefix (60–90% input-token savings on long, repeated system prompts).
  defp apply_cache(system, tools, true) do
    {cache_last_block(system), cache_last_block(tools)}
  end

  defp apply_cache(system, tools, _), do: {system, tools}

  defp cache_last_block(nil), do: nil

  defp cache_last_block([]), do: []

  defp cache_last_block(list) when is_list(list) do
    List.update_at(list, -1, &Map.put(&1, "cache_control", %{"type" => "ephemeral"}))
  end

  defp do_request(config, body, settings, model) do
    case Req.request(
           url: String.trim_trailing(config.base_url, "/") <> "/v1/messages",
           method: :post,
           headers: build_headers(config),
           json: body,
           retry: false,
           redirect: false,
           finch: ExAgent.Finch,
           receive_timeout: settings_timeout(settings) || @default_timeout
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        case parse_body(resp_body, config) do
          {:ok, resp} -> {:ok, resp, model}
          {:error, _} = e -> e
        end

      {:ok, %{status: status, body: body}} ->
        {:error,
         %ExAgent.RequestError{
           provider: :anthropic,
           status: status,
           reason: :http_error,
           body: body
         }}

      {:error, %{reason: :timeout} = exception} ->
        {:error,
         %ExAgent.RequestError{
           provider: :anthropic,
           reason: :timeout,
           body: inspect(exception)
         }}

      {:error, exception} ->
        {:error,
         %ExAgent.RequestError{
           provider: :anthropic,
           reason: :request_failed,
           body: inspect(exception)
         }}
    end
  end

  @doc false
  @spec parse_body(map(), struct()) ::
          {:ok, Response.t()} | {:error, ExAgent.RequestError.t()}
  def parse_body(%{"error" => error}, _config) do
    {:error,
     %ExAgent.RequestError{
       provider: :anthropic,
       reason: :provider_error,
       body: if(is_map(error), do: error["message"] || inspect(error), else: error)
     }}
  end

  def parse_body(body, config), do: {:ok, parse_response(body, config)}

  # ----- config extraction -------------------------------------------------
  defp config(%{__struct__: mod, model: model} = struct) do
    %Config{
      model: model,
      api_key: Map.get(struct, :api_key),
      auth_token: Map.get(struct, :auth_token),
      base_url: Map.get(struct, :base_url) || default_base_url(mod),
      system: Atom.to_string(mod) |> String.split(".") |> List.last() |> String.downcase(),
      cache: Map.get(struct, :cache) || false
    }
  end

  defp default_base_url(ExAgent.Models.Anthropic), do: "https://api.anthropic.com"
  defp default_base_url(_), do: "https://api.anthropic.com"

  defp build_headers(%Config{api_key: api_key, auth_token: auth_token}) do
    auth =
      cond do
        is_binary(auth_token) and auth_token != "" -> [{"authorization", "Bearer " <> auth_token}]
        is_binary(api_key) and api_key != "" -> [{"x-api-key", api_key}]
      end

    [{"content-type", "application/json"}, {"anthropic-version", @anthropic_version} | auth]
  end

  defp ensure_credentials(%{api_key: key, auth_token: token})
       when key in [nil, ""] and token in [nil, ""],
       do: {:error, %ExAgent.RequestError{provider: :anthropic, reason: :missing_credentials}}

  defp ensure_credentials(_), do: :ok

  # ----- encode: messages -> anthropic ------------------------------------
  @doc """
  Split a message history into a top-level `system` block list and the
  conversation messages (with `System` parts removed and consecutive
  same-role messages merged — Anthropic requires strict alternation).
  """
  @spec encode_messages([Message.t()]) :: {[map()], [map()]}
  def encode_messages(messages) do
    {system_parts, convo} =
      Enum.reduce(messages, {[], []}, fn
        %Message.Request{parts: parts}, {sys_acc, convo_acc} ->
          {sys, rest} = split_system(parts)

          case rest do
            [] ->
              {sys_acc ++ sys, convo_acc}

            _ ->
              {sys_acc ++ sys,
               convo_acc ++ [{:user, Enum.flat_map(rest, &encode_request_block/1)}]}
          end

        %Message.Response{parts: parts}, {sys_acc, convo_acc} ->
          blocks = Enum.flat_map(parts, &encode_response_block/1)
          {sys_acc, convo_acc ++ [{:assistant, blocks}]}
      end)

    system =
      case system_parts do
        [] -> nil
        parts -> Enum.map(parts, &%{type: "text", text: &1.content})
      end

    convo = merge_consecutive(convo)
    {system, convo}
  end

  defp split_system(parts) do
    Enum.split_with(parts, &match?(%Part.System{}, &1))
  end

  defp encode_request_block(%Part.System{}), do: []

  defp encode_request_block(%Part.User{content: content}),
    do: [%{type: "text", text: content_to_string(content)}]

  defp encode_request_block(%Part.ToolReturn{
         tool_name: name,
         content: content,
         tool_call_id: id
       }),
       do: [%{type: "tool_result", tool_use_id: id || name, content: encode_content(content)}]

  defp encode_request_block(%Part.Retry{content: content, tool_name: nil}),
    do: [%{type: "text", text: retry_text(content, nil)}]

  defp encode_request_block(%Part.Retry{content: content, tool_name: name, tool_call_id: id}),
    do: [
      %{
        type: "tool_result",
        tool_use_id: id || name,
        content: retry_text(content, name),
        is_error: true
      }
    ]

  defp encode_response_block(%Part.Text{content: content}),
    do: [%{type: "text", text: content}]

  defp encode_response_block(%Part.ToolCall{
         tool_name: name,
         args: args,
         tool_call_id: id
       }),
       do: [%{type: "tool_use", id: id || name, name: name, input: args_to_map(args)}]

  defp encode_response_block(%Part.Thinking{content: content, signature: signature}),
    do: [%{type: "thinking", thinking: content, signature: signature}]

  defp merge_consecutive(convo) do
    convo
    |> Enum.reduce([], fn {role, blocks}, acc ->
      case acc do
        [{^role, prev} | rest] -> [{role, prev ++ blocks} | rest]
        _ -> [{role, blocks} | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {role, blocks} -> %{role: role, content: blocks} end)
  end

  # ----- tools -------------------------------------------------------------
  @doc "Encode `Tool` list into the Anthropic `tools` payload (or `nil`)."
  @spec encode_tools(ModelRequestParameters.t()) :: [map()] | nil
  def encode_tools(%ModelRequestParameters{function_tools: f, output_tools: o}) do
    case Enum.map(f ++ o, &encode_tool/1) do
      [] -> nil
      list -> list
    end
  end

  defp encode_tool(%Tool{} = t) do
    %{name: t.name, description: t.description, input_schema: t.parameters_json_schema}
  end

  defp tool_choice(%ModelRequestParameters{output_mode: :tool}), do: %{type: "any"}
  defp tool_choice(%ModelRequestParameters{function_tools: [], output_tools: []}), do: nil
  defp tool_choice(_), do: %{type: "auto"}

  # ----- streaming ---------------------------------------------------------
  @doc """
  Perform a streaming Messages API request. Returns a lazy stream of:

    * `{:text_delta, binary}`,
    * `{:thinking_delta, binary}` when present,
    * `{:usage, Usage.t()}` — latest per-request snapshot, never an additive delta,
    * `{:response, Response.t(), final_model}` (single final assembled response),
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
          body = model |> build_body(messages, settings, params) |> Map.put("stream", true)

          [
            url: String.trim_trailing(config.base_url, "/") <> "/v1/messages",
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
    acc = %{blocks: %{}, started: false, usage: nil, model: model.model, stop_reason: nil}
    EventStream.transform(sse, acc, fn event, acc -> stream_step(event, acc, model) end)
  end

  defp stream_step(%{"type" => "message_stop"}, acc, model) do
    if acc.started and acc.stop_reason != nil and Enum.all?(acc.blocks, fn {_, b} -> b.closed end) do
      {:halt, [{:response, build_streamed_response(acc), model}], acc}
    else
      stream_error(:incomplete_stream_response, acc, model)
    end
  end

  defp stream_step(event, acc, model) when event in [:done, :eof],
    do: stream_error(:missing_stream_terminal, acc, model)

  defp stream_step({:error, reason}, acc, model), do: stream_error(reason, acc, model)

  defp stream_step(%{"type" => "error", "error" => error}, acc, model),
    do: stream_error({:provider_error, error}, acc, model)

  defp stream_step(%{"type" => "ping"}, acc, _), do: {:cont, [], acc}

  defp stream_step(%{"type" => "message_start", "message" => msg}, %{started: false} = acc, model)
       when is_map(msg) do
    if (is_nil(msg["usage"]) or is_map(msg["usage"])) and
         (is_nil(msg["model"]) or is_binary(msg["model"])) do
      events = if is_map(msg["usage"]), do: [{:usage, parse_usage(msg["usage"])}], else: []

      {:cont, events,
       %{acc | started: true, model: msg["model"] || acc.model, usage: msg["usage"]}}
    else
      stream_error(:invalid_stream_chunk, acc, model)
    end
  end

  defp stream_step(
         %{"type" => "content_block_start", "index" => index, "content_block" => block},
         %{started: true} = acc,
         model
       )
       when is_integer(index) and index >= 0 and is_map(block) do
    with false <- Map.has_key?(acc.blocks, index),
         {:ok, block, events} <- start_block(block) do
      {:cont, events, %{acc | blocks: Map.put(acc.blocks, index, block)}}
    else
      _ -> stream_error(:invalid_content_block, acc, model)
    end
  end

  defp stream_step(
         %{"type" => "content_block_delta", "index" => index, "delta" => delta},
         acc,
         model
       ) do
    with %{closed: false} = block <- Map.get(acc.blocks, index),
         {:ok, block, events} <- update_block(block, delta) do
      {:cont, events, %{acc | blocks: Map.put(acc.blocks, index, block)}}
    else
      _ -> stream_error(:invalid_content_block_delta, acc, model)
    end
  end

  defp stream_step(%{"type" => "content_block_stop", "index" => index}, acc, model) do
    with %{closed: false} = block <- Map.get(acc.blocks, index),
         true <- valid_block?(block) do
      {:cont, [], %{acc | blocks: Map.put(acc.blocks, index, %{block | closed: true})}}
    else
      _ -> stream_error(:invalid_tool_arguments, acc, model)
    end
  end

  defp stream_step(
         %{"type" => "message_delta"} = event,
         %{started: true} = acc,
         model
       ) do
    delta = event["delta"] || %{}
    usage = event["usage"] || (is_map(delta) && delta["usage"]) || nil

    if is_map(delta) and (is_nil(usage) or is_map(usage)) and
         (is_nil(delta["stop_reason"]) or is_binary(delta["stop_reason"])) do
      latest = if is_map(usage), do: Map.merge(acc.usage || %{}, usage), else: acc.usage
      events = if is_map(usage), do: [{:usage, parse_usage(latest)}], else: []

      {:cont, events,
       %{acc | usage: latest, stop_reason: delta["stop_reason"] || acc.stop_reason}}
    else
      stream_error(:invalid_stream_chunk, acc, model)
    end
  end

  defp stream_step(_, acc, model), do: stream_error(:invalid_stream_chunk, acc, model)

  defp start_block(%{"type" => "text", "text" => text}) when is_binary(text),
    do: {:ok, %{type: :text, content: text, closed: false}, delta_event(:text_delta, text)}

  defp start_block(%{"type" => "thinking", "thinking" => text} = block) when is_binary(text),
    do:
      {:ok, %{type: :thinking, content: text, signature: block["signature"] || "", closed: false},
       delta_event(:thinking_delta, text)}

  defp start_block(%{"type" => "redacted_thinking", "data" => data}) when is_binary(data),
    do: {:ok, %{type: :thinking, content: data, signature: nil, closed: false}, []}

  defp start_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input})
       when is_binary(id) and id != "" and is_binary(name) and name != "" and is_map(input),
       do: {:ok, %{type: :tool, id: id, name: name, input: input, json: "", closed: false}, []}

  defp start_block(_), do: :error

  defp update_block(%{type: :text} = block, %{"type" => "text_delta", "text" => text})
       when is_binary(text),
       do: {:ok, %{block | content: block.content <> text}, delta_event(:text_delta, text)}

  defp update_block(%{type: :thinking} = block, %{"type" => "thinking_delta", "thinking" => text})
       when is_binary(text),
       do: {:ok, %{block | content: block.content <> text}, delta_event(:thinking_delta, text)}

  defp update_block(
         %{type: :thinking, signature: signature} = block,
         %{"type" => "signature_delta", "signature" => text}
       )
       when is_binary(text) and is_binary(signature),
       do: {:ok, %{block | signature: signature <> text}, []}

  defp update_block(
         %{type: :tool, input: input} = block,
         %{"type" => "input_json_delta", "partial_json" => json}
       )
       when is_binary(json) and map_size(input) == 0,
       do: {:ok, %{block | json: block.json <> json}, []}

  defp update_block(_, _), do: :error

  defp valid_block?(%{type: :tool, json: json}) when json != "",
    do: match?({:ok, args} when is_map(args), Jason.decode(json))

  defp valid_block?(_), do: true
  defp delta_event(_, ""), do: []
  defp delta_event(type, text), do: [{type, text}]

  defp build_streamed_response(acc) do
    parts =
      acc.blocks
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_, block} ->
        case block do
          %{type: :text} ->
            %Part.Text{content: block.content}

          %{type: :thinking} ->
            %Part.Thinking{content: block.content, signature: block.signature}

          %{type: :tool} ->
            args = if block.json == "", do: block.input, else: block.json

            args =
              case args do
                json when is_binary(json) ->
                  case Jason.decode(json) do
                    {:ok, map} when is_map(map) -> map
                    _ -> json
                  end

                map ->
                  map
              end

            %Part.ToolCall{
              tool_name: block.name,
              tool_call_id: block.id,
              args: args,
              kind: :function
            }
        end
      end)

    Message.new_response(parts,
      usage: parse_usage(acc.usage),
      model_name: acc.model,
      finish_reason: map_stop_reason(acc.stop_reason)
    )
  end

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
      provider: :anthropic,
      reason: reason,
      status: status,
      body: body,
      partial_response: partial_stream_response(acc),
      model: model
    }

    {:halt, [{:error, error}], acc}
  end

  defp partial_stream_response(%{blocks: blocks, usage: nil}) when map_size(blocks) == 0, do: nil
  defp partial_stream_response(acc), do: build_streamed_response(acc)

  # ----- decode: response -> our structs ----------------------------------
  # Anthropic / Z.AI occasionally return a 200 with `content: null` (overload,
  # safety routing). Treat nil/absent content as an empty response rather than
  # crashing the run with a Protocol.UndefinedError on Enum.flat_map(nil, …).
  @spec parse_response(map(), struct()) :: Response.t()
  def parse_response(body, %Config{system: system}) do
    content = Map.get(body, "content", []) || []

    parts =
      Enum.flat_map(content, fn
        %{"type" => "text", "text" => text} ->
          [%Part.Text{content: text}]

        %{"type" => "tool_use", "id" => id, "name" => name, "input" => input} ->
          [tool_call(name, id, input)]

        %{"type" => "thinking", "thinking" => thought, "signature" => signature} ->
          [%Part.Thinking{content: thought, signature: signature}]

        %{"type" => "redacted_thinking", "data" => data} ->
          [%Part.Thinking{content: data, signature: nil}]

        _ ->
          []
      end)

    %Response{
      parts: parts,
      usage: parse_usage(body["usage"]),
      model_name: body["model"] || system,
      finish_reason: map_stop_reason(body["stop_reason"]),
      timestamp: DateTime.utc_now()
    }
  end

  defp tool_call(name, id, input) when is_map(input),
    do: %Part.ToolCall{tool_name: name, args: input, tool_call_id: id, kind: :function}

  defp tool_call(name, id, input) when is_binary(input) do
    args = (match?({:ok, _}, Jason.decode(input)) && elem(Jason.decode(input), 1)) || %{}
    %Part.ToolCall{tool_name: name, args: args, tool_call_id: id, kind: :function}
  end

  defp tool_call(name, id, _), do: %Part.ToolCall{tool_name: name, args: %{}, tool_call_id: id}

  defp map_stop_reason("end_turn"), do: :stop
  defp map_stop_reason("tool_use"), do: :tool_calls
  defp map_stop_reason("max_tokens"), do: :length
  defp map_stop_reason("stop_sequence"), do: :stop_sequence
  defp map_stop_reason(other) when is_binary(other), do: :unknown
  defp map_stop_reason(nil), do: nil

  defp parse_usage(%{} = usage) do
    details = usage |> Map.take(["cache_creation_input_tokens", "cache_read_input_tokens"])

    %Usage{
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0,
      details: details
    }
  end

  defp parse_usage(_), do: nil

  # ----- helpers -----------------------------------------------------------
  defp max_tokens(%ModelSettings{max_tokens: n}) when is_integer(n), do: n
  defp max_tokens(_), do: @default_max_tokens

  defp settings_timeout(%ModelSettings{timeout: t}), do: t
  defp settings_timeout(_), do: nil

  defp put_settings(body, %ModelSettings{} = s) do
    body
    |> maybe_put("temperature", s.temperature)
    |> maybe_put("top_p", s.top_p)
  end

  defp put_settings(body, nil), do: body

  defp put_extra(body, %ModelSettings{extra: extra}) do
    normalized =
      Map.new(extra, fn {key, value} ->
        key = to_string(key)
        {key, Map.get(extra, key, value)}
      end)

    Map.merge(body, Map.drop(normalized, ["model", "messages", "system", "tools", "stream"]))
  end

  defp put_extra(body, nil), do: body

  defp encode_content(content) when is_binary(content), do: content
  defp encode_content(content), do: Jason.encode!(content)

  defp content_to_string(content) when is_binary(content), do: content
  defp content_to_string(content), do: Jason.encode!(content)

  defp retry_text(content, nil), do: format_retry(content)
  defp retry_text(content, name), do: "Error calling tool #{name}: " <> format_retry(content)

  defp format_retry(content) when is_binary(content), do: content
  defp format_retry(errors) when is_list(errors), do: Jason.encode!(%{"errors" => errors})
  defp format_retry(other), do: inspect(other)

  defp args_to_map(nil), do: %{}
  defp args_to_map(args) when is_map(args), do: args

  defp args_to_map(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
