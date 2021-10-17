--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
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

Sources included:
json           -- Copyright (c) 2019 rxi
persistence    -- Copyright (c) 2010 Gerhard Roethlin
file functions -- Credit pkulchenko - ZeroBraneStudio
copas          -- Copyright 2005-2016 - Kepler Project (www.keplerproject.org)
timerwheel     -- Credit https://github.com/Tieske/timerwheel.lua/blob/master/LICENSE
binaryheap     -- Copyright 2015-2019 Thijs Schreijer
LuWS           -- Copyright 2020 Patrick H. Rigney, All Rights Reserved. http://www.toggledbits.com/LuWS
--]]

--[[
Emulator options: (set in the header _=loadfile and loadfile("TQAE.lua"){...} )
user=<user>
  Account used to interact with the HC3 via REST api
pwd=<Password>
  Password for account used to interact with the HC3 via REST api
host=<IP address>
  IP address of HC3
configFile = <filename>
  File used to load in emulator options instead of specifying them in the QA file.
  Great place to keep credentials instead of listing them in the QA code, and forget to remove them when uploading codeto forums...
  Default "TQAEconfigs.lua"
debug={
  traceFibaro=<boolean>,   --default false
  QA=<boolean>,            --default true
  module=<boolean>,        --defaul false
  module2=<boolean>,       --defaul false
  lock=<boolean>,          --default false
  child=<boolean>,         --default true
  device=<boolean>,        --default true
  refreshStates=<boolean>, --default false
}
modPath = <path>, 
  Path to TQAE modules. 
  Default "TQAEmodules/"
temp = <path>
  Path to temp directory. 
  Default "temp/"
startTime=<time string>
  Start date for the emulator. Ex. "12/24/2024-07:00" to start emulator at X-mas morning 07:00 2024.
  Default, current local time.
htmlDebug=<boolean>.
   If false will strip html formatting from the log output. 
   Default true
colorDebug=<boolean>.
   If true will log in ZBS console with color. 
   Default true
copas=<boolean>
   If true will use the copas scheduler. 
   Default true.
noweb=<boolean>
   If true will not start up local web interface.
   Default false
lateTimers=<seconds>
  If set to a value will be used to notify if timers are late to execute.
  Default false
timerVerbose=<boolean>
  If true prints timer reference with extended information (expiration time etc)
  
QuickApp options: (set with --%% directive in file)
--%%name=<name>
--%%id=<number>
--%%type=<com.fibaro.XYZ>
--%%properties={<table of initial properties>}
--%%interfaces={<array of interfaces>}
--%%quickVars={<table of initial quickAppVariables>}   -- Ex. { x = 9, y = "Test" }
--%%proxy=<boolean>
--]]

local embedded=...              -- get parameters if emulator included from QA code...
local EM = { cfg = embedded or {} }
local cfg,pfvs = EM.cfg
local function DEF(x,y) if x==nil then return y else return x end end
cfg.configFile  = DEF(cfg.configFile,"TQAEconfigs.lua")
do 
  EM.PFVS = { debug = {}, configFile=cfg.configFile}
  local pf = loadfile(cfg.configFile)
  if pf then 
    local p = pf() or {}; 
    pfvs = true
    for k,v in pairs(p) do EM.PFVS[k]=v end -- save paramFile values for settings panel
    for k,v in pairs(cfg) do p[ k ]=v end 
    cfg,EM.cfg=p,p 
  end 
end
cfg.modPath      = DEF(cfg.modpath,"TQAEmodules/")   -- directory where TQAE modules are stored
cfg.temp         = DEF(cfg.temp,os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "temp/") -- temp directory
cfg.logLevel     = DEF(cfg.logLevel,1)
cfg.htmlDebug    = DEF(cfg.htmlDebug,true)
cfg.colorDebug   = DEF(cfg.colorDebug,true)
cfg.defaultRoom  = DEF(cfg.defaultRoom,219)
EM.utilities     = dofile(cfg.modPath.."utilities.lua")
EM.debugFlags    = DEF(cfg.debug,{QA=true,child=true,device=true})

local fibColors  = DEF(cfg.fibColors,{ ["DEBUG"] = 'green', ["TRACE"] = 'blue', ["WARNING"] = 'orange', ["ERROR"] = 'red' })
local logColors  = DEF(cfg.logColors,{ ["SYS"] = 'brown', ["ERROR"]='red', ["WARNING"] = 'orange', ["TRACE"] = 'blue' })

