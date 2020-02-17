--[[
%%LibScene
properties: {
"name": "Test scene"
}
conditions: {
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

fibaro.debug("","Hello planet")
