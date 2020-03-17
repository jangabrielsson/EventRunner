if dofile then
  dofile("fibaroapiHC3.lua")
  local cr = loadfile("credentials.lua"); if cr then cr() end
  QuickApp._quickVars["Hue_User"]=_HueUserName
  QuickApp._quickVars["Hue_IP"]=_HueIP
  require('mobdebug').coro()  
end

E_VERSION,E_FIX = 0.1,"fix7"
_HC3IPADDRESS = "192.168.1.58" -- Needs to be defined on the HC3 as /seetings/networks seems broken...

local _debugFlags = { triggers = true, post=false, rule=false, fcall=true  } 
local Util,Device,Event,Remote,Patch,Extras,Rule,Trigger
local triggerInterval = 1000
local module = {}

function main2()
  local rule = Rule.eval
end

function main()    -- EventScript version
  local rule = Rule.eval

  HT = { 
    keyfob = 26, 
    motion= 21,
    temp = 22, lux = 23,
    motionHC2 = 44,
    lightHC2 = 45, 
    tempHC2 = 46
  }

  Util.defvars(HT)
  Util.reverseMapDef(HT)

  rule("keyfob:central => log('Key:%s',env.event.value.keyId)")
  rule("motion:value => log('Motion:%s',motion:value)")
  rule("temp:temp => log('Temp:%s',temp:temp)")
  rule("lux:lux => log('Lux:%s',lux:lux)")
  rule("motionHC2:value => log('MotionHC2:%s',motionHC2:value)")
  rule("tempHC2:temp => log('TempHC2:%s',tempHC2:temp)")
  rule("lightHC2:value => log('lightHC2:%s',lightHC2:value)")

  rule("keyfob:central.keyId==3 => 1000:on") 
  rule("keyfob:central.keyId==4 => 1000:off") 
  rule("keyfob:central.keyId==5 => log('Last:%s',1000:last)") 

  rule("#UI{name='$name'} => log('Clicked:%s',name)") -- Name of UI button clicked

  Nodered.connect("http://192.168.1.50:1880/ER_HC3")
  rule("Nodered.post({type='echo1',value=42})")
  rule("#echo1 => log('ECHO:%s',env.event)")

  rule("#alarm{property='armed', value=true, id='$id'} => log('Zone %d armed',id)")
  rule("#alarm{property='armed', value=false, id='$id'} => log('Zone %d disarmed',id)")
  rule("#alarm{property='homeArmed', value=true} => log('Home armed')")
  rule("#alarm{property='homeArmed', value=false} => log('Home disarmed')")
  rule("#alarm{property='homeBreached', value=true} => log('Home breached')")
  rule("#alarm{property='homeBreached', value=false} => log('Home safe')")

  rule("#weather{property='$prop', value='$val'} => log('%s = %s',prop,val)")

  rule("#profile{property='activeProfile', value='$val'} => log('New profile:%s',val)")

  rule("#Test => log('Test event received')")
  rule("wait(3); post(#Test)")

--  rule("Util.checkEventRunnerVersion()")
--  rule("#ER_version => log('New ER version:%s',env.event)")
end

function mainLua()  -- Lua version

  HT = { 
    keyfob = 26, 
    motion= 21,
    temp = 22, lux = 23,
    motionHC2 = 44,
    lightHC2 = 45, 
    tempHC2 = 46
  }

  Event.event({type='property', deviceId=HT.keyfob, propertyName='CentralSceneEvent'},
    function(env)
      Log(LOG.LOG,"Key:%s",env.event.value.keyId)
    end)

  Event.event({type='property', deviceId=HT.keyfob, propertyName='CentralSceneEvent', value={keyId=3}},
    function(env)
      fibaro.call(1000,"turnOn")
    end)

  Event.event({type='UI', name='$name'},
    function(env)
      Log(LOG.LOG,"Clicked:%s",env.p.name)
    end)

  Nodered.connect("http://192.168.1.50:1880/ER_HC3")
  --Nodered.post({type='echo1',value=42})
  Event.event({type='echo1'},
    function(env)
      Log(LOG.LOG,'ECHO:%s',env.event)
    end)

  Event.event({type='alarm', property='armed', value=true, id='$id'},
    function(env)
      Log(LOG.LOG,'Zone %d armed',env.p.id)
    end)

end

function QuickApp:turnOn() self:updateProperty("value", true) end
function QuickApp:turnOff() self:updateProperty("value", false) end

------------------- EventSupport - Don't change! -------------------- 

