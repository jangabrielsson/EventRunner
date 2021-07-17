fibaro = fibaro  or  {}
fibaro.FIBARO_EXTRA = "v0.905"

local MID = plugin and plugin.mainDeviceId or sceneId or 0
local format = string.format
local function assertf(test,fmt,...) if not test then error(format(fmt,...),2) end end
local debugFlags = {}
local toTime,copy,equal,member,remove

-------------------- Utilities ----------------------------------------------
do
  utils = {}
  if not setTimeout then
    function setTimeout(fun,ms) return fibaro.setTimeout(ms,fun) end
    function clearTimeout(ref) fibaro.clearTimeout(ref) end
    function setInterval(fun,ms) return fibaro.setInterval(ms,fun) end
    function clearInterval(ref) fibaro.clearInterval(ref) end
  end

  function copy(obj)
    if type(obj) == 'table' then
      local res = {} for k,v in pairs(obj) do res[k] = copy(v) end
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

  function equal(e1,e2)
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

  function member(k,tab) for i,v in ipairs(tab) do if equal(v,k) then return i end end return false end
  function remove(obj,list) local i = member(obj,list); if i then table.remove(list,i) return true end end
  utils.member,utils.remove = member,remove
  function utils.remove(k,tab) local r = {}; for _,v in ipairs(tab) do if not equal(v,k) then r[#r+1]=v end end return r end
  function utils.map(f,l) local r={}; for _,e in ipairs(l) do r[#r+1]=f(e) end; return r end
  function utils.mapf(f,l) for _,e in ipairs(l) do f(e) end; end
  function utils.reduce(f,l) local r = {}; for _,e in ipairs(l) do if f(e) then r[#r+1]=e end end; return r end
  function utils.mapk(f,l) local r={}; for k,v in pairs(l) do r[k]=f(v) end; return r end
  function utils.mapkv(f,l) local r={}; for k,v in pairs(l) do k,v=f(k,v) r[k]=v end; return r end
  function utils.size(t) local n=0; for _,_ in pairs(t) do n=n+1 end return n end 

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

  function utils.basicAuthorization(user,password) return "Basic "..utils.base64encode(user..":"..password) end
  function utils.base64encode(data)
    __assert_type(data,"string" )
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

end -- Utilities

--------------------- Fibaro functions --------------------------------------
do
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


end -- Fibaro functions

--------------------- Time functions ------------------------------------------
do
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

  local function midnight() local t = os.date("*t"); t.hour,t.min,t.sec = 0,0,0; return os.time(t) end
  fibaro.midnight = midnight

  function fibaro.between(start,stop,optTime)
    __assert_type(start,"string" )
    __assert_type(stop,"string" )
    start,stop,optTime=toSeconds(start),toSeconds(stop),optTime and toSeconds(optTime) or toSeconds(os.date("%H:%M"))
    stop = stop>=start and stop or stop+24*3600
    optTime = optTime>=start and optTime or optTime+24*3600
    return start <= optTime and optTime <= stop
  end

  local function hm2sec(hmstr)
    local offs,sun
    sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
    if sun and (sun == 'sunset' or sun == 'sunrise') then
      hmstr,offs = fibaro.getValue(1,sun.."Hour"), tonumber(offs) or 0
    end
    local sg,h,m,s = hmstr:match("^(%-?)(%d+):(%d+):?(%d*)")
    assertf(h and m,"Bad hm2sec string %s",hmstr)
    return (sg == '-' and -1 or 1)*(tonumber(h)*3600+tonumber(m)*60+(tonumber(s) or 0)+(tonumber(offs or 0))*60)
  end

-- toTime("10:00")     -> 10*3600+0*60 secs   
-- toTime("10:00:05")  -> 10*3600+0*60+5*1 secs
-- toTime("t/10:00")    -> (t)oday at 10:00. midnight+10*3600+0*60 secs
-- toTime("n/10:00")    -> (n)ext time. today at 10.00AM if called before (or at) 10.00AM else 10:00AM next day
-- toTime("+/10:00")    -> Plus time. os.time() + 10 hours
-- toTime("+/00:01:22") -> Plus time. os.time() + 1min and 22sec
-- toTime("sunset")     -> todays sunset in relative secs since midnight, E.g. sunset="05:10", =>toTime("05:10")
-- toTime("sunrise")    -> todays sunrise
-- toTime("sunset+10")  -> todays sunset + 10min. E.g. sunset="05:10", =>toTime("05:10")+10*60
-- toTime("sunrise-5")  -> todays sunrise - 5min
-- toTime("t/sunset+10")-> (t)oday at sunset in 'absolute' time. E.g. midnight+toTime("sunset+10")

  function toTime(time)
    if type(time) == 'number' then return time end
    local p = time:sub(1,2)
    if p == '+/' then return hm2sec(time:sub(3))+os.time()
    elseif p == 'n/' then
      local t1,t2 = midnight()+hm2sec(time:sub(3)),os.time()
      return t1 > t2 and t1 or t1+24*60*60
    elseif p == 't/' then return  hm2sec(time:sub(3))+midnight()
    else return hm2sec(time) end
  end

end -- Time functions

--------------------- Trace functions ------------------------------------------

--------------------- Debug functions -----------------------------------------
do
  local fformat
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
    local id = MID
    local idt = plugin and "deviceId" or "sceneId"
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
        deviceId = MID,
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
  fibaro._orgToString = old_tostring
  if hc3_emulator then
    function tostring(obj)
      if type(obj)=='table' and not hc3_emulator.getmetatable(obj) then
        if obj.__tostring then return obj.__tostring(obj) 
        elseif debugFlags.json then return json.encodeFast(obj) end
      end
      return old_tostring(obj)
    end
  else
    function tostring(obj)
      if type(obj)=='table' then
        if obj.__tostring then return obj.__tostring(obj) 
        elseif debugFlags.json then return json.encodeFast(obj) end
      end
      return old_tostring(obj)
    end
  end

  local htmlCodes={['\n']='<br>', [' ']='&nbsp;'}
  local function fix(str) return str:gsub("([\n%s])",function(c) return htmlCodes[c] or c end) end
  local function htmlTransform(str)
    local hit = false
    str = str:gsub("([^<]*)(<.->)([^<]*)",function(s1,s2,s3) hit=true
        return (s1~="" and fix(s1) or "")..s2..(s3~="" and fix(s3) or "") 
      end)
    return hit and str or fix(str)
  end

  function fformat(fmt,...)
    local args = {...}
    local stat,res = pcall(function() 
        if #args == 0 then return tostring(fmt) end
        for i,v in ipairs(args) do if type(v)=='table' then args[i]=tostring(v) end end
        return (debugFlags.html and not hc3_emulator) and htmlTransform(format(fmt,table.unpack(args))) or format(fmt,table.unpack(args))
      end)
    if not stat then error(res,4) else return res end
  end

  local function arr2str(...)
    local args,res = {...},{}
    for i=1,#args do if args[i]~=nil then res[#res+1]=tostring(args[i]) end end 
    return (debugFlags.html and not hc3_emulator) and htmlTransform(table.concat(res," ")) or table.concat(res," ")
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

end -- Debug functions

--------------------- Scene function  -----------------------------------------
do
  function fibaro.isSceneEnabled(sceneID) 
    __assert_type(sceneID,"number" )
    return (api.get("/scenes/"..sceneID) or { enabled=false }).enabled 
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


end -- Scene function

--------------------- Globals --------------------------------------------------
do
  function fibaro.getAllGlobalVariables() 
    return utils.map(function(v) return v.name end,api.get("/globalVariables")) 
  end

  function fibaro.createGlobalVariable(name,value,options)
    __assert_type(name,"string")
    if not fibaro.existGlobalVariable(name) then 
      value = tostring(value)
      local args = utils.copy(options or {})
      args.name,args.value=name,value
      return api.post("/globalVariables",args)
    end
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


end -- Globals

--------------------- Custom events --------------------------------------------
do
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


end -- Custom events

--------------------- Profiles -------------------------------------------------
do
  function fibaro.activeProfile(id)
    if id then
      if type(id)=='string' then id = fibaro.profileNameToId(id) end
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


end -- Profiles

--------------------- Alarm functions ------------------------------------------
do
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
  function fibaro.getAllPartitions() return filterPartitions(function() return true end) end

-- Return partitions that are armed
  function fibaro.getArmedPartitions() return filterPartitions(function(p) return p.armed end) end

-- Return partitions that are about to be armed
  function fibaro.getActivatedPartitions() return filterPartitions(function(p) return p.secondsToArm end) end

-- Return breached partitions
  function fibaro.getBreachedPartitions() return api.get("/alarms/v1/partitions/breached") or {} end

--If you want to list all devices that can be part of a alarm partition/zone you can do
  function fibaro.getAlarmDevices() return api.get("/alarms/v1/devices/") end

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

--[[ Ex. check what partitions have breached devices
for _,p in ipairs(getAllPartitions()) do
  local bd = getBreachedDevicesInPartition(p)
  if bd[1] then print("Partition "..p.." contains breached devices "..json.encode(bd)) end
end
--]]

end -- Alarm

--------------------- Weather --------------------------------------------------
do
  fibaro.weather = {}
  function fibaro.weather.temperature() return api.get("/weather").Temperature end
  function fibaro.weather.temperatureUnit() return api.get("/weather").TemperatureUnit end
  function fibaro.weather.humidity() return api.get("/weather").Humidity end
  function fibaro.weather.wind() return api.get("/weather").Wind end
  function fibaro.weather.weatherCondition() return api.get("/weather").WeatherCondition end
  function fibaro.weather.conditionCode() return api.get("/weather").ConditionCode end

end --Weather

--------------------- sourceTrigger & refreshStates ----------------------------
do
  fibaro.REFRESH_STATES_INTERVAL = 1000
  local sourceTriggerCallbacks,refreshCallbacks,refreshRef,pollRefresh={},{}
  local ENABLEDSOURCETRIGGERS,DISABLEDREFRESH={},{}
  local post,sourceTriggerTransformer,filter

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

  function fibaro.registerSourceTriggerCallback(callback)
    __assert_type(callback,"function")
    if member(callback,sourceTriggerCallbacks) then return end
    if #sourceTriggerCallbacks == 0 then
      fibaro.registerRefreshStatesCallback(sourceTriggerTransformer)
    end
    sourceTriggerCallbacks[#sourceTriggerCallbacks+1] = callback
  end

  function fibaro.unregisterSourceTriggerCallback(callback)
    __assert_type(callback,"function")
    if member(callback,sourceTriggerCallbacks) then remove(callback,sourceTriggerCallbacks) end
    if #sourceTriggerCallbacks == 0 then
      fibaro.unregisterRefreshStatesCallback(sourceTriggerTransformer) 
    end
  end

  function post(ev)
    if ENABLEDSOURCETRIGGERS[ev.type] then
      if #sourceTriggerCallbacks==0 then return end
      if debugFlags.sourceTrigger then fibaro.debugf("Incoming sourceTrigger:%s",ev) end
      ev._trigger=true
      for _,cb in ipairs(sourceTriggerCallbacks) do
        setTimeout(function() cb(ev) end,0) 
      end
    end
  end

  function sourceTriggerTransformer(e)
    local handler = EventTypes[e.type]
    if handler then handler(e.data)
    elseif handler==nil and fibaro._UNHANDLED_REFRESHSTATES then 
      fibaro.debugf(__TAG,"[Note] Unhandled refreshState/sourceTrigger:%s -- please report",e) 
    end
  end

  function fibaro.enableSourceTriggers(trigger)
    if type(trigger)~='table' then  trigger={trigger} end
    for _,t in  ipairs(trigger) do ENABLEDSOURCETRIGGERS[t]=true end
  end
  fibaro.enableSourceTriggers({"device","alarm","global-variable","custom-event","quickvar"})

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

  function filter(id,prop,new)
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

  fibaro._REFRESHSTATERATE = 1000
  local lastRefresh = 0
  net = net or { HTTPClient = function() end  }
  local http = net.HTTPClient()
  math.randomseed(os.time())
  local urlTail = "&lang=en&rand="..math.random(2000,4000).."&logs=false"
  function pollRefresh()
    local _,_ = http:request("http://127.0.0.1:11111/api/refreshStates?last=" .. lastRefresh..urlTail,{
        success=function(res)
          local states = res.status == 200 and json.decode(res.data)
          if states then
            lastRefresh=states.last
            if states.events and #states.events>0 then 
              for _,e in ipairs(states.events) do
                fibaro._postRefreshState(e)
              end
            end
          end 
          refreshRef = setTimeout(pollRefresh,fibaro.REFRESH_STATES_INTERVAL or 0)
        end,
        error=function(res) 
          fibaro.errorf(__TAG,"refreshStates:%s",res)
          refreshRef = setTimeout(pollRefresh,fibaro._REFRESHSTATERATE)
        end,
      })
  end

  function fibaro.registerRefreshStatesCallback(callback)
    __assert_type(callback,"function")
    if member(callback,refreshCallbacks) then return end
    refreshCallbacks[#refreshCallbacks] = callback
    if not refreshRef then refreshRef = setTimeout(pollRefresh,0) end
    if debugFlags._refreshStates then fibaro.debug(nil,"Polling for refreshStates") end
  end

  function fibaro.unregisterRefreshStatesCallback(callback)
    remove(callback,refreshCallbacks)
    if #refreshCallbacks == 0 then
      if refreshRef then clearTimeout(refreshRef); refreshRef = nil end
      if debugFlags._refreshStates then fibaro.debug(nil,"Stop polling for refreshStates") end
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
    if #refreshCallbacks>0 and not DISABLEDREFRESH[event.type] then
      for i=1,#refreshCallbacks do
        setTimeout(function() refreshCallbacks[i](event) end,0)
      end
    end
  end

  function fibaro.postGeofenceEvent(userId,locationId,geofenceAction)
    __assert_type(userId,"number")
    __assert_type(locationId,"number")
    __assert_type(geofenceAction,"string")
    return api.post("/events/publishEvent/GeofenceEvent",
      {
        deviceId = MID,
        userId	= userId,
        locationId	= locationId,
        geofenceAction = geofenceAction,
        timestamp = os.time()
      })
  end

  function fibaro.postCentralSceneEvent(keyId,keyAttribute)
    local data = {
      type =  "centralSceneEvent",
      source = MID,
      data = { keyAttribute = keyAttribute, keyId = keyId }
    }
    return api.post("/plugins/publishEvent", data)
  end
end -- sourceTrigger & refreshStates

--------------------- Net functions --------------------------------------------
do
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
end -- Net functions

--------------------- QA functions ---------------------------------------------
do
  function fibaro.restartQA(id)
    __assert_type(id,"number")
    return api.post("/plugins/restart",{deviceId=id or MID})
  end

  function fibaro.getQAVariable(id,name)
    __assert_type(id,"number")
    __assert_type(name,"string")
    local props = (api.get("/devices/"..(id or MID)) or {}).properties or {}
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
    local props = (api.get("/devices/"..(id or MID)) or {}).properties or {}
    local res = {}
    for _, v in ipairs(props.quickAppVariables or {}) do
      res[v.name]=v.value
    end
    return res
  end

  function fibaro.isQAEnabled(id)
    __assert_type(id,"number")
    local dev = api.get("/devices/"..(id or MID))
    return (dev or {}).enabled
  end

  function fibaro.enableQA(id,enable)
    __assert_type(id,"number")
    __assert_type(enable,"boolean")
    return api.post("/devices/"..(id or MID),{enabled=enable==true})
  end

  if QuickApp then

    local _init = QuickApp.__init
    local _onInit = nil
    local loadQA

    function QuickApp.__init(self,...) -- We hijack the __init methods so we can control users :onInit() method
      _onInit = self.onInit
      self.onInit = loadQA
      _init(self,...)
    end

    function loadQA(self)
      local dev = __fibaro_get_device(self.id)
      if not dev.enabled then  
        self:debug("QA ",self.name," disabled")
        return 
      end
      self.config = {}
      for _,v in ipairs(dev.properties.quickAppVariables or {}) do
        if v.value ~= "" then self.config[v.name] = v.value end
      end
      quickApp = self
      if _onInit then _onInit(self) end
    end

    function QuickApp:debug(...) fibaro.debug(nil,...) end
    function QuickApp:trace(...) fibaro.trace(nil,...) end
    function QuickApp:warning(...) fibaro.warning(nil,...) end
    function QuickApp:error(...) fibaro.error(nil,...) end
    function QuickApp:debugf(...) fibaro.debugf(nil,...) end
    function QuickApp:tracef(...) fibaro.tracef(nil,...) end
    function QuickApp:warningf(...) fibaro.warningf(nil,...) end
    function QuickApp:errorf(...) fibaro.errorf(nil,...) end
    function QuickApp:debug2(tl,...) fibaro.debug(tl,...) end
    function QuickApp:trace2(tl,...) fibaro.trace(tl,...) end
    function QuickApp:warning2(tl,...) fibaro.warning(tl,...) end
    function QuickApp:error2(tl,...) fibaro.error(tl,...) end
    function QuickApp:debugf2(tl,...) fibaro.debugf(tl,...) end
    function QuickApp:tracef2(tl,...) fibaro.tracef(tl,...) end
    function QuickApp:warningf2(tl,...) fibaro.warningf(tl,...) end
    function QuickApp:errorf2(tl,...) fibaro.errorf(tl,...) end

-- Like self:updateView but with formatting. Ex self:setView("label","text","Now %d days",days)
    function QuickApp:setView(elm,prop,fmt,...)
      local str = format(fmt,...)
      self:updateView(elm,prop,str)
    end

-- Get view element value. Ex. self:getView("mySlider","value")
    function QuickApp:getView(elm,prop)
      assert(type(elm)=='string' and type(prop)=='string',"Strings expected as arguments")
      local function find(s)
        if type(s) == 'table' then
          if s.name==elm then return s[prop]
          else for _,v in pairs(s) do local r = find(v) if r then return r end end end
        end
      end
      return find(api.get("/plugins/getView?id="..self.id)["$jason"].body.sections)
    end

-- Change name of QA. Note, if name is changed the QA will restart
    function QuickApp:setName(name)
      if self.name ~= name then api.put("/devices/"..self.id,{name=name}) end
      self.name = name
    end

-- Set log text under device icon - optional timeout to clear the message
    function QuickApp:setIconMessage(msg,timeout)
      if self._logTimer then clearTimeout(self._logTimer) self._logTimer=nil end
      self:updateProperty("log", tostring(msg))
      if timeout then 
        self._logTimer=setTimeout(function() self:updateProperty("log",""); self._logTimer=nil end,1000*timeout) 
      end
    end

-- Disable QA. Note, difficult to enable QA...
    function QuickApp:setEnabled(bool)
      local d = __fibaro_get_device(self.id)
      if d.enabled ~= bool then api.put("/devices/"..self.id,{enabled=bool}) end
    end

-- Hide/show QA. Note, if state is changed the QA will restart
    function QuickApp:setVisible(bool) 
      local d = __fibaro_get_device(self.id)
      if d.visible ~= bool then api.put("/devices/"..self.id,{visible=bool}) end
    end

    function QuickApp:post(...) return fibaro.post(...) end
    function QuickApp:event(...) return fibaro.event(...) end

    function fibaro.deleteFile(deviceId,file)
      local name = type(file)=='table' and file.name or file
      return api.delete("/quickApp/"..(deviceId or MID).."/files/"..name)
    end

    function fibaro.updateFile(deviceId,file,content)
      if type(file)=='string' then
        file = {isMain=false,type='lua',isOpen=false,name=file,content=""}
      end
      file.content = type(content)=='string' and content or file.content
      return api.put("/quickApp/"..(deviceId or MID).."/files/"..file.name,file) 
    end

    function fibaro.updateFiles(deviceId,list)
      if #list == 0 then return true end
      return api.put("/quickApp/"..(deviceId or MID).."/files",list) 
    end

    function fibaro.createFile(deviceId,file,content)
      if type(file)=='string' then
        file = {isMain=false,type='lua',isOpen=false,name=file,content=""}
      end
      file.content = type(content)=='string' and content or file.content
      return api.post("/quickApp/"..(deviceId or MID).."/files",file) 
    end

    function fibaro.getFile(deviceId,file)
      local name = type(file)=='table' and file.name or file
      return api.get("/quickApp/"..(deviceId or MID).."/files/"..name) 
    end

    function fibaro.getFiles(deviceId)
      local res,code = api.get("/quickApp/"..(deviceId or MID).."/files")
      return res or {},code
    end

    function fibaro.copyFileFromTo(fileName,deviceFrom,deviceTo)
      deviceTo = deviceTo or (deviceId or MID)
      local copyFile = fibaro.getFile(deviceFrom,fileName)
      assert(copyFile,"File doesn't exists")
      fibaro.addFileTo(copyFile.content,fileName,deviceTo)
    end

    function fibaro.addFileTo(fileContent,fileName,deviceId)
      deviceId = deviceId or MID
      local file = fibaro.getFile(deviceId,fileName)
      if not file then
        local stat,res = fibaro.createFile(deviceId,{   -- Create new file
            name=fileName,
            type="lua",
            isMain=false,
            isOpen=false,
            content=fileContent
          })
        if res == 200 then
          fibaro.debug(nil,"File '",fileName,"' added")
        else self:error("Error:",res) end
      elseif file.content ~= fileContent then
        local stat,res = fibaro.updateFile(deviceId,{   -- Update existing file
            name=file.name,
            type="lua",
            isMain=file.isMain,
            isOpen=file.isOpen,
            content=fileContent
          })
        if res == 200 then
          fibaro.debug(nil,"File '",fileName,"' updated")
        else fibaro.error(nil,"Error:",res) end
      else
        fibaro.debug(nil,"File '",fileName,"' not changed")
      end
    end

    function fibaro.getFQA(deviceId) return api.get("/quickApp/export/"..deviceId) end

    function fibaro.putFQA(content) -- Should be .fqa json
      if type(content)=='table' then content = json.encode(content) end
      return api.post("/quickApp/",content)
    end

-- Add interfaces to QA. Note, if interfaces are added the QA will restart
    local _addInterf = QuickApp.addInterfaces
    function QuickApp:addInterfaces(interfaces) 
      local d,map = __fibaro_get_device(self.id),{}
      for _,i in ipairs(d.interfaces or {}) do map[i]=true end
      for _,i in ipairs(interfaces or {}) do
        if not map[i] then
          _addInterf(self,interfaces)
          return
        end
      end
    end

    local _updateProperty = QuickApp.updateProperty
    function QuickApp:updateProperty(prop,value)
      local _props = self.properties
      if _props==nil or _props[prop] ~= nil then
        return _updateProperty(self,prop,value)
      elseif debugFlags.propWarn then self:warningf("Trying to update non-existing property - %s",prop) end
    end
  end

  function QuickApp:setChildIconPath(childId,path)
    api.put("/devices/"..childId,{properties={icon={path=path}}})
  end

--Ex. self:callChildren("method",1,2) will call MyClass:method(1,2) 
  function QuickApp:callChildren(method,...)
    for _,child in pairs(self.childDevices or {}) do 
      if child[method] then 
        local stat,res = pcall(child[method],child,...)  
        if not stat then self:debug(res) end
      end
    end
  end

  function QuickApp:removeAllChildren()
    for id,_ in pairs(self.childDevices or {}) do self:removeChildDevice(id) end
  end

  function QuickApp:numberOfChildren()
    local n = 0
    for _,_ in pairs(self.childDevices or {}) do n=n+1 end
    return n
  end

  function QuickApp:getChildVariable(child,varName) 
    for _,v in ipairs(child.properties.quickAppVariables or {}) do
      if v.name==varName then return v.value end
    end
    return ""
  end

  local function annotateClass(self,classObj)
    if not classObj then return end
    local stat,res = pcall(function() return classObj._annotated end) 
    if stat and res then return end
    --self:debug("Annotating class")
    for _,m in ipairs({
        "notify","setVisible","setEnabled","setIconMessage","setName","getView","updateProperty",
        "setView","debug","trace","error","warning","debugf","tracef","errorf","warningf"}) 
    do classObj[m] = self[m] end
    classObj.debugFlags = self.debugFlags
  end

  local function setCallbacks(obj,callbacks)
    if callbacks =="" then return end
    local cbs = {}
    for _,cb in ipairs(callbacks or {}) do
      cbs[cb.name]=cbs[cb.name] or {}
      cbs[cb.name][cb.eventType] = cb.callback
    end
    obj.uiCallbacks = cbs
  end

--[[
  QuickApp:createChild{
    className = "MyChildDevice",      -- class name of child object
    name = "MyName",                  -- Name of child device
    type = "com.fibaro.binarySwitch", -- Type of child device
    properties = {},                  -- Initial properties
    interfaces = {},                  -- Initial interfaces
  }
--]]
  function QuickApp:createChild(args)
    local className = args.className or "QuickAppChild"
    annotateClass(self,_G[className])
    local name = args.name or "Child"
    local tpe = args.type or "com.fibaro.binarySensor"
    local properties = args.properties or {}
    local interfaces = args.interfaces or {}
    properties.quickAppVariables = properties.quickAppVariables or {}
    local function addVar(n,v) table.insert(properties.quickAppVariables,1,{name=n,value=v}) end
    for n,v in pairs(args.quickVars or {}) do addVar(n,v) end
    local callbacks = properties.uiCallbacks
    if  callbacks then 
      local function copy(t) local r={}; for k,v in pairs(t) do r[k]=v end return r end
      callbacks = copy(callbacks)
      addVar('_callbacks',callbacks)
    end
    -- Save class name so we know when we load it next time
    addVar('className',className) -- Add first
    local child = self:createChildDevice({
        name = name,
        type=tpe,
        initialProperties = properties,
        initialInterfaces = interfaces
      },
      _G[className] -- Fetch class constructor from class name
    )
    if callbacks then setCallbacks(child,callbacks) end
    return child
  end

-- Loads all children, called automatically at startup
  function QuickApp:loadChildren()
    local cdevs,n = api.get("/devices?parentId="..self.id) or {},0 -- Pick up all my children
    function self:initChildDevices() end -- Null function, else Fibaro calls it after onInit()...
    for _,child in ipairs(cdevs or {}) do
      if not self.childDevices[child.id] then
        local className = self:getChildVariable(child,"className")
        local callbacks = self:getChildVariable(child,"_callbacks")
        annotateClass(self,_G[className])
        local childObject = _G[className] and _G[className](child) or QuickAppChild(child)
        self.childDevices[child.id]=childObject
        childObject.parent = self
        setCallbacks(childObject,callbacks)
      end
      n=n+1
    end
    return n
  end

  local orgRemoveChildDevice = QuickApp.removeChildDevice
  local childRemovedHook
  function QuickApp:removeChildDevice(id)
    if childRemovedHook then
      pcall(childRemovedHook,id)
    end
    return orgRemoveChildDevice(self,id)
  end
  function QuickApp:setChildRemovedHook(fun) childRemovedHook=fun end

-- UI handler to pass button clicks to children
  function QuickApp:UIHandler(event)
    local obj = self
    if self.id ~= event.deviceId then obj = (self.childDevices or {})[event.deviceId] end
    if not obj then return end
    local elm,etyp = event.elementName, event.eventType
    local cb = obj.uiCallbacks or {}
    if obj[elm] then return obj:callAction(elm, event) end
    if cb[elm] and cb[elm][etyp] and obj[cb[elm][etyp]] then return obj:callAction(cb[elm][etyp], event) end
    if obj[elm.."Clicked"] then return obj:callAction(elm.."Clicked", event) end
    self:warning("UI callback for element:", elm, " not found.")
  end

end -- QA

--------------------- Misc -----------------------------------------------------
do 
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
      local function timer2str(t)
        return format("[Timer:%d%s %s]",t.n,t.log or "",os.date('%T %D',t.expires or 0))
      end
      local N = 0
      local function isTimer(timer) return type(timer)=='table' and timer['%TIMER%'] end
      local function makeTimer(ref,log,exp) N=N+1 return {['%TIMER%']=(ref or 0),n=N,log=log and " ("..log..")",expires=exp or 0,__tostring=timer2str} end
      local function updateTimer(timer,ref) timer['%TIMER%']=ref end
      local function getTimer(timer) return timer['%TIMER%'] end

      clearTimeout,oldClearTimout=function(ref)
        if isTimer(ref) then ref=getTimer(ref)
          oldClearTimout(ref)
        end
      end,clearTimeout

      setTimeout,oldSetTimout=function(f,ms,log)
        local ref,maxt=makeTimer(nil,log,math.floor(os.time()+ms/1000+0.5)),2147483648-1
        local fun = function() -- wrap function to get error messages
          if debugFlags.lateTimer then
            local d = os.time() - ref.expires
            if d > debugFlags.lateTimer then fibaro.warningf(nil,"Late timer (%ds):%s",d,ref) end
          end
          local stat,res = pcall(f)
          if not stat then 
            error(res,2)
          end
        end
        if ms > maxt then
          updateTimer(ref,oldSetTimout(function() updateTimer(ref,getTimer(setTimeout(fun,ms-maxt))) end,maxt))
        else updateTimer(ref,oldSetTimout(fun,math.floor(ms+0.5))) end
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
      local function printf(tab,fmt,...) res[#res+1] = string.rep(' ',tab)..format(fmt,...) end
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

  function fibaro.trueFor(time,test,action,delay)
    delay = delay or 1000
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

end -- Misc

--------------------- Events --------------------------------------------------
do
  local inited,initEvents,_RECIEVE_EVENT

  function fibaro.postRemote(id,ev) if not inited then initEvents() end; return fibaro.postRemote(id,ev) end
  function fibaro.post(ev,t) if not inited then initEvents() end; return fibaro.post(ev,t) end
  function fibaro.cancel(ref) if not inited then initEvents() end; return fibaro.cancel(ref) end
  function fibaro.event(ev,fun,doc) if not inited then initEvents() end; return fibaro.event(ev,fun,doc) end
  function fibaro.removeEvent(pattern,fun) if not inited then initEvents() end; return fibaro.removeEvent(pattern,fun) end
  function fibaro.HTTPEvent(args) if not inited then initEvents() end; return fibaro.HTTPEvent(args) end
  function QuickApp:RECIEVE_EVENT(ev) if not inited then initEvents() end; return _RECIEVE_EVENT(self,ev) end

  function initEvents()
    local function DEBUG(...) if debugFlags.event then fibaro.debugf(nil,...) end end
    DEBUG("Setting up events")
    inited = true 

    local em,handlers = { sections = {}, stats={tried=0,matched=0}},{}
    em.BREAK, em.TIMER, em.RULE = '%%BREAK%%', '%%TIMER%%', '%%RULE%%'
    local handleEvent,invokeHandler,post
    local function isEvent(e) return type(e)=='table' and e.type end
    local function isRule(e) return type(e)=='table' and e[em.RULE] end

-- This can be used to "post" an event into this QA... Ex. fibaro.call(ID,'RECIEVE_EVENT',{type='myEvent'})
    function _RECIEVE_EVENT(self,ev)
      assert(isEvent(ev),"Bad argument to remote event")
      local time = ev.ev._time
      ev,ev.ev._time = ev.ev,nil
      if time and time+5 < os.time() then fibaro.warningf(nil,"Slow events %s, %ss",ev,os.time()-time) end
      fibaro.post(ev)
    end

    function fibaro.postRemote(id,ev)
      assert(tonumber(id) and isEvent(ev),"Bad argument to postRemote")
      ev._from,ev._time = MID,os.time()
      fibaro.call(id,'RECIEVE_EVENT',{type='EVENT',ev=ev}) -- We need this as the system converts "99" to 99 and other "helpful" conversions
    end

    function fibaro.post(ev,t)
      local now = os.time()
      t = type(t)=='string' and toTime(t) or t or 0
      if t < 0 then return elseif t < now then t = t+now end
      if debugFlags.post and not ev._sh then fibaro.tracef(nil,"Posting %s at %s",ev,os.date("%c",t)) end
      if type(ev) == 'function' then
        return setTimeout(ev,1000*(t-now))
      else
        return setTimeout(function() handleEvent(ev) end,1000*(t-now))
      end
    end

-- Cancel post in the future
    function fibaro.cancel(ref) clearTimeout(ref) end

    local function transform(obj,tf)
      if type(obj) == 'table' then
        local res = {} for l,v in pairs(obj) do res[l] = transform(v,tf) end 
        return res
      else return tf(obj) end
    end

    local function coerce(x,y) local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end end
    local constraints = {}
    constraints['=='] = function(val) return function(x) x,val=coerce(x,val) return x == val end end
    constraints['<>'] = function(val) return function(x) return tostring(x):match(val) end end
    constraints['>='] = function(val) return function(x) x,val=coerce(x,val) return x >= val end end
    constraints['<='] = function(val) return function(x) x,val=coerce(x,val) return x <= val end end
    constraints['>'] = function(val) return function(x) x,val=coerce(x,val) return x > val end end
    constraints['<'] = function(val) return function(x) x,val=coerce(x,val) return x < val end end
    constraints['~='] = function(val) return function(x) x,val=coerce(x,val) return x ~= val end end
    constraints[''] = function(_) return function(x) return x ~= nil end end

    local function compilePattern2(pattern)
      if type(pattern) == 'table' then
        if pattern._var_ then return end
        for k,v in pairs(pattern) do
          if type(v) == 'string' and v:sub(1,1) == '$' then
            local var,op,val = v:match("$([%w_]*)([<>=~]*)(.*)")
            var = var =="" and "_" or var
            local c = constraints[op](tonumber(val) or val)
            pattern[k] = {_var_=var, _constr=c, _str=v}
          else compilePattern2(v) end
        end
      end
      return pattern
    end

    local function compilePattern(pattern)
      pattern = compilePattern2(copy(pattern))
      if pattern.type and type(pattern.id)=='table' and not pattern.id._constr then
        local m = {}; for _,id in ipairs(pattern.id) do m[id]=true end
        pattern.id = {_var_='_', _constr=function(val) return m[val] end, _str=pattern.id}
      end
      return pattern
    end
    em.compilePattern = compilePattern

    local function match(pattern, expr)
      local matches = {}
      local function unify(pattern,expr)
        if pattern == expr then return true
        elseif type(pattern) == 'table' then
          if pattern._var_ then
            local var, constr = pattern._var_, pattern._constr
            if var == '_' then return constr(expr)
            elseif matches[var] then return constr(expr) and unify(matches[var],expr) -- Hmm, equal?
            else matches[var] = expr return constr(expr) end
          end
          if type(expr) ~= "table" then return false end
          for k,v in pairs(pattern) do if not unify(v,expr[k]) then return false end end
          return true
        else return false end
      end
      return unify(pattern,expr) and matches or false
    end
    em.match = match

    function invokeHandler(env)
      local t = os.time()
      env.last,env.rule.time = t-(env.rule.time or 0),t
      local status, res = pcall(env.rule.action,env) -- call the associated action
      if not status then
        fibaro.errorf(nil,"in %s: %s",env.rule.doc,res)
        env.rule._disabled = true -- disable rule to not generate more errors
      else return res end
    end

    local toHash,fromHash={},{}
    fromHash['device'] = function(e) return {"device"..e.id..e.property,"device"..e.id,"device"..e.property,"device"} end
    fromHash['global-variable'] = function(e) return {'global-variable'..e.name,'global-variable'} end
    fromHash['quickvar'] = function(e) return {"quickvar"..e.id..e.name,"quickvar"..e.id,"quickvar"..e.name,"quickvar"} end
    fromHash['profile'] = function(e) return {'profile'..e.property,'profile'} end
    fromHash['weather'] = function(e) return {'weather'..e.property,'weather'} end
    fromHash['custom-event'] = function(e) return {'custom-event'..e.name,'custom-event'} end
    fromHash['deviceEvent'] = function(e) return {"deviceEvent"..e.id..e.value,"deviceEvent"..e.id,"deviceEvent"..e.value,"deviceEvent"} end
    fromHash['sceneEvent'] = function(e) return {"sceneEvent"..e.id..e.value,"sceneEvent"..e.id,"sceneEvent"..e.value,"sceneEvent"} end
    toHash['device'] = function(e) return "device"..(e.id or "")..(e.property or "") end   
    toHash['global-variable'] = function(e) return 'global-variable'..(e.name or "") end
    toHash['quickvar'] = function(e) return 'quickvar'..(e.id or "")..(e.name or "") end
    toHash['profile'] = function(e) return 'profile'..(e.property or "") end
    toHash['weather'] = function(e) return 'weather'..(e.property or "") end
    toHash['custom-event'] = function(e) return 'custom-event'..(e.name or "") end
    toHash['deviceEvent'] = function(e) return 'deviceEvent'..(e.id or "")..(e.value or "") end
    toHash['sceneEvent'] = function(e) return 'sceneEvent'..(e.id or "")..(e.value or "") end

    if not table.maxn then 
      function table.maxn(tbl)local c=0; for _ in pairs(tbl) do c=c+1 end return c end
    end

    local function rule2str(rule) return rule.doc end
    local function comboToStr(r)
      local res = { r.src }
      for _,s in ipairs(r.subs) do res[#res+1]="   "..tostring(s) end
      return table.concat(res,"\n")
    end
    function map(f,l,s) s = s or 1; local r={} for i=s,table.maxn(l) do r[#r+1] = f(l[i]) end return r end
    function mapF(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) end return e end

    local function comboEvent(e,action,rl,doc)
      local rm = {[em.RULE]=e, action=action, doc=doc, subs=rl}
      rm.enable = function() mapF(function(e) e.enable() end,rl) return rm end
      rm.disable = function() mapF(function(e) e.disable() end,rl) return rm end
      rm.start = function(event) invokeHandler({rule=rm,event=event}) return rm end
      rm.__tostring = comboToStr
      return rm
    end

    function fibaro.event(pattern,fun,doc)
      doc = doc or format("Event(%s) => ..",json.encode(pattern))
      if type(pattern) == 'table' and pattern[1] then 
        return comboEvent(pattern,fun,map(function(es) return fibaro.event(es,fun) end,pattern),doc) 
      end
      if isEvent(pattern) then
        if pattern.type=='device' and pattern.id and type(pattern.id)=='table' then
          return fibaro.event(map(function(id) local e1 = copy(pattern); e1.id=id return e1 end,pattern.id),fun,doc)
        end
      else error("Bad event pattern, needs .type field") end
      assert(type(fun)=='function',"Second argument must be Lua function")
      local cpattern = compilePattern(pattern)
      local hashKey = toHash[pattern.type] and toHash[pattern.type](pattern) or pattern.type
      handlers[hashKey] = handlers[hashKey] or {}
      local rules = handlers[hashKey]
      local rule,fn = {[em.RULE]=cpattern, event=pattern, action=fun, doc=doc}, true
      for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
        if equal(cpattern,rs[1].event) then 
          rs[#rs+1] = rule
          fn = false break 
        end
      end
      if fn then rules[#rules+1] = {rule} end
      rule.enable = function() rule._disabled = nil return rule end
      rule.disable = function() rule._disabled = true return rule end
      rule.start = function(event) invokeHandler({rule=rule, event=event, p={}}) return rule end
      rule.__tostring = rule2str
      if em.SECTION then
        local s = em.sections[em.SECTION] or {}
        s[#s+1] = rule
        em.sections[em.SECTION] = s
      end
      return rule
    end

    function fibaro.removeEvent(pattern,fun)
      local hashKey = toHash[pattern.type] and toHash[pattern.type](pattern) or pattern.type
      local rules,i,j= handlers[hashKey] or {},1,1
      while j <= #rules do
        local rs = rules[j]
        while i <= #rs do
          if rs[i].action==fun then
            table.remove(rs,i)
          else i=i+i end
        end
        if #rs==0 then table.remove(rules,j) else j=j+1 end
      end
    end

    function handleEvent(ev)
      local hasKeys = fromHash[ev.type] and fromHash[ev.type](ev) or {ev.type}
      for _,hashKey in ipairs(hasKeys) do
        for _,rules in ipairs(handlers[hashKey] or {}) do -- Check all rules of 'type'
          local i,m=1,nil
          em.stats.tried=em.stats.tried+1
          for i=1,#rules do
            if not rules[i]._disabled then    -- find first enabled rule, among rules with same head
              m = match(rules[i][em.RULE],ev) -- and match against that rule
              break
            end
          end
          if m then                           -- we have a match
            for i=i,#rules do                 -- executes all rules with same head
              local rule=rules[i]
              if not rule._disabled then 
                em.stats.matched=em.stats.matched+1
                if invokeHandler({event = ev, p=m, rule=rule}) == em.BREAK then return end
              end
            end
          end
        end
      end
    end

    local function handlerEnable(t,handle)
      if type(handle) == 'string' then utils.mapf(em[t],em.sections[handle] or {})
      elseif isRule(handle) then handle[t]()
      elseif type(handle) == 'table' then utils.mapf(em[t],handle) 
      else error('Not an event handler') end
      return true
    end

    function em.enable(handle,opt)
      if type(handle)=='string' and opt then 
        for s,e in pairs(em.sections or {}) do 
          if s ~= handle then handlerEnable('disable',e) end
        end
      end
      return handlerEnable('enable',handle) 
    end
    function em.disable(handle) return handlerEnable('disable',handle) end

--[[
  Event.http{url="foo",tag="55",
    headers={},
    timeout=60,
    basicAuthorization = {user="admin",password="admin"}
    checkCertificate=0,
    method="GET"}
--]]

    function fibaro.HTTPEvent(args)
      local options,url = {},args.url
      options.headers = args.headers or {}
      options.timeout = args.timeout
      options.method = args.method or "GET"
      options.data = args.data or options.data
      options.checkCertificate=options.checkCertificate
      if args.basicAuthorization then 
        options.headers['Authorization'] = 
        utils.basicAuthorization(args.basicAuthorization.user,args.basicAuthorization.password)
      end
      if args.accept then options.headers['Accept'] = args.accept end
      net.HTTPClient():request(url,{
          options = options,
          success=function(resp)
            post({type='HTTPEvent',status=resp.status,data=resp.data,headers=resp.headers,tag=args.tag})
          end,
          error=function(resp)
            post({type='HTTPEvent',result=resp,tag=args.tag})
          end
        })
    end

    fibaro.em = em
    fibaro.registerSourceTriggerCallback(handleEvent)

  end -- initEvents

end -- Events

--------------------- PubSub ---------------------------------------------------
do
  local SUB_VAR = "TPUBSUB"
  local idSubs = {}
  local function DEBUG(...) if debugFlags.pubsub then fibaro.debugf(nil,...) end end
  local inited,initPubSub,match,compile

  function fibaro.publish(event)
    if not inited then initPubSub() end
    assert(type(event)=='table' and event.type,"Not an event")
    local subs = idSubs[event.type] or {}
    for _,e in ipairs(subs) do
      if match(event,e.pattern) then
        for id,_ in pairs(e.ids) do 
          DEBUG("Sending sub QA:%s",id)
          fibaro.call(id,"SUBSCRIPTION",event)
        end
      end
    end
  end

  if QuickApp then -- only subscribe if we are an QuickApp. Scenes can publish
    function fibaro.subscribe(events)
      if not inited then initPubSub() end
      if not events[1] then events = {events} end
      local subs = self:getVariable(SUB_VAR)
      if subs == "" then subs = {} end
      for _,e in ipairs(events) do
        assert(type(e)=='table' and e.type,"Not an event")
        if not member(e,subs) then subs[#subs+1]=e end
      end
      DEBUG("Setting subscription")
      self:setVariable(SUB_VAR,subs)
    end
  end

--  idSubs = {
--    <type> = { { ids = {... }, event=..., pattern = ... }, ... }
--  }

  function initPubSub()
    DEBUG("Setting up pub/sub")
    inited = true

    match = fibaro.em.match
    compile = fibaro.em.compilePattern

    function self:SUBSCRIPTION(e)
      self:post(e)
    end

    local function updateSubscriber(id,events)
      if not idSubs[id] then DEBUG("New subscriber, QA:%s",id) end
      for _,ev in ipairs(events) do
        local subs = idSubs[ev.type] or {}
        for _,s in ipairs(subs) do s.ids[id]=nil end
      end
      for _,ev in ipairs(events) do
        local subs = idSubs[ev.type]
        if subs == nil then
          subs = {}
          idSubs[ev.type]=subs
        end
        for _,e in ipairs(subs) do
          if equal(ev,e.event) then
            e.ids[id]=true
            goto nxt
          end
        end
        subs[#subs+1] = { ids={[id]=true}, event=copy(ev), pattern=compile(ev) }
        ::nxt::
      end
    end

    local function checkVars(id,vars)
      for _,var in ipairs(vars or {}) do 
        if var.name==SUB_VAR then return updateSubscriber(id,var.value) end
      end
    end

-- At startup, check all QAs for subscriptions
    for _,d in ipairs(api.get("/devices?interface=quickApp") or {}) do
      checkVars(d.id,d.properties.quickAppVariables)
    end

    fibaro.event({type='quickvar',name=SUB_VAR},            -- If some QA changes subscription
      function(env) 
        local id = env.event.id
        DEBUG("QA:%s updated quickvar sub",id)
        updateSubscriber(id,env.event.value)       -- update
      end) 

    fibaro.event({type='deviceEvent',value='removed'},      -- If some QA is removed
      function(env) 
        local id = env.event.id
        if id ~= self.id then
          DEBUG("QA:%s removed",id)
          updateSubscriber(env.event.id,{})               -- update
        end
      end)

    fibaro.event({
        {type='deviceEvent',value='created'},              -- If some QA is added or modified
        {type='deviceEvent',value='modified'}
      },
      function(env)                                             -- update
        local id = env.event.id
        if id ~= self.id then
          DEBUG("QA:%s created/modified",id)
          checkVars(id,api.get("/devices/"..id).properties.quickAppVariables)
        end
      end)
  end

end -- PubSub

--------------------- HTTP stuff ----------------------------------------------
-- How can we make it easier?
----------------- Auto update stuff ---------------------------------------------
do
  fibaro._URL_UPDATE_BASE = "https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/"
  fibaro._UPDATE_MANIFEST = "VERSION4.json"
  fibaro._FIBAROEXTRA_NAME = "fibaroExtra.lua"

  function fibaro.updateFibaroExtra(fname)
    fname = fname or fibaro._FIBAROEXTRA_NAME or "fibaroExtra.lua"
    local function fetch(url,cont)
      --fibaro.debug(__TAG,"Fetching ",url)
      net.HTTPClient():request(url,{
          options = {method = 'GET', checkCertificate = false, timeout=20000},
          success = function(res) 
            if res.status == 200 then cont(res.data)
            else fibaro.error(__TAG,"Error ",res.status," fetching ",url) end
          end,
          error  = function(res) 
            fibaro.error(__TAG,"Error ",res," fetching ",url)
          end
        })
    end
    local base = fibaro._URL_UPDATE_BASE or "https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/"
    local manifest = fibaro._UPDATE_MANIFEST or "VERSION4.json"
    fetch(base..manifest,
      function(manifest)
        manifest = json.decode(manifest)
        if fibaro.FIBARO_EXTRA == nil or manifest[fname] > fibaro.FIBARO_EXTRA then
          fibaro.debug(__TAG,"New version of ",fname)
          fetch(fibaro._URL_UPDATE_BASE..fname,
            function(code)
              local name=fname:match("(.*)%.[Ll][Uu][Aa]") or "library"
              local f = {isMain=false,type='lua',isOpen=false,name=name,content=code}
              if api.get("/quickApp/"..plugin.mainDeviceId.."/files/"..name) then
                fibaro.debug(__TAG,"Updating ",name)
                local _,res = api.put("/quickApp/"..plugin.mainDeviceId.."/files/"..name,f)
                if res ~= 200 then fibaro.error(___TAG,"Updating ",name," - ",res) end
              else
                fibaro.debug(__TAG,"Installing ",name)
                local _,res = api.put("/quickApp/"..plugin.mainDeviceId.."/files",f)
                if res ~= 200 then fibaro.error(__TAG,"Installing ",name," - ",res) end
              end
            end)
        end
      end)
  end

  function fibaro.installFibaroExtra()
    local name = "fibaroExtra"
    if fibaro.FIBARO_EXTRA then return end
    local url = "https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/"..name..".lua"
    net.HTTPClient():request(url,{
        options = {method = 'GET', checkCertificate = false, timeout=20000},
        success = function(res) 
          if res.status == 200 then 
            local f = {isMain=false,type='lua',isOpen=false,name=name,content=res.data}
            fibaro.debug(__TAG,"Installing ",name)
            local _,res = api.post("/quickApp/"..plugin.mainDeviceId.."/files",f)
            if res ~= 200 then fibaro.error(__TAG,"Installing ",name," - ",res) end              
          else fibaro.error(__TAG,"Error ",res.status," fetching ",url) end
        end,
        error  = function(res) 
          fibaro.error(__TAG,"Error ",res," fetching ",url)
        end
      })
  end

--[[ Mini installer
function fibaro.installFibaroExtra()local a="fibaroExtra"if fibaro.FIBARO_EXTRA then return end;local b="https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/"..a..".lua"net.HTTPClient():request(b,{options={method='GET',checkCertificate=false,timeout=20000},success=function(c)if c.status==200 then local d={isMain=false,type='lua',isOpen=false,name=a,content=c.data}fibaro.debug(__TAG,"Installing ",a)local e,c=api.post("/quickApp/"..plugin.mainDeviceId.."/files",d)if c~=200 then fibaro.error(__TAG,"Installing ",a," - ",c)end else fibaro.error(__TAG,"Error ",c.status," fetching ",b)end end,error=function(c)fibaro.error(__TAG,"Error ",c," fetching ",b)end})end
--]]
--[[
local fileList = {
  {
    file = "main"
  },
  {
    file = "fibaroExtra", 
    url="https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/fibaroExtra.lua",
    manifest="https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/VERSION4.json"
  },
}
checkForUpdate(fileList)
--]]

end -- Auto update