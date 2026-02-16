defmodule AacWeb.AuthController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Aac.Business.DataKeeper

  def authorize(conn, params) do
    username = params["username"]
    secret = params["secret"]

    if username == nil or secret == nil do
      users = DataKeeper.list_users()
      json(conn, %{"result" => true, "userList" => users["users"]})
    else
      app_name = if conn.request_path == "/aac/authentificate" do
        nil
      else
        params["app"] || ""
      end

      result = DataKeeper.authorize(username, secret, app_name)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def user_details(conn, params) do
    username = params["username"]
    app = params["app"] || ""

    if username == nil do
      users = DataKeeper.list_users()
      json(conn, %{"result" => true, "userList" => users["users"]})
    else
      result = DataKeeper.get_user_reg_details(username, app)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  defp status_for(result), do: AacWeb.ResponseHelper.status_for(result)
end
