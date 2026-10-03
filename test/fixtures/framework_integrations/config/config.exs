import Config

config :req_llm, :load_dotenv, false
config :phoenix, :json_library, Jason

config :framework_integrations, FrameworkIntegrations.Endpoint,
  url: [host: "localhost"],
  server: false,
  secret_key_base: String.duplicate("synthetic-fixture-only-", 4),
  live_view: [signing_salt: "synthetic-fixture"],
  pubsub_server: FrameworkIntegrations.PubSub

config :logger, level: :warning
