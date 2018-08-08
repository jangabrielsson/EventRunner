--[[
%% properties
331 value
339 value
307 value
302 value
261 value
137 value
134 value
131 value
137 value
133 value
136 value
139 value
263 value
304 value
309 value
333 value
341 value
409 value
406 value
9 value
364 value
296 sceneActivation
409 sceneActivation
298 sceneActivation
350 sceneActivation
218 sceneActivation
224 sceneActivation
225 sceneActivation
%% globals
deviceTable
%% events
362 CentralSceneEvent
%% autostart
--]] 

-- Don't forget to add your triggers to the header!

--[[
-- ZEvent. Event based scheduler/device trigger handler
-- Copyright 2017 Jan Gabrielsson. All Rights Reserved.
-- Version 0.38
--
--  function main()                              -- where you add your code and eventhandlers
--  function Event:event(event_pattern,action)   -- declares an event handler, returns handler ref
--  function Event:post(event,time)              -- post an <event> at time <time>, returns post ref
--  function Event:cancel(<post ref>)            -- cancels an outstanding post
--  function Event:retract(<handler ref>)        -- removes an event handler
--  function Event:stop()                        -- stops calling additional event handlers for this event
--  function Event:loop(time,fun,n)              -- calls <fun> with interval <time>, optional <n>
--  function Event:schedule(time,event,test)     -- Posts <event> every interval <time> given that <test> is true
--  function Event:enable(<handler ref>,flag)    -- enables/disables handler, a bit more efficient then retract
--  function Event:remote(id,event)              -- sends <event> to scene. E.g. "fibaro:startScene(id,{event})"
--  function Event:ping(id)                      -- sends 'ping' event to scene (scene's automatically return 'pong' if alive)
--  function Event:pong(id,fun[,timeout,tAction])-- handle 'pong' from scene with optional timeout and timeouthandler

--  function Event:event(event_pattern,action,timeout,timeoutHandler)   
--  Short form for Event:event(event_pattern,action), Event:event({'not',event_pattern,timeout},timeoutHandler)
--
--  function Event:event({'and',E1,E2,...En},action)                   -- call action when E1,...En is true (in any order)
--  function Event:event({'seq',E1,[Delay1,]E2,[Delay2,]...En},action) -- call action when E1,..En happens in sequence with optional Delays inbetween
--  function Event:event({'not',E1,E2,...En,timeout},action)           -- call action when E1,...En haven't happened for timeout seconds
--  function Event:event({type='property',deviceID={I1,..In},...},action) -- Creates separate 'property' handlers for I1 to In

--]]

local SceneID      = 310      -- Set to ID of this scene, important if many scenes runs this code
_deviceTable = "deviceTable" -- Name of json struct with configuration data (i.e. "HomeTable")
local _speedtime   = 48      -- nil run the local clock in normal speed, otherwise stop after 48 hours simulated time. Only "offline"
local _debugLevel  = 2       -- 0,1,2,3 => None, Important, Medium, Max
local _debugEvents = false   -- true if incoming Fibaro events should be logged
local _debugPast   = false   -- Event:post logs attempts to schedule past events
_remote            = false   -- If true and running offline we use FibaroSceneAPI to call fibaro:() functions remote on HC2
local _deaf        = false   -- Do NOT listen to incoming events, a bit more efficient, saves a few CPU cycles, for 'servers'
local _BOXNAME     = 'ZE_EBOX'..SceneID -- Name of the global variable use to synchronize events, auto created by scene

-- Known issues 25/10/17: 
--   ...

local _HC2 = dofile == nil -- are we running on the HC2 or are we running "offline"...?

if not _HC2 then --- Stuff to import and setup if running offline
  dofile("ZEvent_utils_v1.lua") --  We need our own setTimeout and net.HTTPClient() and other fibaro funs when running offline
end

-------------- Here goes events definitions ---------------------

mainTitle = "Time and lights" -- Name of ZEvent functionalityfunction main()  local toTime, mapAnd = Util.toTime, Util.mapAnd  local eval,v = Script.setup()  local conf = json.decode(fibaro:getGlobalValue(_deviceTable))  local dev = conf.dev  Util.reverseMapDef(dev)  local d  = dev  local td = dev.toilet_down  local k  = dev.kitchen  local h  = dev.hall  local l  = dev.livingroom  local b  = dev.back  local g  = dev.game  local t  = dev.tim  local m  = dev.max  local bd = dev.bedroom   Event:event({type='global', name='deviceTable'},    function(env) -- restart if updated      local data = json.decode(fibaro:getGlobalValue("deviceTable"))      if not Util.equal(dev,conf.dev) then        Event:remote(conf.scenes.configurator.id,{type='startMeUp'})        fibaro:abort()      end    end)  local jsonRoomName = {}  for room,devs in pairs(dev) do    if type(devs) ~= 'table' then devs = {} end    for dev,id in pairs(devs) do      jsonRoomName[id] = room    end  end    sched = {    mon={{"07:00",'Morning'}, {"09:00",'Day'}, {"19:00",'Evening'}, {"23:00",'Night'}, {"24:00",'Midnight'}},    tue={{"07:00",'Morning'}, {"09:00",'Day'}, {"19:00",'Evening'}, {"23:00",'Night'}, {"24:00",'Midnight'}},    wed={{"07:00",'Morning'}, {"09:00",'Day'}, {"19:00",'Evening'}, {"23:00",'Night'}, {"24:00",'Midnight'}},    thu={{"07:00",'Morning'}, {"09:00",'Day'}, {"19:00",'Evening'}, {"23:00",'Night'}, {"24:00",'Midnight'}},    fri={{"07:00",'Morning'}, {"09:00",'Day'}, {"19:00",'Evening'}, {"24:00",'Night'}, {"24:00",'Midnight'}},    sat={{"08:00",'Morning'}, {"10:00",'Day'}, {"19:00",'Evening'}, {"24:00",'Night'}, {"24:00",'Midnight'}},    sun={{"08:00",'Morning'}, {"10:00",'Day'}, {"19:00",'Evening'}, {"23:00",'Night'}, {"24:00",'Midnight'}}  }  for _,e in ipairs({{'Sunset','max','on'},                {'Midnight','max','off'},                {'Sunset','tim','on'},                {'Midnight','tim','off'},                {'Sunset','bedroom','on'},                {'Night','bedroom','off'},                {'Sunset','game','on'},                {'Midnight','game','off'},                {'Sunset','livingroom','on'},                {'Midnight','livingroom','off'},                {'Sunset','kitchen','on'},                {'Sunrise','kitchen','off'},                {'Sunset','back','on'},                {'Sunrise','back','off'},                {'Sunset','hall','on'},                {'Sunrise','hall','off'}})    do       Event:event({type=e[1]},{'post',{type=e[2],value=e[3]}})     end                function now() return osDate("%H:%M") end  function past(t) return toTime(t) < osTime() end   Event:event({type='startup'},    function(env)      Event:schedule("n00:10",{type='daily_init'}) -- Run daily setup 10min past midnight      if now() > "00:10" then Event:post({type='daily_init'}) end -- Run at startup    end)  Event:event({type='daily_init'},     function(env)      Log(LOG_COLOR,"Sunrise at %s",fibaro:getValue(1,"sunriseHour"))      Log(LOG_COLOR,"Sunset at %s",fibaro:getValue(1,"sunsetHour"))      Event:post({type='Sunrise'},"Sunrise")      Event:post({type='Sunset'},"Sunset")      local d = {'sun','mon','tue','wed','thu','fri','sat'}      local t = os.date("*t",osTime())      local ne,evs = nil,sched[d[t.wday]]      table.sort(evs,function(a,b) return a[1] < b[1] end)      for _,e in ipairs(evs) do        if past(e[1]) then ne = e[2] else Event:post({type=e[2]},e[1]) end      end      if ne then Event:post({type=ne}) end --latest 'past' event posted - i.e. to set time of day    end)  local motions = fibaro:getDevicesId({name='Movement'})  local lights = fibaro:getDevicesId({interfaces={'light'}})  local luxs = fibaro:getDevicesId({name='Lux'})  rooms = {} -- {name=<name>, dark=true/false, motion=true/false, last = osTime()}  for k,id in ipairs(motions) do     local rid = jsonRoomName[id]    rooms[rid] = rooms[rid] or {name = rid, dark=false, motion=false, lux = {}, last = 0}    local v,t = fibaro:get(id,'value')    if v > '0' then rooms[rid].motion = true; rooms[rid].last = t end  end  for k,id in ipairs(luxs) do     local rid = jsonRoomName[id]; rooms[rid] = rooms[rid] or {name = rid, lux={}, dark=false, motion=false, last = 0}    rooms[rid].lux[#rooms[rid].lux+1] = id  end    function updateLux(rid)    local d = 0    for k,id in ipairs(rooms[rid].lux) do      d = d+fibaro:getValue(id,'value')    end    rooms[rid].dark = d/#rooms[rid].lux <= 40    return rooms[rid].dark  end    for rid,room in pairs(rooms) do -- initialize    updateLux(rid)  end    Event:event({type='property', deviceID=luxs, value='$val'},    function(env)       local id,rid = env.event.deviceID, jsonRoomName[env.event.deviceID]      local dark = rooms[rid].dark      if updateLux(rid) ~= dark then        Log(LOG_COLOR,"Updating darkness in %s to %s",rooms[rid].name,not dark)        Event:post({type='Darkness', room=rid, dark=not dark})      end    end)  Event:event({type='property', deviceID=motions, value='$val', last = '$last'},    function(env)       local rid = fibaro:getRoomID(env.event.deviceID)      rooms[rid].motion = tostring(env.p.val) > '0'      rooms[rid].last = env.p.last    end)  Event:event({type='Darkness', room='$name', dark='$dark'},    function(env)      if Util.between("15:00","Sunset") then        Event:post({type=env.p.name, value=env.p.dark and 'on' or 'off'})      end    end)    -- Bathroom downstairs  -- check if someone is in bathroom (in practice an unsolvable problem)  local tdDoorClosed = 0,0  local tdPresence = false  Event:event(E.breached(td.movement),    function(env)       if F.isOff(td.lamp_roof) then        F.on(td.lamp_roof)        F.log("Turning on bathroom light")      end      if F.isSafe(td.door) and not tdPresence then         F.log("Bathroom presence detected")        tdPresence = true       end    end)  Event:event({'not',E.breached(td.movement),"+00:03"},    function(env)       if F.isSafe(td.movement) and (not tdPresence) and F.isOn(td.lamp_roof) then         F.log("Turning off bathroom light")        F.off(td.lamp_roof)       end    end)  Event:event(E.breached(td.door), function(env) tdPresence = false if tdPresence then F.log("Bathroom presence cleared") end end)  Event:event(E.safe(td.door), function(env) tdDoorClosed = osTime() end)  Event:event(E.safe(td.movement),     function(env)       if (not tdPresence) and F.isSafe(td.door) and osTime()-tdDoorClosed >= 30 then tdPresence = true  F.log("Bathroom presence detected") end     end)-- Kitchen  if true then    local t1,t2 = Cron:new("* 8-12 * * mon-fri"),Cron:new("* 24-4 * * *")    Event:event({'not',E.breached(k.movement),"+00:10"},      function(env)        if F.isSafe(k.movement) and (t1() or t2()) and F.isOn(k.lamp_table) then           F.off(k.lamp_table)          F.log("Turning off kitchen lamp after 10 min inactivity")        end      end)    Event:event({'not',E.breached(k.movement),E.breached(l.movement),E.breached(h.movement),"+00:05"},      function(env)        if F.isSafe(k.movement,l.movement,h.movement) and -- No sensor is currently breached        (t1() or t2()) and                                -- and within the time spane        F.isOn(k.lamp_stove,k.lamp_sink,h.lamp_hall) then -- and some lamp is on          F.off(k.lamp_stove,k.lamp_sink,h.lamp_hall)           F.log("Turning off kitchen spots after 5 min inactivity")        end      end)  end-- Kitchen  Event:event({type='kitchen', value='on'},{':',{'press',k.sink_led,1},{'log',"Turn on kitchen sink light"}})  Event:event({type='kitchen', value='off'},{':',{'press',k.sink_led,2},{'log',"Turn off kitchen sink light"}})  Event:event({type='kitchen', value='on'},{':',{'on',k.lamp_table},{'log',"Evening, turn on kitchen table light"}})-- Living room  Event:event({type='livingroom', value='on'},{':',{'on',l.lamp_window},{'log',"Turn on livingroom light"}})  Event:event({type='livingroom', value='off'},{':',{'off',l.lamp_window},{'log',"Turn off livingroom light"}})  --  Event:post({type='property', deviceID=l.lux, value=30, _sim=true},"16:30")--  Event:post({type='property', deviceID=l.lux, value=100, _sim=true},"17:00")--  Event:post({type='property', deviceID=l.lux, value=40, _sim=true},"17:30")     -- Front  Event:event({type='hall', value='on'},{':',{'on',h.lamp_entrance},{'log',"Turn on lights entr."}})  Event:event({type='hall', value='off'},{':',{'off',h.lamp_entrance},{'log',"Turn off lights entr."}})-- Back  Event:event({type='back', value='on'},{':',{'on',b.lamp},{'log',"Turn on lights back"}})  Event:event({type='back', value='off'},{':',{'off',b.lamp},{'log',"Turn off lights back"}})-- Game room  Event:event({type='game', value='on'},{':',{'on',g.lamp_window},{'log',"Turn on gaming room light"}})  Event:event({type='game', value='off'},{':',{'off',g.lamp_window},{'log',"Turn off gaming room light"}})-- Tim  Event:event({type='tim', value='on'},{':',{'on',t.bed_led,t.lamp_window},{'log',"Turn on lights for Tim"}})  Event:event({type='tim', value='off'},{':',{'off',t.bed_led,t.lamp_window},{'log',"Turn off lights for Tim"}})-- Max  Event:event({type='max', value='on'},{':',{'on',m.lamp_window},{'log',"Turn on lights for Max"}})  Event:event({type='max', value='off'},{':',{'off',m.lamp_window},{'log',"Turn off lights for Max"}})-- Bedroom  Event:event({type='bedroom', value='on'},{':',{'on',bd.lamp_window,bd.lamp_table,bd.bed_led},{'log',"Turn on bedroom light"}})  Event:event({type='bedroom', value='off'},{':',{'off',bd.lamp_window,bd.lamp_table,bd.bed_led},{'log',"Turn off bedroom light"}})---  Event:event({type='Evening'},function(env) end)-- Power watcher  local powerIDs = {d.kitchen.dish_washer, d.hall.washing_machine, d.hall.dryer}  Event:event({type='property', deviceID=powerIDs},    {'post', {type='power', id=v('$env.event,deviceID'), power={'power',v('$env.event,deviceID')}}})  for _,p in   ipairs({{id=d.kitchen.dish_washer,e='dishwasher',l='Dishwasher started',max="3.0",min="1.0"},      {id=d.kitchen.dish_washer,e='washing',l='Washingmachine started',max="3.0",min="1.0"},      {id=d.kitchen.dish_washer,e='dryer',l='Dryer started',max="3.0",min="1.0"},})  do    local state = false    Event:event({type='power', id=p.id, power="$p>"..p.max},function(env)         if not state then state=true Event:post({type=p.e, state='on'}) F.log(p.l) end      end)    Event:event({type='power', id=p.id, power="$p<"..p.min},function(env)         if state then state=false Event:post({type=p.e, state='off'}) F.log(p.l) end       end)  end------------ Triggers ---------------------   local S1 = {click = "16", double = "14", tripple = "15", hold = "12", release = "13"}  local S2 = {click = "26", double = "24", tripple = "25", hold = "22", release = "23"}  Event:event({type='property', propertyName='value', deviceID=137},function(env) end)  Event:event({type='property', propertyName='value', deviceID=261},function(env) end)  local sceneActivationsIDs = {    d.kitchen.lamp_table,    d.hall.lamp_entrance,    d.bedroom.lamp_roof,    d.tim.lamp_roof,    d.max.lamp_roof,    d.game.lamp_roof,    d.livingroom.lamp_roof_holk}  F.log("IDS"..json.encode(sceneActivationsIDs))    Event:event({type='property', deviceID=sceneActivationsIDs, propertyName='sceneActivation'},    {'post',{type='scene', id=v('$env.event.deviceID'), scene={'scene',v('$env.event.deviceID')}, _sh=true}})  Event:event({type='scene', id=l.lamp_roof_holk, scene=S2.click},    {':',{'toggle',l.lamp_roof_sofa},{'log',"Toggling lamp downstairs"}})  Event:event({type='scene', id=bd.lamp_roof, scene=S2.click},     {':',{'toggle',bd.lamp_window, bd.bed_led},{'log',"Toggling bedroom lights"}})  Event:event({type='scene', id=t.lamp_roof, scene=S2.click},    {':',{'toggle',t.bed_led},{'log',"Toggling Tim bedroom lights"}})  Event:event({type='scene', id=t.lamp_roof, scene=S2.double},    {':',{'toggle',t.lamp_window},{'log',"Toggling Tim window lights"}})  Event:event({type='scene', id=m.lamp_roof, scene=S2.click},    {':',{'toggle',m.lamp_window},{'log',"Toggling Max bedroom lights"}})  Event:event({type='scene', id=g.lamp_roof, scene=S2.click},     {':',{'toggle',g.lamp_window},{'log',"Toggling Gameroom window lights"}})  --Event:event({type='scene', id=h.lamp_entrance, scene=S2.click},{'log',"Hembelysning"})  --Event:event({type='scene', id=h.lamp_entrance, scene=S2.double},{'log',"All lights on"})  Event:event({type='scene', id=k.lamp_table, scene=S2.click},    {':',{'if',{'==',{'label',k.sonos,'lblState'},"Playing"},{'press',k.sonos,8},{'press',k.sonos,7}},      {'log',"Toggling Sonos %s",{'label',k.sonos,'lblState'}}})  Event:event({type='property', deviceID=l.lamp_window},    {':',      {'if',{'isOn',l.lamp_window},        {':',{'press',l.lamp_tv,1},{'press',l.lamp_globe,1}},        {':',{'press',l.lamp_tv,2},{'press',l.lamp_globe,2}}},      {'log',"Toggling livingroom window lights"}})  Event:post({type='startup'})endF = {} -- Convenience functions...F.on = function(...) return Util.mapF(function(id) fibaro:call(id,'turnOn') end, {...}) endF.off = function(...) return Util.mapF(function(id) fibaro:call(id,'turnOff') end, {...}) endF.isOn = function(...) return Util.mapOr(function(id) return fibaro:getValue(id,'value') > '0' end, {...}) end F.isOff = function(...) return Util.mapAnd(function(id) return fibaro:getValue(id,'value') < '1' end, {...}) end F.isBreaced = function(...) return F.isOn(...) endF.isSafe = function(...) return F.isOff(...) endF.press = function(id,btn) fibaro:call(id,'pressButton', btn) endF.label = function(id,lbl) return fibaro:get(id,_format("ui.%s.value",lbl)) endF.log = function(msg,...) Log(LOG_COLOR,msg,...) return true endE = {}E.off = function(id) return {type='property', deviceID=id, propertyName='value', value='$value<1'} endE.on = function(id) return {type='property', deviceID=id, propertyName='value', value='$value>='} endE.safe = function(id) return {type='property', deviceID=id, propertyName='value', value='$value<1'} endE.breached = function(id) return {type='property', deviceID=id, propertyName='value', value='$value>0'} endfunction mkSensor(id,reset) -- for testing  local sensor = {}  local timer = nil  sensor.breach = function()    if timer then      clearTimeout(timer)      F.log("BREACH extend:"..id)    else      F.log("BREACH:"..id)      Event:post({type='property', deviceID=id, value='1', _sim=true})    end    timer = setTimeout(function()        Event:post({type='property', deviceID=id, value='0', _sim=true})        end,1000*reset)  end  return sensorend

----------------- Support functions -- 0.38 --------------------
if not _System then _System = {} end
Util = {}

if true then
  WELCOMECOLOR = "orange"
  DEBUGCOLOR = "white"
  SYSTEMCOLOR = "Cyan"
  LOGCOLOR = "green"
  ERRORCOLOR = "Tomato"

  _format = string.format
  function __assert(test, msg, ...) if not test then error(_format(msg,...)) end end

  osTime = os.time  -- Use these instead of os.time and os.clock to make _speedtime work
  osClock = os.clock
  function osDate(f,t) t = t or osTime() return os.date(f,t) end

  if (not _HC2) and _speedtime then
    local _startTime = os.time()
    local _maxTime = _startTime + _speedtime*60*60
    local _sleep = 0
    function osTime()
      local t = _startTime+_sleep+(os.time()-_startTime)
      if t > _maxTime then 
        print(_format("Max time, %s hours, reached, exiting",_speedtime))
        os.exit() 
      end
      return t
    end
    function fibaro:sleep(n) _sleep = _sleep + math.floor(n/1000) end
    function osClock() return osTime() end
  end

  function Log(color, message,...)
    message = _format(message,...)
    if not _HC2 then fibaro:debug(_format("%s %s",os.date("%c",osTime()),message))
    else fibaro:debug(_format('<span style="color:%s;">%s</span>',color, message)) end
  end

  function Debug(level,message,...)
    if (_debugLevel >= level) then
      message = _format(message,...)
      if not _HC2 then fibaro:debug(_format("%s %s",os.date("%c",osTime()),message))
      else fibaro:debug(_format('<span style="color:%s;">%s</span><br>', DEBUGCOLOR, message)) end
    end
  end

  function Error(message,...)
    message = _format(message,...)
    if not _HC2 then fibaro:debug(_format("%s %s",os.date("%c",osTime()),message))
    else fibaro:debug(_format('<span style="color:%s;">%s</span><br>', ERRORCOLOR, message)) end
  end

  local function delay(secs) return osTime()+secs end
  local function sunset() return fibaro:getValue(1,'sunsetHour') end
  local function sunrise() return fibaro:getValue(1,'sunriseHour') end

  local function hm2sec(hmstr)
    if type(hmstr) == 'number' then return hmstr end
    local offs = 0
    if hmstr:sub(1,6) == 'Sunset' then 
      offs = tonumber(hmstr:match("Sunset([+-]?%d*)")) or 0
      hmstr = sunset() 
    elseif hmstr:sub(1,7) == 'Sunrise' then 
      hmstr = sunrise() 
      offs = tonumber(hmstr:match("Sunrise([+-]?%d*)")) or 0
    end
    local h,m,s = hmstr:match("(%d+):(%d+):?(%d*)")
    return h*3600+m*60+(tonumber(s) or 0)+offs
  end

  local function sec2hmStr(hms)
    local h,m,s = math.floor(hms/3600), math.floor((hms % 3600)/60), hms % 60 
    return string.format("%02d:%02d:%02d",h,m,s)
  end

  local function today(hms)
    if type(hms) == 'string' then hms = hm2sec(hms) end
    local d = os.date("*t",osTime())
    d.hour,d.min,d.sec = math.floor(hms/3600), math.floor((hms % 3600)/60), hms % 60 
    return os.time(d)
  end

  local function bracket(t1,t2,t3) 
    local r1,r2,r3 = hm2sec(t1), hm2sec(t2), hm2sec(t3)
    if r2 < r1 then return t1 
    elseif r2 > r3 then return t3
    else return t2 end
  end

  function upcoming(hmstr) 
    local t = type(hmstr) == 'string' and hm2sec(hmstr) or hmstr
    local t1,t2 = today(t), osTime()
    return t1 > t2 and t1 or t1+24*60*60
  end

  local function toTime(t)
    if type(t) ~= 'string' then return t end
    local s = t:sub(1,1)
    if s == '+' then return hm2sec(t:sub(2))+osTime()
    elseif s == 'n' then return upcoming(t:sub(2))
    else return today(hm2sec(t)) end
  end

  local function between(t1,t2)
    local t = osTime()
    return today(hm2sec(t1)) < t and t < today(hm2sec(t2))
  end

  local function between2(str) -- between("17:23-20:10 mon,tue,wed,thu,fri,sat,sun")
    local dayMap = {"sun","mon","tue","wed","thu","fri","sat"};
    local t = os.date("*t",osTime());
    if not (string.find(str,dayMap[t.wday])) then return false end
    local h1,m1,h2,m2 = str:match("(%d+):(%d+)-(%d+):(%d+)")
    m1, m2, t = h1*60+m1, h2*60+m2, t.hour*60+t.min
    if (m1 <= m2) then
      return m1 <= t and t <= m2 -- 01:00-02:00
    else
      return m1 <= t or t <= m2 -- 23:00-21:00
    end
  end

  local function mapF(f,l,s) s=s or 1; for i=s,#l do f(l[i]) end return true end 
  local function mapP(f,l,s) s=s or 1;  local res = true for i=s,#l do res = f(l[i]) end return res end 
  local function mapN(f,l,s) s = s or 1; local res = {} for i=s,#l do res[#res+1] = f(l[i]) end return res end 
  local function mapN2(fun,seq) local res = {} for k,v in pairs(seq) do res[k]=fun(v) end return res end 
  local function mapR(f,l,a,s) s = s or 1; for i=s,#l do a = f(l[i],a) end return a end 
  local function mapAnd(f,l,s) s = s or 1; local e=false for i=s,#l do e = f(l[i]) if not e then return false end end return e end 
  local function mapOr(f,l,s) s = s or 1; for i=s,#l do local e = f(l[i]) if e then return e end end return false end

  function Util.equal(e1,e2)
    local t1,t2 = type(e1),type(e2)
    if t1 ~= t2 then return false end
    if t1 ~= 'table' and t2 ~= 'table' then return e1 == e2 end
    for k1,v1 in pairs(e1) do
      local v2 = e2[k1]
      if v2 == nil or not Util.equal(v1,v2) then return false end
    end
    for k2,v2 in pairs(e2) do
      local v1 = e1[k2]
      if v1 == nil or not Util.equal(v1,v2) then return false end
    end
    return true
  end

  function Util.createGlobal(var, value, ev)
    local http = net.HTTPClient()
    http:request("http://127.0.0.1:11111/api/globalVariables", {
        options = {method='POST',headers={},data=_format('{"name":"%s","value":"%s"}',var,value),timeout = 2000},
        success = function(status)
          --Debug(4,status.status)
          if status.status == 200 or status.status == 201 then 
            Debug(1,"Global %s created",var) 
            if ev then Event:post(ev) end
          end
        end,
        error = function(err) error("Err creating global:".. err) end
      })
  end

  Util._reverseVarTable = {}

  function Util.reverseMapDef(table) Util._reverseMap({},table) end

  function Util._reverseMap(path,value)
    if type(value) == 'number' then
      Util._reverseVarTable[tostring(value)] = table.concat(path,".")
    elseif type(value) == 'table' and not value[1] then
      for k,v in pairs(value) do
        table.insert(path,k) 
        Util._reverseMap(path,v)
        table.remove(path) 
      end
    end
  end

  function Util.reverseVar(id)
    local r = Util._reverseVarTable[tostring(id)]
    return r or id
  end

  local gKeys = {type=1,deviceID=2,value=3,val=4,key=5,arg=6,event=7,events=8,msg=9,res=10}
  local gKeysNext = 10
  local function keyCompare(a,b)
    local av,bv = gKeys[a], gKeys[b]
    if av == nil then gKeysNext = gKeysNext+1 gKeys[a] = gKeysNext av = gKeysNext end
    if bv == nil then gKeysNext = gKeysNext+1 gKeys[b] = gKeysNext bv = gKeysNext end
    return av < bv
  end
    
  function Util.prettyJson(e) -- our own json encode, as we don't have 'pure' json structs
    local res,t = {}
    local function pretty(e)
      local t = type(e)
      if t == 'string' then res[#res+1] = '"' res[#res+1] = e res[#res+1] = '"' 
      elseif t == 'number' then res[#res+1] = e
      elseif t == 'boolean' then res[#res+1] = tostring(e)
      elseif t == 'function' then res[#res+1] = tostring(e) -- kill functions for now...
      elseif t == 'table' then
        if e[1] then
          res[#res+1] = "[" pretty(e[1])
          for i=2,#e do res[#res+1] = "," pretty(e[i]) end
          res[#res+1] = "]"
        else
          if e._var_  then res[#res+1] = _format('"%s"',e._str) return end
          local k = {} for key,_ in pairs(e) do k[#k+1] = key end table.sort(k,keyCompare)
          if #k == 0 then res[#res+1] = "[]" return end
          res[#res+1] = '{'
          res[#res+1] = '"' res[#res+1] = k[1] res[#res+1] = '":' t = k[1] pretty(e[t])
          for i=2,#k do res[#res+1] = ',"' res[#res+1] = k[i] res[#res+1] = '":' t = k[i] pretty(e[t]) end
          res[#res+1] = '}'
        end
      elseif e == nil then
        return "nil"
      else
        error("Bad json expr:"..tostring(e))
      end
    end
    pretty(e)
    return table.concat(res)
  end

  Util.toTime = toTime -- Export local functions
  Util.mapAnd = mapAnd
  Util.mapOr = mapOr
  Util.mapF = mapF
  Util.mapN = mapN
  Util.delay = delay
  Util.sunset = sunset
  Util.sunrise = sunrise
  Util.sec2hmStr = sec2hmStr 
  Util.between = between
  Util.between2 = between2

end
--------------------- Script support --------------------
Script = { 
-- progn, {':',{'on',67},{'off',77}} -> {'on',67} {'off',77} 
-- apply, {'!','on',{'%',{66,77}}} -> {'on',66,77}
-- table, {'#',{a={'+',8,8},b={'isOn',77}}} -> {a=16,b=false}
  _funs = {},
  _vars = {},
  _special = {['if'] = true, ['and'] = true, ['or'] = true, var = true, set = true, [':'] = true, ['!'] = true, ['%'] = true, ['#'] = true}
}

local mapAnd = Util.mapAnd
local mapOr = Util.mapOr
local mapF = Util.mapF

function Script.eval(expr,env)
  if Script._funs[1] == nil then
    Script.eval = Script._eval
    Script.setup()
    return Script.eval(expr,env)
  else error("Bad Script setup") end
end

function Script.setup()
  local eval,funs,format = Script.eval, Script._funs, string.format
  if funs[1] then return Script.eval,Script.v end -- Already setup
  funs['on'] = function(e,env) return mapF(function(id) fibaro:call(id,'turnOn') end, e,1) end
  funs['isOn'] = function(e,env) return mapOr(function(id) return fibaro:getValue(id,'value') > '0' end, e,1) end  
  funs['off'] = function(e,env) return mapF(function(id) fibaro:call(id,'turnOff') end, e, 1) end
  funs['isOff'] = function(e,env) return mapAnd(function(id) return fibaro:getValue(id,'value') < '1' end, e,1) end  
  funs['if'] = function(e,env) if eval(e[2],env) then return eval(e[3],env) elseif e[4] then return eval(e[4],env) else return false end end
  funs['and'] = function(e,env) return mapAnd(function(id) return eval(id,env)  end, e,2) end  
  funs['or'] = function(e,env) return mapOr(function(id) return eval(id,env) end, e,2) end  
  funs['toggle'] = function(e,env) 
    local t = fibaro:getValue(e[1],'value')>'0' and 'turnOff' or 'turnOn'
    return mapF(function(id) fibaro:call(id,t) end, e, 1)
  end
  funs['log'] = function(e,env) Log(LOGCOLOR,e[1],select(2,table.unpack(e))) return true end 
  funs['safe'] = funs['isOff'] 
  funs['breached'] = funs['isOn'] 
  funs['press'] = function(e,env) fibaro:call(e[1],'pressButton', e[2]) end
  funs['label'] = function(e,env) return fibaro:get(e[1],format("ui.%s.value",e[2])) end
  funs['=='] = function(e,env) return e[1] == e[2] end
  funs['~='] = function(e,env) return e[1] ~= e[2] end
  funs['+'] = function(e,env) return e[1] + e[2] end
  funs['power'] = function(e,env) return fibaro:getValue(e[1],'power') end
  funs['scene'] = function(e,env) return fibaro:getValue(e[1],'sceneActivation') end
  funs['var'] = function(e,env) return Script._getVar(e[2]) end
  funs['set'] = function(e,env) return Script._setVar(e[2][2],eval(e[3],env)) end
  funs['post'] = function(e,env) return Event:post(e[1],e[2]) end
  funs[':'] = function(e,env) local r for i=2,#e do r = eval(e[i],env) end return r end
  funs['%'] = function(e,env) return e[2] end
  funs['!'] = function(e,env)
    local fun,args = eval(e[2],env), eval(e[3],env)
    if not funs[fun] then error("Bad !call:"..json.encode(e)) end
    return funs[fun](args,env)
  end
  funs['#'] = function(e,env)
    local r = {}
    for k,v in pairs(e[2]) do r[k] = eval(v,env) end
    return r
  end
  return Script.eval,Script.v
end

function Script._eval(expr,env)
  local eval = Script.eval
  if type(expr) == 'function' then return expr(env)
  elseif type(expr) == 'table' then
    local e = expr[1]
    if type(e) == 'string' and Script._funs[e] then
      if Script._special[e] then -- specials gets their args unevaluated
        return Script._funs[e](expr,env)
      else
        local args = {}
        for i=2,#expr do args[i-1] = eval(expr[i],env) end 
        args[#expr] = nil
        return Script._funs[e](args,env)
      end
    else -- not kosher, but convenient
      local r = {} -- treat all other table exprs as table constructors
      for k,v in pairs(expr) do r[k] = eval(v,env) end
      return r
    end
  else 
    return expr 
  end
end

function Script.defvar(var,expr) Script._vars[var] = expr end

function Script.v(path)
  local res = {} 
  for token in path:gmatch("[%$%w_]+") do res[#res+1] = token end
  return {'var',res}
end

function Script._getVar(path)
  local vars = Script._vars
  for i=1,#path do 
    if vars == nil then return nil end
    if type(vars) ~= 'table' then return error("Undefined var:"..table.concat(path,".")) end
    vars = vars[path[i]]
  end
  return vars
end

function Script._setVar(path,expr)
  local vars = Script._vars
  for i=1,#path-1 do 
    if type(vars[path[i]]) ~= 'table' then vars[path[i]] = {} end
    vars = vars[path[i]]
  end
  vars[path[#path]] = expr
  return expr
end

--------------------- Event handler ---------------------------
if true then
  local prettyJson = Util.prettyJson
  local toTime = Util.toTime
  local EVENT_DEBUG_LENGTH = 20
  
  Event = { 
    _events = {}, 
    STOP='_STOP', BREAK='_BREAK_', 
    PONG='__%%SYSPONG%%__', PING='__%%SYSPING%%__', REMOTE='__%%REMOTE%%__',
    USERFUN = '__%%UFUN%%__',
    S1 = {click = "16", double = "14", tripple = "15", hold = "12", release = "13"}, -- sceneActivation codes
    S2 = {click = "26", double = "24", tripple = "25", hold = "22", release = "23"}
  }

  Event._eventHash = {}
  Event._eventHash['property'] = function(event) 
    local id = event.deviceID
    if type(id) == 'string' then
      local id2 = id:match("==(%d+)$")
      if id2 then id = id2 end
    end
    return "property."..id
  end
  Event._eventHash['global'] = function(event) return 'global.'..event.name end
  Event._eventHash['event'] = function(event) return 'event.'..event.event.data.deviceId end

  function Event._makeEventHash(event) 
    if event.type == nil and event.propertyName then event.type='property' end
    local h = Event._eventHash[event.type]
    return h and h(event) or 'user.'..event.type
  end

  function Event.coerce(x,y)
    local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end
  end

  Event._constraints = {}
  Event._constraints['=='] = function(val) return function(x) x,val=Event.coerce(x,val) return x == val end end
  Event._constraints['>='] = function(val) return function(x) x,val=Event.coerce(x,val) return x >= val end end
  Event._constraints['<='] = function(val) return function(x) x,val=Event.coerce(x,val) return x <= val end end
  Event._constraints['>'] = function(val) return function(x) x,val=Event.coerce(x,val) return x > val end end
  Event._constraints['<'] = function(val) return function(x) x,val=Event.coerce(x,val) return x < val end end
  Event._constraints['~='] = function(val) return function(x) x,val=Event.coerce(x,val) return x ~= val end end
  Event._constraints[''] = function(val) return function(x) return x ~= nil end end

  function Event._compile(pattern)
    if type(pattern) == 'table' then
      if pattern._var_ then return end
      for k,v in pairs(pattern) do
        if type(v) == 'string' and v:sub(1,1) == '$' then
          local var,op,val = v:match("$([%w_%.]+)([<>=~]*)([+-]?%d*%.?%d*)")
          local c = Event._constraints[op](tonumber(val))
          pattern[k] = {_var_=var, _constr=c, _str=v}
        else Event._compile(v) end
      end
    end
  end

  function Event._pmatch(pattern, expr)
    local matches = {}
    local function _unify(pattern,expr)
      if pattern == expr then return true 
      elseif type(pattern) == 'table' then
        if pattern._var_ then
          local var, constr = pattern._var_, pattern._constr
          if var == '_' then return constr(expr) 
          elseif matches[var] then return constr(expr) and _unify(matches[var],expr) -- Hmm, equal?
          else matches[var] = expr return constr(expr) end
        end
        for k,v in pairs(pattern) do 
          if not _unify(v,expr[k]) then return false end 
        end
        return true
      else return false end
    end
    return _unify(pattern,expr) and matches or false 
  end

  Event._specialHandlers = {}
  function Event._defineSpecialHandler(test,fun) Event._specialHandlers[#Event._specialHandlers+1] = {test,fun} end

  function Event._resolveAction(action)
    return type(action) == 'table' and function(env) Script.defvar('$env',env) return Script.eval(action,env) end or action
  end

  function Event:event(pattern,action,timeout,tAction)
    action= Event._resolveAction(action)
    tAction = Event._resolveAction(tAction)
    for _,t in ipairs(Event._specialHandlers) do
      if t[1](pattern) then return t[2](pattern,action) end
    end
    Event._compile(pattern)
    local hash = Event._makeEventHash(pattern)
    if hash == nil then error("Bad event, missing type? :"..Util.prettyJson(pattern)) end
    local events,env = Event._events[hash] or {}
    local event = {event=pattern, action=action, env={}, last = 0, _isEvent=true, enabled=true}  
    env = {myself = event} -- circular, but ok for now...
    event.env = env
    events[#events+1] = event
    Event._events[hash] = events
    if timeout ~= nil then 
      event._childs = {Event:event({'not',pattern,timeout},tAction)}
    end
    return event
  end

  -- Post event, optionally <time> into the future
  function Event:post(event,time,flag) -- fix kludgy 'flag' parameter to debug 'cancels'
    if type(event) == 'function' then event = {type=Event.USERFUN, fun=event, _sh=true} end
    local now = osTime()
    flag = flag == nil and true or flag
    time = time and toTime(time) or now
    time = type(time) == 'function' and time() or time
    local valid = time >= now
    if type(event) == 'table' and not event._sh then -- Shh, keep quiet
      local info = prettyJson(event):sub(1,EVENT_DEBUG_LENGTH)
      if valid then
        Debug(2, "Posting event '%s'%s",info, (time == now) and "" or os.date(" for %H:%M:%S",time))
      elseif _debugPast then
        Debug(2, "Posting past event '%s' for %s - ignored",info,os.date("%H:%M:%S",time))
      end
    end
    if valid then
      return {_System.setTimer(function() Event:handleEvent(event) event = nil end,(time-now)*1000,info), 
              flag,
              event}
    end
  end

  -- Handler for Event:post(function,time), see above Event:post, used by internal handlers mostly..
  Event:event({type=Event.USERFUN}, function(env) env.event.fun() end)
  
  -- Send remote events to scenes, does a 'post' to allow for <time> parameter
  function Event:remote(id,event,time) Event:post({type=Event.REMOTE,id=id,event=event,_sh=true},time) end
  Event:event({type=Event.REMOTE,id='$id',event='$event'},
    function(env) env.p.event._from=SceneID fibaro:startScene(env.p.id,{json.encode(env.p.event)}) end)
  
  -- ping scene
  function Event:ping(id,time) Event:remote(id,{type=Event.PING},time) end
  -- convenience function for receiveing pong, timeout function to handle no response...
  function Event:pong(id,fun,timeout,tAction) return Event:event({type=Event.PONG, _from=id},fun,timeout,tAction) end
  -- reply a ping with a pong
  Event:event({type=Event.PING}, -- add event handler for ping message
    function(env)
      Event:remote(env.event._from,{type=Event.PONG}) -- answer ping with pong
  end)

  --[[
  
  -- Ex. ping sceneX and sceneY every 60s and restart them if no answer
  for _,scene in ipairs({sceneX,sceneY}) do
    Event:pong(scene, -- setup pong handlers
        function(env) 
            Log(LOG_COLOR,"pong %s",scene) -- got pong
            Event:ping(scene,"+00:00:60")  -- send new ping
        end, 
        "+00:00:80", -- No answer in 80s, kill and restart...
        function()
          Log(LOG_COLOR,"No pong for scene %s",scene)
          fibaro:killScenes(scene) -- just to be sure it's really dead
          Log(LOG_COLOR,"Restarting scene %s",scene)
          fibaro:startScene(scene) -- restart scene.
          Event:ping(scene,"+00:00:60") -- ping in 60s to give time to startup
        end)
  
    Event:ping(scene) -- start pinging
  end
  
  function Event:pingHandler(id,intervall,timeout,handler)
    Event:ping(id)
    Event:event({type.Event.PONG,_from=id},
      function(env) Event:ping(id,intervall) end,
      timeout,
      function()
        local res = handler(id)
        if type(res) == 'string' then Event:ping(id,res) end
        end)
  end
   
    Event:pingHandler(id,"00:01:00","00:01:10",
      function(scene)
        Log(LOG_COLOR,"No pong for scene %s",scene)
        fibaro:killScenes(scene) -- just to be sure it's really dead
        Log(LOG_COLOR,"Restarting scene %s",scene)
        fibaro:startScene(scene) -- restart scene.
        return "+00:01:00"  -- ping again in 60s to give time to startup
        end)

--]]
  
  -- cancel an event given the reference, optional <run> set to true forces the event to be handled immediatly.
  function Event:cancel(ref,run) 
    if ref and type(ref) == 'table' and #ref == 3 and ref[3] then 
      if ref[2] then 
        local info = prettyJson(ref[3]):sub(1,EVENT_DEBUG_LENGTH)
        Debug(2,"Cancelling event %s",type(ref[1]) == 'table' and ref[1].doc or info) 
      end
      clearTimeout(ref[1]) 
      if run and ref[3] then Event:handleEvent(ref[3]) end
    end
  end

  function Event:loop(time,fun,n)  -- optional <n>
    local loop = {type="_loop"..math.random(), time=time, _sh=true}
    fun = Event._resolveAction(fun)
    local i = 0
    Event:event(loop,function(env)
        i = i+1
        if n and i > n then return end
        env.p.i = i
        local next = Event:post(loop,env.event.time,false)
        if fun(env) == Event.BREAK then Event:cancel(next) end
      end)
    Event:post(loop)
  end

  function Event:schedule(time,event,test)
    local loop = {type='_scheduler'..math.random(), _sh=true}
    Event:event(loop,
      function(env) 
        if (test == nil or test()) then Event:post(event) end
        Event:post(loop, time) 
      end)
    Event:post(loop,time)
  end

  function Event:request(event,response,action)
    Event:post(event)
    Event:event(response,action)
  end

  function Event:retract(ref) -- remove an event handler
    if type(ref) == 'table' and ref._isEvent then
      if ref._childs then
        for _,e in pairs(ref._childs) do Event:retract(e) end
      end
      local hash = Event._makeEventHash(ref.event)
      local events,i = Event._events[hash] or {},1
      while i <= #events do 
        if events[i] == ref then table.remove(events,i) return end 
        i = i+1 
      end
    end
  end

  function Event:enable(ref,flag) -- enable/disable event handler, a bit more efficient than retract
    if type(ref) == 'table' and ref._isEvent then
      if ref._childs then
        for _,e in pairs(ref._childs) do Event:enable(e,flag) end
      end
      ref.enabled=flag
    end
  end

  function Event:default(fun) -- Register a defaulthandler that gets all events
    -- TBD
  end

  Event._annotate = {}
  Event._annotate['property'] = function(e)
    if e.deviceID then 
      local v,t = fibaro:get(e.deviceID,'value')
      e.value,e.last  = e.value or v, e.last or osTime()-t
    end
  end
  Event._annotate['global'] = function(e)
    if e.name then
      local v,t = fibaro:getGlobal(e.name)
      e.value,e.last  = e.value or v, e.last or osTime()-t
    end
  end

  function Event._handleSim(event)
    if event.type and event.value and event.type == 'property' then
      fibaro._fibaroCalls[event.deviceID..'value'] = {tostring(event.value),osTime()}
    end
  end

  function Event:handleEvent(event)
    --Debug(3,"Handle:%s ",prettyJson(event))
    if event._sim and (not _HC2) and not _remote then Event._handleSim(event) end
    if event.type and Event._annotate[event.type] then Event._annotate[event.type](event) end
    local hash = Event._makeEventHash(event)
    local events = Event._events[hash] or {}
    if #events == 0 then if not event._sh then Error("No handler for event %s",prettyJson(event)) end return end
    for _,e in ipairs(events) do
      if e.enabled then
        --Debug(3,"Matching:%s ",prettyJson(e.event))
        local match= Event._pmatch(e.event,event)
        if match then
          e.env.event, e.env.p = event, match
          e.env.last = osTime()-e.last
          e.last = e.last+e.env.last
          local status, res = xpcall(function() return e.action(e.env) end, function(err) return err end)
          if not status then 
            Error("Bad handler(%s):%s",prettyJson(e.event),res)
            Error("Disabling handler")
            e.enabled = false
          else
            if res == Event.STOP then return end
          end
        end
      end
    end
  end

--[[ ------------------ Optional event handlers -------------------
{'and',E1,E2,...En}  -- fires when E1,...En is true
{'seq',E1,[Delay1,]E2,[Delay2,]...En} -- fires when E1 to En happens in sequence with optional Delays inbetween
{'not',E1,E2,...En,Timeout} -- fires when E1,...En hasn't happened for Timeout seconds
{type='property', deviceID={I1,I2...,In},...} -- Creates separate 'property' handlers for I1 to In
--]]

  Event._defineSpecialHandler( -- {'and',<event1>,<event2>,..,<eventn>}
    function(event) return type(event) == 'table' and event[1] and event[1] == 'and' end,
    function(events,action)
      events = {select(2,table.unpack(events))}
      local cre,re = {}, Event:event({type='and', events=events},action)
      re._childs = cre -- remember childs to be removed
      local ie,p,mp = {type='and', events={}, _sh=true},0,math.pow(2,#events)-1
      for i,e in ipairs(events) do
        cre[#cre+1] = Event:event(e,function(env)
            ie.events[i] = env.event
            p = bit32.bor(p,math.pow(2,i-1))
            if p == mp then Event:post(ie) p = 0 end
          end)
      end
      return re
    end)

--[[
Event:event({'seq',{type='remotekey', key=1},2
                         {type='remotekey', key=2},2
                         {type='remotekey', key=3}},
        function(env) print("Key sequence:1-2-3") end)
    
    local map,t,d = {false,false,flase},0,{inf,2,2}
    Event:event({type='remotekey', key=1}, -- 1
      function(env) 
        map = {true,false,false}
        t = osTime()
      end)
      
    Event:event({type='remotekey', key=2},
      function(env) 
        if allTrue(t,i) and osTime()<t+d[i] then t[i] = true t=osTime() end
      end)
      
    Event:event({type='remotekey', key=3},
      function(env) 
        if allTrue(t,i) and osTime()<t+d[i] then fun() end
      end)

--]]
  Event._defineSpecialHandler( -- {'seq',<event1>,[delay],<event2>,[delay],..,<eventn>}
    function(event) return type(event) == 'table' and event[1] and event[1] == 'seq' end,
    function(events1,action)
      local events = {math.huge,select(2,table.unpack(events1))}
      local n,evs,delay = 1,{},{}
      while n <= #events do 
        if type(events[n]) == 'number' then
          delay[#delay+1] = events[n]
          evs[#evs+1] = events[n+1]
          n = n+2
        else
          delay[#delay+1] = math.huge
          evs[#evs+1] = events[n]
          n = n+1
        end
      end
      local ctime,emap,nevents,cre = 0,{},#evs,{}
      local re = Event:event(evs[1],function(env)
          ctime = osTime()
          for i=2,nevents do emap[i] = false end
          emap[1] = true
        end)
      re._childs = cre
      for i=2,nevents-1 do
        cre[#cre+1] = Event:event(evs[i],function(env)
            for j=1,i-1 do if not emap[j] then return end end
            if osTime() <= ctime+delay[i] then
              ctime = osTime()
              emap[i] = true
            end
          end)
      end
      cre[#cre+1] = Event:event(evs[#evs],function(env)
          for j=1,nevents-1 do if not emap[j] then return end end
          if osTime() <= ctime+delay[nevents] then action() end
        end)
      return re
    end)

--[[
      Event:event({'not',{type='a'},{type='b'},10},action)
      local tp,fun
      fun = function() if action() then Event:post(fun,10) end
      local reschedule = function() Event:cancel(tp) Event:post(fun, 10) end
      Event({type='a'},reschedule)
      Event({type='b'},reschedule)
      tp = Event:post(fun, 10)
--]]
  Event._defineSpecialHandler( -- {'not',<event1>,<event2>,..,<eventn>,delay}
    function(event) return type(event) == 'table' and event[1] and event[1] == 'not' end,
    function(events1,action)
      local events = {select(2,table.unpack(events1))}
      local delay,tp,cre,fun = events[#events],0,{} 
      fun = function() if action() ~= Event.BREAK then tp = Event:post(fun,delay, false) end end
      local reschedule = function() Event:cancel(tp) tp = Event:post(fun, delay, false) end
      for i=1,#events-1 do
        cre[#cre+1] = Event:event(events[i],reschedule) 
      end
      tp = Event:post(fun,delay,false)
      local re = cre[#cre]; table.remove(cre,#cre); re._childs = cre
      return re
    end)


  Event._defineSpecialHandler( -- {type='property', deviceID={<Id1>,<Id2>,...,<Idn>}}
    function(event) return type(event) == 'table' and event.type == 'property' and type(event.deviceID) == 'table' end,
    function(event,action)
      local cre = {}
      for _,id in ipairs(event.deviceID) do
        local ne = json.decode(json.encode(event)) -- Lazy table copy...
        ne.deviceID = id
        cre[#cre+1] = Event:event(ne,action)
      end
      return {_isEvent= true, _childs = cre}
    end)

end

------- "Cron" time/date test --------------
Cron = {}

Cron._dateNames = {
  sun=1,mon=2,tue=3,wed=4,thu=5,fri=6,sat=7,
  jan=1,feb=2,mar=3,apr=4,may=5,jun=6,jul=7,aug=8,sep=9,oct=10,nov=11,dec=12
}

Cron._sunMap = {["@Sunset"] = 'sunsetHour', ["@Sunrise"] = 'sunriseHour'}

Cron._cronMacros =
{['@monthly'] = '0 0 1 * *', ['@weekly'] = '0 0 * * 0', 
  ['@daily'] = '0 0 * * *',   ['@hourly'] = '0 * * * *'}

Cron._seq2map = function(seq)
  local s = {}
  for i,v in ipairs(seq) do s[v] = true end
  return s;
end

Cron._split = function(str,pat)
  local res = {}
  if (str == "*") then return res end
  string.gsub(str, pat, function (w)
      table.insert(res, w)
    end)
  return res
end

Cron._flatten = function(seq) -- flattens a table of tables
  local res = {}
  for _,v1 in ipairs(seq) do
    if (type(v1) ~= 'table') then table.insert(res,v1)
    else for _,v2 in ipairs(v1) do table.insert(res,v2) end end
  end
  return res
end

Cron._expandCron = function(w1)
  local function resolve(id)
    if (type(id) == 'number') then 
      return id
    elseif (Cron._dateNames[id]) then 
      return Cron._dateNames[id]
    else return tonumber(id) end
  end
  local w,m = w1[1],w1[2];
  _,_,start,stop = string.find(w,"(%w+)%p(%w+)")
  if (start == nil) then return resolve(w); end
  start = resolve(start)
  stop = resolve(stop)
  local res = {};
  if (string.find(w,"/")) then
    local _,mm = m(0)
    while(start <= mm) do
      table.insert(res,start);
      start = start+stop;
    end
  else 
    while (start ~= stop) do
      table.insert(res,(m(start)))
      start = m(start + 1)
    end
    table.insert(res,stop)
  end
  return res;
end

Cron._parseCron = function(dateStr)
  local mapN = Util.mapN
  local seq,sun = Cron._split(dateStr,"(%S+)"),nil   -- min,hour,day,month,wday
  if Cron._sunMap[seq[1]] then -- sunset/sunrise.
    local offs,sunFun = tonumber(seq[2])
    if seq[1] == "@sunrise" then
      sunFun = function() return hm2sec("Sunrise") end -- Cache these!
    else
      sunFun = function() return hm2sec("Sunset") end
    end
    seq[1] = "*";
    seq[2] = "*";
    sun = function(p) -- called to patch in current sunset/rise+offset
      local t = sunFun()/60+offs;
      p[1] = {[t % 60] = true};           -- min
      p[2] = {[math.floor(t/60)] = true}; -- hours
    end
  end
  if Cron._cronMacros[seq[1]] then 
  return Cron._parseCron(Cron._cronMacros[seq[1]])
end -- "macros"
seq = mapN(function(w) return Cron._split(w,"[%a%d-/]+") end, seq)   -- split sequences "3,4"
local lim = {
  function(x) return x % 60, 59 end, -- 0-59
  function(x) return x % 24, 23 end, -- 0-23
  function(x) x = x % 32 return x==0 and 1 or x, 31 end, -- 1-31 (need day per month map)
  function(x) x = x % 13 return x==0 and 1 or x, 12 end, -- 1-12
  function(x) x = x % 8 return x==0 and 1 or x, 7 end}; -- 1-7
seq = mapN(function(t) 
    local m = table.remove(lim,1);
    return Cron._flatten(mapN(function (g); return Cron._expandCron({g,m}); end, t))
  end,
  seq) -- expand intervalls "3-5"
return {seq = mapN(Cron._seq2map,seq), sun = sun, day = -1} end

function Cron:new(pattern) 
  pattern = Cron._parseCron(pattern)
  return function()
    local t,dateSeq = os.date("*t",osTime()), pattern.seq
    if pattern.sun and  pattern.day ~= t.wday then
      pattern.day = t.wday
      pattern.sun(dateSeq)
    end
    return 
    (next(dateSeq[1]) == nil or dateSeq[1][t.min]) and    -- minutes 0-59
    (next(dateSeq[2]) == nil or dateSeq[2][t.hour]) and   -- hours   0-23
    (next(dateSeq[3]) == nil or dateSeq[3][t.day]) and    -- day     1-31
    (next(dateSeq[4]) == nil or dateSeq[4][t.month]) and  -- month   1-12
    (next(dateSeq[5]) == nil or dateSeq[5][t.wday])       -- weekday 1-7, 1=sun, 7=sat
  end
end

---------------- Recurring -----------------
-- An example of a recurring event scheduler with minutes, hours, days, months options
-- Ex. recurring{min=15, hour={7,19}, day={'sat','sun'}, action=function(env) ... end)
-- Ex. recurring{sun='rise', min=-15, day={'sat','sun'}, action=function(env) ... end)

function Util.recurring(args)
  local dayMap = {'sun','mon','tue','wed','thu','fri','sat'}
  local monthMap = {'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'}
  local action,hour,min,day,month = args.action,args.hour,args.min,args.day,args.month
  local function tablefy(x) return type(x) == 'table' and x or {x} end
  hour = hour and tablefy(hour) or {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23} 
  min = min and tablefy(min) or {0}
  day = day and table.concat(tablefy(day),',') or table.concat(dayMap,',')
  month = month and table.concat(tablefy(month),',') or table.concat(monthMap,',') 
  local offset = 0
  if args.sun and args.sun == 'set' then hour,offset = sunset():match("(%d+):(%d+)") hour = {hour} end
  if args.sun and args.sun == 'rise' then hour,offset = sunrise():match("(%d+):(%d+)") hour = {hour} end
  Event:event({type='daily_init'},
    function(env)
      local d = os.date("*t",osTime())
      if day:find(dayMap[d.wday]) and month:find(monthMap[d.month]) then -- check if right day&month
        for _,h in ipairs(hour) do
          for _,m in ipairs(min) do
            Event:post({type='action', action=action},today(h*3600+m*60+offset))  -- if so schedule today's events
          end
        end
      end
    end)
end

--------------- System -----------------------
function _System.setTimer(fun,time,doc) return setTimeout(fun,time) end

function _System.decodeJson(str,def)
  local status, res = xpcall(function() return json.decode(str) end, function(err) return err end)
  if not status then 
    Error("Bad JSON DEC(%s):%s",str,res)
    return def
  else
    return res
  end
end

function _System.encodeJson(str,def)
  local status, res = xpcall(function() return json.encode(str) end, function(err) return err end)
  if not status then 
    Error("Bad JSON ENC(%s):%s",str,res)
    return def
  else
    return res
  end
end

if _HC2 then -- Only run the message box on the HC2...

  function _System.startMessageBox()
    fibaro:setGlobal(_BOXNAME,"") -- clear box
    local function poll()
      local l = fibaro:getGlobal(_BOXNAME)
      if l ~= "" and l:sub(1,3) ~= '<@>' then
        fibaro:setGlobal(_BOXNAME,"")
        local e = _System.decodeJson(l,false)
        if e then
          e._sh = _debugEvents == false or nil 
          e._HC2 = true
          --Debug(4,"Incoming event",l)
          Event:post(e)
        end
      end
      setTimeout(poll,250)
    end
    poll()
  end

end

----------------- Main -----------------------------
local version = "0.38"

local sTrigger = fibaro:getSourceTrigger()
local sType = sTrigger['type']

if _HC2 and not _deaf then -- This code only runs on the HC2
  if (sType == 'other' and fibaro:args()) then
    sTrigger,sType = fibaro:args()[1],'event'
  end
  if (sType == 'property' or sType == 'global' or sType=='event') then
    local trigger = type(sTrigger) ~= 'string' and _System.encodeJson(sTrigger,false) or sTrigger
    if trigger == false then fibaro:abort() end
    local ticket = '<@>'..trigger
    repeat 
      while(fibaro:getGlobal(_BOXNAME) ~= "") do fibaro:sleep(100) end
      fibaro:setGlobal(_BOXNAME,ticket)
      --fibaro:sleep(100)
    until fibaro:getGlobal(_BOXNAME) == ticket
    fibaro:setGlobal(_BOXNAME,trigger)
    fibaro:abort()
  end
end

if sTrigger['type'] == 'autostart' or sTrigger['type'] == 'other' then -- Starting scheduler
  mainTitle = mainTitle and mainTitle.." - " or  ""
  Log(WELCOMECOLOR,"%sZEvent vers. %s",mainTitle,version)

  local t = os.date("*t",osTime())
  if math.abs(t.sec-60) < 10 and _HC2 then
    Log(SYSTEMCOLOR,"Aligning to 15s past next minute...")
    fibaro:sleep(1000*((60-t.sec)+15))
  end

  -- We eat our own dogfood, using events to initialize and start everything up
  Event:event({type='sysInit1'},
    function(env) 
      Log(SYSTEMCOLOR,"Starting event listener")
      if (not _deaf) and _System.startMessageBox then _System.startMessageBox() end
      Log(SYSTEMCOLOR,"Loading event definitions")
      local status, res = xpcall(function() main() end, function(err) return err end)
      if not status then 
        Error("Bad declaration in main():%s",res)
      else
        Log(SYSTEMCOLOR,"Running...")
      end
    end)

  if _HC2 and (not _deaf) and fibaro:getGlobalModificationTime(_BOXNAME) == nil then
    Util.createGlobal(_BOXNAME,"",{type='sysInit1', _sh=true})
  else
    Event:post({type='sysInit1', _sh=true})
  end

  if _System.runTimers then _System.runTimers() end

elseif (sTrigger['type'] == 'other') then
  fibaro:abort()
end
