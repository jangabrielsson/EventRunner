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
-  @10der, forum.fibaro.com

Sources:
json        -- Copyright (c) 2019 rxi
persistence -- Copyright (c) 2010 Gerhard Roethlin
--]]

local FIBAROAPIHC3_VERSION = "0.109" 

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

Common hc3_emulator parameters:
---------------------------------
hc3_emulator.name=<string>,          -- Name of QuickApp, default "QuickApp"
hc3_emulator.id=<QuickApp ID>,       -- ID of QuickApp. Normally let emulator asign ID. (usually 999 for non-proxy QA)
hc3_emulator.poll=<poll interval>,   -- Time in ms to poll the HC3 for triggers. default false
hc3_emulator.type=<type>,            -- default "com.fibaro.binarySwitch"
hc3_emulator.speed=<speedtime>,      -- If not false, time in hours the emulator should speed. default false
hc3_emulator.proxy=<boolean>         -- If true create HC3 procy. default false
hc3_emulator.UI=<UI table>,          -- Table defining buttons/sliders/labels. default {}
hc3_emulator.quickVars=<table>,      -- Table with values to assign quickAppVariables. default {}, should be a key-value table
hc3_emulator.offline=<boolean>,      -- If true run offline with simulated devices. default false
hc3_emulator.apiHTTPS=<boolean>,     -- If true use https to call HC3 REST apis. default false
hc3_emulator.deploy=<boolean>,       -- If true deploy code to HC3 instead of running it. default false
hc3_emulator.db=<boolean/string>,    -- If true load data from "HC3sdk.db" or string file
hc3_emulator.colorDebug=<bbolean>    -- If use color console logs in ZBS - not so good if you cut&paste to other apps...

Implemented APIs:
---------------------------------
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
--fibaro.getAllDeviceIds()
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
{type='alarm', property='armed', id=<id>, value=<value>}
{type='alarm', property='breached', id=<id>, value=<value>}
{type='alarm', property='homeArmed', value=<value>}
{type='alarm', property='homeBreached', value=<value>}
{type='weather', property=<prop>, value=<value>, old=<value>}
{type='global-variable', property=<name>, value=<value>, old=<value>}
{type='device', id=<id>, property=<property>, value=<value>, old=<value>}
{type='device', id=<id>, property='centralSceneEvent', value={keyId=<value>, keyAttribute=<value>}}
{type='device', id=<id>, property='accessControlEvent', value=<value>}
{type='device', id=<id>, property='sceneActivationEvent', value=<value>}
{type='profile', property='activeProfile', value=<value>, old=<value>}
{type='custom-event', name=<name>}

json.encode(expr)
json.decode(string)

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

local Util,Timer,QA,Scene,Web,Trigger,Offline,Files   -- local modules
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
  function __fibaro_get_devices() return api.get("/devices") end
  function __fibaro_get_room (roomID) __assert_type(roomID,"number") return api.get("/rooms/"..roomID) end
  function __fibaro_get_scene(sceneID) __assert_type(sceneID,"number") return api.get("/scenes/"..sceneID) end
  function __fibaro_get_global_variable(varName) __assert_type(varName ,"string") 
    local c = cache.read('globals',0,varName) or api.get("/globalVariables/"..varName) 
    cache.write('globals',0,varName,c)
    return c
  end
  function __fibaro_get_device_property(deviceId ,propertyName)
    __assert_type(deviceId,"number")
    __assert_type(propertyName,"string")
    local c = cache.read('devices',deviceId,propertyName) or api.get("/devices/"..deviceId.."/properties/"..propertyName) 
    cache.write('devices',deviceId,propertyName,c)
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
        if tonumber(val) then val=val> 0 end
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
    local function encode(s) return tostring(s) end --urlencode(tostring(s)) end
    if type(filter) ~= 'table' or (type(filter) == 'table' and next( filter ) == nil) then 
      return fibaro.getIds(__fibaro_get_devices()) 
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

  function fibaro.alert(alertType, users, msg) 
    alertType = ({push='sendGlobalPushNotifications',email='sendGlobalEmailNotifications',sms='sendSms'})[alertType]
    assert(alertType,"Missing alert type: 'push', 'email', 'sms'")
    __assert_type(users,'table') 
    for _,u in ipairs(users) do fibaro.call(u,alertType,msg,"false") end
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

