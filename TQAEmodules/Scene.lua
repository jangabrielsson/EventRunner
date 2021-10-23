--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Rudimentary scene support

--]]
local EM,FB=...

local LOG,json,Devices = EM.LOG,FB.json,EM.Devices
local fmt = string.format
local equal,copy = EM.utilities.equal,EM.utilities.copy
local Scenes = {}
local runTriggers

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

local function cronTest(dateStr) -- code for creating cron date test to use in scene condition
  local days = {sun=1,mon=2,tue=3,wed=4,thu=5,fri=6,sat=7}
  local months = {jan=1,feb=2,mar=3,apr=4,may=5,jun=6,jul=7,aug=8,sep=9,oct=10,nov=11,dec=12}
  local last,month = {31,28,31,30,31,30,31,31,30,31,30,31},nil

  local function seq2map(seq) local s = {} for _,v in ipairs(seq) do s[v] = true end return s; end

  local function flatten(seq,res) -- flattens a table of tables
    res = res or {}
    if type(seq) == 'table' then for _,v1 in ipairs(seq) do flatten(v1,res) end else res[#res+1] = seq end
    return res
  end

  local function expandDate(w1,md)
    local function resolve(id)
      local res
      if id == 'last' then month = md res=last[md]
      elseif id == 'lastw' then month = md res=last[md]-6
      else res= type(id) == 'number' and id or days[id] or months[id] or tonumber(id) end
      if res==nil then error("Bad date specifier "..tostring(id)) end 
      return res
    end
    local w,m,step= w1[1],w1[2],1
    local start,stop = w:match("(%w+)%p(%w+)")
    if (start == nil) then return resolve(w) end
    start,stop = resolve(start), resolve(stop)
    local res,res2 = {},{}
    if w:find("/") then
      if not w:find("-") then -- 10/2
        step=stop; stop = m.max
      else step=w:match("/(%d+)") end
    end
    step = tonumber(step)
    assert(start>=m.min and start<=m.max and stop>=m.min and stop<=m.max,"illegal date interval")
    while (start ~= stop) do -- 10-2
      res[#res+1] = start
      start = start+1; 
      if start>m.max then start=m.min end
    end
    res[#res+1] = stop
    if step > 1 then 
      for i=1,#res,step do res2[#res2+1]=res[i] end
      res=res2 
    end
    return res
  end

  table.maxn = table.maxn or function(t) return #t end

  local function map(f,l,s) s = s or 1; local r={} for i=s,table.maxn(l) do r[#r+1] = f(l[i]) end return r end
  local function parseDateStr(dateStr,last)
    local seq = dateStr:split(" ")   -- min,hour,day,month,wday
    local lim = {{min=0,max=59},{min=0,max=23},{min=1,max=31},{min=1,max=12},{min=1,max=7},{min=2019,max=2030}}
    for i=1,6 do if seq[i]=='*' or seq[i]==nil then seq[i]=tostring(lim[i].min).."-"..lim[i].max end end
    seq = map(function(w) return w:split(",") end, seq)   -- split sequences "3,4"
    local month = os.date("*t",EM.osTime()).month
    seq = map(function(t) local m = table.remove(lim,1);
        return flatten(map(function (g) return expandDate({g,m},month) end, t))
      end, seq) -- expand intervals "3-5"
    return map(seq2map,seq)
  end
  local sun,offs,day,sunPatch = dateStr:match("^(sun%a+) ([%+%-]?%d+)")
  if sun then
    sun = sun.."Hour"
    dateStr=dateStr:gsub("sun%a+ [%+%-]?%d+","0 0")
    sunPatch=function(dateSeq)
      local h,m = (FB.fibaro.getValue(1,sun)):match("(%d%d):(%d%d)")
      dateSeq[1]={[(h*60+m+offs)%60]=true}
      dateSeq[2]={[math.floor((h*60+m+offs)/60)]=true}
    end
  end
  local dateSeq = parseDateStr(dateStr)
  return function(ctx) -- Pretty efficient way of testing dates...
    local t = ctx or os.date("*t",EM.osTime())
    if month and month~=t.month then parseDateStr(dateStr) end -- Recalculate 'last' every month
    if sunPatch and (month and month~=t.month or day~=t.day) then sunPatch(dateSeq) day=t.day end -- Recalculate 'last' every month
    return
    dateSeq[1][t.min] and    -- min     0-59
    dateSeq[2][t.hour] and   -- hour    0-23
    dateSeq[3][t.day] and    -- day     1-31
    dateSeq[4][t.month] and  -- month   1-12
    dateSeq[5][t.wday] or false      -- weekday 1-7, 1=sun, 7=sat
  end
end

local function midnight() local d = os.date("*t",EM.osTime()) d.min,d.hour,d.sec=0,0,0; return os.time(d) end

local function checkdates()
  for _,s in pairs(Scenes) do
    local t = os.date("*t")
    runTriggers({type = "date", property = "cron",
        value = { tostring(t.min), tostring(t.hour), tostring(t.day), tostring(t.month), tostring(t.wday), tostring(t.year) }
      })
  end
end

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
  [""] = function() return false end,
}

local function str2sec(str)
  local h,m = str:match("(%d+):(%d+)")
  return math.floor(60*h+m)
end

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

local dateTimer
function types.date(c)
  local isTrigger = c.isTrigger

  if isTrigger and dateTimer==nil then
    LOG.sys("Starting scene cron loop")
    local nxt = (EM.osTime() // 60 +1)*60
    local function loop()
      checkdates()
      nxt=nxt+60
      LOG.sys("Cron checking next %s",os.date("%c",nxt))
      EM.systemTimer(loop,1000*(nxt-EM.osTime()))
    end
    LOG.sys("Cron checking next %s",os.date("%c",nxt))
    dateTimer = EM.systemTimer(loop,1000*(nxt-EM.osTime()))
  end

  if c.property =='cron' then
    local cron = table.concat(c.value," ")
    cron = cronTest(cron)
    return function(trigger,ts)
      local val = cron()
      if isTrigger and val then ts[1]=true end
      return val
    end
  elseif c.property == 'sunset' or c.property == 'sunrise' then
    return function(trigger,ts)
      local tt = str2sec(fibaro.getValue(1,c.property.."Hour"))+(c.value or 0)
      local now = str2sec(os.date("%H:%M"))
      local val = toppers[c.operator](now,tt)
      if isTrigger and val then ts[1]=true end
      return val
    end
  end
end

function types.weather(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    local val = false
    if isTrigger and val then ts[1]=true end
    return val
  end
end
function types.location(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    local val = false
    if isTrigger and val then ts[1]=true end
    return val
  end
end
types['custom-event'] = function(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    local val = false
    if isTrigger and val then ts[1]=true end
    return val
  end
end
function types.alarm(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    local val = false
    if isTrigger and val then ts[1]=true end
    return val
  end
end
types['se-start'] = function(c)
  local isTrigger = c.isTrigger
  return function(trigger,ts)
    local val = true
    if isTrigger and val then ts[1]=true end
    return val
  end
end

local function compile(c)
  if next(c)==nil then return 
    function() return true end
  elseif c.conditions and operators[c.operator or ""] then
    local cs = {}
    for _,c in ipairs(c.conditions) do
      cs[#cs+1]=compile(c) 
    end
    local f = operators[c.operator]
    return function(trigger,ts) return f(trigger,ts,cs) end
  elseif types[c.type or ""] then
    local f = types[c.type](c)
    return function(trigger,ts)
      return trigger.type==c.type and f(trigger,ts) 
    end
  end
  LOG.error("Bad condition %s",json.encode(c))
end

function runTriggers(e)
  for id,s in pairs(Scenes) do
    local ts = {}
    if s.cc(e,ts) and ts[1] then
      local env = s.env
      for k,v in pairs(s.orgEnv) do env[k]=v end
      for k,v in pairs(env) do if s.orgEnv[k]==nil then env[k]=nil end end
      s.env.sourceTrigger = e
      FB.setTimeout(s.action,0,nil,s.info)
    end
  end
end

local function post(e)
  if next(Scenes) then LOG.sys("SourceTrigger:%s",json.encode(e)) end
  runTriggers(e)
end

local function filter(x) return false end

local EventTypes = { -- There are more, but these are what I seen so far...
  AlarmPartitionArmedEvent = function(d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
  AlarmPartitionBreachedEvent = function(d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
  HomeArmStateChangedEvent = function(d) post({type='alarm', property='homeArmed', value=d.newValue}) end,
  HomeDisarmStateChangedEvent = function(d) post({type='alarm', property='homeArmed', value=not d.newValue}) end,
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
    local value = FB.api.get("/customEvents/"..d.name) 
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
  ClimateZoneChangedEvent = function(d)
    if d.changes and type(d.changes)=='table' then
      for _,c in ipairs(d.changes) do
        c.type,c.id='ClimateZone',d.id
        post(c)
      end
    end
  end,
  ClimateZoneSetpointChangedEvent = function(d) d.type = 'ClimateZoneSetpoint' post(d) end,
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

local function manualStart(id)
  local scene = Scenes[id]
  scene.env.sourceTrigger = {type='manual', property='execute'}
  FB.setTimeout(scene.action,1,nil,scene.info)
end

EM.EMEvents('infoEnv',function(ev) -- Intercept
    local info = ev.info
    local env = info.env
    if info.scene then
      env.__TAG = "SCENE"..env.plugin.mainDeviceId
      info.codeType="Scene"
    end
  end)

EM.EMEvents('sceneLoaded',function(ev) 
    local info = ev.info
    local env = info.env
    env.sceneId = "SCENE"..env.plugin.mainDeviceId
    Devices[info.id]=nil
    Scenes[env.plugin.mainDeviceId] = {
      conditions = env.CONDITIONS,
      cc = compile(env.CONDITIONS),
      action = function()
        LOG.sys("Starting scene %s",env.__TAG)
        local stat,res = pcall(env.ACTION)
        LOG.sys("Ended scene %s",env.__TAG)
        if not stat then LOG.error("%s",res) end
      end,
      info=info,
      env = env,      
      orgEnv = copy(env),
    }
    if info.runAtStart then
      manualStart(env.plugin.mainDeviceId)
    end
  end)

EM.EMEvents('start',function(ev) 
    EM.addRefreshListener(function(events)
        for _,e in ipairs(events) do
          if EventTypes[e.type] then EventTypes[e.type](e.data) end
        end
      end)
  end)