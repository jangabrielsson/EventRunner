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
-  @rangee, forum.fibaro.com
-  @petrkl12, forum.fibaro.com

Sources included:
json           -- Copyright (c) 2019 rxi
persistence    -- Copyright (c) 2010 Gerhard Roethlin
file functions -- Credit pkulchenko - ZeroBraneStudio
copas          -- Copyright 2005-2016 - Kepler Project (www.keplerproject.org)
timerwheel     -- Credit https://github.com/Tieske/timerwheel.lua/blob/master/LICENSE
binaryheap     -- Copyright 2015-2019 Thijs Schreijer
--]]

local FIBAROAPIHC3_VERSION = "0.314" 
assert(_VERSION:match("(%d+%.%d+)") >= "5.3","fibaroapiHC3.lua needs Lua version 5.3 or higher")

--[[
  Best way is to conditionally include this code at the top of your lua file
    if dofile and not hc3_emulator then
      hc3_emulator = {
       name = "My QA",    -- Name of QA
       poll = 2000,       -- Poll HC3 for triggers every 2000ms
      --offline = true,
       quickVars = {["Hue_User"]="$CREDS.Hue_user",["Hue_IP"]=$CREDS.Hue_IP}
      }
      dofile("fibaroapiHC3.lua")
    end--hc3
  Then define another file, credentials.lua, where we define credentials to access the HC3 etc:
  return {
    ip = <IP>,
    user = <username>,
    pwd = <password>
  }
  This file will be read by the emulator when it starts up and the table returned
  will be assigned to hc3_emulator.credentials.
  hc3_emulator.credentials.ip,hc3_emulator.credentials.user,hc3_emulator.credentials.pwd will
  be used by the emulator to authorize calls to the HC3.
  This way the credentials are not visible in your code and you will not accidently upload them :-)
  You can also predefine quickvars that are accessible with self:getVariable() when your code starts up.
  quickVar names starting with '$CREDS.' will be replaced with values from hc3_emulator.credentials.
--]]

