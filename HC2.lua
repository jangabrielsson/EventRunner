--[[
EventRunner. HC2 scene emulator
Copyright (c) 2019 Jan Gabrielsson
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
--]]

_version,_fix = "0.3","fix1" -- first version

_REMOTE=true                 -- Run remote, fibaro:* calls functions on HC2, on non-local resources
_EVENTSERVER = 6872          -- To receieve triggers from external systems, HC2, Node-red etc.
_SPEEDTIME = 24*30           -- Speed through X hours, if set to false run in real time
_AUTOCREATEGLOBALS=true      -- Will (silently) autocreate a local fibaro global if it doesn't exist
_AUTOCREATEDEVICES=true      -- Will (silently) autocreate a local fibaro device if it doesn't exist
_VALIDATECHARS = true        -- Check rules for invalid characters (cut&paste, multi-byte charqcters)
_COLOR = true                -- Log with colors on ZBS Output console
_HC2_FILE = "HC2.data"

_HC2_IP="192.198.1.xx"       -- HC2 IP address
_HC2_USER="xxx@yyy"          -- HC2 user name
_HC2_PWD="xxxxxx"            -- HC2 password

local creds = loadfile("credentials2.lua") -- To not accidently commit credentials to Github...
if creds then creds() end

--------------------------------------------------------
-- Main, register scenes, create temporary deviceIDs, schedule triggers...
--------------------------------------------------------
function main()

  HC2.setupConfiguration(true,true) -- read in configuration from stored local file, or from remote HC2
  --HC2.localDevices()
  --HC2.localGlobals()
  --HC2.localRooms(true)
  --HC2.localScenes(true)

  HC2.loadEmbedded()

  --HC2.loadScenesFromDir("scenes") -- Load all files with name <ID>_<name>.lua from dir, Ex. 11_MyScene.lua

  --HC2.createDevice(77,"Test") -- Create local deviceID 77 with name "Test"

  --HC2.listDevices()
  --HC2.listScenes()

  --fibaro:call(17,"turnOn")

  --HC2.registerScene("Scene1",10,"ff.lua")

  --HC2.registerScene("Scene1",11,"EventRunnerA.lua")
  --HC2.registerScene("Scene1",12,"GEA 6.11.lua")
  --HC2.registerScene("Scene1",13,"Main scene FTBE v1.3.0.lua",{Darkness=0,TimeOfDay='Morning'})

  -- Post a simulated trigger 10min in the future...
  --HC2.post({type='property',deviceID=77, propertyName='value'},"+/00:10")

  --Log fibaro:* calls
  --HC2.logFibaroCalls()
  --Debug filters can be used to trim debug output from noisy scenes...
  HC2.addDebugFilter("Memory used:",true) 
  HC2.addDebugFilter("GEA run since",true)
  HC2.addDebugFilter("%.%.%. check running",true)
  HC2.addDebugFilter("%b<>(.*)</.*>")
end

_debugFlags = { threads=false, triggers=false, eventserver=false, hc2calls=true, globals=false, fibaroSet=true, fibaroStart=true }
------------------------------------------------------
-- Context, functions exported to scenes
------------------------------------------------------
function setupContext(id)  -- Table of functions and variables available for scenes
  return
  {
    __fibaroSceneId=id,    -- Scene ID
    __threads=0,           -- Currently number of running threads
    _EMULATED=true,        -- Check if we run in emulated mode
    fibaro=_copy(fibaro),  -- scenes may patch fibaro:*...
    _System=_System,       -- Available for debugging tasks in emulated mode
    dofile=_System.dofile, -- Allow dofile for including code for testing, but use our version that sets context
    os={clock=os.clock,date=osDate,time=osTime,difftime=os.difftime},
    json=json,
    net = net,
    api = api,
    setTimeout=_System.setTimeoutContext,
    clearTimeout=_System.clearTimeout,
    urlencode=urlencode,
    select=select,
    --require=require,
    split=split,
    tostring=tostring,
    tonumber=tonumber,
    table=table,
    string=string,
    math=math,
    pairs=pairs,
    ipairs=ipairs,
    pcall=pcall,
    xpcall=xpcall,
    error=error,
    io=io,
    collectgarbage=collectgarbage,
    type=type,
    next=next,
    bit32=bit32,
  }
end

------------------------------------------------------------------------
-- Support functions - don't touch
------------------------------------------------------------------------
require('mobdebug').coro()   -- Allow debugging of Lua coroutines

mime = require('mime')
https = require ("ssl.https")
ltn12 = require("ltn12")
json = require("json")
socket = require("socket")
http = require("socket.http")
lfs = require("lfs")
tojson = json.encode

_LOCAL= not _REMOTE
function printf(...) print(string.format(...)) end -- Lazy printing - should use Log(...)

_format=string.format
LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ERROR = "Tomato"}
_LOGMAP = {orange="\027[33m",white="\027[34m",Cyan="\027[35m",green="\027[32m",Tomato="\027[31m"} -- ANSI escape code, supported by ZBS
_LOGEND = "\027[0m"
--[[Available colors in Zerobrane
for i = 0,8 do
  print(("%s \027[%dmXYZ\027[0m normal"):format(30+i, 30+i))
end
for i = 0,8 do
  print(("%s \027[1;%dmXYZ\027[0m bright"):format(38+i, 30+i))
end
--]]
function _Msg(color,message,...)
  color = _COLOR and _LOGMAP[color] or ""
  local args = type(... or 42) == 'function' and {(...)()} or {...}
  message = _format(message,table.unpack(args))
  local env,sceneid = Scene.global(),"[SR]"
  if env then sceneid = _format("[%s:%s]",env.__fibaroSceneId,env.__orgInstanceNumber) end
  print(string.format("%s#%s%s %s%s",color,sceneid,osOrgDate("%H:%M:%S, %a %b %d:",osTime()),message,_COLOR and _LOGEND or "")) 
  return message
end
function Debug(flag,message,...) if flag then _Msg(LOG.DEBUG,message,...) end end
function Log(color,message,...) return _Msg(color,message,...) end

function _assert(test,msg,...) if not test then msg = _format(msg,...) error({msg},3) end end
function _assertf(test,msg,fun) if not test then msg = _format(msg,fun and fun() or "") error({msg},3) end end

function isEvent(e) return type(e) == 'table' and e.type end

function _copy(obj) return _transform(obj, function(o) return o end) end
function _equal(e1,e2)
  local t1,t2 = type(e1),type(e2)
  if t1 ~= t2 then return false end
  if t1 ~= 'table' and t2 ~= 'table' then return e1 == e2 end
  for k1,v1 in pairs(e1) do if e2[k1] == nil or not _equal(v1,e2[k1]) then return false end end
  for k2,v2 in pairs(e2) do if e1[k2] == nil or not _equal(e1[k2],v2) then return false end end
  return true
end
function _transform(obj,tf)
  if type(obj) == 'table' then
    local res = {} for l,v in pairs(obj) do res[l] = _transform(v,tf) end 
    return res
  else return tf(obj) end
end

------------------------------------------------------------------------------
-- Scene support
-- load
-- start
-- kill
------------------------------------------------------------------------------
Scene={ scenes={} }

_ENV = _ENV or _G or {}         -- Environment
_SceneContext = {}              -- Map from thread -> environment
local mt = {}; mt.__mode = "k"; 
setmetatable(_SceneContext,mt)  -- weak keys (keys are coroutines)

