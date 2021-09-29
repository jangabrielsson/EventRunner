--%%name="API1"

function QuickApp:test2()
  setTimeout(function() self:debug("Async2") os.exit() end,0)  
  self:debug("C")
  fibaro.getValue(3,"value")
  self:debug("D")
end

function QuickApp:onInit()
  setTimeout(function() self:debug("Async1") self:test2() end,0)
  self:debug("A")
  api.get("/devices/3")
  self:debug("B")
end
