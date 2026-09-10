defmodule ExAgent.MixProject do
  use Mix.Project

  @source_url "https://github.com/akorda-software/exagent"
  @version "1.3.0"

  def project do
    [
      app: :exagent,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      package: package(),
      description: description(),
      # ex_doc
      name: "ExAgent",
      source_url: @source_url,
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "A layered agent framework for Elixir: structured output, tool-calling, " <>
      "streaming, stateful supervised agents, multi-agent sessions, durable " <>
      "persistence, compaction/cost/permissions and MCP — powered by the BEAM."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(lib examples mix.exs README.md docs/README.md docs/status.md docs/changelog.md docs/guides docs/architecture docs/development LICENSE .formatter.exs)
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExAgent.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:finch, "~> 0.22"},
      # Decoder floors protect library consumers too; dependency lockfiles do
      # not constrain the applications that depend on a published Hex package.
      {:mint, "~> 1.10"},
      {:hpax, "~> 1.0 and >= 1.0.4"},
      {:jason, "~> 1.4"},
      {:jsv, "~> 0.22.0"},
      {:ecto, "~> 3.12"},
      {:telemetry, "~> 1.0"},
      # Instrumentation is opt-in; the application owns its SDK and exporter.
      {:opentelemetry_api, "~> 1.5", optional: true},
      # Keep the optional compile-order edge when a host supplies the SDK.
      {:opentelemetry, "~> 1.7", optional: true, runtime: false},
      # Exercise native OTLP locally without adding an exporter to consumers.
      {:opentelemetry_exporter, "~> 1.10.0", only: :test, runtime: false},
      # Only for ExAgent.Store.Postgres tests (the TestRepo needs the adapter).
      # ExAgent.Store.Postgres itself only calls Ecto.Repo.query/3 (from :ecto,
      # already a dependency); a host app that wants a durable store brings its
      # own ecto_sql + postgrex for its repo.
      {:ecto_sql, "~> 3.12", only: :test},
      {:postgrex, "~> 0.22.4", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      check: ["compile --warnings-as-errors", "format", "test"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        {"docs/README.md", filename: "documentation", title: "Documentation index"},
        "docs/status.md",
        "docs/guides/migration.md",
        "docs/guides/observability.md",
        {"docs/architecture/overview.md", filename: "architecture"},
        "docs/architecture/design.md",
        "docs/development/roadmap.md",
        "docs/development/verification.md",
        "docs/development/environment.md",
        "docs/development/backend-evaluation.md",
        "docs/development/handoff.md",
        "docs/changelog.md",
        "LICENSE"
      ],
      groups_for_extras: [
        "Start here": ["README.md", "docs/README.md", "docs/status.md"],
        Guides: ~r"docs/guides/",
        Architecture: ~r"docs/architecture/",
        Development: ~r"docs/development/",
        Reference: ["docs/changelog.md", "LICENSE"]
      ],
      source_ref: "v#{@version}",
      groups_for_modules: [
        "Agent & Loop": [ExAgent, ExAgent.RunContext, ExAgent.UsageLimits],
        Robustness: [
          ExAgent.Compaction,
          ExAgent.Compaction.Summary,
          ExAgent.Compaction.Capability,
          ExAgent.Permissions,
          ExAgent.CostGuard
        ],
        "Stateful Runtime": [ExAgent.Server, ExAgent.AgentSupervisor, ExAgent.Server.Snapshot],
        "Session & Coordination": [
          ExAgent.Session,
          ExAgent.Session.Snapshot,
          ExAgent.Session.Participant,
          ExAgent.Session.SharedState,
          ExAgent.Session.TurnPolicy,
          ExAgent.Session.TurnPolicy.RoundRobin,
          ExAgent.Session.TurnPolicy.Initiative,
          ExAgent.Session.TurnPolicy.SupervisorPolicy,
          ExAgent.Coordination
        ],
        "Events & PubSub": [
          ExAgent.Event,
          ExAgent.PubSub,
          ExAgent.PubSub.None,
          ExAgent.PubSub.Local,
          ExAgent.PubSub.Phoenix
        ],
        Persistence: [ExAgent.Store, ExAgent.Store.ETS, ExAgent.Store.Postgres],
        "External Tools (MCP)": [ExAgent.MCP.Client, ExAgent.MCP.Protocol],
        Messages: [ExAgent.Message],
        "Tools & Output": [ExAgent.Tool, ExAgent.Tools, ExAgent.Schema, ExAgent.OutputSchema],
        Models: [
          ExAgent.Model,
          ExAgent.ModelSettings,
          ExAgent.ModelRequestParameters,
          ExAgent.ModelProfile
        ],
        Providers: [
          ExAgent.Models.OpenAI,
          ExAgent.Models.OpenRouter,
          ExAgent.Models.OpenCode,
          ExAgent.Models.Anthropic,
          ExAgent.Models.Test,
          ExAgent.Providers.OpenAIChat,
          ExAgent.Providers.Anthropic,
          ExAgent.Providers.SSE
        ],
        "Capabilities & Telemetry": [ExAgent.Capability, ExAgent.Capabilities, ExAgent.Telemetry],
        Exceptions: [ExAgent.RequestError, ExAgent.UnexpectedModelBehavior, ExAgent.ModelRetry]
      ]
    ]
  end
end
