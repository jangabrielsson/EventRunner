--[[
%% properties
55 value
66 value
77 value
88 value
%% events
5 CentralSceneEvent
%% globals
counter
--]]

--[[
-- EventRunnerLight. Single scene instance framework
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_version = "1.0" 
osTime = os.time
osDate = os.date
if dofile then dofile("EventRunnerDebug.lua") end -- Support for running off-line on PC/Mac

---- Single scene instance, all fibaro triggers call main(sourceTrigger) ------------

local previousKey = nil -- Hey, these are lua variables keeping their values between scene triggers
local time = osTime() -- Hey, this lua variable keeps its value between scene triggers
local ref1,ref2 = nil,nil
local keyRep = 0
local lamps = {[55]={time=60},[66]={time=2*60,ref=nil},[77]={time=3*60,ref=nil}} -- Best to keep outside main()
function printf(...) fibaro:debug(string.format(...)) end

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

  if event.type == 'call' then event.f() end -- Generic event for posting function calls
end -- main()

------------------------ Framework, do not change ---------------------------  
-- Spawned scene instances post triggers back to starting scene instance ----
local _trigger = fibaro:getSourceTrigger()
local _type, _source = _trigger.type, _trigger
local _MAILBOX = "MAILBOX"..__fibaroSceneId 

if _type == 'other' and fibaro:args() then
  _trigger,_type = fibaro:args()[1],'remote'
end

function post(event, time) return setTimeout(function() main(event) end,(time or 0)*1000) end
function cancel(ref) if ref then clearTimeout(ref) end return nil end
function postRemote(sceneID,event) event._from=__fibaroSceneId; fibaro:startScene(sceneID,{json.encode(event)}) end

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

local function _poll()
  local l = fibaro:getGlobal(_MAILBOX)
  if l and l ~= "" and l:sub(1,3) ~= '<@>' then -- Something in the mailbox
    fibaro:setGlobal(_MAILBOX,"") -- clear mailbox
    post(json.decode(l)) -- and "post" it to our "main()" in new "thread"
  end
  setTimeout(_poll,250) -- check every 250ms
end

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