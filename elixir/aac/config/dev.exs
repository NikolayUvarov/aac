import Config

config :aac, AacWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 5001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  watchers: []

config :logger, :console, format: "[$level] $message\n"
