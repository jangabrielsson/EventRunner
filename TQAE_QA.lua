_=loadfile and loadfile("TQAE.lua"){
--  user="admin", 
--  pwd="admin", 
--  host="192.168.1.57",
  modPath = "TQAEmodules/",
}

--%%name="Test QA"

function QuickApp:onInit()
  self:debug(self.name,self.id)
  self:debug([[This is a simple QA that does nothing besides logging "PING"]])
  setInterval(function() self:debug("PING") end,1000)
end 
