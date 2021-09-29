--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Polling /refreshStates events from HC3 and put them in queue that is used by emulator getting /refreshStates.
And also push events to Scene triggering mechanism

--]]
local EM,FB=...

-- The general idea is that we poll the HC3 /refreshStates and put events in a queue.
-- Then when emulated quickApps do http or api.get to retrieve events from the HC3 we give them events from our queue
-- ...and every one is happy.

local LOG,json = EM.LOG,FB.json

local socket = require("socket")
local http   = require("socket.http")
local https  = require("ssl.https") 
local ltn12  = require("ltn12")

local refreshListeners = {}

local function createRefreshStateQueue(size)
  local self = {}

  local function mkQueue(size)
    local queue,dump,pop = {}
    local tail,head = 301,301
    local function empty() return tail==head end
    local function filled() return head-tail >= size end
    local function push(e)
      if filled() then pop() end
      head=head+1
      local key = tostring(head)
      queue[key]=e
      --print(e,dump(),head,tail)
    end
    local function tailp() return tail end
    local function headp() return head end
    function pop()
      if empty() then return nil end
      tail=tail+1
      local key = tostring(tail)
      local v = queue[key]
      queue[key]=nil
      return v
    end
    local function peek(n) return queue[tostring(head-n)] end
    local function get(n) return queue[tostring(n)] end
    function dump()
      local res={}
      for i=0,size-1 do 
        local e=peek(i)
        if e then res[#res+1]=json.encode(e) end
      end
      return table.concat(res,",")
    end
    return { pop = pop, push = push, tailp=tailp, headp=headp, empty=empty, peek = peek, get=get, dump=dump }
  end

  self.eventQueue=mkQueue(size)       --- 1..QUEUELENGTH
  local eventQueue = self.eventQueue

  function self.addEvents(events)      -- {last=num,events={}}
    events = events[1] and events or {events}
    --print("ADD:"..json.encode(filter(events)))
    for _,f in ipairs(refreshListeners) do f(events) end
    local index = eventQueue.headp()
    eventQueue.push({last=index, events=events})
  end

  function self.getEvents(last)
    --print(eventQueue.dump())
    if eventQueue.empty() then return {last = last } end
    local res1,res2,i = {},{},0
    while true do
      local e = eventQueue.peek(i)     ----    5,6,7,8    6
      if e and e.last > last then
        res1[#res1+1]=e
      else break end
      i=i+1
    end
    if #res1==0 then return { last=last } end
    last = res1[1].last   ----  { 1, 2, 3, 4, 5}
    for j=1,#res1 do
      local es = res1[j].events
      if es then for k=1,#es do res2[#res2+1]=es[k] end end
    end
    --print("RET:"..json.encode(filter(res2)))
    return {last = last, events = res2}
  end
  self.dump = eventQueue.dump
  return self
end

local refreshStatesQueue = createRefreshStateQueue(200)
local lastRefresh = 0
local httpR = nil

local function pollOnce(cb)
  local resp = {}
  local req={ 
    method="GET",
    url = "http://"..EM.host.."/api/refreshStates?last=" .. lastRefresh.."&lang=en&rand=0.09580020181569104&logs=false",
    sink = ltn12.sink.table(resp),
    user=EM.user, password=EM.pwd,
    headers={}
  }
  req.headers["Accept"] = '*/*'
  req.headers["X-Fibaro-Version"] = 2
  local to
  if not EM.copas then 
    to = http.TIMEOUT
    http.TIMEOUT = 1 -- TIMEOUT == 0 doesn't work...
  end
  local r, c, h = httpR.request(req)       -- ToDo https
  if not EM.copas then http.TIMEOUT = to end
  if not r then return cb() end
  if c>=200 and c<300 then
    local states = resp[1] and json.decode(table.concat(resp))
    if states then
      lastRefresh=states.last
      if states.events and #states.events>0 then 
        refreshStatesQueue.addEvents(states.events) 
      end
    end
  end
  cb()
end

local function pollEvents(interval)
  LOG(EM.LOGALLW,"Polling HC3 /refreshStates")
  local INTERVAL = EM.refreshInterval or 0
  local cb
  local function poll() pollOnce(cb) end
  function cb()
    EM.systemTimer(poll,INTERVAL,"RefreshState")
  end
  poll(cb)
end

local function interceptHTTP(args,_) -- Intercept http calls to refreshStates to get events from our queue
  local last = args.url:match("127.0.0.1:11111/api/refreshStates.-last=(%d+)")
  if last then
    return json.encode(refreshStatesQueue.getEvents(tonumber(last))),200
  end
  return -42
end

function EM.addRefreshListener(fun) refreshListeners[#refreshListeners+1] = fun end

EM.addAPI("GET/refreshStates",function(_,_,_,_,_,prop) -- Intercep /api/refreshStates
    return refreshStatesQueue.getEvents(tonumber(prop.last) or 0)
  end)

EM.interceptHTTP = interceptHTTP
EM.EMEvents('start',function()
    httpR = EM.copas and EM.copas.http or http
    if EM.refreshStates then pollEvents(EM.refreshStates) end 
  end)

function EM.addRefreshEvent(event) refreshStatesQueue.addEvents(event) end