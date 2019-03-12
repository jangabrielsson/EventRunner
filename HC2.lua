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

json library - Copyright (c) 2018 rxi https://github.com/rxi/json.lua

--]]

_version,_fix = "0.4","fix7"     
_sceneName = "HC2 emulator"

_REMOTE=false                 -- Run remote, fibaro:* calls functions on HC2, only non-local resources
_EVENTSERVER = 6872          -- To receieve triggers from external systems, HC2, Node-red etc.
_SPEEDTIME = false--24*180          -- Speed through X hours, if set to false run in real time
_BLOCK_PUT=true              -- Block http PUT commands to the HC2 - e.g. changing resources on the HC2
_BLOCK_POST=true             -- Block http POST commands to the HC2 - e.g. creating resources on the HC2
_AUTOCREATEGLOBALS=true      -- Will (silently) autocreate a local fibaro global if it doesn't exist
_AUTOCREATEDEVICES=true      -- Will (silently) autocreate a local fibaro device if it doesn't exist
_VALIDATECHARS = true        -- Check rules for invalid characters (cut&paste, multi-byte charqcters)
_COLOR = true                -- Log with colors on ZBS Output console
_HC2_FILE = "HC2.data"

_HC2_IP="192.198.1.xx"       -- HC2 IP address
_HC2_USER="xxx@yyy"          -- HC2 user name
_HC2_PWD="xxxxxx"            -- HC2 password

local creds = loadfile("credentials.lua") -- To not accidently commit credentials to Github...
if creds then creds() end

--------------------------------------------------------
-- Main, register scenes, create temporary deviceIDs, schedule triggers...
--------------------------------------------------------
function main()

  HC2.setupConfiguration(true,true) -- read in configuration from stored local file, or from remote HC2

  if not _REMOTE or _RUNLOCAL then -- If we are remote don't try to access resources on the HC2
    HC2.localDevices(true) -- set all devices to local
    HC2.localGlobals(true) -- set all globals to local
    HC2.localRooms(true)   -- set all rooms to local
    --HC2.localScenes(true)  -- set all scenes to local
  end

  --HC2.remoteDevices({66,88}) -- We still want to run local, except for deviceID 66,88 that will be controlled on the HC2

  HC2.createDevice(99,"Test")
  HC2.loadEmbedded()

--HC2.loadScenesFromDir("scenes") -- Load all files with name <ID>_<name>.lua from dir, Ex. 11_MyScene.lua
--HC2.createDevice(77,"Test") -- Create local deviceID 77 with name "[[Test"

  HC2.registerScene("SceneTest",99,"sceneTest.lua",nil,
    {"+/00:00:02;call(66,'turnOn')",      -- breached after 2 sec
      "+/00:01:02;call(66,'turnOff')"})    -- safe after 1min and 2sec 

--HC2.runTriggers{"+/00:00;startScene(".._EMBEDDED.id..")"}
--HC2.registerScene("P1",20,"PubSub1EM.lua")
--HC2.registerScene("P2",21,"PubSub2EM.lua")

--HC2.registerScene("EventRunnerEM",10,"EventRunnerEM.lua")
--HC2.registerScene("Supervisor",11,"SupervisorEM.lua")
--HC2.registerScene("iosLocator",14,"IOSLOcatorEM.lua")

--HC2.listDevices()
--HC2.listScenes()
--HC2.registerScene("Scene1",55,"55_Simple.lua",nil,{"+/00:10;call(66,'turnOn')","+/00:20;call(66,'turnOff')"})
--HC2.registerScene("Scene1",11,"EventRunnerA.lua")
--HC2.registerScene("Scene1",12,"GEA 6.11.lua") 
--HC2.registerScene("Scene1",13,"Main scene FTBE v1.3.0.lua",{Darkness=0,TimeOfDay='Morning'})

--Log fibaro:* calls
  HC2.logFibaroCalls()
--Debug filters can be used to trim debug output from noisy scenes...
--HC2.addDebugFilter("Memory used:",true) 
--HC2.addDebugFilter("GEA run since",true)
--HC2.addDebugFilter("%.%.%. check running",true)
  HC2.addDebugFilter("%b<>(.*)</.*>")
end

_debugFlags = { 
  threads=false, triggers=false, eventserver=false, hc2calls=true, globals=false, 
  fibaro=true, fibaroSleep=false, fibaroSet=true, fibaroStart=false, web=true,
}
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

