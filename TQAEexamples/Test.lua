_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  refreshStates=true,
  modPath = "TQAEmodules/",
  temp = "temp/",
  debug = { traceFibaro = true },
--  copas=true,
  --startTime="12/24/2024-07:00",
  ---speed=true
}

--%%name="Test"
--%%quickVars={x="a b c d e f g"}

local interval = 1 -- Poll every second

local function getValue()
  quickApp:trace("OK")
  fibaro.getValue(3,"Temperature")
  setTimeout(getValue,1000*interval)
end

function QuickApp:onInit()
  self:debug(self.name,self.id)
  setTimeout(getValue,1000*interval)
end 
