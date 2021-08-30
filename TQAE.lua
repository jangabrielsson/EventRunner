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
json           -- Copyright (c) 2020 rxi
--]]

local embedded=...              -- get parameters if emulator included from QA code...
local EM = embedded or {}
local function DEF(x,y) if x==nil then return y else return x end end

EM.paramsFile  = DEF(EM.paramsFile,"TQAEconfigs.lua")
do 
  local pf = loadfile(EM.paramsFile); if pf then local p = pf() or {}; for k,v in pairs(EM) do p[ k ]=v end EM=p end 
end
EM.modPath       = DEF(EM.modpath,"TQAEmodules/")   -- directory where TQAE modules are stored
EM.temp          = DEF(EM.temp,os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "temp/") -- temp directory
EM.logLevel      = DEF(EM.logLevel,2)
EM.LOGALLW,EM.LOGINFO1,EM.LOGINFO2,EM.LOGERR=0,1,2,0

local globalModules = { -- default global modules loaded into emulator environment
  "net.lua","json.lua","files.lua", "webserver.lua", "api.lua", "proxy.lua", "ui.lua",
} 
local localModules  = { "class.lua", "fibaro.lua", "QuickApp.lua" } -- default local modules loaded into QA environment

local function main(run) -- playground

--  run{file='GEA_v7.20.fqa'}
  local testQA = [[
  --%%quickVars={x='Hello'}
  --%%interfaces={"power"}
  --%%type="com.fibaro.multilevelSwitch"
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

  local et = loadfile("emu_tests.lua") -- more extensive tests.
  if et then et(run) end 
end

---------------------------------------- TQAE -------------------------------------------------------------
do
  local stat,mobdebug = pcall(require,'mobdebug'); -- If we have mobdebug, enable coroutine debugging
  if stat then mobdebug.coro() end
end
local version = "0.16"

local socket = require("socket")
local http   = require("socket.http")
local https  = require("ssl.https") 
local ltn12  = require("ltn12")

-- Modules
-- FB.x exported native fibaro functions. Ex- __fibaro_get_device, setTimeout etc. Plugins can add to this, ex. net.*
-- EM.x internal emulator functions, HTTP, LOG etc. Plugins can add to this...

local FB,Devices = {},{}  -- id->Device map
local fmt,LOG,call,loadModules,timers,setTimeout,getContext,setContext,xpresume = string.format
EM._info = { modules = { ["local"] = {}, global= {} } }

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
      return resp[1] and table.concat(resp) or nil,status,h 
    else return nil,status,h end
  end

  local base = "http://"..EM.host.."/api"
  local function HC3Request(method,path,data) 
    local res,stat,h = httpRequest({method=method, url=base..path,
        user=EM.user, password=EM.pwd, data=data and FB.json.encode(data),
        headers = {["Accept"] = '*/*',["X-Fibaro-Version"] = 2, ["Fibaro-User-PIN"] = EM.pin},
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
-- basic api functions, tries to deal with local emulated Devices too. Local Device have precedence over HC3 Devices.
  function FB.__fibaro_get_device(id) __assert_type(id,"number") return Devices[id] and Devices[id].dev or HC3Request("GET","/devices/"..id) end
  function FB.__fibaro_get_devices() 
    local ds = HC3Request("GET","/devices") or {}
    for _,dev in pairs(Devices) do ds[#ds+1]=dev.dev end -- Add emulated Devices
    return ds 
  end 
  function FB.__fibaro_get_room (id) __assert_type(id,"number") return HC3Request("GET","/rooms/"..id) end
  function FB.__fibaro_get_scene(id) __assert_type(id,"number") return HC3Request("GET","/scenes/"..id) end
  function FB.__fibaro_get_global_variable(name) __assert_type(name ,"string") return HC3Request("GET","/globalVariables/"..name) end
  function FB.__fibaro_get_device_property(id ,prop) 
    __assert_type(id,"number") __assert_type(prop,"string")
    local D = Devices[id]  -- Is it a local Device?
    if D then return D.dev.properties[prop] and { value = D.dev.properties[prop], modified=0} or nil
    else return HC3Request("GET","/devices/"..id.."/properties/"..prop) end
  end
  function FB.__fibaro_get_partition(id) return HC3Request("GET",'/alarms/v1/partitions/' .. id) end
  function FB.__fibaroUseAsyncHandler(_) end -- TBD
  function FB.__fibaroSleep(ms) -- We lock all timers/coroutines except the one resuming the sleep for us
    local r,D,co; co,r = coroutine.running(),setTimeout(function() setContext(co,D) timers.lock(r,false) xpresume(co) end,ms) 
    D = getContext() timers.lock(r,true); coroutine.yield(co)
  end
  -- Non standard
  function FB.__fibaro_call(id,name,path,data)
    local args = data.args or {}
    return Devices[id] and call(id,name,table.unpack(args)) or HC3Request("POST",path,data)
  end
  function FB.__fibaro_local(bool) local l = EM.locl==true; EM.locl = bool; return l end

  function FB.__fibaro_add_debug_message(tag,str,type)
    assert(str,"Missing tag for debug")
    str=str:gsub("(</?font.->)","") str=str:gsub("(&nbsp;)"," ") -- Remove HTML tags
    print(fmt("%s [%s] [%s]: %s",EM.osDate("[%d.%m.%Y] [%H:%M:%S]"),type,tag,str))
  end
  function FB.urldecode(str) return str and str:gsub('%%(%x%x)',function (x) return string.char(tonumber(x,16)) end) end
  function FB.urlencode(str) return str and str:gsub("([^% w])",function(c) return string.format("%%% 02X",string.byte(c))  end) end
  function string.split(str, sep)
    local fields,s = {},sep or "%s"
    str:gsub("([^"..s.."]+)", function(c) fields[#fields + 1] = c end)
    return fields
  end

  function loadModules(ms,env,args)
    ms = type(ms)=='table' and ms or {ms}
    local stat,res = pcall(function()
        for _,m in ipairs(ms) do
          if type(m)=='table' then m,args=m[1],m[2] end
          LOG(EM.LOGINFO2,"Loading  %s module %s",env and "local" or "global",m) 
          table.insert(EM._info.modules[env and "local" or "global"],m)
          local code,res=loadfile(EM.modPath..m,"t",env or _G)
          assert(code,res)
          code(EM,FB,args or {})
        end
      end)
    if not stat then error("Loading module "..res) end
  end

  local offset=0
  function EM.setDate(str)
    local function tn(str,v) return tonumber(str) or v end
    local d,hour,min,sec = str:match("(.-)%-?(%d+):(%d+):?(%d*)")
    local month,day,year=d:match("(%d*)/?(%d*)/?(%d*)")
    local t = os.date("*t")
    t.year,t.month,t.day=tn(year,t.year),tn(month,t.month),tn(day,t.day)
    t.hour,t.min,t.sec=tn(hour,t.hour),tn(min,t.min),tn(sec,0)
    local t1 = os.time(t)
    local t2 = os.date("*t",t1)
    if t.isdst ~= t2.isdst then t.isdst = t2.isdst t1 = os.time(t) end
    offset = t1-os.time()
  end
  function EM.clock() return socket.gettime()+offset end
  function EM.osTime(a) return a and os.time(a) or os.time()+offset end
  function EM.osDate(a,b) return os.date(a,b or EM.osTime()) end

  local EMEvents = {}
  function EM.EMEvents(typ,callback,front)
    local evs = EMEvents[typ] or {}
    if front then table.insert(evs,1,callback) else evs[#evs+1]=callback end 
    EMEvents[typ] = evs
  end
  function EM.postEMEvent(ev) for _,m in ipairs(EMEvents[ev.type] or {}) do m(ev) end end
  function LOG(level,...) if level <= EM.logLevel then print(fmt("%s |SYS  |: %s",EM.osDate("[%d.%m.%Y] [%H:%M:%S]"),fmt(...))) end end
  EM.LOG,EM.httpRequest,EM.HC3Request,EM.socket = LOG,httpRequest,HC3Request,socket
  EM.Devices=Devices
  FB.__assert_type = __assert_type
end

------------------------ Timers ----------------------------------------------------------
local function timerQueue() -- A sorted timer queue...
  local tq,pcounter,ptr = {},{}
  local tmt={ __tostring = function(t) return t.descr end}

  function tq.queue(t,tag,co,D)    -- Insert timer
    tag = tag or "user"; pcounter[tag] = (pcounter[tag] or 0)+1
    local v={t=t+EM.osTime(),co=co,D=D,descr=tostring(co),tag=tag} setmetatable(v,tmt) 
    if ptr == nil then ptr = v
    elseif v.t < ptr.t then v.next=ptr; ptr.prev = v; ptr = v
    else
      local p = ptr
      while p.next and p.next.t <= v.t do p = p.next end   
      if p.next then v.next,p.next = p.next,v; v.next.prev = v
      else p.next,v.prev = v,p end
    end
    return v
  end

  function tq.dequeue(v) -- remove a timer
    local n = v.next
    pcounter[v.tag]=pcounter[v.tag]-1
    if v==ptr then ptr = v.next else v.prev.next = v.next if v.next then v.next.prev=v.prev end end
    v.next,v.prev=nil,nil
    return n
  end

  function tq.clearTimers(id) -- Clear all timers belonging to QA with id
    local p = ptr
    while p do if p.D and p.D.dev.id == id then p=tq.dequeue(p) else p=p.next end end
  end

  function tq.peek() -- Return next unlocked timer
    local p = ptr
    while p do if not tq.locked(p) then return p,p.t,p.co end p=p.next end 
  end

  function tq.lock(t,b) if t.D then t.D.env.locked = b and t.co or nil end end
  function tq.locked(t) local l = t.D and t.D.env.locked; return l and l~=t.co end
  function tq.tags(tag) return pcounter[tag] or 0 end
  function tq.reset() ptr=nil; for k,_ in pairs(pcounter) do pcounter[k]=0 end end
  function tq.get() return ptr end
  return tq
end

------------------------ Emulator core ----------------------------------------------------------
local function emulator()
  local procs,CO,clock,gID = {},coroutine,EM.clock,1001
  local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
  local function merge(dest,src) for k,v in pairs(src) do dest[k]=v end end
  function setContext(co,D) procs[co]= D or procs[coroutine.running()]; return co,procs[co] end
  function getContext(co) co=co or coroutine.running() return procs[co] end
  function setTimeout(fun,ms,tag) return timers.queue(ms/1000,tag,setContext(CO.create(fun))) end
  FB.setTimeout=setTimeout
-- Like setTimeout but sets another QA's context - used when starting up and fibaro.cal
  local function runProc(D,fun) procs[coroutine.running()]=D setTimeout(fun,0) return D end
  function FB.clearTimeout(ref) timers.dequeue(ref) end
  function FB.setInterval(fun,ms) 
    local r={} 
    local function loop() fun() local r2 = setTimeout(loop,ms) r.t,r.co,r.D,r.tag,r.descr=r2.t,r2.co,r2.D,r2.tag,r2.descr end 
    loop(); return r 
  end
  function FB.clearInterval(ref) FB.clearTimeout(ref) end

-- Used by api/devices/<id>/action/<name> to call and hand over to called QA's thread
  function call(id,name,...)
    local args,D = {...},Devices[id]
    runProc(dev,function() D.env.onAction(id,{deviceId=id,actionName=name,args=args}) end) -- sim. call in another process/QA
  end
  function FB.type(o) local t = type(o) return t=='table' and o._TYPE or t end
-- Check arguments and print a QA error message 
  local function check(name,stat,err) if not stat then FB.__fibaro_add_debug_message(name,err,"ERROR") end return stat end
-- Resume a coroutine and handle errors
  function xpresume(co)  
    local stat,res = CO.resume(co)
    if not stat then 
      check(procs[co] and procs[co].env.__TAG or "",stat,res) debug.traceback(co) 
    end
  end
  function EM.getQA(id)
    local D = Devices[tonumber(id) or 0] if not D then return end
    if D.dev.parentId==0 then return D.env.quickApp,D.env,true 
    else return D.env.quickApp.childDevices[id],D.env,false end
  end

  local installQA,runQA
  local function restartQA(D) timers.clearTimers(D.dev.id) runQA(D) coroutine.yield() end

  local deviceTemplates
  function EM.createDevice(id,name,typ,properties,interfaces,info)
    typ = typ or "com.fibaro.binarySensor"
    if deviceTemplates == nil then 
      local f = io.open(EM.modPath.."devices.json")
      if f then deviceTemplates=FB.json.decode(f:read("*all")) f:close() else deviceTemplates={} end
    end
    local dev = deviceTemplates[typ] and copy(deviceTemplates[typ]) or {
      actions = { turnOn=0,turnOff=0,setValue=1,toggle=0 }
    }
    if id then dev.id = id else dev.id = gID; gID=gID+1 end
    dev.name,dev.parentId = name or "MyQuickApp",0
    merge(dev.interfaces,interfaces or {})
    merge(dev.properties,properties or {})
    Devices[dev.id] = {dev=dev, info=info or {}}
    LOG(EM.LOGINFO1,"Created device %s",dev.id)
    EM.postEMEvent({type='deviceCreated',id=dev.id})
    return Devices[dev.id].dev,Devices[dev.id]
  end

  local function addDevice(spec) -- Creates the device structure and save the QA/device files
    local id,name,typ,code,file,e = spec.id,spec.name,spec.type,spec.code,spec.file,spec.env
    local files,info = EM.loadFile(code,file)
    info.properties = info.properties or {}
    info.properties.quickAppVariables = info.properties.quickAppVariables or {}
    for k,v in pairs(info.quickVars or {}) do table.insert(info.properties.quickAppVariables,1,{name=k,value=v}) end
    local _,D = EM.createDevice(id or info.id,name or info.name,typ or info.type,info.properties,info.interfaces, info)
    D.files,D.save,D.extras,D.restart=files,spec.save or info.save,e,restartQA
    return D
  end

  function runQA(D)        -- Creates an environment and load file modules and starts QuickApp (:onInit())
    local env = {          -- QA environment, all Lua functions available for  QA, 
      plugin={ mainDeviceId = D.dev.id },
      os={time=EM.osTime, date=EM.osDate, exit=function() LOG(EM.LOGALLW,"exit(0)") timers.reset() coroutine.yield() end},
      hc3_emulator={getmetatable=getmetatable,setmetatable=setmetatable,installQA=installQA,EM=EM},
      coroutine=CO,table=table,select=select,pcall=pcall,xpcall=xpcall,print=print,string=string,error=error,
      next=next,pairs=pairs,ipairs=ipairs,tostring=tostring,tonumber=tonumber,math=math,assert=assert,_LOGLEVEL=EM.logLevel
    }
    for s,v in pairs(FB) do env[s]=v end                        -- Copy local exports to QA environment
    for s,v in pairs(D.extras or {}) do env[s]=v end            -- Copy user provided environment symbols
    loadModules(localModules or {},env)                         -- Load default QA specfic modules into environment
    loadModules(EM.localModules or {},env)                      -- Load optional user specified module into environment     
    D.env,env._G=env,env
    LOG(EM.LOGINFO1,"Loading  QA:%s - ID:%s",D.dev.name,D.dev.id)
    local k = coroutine.create(function()
        for _,f in ipairs(D.files) do                                     -- for every file we got, load it..
          LOG(EM.LOGINFO2,"         ...%s",f.name)
          local code = check(env.__TAG,load(f.content,f.fname,"t",env))   -- Load our QA code, check syntax errors
          check(env.__TAG,pcall(code))                                    -- Run the QA code, check runtime errors
        end
      end)
    procs[k]=D coroutine.resume(k) procs[k]=nil
    LOG(EM.LOGINFO1,"Starting QA:%s - ID:%s",D.dev.name,D.dev.id)
    -- Start QA by "creating instance"
    runProc(dev,function() env.QuickApp(D.dev) end)  
    if D.info.noterminate then runProc(D,function() env.setInterval(function() end,5000) end) end -- keep alive...
  end

  function installQA(spec) setTimeout(function() runQA(addDevice(spec)) end,0) end

  local function run(QA) 
    for _,qa in ipairs(QA[1] and QA or {QA}) do installQA(qa) end -- Create QAs given
    -- Timer loop - core of emulator, run each coroutine until none left or all locked
    while(timers.tags('user') > 0) do  -- Loop as long as there are user timers and execute them when their time is up
      local t,time,co = timers.peek()  -- Look at first enabled/unlocked task in queue
      if time == nil then break end
      local now = clock()
      if time <= now then              -- Times up?
        timers.dequeue(t)              -- Remove task from queue
        xpresume(co)                   -- ...and run it, xpresume handles errors
        procs[co]=nil                  -- ...clear co->QA map
      else                            
        socket.sleep(time-now)         -- "sleep" until next timer in line is up
      end                              -- ...because nothing else is running, no timer could enter before in queue.
    end                                   
    if timers.tags('user') > 0 then LOG(EM.LOGINFO1,"All threads locked - terminating") 
    else LOG(EM.LOGINFO1,"No threads left - terminating") end
    for k,D in pairs(Devices) do if D.save then EM.saveFQA(D) end Devices[k]=nil end -- Save and clear directory of Devices                
  end
  return run

end -- emulator

timers = timerQueue(); EM.timers=timers-- Create timer queue
builtins()                             -- Define built-ins
loadModules(globalModules or {})       -- Load global modules
loadModules(EM.globalModules or {})    -- Load optional user specified modules into environment
local run = emulator()                 -- Setup emulator core - returns run function

print(fmt("---------------- Tiny QuickAppEmulator (TQAE) v%s -------------",version)) -- Get going...
if EM.startTime then EM.setDate(EM.startTime) end
EM._info.started = EM.osTime()
EM.postEMEvent{type='start'}            -- Announce that we have started

if embedded then                        -- Embedded call...
  local file = debug.getinfo(2)         -- Find out what file that called us
  if file and file.source then
    if not file.source:sub(1,1)=='@' then error("Can't locate file:"..file.source) end
    run({file=file.source:sub(2)})      -- Run that file
  end
else main(run) end                      -- Else call our playground...
LOG(EM.LOGALLW,"End - runtime %.2f min",(EM.osTime()-EM._info.started)/60)
os.exit()
