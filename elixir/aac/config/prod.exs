import Config

config :aac, AacWeb.Endpoint,
  url: [host: "localhost", port: 5001],
  check_origin: false

config :logger, level: :info
