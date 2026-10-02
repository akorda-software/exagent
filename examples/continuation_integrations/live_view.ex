defmodule ExAgent.Examples.ContinuationLive do
  @moduledoc """
  Minimal host-owned LiveView recipe. Compile in a Phoenix consumer:

      use ExAgent.Examples.ContinuationLive, host: MyApp.ContinuationHost

  The host implements `open/1`, `live_target/2`, `authorize/4` and
  `present_history/1` and `present_approval/1`. Session authentication, namespace ownership, prompt,
  fresh run options and server resolution belong to that host. Neither client
  params nor PubSub payloads resolve configuration or grant authority.
  """
  use Phoenix.Component
  alias ExAgent.{Event, Server}
  alias Phoenix.LiveView
  require Phoenix.LiveView

  defmacro __using__(opts) do
    host = Keyword.fetch!(opts, :host)

    quote do
      use Phoenix.LiveView
      @continuation_host unquote(host)
      @impl true
      def mount(_params, session, socket),
        do: ExAgent.Examples.ContinuationLive.mount(@continuation_host, session, socket)

      @impl true
      def handle_event(event, params, socket),
        do: ExAgent.Examples.ContinuationLive.event(@continuation_host, event, params, socket)

      @impl true
      def handle_info(message, socket),
        do: ExAgent.Examples.ContinuationLive.info(@continuation_host, message, socket)

      @impl true
      def handle_async(:resume, result, socket),
        do: ExAgent.Examples.ContinuationLive.async(@continuation_host, result, socket)

      @impl true
      def render(assigns), do: ExAgent.Examples.ContinuationLive.render(assigns)
    end
  end

  def mount(host, session, socket) do
    socket =
      assign(socket,
        authorized: false,
        status: :unauthorized,
        persistence: :unknown,
        continuation_status: :none,
        history_count: 0,
        text: "",
        request_id: nil,
        approvals: [],
        notice: "",
        resuming: false,
        deltas: 0
      )

    with {:ok, context} <- host.open(session),
         {:ok, target} <- host.live_target(context, :view),
         :ok <- identity(target),
         :ok <- subscribe(socket, target) do
      socket =
        LiveView.put_private(socket, :exagent_integration, %{context: context, target: target})

      {:ok, socket |> assign(:authorized, true) |> refresh(host)}
    else
      _ -> {:ok, socket}
    end
  end

  def event(host, "refresh", _params, socket), do: {:noreply, refresh(socket, host)}

  def event(host, "run", _params, socket) do
    with {:ok, target} <- resolve(socket, host, :stream),
         {:ok, request_id} <- Server.stream(target.server, target.prompt, target.options) do
      {:noreply, assign(socket, request_id: request_id, text: "", notice: "admitted", deltas: 0)}
    else
      _ -> {:noreply, assign(socket, :notice, "run rejected")}
    end
  end

  def event(host, "approve", params, socket) do
    with {:ok, target} <- resolve(socket, host, :decision),
         {:ok, %{status: :pending, record: record}} <- Server.continuation(target.server),
         {:ok, binding} <- decision_binding(record, params, socket.assigns.approvals) do
      context = socket.private.exagent_integration.context

      opts =
        binding ++
          [
            actor: context.actor,
            authorize: fn actor, decision, requested ->
              host.authorize(context, actor, decision, requested)
            end
          ]

      case Server.decide(target.server, :approve, opts) do
        {:ok, _} -> {:noreply, socket |> assign(:notice, "approved") |> refresh(host)}
        _ -> {:noreply, socket |> assign(:notice, "decision rejected") |> refresh(host)}
      end
    else
      _ -> {:noreply, socket |> assign(:notice, "decision rejected") |> refresh(host)}
    end
  end

  def event(host, "resume", _params, socket) do
    with false <- socket.assigns.resuming,
         {:ok, target} <- resolve(socket, host, :resume),
         {:ok, %{status: status}} when status in [:approved, :ready] <-
           Server.continuation(target.server) do
      # Capture only the resolved server/options, never the socket or session.
      server = target.server
      options = target.options

      {:noreply,
       socket
       |> assign(resuming: true, notice: "resuming")
       |> LiveView.start_async(:resume, fn -> Server.resume(server, options) end)}
    else
      _ -> {:noreply, socket |> assign(:notice, "resume rejected") |> refresh(host)}
    end
  end

  def event(_host, _event, _params, socket), do: {:noreply, socket}

  def info(host, {:exagent_event, %Event{} = event}, socket) do
    state = socket.private[:exagent_integration]

    if state && socket.assigns.authorized && event.version == 1 &&
         event.namespace == state.target.namespace && event.agent_id == state.target.agent_id &&
         event.emitter_id == state.emitter_id && event.request_id == socket.assigns.request_id &&
         is_binary(event.request_id) && is_integer(event.seq) && event.seq > state.seq do
      socket = LiveView.put_private(socket, :exagent_integration, %{state | seq: event.seq})

      socket =
        case event do
          %Event{type: :text_delta, payload: %{text: delta}} when is_binary(delta) ->
            assign(socket, text: socket.assigns.text <> delta, deltas: socket.assigns.deltas + 1)

          %Event{type: type} when type in [:run_finished, :run_failed, :approval_requested] ->
            refresh(socket, host)

          _ ->
            socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def info(_host, _message, socket), do: {:noreply, socket}

  def async(host, {:ok, {:ok, _result}}, socket),
    do: {:noreply, socket |> assign(resuming: false, notice: "resume completed") |> refresh(host)}

  def async(host, _failure, socket),
    do:
      {:noreply,
       socket |> assign(resuming: false, notice: "host recovery required") |> refresh(host)}

  def refresh(socket, host) do
    with {:ok, target} <- resolve(socket, host, :view),
         health <- Server.health(target.server),
         history <- Server.history(target.server) do
      {status, record} =
        case Server.continuation(target.server) do
          {:ok, %{status: status, record: record}} -> {status, record}
          _ -> {:none, nil}
        end

      state = socket.private.exagent_integration
      changed_emitter = Map.get(state, :emitter_id) != health.emitter_id

      socket
      |> LiveView.put_private(
        :exagent_integration,
        %{
          state
          | target: target
        }
        |> Map.put(:emitter_id, health.emitter_id)
        |> Map.put(:seq, if(changed_emitter, do: 0, else: state.seq))
      )
      |> assign(
        status: health.status,
        persistence: if(health.persistence.dirty, do: :checkpoint_pending, else: :confirmed),
        continuation_status: status,
        history_count: length(history),
        text: host.present_history(history),
        request_id:
          if(record, do: record["execution"]["request_id"], else: socket.assigns.request_id),
        approvals: approval_views(record, socket.assigns.approvals, host)
      )
    else
      _ -> assign(socket, authorized: false, notice: "unauthorized", approvals: [], text: "")
    end
  end

  defp resolve(socket, host, action) do
    with %{context: context, target: old} <- socket.private[:exagent_integration],
         {:ok, target} <- host.live_target(context, action),
         true <-
           {target.namespace, target.agent_id, target.pubsub} ==
             {old.namespace, old.agent_id, old.pubsub},
         :ok <- identity(target) do
      {:ok, target}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp identity(target) do
    if is_binary(target.namespace) && is_binary(target.agent_id) &&
         Server.health(target.server).namespace == target.namespace,
       do: :ok,
       else: {:error, :wrong_namespace}
  end

  defp subscribe(socket, target) do
    if LiveView.connected?(socket),
      do:
        Phoenix.PubSub.subscribe(
          target.pubsub,
          Event.agent_topic(target.agent_id, target.namespace)
        ),
      else: :ok
  end

  defp approval_views(nil, _, _), do: []

  defp approval_views(record, old, host) do
    for {id, approval} <- Map.get(record["execution"]["progress"], "approvals", %{}),
        is_nil(approval["decision"]) do
      previous = Enum.find(old, &(&1.approval_id == id && &1.revision == record["revision"]))

      %{
        record_id: record["record_id"],
        revision: record["revision"],
        approval_id: id,
        payload_hash: approval["payload_hash"],
        summary: host.present_approval(approval),
        operation_id:
          if(previous,
            do: previous.operation_id,
            else: "live_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
          )
      }
    end
  end

  defp decision_binding(record, params, visible) do
    keys = ~w(approval_id operation_id payload_hash record_id revision)

    with true <- Enum.sort(Map.keys(params)) == keys,
         value when is_binary(value) and byte_size(value) <= 20 <- params["revision"],
         {revision, ""} <- Integer.parse(value),
         true <- revision == record["revision"] && params["record_id"] == record["record_id"],
         binding when not is_nil(binding) <-
           Enum.find(visible, fn binding ->
             binding.record_id == params["record_id"] && binding.revision == revision &&
               binding.approval_id == params["approval_id"] &&
               binding.payload_hash == params["payload_hash"] &&
               binding.operation_id == params["operation_id"]
           end),
         approval when is_map(approval) <-
           record["execution"]["progress"]["approvals"][binding.approval_id],
         true <- is_nil(approval["decision"]) && approval["payload_hash"] == binding.payload_hash do
      {:ok,
       binding
       |> Map.take([:record_id, :revision, :approval_id, :payload_hash, :operation_id])
       |> Map.to_list()}
    else
      _ -> {:error, :stale_decision}
    end
  end

  def render(assigns) do
    ~H"""
    <main id="continuation">
      <p id="status">{@status}</p>
      <p id="continuation-status">{@continuation_status}</p>
      <p id="persistence">{@persistence}</p>
      <p id="notice">{@notice}</p>
      <p id="history-count">{@history_count}</p>
      <p id="deltas">{@deltas}</p>
      <pre id="output">{@text}</pre>
      <div :if={@authorized}>
        <button id="run" phx-click="run">Run host template</button>
        <button id="refresh" phx-click="refresh">Refresh persisted state</button>
        <button id="resume" phx-click="resume" disabled={@resuming}>Resume approved run</button>
        <button :for={approval <- @approvals} id={"approve-" <> approval.approval_id} phx-click="approve"
          phx-value-record_id={approval.record_id} phx-value-revision={approval.revision}
          phx-value-approval_id={approval.approval_id} phx-value-payload_hash={approval.payload_hash}
          phx-value-operation_id={approval.operation_id}>Approve: {approval.summary}</button>
      </div>
    </main>
    """
  end
end
