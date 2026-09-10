defmodule ExAgent.MCP.Client do
  @moduledoc """
  A client for [Model Context Protocol](https://modelcontextprotocol.io) servers
  over the **stdio** transport, exposing a server's tools as `ExAgent.Tool`s.

  An MCP server is an external process that speaks JSON-RPC 2.0 over stdin/stdout
  (e.g. `npx -y @modelcontextprotocol/server-filesystem ./`). This client spawns
  it, performs the `initialize` handshake, lists its tools, and turns each into an
  `ExAgent.Tool` whose execution forwards a `tools/call` back to the server.

  ## Example

      # 1) start the server + handshake
      {:ok, client} =
        ExAgent.MCP.Client.start_link(
          command: "npx",
          args: ["-y", "@modelcontextprotocol/server-filesystem", "./data"]
        )

      # 2) discover its tools as ExAgent tools
      tools = ExAgent.MCP.Client.tools(client)

      # 3) use them like any ExAgent tool
      agent = ExAgent.new(model: "anthropic:claude-3-5-haiku", tools: tools)
      ExAgent.run(agent, "list the files")

  ## Concurrency and request ownership

  A client owns one transport. Requests are sent independently and can execute
  concurrently on the remote server; the GenServer does not serialize remote
  tool effects. Each pending request has a deadline and monitors its caller.
  A timeout returns `{:error, :timeout}` and caller death drops the local request.
  Neither proves that a remote tool stopped or rolled back, and neither triggers
  replay. Requests beyond `:max_pending` return `{:error, :busy}` before sending.

  Incoming newline-delimited frames are limited by `:max_frame_bytes`. An oversized
  frame closes the transport, fails remaining pending requests, and leaves the
  client not ready. Complete responses preceding that frame are processed first,
  independently of transport chunk boundaries. These bounds limit pending state
  and individual frames, not the BEAM mailbox or aggregate traffic from a push
  transport.

  ## Testing seam

  The transport is pluggable: pass `transport: {send_fun, ref}` (mostly for
  tests) to inject a fake transport instead of spawning a real process. The
  client receives data as messages shaped `{ref, {:data, binary}}`.
  `send_fun` must return promptly: it runs in the client process, so a blocking
  callback delays deadlines and other client operations. `{:error, reason}`,
  `false`, exceptions and throws/exits indicate an unconfirmed send; other return
  values (including the value returned by `send/2`) retain their existing meaning.
  """

  use GenServer

  alias ExAgent.MCP.Protocol

  @default_timeout 5_000
  @default_max_pending 128
  @default_max_frame_bytes 8_388_608

  defstruct transport_ref: nil,
            parent: nil,
            send_fun: nil,
            id: 0,
            # id => %{from, method, timer, monitor}; IDs never repeat.
            pending: %{},
            monitors: %{},
            buffer: "",
            ready: false,
            timeout: @default_timeout,
            max_pending: @default_max_pending,
            max_frame_bytes: @default_max_frame_bytes

  @type t :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Start the client, spawn the MCP server (stdio), and perform the `initialize`
  handshake.

  ## Options

    * `:command` — executable to spawn (required for stdio).
    * `:args` — list of args passed to the command (default `[]`).
    * `:env` — list of `{bin, bin}` env vars (default `[]`).
    * `:timeout` — handshake / per-request timeout in ms (default `5000`).
      Must be a positive integer; requests return `{:error, :timeout}` on expiry.
    * `:max_pending` — maximum concurrent pending requests (default `128`).
    * `:max_frame_bytes` — maximum bytes in a newline-delimited incoming frame,
      excluding its newline (default `8388608`, 8 MiB). Also bounds partial frames.
      Both limits must be positive integers.
    * `:cd` — working directory for the spawned server.
    * `:transport` — `{send_fun, ref}` test seam (see moduledoc). When set, no
      process is spawned; `send_fun.(ref, iodata)` must deliver bytes to the
      server and responses must arrive as `{ref, {:data, binary}}` messages.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  List the server's tools as `ExAgent.Tool`s. Each tool's `call` forwards a
  `tools/call` to the server and returns its text result.
  """
  @spec tools(GenServer.server()) :: {:ok, [ExAgent.Tool.t()]} | {:error, term()}
  def tools(client) do
    GenServer.call(client, :tools, :infinity)
  end

  @doc """
  Call a tool on the server by name. Returns `{:ok, text}` (the concatenated
  content text) or `{:error, reason}`. Used by the generated `ExAgent.Tool`s.
  """
  @spec call_tool(GenServer.server(), String.t(), map()) ::
          {:ok, String.t()} | {:error, term()}
  def call_tool(client, name, arguments) do
    GenServer.call(client, {:call_tool, name, arguments}, :infinity)
  end

  @doc "Shut the client and its server process down."
  @spec close(GenServer.server()) :: :ok
  def close(client) do
    GenServer.call(client, :close, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    with {:ok, timeout} <- positive_option(opts, :timeout, @default_timeout),
         {:ok, max_pending} <- positive_option(opts, :max_pending, @default_max_pending),
         {:ok, max_frame_bytes} <-
           positive_option(opts, :max_frame_bytes, @default_max_frame_bytes) do
      init_transport(opts, timeout, max_pending, max_frame_bytes)
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp positive_option(opts, key, default) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _ -> {:error, {:invalid_option, key}}
    end
  end

  defp init_transport(opts, timeout, max_pending, max_frame_bytes) do
    {ref, send_fun} =
      case Keyword.get(opts, :transport) do
        {fun, transport_ref} when is_function(fun, 2) ->
          if is_port(transport_ref), do: Process.flag(:trap_exit, true)
          {transport_ref, fun}

        nil ->
          # The owned Port is linked. Trap before opening it so even an early
          # abnormal Port death reaches the handshake instead of killing Client.
          Process.flag(:trap_exit, true)
          port = open_port(opts)
          {port, fn p, data -> true = Port.command(p, data) end}
      end

    state = %__MODULE__{
      transport_ref: ref,
      parent: parent_pid(),
      send_fun: send_fun,
      timeout: timeout,
      max_pending: max_pending,
      max_frame_bytes: max_frame_bytes
    }

    # Consume initialize synchronously. A known response followed by a broken
    # frame still completes initialize, then leaves Client alive but not ready,
    # just as when those bytes arrive as separate chunks.
    with {:ok, _result, state, frame_error} <-
           request_sync(state, "initialize", handshake_params(opts)),
         :ok <- send_data(state, Protocol.encode_notification("notifications/initialized", %{})) do
      state = %{state | ready: true}

      if frame_error do
        close_transport(state)
        {:ok, fail_all(state, frame_error)}
      else
        {:ok, state}
      end
    else
      {:error, reason} ->
        close_transport(state)
        {:stop, reason}
    end
  end

  # GenServer handles its parent's EXIT in the normal loop. During the inline
  # initialize receive we must do the same rather than await the request timeout.
  defp parent_pid do
    case Process.get(:"$ancestors", []) do
      [pid | _] when is_pid(pid) -> pid
      [name | _] when is_atom(name) -> Process.whereis(name)
      _ -> nil
    end
  end

  defp handshake_params(opts) do
    %{
      "protocolVersion" => Keyword.get(opts, :protocol_version, "2024-11-05"),
      "capabilities" => %{},
      "clientInfo" => %{"name" => "exagent", "version" => "1.1.0"}
    }
  end

  defp open_port(opts) do
    command = Keyword.fetch!(opts, :command)
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, [])

    port_args =
      [
        :binary,
        :use_stdio,
        :stream,
        :exit_status,
        {:args, args},
        {:env, env}
      ] ++ if opts[:cd], do: [{:cd, opts[:cd]}], else: []

    Port.open({:spawn_executable, command}, port_args)
  end

  @impl true
  def handle_call(:close, _from, state) do
    {:stop, :normal, :ok, fail_all(state, :closed)}
  end

  def handle_call(:tools, from, %__MODULE__{ready: true} = state) do
    {:noreply, async_request(state, "tools/list", %{}, from)}
  end

  def handle_call({:call_tool, name, arguments}, from, %__MODULE__{ready: true} = state) do
    params = %{"name" => name, "arguments" => arguments || %{}}
    {:noreply, async_request(state, "tools/call", params, from)}
  end

  def handle_call(_call, _from, %__MODULE__{ready: false} = state),
    do: {:reply, {:error, :not_ready}, state}

  # Incoming data from the transport (Port or injected ref). Buffer + split lines.
  @impl true
  def handle_info({ref, {:data, chunk}}, %__MODULE__{transport_ref: ref, ready: true} = state) do
    case receive_frames(state, chunk) do
      {:ok, lines, state} ->
        {:noreply, Enum.reduce(lines, state, &handle_line(&2, &1))}

      {:error, reason, lines, state} ->
        state = Enum.reduce(lines, state, &handle_line(&2, &1))
        close_transport(state)
        {:noreply, fail_all(state, reason)}
    end
  end

  # Transport exited — fail any pending callers and mark not-ready. The client
  # process is left alive (ready: false) so the host can observe the failure and
  # shut it down cleanly, rather than racing a reply against an EXIT.
  def handle_info({ref, {:exit_status, status}}, %__MODULE__{transport_ref: ref} = state) do
    close_transport(state)
    {:noreply, fail_all(state, {:server_exited, status})}
  end

  def handle_info({ref, {:eof, _}}, %__MODULE__{transport_ref: ref} = state) do
    close_transport(state)
    {:noreply, fail_all(state, :eof)}
  end

  def handle_info({ref, :eof}, %__MODULE__{transport_ref: ref} = state) do
    close_transport(state)
    {:noreply, fail_all(state, :eof)}
  end

  def handle_info({:EXIT, ref, reason}, %__MODULE__{transport_ref: ref} = state)
      when is_port(ref) do
    {:noreply, fail_all(state, {:port_exited, reason})}
  end

  # Preserve ordinary link semantics for links other than the owned transport.
  # Parent exits are normally consumed by GenServer itself, before handle_info.
  def handle_info({:EXIT, _from, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _from, reason}, state), do: {:stop, reason, state}

  def handle_info({:timeout, timer, {:request_timeout, id}}, state) do
    case Map.get(state.pending, id) do
      %{timer: ^timer} -> {:noreply, finish_pending(state, id, {:error, :timeout})}
      _ -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Map.fetch(state.monitors, monitor) do
      {:ok, id} -> {:noreply, finish_pending(state, id, :no_reply)}
      :error -> {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    fail_all(state, {:client_stopped, reason})
    close_transport(state)
    :ok
  end

  defp close_transport(%{transport_ref: ref}) when is_port(ref) do
    Port.close(ref)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp close_transport(_), do: :ok

  # ---------------------------------------------------------------------------
  # Request machinery
  # ---------------------------------------------------------------------------

  # A synchronous request used during init (before the GenServer loop is serving
  # calls): we send and then receive the matching response inline.
  defp request_sync(state, method, params) do
    id = state.id
    deadline = System.monotonic_time(:millisecond) + state.timeout

    with {:ok, iod} <- encode_request(id, method, params),
         :ok <- send_data(state, iod) do
      await_response(%{state | id: id + 1}, id, deadline)
    end
  end

  # An async request from a GenServer.call: store `from`, send, reply later when
  # the response arrives (in handle_info/handle_line). Returns the new state.
  defp async_request(state, method, params, from) do
    if map_size(state.pending) >= state.max_pending do
      GenServer.reply(from, {:error, :busy})
      state
    else
      id = state.id
      monitor = Process.monitor(elem(from, 0))
      timer = :erlang.start_timer(state.timeout, self(), {:request_timeout, id})
      pending = %{from: from, method: method, monitor: monitor, timer: timer}

      state = %{
        state
        | id: id + 1,
          pending: Map.put(state.pending, id, pending),
          monitors: Map.put(state.monitors, monitor, id)
      }

      with {:ok, iod} <- encode_request(id, method, params),
           :ok <- send_data(state, iod) do
        state
      else
        {:error, reason} -> finish_pending(state, id, {:error, reason})
      end
    end
  end

  defp encode_request(id, method, params) do
    {:ok, Protocol.encode_request(id, method, params)}
  rescue
    error -> {:error, {:encode_failed, error}}
  end

  defp send_data(state, iod) do
    case state.send_fun.(state.transport_ref, iod) do
      {:error, reason} -> {:error, {:send_failed, reason}}
      false -> {:error, {:send_failed, :rejected}}
      _ -> :ok
    end
  rescue
    error -> {:error, {:send_failed, {:exception, error}}}
  catch
    kind, reason -> {:error, {:send_failed, {kind, reason}}}
  end

  # Selective receive leaves other transports and unrelated mailbox messages
  # untouched. Preserve a trailing partial frame when initialize completes.
  defp await_response(%{transport_ref: ref, parent: parent} = state, id, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      receive do
        {^ref, {:data, chunk}} ->
          case receive_frames(state, chunk) do
            {:ok, lines, state} ->
              case find_response(lines, id) do
                {:ok, result} -> {:ok, result, state, nil}
                {:error, _} = error -> error
                :none -> await_response(state, id, deadline)
              end

            {:error, reason, lines, state} ->
              case find_response(lines, id) do
                {:ok, result} -> {:ok, result, state, reason}
                {:error, _} = error -> error
                :none -> {:error, reason}
              end
          end

        {:EXIT, ^ref, reason} when is_port(ref) ->
          {:error, {:port_exited, reason}}

        {:EXIT, ^parent, reason} when is_pid(parent) ->
          {:error, reason}

        {:EXIT, _from, reason} when reason != :normal ->
          {:error, reason}

        {^ref, {:exit_status, status}} ->
          {:error, {:server_exited, status}}

        {^ref, :eof} ->
          {:error, :eof}

        {^ref, {:eof, _}} ->
          {:error, :eof}
      after
        remaining -> {:error, :timeout}
      end
    end
  end

  defp find_response([], _id), do: :none

  defp find_response([line | rest], id) do
    case Protocol.decode(line) do
      {:response, ^id, result} -> {:ok, result}
      {:error_response, ^id, error} -> {:error, error}
      _ -> find_response(rest, id)
    end
  end

  defp handle_line(state, line) do
    case Protocol.decode(line) do
      {:response, id, result} ->
        finish_pending(state, id, {:ok, result})

      {:error_response, id, error} ->
        finish_pending(state, id, {:error, error})

      {:notification, _method, _params} ->
        # Server-initiated notifications are accepted but not acted on (e.g.
        # tools/list_changed could trigger a refresh; out of scope for now).
        state

      :ignore ->
        state
    end
  end

  defp finish_pending(%{pending: pending} = state, id, reply) do
    case Map.pop(pending, id) do
      {nil, _} ->
        state

      {%{from: from, method: method, timer: timer, monitor: monitor}, pending} ->
        Process.cancel_timer(timer)
        Process.demonitor(monitor, [:flush])

        unless reply == :no_reply do
          GenServer.reply(from, map_reply(method, reply))
        end

        %{state | pending: pending, monitors: Map.delete(state.monitors, monitor)}
    end
  end

  defp map_reply(method, reply) do
    case method do
      "tools/list" -> map_tools_reply(reply)
      "tools/call" -> tools_call_reply(reply)
      _ -> reply
    end
  rescue
    error -> {:error, {:invalid_response, error}}
  end

  defp map_tools_reply({:ok, %{"tools" => _} = result}), do: {:ok, map_tools(result, nil)}
  defp map_tools_reply({:ok, _}), do: {:ok, []}
  defp map_tools_reply({:error, _} = e), do: e

  defp tools_call_reply({:ok, result}), do: Protocol.result_to_text(result)
  defp tools_call_reply({:error, _} = e), do: e

  defp map_tools(%{"tools" => tools}, _state) when is_list(tools) do
    client = self()

    Enum.map(tools, fn spec ->
      Protocol.to_tool(spec, fn name, args ->
        __MODULE__.call_tool(client, name, args)
      end)
    end)
  end

  defp map_tools(_, _state), do: []

  defp fail_all(state, reason) do
    Enum.reduce(Map.keys(state.pending), %{state | ready: false, buffer: ""}, fn id, state ->
      finish_pending(state, id, {:error, reason})
    end)
  end

  defp receive_frames(state, chunk) do
    chunk = IO.iodata_to_binary(chunk)

    case split_lines(state.buffer, chunk, state.max_frame_bytes, []) do
      {:ok, lines, buffer} -> {:ok, lines, %{state | buffer: buffer}}
      {:error, reason, lines} -> {:error, reason, lines, %{state | buffer: ""}}
    end
  rescue
    ArgumentError -> {:error, :invalid_transport_data, [], %{state | buffer: ""}}
  end

  defp split_lines(buffer, chunk, limit, lines) do
    case :binary.match(chunk, "\n") do
      {index, 1} when byte_size(buffer) + index <= limit ->
        {line, <<"\n", rest::binary>>} = :erlang.split_binary(chunk, index)
        split_lines("", rest, limit, [buffer <> line | lines])

      :nomatch when byte_size(buffer) + byte_size(chunk) <= limit ->
        # A small trailing sub-binary must not retain a much larger input chunk.
        carry = if buffer == "", do: :binary.copy(chunk), else: buffer <> chunk
        {:ok, Enum.reverse(lines), carry}

      _ ->
        {:error, {:frame_too_large, limit}, Enum.reverse(lines)}
    end
  end
end
