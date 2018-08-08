--[[
%% properties
55 value
66 value
77 value
%% events
%% globals
counter
--]]

_version = "0.99"

--[[
-- EventRunner. Event based scheduler/device trigger handler
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_sceneName ="Demo" -- Set to scene/script name
_debugLevel   = 3
_deviceTable  = "deviceTable" -- Name of json struct with configuration data (i.e. "HomeTable")

_HC2 = true
Event = {}
-- If running offline we need our own setTimeout and net.HTTPClient() and other fibaro funs...
if dofile then dofile("EventRunnerDebug.lua") end

---------------- Callbacks to user code --------------------
local houseRules = true
local ruleTests = false
local ruleTests2 = false

function main()
  local function post(e,t) Event.post(e,t) end
  local function prop(id,state,prop) return {type='property', deviceID=id, propertyName=prop, value=state} end
  local function glob(id,state) return {type='global', name=id, value=state} end
  if houseRules then
    -- Read in devicetable
    local conf = json.decode(fibaro:getGlobalValue(_deviceTable))
    dev = conf.dev
    Util.reverseMapDef(dev) -- Make device names availble for debugging

    -- Set up short variables for use in rules
    for k,v in pairs({ 
        td=dev.toilet_down,kt=dev.kitchen,ha=dev.hall,
        lr=dev.livingroom,ba=dev.back,gr=dev.game,
        ti=dev.tim,ma=dev.max,bd=dev.bedroom}) 
    do Util.defvar(k,v) end

    Rule.eval("$a={};$a.b=77")
    local vv = Rule.test("daily({10:00,11:00})")
    print(json.encode(vv))
    --Rule.eval("{type='property', deviceID=55} => off(66)")
    _setClock("t/08:00")
    _setMaxTime(48)
-- Kitchen
    Event.schedule("n/00:00",function() collectgarbage("collect") end,{name='GC'})
    Rule.macro('LIGHTTIME',"(wday('mon-fri')&hour('8-12')|hour('0-4'))")

    Rule.eval([[for(00:10,safe($kt.movement)&$LIGHTTIME$) => off($kt.lamp_table)]])

    fibaro:call(dev.kitchen.lamp_stove, 'turnOn')
    Event.post({type='property', deviceID=dev.kitchen.movement, value=0}, "n09:00")

    Rule.eval([[for(00:10,safe({$kt.movement,$lr.movement,$ha.movement})&$LIGHTTIME$) =>
      isOn({$kt.lamp_stove,$kt.lamp_sink,$ha.lamp_hall})&off({$kt.lamp_stove,$kt.lamp_sink,$ha.lamp_hall})&
      log('Turning off kitchen spots after 10 min inactivity')]])

-- Kitchen
    Rule.eval("daily(sunset-00:10) => press($kt.sink_led,1);log('Turn on kitchen sink light')")
    Rule.eval("daily(sunrise+00:10) => press($kt.sink_led,2);log('Turn off kitchen sink light')")
    Rule.eval("daily(sunset-00:10) => on($kt.lamp_table);log('Evening, turn on kitchen table light')")

-- Living room
    Rule.eval("daily(sunset-00:10) => on($lr.lamp_window);log('Turn on livingroom light')")
    Rule.eval("daily(00:00) => off($lr.lamp_window);log('Turn off livingroom light')")

-- Front
    Rule.eval("daily(sunset-00:10) => on($ha.lamp_entrance);log('Turn on lights entr.')")
    Rule.eval("daily(sunset) => off($ha.lamp_entrance);log('Turn off lights entr.')")

-- Back
    Rule.eval("daily(sunset-00:10) => on($ba.lamp);log('Turn on lights back')")
    Rule.eval("daily(sunset) => off($ba.lamp);log('Turn off lights back')")

-- Game room
    Rule.eval("daily(sunset-00:10) => on($gr.lamp_window);log('Turn on gaming room light')")
    Rule.eval("daily(23:00) => off($gr.lamp_window);log('Turn off gaming room light')")

-- Tim
    Rule.eval("daily(sunset-00:10) => on({$ti.bed_led,$ti.lamp_window});log('Turn on lights for Tim')")
    Rule.eval("daily(00:00) => off({$ti.bed_led,$ti.lamp_window});log('Turn off lights for Tim')")

-- Max
    Rule.eval("daily(sunset-00:10) => on($ma.lamp_window);log('Turn on lights for Max')")
    Rule.eval("daily(00:00) => off($ma.lamp_window);log('Turn off lights for Max')")

-- Bedroom
    Rule.eval("daily(sunset) => on({$bd.lamp_window,$bd.lamp_table,$bd.bed_led});log('Turn on bedroom light')")
    Rule.eval("daily(23:00) => off({$bd.lamp_window,$bd.lamp_table,$bd.bed_led});log('Turn off bedroom light')")

-- Bathroom
    local breach,safe=prop(dev.toilet_down.movement,1),prop(dev.toilet_down.movement,0)
    local open,close=prop(dev.toilet_down.door,1),prop(dev.toilet_down.door,0)
    fibaro:call(dev.toilet_down.movement,'setValue',0)
    fibaro:call(dev.toilet_down.lamp_roof,'setValue',0)
    Rule.eval("for(00:10,safe($td.movement)&value($td.door)) => not($inBathroom)&off($td.lamp_roof)")
    Rule.eval("breached($td.movement) => if(safe($td.door),$inBathroom=true);on($td.lamp_roof)")
    Rule.eval("breached($td.door) => $inBathroom=false")
    Rule.eval("safe($td.door)&(last($td.movement)<3) => $inBathroom=true")

-- SceneActivation events
    post(prop(dev.livingroom.lamp_roof_holk,Util.S2.click,'sceneActivation'),"n/09:10")
    post(prop(dev.livingroom.lamp_roof_holk,Util.S2.click,'sceneActivation'),"n/09:20")
    
    Rule.load([[
      scene($lr.lamp_roof_holk)==$S2.click =>
        toggle($lr.lamp_roof_sofa);log('Toggling lamp downstairs')
      scene($bd.lamp_roof)==$S2.click =>
        toggle({$bd.lamp_window, $bd.bed_led});log('Toggling bedroom lights')
      scene($ti.lamp_roof)==$S2.click =>
        toggle($ti.bed_led);log('Toggling Tim bedroom lights')
      scene($ti.lamp_roof)==$S2.double =>
        toggle($ti.lamp_window);log('Toggling Tim window lights')
      scene($ma.lamp_roof)==$S2.click =>
        toggle($ma.lamp_window);log('Toggling Max bedroom lights')
      scene($gr.lamp_roof)==$S2.click =>
        toggle($gr.lamp_window);log('Toggling Gameroom window lights')
      scene($kt.lamp_table)==$S2.click =>
        if(label($kt.sonos,'lblState')=='Playing',press($kt.sonos,8),press($kt.sonos,7));
        log('Toggling Sonos %s',label($kt.sonos,'lblState'))
      #property{deviceID=$lr.lamp_window} => 
        if(isOn($lr.lamp_window),{press($lr.lamp_tv,1),press($lr.lamp_globe,1)},{press($lr.lamp_tv,2),press($lr.lamp_globe,2)})
    ]])
  end -- houseRules

  if ruleTests then
    d = {
      garage = {door = 10, lamp = 9},
      bed = {window = 11, sensor = 12, lamp = 13},
      kitchen = {window = 14, lamp = 15, sensor = 16, door = 17, temp=34, switch=41},
      hall = {door = 33},
      livingroom = {window = 18, sensor = 19, lamp = 20},
      wc = {lamp= 21, sensor = 22},
      stairs = {lamp = 23, sensor = 24},
      user = {jan = {phone = 120 }}
    }

    for k,j in pairs(d) do Util.defvar(k,j) end -- define variables from device table
    Util.reverseMapDef(d)

    _setClock("t/08:00")

    Rule.eval("$sunsetLamps={$bed.lamp,$garage.lamp}")
    Rule.eval("$sunriseLamps={$garage.lamp,$bed.lamp}")
    Rule.eval("$lampsDownstairs={$kitchen.lamp}")
    Rule.eval("$sensorsDownstairs={$livingroom.sensor,$kitchen.sensor}")

    Rule.eval("{b=2,c={d=3}}.c.d",true)

    Rule.eval([[
      once(temp($kitchen.temp)>10) => 
      send($user.jan.phone,log('Temp too high: %s',temp($kitchen.temp)))
    ]])

    Rule.eval("for(00:10,not(safe($hall.door))) => send($user.jan.phone,log('Door open %s min',repeat(5)*10))")

    Rule.eval("for(00:15,safe($sensorsDownstairs)) => betw(00:00,05:00)&off($lampsDownstairs)")

    Rule.eval("daily(sunset-00:45) => log('Sunset')&on($sunsetLamps)")
    Rule.eval("daily(sunrise+00:15) => log('Sunrise')&off($sunriseLamps)")

    Rule.eval("!homeStatus=='away' => post(#simulate{action='start'})")
    Rule.eval("!homeStatus=='home' => post(#simulate{action='stop'})")

    Rule.eval("#simulate{action='start'} => log('Starting simulation')")
    Rule.eval("#simulate{action='stop'} => log('Stopping simulation')")

    post(prop(d.kitchen.temp,22),"+/00:10")
    post(prop(d.hall.door,0),"+/00:15")
    post(prop(d.hall.door,1),"+/00:20")

    post(prop(d.kitchen.sensor,0),"n/01:10")
    post(prop(d.livingroom.sensor,0),"n/01:11")

    post(glob('homeStatus','away'),"n/05:11")
    post(glob('homeStatus','home'),"n/07:11")

    Rule.eval("scene($kitchen.switch)==$S1.click => log('S1 switch clicked')")

    post(prop(d.kitchen.switch,Util.S1.click,'sceneActivation'),"n/09:10")

    Rule.eval("csEvent(56).keyId=='4' => log('HELLO key=4')")
    Rule.eval("weather() => log('HELLO %s',weather().newValue)")

    -- Rule.time("10:00, sunrise+00:10

    --Rule.eval("post(#event{event=#CentralSceneEvent{data={deviceId=56,keyId='4',keyAttribute='Pressed'}}},n/08:10)")
    post({type='event',event={type='CentralSceneEvent',data={deviceId=56, keyId='4',keyAttribute='Pressed'}}},"n/08:10")
    post({type='event',event = {type="WeatherChangedEvent", data = {newValue=-2.2,change="Temperature"}}},"n/08:20")

    Rule.eval("{b=2,c={d=3}}.c.d") 

    Rule.eval("daily(10:00)&day('1-7')&wday('mon') => log('10 oclock first Monday of the month!')")
    Rule.eval("daily(10:00)&day('lastw-last')&wday('mon') => log('10 oclock last Monday of the month!')")

--{"event":{"type":"WeatherChangedEvent","data":{"newValue":-2.2,"change":"Temperature","oldValue":-4}},"type":"event"}
--{"type":"event","event":{"type":"CentralSceneEvent","data":{"deviceId":362,"keyId":4,"keyAttribute":"Pressed","icon":{"path":"fibaro\/icons\/com.fibaro.FGKF601\/com.fibaro.FGKF601-4Pressed.png","source":"HC"}}}}
  end -- ruleTests

  if ruleTests2 then 
--  Rule.eval("{2,3,4}[2]=5",true) 
    Rule.eval("$foo={}",true) 
    Rule.eval("!foo=5",true) 
    Rule.eval("$foo['bar']=42",true) 
    Rule.eval("label(42,'foo')='bar'",true) 
    fibaro:abort()
    Rule.eval("breached($bed.sensor)&isOff($bed.lamp)&manual($bed.lamp)>10*60 => on($bed.lamp);log('ON.Manual=%s',manual($bed.lamp))")
    Rule.eval("for(00:10,safe($bed.sensor)&isOn($bed.lamp)) => if(manual($bed.lamp)>10*60,off($bed.lamp));repeat();log('OFF.Manual=%s',manual($bed.lamp))")
    --printRule(y)
    Rule.eval("breached($bed.sensor)&isOff($bed.lamp) => on($bed.lamp);$auto='aon',log('Auto.ON')")
    Rule.eval("for(00:10,safe($bed.sensor)&isOn($bed.lamp)) => off($bed.lamp);$auto='aoff';log('Auto.OFF')")
    Rule.eval("isOn($bed.lamp) => if ($auto~='aon',{$auto='m',log('Man.ON')})")
    Rule.eval("isOff($bed.lamp) => if ($auto~='aoff',{$auto='m',log('Man.ON')})")

    post(prop(d.bed.sensor,1),"+/00:10") 
    post(prop(d.bed.sensor,0),"+/00:10:40")
    post(prop(d.bed.lamp,1),"+/00:25")
  end -- ruleTests2

  Event.event({type='error'},function(env) local e = env.event -- catch errors and print them out
      Log(LOG.ERROR,"Runtime error %s for '%s' receiving event %s",e.err,e.rule,e.event) 
    end)
end -- main()
------------------- EventModel --------------------  
local _supportedEvents = {property=true,global=true,event=true,remote=true}
local _trigger = fibaro:getSourceTrigger()
local _type, _source = _trigger.type, _trigger
local _MAILBOX = "MAILBOX"..__fibaroSceneId

if _type == 'other' and fibaro:args() then
  _trigger,_type = fibaro:args()[1],'remote'
end

if not _FIB then
  _FIB={ get = fibaro.get, getGlobal = fibaro.getGlobal }
end
---------- Producer(s) - Handing over incoming triggers to consumer --------------------
if _supportedEvents[_type] then
  local event = type(_trigger) ~= 'string' and json.encode(_trigger) or _trigger
  local ticket = '<@>'..tostring(source)..event
  repeat 
    while(fibaro:getGlobal(_MAILBOX) ~= "") do fibaro:sleep(100) end -- try again in 100ms
    fibaro:setGlobal(_MAILBOX,ticket) -- try to acquire lock
  until fibaro:getGlobal(_MAILBOX) == ticket -- got lock
  fibaro:setGlobal(_MAILBOX,event) -- write msg
  fibaro:abort() -- and exit
end

---------- Consumer - re-posting incoming triggers as internal events --------------------
fibaro:setGlobal(_MAILBOX,"") -- clear box
local function _poll()
  local l = fibaro:getGlobal(_MAILBOX)
  if l and l ~= "" and l:sub(1,3) ~= '<@>' then -- Something in the mailbox
    fibaro:setGlobal(_MAILBOX,"") -- clear mailbox
    Debug(4,"Incoming event:%",l)
    post(json.decode(l)) -- and post it to our "main()"
  end
  setTimeout(_poll,250) -- check every 250ms
end

------------------------ Support functions -----------------
LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ERROR = "Tomato"}
_format = string.format

if _HC2 then -- if running on the HC2
  function _Msg(level,color,message,...)
    if (_debugLevel >= level) then
      local args = type(... or 42) == 'function' and {(...)()} or {...}
      local tadj = _timeAdjust > 0 and osDate("(%X) ") or ""
      local m = _format('<span style="color:%s;">%s%s</span><br>', color, tadj, _format(message,table.unpack(args)))
      fibaro:debug(m) return m
    end
  end
  if not _timeAdjust then _timeAdjust = 0 end -- support for adjusting for hw time drift on HC2
  osTime = function(arg) return arg and os.time(arg) or os.time()+_timeAdjust end
  osClock = os.clock
  function _setClock(_) end
  function _setMaxTime(_) end
end

function Debug(level,message,...) _Msg(level,LOG.DEBUG,message,...) end
function Log(color,message,...) return _Msg(-100,color,message,...) end
function osDate(f,t) t = t or osTime() return os.date(f,t) end
function errThrow(m,err) if type(err) == 'table' then table.insert(err,1,m) else err = {m,err} end error(err) end
function _assert(test,msg,...) if not test then msg = _format(msg,...) error({msg},3) end end
function _assertf(test,msg,fun) if not test then msg = _format(msg,fun and fun() or "") error({msg},3) end end
function isTimer(t) return type(t) == 'table' and t[Event.TIMER] end
function isRule(r) return type(r) == 'table' and r[Event.RULE] end
function isEvent(e) return type(e) == 'table' and e.type end

function _transform(obj,tf)
  if type(obj) == 'table' then
    local res = {} for l,v in pairs(obj) do res[l] = _transform(v,tf) end 
    return res
  else return tf(obj) end
end
function _copy(obj) return _transform(obj, function(o) return o end) end
function _equal(e1,e2)
  local t1,t2 = type(e1),type(e2)
  if t1 ~= t2 then return false end
  if t1 ~= 'table' and t2 ~= 'table' then return e1 == e2 end
  for k1,v1 in pairs(e1) do if e2[k1] == nil or not _equal(v1,e2[k1]) then return false end end
  for k2,v2 in pairs(e2) do if e1[k2] == nil or not _equal(e1[k2],v2) then return false end end
  return true
end

function midnight() 
  local t = osDate("*t") 
  t.hour,t.min,t.sec = 0,0,0 
  local tt = osTime(t) 
  return tt
end
function today(s) return midnight()+s end

function hm2sec(hmstr)
  local offs,sun = 0
  sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
  if sun and (sun == 'sunset' or sun == 'sunrise') then
    hmstr,offs = fibaro:getValue(1,sun.."Hour"), tonumber(offs) or 0
  end
  local h,m,s = hmstr:match("(%d+):(%d+):?(%d*)")
  _assert(h and m,"Bad hm2sec string %s",hmstr)
  return h*3600+m*60+(tonumber(s) or 0)+(offs or 0)*60
end

function between(t11,t22)
  t1,t2,tn = today(hm2sec(t11)),today(hm2sec(t22)),osTime()
  if t1 <= t2 then return t1 <= tn and tn <= t2 else return tn <= t1 or tn >= t2 end 
end

-- toTime("10:00")     -> 10*3600+0*60 secs   
-- toTime("10:00:05")  -> 10*3600+0*60+5*1 secs
-- toTime("t/10:00")    -> (t)oday at 10:00. midnight+10*3600+0*60 secs
-- toTime("n/10:00")    -> (n)ext time. today at 10.00AM if called before (or at) 10.00AM else 10:00AM next day
-- toTime("+/10:00")    -> Plus time. os.time() + 10 hours
-- toTime("+/00:01:22") -> Plus time. os.time() + 1min and 22sec
-- toTime("sunset")     -> todays sunset in relative secs since midnight, E.g. sunset="05:10", =>toTime("05:10")
-- toTime("sunrise")    -> todays sunrise
-- toTime("sunset+10")  -> todays sunset + 10min. E.g. sunset="05:10", =>toTime("05:10")+10*60
-- toTime("sunrise-5")  -> todays sunrise - 5min
-- toTime("t/sunset+10")-> (t)oday at sunset. E.g. midnight+toTime("sunset+10")
function toTime(time)
  if type(time) == 'number' then return time end
  local p = time:sub(1,2)
  if p == '+/' then return hm2sec(time:sub(2))+osTime()
  elseif p == 'n/' then
    local t1,t2 = today(hm2sec(time:sub(2))),osTime()
    return t1 > t2 and t1 or t1+24*60*60
  elseif p == 't/' then return  hm2sec(time:sub(2))+midnight()
  else return hm2sec(time)
  end
end
---------------------- Event/rules handler ----------------------
function newEventEngine()
  local self = {}
  self.BREAK, self.TIMER, self.RULE ='%%BREAK%%', '%%TIMER%%', '%%RULE%%'

  local function _coerce(x,y)
    local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end
  end

  local _constraints = {}
  _constraints['=='] = function(val) return function(x) x,val=_coerce(x,val) return x == val end end
  _constraints['>='] = function(val) return function(x) x,val=_coerce(x,val) return x >= val end end
  _constraints['<='] = function(val) return function(x) x,val=_coerce(x,val) return x <= val end end
  _constraints['>'] = function(val) return function(x) x,val=_coerce(x,val) return x > val end end
  _constraints['<'] = function(val) return function(x) x,val=_coerce(x,val) return x < val end end
  _constraints['~='] = function(val) return function(x) x,val=_coerce(x,val) return x ~= val end end
  _constraints[''] = function(val) return function(x) return x ~= nil end end

  local function _compilePattern(obj) 
    return _transform(obj, function(o) 
        if type(o) == 'string' and o:sub(1,1) == '$' then
          local op,val = o:match("$([<>=~]*)([+-]?%d*%.?%d*)")
          local c = _constraints[op](tonumber(val) or val)
          return {_constr=c, _str=o}
        else return o end
      end) 
  end

  local function _match(pattern,expr) -- match 2 key-pair event structures
    if pattern == expr then return true end
    if type(pattern) == 'table' then
      if pattern._constr then return pattern._constr(expr)
      elseif type(expr) == 'table' then
        for k,v in pairs(pattern) do 
          if not _match(v,expr[k]) then return false end 
        end
        return true
      end
    end 
    return false
  end

  function self.post(e,time) -- time in 'toTime' format, see below.
    _assert(isEvent(e) or type(e) == 'function', "Bad2 event format %s",tojson(e))
    time = toTime(time or osTime())
    if time < osTime() then return nil end
    if type(e) == 'function' then return {[self.TIMER]=setTimeout(e,1000*(time-osTime()))} end
    if _debugLevel >= 3 and not e._sh then 
      Debug(3,"Posting %s for %s",function() return tojson(e),osDate("%a %b %d %X",time) end)
    end
    return {[self.TIMER]=setTimeout(function() self._handleEvent(e) end,1000*(time-osTime()))}
  end

  function self.cancel(t)
    _assert(isTimer(t) or t == nil,"Bad timer")
    if t then clearTimeout(t[self.TIMER]) end 
    return nil 
  end

  function self.enable(r) _assert(isRule(r), "Bad event format") r.enable() end
  function self.disable(r) _assert(isRule(r), "Bad event format") r.disable() end

  function self.postRemote(sceneID, e) -- Post event to other scenes
    _assert(isEvent(e), "Bad event format")
    e._from = __fibaroSceneId
    fibaro:startScene(sceneID,{json.encode(e)})
  end

  local lastID = {}
  local _getProp = {}
  _getProp['property'] = function(e,v2)
    e.propertyName = e.propertyName or 'value'
    local id = e.deviceID
    local v,t = _FIB:get(id,e.propertyName,true)
    e.value = v2 or v
    if lastID[id]==nil or lastID[id][1]=='h' then 
      lastID[id]={'h',e.value,osTime()}
    else 
      local iv = lastID[id]
      if not(iv[2] == e.value and osTime()-iv[3] < 2) then lastID[id]={'h',e.value,osTime()} end
    end  
    return t
  end
  _getProp['global'] = function(e,v2) local v,t = _FIB:getGlobal(e.name,true) e.value = v2 or v return t end

  local _rules = {}

  function self.event(e,action) -- define rules - event template + action
    _assert(isEvent(e), "bad event format '%s'",tojson(e))
    action = self._compileAction(action)
    e = _compilePattern(e)
    _rules[e.type] = _rules[e.type] or {}
    local rules = _rules[e.type]
    local rule,fn = {[self.RULE]=e, action=action, org=tojson(args)}, true
    for _,rs in ipairs(rules) do -- Collect handlers with identical events. {{e1,e2,e3},{e1,e2,e3}}
      if _equal(e,rs[1][self.RULE]) then rs[#rs+1] = rule fn = false break end
    end
    if fn then rules[#rules+1] = {rule} end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    return rule
  end

  function self.schedule(time,action,opt)
    local test, start = opt and opt.cond, opt and opt.start or false
    local name = opt and opt.name or tostring(action)
    local loop,tp = {type='_scheduler:'..name, _sh=true}
    local test2,action2 = self._compileAction(test),self._compileAction(action)
    local re = self.event(loop,function(env)
        local fl = test == nil or test2()
        if fl == self.BREAK then return
        elseif fl then action2() end
        tp = self.post(loop, time) 
      end)
    local res = {
      [self.RULE] = {},
      enable = function() if not tp then tp = self.post(loop,start and 0 or time) end return res end, 
      disable= function() tp = self.cancel(tp) return res end, 
    }
    res.enable()
    return res
  end

  self._compiledExpr = {}
  self._compiledScript = {}
  self._compiledCode = {}

  function self._compileAction(a)
    local function assoc(a,f,table) table[f] = a; return f end
    if type(a) == 'function' then return a end
    if isEvent(a) then return function(e) return self.post(a) end end  -- Event -> post(event)
    if type(a) == 'string' then                  -- Assume 'string' expression...
      a = assoc(a,ScriptCompiler.parse(a),self._compiledExpr) -- ...compile Expr to script 
    end
    a = assoc(a,ScriptCompiler.compile(a),self._compiledScript)
    return assoc(a,function(e) return ScriptEngine.eval(a) end,self._compiledCode)
  end

  local function _invokeRule(env)
    local status, res = pcall(function() env.rule.action(env) end) -- call the associated action
    if not status then
      res = type(res)=='table' and table.concat(res,' ') or res
      self.post({type='error',err=res,rule=env.rule.org,event=tojson(env.event),_sh=true})    -- Send error back
      env.rule._disabled = true                            -- disable rule to not generate more errors
    end
  end

-- {{e1,e2,e3},{e4,e5,e6}} 
  function self._handleEvent(e) -- running a posted event
    if _OFFLINE and not _REMOTE then if _simFuns[e.type] then _simFuns[e.type](e)  end end
    local env = {event = e}
    if _getProp[e.type] then _getProp[e.type](e,e.value) end  -- patch events
    for _,rules in ipairs(_rules[e.type] or {}) do -- Check all rules of 'type'
      if _match(rules[1][self.RULE],e) then
        for _,rule in ipairs(rules) do 
          if not rule._disabled then env.rule = rule; _invokeRule(env) end
        end
      end
    end
  end

  local fibCall = fibaro.call
  fibaro.call = function(obj,id,a1,a2,a3)
    local v = ({turnOff="0",turnOn="99",on="99",off="0"})[a1] or (a1=='setValue' and a2)
    if v then lastID[id]={'m',v,osTime()} end
    fibCall(obj,id,a1,a2,a3)
  end
  function self.lastManual(id)
    local e = lastID[id]
    if not e or e[1]=='m' then return math.huge 
    else return osTime()-e[3] end
  end
  return self
end

Event = newEventEngine()

------ Util ----------
Util = Util or {}

function Util.dateTest(dateStr)
  local self = {}
  local days = {sun=1,mon=2,tue=3,wed=4,thu=5,fri=6,sat=7}
  local months = {jan=1,feb=2,mar=3,apr=4,may=5,jun=6,jul=7,aug=8,sep=9,oct=10,nov=11,dec=12}
  local last,month = {31,28,31,30,31,30,31,31,30,31,30,31},nil

  local function seq2map(seq) local s = {} for i,v in ipairs(seq) do s[v] = true end return s; end

  local function flatten(seq,res) -- flattens a table of tables
    res = res or {}
    if type(seq) == 'table' then for _,v1 in ipairs(seq) do flatten(v1,res) end else res[#res+1] = seq end
    return res
  end

  local function expandCron(w1,md)
    local function resolve(id)
      if id == 'last' then month = md return last[md] 
      elseif id == 'lastw' then month = md return last[md]-6 
      else return type(id) == 'number' and id or days[id] or months[id] or tonumber(id) end
    end
    local w,m = w1[1],w1[2];
    start,stop = w:match("(%w+)%p(%w+)")
    if (start == nil) then return resolve(w) end
    start,stop = resolve(start), resolve(stop)
    local res = {}
    if (string.find(w,"/")) then -- 10/2
      while(start < m.max) do
        res[#res+1] = start
        start = start+stop
      end
    else 
      _assert(start>=m.min and start<=m.max and stop>=m.min and stop<=m.max,"illegal date intervall")
      while (start ~= stop) do -- 10-2
        res[#res+1] = start
        start = start+1; if start>m.max then start=m.min end  
      end
      res[#res+1] = stop
    end
    return res
  end

  local function parseDateStr(dateStr,last)
    local map = Util.map
    local seq = split(dateStr," ")   -- min,hour,day,month,wday
    local lim = {{min=0,max=59},{min=0,max=23},{min=1,max=31},{min=1,max=12},{min=1,max=7}}
    for i=1,5 do if seq[i]=='*' or seq[i]==nil then seq[i]=tostring(lim[i].min).."-"..lim[i].max end end
    seq = map(function(w) return split(w,",") end, seq)   -- split sequences "3,4"
    local month = osDate("*t",osTime()).month
    seq = map(function(t) local m = table.remove(lim,1);
        return flatten(map(function (g) return expandCron({g,m},month) end, t))
      end, seq) -- expand intervalls "3-5"
    return map(seq2map,seq)
  end
  local dateSeq = parseDateStr(dateStr)
  return function() -- Pretty efficient way of testing dates...
    local t = os.date("*t",osTime())
    if month and month~=t.month then parseDateStr(dateStr) end -- Recalculate 'last' every month
    return
    dateSeq[1][t.min] and    -- min     0-59
    dateSeq[1][t.hour] and   -- hour    0-23
    dateSeq[1][t.day] and    -- day     1-31
    dateSeq[2][t.month] and  -- month   1-12
    dateSeq[3][t.wday]       -- weekday 1-7, 1=sun, 7=sat
  end
end

function Util.mapAnd(f,l,s) s = s or 1; local e=false for i=s,#l do e = f(l[i]) if not e then return false end end return e end 
function Util.mapOr(f,l,s) s = s or 1; for i=s,#l do local e = f(l[i]) if e then return e end end return false end
function Util.mapF(f,l,s) s = s or 1; local e=true for i=s,#l do e = f(l[i]) end return e end
function Util.map(f,l,s) s = s or 1; local r={} for i=s,#l do r[#r+1] = f(l[i]) end return r end
function Util.mapo(f,l,o) for _,j in ipairs(l) do f(o,j) end end
function Util.mapkl(f,l) local r={} for i,j in pairs(l) do r[#r+1]=f(i,j) end return r end
function Util.member(v,tab) for _,e in ipairs(tab) do if v==e then return e end return nil end end
function Util.append(t1,t2) for _,e in ipairs(t2) do t1[#t1+1]=e end return t1 end
function Util.traverse(e,f)
  if type(e) ~= 'table' then return e end
  if type(e[1])~='quote' then e=Util.map(function(e) return Util.traverse(e,f) end, e) end
  return f(e[1],e)
end

Util.S1 = {click = "16", double = "14", tripple = "15", hold = "12", release = "13"}
Util.S2 = {click = "26", double = "24", tripple = "25", hold = "22", release = "23"}

Util._vars = {} 

function Util.defvar(var,expr) Util.setVar(Util.v(var),expr) end

function Util.v(path)
  local res = {} 
  for token in path:gmatch("[%$%w_]+") do res[#res+1] = token end
  return {'var',res}
end

function Util.getVar(var)
  _assertf(type(var) == 'table' and var[1]=='var',"Bad variable: %s",function() return tojson(var) end)
  local vars,path = Util._vars,var[2]
  for i=1,#path do 
    if vars == nil then return nil end
    if type(vars) ~= 'table' then return error("Undefined var:"..table.concat(path,".")) end
    vars = vars[path[i]]
  end
  return vars
end

function Util.setVar(var,expr)
  _assertf(type(var) == 'table' and var[1]=='var',"Bad variable: %s",function() return tojson(var) end)
  local vars,path = Util._vars,var[2]
  for i=1,#path-1 do 
    if type(vars[path[i]]) ~= 'table' then vars[path[i]] = {} end
    vars = vars[path[i]]
  end
  vars[path[#path]] = expr
  return expr
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

function Util.reverseVar(id) return Util._reverseVarTable[tostring(id)] or id end

Util.gKeys = {type=1,deviceID=2,value=3,val=4,key=5,arg=6,event=7,events=8,msg=9,res=10}
Util.gKeysNext = 10
function Util._keyCompare(a,b)
  local av,bv = Util.gKeys[a], Util.gKeys[b]
  if av == nil then Util.gKeysNext = Util.gKeysNext+1 Util.gKeys[a] = Util.gKeysNext av = Util.gKeysNext end
  if bv == nil then Util.gKeysNext = Util.gKeysNext+1 Util.gKeys[b] = Util.gKeysNext bv = Util.gKeysNext end
  return av < bv
end

function Util.prettyJson(e) -- our own json encode, as we don't have 'pure' json structs, and sorts keys in order
  local res,t = {}
  local function pretty(e)
    local t = type(e)
    if t == 'string' then res[#res+1] = '"' res[#res+1] = e res[#res+1] = '"' 
    elseif t == 'number' then res[#res+1] = e
    elseif t == 'boolean' or t == 'function' then res[#res+1] = tostring(e)
    elseif t == 'table' then
      if e[1] then
        res[#res+1] = "[" pretty(e[1])
        for i=2,#e do res[#res+1] = "," pretty(e[i]) end
        res[#res+1] = "]"
      else
        if e._var_  then res[#res+1] = _format('"%s"',e._str) return end
        local k = {} for key,_ in pairs(e) do k[#k+1] = key end 
        table.sort(k,Util._keyCompare)
        if #k == 0 then res[#res+1] = "[]" return end
        res[#res+1] = '{'; res[#res+1] = '"' res[#res+1] = k[1]; res[#res+1] = '":' t = k[1] pretty(e[t])
        for i=2,#k do 
          res[#res+1] = ',"' res[#res+1] = k[i]; res[#res+1] = '":' t = k[i] pretty(e[t]) 
        end
        res[#res+1] = '}'
      end
    elseif e == nil then return "nil"
    else error("bad json expr:"..tostring(e)) end
  end
  pretty(e)
  return table.concat(res)
end
tojson = Util.prettyJson

function Util.mkStack()
  local self,stack,stackp = {},{},0
  function self.push(e) stackp=stackp+1; stack[stackp] = e end
  function self.pop(n) n = n or 1; stackp=stackp-n; return stack[stackp+n] end
  function self.ref(n) return stack[stackp-n] end
  function self.lift(n) local s = {} for i=1,n do s[i] = stack[stackp-n+i] end self.pop(n) return s end
  function self.reset() stackp=0 stack={} end
  function self.isEmpty() return stackp==0 end
  return self
end

--------- ScriptEngine ------------------------------------------

function newScriptEngine()
  local self={}

  local timeFs ={["*"]=function(t) return t end,
    t=function(t) return t+midnight() end,
    ['+']=function(t) return t+osTime() end,
    n=function(t) t=t+midnight() return t<= osTime() and t or t+24*60*60 end,
    ['midnight']=function(t) return midnight() end,
    ['sunset']=function(t) return hm2sec('sunset') end,
    ['sunrise']=function(t) return hm2sec('sunrise') end,
    ['now']=function(t) return osTime()-midnight() end}

  function ID(id,i) _assert(tonumber(id),"bad deviceID '%s' for '%s'",id,i[1]) return id end
  local function doit(m,f,s) if type(s) == 'table' then return m(f,s) else return f(s) end end
  local instr,funs = {},{}
  instr['push'] = function(s,n,a) s.push(a) end
  instr['env'] = function(s,n,a,e) s.push(e) end
  instr['time'] = function(s,n,f,env,i) s.push(timeFs[f](i[4])) end 
  instr['table'] = function(s,n,k,i) local t = {} for j=n,1,-1 do t[k[j]] = s.pop() end s.push(t) end
  instr['pop'] = function(s,n) s.pop() end
  instr['setVar'] = function(s,n,a) local v = s.pop() Util.setVar(a,v) s.push(v) end
  instr['setGlob'] = function(s,n,a) local v = s.pop() fibaro:setGlobal(a[2],v) s.push(v) end
  instr['setLabel'] = function(s,n,a,e,i) local id,v = s.pop(),s.pop() 
    fibaro:call(ID(id,i),"setProperty",_format("ui.%s.value",a),tostring(v)) s.push(v) 
  end
  instr['setRef'] = function(s,n,a) local r,v = s.pop(),s.pop() 
    _assertf(type(r)=='table',"trying to set non-table value '%s'",function() return json.encode(r) end)
    r[a]=v s.push(v) 
  end
  instr['jmp'] = function(s,n,a) return a end
  instr['ifnskip'] = function(s,n,a,e,i) if not s.ref(0) then return a end end
  instr['ifskip'] = function(s,n,a,e,i) if s.ref(0) then return a end end
  instr['yield'] = function(s,n) error({type='yield'}) end
  instr['not'] = function(s,n) s.push(not s.pop()) end
  instr['aref'] = function(s,n) local k,table = s.pop(),s.pop() s.push(table[k]) end
  instr['+'] = function(s,n) s.push(s.pop()+s.pop()) end
  instr['-'] = function(s,n) s.push(-s.pop()+s.pop()) end
  instr['*'] = function(s,n) s.push(s.pop()*s.pop()) end
  instr['/'] = function(s,n) s.push(1.0/(s.pop()/s.pop())) end
  instr['>'] = function(s,n) s.push(tostring(s.pop())<tostring(s.pop())) end
  instr['<'] = function(s,n) s.push(tostring(s.pop())>tostring(s.pop())) end
  instr['>='] = function(s,n) s.push(tostring(s.pop())<=tostring(s.pop())) end
  instr['<='] = function(s,n) s.push(tostring(s.pop())>=tostring(s.pop())) end
  instr['~='] = function(s,n) s.push(tostring(s.pop())~=tostring(s.pop())) end
  instr['=='] = function(s,n) s.push(s.pop()==s.pop()) end
  instr['progn'] = function(s,n) local r = s.pop();  s.pop(n-1); s.push(r) end
  instr['log'] = function(s,n) s.push(Log(LOG.LOG,table.unpack(s.lift(n)))) end
  instr['print'] = function(s,n) print(s.ref(0)) end
  instr['tjson'] = function(s,n) local t = s.pop() s.push(tojson(t)) end
  instr['osdate'] = function(s,n) local x,y = s.ref(n-1), n>1 and s.pop() s.pop(); s.push(os.date(x,y)) end
  instr['daily'] = function(s,n,a,e) s.pop() s.push(true) end
  instr['ostime'] = function(s,n) s.push(osTime()) end
  instr['frm'] = function(s,n) s.push(string.format(table.unpack(s.lift(n)))) end
  instr['var'] = function(s,n,a) s.push(Util.getVar(a)) end
  instr['glob'] = function(s,n,a) s.push(fibaro:getGlobal(a)) end
  instr['label'] = function(s,n,a,e,i) local nm,id = s.pop(),s.pop() s.push(fibaro:get(ID(id,i),_format("ui.%s.value",nm))) end
  instr['last'] = function(s,n,a,e,i) s.push(select(2,fibaro:get(ID(s.pop(),i),'value'))) end
  instr['on'] = function(s,n,a,e,i) doit(Util.mapF,function(id) fibaro:call(ID(id,i),'turnOn') end,s.pop()) s.push(true) end
  instr['isOn'] = function(s,n,a,e,i) s.push(doit(Util.mapOr,function(id) return fibaro:getValue(ID(id,i),'value') > '0' end,s.pop())) end
  instr['off'] = function(s,n,a,e,i) doit(Util.mapF,function(id) fibaro:call(ID(id,i),'turnOff') end,s.pop()) s.push(true) end
  instr['isOff'] = function(s,n,a,e,i) s.push(doit(Util.mapAnd,function(id) return fibaro:getValue(ID(id,i),'value') == '0' end,s.pop())) end
  instr['toggle'] = function(s,n,a,e,i)
    s.push(doit(Util.mapF,function(id) local t = fibaro:getValue(ID(id,i),'value') fibaro:call(id,t>'0' and 'turnOff' or 'turnOn') end,s.pop()))
  end
  instr['power'] = function(s,n,a,e,i) s.push(fibaro:getValue(ID(s.pop(),i),'value')) end
  instr['lux'] = instr['power'] instr['temp'] = instr['power'] instr['sense'] = instr['power']
  instr['value'] = instr['power'] instr['trigger'] = instr['power']
  instr['send'] = function(s,n,a,e,i) local m,id = s.pop(), ID(s.pop(),i) fibaro:call(id,'sendPush',m) s.push(m) end
  instr['press'] = function(s,n,a,e,i) local key,id = s.pop(),ID(s.pop(),i) fibaro:call(id,'pressButton', key) end
  instr['scene'] = function(s,n,a,e,i) s.push(fibaro:getValue(ID(s.pop(),i),'sceneActivation')) end
  instr['once'] = function(s,n,a,e,i) local f; i[4],f = s.pop(),i[4]; s.push(not f and i[4]) end
  instr['post'] = function(s,n) local e,t=s.pop(),nil; if n==2 then t=e; e=s.pop() end Event.post(e,t) s.push(e) end
  instr['safe'] = instr['isOff'] 
  instr['manual'] = function(s,n) s.push(Event.lastManual(s.pop())) end
  instr['start'] = function(s,n) fibaro:startScene(ID(s.pop(),i)) s.push(true) end
  instr['stop'] = function(s,n) fibaro:killScene(ID(s.pop(),i)) s.push(true) end
  instr['breached'] = instr['isOn'] 
  instr['betw'] = function(s,n) local t2,t1,now=s.pop(),s.pop(),osTime()-midnight()
    if t1<=t2 then s.push(t1 <= now and now <= t2) else s.push(now >= t1 or now <= t2) end 
  end
  instr['fun'] = function(s,n) local a,f=s.pop(),s.pop() _assert(funs[f],"undefined fun '%s'",f) s.push(funs[f](table.unpack(a))) end
  instr['repeat'] = function(s,n,a,e) 
    local v,c = n>0 and s.pop() or math.huge
    if not e.forR then s.push(0) 
    elseif v > e.forR[2] then s.push(e.forR[1]()) else s.push(e.forR[2]) end 
  end
  instr['for'] = function(s,n,a,e,i) 
    local val,time = s.pop(),s.pop()
    local rep = function() i[6] = true; i[5] = nil; self.eval(e.code,e) end
    e.forR = nil -- Repeat function (see repeat())
    if i[6] then -- true if timer has expired
      i[6] = nil; 
      if val then
        i[7] = (i[7] or 0)+1 -- Times we have repeated
        e.forR={function() Event.post(rep,time+osTime()) return i[7] end,i[7]}
      end
      s.push(val) 
      return
    end 
    i[7] = 0
    if i[5] and (not val) then i[5] = Event.cancel(i[5]) Log(LOG.LOG,"Killing timer")-- Timer already running, and false, stop timer
    elseif (not i[5]) and val then                        -- Timer not running, and true, start timer
      i[5]=Event.post(rep,time+osTime()) 
    end
    s.push(false)
  end

  function self.addInstr(name,fun) 
    _assert(instr[name] == nil,"Instr already defined: %s",name) 
    instr[name] = fun
  end
  function self.define(name,fun) 
    _assert(funs[name] == nil,"Function already defined: %s",name) 
    funs[name] = fun
  end

  function self.eval(code,env,stack,cp) 
    stack = stack or Util.mkStack()
    env = env or {}
    env.code = code
    local p,i = cp or 1,nil
    local status, res = pcall(function()  
        while p <= #code do
          i = code[p]
          local res = instr[i[1]](stack,i[2],i[3],env,i)
          p = p+(res or 1)
        end
        return stack.pop(),env,stack,1 
      end)
    if status then return res
    else
      if not instr[i[1]] then errThrow("eval",_format("undefined instruction '%s'",i[1])) end
      if type(res) == 'table' and res.type == 'yield' then
        return "%YIELD%",env,stack,p+1
      end
      error(res)
    end
  end
  return self
end
ScriptEngine = newScriptEngine()

------------------------ ScriptCompiler --------------------

function newScriptCompiler()
  local self,traverse = {},Util.traverse

  local function mkOp(o) return o end
  local POP = {mkOp('pop'),0}

  local _comp = {}
  function self._getComps() return _comp end

  local function compT(e,ops)
    if type(e) == 'table' then
      local ef = e[1]
      if _comp[ef] then _comp[ef](e,ops)
      elseif ef == 'set' then 
        compT(e[3],ops)
        local setF = type(e[2])=='table' and ({var='setVar',glob='setGlob',aref='setRef',label='setLabel'})[e[2][1]]
        if setF=='setRef' or setF=='setLabel' then -- ["setRef,["var","foo"],"bar",5]
          compT(e[2][2],ops)
          ops[#ops+1]={mkOp(setF),2,e[2][3]} 
        elseif setF=='setVar' or setF=='setGlob' then
          ops[#ops+1]={mkOp(setF),1,e[2]} 
        else error({_format("trying to set illegal value '%s'",tojson(e[2]))}) end
      elseif ef == 'if' then 
        local ne = {'and',e[2],e[3]} 
        if e[4] then ne={'or',ne,e[4]} end 
        compT(ne,ops) 
      elseif ef == 'table' then
        local keys = {}
        for i=2,#e do
          local key,val=e[i]
          if type(key)=='table' and key[1]=='set' and type(key[2])=='string' and key[3] then
            key,val = key[2],key[3]
          else 
            key,val= i-1,e[i]
          end
          keys[#keys+1] = key; compT(val,ops) 
        end
        ops[#ops+1]={mkOp('table'), #keys,keys}
      elseif ef == '.' then 
        compT({'aref',e[2],e[3]},ops)
      else
        for i=2,#e do compT(e[i],ops) end
        ops[#ops+1] = {mkOp(e[1]),#e-1}
      end
    else ops[#ops+1]={mkOp('push'),0,e} end
  end

  _comp['quote'] = function(e,ops) ops[#ops+1] = {mkOp('push'),0,e[2]} end
  _comp['time'] = function(e,ops) ops[#ops+1] = {mkOp('time'),0,e[2],e[3]} end
  _comp['var'] = function(e,ops) ops[#ops+1] = {mkOp('var'),0,e} end
  _comp['glob'] = function(e,ops) ops[#ops+1] = {mkOp('glob'),0,e[2]} end
  _comp['and'] = function(e,ops) 
    compT(e[2],ops)
    local o1,z = {mkOp('ifnskip'),0,0}
    ops[#ops+1] = o1 -- true skip 
    z = #ops; ops[#ops+1]= POP; compT(e[3],ops); o1[3] = #ops-z+1
  end
  _comp['=>'] = _comp['and']
  _comp['or'] = function(e,ops)  
    compT(e[2],ops)
    local o1,z = {mkOp('ifskip'),0,0}
    ops[#ops+1] = o1 -- true skip 
    z = #ops; ops[#ops+1]= POP; compT(e[3],ops); o1[3] = #ops-z+1;
  end
  _comp['%NULL'] = function(e,ops) compT(e[2],ops); ops[#ops+1]= POP; compT(e[3],ops) end

  function self.dump(code)
    for p = 1,#code do
      local i = code[p]
      Log(LOG.LOG,"%-3d:[%s/%s%s]",p,i[1],i[2],i[3] and ","..tojson(i[3]) or "")
    end
  end

  function self.compile(expr) local code = {} compT(expr,code) return code end

  local _prec = {
    ['*'] = 10, ['/'] = 10, ['.'] = 11, ['+'] = 9, ['-'] = 9, ['{'] = 3, ['['] = 2, ['('] = 1, [','] = 3.5, ['=>'] = -2,
    ['>']=7, ['<']=7, ['>=']=7, ['<=']=7, ['==']=7, ['~=']=7, ['&']=6, ['|']=5, ['=']=4, [';']=3.6}
  local _opMap = {['&']='and',['|']='or',['=']='set',['.']='aref',[';']='progn'}
  local function mapOp(op) return _opMap[op] or op end

  local _tokens = {
    {"^(%b'')",'string'},
    {'^(%b"")','string'},
    {"^%#([0-9a-zA-Z]+{?)",'event'},
    {"^$([_0-9a-zA-Z\\$]+)",'lvar'},
    {"^!([_0-9a-zA-Z\\$]+)",'gvar'},
    {"^({})",'symbol'},
    {"^([tn%+]/%d%d:%d%d:?%d*)",'time'},
    {"^(%d%d:%d%d:?%d*)",'time'},
    {"^([a-zA-Z][0-9a-zA-Z]*)%(",'call'},
    {"^%%([a-zA-Z][0-9a-zA-Z]*)%(",'fun'},
    {"^([%[%]%(%)%{%},])",'spec'},
    {"^([a-zA-Z][_0-9a-zA-Z]*)",'symbol'},
    {"^(;)",'op'},    
    {"^(%d+%.?%d*)",'num'},    
    {"^([~%*%+%-/=><&%|%.]+)",'op'},
  }

  local _specs = { 
    ['('] = {0,'lpar','rpar'},[')'] = {0,'rpar','lpar'},
    ['['] = {0,'aref','rbrack'},[']'] = {0,'rbrack','lbrack'},
    ['{'] = {0,'table','rcurl'},['}'] = {0,'rcurl','lcurl'},
    [','] = {0,'comma'}}

  local function tokenize(s) 
    local i,tkns,cp,s1 = 1,{},1
    repeat
      s1,s = s,s:match("^[%s%c]*(.*)")
      cp = cp+(#s1-#s)
      s = s:gsub(_tokens[i][1],
        function(m) local to = _tokens[i] if to[2] == 'spec' then to = _specs[m] end
        tkns[#tkns+1] = {t=to[2], v=m, m=to[3], cp=cp} i = 1 return "" end)
      if s1 == s then i = i+1 if i > #_tokens then error({_format("bad token '%s'",s)}) end end
      cp = cp+(#s1-#s)
    until s:match("^[%s%c]*$")
    self.st = tkns; self.tp = 1 
  end

  local function peekToken() return self.st[self.tp] end
  local function nxtToken() local r = peekToken(); self.tp = self.tp + 1; return r end

  function checkBrackets(s)
    local m = ({call=')', fun=')', aref=']', table='}', lpar=')'})[s.t]
    return m and error({_format("missing '%s'",m,s.cp)}) or s
  end
  local symbol={}
  symbol['{}'] = function() return {'quote',{}} end
  symbol['true'] = function() return true end
  symbol['false'] = function() return false end
  symbol['nil'] = function() return nil end
  symbol['env'] = function() return {'env'} end
  symbol['now'] = function() return {'time','now'} end
  symbol['sunrise'] = function() return {'time','sunrise'} end
  symbol['sunset'] = function() return {'time','sunset'} end
  symbol['midnight'] = function() return {'time','midnight'} end

  function self.expr()
    local st,stp,res,rp,pdone = {},0,{},0,{}
    local function badExpr() error({_format("bad expression '%s'",table.concat(pdone,' '))}) end
    local function notEmpty() return stp > 0 end  
    local function peek() return stp > 0 and st[stp] or nil end
    local function pop() local r = peek(); stp = stp > 0 and stp-1 or stp; return r end
    local function push(t) stp=stp+1; st[stp] = t end
    local function add(t) rp=rp+1; res[rp] = t end
    while true do
      local t = peekToken()
      if t == nil or t.t == 'token' then 
        while notEmpty() do 
          res[rp-1] = {mapOp(checkBrackets(pop()).v),res[rp-1],res[rp]}; rp=rp-1 
        end
        if rp < 1 then badExpr() end
        res[rp+1] = nil
        return res
      end
      pdone[#pdone+1] = nxtToken().v
      if t.t == 'lvar' then add({'var',{t.v}})
      elseif t.t == 'gvar' then add({'glob',t.v}) 
      elseif t.t == 'num' then add(tonumber(t.v))
      elseif t.t == 'string' then add(t.v:sub(2,-2))
      elseif t.t == 'symbol' then 
        if symbol[t.v] then add(symbol[t.v]()) else add(t.v) end
      elseif t.t == 'time' then 
        local p,h,m,s = t.v:match("([%+nt]?/?)(%d%d):(%d%d):?(%d*)")
        _assert(p=="" or p=="+/" or p=="n/" or p=="t/","malformed time constant '%s'",t.v)
        add({'time',p == "" and '*' or p,h*3600+m*60+(s~="" and s or 0)})
      elseif t.t == 'aref' then t.ma = true push(t) add('ELIST')
      elseif t.t == 'table' then t.ma = true push(t) add('ELIST')
      elseif t.t == 'event' then 
        if t.v:sub(-1,-1) ~= '{' then add({'quote',{type=t.v}})
        else
          push({t='table',v='{',m='rcurl',ma=true,cp=t.cp}) 
          add('ELIST') add({'set','type',t.v:sub(1,-2)}) 
        end
      elseif t.t == 'call' or t.t == 'fun' then t.m = 'rpar' t.ma = true t.f = t.v t.v='(' push(t) add('ELIST') -- call or fun
      elseif t.t == 'lpar' then
        push(t)
      elseif t.m then
        local op = pop()
        while op and op.t ~= 'lpar' and op.t ~= 'call' and op.t ~= 'fun' and op.t ~= 'table' and op.t ~= 'aref' do
          res[rp-1] = {mapOp(op.v),res[rp-1],res[rp]}; rp = rp-1
          op = pop()
        end
        if op == nil then badExpr()
        elseif t.t ~= op.m then error({"mismatched "..op.m}) 
        else push(op) end
        if notEmpty() then
          if peek().ma then
            local f,args = pop(),{}
            while rp>0 and res[rp]~='ELIST' do table.insert(args,1,res[rp]); rp=rp-1 end
            if f.t == 'call' then res[rp] = {f.f,table.unpack(args)} 
            elseif f.t == 'fun' then res[rp] = {'fun',f.f,{'table',table.unpack(args)}} 
            elseif f.t == 'table' then res[rp] = {'table',table.unpack(args)} 
            elseif f.t == 'aref' and rp>1 then res[rp-1]={'aref',res[rp-1],args[1]} rp=rp-1 
            else badExpr() end
          else
            if peek().t == 'lpar' then pop() end
          end
        end
      else
        while notEmpty() and _prec[peek().v] >= _prec[t.v] do
          if rp < 1 then badExpr() end
          res[rp-1] = {mapOp(pop().v), res[rp-1], res[rp]}; rp=rp-1
        end
        if t.t ~= 'comma' then push(t) end
      end
    end
  end

  local simpFs={}
  simpFs['+']=function(a,b) return a+b end
  simpFs['-']=function(a,b) return a-b end
  simpFs['/']=function(a,b) return a/b end
  simpFs['*']=function(a,b) return a*b end

  function simplify(e)
    local function sm(k,e)
      return simpFs[k] and tonumber(e[2]) and tonumber(e[3]) and simpFs[k](tonumber(e[2]),tonumber(e[3])) or e 
    end
    local function sp(k,e) 
      if key~='progn' then return e end
      local l1,l2=e[2],e[3]
      if type(l1)=='table' and l1[1]=='progn' then table.remove(l1,1) else l1 = {l1} end
      if type(l2)=='table' and l2[1]=='progn' then table.remove(l2,1) else l2 = {l2} end
      e=Util.append(l1,l2) table.insert(e,1,'progn') return e
    end
    e = traverse(e,sm)
    return traverse(e,sp)
  end

  function self.parse(s)
    tokenize(s)
    local status, res = pcall(function() 
        local expr = self.expr()[1]
        expr = simplify(expr)
        return expr
      end)
    if status then return res 
    else 
      res = type(res) == 'string' and {res} or res
      errThrow(_format(" parsing '%s'",s),res)
    end
  end

  return self
end
ScriptCompiler = newScriptCompiler()

--------- RuleCompiler ------------------------------------------

function newRuleCompiler()
  local self = {}
  local map,mapkl,traverse=Util.map,Util.mapkl,Util.traverse
  local _macros,_dailys,rCounter= {},{},0
  local tFun={isOn=1,isOff=1,power=1,bat=1,lux=1,safe=1,breached=1,sense=1,manual=1,value=1,temp=1,scene=1,trigger=1}
  local triggFuns = {}

  local function getTriggers(e)
    local ids,dailys={},{}
    local function gt(k,e)
      if k=='daily' then dailys[#dailys+1]=ScriptCompiler.compile(e[2])
      elseif k=='glob' then ids[e[2] ] = {type='gobal', name=e[2]}
      elseif tFun[k] then local v = ScriptEngine.eval(ScriptCompiler.compile(e[2]))
        map(function(id) ids[id]={type='property', deviceID=id} end,type(v)=='table' and v or {v})
      elseif triggFuns[k] then local v = ScriptEngine.eval(ScriptCompiler.compile(e[2]))
        map(function(id) ids[id]=triggFuns[k](id) end,type(v)=='table' and v or {v})
      end
      return e
    end
    traverse(e,gt)
    return ids and mapkl(function(k,v) return v end,ids),dailys
  end

  function self.test(s) return {getTriggers(ScriptCompiler.parse(s))} end
  function self.define(name,fun) ScriptEngine.define(name,fun) end
  function self.addTrigger(name,instr,gt) ScriptEngine.addInstr(name,instr) triggFuns[name]=gt end

  local function compTimes(cs)
    local t1,t2=map(function(c) return ScriptEngine.eval(c) end,cs),{}
    _transform(t1,function(t) t2[t]=true end)
    return mapkl(function(k,v) return k end,t2)
  end

  function self.eval(expro,log)
    local expr = self.macroSubs(expro)
    local e = ScriptCompiler.parse(expr)
    local p,a,res,times = e[2],e[3],nil,{}
    if e[1]~='=>' then
      Log(LOG.LOG,tojson(e))
      res = ScriptCompiler.compile(e)
      ScriptCompiler.dump(res)
      res = ScriptEngine.eval(res)
      if log then Log(LOG.LOG,"%s = %s",expr,tojson(res)) end
      return res
    end
    if expr:match("^%s*#") then -- event matching rule
      local ep = ScriptCompiler.compile(p)
      res = Event.event((ScriptEngine.eval(ep)),a)
    elseif type(p) == 'table' then
      local ids,dailys = getTriggers(p)
      local action = Event._compileAction(expr)
      if #dailys>0 then -- 'daily' rule
        local m,ot=midnight(),osTime()
        _dailys[#_dailys+1]={dailys=dailys,action=action}
        times = compTimes(dailys)
        for _,t in ipairs(times) do if t+m >= ot then Event.post(action,t+m) end end
      elseif #ids>0 then -- id/glob trigger rule
        for _,id in ipairs(ids) do Event.event(id,action).org=expro end
      else
        error(_format("no triggers found in rule '%s'",expro))
      end
      res = {[Event.RULE]={time=times,device=ids}, action=action}
    else error(_format("rule syntax:'%s'",expro)) end
    rCounter=rCounter+1
    Log(LOG.SYSTEM,"Rule:%s:%.40s",rCounter,expro:match("([^%c]*)"))
    res.org=expro
    return res
  end

  function self.load(rules,log)
    local function splitRules(rules)
      local lines,cl,pb,cline = {},math.huge,false,""
      rules:gsub("([^%c]*)\r?\n",function(p) 
          if p:match("^%s*---") then return end
          local s,l = p:match("^(%s*)(.*)")
          if l=="" then cl = math.huge return end
          if #s > cl then cline=cline.." "..l cl = #s pb = true
          elseif #s == cl and pb then cline=cline.." "..l
          else if cline~="" then lines[#lines+1]=cline end cline=l cl=#s pb = false end
        end)
      lines[#lines+1]=cline
      return lines
    end
    map(function(r) self.eval(r,log) end,splitRules(rules))
  end

  local function errWrap(fun,msg)
    return function(...) 
      local args = {...}
      local status, res = pcall(function() return fun(table.unpack(args)) end)
      if status then return res end
      errThrow(_format(msg,args[1]),res)
    end
  end  
  self.eval=errWrap(self.eval,"while evaluating '%s'")

  function self.macro(name,str) _macros['%$'..name..'%$'] = str end
  function self.macroSubs(str) for m,s in pairs(_macros) do str = str:gsub(m,s) end return str end

  Event.schedule("n/00:00",function(env)  -- Scheduler that every night posts 'daily' rules
      local midnight = midnight()
      for _,d in ipairs(_dailys) do
        local times = compTimes(d.dailys)
        for _,t in ipairs(times) do 
          --Log(LOG.LOG,"Scheduling at %s",osDate("%X",midnight+t))
          Event.post(d.action,midnight+t) 
        end
      end
    end)

  return self
end
Rule = newRuleCompiler()

---------------- Extra setup ----------------

local function makeDateInstr(f)
  return function(s,n,a,e,i)
    local ts = s.pop()
    if ts ~= i[5] then i[6] = Util.dateTest(f(ts)); i[5] = ts end -- cache fun
    s.push(i[6]())
  end
end
ScriptEngine.addInstr("date",makeDateInstr(function(s) return s end))             -- min,hour,days,month,wday
ScriptEngine.addInstr("hour",makeDateInstr(function(s) return "* "..s end))       -- hour('10-15'), hour('3,5,6')
ScriptEngine.addInstr("day",makeDateInstr(function(s) return "* * "..s end))      -- day('1-31'), day('1,3,5')
ScriptEngine.addInstr("month",makeDateInstr(function(s) return "* * * "..s end))  -- hour('jan-feb'), hour('jan,mar,jun')
ScriptEngine.addInstr("wday",makeDateInstr(function(s) return "* * * * "..s end)) -- wday('fri-sat'), wday('mon,tue,wed')

-- Support for CentralSceneEvent & WeatherChangedEvent
_lastCSEvent = {}
_lastWeatherEvent = {}
Event.event({type='event'}, function(env) env.event.event._sh = true Event.post(env.event.event) end)
Event.event({type='CentralSceneEvent'}, 
  function(env) _lastCSEvent[env.event.data.deviceId] = env.event.data end)
Event.event({type='WeatherChangedEvent'}, 
  function(env) _lastWeatherEvent[env.event.data.change] = env.event.data; _lastWeatherEvent['*'] = env.event.data end)

Rule.addTrigger('csEvent',
  function(s,n,a,e) return s.push(_lastCSEvent[s.pop()]) end,
  function(id) return {type='CentralSceneEvent',data={deviceId=id}} end)
Rule.addTrigger('weather',
  function(s,n,a,e) local k = n>0 and s.pop() or '*'; return s.push(_lastWeatherEvent[k]) end,
  function(id) return {type='WeatherChangedEvent',data={changed=id}} end)

--- SceneActivation constants
Util.defvar('S1',Util.S1)
Util.defvar('S2',Util.S2)

---- Print rule definition -------------

function printRule(e)
  print(_format("Event:%s",tojson(e[Event.RULE])))
  local code = Event._compiledCode[e.action]
  local scr = Event._compiledScript[code]
  local expr = Event._compiledExpr[scr]

  if expr then Log(LOG.LOG,"Expr:%s",expr) end
  if scr then Log(LOG.LOG,"Script:%s",tojson(scr)) end
  if code then Log(LOG.LOG,"Code:") ScriptCompiler.dump(code) end
  Log(LOG.LOG,"Addr:%s",tostring(e.action))
end

---------------------- Startup -----------------------------    
if _type == 'autostart' or _type == 'other' then
  Log(LOG.WELCOME,_format("%sEventRunner v%s",_sceneName and (_sceneName.." - " or ""),_version))

  if _HC2 and fibaro:getGlobalModificationTime(_MAILBOX) == nil then
    api.post("/globalVariables/",{name=_MAILBOX})
  end

  if _HC2 then _poll() end -- start polling mailbox

  Log(LOG.SYSTEM,"Loading rules")
  local status, res = pcall(function() main() end)
  if not status then 
    Log(LOG.ERROR,"Error loading rules:%s",type(res)=='table' and table.concat(res,' ') or res) fibaro:abort() 
  end

  _trigger.type = 'start' -- 'startup' and 'other' -> 'start'
  _trigger._sh = true
  Event.post(_trigger)

  Log(LOG.SYSTEM,"Scene running")
  Log(LOG.SYSTEM,"Sunrise %s, Sunset %s",fibaro:getValue(1,'sunriseHour'),fibaro:getValue(1,'sunsetHour'))
  collectgarbage("collect")
  print(collectgarbage("count"))
  if _OFFLINE then _System.runTimers() end
  print(collectgarbage("count"))
end