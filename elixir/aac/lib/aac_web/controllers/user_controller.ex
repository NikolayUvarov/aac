defmodule AacWeb.UserController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Aac.Business.DataKeeper

  def list(conn, _params) do
    json(conn, DataKeeper.list_users())
  end

  def create(conn, params) do
    if conn.method == "GET" do
      users = DataKeeper.list_users()
      json(conn, %{
        "result" => true,
        "userList" => users["users"],
        "operList" => users["users"],
        "init" => %{ "sessionMax" => Application.get_env(:aac, :session_max_default, 60) },
      })
    else
      result = DataKeeper.create_user(
        params["username"], params["secret"], params["operator"],
        params["pswlifetime"], params["readablename"] || "", params["sessionmax"]
      )
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def change(conn, params) do
    secret = params["secret"] || ""
    if conn.method == "GET" or secret == "" do
      users = DataKeeper.list_users()
      username = params["username"] || ""
      olddata = if username == "" do
        %{}
      else
        det = DataKeeper.get_user_reg_details(username)
        if det["result"], do: det, else: %{}
      end

      json(conn, %{
        "result" => true,
        "userList" => users["users"],
        "operList" => users["users"],
        "init" => olddata,
        "userAutoSubmit" => secret == "",
        "useridInit" => username,
      })
    else
      result = DataKeeper.change_user(
        params["username"], secret, params["operator"],
        params["pswlifetime"], params["readablename"] || "", params["sessionmax"]
      )
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def delete(conn, params) do
    if conn.method == "GET" do
      users = DataKeeper.list_users()
      json(conn, %{
        "result" => true,
        "userList" => users["users"],
        "operList" => users["users"],
        "operatorDriven" => true,
        "formMethod" => "post",
      })
    else
      result = DataKeeper.delete_user(params["username"], params["operator"])
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  defp status_for(result), do: AacWeb.ResponseHelper.status_for(result)
end
