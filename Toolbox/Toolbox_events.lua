--[[
  Toolbox events.
  
  Event handling functions

  function QuickApp:post(ev,t)                        -- Post event 'ev' at time 't'
  function QuickApp:cancel(ref)                       -- Cancel post in the future
  function QuickApp:event(pattern,fun)                -- Create event handler for posted events
  function QuickApp:HTTPEvent(args)                   -- Asynchronous http requests
  function QuickApp:RECIEVE_EVENT(ev)                 -- QA method for recieving events from outside...

--]]

local format = string.format
Toolbox_Module = Toolbox_Module or {}

function Toolbox_Module.events(self)
  local version = "0.1"
  self:debugf("Setup: Event manager (%s)",version) 
  local em,handlers = { sections = {}},{}
  em.BREAK, em.TIMER, em.RULE = '%%BREAK%%', '%%TIMER%%', '%%RULE%%'
  local function isEvent(e) return type(e)=='table' and e.type end
  local function isRule(e) return type(e)=='table' and e[em.RULE] end

  local function time2string(t) return os.date("[Timer:%X]",t.stop) end
  local function makeTimer(ref,t) return {type=em.TIMER, timer=ref,now=os.time(),stop=t,__tostring=time2string} end
  em.expiredTimer = makeTimer(nil,0)

  local function midnight() local t = os.date("*t"); t.hour,t.min,t.sec = 0,0,0; return os.time(t) end

  local function hm2sec(hmstr)
    local offs,sun
    sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
    if sun and (sun == 'sunset' or sun == 'sunrise') then
      hmstr,offs = fibaro.getValue(1,sun.."Hour"), tonumber(offs) or 0
    end
    local sg,h,m,s = hmstr:match("^(%-?)(%d+):(%d+):?(%d*)")
    assert(h and m,"Bad hm2sec string %s",hmstr)
    return (sg == '-' and -1 or 1)*(h*3600+m*60+(tonumber(s) or 0)+(offs or 0)*60)
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

-- This can be used to "post" an event intio this QA... Ex. fibaro.call(ID,'RECIEVE_EVENT',{type='myEvent'})
  function self:RECIEVE_EVENT(ev)
    assert(isEvent(ev),"Bad argument to remote event")
    local time = ev.ev._time
    ev,ev.ev._time = ev.ev,nil
    if time and time+5 < os.time() then self:warningf("Slow events %s, %ss",ev,os.time()-time) end
    self:post(ev)
  end

  function self:postRemote(id,ev) 
    assert(tonumber(id) and isEvent(ev),"Bad argument to postRemote")
    ev._from,ev._time = self.id,os.time()
    fibaro.call(id,'RECIEVE_EVENT',{type='EVENT',ev=ev}) -- We need this as the system converts "99" to 99 and other "helpful" conversions
  end

--[[
  Post event at time 't'. Returns reference to post that can be used to cancel the post
  Event must be table with {type=...} or a Lua function
  't' is absolute unix time or seconds from now. i.e. if t < os.time() then t is considered to be os.time()+t
  't' can also be a time string. See 'toTime' above.
--]]
  function self:post(ev,t)
    local now = os.time()
    t = type(t)=='string' and toTime(t) or t or 0
    if t < 0 then return elseif t < now then t = t+now end
    local timer = makeTimer(nil,t)
    if type(ev) == 'function' then
      timer.ref = setTimeout(function() timer.ref=nil; ev() end,1000*(t-now))
    else
      timer.ref = setTimeout(function() timer.ref=nil; if self._eventHandler then self._eventHandler(ev) end end,1000*(t-now))
    end
    return timer
  end

