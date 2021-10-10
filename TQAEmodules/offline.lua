--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Support for local shadowing global variables, rooms, sections, customEvents - and other resources

--]]
local EM,_ = ...

--local json,LOG,DEBUG = FB.json,EM.LOG,EM.DEBUG

EM.rsrc = { 
  rooms = {}, 
  sections={}, 
  globalVariables={},
  customEvents={},
}

local function setup()
  EM.create.room{id=219,name="Default Room"}
  EM.createSection{id=219,name="Default Section"}
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
    name = "Room",
    sectionID = EM.cfg.defaultSection or 219,
    isDefault = true,
    visible = true,
    icon = "",
    defaultSensors = { temperature = 0, humidity = 0, light = 0 },
    meters = { energy = 0 },
    defaultThermostat = 0,
    sortOrder = 1,
    category = "other"
  }
  for _,k in (
    {"id","name","sectionID","isDefault","visible","icon","defaultSensors","meters","defaultThermostat","sortOrder","category"}
    ) do v[k] = args[k] or v[k] 
  end
  if not v.id then v.id = roomID roomID=roomID+1 end
  EM.rsrc.rooms[v.id]=v
  return v
end

function EM.create.section(args)
  local v = {
    name = "Section" ,
    sortOrder = 1
  }
  for _,k in ({"id","name","sortOrder"}) do v[k] = args[k] or v[k]  end
  if not v.id then v.id = sectionID sectionID=sectionID+1 end
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

EM.EMEvents('start',function(_)
    if EM.cfg.offline then setup() end 
  end)