local globalModules = { -- default global modules loaded once into emulator environment
  "net.lua","json.lua","files.lua", "webserver.lua", "api.lua", "proxy.lua", "ui.lua", "time.lua",
  "refreshStates.lua", "stdQA.lua", "Scene.lua", "offline.lua",
} 
local localModules  = { -- default local modules loaded into every QA environment
  {"class.lua","QA"}, "fibaro.lua", "fibaroPatch.lua", {"QuickApp.lua","QA"} 
} 

--EM.cfg.copas = true
--EM.cfg.noweb=true
local function main(FB) -- For running test examples. Running TQAE.lua directly will run this test.
  if not EM.cfg.NOVERIFY then
    local et = loadfile(EM.cfg.modPath.."/verify/verify.lua") -- more extensive tests.
    if et then et(EM,FB) end 
  else EM.startEmulator(nil) end
end

---------------------------------------- TQAE -------------------------------------------------------------
do
  local stat,mobdebug = pcall(require,'mobdebug'); -- If we have mobdebug, enable coroutine debugging
  if stat then mobdebug.coro() end
end
local version = "0.33"

local socket = require("socket") 
local http   = require("socket.http")
local https  = require("ssl.https") 
local ltn12  = require("ltn12")

-- Modules
-- FB.x exported native fibaro functions. Ex- __fibaro_get_device, setTimeout etc. Plugins can add to this, ex. net.*
-- EM.x internal emulator functions, HTTP, LOG etc. Plugins can add to this...

local FB,Devices = {},{}  -- id->Device map
local Utils=EM.utilities
local fmt,gID,setTimeout,LOG,DEBUG,loadModules,runQA = string.format,1001
local copy,deepCopy,merge,member = Utils.copy,Utils.deepCopy,Utils.merge,Utils.member
EM.http,EM.https=http,https
EM._info = { modules = { ["local"] = {}, global= {} } }

-- luacheck: ignore 142
------------------------ Builtin functions ------------------------------------------------------

local function httpRequest(reqs,extra)
  local resp,req,status,h,_={},{} 
  for k,v in pairs(extra or {}) do req[k]=v end; for k,v in pairs(reqs) do req[k]=v end
  req.sink,req.headers = ltn12.sink.table(resp), req.headers or {}
  req.headers["Accept"] = "*/*"
  req.headers["Content-Type"] = "application/json"
  if req.method=="PUT" or req.method=="POST" then
    req.data = req.data or "[]"
    req.headers["content-length"] = #req.data
    req.source = ltn12.source.string(req.data)
  else req.headers["Content-Length"]=0 end
  if req.url:sub(1,5)=="https" then
    _,status,h = EM.https.request(req)
  else
    _,status,h = EM.http.request(req)
  end
  if tonumber(status) and status < 300 then 
    return resp[1] and table.concat(resp) or nil,status,h 
  else return nil,status,h end
end

local base = "http://"..(EM.cfg.host or "").."/api"
local function HC3Request(method,path,data) 
  local res,stat,_ = httpRequest({method=method, url=base..path,
      user=EM.cfg.user, password=EM.cfg.pwd, data=data and FB.json.encode(data), timeout = 5000, 
      headers = {["Accept"] = '*/*',["X-Fibaro-Version"] = 2, ["Fibaro-User-PIN"] = EM.cfg.pin},
    })
  return res~=nil and FB.json.decode(res),stat,nil
end

local function __assert_type(value,typeOfValue )
  if type(value) ~= typeOfValue then  -- Wrong parameter type, string required. Provided param 'nil' is type of nil
    error(fmt("Wrong parameter type, %s required. Provided param '%s' is type of %s",
        typeOfValue,tostring(value),type(value)),
      3)
  end
end
function FB.__ternary(test, a1, a2) if test then return a1 else return a2 end end
-- Most __fibaro_x functions defined in api.lua
function FB.__fibaro_get_partition(id) return HC3Request("GET",'/alarms/v1/partitions/' .. id) end
function FB.__fibaroUseAsyncHandler(_) end -- TBD
-- Non standard
function FB.__fibaro_call(id,name,path,data)
  local args, D = data.args or {},Devices[id]
  if D then
    -- sim. call in another process/QA
    return setTimeout(function() D.env.onAction(id,{deviceId=id,actionName=name,args=args}) end,0,nil,D) 
  else return HC3Request("POST",path,data) end
end

function FB.__fibaro_local(bool) local l = EM.locl==true; EM.locl = bool; return l end

