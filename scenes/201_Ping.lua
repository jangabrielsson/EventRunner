--[[
%% autostart
--]]

if dofile and not _EMULATED then _EMBEDDED={name="Ping",id=201} dofile("HC2.lua") end

local trigger = fibaro:getSourceTrigger() 
  
if trigger.type=='autostart' then
  fibaro:startScene(202,{"Ping - 4"})
  fibaro:setGlobal("counter","4")
elseif trigger.type=='other' then
  local counter = tonumber(fibaro:getGlobalValue("counter"))
  if counter <= 0 then fibaro:abort() end
  counter=counter-1
  fibaro:setGlobal("counter",counter)
  fibaro:startScene(202,{"Ping - "..counter})
end