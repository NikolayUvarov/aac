defmodule Aac.TestRunner do
  @moduledoc """
  Execute long-running async test tasks with state tracking.
  Port of Python's testRunner.testTask class.

  Uses a GenServer to manage running and completed tasks.
  """
  use GenServer
  require Logger

  # ── Client API ──

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Run a test with given states, durations, and final dict"
  def run_test_generic(states, durations, final_dict) do
    GenServer.call(__MODULE__, {:run, states, durations, final_dict})
  end

  @doc "Run a test with steady step durations and a final message"
  def run_test_steady(states, dur_each, fin_msg, agent_id) do
    durations = List.duplicate(dur_each, length(states))
    run_test_generic(states, durations, %{"final_message" => fin_msg, "agent_id" => agent_id})
  end

  @doc "Check task status by ID"
  def check_task(task_id) do
    GenServer.call(__MODULE__, {:check, task_id})
  end

  # ── Server callbacks ──

  @impl true
  def init(_) do
    {:ok, %{running: %{}, done: %{}}}
  end

  @impl true
  def handle_call({:run, states, durations, final_dict}, _from, state) do
    task_id = generate_task_id()
    steps = Enum.zip(states, durations)
    now = System.monotonic_time(:microsecond)

    task_state = %{
      steps: steps,
      final_dict: Map.put(final_dict, "task_id", task_id),
      started_at: now,
      state_started_at: now,
      current_state: nil
    }

    new_running = Map.put(state.running, task_id, task_state)
    send(self(), {:execute_step, task_id})

    Logger.info("Task #{task_id} created with steps #{inspect(states)}")
    {:reply, task_id, %{state | running: new_running}}
  end

  @impl true
  def handle_call({:check, task_id}, _from, state) do
    cond do
      Map.has_key?(state.running, task_id) ->
        task = state.running[task_id]
        now = System.monotonic_time(:microsecond)
        reply = %{
          "task_id" => task_id,
          "state" => task.current_state,
          "total_exec_time" => now - task.started_at,
          "state_exec_time" => now - task.state_started_at
        }
        {:reply, reply, state}

      Map.has_key?(state.done, task_id) ->
        {result, new_done} = Map.pop(state.done, task_id)
        Logger.info("Task #{task_id} result requested and removed from finished storage")
        {:reply, result, %{state | done: new_done}}

      true ->
        {:reply, %{"result" => false, "reason" => "UNKNOWN_TASK_ID"}, state}
    end
  end

  @impl true
  def handle_info({:execute_step, task_id}, state) do
    case Map.get(state.running, task_id) do
      nil ->
        {:noreply, state}

      %{steps: []} = task ->
        # All steps done
        now = System.monotonic_time(:microsecond)
        final = task.final_dict
          |> Map.put("total_exec_time", now - task.started_at)
          |> Map.put("state", "done")

        new_running = Map.delete(state.running, task_id)
        new_done = Map.put(state.done, task_id, final)
        Logger.info("Task #{task_id} done")
        {:noreply, %{state | running: new_running, done: new_done}}

      %{steps: [{step_state, duration} | rest]} = task ->
        now = System.monotonic_time(:microsecond)
        updated_task = %{task | steps: rest, current_state: step_state, state_started_at: now}
        new_running = Map.put(state.running, task_id, updated_task)

        Logger.info("Task #{task_id} switched to state #{step_state}")
        Process.send_after(self(), {:execute_step, task_id}, duration * 1000)
        {:noreply, %{state | running: new_running}}
    end
  end

  defp generate_task_id do
    :crypto.strong_rand_bytes(8) |> Base.hex_encode32(case: :lower, padding: false)
  end
end
