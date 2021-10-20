--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Module Settings

--]]
local EM,FB = ...

local json = FB.json
local LOG,DEBUG = EM.LOG,EM.DEBUG

local function setup()
  cfg = EM.cfg
  debugFlags = EM.debugFlags
end

EM.EMEvents('start',setup)