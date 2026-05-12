import Config

config :symphony, SymphonyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: String.duplicate("a", 64)
