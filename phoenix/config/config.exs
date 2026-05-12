import Config

config :symphony, SymphonyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SymphonyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: nil,
  live_view: [signing_salt: "phase1-symphony"]

config :phoenix, :json_library, Jason
