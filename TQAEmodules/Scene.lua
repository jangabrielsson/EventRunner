local EM,FB,ARGS=...

local LOG,json = EM.LOG,FB.json
local fmt = string.format

local Scenes = {}

--[[
{
  conditions = { {
      id = 2066,
      isTrigger = true,
      operator = "==",
      property = "centralSceneEvent",
      type = "device",
      value = {
        keyAttribute = "Pressed",
        keyId = 1
      }
    }, {
      conditions = { {
          isTrigger = false,
          operator = "match",
          property = "cron",
          type = "date",
          value = { "*", "*", "*", "*", "1,3,5", "*" }
        }, {
          isTrigger = true,
          operator = "match",
          property = "cron",
          type = "date",
          value = { "00", "06", "*", "*", "*", "*" }
        } },
      operator = "all"
    } },
  operator = "any"
}

{
  conditions = { {
      id = 32,
      isTrigger = true,
      operator = "==",
      property = "value",
      type = "device",
      value = true
    } },
  operator = "all"
}
--]]

local operators = {
  any = function(trigger,ts,cs) for _,c in ipairs(cs) do if c(trigger,ts) then return true end end end,
  all = function(trigger,ts,cs) for _,c in ipairs(cs) do if not c(trigger,ts) then return false end end return true end,
}

local toppers = {
  ["=="] = function(a,b) return tostring(a)==tostring(b) end,  -- are the values the same
  ["!="] = function(a,b) return tostring(a)~=tostring(b) end,  -- are the texts different
  ["anyValue"] = function(a,b) return true               end,  -- match any value
  [">"] = function(a,b) return tostring(a)>tostring(b)   end,  -- is the current value greater than the one in the condition
  [">="] = function(a,b) return tostring(a)>=tostring(b) end,  -- is the current value greater than or equal to the one in the condition
  ["<"] = function(a,b) return tostring(a)<tostring(b)   end,  -- is the current value lesser than the one in the condition
  ["<="] = function(a,b) return tostring(a)<=tostring(b) end,  -- is the current value lesser than or equal to the one in the condition
}

