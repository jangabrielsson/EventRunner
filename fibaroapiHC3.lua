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

Contributions:
-  @petergebruers, forum.fibaro.com

Sources:
json -- Copyright (c) 2019 rxi
--]]

local FIBAROAPIHC3_VERSION = "0.62"

--hc3_emulator.credentials = { ip = <IP>, user = <username>, pwd = <password>}

--[[
  Best way is to conditionally include this file at the top of your lua file
  if dofile then
     dofile("fibaroapiHC3.lua")
     local cr = loadfile("credentials.lua"); if cr then cr() end
     QuickApp._quickVars["Hue_User"]=_HueUserName
     QuickApp._quickVars["Hue_IP"]=_HueIP
  end
  We load another file, credentials.lua, where we define lua globals like _HC3_IP, _HC3_USER etc.
  This way the credentials are not visible in your code and you will not accidently upload them :-)
  You can also predefine quickvars that are accessible with self:getVariable() when your code starts up
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

QuickApp:onInit() -- called at startup if defined
QuickApp - self:setVariable(name,value) 
QuickApp - self:getVariable(name)
QuickApp - self:debug(...)
QuickApp - self:updateView(elm,type,value)
QuickApp - self:updateProperty()

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
              quickvars=<table>,      -- default {}
              } 
hc3_emulator.createQuickApp{          -- creates and deploys QuickApp on HC3
              name=<string>,            
              type=<string>,
              code=<string>,
              UI=<table>,
              quickvars=<table>,
              dryrun=<boolean>
              } 
hc3_emulator.createProxy(<name>,<type>,<UI>,<quickVars>)       -- create QuickApp proxy on HC3 (usually called with 
hc3_emulator.post(ev,t)                                        -- post event/sourceTrigger 
--]]

local https = require ("ssl.https") 
local http = require("socket.http")
local socket = require("socket")
local ltn12 = require("ltn12")

local _debugFlags = {fcall=true, fget=true, post=true} 

local Util,Timer,QA,Scene,Web,Trigger,Offline     -- local modules
fibaro,json,plugin,QuickApp = {},{},nil,nil       -- global exports

hc3_emulator = { 
  version = FIBAROAPIHC3_VERSION,
  conditions=false, actions = false, 
  offline = false,
  emulated = true, 
  debug = _debugFlags,
  runSceneAtStart = false,
  webPort = 6872,
--createProxy()
--createQuickApp{}
--start{}
}

local _HC3_IP,_HC3_USER,_HC3_PWD   -- taken fron hc3_emulator.credentials.*
local ostime = os.time             -- save orginal functions...
local osclock = os.clock
local osdate = os.date
local _timeAdjust = 0              -- Used for speeding the clock...
local LOG,Log,Debug,assert,assertf
local module = {}
local HC3_handleEvent = nil        -- Event hook...
local format = string.format

-------------- Fibaro API functions ------------------
function module.FibaroAPI()
  local EventCache,safeDecode = hc3_emulator.EventCache,Util.safeDecode

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
  function assertf(value,errmsg,...) if not value then error(format(errmsg,...),3) end end
  function __assert_type(value,typeOfValue ) if type(value) ~= typeOfValue then error("Assertion failed: Expected"..typeOfValue,3) end end
  function __fibaro_get_device(deviceID) __assert_type(deviceID,"number") return api.get("/devices/"..deviceID) end
  function __fibaro_get_room (roomID) __assert_type(roomID,"number") return api.get("/rooms/"..roomID) end
  function __fibaro_get_scene(sceneID) __assert_type(sceneID,"number") return api.get("/scenes/"..sceneID) end
  function __fibaro_get_global_variable(varName) __assert_type(varName ,"string") 
    local c = EventCache.polling and EventCache.globals[varName] or api.get("/globalVariables/"..varName) 
    EventCache.globals[varName] = c
    return c
  end
  function __fibaro_get_device_property(deviceId ,propertyName)
    local key = propertyName..deviceId
    local c = EventCache.polling and EventCache.devices[key] or api.get("/devices/"..deviceId.."/properties/"..propertyName) 
    EventCache.devices[key] = c
    return c
  end

--[DEBUG] 14.02.2020 17:46:16:
  local function fibaro_debug(t,type,str) assert(str,"Missing tag for debug") print(format("[%s] %s: %s",t,os.date("%d.%m.%Y %X"),str)) end
  function fibaro.debug(type,str) fibaro_debug("DEBUG",type,str) end
  function fibaro.warning(type,str) fibaro_debug("WARNING",type,str) end
  function fibaro.trace(type,str) fibaro_debug("TRACE",type,str) end
  function fibaro.error(type,str) fibaro_debug("ERROR",type,str) end

  function fibaro.getName(deviceID) 
    __assert_type(deviceID,'number') 
    local dev = __fibaro_get_device(deviceID) 
    return dev and dev.name
  end

  sourceTrigger = nil -- global containing last trigger for scene

  function fibaro.get(deviceID,propertyName) 
    local property = __fibaro_get_device_property(deviceID ,propertyName)
    return property and property.value, property.modified
  end

  function fibaro.getValue(deviceID, propertyName) return (fibaro.get(deviceID , propertyName)) end

  function fibaro.wakeUpDeadDevice(deviceID ) 
    __assert_type(deviceID,'number') 
    fibaro.call(1,'wakeUpDeadDevice',deviceID) 
  end

  function fibaro.call(deviceID, actionName, ...) 
    if type(deviceID)=='table' then 
      for _,d in ipairs(deviceID) do fibaro.call(d, actionName, ...) end
    else
      deviceID =  tonumber(deviceID) 
      __assert_type(actionName ,"string") 
      local a = {args={},delay=0} 
      for i,v in ipairs({...})do 
        a.args[i]=v
      end 
      api.post("/devices/"..deviceID.."/action/"..actionName,a) 
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

  function fibaro.emitCustomEvent(name) return api.post("/customEvents/"..name,nil,{["X-Fibaro-Version"] = 2}) end

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
    __assert_type (deviceID,'number') 
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
    if type(filter) ~= 'table' or (type(filter) == 'table' and next( filter ) == nil) then 
      return fibaro.getIds(fibaro.getAllDeviceIds()) 
    end
    local args = '/?' 
    for c,d in pairs(filter) do 
      if c == 'properties' and d ~= nil and type(d) == 'table' then 
        for a,b in pairs (d) do 
          if b == "nil" then 
            args = args..'property='..tostring(a)..'&' 
          else 
            args = args..'property=['..tostring(a)..','..tostring(b)..']&' 
          end 
        end 
      elseif c == 'interfaces' and d ~= nil and type(d) == 'table' then 
        for _,b in pairs(d) do 
          args = args..'interface='..tostring(b)..'&'
        end 
      else 
        args = args..tostring(c).."="..tostring(d)..'&' 
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
    api.post("/profiles/"..action.."/"..profile_id)
  end

  function fibaro.callGroupAction(action,args)
    api.post("/devices/groupAction/"..action,args)
  end

  function fibaro.alert(alert_type, user_ids, notification_content) 
    __assert_type(user_ids,'table') 
    for _,u in ipairs(alert_type) do fibaro.call(u,alert_type,notification_content) end
  end

