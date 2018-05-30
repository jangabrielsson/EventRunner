--[[
%% properties
313 value
336 value
327 value
%% events
%% globals
--]]

local lightID = 129
local sleepTime = 3*60 -- seconds

if 
fibaro:getValue(313,'value') == '1' or
fibaro:getValue(336,'value') == '1' or
fibaro:getValue(327,'value') == '1'  then
  fibaro:debug("Someone moved, abort")
  fibaro:killScenes(__fibaroSceneId)
end

fibaro:debug("No one moving...")
fibaro:sleep(1000*sleepTime)
fibaro:debug(string.format("No one moved moved for %ss, turn off light %s",sleepTime,lightID))
fibaro:call(lightID,'turnOff')

