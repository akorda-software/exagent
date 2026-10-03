defmodule FrameworkIntegrations.MixProject do
  use Mix.Project

  def project do
    [
      app: :framework_integrations,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: ["lib", "recipes"],
      test_load_filters: [~r{/cases\.exs$}],
      deps: [
        {:exagent, path: System.fetch_env!("EXAGENT_FRAMEWORK_CORE")},
        {:phoenix, "== 1.8.15"},
        {:phoenix_live_view, "== 1.2.12"},
        {:phoenix_pubsub, "== 2.3.0"},
        {:phoenix_html, "~> 4.1"},
        {:oban, "== 2.24.1"},
        {:ecto_sql, "== 3.14.0"},
        {:postgrex, "== 0.22.4"},
        {:lazy_html, "== 0.1.13", only: :test},
        {:floki, "~> 0.38.0", only: :test}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
