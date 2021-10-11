_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  logLevel=1,
  refreshStates=true,
  modPath = "TQAEmodules/",
  temp = "temp/",
--  copas=true,
  --startTime="12/24/2024-07:00",
  ---speed=true
}

--%%name="Test"
--%%quickVars={x="a b c d e f g"}

x = {
  a = { 7, 8 ,9 },
  b = { h = 9 },
  c = 9,
  d = "foo"
}

print(hc3_emulator.EM.utilities.luaFormated(x))

local baseURL = "http://192.168.1.134:8000/"   
local interval = 1 -- Poll every second

local function getValue()
  quickApp:trace("OK")
  setTimeout(getValue,1000*interval)
end

function QuickApp:onInit()
  self:debug(self.name,self.id)
  setTimeout(getValue,1000*interval)
end 
