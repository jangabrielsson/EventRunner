--[[
%% properties
55 value
66 value
77 value
%% events
%% globals
counter
%% autostart
--]]

_version = "1.2"  

--[[
-- EventRunner. Event based scheduler/device trigger handler
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_sceneName   = "Demo"        -- Set to scene/script name
_debugFlags = { post=false,invoke=true,triggers=false,dailys=false,timers=false,rule=false,fibaro=true,fibaroGet=false, fibaroSet=false }
_deviceTable = "deviceTable" -- Name of json struct with configuration data (i.e. "HomeTable")
ruleLogLength = 80

Event = {}
-- If running offline we need our own setTimeout and net.HTTPClient() and other fibaro funs...
if dofile then dofile("EventRunnerDebug.lua") end

---------------- Callbacks to user code --------------------
function main()
  --fibaro:sleep(60*1000)
  --local devs = json.decode(fibaro:getGlobalValue(_deviceTable))
  --Util.defvars(devs)
  --Util.reverseMapDef(devs)
  -- lets start
  dofile("example_rules.lua") -- some example rules to try out...
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

  _negOper={['==']='~=',['~=']='==',['>']='<=',['<=']='>',['<']='>=',['>=']='<'}
  negate = {}
  negate['property'] = function(e) e.value = e.value:gsub("([=><~]+)",function(s) return _negOper[s] end) return e end
  negate['global'] = negate['property']

  function self.trueFor(time,event,action)
    local nevent,ref
    if negate[event.type] then nevent=negate[event.type](_copy(event))
    else error("trueFor needs '$' constraint") end
    Event.event(event,function(env) ref = Event.post(function() ref=nil; action() end,time) end)
    Event.event(nevent,function(env) if ref then ref = Event.cancel(ref) end end)
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
  if type(e) ~= 'table' or e[1]=='quote' or (e[1]=='var' and e[2]:sub(1,1)~="_") then return e end
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
  getIdFun['isOn']=function(s,i) return doit(Util.mapOr,function(id) return fibaro:get(ID(id,i),'value') > '0' end,s.pop()) end
  getIdFun['isOff']=function(s,i) return doit(Util.mapAnd,function(id) return fibaro:getValue(ID(id,i),'value') == '0' end,s.pop()) end
  getIdFun['isAllOn']=function(s,i) return doit(Util.mapAnd,function(id) return fibaro:get(ID(id,i),'value') > '0' end,s.pop()) end
  getIdFun['isAnyOff']=function(s,i) return doit(Util.mapOr,function(id) return fibaro:getValue(ID(id,i),'value') == '0' end,s.pop()) end
  getIdFun['on']=function(s,i) doit(Util.mapF,function(id) fibaro:call(ID(id,i),'turnOn') end,s.pop()) return true end
  getIdFun['off']=function(s,i) doit(Util.mapF,function(id) fibaro:call(ID(id,i),'turnOff') end,s.pop()) return true end
  getIdFun['last']=function(s,i) local t = osTime()
    return doit(Util.map,function(id) return t-select(2,fibaro:get(ID(id,i),'value')) end, s.pop()) 
  end
  getIdFun['scene']=function(s,i) return getIdFuns(s,i,'sceneActivation') end
  getIdFun['bat']=function(s,i) return getIdFuns(s,i,'batteryLevel') end
  getIdFun['name']=function(s,i) return doit(Util.map,function(id) return fibaro:getName(ID(id,i)) end,s.pop()) end 
  getIdFun['roomName']=function(s,i) return doit(Util.map,function(id) return fibaro:getRoomNameByDeviceID(ID(id,i)) end,s.pop()) end 
  getIdFun['safe']=getIdFun['isOff'] getIdFun['breached']=getIdFun['isOn']
  getIdFun['trigger']=function(s,i) return true end -- Nop, only for triggering rules
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
    local vf = type(v) == 'table' and function() vp=vp+1 return v[vp] end or function() return v end 
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
    return Util._vars[v] or _ENV[v]
  end
  local function setVar(var,val,e) local vars = e.context
    while vars do if vars[var] then vars[var][1]=val return val else vars = vars.__next end end
    if var:sub(1,1)=='_' and Util._vars[var]~=val then Event.post({type='variable', name=var, value=val}) end
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
  instr['rule'] = function(s,n,e,i) local r,b,h=s.pop(),s.pop(),s.pop() s.push(Rule.compRule({'=>',h,b},e.src or r)) end
  instr['prop'] = function(s,n,e,i)local prop=i[3] if getIdFun[prop] then s.push(getIdFun[prop](s,i)) else s.push(getIdFuns(s,i,prop)) end end
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
  instr['logRule'] = function(s,n,e,i) local src,res = s.pop(),s.pop() Debug(_debugFlags.rule,"=>[%s]%s",res,src) s.push(res) end
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
  instr['/'] = function(s,n) s.push(1.0/(s.pop()/s.pop())) end
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
  instr['log'] = function(s,n) s.push(Log(LOG.LOG,table.unpack(s.lift(n)))) end
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
  instr['schedule'] = function(s,n,e,i) local t,code = s.pop(),e.code -- Fix this to normal rule format!!!!
    local told,tinc,tnew,res = i[3],i[4],osTime(),true
    if t < 0 then t=-t if i[5]==nil then res = false; i[5]=true end end
    if t ~= tinc then told=nil; tinc=t end
    t = told and t+told or tnew+t
    i[3],i[4]=t,tinc
    Event.post(function() self.eval(code) end,t,e.src) s.push(res)
  end
  instr['ostime'] = function(s,n) s.push(osTime()) end
  instr['frm'] = function(s,n) s.push(string.format(table.unpack(s.lift(n)))) end
  instr['label'] = function(s,n,e,i) local nm,id = s.pop(),s.pop() s.push(fibaro:get(ID(id,i),_format("ui.%s.value",nm))) end
  instr['slider'] = instr['label']
  instr['once'] = function(s,n,e,i) local f; i[4],f = s.pop(),i[4]; s.push(not f and i[4]) end
  instr['always'] = function(s,n,e,i) s.pop(n) s.push(true) end 
  instr['post'] = function(s,n) local e,t=s.pop(),nil; if n==2 then t=e; e=s.pop() end s.push(Event.post(e,t)) end
  instr['cancel'] = function(s,n) Event.cancel(s.pop()) s.push(nil) end
  instr['add'] = function(s,n) local v,t=s.pop(),s.pop() table.insert(t,v) s.push(t) end
  instr['betw'] = function(s,n) local t2,t1,now=s.pop(),s.pop(),osTime()-midnight()
    if t1<=t2 then s.push(t1 <= now and now <= t2) else s.push(now >= t1 or now <= t2) end 
  end
  instr['wait'] = function(s,n,e,i) local t,cp=s.pop(),e.cp
    if i[4] then s.push(false) -- Already 'waiting'
    elseif i[5] then i[5]=false s.push(true) -- Timer expired, return true
    else 
      if t<midnight() then t = osTime()+t end -- Allow both relative and absolute time... e.g '10:00'->midnight+10:00
      i[4]=Event.post(function() i[4]=nil i[5]=true self.eval(e.code,e,e.stack,cp) end,t,e.src) s.push(false) error({type='yield'})
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
        e.forR={function() Event.post(rep,time+osTime(),e.src) return i[7] end,i[7]}
      end
      s.push(val) 
      return
    end 
    --Log(LOG.LOG,"BBB")
    i[7] = 0
    if i[5] and (not val) then i[5] = Event.cancel(i[5]) --Log(LOG.LOG,"Killing timer")-- Timer already running, and false, stop timer
    elseif (not i[5]) and val then                        -- Timer not running, and true, start timer
      i[5]=Event.post(rep,time+osTime(),e.src) --Log(LOG.LOG,"Starting timer %s",tostring(i[5]))
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
  local self,traverse,gensym,preC = {},Util.traverse,Util.gensym,{}

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
    for p = 1,#code do
      local i = code[p]
      Log(LOG.LOG,"%-3d:[%s/%s%s%s]",p,i[1],i[2] ,i[3] and ","..tojson(i[3]) or "",i[4] and ","..tojson(i[4]) or "")
    end
  end

  preC['progn'] = function(k,e) local r={'progn'}
    Util.map(function(p) 
        if type(p)=='table' and p[1 ]=='progn' then for i=2,#p do r[#r+1 ] = p[i] end
      else r[#r+1 ]=p end end
      ,e,2)
    return r
  end
  preC['if'] = function(k,e) local e1={'and',e[2],e[3]} return #e==4 and {'or',e1,e[4]} or e1 end
  preC['dolist'] = function(k,e) local var,list,expr,idx,lvar,LBL=e[2],e[3],e[4],{'var',gensym('fi')},{'var',gensym('fl')},gensym('LBL')
    e={'progn',{'set',idx,1},{'set',lvar,list},{'%addr',LBL}, -- dolist(var,list,expr)
      {'set',var,{'aref',lvar,idx}},{'and',var,{'progn',expr,{'set',idx,{'+',idx,1}},{'%jmp',LBL,0}}},lvar}
    return self.precompile(e)
  end
  preC['dotimes'] = function(k,e) local var,start,stop,step,body=e[2],e[3],e[4],e[5], e[6] -- dotimes(var,start,stop[,step],expr)
    local LBL = gensym('LBL')
    if body == nil then body,step = step,1 end
    e={'progn',{'set',var,start},{'%addr',LBL},{'if',{'<=',var,stop},{'progn',body,{'+=',var,step},{'%jmp',LBL,0}}}}
    return self.precompile(e)
  end
--  preC['>>'] = function(k,e) return self.precompile({'and',e[2],{'always',e[3]}}) end -- test >> expr |||| test >> expr ||| t >> expr
  preC['||'] = function(k,e) local c = {'and',e[2],{'always',e[3]}} return self.precompile(#e==3 and c or {'or',c,e[4]}) end
  preC['=>'] = function(k,e) return {'rule',{'quote',e[2]},{'quote',e[3]},{'quote',e[4]}} end
  preC['.'] = function(k,e) return {'aref',e[2],e[3]} end
  preC['neg'] = function(k,e) return isNum(e[2]) and -e[2] or e end
  preC['+='] = function(k,e) return {'inc',e[2],e[3],'+'} end
  preC['-='] = function(k,e) return {'inc',e[2],e[3],'-'} end
  preC['*='] = function(k,e) return {'inc',e[2],e[3],'*'} end
  preC['+'] = function(k,e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])+tonumber(e[3]) or e end
  preC['-'] = function(k,e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])-tonumber(e[3]) or e end
  preC['*'] = function(k,e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])*tonumber(e[3]) or e end
  preC['/'] = function(k,e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])/tonumber(e[3]) or e end
  preC['%'] = function(k,e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])%tonumber(e[3]) or e end
  preC['time'] = function(k,e)
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
      sg,h,m,s = ts:match("(%-?)(%d%d):(%d%d):?(%d*)")
      _assert(h and m,"malformed time constant '%s'",e[2])
      return {'%time',tm,(sg == '-' and -1 or 1)*(h*3600+m*60+(s~="" and s or 0))}
    end
  end 

  function self.precompile(e) return traverse(e,function (k,e) return preC[k] and preC[k](k,e) or e end) end
  function self.compile(expr) local code = {} compT(self.precompile(expr),code) return code end

  local _opMap = {['&']='and',['|']='or',['=']='set',[':']='prop',[';']='progn',['..']='betw', ['!']='not', ['@']='daily', ['@@']='schedule'}
  local function mapOp(op) return _opMap[op] or op end

  local function _binop(s,res) res.push({mapOp(s.pop().v),table.unpack(res.lift(2))}) end
  local function _unnop(s,res) res.push({mapOp(s.pop().v),res.pop()}) end
  local _prec = {
    ['*'] = 10, ['/'] = 10, ['%'] = 10, ['.'] = 12.5, ['+'] = 9, ['-'] = 9, [':'] = 12, ['..'] = 8.5, ['=>'] = -2, ['neg'] = 13, ['!'] = 6.5, ['@']=8.5, ['@@']=8.5,
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
    {"^([%%%*%+/&%.:~=><%|!@]+)",'op'},{"^(-)",'op'},{"^(%=%-)",'op'},
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
      prev = function() return tkns[tp-2] end, push=function() tp=tp-1 end, str=org}
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
    body = self.statements(tokens) tmatch("end",tokens)
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

  function self.expr(tokens)
    local s,res = Util.mkStack(),Util.mkStack()
    while true do
      local t = tokens.peek()
      if t.t=='EOF' or t.t=='token' or t.v == '}' or t.v == ']' then
        while not s.isEmpty() do _prec[s.peek().v][2](s,res) end
        _passert(res.size()==1,t and t.cp or 1,"bad expression")
        return res.pop()
      end
      tokens.nxt()
      if t.t == 'lsquare' then 
        res.push(self.expr(tokens)) t = tokens.nxt()
        _passert(t.t =='rsquare',t.cp,"bad index [] operator")
        t = {t='op',v='.',cp=t.cp}
      end
      if t.t=='op' then
        if s.isEmpty() then s.push(t)
        else
          while (not s.isEmpty()) do
            local p1,p2 = _prec[t.v][1], _prec[s.peek().v][1] p1 = t.v=='=' and 11 or p1
            if p2 >= p1 then _prec[s.peek().v][2](s,res) else break end
          end
          s.push(t)
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
  local map,mapkl,traverse=Util.map,Util.mapkl,Util.traverse
  local _macros,_dailys,rCounter= {},{},0
  local tProps ={value=1,isOn=1,isOff=1,isAnyOff=1,isAllOn=1,last=1,safe=1,breached=1,scene=2,power=3,bat=4,trigger=1,toggle=1,lux=1,temp=1,manual=1}
  local tPropsV = {[1]='value',[2]='sceneActivation',[3]='power',[4]='batteryLevel'}
  local lblF=function(id,e) return {type='property', deviceID=id, propertyName=_format("ui.%s.value",e[3])} end
  local triggFuns={
    label=lblF,slider=lblF
  }

  local function getTriggers(e)
    local ids,dailys,betw,sched={},{},{},false
    local function gt(k,e)
      if k=='daily' then dailys[#dailys+1 ]=ScriptCompiler.compile(e[2])
      elseif k=='schedule' then sched=true
      elseif k=='betw' then 
        betw[#betw+1 ]=ScriptCompiler.compile(e[2])
        betw[#betw+1 ]=ScriptCompiler.compile({'+',1,e[3]})
      elseif k=='glob' then ids[e[2] ] = {type='global', name=e[2]}
      elseif k=='var' then 
        ids[e[2] ] = {type='variable', name=e[2]}
      elseif k=='set' and isTriggerVar(e[2]) or isGlob(e[2]) then
        error("Can't assign variable in rule header")
      elseif k=='prop' and tProps[e[3]] then
        local cv = ScriptCompiler.compile(e[2])
        local v,pn = ScriptEngine.eval(cv),tPropsV[tProps[e[3]]]
        map(function(id) ids[id]={type='property', deviceID=id, propertyName=pn} end,type(v)=='table' and v or {v})
      elseif triggFuns[k] then 
        local cv = ScriptCompiler.compile(e[2])
        local v = ScriptEngine.eval(cv)
        map(function(id) ids[id]=triggFuns[k](id,e) end,type(v)=='table' and v or {v})
      end
      return e
    end
    traverse(e,gt)
    return ids and mapkl(function(k,v) return v end,ids),dailys,betw,sched
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
  local RULEFORMAT = "Rule:%s:%."..(ruleLogLength or 40).."s"

  function self.compRule(e,src)
    local h,body,res = e[2],e[3]
    if type(h)=='table' and (h[1]=='%table' or h[1]=='quote' and type(h[2])=='table') then -- event matching rule, Needs check for 'type'!!!!
      local ep = ScriptCompiler.compile(h)
      local body = ScriptCompiler.compile(body)
      local code = function(e) return ScriptEngine.eval(body,e) end
      res = Event.event((ScriptEngine.eval(ep)),code) res.src=src
    else
      local ids,dailys,betw,sched,times = getTriggers(h)
      local code = ScriptCompiler.compile({'and',_debugFlags.rule and {'logRule',h,src} or h,body})
      local action = function(e) return ScriptEngine.eval(code,e) end
      if sched then Event.post(action,nil,src)
      elseif #dailys>0 then -- 'daily' rule, ignore other triggers
        local m,ot,catchup1,catchup2=midnight(),osTime()
        _dailys[#_dailys+1]={dailys=dailys,action=action,src=src}
        times = compTimes(dailys)
        for _,t in ipairs(times) do _assert(tonumber(t),"@time not a number:%q",t)
          if t ~= CATCHUP then
            if t+m >= ot then Event.post(action,t+m,src) else catchup1=true end
          else catchup2 = true end
        end
        --if catchup2 and catchup1 then Event.post(function() Log(LOG.LOG,"Cathing up:%s",src); action() end) end
        if catchup2 and catchup1 then Log(LOG.LOG,"Cathing up:%s",src); Event._callTimerFun(action,src) end
      elseif #ids>0 then -- id/glob trigger rule
        res = {}
        for _,id in ipairs(ids) do res[#res+1]=Event.event(id,action); res[#res].src=src end
        if #betw>0 then
          local m,ot=midnight(),osTime()
          _dailys[#_dailys+1]={dailys=betw,action=action,src=src}
          times = compTimes(betw)
          for _,t in ipairs(times) do if t+m >= ot then Event.post(action,t+m,src) end end
        end
      else
        error(_format("no triggers found in rule '%s'",tojson(e)))
      end
      res = {[Event.RULE]={daily=dailys,betw=betw,device=ids}, action=action, src=src}
    end
    rCounter=rCounter+1
    Log(LOG.SYSTEM,RULEFORMAT,rCounter,src:match("([^%c]*)"))
    return res
  end

  function self.eval(expro,log,level)
    level = level or 2
    local line =""
    if _OFFLINE then line = _format(" @line %s",debug.getinfo(level).currentline) end
    local status, res = pcall(function() 
        local expr = self.macroSubs(expro)
        local res = ScriptCompiler.parse(expr)
        res = ScriptCompiler.compile(res)
        res = ScriptEngine.eval(res,{src=expro..line})
        if log then Log(LOG.LOG,"%s = %s",expro,tojson(res)) end
        return res
      end)
    if not status then errThrow(_format("Error evaluating '%s'",expro..line),res)
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
    map(function(r) self.eval(r,log,5) end,splitRules(rules))
  end

  function self.macro(name,str) _macros['%$'..name..'%$'] = str end
  function self.macroSubs(str) for m,s in pairs(_macros) do str = str:gsub(m,s) end return str end

  Event.schedule("n/00:00",function(env)  -- Scheduler that every night posts 'daily' rules
      _DSTadjust = os.date("*t").isdst and -60*60 or 0
      local midnight = midnight()
      --Log(LOG.LOG,"Scheduling")
      for _,d in ipairs(_dailys) do
        local times = compTimes(d.dailys)
        for _,t in ipairs(times) do
          if t ~= CATCHUP then
            Debug(_debugFlags.dailys,"Scheduling at %s",osDate("%X",midnight+t))
            if t==0 then Event._callTimerFun(d.action,d.src) else Event.post(d.action,midnight+t,d.src) end
          end
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
_lastCSEvent = {}
_lastWeatherEvent = {}
Event.event({type='event'}, function(env) env.event.event._sh=true 
    env.event.event.type = env.event.event.type or 'CentralSceneEvent' -- default to centralSceneEvent
    Event.post(env.event.event) 
  end)
Event.event({type='CentralSceneEvent'}, 
  function(env) _lastCSEvent[env.event.data.deviceId] = env.event.data end)
Event.event({type='WeatherChangedEvent'}, 
  function(env) _lastWeatherEvent[env.event.data.change] = env.event.data; _lastWeatherEvent['*'] = env.event.data end)

Rule.addTrigger('csEvent',
  function(s,n,e,i) return s.push(_lastCSEvent[s.pop()]) end,
  function(id) return {type='CentralSceneEvent',data={deviceId=id}} end)
Rule.addTrigger('weather',
  function(s,n,e,i) local k = n>0 and s.pop() or '*'; return s.push(_lastWeatherEvent[k]) end,
  function(id) return {type='WeatherChangedEvent',data={changed=id}} end)

--- SceneActivation constants
Util.defvar('S1',Util.S1)
Util.defvar('S2',Util.S2)
Util.defvar('catch',math.huge)
Util.defvar("defvars",Util.defvars)
Util.defvar("mapvars",Util.reverseMapDef)

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