-- If we need to access local scene variables
function Scene.global() return _SceneContext[coroutine.running()] end -- global().<var>
function Scene.setGlobal(v,s) _SceneContext[coroutine.running()][v]=s end -- setGlobal('v',42)

function Scene.load(name,id,file)
  Scene.scenes[id] = Scene.scenes[id] or {}
  local scene,msg = Scene.scenes[id]
  scene.name = name
  scene.id = id
  scene.runningInstances = 0
  scene._local = true
  scene.runConfig = "TRIGGER_AND_MANUAL"
  scene.triggers,scene.lua = Scene.parseHeaders(file,id)
  scene.isLua = true
  scene.code,msg=loadfile(file)
  _assert(msg==nil,"Error in scene file %s: %s",file,msg)
  Log(LOG.SYSTEM,"Loaded scene:%s, id:%s, file:'%s'",name,id,file)
  return scene
end

function Scene.start(scene,event,args)
  if not scene._local then return end
  local globals,env = setupContext(scene.id)
  if nil then -- If we need to intercept access to globals, however it slows down debugging (stepping)
    local context = {
      __index = function (t,k) --printf("Get %s=%s",k,globals[k]) 
        return globals[k] 
      end,
      __newindex = function (t,k,v) --printf("Set %s=%s",k,globals[k])  
        globals[k] = v 
      end
    }
    env = {}
    setmetatable(env,context)
  else
    env=globals
  end
  globals._ENV=env
  globals.__fibaroSceneSourceTrigger = event
  globals.__fibaroSceneArgs = args
  globals.__sceneCode = scene.code  
  globals.__sceneCleanup = function(co) 
    Log(LOG.LOG,"Scene [%s:%s] terminated (%s)",scene.id,env.__orgInstanceNumber,co)
    scene.runningInstances=scene.runningInstances-1 
  end
  local tr = _System.setTimeoutContext(function() 
      scene.runningInstances=scene.runningInstances+1
      env.__orgInstanceNumber=scene.runningInstances
      setfenv(scene.code,env) 
      --require('mobdebug').on() 
      scene.code() 
    end,
    0,scene.name,env)
  _SceneContext[tr]=env
  Log(LOG.LOG,"Starting scene:%s, trigger:%s (%s)",scene.name,tojson(event),tr)
end

