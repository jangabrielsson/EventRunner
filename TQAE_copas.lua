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
EM.logLevel      = DEF(EM.logLevel,1)
EM.htmlDebug     = DEF(EM.htmlDebug,true)
EM.utilities     = dofile(EM.modPath.."utilities.lua")
EM.copas         = dofile(EM.modPath.."copas.lua")

EM.LOGALLW,EM.LOGINFO1,EM.LOGINFO2,EM.LOGERR,EM.LOGLOCK=-1,1,2,0,3
local fibColors = { ["DEBUG"] = 'green', ["TRACE"] = 'blue', ["WARNING"] = 'orange', ["ERROR"] = 'red' }
local logColors = { [EM.LOGALLW] = 'brown', [EM.LOGERR]='red' }

local globalModules = { -- default global modules loaded into emulator environment
  "net_copas.lua","json.lua","files.lua", "webserver.lua", "api.lua", "proxy.lua", "ui.lua", "time.lua",
  "refreshStates_copas.lua", "stdQA.lua", "Scene.lua",
} 
local localModules  = { {"class.lua","QA"}, "fibaro.lua", {"QuickApp.lua","QA"} } -- default local modules loaded into QA environment

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

--  run{code=[[
--print("Start")
----%%name='TestQA1'
--function QuickApp:onInit()
--    if not fibaro.getValue(self.id,"value") then
--        self:updateProperty("value",true)
--      api.post("/plugins/restart",{deviceId=self.id})
--    end
--    function self:debugf(...) self:debug(string.format(...)) end
--    self:debugf("%s - %s",self.name,self.id)
--    self:debugf("Name1:%s",fibaro.getName(self.id))
--    self:debugf("Name2:%s",api.get("/devices/"..self.id).name)
--    self:debugf("Name3:%s",__fibaro_get_device(self.id).name)
--    hc3_emulator.installQA{name="MuQA",code=testQA} -- install another QA and run it
--end
--]],env={testQA=testQA}} -- we can add extra variables to our QA's environment

local et = loadfile("emu_tests.lua") -- more extensive tests.
if et then et(run) end 
end

---------------------------------------- TQAE -------------------------------------------------------------
do
  local stat,mobdebug = pcall(require,'mobdebug'); -- If we have mobdebug, enable coroutine debugging
  if stat then mobdebug.coro() end
end
local version = "0.23"

local socket = require("socket") 
local http   = require("socket.http")
local https  = require("ssl.https") 
local ltn12  = require("ltn12")

-- Modules
-- FB.x exported native fibaro functions. Ex- __fibaro_get_device, setTimeout etc. Plugins can add to this, ex. net.*
-- EM.x internal emulator functions, HTTP, LOG etc. Plugins can add to this...

local FB,Devices = {},{}  -- id->Device map
local fmt,LOG,call,loadModules,setTimeout,getContext = string.format
EM._info = { modules = { ["local"] = {}, global= {} } }

