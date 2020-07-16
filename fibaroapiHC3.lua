--[[
FibaroAPI HC3 SDK
Copyright (c) 2020 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Contributions & bugfixes:
-  @petergebruers, forum.fibaro.com
-  @tinman, forum.fibaro.com

Sources:
json        -- Copyright (c) 2019 rxi
persistence -- Copyright (c) 2010 Gerhard Roethlin
--]]

local FIBAROAPIHC3_VERSION = "0.100"

--[[
  Best way is to conditionally include this file at the top of your lua file
  if dofile and not hc3_emulator then
    hc3_emulator = {
     quickVars = {["Hue_User"]="$CREDS.Hue_user",["Hue_IP"]=$CREDS.Hue_IP}
    }
    dofile("fibaroapiHC3.lua")
  end
  We load another file, credentials.lua, where we define lua globals like hc3_emulator.credentials etc.
  --hc3_emulator.credentials = { ip = <IP>, user = <username>, pwd = <password>}
  This way the credentials are not visible in your code and you will not accidently upload them :-)
  You can also predefine quickvars that are accessible with self:getVariable() when your code starts up
  quickVar names starting with '$CREDS.' will be replaced with values from hc3_emulator.credentials.
--]]

--[[
fibaro.debug(type,str) 
fibaro.warning(type,str) 
fibaro.trace(type,str) 
fibaro.error(type,str)

fibaro.call(deviceID, actionName, ...) 
fibaro.getType(deviceID) 
fibaro.getValue(deviceID, propertyName)
fibaro.getName(deviceID) 
fibaro.get(deviceID,propertyName) 
fibaro.getGlobalVariable(varName)
fibaro.setGlobalVariable(varName ,value) 
fibaro.getRoomName(roomID)
fibaro.getRoomID(deviceID)
fibaro.getRoomNameByDeviceID(deviceID) 
fibaro.getSectionID(deviceID)
fibaro.getIds(devices)
fibaro.getAllDeviceIds()
fibaro.getDevicesID(filter)
fibaro.scene(action, sceneIDs)
fibaro.profile(profile_id, action)
fibaro.callGroupAction(action,args)
fibaro.alert(alert_type, user_ids, notification_content) 
fibaro.alarm(partition_id, action)
fibaro.setTimeout(ms, func)
fibaro.emitCustomEvent(name)
fibaro.wakeUpDeadDevice
fibaro.sleep(ms) -- simple busy wait...

net.HTTPClient()
net.TCPSocket()
api.get(call) 
api.put(call <, data>) 
api.post(call <, data>)
api.delete(call <, data>)

setTimeout(func, ms)
clearTimeout(ref)
setInterval(func, ms)
clearInterval(ref)

plugin.mainDeviceId

class QuickAppBase
class QuickApp
class QuickAppChild
QuickApp:onInit() -- called at startup if defined
QuickApp - self:setVariable(name,value) 
QuickApp - self:getVariable(name)
QuickApp - self:debug(...)
QuickApp - self:trace(...)
QuickApp - self:warning(...)
QuickApp - self:error(...)
QuickApp - self:updateView(elm,type,value)
QuickApp - self:updateProperty()
QuickApp - self:createChildDevice(props,device)
QuickApp - self:initChildDevices(table)
QuickApp - self:removeChildDevice(id)

sourceTrigger - scene trigger
Scene events:
  {type='device', id=<number>, property=<string>, value=<value>}
  {type='global-variable', property=<string>, value=<value>}
  {type='date', property="cron", value={ <time> }}
  {type='date', property="sunset", value={ <time> }}
  {type='date', property="sunrise", value={ <time> }}
  {type='manual', property='execute'}
  {type='custom-event', name=<string>}
  {type='device' property='centralSceneEvent', id=<number>, value={keyId=<number>, keyAttribute=<string>}}

json.encode(expr)
json.decode(string)

hc3_emulator.start{                   -- start QuickApp/Scene
              id=<QuickApp ID>,       -- default 999
              poll=<poll interval>,   -- default false
              type=<type>,            -- default "com.fibaro.binarySwitch"
              speed=<speedtime>,      -- default false
              proxy=<boolean>         -- default false
              UI=<UI table>,          -- default {}
              quickVars=<table>,      -- default {}
              } 
hc3_emulator.createQuickApp{          -- creates and deploys QuickApp on HC3
              name=<string>,            
              type=<string>,
              code=<string>,
              UI=<table>,
              quickVars=<table>,
              dryrun=<boolean>
              } 
hc3_emulator.createProxy(<name>,<type>,<UI>,<quickVars>)       -- create QuickApp proxy on HC3 (usually called with 
hc3_emulator.post(ev,t)                                        -- post event/sourceTrigger 
--]]

local https  = require ("ssl.https") 
local http   = require("socket.http")
local socket = require("socket")
local ltn12  = require("ltn12")

local _debugFlags = {fcall=true, fget=true, post=true, trigger=true, timers=nil, refreshLoop=false, creation=true, mqtt=true} 
local function merge(t1,t2)
  if type(t1)=='table' and type(t2)=='table' then for k,v in pairs(t2) do if not t1[k] then t1[k]=v else merge(t1[k],v) end end end
  return t1
end

local Util,Timer,QA,Scene,Web,Trigger,Offline,DB,Files   -- local modules
fibaro,json,plugin,quickApp = {},{},nil                  -- global exports
QuickApp,QuickAppBase,QuickAppChild = nil,nil,nil        -- global exports

local function DEF(x,y) if x==nil then return y else return x end end
hc3_emulator = hc3_emulator or {}
hc3_emulator.version           = FIBAROAPIHC3_VERSION
hc3_emulator.credentialsFile   = hc3_emulator.credentialsFile or "credentials.lua" 
hc3_emulator.HC3dir            = hc3_emulator.HC3dir or "HC3files" 
hc3_emulator.backDirFmt        = "%m-%d-%Y %H.%M.%S"
hc3_emulator.conditions        = false
hc3_emulator.actions           = false
hc3_emulator.offline           = DEF(hc3_emulator.offline,false)
hc3_emulator.emulated          = true 
hc3_emulator.debug             = merge(_debugFlags,hc3_emulator.debug  or {})
hc3_emulator.runSceneAtStart   = false
hc3_emulator.webPort           = hc3_emulator.webPort or 6872
hc3_emulator.quickVars         = hc3_emulator.quickVars or {}
hc3_emulator.colorDebug        = DEF(hc3_emulator.colorDebug,true)
hc3_emulator.supressTrigger = {["PluginChangedViewEvent"] = true} -- Ignore noisy triggers...

local cr = loadfile(hc3_emulator.credentialsFile);
if cr then hc3_emulator.credentials = merge(hc3_emulator.credentials or {},cr() or {}) end
pcall(function() require('mobdebug').coro() end) -- Load mobdebug if available to debug coroutines...

local ostime,osclock,osdate,tostring = os.time,os.clock,os.date,tostring
local _timeAdjust = 0
local LOG,Log,Debug,assert,assertf
local module,commandLines = {},{}
local HC3_handleEvent = nil        -- Event hook...
local typeHierarchy = nil
local format = string.format
local onAction,onUIEvent,_quickApp
local QuickApp_devices,QuickAppChildren = {},{}

-------------- Fibaro API functions ------------------
function module.FibaroAPI()
  fibaro.version = "1.0.0"
  local cache,safeDecode = Trigger.cache,Util.safeDecode

  local function __convertToString(value) 
    if  type(value) == 'boolean' then 
      return value and '1' or '0'
    elseif type (value)  ==  'number' then 
      return  tostring(value) 
    elseif type(value) == 'table' then
      return json.encode(value) 
    end
    return value
  end

  function assert(value,errmsg) if not value then error(errmsg,3) end end
  function assertf(value,errmsg,...) 
    if not value then 
      local args = {...}
      if #args==0 then error(errmsg,3) else error(format(errmsg,...),3) end
    end 
  end
  function __assert_type(value,typeOfValue ) 
    if type(value) ~= typeOfValue then  -- Wrong parameter type, string required. Provided param 'nil' is type of nil
      error(format("Wrong parameter type, %s required. Provided param '%s' is type of %s",
          typeOfValue,tostring(value),type(value)),
        3)
    end 
  end
  function __fibaro_get_device(deviceID) __assert_type(deviceID,"number") 
    if _quickApp.id == deviceID then
      return _quickApp
    end
    return api.get("/devices/"..deviceID) 
  end
  function __fibaro_get_room (roomID) __assert_type(roomID,"number") return api.get("/rooms/"..roomID) end
  function __fibaro_get_scene(sceneID) __assert_type(sceneID,"number") return api.get("/scenes/"..sceneID) end
  function __fibaro_get_global_variable(varName) __assert_type(varName ,"string") 
    local c = cache.read('globals',varName) or api.get("/globalVariables/"..varName) 
    cache.write('globals',varName,c)
    return c
  end
  function __fibaro_get_device_property(deviceId ,propertyName)
    __assert_type(deviceId,"number")
    __assert_type(propertyName,"string")
    local key = propertyName..deviceId
    local c = cache.read('devices',key) or api.get("/devices/"..deviceId.."/properties/"..propertyName) 
    cache.write('devices',key,c)
    return c
  end

  local ZBCOLORMAP = Util.ZBCOLORMAP
  local DEBUGCOLORS = {['DEBUG']='green', ['TRACE']='orange', ['WARNING']='purple', ['ERROR']='red'}
  local function fibaro_debug(t,type,str)
    assert(str,"Missing tag for debug") 
    if hc3_emulator.colorDebug then
      local color = DEBUGCOLORS[t] or "black"
      color = ZBCOLORMAP[color]
      t = format('%s%s\027[0m', color, t) 
    end
    print(format("%s [%s]: %s",os.date("[%d.%m.%Y] [%X]"),t,str)) 
  end
  function __fibaro_add_debug_message(type,str) fibaro_debug("DEBUG",type,str) end
  local function d2str(...) local r={...} for i=1,#r do r[i]=tostring(r[i]) end return table.concat(r," ") end 
  function fibaro.debug(type,...)  fibaro_debug("DEBUG",type,d2str(...)) end
  function fibaro.warning(type,...)  fibaro_debug("WARNING",type,d2str(...)) end
  function fibaro.trace(type,...) fibaro_debug("TRACE",type,d2str(...)) end
  function fibaro.error(type,...) fibaro_debug("ERROR",type,d2str(...)) end

  function fibaro.getName(deviceID) 
    __assert_type(deviceID,'number') 
    local dev = __fibaro_get_device(deviceID) 
    return dev and dev.name
  end

  sourceTrigger = nil -- global containing last trigger for scene

  function fibaro.get(deviceID,propertyName) 
    local property = __fibaro_get_device_property(deviceID ,propertyName)
    if property then return property.value, property.modified end
  end

  function fibaro.getValue(deviceID, propertyName) return (fibaro.get(deviceID , propertyName)) end

  function fibaro.wakeUpDeadDevice(deviceID ) 
    __assert_type(deviceID,'number') 
    fibaro.call(1,'wakeUpDeadDevice',deviceID) 
  end

  function fibaro.call(deviceID, actionName, ...) 
    __assert_type(actionName ,"string") 
    if type(deviceID)=='table' then 
      for _,d in ipairs(deviceID) do fibaro.call(d, actionName, ...) end
    else
      __assert_type(deviceID ,"number") 
      if actionName == "toggle" then
        local val = fibaro.getValue(deviceID,'value')
        val = tonumber(val) and val> 0 or val
        return fibaro.call(deviceID,val and 'turnOff' or 'turnOn')
      end
      local a = {args={},delay=0} 
      for i,v in ipairs({...}) do a.args[i]=v end
      if deviceID == plugin.mainDeviceId and not _quickApp.hasProxy then
        _quickApp[actionName](_quickApp,...)
      else
        local res,stat = api.post("/devices/"..deviceID.."/action/"..actionName,a) 
        if stat==404 then Log(LOG.ERROR,"Device %s does not exists",deviceID) end
      end
    end
  end

  function fibaro.getType(deviceID) 
    local dev = __fibaro_get_device(deviceID) 
    return dev and dev.type or nil 
  end

  function fibaro.getGlobalVariable(varName)
    local globalVar = __fibaro_get_global_variable(varName) 
    if  globalVar then return globalVar.value , globalVar.modified end
  end

  function fibaro.setGlobalVariable(varName , value) 
    __assert_type(varName ,"string") 
    local data =  {["value"] = tostring(value) , ["invokeScenes"] = true} 
    api.put("/globalVariables/"..varName , data) 
  end

  function fibaro.emitCustomEvent(name) return api.post("/customEvents/"..name,{}) end

  function fibaro.setTimeout(value, func) return setTimeout(func, value) end

  function fibaro.getRoomName(roomID) 
    __assert_type(roomID,'number') 
    local room = __fibaro_get_room(roomID) 
    return room and room.name
  end

  function fibaro.getRoomID(deviceID) 
    local dev = __fibaro_get_device(deviceID) 
    return dev and dev.roomID
  end

  function fibaro.getRoomNameByDeviceID(deviceID) 
    local roomID = fibaro.getRoomID(deviceID)
    return roomID == 0 and "unassigned" or fibaro.getRoomName(roomID)
  end

  function fibaro.getSectionID(deviceID) 
    local roomID = fibaro.getRoomID(deviceID)
    return roomID == 0 and 0 or __fibaro_get_room(roomID).sectionID 
  end

  function fibaro.getIds(devices) 
    local ids = {} 
    for _,a in pairs(devices) do 
      if a ~= nil and type (a) == 'table' and a['id'] ~= nil and a['id'] > 3  then 
        ids[#ids+1]=a['id']
      end 
    end 
    return ids
  end

  function fibaro.getAllDeviceIds() return api.get('/devices/') end

  function fibaro.getDevicesID(filter) 
    local function encode(s) return urlencode(tostring(s)) end
    if type(filter) ~= 'table' or (type(filter) == 'table' and next( filter ) == nil) then 
      return fibaro.getIds(fibaro.getAllDeviceIds()) 
    end
    local args = '/?' 
    for c,d in pairs(filter) do 
      if c == 'properties' and d ~= nil and type(d) == 'table' then 
        for a,b in pairs (d) do 
          if b == "nil" then 
            args = args..'property='..encode(a)..'&' 
          else 
            args = args..'property=['..encode(a)..','..encode(b)..']&' 
          end 
        end 
      elseif c == 'interfaces' and d ~= nil and type(d) == 'table' then 
        for _,b in pairs(d) do 
          args = args..'interface='..encode(b)..'&'
        end 
      else 
        args = args..encode(c).."="..encode(d)..'&' 
      end 
    end
    args =  string.sub(args,1,-2) 
    return fibaro.getIds(api.get('/devices'..args)) 
  end

  function fibaro.scene(action, sceneIDs) -- execute or kill
    __assert_type(sceneIDs,'table')   
    for _,id in ipairs(sceneIDs) do api.post("/scenes/"..id.."/"..action,{}) end
  end

  function fibaro.profile(profile_id, action)
    __assert_type(profile_id,'number') 
    __assert_type(action,'string') 
    return api.post("/profiles/"..action.."/"..profile_id)
  end

  function fibaro.callGroupAction(action,args)
    __assert_type(action,'string')     
    __assert_type(args,'table')     
    local res,stat = api.post("/devices/groupAction/"..action,args)
    return stat==202 and res.devices
  end

  function fibaro.alert(alert_type, user_ids, notification_content) 
    __assert_type(user_ids,'table') 
    for _,u in ipairs(alert_type) do fibaro.call(u,alert_type,notification_content) end
  end

-- User PIN?
  function fibaro.alarm(partition_id, action)
    if action then return api.post("/alarms/v1/partitions/"..partition_id.."/actions/"..action)
    else return api.post("/alarms/v1/partitions/actions/"..partition_id) end -- partition_id -> action
  end

  function fibaro.__houseAlarm() end -- ToDo:

  function fibaro._sleep(ms) -- raw sleep, ignoring sleep.
    local t = ostime()+ms;  -- Use real clock
    while ostime() <= t do socket.sleep(0.01) end   -- save batteries...
  end
  function fibaro.sleep(ms)
    __assert_type(ms,'number') 
    if hc3_emulator.speeding then 
      _timeAdjust=_timeAdjust+ms/1000 
      --Timer.runSystemTimers()
      return
    else
      local t = os.time()+ms/1000; 
      while os.time() < t do 
        --Timer.runSystemTimers()
        socket.sleep(0.01)       -- without waking up QA/scene timers
      end                        -- ToDo: we probably need 2 timer queues...
    end
  end

  local rawCall
  api={} -- Emulation of api.get/put/post/delete
  function api.get(call) 
    local last = call:match("/refreshStates%?last=(%d+)") -- Always fetch from emulator cache...
    if last  then
      return Trigger.refreshStates.getEvents(tonumber(last))
    end
    return rawCall("GET",call) 
  end
  function api.put(call, data) return rawCall("PUT",call,json.encode(data),"application/json") end
  function api.post(call, data, hs, to) return rawCall("POST",call,data and json.encode(data),"application/json",hs,to) end
  function api.delete(call, data) return rawCall("DELETE",call,data and json.encode(data),"application/json") end

------------  HTTP support ---------------------

  local function intercepLocal(url,options,success,error)
    if url:match("://(127%.0%.0%.1)[:/]") then
      url = url:gsub("(://127%.0%.0%.1)","://"..hc3_emulator.credentials.ip)
      if url:match("://.-:11111/") then
        url = url:gsub("(:11111)","")
        options.headers = options.headers or {}
        options.headers['Authorization'] = hc3_emulator.BasicAuthorization
      end
      local refresh = url:match("/api/refreshStates%?last=(%d+)")
      if refresh then
        local state = Trigger.refreshStates.getEvents(tonumber(refresh))
        if success then success({status=200,data=json.encode(state)}) end
        return true
      end
    end
    return false,url
  end

  net = net or {mindelay=10,maxdelay=1000} -- An emulation of Fibaro's net.HTTPClient and net.TCPSocket()

  function net.HTTPClient(i_options)     -- It is synchronous, but synchronous is a speciell case of asynchronous.. :-)
    local self = {}                    -- Not sure I got all the options right..
    function self:request(url,args)
      local req = {}; for k,v in pairs(i_options or {}) do req[k]=v end
      for k,v in pairs(args.options or {}) do req[k]=v end
      local s,u = intercepLocal(url,req,args.success,args.error)
      if s then return else url=u end
      local resp = {}
      req.url = url
      req.headers = req.headers or {}
      req.sink = ltn12.sink.table(resp)
      if req.data then
        req.headers["Content-Length"] = #req.data
        req.source = ltn12.source.string(req.data)
      end
      local response, status, headers, timeout
      http.TIMEOUT,timeout=req.timeout and math.floor(req.timeout/1000) or http.TIMEOUT, http.TIMEOUT
      if url:lower():match("^https") then
        response, status, headers = https.request(req)
      else 
        response, status, headers = http.request(req)
      end
      http.TIMEOUT = timeout
      if response == 1 then 
        local d = table.concat(resp)
        if args.success then -- simulate asynchronous callback
          if net.maxdelay>=net.mindelay then
            Timer.setTimeout(function() args.success({status=status, headers=headers, data=d}) end,math.random(net.mindelay,net.maxdelay)) 
          else
            args.success({status=status, headers=headers, data=table.concat(resp)})
          end
        end
      else
        if args.error then 
          if net.maxdelay>=net.mindelay then
            Timer.setTimeout(function() args.error(status) end,math.random(net.mindelay,net.maxdelay))
          else
            args.error(status) 
          end
        end
      end
    end
    return self
  end
  local HTTPSyncClient = net.HTTPClient

  function net.HTTPAsyncClient(i_options)  -- It is synchronous, but synchronous is a speciell case of asynchronous.. :-)
    local self = {}                       -- Not sure I got all the options right..
    function self:request(url,args)
      local req = {}; for k,v in pairs(i_options or {}) do req[k]=v end
      for k,v in pairs(args.options or {}) do req[k]=v end
      local s,u = intercepLocal(url,req,args.success,args.error)
      if s then return else url=u end
      local resp = {}
      req.url = url
      req.headers = req.headers or {}
      req.sink = ltn12.sink.table(resp)
      if req.data then
        req.headers["Content-Length"] = #req.data
        req.source = ltn12.source.string(req.data)
      end
      local response, status, headers, timeout, oldTimeout = nil,'timeout'
      --http.TIMEOUT,timeout=req.timeout and math.floor(req.timeout/1000) or http.TIMEOUT, http.TIMEOUT
      oldTimeout,timeout=http.TIMEOUT,os.time()+(req.timeout and math.floor(req.timeout/1000) or http.TIMEOUT or 60)
      local reqFun = url:lower():match("^https") and https.request or http.request
      local function getHTTP()
        http.TIMEOUT=1
        response, status, headers = http.request(req)
        http.TIMEOUT=oldTimeout
        if status=='timeout' and os.time()<=timeout then
          setTimeout(getHTTP,1)
        else 
          if response==1 then
            if args.success then 
              Timer.setTimeout(function() args.success({status=status, headers=headers, data=table.concat(resp)}) end,0) 
            end
          else
            if args.error then 
              Timer.setTimeout(function() args.error(status) end,0)
            end
          end
        end
      end
      getHTTP()
      return
    end
    return self
  end

  function net.TCPSocket(opts) --error("TCPSocket - Not implemented yet")
    local self = { opts = opts }
    local sock = socket.tcp()
    function self:connect(ip, port, opts) 
      for k,v in pairs(self.opts) do opts[k]=v end
      local sock, err = sock:connect(ip,port)
      if sock and opts.success then self.sock = sock; opts.success()
      elseif sock==nil and opts.error then opts.error(err) end
    end
    function self:read(opts) 
      local data,err = sock:receive() 
      if data and opts.success then opts.success(data)
      elseif data==nil and opts.error then opts.error(err) end
    end
    function self:readUntil(delimiter, callbacks) end
    function self:send(data, opts) 
      local res,err = sock:send(data)
      if res and opts.success then opts.success(res)
      elseif res==nil and opts.error then opts.error(err) end
    end
    function self:close() self.sock:close() end
    return self
  end

  function rawCall(method,call,data,cType,hs,to)
    if hc3_emulator.offline then return Offline.api(method,call,data,cType,hs) end
    if call:match("/refreshStates") then return Offline.api(method,call,data,cType,hs) end
    local resp = {}
    local req={ method=method, timeout=to or 5000,
      url = "http://"..hc3_emulator.credentials.ip.."/api"..call,
      sink = ltn12.sink.table(resp),
      user=hc3_emulator.credentials.user,
      password=hc3_emulator.credentials.pwd,
      headers={}
    }
    --req.headers["Accept"] = 'application/json'
    req.headers["Accept"] = '*/*'
    req.headers["X-Fibaro-Version"] = 2
    if data then
      req.headers["Content-Type"] = cType
      req.headers["content-length"] = #data
      req.source = ltn12.source.string(data)
    end
    if hs then for k,v in pairs(hs) do req.headers[k]=v end end
    local r, c, h = http.request(req)
    if not r then
      return nil,c, h
      --error(format("Error connnecting to HC3: '%s' - URL: '%s'.",c,req.url))
    end
    if c>=200 and c<300 then
      return resp[1] and safeDecode(table.concat(resp)) or nil,c
    end
    return nil,c, h
    --error(format("HC3 returned error '%d %s' - URL: '%s'.",c,resp[1] or "",req.url))
  end

