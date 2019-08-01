--[[
%% properties
66 value
--]]

if dofile and not _EMULATED then _EMULATED={name="sceneTest",id=42} dofile("HC2.lua") end

local motion = 66
local lamp = 77
if fibaro:countScenes() > 1 then fibaro:abort() end

local t = fibaro:getSourceTrigger()

if t.type=='property' and t.deviceID==motion and fibaro:getValue(motion,"value") > "0" then
  -- breached
  fibaro:call(lamp,"turnOn")
  local sec = 60*4 -- 4 min
  repeat
    fibaro:sleep(1000*1) -- sleep 1 sec
    if fibaro:getValue(motion,"value") > "0" then 
      sec =  60*4 -- if breached, reset counter
    else
      sec = sec-1 -- otherwise count down
    end
  until sec <= 0

  fibaro:call(lamp,"turnOff")
end