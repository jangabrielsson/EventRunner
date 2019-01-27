--[[
%% properties
%% events
5 CentralSceneEvent
%% globals
--]]

--[[
-- EventRunnerLight. Single scene instance framework
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_version = "1.12" 
osTime = os.time
osDate = os.date
_debugFlags = { post=true,invoke=false,triggers=false,timers=false,fibaro=true,fibaroGet=false }
if dofile then dofile("EventRunnerDebug.lua") end -- Support for running off-line on PC/Mac
---- Single scene instance, all fibaro triggers call main(sourceTrigger) ------------

local previousKey = nil -- Hey, these are lua variables keeping their values between scene triggers
local time = osTime() -- Hey, this lua variable keeps its value between scene triggers
local ref1,ref2 = nil,nil
local keyRep = 0
local lamps = {[55]={time=60},[66]={time=2*60,ref=nil},[77]={time=3*60,ref=nil}} -- Best to keep outside main()
function printf(...) fibaro:debug(string.format(...)) end

local presenceScene = 133
local sensors = {[99]=true,[199]=true,[201]=true,[301]=true}
local breached, ref3 = true, nil
local lamps2 = {55,66,77}
local ref4 = nil

function main(sourceTrigger)
  local event = sourceTrigger

-- Example code triggering on Fibaro remote keys 1-2-3 within 2x3seconds
  if event.type == 'event' then
    local keyPressed = event.event.data.keyId
    if keyPressed == 1 then 
      previousKey=1
      time=osTime()
      printf("key 1 pressed at %s",osDate("%X"))
    elseif keyPressed == 2 and previousKey == 1 and osTime()-time <= 3 then
      previousKey = 2
      time=osTime()
      printf("key 2 pressed at %s",osDate("%X"))
    elseif keyPressed == 3 and previousKey == 2 and osTime()-time <= 3 then
      printf("Key 3 pressed at %s, Keys 1-2-3 pressed within 2x3sec",osDate("%X"))
    end
  end

  -- Test logic by posting key events in 3,5, and 7 seconds
  if event.type=='autostart' or event.type=='other' then
    post({type='event',event={data={keyId=1}}},3)
    post({type='event',event={data={keyId=2}}},5)
    post({type='event',event={data={keyId=3}}},7)
  end

  -- Example code triggering on Fibaro remote key 4 not pressed within 10 seconds
  if event.type == 'event' and event.event.data.keyId == 4 then
    cancel(ref1) -- Key pressed, cancel post/timer
    ref1 = post({type='Timeout'},10) -- and wait another 10s
    printf("Key 4 pressed, resetting timer")
  end
  if event.type == 'Timeout' then -- Post/timer timed out
    keyRep = keyRep+1
    printf("Key 4 not pressed within %s seconds!",keyRep*10)
    if keyRep < 5 then
      ref1 = post({type='Timeout'},10) -- wait another 10s
    end
  end
  if event.type=='autostart' or event.type=='other' then -- Start watching key 4 when starting scene
    ref1 = post({type='Timeout'},10)
  end

  -- Example code watching if lamps are turned on more than specified time, and then turn them off
  if event.type == 'property' and lamps[event.deviceID] then
    local id = event.deviceID
    local val = fibaro:getValue(id,'value') 
    if val>"0" then 
      cancel(lamps[id].ref) 
      printf("Watching lamp %s for %s seconds",id,lamps[id].time)
      lamps[id].ref = post({type='turnOff',deviceID=id},lamps[id].time)
    elseif val < "1" then
      printf("Stop watching lamp %s",id) -- Could easily add check for sensor too...
      lamps[id].ref = cancel(lamps[id].ref)
    end 
  end
  if event.type == 'turnOff' then
    local id = event.deviceID
    lamps[id].ref = nil
    fibaro:call(id,'turnOff')
  end
  if event.type=='autostart' or event.type=='other' then
    -- Start watching lamps at startup
    for id,_ in pairs(lamps) do post({type='property',deviceID=id},0) end 

    -- Test logic of lamps
    post({type='call', f=function() fibaro:call(55,'turnOn') end},60) -- turn on lamp 55 in 60 seconds
    post({type='call', f=function() fibaro:call(66,'turnOn') end},70) -- turn on lamp 66 in 70 seconds
    post({type='call', f=function() fibaro:call(77,'turnOn') end},80) -- turn on lamp 77 in 80 seconds
  end

  -- Turn on light 99 when sensor 88 is breached, and turn off 99 if sensor not breached again within 2 minutes
  if event.deviceID == 88 then
    if fibaro:getValue(88,'value') > '0' then
      if fibaro:getValue(99,'value') < '1' then fibaro:call(99,'turnOn') end
      ref2 = cancel(ref2) -- cancel timer
    else
      ref2 = post({type='call',f=function() printf("No movement for 2 minutes!") fibaro:call(99,'turnOff'); ref2=nil end},2*60)
    end
  end
  if event.type=='autostart' or event.type=='other' and not _OFFLINE then -- only works offline
    post({type='call',f=function() fibaro:call(88,'setValue','1') end},5*60)
    post({type='call',f=function() fibaro:call(88,'setValue','0') end},5*60+30)
  end


  if event.deviceID and sensors[event.deviceID] then
    local n = 0  -- count how many sensors are breached
    for id,_ in pairs(sensors) do if fibaro:getValue(id,'value') > '0' then n=n+1 end end
    if n > 0 and not breached then
      ref3 = cancel(ref3)
      --postRemote(presenceScene,{type='presence',state='stop'})
      post({type='presence',state='stop'})
    elseif n == 0 and breached then
      ref3 = post({type='away'},10*60) -- Assume away if no breach in 10 minutes
    end
    breached = n>0
  end

  if event.type == 'away' then
    --postRemote(presenceScene,{type='presence',state='start'})
    post({type='presence',state='start'})
  end

  if event.type == 'presence' and event.state=='start' then
    printf("Starting presence simulation")
    post({type='simulate'})
  end

  if event.type == 'simulate' then
    local id = lamps2[math.random(1,#lamps2)] -- choose a lamp
    fibaro:call(id,fibaro:getValue(id,'value') > '0' and 'turnOff' or 'turnOn') -- toggle light
    ref4 = post(event,math.random(5,15)*60) -- Run again in 5-15 minutes
  end

  if event.type=='presence' and event.state == 'stop' then
    printf("Stopping presence simulation")
    ref4 = cancel(ref4)
  end

  if _OFFLINE and event.type=='autostart' or event.type=='other' then -- only works offline
    post({type='call', f=function() fibaro:call(99,'setValue',"1") end},10)
    post({type='call', f=function() fibaro:call(99,'setValue',"0") end},20)
    post({type='call', f=function() fibaro:call(99,'setValue',"1") end},60*60)
  end

  local times = {
    {"09:30",function() fibaro:debug("Good morning!") end},
    {"13:10",function() fibaro:debug("Lunch!") end},
    {"17:00",function() fibaro:debug("Evening!") end}}


  if event.type == 'time' then
    fibaro:debug("It's time "..osDate("%X ")..event.time)
    -- carry out whatever actions...
    event.action()
    post(event,24*60*60) -- Re-post the event next day at the same time.
  end

  -- setUp initial posts of daily events
  if event.type == 'autostart' or event.type == 'other' then 
    local now = os.time()
    local t = osDate("*t")
    t.hour,t.min,t.sec = 0,0,0
    local midnight = osTime(t) 
    for _,ts in ipairs(times) do
      local h,m = ts[1]:match("(%d%d):(%d%d)")
      local tn = midnight+h*60*60+m*60
      if tn >= now then 
        post({type='time',time=ts[1], action=ts[2]},tn-now) -- Later today
      else
        post({type='time',time=ts[1], action=ts[2]},tn-now+24*60*60) -- Next day
      end
    end
  end


  if event.type == 'call' then event.f() end -- Generic event for posting function calls

end -- main()

------------------------ Framework, do not change ---------------------------  
-- Spawned scene instances post triggers back to starting scene instance ----
local _trigger = fibaro:getSourceTrigger()
local _type, _source = _trigger.type, _trigger
local _MAILBOX = "MAILBOX"..__fibaroSceneId 
function urldecode(str) return str:gsub('%%(%x%x)',function (x) return string.char(tonumber(x,16)) end) end
if _type == 'other' and fibaro:args() then
  _trigger,_type = urldecode(fibaro:args()[1]),'remote'
end
tojson = json.encode

function _midnight() local t=osDate("*t"); t.min,t.hour,t.sec=0,0,0; return osTime(t) end
function _now() local t=osDate("*t"); return 60*(t.min+60*t.hour)+t.sec end

function hm2sec(hmstr)
  local sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
  if sun and (sun == 'sunset' or sun == 'sunrise') then
    hmstr,offs = fibaro:getValue(1,sun.."Hour"), tonumber(offs) or 0
  end
  local h,m,s = hmstr:match("(%d+):(%d+):?(%d*)")
  return h*3600+m*60+(tonumber(s) or 0)+(offs or 0)*60
end

function toTime(time)
  if type(time) == 'number' then return time end
  local p = time:sub(1,2)
  if p == '+/' then return hm2sec(time:sub(3)) -- Plus now
  elseif p == 'n/' then
    local t1 = hm2sec(time:sub(3))      -- Next
    return t1 > _now() and t1 or t1+24*60*60
  elseif p == 't/' then return  hm2sec(time:sub(3))-_now()  -- Today
  else return hm2sec(time) end
end

if not Debug then function Debug(flag,message,...) if flag then fibaro:debug(string.format(message,...)) end end end

  function interceptFib(name,flag,spec,mf)
    local fun,fstr = fibaro[name],name:match("^get") and "fibaro:%s(%s%s%s) = %s" or "fibaro:%s(%s%s%s)"
    if spec then 
      fibaro[name] = function(obj,...) if _debugFlags[flag] then return spec(obj,fun,...) else return fun(obj,...) end end 
    else 
      fibaro[name] = function(obj,id,...)
        local id2,args = type(id) == 'number' and Util.reverseVar(id) or '"'..id..'"',{...}
        local status,res,r2 = pcall(function() return fun(obj,id,table.unpack(args)) end)
        if status and _debugFlags[flag] then
          fibaro:debug(string.format(fstr,name,id2,(#args>0 and "," or ""),json.encode(args):sub(2,-2),json.encode(res)))
        elseif not status then
          error(string.format("Err:fibaro:%s(%s%s%s), %s",name,id2,(#args>0 and "," or ""),json.encode(args):sub(2,-2),res),3)
        end
        if mf then return res,r2 else return res end
      end
    end
  end
  interceptFib("call","fibaro")
  interceptFib("setGlobal","fibaroSet")
  interceptFib("getGlobal","fibaroGet",nil,true)
  interceptFib("getGlobalValue","fibaroGet")
  interceptFib("get","fibaroGet",nil,true)
  interceptFib("getValue","fibaroGet")
  interceptFib("startScene","fibaro")
  -- function(args) return #args>0 and {Util.prettyEncode(args[1])} or args end)
  interceptFib("killScenes","fibaro")

function post(event, time) 
  if type(time)=='string' then time=toTime(time) else time = time or 0 end
  if _debugFlags.post then Debug(true,"Posting {type=%s,...} for %s",event.type,osDate("%X",time+osTime())) end
  return setTimeout(function() 
      if _OFFLINE and not _REMOTE then if _simFuns[event.type] then _simFuns[event.type](event)  end end
      main(event) end,time*1000) 
  end
  function cancel(ref) if ref then clearTimeout(ref) end return nil end
  function postRemote(sceneID,event) event._from=__fibaroSceneId; fibaro:startScene(sceneID,{urlencode(json.encode(event))}) end

---------- Producer(s) - Handing over incoming triggers to consumer --------------------
  if ({property=true,global=true,event=true,remote=true})[_type] then
    local event = type(_trigger) ~= 'string' and json.encode(_trigger) or _trigger
    local ticket = string.format('<@>%s%s',tostring(_source),event)
    repeat 
      while(fibaro:getGlobal(_MAILBOX) ~= "") do fibaro:sleep(100) end -- try again in 100ms
      fibaro:setGlobal(_MAILBOX,ticket) -- try to acquire lock
    until fibaro:getGlobal(_MAILBOX) == ticket -- got lock
    fibaro:setGlobal(_MAILBOX,event) -- write msg
    fibaro:abort() -- and exit
  end

---------- Consumer - Handing over incoming triggers to main() --------------------
  local function _poll()
    local l = fibaro:getGlobal(_MAILBOX)
    if l and l ~= "" and l:sub(1,3) ~= '<@>' then -- Something in the mailbox
      fibaro:setGlobal(_MAILBOX,"") -- clear mailbox
      Debug(_debugFlags.triggers,"Incoming event %s",l)
      post(json.decode(l)) -- and "post" it to our "main()" in new "thread"
    end
    setTimeout(_poll,250) -- check every 250ms
  end

---------- Startup --------------------
  if _type == 'autostart' or _type == 'other' then
    printf("Starting EventRunnerLite demo")
    if not _OFFLINE then 
      if not string.find(json.encode((api.get("/globalVariables/"))),"\"".._MAILBOX.."\"") then
        api.post("/globalVariables/",{name=_MAILBOX}) 
      end
      fibaro:setGlobal(_MAILBOX,"") 
      _poll()  -- start polling mailbox
      main(_trigger)
    else
      collectgarbage("collect") GC=collectgarbage("count")
      _System.runOffline(function() main(_trigger) end) 
    end
  end