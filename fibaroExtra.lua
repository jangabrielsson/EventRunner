fibaro = fibaro  or  {}
fibaro.FIBARO_EXTRA = "v0.6"

-------------------- Utlities -----------------------
utils = {}

local function copy(obj)
  if type(obj) == 'table' then
    local res = {} for k,v in pairs(obj) do res[k] = v end
    return res
  else return obj end
end
utils.copy = copy 

function utils.copyShallow(t)
  if type(t)=='table' then
    local r={}; for k,v in pairs(t) do r[k]=v end 
    return r 
  else return t end
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
utils.equal=equal

function utils.member(k,tab) for _,v in ipairs(tab) do if v==k then return true end end return false end
function utils.remove(k,tab) local r = {}; for _,v in ipairs(tab) do if v ~= k then r[#r+1]=v end end return r end
function utils.map(f,l) local r={}; for _,e in ipairs(l) do r[#r+1]=f(e) end; return r end
function utils.mapf(f,l) for _,e in ipairs(l) do f(e) end; end
function utils.reduce(f,l) local r = {}; for _,e in ipairs(l) do if f(e) then r[#r+1]=e end end; return r end
function utils.mapk(f,l) local r={}; for k,v in pairs(l) do r[k]=f(v) end; return r end
function utils.mapkv(f,l) local r={}; for k,v in pairs(l) do k,v=f(k,v) r[k]=v end; return r end

function utils.keyMerge(t1,t2)
  local res = utils.copy(t1)
  for k,v in pairs(t2) do if t1[k]==nil then t1[k]=v end end
  return res
end

function utils.keyIntersect(t1,t2)
  local res = {}
  for k,v in pairs(t1) do if t2[k] then res[k]=v end end
  return res
end

function utils.zip(fun,a,b,c,d) 
  local res = {}
  for i=1,math.max(#a,#b) do res[#res+1] = fun(a[i],b[i],c and c[i],d and d[i]) end
  return res
end

function utils.basicAuthorization(user,password) return "Basic "..utils.encodeBase64(user..":"..password) end
function utils.base64encode(data)
  local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x) 
          local r,b='',x:byte() for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
          return r;
        end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
      end)..({ '', '==', '=' })[#data%3+1])
end
----------------------------- Fibaro functions --------------------

local HC3version = nil
function fibaro.HC3version(version)     -- Return/optional check HC3 version
  if HC3version == nil then HC3version = api.get("/settings/info").currentVersion.version end
  if version then return version >= HC3version else return HC3version end 
end

local IPaddress = nil
function fibaro.getIPaddress(name)
  if IPaddress then return IPaddress end
  if hc3_emulator then return hc3_emulator.IPaddress
  else
    name = name or ".*"
    local networkdata = api.get("/proxy?url=http://localhost:11112/api/settings/network")
    for n,d in pairs(networkdata.networkConfig or {}) do
      if n:match(name) and d.enabled then IPaddress = d.ipConfig.ip; return IPaddress end
    end
  end
end

--------------------- Time functions ------------------------------------------

local function toSeconds(str)
  __assert_type(str,"string" )
  local sun = str:match("(sun%a+)") 
  if sun then return toSeconds(str:gsub(sun,fibaro.getValue(1,sun.."Hour"))) end
  local var = str:match("(%$[A-Za-z]+)") 
  if var then return toSeconds(str:gsub(var,fibaro.getGlobalVariable(var:sub(2)))) end
  local h,m,s,op,off=str:match("(%d%d):(%d%d):?(%d*)([+%-]*)([%d:]*)")
  off = off~="" and (off:find(":") and toSeconds(off) or toSeconds("00:00:"..off)) or 0
  return 3600*h+60*m+(s~="" and s or 0)+((op=='-' or op =='+-') and -1 or 1)*off
end
fibaro.toSeconds = toSeconds

function fibaro.between(start,stop,optTime)
  __assert_type(start,"string" )
  __assert_type(stop,"string" )
  start,stop,optTime=toSeconds(start),toSeconds(stop),optTime and toSeconds(optTime) or toSeconds(os.date("%H:%M"))
  stop = stop>=start and stop or stop+24*3600
  optTime = optTime>=start and optTime or optTime+24*3600
  return start <= optTime and optTime <= stop
end

--------------------- Trace functions ------------------------------------------

--------------------- Debug functions -----------------------------------------
local format,fformat = string.format
local debugFlags = {}
fibaro.debugFlags = debugFlags
debugFlags.debugLevel=nil
debugFlags.traceLevel=nil
debugFlags.notifyError=true
debugFlags.notifyWarning=true
debugFlags.onaction=true
debugFlags.uievent=true
debugFlags.json=true
debugFlags.html=true
debugFlags.reuseNotifies=true

-- Add notification to notification center
local cachedNots = {}
local function notify(priority, text, reuse)
  local id = quickApp and  quickApp.id or sceneId
  local idt = quickApp and "deviceId" or "sceneId"
  local name = quickApp and quickApp.name or tag or "Scene"
  assert(({info=true,warning=true,alert=true})[priority],"Wrong 'priority' - info/warning/alert")
  local title = text:match("(.-)[:%s]") or format("%s deviceId:%d",name,idt,id)

  if reuse==nil then reuse = debugFlags.reuseNotifies end
  local msgId = nil
  local data = {
    canBeDeleted = true,
    wasRead = false,
    priority = priority,
    type = "GenericDeviceNotification",
    data = {
      sceneId = sceneId,
      deviceId = quickApp and quickApp.id,
      subType = "Generic",
      title = title,
      text = tostring(text)
    }
  }
  local nid = title..id
  if reuse then
    if cachedNots[nid] then
      msgId = cachedNots[nid]
    else
      for _,n in ipairs(api.get("/notificationCenter") or {}) do
        if n.data and (n.data.deviceId == id or n.data.sceneeId == id) and n.data.title == title then
          msgId = n.id; break
        end
      end
    end
  end
  if msgId then
    api.put("/notificationCenter/"..msgId, data)
  else
    local d = api.post("/notificationCenter", data)
    if d then cachedNots[nid] = d.id end
  end
end

local oldPrint = print
local inhibitPrint = {['onAction: ']='onaction', ['UIEvent: ']='uievent'}
function print(a,...) 
  if not inhibitPrint[a] or debugFlags[inhibitPrint[a]] then
    oldPrint(a,...) 
  end
end

local old_tostring = tostring
function tostring(obj)
  if type(obj)=='table' then
    if obj.__tostring then return obj.__tostring(obj) 
    elseif debugFlags.json then return json.encodeFast(obj) end
  end
  return old_tostring(obj)
end

local htmlCodes={['\n']='<br>', [' ']='&nbsp;'}
local function htmlTransform(str)
  return (debugFlags.html and not hc3_emulator) and str:gsub("([\n%s])",function(c) return htmlCodes[c] or c end) or str
end

function fformat(fmt,...)
  local args = {...}
  if #args == 0 then return tostring(fmt) end
  for i,v in ipairs(args) do if type(v)=='table' then args[i]=tostring(v) end end
  return htmlTransform(format(fmt,table.unpack(args)))
end

local function arr2str(...)
  local args,res = {...},{}
  for i=1,#args do if args[i]~=nil then res[#res+1]=tostring(args[i]) end end 
  return htmlTransform(table.concat(res," "))
end 

local function print_debug(typ,tag,str)
  api.post("/debugMessages",{
      messageType=typ or "debug",
      message = str or "",
      tag = tag or __TAG
    })
  return str
end

function fibaro.debug(tag,...) 
  if not(type(tag)=='number' and tag > (debugFlags.debugLevel or 0)) then 
    return print_debug('debug',tag,arr2str(...)) 
  else return "" end 
end
function fibaro.trace(tag,...) 
  if not(type(tag)=='number' and tag > (debugFlags.traceLevel or 0)) then 
    return print_debug('trace',tag,arr2str(...)) 
  else return "" end 
end
function fibaro.error(tag,...)
  local str = print_debug('error',tag,arr2str(...))
  if debugFlags.notifyError then notify("alert",str) end
  return str
end
function fibaro.warning(tag,...) 
  local str = print_debug('warning',tag,arr2str(...))
  if debugFlags.notifyWarning then notify("warning",str) end
  return str
end
function fibaro.debugf(tag,fmt,...) 
  if not(type(tag)=='number' and tag > (debugFlags.debugLevel or 0)) then 
    return print_debug('debug',tag,fformat(fmt,...)) 
  else return "" end 
end
function fibaro.tracef(tag,fmt,...) 
  if not(type(tag)=='number' and tag > (debugFlags.traceLevel or 0)) then 
    return print_debug('trace',tag,fformat(fmt,...)) 
  else return "" end 
end
function fibaro.errorf(tag,fmt,...)
  local str = print_debug('error',tag,fformat(fmt,...)) 
  if debugFlags.notifyError then notify("alert",str) end
  return str
end
function fibaro.warningf(tag,fmt,...) 
  local str = print_debug('warning',tag,fformat(fmt,...)) 
  if debugFlags.notifyWarning then notify("warning",str) end
  return str
end

--------------------- Scene function, "missing" from HC2 ----------------------
function fibaro.isSceneEnabled(sceneID) 
  __assert_type(sceneID,"number" )
  return api.get("/scenes/"..sceneID).enabled 
end

function fibaro.setSceneEnabled(sceneID,enabled) 
  __assert_type(sceneID,"number" )   __assert_type(enabled,"boolean" )
  return api.put("/scenes/"..sceneID,{enabled=enabled}) 
end

function fibaro.getSceneRunConfig(sceneID)
  __assert_type(sceneID,"number" )
  return api.get("/scenes/"..sceneID).mode 
end

function fibaro.setSceneRunConfig(sceneID,runConfig)
  __assert_type(sceneID,"number" )
  assert(({automatic=true,manual=true})[runConfig],"runconfig must be 'automatic' or 'manual'")
  return api.put("/scenes/"..sceneID, {mode = runConfig}) 
end

---------------------------- Globals -------------------------------
function fibaro.getAllGlobalVariables() 
  return utils.map(function(v) return v.name end,api.get("/globalVariables")) 
end

function fibaro.createGlobalVariable(name,value,options)
  __assert_type(name,"string")
  value = tostring(value)
  local args = utils.copy(options or {})
  args.name,args.value=name,value
  api.post("/globalVariables",args)
end

function fibaro.deleteGlobalVariable(name) 
  __assert_type(name,"string")
  return api.delete("/globalVariable/"..name) 
end

function fibaro.existGlobalVariable(name)
  __assert_type(name,"string")
  return api.get("/globalVariable/"..name) and true 
end

function fibaro.getGlobalVariableType(name)
  __assert_type(name,"string")
  local v = api.get("/globalVariable/"..name) or {}
  return v.isEnum,v.readOnly
end

function fibaro.getGlobalVariableLastModified(name)
  __assert_type(name,"string")
  return (api.get("/globalVariable/"..name) or {}).modified 
end

---------------------------- Custom events -------------------------
function fibaro.getAllCustomEvents() 
  return utils.map(function(v) return v.name end,api.get("/customEvents") or {}) 
end

function fibaro.createCustomEvent(name,userDescription) 
  __assert_type(name,"string" )
  return api.post("/customEvent",{name=name,uderDescription=userDescription or ""})
end

function fibaro.deleteCustomEvent(name) 
  __assert_type(name,"string" )
  return api.delete("/customEvents/"..name) 
end

function fibaro.existCustomEvent(name) 
  __assert_type(name,"string" )
  return api.get("/customEvents/"..name) and true 
end

---------------------------- Profiles -----------------------------
function fibaro.activeProfile(id)
  if id then
    if type(id)=='string' then id = fibaro.profileNameToId(name) end
    assert(id,"fibaro.getActiveProfile(id) - no such id/name")
    return api.put("/profiles",{activeProfile=id}) and id
  end
  return api.get("/profiles").activeProfile 
end

function fibaro.profileIdtoName(pid)
  __assert_type(pid,"number")
  for _,p in ipairs(api.get("/profiles").profiles or {}) do 
    if p.id == pid then return p.name end 
  end 
end

function fibaro.profileNameToId(name)
  __assert_type(name,"string")
  for _,p in ipairs(api.get("/profiles").profiles or {}) do 
    if p.name == name then return p.id end 
  end 
end

---------------------------- Alarm functions ----------------------
function fibaro.partitionIdToName(pid)
  __assert_type(pid,"number")
  return (api.get("/alarms/v1/partitions/"..pid) or {}).name 
end

function fibaro.partitionNameToId(name)
  assert(type(name)=='string',"Alarm partition name not a string")
  for _,p in ipairs(api.get("/alarms/v1/partitions") or {}) do
    if p.name == name then return p.id end
  end
end

-- Returns devices breached in partition 'pid'
function fibaro.getBreachedDevicesInPartition(pid)
  assert(type(pid)=='number',"Alarm partition id not a number")
  local p,res = api.get("/alarms/v1/partitions/"..pid),{}
  for _,d in ipairs((p or {}).devices or {}) do
    if fibaro.getValue(d,"value") then res[#res+1]=d end
  end
  return res
end

-- helper function
local function filterPartitions(filter)
  local res = {}
  for _,p in ipairs(api.get("/alarms/v1/partitions") or {}) do if filter(p) then res[#res+1]=p.id end end
  return res
end

-- Return all partitions ids
function fibaro.getAllPartitions() return filterPartitions(function(p) return true end) end

-- Return partitions that are armed
function fibaro.getArmedPartitions() return filterPartitions(function(p) return p.armed end) end

-- Return partitions that are about to be armed
function fibaro.getActivatedPartitions() return filterPartitions(function(p) return p.secondsToArm end) end

-- Return breached partitions
function fibaro.getBreachedPartitions() return api.get("/alarms/v1/partitions/breached") end

--If you want to list all devices that can be part of a alarm partition/zone you can do
function fibaro.getAlarmDevices() return api.get("/alarms/v1/devices/") end

do 
  fibaro.ALARM_INTERVAL = 1000
  local fun
  local ref
  local armedPs={}
  local function watchAlarms()
    for _,p in ipairs(api.get("/alarms/v1/partitions") or {}) do
      if p.secondsToArm and not armedPs[p.id] then
        setTimeout(function() pcall(fun,p.id) end,0)
      end
      armedPs[p.id] = p.secondsToArm
    end
  end
  function fibaro.activatedPartitions(callback)
    __assert_type(callback,"function")
    fun = callback
    if fun and ref == nil then
      ref = setInterval(watchAlarms,fibaro.ALARM_INTERVAL)
    elseif fun == nil and ref then
      clearInterval(ref); ref = nil 
    end
  end
end

--[[ Ex. check what partitions have breached devices
for _,p in ipairs(getAllPartitions()) do
  local bd = getBreachedDevicesInPartition(p)
  if bd[1] then print("Partition "..p.." contains breached devices "..json.encode(bd)) end
end
--]]

------------------------- Weather --------------------------
fibaro.weather = {}
function fibaro.weather.temperature() return api.get("/weather").Temperature end
function fibaro.weather.temperatureUnit() return api.get("/weather").TemperatureUnit end
function fibaro.weather.humidity() return api.get("/weather").Humidity end
function fibaro.weather.wind() return api.get("/weather").Wind end
function fibaro.weather.weatherCondition() return api.get("/weather").WeatherCondition end
function fibaro.weather.conditionCode() return api.get("/weather").ConditionCode end

---------------------------------------------------------------
fibaro.REFRESH_STATES_INTERVAL = 1000
local sourceTriggerCallback,refreshCallback,refreshRef,pollRefresh
local ENABLEDSOURCETRIGGERS,DISABLEDREFRESH={},{}

function fibaro.getSourceTriggers(callback)
  __assert_type(callback,"function")
  sourceTriggerCallback = callback
  if sourceTriggerCallback or refreshCallback then
    if not refreshRef then 
      refreshRef = setTimeout(pollRefresh,0)
      if debugFlags._sourceTrigger then fibaro.debug(nil,"Polling for sourceTriggers") end
    end
  else 
    if refreshRef then 
      clearTimeout(refreshRef); refreshRef = nil 
      if debugFlags._sourceTrigger then fibaro.debug(nil,"Stop polling for sourceTriggers") end
    end
  end
end

function fibaro.enableSourceTriggers(trigger)
  if type(trigger)~='table' then  trigger={trigger} end
  for _,t in  ipairs(trigger) do ENABLEDSOURCETRIGGERS[t]=true end
end
fibaro.enableSourceTriggers({"device","alarm","global-variable","custom-event"})

function fibaro.disableSourceTriggers(trigger)
  if type(trigger)~='table' then  trigger={trigger} end
  for _,t in  ipairs(trigger) do ENABLEDSOURCETRIGGERS[t]=nil end
end

local propFilters = {}
function fibaro.sourceTriggerDelta(id,prop,value)
  __assert_type(id,"number")
  __assert_type(prop,"string")
  local d = propFilters[id] or {}
  d[prop] =  {delta = value}
  propFilters[id] = d
end

local function filter(id,prop,new)
  local d = (propFilters[id] or {})[prop]
  if d then
    if d.last == nil then 
      d.last = new
      return false
    else
      if math.abs(d.last-new) >= d.delta then
        d.last = new
        return false
      else return true end
    end
  else return false end
end

local function post(ev)
  if ENABLEDSOURCETRIGGERS[ev.type] then
    if debugFlags.sourceTrigger then fibaro.debugf("Incoming sourceTrigger:%s",ev) end
    ev._trigger=true
    if sourceTriggerCallback then setTimeout(function() sourceTriggerCallback(ev) end,0) end
  end
end

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
        if v.value ~= old[v.name] then
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

local lastRefresh = 0
net = net or { HTTPClient = function() end  }
local http = net.HTTPClient()
math.randomseed(os.time())
local urlTail = "&lang=en&rand="..math.random(2000,4000).."&logs=false"
function pollRefresh()
  local stat,res = http:request("http://127.0.0.1:11111/api/refreshStates?last=" .. lastRefresh..urlTail,{
      success=function(res)
        local states = res.status == 200 and json.decode(res.data)
        if states then
          lastRefresh=states.last
          if states.events and #states.events>0 then 
            for _,e in ipairs(states.events) do
              fibaro._postRefreshState(e)
              local handler = EventTypes[e.type]
              if handler then handler(e.data)
              elseif handler==nil and fibaro._UNHANDLED_REFRESHSTATES then 
                fibaro.debugf(__TAG,"[Note] Unhandled refreshState:%s -- please report",e) 
              end
            end
          end
        end 
        refreshRef = setTimeout(pollRefresh,fibaro.REFRESH_STATES_INTERVAL or 0)
      end,
      error=function(res) 
        fibaro.errorf(__TAG,"refreshStates:%s",res)
        refreshRef = setTimeout(pollRefresh,1000)
      end,
    })
end

function fibaro.getRefreshStates(callback)
  __assert_type(callback,"function")
  refreshCallback = callback
  if sourceTriggerCallback or refreshCallback then
    if not refreshRef then refreshRef = setTimeout(pollRefresh,0) end
    if debugFlags._sourceTrigger then fibaro.debug(nil,"Polling for refreshStates") end
  else 
    if refreshRef then clearTimeout(refreshRef); refreshRef = nil end
    if debugFlags._sourceTrigger then fibaro.debug(nil,"Stop polling for refreshStates") end
  end
end

function fibaro.enableRefreshStatesTypes(typs) 
  if  type(typs)~='table' then typs={typs} end
  for _,t in ipairs(typs) do DISABLEDREFRESH[t]=nil end
end

function fibaro.disableRefreshStatesTypes(typs)
  if  type(typs)~='table' then typs={typs} end
  for _,t in ipairs(typs) do DISABLEDREFRESH[t]=true end
end

function fibaro._postSourceTrigger(trigger) post(trigger) end

function fibaro._postRefreshState(event)
  if refreshCallBack and not DISABLEDREFRESH[e.type] then 
    setTimeout(function() refreshCallBack(e) end,0)
  end
end

---------------------------- Net functions -------------------
netSync = { HTTPClient = function(args)
    local self,queue,HTTP,key = {},{},net.HTTPClient(args),0
    local _request
    local function dequeue()
      table.remove(queue,1)
      local v = queue[1]
      if v then 
        --if _debugFlags.netSync then self:debugf("netSync:Pop %s (%s)",v[3],#queue) end
        --setTimeout(function() _request(table.unpack(v)) end,1) 
        _request(table.unpack(v))
      end
    end
    _request = function(url,params,key)
      params = copy(params)
      local uerr,usucc = params.error,params.success
      params.error = function(status)
        --if _debugFlags.netSync then self:debugf("netSync:Error %s %s",key,status) end
        dequeue()
        --if params._logErr then self:errorf(" %s:%s",log or "netSync:",tojson(status)) end
        if uerr then uerr(status) end
      end
      params.success = function(status)
        --if _debugFlags.netSync then self:debugf("netSync:Success %s",key) end
        dequeue()
        if usucc then usucc(status) end
      end
      --if _debugFlags.netSync then self:debugf("netSync:Calling %s",key) end
      HTTP:request(url,params)
    end
    function self:request(url,parameters)
      key = key+1
      if next(queue) == nil then
        queue[1]='RUN'
        _request(url,parameters,key)
      else 
        --if _debugFlags.netSync then self:debugf("netSync:Push %s",key) end
        queue[#queue+1]={url,parameters,key} 
      end
    end
    return self
  end}

--------------------------- QA functions --------------------------------
function fibaro.restartQA(id)
  __assert_type(id,"number")
  return api.post("/plugins/restart",{deviceId=id or quickApp.id})
end

function fibaro.getQAVariable(id,name)
  __assert_type(id,"number")
  __assert_type(name,"string")
  local props = (api.get("/devices/"..(id or quickApp.id)) or {}).properties or {}
  for _, v in ipairs(props.quickAppVariables or {}) do
    if v.name==name then return v.value end
  end
end

function fibaro.setQAVariable(id,name,value)
  __assert_type(id,"number")
  __assert_type(name,"string")
  return fibaro.call(id,"setVariable",name,value)
end

function fibaro.getAllQAVariables(id)
  __assert_type(id,"number")
  local props = (api.get("/devices/"..(id or quickApp.id)) or {}).properties or {}
  local res = {}
  for _, v in ipairs(props.quickAppVariables or {}) do
    res[v.name]=v.value
  end
  return res
end

function fibaro.isQAEnabled(id)
  __assert_type(id,"number")
  local dev = api.get("/devices/"..(id or quickApp.id))
  return (dev or {}).enabled
end

function fibaro.enableQA(id,enable)
  __assert_type(id,"number")
  __assert_type(enable,"boolean")
  return api.post("/devices/"..(id or quickApp.id),{enabled=enable==true})
end

---------------------------- Utils --------------------------------------
function urlencode(str) -- very useful
  if str then
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w %-%_%.%~])", function(c)
        return ("%%%02X"):format(string.byte(c))
      end)
    str = str:gsub(" ", "%%20")
  end
  return str	
end

do
  json = json or {}
  local setinterval,encode,decode =  -- gives us a better error messages
  setInterval, json.encode, json.decode
  local oldClearTimout,oldSetTimout

  if not hc3_emulator then -- Patch short-sighthed setTimeout...
    clearTimeout,oldClearTimout=function(ref)
      if type(ref)=='table' and ref[1]=='%EXT%' then ref=ref[2] end
      oldClearTimout(ref)
    end,clearTimeout

    setTimeout,oldSetTimout=function(f,ms)
      local ref,maxt={'%EXT%'},2147483648-1
      local fun = function() -- wrap function to get error messages
        local stat,res = pcall(f)
        if not stat then 
          error(res,2)
        end
      end
      if ms > maxt then
        ref[2]=oldSetTimout(function() ref[2 ]=setTimeout(fun,ms-maxt)[2] end,maxt)
      else ref[2 ]=oldSetTimout(fun,math.floor(ms+0.5)) end
      return ref
    end,setTimeout

    function setInterval(fun,ms) -- can't manage looong intervals
      return setinterval(function()
          local stat,res = pcall(fun)
          if not stat then 
            error(res,2)
          end
        end,math.floor(ms+0.5))
    end
    function json.decode(...)
      local stat,res = pcall(decode,...)
      if not stat then error(res,2) else return res end
    end
    function json.encode(...)
      local stat,res = pcall(encode,...)
      if not stat then error(res,2) else return res end
    end
  end
end

do
  local sortKeys = {"type","device","deviceID","value","oldValue","val","key","arg","event","events","msg","res"}
  local sortOrder={}
  for i,s in ipairs(sortKeys) do sortOrder[s]="\n"..string.char(i+64).." "..s end
  local function keyCompare(a,b)
    local av,bv = sortOrder[a] or a, sortOrder[b] or b
    return av < bv
  end

  -- our own json encode, as we don't have 'pure' json structs, and sorts keys in order (i.e. "stable" output)
  local function prettyJsonFlat(e) 
    local res,seen = {},{}
    local function pretty(e)
      local t = type(e)
      if t == 'string' then res[#res+1] = '"' res[#res+1] = e res[#res+1] = '"'
      elseif t == 'number' then res[#res+1] = e
      elseif t == 'boolean' or t == 'function' or t=='thread' or t=='userdata' then res[#res+1] = tostring(e)
      elseif t == 'table' then
        if next(e)==nil then res[#res+1]='{}'
        elseif seen[e] then res[#res+1]="..rec.."
        elseif e[1] or #e>0 then
          seen[e]=true
          res[#res+1] = "[" pretty(e[1])
          for i=2,#e do res[#res+1] = "," pretty(e[i]) end
          res[#res+1] = "]"
        else
          seen[e]=true
          if e._var_  then res[#res+1] = format('"%s"',e._str) return end
          local k = {} for key,_ in pairs(e) do k[#k+1] = key end
          table.sort(k,keyCompare)
          if #k == 0 then res[#res+1] = "[]" return end
          res[#res+1] = '{'; res[#res+1] = '"' res[#res+1] = k[1]; res[#res+1] = '":' t = k[1] pretty(e[t])
          for i=2,#k do
            res[#res+1] = ',"' res[#res+1] = k[i]; res[#res+1] = '":' t = k[i] pretty(e[t])
          end
          res[#res+1] = '}'
        end
      elseif e == nil then res[#res+1]='null'
      else error("bad json expr:"..tostring(e)) end
    end
    pretty(e)
    return table.concat(res)
  end
  json.encodeFast = prettyJsonFlat
end

do -- Used for print device table structs - sortorder for device structs
  local sortKeys = {
    'id','name','roomID','type','baseType','enabled','visible','isPlugin','parentId','viewXml','configXml',
    'interfaces','properties','view', 'actions','created','modified','sortOrder'
  }
  local sortOrder={}
  for i,s in ipairs(sortKeys) do sortOrder[s]="\n"..string.char(i+64).." "..s end
  local function keyCompare(a,b)
    local av,bv = sortOrder[a] or a, sortOrder[b] or b
    return av < bv
  end

  local function prettyJsonStruct(t0)
    local res = {}
    local function isArray(t) return type(t)=='table' and t[1] end
    local function isEmpty(t) return type(t)=='table' and next(t)==nil end
    local function printf(tab,fmt,...) res[#res+1] = string.rep(' ',tab)..string.format(fmt,...) end
    local function pretty(tab,t,key)
      if type(t)=='table' then
        if isEmpty(t) then printf(0,"[]") return end
        if isArray(t) then
          printf(key and tab or 0,"[\n")
          for i,k in ipairs(t) do
            local _ = pretty(tab+1,k,true)
            if i ~= #t then printf(0,',') end
            printf(tab+1,'\n')
          end
          printf(tab,"]")
          return true
        end
        local r = {}
        for k,_ in pairs(t) do r[#r+1]=k end
        table.sort(r,keyCompare)
        printf(key and tab or 0,"{\n")
        for i,k in ipairs(r) do
          printf(tab+1,'"%s":',k)
          local _ =  pretty(tab+1,t[k])
          if i ~= #r then printf(0,',') end
          printf(tab+1,'\n')
        end
        printf(tab,"}")
        return true
      elseif type(t)=='number' then
        printf(key and tab or 0,"%s",t)
      elseif type(t)=='boolean' then
        printf(key and tab or 0,"%s",t and 'true' or 'false')
      elseif type(t)=='string' then
        printf(key and tab or 0,'"%s"',t:gsub('(%")','\\"'))
      end
    end
    pretty(0,t0,true)
    return table.concat(res,"")
  end
  json.encodeFormated = prettyJsonStruct
end

function fibaro.sequence(...)
  local args,i = {...},1
  local function stepper()
    if i <= #args then
      local arg = args[i]
      i=i+1
      if type(arg)=='number' then 
        setTimeout(stepper,arg)
      elseif type(arg)=='table' and type(arg[1])=='function' then
        pcall(table.unpack(arg))
        setTimeout(stepper,0)
      end
    end
  end
  setTimeout(stepper,0)
end

function fibaro.trueFor(time,test,action)
  local state = false
  local  function loop()
    if test() then
      if state == false then
        state=os.time()+time
      elseif state == true then
      elseif state <=  os.time() then
        if action() then
          state = os.time()+time
        else
          state = true 
        end
      end
    else
      state=false
    end
    setTimeout(loop,delay)
  end
end
