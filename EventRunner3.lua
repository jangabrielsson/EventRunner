--[[
%% properties
17 value
55 value
56 value
57 value
88 value
%% events
5 CentralSceneEventx
22 GeofenceEvent
%% globals 
Test
%% autostart 
--]] 

if dofile and not _EMULATED then _EMULATED={name="EventRunner",id=99,maxtime=24} dofile("HC2.lua") end -- For HC2 emulator

local _version,_fix = "3.0","B54"  -- Aug 15, 2019  

local _sceneName   = "Demo"                                 -- Set to scene/script name
local _homeTable   = "devicemap"                            -- Name of your HomeTable variable (fibaro global)
--local _HueUserName = ".........."                           -- Hue API key
--local _HueIP       = "192.168.1.XX"                         -- Hue bridge IP
--local _NodeRed     = "http://192.168.1.YY:8080/EventRunner" -- Nodered URL
--local _TelegBOT    = "t34yt98iughvnw9458gy5of45pg:chr9hcj"  -- Telegram BOT key
--local _TelegCID    = 6876768686                             -- Telegram chat ID

if loadfile then local cr = loadfile("credentials.lua"); if cr then cr() end end
-- To not accidently commit credentials to Github, or post at forum :-)
-- E.g. Hue user names, icloud passwords etc. HC2 credentials is set from HC2.lua, but can use same file.

-- debug flags for various subsystems (global)
_debugFlags = { 
  post=true,invoke=false,triggers=true,dailys=false,rule=false,ruleTrue=false,
  fcall=true, fglobal=false, fget=false, fother=false, hue=true, telegram=false, nodered=false,
}
-- options for various subsystems (global)
_options=_options or {}

-- Hue setup before main() starts. You can add more Hue.connect() inside this if you have more Hue bridges.
function HueSetup() if _HueUserName and _HueIP then Hue.connect(_HueUserName,_HueIP) end end

---------- Main --------------------------------------
function main()
  local rule,define = Rule.eval, Util.defvar

  if _EMULATED then
    --_System.speed(true)               -- run emulator faster than real-time
    --_System.setRemote("devices",{5})  -- make device 5 remote (call HC2 with api)
    --_System.installProxy()            -- Install HC2 proxy sending sourcetriggers back to emulator
  end

  local HT =  -- Example of in-line "home table"
  {
    dev = 
    { bedroom = {lamp = 88,motion = 99},
      phones = {bob = 121},
      kitchen = {lamp = 66, motion = 77},
    },
    other = "other"
  }

--or read in "HomeTable" from a fibaro global variable (or scene)
--local HT = type(_homeTable)=='number' and api.get("/scenes/".._homeTable).lua or fibaro:getGlobalValue(_homeTable) 
--HT = type(HT) == 'string' and json.decode(HT) or HT
  Util.defvars(HT.dev)            -- Make HomeTable variables available in EventScript
  Util.reverseMapDef(HT.dev)      -- Make HomeTable variable names available for logger

--rule("@@00:00:05 => f=!f; || f >> log('Ding!') || true >> log('Dong!')") -- example rule logging ding/dong every 5 second
  
--Nodered.connect(_NodeRed)            -- Setup nodered functionality
--Telegram.bot(_TelegBOT)              -- Setup Telegram bot that listens on oncoming messages. Only one per BOT.
--Telegram.msg({_TelegCID,_TelegBOT})  -- Send msg to Telegram without BOT setup
--rule("@{06:00,catch} => Util.checkVersion()") -- Check for new version every morning at 6:00
--rule("#ER_version => log('New ER version, v:%s, fix:%s',env.event.version,env.event.fix)")
--rule("#ER_version => log('...patching scene'); Util.patchEventRunner()") -- Auto patch new versions...
  if _EMULATED then 
    --dofile("example_rules3.lua")
  end
end

------------------- EventModel - Don't change! -------------------- 
local function setDefault(GL,V) if _options[GL]==nil then _options[GL]=V end return _options[GL] end
local _RULELOGLENGTH = setDefault('RULELOGLENGTH',80)
local _TIMEADJUST = setDefault('TIMEADJUST',0)
local _STARTONTRIGGER = setDefault('STARTONTRIGGER',false)
local _NUMBEROFBOXES = setDefault('NUMBEROFBOXES',1)
local _MIDNIGHTADJUST = setDefault('MIDNIGHTADJUST',false)
setDefault('DEVICEAUTOACTION',false)
local _VALIDATECHARS = setDefault('VALIDATECHARS',true)
local _NODEREDTIMEOUT = setDefault('NODEREDTIMEOUT',5000)
local _EVENTRUNNERSRCPATH = setDefault('EVENTRUNNERSRCPATH',"EventRunner3.lua")
local _HUETIMEOUT = setDefault('HUETIMEOUT',10000)
local _MARSHALL = setDefault('MARSHALL',true)
setDefault('SUBFILE',nil)

local _MAILBOXES={}
local _MAILBOX = "MAILBOX"..__fibaroSceneId 
local _emulator={ids={},adress=nil}
local _supportedEvents = {property=true,global=true,event=true,remote=true}
local _trigger = fibaro:getSourceTrigger()
local _type, _source = _trigger.type, _trigger
function urldecode(str) return str:gsub('%%(%x%x)',function (x) return string.char(tonumber(x,16)) end) end
local function isRemoteEvent(e) return type(e)=='table' and type(e[1])=='string' end -- change in the future...
local function encodeRemoteEvent(e) return {urlencode(json.encode(e)),'%%ER%%'} end
local function decodeRemoteEvent(e) return (json.decode((urldecode(e[1])))) end

local args = fibaro:args()
if _type == 'other' and args and isRemoteEvent(args) then
  _trigger,_type = decodeRemoteEvent(args),'remote'
end

---------- Producer(s) - Handing over incoming triggers to consumer --------------------
local _MAXWAIT=5.0 -- seconds to wait
if _supportedEvents[_type] then 
  local _MBP = _MAILBOX.."_"
  local mbp,mb,time,cos,count = 1,nil,os.clock(),nil,fibaro:countScenes()
  if not _STARTONTRIGGER then
    if count == 1 then fibaro:debug("Aborting: Server not started yet"); fibaro:abort() end
  end
  if _EMULATED then -- If running in emulated mode, use shortcut to pass event to main instance
    local _,env = _System.getInstance(__fibaroSceneId,1) -- if we only could do this on the HC2...
    setTimeout(function() env.Event._handleEvent(_trigger) end,nil,"",env)
    fibaro:abort()
  end
  local event = type(_trigger) ~= 'string' and json.encode(_trigger) or _trigger
  local ticket = string.format('<@>%s%s',tostring(_source),event)
  math.randomseed(time*100000)
  cos = math.random(1,_NUMBEROFBOXES)
  mbp=cos
  repeat
    mb = _MBP..mbp
    mbp = (mbp % _NUMBEROFBOXES)+1
    while(fibaro:getGlobal(mb) ~= "") do
      if os.clock()-time>=_MAXWAIT then fibaro:debug("Couldn't post event (dead?), dropping:"..event) fibaro:abort() end
      if mbp == cos then fibaro:sleep(10) end
      mb = _MBP..mbp
      mbp = (mbp % _NUMBEROFBOXES)+1
    end
    fibaro:setGlobal(mb,ticket) -- try to acquire lock
  until fibaro:getGlobal(mb) == ticket -- got lock
  fibaro:setGlobal(mb,event) -- write msg
  if count>1  then fibaro:abort() end -- and exit
  _trigger.type,_type='other','other'
end

---------- Consumer - re-posting incoming triggers as internal events --------------------
do
  local _getGlobal,_setGlobal = fibaro.getGlobal, fibaro.setGlobal
  function eventConsumer()
    local mailboxes,_debugFlags,Event,json = _MAILBOXES,_debugFlags,Event,json
    local _CXCS,_CXCST1,_CXCST2=250,os.clock()
    local function poll()
      _CXCS = math.min(2*(_CXCS+1),250)
      _CXCST1,_CXCST2 = os.clock(),_CXCST1
      if _CXCST1-_CXCST2 > 0.75 then Log(LOG.ERROR,"Slow mailbox watch:%ss",_CXCST1-_CXCST2) end
      for _,mb in ipairs(mailboxes) do
        local l = _getGlobal(nil,mb)
        if l and l ~= "" and l:sub(1,3) ~= '<@>' then -- Something in the mailbox
          _setGlobal(nil,mb,"") -- clear mailbox
          if _debugFlags.triggers then Debug(true,"Incoming event:"..l) end
          l = json.decode(l) l._sh=true
          setTimeout(function() Event.triggerHandler(l) end,5)-- and post it to our "main()"
          _CXCS=1
        end
      end
      setTimeout(poll,_CXCS) -- check again
    end
    poll()
  end
