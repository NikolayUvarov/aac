import asyncio
import time
import json

#--------------------------------------------------------------------------------------------------------------
_logName = "testRunner"
import logging
logger = logging.getLogger(_logName)
#--------------------------------------------------------------------------------------------------------------

class testTask:

    #-----------

    def __init__(self, states, durations, finalDict):
        logger.info(f"Constructing object for task with steps {states} lasting {durations} and final dict object {finalDict}")
        self._todo = zip(states,durations)
        self._final_dict = finalDict
        self._final_dict['task_id'] = self.taskId()
        self.state = None
        logger.info(f"Task {self.taskId()} just created")


    def taskId(self):
        return str(id(self))

    #-----------
    
    __running_tasks = {} # tasks being executed
    __done_tasks = {} # tasks done but not reported

    #-----------

    @classmethod
    async def runTestGeneric(cls,states,durations,finDict):
        taskObj = cls( states, durations, finDict )
        taskObj.__executingTask = asyncio.create_task(taskObj.__self_updater())
        return taskObj.taskId()

    @classmethod
    async def runTestSteadyStepsWithFinMsg(cls,states,dur4each, finMsg, agentId):
        return await cls.runTestGeneric( states, [dur4each]*len(states), {'final_message':finMsg, 'agent_id':agentId} )

    #-----------

    async def __self_updater(self):
        tId = self.taskId()
        self._task_started_at = time.monotonic_ns()
        type(self).__running_tasks[tId] = self
        logger.info(f"Tasks being executed now are: {type(self).__running_tasks.keys()}")

        for s in self._todo:
            self.state = s[0]
            self._state_started_at = time.monotonic_ns()
            logger.info(f"Task {tId} switched to to state {self.state}")
            await asyncio.sleep(s[1])

        self._final_dict['total_exec_time'] = (time.monotonic_ns() - self._task_started_at) // 1000
        self._final_dict['state'] = "done"
        type(self).__done_tasks[tId] = type(self).__running_tasks.pop(tId)
        logger.info(f"Task {tId} done, finished tasks storage is: {type(self).__done_tasks.keys()}")

    #-----------

    @classmethod
    async def checkTask(cls,taskid):
        if taskid in cls.__running_tasks:
            taskObj = cls.__running_tasks[taskid]
            return { 'task_id': taskid,
                     'state': taskObj.state,
                     'total_exec_time': (time.monotonic_ns() - taskObj._task_started_at) // 1000,
                     'state_exec_time': (time.monotonic_ns() - taskObj._state_started_at) // 1000,
                   }
        elif taskid in cls.__done_tasks:
            taskObj = cls.__done_tasks.pop(taskid)
            logger.info(f"Task {taskid} result requested and removed from a finished tasks storage that is now: {cls.__done_tasks.keys()}")
            return taskObj._final_dict
        else:
            return { 'result': False,
                     'reason': "UNKNOWN_TASK_ID",
                   }


#--------------------------------------------------------------------------------------------------------------
# Some self-test functionality

if __name__ == '__main__':

    #~~~~~~~~~~~~~~~~~~~~~~~

    import configTestLogging
    configTestLogging.config(_logName)

    #~~~~~~~~~~~~~~~~~~~~~~~
    async def main():

        task1id = await testTask.runTestSteadyStepsWithFinMsg(["STATE3","STATE1","STATE2","STATE3"],5,"Task 1 done!!!","SUPERAGENT")
        task2id = await testTask.runTestSteadyStepsWithFinMsg(["STATE1","STATE2"],7,"Task 2 done!!!","James Bond")
    
        for i in range(30):
            await asyncio.sleep(1)
            logger.info(f"{i+1} sec:")
            logger.info(f" task 1: {await testTask.checkTask(task1id)}")
            logger.info(f" task 2: {await testTask.checkTask(task2id)}")

    #~~~~~~~~~~~~~~~~~~~~~~~

    asyncio.run(main())

#--------------------------------------------------------------------------------------------------------------
