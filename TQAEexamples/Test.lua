_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  logLevel=1,
  refreshStates=true,
  modPath = "TQAEmodules/",
  temp = "temp/",
  --startTime="12/24/2024-07:00",
  ---speed=true
}

--%%name="Test"
--%%quickVars={x="a b c d e f g"}

function QuickApp:onInit()
  setInterval(function()
      self:debug("PING")
    end,1000*60*60)
end
