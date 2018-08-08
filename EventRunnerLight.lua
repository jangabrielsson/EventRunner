--[[
%% properties
55 value
%% events
%% globals
counter
--]]

--[[
-- EventRunnerLight. Single scene instance framework
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_HC2,_version = true,"1.0" 
if dofile then dofile("EventRunnerDebug.lua") end -- Support for running off-line on PC/Mac

---- Single scene instance, all fibaro triggers call main(sourceTrigger) ------------

local counter = 0

function main(sourceTrigger)
  local event = sourceTrigger

  if event.type == 'property' and event.deviceID == '55' then
    counter=counter+1
    fibaro:debug("Light 55 has changed states "..counter.." times")
  end

end -- main()

------------------------ Framework, do not change ---------------------------  
-- Spawned scene instances post triggers back to starting scene instance ----
local _trigger = fibaro:getSourceTrigger()
local _type, _source = _trigger.type, _trigger
local _MAILBOX = "MAILBOX"..__fibaroSceneId 

if _type == 'other' and fibaro:args() then
  _trigger,_type = fibaro:args()[1],'remote'
end

---------- Producer(s) - Handing over incoming triggers to consumer --------------------
if ({property=true,global=true,event=true,remote=true})[_type] then
  local event = type(_trigger) ~= 'string' and json.encode(_trigger) or _trigger
  local ticket = '<@>'..tostring(_source)..event
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
    main(json.decode(l) ) -- and "post" it to our "main()"
  end
  setTimeout(_poll,250) -- check every 250ms
end

if _type == 'autostart' or _type == 'other' then
  if _HC2 and fibaro:getGlobalModificationTime(_MAILBOX) == nil then
    api.post("/globalVariables/",{name=_MAILBOX})
  end 
  if _HC2 then fibaro:setGlobal(_MAILBOX,"") _poll() end -- start polling mailbox
  main(_trigger)
  if _OFFLINE then _System.runTimers() end
end

