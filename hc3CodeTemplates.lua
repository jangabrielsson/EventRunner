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
end

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
  self:debug("onInit ",self.id)
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
end

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
  self:debug("onInit",self.id)
end
]]
}
return {version = version, templates = code}