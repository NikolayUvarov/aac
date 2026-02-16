defmodule AacWeb.RoleController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Aac.Business.DataKeeper

  def funcsets(conn, params) do
    branch = params["branch"] || ""
    role = params["role"] || ""

    if branch == "" or role == "" do
      roles = if branch != "", do: DataKeeper.list_roles_4_branch(branch), else: []
      json(conn, %{
        "result" => true,
        "formMethod" => "get",
        "branchList" => DataKeeper.list_branches(),
        "branchInit" => branch,
        "branchAutoSubmit" => role == "",
        "rolesList" => roles,
        "roleRequired" => branch != "",
      })
    else
      result = DataKeeper.list_role_funcsets(branch, role)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def funcset_add(conn, params) do
    branch = params["branch"] || ""
    role = params["role"] || ""
    funcset = params["funcset"] || ""

    if conn.method == "GET" or branch == "" or role == "" or funcset == "" do
      roles = if branch != "", do: DataKeeper.list_roles_4_branch(branch), else: []
      json(conn, %{
        "result" => true,
        "branchList" => DataKeeper.list_branches(),
        "branchInit" => branch,
        "branchAutoSubmit" => role == "",
        "rolesList" => roles,
        "roleRequired" => branch != "",
        "funcSets" => DataKeeper.get_funcsets(),
      })
    else
      result = DataKeeper.role_funcset_add(branch, role, funcset)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def funcset_remove(conn, params) do
    branch = params["branch"] || ""
    role = params["role"] || ""
    funcset = params["funcset"] || ""

    if conn.method == "GET" or branch == "" or role == "" or funcset == "" do
      roles = if branch != "", do: DataKeeper.list_roles_4_branch(branch), else: []
      role_fs = if branch != "" and role != "" do
        case DataKeeper.list_role_funcsets(branch, role) do
          %{"funcsets" => fs} -> fs
          _ -> []
        end
      else
        []
      end
      json(conn, %{
        "result" => true,
        "branchList" => DataKeeper.list_branches(),
        "branchInit" => branch,
        "branchAutoSubmit" => role == "",
        "rolesList" => roles,
        "roleRequired" => branch != "",
        "roleInit" => role,
        "roleAutoSubmit" => funcset == "",
        "funcSets" => role_fs,
        "funcSetRequired" => branch != "" and role != "",
      })
    else
      result = DataKeeper.role_funcset_remove(branch, role, funcset)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  defp status_for(result), do: AacWeb.ResponseHelper.status_for(result)
end
