--[[
%% properties
%% events
%% globals
%% autostart
--]]
-- Don't forget to declare triggers from devices in the header!!!
if dofile and not _EMULATED then _EMBEDDED={name="EventRunner",id=10} dofile("HC2.lua") end

_version,_fix  = "2.0","B4"  -- June 5, 2019 

_sceneName     = "iOSLocator"
nameOfHome = "Home"
_deviceTable   = "devicemap" -- Name of your HomeTable variable
_ruleLogLength = 80          -- Log message cut-off, defaults to 40
_HueHubs       = {}          -- Hue bridges, Ex. {{name='Hue',user=_HueUserName,ip=_HueIP}}
_NUMBEROFBOXES = 1           -- Number of mailboxes, increase if exceeding 10 instances...
EVENTRUNNERSRCPATH = "scenesER/ILocator.lua"

local _test = true                -- use local HomeTable variable instead of fibaro global
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

-- debug flags for various subsystems...
_debugFlags = { 
  post=true,invoke=false,triggers=true,dailys=true,timers=false,rule=false,ruleTrue=false,
  hue=false,msgTime=false
}

function main()

  INTERVAL = 90 -- check every 90s
  local whereIsUser = {}
  local devicePattern = "iPhone"
  local extrapolling = 4000
  local conf
  locations = {}
  homeFlag = false

  function readConfigurationData()
    if type(_deviceTable)=='number' and not _test then
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

  function getIOSDeviceNextStage(nextStage,username,name,headers,pollingextra)
    pollingextra = pollingextra or 0
    HTTP:request("https://" .. nextStage .. "/fmipservice/device/" .. username .."/initClient",{
        options = { headers = headers, data = '', checkCertificate = false, method = 'POST', timeout = 20000 },
        error = function(status)
          Debug(true,"Error getting NextStage data:%s",status or "<unknown error>")
        end,
        success = function(status)
          local stat,res = pcall(function()
              --Debug(true,"iCloud Response:%s",status.status)
              if (status.status==200) then			
                if (pollingextra==0) then
                  local output = json.decode(status.data)
                  Event.post({type='deviceMap', user=username, data=output.content, _sh=true})
                  --listDevices(output.content)
                  return
                else
                  Debug(true,"Waiting for NextStage extra polling")
                  setTimeout(function() getIOSDeviceNextStage(nextStage,username,name,headers,0) end, extrapolling)
                  return
                end
              end
              Debug(true,"Bad response from NextStage:%s",json.encode(status) )	
            end)
          if not stat then Debug(true,"Crash NextStage:%s",res )	end
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
            local stat,res = pcall(function()
                if (status.status==330) then
                  --Debug(true,"330 Resp:%s",json.encode(status))
                  local nextStage="fmipmobile.icloud.com"  
                  for k,ns in pairs(status.headers) do if string.lower(k)=="x-apple-mme-host" then nextStage=ns; break  end end
                  Debug(true,"NextStage:%s",nextStage)
                  getIOSDeviceNextStage(nextStage,event.user,event.name,headers,pollingextra)
                elseif (status.status==200) then
                  --Debug(true,"Data:%s",json.encode(status.data))
                  Event.post({type='deviceMap', user=event.name, data=json.decode(status.data).content, _sh=true})
                else
                  Event.post({type='error', msg=_format("Access denied for %s :%s",event.user,json.encode(status))})
                end
              end)
            if not stat then Debug(true,"Crash getIOSdevices:%s",res ) end
          end
        })
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
      Debug(true,"Error %s",tojson(event))
    end)

  Event.event({{type='autostart'},{type='other'}},
    function(env)
      local event=env.event
      Event.post({type='readConfig'})
      Event.post({type='poll',index=1})
    end)

  Event.event({type='ER_version'},
    function(env)
      Log(LOG.LOG,'New IOSLocator version, v:%s, fix:%s',env.event.version,env.event.fix)
      Util.patchEventRunner()
    end)
  Event.schedule("t/06:00",function() Util.checkVersion("IOSLocator") end,{start=true})
  
end -- main()

------------------- EventModel - Don't change! --------------------  
Event = Event or {}
_STARTONTRIGGER = _STARTONTRIGGER or false
_NUMBEROFBOXES = _NUMBEROFBOXES or 1
_MAILBOXES={}
_MIDNIGHTADJUST = _MIDNIGHTADJUST or false
_emulator={ids={},adress=nil}
--_STARTLINE = _EMULATED and debug.getinfo(1).currentline or nil
local _supportedEvents = {property=true,global=true,event=true,remote=true}
local _trigger = fibaro:getSourceTrigger()
local _type, _source = _trigger.type, _trigger
local _MAILBOX = "MAILBOX"..__fibaroSceneId 
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
  if _debugFlags.msgTime then _trigger._timestamps={triggered={os.time(),time}} end
  if not _STARTONTRIGGER then
    if count == 1 then fibaro:debug("Aborting: Server not started yet"); fibaro:abort() end
  end
  if _EMULATED then -- If running in emulated mode, use shortcut to pass event to main instance
    local co,env = _System.getInstance(__fibaroSceneId,1) -- if we only could do this on the HC2...
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
  if _debugFlags.msgTime then _trigger._timestamps.posted={os.time(),os.clock()} event=json.encode(_trigger) end
  fibaro:setGlobal(mb,event) -- write msg
  if count>1  then fibaro:abort() end -- and exit
  _trigger.type,_type='other','other'