----------------- Module Event engine -------------------------
function module.EventEngine() -- Event extension
  Log(LOG.SYS,"Setting up event engine..")
  local self,_handlers = {},{}
  self._sections,self.SECTION = {},nil
  self.BREAK, self.TIMER, self.RULE, self.INTERVAL ='%%BREAK%%', '%%TIMER%%', '%%RULE%%', 1000
  local equal,format,map,mapF,copy,toTime,orgToStr =  Util.equal, string.format, Util.map, Util.mapF, Util.copy, Util.toTime,Util.orgTostring

  local function isTimer(t) return type(t) == 'table' and t[Event.TIMER] end
  local function isRule(r) return type(r) == 'table' and r[Event.RULE] end
  local function isEvent(e) return type(e) == 'table' and e.type end
  self.deviceID = plugin.mainDeviceId
  local smNR,maMatch=0,"^CE"..self.deviceID
  function self.makeAddress(id) smNR=smNR+1; return "CE"..id.."F"..self.deviceID.."N"..smNR end
  function self.isMyAddress(address) return address:match(maMatch)  end
  function self.isBroadcastAddress(address) return address:match("^CE000") end
  self.tickEvent = "TICK"

  local function timer2str(t) 
    local s = orgToStr(t[Event.TIMER])
    if s:sub(1,6)=="<Timer" then return s
    else 
      return format("<Timer:%s, exp:%s>", 
        s:sub(10),
        os.date("%H:%M:%S",math.floor(t.start+t.len/1000+0.5)))
    end
  end
  local function mkTimer(f,t) t=t or 0;
    return {[Event.TIMER]=setTimeout(f,t), start=os.time(), len=t, __tostring=timer2str} 
  end

  local function str2event(str)
    local t = str:match("#([%w_]+)")
    _assert(t,"Bad event:"..str)
    local e = str:sub(#t+2)
    e = e:sub(1,1)=='{' and json.decode(e) or {}
    e.type = t
    return e
  end

  local function coerce(x,y) local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end end
  local constraints = {}
  constraints['=='] = function(val) return function(x) x,val=coerce(x,val) return x == val end end
  constraints['>='] = function(val) return function(x) x,val=coerce(x,val) return x >= val end end
  constraints['<='] = function(val) return function(x) x,val=coerce(x,val) return x <= val end end
  constraints['>'] = function(val) return function(x) x,val=coerce(x,val) return x > val end end
  constraints['<'] = function(val) return function(x) x,val=coerce(x,val) return x < val end end
  constraints['~='] = function(val) return function(x) x,val=coerce(x,val) return x ~= val end end
  constraints[''] = function(_) return function(x) return x ~= nil end end

  self.isTimer, self.isRule, self.isEvent, self.mkTimer, self.coerce = isTimer, isRule, isEvent, mkTimer, coerce

  local function compilePattern2(pattern)
    if type(pattern) == 'table' then
      if pattern._var_ then return end
      for k,v in pairs(pattern) do
        if type(v) == 'string' and v:sub(1,1) == '$' then
          local var,op,val = v:match("$([%w_]*)([<>=~]*)([+-]?%d*%.?%d*)")
          var = var =="" and "_" or var
          local c = constraints[op](tonumber(val))
          pattern[k] = {_var_=var, _constr=c, _str=v}
        else compilePattern2(v) end
      end
    end
  end

  local function compilePattern(pattern)
    compilePattern2(pattern)
    if pattern.type and type(pattern.deviceID)=='table' and not pattern.deviceID._constr then
      local m = {}; for _,id in ipairs(pattern.deviceID) do m[id]=true end
      pattern.deviceID = {_var_='_', _constr=function(val) return m[val] end, _str=pattern.deviceID}
    end
  end
  self._compilePattern = compilePattern

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

  local toHash,fromHash={},{}
  fromHash['property'] = function(e) return {e.type..e.deviceID,e.type} end
  fromHash['global'] = function(e) return {e.type..e.name,e.type} end
  toHash['property'] = function(e) return e.deviceID and 'property'..e.deviceID or 'property' end
  toHash['global'] = function(e) return e.name and 'global'..e.name or 'global' end

  local function ruleToStr(r) return r.src end
  local function comboToStr(r)
    local res = { r.src }
    for _,s in ipairs(r.subs) do res[#res+1]="   "..tostring(s) end
    return table.concat(res,"\n")
  end

  function self.comboEvent(e,action,rl,src)
    local rm = {[self.RULE]=e, action=action, src=src, subs=rl}
    rm.enable = function() mapF(function(e) e.enable() end,rl) return rm end
    rm.disable = function() mapF(function(e) e.disable() end,rl) return rm end
    rm.start = function(event) self._invokeRule({rule=rm,event=event}) return rm end
    rm.print = function() map(function(e) e.print() end,rl) end
    rm.__tostring = comboToStr
    return rm
  end

  function self.event(e,action,src) 
    local front = false
    e = type(e)=='string' and str2event(e) or e
    src = src or (type(e)=='table' and format("Event(%s) => ..",e) or tostring(e))
    if type(e) == 'table' and e[1] then 
      return self.comboEvent(e,action,map(function(es) return self.event(es,action) end,e),src) 
    end
    if isEvent(e) then
      if e.type=='property' and e.deviceID and type(e.deviceID)=='table' then
        return self.event(map(function(id) local e1 = copy(e); e1.deviceID=id return e1 end,e.deviceID),action,src)
      end
    end
    compilePattern(e)
    local hashKey = toHash[e.type] and toHash[e.type](e) or e.type
    _handlers[hashKey] = _handlers[hashKey] or {}
    local rules = _handlers[hashKey]
    local rule,fn = {[self.RULE]=e, action=action, src=src}, true
    for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
      if equal(e,rs[1][self.RULE]) then 
        if front then table.insert(rs,1,rule) else rs[#rs+1] = rule end 
        fn = false break 
      end
    end
    if fn then if front then table.insert(rules,1,{rule}) else rules[#rules+1] = {rule} end end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    rule.start = function(event) self._invokeRule({rule=rule,event=event}) return rule end
    rule.print = function() Log(LOG.LOG,src) end
    rule.__tostring = ruleToStr
    if self.SECTION then
      local s = self._sections[self.SECTION] or {}
      s[#s+1] = rule
      self._sections[self.SECTION] = s
    end
    return rule
  end

  function self._callTimerFun(tf,src)
    local status,res = pcall(tf) 
    if not status then 
      Log(LOG.ERROR,"in '%s': %s",src or tostring(tf),res)  
    end
  end

  function self.post(e,time,src) -- time in 'toTime' format, see below.
    if not(isEvent(e) or type(e) == 'function') then error("Bad event format "..tojson(e),3) end
    time = toTime(time or os.time())
    if time < os.time() then return nil end
    if type(e) == 'function' then 
      src = src or "timer "..tostring(e)
      if _debugFlags.postTimers then Debug(true,"Posting timer %s at %s",src,os.date("%a %b %d %X",time)) end
      return mkTimer(function() self._callTimerFun(e,src) end, 1000*(time-os.time()))
    end
    if _debugFlags.post and not e._sh then Debug(true,"Posting %s at %s",e,os.date("%a %b %d %X",time)) end
    return mkTimer(function() self._handleEvent(e) end,1000*(time-os.time()))
  end

  function self.cancel(t)
    _assert(isTimer(t) or t == nil,"Bad timer")
    if t then clearTimeout(t[self.TIMER]) end 
    return nil 
  end

  function self.loop(time,fun,sync)
    local nextTime,interval,tp = os.time(),toTime(time),nil
    local res = {[self.RULE] = {}, count = 0}
    if type(fun)=='table' then local e = fun; fun = function() self.post(e) end end
    local function _loop()
      nextTime = nextTime + toTime(time); res.count=res.count+1
      if fun(res) == self.BREAK then tp = nil
      else tp = setTimeout(_loop,1000*(nextTime-os.time())) end
    end
    res.enable = function() 
      if tp then res.disable() end
      nextTime, res.count = os.time(),0
      if sync then nextTime = math.floor(nextTime/interval)*interval+interval end
      tp = setTimeout(_loop,1000*(nextTime-os.time()))
      return res
    end
    res.disable = function() if tp then clearTimeout(tp); tp=nil end return res end
    res.print = function() Log(LOG.LOG,res) end
    res.__tostring = function(e) return string.format("{loop interval:'%s', count:%s}",time,res.count) end
    res.enable()
    return res
  end

  function self.cron(pattern,fun)
    local test,c = Util.dateTest(pattern),0
    local r = self.loop("00:01",function(r) if test() then c=c+1; r.count=c return fun(r) end end,true)
    r.__tostring = function(e) return string.format("{cron:'%s', count:%s}",pattern,r.count) end
    return r
  end

  function self._compileAction(a)
    if type(a) == 'function' then return a                    -- Lua function
    elseif isEvent(a) then 
      return function(e) return self.post(a,nil,e.rule) end  -- Event -> post(event)
    end
  end

  function self._compileAction(a,src,log)
    if type(a) == 'function' then return a                   -- Lua function
    elseif isEvent(a) then 
      return function(e) return self.post(a,nil,tostring(a)) end  -- Event -> post(event)
    elseif self._compileActionHook then
      local r = self._compileActionHook(a,src,log)
      if r then return r end
    end
    error("Unable to compile action:"..json.encode(a))
  end

  local _getProp = {}
  _getProp['property'] = function(e,v)
    e.propertyName = e.propertyName or 'value'
    e.value = v or (fibaro.getValue(e.deviceID,e.propertyName))
    --self.trackManual(e.deviceID,e.value)
  end
  _getProp['global'] = function(e,v2) e.value = v2 or fibaro.getGlobalVariable(e.name) end

  function self._invokeRule(env,event)
    local t = os.time()
    env.last,env.rule.time = t-(env.rule.time or 0),t
    env.event = env.event or event
    local status, res = pcall(env.rule.action,env) -- call the associated action
    if not status then
      Log(LOG.ERROR,"in '%s': %s",res and res.src or "rule",res)
      env.rule._disabled = true -- disable rule to not generate more errors
    else return res end
  end

-- {{e1,e2,e3},{e4,e5,e6}} env={event=_,p=_,locals=_,rule.src=_,last=_}
  function self._handleEvent(e) -- running a posted event
    --Log("E:%s",tojson(e))
    if _getProp[e.type] then _getProp[e.type](e,e.value) end  -- patch events
    local _match,hasKeys = self._match,fromHash[e.type] and fromHash[e.type](e) or {e.type}
    for _,hashKey in ipairs(hasKeys) do
      for _,rules in ipairs(_handlers[hashKey] or {}) do -- Check all rules of 'type'
        local match,m = _match(rules[1][self.RULE],e),nil
        if match then
          for _,rule in ipairs(rules) do 
            if not rule._disabled then 
              m={}; if next(match) then for k,v in pairs(match) do m[k]={v} end end
              local env = {event = e, p=match, rule=rule, locals= m}
              if self._invokeRule(env) == self.BREAK then break end
            end
          end
        end
      end
    end
  end

  self.event({type='centralSceneEvent'},function(env)
      if not env.event.data.keyId then return end
      self.post({type='property',deviceID=env.event.data.deviceId,
          propertyName='CentralSceneEvent',value=env.event.data, _sh = env.event._sh})
    end)

  function self.getCustomEvent(name) return api.get("/customEvents/"..name) end
  function self.getCustomEventDescription(name) 
    local ce = self.getCustomEvent(name) 
    return ce and ce.userDescription or nil
  end
  function self.createCustomEvent(name,descr) api.post("/customEvents",{name=name,userDescription=descr}) end
  function self.deleteCustomEvent(name) api.delete("/customEvents/"..name) end
  function self.postCustomEvent(name) api.post("/customEvents/"..name) end
  return self
end -- eventEngine

----------------- Module device support -----------------------
function module.Device()
  Log(LOG.SYS,"Setting up device support..")
  local qs = fibaro.QD
  local self = { deviceID = plugin.mainDeviceId }
  function self.updateProperty(prop,value) return qs:updateProperty(prop,value)  end
  function self.updateView(componentID, property, value) return qs:updateView(componentID, property, value)  end
  function self.setVariable(name,value) return qs:setVariable(name,value) end
  function self.getVariable(name) return qs:getVariable(name) end
  local uis,err = api.get("/devices/"..self.deviceID)
  local uiCallbacks = uis.properties.uiCallbacks or {}
  for _,e in ipairs(uiCallbacks) do 
    local name = e.name.."Clicked"
    if qs[name] then 
      local old = qs[name]; qs[name] = function(self,arg) Event.post({type='UI',name=e.name,value=arg}) old(self,arg) end
    else
      qs[name] = function(self,arg) Event.post({type='UI',name=e.name,value=arg}) end
    end
  end
  return self
end

----------------- Module utilities ----------------------------
function module.Utilities()
  local self,format = {},string.format

  function self.map(f,l,s) s = s or 1; local r={} for i=s,table.maxn(l) do r[#r+1] = f(l[i]) end return r end
  function self.mapAnd(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) if not e then return false end end return e end 
  function self.mapOr(f,l,s) s = s or 1; for i=s,table.maxn(l) do local e = f(l[i]) if e then return e end end return false end
  function self.mapF(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) end return e end

  local function transform(obj,tf)
    if type(obj) == 'table' then
      local res = {} for l,v in pairs(obj) do res[l] = transform(v,tf) end 
      return res
    else return tf(obj) end
  end
  local function copy(obj) return transform(obj, function(o) return o end) end
  local function equal(e1,e2)
    local t1,t2 = type(e1),type(e2)
    if t1 ~= t2 then return false end
    if t1 ~= 'table' and t2 ~= 'table' then return e1 == e2 end 
    for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
    for k2,v2 in pairs(e2) do if e1[k2] == nil or not equal(e1[k2],v2) then return false end end
    return true
  end

  if (_VERSION or ""):match("5%.3") then
    function table.maxn(tbl)
      local c=0
      for k in pairs(tbl) do c=c+1 end
      return c
    end
  end

  function self.map(f,l,s) s = s or 1; local r={} for i=s,table.maxn(l) do r[#r+1] = f(l[i]) end return r end
  function self.mapAnd(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) if not e then return false end end return e end 
  function self.mapOr(f,l,s) s = s or 1; for i=s,table.maxn(l) do local e = f(l[i]) if e then return e end end return false end
  function self.mapF(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) end return e end
  function self.mapkl(f,l) local r={} for i,j in pairs(l) do r[#r+1]=f(i,j) end return r end
  function self.mapkk(f,l) local r={} for k,v in pairs(l) do r[k]=f(v) end return r end
  function self.member(v,tab) for _,e in ipairs(tab) do if v==e then return e end end return nil end
  function self.append(t1,t2) for _,e in ipairs(t2) do t1[#t1+1]=e end return t1 end

  function isError(e) return type(e)=='table' and e.ERR end
  function throwError(args) args.ERR=true; error(args,args.level) end

  function self.mkStream(tab)
    local p,self=0,{ stream=tab, eof={type='eof', value='', from=tab[#tab].from, to=tab[#tab].to} }
    function self.next() p=p+1 return p<=#tab and tab[p] or self.eof end
    function self.last() return tab[p] or self.eof end
    function self.peek(n) return tab[p+(n or 1)] or self.eof end
    return self
  end
  function self.mkStack()
    local p,st,self=0,{},{}
    function self.push(v) p=p+1 st[p]=v end
    function self.pop(n) n = n or 1; p=p-n; return st[p+n] end
    function self.popn(n,v) v = v or {}; if n > 0 then local p = self.pop(); self.popn(n-1,v); v[#v+1]=p end return v end 
    function self.peek(n) return st[p-(n or 0)] end
    function self.lift(n) local s = {} for i=1,n do s[i] = st[p-n+i] end self.pop(n) return s end
    function self.liftc(n) local s = {} for i=1,n do s[i] = st[p-n+i] end return s end
    function self.isEmpty() return p<=0 end
    function self.size() return p end    
    function self.setSize(np) p=np end
    function self.set(i,v) st[p+i]=v end
    function self.get(i) return st[p+i] end
    function self.dump() for i=1,p do print(json.encode(st[i])) end end
    function self.clear() p,st=0,{} end
    return self
  end

  self._vars = {}
  local _vars = self._vars
  local _triggerVars = {}
  self._triggerVars = _triggerVars
  self._reverseVarTable = {}
  function self.defvar(var,expr) if _vars[var] then _vars[var][1]=expr else _vars[var]={expr} end end
  function self.defvars(tab) for var,val in pairs(tab) do self.defvar(var,val) end end
  function self.defTriggerVar(var,expr) _triggerVars[var]=true; self.defvar(var,expr) end
  function self.triggerVar(v) return _triggerVars[v] end
  function self.reverseMapDef(table) self._reverseMap({},table) end
  function self._reverseMap(path,value)
    if type(value) == 'number' then self._reverseVarTable[tostring(value)] = table.concat(path,".")
    elseif type(value) == 'table' and not value[1] then
      for k,v in pairs(value) do table.insert(path,k); self._reverseMap(path,v); table.remove(path) end
    end
  end
  function self.reverseVar(id) return Util._reverseVarTable[tostring(id)] or id end

  self.coroutine = {
    create = function(code,src,env)
      env=env or {}
      env.cp,env.stack,env.code,env.src=1,Util.mkStack(),code,src
      return {state='suspended', context=env}
    end,
    resume = function(co) 
      if co.state=='dead' then return false,"cannot resume dead coroutine" end
      if co.state=='running' then return false,"cannot resume running coroutine" end
      co.state='running' 
      local status,res = Rule.ScriptEngine.eval(co.context)
      co.state= status=='suspended' and status or 'dead'
      return true,table.unpack(res)
    end,
    status = function(co) return co.state end,
    _reset = function(co) co.state,co.context.cp='suspended',1; co.context.stack.clear(); return co.context end
  }

  local VIRTUALDEVICES = {}
  function self.defineVirtualDevice(id,call,get) VIRTUALDEVICES[id]={call=call,get=get} end
  do
    local oldGet,oldCall = fibaro.get,fibaro.call
    function fibaro.call(id,action,...) local d = VIRTUALDEVICES[id]
      if d and d.call and d.call(id,action,...) then return
      else oldCall(id,action,...) end
    end
    function fibaro.get(id,prop,...) local g = VIRTUALDEVICES[id]
      if g and g.get then 
        local stat,res = g.get(id,prop,...)
        if stat then return table.unpack(res) end
      end
      return oldGet(id,prop,...)
    end
  end

  local function patchF(name)
    local oldF,flag = fibaro[name],"f"..name
    fibaro[name] = function(...)
      local args = {...}
      local res = {oldF(...)}
      if _debugFlags[flag] then
        args = #args==0 and "" or json.encode(args):sub(2,-2)
        Log(LOG.DEBUG,"fibaro.%s(%s) => %s",name,args,#res==0 and "nil" or #res==1 and res[1] or res)
      end
      return table.unpack(res)
    end
  end

  patchF("call")

  function urldecode(str) return str:gsub('%%(%x%x)',function (x) return string.char(tonumber(x,16)) end) end
  function split(s, sep)
    local fields = {}
    sep = sep or " "
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
    return fields
  end

  local oldtostring,oldformat = tostring,string.format
  self.orgTostring = oldtostring
  tostring = function(o)
    if type(o)=='table' then
      if o.__tostring then return o.__tostring(o)
      else return tojson(o) end
    else return oldtostring(o) end
  end
  string.format = function(...)
    local args = {...}
    for i=1,#args do if type(args[i])=='table' then args[i]=tostring(args[i]) end end
    return #args > 1 and oldformat(table.unpack(args)) or args[1]
  end
  format = string.format 
  function self.gensym(s) return (s or "G")..oldtostring({}):match("0x(.*)") end

  local function logHeader(len,str)
    if #str % 2 == 1 then str=str.." " end
    local n = #str+2
    return string.rep("-",len/2-n/2).." "..str.." "..string.rep("-",len/2-n/2)
  end

  local orgDebug = fibaro.QD.debug
  LOG = { LOG="[L] ", ULOG="[U] ", WARNING="[W] ", SYS="[Sys] ", DEBUG="[D] ", ERROR='[ERROR] ', HEADER='HEADER'}
  function Debug(flag,...) if flag then Log(LOG.DEBUG,...) end end
  function Log(flag,...)
    local args={...}
    local str = format(...)
    if flag == LOG.HEADER then str = logHeader(100,str) else str=flag..str end
    for _,s in ipairs(split(str,"\n")) do orgDebug(fibaro.QD,s) end
    return str
  end

  function _assert(test,msg,...) if not test then error(string.format(msg,...),3) end end
  function _assertf(test,msg,fun) if not test then error(string.format(msg,fun and fun() or ""),3) end end
  local function time2str(t) return format("%02d:%02d:%02d",math.floor(t/3600),math.floor((t%3600)/60),t%60) end
  local function midnight() local t = os.date("*t"); t.hour,t.min,t.sec = 0,0,0; return os.time(t) end
  local function hm2sec(hmstr)
    local offs,sun
    sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
    if sun and (sun == 'sunset' or sun == 'sunrise') then
      hmstr,offs = fibaro.getValue(1,sun.."Hour"), tonumber(offs) or 0
    end
    local sg,h,m,s = hmstr:match("^(%-?)(%d+):(%d+):?(%d*)")
    _assert(h and m,"Bad hm2sec string %s",hmstr)
    return (sg == '-' and -1 or 1)*(h*3600+m*60+(tonumber(s) or 0)+(offs or 0)*60)
  end
  local function between(t11,t22)
    local t1,t2,tn = midnight()+hm2sec(t11),midnight()+hm2sec(t22),os.time()
    if t1 <= t2 then return t1 <= tn and tn <= t2 else return tn <= t1 or tn >= t2 end 
  end
  local function toDate(str)
    local y,m,d = str:match("(%d%d%d%d)/(%d%d)/(%d%d)")
    return os.time{year=tonumber(y),month=tonumber(m),day=tonumber(d),hour=0,min=0,sec=0}
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
    if p == '+/' then return hm2sec(time:sub(3))+os.time()
    elseif p == 'n/' then
      local t1,t2 = midnight()+hm2sec(time:sub(3)),os.time()
      return t1 > t2 and t1 or t1+24*60*60
    elseif p == 't/' then return  hm2sec(time:sub(3))+midnight()
    else return hm2sec(time) end
  end

  local gKeys = {type=1,deviceID=2,value=3,val=4,key=5,arg=6,event=7,events=8,msg=9,res=10}
  local gKeysNext = 10
  local function keyCompare(a,b)
    local av,bv = gKeys[a], gKeys[b]
    if av == nil then gKeysNext = gKeysNext+1 gKeys[a] = gKeysNext av = gKeysNext end
    if bv == nil then gKeysNext = gKeysNext+1 gKeys[b] = gKeysNext bv = gKeysNext end
    return av < bv
  end
  function self.prettyJson(e) -- our own json encode, as we don't have 'pure' json structs, and sorts keys in order
    local res,seen = {},{}
    local function pretty(e)
      local t = type(e)
      if t == 'string' then res[#res+1] = '"' res[#res+1] = e res[#res+1] = '"' 
      elseif t == 'number' then res[#res+1] = e
      elseif t == 'boolean' or t == 'function' or t=='thread' then res[#res+1] = tostring(e)
      elseif t == 'table' then
        if next(e)==nil then res[#res+1]='{}'
        elseif seen[e] then res[#res+1]="..rec.."
        elseif e[1] or #e>0 then
          seen[e]=true
          res[#res+1] = "[" pretty(e[1])
          for i=2,#e do res[#res+1] = "," pretty(e[i]) end
          res[#res+1] = "]"
        else
          seen[e]=true
          if e._var_  then res[#res+1] = format('"%s"',e._str) return end
          local k = {} for key,_ in pairs(e) do k[#k+1] = key end 
          table.sort(k,keyCompare)
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

  self.S1 = {click = "16", double = "14", tripple = "15", hold = "12", release = "13"}
  self.S2 = {click = "26", double = "24", tripple = "25", hold = "22", release = "23"} 

  self.netSync = { HTTPClient = function (log)   
      local self,queue,HTTP,key = {},{},net.HTTPClient(),0
      local _request
      local function dequeue()
        table.remove(queue,1)
        local v = queue[1]
        if v then 
          Debug(_debugFlags.netSync,"netSync:Pop %s (%s)",v[3],#queue)
          --setTimeout(function() _request(table.unpack(v)) end,1) 
          _request(table.unpack(v))
        end
      end
      _request = function(url,params,key)
        params = copy(params)
        local uerr,usucc = params.error,params.success
        params.error = function(status)
          Debug(_debugFlags.netSync,"netSync:Error %s %s",key,status)
          dequeue()
          if params._logErr then Log(LOG.ERROR," %s:%s",log or "netSync:",tojson(status)) end
          if uerr then uerr(status) end
        end
        params.success = function(status)
          Debug(_debugFlags.netSync,"netSync:Success %s",key)
          dequeue()
          if usucc then usucc(status) end
        end
        Debug(_debugFlags.netSync,"netSync:Calling %s",key)
        HTTP:request(url,params)
      end
      function self:request(url,parameters)
        key = key+1
        if next(queue) == nil then
          queue[1]='RUN'
          _request(url,parameters,key)
        else 
          Debug(_debugFlags.netSync,"netSync:Push %s",key)
          queue[#queue+1]={url,parameters,key} 
        end
      end
      return self
    end}

--  if hc3_emulator.emulated then self.getWeekNumber = _System.getWeekNumber
--  else self.getWeekNumber = function(tm) return tonumber(os.date("%V",tm)) end end

  function self.dateTest(dateStr)
    local days = {sun=1,mon=2,tue=3,wed=4,thu=5,fri=6,sat=7}
    local months = {jan=1,feb=2,mar=3,apr=4,may=5,jun=6,jul=7,aug=8,sep=9,oct=10,nov=11,dec=12}
    local last,month = {31,28,31,30,31,30,31,31,30,31,30,31},nil

    local function seq2map(seq) local s = {} for _,v in ipairs(seq) do s[v] = true end return s; end

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
      local month = os.date("*t",os.time()).month
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
      local t = os.date("*t",os.time())
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

---- SunCalc -----

  local function sunturnTime(date, rising, latitude, longitude, zenith, local_offset)
    local rad,deg,floor = math.rad,math.deg,math.floor
    local frac = function(n) return n - floor(n) end
    local cos = function(d) return math.cos(rad(d)) end
    local acos = function(d) return deg(math.acos(d)) end
    local sin = function(d) return math.sin(rad(d)) end
    local asin = function(d) return deg(math.asin(d)) end
    local tan = function(d) return math.tan(rad(d)) end
    local atan = function(d) return deg(math.atan(d)) end

    local function day_of_year(date)
      local n1 = floor(275 * date.month / 9)
      local n2 = floor((date.month + 9) / 12)
      local n3 = (1 + floor((date.year - 4 * floor(date.year / 4) + 2) / 3))
      return n1 - (n2 * n3) + date.day - 30
    end

    local function fit_into_range(val, min, max)
      local range,count = max - min
      if val < min then count = floor((min - val) / range) + 1; return val + count * range
      elseif val >= max then count = floor((val - max) / range) + 1; return val - count * range
      else return val end
    end

    -- Convert the longitude to hour value and calculate an approximate time
    local n,lng_hour,t =  day_of_year(date), longitude / 15, nil
    if rising then t = n + ((6 - lng_hour) / 24) -- Rising time is desired
    else t = n + ((18 - lng_hour) / 24) end -- Setting time is desired
    local M = (0.9856 * t) - 3.289 -- Calculate the Sun^s mean anomaly
    -- Calculate the Sun^s true longitude
    local L = fit_into_range(M + (1.916 * sin(M)) + (0.020 * sin(2 * M)) + 282.634, 0, 360)
    -- Calculate the Sun^s right ascension
    local RA = fit_into_range(atan(0.91764 * tan(L)), 0, 360)
    -- Right ascension value needs to be in the same quadrant as L
    local Lquadrant = floor(L / 90) * 90
    local RAquadrant = floor(RA / 90) * 90
    RA = RA + Lquadrant - RAquadrant; RA = RA / 15 -- Right ascension value needs to be converted into hours
    local sinDec = 0.39782 * sin(L) -- Calculate the Sun's declination
    local cosDec = cos(asin(sinDec))
    local cosH = (cos(zenith) - (sinDec * sin(latitude))) / (cosDec * cos(latitude)) -- Calculate the Sun^s local hour angle
    if rising and cosH > 1 then return "N/R" -- The sun never rises on this location on the specified date
    elseif cosH < -1 then return "N/S" end -- The sun never sets on this location on the specified date

    local H -- Finish calculating H and convert into hours
    if rising then H = 360 - acos(cosH)
    else H = acos(cosH) end
    H = H / 15
    local T = H + RA - (0.06571 * t) - 6.622 -- Calculate local mean time of rising/setting
    local UT = fit_into_range(T - lng_hour, 0, 24) -- Adjust back to UTC
    local LT = UT + local_offset -- Convert UT value to local time zone of latitude/longitude
    return os.time({day = date.day,month = date.month,year = date.year,hour = floor(LT),min = math.modf(frac(LT) * 60)})
  end

  local function getTimezone() local now = os.time() return os.difftime(now, os.time(os.date("!*t", now))) end

  function self.sunCalc(time)
    local hc2Info = api.get("/settings/location") or {}
    local lat = hc2Info.latitude
    local lon = hc2Info.longitude
    local utc = getTimezone() / 3600
    local zenith,zenith_twilight = 90.83, 96.0 -- sunset/sunrise 90°50′, civil twilight 96°0′

    local date = os.date("*t",time or os.time())
    if date.isdst then utc = utc + 1 end
    local rise_time = os.date("*t", sunturnTime(date, true, lat, lon, zenith, utc))
    local set_time = os.date("*t", sunturnTime(date, false, lat, lon, zenith, utc))
    local rise_time_t = os.date("*t", sunturnTime(date, true, lat, lon, zenith_twilight, utc))
    local set_time_t = os.date("*t", sunturnTime(date, false, lat, lon, zenith_twilight, utc))
    local sunrise = format("%.2d:%.2d", rise_time.hour, rise_time.min)
    local sunset = format("%.2d:%.2d", set_time.hour, set_time.min)
    local sunrise_t = format("%.2d:%.2d", rise_time_t.hour, rise_time_t.min)
    local sunset_t = format("%.2d:%.2d", set_time_t.hour, set_time_t.min)
    return sunrise, sunset, sunrise_t, sunset_t
  end

  if not hc3_emulator then
    local _IPADDRESS = _HC3IPADDRESS
    function self.getIPaddress()
      if _IPADDRESS then return _IPADDRESS end
      local nets = api.get("/settings/network").networkConfig or {}
      if nets.wlan0.enabled then
        _IPADDRESS =  nets.wlan0.ipConfig.ip
      elseif nets.eth0.enabled then
        _IPADDRESS =  nets.eth0.ipConfig.ip
      else
        error("Can't find IP address")
      end
      return _IPADDRESS
    end
  else 
    self.getIPaddress = hc3_emulator.getIPaddress 
  end

  self.equal,self.copy,self.transform,self.toTime,self.hm2sec,self.midnight  = equal,copy,transform,toTime,hm2sec,midnight
  tojson = self.prettyJson
  return self
end -- Utils

----------------- Module Remote support -----------------------
function module.Remote()
  Log(LOG.SYS,"Setting up remote  support..")
  local function printSendEvent(e) return string.format("to %d %s",e.to,e.event) end

  local ces = api.get("/customEvents") -- Remove stale events
  for _,ce in ipairs(ces) do
    if Event.isMyAddress(ce.name) then Event.deleteCustomEvent(ce.name) end
  end

  Event.event({type='%sendEvent%'},function(env)
      local event = env.event.event
      event._from = Event.deviceID
      event._time = os.time()
      if env.event.fc then
        fibaro.call(env.event.to,"ER_remoteEvent",json.encode(event))
      else
        local address = Event.makeAddress(env.event.to)
        Event.createCustomEvent(address,json.encode(event))
        Event.postCustomEvent(address)
        if env.event.to=="000" then
          setTimeout(function() Event.deleteCustomEvent(address) end,6*1000) -- Remove after 4s
        end
      end
    end)

  function Event.postRemote(toid,event,time) 
    Event.post({type='%sendEvent%',to=toid,event=event, fc=true, __tostring=printSendEvent},time) 
  end
  function Event.broadcastEvent(event,time) 
    Event.post({type='%sendEvent%',to="000", event=event, __tostring=printSendEvent},time) 
  end

  function QuickApp:ER_remoteEvent(e)
    local stat,res = true,e
    if type(e) == 'string' then 
      stat,res = type(e)=='table' and pcall(function() return (json.decode(e)) end)
    end
    if stat and Event.isEvent(res) then 
      if res._time and res._time+5 < os.time() then 
        Log(LOG.WARNING,"Slow events %s, %ss",e,os.time()-res._time) 
      end
      res._time = nil
      Event.post(res)
    else Log(LOG.ERROR,"Bad arg to 'recieveEvent' "..tostring(e)) end
  end

  Event.event({type='customevent'}, -- Triggering on a custom event
    function(env) 
      local ev = env.event
      local address,broadcast = ev.name,Event.isBroadcastAddress(ev.name)
      if Event.isMyAddress(address) or broadcast then
        if ev.value then fibaro.QD:ER_remoteEvent(ev.value) end
        if not broadcast then Event.deleteCustomEvent(address) end
        return Event.BREAK
      end
    end)

  ---- Remote calls

  local TIMEOUT = 4

  function defineRemoteFun(name,deviceID,tab) (tab or _G or _ENV)[name] = function(...) return funCall(deviceID,name,{...}) end end

  function exportFunctions(funList) fibaro.QD:setVariable("ExportedFuns",json.encode(funList)) end
  function importFunctions(deviceID,tab,log)
    log = log==nil and true or log    
    for _,v in ipairs(fibaro.getValue(deviceID,'quickAppVariables') or {}) do
      if v.name == "ExportedFuns" then
        for _,ef in ipairs(json.decode(v.value) or {}) do
          ef = type(ef)=='string' and {name=ef} or ef
          if log then Log(LOG.SYS,"importing fun %s:%s%s",deviceID,ef.name,ef.doc and (" - "..ef.doc) or "") end
          defineRemoteFun(ef.name,deviceID,tab)
        end
        return
      end
    end
    fibaro.QD:debug("No exported functions from deviceID:"..deviceID)
  end

  local FUNRES = nil
  local ASYNC = {"ASYNC"}

  function funCall(deviceID,fun,args)
    if not FUNRES then
      FUNRES = "RPC"..Event.deviceID
      api.post("/globalVariables/",{name=FUNRES,value=""})
    end
    if args[1]==ASYNC then return deviceID,fun end
    local timeout,res = os.time()+TIMEOUT,nil
    fibaro.setGlobalVariable(FUNRES,"")
    fibaro.call(deviceID,"funCall",json.encode({name=fun,args=args,from=FUNRES}))
    repeat res=fibaro.getGlobalVariable(FUNRES) until res~="" or timeout < os.time()
    if res~="" then
      res = json.decode(res)
      if res[1] then return table.unpack(res[2])
      else 
        error(string.format("Remote function error %s:%s - %s",deviceID,fun,res[2]),3)
      end
    end 
    error(string.format("Remote function %s:%s timed out",deviceID,fun),3)
  end

-- Receieve function call and return reponse
  function QuickApp:funCall(call) -- Receieve a remote funcall
    local stat,res = pcall(function() return {_G[call.name](table.unpack(call.args))} end)
    --Log(LOG.LOG,"RES:%s - %s",res,call.from)
    fibaro.setGlobalVariable(call.from,json.encode({stat,res}))
  end

end -- createRemoteFunctionSupport 

----------------- Autopatch support ---------------------------
function module.Autopatch()
  local self = {}
  Log(LOG.SYS,"Setting up autopatch support..")
  local _EVENTSSRCPATH = "EventRunner4.lua"
  local versionInfo = nil

  local function fetchVersionInfo(cont)
    local req = net.HTTPClient()
    req:request("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/VERSION4.json",{
        options = {method = 'GET', checkCertificate = false, timeout=20000},
        success=function(data)
          if data.status == 200 then 
            versionInfo = json.decode(data.data)
            if cont then cont() end
          end
        end})
  end

  function Util.checkEventRunnerVersion(vers)
    versionInfo = nil
    fetchVersionInfo(function()
        if versionInfo and versionInfo[_EVENTSSRCPATH].version ~= E_VERSION then
          Event.post({type='ER_version',version=versionInfo[_EVENTSSRCPATH].version, _sh=true})
        end
      end)
  end

  local _EVENTSDELIMETER = "%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%- EventSupport %- Don't change! "

  function Util.patchEventRunner(newSrc)
    if newSrc == nil then
      local req = net.HTTPClient()
      req:request("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/".._EVENTSSRCPATH,{
          options = {method = 'GET', checkCertificate = false, timeout=20000},
          success=function(data) if data.status == 200 then Util.patchEventRunner(data.data) end end,
          error=function(status) Log(LOG.ERROR,"Get src code from Github: %s",status) end
        })
      return
    end
    local oldSrc = api.get("/devices/"..fibaro.ID).properties.mainFunction
    local obp = oldSrc:find(_EVENTSDELIMETER)
    oldSrc = oldSrc:sub(1,obp-1) -- Save start of old file - contains user stuff
    local nbp = newSrc:find(_EVENTSDELIMETER)
    local nbody = newSrc:sub(nbp) -- copy rest of new file - contains updated stuff
    oldSrc = oldSrc:gsub("(E_VERSION,E_FIX = .-\n)",newSrc:match("(E_VERSION,E_FIX = .-\n)"))
    Log(LOG.SYS,"Patching scene to latest version")
    if not hc3_emulator then
      local stat,res = api.put("/devices/"..fibaro.ID,{properties = {mainFunction = oldSrc..nbody}})
      if not stat then 
        Log(LOG.ERROR,"Could not update mainFunction (%s)",res) 
        Log(LOG.SYS"Restarting...")
      end
    end
  end

  -- code == {{name=name, code=code},{name=name, code=code} ...}
  function self.addCode(code) -- Add code to uiCallback, without defining any UI element
    local uicb = api.get("/devices/"..plugin.mainDeviceId).properties.uiCallbacks
    local map,changed = {},false
    for _,cb in ipairs(uicb) do map[cb.name]=cb.callback end
    for _,cb in ipairs(code or {}) do
      if not (map[cb.name] and map[cb.name]==cb.code) then 
        changed=true
        map[cb.name]=cb.code 
      end 
    end
    if not changed then return end -- Only update if anything changed, otherwise we loop forever...
    uicb = {} 
    for k,v in pairs(map) do uicb[#uicb+1]={name=k,callback=v,eventType='pressed'} end
    api.put("/devices/"..plugin.mainDeviceId,{ properties = { uiCallbacks = uicb} } )
  end

  function self.activateCode(self,name)
    self:callAction("component"..name.."Clicked", unpack('{"values":[null]}'))
  end

  if hc3_emulated then
  else
    function self.loadModule(str)
    end
  end
  return self
end


----------------- Module Extras -------------------------------
function module.Extras()
  -- Sunset/sunrise patch -- first time in the day someone asks for sunsethours we calculate and cahche
  local _SUNTIMEDAY = nil
  local _SUNTIMEVALUES = {sunsetHour="00:00",sunriseHour="00:00",dawnHour="00:00",duskHour="00:00"}
  Util.defineVirtualDevice(1,nil,function(id,prop,...)
      if not _SUNTIMEVALUES[prop] then return nil end
      local s = _SUNTIMEVALUES
      local day = os.date("*t").day
      if day ~= _SUNTIMEDAY then
        _SUNTIMEDAY = day
        s.sunriseHour,s.sunsetHour,s.dawnHour,s.duskHour=Util.sunCalc()
      end
      return true,{_SUNTIMEVALUES[prop],os.time()}
    end)

  local DEBUGKEYS = {debugTriggers=true,debugRules=true,debugPost=true}

  local function updateDebugKey(key,upd)
    local name = key:match("debug(.*)")
    local dkey = name:lower()
    if upd then _debugFlags[dkey] = not _debugFlags[dkey] end
    fibaro.QD:updateView(key,"text",name..":"..(_debugFlags[dkey] and "ON" or "OFF"))
  end

  for k,_ in pairs(DEBUGKEYS) do updateDebugKey(k) end

  Event.event({type='UI'},function(env)
      local b = env.event.name
      if DEBUGKEYS[b] then updateDebugKey(b,true) end
    end)

  function Event.subscribe(event,h) 

  end

  function Event.publish(event) Event.broadcastEvent(event) end

  function add100(x) return x+100 end   -- test
  function add1000(x) return x+1000 end -- test
end

----------------- EventScript support -------------------------
function module.EventScript()
  local ScriptParser,ScriptCompiler,ScriptEngine

  function makeEventScriptParser()
    local source, tokens, cursor
    local mkStack,mkStream,toTime,map,mapkk,gensym=Util.mkStack,Util.mkStream,Util.toTime,Util.map,Util.mapkk,Util.gensym
    local patterns,self = {},{}
    local opers = {['%neg']={14,1},['t/']={14,1,'%today'},['n/']={14,1,'%nexttime'},['+/']={14,1,'%plustime'},['$']={14,1,'%vglob'},
      ['.']={12.9,2},[':']= {13,2,'%prop'},['..']={9,2,'%betw'},['...']={9,2,'%betwo'},['@']={9,1,'%daily'},['jmp']={9,1},['::']={9,1},--['return']={-0.5,1},
      ['@@']={9,1,'%interv'},['+']={11,2},['-']={11,2},['*']={12,2},['/']={12,2},['%']={12,2},['==']={6,2},['<=']={6,2},['>=']={6,2},['~=']={6,2},
      ['>']={6,2},['<']={6,2},['&']={5,2,'%and'},['|']={4,2,'%or'},['!']={5.1,1,'%not'},['=']={0,2},['+=']={0,2},['-=']={0,2},
      ['*=']={0,2},[';']={-1,2,'%progn'},
    }
    local nopers = {['jmp']=true,}--['return']=true}
    local reserved={
      ['sunset']={{'sunset'}},['sunrise']={{'sunrise'}},['midnight']={{'midnight'}},['dusk']={{'dusk'}},['dawn']={{'dawn'}},
      ['now']={{'now'}},['wnum']={{'wnum'}},['env']={{'env'}},
      ['true']={true},['false']={false},['{}']={{'quote',{}}},['nil']={{'%quote',nil}},
    }
    local function apply(t,st) return st.push(st.popn(opers[t.value][2],{t.value})) end
    local _samePrio = {['.']=true,[':']=true}
    local function lessp(t1,t2) 
      local v1,v2 = t1.value,t2.value
      if v1==':' and v2=='.' then return true 
      elseif v1=='=' then v1='/' end
      return v1==v2 and _samePrio[v1] or opers[v1][1] < opers[v2][1] 
    end
    local function isInstr(i,t) return type(i)=='table' and i[1]==t end

    local function tablefy(t)
      local res={}
      for k,e in pairs(t) do if isInstr(e,'=') then res[e[2][2]]=e[3] else res[k]=e end end
      return res
    end

    local pExpr,gExpr={}
    pExpr['lpar']=function(inp,st,ops,t,pt)
      if pt.value:match("^[%]%)%da-zA-Z]") then 
        while not ops.isEmpty() and opers[ops.peek().value][1] >= 12.9 do apply(ops.pop(),st) end
        local fun,args = st.pop(),self.gArgs(inp,')')
        if isInstr(fun,':') then st.push({'%calls',{'%aref',fun[2],fun[3]},fun[2],table.unpack(args)})
        elseif isInstr(fun,'%var') then st.push({fun[2],table.unpack(args)})
        elseif type(fun)=='string' then st.push({fun,table.unpack(args)})
        else st.push({'%calls',fun,table.unpack(args)}) end
      else
        st.push(gExpr(inp,{[')']=true})) inp.next()
      end
    end
    pExpr['lbra']=function(inp,st,ops,t,pt) 
      while not ops.isEmpty() and opers[ops.peek().value][1] >= 12.9 do apply(ops.pop(),st) end
      st.push({'%aref',st.pop(),gExpr(inp,{[']']=true})}) inp.next() 
    end
    pExpr['lor']=function(inp,st,ops,t,pt) 
      local e = gExpr(inp,{['>>']=true}); inp.next()
      local body,el = gExpr(inp,{[';;']=true,['||']=true})
      if inp.peek().value == '||' then el = gExpr(inp) else inp.next() end
      st.push({'if',e,body,el})
    end
    pExpr['lcur']=function(inp,st,ops,t,pt) st.push({'%table',tablefy(self.gArgs(inp,'}'))}) end
    pExpr['ev']=function(inp,st,ops,t,pt) local v = {}
      if inp.peek().value == '{' then inp.next() v = tablefy(self.gArgs(inp,'}')) end
      v.type = t.value:sub(2); st.push({'%table',v})
    end
    pExpr['num']=function(inp,st,ops,t,pt) st.push(t.value) end
    pExpr['str']=function(inp,st,ops,t,pt) st.push(t.value) end
    pExpr['nam']=function(inp,st,ops,t,pt) 
      if reserved[t.value] then st.push(reserved[t.value][1]) 
      elseif pt.value == '.' or pt.value == ':' then st.push(t.value) 
      else st.push({'%var',t.value,'script'}) end -- default to script vars
    end
    pExpr['op']=function(inp,st,ops,t,pt)
      if t.value == '-' and not(pt.type == 'name' or pt.type == 'number' or pt.value == '(') then t.value='%neg' end
      while ops.peek() and lessp(t,ops.peek()) do apply(ops.pop(),st) end
      ops.push(t)
    end

    function gExpr(inp,stop)
      local st,ops,t,pt=mkStack(),mkStack(),{value='<START>'}
      while true do
        t,pt = inp.peek(),t
        if t.type=='eof' or stop and stop[t.value] then break end
        t = inp.next()
        pExpr[t.sw](inp,st,ops,t,pt)
      end
      while not ops.isEmpty() do apply(ops.pop(),st) end
      --st.dump()
      return st.pop()
    end

    function self.gArgs(inp,stop)
      local res,i = {},1
      while inp.peek().value ~= stop do _assert(inp.peek().type~='eof',"Missing ')'"); res[i] = gExpr(inp,{[stop]=true,[',']=true}); i=i+1; if inp.peek().value == ',' then inp.next() end end
      inp.next() return res
    end

    local function token(pattern, createFn)
      table.insert(patterns, function ()
          local _, len, res, group = string.find(source, "^(" .. pattern .. ")")
          if len then
            if createFn then
              local token = createFn(group or res)
              token.from, token.to = cursor, cursor+len
              table.insert(tokens, token)
            end
            source = string.sub(source, len+1)
            cursor = cursor + len
            return true
          end
        end)
    end

    local function toTimeDate(str)
      local y,m,d,h,min,s=str:match("(%d?%d?%d?%d?)/?(%d+)/(%d+)/(%d%d):(%d%d):?(%d?%d?)")
      local t = os.date("*t")
      return os.time{year=y~="" and y or t.year,month=m,day=d,hour=h,min=min,sec=s~="" and s or 0}
    end

    local SW={['(']='lpar',['{']='lcur',['[']='lbra',['||']='lor'}
    token("[%s%c]+")
    --2019/3/30/20:30
    token("%d?%d?%d?%d?/?%d+/%d+/%d%d:%d%d:?%d?%d?",function (t) return {type="number", sw='num', value=toTimeDate(t)} end)
    token("%d%d:%d%d:?%d?%d?",function (t) return {type="number", sw='num', value=toTime(t)} end)
    token("[t+n][/]", function (op) return {type="operator", sw='op', value=op} end)
    token("#[A-Za-z_][%w_]*", function (w) return {type="event", sw='ev', value=w} end)
    --token("[A-Za-z_][%w_]*", function (w) return {type=nopers[w] and 'operator' or "name", sw=nopers[w] and 'op' or 'nam', value=w} end)
    token("[_a-zA-Z\xC3\xA5\xA4\xB6\x85\x84\x96][_0-9a-zA-Z\xC3\xA5\xA4\xB6\x85\x84\x96]*", function (w) return {type=nopers[w] and 'operator' or "name", sw=nopers[w] and 'op' or 'nam', value=w} end)
    token("%d+%.%d+", function (d) return {type="number", sw='num', value=tonumber(d)} end)
    token("%d+", function (d) return {type="number", sw='num', value=tonumber(d)} end)
    token('"([^"]*)"', function (s) return {type="string", sw='str', value=s} end)
    token("'([^']*)'", function (s) return {type="string", sw='str', value=s} end)
    token("%-%-.-\n")
    token("%-%-.*")  
    token("%.%.%.",function (op) return {type="operator", sw=SW[op] or 'op', value=op} end)
    token("[@%$=<>!+%.%-*&|/%^~;:][@=<>&|;:%.]?", function (op) return {type="operator", sw=SW[op] or 'op', value=op} end)
    token("[{}%(%),%[%]#%%]", function (op) return {type="operator", sw=SW[op] or 'op', value=op} end)


    local function dispatch() for _,m in ipairs(patterns) do if m() then return true end end end

    local function tokenize(src)
      source, tokens, cursor = src, {}, 0
      while #source>0 and dispatch() do end
      if #source > 0 then print("tokenizer failed at " .. source) end
      return tokens
    end

    local postP={}
    postP['%progn'] = function(e) local r={'%progn'}
      map(function(p) if isInstr(p,'%progn') then for i=2,#p do r[#r+1] = p[i] end else r[#r+1]=p end end,e,2)
      return r
    end
    postP['%vglob'] = function(e) return {'%var',e[2][2],'glob'} end
    postP['='] = function(e) 
      local lv,rv = e[2],e[3]
      if type(lv) == 'table' and ({['%var']=true,['%prop']=true,['%aref']=true,['slider']=true,['label']=true})[lv[1]] then
        return {'%set',lv[1]:sub(1,1)~='%' and '%'..lv[1] or lv[1],lv[2], lv[3] or true, rv}
      else error("Illegal assignment") end
    end
    postP['%betwo'] = function(e) 
      local t = Util.gensym("TODAY")
      return {'%and',{'%betw', e[2],e[3]},{'%and',{'~=',{'%var',t,'script'},{'%var','dayname','script'}},{'%set','%var',t,'script',{'%var','dayname','script'}}}}
    end 
    postP['if'] = function(e) local c = {'%and',e[2],{'%always',e[3]}} return self.postParse(#e==3 and c or {'%or',c,e[4]}) end
    postP['=>'] = function(e) return {'%rule',{'%quote',e[2]},{'%quote',e[3]}} end
    postP['.'] = function(e) return {'%aref',e[2],e[3]} end
    postP['::'] = function(e) return {'%addr',e[2][2]} end
    postP['%jmp'] = function(e) return {'%jmp',e[2][2]} end
    -- preC['return'] = function(e) return {'return',e[2]} end
    postP['%neg'] = function(e) return tonumber(e[2]) and -e[2] or e end
    postP['+='] = function(e) return {'%inc',e[2],e[3],'+'} end
    postP['-='] = function(e) return {'%inc',e[2],e[3],'-'} end
    postP['*='] = function(e) return {'%inc',e[2],e[3],'*'} end
    postP['+'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])+tonumber(e[3]) or e end
    postP['-'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])-tonumber(e[3]) or e end
    postP['*'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])*tonumber(e[3]) or e end
    postP['/'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])/tonumber(e[3]) or e end
    postP['%'] = function(e) return tonumber(e[2]) and tonumber(e[3]) and tonumber(e[2])%tonumber(e[3]) or e end

    function self.postParse(e)
      local function traverse(e)
        if type(e)~='table' or e[1]=='quote' then return e end
        if opers[e[1]] then 
          e[1]=opers[e[1]][3] or e[1]
        end
        local pc = mapkk(traverse,e); return postP[pc[1]] and postP[pc[1]](pc) or pc
      end
      return traverse(e)
    end

    local gStatements; local gElse; 
    local function matchv(inp,t,v) local t0=inp.next(); _assert(t0.value==t,"Expected '%s' in %s",t,v); return t0 end
    local function matcht(inp,t,v) local t0=inp.next(); _assert(t0.type==t,"Expected %s",v); return t0 end

    local function mkVar(n) return {'%var',n and n or gensym("V"),'script'} end
    local function mkSet(v,e) return {'%set',v[1],v[2],v[3],e} end        
    local function gStatement(inp,stop)
      local t,vars,exprs = inp.peek(),{},{}
      if t.value=='local' then inp.next()
        vars[1] = matcht(inp,'name',"variable in 'local'").value
        while inp.peek().value==',' do inp.next(); vars[#vars+1]= matcht(inp,'name',"variable in 'local'").value end
        if inp.peek().value == '=' then
          inp.next()
          exprs[1] = {gExpr(inp,{[',']=true,[';']=true})}
          while inp.peek().value==',' do inp.next(); exprs[#exprs+1]= {gExpr(inp,{[',']=true,[';']=true})} end
        end
        return {'%local',vars,exprs}
      elseif t.value == 'while' then inp.next()
        local test = gExpr(inp,{['do']=true}); matchv(inp,'do',"While loop")
        local body = gStatements(inp,{['end']=true}); matchv(inp,'end',"While loop")
        return {'%frame',{'%while',test,body}}
      elseif t.value == 'repeat' then inp.next()
        local body = gStatements(inp,{['until']=true}); matchv(inp,'until',"Repeat loop")
        local test = gExpr(inp,stop)
        return {'%frame',{'%repeat',body,test}}
      elseif t.value == 'begin' then inp.next()
        local body = gStatements(inp,{['end']=true}); matchv(inp,'end',"Begin block")
        return {'%frame',body} 
      elseif t.value == 'for' then inp.next()
        local var = matcht(inp,'name').value; 
        if inp.peek().value==',' then -- for a,b in f(x) do ...  end
          matchv(inp,','); --local l,a,b,c,i; c=pack(f(x)); i=c[1]; l=c[2]; c=pack(i(l,c[3])); while c[1] do a=c[1]; b=c[2]; ... ; c=pack(i(l,a)) end
          local var2 = matcht(inp,'name').value; 
          matchv(inp,'in',"For loop"); 
          local expr = gExpr(inp,{['do']=true}); matchv(inp,'do',"For loop")
          local body = gStatements(inp,{['end']=true}); matchv(inp,'end',"For loop")
          local v1,v2,i,l = mkVar(var),mkVar(var2),mkVar(),mkVar()
          return {'%frame',{'%progn',{'%local',{var,var2,l[2],i[2]},{}},
              {'setList',{i,l,v1},{'pack',expr}},{'setList',{v1,v2},{'pack',{'%calls',i,l,v1}}},
              {'%while',v1,{'%progn',body,{'setList',{v1,v2},{'pack',{'%calls',i,l,v1}}}}}}}
        else -- for for a = x,y,z  do ... end
          matchv(inp,'=') -- local a,e,s,si=x,y,z; si=sign(s); e*=si while a*si<=e do ... a+=s end
          local inits = {}
          inits[1] = {gExpr(inp,{[',']=true,['do']=true})}
          while inp.peek().value==',' do inp.next(); inits[#inits+1]= {gExpr(inp,{[',']=true,['do']=true})} end
          matchv(inp,'do',"For loop")
          local body = gStatements(inp,{['end']=true}); matchv(inp,'end',"For loop")
          local v,s,e,step = mkVar(var),mkVar(),mkVar(),mkVar()
          if #inits<3 then inits[#inits+1]={1} end
          local locals = {'%local',{var,e[2],step[2],s[2]},inits}
          return {'%frame',{'%progn',locals,mkSet(s,{'sign',step}),{'*=',e,s},{'%while',{'<=',{'*',v,s},e},{'%progn',body,{'+=',v,step}}}}}
        end
      elseif t.value == 'if' then inp.next()
        local test = gExpr(inp,{['then']=true}); matchv(inp,'then',"If statement")
        local body = gStatements(inp,{['end']=true,['else']=true,['elseif']=true})
        return {'if',test,{'%frame',body},gElse(inp)}
      else return gExpr(inp,stop) end 
    end

    function gElse(inp)
      if inp.peek().value=='end' then inp.next(); return nil end
      if inp.peek().value=='else' then inp.next()
        local r = gStatements(inp,{['end']=true}); matchv(inp,'end',"If statement"); return {'%frame',r}
      end
      if inp.peek().value=='elseif' then inp.next(); 
        local test = gExpr(inp,{['then']=true}); matchv(inp,'then',"If statement")
        local body = gStatements(inp,{['end']=true,['else']=true,['elseif']=true})  
        return {'if',test,{'%frame',body},gElse(inp)}
      end
      error()
    end

    function gStatements(inp,stop)
      local progn = {'%progn'}; stop=stop or {}; stop[';']=true; progn[2] = gStatement(inp,stop)
      while inp.peek().value == ';' do
        inp.next(); progn[#progn+1] = gStatement(inp,stop)
      end
      return #progn > 2 and progn or progn[2]
    end

    local statement={['while']=true,['repeat']=true,['if']=true,['local']=true,['begin']=true,['for']=true}
    local function gRule(inp)
      if statement[inp.peek().value] then return gStatements(inp) end
      local e = gExpr(inp,{['=>']=true,[';']=true})
      if inp.peek().value=='=>' then inp.next()
        return {'=>',e,gStatements(inp)}
      elseif inp.peek().value==';' then inp.next()
        local s = gStatements(inp)
        return {'%progn',e,s}
      else return e end
    end

    function self.parse(str)
      local tokens = mkStream(tokenize(str))
      --for i,v in ipairs(tokens.stream) do print(v.type, v.value, v.from, v.to) end
      local stat,res = pcall(function() return self.postParse(gRule(tokens)) end)
      if not stat then local t=tokens.last() error(string.format("Parser error char %s ('%s') in expression '%s' (%s)",t.from+1,str:sub(t.from+1,t.to),str,res)) end
      return res
    end

    return self
  end

---------- Event Script Compiler --------------------------------------
  function makeEventScriptCompiler(parser)
    local self,comp,gensym,isVar,isGlob={ parser=parser },{},Util.gensym,Util.isVar,Util.isGlob
    local function mkOp(o) return o end
    local POP = {mkOp('%pop'),0}

    local function compT(e,ops)
      if type(e) == 'table' then
        local ef = e[1]
        if comp[ef] then comp[ef](e,ops)
        else for i=2,#e do compT(e[i],ops) end ops[#ops+1] = {mkOp(e[1]),#e-1} end -- built-in fun
      else 
        ops[#ops+1]={mkOp('%push'),0,e} -- constants etc
      end
    end

    comp['%quote'] = function(e,ops) ops[#ops+1] = {mkOp('%push'),0,e[2]} end
    comp['%var'] = function(e,ops) ops[#ops+1] = {mkOp('%var'),0,e[2],e[3]} end
    comp['%addr'] = function(e,ops) ops[#ops+1] = {mkOp('%addr'),0,e[2]} end
    comp['%jmp'] = function(e,ops) ops[#ops+1] = {mkOp('%jmp'),0,e[2]} end
    comp['%frame'] = function(e,ops) ops[#ops+1] = {mkOp('%frame'),0} compT(e[2],ops) ops[#ops+1] = {mkOp('%unframe'),0} end  
    comp['%eventmatch'] = function(e,ops) ops[#ops+1] = {mkOp('%eventmatch'),0,e[2],e[3]} end
    comp['setList'] = function(e,ops) compT(e[3],ops); ops[#ops+1]={mkOp('%setlist'),1,e[2]} end
    comp['%set'] = function(e,ops)
      if e[2]=='%var' then
        if type(e[5])~='table' then ops[#ops+1] = {mkOp('%setvar'),0,e[3],e[4],e[5]} 
        else compT(e[5],ops); ops[#ops+1] = {mkOp('%setvar'),1,e[3],e[4]} end
      else
        local args,n = {},1;
        if type(e[4])~='table' then args[2]={e[4]} else args[2]=false compT(e[4],ops) n=n+1 end
        if type(e[5])~='table' then args[1]={e[5]} else args[1]=false compT(e[5],ops) n=n+1 end
        compT(e[3],ops)
        ops[#ops+1] = {mkOp('%set'..e[2]:sub(2)),n,table.unpack(args)} 
      end
    end
    comp['%aref'] = function(e,ops)
      compT(e[2],ops) 
      if type(e[3])~='table' then ops[#ops+1] = {mkOp('%aref'),1,e[3]} 
      else compT(e[3],ops); ops[#ops+1] = {mkOp('%aref'),2} end
    end
    comp['%prop'] = function(e,ops)
      _assert(type(e[3])=='string',"non constant property '%s'",function() return json.encode(e[3]) end)
      compT(e[2],ops); ops[#ops+1] = {mkOp('%prop'),1,e[3]} 
    end
    comp['%table'] = function(e,ops) local keys={}
      for key,val in pairs(e[2]) do keys[#keys+1] = key; compT(val,ops) end
      ops[#ops+1]={mkOp('%table'),#keys,keys}
    end
    comp['%and'] = function(e,ops) 
      compT(e[2],ops)
      local o1,z = {mkOp('%ifnskip'),0,0}
      ops[#ops+1] = o1 -- true skip 
      z = #ops; ops[#ops+1]= POP; compT(e[3],ops); o1[3] = #ops-z+1
    end
    comp['%or'] = function(e,ops)  
      compT(e[2],ops)
      local o1,z = {mkOp('%ifskip'),0,0}
      ops[#ops+1] = o1 -- true skip 
      z = #ops; ops[#ops+1]= POP; compT(e[3],ops); o1[3] = #ops-z+1;
    end
    comp['%inc'] = function(e,ops) 
      if tonumber(e[3]) then ops[#ops+1] = {mkOp('%inc'..e[4]),0,e[2][2],e[2][3],e[3]}
      else compT(e[3],ops) ops[#ops+1] = {mkOp('%inc'..e[4]),1,e[2][2],e[2][3]} end 
    end
    comp['%progn'] = function(e,ops)
      if #e == 2 then compT(e[2],ops) 
      elseif #e > 2 then for i=2,#e-1 do compT(e[i],ops); ops[#ops+1]=POP end compT(e[#e],ops) end
    end
    comp['%local'] = function(e,ops)
      for _,e1 in ipairs(e[3]) do compT(e1[1],ops) end
      ops[#ops+1]={mkOp('%local'),#e[3],e[2]}
    end
    comp['%while'] = function(e,ops) -- lbl1, test, infskip lbl2, body, jmp lbl1, lbl2
      local test,body,lbl1,cp=e[2],e[3],gensym('LBL1')
      local jmp={mkOp('%ifnskip'),0,nil,true}
      ops[#ops+1] = {'%addr',0,lbl1}; ops[#ops+1] = POP
      compT(test,ops); ops[#ops+1]=jmp; cp=#ops
      compT(body,ops); ops[#ops+1]=POP; ops[#ops+1]={mkOp('%jmp'),0,lbl1}
      jmp[3]=#ops+1-cp
    end
    comp['%repeat'] = function(e,ops) -- -- lbl1, body, test, infskip lbl1
      local body,test,z=e[2],e[3],#ops
      compT(body,ops); ops[#ops+1]=POP; compT(test,ops)
      ops[#ops+1] = {mkOp('%ifnskip'),0,z-#ops,true}
    end

    function self.compile(src,log) 
      local code,res=type(src)=='string' and self.parser.parse(src) or src,{}
      if log and log.code then print(json.encode(code)) end
      compT(code,res) 
      if log and log.code then if ScriptEngine then  ScriptEngine.dump(res) end end
      return res 
    end
    function self.compile2(code) local res={}; compT(code,res); return res end
    return self
  end

---------- Event Script RunTime --------------------------------------
  function makeEventScriptRuntime()
    local self,instr={},{}
    local format,coroutine = string.format,Util.coroutine
    local function safeEncode(e) local stat,res = pcall(function() return tojson(e) end) return stat and res or tostring(e) end
    local toTime,midnight,map,mkStack,copy,coerce,isEvent=Util.toTime,Util.midnight,Util.map,Util.mkStack,Util.copy,Event.coerce,Event.isEvent
    local _vars,triggerVar = Util._vars,Util.triggerVar

    local function getVarRec(var,locs) return locs[var] or locs._next and getVarRec(var,locs._next) end
    local function getVar(var,env) local v = getVarRec(var,env.locals); env._lastR = var
      if v then return v[1]
      elseif _vars[var] then return _vars[var][1]
      elseif _ENV[var]~=nil then return _ENV[var] end
    end
    local function setVar(var,val,env) local v = getVarRec(var,env.locals)
      if v then v[1] = val
      else
        local oldVal 
        if _vars[var] then oldVal=_vars[var][1]; _vars[var][1] = val else _vars[var]={val} end
        if triggerVar(var) and oldVal ~= val then Event.post({type='variable', name=var, value=val}) end
        --elseif _ENV[var] then return _ENV[var] end -- allow for setting Lua globals
      end
      return val 
    end

    -- Primitives
    instr['%pop'] = function(s) s.pop() end
    instr['%push'] = function(s,n,e,i) s.push(i[3]) end
    instr['%ifnskip'] = function(s,n,e,i) if not s.peek() then e.cp=e.cp+i[3]-1; end if i[4] then s.pop() end end
    instr['%ifskip'] = function(s,n,e,i) if s.peek() then e.cp=e.cp+i[3]-1; end if i[4] then s.pop() end end
    instr['%addr'] = function(s,n,e,i) s.push(i[3]) end
    instr['%frame'] = function(s,n,e,i)  e.locals = {_next=e.locals} end
    instr['%unframe'] = function(s,n,e,i)  e.locals = e.locals._next end
    instr['%jmp'] = function(s,n,e,i) local addr,c,p = i[3],e.code,i[4]
      if p then  e.cp=p-1 return end  -- First time we search for the label and cache the position
      for k=1,#c do if c[k][1]=='%addr' and c[k][3]==addr then i[4]=k e.cp=k-1 return end end 
      error({"jump to bad address:"..addr}) 
    end
    instr['%table'] = function(s,n,e,i) local k,t = i[3],{} for j=n,1,-1 do t[k[j]] = s.pop() end s.push(t) end
    local function getArg(s,e) if e then return e[1] else return s.pop() end end
    instr['%aref'] = function(s,n,e,i) local k,tab 
      if n==1 then k,tab=i[3],s.pop() else k,tab=s.pop(),s.pop() end
      _assert(type(tab)=='table',"attempting to index non table with key:'%s'",k); e._lastR = k
      s.push(tab[k])
    end
    instr['%setaref'] = function(s,n,e,i) local r,v,k = s.pop(),getArg(s,i[3]),getArg(s,i[4])
      _assertf(type(r)=='table',"trying to set non-table value '%s'",function() return json.encode(r) end)
      r[k]= v; s.push(v) 
    end
    local _marshalBool={['true']=true,['True']=true,['TRUE']=true,['false']=false,['False']=false,['FALSE']=false}

    local function marshallFrom(v) 
      if not _MARSHALL then return v elseif v==nil then return v end
      local fc = v:sub(1,1)
      if fc == '[' or fc == '{' then local s,t = pcall(json.decode,v); if s then return t end end
      if tonumber(v) then return tonumber(v)
      elseif _marshalBool[v ]~=nil then return _marshalBool[v ] end
      local s,t = pcall(toTime,v); return s and t or v 
    end
    local function marshallTo(v) 
      if not _MARSHALL then return v end
      if type(v)=='table' then return safeEncode(v) else return tostring(v) end
    end
    local getVarFs = { script=getVar, glob=function(n,e) return marshallFrom(fibaro.getGlobalVariable(n)) end }
    local setVarFs = { script=setVar, glob=function(n,v,e) fibaro.setGlobalVariable(n,marshallTo(v)) return v end }
    instr['%var'] = function(s,n,e,i) s.push(getVarFs[i[4]](i[3],e)) end
    instr['%setvar'] = function(s,n,e,i) if n==1 then setVarFs[i[4]](i[3],s.peek(),e) else s.push(setVarFs[i[4]](i[3],i[5],e)) end end
    instr['%local'] = function(s,n,e,i) local vn,ve = i[3],s.lift(n); e.locals = e.locals or {}
      local i,x=1; for _,v in ipairs(vn) do x=ve[i]; e.locals[v]={ve[i]}; i=i+1 end
      s.push(x) 
    end
    instr['%setlist'] = function(s,n,e,i) 
      local vars,arg,r = i[3],s.pop() 
      for i,v in ipairs(vars) do r=setVarFs[v[3]](v[2],arg[i],e) end 
      s.push(r) 
    end
    instr['trace'] = function(s,n,e) _traceInstrs=s.peek() end
    instr['pack'] = function(s,n,e) local res=s.get(1); s.pop(); s.push(res) end
    instr['env'] = function(s,n,e) s.push(e) end
    local function resume(co,e)
      local res = {coroutine.resume(co)}
      if res[1]==true then
        if coroutine.status(co)=='dead' then e.log.cont(select(2,table.unpack(res))) end
      else error(res[2]) end
    end
    local function handleCall(s,e,fun,args)
      local res = table.pack(fun(table.unpack(args)))
      if type(res[1])=='table' and res[1]['<cont>'] then
        local co = e.co
        setTimeout(function() res[1]['<cont>'](function(...) local r=table.pack(...); s.push(r[1]); s.set(1,r); resume(co,e) end) end,0)
        return 'suspended',{}
      else s.push(res[1]) s.set(1,res) end
    end
    instr['%call'] = function(s,n,e,i) local fun = getVar(i[1] ,e); _assert(type(fun)=='function',"No such function:%s",i[1] or "nil")
      return handleCall(s,e,fun,s.lift(n))
    end
    instr['%calls'] = function(s,n,e,i) local args,fun = s.lift(n-1),s.pop(); _assert(type(fun)=='function',"No such function:%s",fun or "nil")
      return handleCall(s,e,fun,args)
    end
    instr['yield'] = function(s,n,e,i) local r = s.lift(n); s.push(nil); return 'suspended',r end
    instr['return'] = function(s,n,e,i) return 'dead',s.lift(n) end
    instr['wait'] = function(s,n,e,i) local t,co=s.pop(),e.co; t=t < os.time() and t or t-os.time(); s.push(t);
      setTimeout(function() resume(co,e) end,t*1000); return 'suspended',{}
    end
    instr['%not'] = function(s,n) s.push(not s.pop()) end
    instr['%neg'] = function(s,n) s.push(-tonumber(s.pop())) end
    instr['+'] = function(s,n) s.push(s.pop()+s.pop()) end
    instr['-'] = function(s,n) s.push(-s.pop()+s.pop()) end
    instr['*'] = function(s,n) s.push(s.pop()*s.pop()) end
    instr['/'] = function(s,n) local y,x=s.pop(),s.pop() s.push(x/y) end
    instr['%'] = function(s,n) local a,b=s.pop(),s.pop(); s.push(b % a) end
    instr['%inc+'] = function(s,n,e,i) local var,t,val=i[3],i[4] if n>0 then val=s.pop() else val=i[5] end 
    s.push(setVarFs[t](var,getVarFs[t](var,e)+val,e)) end
    instr['%inc-'] = function(s,n,e,i) local var,t,val=i[3],i[4]; if n>0 then val=s.pop() else val=i[5] end 
    s.push(setVarFs[t](var,getVarFs[t](var,e)-val,e)) end
    instr['%inc*'] = function(s,n,e,i) local var,t,val=i[3],i[4]; if n>0 then val=s.pop() else val=i[5] end
    s.push(setVarFs[t](var,getVarFs[t](var,e)*val,e)) end
    instr['>'] = function(s,n) local y,x=coerce(s.pop(),s.pop()) s.push(x>y) end
    instr['<'] = function(s,n) local y,x=coerce(s.pop(),s.pop()) s.push(x<y) end
    instr['>='] = function(s,n) local y,x=coerce(s.pop(),s.pop()) s.push(x>=y) end
    instr['<='] = function(s,n) local y,x=coerce(s.pop(),s.pop()) s.push(x<=y) end
    instr['~='] = function(s,n) s.push(tostring(s.pop())~=tostring(s.pop())) end
    instr['=='] = function(s,n) s.push(tostring(s.pop())==tostring(s.pop())) end

-- ER funs
    local getFuns,setFuns={},{}
    local _getFun = function(id,prop) return fibaro.get(id,prop) end
    do
      local function BN(x) return (type(x)=='boolean' and x and '1' or '0') or x end
      local get = _getFun
      local function on(id,prop) return BN(fibaro.get(id,prop)) > '0' end
      local function off(id,prop) return BN(fibaro.get(id,prop)) == '0' end
      local function last(id,prop) return os.time()-select(2,fibaro.get(id,prop)) end
      local function cce(id,prop,e) e=e.event; return e.type=='property' and e.propertyName=='CentralSceneEvent' and e.deviceID==id and e.value or {} end
      local function ace(id,prop,e) e=e.event; return e.type=='property' and e.propertyName=='AccessControlEvent' and e.deviceID==id and e.value or {} end
      local function armed(id,prop) return fibaro.get(id,prop) == '1' end
      local function call(id,cmd) fibaro.call(id,cmd); return true end
      local function set(id,cmd,val) fibaro.call(id,cmd,val); return val end
      local function setArmed(id,cmd,val) fibaro.call(id,cmd,val and '1' or '0'); return val end
      local function set2(id,cmd,val) fibaro.call(id,cmd,table.unpack(val)); return val end
      local mapOr,mapAnd,mapF=Util.mapOr,Util.mapAnd,function(f,l,s) Util.mapF(f,l,s); return true end
      getFuns={
        value={get,'value',nil,true},bat={get,'batteryLevel',nil,true},power={get,'power',nil,true},
        isOn={on,'value',mapOr,true},isOff={off,'value',mapAnd,true},isAllOn={on,'value',mapAnd,true},isAnyOff={off,'value',mapOr,true},
        last={last,'value',nil,true},scene={get,'sceneActivation',nil,true},
        access={ace,'AccessControlEvent',nil,true},central={cce,'CentralSceneEvent',nil,true},
        safe={off,'value',mapAnd,true},breached={on,'value',mapOr,true},isOpen={on,'value',mapOr,true},isClosed={off,'value',mapAnd,true},
        lux={get,'value',nil,true},temp={get,'value',nil,true},on={call,'turnOn',mapF,true},off={call,'turnOff',mapF,true},
        open={call,'open',mapF,true},close={call,'close',mapF,true},stop={call,'stop',mapF,true},
        secure={call,'secure',mapF,false},unsecure={call,'unsecure',mapF,false},
        isSecure={on,'secured',mapOr,true},isUnsecure={off,'secured',mapAnd,true},
        name={function(id) return fibaro.getName(id) end,nil,nil,false},
        HTname={function(id) return Util.reverseVar(id) end,nil,nil,false},
        roomName={function(id) return fibaro.getRoomNameByDeviceID(id) end,nil,nil,false},
        trigger={function() return true end,'value',nil,true},time={get,'time',nil,true},armed={armed,'armed',mapOr,true},
        manual={function(id) return Event.lastManual(id) end,'value',nil,true},
        start={function(id) return fibaro.scene("execute",{id}) end,"",mapF,false},
        kill={function(id) return fibaro.scene("kill",{id}) end,"",mapF,false},
        toggle={call,'toggle',mapF,true},wake={call,'wakeUpDeadDevice',mapF,true},
        removeSchedule={call,'removeSchedule',mapF,true},retryScheduleSynchronization={call,'retryScheduleSynchronization',mapF,true},
        setAllSchedules={call,'setAllSchedules',mapF,true},
        dID={function(a,e) 
            if type(a)=='table' then
              local id = e.event and Util.getIDfromTrigger[e.event.type or ""](e.event)
              if id then for _,id2 in ipairs(a) do if id == id2 then return id end end end
            end
            return a
          end,'<nop>',nil,true}
      }
      getFuns.lock=getFuns.secure;getFuns.unlock=getFuns.unsecure;getFuns.isLocked=getFuns.isSecure;getFuns.isUnlocked=getFuns.isUnsecure -- Aliases
      setFuns={
        R={set,'setR'},G={set,'setG'},B={set,'setB'},W={set,'setW'},value={set,'setValue'},armed={setArmed,'setArmed'},
        time={set,'setTime'},power={set,'setPower'},targetLevel={set,'setTargetLevel'},interval={set,'setInterval'},
        mode={set,'setMode'},setpointMode={set,'setSetpointMode'},defaultPartyTime={set,'setDefaultPartyTime'},
        scheduleState={set,'setScheduleState'},color={set2,'setColor'},
        thermostatSetpoint={set2,'setThermostatSetpoint'},schedule={set2,'setSchedule'},dim={set2,'dim'},
        msg={set,'sendPush'},defemail={set,'sendDefinedEmailNotification'},btn={set,'pressButton'},
        email={function(id,cmd,val) local h,m = val:match("(.-):(.*)"); fibaro.call(id,'sendEmail',h,m) return val end,""},
        start={function(id,cmd,val) 
            if isEvent(val) then Event.postRemote(id,val) else fibaro.scene("execute",{id},val) return true end 
          end,""},
      }
      self.getFuns=getFuns
    end

    local function ID(id,i,l) 
      if tonumber(id)==nil then 
        error(format("bad deviceID '%s' for '%s' '%s'",id,i[1],tojson(l or i[4] or "").."?"),3) else return id
      end
    end
    instr['%prop'] = function(s,n,e,i) local id,f=s.pop(),getFuns[i[3]]
      if i[3]=='dID' then s.push(getFuns['dID'][1](id,e)) return end
      if not f then f={_getFun,i[3]} end
      if type(id)=='table' then s.push((f[3] or map)(function(id) return f[1](ID(id,i,e._lastR),f[2],e) end,id))
      else s.push(f[1](ID(id,i,e._lastR),f[2],e)) end
    end
    instr['%setprop'] = function(s,n,e,i) local id,val,prop=s.pop(),getArg(s,i[3]),getArg(s,i[4])
      local f = setFuns[prop] _assert(f,"bad property '%s'",prop or "") 
      if type(id)=='table' then Util.mapF(function(id) f[1](ID(id,i,e._lastR),f[2],val,e) end,id); s.push(true)
      else s.push(f[1](ID(id,i,e._lastR),f[2],val,e)) end
    end
    instr['%rule'] = function(s,n,e,i) local b,h=s.pop(),s.pop(); s.push(Rule.compRule({'=>',h,b,e.log},e)) end
    instr['log'] = function(s,n) s.push(Log(LOG.ULOG,table.unpack(s.lift(n)))) end
    instr['%logRule'] = function(s,n,e,i) local src,res = s.pop(),s.pop() 
      Debug(_debugFlags.rule or (_debugFlags.ruleTrue and res),"[%s]>>'%s'",tojson(res),src) s.push(res) 
    end
    instr['%setlabel'] = function(s,n,e,i) local id,v,lbl = s.pop(),getArg(s,i[3]),getArg(s,i[4])
      fibaro.call(ID(id,i),"setProperty",format("ui.%s.value",lbl),tostring(v)) s.push(v) 
    end
    instr['%setslider'] = instr['%setlabel'] 

-- ER funs
    local simpleFuns={num=tonumber,str=tostring,idname=Util.reverseVar,time=toTime,['type']=type,
      tjson=safeEncode,fjson=json.decode}
    for n,f in pairs(simpleFuns) do instr[n]=function(s,n,e,i) return s.push(f(s.pop())) end end

    instr['sunset']=function(s,n,e,i) s.push(toTime(fibaro.getValue(1,'sunsetHour'))) end
    instr['sunrise']=function(s,n,e,i) s.push(toTime(fibaro.getValue(1,'sunriseHour'))) end
    instr['midnight']=function(s,n,e,i) s.push(midnight()) end
    instr['dawn']=function(s,n,e,i) s.push(toTime(fibaro.getValue(1,'dawnHour'))) end
    instr['dusk']=function(s,n,e,i) s.push(toTime(fibaro.getValue(1,'duskHour'))) end
    instr['now']=function(s,n,e,i) s.push(os.time()-midnight()) end
    instr['wnum']=function(s,n,e,i) s.push(Util.getWeekNumber(os.time())) end
    instr['%today']=function(s,n,e,i) s.push(midnight()+s.pop()) end
    instr['%nexttime']=function(s,n,e,i) local t=s.pop()+midnight(); s.push(t >= os.time() and t or t+24*3600) end
    instr['%plustime']=function(s,n,e,i) s.push(os.time()+s.pop()) end
    instr['HM']=function(s,n,e,i) local t = s.pop(); s.push(os.date("%H:%M",t < os.time() and t+midnight() or t)) end  
    instr['HMS']=function(s,n,e,i) local t = s.pop(); s.push(os.date("%H:%M:%S",t < os.time() and t+midnight() or t)) end  
    instr['sign'] = function(s,n) s.push(tonumber(s.pop()) < 0 and -1 or 1) end
    instr['rnd'] = function(s,n) local ma,mi=s.pop(),n>1 and s.pop() or 1 s.push(math.random(mi,ma)) end
    instr['round'] = function(s,n) local v=s.pop(); s.push(math.floor(v+0.5)) end
    instr['sum'] = function(s,n) local m,res=s.pop(),0 for _,x in ipairs(m) do res=res+x end s.push(res) end 
    instr['average'] = function(s,n) local m,res=s.pop(),0 for _,x in ipairs(m) do res=res+x end s.push(res/#m) end 
    instr['size'] = function(s,n) s.push(#(s.pop())) end
    instr['min'] = function(s,n) s.push(math.min(table.unpack(type(s.peek())=='table' and s.pop() or s.lift(n)))) end
    instr['max'] = function(s,n) s.push(math.max(table.unpack(type(s.peek())=='table' and s.pop() or s.lift(n)))) end
    instr['sort'] = function(s,n) local a = type(s.peek())=='table' and s.pop() or s.lift(n); table.sort(a) s.push(a) end
    instr['match'] = function(s,n) local a,b=s.pop(),s.pop(); s.push(string.match(b,a)) end
    instr['osdate'] = function(s,n) local x,y = s.peek(n-1),(n>1 and s.pop() or nil) s.pop(); s.push(os.date(x,y)) end
    instr['ostime'] = function(s,n) s.push(os.time()) end
    instr['%daily'] = function(s,n,e) s.pop() s.push(true) end
    instr['%interv'] = function(s,n,e,i) local t = s.pop(); s.push(true) end
    instr['fmt'] = function(s,n) s.push(string.format(table.unpack(s.lift(n)))) end
    instr['label'] = function(s,n,e,i) local nm,id = s.pop(),s.pop() s.push(fibaro.getValue(ID(id,i),format("ui.%s.value",nm))) end
    instr['slider'] = instr['label']
    instr['redaily'] = function(s,n,e,i) s.push(Rule.restartDaily(s.pop())) end
    instr['eval'] = function(s,n) s.push(Rule.eval(s.pop(),{print=false})) end
    instr['global'] = function(s,n,e,i)  s.push(api.post("/globalVariables/",{name=s.pop()})) end  
    instr['listglobals'] = function(s,n,e,i) s.push(api.get("/globalVariables/")) end
    instr['deleteglobal'] = function(s,n,e,i) s.push(api.delete("/globalVariables/"..s.pop())) end
    instr['once'] = function(s,n,e,i) 
      if n==1 then local f; i[4],f = s.pop(),i[4]; s.push(not f and i[4]) 
      elseif n==2 then local f,g,e; e,i[4],f = s.pop(),s.pop(),i[4]; g=not f and i[4]; s.push(g) 
        if g then Event.cancel(i[5]) i[5]=Event.post(function() i[4]=nil end,e) end
      else local f; i[4],f=os.date("%x"),i[4] or ""; s.push(f ~= i[4]) end
    end
    instr['%always'] = function(s,n,e,i) local v = s.pop(n) s.push(v or true) end
    instr['enable'] = function(s,n,e,i) local t,g = s.pop(),false; if n==2 then g,t=t,s.pop() end s.push(Event.enable(t,g)) end
    instr['disable'] = function(s,n,e,i) s.push(Event.disable(s.pop())) end
    instr['post'] = function(s,n,ev) local e,t=s.pop(),nil; if n==2 then t=e; e=s.pop() end s.push(Event.post(e,t,ev.rule)) end
    instr['subscribe'] = function(s,n,ev) Event.subscribe(s.pop()) s.push(true) end
    instr['publish'] = function(s,n,ev) local e,t=s.pop(),nil; if n==2 then t=e; e=s.pop() end Event.publish(e,t) s.push(e) end
    instr['remote'] = function(s,n,ev) _assert(n==2,"Wrong number of args to 'remote/2'"); 
      local e,u=s.pop(),s.pop(); 
      Event.postRemote(u,e) 
      s.push(true) 
    end
    instr['cancel'] = function(s,n) Event.cancel(s.pop()) s.push(nil) end
    instr['add'] = function(s,n) local v,t=s.pop(),s.pop() table.insert(t,v) s.push(t) end
    instr['remove'] = function(s,n) local v,t=s.pop(),s.pop() table.remove(t,v) s.push(t) end
    instr['%betw'] = function(s,n) local t2,t1,now=s.pop(),s.pop(),os.time()-midnight()
      _assert(tonumber(t1) and tonumber(t2),"Bad arguments to between '...', '%s' '%s'",t1 or "nil", t2 or "nil")
      if t1<=t2 then s.push(t1 <= now and now <= t2) else s.push(now >= t1 or now <= t2) end 
    end
    instr['%eventmatch'] = function(s,n,e,i) 
      local ev,evp=i[4],i[3]; 
      local vs = Event._match(evp,e.event)
      if vs then for k,v in pairs(vs) do e.locals[k]={v} end end -- Uneccesary? Alread done in head matching.
      s.push(e.event and vs and ev or false) 
    end
    instr['again'] = function(s,n,e) 
      local v = n>0 and s.pop() or math.huge
      e.rule._again = (e.rule._again or 0)+1
      if v > e.rule._again then setTimeout(function() e.rule.start(e.rule._event) end,0) else e.rule._again,e.rule._event = nil,nil end
      s.push(e.rule._again or v)
    end
    instr['trueFor'] = function(s,n,e,i)
      local val,time = s.pop(),s.pop()
      e.rule._event = e.event
      local flags = i[5] or {}; i[5]=flags
      if val then
        if flags.expired then s.push(val); flags.expired=nil; return end
        if flags.timer then s.push(false); return end
        flags.timer = setTimeout(function() 
            --  Event._callTimerFun(function()
            flags.expired,flags.timer=true,nil; 
            e.rule.start(e.rule._event) 
            --      end)
          end,1000*time); 
        s.push(false); return
      else
        if flags.timer then flags.timer=clearTimeout(flags.timer) end
        s.push(false)
      end
    end

    function self.addInstr(name,fun) _assert(instr[name] == nil,"Instr already defined: %s",name) instr[name] = fun end

    self.instr = instr
    local function postTrace(i,args,stack,cp)
      local f,n = i[1],i[2]
      if not ({jmp=true,push=true,pop=true,addr=true,fn=true,table=true,})[f] then
        local p0,p1=3,1; while i[p0] do table.insert(args,p1,i[p0]) p1=p1+1 p0=p0+1 end
        args = format("%s(%s)=%s",f,safeEncode(args):sub(2,-2),safeEncode(stack.peek()))
        Log(LOG.LOG,"pc:%-3d sp:%-3d %s",cp,stack.size(),args)
      else
        Log(LOG.LOG,"pc:%-3d sp:%-3d [%s/%s%s]",cp,stack.size(),i[1],i[2],i[3] and ","..json.encode(i[3]) or "")
      end
    end

    function self.dump(code)
      code = code or {}
      for p = 1,#code do
        local i = code[p]
        Log(LOG.LOG,"%-3d:[%s/%s%s%s]",p,i[1],i[2] ,i[3] and ","..tojson(i[3]) or "",i[4] and ","..tojson(i[4]) or "")
      end
    end

    function self.listInstructions()
      local t={}
      print("User functions:")
      for f,_ in pairs(instr) do if f=="%" or f:sub(1,1)~='%' then t[#t+1]=f end end
      table.sort(t); for _,f in ipairs(t) do print(f) end
      print("Property functions:")
      t={}
      for f,_ in pairs(getFuns) do t[#t+1]="<ID>:"..f end 
      for f,_ in pairs(setFuns) do t[#t+1]="<ID>:"..f.."=.." end 
      table.sort(t); for _,f in ipairs(t) do print(f) end
    end

    function self.eval(env)
      local stack,code=env.stack or mkStack(),env.code
      local traceFlag = env.log and env.log.trace or _traceInstrs
      env.cp,env.env,env.src = env.cp or 1, env.env or {},env.src or ""
      local i,args
      local status,stat,res = pcall(function() 
          local stat,res
          while env.cp <= #code and stat==nil do
            i = code[env.cp]
            if traceFlag or _traceInstrs then 
              args = copy(stack.liftc(i[2]))
              stat,res=(instr[i[1]] or instr['%call'])(stack,i[2],env,i)
              postTrace(i,args,stack,env.cp) 
            else stat,res=(instr[i[1]] or instr['%call'])(stack,i[2],env,i) end
            env.cp = env.cp+1
          end --until env.cp > #code or stat
          return stat,res or {stack.pop()}
        end)
      if status then return stat,res
      else
        if isError(stat) then stat.src = stat.src or env.src; error(stat) end
        throwError{msg=format("Error executing instruction:'%s'",tojson(i)),err=stat,src=env.src,ctx=res}
      end
    end

    function self.eval2(env) env.cp=nil; env.locals = env.locals or {}; local _,res=self.eval(env) return res[1] end

    local function makeDateInstr(f)
      return function(s,n,e,i)
        local ts,cache = s.pop(),e.rule.cache
        if ts ~= i[5] then i[6] = Util.dateTest(f(ts)); i[5] = ts end -- cache fun
        s.push(i[6]())
      end
    end

    self.addInstr("date",makeDateInstr(function(s) return s end))             -- min,hour,days,month,wday
    self.addInstr("day",makeDateInstr(function(s) return "* * "..s end))      -- day('1-31'), day('1,3,5')
    self.addInstr("month",makeDateInstr(function(s) return "* * * "..s end))  -- month('jan-feb'), month('jan,mar,jun')
    self.addInstr("wday",makeDateInstr(function(s) return "* * * * "..s end)) -- wday('fri-sat'), wday('mon,tue,wed')

    return self
  end

--------- Event script Rule compiler ------------------------------------------
  function makeEventScriptRuleCompiler()
    local self = {}
    local HOURS24,CATCHUP,RULEFORMAT = 24*60*60,math.huge,"Rule:%s[%s]"
    local map,mapkl,getFuns,format,midnight,time2str=Util.map,Util.mapkl,ScriptEngine.getFuns,string.format,Util.midnight,Util.time2str
    local transform,copy,isGlob,isVar,triggerVar = Util.transform,Util.copy,Util.isGlob,Util.isVar,Util.triggerVar
    local _macros,dailysTab,rCounter= {},{},0
    local lblF=function(id,e) return {type='property', deviceID=id, propertyName=format("ui.%s.value",e[3])} end
    local triggFuns={label=lblF,slider=lblF}
    local function isTEvent(e) return type(e)=='table' and (e[1]=='%table' or e[1]=='%quote') and type(e[2])=='table' and e[2].type end

    local function ID(id,p) _assert(tonumber(id),"bad deviceID '%s' for '%s'",id,p or "") return id end
    local gtFuns = {
      ['%daily'] = function(e,s) s.dailys[#s.dailys+1 ]=ScriptCompiler.compile2(e[2]); s.dailyFlag=true end,
      ['%interv'] = function(e,s) s.scheds[#s.scheds+1 ] = ScriptCompiler.compile2(e[2]) end,
      ['%betw'] = function(e,s) 
        s.dailys[#s.dailys+1 ]=ScriptCompiler.compile2(e[2])
        s.dailys[#s.dailys+1 ]=ScriptCompiler.compile({'+',1,e[3]}) 
      end,
      ['%var'] = function(e,s) 
        if e[3]=='glob' then s.triggs[e[2] ] = {type='global', name=e[2]} 
        elseif triggerVar(e[2]) then s.triggs[e[2] ] = {type='variable', name=e[2]} end 
      end,
      ['%set'] = function(e,s) if isVar(e[2]) and triggerVar(e[2][2]) or isGlob(e[2]) then error("Can't assign variable in rule header") end end,
      ['%prop'] = function(e,s)
        local pn
        if not getFuns[e[3]] then pn = e[3] elseif not getFuns[e[3]][4] then return else pn = getFuns[e[3]][2] end
        local cv = ScriptCompiler.compile2(e[2])
        local v = ScriptEngine.eval2({code=cv})
        map(function(id) s.triggs[ID(id,e[3])..pn]={type='property', deviceID=id, propertyName=pn} end,type(v)=='table' and v or {v})
      end,
    }

    local function getTriggers(e)
      local s={triggs={},dailys={},scheds={},dailyFlag=false}
      local function traverse(e)
        if type(e) ~= 'table' then return e end
        if e[1]== '%eventmatch' then -- {'eventmatch',{'quote', ep,ce}} 
          local ep,ce = e[2],e[3]
          s.triggs[tojson(ce)] = ce  
        else
          Util.mapkk(traverse,e)
          if gtFuns[e[1]] then gtFuns[e[1]](e,s)
          elseif triggFuns[e[1]] then
            local cv = ScriptCompiler.compile2(e[2])
            local v = ScriptEngine.eval2({code=cv})
            map(function(id) s.triggs[id]=triggFuns[e[1]](id,e) end,type(v)=='table' and v or {v})
          end
        end
      end
      traverse(e); return mapkl(function(_,v) return v end,s.triggs),s.dailys,s.scheds,s.dailyFlag
    end

    function self.test(s) return {getTriggers(ScriptCompiler.parse(s))} end
    function self.define(name,fun) ScriptEngine.define(name,fun) end
    function self.addTrigger(name,instr,gt) ScriptEngine.addInstr(name,instr) triggFuns[name]=gt end

    local function compTimes(cs)
      local t1,t2=map(function(c) return ScriptEngine.eval2({code=c}) end,cs),{}
      if #t1>0 then transform(t1,function(t) t2[t]=true end) end
      return mapkl(function(k,_) return k end,t2)
    end

    local function remapEvents(obj)
      if isTEvent(obj) then 
        local ce = ScriptEngine.eval2({code=ScriptCompiler.compile(obj)})
        local ep = copy(ce); Event._compilePattern(ep)
        obj[1],obj[2],obj[3]='%eventmatch',ep,ce; 
--    elseif type(obj)=='table' and (obj[1]=='%and' or obj[1]=='%or' or obj[1]=='trueFor') then remapEvents(obj[2]); remapEvents(obj[3])  end
      elseif type(obj)=='table' then map(function(e) remapEvents(e) end,obj,2) end
    end

    local function trimRule(str)
      local str2 = str:sub(1,(str:find("\n") or math.min(#str,_RULELOGLENGTH or 80)+1)-1)
      if #str2 < #str then str2=str2.."..." end
      return str2
    end

    local coroutine = Util.coroutine
    function Event._compileActionHook(a,src,log)
      if type(a)=='string' or type(a)=='table' then        -- EventScript
        src = src or a
        local code = type(a)=='string' and ScriptCompiler.compile(src,log) or a
        local function run(env)
          env=env or {}; env.log = env.log or {}; env.log.cont=env.log.cont or function(...) return ... end
          env.locals = env.locals or {}
          local co = coroutine.create(code,src,env); env.co = co
          local res={coroutine.resume(co)}
          if res[1]==true then
            if coroutine.status(co)=='dead' then return env.log.cont(select(2,table.unpack(res))) end
          else error(res[1]) end
        end
        return run
      else return nil end
    end

    function self.compRule(e,env)
      local head,body,log,res,events,src,triggers2,sdaily = e[2],e[3],e[4],{},{},env.src or "<no src>",{}
      src=format(RULEFORMAT,rCounter+1,trimRule(src))
      remapEvents(head)  -- #event -> eventmatch
      local triggers,dailys,reps,dailyFlag = getTriggers(head)
      _assert(#triggers>0 or #dailys>0 or #reps>0, "no triggers found in header")
      --_assert(not(#dailys>0 and #reps>0), "can't have @daily and @@interval rules together in header")
      local code = ScriptCompiler.compile({'%and',(_debugFlags.rule or _debugFlags.ruleTrue) and {'%logRule',head,src} or head,body})
      local action = Event._compileAction(code,src,env.log)
      if #reps>0 then -- @@interval rules
        local event,env={type=Util.gensym("INTERV")},{code=reps[1]}
        events[#events+1] = Event.event(event,action,src)
        event._sh=true
        local timeVal,skip = nil,ScriptEngine.eval2(env)
        local function interval()
          timeVal = timeVal or os.time()
          Event.post(event)
          timeVal = timeVal+math.abs(ScriptEngine.eval2(env))
          setTimeout(interval,1000*(timeVal-os.time()))
        end
        setTimeout(interval,1000*(skip < 0 and -skip or 0))
      else
        if #dailys > 0 then -- daily rules
          local event,timers={type=Util.gensym("DAILY"),_sh=true},{}
          sdaily={dailys=dailys,event=event,timers=timers}
          dailysTab[#dailysTab+1] = sdaily
          events[#events+1]=Event.event(event,action,src)
          self.recalcDailys({dailys=sdaily,src=src},true)
          local reaction = function() self.recalcDailys(res) end
          for _,tr in ipairs(triggers) do -- Add triggers to reschedule dailys when variables change...
            if tr.type=='global' then Event.event(tr,reaction,{doc=src})  end
          end
        end
        if not dailyFlag and #triggers > 0 then -- id/glob trigger or events
          for _,tr in ipairs(triggers) do 
            if tr.propertyName~='<nop>' then events[#events+1]=Event.event(tr,action,src) triggers2[#triggers2+1]=tr end
          end
        end
      end
      res=#events>1 and Event.comboEvent(src,action,events,src) or events[1]
      res.dailys = sdaily
      if sdaily then sdaily.rule=res end
      res.print = function()
        Util.map(function(r) Log(LOG.LOG,"Interval(%s) =>...",time2str(r)) end,compTimes(reps)) 
        Util.map(function(d) Log(LOG.LOG,"Daily(%s) =>...",d==CATCHUP and "catchup" or time2str(d)) end,compTimes(dailys)) 
        Util.map(function(tr) Log(LOG.LOG,"Trigger(%s) =>...",tojson(tr)) end,triggers2)
      end
      rCounter=rCounter+1
      return res
    end

-- context = {log=<bool>, level=<int>, line=<int>, doc=<str>, trigg=<bool>, enable=<bool>}
    function self.eval(escript,log)
      if log == nil then log = {} elseif log==true then log={print=true} end
      if log.print==nil then log.print=true end
      local status,res,ctx
      status, res = pcall(function() 
          local expr = self.macroSubs(escript)
          if not log.cont then 
            log.cont=function(res)
              log.cont=nil
              local name,r
              if not log.print then return res end
              if Event.isRule(res) then name,r=res.src,"OK" else name,r=escript,res end
              Log(LOG.LOG,"%s = %s",name,r or "nil") 
              return res
            end
          end
          local f = Event._compileAction(expr,nil,log)
          return f({log=log,rule={cache={}}})
        end)
      if not status then 
        if not isError(res) then res={ERR=true,ctx=ctx,src=escript,err=res} end
        Log(LOG.ERROR,"Error in '%s': %s",res and res.src or "rule",res.err)
        if res.ctx then Log(LOG.ERROR,"\n%s",res.ctx) end
        error(res.err)
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
      map(function(r) self.eval(r,log) end,splitRules(rules))
    end

    function self.macro(name,str) _macros['%$'..name..'%$'] = str end
    function self.macroSubs(str) for m,s in pairs(_macros) do str = str:gsub(m,s) end return str end

    function self.recalcDailys(r,catch)
      if r==nil and catch==nil then
        for _,d in ipairs(dailysTab) do self.recalcDailys(d.rule) end
        return
      end
      if not r.dailys then return end
      local dailys,newTimers,oldTimers,max = r.dailys,{},r.dailys.timers,math.max
      for _,t in ipairs(oldTimers) do Event.cancel(t[2]) end
      dailys.timers = newTimers
      local times,m,ot,catchup1,catchup2 = compTimes(dailys.dailys),midnight(),os.time()
      for i,t in ipairs(times) do _assert(tonumber(t),"@time not a number:%s",t)
        local oldT = oldTimers[i] and oldTimers[i][1]
        if t ~= CATCHUP then
          if _MIDNIGHTADJUST and t==HOURS24 then t=t-1 end
          if t+m >= ot then 
            Debug(oldT ~= t and _debugFlags.dailys,"Rescheduling daily %s for %s",r.src or "",os.date("%c",t+m)); 
            newTimers[#newTimers+1]={t,Event.post(dailys.event,max(os.time(),t+m),r.src)}
          else catchup1=true end
        else catchup2 = true end
      end
      if catch and catchup2 and catchup1 then Log(LOG.LOG,"Catching up:%s",r.src); Event.post(dailys.event) end
      return r
    end

    -- Scheduler that every night posts 'daily' rules
    Util.defvar('dayname',os.date("%a"))
    Event.event({type='%MIDNIGHT'},function(env) 
        Util.defvar('dayname',os.date("*t").wday)
        for _,d in ipairs(dailysTab) do self.recalcDailys(d.rule) end 
        Event.post(env.event,"n/00:00")
      end)
    Event.post({type='%MIDNIGHT',_sh=true},"n/00:00")
    return self
  end
--- SceneActivation constants
  Util.defvar('S1',Util.S1)
  Util.defvar('S2',Util.S2)
  Util.defvar('catch',math.huge)
  Util.defvar("defvars",Util.defvars)
  Util.defvar("mapvars",Util.reverseMapDef)

  ScriptParser   = makeEventScriptParser()
  ScriptCompiler = makeEventScriptCompiler(ScriptParser)
  ScriptEngine   = makeEventScriptRuntime()
  Rule           = makeEventScriptRuleCompiler() 
  Rule.ScriptParser   = ScriptParser
  Rule.ScriptCompiler = ScriptCompiler
  Rule.ScriptEngine   = ScriptEngine
  Log(LOG.SYS,"Setting up EventScript support..")
  return Rule
end
----------------- Node-red support ----------------------------
function module.Nodered()
  local self = { _nrr = {}, _timeout = 4000, _last=nil }
  function self.connect(url) 
    local isEvent,gensym = Event.isEvent,Util.gensym
    local self2 = { _url = url, _http=Util.netSync.HTTPClient("Nodered") }
    function self2.post(event,sync)
      _assert(isEvent(event),"Arg to nodered.msg is not an event")
      local tag, nrr = gensym("NR"), self2._nrr
      event._transID = tag
      event._from = fibaro.ID
      event._async = true
      event._IP = Util.getIPaddress()
      if hc3_emulator then event._IP=event._IP..":"..hc3_emulator.webPort end
      local params =  {options = {
          headers = {['Accept']='application/json',['Content-Type']='application/json'},
          data = json.encode(event), timeout=4000, method = 'POST'},
        _logErr=true
      }
      self2._http:request(self2._url,params)
      if sync then
        nrr[tag]={}
        nrr[tag][1]=setTimeout(function() nrr[tag]=nil 
            Log(LOG.ERROR,"No response from Node-red, '%s'",event)
          end,self._timeout)
        return {['<cont>']=function(cont) nrr[tag][2]=cont end}
      else return true end
    end
    self._last = self2
    return self2
  end

  function self.receive(ev)
    local tag = ev._transID
    if tag then
      ev._IP,ev._async,ev._from,ev._transID = nil,nil,nil,nil
      local nrr = self._nrr
      local cr = nrr[tag] or {}
      if cr[1] then clearTimeout(cr[1]) end
      if cr[2] then 
        local stat,res = pcall(function() cr[2](ev) end)
        if not stat then
          Log(LOG.ERROR,"Error in Node-red rule for %s, - %s",ev,res)
        end
      else Event.post(ev) end
      nrr[tag]=nil
    else Event.post(ev) end
  end

  function self.post(event,sync)
    _assert(self._last,"Missing nodered URL - make Nodered.connect(<url>) at beginning of scene")
    return self._last.post(event,sync)
  end

  function QuickApp:fromNodeRed(ev) Nodered.receive(ev) end
  return self
end
--------------- Trigger support -------------------------------
function module.Trigger()
  local self = {}
  if not hc3_emulator then  
    fibaro._EventCache = { polling=false, devices={}, globals={}, centralSceneEvents={}, accessControlEvents={}} 
    local _oldSetTimeout = setTimeout
    local stat,res = pcall(function() x() end)
    local line = 399-res:match("lua:(%d+)") -- '4' should be the line number of the previous line
    function setTimeout(fun,ms)
      return _oldSetTimeout(function()
          stat,res = pcall(fun)
          if not stat then
            local cline,msg = res:match("lua:(%d+):(.*)")
            print(string.format("Error in setTimeout (line:%d):%s",line+cline,msg)) 
          end
        end,ms)
    end
  else fibaro._EventCache = hc3_emulator.cache end

  fibaro.setTimeout = setTimeout
  local _setTimeout = setTimeout

  function fibaro._cacheDeviceProp(deviceID,prop,value)
    fibaro._EventCache.devices[prop..deviceID]={value=value,modified=os.time()}
  end

  function self.pollForTriggers(interval)
    local EventCache = fibaro._EventCache
    local INTERVAL = interval or 1000 -- every second, could do more often...
    local tickEvent = "ERTICK"

    local function post(ev)
      if _debugFlags.triggers then Debug(true,"Incoming event:%s",ev) end
      ev._sh=true
      Event._handleEvent(ev) 
    end 

    --api.post("/customEvents",{name=tickEvent,userDescription="Tock!"})
    api.post("/globalVariables",{name=tickEvent,value="Tock!"})

    local EventTypes = { -- There are more, but these are what I seen so far...
      AlarmPartitionArmedEvent = function(self,d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
      AlarmPartitionBreachedEvent = function(self,d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
      HomeArmStateChangedEvent = function(self,d) post({type='alarm', property='homeArmed', value=d.newValue}) end,
      HomeBreachedEvent = function(self,d) post({type='alarm', property='homeBreached', value=d.breached}) end,
      WeatherChangedEvent = function(self,d) post({type='weather',property=d.change, value=d.newValue, old=d.oldValue}) end,
      GlobalVariableChangedEvent = function(self,d)
        EventCache.globals[d.variableName]={name=d.variableName, value = d.newValue, modified=os.time()}
        if d.variableName == tickEvent then return end
        post({type='global', name=d.variableName, value=d.newValue, old=d.oldValue})
      end,
      DevicePropertyUpdatedEvent = function(self,d)
        if d.property=='quickAppVariables' then 
          local old={}; for _,v in ipairs(d.oldValue) do old[v.name] = v.value end -- Todo: optimize
          for _,v in ipairs(d.newValue) do
            if v.value ~= old[v.name] then
              post({type='quickvar', name=v.name, value=v.value, old=old[v.name]})
            end
          end
        else
          --if d.property:match("^ui%.") then return end
          if d.property == "icon" then return end
          EventCache.devices[d.property..d.id]={value=d.newValue, modified=os.time()}     
          post({type='property', deviceID=d.id, propertyName=d.property, value=d.newValue, old=d.oldValue})
        end
      end,
      CentralSceneEvent = function(self,d) EventCache.centralSceneEvents[d.deviceId]=d; d.icon=nil post({type='centralSceneEvent', data=d}) end,
      AccessControlEvent = function(self,d) EventCache.accessControlEvents[d.id]=d; post({type='accessControlEvent', data=d}) end,
      CustomEvent = function(self,d) 
        if d.name == tickEvent then return 
        elseif fibaro._handleEvent and fibaro._handleEvent({type='customevent',name=d.name}) then return
        else
          local value = api.get("/customEvents/"..d.name) 
          post({type='customevent', name=d.name, value=value and value.userDescription}) 
        end 
      end,
      PluginChangedViewEvent = function(self,d) post({type='PluginChangedViewEvent', value=d}) end,
      WizardStepStateChangedEvent = function(self,d) post({type='WizardStepStateChangedEvent', value=d})  end,
      UpdateReadyEvent = function(self,d) post({type='UpdateReadyEvent', value=d}) end,
      SceneRunningInstancesEvent = function(self,d) post({type='SceneRunningInstancesEvent', value=d}) end,
      DeviceRemovedEvent = function(self,d)  post({type='DeviceRemovedEvent', value=d}) end,
      DeviceChangedRoomEvent = function(self,d)  post({type='DeviceChangedRoomEvent', value=d}) end,    
      DeviceCreatedEvent = function(self,d)  post({type='DeviceCreatedEvent', value=d}) end,
      DeviceModifiedEvent = function(self,d) post({type='DeviceModifiedEvent', value=d}) end,
      SceneStartedEvent = function(self,d)   post({type='SceneStartedEvent', value=d}) end,
      SceneFinishedEvent = function(self,d)  post({type='SceneFinishedEvent', value=d})end,
      SceneRemovedEvent = function(self,d)  post({type='SceneRemovedEvent', value=d}) end,
      PluginProcessCrashedEvent = function(self,d) post({type='PluginProcessCrashedEvent', value=d}) end,
      onUIEvent = function(self,d) 
        Log(LOG.LOG,"UI %s",d)
        post({type='uievent', deviceID=d.deviceId, name=d.elementName}) 
      end,
      ActiveProfileChangedEvent = function(self,d) 
        post({type='profile',property='activeProfile',value=d.newActiveProfile, old=d.oldActiveProfile}) 
      end,
    }

    fibaro._eventTypes = EventTypes

    local function checkEvents(events)
      for _,e in ipairs(events) do
        local eh = EventTypes[e.type]
        if eh then eh(_,e.data)
        elseif eh==nil then fibaro.debug("",string.format("Unhandled event:%s -- please report",json.encode(e))) end
      end
    end

    local function pollEvents()
      local lastRefresh = 0
      EventCache.polling = true -- Our loop will populate cache with values - no need to fetch from HC3
      local function pollRefresh()
        --print("*")
        local states = api.get("/refreshStates?last=" .. lastRefresh)
        if states then
          lastRefresh=states.last
          if states.events and #states.events>0 then checkEvents(states.events) end
        end
        _setTimeout(pollRefresh,INTERVAL)
        --fibaro.emitCustomEvent(tickEvent)  -- hack because refreshState hang if no events...
        fibaro.setGlobalVariable(tickEvent,tostring(os.clock()))
      end
      _setTimeout(pollRefresh,INTERVAL)
    end

    Log(LOG.SYS,"Polling for triggers..")
    pollEvents()
  end
  return self
end


----------------- Main ----------------------------------------
local function startUp(e)
  if e.type == 'ready' then
    Log(LOG.SYS,"Sunrise:%s,  Sunset:%s",(fibaro.get(1,"sunriseHour")),(fibaro.get(1,"sunsetHour")))
    Log(LOG.HEADER,"Setting up rules (main)")
    local stat,res = pcall(function()
        main(self) -- call main
      end)
    if not stat then error("Main() ERROR:"..res) end
    Event.createCustomEvent(Event.tickEvent,"Tock!") -- hack because refreshState hang if no events available... 
    Log(LOG.HEADER,"Running")
    Trigger.pollForTriggers(triggerInterval) 
    Event.post({type='startup'})
  end

  if e.type == 'load' then
    if module[e.name] then 
      module[e.name](function() startUp(e.cont) end)
    else startUp(e.cont) end
  end
end

function QuickApp:onInit()
  fibaro.QD = self
  fibaro.ID = plugin.mainDeviceId
  Util = module.Utilities() 
  if not fibaro.debug then fibaro.debug = function(...) self:debug(...) end end
  self.debug = function(self,...) Log(LOG.LOG,...) end

  local appName = api.get("/devices/"..fibaro.ID).name
  Log(LOG.HEADER,"%s, %s (ID:%s)",appName or "NoName",APP_VERS or "",fibaro.ID)
  Log(LOG.SYS,"Events %s, %s",E_VERSION,E_FIX)
  Log(LOG.SYS,"IP address:%s",Util.getIPaddress())  

  Device  = module.Device()
  Event   = module.EventEngine()
  Remote  = module.Remote()
  Patch   = module.Autopatch()
  Extras  = module.Extras()
  Rule    = module.EventScript()
  Nodered = module.Nodered()
  Trigger = module.Trigger()
  startUp({type='load',name='Hue', cont={type='ready'}})
end 

if dofile then
  hc3_emulator.offline=true
  hc3_emulator.start{
    name="EventRunner4",
    --proxy=true,
    UI = {
      {label='name',text="ER 4.0 beta v0.1"},
      {button='debugTriggers', text='Triggers:ON'},
      {button='debugPost', text='Post:ON'},
      {button='debugRules', text='Rules:ON'},
    }
  }
end
