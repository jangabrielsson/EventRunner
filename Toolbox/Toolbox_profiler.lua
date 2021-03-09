--[[
  Toolbox profiler.
  
  Functions to profile functions in QA

  function QuickApp:profiler(args)                 -- Instruments code and return table of profiler function
  
  local prof = self:profiler(args)
  prof.report()
  prof.addQA(name)
  prof.addFun(name,fun)
  prof.start()
  prof.stop()
  prof.ignore()

--]]

Toolbox_Module = Toolbox_Module or {}
Toolbox_Module.profiler = {
  name = "Code profiler",
  author = "jan@gabrielsson.com",
  version = "0.1"
}

function Toolbox_Module.profiler.init(self)
  if Toolbox_Module.profiler.inited then return Toolbox_Module.profiler.inited end
  Toolbox_Module.profiler.inited = true

  function self:profiler(args)
    args = args or {}
    local self = quickApp
    local funs = {}
    local rev = {}
    local startT = os.clock()
    local sumT = 0
    local osclock,format = os.clock,string.format
    local unpack2 = table.unpack
    local trace,sort = self.trace,table.sort
    local enabled = args.enabled==nil or args.enabled==true or false

    local function ignore(args,p)
      if type(args)=='string' then args = {args} end
      for _,n in ipairs(args) do funs[n]=true end
      if not p then
        local funs1 = {}
        for n,v in pairs(funs) do if type(v)=='table' then funs1[n]=v end  end
        funs = funs1
      end
    end

    if args.ignore then ignore(args.ignore,true) end

    local function trapFun(name,f)
      local v = {time=0,count=0,org=f}
      funs[name]=v
      rev[tostring(f)]=true
      return function(...)
        if enabled then 
          local t0=osclock()
          local res = {f(...)}
          v.time=v.time+(osclock()-t0)
          v.count=v.count+1
          return unpack2(res)
        else return f(...) end
      end
    end

    local function exclude(name,f) return funs[name] or rev[tostring(f)] end

    local function addQA(name) 
      if not exclude(name,self) then
        self[name] = trapFun("QuickApp:"..name,self[name]) 
      end
    end

    local QAfuns = {
      ["trace"]=true,["debug"]=true,["error"]=true,["warning"]=true,
      ["getVariable"]=true,["setVariable"]=true,["updateView"]=true,
      ["updateProperty"]=true
    }

    local l = api.get("/quickApp/"..quickApp.id.."/files")  -- check source code, we can't inpect classes
    --l = {}
    for _,f in  ipairs(l  or {}) do
      local f0 = api.get("/quickApp/"..quickApp.id.."/files/"..f.name)
      f0.content:gsub(
        "function%s+QuickApp%s*:%s*([%w_]+)",
        function(n) QAfuns[n]=true end
      )
    end

    for n,_ in pairs(QAfuns) do addQA(n) end -- add found QA functions

    local function printf(...) print(format(...)) end

    local function scanFuns1(n,t)
      if type(t) ~= 'table' then
        if type(t)=='function' and not exclude(n,t) then
          _G[n]=trapFun(n,t)
        end
        return
      end
      for f,g in pairs(t) do
        if type(g) == "function" and not exclude(f,g) then
          --printf("T:"..f)
          t[f]=trapFun(n.."."..f,g)
        elseif type(g)=='table' then
          scanFuns1(n.."."..f,g)
        end
      end
    end

    local fibNative = {
      "__assert_type",
      "__fibaroSleep",
      "__fibaroUseAsyncHandler",
      "__fibaro_add_debug_message",
      "__fibaro_get_device",
      "__fibaro_get_device_property",
      "__fibaro_get_devices",
      "__fibaro_get_global_variable",
      "__fibaro_get_room",
      "__fibaro_get_scene",
      "__print",
      "__ternary"
    }

    local stdFibaro = {
      "api",
      "fibaro",
      "plugin",
      "logger",
    }

    local funFibaro = {
      "class",
      "clearInterval",
      "clearTimeout",
      "setInterval",
      "setTimeout",
      "getHierarchy",
    }

    local luaLibs = {
      "bit32",
      "string",
      "table",
      "os",
      "math",
    }

    local luaBuiltin = {
      "assert",
      "collectgarbage",
      "error",
      "ipairs",
      "pairs",
      "pcall",
      "tonumber",
      "tostring",
      "type",
      "unpack",
      "next",
      "xpcall",
      "utf8",
      "rawlen",
      "select",
      "print",
    }

    local function scanFunsTab(t)
      for _,f in ipairs(t) do
        scanFuns1(f,_G[f])
      end
    end

    scanFunsTab(stdFibaro) 
    scanFunsTab(funFibaro)
    scanFunsTab(fibNative)
    scanFunsTab(luaLibs)

    local seen = {}
    local function copy(t)
      local res = {}
      for f,g in pairs(t) do res[f]=g end
      return res
    end

    local function scanEnv(f,g,t,prefix)
      local name = prefix..f
      if type(g) == 'function' and not exclude(f,g) then
        --print("E:"..name)
        t[f]=trapFun(name,g)
      elseif type(g)=='table' and not (g[1] or seen[g]) then
        seen[g]=true
        for f,t in pairs(copy(g)) do 
          scanEnv(f,t,g,name..".") 
        end
      end
    end

    local excl = {modules=true,json=true,quickApp=true}
    seen[_G]=true
    for f,g in pairs(copy(_G)) do
      if not excl[f] then scanEnv(f,g,_G,"") end
    end
    json.encode = trapFun("json.encode",json.encode)
    json.decode = trapFun("json.decode",json.decode)

    local _net = net
    local httpInfo = {count = 0}
    net = { 
      HTTPClient = function(opts)
        local http =  _net.HTTPClient(opts)
        return {
          request = function(_,url,opts) 
            httpInfo.count = httpInfo.count+1
            return http:request(url,opts)
          end
        }
      end,
      TCPClient = _net.TCPClient
    }

    local function ptrace(str) trace(self,(str:gsub("(%s)","&nbsp;"))) end 
    local function trunc(str,n) return #str > n and str:sub(1,n-3)..".." or str end

    local function report()
      local res = {}
      for n,v in pairs(funs) do if v.time>0 then res[#res+1]={time=v.time,name=n,count=v.count} end end
      sort(res,function(a,b) return a.time > b.time end)
      local tt = nil
      if enabled then -- running
        tt = sumT+osclock()-startT
      else -- stopped
        tt = sumT
      end
      local sum = 0
      for _,e in ipairs(res) do sum=sum+e.time end
      ptrace(format("%-30s%-11s%-7s%-7s%-3s","Function","Time","Count","%time","%time(A)"))
      ptrace(string.rep("-",100))
      for _,e in ipairs(res) do
        ptrace(format("%-26s    %.06fs  %05d  %04.1f   %04.1f",trunc(e.name,27),e.time,e.count,e.time/sum*100,e.time/tt*100))
      end
      ptrace(format("httpRequests: %s",httpInfo.count))
      ptrace(format("Monitored accumulated time: %.06fs,  Absolute time: %.06fs",sum,tt))
    end

    local funs1 = {}
    for n,v in pairs(funs) do if type(v)=='table' then funs1[n]=v end  end
    funs = funs1

    local function start() 
      if not enabled then
        enabled = true; 
        startT=osclock() 
      end
    end

    local function stop() 
      if enabled then
        enabled = false;
        sumT = sumT+osclock()-startT
      end
    end

    if enabled then start() end

    local function addFun(name,fun) 
      if type(fun) == 'function' then
        return trapFun(name,g)
      elseif type(fun)=='table' and not fun[1] then
        for f,g in pairs(fun) do
          addFun(name.."."..f,g)
        end
      end
    end

    local p = { report = report, addQA = addQA, addFun=addFun, start=start, stop=stop, ignore=ignore }
    Toolbox_Module.profiler.inited = p
    return p
  end
end