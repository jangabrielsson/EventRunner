local _=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  verbose=false,
  refreshStates=true,
  modPath = "TQAEmodules/",
  temp = "temp/",
--  startTime="12/24/2024-07:00", 
}

--%%name="TestSceneCron"
--%%scene=true
-- %%runAtStart=true
--%%noterminate=true

CONDITIONS = {
  conditions = { {
      isTrigger = true,
      operator = "match",
      property = "cron",
      type = "date",
      value = {"*","*","*","*","*","*"}
    }},
  operator = "any"
}


function ACTION()
  fibaro.debug(sceneId,"STARTED")
  fibaro.debug(sceneId,"Trigger",json.encode(sourceTrigger))
end