-------------- MQTT support ---------------------
  local stat,_mqtt=pcall(function() return require("mqtt") end)
  if stat then
    mqtt={ 
      Client = {}, 
      QoS = {EXACTLY_ONCE=1},
      MSGT = { 
        CONNECT = 1,
        CONNACK = 2,
        PUBLISH = 3,
        PUBACK = 4,
        PUBREC = 5,
        PUBREL = 6,
        PUBCOMP = 7,
        SUBSCRIBE = 8,
        SUBACK = 9,
        UNSUBSCRIBE = 10,
        UNSUBACK = 11,
        PINGREQ = 12,
        PINGRESP = 13,
        DISCONNECT = 14,
        AUTH = 15,
      },
      MSGMAP = {
        [9]='subscribed',
        [11]='unsubscribed', 
        [4]='published',  -- Should be onpublished according to doc?
        [14]='closed',
      }
    }
    function mqtt.Client.connect(uri, options)
      options = options or {}
      local args = {}
      args.uri = uri
      args.username = options.username
      args.password = options.password
      args.clean = options.cleanSession
      if args.clean == nil then args.clean=true end
      args.will = options.lastWill
      args.keep_alive = options.keepAlivePeriod
      args.id = options.clientId

      --cafile="...", certificate="...", key="..." (default false)
      if options.clientCertificate then -- Not in place...
        args.secure = {
          certificate= options.clientCertificate,
          cafile = options.certificateAuthority,
          key = "",
        }
      end

      local _client = _mqtt.client(args)
      local client={ _client=_client, _handlers={} }
      function client:addEventListener(message,handler) 
        self._handlers[message]=handler
      end
      function client:subscribe(topic, options) 
        options = options or {}
        local args = {}
        args.topic = topic
        args.qos = options.qos or 0
        args.callback = options.callback
        return self._client:subscribe(args)
      end
      function client:unsubscribe(topics, options) 
        if type(topics)=='string' then return self._client:unsubscribe({topic=topics})
        else
          local res
          for _,t in ipairs(topics) do res=self:unsubscribe(t) end
          return res
        end
      end
      function client:publish(topic, payload, options) 
        options = options or {}
        local args = {}
        args.topic = topic
        args.payload = payload
        args.qos = options.qos or 0
        args.retain = options.retain or false
        args.callback = options.callback
        return self._client:publish(args)
      end
      function client:disconnect(options) 
        options = options or {}
        local args = {}
        args.callback = options.callback
        return self._client:disconnect(args)
      end
      --function client:acknowledge() end

      _client:on{
        --{"type":2,"sp":false,"rc":0}
        connect = function(connack)
          Debug(_debugFlags.mqtt,"MQTT connect:"..json.encode(connack))
          if client._handlers['connected'] then 
            client._handlers['connected']({sessionPresent=connack.sp,returnCode=connack.rc}) 
          end
        end,
        subscribe = function(event)
          Debug(_debugFlags.mqtt,"MQTT subscribe:"..json.encode(event))
          if client._handlers['subscribed'] then client._handlers['subscribed'](event) end
        end,
        unsubscribe = function(event)
          Debug(_debugFlags.mqtt,"MQTT unsubscribe:"..json.encode(event))
          if client._handlers['unsubscribed'] then client._handlers['unsubscribed'](event) end
        end,
        message = function(msg)
          Debug(_debugFlags.mqtt,"MQTT message:"..json.encode(msg))
          local msgt = mqtt.MSGMAP[msg.type]
          if msgt and client._handlers[msgt] then client._handlers[msgt](msg)
          elseif client._handlers['message'] then client._handlers['message'](msg) end
        end,
        acknowledge = function(event)
          Debug(_debugFlags.mqtt,"MQTT acknowledge:"..json.encode(event))
          if client._handlers['acknowledge'] then client._handlers['acknowledge']() end
        end,
        error = function(err)
          if _debugFlags.mqtt then Log(LOG.ERROR,"MQTT error:"..err) end
          if client._handlers['error'] then client._handlers['error'](err) end
        end,
        close = function(event)
          Debug(_debugFlags.mqtt,"MQTT close:"..Util.prettyJson(event))
          if client._handlers['closed'] then client._handlers['closed'](event) end
        end,
        auth = function(event)
          Debug(_debugFlags.mqtt,"MQTT auth:"..json.encode(event))
          if client._handlers['auth'] then client._handlers['auth'](event) end
        end,
      }

      _mqtt.get_ioloop():add(client._client)
      if not mqtt._loop then
        local iter = _mqtt.get_ioloop()
        mqtt._loop = Timer.setInterval(function() iter:iteration() end,1000)
      end
      return client
    end
  end

------------ HomeCenter ------------------------------
  fibaro.homeCenter = {   
    PopupService = { 
      publish = function(request) 
        return api.post("/popups",request) 
      end 
    }, 

    climate = {
      setClimateZoneToScheduleMode = fibaro.setClimateZoneToScheduleMode,
      setClimateZoneToManualMode = fibaro.setClimateZoneToManualMode,
      setClimateZoneToVacationMode = fibaro.setClimateZoneToVacationMode
    },

    SystemService = {
      reboot = function() api.post("/service/reboot") end,
      suspend = function() api.post("/service/suspend") end,
      shutdown = function() api.post("/service/shutdown") end,
    },

    notificationService = {
      publish = function(request)
        request.canBeDeleted = true
        request.canBeDeleted = true
        return api.post('/notificationCenter', request)
      end,

      update = function(id, request)
        __assert_type(id, "number")
        request.canBeDeleted = true
        return api.put('/notificationCenter/'..id, request)
      end,

      remove = function(id)
        __assert_type(id, "number")
        return api.delete('/notificationCenter/'..id)
      end
    },
  }

  urlencode = Util.urlencode
  unpack = table.unpack
  return fibaro
end

-------------- Timer support -------------------------
function module.Timer()
  local self = {}

  local timers = nil
  local function milliTime() return ostime() end

  local function insertTimer(t) -- {fun,time,next}
    if timers == nil then timers=t
    elseif t.time < timers.time then
      timers,t.next=t,timers
    else
      local tp = timers
      while tp.next and tp.next.time <= t.time do tp=tp.next end
      t.next,tp.next=tp.next,t
    end
    return t.fun
  end

  function self.start()
    while timers ~= nil do
      ::REDO::
      local t,now = timers,milliTime()
      if t==nil or t.time > now then 
        socket.sleep(0.01) -- 10ms
        goto REDO 
      end
      ---local ct = osclock() - can we add a millisecond part?
      timers=timers.next
      --Log(LOG.SYS,"CT:%s",t)
      if _debugFlags.timers and t.tag then Log(LOG.SYS,"T:"..tostring(t)) end
      t.fun()
    end
  end

  function self.runSystemTimers() -- Called from sleep and other places to keep system timers going
    if timers == nil then return end
    local t0,now = timers,milliTime()
    while t0 and t0.isSystem and t0.time <= now do
      t0.fun() t0=t0.next 
    end
    while t0.next and t0.next.time <= now do
      if t0.next.isSystem then ---  t0 -> t1 -> nil
        t0.next.fun()
        t0.next = t0.next.next
      end
      t0=t0.next
    end
  end

  local function dumpTimers()
    local t = timers 
    while(t) do Log(LOG.LOG,t) t=t.next end
  end

  local TimerMetatable = {
    __tostring = function(self)
      return format("<%sTimer:%s, exp:%s%s>", 
        self.isSystem and "Sys" or "", 
        self.tostr:sub(10), 
        os.date("%H:%M:%S",math.floor(0.5+self.t0)), 
        self.tag and (", tag:'"..self.tag.."'") or "")
    end
  }

  local function makeTimer(time,fun,props)  
    local t = {['%%TIMER%%']=true, time=time, fun=fun, tag=props and props.tag, t0=os.time()+time}
    t.tostr = tostring(t) setmetatable(t,TimerMetatable)
    return t
  end
  local function isTimer(timer) return type(timer)=='table' and timer['%%TIMER%%'] end

  function self.clearTimeout(timer)
    assert(timer == nil or isTimer(timer),"Bad timer to clearTimeout:"..tostring(timer))
    if timer==nil then return end
    if timers == timer then
      timers = timers.next
    else
      local tp = timers
      while tp and tp.next do
        if tp.next == timer then tp.next = tp.next.next return end
        tp = tp.next
      end
    end
  end

  function self.setTimeout(fun,ms,tag)
    assert(type(fun)=='function' and type(ms)=='number',"Bad argument to setTimeout")
    if ms >= 0 then
      local t = makeTimer(ms/1000+milliTime(),fun,{tag=tag})
      insertTimer(t)
      return t
    end
  end

  function self.coprocess(ms,fun,tag,...)
    local args = {...}
    local p = coroutine.create(function() fun(table.unpack(args)) end)
    local function process()
      local res,err = coroutine.resume(p)
      local stat = coroutine.status(p) -- run every ms
      if stat~="dead" then self.setTimeout(process,ms,tag).isSystem=true end  -- ToDo: check exit
      if stat == 'dead' and err then
        Log(LOG.ERROR,err)
        Log(LOG.ERROR,debug.traceback(p))
      end
    end
    process()
  end

  function self.setInterval(fun,ms,tag)
    assert(type(fun)=='function' and type(ms)=='number',"Bad argument to setInterval")
    local ref={}
    local function loop()
      if ref[1] then
        fun()
        ref[1]=setTimeout(loop,ms,tag)
      end
    end
    ref[1] = setTimeout(loop,ms,tag)
    return ref
  end

  function self.clearInterval(ref) 
    assert(type(ref)=='table',"Bad timer to clearInterval")
    local r = ref[1]
    assert(r == nil or isTimer(r),"Bad timer to clearInterval:"..tostring(r))
    if r then ref[1]=nil; clearTimeout(r) end 
  end

  function self.speedTime(speedTime)
    local maxTime = os.time()+speedTime*60*60
    local fastTimer = nil

    local function addTimer(t) --{f = fun, t=time, nxt = next}
      t.time=t.time+os.time() -- absolute time we expire
      if fastTimer == nil then fastTimer = t
      elseif t.time < fastTimer.time then
        t.next=fastTimer; fastTimer = t
      else
        local ft = fastTimer
        while(ft.next and ft.next.time < t.time) do ft=ft.next end
        t.next=ft.next; ft.next=t
      end
      return t
    end

    function setTimeout(fun,t,tag) -- globally redefine global setTimeout
      assert(type(fun)=='function' and type(t)=='number',"Bad argument to setTimeout")
      --Log(LOG.LOG,"S %s:%d",tag or "",t/1000)
      if t >= 0 then return addTimer(makeTimer(t/1000,fun,{tag=tag})) end
    end

    function clearTimeout(ref)  -- globally redefine global clearTimeout
      assert(ref == nil or isTimer(ref),"Bad timer to clearTimeout:"..tostring(ref))
      if ref == fastTimer then
        fastTimer = fastTimer.next
      elseif fastTimer.next == ref then
        fastTimer.next = ref.next
      else
        local ft = fastTimer
        while(ft.next and ft.next ~= ref) do ft=ft.next end
        ft.next=ref.next
      end
    end

    local function dumpTimers()
      local t = fastTimer
      Log(LOG.LOG,"-------")
      while t do
        Log(LOG.LOG,t)
        t=t.next
      end
    end
    self.coprocess(0,function()
        while true do
          if os.time() >= maxTime then Log(LOG.SYS,"Max time - exit")  os.exit() end
          if fastTimer then
            --dumpTimers()
            local time = fastTimer.time
            Timer.setTimeout(fastTimer.fun,0,fastTimer.tag) -- schedule next time in lines
            --Log(LOG.LOG,"E %s",fastTimer)
            _timeAdjust=_timeAdjust+time-os.time() -- adjust time
            fastTimer = fastTimer.next
            while fastTimer and fastTimer.time==time do
              Timer.setTimeout(fastTimer.fun,0,fastTimer.tag)
              --Log(LOG.LOG,"E %s",fastTimer)
              fastTimer = fastTimer.next
            end
          else 
            _timeAdjust=_timeAdjust+5 -- 2s?
          end
          coroutine.yield()
        end
      end,"speedTime")
  end

-- Redefine time functions so we can "control" time
  function os.time(t) return t and ostime(t) or ostime()+math.floor(_timeAdjust+0.5) end
  function os.date(f,t) return t and osdate(f,t) or osdate(f,os.time()) end

  function self.setEmulatorTime(t)
    local diff = t-os.time()
    _timeAdjust = _timeAdjust + diff
    Log(LOG.SYS,"Setting emulator time to %s",os.date("%c",t))
  end

  setTimeout = self.setTimeout
  clearTimeout = self.clearTimeout
  setInterval = self.setInterval
  clearInterval = self.clearInterval

  hc3_emulator.dumpTimers = dumpTimers
  return self
end

