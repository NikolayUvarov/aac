defmodule AacWeb.RedirectController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  def index(conn, _params) do
    redirect(conn, to: "/aac/static/techIndex.html")
  end
end