local html2color,ANSICOLORS,ANSIEND = Utils.html2color,Utils.ZBCOLORMAP,Utils.ZBCOLOREND

function FB.__fibaro_add_debug_message(tag,str,typ)
  assert(str,"Missing tag for debug")
  str = EM.cfg.htmlDebug and html2color(str) or str:gsub("(</?font.->)","") -- Remove color tags
  typ = EM.cfg.colorDebug and (ANSICOLORS[(fibColors[typ] or "black")]..typ..ANSIEND) or typ
  str=str:gsub("(&nbsp;)"," ")      -- remove html space
  print(fmt("%s [%s] [%s]: %s",EM.osDate("[%d.%m.%Y] [%H:%M:%S]"),typ,tag,str))
end

local function _LOG(typ,...)
  if EM.cfg.colorDebug then
    local colorCode = ANSICOLORS[logColors[typ]]
    print(fmt("%s |%s%5s%s|: %s",EM.osDate("[%d.%m.%Y] [%H:%M:%S]"),colorCode,typ,ANSIEND,fmt(...)))
  else
    print(fmt("%s |%5s|: %s",EM.osDate("[%d.%m.%Y] [%H:%M:%S]"),typ,fmt(...)))
  end
end
LOG = {}
function LOG.sys(...)   _LOG("SYS",  ...) end
function LOG.warn(...)  _LOG("WARNING", ...) end
function LOG.error(...) _LOG("ERROR",...) end
function LOG.trace(...) _LOG("TRACE",...) end
function DEBUG(flag,typ,...) if EM.debugFlags[flag] then LOG[typ](...) end end

