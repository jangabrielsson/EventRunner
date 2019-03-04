--[[
%% properties
%% events
%% globals
%% autostart
--]]

--[[
-- EventRunnerLite. Single scene instance framework
-- Copyright 2018 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_version,_fix = "1.15","fix3"  -- Feb 21, 2019 
_sceneName = "iOSLocator"
osTime = os.time
osDate = os.date
_REMOTE=true
_SPEEDTIME=false
_debugFlags = { post=true,invoke=false,fibaroStart=true,triggers=false,timers=false,fibaro=true,fibaroGet=false }
if dofile then dofile("EventRunnerDebug.lua") end -- Support for running off-line on PC/Mac

_deviceTable = 456         -- name of HomeTable global

local _test = false                -- use local HomeTable variable instead of fibaro global
local homeLatitude,homeLongitude  -- set to first place in HomeTable.places list

HomeTable = [[
{"scenes":{
    "iOSLocator":{"id":11,"send":["iOSClient"]},
    "iOSClient":{"id":9,"send":{}},
  },
"places":[
    {"longitude":17.9876023512,"dist":0.6,"latitude":60.7879477,"name":"Home"},
    {"longitude":17.955049,"dist":0.8,"latitude":59.405818,"name":"Ericsson"},
    {"longitude":18.080638,"dist":0.8,"latitude":59.52869,"name":"Vallentuna"},
    {"longitude":17.648488,"dist":0.8,"latitude":59.840704,"name":"Polacksbacken"},
    {"longitude":17.5951,"dist":0.8,"latitude":59.850153,"name":"Flogsta"},
    {"longitude":18.120588,"dist":0.5,"latitude":59.303781,"name":"Rytmus"}
  ],
"users":{
    "daniela":{"phone":777,"icloud":{"pwd":"XXXX","user":"XXX@XXX.com"},"name":"Daniela"},
    "jan":{"phone":411,"icloud":{"pwd":"XXXX","user":"XXX@XXX.com"},"name":"Jan"},
    "tim":{"phone":888,"icloud":{"pwd":"XXXXX","user":"XXX@XXX.com"},"name":"Tim"},
    "max":{"phone":888,"icloud":{"pwd":"XXXXX","user":"XXX@XXX.com"},"name":"Max"}
  },
}
]]
if dofile then dofile("iOScredentials.lua") end

function main()

  INTERVAL = 90 -- check every 90s
  local nameOfHome = "Home"
  local whereIsUser = {}
  local devicePattern = "iPhone"
  local extrapolling = 4000
  local conf
  locations = {}
  homeFlag = false

  function readConfigurationData()
    if type(_deviceTable)=='number' then
      return json.decode(api.get("/scenes/".._deviceTable).lua)
    else
      return json.decode(_test and HomeTable or fibaro:getGlobalValue(_deviceTable))
    end
  end

  function distance(lat1, lon1, lat2, lon2)
    local dlat = math.rad(lat2-lat1)
    local dlon = math.rad(lon2-lon1)
    local sin_dlat = math.sin(dlat/2)
    local sin_dlon = math.sin(dlon/2)
    local a = sin_dlat * sin_dlat + math.cos(math.rad(lat1)) * math.cos(math.rad(lat2)) * sin_dlon * sin_dlon
    local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    local d = 6378 * c
    return d
  end

  function enc(data)
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x) 
            local r,b='',x:byte()
            for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
            return r;
          end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
          if (#x < 6) then return '' end
          local c=0
          for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
          return b:sub(c+1,c+1)
        end)..({ '', '==', '=' })[#data%3+1])
  end

  function getIOSDeviceNextStage(nextStage,username,headers,pollingextra)
    pollingextra = pollingextra or 0
    HTTP:request("https://" .. nextStage .. "/fmipservice/device/" .. username .."/initClient",{
        options = { headers = headers, data = '', checkCertificate = false, method = 'POST', timeout = 20000 },
        error = function(status)
          Debug(true,"Error getting NextStage data:"..status)
        end,
        success = function(status)
          local output = json.decode(status.data,{statusCode="444"})
          --Debug("iCloud Response:"..status.data)
          if (output.statusCode=="200") then			
            if (pollingextra==0) then
              listDevices(output.content)
            else
              Debug(2,"Waiting for NextStage extra polling")
              fibaro:sleep(extrapolling)	
              getIOSDeviceNextStage(nextStage,username,headers,0)
            end
          end
          Debug(true,"Bad response from NextStage:" .. json.encode(status) )	
        end})
  end

  _format = string.format

  Event.event({type='readConfig'},
    function(env)
      iUsers = {}
      conf = readConfigurationData()
      if conf  == nil or not conf.users then 
        Debug(true,"Missing configuration data, HomeTable='%s'",tojson(conf))
        fibaro:abort()
      end
      if conf.places then
        homeLatitude=conf.places[1].latitude
        homeLongitude=conf.places[1].longitude
      else
        homeLatitude = fibaro:getValue(2, "Latitude")
        homeLongitude = fibaro:getValue(2, "Longitude")
      end
      for _,v in pairs(conf.users) do if v.icloud then v.icloud.name = v.name iUsers[#iUsers+1] = v.icloud end end
      Debug(true,"Configuration data:")
      for _,p in ipairs(iUsers) do Debug(true,"User:%s",p.name) end
      for _,p in ipairs(conf.places) do 
        Debug(true,"Place:%s",p.name) 
        if p.name==nameOfHome then 
          homeLatitude=p.latitude
          homeLongitude=p.longitude
        end
      end
    end)

  Event.event({type='location_upd'},
    function(env)
      local event = env.event
      local loc = event.result.location
      if not loc then return end
      for _,v in ipairs(conf.places) do
        local d = distance(loc.latitude,loc.longitude,v.latitude,v.longitude)
        if d < v.dist then 
          Event.post({type='checkPresence', user=event.user, place=v.name, dist=d, _sh=true})
          return
        end
      end
      Event.post({type='checkPresence', user=event.user, place='away', dist=event.result.distance, _sh=true})
    end)

  Event.event({type='deviceMap'},
    function(env)
      local event = env.event
      local dm = event.data  
      if dm ==nil then return end
      -- Get the list of all iDevices in the iCloud account
      local result = {}
      for key,value in pairs(dm) do
        local loc = value.location
        if value.name:match(devicePattern) and loc and type(loc) == 'table' then
          local d = distance(loc.latitude,loc.longitude,homeLatitude,homeLongitude)
          result[#result+1] = {device=value.name, distance=d, location=loc}
        end
      end
      if #result == 1 then result = result[1] end
      --Log(LOG.LOG,"%s LOC:%s",env.p.user,json.encode(result))
      Event.post({type='location_upd', user=event.user, result=result, _sh=true})
    end)

  Event.event({type='getIOSdevices'}, --, user='$user', name = '$name', pwd='$pwd'},
    function(env)
      local event = env.event
      --Debug(true,"getIOSdevices for:%s",event.user)
      pollingextra = event.polling or 0

      HTTP = net.HTTPClient()

      local headers = {
        ["Authorization"]="Basic ".. enc(event.user..":"..event.pwd), 
        ["Content-Type"] = "application/json; charset=utf-8",
        ["X-Apple-Find-Api-Ver"] = "2.0",
        ["X-Apple-Authscheme"] = "UserIdGuest",
        ["X-Apple-Realm-Support"] = "1.0",
        ["User-agent"] = "Find iPhone/1.3 MeKit (iPad: iPhone OS/4.2.1)",
        ["X-Client-Name"]= "iPad",
        ["X-Client-UUID"]= "0cf3dc501ff812adb0b202baed4f37274b210853",
        ["Accept-Language"]= "en-us",
        ["Connection"]= "keep-alive"}

      HTTP:request("https://fmipmobile.icloud.com/fmipservice/device/" .. event.user .."/initClient",{
          options = {
            headers = headers,
            data = '',
            checkCertificate = false,
            method = 'POST', 
            timeout = 20000
          },
          error = function(status) 
            Event.post({type='error', msg=_format("Failed calling FindMyiPhone service for %s",event.user)})
          end,
          success = function(status)
            if (status.status==330) then
              local nextStage="fmipmobile.icloud.com" --status.headers["x-apple-mme-host"]
              Debug(2,"NextStage")
              getIOSDeviceNextStage(nextStage,event.user,headers,pollingextra)
            elseif (status.status==200) then
              --Debug(true,"Data:%s",json.encode(status.data))
              Event.post({type='deviceMap', user=event.name, data=json.decode(status.data).content, _sh=true})
            else
              Event.post({type='error', msg=_format("Access denied for %s :%s",event.user,json.encode(status))})
            end
          end})
    end)

  Event.event({type='checkPresence'},
    function(env)
      local event = env.event
      if whereIsUser[event.user] ~= event.place then  -- user at new place
        whereIsUser[event.user] = event.place
        Debug(true,"%s is at %s",event.user,event.place)
        local ev = {type='location', user=event.user, place=event.place, dist=event.dist, ios=true}
        local evs = json.encode(ev)
        for _,v in pairs(conf.scenes.iOSLocator.send) do
          Debug(true,"Sending %s to scene %s",evs,conf.scenes[v].id)
          Event.postRemote(conf.scenes[v].id,ev)
        end
        Event.publish(ev) -- and publish to subscribers
      end

      local user,place,ev=event.user,event.place 
      locations[user]=place
      local home = false
      local who = {}
      for w,p in pairs(locations) do 
        if p == nameOfHome then home=true; who[#who+1]=w end
      end
      if home and homeFlag ~= true then 
        homeFlag = true
        ev={type='presence', state='home', who=table.concat(who,','), ios=true}
      elseif #locations == #iUsers then
        if homeFlag ~= false then
          homeFlag = false
          ev={type='presence', state='allaway', ios=true}
        end
      end
      if ev then
        local evs = json.encode(ev)
        for _,v in pairs(conf.scenes.iOSLocator.send) do
          Debug(true,"Sending %s to scene %s",evs,conf.scenes[v].id)
          Event.postRemote(conf.scenes[v].id,ev)
        end
        Event.publish(ev) -- and to all subscribers
      end
    end)

  Event.event({type='getLocations'}, -- Resend all locations if scene asks for it
    function(env)
      local event=env.event
      Debug(true,"Got remote location request from scene:%s",event._from)
      for u,p in pairs(whereIsUser) do
        if u and p then
          Debug(true,"User:%s Position:%s",u,p)
          Event.postRemote(event._from,{type='location', user=u, place=p, ios=true})
        end
      end
    end)

  Event.event({type='poll'},
    function(env)
      local event=env.event
      local index = event.index
      local user = iUsers[(index % #iUsers)+1]
      Event.post({type='getIOSdevices', user=user.user, pwd=user.pwd, name=user.name})
      Event.post({type='poll',index=index+1},osTime()+math.floor(0.5+INTERVAL/#iUsers)) -- INTERVAL=60 => check every minute
    end)

  Event.event({type='error'},
    function(env)
      local event=env.event
      Debug(true,"Error %s",event.msg)
    end)

  Event.event({{type='autostart'},{type='other'}},
    function(env)
      local event=env.event
      Event.post({type='readConfig'})
      Event.post({type='poll',index=1})
    end)

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
gEventSupervisorKey="9t8232395ue734r327fh3"

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
  self.PING, self.PONG = '%%PING%%', '%%PONG%%'
  self.PUBLISH, self.SUBSCRIBE = '%%PUBLISH%%', '%%SUBSCRIBE%%'
  self.REGISTER, self.DIRECTORY = '%%REGISTER%%', '%%DIRECTORY%%'
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
      local id2,args = type(id) == 'number' and Util.reverseVar and Util.reverseVar(id) or '"'..(id or "<ID>")..'"',{...}
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
interceptFib("startScene","fibaroStart",
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

function Util.findScenes(str)
  local res = {}
  for _,s1 in ipairs(api.get("/scenes")) do
    if s1.isLua and s1.id~=__fibaroSceneId then
      local s2=api.get("/scenes/"..s1.id)
      if s2.lua:match(str) then res[#res+1]=s1.id end
    end
  end
  return res
end

Util.getIDfromEvent={ CentralSceneEvent=function(d) return d.deviceId end,AccessControlEvent=function(d) return d.id end }
Util.getIDfromTrigger={
  property=function(e) return e.deviceID end,
  event=function(e) return e.event and Util.getIDfromEvent[e.event.type or ""](e.event.data) end
}

-- Ping / publish / subscribe
Event._dir,Event._rScenes,Event._subs,Event._stats = {},{},{},{}
Event.ANNOUNCE,Event.SUB = '%%ANNOUNCE%%','%%SUB%%' 
Event.event({type=Event.PING},function(env) e=_copy(env.event);e.type=Event.PONG; Event.postRemote(e._from,e) end)

function isRunning(id) return fibaro:countScenes(id)>0 end

Event.event({{type='autostart'},{type='other'}},
  function(env)
    local event = {type=Event.ANNOUNCE, subs=#Event._subs>0 and Event._subs or nil}
    for _,id in ipairs(Util.findScenes(gEventRunnerKey)) do 
      if isRunning(id) then Debug(_debugFlags.pubsub,"Found ID:%s",id); Event._rScenes[id]=true; Event.postRemote(id,event) end
    end
  end)

Event.event({type=Event.ANNOUNCE},function(env)
    local id = env.event._from
    Debug(_debugFlags.pubsub,"Announce from ID:%s %s",id,tojson(env.event.subs))
    Event._rScenes[id]=true;
    if #Event._subs>0 then Event.postRemote(id,{type=Event.SUB, event=Event._subs}) end
    for _,e in ipairs(Event._dir) do for i,id2 in ipairs(e.ids) do if id==id2 then table.remove(e.ids,i); break; end end end
    if env.event.subs then Event.post({type=Event.SUB, event=env.event.subs, _from=id}) end
  end)

function Event.sendScene(id,event) if Event._rScenes[id] and isRunning(id) then Event.postRemote(id,event) else Event._rScenes[id]=false end end
function Event.sendAllScenes(event) for id,s in pairs(Event._rScenes) do Event.sendScene(id,event) end end
function Event.subscribe(event) Event._subs[#Event._subs+1]=event; Event.sendAllScenes({type=Event.SUB, event=event}) 
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
    Debug(_debugFlags.pubsub,"Subcribe from ID:%s %s",id,tojson(env.event.event))
    for _,event in ipairs(env.event.event[1] and env.event.event or {env.event.event}) do
      local seen = false
      for _,e in ipairs(Event._dir) do
        if _equal(e.event) and not Util.member(id,e.ids) then e.ids[#e.ids+1]=id; seen=true; break; end
      end
      if not seen then
        local pattern = _copy(event); Event._compilePattern(pattern)
        Event._dir[#Event._dir+1]={event=event,ids={id},pattern=pattern}
        for _,se in ipairs(Event._stats) do
          if Event._match(pattern,se) then Event.sendScene(id,se) end
        end
      end
    end
  end)

---------------------- Startup -----------------------------   
if _type == 'other' and fibaro:countScenes() > 1 then 
  Log(LOG.LOG,"Scene already started. Try again?") 
  fibaro:abort()
end
if _type == 'autostart' or _type == 'other' then
  Log(LOG.WELCOME,_format("%sEventRunner v%s",_sceneName and (_sceneName.." - " or ""),_version))
  Log(LOG.WELCOME,"Starting iOSLocator service")

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