end

---------- Consumer - re-posting incoming triggers as internal events --------------------

local _CXCS=250
local _CXCST1,_CXCST2=os.clock()
local function _poll()
  _CXCS = math.min(2*(_CXCS+1),250)
  _CXCST2 = _CXCST1
  _CXCST1 = os.clock()
  if _CXCST1-_CXCST2 > 0.75 then Log(LOG.ERROR,"Slow mailbox watch:%ss",_CXCST1-_CXCST2) end
  for _,mb in ipairs(_MAILBOXES) do
    local l = fibaro:getGlobal(mb)
    if l and l ~= "" and l:sub(1,3) ~= '<@>' then -- Something in the mailbox
      fibaro:setGlobal(mb,"") -- clear mailbox
      Debug(_debugFlags.triggers,"Incoming event:%s",l)
      l = json.decode(l) l._sh=true
      if _debugFlags.msgTime then l._timestamps.received={os.time(),os.clock()} end
      setTimeout(function() Event.triggerHandler(l) end,5)-- and post it to our "main()"
      _CXCS=1
    end
  end
  setTimeout(_poll,_CXCS) -- check again
end

------------------------ Support functions -----------------
LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ULOG="Khaki", ERROR = "Tomato"}
_format = string.format
_ruleLogLength = _ruleLogLength or 80   -- Log message cut-off, defaults to 80
local _getIdProp = function(id,prop) return fibaro:getValue(id,prop) end
local _getGlobal = function(id) return fibaro:getGlobalValue(id) end

Util = Util or {}
tojson = json.encode
gEventRunnerKey="6w8562395ue734r437fg3"
gEventSupervisorKey="9t823239".."5ue734r327fh3"

if not _EMULATED then
-- Patch possibly buggy setTimeout - what is 1ms between friends...
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

local function _Msg(color,message,...)
  local args = type(... or 42) == 'function' and {(...)()} or {...}
  local tadj = _timeAdjust > 0 and osDate("(%X) ") or ""
  message = _format(message,table.unpack(args))
  fibaro:debug(_format('<span style="color:%s;">%s%s</span><br>', color, tadj, message))
  return message
end

if _System and _System._Msg then _Msg=_System._Msg end -- Get a better ZBS version of _Msg if running emulated 

local function protectMsg(...)
  local args = {...}
  local stat,res=pcall(function() return _Msg(table.unpack(args)) end)
  if not stat then error("Bad arguments to Log/Debug:"..tojson(args),2)
  else return res end
end

