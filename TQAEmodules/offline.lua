--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Support for local shadowing global variables - and other resources
ToDo, should generate events...

--]]
local EM,FB = ...

local json = FB.json
local HC3Request,LOG,Devices = EM.HC3Request,EM.LOG,EM.Devices
local __fibaro_get_devices,__fibaro_get_device,__fibaro_get_device_property,__fibaro_call,__assert_type=
FB.__fibaro_get_devices,FB.__fibaro_get_device,FB.__fibaro_get_device_property,FB.__fibaro_call,FB.__assert_type
local copy = EM.utilities.copy

EM.rsrc = { 
  rooms = {}, 
  sections={}, 
  globalVariables={},
  customEvents={},
}

local function setup()
end

local roomID = 1001
local sectionID = 1001

EM.creat = EM.create or {}
function EM.create.globalVariable(args)
  local v = {
    name=args.name,
    value=args.value,
    modified=EM.osTime(),
  }
  EM.rsrc.globalVariables[args.name]=v
  return v
end

function EM.create.room(args)
  local v = {
    id = roomID,
    name=args.name,
    modified=EM.osTime(),
  }
  roomID=roomID+1
  EM.rsrc.rooms[v.id]=v
  return v
end

function EM.create.section(args)
  local v = {
    id = sectionID,
    name=args.name,
    modified=EM.osTime(),
  }
  sectionID=sectionID+1
  EM.rsrc.sections[v.id]=v
  return v
end

function EM.create.customEvent(args)
  local v = {
    name=args.name,
    userDescription=args.userDescription or "",
  }
  EM.rsrc.customEvents[v.id]=v
  return v
end

EM.EMEvents('start',function(ev)
    if EM.cfg.offline then setup() end 
  end)


