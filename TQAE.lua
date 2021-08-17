--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
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

Sources included:
json           -- Copyright (c) 2020 rxi
--]]

local embedded=...              -- get parameters if emulator included from QA code...
local EM = embedded or {}
local function DEF(x,y) if x==nil then return y else return x end end

EM.paramsFile  = DEF(EM.paramsFile,"TQAEconfigs.lua")
do 
  local pf = loadfile(EM.paramsFile); if pf then local p = pf() or {}; for k,v in pairs(EM) do p[ k ]=v end EM=p end 
end
EM.verbose       = DEF(EM.verbose,false)
EM.modPath       = DEF(EM.modpath,"TQAEmodules/")   -- directory where TQAE modules are stored
EM.temp          = DEF(EM.temp,os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "temp/") -- temp directory

local globalModules = { "net.lua","json.lua","files.lua", "webserver.lua" } -- default global modules loaded into emulator environment
local localModules  = { "class.lua", "fibaro.lua", "QuickApp.lua" } -- default local modules loaded into QA environment

local function main(run) -- playground

--  run{file='GEA_v7.20.fqa'}
  local testQA = [[
  --%%quickVars={x='Hello'}
  --%%interfaces={"power"}
  --%%save="temp/foo.fqa"
  function QuickApp:onInit()
    self:debug(self.name,self.id)
    self:debug("quickVar","x=",self:getVariable("x"))
    local n = 5
    setInterval(function() 
       self:debug("PP") 
       n=n-1
       if n <= 0 then os.exit() end
      end,1000)
  end
]]

  run{code=[[
print("Start")
--%%name='TestQA1'
function QuickApp:onInit()
    if not fibaro.getValue(self.id,"value") then
        self:updateProperty("value",true)
      api.post("/plugins/restart",{deviceId=self.id})
    end
    function self:debugf(...) self:debug(string.format(...)) end
    self:debugf("%s - %s",self.name,self.id)
    self:debugf("Name1:%s",fibaro.getName(self.id))
    self:debugf("Name2:%s",api.get("/devices/"..self.id).name)
    self:debugf("Name3:%s",__fibaro_get_device(self.id).name)
    hc3_emulator.installQA{name="MuQA",code=testQA} -- install another QA and run it
end
]],env={testQA=testQA}} -- we can add extra variables to our QA's environment

  loadfile("emu_tests.lua")(run) -- more extensive tests.
end

---------------------------------------- TQAE -------------------------------------------------------------
do
  local stat,mobdebug = pcall(require,'mobdebug'); -- If we have mobdebug, enable coroutine debugging
  if stat then mobdebug.coro() end
end
local version = "0.7"

local socket = require("socket")
local http   = require("socket.http")
local https  = require("ssl.https") 
local ltn12  = require("ltn12")

-- Modules
-- FB.x exported native fibaro functions. Ex- __fibaro_get_device, setTimeout etc. Plugins can add to this, ex. net.*
-- EM.x internal emulator functions, HTTP, LOG etc. Plugins can add to this...

local FB,QAs,Devices = {},{},{}  -- id->QA map, id->Device map
local fmt,LOG,call,loadModules,setTimeout,getContext,setContext,xpresume,lock = string.format 
EM._info = { started=os.time(), modules = { ["local"] = {}, global= {} } }
local verbose = EM.verbose

------------------------ Builtin functions ------------------------------------------------------
local function builtins()

  local function httpRequest(reqs,extra)
    local resp,req,status,h,_={},{} 
    for k,v in pairs(extra or {}) do req[k]=v end; for k,v in pairs(reqs) do req[k]=v end
    req.sink,req.headers = ltn12.sink.table(resp), req.headers or {}
    if req.method=="PUT" or req.method=="POST" then
      req.data = req.data or {}
      req.headers["Content-Length"] = #req.data
      req.source = ltn12.source.string(req.data)
    else req.headers["Content-Length"]=0 end
    if req.url:sub(1,5)=="https" then
      _,status,h = https.request(req)
    else
      _,status,h = http.request(req)
    end
    if tonumber(status) and status < 300 then 
      return resp[1] and FB.json.decode(table.concat(resp)) or nil,status,h 
    else return nil,status,h end
  end

  local base = "http://"..EM.host.."/api"
  local function HC3Request(method,path,data) 
    return httpRequest({method=method, url=base..path,
        user=EM.user, password=EM.pwd, data=data and FB.json.encode(data),
        headers = {["Accept"] = '*/*',["X-Fibaro-Version"] = 2, ["Fibaro-User-PIN"] = EM.pin},
      })
  end

  local function __assert_type(value,typeOfValue )
    if type(value) ~= typeOfValue then  -- Wrong parameter type, string required. Provided param 'nil' is type of nil
      error(fmt("Wrong parameter type, %s required. Provided param '%s' is type of %s",
          typeOfValue,tostring(value),type(value)),
        3)
    end
  end
  function FB.__ternary(test, a1, a2) if test then return a1 else return a2 end end