if not _timeAdjust then _timeAdjust = 0 end -- support for adjusting for hw time drift on HC2
osTime = function(arg) return arg and os.time(arg) or os.time()+_timeAdjust end
function Debug(flag,message,...) if flag then _Msg(LOG.DEBUG,message,...) end end
function Log(color,message,...) return protectMsg(color,message,...) end
local function _LINEFORMAT(line) return "" end
local function _LINE() return nil end
function osDate(f,t) t = t or osTime() return os.date(f,t) end

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
    ---Log(LOG.LOG,"DATE:%s",osDate("%c",time))
    ctx.src=ctx.src or tojson(e)
    if _debugFlags.post and not e._sh then Debug(true,"Posting %s at %s",tojson(e),osDate("%a %b %d %X",time)) end
    return {[self.TIMER]=setTimeout(function() self._handleEvent(e) end,1000*(time-osTime()))}
  end

  function self.cancel(t)
    _assert(isTimer(t) or t == nil,"Bad timer")
    if t then clearTimeout(t[self.TIMER]) end 
    return nil 
  end

  self.triggerHandler = self.post -- default handler for consumer

  local function httpPostEvent(url,payload, e)
    local HTTP = net.HTTPClient()
    payload=json.encode(payload)
    HTTP:request(url,{options = {
          headers = {['Accept']='application/json',['Content-Type']='application/json'},
          data = payload, timeout=2000, method = 'POST'},
        error = function(status) self.post({type='%postEvent%',status='fail', oe=e, _sh=true}) end,
        success = function(status) self.post({type='%postEvent%',status='success', oe=e, _sh=true}) end,
      })
  end

  function self.postRemote(sceneID, e) -- Post event to other scenes or node-red
    _assert(isEvent(e),"Bad event format")
    e._from = _EMULATED and -__fibaroSceneId or __fibaroSceneId
    local payload = encodeRemoteEvent(e)
    if type(sceneID)=='string' and sceneID:sub(1,4)=='http' then -- external http event (node-red)
      payload={args={payload[1]}}
      httpPostEvent(sceneID, payload, e)
    elseif not _EMULATED then                  -- On HC2
      if sceneID < 0 then    -- call emulator
        if not _emulator.adress then return end
        httpPostEvent(_emulator.adress.."trigger/"..sceneID,payload)
      else fibaro:startScene(sceneID,payload) end -- call other scene on HC2
    else -- on emulator
      fibaro:startScene(math.abs(sceneID),payload)
    end
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
    rm.start = function() self._invokeRule({rule=rm}) return rm end
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

  function self.event(e,action,doc,ctx,front) -- define rules - event template + action
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
      if _equal(e,rs[1][self.RULE]) then if front then table.insert(rs,1,rule) else rs[#rs+1] = rule end fn = false break end
    end
    if fn then if front then table.insert(rules,1,{rule}) else rules[#rules+1] = {rule} end end
    rule.enable = function() rule._disabled = nil return rule end
    rule.disable = function() rule._disabled = true return rule end
    rule.start = function() self._invokeRule({rule=rule}) return rule end
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

  function self._invokeRule(env)
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
    local env, _match = {event = e, p={}}, self._match
    local hasKeys = fromHash[e.type] and fromHash[e.type](e) or {e.type}
    for _,hashKey in ipairs(hasKeys) do
      for _,rules in ipairs(_handlers[hashKey] or {}) do -- Check all rules of 'type'
        local match = _match(rules[1][self.RULE],e)
        if match then
          if next(match) then for k,v in pairs(match) do env.p[k]=v match[k]={v} end env.context = match end
          for _,rule in ipairs(rules) do 
            if not rule._disabled then env.rule = rule self._invokeRule(env) end
          end
        end
      end
    end
  end

-- Extended fibaro:* commands, toggle, setValue, User defined device IDs, > 10000
  fibaro._idMap={}
  fibaro._call,fibaro._get,fibaro._getValue,fibaro._actions=fibaro.call,fibaro.get,fibaro.getValue,{}
  local lastID,orgCall = {},fibaro.call
  function self.lastManual(id)
    lastID[id] = lastID[id] or {time=0}
    if lastID[id].script then return -1 else return osTime()-lastID[id].time end
  end
  function self.trackManual(id,value)
    lastID[id] = lastID[id] or {time=0}
    if lastID[id].script==nil or osTime()-lastID[id].time>1 then lastID[id]={time=osTime()} end -- Update last manual
  end
  function self._registerID(id,call,get) fibaro._idMap[id]={call=call,get=get} end

  function fibaro.call(obj,id,call,...)
    id = tonumber(id); if not id then error("deviceID not a number",2) end
    if ({turnOff=true,turnOn=true,on=true,off=true,setValue=true})[call] then lastID[id]={script=true,time=osTime()} end
    if call=='toggle' then 
      return fibaro.call(obj,id,fibaro:getValue(id,"value")>"0" and "turnOff" or "turnOn") 
    end

    if fibaro._idMap[id] then return fibaro._idMap[id].call(obj,id,call,...)
    elseif call=='setValue' then
      fibaro._actions[id] = fibaro._actions[id] or  api.get("/devices/"..id).actions
      if (not fibaro._actions[id].setValue) and fibaro._actions[id].turnOn then
        return fibaro._call(obj,id,tonumber(({...})[1]) > 0 and "turnOn" or "turnOff")
      end
    end 
    return fibaro._call(obj,id,call,...)
  end 

  function fibaro.get(obj,id,...) 
    id = tonumber(id); if not id then error("deviceID not a number",2) end
    if fibaro._idMap[id] then return fibaro._idMap[id].get(obj,id,...) else return fibaro._get(obj,id,...) end
  end

  function fibaro.getValue(obj,id,...) 
    id = tonumber(id); if not id then error("deviceID not a number",2) end
    if fibaro._idMap[id] then return (fibaro._idMap[id].get(obj,id,...)) else return (fibaro._getValue(obj,id,...)) end
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
        return table.unpack(res)
      else
        local astr=(id~=nil and Util.reverseVar(id).."," or "")..json.encode(args):sub(2,-2)
        error(_format("fibaro:%s(%s),%s",name,astr,res),3)
      end
    end
  end

  if not _EMULATED then  -- Emulator logs fibaro:* calls for us
    local maps = {
      {"call","fcall"},{"setGlobal","fglobal"},{"getGlobal","fglobal"},{"getGlobalValue","fglobal"},
      {"get","fget"},{"getValue","fget"},{"killScenes","fother"},{"abort","fother"},
      {"sleep","fother",function(id,args,res) 
          Debug(true,"fibaro:sleep(%s) until %s",id,osDate("%X",osTime()+math.floor(0.5+id/1000))) 
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

function Util.eventTimestamp(e,mt,color)
  if not e._timestamps then return end
  local t=e._timestamps
  mt=mt or 0
  color = color or LOG.LOG
  local totalMain=os.clock()-t.received[2]
  local totalPost=t.posted[2]-t.triggered[2]
  local totalSec=osTime()-t.triggered[1]
  if (totalMain+totalPost > mt) or totalSec>mt then
    Log(color,"Triggered:%s",osDate("%H:%M:%S",t.triggered[1]))
    Log(color,"Posted:%s seconds later",totalPost)
    Log(color,"Received:%s",osDate("%H:%M:%S",t.received[1]))
    Log(color,"Logged:%s seconds later",totalMain)
    Log(color,"%s seconds from triggered to logged",totalSec)
  end
end

function Util.validateChars(str,msg)
  if _VALIDATECHARS then -- Check for strange characters in input string, can happen with cut&paste
    local p = str:find("\xEF\xBB\xBF") if p then error(string.format("Char:%s, "..msg,p,str)) end
--    str=str:gsub("[\192-\255]+[\128-\191]*","X") -- remove multibyte unicode
--    if str:match("[%w%p%s]*") ~= str then error(string.format(msg,str)) end 
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
function Util.reverseMapDef(table) 
  if _EMULATED and _System.reverseMapDef then _System.reverseMapDef(table) end 
  Util._reverseMap({},table) 
end

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
  local res,seen,t = {},{}
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

if _EMULATED then Util.getWeekNumber = _System.getWeekNumber
else Util.getWeekNumber = function(tm) return tonumber(os.date("%V",tm)) end end

function Util.findScenes(str)
  local res = {}
  for _,s1 in ipairs(api.get("/scenes")) do
    if s1.isLua and s1.id~=__fibaroSceneId and s1._local ~= true then
      local s2=api.get("/scenes/"..s1.id)
      if s2==nil or s2.lua==nil then Log(LOG.ERROR,"Scene missing: %s",s1.id)
      elseif s2.lua:match(str) then res[#res+1]=s1.id end
    end
  end
  return res
end

Util.getIDfromEvent={ CentralSceneEvent=function(d) return d.deviceId end,AccessControlEvent=function(d) return d.id end }
Util.getIDfromTrigger={
  property=function(e) return e.deviceID end,
  event=function(e) return e.event and Util.getIDfromEvent[e.event.type or ""](e.event.data) end
}

function Util.checkVersion(vers)
  local req = net.HTTPClient()
  req:request("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/VERSION.json",
    {options = {method = 'GET',timeout=1000},
      success=function(data)
        if data.status == 200 then
          local v = json.decode(data.data)
          if vers then v = v.scenes[vers] end
          if v.version ~= _version or v.fix ~= _fix then
            Event.post({type='ER_version',version=v.version,fix=v.fix or "", _sh=true})
          end
        end
      end})

  EVENTRUNNERSRCPATH = EVENTRUNNERSRCPATH or "EventRunner.lua"
  EVENTRUNNERDELIMETER = EVENTRUNNERDELIMETER or "%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%- EventModel %- Don't change! "
  
  function Util.patchEventRunner(newSrc)
    if newSrc == nil then
      local req = net.HTTPClient()
      req:request("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/"..EVENTRUNNERSRCPATH,
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
      local obp = oldSrc:find(EVENTRUNNERDELIMETER)
      oldSrc = oldSrc:sub(1,obp-1)
      local nbp = newSrc:find(EVENTRUNNERDELIMETER)
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
end

---------- VDev support --------------

function makeVDev()
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
  local function makeButton(tag,id,name,lbl) local b=makeElement(tag,id,name,lbl); b.empty,b.lua,b.msg,b.buttonIcon=false,true,CODE(lbl,tag),0; return b end 
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
VDev = makeVDev()

---- SunCalc -----
SunCalc={}
function SunCalc.sunturnTime(date, rising, latitude, longitude, zenith, local_offset)
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
  return osTime({day = date.day,month = date.month,year = date.year,hour = floor(LT),min = math.modf(frac(LT) * 60)})
end

function SunCalc.getTimezone() local now = osTime() return os.difftime(now, osTime(osDate("!*t", now))) end

function SunCalc.sunCalc(time)
  local hc2Info = api.get("/settings/location") or {}
  local lat = hc2Info.latitude or _LATITUDE
  local lon = hc2Info.longitude or _LONGITUDE
  local utc = SunCalc.getTimezone() / 3600
  local zenith,zenith_twilight = 90.83, 96.0 -- sunset/sunrise 90°50′, civil twilight 96°0′

  local date = osDate("*t",time or osTime())
  if date.isdst then utc = utc + 1 end
  local rise_time = osDate("*t", SunCalc.sunturnTime(date, true, lat, lon, zenith, utc))
  local set_time = osDate("*t", SunCalc.sunturnTime(date, false, lat, lon, zenith, utc))
  local rise_time_t = osDate("*t", SunCalc.sunturnTime(date, true, lat, lon, zenith_twilight, utc))
  local set_time_t = osDate("*t", SunCalc.sunturnTime(date, false, lat, lon, zenith_twilight, utc))
  local sunrise = _format("%.2d:%.2d", rise_time.hour, rise_time.min)
  local sunset = _format("%.2d:%.2d", set_time.hour, set_time.min)
  local sunrise_t = _format("%.2d:%.2d", rise_time_t.hour, rise_time_t.min)
  local sunset_t = _format("%.2d:%.2d", set_time_t.hour, set_time_t.min)
  return sunrise, sunset, sunrise_t, sunset_t
end
--------- ScriptEngine ------------------------------------------
_traceInstrs=false

function newScriptEngine() 
  local self={}
  local function ID(id,i) _assert(tonumber(id),"bad deviceID '%s' for '%s' '%s'",id,i[1],i[3] or "") return id end
  local function doit(m,f,s) if type(s) == 'table' then return m(f,s) else return f(s) end end

  local function getIdFuns(s,i,prop) local id = s.pop() 
    if type(id)=='table' then return Util.map(function(id) return fibaro:getValue(ID(id,i),prop) end,id) else return fibaro:getValue(ID(id,i),prop) end 
  end
  local getIdFun={}
  getIdFun['isOn']=function(s,i) return doit(Util.mapOr2,function(id) return fibaro:getValue(ID(id,i),'value') > '0' end,s.pop()) end
  getIdFun['isOff']=function(s,i) return doit(Util.mapAnd2,function(id) return fibaro:getValue(ID(id,i),'value') == '0' end,s.pop()) end
  getIdFun['isOpen']=function(s,i) return doit(Util.mapOr2,function(id) return fibaro:getValue(ID(id,i),'value') > '0' end,s.pop()) end
  getIdFun['isClose']=function(s,i) return doit(Util.mapAnd2,function(id) return fibaro:getValue(ID(id,i),'value') == '0' end,s.pop()) end
  getIdFun['isAllOn']=function(s,i) return doit(Util.mapAnd2,function(id) return fibaro:getValue(ID(id,i),'value') > '0' end,s.pop()) end
  getIdFun['isAnyOff']=function(s,i) return doit(Util.mapOr2,function(id) return fibaro:getValue(ID(id,i),'value') == '0' end,s.pop()) end
  getIdFun['on']=function(s,i) doit(Util.mapF2,function(id) fibaro:call(ID(id,i),'turnOn') end,s.pop()) return true end
  getIdFun['off']=function(s,i) doit(Util.mapF2,function(id) fibaro:call(ID(id,i),'turnOff') end,s.pop()) return true end
  getIdFun['open']=function(s,i) doit(Util.mapF2,function(id) fibaro:call(ID(id,i),'open') end,s.pop()) return true end
  getIdFun['close']=function(s,i) doit(Util.mapF2,function(id) fibaro:call(ID(id,i),'close') end,s.pop()) return true end
  getIdFun['stop']=function(s,i) doit(Util.mapF2,function(id) fibaro:call(ID(id,i),'stop') end,s.pop()) return true end
  getIdFun['secure']=function(s,i) doit(Util.mapF2,function(id) fibaro:call(ID(id,i),'secure') end,s.pop()) return true end
  getIdFun['unsecure']=function(s,i) doit(Util.mapF2,function(id) fibaro:call(ID(id,i),'unsecure') end,s.pop()) return true end
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
  getIdFun['toggle']=function(s,i) return doit(Util.mapF,function(id) fibaro:call(id,"toggle") end,s.pop()) end
  local setIdFun={}
  local _propMap={R='setR',G='setG',B='setB', armed='setArmed',W='setW',value='setValue',time='setTime',power='setPower'}
  local function setIdFuns(s,i,prop,id,v) 
    local p,vp=_propMap[prop],0 _assert(p,"bad setProperty :%s",prop)
    local vf = type(v) == 'table' and type(id)=='table' and v[1] and function() vp=vp+1 return v[vp] end or function() return v end 
    doit(Util.mapF,function(id) fibaro:call(ID(id,i),p,vf()) end,id) 
  end
  setIdFun['color'] = function(s,i,id,v) doit(Util.mapF,function(id) fibaro:call(ID(id,i),'setColor',v[1],v[2],v[3]) end,id) return v end
  setIdFun['msg'] = function(s,i,id,v) local m = v doit(Util.mapF,function(id) fibaro:call(ID(id,i),'sendPush',m) end,id) return m end
  setIdFun['email'] = function(s,i,id,v) local h,m = v:match("(.-):(.*)") 
    doit(Util.mapF,function(id) fibaro:call(ID(id,i),'sendEmail',h,m) end,id) return v
  end
  setIdFun['defemail'] = function(s,i,id,v) 
    doit(Util.mapF,function(id) fibaro:call(ID(id,i),'sendDefinedEmailNotification',v) end,id) return v
  end
  setIdFun['btn'] = function(s,i,id,v) local k = v doit(Util.mapF,function(id) fibaro:call(ID(id,i),'pressButton',k) end,id) return k end
  setIdFun['start'] = function(s,i,id,v) 
    if isEvent(v) then doit(Util.mapF,function(id) Event.postRemote(ID(id,i),v) end,id) return v
    else doit(Util.mapF,function(id) fibaro:startScene(ID(id,i),v) end,id) return v end 
  end
  local timeFs ={["*"]=function(t) return t end,
    t=function(t) return t+midnight() end,
    ['+']=function(t) return t+osTime() end,
    n=function(t) t=t+midnight() return t> osTime() and t or t+24*60*60 end,
    ['midnight']=function(t) return midnight() end,
    ['sunset']=function(t) if t=='*' then return hm2sec('sunset') else return toTime(t.."/sunset") end end,
    ['sunrise']=function(t) if t=='*' then return hm2sec('sunrise') else return toTime(t.."/sunrise") end end,
    ['wnum']=function(t)  return Util.getWeekNumber(osTime()) end,
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
  instr['setProp'] = function(s,n,e,i) local id,v,prop=s.pop(),s.pop(),i[3] 
    if setIdFun[prop] then setIdFun[prop](s,i,id,v) else setIdFuns(s,i,prop,id,v) end
    s.push(v) 
  end
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
    if type(x)=='table' and type(y)=='string' then s.push(Util.deviceTypeFilter(x,y)) else s.push(x/y) end
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
  instr['match'] = function(s,n) local a,b=s.pop(),s.pop(); s.push(string.match(b,a)) end
  instr['tjson'] = function(s,n) s.push(tojson(s.pop())) end
  instr['fjson'] = function(s,n) s.push(json.decode(s.pop())) end
  instr['osdate'] = function(s,n) local x,y = s.ref(n-1),(n>1 and s.pop() or nil) s.pop(); s.push(osDate(x,y)) end
  instr['daily'] = function(s,n,e) s.pop() s.push(true) end
  instr['schedule'] = function(s,n,e,i) local t,code = s.pop(),e.code; s.push(true) end
  instr['ostime'] = function(s,n) s.push(osTime()) end
  instr['frm'] = function(s,n) s.push(string.format(table.unpack(s.lift(n)))) end
  instr['idname'] = function(s,n) s.push(Util.reverseVar(s.pop())) end 
  instr['label'] = function(s,n,e,i) local nm,id = s.pop(),s.pop() s.push(fibaro:getValue(ID(id,i),_format("ui.%s.value",nm))) end
  instr['slider'] = instr['label']
  instr['once'] = function(s,n,e,i) local f; i[4],f = s.pop(),i[4]; s.push(not f and i[4]) end
  instr['always'] = function(s,n,e,i) s.pop(n) s.push(true) end
  instr['enable'] = function(s,n,e,i) local t,g = s.pop(),false; 
    if n==2 then g,t=t,s.pop() end
    s.push(Event.enable(t,g)) 
  end
  instr['disable'] = function(s,n,e,i) s.push(Event.disable(s.pop())) end
  instr['post'] = function(s,n,ev) local e,t=s.pop(),nil; if n==2 then t=e; e=s.pop() end s.push(Event.post(e,t,ev.rule)) end
  instr['subscribe'] = function(s,n,ev) Event.subscribe(s.pop()) s.push(true) end
  instr['publish'] = function(s,n,ev) local e,t=s.pop(),nil; if n==2 then t=e; e=s.pop() end Event.publish(e,t) s.push(e) end
  instr['remote'] = function(s,n,ev) local e,u=s.pop(),s.pop(); Event.postRemote(u,e) s.push(true) end
  instr['cancel'] = function(s,n) Event.cancel(s.pop()) s.push(nil) end
  instr['add'] = function(s,n) local v,t=s.pop(),s.pop() table.insert(t,v) s.push(t) end
  instr['remove'] = function(s,n) local v,t=s.pop(),s.pop() table.remove(t,v) s.push(t) end
  instr['betw'] = function(s,n) local t2,t1,now=s.pop(),s.pop(),osTime()-midnight()
    _assert(tonumber(t1) and tonumber(t2),"Bad arguments to between '...', '%s' '%s'",t1 or "nil", t2 or "nil")
    --Log(LOG.LOG,"BETWEEN T1:%s - Now:%s - T2:%s",time2str(t1),time2str(now),time2str(t2))
    if t1<=t2 then s.push(t1 <= now and now <= t2) else s.push(now >= t1 or now <= t2) end 
  end
  instr['redaily'] = function(s,n,e,i) s.push(Rule.restartDaily(s.pop())) end
  instr['eventmatch'] = function(s,n,e,i) local ev,evp=i[3][2],i[3][3] 
    s.push(e.event and Event._match(evp,e.event) and ev or false) 
  end
  instr['wait'] = function(s,n,e,i) local t,cp=s.pop(),e.cp 
    if i[4] then s.push(false) -- Already 'waiting'
    elseif i[5] then i[5]=false s.push(true) -- Timer expired, return true
    else 
      _assert(type(t)=='number',"Bad argument to wait '%s'",t~=nil and t or "nil")
      if t<midnight() then t = osTime()+t end -- Allow both relative and absolute time... e.g '10:00'->midnight+10:00
      local code,stack = e.code,e.stack
      i[4]=Event.post(function() i[4]=nil i[5]=true self.eval(code,e,stack,cp) end,t,e.rule) s.push(false) error({type='yield'})
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
    local rep = function() i[6] = true; i[5] = nil; self.eval(code,e) end
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

  local function postTrace(i,args,stack,cp)
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
      t.isdst=nil
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
    {"^%#([0-9a-zA-Z_]+{?)",'event'},
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
    {"^([_a-zA-Z\xC3\xA5\xA4\xB6\x85\x84\x96][_0-9a-zA-Z\xC3\xA5\xA4\xB6\x85\x84\x96]*)",'symbol'},
    {"^(%.%.)",'op'},{"^(->)",'op'},    
    {"^(%d+%.?%d*)",'num'},
    {"^(%|%|)",'token'},{"^(>>)",'token'},{"^(=>)",'token'},{"^(@@)",'op'},{"^([%*%+~=><]+)",'op'},
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
  local tProps ={value=1,isOn=1,isOff=1,open=1,close=1,isOpen=1,isClose=1,isAnyOff=1,isAllOn=1,last=1,safe=1,breached=1,scene=2,power=3,bat=4,trigger=1,dID=7,toggle=1,lux=1,temp=1,manual=1,central=5,access=6}
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
    if #t1>0 then _transform(t1[1],function(t) t2[t]=true end) end
    return mapkl(function(k,v) return k end,t2)
  end

  local CATCHUP = math.huge
  local RULEFORMAT = "Rule:%s:%."..(_ruleLogLength or 40).."s"

  -- #property{deviceID={6,7} & 6:isOn => .. generates 2 triggers for 6????
  -- #ev & 6:isOn
  local function _remapEvents(obj)
    if isTEvent(obj) then 
      local ce = ScriptEngine.eval(ScriptCompiler.compile(obj))
      if isEvent(ce) then ---ce.type == 'property' and type(ce.deviceID)=='table' then
        if type(ce.deviceID)=='table' and #ce.deviceID> 0 then
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
      local res = {} for l,v in pairs(obj) do res[l] = _remapEvents(v) end 
      return res
    else return obj end
  end

  HOURS24 = 24*60*60
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
      local timeVal,skip = nil,ScriptEngine.eval(scheds[1])
      Log(LOG.LOG,'start')
      local function interval()
        timeVal=timeVal or osTime()
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
            if _MIDNIGHTADJUST and t==HOURS24 then t=t-1 end
            if t+m >= ot then 
              --if _debugFlags.dailys then Debug(true,"Scheduling daily %s at %s",rCounter+1,osDate("%c",m+t)) end
              dtimers[#dtimers+1]=Event.post(devent,t+m) 
            else catchup1=true end
          else catchup2 = true end
        end
        if catchup2 and catchup1 then Log(LOG.LOG,"Catching up:%s",ctx.src); Event.post(devent) end
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
    res._name = Log(LOG.SYSTEM,RULEFORMAT,rCounter,ctx.src:match("([^%c]*)")):sub(1,40)..".."
    return res
  end

-- context = {log=<bool>, level=<int>, line=<int>, doc=<str>, trigg=<bool>, enable=<bool>}
  function self.eval(escript,log,ctx)
    Util.validateChars(escript,"Invalid (multi-byte) char in rule:%s")
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
      if _MIDNIGHTADJUST and t==HOURS24 then t=t-1 end
      if t ~= CATCHUP and t+m >= ot then 
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
          if t ~= CATCHUP then
            if _debugFlags.dailys then Debug(true,"Scheduling daily %s at %s",d.rule._name or "",osDate("%c",midnight+t)) end
            if _MIDNIGHTADJUST and t==HOURS24 then t=t-1 end
            if t==0 then dt=Event.post(d.event) else dt=Event.post(d.event,midnight+t) end
            d.timers[#d.timers+1]=dt
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

--- SceneActivation constants
Util.defvar('S1',Util.S1)
Util.defvar('S2',Util.S2)
Util.defvar('catch',math.huge)
Util.defvar("defvars",Util.defvars)
Util.defvar("mapvars",Util.reverseMapDef)

-- Sunset/sunrise patch
local _SUNTIMEDAY = nil
local _SUNTIMEVALUES = {sunsetHour=nil,sunriseHour=nil}
Event._registerID(1,nil,function(obj,id,prop) 
    if prop=='sunsetHour' or prop=='sunriseHour' then
      local day = os.date("*t").day
      if day ~= _SUNTIMEDAY then
        _SUNTIMEDAY = day
        _SUNTIMEVALUES.sunriseHour,_SUNTIMEVALUES.sunsetHour=SunCalc.sunCalc()
      end
      return _SUNTIMEVALUES[prop]
    else return fibaro._get(obj,id,prop) end
  end)

-- Ping / publish / subscribe / & emulator support
Event._dir,Event._rScenes,Event._subs,Event._stats = {},{},{},{}
Event.ANNOUNCE,Event.SUB = '%%ANNOUNCE%%','%%SUB%%' 
Event.event({type=Event.PING},function(env) e=_copy(env.event);e.type=Event.PONG; Event.postRemote(e._from,e) end)

local function isRunning(id) 
  if _EMULATED then id = math.abs(id) end
  return fibaro:countScenes(id)>0 
end

Event.event({{type='autostart'},{type='other'}},
  function(env)
    local event = {type=Event.ANNOUNCE, subs=#Event._subs>0 and Event._subs or nil}
    for _,id in ipairs(Util.findScenes(gEventRunnerKey)) do 
      if isRunning(id) then
        Debug(_debugFlags.pubsub,"Announce to ID:%s %s",id,tojson(env.event.subs)); Event._rScenes[id]=true; Event.postRemote(id,event) 
      end
    end
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
function Event.sendAllScenes(event) for id,s in pairs(Event._rScenes) do Event.sendScene(id,event) end end
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
        if _equal(e.event,event) then seen=true; if not Util.member(id,e.ids) then e.ids[#e.ids+1]=id end; break; end
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

Event.event({type='%%EMU%%'},function(env)
    e = env.event
    local ids = {}
    for _,id in ipairs(e.ids or {}) do ids[id]=true end
    _emulator={ids=ids,adress=e.adress} 
    if e.proxy then
      local function proxy(trigger)
        if not _emulator.address then return end
        local req = net.HTTPClient()
        req:request(_emulator.adress,{options = {method = 'PUT', data=json.encode(trigger), timeout=500},
            error=function() Event.triggerProxy=Event.post; Log(LOG.LOG,"Resetting proxy") end}) -- reset handler if error
      end
      Event.triggerHandler=proxy
    else Event.triggerHandler=Event.post end
  end)

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
    function self.hueName(hue) --Hue1:SensorID=1
      local name,t,id=hue:match("(%w+):(%a+)=(%d+)")
      local dev = ({SensorID='sensors',LightID='lights',GroupID='groups'})[t]
      return name..":"..self.hubs[name][dev][tonumber(id)].name 
    end
    function self.request(url,cont,op,payload)
      op,payload = op or "GET", payload and json.encode(payload) or ""
      Debug(_debugFlags.hue,"Hue req:%s Payload:%s",url,payload)
      HTTP:request(url,{
          options = {headers={['Accept']='application/json',['Content-Type']='application/json'},
            data = payload, timeout=_HueTimeout or 2000, method = op},
          error = function(status) error("Hue connection:"..tojson(status)..", "..url) end,
          success = function(status) if cont then cont(json.decode(status.data)) end end
        })
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
    function self.define(name,var,id) -- optional var
      if id ==nil then id = mapIndex; mapIndex=mapIndex+1 else id =tonumber(id) end
      if not name:match(":") then name=_defaultHubName..":"..name end -- default to Hue:<name>
      hueNames[name]=id
      local hue,hub = find(name) 
      if hue then devMap[id] = {type=hue.type,hue=hue,hub=self.hubs[hub]}; hue.fid=id    
      else error("No Hue name:"..name) end
      if Util and var then Util.defvar(var,id) end
      Log(LOG.LOG,"Hue device '%s' assigned deviceID %s",name,id)
      Event._registerID(id,hueCall,hueGet)
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
  local function match(t1,t2) if #t1~=#t2 then return false end; for i=1,#t1 do if t1[i]~=t2[i] then return false end end return true end
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
      Debug(_debugFlags.hue,"Monitoring URL:%s",url)
      local function poll() 
        Hue.request(url,function(state) self._setState(sensor,state.state) sensor._timer=setTimeout(poll,interval) end)
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
if _type == 'other' and fibaro:countScenes() > 1 then 
  Log(LOG.LOG,"Scene already started. Try again?") 
  fibaro:abort()
end
if _type == 'autostart' or _type == 'other' then
  Log(LOG.WELCOME,_format("%sEventRunner v%s %s",_sceneName and (_sceneName.." - " or ""),_version,_fix))

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
  if _EMULATED and not _ANNOUNCEDTIME then 
    Log(LOG.LOG,"Starting:%s %s",osDate("%x %X",osTime()),_SPEEDTIME and "(speeding)" or "") 
  end

  GC = 0
  local function setUp()
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

  local function chainStartup() if hueSetup then return hueSetup(setUp) else return setUp() end end

  for _,mb in ipairs(_MAILBOXES) do 
    fibaro:setGlobal(mb,"") 
  end
  _CXCST1=os.clock()
  if not _EMULATED then _poll()  end -- start polling mailbox
  chainStartup()

end