-- User PIN?
  function fibaro.alarm(partition_id, action)
    if action then api.post("/alarms/v1/partitions/"..partition_id.."/actions/"..action)
    else api.post("/alarms/v1/partitions/actions/"..action) end
  end

  function fibaro.__houseAlarm() end -- ToDo:

  function fibaro._sleep(ms) 
    local t = ostime()+ms;  -- Use real clock
    while ostime() <= t do socket.sleep(0.01) end   -- save batteries...
  end
  function fibaro.sleep(ms)
    if hc3_emulator.speeding then 
      _timeAdjust=_timeAdjust+ms/1000 return
    else
      local t = os.time()+ms/1000; 
      while os.time() < t do 
        socket.sleep(0.01)       -- without waking up QA/scene timers
      end                        -- ToDo: we probably need 2 timer queues...
    end
  end


  local rawCall
  api={} -- Emulation of api.get/put/post/delete
  function api.get(call) return rawCall("GET",call) end
  function api.put(call, data) return rawCall("PUT",call,json.encode(data),"application/json") end
  function api.post(call, data, hs) return rawCall("POST",call,data and json.encode(data),"application/json",hs) end
  function api.delete(call, data) return rawCall("DELETE",call,data and json.encode(data),"application/json") end

  ------------  HTTP support ---------------------

  net = { delmin=10, delmax=1000 } -- An emulation of Fibaro's net.HTTPClient and net.TCPSocket()

  function net.HTTPClient(moptions)     -- It is synchronous, but synchronous is a speciell case of asynchronous.. :-)
    local self = {}                    -- Not sure I got all the options right..
    function self:request(url,options)
      local resp = {}
      options = options or {}
      for k,v in pairs(moptions or {}) do options[k]=v end
      local req = options.options or {}
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
      local delay = math.random(net.delmin,net.delmax)
      if response == 1 then 
        if options.success then -- simulate asynchronous callback
          Timer.setTimeout(function() options.success({status=status, headers=headers, data=table.concat(resp)}) end,delay) 
        end
      else
        if options.error then 
          Timer.setTimeout(function() options.error(status) end,delay)
        end
      end
    end
    return self
  end

  function net.TCPSocket(opts) error("TCPSocket - Not implemented yet")
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

  function rawCall(method,call,data,cType,hs)
    if not _HC3_IP then -- We delay it to here...
      local c = hc3_emulator.credentials
      _HC3_IP, _HC3_USER, _HC3_PWD = c.ip, c.user, c.pwd
    end
    if hc3_emulator.offline then return Offline.api(method,call,data,cType,hs) end
    local resp = {}
    local req={ method=method, timeout=5000,
      url = "http://".._HC3_IP.."/api"..call,
      sink = ltn12.sink.table(resp),
      user=_HC3_USER,
      password=_HC3_PWD,
      headers={}
    }
    req.headers["Accept"] = 'application/json'
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
      error(format("Error connnecting to HC3: '%s' - URL: '%s'.",c,req.url))
    end
    if c>=200 and c<300 then
      return resp[1] and safeDecode(table.concat(resp)) or nil,c
    end
    return nil,c, h
    --error(format("HC3 returned error '%d %s' - URL: '%s'.",c,resp[1] or "",req.url))
  end

  HomeCenter =  {   -- ToDo
    PopupService =  { 
      publish =  function ( request ) 
        local response = api.post( '/popups' , request ) 
        return response
      end 
    } , 
    SystemService =  { 
      reboot =  function ( ) 
        local client = net.HTTPClient() 
        client:request ("http://localhost/reboot.php") 
      end , 
      shutdown =  function ( ) 
        local client = net.HTTPClient() 
        client:request ( "http://localhost/shutdown.php" ) 
      end 
    } 
  }

  urlencode = Util.urlencode
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
      if t.txt then Log(LOG.SYS,"Timer:"..t.txt) end
      t.fun()
    end
  end

  local function makeTimer(time,fun,txt) return {['%%TIMER%%']=true, time=time,fun=fun, text=txt,t0=_timeAdjust+time} end
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

  function self.setTimeout(fun,ms,text)
    assert(type(fun)=='function' and type(ms)=='number',"Bad argument to setTimeout")
    if ms >= 0 then
      local t = makeTimer(ms/1000+milliTime(),fun,text)
      insertTimer(t)
      return t
    end
  end

  function self.coprocess(ms,fun,name,...)
    local args = {...}
    local p = coroutine.create(function() fun(table.unpack(args)) end)
    local function process()
      local res,err = coroutine.resume(p)
      local stat = coroutine.status(p) -- run every ms
      if stat~="dead" then self.setTimeout(process,ms) end  -- ToDo: check exit
    end
    process()
  end

  function self.setInterval(fun,ms)
    local ref={}
    local function loop()
      if ref[1] then
        fun()
        ref[1]=setTimeout(loop,ms)
      end
    end
    ref[1] = setTimeout(loop,ms)
    return ref
  end

  function self.clearInterval(ref) -- Urk, fix this
    assert(type(ref)=='table',"Bad timer to clearInterval")
    local r = ref[1]
    assert(r == nil or isTimer(r),"Bad timer to clearInterval:"..tostring(r))
    if r then clearTimeout(r) ref[1]=nil end 
  end

  function self.speedTime(speedTime)
    local maxTime = os.time()+speedTime*60*60
    local fastTimer = nil

    local function addTimer(t) --{f = fun, t=time, nxt = next}
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

    function setTimeout(f,t,text) -- globally redefine global setTimeout
      --Log(LOG.LOG,"S %s:%d",text or "",t/1000)
      if t >= 0 then return addTimer(makeTimer(t/1000,f,text,_timeAdjust+t/1000)) end
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

    self.coprocess(0,function()
        while true do
          if os.time() >= maxTime then Log(LOG.SYS,"Max time - exit")  os.exit() end
          if fastTimer then
            local t0 = fastTimer.t0
            Timer.setTimeout(fastTimer.fun,0,fastTimer.text) -- schedule next time in lines
            --Log(LOG.LOG,"E %s",fastTimer.text or "")
            _timeAdjust=fastTimer.t0 -- adjust time
            fastTimer = fastTimer.next
            while fastTimer and fastTimer.t0==t0 do
              Timer.setTimeout(fastTimer.fun,0,fastTimer.text)
              --Log(LOG.LOG,"E %s",fastTimer.text or "")
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

  setTimeout = self.setTimeout
  clearTimeout = self.clearTimeout
  setInterval = self.setInterval
  clearInterval = self.clearInterval

  return self
end

--------------- QuickApp functions and support -------
function module.QuickApp()
  local self = {}
--core.EventTarget = class EventTarget (EventTarget)
  plugin = {}
  plugin.mainDeviceId = nil
  plugin.deleteDevice = nil
  plugin.restart = nil
  plugin.getProperty = nil
  plugin.getChildDevices = nil
  plugin.createChildDevice = nil
  plugin.getDevice = nil

  QuickApp = {
    debug = function(self,...) fibaro.debug("",table.concat({...})) end,
    _props = {},
    _quickVars = {},
    getVariable = function(self,name) 
      if plugin.isProxy then
        local d = api.get("/devices/"..plugin.mainDeviceId) or {properties={}}
        for _,v in ipairs(d.properties.quickAppVariables or {}) do
          if v.name==name then return v.value end
        end
        return QuickApp._quickVars[name] -- default to local var
      else return QuickApp._quickVars[name] end
    end,
    setVariable = function(self,name,value) 
      if plugin.isProxy then
        fibaro.call(plugin.mainDeviceId,"setVariable",name,json.encode(value))
      end
      QuickApp._quickVars[name] = tostring(value) -- set local too
    end,
    updateView = function(self,elm,t,value) 
      if plugin.isProxy then
        fibaro.call(plugin.mainDeviceId,"updateView",elm,t,value)
      end
    end,
    updateProperty = function(self,prop,value) 
      if plugin.isProxy then
        fibaro.call(plugin.mainDeviceId,"updateProperty",prop,value)
      else 
        QuickApp._props[prop]=tostring(value)
      end
    end,
    addInterfaces = function(interfaces)
      if plugin.isProxy then
        api.post("/devices/addInterface",{deviceID={plugin.mainDeviceId},interfaces=interfaces})
      end
    end
  }

  local function traverse(o,f)
    if type(o) == 'table' and o[1] then
      for _,e in ipairs(o) do traverse(e,f) end
    else f(o) end
  end
  local function map(f,l) for _,e in ipairs(l) do f(e) end end

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

  local function updateViewLayout(id,UI,forceUpdate)
    transformUI(UI)
    local cb = api.get("/devices/"..id).properties.uiCallbacks or {}
    local viewLayout = mkViewLayout(UI)
    local newcb = {}
    newcb = {}
    --- "callback": "self:button1Clicked()",
    traverse(UI,
      function(e)
        if e.name then newcb[#newcb+1]={callback="self:"..e.name.."Clicked(value)",eventType="pressed",name=e.name} end
      end)
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
    local cb = {}
    --- "callback": "self:button1Clicked()",
    traverse(UI,
      function(e)
        if e.name then cb[#cb+1]={callback="self:"..e.name.."Clicked(value)",eventType="pressed",name=e.name} end
      end)
    ip.uiCallbacks = cb 
    local varList = {}
    for n,v in pairs(vars) do varList[#varList+1]={name=n,value=v} end
    ip.quickAppVariables = varList
    ip.typeTemplateInitialized=true
    return ip
  end

  -- name of device - string
  -- type of device - string, default "com.fibaro.binarySwitch"
  -- code - string, Lua code
  -- UI -- table with UI elements
  --      {{{button='button1", text="L"},{button='button2'}}, -- 2 buttons  1 row
  --      {{slider='slider1", text="L", min=100,max=99}},     -- 1 slider 1 row
  --      {{label="label1",text="L"}}}                        -- 1 label 1 row
  -- quickvars - quickAppVariables, {<var1>=<value1>,<var2>=<value2>,...}
  -- dryRun - if true only returns the quickapp without deploying

  local function createQuickApp(args)
    local d = {} -- Our device
    d.name = args.name or "QuickApp"
    d.type = args.type or "com.fibaro.binarySensor"
    local body = args.code or ""
    local UI = args.UI or {}
    local variables = args.quickvars or {}
    local dryRun = args.dryRun or false
    d.apiVersion = "1.0"
    d.initialProperties = makeInitialProperties(body,UI,variables,args.height)
    if dryRun then return d end
    Log(LOG.SYS,"Creating device...")--..json.encode(d)) 
    if not d.initialProperties.uiCallbacks[1] then
      d.initialProperties.uiCallbacks = nil
    end
    local d1,res = api.post("/quickApp/",d)
    if res ~= 201 then 
      Log(LOG.ERROR,"D:%s,RES:%s",json.encode(d1),json.encode(res))
      return nil
    else 
      Log(LOG.SYS,"Device %s created",d1.id or "")
      return d1.id
    end
  end

-- Create a Proxy device - will be named "Proxy "..name, returns deviceID if successful
  local function createProxy(name,tp,UI,vars,proxyWithEvents)
    local ID,device = nil,nil
    if not tonumber(name) then
      name = "Proxy "..name
      Log(LOG.SYS,"Proxy: Looking for QuickApp on HC3...")
      local devices = api.get("/devices")
      for _,d in pairs(devices) do 
        if d.name==name then 
          ID=d.id; 
          device = d
          Log(LOG.SYS,"Proxy: Found ID:"..ID)
          break 
        end 
      end
    else
      device = api.get("/devices/"..name)
      ID = device.id
      name = device.name
    end
    tp = tp or "com.fibaro.binarySensor"
    vars = vars or {}
    UI = UI or {}
    local EXCL = {onInit=true,getVariable=true,setVariable=true,updateView=true,debug=true,updateProperty=true}
    local funs1 = {}
    traverse(UI,
      function(e)
        if e.button then funs1[e.button.."Clicked"]=true 
        elseif e.slider then funs1[e.slider.."Clicked"]=true end
      end)
    for n,f in pairs(QuickApp) do
      if type(f)=='function' and not EXCL[n] then funs1[n]=true end
    end
    local funs = {}; for n,_ in pairs(funs1) do funs[#funs+1]=n end
    table.sort(funs)
    local code
    if proxyWithEvents then
      code = {
        "function EVENT(ev)",
        " COUNT = (COUNT or 0)+1",
        ' local name="PROXY"..plugin.mainDeviceId.."_"..COUNT',
        ' api.delete("/customEvents/"..name)',
        ' api.post("/customEvents",{name=name,userDescription=json.encode(ev)})',
        " fibaro.emitCustomEvent(name)",
        "end",
        "function QuickApp:ACTION(name) self[name] = function(self,...) EVENT({name=name,args={...}}) end end"
      }
    else
      code = {}
      code[1] = [[
  local function urlencode (str) 
  return str and string.gsub(str ,"([^% w])",function(c) return string.format("%%% 02X",string.byte(c))  end) 
end
local function CALLIDE(actionName,...)
    local args = "" 
    for i,v in ipairs({...}) do 
      args = args..'&arg'..tostring(i)..'='..urlencode(json.encode(v))  
    end 
    url = "http://"..IP.."/api"
    net.HTTPClient():request(url.."/callAction?deviceID="..plugin.mainDeviceId.."&name="..actionName..args,{})
end
function QuickApp:ACTION(name) self[name] = function(self,...) CALLIDE(name,...) end end
]]
    end

    for _,f in ipairs(funs) do code[#code+1]=format("QuickApp:ACTION('%s')",f) end
    code[#code+1]= "function QuickApp:onInit()"
    code[#code+1]= " self:debug('"..name.."',' deviceId:',plugin.mainDeviceId)"
    code[#code+1]= " IP = self:getVariable('IP')"
    code[#code+1]= "end"
    code[#code+1]= [[
INSTALLED_MODULES={}
-->MODULES>-----------------------------
INSTALLED_MODULES['EventScript4.lua']={isInstalled=true,installedVersion=0.1}
INSTALLED_MODULES['EventScript.lua']={isInstalled=true,installedVersion=0.001}

--....
--<MODULES<-----------------------------
  ]]

    code = table.concat(code,"\n")

    if ID then -- ToDo: Re-use ID if it exists.
      local d = device
      if d.properties.mainFunction == code then 
        Log(LOG.SYS,"Proxy: Not changed, reusing QuickApp proxy")
        return d.id 
      end
      Log(LOG.SYS,"Proxy: Changed, re-creating")
      api.delete("/devices/"..d.id)
    end
    Log(LOG.SYS,"Proxy: Creating new proxy")
    local vars2 = {["IP"]=Util.getIPaddress()..":"..hc3_emulator.webPort}
    return createQuickApp{name=name,type=tp,code=code,UI=UI,quickvars=vars2}
  end

  local function runQuickApp(args)
    plugin.mainDeviceId = args.id or 999
    plugin.type = args.type or "com.fibaro.binarySwitch"
    plugin.isProxy = args.proxy and not hc3_emulator.offline
    local name = args.name or "My App"
    local UI = args.UI or {}
    local quickvars = args.quickvars or {}

    if plugin.isProxy then
      plugin.mainDeviceId = createProxy(name,plugin.type,UI,quickvars)
    end

    if args.poll then Trigger.startPolling(tonumber(args.poll ) or 2000) end

    if plugin.isProxy then
      local es,mm = (api.get("/customEvents") or {}),"PROXY"..plugin.mainDeviceId
      for _,e in ipairs(es) do  -- clear stale events left behind
        if e.name:match(mm) then 
          Log(LOG.SYS,"Removing stale event "..e.name); fibaro._sleep(1)
          api.delete("/customEvents/"..e.name) 
        end
      end

      function HC3_handleEvent(e) -- If we have a HC3 proxy, we listen for UI events (PROXY)
        if e.type=='customevent' then -- (Default is to get them from callAction...)
          local id,elm = e.name:match("PROXY(%d+)")
          if id and id~="" and ID==tonumber(id) then
            local ed = api.get("/customEvents/"..e.name)
            local fun = json.decode(ed.userDescription)
            if QuickApp[fun.name] then 
              Timer.setTimeout(function() QuickApp[fun.name](QuickApp,table.unpack(fun.args)) end,1)
            else
              Log(LOG.WARNING,"Unhandled PROXY CALL:"..json.encode(ed.userDescription))
            end
            api.delete("/customEvents/"..e.name)
            return true
          end
        end
      end
    end

    if QuickApp.onInit then Timer.setTimeout(function() QuickApp:onInit() end,1) end -- start :onInit if we have one...
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
          return comp(cv,value)
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

  local function runScene(args)
    local condition,triggers,dates = compileCondition(hc3_emulator.conditions)
    printf("Scene started at %s",os.date("%c"))
    if hc3_emulator.runSceneAtStart or next(hc3_emulator.conditions)==nil then
      Timer.setTimeout(function() HC3_handleEvent({type = "manual", property = "execute"}) end,0)
    end
    Trigger.startPolling(tonumber(args.poll) or 2000) -- Start polling HC3 for triggers

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
  local EventCache = hc3_emulator.EventCache
  local tickEvent = "ERTICK"

  local function post(event) if HC3_handleEvent then HC3_handleEvent(event) end end

  local EventTypes = { -- There are more, but these are what I seen so far...
    AlarmPartitionArmedEvent = function(self,d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
    AlarmPartitionBreachedEvent = function(self,d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
    HomeArmStateChangedEvent = function(self,d) post({type='alarm', property='homeArmed', value=d.newValue}) end,
    HomeBreachedEvent = function(self,d) post({type='alarm', property='homeBreached', value=d.breached}) end,
    WeatherChangedEvent = function(self,d) post({type='weather',property=d.change, value=d.newValue, old=d.oldValue}) end,
    GlobalVariableChangedEvent = function(self,d)
      EventCache.globals[d.variableName]={name=d.variableName, value = d.newValue, modified=os.time()}
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
        EventCache.devices[d.property..d.id]={value=d.newValue, modified=os.time()}     
        post({type='device', id=d.id, property=d.property, value=d.newValue, old=d.oldValue})
      end
    end,
    CentralSceneEvent = function(self,d) 
      EventCache.centralSceneEvents[d.deviceId]=d 
      post({type='device', property='centralSceneEvent', id=d.deviceId, value = {keyId=d.keyId, keyAttribute=d.keyAttribute}}) 
    end,
    AccessControlEvent = function(self,d) 
      EventCache.caccessControlEvent[d.id]=d
      post({type='device', property='accessControlEvent', id = d.deviceID, value=d}) 
    end,
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
  }

  local function checkEvents(events)
    for _,e in ipairs(events) do
      local eh = EventTypes[e.type]
      if eh then eh(_,e.data)
      elseif eh==nil then Log(LOG.WARNING,"Unhandled event:%s -- please report",json.encode(e)) end
    end
  end

  local function pollEvents(interval)
    local INTERVAL = interval or 1000 -- every second, could do more often...
    local lastRefresh = 0
    api.post("/globalVariables",{name=tickEvent,value="Tock!"})
    EventCache.polling = true -- Our loop will populate cache with values - no need to fetch from HC3
    local function pollRefresh()
      --Log(LOG.SYS,"*")
      local states = api.get("/refreshStates?last=" .. lastRefresh)
      if states then
        lastRefresh=states.last
        if states.events and #states.events>0 then checkEvents(states.events) end
      end
      Timer.setTimeout(pollRefresh,INTERVAL,"MAIN")
      fibaro.setGlobalVariable(tickEvent,tostring(os.clock())) -- emit hangs
--    fibaro.emitCustomEvent(tickEvent)  -- hack because refreshState hang if no events...
    end
    Timer.setTimeout(pollRefresh,INTERVAL)
  end

  if not HC3_handleEvent then -- default handle event routine
    function HC3_handleEvent(e)
      if _debugFlags.trigger then Log(LOG.DEBUG,"Incoming trigger:"..json.encode(e)) end
    end
  end 

  function hc3_emulator.post(ev,t)
    assert(type(ev)=='table' and ev.type,"Bad event format:"..ev)
    t = t or 0
    setTimeout(function() HC3_handleEvent(ev) end,t)
  end

  self.eventTypes = EventTypes
  self.startPolling = pollEvents
  return self
end

-------------- Utilities -----------------------------
function module.Utilities()
  local self = {}
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

  LOG = { LOG="|LOG  |", WARNING="|WARN |", SYS="|SYS  |", DEBUG="|SDBG |", ERROR='|ERROR|', HEADER='HEADER'}
  function Debug(flag,...) if flag then Log(LOG.DEBUG,...) end end
  function Log(flag,...)
    local args={...}
    local stat,res = pcall(function() 
        local str = format(table.unpack(args))
        if flag == LOG.HEADER then print(logHeader(100,str))
        else print(format("%s %s: %s",flag,os.date("%d.%m.%Y %X"),str)) end
        return str
      end)
    if not stat then print(res) end
  end

  function self.printf(...) print(format(...)) end
  function self.split(s, sep)
    local fields = {}
    sep = sep or " "
    local pattern = format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    return fields
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
    patchFibaro("get")
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
      coprocess(10,clientHandler,"client",client,getHandler,postHandler,putHandler)
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
    coprocess(10,socketServer,"server",server,getHandler,postHandler,putHandler)
    Log(LOG.SYS,"Created %s at %s:%s",name,self.ipAddress,port)
  end

  local GUI_HANDLERS = {
    ["GET"] = {
      ["/api/callAction%?deviceID=(%d+)&name=(%w+)(.*)"] = function(client,ref,body,id,action,args)
        local res = {}
        args = split(args,"&")
        for _,a in ipairs(args) do
          local i,v = a:match("^arg(%d+)=(.*)")
          res[tonumber(i)]=json.decode(urldecode(v))
        end
        local stat,res2=pcall(function() QuickApp[action](QuickApp,table.unpack(res)) end)
        if not stat then Log(LOG.ERROR,"Bad eventCall:%s",res2) end
        client:send("HTTP/1.1 201 Created\nETag: \"c180de84f991g8\"\n\n")
        return true
      end,
    },
    ["POST"] = {
      ["/fibaroapiHC3/event"] = function(client,ref,body,id,action,args)
        --- ToDo
      end,
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

  return self
end

--------------- Offline support ----------------------
function module.Offline()
  -- We setup our own /refreshState handler and other REST API handlers and keep our own reosurce states
  local self,split,urldecode,QUEUESIZE = {},Util.split,Util.urldecode,200

  local resources = {
    devices = {},
    globalVariables = {},
    customEvents = {}
  }

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
        if e and e.last > last then res1[#res1+1]=e
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

  local refreshStates = createRefreshStateQueue(QUEUESIZE)

  local function rawCopy(t)
    local res = {}
    for k,_ in pairs(t) do res[k]=rawget(t,k) end
    return res
  end

  local OFFLINE_HANDLERS = {
    ["GET"] = {
      ["/callAction%?deviceID=(%d+)&name=(%w+)(.*)"] = function(call,data,cType,id,action,args)
        local res = {}
        args = split(args,"&")
        for _,a in ipairs(args) do
          local i,v = a:match("^arg(%d+)=(.*)")
          res[tonumber(i)]=urldecode(v)
        end
        local d = resources.devices[id]
        local stat,err = pcall(function() d.actions[action](table.unpack(res)) end)
        if not stat then error(format("Bad call:%s(%s) (%s)",action,json.encode(res):sub(2,-2),err),4) end
        return 200
      end,
      ["/devices/(%d+)$"] = function(call,data,cType,id) return resources.devices[id] end,
      ["/devices/?$"] = function(call,data,cType,name) return rawCopy(resources.devices) end,    
      ["/globalVariables/(.+)"] = function(call,data,cType,name) return resources.globalVariables[name] end,
      ["/globalVariables/?$"] = function(call,data,cType,name) return rawCopy(resources.globalVariables) end,
      ["/customEvents/(.+)"] = function(call,data,cType,name) return resources.customEvents[name] end,
      ["/customEvents/?$"] = function(call,data,cType,name) return rawCopy(resources.customEvents) end,
      ["/refreshStates%?last=(%d+)"] = function(call,data,cType,last)
        return refreshStates.getEvents(tonumber(last))
      end,
      ["/settings/location/?$"] = function(call,data,cType,id) return {longitude=13.404954,latitude=52.520008} end,
    },
    ["POST"] = {
      ["/globalVariables/?$"] = function(call,data,cType) 
        data = json.decode(data)
        data.modified = os.time()
        resources.globalVariables[data.name] = data 
      end,
      ["/devices/(%d+)/action/(.+)$"] = function(call,data,cType,deviceID,action) 
        data = json.decode(data)
        local d = resources.devices[deviceID]
        local stat,err = pcall(function() d.actions[action](table.unpack(data.args)) end)
        if not stat then error(format("Bad fibaro.call(%s,'%s',%s)",deviceID,action,json.encode(data.args):sub(2,-2),err),4) end
        return 200
      end,
    },
    ["PUT"] = {
      ["/globalVariables/(.+)"] = function(call,data,cType,name) 
        resources.globalVariables[name]._setValue(json.decode(data))
      end,
    },
    ["DELETE"] = {
      --- ToDo
    },
  }

  local function offlineApi(method,call,data,cType,hs)
    for p,h in pairs(OFFLINE_HANDLERS[method] or {}) do
      local match = {call:match(p)}
      if match and #match>0 then
        return h(call,data,cType,table.unpack(match))
      end
    end
    fibaro.warning("","API not supported yet: "..method..":"..call)
  end

  local typeHierarchy = { -- Need to keep this to see if we support the basetype...
    children = {
      {children = {}, type = "com.fibaro.zwaveDevice"}, 
      {children = {}, type = "com.fibaro.zwaveController"}, 
      {children = {
          {children = {}, type = "com.fibaro.yrWeather"}, 
          {children = {}, type = "com.fibaro.WeatherProvider"}
        }, 
        type = "com.fibaro.weather"
      }, 
      {children = {}, type = "com.fibaro.usbPort"}, 
      {children = {}, type = "com.fibaro.setPointForwarder"}, 
      {children = {
          {children = {
              {children = {}, type = "com.fibaro.windSensor"}, 
              {children = {}, type = "com.fibaro.temperatureSensor"}, 
              {children = {}, type = "com.fibaro.seismometer"}, 
              {children = {}, type = "com.fibaro.rainSensor"}, 
              {children = {}, type = "com.fibaro.powerSensor"}, 
              {children = {}, type = "com.fibaro.lightSensor"}, 
              {children = {}, type = "com.fibaro.humiditySensor"}
            }, 
            type = "com.fibaro.multilevelSensor"
          }, 
          {children = {
              {children = {
                  {children = {}, type = "com.fibaro.satelZone"}, 
                  {children = {
                      {children = {{children = {}, type = "com.fibaro.FGMS001v2"}}, 
                        type = "com.fibaro.FGMS001"}
                      },type = "com.fibaro.motionSensor" }, 
                  {children = {}, type = "com.fibaro.envisaLinkZone"}, 
                  {children = {}, type = "com.fibaro.dscZone"}, 
                  {children = {
                      {children = {}, type = "com.fibaro.windowSensor"}, 
                      {children = {}, type = "com.fibaro.rollerShutterSensor"}, 
                      {children = {}, type = "com.fibaro.gateSensor"}, 
                      {children = {}, type = "com.fibaro.doorSensor"}, 
                      {children = {}, type = "com.fibaro.FGDW002"}
                      },type = "com.fibaro.doorWindowSensor" }
                  }, type = "com.fibaro.securitySensor" }, 
              {children = {}, type = "com.fibaro.safetySensor"}, 
              {children = {}, type = "com.fibaro.rainDetector"}, 
              {children = {
                  {children = {}, type = "com.fibaro.heatDetector"}, 
                  {children = {
                      {children = { {children = {}, type = "com.fibaro.FGSS001"} }, 
                        type = "com.fibaro.smokeSensor"
                      }, 
                      {children = {
                          {children = {}, type = "com.fibaro.FGCD001"}
                        }, 
                        type = "com.fibaro.coDetector"
                      }
                    }, 
                    type = "com.fibaro.gasDetector"}, 
                  {children = {{children = {}, type = "com.fibaro.FGFS101"}}, 
                    type = "com.fibaro.floodSensor"
                  }, 
                  {children = {}, type = "com.fibaro.fireDetector"}
                }, 
                type = "com.fibaro.lifeDangerSensor"
              }
            }, 
            type = "com.fibaro.binarySensor"
          }, 
          {children = {}, type = "com.fibaro.accelerometer"}
        }, 
        type = "com.fibaro.sensor"
      }, 
      {children = {
          {children = {
              {children = {}, type = "com.fibaro.mobotix"}, 
              {children = {}, type = "com.fibaro.heliosGold"}, 
              {children = {}, type = "com.fibaro.heliosBasic"}, 
              {children = {}, type = "com.fibaro.alphatechFarfisa"}
            }, 
            type = "com.fibaro.intercom"
          }, 
          {children = {
              {children = {}, type = "com.fibaro.schlage"}, 
              {children = {}, type = "com.fibaro.polyControl"}, 
              {children = {}, type = "com.fibaro.kwikset"}, 
              {children = {}, type = "com.fibaro.gerda"}
            }, 
            type = "com.fibaro.doorLock"
          }, 
          {children = {
              {children = {
                  {children = {
                      {children = {}, type = "com.fibaro.fibaroIntercom"}
                    }, 
                    type = "com.fibaro.videoGate"
                  }
                }, 
                type = "com.fibaro.ipCamera"
              }
            },
            type = "com.fibaro.camera"
          }, 
          {children = {
              {children = {}, type = "com.fibaro.satelPartition"}, 
              {children = {}, type = "com.fibaro.envisaLinkPartition"}, 
              {children = {}, type = "com.fibaro.dscPartition"}
            }, 
            type = "com.fibaro.alarmPartition"
          }
        }, 
        type = "com.fibaro.securityMonitoring"
      }, 
      {children = {}, type = "com.fibaro.samsungSmartAppliances"}, 
      {children = {}, type = "com.fibaro.russoundXZone4"}, 
      {children = {}, type = "com.fibaro.russoundXSource"}, 
      {children = {}, type = "com.fibaro.russoundX5"}, 
      {children = {}, type = "com.fibaro.russoundMCA88X"},
      {children = {}, type = "com.fibaro.russoundController"}, 
      {children = {}, type = "com.fibaro.powerMeter"}, 
      {children = {}, type = "com.fibaro.planikaFLA3"}, 
      {children = {{children = {}, type = "com.fibaro.xbmc"}, 
          {children = {}, type = "com.fibaro.wakeOnLan"}, 
          {children = {}, type = "com.fibaro.sonosSpeaker"}, 
          {children = {}, type = "com.fibaro.russoundXZone4Zone"}, 
          {children = {}, type = "com.fibaro.russoundXSourceZone"}, 
          {children = {}, type = "com.fibaro.russoundX5Zone"}, 
          {children = {}, type = "com.fibaro.russoundMCA88XZone"},
          {children = {
              {children = {}, type = "com.fibaro.davisVantage"}}, 
            type = "com.fibaro.receiver"
          }, 
          {children = {}, type = "com.fibaro.philipsTV"}, 
          {children = {}, type = "com.fibaro.nuvoZone"}, 
          {children = {}, type = "com.fibaro.nuvoPlayer"}, 
          {children = {}, type = "com.fibaro.initialstate"}, 
          {children = {}, type = "com.fibaro.denonHeosZone"}, 
          {children = {}, type = "com.fibaro.denonHeosGroup"}
        }, 
        type = "com.fibaro.multimedia"},
      {children = {
          {children = {}, type = "com.fibaro.waterMeter"}, 
          {children = {}, type = "com.fibaro.gasMeter"}, 
          {children = {}, type = "com.fibaro.energyMeter"}
        }, 
        type = "com.fibaro.meter"
      }, 
      {children = {}, type = "com.fibaro.logitechHarmonyHub"}, 
      {children = {}, type = "com.fibaro.logitechHarmonyActivity"}, 
      {children = {}, type = "com.fibaro.logitechHarmonyAccount"}, 
      {children = {
          {children = {
              {children = {}, type = "com.fibaro.thermostatHorstmann"}
            }, 
            type = "com.fibaro.thermostatDanfoss"
          }, 
          {children = {}, type = "com.fibaro.FGT001"}
        },
        type = "com.fibaro.hvacSystem"
      }, 
      {children = {}, type = "com.fibaro.hunterDouglasScene"}, 
      {children = {}, type = "com.fibaro.hunterDouglas"}, 
      {children = {}, type = "com.fibaro.humidifier"}, 
      {children = {
          {children = {}, type = "com.fibaro.samsungWasher"}, 
          {children = {}, type = "com.fibaro.samsungRobotCleaner"},
          {children = {}, type = "com.fibaro.samsungRefrigerator"}, 
          {children = {}, type = "com.fibaro.samsungOven"}, 
          {children = {}, type = "com.fibaro.samsungDryer"}, 
          {children = {}, type = "com.fibaro.samsungDishwasher"},
          {children = {}, type = "com.fibaro.samsungAirPurifier"}, 
          {children = {
              {children = {
                  {children = {}, type = "com.fibaro.samsungAirConditioner"}, 
                  {children = {}, type = "com.fibaro.coolAutomationHvac"}
                }, 
                type = "com.fibaro.setPoint"
              }, 
              {children = {{children = {}, type = "com.fibaro.operatingModeHorstmann"}}, 
                type = "com.fibaro.operatingMode"
              }, 
              {children = {}, type = "com.fibaro.fanMode"}
              }, type = "com.fibaro.hvac"
          }
        }, 
        type = "com.fibaro.homeAutomation"
      }, 
      {children = {}, type = "com.fibaro.genericZwaveDevice"},
      {children = {}, type = "com.fibaro.denonHeos"}, 
      {children = {}, type = "com.fibaro.coolAutomation"}, 
      {children = {
          {children = {}, type = "com.fibaro.satelAlarm"}, 
          {children = {}, type = "com.fibaro.envisaLinkAlarm"}, 
          {children = {}, type = "com.fibaro.dscAlarm"}
        }, 
        type = "com.fibaro.alarm"
      }, 
      {children = {
          {children = {
              {children = {}, type = "com.fibaro.FGR221"}, 
              {children = {
                  {children = {}, type = "com.fibaro.FGWR111"},
                  {children = {}, type = "com.fibaro.FGRM222"},
                  {children = {}, type = "com.fibaro.FGR223"}
                }, 
                type = "com.fibaro.FGR"
              }
            }, 
            type = "com.fibaro.rollerShutter"
          }, 
          {children = {}, type = "com.fibaro.remoteSwitch"},
          {children = {
              {children = {
                  {children = {}, type = "com.fibaro.FGPB101"},
                  {children = {}, type = "com.fibaro.FGKF601"}, 
                  {children = {}, type = "com.fibaro.FGGC001"}
                }, 
                type = "com.fibaro.remoteSceneController"
              }
            }, 
            type = "com.fibaro.remoteController"
          }, 
          {children = {
              {children = {}, type = "com.fibaro.sprinkler"}, 
              {children = {}, type = "com.fibaro.satelOutput"}, 
              {children = {
                  {children = {
                      {children = {}, type = "com.fibaro.philipsHueLight"},
                      {children = {}, type = "com.fibaro.philipsHue"}, 
                      {children = {}, type = "com.fibaro.FGRGBW442CC"}, 
                      {children = {}, type = "com.fibaro.FGRGBW441M"}
                    }, 
                    type = "com.fibaro.colorController"
                  }, 
                  {children = {}, type = "com.fibaro.FGWD111"}, 
                  {children = {}, type = "com.fibaro.FGD212"}
                }, 
                type = "com.fibaro.multilevelSwitch"
              }, 
              {children = {
                  {children = {}, type = "com.fibaro.FGWPI121"}, 
                  {children = {}, type = "com.fibaro.FGWPG121"}, 
                  {children = {}, type = "com.fibaro.FGWPG111"}, 
                  {children = {}, type = "com.fibaro.FGWPB121"}, 
                  {children = {}, type = "com.fibaro.FGWPB111"}, 
                  {children = {}, type = "com.fibaro.FGWP102"}, 
                  {children = {}, type = "com.fibaro.FGWP101"}
                }, 
                type = "com.fibaro.FGWP"}, 
              {children = {}, type = "com.fibaro.FGWOEF011"}, 
              {children = {}, type = "com.fibaro.FGWDS221"}
              }, type = "com.fibaro.binarySwitch"
          }, 
          {children = {}, type = "com.fibaro.barrier"}
        }, 
        type = "com.fibaro.actor"}, 
      {children = {}, type = "com.fibaro.FGRGBW442"},
      {children = {}, type = "com.fibaro.FGBS222"}
    }, 
    type = "com.fibaro.device"
  }

  local function getHierarchy(tp,tree)
    if tree.type==tp then return {tp}
    else
      for _,c in ipairs(tree.children) do
        local m = getHierarchy(tp,c)
        if m then table.insert(m,tree.type) return m end
      end
    end
  end

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

  local function propChange(self,prop,newValue)
    local oldValue = self.properties[prop]
    if oldValue ~= newValue then
      refreshStates.addEvents(
        {type='DevicePropertyUpdatedEvent', data={id=tonumber(self.id),newValue=newValue,oldValue=oldValue,property=prop}}
      )
    end
  end

  local deviceTypes = {
    ["com.fibaro.binarySwitch"] = function(self)
      self.properties.value = false
      self.actions.turnOn = function() propChange(self,"value",true) end
      self.actions.turnOff = function() propChange(self,"value",false) end
    end,
    ["com.fibaro.multilevelSwitch"] = function(self)
      self.properties.value = 0
      self.actions.turnOn = function() propChange(self,"value",99) end
      self.actions.turnOff = function() propChange(self,"value",0) end
      self.actions.setValue = function(value) self.value.properties = value end
    end,
    ["com.fibaro.binarySensor"] = function(self)
      self.properties.value = false
      self.actions.turnOn = function() propChange(self,"value",true) end
      self.actions.turnOff = function() propChange(self,"value",false) end
    end,
    ["com.fibaro.multilevelSensor"] = function(self)
      self.properties.value = 0
      self.actions.turnOn = function() propChange(self,"value",99) end
      self.actions.turnOff = function() propChange(self,"value",0) end
      self.actions.setValue = function(value) self.value.properties = value end
    end,
  }

  local hierarchyCache = {}
  local function createDevice(id)
    local self = {
      id = id, 
      name = "<noname>", 
      type=hc3_emulator.defaultDevice, 
      properties = {
        value=nil, 
        modified=os.time() 
      },
      actions = {}
    }
    local tps,bt = hierarchyCache[self.type]
    if tps == nil then
      tps = getHierarchy(self.type,typeHierarchy)
      if #tps == 0 then error("Unsupported device type:"..self.type) end
      for _,t in ipairs(tps) do if deviceTypes[t] then bt = t break end end
      if not bt then error("Unsupported device type:"..self.type) end
      self.baseType = bt
    else self.baseType = tps end

    deviceTypes[self.baseType](self)
    return self
  end

  local function createGlobal(name,value)
    local self = {name=name, value=value, modified=os.time() }
    function self._setValue(val)
      local oldValue = self.value 
      self.value,self.modified = val.value,os.time()
      if self.value ~= oldValue then
        refreshStates.addEvents(
          {type='GlobalVariableChangedEvent', data={variableName=self.name, newValue=self.value, old=oldValue}}
        )
      end
    end
    return self
  end

  local function createCustomEvent(name,value)
    local self = {name=name, userDescription=value, modified=os.time() }
    return self
  end

  local function addCreator(tab,fun)
    setmetatable(tab, {
        __newindex = function(mytable, key, value)
          return rawset(mytable, key, fun(key))
        end,
        __index = function(mytable, key)
          if not rawget(mytable,key) then
            rawset(mytable, key, fun(key))
          end
          return  rawget(mytable,key)
        end
      })
  end

  addCreator(resources.devices,createDevice)
  addCreator(resources.globalVariables,createGlobal)
  addCreator(resources.customEvents,createCustomEvent)

--hc3_emulator.createDevice(99,"com.fibaro.multilevelSwitch")
  function self.createDevice(id,tp)
    tp = tp or hc3_emulator.defaultDevice
    local temp
    hc3_emulator.defaultDevice,temp=tp,hc3_emulator.defaultDevice
    local d = resources.devices[tostring(id)]
    hc3_emulator.defaultDevice=temp
    return d
  end

  self.api = offlineApi
  return self
end

hc3_emulator.EventCache = { polling=false, devices={}, globals={}, centralSceneEvents={}} -- Caching values when we poll to reduce traffic to HC3...

--------------- Modules ------------------------------
Util    = module.Utilities()
json    = module.Json()
Timer   = module.Timer()
Trigger = module.Trigger()
fibaro  = module.FibaroAPI()
QA      = module.QuickApp()
Scene   = module.Scene()
Web     = module.WebAPI()
Offline = module.Offline()

local function DEFAULT(v,d) if v~=nil then return v else return d end end
hc3_emulator.offline = DEFAULT(hc3_emulator.offline,false)
hc3_emulator.defaultDevice = DEFAULT(hc3_emulator.defaultDevice,"com.fibaro.binarySwitch")
hc3_emulator.autocreateDevices = DEFAULT(hc3_emulator.autocreateDevices,true)
hc3_emulator.autocreateGlobals = DEFAULT(hc3_emulator.autocreateGlobals,true)

hc3_emulator.updateViewLayout = QA.updateViewLayout
hc3_emulator.createQuickApp = QA.createQuickApp
hc3_emulator.createProxy = QA.createProxy
hc3_emulator.getIPaddress = Util.getIPaddress
hc3_emulator.createDevice = Offline.createDevice --(id,tp)

function hc3_emulator.start(args)
  if not hc3_emulator.offline and not hc3_emulator.credentials then
    error("Missing HC3 credentials -- hc3_emulator.credentials{ip=<IP>,user=<string>,pwd=<string>}")
  end
  hc3_emulator.speeding = args.speed==true and 48 or tonumber(args.speed)
  if hc3_emulator.speeding then Timer.speedTime(hc3_emulator.speeding) end
  if args.traceFibaro then Util.traceFibaro() end

  Log(LOG.SYS,"HC3 SDK v%s",hc3_emulator.version)
  if hc3_emulator.speeding then Log(LOG.SYS,"Speeding %s hours",hc3_emulator.speeding) end
  if not (args.startWeb==false) then Web.start(Util.getIPaddress()) end

  if hc3_emulator.conditions and hc3_emulator.actions then 
    Scene.start(args)  -- Run a scene
  else 
    QA.start(args) 
  end
  Timer.start()
end