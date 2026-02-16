import Config

config :aac,
  ecto_repos: [Aac.Repo]

config :aac, Aac.Repo,
  database: Path.expand("../priv/repo/aac.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :aac, AacWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: AacWeb.ErrorJSON], layout: false],
  pubsub_server: Aac.PubSub,
  live_view: [signing_salt: "aac_salt"]

config :aac,
  session_max_default: 60,
  default_run_location: "public-internet",
  run_locations: %{
    "public-internet" => %{
      "port" => 5001,
      "cors_whitelist" => [
        "http://127.0.0.1:5000",
        "http://localhost:5000",
        "http://127.0.0.1:5001"
      ]
    },
    "rdsctest" => %{
      "port" => 5001,
      "cors_whitelist" => [
        "http://127.0.0.1:5000",
        "http://localhost:5000",
        "http://d.rdsc.ru:14300",
        "http://d.rdsc.ru:14500",
        "http://d.rdsc.ru:5001"
      ]
    }
  }

config :logger, :console,
  format: "[$level] $metadata$message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
