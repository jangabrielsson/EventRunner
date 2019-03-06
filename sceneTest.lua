--[[
%% properties
66 value
--]]

local motion = 66
local lamp = 77

local t = fibaro:getSourceTrigger()

if t.type=='property' and t.deviceID==66 then

  local val = fibaro:getValue(66,"value")
  if val > "0" then
    fibaro:debug("Sensor 66 breached")
  else
    fibaro:debug("Sensor 66 breached")
  end
end