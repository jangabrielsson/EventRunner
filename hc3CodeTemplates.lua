local version = "1.0"
local code = {
  ['Scene template'] =
[[if dofile and not hc3_emulator then
  hc3_emulator = {
    name = "My Scene",       -- Name of Scene
    poll = 2000,             -- Poll HC3 for triggers every 2000ms
    traceFibaro=true,        -- Log fibaro.call and fibaro.get
    --offline = true,
  }
  dofile("fibaroapiHC3.lua")
end--hc3

hc3_emulator.conditions = {  -- example condition triggering on device 37 becoming 'true'
  conditions = { {
      id = 37,
      isTrigger = true,
      operator = "==",
      property = "value",
      type = "device",
      value = true
      } },
  operator = "all"
}

function hc3_emulator.actions()
  local hc = fibaro
  jT = json.decode(hc.getGlobalVariable("HomeTable")) 
  -- Your code
end

]],
  ['QA template'] = 
[[if dofile and not hc3_emulator then
  hc3_emulator = {
    name = "My QA",    -- Name of QA
    poll = 2000,       -- Poll HC3 for triggers every 2000ms
    --offline = true,
  }
  dofile("fibaroapiHC3.lua")
end--hc3

function QuickApp:onInit()
  self:debug(self.name, self.id)
end

]],
  ['QA template with toolbox'] = 
[[if dofile and not hc3_emulator then
  hc3_emulator = {
    name="My QA",
    --proxy=true,
    --deploy=true,
    type="com.fibaro.deviceController",
    poll=1000,
    UI = {}
  }
  dofile("fibaroapiHC3.lua")
end--hc3

--FILE:Toolbox/Toolbox_basic.lua,Toolbox;
-- FILE("Toolbox/Toolbox_child.lua,Toolbox_child;
-- FILE("Toolbox/Toolbox_events.lua,Toolbox_events;
-- FILE("Toolbox/Toolbox_triggers.lua,Toolbox_triggers;
-- FILE("Toolbox/Toolbox_files.lua,Toolbox_files;
-- FILE("Toolbox/Toolbox_rpc.lua,Toolbox_rpc;
-- FILE("Toolbox/Toolbox_pubsub.lua,Toolbox_pubsub;
-- FILE("Toolbox/Toolbox_ui.lua,Toolbox_ui;
----------- Code -----------------------------------------------------------
_version = "0.1"
modules = {
--  "childs",
--  "events",
--  "triggers",
--  "files",
--  "rpc",
--  "pubsub",
--  "ui"
}

function QuickApp:onInit()
  self:debug(self.name ,self.id)
end
]],
  ['Simple backup'] =
[[if dofile and not hc3_emulator then
  dofile("fibaroapiHC3.lua")
end--hc3

local fs = "/"
local today    = os.date("%x"):gsub("/","")
local qaDir    = "QAbackup"..fs..today..fs             -- Directory will be created if it doesn't exist.
local sceneDir = "Scenebackup"..fs..today..fs          -- Directory will be created if it doesn't exist.

local function printf(...) print(string.format(...)) end

-- This is a script that backs up your QAs and Scenes from the HC3 and store them in a directory

local QAs = api.get("/devices?interface=quickApp")
for _,q in ipairs(QAs) do
  printf("Backing up %s",q.name)
  hc3_emulator.loadQA(q.id):save("fqa",qaDir)
end

local scenes = api.get("/scenes")
for _,s in ipairs(scenes) do
  printf("Backing up %s",s.name)
  hc3_emulator.loadScene(s.id):save("fsc",sceneDir)
end
]],
  ['MultilevelSwitch'] =
[[if dofile and not hc3_emulator then
  hc3_emulator = {
    name = "MyMultilevelSwitch",    -- Name of QA
    type = "com.fibaro.multilevelSwitch",
    poll = 1000,                    -- Poll HC3 for triggers every 1000ms
    offline = true,
    UI = {
      {label='info', text=''},
      {
        {button='turnOn', text='Turn On',  onReleased='turnOn'},
        {button='turnOff', text='Turn Off',  onReleased='turnOff'}
      },
      {slider='val', min=0, max=99, onChanged='slider'}
    }
  }
  dofile("fibaroapiHC3C.lua")
end--hc3

function QuickApp:turnOn()
  self:updateProperty("value",99)
  self:info()
end

function QuickApp:turnOff()
  self:updateProperty("value",0)
  self:info()
end

function QuickApp:slider(ev) self:setValue(ev.values[1]) end

function QuickApp:setValue(value)
  self:updateProperty("value",value)
  self:info()
end

function QuickApp:info()
  local val = fibaro.getValue(self.id,"value")
  self:updateView("info","text","Value is "..val)
  self:updateView("val","value",tostring(val))
end

function QuickApp:onInit()
  self:debug(self.name, self.id)
  self:info()
end]]
}
return {version = version, templates = code}