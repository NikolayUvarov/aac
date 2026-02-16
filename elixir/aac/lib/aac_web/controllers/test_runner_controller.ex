defmodule AacWeb.TestRunnerController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  def states(conn, params) do
    task_id = params["poll"] || ""

    if task_id != "" do
      result = Aac.TestRunner.check_task(task_id)
      json(conn, result)
    else
      dur_each_raw = params["durationEach"] || ""
      states_str = params["states"] || ""
      fin_msg = params["final"] || ""
      agent = params["agent"] || ""

      states_list = String.split(states_str, ",", trim: false)
      duration_each = String.to_integer(dur_each_raw)

      task_id = Aac.TestRunner.run_test_generic(
        states_list,
        List.duplicate(duration_each, length(states_list)),
        %{"final_message" => fin_msg, "agent_id" => agent}
      )

      Process.sleep(1000)
      result = Aac.TestRunner.check_task(task_id)
      json(conn, result)
    end
  end
end
