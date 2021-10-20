_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  modPath = "TQAEmodules/",
  refreshStates = true,
  debug = { refreshStates=true },
  temp = "temp/",
  startTime="12/24/2024-07:00",
}

--%%name="MyQuickApp"
--%%type="com.fibaro.binarySwitch"
--%%quickVars = {['x'] = 17, ['y'] = 42 }
--%%noterminate = true
--%%u1={button='b1', text='B1', onReleased='turnOn'}
--%%u2={{button='b2', text='B2', onReleased='turnOff'},{button='b3', text='B3', onReleased='turnOff'}}
--%%u2={{button='b4', text='B4', onReleased='turnOff'},{button='b5', text='B5', onReleased='turnOff'},{button='b6', text='B6', onReleased='turnOff'},{button='b7', text='B7', onReleased='turnOff'},{button='b8', text='B8', onReleased='turnOff'}}
--%%u3={label='l1', text='ABCDEFG'}
--%%u4={slider='s1', onChanged='slider'}
-- %%proxy=true

function QuickApp:turnOn()
  if self.properties.value == false then self:debug("Turn On") end
  self:updateProperty("value",true)
end

function QuickApp:turnOff()
  if self.properties.value == true then self:debug("Turn Off") end
  self:updateProperty("value",false)
end

function QuickApp:slider(ev)
  self:debug("Slider ",ev.values[1])
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