function Scene.checkValidCharsInFile(src,fileName)
  local lines = split(src,'\r')
  local function ptr(p) local r={}; for i=1,p+9 do r[#r+1]=' ' end return table.concat(r).."^" end
  for n,s in ipairs(lines) do
    s=s:match("^%c*(.*)")
    local p = s:find("\xEF\xBB\xBF")
    if p then 
      local err = string.format("Illegal UTF-8 sequence in file:%s\rLine:%3d, %s\r%s",fileName,n,s,ptr(p))
      err=err:gsub("%%","%%%%")
      Log(LOG.ERROR,err)
    end
  end
end

function Scene.parseHeaders(fileName,id)
  local headers = {}

  local f = io.open(fileName)
  if not f then error("No such file:"..fileName) end
  local src = f:read("*all")
  Scene.checkValidCharsInFile(src,fileName)
  local c = src:match("--%[%[.-%-%-%]%]")
  local curr = nil
  if c and c~="" then
    c=c:gsub("([\r\n]+)","\n")
    c = split(c,'\n')
    for i=2,#c-1 do
      if c[i]:match("^%%%%") then curr=c[i]:match("%a+"); headers[curr]={}
      elseif curr then 
        local h = headers[curr] or {}
        h[#h+1] = c[i]
        headers[curr]=h
      end
    end
  end

  local events={}
  for i=1,headers['properties'] and #headers['properties'] or 0 do
    local id,name = headers['properties'][i]:match("(%d+)%s+([%a]+)")
    if id and id ~="" and name and name~="" then events[#events+1]={type='property',deviceID=tonumber(id), propertyName=name} end
  end
  for i=1,headers['globals'] and #headers['globals'] or 0 do
    local name = headers['globals'][i]:match("([%w]+)")
    if name and name ~="" then events[#events+1]={type='global', name=name} end
  end
  for i=1,headers['events'] and #headers['events'] or 0 do
    local id,t = headers['events'][i]:match("(%d+)%s+CentralSceneEvent")
    if id and id~="" and t and t~="" then events[#events+1]={type='event',event={type='CentralSceneEvent',data={deviceId=tonumber(id)}}}
    else
      id,t = headers['events'][i]:match("(%d+)%s+AccessControlEvent")
      if id and id~="" and t and t~="" then events[#events+1]={type='event',event={type='AccessControlEvent',data={id=tonumber(id)}}} end 
    end
  end
  if headers['autostart'] then events[#events+1]={type='autostart'} end
  return events,src
end

------------------------------------------------------------------------
-- HC2 functions
-- Creating and managing HC2 resources
------------------------------------------------------------------------
HC2 = { rsrc={} }
HC2.rsrc.globalVariables = {}
HC2.rsrc.devices = {}
HC2.rsrc.iosDevices = {}
HC2.rsrc.users = {}
HC2.rsrc.scenes = {}
HC2.rsrc.sections = {}
HC2.rsrc.rooms = {}
HC2.rsrc.info = {}
HC2.rsrc.location = {}

function HC2.registerScene(name,id,file,globVars)
  local scene = Scene.load(name,id,file) 
  HC2.rsrc.scenes[id]=scene
  for _,t in ipairs(scene.triggers) do
    Log(LOG.SYSTEM,"Scene:%s [ Trigger:%s ]",id,tojson(t))
    Event.event(t,function(env) Scene.start(scene,env.event) end)
  end
  Event.event({type='other',_id=id}, -- startup event
    function(env) 
      local event = env.event
      local args = event._args
      event._args=nil
      event._id=nil
      Scene.start(scene,event,args)
    end)
  for name,value in pairs(globVars or {}) do HC2.createGlobal(name,value) end
end

local function patchID(t) local c= 0; for k,v in pairs(t) do t[k]=nil; t[tonumber(k)]=v c=c+1 end return c end

function HC2.setupConfiguration(file,copyFromHC2)
  local file2 = type(file)=='string' and file or _HC2_FILE
  local c1,c2,c3,c4=0,0,0,0
  local rsrc = HC2.rsrc
  if copyFromHC2 then
    Log(LOG.SYSTEM,"Reading configuration from H2C...")
    local vars = api._get(false,"/globalVariables/")
    for _,v in ipairs(vars) do rsrc.globalVariables[v.name] = v c1=c1+1 end
    local s = api._get(false,"/sections")
    for _,v in ipairs(s) do rsrc.sections[v.id] = v end
    s = api._get(false,"/rooms")
    for _,v in ipairs(s) do rsrc.rooms[v.id] = v c4=c4+1 end
    s = api._get(false,"/devices")
    for _,v in ipairs(s) do rsrc.devices[v.id] = v c3=c3+1 end
    s = api._get(false,"/scenes") -- need to retrieve once more to get the Lua code
    for _,v in ipairs(s) do rsrc.scenes[v.id] = api._get(false,"/scenes/"..v.id) c2=c2+1 end
    s = api._get(false,"/iosDevices")
    for _,v in ipairs(s) do rsrc.iosDevices[v.id] = v end
    rsrc.info = api._get(false,"/settings/info")
    rsrc.location = api._get(false,"/settings/location")
    if file then HC2.writeConfigurationToFile(file2) end
  else
    local f = io.open(file2)
    if f then
      local data = f:read("*all")
      rsrc = json.decode(data)
      for n,_ in pairs(rsrc.globalVariables) do c1=c1+1 end
      c3=patchID(rsrc.devices); c=patchID(rsrc.scenes); c4=patchID(rsrc.rooms); patchID(rsrc.sections); patchID(rsrc.iosDevices); 
      HC2.rsrc=rsrc
    else Log(LOG.SYSTEM,"No HC2 data file found (%s)'",file2) end
  end
  if not rsrc.info.serverStatus then
    rsrc.info={serverStatus=os.time(), currentVersion={version="100.00"}}
  end
  Log(LOG.SYSTEM,"Configuration setup, Globals:%s, Scenes:%s, Device:%s, Rooms:%s",c1,c2,c3,c4)
end

function HC2.writeConfigurationToFile(file)
  Log(LOG.SYSTEM,"Writing info to '%s'",file)
  local f = io.open(file,"w+")
  f:write(json.encode(HC2.rsrc))
  f:close()
end

function HC2.getRsrc(name,id)
  local rsrcs=HC2.rsrc[name]
  local rsrc=rsrcs[id]
  if rsrc and rsrc._local then return rsrc
  elseif _REMOTE and rsrc then
    local rsrc = api._get(false,"/"..name.."/"..id)
    rsrcs[id] = rsrc
    return rsrc
  elseif not rsrc then-- rsrc doesn't exists
    if name=='globalVariables' and _AUTOCREATEGLOBALS then
      rsrc = {name=is, modified=osTime(), _local=true}
      rsrcs[id] = rsrc
    elseif name=='devices' and _AUTOCREATEDEVICES then
      rsrc = HC2.createDevice(id,tostring(id))
      rsrcs[id] = rsrc
    end
  end
  return rsrc
end

local function _getId(n,r) return n=='globalVariables' and r.name or r.id end

function HC2.getAllRsrc(name)
  local r2,res={},{}
  if _REMOTE then 
    r2 = api._get(false,"/"..name) -- if remote connection, get fresh data
    for _,r3 in ipairs(r2) do
      local i = _getId(name,r3) -- only update non-local data
      if HC2.rsrc[name][i] and not HC2.rsrc[name][i]._local then HC2.rsrc[name][i] = r3 end
    end
  end
  for id,r in pairs(HC2.rsrc[name]) do res[#res+1]=r end
  return res
end

function HC2.getDevice(id) return HC2.getRsrc('devices',id) end
function HC2.getGlobal(id) return HC2.getRsrc('globalVariables',id) end
function HC2.getScene(id) return HC2.getRsrc('scenes',id) end
function HC2.getRoom(id) return HC2.getRsrc('rooms',id) end
function HC2.getSection(id) return HC2.getRsrc('sections',id) end
function HC2.getiosDevice(id) return HC2.getRsrc('iosDevices',id) end

-- ToDo, This should be cleaned up and functionality moved from fibaro:* to api.*
--[[
GET:/settings/info
GET:/settings/location
GET:/iosDevices
GET:/devices
GET:/devices/<deviceID>
POST:/devices/<deviceID/action/<actionName>
POST:/devices/<deviceID/groupAction/<actionName>
GET:/sections
GET:/sections/<sectionID>
GET:/scenes
GET:/scenes/<sceneID>
GET:/rooms
GET:/rooms/<roomID>
GET:/globalVariables              -- Get all variables
GET:/globalVariables/<varName>    -- Get variable
PUT:/globalVariables/<var struct> -- Modify variable
PUT:/globalVariables/<var struct> -- Modify variable
POST:/globalVariables/<var struct> -- Create variable
--]]

local function stdGetRsrc(name,id)
  if id==nil or id=="" then return  HC2.getAllRsrc(name)
  elseif id then return HC2.getRsrc(name,id)
  else return null end
end

HC2._getHandlers={
  settings=function(arg)
    if arg=='info' then return HC2.rsrc.info
    elseif arg=='location' then return HC2.rsrc.location
    else return null end
  end,
  iosDevice=function(arg) return stdGetRsrc('iosDevices',tonumber(arg)) end,
  devices=function(arg) return stdGetRsrc('devices',tonumber(arg)) end,
  sections=function(arg) return stdGetRsrc('sections',tonumber(arg)) end,
  scenes=function(arg) return stdGetRsrc('scenes',tonumber(arg)) end,
  rooms=function(arg) return stdGetRsrc('rooms',tonumber(arg)) end,
  globalVariables=function(arg) return stdGetRsrc('globalVariables',arg) end,
}

HC2._putHandlers={ -- update global variable
  globalVariables=function(r,data,cType)
    local v = HC2.getRsrc('globalVariables',r)
    if v and v._local then HC2.rsrc.globalVariables[r]=data
    elseif v and _REMOTE then -- update global remote
      api._put(false,"/globalVariables/"..r,data,cType)
      HC2.rsrc.globalVariables[r]=data -- cache
    end
  end,
}

HC2._postHandlers={ -- create global variable, always local...?
  globalVariables=function(r,data,cType) 
    local v = HC2.rsrc.globalVariable[r]
    if not v then data._local=true; HC2.rsrc.globalVariables[data.name]=data end
  end,
}

_API_METHODS={
  GET=function(call,data,cType)
    local m,r = call:match("/([^/]+)/?(%w*)$")
    if m and HC2._getHandlers[m] then return HC2._getHandlers[m](r)
    else error("GET "..call.." not supported") end
  end,
  PUT=function(call,data,cType)
    local m,r = call:match("/([^/]+)/?(%w*)$")
    if m and HC2._putHandlers[m] then return HC2._putHandlers[m](r,data,cType)
    else error("PUT "..call.." not supported") end
  end,
  POST=function(call,data,cType) 
    local m,r = call:match("/([^/]+)/?(%w*)$")
    if m and HC2._getHandlers[m] then return HC2._getHandlers[m](r,data,cType)
    else error("POST "..call.." not supported") end
  end,
  DELETE=function(call,data,cType) error("DELETE not supported") end,
}

function HC2.apiCall(method,call,data,cType) 
  local mhandler = _API_METHODS[method]
  if mhandler then return mhandler(call,data,cType) else return null end
end

function HC2.listDevices()
  for id,dev in pairs(HC2.rsrc.devices) do
    if id > 3 then
      printf("deviceID:%-3d, name:%-20s type:%-30s, value:%s",id,dev.name,dev.type,dev.properties.value)
    end
  end
end

function HC2.listScenes()
  for id,scene in pairs(HC2.rsrc.scenes) do
    printf("SceneID :%-3d, name:%s",id,scene.name)
  end
end

local function setLocal(list,args)
  if args==true then 
    for _,d in pairs(list) do d._local=true end
  elseif type(args)=='table' then 
    for _,id in ipairs(args) do list[id]._local = true end 
  end
end

function HC2.localDevices(args) setLocal(HC2.rsrc.devices,args) end
function HC2.localGlobals(args) setLocal(HC2.rsrc.globalVariables,args) end
function HC2.localRooms(args) setLocal(HC2.rsrc.rooms,args) end
function HC2.localScenes(args) setLocal(HC2.rsrc.scenes,args) end

function HC2.createGlobal(name,value)
  HC2.rsrc.globalVariables[name]={name=name, value=value,modified=osTime(),_local=true}
end

-- lets make a vanilla device of type switch...
-- ToDo, make this more realistic, clone existing devices?
function HC2.createDevice(id,name,roomID,type,baseType,value)
  local d = 
  {
    _local=true,
    id=id,
    name=name,
    roomID = false,
    type = type or "com.fibaro.FGWP101",
    baseType = basType or "com.fibaro.FGWP",
    enabled = true,
    properties={
      value=value or false,
      armed = false,
      lastBreached = osTime(),
      deviceIcon = 42
    },
    actions = {
      abortUpdate = 1,
      reconfigure = 0,
      reset = 0,
      retryUpdate = 1,
      startUpdate = 1,
      turnOff = 0,
      turnOn = 0,
      setArmed = 1,
      forceArm = 0,
      updateFirmware = 1
    },
    created = osTime(),
    modified = osTime(),
  }
  if HC2.rsrc.devices[id] then
    error(_format("deviceID:%s already exists!",id),3)
  else HC2.rsrc.devices[id]=d end
end

HC2._debugFilters={}
function HC2.addDebugFilter(f,ret) HC2._debugFilters[#HC2._debugFilters+1]={str=f,ret=ret} end

function HC2.loadScenesFromDir(path)
  for file in lfs.dir(path) do
    if file ~= "." and file ~= ".." then
      local f = path..'/'..file
      local id,name = file:match("(%d+)_(.*)%.[Ll][Uu][Aa]")
      if id and name then
        HC2.registerScene(name,tonumber(id),f)
      end
    end
  end
end

function HC2.loadEmbedded()
  if _EMBEDDED then
    local short_src = _sceneFile or debug.getinfo(5).short_src
    local name,id
    if type(_EMBEDDED)=='table' then
      name,id = _EMBEDDED.name,_EMBEDDED.id
    else 
      name,id = short_src:match("(%d+)_(%w+)%.[lL][uU][aA]$")
      if name then id=tonumber(id)
      else name,id="Test",99 end
    end
    local scene = HC2.registerScene(name,id,short_src)
  end
end

function HC2.logFibaroCalls() fibaro._logFibaroCalls() end

------------------------------------------------------------------------------
-- _System
------------------------------------------------------------------------------
_System = {}
_System.createDevice = HC2.createDevice

function _System.dofile(file)
  local code = loadfile(file)
  setfenv(code,_SceneContext[coroutine.running()])
  code()
end

_System.createGlobal = HC2.createGlobal
_System.createDevice = HC2.createDevice
  
function _System._getInstance(id,inst)
  for co,env in pairs(_SceneContext) do
    if env.fibaroSelfId==id and env.__orgInstanceNumber==inst then return co,env end
  end
end

local _gTimers = nil

function _System.insertCoroutine(co)
  if _gTimers == nil then _gTimers=co
  elseif co.time < _gTimers.time then
    _gTimers,co.next=co,_gTimers
  else
    local tp = _gTimers
    while tp.next and tp.next.time < co.time do tp=tp.next end
    co.next,tp.next=tp.next,co
  end
  return co.co
end

function _System.dumpTimers()
  local t = _gTimers
  while t do printf("Timer %s at %s",t.name,osOrgDate("%X",t.time)) t=t.next end
end

osOrgTime,osOrgDate = os.time,os.date
function osTime(t) return math.floor(osTimeFrac(t)+0.5) end
function osTimeFrac(t) return t and osOrgTime(t) or _gTime end
function osDate(f,t) return osOrgDate(f,t or osTime()) end
_gTime = osOrgTime()
_gOrgTime = _gTime

function _System.setTime(start,stop)
  if type(start)=='number' then 
    stop = start
    start = osOrgDate("%X")
  elseif type(start)=='string' then
    if type(stop)~='number' then stop=60*24*3600 end -- default to 2 month
  end
  local h,m,s = start:match("(%d+):(%d+):?(%d*)")
  local d = osOrgDate("*t")
  d.hour,d.min,d.sec=h,m,s and s~="" and s or 0
  _gTime=osOrgTime(d)
  _gOrgTime = _gTime
  _eTime=_gTime+stop*3600
end

WAITINDEX=_SPEEDTIME and "SPEED" or "NORMAL"

_System.waitFor={
  ["SPEED"] = function(t) _gTime=_gTime+t return false end,
  ["NORMAL"] = function(t) socket.sleep(t) _gTime=_gTime+t return false end,
}

function _System.runTimers()
  while _gTimers ~= nil do
    --_System.dumpTimers()
    local co,now = _gTimers,osTimeFrac()
    if co.time > now then _System.waitFor[WAITINDEX](co.time-now) end
    _gTimers=_gTimers.next
    if co.env then setfenv(co.env.__sceneCode,co.env) end
    local stat,thread,time=coroutine.resume(co.co)
    if not stat then
      local name=co.name or co.env and "Scene:"..co.env.__fibaroSceneId or tostring(co.co)
      Log(LOG.ERROR,"Error in %s %s",name,tojson(thread))
      print(debug.traceback())
    end
    if time~='%%ABORT%%' and coroutine.status(co.co)=='suspended' then
      co.time,co.next=osTimeFrac()+time,nil
      _System.insertCoroutine(co)
    elseif co.env then
      local t = co.env.__threads
      co.env.__threads=t-1
      t=t-1
      if _debugFlags.threads then Log(LOG.LOG,"Dead thread %s, %s, t=%s",co.name or "", co.co,t) end
      if time=='%%ABORT%%' then 
        t0 = _System.clearAllTimeoutFilter(function(t) return t.env==co.env end)
        if _debugFlags.scenes then Log(LOG.LOG,"Aborting, %s, %s, t=%s, t0=%s",co.name or "", co.co,t,t0) end
        t=0
      end
      if t<=0 and co.env.__sceneCleanup then co.env.__sceneCleanup(co.co) end
      if co.cleanup then co.cleanup() end
    end
  end
  Log(LOG.SYSTEM,"%s:End of time(rs)",osOrgDate("%X",osTime()))
end

function _System.setTimeoutContext(fun,time,name,env,cleanup)
  time = (time or 0)/1000+osTimeFrac()
  local co = coroutine.create(fun)
  local cco = coroutine.running()
  env = env or _SceneContext[cco]
  _SceneContext[co]=env 
  if env then 
    local t = env.__threads
    if _debugFlags.threads then Log(LOG.LOG,"Starting thread %s, %s, t:%s",name or "", co,t) end
    env.__threads=t+1
  end
  return _System.insertCoroutine({co=co,time=time,name=name,env=env,cleanup=cleanup})
end

function _System.setTimeout(fun,time,name,context,cleanup)
  time = (time or 0)/1000+osTimeFrac()
  local co = coroutine.create(fun)
  return _System.insertCoroutine({co=co,time=time,name=name,context=nil,cleanup=cleanup})
end

function _System.clearTimeout(timer)
  if timer==nil then return end
  if _gTimers.co == timer then
    _gTimers = _gTimers.next
  else
    local tp = _gTimers
    while tp and tp.next do
      if tp.next.co == timer then tp.next = tp.next.next return end
      tp = tp.next
    end
  end
end

function _System.clearAllTimeoutFilter(filter,c)
  c=c or 0
  if _gTimers==nil then return c end
  if filter(_gTimers) then
    _gTimers = _gTimers.next
    return _System.clearAllTimeoutFilter(filter,c+1)
  else
    local tp = _gTimers
    while tp and tp.next do
      if filter(tp.next) then tp.next = tp.next.next c=c+1 end
      tp = tp.next
    end
    return c
  end
end

------------------------------------------------------------------------------
-- Event engine
------------------------------------------------------------------------------
function newEventEngine()
  local self,_handlers = { RULE='%%RULE%%' },{}

  local function _coerce(x,y)
    local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end
  end

  local _constraints = {}
  _constraints['=='] = function(val) return function(x) x,val=_coerce(x,val) return x == val end end
  _constraints['>='] = function(val) return function(x) x,val=_coerce(x,val) return x >= val end end
  _constraints['<='] = function(val) return function(x) x,val=_coerce(x,val) return x <= val end end
  _constraints['>'] = function(val) return function(x) x,val=_coerce(x,val) return x > val end end
  _constraints['<'] = function(val) return function(x) x,val=_coerce(x,val) return x < val end end
  _constraints['~='] = function(val) return function(x) x,val=_coerce(x,val) return x ~= val end end
  _constraints[''] = function(val) return function(x) return x ~= nil end end

  function self._compilePattern(pattern)
    if type(pattern) == 'table' then
      if pattern._var_ then return end
      for k,v in pairs(pattern) do
        if type(v) == 'string' and v:sub(1,1) == '$' then
          local var,op,val = v:match("$([%w_]*)([<>=~]*)([+-]?%d*%.?%d*)")
          var = var =="" and "_" or var
          local c = _constraints[op](tonumber(val))
          pattern[k] = {_var_=var, _constr=c, _str=v}
        else self._compilePattern(v) end
      end
    end
  end

  function self._match(pattern, expr)
    local matches = {}
    local function _unify(pattern,expr)
      if pattern == expr then return true
      elseif type(pattern) == 'table' then
        if pattern._var_ then
          local var, constr = pattern._var_, pattern._constr
          if var == '_' then return constr(expr)
          elseif matches[var] then return constr(expr) and _unify(matches[var],expr) -- Hmm, equal?
          else matches[var] = expr return constr(expr) end
        end
        if type(expr) ~= "table" then return false end
        for k,v in pairs(pattern) do if not _unify(v,expr[k]) then return false end end
        return true
      else return false end
    end
    return _unify(pattern,expr) and matches or false
  end

  local toHash,fromHash={},{}
  fromHash['property'] = function(e) return {e.type..e.deviceID,e.type} end
  fromHash['global'] = function(e) return {e.type..e.name,e.type} end
  toHash['property'] = function(e) return e.deviceID and 'property'..e.deviceID or 'property' end
  toHash['global'] = function(e) return e.name and 'global'..e.name or 'global' end

  function self.event(e,action) -- define rules - event template + action
    _assert(isEvent(e), "bad event format '%s'",tojson(e))
    self._compilePattern(e)
    local hashKey = toHash[e.type] and toHash[e.type](e) or e.type
    _handlers[hashKey] = _handlers[hashKey] or {}
    local rules = _handlers[hashKey]
    local rule,fn = {[self.RULE]=e, action=action}, true
    for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
      if _equal(e,rs[1][self.RULE]) then rs[#rs+1] = rule fn = false break end
    end
    if fn then rules[#rules+1] = {rule} end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    return rule
  end

  function self._handleEvent(e) -- running a posted event
    local env, _match = {event = e, p={}}, self._match
    local hasKeys = fromHash[e.type] and fromHash[e.type](e) or {e.type}
    for _,hashKey in ipairs(hasKeys) do
      for _,rules in ipairs(_handlers[hashKey] or {}) do -- Check all rules of 'type'
        local match = _match(rules[1][self.RULE],e)
        if match then
          if next(match) then for k,v in pairs(match) do env.p[k]=v match[k]={v} end env.context = match end
          for _,rule in ipairs(rules) do 
            if not rule._disabled then env.rule = rule rule.action(env) end
          end
        end
      end
    end
  end

  local function midnight() local t = osDate("*t"); t.hour,t.min,t.sec = 0,0,0; return osTime(t) end

  local function hm2sec(hmstr)
    local offs,sun
    sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
    if sun and (sun == 'sunset' or sun == 'sunrise') then
      hmstr,offs = fibaro:getValue(1,sun.."Hour"), tonumber(offs) or 0
    end
    local sg,h,m,s = hmstr:match("^(%-?)(%d+):(%d+):?(%d*)")
    _assert(h and m,"Bad hm2sec string %s",hmstr)
    return (sg == '-' and -1 or 1)*(h*3600+m*60+(tonumber(s) or 0)+(offs or 0)*60)
  end

  local function toTime(time)
    if type(time) == 'number' then return time end
    local p = time:sub(1,2)
    if p == '+/' then return hm2sec(time:sub(3))+osTime()
    elseif p == 'n/' then
      local t1,t2 = midnight()+hm2sec(time:sub(3)),osTime()
      return t1 > t2 and t1 or t1+24*60*60
    elseif p == 't/' then return  hm2sec(time:sub(3))+midnight()
    else return hm2sec(time) end
  end

  function self.post(e,time) -- time in 'toTime' format, see below.
    _assert(isEvent(e), "Bad event format %s",tojson(e))
    time = toTime(time or osTime())
    if time < osTime() then return nil end
    if _debugFlags.triggers then Log(LOG.LOG,"System trigger:%s at %s",tojson(e),osDate("%a %b %d %X",time)) end
    return _System.setTimeout(function() self._handleEvent(e) end,1000*(time-osTime()),"Main")
  end

  return self
end

Event = newEventEngine()

------------------------------------------------------------------------------
-- Fibaro functions
--
-- Adoption of FibaroSceneAPI.lua ...
--
-- Credits:
-- Edits by @petergebruers 2017-02-09:
-- fix HC user authentication (was: user:password in URL, is now: basic authentication).
-- fix chunked responses (was: use only chunk 1, is now: concatenate chunks). Fixes "getDevicesId".
-- add error checking and display in the HTTP part, to get sensible error messages.
-- Based on a version published by @riemers:
-- https://forum.fibaro.com/index.php?/topic/24319-tutorial-zerobrane-usage-lua-coding/
-- And that's based on:
-- https://www.domotique-fibaro.fr/topic/9248-zerobrainstudio-pour-ecrire-et-tester-vos-scripts-lua-directement-sur-votre-pc/

-- fibaro:getSourceTrigger()
-- fibaro:getSourceTriggerType()
-- fibaro:debug()
-- fibaro:countScenes([sceneID])
-- fibaro:startScene(sceneID[,args])
-- fibaro:args()
-- fibaro:stopScene(sceneID)
-- fibaro:sleep(time)
-- fibaro:abort()
-- fibaro:call(deviceID,method,...)
-- fibaro:killScenes(sceneID) -- not yet implemented 
-- fibaro:isSceneEnabled(sceneID) 
-- fibaro:setSceneEnabled(sceneID, enabled)
-- fibaro:getSceneRunConfig(sceneID) 
-- fibaro:setSceneRunConfig(sceneID, runConfig) 
-- fibaro:getRoomID(deviceID) 
-- fibaro:getSectionID(deviceID) 
-- fibaro:getType(deviceID) 
-- fibaro:calculateDistance(position1 , position2)
-- fibaro:getName(deviceID) 
-- fibaro:getRoomName(roomID) 
-- fibaro:getRoomNameByDeviceID(deviceID) 
-- fibaro:wakeUpDeadDevice(deviceID) -- only remote
-- fibaro:getDevicesId(filter)
-- fibaro:getAllDeviceIds()
-- fibaro:getIds(devices)
-- fibaro:get(deviceID, propertyName) 
-- fibaro:getValue(deviceID, propertyName)
-- fibaro:getModificationTime(deviceID ,propertyName)
-- fibaro:getGlobal(varName) 
-- fibaro:getGlobalValue(varName)
-- fibaro:getGlobalModificationTime(varName)
-- fibaro:setGlobal(varName ,value) 
-- HomeCenter -- only remote
-- setTimeout(function,time)
-- clearTimeout(ref)
-- net()
-- api()
-- split(string,char)
-- urlencode(string)
------------------------------------------------------------------------------
fibaro={}

function __assert_type(value ,typeOfValue) 
  if  type(value) ~= typeOfValue then error("Assertion failed: Expected"..typeOfValue ,3) end 
end 

function __convertToString(value) 
  if  type(value) == 'boolean'  then return  value and '1' or '0'
  elseif type(value) ==  'number' then return tostring(value) 
  elseif type(value) == 'table' then return json.encode(value) 
  else return value end
end

function __fibaro_get_device(deviceID,lcl) 
  __assert_type(deviceID ,"number")
  local d = HC2.rsrc.devices[deviceID]
  if lcl or (not _REMOTE) or (d and d._local) then return d
  else return api._get(true,"/devices/"..deviceID) end
end

function __fibaro_get_room(roomID,lcl) 
  __assert_type(roomID , "number") 
  local r = HC2.rsrc.rooms[roomID]
  if lcl or (not _REMOTE) or (r and r._local) then return r
  else return api._get(true,"/rooms/"..roomID) end
end

function __fibaro_get_global_variable(varName,lcl)
  __assert_type(varName ,"string")
  local v = HC2.rsrc.globalVariables[varName]
  if lcl or (not _REMOTE) or (v and v._local) then return v
  else return api._get(true,"/globalVariables/"..varName) end
end

function __fibaro_get_device_property(deviceID ,propertyName, lcl)
  local d = HC2.rsrc.devices[deviceID]
  if lcl or (not _REMOTE) or (d and d._local) then
    return d and {value=__convertToString(d.properties[propertyName]),modified=d.modified}
  else return api._get(true,"/devices/"..deviceID.."/properties/"..propertyName) end
end

function __fibaro_get_scene(sceneID,lcl) 
  __assert_type(sceneID, "number")
  local s = HC2.getScene(sceneID)
  if lcl or (not _REMOTE) or (s and s._local) then return s
  else return api._get(true,"/scenes/"..sceneID) end
end

function fibaro:getSourceTrigger() return Scene.global().__fibaroSceneSourceTrigger end
function fibaro:getSourceTriggerType() return Scene.global().__fibaroSceneSourceTrigger["type"] end
function fibaro:debug(str)
  str=tostring(str)
  for _,f in ipairs(HC2._debugFilters) do
    local m = str:match(f.str)
    if m then if f.ret then return else str=m; break end end
  end 
  local env = Scene.global()
  print(_format("[%d:%d]%s %s",env.__fibaroSceneId,env.__orgInstanceNumber,osDate("[DEBUG] %H:%M:%S:"),str)) 
end
function fibaro:sleep(n) return coroutine.yield(coroutine.running(),n/1000) end
function fibaro:abort() coroutine.yield(coroutine.running(),'%%ABORT%%') end

function fibaro:countScenes(sceneID) 
  sceneID = sceneID or Scene.global().__fibaroSceneId
  local scene = __fibaro_get_scene(sceneID) 
  return scene ==  nil and 0 or scene.runningInstances
end

function fibaro:isSceneEnabled(sceneID) 
  local scene = __fibaro_get_scene(sceneID) 
  if  scene ==  nil then return  nil end
  return scene.runConfig == "TRIGGER_AND_MANUAL" or scene.runConfig == "MANUAL_ONLY"
end

function fibaro:killScenes(sceneID)
  local scene = __fibaro_get_scene(sceneID,true)
  if not scene then return end
  if scene._local then
    error("local killScene not implemented yet")
  elseif _REMOTE then api._post(true,"/scenes/"..sceneID.."/action/stop") end
end

function fibaro:startScene(sceneID,args)
  local scene = __fibaro_get_scene(sceneID,true)
  if not scene then return end
  if scene._local then Scene.start(scene,{type='other'},args) 
  elseif _REMOTE then api._post(true,"/scenes/"..sceneID.."/action/start",args and {args=args} or nil)  end
end

function fibaro:args() return Scene.global().__fibaroSceneArgs end

function fibaro:setSceneEnabled(sceneID , enabled) 
  __assert_type(sceneID ,"number") 
  __assert_type(enabled ,"boolean")
  local scene = __fibaro_get_scene(sceneID,true)
  local runConfig = enabled ==true and "TRIGGER_AND_MANUAL" or "DISABLED"
  if (not _REMOTE) or (scene and scene._local) then
    if scene then scene.runConfig = runConfig end
  else api._put(true,"/scenes/"..sceneID, {id = sceneID ,runConfig = runConfig}) end 
end

function fibaro:getSceneRunConfig(sceneID) 
  local scene = __fibaro_get_scene(sceneID) 
  if scene ==  nil then return  nil end
  return scene.runConfig
end

function fibaro:setSceneRunConfig(sceneID ,runConfig) 
  __assert_type(sceneID ,"number") 
  __assert_type(runConfig ,"string")
  local scene = __fibaro_get_scene(sceneID,true)
  if (not _REMOTE) or (scene and scene._local) then 
    if scene then scene.runConfig = runConfig end
  else api._put(true,"/scenes/"..sceneID, {id = sceneID ,runConfig = runConfig}) end
end

function fibaro:getRoomID(deviceID) 
  local dev = HC2.getDevice(deviceID)
  if  dev ==  nil then return  nil end
  return dev.roomID
end

function fibaro:getSectionID(deviceID) 
  local dev = HC2.getDevice(deviceID)
  if  dev ==  nil then return  nil end
  if  dev.ROOMID ~=  0  then 
    return HC2.getRoom(dev.ROOMID).sectionID
  end 
  return  0 
end

function fibaro:getType(deviceID) 
  local dev = HC2.getDevice(deviceID)
  if  dev == nil then return  nil end
  return dev.type
end

function fibaro:get(deviceID ,propertyName) 
  local property = __fibaro_get_device_property(deviceID , propertyName)
  if property ==  nil then return  nil end
  return __convertToString(property.value) , property.modified
end

function fibaro:getValue(deviceID , propertyName) return (fibaro:get(deviceID ,propertyName)) end

function fibaro:getModificationTime(deviceID ,propertyName) return select(2,fibaro:get(deviceID,propertyName)) end

function fibaro:getGlobal(varName) 
  local globalVar = __fibaro_get_global_variable(varName) 
  if globalVar ==  nil then return  nil end
  return globalVar.value ,globalVar.modified
end

function fibaro:getGlobalValue(varName) return (fibaro:getGlobal(varName)) end

function fibaro:getGlobalModificationTime(varName) return select(2,fibaro:getGlobal(varName)) end

function fibaro:setGlobal(varName ,value) 
  __assert_type(varName ,"string")
  local globalVar = __fibaro_get_global_variable(varName,true)
  if (not _REMOTE) or (globalVar and globalVar._local) then
    if not globalVar and _AUTOCREATEGLOBALS then
      HC2.rsrc.globalVariables[varName]={name=varName,_local=true}
      fibaro:setGlobal(varName,value)
      return
    end
    globalVar.value,globalVar.modified= tostring(value),osTime()
    if _debugFlags.globals then Log(LOG.LOG,"Setting global %s='%s'",varName,value) end
    Event.post({type='global',name=globalVar.name}) -- trigger
  elseif _REMOTE then
    api._put(true,"/globalVariables/"..varName ,{value=tostring(value), invokeScenes= true}) 
  elseif _AUTOCREATEGLOBALS then
    HC2.rsrc.globalVariables[varName]={name=varName,_local=true}
    fibaro:setGlobal(varName,value)
  else
    error("Non existent fibaro global: "..varName)
  end
end

function fibaro:calculateDistance(position1 , position2) 
  __assert_type(position1 ,"string") 
  __assert_type(position2 ,"string") 
  lat1,lon1=position1:match("(.*);(.*)")
  lat2,lon3=position2:match("(.*);(.*)")
  lat1,lon1,lat2,lon2=tonumber(lat1),tonumber(lon1),tonumber(lat2),tonumber(lon2)
  _assert(lat1 and lon1 and lat2 and lon2,"Bad arguments to fibaro:calculateDistance")
  local dlat = math.rad(lat2-lat1)
  local dlon = math.rad(lon2-lon1)
  local sin_dlat = math.sin(dlat/2)
  local sin_dlon = math.sin(dlon/2)
  local a = sin_dlat * sin_dlat + math.cos(math.rad(lat1)) * math.cos(math.rad(lat2)) * sin_dlon * sin_dlon
  local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
  local d = 6378 * c
  return d
end

function setAndPropagate(id,key,value)
  local d = HC2.rsrc.devices[id].properties
  if d[key] ~= value then
    d[key]=value
    HC2.rsrc.devices[id].modified=osTime()
    Event.post({type='property', deviceID=id, propertyName=key})
  end
end

_specCalls={}
_specCalls['setProperty'] = function(id,prop,...) setAndPropagate(id,prop,({...})[1]) end 
_specCalls['setColor'] = function(id,R,G,B) setAndPropagate(id,"color","RGB") end
_specCalls['setArmed'] = function(id,value) setAndPropagate(id,"armed",value) end
_specCalls['sendPush'] = function(id,msg) end -- log to console?
_specCalls['pressButton'] = function(id,msg) end -- simulate VD?
_specCalls['setPower'] = function(id,value) setAndPropagate(id,"power",value) end

function fibaro:call(deviceID ,actionName ,...) 
  deviceID =  tonumber(deviceID) 
  __assert_type(actionName ,"string")
  local dev = HC2.getDevice(deviceID)
  if dev and dev._local then
    if _specCalls[prop] then _specCalls[actionName](deviceID,...) return end 
    local value = ({turnOff=false,turnOn=true,open=true, on=true,close=false, off=false})[actionName] or 
    (actionName=='setValue' and tostring(({...})[1]))
    if value==nil then error(_format("fibaro:call(..,'%s',..) is not supported, fix it!",actionName)) end
    setAndPropagate(deviceID,'value',value)
  elseif _REMOTE and dev then
    local args = "" 
    for i,v in  ipairs ({...})  do args = args.. '&arg'..tostring(i)..'='..urlencode(tostring(v)) end 
    api._get(true,"/callAction?deviceID="..deviceID.."&name="..actionName..args) 
  end
end

function fibaro:getName(deviceID) 
  __assert_type(deviceID ,'number') 
  local dev = HC2.getDevice(deviceID)
  return dev and dev.name
end

function fibaro:getRoomName(roomID) 
  __assert_type(roomID ,'number') 
  local room = __fibaro_get_room(roomID) 
  return room and room.name 
end

function fibaro:getRoomNameByDeviceID(deviceID) 
  __assert_type(deviceID,'number') 
  local dev = HC2.getDevice(deviceID)
  if  dev == nil then return  nil end
  local room =HC2.getRoom(dev.ROOMID)
  return dev.ROOMID==0 and 'unassigned' or room and room.name
end

function fibaro:wakeUpDeadDevice(deviceID ) 
  __assert_type(deviceID ,'number') 
  fibaro:call(1,'wakeUpDeadDevice',deviceID) 
end

--[[
Expected input:
{
  name: value,        //: require name to be equal to value
  properties: {       //:
    volume: "nil",    //: require property volume to exist, any value
    ip: "127.0.0.1"   //: require property ip to equal 127.0.0.1
  },
  interface: ifname   //: require device to have interface ifname

}
]]--
function fibaro:getDevicesId(filter)
  if type(filter) ~= 'table' or (type(filter) == 'table' and next(filter) == nil) then
    return fibaro:getIds(fibaro:getAllDeviceIds())
  end
  local args = '/?'
  for c, d in pairs(filter) do
    if c == 'properties' and d ~= nil and type(d) == 'table' then
      for a, b in pairs(d) do
        if b == "nil" then args = args .. 'property=' .. tostring(a) .. '&'
        else args = args .. 'property=[' .. tostring(a) .. ',' .. tostring(b) .. ']&' end
      end
    elseif c == 'interfaces' and d ~= nil and type(d) == 'table' then
      for a, b in pairs(d) do args = args .. 'interface=' .. tostring(b) .. '&' end
    else args = args .. tostring(c) .. "=" .. tostring(d) .. '&' end
  end
  args = string.sub(args, 1, -2)
  return fibaro:getIds(api.get('/devices'..args))
end

function fibaro:getAllDeviceIds()
  if _REMOTE then
    return api.get('/devices/')
  else
    local res={}
    for id,_ in pairs(HC2.rsrc.devices) do res[#res+1]=id end
    return res
  end
end

function fibaro:getIds(devices)
  local ids = {}
  for _,a in pairs(devices) do
    if a ~= nil and type(a) == 'table' and a['id'] ~= nil and a['id'] > 3 then
      table.insert(ids, a['id'])
    end
  end
  return ids
end

function split(s, sep)
  local fields = {}
  sep = sep or " "
  local pattern = string.format("([^%s]+)", sep)
  string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
  return fields
end

function urlencode(str)
  if str then
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w %-%_%.%~])", function(c)
        return ("%%%02X"):format(string.byte(c))
      end)
    str = str:gsub(" ", "%%20")
  end
  return str	
end

function urldecode(str) return str:gsub('%%(%x%x)',function (x) return string.char(tonumber(x,16)) end) end

net = {} -- An emulation of Fibaro's net.HTTPClient
-- It is synchronous, but synchronous is a speciell case of asynchronous.. :-)
function net.HTTPClient() return _HTTP end
_HTTP = {}
-- Not sure I got all the options right..
function _HTTP:request(url,options)
  local resp = {}
  local req = options.options
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
    options.success({status=status, headers=headers, data=table.concat(resp)})
  else
    options.error(status)
  end
end

api={} -- Emulation of api.get/put/post
local function apiCall(flag,method,call,data,cType)
  if flag and _debugFlags.hc2calls then Log(LOG.LOG,"HC2 call:%s:%s",method,call) end
  local resp = {}
  local req={ method=method, timeout=5000,
    url = "http://".._HC2_IP.."/api"..call,sink = ltn12.sink.table(resp),
    user=_HC2_USER,
    password=_HC2_PWD,
    headers={}
  }
  if data then
    req.headers["Content-Type"] = cType
    req.headers["Content-Length"] = #data
    req.source = ltn12.source.string(data)
  end
  local r, c = http.request(req)
  if not r then
    Log(LOG.ERROR,"Error connnecting to HC2: '%s' - URL: '%s'.",c,req.url)
    os.exit(1)
  end
  if c>=200 and c<300 then
    return resp[1] and json.decode(table.concat(resp)) or nil
  end
  Log(LOG.ERROR,"HC2 returned error '%d %s' - URL: '%s'.",c,resp[1] or "",req.url)
  os.exit(1)
end

function api.get(call) return HC2.apiCall("GET",call) end
function api.put(call, data) return HC2.apiCall("PUT",call,data,"application/json") end
function api.post(call, data) return HC2.apiCall("POST",call,data,"application/json") end
function api.delete(call, data) return HC2.apiCall("DELETE",call,data,"application/json") end

function api._get(l,call) return apiCall(l,"GET",call) end
function api._put(l,call, data) return apiCall(l,"PUT",call,json.encode(data),"application/json") end
function api._post(l,call, data) return apiCall(l,"POST",call,json.encode(data),"application/json") end
function api._delete(l,call, data) return apiCall(l,"DELETE",call,json.encode(data),"application/json") end

HomeCenter = {
  PopupService = {
    publish = function(request)
      local response = api.post('/popups', request)
      return response
    end
  },
  SystemService = {
    reboot = function()
    end,
    shutdown = function()
    end
  }
}

-------- Fibaro log support --------------
-- Logging of fibaro:* calls -------------
function fibaro._logFibaroCalls()
  if fibaro._orgf then return end
  fibaro._orgf={}
  local function interceptFib(fs,name,flag,spec)
    local fun,fstr = fibaro[name],fs:match("r") and "fibaro:%s(%s%s%s) = %s" or "fibaro:%s(%s%s%s)"
    fibaro._orgf[name]=fun
    if spec then 
      fibaro[name] = function(obj,...) 
        if _debugFlags[flag] then return spec(obj,fibaro._orgf[name],...) else return fibaro._orgf[name](obj,...)  end 
      end 
    else 
      fibaro[name] = function(obj,id,...)
        local id2,args = type(id) == 'number' and Util.reverseVar(id) or '"'..(id or "<ID>")..'"',{...}
        local status,res,r2 = pcall(function() return fibaro._orgf[name](obj,id,table.unpack(args)) end)
        if status and _debugFlags[flag] then
          Debug(true,fstr,name,id2,(#args>0 and "," or ""),json.encode(args):sub(2,-2),json.encode(res))
        elseif not status then
          error(string.format("Err:fibaro:%s(%s%s%s), %s",name,id2,(#args>0 and "," or ""),json.encode(args):sub(2,-2),res),3)
        end
        if fs=="mr" then return res,r2 else return res end
      end
    end
  end

  interceptFib("","call","fibaro")
  interceptFib("","setGlobal","fibaroSet") 
  interceptFib("mr","getGlobal","fibaroGet")
  interceptFib("r","getGlobalValue","fibaroGet")
  interceptFib("mr","get","fibaroGet")
  interceptFib("r","getValue","fibaroGet")
  interceptFib("","killScenes","fibaro")
  interceptFib("","sleep","fibaro",
    function(obj,fun,time) 
      Debug(true,"fibaro:sleep(%s) until %s",time,osDate("%X",osTime()+math.floor(0.5+time/1000)))
      fun(obj,time) 
    end)
  interceptFib("","startScene","fibaroStart",
    function(obj,fun,id,args) 
      local a = args and #args==1 and type(args[1])=='string' and (json.encode({(urldecode(args[1]))})) or args and json.encode(args)
      Debug(true,"fibaro:start(%s%s)",id,a and ","..a or "")
      fun(obj,id, args) 
    end)
end

------------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------------
Log(LOG.WELCOME,_format("HC2 SceneRunner v%s %s",_version,_fix))

_mainPosts={}
function HC2.post(event,t) _mainPosts[#_mainPosts+1]={event,t} end
main()                             -- Call main to setup scenes
Event.post({type='autostart'})     -- Post autostart to get things going
for _,e in ipairs(_mainPosts) do Event.post(e[1],e[2]) end

if _SPEEDTIME then                -- If speeding, check every hour if we should exit
  local endTime= osTime()+_SPEEDTIME*3600
  local function cloop()
    if osTime()>endTime then
      Log(LOG.SYSTEM,"%s, End of time (%s hours) - exiting",osDate("%c"),_SPEEDTIME)
      os.exit()
    end   
    _System.setTimeout(cloop,1000*3600,"Speed watch")
  end
  cloop()
end

function eventServer(port)
  local someRandomIP = "192.168.1.122" --This address you make up
  local someRandomPort = "3102" --This port you make up  
  local mySocket = socket.udp() --Create a UDP socket like normal
  mySocket:setpeername(someRandomIP,someRandomPort) 
  local myDevicesIpAddress, somePortChosenByTheOS = mySocket:getsockname()-- returns IP and Port 
  local host = myDevicesIpAddress
  Log(LOG.LOG,"Remote Event listener started at %s:%s",host,port)
  local s,c,err = assert(socket.bind("*", port))
  local i, p = s:getsockname()
  local timeoutCounter = 0
  assert(i, p)
  return function()
    local co = coroutine.running()
    while true do
      s:settimeout(0)
      repeat
        c, err = s:accept()
        if err == 'timeout' then
          timeoutCounter = timeoutCounter+1
          local wt = _POLLINTERVAL
          if timeoutCounter > 5*60 then wt=wt*100 end
          coroutine.yield(co,wt/1000) 
        end
      until err ~= 'timeout'
      timeoutCounter = 0
      c:settimeout(0)
      repeat
        local l, e, j = c:receive()
        if l and l:sub(1,3)=='GET' then -- Support GET...
          j=l:match("GET[%s%c]*/(.*)HTTP/1%.1$")
          j = urldecode(j)
          if _debugFlags.eventserver then Debug(true,"External trigger:%s",j) end
          if Scene.validateChars then Scene.validateChars(j,"Bad chars in in external trigger:%s") end
          j=json.decode(j)
          Event.post(j)
        elseif j and j~="" then
          --c:close()
          if _debugFlags.eventserver then Debug(true,"External trigger:%s",j) end
          if Scene.validateChars then Scene.validateChars(j,"Bad chars in external trigger:%s") end
          j=json.decode(j)
          Event.post(j)
        end
        --coroutine.yield(co,_POLLINTERVAL/1000)
      until (j and j~="") or e == 'closed'
    end
  end
end

_POLLINTERVAL = 200 
if _EVENTSERVER then
  _System.setTimeout(eventServer(_EVENTSERVER),100,"EVENTSERVER")
end

_System.runTimers()                -- Run our simulated threads...