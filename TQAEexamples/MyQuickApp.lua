_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  verbose=false,
  modPath = "TQAEmodules/",
  temp = "temp/",
  startTime="12/24/2024-07:00",
}

--%%name="MyQuickApp"
--%%type="com.fibaro.binarySwitch"
--%%quickVars = {['x'] = 17, ['y'] = 42 }
--%%noterminate = true

function QuickApp:turnOn()
  if self.properties.value == false then self:debug("Turn On") end
  self:updateProperty("value",true)
end

function QuickApp:turnOff()
  if self.properties.value == true then self:debug("Turn Off") end
  self:updateProperty("value",false)
end

function QuickApp:toggle()
  if self.properties.value == false then self:turnOn() else self:turnOff() end
end

function QuickApp:onInit()
  local x = self:getVariable('x')         
  local y = self:getVariable('y')          

  self:debug("Sum",x,y,"=",x+y)
  
  setTimeout(function() self:toggle() end,3000)
end