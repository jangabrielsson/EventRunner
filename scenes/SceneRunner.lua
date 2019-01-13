--[[
-- SceneRunner. Event based scene emulator
-- Copyright 2019 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

----------- Set up scenes and commands/triggers --------
scenes = {
   {name="Ping",id=11,file="scenes/Ping.lua"},
   {name="Pong",id=22,file="scenes/Pong.lua"},
}

commands = {"55:on"}

------------- Don't touch -------------------------------
function _ALTERNATIVEMAIN()
  for _,scene in ipairs(scenes) do
    _System.loadScene(scene.name,scene.id,scene.file)
  end
  for _,cmd in ipairs(commands) do
    Rule.eval(cmd)
  end
end

dofile("EventRunner.lua")
