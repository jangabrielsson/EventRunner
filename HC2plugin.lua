local ideh2 = ID("HC2.helpHC2")
local idehe = ID("HC2.helpER")
local idem = ID("HC2.emu")
local idet = ID("HC2.templ")

--https = require ("ssl.https")
--ltn12 = require("ltn12")
--local s33 = require("socket")
--local h33 = require("socket.http")

local urlEmu = "http://127.0.0.1:6872/emu/main"
local urlHC2Help = "https://forum.fibaro.com/topic/42835-hc2-scene-emulator/"
local urlERHelp = "https://forum.fibaro.com/topic/31180-tutorial-single-scene-instance-event-model/"
local urlEventRunner = "https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/EventRunner.lua"

local function launchERHelp()
  wx.wxLaunchDefaultBrowser(urlERHelp, 0)
end

local function launchHC2Help()
  wx.wxLaunchDefaultBrowser(urlHC2Help, 0)
end

local function launchEmulator()
  wx.wxLaunchDefaultBrowser(urlEmu, 0)
end

local SCENE_TEMP = 
[[--[[
%% properties
66 value
%% globals
%% events
%% autostart
--]].."]]"..[[

if dofile and not _EMULATED then _EMBEDDED=true dofile("HC2.lua") end

local trigger = fibaro:getSourceTrigger()

if trigger.type == 'property' then
  if fibaro:getValue(66,"value") > "0" then
    fibaro:call(77,"turnOn")
  else
    fibaro:call(77,"turnOff")
  end
else 
  fibaro:debug("Autostarted")
end
]]

local function addTemplates(t)
  if t=="SCENE" then
    ide:GetEditor():InsertText(-1, SCENE_TEMP)
  elseif t=="ER" then
    local tip = GetTipInfo(ide:GetEditor(), urlEventRunner)
    ide:GetEditor():InsertText(-1, tip)
  end
end

return {
  name = "HC2 Scene support",
  description = "Support for HC2 emulator and templates.",
  author = "Jan Gabrielsson",
  version = 0.1,
  dependencies = "1.0",

  onRegister = function()
    local menu = ide:FindTopMenu("&View")
    menu:Append(idem, "HC2 Emulator\tCtrl-Alt-E"..KSC(idem))
    ide:GetMainFrame():Connect(idem, wx.wxEVT_COMMAND_MENU_SELECTED, launchEmulator)

    menu = ide:FindTopMenu("&Help")
    menu:Append(ideh2, "HC2 Emulator help"..KSC(ideh2))
    ide:GetMainFrame():Connect(ideh2, wx.wxEVT_COMMAND_MENU_SELECTED, launchHC2Help)

    menu = ide:FindTopMenu("&Help")
    menu:Append(idehe, "EventRunner help"..KSC(idehe))
    ide:GetMainFrame():Connect(idehe, wx.wxEVT_COMMAND_MENU_SELECTED, launchERHelp)

    menu = ide:FindTopMenu("&Edit")
    local templSubMenu = ide:MakeMenu()
    local templ = menu:AppendSubMenu(templSubMenu, TR("HC2 Scene templates..."))

    local idTSC = ID("HC2.temp_SC")
    local idTER = ID("HC2.temp_ER")
    templSubMenu:Append(idTSC, "HC2 scene"..KSC(idTSC))
    ide:GetMainFrame():Connect(idTSC, wx.wxEVT_COMMAND_MENU_SELECTED, function() addTemplates("SCENE") end)
--    templSubMenu:Append(idTER, "EventRunner scene"..KSC(idTER))
--    ide:GetMainFrame():Connect(idTER, wx.wxEVT_COMMAND_MENU_SELECTED, function() addTemplates("ER") end)


  end,
  onUnRegister = function()
    ide:RemoveMenuItem(idem)
    ide:RemoveMenuItem(ideh)
    ide:RemoveMenuItem(idet)
  end,

--  onMenuEditor = function(self, menu, editor, event)
--    menu:AppendSeparator()
--    menu:Append(id, "..."..KSC(id))
--  end

}