end
---------- Event manager --------------------------------------
function makeEventManager()
  local self,_handlers = {},{}
  self.BREAK, self.TIMER, self.RULE ='%%BREAK%%', '%%TIMER%%', '%%RULE%%'
  self.PING, self.PONG ='%%PING%%', '%%PONG%%'
  self._sections,self.SECTION = {},nil
  local isTimer,isEvent,isRule,coerce,format,toTime = Util.isTimer,Util.isEvent,Util.isRule,Util.coerce,string.format,Util.toTime
  local equal,copy = Util.equal,Util.copy
  local function timer2str(t) 
    return format("<timer:%s, start:%s, stop:%s>",t[self.TIMER],os.date("%c",t.start),os.date("%c",math.floor(t.start+t.len/1000+0.5))) 
  end
  local function mkTimer(f,t) t=t or 0; return {[self.TIMER]=setTimeout(f,t), start=os.time(), len=t, __tostring=timer2str} end
      
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

  function self._callTimerFun(e,src)
    local status,res,ctx = spcall(e) 
    if not status then 
      if not isError(res) then
        res={ERR=true,ctx=ctx,src=src or tostring(e),err=res}
      end
      Log(LOG.ERROR,"Error in '%s': %s",res and res.src or tostring(e),res.err)
      if res.ctx then Log(LOG.ERROR,"\n%s",res.ctx) end
    end
  end

  function self.post(e,time,src) -- time in 'toTime' format, see below.
    _assert(isEvent(e) or type(e) == 'function', "Bad2 event format %s",tojson(e))
    time = toTime(time or os.time())
    if time < os.time() then return nil end
    if type(e) == 'function' then 
      src = src or "timer "..tostring(e)
      if _debugFlags.postTimers then Debug(true,"Posting timer %s at %s",src,os.date("%a %b %d %X",time)) end
      return mkTimer(function() self._callTimerFun(e,src) end, 1000*(time-os.time()))
    end
    src = src or tojson(e)
    if _debugFlags.post and not e._sh then Debug(true,"Posting %s at %s",tojson(e),os.date("%a %b %d %X",time)) end
    return mkTimer(function() self._handleEvent(e) end,1000*(time-os.time()))
  end

  function self.cancel(t)
    _assert(isTimer(t) or t == nil,"Bad timer")
    if t then clearTimeout(t[self.TIMER]) end 
    return nil 
  end

  self.triggerHandler = self.post -- default handler for consumer

  function self.postRemote(sceneID, e) -- Post event to other scenes
    _assert(sceneID and tonumber(sceneID),"sceneID is not a number to postRemote:%s",sceneID or ""); 
    _assert(isEvent(e),"Bad event format to postRemote")
    e._from = _EMULATED and -__fibaroSceneId or __fibaroSceneId
    local payload = encodeRemoteEvent(e)
    if not _EMULATED then                  -- On HC2
      if sceneID < 0 then    -- call emulator 
        if not _emulator.adress then return end
        local HTTP = net.HTTPClient()
        HTTP:request(_emulator.adress.."trigger/"..sceneID,{options = {
              headers = {['Accept']='application/json',['Content-Type']='application/json'},
              data = json.encode(payload), timeout=2000, method = 'POST'},
            -- Can't figure out why we get an and of file - must depend on HC2.lua
            error = function(status) if status~="End of file" then Log(LOG.ERROR,"Emulator error:%s, (%s)",status,tojson(e)) end end,
            success = function(status) end,
          })
      else 
        fibaro:startScene(sceneID,payload) 
      end -- call other scene on HC2
    else -- on emulator
      fibaro:startScene(math.abs(sceneID),payload)
    end
  end

  local _getIdProp = function(id,prop) return fibaro:getValue(id,prop) end
  local _getGlobal = function(id) return fibaro:getGlobalValue(id) end

  local _getProp = {}
  _getProp['property'] = function(e,v)
    e.propertyName = e.propertyName or 'value'
    e.value = v or (_getIdProp(e.deviceID,e.propertyName,true))
    self.trackManual(e.deviceID,e.value)
    return nil -- was t
  end
  _getProp['global'] = function(e,v2) local v,t = _getGlobal(e.name,true) e.value = v2 or v return t end

  local function ruleToStr(r) return r.src end
  function self._mkCombEvent(e,action,doc,rl)
    local rm = {[self.RULE]=e, action=action, src=doc, cache={}, subs=rl}
    rm.enable = function() Util.mapF(function(e) e.enable() end,rl) return rm end
    rm.disable = function() Util.mapF(function(e) e.disable() end,rl) return rm end
    rm.start = function(event) self._invokeRule({rule=rm,event=event}) return rm end
    rm.print = function() Util.map(function(e) e.print() end,rl) end
    rm.__tostring = ruleToStr
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
        if s ~= handle then handlerEnable('disable',e) end
      end
    end
    return handlerEnable('enable',handle) 
  end
  function self.disable(handle) return handlerEnable('disable',handle) end

  function self.event(e,action,opt) -- define rules - event template + action
    opt=opt or {}
    local doc,front = opt.doc or nil, opt.front
    doc = doc or format(" Event.event(%s,...)",tojson(e))
    if e[1] then -- events is list of event patterns {{type='x', ..},{type='y', ...}, ...}
      return self._mkCombEvent(e,action,doc,Util.map(function(es) return self.event(es,action,opt) end,e))
    end
    _assert(isEvent(e), "bad event format '%s'",tojson(e))
    if e.deviceID and type(e.deviceID) == 'table' then  -- multiple IDs in deviceID {type='property', deviceID={x,y,..}}
      return self.event(Util.map(function(id) local el=copy(e); el.deviceID=id return el end,e.deviceID),action,opt)
    end
    action = self._compileAction(action,doc,opt.log)
    compilePattern(e)
    local hashKey = toHash[e.type] and toHash[e.type](e) or e.type
    _handlers[hashKey] = _handlers[hashKey] or {}
    local rules = _handlers[hashKey]
    local rule,fn = {[self.RULE]=e, action=action, src=doc, log=opt.log, cache={}}, true
    for _,rs in ipairs(rules) do -- Collect handlers with identical patterns. {{e1,e2,e3},{e1,e2,e3}}
      if equal(e,rs[1][self.RULE]) then if front then table.insert(rs,1,rule) else rs[#rs+1] = rule end fn = false break end
    end
    if fn then if front then table.insert(rules,1,{rule}) else rules[#rules+1] = {rule} end end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    rule.start = function(event) self._invokeRule({rule=rule,event=event}) return rule end
    rule.print = function() Log(LOG.LOG,"Event(%s) => ..",tojson(e)) end
    rule.__tostring = ruleToStr
    if self.SECTION then
      local s = self._sections[self.SECTION] or {}
      s[#s+1] = rule
      self._sections[self.SECTION] = s
    end
    return rule
  end

  function self.schedule(time,action,opt)
    opt = opt or {}
    local test,start,doc = opt.cond, opt.start or false, opt.doc or format("Schedule(%s):%s",time,tostring(action))
    local loop,tp = {type='_scheduler:'..doc, _sh=true}
    local test2,action2 = test and self._compileAction(test,doc,opt.log),self._compileAction(action,doc,opt.log)
    local re = self.event(loop,function(env)
        local fl = test == nil or test2()
        if fl == self.BREAK then return
        elseif fl then action2() end
        tp = self.post(loop, time, doc) 
      end)
    local res = nil
    res = {
      [self.RULE] = {}, src=doc, 
      enable = function() if not tp then tp = self.post(loop,(not start) and time or nil,doc) end return res end, 
      disable= function() tp = self.cancel(tp) return res end, 
      print = re.print,
      __tostring = ruleToStr
    }
    res.enable()
    return res
  end

  local _trueFor={ property={'value'}, global = {'value'}}
  function self.trueFor(time,event,action,name)
    local pattern,ev,ref = copy(event),copy(event),nil
    name=name or tojson(event)
    compilePattern(pattern)
    if _trueFor[ev.type] then 
      for _,p in ipairs(_trueFor[ev.type]) do ev[p]=nil end
    else error(format("trueFor can't handle events of type '%s'%s",event.type,name)) end
    return Event.event(ev,function(env) 
        local p = self._match(pattern,env.event)
        if p then env.p = p; self.post(function() ref=nil action(env) end, time, name) else self.cancel(ref) end
      end)
  end

  function self.pollTriggers(devices)
    local filter = {}
    local function truthTable(t) local res={}; for _,p in ipairs(t) do res[p]=true end return res end
    for id,t in pairs(devices) do filter[id]=truthTable(type(t)=='table' and t or {t}) end
    INTERVAL = 2
    lastRefresh = 0
    function pollRefresh()
      states = api.get("/refreshStates?last=" .. lastRefresh)
      if states then
        lastRefresh=states.last
        for k,v in pairs(states.changes or {}) do
          for p,a in pairs(v) do
            if p~='id' and filter[v.id] and filter[v.id][p] then
              local e = {type='property', deviceID=v.id,propertyName=p, value=a}
              print(json.encode(e))
            end
          end
        end
      end
      setTimeout(pollRefresh,INTERVAL*1000)
    end
    pollRefresh()
  end

  function self._compileAction(a,src,log)
    if type(a) == 'function' then return a                   -- Lua function
    elseif isEvent(a) then 
      return function(e) return self.post(a,nil,e.rule) end  -- Event -> post(event)
    elseif type(a)=='string' or type(a)=='table' then        -- EventScript
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
    end
    error("Unable to compile action:"..json.encode(a))
  end

  function self._invokeRule(env,event)
    local t = os.time()
    env.last,env.rule.time,env.log = t-(env.rule.time or 0),t,env.rule.log
    env.event = env.event or event
    if _debugFlags.invoke and (env.event == nil or not env.event._sh) then Debug(true,"Invoking:%s",env.rule.src) end
    local status, res, ctx = spcall(env.rule.action,env) -- call the associated action
    if not status then
      if not isError(res) then
        res={ERR=true,ctx=ctx,src=env.src,err=res}
      end
      Log(LOG.ERROR,"Error in '%s': %s",res and res.src or "rule",res.err)
      if res.ctx then Log(LOG.ERROR,"\n%s",res.ctx) end
      self.post({type='error',err=res,rule=res.src,event=tojson(env.event),_sh=true})    -- Send error back
      env.rule._disabled = true                            -- disable rule to not generate more errors
    end
  end

-- {{e1,e2,e3},{e4,e5,e6}} env={event=_,p=_,locals=_,rule.src=_,last=_}
  function self._handleEvent(e) -- running a posted event
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
              self._invokeRule(env) 
            end
          end
        end
      end
    end
  end

-- Extended fibaro:* commands, toggle, setValue, User defined device IDs, > 10000
  fibaro._idMap={}
  fibaro._call,fibaro._get,fibaro._getValue,fibaro._actions,fibaro._properties=fibaro.call,fibaro.get,fibaro.getValue,{},{}
  local lastID = {}
  function self.lastManual(id)
    lastID[id] = lastID[id] or {time=0}
    if lastID[id].script then return -1 else return os.time()-lastID[id].time end
  end
  function self.trackManual(id,value)
    lastID[id] = lastID[id] or {time=0}
    if lastID[id].script==nil or os.time()-lastID[id].time>1 then lastID[id]={time=os.time()} end -- Update last manual
  end
  function self._registerID(id,call,get) fibaro._idMap[id]={call=call,get=get} end

  -- We intercept fibaro:call, fibaro:get, and fibaro:getValue - we may change this to an object model
  local _DEFACTIONS={wakeUpDeadDevice=true, setProperty=true}
  function fibaro.call(obj,id,call,...)
    id = tonumber(id); if not id then error("deviceID not a number",2) end
    if ({turnOff=true,turnOn=true,on=true,off=true,setValue=true})[call] then lastID[id]={script=true,time=os.time()} end
    if call=='toggle' then 
      return fibaro.call(obj,id,fibaro:getValue(id,"value")>"0" and "turnOff" or "turnOn") 
    end
    if fibaro._idMap[id] then return fibaro._idMap[id].call(obj,id,call,...) end
    -- Now we have a real deviceID
    if select(2,__fibaro_get_device(id)) == 404 then Log(LOG.ERROR,"No such deviceID:%s",id) return end
    fibaro._actions[id] = fibaro._actions[id] or api.get("/devices/"..id).actions
    if call=='setValue' and not fibaro._actions[id].setValue and fibaro._actions[id].turnOn then
      return fibaro._call(obj,id,tonumber(({...})[1]) > 0 and "turnOn" or "turnOff")
    end
    if _options.DEVICEAUTOACTION or _DEFACTIONS[call] then fibaro._actions[id][call]="1" end
    _assert(fibaro._actions[id][call],"ID:%d does not support action '%s'",id,call)
    return fibaro._call(obj,id,call,...)
  end 

  local _DEV_PROP_MAP={["IPAddress"]='ip', ["TCPPort"]='port'}
  function fibaro.get(obj,id,prop,...) 
    id = tonumber(id); if not id then error("deviceID not a number",2) end
    if fibaro._idMap[id] then return fibaro._idMap[id].get(obj,id,prop,...) end
    if select(2,__fibaro_get_device(id)) == 404 then Log(LOG.ERROR,"No such deviceID:%s",id) return end
    fibaro._properties[id] = fibaro._properties[id] or api.get("/devices/"..id).properties
    if not _DEV_PROP_MAP[prop] then
      _assert(fibaro._properties[id][prop]~=nil,"ID:%d does not support property '%s'",id,prop) 
    end
    return fibaro._get(obj,id,prop,...) 
  end
  function fibaro.getValue(obj,id,prop,...) 
    id = tonumber(id); if not id then error("deviceID not a number",2) end
    if fibaro._idMap[id] then return (fibaro._idMap[id].get(obj,id,prop,...)) end
    if select(2,__fibaro_get_device(id)) == 404 then Log(LOG.ERROR,"No such deviceID:%s",id) return end
    fibaro._properties[id] = fibaro._properties[id] or api.get("/devices/"..id).properties
    _assert(fibaro._properties[id][prop]~=nil,"ID:%d does not support property '%s'",id,prop) 
    return fibaro._getValue(obj,id,prop,...) 
  end

-- Logging of fibaro:* calls -------------
  local function traceFibaro(name,flag,rt)
    local orgFun=fibaro[name]
    fibaro[name]=function(f,id,...)
      local args={...}
      local stat,res = pcall(function() return {orgFun(f,id,table.unpack(args))} end)
      if stat then
        if _debugFlags[flag] then
          if rt then rt(id,args,res)
          else
            local astr=(id~=nil and Util.reverseVar(id).."," or "")..json.encode(args):sub(2,-2)
            Debug(true,"fibaro:%s(%s)%s",name,astr,#res>0 and "="..tojson(res):sub(2,-2) or "")
          end
        end
        if #res>0 then return table.unpack(res) else return nil end
      else
        local astr=(id~=nil and Util.reverseVar(id).."," or "")..json.encode(args):sub(2,-2)
        error(format("fibaro:%s(%s),%s",name,astr,res),3)
      end
    end
  end

  if not _EMULATED then  -- Emulator logs fibaro:* calls for us
    local maps = {
      {"call","fcall"},{"setGlobal","fglobal"},{"getGlobal","fglobal"},{"getGlobalValue","fglobal"},
      {"get","fget"},{"getValue","fget"},{"killScenes","fother"},{"abort","fother"},
      {"sleep","fother",function(id,args,res) 
          Debug(true,"fibaro:sleep(%s) until %s",id,os.date("%X",os.time()+math.floor(0.5+id/1000))) 
        end},        
      {"startScene","fother",function(id,args,res) 
          local a = isRemoteEvent(args[1]) and json.encode(decodeRemoteEvent(args[1])) or args and json.encode(args)
          Debug(true,"fibaro:startScene(%s%s)",id,a and ","..a or "") 
        end},
    }
    for _,f in ipairs(maps) do traceFibaro(f[1],f[2],f[3]) end
  end

  function fibaro:sleep() error("Not allowed to use fibaro:sleep in EventRunner scenes!") end

  return self
end

---------- Utilities --------------------------------------
local function makeUtils()
  local LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ULOG="Khaki", ERROR = "Tomato"}
  local self,format = {},string.format
  gEventRunnerKey="6w8562395ue734r437fg3"
  gEventSupervisorKey="9t823239".."5ue734r327fh3"
  if not _EMULATED then -- Patch possibly buggy setTimeout - what is 1ms between friends...
    clearTimeout,oldClearTimout=function(ref)
      if type(ref)=='table' and ref[1]=='%EXT%' then ref=ref[2] end
      oldClearTimout(ref)
    end,clearTimeout

    setTimeout,oldSetTimout=function(f,ms)
      local ref,maxt={'%EXT%'},2147483648-1
      ms = ms and ms < 1 and 1 or ms
      if ms > maxt then
        ref[2]=oldSetTimout(function() ref[2 ]=setTimeout(f,ms-maxt)[2] end,maxt)
      else ref[2 ]=oldSetTimout(f,ms) end
      return ref
    end,setTimeout
  end

  local function prconv(o)
    if type(o)=='table' then
      if o.__tostring then return o.__tostring(o)
      else return tojson(o) end
    else return o end
  end
  local function prconvTab(args) local r={}; for _,o in ipairs(args) do r[#r+1]=prconv(o) end return r end

  local function _Msg(color,message,...)
    local args = type(... or 42) == 'function' and {(...)()} or {...}
    local tadj = _TIMEADJUST > 0 and os.date("(%X) ") or ""
    message = #args > 0 and format(message,table.unpack(prconvTab(args))) or prconv(message)
    fibaro:debug(format('<span style="color:%s;">%s%s</span><br>', color, tadj, message))
    return message
  end

  if _System and _System._Msg then _Msg=_System._Msg end -- Get a better ZBS version of _Msg if running emulated 

  local function protectMsg(...)
    local args = {...}
    local stat,res=pcall(function() return _Msg(table.unpack(args)) end)
    if not stat then error("Bad arguments to Log/Debug:"..tojson(args),2)
    else return res end
  end

  function _assert(test,msg,...) if not test then error(string.format(msg,...),3) end end
  function _assertf(test,msg,fun) if not test then error(string.format(msg,fun and fun() or ""),3) end end

  function Debug(flag,message,...) if flag then _Msg(LOG.DEBUG,message,...) end end
  function Log(color,message,...) return protectMsg(color,message,...) end
  function isError(e) return type(e)=='table' and e.ERR end
  function throwError(args) args.ERR=true; error(args,args.level) end

  function spcall(fun,...)
    local stat={pcall(fun,...)}
    if not stat[1] then
      local msg = type(stat[2])=='table' and stat[2].err or stat[2]
      local line,l,src,lua = tonumber(msg:match(":(%d+)")),0,{},nil
      if line == nil or line == "" then return false,stat[2],"" end
      if _options.SUBFILE and msg:match(_options.SUBFILE..":"..line) then
        local f = io.open(_options.SUBFILE); lua = f:read("*all")
      else lua = api.get("/scenes/"..__fibaroSceneId).lua end
      for row in lua:gmatch(".-\n") do l=l+1; 
        if math.abs(line-l)<3 then src[#src+1]=string.format("Line %d:%s%s",l,(l==line and ">>>" or ""),row) end
      end
      return false,stat[2],table.concat(src)
    end
    return table.unpack(stat)
  end

  function self.map(f,l,s) s = s or 1; local r={} for i=s,table.maxn(l) do r[#r+1] = f(l[i]) end return r end
  function self.mapAnd(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) if not e then return false end end return e end 
  function self.mapOr(f,l,s) s = s or 1; for i=s,table.maxn(l) do local e = f(l[i]) if e then return e end end return false end
  function self.mapF(f,l,s) s = s or 1; local e=true for i=s,table.maxn(l) do e = f(l[i]) end return e end
  function self.mapkl(f,l) local r={} for i,j in pairs(l) do r[#r+1]=f(i,j) end return r end
  function self.mapkk(f,l) local r={} for k,v in pairs(l) do r[k]=f(v) end return r end
  function self.member(v,tab) for _,e in ipairs(tab) do if v==e then return e end end return nil end
  function self.append(t1,t2) for _,e in ipairs(t2) do t1[#t1+1]=e end return t1 end
  function self.gensym(s) return s..tostring({1,2,3}):match("([abcdef%d]*)$") end
  local function transform(obj,tf)
    if type(obj) == 'table' then
      local res = {} for l,v in pairs(obj) do res[l] = Util.transform(v,tf) end 
      return res
    else return tf(obj) end
  end
  function self.copy(obj) return transform(obj, function(o) return o end) end
  local function equal(e1,e2)
    local t1,t2 = type(e1),type(e2)
    if t1 ~= t2 then return false end
    if t1 ~= 'table' and t2 ~= 'table' then return e1 == e2 end
    for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
    for k2,v2 in pairs(e2) do if e1[k2] == nil or not equal(e1[k2],v2) then return false end end
    return true
  end
  function self.randomizeList(list)
    local res,l,j,n = {},{}; for _,v in pairs(list) do l[#l+1]=v end 
    n=#l
    for i=n,1,-1 do j=math.random(1,i); res[#res+1]=l[j]; table.remove(l,j) end
    return res
  end
  local function isVar(v) return type(v)=='table' and v[1]=='%var' end
  self.isVar = isVar
  function self.isGlob(v) return isVar(v) and v[3]=='glob' end
  local function time2str(t) return format("%02d:%02d:%02d",math.floor(t/3600),math.floor((t%3600)/60),t%60) end
  local function midnight() local t = os.date("*t"); t.hour,t.min,t.sec = 0,0,0; return os.time(t) end
  local function hm2sec(hmstr)
    local offs,sun
    sun,offs = hmstr:match("^(%a+)([+-]?%d*)")
    if sun and (sun == 'sunset' or sun == 'sunrise') then
      hmstr,offs = fibaro:getValue(1,sun.."Hour"), tonumber(offs) or 0
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
  self.toTime,self.midnight,self.toDate,self.time2str,self.transform,self.equal=toTime,midnight,toDate,time2str,transform,equal

  function self.isTimer(t) return type(t) == 'table' and t[Event.TIMER] end
  function self.isRule(r) return type(r) == 'table' and r[Event.RULE] end
  function self.isEvent(e) return type(e) == 'table' and e.type end
  function self.isTEvent(e) return type(e)=='table' and (e[1]=='%table' or e[1]=='%quote') and type(e[2])=='table' and e[2].type end
  function self.coerce(x,y) local x1 = tonumber(x) if x1 then return x1,tonumber(y) else return x,y end end
  self.S1 = {click = "16", double = "14", tripple = "15", hold = "12", release = "13"}
  self.S2 = {click = "26", double = "24", tripple = "25", hold = "22", release = "23"} 
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

  function self.validateChars(str,msg)
    if _VALIDATECHARS then local p = str:find("\xEF\xBB\xBF") if p then error(format("Char:%s, "..msg,p,str)) end end
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
  function self.printRule(rule)
    Log(LOG.LOG,"-----------------------------------")
    Log(LOG.LOG,"Source:'%s'",rule.src)
    rule.print()
    Log(LOG.LOG,"-----------------------------------")
  end
  function self.dump(code)
    code = code or {}
    for p = 1,#code do
      local i = code[p]
      Log(LOG.LOG,"%-3d:[%s/%s%s%s]",p,i[1],i[2] ,i[3] and ","..tojson(i[3]) or "",i[4] and ","..tojson(i[4]) or "")
    end
  end

  self.getIDfromEvent={ CentralSceneEvent=function(d) return d.deviceId end,AccessControlEvent=function(d) return d.id end }
  self.getIDfromTrigger={
    property=function(e) return e.deviceID end,
    event=function(e) return e.event and Util.getIDfromEvent[e.event.type or ""](e.event.data) end
  }

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
      local status,res = ScriptEngine.eval(co.context)
      co.state= status=='suspended' and status or 'dead'
      return true,table.unpack(res)
    end,
    status = function(co) return co.state end,
    _reset = function(co) co.state,co.context.cp='suspended',1; co.context.stack.clear(); return co.context end
  }

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

  self._vars = {}
  local _vars = self._vars
  local _triggerVars = {}
  self._triggerVars = _triggerVars
  self._reverseVarTable = {}
  function self.defvar(var,expr) if _vars[var] then _vars[var][1]=expr else _vars[var]={expr} end end
  function self.defvars(tab) for var,val in pairs(tab) do self.defvar(var,val) end end
  function self.defTriggerVar(var,expr) _triggerVars[var]=true; self.defvar(var,expr) end
  function self.triggerVar(v) return _triggerVars[v] end
  function self.reverseMapDef(table) 
    if _EMULATED and _System.reverseMapDef then _System.reverseMapDef(table) end 
    self._reverseMap({},table) 
  end
  function self._reverseMap(path,value)
    if type(value) == 'number' then self._reverseVarTable[tostring(value)] = table.concat(path,".")
    elseif type(value) == 'table' and not value[1] then
      for k,v in pairs(value) do table.insert(path,k); self._reverseMap(path,v); table.remove(path) end
    end
  end
  function self.reverseVar(id) return Util._reverseVarTable[tostring(id)] or id end

  function self.encodePostEvent(event) --> payload for POST
    event._from = _EMULATED and -__fibaroSceneId or __fibaroSceneId
    return {args={encodeRemoteEvent(event)[1]}}
  end

  self.netSync = { HTTPClient = function (log)   
      local self,queue,HTTP,key = {},{},net.HTTPClient(),0
      local _request
      local function dequeue()
        table.remove(queue,1)
        local v = queue[1]
        if v then 
          Debug(_debugFlags.netSync,"netSync:Pop %s",v[3])
          setTimeout(function() _request(table.unpack(v)) end,1) 
        end
      end
      function _request(url,params,key)
        local uerr,usucc = params.error,params.success
        params.error = function(status)
          Debug(_debugFlags.netSync,"netSync:Error %s",key)
          dequeue()
          if params._logErr then Log(LOG.LOG.ERROR,"%s:%s",log or "netSync:",tojson(status.status)) end
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

  ---- SunCalc -----
  do
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
  end

  self.LOG = LOG
  return self
end

---------- EventScript Parser --------------------------------------
--[[
<statements> := <statement> [; <statements>]
<statement> := local <varlist> [= <expr>[,<expr>]
<statement> := while <expr> do <statements> end 
<statement> := repeat <statements> until <expr> 
<statement> := if <expr> then <statements> <elseend>
<elseend> end 
<elseend> else <statements> 
<elseend> elseif <expr> then <statements> <elseends>
--]]

local function makeEventScriptParser()
  local source, tokens, cursor
  local mkStack,mkStream,toTime,map,mapkk,gensym=Util.mkStack,Util.mkStream,Util.toTime,Util.map,Util.mapkk,Util.gensym
  local patterns,self = {},{}
  local opers = {['%neg']={14,1},['t/']={14,1,'%today'},['n/']={14,1,'%nexttime'},['+/']={14,1,'%plustime'},['$']={14,1,'%vglob'},
    ['.']={12.9,2},[':']= {13,2,'%prop'},['..']={9,2,'%betw'},['@']={9,1,'%daily'},['jmp']={9,1},['::']={9,1},--['return']={-0.5,1},
    ['@@']={9,1,'%interv'},['+']={11,2},['-']={11,2},['*']={12,2},['/']={12,2},['%']={12,2},['==']={6,2},['<=']={6,2},['>=']={6,2},['~=']={6,2},
    ['>']={6,2},['<']={6,2},['&']={5,2,'%and'},['|']={4,2,'%or'},['!']={5.1,1,'%not'},['=']={0,2},['+=']={0,2},['-=']={0,2},
    ['*=']={0,2},[';']={-1,2,'%progn'},
  }
  local nopers = {['jmp']=true,}--['return']=true}
  local reserved={
    ['sunset']={{'sunset'}},['sunrise']={{'sunrise'}},['midnight']={{'midnight'}},['dusk']={{'dusk'}},['dawn']={{'dawn'}},
    ['now']={{'now'}},['wnum']={{'wnum'}},['env']={{'env'}},
    ['true']={true},['false']={false},['{}']={{'quote',{}}},['nil']={nil},
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
  token("[A-Za-z_][%w_]*", function (w) return {type=nopers[w] and 'operator' or "name", sw=nopers[w] and 'op' or 'nam', value=w} end)
  token("%d+%.%d+", function (d) return {type="number", sw='num', value=tonumber(d)} end)
  token("%d+", function (d) return {type="number", sw='num', value=tonumber(d)} end)
  token('"([^"]*)"', function (s) return {type="string", sw='str', value=s} end)
  token("'([^']*)'", function (s) return {type="string", sw='str', value=s} end)
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
      return {'local',vars,exprs}
    elseif t.value == 'while' then inp.next()
      local test = gExpr(inp,{['do']=true}); matchv(inp,'do',"While loop")
      local body = gStatements(inp,{['end']=true}); matchv(inp,'end',"While loop")
      return {'%frame',{'while',test,body}}
    elseif t.value == 'repeat' then inp.next()
      local body = gStatements(inp,{['until']=true}); matchv(inp,'until',"Repeat loop")
      local test = gExpr(inp,stop)
      return {'%frame',{'repeat',body,test}}
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
        return {'%frame',{'%progn',{'local',{var,var2,l[2],i[2]},{}},
            {'setList',{i,l,v1},{'pack',expr}},{'setList',{v1,v2},{'pack',{'%calls',i,l,v1}}}},
          {'while',v1,{'%progn',body,{'setList',{v1,v2},{'pack',{'%calls',i,l,v1}}}}}}
      else -- for for a = x,y,z  do ... end
        matchv(inp,'=') -- local a,e,s,si=x,y,z; si=sign(s); e*=si while a*si<=e do ... a+=s end
        local inits = {}
        inits[1] = {gExpr(inp,{[',']=true,['do']=true})}
        while inp.peek().value==',' do inp.next(); inits[#inits+1]= {gExpr(inp,{[',']=true,['do']=true})} end
        matchv(inp,'do',"For loop")
        local body = gStatements(inp,{['end']=true}); matchv(inp,'end',"For loop")
        local v,s,e,step = mkVar(var),mkVar(),mkVar(),mkVar()
        if #inits<3 then inits[#inits+1]={1} end
        local locals = {'local',{var,e[2],step[2],s[2]},inits}
        return {'%frame',{'%progn',locals,mkSet(s,{'sign',step}),{'*=',e,s},{'while',{'<=',{'*',v,s},e},{'%progn',body,{'+=',v,step}}}}}
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
      if type(e[5])~='table' then args[#args+1]={e[5]} else args[#args+1]=false compT(e[5],ops) n=n+1 end
      if type(e[4])~='table' then args[#args+1]={e[4]} else args[#args+1]=false compT(e[4],ops) n=n+1 end
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
  comp['local'] = function(e,ops)
    for _,e1 in ipairs(e[3]) do compT(e1[1],ops) end
    ops[#ops+1]={mkOp('%local'),#e[3],e[2]}
  end
  comp['while'] = function(e,ops) -- lbl1, test, infskip lbl2, body, jmp lbl1, lbl2
    local test,body,lbl1,cp=e[2],e[3],gensym('LBL1')
    local jmp={mkOp('%ifnskip'),0,nil,true}
    ops[#ops+1] = {'%addr',0,lbl1}; ops[#ops+1] = POP
    compT(test,ops); ops[#ops+1]=jmp; cp=#ops
    compT(body,ops); ops[#ops+1]=POP; ops[#ops+1]={mkOp('%jmp'),0,lbl1}
    jmp[3]=#ops+1-cp
  end
  comp['repeat'] = function(e,ops) -- -- lbl1, body, test, infskip lbl1
    local body,test,z=e[2],e[3],#ops
    compT(body,ops); ops[#ops+1]=POP; compT(test,ops)
    ops[#ops+1] = {mkOp('%ifnskip'),0,z-#ops,true}
  end

  function self.compile(src,log) 
    local code,res=type(src)=='string' and self.parser.parse(src) or src,{}
    if log and log.code then print(json.encode(code)) end
    compT(code,res) 
    if log and log.code then Util.dump(res) end
    return res 
  end
  function self.compile2(code) local res={}; compT(code,res); return res end
  return self
end

---------- Event Script RunTime --------------------------------------
function makeEventScriptRuntime()
  local self,instr={},{}
  local format = string.format
  local function safeEncode(e) local stat,res = pcall(function() return tojson(e) end) return stat and res or tostring(e) end
  local toTime,midnight,map,mkStack,copy,coerce,isEvent=Util.toTime,Util.midnight,Util.map,Util.mkStack,Util.copy,Util.coerce,Util.isEvent
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
  local getVarFs = { script=getVar, glob=function(n,e) return marshallFrom(fibaro:getGlobalValue(n)) end }
  local setVarFs = { script=setVar, glob=function(n,v,e) fibaro:setGlobal(n,marshallTo(v)) return v end }
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
  local _getFun = function(id,prop) return fibaro:get(id,prop) end
  do
    local get = _getFun
    local function on(id,prop) return fibaro:get(id,prop) > '0' end
    local function off(id,prop) return fibaro:get(id,prop) == '0' end
    local function last(id,prop) return os.time()-select(2,fibaro:get(id,prop)) end
    local function eid(id,prop) return _lastEID[prop][id] or {} end
    local function armed(id,prop) return fibaro:get(id,prop) == '1' end
    local function call(id,cmd) fibaro:call(id,cmd); return true end
    local function set(id,cmd,val) fibaro:call(id,cmd,val); return val end
    local function setArmed(id,cmd,val) fibaro:call(id,cmd,val and '1' or '0'); return val end
    local function set2(id,cmd,val) fibaro:call(id,cmd,table.unpack(val)); return val end
    local mapOr,mapAnd,mapF=Util.mapOr,Util.mapAnd,function(f,l,s) Util.mapF(f,l,s); return true end
    getFuns={
      value={get,'value',nil,true},bat={get,'batteryLevel',nil,true},power={get,'power',nil,true},
      isOn={on,'value',mapOr,true},isOff={off,'value',mapAnd,true},isAllOn={on,'value',mapAnd,true},isAnyOff={off,'value',mapOr,true},
      last={last,'value',nil,true},scene={get,'sceneActivation',nil,true},
      access={eid,'AccessControlEvent',nil,true},central={eid,'CentralSceneEvent',nil,true},
      safe={off,'value',mapAnd,true},breached={on,'value',mapOr,true},isOpen={on,'value',mapOr,true},isClosed={off,'value',mapAnd,true},
      lux={get,'value',nil,true},temp={get,'value',nil,true},on={call,'turnOn',mapF,true},off={call,'turnOff',mapF,true},
      open={call,'open',mapF,true},close={call,'close',mapF,true},stop={call,'stop',mapF,true},
      secure={call,'secure',mapF,true},unsecure={call,'unsecure',mapF,true},
      name={function(id) return fibaro:getName(id) end,nil,nil,false},
      roomName={function(id) return fibaro:getRoomNameByDeviceID(id) end,nil,nil,false},
      trigger={function() return true end,'value',nil,true},time={get,'time',nil,true},armed={armed,'armed',mapOr,true},
      manual={function(id) return Event.lastManual(id) end,'value',nil,true},
      start={function(id) return fibaro:startScene(id) end,"",mapF,false},kill={function(id) return fibaro:killScenes(id) end,"",mapF,false},
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
    setFuns={
      R={set,'setR'},G={set,'setG'},B={set,'setB'},W={set,'setW'},value={set,'setValue'},armed={setArmed,'setArmed'},
      time={set,'setTime'},power={set,'setPower'},targetLevel={set,'setTargetLevel'},interval={set,'setInterval'},
      mode={set,'setMode'},setpointMode={set,'setSetpointMode'},defaultPartyTime={set,'setDefaultPartyTime'},
      scheduleState={set,'setScheduleState'},color={set2,'setColor'},
      thermostatSetpoint={set2,'setThermostatSetpoint'},schedule={set2,'setSchedule'},
      msg={set,'sendPush'},defemail={set,'sendDefinedEmailNotification'},btn={set,'pressButton'},
      email={function(id,cmd,val) local h,m = val:match("(.-):(.*)"); fibaro:call(id,'sendEmail',h,m) return val end,""},
      start={function(id,cmd,val) if isEvent(val) then Event.postRemote(id,val) else fibaro:startScene(id,val) return true end end,""},
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
    if type(id)=='table' then s.push((f[3] or map)(function(id) return f[1](ID(id,i,e._lastR),f[2]) end,id))
    else s.push(f[1](ID(id,i,e._lastR),f[2])) end
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
    fibaro:call(ID(id,i),"setProperty",format("ui.%s.value",lbl),tostring(v)) s.push(v) 
  end
  instr['%setslider'] = instr['setlabel'] 

-- ER funs
  local simpleFuns={num=tonumber,str=tostring,idname=Util.reverseVar,time=toTime,['type']=type,
    tjson=safeEncode,fjson=json.decode}
  for n,f in pairs(simpleFuns) do instr[n]=function(s,n,e,i) return s.push(f(s.pop())) end end

  instr['sunset']=function(s,n,e,i) s.push(toTime(fibaro:getValue(1,'sunsetHour'))) end
  instr['sunrise']=function(s,n,e,i) s.push(toTime(fibaro:getValue(1,'sunriseHour'))) end
  instr['midnight']=function(s,n,e,i) s.push(midnight()) end
  instr['dawn']=function(s,n,e,i) s.push(toTime(fibaro:getValue(1,'dawnHour'))) end
  instr['dusk']=function(s,n,e,i) s.push(toTime(fibaro:getValue(1,'duskHour'))) end
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
  instr['label'] = function(s,n,e,i) local nm,id = s.pop(),s.pop() s.push(fibaro:getValue(ID(id,i),format("ui.%s.value",nm))) end
  instr['slider'] = instr['label']
  instr['redaily'] = function(s,n,e,i) s.push(Rule.restartDaily(s.pop())) end
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
  instr['remote'] = function(s,n,ev) local e,u=s.pop(),s.pop(); Event.postRemote(u,e) s.push(true) end
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
          flags.expired,flags.timer=true,nil; 
          e.rule.start(e.rule._event) 
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
    local status,stat,res = spcall(function() 
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
    if Util.isTEvent(obj) then 
      local ce = ScriptEngine.eval2({code=ScriptCompiler.compile(obj)})
      local ep = copy(ce); Event._compilePattern(ep)
      obj[1],obj[2],obj[3]='%eventmatch',ep,ce; 
--    elseif type(obj)=='table' and (obj[1]=='%and' or obj[1]=='%or' or obj[1]=='trueFor') then remapEvents(obj[2]); remapEvents(obj[3])  end
    elseif type(obj)=='table' then map(function(e) remapEvents(e) end,obj,2) end
  end

  local function trimRule(str)
    local str2 = str:sub(1,(str:find("\n") or math.min(#str,_RULELOGLENGTH)+1)-1)
    if #str2 < #str then str2=str2.."..." end
    return str2
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
      events[#events+1] = Event.event(event,action,{doc=src,log=log})
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
        events[#events+1]=Event.event(event,action,{doc=src,log=log})
        self.recalcDailys({dailys=sdaily,src=src},true)
        local reaction = function() self.recalcDailys(res) end
        for _,tr in ipairs(triggers) do -- Add triggers to reschedule dailys when variables change...
          if tr.type=='global' then Event.event(tr,reaction,{doc=src})  end
        end
      end
      if not dailyFlag and #triggers > 0 then -- id/glob trigger or events
        for _,tr in ipairs(triggers) do 
          if tr.propertyName~='<nop>' then events[#events+1]=Event.event(tr,action,{doc=src,log=log}) triggers2[#triggers2+1]=tr end
        end
      end
    end
    res=#events>1 and Event._mkCombEvent(src,action,src,events) or events[1]
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
    Util.validateChars(escript,"Invalid (multi-byte) char in rule:%s")
    if log == nil then log = {} elseif log==true then log={print=true} end
    if log.print==nil then log.print=true end
    local status,res,ctx
    status, res, ctx = spcall(function() 
        local expr = self.macroSubs(escript)
        if not log.cont then 
          log.cont=function(res)
            log.cont=nil
            local name,r
            if not log.print then return res end
            if Util.isRule(res) then name,r=res.src,"OK" else name,r=escript,res end
            Log(LOG.LOG,"%s = %s",name,tojson(r)) 
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
  Event.schedule("n/00:00",function(env) for _,d in ipairs(dailysTab) do self.recalcDailys(d.rule) end end)

  return self
end

------- Extra ER setup ------------------------------
function extraERSetup()
  local copy,member,equal,format=Util.copy,Util.member,Util.equal,string.format
  local function makeDateInstr(f)
    return function(s,n,e,i)
      local ts,cache = s.pop(),e.rule.cache
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
        env.p.data.timestamp=os.time()
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

--- SceneActivation constants
  Util.defvar('S1',Util.S1)
  Util.defvar('S2',Util.S2)
  Util.defvar('catch',math.huge)
  Util.defvar("defvars",Util.defvars)
  Util.defvar("mapvars",Util.reverseMapDef)
  if _EMULATED then Util.getWeekNumber = _System.getWeekNumber
  else Util.getWeekNumber = function(tm) return tonumber(os.date("%V",tm)) end end
  function Util.findScenes(str)
    local res = {}
    for _,s1 in ipairs(api.get("/scenes")) do
      if s1.isLua and s1.id~=__fibaroSceneId and s1.runningInstances > 0 then
        local s2=api.get("/scenes/"..s1.id)
        if s2==nil or s2.lua==nil then Log(LOG.ERROR,"Scene missing: %s",s1.id)
        elseif s2.lua:match(str) then res[#res+1]=s1.id end
      end
    end
    return res
  end
-- Sunset/sunrise patch
  local _SUNTIMEDAY = nil
  local _SUNTIMEVALUES = {sunsetHour=nil,sunriseHour=nil,dawnHour=nil,duskHour=nil}
  Event._registerID(1,nil,function(obj,id,prop) 
      local s = _SUNTIMEVALUES
      if prop=='sunsetHour' or prop=='sunriseHour' or prop=='dawnHour' or prop=='duskHour' then
        local day = os.date("*t").day
        if day ~= _SUNTIMEDAY then
          _SUNTIMEDAY = day
          s.sunriseHour,s.sunsetHour,s.dawnHour,s.duskHour=Util.sunCalc()
        end
        return _SUNTIMEVALUES[prop]
      else return fibaro._get(obj,id,prop) end
    end)

--------- Telegram support ---------

  Telegram={ _interval=2, _http=netSync.HTTPClient(), _users=nil, _userVar="TelegramUsers", _persist=true }
  function Telegram._request(key,cmd,payload,cont)
    local url = key..cmd
    payload = payload and json.encode(payload)
    Telegram._http:request(url,{options = {
          headers = {['Accept']='application/json',['Content-Type']='application/json'},
          data = payload, timeout=2000, checkCertificate = false, method = 'POST'},
        error = function(status) if status~= "Operation canceled" then Log(LOG.ERROR,"Telegram error: %s",json.encode(status)) end end,
        success = function(status) 
          local data = json.decode(status.data)
          if status.status ~= 200 and data.ok==false then
            Log(LOG.ERROR,"Telegram error: %s, %s",data.error_code,data.description)
          elseif cont then cont(data) end 
        end,
      })
  end
  function Telegram._recordUser(username,chatID,bot)
    local u = username..":"..chatID..":"..bot
    local names = Telegram._users
    for _,u2 in ipairs(names) do if u==u2 then return end end
    names[#names+1]=u; Telegram._persistFlag = true
  end
  function Telegram._loadUsers()
    if fibaro:getGlobalModificationTime(Telegram._userVar)==nil then
      api.post("/globalVariables/",{name=Telegram._userVar,value="{}"});
    end
    local users = fibaro:getGlobal(Telegram._userVar)
    if users == nil or users == "" then users = "{}" end 
    Telegram._users = json.decode(users)
  end
  function Telegram._findUser(key1,key2) -- user / chatID / chatID,Bot_key
    if key2==nil then
      local p
      if tonumber(key1) then p="(.-):("..key1.."):(.*)$" else p="("..key1.."):(%d+):(.*)$" end
      for _,user in ipairs(Telegram._users or {}) do
        local u,c,b = user:match(p)
        if u then return {tonumber(c),b} end
      end
      return nil
    else return {key1,key2} end
  end
  function Telegram._flush()
    if Telegram._persistFlag == true and Telegram._persist then 
      fibaro:setGlobal(Telegram._userVar,json.encode(Telegram._users)) 
      Telegram._persistFlag=false
    end
  end
  function Telegram.bot(key,tag)
    tag = tag or "Telegram"
    Telegram._botkey = key
    if not Telegram._users then Telegram._loadUsers() end
    local url,lastID,msg = "https://api.telegram.org/bot"..key.."/",1,nil
    local function loop()
      Telegram._request(url,"getUpdates",{offset=lastID+1},
        function(messages)
          for _,m in ipairs(messages.result) do
            lastID,msg=m.update_id,m.message
            Telegram._recordUser(msg.from.username,msg.chat.id,key)
            Event.post({type=tag,user=msg.from.username,text=msg.text,id={msg.chat.id,key},info=msg.chat,_sh=true})
          end
        end)
      Telegram._flush()
      setTimeout(loop,Telegram._interval*1000)
    end
    loop()
  end

  function Telegram.msg(id,text,keyboard)
    if not Telegram._users then Telegram._loadUsers() end
    local id2 = type(id)=='table' and id or Telegram._findUser(table.unpack(type(id)=='table' and id or {id}))
    _assert(id2,"No user with name "..tojson(id))
    Telegram._request("https://api.telegram.org/bot"..id2[2].."/","sendMessage",{chat_id=id2[1],text=text,reply_markup=keyboard},
      function(msgs) local m = msgs.result; Telegram._recordUser(m.chat.username,m.chat.id,id2[2]); Telegram._flush() end) 
  end

--------- Node-red support ---------

  Nodered = { _nrr = {}, _timeout = 4000, _last=nil }
  function Nodered.connect(url) 
    local self = { _url = url, _http=netSync.HTTPClient("Nodered") }
    function self.post(event,sync)
      _assert(Util.isEvent(event),"Arg to nodered.msg is not an event")
      local tag, nrr = Util.gensym("NR"), Nodered._nrr
      event._transID = tag
      local params =  {options = {
          headers = {['Accept']='application/json',['Content-Type']='application/json'},
          data = json.encode(Util.encodePostEvent(event)), timeout=timeout or 2000, method = 'POST'},
        _logErr=true
      }
      self._http:request(self._url,params)
      if sync then
        nrr[tag]={}
        nrr[tag][1]=setTimeout(function() nrr[tag]=nil 
            error(format("No response from Node-red, '%s'",(tojson(event))))
          end,Nodered._timeout or _options['NODEREDTIMEOUT'])
        return {['<cont>']=function(cont) nrr[tag][2]=cont end}
      else return true end
    end
    Nodered._last = self
    return self
  end
  function Nodered.post(event,sync)
    _assert(Nodered._last,"Missing nodered URL - make Nodered.connect(<url>) at beginning of scene")
    return Nodered._last.post(event,sync)
  end
  Event.event({type='NODERED',value='$e'},
    function(env) local p,tag = env.p,env.event._transID
      if tag then
        local nrr = Nodered._nrr
        local cr = nrr[tag] or {}
        if cr[1] then clearTimeout(cr[1]) end
        if cr[2] then cr[2](p.e) else Event.post(p.e) end
        nrr[tag]=nil
      else Event.post(p.e) end
    end)

----------- Sonos speech/mp3

  Sonos = { vdID = 10, buttonID = 28, lang = 'en'}
  function Sonos._cmd(cmd)
    vol = vol or 30
    local _f = fibaro
    local _x ={root="x_sonos_object",load=function(b)local c=_f:getGlobalValue(b.root)if string.len(c)>0 then local d=json.decode(c)if d and type(d)=="table"then return d else _f:debug("Unable to process data, check variable")end else _f:debug("No data found!")end end,set=function(b,e,d)local f=b:load()if f[e]then for g,h in pairs(d)do f[e][g]=h end else f[e]=d end;_f:setGlobal(b.root,json.encode(f))end,get=function(b,e)local f=b:load()if f and type(f)=="table"then for g,h in pairs(f)do if tostring(g)==tostring(e or"")then return h end end end;return nil end}
    _x:set(tostring(Sonos.vdID), cmd)
    _f:call(Sonos.vdID, "pressButton", Sonos.buttonID)
  end

  function Sonos.mp3(file, vol) vol=vol or 30; Sonos._cmd({stream={stream=file, source="local", duration="auto", volume=vol}}) end
  function Sonos.speak(message, vol) vol=vol or 30; Sonos._cmd({tts={message=message, duration='auto', language=sonos.lang, volume=vol}}) end

--------- Auto patch ---------------
  function Util.checkVersion(vers)
    local req = net.HTTPClient()
    req:request("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/VERSION.json",
      {options = {method = 'GET', checkCertificate = false, timeout=20000},
        success=function(data)
          if data.status == 200 then
            local v = json.decode(data.data)
            v = v[_EVENTRUNNERSRCPATH]
            if vers then v = v.scenes[vers] end
            if v.version ~= _version or v.fix ~= _fix then
              Event.post({type='ER_version',version=v.version,fix=v.fix or "", _sh=true})
            end
          end
        end})
  end

  local _EVENTRUNNERDELIMETER = "%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%- EventModel %- Don't change! "

  function Util.patchEventRunner(newSrc)
    if newSrc == nil then
      local req = net.HTTPClient()
      req:request("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/".._EVENTRUNNERSRCPATH,
        {options = {method = 'GET', checkCertificate = false, timeout=20000},
          success=function(data)
            if data.status == 200 then
              local src = data.data
              Util.patchEventRunner(src)
            end
          end,
          error=function(status) Log(LOG.LOG,"Err:Get src code from Github: %s",status) end
        })
    else
      local oldSrc,scene="",nil
      if __fullFileName then
        local f = io.open(__fullFileName)
        if not f then return end
        oldSrc = f:read("*all")
      else scene = api.get("/scenes/"..__fibaroSceneId); oldSrc=scene.lua end
      local obp = oldSrc:find(_EVENTRUNNERDELIMETER)
      oldSrc = oldSrc:sub(1,obp-1)
      local nbp = newSrc:find(_EVENTRUNNERDELIMETER)
      local nbody = newSrc:sub(nbp)
      oldSrc = oldSrc:gsub("(_version,_fix = .-\n)",newSrc:match("(_version,_fix = .-\n)"))
      Log(LOG.LOG,"Patching scene to latest version")
      if __fullFileName then
        local f = io.open(__fullFileName, "w")
        io.output(f)
        io.write(oldSrc..nbody)
        io.close(f)
      else scene.lua=oldSrc..nbody; api.put("/scenes/"..__fibaroSceneId,scene) end
    end
  end

-- Ping / publish / subscribe / & emulator support
  Event._dir,Event._rScenes,Event._subs,Event._stats = {},{},{},{}
  Event.ANNOUNCE,Event.SUB = '%%ANNOUNCE%%','%%SUB%%' 
  Event.event({type=Event.PING},function(env) local e=copy(env.event);e.type=Event.PONG; Event.postRemote(e._from,e) end)

  local function isRunning(id) 
    if _EMULATED then id = math.abs(id) end
    return fibaro:countScenes(id)>0 
  end

  Event.event({{type='autostart'},{type='other'}},
    function(env)
      setTimeout(function() -- Do this after startup so triggers don't pile up
          local event = {type=Event.ANNOUNCE, subs=#Event._subs>0 and Event._subs or nil}
          for _,id in ipairs(Util.findScenes(gEventRunnerKey)) do 
            if isRunning(id) then
              Debug(_debugFlags.pubsub,"Announce to ID:%s %s",id,tojson(env.event.subs)); Event._rScenes[id]=true; Event.postRemote(id,event) 
            end
          end
        end,2000)
    end)

  Event.event({type=Event.ANNOUNCE},function(env)
      local id = env.event._from
      if _EMULATED then id = math.abs(id) end
      Debug(_debugFlags.pubsub,"Announce from ID:%s %s",id,env.event.subs and tojson(env.event.subs) or "")
      Event._rScenes[id]=true;
      if #Event._subs>0 then Event.postRemote(id,{type=Event.SUB, event=Event._subs}) end
      for _,e in ipairs(Event._dir) do for i,id2 in ipairs(e.ids) do if id==id2 then table.remove(e.ids,i); break; end end end
      if env.event.subs then Event.post({type=Event.SUB, event=env.event.subs, _from=id}) end
    end)

  function Event.sendScene(id,event) if Event._rScenes[id] and isRunning(id) then Event.postRemote(id,event) else Event._rScenes[id]=false end end
  function Event.sendAllScenes(event) for id,_ in pairs(Event._rScenes) do Event.sendScene(id,event) end end
  function Event.subscribe(event,h) 
    Event._subs[#Event._subs+1]=event; Event.sendAllScenes({type=Event.SUB, event=event}) 
    if h then Event.event(event,h) end
  end
  function Event.publish(event,stat)
    if stat then Event._stats[#Event._stats+1]=event end
    for _,e in ipairs(Event._dir) do
      if Event._match(e.pattern,event) then for _,id in ipairs(e.ids) do Event.sendScene(id,event) end end
    end
  end

  Event.event({type=Event.SUB},
    function(env)
      local id = env.event._from
      if _EMULATED then id = math.abs(id) end
      Debug(_debugFlags.pubsub,"Subcribe from ID:%s %s",id,tojson(env.event.event))
      for _,event in ipairs(env.event.event[1] and env.event.event or {env.event.event}) do
        local seen = false
        for _,e in ipairs(Event._dir) do
          if equal(e.event,event) then seen=true; if not member(id,e.ids) then e.ids[#e.ids+1]=id end; break; end
        end
        if not seen then
          local pattern = copy(event); Event._compilePattern(pattern)
          Event._dir[#Event._dir+1]={event=event,ids={id},pattern=pattern}
          for _,se in ipairs(Event._stats) do
            if Event._match(pattern,se) then Event.sendScene(id,se) end
          end
        end
      end
    end)
end

------- Virtual device creation support ---------------------------------
function makeVDevSupport()
  local self = {}
  local ip, port = "127.0.0.1",80
  if _EMULATED then ip,port=_System.ipAdress,_System.port end
  local function CODE(lbl,tag) 
    return string.format(
[[local sceneID,label,tag=%s,'%s','%s'
  local VDID=fibaro:getSelfId()
  local val = fibaro:getValue(VDID,"ui.%s.value") or ""
  local event = {type='VD', label=label,value=val, tag=tag}
  local data = {urlencode(json.encode(event))}
  if sceneID > 0 then
   fibaro:debug("Calling scene "..sceneID)
   fibaro:startScene(sceneID,data)
else
  local HC2 = Net.FHttp('%s',%s)
  fibaro:debug("Calling emulator, sceneID "..sceneID)
  data = json.encode(data)
  local response ,status, err = HC2:POST('/trigger/'..sceneID,data);
  if tonumber(status) == 200 or tonumber(status) == 201 then
    fibaro:debug("success")
  else
    fibaro:debug("error "..err)
  end
end]],_EMULATED and -__fibaroSceneId or __fibaroSceneId,lbl,tag,lbl,ip,port)
  end

  local function makeElement(tag,id,name,lbl) return {id=id,lua=false,waitForResponse=false,caption=name,name=lbl,favourite=false,main=false} end
  local function makeButton(tag,id,name,lbl) 
    local b=makeElement(tag,id,name,lbl); b.empty,b.lua,b.msg,b.buttonIcon=false,true,CODE(lbl,tag),0; return b 
  end 
  local function makeSlider(tag,id,name,lbl,def) local b=makeButton(tag,id,name,lbl); b.empty,b.value=def,0; return b end 
  local eCreate={button=makeButton,slider=makeSlider,label=makeElement}

  local function createVD(vt,name,tag,vers,rows)
    local vp,tagv = vt.properties or {}, tag..":"..vers
    local vd = {id=vt.id or 42,name=name,roomID=vt.roomID or 0,type='virtual_device',visible=vt.visible or true,enabled=true,actions={pressButton=1,setSlider=2}}
    local id,ui,props = 1,{},{deviceIcon=vp.deviceIcon or 0,ip="",port=80,currentIcon=vt.currentIcon or "0",log="",logTemp="",mainLoop="t='"..tagv.."'",rows={}}
    for _,row in ipairs(rows) do
      local etype = row[1] -- type
      local r = {type = etype, elements = {}}
      for i=2,#row do 
        local e = row[i]
        r.elements[#r.elements+1]= eCreate[etype](tag,id,e[1],e[2],e[3]); id=id+1
        if etype=='label' then r.elements[#r.elements].favourite=e[4] or false end
        if etype~='button' then ui["ui."..e[2]..".value"] = e[3] or "" end
      end
      props.rows[#props.rows+1]=r
    end
    for k,v in pairs(ui) do props[k]=v end
    vd.properties = props
    return vd,ui
  end 

  local function createVDObject(vd) 
    local self = { id = vd.id, map={} }
    for _,r in ipairs(vd.properties.rows) do for _,e in ipairs(r.elements) do self.map[e.name]=e.id end end
    function self.idOf(lbl) return self.map[lbl] end
    function self.setValue(lbl,val) return fibaro:call(self.id,"setProperty","ui."..lbl..".value",val) end
    function self.getValue(lbl) return fibaro:getValue(self.id,"ui."..lbl..".value") end
    function self.setIcon(icon)
      local vd = api.get("/virtualDevices/"..self.id)
      vd.properties.deviceIcon=icon
      for _,row in pairs(vd.properties.rows) do 
        for _,element in pairs(row.elements) do element.buttonIcon=icon end 
      end 
      api.put("/virtualDevices/"..self.id,vd)
    end

    return self
  end

  local _CACHE_FIND_VIRTUALS = nil
  local function find(tag)
    local tmatch="^t='("..tag.."):(%d+)'"
    local vds = _CACHE_FIND_VIRTUALS or api.get("/virtualDevices")
    _CACHE_FIND_VIRTUALS = vds
    for _,vd1 in ipairs(vds) do 
      local tag,vers=(vd1.properties and vd1.properties.mainLoop or ""):match(tmatch)
      if tag then return tag,vers,vd1 end
    end
    return nil
  end

  function self.clearCache() _CACHE_FIND_VIRTUALS = nil end

  function self.remove(tag)
    local tag1,vers,vd = find(tag)
    if tag1 then api.delete("/virtualDevices/"..vd.id); Log(LOG.LOG,"VD %s deleted",vd.name) return vd 
    else Log(LOG.LOG,"VD tag:%s not found",tag) end
  end

  function self.define(name,tag,version,rows)
    version = tostring(version)
    local tag1,vers,vd,ui = find(tag)
    if tag1 then
      if vers==version then 
        Log(LOG.LOG,"VD %s already exist",name)
        return createVDObject(vd)
      end
    end
    if not vd then vd = api.post("/virtualDevices",{id=42,name=name}) Log(LOG.LOG,"VD %s created",name) else Log(LOG.LOG,"VD %s updated",name) end
    vd,ui=createVD(vd,name,tag,(version or 1),rows)
    api.put("/virtualDevices/"..vd.id,vd)
    for k,v in pairs(ui) do fibaro:call(vd.id,"setProperty",k,v) end
    return createVDObject(vd)
  end
  return self
end

------- Hue support ---------------------------------
function makeHueSupport()
  local format,Hue = string.format,nil

  local function makeHueHub(name,username,ip,cont)
    local lights,groups,scenes,sensors = {},{},{},{}
    local self = {lights=lights,groups=groups,scenes=scenes,sensors=sensors}
    local hubName,baseURL=name,"http://"..ip..":80/api/"..username.."/"
    local lightURL = baseURL.."lights/%s/state"
    local groupURL = baseURL.."groups/%s/action"
    local sensorURL = baseURL.."sensors/%s"

    local HTTP = netSync.HTTPClient()
    function self.request(url,cont,op,payload)
      op,payload = op or "GET", payload and json.encode(payload) or ""
      Debug(_debugFlags.hue,"Hue req:%s Payload:%s",url,payload)
      HTTP:request(url,{
          options = {headers={['Accept']='application/json',['Content-Type']='application/json'},
            data = payload, timeout=_HUETIMEOUT, method = op},
          error = function(status) Log(LOG.ERROR,"ERROR, Hue connection:%s, %s",tojson(status),url) end,
          success = function(status) 
            if cont then cont(json.decode(status.data)) end
          end
        })
    end

    function self._setState(hue,prop,val,upd)
      if type(prop)=='table' then 
        for k,v in pairs(prop) do self._setState(hue,k,v,upd) end
        return
      end
      local change,id = hue.state[prop]~=nil and hue.state[prop] ~= val, hue.fid
      hue.state[prop],hue.state['lastupdate']=val,os.time()
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

    local function match(t1,t2) if #t1~=#t2 then return false end; for i=1,#t1 do if t1[i]~=t2[i] then return false end end return true end

    function self.getFullState(f)
      self.request(baseURL,function(data)
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
      url=baseURL..format(url:match("(.-/)").."%s",sensor.id)
      sensor._filter = filter or sensor._filter or _defFilter
      if sensor._timer then clearTimeout(sensor._timer) sensor._timer=nil end
      if interval>0 then 
        Debug(_debugFlags.hue,"Monitoring URL:%s",url)
        local function poll() 
          self.request(url,function(state) self._setState(sensor,state.state) sensor._timer=setTimeout(poll,interval) end)
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
    Hue._initializing = Hue._initializing+1
    self.getFullState(function()
        Hue._initializing = Hue._initializing-1
      end)
    return self
  end

  local function makeHue()
    local self, devMap, hueNames = { hubs={}, _initializing=0 }, {}, {}
    local HTTP = net.HTTPClient()
    function self.isHue(id) return devMap[id] and devMap[id].hue end
    function self.name(n) return hueNames[n] end 

    function self.connect(user,ip,name)
      name = name or "Hue"
      if next(self.hubs)==nil then Log(LOG.LOG,"Hue system inited (experimental)") end
      _assert(self.hubs[name]==nil,"Hue hub name "..name.." already defined")
      self.hubs[name]=makeHueHub(name,user,ip)
    end

    function self.hueName(hue) --Hue1:SensorID=1
      local name,t,id=hue:match("(%w+):(%a+)=(%d+)")
      local dev = ({SensorID='sensors',LightID='lights',GroupID='groups'})[t]
      return name..":"..self.hubs[name][dev][tonumber(id)].name 
    end

    function self.dump() for _,h in pairs(self.hubs) do h.dump() end end
    local function find(name) -- find a Hue device in any of the connected Hue hubs we have, name is <hub>:<name>
      local hname,dname=name:match("(.*):(.*)")
      local hub = self.hubs[hname]
      return hub.lights[dname] or hub.groups[dname] or hub.sensors[dname],hname
    end

    local function hueCall(obj,id,...)
      local val,params=({...})[1],{select(2,...)}
      if Hue[val] then Hue[val](id,table.unpack(params)) end
    end
    local function hueGet(obj,id,...)
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
    end

    local mapIndex=10000 -- start mapping at deviceID 10000
    --devMap[deviceID] -> {hub, type, hue}
    function self.define(name,id) -- optional var
      if id ==nil then id = mapIndex; mapIndex=mapIndex+1 else id =tonumber(id) end
      if not name:match(":") then name="Hue:"..name end -- default to Hue:<name>
      hueNames[name]=id
      local hue,hub = find(name) 
      if hue then devMap[id] = {type=hue.type,hue=hue,hub=self.hubs[hub]}; hue.fid=id    
      else error("No Hue name:"..name) end
      Debug(_debugFlags.hue,"Hue device '%s' assigned deviceID %s",name,id)
      Event._registerID(id,hueCall,hueGet)
      return id
    end

    function self.monitor(name,interval,filter)
      if type(name)=='table' then Util.mapF(function(n) self.monitor(n,interval,filter) end, name) return end
      if type(name) == 'string' and not name:match(":") then name = "Hue:"..name end
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
      h.request(format(d.url,d.id),h.updateState,"PUT",{on=true}) h._setState(d,'on',true) 
    end
    function self.turnOff(id) local d,h=devMap[id].hue, devMap[id].hub
      h.request(format(d.url,d.id),h.updateState,"PUT",{on=false}) h._setState(d,'on',false) 
    end
    function self.setColor(id,r,g,b,w) local d,h,x,y=devMap[id].hue,devMap[id].hub,self.rgb2xy(r,g,b); 
      local pl={xy={x,y},bri=w and w/99*254}
      h.request(format(d.url,d.id),h.updateState,"PUT",pl) h._setState(d,pl) 
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
            h.request(format(url,d.id),nil,"PUT",payload)
          end
          return
        else payload=val end
      end
      if payload then h.request(format(d.url,d.id),h.updateState,"PUT",payload) h._setState(d,payload)
      else  Log(LOG.ERROR,"Hue setValue id:%s value:%s",id,val) end
    end
    return self
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

  Hue = makeHue() -- create global Hue object
  return Hue
end

-------- StartUp --------------------
function startUp(cont)
  if _type == 'other' and fibaro:countScenes() > 1 then 
    Log(LOG.LOG,"Scene already started. Try again?") 
    fibaro:abort()
  end

  if _type == 'autostart' or _type == 'other' then
    Log(LOG.WELCOME,string.format("%sEventRunner v%s %s",_sceneName and (_sceneName.." - " or ""),_version,_fix))

    local info = api.get("/settings/info")
    Log(LOG.LOG,"Fibaro software version: %s",info.currentVersion.version)
    Log(LOG.LOG,"HC2 uptime: %s hours",math.floor((os.time()-info.serverStatus)/3600))
    for i=1,_NUMBEROFBOXES do
      local mailbox = _MAILBOX.."_"..tostring(i)
      if not string.find(json.encode((api.get("/globalVariables/"))),"\""..mailbox.."\"") then
        api.post("/globalVariables/",{name=mailbox})
      end
      _MAILBOXES[i]=mailbox
    end

    Log(LOG.LOG,"Sunrise %s, Sunset %s",fibaro:getValue(1,'sunriseHour'),fibaro:getValue(1,'sunsetHour'))
    if _EMULATED then 
      Log(LOG.LOG,"Starting:%s %s",os.date("%x %X",os.time()),_System.speed()=="SPEED" and "(speeding)" or "") 
    end

    GC = 0
    local function setUpCont()
      Log(LOG.SYSTEM,"") Log(LOG.SYSTEM,"Loading rules")
      local status, res = pcall(function() return main() end)
      if not status then 
        Log(LOG.ERROR,"Error loading rules:%s",type(res)=='table' and table.concat(res,' ') or res) fibaro:abort() 
      end

      _trigger._sh = true
      Event.post(_trigger)
      Log(LOG.SYSTEM,"") Log(LOG.SYSTEM,"Scene running")
      collectgarbage("collect") GC=collectgarbage("count")
    end

    if not _EMULATED then
      for _,mb in ipairs(_MAILBOXES) do fibaro:setGlobal(mb,"") end -- clear mailboxes
      eventConsumer()  -- start polling mailbox
    end
    if cont then cont(setUpCont) else setUpCont() end
  end
end
-------- Init ---------------------------
Util           = makeUtils()
tojson         = Util.prettyJson
toTime         = Util.toTime
netSync        = Util.netSync
LOG            = Util.LOG
coroutine      = Util.coroutine
Event          = makeEventManager()
ScriptCompiler = makeEventScriptCompiler and makeEventScriptCompiler(makeEventScriptParser())
ScriptEngine   = makeEventScriptRuntime and makeEventScriptRuntime()
Rule           = makeEventScriptRuleCompiler and makeEventScriptRuleCompiler() 
VDev           = makeVDevSupport and makeVDevSupport()
Hue            = makeHueSupport()
extraERSetup()

if HueSetup then 
  local function hue(cont)
    HueSetup()
    local now = os.time()
    local function waitFor()
      if Hue._initializing > 0 then
        if os.time()-now > 5 then
          Log(LOG.ERROR,"HueSetup takes too long time")
          cont()
        else
          setTimeout(waitFor,500)
        end
      else
        cont()
      end
    end
    waitFor()
  end
  startUp(hue)
else
  startUp()
end

