defmodule AacWeb.FunctionController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Aac.Business.DataKeeper

  def list(conn, params) do
    prop = params["prop"]
    if prop == nil do
      json(conn, %{"result" => true})
    else
      result = DataKeeper.list_functions(prop)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def review(conn, params) do
    props = params["props"]
    func_id = if conn.request_path == "/aac/functions/review", do: nil, else: params["funcId"] || -1

    if props == nil or func_id == -1 do
      functions = case DataKeeper.list_functions("id") do
        %{"values" => v} -> v
        _ -> []
      end

      if conn.request_path == "/aac/function/review" do
        json(conn, %{
          "result" => true,
          "funcList" => functions,
        })
      else
        json(conn, %{
          "result" => true,
        })
      end
    else
      result = DataKeeper.review_functions(props, func_id)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def review_all(conn, params) do
    review(conn, params)
  end

  def info(conn, params) do
    func_id = params["funcId"] || ""
    xsltref = params["xsltref"] || ""
    pure = params["pure"] || "no"

    if func_id == "" do
      functions = case DataKeeper.list_functions("id") do
        %{"values" => v} -> v
        _ -> []
      end
      json(conn, %{
        "result" => true,
        "funcRequired" => true,
        "funcList" => functions,
      })
    else
      header = if xsltref == "" do
        ""
      else
        quoted = xml_attr_quote(xsltref)
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<?xml-stylesheet type=\"text/xsl\" href=#{quoted}?>\n\n"
      end

      result = DataKeeper.get_function_def(func_id, header)
      if pure == "yes" and result["result"] do
        conn
        |> put_resp_content_type("text/xml", "utf-8")
        |> send_resp(200, result["definition"])
      else
        conn |> put_status(status_for(result)) |> json(result)
      end
    end
  end

  def delete(conn, params) do
    if conn.method == "GET" do
      functions = case DataKeeper.list_functions("id") do
        %{"values" => v} -> v
        _ -> []
      end
      json(conn, %{
        "result" => true,
        "funcRequired" => true,
        "funcList" => functions,
        "formMethod" => "post",
      })
    else
      result = DataKeeper.delete_function_def(params["funcId"])
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def upload_xml_descr(conn, params) do
    if conn.method == "GET" do
      json(conn, %{"result" => true})
    else
      result = DataKeeper.post_function_def(params["xmltext"])
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def upload_xml_file(conn, params) do
    if conn.method == "GET" do
      json(conn, %{"result" => true})
    else
      case params["xmlfile"] do
        %Plug.Upload{path: path} ->
          txt = File.read!(path)
          result = DataKeeper.post_function_def(txt)
          conn |> put_status(status_for(result)) |> json(result)
        _ ->
          result = %{"result" => false, "reason" => "WRONG-FORMAT"}
          conn |> put_status(status_for(result)) |> json(result)
      end
    end
  end

  def tagset_modify(conn, params) do
    if conn.method == "GET" do
      functions = case DataKeeper.list_functions("id") do
        %{"values" => v} -> v
        _ -> []
      end
      json(conn, %{
        "result" => true,
        "formMethod" => "post",
        "funcRequired" => true,
        "funcList" => functions,
      })
    else
      func_id = params["funcId"]
      method = params["method"]
      tags = parse_tagset(params["tag"])
      result = DataKeeper.modify_func_tagset(func_id, method, tags)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def tagset_test(conn, params) do
    func_id = params["funcId"]
    method = params["method"]
    if func_id in [nil, ""] or method in [nil, ""] do
      functions = case DataKeeper.list_functions("id") do
        %{"values" => v} -> v
        _ -> []
      end
      json(conn, %{
        "result" => true,
        "formMethod" => "get",
        "funcRequired" => true,
        "funcList" => functions,
        "readOnly" => true,
      })
    else
      tags = parse_tagset(params["tag"])
      result = DataKeeper.modify_func_tagset(func_id, method, tags, true)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  defp parse_tagset(nil), do: []
  defp parse_tagset(tags) when is_list(tags), do: Enum.reject(tags, & &1 == "")
  defp parse_tagset(tag), do: [tag] |> Enum.reject(& &1 == "")

  defp xml_attr_quote(value) do
    escaped =
      value
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")

    if String.contains?(value, "\"") and not String.contains?(value, "'") do
      "'#{escaped}'"
    else
      escaped =
        escaped
        |> String.replace("\"", "&quot;")

      "\"#{escaped}\""
    end
  end

  defp status_for(result), do: AacWeb.ResponseHelper.status_for(result)
end
