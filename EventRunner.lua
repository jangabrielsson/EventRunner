--[[
%% properties
55 value
66 value
77 value
%% events
88 CentralSceneEvent
99 sceneActivation
100 AccessControlEvent
%% globals
counter 
%% autostart
--]]
-- Don't forget to declare triggers from devices in the header!!!
_version,_fix = "1.12","fix3"  -- Jan 27, 2019 

--[[
-- EventRunner. Event based scheduler/device trigger handler
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]
if not _SCENERUNNER then 

  _sceneName     = "Demo"      -- Set to scene/script name
  _deviceTable   = "devicemap" -- Name of your HomeTable variable
  _ruleLogLength = 80          -- Log message cut-off, defaults to 40
  _HueHubs       = {}          -- Hue bridges, Ex. {{name='Hue',user=_HueUserName,ip=_HueIP}}
  _GUI = false                 -- Offline only, Open WX GUI for event triggers, Requires Lua 5.1 in ZBS
  _SPEEDTIME     = 24*36           -- Offline only, Speed through X hours, set to false will run in real-time
  _EVENTSERVER   = true          -- Starts port on 6872 listening for incoming events (Node-red, HC2 etc)

  _myNodeRed = "http://192.168.1.50:1880/eventrunner"  -- Ex. used for Event.postRemote(_myNodeRed,{type='test})

-- debug flags for various subsystems...
  _debugFlags = { 
    post=true,invoke=false,eventserver=true,triggers=false,dailys=true,timers=false,rule=false,ruleTrue=false,
    fibaro=true,fibaroStart=false,fibaroGet=false,fibaroSet=false,sysTimers=false,hue=false,scene=true
  }

end
-- If running offline we need our own setTimeout and net.HTTPClient() and other fibaro funs...
if dofile then dofile("EventRunnerDebug.lua") require('mobdebug').coro() end

---------------- Here you place rules and user code, called once --------------------
function main()
  local rule,define = Rule.eval, Util.defvar
  --_System.copyGlobalsFromHC2()             -- copy globals from HC2 to ZBS
  --_System.writeGlobalsToFile("test.data")  -- write globals from ZBS to file, default 'globals.data'
  --_System.readGlobalsFromFile()            -- read in globals from file, default 'globals.data'

  --local devs = json.decode(fibaro:getGlobalValue(_deviceTable)) -- Read in "HomeTable" global
  --Util.defvars(devs)                                            -- Make HomeTable defs available in EventScript
  --Util.reverseMapDef(devs)                                      -- Make HomeTable names available for logger

  dofile("example_rules.lua")      -- some example rules to try out...
end -- main()

------------------- EventModel - Don't change! --------------------  
Event = Event or {}
if not _OFFLINE then -- define _System
  local f = function(...) return true end
  _System = {copyGlobalsFromHC2=f,writeGlobalsToFile=f,readGlobalsFromFile=f,defineGlobals=f,setTime=f}
end
_STARTLINE = _OFFLINE and debug.getinfo(1).currentline or nil
if _OFFLINE then MAINTHREAD=coroutine.running() end
local _supportedEvents = {property=true,global=true,event=true,remote=true}
local _trigger = fibaro:getSourceTrigger()
local _type, _source = _trigger.type, _trigger
local _MAILBOX = "MAILBOX"..__fibaroSceneId 
function urldecode(str) return str:gsub('%%(%x%x)',function (x) return string.char(tonumber(x,16)) end) end
if _type == 'other' and fibaro:args() then
  _trigger,_type = urldecode(fibaro:args()[1]),'remote'
end

---------- Producer(s) - Handing over incoming triggers to consumer --------------------

if _supportedEvents[_type] then
  if fibaro:countScenes() == 1 then fibaro:debug("Aborting: Server not started yet"); fibaro:abort() end
  local event = type(_trigger) ~= 'string' and json.encode(_trigger) or _trigger
  local ticket = string.format('<@>%s%s',tostring(_source),event)
  repeat 
    while(fibaro:getGlobal(_MAILBOX) ~= "") do fibaro:sleep(100) end -- try again in 100ms
    fibaro:setGlobal(_MAILBOX,ticket) -- try to acquire lock
  until fibaro:getGlobal(_MAILBOX) == ticket -- got lock
  fibaro:setGlobal(_MAILBOX,event) -- write msg
  fibaro:abort() -- and exit
end

---------- Consumer - re-posting incoming triggers as internal events --------------------

local function _poll()
  local l = fibaro:getGlobal(_MAILBOX)
  if l and l ~= "" and l:sub(1,3) ~= '<@>' then -- Something in the mailbox
    fibaro:setGlobal(_MAILBOX,"") -- clear mailbox
    Debug(_debugFlags.triggers,"Incoming event:%s",l)
    l = json.decode(l) l._sh=true
    Event.post(l) -- and post it to our "main()"
  end
  setTimeout(_poll,250) -- check every 250ms
end

------------------------ Support functions -----------------
LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ULOG="Khaki", ERROR = "Tomato"}
_format = string.format
if not _getIdProp then
  _getIdProp = function(id,prop) return fibaro:get(id,prop) end; _getGlobal = function(id) return fibaro:getGlobal(id) end
end
Util = Util or {}
gEventRunnerKey="6w8562395ue734r437fg3"

if not _OFFLINE then -- if running on the HC2
  function _Msg(color,message,...)
    local args = type(... or 42) == 'function' and {(...)()} or {...}
    local tadj = _timeAdjust > 0 and osDate("(%X) ") or ""
    message = _format(message,table.unpack(args))
    fibaro:debug(_format('<span style="color:%s;">%s%s</span><br>', color, tadj, message))
    return message
  end
  if not _timeAdjust then _timeAdjust = 0 end -- support for adjusting for hw time drift on HC2
  osTime = function(arg) return arg and os.time(arg) or os.time()+_timeAdjust end
  function Debug(flag,message,...) if flag then _Msg(LOG.DEBUG,message,...) end end
  function Log(color,message,...) return _Msg(color,message,...) end
  function _LINEFORMAT(line) return "" end
  function _LINE() return nil end
  function osDate(f,t) t = t or osTime() return os.date(f,t) end
end

function errThrow(m,err) if type(err) == 'table' then table.insert(err,1,m) else err = {m,err} end error(err) end
function _assert(test,msg,...) if not test then msg = _format(msg,...) error({msg},3) end end
function _assertf(test,msg,fun) if not test then msg = _format(msg,fun and fun() or "") error({msg},3) end end
function isTimer(t) return type(t) == 'table' and t[Event.TIMER] end
function isRule(r) return type(r) == 'table' and r[Event.RULE] end
function isEvent(e) return type(e) == 'table' and e.type end
function isTEvent(e) return type(e)=='table' and (e[1]=='%table' or e[1]=='quote') and type(e[2])=='table' and e[2].type end
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
function time2str(t) return string.format("%02d:%02d:%02d",math.floor(t/3600),math.floor((t%3600)/60),t%60) end
function midnight() local t = osDate("*t"); t.hour,t.min,t.sec = 0,0,0; return osTime(t) end

function hm2sec(hmstr)
  local offs,sun
  sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
  if sun and (sun == 'sunset' or sun == 'sunrise') then
    hmstr,offs = fibaro:getValue(1,sun.."Hour"), tonumber(offs) or 0
  end
  local sg,h,m,s = hmstr:match("^(%-?)(%d+):(%d+):?(%d*)")
  _assert(h and m,"Bad hm2sec string %s",hmstr)
  return (sg == '-' and -1 or 1)*(h*3600+m*60+(tonumber(s) or 0)+(offs or 0)*60)
end

function between(t11,t22)
  local t1,t2,tn = midnight()+hm2sec(t11),midnight()+hm2sec(t22),osTime()
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
-- toTime("t/sunset+10")-> (t)oday at sunset in 'absolute' time. E.g. midnight+toTime("sunset+10")
function toTime(time)
  if type(time) == 'number' then return time end
  local p = time:sub(1,2)
  if p == '+/' then return hm2sec(time:sub(3))+osTime()
  elseif p == 'n/' then
    local t1,t2 = midnight()+hm2sec(time:sub(3)),osTime()
    return t1 > t2 and t1 or t1+24*60*60
  elseif p == 't/' then return  hm2sec(time:sub(3))+midnight()
  else return hm2sec(time) end
end
---------------------- Event/rules handler ----------------------
function newEventEngine()
  local self,_handlers = {},{}
  self.BREAK, self.TIMER, self.RULE ='%%BREAK%%', '%%TIMER%%', '%%RULE%%'
  self.PING, self.PONG ='%%PING%%', '%%PONG%%'
  self._sections = {}
  self.SECTION = nil

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

  function self._compilePattern(pattern)
    if type(pattern) == 'table' then
      if pattern._var_ then return end
      for k,v in pairs(pattern) do
        if type(v) == 'string' and v:sub(1,1) == '$' then
          local var,op,val = v:match("$([%w_]*)([<>=~]*)([+-]?%d*%.?%d*)")
          var = var =="" and "_" or var
          local c = _constraints[op](tonumber(val))
          pattern[k] = {_var_=var, _constr=c, _str=v}
        else self._compilePattern(v) end
      end
    end
  end

  function self._match(pattern, expr)
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
        if type(expr) ~= "table" then return false end
        for k,v in pairs(pattern) do if not _unify(v,expr[k]) then return false end end
        return true
      else return false end
    end
    return _unify(pattern,expr) and matches or false
  end

  local function ruleError(res,ctx,def)
    res = type(res)=='table' and table.concat(res,' ') or res
    Log(LOG.ERROR,"Error in '%s'%s: %s",ctx and ctx.src or def,_LINEFORMAT(ctx and ctx.line),res)
  end

  function self._callTimerFun(e,ctx)
    local status,res = pcall(function() return e(ctx) end) 
    if not status then ruleError(res,ctx,"timer fun") end
  end

  function self.post(e,time,ctx) -- time in 'toTime' format, see below. ctx is like env...
    _assert(isEvent(e) or type(e) == 'function', "Bad2 event format %s",tojson(e))
    time,ctx = toTime(time or osTime()), ctx or {}
    if time < osTime() then return nil end
    if type(e) == 'function' then 
      ctx.src=ctx.src or "timer "..tostring(e)
      if _debugFlags.postTimers then Debug(true,"Posting timer %s at %s",ctx.src,osDate("%a %b %d %X",time)) end
      return {[self.TIMER]=setTimeout(function() self._callTimerFun(e,ctx) end, 1000*(time-osTime()))}
    end
    ctx.src=ctx.src or tojson(e)
    if _debugFlags.post and not e._sh then Debug(true,"Posting %s at %s",tojson(e),osDate("%a %b %d %X",time)) end
    return {[self.TIMER]=setTimeout(function() self._handleEvent(e) end,1000*(time-osTime()))}
  end

  function self.cancel(t)
    _assert(isTimer(t) or t == nil,"Bad timer")
    if t then clearTimeout(t[self.TIMER]) end 
    return nil 
  end

  local function httpPostEvent(url,payload, e)
    local HTTP = net.HTTPClient()
    payload=json.encode({args={payload}})
    HTTP:request(url,{options = {
          headers = {['Accept']='application/json',['Content-Type']='application/json'},
          data = payload, timeout=2000, method = 'POST'},
        error = function(status) self.post({type='%postEvent%',status='fail', oe=e, _sh=true}) end,
        success = function(status) self.post({type='%postEvent%',status='success', oe=e, _sh=true}) end,
      })
  end

  function self.postRemote(sceneIDorURL, e) -- Post event to other scenes or node-red
    _assert(isEvent(e), "Bad event format")
    e._from = _OFFLINE and -1 or __fibaroSceneId
    local payload = urlencode(json.encode(e))
    if type(sceneIDorURL)=='string' and sceneIDorURL:sub(1,4)=='http' then
      httpPostEvent(sceneIDorURL, payload, e)
    else fibaro:startScene(sceneIDorURL,{payload}) end
  end

  local _getProp = {}
  _getProp['property'] = function(e,v)
    e.propertyName = e.propertyName or 'value'
    e.value = v or (_getIdProp(e.deviceID,e.propertyName,true))
    self.trackManual(e.deviceID,e.value)
    return nil -- was t
  end
  _getProp['global'] = function(e,v2) local v,t = _getGlobal(e.name,true) e.value = v2 or v return t end

  function self._mkCombEvent(e,doc,action,rl)
    local rm = {[self.RULE]=e, action=action, src=doc, subs=rl}
    rm.enable = function() Util.mapF(function(e) e.enable() end,rl) return rm end
    rm.disable = function() Util.mapF(function(e) e.disable() end,rl) return rm end
    rm.print = function() Util.map(function(e) e.print() end,rl) end
    return rm
  end

  local toHash,fromHash={},{}
  fromHash['property'] = function(e) return {e.type..e.deviceID,e.type} end
  fromHash['global'] = function(e) return {e.type..e.name,e.type} end
  toHash['property'] = function(e) return e.deviceID and 'property'..e.deviceID or 'property' end
  toHash['global'] = function(e) return e.name and 'global'..e.name or 'global' end

  local function handlerEnable(t,handle)
    if type(handle) == 'string' then Util.mapF(self[t],Event._sections[handle] or {})
    elseif isRule(handle) then handle[t]()
    elseif type(handle) == 'table' then Util.mapF(self[t],handle) 
    else error('Not an event handler') end
    return true
  end

  function self.enable(handle,opt)
    if type(handle)=='string' and opt then 
      for s,e in pairs(self._sections or {}) do 
        if s ~= handle then Log(LOG.LOG,'dis:%s',s); handlerEnable('disable',e) end
      end
    end
    return handlerEnable('enable',handle) 
  end
  function self.disable(handle) return handlerEnable('disable',handle) end

  function self.event(e,action,doc,ctx) -- define rules - event template + action
    doc = doc and " Event.event:"..doc or _format(" Event.event(%s,...)",tojson(e))
    ctx = ctx or {}; ctx.src,ctx.line=ctx.src or doc,ctx.line or _LINE()
    if e[1] then -- events is list of event patterns {{type='x', ..},{type='y', ...}, ...}
      return self._mkCombEvent(e,action,doc,Util.map(function(es) return self.event(es,action,doc,ctx) end,e))
    end
    _assert(isEvent(e), "bad event format '%s'",tojson(e))
    if e.deviceID and type(e.deviceID) == 'table' then  -- multiple IDs in deviceID {type='property', deviceID={x,y,..}}
      return self.event(Util.map(function(id) local el=_copy(e); el.deviceID=id return el end,e.deviceID),action,doc,ctx)
    end
    action = self._compileAction(action)
    self._compilePattern(e)
    local hashKey = toHash[e.type] and toHash[e.type](e) or e.type
    _handlers[hashKey] = _handlers[hashKey] or {}
    local rules = _handlers[hashKey]
    local rule,fn = {[self.RULE]=e, action=action, src=ctx.src, line=ctx.line}, true
    for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
      if _equal(e,rs[1][self.RULE]) then rs[#rs+1] = rule fn = false break end
    end
    if fn then rules[#rules+1] = {rule} end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    rule.print = function() Log(LOG.LOG,"Event(%s) => ..",tojson(e)) end
    if self.SECTION then
      local s = self._sections[self.SECTION] or {}
      s[#s+1] = rule
      self._sections[self.SECTION] = s
    end
    return rule
  end

  function self.schedule(time,action,opt,ctx)
    local test,start,name = opt and opt.cond, opt and (opt.start or false), opt and opt.name or tostring(action)
    ctx = ctx or {}; ctx.src,ctx.line=ctx.src or name,ctx.line or _LINE()
    local loop,tp = {type='_scheduler:'..name, _sh=true}
    local test2,action2 = test and self._compileAction(test),self._compileAction(action)
    local re = self.event(loop,function(env)
        local fl = test == nil or test2()
        if fl == self.BREAK then return
        elseif fl then action2() end
        tp = self.post(loop, time,ctx) 
      end)
    local res = nil
    res = {
      [self.RULE] = {}, src=ctx.src, line=ctx.line, --- res ??????
      enable = function() if not tp then tp = self.post(loop,(not start) and time or nil,ctx) end return res end, 
      disable= function() tp = self.cancel(tp) return res end, 
    }
    res.enable()
    return res
  end

  local _trueFor={ property={'value'}, global = {'value'}}
  function self.trueFor(time,event,action,ctx)
    local pattern,ev,ref = _copy(event),_copy(event),nil
    ctx = ctx or {}; ctx.src,ctx.line=ctx.src or tojson(event),ctx.line or _LINE()
    self._compilePattern(pattern)
    if _trueFor[ev.type] then 
      for _,p in ipairs(_trueFor[ev.type]) do ev[p]=nil end
    else error(_format("trueFor can't handle events of type '%s'%s",event.type,_LINEFORMAT(ctx.line))) end
    return Event.event(ev,function(env) 
        local p = self._match(pattern,env.event)
        if p then env.p = p; self.post(function() ref=nil action(env) end, time, ctx) else self.cancel(ref) end
      end)
  end

  function self._compileAction(a)
    if type(a) == 'function' then return a end
    if isEvent(a) then return function(e) return self.post(a,nil,e.rule) end end  -- Event -> post(event)
    error("Unable to compile action:"..json.encode(a))
  end

  local function _invokeRule(env)
    local t = osTime()
    env.last,env.rule.time = t-(env.rule.time or 0),t
    Debug(_debugFlags.invoke and not env.event._sh,"Invoking:%s",env.rule.src,_LINEFORMAT(env.rule.line))
    local status, res = pcall(function() env.rule.action(env) end) -- call the associated action
    if not status then
      ruleError(res,env.rule,"rule")
      self.post({type='error',err=res,rule=env.rule.src,line=env.rule.line,event=tojson(env.event),_sh=true})    -- Send error back
      env.rule._disabled = true                            -- disable rule to not generate more errors
    end
  end

-- {{e1,e2,e3},{e4,e5,e6}} env={event=_,p=_,context=_,rule.src=_,last=_}
  function self._handleEvent(e) -- running a posted event
    if _getProp[e.type] then _getProp[e.type](e,e.value) end  -- patch events
    if _OFFLINE and not _REMOTE then if _simFuns[e.type] then _simFuns[e.type](e)  end end
    local env, _match = {event = e, p={}}, self._match
    local hasKeys = fromHash[e.type] and fromHash[e.type](e) or {e.type}
    for _,hashKey in ipairs(hasKeys) do
      for _,rules in ipairs(_handlers[hashKey] or {}) do -- Check all rules of 'type'
        local match = _match(rules[1][self.RULE],e)
        if match then
          if next(match) then for k,v in pairs(match) do env.p[k]=v match[k]={v} end env.context = match end
          for _,rule in ipairs(rules) do 
            if not rule._disabled then env.rule = rule _invokeRule(env) end
          end
        end
      end
    end
  end

-- We intercept all fibaro:call so we can detect manual invocations of switches
  fibaro._call = fibaro.call 
  local lastID = {}
  fibaro.call = function(obj,id,a1,...)
    if ({turnOff=true,turnOn=true,on=true,off=true,setValue=true})[a1] then lastID[id]={script=true,time=osTime()} end
    fibaro._call(obj,id,a1,...)
  end
  function self.lastManual(id)
    lastID[id] = lastID[id] or {time=0}
    if lastID[id].script then return -1 
    else return osTime()-lastID[id].time end
  end
  function self.trackManual(id,value)
    lastID[id] = lastID[id] or {time=0}
    if lastID[id].script==nil or osTime()-lastID[id].time>1 then lastID[id]={time=osTime()} end -- Update last manual
  end
  if nil then
    fibaro._orgf={}
    function fibaro:_intercept(name,fun)
      local ff = fibaro._orgf[name] or fibaro[name]
      if fibaro._orgf[name] then 
        fibaro._orgf[name] =function(obj,...) fun(obj,ff,...) end
      else fibaro._orgf[name] = ff; fibaro[name]=function(obj,...) fun(obj,ff,...) end 
    end
  end
end
-- Logging of fibaro:* calls -------------
fibaro._orgf={}
function interceptFib(name,flag,spec,mf)
  local fun,fstr = fibaro[name],name:match("^get") and "fibaro:%s(%s%s%s) = %s" or "fibaro:%s(%s%s%s)"
  fibaro._orgf[name]=fun
  if spec then 
    fibaro[name] = function(obj,...) 
      if _debugFlags[flag] then 
        return spec(obj,fibaro._orgf[name],...) else return fibaro._orgf[name](obj,...) 
      end 
    end 
  else 
    fibaro[name] = function(obj,id,...)
      local id2,args = type(id) == 'number' and Util.reverseVar(id) or '"'..(id or "<ID>")..'"',{...}
      local status,res,r2 = pcall(function() return fibaro._orgf[name](obj,id,table.unpack(args)) end)
      if status and _debugFlags[flag] then
        Debug(true,fstr,name,id2,(#args>0 and "," or ""),json.encode(args):sub(2,-2),json.encode(res))
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
interceptFib("killScenes","fibaro")
interceptFib("sleep","fibaro",
  function(obj,fun,time) 
    Debug(true,"fibaro:sleep(%s) until %s",time,osDate("%X",osTime()+math.floor(0.5+time/1000)))
    fun(obj,time) 
  end)
interceptFib("startScene","fibaro",
  function(obj,fun,id,args) 
    local a = args and #args==1 and type(args[1])=='string' and (json.encode({(urldecode(args[1]))})) or args and json.encode(args)
    Debug(true,"fibaro:start(%s%s)",id,a and ","..a or "")
    fun(obj,id, args) 
  end)

return self
end

Event = newEventEngine()

------ Util ----------
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

  local function expandDate(w1,md)
    local function resolve(id)
      local res
      if id == 'last' then month = md res=last[md] 
      elseif id == 'lastw' then month = md res=last[md]-6 
      else res= type(id) == 'number' and id or days[id] or months[id] or tonumber(id) end
      _assert(res,"Bad date specifier '%s'",id) return res
    end
    local w,m,step= w1[1],w1[2],1
    local start,stop = w:match("(%w+)%p(%w+)")
    if (start == nil) then return resolve(w) end
    start,stop = resolve(start), resolve(stop)
    local res,res2 = {},{}
    if w:find("/") then
      if not w:find("-") then -- 10/2
        step=stop; stop = m.max
      else step=w:match("/(%d+)") end
    end
    step = tonumber(step)
    _assert(start>=m.min and start<=m.max and stop>=m.min and stop<=m.max,"illegal date intervall")
    while (start ~= stop) do -- 10-2
      res[#res+1] = start
      start = start+1; if start>m.max then start=m.min end  
    end
    res[#res+1] = stop
    if step > 1 then for i=1,#res,step do res2[#res2+1]=res[i] end; res=res2 end
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
        return flatten(map(function (g) return expandDate({g,m},month) end, t))
      end, seq) -- expand intervalls "3-5"
    return map(seq2map,seq)
  end
  local sun,offs,day,sunPatch = dateStr:match("^(sun%a+) ([%+%-]?%d+)")
  if sun then
    sun = sun.."Hour"
    dateStr=dateStr:gsub("sun%a+ [%+%-]?%d+","0 0")
    sunPatch=function(dateSeq)
      local h,m = (fibaro:getValue(1,sun)):match("(%d%d):(%d%d)")
      dateSeq[1]={[(h*60+m+offs)%60]=true}
      dateSeq[2]={[math.floor((h*60+m+offs)/60)]=true}
    end
  end
  local dateSeq = parseDateStr(dateStr)
  return function() -- Pretty efficient way of testing dates...
    local t = os.date("*t",osTime())
    if month and month~=t.month then parseDateStr(dateStr) end -- Recalculate 'last' every month
    if sunPatch and (month and month~=t.month or day~=t.day) then sunPatch(dateSeq) day=t.day end -- Recalculate 'last' every month
    return
    dateSeq[1][t.min] and    -- min     0-59
    dateSeq[2][t.hour] and   -- hour    0-23
    dateSeq[3][t.day] and    -- day     1-31
    dateSeq[4][t.month] and  -- month   1-12
    dateSeq[5][t.wday] or false      -- weekday 1-7, 1=sun, 7=sat
  end
end

function Util.printRule(rule)
  Log(LOG.LOG,"-----------------------------------")
  Log(LOG.LOG,"Source:'%s'%s",rule.src,_LINEFORMAT(rule.line))
  rule.print()
  Log(LOG.LOG,"-----------------------------------")
end

function Util.mapAnd(f,l,s) s = s or 1; local e=true for i=s,#l do e = f(l[i]) if not e then return false end end return e end 
function Util.mapAnd2(f,l) local e=true for _,v in pairs(l) do e = type(v)=='table' and true or f(v) if not e then return false end end return e end 
function Util.mapOr(f,l,s) s = s or 1; for i=s,#l do local e = f(l[i]) if e then return e end end return false end
function Util.mapOr2(f,l) for _,v in pairs(l) do local e = type(v) ~= 'table' and f(v) if e then return e end end return false end
function Util.mapF(f,l,s) s = s or 1; local e=true for i=s,#l do e = f(l[i]) end return e end
function Util.mapF2(f,l) local e=true for _,v in pairs(l) do if type(v) ~= 'table' then e = f(v) end end return e end
function Util.map(f,l,s) s = s or 1; local r={} for i=s,#l do r[#r+1] = f(l[i]) end return r end
function Util.map2(f,l) local r={} for _,v in pairs(l) do if type(v)~='table' then r[#r+1] = f(v) end end return r end
function Util.mapo(f,l,o) for _,j in ipairs(l) do f(o,j) end end
function Util.mapkl(f,l) local r={} for i,j in pairs(l) do r[#r+1]=f(i,j) end return r end
function Util.mapkk(f,l) local r={} for i,j in pairs(l) do r[i]=f(j) end return r end
function Util.member(v,tab) for _,e in ipairs(tab) do if v==e then return e end end return nil end
function Util.append(t1,t2) for _,e in ipairs(t2) do t1[#t1+1]=e end return t1 end
function Util.gensym(s) return s..tostring({1,2,3}):match("([abcdef%d]*)$") end
Util.S1 = {click = "16", double = "14", tripple = "15", hold = "12", release = "13"}
Util.S2 = {click = "26", double = "24", tripple = "25", hold = "22", release = "23"} 

function Util.deviceTypeFilter(expr,ty)
  _assert(type(expr)=='table' and type(ty)=='string',"Bad filter")
  local res,sf={},expr[1] and ipairs or pairs
  local function match(expr)
    for k,id in sf(expr) do 
      if type(id)=='table' then match(id)
      else
        local map = Util._types[id]
        if map then for _,s in ipairs(map) do if s:match(ty) then res[#res+1]=id break end end end
      end
    end
  end
  match(expr)
  return res
end

Util._vars,Util._types = {},{sensor={},light={},switch={}}

function Util.deftype(id,ty)
  if type(id)=='table' then Util.mapF(function(id) Util.deftype(id,ty) end, id)
  else 
    local map = Util._types[id] or {}; Util._types[id] = map
    map[#map+1]=ty
  end
end

if not Util.defineGlobals then function Util.defineGlobals() end end
function Util.defvar(var,expr) Util._vars[var]=expr end
function Util.defvars(tab) 
  for var,val in pairs(tab) do Util.defvar(var,val) end
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
      if next(e)==nil then res[#res+1]='{}'
      elseif e[1] then
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
    elseif e == nil then res[#res+1]='null'
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
  function self.peek() return stackp>0 and stack[stackp] or nil end
  function self.lift(n) local s = {} for i=1,n do s[i] = stack[stackp-n+i] end self.pop(n) return s end
  function self.liftc(n) local s = {} for i=1,n do s[i] = stack[stackp-n+i] end return s end
  function self.reset() stackp=0 stack={} end
  function self.isEmpty() return stackp==0 end
  function self.size() return stackp end
  self.stack = stack
  return self
end

Util.getIDfromEvent={ CentralSceneEvent=function(d) return d.deviceId end,AccessControlEvent=function(d) return d.id end }
Util.getIDfromTrigger={
  property=function(e) return e.deviceID end,
  event=function(e) return e.event and Util.getIDfromEvent[e.event.type or ""](e.event.data) end
}

--------- ScriptEngine ------------------------------------------
_traceInstrs=false

function newScriptEngine() 
  local self={}

  function ID(id,i) _assert(tonumber(id),"bad deviceID '%s' for '%s' '%s'",id,i[1],i[3] or "") return id end
  local function doit(m,f,s) if type(s) == 'table' then return m(f,s) else return f(s) end end

  local function getIdFuns(s,i,prop) local id = s.pop() 
    if type(id)=='table' then return Util.map(function(id) return fibaro:get(ID(id,i),prop) end,id) else return fibaro:get(ID(id,i),prop) end 
  end
  local getIdFun={}
  getIdFun['isOn']=function(s,i) return doit(Util.mapOr2,function(id) return fibaro:get(ID(id,i),'value') > '0' end,s.pop()) end
  getIdFun['isOff']=function(s,i) return doit(Util.mapAnd2,function(id) return fibaro:getValue(ID(id,i),'value') == '0' end,s.pop()) end
  getIdFun['isAllOn']=function(s,i) return doit(Util.mapAnd2,function(id) return fibaro:get(ID(id,i),'value') > '0' end,s.pop()) end
  getIdFun['isAnyOff']=function(s,i) return doit(Util.mapOr2,function(id) return fibaro:getValue(ID(id,i),'value') == '0' end,s.pop()) end
  getIdFun['on']=function(s,i) doit(Util.mapF2,function(id) fibaro:call(ID(id,i),'turnOn') end,s.pop()) return true end
  getIdFun['off']=function(s,i) doit(Util.mapF2,function(id) fibaro:call(ID(id,i),'turnOff') end,s.pop()) return true end
  getIdFun['last']=function(s,i) local t = osTime()
    return doit(Util.map2,function(id) return t-select(2,fibaro:get(ID(id,i),'value')) end, s.pop()) 
  end
  getIdFun['scene']=function(s,i) return getIdFuns(s,i,'sceneActivation') end
  getIdFun['bat']=function(s,i) return getIdFuns(s,i,'batteryLevel') end
  getIdFun['name']=function(s,i) return doit(Util.map,function(id) return fibaro:getName(ID(id,i)) end,s.pop()) end 
  getIdFun['roomName']=function(s,i) return doit(Util.map,function(id) return fibaro:getRoomNameByDeviceID(ID(id,i)) end,s.pop()) end 
  getIdFun['safe']=getIdFun['isOff'] getIdFun['breached']=getIdFun['isOn']
  getIdFun['trigger']=function(s,i) return true end -- Nop, only for triggering rules
  getIdFun['dID']=function(s,i,e) local a = s.pop()
    if type(a)=='table' then
      local id = e.event and Util.getIDfromTrigger[e.event.type or ""](e.event)
      if id then for _,id2 in ipairs(a) do if id == id2 then return id end end end
    end
    return a
  end 
  getIdFun['access']=function(s,i) return doit(Util.map,function(id) return _lastEID['AccessControlEvent'][id] or {} end,s.pop()) end
  getIdFun['central']=function(s,i) return doit(Util.map,function(id) return _lastEID['CentralSceneEvent'][id] or {} end,s.pop()) end
  getIdFun['lux']=function(s,i) return getIdFuns(s,i,'value') end
  getIdFun['temp']=getIdFun['lux']
  getIdFun['manual']=function(s,i) return doit(Util.map,function(id) return Event.lastManual(id) end,s.pop()) end
  getIdFun['start']=function(s,i) doit(Util.mapF,function(id) fibaro:startScene(ID(id,i)) end,s.pop()) return true end
  getIdFun['stop']=function(s,i) doit(Util.mapF,function(id) fibaro:killScenes(ID(id,i)) end,s.pop()) return true end  
  getIdFun['toggle']=function(s,i)
    return doit(Util.mapF,function(id) local t = fibaro:getValue(ID(id,i),'value') fibaro:call(id,t>'0' and 'turnOff' or 'turnOn') end,s.pop())
  end
  local setIdFun={}
  local _propMap={R='setR',G='setG',B='setB', armed='setArmed',W='setW',value='setValue',time='setTime',power='setPower'}
  local function setIdFuns(s,i,prop,id,v) 
    local p,vp=_propMap[prop],0 _assert(p,"bad setProperty :%s",prop)
    local vf = type(v) == 'table' and type(id)=='table' and v[1] and function() vp=vp+1 return v[vp] end or function() return v end 
    doit(Util.mapF,function(id) fibaro:call(ID(id,i),p,vf()) end,id) 
  end
  setIdFun['color'] = function(s,i,id,v) doit(Util.mapF,function(id) fibaro:call(ID(id,i),'setColor',v[1],v[2],v[3]) end,id) return v end
  setIdFun['msg'] = function(s,i,id,v) local m = v doit(Util.mapF,function(id) fibaro:call(ID(id,i),'sendPush',m) end,id) return m end
  setIdFun['btn'] = function(s,i,id,v) local k = v doit(Util.mapF,function(id) fibaro:call(ID(id,i),'pressButton',k) end,id) return k end
  setIdFun['start'] = function(s,i,id,v) 
    if isEvent(v) then doit(Util.mapF,function(id) Event.postRemote(ID(id,i),v) end,id) return v
    else doit(Util.mapF,function(id) fibaro:startScene(ID(id,i),v) end,id) return v end 
  end

  local WEEKNMUMSTR = os.getenv and os.getenv('OS') and os.getenv('OS'):lower():match("windows") and "%W" or "%V"
  local timeFs ={["*"]=function(t) return t end,
    t=function(t) return t+midnight() end,
    ['+']=function(t) return t+osTime() end,
    n=function(t) t=t+midnight() return t> osTime() and t or t+24*60*60 end,
    ['midnight']=function(t) return midnight() end,
    ['sunset']=function(t) if t=='*' then return hm2sec('sunset') else return toTime(t.."/sunset") end end,
    ['sunrise']=function(t) if t=='*' then return hm2sec('sunrise') else return toTime(t.."/sunrise") end end,
    ['wnum']=function(t) return tonumber(osDate(WEEKNMUMSTR)) end,
    ['now']=function(t) return osTime()-midnight() end}
  local function _coerce(x,y) local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end end
  local function getVar(v,e) local vars = e.context 
    while vars do local v1 = vars[v] if v1 then return v1[1] else vars=vars.__next end end
    if Util._vars[v]~=nil then return Util._vars[v] else return _ENV[v] end
  end
  local function setVar(var,val,e) local vars = e.context
    while vars do if vars[var] then vars[var][1]=val return val else vars = vars.__next end end
    if var:sub(1,1)=='_' and Util._vars[var]~=val then Event.post({type='variable', name=var, value=val},nil,e.rule) end
    Util._vars[var]=val; return val
  end

  local instr = {}
  function self.isInstr(i) return instr[i] end
  instr['pop'] = function(s) s.pop() end
  instr['push'] = function(s,n,e,i) s.push(i[3]) end
  instr['time'] = function(s,n,e,i) if n==1 then s.push(toTime(s.pop())) else s.push(timeFs[i[3] ](i[4])) end end
  instr['ifnskip'] = function(s,n,e,i) if not s.ref(0) then e.cp=e.cp+i[3]-1 end end
  instr['ifskip'] = function(s,n,e,i) if s.ref(0) then e.cp=e.cp+i[3]-1 end end
  instr['addr'] = function(s,n,e,i) s.push(i[3]) end
  instr['jmp'] = function(s,n,e,i) local addr,c,cp,p = i[3],e.code,e.cp,i[4] or 0
    if i[5] then s.pop(p) e.cp=i[5]-1 return end  -- First time we search for the label and cache the position
    for k=1,#c do if c[k][1]=='addr' and c[k][3]==addr then i[5]=k s.pop(p) e.cp=k-1 return end end 
    error({"jump to bad address:"..addr}) 
  end
  instr['fn'] = function(s,n,e,i) local vars,cnxt = i[3],e.context or {__instr={}} for i=1,n do cnxt[vars[i]]={s.pop()} end end
  instr['rule'] = function(s,n,e,i) local r,b,h=s.pop(),s.pop(),s.pop() s.push(Rule.compRule({'=>',h,b},e)) end
  instr['prop'] = function(s,n,e,i)local prop=i[3] if getIdFun[prop] then s.push(getIdFun[prop](s,i,e)) else s.push(getIdFuns(s,i,prop)) end end
  instr['apply'] = function(s,n,e,i) local f = s.pop()
    local fun = type(f) == 'string' and getVar(f,e) or f
    if type(fun)=='function' then s.push(fun(table.unpack(s.lift(n)))) 
    elseif type(fun)=='table' and type(fun[1]=='table') and fun[1][1]=='fn' then
      local context = {__instr={}, __ret={e.cp,e.code}, __next=e.context}
      e.context,e.cp,e.code=context,0,fun 
    else _assert(false,"undefined fun '%s'",i[3]) end
  end
  instr['return'] = function(s,n,e) local cnxt=e.context
    if cnxt.__ret then e.cp,e.code=cnxt.__ret[1 ],cnxt.__ret[2 ] e.context=cnxt.__next 
      if n==0 then s.push(false) end
    else error("return out of context") end
  end
  instr['table'] = function(s,n,e,i) local k,t = i[3],{} for j=n,1,-1 do t[k[j]] = s.pop() end s.push(t) end
  instr['logRule'] = function(s,n,e,i) local src,res = s.pop(),s.pop() 
    Debug(_debugFlags.rule or (_debugFlags.ruleTrue and res),"[%s]>>'%s'",tojson(res),src) s.push(res) 
  end
  instr['var'] = function(s,n,e,i) s.push(getVar(i[3],e)) end
  instr['glob'] = function(s,n,e,i) s.push(fibaro:getGlobal(i[3])) end
  instr['setVar'] =  function(s,n,e,i) local var,val = i[3],i[4] or s.pop() s.push(setVar(var,val,e)) end
  instr['setGlob'] = function(s,n,e,i) local var,val = i[3],i[4] or s.pop() fibaro:setGlobal(var,val) s.push(val) end
  instr['setLabel'] = function(s,n,e,i) local id,v,lbl = s.pop(),s.pop(),i[3]
    fibaro:call(ID(id,i),"setProperty",_format("ui.%s.value",lbl),tostring(v)) s.push(v) 
  end
  instr['setSlider'] = instr['setLabel']
  instr['setRef'] = function(s,n,e,i) local r,v,k = s.pop(),s.pop() 
--    if n==3 then r,k=s.pop(),r else k=i[3] end
    if n==3 then r,k,v=v,r,s.pop() else k=i[3] end
    _assertf(type(r)=='table',"trying to set non-table value '%s'",function() return json.encode(r) end)
    r[k]= v; s.push(v) 
  end  
  instr['setProp'] = function(s,n,e,i) local id,v,prop=s.pop(),s.pop(),i[3] 
    if setIdFun[prop] then setIdFun[prop](s,i,id,v) else setIdFuns(s,i,prop,id,v) end
    s.push(v) 
  end
  instr['aref'] = function(s,n,e,i) local k,tab 
    if n==1 then k,tab=i[3],s.pop() else k,tab=s.pop(),s.pop() end
    _assert(type(tab)=='table',"attempting to index non table with key:'%s'",k)
    s.push(tab[k])
  end
  instr['trace'] = function(s,n) _traceInstrs=s.ref(0) end
  instr['env'] = function(s,n,e) s.push(e) end
  instr['yield'] = function(s,n) s.push(true) error({type='yield'}) end
  instr['not'] = function(s,n) s.push(not s.pop()) end
  instr['neg'] = function(s,n) s.push(-tonumber(s.pop())) end
  instr['+'] = function(s,n) s.push(s.pop()+s.pop()) end
  instr['-'] = function(s,n) s.push(-s.pop()+s.pop()) end
  instr['*'] = function(s,n) s.push(s.pop()*s.pop()) end
  instr['/'] = function(s,n) local y,x=s.pop(),s.pop()
    if type(x)=='table' and type(y)=='string' then s.push(Util.deviceTypeFilter(x,y)) else s.push(x,y) end
  end
  instr['%'] = function(s,n) local a,b=s.pop(),s.pop(); s.push(b % a) end
  instr['inc+'] = function(s,n,e,i) local var,val=i[3],i[4] or s.pop() s.push(setVar(var,getVar(var,e)+val,e)) end
  instr['inc-'] = function(s,n,e,i) local var,val=i[3],i[4] or s.pop() s.push(setVar(var,getVar(var,e)-val,e)) end
  instr['inc*'] = function(s,n,e,i) local var,val=i[3],i[4] or s.pop() s.push(setVar(var,getVar(var,e)*val,e)) end
  instr['>'] = function(s,n) local y,x=_coerce(s.pop(),s.pop()) s.push(x>y) end
  instr['<'] = function(s,n) local y,x=_coerce(s.pop(),s.pop()) s.push(x<y) end
  instr['>='] = function(s,n) local y,x=_coerce(s.pop(),s.pop()) s.push(x>=y) end
  instr['<='] = function(s,n) local y,x=_coerce(s.pop(),s.pop()) s.push(x<=y) end
  instr['~='] = function(s,n) s.push(tostring(s.pop())~=tostring(s.pop())) end
  instr['=='] = function(s,n) s.push(tostring(s.pop())==tostring(s.pop())) end
  instr['log'] = function(s,n) s.push(Log(LOG.ULOG,table.unpack(s.lift(n)))) end
  instr['rnd'] = function(s,n) local ma,mi=s.pop(),n>1 and s.pop() or 1 s.push(math.random(mi,ma)) end
  instr['round'] = function(s,n) local v=s.pop(); s.push(math.floor(v+0.5)) end
  instr['sum'] = function(s,n) local m,res=s.pop(),0 for _,x in ipairs(m) do res=res+x end s.push(res) end 
  instr['average'] = function(s,n) local m,res=s.pop(),0 for _,x in ipairs(m) do res=res+x end s.push(res/#m) end 
  instr['size'] = function(s,n) s.push(#(s.pop())) end
  instr['min'] = function(s,n) s.push(math.min(table.unpack(type(s.peek())=='table' and s.pop() or s.lift(n)))) end
  instr['max'] = function(s,n) s.push(math.max(table.unpack(type(s.peek())=='table' and s.pop() or s.lift(n)))) end
  instr['sort'] = function(s,n) local a = type(s.peek())=='table' and s.pop() or s.lift(n); table.sort(a) s.push(a) end
  instr['tjson'] = function(s,n) s.push(tojson(s.pop())) end
  instr['fjson'] = function(s,n) s.push(json.decode(s.pop())) end
  instr['osdate'] = function(s,n) local x,y = s.ref(n-1),(n>1 and s.pop() or nil) s.pop(); s.push(osDate(x,y)) end
  instr['daily'] = function(s,n,e) s.pop() s.push(true) end
  instr['schedule'] = function(s,n,e,i) local t,code = s.pop(),e.code; s.push(true) end
  instr['ostime'] = function(s,n) s.push(osTime()) end
  instr['frm'] = function(s,n) s.push(string.format(table.unpack(s.lift(n)))) end
  instr['idname'] = function(s,n) s.push(Util.reverseVar(s.pop())) end 
  instr['label'] = function(s,n,e,i) local nm,id = s.pop(),s.pop() s.push(fibaro:get(ID(id,i),_format("ui.%s.value",nm))) end
  instr['slider'] = instr['label']
  instr['once'] = function(s,n,e,i) local f; i[4],f = s.pop(),i[4]; s.push(not f and i[4]) end
  instr['always'] = function(s,n,e,i) s.pop(n) s.push(true) end
  instr['enable'] = function(s,n,e,i) local t,g = s.pop(),false; 
    if n==2 then g,t=t,s.pop() end
    s.push(Event.enable(t,g)) 
  end
  instr['disable'] = function(s,n,e,i) s.push(Event.disable(s.pop())) end
  instr['post'] = function(s,n,ev) local e,t=s.pop(),nil; if n==2 then t=e; e=s.pop() end s.push(Event.post(e,t,ev.rule)) end
  instr['remote'] = function(s,n,ev) local e,u=s.pop(),s.pop(); Event.postRemote(u,e) s.push(true) end
  instr['cancel'] = function(s,n) Event.cancel(s.pop()) s.push(nil) end
  instr['add'] = function(s,n) local v,t=s.pop(),s.pop() table.insert(t,v) s.push(t) end
  instr['betw'] = function(s,n) local t2,t1,now=s.pop(),s.pop(),osTime()-midnight()
    _assert(tonumber(t1) and tonumber(t2),"Bad arguments to between '...', '%s' '%s'",t1 or "nil", t2 or "nil")
    if t1<=t2 then s.push(t1 <= now and now <= t2) else s.push(now >= t1 or now <= t2) end 
  end
  instr['redaily'] = function(s,n,e,i) s.push(Rule.restartDaily(s.pop())) end
  instr['eventmatch'] = function(s,n,e,i) local ev,evp=i[3][2],i[3][3] s.push(e.event and Event._match(evp,e.event) and ev or false) end
  instr['wait'] = function(s,n,e,i) local t,cp=s.pop(),e.cp 
--    _assert(tonumber(t),"Bad argument to wait '%s'",t or "nil")
    if i[4] then s.push(false) -- Already 'waiting'
    elseif i[5] then i[5]=false s.push(true) -- Timer expired, return true
    else 
      if t<midnight() then t = osTime()+t end -- Allow both relative and absolute time... e.g '10:00'->midnight+10:00
      i[4]=Event.post(function() i[4]=nil i[5]=true self.eval(e.code,e,e.stack,cp) end,t,e.rule) s.push(false) error({type='yield'})
    end 
  end
  instr['repeat'] = function(s,n,e) 
    local v,c = n>0 and s.pop() or math.huge
    if not e.forR then s.push(0) 
    elseif v > e.forR[2] then s.push(e.forR[1]()) else s.push(e.forR[2]) end 
  end
  instr['for'] = function(s,n,e,i) 
    local val,time, stack, cp = s.pop(),s.pop(), e.stack, e.cp
    local code = e.code
    local rep = function() i[6] = true; i[5] = nil; self.eval(code) end
    e.forR = nil -- Repeat function (see repeat())
    --Log(LOG.LOG,"FOR")
    if i[6] then -- true if timer has expired
      --Log(LOG.LOG,"Timer expired")
      i[6] = nil; 
      if val then 
        i[7] = (i[7] or 0)+1 -- Times we have repeated 
        --print(string.format("REP:%s, TIME:%s",i[7],time))
        e.forR={function() Event.post(rep,time+osTime(),e.rule) return i[7] end,i[7]}
      end
      s.push(val) 
      return
    end 
    i[7] = 0
    if i[5] and (not val) then i[5] = 
      Event.cancel(i[5]) --Log(LOG.LOG,"Killing timer")-- Timer already running, and false, stop timer
    elseif (not i[5]) and val then                        -- Timer not running, and true, start timer
      i[5]=Event.post(rep,time+osTime(),e.rule) --Log(LOG.LOG,"Starting timer %s",tostring(i[5]))
    end
    s.push(false)
  end

  function self.addInstr(name,fun) _assert(instr[name] == nil,"Instr already defined: %s",name) instr[name] = fun end

  function postTrace(i,args,stack,cp)
    local f,n = i[1],i[2]
    if not ({jmp=true,push=true,pop=true,addr=true,fn=true,table=true,})[f] then
      local p0,p1=3,1; while i[p0] do table.insert(args,p1,i[p0]) p1=p1+1 p0=p0+1 end
      args = _format("%s(%s)=%s",f,tojson(args):sub(2,-2),tojson(stack.ref(0)))
      Log(LOG.LOG,"pc:%-3d sp:%-3d %s",cp,stack.size(),args)
    else
      Log(LOG.LOG,"pc:%-3d sp:%-3d [%s/%s%s]",cp,stack.size(),i[1],i[2],i[3] and ","..tojson(i[3]) or "")
    end
  end

  function self.eval(code,env,stack,cp) 
    stack = stack or Util.mkStack()
    env = env or {}
    env.context = env.context or {__instr={}}
    env.cp,env.code,env.stack = cp or 1,code,stack
    local i,args
    local status, res = pcall(function()  
        while env.cp <= #env.code do
          i = env.code[env.cp]
          if _traceInstrs then 
            args = _copy(stack.liftc(i[2]))
            instr[i[1]](stack,i[2],env,i)
            postTrace(i,args,stack,env.cp) 
          else instr[i[1]](stack,i[2],env,i) end
          env.cp = env.cp+1
        end
        return stack.pop(),env,stack,1 
      end)
    if status then return res
    else
      if not instr[i[1]] then errThrow("eval",_format("undefined instruction '%s'",i[1])) end
      if type(res) == 'table' and res.type == 'yield' then
        if res.fun then res.fun(env,stack,env.cp+1,res) end
        return "%YIELD%",env,stack,env.cp+1
      end
      error(res)
    end
  end
  return self
end
ScriptEngine = newScriptEngine()

------------------------ ScriptCompiler --------------------
Rule = nil
function newScriptCompiler()
  local self,gensym,preC = {},Util.gensym,{}

  local function mkOp(o) return o end
  local POP = {mkOp('pop'),0}
  local function isVar(e) return type(e)=='table' and e[1]=='var' end
  function isGlob(e) return type(e)=='table' and e[1]=='glob' end
  function isTriggerVar(e) return isVar(e) and e[2]:sub(1,1)=='_' end
  local function isNum(e) return type(e)=='number' end
  local function isBuiltin(fun) return ScriptEngine.isInstr(fun) or preC[fun] end
  local function isString(e) return type(e)=='string' end
  local _comp = {}
  function self._getComps() return _comp end

  local symbol={['{}'] = {{'quote',{}}}, ['true'] = {true}, ['false'] = {false}, ['nil'] = {nil},
    ['env'] = {{'env'}}, ['wnum'] = {{'%time','wnum'}},['now'] = {{'%time','now'}},['sunrise'] = {{'%time','sunrise','*'}}, ['sunset'] = {{'%time','sunset','*'}},
    ['midnight'] = {{'%time','midnight'}}}

  local function compT(e,ops)
    if type(e) == 'table' then
      local ef = e[1]
      if _comp[ef] then _comp[ef](e,ops)
      else for i=2,#e do compT(e[ i],ops) end ops[#ops+1] = {mkOp(e[1]),#e-1} end -- built-in fun
    else 
      ops[#ops+1]={mkOp('push'),0,e} -- constants etc
    end
  end

  _comp['%jmp'] = function(e,ops) ops[#ops+1] = {mkOp('jmp'),0,e[2],e[3]} end
  _comp['%addr'] = function(e,ops) ops[#ops+1] = {mkOp('addr'),0,e[2]} end
  _comp['%time'] = function(e,ops) ops[#ops+1] = {mkOp('time'),0,e[2],e[3]} end
  _comp['%eventmatch'] = function(e,ops) ops[#ops+1] = {mkOp('eventmatch'),0,e[2]} end
  _comp['quote'] = function(e,ops) ops[#ops+1] = {mkOp('push'),0,e[2]} end
  _comp['glob'] = function(e,ops) ops[#ops+1] = {mkOp('glob'),0,e[2]} end
  _comp['var'] = function(e,ops) ops[#ops+1] = {mkOp('var'),0,e[2]} end
  _comp['prop'] = function(e,ops) 
    _assert(isString(e[3]),"bad property field: '%s'",e[3])
    compT(e[2],ops) ops[#ops+1]={mkOp('prop'),0,e[3]} 
  end
  _comp['apply'] = function(e,ops) for i=1,#e[3] do compT(e[3][i],ops) end compT(e[2],ops) ops[#ops+1] = {mkOp('apply'),#e[3],e[2][2]} end
  _comp['%table'] = function(e,ops) local keys = {}
    for key,val in pairs(e[2]) do keys[#keys+1] = key; compT(val,ops) end
    ops[#ops+1]={mkOp('table'),#keys,keys}
  end
  _comp['inc'] = function(e,ops) -- {inc,var,val,op}
    if isString(e[3]) or isNum(e[3]) then ops[#ops+1]= {mkOp('inc'..e[4]),0,e[2][2],e[3]}
    else compT(e[3],ops) ops[#ops+1]= {mkOp('inc'..e[4]),1,e[2][2]} end
  end
  _comp['and'] = function(e,ops) 
    compT(e[2],ops)
    local o1,z = {mkOp('ifnskip'),0,0}
    ops[#ops+1] = o1 -- true skip 
    z = #ops; ops[#ops+1]= POP; compT(e[3],ops); o1[3] = #ops-z+1
  end
  _comp['or'] = function(e,ops)  
    compT(e[2],ops)
    local o1,z = {mkOp('ifskip'),0,0}
    ops[#ops+1] = o1 -- true skip 
    z = #ops; ops[#ops+1]= POP; compT(e[3],ops); o1[3] = #ops-z+1;
  end
  _comp['progn'] = function(e,ops)
    if #e == 2 then compT(e[2],ops) 
    elseif #e > 2 then
      for i=2,#e-1 do compT(e[i],ops); ops[#ops+1]=POP end 
      compT(e[#e],ops)
    end
  end
  _comp['->'] = function(e,ops)
    local h,body,vars,f,code = e[2],e[3],{},{'progn',true},{}
    for i=1,#h do vars[i]=h[#h+1-i] end
    code[#code+1]={mkOp('fn'),#vars,vars}
    compT(body,code)
    ops[#ops+1]={mkOp('push'),0,code}
  end
  _comp['aref'] = function(e,ops) 
    compT(e[2],ops) 
    if isNum(e[3]) or isString(e[3]) then ops[#ops+1]={mkOp('aref'),1,e[3]}
    else compT(e[3],ops) ops[#ops+1]={mkOp('aref'),2} end
  end
  _comp['set'] = function(e,ops)
    local ref,val=e[2],e[3]
    local setF = type(ref)=='table' and ({var='setVar',glob='setGlob',aref='setRef',label='setLabel',slider='setSlider',prop='setProp'})[ref[1]]
    if setF=='setRef' or setF=='setLabel' or setF=='setProp' or setF=='setSlider' then -- ["setRef,["var","foo"],"bar",5]
      local expr,idx = ref[2],ref[3]
      compT(val,ops) compT(expr,ops)
      idx = setF=='setProp' and idx[2] or idx
      if isString(idx) or isNum(idx) then ops[#ops+1]={mkOp(setF),2,idx}
      else compT(idx,ops) ops[#ops+1]={mkOp(setF),3} end
    elseif setF=='setVar' or setF=='setGlob' then
      if isString(val) or isNum(val) then ops[#ops+1]={mkOp(setF),0,ref[2],val}
      else compT(val,ops) ops[#ops+1]={mkOp(setF),1,ref[2]} end
    else error({_format("trying to set illegal value '%s'",tojson(ref))}) end
  end
  _comp['%NULL'] = function(e,ops) compT(e[2],ops); ops[#ops+1]= POP; compT(e[3],ops) end

  function self.dump(code)
    code = code or {}
    for p = 1,#code do
      local i = code[p]
      Log(LOG.LOG,"%-3d:[%s/%s%s%s]",p,i[1],i[2] ,i[3] and ","..tojson(i[3]) or "",i[4] and ","..tojson(i[4]) or "")
    end
  end

  preC['progn'] = function(e) local r={'progn'}
    Util.map(function(p) 
        if type(p)=='table' and p[1 ]=='progn' then for i=2,#p do r[#r+1 ] = p[i] end
      else r[#r+1 ]=p end end
      ,e,2)
    return r
  end
  preC['if'] = function(e) local e1={'and',e[2],e[3]} return #e==4 and {'or',e1,e[4]} or e1 end
  preC['dolist'] = function(e) local var,list,expr,idx,lvar,LBL=e[2],e[3],e[4],{'var',gensym('fi')},{'var',gensym('fl')},gensym('LBL')
    e={'progn',{'set',idx,1},{'set',lvar,list},{'%addr',LBL}, -- dolist(var,list,expr)
      {'set',var,{'aref',lvar,idx}},{'and',var,{'progn',expr,{'set',idx,{'+',idx,1}},{'%jmp',LBL,0}}},lvar}
    return self.precompile(e)
  end
  preC['dotimes'] = function(e) local var,start,stop,step,body=e[2],e[3],e[4],e[5], e[6] -- dotimes(var,start,stop[,step],expr)
    local LBL = gensym('LBL')
    if body == nil then body,step = step,1 end
    e={'progn',{'set',var,start},{'%addr',LBL},{'if',{'<=',var,stop},{'progn',body,{'+=',var,step},{'%jmp',LBL,0}}}}
    return self.precompile(e)
  end
--  preC['>>'] = function(k,e) return self.precompile({'and',e[2],{'always',e[3]}}) end -- test >> expr |||| test >> expr ||| t >> expr
  preC['||'] = function(e) local c = {'and',e[2],{'always',e[3]}} return self.precompile(#e==3 and c or {'or',c,e[4]}) end
  preC['=>'] = function(e) return {'rule',{'quote',e[2]},{'quote',e[3]},{'quote',e[4]}} end
  preC['.'] = function(e) return {'aref',e[2],e[3]} end
  preC['neg'] = function(e) return isNum(e[2]) and -e[2] or e end
  preC['+='] = function(e) return {'inc',e[2],e[3],'+'} end
  preC['-='] = function(e) return {'inc',e[2],e[3],'-'} end
  preC['*='] = function(e) return {'inc',e[2],e[3],'*'} end
  preC['+'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])+tonumber(e[3]) or e end
  preC['-'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])-tonumber(e[3]) or e end
  preC['*'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])*tonumber(e[3]) or e end
  preC['/'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])/tonumber(e[3]) or e end
  preC['%'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])%tonumber(e[3]) or e end
  preC['time'] = function(e)
    if type(e[2])~='string' then return e end
    local tm,ts = e[2]:match("([tn%+]?)/?(.+)")
    if tm == "" or tm==nil then tm = '*' end
    if ts=='sunrise' or ts=='sunset' then return {'%time',ts,tm} end
    local date,h,m,s = ts:match("([%d/]+)/(%d%d):(%d%d):?(%d*)") 
    if date~=nil and date~="" then 
      local year,month,day=date:match("(%d+)/(%d+)/(%d+)")
      _assert(h and m and year and month and day,"malformed date constant '%s'",e[2])
      local t = osDate("*t") 
      t.year,t.month,t.day,t.hour,t.min,t.sec=year,month,day,h,m,((s~="" and s or 0) or 0)
      return {'%time',tm,osTime(t)}
    else
      local sg
      sg,h,m,s = ts:match("(%-?)(%d%d):(%d%d):?(%d*)")
      _assert(h and m,"malformed time constant '%s'",e[2])
      return {'%time',tm,(sg == '-' and -1 or 1)*(h*3600+m*60+(s~="" and s or 0))}
    end
  end 

  function self.precompile(e)
    local function traverse(e)
      if type(e)=='table' then
        if e[1]=='quote' then return e
        else 
          local pc = Util.mapkk(traverse,e)
          return preC[pc[1]] and preC[pc[1]](pc) or pc
        end
      else return e end
    end
    return traverse(e)
  end
  function self.compile(expr) local code = {} local prc = self.precompile(expr) compT(prc,code) return code end

  local _opMap = {['&']='and',['|']='or',['=']='set',[':']='prop',[';']='progn',['..']='betw', ['!']='not', ['@']='daily', ['@@']='schedule'}
  local function mapOp(op) return _opMap[op] or op end

  local function _binop(s,res) res.push({mapOp(s.pop().v),table.unpack(res.lift(2))}) end
  local function _unnop(s,res) res.push({mapOp(s.pop().v),res.pop()}) end
  local _prec = {
    ['*'] = 10, ['/'] = 10, ['%'] = 10, ['.'] = 12.5, ['+'] = 9, ['-'] = 9, [':'] = 12.6, ['..'] = 8.5, ['=>'] = -2, ['neg'] = 13, ['!'] = 6.5, ['@']=8.5, ['@@']=8.5,
    ['>']=7, ['<']=7, ['>=']=7, ['<=']=7, ['==']=7, ['~=']=7, ['&']=6, ['|']=5, ['=']=4, ['+=']=4, ['-=']=4, ['*=']=4, [';']=3.6, ['('] = 1, }

  for i,j in pairs(_prec) do _prec[i]={j,_binop} end 
  _prec['neg']={13,_unnop} _prec['!']={6.5,_unnop} _prec['@']={8.5,_unnop} _prec['@@']={8.5,_unnop}

  local _tokens = {
    {"^(%b'')",'string'},{'^(%b"")','string'},
    {"^%#([0-9a-zA-Z]+{?)",'event'},
    {"^({})",'symbol'},
    {"^({)",'lbrack'},{"^(})",'rbrack'},{"^(,)",'token'},
    {"^(%[)",'lsquare'},{"^(%])",'rsquare'},
    {"^%$([_0-9a-zA-Z\\$]+)",'gvar'},
    {"^([tn]/[sunriset]+)",'time'},
    {"^([tn%+]/%d%d:%d%d:?%d*)",'time'},{"^([%d/]+/%d%d:%d%d:?%d*)",'time'},{"^(%d%d:%d%d:?%d*)",'time'},    
    {"^:(%u+%d*)",'addr'},
    {"^(fn%()",'fun'}, 
    {"^(%()",'lpar'},{"^(%))",'rpar'},
    {"^([;,])",'token'},{"^(end)",'token'},
    {"^([_a-zA-Z][_0-9a-zA-Z]*)",'symbol'},
    {"^(%.%.)",'op'},{"^(->)",'op'},    
    {"^(%d+%.?%d*)",'num'},
    {"^(%|%|)",'token'},{"^(>>)",'token'},{"^(=>)",'token'},{"^(@@)",'op'},
    {"^([%%%*%+/&%.:~=><%|!@]+)",'op'},{"^(%-%=)",'op'},{"^(-)",'op'},
  }

  local _specT={bracks={['{']='lbrack',['}']='rbrack',[',']='token',['[']='lsquare',[']']='rsquare'},
    symbols={['end']='token'}}
  local function _passert(test,pos,msg,...) if not test then msg = _format(msg,...) error({msg,'at char',pos},3) end end

  local function tokenize(s) 
    local i,tkns,cp,s1,tp,EOF,org = 1,{},1,'',1,{t='EOF',v='<eol>',cp=#s},s
    repeat
      s1,s = s,s:match("^[^%w%p]*(.*)") --"^[%s%c]*(.*)")
      cp = cp+(#s1-#s)
      s = s:gsub(_tokens[ i ][ 1 ],
        function(m) local r,to = "",_tokens[i]
          if to[2]=='num' and m:match("%.$") then m=m:sub(1,-2); r ='.' -- hack for e.g. '7.'
          elseif m == '(' and #tkns>0 and tkns[#tkns ].t ~= 'fun' and tkns[#tkns ].v:match("^[%]%)%da-zA-Z]") then 
            m='call' to={1,'call'} 
          elseif m == '-' and (#tkns==0 or tkns[#tkns ].t=='call' or tkns[#tkns ].v:match("^[+%-*/({.><=&|;,@]")) then 
            m='neg' to={1,'op'} 
          end
          tkns[#tkns+1 ] = {t=to[2], v=m, cp=cp} i = 1 return r
        end
      )
      if s1 == s then i = i+1 _passert(i <= #_tokens,cp,"bad token '%s'",s) end
      cp = cp+(#s1-#s)
    until s:match("^[%s%c]*$")
    return { peek = function() return tkns[tp] or EOF end, nxt = function() tp=tp+1 return tkns[tp-1] or EOF end, 
      prev = function() return tkns[tp-2] end, push=function() tp=tp-1 end, str=org, atkns=tkns}
  end

  local function tmatch(str,t) _passert(t.peek().v==str,t.peek().cp,"expected '%s'",str) t.nxt() end
  local function tpeek(str,t) if t.peek().v==str then return t.nxt() else return false end end

  local pExpr = {}
  pExpr['lbrack'] = function(t,tokens,it) 
    local table,idx,tt=it or {},1
    if tokens.peek().t =='rbrack' then tokens.nxt() return {'%table',table} end
    repeat
      local el,key,val = self.expr(tokens)
      if type(el)=='table' and el[1]=='set' then key,val=el[2][2],el[3] else key,val=idx,el idx=idx+1 end
      table[key]=val
      local t = tokens.nxt() _passert(t.v==',' or t.v=='}',t and t.cp or tt.cp,"bad table")
    until t.v=='}'
    return {'%table',table}
  end
  pExpr['event'] = function(t,tokens) 
    if t.v:sub(-1,-1) ~= '{' then return {'quote',{type=t.v}} 
    else return pExpr['lbrack'](nil,tokens,{type=t.v:sub(1,-2)}) end
  end
  pExpr['fun'] = function(t,tokens) -- Fix!!!
    local args = {}
    if tokens.peek().t ~= 'rpar' then 
      repeat
        args[#args+1]=tokens.nxt().v 
        local t = tokens.nxt() _passert(t.v==',' or t.t=='rpar',t.cp,"bad function definition")
      until t.t=='rpar'
    else tokens.nxt() end
    local body = self.statements(tokens) tmatch("end",tokens)
    return {'->',args,body}
  end
  pExpr['num']=function(t,tokens) return tonumber(t.v) end
  pExpr['string']=function(t,tokens) return t.v:sub(2,-2) end
  pExpr['symbol']=function(t,tokens) local p = tokens.prev(); 
    if symbol[t.v] then return symbol[t.v][1] 
    elseif p and (p.v=='.' or p.v == ':') and p.t=='op' then 
      return t.v 
    else return {'var',t.v} end 
  end
  pExpr['gvar'] = function(t,tokens) return {'glob',t.v} end
  pExpr['addr'] = function(t,tokens) return {'%addr',t.v} end
  pExpr['time'] = function(t,tokens) return {'time',t.v} end

  function self._dtokens(tokens) for _,t in ipairs(tokens.atkns) do printf("%s, %s, %s",t.t,t.v,t.cp) end end

  function self.expr(tokens)
    local s,res = Util.mkStack(),Util.mkStack()
    while true do
      local t,tsq = tokens.peek(),nil
      if t.t=='EOF' or t.t=='token' or t.v == '}' or t.v == ']' then
        while not s.isEmpty() do _prec[s.peek().v][2](s,res) end
        _passert(res.size()==1,t and t.cp or 1,"bad expression")
        return res.pop()
      end
      tokens.nxt()
      if t.t == 'lsquare' then 
        tsq=self.expr(tokens) t = tokens.nxt()
        _passert(t.t =='rsquare',t.cp,"bad index [] operator")
        t = {t='op',v='.',cp=t.cp}
      end
      if t.t=='op' then
        if s.isEmpty() then s.push(t); if tsq then res.push(tsq) end
      else
        while (not s.isEmpty()) do
          local p1,p2 = _prec[t.v][1], _prec[s.peek().v][1] p1 = t.v=='=' and 11 or p1
          if s.peek().v=='.' then p2=p2+.2 end
          if p2 >= p1 then _prec[s.peek().v][2](s,res) else break end
        end
        s.push(t); if tsq then res.push(tsq) end
      end
    elseif t.t == 'call' then
      local args,fun = {}
      if tokens.peek().t ~= 'rpar' then 
        repeat
          args[#args+1]=self.expr(tokens)
          local t = tokens.nxt() _passert(t.v==',' or t.t=='rpar',t.cp,"bad function call")
        until t.t=='rpar'
      else tokens.nxt() end
      while (not s.isEmpty()) and _prec[s.peek().v][1] > 11 do _prec[s.peek().v][2](s,res) end
      fun = res.pop()
      if isVar(fun) and isBuiltin(fun[2]) then res.push({fun[2],table.unpack(args)})
      else res.push({'apply',fun,args}) end
    elseif t.t == 'lpar' then s.push(t)
    elseif t.t== 'rpar' then
      while not s.isEmpty() and s.peek().t ~= 'lpar' do _prec[s.peek().v][2](s,res) end
      if s.isEmpty() then tokens.push(t) return res.pop() end
      s.pop()
    elseif pExpr[t.t] then res.push(pExpr[t.t](t,tokens))
    else
      res.push(t.v) -- symbols, constants etc
    end
  end
end

function self.parse(s)
  local t = tokenize(s)
  local status,res = pcall(function()
      if tpeek("def",t) then
        _assert(false,"'def' not implemented yet")
      else
        if t.peek().v=='||' then return self.statements(t) end
        local e = self.expr(t)
        return tpeek("=>",t) and {"=>",e,self.statements(t),t.str} or self.statements(t,e)
      end
    end)
  if status then return res 
  else 
    res = type(res) == 'string' and {res} or res
    errThrow(_format(" parsing '%s'",s),res)
  end
end

function self.statements(t,ie)
  local e = {'progn',ie or self.statement(t)}
  while tpeek(";",t) and t.peek().v~=';' do e[#e+1]=self.statement(t) end
  return #e>2 and e or e[2]
end

function self.statement(t)
  if tpeek('||',t) then 
    local c,a=self.expr(t) 
    tmatch(">>",t)
    a=self.statements(t)
    return {'||',c,a,t.peek().v=='||' and self.statement(t) or nil}
  else return self.expr(t) end
end

return self
end
ScriptCompiler = newScriptCompiler()

--------- RuleCompiler ------------------------------------------
local rCounter=0
function newRuleCompiler()
  local self = {}
  local map,mapkl=Util.map,Util.mapkl
  local _macros,_dailys,rCounter= {},{},0
  local tProps ={value=1,isOn=1,isOff=1,isAnyOff=1,isAllOn=1,last=1,safe=1,breached=1,scene=2,power=3,bat=4,trigger=1,dID=7,toggle=1,lux=1,temp=1,manual=1,central=5,access=6}
  local tPropsV = {[1]='value',[2]='sceneActivation',[3]='power',[4]='batteryLevel',[5]='CentralSceneEvent',[6]='AccessControlEvent',[7]='$prop'}
  local lblF=function(id,e) return {type='property', deviceID=id, propertyName=_format("ui.%s.value",e[3])} end
  local triggFuns={
    label=lblF,slider=lblF
  }

  local gtFuns = {
    ['daily'] = function(e,s) s.dailys[#s.dailys+1 ]=ScriptCompiler.compile(e[2]) s.dailyFlag=true end,
    ['schedule'] = function(e,s) s.scheds[#s.scheds+1 ] = ScriptCompiler.compile(e[2]) end,
    ['betw'] = function(e,s) 
      s.dailys[#s.dailys+1 ]=ScriptCompiler.compile(e[2])
      s.dailys[#s.dailys+1 ]=ScriptCompiler.compile({'+',1,e[3]}) 
    end,
    ['glob'] = function(e,s) s.triggs[e[2] ] = {type='global', name=e[2]} end,
    ['var'] = function(e,s) if e[2]:sub(1,1)=="_" then s.triggs[e[2] ] = {type='variable', name=e[2]} end end,
    ['set'] = function(e,s) if isTriggerVar(e[2]) or isGlob(e[2]) then error("Can't assign variable in rule header") end end,
    ['prop'] = function(e,s) 
      local pn = tProps[e[3]] and tPropsV[tProps[e[3]]] or e[3]
      local cv = ScriptCompiler.compile(e[2])
      local v = ScriptEngine.eval(cv)
      map(function(id) s.triggs[id..pn]={type='property', deviceID=id, propertyName=pn} end,type(v)=='table' and v or {v})
    end,
  }

  local function nestOr(t,p) if t[p+1]==nil then return t[p] else return {'or',t[p],nestOr(t,p+1)} end end

  local function getTriggers(e)
    local s={triggs={},dailys={},scheds={},dailyFlag=false,eventFlag=false}
    local function traverse(e)
      if type(e)=='table' and e[1]== '%eventmatch' then -- {'%eventmatch',{'quote', ce1,cep,id}} 
        local ep,ce,id = e[2][3],e[2][2],e[2][4]
        if id then s.triggs[id]=ce 
        else s.triggs[tojson(ce)] = ce end 
        s.eventFlag=true
      elseif type(e) =='table' then
        Util.mapkk(traverse,e)
        if gtFuns[e[1]] then gtFuns[e[1]](e,s)
        elseif triggFuns[e[1]] then
          local cv = ScriptCompiler.compile(e[2])
          local v = ScriptEngine.eval(cv)
          map(function(id) s.triggs[id]=triggFuns[e[1]](id,e) end,type(v)=='table' and v or {v})
        end
      end
    end
    traverse(e)
    return mapkl(function(k,v) return v end,s.triggs),s.dailys,s.scheds,s.dailyFlag,s.eventFlag
  end

  function self.test(s) return {getTriggers(ScriptCompiler.parse(s))} end
  function self.define(name,fun) ScriptEngine.define(name,fun) end
  function self.addTrigger(name,instr,gt) ScriptEngine.addInstr(name,instr) triggFuns[name]=gt end

  local function compTimes(cs)
    local t1,t2=map(function(c) return ScriptEngine.eval(c) end,cs),{}
    _transform(t1,function(t) t2[t]=true end)
    return mapkl(function(k,v) return k end,t2)
  end

  local CATCHUP = math.huge
  local RULEFORMAT = "Rule:%s:%."..(_ruleLogLength or 40).."s"

  -- #property{deviceID={6,7} & 6:isOn => .. generates 2 triggers for 6????
  function _remapEvents(obj)
    if isTEvent(obj) then 
      local ce = ScriptEngine.eval(ScriptCompiler.compile(obj))
      if ce.type == 'property' and type(ce.deviceID)=='table' then
        if #ce.deviceID> 0 then
          local ss =Util.map(function(id) 
              local ce1,cep = _copy(ce); ce1.deviceID=id
              cep = _copy(ce1); Event._compilePattern(cep)
              return {'%eventmatch',{'quote', ce1,cep,id}} 
            end,ce.deviceID)
          ss = nestOr(ss,1)
          return ss
        end
      end
      local cep = _copy(ce)
      Event._compilePattern(cep)
      return {'%eventmatch',{'quote',ce,cep}}
    elseif type(obj) == 'table' then
      local res = {} for l,v in pairs(obj) do res[l] = _remapEvents(v,tf) end 
      return res
    else return obj end
  end

  function self.compRule(e,env)
    local h,body,events,res,ctx,times,sdaily = e[2],e[3],{},{},{src=env.src,line=env.line}
    h = _remapEvents(h)  -- fix #events in header
    local triggs,dailys,scheds,dailyFlag,eventFlag = getTriggers(h)
    if #triggs==0 and #dailys==0 and #scheds==0 then 
      error(_format("no triggers found in rule '%s'%s",ctx.src,_LINEFORMAT(ctx.line)))
    end
    local code,action = ScriptCompiler.compile({'and',(_debugFlags.rule or _debugFlags.ruleTrue) and {'logRule',h,ctx.src} or h,body})
    action = function(env) return ScriptEngine.eval(code,env) end
    if #scheds>0 then
      local sevent={type=Util.gensym("INTERV")}
      events[#events+1] = Event.event(sevent,action,nil,ctx); events[#events].ctx=ctx
      sevent._sh=true
      local timeVal,skip = osTime(),ScriptEngine.eval(scheds[1])
      if timeVal<0 then timeVal=-timeVal; skip = timeVal end
      local function interval()
        Event.post(sevent)
        timeVal = timeVal+math.abs(ScriptEngine.eval(scheds[1]))
        setTimeout(interval,1000*(timeVal-osTime()))
      end
      setTimeout(interval,1000*(skip < 0 and -skip or 0))
    else
      local m,ot,catchup1,catchup2=midnight(),osTime()
      if #dailys > 0 then
        local devent,dtimers={type=Util.gensym("DAILY"),_sh=true},{}
        sdaily={dailys=dailys,event=devent,timers=dtimers}
        _dailys[#_dailys+1] = sdaily
        events[#events+1]=Event.event(devent,action,nil,ctx); events[#events].ctx=ctx; 
        times = compTimes(dailys)
        for i,t in ipairs(times) do _assert(tonumber(t),"@time not a number:%s",t)
          if t ~= CATCHUP then
            if t+m >= ot then dtimers[#dtimers+1]=Event.post(devent,t+m) else catchup1=true end
          else catchup2 = true, table.remove(dailys,i) end
        end
        if catchup2 and catchup1 then Log(LOG.LOG,"Cathing up:%s",ctx.src); Event.post(devent) end
      end
      if not dailyFlag and #triggs > 0 then -- id/glob trigger or events
        for _,tr in ipairs(triggs) do 
            if tr.propertyName~='$prop' then
              events[#events+1]=Event.event(tr,action,nil,ctx); events[#events].ctx=ctx
            end
        end
      end
    end
    res=Event._mkCombEvent(ctx.src,ctx.src,action,events)
    res.dailys,res.ctx = sdaily,ctx
    if sdaily then sdaily.rule=res end
    res._code = code
    res.print = function()
      Util.map(function(d) Log(LOG.LOG,"Interval(%s) =>...",time2str(d)) end,compTimes(scheds)) 
      Util.map(function(d) Log(LOG.LOG,"Daily(%s) =>...",d==CATCHUP and "catchup" or time2str(d)) end,compTimes(dailys)) 
      Util.map(function(tr) Log(LOG.LOG,"Trigger(%s) =>...",tojson(tr)) end,triggs)
    end
    rCounter=rCounter+1
    Log(LOG.SYSTEM,RULEFORMAT,rCounter,ctx.src:match("([^%c]*)"))
    return res
  end

-- context = {log=<bool>, level=<int>, line=<int>, doc=<str>, trigg=<bool>, enable=<bool>}
  function self.eval(escript,log,ctx)
    ctx = ctx or {src=escript, line=_LINE()}
    ctx.src,ctx.line = ctx.src or escript, ctx.line or _LINE()
    local status, res = pcall(function() 
        local expr = self.macroSubs(escript)
        local res = ScriptCompiler.parse(expr)
        res = ScriptCompiler.compile(res)
        res = ScriptEngine.eval(res,ctx) -- ctx is like an environment...
        if log then Log(LOG.LOG,"%s = %s",escript,tojson(res)) end
        return res
      end)
    if not status then errThrow(_format("Error evaluating '%s'%s",ctx.src,_LINEFORMAT(ctx.line)),res)
    else return res end
  end

  function self.load(rules,log)
    local function splitRules(rules)
      local lines,cl,pb,cline = {},math.huge,false,""
      if not rules:match("([^%c]*)\r?\n") then return {rules} end
      rules:gsub("([^%c]*)\r?\n?",function(p) 
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
    map(function(r) self.eval(r,log,{src=r,level=_LINE()}) end,splitRules(rules))
  end

  function self.macro(name,str) _macros['%$'..name..'%$'] = str end
  function self.macroSubs(str) for m,s in pairs(_macros) do str = str:gsub(m,s) end return str end

  function self.restartDaily(r)
    if not r.dailys then return end
    local dailys,dtimers = r.dailys,{}
    for _,t in ipairs(dailys.timers or {}) do Event.cancel(t) end
    dailys.timers = dtimers
    local times,m,ot = compTimes(dailys.dailys),midnight(),osTime()
    for _,t in ipairs(times) do
      if t+m >= ot then 
        Debug(_debugFlags.dailys,"Rescheduling daily %s at %s",r._name or "",osDate("%c",t+m)); 
        dtimers[#dtimers+1]=Event.post(dailys.event,t+m) 
      end
    end
  end

  Event.schedule("n/00:00",function(env)  -- Scheduler that every night posts 'daily' rules
      _DSTadjust = os.date("*t").isdst and -60*60 or 0
      local midnight = midnight()
      for _,d in ipairs(_dailys) do
        d.timers={}
        local times,dt = compTimes(d.dailys)
        for _,t in ipairs(times) do
          if _debugFlags.dailys then Debug(true,"Scheduling daily %s at %s",d.rule._name or "",osDate("%c",midnight+t)) end
          if t==0 then dt=Event.post(d.event) else dt=Event.post(d.event,midnight+t) end
          d.timers[#d.timers+1]=dt
        end
      end
    end)

  return self
end
Rule = newRuleCompiler()

---------------- Extra setup ----------------

local function makeDateInstr(f)
  return function(s,n,e,i)
    local ts = s.pop()
    if ts ~= i[5] then i[6] = Util.dateTest(f(ts)); i[5] = ts end -- cache fun
    s.push(i[6]())
  end
end
ScriptEngine.addInstr("date",makeDateInstr(function(s) return s end))             -- min,hour,days,month,wday
ScriptEngine.addInstr("day",makeDateInstr(function(s) return "* * "..s end))      -- day('1-31'), day('1,3,5')
ScriptEngine.addInstr("month",makeDateInstr(function(s) return "* * * "..s end))  -- month('jan-feb'), month('jan,mar,jun')
ScriptEngine.addInstr("wday",makeDateInstr(function(s) return "* * * * "..s end)) -- wday('fri-sat'), wday('mon,tue,wed')

-- Support for CentralSceneEvent & WeatherChangedEvent
_lastEID = {CentralSceneEvent={}, AccessControlEvent={}}
Event.event({type='event', event={type='$t', data='$data'}}, 
  function(env) 
    local t = env.p.t
    if _lastEID[t] then
      local id = Util.getIDfromEvent[t](env.p.data)
      if not id then return end
      env.p.data.timestamp=osTime()
      _lastEID[t][id]=env.p.data
      Event.post({type='property',deviceID=id,propertyName=t, value=env.p.data, _sh=true})
    end
  end)

_lastWeatherEvent = {}
Event.event({type='WeatherChangedEvent'}, 
  function(env) _lastWeatherEvent[env.event.data.change] = env.event.data; _lastWeatherEvent['*'] = env.event.data end)
Rule.addTrigger('weather',
  function(s,n,e,i) local k = n>0 and s.pop() or '*'; return s.push(_lastWeatherEvent[k]) end,
  function(id) return {type='WeatherChangedEvent',data={changed=id}} end)

Event.event({type=Event.PING},function(env) e=env.event;e.type=Event.PONG; Event.postRemote(e._from,e) end)

--- SceneActivation constants
Util.defvar('S1',Util.S1)
Util.defvar('S2',Util.S2)
Util.defvar('catch',math.huge)
Util.defvar("defvars",Util.defvars)
Util.defvar("mapvars",Util.reverseMapDef)

---------------------- Hue support, can be removed if not needed -------------------------
function hueSetup(cont)
  local _defaultHubName = "Hue"
  function makeHue()
    local self, devMap, hueNames = { hubs={} }, {}, {}
    local HTTP = net.HTTPClient()
    function self.isHue(id) return devMap[id] and devMap[id].hue end
    function self.name(n) return hueNames[n] end   
    function self.connect(name,user,ip,cont)
      self.hubs[name]=makeHueHub(name,user,ip,cont)
    end
    function self.hueName(hue) --Hue1﻿:SensorID=1
      local name,t,id=hue:match("(%w+):(%a+)=(%d+)")
      local dev = ({SensorID='sensors',LightID='lights',GroupID='groups'})[t]
      return name..":"..self.hubs[name][dev][tonumber(id)].name 
    end
    function self.request(url,cont,op,payload)
      op,payload = op or "GET", payload and json.encode(payload) or ""
      Debug(_debugFlags.hue,"Hue req:%s Payload:%s",url,payload)
      HTTP:request(url,{
          options = {headers={['Accept']='application/json',['Content-Type']='application/json'},
            data = payload, timeout=2000, method = op},
          error = function(status) error("Hue connection:"..tojson(status)) end,
          success = function(status) if cont then cont(json.decode(status.data)) end end
        })
    end

    function self.dump() for _,h in pairs(self.hubs) do h.dump() end end
    local function find(name) -- find a Hue device in any of the connected Hue hubs we have, name is <hub>:<name>
      local hname,dname=name:match("(.*):(.*)")
      local hub = self.hubs[hname]
      return hub.lights[dname] or hub.groups[dname] or hub.sensors[dname],hname
    end

    local mapIndex=10000 -- start mapping at deviceID 10000
    --devMap[deviceID] -> {hub, type, hue}
    function self.define(name,var,id) -- optional var
      if id ==nil then id = mapIndex; mapIndex=mapIndex+1 else id =tonumber(id) end
      if not name:match(":") then name=_defaultHubName..":"..name end -- default to Hue:<name>
      hueNames[name]=id
      local hue,hub = find(name) 
      if hue then devMap[id] = {type=hue.type,hue=hue,hub=self.hubs[hub]}; hue.fid=id    
      else error("No Hue name:"..name) end
      if Util and var then Util.defvar(var,id) end
      Log(LOG.LOG,"Hue device '%s' assigned deviceID %s",name,id)
      return id
    end

    function self.monitor(name,interval,filter)
      if type(name)=='table' then Util.mapF(function(n) self.monitor(n,interval,filter) end, name) return end
      if type(name) == 'string' and not name:match(":") then name = _defaultHubName..":"..name end
      local id = hueNames[name] or name -- name could be deviceID
      local sensor = devMap[id]
      sensor.hub.monitor(sensor.hue,interval,filter)
    end

    function self.rgb2xy(r,g,b)
      r,g,b = r/254,g/254,b/254
      r = (r > 0.04045) and ((r + 0.055) / (1.0 + 0.055)) ^ 2.4 or (r / 12.92)
      g = (g > 0.04045) and ((g + 0.055) / (1.0 + 0.055)) ^ 2.4 or (g / 12.92)
      b = (b > 0.04045) and ((b + 0.055) / (1.0 + 0.055)) ^ 2.4 or (b / 12.92)
      local X = r*0.649926+g*0.103455+b*0.197109
      local Y = r*0.234327+g*0.743075+b*0.022598
      local Z = r*0.0000000+g*0.053077+b*1.035763
      return X/(X+Y+Z), Y/(X+Y+Z)
    end

    function self.turnOn(id) local d,h=devMap[id].hue,devMap[id].hub 
      self.request(_format(d.url,d.id),h.updateState,"PUT",{on=true}) h._setState(d,'on',true) 
    end
    function self.turnOff(id) local d,h=devMap[id].hue, devMap[id].hub
      self.request(_format(d.url,d.id),h.updateState,"PUT",{on=false}) h._setState(d,'on',false) 
    end
    function self.setColor(id,r,g,b,w) local d,h,x,y=devMap[id].hue,devMap[id].hub,self.rgb2xy(r,g,b); 
      local pl={xy={x,y},bri=w and w/99*254}
      self.request(_format(d.url,d.id),h.updateState,"PUT",pl) h._setState(d,pl) 
    end
    function self.setValue(id,val) local d,h,payload=devMap[id].hue, devMap[id].hub
      if type(val)=='string' and not tonumber(val) then payload={scene=d.scenes[val] or val}
      elseif tonumber(val)==0 then payload={on=false} 
      elseif tonumber(val) then payload={on=true,bri=math.floor((val/99)*254)}
      elseif type(val)=='table' then
        if val.startup then
          local lights = d.lights and #d.lights>0 and d.lights or {d.id}
          for _,id in ipairs(lights) do
            local d = h.lights[tonumber(id)]
            local url = (d.url:match("(.*)/state")).."/config/startup/"
            payload=val
            self.request(_format(url,d.id),nil,"PUT",payload)
          end
          return
        else payload=val end
      end
      if payload then self.request(_format(d.url,d.id),h.updateState,"PUT",payload) h._setState(d,payload)
      else  error(_format("Hue setValue id:%s value:%s",id,val)) end
    end

    return self
  end

  Hue=makeHue() -- create global Hue object
--[[
  _HueHubs = {{name="Hub1",user="hghgjhT6TUG", ip="192.168.1.50"}}
  Hue.define("Hub1:my Light","light",890)
--]]
  if _HueHubs then
    local c = cont
    cont = function() Log(LOG.LOG,"Hue system inited (experimental)") c() end
    if _HueHubs and #_HueHubs==1 then _defaultHubName=_HueHubs[1].name end
    for _,hub in ipairs(_HueHubs or {}) do
      local c,h = cont,hub
      cont = function() Hue.connect(h.name,h.user,h.ip,c) end
    end
  end

  Event.event({type='property',propertyName='on',_hue=true},
    function(env) -- transform 'on' events
      local e=env.event
      Event.post({type='property',deviceID=e.deviceID,propertyName='value',value=fibaro:getValue(e.deviceID,'value'),_sh=true})
    end)
--  Event.event({type='property', propertyName='buttonevent', value='$val', _hue=true},
--    function(env) -- transform 'buttonevent' to CentralSceneEvents
--      local e = env.event
--      local keyId = math.floor(env.p.val/1000)
--      local state = Hue.isHue(e.deviceID).state
--      state.buttonevent=nil
--      local keyAttr = ({'Down','Hold','Down/Released','Released'})[env.p.val % 1000 + 1]
--      Event.post({type='event',event={type='CentralSceneEvent',data={deviceId=e.deviceID,keyId=keyId,keyAttribute=keyAttr}}})
--    end)

  local function mapFib(f,fun)
    local fm = fibaro._orgf or fibaro
    local ofc = fm[f]
    fm[f] = function(obj,id,...)
      if not Hue.isHue(id) then return ofc(obj,id,...) else return fun(obj,id,...) end 
    end
  end
  mapFib('call',function(obj,id,...)
      local val,params=({...})[1],{select(2,...)}
      if Hue[val] then Hue[val](id,table.unpack(params)) end
    end)
  mapFib('get',function(obj,id,...)
      local val,res,dev,time=({...})[1],nil,Hue.isHue(id)
      if val=='value' then 
        if dev.state.on and (dev.state.reachable==nil or  dev.state.reachable==true) then 
          res = dev.state.bri and tostring(math.floor((dev.state.bri/254)*99+0.5)) or '99' 
        else res = '0' end 
      elseif val=='values' then res = dev.state
      else res =  dev.state[val] and tostring(dev.state[val]) or nil end
      time=dev.state.lastupdate or 0
      Debug(_debugFlags.hue,"Get ID:%s %s -> %s",id,val,res)
      return res and res,time
    end)
  mapFib('getValue',function(obj,id,...) return (fibaro.get(obj,id,...)) end)

  cont()
end

function makeHueHub(name,username,ip,cont)
  local lights,groups,scenes,sensors = {},{},{},{},{}
  local self = {lights=lights,groups=groups,scenes=scenes,sensors=sensors}
  local hubName,baseURL=name,"http://"..ip..":80/api/"..username.."/"
  local lightURL = baseURL.."lights/%s/state"
  local groupURL = baseURL.."groups/%s/action"
  local sensorURL = baseURL.."sensors/%s"
  function self._setState(hue,prop,val,upd)
    if type(prop)=='table' then 
      for k,v in pairs(prop) do self._setState(hue,k,v,upd) end
      return
    end
    local change,id = hue.state[prop]~=nil and hue.state[prop] ~= val, hue.fid
    hue.state[prop],hue.state['lastupdate']=val,osTime()
    local filter = id and hue._filter
    if change and id and filter and filter[prop] then 
      Event.post({type='property',deviceID=id,propertyName=prop,value=val,_hue=true,_sh=_debugFlags.hue}) 
    end
    --Log(LOG.LOG,"Name:%s, PROP:%s, VAL:%s",hue.name,tojson(prop),tojson(val))
    if (not upd) and hue.lights then -- for groups
      for _,id in ipairs(hue.lights) do self._setState(lights[tonumber(id)],prop,val,upd) end 
    end
  end
  function self.updateState(state) -- partial state
    for _,s in ipairs(state[1] and state or {}) do
      if s.success then 
        for p,v in pairs(s.success) do 
          local tp,id,mt,prop = p:match("/(%a+)/(%d+)/(%a+)/(.*)")
          if id then self._setState(self[tp][ tonumber(id) ],prop,v)
          else Log(LOG.LOG,"Unknown Hue state %s %s",p,v) end
        end --for 
      end -- if
    end --for
  end --fun
  local function setFullState(devices,id,d,state,t,url)
    local dd = devices[d.name] or {name=d.name,id=tonumber(id), state={}, type=t, url=url,lights=d.lights, scenes={}}
    devices[d.name],devices[tonumber(id)]=dd,dd
    self._setState(dd,d[state],nil,true)
  end
  function match(t1,t2) if #t1~=#t2 then return false end; for i=1,#t1 do if t1[i]~=t2[i] then return false end end return true end
  function self.getFullState(f)
    Hue.request(baseURL,function(data)
        for id,d in pairs(data.sensors) do setFullState(sensors,id,d,'state','sensor',sensorURL) end
        for id,d in pairs(data.lights) do setFullState(lights,id,d,'state','light',lightURL) end
        for id,d in pairs(data.groups) do table.sort(d.lights) setFullState(groups,id,d,'action','group',groupURL) end
        for id,d in pairs(data.scenes) do if d.version>1 then 
          scenes[d.name] = id; table.sort(d.lights)
          for _,g in pairs(groups) do if match(g.lights,d.lights) then g.scenes[d.name]=id end end
        end end
        if f then f() end
      end)
  end
  local _defFilter={buttonevent=true, on=true}
  function self.monitor(sensor,interval,filter)
    local url = sensor.url:sub(#baseURL+1)
    url=baseURL.._format(url:match("(.-/)").."%s",sensor.id)
    sensor._filter = filter or sensor._filter or _defFilter
    if sensor._timer then clearTimeout(sensor._timer) sensor._timer=nil end
    if interval>0 then 
      local function poll() 
        Hue.request(url,function(state) self._setState(sensor,state.state) setTimeout(poll,interval) end)
      end
      poll()
    end
  end
  function self.dump()
    Log(LOG.LOG,"%s------------ Hue Lights ---------------------",name)
    for k,v in pairs(lights) do if not tonumber(k) then Log(LOG.LOG,"Light '%s' id=%s",k,json.encode(v.id)) end end
    Log(LOG.LOG,"%s------------- Hue Groups ---------------------",name)
    for k,v in pairs(groups) do if not tonumber(k) then Log(LOG.LOG,"Group '%s' id=%s",k,json.encode(v.id)) end end
    Log(LOG.LOG,"%s------------- Hue Scenes ---------------------",name)
    for k,v in pairs(scenes) do Log(LOG.LOG,"Scene '%s' id=%s",k,v) end
    Log(LOG.LOG,"%s------------- Hue Sensors ---------------------",name)
    for k,v in pairs(sensors) do if not tonumber(k) then Log(LOG.LOG,"Sensor '%s' id=%s",k,json.encode(v.id)) end end
    Log(LOG.LOG,"----------------------------------------------")
  end
  Hue.hubs[name]=self -- hack
  self.getFullState(cont)
  return self
end

---------------------- Startup -----------------------------    
if _type == 'autostart' or _type == 'other' then
  Log(LOG.WELCOME,_format("%sEventRunner v%s %s",_sceneName and (_sceneName.." - " or ""),_version,_fix))

  if not _OFFLINE then
    local info = api.get("/settings/info")
    Log(LOG.LOG,"Fibaro software version: %s",info.currentVersion.version)
    Log(LOG.LOG,"HC2 uptime: %s hours",math.floor((os.time()-info.serverStatus)/3600))
    if not string.find(json.encode((api.get("/globalVariables/"))),"\"".._MAILBOX.."\"") then
      api.post("/globalVariables/",{name=_MAILBOX}) 
    end
  end 

  if _GUI and _OFFLINE then Log(LOG.LOG,"GUI enabled") end
  Log(LOG.LOG,"Sunrise %s, Sunset %s",fibaro:getValue(1,'sunriseHour'),fibaro:getValue(1,'sunsetHour'))
  if _OFFLINE and not _ANNOUNCEDTIME then 
    Log(LOG.LOG,"Starting:%s, Ending:%s %s",osDate("%x %X",osTime()),osDate("%x %X",osETime()),_SPEEDTIME and "(speeding)" or "") 
  end

  GC = 0
  function setUp()
    if _OFFLINE and _GLOBALS then Util.defineGlobals(_GLOBALS) end
    Log(LOG.SYSTEM,"") Log(LOG.SYSTEM,"Loading rules")
    if _ALTERNATIVEMAIN then main = _ALTERNATIVEMAIN end
    local status, res = pcall(function() return main() end)
    if not status then 
      Log(LOG.ERROR,"Error loading rules:%s",type(res)=='table' and table.concat(res,' ') or res) fibaro:abort() 
    end

    _trigger._sh = true
    Event.post(_trigger)

    Log(LOG.SYSTEM,"") Log(LOG.SYSTEM,"Scene running")
    collectgarbage("collect") GC=collectgarbage("count")
  end

  local function chainStartup() if hueSetup then return hueSetup(setUp) else return setUp() end end

  if not _OFFLINE then 
    fibaro:setGlobal(_MAILBOX,"") 
    _poll()  -- start polling mailbox
    chainStartup()
  else 
    _System.runOffline(chainStartup) 
  end
end