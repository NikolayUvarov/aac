import Config

if config_env() == :prod do
  config :aac, Aac.Repo,
    database: System.get_env("DATABASE_PATH") || "priv/repo/aac.db"

  port = String.to_integer(System.get_env("PORT") || "5001")

  config :aac, AacWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    server: true
end
