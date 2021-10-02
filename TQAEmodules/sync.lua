--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Synchronous timers and IO support - simulates asynchronous calls with short repeated IO timeouts

--]]
local EM,FB=...

local LOG,Devices = EM.LOG,EM.Devices
local timers
local socket = require("socket") 

------------------------ Timers ----------------------------------------------------------
local function timerQueue() -- A sorted timer queue...
  local tq,pcounter,ptr = {},{}

  function tq.queue(v)    -- Insert timer
    v.tag = v.tag or "user"; pcounter[v.tag] = (pcounter[v.tag] or 0)+1
    if ptr == nil then ptr = v 
    elseif v.time < ptr.time then v.next=ptr; ptr.prev = v; ptr = v
    else
      local p = ptr
      while p.next and p.next.time <= v.time do p = p.next end   
      if p.next then p.next,v.next,p.next.prev,v.prev=v,p.next,v,p 
      else p.next,v.prev = v,p end
    end
    return v
  end

  function tq.dequeue(v) -- remove a timer
    assert(v.dead==nil,"Dead ptr")
    local n = v.next
    pcounter[v.tag]=pcounter[v.tag]-1
    if v==ptr then 
      ptr = v.next 
    else 
      if v.next then v.next.prev=v.prev end 
      v.prev.next = v.next 
    end
    v.dead = true
    v.next,v.prev=nil,nil
    return n
  end

  function tq.clearTimers(id) -- Clear all timers belonging to QA with id
    local p = ptr
    while p do if p.ctx and p.ctx.dev.id == id then p=tq.dequeue(p) else p=p.next end end
  end

  function tq.peek() -- Return next unlocked timer
    local p = ptr
    while p do if not tq.locked(p) then return p,p.time,p.co,p.ctx end p=p.next end 
  end

  function tq.lock(t,b) if t.ctx then t.ctx.env.LOCKED = b and t.co or nil end end
  function tq.locked(t) local l = t.ctx and t.ctx.env.LOCKED; return l and l~=t.co end
  function tq.tags(tag) return pcounter[tag] or 0 end
  function tq.reset() ptr=nil; for k,_ in pairs(pcounter) do pcounter[k]=0 end end
  function tq.get() return ptr end
  tq.milliStr = EM.milliStr
  function tq.dump() local p = ptr while(p) do LOG.sys("%s,%s,%s",p,tq.milliStr(p.time),p.tag) p=p.next end end
  return tq
end

local getContext,procs = EM.getContext,EM.procs
local function IDF() end

local function killTimers() timers.reset() end

local function checkForExit(cf,co,stat,res,...)
  local ctx = EM.procs[co]
  if not stat then 
    if type(res)=='table' then
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
  if EM.cfg.lateTimers then EM.timerCheckFun(t) end
  local stat,res = coroutine.resume(co)
  ctx.timers[t]=nil
  checkForExit(false,co,stat,res)
end

local function setTimeout(fun,ms,tag,ctx)
  ctx = ctx or procs[coroutine.running()]
  local co,v = coroutine.create(fun)
  v = EM.makeTimer(ms/1000+EM.clock(),co,ctx,tag,timerCall,{co,ctx}) 
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

timers = timerQueue()
EM.dumpTimers = timers.dump

local function start(fun) 
  local clock = EM.clock
  systemTimer(fun,0,"user")
  -- Timer loop - core of emulator, run each coroutine until none left or all locked
  while(timers.tags('user') > 0) do  -- Loop as long as there are user timers and execute them when their time is up
    local t,time = timers.peek()     -- Look at first enabled/unlocked task in queue
    if time == nil then break end
    local now = clock()
    if time <= now then              -- Times up?
      timers.dequeue(t)              -- Remove task from queue
      t.fun(t,t.args)                  -- ...and run it
    else                 
      socket.sleep(time-now)         -- "sleep" until next timer in line is up
    end                              -- ...because nothing else is running, no timer could enter before in queue.
  end                                   
  if timers.tags('user') > 0 then LOG.sys("All threads locked - terminating") 
  else LOG.sys("No threads left - terminating") end
  for k,D in pairs(Devices) do if D.save then EM.saveFQA(D) end Devices[k]=nil end -- Save and clear directory of Devices
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