--------------- QuickApp functions and support -------
function module.QuickApp()
  local self = {}
  plugin = {}
  plugin.mainDeviceId = nil
  function plugin.deleteDevice(deviceId) return api.delete("/devices/"..deviceId) end
  function plugin.restart(deviceId) return api.post("/plugins/restart",{deviceId=deviceId}) end
  function plugin.getProperty(id,prop) return api.get("/devices/"..id.."/property/"..prop) end
  function plugin.getChildDevices(id) return api.get("/devices?parentId="..(id or plugin.mainDeviceId)) end
  function plugin.createChildDevice(prop) return api.post("/plugins/createChildDevice",prop) end
  plugin.getDevice = nil

  plugin._uiValues = {}
  function self.getWebUIValue(elm,t) return plugin._uiValues[elm][t] end
  function self.setWebUIValue(elm,t,v) 
    plugin._uiValues[elm] = plugin._uiValues[elm] or {}
    plugin._uiValues[elm][t]=tostring(v) 
  end

  class 'QuickAppBase'
  function QuickAppBase:__init(device)
    for k,v in pairs(device) do self[k]=v end
    local cbs = {}
    for _,cb in ipairs(self.properties.uiCallbacks or {}) do
      cbs[cb.name]=cbs[cb.name] or {}
      cbs[cb.name][cb.eventType] = cb.callback
      if hc3_emulator.UI then
        for _,row in ipairs(hc3_emulator.UI) do
          row = row[1] and row or {row}
          for _,e in ipairs(row) do
            QA.setWebUIValue(e.name,"value","0")
            QA.setWebUIValue(e.name,"text",e.text or "")
          end
        end
      end
    end
    self.uiCallbacks = cbs
  end

  function QuickAppBase:debug(...) fibaro.debug("",table.concat({...})) end
  function QuickAppBase:trace(...) fibaro.trace("",table.concat({...})) end
  function QuickAppBase:warning(...) fibaro.warning("",table.concat({...})) end
  function QuickAppBase:error(...) fibaro.error("",table.concat({...})) end

  function QuickAppBase:getVariable(name)
    __assert_type(name,'string')
    if self.hasProxy then
      local d = api.get("/devices/"..self.id) or {properties={}}
      for _,v in ipairs(d.properties.quickAppVariables or {}) do
        if v.name==name then return v.value end
      end
    end
    for _,v in ipairs(self.properties.quickAppVariables or {}) do
      if v.name==name then return v.value end
    end
    return ""
  end

  function QuickAppBase:setVariable(name,value)
    __assert_type(name,'string')
    if self.hasProxy then
      fibaro.call(self.id,"setVariable",name,value)
    end
    local vs = self.properties.quickAppVariables
    vs = vs or {}
    for _,v in ipairs(vs) do
      if v.name==name then v.value=value; return end
    end
    vs[#vs+1]={name=name,value=value}
    self.properties.quickAppVariables = vs
  end

  function QuickAppBase:updateView(elm,t,value) 
    if self.hasProxy then
      api.post("/plugins/updateView",{
          deviceId=self.id,
          componentName =  elm,
          propertyName = t,  
          newValue = value
        })
      --fibaro.call(self.id,"updateView",elm,t,value)
    end
    QA.setWebUIValue(elm,t,value)
  end

  function QuickAppBase:updateProperty(prop,value)
    __assert_type(prop,'string')
    if self.hasProxy then
      local stat,res=api.put("/devices/"..self.id,{properties = {[prop]=value}})
    else 
      self.properties[prop]=tostring(value)
    end
  end

  function QuickAppBase:callAction(fun, ...)
    if type(self[fun])=='function' then return self[fun](self,...)
    else
      self:warning("Class does not have "..fun.." function defined - action ignored")
    end
  end

  function QuickAppBase:addInterfaces(interfaces)
    if self.hasProxy then
      api.post("/devices/addInterface",{deviceID={self.id},interfaces=interfaces})
    end
  end

  class 'QuickApp'(QuickAppBase)
  function QuickApp:__init(device) 
    QuickAppBase.__init(self,device)
    if hc3_emulator.quickVars then 
      local vs = self.properties.quickAppVariables or {}
      for k,v in pairs(hc3_emulator.quickVars) do self:setVariable(k,v) end
    end
    self.childDevices = {}
    self.hasProxy = plugin.isProxy
    _quickApp = self
    if self.onInit then self:onInit() end
    if not self._childsInited then self:initChildDevices() end
  end

  function QuickApp:createChildDevice(props,device)
    assert(self.hasProxy,"Can only create child device when using proxy")
    props.parentId = self.id
    props.initialInterfaces = props.initialInterfaces or {}
    props.initialInterfaces[#props.initialInterfaces+1]='quickAppChild'

    local d,res = api.post("/plugins/createChildDevice",props)
    assert(res==200,"Can't create child device "..json.encode(props))
    --fibaro.call(self.id,"CREATECHILD",d.id)
    device = device or QuickAppChild
    local cd = device(d)
    cd.parent = self
    self.childDevices[d.id]=cd
    return cd
  end

  function QuickApp:removeChildDevice(id)
    __assert_type(id,'number')
    if self.childDevices[id] then
      api.delete("/plugins/removeChildDevice/" .. id)
      self.childDevices[id] = nil
    end
  end

  function QuickApp:initChildDevices(map)
    local echilds = plugin.getChildDevices() 
    local childs = self.childDevices
    for _,d in pairs(echilds or {}) do
      if (not childs[d.id]) and map[d.type] then
        childs[d.id]=map[d.type](d)
      elseif not childs[d.id] then
        Log(LOG.ERROR,"Class for the child device: %s, with type: %s not found. Using base class: QuickAppChild",d.id,d.type)
        childs[d.id]=QuickAppChild(d)
      end
      childs[d.id].parent = self
    end
    self._childsInited = true
  end

  class 'QuickAppChild'(QuickAppBase)
  function QuickAppChild:__init(device) 
    QuickAppBase.__init(self,device) 
    self.hasProxy=true
  end

  local function traverse(o,f)
    if type(o) == 'table' and o[1] then
      for _,e in ipairs(o) do traverse(e,f) end
    else f(o) end
  end
  local map = Util.mapf

  local function collectViewLayoutRow(u,map)
    local row = {}
    local function conv(u)
      if type(u) == 'table' then
        if u.name then
          if u.type=='label' then
            row[#row+1]={label=u.name, text=u.text}
          elseif u.type=='button'  then
            local cb = map["button"..u.name]
            if cb == u.name.."Clicked" then cb = nil end
            row[#row+1]={button=u.name, text=u.text, callback=cb}
          elseif u.type=='slider' then
            local cb = map["slider"..u.name]
            if cb == u.name.."Clicked" then cb = nil end
            row[#row+1]={slider=u.name, text=u.text, callback=cb}
          end
        else 
          for k,v in pairs(u) do conv(v) end 
        end
      end
    end
    conv(u)
    return row
  end

  local function viewLayout2UI(u,map)
    local function conv(u)
      local rows = {}
      for i,j in pairs(u.items) do
        local row = collectViewLayoutRow(j.components,map)
        if #row > 0 then
          if #row == 1 then row=row[1] end
          rows[#rows+1]=row
        end
      end
      return rows
    end
    return conv(u['$jason'].body.sections)
  end

  function self.view2UI(view,callbacks)
    local map = {}
    traverse(callbacks,function(e)
        if e.eventType=='onChanged' then map["slider"..e.name]=e.callback
        elseif e.eventType=='onReleased' then map["button"..e.name]=e.callback end
      end) 
    local UI = viewLayout2UI(view,map)
    return UI
  end

  function self.getQAUI(id)
    local d = api.get("/devices/"..id)
    local UI = self.view2UI(d.properties.viewLayout,d.properties.uiCallbacks)
    return UI
  end

  local ELMS = {
    button = function(d,w)
      return {name=d.name,style={weight=w or "0.50"},text=d.text,type="button"}
    end,
    select = function(d,w)
      if d.options then map(function(e) e.type='option' end,d.options) end
      return {name=d.name,style={weight=w or "0.50"},text=d.text,type="select", selectionType='single',
        options = d.options or {{value="1", type="option", text="option1"}, {value = "2", type="option", text="option2"}},
        values = d.values or { "option1" }
      }
    end,
    multi = function(d,w)
      if d.options then map(function(e) e.type='option' end,d.options) end
      return {name=d.name,style={weight=w or "0.50"},text=d.text,type="select", selectionType='multi',
        options = d.options or {{value="1", type="option", text="option2"}, {value = "2", type="option", text="option3"}},
        values = d.values or { "option3" }
      }
    end,
    image = function(d,w)
      return {name=d.name,style={dynamic="1"},type="image", url=d.url}
    end,
    switch = function(d,w)
      return {name=d.name,style={weight=w or "0.50"},type="switch", value=d.value or "true"}
    end,
    option = function(d,w)
      return {name=d.name, type="option", value=d.value or "Hupp"}
    end,
    slider = function(d)
      return {name=d.name,max=tostring(d.max),min=tostring(d.min),style={weight="1.2"},text=d.text,type="slider"}
    end,
    label = function(d)
      return {name=d.name,style={weight="1.2"},text=d.text,type="label"}
    end,
    space = function(d,w)
      return {style={weight=w or "0.50"},type="space"}
    end
  }

  local function mkRow(elms,weight)
    local comp = {}
    if elms[1] then
      local c = {}
      local width = format("%.2f",1/#elms)
      for _,e in ipairs(elms) do c[#c+1]=ELMS[e.type](e,width) end
      comp[#comp+1]={components=c,style={weight="1.2"},type='horizontal'}
      comp[#comp+1]=ELMS['space']({},"0.5")
    else
      comp[#comp+1]=ELMS[elms.type](elms,"1.2")
      comp[#comp+1]=ELMS['space']({},"0.5")
    end
    return {components=comp,style={weight=weight or "1.2"},type="vertical"}
  end

  local function mkViewLayout(list,height)
    local items = {}
    for _,i in ipairs(list) do items[#items+1]=mkRow(i) end
    return 
    { ['$jason'] = {
        body = {
          header = {
            style = {height = tostring(height or #list*50)},
            title = "quickApp_device_23"
          },
          sections = {
            items = items
          }
        },
        head = {
          title = "quickApp_device_23"
        }
      }
    }
  end

  local function transformUI(UI) -- { button=<text> } => {type="button", name=<text>}
    traverse(UI,
      function(e)
        if e.button then e.name,e.type=e.button,'button'
        elseif e.slider then e.name,e.type=e.slider,'slider'
        elseif e.select then e.name,e.type=e.select,'select'
        elseif e.switch then e.name,e.type=e.switch,'switch'
        elseif e.multi then e.name,e.type=e.multi,'multi'
        elseif e.option then e.name,e.type=e.option,'option'
        elseif e.image then e.name,e.type=e.image,'image'
        elseif e.label then e.name,e.type=e.label,'label'
        elseif e.space then e.weight,e.type=e.space,'space' end
      end)
  end

  local function uiStruct2uiCallbacks(UI)
    local cb = {}
    --- "callback": "self:button1Clicked()",
    traverse(UI,
      function(e)
        if e.name then 
          -- {callback="foo",name="foo",eventType="onReleased"}
          local cbt,et = e.name..(e.button and "Clicked" or "Change"),e.button and "onReleased" or "onChanged"
          if e.onReleased then 
            cbt = e.onReleased
          elseif e.onChanged then
            cbt = e.onChanged
            et = "onChanged"
          end
          if e.button or e.slider then 
            cb[#cb+1]={callback=cbt,eventType=et,name=e.name} 
          end
        end
      end)
    return cb
  end

  local function updateViewLayout(id,UI,forceUpdate) --- This may not work anymore....
    transformUI(UI)
    local cb = api.get("/devices/"..id).properties.uiCallbacks or {}
    local viewLayout = mkViewLayout(UI)
    local newcb = uiStruct2uiCallbacks(UI)
    if forceUpdate then 
      cb = newcb -- just replace uiCallbacks with new elements callbacks
    else
      local mapOrg = {}
      for _,c in ipairs(cb) do mapOrg[c.name]=c.callback end -- existing callbacks, map name->callback
      for _,c in ipairs(newcb) do if mapOrg[c.name] then c.callback=mapOrg[c.name] end end
      cb = newcb -- save exiting elemens callbacks
    end
    if not cb[1] then cb = nil end
    return api.put("/devices/"..id,{
        properties = {
          viewLayout = viewLayout,
          uiCallbacks = cb},
      })
  end

  local function makeInitialProperties(code,UI,vars,height)
    local ip = {}
    vars = vars or {}
    ip.mainFunction = code
    transformUI(UI)
    ip.viewLayout = mkViewLayout(UI,height)
    ip.uiCallbacks = uiStruct2uiCallbacks(UI)
    ip.apiVersion = "1.1"
    local varList = {}
    for n,v in pairs(vars) do varList[#varList+1]={name=n,value=v} end
    ip.quickAppVariables = varList
    ip.typeTemplateInitialized=true
    return ip
  end

  local function replaceRequires(code)
    pcall(function()
        code = code:gsub([[require%s*%(%s*[%"%'](.-)[%"%']%s*%)]],
          function(m) 
            f = io.open(m..".lua")
            if f then
              local c = f:read("*all")
              local c2 = c:match("%-%-%-%-%-%-%-%-%-%-%- Code.-\n(.*)")
              return c2 or c
              --return "do\n"..c.."\nend\n"
            end
            return ""
          end)
      end)
    return code
  end

-- name of device - string
-- type of device - string, default "com.fibaro.binarySwitch"
-- code - string, Lua code
-- UI -- table with UI elements
--      {{{button='button1", text="L"},{button='button2'}}, -- 2 buttons  1 row
--      {{slider='slider1", text="L", min=100,max=99}},     -- 1 slider 1 row
--      {{label="label1",text="L"}}}                        -- 1 label 1 row
-- quickVars - quickAppVariables, {<var1>=<value1>,<var2>=<value2>,...}
-- dryrun - if true only returns the quickapp without deploying

  local function createQuickApp(args)
    local d = {} -- Our device
    d.name = args.name or "QuickApp"
    d.type = args.type or "com.fibaro.binarySensor"
    local body = args.code or ""
    body = replaceRequires(body)
    local UI = args.UI or {}
    local variables = args.quickVars or {}
    local dryRun = args.dryrun or false
    d.apiVersion = "1.1"
    d.initialProperties = makeInitialProperties(body,UI,variables,args.height)
    if dryRun then return d end
    --Log(LOG.SYS,"Creating device...")--..json.encode(d)) 
    if not d.initialProperties.uiCallbacks[1] then
      d.initialProperties.uiCallbacks = nil
    end
    local what,d1,res="updated"
    if args.id then
      d1,res = api.put("/devices/"..args.id,{
          properties={
            quickAppVariables = d.initialProperties.quickAppVariables,
            mainFunction = d.initialProperties.mainFunction,
            uiCallBacks = d.initialProperties.uiCallbacks,
          }
        })
    else
      d1,res = api.post("/quickApp/",d)
      what = "created"
    end
    if type(res)=='string' or res > 201 then 
      Log(LOG.ERROR,"D:%s,RES:%s",json.encode(d1),json.encode(res))
      return nil
    else 
      Log(LOG.SYS,"Device %s %s",d1.id or "",what)
      return d1
    end
  end

-- Create a Proxy device - will be named "Proxy "..name, returns deviceID if successful
  local function createProxy(name,tp,UI,vars)
    local ID,device = nil,nil
    if tonumber(name) then
      device = api.get("/devices/"..name)
      if device then name = device.name end
    end
    name = "Proxy "..name
    Log(LOG.SYS,"Proxy: Looking for QuickApp on HC3...")
    for _,d in pairs(api.get("/devices") or {}) do 
      if d.name==name then 
        device = d
        Log(LOG.SYS,"Proxy: Found ID:"..device.id)
        break 
      end 
    end
    ID   = device and device.id
    tp   = tp or "com.fibaro.binarySensor"
    vars = vars or {}
    UI   = UI or {}
    local code = {}
    code[#code+1] = [[
  local function urlencode (str) 
  return str and string.gsub(str ,"([^% w])",function(c) return string.format("%%% 02X",string.byte(c))  end) 
end
local function POST2IDE(path,payload)
    url = "http://"..IP..path
    net.HTTPClient():request(url,{options={method='POST',data=json.encode(payload)}})
end
local IGNORE={updateView=true,setVariable=true,updateProperty=true} -- Rewrite!!!!
function QuickApp:actionHandler(action) 
      if IGNORE[action.actionName] then 
        return self:callAction(action.actionName, table.unpack(action.args))
      end
      POST2IDE("/fibaroapiHC3/action/"..self.id,action) 
end
function QuickApp:UIHandler(UIEvent) POST2IDE("/fibaroapiHC3/ui/"..self.id,UIEvent) end
function QuickApp:CREATECHILD(id) self.childDevices[id]=QuickAppChild({id=id}) end
]]
    code[#code+1]= "function QuickApp:onInit()"
    code[#code+1]= " self:debug('"..name.."',' deviceId:',self.id)"
    code[#code+1]= " IP = self:getVariable('PROXYIP')"
    code[#code+1]= " function QuickApp:initChildDevices() end"    
    code[#code+1]= "end"

    code = table.concat(code,"\n")

    local newVars = {}
    if ID then
      for _,v in ipairs(device.properties.quickAppVariables or {}) do newVars[v.name]=v.value end   -- Move over vars from existing QA
      local nip = makeInitialProperties("",UI)
      local nUIstr = Util.prettyJson({nip.uiCallbacks,nip.viewLayout})
      local eUIstr = Util.prettyJson({device.properties.uiCallbacks or {},device.properties.viewLayout or {}})
      if nUIstr ~= eUIstr then 
        Log(LOG.SYS,"Proxy: QuickApp changed UI")
        api.delete("/devices/"..ID)
        ID = nil 
      end   
    end

    Log(LOG.SYS,ID and "Proxy: Reusing QuickApp proxy" or "Proxy: Creating new proxy")

    for k,v in pairs(vars) do newVars[k]=v end -- add user specified vars
    newVars["PROXYIP"] = Util.getIPaddress()..":"..hc3_emulator.webPort
    return createQuickApp{id=ID,name=name,type=tp,code=code,UI=UI,quickVars=newVars}
  end

  local function runQuickApp(args)
    local ptype         = hc3_emulator.type or "com.fibaro.binarySwitch"
    local UI            = hc3_emulator.UI or {}
    local quickVars     = hc3_emulator.quickVars or {}
    local name          = hc3_emulator.name or "My App"

    for k,v in pairs(quickVars) do 
      if type(v)=='string' and v:match("^%$CREDS") then
        local p = "return hc3_emulator.credentials"..v:match("^%$CREDS(.*)") 
        quickVars[k]=load(p)()
      end
    end

    local deviceStruct= {
      id=hc3_emulator.id or 999,name=name,type=ptype,
      properties={quickAppVariables=quickVars}
    }

    if hc3_emulator.offline then              -- Offline
      plugin.mainDeviceId = hc3_emulator.id or 999

    else -- Connected to something at the HC3...
      if hc3_emulator.id or hc3_emulator.proxy then
        if hc3_emulator.id then
          deviceStruct = api.get("/devices/"..hc3_emulator.id)
          assert(deviceStruct,format("hc3_emulator.start: QuickApp with id %s doesn't exist on HC3",hc3_emulator.id))
        elseif hc3_emulator.proxy then
          deviceStruct = createProxy(name, ptype, UI, quickVars)
          assert(deviceStruct,"hc3_emulator.start: Failed creating proxy")
        end
        plugin.isProxy = true
        Log(LOG.SYS,"Connected to HC3 device %s",deviceStruct.id)
      else -- No proxy
        if UI then 
          transformUI(UI)
          deviceStruct.properties.uiCallbacks  = uiStruct2uiCallbacks(UI)
        end
      end
    end

    plugin.mainDeviceId = deviceStruct.id
    plugin.type = deviceStruct.type

    Log(LOG.HEADER,"QuickApp '%s', deviceID:%s started at %s",deviceStruct.name,deviceStruct.id,os.date("%c"))

    if hc3_emulator.poll and not hc3_emulator.offline then Trigger.startPolling(tonumber(hc3_emulator.poll ) or 2000) end

    if plugin.isProxy then

      function HC3_handleEvent(e) -- If we have a HC3 proxy, we listen for UI events (PROXY)

        if e.type=='DeviceRemovedEvent' then
          quickApp:removeChildDevice(e.value.id) -- Remove it if it was a child of the QuickApp
        end
      end

    end

    quickApp = QuickApp(deviceStruct)
    _quickApp = quickApp
  end

  function onAction(event)
    Debug(_debugFlags.onAction,"onAction: %s",json.encode(event))
    local self = _quickApp
    if self.actionHandler then self:actionHandler(event)
    else
      local id = event.deviceId 
      if id == self.id then
        self:callAction(event.actionName, table.unpack(event.args))
      else
        local child = self.childDevices[id] 
        if child then child:callAction(event.actionName, table.unpack(event.args))
        else
          self:debug("Child with id:", id, " not found")
        end
      end
    end
  end

--"{\"eventType\":\"onReleased\",\"values\":[null],\"elementName\":\"bt\",\"deviceId\":726}"
--"{\"eventType\":\"onChanged\",\"values\":[80],\"elementName\":\"sl\",\"deviceId\":726}"
  function onUIEvent(event)
    Debug(_debugFlags.UIEvent,"UIEvent: %s",json.encode(event))
    local self = _quickApp
    if self.UIHandler then self:UIHandler(event)
    else
      local elm,etyp = event.elementName, event.eventType
      local cb = self.uiCallbacks
      if cb[elm] and cb[elm][etyp] then 
        if etyp=='onChanged' then
          QA.setWebUIValue(elm,'value',event.values[1]) 
        end
        return self:callAction(cb[elm][etyp], event)
      end
      self:warning("UI callback for element:", elm, " not found.")
    end
  end

  function self.copyQA(id)
    local device,res = api.get("/devices/"..id)
    if device then 
      print(device.properties.mainFunction)
    else print("Error:"..res) end
  end

  commandLines['pullqatobuffer']=self.copyQA

-- Export functions
  self.updateViewLayout = updateViewLayout
  self.createQuickApp = createQuickApp
  self.createProxy = createProxy
  self.start = runQuickApp
  return self
end

--------------- Scene functions and support ----------
function module.Scene()
  local self = {}
  local printf,split = Util.printf,Util.split
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
        assertf(res,"Bad date specifier '%s'",id) return res
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
        start = start+1; if start>m.max then start=m.min end  
      end
      res[#res+1] = stop
      if step > 1 then for i=1,#res,step do res2[#res2+1]=res[i] end; res=res2 end
      return res
    end

    table.maxn = table.maxn or function(t) return #t end

    local function map(f,l,s) s = s or 1; local r={} for i=s,table.maxn(l) do r[#r+1] = f(l[i]) end return r end
    local function parseDateStr(dateStr,last)
      local seq = split(dateStr," ")   -- min,hour,day,month,wday
      local lim = {{min=0,max=59},{min=0,max=23},{min=1,max=31},{min=1,max=12},{min=1,max=7},{min=2019,max=2030}}
      for i=1,6 do if seq[i]=='*' or seq[i]==nil then seq[i]=tostring(lim[i].min).."-"..lim[i].max end end
      seq = map(function(w) return split(w,",") end, seq)   -- split sequences "3,4"
      local month = os.date("*t",os.time()).month
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
        local h,m = (fibaro:getValue(1,sun)):match("(%d%d):(%d%d)")
        dateSeq[1]={[(h*60+m+offs)%60]=true}
        dateSeq[2]={[math.floor((h*60+m+offs)/60)]=true}
      end
    end
    local dateSeq = parseDateStr(dateStr)
    return function(ctx) -- Pretty efficient way of testing dates...
      local t = ctx or os.date("*t",os.time())
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

  local function midnight() local d = os.date("*t") d.min,d.hour,d.sec=0,0,0; return os.time(d) end 
  local function pd(s,op,t1,t2)
    local m = midnight()
    printf("%s %s %s %s",s,os.date("%H:%M",m+60*t1),op,os.date("%H:%M",m+60*t2))
  end

  local function compileCondition(cf)
    local triggers,dates = {},{}
    local compile

    local stdProps = {value=true,battery=true, ['global']=true}

    local condCompFuns = {
      ['=='] = function(a,b) return tostring(a) == tostring(b) end,
      ['>='] = function(a,b) return tostring(a) >= tostring(b) end,
      ['<'] = function(a,b) return tostring(a) < tostring(b) end,
      ['>'] = function(a,b) return tostring(a) > tostring(b) end,
      ['<='] = function(a,b) return tostring(a) <= tostring(b) end,
      ['!='] = function(a,b) return tostring(a) ~= tostring(b) end,
      ['n=='] = function(a,b) return a==b end,
      ['n>='] = function(a,b) return a>=b end,
      ['n<'] = function(a,b) return a<b end,
      ['n>'] = function(a,b) return a>b end,
      ['n<='] = function(a,b) return a<=b end,
      ['n!='] = function(a,b) return a~=b end,
      ['match'] = function(a,b) return a==b end,
      ['match=='] = function(a,b) return a==b end,
      ['match>='] = function(a,b) return a>=b end,
      ['match<'] = function(a,b) return a<b end,
      ['match>'] = function(a,b) return a>b end,
      ['match<='] = function(a,b) return a<=b end,
      ['match!='] = function(a,b) return a~=b end,
    }

    local compileCF = {
      ['all'] = function(e,all)
        local c,allt,cs = e.conditions,{},{}; for _,c0 in ipairs(c) do cs[#cs+1]=compile(c0,allt) end
        local test = function(ctx) if e.log then print(e.log) end for _,c in ipairs(cs) do if not c(ctx) then return false end end return true end
        if all and all[1] then allt[1]=all[1] else allt[1]=test end
        return test
      end,
      ['any'] = function(e)
        local c,cs = e.conditions,{}; for _,c0 in ipairs(c) do cs[#cs+1]=compile(c0,nil) end
        return function(ctx) if e.log then print(e.log) end  for _,c in ipairs(cs) do if c(ctx) then return true end end return false end
      end,
      ['device:*'] = function(c,all)
        local id,property,value,comp,tkey = c.id,c.property,c.value,condCompFuns[c.operator],c.property..c.id
        if c.isTrigger then triggers[id] = property end
        return function(ctx) 
          local cv = __fibaro_get_device_property(id,property)
          return comp(cv and cv.value,value)
        end
      end,
      ['device:centralSceneEvent'] = function(c,all)
        local id,keyAttribute,keyId = c.id,c.value.keyAttribute,c.value.keyId
        if c.isTrigger then triggers[id] = c.property end
        return function(ctx)
          ctx=ctx.centralSceneEvent or {}
          return id == ctx.id and ctx.value.keyId == keyId and ctx.value.keyAttribute == keyAttribute
        end
      end, 
      ['global-variable:*'] = function(c,all)
        local name,value,comp = c.property,c.value,condCompFuns[c.operator]
        if c.isTrigger then triggers[name] = true end
        return function(ctx)
          local cv = fibaro.getGlobalVariable(name)
          return comp(cv,value)
        end
      end, 
      ['date:sunset'] = function(c,all) 
        local comp,offset = condCompFuns["n"..c.operator],c.value
        local function mkRes(ctx) return {type='date', property='sunset', value=offset} end
        local test = function(ctx) if comp(ctx.hour*60+ctx.min,ctx.sunset+offset) then return mkRes(ctx) end end
        if c.isTrigger then dates[#dates+1]=function(ctx) if all[1] then return all[1](ctx) and mkRes(ctx) else return test(ctx) end end end
        return test
      end,
      ['date:sunrise'] = function(c,all)
        local comp,offset = condCompFuns["n"..c.operator],c.value
        local function mkRes(ctx) return {type='date', property='sunrise', value=offset} end
        local test = function(ctx) if comp(ctx.hour*60+ctx.min,ctx.sunrise+offset) then return mkRes() end end
        if c.isTrigger then dates[#dates+1]=function(ctx) if all[1] then return all[1](ctx) and mkRes(ctx) else return test(ctx) end end end
        return test
      end,
      ['date:cron'] = function(c,all)
        local test,comp = cronTest(table.concat(c.value," ")),condCompFuns[c.operator]
        local function mkRes(ctx) return {type='date', property='cron', value={ctx.min, ctx.hour, ctx.day, ctx.month, ctx.wday, ctx.year}} end
        local cronFun = function(ctx) if test(ctx) then return mkRes(ctx) end end
        if c.isTrigger then 
          dates[#dates+1] = function(ctx) if all[1] then return all[1](ctx) and mkRes(ctx) else return cronFun(ctx) end end
        end
        return function(ctx) return cronFun(ctx) end
      end,
    }

    function compile(c,all)
      if c.conditions and c.operator then return compileCF[c.operator](c,all)
      elseif c.type then
        local prop = c.property
        prop = c.type == 'global-variable' and "global" or prop
        local tp = c.type..":"..(stdProps[prop] and "*" or prop)
        if compileCF[tp] then return compileCF[tp](c,all) end
      end
      error(format("Bad condition:%s (%s)",json.encode(c),json.encode(cf)))
    end

    if not next(cf) then return function() return true end,triggers,dates end
    return compile(cf),triggers,dates
  end

--[[
manual
alarm
custom-event
date
device
global-variable
location
panic
profile
se-start
weather
climate
--]]

  local function toTime(str) local h,m=str:match("(%d+):(%d+)") return 60*h+m end
  local SUN = {}
  local function createCTX()
    local ctx = os.date("*t")
    if SUN.last ~= ctx.day then
      SUN.last,SUN.sunrise,SUN.sunset=ctx.day,toTime(fibaro.getValue(1,"sunriseHour")),toTime(fibaro.getValue(1,"sunsetHour"))
    end
    ctx.sunrise,ctx.sunset=SUN.sunrise,SUN.sunset
    return ctx
  end

  local function runScene()
    local condition,triggers,dates = compileCondition(hc3_emulator.conditions)
    Log(LOG.HEADER,"Scene started at %s",os.date("%c"))
    if hc3_emulator.runSceneAtStart or next(hc3_emulator.conditions)==nil then
      Timer.setTimeout(function() HC3_handleEvent({type = "manual", property = "execute"}) end,0)
    end
    Trigger.startPolling(tonumber(hc3_emulator.poll) or 2000) -- Start polling HC3 for triggers

    function HC3_handleEvent(e)
      local ctx = createCTX()

      if e.type=='device' and e.property=='centralSceneEvent' then
        ctx.centralSceneEvent = e
      end
      if e.type=='manual' and e.property=='execute' then
        sourceTrigger = e
        Timer.setTimeout(hc3_emulator.actions,0)
      elseif e.type=='device' and triggers[e.id]==e.property or
      e.type=='global-variable' and triggers[e.property] or
      e.type=='date' 
      then
        Log(LOG.DEBUG,"Scene trigger:%s",json.encode(e))
        if condition(ctx) then
          sourceTrigger = e
          Timer.setTimeout(hc3_emulator.actions,0)
        end
      end
    end

    if #dates>0 then --- Check cron expressions every minute
      local nxt = os.time()
      local function loop()
        local ctx = createCTX()
        for _,c in ipairs(dates) do
          local e = c(ctx)
          if e then 
            HC3_handleEvent(e); break 
          end
        end
        nxt = nxt+60
        setTimeout(loop,1000*(nxt-os.time()))
      end
      loop()
    end
  end

  self.start = runScene
  return self
end


--------------- Trigger functions and support --------
function module.Trigger()
  local self = {}
  local tickEvent = "ERTICK"

  local cache = { polling=false, devices={}, globals={}, centralSceneEvents={}} -- Caching values when we poll to reduce traffic to HC3...
  function cache.write(type,key,value) cache[type][key]=value end
  function cache.read(type,key) return hc3_emulator.speeding and hc3_emulator.polling and cache[type][key] end

  local function post(event) 
    if hc3_emulator.supressTrigger[event.type] then return end
    if HC3_handleEvent then HC3_handleEvent(event) end 
  end

  local EventTypes = { -- There are more, but these are what I seen so far...
    AlarmPartitionArmedEvent = function(self,d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
    AlarmPartitionBreachedEvent = function(self,d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
    HomeArmStateChangedEvent = function(self,d) post({type='alarm', property='homeArmed', value=d.newValue}) end,
    HomeBreachedEvent = function(self,d) post({type='alarm', property='homeBreached', value=d.breached}) end,
    WeatherChangedEvent = function(self,d) post({type='weather',property=d.change, value=d.newValue, old=d.oldValue}) end,
    GlobalVariableChangedEvent = function(self,d)
      cache.write('globals',d.variableName,{name=d.variableName, value = d.newValue, modified=os.time()})
      if d.variableName == tickEvent then return end
      post({type='global-variable', property=d.variableName, value=d.newValue, old=d.oldValue})
    end,
    DevicePropertyUpdatedEvent = function(self,d)
      if d.property=='quickAppVariables' then 
        local old={}; for _,v in ipairs(d.oldValue) do old[v.name] = v.value end -- Todo: optimize
        for _,v in ipairs(d.newValue) do
          if v.value ~= old[v.name] then
            post({type='quickvar', name=v.name, value=v.value, old=old[v.name]})
          end
        end
      else
        --if d.property:match("^ui%.") then return end
        if d.property == 'icon' then return end
        cache.write('devices',d.property..d.id,{value=d.newValue, modified=os.time()})    
        post({type='device', id=d.id, property=d.property, value=d.newValue, old=d.oldValue})
      end
    end,
    CentralSceneEvent = function(self,d) 
      cache.write('centralSceneEvents',d.deviceId,d) 
      post({type='device', property='centralSceneEvent', id=d.deviceId, value = {keyId=d.keyId, keyAttribute=d.keyAttribute}}) 
    end,
    AccessControlEvent = function(self,d) 
      cache.write('accessControlEvent',d.id,d)
      post({type='device', property='accessControlEvent', id = d.deviceID, value=d}) 
    end,
    RoomModifiedEvent = function(self,d) end,
    CustomEvent = function(self,d) if d.name == tickEvent then return else post({type='custom-event', name=d.name}) end end,
    PluginChangedViewEvent = function(self,d) post({type='PluginChangedViewEvent', value=d}) end,
    WizardStepStateChangedEvent = function(self,d) post({type='WizardStepStateChangedEvent', value=d})  end,
    UpdateReadyEvent = function(self,d) post({type='UpdateReadyEvent', value=d}) end,
    SceneRunningInstancesEvent = function(self,d) post({type='SceneRunningInstancesEvent', value=d}) end,
    DeviceRemovedEvent = function(self,d)  post({type='DeviceRemovedEvent', value=d}) end,
    DeviceChangedRoomEvent = function(self,d)  post({type='DeviceChangedRoomEvent', value=d}) end,    
    DeviceCreatedEvent = function(self,d)  post({type='DeviceCreatedEvent', value=d}) end,
    DeviceModifiedEvent = function(self,d) post({type='DeviceModifiedEvent', value=d}) end,
    SceneStartedEvent = function(self,d)   post({type='SceneStartedEvent', value=d}) end,
    SceneFinishedEvent = function(self,d)  post({type='SceneFinishedEvent', value=d})end,
    -- {"data":{"id":219},"type":"RoomModifiedEvent"}
    SceneRemovedEvent = function(self,d)  post({type='SceneRemovedEvent', value=d}) end,
    PluginProcessCrashedEvent = function(self,d) post({type='PluginProcessCrashedEvent', value=d}) end,
    onUIEvent = function(self,d) post({type='uievent', deviceID=d.deviceId, name=d.elementName}) end,
    ActiveProfileChangedEvent = function(self,d) 
      post({type='profile',property='activeProfile',value=d.newActiveProfile, old=d.oldActiveProfile}) 
    end,
    OnlineStatusUpdatedEvent = function(self,d)  post({type='OnlineStatusUpdatedEvent', value=d}) end,
    NotificationCreatedEvent = function(d) end,
    NotificationRemovedEvent = function(d) end,
  }

  local function checkEvents(events)
    for _,e in ipairs(events) do
      local eh = EventTypes[e.type]
      if eh then eh(_,e.data)
      elseif eh==nil then Log(LOG.WARNING,"Unhandled event:%s -- please report",json.encode(e)) end
    end
    self.refreshStates.addEvents(events)
  end

  local lastRefresh = 0

  local function pollOnce()
    if _debugFlags.refreshLoop then Log(LOG.DEBUG,"*") end
    local states = api.get("/refreshStates?last=" .. lastRefresh)
    if states then
      lastRefresh=states.last
      if states.events and #states.events>0 then checkEvents(states.events) end
    end
  end

  local function pollOnce() -- Doesn't work, we need predictable returns
    if hc3_emulator.offline then return Offline.api("GET","/refreshStates?last=" .. lastRefresh) end
    local resp = {}
    local req={ method="GET",
      url = "http://"..hc3_emulator.credentials.ip.."/api/refreshStates?last=" .. lastRefresh,
      sink = ltn12.sink.table(resp),
      user=hc3_emulator.credentials.user,
      password=hc3_emulator.credentials.pwd,
      headers={}
    }
    req.headers["Accept"] = '*/*'
    req.headers["X-Fibaro-Version"] = 2
    local to = http.TIMEOUT
    http.TIMEOUT = 1 -- TIMEOUT == 0 doesn't work...
    local r, c, h = http.request(req)
    http.TIMEOUT = to
    if not r then return nil,c, h end
    if c>=200 and c<300 then
      local states = resp[1] and json.decode(table.concat(resp))
      if states then
        lastRefresh=states.last
        if states.events and #states.events>0 then checkEvents(states.events) end
      end
    end
    return nil,c, h
  end

  local function pollEvents(interval)
    local INTERVAL = interval or 0 -- every second, could do more often...

    api.post("/globalVariables",{name=tickEvent,value="Tock!"})
    cache.polling = true -- Our loop will populate cache with values - no need to fetch from HC3

    local function pollRefresh()
      pollOnce()
      Timer.setTimeout(pollRefresh,INTERVAL,"RefreshState").isSystem=true
      fibaro.setGlobalVariable(tickEvent,tostring(os.clock())) -- emit hangs
    end
    Timer.setTimeout(pollRefresh,0).isSystem=true
  end

  if not HC3_handleEvent then -- default handle event routine
    function HC3_handleEvent(e)
      if _debugFlags.trigger then Log(LOG.DEBUG,"Incoming trigger:"..json.encode(e)) end
    end
  end 

  function hc3_emulator.post(ev,t)
    assert(type(ev)=='table' and ev.type,"Bad event format:"..ev)
    t = t or 0
    setTimeout(function() HC3_handleEvent(ev) end,t).isSystem=true
  end

--------------- refreshState handling ---------------
  local function createRefreshStateQueue(size)
    local self = {}
    local QLAST = 300
    local function mkQeueu(size)
      self = { size=size, queue={} }
      local queue,head,tail = self.queue,1,1
      function self.pop()
        if head==tail then return end
        local e = queue[head]
        head = head-1; if head==0 then head = size end
        return e
      end
      function self.push(e) 
        head=head % size + 1
        if head==tail then tail = tail % size + 1 end
        queue[head]=e
      end
      function self.dump()
        local h1,t1 = head,tail
        local e = self.pop()
        while e do print(json.encode(e)) e = self.pop() end
        head,tail = h1,t1
      end
      return self
    end

    self.eventQueue=mkQeueu(size) --- 1..QUEUELENGTH
    local eventQueue = self.eventQueue

    function self.addEvents(events) -- {last=num,events={}}
      QLAST=QLAST+1
      events = events[1] and events or {events}
      eventQueue.push({last=QLAST, events=events})
    end

    function self.getEvents(last)
      local res1,res2 = {},{}
      while true do
        local e = eventQueue.pop()     ----    5,6,7,8    6
        if e and e.last > last then 
          res1[#res1+1]=e
        else break end
      end
      if #res1==0 then return { last=last } end
      last = res1[1].last   ----  { 1, 2, 3, 4, 5}
      for i=#res1,1,-1 do
        local es = res1[i].events or {}
        for j=#es,1,-1 do res2[#res2+1]=es[j] end
      end
      return {last = last, events = res2}
    end
    self.dump = eventQueue.dump
    return self
  end

  self.refreshStates = createRefreshStateQueue(200)

  self.eventTypes = EventTypes
  self.startPolling = pollEvents
  self.pollOneEvent = pollOnce
  self.cache = cache
  return self
end

-------------- Utilities -----------------------------
function module.Utilities()
  local self = {}

  function class(name)
    local cl,parent = {},nil
    cl._name = name
    cl.__index = cl
    local mt = {}
    mt.__tostring = function(_) return string.format("<Class %s>",name) end

    local fun=function(parent2) 
      assert(parent2,"Missing parent, use without () if no parent")
      parent = parent2
      for n,p in pairs(parent or {}) do cl[n]=p end
      cl._name = name
      cl.__index = cl
      return cl
    end

    mt.__call = function(class_tbl, ...)
      local obj = {}
      setmetatable(obj,cl)
      if cl.__init then cl.__init(obj,...)
      else 
        if parent and parent.__init then parent.__init(obj, ...) end
      end
      return obj
    end

    setmetatable(cl,mt)
    if _ENV then _ENV[name]=cl else _G[name]=cl end
    if parent and parent._name == 'QuickAppChild' then -- Hack to keep track of child classes.... not used?
      QuickAppChildren[name]=cl
    end
    return fun
  end


  if not class then class=self.class end -- If we already have 'class' from Luabind - let's hope it wors as a substitute....

  function self.urlencode (str) 
    return str and string.gsub(str ,"([^% w])",function(c) return format("%%% 02X",string.byte(c))  end) 
  end
  function self.urldecode(str) return str:gsub('%%(%x%x)',function (x) return string.char(tonumber(x,16)) end) end
  function self.safeDecode(x) local stat,res = pcall(function() return json.decode(x) end) return stat and res end

  local function logHeader(len,str)
    if #str % 2 == 1 then str=str.." " end
    local n = #str+2
    return string.rep("-",len/2-n/2).." "..str.." "..string.rep("-",len/2-n/2)
  end

  local ZBCOLORMAP = {
    black="\027[30m",brown="\027[31m",green="\027[32m",orange="\027[33m",
    navy="\027[34m",purple="\027[35m",teal="\027[36m",grey="\027[37m",
    red="\027[31;1m",tomato="\027[31;1m",neon="\027[32;1m",yellow="\027[33;1m",
    blue="\027[34;1m",magenta="\027[35;1m",cyan="\027[36;1m",white="\027[37;1m",
  }

  self.ZBCOLORMAP = ZBCOLORMAP
  LOG = { LOG="LOG  ", WARNING="WARN ", SYS="SYS  ", DEBUG="SDBG ", ERROR='ERROR', HEADER='HEADER'}
  local DEBUGCOLORS = {
    [LOG.LOG]='navy', [LOG.WARNING]='orange', [LOG.DEBUG]='blue', 
    [LOG.SYS]='purple', [LOG.ERROR]='red',[LOG.HEADER]='blue'
  }

  function Debug(flag,...) if flag then Log(LOG.DEBUG,...) end end
  function Log(flag,arg1,...)
    local args={...}
    local stat,res = pcall(function() 
        local str = #args==0 and arg1 or format(arg1,table.unpack(args))
        local color = "black"
        if hc3_emulator.colorDebug then
          color = DEBUGCOLORS[flag] or color
          color = ZBCOLORMAP[color]
          if flag == LOG.HEADER then
            print(color..logHeader(100,str).."\027[0m")
            return str
          else
            flag = format('%s%s\027[0m', color, flag)
          end
        end
        if flag == LOG.HEADER then print(logHeader(100,str))
        else
          print(format("%s |%s|: %s",os.date("[%d.%m.%Y] [%X]"),flag,str))
          return str
        end
      end)
    if not stat then error(res) end
  end

  function self.parseDate(dateStr) --- Format 10:00:00 5/12/2020
    local h,m,s = dateStr:match("(%d+):(%d+):?(%d*)")
    local d,mon,y = dateStr:match("(%d+)/(%d+)/?(%d*)")
    s = s~="" and s or 0
    local t = os.date("*t")
    t.hour = tonumber(h) or t.hour
    t.min = tonumber(m) or t.min
    t.sec = tonumber(s) or t.sec
    t.day = tonumber(d) or t.day
    t.month = tonumber(mon) or t.month
    t.year = tonumber(y) or t.year
    return os.time(t)
  end

  function self.printf(arg1,...) local args={...} if #args==0 then print(arg1) else print(format(arg1,...)) end end
  function self.split(s, sep)
    local fields = {}
    sep = sep or " "
    local pattern = format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    return fields
  end

  function self.map(f,l) local r={}; for _,e in ipairs(l) do r[#r+1]=f(e) end; return r end
  function self.mapf(f,l) for _,e in ipairs(l) do f(e) end; end
  function self.mapk(f,l) local r={}; for k,v in pairs(l) do r[k]=f(v) end; return r end
  function self.mapkv(f,l) local r={}; for k,v in pairs(l) do k,v=f(k,v) r[k]=v end; return r end
  local function transform(obj,tf)
    if type(obj) == 'table' then
      local res = {} for l,v in pairs(obj) do res[l] = transform(v,tf) end 
      return res
    else return tf(obj) end
  end
  function self.copy(obj) return transform(obj, function(o) return o end) end
  local function equal(e1,e2)
    local t1,t2 = type(e1),type(e2)
    if t1 ~= t2 then return false end
    if t1 ~= 'table' and t2 ~= 'table' then return e1 == e2 end
    for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
    for k2,v2 in pairs(e2) do if e1[k2] == nil or not equal(e1[k2],v2) then return false end end
    return true
  end

  do
    local sortKeys = {"type","device","deviceID","value","oldValue","val","key","arg","event","events","msg","res"}
    local sortOrder={}
    for i,s in ipairs(sortKeys) do sortOrder[s]="\n"..string.char(i+64).." "..s end
    local function keyCompare(a,b)
      local av,bv = sortOrder[a] or a, sortOrder[b] or b
      return av < bv
    end

    function self.prettyJsonFlat(e) -- our own json encode, as we don't have 'pure' json structs, and sorts keys in order (i.e. "stable" output)
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
  end
  self.prettyJson = self.prettyJsonFlat

  do -- Used for print device tabel structs
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

    function self.prettyJsonStruct(t)
      local res = {}
      local function isArray(t) return type(t)=='table' and t[1] end
      local function isEmpty(t) return type(t)=='table' and next(t)==nil end
      local function isKeyVal(t) return type(t)=='table' and t[1]==nil and next(t)~=nil end
      local function printf(tab,fmt,...) res[#res+1] = string.rep(' ',tab)..string.format(fmt,...) end
      local function pretty(tab,t,key)
        if type(t)=='table' then
          if isEmpty(t) then printf(0,"[]") return end
          if isArray(t) then
            printf(key and tab or 0,"[\n")
            for i,k in ipairs(t) do
              local cr = pretty(tab+1,k,true)
              if i ~= #t then printf(0,',') end
              printf(tab+1,'\n')
            end
            printf(tab,"]")
            return true
          end
          local r = {}
          for k,v in pairs(t) do r[#r+1]=k end
          table.sort(r,keyCompare)
          printf(key and tab or 0,"{\n")
          for i,k in ipairs(r) do
            printf(tab+1,'"%s":',k)
            local cr =  pretty(tab+1,t[k])
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
          printf(key and tab or 0,'"%s"',t)
        end
      end
      pretty(0,t,true)
      return table.concat(res,"")
    end
  end

  local function patchFibaro(name)
    local oldF,flag = fibaro[name],"f"..name
    fibaro[name] = function(...)
      local args = {...}
      local res = {oldF(...)}
      if _debugFlags[flag] then
        args = #args==0 and "" or json.encode(args):sub(2,-2)
        Log(LOG.LOG,"fibaro.%s(%s) => %s",name,args,#res==0 and "nil" or #res==1 and res[1] or res)
      end
      return table.unpack(res)
    end
  end

  function self.traceFibaro()
    patchFibaro("call")
    -- patchFibaro("get")
  end

  function self.cleanUpVarsAndEvents()
    local vs,c1,c2 = api.get("/globalVariables/"),0,0
    for _,v in ipairs(vs or {}) do
      if v.name:match("RPC%d+") then
        api.delete("/globalVariables/"..v.name)
        c1=c1+1
      end
    end
    vs = api.get("/customEvents/")
    for _,v in ipairs(vs or {}) do
      if v.name:match("PROXY%d+_%d+") then
        api.delete("/customeEvents/"..v.name)
        c2=c2+1
      end
    end
    Log(LOG.SYS,"Deleted %s RPC variables",c1)
    Log(LOG.SYS,"Deleted %s PROXY events",c2)
  end

  function self.base64(data)
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

  local IPADDRESS = nil
  function self.getIPaddress()
    if IPADDRESS then return IPADDRESS end
    local someRandomIP = "192.168.1.122" --This address you make up
    local someRandomPort = "3102" --This port you make up  
    local mySocket = socket.udp() --Create a UDP socket like normal
    mySocket:setpeername(someRandomIP,someRandomPort) 
    local myDevicesIpAddress,_ = mySocket:getsockname()-- returns IP and Port
    IPADDRESS = myDevicesIpAddress == "0.0.0.0" and "127.0.0.1" or myDevicesIpAddress
    return IPADDRESS
  end

------------------- Sunset/Sunrise ---------------
-- \fibaro\usr\share\lua\5.2\common\lustrous.lua ﻿based on the United States Naval Observatory

  local function sunturnTime(date, rising, latitude, longitude, zenith, local_offset)
    local rad,deg,floor = math.rad,math.deg,math.floor
    local frac = function(n) return n - floor(n) end
    local cos = function(d) return math.cos(rad(d)) end
    local acos = function(d) return deg(math.acos(d)) end
    local sin = function(d) return math.sin(rad(d)) end
    local asin = function(d) return deg(math.asin(d)) end
    local tan = function(d) return math.tan(rad(d)) end
    local atan = function(d) return deg(math.atan(d)) end

    local function day_of_year(date)
      local n1 = floor(275 * date.month / 9)
      local n2 = floor((date.month + 9) / 12)
      local n3 = (1 + floor((date.year - 4 * floor(date.year / 4) + 2) / 3))
      return n1 - (n2 * n3) + date.day - 30
    end

    local function fit_into_range(val, min, max)
      local range,count = max - min
      if val < min then count = floor((min - val) / range) + 1; return val + count * range
      elseif val >= max then count = floor((val - max) / range) + 1; return val - count * range
      else return val end
    end

    -- Convert the longitude to hour value and calculate an approximate time
    local n,lng_hour,t =  day_of_year(date), longitude / 15, nil
    if rising then t = n + ((6 - lng_hour) / 24) -- Rising time is desired
    else t = n + ((18 - lng_hour) / 24) end -- Setting time is desired
    local M = (0.9856 * t) - 3.289 -- Calculate the Sun^s mean anomaly
    -- Calculate the Sun^s true longitude
    local L = fit_into_range(M + (1.916 * sin(M)) + (0.020 * sin(2 * M)) + 282.634, 0, 360)
    -- Calculate the Sun^s right ascension
    local RA = fit_into_range(atan(0.91764 * tan(L)), 0, 360)
    -- Right ascension value needs to be in the same quadrant as L
    local Lquadrant = floor(L / 90) * 90
    local RAquadrant = floor(RA / 90) * 90
    RA = RA + Lquadrant - RAquadrant; RA = RA / 15 -- Right ascension value needs to be converted into hours
    local sinDec = 0.39782 * sin(L) -- Calculate the Sun's declination
    local cosDec = cos(asin(sinDec))
    local cosH = (cos(zenith) - (sinDec * sin(latitude))) / (cosDec * cos(latitude)) -- Calculate the Sun^s local hour angle
    if rising and cosH > 1 then return "N/R" -- The sun never rises on this location on the specified date
    elseif cosH < -1 then return "N/S" end -- The sun never sets on this location on the specified date

    local H -- Finish calculating H and convert into hours
    if rising then H = 360 - acos(cosH)
    else H = acos(cosH) end
    H = H / 15
    local T = H + RA - (0.06571 * t) - 6.622 -- Calculate local mean time of rising/setting
    local UT = fit_into_range(T - lng_hour, 0, 24) -- Adjust back to UTC
    local LT = UT + local_offset -- Convert UT value to local time zone of latitude/longitude
    return os.time({day = date.day,month = date.month,year = date.year,hour = floor(LT),min = math.modf(frac(LT) * 60)})
  end

  local function getTimezone() local now = os.time() return os.difftime(now, os.time(os.date("!*t", now))) end

  local function sunCalc(time)
    local hc3Location = api.get("/settings/location")
    local lat = hc3Location.latitude or 0
    local lon = hc3Location.longitude or 0
    local utc = getTimezone() / 3600
    local zenith,zenith_twilight = 90.83, 96.0 -- sunset/sunrise 90°50′, civil twilight 96°0′

    local date = os.date("*t",time or os.time())
    if date.isdst then utc = utc + 1 end
    local rise_time = osdate("*t", sunturnTime(date, true, lat, lon, zenith, utc))
    local set_time = osdate("*t", sunturnTime(date, false, lat, lon, zenith, utc))
    local rise_time_t = osdate("*t", sunturnTime(date, true, lat, lon, zenith_twilight, utc))
    local set_time_t = osdate("*t", sunturnTime(date, false, lat, lon, zenith_twilight, utc))
    local sunrise = format("%.2d:%.2d", rise_time.hour, rise_time.min)
    local sunset = format("%.2d:%.2d", set_time.hour, set_time.min)
    local sunrise_t = format("%.2d:%.2d", rise_time_t.hour, rise_time_t.min)
    local sunset_t = format("%.2d:%.2d", set_time_t.hour, set_time_t.min)
    return sunrise, sunset, sunrise_t, sunset_t
  end

  self.sunCalc = sunCalc
  return self
end

--------------- json functions ------------------------
function module.Json()
--
-- Copyright (c) 2019 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

  local json = { _version = "0.1.2" }

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

  local encode

  local escape_char_map = {
    [ "\\" ] = "\\\\",
    [ "\"" ] = "\\\"",
    [ "\b" ] = "\\b",
    [ "\f" ] = "\\f",
    [ "\n" ] = "\\n",
    [ "\r" ] = "\\r",
    [ "\t" ] = "\\t",
  }

  local escape_char_map_inv = { [ "\\/" ] = "/" }
  for k, v in pairs(escape_char_map) do
    escape_char_map_inv[v] = k
  end


  local function escape_char(c)
    return escape_char_map[c] or string.format("\\u%04x", c:byte())
  end


  local function encode_nil(val)
    return "null"
  end


  local function encode_table(val, stack)
    local res = {}
    stack = stack or {}

    -- Circular reference?
    if stack[val] then error("circular reference") end

    stack[val] = true

    if rawget(val, 1) ~= nil or next(val) == nil then
      -- Treat as array -- check keys are valid and it is not sparse
      local n = 0
      for k in pairs(val) do
        if type(k) ~= "number" then
          error("invalid table: mixed or invalid key types")
        end
        n = n + 1
      end
      if n ~= #val then
        error("invalid table: sparse array")
      end
      -- Encode
      for _, v in ipairs(val) do
        table.insert(res, encode(v, stack))
      end
      stack[val] = nil
      return "[" .. table.concat(res, ",") .. "]"

    else
      -- Treat as an object
      for k, v in pairs(val) do
        if type(k) ~= "string" then
          error("invalid table: mixed or invalid key types")
        end
        table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
      end
      stack[val] = nil
      return "{" .. table.concat(res, ",") .. "}"
    end
  end


  local function encode_string(val)
    return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
  end


  local function encode_number(val)
    -- Check for NaN, -inf and inf
    if val ~= val or val <= -math.huge or val >= math.huge then
      error("unexpected number value '" .. tostring(val) .. "'")
    end
    return string.format("%.14g", val)
  end

  local type_func_map = {
    [ "nil"     ] = encode_nil,
    [ "table"   ] = encode_table,
    [ "string"  ] = encode_string,
    [ "number"  ] = encode_number,
    [ "boolean" ] = tostring,
    [ "function" ] = tostring,
  }

  encode = function(val, stack)
    local t = type(val)
    local f = type_func_map[t]
    if f then
      return f(val, stack)
    end
    error("unexpected type '" .. t .. "'")
  end

  function json.encode(val)
    return ( encode(val) )
  end

-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

  local parse

  local function create_set(...)
    local res = {}
    for i = 1, select("#", ...) do
      res[ select(i, ...) ] = true
    end
    return res
  end

  local space_chars   = create_set(" ", "\t", "\r", "\n")
  local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
  local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
  local literals      = create_set("true", "false", "null")

  local literal_map = {
    [ "true"  ] = true,
    [ "false" ] = false,
    [ "null"  ] = nil,
  }

  local function next_char(str, idx, set, negate)
    for i = idx, #str do
      if set[str:sub(i, i)] ~= negate then
        return i
      end
    end
    return #str + 1
  end


  local function decode_error(str, idx, msg)
    local line_count = 1
    local col_count = 1
    for i = 1, idx - 1 do
      col_count = col_count + 1
      if str:sub(i, i) == "\n" then
        line_count = line_count + 1
        col_count = 1
      end
    end
    error( string.format("%s at line %d col %d", msg, line_count, col_count) )
  end


  local function codepoint_to_utf8(n)
    -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
    local f = math.floor
    if n <= 0x7f then
      return string.char(n)
    elseif n <= 0x7ff then
      return string.char(f(n / 64) + 192, n % 64 + 128)
    elseif n <= 0xffff then
      return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
    elseif n <= 0x10ffff then
      return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
        f(n % 4096 / 64) + 128, n % 64 + 128)
    end
    error( string.format("invalid unicode codepoint '%x'", n) )
  end


  local function parse_unicode_escape(s)
    local n1 = tonumber( s:sub(3, 6),  16 )
    local n2 = tonumber( s:sub(9, 12), 16 )
    -- Surrogate pair?
    if n2 then
      return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
    else
      return codepoint_to_utf8(n1)
    end
  end


  local function parse_string(str, i)
    local has_unicode_escape = false
    local has_surrogate_escape = false
    local has_escape = false
    local last
    for j = i + 1, #str do
      local x = str:byte(j)

      if x < 32 then
        decode_error(str, j, "control character in string")
      end

      if last == 92 then -- "\\" (escape char)
        if x == 117 then -- "u" (unicode escape sequence)
          local hex = str:sub(j + 1, j + 5)
          if not hex:find("%x%x%x%x") then
            decode_error(str, j, "invalid unicode escape in string")
          end
          if hex:find("^[dD][89aAbB]") then
            has_surrogate_escape = true
          else
            has_unicode_escape = true
          end
        else
          local c = string.char(x)
          if not escape_chars[c] then
            decode_error(str, j, "invalid escape char '" .. c .. "' in string")
          end
          has_escape = true
        end
        last = nil

      elseif x == 34 then -- '"' (end of string)
        local s = str:sub(i + 1, j - 1)
        if has_surrogate_escape then
          s = s:gsub("\\u[dD][89aAbB]..\\u....", parse_unicode_escape)
        end
        if has_unicode_escape then
          s = s:gsub("\\u....", parse_unicode_escape)
        end
        if has_escape then
          s = s:gsub("\\.", escape_char_map_inv)
        end
        return s, j + 1

      else
        last = x
      end
    end
    decode_error(str, i, "expected closing quote for string")
  end

  local function parse_number(str, i)
    local x = next_char(str, i, delim_chars)
    local s = str:sub(i, x - 1)
    local n = tonumber(s)
    if not n then
      decode_error(str, i, "invalid number '" .. s .. "'")
    end
    return n, x
  end

  local function parse_literal(str, i)
    local x = next_char(str, i, delim_chars)
    local word = str:sub(i, x - 1)
    if not literals[word] then
      decode_error(str, i, "invalid literal '" .. word .. "'")
    end
    return literal_map[word], x
  end

  local function parse_array(str, i)
    local res = {}
    local n = 1
    i = i + 1
    while 1 do
      local x
      i = next_char(str, i, space_chars, true)
      -- Empty / end of array?
      if str:sub(i, i) == "]" then
        i = i + 1
        break
      end
      -- Read token
      x, i = parse(str, i)
      res[n] = x
      n = n + 1
      -- Next token
      i = next_char(str, i, space_chars, true)
      local chr = str:sub(i, i)
      i = i + 1
      if chr == "]" then break end
      if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
    end
    return res, i
  end

  local function parse_object(str, i)
    local res = {}
    i = i + 1
    while 1 do
      local key, val
      i = next_char(str, i, space_chars, true)
      -- Empty / end of object?
      if str:sub(i, i) == "}" then
        i = i + 1
        break
      end
      -- Read key
      if str:sub(i, i) ~= '"' then
        decode_error(str, i, "expected string for key")
      end
      key, i = parse(str, i)
      -- Read ':' delimiter
      i = next_char(str, i, space_chars, true)
      if str:sub(i, i) ~= ":" then
        decode_error(str, i, "expected ':' after key")
      end
      i = next_char(str, i + 1, space_chars, true)
      -- Read value
      val, i = parse(str, i)
      -- Set
      res[key] = val
      -- Next token
      i = next_char(str, i, space_chars, true)
      local chr = str:sub(i, i)
      i = i + 1
      if chr == "}" then break end
      if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
    end
    return res, i
  end

  local char_func_map = {
    [ '"' ] = parse_string,
    [ "0" ] = parse_number,
    [ "1" ] = parse_number,
    [ "2" ] = parse_number,
    [ "3" ] = parse_number,
    [ "4" ] = parse_number,
    [ "5" ] = parse_number,
    [ "6" ] = parse_number,
    [ "7" ] = parse_number,
    [ "8" ] = parse_number,
    [ "9" ] = parse_number,
    [ "-" ] = parse_number,
    [ "t" ] = parse_literal,
    [ "f" ] = parse_literal,
    [ "n" ] = parse_literal,
    [ "[" ] = parse_array,
    [ "{" ] = parse_object,
  }

  parse = function(str, idx)
    local chr = str:sub(idx, idx)
    local f = char_func_map[chr]
    if f then
      return f(str, idx)
    end
    decode_error(str, idx, "unexpected character '" .. chr .. "'")
  end

  function json.decode(str)
    if type(str) ~= "string" then
      error("expected argument of type string, got " .. type(str))
    end
    local res, idx = parse(str, next_char(str, 1, space_chars, true))
    idx = next_char(str, idx, space_chars, true)
    if idx <= #str then
      decode_error(str, idx, "trailing garbage")
    end
    return res
  end

  -- /api/devices/hierarchy 5.030.45
  typeHierarchy = 
[[{"type":"com.fibaro.device","children":[{"type":"com.fibaro.zwaveDevice","children":[]},{"type":"com.fibaro.zwaveController","children":[]},{"type":"com.fibaro.weather","children":[{"type":"com.fibaro.yrWeather","children":[]},{"type":"com.fibaro.WeatherProvider","children":[]}]},{"type":"com.fibaro.usbPort","children":[]},{"type":"com.fibaro.setPointForwarder","children":[]},{"type":"com.fibaro.sensor","children":[{"type":"com.fibaro.multilevelSensor","children":[{"type":"com.fibaro.windSensor","children":[]},{"type":"com.fibaro.temperatureSensor","children":[]},{"type":"com.fibaro.seismometer","children":[]},{"type":"com.fibaro.rainSensor","children":[]},{"type":"com.fibaro.powerSensor","children":[]},{"type":"com.fibaro.lightSensor","children":[]},{"type":"com.fibaro.humiditySensor","children":[]}]},{"type":"com.fibaro.binarySensor","children":[{"type":"com.fibaro.securitySensor","children":[{"type":"com.fibaro.satelZone","children":[]},{"type":"com.fibaro.motionSensor","children":[{"type":"com.fibaro.FGMS001","children":[{"type":"com.fibaro.FGMS001v2","children":[]}]}]},{"type":"com.fibaro.envisaLinkZone","children":[]},{"type":"com.fibaro.dscZone","children":[]},{"type":"com.fibaro.doorWindowSensor","children":[{"type":"com.fibaro.windowSensor","children":[]},{"type":"com.fibaro.rollerShutterSensor","children":[]},{"type":"com.fibaro.gateSensor","children":[]},{"type":"com.fibaro.doorSensor","children":[]},{"type":"com.fibaro.FGDW002","children":[]}]}]},{"type":"com.fibaro.safetySensor","children":[]},{"type":"com.fibaro.rainDetector","children":[]},{"type":"com.fibaro.lifeDangerSensor","children":[{"type":"com.fibaro.heatDetector","children":[]},{"type":"com.fibaro.gasDetector","children":[{"type":"com.fibaro.smokeSensor","children":[{"type":"com.fibaro.FGSS001","children":[]}]},{"type":"com.fibaro.coDetector","children":[{"type":"com.fibaro.FGCD001","children":[]}]}]},{"type":"com.fibaro.floodSensor","children":[{"type":"com.fibaro.FGFS101","children":[]}]},{"type":"com.fibaro.fireDetector","children":[]}]}]},{"type":"com.fibaro.accelerometer","children":[]}]},{"type":"com.fibaro.securityMonitoring","children":[{"type":"com.fibaro.intercom","children":[{"type":"com.fibaro.mobotix","children":[]},{"type":"com.fibaro.heliosGold","children":[]},{"type":"com.fibaro.heliosBasic","children":[]},{"type":"com.fibaro.alphatechFarfisa","children":[]}]},{"type":"com.fibaro.doorLock","children":[{"type":"com.fibaro.schlage","children":[]},{"type":"com.fibaro.polyControl","children":[]},{"type":"com.fibaro.kwikset","children":[]},{"type":"com.fibaro.gerda","children":[]}]},{"type":"com.fibaro.camera","children":[{"type":"com.fibaro.ipCamera","children":[{"type":"com.fibaro.videoGate","children":[{"type":"com.fibaro.fibaroIntercom","children":[]}]}]}]},{"type":"com.fibaro.alarmPartition","children":[{"type":"com.fibaro.satelPartition","children":[]},{"type":"com.fibaro.envisaLinkPartition","children":[]},{"type":"com.fibaro.dscPartition","children":[]}]}]},{"type":"com.fibaro.samsungWasher","children":[]},{"type":"com.fibaro.samsungSmartAppliances","children":[]},{"type":"com.fibaro.samsungRobotCleaner","children":[]},{"type":"com.fibaro.samsungRefrigerator","children":[]},{"type":"com.fibaro.samsungOven","children":[]},{"type":"com.fibaro.samsungDryer","children":[]},{"type":"com.fibaro.samsungDishwasher","children":[]},{"type":"com.fibaro.samsungAirPurifier","children":[]},{"type":"com.fibaro.russoundXZone4","children":[]},{"type":"com.fibaro.russoundXSource","children":[]},{"type":"com.fibaro.russoundX5","children":[]},{"type":"com.fibaro.russoundMCA88X","children":[]},{"type":"com.fibaro.russoundController","children":[]},{"type":"com.fibaro.powerMeter","children":[]},{"type":"com.fibaro.planikaFLA3","children":[]},{"type":"com.fibaro.multimedia","children":[{"type":"com.fibaro.xbmc","children":[]},{"type":"com.fibaro.wakeOnLan","children":[]},{"type":"com.fibaro.sonosSpeaker","children":[]},{"type":"com.fibaro.russoundXZone4Zone","children":[]},{"type":"com.fibaro.russoundXSourceZone","children":[]},{"type":"com.fibaro.russoundX5Zone","children":[]},{"type":"com.fibaro.russoundMCA88XZone","children":[]},{"type":"com.fibaro.receiver","children":[{"type":"com.fibaro.davisVantage","children":[]}]},{"type":"com.fibaro.philipsTV","children":[]},{"type":"com.fibaro.nuvoZone","children":[]},{"type":"com.fibaro.nuvoPlayer","children":[]},{"type":"com.fibaro.initialstate","children":[]},{"type":"com.fibaro.denonHeosZone","children":[]},{"type":"com.fibaro.denonHeosGroup","children":[]}]},{"type":"com.fibaro.meter","children":[{"type":"com.fibaro.waterMeter","children":[]},{"type":"com.fibaro.gasMeter","children":[]},{"type":"com.fibaro.energyMeter","children":[]}]},{"type":"com.fibaro.logitechHarmonyHub","children":[]},{"type":"com.fibaro.logitechHarmonyActivity","children":[]},{"type":"com.fibaro.logitechHarmonyAccount","children":[]},{"type":"com.fibaro.hvacSystem","children":[{"type":"com.fibaro.thermostatDanfoss","children":[{"type":"com.fibaro.thermostatHorstmann","children":[]}]},{"type":"com.fibaro.samsungAirConditioner","children":[]},{"type":"com.fibaro.operatingModeHorstmann","children":[]},{"type":"com.fibaro.coolAutomationHvac","children":[]},{"type":"com.fibaro.FGT001","children":[]}]},{"type":"com.fibaro.hunterDouglasScene","children":[]},{"type":"com.fibaro.hunterDouglas","children":[]},{"type":"com.fibaro.humidifier","children":[]},{"type":"com.fibaro.genericZwaveDevice","children":[]},{"type":"com.fibaro.genericDevice","children":[]},{"type":"com.fibaro.deviceController","children":[]},{"type":"com.fibaro.denonHeos","children":[]},{"type":"com.fibaro.coolAutomation","children":[]},{"type":"com.fibaro.alarm","children":[{"type":"com.fibaro.satelAlarm","children":[]},{"type":"com.fibaro.envisaLinkAlarm","children":[]},{"type":"com.fibaro.dscAlarm","children":[]}]},{"type":"com.fibaro.actor","children":[{"type":"com.fibaro.soundSwitch","children":[]},{"type":"com.fibaro.rollerShutter","children":[{"type":"com.fibaro.FGR221","children":[]},{"type":"com.fibaro.FGR","children":[{"type":"com.fibaro.FGWR111","children":[]},{"type":"com.fibaro.FGRM222","children":[]},{"type":"com.fibaro.FGR223","children":[]}]}]},{"type":"com.fibaro.remoteSwitch","children":[]},{"type":"com.fibaro.remoteController","children":[{"type":"com.fibaro.remoteSceneController","children":[{"type":"com.fibaro.FGPB101","children":[]},{"type":"com.fibaro.FGKF601","children":[]},{"type":"com.fibaro.FGGC001","children":[]}]}]},{"type":"com.fibaro.binarySwitch","children":[{"type":"com.fibaro.sprinkler","children":[]},{"type":"com.fibaro.satelOutput","children":[]},{"type":"com.fibaro.multilevelSwitch","children":[{"type":"com.fibaro.colorController","children":[{"type":"com.fibaro.philipsHueLight","children":[]},{"type":"com.fibaro.philipsHue","children":[]},{"type":"com.fibaro.FGRGBW442CC","children":[]},{"type":"com.fibaro.FGRGBW441M","children":[]}]},{"type":"com.fibaro.FGWD111","children":[]},{"type":"com.fibaro.FGD212","children":[]}]},{"type":"com.fibaro.FGWP","children":[{"type":"com.fibaro.FGWPI121","children":[]},{"type":"com.fibaro.FGWPG121","children":[]},{"type":"com.fibaro.FGWPG111","children":[]},{"type":"com.fibaro.FGWPB121","children":[]},{"type":"com.fibaro.FGWPB111","children":[]},{"type":"com.fibaro.FGWP102","children":[]},{"type":"com.fibaro.FGWP101","children":[]}]},{"type":"com.fibaro.FGWOEF011","children":[]},{"type":"com.fibaro.FGWDS221","children":[]}]},{"type":"com.fibaro.barrier","children":[]}]},{"type":"com.fibaro.FGRGBW442","children":[]},{"type":"com.fibaro.FGBS222","children":[]}]}]]
  typeHierarchy = json.decode(typeHierarchy) 
  return json
end

--------------- Webserver API support  ----------------
function module.WebAPI()
  local self,coprocess,split,urldecode = {},Timer.coprocess,Util.split,Util.urldecode

  local function clientHandler(client,getHandler,postHandler,putHandler)
    client:settimeout(0,'b')
    client:setoption('keepalive',true)
    --local ip=client:getpeername()
    --printf("IP:%s",ip)
    while true do
      local l,e,j = client:receive()
      --print(format("L:%s, E:%s, J:%s",l or "nil", e or "nil", j or "nil"))
      if l then
        local body,referer,header,e,b
        local method,call = l:match("^(%w+) (.*) HTTP/1.1")
        repeat
          header,e,b = client:receive()
          --print(format("H:%s, E:%s, B:%s",header or "nil", e or "nil", b or "nil"))
          if b and b~="" then body=b end
          referer = header and header:match("^[Rr]eferer:%s*(.*)") or referer
        until header == nil or e == 'closed'
        if method=='POST' and postHandler then postHandler(method,client,call,body,referer)
        elseif method=='PUT' and putHandler then putHandler(method,client,call,body,referer) 
        elseif method=='GET' and getHandler then getHandler(method,client,call,body,referer) end
        --client:flush()
        client:close()
        return
      end
      coroutine.yield()
    end
  end

  local function socketServer(server,getHandler,postHandler,putHandler)
    while true do
      local client,err
      repeat
        client, err = server:accept()
        if err == 'timeout' then coroutine.yield() end
      until err ~= 'timeout'
      coprocess(10,clientHandler,"Web:client",client,getHandler,postHandler,putHandler)
    end
  end

  local function createServer(name,port,getHandler,postHandler,putHandler)
    local server,c,err=socket.bind("*", port)
    --print(err,c,server)
    local i, p = server:getsockname()
    assert(i, p)
    --printf("http://%s:%s/test",ipAdress,port)
    server:settimeout(0,'b')
    server:setoption('keepalive',true)
    coprocess(10,socketServer,"Web:server",server,getHandler,postHandler,putHandler)
    Log(LOG.SYS,"Created %s at %s:%s",name,self.ipAddress,port)
  end

  local Pages = nil

  local GUI_HANDLERS = {  -- External calls
    ["GET"] = {
      ["/api/callAction%?deviceID=(%d+)&name=(%w+)(.*)"] = function(client,ref,body,id,action,args)
        local res = {}
        args = split(args,"&")
        for _,a in ipairs(args) do
          local i,v = a:match("^arg(%d+)=(.*)")
          res[tonumber(i)]=json.decode(urldecode(v))
        end
        local QA 
        id = tonumber(id)
        if id == plugin.mainDeviceId then
          QA = _quickApp
        else
          for id2,d in pairs(_quickApp.childDevices or {}) do
            if id == id2 then QA=d; break end
          end
        end
        local stat,res2=pcall(function() QA[action](QA,table.unpack(res)) end)
        if not stat then Log(LOG.ERROR,"Bad eventCall:%s",res2) end
        client:send("HTTP/1.1 201 Created\nETag: \"c180de84f991g8\"\n\n")
        return true
      end,
      ["/web/(.*)"] = function(client,ref,body,call)
        if call=="" then call="main" end
        local page = Pages.getPath(call)
        if page~=nil then client:send(page) return true
        else return false end
      end,
      ["/fibaroapiHC3/webQA2%?(.*)"] = function(client,ref,body,args)
        local res = {}
        args = split(args,"&")
        for _,a in ipairs(args) do
          local i,v = a:match("^(%w+)=(.*)")
          res[i]=v
        end
        hc3_emulator._slideCache = hc3_emulator._slideCache or {}
        if res.type=='values' then
          local UI,res = hc3_emulator.UI or {},{}
          for _,row in ipairs(UI or {}) do
            row = row[1] and row or {row}
            for _,e in ipairs(row) do 
              if e.type=='button' then 
                res["#"..e.button]={f="text",v=QA.getWebUIValue(e.button,"text")}
              elseif e.type=="label" then 
                res["#"..e.label]={f="text",v=QA.getWebUIValue(e.label,"text")}
              elseif e.type =="slider" then
                local val = QA.getWebUIValue(e.slider,"value")
                if hc3_emulator._slideCache[e.slider] ~= val then
                  hc3_emulator._slideCache[e.slider] = val
                  res["#"..e.slider]={f="val",v=val}
                  res["#"..e.slider.."I"]={f="text",v=val}
                end
              end
            end
          end
          res = json.encode(res)
          client:send("HTTP/1.1 200 OK\n")
          client:send("Access-Control-Allow-Headers: Origin\n")
          client:send("Content-Type: application/json; charset=utf-8\n")
          client:send("Content-Length: "..res:len())
          client:send("\n\n")
          client:send(res)    
        else
          if res.type=='btn' then
            onUIEvent({eventType='onReleased',values={},elementName=res.id,deviceId=quickApp.id})
          elseif res.type=='slider' then
            onUIEvent({eventType='onChanged',values={tonumber(res.val)},elementName=res.id,deviceId=quickApp.id})
            QA.setWebUIValue(res.id,'value',tonumber(res.val))
          end
          client:send("HTTP/1.1 302 Found\nLocation: "..(ref or "/web/main").."\n")
        end
      end,
    },
    ["POST"] = {
      ["/fibaroapiHC3/event"] = function(client,ref,body,id,action,args)
        --- ToDo
      end,
      ["/fibaroapiHC3/action/(.+)$"] = function(client,ref,body,id) onAction(json.decode(body)) end,
      ["/fibaroapiHC3/ui/(.+)$"] = function(client,ref,body,id) onUIEvent(json.decode(body)) end,
      ["/devices/(%d+)/action/(.+)$"] = function(client,ref,body,id,action) 
        local data = json.decode(body)
        local stat,err=pcall(function() QuickApp[action](QuickApp,table.unpack(data.args)) end)
        if not stat then error(format("Bad fibaro.call(%s,'%s',%s)",id,action,json.encode(data.args):sub(2,-2),err),4) end
        client:send("HTTP/1.1 201 Created\nETag: \"c180de84f991g8\"\n\n")
        return true
      end,
    }
  }

  local function GUIhandler(method,client,call,body,ref) 
    local stat,res = pcall(function()
        for p,h in pairs(GUI_HANDLERS[method] or {}) do
          local match = {call:match(p)}
          if match and #match>0 then
            if h(client,ref,body,table.unpack(match)) then return end
          end
        end
        client:send("HTTP/1.1 501 Not Implemented\nLocation: "..(ref or "/emu/triggers").."\n")
      end)
    if not stat then 
      Log(LOG.ERROR,"Bad API call:%s",res)
      --local p = Pages.renderError(res)
      --client:send(p) 
    end
  end

  function self.start(ipAddress) 
    self.ipAddress = ipAddress
    createServer("Event server",hc3_emulator.webPort,GUIhandler,GUIhandler)
  end

  Pages = { pages={} }

  function Pages.register(path,page)
    local file = page:match("^file:(.*)")
    if file then
      local f = io.open(file)
      if not f then error("No such file:"..file) end
      local page = f:read("*all")
    end
    Pages.pages[path]={page=page, path=path} 
    return Pages.pages[path]
  end

  function Pages.getPath(path)
    local p = Pages.pages[path]
    if p and not p.cpage then
      Pages.compile(p)
    end
    if p then return Pages.render(p)
    else return nil end
  end

  function Pages.renderError(msg) return format(Pages.P_ERROR1,msg) end

  function Pages.render(p)
    if p.static and p.static~=true then return p.static end
    local stat,res = pcall(function()
        return p.cpage:gsub("<<<(%d+)>>>",
          function(i)
            return p.funs[tonumber(i)]()
          end)
      end)
    if not stat then return Pages.renderError(res)
    else 
      p.static = p.static and res
      return res end
    end

    function Pages.compile(p)
      local funs={}
      p.cpage=p.page:gsub("<<<(.-)>>>",
        function(code)
          local f = format("do %s end",code)
          f,m = load(f,nil,nil,{["Web"]=Web,["Pages"]=Pages,hc3_emulator=hc3_emulator})
          if m then Log(LOG.ERROR,"ERROR RENDERING PAGE %s, %s",p.path,m) end
          funs[#funs+1]=f
          return (format("<<<%s>>>",#funs))
        end)
      p.funs=funs
    end

    Pages.P_ERROR1 =
[[HTTP/1.1 200 OK
Content-Type: text/html
Cache-Control: no-cache, no-store, must-revalidate
<!DOCTYPE html><html><head><title>Error</title><meta charset="utf-8"></head><body><pre>%s</pre></body></html>
]]

    Pages.P_MAIN =
[[HTTP/1.1 200 OK
Content-Type: text/html
Cache-Control: no-cache, no-store, must-revalidate

<!DOCTYPE html>
<html>
<head>
    <title>fibaroapiHC3</title>
    <meta charset="utf-8">
  
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.5.1/jquery.min.js"></script>
<script>
$(document).ready(function(){
   $("button.reload").click(reloadData);
   $("#auto").click(doTimer);
});
function reloadData() {
   $.get("http://192.168.1.18:6872/fibaroapiHC3/webQA2?type=values",
          function(data, status) {
            //alert("Data: " + JSON.stringify(data) + "\nStatus: " + status);
             Object.keys(data).forEach(function(key) {
                //$(key).text(data[key])
                var val = data[key];
                //alert(key + " " + val.f + " " + val.v)
                //console.log(key + " " + val.f + " " + val.v);
                $(key)[val.f](val.v);
                });
          }).fail(function() {
             $("#auto").prop("checked", false);
             doTimer();
             console.log("Error fetching UI values");
          });
}
var timer, delay = 2000;
//timer = setInterval(reloadData,delay)
function doTimer() {
  if ($('#auto').is(':checked')) {
    timer = setInterval(reloadData, delay)
  } else {
    clearInterval(timer);
  }
}
function QAbutton(id) {
  $.get('http://192.168.1.18:6872/fibaroapiHC3/webQA2?type=btn&id='+id)
}
function QAslider(id,val) {
  $.get('http://192.168.1.18:6872/fibaroapiHC3/webQA2?type=slider&id='+id+'&val='+val)
}
setTimeout(doTimer,10)
</script>
<<<return Web._PAGE_STYLE>>>
</head>
<body>
<t1>QuickApp: <<<return hc3_emulator.name>>></t1>
<div class="frame" align="middle"></p>
<<<return Web.generateQA_UI()>>>
</p></div>
<div>
  <button class="reload" id="X">Reload</button>
  <input type="checkbox" id="auto" name="auto" checked>
  <label for="auto">Auto</label>
</div>
</body>
</html>
]]

    Pages.register("main",Pages.P_MAIN).static=false

    function Pages.renderButton(id,name,c)
      return format([[<button class="button%d" id="%s" onClick="QAbutton('%s');">%s</button>]],c,id,id,name)
    end
    function Pages.renderLabel(id,text)
      return format([[<label class="label" id="%s">%s</label>]],id,text)
    end
    function Pages.renderSlider(id,name,value)
      return format([[<input class="slider" min="0" max="255"
        type="range" id="%s" value="%s"
        onmouseup="QAslider('%s',value);"
        onchange="$('#%sI').text(value);">
        <label class="slider" id="%sI">0</label>]],id,value,id,id,id,id)
    end

    function self.generateQA_UI()
      local code = {}
      local function add(str) code[#code+1]=str end
      local UI = hc3_emulator.UI
      for _,row in ipairs(UI or {}) do
        row = row[1] and row or {row}
        for _,e in ipairs(row) do 
          if e.type=='button' then 
            add(Pages.renderButton(e.button,QA.getWebUIValue(e.button,"text"),#row))
          elseif e.type=="label" then 
            add(Pages.renderLabel(e.label,QA.getWebUIValue(e.label,"text")))
          elseif e.type =="slider" then 
            add(Pages.renderSlider(e.slider,e.text,QA.getWebUIValue(e.slider,"value")))
          end
          add("&nbsp;")
        end
        add("</p>")
      end
      return table.concat(code)
    end

    self._PAGE_STYLE=
[[<style>
label.label {
   // color: blue;
}
button {
	background-color:#e6e1e6;
	border-radius:5px;
	border:1px solid #b6bdbd;
	display:inline-block;
	cursor:pointer;
	color:#333333;
	font-family:Times New Roman;
	font-size:13px;
	text-decoration:none;
	text-shadow:0px 1px 0px #ffee66;
}
button:hover {
	background-color:#d6d1d6;
}
button:active {
	position:relative;
	top:1px;
}
button.button5 { width: 54px; }
button.button4 { width: 69px; }
button.button3 { width: 93px; }
button.button2 { width: 142px; }
button.button1 { width: 287px; }
input.slider {
    color: red;
}
input.slider {
  -webkit-appearance: none;
  width: 80%;
  height: 5px;
  border-radius: 5px;   
  background: #d3d3d3;
  outline: none;
  opacity: 0.7;
  -webkit-transition: .2s;
  transition: opacity .2s;
}

input.slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  appearance: none;
  width: 12px;
  height: 12px;
  border-radius: 50%; 
  background: #000000;
  cursor: pointer;
}

input.slider::-moz-range-thumb {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #4CAF50;
  cursor: pointer;
}
div.frame {
  border: 1px solid black;
  width: 300px;
}
</style>
]]

    return self
  end

--------------- Offline support ----------------------
  function module.Files()
    local lfs = require("lfs")
    local self,dir,sep = {},"",package.config:sub(1,1)

    local function concatPath(path,file)
      if path:sub(-1)==sep then return path..file 
      else return path..sep..file end
    end

    local function createDir(dir)
      local r,err =  lfs.mkdir(dir) 
      if not r and err~="File exists" then error(format("Can't create HC3 data directory: %s (%s)",dir,err)) end
    end

    local function getHC3dir()
      local cdir = lfs.currentdir()
      dir = cdir .. sep .. hc3_emulator.HC3dir
      if not lfs.attributes(dir) then createDir(dir) end
    end

    function self.deploy(source)
      local name,id = hc3_emulator.name
      assert(name,"Missing name for deployment")
      --local source = debug.getinfo(2, 'S').short_src
      local f = io.open(source)
      assert(f,"Can't find source "..source)
      net.maxdelay=0
      local ds = api.get("/devices")
      for _,d in ipairs(ds) do
        if d.name==name then id=d.id; break end
      end
      local code = f:read("*all")
      Log(LOG.SYS,"Deploying %s",name)

      local quickVars = {}
      for k,v in pairs(hc3_emulator.quickVars or {}) do
        if not quickVars[k] then quickVars[k]=v end
      end

      for k,v in pairs(quickVars) do 
        if type(v)=='string' and v:match("^%$CREDS") then
          local p = "return hc3_emulator.credentials"..v:match("^%$CREDS(.*)") 
          quickVars[k]=load(p)()
        end
      end

      local res = QA.createQuickApp{
        name=name,
        id = id,
        type=hc3_emulator.type,
        code=code,
        UI=hc3_emulator.UI,
        quickVars=quickVars
      }
    end

    local sortKeys = {
      'id','name','roomID','type','baseType','enabled','visible','isPlugin','parentId','viewXml','configXml',
      'interfaces','properties','actions','created','modified','sortOrder'
    }
    local sortOrder={}
    for i,s in ipairs(sortKeys) do sortOrder[s]=i end
    local nKeys = #sortKeys
    local function keyCompare(a,b)
      local av,bv = sortOrder[a], sortOrder[b]
      if av == nil then nKeys = nKeys+1 sortOrder[a] = nKeys av = nKeys end
      if bv == nil then nKeys = nKeys+1 sortOrder[b] = nKeys bv = nKeys end
      return av < bv
    end

    function prettyPrint(t)
      local res = {}
      local function isArray(t) return type(t)=='table' and t[1] end
      local function isEmpty(t) return type(t)=='table' and next(t)==nil end
      local function isKeyVal(t) return type(t)=='table' and t[1]==nil and next(t)~=nil end
      local function printf(tab,fmt,...) res[#res+1] = string.rep(' ',tab)..string.format(fmt,...) end
      local function pretty(tab,t,key)
        if type(t)=='table' then
          if isEmpty(t) then printf(0,"[]") return end
          if isArray(t) then
            printf(key and tab or 0,"[\n")
            table.sort(t,keyCompare)
            for i,k in ipairs(t) do
              local cr = pretty(tab+1,k,true)
              if i ~= #t then printf(0,',') end
              printf(tab+1,'\n')
            end
            printf(tab,"]")
            return true
          end
          local r = {}
          for k,v in pairs(t) do r[#r+1]=k end
          table.sort(r,keyCompare)
          printf(key and tab or 0,"{\n")
          for i,k in ipairs(r) do
            printf(tab+1,'"%s":',k)
            local cr =  pretty(tab+1,t[k])
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
          printf(key and tab or 0,'"%s"',t)
        end
      end
      pretty(0,t,true)
      return table.concat(res,"")
    end

    self.prettyPrint = prettyPrint

    function self.Scene2Flat(s)
      local res = {}
      local function printf(...) res[#res+1]=string.format(...) end
      local ll = loadstring or load
      local content = json.decode(s.content)
      local conds = ll("return "..(content.conditions or "{}"))()
      s.content = "<content>"
      printf("--[[ <<Scene>>")
      printf("  Name      : %s",s.name)
      printf("  Id        : %s",s.id)
      if s.type=='json' then
        printf("  Conditions: %s",prettyPrint(content))
        printf("--]]\n") 
      else
        printf("  Conditions: %s",content.conditions)
        printf("--]]\n")      
        content.actions = (content.actions or ""):match("(.-)[%s%c]*$")
        printf("%s",content.actions)
      end
      printf("\n--[[ <<Scene struct>>")
      printf("%s",prettyPrint(s))
      printf("--]]")

      return table.concat(res,"\n")
    end

    function self.flat2Scene(str)
      local h,code,e = str:match("%-%-%[%[ <<Scene>>(.-)%-%-%]%]%c*(.*)%c*%-%-%[%[ <<Scene struct>>(.-)%-%-%]%][%s%c]*")
      local s = json.decode(e)
      local cond = h:match("Conditions: (.*)")
      if s.type=='json' then
        s.content = json.decode(cond)
      else
        cond = cond
        local content = json.encode({conditions=cond,actions=code})
        s.content = content
      end
      return s
    end

    function self.QuickApp2Flat(d)
      local res = {}
      local function printf(...) res[#res+1]=string.format(...) end

      if d.initialProperties then
        d.properties=d.initialProperties
        d.initialProperties = nil
      end
      printf("--[[ <<QuickApp>>")
      printf("  Name:%s",d.name)
      printf("  Id:  %s",d.id)
      printf("  Type:%s",d.type)
      printf("--]]\n")
      printf("%s",d.properties.mainFunction)
      d.properties.mainFunction=""
      printf("--[[ <<Device struct>>")
      printf("%s",prettyPrint(d))
      printf("--]]")
      return table.concat(res,"\n")
    end

    function self.flat2QuickApp(str)
      local h,code,e = str:match("%-%-%[%[ <<QuickApp>>(.-)%-%-%]%]%c*(.*)%c*%-%-%[%[ <<Device struct>>(.-)%-%-%]%][%s%c]*")
      assert(h and code and e,"Bad flat QuickApp format")
      local d = json.decode(e)

      local noProps = {
        logTemp=true,deadReason=true,dead=true,log=true
      }

      local ip = {}
      for k,v in pairs(d.properties) do if not noProps[k] then ip[k]=v end end
      ip.mainFunction = code
      ip.viewLayout = d.properties.viewLayout
      d.properties.viewLayout = nil
      ip.uiCallbacks = d.properties.uiCallbacks
      d.properties.uiCallbacks = nil
      ip.quickAppVariables = d.properties.quickAppVariables
      d.properties.quickAppVariables = nil
      ip.typeTemplateInitialized=true
      local ds = {}
      for _,k in ipairs({'id','name','roomID','type','baseType','enabled','visible','isPlugin','viewXml','configXml',
          'interfaces','actions','sortOrder'}) do ds[k]=d[k] end
      ds.initialProperties=ip
      ds.apiVersion = "1.1"
      return ds
    end

    function self.upload2DownloadQAStruct(d)
      d.properties = d.initialProperties
      d.initialProperties = nil
      d.properties.apiVersion = d.apiVersion
      d.apiVersion = nil
      return d
    end

    function self.writeFile(tp,struct,path)
      local fileText = self[tp].convertStruct2text(struct)
      local fname = format("%s_%d_%s.lua",tp,struct.id or 0,struct.name)
      fname =  fname:gsub("([%s%/])","_")
      fname = path~="" and concatPath(path,fname) or fname
      local f,err = io.open(fname,"w")
      assert(f,"Can't open file for write:"..fname)
      f:write(fileText)
      f:close()
      return fname
    end

    local function checkError(res,err)
      if res==nil and err > 204 then Log(LOG.ERROR,"Resource update error : %s",err) end
    end

    local function warn(test,tp,name)
      if not test then Log(LOG.WARNING,"%s:%s, name or id mismatch with file content, using file content",tp,name) end
    end

    function self.restoreQuickApp(struct,id,name)
      local sname = struct.name:gsub("([%s%/])","_")
      warn(sname==name and struct.id==id,"QuickApp",name)
      local ds = api.get("/devices/"..struct.id)
      if ds and ds.name==struct.name then
        Log(LOG.LOG,"Updating existing device %s",struct.name)
        local d, err = api.put("/devices/"..struct.id,{
            properties={
              quickAppVariables = struct.initialProperties.quickAppVariables,
              mainFunction = struct.initialProperties.mainFunction,
              uiCallBacks = struct.initialProperties.uiCallbacks,
            }
          })
        if d == nil then
          Log(LOG.LOG,"Error creating device: %s",err)
        else
          Log(LOG.LOG,"Device %s with id:%s created",d.name,d.id)
        end
        return -- update
      end
      Log(LOG.LOG,"Creating new device %s",struct.name)
      local d,err = api.post("/quickApp/",struct)
      if d == nil then
        Log(LOG.LOG,"Error creating device: %s",err)
      else
        Log(LOG.LOG,"Device %s with id:%s created",d.name,d.id)
      end
    end

    function self.restoreScene(struct,id,name)
      local sname = struct.name:gsub("([%s%/])","_")
      warn(sname==name and struct.id==id,"scene",name)
      if api.get("/scenes/"..struct.id) then
        Log(LOG.LOG,"Updating existing scene %s",struct.name)
        checkError(api.put("/scenes/"..struct.id,struct))
      else
        Log(LOG.LOG,"Creating new scene %s",struct.name)
        checkError(api.post("/scenes",struct))
      end   
    end

    function self.restoreGlobal(struct,id,name)
      local sname = struct.name:gsub("([%s%/])","_")
      warn(sname==name,"globalVariable",name)
      if api.get("/globalVariables/"..struct.name) then
        Log(LOG.LOG,"Updating existing globalVariable %s",struct.name)
        checkError(api.put("/globalVariables/"..struct.name,struct))
      else
        Log(LOG.LOG,"Creating new globalVariable %s",struct.name)
        checkError(api.post("/globalVariables",struct))
      end
    end

    function self.restoreLocation(struct,id,name)
      local sname = struct.name:gsub("([%s%/])","_")
      warn(sname==name and struct.id==id,"location",name)
      if api.get("/panels/location/"..struct.id) then
        Log(LOG.LOG,"Updating existing location %s",struct.name)
        checkError(api.put("/panels/location/"..struct.id,struct))
      else
        Log(LOG.LOG,"Creating new location %s",struct.name)
        checkError(api.post("/panels/location",struct))
      end
    end

    function self.restoreCustom(struct,id,name)
      local sname = struct.name:gsub("([%s%/])","_")
      warn(sname==name and struct.id==id,"customEvent",name)
      if api.get("/customEvents/"..struct.name) then
        Log(LOG.LOG,"Updating existing customEvent %s",struct.name)
        checkError(api.put("/customEvents/"..struct.name,struct))
      else
        Log(LOG.LOG,"Creating new customEvent %s",struct.name)
        checkError(api.post("/customEvents",struct.struct))
      end
    end

    self.QA,self.Scene,self.Global,self.Location,self.CustomEvent={},{},{},{},{}
    function self.QA.convertText2struct(text,struct) return self.flat2QuickApp(text) end
    function self.QA.convertStruct2text(struct) return self.QuickApp2Flat(struct) end
    function self.QA.restoreStruct(struct,id,name) return self.restoreQuickApp(struct,id,name) end
    function self.Scene.convertText2struct(text) return self.flat2Scene(text) end
    function self.Scene.convertStruct2text(struct) return self.Scene2Flat(struct) end
    function self.Scene.restoreStruct(struct,id,name) return self.restoreScene(struct,id,name) end
    function self.Global.convertStruct2text(struct) return prettyPrint(struct) end
    function self.Global.convertText2struct(text) return json.decode(text) end
    function self.Global.restoreStruct(struct,id,name) return self.restoreGlobal(struct,id,name) end
    function self.Location.convertStruct2text(struct)  return prettyPrint(struct) end
    function self.Location.convertText2struct(text)  return json.decode(text) end
    function self.Location.restoreStruct(struct,id,name) return self.restoreLocation(struct,id,name) end
    function self.CustomEvent.convertStruct2text(struct)  return prettyPrint(struct) end
    function self.CustomEvent.convertText2struct(text)  return json.decode(text) end
    function self.CustomEvent.restoreStruct(struct,id,name) return self.restoreCustomEvent(struct,id,name) end

    local resMap = {
      scenes={name="Scene",rsrcpath="/scenes", dir="Scenes"},
      devices={name="QA",rsrcpath="/devices", dir="QAs", test=function(d) return d.id < 4 or (d.parentId and d.parentId > 0) end },
      globals={name="Global",rsrcpath="/globalVariables", dir="Globals"},
      locations={name="Location",rsrcpath="/panels/location", dir="Locations"},
      custom={name="CustomEvent",rsrcpath="/customEvents", dir="CustomEvents"},
    }

    function self.download(resource,path)
      local r = resMap[resource]
      assert(resMap[resource],"Unsupported resource:"..resource)
      local dpath = path
      createDir(dpath)
      for _,d in ipairs(api.get(r.rsrcpath) or {}) do
        if r.test and r.test(d) then 
          -- ignore
        else
          self.writeFile(r.name,d,dpath)
        end
      end
    end

    function self.backupR(resource,path) -- scenes,devices,globals,locations,customs
      local r = resMap[resource]
      assert(resMap[resource],"Unsupported resource:"..resource)
      path = concatPath(path,r.dir)
      createDir(path)
      Log(LOG.LOG,"Backing up %s to %s",resource,path)
      self.download(resource,path)
    end

    function self.backup(resource) -- scenes,devices,globals,locations,customs
      local dpath = concatPath(dir,"backup")
      createDir(dpath)
      local dname = os.date(hc3_emulator.backDirFmt)
      dpath = concatPath(dpath,dname) 
      createDir(dpath)
      if resource == 'all' then
        for r,_ in pairs(resMap) do self.backupR(r,dpath) end 
      else self.backupR(resource,dpath) end
    end

    function self.restore(path)
      local tp,id,name = path:match("(%a+)_(%d+)_([%-%._%w]+)%.lua$")
      local f = io.open(path)
      assert(f,"File does not exist: "..path)
      assert(tp,"Unsupported resource: "..tostring(tp))
      Log(LOG.LOG,"Restoring resource %s %s",tp,path)
      local txt = f:read("*all")
      f:close()
      local struct = self[tp].convertText2struct(txt)
      self[tp].restoreStruct(struct,tonumber(id),name)
    end

    getHC3dir()

    commandLines['pull']=function(...) -- devices/239
      local path = table.concat({...})
      local rsrc,id = path:match("^%s*/?(%a+)/([%a%d]+)%s*")
      assert(rsrc and id and resMap[rsrc],"Not a resource name")
      local r = resMap[rsrc]
      local struct = api.get("/"..rsrc.."/"..id)
      Log(LOG.LOG,"Writing file...")
      local fn = self.writeFile(r.name,struct,"")
      if fn then
        Log(LOG.LOG,"File %s written",fn)
      end
    end
    commandLines['push']=function(...) self.restore(table.concat({...}," ")) end
    commandLines['backup']=function() self.backup("all") end
    return self
  end

--------------- Offline support ----------------------
  function module.Offline()
    -- We setup our own /refreshState handler and other REST API handlers and keep our own reosurce states
    local self,cache,split,urldecode,QUEUESIZE = {},Trigger.cache,Util.split,Util.urldecode,200
    local refreshStates = nil

    ---------------- Resource DB --------------------
    local function resourceDB()
      local self,cache = {},{}
      local resources= {
        devices = {},
        scenes = {},
        globalVariables = {},
        customEvents = {},
        rooms = {},
        sections = {},
        profiles = {},
        settings = {info = {}, location={}, network={}, led={}},
        users={},
        weather={},
        iosDevices={},
        home={},
        categories={},
        alarms = {
          v1 = {
            devices = {},
            history = {},
            partitions = {},
          }
        },
        panels = {
          family = {}
        }
      }
      local auto = { devices = true, globals = true, customevent = true }
      self.resources,self.auto = resources,auto

      function self.setDB(db) resources=db self.resources=db end

      local function splitPath(path) local p = split(path,"/") p = #p==1 and p[1] or p; cache[path]=p return p end
      local function copyOver(o1,o2,cm,r)
        cm = cm or {}
        for k,v in pairs(o2) do
          if type(v)=='table' then
            if o1[k]==nil then o1[k]=copyOver({},v,cm[k],r)
            elseif type(o1[k])=='table' then copyOver(o1[k],v,cm[k],r) end
          elseif not (cm and cm[k]==false) then 
            if cm and type(cm[k])=='function' then cm[k](k,o1[k],v,r) end
            o1[k]=v 
          end
        end
      end
      local function get(rsrc)
        local path = cache[rsrc] or splitPath(rsrc)
        if type(path)=='string' then return resources[path]
        else
          local r = resources
          for _,k in ipairs(path) do r=r[k] end
          return r
        end
      end
      local creator,modifier,actions= {},{},{}
      function self.addCreator(rsrc,fun) local r = get(rsrc) creator[r]=fun end
      function self.addModifier(rsrc,tab) local r = get(rsrc) modifier[r]=tab end
      function self.addActions(rsrc,a) actions[rsrc]=a end
      function self.getActions(rsrc) return actions[rsrc] or {} end

      function self.delete(rsrc,key)
        local r = get(rsrc)
        if r[key] then actions[r[key]]=nil; r[key]=nil return nil,200 else return nil,404 end
      end

      function self.add(rsrc,key,value,force) -- error if exists
        local r = get(rsrc)
        if r[key] then return nil,409 end
        self.get(rsrc,key,force)
        self.modify(rsrc,key,value)
        return r[key],200
      end

      function self.modify(rsrc,key,value) -- creates if creator
        local r = get(rsrc)
        if not r[key] then 
          local v,err = self.get(rsrc,key)
          if err~=200 then return v,err end
        end
        if type(value) == 'table' then
          copyOver(r[key],value,modifier[r],r[key])
        else r[key]=value end
        return r[key],200
      end

      function self.get(rsrc,key,force) -- creates if creator
        local r = get(rsrc)
        if key then
          if r[key] then return r[key],200
          elseif creator[r] then
            local v = creator[r](key,force)
            if v then r[key]=v; return v,200 end
          end
          return nil,404 
        else 
          local res = {}
          if type(next(r))=='table' then
            for _,v in pairs(r) do res[#res+1]=v end
            return res,200
          else return r,200 end
        end
      end
      return self
    end

    local db = resourceDB()

    local function createGlobalVariable(var)
      var.readOnly = var.readOnly or false
      var.isEnum = var.isEnum or false
      var.enumValues = var.enumValues or {}
      var.created = os.time()
      var.modified = os.time()
      return var.name and var
    end

    local function createCustomEvent(ce)
      ce.userDescription = ce.userDescription or ""
      return ce.name and ce
    end

    local deviceTypes = {
      ["com.fibaro.binarySwitch"] = function(self)
        self.properties.value = false
        self.properties.state = false
        self.actions = {turnOn=0, turnOff=0}
        local actions = {}
        function actions.turnOn() actions.setValue("value",true) end
        function actions.turnOff() actions.setValue("value",false) end
        function actions.setValue(prop,value) 
          if prop=='value' or prop=='state' then
            db.modify("/devices",self.id,{properties ={value=value}}) 
            db.modify("/devices",self.id,{properties ={state=value}}) 
            cache.write('devices',prop..self.id,{value=value,modified=os.time()})
          end
        end -- could be more efficient
        return actions
      end,
      ["com.fibaro.multilevelSwitch"] = function(self)
        self.properties.value = 0
        self.actions = {turnOn=0, turnOff=0, setValue=2}
        local actions = {}
        function actions.turnOn() actions.setValue("value",99) end
        function actions.turnOff() actions.setValue("value",0) end
        function actions.setValue(prop,value) 
          db.modify("/devices",self.id,{properties={[prop]=value}}) 
          if prop=='value' then 
            db.modify("/devices",self.id,{properties={state=value>0}}) 
          end 
          if hc3_emulator.speeding then 
            cache.write('devices','state'..self.id,{value=value>0,modified=os.time()})
            cache.write('devices',prop..self.id,{value=value,modified=os.time()})
          end
        end
        return actions
      end,
      ["com.fibaro.binarySensor"] = function(self)
        self.properties.value = false
        self.properties.state = false
        self.lastBreached = 0
        self.actions = {turnOn=0, turnOff=0}
        local actions = {}
        function actions.turnOn() actions.setValue("value",true) end
        function actions.turnOff() actions.setValue("value",false) end
        function actions.setValue(prop,value) 
          if prop=='value' or prop=='state' then
            self.lastBreached = os.time()
            db.modify("/devices",self.id,{properties ={value=value}}) 
            db.modify("/devices",self.id,{properties ={state=value}}) 
          end
        end
        return actions
      end,
      ["com.fibaro.multilevelSensor"] = function(self)
        self.properties.value = 0
        self.actions = {turnOn=0, turnOff=0, setValue=2}
        local actions = {}
        function actions.turnOn() actions.setValue("value",99) end
        function actions.turnOff() actions.setValue("value",0) end
        function actions.setValue(prop,value) 
          db.modify("/devices",self.id,{properties={[prop]=value}}) 
          if prop=='value' then 
            db.modify("/devices",self.id,{properties={state=value>0}}) 
          end 
        end
        return actions
      end,
    }

    local hierarchyCache={}
    local function getBaseType(tp)
      if hierarchyCache[tp] then return hierarchyCache[tp] end
      local function getHierarchy(tp,tree)
        if tree.type==tp then return {tp}
        else
          for _,c in ipairs(tree.children) do
            local m = getHierarchy(tp,c)
            if m then table.insert(m,tree.type) return m end
          end
        end
      end
      local h,bt = getHierarchy(tp,typeHierarchy)
      if h==nil or #h == 0 then return nil
      else
        for _,t in ipairs(h) do if deviceTypes[t] then bt = t break end end
        return bt
      end
    end

    local function createDevice(dev)
      if dev.id == 1 then
        dev.id=1
        dev.properties={sunsetHour="20:00",sunriseHour="06:00"}
        dev.type="com.fibaro.zwavePrimaryController"
        dev.baseType=""
      else
        dev.properties = dev.properties or {}
        dev.created = os.time()
        dev.modified = dev.created
        dev.name = dev.name or ""
        dev.type = dev.type or hc3_emulator.defaultDevice or "com.fibaro.binarySwitch"
        dev.baseType = getBaseType(dev.type)
        if not (dev.id and dev.baseType) then return end
        db.addActions(dev,deviceTypes[dev.baseType](dev))
      end
      Debug(dev.id ~= 1 and _debugFlags.creation,"DeviceId:%s (%s) created",dev.id,dev.type)
      return dev
    end

    local initExemptions = { ['HC_User']=true,['com.fibaro.zwavePrimaryController']=true}
    function self.initExistingDevice(dev)
      if initExemptions[dev.type] then return end
      local baseType = getBaseType(dev.type)
      dev.baseType = baseType or "com.fibaro.multilevelSwitch" 
      if dev.baseType~="" then db.addActions(dev,deviceTypes[dev.baseType](dev)) end
    end

    --local function pr(o) print(json.encode(o)) end

    self.db = db
    hc3_emulator.autocreate = db.auto


--[[
    {type='AlarmPartitionArmedEvent' = function(self,d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
    {type='AlarmPartitionBreachedEvent' = function(self,d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
    {type='HomeArmStateChangedEvent', data = {newValue=<val1>}}
    {type='HomeBreachedEvent, data = {breached=<val>}}
    {type='WeatherChangedEvent', data={change=<prop>,newValue=<val1>, oldValue=<val2>}}
    {type='GlobalVariableChangedEvent', data={variableName=<name>, newValue=<val1>, oldValue=<val2>}}
    {type='DevicePropertyUpdatedEvent', data={id=<deviceID>,newValue=<val1>,oldValue=<val2>,property=<name>}}
    {type='CentralSceneEvent, data={}}
    {type='AccessControlEvent', fata{}}
    {type='CustomEvent' data = {name=<name>}}
    {type='ActiveProfileChangedEvent', data={newActiveProfile=<val1>, oldActiveProfile=<val2>}}
--]]

    local function propChange(prop,oldValue,newValue,d)
      if oldValue ~= newValue then
        d.modified = os.time()
        refreshStates.addEvents(
          {type='DevicePropertyUpdatedEvent', data={id=tonumber(d.id),newValue=newValue,oldValue=oldValue,property=prop}}
        )
        --Trigger.pollOneEvent()
      end
    end

    function self.setupDBhooks()
      db.addCreator("/devices",function(id,force) return (force or db.auto.devices) and createDevice({id=tonumber(id)}) end)
      db.addCreator("/globalVariables",function(name,force) return (force or db.auto.globals) and createGlobalVariable({name=name}) end)
      db.addCreator("/customEvents",function(name,force) return (force or db.auto.customevents) and createCustomEvent({name=name}) end)
      db.addModifier("/globalVariables",
        {
          name=false, 
          value=function(_,oldValue,newValue,v) 
            if oldValue ~= newValue then
              refreshStates.addEvents(
                {type='GlobalVariableChangedEvent', data={variableName=v.name, newValue=newValue, old=oldValue}}
              )
              --Trigger.pollOneEvent()
            end
          end
        })
      db.addModifier("/devices",
        {
          name=false, 
          id=false, 
          type=false, 
          properties = {
            value=propChange,
            color=propChange,
          }
        })
    end
    self.setupDBhooks()


    self.refreshStates = Trigger.refreshStates
    refreshStates = self.refreshStates

---------------- api.* handlers -- simulated calls to offline version of resources
    local function arr(tab) local res={} for _,v in pairs(tab) do res[#res+1]=v end return res end
    local OFFLINE_HANDLERS = {
      ["GET"] = {
        ["/callAction%?deviceID=(%d+)&name=(%w+)(.*)"] = function(call,data,cType,id,action,args)
          local res = {}
          args,id = split(args,"&"),tonumber(id)
          for _,a in ipairs(args) do
            local i,v = a:match("^arg(%d+)=(.*)")
            res[tonumber(i)]=urldecode(v)
          end
          local d,err1 = db.get("/devices",id)
          if err1 then return d,err1 end
          local fun = db.getActions(d)[action]
          local stat,err2 = pcall(function() fun(table.unpack(res)) end)
          if not stat then 
            Log(LOG.ERROR,"Bad fibaro.call(%s,'%s',%s)",id,action,json.encode(res):sub(2,-2),err2)
            return nil,501
          end
          return nil,200
        end,
        ["/devices/(%d+)/properties/(.+)$"] = function(call,data,cType,deviceID,property) 
          local d,err1 = db.get("/devices",tonumber(deviceID))
          if err1 and err1~=200 then return nil,err1 end
          return {value=d.properties[property],modified=d.modified},200
        end,
        ["/devices/(%d+)$"] = function(call,data,cType,id) return db.get("/devices",tonumber(id)) end,
        ["/devices/?$"] = function(call,data,cType,name) return arr(db.get("/devices")) end,    
        ["/globalVariables/(.+)"] = function(call,data,cType,name) return db.get("/globalVariables",name) end,
        ["/globalVariables/?$"] = function(call,data,cType,name) return arr(db.get("/globalVariables")) end,
        ["/customEvents/(.+)"] = function(call,data,cType,name) return db.get("/customEvents",name) end,
        ["/customEvents/?$"] = function(call,data,cType,name) return arr(db.get("/customEvents")) end,
        ["/scenes/(%d+)"] = function(call,data,cType,id) return db.get("/scenes",tonumber(id)) end,
        ["/scenes/?$"] = function(call,data,cType,name) return arr(db.get("/scenes")) end,
        ["/rooms/(%d+)"] = function(call,data,cType,id) return db.get("/rooms",tonumber(id)) end,
        ["/rooms/?$"] = function(call,data,cType,name) return arr(db.get("/rooms")) end,
        ["/iosUser/(%d+)"] = function(call,data,cType,id) return db.get("/rooms",tonumber(id)) end,
        ["/rooms/?$"] = function(call,data,cType,name) return arr(db.get("/rooms")) end,
        ["/sections/(%d+)"] = function(call,data,cType,id) return db.get("/sections",tonumber(id)) end,
        ["/sections/?$"] = function(call,data,cType,name) return arr(db.get("/sections")) end,
        ["/refreshStates%?last=(%d+)"] = function(call,data,cType,last) return refreshStates.getEvents(tonumber(last)),200 end,
        ["/settings/location/?$"] = function(_) return db.get("/settings/location/") end
      },
      ["POST"] = {
        ["/globalVariables/?$"] = function(call,data,_) -- Create variable.
          data = json.decode(data) 
          return db.add("/globalVariables",data.name,data,true)
        end,
        ["/customEvents/?$"] = function(call,data,_) -- Create customEvent.
          data = json.decode(data) 
          return db.add("/customEvents",data.name,data,true)
        end,
        ["/scenes/?$"] = function(call,data,_) -- Create scene.
          data = json.decode(data) 
          return db.add("/scenes",data.id,data,true)
        end,
        ["/rooms/?$"] = function(call,data,_) -- Create room.
          data = json.decode(data) 
          return db.add("/rooms",data.id,data,true)
        end,
        ["/sections/?$"] = function(call,data,_) -- Create section.
          data = json.decode(data) 
          return db.add("/sections",data.id,data,true)
        end,   
        ["/devices/(%d+)/action/(.+)$"] = function(call,data,cType,deviceID,action) -- call device action
          data = json.decode(data)
          local d,err1 = db.get("/devices",tonumber(deviceID))
          if err1 and err1~=200 then return d,err1 end
          local fun = db.getActions(d)[action]
          local stat,err2 = pcall(function() fun(table.unpack(data.args)) end)
          if not stat then 
            Log(LOG.ERROR,"Bad fibaro.call(%s,'%s',%s)",deviceID,action,json.encode(data.args):sub(2,-2),err2)
            return nil,501
          end
          return nil,200
        end,
        ["/customEvents/(.+)$"] = function(call,data,cType,name)
          if db.get("/customEvents",name) then
            refreshStates.addEvents({type='CustomEvent', data={name=name,}})
          end
        end
      },
      ["PUT"] = {
        ["/globalVariables/(.+)"] = function(call,data,cType,name) -- modify value
          data = json.decode(data)
          return db.modify("/globalVariables",name,data)
        end,
        ["/customEvents/(.+)"] = function(call,data,cType,name) -- modify value
          data = json.decode(data)
          return db.modify("/customEvents",name,data)
        end,
        ["/devices/(%d+)"] = function(call,data,cType,id) -- modify value
          data = json.decode(data)
          return db.modify("/devices",tonumber(id),data)
        end,
      },
      ["DELETE"] = {
        ["/globalVariables/(.+)"] = function(call,data,cType,name) 
          return db.delete("/globalVariables",name)
        end,
        ["/customEvents/(.+)"] = function(call,data,cType,name) 
          return db.delete("/customEvents",name)
        end,
        ["/devices/(%d+)"] = function(call,data,cType,id) 
          return db.delete("/device",tonumber(id))
        end,
        ["/rooms/(%d+)"] = function(call,data,cType,id) 
          return db.delete("/rooms",tonumber(id))
        end,
        ["/sections/(%d+)"] = function(call,data,cType,id) 
          return db.delete("/sections",tonumber(id))
        end,
        ["/scenes/(%d+)"] = function(call,data,cType,id) 
          return db.delete("/scenes",tonumber(id))
        end,
      },
    }

    local olh = {} -- Factor path one step.
    for k,v in pairs(OFFLINE_HANDLERS) do
      olh[k]={}
      local o = olh[k]
      for i,j in pairs(v) do
        local m,r = i:match("(/%w+)(.*)")
        if not m then 
          o[i]=j
        else 
          o[m] = o[m] or {}
          o[m]["^"..r]=j
        end
      end
    end
    OFFLINE_HANDLERS=olh

    local function offlineApi(method,call,data,cType)
      local f = OFFLINE_HANDLERS[method]
      local m,r = call:match("(/%w+)(.*)")
      if m then
        local hs = f[m]
        for p,h in pairs(hs or {}) do
          local match = {r:match(p)}
          if match and #match>0 then
            return h(call,data,cType,table.unpack(match))
          end
        end
      end
      fibaro.warning("","API not supported yet: "..method..":"..call)
    end

--hc3_emulator.createDevice(99,"com.fibaro.multilevelSwitch")
    function self.createDevice(id,tp,name)
      assert(hc3_emulator.offline,"createDevice can only run offline")
      local temp
      temp,hc3_emulator.defaultDevice = hc3_emulator.defaultDevice,tp or hc3_emulator.defaultDevice
      local d = db.add("/devices",id,{id=id,type=tp,name=name})
      hc3_emulator.defaultDevice = temp
      return d
    end

    local function userDev(d0)
      local u,d = {},d0
      for k,v in pairs(db.getActions(d)) do u[k]=v end
      function u.breach(secRestore)
        u.turnOn()
        setTimeout(function() u.turnOff() end,1000*secRestore)
      end
      function u.delay(s)
        local res = {}
        for k,v in pairs(u) do 
          res[k]=function(...) local a={...} setTimeout(function() v(table.unpack(a)) end,s*1000) end
        end 
        return res
      end
      return u
    end

    hc3_emulator.create = {}
    function hc3_emulator.create.motionSensor(id,name) return userDev(self.createDevice(id,"com.fibaro.motionSensor",name)) end
    function hc3_emulator.create.tempSensor(id,name) return userDev(self.createDevice(id,"com.fibaro.temperatureSensor",name)) end
    function hc3_emulator.create.doorSensor(id,name) return userDev(self.createDevice(id,"com.fibaro.doorSensor",name)) end
    function hc3_emulator.create.luxSensor(id,name) return userDev(self.createDevice(id,"com.fibaro.lightSensor",name)) end
    function hc3_emulator.create.dimmer(id,name) return userDev(self.createDevice(id,"com.fibaro.multilevelSwitch",name)) end
    function hc3_emulator.create.light(id,name) return userDev(self.createDevice(id,"com.fibaro.binarySwitch",name)) end

    function self.start()
      if #db.get("/settings/location")==0 then
        db.modify("/settings","location",{latitude=52.520008,longitude=13.404954}) -- Berlin
      end
      local function setupSuntimes()
        local sunrise,sunset = Util.sunCalc()
        db.modify("/devices",1,{properties={sunriseHour=sunrise,sunsetHour=sunset}})
      end
      local t = os.date("*t")
      t.min,t.hour,t.sec=0,0,0
      t = os.time(t)+24*60*60
      local function midnight()
        setupSuntimes()
        t = t+24*60*60
        setTimeout(midnight,1000*(t-os.time()))
      end
      setTimeout(midnight,1000*(t-os.time()))
      setupSuntimes()
    end

    self.api = offlineApi
    return self

  end -- Offline

-------------- OfflineDB functions ------------------
  function module.OfflineDB()
    local fname = "HC3sdk.db"
    local self,persistence = {},nil
    local cr = not hc3_emulator.credentials and loadfile(hc3_emulator.credentialsFile); cr = cr and cr()

    function self.downloadFibaroAPI()
      net.maxdelay=0; net.mindelay=0
      net.HTTPClient():request("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/fibaroapiHC3.lua",{
          options={method="GET", checkCertificate = false, timeout=5000},
          success=function(res) 
            local version = res.data:match("FIBAROAPIHC3_VERSION%s*=%s*\"(.-)\"")
            if version then
              Log(LOG.LOG,"Writing file fibaroapiHC3.lua v%s",version)
              local f = io.open("fibaroapiHC3.lua","w")
              f:write(res.data)
              f:close()
            else
              Log(LOG.ERROR,"Bad file - fibaroapiHC3.lua")
            end
          end,
          error=function(res) Log(LOG.ERROR,"Unable to read file fibaroapiHC3.lua:"..res) end,
        })
    end

    function self.copyFromHC3()
      local function mapIDS(r)
        if type(r)~='table' or r[1]==nil then return r end
        local v = r[1]
        if not (v.id or v.name or v.partionId) then return end
        local res={}
        for _,r0 in ipairs(r) do 
          res[r0.id or r0.name or r0.partionId]=r0 
        end
        return res
      end
      local resources = Offline.db.resources
      local stat,res = pcall(function()
          local function copy(resources,path)
            for k,v in pairs(resources) do
              if next(v)==nil then 
                Log(LOG.LOG,"Reading %s",path..k)
                resources[k]=mapIDS(api.get(path..k))
              else copy(v,path..k.."/")
              end
            end
          end
          copy(resources,"/")
        end)
      if not stat then
        Log(LOG.ERROR,"Failed copying HC3 data:%s",res)
      else
        Log(LOG.LOG,"Writing HC3 resources to file (%s)",fname)
        persistence.store(fname,resources)
      end
    end

    function self.loadDB()
      local r = persistence.load(fname)
      for _,dev in pairs(r.devices) do
        Offline.initExistingDevice(dev)
      end
      Offline.db.setDB(r)
      Offline.setupDBhooks()
      Log(LOG.SYS,"Loaded database '%s'",fname)
    end

-----------------------------
-- persistence
-- Copyright (c) 2010 Gerhard Roethlin

--------------------
-- Private methods
    local write, writeIndent, writers, refCount;

    persistence = {
      store = function (path, ...)
        local file, e;
        if type(path) == "string" then
          -- Path, open a file
          file, e = io.open(path, "w");
          if not file then
            return error(e);
          end
        else
          -- Just treat it as file
          file = path;
        end
        local n = select("#", ...);
        -- Count references
        local objRefCount = {}; -- Stores reference that will be exported
        for i = 1, n do
          refCount(objRefCount, (select(i,...)));
        end;
        -- Export Objects with more than one ref and assign name
        -- First, create empty tables for each
        local objRefNames = {};
        local objRefIdx = 0;
        file:write("-- Persistent Data\n");
        file:write("local multiRefObjects = {\n");
        for obj, count in pairs(objRefCount) do
          if count > 1 then
            objRefIdx = objRefIdx + 1;
            objRefNames[obj] = objRefIdx;
            file:write("{};"); -- table objRefIdx
          end;
        end;
        file:write("\n} -- multiRefObjects\n");
        -- Then fill them (this requires all empty multiRefObjects to exist)
        for obj, idx in pairs(objRefNames) do
          for k, v in pairs(obj) do
            file:write("multiRefObjects["..idx.."][");
            write(file, k, 0, objRefNames);
            file:write("] = ");
            write(file, v, 0, objRefNames);
            file:write(";\n");
          end;
        end;
        -- Create the remaining objects
        for i = 1, n do
          file:write("local ".."obj"..i.." = ");
          write(file, (select(i,...)), 0, objRefNames);
          file:write("\n");
        end
        -- Return them
        if n > 0 then
          file:write("return obj1");
          for i = 2, n do
            file:write(" ,obj"..i);
          end;
          file:write("\n");
        else
          file:write("return\n");
        end;
        file:close();
      end;

      load = function (path)
        local f, e = loadfile(path);
        if f then
          return f();
        else
          return nil, e;
        end;
      end;
    }

-- Private methods

-- write thing (dispatcher)
    write = function (file, item, level, objRefNames)
      writers[type(item)](file, item, level, objRefNames);
    end;

-- write indent
    writeIndent = function (file, level)
      for i = 1, level do
        file:write("\t");
      end;
    end;

-- recursively count references
    refCount = function (objRefCount, item)
      -- only count reference types (tables)
      if type(item) == "table" then
        -- Increase ref count
        if objRefCount[item] then
          objRefCount[item] = objRefCount[item] + 1;
        else
          objRefCount[item] = 1;
          -- If first encounter, traverse
          for k, v in pairs(item) do
            refCount(objRefCount, k);
            refCount(objRefCount, v);
          end;
        end;
      end;
    end;

-- Format items for the purpose of restoring
    writers = {
      ["nil"] = function (file, item)
        file:write("nil");
      end;
      ["number"] = function (file, item)
        file:write(tostring(item));
      end;
      ["string"] = function (file, item)
        file:write(string.format("%q", item));
      end;
      ["boolean"] = function (file, item)
        if item then
          file:write("true");
        else
          file:write("false");
        end
      end;
      ["table"] = function (file, item, level, objRefNames)
        local refIdx = objRefNames[item];
        if refIdx then
          -- Table with multiple references
          file:write("multiRefObjects["..refIdx.."]");
        else
          -- Single use table
          file:write("{\n");
          for k, v in pairs(item) do
            writeIndent(file, level+1);
            file:write("[");
            write(file, k, level+1, objRefNames);
            file:write("] = ");
            write(file, v, level+1, objRefNames);
            file:write(";\n");
          end
          writeIndent(file, level);
          file:write("}");
        end;
      end;
      ["function"] = function (file, item)
        -- Does only work for "normal" functions, not those
        -- with upvalues or c functions
        local dInfo = debug.getinfo(item, "uS");
        if dInfo.nups > 0 then
          file:write("nil --[[functions with upvalue not supported]]");
        elseif dInfo.what ~= "Lua" then
          file:write("nil --[[non-lua function not supported]]");
        else
          local r, s = pcall(string.dump,item);
          if r then
            file:write(string.format("loadstring(%q)", s));
          else
            file:write("nil --[[function could not be dumped]]");
          end
        end
      end;
      ["thread"] = function (file, item)
        file:write("nil --[[thread]]\n");
      end;
      ["userdata"] = function (file, item)
        file:write("nil --[[userdata]]\n");
      end;
    }

    commandLines['copysdkdb']=self.copyFromHC3
    commandLines['downloadsdk']=self.downloadFibaroAPI
    self.persistence = persistence

    return self
  end -- OfflineDB

--------------- Load modules  and start ------------------------------
  Util    = module.Utilities()
  json    = module.Json()
  Timer   = module.Timer()
  Trigger = module.Trigger()
  fibaro  = module.FibaroAPI()
  QA      = module.QuickApp()
  Scene   = module.Scene()
  Web     = module.WebAPI()
  Files   = module.Files()
  Offline = module.Offline()
  DB      = module.OfflineDB() 

  commandLines['help'] = function()
    for c,f in pairs(commandLines) do
      Log(LOG.LOG,"Command: -%s",c)
    end
  end

  if arg[1] then
    local cmd = arg[1]
    if cmd:sub(1,1)=='-' then
      cmd = cmd:sub(2)
      if commandLines[cmd] then --- When fibaroapiHC3.lua is used as a command from ZBS
        commandLines[cmd](select(2,table.unpack(arg)))
        os.exit()
      end
    end
    Log(LOG.ERROR,"Unrecognized command line argument: %s",table.concat(arg," "))
    os.exit()
  end

  local function DEFAULT(v,d) if v~=nil then return v else return d end end
  hc3_emulator.offline = DEFAULT(hc3_emulator.offline,false)
  hc3_emulator.defaultDevice     = DEFAULT(hc3_emulator.defaultDevice,"com.fibaro.binarySwitch")
  hc3_emulator.autocreateDevices = DEFAULT(hc3_emulator.autocreateDevices,true)
  hc3_emulator.autocreateGlobals = DEFAULT(hc3_emulator.autocreateGlobals,true)

  hc3_emulator.updateViewLayout  = QA.updateViewLayout
  hc3_emulator.getUI             = QA.getQAUI
  hc3_emulator.createQuickApp    = QA.createQuickApp
  hc3_emulator.createProxy       = QA.createProxy
  hc3_emulator.getIPaddress      = Util.getIPaddress
  hc3_emulator.createDevice      = Offline.createDevice --(id,tp)
  hc3_emulator.cache             = Trigger.cache 
  hc3_emulator.copyFromHC3       = DB.copyFromHC3

--[[
hc3_emulator.credentials
hc3_emulator.offline
args.speed
args.traceFibaro
args.startWeb
args.startTime / hc3_emulator.startTime
hc3_emulator.preamble
hc3_emulator.asyncHTTP
args.restartQA
--]]

  local function startUp(file)

    if not hc3_emulator.offline and not hc3_emulator.credentials then
      error("Missing HC3 credentials -- hc3_emulator.credentials{ip=<IP>,user=<string>,pwd=<string>}")
    end
    hc3_emulator.speeding = hc3_emulator.speed==true and 48 or tonumber(hc3_emulator.speed)
    if hc3_emulator.traceFibaro then Util.traceFibaro() end

    Log(LOG.SYS,"HC3 SDK v%s",hc3_emulator.version)
    if hc3_emulator.deploy==true then Files.deploy(file) os.exit() end

    if hc3_emulator.speeding then Log(LOG.SYS,"Speeding %s hours",hc3_emulator.speeding) end
    if not (hc3_emulator.startWeb==false) then Web.start(Util.getIPaddress()) end

    if type(hc3_emulator.startTime) == 'string' then 
      Timer.setEmulatorTime(Util.parseDate(hc3_emulator.startTime)) 
    end

    if hc3_emulator.offline then
      if hc3_emulator.loadDB then DB.loadDB() end
      if #Offline.db.get("/settings/location")==0 then
        Offline.db.modify("/settings","location",{latitude=52.520008,longitude=13.404954}) -- Berlin
      end
      Offline.start()
    end
    local codeType = "Code"
    ::RESTART::
    Timer.setTimeout(function() 
        if hc3_emulator.speeding then Timer.speedTime(hc3_emulator.speeding) end
        if type(hc3_emulator.preamble) == 'function' then -- Stuff to run before starting up QA/Scene
          hc3_emulator.inhibitTriggers = true -- preamble stuff don't generate triggers
          hc3_emulator.preamble() 
          hc3_emulator.inhibitTriggers = false
        end
        if hc3_emulator.asyncHTTP then net.HTTPClient = net.HTTPAsyncClient end
        if hc3_emulator.credentials then 
          hc3_emulator.BasicAuthorization = "Basic "..Util.base64(hc3_emulator.credentials.user..":"..hc3_emulator.credentials.pwd)
        end
        dofile(file)
        if hc3_emulator.conditions and hc3_emulator.actions then
          codeType="Scene"
          Scene.start()  -- Run a scene
        elseif QuickApp.onInit then
          codeType = "QuickApp"
          hc3_emulator.isQA = true
          QA.start()
        end
      end,0,"Main")
    local stat,res = xpcall(Timer.start,
      function(err)
        Log(LOG.ERROR,"%s crashed: %s",codeType,err)
        print(debug.traceback(err))
      end)
    if hc3_emulator.restartQA then goto RESTART end
  end

  local file = debug.getinfo(3, 'S')                                  -- Find out what file we are running
  if file and file.source then
    file = file.source
    if not file:sub(1,1)=='@' then error("Can't locate file:"..file) end  -- Is it a file?
    file = file:sub(2)
    startUp(file)
  end
  os.exit()