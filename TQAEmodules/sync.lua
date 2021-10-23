--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Synchronous timers and IO support - simulates asynchronous calls with short repeated IO timeouts

--]]
local EM,FB=...

local LOG,Devices,debugFlags = EM.LOG,EM.Devices,EM.debugFlags
local timers
local socket = require("socket") 

local getContext,procs = EM.getContext,EM.procs
local function IDF() end

local function killTimers() timers.reset() end

local function checkForExit(cf,co,stat,res,...)
  local ctx = EM.procs[co]
  if not stat then 
    if type(res)=='table' and res.type then
      killTimers()
      if ctx.cont then ctx.cont() end
      if cf then coroutine.yield(co) end
    else 
      EM.checkErr(ctx.env.__TAG,false,res)
    end
  end
  return stat,res,...
end

local function timerCall(t,args)
  local co,ctx = table.unpack(args)
  if EM.cfg.lateTimer then EM.timerCheckFun(t) end
  local stat,res = coroutine.resume(co)
  ctx.timers[t]=nil
  checkForExit(false,co,stat,res)
end

local function setTimeout(fun,ms,tag,ctx)
  ctx = ctx or procs[coroutine.running()]
  local co = coroutine.create(fun)
  local v = EM.makeTimer(ms/1000+EM.clock(),co,ctx,tag,timerCall,{co,ctx}) 
  ctx.timers[v] = true
  procs[co] = ctx
  return timers.queue(v) 
end

local sysCtx = {env={__TAG='SYSTEM'},dev={}, timers={}}
local function systemTimer(fun,ms,tag) return setTimeout(fun,ms,tag or nil,sysCtx) end
local function clearTimeout(ref) timers.dequeue(ref) end

local function fibaroSleep(ms) -- We lock all timers/coroutines except the one resuming the sleep for us
  local r,co; 
  co,r = coroutine.running(),EM.setTimeout(function() timers.lock(r,false) coroutine.resume(co) end,ms) 
  timers.lock(r,true); 
  coroutine.yield(co)
end

local function exit(status) 
  LOG.sys("exit(%s)",status or 0) 
  error({type='exit'})
end

local function createLock() return { release=IDF, get=IDF } end

local function restartQA(D) timers.clearTimers(D.dev.id) EM.runQA(D.id,D.cont) coroutine.yield() end

local function start(fun) 
  timers = EM.utilities.timerQueue()
  local clock = EM.clock
  EM.running = true
  systemTimer(fun,0,"user")
  -- Timer loop - core of emulator, run each coroutine until none left or all locked
  while(EM.running) do  -- Loop as long as there are user timers and execute them when their time is up
    local t,time = timers.peek()     -- Look at first enabled/unlocked task in queue
    if time ~= nil then
      local now = clock()
      if time <= now then              -- Times up?
        timers.dequeue(t)              -- Remove task from queue
        t.fun(t,t.args)                  -- ...and run it
      else                 
        socket.sleep(time-now)         -- "sleep" until next timer in line is up
      end       
    else socket.sleep(0.01) end
  end                                   
  for k,_ in pairs(Devices) do Devices[k]=nil end -- Save and clear directory of Devices
end

local CO = coroutine
local function cocreate(fun,...)
  local co = CO.create(fun,...)
  EM.proces[co]=getContext()
  return co
end
local function resume(co,...)
  return checkForExit(true,co,coroutine.resume(co,...))
end

EM.userCoroutines = {resume=resume,yield=CO.yield,create=cocreate,status=CO.status,running=CO.running}
EM.start = start
EM.setTimeout = setTimeout
EM.clearTimeout = clearTimeout
EM.systemTimer = systemTimer
EM.exit = exit
EM.restartQA = restartQA
EM.createLock = createLock
FB.__fibaroSleep = fibaroSleep 
EM.checkForExit = checkForExit