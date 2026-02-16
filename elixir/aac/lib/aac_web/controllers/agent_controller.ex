defmodule AacWeb.AgentController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Aac.Business.DataKeeper

  def register(conn, params) do
    if conn.method == "GET" do
      json(conn, %{
        "result" => true,
        "formMethod" => "post",
        "branchList" => ["*ROOT*"] ++ DataKeeper.list_branches(),
        "extratxtinputs" => [
          ["descr", "Description", ""],
          ["location", "Location", ""],
          ["tags", "Tags (comma separated)", ""],
          ["extraxml", "Optional info in free XML format", ""],
        ],
      })
    else
      result = DataKeeper.register_agent_in_branch(
        params["branch"] || "",
        params["agent"] || "",
        move: false,
        descr: params["descr"] || "",
        location: params["location"] || "",
        tags: params["tags"] || "",
        extra_xml: params["extraxml"] || ""
      )
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def movedown(conn, params) do
    branch = params["branch"] || ""
    agent = params["agent"] || ""

    if conn.method == "GET" or branch == "" or agent == "" do
      ini = %{"descr" => "", "extra" => "", "location" => "", "tags" => ""}

      ini =
        if agent != "" do
          case DataKeeper.agent_details_json(agent) do
            %{"result" => true, "details" => details} ->
              %{
                "descr" => details["descr"] || "",
                "location" => details["location"] || "",
                "tags" => details["tags"] || "",
                "extra" => details["extra"] || "",
              }
            _ ->
              ini
          end
        else
          ini
        end

      json(conn, %{
        "result" => true,
        "formMethod" => "post",
        "agentsList" => DataKeeper.get_agents() |> Enum.sort(),
        "agentInit" => agent,
        "agentAutoSubmit" => branch == "",
        "branchList" => if(agent == "", do: [], else: DataKeeper.get_sub_branches_of_agent(agent)),
        "extratxtinputs" => [
          ["descr", "Description", ini["descr"]],
          ["location", "Location", ini["location"]],
          ["tags", "Tags (comma separated)", ini["tags"]],
          ["extraxml", "Optional info in free XML format", ini["extra"]],
        ],
      })
    else
      result = DataKeeper.register_agent_in_branch(
        branch,
        agent,
        move: true,
        descr: params["descr"] || "",
        location: params["location"] || "",
        tags: params["tags"] || "",
        extra_xml: params["extraxml"] || ""
      )
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def unregister(conn, params) do
    if conn.method == "GET" do
      json(conn, %{
        "result" => true,
        "formMethod" => "post",
        "agentsList" => DataKeeper.get_agents() |> Enum.sort(),
      })
    else
      result = DataKeeper.unregister_agent(params["agent"] || "")
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def details_xml(conn, params) do
    agent = params["agent"] || ""
    if agent == "" do
      json(conn, %{
        "result" => true,
        "formMethod" => "get",
        "agentsList" => DataKeeper.get_agents() |> Enum.sort(),
      })
    else
      preret = DataKeeper.agent_details_xml(agent)
      if preret["result"] != true do
        conn |> put_status(status_for(preret)) |> json(preret)
      else
        conn
        |> put_resp_content_type("text/xml", "utf-8")
        |> send_resp(200, preret["details"])
      end
    end
  end

  def details_json(conn, params) do
    agent = params["agent"] || ""
    if agent == "" do
      json(conn, %{
        "result" => true,
        "formMethod" => "get",
        "agentsList" => DataKeeper.get_agents() |> Enum.sort(),
      })
    else
      result = DataKeeper.agent_details_json(agent)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  def list(conn, params) do
    branch_id = params["branch"] || ""
    if branch_id == "" do
      json(conn, %{
        "result" => true,
        "branchList" => ["*ALL*"] ++ DataKeeper.list_branches(),
        "cboxes" => [
          ["subsidinaries", "Including subsidinaries"],
          ["location", "With location branch"],
        ],
      })
    else
      with_subs = params["subsidinaries"] == "yes"
      with_loc = params["location"] == "yes"
      result = DataKeeper.list_agents(branch_id, with_subs, with_loc)
      conn |> put_status(status_for(result)) |> json(result)
    end
  end

  defp status_for(result), do: AacWeb.ResponseHelper.status_for(result)
end
