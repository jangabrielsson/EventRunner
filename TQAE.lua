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

local embedded=...
local gParams = embedded or {}
local function DEF(x,y) if x==nil then return y else return x end end
gParams.paramsFile  = DEF(gParams.paramsFile,"TQAEconfigs.lua")
do 
  local pf = loadfile(gParams.paramsFile); if pf then local p = pf() or {}; for k,v in pairs(gParams) do p[ k ]=v end gParams=p end 
end
gParams.verbose  = DEF(gParams.verbose,false)
gParams.modPath  = DEF(gParams.modpath,"TQAEmodules/")   -- directory where TQAE modules are stored
gParams.temp     = DEF(gParams.temp,os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "temp/") -- temp directory
local verbose    = gParams.verbose

-- default global modules loaded into emulator environment
local globalModules = { "net.lua","json.lua","fibaro.lua","files.lua" }
-- default local modules loaded into QA environment
local localModules = { "QuickApp.lua" }  

local function main(run) -- playground

--  run{file='GEA_v7.20.fqa'}
  local testQA = [[
  --%%quickVars={x='Hello'}
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
    function self:debugf(...) self:debug(string.format(...)) end
    self:debugf("%s - %s",self.name,self.id)
    self:debugf("Name1:%s",fibaro.getName(self.id))
    self:debugf("Name2:%s",api.get("/devices/"..self.id).name)
    self:debugf("Name3:%s",__fibaro_get_device(self.id).name)
    hc3_emulator.installQA{name="MuQA",code=testQA} -- install another QA and run it
end
--]],env={testQA=testQA}}

  loadfile("emu_tests.lua")(run)
end

---------------------------------------- TQAE -------------------------------------------------------------
local stat,mobdebug = pcall(require,'mobdebug'); -- If we have mobdebug, enable coroutine debugging
if stat then mobdebug.coro() end
local version = "0.5"

local socket = require("socket")
local http   = require("socket.http")
local https  = require("ssl.https") 
local ltn12  = require("ltn12")

local fmt,loadFile,loadModules,xpresume,lock=string.format 
--Exports: setContext,getContext,call,getQA,LOG,
--Imports: fibaro,json,api,net

------------------------ Builtin functions ------------------------------------------------------
local function builtins()

  function httpRequest(reqs,extra)
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
    if tonumber(status) and status < 300 then return resp[1] and json.decode(table.concat(resp)) or nil,status,h else return nil,status,h end
  end

  local base = "http://"..gParams.host.."/api"
  function HC3Request(method,path,data) 
    return httpRequest({method=method, url=base..path,
        user=gParams.user, password=gParams.pwd, data=data and json.encode(data),
        headers = {["Accept"] = '*/*',["X-Fibaro-Version"] = 2, ["Fibaro-User-PIN"] = gParams.pin},
      })
  end

  function __assert_type(value,typeOfValue )
    if type(value) ~= typeOfValue then  -- Wrong parameter type, string required. Provided param 'nil' is type of nil
      error(fmt("Wrong parameter type, %s required. Provided param '%s' is type of %s",
          typeOfValue,tostring(value),type(value)),
        3)
    end
  end
  function __ternary(test, a1, a2) if test then return a1 else return a2 end end
