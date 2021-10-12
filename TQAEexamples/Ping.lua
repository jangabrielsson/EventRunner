_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  modPath = "TQAEmodules/",
  temp = "temp/",
  startTime="12/24/2024-07:00",
}

--%%name="Ping"

hc3_emulator.installQA{id=88,file='TQAEexamples/Pong.lua'}
function QuickApp:pong(ret)
  self:debug("Pong")
  setTimeout(function() fibaro.call(ret,"ping",self.id) end, 2000)
end

function QuickApp:onInit()
  fibaro.call(88,"ping",self.id)
end