function FB.urldecode(str) return str and str:gsub('%%(%x%x)',function (x) return string.char(tonumber(x,16)) end) end
function FB.urlencode(str) return str and str:gsub("([^% w])",function(c) return string.format("%%% 02X",string.byte(c))  end) end
function string.split(str, sep)
  local fields,s = {},sep or "%s"
  str:gsub("([^"..s.."]+)", function(c) fields[#fields + 1] = c end)
  return fields
end

function loadModules(ms,env,isScene,args)
  ms = type(ms)=='table' and ms or {ms}
  local stat,res = pcall(function()
      for _,m in ipairs(ms) do
        if type(m)=='table' then m,args=m[1],m[2] else args=nil end
        if not(args=='QA' and isScene) then
          DEBUG("module","sys","Loading  %s module %s",env and "local" or "global",m) 
          EM._info.modules[env and "local" or "global"][m]=true
          local code,res=loadfile(EM.cfg.modPath..m,"t",env or _G)
          assert(code,res)
          code(EM,FB,args or {})
        end
      end
    end)
  if not stat then error("Loading module "..res) end
end

local offset=0
function EM.setTimeOffset(offs) if offs then offset=offs else return offset end end
function EM.clock() return socket.gettime()+offset end
function EM.osTime(a) return a and os.time(a) or math.floor(os.time()+offset+0.5) end
function EM.osDate(a,b) return os.date(a,b or EM.osTime()) end

local EMEvents = {}
function EM.EMEvents(typ,callback,front)
  local evs = EMEvents[typ] or {}
  if front then table.insert(evs,1,callback) else evs[#evs+1]=callback end 
  EMEvents[typ] = evs
end
function EM.postEMEvent(ev) for _,m in ipairs(EMEvents[ev.type] or {}) do m(ev) end end
EM.LOG,EM.DEBUG,EM.httpRequest,EM.HC3Request,EM.socket = LOG,DEBUG,httpRequest,HC3Request,socket
EM.Devices=Devices
FB.__assert_type = __assert_type

function FB.setInterval(fun,ms) 
  local r={} 
  local function loop() fun() if r[1] then r[1] = FB.setTimeout(loop,ms) end end 
  r[1] = FB.setTimeout(loop,ms) 
  return r 
end
function FB.clearInterval(ref) if type(ref)=='table' and ref[1] then FB.clearTimeout(ref[1]) ref[1]=nil end end
local function milliStr(t) return os.date("%H:%M:%S",math.floor(t))..string.format(":%03d",math.floor((t%1)*1000+0.5)) end
EM.milliStr = milliStr

local timer2str = { __tostring=function(t)
    if EM.cfg.timerVerbose then
      local ctx = t.ctx
      return fmt("<%s %s(%s), expires=%s>",t.descr,ctx.env.__TAG,ctx.id or 0,milliStr(t.time))
    else return t.descr end
  end 
}
function EM.makeTimer(time,co,ctx,tag,ft,args) 
  return setmetatable({time=time,co=co,ctx=ctx,tag=tag,fun=ft,args=args,descr=tostring(co)},timer2str)
end
function EM.timerCheckFun(t)
  local now = EM.clock()
  if (now-t.time) >= (tonumber(EM.cfg.lateTimers) or 0.5) then
    LOG.warn("Late timer %.3f - %s",now-t.time,t)
  end
end

------------------------ Emulator functions ------------------------------------------------------
local weakKeys = { __mode='k' } 
local procs    = setmetatable({},weakKeys)
local deviceTemplates

local function getContext(co) return procs[co or coroutine.running()] end
EM.getContext,EM.procs = getContext,procs

FB.json = {decode = function(s) return s end } -- Need fake json at this moment, will be replaced when loading json.lua
local HC3online = HC3Request("GET","/settings/info",nil) 

if EM.cfg.copas then loadfile(EM.cfg.modPath.."async.lua")(EM,FB) else loadfile(EM.cfg.modPath.."sync.lua")(EM,FB) end
setTimeout = EM.setTimeout
FB.setTimeout = EM.setTimeout
FB.clearTimeout = EM.clearTimeout

function FB.type(o) local t = type(o) return t=='table' and o._TYPE or t end
-- Check arguments and print a QA error message 
local function check(name,stat,err)
  if type(err)=='table' then return end
  if not stat then 
    err = err:gsub('(%[string ")(.-)("%])',function(_,s,_) return s end)
    FB.__fibaro_add_debug_message(name,err,"ERROR") 
  end 
  return stat,err
end
EM.checkErr = check

function EM.getQA(id)
  local D = Devices[tonumber(id) or 0] if not D then return end
  if D.dev.parentId==0 then return D.env.quickApp,D.env,true 
  else return D.env.quickApp.childDevices[id],D.env,false end
end

EM.EMEvents('QACreated',function(ev) -- Register device and clean-up when QA is created
    --local qa,dev = ev.qa,ev.dev
  end)

function EM.createDevice(info) -- Creates device structure
  local typ = info.type or "com.fibaro.binarySensor"
  local deviceTemplates = EM.getDeviceResources()
  local dev = deviceTemplates[typ] and deepCopy(deviceTemplates[typ]) or {
    actions = { turnOn=0,turnOff=0,setValue=1,toggle=0 }
  }

  if info.parentId and info.parentId > 0 then
    local p = Devices[info.parentId]
    info.env,info.childProxy = p.env,p.proxy
    if info.childProxy then DEBUG("child","sys","Imported proxy child %s",info.id) end
  end

  dev.name,dev.parentId,dev.roomID = info.name or "MyQuickApp",0,info.roomID or EM.cfg.defaultRoom
  merge(dev.interfaces,info.interfaces or {})
  merge(dev.properties,info.properties or {})
  info.dev = dev
  EM.addUI(info)

  if info.proxy then  -- Move out?
    local l = FB.__fibaro_local(false)
    local stat,res = pcall(EM.createProxy,dev)
    FB.__fibaro_local(l)
    if not stat then 
      LOG.error("Proxy: %s",res)
      info.proxy = false
    else
      info.id = res.id
    end
  end

  if not info.id then info.id = gID; gID=gID+1 end
  dev.id = info.id
  return dev
end

local function extractInfo(file,code) -- Creates info structure from file/code
  local files,info = EM.loadFile(code,file)
  info.properties = info.properties or {}
  info.properties.quickAppVariables = info.properties.quickAppVariables or {}
  for k,v in pairs(info.quickVars or {}) do table.insert(info.properties.quickAppVariables,1,{name=k,value=v}) end
  info.name,info.type=info.name or "MyQuickApp",info.type or "com.fibaro.binarySwitch"
  info.files,info.fileMap,info.extras,info.codeType=files,{},e,"QA"
  for _,f in ipairs(info.files) do if not info.fileMap[f.name] then info.fileMap[f.name]=f end end
  local lock = EM.createLock()
  info.timers,info._lock = {},lock
  info.lock = { 
    get = function() 
      DEBUG("lock","trace","GET(%s) %s",info.id,coroutine.running()) 
      lock:get()
      DEBUG("lock","trace","GOT(%s) %s",info.id,coroutine.running()) 
    end, 
    release=function() 
      DEBUG("lock","trace","RELEASE(%s) %s",info.id,coroutine.running()) 
      lock:release()
    end 
  }
  return info
end

local function createQA(args) -- Create QA/info struct from file or code string.
  local info = extractInfo(args.file,args.code)
  for _,p in ipairs({"id","name","type","properties","interfaces"}) do 
    if args[p]~=nil then info[p]=args[p] end 
  end
  EM.createDevice(info) -- assignes info.dev = dev
  return info
end

local function installDevice(info) -- Register device
  local dev = info.dev
  Devices[dev.id]=info
  DEBUG("device","sys","Created %s device %s",(member('quickAppChild',info.interfaces or {}) and "child" or ""),dev.id)
  EM.postEMEvent({type='deviceInstalled', info=info})
  return dev
end
EM.installDevice = installDevice

function EM.installQA(args,cont) 
  runQA(installDevice(createQA(args)).id,
    function()
      LOG.sys("End - runtime %.2f min",(EM.osTime()-EM._info.started)/60)
      EM._info.started = EM.osTime()
      if cont then cont() else os.exit() end
    end) 
end

local LOADLOCK = EM.createLock()

function runQA(id,cont)         -- Creates an environment and load file modules and starts QuickApp (:onInit())
  local info = Devices[id]
  info.cont = cont
  local env = {             -- QA environment, all Lua functions available for  QA, 
    plugin={ mainDeviceId = info.id },
    os={
      time=EM.osTime, date=EM.osDate, clock=os.clock, difftime=os.difftime, exit=EM.exit
    },
    hc3_emulator={
      getmetatable=getmetatable,setmetatable=setmetatable,io=io,installQA=EM.installQA,EM=EM,IPaddress=EM.IPAddress,
      os={setTimer=setTimeout, exit=os.exit},trigger=EM.trigger,create=EM.create,rawset=rawset,rawget=rawget,
    },
    coroutine=EM.userCoroutines,
    table=table,select=select,pcall=pcall,xpcall=xpcall,print=print,string=string,error=error,
    collectgarbage=collectgarbage,
    next=next,pairs=pairs,ipairs=ipairs,tostring=tostring,tonumber=tonumber,math=math,assert=assert
  }
  info.env,env._G,co=env,env,coroutine.running()
  for s,v in pairs(FB) do env[s]=v end                        -- Copy local exports to QA environment
  for s,v in pairs(info.extras or {}) do env[s]=v end         -- Copy user provided environment symbols
  loadModules(localModules or {},env,info.scene)              -- Load default QA specfic modules into environment
  loadModules(EM.cfg.localModules or {},env,info.scene)       -- Load optional user specified module into environment    
  EM.postEMEvent({type='infoEnv', info=info})
  procs[co]=info
  LOADLOCK:get()
  DEBUG("module","sys","Loading  %s:%s",info.codeType,info.name)
  for _,f in ipairs(info.files) do                                  -- for every file we got, load it..
    DEBUG("module2","sys","         ...%s",f.name)
    local code = check(env.__TAG,load(f.content,f.fname,"t",env))   -- Load our QA code, check syntax errors
    EM.checkForExit(true,co,pcall(code))                            -- Run the QA code, check runtime errors
  end
  LOADLOCK:release()
  if env.QuickApp and env.QuickApp.onInit then
    DEBUG("QA","sys","Starting QA:%s - ID:%s",info.name,info.id)       -- Start QA by "creating instance"
    setTimeout(function() env.QuickApp(info.dev) end,0)
  elseif env.ACTION then
    EM.postEMEvent({type='sceneLoaded', info=info})     
  end
end

EM.runQA = runQA

loadModules(globalModules or {})        -- Load global modules
loadModules(EM.cfg.globalModules or {}) -- Load optional user specified modules into environment

print(fmt("---------------- Tiny QuickAppEmulator (TQAE) v%s -------------",version)) -- Get going...
if not HC3online then LOG.warn("No connection to HC3") end
if pfvs then LOG.sys("Using config file %s",EM.cfg.configFile) end

function EM.startEmulator(cont)
  EM.start(function() EM.postEMEvent{type='start'} 
      if cont then cont() end
    end)
end

if embedded then                        -- Embedded call...
  local file = debug.getinfo(2)         -- Find out what file that called us
  if file and file.source then
    if not file.source:sub(1,1)=='@' then error("Can't locate file:"..file.source) end
    local fileName = file.source:sub(2)
    EM.startEmulator(function() EM.installQA({file=fileName},nil) end)
  end
else main(FB) end
LOG.sys("End - runtime %.2f min",(EM.osTime()-EM._info.started)/60)
os.exit()
