--[[
%% properties
%% events
%% globals
%% autostart
--]]

_version = "1.3"  

--[[
-- EventRunner. Event based scheduler/device trigger handler
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_sceneName   = "Cron Service"        -- Set to scene/script name
_debugFlags = { post=false,invoke=false,triggers=false,dailys=false,timers=false,rule=false,fibaro=true,fibaroGet=false, fibaroSet=false }
_deviceTable = "deviceTable" -- Name of json struct with configuration data (i.e. "HomeTable")
ruleLogLength = 80

Event = {}
-- If running offline we need our own setTimeout and net.HTTPClient() and other fibaro funs...
if dofile then dofile("EventRunnerDebug.lua") end

---------------- Event/Rule decalarations --------------------
function main()
  callbacks={}

  Event.event({type='add',time='$time',callback='$call'},
    function(env)
      if env.event._first then
        local cb = {}
        for _,e in ipairs(callbacks) do
          if e.scene~=env.event._from then cb[#cb+1]=e end
        end
        if #cb~=#callbacks then
          Log(LOG.LOG,"Removing old callbacks from %s",env.event._from)
          callbacks=cb
        end
      end
      Log(LOG.LOG,"Registering %s from %s",env.p.time,env.event._from)
      local status,res = pcall(function()
          local e = {id=id,scene=env.event._from,test=Util.dateTest(env.p.time),time=env.p.time,callback=env.p.call}
          callbacks[#callbacks+1]=e
        end)
      if not status then env.event.type='error'; Event.postRemote(env.event._from,env.event) end
    end)

  Event.event({type='loop',last='$last'},
    function(env)
      for _,e in ipairs(callbacks) do
        if e.test() then
          fibaro:debug("T:"..#callbacks)
          Event.post({type='send',scene=e.scene,callback=e.callback}) 
        end
      end
      local last=env.event.last+60
      env.event.last=last
      Event.post(env.event,last)
    end)

  Event.post({type='loop',last=osTime()+60},"+/00:01")

  Event.event({type='send'},
    function(env)
      Log(LOG.LOG,"Scene:%s Callback:%s",env.event.scene,json.encode(env.event.callback))
      Event.postRemote(env.event.scene,{type='callback',callback=env.event.callback})
    end)

end -- main()

------------------- EventModel - Don't change! --------------------  
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
LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ERROR = "Tomato"}
_format = string.format
if not _getIdProp then
  _getIdProp = function(id,prop) return fibaro:get(id,prop) end; _getGlobal = function(id) return fibaro:getGlobal(id) end
end
Util = Util or {}

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
  function _setClock(_) end
  function _setMaxTime(_) end
  function Debug(flag,message,...) if flag then _Msg(LOG.DEBUG,message,...) end end
  function Log(color,message,...) return _Msg(color,message,...) end
end

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

function midnight() local t = osDate("*t"); t.hour,t.min,t.sec = 0,0,0; return osTime(t) end

function hm2sec(hmstr)
  local offs,sun
  sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
  if sun and (sun == 'sunset' or sun == 'sunrise') then
    hmstr,offs = fibaro:getValue(1,sun.."Hour"), tonumber(offs) or 0
  end
  local sg,h,m,s = hmstr:match("(%-?)(%d+):(%d+):?(%d*)")
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

  local function _compilePattern(pattern)
    if type(pattern) == 'table' then
      if pattern._var_ then return end
      for k,v in pairs(pattern) do
        if type(v) == 'string' and v:sub(1,1) == '$' then
          local var,op,val = v:match("$([%w_]*)([<>=~]*)([+-]?%d*%.?%d*)")
          var = var =="" and "_" or var
          local c = _constraints[op](tonumber(val))
          pattern[k] = {_var_=var, _constr=c, _str=v}
        else _compilePattern(v) end
      end
    end
  end

  local function _match(pattern, expr)
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
        for k,v in pairs(pattern) do if not _unify(v,expr[k]) then return false end end
        return true
      else return false end
    end
    return _unify(pattern,expr) and matches or false
  end

  local function ruleError(res,src,def)
    res = type(res)=='table' and table.concat(res,' ') or res
    src = src or def
    Log(LOG.ERROR,"Error in '%s': %s",src,res)
  end

  function self._callTimerFun(e,src)
    local status,res = pcall(e) 
    if not status then ruleError(res,src,"timer fun") end
  end

  function self.post(e,time,src) -- time in 'toTime' format, see below.
    _assert(isEvent(e) or type(e) == 'function', "Bad2 event format %s",tojson(e))
    time = toTime(time or osTime())
    if time < osTime() then return nil end
    if type(e) == 'function' then 
      Debug(_debugFlags.post,"Posting %s for %s",src or tostring(e),osDate("%a %b %d %X",time))
      return {[self.TIMER]=setTimeout(function() self._callTimerFun(e,src) end, 1000*(time-osTime()))}
    end
    Debug(_debugFlags.post and not e._sh,"Posting %s for %s",function() return tojson(e),osDate("%a %b %d %X",time) end)
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
    fibaro:startScene(sceneID,{urlencode(json.encode(e))})
  end

  local _getProp = {}
  _getProp['property'] = function(e,v2)
    e.propertyName = e.propertyName or 'value'
    local id = e.deviceID
    local v,t = _getIdProp(id,e.propertyName,true)
    e.value = v2 or v
    self.trackManual(id,e.value)
    return t
  end
  _getProp['global'] = function(e,v2) local v,t = _getGlobal(e.name,true) e.value = v2 or v return t end

  local function _mkCombEvent(e,doc,action,rl)
    local rm = {[self.RULE]=e, action=action, src=doc, subs=rl}
    rm.enable = function() Util.mapF(function(e) e.enable() end,rl) return rm end
    rm.disable = function() Util.mapF(function(e) e.disable() end,rl) return rm end
    return rm
  end

  -- {type='property' deviceID=x, ...}
  function self.event(e,action,doc) -- define rules - event template + action
    if e[1] then -- events is list of event patterns {{type='x', ..},{type='y', ...}, ...}
      return _mkCombEvent(e,action,doc,Util.map(function(es) return self.event(es,action,doc) end,e))
    end
    _assert(isEvent(e), "bad event format '%s'",tojson(e))
    if e.deviceID and type(e.deviceID) == 'table' then  -- multiple IDs in deviceID {type='property', deviceID={x,y,..}}
      return _mkCombEvent(e,action,doc,Util.map(function(id) local el=_copy(e) el.deviceID=id return self.event(el,action,doc) end,e.deviceID))
    end
    doc = doc and "Event.event:"..doc or _format("Event.event(%s,...)",tojson(e))
    action = self._compileAction(action)
    _compilePattern(e)
    _handlers[e.type] = _handlers[e.type] or {}
    local rules = _handlers[e.type]
    local rule,fn = {[self.RULE]=e, action=action, src=doc}, true
    for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
      if _equal(e,rs[1][self.RULE]) then rs[#rs+1] = rule fn = false break end
    end
    if fn then rules[#rules+1] = {rule} end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    return rule
  end

  function self.schedule(time,action,opt)
    local test, start = opt and opt.cond, opt and (opt.start or false)
    local name = opt and opt.name or tostring(action)
    local loop,tp = {type='_scheduler:'..name, _sh=true}
    local test2,action2 = test and self._compileAction(test),self._compileAction(action)
    local re = self.event(loop,function(env)
        local fl = test == nil or test2()
        if fl == self.BREAK then return
        elseif fl then action2() end
        tp = self.post(loop, time) 
      end)
    local res = {
      [self.RULE] = {}, src=name, --- res ??????
      enable = function() if not tp then tp = self.post(loop,start and 0 or time) end return res end, 
      disable= function() tp = self.cancel(tp) return res end, 
    }
    res.enable()
    return res
  end

  function self._compileAction(a)
    if type(a) == 'function' then return a end
    if isEvent(a) then return function(e) return self.post(a) end end  -- Event -> post(event)
    error("Unable to compile action:"..json.encode(a))
  end

  local function _invokeRule(env)
    local t = osTime()
    env.last,env.rule.time = t-(env.rule.time or 0),t
    Debug(_debugFlags.invoke and not env.event._sh,"Invoking:%s",env.rule.src)
    local status, res = pcall(function() env.rule.action(env) end) -- call the associated action
    if not status then
      ruleError(res,env.rule.src,"rule")
      self.post({type='error',err=res,rule=env.rule.src,event=tojson(env.event),_sh=true})    -- Send error back
      env.rule._disabled = true                            -- disable rule to not generate more errors
    end
  end

-- {{e1,e2,e3},{e4,e5,e6}} 
  function self._handleEvent(e) -- running a posted event
    if _getProp[e.type] then _getProp[e.type](e,e.value) end  -- patch events
    if _OFFLINE and not _REMOTE then if _simFuns[e.type] then _simFuns[e.type](e)  end end
    local env = {event = e, p={}}
    for _,rules in ipairs(_handlers[e.type] or {}) do -- Check all rules of 'type'
      local match = _match(rules[1][self.RULE],e)
      if match then
        if next(match) then for k,v in pairs(match) do env.p[k]=v match[k]={v} end env.context = match end
        for _,rule in ipairs(rules) do 
          if not rule._disabled then env.rule = rule _invokeRule(env) end
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

  -- Logging of fibaro:* calls -------------
  function interceptFib(name,flag,spec,mf)
    local fun,fstr = fibaro[name],name:match("^get") and "fibaro:%s(%s%s%s) = %s" or "fibaro:%s(%s%s%s)"
    if spec then 
      fibaro[name] = function(obj,...) if _debugFlags[flag] then return spec(obj,fun,...) else return fun(obj,...) end end 
    else 
      fibaro[name] = function(obj,id,...)
        local id2,args = type(id) == 'number' and Util.reverseVar(id) or '"'..id..'"',{...}
        local status,res,r2 = pcall(function() return fun(obj,id,table.unpack(args)) end)
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
  interceptFib("startScene","fibaro",
    function(obj,fun,id,args) 
      local a = args and #args==1 and type(args[1])=='string' and (json.encode({(urldecode(args[1]))})) or ""
      Debug(true,"fibaro:start(%s,%s)",id,a)
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

function Util.mapAnd(f,l,s) s = s or 1; local e=false for i=s,#l do e = f(l[i]) if not e then return false end end return e end 
function Util.mapOr(f,l,s) s = s or 1; for i=s,#l do local e = f(l[i]) if e then return e end end return false end
function Util.mapF(f,l,s) s = s or 1; local e=true for i=s,#l do e = f(l[i]) end return e end
function Util.map(f,l,s) s = s or 1; local r={} for i=s,#l do r[#r+1] = f(l[i]) end return r end
function Util.mapo(f,l,o) for _,j in ipairs(l) do f(o,j) end end
function Util.mapkl(f,l) local r={} for i,j in pairs(l) do r[#r+1]=f(i,j) end return r end
function Util.mapkk(f,l) local r={} for i,j in pairs(l) do r[i]=f(j) end return r end
function Util.member(v,tab) for _,e in ipairs(tab) do if v==e then return e end end return nil end
function Util.append(t1,t2) for _,e in ipairs(t2) do t1[#t1+1]=e end return t1 end
function Util.gensym(s) return s..tostring({1,2,3}):match("([abcdef%d]*)$") end
function Util.traverse(e,f)
  if type(e) ~= 'table' or e[1]=='quote' or e[1]=='var' then return e end
  if e[1]=='%table' then 
    e={'%table',Util.mapkk(function(e) return Util.traverse(e,f) end, e[2])}
  elseif e[1]~='quote' then e=Util.map(function(e) return Util.traverse(e,f) end, e) end
  return f(e[1],e)
end

Util.S1 = {click = "16", double = "14", tripple = "15", hold = "12", release = "13"}
Util.S2 = {click = "26", double = "24", tripple = "25", hold = "22", release = "23"}

Util._vars = {} 
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
  return self
end

---------------------- Startup -----------------------------    
if _type == 'autostart' or _type == 'other' then
  Log(LOG.WELCOME,_format("%sEventRunner v%s",_sceneName and (_sceneName.." - " or ""),_version))

  if not _OFFLINE then
    Log(LOG.LOG,"Fibaro software version: %s",(api.get("/settings/info/")).currentVersion.version)
    if not string.find(json.encode((api.get("/globalVariables/"))),"\"".._MAILBOX.."\"") then
      api.post("/globalVariables/",{name=_MAILBOX}) 
    end
  end 

  GC = 0
  function setUp()
    Log(LOG.SYSTEM,"Loading rules")
    local status, res = pcall(function() main() end)
    if not status then 
      Log(LOG.ERROR,"Error loading rules:%s",type(res)=='table' and table.concat(res,' ') or res) fibaro:abort() 
    end

    _trigger._sh = true
    Event.post(_trigger)

    Log(LOG.SYSTEM,"Scene running")
    Log(LOG.SYSTEM,"Sunrise %s, Sunset %s",fibaro:getValue(1,'sunriseHour'),fibaro:getValue(1,'sunsetHour'))
    collectgarbage("collect") GC=collectgarbage("count")
  end

  if not _OFFLINE then 
    fibaro:setGlobal(_MAILBOX,"") 
    _poll()  -- start polling mailbox
    setUp()
  else 
    _System.runOffline(setUp) 
  end
end