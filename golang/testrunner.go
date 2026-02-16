package main

import (
	"sync"
	"sync/atomic"
	"strconv"
	"time"
)

type testTaskState struct {
	state         string
	taskStartedAt int64
	stateStarted  int64
	finalDict     map[string]interface{}
}

var (
	runningTestTasks = map[string]*testTaskState{}
	finishedTasks   = map[string]*testTaskState{}
	tasksMu        sync.Mutex
	taskSequence   int64
)

func cloneStringMap(in map[string]interface{}) map[string]interface{} {
	out := make(map[string]interface{}, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}

func runTestGeneric(states []string, durations []int, finalDict map[string]interface{}) string {
	taskId := stringsFromInt(atomic.AddInt64(&taskSequence, 1))

	task := &testTaskState{
		state:         "",
		taskStartedAt: time.Now().UnixNano(),
		stateStarted:  time.Now().UnixNano(),
		finalDict:     cloneStringMap(finalDict),
	}
	task.finalDict["task_id"] = taskId

	tasksMu.Lock()
	runningTestTasks[taskId] = task
	tasksMu.Unlock()

	go func() {
		for i, state := range states {
			dur := 0
			if len(durations) > i {
				dur = durations[i]
			}

			tasksMu.Lock()
			task.state = state
			task.stateStarted = time.Now().UnixNano()
			tasksMu.Unlock()

			if dur > 0 {
				time.Sleep(time.Duration(dur) * time.Second)
			}
		}

		tasksMu.Lock()
		task.finalDict["total_exec_time"] = (time.Now().UnixNano() - task.taskStartedAt) / 1000
		task.finalDict["state"] = "done"
		delete(runningTestTasks, taskId)
		finishedTasks[taskId] = task
		tasksMu.Unlock()
	}()

	return taskId
}

func runTestSteadyStepsWithFinMsg(states []string, dur4each int, finMsg, agentId string) string {
	finalDict := map[string]interface{}{
		"final_message": finMsg,
		"agent_id":      agentId,
	}

	durations := make([]int, len(states))
	for i := range durations {
		durations[i] = dur4each
	}

	return runTestGeneric(states, durations, finalDict)
}

func checkTask(taskID string) map[string]interface{} {
	if taskID == "" {
		return map[string]interface{}{"result": false, "reason": "UNKNOWN_TASK_ID"}
	}

	now := time.Now().UnixNano()

	tasksMu.Lock()
	if task, ok := runningTestTasks[taskID]; ok {
		ret := map[string]interface{}{
			"task_id":       taskID,
			"state":         task.state,
			"total_exec_time": (now-task.taskStartedAt)/1000,
			"state_exec_time": (now-task.stateStarted)/1000,
		}
		tasksMu.Unlock()
		return ret
	}

	if task, ok := finishedTasks[taskID]; ok {
		delete(finishedTasks, taskID)
		ret := cloneStringMap(task.finalDict)
		tasksMu.Unlock()
		return ret
	}

	tasksMu.Unlock()
	return map[string]interface{}{"result": false, "reason": "UNKNOWN_TASK_ID"}
}

func stringsFromInt(v int64) string {
	return strconv.FormatInt(v, 10)
}
