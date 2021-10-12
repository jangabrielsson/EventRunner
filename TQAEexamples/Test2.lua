_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  modPath = "TQAEmodules/",
  temp = "temp/",
  --startTime="12/24/2024-07:00",
  ---speed=true
}

--%%name="Test"

function QuickApp:onInit()
  setInterval(function()
      self:debug("PING")
    end,1000*60*60)
end
