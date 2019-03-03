--[[
--]]

local trigger = fibaro:getSourceTrigger()
  
if trigger.type=='other' then
  local message = fibaro:args()
  fibaro:debug("Got message: "..message[1])
  fibaro:startScene(201,{"Pong"})
end