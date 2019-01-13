--[[
-- SceneRunner. Event based scene emulator
-- Copyright 2019 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_GUI = true               -- Offline only, Open WX GUI for event triggers, Requires Lua 5.1 in ZBS
_SPEEDTIME = 24*36        -- Offline only, Speed through X hours, set to false will run in real-time
_EVENTSERVER=false        -- Starts port on 6872 listening for incoming events (Node-red, HC2 etc)
_REMOTE=false             -- Use Fibaro remote API
hc2_user = "xxx"          -- used for api.x/FibaroSceneAPI calls
hc2_pwd  = "xxx" 
hc2_ip   = "192.168.1.84" -- IP of HC2

----------- Set up scenes and commands/triggers --------
if nil then -- Example with scenes starting up eachother
scenes = {
   {name="Ping",id=11,file="scenes/Ping.lua"},
   {name="Pong",id=22,file="scenes/Pong.lua"},
}
end

if nil then -- Example with scenes reacting on sensor turning on/off light
scenes = {
   {name="Test2",id=11,file="scenes/Test2.lua"},
}
commands = {"wait(00:10);55:on;wait(00:00:40);55:off"}
end

if true then -- Example with scenes reacting on sensor turning on/off light
scenes = {
   {name="GEA",id=42,file="GEA 6.11.lua"},
}
--commands = {"wait(00:10);55:on;wait(00:00:40);55:off"}
end

--[[
function _SETUP()
	-- other setup needed, ex. _System.copyGlobalsFromHC2()
end
--]]

-- debug flags for various subsystems...
_debugFlags = { 
  post=true,invoke=false,eventserver=true,triggers=false,dailys=false,timers=false,rule=false,
  ruleTrue=false,fibaro=true,fibaroGet=false,fibaroSet=false,sysTimers=false, scene=true 
}

------------- Don't touch -------------------------------
function _ALTERNATIVEMAIN()
  if _SETUP then _SETUP() end 
  local choices={}
  for _,scene in ipairs(scenes or {}) do
    local s = _System.loadScene(scene.name,scene.id,scene.file)
    local hs=_System.headers2Events(s.headers,true)
    for _,h in ipairs(hs) do choices[h]=true end
  end
  local choices2 = {}
  for k,v in pairs(choices) do choices2[#choices2+1]=k end
  _setUIEventItems(choices2)
  for _,cmd in ipairs(commands or {}) do
    Rule.eval(cmd)
  end
end
_SCENERUNNER = true
_sceneName   = "SceneRunner"
dofile("EventRunner.lua")