-- Cancel post in the future
  function self:cancel(ref) 
    assert(type(ref)=='table' and ref.type==em.TIMER,"Bad timer reference:"..tostring(ref))
    if ref.timer then clearTimeout(ref.timer) end
    ref.timer = nil
    return nil
  end

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

  local function coerce(x,y) local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end end
  local constraints = {}
  constraints['=='] = function(val) return function(x) x,val=coerce(x,val) return x == val end end
  constraints['>='] = function(val) return function(x) x,val=coerce(x,val) return x >= val end end
  constraints['<='] = function(val) return function(x) x,val=coerce(x,val) return x <= val end end
  constraints['>'] = function(val) return function(x) x,val=coerce(x,val) return x > val end end
  constraints['<'] = function(val) return function(x) x,val=coerce(x,val) return x < val end end
  constraints['~='] = function(val) return function(x) x,val=coerce(x,val) return x ~= val end end
  constraints[''] = function(_) return function(x) return x ~= nil end end

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
    return pattern
  end

  local function compilePattern(pattern)
    pattern = compilePattern2(copy(pattern))
    if pattern.type and type(pattern.id)=='table' and not pattern.id._constr then
      local m = {}; for _,id in ipairs(pattern.id) do m[id]=true end
      pattern.id = {_var_='_', _constr=function(val) return m[val] end, _str=pattern.id}
    end
    return pattern
  end
  em.compilePattern = compilePattern

  local function match(pattern, expr)
    local matches = {}
    local function unify(pattern,expr)
      if pattern == expr then return true
      elseif type(pattern) == 'table' then
        if pattern._var_ then
          local var, constr = pattern._var_, pattern._constr
          if var == '_' then return constr(expr)
          elseif matches[var] then return constr(expr) and unify(matches[var],expr) -- Hmm, equal?
          else matches[var] = expr return constr(expr) end
        end
        if type(expr) ~= "table" then return false end
        for k,v in pairs(pattern) do if not unify(v,expr[k]) then return false end end
        return true
      else return false end
    end
    return unify(pattern,expr) and matches or false
  end
  em.match = match

  local function invokeHandler(env)
    local t = os.time()
    env.last,env.rule.time = t-(env.rule.time or 0),t
    local status, res = pcall(env.rule.action,env) -- call the associated action
    if not status then
      self:errorf("in %s: %s",env.rule.doc,res)
      env.rule._disabled = true -- disable rule to not generate more errors
    else return res end
  end

  local toHash,fromHash={},{}
  fromHash['device'] = function(e) return {"device"..e.id..e.property,"device"..e.id,"device"..e.property,"device"} end
  fromHash['global-variable'] = function(e) return {'global-variable'..e.name,'global-variable'} end
  toHash['device'] = function(e) return "device"..(e.id or "")..(e.property or "") end   
  toHash['global-variable'] = function(e) return 'global-variable'..(e.name or "") end

  local function rule2str(rule) return rule.doc end
  local function comboToStr(r)
    local res = { r.src }
    for _,s in ipairs(r.subs) do res[#res+1]="   "..tostring(s) end
    return table.concat(res,"\n")
  end
  function map(f,l,s) s = s or 1; local r={} for i=s,table.maxn(l) do r[#r+1] = f(l[i]) end return r end
  function mapF(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) end return e end

  local function comboEvent(e,action,rl,doc)
    local rm = {[em.RULE]=e, action=action, doc=doc, subs=rl}
    rm.enable = function() mapF(function(e) e.enable() end,rl) return rm end
    rm.disable = function() mapF(function(e) e.disable() end,rl) return rm end
    rm.start = function(event) self._invokeRule({rule=rm,event=event}) return rm end
    rm.__tostring = comboToStr
    return rm
  end

  function self:event(pattern,fun,doc)
    doc = doc or format("Event(%s) => ..",json.encode(pattern))
    if type(pattern) == 'table' and pattern[1] then 
      return comboEvent(pattern,fun,map(function(es) return self:event(es,fun) end,pattern),doc) 
    end
    if isEvent(pattern) then
      if pattern.type=='device' and pattern.id and type(pattern.id)=='table' then
        return self:event(map(function(id) local e1 = copy(pattern); e1.id=id return e1 end,pattern.id),fun,doc)
      end
    else error("Bad event pattern, needs .type field") end
    assert(type(fun)=='function',"Second argument must be Lua function")
    local cpattern = compilePattern(pattern)
    local hashKey = toHash[pattern.type] and toHash[pattern.type](pattern) or pattern.type
    handlers[hashKey] = handlers[hashKey] or {}
    local rules = handlers[hashKey]
    local rule,fn = {[em.RULE]=cpattern, event=pattern, action=fun, doc=doc}, true
    for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
      if equal(cpattern,rs[1].event) then 
        rs[#rs+1] = rule
        fn = false break 
      end
    end
    if fn then rules[#rules+1] = {rule} end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    rule.start = function(event) invokeHandler({rule=rule, event=event, p={}}) return rule end
    rule.__tostring = rule2str
    if em.SECTION then
      local s = em.sections[em.SECTION] or {}
      s[#s+1] = rule
      em.sections[em.SECTION] = s
    end
    return rule
  end

  local function handleEvent(ev)
    local hasKeys = fromHash[ev.type] and fromHash[ev.type](ev) or {ev.type}
    for _,hashKey in ipairs(hasKeys) do
      for _,rules in ipairs(handlers[hashKey] or {}) do -- Check all rules of 'type'
        local m = match(rules[1][em.RULE],ev)
        if m then
          for _,rule in ipairs(rules) do 
            if not rule._disabled then 
              if invokeHandler({event = ev, p=m, rule=rule}) == em.BREAK then return end
            end
          end
        end
      end
    end
  end

--[[
  Event.http{url="foo",tag="55",
    headers={},
    timeout=60,
    basicAuthorization = {user="admin",password="admin"}
    useCertificate=0,
    method="GET"}
--]]

  function self:HTTPEvent(args)
    local options,url = {},args.url
    options.headers = args.headers or {}
    options.timeout = args.timeout
    options.method = args.method or "GET"
    options.data = args.data or options.data
    options.checkCertificate=options.checkCertificate
    if args.basicAuthorization then 
      options.headers['Authorization'] = 
      self:basicAuthorization(args.basicAuthorization.user,args.basicAuthorization.password)
    end
    if args.accept then options.headers['Accept'] = args.accept end
    net.HTTPClient():request(url,{
        options = options,
        success=function(resp)
          self:post({type='HTTPEvent',status=resp.status,data=resp.data,headers=resp.headers,tag=args.tag})
        end,
        error=function(resp)
          self:post({type='HTTPEvent',result=resp,tag=args.tag})
        end
      })
  end

  em.midnight,em.hm2sec,em.toTime,em.transform,em.copy,em.equal,em.isEvent,em.isRule,em.coerce,em.comboEvent = 
  midnight,hm2sec,toTime,transform,copy,equal,isEvent,isRule,coerce,comboEvent
  self.EM = em
  self._eventHandler = handleEvent
end -- events