------------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------------
function startup()
  Log(LOG.WELCOME,_format("HC2 SceneRunner v%s %s",_version,_fix))

  _mainPosts={}
  function HC2.post(event,t) _mainPosts[#_mainPosts+1]={event,t} end
  main()                             -- Call main to setup scenes

  local endTime= osTime()+(_SPEEDTIME or 365*24)*3600
  local function cloop()
    if osTime()>endTime then
      Log(LOG.SYSTEM,"%s, End of time (%s hours) - exiting",osDate("%c"),_SPEEDTIME)
      os.exit()
    end   
    _System.setTimeout(cloop,1000*3600,"Speed watch")
  end
  cloop()

  ProcessManager = _System.makeProcessManager()
  _System.idleHandler = ProcessManager.idleHandler

  local ipAddress = _System.getIPadress()

  wServer = makeWebserver(ipAddress)
  wServer.createServer("Event server2",_EVENTSERVER,
    function(client,call,ref) -- GET handler
      if _debugFlags.web then Log(LOG.LOG,"GET %s",call) end
      local page = Pages.getPath(call)
      if page~=null then 
        client:send(page) 
        return
      end
      local code = call:match("/emu/code/(.*)")
      if code then
        loadstring(urldecode(code))()
        client:send("HTTP/1.1 302 Found\nLocation: "..(ref or "/emu/triggers").."\n")
        return
      end
      local method,id,action,args = call:match("/emu/fibaro/(%w+)/(%d+)/(.-)%?(.*)")
      if args and args~="" then
        args=args:match("value=(.*)")
      else args = nil end
      if method then
        printf("Calling fibaro:%s(%s,'%s')",method,id,action,args and _format(", '%s'",args) or "")
        fibaro[method](fibaro,tonumber(id),action,args)
        client:send("HTTP/1.1 302 Found\nLocation: "..(ref or "/emu/main").."\n")
        return
      end
    end,
    function(client,call,args)  -- POST handler
      if _debugFlags.web then Log(LOG.LOG,"POST %s %s",call,args) end
      client:send("HTTP/1.1 201 Created\nETag: \"c180de84f991g8\"\n")
      for i=1,#gg do printf("%s",gg:byte(i)) end
      if call:match("^/api/") then api.post(call,json.decode(args)) return end
      local id = call:match("^/trigger/(%-?%d*)")
      if id then
        id=tonumber(id)
        if id then Event.post({type='other', _id=math.abs(id), _args=json.decode(args)}) 
        else Event.post(json.decode(args)) end
        return
      end
      if call=='/trigger' then
        e = json.decode(args)
        Event.post(e)
        return
      end
    end,
    function(client,call,args) -- PUT handler
      if _debugFlags.web then Log(LOG.LOG,"PUT %s %s",call,args) end
    end)

  Event.post({type='autostart'})     -- Post autostart to get things going
  for _,e in ipairs(_mainPosts) do Event.post(e[1],e[2]) end

  if _REMOTE then ER.announceEmulator(ipAddress,_EVENTSERVER) end
  Log(LOG.LOG,"Web GUI at http://%s:%s/emu/main",ipAddress,_EVENTSERVER)
  _System.runTimers()                -- Run our simulated threads...
  os.exit()
end

------------------------------------------------------------------------
-- Support functions - don't touch
------------------------------------------------------------------------
require('mobdebug').coro()   -- Allow debugging of Lua coroutines

--mime = require('mime')
https = require ("ssl.https")
ltn12 = require("ltn12")
--json = require("json")
socket = require("socket")
http = require("socket.http")
lfs = require("lfs")

_LOCAL= not _REMOTE
_HCPrompt="[HC2]"
function printf(...) print(string.format(...)) end -- Lazy printing - should use Log(...)

_format=string.format
LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ERROR = "Tomato"}
-- ZBS colors, works best with dark color scheme http://bitstopixels.blogspot.com/2016/09/changing-color-theme-in-zerobrane-studio.html
if _COLOR=='Dark' then
  _LOGMAP = {orange="\027[33m",white="\027[37m",Cyan="\027[1;43m",green="\027[32m",Tomato="\027[39m"} -- ANSI escape code, supported by ZBS
else
  _LOGMAP = {orange="\027[33m",white="\027[34m",Cyan="\027[35m",green="\027[32m",Tomato="\027[31m"} -- ANSI escape code, supported by ZBS
end
_LOGEND = "\027[0m"
--[[Available colors in Zerobrane
for i = 0,8 do
  print(("%s \027[%dmXYZ\027[0m normal"):format(30+i, 30+i))
end
for i = 0,8 do
  print(("%s \027[1;%dmXYZ\027[0m bright"):format(38+i, 30+i))
end
--]]
function _UserMsg(color,message,...)
  color = _COLOR and _LOGMAP[color] or ""
  local args = type(... or 42) == 'function' and {(...)()} or {...}
  message = string.format(message,table.unpack(args))
  fibaro:debug(string.format("%s%s %s%s",color,osOrgDate("%a %b %d:",osTime()),message,_COLOR and _LOGEND or "")) 
  return message
end
function _Msg(color,message,...)
  color = _COLOR and _LOGMAP[color] or ""
  local args = type(... or 42) == 'function' and {(...)()} or {...}
  message = _format(message,table.unpack(args))
  local env,sceneid = Scene.global(),_HCPrompt
  if env then sceneid = _format("[%s:%s]",env.__fibaroSceneId,env.__orgInstanceNumber) end
  print(string.format("%s#%s%s %s%s",color,sceneid,osOrgDate("%H:%M:%S, %a %b %d:",osTime()),message,_COLOR and _LOGEND or "")) 
  return message
end
function Debug(flag,message,...) if flag then _Msg(LOG.DEBUG,message,...) end end
function Log(color,message,...) return _Msg(color,message,...) end

function _assert(test,msg,...) 
  if not test then 
    msg = _format(msg,...) error(msg,3) 
  end 
end
function _assertf(test,msg,fun) if not test then msg = _format(msg,fun and fun() or "") error(msg,3) end end

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
function isRemoteEvent(e) return type(e)=='table' and type(e[1])=='string' end
function encodeRemoteEvent(e) return {urlencode(json.encode(e)),'%%ER%%'} end
function decodeRemoteEvent(e) return (json.decode((urldecode(e[1])))) end
------------------------------------------------------------------------------
-- SSupport functions
-- Scene
-- _System
-- HC2
------------------------------------------------------------------------------

