defmodule AacWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :aac

  @session_options [
    store: :cookie,
    key: "_aac_key",
    signing_salt: "aac_salt",
    same_site: "Lax"
  ]

  plug Plug.Static,
    at: "/aac/static",
    from: {:aac, "priv/static"},
    gzip: false

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug AacWeb.CorsPlug
  plug AacWeb.Router
end
