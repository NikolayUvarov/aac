defmodule AacWeb.FuncsetController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Aac.Business.DataKeeper

  def index(conn, _params) do
    json(conn, %{"result" => true, "funcsets" => DataKeeper.get_funcsets()})
  end

  def create(conn, params) do
    if conn.method == "GET" do
      json(conn, %{
        "result" => true,
        "branchList" => DataKeeper.list_branches()
      })
    else
      result = DataKeeper.funcset_create(params["branch"], params["funcset"], params["readablename"])
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def delete(conn, params) do
    if conn.method == "GET" do
      json(conn, %{
        "result" => true,
        "funcSets" => DataKeeper.get_funcsets(),
        "formMethod" => "post",
      })
    else
      result = DataKeeper.funcset_delete(params["funcset"])
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def details(conn, params) do
    funcset = params["funcset"]
    if funcset == nil do
      json(conn, %{
        "result" => true,
        "funcSets" => DataKeeper.get_funcsets(),
        "formMethod" => "get",
      })
    else
      result = DataKeeper.get_funcset_details(funcset)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def func_add(conn, params) do
    if conn.method == "GET" do
      json(conn, %{
        "result" => true,
        "funcSets" => DataKeeper.get_funcsets(),
        "funcList" => elem_or(DataKeeper.list_functions("id"), "values", []),
        "funcRequired" => true,
      })
    else
      result = DataKeeper.funcset_func_add(params["funcset"], params["funcId"])
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def func_remove(conn, params) do
    funcset = params["funcset"] || ""
    func_id = params["funcId"] || ""

    if conn.method == "GET" or funcset == "" or func_id == "" do
      funcs = if funcset != "" do
        case DataKeeper.get_funcset_details(funcset) do
          %{"functions" => f} -> f
          _ -> []
        end
      else
        []
      end
      json(conn, %{
        "result" => true,
        "funcSets" => DataKeeper.get_funcsets(),
        "funcSetInit" => funcset,
        "funcList" => funcs,
        "funcsetAutoSubmit" => funcset == "",
        "funcRequired" => funcset != "",
      })
    else
      result = DataKeeper.funcset_func_remove(funcset, func_id)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  defp elem_or(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp elem_or(_, _key, default), do: default

  defp status_for(result), do: AacWeb.ResponseHelper.status_for(result)
end
