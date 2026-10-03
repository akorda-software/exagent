Code.require_file("docs/markdown_formatter.exs", __DIR__)

defmodule ExAgent.MixProject do
  use Mix.Project

  @source_url "https://github.com/akorda-software/exagent"
  @version "1.3.0"

  def project do
    [
      app: :exagent,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      # This separate consumer application is exercised by its own runner.
      test_ignore_filters: [~r"^test/fixtures/framework_integrations/"],
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
        ~w(lib examples mix.exs README.md docs/home.md docs/assets docs/site docs/markdown_formatter.exs docs/README.md docs/status.md docs/changelog.md docs/guides docs/architecture docs/development LICENSE .formatter.exs)
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
      {:req_llm, "~> 1.26.0"},
      {:req, "~> 0.7.4"},
      {:finch, "~> 0.24"},
      # Decoder floors protect library consumers too; dependency lockfiles do
      # not constrain the applications that depend on a published Hex package.
      {:mint, "~> 1.11"},
      {:hpax, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:jsv, "~> 0.25.0"},
      {:ecto, "~> 3.12"},
      {:telemetry, "~> 1.0"},
      # Instrumentation is opt-in; the application owns its SDK and exporter.
      {:opentelemetry_api, "~> 1.5", optional: true},
      # Keep the optional compile-order edge when a host supplies the SDK.
      {:opentelemetry, "~> 1.7", optional: true, runtime: false},
      # Exercise native OTLP locally without adding an exporter to consumers.
      {:opentelemetry_exporter, "~> 1.11.0", only: :test, runtime: false},
      # Only for ExAgent.Store.Postgres tests (the TestRepo needs the adapter).
      # ExAgent.Store.Postgres itself only calls Ecto.Repo.query/3 (from :ecto,
      # already a dependency); a host app that wants a durable store brings its
      # own ecto_sql + postgrex for its repo.
      {:ecto_sql, "~> 3.12", only: :test},
      {:postgrex, "~> 0.22.4", only: :test},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      check: ["compile --warnings-as-errors", "format", "test"]
    ]
  end

  defp docs do
    [
      main: "welcome",
      formatters: ["html", ExAgent.Docs.Markdown, "epub"],
      assets: %{"docs/assets" => "assets", "docs/site" => ""},
      before_closing_head_tag: &docs_head/1,
      before_closing_footer_tag: &docs_footer/1,
      extras: [
        {"docs/home.md", filename: "welcome", title: "Welcome"},
        "docs/guides/getting-started.md",
        "docs/guides/tools-and-output.md",
        "docs/guides/models-and-limits.md",
        "docs/guides/runtime-and-events.md",
        "docs/guides/durability-and-approvals.md",
        "docs/guides/coordination.md",
        "docs/guides/testing.md",
        "docs/guides/mcp.md",
        "docs/guides/troubleshooting.md",
        "docs/guides/agents.md",
        "README.md",
        {"docs/README.md", filename: "documentation", title: "Documentation index"},
        "docs/status.md",
        "docs/guides/migration.md",
        "docs/guides/observability.md",
        {"docs/architecture/overview.md", filename: "architecture"},
        "docs/architecture/design.md",
        "docs/development/roadmap.md",
        "docs/development/r4-implementation.md",
        "docs/development/r5-implementation.md",
        "docs/development/r6-implementation.md",
        "docs/development/r7-mcp-implementation.md",
        "docs/development/continuation-jobs.md",
        "docs/development/framework-integrations.md",
        "docs/development/coordination-recipes.md",
        "docs/development/external-retrieval.md",
        "docs/development/mcp-continuation-binding.md",
        "docs/development/otlp-transport.md",
        "docs/development/otlp-isolated-transport.md",
        "docs/development/otlp-collector-transport.md",
        "docs/development/release-scope.md",
        "docs/development/production-acceptance.md",
        "docs/development/jido-comparison.md",
        "docs/development/framework-direction.md",
        "docs/development/verification.md",
        "docs/development/dependencies.md",
        "docs/development/known-limits.md",
        "docs/development/real-consumer-e2e.md",
        "docs/development/testing-audit.md",
        "docs/development/execution-flow.md",
        "docs/development/environment.md",
        "docs/development/backend-evaluation.md",
        "docs/development/handoff.md",
        "docs/changelog.md",
        "LICENSE"
      ],
      groups_for_extras: [
        "Start here": ["docs/home.md", "docs/guides/getting-started.md", "docs/README.md"],
        "Build with ExAgent": [
          "docs/guides/tools-and-output.md",
          "docs/guides/models-and-limits.md",
          "docs/guides/runtime-and-events.md",
          "docs/guides/durability-and-approvals.md",
          "docs/guides/coordination.md",
          "docs/guides/testing.md",
          "docs/guides/observability.md",
          "docs/guides/mcp.md",
          "docs/guides/troubleshooting.md"
        ],
        Integrations: [
          "docs/development/continuation-jobs.md",
          "docs/development/framework-integrations.md",
          "docs/development/coordination-recipes.md",
          "docs/development/external-retrieval.md",
          "docs/development/mcp-continuation-binding.md",
          "docs/development/otlp-isolated-transport.md",
          "docs/development/otlp-collector-transport.md"
        ],
        Reference: [
          "docs/guides/agents.md",
          "docs/guides/migration.md",
          "README.md",
          "docs/status.md",
          "docs/changelog.md",
          "LICENSE"
        ],
        Architecture: ~r"docs/architecture/",
        "Maintaining ExAgent": ~r"docs/development/"
      ],
      source_ref: System.get_env("EXAGENT_DOCS_SOURCE_REF", "main"),
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
          ExAgent.Coordination,
          ExAgent.Coordination.Composition,
          ExAgent.Coordination.Flow
        ],
        "Events & PubSub": [
          ExAgent.Event,
          ExAgent.PubSub,
          ExAgent.PubSub.None,
          ExAgent.PubSub.Local,
          ExAgent.PubSub.Phoenix
        ],
        Persistence: [ExAgent.Store, ExAgent.Store.ETS, ExAgent.Store.Postgres],
        "Continuation & Recovery": [
          ExAgent.Continuation,
          ExAgent.Continuation.Record,
          ExAgent.Continuation.Checkpoint,
          ExAgent.CheckpointError
        ],
        "External Tools (MCP)": [
          ExAgent.MCP.Client,
          ExAgent.MCP.Protocol,
          ExAgent.MCP.StreamableHTTP
        ],
        Messages: [ExAgent.Message],
        "Tools & Output": [ExAgent.Tool, ExAgent.Tools, ExAgent.Schema, ExAgent.OutputSchema],
        Models: [
          ExAgent.Model,
          ExAgent.ModelSettings,
          ExAgent.ModelRequestParameters,
          ExAgent.ModelProfile
        ],
        Providers: [
          ExAgent.Models.ReqLLM,
          ExAgent.Models.Test
        ],
        "Capabilities & Telemetry": [ExAgent.Capability, ExAgent.Capabilities, ExAgent.Telemetry],
        Observability: [
          ExAgent.Observability.OpenTelemetry,
          ExAgent.Observability.ReqLLM,
          ExAgent.Observability.BoundedProcessor
        ],
        Exceptions: [
          ExAgent.RunError,
          ExAgent.RequestError,
          ExAgent.UnexpectedModelBehavior,
          ExAgent.ModelRetry
        ]
      ]
    ]
  end

  defp docs_head(:html), do: ~s(<link rel="stylesheet" href="assets/exagent.css" />)
  defp docs_head(_format), do: ""

  defp docs_footer(:html),
    do:
      ~s(<p class="exagent-release-note">Unreleased v2 candidate · nominal v#{@version} · <a href="status.html">Support and release status</a> · <a href="llms.txt">View llms.txt</a></p>)
end