------------------------ Builtin functions ------------------------------------------------------
local function builtins()

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
      _,status,h = EM.copas.https.request(req)
    else
      _,status,h = EM.copas.http.request(req)
    end
    if tonumber(status) and status < 300 then 
      return resp[1] and table.concat(resp) or nil,status,h 
    else return nil,status,h end
  end

  local base = "http://"..EM.host.."/api"
  local function HC3Request(method,path,data) 
    local res,stat,h = httpRequest({method=method, url=base..path,
        user=EM.user, password=EM.pwd, data=data and FB.json.encode(data), timeout = 5000, 
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
    local co = coroutine.running()
    EM.systemTimer(function() coroutine.resume(co) end,ms)
    coroutine.yield(co)
  end
  -- Non standard
  function FB.__fibaro_call(id,name,path,data)
    local args = data.args or {}
    return Devices[id] and call(id,name,table.unpack(args)) or HC3Request("POST",path,data)
  end
  function FB.__fibaro_local(bool) local l = EM.locl==true; EM.locl = bool; return l end

  local html2color,ANSICOLORS,ANSIEND = EM.utilities.html2color,EM.utilities.ZBCOLORMAP,EM.utilities.ZBCOLOREND

  function FB.__fibaro_add_debug_message(tag,str,type)
    assert(str,"Missing tag for debug")
    if EM.htmlDebug then
      str = html2color(str)
      type = ANSICOLORS[(fibColors[type] or "black")]..type..ANSIEND
    else
      str=str:gsub("(</?font.->)","") -- Remove color tags
    end
    str=str:gsub("(&nbsp;)"," ")      -- remove html space
    print(fmt("%s [%s] [%s]: %s",EM.osDate("[%d.%m.%Y] [%H:%M:%S]"),type,tag,str))
  end

  function LOG(level,...) 
    if level > EM.logLevel then return end
    local colorCode = ANSICOLORS[logColors[level] or logColors[EM.LOGALLW]]
    print(fmt("%s |%sSYS  %s|: %s",EM.osDate("[%d.%m.%Y] [%H:%M:%S]"),colorCode,ANSIEND,fmt(...)))
  end

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
            LOG(EM.LOGINFO2,"Loading  %s module %s",env and "local" or "global",m) 
            EM._info.modules[env and "local" or "global"][m]=true
            local code,res=loadfile(EM.modPath..m,"t",env or _G)
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
  function EM.osTime(a) return a and os.time(a) or os.time()+offset end
  function EM.osDate(a,b) return os.date(a,b or EM.osTime()) end

  local EMEvents = {}
  function EM.EMEvents(typ,callback,front)
    local evs = EMEvents[typ] or {}
    if front then table.insert(evs,1,callback) else evs[#evs+1]=callback end 
    EMEvents[typ] = evs
  end
  function EM.postEMEvent(ev) for _,m in ipairs(EMEvents[ev.type] or {}) do m(ev) end end
  EM.LOG,EM.httpRequest,EM.HC3Request,EM.socket = LOG,httpRequest,HC3Request,socket
  EM.Devices=Devices
  FB.__assert_type = __assert_type
end

------------------------ Emulator core ----------------------------------------------------------
local function emulator()
  local procs,CO,clock,gID = {},coroutine,EM.clock,1001
  local copy,member,merge = EM.utilities.copy,EM.utilities.member,EM.utilities.merge
  function getContext(co) return procs[co or coroutine.running()] end
  EM.getContext = getContext
  local function yield(co) 
    local ctx,r=getContext(co) 
    ctx.lock.release(); 
    r={CO.yield(coroutine.running())}
    ctx.lock.get() 
    return table.unpack(r)
  end
  local function resume(co,...) 
    local ctx,r=getContext(co)
    ctx.lock.release(); 
    r = {CO.resume(co,...)}
    ctx.lock.get() 
    return table.unpack(r)    
  end
  local function cocreate(fun) 
    local co,ctx = CO.create(fun),getContext()
    procs[co]=ctx 
    return co 
  end
  local function killTimers()
    local ctx = getContext()
    for t,_ in pairs(ctx.timers) do t:cancel() end
  end
  local function timerCall(t,args)
    local fun,ctx = table.unpack(args)
    ctx.lock.get() 
    local stat,res = pcall(fun)
    ctx.lock.release() 
    ctx.timers[t]=nil
    if not stat then 
      if type(res)=='table' then
        killTimers()
      else LOG(EM.LOGERR,"ERR :%s",res) end
    end
  end
  function setTimeout(fun,ms,tag,ctx)
    ctx = ctx or procs[coroutine.running()]
    local t = EM.copas.timer.new({delay = ms/1000,recurring = false,callback = timerCall,params = {fun,ctx} })
    ctx.timers[t] = true
    procs[t.co] = ctx
    local v={time=ms/1000+EM.osTime(),t=t,ctx=ctx,descr=tostring(t.co),tag=tag}
    return v
  end
  local function IDF() end
  local sysCtx = {env={__TAG='SYSTEM'}, dev={}, timers={}, lock={get=IDF,release=IDF}}
  function EM.systemTimer(fun,ms,tag) return setTimeout(fun,ms,tag,sysCtx) end
  FB.setTimeout=setTimeout
  function FB.clearTimeout(ref) ref.t:cancel() end
  function FB.setInterval(fun,ms) 
    local r={} 
    local function loop() fun() if r[1] then r[1] = setTimeout(loop,ms) end end 
    r[1]=setTimeout(loop,ms) 
    return r 
  end
  function FB.clearInterval(ref) FB.clearTimeout(ref[1]) ref[1]=nil end
-- Used by api/devices/<id>/action/<name> to call and hand over to called QA's thread
  function call(id,name,...)
    local args,D = {...},Devices[id]
    return setTimeout(function() D.env.onAction(id,{deviceId=id,actionName=name,args=args}) end,0,nil,D) -- sim. call in another process/QA
  end
  function FB.type(o) local t = type(o) return t=='table' and o._TYPE or t end
-- Check arguments and print a QA error message 
  local function check(name,stat,err) if not stat then FB.__fibaro_add_debug_message(name,err,"ERROR") end return stat end
  function EM.getQA(id)
    local D = Devices[tonumber(id) or 0] if not D then return end
    if D.dev.parentId==0 then return D.env.quickApp,D.env,true 
    else return D.env.quickApp.childDevices[id],D.env,false end
  end

  local installQA,runQA
  local function restartQA(D) killTimers() runQA(D) end

  EM.EMEvents('QACreated',function(ev) -- Register device and clean-up when QA is created
      local qa,dev = ev.qa,ev.dev
      local info = dev._info
      Devices[dev.id],info.dev,dev._info =info,dev,nil
      if qa.id ~= dev.id then -- QA got proxy id - update
        LOG(EM.LOGINFO1,"Proxy: Changing device ID %s to proxy ID %s",qa.id,dev.id)
        qa.id=dev.id
        info.env.plugin.mainDeviceId = dev.id
        info.env.__TAG="QUICKAPP"..dev.id
      end
    end)

  local deviceTemplates
  function EM.createDevice(info)
    local typ = info.type or "com.fibaro.binarySensor"
    if deviceTemplates == nil then 
      local f = io.open(EM.modPath.."devices.json")
      if f then deviceTemplates=FB.json.decode(f:read("*all")) f:close() else deviceTemplates={} end
    end
    local dev = deviceTemplates[typ] and copy(deviceTemplates[typ]) or {
      actions = { turnOn=0,turnOff=0,setValue=1,toggle=0 }
    }
    dev.id = info.id
    if not dev.id then dev.id = gID; gID=gID+1 end
    dev.name,dev.parentId = info.name or "MyQuickApp",0
    merge(dev.interfaces,info.interfaces or {})
    merge(dev.properties,info.properties or {})
    dev._info = info
    LOG(EM.LOGINFO1,"Created %s device %s",(member('quickAppChild',info.interfaces or {}) and "child" or ""),dev.id)
    return dev
  end

  local function createInfo(spec) -- Creates the device structure and save the QA/device files
    local id,name,typ,code,file,e = spec.id,spec.name,spec.type,spec.code,spec.file,spec.env
    local files,info = EM.loadFile(code,file)
    info.properties = info.properties or {}
    info.properties.quickAppVariables = info.properties.quickAppVariables or {}
    for k,v in pairs(info.quickVars or {}) do table.insert(info.properties.quickAppVariables,1,{name=k,value=v}) end
    info.id,info.name,info.type=id or info.id,name or info.name or "MyQuickApp",typ or info.type or "com.fibaro.binarySwitch"
    info.files,info.fileMap,info.save,info.extras,info.restart,info.codeType=files,{},spec.save or info.save,e,restartQA,"QA"
    for _,f in ipairs(info.files) do if not info.fileMap[f.name] then info.fileMap[f.name]=f end end
    if not info.id then info.id = gID; gID=gID+1 end
    local lock = EM.copas.lock.new(60000)
    info.timers,info._lock = {},lock
    info.lock = { 
      get = function() 
        LOG(EM.LOGLOCK,"GET(%s) %s",info.id,coroutine.running()) 
        lock:get() 
        LOG(EM.LOGLOCK,"GOT(%s) %s",info.id,coroutine.running()) 
      end, 
      release=function() 
        LOG(EM.LOGLOCK,"RELEASE(%s) %s",info.id,coroutine.running()) 
        lock:release() 
      end 
    }
    return info
  end

  local LOADLOCK = EM.copas.lock.new(600)

  function runQA(info)        -- Creates an environment and load file modules and starts QuickApp (:onInit())
    local env = {             -- QA environment, all Lua functions available for  QA, 
      plugin={ mainDeviceId = info.id },
      os={
        time=EM.osTime, date=EM.osDate, clock=os.clock, difftime=os.difftime,
        exit=function() LOG(EM.LOGALLW,"exit(0)") error({type='exit'}) end
      },
      hc3_emulator={
        getmetatable=getmetatable,setmetatable=setmetatable,io=io,installQA=installQA,EM=EM,
        os={setTimer=setTimeout},trigger=EM.trigger,create=EM.createDevices
      },
      coroutine={running=CO.running,yield=yield,resume=resume,create=cocreate},
      table=table,select=select,pcall=pcall,xpcall=xpcall,print=print,string=string,error=error,collectgarbage=collectgarbage,
      next=next,pairs=pairs,ipairs=ipairs,tostring=tostring,tonumber=tonumber,math=math,assert=assert,_LOGLEVEL=EM.logLevel
    }
    info.env,env._G=env,env
    for s,v in pairs(FB) do env[s]=v end                        -- Copy local exports to QA environment
    for s,v in pairs(info.extras or {}) do env[s]=v end         -- Copy user provided environment symbols
    loadModules(localModules or {},env,info.scene)              -- Load default QA specfic modules into environment
    loadModules(EM.localModules or {},env,info.scene)           -- Load optional user specified module into environment    
    EM.postEMEvent({type='infoEnv', info=info})
    LOADLOCK:get()
    LOG(EM.LOGINFO1,"Loading  %s:%s",info.codeType,info.name)
    for _,f in ipairs(info.files) do                                  -- for every file we got, load it..
      LOG(EM.LOGINFO2,"         ...%s",f.name)
      local code = check(env.__TAG,load(f.content,f.fname,"t",env))   -- Load our QA code, check syntax errors
      check(env.__TAG,pcall(code))                                    -- Run the QA code, check runtime errors
    end
    LOADLOCK:release()
    if env.QuickApp and env.QuickApp.onInit then
      LOG(EM.LOGINFO1,"Starting QA:%s - ID:%s",info.name,info.id)       -- Start QA by "creating instance"
      local dev = EM.createDevice(info)
      local stat,res = pcall(env.QuickApp,dev)
      if not stat then LOG(EM.LOGERR,"Ups %s",res) end
    elseif env.ACTION then
      EM.postEMEvent({type='sceneLoaded', info=info})     
    end
  end

  function installQA(spec) 
    local info = createInfo(spec); 
    setTimeout(function() 
        runQA(info) 
      end,0,nil,info) end
    EM.installQA = installQA

    local function run(QA) 
      for _,qa in ipairs(QA[1] and QA or {QA}) do installQA(qa) end -- Create QAs given
    end
    return run
  end -- emulator

  builtins()                             -- Define built-ins
  loadModules(globalModules or {})       -- Load global modules
  loadModules(EM.globalModules or {})    -- Load optional user specified modules into environment
  local run = emulator()                 -- Setup emulator core - returns run function

  print(fmt("---------------- Tiny QuickAppEmulator (TQAE) v%s -------------",version)) -- Get going...

  local file = debug.getinfo(2)           -- Find out what file that called us
  EM.copas.loop(function()
      EM.postEMEvent{type='start'}            -- Announce that we have started
      if embedded then                        -- Embedded call...
        if file and file.source then
          if not file.source:sub(1,1)=='@' then error("Can't locate file:"..file.source) end
          run({file=file.source:sub(2)})      -- Run that file
        end
      else main(run) end                      -- Else call our playground...
    end)

  LOG(EM.LOGALLW,"End - runtime %.2f min",(EM.osTime()-EM._info.started)/60)
  os.exit()