-- basic api functions, tries to deal with local emulated QAs too. Local QAs have precedence over HC3 QAs.
  function __fibaro_get_device(id) __assert_type(id,"number") return getQA(id) or HC3Request("GET","/devices/"..id) end
  function __fibaro_get_devices() 
    local ds = HC3Request("GET","/devices") or {}
    for _,qa in pairs(getQA()) do ds[#ds+1]=qa.QA end -- Add emulated QAs
    return ds 
  end 
  function __fibaro_get_room (id) __assert_type(id,"number") return HC3Request("GET","/rooms/"..id) end
  function __fibaro_get_scene(id) __assert_type(id,"number") return HC3Request("GET","/scenes/"..id) end
  function __fibaro_get_global_variable(name) __assert_type(name ,"string") return HC3Request("GET","/globalVariables/"..name) end
  function __fibaro_get_device_property(id ,prop) 
    __assert_type(id,"number") __assert_type(prop,"string")
    local qa = getQA(id) -- Is it a local QA?
    if qa then return qa.properties[prop] and { value = qa.properties[prop], modified=0} or nil
    else return HC3Request("GET","/devices/"..id.."/properties/"..prop) end
  end
  function __fibaroSleep(ms) -- We lock all timers/coroutines except the one resuming the sleep for us
    local r,qa,co; co,r = coroutine.running(),setTimeout(function() setContext(co,qa) lock(r,false) xpresume(co) end,ms) 
    qa = getContext() lock(r,true); coroutine.yield(co)
  end
  -- Non standard
  function __fibaro_call(id,name,path,data)
    return getQA(id) and call(id,name,table.unpack(data.args)) or HC3Request("POST",path,data)
  end

  function __fibaro_add_debug_message(tag,type,str)
    assert(str,"Missing tag for debug")
    str=str:gsub("(</?font.->)","") str=str:gsub("(&nbsp;)"," ") -- Remove HTML tags
    print(fmt("%s [%s] [%s]: %s",os.date("[%d.%m.%Y] [%H:%M:%S]"),type,tag,str))
  end

-- Class support, mimicking LuaBind's class implementation
  local metas = {}
  for _,m in ipairs({
      "__add","__sub","__mul","__div","__mod","__pow","__unm","__idiv","__band","__bor",
      "__bxor","__bnot","__shl","__shr","__concat","__len","__eq","__lt","__le","__call",
      "__tostring"
      }) do
    metas[m]=true
  end

  function property(get,set)
    assert(type(get)=='function' and type(set)=="function","Property need function set and get")
    return {['%CLASSPROP%']=true, get=get, set=set}
  end

  local function trapIndex(props,cmt,obj)
    function cmt.__index(_,key)
      if props[key] then return props[key].get(obj) else return rawget(obj,key) end
    end
    function cmt.__newindex(_,key,val)
      if props[key] then return props[key].set(obj,val) else return rawset(obj,key,val) end
    end
  end

  function class(name)       -- Version that tries to avoid __index & __newindex to make debugging easier
    local cl,mt,cmt,props,parent= {['_TYPE']='userdata'},{},{},{}  -- We still try to be Luabind class compatible
    function cl.__copyObject(cl,obj)
      for k,v in pairs(cl) do if metas[k] then cmt[k]=v else obj[k]=v end end
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
    getContext().env[name] = cl
    return function(p) -- Class creation -- class <name>
      parent = p 
      if parent then parent.__copyObject(parent,cl) end
    end 
  end

  local function setLocal(name,v)
    local idx,ln,lv = 1,true
    while ln do
      ln, lv = debug.getlocal(5, idx)
      if ln == name then if verbose then Log("Importing "..name) end debug.setlocal(5,idx,v) return  end
      idx=idx+1
    end
    error("Import "..name.." not found")
  end

  function loadModules(ms,env)
    ms = type(ms)=='table' and ms or {ms}
    local stat,res = pcall(function()
        for _,m in ipairs(ms) do 
          if verbose then LOG("Loading  %s module %s",env and "local" or "global",m) end
          local code,res=loadfile(gParams.modPath..m,"t",env or _G)
          assert(code,res)
          local imports = code(gParams) or {}
          for k,v in pairs(imports.globals or {}) do setLocal(k,v) end
        end
      end)
    if not stat then error("Loading module "..res) end
  end

  function LOG(...) print(fmt("%s |SYS  |: %s",os.date("[%d.%m.%Y] [%H:%M:%S]"),fmt(...))) end
end
------------------------ Emulator core ----------------------------------------------------------
local function emulator()
  local QADir,tasks,procs,CO,clock,insert,gID = {},{},{},coroutine,socket.gettime,table.insert,1001
  local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
  function getQA(id) if id==nil then return QADir else local qa = QADir[id] if qa then return qa.QA,qa.env end end end
  -- meta table to print threads like "thread ..."
  local tmt={ __tostring = function(t) return t[4] end}
  -- Insert timer in queue, sorted on ascending absolute time
  local function queue(t,co,q) 
    local v={t+os.time(),co,q,tostring(co)} setmetatable(v,tmt) 
    for i=1,#tasks do if v[1]<tasks[i][1] then insert(tasks,i,v) return v end end 
    tasks[#tasks+1]=v return v 
  end

  local function deqeue(i) table.remove(tasks,i) end
  -- Lock or unlock QA. peek8) will return first unlocked. Used by fibaro.sleep to lock all other timers in same QA
  function lock(t,b) if t[3] then t[3].env.locked = b and t[2] or nil end end

  local function locked(t) local locked = t[3] and t[3].env.locked; return locked and locked~=t[2] end
  -- set QA context to given or current coroutine - we can then pickup the context from the current coroutine
  function setContext(co,qa) procs[co]= qa or procs[coroutine.running()]; return co,procs[co] end

  function getContext(co) co=co or coroutine.running() return procs[co] end

  local function peek() for i=1,#tasks do if not locked(tasks[i]) then return i,table.unpack(tasks[i] or {}) end end end

  function setTimeout(fun,ms) return queue(ms/1000,setContext(CO.create(fun))) end
  -- Like setTimeout but sets another QA's context - used when starting up and fibaro.cal
  local function runProc(qa,fun) procs[coroutine.running()]=qa setTimeout(fun,0)  return qa end

  function clearTimeout(ref) for i=1,#tasks do if ref==tasks[i] then table.remove(tasks,i) return end end end

  function setInterval(fun,ms) local r={} local function loop() fun() r[1],r[2],r[3]=table.unpack(setTimeout(loop,ms)) end loop() return r end

  function clearInterval(ref) clearTimeout(ref) end

  -- Used by api/devices/<id>/action/<name> to call and hand over to called QA's thread
  function call(id,name,...)
    local args,QA = {...},QADir[id]
    runProc(QA,function() QA.env.onAction(QA.QA,{deviceId=id,actionName=name,args=args}) end) -- sim. call in another process/QA
  end
  local function type2(o) local t = type(o) return t=='table' and o._TYPE or t end
  -- Check arguments and print a QA error message 
  local function check(name,stat,err) if not stat then __fibaro_add_debug_message(name,"ERROR",err) end return stat end
  -- Resume a coroutine and handle errors
  function xpresume(co)  
    local stat,res = CO.resume(co)
    if not stat then 
      check(procs[co].env.__TAG,stat,res) debug.traceback(co) 
    end
  end

  local function installQA(qa) -- code can be string or file
    local id,name,typ,code,file,e = qa.id,qa.name,qa.type,qa.code,qa.file,qa.env
    local env = {          -- QA environment, all Lua functions available for  QA, 
      plugin={}, os=copy(os), json=json, fibaro=copy(fibaro), hc3_emulator={getmetatable=getmetatable,installQA=installQA},
      __assert_type=__assert_type, __fibaro_get_device=__fibaro_get_device, __fibaro_get_devices=__fibaro_get_devices,
      __fibaro_get_room=__fibaro_get_room, __fibaro_get_scene=__fibaro_get_scene, 
      __fibaro_get_global_variable=__fibaro_get_global_variable, __fibaro_get_device_property=__fibaro_get_device_property,
      __fibaroSleep=__fibaroSleep, __fibaro_add_debug_message=__fibaro_add_debug_message,_VERBOSE=verbose,
      setTimeout=setTimeout, setInterval=setInterval, clearTimeout=clearTimeout, clearInterval=clearInterval,assert=assert,
      coroutine=CO,table=table,select=select,pcall=pcall,tostring=tostring,print=print,net=net,api=api,string=string,error=error,
      type=type2,pairs=pairs,ipairs=ipairs,tostring=tostring,tonumber=tonumber,math=math,class=class,propert=property
    }
    for s,v in pairs(e or {}) do env[s]=v end       -- Copy usert provided environment symbols
    -- Setup device struct
    local files,info = loadFile(code,file)
    local dev = {}
    dev.id = id or info.id or gID; gID=gID+1
    env.plugin.mainDeviceId = dev.id
    dev.name = name or info.name or "MyQuickApp"
    dev.type = typ or info.type or "com.fibaro.binarySensor"
    dev.properties = info.properties or {}
    dev.properties.quickAppVariables = dev.properties.quickAppVariables or {}
    for k,v in pairs(info.quickVars or {}) do table.insert(dev.properties.quickAppVariables,{name=k,value=v}) end
    loadModules(localModules or {},env)             -- Load default QA specfic modules into environment
    loadModules(gParams.localModules or {},env)      -- Load optional user specified module into environment
    env.os.exit=function() LOG("exit(0)") tasks={} coroutine.yield() end        
    local self=env.QuickApp
    QADir[dev.id]={QA=self,env=env}
    LOG("Loading  QA:%s - ID:%s",dev.name,dev.id)
    local k = coroutine.create(function()
        for _,f in ipairs(files) do                                     -- for every file we got, load it..
          if verbose then LOG("         ...%s",f.name) end
          local code = check(env.__TAG,load(f.content,f.fname,"t",env)) -- Load our QA code, check syntax errors
          check(env.__TAG,pcall(code))                                  -- Run the QA code, check runtime errors
        end
      end)
    procs[k]=QADir[dev.id] coroutine.resume(k) procs[k]=nil
    LOG("Starting QA:%s - ID:%s",dev.name,dev.id)
    runProc(QADir[dev.id],function() env.QuickApp:__init(dev) end)  -- Start QA by "creating instance"
  end

  local function run(QAs) 
    for _,qa in ipairs(QAs[1] and QAs or {QAs}) do installQA(qa) end -- Create QAs given
    -- Timer loop - core of emulator, run each coroutine until none left or all locked
    while(true) do                     -- Loop and execute tasks when their time is up
      local i,time,co = peek()         -- Look at first enabled/unlocked task in queue
      if time == nil then break end
      local now = clock()
      if time <= now then             -- Times up?
        deqeue(i)                     -- Remove task from queue
        xpresume(co)                  -- ...and run it, xpresume handles errors
        procs[co]=nil                 -- ...clear co->QA map
      else                            
        socket.sleep(time-now)        -- "sleep" until next timer in line is up
      end                             -- ...because nothing else is running, no timer could enter before in queue.
    end                                   
    if #tasks > 0 then LOG("All threads locked - terminating") 
    else LOG("No threads left - terminating") end
    QADir = {}                         -- Clear directory of QAs
  end
  return run
end -- emulator




builtins()                                  -- Define built-ins
loadModules(globalModules or {})            -- Load global modules
loadModules(gParams.globalModules or {})     -- Load optional user specified module into environment
local run = emulator()                      -- Setup emulator core - returns run function

print(fmt("---------------- Tiny QuickAppEmulator (TQAE) v%s -------------",version)) -- Get going...
if embedded then                -- Embedded call...
  local file = debug.getinfo(2)    -- Find out what file that called us
  if file and file.source then
    if not file.source:sub(1,1)=='@' then error("Can't locate file:"..file.source) end
    run({file=file.source:sub(2)}) -- Run that file
    os.exit()
  end
else main(run) end
