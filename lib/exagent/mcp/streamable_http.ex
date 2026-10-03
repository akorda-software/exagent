defmodule ExAgent.MCP.StreamableHTTP do
  @moduledoc """
  Bounded MCP 2025-06-18 POST transport using stock Finch's public API.

  Configure `Client.start_link(transport: :streamable_http, url: url, finch: name)`.
  The application must own a Finch pool configured with `protocols: [:http1]`.
  This is a trusted precondition, not detected by the adapter. Use at least two
  connections if the server sends requests requiring responses during SSE.
  No redirects, POST retries, spontaneous GET or SSE resume/replay are performed.

  Limits apply to host-retained body/line/event bytes after Finch delivers chunks,
  not upstream socket allocation. `:headers` are per-client and must not contain
  reserved transport headers. No session/auth value is included in adapter errors.
  Finch instrumentation is application-owned; do not attach handlers that export
  raw HTTP requests/headers. MCP session IDs are ephemeral, never C7 authority.
  """
  alias __MODULE__.{Message, SSE}

  @limits [
    max_response_bytes: 1_048_576,
    max_request_bytes: 1_048_576,
    max_line_bytes: 65_536,
    max_event_bytes: 262_144,
    max_header_bytes: 16_384,
    max_session_bytes: 256,
    max_tools: 256,
    max_controls: 16,
    max_control_bytes: 65_536,
    max_control_workers: 4,
    control_timeout: 1_000
  ]
  @reserved ~w(accept content-type content-length host connection transfer-encoding mcp-session-id mcp-protocol-version last-event-id)

  def config(opts) do
    url = opts[:url]
    headers = Keyword.get(opts, :headers, [])
    config = Map.new(@limits, fn {key, default} -> {key, Keyword.get(opts, key, default)} end)

    with true <- is_binary(url) and byte_size(url) <= 8_192,
         true <- Keyword.get(opts, :protocol_version, "2025-06-18") == "2025-06-18",
         %URI{scheme: scheme, host: host, userinfo: nil, fragment: nil} <- URI.parse(url),
         true <- scheme in ["http", "https"] and is_binary(host) and host != "",
         true <- is_atom(opts[:finch]) and not is_nil(opts[:finch]),
         true <- Enum.all?(config, fn {_, value} -> is_integer(value) and value > 0 end),
         true <- is_list(headers) and Enum.all?(headers, &header?/1),
         true <- headers_size(headers) <= config.max_header_bytes do
      {:ok, Map.merge(config, %{url: url, finch: opts[:finch], headers: headers})}
    else
      _ -> {:error, :invalid_http_configuration}
    end
  rescue
    _ -> {:error, :invalid_http_configuration}
  end

  defp header?({name, value}) when is_binary(name) and is_binary(value),
    do:
      name != "" and Regex.match?(~r/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/, name) and
        String.downcase(name) not in @reserved and visible?(value)

  defp header?(_), do: false
  defp visible?(value), do: Enum.all?(:binary.bin_to_list(value), &(&1 in 32..126))

  defp headers_size(headers),
    do: Enum.reduce(headers, 0, fn {k, v}, n -> n + byte_size(k) + byte_size(v) end)

  # A separately monitored guardian survives an untrappable owner :kill. Both
  # owner and worker death release it; the total deadline also kills stalled IO.
  def spawn_request(owner, generation, id, deadline, fun) do
    spawn_monitor(fn ->
      worker = self()
      spawn(fn -> guard(owner, worker, deadline) end)

      receive do
        :http_guard_ready ->
          result =
            try do
              fun.()
            rescue
              _ -> {:error, :http_transport_error}
            catch
              _, _ -> {:error, :http_transport_error}
            end

          send(owner, {:mcp_http, generation, id, self(), result})
      end
    end)
  end

  defp guard(owner, worker, deadline) do
    owner_ref = Process.monitor(owner)
    worker_ref = Process.monitor(worker)
    send(worker, :http_guard_ready)

    receive do
      {:DOWN, ^owner_ref, :process, _, _} -> Process.exit(worker, :kill)
      {:DOWN, ^worker_ref, :process, _, _} -> :ok
    after
      max(deadline - now(), 0) -> Process.exit(worker, :kill)
    end
  end

  def now, do: System.monotonic_time(:millisecond)

  def initialize(config, id, deadline) do
    params = %{
      "protocolVersion" => "2025-06-18",
      "capabilities" => %{},
      "clientInfo" => %{"name" => "exagent", "version" => "1.3.0"}
    }

    with {:ok, result, session} <- request(config, "initialize", params, id, nil, deadline),
         :ok <- Message.initialize(result),
         {:ok, _, _} <-
           notification(
             config,
             "notifications/initialized",
             %{},
             session,
             min(deadline, now() + config.control_timeout)
           ) do
      {:ok, result, session}
    end
  end

  def request(config, method, params, id, session, deadline) do
    body = %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

    exchange(
      config,
      :post,
      body,
      id,
      session,
      deadline,
      if(method == "initialize", do: :initialize, else: :request)
    )
  end

  def notification(config, method, params, session, deadline),
    do:
      exchange(
        config,
        :post,
        %{"jsonrpc" => "2.0", "method" => method, "params" => params},
        nil,
        session,
        deadline,
        :control
      )

  def delete(config, session, deadline),
    do: exchange(config, :delete, nil, nil, session, deadline, :delete)

  defp exchange(config, method, value, id, session, deadline, phase) do
    with {:ok, body} <- encode(value),
         true <- byte_size(body) <= config.max_request_bytes,
         true <- phase != :control or byte_size(body) <= config.max_control_bytes,
         true <- now() < deadline do
      headers =
        [{"accept", "application/json, text/event-stream"}, {"content-type", "application/json"}] ++
          config.headers

      headers =
        if phase == :initialize,
          do: headers,
          else: [{"mcp-protocol-version", "2025-06-18"} | headers]

      headers = if session, do: [{"mcp-session-id", session} | headers], else: headers

      acc = %{
        config: config,
        id: id,
        session: session,
        deadline: deadline,
        phase: phase,
        status: nil,
        type: nil,
        bytes: 0,
        header_bytes: 0,
        body: [],
        result: nil,
        controls: 0,
        control_bytes: 0,
        error: nil,
        sse: SSE.new(config.max_line_bytes, config.max_event_bytes)
      }

      req = Finch.build(method, config.url, headers, body)
      remaining = max(deadline - now(), 1)

      case Finch.stream_while(req, config.finch, acc, &receive_part/2,
             receive_timeout: remaining,
             pool_timeout: remaining,
             request_timeout: remaining
           ) do
        {:ok, acc} -> complete(acc)
        {:error, _, _} -> {:error, :http_transport_error}
      end
    else
      false -> if(now() >= deadline, do: {:error, :timeout}, else: {:error, :request_byte_limit})
      error -> error
    end
  rescue
    _ -> {:error, :http_transport_error}
  catch
    _, _ -> {:error, :http_transport_error}
  end

  defp encode(nil), do: {:ok, ""}

  defp encode(value) do
    case Jason.encode(value) do
      {:ok, bytes} -> {:ok, bytes}
      _ -> {:error, :invalid_request}
    end
  end

  defp receive_part(part, acc) do
    if now() >= acc.deadline,
      do: {:halt, %{acc | error: :timeout}},
      else: receive_current(part, acc)
  end

  defp receive_current({:status, status}, acc) do
    error =
      cond do
        status == 401 -> :unauthorized
        status == 403 -> :forbidden
        status == 404 and not is_nil(acc.session) -> :session_expired
        acc.phase == :delete and status in [200, 202, 204, 405] -> nil
        acc.phase == :control and status == 202 -> nil
        acc.phase in [:initialize, :request] and status == 200 -> nil
        true -> {:http_status, status}
      end

    if error, do: {:halt, %{acc | error: error}}, else: {:cont, %{acc | status: status}}
  end

  defp receive_current({:headers, headers}, acc) do
    bytes = acc.header_bytes + headers_size(headers)
    types = for {k, v} <- headers, String.downcase(k) == "content-type", do: v
    sessions = for {k, v} <- headers, String.downcase(k) == "mcp-session-id", do: v

    with true <- bytes <= acc.config.max_header_bytes,
         {:ok, session} <- session(acc, sessions),
         {:ok, type} <- content_type(acc.phase, types) do
      {:cont, %{acc | header_bytes: bytes, session: session, type: type}}
    else
      false -> {:halt, %{acc | error: :header_byte_limit}}
      {:error, error} -> {:halt, %{acc | error: error}}
    end
  end

  defp receive_current({:trailers, headers}, acc) do
    # Trailers cannot change the negotiated session or content type.
    bytes = acc.header_bytes + headers_size(headers)

    if bytes <= acc.config.max_header_bytes and
         Enum.all?(headers, fn {k, _} ->
           String.downcase(k) not in ["mcp-session-id", "content-type"]
         end),
       do: {:cont, %{acc | header_bytes: bytes}},
       else: {:halt, %{acc | error: :invalid_trailers}}
  end

  defp receive_current({:data, bytes}, %{type: :sse} = acc),
    do: receive_sse(bytes, acc)

  defp receive_current({:data, bytes}, acc) do
    total = acc.bytes + byte_size(bytes)

    cond do
      total > acc.config.max_response_bytes ->
        {:halt, %{acc | error: :response_byte_limit}}

      acc.phase in [:control, :delete] and bytes != "" ->
        {:halt, %{acc | error: :unexpected_response_body}}

      acc.type == :json ->
        {:cont, %{acc | bytes: total, body: [:binary.copy(bytes) | acc.body]}}

      true ->
        {:halt, %{acc | error: :invalid_content_type}}
    end
  end

  defp receive_sse("", acc), do: {:cont, acc}

  defp receive_sse(bytes, acc) do
    # Only the prefix through the first terminal belongs to this response.
    # Bound scanning by the remaining budget, rather than rejecting an entire
    # Finch chunk which may also contain an irrelevant post-terminal suffix.
    available = min(byte_size(bytes), acc.config.max_response_bytes - acc.bytes)
    prefix = binary_part(bytes, 0, available)

    case SSE.next(acc.sse, prefix) do
      {:event, sse, event, rest} ->
        consumed = available - byte_size(rest)
        acc = %{acc | sse: sse, bytes: acc.bytes + consumed}

        case events([event], acc) do
          {:cont, acc} ->
            receive_sse(binary_part(bytes, consumed, byte_size(bytes) - consumed), acc)

          halt ->
            halt
        end

      {:more, sse} ->
        acc = %{acc | sse: sse, bytes: acc.bytes + available}

        if available < byte_size(bytes),
          do: {:halt, %{acc | error: :response_byte_limit}},
          else: {:cont, acc}

      {:error, error} ->
        {:halt, %{acc | error: error}}
    end
  end

  defp session(%{phase: :initialize} = acc, [value]) do
    if value != "" and byte_size(value) <= acc.config.max_session_bytes and
         Enum.all?(:binary.bin_to_list(value), &(&1 in 33..126)),
       do: {:ok, value},
       else: {:error, :invalid_session_id}
  end

  defp session(acc, []), do: {:ok, acc.session}

  defp session(%{phase: phase, session: session}, [session]) when phase != :initialize,
    do: {:ok, session}

  defp session(_, _), do: {:error, :invalid_session_id}

  defp content_type(phase, _) when phase in [:control, :delete], do: {:ok, nil}

  defp content_type(_, [value]) do
    case value |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase() do
      "application/json" -> {:ok, :json}
      "text/event-stream" -> {:ok, :sse}
      _ -> {:error, :invalid_content_type}
    end
  end

  defp content_type(_, _), do: {:error, :invalid_content_type}

  defp events([], acc), do: {:cont, acc}

  defp events([event | rest], acc) do
    case Message.decode(event, acc.id) do
      {:result, result} -> {:halt, %{acc | result: result}}
      {:error, error} -> {:halt, %{acc | error: error}}
      :notification -> control_event(rest, acc, byte_size(event), nil)
      {:control, response} -> control_event(rest, acc, byte_size(event), response)
    end
  end

  defp control_event(rest, acc, bytes, response) do
    acc = %{acc | controls: acc.controls + 1, control_bytes: acc.control_bytes + bytes}

    cond do
      acc.controls > acc.config.max_controls ->
        {:halt, %{acc | error: :control_count_limit}}

      acc.control_bytes > acc.config.max_control_bytes ->
        {:halt, %{acc | error: :control_byte_limit}}

      is_nil(response) ->
        events(rest, acc)

      true ->
        deadline = min(acc.deadline, now() + acc.config.control_timeout)

        # An initialize header is provisional until its result is validated.
        session = if acc.phase == :initialize, do: nil, else: acc.session

        case exchange(acc.config, :post, response, nil, session, deadline, :control) do
          {:ok, _, _} -> events(rest, acc)
          {:error, error} -> {:halt, %{acc | error: error}}
        end
    end
  end

  defp complete(acc) do
    cond do
      now() >= acc.deadline ->
        {:error, :timeout}

      acc.error != nil ->
        {:error, acc.error}

      acc.phase in [:control, :delete] ->
        {:ok, %{}, acc.session}

      acc.result != nil ->
        {:ok, acc.result, acc.session}

      acc.type == :json ->
        case Message.decode(acc.body |> Enum.reverse() |> IO.iodata_to_binary(), acc.id) do
          {:result, result} -> {:ok, result, acc.session}
          {:error, error} -> {:error, error}
          _ -> {:error, :invalid_jsonrpc_response}
        end

      true ->
        case SSE.finish(acc.sse) do
          :ok -> {:error, :missing_response}
          error -> error
        end
    end
  end
end
