--[[
%% properties
55 value
66 value
77 value
%% events
%% globals
counter



---------------- SourceTrigger call-backs --------------------
function handleSourceTrigger(type,event)

end

------------------- EventModel, Don't change --------------------
if true then
  local _trigger = fibaro:getSourceTrigger()
  local _type, _source = _trigger.type, _trigger
  local _MAILBOX = "MAILBOX"..__fibaroSceneId 

  if _type == 'other' and fibaro:args() then _trigger,_type = fibaro:args()[1],'remote' end

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
      handleSourceTrigger(json.decode(l))
    end
    setTimeout(_poll,250) -- check every 250ms
  end

  if fibaro:getGlobalModificationTime(_MAILBOX) == nil then -- Create if not exist
    api.post("/globalVariables/",{name=_MAILBOX})
  end 

  if (_type=='other' or type=='autostart') and fibaro:countScenes()== 1 then
    fibaro:setGlobal(_MAILBOX,"") -- clear mailbox
    _poll() -- start polling mailbox
    fibaro:debug("Starting")
    handleSourceTrigger(_trigger)
  else 
    fibaro:debug("Already running - exiting")
  end
end