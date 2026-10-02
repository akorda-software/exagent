defmodule FrameworkIntegrations.Repo do
  use Ecto.Repo, otp_app: :framework_integrations, adapter: Ecto.Adapters.Postgres
end

defmodule FrameworkIntegrations.Host do
  alias FrameworkIntegrations.Repo
  alias ExAgent.{Permissions, Store, Tool}
  alias ExAgent.Message.Part

  def put(id, namespace, server \\ nil) do
    target = %{
      reference: namespace <> "/" <> id,
      agent_id: id,
      namespace: namespace,
      pubsub: FrameworkIntegrations.PubSub,
      server: server,
      agent: agent(id, namespace),
      continuation: config(id, namespace),
      prompt: "synthetic host template",
      options: [
        permissions: Permissions.new!(default: :ask),
        stream_text: true,
        deps: %{private_credential: "synthetic-private-option"}
      ],
      enabled: true
    }

    Agent.update(__MODULE__, &Map.put(&1, target.reference, target))
    target
  end

  def target(reference), do: Agent.get(__MODULE__, &Map.get(&1, reference))

  def put_crashing(id, namespace) do
    target = put(id, namespace)

    target = %{
      target
      | agent: agent(id, namespace, true),
        continuation: %{target.continuation | lease_ms: 1_000},
        options: [permissions: Permissions.new!(default: :allow)]
    }

    Agent.update(__MODULE__, &Map.put(&1, target.reference, target))
    target
  end

  def server(reference, server),
    do: Agent.update(__MODULE__, &put_in(&1, [reference, :server], server))

  def disable(reference), do: Agent.update(__MODULE__, &put_in(&1, [reference, :enabled], false))

  # Fixture session refs stand for a trusted application session lookup. A real
  # application authenticates the signed session and current account here.
  def open(%{"session_ref" => reference, "access" => access})
      when access in ["owner", "viewer"] do
    case target(reference) do
      %{enabled: true, namespace: namespace} ->
        {:ok,
         %{
           reference: reference,
           actor: %{id: access, namespace: namespace, credential: "synthetic-private-actor"}
         }}

      _ ->
        {:error, :unauthorized}
    end
  end

  def open(_session), do: {:error, :unauthorized}

  def live_target(context, action) do
    case target(context.reference) do
      %{enabled: true, namespace: namespace} = target ->
        if namespace == context.actor.namespace &&
             (action == :view || context.actor.id == "owner"),
           do: {:ok, target},
           else: {:error, :unauthorized}

      _ ->
        {:error, :unauthorized}
    end
  end

  def authorize(context, actor, :approve, requested) do
    case live_target(context, :decision) do
      {:ok, target} ->
        with true <- actor == context.actor,
             {:ok, %{record: current}} <-
               ExAgent.Continuation.get(target.continuation.store, target.agent_id),
             true <- current["record_id"] == requested.record_id do
          {:ok, target.namespace <> "/" <> actor.id}
        else
          _ -> {:error, :unauthorized}
        end

      _ ->
        {:error, :unauthorized}
    end
  end

  def authorize(_context, _actor, _decision, _requested), do: {:error, :unauthorized}

  # A service principal is established by this host lookup. Job JSON cannot
  # choose an actor, executable module, template, credentials, or run options.
  def job_target(reference) do
    case target(reference) do
      %{enabled: true} = target -> {:ok, target}
      _ -> {:error, :unauthorized}
    end
  end

  def present_history(history) do
    history
    |> Enum.filter(&match?(%ExAgent.Message.Response{}, &1))
    |> Enum.flat_map(& &1.parts)
    |> Enum.flat_map(fn
      %Part.Text{content: text} -> [text]
      _ -> []
    end)
    |> Enum.join("\n")
  end

  def counts(reference) do
    %{rows: rows} =
      Repo.query!(
        "SELECT kind, count(*) FROM fixture_observations WHERE reference=$1 GROUP BY kind",
        [reference]
      )

    Map.merge(
      %{"request" => 0, "effect" => 0},
      Map.new(rows, fn [kind, count] -> {kind, count} end)
    )
  end

  def present_approval(approval),
    do: approval["tool_name"] <> " " <> Jason.encode!(approval["args"])

  defp count(reference, kind),
    do:
      Repo.query!("INSERT INTO fixture_observations (reference,kind) VALUES ($1,$2)", [
        reference,
        kind
      ])

  defp agent(id, namespace, crash? \\ false) do
    reference = namespace <> "/" <> id

    tool =
      Tool.new(
        name: "effect",
        parameters_json_schema: %{"type" => "object"},
        max_retries: 0,
        call: fn _, _ ->
          count(reference, "effect")
          if crash?, do: System.halt(73)
          {:ok, "saved"}
        end
      )

    script = [
      fn _, _ ->
        count(reference, "request")

        %ExAgent.Message.Response{
          parts: [%Part.ToolCall{tool_name: "effect", tool_call_id: "one", args: %{}}]
        }
      end,
      fn _, _ ->
        count(reference, "request")
        "synthetic completed output"
      end
    ]

    ExAgent.new(model: %ExAgent.Models.Test{script: script}, tools: [tool])
  end

  defp config(id, namespace) do
    %{
      store: Store.scoped({Store.Postgres, {Repo, table: "fixture_records"}}, namespace),
      id: id,
      durability: :durable,
      expires_at: nil,
      lease_ms: 30_000,
      active_time_limit_ms: 20_000,
      definition: %{"id" => "synthetic-template", "version" => "1"},
      policy: %{"id" => "synthetic-policy", "version" => "1"},
      model_ref: %{"id" => "test", "version" => "1"},
      model_codec: %{
        dump: fn model -> {:ok, %{"index" => model.index}} end,
        load: fn model, %{"index" => index} -> {:ok, %{model | index: index}} end
      }
    }
  end
end

defmodule FrameworkIntegrations.Live do
  use ExAgent.Examples.ContinuationLive, host: FrameworkIntegrations.Host
end

defmodule FrameworkIntegrations.Worker do
  use ExAgent.Examples.ContinuationWorker, host: FrameworkIntegrations.Host
end

defmodule FrameworkIntegrations.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/" do
    pipe_through(:browser)
    live("/continuation", FrameworkIntegrations.Live)
  end
end

defmodule FrameworkIntegrations.Endpoint do
  use Phoenix.Endpoint, otp_app: :framework_integrations
  @session_options [store: :cookie, key: "_synthetic_fixture", signing_salt: "synthetic-session"]
  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])
  plug(Plug.Session, @session_options)
  plug(FrameworkIntegrations.Router)
end