-- basic api functions, tries to deal with local emulated Devices too. Local Device have precedence over HC3 Devices.
  function FB.__fibaro_get_device(id) __assert_type(id,"number") return Devices[id] or HC3Request("GET","/devices/"..id) end
  function FB.__fibaro_get_devices() 
    local ds = HC3Request("GET","/devices") or {}
    for _,dev in pairs(Devices) do ds[#ds+1]=dev end -- Add emulated Devices
    return ds 
  end 
  function FB.__fibaro_get_room (id) __assert_type(id,"number") return HC3Request("GET","/rooms/"..id) end
  function FB.__fibaro_get_scene(id) __assert_type(id,"number") return HC3Request("GET","/scenes/"..id) end
  function FB.__fibaro_get_global_variable(name) __assert_type(name ,"string") return HC3Request("GET","/globalVariables/"..name) end
  function FB.__fibaro_get_device_property(id ,prop) 
    __assert_type(id,"number") __assert_type(prop,"string")
    local dev = Devices[id] -- Is it a local Device?
    if dev then return dev.properties[prop] and { value = dev.properties[prop], modified=0} or nil
    else return HC3Request("GET","/devices/"..id.."/properties/"..prop) end
  end
  function FB.__fibaro_get_partition(id) return HC3Request("GET",'/alarms/v1/partitions/' .. id) end
  function FB.__fibaroUseAsyncHandler(_) end -- TBD
  function FB.__fibaroSleep(ms) -- We lock all timers/coroutines except the one resuming the sleep for us
    local r,qa,co; co,r = coroutine.running(),setTimeout(function() setContext(co,qa) lock(r,false) xpresume(co) end,ms) 
    qa = getContext() lock(r,true); coroutine.yield(co)
  end
  -- Non standard
  function FB.__fibaro_call(id,name,path,data)
    return Devices[id] and call(id,name,data.args and table.unpack(data.args)) or HC3Request("POST",path,data)
  end
  function FB.__fibaro_local(bool) EM.locl = bool end

  function FB.__fibaro_add_debug_message(tag,str,type)
    assert(str,"Missing tag for debug")
    str=str:gsub("(</?font.->)","") str=str:gsub("(&nbsp;)"," ") -- Remove HTML tags
    print(fmt("%s [%s] [%s]: %s",os.date("[%d.%m.%Y] [%H:%M:%S]"),type,tag,str))
  end

  function loadModules(ms,env,args)
    ms = type(ms)=='table' and ms or {ms}
    local stat,res = pcall(function()
        for _,m in ipairs(ms) do
          if type(m)=='table' then m,args=m[1],m[2] end
          if verbose then LOG("Loading  %s module %s",env and "local" or "global",m) end
          table.insert(EM._info.modules[env and "local" or "global"],m)
          local code,res=loadfile(EM.modPath..m,"t",env or _G)
          assert(code,res)
          code(EM,FB,args or {})
        end
      end)
    if not stat then error("Loading module "..res) end
  end

  local EMEvents = {}
  function EM.EMEvents(callback) EMEvents[#EMEvents+1]=callback end
  function EM.postEMEvent(ev) for _,m in ipairs(EMEvents) do m(ev) end end
  function LOG(...) print(fmt("%s |SYS  |: %s",os.date("[%d.%m.%Y] [%H:%M:%S]"),fmt(...))) end
  EM.LOG,EM.httpRequest,EM.HC3Request = LOG,httpRequest,HC3Request
  EM.Devices,EM.QAs=Devices,QAs
  FB.__assert_type = __assert_type
end

------------------------ Emulator core ----------------------------------------------------------
local function emulator()
  local tasks,procs,CO,clock,insert,gID = {},{},coroutine,socket.gettime,table.insert,1001
  local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
  -- meta table to print threads like "thread ..."
  local tmt={ __tostring = function(t) return t[4] end}
  -- Insert timer in queue, sorted on ascending absolute time
  local function queue(t,co,q) 
    local v={t+os.time(),co,q,tostring(co)} setmetatable(v,tmt) 
    for i=1,#tasks do if v[1]<tasks[i][1] then insert(tasks,i,v) return v end end 
    tasks[#tasks+1]=v return v 
  end
  local function clearTasks(id)
    local res = {}
    for _,t in ipairs(tasks) do if not (t[3] and t[3].QA.id == id) then res[#res+1]=t end end
    tasks = res
  end
  local function deqeue(i) table.remove(tasks,i) end
  -- Lock or unlock QA. peek8) will return first unlocked. Used by fibaro.sleep to lock all other timers in same QA
  function lock(t,b) if t[3] then t[3].env.locked = b and t[2] or nil end end

  local function locked(t) local l = t[3] and t[3].env.locked; return l and l~=t[2] end
  -- set QA context to given or current coroutine - we can then pickup the context from the current coroutine
  function setContext(co,qa) procs[co]= qa or procs[coroutine.running()]; return co,procs[co] end

  function getContext(co) co=co or coroutine.running() return procs[co] end

  local function peek() for i=1,#tasks do if not locked(tasks[i]) then return i,table.unpack(tasks[i] or {}) end end end

  function setTimeout(fun,ms) return queue(ms/1000,setContext(CO.create(fun))) end
  FB.setTimeout=setTimeout
  -- Like setTimeout but sets another QA's context - used when starting up and fibaro.cal
  local function runProc(qa,fun) procs[coroutine.running()]=qa setTimeout(fun,0)  return qa end

  function FB.clearTimeout(ref) for i=1,#tasks do if ref==tasks[i] then table.remove(tasks,i) return end end end

  function FB.setInterval(fun,ms) local r={} local function loop() fun() r[1],r[2],r[3]=table.unpack(setTimeout(loop,ms)) end loop() return r end

  function FB.clearInterval(ref) FB.clearTimeout(ref) end

  -- Used by api/devices/<id>/action/<name> to call and hand over to called QA's thread
  function call(id,name,...)
    local args,QA = {...},QAs[id] or QAs[Devices[id].parentId]
    runProc(QA,function() QA.env.onAction(QA.QA,{deviceId=id,actionName=name,args=args}) end) -- sim. call in another process/QA
  end
  local function type2(o) local t = type(o) return t=='table' and o._TYPE or t end
  -- Check arguments and print a QA error message 
  local function check(name,stat,err) if not stat then FB.__fibaro_add_debug_message(name,err,"ERROR") end return stat end
  -- Resume a coroutine and handle errors
  function xpresume(co)  
    local stat,res = CO.resume(co)
    if not stat then 
      check(procs[co].env.__TAG,stat,res) debug.traceback(co) 
    end
  end
  function EM.getQA(id)
    id = tonumber(id) or 0
    if QAs[id] then return QAs[id].QA end
    local d = Devices[id]
    return d and QAs[d.parentId].QA.childDevices[id]
  end

  local installQA,runQA
  local function restartQA(QA) clearTasks(QA.QA.id) runQA(Devices[QA.QA.id]) coroutine.yield() end

  function EM.createDevice(id,name,typ,properties,interfaces)
    local dev = {}
    if id then dev.id = id else dev.id = gID; gID=gID+1 end
    dev.name = name or "MyQuickApp"
    dev.type = typ or "com.fibaro.binarySensor"
    dev.interfaces = interfaces or {}
    dev.properties = properties or {}
    dev.properties.quickAppVariables = dev.properties.quickAppVariables or {}
    Devices[dev.id]=dev
    return dev
  end

  local function addQA(qa) -- Creates the device structure and save the QA files
    local id,name,typ,code,file,e = qa.id,qa.name,qa.type,qa.code,qa.file,qa.env
    local files,info = EM.loadFile(code,file)
    local dev = EM.createDevice(id or info.id,name or info.name,info.properties,info.interfaces)
    for k,v in pairs(info.quickVars or {}) do table.insert(dev.properties.quickAppVariables,{name=k,value=v}) end
    QAs[dev.id]={files=files,save=qa.save or info.save, extras=e, restart=restartQA }
    return dev
  end

  function runQA(dev)      -- Creates an environment and load file modules and starts QuickApp (:onInit())
    local env = {          -- QA environment, all Lua functions available for  QA, 
      plugin={ mainDeviceId = dev.id }, os=copy(os), 
      hc3_emulator={getmetatable=getmetatable,setmetatable=setmetatable,installQA=installQA},
      coroutine=CO,table=table,select=select,pcall=pcall,print=print,string=string,error=error,
      type=type2,pairs=pairs,ipairs=ipairs,tostring=tostring,tonumber=tonumber,math=math,assert=assert,_VERBOSE=verbose
    }
    local qa = QAs[dev.id]
    for s,v in pairs(FB) do env[s]=v end                        -- Copy local exports to QA environment
    for s,v in pairs(QAs[dev.id].extras or {}) do env[s]=v end  -- Copy user provided environment symbols
    loadModules(localModules or {},env)                         -- Load default QA specfic modules into environment
    loadModules(EM.localModules or {},env)                      -- Load optional user specified module into environment
    env.os.exit=function() LOG("exit(0)") tasks={} coroutine.yield() end        
    local self=env.QuickApp
    qa.QA,qa.env=self,env
    LOG("Loading  QA:%s - ID:%s",dev.name,dev.id)
    local k = coroutine.create(function()
        for _,f in ipairs(qa.files) do                                     -- for every file we got, load it..
          if verbose then LOG("         ...%s",f.name) end
          local code = check(env.__TAG,load(f.content,f.fname,"t",env)) -- Load our QA code, check syntax errors
          check(env.__TAG,pcall(code))                                  -- Run the QA code, check runtime errors
        end
      end)
    procs[k]=QAs[dev.id] coroutine.resume(k) procs[k]=nil
    LOG("Starting QA:%s - ID:%s",dev.name,dev.id)
    runProc(QAs[dev.id],function() env.QuickApp:__init(dev) end)  -- Start QA by "creating instance"
  end

  function installQA(qa) runQA(addQA(qa)) end

  local function run(QA) 
    for _,qa in ipairs(QA[1] and QA or {QA}) do installQA(qa) end -- Create QAs given
    -- Timer loop - core of emulator, run each coroutine until none left or all locked
    while(true) do                     -- Loop and execute tasks when their time is up
      local i,time,co = peek()         -- Look at first enabled/unlocked task in queue
      if time == nil then break end
      local now = clock()
      if time <= now then              -- Times up?
        deqeue(i)                      -- Remove task from queue
        xpresume(co)                   -- ...and run it, xpresume handles errors
        procs[co]=nil                  -- ...clear co->QA map
      else                            
        socket.sleep(time-now)         -- "sleep" until next timer in line is up
      end                              -- ...because nothing else is running, no timer could enter before in queue.
    end                                   
    if #tasks > 0 then LOG("All threads locked - terminating") 
    else LOG("No threads left - terminating") end
    for _,qa in pairs(QAs) do if qa.save then EM.saveFQA(qa) end end
    QAs = {}                         -- Clear directory of QAs
  end
  return run

end -- emulator

builtins()                             -- Define built-ins
loadModules(globalModules or {})       -- Load global modules
loadModules(EM.globalModules or {})    -- Load optional user specified module into environment
local run = emulator()                 -- Setup emulator core - returns run function

print(fmt("---------------- Tiny QuickAppEmulator (TQAE) v%s -------------",version)) -- Get going...
EM.postEMEvent{type='start'}

if embedded then                   -- Embedded call...
  local file = debug.getinfo(2)    -- Find out what file that called us
  if file and file.source then
    if not file.source:sub(1,1)=='@' then error("Can't locate file:"..file.source) end
    run({file=file.source:sub(2)}) -- Run that file
    os.exit()
  end
else main(run) end                 -- Else call our playground...
