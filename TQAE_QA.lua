_=loadfile and loadfile("TQAE.lua"){
--  modPath = "TQAEmodules/",
}

--%%name="Test QA"

function QuickApp:turnOn()
  self:updateProperty("value",true)
end

function QuickApp:onInit()
  self:debug(self.name,self.id)
  self:debug([[This is a simple QA that does nothing besides logging "PING"]])
  setInterval(function() self:debug("PING") end,1000)
end 
