--[[
%% properties
%% events
%% globals
%% autostart 
--]] 

-- Don't forget to declare triggers from devices in the header!!!
if dofile and not _EMULATED then _EMBEDDED={name="EventRunner", id=11} dofile("HC2.lua") end

_version,_fix = "2.0","B9"  -- June 5, 2019   

--[[
-- EventRunner. Event based scheduler/device trigger handler
-- Copyright 2019 Jan Gabrielsson. All Rights Reserved.
-- Email: jan@gabrielsson.com
--]]

_sceneName   = "Supervisor"      -- Set to scene/script name
--if dofile then dofile("credentials.lua") end -- To not accidently commit credentials to Github, or post at forum :-)
-- E.g. Hue user names, icloud passwords etc. HC2 credentials is set from HC2.lua, but can use same file.

KEEPALIVE = true -- Enable keep-alive service
LOGGER    = true -- Enable Logger service
KEYSTORE  = false -- Enable Key store service

SIMPLEKEEPALIVE = false -- SImple count scene instances to check if scenes are alive

-- debug flags for various subsystems...
_debugFlags = { 
  post=false,invoke=false,triggers=false,dailys=false,rule=false,ruleTrue=false,hue=false,msgTime=false,
  fcall=true, fglobal=false, fget=false, fother=false
}
---------------- Here you place rules and user code, called once at startup --------------------
function main()

  if KEEPALIVE then
    -- Ping and Keep-alive -------------------------------

    local POLLINTERVAL = "+/00:03"    -- poll every 3 minute
    local PINGTIMEOUT = "+/00:00:20"  -- No answer in 10s, scene will be restarted
    local STARTUPDELAY = "+/00:00:20" -- Time for scene to startup after a restart before pinging starts again
    local MAXRESTARTS = 2             -- Number of failed restarts before disabling the scene
    local phonesToNotify = {}         -- Phone to alter when restarting scenes

    local eventRunners = {}
    local eventMap = {}

    Event.event({{type='autostart'},{type='other'}},
      function(env)
        local scenes = Util.findScenes(gEventRunnerKey)
        for _,id in ipairs(scenes) do Event.post({type=Event.ANNOUNCE,_from=id,d='AS'}) end
      end)

    Event.event({type='notify',scene='$scene', msg='$msg'},
      function(env) 
        for _,p in ipairs(phonesToNotify) do 
          fibaro:call(p,"sendPush",string.format(env.p.msg,env.p.scene.name,env.p.scene.id)) 
        end
      end)

    if SIMPLEKEEPALIVE then -- count instances model
      Event.event({type=Event.ANNOUNCE},
        function(env)
          local id,old = env.event._from
          local scene = eventRunners[id]
          if scene and scene.timeout then scene.timeout = Event.cancel(scene.timeout) old=true end -- if we have pinged, cancel
          scene={id=id,name=api.get("/scenes/"..id).name}
          eventRunners[id]=scene
          Log(LOG.LOG,"%segistering scene:'%s', ID:%s",old and "Re-r" or "R",scene.name,scene.id) 
          scene.timeout=Event.post({type='watch',scene=scene,interval=POLLINTERVAL,timeout=PINGTIMEOUT},osTime()+math.random(1,4))
        end)

      Event.event({type='watch', scene='$scene', timeout='$timeout',},
        function(env)
          local scene = env.p.scene
          scene.timeout=nil
          scene.ttime = os.time()
          local runconfig = fibaro:getSceneRunConfig(scene.id)
          if runconfig == nil then eventRunners[scene.id]=nil; return end -- Removed?
          eventMap[scene.id]=env.event
          if (not scene.disabled) and runconfig == 'TRIGGER_AND_MANUAL' then
            local n = fibaro:countScenes(scene.id)
            if n < 1 then
              if scene.restarts and scene.restarts >= MAXRESTARTS then
                Log(LOG.ERROR,"Scene:'%s', ID:%s - unable to restart",scene.name,scene.id)
                --fibaro:setSceneRunConfig(scene.id,'MANUAL_ONLY')
                Event.post({type='notify',scene=scene, msg="Scene:'%s', ID:%s could not be restarted"})
              else
                Log(LOG.ERROR,"Scene:'%s', ID:%s not running, restarting scene!",scene.name,scene.id)
                fibaro:killScenes(scene.id) 
                fibaro:startScene(scene.id)
                Event.post({type='notify',scene=scene, msg="Restarted scene:'%s', ID:%s"})
                scene.restarts = scene.restarts and scene.restarts+1 or 1
                scene.timeout=Event.post(env.event,STARTUPDELAY)-- Start watching again. Give scene some time to start up 
              end
            else 
              Log(LOG.LOG,"Scene:'%s' is alive, ID:%s",scene.name,scene.id)
              scene.timeout=Event.post(env.event,env.event.interval)
            end
          else
            Log(LOG.LOG,"Not watching scene:'%s', ID:%s disabled=%s runconfig=%s",
              scene.name,scene.id,tostring(scene.disabled),runconfig)
            if scene.disabled then
              -- Log(LOG.LOG,"Skipping disabled scene:'%s', ID:%s",scene.name,scene.id)
            else
              -- Log(LOG.LOG,"Skipping scene:'%s', ID:%s with runconfig:%s",scene.name,scene.id,runconfig)
            end
            scene.timeout=Event.post(env.event,env.event.interval) 
          end
        end) 


    else -- Ping model
      Event.event({type=Event.ANNOUNCE},
        function(env)
          local id,old = env.event._from
          local scene = eventRunners[id]
          if scene and scene.timeout then scene.timeout = Event.cancel(scene.timeout) old=true end -- if we have pinged, cancel
          scene={id=id,name=api.get("/scenes/"..id).name}
          eventRunners[id]=scene
          Log(LOG.LOG,"%segistering scene:'%s', ID:%s",old and "Re-r" or "R",scene.name,scene.id) 
          scene.timeout=Event.post({type='watch',scene=scene,interval=POLLINTERVAL,timeout=PINGTIMEOUT},osTime()+math.random(1,4))
        end)

      Event.event({type='watch', scene='$scene', timeout='$timeout',},
        function(env)
          local scene = env.p.scene
          scene.timeout=nil
          scene.ttime = os.time()
          local runconfig = fibaro:getSceneRunConfig(scene.id)
          if runconfig == nil then eventRunners[scene.id]=nil; return end -- Removed?
          eventMap[scene.id]=env.event
          if (not scene.disabled) and runconfig == 'TRIGGER_AND_MANUAL' then
            scene.timeout=Event.post({type='pingTimeout',scene=scene},env.p.timeout)
            Log(LOG.LOG,"Pinging scene:'%s', ID:%s",scene.name,scene.id)
            Event.postRemote(scene.id,{type=Event.PING})
          else
            Log(LOG.LOG,"Not pinging scene:'%s', ID:%s disabled=%s runconfig=%s",
              scene.name,scene.id,tostring(scene.disabled),runconfig)
            if scene.disabled then
              -- Log(LOG.LOG,"Skipping disabled scene:'%s', ID:%s",scene.name,scene.id)
            else
              -- Log(LOG.LOG,"Skipping scene:'%s', ID:%s with runconfig:%s",scene.name,scene.id,runconfig)
            end
            scene.timeout=Event.post(env.event,env.event.interval) 
          end
        end) 

      Event.event({type='pingTimeout', scene='$scene'}, -- restart scene
        function(env)
          local scene = env.p.scene
          local wevent = eventMap[scene.id]
          scene.timeout=nil
          if scene.restarts and scene.restarts >= MAXRESTARTS then
            Log(LOG.ERROR,"Scene:'%s', ID:%s - unable to restart",scene.name,scene.id)
            fibaro:setSceneRunConfig(scene.id,'MANUAL_ONLY')
            Event.post({type='notify',scene=scene, msg="Scene:'%s', ID:%s could not be restarted"})
            scene.timeout=Event.post(wevent,wevent.interval)
          else
            Log(LOG.ERROR,"Scene:'%s', ID:%s not answering, restarting scene!",scene.name,scene.id)
            fibaro:killScenes(scene.id) 
            fibaro:startScene(scene.id)
            Event.post({type='notify',scene=scene, msg="Restarted scene:'%s', ID:%s"})
            scene.restarts = scene.restarts and scene.restarts+1 or 1
            scene.timeout=Event.post(wevent,STARTUPDELAY)-- Start watching again. Give scene some time to start up 
          end
        end)

      Event.event({type=Event.PONG}, -- Got a pong back from client, cancel 'timeout' and watch again 
        function(env)
          local id = env.event._from
          local scene = eventRunners[id]
          local wevent = eventMap[id]
          if scene.timeout == nil then return end
          scene.restarts = nil
          Log(LOG.LOG,"Pong from scene:'%s', ID:%s (resp:%ss)",scene.name,id,os.time()-scene.ttime)
          Event.cancel(scene.timeout) 
          scene.timeout=Event.post(wevent,wevent.interval)
        end)
    end
  end

