--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Asynchronous timers and IO support - leverage copas framework

--]]

local EM,FB=...

local LOG,DEBUG,debugFlags = EM.LOG,EM.DEBUG,EM.debugFlags
EM.copas = dofile(EM.cfg.modPath.."copas.lua")

LOG.register("socketserver","Log (TCP)socketserver related events")

------------------------ Emulator core ----------------------------------------------------------
local procs,getContext = EM.procs,EM.getContext
local CO = coroutine
local systemTimer
local function IDF() end

local function yield(co)
--luacheck: push ignore 311
  local ctx,r=getContext(co) 
  ctx.lock.release(); 
  r={CO.yield(coroutine.running())}   
  ctx.lock.get() 
  return table.unpack(r)
--luacheck: pop
end

local function resume(co,...) 
--luacheck: push ignore 311
  local ctx,r=getContext(co)
  ctx.lock.release(); 
  r = {CO.resume(co,...)}
  ctx.lock.get() 
  return table.unpack(r)   
--luacheck: pop
end

local function cocreate(fun) 
  local co,ctx = CO.create(fun),getContext()
  procs[co]=ctx 
  return co 
end

local function fibaroSleep(ms) -- We lock all timers/coroutines except the one resuming the sleep for us
  EM.copas.sleep(ms/1000)
end

local function killTimers()
  local ctx = getContext()
  for v,_ in pairs(ctx.timers) do v.t:cancel() end
end

local function checkForExit(_,co,stat,res,...)
  local ctx = EM.procs[co]
  if not stat then 
    if type(res)=='table' and res.type then
      killTimers()
      if ctx.cont then ctx.cont() end
      --if cf then coroutine.yield(co) end
    else 
      EM.checkErr(ctx.env.__TAG,false,res)
    end
  end
  return stat,res,...
end

local function timerCall(_,args)
  local fun,ctx,v = table.unpack(args)
  ctx.lock.get() 
  if debugFlags.lateTimer then EM.timerCheckFun(v) end
  local stat,res = pcall(fun)
  ctx.lock.release() 
  ctx.timers[v]=nil
  checkForExit(nil,v.co,stat,res)
end

local function setTimeout(fun,ms,tag,ctx)
  ctx = ctx or procs[coroutine.running()]
  local params = {fun,ctx,nil}
  local t = EM.copas.timer.new({delay = ms/1000,recurring = false,callback = timerCall,params = params })
  local v = EM.makeTimer(ms/1000+EM.clock(),t.co,ctx,tag or "user",t,params)
  v.t,v.fun=v.fun,nil
--  local v={time=ms/1000+EM.osTime(),t=t,ctx=ctx,descr=tostring(t.co),tag=tag}
  params[3]=v
  ctx.timers[v] = true
  procs[t.co] = ctx
  return v
end

local function socketServer(args)
  local port,pat,conMsg,handler,i = args.port,args.pat,args.connectMsg,args.cmdHandler
  local server,msg = EM.socket.bind("*", port)
  assert(server,(msg or "").." ,port "..port)
  i, msg = server:getsockname()
  assert(i, msg)
  local copas = EM.copas
  handler = handler or function(str) return str.."\n" end 
  pat = pat or "*l"
  local function sockHandler(skt)
    DEBUG("socketserver","trace","SocketServer: Connected")
    if conMsg then copas.send(skt, conMsg.."\n") end
    while true do
      local data,err = copas.receive(skt,pat)
      if err == "closed" then
        DEBUG("socketserver","trace","SocketServer: Closed")
        return
      else
        DEBUG("socketserver","trace","SocketServer: Received '%s'",data or "")
        local res = handler(data)
        if res then copas.send(skt, res) end
      end
    end
  end
  copas.addserver(server,sockHandler)
  LOG.sys("Created Socket server at %s:%s",EM.IPAddress, port)
end

local sysCtx = {env={__TAG='SYSTEM'}, dev={}, timers={}, lock={get=IDF,release=IDF}}

function systemTimer(fun,ms,tag) return setTimeout(fun,ms,tag or "SYSTEM",sysCtx) end

local function clearTimeout(ref) ref.t:cancel() end

local function restartQA(D) killTimers() EM.runQA(D.id,D.cont) end

local function exit(status) 
  LOG.sys("exit(%s)",tostring(status or 0)) 
  error({type='exit'}) 
end

local function createLock(t) return EM.copas.lock.new(t or 6000000) end

local function start(fun) 
  pcall(EM.copas.loop,function() systemTimer(fun,0) end) 
end

EM.userCoroutines={yield=yield,resume=resume,create=cocreate,running=CO.running,status=CO.status}
EM.start = start
EM.setTimeout = setTimeout
EM.clearTimeout = clearTimeout
EM.systemTimer = systemTimer
EM.exit = exit
EM.restartQA = restartQA
EM.createLock = createLock
FB.__fibaroSleep = fibaroSleep
EM.http = EM.copas.http
EM.https = EM.copas.https
EM.checkForExit = checkForExit
EM.socketServer = socketServer