function support()
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

  function YIELD(ms)
    local co = coroutine.running()
    if _SceneContext[co] then 
      BREAKIDLE=true; coroutine.yield(co,(ms and ms > 0 and ms or 100)/1000) 
    end
  end
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
    ER.checkForEventRunner(scene)
    scene.code,msg=loadfile(file)
    _assert(scene.code~=nil,"Error in scene file %s: %s",file,msg)
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
    globals.__debugName=_format("[%s:%s]",scene.id,scene.runningInstances+1)
    globals.__sceneCleanup = function(co)
      if (not scene._terminateMsg) or (scene._terminateMsg and not scene._terminateMsg(scene.id,env.__orgInstanceNumber,env)) then
        Log(LOG.LOG,"Scene %s terminated (%s)",env.__debugName,co)
      end
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
    if isRemoteEvent(args) then args=decodeRemoteEvent(args) end
    if (not scene._startMsg) or (scene._startMsg and not scene._startMsg(scene.id,scene.runningInstances,env)) then
      Log(LOG.LOG,"Scene %s started (%s), trigger:%s %s(%s)",globals.__debugName,scene.name,tojson(event),args and tojson(args) or "",tr)
    end
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

  function HC2.runTriggers(tab)
    if type(tab)=='string' then tab={tab} end
    for _,s in ipairs(tab or {}) do
      local t,cmd = s:match("(.-);(.*)")
      cmd = loadstring("fibaro:"..cmd)
      Event.post(cmd,t)
    end
  end

  function HC2.registerScene(name,id,file,globVars,triggers)
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
    HC2.runTriggers(triggers)
  end

  local function patchID(t) 
    local res,c={},0; 
    for k,v in pairs(t) do 
      if type(v)=='table' then res[tonumber(k)]=v c=c+1 end 
    end 
    return res,c
  end

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
      for _,v in ipairs(s) do 
        local scene = api._get(false,"/scenes/"..v.id)
        rsrc.scenes[v.id] = scene; c2=c2+1 
        scene.EventRunner = scene.lua and scene.lua:match(ER.gEventRunnerKey)
      end
      s = api._get(false,"/iosDevices")
      for _,v in ipairs(s) do rsrc.iosDevices[v.id] = v end
      rsrc.info = api._get(false,"/settings/info")
      rsrc.location = api._get(false,"/settings/location")
      if file then HC2.writeConfigurationToFile(file2) end
    else
      local f = io.open(file2)
      if f then
        Log(LOG.SYSTEM,"Reading and decoding configuration from %s",file2)
        --local data = f:read("*all")
        --rsrc = json.decode(data)
        rsrc=persistence.load(file2);
        for n,_ in pairs(rsrc.globalVariables) do c1=c1+1 end
        rsrc.devices,c3=patchID(rsrc.devices); rsrc.scenes,c2=patchID(rsrc.scenes); 
        rsrc.rooms,c4=patchID(rsrc.rooms); rsrc.sections,_=patchID(rsrc.sections); 
        rsrc.iosDevices,_=patchID(rsrc.iosDevices); 
        HC2.rsrc=rsrc
      else Log(LOG.SYSTEM,"No HC2 data file found (%s)'",file2) end
    end
    if not rsrc.info.serverStatus then
      rsrc.info={serverStatus=os.time(), currentVersion={version="100.00"}}
    end
    Log(LOG.SYSTEM,"Configuration setup, Globals:%s, Scenes:%s, Device:%s, Rooms:%s",c1,c2,c3,c4)
  end

  function HC2.writeConfigurationToFile(file)
    Log(LOG.SYSTEM,"Writing configuration data to '%s'",file)
    persistence.store(file, HC2.rsrc);
  end

  function HC2.getRsrc(name,id,f)
    local rsrcs=HC2.rsrc[name]
    local rsrc=rsrcs[id]
    --if not _REMOTE and rsrc then rsrc._local = true end
    if rsrc and rsrc._local or f then
      -- found
    elseif _REMOTE and rsrc then
      local rsrc = api._get(false,"/"..name.."/"..id)
      rsrcs[id] = rsrc
    elseif not rsrc then-- rsrc doesn't exists
      if name=='globalVariables' and _AUTOCREATEGLOBALS then
        rsrc = HC2.createGlobal(id)
      elseif name=='devices' and _AUTOCREATEDEVICES then
        rsrc = HC2.createDevice(id,tostring(id))
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
        if HC2.rsrc[name][i] and not HC2.rsrc[name][i]._local then 
          HC2.rsrc[name][i] = r3
          if name=='scenes' then
            HC2.rsrc[name][i] = api._get(false,"/"..name.."/"..r3.id)
          end
        end
      end
    end
    for id,r in pairs(HC2.rsrc[name]) do res[#res+1]=r 
      --r._local=(not _REMOTE) and true or r._local 
    end
    return res
  end

  function HC2.getDevice(id,f) return HC2.getRsrc('devices',id,f) end
  function HC2.getGlobal(id,f) return HC2.getRsrc('globalVariables',id,f) end
  function HC2.getScene(id,f) return HC2.getRsrc('scenes',id,f) end
  function HC2.getRoom(id,f) return HC2.getRsrc('rooms',id,f) end
  function HC2.getSection(id,f) return HC2.getRsrc('sections',id,f) end
  function HC2.getiosDevice(id,f) return HC2.getRsrc('iosDevices',id,f) end

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
    weather=function(arg)
      local w = not _REMOTE and 
      (json.decode(
          [[{"Temperature": 9.5,"TemperatureUnit": "C",
             "Humidity": 91.8,
             "Wind": 11.52,
             "WindUnit": "km/h",
             "WeatherCondition": "cloudy",
             "ConditionCode": 26}
          ]]))
      or api._get(false,"/weather")
      return w
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
        if _BLOCK_PUT then Log(LOG.LOG,"Updating HC2 global '%s'denied, set _BLOCK_PUT=false",r) return end
        api._put(false,"/globalVariables/"..r,data,cType)
        HC2.rsrc.globalVariables[r]=data -- cache
      end
    end,
  }

  HC2._postHandlers={ -- create global variable, always local...?
    globalVariables=function(r,data,cType) 
      local v = HC2.rsrc.globalVariables[data.name]
      if not v then data._local=true; HC2.rsrc.globalVariables[data.name]=data end
    end,
    scenes=function(r,data,cType)
      local sceneID,cmd=r:match("(%-?%d+)/action/(%w+)")
      sceneID=math.abs(tonumber(sceneID))
      if cmd=='start' then
        local scene = HC2.getScene(sceneID,true)
        if not scene then return end
        if scene._local then --Scene.start(scene,{type='other'},args) 
          Event.post({type='other',_id=scene.id,_args=data.args})
          BREAKIDLE=true
        end
      end
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
      if call=="/" then
        Event.post(data)
        BREAKIDLE=true
        return
      end
      local m,r = call:match("^/([^/]+)/?(.*)$")
      if m and HC2._postHandlers[m] then return HC2._postHandlers[m](r,data,cType)
      else error("POST "..call.." not supported") end
    end,
    DELETE=function(call,data,cType) error("DELETE not supported") end,
  }

  function HC2.apiCall(method,call,data,cType) 
    call=call:match("^/api(.*)") or call
    local mhandler = _API_METHODS[method]
    if mhandler then return mhandler(call,data,cType) else return null end
  end

  function HC2.listDevices(list)
    local res={}
    for id,dev in pairs(HC2.rsrc.devices) do
      if tonumber(id) > 3 then
        res[#res+1]=string.format("deviceID:%-3d, name:%-20s type:%-30s, value:%-10s",
          id,dev.name,dev.type,dev.properties.value,dev._local and "local" or "")
      end
    end
    if not list then print(table.concat(res,"\r\n")) end 
    return res
  end

  function HC2.listScenes(list)
    res={}
    for id,scene in pairs(HC2.rsrc.scenes) do
      res[#res+1]=string.format("SceneID :%-3d, name:%-10s %s",id,scene.name,scene._local and "local" or "")
    end
    if not list then print(table.concat(res,"\r\n")) end 
    return res
  end

  local function setRsrcStatus(list,args,tp)
    if args==true then 
      for _,d in pairs(list) do d._local=tp end
    elseif type(args)=='table' then 
      for _,id in ipairs(args) do if list[id] then list[id]._local = tp end end 
    elseif type(args)=='number' then 
      if list[args] then list[args]._local = tp end
    elseif type(args)=='string' then 
      if list[id] then list[id]._local = tp end
    end
  end

  function HC2.localDevices(args) setRsrcStatus(HC2.rsrc.devices,args,true) end
  function HC2.localGlobals(args) setRsrcStatus(HC2.rsrc.globalVariables,args,true) end
  function HC2.localRooms(args) setRsrcStatus(HC2.rsrc.rooms,args,true) end
  function HC2.localScenes(args) setRsrcStatus(HC2.rsrc.scenes,args,true) end

  function HC2.remoteDevices(args) setRsrcStatus(HC2.rsrc.devices,args) end
  function HC2.remoteGlobals(args) setRsrcStatus(HC2.rsrc.globalVariables,args) end
  function HC2.remoteRooms(args) setRsrcStatus(HC2.rsrc.rooms,args) end
  function HC2.remoteScenes(args) setRsrcStatus(HC2.rsrc.scenes,args) end

  function HC2.createGlobal(name,value)
    if value~=nil then value=tostring(value) end
    HC2.rsrc.globalVariables[name]={name=name, value=value,modified=osTime(),_local=true}
    return HC2.rsrc.globalVariables[name]
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
    return d
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
      local short_src = _sceneFile or debug.getinfo(6).short_src
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

  function _System.dofile(file)
    local code = loadfile(file)
    if code then
      setfenv(code,_SceneContext[coroutine.running()])
      code()
    else Log(LOG.ERROR,"Missing file:%s",file) end
  end

  _System.createGlobal = HC2.createGlobal
  _System.createDevice = HC2.createDevice
  _System._Msg = _UserMsg

  function _System._getInstance(id,inst)
    for co,env in pairs(_SceneContext) do
      if env.__fibaroSceneId==id and env.__orgInstanceNumber==inst then return co,env end
    end
  end

  local _gTimers = nil

  function _System.insertCoroutine(co)
    if _gTimers == nil then _gTimers=co
    elseif co.time < _gTimers.time then
      _gTimers,co.next=co,_gTimers
    else
      local tp = _gTimers
      while tp.next and tp.next.time <= co.time do tp=tp.next end
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
    ["SPEED"] = function(t) _gTime=_gTime+t if _System.idleHandler then _System.idleHandler() end return false end,
    --["NORMAL"] = function(t) socket.sleep(t) _gTime=_gTime+t return false end,
    ["NORMAL"] = function(t) 
      local idle = _System.idleHandler
      local ic,interval = 0,10000
      BREAKIDLE=false
      local t2=os.clock()+t
      while os.clock() < t2 and not BREAKIDLE do 
        if idle and ic == 0 then idle() end
        ic = (ic+1) % interval
      end
      _gTime=os.time()
      return false 
    end,
  }

  function _System.runTimers()
    while _gTimers ~= nil do
      --_System.dumpTimers()
      ::REDO::
      local co,now = _gTimers,osTimeFrac()
      if co.time > now then _System.waitFor[WAITINDEX](co.time-now) goto REDO end
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

  function _System.getIPadress()
    local someRandomIP = "192.168.1.122" --This address you make up
    local someRandomPort = "3102" --This port you make up  
    local mySocket = socket.udp() --Create a UDP socket like normal
    mySocket:setpeername(someRandomIP,someRandomPort) 
    local myDevicesIpAddress, somePortChosenByTheOS = mySocket:getsockname()-- returns IP and Port 
    return myDevicesIpAddress
  end

  function _System.makeProcessManager()
    self = {}
    local threads=nil
    local free=nil

    local function PP(p,t) printf("%sProcess:%s %s %s %s",p,t.name,t.thread,coroutine.status(t.thread),t.args[1]:getpeername()) end

    function self.create(fun,name,...)
      local args={...}
      fun = coroutine.create(fun)
      local l=free; 
      if free==nil then l={} else free=free.next end
      l.thread=fun; l.args=args; l.name=name; l.next=nil
      if threads==nil then threads=l; return l end
      local t=threads; while t.next do t=t.next end
      t.next=l; 
      return l;
    end

    local function dispose(t) t.next=free; free=t end

    local function resume(co,args,name) 
      coroutine.resume(co,table.unpack(args))
      return coroutine.status(co) 
    end

    function self.idleHandler()
      while(threads) do
        if resume(threads.thread,threads.args,threads.name)=='dead' then
          local l = threads; threads=threads.next; dispose(l) 
        else break end
      end
      local t = threads
      while(t and t.next) do 
        if resume(t.next.thread,t.next.args,t.name)=='dead' then
          local l = t.next; t.next=t.next.next; dispose(l) 
        else t=t.next end 
      end
    end

    return self
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
      _assertf(isEvent(e) or type(e)=='function', "bad event format '%s'",tojson(e))
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
      _assertf(type(e) == "function" or isEvent(e), "Bad event format %s",function() tojson(e) end)
      time = toTime(time or osTime())
      if time < osTime() then return nil end
      if _debugFlags.triggers and not (type(e)=='function') then
        if e.type=='other' and e._id then
          Log(LOG.LOG,"System trigger:{\"type\":\"other\"} to scene:%s at %s",e._id,osDate("%a %b %d %X",time)) 
        else
          Log(LOG.LOG,"System trigger:%s at %s",tojson(e),osDate("%a %b %d %X",time)) 
        end
      end
      BREAKIDLE=true
      if type(e)=='function' then return _System.setTimeout(e,1000*(time-osTime()),"Timer")
      else return _System.setTimeout(function() self._handleEvent(e) end,1000*(time-osTime()),"Main") end
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
    if  type(value) ~= typeOfValue then error("Assertion failed: Expected "..typeOfValue ,3) end 
  end 

  function __convertToString(value) 
    if  type(value) == 'boolean'  then return  value and '1' or '0'
    elseif type(value) ==  'number' then return tostring(value) 
    elseif type(value) == 'table' then return json.encode(value) 
    else return value end
  end

  function __fibaro_get_device_property(deviceID ,propertyName, lcl)
    local d = HC2.getDevice(deviceID)
    return d and {value=__convertToString(d.properties[propertyName] or false),modified=d.modified}
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
    print(_format("%s%s %s",env.__debugName,osDate("[DEBUG] %H:%M:%S:"),str)) 
  end
  function fibaro:sleep(n) return coroutine.yield(coroutine.running(),n/1000) end
  function fibaro:abort() coroutine.yield(coroutine.running(),'%%ABORT%%') end

  function fibaro:countScenes(sceneID) YIELD()
    sceneID = sceneID or Scene.global().__fibaroSceneId
    local scene = HC2.getScene(sceneID) 
    return scene ==  nil and 0 or scene.runningInstances
  end

  function fibaro:isSceneEnabled(sceneID) YIELD() 
    local scene = HC2.getScene(sceneID) 
    if  scene ==  nil then return  nil end
    return scene.runConfig == "TRIGGER_AND_MANUAL" or scene.runConfig == "MANUAL_ONLY"
  end

  function fibaro:killScenes(sceneID) YIELD()
    local scene = HC2.getScene(sceneID,true)
    if not scene then return end
    if scene._local then
      error("local killScene not implemented yet")
    elseif _REMOTE then api._post(true,"/scenes/"..sceneID.."/action/stop") end
  end

  function fibaro:startScene(sceneID,args) YIELD()
    local scene = HC2.getScene(sceneID,true)
    if not scene then return end
    if scene._local then --Scene.start(scene,{type='other'},args) 
      Event.post({type='other',_id=scene.id,_args=args})
    else api._post(true,"/scenes/"..sceneID.."/action/start",args and {args=args} or nil)  end
  end

  function fibaro:args() return Scene.global().__fibaroSceneArgs end

  function fibaro:setSceneEnabled(sceneID , enabled) YIELD() 
    __assert_type(sceneID ,"number") 
    __assert_type(enabled ,"boolean")
    local scene = HC2.getScene(sceneID,true)
    local runConfig = enabled ==true and "TRIGGER_AND_MANUAL" or "DISABLED"
    if (not _REMOTE) or (scene and scene._local) then
      if scene then scene.runConfig = runConfig end
    else api._put(true,"/scenes/"..sceneID, {id = sceneID ,runConfig = runConfig}) end 
  end

  function fibaro:getSceneRunConfig(sceneID) YIELD() 
    local scene = HC2.getScene(sceneID) 
    if scene ==  nil then return  nil end
    return scene.runConfig
  end

  function fibaro:setSceneRunConfig(sceneID ,runConfig) YIELD() 
    __assert_type(sceneID ,"number") 
    __assert_type(runConfig ,"string")
    local scene = HC2.getScene(sceneID,true)
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

  function fibaro:getType(deviceID) YIELD() 
    local dev = HC2.getDevice(deviceID)
    if  dev == nil then return  nil end
    return dev.type
  end

  function fibaro:get(deviceID ,propertyName) YIELD() 
    local property = __fibaro_get_device_property(deviceID , propertyName)
    if property ==  nil then return  nil end
    return property.value , property.modified
  end

  function fibaro:getValue(deviceID ,propertyName) YIELD() 
    local property = __fibaro_get_device_property(deviceID , propertyName)
    return property and property.value
  end

  function fibaro:getModificationTime(deviceID ,propertyName) 
    local property = __fibaro_get_device_property(deviceID , propertyName)
    return property and property.modified
  end

  function fibaro:getGlobal(varName) YIELD(10) 
    local globalVar = HC2.getGlobal(varName) 
    if globalVar ==  nil then return  nil end
    return globalVar.value ,globalVar.modified
  end

  function fibaro:getGlobalValue(varName) YIELD(10)
    local globalVar = HC2.getGlobal(varName)
    return globalVar and  globalVar.value 
  end

  function fibaro:getGlobalModificationTime(varName) return select(2,fibaro:getGlobal(varName)) end

  function fibaro:setGlobalOld(varName ,value) 
    __assert_type(varName ,"string")
    local globalVar = HC2.getGlobal(varName,true)
    if (not _REMOTE) or (globalVar and globalVar._local) then
      if not globalVar and _AUTOCREATEGLOBALS then
        HC2.rsrc.globalVariables[varName]={name=varName,_local=true}
        globalVar=HC2.rsrc.globalVariables[varName]
        --fibaro:setGlobal(varName,value)
        --return
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

  function fibaro:setGlobal(varName ,value) YIELD(10) 
    __assert_type(varName ,"string")
    ::REDO::
    local globalVar = HC2.getGlobal(varName,true)
    if globalVar and globalVar._local then -- we have a local
      globalVar.value,globalVar.modified= tostring(value),osTime()
      if _debugFlags.globals then Log(LOG.LOG,"Setting global %s='%s'",varName,value) end
      Event.post({type='global',name=globalVar.name}) -- trigger
    elseif globalVar then -- we have a global
      api._put(true,"/globalVariables/"..varName ,{value=tostring(value), invokeScenes= true}) 
    elseif _AUTOCREATEGLOBALS then -- we autocreate
      _System.createGlobal(varName)
      goto REDO
    else error("Non existent fibaro global: "..varName) end
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

  function fibaro:call(deviceID ,actionName ,...)  YIELD(10)
    deviceID =  tonumber(deviceID) 
    __assert_type(actionName ,"string")
    local dev = HC2.getDevice(deviceID)
    if dev and dev._local then
      if _specCalls[prop] then _specCalls[actionName](deviceID,...) return end 
      local value = ({turnOff=false,turnOn=true,open=true, on=true,close=false, off=false})[actionName] or 
      (actionName=='setValue' and tostring(({...})[1]))
      if value==nil then error(_format("fibaro:call(..,'%s',..) is not supported, fix it!",actionName)) end
      setAndPropagate(deviceID,'value',value)
    elseif dev then
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
    local room = HC2.getRoom(roomID) 
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
          local id2,args = type(id) == 'number' and Util and Util.reverseVar(id) or '"'..(id or "<ID>")..'"',{...}
          local status,res,r2 = pcall(function() return fibaro._orgf[name](obj,id,table.unpack(args)) end)
          if status and _debugFlags[flag] then
            Debug(true,fstr,name,id2,(#args>0 and "," or ""),json.encode(args):sub(2,-2),json.encode(res))
          elseif not status then
            printf(debug.traceback())
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
    interceptFib("","sleep","fibaroSleep",
      function(obj,fun,time) 
        Debug(true,"fibaro:sleep(%s) until %s",time,osDate("%X",osTime()+math.floor(0.5+time/1000)))
        fun(obj,time) 
      end)
    interceptFib("","startScene","fibaroStart",
      function(obj,fun,id,args) 
        local a = isRemoteEvent(args) and json.encode(decodeRemoteEvent(args)) or args and json.encode(args)
        Debug(true,"fibaro:start(%s%s)",id,a and ","..a or "")
        fun(obj,id, args) 
      end)
  end

--------------------------------------
-- EventRunner support
--------------------------------------
  ER={ gEventRunnerKey="6w8562395ue734r437fg3" }

  function ER.checkForEventRunner(scene)
    scene.EventRunner = scene.lua:match(ER.gEventRunnerKey)
    if scene.EventRunner then
      scene._startMsg = function(id,inst,env) return inst > 0 end
      scene._terminateMsg = function(id,inst,env) return inst > 1 end
    end
  end

  function ER.announceEmulator(ipaddress,port)
    -- Tell HC2 what local scenes we have.
    local locals,remotes={},{}
    for id,scene in pairs(HC2.rsrc.scenes) do
      if scene._local then 
        locals[#locals+1]=id  
      elseif scene.EventRunner then
        -- Should we check that they are active too?
        remotes[#remotes+1]=id
      end
    end
    if #remotes>0 then
      local event = {type='%%EMU%%',ids=locals,adress="http://"..ipaddress..":"..port.."/"}
      local args=encodeRemoteEvent(event)
      for _,sceneID in ipairs(remotes) do
        if _REMOTE then api._post(true,"/scenes/"..sceneID.."/action/start",{args=args}) end
      end
    end
  end

  function ER.makeProxy(remoteSceneID,enable)
    local s = HC2.rsrc.scenes[remoteSceneID]
    if s and s.EventRunner then
      enable = enable==nil and true or enable
      local event = {type='%%PROX%%',value=enable,adress="http://"..ipaddress..":"..port.."/"}
      local args=encodeRemoteEvent(event)
      api._post(true,"/scenes/"..remoteSceneID.."/action/start",{args=args})
    end
  end

  function makeWebserver(ipAdress)
    local self = { ipAdress = ipAdress }

    local function clientHandler(client,getHandler,postHandler,putHandler)
      client:settimeout(0,'b')
      client:setoption('keepalive',true)
      local ip=client:getpeername()
      printf("IP:%s",ip)
      while true do
        l,e,j = client:receive()
        if l then
          local method,call = l:match("^(%w+) (.*) HTTP/1.1")
          if method and call then
            if method=='POST' or method=='PUT' then
              while true do
                l,e,j = client:receive()
                if j and j~="" then
                  if method=='POST' and postHandler then postHandler(client,call,j)
                  elseif method=='PUT' and putHandler then putHandler(client,call,j) end
                  client:close() 
                  return
                end
                if e=='closed' then return end
                if e=='timeout' then coroutine.yield()  end
              end
            elseif method=="GET" and getHandler then
              local ref=nil
              repeat 
                l,e,j = client:receive()
                if l then
                  local r2 = l:match("^[Rr]eferer:%s*(.*)")
                  ref = ref or r2
                end
                --printf("GET: %s",tostring(l))
              until e=='closed' or e=='timeout'
              getHandler(client,call,ref)
              client:close()
            end
          end
        end
        if e == 'closed' then return 
        else coroutine.yield() end
      end
    end

    local function socketServer(server,getHandler,postHandler,putHandler)
      while true do
        repeat
          client, err = server:accept()
          if err == 'timeout' then coroutine.yield() end
        until err ~= 'timeout'
        ProcessManager.create(clientHandler,"client",client,getHandler,postHandler,putHandler)
      end
    end

    function self.createServer(name,port,getHandler,postHandler,putHandler)
      local server,c,err=assert(socket.bind("*", port))
      local i, p = server:getsockname()
      local timeoutCounter = 0
      assert(i, p)
      --printf("http://%s:%s/test",ipAdress,port)
      server:settimeout(0,'b')
      server:setoption('keepalive',true)
      ProcessManager.create(socketServer,"server",server,getHandler,postHandler,putHandler)
      Log(LOG.LOG,"Created %s at %s:%s",name,self.ipAdress,port)
    end

    return self
  end

end
-------------------------------------------------------------------------------
-- Libs, json etc
---------------------------------------------------------------------------------
function libs()

  if not _VERSION:match("5%.1") then
    loadstring = load
    function setfenv(fn, env)
      local i = 1
      while true do
        local name = debug.getupvalue(fn, i)
        if name == "_ENV" then debug.upvaluejoin(fn, i, (function() return env end), 1) break
        elseif not name then break end
        i = i + 1
      end
      return fn
    end

    function getfenv(fn)
      local i = 1
      while true do
        local name, val = debug.getupvalue(fn, i)
        if name == "_ENV" then return val
        elseif not name then break end
        i = i + 1
      end
    end
  end

--------------------------------------------------------------------------------
-- json support
-- json library - Copyright (c) 2018 rxi https://github.com/rxi/json.lua
-----------------------------------------------------------------------------
  json = { _version = "0.1.1" }

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------
  do
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

      if val[1] ~= nil or next(val) == nil then
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
        for i, v in ipairs(val) do
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
        error("expected argument of type string, got " .. type(str),2)
      end
      local stat,res = pcall(function()
          local res, idx = parse(str, next_char(str, 1, space_chars, true))
          idx = next_char(str, idx, space_chars, true)
          if idx <= #str then
            decode_error(str, idx, "trailing garbage")
          end
          return res
        end)
      if not stat then
        error(res,2)
      else return res end
    end
  end

  tojson = json.encode

-----------------------------
-- persistence
-- Copyright (c) 2010 Gerhard Roethlin

--------------------
-- Private methods
  do
    local write, writeIndent, writers, refCount;

    persistence =
    {
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
  end
end

function pages()
  local P_MAIN =
[[HTTP/1.1 200 OK
Content-Type: text/html
Cache-Control: no-cache, no-store, must-revalidate

<!DOCTYPE html>
<html>
<head>
<meta content="text/html; charset=ISO-8859-1" http-equiv="content-type">
<title><<<return _format("%s v%s%s",_sceneName,_version,_fix~="" and " ,".._fix or "")>>></title></head>
<body>
<a href="devices">Devices</a>
<a href="scenes">Scenes</a>
</body></html>

]]

  local P_SCENES =
[[HTTP/1.1 200 OK
Content-Type: text/html
Cache-Control: no-cache, no-store, must-revalidate

<!DOCTYPE html>
<html>
<head>
<meta content="text/html; charset=ISO-8859-1" http-equiv="content-type">
<<<return _PAGE_STYLE>>>
<title>Scenes</title></head>
<body>
<table>
<tr><th>sceneID</th><th>Name<th>Where</th></tr>
<<<
local res={}
for id,dev in pairs(HC2.rsrc.scenes) do
   res[#res+1] = _format("<tr><td>%s</td><td>%s</td><td>%s</td></tr>",id,dev.name,dev._local and "Local" or "Remote" )
end
return table.concat(res)
>>>
</table>
</body></html>

]]

  local P_DEVICES = 
[[HTTP/1.1 200 OK
Content-Type: text/html

<!DOCTYPE html>
<html>
<head>
    <title>Triggers</title>
    <meta charset="utf-8">
<<<return _PAGE_STYLE>>>
</head>
<body>
<table style="width:100%">
<tr><th>deviceID</th><th>Name<th>Type</th><th>Value</th><th>Where</th><th>Actions</th></tr>
<<<
local res={}
for id,dev in pairs(HC2.rsrc.devices) do
 if id > 3 and dev.type~="virtual_device" then
  local function actions(id,dev) 
      local res={}
      local val = dev.properties.value
      val = val ~= nil and tostring(val) or false
      res[#res+1]=Pages.renderAction(id,"call","turnOn",false)
      res[#res+1]=Pages.renderAction(id,"call","turnOff",false)
      if val then res[#res+1]=Pages.renderAction(id,"call","setValue",val) end
      return "<div class=\"trigger-actions\">"..table.concat(res).."</div>"
      end
   res[#res+1] =     
         _format("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
         id,dev.name,dev.type,dev.properties.value,dev._local and "Local" or "Remote",actions(id,dev))
 end
end
return table.concat(res)
>>>
</table>
</body>
</html>

]]

  local P_ERROR1 =
[[HTTP/1.1 200 OK
Content-Type: text/html
<!DOCTYPE html>
<html>
<head>
    <title>Error</title>
    <meta charset="utf-8">
</head>
<body>
%s
</body>
</html>

]]  
  local P_POSTT =  -- experimental
[[HTTP/1.1 200 OK
Content-Type: text/html
<!DOCTYPE html>
<html>
<head>
    <title>Post trigger</title>
    <meta charset="utf-8">
</head>
<body>
<div id="response">
    <pre></pre>
</div>
<form id="my-form">
  <button type="submit">Submit</button>
</form>
<script src="//ajax.googleapis.com/ajax/libs/jquery/1.11.1/jquery.min.js"></script>
<script>
    (function($){
        function processForm( e ){
            $.ajax({
                url: 'trigger',
                dataType: 'json',
                type: 'post',
                contentType: 'application/json',
                data: JSON.stringify({"type" : "test"}),
                processData: false,
                success: function( data, textStatus, jQxhr ){
                     $('#response pre').html( JSON.stringify( data ) );
                },
                error: function( jqXhr, textStatus, errorThrown ){
                    console.log( errorThrown );
                }
            });

            e.preventDefault();
        }

        $('#my-form').submit( processForm );
    })(jQuery);
</script>
</body>
</html>

]]
  Pages = { pages={} }
  function Pages.register(path,page) Pages.pages[path]={page=page, path=path} end

  function Pages.getPath(path)
    local p = Pages.pages[path]
    if p and not p.cpage then
      Pages.compile(p)
    end
    if p then return Pages.render(p)
    else return null end
  end

  function Pages.render(p)
    local stat,res = pcall(function()
        return p.cpage:gsub("<<<(%d+)>>>",
          function(i)
            return p.funs[tonumber(i)]()
          end)
      end)
    if not stat then
      return _format(P_ERROR1,res)
    else return res end
  end

  function Pages.renderAction(id,method,action,value)
    local res
    if not value then
      res = _format([[<form action="/emu/fibaro/%s/%s/%s"><input type="submit" value="%s"></form>]],method,id,action,action)
    else
      res = _format([[<form action="/emu/fibaro/%s/%s/%s"><input type="submit" value="%s"><input type="text" name="value" value="%s"></form>]],method,id,action,action,value)
    end
    return res
  end

  function Pages.compile(p)
    local funs={}
    p.cpage=p.page:gsub("<<<(.-)>>>",
      function(code)
        local f = _format("do %s end",code)
        f,m = loadstring(f)
        if m then printf("ERROR RENDERING PAGE %s, %s",p.path,m) end
        funs[#funs+1]=f
        return (_format("<<<%s>>>",#funs))
      end)
    p.funs=funs
  end

  Pages.register("/emu/main",P_MAIN)
  Pages.register("/emu/scenes",P_SCENES)
  Pages.register("/emu/devices",P_DEVICES)

  _PAGE_STYLE=
[[<style>
table, th, td {
  border: 1px solid black;
  border-collapse: collapse;
}
form {
  display: flex; /* 2. display flex to the rescue */
  flex-direction: row;
  display:inline-block;
}
label {
  display: block; /* 1. oh noes, my inputs are styled as block... */
}
th, td {
  padding: 5px;
}
th {
  text-align: left;
}
</style>
]]

--print(Pages.getPath("triggers"))
end

--------------------------------------------------
-- Load code and start
--------------------------------------------------
libs()
support()
pages()
startup()