local types = {}
function types.device(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    local val = 
    trigger.id==c.id and
    trigger.property == c.property and
    toppers[c.operator](trigger.value,c.value)
    if val and isTrigger then ts[1]=true end
    return val
  end
end
function types.date(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    val = true
    if isTrigger and val then ts[1]=true end
    return val
  end
end
function types.weather(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    val = true
    if isTrigger and val then ts[1]=true end
    return val
  end
end
function types.location(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    val = true
    if isTrigger and val then ts[1]=true end
    return val
  end
end
types['custom-event'] = function(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    val = true
    if isTrigger and val then ts[1]=true end
    return val
  end
end
function types.alarm(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    val = true
    if isTrigger and val then ts[1]=true end
    return val
  end
end
types['se-start'] = function(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    val = true
    if isTrigger and val then ts[1]=true end
    return val
  end
end

local function compile(c)
  if next(c)==nil then return function() return true end
elseif c.conditions and operators[c.operator or ""] then
  local cs = {}
  for _,c in ipairs(c.conditions) do
    cs[#cs+1]=compile(c) 
  end
  local f = operators[c.operator]
  return function(trigger,ts) return f(trigger,ts,cs) end
elseif types[c.type or ""] then
  return types[c.type](c)
end
LOG(EM.LOGERR,"Bad condition %s",json.encode(c))
end

local function post(e)
  LOG(EM.LOGALLW,"SourceTrigger:%s",json.encode(e))
  for id,s in pairs(Scenes) do
    local ts = {}
    if s.cc(e,ts) and ts[1] then
      FB.setTimeout(s.action,0)
    end
  end
end

local function equal(e1,e2)
  if e1==e2 then return true
  else
    if type(e1) ~= 'table' or type(e2) ~= 'table' then return false
    else
      for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
      for k2,_  in pairs(e2) do if e1[k2] == nil then return false end end
      return true
    end
  end
end

local function filter(x) return false end

local EventTypes = { -- There are more, but these are what I seen so far...
  AlarmPartitionArmedEvent = function(d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
  AlarmPartitionBreachedEvent = function(d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
  HomeArmStateChangedEvent = function(d) post({type='alarm', property='homeArmed', value=d.newValue}) end,
  HomeBreachedEvent = function(d) post({type='alarm', property='homeBreached', value=d.breached}) end,
  WeatherChangedEvent = function(d) post({type='weather',property=d.change, value=d.newValue, old=d.oldValue}) end,
  GlobalVariableChangedEvent = function(d) 
    post({type='global-variable', name=d.variableName, value=d.newValue, old=d.oldValue}) 
  end,
  DevicePropertyUpdatedEvent = function(d)
    if d.property=='quickAppVariables' then 
      local old={}; for _,v in ipairs(d.oldValue) do old[v.name] = v.value end -- Todo: optimize
      for _,v in ipairs(d.newValue) do
        if not equal(v.value,old[v.name]) then
          post({type='quickvar', id=d.id, name=v.name, value=v.value, old=old[v.name]})
        end
      end
    else
      if d.property == "icon" or filter(d.id,d.property,d.newValue) then return end
      post({type='device', id=d.id, property=d.property, value=d.newValue, old=d.oldValue})
    end
  end,
  CentralSceneEvent = function(d) 
    d.id = d.id or d.deviceId
    d.icon=nil 
    post({type='device', property='centralSceneEvent', id=d.id, value={keyId=d.keyId, keyAttribute=d.keyAttribute}}) 
  end,
  SceneActivationEvent = function(d) 
    d.id = d.id or d.deviceId
    post({type='device', property='sceneActivationEvent', id=d.id, value={sceneId=d.sceneId}})     
  end,
  AccessControlEvent = function(d) 
    post({type='device', property='accessControlEvent', id=d.id, value=d}) 
  end,
  CustomEvent = function(d) 
    local value = api.get("/customEvents/"..d.name) 
    post({type='custom-event', name=d.name, value=value and value.userDescription}) 
  end,
  PluginChangedViewEvent = function(d) post({type='PluginChangedViewEvent', value=d}) end,
  WizardStepStateChangedEvent = function(d) post({type='WizardStepStateChangedEvent', value=d})  end,
  UpdateReadyEvent = function(d) post({type='updateReadyEvent', value=d}) end,
  DeviceRemovedEvent = function(d)  post({type='deviceEvent', id=d.id, value='removed'}) end,
  DeviceChangedRoomEvent = function(d)  post({type='deviceEvent', id=d.id, value='changedRoom'}) end,
  DeviceCreatedEvent = function(d)  post({type='deviceEvent', id=d.id, value='created'}) end,
  DeviceModifiedEvent = function(d) post({type='deviceEvent', id=d.id, value='modified'}) end,
  PluginProcessCrashedEvent = function(d) post({type='deviceEvent', id=d.deviceId, value='crashed', error=d.error}) end,
  SceneStartedEvent = function(d)   post({type='sceneEvent', id=d.id, value='started'}) end,
  SceneFinishedEvent = function(d)  post({type='sceneEvent', id=d.id, value='finished'})end,
  SceneRunningInstancesEvent = function(d) post({type='sceneEvent', id=d.id, value='instance', instance=d}) end,
  SceneRemovedEvent = function(d)  post({type='sceneEvent', id=d.id, value='removed'}) end,
  SceneModifiedEvent = function(d)  post({type='sceneEvent', id=d.id, value='modified'}) end,
  SceneCreatedEvent = function(d)  post({type='sceneEvent', id=d.id, value='created'}) end,
  OnlineStatusUpdatedEvent = function(d) post({type='onlineEvent', value=d.online}) end,
  --onUIEvent = function(d) post({type='uievent', deviceID=d.deviceId, name=d.elementName}) end,
  ActiveProfileChangedEvent = function(d) 
    post({type='profile',property='activeProfile',value=d.newActiveProfile, old=d.oldActiveProfile}) 
  end,
  ClimateZoneChangedEvent = function(d) d.type = 'ClimateZoneChangedEvent' post(d) end,
  ClimateZoneSetpointChangedEvent = function(d) d.type = 'ClimateZoneSetpointChangedEvent' post(d) end,
  NotificationCreatedEvent = function(d) post({type='notification', id=d.id, value='created'}) end,
  NotificationRemovedEvent = function(d) post({type='notification', id=d.id, value='removed'}) end,
  NotificationUpdatedEvent = function(d) post({type='notification', id=d.id, value='updated'}) end,
  RoomCreatedEvent = function(d) post({type='room', id=d.id, value='created'}) end,
  RoomRemovedEvent = function(d) post({type='room', id=d.id, value='removed'}) end,
  RoomModifiedEvent = function(d) post({type='room', id=d.id, value='modified'}) end,
  SectionCreatedEvent = function(d) post({type='section', id=d.id, value='created'}) end,
  SectionRemovedEvent = function(d) post({type='section', id=d.id, value='removede'}) end,
  SectionModifiedEvent = function(d) post({type='section', id=d.id, value='modified'}) end,
  DeviceActionRanEvent = function(_) end,
  QuickAppFilesChangedEvent = function(_) end,
  ZwaveDeviceParametersChangedEvent = function(_) end,
  ZwaveNodeAddedEvent = function(_) end,
  RefreshRequiredEvent = function(_) end,
  DeviceFirmwareUpdateEvent = function(_) end,
  GeofenceEvent = function(d) 
    post({type='location',id=d.userId,property=d.locationId,value=d.geofenceAction,timestamp=d.timestamp})
  end,
}

local function startScene(self,env,info)
  self:debug("Started")
end

EM.EMEvents('infoEnv',function(ev) -- Intercept
    local info = ev.info
    local env = info.env
    if info.scene then
      env.__TAG = "SCENE"..env.plugin.mainDeviceId
      env.QuickApp.onInit = function(self) startScene(self,env,info) end
    end
  end)

EM.EMEvents('QACreated',function(ev) 
    local qa,dev = ev.qa,ev.dev
    local env = dev._info.env
    if not dev._info.scene then return end
    env.sceneId = "SCENE"..env.plugin.mainDeviceId
    Scenes[env.plugin.mainDeviceId] = {
      conditions = env.CONDITIONS,
      cc = compile(env.CONDITIONS),
      action = env.ACTION,
      env = env,
    }
  end)

EM.EMEvents('start',function(ev) 
    EM.addRefreshListener(function(events)
        for _,e in ipairs(events) do
          if EventTypes[e.type] then EventTypes[e.type](e.data) end
        end
      end)
  end)