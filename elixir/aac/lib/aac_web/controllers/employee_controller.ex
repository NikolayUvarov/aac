defmodule AacWeb.EmployeeController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Aac.Business.DataKeeper

  def positions(conn, params) do
    branch_id = params["branch"]
    if branch_id == nil do
      json(conn, %{
        "result" => true,
        "branchList" => ["*ALL*" | DataKeeper.list_branches()],
        "cboxes" => [
          ["perRole", "Per-role report", true],
          ["onlyVacant", "Report only vacant positions", true],
        ],
      })
    else
      per_role = params["perRole"] == "yes"
      only_vacant = params["onlyVacant"] == "yes"
      result = DataKeeper.get_branches_with_positions(branch_id, per_role, only_vacant)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def position_create(conn, params) do
    branch = params["branch"] || ""
    role = params["role"] || ""

    if conn.method == "GET" or branch == "" or role == "" do
      roles = if branch != "", do: DataKeeper.list_enabled_roles_4_branch(branch), else: []
      json(conn, %{
        "result" => true,
        "formMethod" => "post",
        "branchList" => DataKeeper.list_branches(),
        "branchInit" => branch,
        "branchAutoSubmit" => role == "",
        "rolesList" => roles,
        "roleRequired" => branch != "",
      })
    else
      result = DataKeeper.create_branch_position(branch, role)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def position_delete(conn, params) do
    branch = params["branch"] || ""
    role = params["role"] || ""

    if conn.method == "GET" or branch == "" or role == "" do
      roles = if branch != "", do: DataKeeper.get_branch_vacant_positions(branch), else: []
      json(conn, %{
        "result" => true,
        "formMethod" => "post",
        "branchList" => DataKeeper.list_branches(),
        "branchInit" => branch,
        "branchAutoSubmit" => role == "",
        "rolesList" => roles,
        "roleRequired" => branch != "",
      })
    else
      result = DataKeeper.delete_branch_position(branch, role)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def hire(conn, params) do
    u = params["username"] || ""
    b = params["branch"] || ""
    p = params["position"] || ""
    operator = params["operator"] || ""

    if conn.method == "GET" or b == "" or p == "" do
      users = DataKeeper.list_users()
      json(conn, %{
        "result" => true,
        "userList" => users["users"],
        "branchReview" => DataKeeper.review_branches(p),
        "posReview" => DataKeeper.review_positions(b),
        "init" => %{"u" => u, "b" => b, "p" => p},
        "operList" => users["users"],
      })
    else
      result = DataKeeper.hire_employee(u, b, p, operator)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def fire(conn, params) do
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
      result = DataKeeper.fire_employee(params["username"], params["operator"])
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def get_positions(conn, params) do
    branch = params["filter"] || ""
    result = %{"result" => true, "data" => DataKeeper.get_positions(branch)}
    json(conn, result)
  end

  def subbranches_list(conn, params) do
    username = params["username"]
    if username == nil do
      json(conn, %{
        "result" => true,
        "userList" => DataKeeper.list_users()["users"],
      })
    else
      all_levels = (params["allLevels"] || "yes") == "yes"
      exclude_own = params["excludeOwn"] == "yes"
      result = DataKeeper.emp_subbranches_list(username, all_levels, exclude_own)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def funcsets_list(conn, params) do
    username = params["username"]
    if username == nil do
      json(conn, %{
        "result" => true,
        "userList" => DataKeeper.list_users()["users"],
        "formMethod" => "get",
      })
    else
      result = DataKeeper.emp_funcsets_list(username)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def functions_list(conn, params) do
    username = params["username"]
    if username == nil do
      json(conn, %{
        "result" => true,
        "userList" => DataKeeper.list_users()["users"],
        "formMethod" => "get",
      })
    else
      prop = params["prop"] || "id"
      result = DataKeeper.emp_functions_list(username, prop)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def functions_review(conn, params) do
    username = params["username"]
    props = params["props"]
    if username == nil or props == nil do
      json(conn, %{
        "result" => true,
        "userList" => DataKeeper.list_users()["users"],
        "formMethod" => "get",
      })
    else
      result = DataKeeper.emp_functions_review(username, props)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  defp status_for(result), do: AacWeb.ResponseHelper.status_for(result)
end
