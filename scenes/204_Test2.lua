--[[
%% properties
55 value
--]]

sensor = 55
light = 66  

if fibaro:countScenes() > 1 then
  fibaro:debug("Already started, exit")
  fibaro:abort()
end

local trigger = fibaro:getSourceTrigger()

if trigger.type=='property' and trigger.deviceID==55 and
fibaro:getValue(55,"value") > "0" then
  fibaro:call(66,"turnOn")
  local time = 60
  repeat
    fibaro:sleep(10*1000)
    if fibaro:getValue(55,"value") > "0" then time = 60 else time=time-10 end
  until time <= 0
  fibaro:call(66,"turnOff")
end
