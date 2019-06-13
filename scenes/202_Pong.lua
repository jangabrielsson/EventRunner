--[[
--]]

if dofile and not _EMULATED then _EMBEDDED={name="Pomng",id=202} dofile("HC2.lua") end

local trigger = fibaro:getSourceTrigger()
  
if trigger.type=='other' then
  local message = fibaro:args()
  fibaro:debug("Got message: "..message[1])
  fibaro:startScene(201,{"Pong"})
end