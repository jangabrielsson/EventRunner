--[[
%% properties
55 value
%% autostart
--]]
local function printf(...) fibaro:debug(string.format(...)) end

local s = fibaro:getSourceTrigger()
local a = fibaro:args()

printf("getSourceTrigger:%s",json.encode(s))
printf("getSourceTriggerType:%s",fibaro:getSourceTriggerType())
printf("args:%s",json.encode(a))
printf("countScenes:%s",fibaro:countScenes())
printf("__fibaroSceneId:%s",__fibaroSceneId)
printf("isSceneEnabled:%s",fibaro:isSceneEnabled(__fibaroSceneId))
printf("getSceneRunConfig:%s",fibaro:getSceneRunConfig(__fibaroSceneId))


