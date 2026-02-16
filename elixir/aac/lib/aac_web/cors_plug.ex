defmodule AacWeb.CorsPlug do
  @moduledoc """
  CORS plug that checks the Origin header against the configured whitelist.
  Mirrors the Python version's after_request CORS handling.
  """
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    if origin do
      run_location = Application.get_env(:aac, :default_run_location, "public-internet")
      locations = Application.get_env(:aac, :run_locations, %{})
      whitelist = get_in(locations, [run_location, "cors_whitelist"]) || []

      if origin in whitelist do
        Logger.info("Welcomed request from whitelisted origin #{inspect(origin)}")

        conn
        |> put_resp_header("access-control-allow-origin", origin)
        |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
        |> put_resp_header("access-control-allow-headers", "content-type, x-rdsc-username")
        |> put_resp_header("access-control-allow-credentials", "true")
        |> handle_preflight()
      else
        Logger.info("Request from non-whitelisted origin #{inspect(origin)}")
        conn
      end
    else
      conn
    end
  end

  defp handle_preflight(%{method: "OPTIONS"} = conn) do
    conn |> send_resp(204, "") |> halt()
  end

  defp handle_preflight(conn), do: conn
end
