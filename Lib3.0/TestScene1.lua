--[[
%%LibScene
{
  "id": 26,
  "name": "ttt",
  "type": "lua",
  "mode": "manual",
  "maxRunningInstances": 2,
  "icon": "scene_block",
  "hidden": false,
  "protectedByPin": false,
  "stopOnAlarm": false,
  "restart": true,
  "enabled": true,
  "conditions "{
    conditions = { 
      { id = 41,
        isTrigger = true,
        operator = "==",
        property = "value",
        type = "device",
        value = false
      }, 
      { isTrigger = true,
        operator = "matchInterval",
        property = "cron",
        type = "date",
        value = {
          date = { "00", "10", "4", "2", "*", "2020" },
          interval =  1200
        }
      } 
    },
    operator = "all"
  }
}
--]]

fibaro.debug("","Hello world")