--[[

Common hc3_emulator parameters:
---------------------------------
hc3_emulator.name=<string>             -- Name of QuickApp, default "QuickApp"
hc3_emulator.id=<QuickApp ID>          -- ID of QuickApp. Normally let emulator asign ID. (usually 999 for non-proxy QA)
hc3_emulator.poll=<poll interval>      -- Time in ms to poll the HC3 for triggers. default false
hc3_emulator.type=<type>               -- default "com.fibaro.binarySwitch"
hc3_emulator.speed=<speedtime>         -- If not false, time in hours the emulator should speed. default false
hc3_emulator.proxy=<boolean>           -- If true create HC3 procy. default false
hc3_emulator.UI=<UI table>             -- Table defining buttons/sliders/labels. default {}
hc3_emulator.quickVars=<table>         -- Table with values to assign quickAppVariables. default {},
hc3_emulator.offline=<boolean>         -- If true run offline with simulated devices. default false
hc3_emulator.autocreate=<boolean>      -- Autocreate local resources
hc3_emulator.breakOnInit=<boolean>     -- Tries to set breakpoint on QuickApp:onInit (mobdebug)
hc3_emulator.breakOnLoad=<boolean>     -- Tries  to set breakpoint on first line in loaded file (mobdebug)
hc3_emulator.breakOnError=<boolean>    -- Tries to break after error (makes it easier to look at call stack etc)
hc3_emulator.apiHTTPS=<boolean>        -- If true use https to call HC3 REST apis. default false
hc3_emulator.deploy=<boolean>,         -- If true deploy code to HC3 instead of running it. default false
hc3_emulator.assetDirectory=<string>   -- Directory where assets shoud be downloaded (ZBS). Default  ~/.zbstudio/hc3emu
hc3_emulator.resourceFile=<string>     -- When doing a resource download, use this file as default.
hc3_emulator.db=<boolean/string>,      -- If true load a "resource download" from hc3_emulator.resourceFile or string
hc3_emulator.htmlDebug=<boolean>       -- Try to convert html tags to ZBS console cmds (i.e. colors)
hc3_emulator.terminalPort=<boolean>    -- Port used for socket/telnet interface
hc3_emulator.webPort=<number>          -- Port used for web UI and events from HC3
hc3_emulator.HC3_logmessages=<boolean> -- Defult false. If true will push log messages to the HC3 also.
hc3_emulator.supressTrigger            -- Make the emulator ignore certain events from the HC3, like = PluginChangedViewEvent
hc3_emulator.negativeTimeout=<boolean> -- Allow specification of negative timeout for setTimeout (will fire immediatly)
hc3_emulator.strictClass=<boolean>     -- Strict class semantics, requiring initializers
hc3_emulator.consoleColors=<table>     -- Maps fibaro.debug/self:debug etc to color (debug.color enables color debugging)
hc3_emulator.sysConsoleColors=<table>  -- Maps colors used for system logs 
hc3_emulator.userdataType=<boolean>    -- If true intercepts type(...) to return userdate for our Lua classes. Some apps tests this...
hc3_emulator.package=...               -- Lua library paths (.path, .cpath)

Common hc3_emulator functions:
---------------------------------
hc3_emulator.setOffline(<boolean>,<boolean>)  --
hc3_emulator.getIPaddress()                   -- Return HC3 IP address
hc3_emulator.prettyJsonFormat(<table>)        -- Return json formatted string of Lua table
hc3_emulator.postTrigger(<event>,[<time ms>]) -- Posts a trigger to the emulator...
hc3_emulator.loadScene(...)                   -- Load scene from file or HC3...
hc3_emulator.loadQA(...)                      -- Load QA from file or HC3...
hc3_emulator.downloadPlugin()                 -- (ZBS). Default ~/.zbstudio/packages
hc3_emulator.downloadAssets()                 -- (ZBS). Default ~/.zbstudio/hc3emu
hc3_emulator.downloadResources([<filename>])  -- Downloads a "backup" of HC3 resources
hc3_emulator.loadResources([<filename>])      -- ...that can be loaded as "local" resources for the emulator.


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
fibaro.clearTimeout(ref)
fibaro.emitCustomEvent(name)
fibaro.wakeUpDeadDevice
fibaro.sleep(ms) -- blocking wait...

net.HTTPClient()
net.TCPSocket()
net.UDPSocket()
net.WebSocketClient()       -- needs extra download
net.WebSocketClientTls()    -- needs extra download
mqtt.Client()               -- needs extra download
api.get(call)
api.put(call <, data>)
api.post(call <, data>)
api.delete(call <, data>)

setTimeout(func, ms)
clearTimeout(ref)
setInterval(func, ms)
clearInterval(ref)

plugin.mainDeviceId
plugin.deleteDevice(deviceId)
plugin.restart(deviceId)
plugin.getProperty(id,prop)
plugin.getChildDevices(id)
plugin.createChildDevice(prop)

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

local _debugFlags = {
  fibaro=false,        -- Logs calls to fibaro api
  trigger=true,        -- Logs incoming triggers from HC3 or internal emulator
  timers=nil,          -- Logs low level  info on timers being called, very noisy.
  refreshloop=false,   -- Logs evertime refreshloop receives events
  mqtt=true,           -- Logs mqtt   message and callbacks
  http=false,          -- Logs all net.HTTPClient():request. ALso includes the time the request took
  api=false,           -- Logs all api request to the HC3
  onAction=true,       -- Logs call to onAction (incoming fibaro.calls etc
  UIEvent=true,        -- Logs incoming UIEvents,  from GUI elements
  zbsplug=true,        -- Logs call from ZBS plugin calls
  webServer=false,     -- Logs requests to /web/ including headers
  webServerReq=false,  -- Logs requests to /web/ excluding headers
  files=false,         -- Logs files loaded and run
  color=true,          -- Logs in console using ANSI colors (see hc3_emulator.consoleColors for mapping)
  locl=true,           -- Log creation of local devices
  breakOnError=false,  -- Logs files loaded and run
  breakOnLoad=false,   -- Sets breakpoint on first line of file loaded
  ctx=false,           -- Logs Lua context switches
  timersSched=false,   -- Logs when timers are scheduled
  timersWarn=0.500,    -- Logs when  timers are called late or setTimeout with time < 0
  timersExtra=true,    -- Adds extra info to timers, like from where it's called and definition of function (small time penalty)
}
local function merge(t1,t2)
  if type(t1)=='table' and type(t2)=='table' then for k,v in pairs(t2) do if t1[k]==nil then t1[k]=v else merge(t1[k],v) end end end
  return t1
end

QuickApp,QuickAppBase,QuickAppChild = nil,nil,nil

local function DEF(x,y) if x==nil then return y else return x end end
hc3_emulator = hc3_emulator or {}
hc3_emulator.version           = FIBAROAPIHC3_VERSION
hc3_emulator.credentialsFile   = hc3_emulator.credentialsFile or "credentials.lua"
hc3_emulator.resourceFile      = DEF(hc3_emulator.resourceFile,"HC3resources.data")
hc3_emulator.HC3dir            = hc3_emulator.HC3dir or "HC3files" -- not used
hc3_emulator.backupDir         = hc3_emulator.backupDir or "/tmp"  -- not used
hc3_emulator.backDirFmt        = "%m-%d-%Y %H.%M.%S"               -- not used
hc3_emulator.conditions        = false
hc3_emulator.actions           = false
hc3_emulator.offline           = DEF(hc3_emulator.offline,false)
hc3_emulator.autoCreate        = DEF(hc3_emulator.autoCreate,hc3_emulator.offline)
hc3_emulator.emulated          = true
hc3_emulator.debug             = merge(hc3_emulator.debug  or {},_debugFlags)
hc3_emulator.runSceneAtStart   = false
hc3_emulator.webPort           = hc3_emulator.webPort or 6872
hc3_emulator.terminalPort      = hc3_emulator.terminalPort or 6972
hc3_emulator.quickVars         = hc3_emulator.quickVars or {}
hc3_emulator.htmlDebug         = DEF(hc3_emulator.htmlDebug,true)
hc3_emulator.supressTrigger    = {["PluginChangedViewEvent"] = true} -- Ignore noisy triggers...
hc3_emulator.negativeTimeout   = DEF(hc3_emulator.negativeTimeout,true)
hc3_emulator.strictClass       = true
hc3_emulator.HC3_logmessages   = DEF(hc3_emulator.HC3_logmessages,false)
hc3_emulator.githubSrc         = "https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/"
hc3_emulator.deviceIDs         = DEF(hc3_emulator.deviceIDs,9000)

hc3_emulator.emu = {}
hc3_emulator.emu.EMURUNNING               = "HC3Emulator"
hc3_emulator.emu.EMURUNNING_INTERVAL      = 4.0
_debugFlags  = hc3_emulator.debug

do
  local cr = loadfile(hc3_emulator.credentialsFile)
  --hc3_emulator.credentials = hc3_emulator.credentials or {}
  if cr then hc3_emulator.credentials = merge(hc3_emulator.credentials or {},cr() or {}) end
end

do
  if type(package)=='table' then -- For VS. 
    -- See https://forum.fibaro.com/topic/49488-sdk-for-remote-and-offline-hc3-development/page/8/?tab=comments#comment-225963
    if hc3_emulator.package then
      package.path,package.cpath = package.path..";"..hc3_emulator.package.path, package.cpath..";"..hc3_emulator.package.cpath
    else
      package.path = package.path .. ";./libs/?.lua";
      package.cpath = package.cpath .. ";./libs/?.dll";
    end
  end
  local socket  = require("socket")         -- LuaSocket, these are the dependencies we have
  local url     = require("socket.url")     -- LuaSocket
  local headers = require("socket.headers") -- LuaSocket
  local ltn12   = require("ltn12")          -- LuaSocket
  local mime    = require("mime")           -- LuaSocket
  local lfs     = require("lfs")            -- LuaFileSystem,
--  optional require('mobdebug')           -- Lua remote debugger
  assert(socket and url and headers and ltn12 and mime and lfs,"Missing libraries")

  local stat,mobdebug = pcall(function() return require('mobdebug') end) -- Load mobdebug if available to debug coroutines..
  local fid = function() end
  hc3_emulator.mobdebug = stat and mobdebug or {coro=fid, pause=fid, setbreakpoint=fid, on=fid, off=fid}
  hc3_emulator.mobdebug.coro()
end 

local profiler = nil
local function osExit()
  if hc3_emulator.profile and profiler then
    profiler.stop()
    profiler.report("profiler.log")
  end
  os.exit(0,true)
end

collectgarbage("setpause",100)
collectgarbage("setstepmul",150)

-- Globals
LOG,Log,json,assertf,api,net=nil,nil,nil,nil,nil,nil
local module,commandLines,terminals = {},{},{}
onAction,onUIEvent = nil,nil

local function d2str(...) local r,s={...},{} for i=1,#r do if r[i]~=nil then s[#s+1]=tostring(r[i]) end end return table.concat(s," ") end
------------------- Contexts, QuickApps and Scenes -------------------------
local contexts = {}
setmetatable(contexts,{__mode='k'})
local function setContext(env)
  local co = coroutine.running()
  if _debugFlags.ctx then print("SC:",((env or _ENV).plugin or {}).mainDeviceId,tostring(co),tostring(env.quickApp)) end
  contexts[co]=env or _ENV
end
local function getContext()
  local co = coroutine.running()
  local env = contexts[co] or {}
  if _debugFlags.ctx then print("GC:",(env.plugin or {}).mainDeviceId,tostring(co),tostring(env.quickApp)) end
  return env
end
setContext(_G) -- Start, main thread

-------------- Fibaro API functions ------------------
function module.Fibaro(hc3)
  local self,fibaro = {},{version = "1.0.0"}
  local Util,Trigger,Timer = hc3.module.Util
  local copas,cache,safeDecode,urlencode,colorStr
  local _debugFlags = hc3.debug
  local format = string.format
  local GET_DEVICE,GET_SCENE,GET_PROPERTY,GET_VARIABLE,PUT_VARIABLE,CALL_ACTION

  Log,LOG,json,api,net,assert,assertf=Log,LOG,json,api,net,assert,assertf

  function self.initialise() --luacheck: ignore
    Trigger,Timer = hc3.module.Trigger,hc3.module.Timer
    cache,safeDecode,urlencode,colorStr = Trigger.cache,Util.safeDecode,Util.urlencode,Util.colorStr
    copas = Timer.copas
    local API = hc3.module.API
    GET_DEVICE = API.GET_DEVICE
    GET_SCENE = API.GET_SCENE
    GET_PROPERTY = API.GET_PROPERTY
    GET_VARIABLE = API.GET_VARIABLE
    PUT_VARIABLE = API.PUT_VARIABLE
    CALL_ACTION = API.CALL_ACTION
    POST_DEBUGMESSAGE = API.POST_DEBUGMESSAGE
  end

  local function __assert_type(value,typeOfValue )
    if type(value) ~= typeOfValue then  -- Wrong parameter type, string required. Provided param 'nil' is type of nil
      error(format("Wrong parameter type, %s required. Provided param '%s' is type of %s",
          typeOfValue,tostring(value),type(value)),
        3)
    end
  end

  local function __fibaro_get_device(id) __assert_type(id,"number") return GET_DEVICE(nil,"/devices/"..id,id) end
  local function __fibaro_get_devices() return api.get("/devices") end
  local function __fibaro_get_room (id) __assert_type(id,"number") return api.get("/rooms/"..id) end
  local function __fibaro_get_scene(id) __assert_type(id,"number") return GET_SCENE(nil,"/scenes/"..id,id) end
  local function __fibaro_get_global_variable(name) __assert_type(name ,"string")
    local c = cache.read('globals',0,name) or GET_VARIABLE(nil,"/globalVariables/"..name,name)
    cache.write('globals',0,name,c)
    return c
  end

  local function __fibaro_get_device_property(id ,prop)
    __assert_type(id,"number")
    __assert_type(prop,"string")
    local c = cache.read('devices',id,prop) or GET_PROPERTY(nil,"/devices/"..id.."/properties/"..prop,id,prop)
    cache.write('devices',id,prop,c)
    return c
  end
  local function __fibaroSleep(ms)
    __assert_type(ms,'number')
    --local ctx = getContext()
    --if ctx.getLock then ctx.getLock() end
    copas.sleep(ms/1000.0)
    --if ctx.releaseeLock then ctx.releaseLock() end
  end

  local function __fibaro_add_debug_message(tag,type,str)
    assert(str,"Missing tag for debug")
    POST_DEBUGMESSAGE({message=str,messageType=type,tag=tag},"/debugMessages")
  end
  function fibaro.debug(tag,...)  __fibaro_add_debug_message(tag,"DEBUG",d2str(...)) end
  function fibaro.warning(tag,...) __fibaro_add_debug_message(tag,"WARNING",d2str(...)) end
  function fibaro.trace(tag,...) __fibaro_add_debug_message(tag,"TRACE",d2str(...)) end
  function fibaro.error(tag,...) __fibaro_add_debug_message(tag,"ERROR",d2str(...)) end

  function fibaro.getName(deviceID)
    __assert_type(deviceID,'number')
    local dev = __fibaro_get_device(deviceID)
    return dev and dev.name
  end

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
      local a = {args={},delay=0}
      local args = {...}
      for i,v in ipairs(args) do a.args[i]=v end
      local res,stat = CALL_ACTION(a,"/devices/"..deviceID.."/action/"..actionName,deviceID,actionName)
      if stat>202 then Log(LOG.ERROR,"Device %s does not exists - %s",deviceID,stat) end
      return res
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

  function fibaro.setGlobalVariable(name , value)
    __assert_type(name ,"string")
    local data =  {["value"] = tostring(value) , ["invokeScenes"] = true}
    PUT_VARIABLE(data,"/globalVariables/"..name,name)
  end

  function fibaro.emitCustomEvent(name) return api.post("/customEvents/"..name,{}) end

  function fibaro.setTimeout(value, func) return Timer.setTimeout(func, value) end
  function fibaro.clearTimeout(ref) return Timer.clearTimeout(ref) end

  function fibaro.getRoomName(roomID)
    __assert_type(roomID,'number')
    local room = __fibaro_get_room(roomID)
    return room and room.name
  end

  function fibaro.getRoomID(deviceID)
    local dev = __fibaro_get_device(deviceID)
    return dev and (dev.roomID or 0)
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
    local function encode(s) return tostring(s) end -- urlencode(tostring(s)) end
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
    return fibaro.getIds(api.get(urlencode('/devices'..args)))
  end

  function fibaro.scene(action, sceneIDs) -- execute or kill
    __assert_type(sceneIDs,'table')
    assert(action=='execute' or action=='kill',"fibaro.scene arguments mist be execute/kill")
    for _,id in ipairs(sceneIDs) do api.post("/scenes/"..id.."/"..action,{}) end
  end

  function fibaro.profile(profile_id, action)
    if hc3.codeType == 'QA' then
      profile_id,action = action,profile_id
    end
    __assert_type(profile_id,'number')
    __assert_type(action,'string')
    return api.post("/profiles/"..action.."/"..profile_id,{})
  end

  function fibaro.callGroupAction(action,args)
    __assert_type(action,'string')
    __assert_type(args,'table')
    local res,stat = api.post("/devices/groupAction/"..action,args)
    return stat==202 and res.devices
  end

  function fibaro.alert(alertType, users, msg)
    alertType = ({simplePush='simplePush',push='sendGlobalPushNotifications',email='sendGlobalEmailNotifications',sms='sendSms'})[alertType]
    assert(alertType,"Missing alert type: 'push', 'email', 'sms'")
    __assert_type(users,'table')
    for _,u in ipairs(users) do fibaro.call(u,alertType,msg,"false") end
  end

-- User PIN?
  function fibaro.alarm(partition_id, action)
    if action==nil then
      action = partition_id
      assert(action=='arm' or action=='disarm',"alarm action is 'arm' or 'disarm'")
      if action=='arm' then
        api.post("/alarms/v1/partitions/actions/arm",{})
      elseif action=='disarm' then
        api.delete("/alarms/v1/partitions/actions/arm",{})
      end
    else
      assert(action=='arm' or action=='disarm',"alarm action is 'arm' or 'disarm'")
      __assert_type(partition_id,'number')
      if action=='arm' then
        return api.post(format("/alarms/v1/partitions/%s/actions/arm",partition_id),{})
      elseif action=='disarm' then
        return api.delete(format("/alarms/v1/partitions/%s/actions/arm",partition_id),{})
      end
    end
  end

  function fibaro.__houseAlarm() end -- ToDo:

  function fibaro.sleep(ms) __fibaroSleep(ms) end

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

  local fjson = Util.prettyJson
  local function patchFibaro(name)
    local oldF,flag = fibaro[name],"f"..name
    fibaro[name] = function(...)
      local args = {...}
      local res = {oldF(...)}
      if _debugFlags[flag] then
        args = #args==0 and "" or fjson(args):sub(2,-2)
        Log(LOG.LOG,"fibaro.%s(%s) => %s",name,args,#res==0 and "nil" or #res==1 and res[1] or res)
      end
      return table.unpack(res)
    end
  end

  local fibaroFunsToPatch = {
    "call","getType","getValue","getName","get","getGlobalVariable","setGlobalVariable","getRoomName",
    "getRoomID","getRoomNameByDeviceID","getSectionID","getIds","getDevicesID","scene","profile","callGroupAction",
    "alert","alarm","setTimeout","clearTimeout","emitCustomEvent","wakeUpDeadDevice","sleep"
  }

  function self.traceFibaro()
    for _,name in ipairs(fibaroFunsToPatch) do patchFibaro(name) end
    _debugFlags["f".."call"]=true
  end

  self.fibaro = fibaro
  self.__assert_type = __assert_type
  self.__fibaro_get_device = __fibaro_get_device
  self.__fibaro_get_devices = __fibaro_get_devices
  self.__fibaro_get_room = __fibaro_get_room
  self.__fibaro_get_scene = __fibaro_get_scene
  self.__fibaro_get_global_variable = __fibaro_get_global_variable
  self.__fibaro_get_device_property = __fibaro_get_device_property
  self.__fibaro_add_debug_message = __fibaro_add_debug_message
  self.__fibaroSleep = __fibaroSleep

  return self
end--module Fibaro

------------  HTTP support ---------------------
-- An emulation of Fibaro's net.HTTPClient, net.TCPSocket() and net.UDPSocket()
function module.HTTP(hc3)
  local self = {}
  local Util,Trigger,Timer = hc3.module.Util
  local _debugFlags = hc3.debug
  local urlencode,copas=Util.urlencode
  Log,LOG,json,api,net,assert,assertf=Log,LOG,json,api,net,assert,assertf

  local socket  = require("socket")         -- LuaSocket, these are the dependencies we have
  local ltn12   = require("ltn12")          -- LuaSocket

  function self.initialise() --luacheck: ignore
    Trigger,Timer = hc3.module.Trigger,hc3.module.Timer
    copas = Timer.copas
  end

  local function interceptLocal(url,options,success,_) --error)
    if url:match("://(127%.0%.0%.1)[:/]") then
      local refresh = url:match("/api/refreshStates%?last=(%d+)")
      if refresh then
        local state = Trigger.refreshStates.getEvents(tonumber(refresh))
        if success then success({status=200,data=json.encode(state)}) end
        return true
      end
      url = url:gsub("(://127%.0%.0%.1)","://"..(hc3.credentials.ip or "127.0.0.1"))
      if url:match("://.-:11111/") then
        url = url:gsub("(:11111)","")
        options.headers = options.headers or {}
        options.headers['Authorization'] = hc3.BasicAuthorization or ""
      end
    end
    return false,url
  end

  local net = net or {}
  local outstanding = 0

  function net.HTTPClient(i_options)   
    local self = {}                   
    function self:request(url,args)
      if outstanding > 30 then
        Log(LOG.WARNING,"Number of outstanding http requests %s",outstanding)
      end
      local req,resp = {},{}; for k,v in pairs(i_options or {}) do req[k]=v end
      for k,v in pairs(args.options or {}) do req[k]=v end
      req.timeout = req.timeout or (i_options and i_options.timeout)
      if req.timeout then req.timeout = req.timeout / 1000.0  end -- timeout in ms -> s
      local s,u = interceptLocal(url,req,args.success,args.error)
      if s then return else url=u end
      req.url = url
      req.headers = req.headers or {}
      req.sink = ltn12.sink.table(resp)
      if req.data then
        req.headers["Content-Length"] = #req.data
        req.source = ltn12.source.string(req.data)
      else req.headers["Content-Length"]=0 end
      local ctx = getContext()
      local sync = i_options and i_options.sync==true
      if not sync then assert(ctx._getLock,"net.HTTPClient() not called from QuickApp/Scene") end
      local call = sync and (function(f) f() end) or ctx.setTimeout
      call(function()
          local t1 = os.milliTime()
          if not sync then ctx._releaseLock() end -- release lock so other timers in the QA can run during the request
          outstanding = outstanding +1
          local _,status,headers = copas.http.request(req)
          outstanding = outstanding -1
          if not sync then ctx._getLock() end
          if _debugFlags.http then Log(LOG.LOG,"httpRequest(%.03fs): %s %s %s",os.milliTime()-t1,req.method,url,req.data or "") end
          if tonumber(status) and status >= 200 and status < 400 then
            if args.success then
              call(function()
                  args.success(
                    {status=status, headers=headers, data=table.concat(resp)})
                end,
                0,"HTTP Success handler",nil,nil,_debugFlags.timersExtra and debug.getinfo(args.success,"Sl")
              )
            end
          elseif args.error then call(function() args.error(status) end,0,"HTTP Error handler") end
        end, 0, "HTTPClient", ctx)
      return nil
    end
    local pstr = "HTTPClient object: "..tostring(self):match("%s(.*)")
    setmetatable(self,{__tostring = function() return pstr end})
    return self
  end

  function net.TCPSocket(opts)
    local self = { opts = opts or {} }
    local sock --= socket.tcp()
    function self:connect(ip, port, opts)
      for k,v in pairs(self.opts) do opts[k]=v end
      local err
      sock,err = socket.connect(ip,port)
      if err==nil and opts and opts.success then sock:settimeout(0) opts.success()
      elseif opts and opts.error then opts.error(err) end
    end
    function self:read(opts) -- I interpret this as reading as much as is available...?
      copas.addthread(function()
          local data,res = {}
          local b,err = copas.receive(sock,1)
          if not err then
            data[#data+1]=b
            while socket.select({sock},nil,0.1)[1] do
              b,err = copas.receive(sock,1)
              if b then data[#data+1]=b else break end
            end
            res = table.concat(data)
          end
          if res and opts and opts.success then opts.success(res)
          elseif res==nil and opts and opts.error then opts.error(err) end
        end)
    end
    local function check(data,del)
      local n = #del
      for i=1,#del do if data[#data-n+i]~=del:sub(i,i) then return false end end
      return true
    end
    function self:readUntil(delimiter, opts) -- Read until the cows come home, or closed
      copas.addthread(function()
          local data,ok,res = {},true,nil
          local b,err = copas.receive(sock,1)
          if not err then
            data[#data+1]=b
            if not check(data,delimiter) then
              ok = false
              while true do
                b,err = copas.receive(sock,1)
                if b then 
                  data[#data+1]=b 
                  if check(data,delimiter) then ok=true break end
                else break end
              end -- while
            end
            if ok then
              for i=1,#delimiter do table.remove(data,#data) end
              res = table.concat(data)
            end
          end
          if res and opts and opts.success then opts.success(res)
          elseif res==nil and opts and opts.error then opts.error(err) end
        end)
    end
    function self:write(data, opts)
      copas.addthread(function()
          local res,err = copas.send(sock,data)
          if res and opts and opts.success then opts.success(res)
          elseif res==nil and opts and opts.error then opts.error(err) end
        end)
    end
    function self:close() sock:close() end
    local pstr = "TCPSocket object: "..tostring(self):match("%s(.*)")
    setmetatable(self,{__tostring = function() return pstr end})
    return self
  end

  function net.UDPSocket(opts)
    local self = { opts = opts or {} }
    local sock = socket.udp()
    if self.opts.broadcast~=nil then
      sock:setsockname(Util.getIPaddress(), 0)
      sock:setoption("broadcast", self.opts.broadcast)
    end
    if opts.timeout~=nil then sock:settimeout(opts.timeout / 1000) end
    function self:sendTo(datagram, ip,port, callbacks) -- udp sendTo doesn't block.
      local stat, res = copas.sendto(sock, datagram, ip, port)
      if stat and callbacks.success then
        pcall(callbacks.success,1)
      elseif stat==nil and callbacks.error then
        pcall(callbacks.error,res)
      end
    end
    function self:bind(ip,port) sock:setsockname(ip, port) end
    function self:receive(callbacks)
      copas.addthread(function()
          local stat, res = copas.receivefrom(sock,ip,port)
          if stat and callbacks.success then
            pcall(callbacks.success,stat, res)
          elseif stat==nil and callbacks.error then
            pcall(callbacks.error,res)
          end
        end)
    end
    function self:close() sock:close() end
    local pstr = "UDPSocket object: "..tostring(self):match("%s(.*)")
    setmetatable(self,{__tostring = function() return pstr end})
    return self
  end

-------------- MQTT support ---------------------
  local function safeJson(e)
    if type(e)=='table' then
      for k,v in pairs(e) do e[k]=safeJson(v) end
      return e
    elseif type(e)=='function' or type(e)=='thread' or type(e)=='userdata' then return tostring(e)
    else return e end
  end

  local mqtt
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
      args.uri = string.gsub(uri, "mqtt://", "")
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
          Debug(_debugFlags.mqtt,"MQTT connect:"..Util.prettyJson(connack))
          if client._handlers['connected'] then
            client._handlers['connected']({sessionPresent=connack.sp,returnCode=connack.rc})
          end
        end,
        subscribe = function(event)
          Debug(_debugFlags.mqtt,"MQTT subscribe:"..Util.prettyJson(event))
          if client._handlers['subscribed'] then client._handlers['subscribed'](safeJson(event)) end
        end,
        unsubscribe = function(event)
          Debug(_debugFlags.mqtt,"MQTT unsubscribe:"..Util.prettyJson(event))
          if client._handlers['unsubscribed'] then client._handlers['unsubscribed'](safeJson(event)) end
        end,
        message = function(msg)
          Debug(_debugFlags.mqtt,"MQTT message:"..Util.prettyJson(msg))
          local msgt = mqtt.MSGMAP[msg.type]
          if msgt and client._handlers[msgt] then client._handlers[msgt](msg)
          elseif client._handlers['message'] then client._handlers['message'](msg) end
        end,
        acknowledge = function(event)
          Debug(_debugFlags.mqtt,"MQTT acknowledge:"..Util.prettyJson(event))
          if client._handlers['acknowledge'] then client._handlers['acknowledge']() end
        end,
        error = function(err)
          if _debugFlags.mqtt then Log(LOG.ERROR,"MQTT error:"..err) end
          if client._handlers['error'] then client._handlers['error'](err) end
        end,
        close = function(event)
          Debug(_debugFlags.mqtt,"MQTT close:"..Util.prettyJson(event))
          event = safeJson(event)
          if client._handlers['closed'] then client._handlers['closed'](safeJson(event)) end
        end,
        auth = function(event)
          Debug(_debugFlags.mqtt,"MQTT auth:"..Util.prettyJson(event))
          if client._handlers['auth'] then client._handlers['auth'](safeJson(event)) end
        end,
      }

      _mqtt.get_ioloop():add(client._client)
      if not mqtt._loop then
        local iter = _mqtt.get_ioloop()
        mqtt._loop = os.setTimer(function() iter:iteration() end,1000,true)
      end
      return client
    end
  else
    mqtt={ Client = {} }
    function mqtt.Client.connect()
      Log(LOG.ERROR,
[[You need to have installed https://github.com/xHasKx/luamqtt so that require("mqtt") works from fibaroapiHC3.lua]]
      )
    end
  end

-------------- WebSocket support ---------------------
  local stat2,websocket = pcall(function()
      local v,res=_VERSION,require("wsLua_ER")
      net._WSVERSION,_VERSION = _VERSION,v
      return res
    end)
  if stat2 then

    function net.WebSocketClientTls()
      local POLLINTERVAL = 1000
      local conn,err,lt = nil
      local self = { }
      local handlers = {}
      local function dispatch(h,...)
        if handlers[h] then
          h = handlers[h]
          local args = {...}
          os.setTimer(function() h(table.unpack(args)) end,0)
        end
      end
      local function listen()
        if not conn then return end
        local function loop()
          if lt == nil then return end
          websocket.wsreceive(conn)
          if lt then lt = os.setTimer(loop,POLLINTERVAL) end
        end
        lt = os.setTimer(loop,0)
      end
      local function stopListen() if lt then os.clearTimer(lt) lt = nil end end
      local function disconnected() websocket.wsclose(conn) conn=nil; stopListen(); dispatch("disconnected") end
      local function connected() self.co = true; listen();  dispatch("connected") end
      local function dataReceived(data) dispatch("dataReceived",data) end
      local function error(err) dispatch("error",err) end
      local function message_handler( conn, opcode, data, ... )
        if not opcode then
          error(data)
          disconnected()
        else
          dataReceived(data)
        end
      end
      function self:addEventListener(h,f) handlers[h]=f end
      function self:connect(url)
        if conn then return false end
        conn, err = websocket.wsopen( url, message_handler, nil ) --options )
        if not err then connected(); return true
        else return false,err end
      end
      function self:send(data)
        if not conn then return false end
        if not websocket.wssend(conn,1,data) then return disconnected() end
        return true
      end
      function self:isOpen() return conn and true end
      function self:close() if conn then disconnected() return true end end
      return self
    end

    net.WebSocketClient = net.WebSocketClientTls
  else
    function net.WebSocketClientTls()
      Log(LOG.ERROR,
[[You need to have installed https://github.com/jangabrielsson/wsLua_ER so that require("wsLua_ER") works from fibaroapiHC3.lua]]
      )
    end
    net.WebSocketClient = net.WebSocketClientTls
  end

  local function safeDecode(x) local stat,res = pcall(function() return json.decode(x) end) return stat and res end

  function self.HC3call(method,call,data,cType)
    if hc3.offline then return nil,400 end
    if _debugFlags.api then Log(LOG.SYS,"api.%s - %s",method,call) end
    -- Special case, url encode arguments
    if call:match("/devices/%?.+") then call=urlencode(call) end
    local resp = {}
    local req={ method=method, timeout = 5000, -- ToDo: Replace with configurable constant
      url = "http://"..hc3.credentials.ip.."/api"..call, --urlencode(call),
      sink = ltn12.sink.table(resp),
      user=hc3.credentials.user,
      password=hc3.credentials.pwd,
      headers={}
    }
    if (method == "POST" or method=="PUT") and data == nil then data =  "[]" end
    req.headers["Accept"] = '*/*'
    req.headers["X-Fibaro-Version"] = 2
    req.headers["Fibaro-User-PIN"] = hc3.USERPIN -- UserPIN needed for alarms devices etc.
    if data then
      req.headers["Content-Type"] = cType or "application/json"
      req.headers["content-length"] = #data
      req.source = ltn12.source.string(data)
    end
    local r, c, h
    if hc3.apiHTTPS then
      req.url = "https"..req.url:sub(5)
    end
    local ctx = getContext()
    --if ctx._ENVID then ctx.setTimeout(function() end,250) end
    r,c,h = copas.http.request(req)
    if not r then
      Log(LOG.ERROR,"Error connnecting to HC3: '%s' - URL: '%s'.",c,req.url)
      return nil,c, h
    end
    if c>=200 and c<300 then
      return resp[1] and safeDecode(table.concat(resp)) or nil,c
    end
    if _debugFlags.api then Log(LOG.ERROR,"HC3 returned error '%d %s' - URL: '%s'.",c,resp[1] or "",req.url) end
    return nil,c, h
  end

  self.net = net
  self.mqtt = mqtt
  return self
end--module HTTP

-------------- Timer support -------------------------
function module.Timer(hc3)
  local self = {}
  local Util = hc3.module.Util
  local _debugFlags = hc3.debug
  local copas,timer,timerwheel2,lock
  local binaryheap
  Log,LOG,json,api,net,assert,assertf=Log,LOG,json,api,net,assert,assertf

  local socket = require("socket")
  local url = require("socket.url")
  local ltn12 = require("ltn12")
  local mime = require("mime")
  local string = require("string")
  local headers = require("socket.headers")

  ------- Timer wheel --------------
  do
    local default_now  -- return time in seconds
    if _G['ngx'] then -- no problem, main thread
      default_now = _G['ngx'].now
    else
      local ok, socket = pcall(require, "socket")
      if ok then
        default_now = socket.gettime
      else
        default_now = nil -- we don't have a default
      end
    end

    new_tab = function(narr, nrec) return {} end

    local xpcall = xpcall --pcall(function() return require("coxpcall").xpcall end) or xpcall
    local default_err_handler = function(err)
      io.stderr:write(debug.traceback("TimerWheel callback failed with: " .. tostring(err)))
    end

    local math_floor = math.floor
    local math_huge = math.huge
    local EMPTY = {}

    local _M = {}

    function _M.new(opts)
      assert(opts ~= _M, "new should not be called with colon ':' notation")

      opts = opts or EMPTY
      assert(type(opts) == "table", "expected options to be a table")

      local precision = opts.precision or 0.050  -- in seconds, 50ms by default
      local ringsize  = opts.ringsize or 72000   -- #slots per ring, default 1 hour = 60 * 60 / 0.050
      local now       = opts.now or default_now  -- function to get time in seconds
      local err_handler = opts.err_handler or default_err_handler
      opts = nil   -- luacheck: ignore

      assert(type(precision) == "number" and precision > 0,
        "expected 'precision' to be number > 0")
      assert(type(ringsize) == "number" and ringsize > 0 and math_floor(ringsize) == ringsize,
        "expected 'ringsize' to be an integer number > 0")
      assert(type(now) == "function",
        "expected 'now' to be a function, got: " .. type(now))
      assert(type(err_handler) == "function",
        "expected 'err_handler' to be a function, got: " .. type(err_handler))

      local start     = now()
      local position  = 1  -- position next up in first ring of timer wheel
      local id_count  = 0  -- counter to generate unique ids (all negative)
      local id_list   = {} -- reverse lookup table to find timers by id
      local rings     = {} -- list of rings, index 1 is the current ring
      local rings_n   = 0  -- the number of the last ring in the rings list
      local count     = 0  -- how many timers do we have
      local wheel     = {} -- the returned wheel object
      -- because we assume hefty setting and cancelling, we're reusing tables
      -- to prevent excessive GC.
      local tables    = {} -- list of tables to be reused
      local tables_n  = 0  -- number of tables in the list
      --- Checks and executes timers.
      -- Call this function (at least) every `precision` seconds.
      -- @return `true`
      function wheel:step()
        local new_position = math_floor((now() - start) / precision) + 1
        local ring = rings[1] or EMPTY

        while position < new_position do
          -- get the expired slot, and remove it from the ring
          local slot = ring[position]
          ring[position] = nil
          -- forward pointers
          position = position + 1
          if position > ringsize then
            -- current ring is done, remove it and forward pointers
            for i = 1, rings_n do
              -- manual loop, since table.remove won't deal with holes
              rings[i] = rings[i + 1]
            end
            rings_n = rings_n - 1

            ring = rings[1] or EMPTY
            start = start + ringsize * precision
            position = 1
            new_position = new_position - ringsize
          end
          -- only deal with slot after forwarding pointers, to make sure that
          -- any cb inserting another timer, does not end up in the slot being
          -- handled
          if slot then
            -- deal with the slot
            local ids = slot.ids
            local args = slot.arg
            for i = 1, slot.n do
              local id  = slot[i];  slot[i]  = nil; slot[id] = nil
              local cb  = ids[id];  ids[id]  = nil
              local arg = args[id]; args[id] = nil
              id_list[id] = nil
              count = count - 1
              xpcall(cb, err_handler, arg)
            end

            slot.n = 0
            -- delete the slot
            tables_n = tables_n + 1
            tables[tables_n] = slot
          end

        end
        return true
      end

      --- Gets the number of timers.
      -- @return number of timers
      function wheel:count()
        return count
      end

      function wheel:set(expire_in, cb, arg)
        local time_expire = now() + expire_in
        local pos = math_floor((time_expire - start) / precision) + 1
        if pos < position then
          -- we cannot set it in the past
          pos = position
        end
        local ring_idx = math_floor((pos - 1) / ringsize) + 1
        local slot_idx = pos - (ring_idx - 1) * ringsize

        -- fetch actual ring table
        local ring = rings[ring_idx]
        if not ring then
          ring = new_tab(ringsize, 0)
          rings[ring_idx] = ring
          if ring_idx > rings_n then
            rings_n = ring_idx
          end
        end

        -- fetch actual slot
        local slot = ring[slot_idx]
        if not slot then
          if tables_n == 0 then
            slot = { n = 0, ids = {}, arg = {} }
          else
            slot = tables[tables_n]
            tables_n = tables_n - 1
          end
          ring[slot_idx] = slot
        end

        -- get new id
        local id = id_count - 1 -- use negative idx to not interfere with array part
        id_count = id

        -- store timer
        -- if we do not do this check, it will go unnoticed and lead to very
        -- hard to find bugs (`count` will go out of sync)
        slot.ids[id] = cb or error("the callback parameter is required", 2)
        slot.arg[id] = arg
        local idx = slot.n + 1
        slot.n = idx
        slot[idx] = id
        slot[id] = idx
        id_list[id] = slot
        count = count + 1

        return id
      end

      function wheel:cancel(id)
        local slot = id_list[id]
        if slot then
          local idx = slot[id]
          slot[id] = nil
          slot.ids[id] = nil
          slot.arg[id] = nil
          local n = slot.n
          slot[idx] = slot[n]
          slot[n] = nil
          slot.n = n - 1
          id_list[id] = nil
          count = count - 1
          return true
        end
        return false
      end

      function wheel:peek(max_ahead)
        if count == 0 then
          return nil
        end
        local time_now = now()

        -- convert max_ahead from seconds to positions
        if max_ahead then
          max_ahead = math_floor((time_now + max_ahead - start) / precision)
        else
          max_ahead = math_huge
        end

        local position_idx = position
        local ring_idx = 1
        local ring = rings[ring_idx] or EMPTY -- TODO: if EMPTY then we can skip it?
        local ahead_count = 0
        while ahead_count < max_ahead do

          local slot = ring[position_idx]
          if slot then
            if slot[1] then
              -- we have a timer
              return ((ring_idx - 1) * ringsize + position_idx) * precision +
              start - time_now
            end
          end

          -- there is nothing in this position
          position_idx = position_idx + 1
          ahead_count = ahead_count + 1
          if position_idx > ringsize then
            position_idx = 1
            ring_idx = ring_idx + 1
            ring = rings[ring_idx] or EMPTY
          end
        end
        return nil
      end
      return wheel
    end

    timerwheel2 = _M
  end

--------- Binary heap ----------
  do

    local M = {}
    local floor = math.floor

    M.binaryHeap = function(swap, erase, lt)

      local heap = {
        values = {},  -- list containing values
        erase = erase,
        swap = swap,
        lt = lt,
      }

      function heap:bubbleUp(pos)
        local values = self.values
        while pos>1 do
          local parent = floor(pos/2)
          if not lt(values[pos], values[parent]) then
            break
          end
          swap(self, parent, pos)
          pos = parent
        end
      end

      function heap:sinkDown(pos)
        local values = self.values
        local last = #values
        while true do
          local min = pos
          local child = 2 * pos

          for c = child, child + 1 do
            if c <= last and lt(values[c], values[min]) then min = c end
          end

          if min == pos then break end

          swap(self, pos, min)
          pos = min
        end
      end

      return heap
    end

    local update
--- Updates the value of an element in the heap.
-- @function heap:update
-- @param pos the position which value to update
-- @param newValue the new value to use for this payload
    update = function(self, pos, newValue)
      assert(newValue ~= nil, "cannot add 'nil' as value")
      assert(pos >= 1 and pos <= #self.values, "illegal position")
      self.values[pos] = newValue
      if pos > 1 then self:bubbleUp(pos) end
      if pos < #self.values then self:sinkDown(pos) end
    end

    local remove
--- Removes an element from the heap.
-- @function heap:remove
-- @param pos the position to remove
-- @return value, or nil if a bad `pos` value was provided
    remove = function(self, pos)
      local last = #self.values
      if pos < 1 then
        return  -- bad pos

      elseif pos < last then
        local v = self.values[pos]
        self:swap(pos, last)
        self:erase(last)
        self:bubbleUp(pos)
        self:sinkDown(pos)
        return v

      elseif pos == last then
        local v = self.values[pos]
        self:erase(last)
        return v

      else
        return  -- bad pos: pos > last
      end
    end

    local insert
--- Inserts an element in the heap.
-- @function heap:insert
-- @param value the value used for sorting this element
-- @return nothing, or throws an error on bad input
    insert = function(self, value)
      assert(value ~= nil, "cannot add 'nil' as value")
      local pos = #self.values + 1
      self.values[pos] = value
      self:bubbleUp(pos)
    end

    local pop
--- Removes the top of the heap and returns it.
-- @function heap:pop
-- @return value at the top, or `nil` if there is none
    pop = function(self)
      if self.values[1] ~= nil then
        return remove(self, 1)
      end
    end

    local peek
--- Returns the element at the top of the heap, without removing it.
-- @function heap:peek
-- @return value at the top, or `nil` if there is none
    peek = function(self)
      return self.values[1]
    end

    local size
--- Returns the number of elements in the heap.
-- @function heap:size
-- @return number of elements
    size = function(self)
      return #self.values
    end

    local function swap(heap, a, b)
      heap.values[a], heap.values[b] = heap.values[b], heap.values[a]
    end

    local function erase(heap, pos)
      heap.values[pos] = nil
    end

    do end -- luacheck: ignore
-- the above is to trick ldoc (otherwise `update` below disappears)

    local updateU
    function updateU(self, payload, newValue)
      return update(self, self.reverse[payload], newValue)
    end

    local insertU
    function insertU(self, value, payload)
      assert(self.reverse[payload] == nil, "duplicate payload")
      local pos = #self.values + 1
      self.reverse[payload] = pos
      self.payloads[pos] = payload
      return insert(self, value)
    end

    local removeU
    function removeU(self, payload)
      local pos = self.reverse[payload]
      if pos ~= nil then
        return remove(self, pos), payload
      end
    end

    local popU
    function popU(self)
      if self.values[1] then
        local payload = self.payloads[1]
        local value = remove(self, 1)
        return payload, value
      end
    end

    local peekU
    peekU = function(self)
      return self.payloads[1], self.values[1]
    end

    local peekValueU
    peekValueU = function(self)
      return self.values[1]
    end

    local valueByPayload
    valueByPayload = function(self, payload)
      return self.values[self.reverse[payload]]
    end

    local sizeU
    sizeU = function(self)
      return #self.values
    end

    local function swapU(heap, a, b)
      local pla, plb = heap.payloads[a], heap.payloads[b]
      heap.reverse[pla], heap.reverse[plb] = b, a
      heap.payloads[a], heap.payloads[b] = plb, pla
      swap(heap, a, b)
    end

    local function eraseU(heap, pos)
      local payload = heap.payloads[pos]
      heap.reverse[payload] = nil
      heap.payloads[pos] = nil
      erase(heap, pos)
    end

--================================================================
-- unique heap creation
--================================================================

    local function uniqueHeap(lt)
      local h = M.binaryHeap(swapU, eraseU, lt)
      h.payloads = {}  -- list contains payloads
      h.reverse = {}  -- reverse of the payloads list
      h.peek = peekU
      h.peekValue = peekValueU
      h.valueByPayload = valueByPayload
      h.pop = popU
      h.size = sizeU
      h.remove = removeU
      h.insert = insertU
      h.update = updateU
      return h
    end

    M.minUnique = function(lt)
      if not lt then
        lt = function(a,b) return (a < b) end
      end
      return uniqueHeap(lt)
    end

    binaryheap = M
  end

--------- Copas ------------------
  do
    local gettime = socket.gettime
    local ssl -- only loaded upon demand

    local WATCH_DOG_TIMEOUT = 120
    local UDP_DATAGRAM_MAX = 8192  -- TODO: dynamically get this value from LuaSocket
    local TIMEOUT_PRECISION = 0.1  -- 100ms
    local fnil = function() end

    local pcall = pcall

-- Redefines LuaSocket functions with coroutine safe versions
-- (this allows the use of socket.http from within copas)
    local function statusHandler(status, ...)
      if status then return ... end
      local err = (...)
      if type(err) == "table" then
        return nil, err[1]
      else
        error(err)
      end
    end

    function socket.protect(func)
      return function (...)
        return statusHandler(pcall(func, ...))
      end
    end

    function socket.newtry(finalizer)
      return function (...)
        local status = (...)
        if not status then
          pcall(finalizer, select(2, ...))
          error({ (select(2, ...)) }, 0)
        end
        return ...
      end
    end

    copas = {}

-- Meta information is public even if beginning with an "_"
    copas._COPYRIGHT   = "Copyright (C) 2005-2017 Kepler Project"
    copas._DESCRIPTION = "Coroutine Oriented Portable Asynchronous Services"
    copas._VERSION     = "Copas 2.0.2"

-- Close the socket associated with the current connection after the handler finishes
    copas.autoclose = true

-- indicator for the loop running
    copas.running = false
-------------------------------------------------------------------------------
-- Simple set implementation
-- adds a FIFO queue for each socket in the set
-------------------------------------------------------------------------------

    local function newsocketset()
      local set = {}

      do  -- set implementation
        local reverse = {}

        -- Adds a socket to the set, does nothing if it exists
        function set:insert(skt)
          if not reverse[skt] then
            self[#self + 1] = skt
            reverse[skt] = #self
          end
        end

        -- Removes socket from the set, does nothing if not found
        function set:remove(skt)
          local index = reverse[skt]
          if index then
            reverse[skt] = nil
            local top = self[#self]
            self[#self] = nil
            if top ~= skt then
              reverse[top] = index
              self[index] = top
            end
          end
        end
      end

      do  -- queues implementation
        local fifo_queues = setmetatable({},{
            __mode = "k",                 -- auto collect queue if socket is gone
            __index = function(self, skt) -- auto create fifo queue if not found
              local newfifo = {}
              self[skt] = newfifo
              return newfifo
            end,
          })

        -- pushes an item in the fifo queue for the socket.
        function set:push(skt, itm)
          local queue = fifo_queues[skt]
          queue[#queue + 1] = itm
        end

        -- pops an item from the fifo queue for the socket
        function set:pop(skt)
          local queue = fifo_queues[skt]
          return table.remove(queue, 1)
        end
      end
      return set
    end

-- Threads immediately resumable
    local _resumable = {} do
      local resumelist = {}

      function _resumable:push(co)
        resumelist[#resumelist + 1] = co
      end

      function _resumable:clear_resumelist()
        local lst = resumelist
        resumelist = {}
        return lst
      end
      function _resumable:done()
        return resumelist[1] == nil
      end
    end

-- Similar to the socket set above, but tailored for the use of
-- sleeping threads
    local _sleeping = {} do

      local heap = binaryheap.minUnique()
      local lethargy = setmetatable({}, { __mode = "k" }) -- list of coroutines sleeping without a wakeup time
      -- Required base implementation
      -----------------------------------------
      _sleeping.insert = fnil
      _sleeping.remove = fnil

      -- push a new timer on the heap
      function _sleeping:push(sleeptime, co)
        if sleeptime < 0 then
          lethargy[co] = true
        elseif sleeptime == 0 then
          _resumable:push(co)
        else
          heap:insert(gettime() + sleeptime, co)
        end
      end

      -- find the thread that should wake up to the time, if any
      function _sleeping:pop(time)
        if time < (heap:peekValue() or math.huge) then
          return
        end
        return heap:pop()
      end

      -- additional methods for time management
      -----------------------------------------
      function _sleeping:getnext()  -- returns delay until next sleep expires, or nil if there is none
        local t = heap:peekValue()
        if t then
          -- never report less than 0, because select() might block
          return math.max(t - gettime(), 0)
        end
      end

      function _sleeping:wakeup(co)
        if lethargy[co] then
          lethargy[co] = nil
          _resumable:push(co)
          return
        end
        if heap:remove(co) then
          _resumable:push(co)
        end
      end

      -- @param tos number of timeouts running
      function _sleeping:done(tos)
        -- return true if we have nothing more to do
        -- the timeout task doesn't qualify as work (fallbacks only),
        -- the lethargy also doesn't qualify as work ('dead' tasks),
        -- but the combination of a timeout + a lethargy can be work
        return heap:size() == 1       -- 1 means only the timeout-timer task is running
        and not (tos > 0 and next(lethargy))
      end

    end   -- _sleeping

-------------------------------------------------------------------------------
-- Tracking coroutines and sockets
-------------------------------------------------------------------------------

    local _servers = newsocketset() -- servers being handled
    local _threads = setmetatable({}, {__mode = "k"})  -- registered threads added with addthread()
    local _canceled = setmetatable({}, {__mode = "k"}) -- threads that are canceled and pending removal

-- for each socket we log the last read and last write times to enable the
-- watchdog to follow up if it takes too long.
-- tables contain the time, indexed by the socket
    local _reading_log = {}
    local _writing_log = {}

    local _reading = newsocketset() -- sockets currently being read
    local _writing = newsocketset() -- sockets currently being written
    local _isSocketTimeout = { -- set of errors indicating a socket-timeout
      ["timeout"] = true,      -- default LuaSocket timeout
      ["wantread"] = true,     -- LuaSec specific timeout
      ["wantwrite"] = true,    -- LuaSec specific timeout
    }

-------------------------------------------------------------------------------
-- Coroutine based socket timeouts.
-------------------------------------------------------------------------------
    local usertimeouts = setmetatable({}, {
        __mode = "k",
        __index = function(self, skt)
          -- if there is no timeout found, we insert one automatically,
          -- a 10 year timeout as substitute for the default "blocking" should do
          self[skt] = 10*365*24*60*60
          return self[skt]
        end,
      })

    local useSocketTimeoutErrors = setmetatable({},{ __mode = "k" })

-- sto = socket-time-out
    local sto_timeout, sto_timed_out, sto_change_queue, sto_error do

      local socket_register = setmetatable({}, { __mode = "k" })    -- socket by coroutine
      local operation_register = setmetatable({}, { __mode = "k" }) -- operation "read"/"write" by coroutine
      local timeout_flags = setmetatable({}, { __mode = "k" })      -- true if timedout, by coroutine


      local function socket_callback(co)
        local skt = socket_register[co]
        local queue = operation_register[co]

        -- flag the timeout and resume the coroutine
        timeout_flags[co] = true
        _resumable:push(co)

        -- clear the socket from the current queue
        if queue == "read" then
          _reading:remove(skt)
        elseif queue == "write" then
          _writing:remove(skt)
        else
          error("bad queue name; expected 'read'/'write', got: "..tostring(queue))
        end
      end

      -- Sets a socket timeout.
      -- Calling it as `sto_timeout()` will cancel the timeout.
      -- @param queue (string) the queue the socket is currently in, must be either "read" or "write"
      -- @param skt (socket) the socket on which to operate
      -- @return true
      function sto_timeout(skt, queue)
        local co = coroutine.running()
        socket_register[co] = skt
        operation_register[co] = queue
        timeout_flags[co] = nil
        if skt then
          copas.timeout(usertimeouts[skt], socket_callback)
        else
          copas.timeout(0)
        end
        return true
      end

      -- Changes the timeout to a different queue (read/write).
      -- Only usefull with ssl-handshakes and "wantread", "wantwrite" errors, when
      -- the queue has to be changed, so the timeout handler knows where to find the socket.
      -- @param queue (string) the new queue the socket is in, must be either "read" or "write"
      -- @return true
      function sto_change_queue(queue)
        operation_register[coroutine.running()] = queue
        return true
      end

      -- Responds with `true` if the operation timed-out.
      function sto_timed_out()
        return timeout_flags[coroutine.running()]
      end

      -- Returns the poroper timeout error
      function sto_error(err)
        return useSocketTimeoutErrors[coroutine.running()] and err or "timeout"
      end
    end
-------------------------------------------------------------------------------
-- Coroutine based socket I/O functions.
-------------------------------------------------------------------------------

    local function isTCP(socket)
      return string.sub(tostring(socket),1,3) ~= "udp"
    end

    function copas.settimeout(skt, timeout)
      if timeout ~= nil and type(timeout) ~= "number" then
        return nil, "timeout must be a 'nil' or a number"
      end

      if timeout and timeout < 0 then
        timeout = nil    -- negative is same as nil; blocking indefinitely
      end

      usertimeouts[skt] = timeout
      return true
    end

-- reads a pattern from a client and yields to the reading set on timeouts
-- UDP: a UDP socket expects a second argument to be a number, so it MUST
-- be provided as the 'pattern' below defaults to a string. Will throw a
-- 'bad argument' error if omitted.
    function copas.receive(client, pattern, part)
      local s, err
      pattern = pattern or "*l"
      local current_log = _reading_log
      sto_timeout(client, "read")

      repeat
        s, err, part = client:receive(pattern, part)

        if s then
          current_log[client] = nil
          sto_timeout()
          return s, err, part

        elseif not _isSocketTimeout[err] then
          current_log[client] = nil
          sto_timeout()
          return s, err, part

        elseif sto_timed_out() then
          current_log[client] = nil
          return nil, sto_error(err)
        end

        if err == "wantwrite" then -- wantwrite may be returned during SSL renegotiations
          current_log = _writing_log
          current_log[client] = gettime()
          sto_change_queue("write")
          coroutine.yield(client, _writing)
        else
          current_log = _reading_log
          current_log[client] = gettime()
          sto_change_queue("read")
          coroutine.yield(client, _reading)
        end
      until false
    end

-- receives data from a client over UDP. Not available for TCP.
-- (this is a copy of receive() method, adapted for receivefrom() use)
    function copas.receivefrom(client, size)
      local s, err, port
      size = size or UDP_DATAGRAM_MAX
      sto_timeout(client, "read")

      repeat
        s, err, port = client:receivefrom(size) -- upon success err holds ip address

        if s then
          _reading_log[client] = nil
          sto_timeout()
          return s, err, port

        elseif err ~= "timeout" then
          _reading_log[client] = nil
          sto_timeout()
          return s, err, port

        elseif sto_timed_out() then
          _reading_log[client] = nil
          return nil, sto_error(err)
        end

        _reading_log[client] = gettime()
        coroutine.yield(client, _reading)
      until false
    end

-- same as above but with special treatment when reading chunks,
-- unblocks on any data received.
    function copas.receivePartial(client, pattern, part)
      local s, err
      pattern = pattern or "*l"
      local current_log = _reading_log
      sto_timeout(client, "read")

      repeat
        s, err, part = client:receive(pattern, part)

        if s or (type(pattern) == "number" and part ~= "" and part ~= nil) then
          current_log[client] = nil
          sto_timeout()
          return s, err, part

        elseif not _isSocketTimeout[err] then
          current_log[client] = nil
          sto_timeout()
          return s, err, part

        elseif sto_timed_out() then
          current_log[client] = nil
          return nil, sto_error(err)
        end

        if err == "wantwrite" then
          current_log = _writing_log
          current_log[client] = gettime()
          sto_change_queue("write")
          coroutine.yield(client, _writing)
        else
          current_log = _reading_log
          current_log[client] = gettime()
          sto_change_queue("read")
          coroutine.yield(client, _reading)
        end
      until false
    end

-- sends data to a client. The operation is buffered and
-- yields to the writing set on timeouts
-- Note: from and to parameters will be ignored by/for UDP sockets
    function copas.send(client, data, from, to)
      local s, err
      from = from or 1
      local lastIndex = from - 1
      local current_log = _writing_log
      sto_timeout(client, "write")

      repeat
        s, err, lastIndex = client:send(data, lastIndex + 1, to)

        -- adds extra coroutine swap
        -- garantees that high throughput doesn't take other threads to starvation
        if (math.random(100) > 90) then
          current_log[client] = gettime()   -- TODO: how to handle this??
          if current_log == _writing_log then
            coroutine.yield(client, _writing)
          else
            coroutine.yield(client, _reading)
          end
        end

        if s then
          current_log[client] = nil
          sto_timeout()
          return s, err, lastIndex

        elseif not _isSocketTimeout[err] then
          current_log[client] = nil
          sto_timeout()
          return s, err, lastIndex

        elseif sto_timed_out() then
          current_log[client] = nil
          return nil, sto_error(err)
        end

        if err == "wantread" then
          current_log = _reading_log
          current_log[client] = gettime()
          sto_change_queue("read")
          coroutine.yield(client, _reading)
        else
          current_log = _writing_log
          current_log[client] = gettime()
          sto_change_queue("write")
          coroutine.yield(client, _writing)
        end
      until false
    end

    function copas.sendto(client, data, ip, port)
      -- deprecated; for backward compatibility only, since UDP doesn't block on sending
      return client:sendto(data, ip, port)
    end

-- waits until connection is completed
    function copas.connect(skt, host, port)
      skt:settimeout(0)
      local ret, err, tried_more_than_once
      sto_timeout(skt, "write")

      repeat
        ret, err = skt:connect(host, port)

        -- non-blocking connect on Windows results in error "Operation already
        -- in progress" to indicate that it is completing the request async. So essentially
        -- it is the same as "timeout"
        if ret or (err ~= "timeout" and err ~= "Operation already in progress") then
          _writing_log[skt] = nil
          sto_timeout()
          -- Once the async connect completes, Windows returns the error "already connected"
          -- to indicate it is done, so that error should be ignored. Except when it is the
          -- first call to connect, then it was already connected to something else and the
          -- error should be returned
          if (not ret) and (err == "already connected" and tried_more_than_once) then
            return 1
          end
          return ret, err

        elseif sto_timed_out() then
          _writing_log[skt] = nil
          return nil, sto_error(err)
        end

        tried_more_than_once = tried_more_than_once or true
        _writing_log[skt] = gettime()
        coroutine.yield(skt, _writing)
      until false
    end
---
-- Peforms an (async) ssl handshake on a connected TCP client socket.
-- NOTE: replace all previous socket references, with the returned new ssl wrapped socket
-- Throws error and does not return nil+error, as that might silently fail
-- in code like this;
--   copas.addserver(s1, function(skt)
--       skt = copas.wrap(skt, sparams)
--       skt:dohandshake()   --> without explicit error checking, this fails silently and
--       skt:send(body)      --> continues unencrypted
-- @param skt Regular LuaSocket CLIENT socket object
-- @param sslt Table with ssl parameters
-- @return wrapped ssl socket, or throws an error
    function copas.dohandshake(skt, sslt)
      ssl = ssl or require("ssl")
      local nskt, err = ssl.wrap(skt, sslt)
      if not nskt then return error(err) end
      local queue
      nskt:settimeout(0)  -- non-blocking on the ssl-socket
      copas.settimeout(nskt, usertimeouts[skt]) -- copy copas user-timeout to newly wrapped one
      sto_timeout(nskt, "write")

      repeat
        local success, err = nskt:dohandshake()

        if success then
          sto_timeout()
          return nskt

        elseif not _isSocketTimeout[err] then
          sto_timeout()
          return error(err)

        elseif sto_timed_out() then
          return nil, sto_error(err)

        elseif err == "wantwrite" then
          sto_change_queue("write")
          queue = _writing

        elseif err == "wantread" then
          sto_change_queue("read")
          queue = _reading

        else
          error(err)
        end

        coroutine.yield(nskt, queue)
      until false
    end

-- flushes a client write buffer (deprecated)
    function copas.flush()
    end

-- wraps a TCP socket to use Copas methods (send, receive, flush and settimeout)
    local _skt_mt_tcp = {
      __tostring = function(self)
        return tostring(self.socket).." (copas wrapped)"
      end,
      __index = {

        send = function (self, data, from, to)
          return copas.send (self.socket, data, from, to)
        end,

        receive = function (self, pattern, prefix)
          if usertimeouts[self.socket] == 0 then
            return copas.receivePartial(self.socket, pattern, prefix)
          end
          return copas.receive(self.socket, pattern, prefix)
        end,

        flush = function (self)
          return copas.flush(self.socket)
        end,

        settimeout = function (self, time)
          return copas.settimeout(self.socket, time)
        end,

        -- TODO: socket.connect is a shortcut, and must be provided with an alternative
        -- if ssl parameters are available, it will also include a handshake
        connect = function(self, ...)
          local res, err = copas.connect(self.socket, ...)
          if res and self.ssl_params then
            res, err = self:dohandshake()
          end
          return res, err
        end,

        close = function(self, ...) return self.socket:close(...) end,

        -- TODO: socket.bind is a shortcut, and must be provided with an alternative
        bind = function(self, ...) return self.socket:bind(...) end,
        -- TODO: is this DNS related? hence blocking?
        getsockname = function(self, ...) return self.socket:getsockname(...) end,
        getstats = function(self, ...) return self.socket:getstats(...) end,
        setstats = function(self, ...) return self.socket:setstats(...) end,
        listen = function(self, ...) return self.socket:listen(...) end,
        accept = function(self, ...) return self.socket:accept(...) end,
        setoption = function(self, ...) return self.socket:setoption(...) end,
        -- TODO: is this DNS related? hence blocking?
        getpeername = function(self, ...) return self.socket:getpeername(...) end,
        shutdown = function(self, ...) return self.socket:shutdown(...) end,
        dohandshake = function(self, sslt)
          self.ssl_params = sslt or self.ssl_params
          local nskt, err = copas.dohandshake(self.socket, self.ssl_params)
          if not nskt then return nskt, err end
          self.socket = nskt  -- replace internal socket with the newly wrapped ssl one
          return self
        end,

      }}

-- wraps a UDP socket, copy of TCP one adapted for UDP.
    local _skt_mt_udp = {__index = { }}
    for k,v in pairs(_skt_mt_tcp) do _skt_mt_udp[k] = _skt_mt_udp[k] or v end
    for k,v in pairs(_skt_mt_tcp.__index) do _skt_mt_udp.__index[k] = v end

    _skt_mt_udp.__index.send        = function(self, ...) return self.socket:send(...) end

    _skt_mt_udp.__index.sendto      = function(self, ...) return self.socket:sendto(...) end

    _skt_mt_udp.__index.receive =     function (self, size)
      return copas.receive (self.socket, (size or UDP_DATAGRAM_MAX))
    end

    _skt_mt_udp.__index.receivefrom = function (self, size)
      return copas.receivefrom (self.socket, (size or UDP_DATAGRAM_MAX))
    end

    -- TODO: is this DNS related? hence blocking?
    _skt_mt_udp.__index.setpeername = function(self, ...) return self.socket:setpeername(...) end

    _skt_mt_udp.__index.setsockname = function(self, ...) return self.socket:setsockname(...) end

    -- do not close client, as it is also the server for udp.
    _skt_mt_udp.__index.close       = function(self, ...) return true end
---
-- Wraps a LuaSocket socket object in an async Copas based socket object.
-- @param skt The socket to wrap
-- @sslt (optional) Table with ssl parameters, use an empty table to use ssl with defaults
-- @return wrapped socket object
    function copas.wrap (skt, sslt)
      if (getmetatable(skt) == _skt_mt_tcp) or (getmetatable(skt) == _skt_mt_udp) then
        return skt -- already wrapped
      end
      skt:settimeout(0)
      if not isTCP(skt) then
        return  setmetatable ({socket = skt}, _skt_mt_udp)
      else
        return  setmetatable ({socket = skt, ssl_params = sslt}, _skt_mt_tcp)
      end
    end

--- Wraps a handler in a function that deals with wrapping the socket and doing the
-- optional ssl handshake.
    function copas.handler(handler, sslparams)
      -- TODO: pass a timeout value to set, and use during handshake
      return function (skt, ...)
        skt = copas.wrap(skt)
        if sslparams then skt:dohandshake(sslparams) end
        return handler(skt, ...)
      end
    end

--------------------------------------------------
-- Error handling
--------------------------------------------------
    local _errhandlers = setmetatable({}, { __mode = "k" })   -- error handler per coroutine

    local function _deferror(msg, co, skt)
      msg = ("%s (coroutine: %s, socket: %s)"):format(tostring(msg), tostring(co), tostring(skt))
      if type(co) == "thread" then
        -- regular Copas coroutine
        msg = debug.traceback(co, msg)
      else
        -- not a coroutine, but the main thread, this happens if a timeout callback
        -- (see `copas.timeout` causes an error (those callbacks run on the main thread).
        msg = debug.traceback(msg, 2)
      end
      print(msg)
    end

    function copas.setErrorHandler (err, default)
      if default then
        _deferror = err
      else
        _errhandlers[coroutine.running()] = err
      end
    end

-- if `bool` is truthy, then the original socket errors will be returned in case of timeouts;
-- `timeout, wantread, wantwrite, Operation already in progress`. If falsy, it will always
-- return `timeout`.
    function copas.useSocketTimeoutErrors(bool)
      useSocketTimeoutErrors[coroutine.running()] = not not bool -- force to a boolean
    end

-------------------------------------------------------------------------------
-- Thread handling
-------------------------------------------------------------------------------

    local function _doTick (co, skt, ...)
      if not co then return end
      -- if a coroutine was canceled/removed, don't resume it
      if _canceled[co] then
        _canceled[co] = nil -- also clean up the registry
        _threads[co] = nil
        return
      end

      local ok, res, new_q = coroutine.resume(co, skt, ...) 

      if ok and res and new_q then
        new_q:insert (res)
        new_q:push (res, co)
      else
        if not ok then pcall (_errhandlers [co] or _deferror, res, co, skt) end
        if skt and copas.autoclose and isTCP(skt) then
          skt:close() -- do not auto-close UDP sockets, as the handler socket is also the server socket
        end
        _errhandlers [co] = nil
      end
    end

-- accepts a connection on socket input
    local function _accept(server_skt, handler)
      local client_skt = server_skt:accept()
      if client_skt then
        client_skt:settimeout(0)
        local co = coroutine.create(handler)
        _doTick(co, client_skt)
      end
    end
-------------------------------------------------------------------------------
-- Adds a server/handler pair to Copas dispatcher
-------------------------------------------------------------------------------
    do
      local function addTCPserver(server, handler, timeout)
        server:settimeout(timeout or 0)
        _servers[server] = handler
        _reading:insert(server)
      end

      local function addUDPserver(server, handler, timeout)
        server:settimeout(timeout or 0)
        local co = coroutine.create(handler)
        _reading:insert(server)
        _doTick(co, server)
      end

      function copas.addserver(server, handler, timeout)
        if isTCP(server) then
          addTCPserver(server, handler, timeout)
        else
          addUDPserver(server, handler, timeout)
        end
      end
    end

    function copas.removeserver(server, keep_open)
      local skt = server
      local mt = getmetatable(server)
      if mt == _skt_mt_tcp or mt == _skt_mt_udp then
        skt = server.socket
      end
      _servers:remove(skt)
      _reading:remove(skt)
      if keep_open then
        return true
      end
      return server:close()
    end

-------------------------------------------------------------------------------
-- Adds an new coroutine thread to Copas dispatcher
-------------------------------------------------------------------------------
    function copas.addthread(handler, ...)
      -- create a coroutine that skips the first argument, which is always the socket
      -- passed by the scheduler, but `nil` in case of a task/thread
      local thread = coroutine.create(function(_, ...) return handler(...) end)
      _threads[thread] = true -- register this thread so it can be removed
      _doTick (thread, nil, ...)
      return thread
    end

    function copas.removethread(thread)
      -- if the specified coroutine is registered, add it to the canceled table so
      -- that next time it tries to resume it exits.
      _canceled[thread] = _threads[thread or 0]
    end
-------------------------------------------------------------------------------
-- Sleep/pause management functions
-------------------------------------------------------------------------------
-- yields the current coroutine and wakes it after 'sleeptime' seconds.
-- If sleeptime < 0 then it sleeps until explicitly woken up using 'wakeup'
    function copas.sleep(sleeptime)
      coroutine.yield((sleeptime or 0), _sleeping)
    end

-- Wakes up a sleeping coroutine 'co'.
    function copas.wakeup(co)
      _sleeping:wakeup(co)
    end
-------------------------------------------------------------------------------
-- Timeout management
-------------------------------------------------------------------------------
    do
      local timeout_register = setmetatable({}, { __mode = "k" })
      local timerwheel = timerwheel2.new({
          precision = TIMEOUT_PRECISION,                -- timeout precision 100ms
          ringsize = math.floor(60/TIMEOUT_PRECISION),  -- ring size 1 minute
          err_handler = function(...) return _deferror(...) end,
        })

      copas.addthread(function()
          while true do
            copas.sleep(TIMEOUT_PRECISION)
            timerwheel:step()
          end
        end)

      -- get the number of timeouts running
      function copas.gettimeouts()
        return timerwheel:count()
      end

      function copas.timeout(delay, callback)
        local co = coroutine.running()
        local existing_timer = timeout_register[co]
        if existing_timer then
          timerwheel:cancel(existing_timer)
        end
        if delay > 0 then
          timeout_register[co] = timerwheel:set(delay, callback, co)
        else
          timeout_register[co] = nil
        end
        return true
      end
    end

    local _tasks = {} do function _tasks:add(tsk) _tasks[#_tasks + 1] = tsk end end

-- a task to check ready to read events
    local _readable_task = {} do

      local function tick(skt)
        local handler = _servers[skt]
        if handler then
          _accept(skt, handler)
        else
          _reading:remove(skt)
          _doTick(_reading:pop(skt), skt)
        end
      end
      function _readable_task:step()
        for _, skt in ipairs(self._evs) do
          tick(skt)
        end
      end
      _tasks:add(_readable_task)
    end

-- a task to check ready to write events
    local _writable_task = {} do

      local function tick(skt)
        _writing:remove(skt)
        _doTick(_writing:pop(skt), skt)
      end

      function _writable_task:step()
        for _, skt in ipairs(self._evs) do tick(skt) end
      end
      _tasks:add(_writable_task)
    end

-- sleeping threads task
    local _sleeping_task = {} do

      function _sleeping_task:step()
        local now = gettime()

        local co = _sleeping:pop(now)
        while co do
          -- we're pushing them to _resumable, since that list will be replaced before
          -- executing. This prevents tasks running twice in a row with sleep(0) for example.
          -- So here we won't execute, but at _resumable step which is next
          _resumable:push(co)
          co = _sleeping:pop(now)
        end
      end

      _tasks:add(_sleeping_task)
    end

-- resumable threads task
    local _resumable_task = {} do

      function _resumable_task:step()
        -- replace the resume list before iterating, so items placed in there
        -- will indeed end up in the next copas step, not in this one, and not
        -- create a loop
        local resumelist = _resumable:clear_resumelist()

        for _, co in ipairs(resumelist) do _doTick(co) end
      end

      _tasks:add(_resumable_task)
    end

-------------------------------------------------------------------------------
-- Checks for reads and writes on sockets
-------------------------------------------------------------------------------
    local _select do

      local last_cleansing = 0
      local duration = function(t2, t1) return t2-t1 end

      _select = function(timeout)
        local err
        local now = gettime()

        _readable_task._evs, _writable_task._evs, err = socket.select(_reading, _writing, timeout)
        local r_evs, w_evs = _readable_task._evs, _writable_task._evs

        if duration(now, last_cleansing) > WATCH_DOG_TIMEOUT then
          last_cleansing = now

          -- Check all sockets selected for reading, and check how long they have been waiting
          -- for data already, without select returning them as readable
          for skt,time in pairs(_reading_log) do
            if not r_evs[skt] and duration(now, time) > WATCH_DOG_TIMEOUT then
              -- This one timedout while waiting to become readable, so move
              -- it in the readable list and try and read anyway, despite not
              -- having been returned by select
              _reading_log[skt] = nil
              r_evs[#r_evs + 1] = skt
              r_evs[skt] = #r_evs
            end
          end

          -- Do the same for writing
          for skt,time in pairs(_writing_log) do
            if not w_evs[skt] and duration(now, time) > WATCH_DOG_TIMEOUT then
              _writing_log[skt] = nil
              w_evs[#w_evs + 1] = skt
              w_evs[skt] = #w_evs
            end
          end
        end

        if err == "timeout" and #r_evs + #w_evs > 0 then
          return nil
        else
          return err
        end
      end
    end
-------------------------------------------------------------------------------
-- Dispatcher loop step.
-- Listen to client requests and handles them
-- Returns false if no socket-data was handled, or true if there was data
-- handled (or nil + error message)
-------------------------------------------------------------------------------
    function copas.step(timeout)
      -- Need to wake up the select call in time for the next sleeping event
      if not _resumable:done() then
        timeout = 0
      else
        timeout = math.min(_sleeping:getnext(), timeout or math.huge)
      end
      local err = _select(timeout)
      for _, tsk in ipairs(_tasks) do
        tsk:step()
      end
      if err then
        if err == "timeout" then return false end
        return nil, err
      end
      return true
    end
-------------------------------------------------------------------------------
-- Check whether there is something to do.
-- returns false if there are no sockets for read/write nor tasks scheduled
-- (which means Copas is in an empty spin)
-------------------------------------------------------------------------------
    function copas.finished()
      return #_reading == 0 and #_writing == 0 and _resumable:done() and _sleeping:done(copas.gettimeouts())
    end
-------------------------------------------------------------------------------
-- Dispatcher endless loop.
-- Listen to client requests and handles them forever
-------------------------------------------------------------------------------
    function copas.loop(initializer, timeout)
      if type(initializer) == "function" then
        copas.addthread(initializer)
      else
        timeout = initializer or timeout
      end

      copas.running = true
      while not copas.finished() do copas.step(timeout) end
      copas.running = false
    end
  end
--------- Copas timer ---------
  do
    timer = {}
    timer.__index = timer

    do
      local function expire_func(self, initial_delay)
        copas.sleep(initial_delay)
        while true do
          if not self.cancelled then
            self:callback(self.params)
          end
          if (not self.recurring) or self.cancelled then
            -- clean up and exit the thread
            self.co = nil
            self.cancelled = true
            return
          end
          copas.sleep(self.delay)
        end
      end

      function timer:arm(initial_delay)
        assert(initial_delay == nil or initial_delay >= 0, "delay must be greater than or equal to 0")
        if self.co then return nil, "already armed" end
        self.cancelled = false
        self.co = copas.addthread(expire_func, self, initial_delay or self.delay)
        return self
      end
    end

    function timer:cancel()
      if not self.co then return nil, "not armed" end
      if self.cancelled then return nil, "already cancelled" end
      self.cancelled = true
      copas.wakeup(self.co)       -- resume asap
      copas.removethread(self.co) -- will immediately drop the thread upon resuming
      self.co = nil
      return self
    end

    function timer.new(opts)
      assert(opts.delay >= 0, "delay must be greater than or equal to 0")
      assert(type(opts.callback) == "function", "expected callback to be a function")
      return setmetatable({
          delay = opts.delay,
          callback = opts.callback,
          recurring = not not opts.recurring,
          params = opts.params,
          cancelled = false,
          }, timer):arm(opts.initial_delay)
    end
  end

--------- Copas HTTP support -------------------------
  do
    -----------------------------------------------------------------------------
-- Full copy of the LuaSocket code, modified to include
-- https and http/https redirects, and Copas async enabled.
-----------------------------------------------------------------------------
-- HTTP/1.1 client support for the Lua language.
-- LuaSocket toolkit.
-- Author: Diego Nehab
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Declare module and import dependencies
-------------------------------------------------------------------------------
    local base = _G
    --local table = require("table")
    local try = socket.try
    copas.http = {}
    local _M = copas.http

-----------------------------------------------------------------------------
-- Program constants
-----------------------------------------------------------------------------
-- connection timeout in seconds
    _M.TIMEOUT = 60
-- default port for document retrieval
    _M.PORT = 80
-- user agent field sent in request
    _M.USERAGENT = socket._VERSION

-- Default settings for SSL
    _M.SSLPORT = 443
    _M.SSLPROTOCOL = "tlsv1_2"
    _M.SSLOPTIONS  = "all"
    _M.SSLVERIFY   = "none"


-----------------------------------------------------------------------------
-- Reads MIME headers from a connection, unfolding where needed
-----------------------------------------------------------------------------
    local function receiveheaders(sock, headers)
      local line, name, value, err
      headers = headers or {}
      -- get first line
      line, err = sock:receive()
      if err then return nil, err end
      -- headers go until a blank line is found
      while line ~= "" do
        -- get field-name and value
        name, value = socket.skip(2, string.find(line, "^(.-):%s*(.*)"))
        if not (name and value) then return nil, "malformed reponse headers" end
        name = string.lower(name)
        -- get next line (value might be folded)
        line, err  = sock:receive()
        if err then return nil, err end
        -- unfold any folded values
        while string.find(line, "^%s") do
          value = value .. line
          line = sock:receive()
          if err then return nil, err end
        end
        -- save pair in table
        if headers[name] then headers[name] = headers[name] .. ", " .. value
        else headers[name] = value end
      end
      return headers
    end

-----------------------------------------------------------------------------
-- Extra sources and sinks
-----------------------------------------------------------------------------
    socket.sourcet["http-chunked"] = function(sock, headers)
      return base.setmetatable({
          getfd = function() return sock:getfd() end,
          dirty = function() return sock:dirty() end
          }, {
          __call = function()
            -- get chunk size, skip extention
            local line, err = sock:receive()
            if err then return nil, err end
            local size = base.tonumber(string.gsub(line, ";.*", ""), 16)
            if not size then return nil, "invalid chunk size" end
            -- was it the last chunk?
            if size > 0 then
              -- if not, get chunk and skip terminating CRLF
              local chunk, err = sock:receive(size)
              if chunk then sock:receive() end
              return chunk, err
            else
              -- if it was, read trailers into headers table
              headers, err = receiveheaders(sock, headers)
              if not headers then return nil, err end
            end
          end
        })
    end

    socket.sinkt["http-chunked"] = function(sock)
      return base.setmetatable({
          getfd = function() return sock:getfd() end,
          dirty = function() return sock:dirty() end
          }, {
          __call = function(self, chunk, err)
            if not chunk then return sock:send("0\r\n\r\n") end
            local size = string.format("%X\r\n", string.len(chunk))
            return sock:send(size ..  chunk .. "\r\n")
          end
        })
    end

-----------------------------------------------------------------------------
-- Low level HTTP API
-----------------------------------------------------------------------------
    local metat = { __index = {} }

    function _M.open(reqt)
      -- create socket with user connect function
      local c = socket.try(reqt:create())   -- method call, passing reqt table as self!
      local h = base.setmetatable({ c = c }, metat)
      -- create finalized try
      h.try = socket.newtry(function() h:close() end)
      -- set timeout before connecting
      h.try(c:settimeout(reqt.timeout or _M.TIMEOUT))
      h.try(c:connect(reqt.host, reqt.port or _M.PORT))
      -- here everything worked
      return h
    end

    function metat.__index:sendrequestline(method, uri)
      local reqline = string.format("%s %s HTTP/1.1\r\n", method or "GET", uri)
      return self.try(self.c:send(reqline))
    end

    function metat.__index:sendheaders(tosend)
      local canonic = headers.canonic
      local h = "\r\n"
      for f, v in base.pairs(tosend) do
        h = (canonic[f] or f) .. ": " .. v .. "\r\n" .. h
      end
      self.try(self.c:send(h))
      return 1
    end

    function metat.__index:sendbody(headers, source, step)
      source = source or ltn12.source.empty()
      step = step or ltn12.pump.step
      -- if we don't know the size in advance, send chunked and hope for the best
      local mode = "http-chunked"
      if headers["content-length"] then mode = "keep-open" end
      return self.try(ltn12.pump.all(source, socket.sink(mode, self.c), step))
    end
    function metat.__index:receivestatusline()
      local status = self.try(self.c:receive(5))
      -- identify HTTP/0.9 responses, which do not contain a status line
      -- this is just a heuristic, but is what the RFC recommends
      if status ~= "HTTP/" then return nil, status end
      -- otherwise proceed reading a status line
      status = self.try(self.c:receive("*l", status))
      local code = socket.skip(2, string.find(status, "HTTP/%d*%.%d* (%d%d%d)"))
      return self.try(base.tonumber(code), status)
    end

    function metat.__index:receiveheaders()
      return self.try(receiveheaders(self.c))
    end

    function metat.__index:receivebody(headers, sink, step)
      sink = sink or ltn12.sink.null()
      step = step or ltn12.pump.step
      local length = base.tonumber(headers["content-length"])
      local t = headers["transfer-encoding"] -- shortcut
      local mode = "default" -- connection close
      if t and t ~= "identity" then mode = "http-chunked"
      elseif base.tonumber(headers["content-length"]) then mode = "by-length" end
      return self.try(ltn12.pump.all(socket.source(mode, self.c, length),
          sink, step))
    end

    function metat.__index:receive09body(status, sink, step)
      local source = ltn12.source.rewind(socket.source("until-closed", self.c))
      source(status)
      return self.try(ltn12.pump.all(source, sink, step))
    end

    function metat.__index:close() return self.c:close() end

-----------------------------------------------------------------------------
-- High level HTTP API
-----------------------------------------------------------------------------
    local function adjusturi(reqt)
      local u = reqt
      -- if there is a proxy, we need the full url. otherwise, just a part.
      if not reqt.proxy and not _M.PROXY then
        u = {
          path = socket.try(reqt.path, "invalid path 'nil'"),
          params = reqt.params,
          query = reqt.query,
          fragment = reqt.fragment
        }
      end
      return url.build(u)
    end

    local function adjustproxy(reqt)
      local proxy = reqt.proxy or _M.PROXY
      if proxy then
        proxy = url.parse(proxy)
        return proxy.host, proxy.port or 3128
      else
        return reqt.host, reqt.port
      end
    end

    local function adjustheaders(reqt)
      -- default headers
      local host = string.gsub(reqt.authority, "^.-@", "")
      local lower = {
        ["user-agent"] = _M.USERAGENT,
        ["host"] = host,
        ["connection"] = "close, TE",
        ["te"] = "trailers"
      }
      -- if we have authentication information, pass it along
      if reqt.user and reqt.password then
        lower["authorization"] =
        "Basic " ..  (mime.b64(reqt.user .. ":" .. reqt.password))
      end
      -- override with user headers
      for i,v in base.pairs(reqt.headers or lower) do
        lower[string.lower(i)] = v
      end
      return lower
    end

-- default url parts
    local default = {
      host = "",
      port = _M.PORT,
      path ="/",
      scheme = "http"
    }

    local function adjustrequest(reqt)
      -- parse url if provided
      local nreqt = reqt.url and url.parse(reqt.url, default) or {}
      -- explicit components override url
      for i,v in base.pairs(reqt) do nreqt[i] = v end
      if nreqt.port == "" then nreqt.port = 80 end
      socket.try(nreqt.host and nreqt.host ~= "",
        "invalid host '" .. base.tostring(nreqt.host) .. "'")
      -- compute uri if user hasn't overriden
      nreqt.uri = reqt.uri or adjusturi(nreqt)
      -- ajust host and port if there is a proxy
      nreqt.host, nreqt.port = adjustproxy(nreqt)
      -- adjust headers in request
      nreqt.headers = adjustheaders(nreqt)
      return nreqt
    end

    local function shouldredirect(reqt, code, headers)
      return headers.location and
      string.gsub(headers.location, "%s", "") ~= "" and
      (reqt.redirect ~= false) and
      (code == 301 or code == 302 or code == 303 or code == 307) and
      (not reqt.method or reqt.method == "GET" or reqt.method == "HEAD")
      and (not reqt.nredirects or reqt.nredirects < 5)
    end

    local function shouldreceivebody(reqt, code)
      if reqt.method == "HEAD" then return nil end
      if code == 204 or code == 304 then return nil end
      if code >= 100 and code < 200 then return nil end
      return 1
    end

-- forward declarations
    local trequest, tredirect

--[[local]] function tredirect(reqt, location)
      local result, code, headers, status = trequest {
        -- the RFC says the redirect URL has to be absolute, but some
        -- servers do not respect that
        url = url.absolute(reqt.url, location),
        source = reqt.source,
        sink = reqt.sink,
        headers = reqt.headers,
        proxy = reqt.proxy,
        nredirects = (reqt.nredirects or 0) + 1,
        create = reqt.create
      }
      -- pass location header back as a hint we redirected
      headers = headers or {}
      headers.location = headers.location or location
      return result, code, headers, status
    end

--[[local]] function trequest(reqt)
      -- we loop until we get what we want, or
      -- until we are sure there is no way to get it
      local nreqt = adjustrequest(reqt)
      local h = _M.open(nreqt)
      -- send request line and headers
      h:sendrequestline(nreqt.method, nreqt.uri)
      h:sendheaders(nreqt.headers)
      -- if there is a body, send it
      if nreqt.source then
        h:sendbody(nreqt.headers, nreqt.source, nreqt.step)
      end
      local code, status = h:receivestatusline()
      -- if it is an HTTP/0.9 server, simply get the body and we are done
      if not code then
        h:receive09body(status, nreqt.sink, nreqt.step)
        return 1, 200
      end
      local headers
      -- ignore any 100-continue messages
      while code == 100 do
        h:receiveheaders()
        code, status = h:receivestatusline()
      end
      headers = h:receiveheaders()
      -- at this point we should have a honest reply from the server
      -- we can't redirect if we already used the source, so we report the error
      if shouldredirect(nreqt, code, headers) and not nreqt.source then
        h:close()
        return tredirect(reqt, headers.location)
      end
      -- here we are finally done
      if shouldreceivebody(nreqt, code) then
        h:receivebody(headers, nreqt.sink, nreqt.step)
      end
      h:close()
      return 1, code, headers, status
    end

-- Return a function which performs the SSL/TLS connection.
    local function tcp(params)
      params = params or {}
      -- Default settings
      params.protocol = params.protocol or _M.SSLPROTOCOL
      params.options = params.options or _M.SSLOPTIONS
      params.verify = params.verify or _M.SSLVERIFY
      params.mode = "client"   -- Force client mode
      -- upvalue to track https -> http redirection
      local washttps = false
      -- 'create' function for LuaSocket
      return function (reqt)
        local u = url.parse(reqt.url)
        if (reqt.scheme or u.scheme) == "https" then
          -- https, provide an ssl wrapped socket
          local conn = copas.wrap(socket.tcp(), params)
          -- insert https default port, overriding http port inserted by LuaSocket
          if not u.port then
            u.port = _M.SSLPORT
            reqt.url = url.build(u)
            reqt.port = _M.SSLPORT
          end
          washttps = true
          return conn
        else
          -- regular http, needs just a socket...
          if washttps and params.redirect ~= "all" then
            try(nil, "Unallowed insecure redirect https to http")
          end
          return copas.wrap(socket.tcp())
        end
      end
    end

-- parses a shorthand form into the advanced table form.
-- adds field `target` to the table. This will hold the return values.
    _M.parseRequest = function(u, b)
      local reqt = {
        url = u,
        target = {},
      }
      reqt.sink = ltn12.sink.table(reqt.target)
      if b then
        reqt.source = ltn12.source.string(b)
        reqt.headers = {
          ["content-length"] = string.len(b),
          ["content-type"] = "application/x-www-form-urlencoded"
        }
        reqt.method = "POST"
      end
      return reqt
    end
    _M.request = socket.protect(function(reqt, body)
        if base.type(reqt) == "string" then
          reqt = _M.parseRequest(reqt, body)
          local ok, code, headers, status = _M.request(reqt)

          if ok then
            return table.concat(reqt.target), code, headers, status
          else
            return nil, code
          end
        else
          reqt.create = reqt.create or tcp(reqt)
          return trequest(reqt)
        end
      end)

    http = _M
  end
--------- Copas Lock support -------------------------
  do
    local DEFAULT_TIMEOUT = 10
    local gettime = socket.gettime
    lock = {}
    lock.__index = lock

-- registry, locks indexed by the coroutines using them.
    local registry = setmetatable({}, { __mode="kv" })

--- Creates a new lock.
-- @param seconds (optional) default timeout in seconds when acquiring the lock (defaults to 10)
-- @param not_reentrant (optional) if truthy the lock will not allow a coroutine to grab the same lock multiple times
-- @return the lock object
    function lock.new(seconds, not_reentrant)
      local timeout = tonumber(seconds or DEFAULT_TIMEOUT) or -1
      if timeout < 0 then
        error("expected timeout (1st argument) to be a number greater than or equal to 0, got: " .. tostring(seconds), 2)
      end
      return setmetatable({
          timeout = timeout,
          not_reentrant = not_reentrant,
          queue = {},
          q_tip = 0,  -- index of the first in line waiting
          q_tail = 0, -- index where the next one will be inserted
          owner = nil, -- coroutine holding lock currently
          call_count = nil, -- recursion call count
          errors = setmetatable({}, { __mode = "k" }), -- error indexed by coroutine
          }, lock)
    end

    do
      local destroyed_func = function()
        return nil, "destroyed"
      end

      local destroyed_lock_mt = {
        __index = function()
          return destroyed_func
        end
      }
      --- destroy a lock.
      -- Releases all waiting threads with `nil+"destroyed"`
      function lock:destroy()
        --print("destroying ",self)
        for i = self.q_tip, self.q_tail do
          local co = self.queue[i]
          if co then
            self.errors[co] = "destroyed"
            --print("marked destroyed ", co)
            copas.wakeup(co)
          end
        end
        if self.owner then
          self.errors[self.owner] = "destroyed"
          --print("marked destroyed ", co)
        end
        self.queue = {}
        self.q_tip = 0
        self.q_tail = 0
        self.destroyed = true
        setmetatable(self, destroyed_lock_mt)
        return true
      end
    end

    local function timeout_handler(co)
      local self = registry[co]
      for i = self.q_tip, self.q_tail do
        if co == self.queue[i] then
          self.queue[i] = nil
          self.errors[co] = "timeout"
          --print("marked timeout ", co)
          copas.wakeup(co)
          return
        end
      end
    end

--- Acquires the lock.
-- If the lock is owned by another thread, this will yield control, until the
-- lock becomes available, or it times out.
-- If `timeout == 0` then it will immediately return (without yielding).
-- @param timeout (optional) timeout in seconds, if given overrides the timeout passed to `new`.
-- @return wait-time on success, or nil+error+wait_time on failure. Errors can be "timeout", "destroyed", or "lock is not re-entrant"
    function lock:get(timeout)
      local co = coroutine.running()
      local start_time

      -- is the lock already taken?
      if self.owner then
        -- are we re-entering?
        if co == self.owner then
          if self.not_reentrant then
            return nil, "lock is not re-entrant", 0
          else
            self.call_count = self.call_count + 1
            return 0
          end
        end

        self.queue[self.q_tail] = co
        self.q_tail = self.q_tail + 1
        timeout = timeout or self.timeout
        if timeout == 0 then
          return nil, "timeout", 0
        end

        registry[co] = self
        copas.timeout(timeout, timeout_handler)
        start_time = gettime()
        copas.sleep(-1)
        local err = self.errors[co]
        self.errors[co] = nil
        if err ~= "timeout" then
          copas.timeout(0)
        end
        if err then
          self.errors[co] = nil
          return nil, err, gettime() - start_time
        end
      end
      self.owner = co
      self.call_count = 1
      return start_time and (gettime() - start_time) or 0
    end
--- Releases the lock currently held.
-- Releasing a lock that is not owned by the current co-routine will return
-- an error.
-- returns true, or nil+err on an error
    function lock:release()
      local co = coroutine.running()
      if co ~= self.owner then
        return nil, "cannot release a lock not owned"
      end
      self.call_count = self.call_count - 1
      if self.call_count > 0 then
        -- same coro is still holding it
        return true
      end
      if self.q_tail == self.q_tip then
        -- queue is empty
        self.owner = nil
        return true
      end
      while self.q_tip < self.q_tail do
        local next_up = self.queue[self.q_tip]
        if next_up then
          self.owner = next_up
          self.queue[self.q_tip] = nil
          self.q_tip = self.q_tip + 1
          copas.wakeup(next_up)
          return true
        end
        self.q_tip = self.q_tip + 1
      end
      -- queue is empty, reset pointers
      self.q_tip = 0
      self.q_tail = 0
      return true
    end
  end

--------- Main HC3 timer support based on  Copas -------------------------
  local format,colorStr = string.format,Util.colorStr
  local function patchSource(str) return str:match('"(.-)"') or str end
  local TimerMetatable = {
    __tostring = function(self)
      local extra = self.tag and (" "..self.tag) or ""
      if self.extra then extra = format("%s %s,line:%s",extra,patchSource(self.extra.short_src),self.extra.currentline) end
      if _debugFlags.timersWarn then
        local diff = os.milliTime()-self.time
        return colorStr(diff > _debugFlags.timersWarn and 'red' or 'green',self.tostr..os.milliStr(self.time)..extra..">")
      else
        return self.tostr..os.milliStr(self.time)..extra..">"
      end
    end
  }
  -- <Timer:999, fun=0x8888, exp:...>
  local function ISTIMER(t) return type(t)=='table' and t['%%TIMER%%'] end
  local TINDEX = 1
  local function makeTimer(t)
    t['%%TIMER%%']=true
    t.tostr = format("<Timer:%04d fun:%s exp:",TINDEX,tostring(t.fun2 or t.fun):sub(11))
    TINDEX=TINDEX+1
    setmetatable(t,TimerMetatable)
    return t
  end

  local SPEED,timeAdjust = false,0
  local timers = nil
  local runT,runTimers,maxTime = nil,nil

  local _milliTime  -- return time in seconds
  if _G['ngx'] then _milliTime = _G['ngx'].now
  else
    local ok, socket = pcall(require, "socket")
    if ok then _milliTime = socket.gettime
    else _milliTime = os.time end
  end

  local function max(x,y) return x>=y and x or y end

  os._time  = os.time
  os._clock = os.clock
  os._date  = os.date
  os.rt = _milliTime
  os._exit = os.exit
  os.speed = function(b) 
    SPEED = b Log(LOG.SYS,"Setting speed to %s",tostring(b)) 
    if runT then runT:cancel(); runT=nil end
    runT = os.setTimer2(runTimers,SPEED and 0 or max(timers.time-os.milliTime(),0))
  end
  os.time = function(t) return t and os._time(t) or math.floor(os.rt() + timeAdjust) end
  os.milliTime = function() return os.rt() + timeAdjust end
  os.clock = function() return os._clock() end
  os.date = function(s,t) return os._date(s,t or os.time()) end
  os.setTimer2 = function(fun,sec,recurring,params,env)
    local t =
    timer.new({
        delay = sec,
        recurring = recurring or false,
        callback = fun,
        params = params
      })
    contexts[t.co]=env or _ENV
    return t
  end
  os.setTimer = function(fun,ms,recurring,params,env) return os.setTimer2(fun,ms/1000.0,recurring,params,env) end
  os.clearTimer = function(t) t:cancel() end
  os.milliStr = function(t) return os.date("%H:%M:%S",math.floor(t))..format(":%03d",math.floor((t%1)*1000+0.5)) end
  function os.setTime(t)
    timeAdjust = t-os.time()
    Log(LOG.SYS,"Setting emulator time to %s",os.date("%c",t))
    local t0 = timers
    while t0 do -- update already scheduled timers
      t0.time = t0.time + timeAdjust
      t0 = t0.next
    end
  end

  local function dumpTimers()
    local t = timers
    print("-----------------------")
    while t do print(os.date("%c",math.floor(t.time)),t.time,t); t = t.next end
  end

  hc3_emulator.dumpTimers = dumpTimers

  local function countTimers() local t,n = timers,0; while t do n=n+1; t=t.next end return  n end --luacheck: ignore

  local function kick()
    if not timers then return end
    if _debugFlags.timersSched then
      Log(LOG.LOG,"Will run next timer at %s in %0.4fs",os.milliStr(timers.time),timers.time-os.milliTime())
    end
    if runT then runT:cancel(); runT=nil end
    runT = os.setTimer2(runTimers,SPEED and 0 or max(timers.time-os.milliTime(),0))
  end
  self.kick = kick

  local function insertTimer(t) -- {fun,time,next}
    if _debugFlags.timersSched then Log(LOG.LOG,"Inserting timer %s",t) end
    if t.env and not t.env._ENVID then return end
    if timers == nil then
      timers=t
    elseif t.time < timers.time then
      timers,t.next=t,timers
    else
      local tp = timers
      while tp.next and tp.next.time <= t.time do tp=tp.next end
      t.next,tp.next=tp.next,t
    end
    if self._started and timers == t then kick() end
    --dumpTimers()
    return t
  end

  local function deleteTimer(timer) -- ToDo: delete scheduled timer?
    if timer==nil then return end
    if _debugFlags.timersSched then Log(LOG.LOG,"Deleting timer:%s",timer) end
    timer.expired = true
    if timers == timer then
      timers = timers.next
      if runT then runT:cancel() runT=nil end
      if timers then runT = os.setTimer2(runTimers,SPEED and 0 or max(timers.time-os.milliTime(),0)) end
    else
      local tp = timers
      while tp and tp.next do
        if tp.next == timer then tp.next = tp.next.next return end
        tp = tp.next
      end
    end
  end

  function runTimers()
    runT = nil
    ::REDO::
    local t,now = timers,os.milliTime()
    if timers then
      if _debugFlags.timersSched then Log(LOG.LOG,"Running:%s, RT:%s, SPEED:%s",t,os.milliStr(now),SPEED) end
      if maxTime and t.time >= maxTime then
        timeAdjust = maxTime-os.rt()
        Log(LOG.SYS,"Max time - exit") osExit()
      end
      if SPEED then 
        timers = timers.next
        timeAdjust = t.time-os.rt()
        --os.setTimer2(t.fun,0,false,t.params,t.env)
        t.fun(nil,t.params)
        if timers ~= nil and timers.time == t.time then goto REDO end
      else
        timers = timers.next 
        os.setTimer2(t.fun,0,false,t.params,t.env)
      end
      if timers then
        if SPEED then 
          runT = os.setTimer2(runTimers,1)
        elseif not SPEED then
          local s = max(timers.time-os.milliTime(),0)
          runT = os.setTimer2(runTimers,s)
        end
      end
    end
  end

  local function timerWrap(_,params)
    local t,fun,eh,ctx,now = params[2],params[1],params[3],params[4]
    --local ctx = getContext()
    ctx._getLock()
    if not t.expired and ctx._ENVID then
      now = os.milliTime()
      t.expired = true
      if _debugFlags.timersWarn  and now-t.time > _debugFlags.timersWarn then
        Log(LOG.WARNING,"Late timer:%0.3fs %s",now-t.time,t)
        --if ctx._lastTimer then Log(LOG.WARNING,"Last timer:%s",ctx._lastTimer) end
        ----hc3.mobdebug.pause() 
      end
      ctx._lastTimer = t
      xpcall(fun,eh)
    end
    ctx._releaseLock()
  end

  local function timerErr(err)
    Log(LOG.ERROR,"Timer %s crashed - %s",_lastTimer,err)
    print(debug.traceback(err,1))
    if _debugFlags.breakOnError then hc3.mobdebug.pause() end
  end

  function self.adjustTime(time) timeAdjust=timeAdjust+time end
  function self.setSystemTimeout(fun,time,tag)
    time,tag = time > 0 and time or 0, tag or "System"
    return insertTimer(makeTimer({fun=fun,time=os.milliTime()+time/1000.0,tag=tag}))
  end

  local function setTimeout(fun,time,tag,errHandler,env,extra)
    if not env._ENVID then return end -- Killed
    assert(type(fun)=='function' and type(time)=='number',"Bad arguments to setTimeout")
    local warn,params = _debugFlags.timersWarn and time<0, {fun,nil,errHandler or timerErr,env}
    time = time > 0 and time or 0
    if _debugFlags.timersExtra then
      extra = extra or debug.getinfo(2,"Sl")
    end
    -- tag = env._VERSION
    local t = insertTimer(makeTimer({
          fun=timerWrap,params=params,fun2=fun,extra=extra,
          time=os.milliTime()+time/1000.0,tag=tag,env=env or getContext()
        }))
    if warn then Log(LOG.WARNING,"Negative timer:%s",t) end
    params[2]=t
    --dumpTimers()
    return t
  end

  local function clearTimeout(timer)
    if ISTIMER(timer) and not timer.expired then
      deleteTimer(timer)
    end
  end

  function self.killTimers(id)
    local n,killable = 0,function (t) return t and t.env and t.env._ENVID == id end
    while killable(timers) do deleteTimer(timers) n=n+1 end
    if timers==nil then return n end
    local t = timers
    while t.next do
      if killable(t.next) then deleteTimer(t.next) n=n+1
      else t=t.next end
    end
    return n
  end

  local function setInterval(fun,ms,tag)
    local setTimeout,extra = getContext().setTimeout or setTimeout
    assert(type(fun)=='function' and type(ms)=='number',"Bad argument to setInterval")
    if _debugFlags.timersExtra then
      extra = debug.getinfo(2,"Sl")
    end
    local ref={}
    local function loop()
      if ref[1] then
        fun()
        ref[1]=ref[1] and setTimeout(loop,ms,tag,nil,nil,extra)
      end
    end
    ref[1] = setTimeout(loop,ms,tag,nil,nil,extra)
    return ref
  end

  local function clearInterval(ref)
    assert(type(ref)=='table' and ISTIMER(ref[1]),"Bad timer to clearInterval")
    local r = ref[1]
    if r then ref[1]=nil; clearTimeout(r) end
  end

  function self.speedTime(speedTime) -- seconds
    maxTime = os.time()+speedTime*60*60
    --print(os.date("%c",os.time()))
    os.speed(true)
  end

  function self.start(f)
    copas.loop(function()
        timer.new({
            delay = 0, -- delay in seconds
            recurring = false,
            params = "",
            callback = function(_, _) f() end
          })
      end)
  end

  self.copas = copas
  self.copas.lock = lock
  self.dumpTimers = dumpTimers
  self.makeTimer = makeTimer
  self.inserTimer = insertTimer
  self.setTimeout = setTimeout
  self.clearTimeout = clearTimeout
  self.setInterval = setInterval
  self.clearInterval = clearInterval
  return self
end--module Timer

--------------- QuickApp functions and support -------
function module.QuickApp(hc3)
  local self = {}
  local QA = self
  local Util,Timer,Trigger,OS,Local=hc3.module.Util
  local _debugFlags = hc3.debug
  local class,ff,copas,fibaro = Util.class
  local __fibaro_get_device,__assert_type
  local format = string.format

  local quickApps,files,filePaths,plugin = {},{},{},{}
  self.quickApps,self.files,self.plugin = quickApps,files,plugin

  Log,LOG,json,api,net,assert,assertf=Log,LOG,json,api,net,assert,assertf

  function self.initialise()
    Timer,Trigger,OS,Local = hc3.module.Timer,hc3.module.Trigger,hc3.module.OS,hc3.module.Local
    __fibaro_get_device = hc3.module.Fibaro.__fibaro_get_device
    __assert_type = hc3.module.Fibaro.__assert_type
    ff,copas,fibaro = OS.file,Timer.copas,hc3.module.Fibaro.fibaro
  end

  plugin.mainDeviceId = 999
  local function ID() return getContext().plugin.mainDeviceId end
  function plugin.deleteDevice(deviceId) return api.delete("/devices/"..deviceId) end
  function plugin.restart(deviceId) return api.post("/plugins/restart",{deviceId=deviceId or ID()}) end
  function plugin.getProperty(id,prop) return api.get("/devices/"..id.."/property/"..prop) end
  function plugin.getChildDevices(id) return api.get("/devices?parentId="..(id or ID())) end
  function plugin.createChildDevice(props) return api.post("/plugins/createChildDevice",props) end

  function self.getWebUIValue(id,elm,t)
    local qa = quickApps[id]
    if qa and qa._emu.UI then
      return qa._emu.uiValues[elm][t]
    end
  end
  function self.setWebUIValue(id,elm,t,v)
    local qa = quickApps[id]
    if qa and qa._emu.UI then
      qa._emu.uiValues[elm] = qa._emu.uiValues[elm] or {}
      qa._emu.uiValues[elm][t]=tostring(v)
    end
  end

  Util.class 'QuickAppBase'
  function QuickAppBase:__init(device)
    if tonumber(device) then device =  api.get("/devices/"..device) end
    quickApps[device.id] = self
    self.name = device.name
    self.id = device.id
    self.type = device.type
    self.properties = device.properties
    self._emu = {proxy=device._proxy, env=device._env, uiValues={}, slideCache={}}
    if device.properties.viewLayout then
      self._emu.UI = QA.view2UI(device.properties.viewLayout,device.properties.uiCallbacks or {})
      QA.transformUI(self._emu.UI)
    else self._emu.UI = {} end
    self.parentId = self.parentId or (device.parentId and device.parentId > 0 and device.parentId)
    device._proxy = nil
    device._env = nil
    local cbs = {}
    for _,cb in ipairs(device.properties.uiCallbacks or {}) do
      cbs[cb.name]=cbs[cb.name] or {}
      cbs[cb.name][cb.eventType] = cb.callback
    end
    self.uiCallbacks = cbs
    if self._emu.UI then
      for _,row in ipairs(self._emu.UI) do
        row = row[1] and row or {row}
        for _,e in ipairs(row) do
          QA.setWebUIValue(self.id,e.name,"value","0")
          QA.setWebUIValue(self.id,e.name,"text",e.text or "")
        end
      end
    end
  end

  function QuickAppBase:debug(...) fibaro.debug(self._emu.env.__TAG,d2str(...)) end
  function QuickAppBase:trace(...) fibaro.trace(self._emu.env.__TAG,d2str(...)) end
  function QuickAppBase:warning(...) fibaro.warning(self._emu.env.__TAG,d2str(...)) end
  function QuickAppBase:error(...) fibaro.error(self._emu.env.__TAG,d2str(...)) end

  function QuickAppBase:getVariable(name)
    __assert_type(name,'string')
    if self._emu.proxy then
      local d = __fibaro_get_device(self.id) or {properties={}}
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
    local vs,vs2,flag = {},self.properties.quickAppVariables or {},false
    for i=1,#vs2 do vs[i]=vs2[i] end
    for _,v in ipairs(vs) do
      if v.name==name then v.value=value; flag=true; break end
    end
    if not flag then -- variable not found, add it
      vs[#vs+1]={name=name,value=value}
      --self.properties.quickAppVariables = vs
    end
    self:updateProperty('quickAppVariables', vs, true)
  end

  function QuickAppBase:updateView(elm,t,value)
    api.post("/plugins/updateView",{
        deviceId=self.id,
        componentName =  elm,
        propertyName = t,
        newValue = value
      })
  end

  function QuickAppBase:updateProperty(prop,value,force)
    __assert_type(prop,'string')
    if self.properties[prop] == value and not force then return end -- optimization
    api.post("/plugins/updateProperty",{deviceId = self.id, propertyName = prop, value = value, force=force})
  end

  function QuickAppBase:setEnabled(bool) self.enabled=bool==true end

  function QuickAppBase:callAction(fun, ...)
    if type(self[fun])=='function' then
      local args = {...}
      self._emu.env.setTimeout(function()
          local stat,res = pcall(self[fun],self,table.unpack(args))
          if not stat then Log(LOG.ERROR,res) end
        end,0)
    else
      Log(LOG.WARNING,"Class does not have "..fun.." function defined - action ignored")
    end
  end

  function QuickAppBase:addInterfaces(interfaces)
    if self._emu.proxy then
      api.post("/devices/addInterface",{deviceID={self.id},interfaces=interfaces})
    end
  end

  Util.class 'QuickApp'(QuickAppBase) -- Special form of class easier to step through...
  function QuickApp:__init(device)
    QuickAppBase.__init(self,device)
    self.childDevices = {}
    if self.onInit then self:onInit() end
    if not self._childsInited then self:initChildDevices() end
  end

  function QuickApp:createChildDevice(props,device)
    --assert(self._emu.proxy,"Can only create child device when using proxy")
    props.parentId = self.id
    props.initialInterfaces = props.initialInterfaces or {}
    props.initialInterfaces[#props.initialInterfaces+1]='quickAppChild'
    if next(props.initialProperties)==nil then props.initialProperties=nil end
    local d,res = api.post("/plugins/createChildDevice",props)
    assert(res==200,"Can't create child device "..res.." - "..json.encode(props))
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
    map = map or {}
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
    assert(type(device)=='number' or type(device)=='table',"QuickAppChild:__init needs number/table")
    local parent = device.parentId and quickApps[device.parentId]
    assert(parent,"Trying to create QuickAppChild without parentId")
    device._proxy = parent._emu.proxy
    device._env = parent._emu.env
    if Util.member('quickApp',device.interfaces or {}) and device.properties.viewLayout then
      Log(LOG.LOG,"Using QuickAppChild's provided viewlayout")
    else
      local UI = Local.customUI[device.type] or Local.customUI[device.baseType]
      if UI and not device.properties.viewLayout then
        UI = Util.copy(UI)
        local ip = QA.makeInitialProperties(UI)
        device.properties.viewLayout,device.properties.uiCallbacks = ip.viewLayout,ip.uiCallbacks
      end
    end
    QuickAppBase.__init(self,device)
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
            row[#row+1]={button=u.name, text=u.text, onReleased=cb}
          elseif u.type=='slider' then
            local cb = map["slider"..u.name]
            if cb == u.name.."Clicked" then cb = nil end
            row[#row+1]={slider=u.name, text=u.text, onChanged=cb}
          end
        else
          for _,v in pairs(u) do conv(v) end
        end
      end
    end
    conv(u)
    return row
  end

  local function viewLayout2UI(u,map)
    local function conv(u)
      local rows = {}
      for _,j in pairs(u.items) do
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
      return {name=d.name,style={weight=d.weight or w or "0.50"},text=d.text,type="button"}
    end,
    select = function(d,w)
      if d.options then map(function(e) e.type='option' end,d.options) end
      return {name=d.name,style={weight=d.weight or w or "0.50"},text=d.text,type="select", selectionType='single',
        options = d.options or {{value="1", type="option", text="option1"}, {value = "2", type="option", text="option2"}},
        values = d.values or { "option1" }
      }
    end,
    multi = function(d,w)
      if d.options then map(function(e) e.type='option' end,d.options) end
      return {name=d.name,style={weight=d.weight or w or "0.50"},text=d.text,type="select", selectionType='multi',
        options = d.options or {{value="1", type="option", text="option2"}, {value = "2", type="option", text="option3"}},
        values = d.values or { "option3" }
      }
    end,
    image = function(d,w)
      return {name=d.name,style={dynamic="1"},type="image", url=d.url}
    end,
    switch = function(d,w)
      return {name=d.name,style={weight=w or d.weight or "0.50"},type="switch", value=d.value or "true"}
    end,
    option = function(d,w)
      return {name=d.name, type="option", value=d.value or "Hupp"}
    end,
    slider = function(d,w)
      return {name=d.name,step=tostring(d.step),value=tostring(d.value),max=tostring(d.max),min=tostring(d.min),style={weight=d.weight or w or "1.2"},text=d.text,type="slider"}
    end,
    label = function(d,w)
      return {name=d.name,style={weight=d.weight or w or "1.2"},text=d.text,type="label"}
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
      if width:match("%.00") then width=width:match("^(%d+)") end
      for _,e in ipairs(elms) do c[#c+1]=ELMS[e.type](e,width) end
      if #elms > 1 then comp[#comp+1]={components=c,style={weight="1.2"},type='horizontal'}
      else comp[#comp+1]=c[1] end
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
--    if #items == 0 then  return nil end
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

  self.mkViewLayout = mkViewLayout
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
    return UI
  end

  local function uiStruct2uiCallbacks(UI)
    local cb = {}
    --- "callback": "self:button1Clicked()",
    traverse(UI,
      function(e)
        if e.name then
          -- {callback="foo",name="foo",eventType="onReleased"}
          local defu = e.button and "Clicked" or e.slider and "Change" or (e.switch or e.select) and "Toggle" or ""
          local deff = e.button and "onReleased" or e.slider and "onChanged" or (e.switch or e.select) and "onToggled" or ""
          local cbt = e.name..defu
          if e.onReleased then
            cbt = e.onReleased
          elseif e.onChanged then
            cbt = e.onChanged
          elseif e.onToggled then
            cbt = e.onToggled
          end
          if e.button or e.slider or e.switch or e.select then
            cb[#cb+1]={callback=cbt,eventType=deff,name=e.name}
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
  self.makeInitialProperties = makeInitialProperties

--  local function pruneCode(code)
--    local c = code:match("%-%-%-%-%-%-%-%-%-%-%- Code.-\n(.*)")
--    return c or code
--  end

  function hc3_emulator.dofile(file)
    local ctx = getContext()
    return loadfile(file,"bt",ctx)()
  end

  function hc3_emulator.FILE(_,_) end -- Nop. For backward compatibility

  local function createFilesFromSource(source,mainFileName)
    local files,paths = {},{}
    local function gf(pattern)
      source = source:gsub(pattern,
        function(file,name)
          local stat,res = pcall(function() return ff.read(file) end)
          if not stat then Log(LOG.ERROR,"%s",res)
          else
            files[#files+1]={name=name,content=res,isMain=false,type="lua",isOpen=false}
            paths[name]=file
          end
          return ""
        end)
    end
    pcall(gf,[[%-%-FILE:%s*(.-)%s*,%s*(.-);]])
    table.insert(files,1,{name="main",content=source,isMain=true,type='lua',isOpen=false})
    paths['main']=mainFileName
    return files,paths
  end

  function self.loadFilesFromSource(source,mainFileName)
    local files,paths = createFilesFromSource(source,mainFileName)
    --- TBD
  end

  self.createFilesFromSource = createFilesFromSource

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
    if (hc3_emulator.HC3version or "5.040.37") < "5.040.37" then
      error("Sorry, QuickApp creation need HC3 version >= 5.040.37")
    end
    local d = {} -- Our device
    d.name = args.name or "QuickApp"
    d.type = args.type or "com.fibaro.binarySensor"
    local files = args.code or ""
    --body = replaceRequires(body)
    local UI = args.UI or {}
    local variables = args.quickVars or {}
    local interfaces = args.interfaces
    local dryRun = args.dryrun or false
    d.apiVersion = "1.2"
    if not args.initialProperties then
      d.initialProperties = makeInitialProperties(UI,variables,args.height)
    else
      d.initialProperties = args.initialProperties
    end
    if d.initialProperties.uiCallbacks and not d.initialProperties.uiCallbacks[1] then
      d.initialProperties.uiCallbacks = nil
    end
    d.initialProperties.apiVersion = "1.2"

    if type(files)=='string' then files = {{name='main',type='lua',isMain=true,isOpen=false,content=files}} end
    d.files  = {}

    for _,f in ipairs(files) do f.isOpen=false; d.files[#d.files+1]=f end

    if dryRun then return d end

    local what,d1,res="updated"
    if args.id and api.getHC3("/devices/"..args.id) then
      d1,res = api.putHC3("/devices/"..args.id,{
          properties={
            quickAppVariables = d.initialProperties.quickAppVariables,
            viewLayout= d.initialProperties.viewLayout,
            uiCallbacks = d.initialProperties.uiCallbacks,
          }
        })
      if res <= 201 then
        local a,b = OS.file.updateHC3QAFiles(files,args.id)
      end
    else
      --print(json.encode(d))
      d1,res = api.postHC3("/quickApp/",d)
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

  local proxyPinger = nil
  local function startProxyPinger()
    if proxyPinger then return end --only start once
    api.postHC3("/globalVariables",{ name=hc3.emu.EMURUNNING,value=""  })
    local tick=0
    proxyPinger = os.setTimer2(function()
        api.putHC3("/globalVariables/"..hc3.emu.EMURUNNING,{value=tostring(tick)..":"..hc3.IPaddress..":"..hc3.webPort})
        tick  = tick+1
      end,hc3.emu.EMURUNNING_INTERVAL,true)
  end

-- Create a Proxy device - will be named "Proxy "..name, returns deviceID if successful
  local function createProxy(name,tp,ips,interfaces)
    local pdevice,id
    name = "Proxy "..name
    local d,res = api.getHC3("/devices/?name="..name)
    if d and #d>0 then
      table.sort(d,function(a,b) return a.id >= b.id end)
      pdevice = d[1]
      Log(LOG.SYS,"Proxy: '%s' found, ID:%s",name,pdevice.id)
      if pdevice.type ~= tp then
        Log(LOG.SYS,"Proxy: Type changed from '%s' to %s",tp,pdevice.type)
        api.delete("/devices/"..pdevice.id)
        pdevice = nil
      else id = pdevice.id end
    end
    local code = {}
    code[#code+1] = [[
  local function urlencode (str)
  return str and string.gsub(str ,"([^% w])",function(c) return string.format("%%% 02X",string.byte(c))  end)
end
local function POST2IDE(path,payload)
    url = "http://"..IP..path
    net.HTTPClient():request(url,{options={method='POST',data=json.encode(payload)}})
end
local IGNORE={updateView=true,setVariable=true,updateProperty=true,APIPOST=true,APIPUT=true,APIGET=true} -- Rewrite!!!!
function QuickApp:actionHandler(action)
      if IGNORE[action.actionName] then 
        return self:callAction(action.actionName, table.unpack(action.args))
      end
      POST2IDE("/fibaroapiHC3/action/"..self.id,action)
end
function QuickApp:UIHandler(UIEvent) POST2IDE("/fibaroapiHC3/ui/"..self.id,UIEvent) end
function QuickApp:CREATECHILD(id) self.childDevices[id]=QuickAppChild({id=id}) end
function QuickApp:APIGET(url) api.get(url) end
function QuickApp:APIPOST(url,data) api.post(url,data) end -- to get around some access restrictions
function QuickApp:APIPUT(url,data) api.put(url,data) end
]]
    code[#code+1]= "function QuickApp:onInit()"
    code[#code+1]= " self:debug('"..name.."',' deviceId:',self.id)"
    code[#code+1]= " IP = self:getVariable('PROXYIP')"
    code[#code+1]= " function QuickApp:initChildDevices() end"
    code[#code+1]= "end"

    code = table.concat(code,"\n")

    Log(LOG.SYS,id and "Proxy: Reusing QuickApp proxy" or "Proxy: Creating new proxy")

    table.insert(ips.quickAppVariables,{name="PROXYIP", value = Util.getIPaddress()..":"..hc3.webPort})
    return createQuickApp{id=id,name=name,type=tp,code=code,initialProperties=ips,interfaces=interfaces}
  end

  local function injectProxy(id)
    local code = [[
do
   local actionH,UIh,patched = nil,nil,false
   local function urlencode (str)
     return str and string.gsub(str ,"([^% w])",function(c) return string.format("%%% 02X",string.byte(c))  end)
   end
   local IGNORE={updateView=true,setVariable=true,updateProperty=true,PROXY=true,APIPOST=true,APIPUT=true,APIGET=true} -- Rewrite!!!!
   
   local function enable(ip)
     if patched==false then
        actionH,UIh = quickApp.actionHandler,quickApp.UIHandler
        local function POST2IDE(path,payload)
          url = "http://"..ip..path
          net.HTTPClient():request(url,{options={method='POST',data=json.encode(payload)}})
        end
        function quickApp:actionHandler(action)
           if IGNORE[action.actionName] then
             return quickApp:callAction(action.actionName, table.unpack(action.args))
           end
           POST2IDE("/fibaroapiHC3/action/"..quickApp.id,action)
        end
        function quickApp:UIHandler(UIEvent) POST2IDE("/fibaroapiHC3/ui/"..quickApp.id,UIEvent) end
        quickApp:debug("Events intercepted by emulator at "..ip)
      end
      patched=true
   end

   local function disable()
    if patched==true then
      if actionH then quickApp.actionHandler = actionH end
      if UIh then quickApp.UIHandler = UIh end
      actionH,UIh=nil,nil
      quickApp:debug("Events restored from emulator")
      patched=false
    end
   end
   
   setInterval(function()
    local stat,res = pcall(function()
    local var,err = __fibaro_get_global_variable("HC3Emulator")
    if var then
      local modified = var.modified
      local ip = var.value
      --print(modified,os.time()-5,modified-os.time()+5)
      if modified > os.time()-5 then enable(ip:match(":(.*)"))
      else disable() end
    end
   end)
   if not stat then print(res) end
   end,3000)
end
]]
    local dev = api.getHC3("/devices/"..id)
    assert(dev,"No such device "..id)
    if not api.getHC3("/quickApp/"..id.."/files/PROXY") then
      api.postHC3("/quickApp/"..id.."/files",{
          name="PROXY",
          isMain=false,
          isOpen=false,
          content=code,
          type='lua'
        })
    end
    return dev
  end

  function onAction(event)
--    Debug(_debugFlags.onAction,"onAction: %s",json.encode(event))
    if _debugFlags.onAction then print("onAction: "..json.encode(event)) end
    local self = quickApps[event.deviceId]
    if self.parentId then self = quickApps[self.parentId] end
    assert(self,"Unknown deviceID for onAction:"..event.deviceId)
    if self.actionHandler then self:actionHandler(event)
    else
      local id = event.deviceId
      if id == self.id then
        return self:callAction(event.actionName, table.unpack(event.args))
      else
        local child = self.childDevices[id]
        if child then child:callAction(event.actionName, table.unpack(event.args))
        else
          error(format("Child with id:%s not found.", id))
        end
      end
    end
  end

--"{\"eventType\":\"onReleased\",\"values\":[null],\"elementName\":\"bt\",\"deviceId\":726}"
--"{\"eventType\":\"onChanged\",\"values\":[80],\"elementName\":\"sl\",\"deviceId\":726}"
  local function ui2fun(self,event)
    local elm,etyp=event.elementName,event.eventType
    local callbacks = self.uiCallbacks or {}
    if callbacks[elm] and callbacks[elm][etyp] then
      if etyp=='onChanged' then
        QA.setWebUIValue(self.id,elm,'value',event.values)
      end
      return callbacks[elm][etyp]
    else return self[elm] end
  end

  function onUIEvent(event)
    local self = quickApps[event.deviceId]
    assert(self,"Unknown deviceID for UIEvent:"..event.deviceId)
    local parent = quickApps[self.parentId or 0] or self
    if event.elementName:sub(1,2)=="__" then -- json/builtin UI that becomes onAction
      local actionName = ui2fun(self,event)
      return onAction({deviceId=event.deviceId,actionName=actionName,args=event.values})
    end
    --Debug(_debugFlags.UIEvent,"UIEvent: %s",json.encode(event))
    if _debugFlags.UIEvent then print("UIEvent: "..json.encode(event)) end
    if parent.UIHandler then return parent:UIHandler(event) end
    local actionName = ui2fun(self,event)
    if actionName then return self:callAction(actionName, event) end
    error(format("UI callback for element:%s not found.", event.elementName))
  end

  local function vars2keymap(vars)
    local vs = {}
    for _,v in ipairs(vars) do vs[v.name]=v.value end
    return vs
  end

  local function vars2list(vars)
    local vs = {}
    for n,v in pairs(vars) do vs[#vs+1]={name=n,value=v} end
    return vs
  end

  local resources = {}
  local function loadResourceFromQA(id)
    if resources[id] then return resources[id].properties end
    resources[id] = api.getHC3("/devices/"..id)
    assert(resources[id],"No such  QA, deviceId:"..id)
    return resources[id].properties   
  end

  local function loadResources(self) -- quickVars, UI
    if not self.resources then return end
    assert(type(self.resources)=='table',"resources need to be a table")
    for p,v0 in pairs(self.resources) do
      local v = tonumber(v0) and loadResourceFromQA(tonumber(v0)) or v0
      if p=='quickVars' then
        self.quickVars = self.quickVars or {}
        for n,v in pairs(vars2keymap(v.quickAppVariables or {})) do self.quickVars[n]=v end
      elseif p == 'UI' then
        self.viewLayout = v.viewLayout
        self.uiCallbacks = v.uiCallbacks
      end
    end
  end

  local function resolveCREDS(quickVars)
    for k,v in pairs(quickVars) do
      assertf(type(k)=='string',"Corrupt quickVars table, key=%s, value=%s",k,json.encode(v))
      if type(v)=='string' and v:match("^%$CREDS") then
        v = hc3_emulator.credentials[v:match("^%$CREDS%.(.*)")]
      end
      quickVars[k]=v
    end
  end

  local function findFirstCodeLine(code,name)  -- Try to find first code line
    local n,first,init = 1
    for line in string.gmatch(code,"([^\r\n]*)[\r\n]?") do
      if not (line=="" or line:match("^[%-%s]+")) then 
        if not first then first = n end
      end
      if line:match("%s*QuickApp%s*:%s*onInit%s*%(") then
        if not init then init = n end
      end
      n=n+1
    end
    --print(name,tostring(first),tostring(init))
    return first or 1,init
  end



-- 2 types of QuickApps, fqa based and emu based  
  local function LQAcreate(self,arg,code)
    assert(type(arg)=='number' or type(arg)=='string',"Bad argument  to loadQA")

    if tonumber(arg) then                                        -- Download QA from HC3 (fqa)
      self.fqa = api.getHC3("/quickApp/export/"..arg)
      assert(self.fqa,"QA "..arg.." does not exists on HC3")
      self.id = arg
    end
    if type(arg)=='string' and arg:match("^http[s?]://") then    -- From URL (authentication????)
      local f = OS.file.downloadFile(arg)
      assert(f,"No such QA url - "..arg)
      code = f
      self.fqa = json.decode(code)    
    elseif type(arg)=='string' and arg:match("%.[Ff][Qq][Aa]$") then  -- Read in .fqa  file
      code = code or ff.read(arg)
      self.fname = arg
      self.fqa = json.decode(code)
      self.file_fqa = arg
    end
    if self.fqa then
      local fqa = self.fqa
      assert(fqa.apiVersion == "1.2","Bad FQA api version")
      self.type = fqa.type
      self.name = fqa.name
      self.viewLayout = fqa.initialProperties.viewLayout
      self.uiCallbacks = fqa.initialProperties.uiCallbacks
      self.quickVars = vars2keymap(fqa.initialProperties.quickAppVariables or {})
      self.interfaces = fqa.initialInterfaces
      loadResources(self)
    elseif arg:match("%.[Jj][Ss][Oo][Nn]$") then                 -- Read in unpacked file(s)
      self.fname = arg
      self.file_unpacked = arg
      local name = ff.extract_name(arg)
      local dir = arg:sub(1,-(name:len()+1))
      local files,paths = {},{}
      local prefix = "^"..name:match("(.*)%.[Jj][Ss][Oo][Nn]$").."_(%d+)_(.-)%.lua"
      assert(ff.dir(dir),"Not a directory: "..tostring(dir))
      for d,n in ff.dir(dir) do -- read unpacked files
        if d:match(prefix) then
          local id,name = d:match("(%d+)_([^_]+)%.lua")
          assert(name,"Bad unpacked file "..d)
          local content  = ff.read(dir..d)
          files[tonumber(id)]={name=name, content=content, type="lua", isMain=name == 'main', isOpen=false}
          paths[name]=dir..d
        end
      end
      assert(files[1],"No code files belonging to "..name)
      local fqa = ff.read(arg) -- read main json files
      fqa = json.decode(fqa)
      self.name = fqa.name
      self.type = fqa.type
      self.viewLayout = fqa.initialProperties.viewLayout
      self.uiCallbacks = fqa.initialProperties.uiCallbacks
      self.quickVars = vars2keymap(fqa.initialProperties.quickAppVariables or {})
      self.interfaces = fqa.initialInterfaces
      self.fqa = fqa
      self.fqa.files = files
      self.paths = paths
      loadResources(self)
    elseif arg:match("%.[Ll][Uu][Aa]$") then                     -- Read in "emulator" file
      self.fname = arg
      self.file_emu = arg
      code = code or ff.read(arg) -- hack, code is already loaded by caller, should be arg?
      local header,env1 = code:match("(if%s+dofile.-[\n\r]%s*end%s*%-%-[hH][cC]3)"),{
        dofile=function() end, require=require,
      }
      assert(header and header~="","Malformed emulator header, forgot 'end--hc3'?")
      local e1,msg = load(header,nil,nil,env1)
      if msg then error("Error in emulator header, forgot 'end--hc3'?:"..msg) end
      local stat,res = pcall(e1)
      if not stat then error("Error in emulator header, forgot 'end--hc3'?:"..res) end
      env1.hc3_emulator = env1.hc3_emulator or {}
      self.name = env1.hc3_emulator.name or arg:match("([%w%s_%-]+)%.[Ll][Uu][Aa]$")
      self.type = env1.hc3_emulator.type or "com.fibaro.binarySwitch"
      self.baseType = env1.hc3_emulator.baseType
      self.fullLua = env1.hc3_emulator.fullLua
      hc3_emulator.credentials = hc3_emulator.credentials or {}
      for k,v in pairs(env1.hc3_emulator.credentials or {}) do 
        hc3_emulator.credentials[k]=v
      end
      self.id = env1.hc3_emulator.id
      self.interfaces = env1.hc3_emulator.interfaces
      self.resources = env1.hc3_emulator.resources
      self.proxy = env1.hc3_emulator.proxy or false
      self.debug = env1.hc3_emulator.debug or self.debug
      loadResources(self)
      self.quickVars = self.quickVars or {}
      for n,v in pairs(env1.hc3_emulator.quickVars or {}) do
        self.quickVars[n]=v
      end
      self.UI = env1.hc3_emulator.UI
      if type(self.UI) == 'string' then self.UI = json.decode(self.UI) end
      self.files,self.paths = createFilesFromSource(code,self.fname)
    else error("Bad argument to loadQA") end
    return self
  end

--  Inject args -- overwriting existing args
  local function LQAargs(self,args)
    local function copyFrom(a,b)
      if type(a)=='table' and type(b)=='table' then
        for k,v in pairs(a) do b[k]=copyFrom(v,b[k]) end
        return b
      else return a end
    end
    copyFrom(args,self)
    return self 
  end

-- Saving file in filesystem. We can save in .fqa or "unpacked" format
  local function LQAsave(self,fm,path,overwrite)
    assert(({fqa=true,unpacked=true})[fm or ""],"Bad format for save")
    path = path or ""
    local fqa = self.fqa
    if fm == "fqa" then        -- Save as .fqa
      if not(fqa or (self.viewLayout and self.uiCallbacks)) then
        fqa = QA.createQuickApp{
          name=self.name,type=self.type,UI=self.UI,
          quickVars=self.quickVars,code=self.files,dryrun=true
        }
      end
      if fqa then
        fqa.name = self.name
        fqa.type = self.type
        fqa.initialProperties.viewLayout = self.viewLayout or fqa.initialProperties.viewLayout
        fqa.initialProperties.uiCallbacks = self.uiCallbacks or fqa.initialProperties.uiCallbacks
        if self.quickVars then
          fqa.initialProperties.quickAppVariables = vars2list(self.quickVars or {})
        end
        local fn = self.fname
        if fn then fn = fn:match("(.+)%.")..".fqa" end
        fn =  (fn or fqa.name ..".fqa"):gsub("(%/)","_")
        path  = path or ""
        if path ~= "" and path:sub(-1) ~= ff.path_separator then
          fn = ff.extract_name(path)
          path = path:sub(1,-(fn:len()+1))
        end
        self.file_fqa = fn
        ff.write(path..fn,json.encode(fqa),overwrite)
      else
        error("Can't save fqa")
      end
    else                      -- Save in unpacked format (files separatly)
      if path:sub(-1) == ff.path_separator then
        path = path.."QA_"..(self.id or "999").."_"..self.name:gsub("(%/)","_")
      elseif path:match("%.[Jj][Ss][Oo][Nn]$") then
        path = path:match("(.*)%.")
      end
      local paths = {}
      for i,f in ipairs(self.files or self.fqa.files or {}) do
        local name = path.."_"..i.."_"..f.name:gsub("(%/)","_")..".lua"
        ff.write(name,f.content,overwrite)
        paths[f.name]=name
      end
      self.paths = paths
      local fqa = Util.copy(self.fqa)
      fqa.files = nil
      self.file_unpacked = ff.extract_name(path..".json")
      ff.write(path..".json",Util.prettyJsonFormat(fqa),overwrite)
    end
    return self
  end -- save

--  Upload QuickApp to HC3
  local function LQAupload(self,name,id)
    -- Resolve $CREDS
    resolveCREDS(self.quickVars)
    if self.fqa or (self.viewLayout and self.uiCallbacks) then
      QA.createQuickApp{
        name=name or self.name,type=self.type, id = id or self.id,
        initialProperties = {
          viewLayout=self.viewLayout, 
          uiCallbacks = self.uiCallbacks, 
          quickAppVariables = vars2list(self.quickVars or {}),
        },
        interfaces = self.interfaces,
        code=self.files or self.fqa.files
      }
    else
      QA.createQuickApp{
        name=name or self.name,type=self.type,UI=self.UI, id = id or self.id,
        quickVars=self.quickVars,code=self.files, interfaces = self.interfaces,
      }
    end
    return self
  end

-- Install QuickApp in the emulator
  function LQAinstall(self,args)
    -- A QA is a 7 step process
    -- 0. Initialization
    -- 1. Create proxy if wanted
    -- 2. Create environment
    -- 3. Load the files (not executing them)
    -- 4. Build device struct
    -- 5. Run the QA files, main last (execute them)
    --    The loading of files/users are expected to define the QuickApp methods incl. QuickApp:onInit()
    -- 6. We create an instance of QuickApp and call the :onInit method if it exists
    -- Restarting QA means kill timers and go back to 2

    assert(not(tonumber(self.id) and self.proxy),"Can't specify both id and proxy")
    assert(not(self.offline and self.proxy),"Can't specify both offline and proxy")
    Timer.setSystemTimeout(function()
        --os.setTimer(function()
        --Timer.kick()
        --hc3_emulator.dumpTimers()
        Log(LOG.HEADER,"Loading QuickApp '%s'...",self.name)

        -- step 0. initialization, fix missing structures etc.
        local pdevice

        local fl = false
        local interfaces = self.interfaces or {'quickApp'}
        for _,i in ipairs(interfaces) do if i=='quickApp' then fl=true; break end end
        if not fl then interfaces[#self.interfaces+1]='quickApp' end

        -- Initialize quickAppVariables and load resources
        -- Logic:
        --- First variables from fqa if they exists
        --- Then variables from loaded hc3_emulator.resources = {quickVars = ...
        --- Then variables from hc3_emulator.quickVars
        local quickVars = self.quickVars
        -- Resolve $CREDS
        resolveCREDS(quickVars)

        if self.UI then
          local ip = makeInitialProperties(self.UI)
          self.viewLayout,self.uiCallbacks = ip.viewLayout,ip.uiCallbacks
        elseif self.viewLayout then
          self.UI=QA.view2UI(self.viewLayout,self.uiCallbacks)
        elseif self.UI==nil then
          self.UI = {} 
          local ip = makeInitialProperties(self.UI)
          self.viewLayout,self.uiCallbacks = ip.viewLayout,ip.uiCallbacks
        end
        -- step 1. create proxy
        if self.proxy and not self.offline then
          if tonumber(self.proxy) then
            if api.getHC3("/quickApp/"..self.proxy.."/files/PROXY") == nil then
              pdevice = injectProxy(self.proxy)
              Log(LOG.LOG,"Connecting to QA %s, injecting new PROXY",self.proxy)
            else
              Log(LOG.LOG,"Connecting to QA %s, using existing PROXY",self.proxy)
              pdevice = api.getHC3("/devices/"..self.proxy)
            end
            startProxyPinger()
          else
            pdevice = createProxy(self.name,self.type,
              {
                viewLayout=self.viewLayout,
                uiCallbacks = self.uiCallbacks, 
                quickAppVariables = vars2list(quickVars)
              },
              interfaces)
          end
        end

        if pdevice then self.id = pdevice.id else 
          while self.id == nil or quickApps[self.id] do -- find free id
            self.id = Local.getNextDeviceID()
          end
        end

        -- Now we have deviceID!!! Setup files in /quickApp/../files
        files[self.id]={} -- This struct is used for /api/quickApp/...
        self.paths = self.paths or {}
        for _,f in ipairs(self.files or self.fqa and self.fqa.files) do

          files[self.id][f.name]={name=f.name,content=f.content,type='lua',isOpen=false,isMain=f.isMain==true}
          if self.paths[f.name] == nil then -- Store code without files in tmp/...
            local p = ff.tmp_name(f.name,Util.crc16(f.content))
            if ff.exists(p) then
              self.paths[f.name]=p
              f.content = ff.read(p)
            else
              if pcall(function() ff.write(p,f.content,true,true) end) then
                self.paths[f.name]=p
              end
            end
          end
        end
        filePaths[self.id]=self.paths

        local runQA,codeEnv
        local function restartQA()
          collectgarbage("collect")
          Log(LOG.SYS,"Restarting QA %s, timers=%s, memory used %.1fkB",
            self.id,Timer.killTimers("QUICKAPP"..self.id),collectgarbage("count")
          ) 
          codeEnv._ENVID=nil
          --os.setTimer(function() runQA('DeviceModifiedEvent') end,0)
          runQA('DeviceModifiedEvent')
        end

        local function deleteQA()
          collectgarbage("collect")
          Log(LOG.SYS,"Deleting QA %s, timers=%s, memory used %.1fkB",
            self.id,Timer.killTimers("QUICKAPP"..self.id),collectgarbage("count")
          )
          codeEnv._ENVID=nil
          quickApps[self.id]=nil
          Trigger.postTrigger({type='DeviceRemovedEvent', data = {id = self.id}},0)
        end

        quickVarsReal = vars2list(quickVars)

        function runQA(event) -- rest of the steps in a function that can be called
          -- step 2. create the environment
          codeEnv = Util.createEnvironment("QA",self.fullLua)
          self._codeEnv = codeEnv
          setContext(codeEnv)
          local QAlock = copas.lock.new(60*60*30)
          function codeEnv._getLock() QAlock:get(60*60*30) end
          function codeEnv._releaseLock() QAlock:release() end
          codeEnv._ENVID = "QUICKAPP"..self.id -- used to find timers beloning to this QA
          codeEnv.plugin.mainDeviceId = self.id
          local st = codeEnv.setTimeout
          local function errHandler(err)
            Log(LOG.ERROR,"QuickApp timer %s for '%s', deviceId:%s, crashed - %s",codeEnv._lastTimer,self.name,self.id,err)
            if _debugFlags.breakOnError then hc3.mobdebug.pause() end
          end
          codeEnv.setTimeout = function(fun,ms,tag,eh,env,off) return st(fun,ms,tag,errHandler,codeEnv,off) end
          local st2 = codeEnv.setTimeout
          codeEnv.fibaro.setTimeout = function(a,b,...) return st2(b,a,...) end
          codeEnv.print = function(...) codeEnv.fibaro.debug(codeEnv.__TAG,...) end
          codeEnv.__TAG = "QuickApp"..self.id
          codeEnv.setTimeout(function() end,2000)
          -- Step 3. load the files (we don't run them yet)
          local loadedFiles = {}
          self.paths = self.paths or {}
          local ost,ostf,jsenc,jsdec = codeEnv.setTimeout, codeEnv.fibaro.setTimeout,codeEnv.json.encode,codeEnv.json.decode
          for _,f in pairs(QA.files[self.id]) do
            if f.name ~= 'PROXY' then
              local path = filePaths[self.id][f.name] or f.name
              if _debugFlags.files then Log(LOG.LOG,"Loading file '%s' in %s",f.name,self.name) end
              local code,msg=load(f.content,path,"bt",codeEnv)
              assert(code,msg)
              if f.isMain then table.insert(loadedFiles,{code=code,content=f.content,name=f.name,isMain=true}) -- 'main' last
              else  table.insert(loadedFiles,math.max(#loadedFiles,1),{code=code,content=f.content,name=f.name}) end
            end
          end

          -- Step 4. build device struct
          -- Add 'quickApp' to interfaces if not existing

          pdevice = pdevice or Local.getDeviceTemplate(self.type,self.baseType)
          if pdevice == nil then
            Log(LOG.WARNING,"QA %s missing template, device structure is set to generic. Set baseType to get template.",self.type)
            pdevice = {}
          end

          local device = pdevice
          device.id = device.id or self.id
          device.name = self.name or "QuickApp"..self.id
          device.interfaces = device.interfaces or interfaces
          device.enabled = true
          device.visible = true
          device.type = device.type or self.type
          device.roomID = device.roomID or 219
          device._proxy = self.proxy
          device._env = codeEnv
          device.properties = device.properties or {}
          device.properties.uiCallbacks = self.uiCallbacks
          device.properties.viewLayout = self.viewLayout
          device.properties.quickAppVariables = quickVarsReal
          Local.gLoc.devices[device.id]=device -- register it as a device

          -- step 5. run the files
          for _,f in ipairs(loadedFiles) do
            local path = self.paths[f.name] or f.name
            if (_debugFlags.breakOnLoad or _debugFlags.breakOnInit) and self.paths[f.name] then 
              local first,init = findFirstCodeLine(f.content,f.name)
              if _debugFlags.breakOnLoad then hc3.mobdebug.setbreakpoint(path,first) end
              if _debugFlags.breakOnInit and init then hc3.mobdebug.setbreakpoint(path,init) end
            end
            if _debugFlags.files then Log(LOG.LOG,"Running file '%s' in %s",f.name,self.name) end
            local stat42,res42 = xpcall(f.code,function(err)
                Log(LOG.ERROR,"Running %s - %s",path or "",err or "")
                print(debug.traceback(err,2))
              end)
            if not stat42 then error(res42) end
          end
          if not _debugFlags.patchSetTimeout then -- restore setTimeout etc if pacthed by user
            codeEnv.setTimeout,codeEnv.fibaro.setTimeout =  ost,ostf
          end

          -- step 6. instantiate QA
          codeEnv._getLock()
          local status, err, ret = xpcall(
            function() 
              self.VERSION=(self.VERSION or 0)+1
              codeEnv._VERSION=format("QA%s:%s",self.id,self.VERSION) 
              Log(LOG.HEADER,"QuickApp '%s', deviceID:%s started at %s",device.name,device.id,os.date("%c"))
              Trigger.postTrigger({type=event, data = {id = self.id}, sourceType="system"},0)
              codeEnv.quickApp = codeEnv.QuickApp(device)
              hc3._SYNC = false
              quickApps[self.id] = codeEnv.quickApp
            end,
            function(err)
              Log(LOG.ERROR,"QuickApp '%s', deviceId:%s, crashed (%s) at %s",self.name,self.id,err,os.date("%c"))
              print(debug.traceback(err))
              if _debugFlags.breakOnError then hc3.mobdebug.pause() end
            end)
          codeEnv._releaseLock()
          codeEnv.quickApp.restartQA = restartQA
          codeEnv.quickApp.deleteQA = deleteQA
          codeEnv.quickApp.runQA = runQA
        end
        runQA('DeviceCreatedEvent')

      end,0) -- os.setTimer
    return self
  end -- install

  local function loadQA(arg,code) return LQAcreate({args=LQAargs,save=LQAsave,upload=LQAupload,install=LQAinstall},arg,code) end

  function hc3_emulator.loadQAorScene(file)
    local code,done = OS.file.read(file),nil
    if code:match("hc3_emulator%.actions") then
      hc3.module.Scene.loadScene(file,code):upload()
    elseif code:match("QuickApp:") or code:match("QuickerApp:") then
      QA.loadQA(file,code):upload()
    else
      Log(LOG.LOG,"Unrecognized file")
    end
  end

  commandLines['deploy']=function(file)
    -- print(json.encode(hc3_emulator.credentials))
    hc3_emulator.loadQAorScene(file)
    fibaro.sleep(2000)
    os.exit()
  end

-- Export functions
  self.transformUI = transformUI
  self.uiStruct2uiCallbacks = uiStruct2uiCallbacks
  self.updateViewLayout     = updateViewLayout
  self.createQuickApp       = createQuickApp
  self.createProxy          = createProxy
  self.loadQA               = loadQA
  return self
end--module QuickApp

--------------- Scene functions and support ----------
function module.Scene(hc3)
  local self = {scenes = {}}
  local Util,Timer,Trigger,OS=hc3.module.Util
  local _debugFlags = hc3.debug
  local ff,printf,fibaro,__fibaro_get_device_property
  local scenes = self.scenes

  Log,LOG,json,api,net,assert,assertf=Log,LOG,json,api,net,assert,assertf

  function self.initialise() --luacheck: ignore
    Timer,Trigger,OS = hc3.module.Timer,hc3.module.Trigger,hc3.module.OS
    fibaro,ff,printf = hc3.module.Fibaro.fibaro,OS.file,Util.printf
    __fibaro_get_device_property = hc3.module.Fibaro.__fibaro_get_device_property
  end

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
      local seq = dateStr:split(" ")   -- min,hour,day,month,wday
      local lim = {{min=0,max=59},{min=0,max=23},{min=1,max=31},{min=1,max=12},{min=1,max=7},{min=2019,max=2030}}
      for i=1,6 do if seq[i]=='*' or seq[i]==nil then seq[i]=tostring(lim[i].min).."-"..lim[i].max end end
      seq = map(function(w) return w:split(",") end, seq)   -- split sequences "3,4"
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
        local h,m = (fibaro.getValue(1,sun)):match("(%d%d):(%d%d)")
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
      ['device:centralSceneEvent'] = function(c,_)
        local id,keyAttribute,keyId = c.id,c.value.keyAttribute,c.value.keyId
        if c.isTrigger then triggers[id] = c.property end
        return function(ctx)
          ctx=ctx.centralSceneEvent or {}
          return id == ctx.id and ctx.value.keyId == keyId and ctx.value.keyAttribute == keyAttribute
        end
      end,
      ['global-variable:*'] = function(c,_)
        local name,value,comp = c.property,c.value,condCompFuns[c.operator]
        if c.isTrigger then triggers[name] = true end
        return function(_)
          local cv = fibaro.getGlobalVariable(name)
          return comp(cv,value)
        end
      end,
      ['date:sunset'] = function(c,all)
        local comp,offset = condCompFuns["n"..c.operator],c.value
        local function mkRes(_) return {type='date', property='sunset', value=offset} end
        local test = function(ctx) if comp(ctx.hour*60+ctx.min,ctx.sunset+offset) then return mkRes(ctx) end end
        if c.isTrigger then dates[#dates+1]=function(ctx) if all[1] then return all[1](ctx) and mkRes(ctx) else return test(ctx) end end end
        return test
      end,
      ['date:sunrise'] = function(c,all)
        local comp,offset = condCompFuns["n"..c.operator],c.value
        local function mkRes(_) return {type='date', property='sunrise', value=offset} end
        local test = function(ctx) if comp(ctx.hour*60+ctx.min,ctx.sunrise+offset) then return mkRes() end end
        if c.isTrigger then dates[#dates+1]=function(ctx) if all[1] then return all[1](ctx) and mkRes(ctx) else return test(ctx) end end end
        return test
      end,
      ['date:cron'] = function(c,all)
        local test,_ = cronTest(table.concat(c.value," ")),condCompFuns[c.operator]
        local function mkRes(ctx) return {type='date', property='cron', value={ctx.min, ctx.hour, ctx.day, ctx.month, ctx.wday, ctx.year}} end
        local cronFun = function(ctx) if test(ctx) then return mkRes(ctx) end end
        if c.isTrigger then
          dates[#dates+1] = function(ctx) if all and all[1] then return all[1](ctx) and mkRes(ctx) else return cronFun(ctx) end end
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
      error(string.format("Bad condition:%s (%s)",json.encode(c),json.encode(cf)))
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

  local SceneID = 800

  local function loadScene(arg,code)
    assert(type(arg)=='number' or type(arg)=='string',"Bad argument  to loadScene")
    local self,ff = {},OS.file
    if tonumber(arg) then                          -- Download from HC3
      self._scene = api.get("/scenes/"..arg)
      assert(self._scene,"Scene ID "..arg.."  does not exist on HC3")
      self.id = arg
    elseif type(arg)=='string' and arg:match("%.[Ff][Ss][Cc]$") then       -- Read .fsc file
      local s = ff.read(arg)
      self._scene = json.decode(s)
      self.fname = arg
      self.file_scene = arg
    end
    if self._scene then 
      self.name = self._scene.name
    elseif arg:match("%.[Ll][Uu][Aa]$") then       -- Read emulator file
      self.fname = arg
      self.file_emu = arg
      code = code or ff.read(arg)
      local header,env1 = (code:match("(if%s+dofile.-end%s*%-%-[hH][cC]3)")),{
        dofile=function() end, require=require,
      }
      assert(header and header~="","Malformed emulator header, forgot 'end--hc3'?")
      local e1,msg = load(header,nil,nil,env1)
      if msg then error(msg) end
      local stat,res = pcall(e1)
      if not stat then error(res) end
      self.name = env1.hc3_emulator.name or arg:match("(.-)%.[Ll][Uu][Aa]$")
      self.id = env1.hc3_emulator.id
      self.runSceneAtStart = env1.hc3_emulator.runSceneAtStart
      self.fullLua = env1.hc3_emulator.fullLua
      self.code = code
      local conditions = code:match("hc3_emulator%.conditions%s*=%s*(%b{})")
      local actions = code:match("hc3_emulator%.actions%s*%(%s*%)(.*)end")
      self.content=json.encode({conditions=json.encode(conditions),actions=actions})
    elseif arg:match("%.[Jj][Ss][Oo][Nn]$") then   -- Read in unpacked file(s)
      self.fname = arg
      self.file_unpacked = arg
      local name = ff.extract_name(arg)
      --local dir = arg:sub(1,-(name:len()+1))
-----
      local j = f.read(arg)
      j = json.decode(j)
      self.name = j.name
      ----
    else error("Bad argument to loadScene") end

    -- Saving file in filesystem. We can save in .fsc or "unpacked" format
    function self:save(fm,path,overwrite)
      assert(({fsc=true,unpacked=true})[fm or ""],"Bad format for save")
      if fm == 'fsc' then
        if not self._scene then
          local scene = {
            id = self.id, name = self.name, type =  "lua", mode = "automatic", maxRunningInstances = 2,
            icon = "scene_lua", hidden = false, protectedByPin= false, stopOnAlarm= false,
            restart= true, enabled = true, created = os.time(), updated = os.time(),
            isRunning = false, started = os.time(), categories = {1}
          }
          scene.content = self.content
          self._scene = scene
        end
        local fn = self.fname
        if fn then fn = fn:match("(.+)%.")..".fsc" end
        fn =  (fn or self._scene.name ..".fsc"):gsub("(%/)","_")
        path  = path or ""
        if path~="" and path:sub(-1) ~= ff.path_separator then
          fn = ff.extract_name(path)
          path = path:sub(1,-(fn:len()+1))
        end
        self.file_fsc = fn
        ff.write(path..fn,json.encode(self._scene),overwrite)
      elseif fm == 'unpacked' then
        error("Saving unpacked scenes not implemented yet")
      end
    end

    --  Inject args
    function self:args(args) for k,v in pairs(args) do self[k]=v end return self end

    --  Upload Scene to HC3
    function self:upload(name,id)
      if not self._scene then
        error("Not yet implemented")
      end
      self.id = id or self.id
      self._scene.name = name or self._scene.name
      if self.id and tonumber(self.id) then
        local s = Util.copy(self._scene)
        s.id,s.created,s.updated,s.isRunning=nil,nil,nil,nil
        local _,res = api.put("/scenes/"..self.id,s)
        if res == 204 then
          Log(LOG.LOG,"Scene '%s', ID:%s updated",self._scene.name,self.id)
        else
          Log(LOG.LOG,"Error updating scene '%s', %s",self._scene.name,res)
        end
      else
        local stat,res = api.post("/scenes",self._scene)
        if res == 201 then
          Log(LOG.LOG,"Scene '%s', ID:%s uploaded",self._scene.name,stat.id)
        else
          Log(LOG.LOG,"Error uploading scene '%s', %s",self._scene.name,res)
        end
      end
      return self
    end

    --  Install Scene in emulator
    function self:install()

      local codeEnv = Util.createEnvironment("Scene",self.fullLua)

      os.setTimer(function()

          if self.code then -- emu
            if _debugFlags.breakOnLoad then hc3.mobdebug.setbreakpoint(self.fname,1) end
            local _,msg=load(self.code,self.fname,"bt",codeEnv)()
            assert(msg==nil,string.format("Loading %s - %s",self.fname,msg))
            self.conditions = codeEnv.hc3_emulator.conditions
            self.actions = codeEnv.hc3_emulator.actions
          elseif self._scene then
            local c = json.decode(self._scene.content)
            self.conditions = load("return "..c.conditions)()
            self.actions = load(c.actions,self.fname,"bt",codeEnv)
          end

          local condition,triggers,dates = compileCondition(self.conditions)

          setContext(codeEnv)
          Log(LOG.HEADER,"Loading Scene '%s'...",self.name)

          if self.id == nil then
            self.id = SceneID; SceneID=SceneID+1
          end

          codeEnv.sceneId = self.id

          codeEnv._ENVID='SCENE'..self.id
          codeEnv.tag = "Scene"..self.id
          self.timers = 0
          self.content = json.encode({
              conditions = json.encode(self.conditions),
              actions = "..."
            })

          local SceneLock = Timer.copas.lock.new(60*60*30)
          function codeEnv._getLock() SceneLock:get(60*60*30) end
          function codeEnv._releaseLock() SceneLock:release() end
          codeEnv.print = function(...) codeEnv.fibaro.debug(codeEnv.tag:upper(),...) end

          local st = Timer.setTimeout
          local function errHandler(err)
            Log(LOG.ERROR,"Scene timer %s for '%s', sceneId:%s, crashed - %s",codeEnv._lastTimer,self.name,self.id,err)
          end
          codeEnv.setTimeout = function(fun,ms,tag)
            self.timers = self.timers+1
            local function f(...)
              local stat,res = pcall(fun)
              self.timers = self.timers-1
              if self.timers <= 0 then
                self.struct.isRunning = false
                Log(LOG.HEADER,"Scene '%s', sceneId:%s, terminated at %s",self.name,self.id,os.date("%c"))
              end
              if not stat then error(res,2) end
            end
            return st(f,ms,tag,errHandler,codeEnv)
          end

          local ct1 = codeEnv.fibaro.clearTimeout
          codeEnv.fibaro.setTimeout = function(a,b,...) return codeEnv.setTimeout(b,a,...) end
          function codeEnv.fibaro.clearTimeout(ref)
            self.timers = self.timers-1
            return ct1(ref)
          end

          scenes[self.id] = self
          self.struct = {
            id = self.id, name = self.name, type =  "lua", mode = "automatic", maxRunningInstances = 2,
            icon = "scene_lua", hidden = false, protectedByPin= false, stopOnAlarm= false,
            restart= true, enabled = true, created = os.time(), updated = os.time(),
            isRunning = false, started = os.time(), categories = {1}, content = self.content
          }

          function self.run() -- A scene runs as long as it has timers
            Log(LOG.HEADER,"Scene '%s', sceneId:%s, started at %s",self.name,self.id,os.date("%c"))
            self.struct.isRunning = true
            codeEnv.fibaro.setTimeout(0,
              function() 
                codeEnv._getLock()
                local status, err, ret = xpcall(self.actions,function(err)
                    Log(LOG.ERROR,"Scene '%s', sceneId:%s, crashed (%s) at %s",self.name,self.id,err,os.date("%c"))
                    print(debug.traceback(err,1))
                    if _debugFlags.breakOnError then hc3.mobdebug.pause() end
                  end)
                codeEnv._releaseLock()
              end)
          end

          function self.killScene() 
            Log(LOG.SYS,"Killing scene %s, timers=%s",self.id,Timer.killTimers("SCENE"..self.id)) 
            self.struct.isRunning = false
            Log(LOG.HEADER,"Scene '%s', sceneId:%s, terminated at %s",self.name,self.id,os.date("%c"))
          end

          function self.eventHandler(e)
            local ctx = createCTX()
            codeEnv.sourceTrigger = nil
            if e.type=='device' and e.property=='centralSceneEvent' then
              ctx.centralSceneEvent = e
            end
            if (e.type=='user' or e.type=='manual') and e.property=='execute' then
              codeEnv.sourceTrigger = e
              self.run()
            elseif e.type=='device' and triggers[e.id]==e.property or
            e.type=='global-variable' and triggers[e.property] or
            e.type=='date'
            then
              Log(LOG.DEBUG,"Scene trigger:%s",json.encode(e))
              if condition(ctx) then
                codeEnv.sourceTrigger = e
                self.run()
              end
            end
          end -- end handleEvent

          if #dates>0 then --- Check cron expressions every minute
            local nxt = os.time()
            local function loop()
              local ctx = createCTX()
              for _,c in ipairs(dates) do
                local e = c(ctx)
                if e then
                  self.eventHandler(e); break
                end
              end
              nxt = nxt+60
              codeEnv.setTimeout(loop,1000*(nxt-os.time()),"Cron"..self.id) 
            end
            loop()
          end

          if self.runSceneAtStart then
            os.setTimer(function() self.eventHandler({type = "user", property = "execute", id=2}) end,0)
          end

        end,0)
    end

    return self
  end -- loadScene

  self.loadScene = loadScene
  return self
end--module Scene

--------------- Trigger functions and support --------
function module.Trigger(hc3)
  local selfm = {}
  local _debugFlags = hc3.debug
  local Util,Timer = hc3.module.Util
  local copas,safeDecode,colorStr,scenes

  Log,LOG,json,api,net,assert,assertf=Log,LOG,json,api,net,assert,assertf

  local ltn12   = require("ltn12")          -- LuaSocket

  function selfm.initialise()
    Timer = hc3.module.Timer
    safeDecode,colorStr = Util.safeDecode,Util.colorStr
    copas,scenes = Timer.copas,hc3.module.Scene.scenes
  end

  local cache = {  -- Caching values when we poll to reduce traffic to HC3...
    polling=false, devices={}, globals={}, 
    centralSceneEvents={},accessControlEvents={},sceneActivationEvents={}
  } 
  selfm.cacheStore=cache
  function cache.write(type,id,prop,value)
    cache[type][id] = cache[type][id] or {}
    cache[type][id][prop]=value
  end
  function cache.read(type,id,prop) 
    return hc3.speeding and hc3.polling and cache[type][id] and cache[type][id][prop]
  end

  local function post(event) 
    if hc3.supressTrigger[event.type] then return end
    if _debugFlags.trigger then Log(LOG.DEBUG,"Incoming trigger:%s",Util.prettyJson(event)) end
    for _,s in pairs(scenes) do
      if s.eventHandler then os.setTimer(function() s.eventHandler(event) end,0) end
    end
  end

  local ignoreProperties = {icon=true, mainFunction=true,uiCallbacks = true}
  local EventTypes = { -- There are more, but these are what I seen so far...
    AlarmPartitionArmedEvent = function(d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
    AlarmPartitionBreachedEvent = function(d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
    HomeArmStateChangedEvent = function(d) post({type='alarm', property='homeArmed', value=d.newValue}) end,
    HomeBreachedEvent = function(d) post({type='alarm', property='homeBreached', value=d.breached}) end,
    HomeDisarmStateChangedEvent = function(_) end,
    WeatherChangedEvent = function(d) post({type='weather',property=d.change, value=d.newValue, old=d.oldValue}) end,
    GlobalVariableChangedEvent = function(d)
      cache.write('globals',0,d.variableName,{name=d.variableName, value = d.newValue, modified=os.time()})
      if d.variableName == hc3.emu.EMURUNNING then return true end
      post({type='global-variable', name=d.variableName, value=d.newValue, old=d.oldValue})
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
        if ignoreProperties[d.property] then return end
        cache.write('devices',d.id,d.property,{value=d.newValue, modified=os.time()})
        post({type='device', id=d.id, property=d.property, value=d.newValue, old=d.oldValue})
      end
    end,
    CentralSceneEvent = function(d)
      d.id = d.id or  d.deviceId
      cache.write('centralSceneEvents',d.id,"",d)
      post({type='device', property='centralSceneEvent', id=d.id, value = {keyId=d.keyId, keyAttribute=d.keyAttribute}})
    end,
    SceneActivationEvent = function(d)
      d.id = d.id or  d.deviceId
      cache.write('sceneActivationEvents',d.id,"",d)
      post({type='device', property='sceneActivationEvent', id=d.id, value = {sceneId=d.sceneId, name=d.name}})
    end,
    AccessControlEvent = function(d) 
      cache.write('accessControlEvents',d.id,"",d)
      post({type='device', property='accessControlEvent', id = d.deviceID, value=d})
    end,
    GeofenceEvent = function(d)
      post({type='location',id=d.userId,property=d.locationId,value=d.geofenceAction,timestamp=d.timestamp})
    end,
    ActiveProfileChangedEvent = function(d)
      post({type='profile',property='activeProfile',value=d.newActiveProfile, old=d.oldActiveProfile})
    end,
    CustomEvent = function(d) post({type='custom-event', name=d.name}) end,
    PluginChangedViewEvent = function(d) end,
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
    SceneModifiedEvent = function() end,
    PluginProcessCrashedEvent = function()  end,
    onUIEvent = function(d) end,
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
    DeviceFirmwareUpdateEvent = function(_) end,
    QuickAppFilesChangedEvent = function() end,
    ZwaveDeviceParametersChangedEvent = function() end,
    ZwaveNodeAddedEvent = function() end,
    RefreshRequiredEvent = function() end,
  }

  local function checkEvents(events)
    local kills={}
    for i,e in ipairs(events) do
      if _debugFlags.trigger0 then Log(LOG.DEBUG,"Incoming trigger0:%s",Util.prettyJson(e)) end
      local eh = EventTypes[e.type]
      if eh then 
        if eh(e.data) then 
          kills[#kills+1]=i 
        end
      elseif eh==nil then Log(LOG.WARNING,"Unhandled event:%s -- please report",json.encode(e)) end
    end
    for i=#kills,1,-1 do table.remove(events,kills[i]) end
    if #events > 0 then selfm.refreshStates.addEvents(events) end
  end

  local lastRefresh = 0

  local function pollOnce() -- Doesn't work, we need predictable returns
    local resp = {}
    local req={
      method="GET",
      url = "http://"..hc3.credentials.ip.."/api/refreshStates?last=" .. lastRefresh.."&lang=en&rand=0.09580020181569104&logs=false",
      sink = ltn12.sink.table(resp),
      user=hc3.credentials.user,
      password=hc3.credentials.pwd,
      headers={}
    }
    req.headers["Accept"] = '*/*'
    req.headers["X-Fibaro-Version"] = 2
    local r, c, h = copas.http.request(req)       -- ToDo https
    if not r then return nil,c, h end
    if c>=200 and c<300 then
      local states = resp[1] and json.decode(table.concat(resp))
      if states then
        lastRefresh=states.last
        if states.events and #states.events>0 then
          local events = states.events
          if _debugFlags.refreshloop then Log(LOG.LOG,"/refresh #%s",#events) end
          checkEvents(events) 
        end
        if  states.alarmChanges then
          print(json.encode(states.alarmChanges))
        end
      end
    end
    return nil,c, h
  end

  local function pollEvents(interval)
    local INTERVAL = interval or 0 -- every second, could do more often...
    cache.polling = true -- Our loop will populate cache with values - no need to fetch from HC3
    local function pollRefresh()
      pollOnce()
      os.setTimer(pollRefresh,INTERVAL)--,"RefreshState")
    end
    os.setTimer(pollRefresh,0)
  end

  function selfm.postTrigger(ev,t)
    assert(type(ev)=='table' and ev.type,"Bad event format:"..json.encode(ev))
    t = t or 0
    local f = t==0 and (function(f) f() end) or os.setTimer 
    f(function() checkEvents({ev}) end,t)
  end

--------------- refreshState handling ---------------
  local function createRefreshStateQueue(size)
    local self = {}

    function mkQueue(size)
      local queue,dump,pop = {}
      local tail,head = 301,301
      local function empty() return tail==head end
      local function filled() return head-tail >= size end
      local function push(e)
        if filled() then pop() end
        head=head+1
        local key = tostring(head)
        queue[key]=e
        --print(e,dump(),head,tail)
      end
      local function tailp() return tail end
      local function headp() return head end
      function pop()
        if empty() then return nil end
        tail=tail+1
        local key = tostring(tail)
        local v = queue[key]
        queue[key]=nil
        return v
      end
      local function peek(n) return queue[tostring(head-n)] end
      local function get(n) return queue[tostring(n)] end
      function dump()
        local res={}
        for i=0,size-1 do 
          local e=peek(i)
          if e then res[#res+1]=json.encode(e) end
        end
        return table.concat(res,",")
      end
      return { pop = pop, push = push, tailp=tailp, headp=headp, empty=empty, peek = peek, get=get, dump=dump }
    end

    self.eventQueue=mkQueue(size) --- 1..QUEUELENGTH
    local eventQueue = self.eventQueue

--    local function filter(events)
--      local res = {}
--      for _,e in ipairs(events) do res[#res+1]=e.type end
--      return res
--    end

    function self.addEvents(events) -- {last=num,events={}}
      events = events[1] and events or {events}
      --print("ADD:"..json.encode(filter(events)))
      local index = eventQueue.headp()
      eventQueue.push({last=index, events=events})
    end

    function self.getEvents(last)
      --print(eventQueue.dump())
      if eventQueue.empty() then return {last = last } end
      local res1,res2,i = {},{},0
      while true do
        local e = eventQueue.peek(i)     ----    5,6,7,8    6
        if e and e.last > last then
          res1[#res1+1]=e
        else break end
        i=i+1
      end
      if #res1==0 then return { last=last } end
      last = res1[1].last   ----  { 1, 2, 3, 4, 5}
      for j=1,#res1 do
        local es = res1[j].events
        if es then for k=1,#es do res2[#res2+1]=es[k] end end
      end
      --print("RET:"..json.encode(filter(res2)))
      return {last = last, events = res2}
    end
    self.dump = eventQueue.dump
    return self
  end

  selfm.refreshStates = createRefreshStateQueue(200)

  selfm.eventTypes = EventTypes
  selfm.startPolling = pollEvents
  selfm.pollOneEvent = pollOnce
  selfm.checkEvents = checkEvents
  selfm.cache = cache
  return selfm
end--module Trigger

-------------- Utilities -----------------------------
function module.Utilities(hc3)
  local self = {}
  local format = string.format
  local _debugFlags = hc3.debug
  --[[
  Util.assert(value,errmsg)
  Util.assertf(value,errmsg,...)
  Util.class(name)
  Util.property(getter,setter)
  Util.urlencode(str)
  Util.urldecode(str)
  Util.safeDecode(x)
  Util.ZBCOLORMAP
  Util.LOG = {}
  Util.Log(flag,arg1,...)
  Util.parseDate(dateStr) --- Format 10:00:00 5/12/2020
  Util.printf(fmt,...)
  Util.map(f,l)      -- function(e) x list -> list
  Util.mapf(f,l)     -- function(e) x list -> nil
  Util.mapk(f,l)     -- function(k,v) x list -> list
  Util.mapkv(f,l)
  Util.member(k,tab)
  Util.copy(obj)
  Util.equal(e1,e2)
  Util.transform(obj,tf)
  Util.prettyJson(expr)
  Util.prettyJsonFormat(expr)
  Util.traceFibaro()
  Util.crc16(bytes)
  Util.base64(str)
  Util.getIPaddress()
  Util.sunCalc(time) -> sunrise,sunset,down,dusk
  --]]

  local function assert(value,errmsg) if not value then error(errmsg,3) end end
  local function assertf(value,errmsg,...)
    if not value then
      local args = {...}
      if #args==0 then error(errmsg,3) else error(format(errmsg,...),3) end
    end
  end
  self.assert,self.assertf = assert,assertf

  -- Class support
  local metas = {}
  for _,m in ipairs({
      "__add","__sub","__mul","__div","__mod","__pow","__unm","__idiv","__band","__bor",
      "__bxor","__bnot","__shl","__shr","__concat","__len","__eq","__lt","__le","__call",
      "__tostring"
      }) do
    metas[m]=true
  end

  function self.property(get,set)
    assert(type(get)=='function' and type(set)=="function","Property need function set and get")
    return {['%CLASSPROP%']=true, get=get, set=set}
  end

  local function trapIndex(props,cmt,obj)
    function cmt.__index(tab,key)
      if props[key] then return props[key].get(obj) 
      else return rawget(obj,key) end
    end
    function cmt.__newindex(tab,key,val)
      if props[key] then return props[key].set(obj,val) 
      else return rawset(obj,key,val) end
    end
  end

  function self.class(name)       -- Version that tries to avoid __index & __newindex  to make debugging easier
    local cl,mt,cmt,props,parent= {['_USERDATA']=true},{},{},{}  -- We still try to be Luabind class compatible
    function cl.__copyObject(cl,obj)
      if parent then parent.__copyObject(parent,obj) end
      for k,v in pairs(cl) do
        if metas[k] then cmt[k]=v else obj[k]=v end
      end
      return obj
    end
    function mt.__call(tab,...)        -- Instantiation  <name>(...)
      local obj = tab.__copyObject(tab,{})
      if not tab.__init then error("Class "..name.." missing initialiser") end
      tab.__init(obj,...)
      local trapF = false
      for k,v in pairs(obj) do
        if type(v)=='table' and v['%CLASSPROP%'] then obj[k],props[k]=nil,v; trapF = true end
      end
      if trapF then trapIndex(props,cmt,obj) end
      local str = "Object "..name..":"..tostring(obj):match("%s(.*)")
      setmetatable(obj,cmt)
      if not obj.__tostring then 
        function obj:__tostring() return str end
      end
      return obj
    end
    function mt:__tostring() return "class "..name end
    setmetatable(cl,mt)
    getContext()[name] = cl
    return function(p) -- Class creation -- class <name>
      parent = p 
    end 
  end

  function self.class(name)       -- Version that tries to avoid __index & __newindex  to make debugging easier
    local cl,mt,cmt,props,parent= {['_USERDATA']=true},{},{},{}  -- We still try to be Luabind class compatible
    function cl.__copyObject(cl,obj)
      for k,v in pairs(cl) do
        if metas[k] then cmt[k]=v else obj[k]=v end
      end
      return obj
    end
    function mt.__call(tab,...)        -- Instantiation  <name>(...)
      local obj = tab.__copyObject(tab,{})
      if not tab.__init then error("Class "..name.." missing initialiser") end
      tab.__init(obj,...)
      local trapF = false
      for k,v in pairs(obj) do
        if type(v)=='table' and v['%CLASSPROP%'] then obj[k],props[k]=nil,v; trapF = true end
      end
      if trapF then trapIndex(props,cmt,obj) end
      local str = "Object "..name..":"..tostring(obj):match("%s(.*)")
      setmetatable(obj,cmt)
      if not obj.__tostring then 
        function obj:__tostring() return str end
      end
      return obj
    end
    function mt:__tostring() return "class "..name end
    setmetatable(cl,mt)
    getContext()[name] = cl
    return function(p) -- Class creation -- class <name>
      parent = p 
      if parent then parent.__copyObject(parent,cl) end
    end 
  end

  function self.urlencode(str)
    local s = str and string.gsub(str ,"([^% w])",function(c) return format("%%% 02X",string.byte(c))  end)
    return s
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
    darkgrey="\027[30;1m",
  }

  self.ZBCOLORMAP = ZBCOLORMAP
  LOG = { LOG="LOG  ", WARNING="WARN ", SYS="SYS  ", DEBUG="SDBG ", ERROR='ERROR', HEADER='HEADER'}
  hc3.sysConsoleColors = hc3.sysConsoleColors or {
    [LOG.LOG]='navy', [LOG.WARNING]='orange', [LOG.DEBUG]='blue',
    [LOG.SYS]='purple', [LOG.ERROR]='red',[LOG.HEADER]='blue'
  }

  local function colorStr(color,str)
    if _debugFlags.color then 
      return (ZBCOLORMAP[color] or ZBCOLORMAP['black'])..str.."\027[0m"
    else return str end
  end
  self.colorStr = colorStr

  function Debug(flag,...) if flag then Log(LOG.DEBUG,...) end end
  function Log(flag,arg1,...)
    local args={...}
    local stat,res = pcall(function()
        local str = #args==0 and arg1 or format(arg1,table.unpack(args))
        local color = "black"
        if flag == LOG.HEADER  then
          print(format("%s |%s|: %s",os.date("[%d.%m.%Y] [%X]"),"-----",colorStr(hc3.sysConsoleColors[flag],logHeader(100,str))))
          return str
        end
        print(format("%s |%s|: %s",os.date("[%d.%m.%Y] [%X]"),colorStr(hc3.sysConsoleColors[flag],flag),str))
        return str
      end)
    if not stat then error(res) end
  end
  self.Log,self.LOG = Log,LOG

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
  function string.split(str, sep)
    local fields,s = {},sep or "%s"
    str:gsub("([^"..s.."]+)", function(c) fields[#fields + 1] = c end)
    return fields
  end
  string.starts = function(str,pat) return str:sub(1,#pat)==pat end

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
  self.transform = transform
  function self.copy(obj) return transform(obj, function(o) return o end) end
  function self.shallowCopy(t) 
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
  self.equal=equal

  function self.member(k,tab) for _,v in ipairs(tab) do if v==k then return true end end return false end
  function self.remove(k,tab) local r = {}; for _,v in ipairs(tab) do if v ~= k then r[#r+1]=v end end return r end

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
          local mt = getmetatable(e)
          if mt and mt.__tostring then res[#res+1]=tostring(e) -- honor metatable.__tostring
          elseif next(e)==nil then res[#res+1]='{}'
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

    function self.prettyJsonFormat(t0)
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
  end

  local CRC16Lookup = {
    0x0000,0x1021,0x2042,0x3063,0x4084,0x50a5,0x60c6,0x70e7,0x8108,0x9129,0xa14a,0xb16b,0xc18c,0xd1ad,0xe1ce,0xf1ef,
    0x1231,0x0210,0x3273,0x2252,0x52b5,0x4294,0x72f7,0x62d6,0x9339,0x8318,0xb37b,0xa35a,0xd3bd,0xc39c,0xf3ff,0xe3de,
    0x2462,0x3443,0x0420,0x1401,0x64e6,0x74c7,0x44a4,0x5485,0xa56a,0xb54b,0x8528,0x9509,0xe5ee,0xf5cf,0xc5ac,0xd58d,
    0x3653,0x2672,0x1611,0x0630,0x76d7,0x66f6,0x5695,0x46b4,0xb75b,0xa77a,0x9719,0x8738,0xf7df,0xe7fe,0xd79d,0xc7bc,
    0x48c4,0x58e5,0x6886,0x78a7,0x0840,0x1861,0x2802,0x3823,0xc9cc,0xd9ed,0xe98e,0xf9af,0x8948,0x9969,0xa90a,0xb92b,
    0x5af5,0x4ad4,0x7ab7,0x6a96,0x1a71,0x0a50,0x3a33,0x2a12,0xdbfd,0xcbdc,0xfbbf,0xeb9e,0x9b79,0x8b58,0xbb3b,0xab1a,
    0x6ca6,0x7c87,0x4ce4,0x5cc5,0x2c22,0x3c03,0x0c60,0x1c41,0xedae,0xfd8f,0xcdec,0xddcd,0xad2a,0xbd0b,0x8d68,0x9d49,
    0x7e97,0x6eb6,0x5ed5,0x4ef4,0x3e13,0x2e32,0x1e51,0x0e70,0xff9f,0xefbe,0xdfdd,0xcffc,0xbf1b,0xaf3a,0x9f59,0x8f78,
    0x9188,0x81a9,0xb1ca,0xa1eb,0xd10c,0xc12d,0xf14e,0xe16f,0x1080,0x00a1,0x30c2,0x20e3,0x5004,0x4025,0x7046,0x6067,
    0x83b9,0x9398,0xa3fb,0xb3da,0xc33d,0xd31c,0xe37f,0xf35e,0x02b1,0x1290,0x22f3,0x32d2,0x4235,0x5214,0x6277,0x7256,
    0xb5ea,0xa5cb,0x95a8,0x8589,0xf56e,0xe54f,0xd52c,0xc50d,0x34e2,0x24c3,0x14a0,0x0481,0x7466,0x6447,0x5424,0x4405,
    0xa7db,0xb7fa,0x8799,0x97b8,0xe75f,0xf77e,0xc71d,0xd73c,0x26d3,0x36f2,0x0691,0x16b0,0x6657,0x7676,0x4615,0x5634,
    0xd94c,0xc96d,0xf90e,0xe92f,0x99c8,0x89e9,0xb98a,0xa9ab,0x5844,0x4865,0x7806,0x6827,0x18c0,0x08e1,0x3882,0x28a3,
    0xcb7d,0xdb5c,0xeb3f,0xfb1e,0x8bf9,0x9bd8,0xabbb,0xbb9a,0x4a75,0x5a54,0x6a37,0x7a16,0x0af1,0x1ad0,0x2ab3,0x3a92,
    0xfd2e,0xed0f,0xdd6c,0xcd4d,0xbdaa,0xad8b,0x9de8,0x8dc9,0x7c26,0x6c07,0x5c64,0x4c45,0x3ca2,0x2c83,0x1ce0,0x0cc1,
    0xef1f,0xff3e,0xcf5d,0xdf7c,0xaf9b,0xbfba,0x8fd9,0x9ff8,0x6e17,0x7e36,0x4e55,0x5e74,0x2e93,0x3eb2,0x0ed1,0x1ef0
  }

  function self.crc16(bytes)
    local crc = 0
    for i=1,#bytes do
      local b = string.byte(bytes,i,i)
      crc = ((crc<<8) & 0xffff) ~ CRC16Lookup[(((crc>>8)~b) & 0xff) + 1]
    end
    return tonumber(crc)
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
  local socket = require('socket')
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
    local n,lng_hour,t =  day_of_year(date), longitude / 15
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
    local rise_time = os._date("*t", sunturnTime(date, true, lat, lon, zenith, utc))
    local set_time = os._date("*t", sunturnTime(date, false, lat, lon, zenith, utc))
    local rise_time_t = os._date("*t", sunturnTime(date, true, lat, lon, zenith_twilight, utc))
    local set_time_t = os._date("*t", sunturnTime(date, false, lat, lon, zenith_twilight, utc))
    local sunrise = format("%.2d:%.2d", rise_time.hour, rise_time.min)
    local sunset = format("%.2d:%.2d", set_time.hour, set_time.min)
    local sunrise_t = format("%.2d:%.2d", rise_time_t.hour, rise_time_t.min)
    local sunset_t = format("%.2d:%.2d", set_time_t.hour, set_time_t.min)
    return sunrise, sunset, sunrise_t, sunset_t
  end

  self.sunCalc = sunCalc
  return self
end--module Utilities

--------------- json functions ------------------------
function module.Json(hc3)
  local _debugFlags = hc3.debug
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


  local function encode_nil(_)
    return "null"
  end


  local function encode_table(val, stack)
    local res = {}
    stack = stack or {}

    -- Circular reference?
    if stack[val] then
      error("circular reference")
    end

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
    --   [ "function" ] = tostring,
  }

  encode = function(val, stack)
    local t = type(val)
    local f = type_func_map[t]
    if f then
      return f(val, stack)
    end
    error("unexpected type '" .. t .. "'")
  end

  function json.encode(val,...)
    local extras = {...}
    assert(#extras==0,"Too many arguments to json.encode?")
    local res = {pcall(encode,val)}
    if res[1] then return select(2,table.unpack(res))
    else 
      local info = debug.getinfo(2)
      error(string.format("json.encode, %s, called from %s line:%s",res[2],info.short_src,info.currentline))
    end
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
    local res = {pcall(function()
          if type(str) ~= "string" then
            error("expected argument of type string, got " .. type(str))
          end
          local res, idx = parse(str, next_char(str, 1, space_chars, true))
          idx = next_char(str, idx, space_chars, true)
          if idx <= #str then
            decode_error(str, idx, "trailing garbage")
          end
          return res
        end)}
    if res[1] then return select(2,table.unpack(res))
    else 
      local info = debug.getinfo(2)
      error(string.format("json.encode, %s, called from %s line:%s",res[2],info.short_src,info.currentline))
    end
  end

  return json
end--module Json

--------------- Webserver API support  ----------------
function module.WebAPI(hc3)
  local self = {}
  local Util,Timer,Trigger,QA=hc3.module.Util
  local _debugFlags = hc3.debug
  local copas,quickApps,scenes
  local urldecode,fibaro = Util.urldecode
  local format = string.format

  Log,LOG,json,api,net,assert,assertf=Log,LOG,json,api,net,assert,assertf

  local socket  = require("socket")         -- LuaSocket, these are the dependencies we have

  function self.initialise()
    Timer,Trigger,QA = hc3.module.Timer,hc3.module.Trigger,hc3.module.QA
    copas,quickApps,scenes = Timer.copas,hc3.module.QA.quickApps,hc3.module.Scene.scenes
    fibaro = hc3.module.Fibaro.fibaro
  end

  local function redirect(method,client,call,body,headers)
  end

  local function clientHandler(client,handler)
    local headers = {}
    while true do
      local l,_,_ = client:receive()
      if _debugFlags.webServer or _debugFlags.webServerReq then Log(LOG.SYS,"WS: Request:%s",l) end
      if l then
        local body,header,e,b
        local method,call = l:match("^(%w+) (.*) HTTP/1.1")
        repeat
          header,e,b = client:receive()
          if header then
            local key,val = header:match("^(.-):%s*(.*)")
            if key then headers[key:lower()] = val
              if _debugFlags.webServer then Log(LOG.SYS,"WS: Header:%s",header) end
            elseif header~="" and _debugFlags.webServer then
              Log(LOG.SYS,"WS: Unknown request data:%s",header or "nil") 
            end
          end
          if header=="" then
            if headers['content-length'] and tonumber(headers['content-length'])>0 then
              body = client:receive(tonumber(headers['content-length']))
              if _debugFlags.webServer then Log(LOG.SYS,"WS: Body:%s",body) end
            end
            header=nil
          end
        until header == nil or e == 'closed'
        if _debugFlags.webServer or _debugFlags.webServerReq then Log(LOG.SYS,"WS: Request served:%s",l) end
        if call:match("/REDIRECTHC3/") then
          redirect(method,client,call,body,headers)
        end
        if handler then handler(method,client,call,body,headers) end
        client:close()
        return
      end
    end
  end

  local Pages = nil
  local lastDeviceUpdate = 0

  local GUI_HANDLERS = {  -- External calls
    ["GET"] = {
      ["/api/callAction%?deviceID=(%d+)&name=(%w+)(.*)"] = function(client,_,_,id,action,args)
        local res = {}
        args = args:split("&")
        for _,a in ipairs(args) do
          local i,v = a:match("^arg(%d+)=(.*)")
          res[tonumber(i)]=json.decode(urldecode(v))
        end
        local stat,res2=pcall(onAction,{actionName=action,deviceId=tonumber(id),args=res})
        if not stat then Log(LOG.ERROR,"Bad eventCall:%s",res2) end
        client:send("HTTP/1.1 201 Created\nETag: \"c180de84f991g8\"\n\n")
        return true
      end,
      ["/web/(.*)"] = function(client,_,_,call)
        if call=="" then call="main" end
        local qp = call:match("quickApp/(%d+)")
        if qp then call,qp = "quickApp",tonumber(qp) end
        local page = Pages.getPath(call,qp,quickApps[qp])
        if page~=nil then client:send(page) return true
        else return false end
      end,
      ["/fibaroapiHC3/ping"] = function(client,_,_,call)
        client:send((
[[HTTP/1.1 200 OK
Content-Length: 0
Content-Type: text/html
Connection: Closed

]]):gsub("\n","\r\n"))
        return true
      end,
      ["/fibaroapiHC3/webQA2/(%d+)%?(.*)"] = function(client,headers,_,id,args)
        local res = {}
        id = tonumber(id)
        args = args:split("&")
        for _,a in ipairs(args) do
          local i,v = a:match("^(%w+)=(.*)")
          res[i]=v
        end
        local qa = quickApps[id]
        if not qa then return end
        local slideCache = qa._emu.slideCache
        if res.type=='values' then
          local UI,res = qa._emu.UI or {},{}
          for _,row in ipairs(UI or {}) do
            row = row[1] and row or {row}
            for _,e in ipairs(row) do
              if e.type=='button' then 
                res["#"..e.button]={f="text",v=QA.getWebUIValue(id,e.button,"text")}
              elseif e.type=="label" then
                res["#"..e.label]={f="text",v=QA.getWebUIValue(id,e.label,"text")}
              elseif e.type =="slider" then
                local val = QA.getWebUIValue(id,e.slider,"value")
                if slideCache[e.slider] ~= val then
                  slideCache[e.slider] = val
                  res["#"..e.slider]={f="val",v=val}
                  res["#"..e.slider.."I"]={f="text",v=val}
                end
              end
            end
          end
          res = json.encode(res)
          client:send("HTTP/1.1 200 OK\n")
          client:send("Access-Control-Allow-Headers: Origin\n")
          client:send("Access-Control-Allow-Origin: *\n")
          client:send("Content-Type: application/json; charset=utf-8\n")
          client:send("Content-Length: "..res:len())
          client:send("\n\n")
          client:send(res)    
        else
          local stat,res = pcall(function()
              if res.type=='btn' then
                onUIEvent({eventType='onReleased',values={id},elementName=res.id,deviceId=id})
              elseif res.type=='slider' then
                onUIEvent({eventType='onChanged',values={tonumber(res.val)},elementName=res.id,deviceId=id})
                QA.setWebUIValue(id,res.id,'value',tonumber(res.val))
              end
            end)
          if not stat then Log(LOG.ERROR,res) end
          client:send("HTTP/1.1 302 Found\nLocation: "..(headers['referer'] or "/web/main").."\n")
          client:send("Access-Control-Allow-Headers: Origin\n")
          client:send("Access-Control-Allow-Origin: *\n")
        end
      end,
      ["/fibaroapiHC3/webCMD%?(.*)"] = function(client,headers,_,args)
        local res = {}
        args = args:split("&")
        for _,a in ipairs(args) do
          local i,v = a:match("^(%w+)=(.*)")
          res[i]=v
        end
        local val = nil
        if res.cmd == 'setValue' then val = res.value end
        fibaro.call(tonumber(res.id),res.cmd,val)
        client:send("HTTP/1.1 302 Found\nLocation: "..(headers['referer'] or "/web/main").."\n")
        client:send("Access-Control-Allow-Headers: Origin\n")
        client:send("Access-Control-Allow-Origin: *\n")
      end,
      ["/fibaroapiHC3/webDEV"] = function(client,_,_,_)
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
              --Log(LOG.LOG,"Update %s, %s",id,str.value.value)
            end
          end
        end
        lastDeviceUpdate = os.time()
        res = json.encode(res)
        client:send("HTTP/1.1 200 OK\n")
        client:send("Access-Control-Allow-Headers: Origin\n")
        client:send("Access-Control-Allow-Origin: *\n")
        client:send("Content-Type: application/json; charset=utf-8\n")
        client:send("Content-Length: "..res:len())
        client:send("\n\n")
        client:send(res)
      end,
    },
    ["POST"] = {
      ["/fibaroapiHC3/event"] = function(_,_,_,_,_,_)
        --- ToDo
      end,
      ["/fibaroapiHC3/action/(.+)$"] = function(client,_,body,_)
        local stat,res = pcall(onAction,(json.decode(body)))
        if not  stat then Log(LOG.ERROR,res) end
        client:send("HTTP/1.1 201 Created\r\nETag: \"c180de84f991g8\"\r\n\r\n")
        return true
      end,
      ["/fibaroapiHC3/ui/(.+)$"] = function(client,_,body,_)
        local stat,res = pcall(onUIEvent,(json.decode(body)))
        if not  stat then Log(LOG.ERROR,res) end
        client:send("HTTP/1.1 201 Created\r\nETag: \"c180de84f991g8\"\r\n\r\n")
        return true
      end,
      ["/devices/(%d+)/action/(.+)$"] = function(client,_,body,id,action)
        local data = json.decode(body)
        local event = {actionName=action,deviceId=tonumber(id),args=data.args}
        local stat,err=pcall(onAction,event)
        if not stat then error(format("Bad fibaro.call(%s,'%s',%s) - %s",id,action,json.encode(data.args):sub(2,-2),err),4) end
        client:send("HTTP/1.1 201 Created\r\nETag: \"c180de84f991g8\"\r\n\r\n")
        return true
      end,
      ["/api/(.+)$"] = function(client,_,body,path)
        local res,err = api.put(path,body)
        if not res then error(format("Bad api.put(%s) - %s",path,err),4) end
        client:send("HTTP/1.1 201 Created\r\nETag: \"c180de84f991g8\"\r\n\r\n")
        return true
      end
    }
  }

  local function GUIhandler(method,client,call,body,headers)
    local stat,res = pcall(function()
        for p,h in pairs(GUI_HANDLERS[method] or {}) do
          local match = {call:match(p)}
          if match and #match>0 then
            if h(client,headers,body,table.unpack(match)) then return end
          end
        end
        client:send("HTTP/1.1 501 Not Implemented\nLocation: "..(headers['referer'] or "/emu/triggers").."\n")
      end)
    if not stat then
      Log(LOG.ERROR,"Bad API call:%s",res)
      --local p = Pages.renderError(res)
      --client:send(p)
    end
  end

--  local socket = require'socket'
  function self.eventServer(port)
    local server,msg = socket.bind("*", port)
    assert(server,(msg or "").." ,port "..port)
    local i, msg2 = server:getsockname()
    assert(i, msg2)
    copas.addserver(server,
      function(sock)
        clientHandler(copas.wrap(sock),GUIhandler)
      end)
    Log(LOG.SYS,"Created Event server at %s:%s",hc3.IPaddress ,port)
  end

  local terminalCommands = {
    log = function(skt,str)
      local p = str:match("^log (.*)")
      if not p or p=="" then p = ".*" end
      local s = terminals[p] or {}
      s[skt]=true
      terminals[p] = s
    end,
    quit = function(skt,_)
      for p,s in pairs(terminals) do
        s[skt] = nil
        if next(s)==nil then terminals[p]=nil end
      end
      return 'break'
    end,
    help = function(skt,_)
      copas.send(skt,
[[quit - close socket
log <pattern> - captures log output where tag matches pattern
help - this text
<any other string> - interpreted as lua code and is loaded and executed
]])
    end
  }

  function self.terminalServer(port)
    local server,msg,i = socket.bind("*", port)
    assert(server,(msg or "").." ,port "..port)
    i, msg = server:getsockname()
    assert(i, msg)
    local function termHandler(skt)
      while true do
        local data = copas.receive(skt)
        local cr = 'lua'
        for c,f in pairs(terminalCommands) do
          if data:match("^"..c) then cr = f(skt,data) end
        end
        if cr == 'break' then break end
        if cr == 'lua' then
          local stat,res = pcall(function()
              return load("return "..data,"terminal","bt")()
            end)
          if stat then copas.send(skt, Util.prettyJson(res).."\n")
          else copas.send(skt, tostring(res).."\n") end
        end
      end
    end
    copas.addserver(server,termHandler)
    Log(LOG.SYS,"Created Terminal server at %s:%s",hc3.IPaddress, port)
  end

  function self.socketServer(port,patt,handler)
    local server,msg,i = socket.bind("*", port)
    assert(server,(msg or "").." ,port "..port)
    i, msg = server:getsockname()
    assert(i, msg)
    local function sockHandler(skt)
      if _debugFlags.socketServer then Log(LOG.SYS,"SocketServer: Connected") end
      while true do
        local data,err,n = copas.receive(skt,patt)
        if err == "closed" then
          if _debugFlags.socketServer then Log(LOG.SYS,"SocketServer: Closed") end
          return
        else
          local res = handler(data)
          if res then copas.send(skt, res) end
        end
      end
    end
    copas.addserver(server,sockHandler)
    Log(LOG.SYS,"Created Socket server at %s:%s",hc3.IPaddress, port)
  end

  Pages = { pages={} }

  function Pages.register(path,page)
    local file = page:match("^file:(.*)")
    if file then
      local f,err = io.open(file,"r")
      if not f then error("No such file:"..file) end
      page = f:read("*all")
      f:close()
    end
    Pages.pages[path]={page=page, path=path}
    return Pages.pages[path]
  end

  local function addLocalPage(name,path,headers)
    Pages.pages[name] = {fun = function()
        local f,err = io.open(path,"r")
        if not f then error("No such file:"..path) end
        page = f:read("*all")
        f:close()
        return [[HTTP/1.1 200 OK
Content-Type: text/html
Origin: http://127.0.0.1:6872
Access-Control-Allow-Origin: http://127.0.0.1:6872
Access-Control-Allow-Methods: POST, GET
Access-Control-Allow-Headers: X-Fibaro-Version, Authorization, Content-Type, access-control-allow-origin, access-control-allow-methods, access-control-allow-headers
Cache-Control: no-cache, no-store, must-revalidate

]]..(headers and  [[<!DOCTYPE html>]] or "")..page
      end}
  end

  addLocalPage("webui2","web/index.html",true)
  addLocalPage("script.js","web/script.js")

  function Pages.getPath(path,...)
    local p = Pages.pages[path]
    if p and p.fun then return p.fun() end
    if p and not p.cpage then
      Pages.compile(p)
    end
    if p then return Pages.render(p,...)
    else return nil end
  end

  function Pages.renderError(msg) return format(Pages.P_ERROR1,msg) end

  function Pages.render(p,...)
    if p.static and p.static~=true then return p.static end
    local args = {...}
    local stat,res = pcall(function()
        local fs = {}
        for i,f in ipairs(p.funs) do fs[i]=f(table.unpack(args)) end -- can't yield across :gsub...
        return p.cpage:gsub("<<<(%d+)>>>",function(i) return tostring(fs[tonumber(i)]) end)
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
          ["Web"]=self,["Pages"]=Pages,hc3=hc3,
          api=api,fibaro=fibaro, table=table, print=print, json=json, tostring=tostring,
          ["FIBAROAPIHC3_VERSION"] = FIBAROAPIHC3_VERSION,
          quickApps = quickApps, scenes = scenes, ipairs=ipairs, pairs=pairs,
        }
        local f = format("return function(a1,a2,a3) %s end",code)
        f,m = load(f,nil,nil,LENV)()
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
<<<return Web._PAGE_NAV()>>>
<t1>fibaroapiHC3 v<<<return FIBAROAPIHC3_VERSION>>></t1><br>
<t1>poll: <<<if hc3.poll== nil then return "false" else return hc3.poll end>>></t1><br>
<t1>proxy: <<<if hc3.proxy== nil then return "false" else return hc3.proxy end>>></t1>
</div>
<<<return Web._PAGE_FOOTER>>>
</body>
</html>
]]

  Pages.register("main",Pages.P_MAIN).static=false

  Pages.P_DEVICES =
[[HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: Origin
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
   $.get("http://127.0.0.1:<<<return hc3.webPort>>>/fibaroapiHC3/webDEV",
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
  $.get('http://127.0.0.1:<<<return hc3.webPort>>>/fibaroapiHC3/webCMD?id='+id+'&cmd='+cmd)
}
function QAslider(id,val) {
  $.get('http://127.0.0.1:<<<return hc3.webPort>>>/fibaroapiHC3/webCMD?id='+id+'&cmd=setValue&value='+val)
}
window.onfocus = function(){ $("#auto").prop("checked", true); reloadData(); doTimer(); }
window.onblur = function(){ $("#auto").prop("checked", false); doTimer(); }
setTimeout(doTimer,10)
</script>
</head>
<body>
<div style="margin-left: 20px;">
<<<return Web._PAGE_NAV()>>>
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

  function Pages.renderBinarySensor(d)
    local ctrl =
[[<tr >
<td style="width:30px"><label>%s</label></td>
<td style="width:150px"><label>%s</label></td>
<td style="width:80px;" align="center"><span id="D%s" class="dot"></span></td>
<td><button type="button" onClick="QAbutton(%s,'breachSensor');">Breach</button></td>
<td><button type="button" onClick="QAbutton(%s,'safeSensor');">Safe</button></td>
</tr>
]]
    return ctrl:format(d.id,d.name,d.id,d.id,d.id)
  end

  function Pages.renderMultilevelSensor(d)
    local ctrl =
[[<tr >
<td style="width:40px"><label>%s</label></td>
<td style="width:200px"><label>%s</label></td>
<td style="width:80px;" align="center"><span id="D%s" class="dot"></span></td>
<td> </td><td><input type="range" class="form-control-range" max="99" min="0" value="%s"
    onmouseup="QAslider(%s,this.value);"
    onmouseup="QAslider(%s,this.value);"
    oninput="$('#L%s').text(value);"
    id="S%s">
</td>
<td><label id="L%s">0</label></td>
</tr>
]]
    return
    ctrl:format(d.id,d.name,d.id,d.id,d.id,fibaro.getValue(d.id,"value"),d.id,d.id,d.id,d.id,d.id)
  end

  function Pages.renderSwitch(d)
    local ctrl =
[[<tr >
<td style="width:30px"><label>%s</label></td>
<td style="width:150px"><label>%s</label></td>
<td style="width:80px;" align="center"><span id="D%s" class="dot"></span></td>
<td><button type="button" onClick="QAbutton(%s,'turnOn');">Turn On</button></td>
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
<td><button type="button" onClick="QAbutton(%s,'turnOn');">Turn On</button></td>
<td><button type="button" onClick="QAbutton(%s,'turnOff');">Turn Off</button></td>
<td> </td><td><input type="range" class="form-control-range" max="99" min="0" value="%s"
    onmouseup="QAslider(%s,this.value);"
    onmouseup="QAslider(%s,this.value);"
    oninput="$('#L%s').text(value);"
    id="S%s">
</td>
<td><label id="L%s">0</label></td>
</tr>
]]
    return
    ctrl:format(d.id,d.name,d.id,d.id,d.id,fibaro.getValue(d.id,"value"),d.id,d.id,d.id,d.id,d.id)
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
      elseif actions.breachSensor then
        devs[#devs+1]={d.id,Pages.renderBinarySensor(d)}
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
<<<return Web._PAGE_NAV()>>>
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
<<<return Web._PAGE_NAV()>>>
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
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: Origin
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
   $.get("http://127.0.0.1:<<<return hc3.webPort>>>/fibaroapiHC3/webQA2/<<<return a1>>>?type=values",
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
  $.get('http://127.0.0.1:<<<return hc3.webPort>>>/fibaroapiHC3/webQA2/<<<return a1>>>?type=btn&id='+id)
}
function QAslider(id,val) {
  $.get('http://127.0.0.1:<<<return hc3.webPort>>>/fibaroapiHC3/webQA2/<<<return a1>>>?type=slider&id='+id+'&val='+val)
}
window.onfocus = function(){ $("#auto").prop("checked", true); reloadData(); doTimer(); }
window.onblur = function(){ $("#auto").prop("checked", false); doTimer(); }
setTimeout(doTimer,10)
</script>
</head>
<body>
<div style="margin-left: 20px;">
<<<return Web._PAGE_NAV()>>>
<t1>QuickApp: '<<<return a2.name>>>', deviceId:<<<return a2.id>>>, type:<<<return a2.type>>></t1>

<div class='row'><div class='col-lg-8 col-lg-offset-2'><hr></div></div>
<<<return Web.generateQA_UI(a2)>>>
<div class='row'><div class='col-lg-8 col-lg-offset-2'><hr></div></div>
<b>Properties:</b></br>
<<<local vals = {}
   for _,k in ipairs({'value','state','power','log'}) do
     if a2.properties[k]~=nil then
       vals[#vals+1]=k.."="..tostring(a2.properties[k])
     end
   end
   return table.concat(vals,"</br>")
>>>
<div class='row'><div class='col-lg-8 col-lg-offset-2'><hr></div></div>
<b>QuickAppVariables:</b></br>
<<<local vals = {}
   for _,k in ipairs(a2.properties.quickAppVariables or {}) do
      vals[#vals+1]=k.name.."="..tostring(k.value)
   end
   return table.concat(vals,"</br>")
>>>
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
  function Pages.renderSlider(id,_,value)
    return format([[<input class="form-control-range" min="0" max="99"
        type="range" id="%s" value="%s" style="width: 287px;"
        onmouseup="QAslider('%s',value);"
        onchange="$('#%sI').text(value);">
        <label class="slider" id="%sI">0</label>]],id,value,id,id,id,id)
  end

  function self.generateQA_UI(qa)
    local code = {}
    local function add(str) code[#code+1]=str end
    local UI,id = qa._emu.UI,qa.id
    for _,row in ipairs(UI or {}) do
      row = row[1] and row or {row}
      for _,e in ipairs(row) do
        if e.type=='button' or e.button then
          add(Pages.renderButton(e.button,QA.getWebUIValue(id,e.button,"text"),#row))
        elseif e.type=="label" or e.label then
          add(Pages.renderLabel(e.label,QA.getWebUIValue(id,e.label,"text")))
        elseif e.type =="slider" or e.slider then
          add(Pages.renderSlider(e.slider,e.text,QA.getWebUIValue(id,e.slider,"value")))
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

  function self._PAGE_NAV()
    local res = {
[[<nav class="navbar navbar-expand-sm bg-light navbar-light">
  <ul class="navbar-nav">
    <li class="nav-item" id="mainN">
      <a class="nav-link" target="_self" href="/web/main">FibaroAPIHC3</a>
    </li>
    <li class="nav-item" id="devicesN">
      <a class="nav-link" target="_self" href="/web/devices">Devices</a>
    </li>
    <li class="nav-item" id="globalsN">
      <a class="nav-link" target="_self" href="/web/globals">Global variables</a>
    </li>
    <li class="nav-item" id="eventsN">
      <a class="nav-link" target="_self" href="/web/events">Events</a>
    </li>]]}
    for _,v in pairs(quickApps) do
      res[#res+1]=format([[<li class="nav-item" id="quickAppN">
      <a class="nav-link" target="_self" href="/web/quickApp/%d">QA:%s</a>]],v.id,v.name)
    end
    res[#res+1]=[[
  </ul>
</nav>]]
    return table.concat(res)
  end

  return self
end--module WebAPI

--------------- OS support ----------------------
--file I/O etc.
function module.OS(hc3)
  local Util = hc3.module.Util
  local _debugFlags = hc3.debug
  local self = {}
  local lfs = require("lfs")

  Log,LOG,json,api,net,assert,assertf=Log,LOG,json,api,net,assert,assertf

  function self.initialise() --luacheck: ignore
    net,api = hc3.module.HTTP.net,hc3.module.API.api
  end

  -- File functions credit pkulchenko - ZeroBraneStudio
  local win = (os.getenv('WINDIR') or (os.getenv('OS') or ''):match('[Ww]indows'))
  and not (os.getenv('OSTYPE') or ''):match('cygwin') -- exclude cygwin
  local arch = win and "Windows" or "Linux" -- Host architecture
  local path_separator = arch == "Windows" and "\\" or "/"
  self.path_separator = path_separator

  local function escape_magic(str)
    assert(type(str) == "string", "utils.escape: Argument 'str' is not a string")
    local escaped = str:gsub('[%-%.%+%[%]%(%)%^%%%?%*%^%$]','%%%1')
    return escaped
  end

  local function exists(path)
    assert(type(path) == "string", "sys.exists: Argument 'path' is not a string.")
    local attr, err = lfs.attributes(path)
    return (not not attr), err
  end

  local function is_root(path)
    assert(type(path) == "string", "sys.is_root: Argument 'path' is not a string.")
    return (not not path:find("^[a-zA-Z]:[/\\]$") or path:find("^[/\\]$"))
  end

  local function is_dir(dir)
    assert(type(dir) == "string", "sys.is_dir: Argument 'dir' is not a string.")
    return lfs.attributes(dir, "mode") == "directory"
  end

  local function current_dir()
    local dir, err = lfs.currentdir()
    if not dir then return nil, err end
    return dir
  end

  local function get_directory(dir)
    dir = dir or current_dir()
    assert(type(dir) == "string", "sys.get_directory: Argument 'dir' is not a string.")
    if is_dir(dir) then
      return lfs.dir(dir)
    else
      return nil, "Error: '".. dir .. "' is not a directory."
    end
  end

  local function remove_trailing(path)
    assert(type(path) == "string", "sys.remove_trailing: Argument 'path' is not a string.")
    if path:sub(-1) == path_separator and not is_root(path) then path = path:sub(1,-2) end
    return path
  end

  local function remove_curr_dir_dots(path)
    assert(type(path) == "string", "sys.remove_curr_dir_dots: Argument 'path' is not a string.")
    while path:match(path_separator .. "%." .. path_separator) do                       -- match("/%./")
      path = path:gsub(path_separator .. "%." .. path_separator, path_separator)    -- gsub("/%./", "/")
    end
    return path:gsub(path_separator .. "%.$", "")                                         -- gsub("/%.$", "")
  end

  local function extract_name(path)
    assert(type(path) == "string", "sys.extract_name: Argument 'path' is not a string.")
    if is_root(path) then return path end
    path = remove_trailing(path)
    path = path:gsub("^.*" .. path_separator, "")
    return path
  end

  local function make_path(...)
    -- arg is deprecated in lua 5.2 in favor of table.pack we mimic here
    local arg = {n=select('#',...),...}
    local parts = arg
    assert(type(parts) == "table", "make_path: Argument 'parts' is not a table.")

    local path, err
    if parts.n == 0 then
      path, err = current_dir()
    else
      path, err = table.concat(parts, path_separator)
    end
    if not path then return nil, err end

    -- squeeze repeated occurences of a file separator
    path = path:gsub(path_separator .. "+", path_separator)

    -- remove unnecessary trailing path separator
    path = remove_trailing(path)

    return path
  end

  local function parent_dir(path)
    assert(type(path) == "string", "sys.parent_dir: Argument 'path' is not a string.")
    path = remove_curr_dir_dots(path)
    path = remove_trailing(path)

    local dir = path:gsub(escape_magic(extract_name(path)) .. "$", "")
    if dir == "" then
      return nil
    else
      return make_path(dir)
    end
  end

  local function make_dir(dir_name)
    assert(type(dir_name) == "string", "make_dir: Argument 'dir_name' is not a string.")
    if exists(dir_name) then
      return true
    else
      local par_dir = parent_dir(dir_name)
      if par_dir then
        local ok, err = make_dir(par_dir)
        if not ok then return nil, err end
      end
      return lfs.mkdir(dir_name)
    end
  end

  local function tmp_dir()
    return os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
  end

  local function tmp_name(prefix,suff)
    prefix = prefix or ""
    assert(type(prefix) == "string", "sys.tmp_name: Argument 'prefix' is not a string.")
    return make_path(tmp_dir(), prefix .. "_hc3emu_" ..(suff or (tostring({}):match("%d.*")))..".lua")
  end

  local function read(fn)
    local f = io.open(fn,"r")
    assert(f,"File "..fn.." doesn't exists")
    local c = f:read("*all"); f:close()
    return c
  end

  local function write(path,content,overwrite,silent)
    local n = extract_name(path)
    local d = path:sub(1,-(n:len()+2))
    if d:len()>0  then -- We have a dir
      if not is_dir(d) then make_dir(d) end
    end
    local file = io.open(path,"w")
    assert(file,"Can't openfile "..path)
    file:write(content)
    file:close()
    if not silent then Log(LOG.SYS,"Wrote file %s",path) end
  end

  local function updateHC3QAFiles(newFiles,id)
    local oldFiles = api.getHC3("/quickApp/"..id.."/files")
    local oldFilesMap = {}
    local updateFiles,createFiles = {},{}
    for _,f in ipairs(oldFiles) do oldFilesMap[f.name]=f end
    for _,f in ipairs(newFiles) do
      if oldFilesMap[f.name] then
        updateFiles[#updateFiles+1]=f
        oldFilesMap[f.name] = nil
      else createFiles[#createFiles+1]=f end
    end
    local _,res = api.putHC3("/quickApp/"..id.."/files",updateFiles)  -- Update existing files
    if res > 201 then return nil,res end
    for _,f in ipairs(createFiles) do
      _,res = api.postHC3("/quickApp/"..id.."/files",f)
      if res > 201 then return nil,res end
    end
    for _,f in pairs(oldFilesMap) do
      _,res = api.deleteHC3("/quickApp/"..id.."/files/"..f.name)
      if res > 201 then return nil,res end
    end
    return newFiles,200
  end

  local function downloadFile(url,path)
    if hc3.zbsplug then Log(LOG.DEBUG,"Downloading %s %s",tostring(url),tostring(path)) end
    local res2
    net.HTTPClient({sync=true}):request(url,{
        options={method="GET", checkCertificate = false, timeout=20000},
        success=function(res)
          if res.status == 200 then
            if path ~= nil then
              Log(LOG.LOG,"Writing file %s",path)
              local f = io.open(path,"w")
              f:write(res.data)
              f:close()
            else res2 = res.data end
          else
            Log(LOG.ERROR,"Bad file - %s",url)
          end
        end,
        error=function(res) Log(LOG.ERROR,"Downloading %s: %s",url,res) end,
      })
    return res2
  end

  function self.deployQA(sourceFile) hc3.loadQA(sourceFile):upload() end

  local ps  = self.path_separator
  local assetDir  = os.getenv("HC3EMU")
  if not assetDir then
    assetDir = (os.getenv('HOME')  or '')..ps..".zbstudio"..ps.."hc3emu"..ps
  end
  if not is_dir(assetDir) then
    local stat,_ = pcall(function() make_dir(assetDir) end)
    if not stat then
      Log(LOG.WARNING,"Can't create asset directory -'%s'",assetDir)
    else hc3.assetDirectory = assetDir end
  else hc3.assetDirectory = assetDir end

  local zbsDir = (os.getenv('HOME')  or '')..ps..".zbstudio"..ps
  if is_dir(zbsDir) then hc3.zbsDirectory = zbsDir end

  function self.splitEmulator(name)
    local f = io.open(name or "fibaroapiHC3.lua","r+")
    local src = f:read("*all")
    f:close()
    make_dir("emu")
    src = src:gsub("(function module%.)([A-Za-z]+)(.-end%-%-module.-[\n\r])",
      function(pre,name,post)
        local f  = io.open("emu/"..name..".lua","w+")
        f:write(pre..name..post)
        f:close()
        return [[dofile("emu/]]..name..".lua"..'")\n'
      end)
    f = io.open("mod_"..name,"w+")
    f:write(src)
    f:close()
  end

  function self.mergeEmulator()
  end

  function self.downloadZbsPlugin()
    if not hc3.zbsDirectory then
      Log(LOG.WARNING,"Can't download HC3 plugin for ZeroBrane Studio. Please create ~/.zbstudio/packages/")
      return
    end
    local path = hc3.zbsDirectory..ps.."packages"..ps
    if not is_dir(path) then
      local stat,_ = pcall(function() return make_dir(path) end)
      if not stat then
        Log(LOG.WARNING,"Can't createcreate ~/.zbstudio/packages/")
        return
      end
    end
    downloadFile(hc3.githubSrc.."fibaroapiHC3plug.lua",path..ps.."fibaroapiHC3plug.lua")
  end

  function self.downloadAssets()
    if not hc3.assetDirectory then
      Log(LOG.WARNING,"Can't download emulator assets. Please set ENV variable 'HC3EMU'")
      return
    end
    downloadFile(hc3.githubSrc.."hierarchy.json",hc3.assetDirectory.."hierarchy.json")
    downloadFile(hc3.githubSrc.."deviceTemplates.json",hc3.assetDirectory.."deviceTemplates.json")
    downloadFile(hc3.githubSrc.."hc3CodeTemplates.lua",hc3.assetDirectory.."hc3CodeTemplates.lua")
    downloadFile(hc3.githubSrc.."hc3Downloads.lua",hc3.assetDirectory.."hc3Downloads.lua")
  end

  function self.downloadFile(name)
    if not hc3.assetDirectory then
      Log(LOG.WARNING,"Can't download emulator assets. Please set ENV variable 'HC3EMU'")
      return
    end
    downloadFile(hc3.githubSrc.."hierarchy.json",hc3.assetDirectory.."hierarchy.json")
    downloadFile(hc3.githubSrc.."deviceTemplates.json",hc3.assetDirectory.."deviceTemplates.json")
  end

  self.file = {
    arch = arch,
    escape_magic = escape_magic, --(str)
    exists = exists, --(path)
    tmp_name = tmp_name,
    is_root = is_root, --(path)
    is_dir = is_dir,
    remove_trailing = remove_trailing, --(path)
    remove_curr_dir_dots = remove_curr_dir_dots, --(path)
    path_separator = path_separator, --()
    extract_name = extract_name, --(path)
    make_path = make_path, --(...)
    parent_dir = parent_dir, --(path)
    make_dir = make_dir, --(dir_name)
    dir = get_directory, --(dir)
    read = read,
    write = write,
    downloadFile = downloadFile,
    updateHC3QAFiles = updateHC3QAFiles
  }
  return self
end--module OS

--------------- Local devices --------------------
function module.Local(hc3)
  local self,gLoc = {}
  local Util,Timer,postTrigger = hc3.module.Util
  local _debugFlags,fibaro = hc3.debug
  local setProp,setSystemTimeout,clearTimeout
  local copy = Util.copy

  Log,LOG,json,api,net,assert,assertf=Log,LOG,json,api,net,assert,assertf

  function self.initialise() --luacheck: ignore
    Timer,fibaro = hc3.module.Timer,hc3.module.Fibaro.fibaro
    postTrigger = hc3.module.Trigger.postTrigger
    local h = hc3.module.API.getHandler("POST","/plugins/updateProperty")
    setProp = function(id,prop,value,force)
      h("POST","/plugins/updateProperty",{},{deviceId=id,propertyName=prop,value=value,force=force})
    end
    setSystemTimeout,clearTimeout = hc3.module.Timer.setSystemTimeout,hc3.module.Timer.clearTimeout

    local function setupSuntimes()
      if hc3.offline then
        if not gLoc.devices[1] then self.createDevice(1,true) end
        local sunrise,sunset = Util.sunCalc()
        local id1 = gLoc.devices[1]
        id1.properties.sunriseHour = sunrise
        gLoc.settings_info.sunriseHour = sunrise
        id1.properties.sunsetHour = sunset
        gLoc.settings_info.sunsetHour = sunset
      end
    end
    local t = os.date("*t")
    t.min,t.hour,t.sec=0,0,0
    t = os.time(t)+24*60*60
    local function midnight()
      --print("S",os.date("%c"))
      setupSuntimes()
      t = t+24*60*60
      Timer.setSystemTimeout(midnight,1000*(t-os.time()))
    end
    function self.startSun()
      Timer.setSystemTimeout(midnight,1000*(t-os.time()))
      Timer.setSystemTimeout(setupSuntimes,1)
    end
    self.startSun()
  end

  local ROOM_IDS = 1100
  local SECTION_IDS = 2100
  local DEVICE_IDS = 3100

  function self.getNextDeviceID() DEVICE_IDS = DEVICE_IDS+1 return DEVICE_IDS end

  local function makeHC3user(id,name)
    local u = {
      id = id, name = name, roomID = 219, view = {}, type = "HC_user", baseType = "com.fibaro.voipUser",
      enabled = true, visible = true, isPlugin = false, parentId = 0,
      interfaces = {"voip"},
      properties = {
        Email = "bob@foo.com",
        HotelModeRoom = 0, LastPwdChange = 1616131201,
        Latitude = 52.4320294933,Location = "52.4320294933;16.8449900900",
        LocationTime = "2012-12-06 12:15", LocationTimestamp = 1354792521, Longitude = 16.84499009,
        PreviousLatitude = 52.4320252015, PreviousLocation = "52.4320252015;16.8449947542",
        PreviousLocationTime = "2012-12-06 12:14", PreviousLocationTimestamp = 1354792461, PreviousLongitude = 16.844994754200002,
        SendNotifications = true, TrackUser = 0, UserType = "superuser", atHome = false,
        deviceIcon = 91, fidUuid = "b7a2295a-2615-40d0-84d9-f22de24875fe", firmwareUpdateLevel = 0,
        saveLogs = 1,sipDisplayName = "_",sipUserEnabled = true,sipUserID = "1",sipUserPassword = "",
        skin = "light",skinSetting = "manual",useOptionalArmPin = false,usePin = false
      },
      actions = {
        sendDefinedEmailNotification = 1, sendDefinedSMSNotification = 2,
        sendEmail = 2, sendGlobalEmailNotifications = 1,
        sendGlobalPushNotifications = 1, sendGlobalSMSNotifications = 1,
        sendPush = 1, setSipDisplayName = 1, setSipUserID = 1, setSipUserPassword = 1
      }
    }
    return u
  end

  gLoc = {
    devices = {},
    scenes = {},
    globalVariables = {},
    rooms = {},
    sections = {},
    customEvents = {},
    panels_location = {},
    panels_notification = {},
    notificationCenter = {},
    alarm_partitions = {},
    alarm_devices = {},
    settings_location = {
      date = { month = 12, year = 2020, day = 10 },
      city = "Stockholm", dateFormat = "dd.mm.yy", timezone = "Europe/Stockholm",
      latitude = 59.3169518987572, longitude = 18.06379775049387,
      houseNumber = 0, ntp = true, windUnit = "km/h",
      timezoneOffset = 7200, temperatureUnit = "C", timeFormat = 24,
      time = { hour = 21, minute = 31 },
      decimalMark = ".", ntpServer = "ntp.server.org"
    },
    settings_info = {
      serialNumber = "HC3-00000532",platform = "HC3",
      zwaveEngineVersion = "2.0",hcName = "HC3-00000532",
      mac = "ac:17:02:0d:35:c8",zwaveVersion = "4.33",
      timeFormat = 24,zwaveRegion = "EU",serverStatus = 1616353169,
      defaultLanguage = "en",defaultRoomId = 219,
      sunsetHour = "18:10",sunriseHour = "05:39",
      hotelMode = false,temperatureUnit = "C",
      batteryLowNotification = false,date = "12:04 | 24.3.2021",
      dateFormat = "dd.mm.yy",decimalMark = ".",
      timezoneOffset = 3600,softVersion = "5.070.42", beta = false,
      currentVersion = { version = "5.070.42", type = "stable" },
      installVersion = {version = "",type = "",status = "",progress = 0},
      timestamp = 1616583869,online = false,tosAccepted = true,
      skin = "light",skinSetting = "manual",
      updateStableAvailable = false, updateBetaAvailable = false,
      newestStableVersion = "5.070.42",newestBetaVersion = "5.000.00",
      isFTIConfigured = true,isSlave = false
    },
    categories = {
      {id=1, name="other"},{id=2, name="lights"},{id=3, name="blinds"},{id=4, name="gates"},{id=5, name="ambience"},
      {id=6, name="safety"},{id=7, name="security"},{id=8, name="multimedia"},{id=9, name="remotes"},{id=10, name="climate"},
    },
    home = {
      firstRunAfterUpdate = true,
      notificationClient = { marketingNotificationAllowed = true },
      freezeAlarmTemperature = 7.061401241503109, dateFormat = "dateFormat",
      defaultSensors = { light = 69, temperature = 12, humidity = 5 },
      meters = { energy = 12345 },
      hcName = "hcName", fireAlarmTemperature = 222,
      timeFormat = 12, weatherProvider = 5,
      currency = "currency", timestamp = 0.8008281904610115
    },
    iosDevices = {
      [55] = {
        id = 55,
        name = "Bob's iPhone",
        udid = "3BD269E2-190B-449E-B2BD-80EEBFB767B5",
        push = true
      }
    },
    profiles = {
      activeProfile = 1,
      profiles = {
        {
          id = 1, name = "Home", iconId = 1,
          devices = {
            {id=21, action=nil}, {id=22, action=nil}, {id=23, action=nil}, {id=24, action=nil}, {id=25, action=nil},
            {id=26, action=nil}, {id=27, action=nil}, {id=28, action=nil}, {id=29, action=nil}, {id=30, action=nil},
            {id=31, action=nil}, {id=32, action=nil}, {id=33, action=nil}, {id=34, action=nil}, {id=35, action=nil},
            {id=36, action=nil}, {id=37, action=nil}, {id=38, action=nil}, {id=39, action=nil}, {id=40, action=nil},
            {id=41, action=nil}, {id=42, action=nil}, {id=43, action=nil}, {id=44, action=nil}, {id=45, action=nil},
            {id=46, action=nil}, {id=47, action=nil}, {id=48, action=nil},
          },
          scenes = {}, climateZones = {}, partitions = {}
        },
      }
    },
    users = {
      [2] = {
        id = 2, name = "admin", type = "superuser", email = "foo@abc.com",
        deviceRights = { 50, 51, 52, 55, 56 },
        sceneRights = {},alarmRights = {},profileRights = {},climateZoneRights = {},
        hotelRoom = 0, sendNotifications = true, tracking = 0,
        atHome = false, useOptionalArmPin = false, skin = "light", skinSetting = "manual",
        fidUuid = "b7a2285a-2615-90d0-84d9-f52de24275fe"
      }
    },
    weather = {
      Temperature = 3.8, TemperatureUnit = "C", Humidity = 80,
      Wind = 15.48, WindUnit = "km/h", WeatherCondition = "cloudy", ConditionCode = 30
    },
    hierarchy = {}
  }
  do
    local p = gLoc.profiles.profiles
    local pnames = {'Home','Away¨','Vacation','Night'}
    for i=2,4 do p[#p+1] = copy(p[1]); p[#p].id = i; p[#p].name = pnames[i] end
  end

  local CHANGE_STEP = 8
  local function stopIncrease(d)
    if d._levelChange then clearTimeout(d._levelChange); d._levelChange = nil end
  end
  local function levelIncrease(d)
    local p,force = d.properties,true
    stopIncrease(d)
    --if p.value==0 then p.value = 99 setProp(d.id,'value',p.value,force) end
    local function increase()
      local val = p.value  + CHANGE_STEP
      if val >= 99 then
        setProp(d.id,'value',99,force)
        stopIncrease(d)
      else
        setProp(d.id,'value',val,true)
        d._levelChange = setSystemTimeout(increase,1000)
      end
    end
    d._levelChange = setSystemTimeout(increase, 1000)
  end
  local function levelDecrease(d)
    local p,force = d.properties,true
    stopIncrease(d)
    if p.value == 0 then return end
    local function decrease()
      local val = p.value - CHANGE_STEP
      if val <= 0 then
        setProp(d.id,'value',0,force)
        stopIncrease(d)
      else
        setProp(d.id,'value',val,true)
        d._levelChange = setSystemTimeout(decrease,1000)
      end
    end
    d._levelChange = setSystemTimeout(decrease, 1000)
  end

  self.customUI = {}
  self.customUI['com.fibaro.binarySwitch'] = 
  {{{button='__turnon', text="Turn On",onReleased="turnOn"},{button='__turnoff', text="Turn Off",onReleased="turnOff"}}}
  self.customUI['com.fibaro.multilevelSwitch'] = 
  {{{button='__turnon', text="Turn On",onReleased="turnOn"},{button='__turnoff', text="Turn Off",onReleased="turnOff"}},
    {{label='__lab1',text='Value'},{slider='__value', min=0, max=99, onChanged='setValue'}},
    {
      {button='__sli', text="🔼",onReleased="startLevelIncrease"},
      {button='__sld', text="🔽",onReleased="startLevelIncrease"},
      {button='__sls', text="⏸",onReleased="stopLevelChange"},
    }
  }

  self.customUI['com.fibaro.binarySensor']     = self.customUI['com.fibaro.binarySwitch']      -- For debugging
  self.customUI['com.fibaro.multilevelSensor'] = self.customUI['com.fibaro.multilevelSwitch']  -- For debugging

  local function setValue(d,value) return setProp(d.id,'value',value) end

  local actions = {
    ['com.fibaro.binarySensor'] = {
      ['breachSensor'] = function(d) setProp(d.id,'value',true) end,
      ['safeSensor'] = function(d) setProp(d.id,'value',false) end,
    },    
    ['com.fibaro.multilevelSensor'] = {
      ['setValue'] = setValue,
    },
    ['com.fibaro.doorLock'] = {
      ['secure'] = function() end,
      ['setDoorLockMode'] = function() end,
      ['unsecure'] = function() end,
    },
    ['com.fibaro.colorController'] = {
      ['setColor'] = function() end,
      ['startLevelDecrease'] = function() end,
      ['setValue'] = setValue,
      ['turnOff'] = function(d) end,
      ['startColorEnhancement'] = function() end,
      ['turnOn'] = function() end,
      ['startLevelIncrease'] = function() end,
      ['toggle'] = function() end,
      ['stopColorChange'] = function() end,
      ['startColorFade'] = function() end,
      ['stopLevelChange'] = function() end,
      ['setColorComponents'] = function() end,
    },
    ['com.fibaro.multimedia'] = {
      ['setMute'] = function() end,
      ['turnOn'] = function() end,
      ['setVolume'] = function() end,
      ['turnOff'] = function() end,
    },
    ['com.fibaro.multilevelSwitch'] = {
      ['startLevelIncrease'] = function(d) levelIncrease(d) end,
      ['stopLevelChange'] = function(d) stopIncrease(d) end,
      ['startLevelDecrease'] = function(d) levelDecrease(d) end,
      ['toggle'] = function(d) setProp(d.id,'value',true) end,
      ['turnOn'] = function(d) setProp(d.id,'value',100) end,
      ['setValue'] = setValue,
      ['turnOff'] = function(d) setProp(d.id,'value',0) end,
    },
    ['com.fibaro.FGR'] = {
      ['startLevelIncrease'] = function() end,
      ['stopLevelChange'] = function() end,
      ['setValue2'] = function() end,
      ['stop'] = function() end,
      ['reset'] = function() end,
      ['startLevelDecrease'] = function() end,
      ['setValue'] = setValue,
      ['open'] = function() end,
      ['close'] = function() end,
      ['setFavoritePosition'] = function() end,
    },
    ['com.fibaro.intercom'] = {
      ['openLock'] = function() end,
    },
    ['com.fibaro.rollerShutter'] = {
      ['startLevelIncrease'] = function() end,
      ['stopLevelChange'] = function() end,
      ['stop'] = function() end,
      ['startLevelDecrease'] = function() end,
      ['setValue'] = setValue,
      ['open'] = function() end,
      ['close'] = function() end,
      ['setFavoritePosition'] = function() end,
    },
    ['com.fibaro.FGWP'] = {
      ['toggle'] = function() end,
      ['turnOn'] = function() end,
      ['reset'] = function() end,
      ['turnOff'] = function() end,
    },
    ['com.fibaro.ipCamera'] = {
      ['moveUp'] = function() end,
      ['moveDown'] = function() end,
      ['moveStop'] = function() end,
      ['moveLeft'] = function() end,
      ['moveRight'] = function() end,
      ['sendPhotoToUser'] = function() end,
    },
    ['com.fibaro.player'] = {
      ['prev'] = function() end,
      ['play'] = function() end,
      ['turnOn'] = function() end,
      ['pause'] = function() end,
      ['setVolume'] = function() end,
      ['next'] = function() end,
      ['setMute'] = function() end,
      ['turnOff'] = function() end,
      ['stop'] = function() end,
    },
    ['com.fibaro.thermostatDanfoss'] = {
      ['setThermostatMode'] = function() end,
    },
    ['com.fibaro.meter'] = {
      ['reset'] = function() end,
    },
    ['com.fibaro.videoGate'] = {
      ['moveUp'] = function() end,
      ['moveDown'] = function() end,
      ['moveLeft'] = function() end,
      ['moveStop'] = function() end,
      ['openGate'] = function() end,
      ['moveRight'] = function() end,
      ['sendPhotoToUser'] = function() end,
    },
    ['com.fibaro.electricMeter'] = {
      ['reset'] = function() end,
    },
    ['com.fibaro.baseShutter'] = {
      ['open'] = function() end,
      ['close'] = function() end,
      ['stop'] = function() end,
    },
    ['com.fibaro.binarySwitch'] = {
      ['turnOff'] = function(d) setProp(d.id,'value',false) end,
      ['turnOn'] = function(d) setProp(d.id,'value',true) end,
      ['toggle'] = function(d) setProp(d.id,'value',not d.properties.value) end,
    },
    ['com.fibaro.receiver'] = {
      ['prev'] = function() end,
      ['play'] = function() end,
      ['turnOn'] = function() end,
      ['pause'] = function() end,
      ['setVolume'] = function() end,
      ['next'] = function() end,
      ['setMute'] = function() end,
      ['turnOff'] = function() end,
      ['stop'] = function() end,
    },
    ['com.fibaro.camera'] = {
      ['sendPhotoToUser'] = function() end,
    }
  }

  local deviceTemplates = nil

  function self.createGlobal(data)
    if type(data)=='string' then data = {name=data,value=""} end
    local v = {
      name = data.name,
      value = data.value,
      readOnly = data.readOnly or false,
      isEnum = data.isEnum or false,
      enumValues = data.enumValues or {},
      created = os.time(),
      modified = os.time()
    }
    gLoc.globalVariables[data.name]=v
    Log(LOG.SYS,"[Local] Creating globalVariable: '%s'",v.name)
    return v
  end

  function self.createRoom(data)
    if type(data)=='number' then data={id=data, name='Room:'..data} end
    data.id = data.id or ROOM_ID; ROOM_ID = ROOM_ID+1
    local r = {
      id = data.id,
      name = data.name or 'Room:'..data,
      sectionID = data.sectionID or 219,
      isDefault = true, visible = true, icon = "",
      defaultSensors = { temperature = 0, humidity = 0, light = 0 },
      meters = { energy = 0 },
      defaultThermostat = 0, created = os.time(), modified = os.time(),
      sortOrder = 1, category = "other"
    }
    gLoc.rooms[r.id]=r
    Log(LOG.SYS,"[Local] Creating room, id:%s, name:'%s'",r.id,r.name)
    return r
  end

  function self.createSection(data)
    if type(data)=='number' then data={name="Section:"..data,id=data} end
    data.id = data.id or SECTION_ID; SECTION_ID = SECTION_ID+1
    local s = {id = data.id, name = data.name, sortOrder=data.sortOrder or 1, created=os.time(), modified=os.time()}
    gLoc.sections[s.id]=s
    Log(LOG.SYS,"[Local] Creating section, id:%s, name:'%s'",s.id,s.name)
    return s
  end

  function self.createCustomEvent(data)
    if type(data)=='string' then   data={name=data,userDescription=""}  end
    local  e = {name=data.name, userDescription=data.userDescription or ""}
    gLoc.customEvents[data.name]=e
    Log(LOG.SYS,"[Local] Creating customEvent: '%s'",e.name)
    return e
  end

  function self.getDeviceTemplate(typ,baseType)
    if not deviceTemplates then
      local f = hc3.assetDirectory and io.open(hc3.assetDirectory.."deviceTemplates.json")
      if  not f then
        Log(LOG.WARNING,"Please download assets to create device types")
        return nil
      end
      deviceTemplates = json.decode((f:read("*all")))
    end
    local d = deviceTemplates[typ] or baseType and deviceTemplates[baseType] or nil
    if d then
      d = copy(d)
      d.id = nil
      d.interfaces = Util.remove('quickApp',d.interfaces or {})
      d.properties.uiCallbacks = nil
      d.properties.viewLayout=nil
      d.typeTemplateInitialized = nil
      d.apiVersion=nil
      d.quickAppVariables = nil
      if d.type == 'com.fibaro.binarySensor' or d.baseType == 'com.fibaro.binarySensor'  then
        d.actions.breachSensor = 0
        d.actions.safeSensor = 0
      end
    end
    return d
  end

  function self.createDevice(data,silent)
    if type(data) == 'number' then
      data = {id = data, name='Device_'..data, type=hc3.defaultDevice} -- Minimal device
    end
    local d,typ = nil,data.type or hc3.defaultDevice
    if data.id  == 1 then
      d = { 
        name = "zwave", type = "com.fibaro.zwavePrimaryController", baseType = "",
        properties = { sunsetHour="00:00", sunriseHour="00:00"}, interfaces = {"zwave"},
      }
    else
      d = self.getDeviceTemplate(typ)
    end
    if not d then
      Log(LOG.WARNING,"Unknown device type: %s",typ)
      return nil,500
    end
    d.id = data.id or self.getNextDeviceID()
    d.name = data.name or 'Device_'..data.id
    if _debugFlags.locl and not silent then Log(LOG.SYS,"[Local] Creating local device, id:%s, name:%s, type:%s",d.id,d.name,d.type) end
    postTrigger({type="DeviceCreatedEvent",data={id=d.id},objects={{objectId=d.id,objectType="device"}},sourceType="system"})
    gLoc.devices[d.id]=d
    return d
  end

  function self.deviceAction(dev,action,a,b,...)
    local m = actions[dev.type] or actions[dev.baseType]
    if m and m[action] then return m[action](dev,a,b,...)
    else Log(LOG.WARNING,"Unknown action '%s' for type:%s",action,dev.type) end
  end

  self.locl = {}
  function self.locl.room(args)
    if args.id and gLoc.rooms[args.id] then
      Log(LOG.SYS,"[Local] Room: '%s' exists",args.id)
      return gLoc.rooms[args.id]
    else return self.createRoom(args) end
  end

  function self.locl.section(args)
    if args.id and gLoc.sections[args.id] then
      Log(LOG.SYS,"[Local] Section: '%s' exists",args.id)
      return gLoc.sections[args.id]
    else return self.createSection(args) end
  end

  function self.locl.device(args)
    if args.id and gLoc.devices[args.id] then
      Log(LOG.SYS,"[Local] Device: '%s' exists",args.id)
      return gLoc.devices[args.id]
    else return self.createDevice(args) end
  end

  function self.locl.global(args)
    local name,value = args.name,args.value
    assert(type(name)=='string',"Global variable need name")
    if gLoc.globalVariables[name] then
      Log(LOG.SYS,"[Local] globalVariable: '%s' exists",name)
      return gLoc.globalVariables[name]
    else return self.createGlobal(args) end
  end

  local persistence = nil
  function self.downloadResources(fname)
    local dapi = _debugFlags.api
    _debugFlags.api = true
    fname = fname or hc3.resourceFile
    local rsrc = {}
    rsrc.devices = api.getHC3("/devices")
    rsrc.scenes = api.getHC3("/scenes")
    rsrc.globalVariables = api.getHC3("/globalVariables")
    rsrc.rooms = api.getHC3("/rooms")
    rsrc.sections = api.getHC3("/sections")
    rsrc.customEvents = api.getHC3("/customEvents")
    rsrc.panels_location = api.getHC3("/panels/location")
    rsrc.panels_notification = {}
    rsrc.alarm_partitions = api.getHC3("/alarms/v1/partitions")
    rsrc.alarm_devices = api.getHC3("/alarms/v1/devices/")
    rsrc.settings_location = api.getHC3("/settings/location")
    rsrc.settings_info = api.getHC3("/settings/info")
    rsrc.categories = api.getHC3("/categories")
    rsrc.home = api.getHC3("/home")
    rsrc.iosDevices = api.getHC3("/iosDevices")
    rsrc.profiles = api.getHC3("/profiles")
    rsrc.users = api.getHC3("/users")
    rsrc.weather = api.getHC3("/weather")
    rsrc.hierarchy = api.getHC3("/devices/hierarchy")
    persistence.store(fname,rsrc)
    Log(LOG.SYS,"Wrote '%s'",fname)
    _debugFlags.api = dapi
    os.exit()
  end

  function self.restoreResources(fname)
    fname = fname or hc3.resourceFile
    local f = io.read(fname,"r")
    local rsrc = persistence.load(fname)
    local function idMap(list,fun) 
      fun = fun or function(r) return r.id or r.name end
      local res = {}; 
      for _,r in ipairs(list) do res[fun(r)]=r end
      return res 
    end
    rsrc.devices = idMap(rsrc.devices)
    rsrc.scenes = idMap(rsrc.scenes)
    rsrc.globalVariables = idMap(rsrc.globalVariables)
    rsrc.rooms = idMap(rsrc.rooms)
    rsrc.sections = idMap(rsrc.sections)
    rsrc.customEvents = idMap(rsrc.customEvents)
    rsrc.panels_location = idMap(rsrc.panels_location)
    rsrc.panels_notification = idMap(rsrc.panels_notification)
    rsrc.alarm_partitions = idMap(rsrc.alarm_partitions)
    rsrc.alarm_devices = idMap(rsrc.alarm_devices)
--    rsrc.settings_location = idMap()
--    rsrc.settings_info = idMap()
    rsrc.categories = idMap(rsrc.categories)
--    rsrc.home = idMap()
    rsrc.iosDevices = idMap(rsrc.iosDevices)
--    rsrc.profiles = idMap(rsrc.profiles)
    rsrc.users = idMap(rsrc.users)
    gLoc = rsrc
  end

  commandLines['downloaddb']=function()
    self.downloadResources()
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

  self.gLoc = gLoc
  return self
end--module Local

--------------- API support ----------------------
function module.API(hc3)
  local self = {}
  local Util = hc3.module.Util
  local _debugFlags,format = hc3.debug,string.format
  local copy,urldecode,colorStr = Util.copy,Util.urldecode,Util.colorStr
  local HC3call,URLcall
  local offline,online,auto = true,false,false
  local Trigger,QA,Scene,Local,copas
  local postTrigger,gLoc,refreshStates
  Log,LOG,json=Log,LOG,json

  function self.initialise()
    Trigger,QA,Scene,Local = hc3.module.Trigger,hc3.module.QA,hc3.module.Scene,hc3.module.Local
    gLoc = Local.gLoc
    refreshStates,postTrigger = Trigger.refreshStates.getEvents,Trigger.postTrigger
    local hc3call = hc3.module.HTTP.HC3call
    copas = hc3.module.Timer.copas
    HC3call = function(method,url,data)
      if type(data)=='table' then data = json.encode(data) end
      if offline then return nil,404  else return hc3call(method,url,data) end
    end
    self.setOffline(hc3.offline,hc3.autoCreate)
  end

  local function createHandler(method,url)
    local h = self.getHandler(method,url)
    return function(data,url2,...) return h(method,url2,{},data,{},...) end
  end
  self.createHandler = createHandler

  local function copyTo(from,tos)  --- {a=9,b=10},{b=10}
    if type(tos) == 'table' then
      for k,v in pairs(tos) do
        if from[k] then tos[k]=copyTo(from[k],v) end
      end
      return tos
    else return from end
  end

  local function NIP(m,url) Log(LOG.WARNING,"API not implemented: %s %s",m,url) end

  local function idfi(r) return r.id end
  local function merge(list,map,idfv)
    local rs,idff = {},idfv or idfi
    for _,rsrc in ipairs(list) do
      if map[idff(rsrc)]==nil then rs[#rs+1]=rsrc end
    end
    for _,rsrc in pairs(map) do rs[#rs+1]=rsrc end
    return rs
  end

  local _fcont={['true']=true,['false']=false}
  local function _fconv(s) return _fcont[s]==nil and s or _fcont[s] end
  local fFuns = {
    interface=function(v,rsrc) return Util.member(v,rsrc.interfaces or {}) end,
    property=function(v,rsrc) return rsrc.properties[v:match("%[(.-),")]==_fconv(v:match(",(.*)%]")) end
  }

  local function filter(list,props)
    if next(props)==nil then return list end
    local res = {}
    for _,rsrc in ipairs(list) do
      local flag = false
      for k,v in pairs(props) do
        if fFuns[k] then flag = fFuns[k](v,rsrc)
        else flag = rsrc[k]==v end
        if not flag then break end 
      end
      if flag then res[#res+1]=rsrc end
    end
    return res
  end

  local ZBCOLORMAP = Util.ZBCOLORMAP
  hc3.consoleColors = hc3.consoleColors or {['DEBUG']='green', ['TRACE']='orange', ['WARNING']='purple', ['ERROR']='red'}

  local function html2color(str,startColor)
    local st,p = {startColor or '\027[0m'},1
    return str:gsub("(</?font.->)",function(s)
        if s=="</font>" then
          p=p-1; return st[p]
        else
          local color = s:match("color=(%w+)")
          color=ZBCOLORMAP[color] or ZBCOLORMAP['black']
          p=p+1; st[p]=color
          return color
        end
      end)
  end

  API = {
    ------------ Devices -------------
    ["GET/devices"] -- Get list of available devices
    = function(method,url,props,data,options)
      local devices = offline and {} or HC3call(method,url)
      return filter(merge(devices,gLoc.devices),props or {}),200
    end,
--   ?type=
--   ?interface=
--   ?name?
    ["GET/devices?property=[lastLoggedUser,{userId}]"] --Get mobile device list for user with specified id
    = function(method,url,props,data,options)
      return NIP(method,url)
    end,
    ["GET/devices/#id"] --Get device object
    = function(method,url,props,data,options,id)
      local d = gLoc.devices[id] or online and HC3call(method,url) or auto and Local.createDevice(id)
      if d then return d,200 else return nil,404 end
    end,
    ["GET/devices/#id/properties/#name"] --Get device property
    = function(method,url,props,data,options,id,name)
      local d = gLoc.devices[id] or (offline and auto and Local.createDevice(id))
      if d then return {value = d.properties[name], modified=d.modified},200
      else return HC3call(method,url) end
--      if not gLoc.devices[id] and  offline and auto then Local.createDevice(id) end
--      local d = gLoc.devices[id]
--      if d then return {value = d.properties[name], modified=d.modified},200
--      else return HC3call(method,url) end
    end,

    ["POST/devices"] --Create plugin
    = function(method,url,props,data,options)
      local args = type(data)=='string' and json.decode(data) or data
      if args.id and gLoc.devices[args.id] then return nil,409 end
      local dev = Local.createDevice(args)
      if dev then
        gLoc.devices[dev.id]=dev
        return dev,200
      else return nil,500 end
    end,
    ["POST/devices/filter"] --Get list of filtered devices
    = function(method,url,props,data,options)
      return HC3call(method,url,data)
    end,
    ["POST/devices/addInterface"]           --Add interfaces to devices
    = function(method,url,props,data,options)
      local args = type(data)=='string' and json.decode(data) or data
      local ids,eids = args.deviceId,{}
      for _,id in ipairs(ids or {}) do
        if gLoc.devices[id]  then
          for  _,i in ipairs(args.interfaces or {}) do
            if not Util.member(i,gLoc.devices[id].interfaces or {}) then
              table.insert(gLoc.devices[id].interfaces or {},i)
            end
          end
        else eids[#eids+1]=id end
      end
      if #eids > 0 then
        args.deviceId = eids
        return HC3call(method,url,(json.encode(args)))
      end
    end,
    ["POST/devices/deleteInterface"]        --Delete interfaces from devices
    = function(method,url,props,data,options)
      local args = type(data)=='string' and json.decode(data) or data
      local ids,eids = args.deviceId,{}
      for _,id in ipairs(ids or {}) do
        if gLoc.devices[id]  then
          for  _,i in ipairs(args.interfaces or {}) do 
            Util.remove(gLoc.devices[id].interfaces or {},i)
          end
        else eids[#eids+1]=id end
      end
      if #eids > 0 then
        args.deviceId = eids
        return HC3call(method,url,(json.encode(args)))
      end
    end,
    ["POST/devices/groupAction/#name"]       --Call group action
    = function(method,url,props,data,options,name)
      HC3call(method,url,data)
    end,
    ["POST/devices/#id/action/#name"]         --Call action
    = function(method,url,props,data,options,id,name)
      local args = type(data)=='string' and json.decode(data) or data
      if offline and not gLoc.devices[id] and auto then Local.createDevice(id) end
      if gLoc.devices[id] then
        if QA.quickApps[id] then
          local stat,res = pcall(onAction,{deviceId=id,actionName=name,args=args.args})
          if stat then return true,200 else return nil,500 end
        else
          Local.deviceAction(gLoc.devices[id],name,table.unpack(args.args))
          return true,200
        end
      else return HC3call(method,url,data) end
    end,
    ["PUT/devices/#id/interfaces/polling"] --Add polling interface
    = function(method,url,props,data,options,id)
      return NIP(method,url)
    end,
    ["PUT/devices/#id"] --Modify device
    = function(method,url,props,data,options,id)
      if gLoc.devices[id] then
        local args = type(data)=='string' and json.decode(data) or data
        gLoc.devices[id]=copyTo(args,gLoc.devices[id])
        return gLoc.devices[id],200
      else return HC3call(method,url,data) end
    end,
    ["POST/slave/#id/api/devices/#id/action/#name"] --Call action using master as a proxy for slave
    = function(method,url,props,data,options,id1,id2,name)
      return NIP(method,url)
    end,
    ["GET/devices/hierarchy"]                 --hierarchy
    = function(method,url,props,data,options,name)
      if offline then
        if next(gLoc.hierarchy)==nil then
          local f = hc3.assetDirectory and io.open(hc3.assetDirectory.."hierarchy.json")
          if f then
            gLoc.hierarchy = json.decode((f:read("*all")))
          else
            Log(LOG.WARNING,"Please download assets to use hierarchy offline")
            return nil,404
          end
        end
        return gLoc.hierarchy,200
      else return HC3call(method,url) end
    end,
    ["DELETE/devices/#id/interfaces/polling"] --Delete polling interface
    = function(method,url,props,data,options,id)
      return NIP(method,url)
    end,
    ["DELETE/devices/#id"]                    --Delete device
    = function(method,url,props,data,options,id)
      local d = gLoc.devices[id]
      if d then
        if QA.quickApps[id] then
          QA.quickApps[id].deleteQA()
        end
        gLoc.devices[id]=nil
        postTrigger({type="DeviceRemovedEvent",data={
              type=d.type,deviceName=d.name,id=d.id,roomId=d.roomId,roomName="Default Room",sectionName="Default Section"
            },
            sourceType="system"
          })
        return true,200
      else return HC3call(method,url) end
    end,
    ["DELETE/slave/#id/api/devices/#id"]  --Delete device using master as a proxy for slave
    = function(method,url,props,data,options,id1,id2)
      return HC3call(method,url)
    end,
    ["DELETE/devices/action/#id/#id"]     --Delete delayed action
    = function(method,url,props,data,options,id1,id2)
      if gLoc.devices[id1] then
        Log(LOG.WARNING,"%s not implmeneted",url)
        return nil,500
      else return HC3call(method,url) end
    end,
    ["GET/uiDeviceInfo"]                  --Get device info
    = function(method,url,props,data,options)
      return NIP(method,url)
    end,
    ------------ Scenes -------------
    ["GET/scenes"] -- Get scenes
    = function(method,url,props,data,options)
      local scenes = offline and {} or HC3call(method,url)
      return merge(scenes,gLoc.scenes),200
    end,
    ["GET/scenes/#id"] --Get scene object
    = function(method,url,props,data,options,id)
      local s = gLoc.scenes[id] or HC3call(method,url)
      if s then return s,200 else return nil,404 end
    end,
    ["POST/scenes"]   -- Install scene
    = function(method,url,props,data,options)
      if offline then
        local stat,res = pcall(function()
            Scene.loadScene(nil,data):install()
          end)
        if stat then return nil,500
        else return res,201 end
      else return HC3call(method,url,data) end
    end,
    ["POST/scenes/hasTriggers"] --Filter scenes by triggers
    = function(method,url,props,data,options)
      return HC3call(method,url,data)
    end,
    ["POST/scenes/#id/execute"] --Executes asynchronously executive part of the scene neglecting conditional part.
    = function(method,url,props,data,options,id)
      if gLoc.scenes[id] then
        Scene.runScene(id)
        return true,200
      else return HC3call(method,url,data) end
    end,
    ["POST/scenes/#id/executeSync"] --Executes synchronously executive part of the scene neglecting conditional part.
    = function(method,url,props,data,options,id)
      if gLoc.scenes[id] then
        Scene.runScene(id)
        return true,200
      else return HC3call(method,url,data) end
    end,
    ["POST/scenes/#id/convert"] --Convert block scene to lua.
    = function(method,url,props,data,options,id)
      if gLoc.scenes[id] then return NIP(method,url)
      else return HC3call(method,url,data) end
    end,
    ["POST/scenes/#id/copy"] --Create scene copy scene
    = function(method,url,props,data,options,id)
      if gLoc.scenes[id] then return NIP(method,url)
      else return HC3call(method,url,data) end
    end,
    ["POST/scenes/#id/copyAndConvert"] --Copy and convert block scene to lua.
    = function(method,url,props,data,options,id)
      if gLoc.scenes[id] then return NIP(method,url)
      else return HC3call(method,url,data) end
    end,
    ["POST/scenes/#id/kill"] --Kill running scene.
    = function(method,url,props,data,options,id)
      if gLoc.scenes[id] then
        if Scene.scenes[id] then Scene.killScene(id) end
        return true,200
      else HC3call(method,url,data) end
    end,
    ["PUT/scenes/#id"]  --Modify scene
    = function(method,url,props,data,options,id)
      if gLoc.scenes[id] then
        local args = type(data)=='string' and json.decode(data) or data
        gLoc.scenes[id]=copyTo(args,gLoc.scenes[id])
        return gLoc.scenes[id],200
      else return HC3call(method,url,data) end
    end,
    ["DELETE/scenes/#id"]                     --Delete scene
    = function(method,url,props,data,options,id)
      if gLoc.scenes[id] then
        if Scene.scenes[id] then
          Scene.scenes[id]:deleteScene()
          return true,200
        end
        gLoc.scenes[id] = nil
        return true,200
      else return HC3call(method,url) end
    end,
    ------------ Global variables -------------
    ["GET/globalVariables"] -- Get global variables
    = function(method,url,props,data,options)
      local globs = offline and {} or HC3call(method,url)
      return merge(globs,gLoc.globalVariables,function(v) return v.name end),200
    end,
    ["GET/globalVariables/#name"] --Get globalvariable object
    = function(method,url,props,data,options,name)
      local s = gLoc.globalVariables[name] or online and HC3call(method,url) or auto and Local.createGlobal(name)
      if s then return s,200 else return s,404 end
    end,
    ["POST/globalVariables"]  --Create variable
    = function(method,url,props,data,options)
      if offline then
        local args = type(data)=='string' and json.decode(data) or data
        if gLoc.globalVariables[args.name] then return nil,409 end
        local v = Local.createGlobal(args)
        if v then return v,200 else return v,500 end
      else return HC3call(method,url,data) end
    end,
    ["PUT/globalVariables/#name"]  --Modify global
    = function(method,url,props,data,options,name)
      if offline and auto then Local.createGlobal(name) end
      if gLoc.globalVariables[name] then
        local args = type(data)=='string' and json.decode(data) or data
        local var = gLoc.globalVariables[name]
        local oldValue = var.value
        var.value = args.value
        if var.value ~= oldValue then
          postTrigger({type='GlobalVariableChangedEvent',data={variableName=name,newValue=var.value,oldValue=oldValue}})
        end
        return var,200
      else return HC3call(method,url,data) end
    end,
    ["DELETE/globalVariables/#name"]  --Delete global
    = function(method,url,props,data,options,name)
      if gLoc.globalVariables[name] then
        gLoc.globalVariables[name]=nil
        return true,200
      else return HC3call(method,url) end
    end,
    ------------ Custom events -------------
    ["GET/customEvents"]          --get events
    = function(method,url,props,data,options)
      local ces = offline and {} or HC3call(method,url)
      return merge(ces,gLoc.customEvents,function(v) return v.name end),200
    end,
    ["GET/customEvents/#name"]          --get named event
    = function(method,url,props,data,options,name)
      local e = gLoc.customEvents[name] or online and HC3call(method,url)
      if e then return e,200 else return e,404 end
    end,
    ["POST/customEvents"]  --Create custom event
    = function(method,url,props,data,options)
      if offline then
        local args = type(data)=='string' and json.decode(data) or data
        local e = Local.createCustomEvent(args)
        if e then return e,200 else return e,500 end
      else return HC3call(method,url,data) end
    end,
    ["POST/customEvents/#name"]  --post event
    = function(method,url,props,data,options,name)
      if gLoc.customEvents[name] then
        postTrigger({type='CustomEvent',data={name=name}},0)
        return true,200
      else return HC3call(method,url,data) end
    end,
    ["PUT/customEvents/#name"]  --modify event
    = function(method,url,props,data,options,name)
      if offline then
        if not gLoc.customEvents[name] then return nil,404 end
        local args = type(data)=='string' and json.decode(data) or data
        copyTo(args,gLoc.customEvents[name])
        gLoc.customEvents[name].name=name
        return gLoc.customEvents[name],200
      else return HC3call(method,url,data) end
    end,
    ["DELETE/customEvents/#name"]  --delete event
    = function(method,url,props,data,options,name)
      if offline then
        if not gLoc.customEvents[name] then return nil,404 end
        gLoc.customEvents[name]=nil
        return true,200
      else return HC3call(method,url,data) end
    end,
    ------------- quickApp ---------
    ["GET/quickApp/#id/files"]                --get files
    = function(method,url,props,data,options,id)
      if QA.quickApps[id] then
        local f,files = QA.files[id],{}
        for _,v in pairs(f) do v = copy(v); v.content = nil; files[#files+1]=v end
        return files,200
      else return HC3call(method,url) end
    end,
    ["GET/quickApp/#id/files/#name"]          --Get specific file
    = function(method,url,props,data,options,id,name)
      if QA.quickApps[id] then
        if QA.files[id][name] then return QA.files[id][name],200
        else return nil,404 end
      else return HC3call(method,url) end
    end,
    ["PUT/quickApp/#id/files/#name"]          --Update specific file
    = function(method,url,props,data,options,id,name)
      if QA.quickApps[id] then
        if QA.files[id][name] then
          local args = type(data)=='string' and json.decode(data) or data
          QA.files[id][name] = args
          if hc3.HC3quickAppFile and tonumber(QA.quickApps[id]._emu.proxy) then HC3call(method,url,data) end
          QA.quickApps[id].restartQA()
          return QA.files[id][name],200
        else return nil,404 end
      else return HC3call(method,url) end
    end,
    ["PUT/quickApp/#id/files"]               --Update files
    = function(method,url,props,data,options,id)
      if QA.quickApps[id] then
        local args = type(data)=='string' and json.decode(data) or data
        for _,f in ipairs(args) do
          if QA.quickApps[id][f.name] then QA.quickApps[id][f.name]=f end
        end
        if hc3.HC3quickAppFile and tonumber(QA.quickApps[id]._emu.proxy) then HC3call(method,url,data) end
        QA.quickApps[id].restartQA()
        return true,200
      else return HC3call(method,url,data) end
    end,
    ["GET/quickApp/export/#id"]             --Export QA to fqa
    = function(method,url,props,data,options,id)
      if QA.quickApps[id] then
        return QA.toFQA(id,nil),200
      else return HC3call(method,url) end
    end,
    ["GET/quickApp/availableTypes"]          --Available QA types
    = function(method,url,props,data,options,id,name)
      return HC3call(method,url)
    end,
    ["POST/quickApp/"]    -- Install QA
    = function(method,url,props,data,options)
      local stat,res = pcall(function()
          return QA.loadQA(".fqa",data):install()
        end)
      if not stat then return nil,500
      else return res,201 end
    end,
    ["DELETE/quickApp/#id/files/#name"]    -- Delete file
    = function(method,url,props,data,options,id,name)
      local qa = QA.quickApps[id]
      if qa then
        if qa[name] then
          QA.files[id][name]=nil
          if hc3.HC3quickAppFile and tonumber(QA.quickApps[id]._emu.proxy) then HC3call(method,url) end
          QA.quickApps[id].restartQA()
          return true,200
        else return nil,404 end
      else return HC3call(method,url) end
    end,
    -------------- Plugins ---------------
    ["GET/plugins"] -- Get  installed plugin
    = function(method,url,props,data,options)
      return HC3call(method,url)
    end,
    ["GET/plugins/callUIEvent"]
    = function(method,url,props,data,options)
      return HC3call(method,url)
    end,
    ["GET/plugins/getView"]
    = function(method,url,props,data,options)
      return HC3call(method,url)
    end,
    ["GET/plugins/installed"]
    = function(method,url,props,data,options)
      return HC3call(method,url)
    end,
    ["GET/plugins/ipCameras"]
    = function(method,url,props,data,options)
      return HC3call(method,url)
    end,
    ["GET/plugins/types"]   --Types in the system
    = function(method,url,props,data,options)
      return HC3call(method,url)
    end,
    ["DELETE/plugins/installed"]                  --Delete plugin
    = function(method,url,props,data,options)
      return NIP(method,url,data)
    end,
    ["POST/plugins/createChildDevice"]
    = function(method,url,props,data,options)
      local args = type(data)=='string' and json.decode(data) or data
      local parent = QA.quickApps[args.parentId or 0]
      if (not online) or (parent and not parent._emu.proxy) then
        local dev = Local.createDevice({name=args.name,type=args.type})
        -- name,parentId,type,initialProperties,initialInterfaces
        if not dev then return nil,500 end
        dev.parentId = args.parentId
        local iprops = args.initialProperties or {}
        local interfaces = args.initialInterfaces or {}
        dev.interfaces = dev.interfaces or {}
        for p,v in  pairs(iprops) do dev.properties[p]=v end
        for _,i in ipairs(interfaces) do if not Util.member(i,dev.interfaces) then table.insert(dev.interfaces,i) end end
        return dev,200
      end
      return HC3call(method,url,data)
    end,
    ["DELETE/plugins/createChildDevice/#id"]
    = function(method,url,props,data,options,id)
      if gLoc.devices[id] then
        gLoc.devices[id]=nil
        return nil,200
      end
      return HC3call(method,url,data)
    end,
    ["POST/plugins/interfaces"]      --Add/remove interfaces
    = function(method,url,props,data,options)
      return HC3call(method,url,data)
    end,
    ["POST/plugins/publishEvent"]    --Publish event
    = function(method,url,props,data,options)
      if offline then
        Log(LOG.WARNING,"/plugins/publishEvent not implemented for offline yet")
        return nil,500
      end
      return HC3call(method,url,data)
    end,
    ["POST/plugins/restart"]         --Restart plugin
    = function(method,url,props,data,options)
      local args = type(data)=='string' and json.decode(data) or data
      if args.deviceId and QA.quickApps[args.deviceId] then
        QA.quickApps[args.deviceId].restartQA()
        return true,200
      else return HC3call(method,url,data) end
    end,
    ["POST/plugins/updateProperty"]  --Update property
    = function(method,url,props,data,options)
      local args,old = type(data)=='string' and json.decode(data) or data
      local id,dev = args.deviceId,gLoc.devices[args.deviceId]
      if dev then
        if dev.properties[args.propertyName] ~= args.value or args.force then
          local qa = QA.quickApps[id]
          old = dev.properties[args.propertyName]
          if qa==nil and type(dev.properties[args.propertyName]) ~= type(args.value) then
            Log(LOG.ERROR,"updateProperty id:%s, propertyName:%s, wrong type:%s",id,args.propertyName,type(args.value))
          end
          dev.properties[args.propertyName] = args.value
          if qa and qa._emu.proxy then 
            return HC3call(method,url,data) -- We have a proxy, let it post the update event
          else -- Local QA or device, post event locally
            postTrigger({
                type='DevicePropertyUpdatedEvent',
                data = {
                  id=args.deviceId,
                  property=args.propertyName,
                  newValue=args.value,
                  oldValue=old
                }
              })
          end
        end
        return data.value,200
      else return HC3call(method,url,data) end
    end,
    ["POST/plugins/updateView"]      --Update view
    = function(method,url,props,data,options)
      local args = type(data)=='string' and json.decode(data) or data
      local qa = QA.quickApps[args.deviceId]
      if qa then
        QA.setWebUIValue(args.deviceId,args.componentName,args.propertyName,args.newValue)
        if qa._emu.proxy then
          return HC3call(method,url,data)
        else return true,200 end
      else return HC3call(method,url,data) end
    end,
    ------------ Misc -------------
    ["GET/refreshStates"]           --events
    = function(method,url,props,data,options)
      return refreshStates(tonumber(props.last) or 0),200
    end,
    ["GET/weather"]           --weather
    = function(method,url,props,data,options)
      if offline then return gLoc.weather,200
      else return HC3call(method,url) end
    end,
    ["GET/alarms/v1/devices/"]           --alarms
    = function(method,url,props,data,options)
      if offline then return gLoc.alarms_devices,200
      else return HC3call(method,url) end
    end,
    ["GET/alarms/v1/partitions"]          --alarm partitions
    = function(method,url,props,data,options)
      if offline then return gLoc.alarms_partitions,200
      else return HC3call(method,url) end
    end,
    ["GET/settings/info"]                    --settings/info
    = function(method,url,props,data,options,name)
      if offline then return gLoc.settings_info,200
      else return HC3call(method,url) end
    end,
    ["PUT/settings/info"]                    --settings/info
    = function(method,url,props,data,options,name)
      if offline then
        local args = type(data)=='string' and json.decode(data) or data
        for k,v  in pairs(args) do
          gLoc.settings_info[k]=v
        end
        return gLoc.settings_info,200
      else return HC3call(method,url,data) end
    end,
    ["GET/settings/location"]                    --settings/location
    = function(method,url,props,data,options,name)
      if offline then return gLoc.settings_location,200
      else return HC3call(method,url) end
    end,
    ["PUT/settings/location"]                    --settings/location
    = function(method,url,props,data,options,name)
      if offline then 
        local args = type(data)=='string' and json.decode(data) or data
        for k,v  in pairs(args) do
          gLoc.settings_location[k]=v
        end
        return gLoc.settings_location,200
      else return HC3call(method,url,data) end
    end,
    ----------- Rooms ------------
    ["GET/rooms"] -- Get rooms
    = function(method,url,props,data,options)
      local rooms = offline and {} or HC3call(method,url)
      return merge(rooms,gLoc.rooms),200
    end,
    ["GET/rooms/#id"] --Get globalvariable  object
    = function(method,url,props,data,options,id)
      local s = gLoc.rooms[id] or online and HC3call(method,url)
      if s then return s,200 else return s,404 end
    end,
    ["POST/rooms"]  --Create room
    = function(method,url,props,data,options)
      if offline then
        local args = type(data)=='string' and json.decode(data) or data
        local r = Local.createRoom(args)
        if r then return r,200 else return r,500 end
      else return HC3call(method,url,data) end
    end,
    ["PUT/rooms/#id"]  --Modify room
    = function(method,url,props,data,options,id)
      if offline then
        if gLoc.rooms[id] then
          local args = type(data)=='string' and json.decode(data) or data
          gLoc.rooms[id]=copyTo(args,gLoc.rooms[id])
          return gLoc.rooms[id],200
        else return nil,404 end
      else return HC3call(method,url,data) end
    end,
    ["DELETE/rooms/#id"]  --Delete room
    = function(method,url,props,data,options,id)
      if gLoc.rooms[id] then
        gLoc.rooms[id]=nil
        return true,200
      else return HC3call(method,url) end
    end,
    ----------- Sections ------------
    ["POST/sections"]  --Create section
    = function(method,url,props,data,options)
      if offline then
        local args = type(data)=='string' and json.decode(data) or data
        local s = Local.createSection(args)
        if s then return s,200 else return s,404 end
      else return HC3call(method,url,data) end
    end,
    ["PUT/sections/#id"]  --Modify section
    = function(method,url,props,data,options,id)
      if offline then
        if gLoc.sections[id] then
          local args = type(data)=='string' and json.decode(data) or data
          gLoc.sections[id]=copyTo(args,gLoc.sections[id])
          return gLoc.sections[id],200
        else return nil,404 end
      else return HC3call(method,url,data) end
    end,
    ["GET/sections"] -- Get global variables
    = function(method,url,props,data,options)
      local secs = offline and {} or HC3call(method,url)
      return merge(secs,gLoc.sections,function(v) return v.name end),200
    end,
    ["GET/sections/#name"] --Get globalvariable  object
    = function(method,url,props,data,options,id)
      local s = gLoc.sections[id] or online and HC3call(method,url)
      if s then return s,200 else return s,404 end
    end,
    ["DELETE/sections/#id"]  --Delete section
    = function(method,url,props,data,options,id)
      if gLoc.sections[id] then
        gLoc.section[id]=nil
        return true,200
      else return HC3call(method,url) end
    end,
    ["GET/notificationCenter"]  --Notification list
    = function(method,url,props,data,options,id)
      if offline then return gLoc.notificationCenter,200 end
      return HC3call(method,url,data)
    end,
    ["POST/notificationCenter"]  --Create notification
    = function(method,url,props,data,options,id)
      return HC3call(method,url,data)
    end,
    ["DELETE/notificationCenter"]  --Delete read notifications
    = function(method,url,props,data,options,id)
      return HC3call(method,url,data)
    end,
    ["GET/notificationCenter​/#ID"]  --Notification
    = function(method,url,props,data,options,id)
      return HC3call(method,url,data)
    end,
    ["PUT/notificationCenter​/#ID"]  --Modify Notification
    = function(method,url,props,data,options,id)
      return HC3call(method,url,data)
    end,
    ["DELETE/notificationCenter​/#ID"]  --Delete Notification
    = function(method,url,props,data,options,id)
      return HC3call(method,url,data)
    end,
    ["POST/notificationCenter​/markAsRead"]  --mas Notification
    = function(method,url,props,data,options)
      return HC3call(method,url,data)
    end,
    ["POST/debugMessages"]  --mas Notification
    = function(method,url,props,data,options)
      local args = type(data)=='string' and json.decode(data) or data
      if hc3.HC3_debugmessages then
        HC3call(method,url,data)
      end
      local str,tag,typ = args.message,args.tag,args.messageType
      assert(type(tag)=='string' and type(typ)=='string',"Bad arguments to debugMessages")
      if hc3.htmlDebug then -- A bit messy, but try to convert html tags to ZBSconsole equivalents
        str = html2color(str,'\027[0m')
        str=str:gsub("&nbsp;"," ")
      end
      typ=typ:upper()
      str = format("%s [%s] [%s]: %s",os.date("[%d.%m.%Y] [%X]"),colorStr(hc3.consoleColors[typ],typ),tag:upper(),str)
      print(str) -- To IDE console
      for pat,skts in pairs(terminals) do
        if tag:match(pat) then
          for skt,_ in pairs(skts) do copas.send(skt, str.."\n") end
        end
      end
    end,
  }

  local pAPI={GET={},PUT={},POST={},DELETE={}}
  local function processAPI(api,dict)
    local method
    for k,v in pairs(api) do
      method,k = k:match("(%w+)(.*)")
      local d = dict[method]
      k:gsub("([^/]+)",function(p)
          d[p] = d[p] or {}
          d=d[p]
        end)
      d['#fun']=v
    end
  end

  processAPI(API,pAPI)

  local function redirect(method,url,props, data) --fun,method,url,props,data
    if _debugFlags.api then
      Log(LOG.WARNING,"Unhandled API call '%s:%s'%s",method,url,
        online and ", redirecting to HC3" or  "") 
    end
    return HC3call(method,url,data)
  end

  local keyMap = {['number'] = 'id', ['string'] = 'name'}

  local function findPath(path,tree,keys)
    for i=1,#path do
      local key = path[i]
      local t = tree[key]
      if not t then
        key = tonumber(key) or key
        t = tree["#"..keyMap[type(key)]]
        if t then
          keys[#keys+1] = key
          tree=t
        else return redirect end
      else tree = t end
    end
    return tree['#fun'] or redirect
  end

  local function valueOf(v)
    return tonumber(v) or (v=='true' and true) or (v=='false' and false) or v
  end

  local function findHandler(method,url)
    local tree = pAPI[method]
    local path,query=url:match("([^%?]+)%??(.*)")
    path = path:split("/")
    local keys,props = {},false
    if query~="" then
      props={}
      if query:sub(1,1)=='%' then query = urldecode(query) end
      query:gsub("([%w%%]+)=([%w%%%[%]%,:_]+)",
        function(k,v) props[k]=valueOf(v) end)
    end
    return findPath(path,tree,keys),props,keys
  end

  function URLcall(method,url,data,options)
    local fun,props,keys = findHandler(method,url)
    local stat,res,code = pcall(fun,method,url,props,data or false,options or {},table.unpack(keys or {}))
    if not stat then Log(LOG.ERROR,"API crashed, %s:%s - %s",method,url,res) end
    return res,code
  end

  self.getHandler = findHandler
  self.call = URLcall
  function self.setOffline(flag,autoc)
    offline = flag; online = not flag
    if autoc~=nil then auto=autoc end
  end
  self.resources = gLoc
  self.api = {
    get = function(call, _, options) return URLcall("GET",call, nil, options) end,
    put = function(call, data, options) return URLcall("PUT",call, data and json.encode(data), options) end,
    post = function(call, data, options) return URLcall("POST",call, data and json.encode(data), options) end,
    delete = function(call, data, options) return URLcall("DELETE",call, data and json.encode(data), options) end,
    getHC3 = function(call) return HC3call("GET",call, nil) end,
    putHC3 = function(call, data) return HC3call("PUT",call, data and json.encode(data)) end,
    postHC3 = function(call, data) return HC3call("POST",call, data and json.encode(data)) end,
    deleteHC3 = function(call, data) return HC3call("DELETE",call, data and json.encode(data)) end,
  }
  self.GET_DEVICE = createHandler("GET","/devices/#id")
  self.GET_SCENE = createHandler("GET","/scenes/#id")
  self.GET_PROPERTY = createHandler("GET","/devices/#id/properties/#name")
  self.GET_VARIABLE = createHandler("GET","/globalVariables/#name")
  self.PUT_VARIABLE = createHandler("PUT","/globalVariables/#name")
  self.CALL_ACTION = createHandler("POST","/devices/#id/action/#name")
  self.POST_DEBUGMESSAGE = createHandler("POST","/debugMessages")
  return self
end--module API

--------------- Load modules and start ------------------------------
local hc3 = hc3_emulator
hc3.module = {}
hc3.module.json    = module.Json(hc3)
hc3.module.Util    = module.Utilities(hc3)
hc3.module.Timer   = module.Timer(hc3)
hc3.module.HTTP    = module.HTTP(hc3)
hc3.module.Trigger = module.Trigger(hc3)
hc3.module.Fibaro  = module.Fibaro(hc3)
hc3.module.OS      = module.OS(hc3)
hc3.module.QA      = module.QuickApp(hc3)
hc3.module.Scene   = module.Scene(hc3)
hc3.module.Web     = module.WebAPI(hc3)
hc3.module.API     = module.API(hc3)
hc3.module.Local   = module.Local(hc3)

--Setup global functions
json,Log,LOG   = hc3.module.json,hc3.module.Util.Log,hc3.module.Util.LOG
net,api        = hc3.module.HTTP.net,hc3.module.API.api
assert,assertf = hc3.module.Util.assert,hc3.module.Util.assertf

local Util,Timer,API,OS = hc3.module.Util,hc3.module.Timer,hc3.module.API,hc3.module.OS
local Web,Trigger,Fibaro= hc3.module.Web,hc3.module.Trigger,hc3.module.Fibaro

--Initialize modules
for _,m in pairs(hc3.module) do if m and m.initialise then m.initialise(hc3) end end

commandLines['help'] = function()
  for c,_ in pairs(commandLines) do
    Log(LOG.LOG,"Command: -%s",c)
  end
end

local function DEFAULT(v,d) if v~=nil then return v else return d end end
hc3.offline           = DEFAULT(hc3.offline,false)
hc3.defaultDevice     = DEFAULT(hc3.defaultDevice,"com.fibaro.multilevelSwitch")
hc3.autoCreate        = DEFAULT(hc3.autoCreate,true)
hc3.setOffline        = hc3.module.API.setOffline
hc3.locl              = hc3.module.Local.locl

hc3.updateViewLayout  = hc3.module.QA.updateViewLayout
hc3.getUI             = hc3.module.QA.getQAUI
hc3.createQuickApp    = hc3.module.QA.createQuickApp
hc3.createProxy       = hc3.module.QA.createProxy
hc3.getIPaddress      = hc3.module.Util.getIPaddress
hc3.cache             = hc3.module.Trigger.cache
hc3.prettyJsonFormat  = hc3.module.Util.prettyJsonFormat
hc3.prettyJson        = hc3.module.Util.prettyJson
hc3.file              = hc3.module.OS.file
hc3.postTrigger       = hc3.module.Trigger.postTrigger
hc3.loadScene         = hc3.module.Scene.loadScene
hc3.loadQA            = hc3.module.QA.loadQA
hc3.downloadPlugin    = hc3.module.OS.downloadZbsPlugin
hc3.downloadAssets    = hc3.module.OS.downloadAssets
hc3.downloadFile      = hc3.module.OS.downloadFile
hc3.downloadResources = hc3.module.Local.downloadResources
hc3.loadResources     = hc3.module.Local.loadResources
hc3.socketServer      = Web.socketServer
hc3.getmetatable      = getmetatable

function hc3.module.Util.createEnvironment(envType, extras)
  local env = {}
  local function copy(t) local res={} for k,v in pairs(t) do res[k]=v end  return res end
  hc3.orgOs = os
  env._G = env
  env.hc3_emulator = copy(hc3)
  env.fibaro = copy(hc3.module.Fibaro.fibaro)  -- scenes may patch fibaro:*...
  env.json = copy(hc3.module.json)
  env.print = print
  env.net = copy(hc3.module.HTTP.net)
  env.api = copy(hc3.module.API.api)
  env.tostring = tostring
  env.tonumber = tonumber
  env.table = table
  env.string = string
  env.math = math
  env.pairs = pairs
  env.ipairs = ipairs
  env.pcall = pcall
  env.error = error
  if hc3.userdataType then -- Some code tests against userdata...
    env.type = function(o)
      local t = type(o) 
      return t=='table' and o._USERDATA and 'userdata' or t
    end
  else env.type = type end

  env.next = next
  env.select = select
  env.assert = assert

  if envType == 'Scene' then env.os = { time = os.time, date = os.date } end

  if envType == 'QA' or extras then

    env._VERSION = "Lua 5.3"
    env.__assert_type = hc3.module.Fibaro.__assert_type
    env.__fibaro_get_device = hc3.module.Fibaro.__fibaro_get_device
    env.__fibaro_add_debug_message = hc3.module.Fibaro.__fibaro_add_debug_message
    env.__fibaro_get_global_variable = hc3.module.Fibaro.__fibaro_get_global_variable
    env.__fibaro_get_device_property = hc3.module.Fibaro.__fibaro_get_device_property
    env.__fibaroUseAsyncHandler = hc3.module.Fibaro.__fibaroUseAsyncHandler
    env.__ternary = function(a,b,c) if a then return b else return c end end
    env.__fibaro_get_device = hc3.module.Fibaro.__fibaro_get_device
    env.__fibaroSleep = hc3.module.Fibaro.__fibaroSleep
    env.__fibaro_get_scene = hc3.module.Fibaro.__fibaro_get_scene
    env.__fibaro_get_devices = hc3.module.Fibaro.__fibaro_get_devices
    env.__fibaro_get_room = hc3.module.Fibaro.__fibaro_get_room

    env.setTimeout = hc3.module.Timer.setTimeout
    env.clearTimeout = hc3.module.Timer.clearTimeout
    env.setInterval = hc3.module.Timer.setInterval
    env.clearInterval = hc3.module.Timer.clearInterval
    env.urlencode = Util.urlencode
    env.xpcall = xpcall
    env.rawlen = rawlen
    env.collectgarbage = collectgarbage
    env.bit32 = bit32
    env.debug = debug
    env.mqtt = hc3.module.HTTP.mqtt
    env.unpack = table.unpack
    env.os = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime, milliTime = os.milliTime }

    local mt0 = getmetatable(QuickApp)
    local QA,mt = copy(QuickApp),copy(mt0)
    setmetatable(QA,mt)
    env.Device = Device
    env.QuickApp = QA
    env.QuickAppBase = QuickAppBase
    env.QuickAppChild = QuickAppChild
    env.plugin = copy(hc3.module.QA.plugin)
    env.class = class or Util.class
    env.property = property or Util.property
    env.super = Util.super
    env.utf8 = utf8

    env.getHierarchy = getHierarchy -- ToDo define...
    env.Hierarchy = Hierarchy
  end

  if extras then
    env.os = os
    env.io = io
    env.dofile = hc3_emulator.dofile -- Allow dofile for including code for testing, but use our version that sets context
    env.loadfile = loadfile
    env.load = load
    env.rawset = rawset
    env.rawget = rawget
    env.require = require
    env.coroutine = coroutine
    env.setmetatable = setmetatable
    env.getmetatable = getmetatable
    env.debug = debug
  end
  return env
end

if arg[1] then
  Timer.start(function()
      os.setTimer(function()
          local cmd,res = arg[1],false
          if cmd:sub(1,1)=='-' then
            cmd = cmd:sub(2)
            if commandLines[cmd] then --- When fibaroapiHC3.lua is used as a command from ZBS
              res = commandLines[cmd](select(2,table.unpack(arg)))
            end
          end
        end,0)
    end,0)
end

local function startEmulator(file)
  API.setOffline(hc3_emulator.offline)
  local offline = hc3_emulator.offline
  hc3_emulator.print = print 

  if not offline and not hc3_emulator.credentials then
    error("Missing HC3 credentials -- hc3_emulator.credentials{ip=<IP>,user=<string>,pwd=<string>}")
  end
  if not offline then
    hc3_emulator.typeHierarchy = api.get('/devices/hierarchy')
    hc3_emulator.HC3version = api.get("/settings/info").currentVersion.version or "5.040.37"
  end
  hc3_emulator.speeding = hc3_emulator.speed==true and 48 or tonumber(hc3_emulator.speed)
  if hc3_emulator.traceFibaro then Fibaro.traceFibaro() end

  Log(LOG.SYS,"HC3 SDK v%s",hc3_emulator.version)
  if hc3_emulator.deploy==true or _G["DEPLOY"] then OS.deployQA(file) osExit() end

  Log(LOG.SYS,"Running %sline (autocreate %s)",offline and "off" or "on",tostring(hc3_emulator.autoCreate))

  if hc3_emulator.speeding then Log(LOG.SYS,"Speeding %s hours",hc3_emulator.speeding) end
  hc3_emulator.IPaddress = Util.getIPaddress()
  if hc3_emulator.startWeb ~= false then Web.eventServer(hc3_emulator.webPort) end
  if hc3_emulator.startTerminal ~= false then Web.terminalServer(hc3_emulator.terminalPort) end

  if type(hc3_emulator.startTime) == 'string' then
    os.setTime(Util.parseDate(hc3_emulator.startTime))
  end

  local t = (math.floor(os.time() / 3600))*3600
  local dst = os.date("*t",t).isdst
  for _=1,24*30*6 do
    t=t+3600
    if os.date("*t",t).isdst ~= dst then
      hc3_emulator.DST = t;
      Log(LOG.LOG,os.date("DST at %c",t))
      Timer.setSystemTimeout(function()
          Timer.adjustTime(dst and 3600 or -3600)
        end,1000*(t-os.time()))
      break
    end
  end

  if hc3_emulator.speeding then Timer.speedTime(hc3_emulator.speeding) end
  if hc3_emulator.credentials and not offline then
    hc3_emulator.BasicAuthorization = "Basic "..Util.base64(hc3_emulator.credentials.user..":"..hc3_emulator.credentials.pwd)
  end

  if hc3_emulator.poll and not hc3_emulator.offline then
    local p = tonumber(hc3_emulator.poll) or 2000
    Log(LOG.LOG,"Polling HC3 for triggers every %s ms",p)
    Trigger.startPolling(p)
  end

  if _debugFlags.fibaro then Fibaro.traceFibaro() end

  if offline then api.put("/settings/info",{serverStatus=os.time()})  end -- Set the time

  local t = os.time()
  local function loop()
    t=t+3600
    --Log(LOG.SYS,"HOUR")
    Timer.setSystemTimeout(loop,1000*(t-os.time()))
  end
  t = (t // 3600 +1)*3600
  Timer.setSystemTimeout(loop,1000*(t-os.time()))

  Timer.setSystemTimeout(function()
      t = t+3600
    end,1000*(t-os.time()))

  local code = OS.file.read(file)
  if code:match("hc3_emulator%.actions") then
    hc3_emulator.codeType = 'Scene'
    hc3_emulator.loadScene(file,code):install()
  elseif code:match("QuickApp:") or hc3_emulator.quickAppPattern and code:match(hc3_emulator.quickAppPattern) then
    hc3_emulator.codeType = 'QA'
    hc3_emulator._SYNC = true
    hc3_emulator.loadQA(file,code):install()
  else
    hc3_emulator.codeType = 'QA'
    local env = Util.createEnvironment("QA",true)
    setContext(env)

    env._ENVID='Lua'
    local CodeLock = Timer.copas.lock.new(60*60*30)
    function env._getLock() CodeLock:get(60*60*30) end
    function env._releaseLock() CodeLock:release() end
    env.print = function(...) env.fibaro.debug("Lua",...) end
    local st = Timer.setTimeout
    local function errHandler(err)
      Log(LOG.ERROR,"Lua timer %s crashed - %s",env._lastTimer,"Lua",err)
    end
    env.setTimeout = function(fun,ms,tag)
      local function f(...)
        local stat,res = pcall(fun)
        if not stat then error(res,2) end
      end
      return st(f,ms,tag,errHandler,env)
    end
    env.fibaro.setTimeout = function(a,b,...) return env.setTimeout(b,a,...) end
    load(code,file,"bt",env)()
  end
end -- startEmulator

if not hc3_emulator.sourceFile then
  local file = debug.getinfo(3, 'S')                                      -- Find out what file we are running
  if file and file.source then
    file = file.source
    if not file:sub(1,1)=='@' then error("Can't locate file:"..file) end  -- Is it a file?
    hc3_emulator.sourceFile = file:sub(2)
  end
end

if hc3_emulator.sourceFile then
  if hc3_emulator.profile then
    -- https://raw.githubusercontent.com/charlesmallah/lua-profiler/master/src/profiler.lua
    profiler = require("profiler")
    profiler.start()
  end
  Timer.start(function()
      --setTimeout(function() profiler.report("profiler.log") end,60*1000)
      Timer._started = true
      Timer.kick()
      startEmulator(hc3_emulator.sourceFile) 
    end, 0)
else
  Log(LOG.SYS,"fibaroapiHC3 version:%s",FIBAROAPIHC3_VERSION)
end
osExit()