-- An emulation of Fibaro's net.HTTPClient, net.TCPSocket() and net.UDPSocket()
  net = net or {mindelay=10,maxdelay=1000} 

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

  function net.TCPSocket(opts) 
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

  function net.UDPSocket(opts) --error("TCPSocket - Not implemented yet")
    self = {}
    opts = opts or {}
    local sock = socket.udp()
    if opts.broadcast~=nil then sock:setoption("broadcast", opts.broadcast) end
    if opts.timeout~=nil then sock:settimeout(opts.timeout) end

    function self:sendTo(datagram, ip,port, callbacks) 
      local stat,res = sock:sendto(datagram, ip, port)
      if stat and callbacks.success then 
        pcall(function() callbacks.success(1) end)
      elseif stat==nil and callbacks.error then
        pcall(function() callbacks.error(res) end)
      end
    end 
    function self:receive(callbacks) 
      local stat,res = sock:receive()
      if stat and callbacks.success then 
        pcall(function() callbacks.success(stat) end)
      elseif stat==nil and callbacks.error then
        pcall(function() callbacks.error(res) end)
      end
    end
    function self:close() sock:close() end
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
    local r, c, h
    if hc3_emulator.apiHTTPS then
      req.url = "https"..req.url:sub(5)
      r,c,h = https.request(req)
    else 
      r,c,h = http.request(req)
    end
    if not r then
      Log(LOG.ERROR,"Error connnecting to HC3: '%s' - URL: '%s'.",c,req.url)
      return nil,c, h
    end
    if c>=200 and c<300 then
      return resp[1] and safeDecode(table.concat(resp)) or nil,c
    end
    return nil,c, h
    --error(format("HC3 returned error '%d %s' - URL: '%s'.",c,resp[1] or "",req.url))
  end
  hc3_emulator.rawCall = rawCall
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
    for k,v in pairs(device) do 
      self[k]=v 
    end
    local cbs = {}
    for _,cb in ipairs(self.properties.uiCallbacks or {}) do
      cbs[cb.name]=cbs[cb.name] or {}
      cbs[cb.name][cb.eventType] = cb.callback
    end
    self.uiCallbacks = cbs
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

  function QuickAppBase:debug(...) fibaro.debug("",table.concat({...})) end -- Should we add _TAG ?
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
    local vs = self.properties.quickAppVariables or {}
    for _,v in ipairs(vs) do
      if v.name==name then v.value=value; return end
    end
    vs[#vs+1]={name=name,value=value}
    self.properties.quickAppVariables = vs
    if self.hasProxy then
      self:updateProperty('quickAppVariables', self.properties.quickAppVariables)
    end
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
      -- Override quickAppVariables with ex. values from hc3_emulator.quickVars
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

  local function makeInitialProperties(UI,vars,height)
    local ip = {}
    vars = vars or {}
    transformUI(UI)
    ip.viewLayout = mkViewLayout(UI,height)
    ip.uiCallbacks = uiStruct2uiCallbacks(UI)
    ip.apiVersion = "1.2"
    local varList = {}
    for n,v in pairs(vars) do varList[#varList+1]={name=n,value=v} end
    ip.quickAppVariables = varList
    ip.typeTemplateInitialized=true
    return ip
  end

  local function pruneCode(code)
    local c = code:match("%-%-%-%-%-%-%-%-%-%-%- Code.-\n(.*)")
    return c or code
  end

  local function replaceRequires(code)
    pcall(function()
        code = code:gsub([[require%s*%(%s*[%"%'](.-)[%"%']%s*%)]],
          function(m) 
            f = io.open(m..".lua")
            if f then
              local c = f:read("*all")
              return pruneCode(c)
            end
            return ""
          end)
      end)
    return code
  end

  local function updateFiles(newFiles,id)
    local oldFiles = api.get("/quickApp/"..id.."/files")
    local newFileMap,oldFileMap = {},{}
    for _,f in ipairs(newFiles) do newFileMap[f.name]=f end
    for _,f in ipairs(oldFiles) do oldFileMap[f.name]=f end
    for _,f in pairs(newFileMap) do
      if oldFileMap[f.name] then
        local _,res = api.put("/quickApp/"..id.."/files/"..f.name,f) -- Update existing
        if res > 201 then return res end
      else
        local _,res = api.post("/quickApp/"..id.."/files",f)         -- Create new
        if res > 201 then return res end
      end
    end
    for _,f in pairs(oldFileMap) do
      if not newFileMap[f.name] then
        local _,res = api.delete("/quickApp/"..id.."/files/"..f.name)
        if res > 201 then return res end
      end
    end
    return 200
  end

  function hc3_emulator.FILE(file,name) dofile(file) end

  local function createFilesFromSource(source)
    local files = {}
    pcall(function() 
        source = source:gsub([[hc3_emulator%s*.%s*FILE%s*%(%s*[%"%'](.-)[%"%']%s*,%s*[%"%'](.-)[%"%']%s*%)]],
          function(file,name) 
            f = io.open(file)
            if f then
              local c = f:read("*all")
              c = pruneCode(c)
              files[#files+1]={name=name,content=c,isMain=false,isOpen=false}
            else Log(LOG.ERROR,"Can't find FILE:%s - ignoring",file) end
            return ""
          end)
      end)
    table.insert(files,1,{name="main",content=pruneCode(source),isMain=true,isOpen=false})
    return files
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
    if hc3_emulator.HC3version < "5.040.37" then
      error("Sorry, QuickApp creation need HC3 version >= 5.040.37")
    end
    local d = {} -- Our device
    d.name = args.name or "QuickApp"
    d.type = args.type or "com.fibaro.binarySensor"
    local files = args.code or ""
    --body = replaceRequires(body)
    local UI = args.UI or {}
    local variables = args.quickVars or {}
    local dryRun = args.dryrun or false
    d.apiVersion = "1.2"
    d.initialProperties = makeInitialProperties(UI,variables,args.height)
    if type(files)=='string' then files = createFilesFromSource(files) end
    d.files  = {}
    for _,f in ipairs(files) do f.isOpen=false; d.files[#d.files+1]=f end
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
            viewLayout= d.initialProperties.viewLayout,
            uiCallBacks = d.initialProperties.uiCallbacks,
          }
        })
      if res <= 201 then
        res = updateFiles(files,args.id)
      end
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
    if ID and tp ~= device.type then
      Log(LOG.SYS,"Proxy type changed")
      ID=nil
    end
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

    hc3_emulator.name = name
    hc3_emulator.type = ptype

    for k,v in pairs(quickVars) do 
      if type(v)=='string' and v:match("^%$CREDS") then
        local p = "return hc3_emulator.credentials"..v:match("^%$CREDS(.*)") 
        quickVars[k]=load(p)()
      end
    end

    local qv = {}
    for k,v in pairs(quickVars) do qv[#qv+1]={name=k,value=v} end
    local deviceStruct= {
      id=hc3_emulator.id or 999,name=name,type=ptype,
      properties={quickAppVariables=qv}
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
      end
    end

    if hc3_emulator.offline or not plugin.isProxy and UI then
      transformUI(UI)
      deviceStruct.properties.uiCallbacks  = uiStruct2uiCallbacks(UI)
    end

    plugin.mainDeviceId = deviceStruct.id
    hc3_emulator.id = plugin.mainDeviceId
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
  commandLines['deploy']=function(file) 
    _G["DEPLOY"]=true
    arg={}
    hc3_emulator=nil
    loadfile(file,nil,_G)()
    os.exit()
  end

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
  self.cacheStore=cache
  function cache.write(type,id,prop,value) 
    cache[type][id] = cache[type][id] or {}
    cache[type][id][prop]=value 
  end
  function cache.read(type,id,prop) 
    return hc3_emulator.speeding and hc3_emulator.polling and cache[type][id] and cache[type][id][prop]
  end

  local function post(event) 
    if hc3_emulator.supressTrigger[event.type] then return end
    if _debugFlags.trigger then Log(LOG.DEBUG,"Incoming trigger:%s",json.encode(event)) end
    if HC3_handleEvent then HC3_handleEvent(event) end 
  end

  local EventTypes = { -- There are more, but these are what I seen so far...
    AlarmPartitionArmedEvent = function(d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
    AlarmPartitionBreachedEvent = function(d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
    HomeArmStateChangedEvent = function(d) post({type='alarm', property='homeArmed', value=d.newValue}) end,
    HomeBreachedEvent = function(d) post({type='alarm', property='homeBreached', value=d.breached}) end,
    WeatherChangedEvent = function(d) post({type='weather',property=d.change, value=d.newValue, old=d.oldValue}) end,
    GlobalVariableChangedEvent = function(d)
      cache.write('globals',0,d.variableName,{name=d.variableName, value = d.newValue, modified=os.time()})
      if d.variableName == tickEvent then return end
      post({type='global-variable', property=d.variableName, value=d.newValue, old=d.oldValue})
    end,
    DevicePropertyUpdatedEvent = function(d)
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
        cache.write('devices',d.id,d.property,{value=d.newValue, modified=os.time()})    
        post({type='device', id=d.id, property=d.property, value=d.newValue, old=d.oldValue})
      end
    end,
    CentralSceneEvent = function(d) 
      cache.write('centralSceneEvents',d.deviceId,"",d) 
      post({type='device', property='centralSceneEvent', id=d.deviceId, value = {keyId=d.keyId, keyAttribute=d.keyAttribute}}) 
    end,
    AccessControlEvent = function(d) 
      cache.write('accessControlEvent',d.id,"",d)
      post({type='device', property='accessControlEvent', id = d.deviceID, value=d}) 
    end,
    ActiveProfileChangedEvent = function(d) 
      post({type='profile',property='activeProfile',value=d.newActiveProfile, old=d.oldActiveProfile}) 
    end,
    CustomEvent = function(d) if d.name == tickEvent then return else post({type='custom-event', name=d.name}) end end,
    PluginChangedViewEvent = function() end,
    WizardStepStateChangedEvent = function() end,
    UpdateReadyEvent = function() end,
    SceneRunningInstancesEvent = function() end,
    DeviceRemovedEvent = function() end,
    DeviceChangedRoomEvent = function() end,    
    DeviceCreatedEvent = function() end,
    DeviceModifiedEvent = function() end,
    SceneStartedEvent = function() end,
    SceneFinishedEvent = function() end,
    SceneCreatedEvent = function() end,
    SceneRemovedEvent = function() end,
    PluginProcessCrashedEvent = function()  end,
    onUIEvent = function() end,
    OnlineStatusUpdatedEvent = function() end,
    NotificationCreatedEvent = function() end,
    NotificationRemovedEvent = function() end,
    NotificationUpdatedEvent = function() end,
    RoomCreatedEvent = function() end,
    RoomRemovedEvent = function() end,
    RoomModifiedEvent = function() end,
    SectionCreatedEvent = function() end,
    SectionRemovedEvent = function() end,
    SectionModifiedEvent = function() end,
    DeviceActionRanEvent = function() end,
  }

  local function checkEvents(events)
    if not events[1] then events={events} end
    for _,e in ipairs(events) do
      local eh = EventTypes[e.type]
      if eh then eh(e.data)
      elseif eh==nil then Log(LOG.WARNING,"Unhandled event:%s -- please report",json.encode(e)) end
    end
    self.refreshStates.addEvents(events)
  end

  local lastRefresh = 0

  local function pollOnce() -- Doesn't work, we need predictable returns
    if hc3_emulator.offline then return Offline.api("GET","/refreshStates?last=" .. lastRefresh) end
    local resp = {}
    local req={ 
      method="GET",
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
    local r, c, h = http.request(req)       -- ToDo https
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
  self.checkEvents = checkEvents
  self.cache = cache
  return self
end

-------------- Utilities -----------------------------
function module.Utilities()
  local self = {}

  function self.property(getter,setter)
    return {['%CLASSPROPERTY%']=true,get=getter,set=setter}
  end

  local function isProp(x) return type(x)=='table' and x['%CLASSPROPERTY%']  end

  function self.class(name)
    local c = {}    -- a new class instance
    local mt = {}

--  mt.__index = function(tab,key) return rawget(c,key) end
--  mt.__newindex = function(tab,key,value) rawset(c,key,value) end
    mt.__call = function(class_tbl, ...)
      local obj = {}
      setmetatable(obj,c)
      if c.__init then
        c.__init(obj,...)
      else 
        if c.__base and c.__base.__init then
          c.__base.__init(obj, ...)
        end
      end
      return obj
    end

    c.__index = function(tab,key)
      local v = c[key]
      if v==nil then
        local p = rawget(tab,'__props')
        if p and p[key] then return p[key].get(tab) end
      end
      return rawget(c,key) --c[key]
    end

    c.__newindex = function(tab,key,value)
      local p = rawget(tab,'__props')
      if isProp(value) then
        if not p then 
          p = {}
          rawset(tab,'__props',p)
        end
        p[key]=value
      elseif p and p[key] then p[key].set(tab,value) 
      else rawset(c,key,value) end
    end

    setmetatable(c, mt)
    _G[name] = c

    return function(base)
      local mb = getmetatable(base)
      setmetatable(base,nil)
      for i,v in pairs(base) do 
        if not ({__index=true,__newindex=true,__base=true})[i] then 
          rawset(c,i,v) 
        end
      end
      rawset(c,'__base',base)
      setmetatable(base,mb)
      return c
    end
  end

  if not class then     -- If we already have 'class' from Luabind - let's hope it wors as a substitute....
    class=self.class 
    property=self.property 
  end 

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
            str = color..logHeader(100,str).."\027[0m"
            print(format("%s |%s|: %s",os.date("[%d.%m.%Y] [%X]"),"-----",str))
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
    local t1 = os.time(t)
    local t2 = os.date("*t",t1)
    if t.isdst ~= t2.isdst then t.isdst = t2.isdst t1 = os.time(t) end
    return t1
  end

  function self.printf(arg1,...) local args={...} if #args==0 then print(arg1) else print(format(arg1,...)) end end
  function self.split(str, sep)
    local fields,s = {},sep or "%s"
    str:gsub("([^"..s.."]+)", function(c) fields[#fields + 1] = c end)
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

  -- /api/devices/hierarchy 5.031.33
  typeHierarchy = 
[[{"children":[{"children":[],"type":"com.fibaro.zwaveDevice"},{"children":[],"type":"com.fibaro.zwaveController"},{"children":[{"children":[],"type":"com.fibaro.yrWeather"},{"children":[],"type":"com.fibaro.WeatherProvider"}],"type":"com.fibaro.weather"},{"children":[],"type":"com.fibaro.usbPort"},{"children":[],"type":"com.fibaro.setPointForwarder"},{"children":[{"children":[{"children":[],"type":"com.fibaro.windSensor"},{"children":[],"type":"com.fibaro.temperatureSensor"},{"children":[],"type":"com.fibaro.seismometer"},{"children":[],"type":"com.fibaro.rainSensor"},{"children":[],"type":"com.fibaro.powerSensor"},{"children":[],"type":"com.fibaro.lightSensor"},{"children":[],"type":"com.fibaro.humiditySensor"}],"type":"com.fibaro.multilevelSensor"},{"children":[{"children":[{"children":[],"type":"com.fibaro.satelZone"},{"children":[{"children":[{"children":[],"type":"com.fibaro.FGMS001v2"}],"type":"com.fibaro.FGMS001"}],"type":"com.fibaro.motionSensor"},{"children":[],"type":"com.fibaro.envisaLinkZone"},{"children":[],"type":"com.fibaro.dscZone"},{"children":[{"children":[],"type":"com.fibaro.windowSensor"},{"children":[],"type":"com.fibaro.rollerShutterSensor"},{"children":[],"type":"com.fibaro.gateSensor"},{"children":[],"type":"com.fibaro.doorSensor"},{"children":[],"type":"com.fibaro.FGDW002"}],"type":"com.fibaro.doorWindowSensor"}],"type":"com.fibaro.securitySensor"},{"children":[],"type":"com.fibaro.safetySensor"},{"children":[],"type":"com.fibaro.rainDetector"},{"children":[{"children":[],"type":"com.fibaro.heatDetector"},{"children":[{"children":[{"children":[],"type":"com.fibaro.FGSS001"}],"type":"com.fibaro.smokeSensor"},{"children":[{"children":[],"type":"com.fibaro.FGCD001"}],"type":"com.fibaro.coDetector"}],"type":"com.fibaro.gasDetector"},{"children":[{"children":[],"type":"com.fibaro.FGFS101"}],"type":"com.fibaro.floodSensor"},{"children":[],"type":"com.fibaro.fireDetector"}],"type":"com.fibaro.lifeDangerSensor"}],"type":"com.fibaro.binarySensor"},{"children":[],"type":"com.fibaro.accelerometer"}],"type":"com.fibaro.sensor"},{"children":[{"children":[{"children":[],"type":"com.fibaro.mobotix"},{"children":[],"type":"com.fibaro.heliosGold"},{"children":[],"type":"com.fibaro.heliosBasic"},{"children":[],"type":"com.fibaro.alphatechFarfisa"}],"type":"com.fibaro.intercom"},{"children":[{"children":[],"type":"com.fibaro.schlage"},{"children":[],"type":"com.fibaro.polyControl"},{"children":[],"type":"com.fibaro.kwikset"},{"children":[],"type":"com.fibaro.gerda"}],"type":"com.fibaro.doorLock"},{"children":[{"children":[{"children":[{"children":[],"type":"com.fibaro.fibaroIntercom"}],"type":"com.fibaro.videoGate"}],"type":"com.fibaro.ipCamera"}],"type":"com.fibaro.camera"},{"children":[{"children":[],"type":"com.fibaro.satelPartition"},{"children":[],"type":"com.fibaro.envisaLinkPartition"},{"children":[],"type":"com.fibaro.dscPartition"}],"type":"com.fibaro.alarmPartition"}],"type":"com.fibaro.securityMonitoring"},{"children":[],"type":"com.fibaro.samsungWasher"},{"children":[],"type":"com.fibaro.samsungSmartAppliances"},{"children":[],"type":"com.fibaro.samsungRobotCleaner"},{"children":[],"type":"com.fibaro.samsungRefrigerator"},{"children":[],"type":"com.fibaro.samsungOven"},{"children":[],"type":"com.fibaro.samsungDryer"},{"children":[],"type":"com.fibaro.samsungDishwasher"},{"children":[],"type":"com.fibaro.samsungAirPurifier"},{"children":[],"type":"com.fibaro.russoundXZone4"},{"children":[],"type":"com.fibaro.russoundXSource"},{"children":[],"type":"com.fibaro.russoundX5"},{"children":[],"type":"com.fibaro.russoundMCA88X"},{"children":[],"type":"com.fibaro.russoundController"},{"children":[],"type":"com.fibaro.powerMeter"},{"children":[],"type":"com.fibaro.planikaFLA3"},{"children":[],"type":"com.fibaro.philipsHue"},{"children":[{"children":[],"type":"com.fibaro.xbmc"},{"children":[],"type":"com.fibaro.wakeOnLan"},{"children":[],"type":"com.fibaro.sonosSpeaker"},{"children":[],"type":"com.fibaro.russoundXZone4Zone"},{"children":[],"type":"com.fibaro.russoundXSourceZone"},{"children":[],"type":"com.fibaro.russoundX5Zone"},{"children":[],"type":"com.fibaro.russoundMCA88XZone"},{"children":[{"children":[],"type":"com.fibaro.davisVantage"}],"type":"com.fibaro.receiver"},{"children":[],"type":"com.fibaro.philipsTV"},{"children":[],"type":"com.fibaro.nuvoZone"},{"children":[],"type":"com.fibaro.nuvoPlayer"},{"children":[],"type":"com.fibaro.initialstate"},{"children":[],"type":"com.fibaro.denonHeosZone"},{"children":[],"type":"com.fibaro.denonHeosGroup"}],"type":"com.fibaro.multimedia"},{"children":[{"children":[],"type":"com.fibaro.waterMeter"},{"children":[],"type":"com.fibaro.gasMeter"},{"children":[],"type":"com.fibaro.energyMeter"}],"type":"com.fibaro.meter"},{"children":[],"type":"com.fibaro.logitechHarmonyHub"},{"children":[],"type":"com.fibaro.logitechHarmonyActivity"},{"children":[],"type":"com.fibaro.logitechHarmonyAccount"},{"children":[{"children":[{"children":[],"type":"com.fibaro.thermostatHorstmann"}],"type":"com.fibaro.thermostatDanfoss"},{"children":[],"type":"com.fibaro.samsungAirConditioner"},{"children":[],"type":"com.fibaro.operatingModeHorstmann"},{"children":[],"type":"com.fibaro.hvacSystemHeat"},{"children":[],"type":"com.fibaro.hvacSystemCool"},{"children":[],"type":"com.fibaro.hvacSystemAuto"},{"children":[],"type":"com.fibaro.coolAutomationHvac"},{"children":[],"type":"com.fibaro.FGT001"}],"type":"com.fibaro.hvacSystem"},{"children":[],"type":"com.fibaro.hunterDouglasScene"},{"children":[],"type":"com.fibaro.hunterDouglas"},{"children":[],"type":"com.fibaro.humidifier"},{"children":[],"type":"com.fibaro.genericZwaveDevice"},{"children":[],"type":"com.fibaro.genericDevice"},{"children":[],"type":"com.fibaro.deviceController"},{"children":[],"type":"com.fibaro.denonHeos"},{"children":[],"type":"com.fibaro.coolAutomation"},{"children":[{"children":[],"type":"com.fibaro.satelAlarm"},{"children":[],"type":"com.fibaro.envisaLinkAlarm"},{"children":[],"type":"com.fibaro.dscAlarm"}],"type":"com.fibaro.alarm"},{"children":[{"children":[],"type":"com.fibaro.soundSwitch"},{"children":[],"type":"com.fibaro.remoteSwitch"},{"children":[{"children":[{"children":[],"type":"com.fibaro.FGPB101"},{"children":[],"type":"com.fibaro.FGKF601"},{"children":[],"type":"com.fibaro.FGGC001"}],"type":"com.fibaro.remoteSceneController"}],"type":"com.fibaro.remoteController"},{"children":[{"children":[],"type":"com.fibaro.sprinkler"},{"children":[],"type":"com.fibaro.satelOutput"},{"children":[{"children":[{"children":[],"type":"com.fibaro.philipsHueLight"},{"children":[],"type":"com.fibaro.FGRGBW442CC"},{"children":[],"type":"com.fibaro.FGRGBW441M"}],"type":"com.fibaro.colorController"},{"children":[],"type":"com.fibaro.FGWD111"},{"children":[],"type":"com.fibaro.FGD212"}],"type":"com.fibaro.multilevelSwitch"},{"children":[{"children":[],"type":"com.fibaro.FGWPI121"},{"children":[],"type":"com.fibaro.FGWPG121"},{"children":[],"type":"com.fibaro.FGWPG111"},{"children":[],"type":"com.fibaro.FGWPB121"},{"children":[],"type":"com.fibaro.FGWPB111"},{"children":[],"type":"com.fibaro.FGWP102"},{"children":[],"type":"com.fibaro.FGWP101"}],"type":"com.fibaro.FGWP"},{"children":[],"type":"com.fibaro.FGWOEF011"},{"children":[],"type":"com.fibaro.FGWDS221"}],"type":"com.fibaro.binarySwitch"},{"children":[{"children":[{"children":[],"type":"com.fibaro.tubularMotor"},{"children":[],"type":"com.fibaro.FGR221"},{"children":[{"children":[],"type":"com.fibaro.FGWR111"},{"children":[],"type":"com.fibaro.FGRM222"},{"children":[],"type":"com.fibaro.FGR223"}],"type":"com.fibaro.FGR"}],"type":"com.fibaro.rollerShutter"}],"type":"com.fibaro.baseShutter"},{"children":[],"type":"com.fibaro.barrier"}],"type":"com.fibaro.actor"},{"children":[],"type":"com.fibaro.FGRGBW442"},{"children":[],"type":"com.fibaro.FGBS222"}],"type":"com.fibaro.device"}]]

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
  local lastDeviceUpdate = 0

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
      ["/fibaroapiHC3/webCMD%?(.*)"] = function(client,ref,body,args)
        local res = {}
        args = split(args,"&")
        for _,a in ipairs(args) do
          local i,v = a:match("^(%w+)=(.*)")
          res[i]=v
        end
        fibaro.call(tonumber(res.id),res.cmd,res.cmd=='setValue' and res.value)
        client:send("HTTP/1.1 302 Found\nLocation: "..(ref or "/web/main").."\n")
      end,
      ["/fibaroapiHC3/webDEV"] = function(client,ref,body,args)
        local res = {}
        for id,str in pairs(Trigger.cacheStore.devices or {}) do
          if str.value then
            if str.value.modified >= lastDeviceUpdate then
              local r = str.value.value
              if type(r)=='number' then r=r>0 end
              res["#D"..id] = r and "#00FF00" or "lightgrey"
              if tonumber(str.value.value) then 
                res[tostring(id)] = tostring(str.value.value)
              end
              Log(LOG.LOG,"Update %s, %s",id,str.value.value)
            end
          end
        end
        lastDeviceUpdate = os.time()
        res = json.encode(res)
        client:send("HTTP/1.1 200 OK\n")
        client:send("Access-Control-Allow-Headers: Origin\n")
        client:send("Content-Type: application/json; charset=utf-8\n")
        client:send("Content-Length: "..res:len())
        client:send("\n\n")
        client:send(res) 
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
            local l = p.funs[tonumber(i)]()
            return l --p.funs[tonumber(i)]()
          end)
      end)
    if not stat then
      return Pages.renderError(res)
    else 
      p.static = p.static and res
      return res 
    end
  end

  function Pages.compile(p)
    local funs={}
    p.cpage=p.page:gsub("<<<(.-)>>>",
      function(code)
        local LENV = {
          ["Web"]=Web,["Pages"]=Pages,hc3_emulator=hc3_emulator,
          ["FIBAROAPIHC3_VERSION"] = FIBAROAPIHC3_VERSION
        }
        local f = format("do %s end",code)
        f,m = load(f,nil,nil,LENV)
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

<!DOCTYPE html>
<html>
<head>
<title>Error</title>
<meta charset="utf-8">
</head>
<body>
<pre>%s</pre>
</body>
</html>
]]

  Pages.P_MAIN = 
[[HTTP/1.1 200 OK
Content-Type: text/html

<!DOCTYPE html>
<html>
<head>
<title>fibaroapiHC3</title>
<meta charset="utf-8">
<!-- Bootstrap CSS -->
<<<return Web._PAGE_HEADER>>>
<script>
 $(document).ready(function(){
  $("#mainN").closest('.nav-item').addClass('active'); 
 });
</script>
</head>
<body>
<div style="margin-left: 20px;">
<<<return Web._PAGE_NAV>>>
<t1>fibaroapiHC3 v<<<return FIBAROAPIHC3_VERSION>>></t1><br>
<t1>poll: <<<if hc3_emulator.poll== nil then return "false" else return hc3_emulator.poll end>>></t1><br>
<t1>proxy: <<<return hc3_emulator.proxy== nil then return "false" else return hc3_emulator.proxy end>>></t1>
</div>
<<<return Web._PAGE_FOOTER>>>
</body>
</html>
]]

  Pages.register("main",Pages.P_MAIN).static=false

  Pages.P_DEVICES = 
[[HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
Content-Type: text/html

<!DOCTYPE html>
<html>
<head>
<title>fibaroapiHC3</title>
<meta charset="utf-8">
<<<return Web._PAGE_HEADER>>>
<script>
$(document).ready(function(){
  $("#devicesN").closest('.nav-item').addClass('active');
});
function reloadData() {
   $.get("http://127.0.0.1:6872/fibaroapiHC3/webDEV",
          function(data, status) {
            //alert("Data: " + JSON.stringify(data) + "\nStatus: " + status);
             Object.keys(data).forEach(function(key) {
                var val = data[key];
                //alert(key + " " + val.f + " " + val.v)
                console.log(key + " " + val);
                if (isNaN(val)) {
                     $(key).css("background-color",val);
                } else {
                   $("#S"+key).val(val);
                   $("#L"+key).text(val);
                }
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
function QAbutton(id,cmd) {
  $.get('http://127.0.0.1:6872/fibaroapiHC3/webCMD?id='+id+'&cmd='+cmd)
}
function QAslider(id,val) {
  $.get('http://127.0.0.1:6872/fibaroapiHC3/webCMD?id='+id+'&cmd=setValue&value='+val)
}
window.onfocus = function(){ $("#auto").prop("checked", true); reloadData(); doTimer(); }
window.onblur = function(){ $("#auto").prop("checked", false); doTimer(); }
setTimeout(doTimer,10)
</script>
</head>
<body>
<div style="margin-left: 20px;">
<<<return Web._PAGE_NAV>>>
<table >
<tr>
<td >ID</td>
<td>Name</td>
<td align="center">Status</td>
<td>Controls</td>
</tr>
<<<return Web.generateDeviceList()>>>
</table>
<div class='row'><div class='col-lg-8 col-lg-offset-2'><hr></div></div>
<div>
  <button class="reload" id="X">Reload</button>
  <input type="checkbox" id="auto" name="auto" checked>
  <label for="auto">Auto</label>
</div>
</div>
<style>
tr:nth-child(even) {
  background-color: #f2f2f2;
}
.dot {
  height: 25px;
  width: 25px;
  vertical-align: middle;
  background-color: #00FF00;
  border-radius: 50%;
  display: inline-block;
}
</style>
<<<return Web._PAGE_FOOTER>>>
</body>
</html>
]]

  function Pages.renderSwitch(d)
    local ctrl = 
[[<tr >
<td style="width:30px"><label>%s</label></td>
<td style="width:150px"><label>%s</label></td>
<td style="width:80px;" align="center"><span id="D%s" class="dot"></span></td>
<td><button type="button" onClick="QAbutton(%s,'turnOn');">Turn ON</button></td>
<td><button type="button" onClick="QAbutton(%s,'turnOff');">Turn Off</button></td>
</tr>
]]
    return ctrl:format(d.id,d.name,d.id,d.id,d.id)
  end

  function Pages.renderMultilevel(d)
    local ctrl = 
[[<tr >
<td style="width:40px"><label>%s</label></td>
<td style="width:200px"><label>%s</label></td>
<td style="width:80px;" align="center"><span id="D%s" class="dot"></span></td>
<td><button type="button" onClick="QAbutton(%s,'turnOn');">Turn ON</button></td>
<td><button type="button" onClick="QAbutton(%s,'turnOff');">Turn Off</button></td>
<td> </td><td><input type="range" class="form-control-range" max="99" min="0" value="0"
    onmouseup="QAslider(%s,this.value);"
    onmouseup="QAslider(%s,this.value);"
    oninput="$('#L%s').text(value);"
    id="S%s">
</td>
<td><label id="L%s">0</label></td>
</tr>
]]
    return ctrl:format(d.id,d.name,d.id,d.id,d.id,d.id,d.id,d.id,d.id,d.id)
  end


  local devicesCache = nil
  local globalsCache = nil
  function self.invalidateDevicesPage() devicesCache = nil end
  function self.invalidateGlobalsPage() end-- globalsCache = nil end

  function self.generateDeviceList()
    if devicesCache then return devicesCache end
    local code = {}
    local devs = {}
    for _,d in ipairs(api.get("/devices") or {}) do
      local actions = d.actions or {}
      if actions.turnOn and actions.setValue then
        devs[#devs+1]={d.id,Pages.renderMultilevel(d)}
      elseif actions.turnOn then
        devs[#devs+1]={d.id,Pages.renderSwitch(d)}
      end
    end
    table.sort(devs,function(a,b) return a[1] <= b[1] end)
    for _,d in ipairs(devs) do code[#code+1]=d[2] end
    devicesCache = table.concat(code,"")
    return devicesCache
  end

  Pages.register("devices",Pages.P_DEVICES).static=false

  function self.generateGlobalList()
    if globalsCache then return globalsCache end
    local code = {}
    local glob=
[[ 
<tr>
<td style="width:200px"><label>%s</label></td>
<td><input type="text" class="form-control" placeHolder='%s' id="99"></td>
</tr>
]]
    for _,g in ipairs(api.get("/globalVariables") or {}) do
      code[#code+1]=glob:format(g.name,g.value)
    end
    table.sort(code)
    globalsCache = table.concat(code,"")
    return globalsCache
  end

  Pages.P_GLOBALS = 
[[HTTP/1.1 200 OK
Content-Type: text/html

<!DOCTYPE html>
<html>
<head>
<title>fibaroapiHC3</title>
<meta charset="utf-8">
<<<return Web._PAGE_HEADER>>>
<script>
$(document).ready(function(){
  $("#globalsN").closest('.nav-item').addClass('active'); 
});
</script>
</head>
<body>
<div style="margin-left: 20px;">
<<<return Web._PAGE_NAV>>>
<table >
<tr>
<td>Name</td>
<td>Value</td>
</tr>
<<<return Web.generateGlobalList()>>>
</table>
</div>
<style>
tr:nth-child(even) {
  background-color: #f2f2f2;
}
.dot {
  height: 25px;
  width: 25px;
  vertical-align: middle;
  background-color: #00FF00;
  border-radius: 50%;
  display: inline-block;
}
</style>
<<<return Web._PAGE_FOOTER>>>
</body>
</html>
]]

  Pages.register("globals",Pages.P_GLOBALS).static=false

  Pages.P_EVENTS = 
[[HTTP/1.1 200 OK
Content-Type: text/html

<!DOCTYPE html>
<html>
<head>
<title>fibaroapiHC3</title>
<meta charset="utf-8">
<<<return Web._PAGE_HEADER>>>
<script>
$(document).ready(function(){
  $("#eventsN").closest('.nav-item').addClass('active'); 
});
</script>
</head>
<body>
<div style="margin-left: 20px;">
<<<return Web._PAGE_NAV>>>
<table >
</table>
</div>
<style>
tr:nth-child(even) {
  background-color: #f2f2f2;
}
.dot {
  height: 25px;
  width: 25px;
  vertical-align: middle;
  background-color: #00FF00;
  border-radius: 50%;
  display: inline-block;
}
</style>
<<<return Web._PAGE_FOOTER>>>
</body>
</html>
]]

  Pages.register("events",Pages.P_EVENTS).static=false

  Pages.P_QA =
[[HTTP/1.1 200 OK
Content-Type: text/html
Access-Control-Allow-Origin: http://127.0.0.1:6872
Vary: Origin

<!DOCTYPE html>
<html>
<head>
    <title>fibaroapiHC3</title>
    <meta charset="utf-8">
<<<return Web._PAGE_HEADER>>>
<script>
$(document).ready(function(){
   $("#quickAppN").addClass('active'); 
   $("button.reload").click(reloadData);
});
function reloadData() {
   $.get("http://127.0.0.1:6872/fibaroapiHC3/webQA2?type=values",
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
  $.get('http://127.0.0.1:6872/fibaroapiHC3/webQA2?type=btn&id='+id)
}
function QAslider(id,val) {
  $.get('http://127.0.0.1:6872/fibaroapiHC3/webQA2?type=slider&id='+id+'&val='+val)
}
window.onfocus = function(){ $("#auto").prop("checked", true); reloadData(); doTimer(); }
window.onblur = function(){ $("#auto").prop("checked", false); doTimer(); }
setTimeout(doTimer,10)
</script>
</head>
<body>
<div style="margin-left: 20px;">
<<<return Web._PAGE_NAV>>>
<t1>QuickApp: '<<<return hc3_emulator.name>>>', deviceId:<<<return hc3_emulator.id>>>, type:<<<return hc3_emulator.type>>></t1>

<div class='row'><div class='col-lg-8 col-lg-offset-2'><hr></div></div>
<<<return Web.generateQA_UI()>>>
<div class='row'><div class='col-lg-8 col-lg-offset-2'><hr></div></div>
<div>
  <button class="reload" id="X">Reload</button>
  <input type="checkbox" id="auto" name="auto" checked>
  <label for="auto">Auto</label>
</div>
</div>
<<<return Web._PAGE_FOOTER>>>
<style>
button.button5 { width: 54px; }
button.button4 { width: 69px; }
button.button3 { width: 93px; }
button.button2 { width: 142px; }
button.button1 { width: 287px; }
</style>
</body>
</html>
]]

  Pages.register("quickApp",Pages.P_QA).static=false

  function Pages.renderButton(id,name,c)
    return format([[<button class="button%d" id="%s" onClick="QAbutton('%s');">%s</button>]],c,id,id,name)
  end
  function Pages.renderLabel(id,text)
    return format([[<label class="label" id="%s">%s</label>]],id,text)
  end
  function Pages.renderSlider(id,name,value)
    return format([[<input class="form-control-range" min="0" max="255"
        type="range" id="%s" value="%s" style="width: 287px;"
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
        if e.type=='button' or e.button then 
          add(Pages.renderButton(e.button,QA.getWebUIValue(e.button,"text"),#row))
        elseif e.type=="label" or e.label then 
          add(Pages.renderLabel(e.label,QA.getWebUIValue(e.label,"text")))
        elseif e.type =="slider" or e.slider then 
          add(Pages.renderSlider(e.slider,e.text,QA.getWebUIValue(e.slider,"value")))
        end
        add("&nbsp;")
      end
      add("</p>")
    end
    return table.concat(code)
  end

  self._PAGE_HEADER =
[[
<!-- Bootstrap CSS -->
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.5.1/jquery.min.js"></script>
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.0/css/bootstrap.min.css" integrity="sha384-9aIt2nRpC12Uk9gS9baDl411NQApFmC26EwAOH8WgZl5MYYxFfc+NcPb1dKGj7Sk" crossorigin="anonymous">
<meta name="viewport" content="width=device-width, initial-scale=1">
]]

  self._PAGE_FOOTER =
[[
<script src="https://cdn.jsdelivr.net/npm/popper.js@1.16.0/dist/umd/popper.min.js" integrity="sha384-Q6E9RHvbIyZFJoft+2mJbHaEWldlvI9IOYy5n3zV9zzTtmI3UksdQRVvoxMfooAo" crossorigin="anonymous"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.0/js/bootstrap.min.js" integrity="sha384-OgVRvuATP1z7JjHLkuOU7Xw704+h835Lr+6QL9UvYjZE3Ipu6Tp75j7Bh/kR0JKI" crossorigin="anonymous"></script>
]]

  self._PAGE_NAV =
[[<nav class="navbar navbar-expand-sm bg-light navbar-light">
  <ul class="navbar-nav">
    <li class="nav-item" id="mainN">
      <a class="nav-link" target="_self" href="/web/main">FibaroAPIHC3</a>
    </li>
    <li class="nav-item" id="quickAppN">
      <a class="nav-link" target="_self" href="/web/quickApp">QuickApp</a>
    <li class="nav-item" id="devicesN">
      <a class="nav-link" target="_self" href="/web/devices">Devices</a>
    </li>
    <li class="nav-item" id="globalsN">
      <a class="nav-link" target="_self" href="/web/globals">Global variables</a>
    </li>
    <li class="nav-item" id="eventsN">
      <a class="nav-link" target="_self" href="/web/events">Events</a>
    </li>
  </ul>
</nav>
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

  function self.deploy(sourceFile)
    local name,id = hc3_emulator.name
    assert(name,"Missing name for deployment")
    --local source = debug.getinfo(2, 'S').short_src
    local f = io.open(sourceFile)
    assert(f,"Can't find source file"..sourceFile)
    net.maxdelay=0
    local ds = api.get("/devices")
    for _,d in ipairs(ds) do
      if d.name==name then id=d.id; break end
    end
    local code = f:read("*all")
    Log(LOG.SYS,"Deploying '%s'",name)

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

  getHC3dir()

  commandLines['backup']=function() self.backup("all") end
  return self
end

--------------- Offline support ----------------------
function module.Offline(self)
  local refreshStates
  local offline = {}
  local resources

  local function mergeDeep(to,from)
    if type(from) == 'table' then
      if type(to)=='table' then
        for k,v in pairs(from) do
          if to[k] then to[k] = mergeDeep(to[k],v)
          else to[k]=v end
        end
        return to
      else return from end
    else return from end
  end

  class '_Global'
  function _Global:__init(name,g)
    self.data = {
      readOnly = false,
      isEnum =  false,
      enumValues = {},
      created = os.time(),
      modified = os.time(),
      name = name
    }
    mergeDeep(self.data,g or {})
    if not hc3_emulator.loadingDB then
      Log(LOG.SYS,"Global %s created",name)
    end
    if Web then Web.invalidateGlobalsPage() end
  end

  function _Global:modify(data)
    if self.data.value ~= data.value then
      Trigger.checkEvents{
        type='GlobalVariableChangedEvent',
        data={variableName=self.data.name, newValue=data.value, oldValue=self.data.value}
      }
      self.data.value = data.value
      self.data.modified = os.time()
    end
  end

  class 'OfflineDevice'
  function OfflineDevice:__init(id,type,base,data,className)
    self.data = {
      id = id,
      name = data and data.name or "Device:"..id,
      baseType = data and data.baseType or base,
      type = data and data.type or type,
      properties={},
      created = os.time(),
      modified = os.time(),
    }
    mergeDeep(self.data,data or {})
    self.propsModified={}
    self._className=className or "OfflineDevice"
    if not hc3_emulator.loadingDB then
      Log(LOG.SYS,"'%s' (%s) created",self.data.name,self._className)
    end
    if Web then Web.invalidateDevicesPage() end
  end

  function OfflineDevice:updateProperty(prop,value)
    Trigger.checkEvents{
      type='DevicePropertyUpdatedEvent', 
      data={id=self.data.id, property=prop, newValue=value, oldValue=self.data.properties[prop]}
    }
    self.propsModified[prop]=os.time()
    self.data.properties[prop]=value
  end

  function OfflineDevice:modify(data)
    for k,v in pairs(data) do
      if k == 'properties' then
        for k,v in pairs(v) do self:updateProperty(k,v) end
      else self.data[k]=v end
    end
  end

  function OfflineDevice:getProperty(prop) 
    return {
      value=self.data.properties[prop],modified=self.propsModified[prop] or self.data.created
    } 
  end

  class 'BinarySwitch'(OfflineDevice)
  function BinarySwitch:__init(id,type,base,data,className)
    OfflineDevice.__init(self,id,type,base,data,className or "BinarySwitch")
    self.data.properties.value = false
    self.data.actions={turnOn=0,turnOff=0}
  end

  function BinarySwitch:turnOn()
    if not self.data.value then
      self:updateProperty('value',true)
      self:updateProperty('state',true)
    end
  end

  function BinarySwitch:turnOff()
    if self.data.properties.value then
      self:updateProperty('value',false)
      self:updateProperty('state',false)
    end
  end

  class 'MultilevelSwitch'(OfflineDevice)
  function MultilevelSwitch:__init(id,type,base,data,className)
    OfflineDevice.__init(self,id,type,base,data,className or "MultilevelSwitch")
    self.data.properties.value = 0
    self.data.actions={turnOn=0,turnOff=0,setValue=1}
  end

  function MultilevelSwitch:setValue(value)
    if self.data.properties.value ~= value then
      if value == 0 then
        self:updateProperty('value',0)
        self:updateProperty('state',false)
      else
        self:updateProperty('value',value)
        self:updateProperty('state',false)
      end
    end
  end

  function MultilevelSwitch:turnOn() self:setValue(99) end
  function MultilevelSwitch:turnOff() self:setValue(0) end

  class 'BinarySensor'(BinarySwitch)
  function BinarySensor:__init(id,type,base,data,className)
    BinarySwitch.__init(self,id,type,base,data,className or "BinarySensor")
  end

  class 'MultilevelSensor'(MultilevelSwitch)
  function MultilevelSensor:__init(id,type,base,data,className)
    MultilevelSwitch.__init(self,id,type,base,data,className or "MultilevelSensor")
  end

  class 'HC_user'(OfflineDevice)
  function HC_user:__init(id,type,base,data,className)
    OfflineDevice.__init(self,id,type,base,data,className or "HC_user")
    self.data.actions={sendPush=1,sendEmail=2}
  end

  function HC_user:sendPush(msg)
    Log(LOG.LOG,"Push user:%s - %s",self.data.id,msg)
  end

  function HC_user:sendEmmail(subject,body)
    Log(LOG.LOG,"Email user:%s - %s,%s",self.data.id,subject,body)
  end


  local deviceClassMap = {
    ["HC_user"]=HC_user,
    ["com.fibaro.device"]=OfflineDevice,
    ["com.fibaro.actor"]=OfflineDevice,
    ["com.fibaro.voipUser"]=OfflineDevice,
    ["com.fibaro.binarySensor"]=BinarySensor,
    ["com.fibaro.binarySwitch"]=BinarySwitch,
    ["com.fibaro.multilevelSensor"]=MultilevelSensor,
    ["com.fibaro.multilevelSwitch"]=MultilevelSwitch,
  }
  local baseMap={}
  function offline.createBaseMap()
    local function findBase(h,t)
      if type(h)=='table' then
        if deviceClassMap[h.type] then t=h.type end
        if t then baseMap[h.type]=t end
        for _,c in ipairs(h.children or {}) do findBase(c,t) end
      end
    end
    findBase(typeHierarchy,nil)
    baseMap["HC_user"]="HC_user"
  end

  local function createBestDevice(type,data,force)
    if hc3_emulator.autocreateDevices or force then
      local base = baseMap[type] or "com.fibaro.multilevelSwitch"
      local device = deviceClassMap[base](data.id,type,base,data)
      return device
    end
  end

  function makeRsrcTable(constructor)
    local tab = {}
    local mt = {
      __index = function(table, index) -- get
        if rawget(tab,index) then return rawget(tab,index)
        elseif constructor then 
          local value = constructor(index)
          if value then rawset(tab,index,value) end
          return value
        end
      end,
      __newindex = function(table, index, value)
        if constructor then 
          value = constructor(index,value)
        end
        rawset(tab,index,value)
      end
    }
    setmetatable(tab,mt)
    return tab
  end

  function globalCreator(name,data) return _Global(name,data) end

  local function deviceCreator(id,data)
    local base = baseMap[hc3_emulator.defaultDevice] or "com.fibaro.multilevelSwitch"
    local device = deviceClassMap[base](id,hc3_emulator.defaultDevice,base,data)
    return device
  end

  local function resourceStructure(flag)
    return {
      devices = flag and makeRsrcTable(deviceCreator) or {},
      scenes = {},
      globalVariables = flag and makeRsrcTable(globalCreator) or {},
      customEvents = {},
      rooms = {},
      sections = {},
      profiles = {},
      settings = {
        info = {}, 
        location={}, 
        network={}, 
        led={} 
      },
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
        family = {},
        location = {},
        notifications = {},
        sprinkler = {},
        humidity = {}
      }
    }
  end

  resources = resourceStructure(true)

  offline.resources = resources

---------------- api.* handlers -- simulated calls to offline version of resources
  local function arr(tab) local res={} for _,v in pairs(tab) do res[#res+1]=v.data or v end return res end
  local function get(res,id) local r = res[id] if r then return r.data or r,200 else return nil,404 end end
  local function copyTo(from,to) for k,v in pairs(to) do if from[k] then from[k]=v end end end
  local function modify(rsrc,id,data) if rsrc[id].modify then rsrc[id]:modify(data) else copyTo(data,rsrc[id]) end end
  local function delete(resource,id) 
    if not rawget(resource,id) then return nil,401 end
    resource[id]=nil
    return nil,200
  end
  local function valueOf(v)
    if tonumber(v) then return tonumber(v) end
    if v=="true" then return true elseif v=="false" then return false else return v end
  end
  local function member(k,tab) for _,v in ipairs(tab) do if v==k then return true end end return false end
  local notificationsID=1
  local notifications={}

  local OFFLINE_HANDLERS = {
    ["GET"] = {
      ["/callAction%?deviceID=(%d+)&name=(%w+)(.*)"] = function(call,data,cType,id,action,args)
        local res = {}
        args,id = split(args,"&"),tonumber(id)
        for _,a in ipairs(args) do
          local i,v = a:match("^arg(%d+)=(.*)")
          res[tonumber(i)]=urldecode(v)
        end
        local dev = resources.devices[id]
        if not dev then return nil,404 end
        local stat,err = pcall(dev[action],dev,table.unpack(res))
        if not stat then 
          Log(LOG.ERROR,"Bad fibaro.call(%s,'%s',%s)",id,action,json.encode(res):sub(2,-2),err)
          return nil,501
        end
        return nil,200
      end,
      ["/devices/(%d+)/properties/(.+)$"] = function(call,data,cType,id,property) 
        id = tonumber(id)
        local dev = resources.devices[id]
        if not dev then return nil,404 end
        return dev:getProperty(property),200
      end,
      ["/devices/(%d+)$"] = function(call,data,cType,id) return get(resources.devices,tonumber(id)) end,
      ["/devices/?$"] = function(call,data,cType,name) return arr(resources.devices) end,    
      ["/devices/?%?(.*)"] = function(call,data,cType,args) 
        local props = {}
        args:gsub("([%w%%]+)=([%w%%%[%]%,]+)",
          function(k,v) props[k]=v end)
        local a,b = next(props)
        if a and (a:match("%%") or b:match("%%")) then
          local p2 = {}
          local urldecode = Util.urldecode
          for k,v in pairs(props) do p2[urldecode(k)]=urldecode(v) end
          props = p2
        end
        for k,v in pairs(props) do props[k]=valueOf(v) end
        local ds = arr(resources.devices) 
        local res = {}
        for _,d in ipairs(ds) do
          local match = true
          for k,v in pairs(props) do
            if k == 'interface' then
              if not member(v,d.interfaces or {}) then match=false; break end
            elseif k == 'property' then
              local prop,val = v:match("%[(.-),(.*)%]")
              val = valueOf(val)
              if d.properties[prop]~=val then match=false; break end
            elseif d[k] ~= v then match=false; break end
          end
          if match then res[#res+1]=d
          end
        end
        return res
      end,    
      ["/globalVariables/(.+)"] = function(call,data,cType,name) return get(resources.globalVariables,name) end,
      ["/globalVariables/?$"] = function(call,data,cType,name) return arr(resources.globalVariables) end,
      ["/customEvents/(.+)"] = function(call,data,cType,name) return get(resources.customEvents,name) end,
      ["/customEvents/?$"] = function(call,data,cType,name) return arr(resources.customEvents) end,
      ["/scenes/(%d+)"] = function(call,data,cType,id) return get(resources.scenes,tonumber(id)) end,
      ["/scenes/?$"] = function(call,data,cType,name) return arr(resources.scenes) end,
      ["/rooms/(%d+)"] = function(call,data,cType,id) return get(resources.rooms,tonumber(id)) end,
      ["/rooms/?$"] = function(call,data,cType,name) return arr(resources.rooms) end,
      ["/iosUser/(%d+)"] = function(call,data,cType,id) return get(resources.rooms,tonumber(id)) end,
      ["/rooms/?$"] = function(call,data,cType,name) return arr(resources.rooms) end,
      ["/sections/(%d+)"] = function(call,data,cType,id) return get(resources.sections,tonumber(id)) end,
      ["/sections/?$"] = function(call,data,cType,name) return arr(resources.sections) end,
      ["/refreshStates%?last=(%d+)"] = function(call,data,cType,last) return refreshStates.getEvents(tonumber(last)),200 end,
      ["/settings/location/?$"] = function(_) return resources.settings.location end
    },
    ["POST"] = {
      ["/globalVariables/?$"] = function(call,data,_) -- Create variable.
        data = json.decode(data)
        local a = rawget(resources.globalVariables,data.name) 
        if rawget(resources.globalVariables,data.name) then return nil,409 end
        resources.globalVariables[data.name]=data
        return resources.globalVariables[data.name],200
      end,
      ["/customEvents/?$"] = function(call,data,_) -- Create customEvent.
        data = json.decode(data)
        if rawget(resources.customEvents,data.name) then return nil,409 end
        resources.customEvents[data.name]=data
        return resources.customEvents[data.name],200
      end,
      ["/scenes/?$"] = function(call,data,_) -- Create scene.
        data = json.decode(data)
        if rawget(resources.scenes,data.id) then return nil,409 end
        resources.scenes[data.id]=data
        return resources.scenes[data.id],200
      end,
      ["/rooms/?$"] = function(call,data,_) -- Create room.
        data = json.decode(data)
        if rawget(resources.rooms,data.id) then return nil,409 end
        resources.rooms[data.id]=data
        return resources.rooms[data.id],200
      end,
      ["/sections/?$"] = function(call,data,_) -- Create section.
        data = json.decode(data)
        if rawget(resources.sections,data.id) then return nil,409 end
        resources.sections[data.id]=data
        return resources.sections[data.id],200
      end,   
      ["/devices/(%d+)/action/(.+)$"] = function(call,data,cType,id,action) -- call device action
        data = json.decode(data)
        local dev,err = resources.devices[tonumber(id)]
        if not dev then return dev,404 end
        local stat,err = pcall(dev[action],dev,table.unpack(data.args))
        if not stat then 
          Log(LOG.ERROR,"Bad fibaro.call(%s,'%s',%s)",id,action,json.encode(data.args):sub(2,-2),err)
          return nil,501
        end
        return nil,200
      end,
      ["/notificationCenter"] = function(call,data,cType)
        data = json.decode(data)
        notificationsID=notificationsID+1
        notifications[notificationsID]=data
        data.id=notificationsID
        Log(LOG.LOG,"InfoCenter(%s):%s, %s - %s",data.priority,data.id,data.data.title,data.data.text)
        return data,200
      end,
      ["/customEvents/(.+)$"] = function(call,data,cType,name)
        if not rawget(resources.customEvents,name) then return nil,409 end
        Trigger.checkEvents({type='CustomEvent', data={name=name,}})
      end
    },
    ["PUT"] = {
      ["/globalVariables/(.+)"] = function(call,data,cType,name) -- modify value
        data = json.decode(data)
        if rawget(resources.globalVariables,name) == nil then return nil,404 end
        resources.globalVariables[name]:modify(data)
        return resources.globalVariables[name],200
      end,
      ["/customEvents/(.+)"] = function(call,data,cType,name) -- modify value
        data = json.decode(data)
        if rawget(resources.customEvents,name)==nil then return nil,404 end
        resources.customEvents[name]:modify(data)
        return resources.customEvents[name],200
      end,
      ["/devices/(%d+)"] = function(call,data,cType,id) -- modify value
        data = json.decode(data)
        id = tonumber(id)
        if rawget(resources.devices,id) == nil then return nil,404 end
        resources.devices[id]:modify(data)
        return resources.devices[id],200
      end,
      ["/notificationCenter/(%d+)"] = function(call,data,cType,id)
        data = json.decode(data)
        id = tonumber(id)
        if not notifications[id] then return nil,404 end
        data.id = id
        notifications[id]=data
        Log(LOG.LOG,"InfoCenter(%s):%s, %s - %s",data.priority,data.id,data.data.title,data.data.text)
        return data,200
      end,
    },
    ["DELETE"] = {
      ["/globalVariables/(.+)"] = function(call,data,cType,name) 
        return delete(resources.globalVariables,name)
      end,
      ["/customEvents/(.+)"] = function(call,data,cType,name) 
        return delete(resources.customEvents,name)
      end,
      ["/devices/(%d+)"] = function(call,data,cType,id) 
        return delete(resources.devices,tonumber(id))
      end,
      ["/rooms/(%d+)"] = function(call,data,cType,id) 
        return delete(resources.rooms,tonumber(id))
      end,
      ["/sections/(%d+)"] = function(call,data,cType,id) 
        return delete(resources.sections,tonumber(id))
      end,
      ["/scenes/(%d+)"] = function(call,data,cType,id) 
        return delete(resources.scenes,tonumber(id))
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

  local function userDev(d0)
    local u = {}
    for k,_ in pairs(d0.data.actions) do u[k]=d0[k] end
    function u:breach(secRestore)
      u.turnOn(d0)
      setTimeout(function() u.turnOff(d0) end,1000*secRestore)
    end
    function u:delay(s)
      local res = {}
      for k,v in pairs(u) do 
        res[k]=function(...) 
          local a={...} 
          setTimeout(function() v(d0,select(2,table.unpack(a))) end,s*1000) 
        end
      end 
      return res
    end
    return u
  end

  hc3_emulator.create = {}
  function hc3_emulator.create.global(name,value) 
    local g = Global(name,{name=name,value=value},true)
    function g:set(value) self:modify({value=value}) end
    g.data.actions = {set=1 }
    return userDev(g) 
  end
  function hc3_emulator.create.motionSensor(id,name) return userDev(createBestDevice("com.fibaro.motionSensor",{id=id,name=name},true)) end
  function hc3_emulator.create.tempSensor(id,name) 
    return userDev(createBestDevice(id,"com.fibaro.temperatureSensor",{id=id,name=name},true)) 
  end
  function hc3_emulator.create.doorSensor(id,name) return userDev(createBestDevice(id,"com.fibaro.doorSensor",{id=id,name=name},true)) end
  function hc3_emulator.create.luxSensor(id,name) return userDev(createBestDevice(id,"com.fibaro.lightSensor",{id=id,name=name},true)) end
  function hc3_emulator.create.dimmer(id,name) return userDev(createBestDevice(id,"com.fibaro.multilevelSwitch",{id=id,name=name},true)) end
  function hc3_emulator.create.light(id,name) return userDev(createBestDevice(id,"com.fibaro.binarySwitch",{id=id,name=name},true)) end

  function offline.start()
    if next(resources.settings.location)==nil then
      resources.settings.location={latitude=52.520008,longitude=13.404954}-- Berlin
    end
    local function setupSuntimes()
      local sunrise,sunset = Util.sunCalc()
      rawset(resources.devices,1,{properties={sunriseHour=sunrise,sunsetHour=sunset}})
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

  refreshStates = Trigger.refreshStates
  offline.api = offlineApi

  local persistence = nil
  local cr = not hc3_emulator.credentials and loadfile(hc3_emulator.credentialsFile); cr = cr and cr()

  function offline.downloadFibaroAPI()
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

  function offline.downloadDB(fname)
    fname = fname or type(hc3_emulator.db)=='string' and hc3_emulator.db or "HC3sdk.db"
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
    local offline = hc3_emulator.offline
    hc3_emulator.offline = false
    local rawCall = hc3_emulator.rawCall
    local resources = resourceStructure(false)

    Log(LOG.SYS,"Reading devices")
    local devices = rawCall('GET',"/devices")
    for _,d in pairs(devices or {}) do
      rawset(resources.devices,d.id,d)
    end
    Log(LOG.SYS,"Reading global variables")
    local globals = rawCall('GET',"/globalVariables")
    for _,global in pairs(globals or {}) do
      rawset(resources.globalVariables,global.name,global)
    end
    Log(LOG.SYS,"Reading panels")
    for key,_ in pairs(resources.panels) do
      local res = rawCall("GET","/panels/"..key) or {}
      res = mapIDS(res)
      resources.panels[key] = res
    end
    Log(LOG.SYS,"Reading settings")
    for key,_ in pairs(resources.settings) do
      local res = rawCall("GET","/settings/"..key) or {}
      res = mapIDS(res)
      resources.settings[key] = res
    end
    Log(LOG.SYS,"Reading alarms")
    for key,_ in pairs(resources.alarms.v1) do
      local res = rawCall("GET","/alarms/v1/"..key) or {}
      res = mapIDS(res)
      resources.alarms.v1[key] = res
    end
    local keys = {}
    for k,_ in pairs(resources) do keys[k]=true end
    keys.devices = nil
    keys.globalVariables = nil
    keys.panels = nil
    keys.settings = nil
    keys.alarms = nil
    for key,_ in pairs(keys) do
      Log(LOG.SYS,"Reading %s",key)
      local resources = rawCall('GET',"/"..key) or {}
      resources[key]=mapIDS(resources)
    end
    Log(LOG.LOG,"Writing HC3 resources to file (%s)",fname)
    persistence.store(fname,resources)
    hc3_emulator.offline = offline
  end

  function offline.loadDB(fname)
    fname = fname or type(hc3_emulator.db)=='string' and hc3_emulator.db or "HC3sdk.db"
    hc3_emulator.loadingDB = true
    local stat,res = pcall(function()
        local r = persistence.load(fname)
        Log(LOG.SYS,"Loading devices")
        for id,d in pairs(r.devices or {}) do
          rawset(resources.devices,id,createBestDevice(d.type,d))
        end
        Log(LOG.SYS,"Loading global variables")
        for name,g in pairs(r.globalVariables or {}) do
          rawset(resources.globalVariables,name,Global(name,g))
        end
        local keys = {}
        for k,_ in pairs(resources) do keys[k]=true end
        keys.devices = nil
        keys.globalVariables = nil
        for key,_ in pairs(keys) do
          Log(LOG.SYS,"Loading %s",key)
          for id,rsrc in pairs(r[key]) do
            resources[key][id]=rsrc
          end
        end
        Log(LOG.SYS,"Loaded database '%s'",fname)
      end)
    hc3_emulator.loadingDB = false
    if not stat then Log(LOG.ERROR,"Failed to load database '%s' - %s",fname,res) end
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

  commandLines['downloaddb']=offline.downloadDB
  commandLines['downloadsdk']=offline.downloadFibaroAPI
  offline.persistence = persistence

  return offline
end -- Offline

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

commandLines['help'] = function()
  for c,f in pairs(commandLines) do
    Log(LOG.LOG,"Command: -%s",c)
  end
end

if arg[1] then
  local cmd,res = arg[1],false
  if cmd:sub(1,1)=='-' then
    cmd = cmd:sub(2)
    if commandLines[cmd] then --- When fibaroapiHC3.lua is used as a command from ZBS
      res = commandLines[cmd](select(2,table.unpack(arg)))
      if not res then os.exit() end
    end
  end
  if not res then 
    Log(LOG.ERROR,"Unrecognized command line argument: %s",table.concat(arg," "))
    os.exit()
  end
end
local function DEFAULT(v,d) if v~=nil then return v else return d end end
hc3_emulator.offline = DEFAULT(hc3_emulator.offline,false)
hc3_emulator.defaultDevice     = DEFAULT(hc3_emulator.defaultDevice,"com.fibaro.multilevelSwitch")
hc3_emulator.autocreateDevices = DEFAULT(hc3_emulator.autocreateDevices,true)
hc3_emulator.autocreateGlobals = DEFAULT(hc3_emulator.autocreateGlobals,true)

hc3_emulator.updateViewLayout  = QA.updateViewLayout
hc3_emulator.getUI             = QA.getQAUI
hc3_emulator.createQuickApp    = QA.createQuickApp
hc3_emulator.createProxy       = QA.createProxy
hc3_emulator.getIPaddress      = Util.getIPaddress
hc3_emulator.cache             = Trigger.cache 
hc3_emulator.copyFromHC3       = Offline.copyFromHC3

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

  for k,v in pairs(hc3_emulator.quickVars or {}) do
    assertf(type(k)=='string',"Corrupt quickVars table, key=%s, value=%s",k,json.encode(v))
  end

  if not hc3_emulator.offline and not hc3_emulator.credentials then
    error("Missing HC3 credentials -- hc3_emulator.credentials{ip=<IP>,user=<string>,pwd=<string>}")
  end 
  if not hc3_emulator.offline then
    typeHierarchy = api.get('/devices/hierarchy')
    hc3_emulator.HC3version = api.get("/settings/info").currentVersion.version
  end
  hc3_emulator.speeding = hc3_emulator.speed==true and 48 or tonumber(hc3_emulator.speed)
  if hc3_emulator.traceFibaro then Util.traceFibaro() end

  Log(LOG.SYS,"HC3 SDK v%s",hc3_emulator.version)
  if hc3_emulator.deploy==true or _G["DEPLOY"] then Files.deploy(file) os.exit() end

  if hc3_emulator.speeding then Log(LOG.SYS,"Speeding %s hours",hc3_emulator.speeding) end
  if not (hc3_emulator.startWeb==false) then Web.start(Util.getIPaddress()) end

  if type(hc3_emulator.startTime) == 'string' then 
    Timer.setEmulatorTime(Util.parseDate(hc3_emulator.startTime)) 
  end

  if hc3_emulator.offline then
    Offline.createBaseMap()
    if hc3_emulator.db then Offline.loadDB() end
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
      hc3_emulator.inited = true
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

if not hc3_emulator.sourceFile then 
  local file = debug.getinfo(3, 'S')                                  -- Find out what file we are running
  if file and file.source then
    file = file.source
    if not file:sub(1,1)=='@' then error("Can't locate file:"..file) end  -- Is it a file?
    hc3_emulator.sourceFile = file:sub(2)
  end
end
--print("SOURCE:"..hc3_emulator.sourceFile)
if hc3_emulator.sourceFile then  startUp(hc3_emulator.sourceFile) end
Log(LOG.SYS,"fibaroapiHC3 version:%s",FIBAROAPIHC3_VERSION)
os.exit()