----------------- DB handling -------------------------------------
  DB={}
  function DB:create(name,init)
    local scenes = api.get("/scenes")
    for _,s in ipairs(scenes) do 
      if s.name==name then 
        Log(LOG.LOG,"Log database exist") 
        return s.id  
      end -- database already exist, return ID
    end
    local db = -- create "database", i.e. scene
    {actions = {devices = {}, groups = {}, scenes = {}}, 
      alexaProhibited = true, autostart = false, --iconID = 0, 
      isLua = true, killOtherInstances = false, killable = true, 
      lua = "", maxRunningInstances = 10, 
      name = name,properties = "", protectedByPIN = false,runConfig = "DISABLED", 
      triggers = {events = {}, globals = {}, properties = {}, weather = {}}, 
      type = "com.fibaro.luaScene",visible = false}
    local s = api.post("/scenes",db)
    if s then
      s.lua, s.runConfig = init,"DISABLED"
      api.put("/scenes/"..s.id,s)
      return s.id 
    end
  end

  function DB:read(id)
    local s = api.get("/scenes/"..id)
    --print(s.lua)
    return s.lua and json.decode(s.lua) or {}
  end

  function DB:write(id,items,start,stop,fun)
    local s = api.get("/scenes/"..id)
    if s.lua then
      local res = {start}
      for k,i in pairs(items) do
        res[#res+1]= fun(i,k)..","
      end
      if res[#res] then res[#res]=res[#res]:sub(1,-2) end
      res[#res+1]=stop
      res = table.concat(res,"\n")
      s.lua = res
      api.put("/scenes/"..id,s)
    end
  end

  if LOGGER then
    ------- Log handling ------------- 
    local LOGWRITEINTERVAL = "+/00:01" 
    local MAXENTRIES = 2000
    local PRUNENTRIES = 1500

    function createLog(name) return DB:create(name,"[]") end
    function readLog(id) return DB:read(id) end
    function writeLog(id,items) DB:write(id,items,"[","]",function(i,k) return Util.prettyJson(k) end) end

    local logID = createLog("EventRunner Log")
    if logID then
      local logItems = readLog(logID)
      local currLogItems = #logItems 
      Log(LOG.LOG,"Log items %s",currLogItems)

      Event.subscribe({type='ERLog'},
        function(env)
          local time = env.event.time or os.time()
          local from = env.event.from or env.event._from
          local msg = env.event.msg or "No text"
          time = type(time)=='number' and os.date("%X/%x",time) or time
          logItems[#logItems+1]={time,"Scene:"..from,msg}
        end)

      Event.schedule(LOGWRITEINTERVAL,function()
          if #logItems ~= currLogItems then
            if #logItems > MAXENTRIES then
              local l,n={},#logItems
              for i=PRUNENTRIES,0,-1 do l[#l+1]=logItems[n-i] end
              logItems=l
            end
            writeLog(logID,logItems)
            currLogItems = #logItems
          end
        end)

    else
      Log(LOG.ERROR,"Unable to create log database!")
    end
  end

  if KEYSTORE then
    ------- KeyStore handling ------------- 
    local KEYSTOREWRITEINTERVAL = "+/00:01" 
    local ksUpdate = false

    function createKS(name) return DB:create(name,"[]") end
    function readKS(id) return DB:read(id) end
    function writeKS(id,items) DB:write(id,items,"{","}",
        function(i,k) return string.format('"%s"="%s"',i,Util.prettyJson(k)) end) 
    end

    local ksID = createKS("EventRunner keystore")
    if ksID then
      local ksItems = readKS(ksID)

      Event.subscribe({type='ERkeystore'},
        function(env)
          local key = env.event.key
          local value = env.event.value 
          if key and type(key)=='string' and value then
            Log(LOG.LOG,"%s %s",key,tojson(value))
            ksItems[key]=value
            ksUpdate=true
          end
        end)

      -- Supervisor={}
      -- Event.subscribe({type='%%Supervisor%%', id=__fibaroSceneId, logId=logID, keystoreId=ksID},
      --        function(env) local s,e=Supervisor,env.event; s.id,s.logId,s.keystoreId=e.id,e.logId,e.keystoreId end)
      -- function Supervisor.getKey(key)
      --    if Supervisor.ksID then
      --      local ks = api.get("/scenes/"..Supervisor.ksID)
      --      return ks.isLua and (json.decode(ks.lua))[key]
      --    end
      -- end
      -- function Supervisor.setKey(key,value)
      --    Event.publish({type='ERkeystore', key=key, value=value})
      -- end
      -- function Supervisor.log(str,...)
      --    Event.publish({type='ERlog', msg=string.format(str,...)})
      -- end

      Event.schedule(KEYSTOREWRITEINTERVAL,function()
          if ksUpdate then writeKS(ksID,ksItems); ksUpdate=false end
        end)

    else
      Log(LOG.ERROR,"Unable to create keystore database!")
    end

  end

  Event.publish({type='%%Supervisor%%', id=__fibaroSceneId, logId=logID, keystoreId=ksID},true)

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

function Util.checkVersion()
  local req = net.HTTPClient()
  req:request("https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/VERSION.json",
    {options = {method = 'GET',timeout=1000},
      success=function(data)
        if data.status == 200 then
          local v = json.decode(data.data)
          if v.version ~= _version or v.fix ~= _fix then
            Event.post({type='ER_version',version=v.version,fix=v.fix or "", _sh=true})
          end
        end
      end})
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

---------------- Extra setup ----------------

local function makeDateInstr(f)
  return function(s,n,e,i)
    local ts = s.pop()
    if ts ~= i[5] then i[6] = Util.dateTest(f(ts)); i[5] = ts end -- cache fun
    s.push(i[6]())
  end
end

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