defmodule AacWeb.BranchController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Aac.Business.DataKeeper

  def index(conn, _params) do
    result = %{"result" => true, "data" => DataKeeper.get_branches("")}
    json(conn, result)
  end

  def subbranches(conn, params) do
    branch_id = params["branch"]
    if branch_id == nil do
      json(conn, %{
        "result" => true,
        "formMethod" => "get",
        "branchList" => DataKeeper.list_branches(),
        "branchCanBeEmpty" => true,
        "label4Branch" => "Parent branch (or leave empty for root)",
      })
    else
      result = DataKeeper.get_branch_subs(branch_id)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def subbranch_add(conn, params) do
    if conn.method == "GET" do
      json(conn, %{
        "result" => true,
        "formMethod" => "post",
        "branchList" => DataKeeper.list_branches(),
        "label4Branch" => "Parent branch",
        "subBranchRequired" => true,
      })
    else
      result = DataKeeper.add_branch_sub(params["branch"], params["subbranch"])
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def delete(conn, params) do
    if conn.method == "GET" do
      json(conn, %{
        "result" => true,
        "formMethod" => "post",
        "branchList" => DataKeeper.list_branches()
      })
    else
      result = DataKeeper.delete_branch(params["branch"])
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def fswl_get(conn, params) do
    branch_id = params["branch"]
    if branch_id == nil do
      json(conn, %{
        "result" => true,
        "branchList" => DataKeeper.list_branches()
      })
    else
      result = DataKeeper.get_branch_fs_whitelist(branch_id)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def fswl_set(conn, params) do
    if conn.method == "GET" do
      branch = params["branch"] || ""
      init = if branch == "", do: %{}, else: DataKeeper.get_branch_fs_whitelist(branch)
      json(conn, %{
        "result" => true,
        "branchList" => DataKeeper.list_branches(),
        "branchInit" => branch,
        "branchAutoSubmit" => branch == "",
        "funcSets" => DataKeeper.get_funcsets(),
        "init" => init,
      })
    else
      branch = params["branch"]
      prop_parent = params["propparent"] == "yes"
      wl = List.wrap(params["white"])
      result = DataKeeper.set_branch_fs_whitelist(branch, prop_parent, wl)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def roles_list(conn, params) do
    branch_id = params["branch"]
    if branch_id == nil do
      json(conn, %{
        "result" => true,
        "branchList" => DataKeeper.list_branches(),
        "cboxes" => [
          ["inherited", "Include inherited roles"],
          ["withbranchids", "Report also branch IDs"],
        ],
      })
    else
      inherited = params["inherited"] == "yes"
      with_brids = params["withbranchids"] == "yes"
      result = DataKeeper.list_branch_roles(branch_id, inherited, with_brids)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def role_create(conn, params) do
    branch = params["branch"] || ""
    role = params["role"] || ""

    if conn.method == "GET" or branch == "" or role == "" do
      enabled_fs = if branch != "", do: DataKeeper.get_branch_enabled_funcsets(branch), else: []
      json(conn, %{
        "result" => true,
        "formMethod" => "post",
        "branchList" => DataKeeper.list_branches(),
        "branchInit" => branch,
        "branchAutoSubmit" => branch == "",
        "roleRequired" => branch != "",
        "funcSets" => DataKeeper.get_funcsets(),
        "enabledFuncSets" => enabled_fs,
      })
    else
      duties = List.wrap(params["duties"])
      result = DataKeeper.create_branch_role(branch, role, duties)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def role_delete(conn, params) do
    branch = params["branch"] || ""
    role = params["role"] || ""

    if conn.method == "GET" or branch == "" or role == "" do
      roles = if branch != "", do: DataKeeper.list_roles_4_branch(branch), else: []
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
      result = DataKeeper.delete_branch_role(branch, role)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def employees_list(conn, params) do
    branch_id = params["branch"] || ""
    if branch_id == "" do
      json(conn, %{
        "result" => true,
        "branchList" => DataKeeper.list_branches(),
        "cboxes" => [["includeSubBranches", "Include sub-branches"]],
      })
    else
      include_sub = params["includeSubBranches"] == "yes"
      result = DataKeeper.branch_employees_list(branch_id, include_sub)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  defp status_for(result), do: AacWeb.ResponseHelper.status_for(result)
end
