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

--[[

  EventRunnerDebug. EventRunner support
  GNU GENERAL PUBLIC LICENSE. Version 3, 29 June 2007
  Author Jan Gabrielson, Email: jan@gabrielsson.com

  Offline support for HC2 functions
  Can use FibaroSceneAPI/Lualibs for HC2 remote invocation (_REMOTE=true)
  (See tutorial at https://forum.fibaro.com/index.php?/topic/24319-tutorial-zerobrane-usage-lua-coding/)
  ...or some simpler local emulation of Fibaro functions (_REMOTE=false) that logs to the console
  _PORTLISTENER=true starts a listener on a socket for receieving sourcetriggers/events from HC2 scene
  
--]] 
_version = _version or "1.8"
if _version ~= "1.8" then error("Bad version of EventRunnerDebug") end  
function _DEF(v,d) if v==nil then return d else return v end end

_GUI           = _DEF(_GUI,false)        -- Needs wxwidgets support (e.g. require "wx"). Works in ZeroBrane under Lua 5.1.
_SPEEDTIME     = _DEF(_SPEEDTIME,24*35)  -- nil or run faster than realtime for x hours
_REMOTE        = _DEF(_REMOTE,false)     -- If true use FibaroSceneAPI to call functions on HC2, else emulate them locally...
_GLOBALS_FILE  = _DEF(GLOBALS_FILE,"globals.data")
-- Server parameters
_PORTLISTENER = NodeRed
_POLLINTERVAL = 200 
_PORT         = 6872
_MEM          = false  -- log memory usage

_LATITIDE = "59.316947"
_LONGITIDE = "18.064006"

-- HC2 credentials and parameters
hc2_user           = "xxx" -- used for api.x/FibaroSceneAPI calls
hc2_pwd            = "xxx" 
hc2_ip             = "192.168.1.84" -- IP of HC2
local creds = loadfile("credentials.lua") -- To not accidently commit credentials to Github...
if creds then creds() end
GLOBALS_FILE       = "globals.data"

__fibaroSceneId    = __fibaroSceneId or 32     -- Set to scene ID. On HC2 this variable is defined

-- Don't touch --------------------------------------------------
--[[
_debugFlags = { 
  post=true,       -- Log all posts
  invoke=true,     -- Log all handlers being invoked (triggers, rules etc)
  rule=false,      -- Log result from invoked script rule
  ruleTrue=false,  -- Log result from invoked script rule on if result is true
  triggers=false,  -- Log all externally incoming triggers (devices, globals etc)
  dailys=false,    -- Log all dailys being scheduled at midnight
  postFuns=false,  -- Log post of functions (many internal functions use this)
  sysTimers=false, -- Log all timers (setTimeout) being scheduled)
  fibaro=true,     -- Log all fibaro calls except get/set
  fibaroGet=false  -- Log fibaro get/set
}
--]]
_debugFlags = 
_debugFlags or { 
  post=true,invoke=false,triggers=false,dailys=false,postFuns=false,rule=false,ruleTrue=false,
  fibaro=true,fibaroGet=false,fibaroSet=false,sysTimers=false 
}

--if _GUI then _SPEEDTIME=false end
_OFFLINE           = true          -- Always true if we include this file (e.g. not running on the HC2)
_HC2               = not _OFFLINE  -- Always false if we include this file               = 
mime = require('mime')
https = require ("ssl.https")
ltn12 = require("ltn12")
json = require("json")
socket = require("socket")
http = require("socket.http")
fibaro = {}
_System = _System  or {}
Event = Event  or {}
require('mobdebug').coro()
if _REMOTE then
  require ("FibaroSceneAPI") 
end

_ENV = _ENV or _G or {}

_SCENECOUNT=1
_SOURCETRIGGER={type = "autostart"}
function fibaro:getSourceTrigger() return _SOURCETRIGGER end

osDate,osTime = os.date,os.time
osOrgDate,osOrgTime = os.date,os.time
GC=GC or collectgarbage("count")

------------------------------------------------
LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ERROR = "Tomato"}
_LOGMAP = {orange="\027[33m",white="\027[34m",Cyan="\027[35m",green="\027[32m",Tomato="\027[31m"} -- ANSI escape code, supported by ZBS
_LOGEND = "\027[0m"
_format = string.format
function printf(...) print(_format(...)) end
function fibaro:debug(str) print(_format("%s:%s",osDate("%X"),str)) end

function _Msg(color,message,...)
  color = _LOGMAP[color] or ""
  local args = type(... or 42) == 'function' and {(...)()} or {...}
  message = string.format(message,table.unpack(args))
  local gc = _MEM and _format("mem:%-6.1f ",collectgarbage("count")) or ""
  fibaro:debug(string.format("%s%s%s %s%s",color,gc,osOrgDate("%a %b %d:",osTime()),message,_LOGEND)) 
  return message
end
function Debug(flag,message,...) if flag then _Msg(LOG.DEBUG,message,...) end end
function Log(color,message,...) return _Msg(color,message,...) end

function _LINEFORMAT(line) return line and " at line "..line or "" end
function _LINE() 
  if _OFFLINE then 
    for i=1,5 do 
      local l = debug.getinfo(i); 
      if l and l.currentline < _STARTLINE then return l.currentline end 
    end
    return nil
  end
end

function split(s, sep)
  local fields = {}
  sep = sep or " "
  local pattern = string.format("([^%s]+)", sep)
  string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
  return fields
end

function urlencode(str)
  if str then
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w %-%_%.%~])", function(c)
        return ("%%%02X"):format(string.byte(c))
      end)
    str = str:gsub(" ", "%%20")
  end
  return str	
end

------------- Saving restoring globals -----------------

function _System.copyGlobalsFromHC2()
  file = file or _GLOBALS_FILE
  Log(LOG.SYSTEM,"Reading globals from H2C...")
  local vars = api.get("/globalVariables/")
  for _,v in ipairs(vars) do
    fibaro._globals[v.name] = {tostring(v.value),osTime()}
  end
end

function _System.writeGlobalsToFile(file)
  file = file or _GLOBALS_FILE
  Log(LOG.SYSTEM,"Writing globals to '%s'",file)
  local f = io.open(file,"w+")
  local fl = false
  f:write("[\r\n")
  for name,value in pairs(fibaro._globals) do
    if not fl then fl=true else f:write(",\r\n\r\n") end
    f:write(json.encode({[name]=value[1]}))
   -- f:write("\r\n\r\n")
  end
  f:write("\r\n]\r\n")
  f:close()
  Log(LOG.SYSTEM,"Globals written - exiting")
end

function _System.readGlobalsFromFile(file)
  file = file or _GLOBALS_FILE
  local f = io.open(file)
  if f then
    local vars = f:read("*all")
    vars = json.decode(vars)
    for _,v in ipairs(vars) do 
      local var,val=next(v)
      fibaro._globals[var] = {tostring(val),osTime()} 
    end
    Log(LOG.SYSTEM,"Initiated %s globals from '%s'",#vars,file)
  else Log(LOG.SYSTEM,"No globals file found (%s)'",file) end
end

--- Parse scene headers ------------------------
do
  _System.headers = {}
  local short_src = _sceneFile or debug.getinfo(3).short_src
  short_src=short_src:match("[\\/]?([%.%w_%-]+)$")
  local f = io.open(short_src) 
  local src = f:read("*all")
  local c = src:match("--%[%[.-%-%-%]%]")
  local curr = nil
  if c and c~="" then
    c=c:gsub("([\r\n]+)","\n")
    c = split(c,'\n')
    for i=2,#c-1 do
      if c[i]:match("%%%%") then curr=c[i]:match("%a+")
      elseif curr then 
        local h = _System.headers[curr] or {}
        h[#h+1] = c[i]
        _System.headers[curr]=h
      end
    end
  end

  local filters={}
  for i=1,_System.headers['properties'] and #_System.headers['properties'] or 0 do
    local id,name = _System.headers['properties'][i]:match("(%d+)%s+([%a]+)")
    if id and id ~="" and name and name~="" then filters['property'..id..name]=true end
  end
  for i=1,_System.headers['globals'] and #_System.headers['globals'] or 0 do
    local name = _System.headers['globals'][i]:match("([%w]+)")
    if name and name ~="" then filters['global'..name]=true end
  end
  for i=1,_System.headers['events'] and #_System.headers['events'] or 0 do
    local id,t = _System.headers['events'][i]:match("(%d+)%s+(%a+)")
    if id and id~="" and t and t~="" then filters['event'..id..t]=true end
  end
  filters['autostart']=true
  filters['other']=true
  _System._filters = filters
  _System._getFilter = {
    autostart=function(env) return '' end,
    other=function(env) return '' end,
    property=function(env) return (env.deviceID or -1)..(env.propertyName or 'value') end,
    global=function(env) return env.name or "%UNKNOWN%" end,
    event=function(env) 
      if env.env == nil then return "%UNKNOW%" end
      local name,id = env.env.type or "%UNKNOW%","%UNKNOW%"
      if env.env.data == nil then return "%UNKNOW%" end
      if name=='CentralSceneEvent' then id=env.env.data.deviceId
      elseif name=='CentralSceneEvent' then id=env.env.data.id end
      return id..name
    end}
  function _System.filterEvent(ev)
    if not _System._getFilter[ev.type] then return false end
    local p = _System._getFilter[ev.type](ev)
    p = _System._filters[ev.type..p]
    return p
  end
end

------------------ Net functions ------------------------
net = {} -- An emulation of Fibaro's net.HTTPClient
-- It is synchronous, but synchronous is a speciell case of asynchronous.. :-)
function net.HTTPClient() return _HTTP end
_HTTP = {}
-- Not sure I got all the options right..
function _HTTP:request(url,options)
  local resp = {}
  local req = options.options
  req.url = url
  req.headers = req.headers or {}
  req.sink = ltn12.sink.table(resp)
  if req.data then
    req.headers["Content-Length"] = #req.data
    req.source = ltn12.source.string(req.data)
  end
  local response, status, headers
  if url:lower():match("^https") then
    response, status, headers = https.request(req)
  else 
    response, status, headers = http.request(req)
  end
  if response == 1 then 
    options.success({status=status, headers=headers, data=table.concat(resp)})
  else
    options.error(status)
  end
end

api={} -- Emulation of api.get/put/post
local function apiCall(method,call,data,cType)
  local resp = {}
  local req={ method=method,
    url = "http://"..hc2_ip.."/api"..call,sink = ltn12.sink.table(resp),
    user=hc2_user,
    password=hc2_pwd,
    headers={}
  }
  if data then
    req.headers["Content-Type"] = cType
    req.headers["Content-Length"] = #data
    req.source = ltn12.source.string(data)
  end
  local r, c = http.request(req)
  if not r then
    Log(LOG.ERROR,"Error connnecting to HC2: '%s' - URL: '%s'.",c,req.url)
    os.exit(1)
  end
  if c>=200 and c<300 then
    return resp[1] and json.decode(table.concat(resp)) or nil
  end
  Log(LOG.ERROR,"HC2 returned error '%d %s' - URL: '%s'.",c,resp[1],req.url)
  os.exit(1)
end

function api.get(call) return apiCall("GET",call) end
function api.put(call, data) return apiCall("PUT",call,json.encode(data),"application/json") end
function api.post(call, data) return apiCall("POST",call,json.encode(data),"application/json") end

-----------------------------------------------------------

function fibaro:sleep(n)
  local c = coroutine.running()
  --print("THREAD:"..tostring(c))
  if c == MAINTHREAD then
    socket.sleep(math.floor(0.5+n/1000))
  else
    return coroutine.yield(c,n/1000)
  end
end

local _gTimers = nil

local function insertCoroutine(co)
  if _gTimers == nil then _gTimers=co
  elseif co.time < _gTimers.time then
    _gTimers,co.next=co,_gTimers
  else
    local tp = _gTimers
    while tp.next and tp.next.time < co.time do tp=tp.next end
    co.next,tp.next=tp.next,co
  end
  return co.co
end

function setTimeout(fun,time,name,cleanup)
  time = (time or 0)/1000+osTimeFrac()
  local co = coroutine.create(fun)
  return insertCoroutine({co=co,time=time,name=name,cleanup=cleanup})
end

function clearTimeout(timer)
  if timer==nil then return end
  if _gTimers == timer then
    _gTimers = _gTimers.next
  else
    local tp = _gTimers
    while tp and tp.next do
      if tp.next == timer then tp.next = timer.next return end
      tp = tp.next
    end
  end
end

function _System.dumpTimers()
  local t = _gTimers
  while t do printf("Timer %s at %s",t.name,osOrgDate("%X",t.time)) t=t.next end
end

function osTime(t) return math.floor(osTimeFrac(t)+0.5) end
function osETime() return _eTime end
function osTimeFrac(t) return t and osOrgTime(t) or _gTime end
function osDate(f,t) return osOrgDate(f,t or osTime()) end
_gTime = osOrgTime()
_gOrgTime = _gTime
_eTime=_gTime+(_SPEEDTIME or 24*60)*3600  -- default to 2 months

WAITINDEX=(_SPEEDTIME and "SPEED" or "NORMAL")..(_GUI and "GUI" or "")

_System.waitFor={
  ["SPEED"] = function(t) _gTime=_gTime+t return false end,
  ["NORMAL"] = function(t) socket.sleep(t) _gTime=_gTime+t return false end,
  ["SPEEDGUI"] = true,
  ["NORMALGUI"] = true
}

function _System.setTime(start,stop)
  if type(start)=='number' then
    stop = start
    start = osOrgDate("%X")
  elseif type(start)=='string' then
    if type(stop)~='number' then stop=60*24*3600 end -- default to 2 month
  end
  local h,m,s = start:match("(%d+):(%d+):?(%d*)")
  local d = osOrgDate("*t")
  d.hour,d.min,d.sec=h,m,s and s~="" and s or 0
  _gTime=osOrgTime(d)
  _gOrgTime = _gTime
  _eTime=_gTime+stop*3600
  _ANNOUNCEDTIME = true
  Debug(true,"Starting:%s, Ending:%s %s",osDate("%x %X",osTime()),osDate("%x %X",osETime()),_SPEEDTIME and "(speeding)" or "")
  Log(LOG.SYSTEM,"Starting time:%s, Ending time:%s",osOrgDate("%x %X",_gTime),osOrgDate("%x %X",_eTime))
end

function _System.runTimers()
  if _gsSt then _gTime=_gTime+(osOrgTime()-_gsSt) _gsSt=nil end -- Sleeping with wxWidget timers
  while _gTimers ~= nil do
    --_System.dumpTimers()
    local co,now = _gTimers,osTimeFrac()
    if co.time > now then
      if _System.waitFor[WAITINDEX](co.time-now) then return end
    end
    _gTimers=_gTimers.next
    local stat,thread,time=coroutine.resume(co.co)
    if not stat then
      Log(LOG.ERROR,"Error in timer:%s %s",co.name or tostring(co.co),tojson(thread))
    end
    if time~='%%ABORT%%' and coroutine.status(co.co)=='suspended' then
      co.time,co.next=osTimeFrac()+time,nil
      --printf("Calling %s",co.name)
      insertCoroutine(co)
    elseif co.cleanup then co.cleanup() end
  end
  if _GUI then 
    _System.waitFor[WAITINDEX](1/1000)
  else
    printf("%s:End of timers",osOrgDate("%X",osTime()))
  end
end

function _System.exitMain() 
  os.exit()
end

function _System.checkMaxTime()
  --printf("gTime:%s, eTime:%s",osOrgDate("%X",_gTime),osOrgDate("%X",_eTime))
  if _gTime > _eTime then
    printf("Max time (_speedtime), %s hours, reached, exiting",(_eTime -_gOrgTime)/3600)
    EventEngine,ScriptEngine,ScriptCompiler,RuleEngine,Util=nil,nil,nil,nil,nil
    collectgarbage("collect") 
    print(_format("Memory start-end:%.2f",collectgarbage("count")-GC))
    _System.exitMain()
  end
  setTimeout(_System.checkMaxTime,1000*3600,"Check")
end

------------------------ Emulated fibaro calls ----------------------
if not _REMOTE then
-- Simple simulation of fibaro functions when offline...
-- Good enough for simple debugging
  -- caching fibaro:setValue to return right value when calling fibaro:getValue
  fibaro._fibaroCalls = {['1sunsetHour'] = {"18:00",osOrgTime()}, ['1sunriseHour'] = {"06:00",osOrgTime()}}
  fibaro._globals = {}

  function fibaro:countScenes() return _SCENECOUNT end
  function fibaro:abort()
    local c = coroutine.running()
    if c == MAINTHREAD then
      os.exit(1)
    else
      return coroutine.yield(c,'%%ABORT%%')
    end
  end
  function fibaro:getName(id) return _format("DEVICE:%s",id) end
  function fibaro:getRoomNameByDeviceID(id) return _format("ROOMFORDEVICE:%s",id) end

  if not Util then
    Util = { reverseVar = function(id) return id end, prettyEncode = function(j) return json.encode(j) end  }
  end

  _simFuns = {}
  _simFuns['property'] = function(e) 
    fibaro._fibaroCalls[e.deviceID..(e.propertyName or 'value')] = {e.value and tostring(e.value) or '0',osTime()} 
  end
  _simFuns['global'] = function(e) fibaro._globals[e.name] = {e.value and tostring(e.value) or nil, osTime()} end

  function _getIdProp(id,prop)
    local keyid = id..prop
    local v = fibaro._fibaroCalls[keyid] or {'0',osTime()}
    fibaro._fibaroCalls[keyid] = v
    return table.unpack(v)
  end

  function fibaro:get(id,prop) return _getIdProp(id,prop) end
  function fibaro:getValue(id,prop) return (_getIdProp(id,prop)) end

  function _getGlobal(name)
    fibaro._globals[name] = fibaro._globals[name] or {nil,osTime()}
    return table.unpack(fibaro._globals[name])
  end

  function Util.defineGlobals(args) for var,val in pairs(args) do fibaro._globals[var] = {tostring(val),osTime()} end end

  function Util.getComment(str) 
    local f = io.open(debug.getinfo(2).short_src) 
    local src = f:read("*all")
    return src:match("--%[%[[%s%c]*"..str.."(.*)"..str.."%-%-%]%]")
  end

  function fibaro:getGlobal(name) return _getGlobal(name) end
  function fibaro:getGlobalValue(name) return (_getGlobal(name)) end
  function fibaro:getGlobalModificationTime(name) return select(2,_getGlobal(name)) end
  function fibaro:setGlobal(name,value) _setGlobal(name,value) end

  function _setGlobal(name,value)
    if value ~= nil then value = tostring(value) end
    if fibaro._globals[name] == nil or fibaro._globals[name][1] ~= value then
      local ev = {type='global', name=name, value=x, _sh=true} -- If global changes value, fibaro send back event to scene
      if Event then if Event.post then Event.post(ev) end else setTimeout(function() main(ev) end,0) end
    end
    fibaro._globals[name] = {value,osTime and osTime() or osOrgTime()}
  end

  fibaro._getDevicesId =  {133, 136, 139, 263, 304, 309, 333, 341} -- Should be more advanced...
  function fibaro:getDevicesId(s) return fibaro._getDevicesId end

  function fibaro:startScene(id,args)
    Event.post({type='%INTERNAL%', name='startScene', id=id, val=args, _sh=true})
  end
  function fibaro:killScenes(id) end

  function setAndPropagate(id,key,value)
    local idKey = id..key
    if not fibaro._fibaroCalls[idKey] or fibaro._fibaroCalls[idKey][1] ~= value then
      local ev = {type='property', deviceID=id, propertyName=key, value=value, _sh=true}
      if Event then Event.post(ev) else setTimeout(function() main(ev) end,0) end
    end
    fibaro._fibaroCalls[idKey] = {value,osTime()}
  end

  _specCalls={}
  _specCalls['setProperty'] = function(id,prop,...) setAndPropagate(id,prop,({...})[1]) end 
  _specCalls['setColor'] = function(id,R,G,B) fibaro._fibaroCalls[id..'color'] = {{R,G,B},osTime()} end
  _specCalls['setArmed'] = function(id,val) fibaro._fibaroCalls[id..'armed'] = {val,osTime()} end
  _specCalls['sendPush'] = function(id,msg) end -- log to console?
  _specCalls['pressButton'] = function(id,msg) end -- simulate VD?
  _specCalls['setPower'] = function(id,value) setAndPropagate(id,"power",value) end

  function fibaro:call(id,prop,...)
    if _specCalls[prop] then _specCalls[prop](id,...) return end 
    local value = ({turnOff="0",turnOn="99",on="99",off="0"})[prop] or (prop=='setValue' and tostring(({...})[1]))
    if not value then error(_format("fibaro:call(..,'%s',..) is not supported, fix it!",prop)) end
    setAndPropagate(id,'value',value)
  end

end

--------------------------- GUI -------------------------------

if _GUI then

  local function _sortE(a,b)
    if a:match("^{type:'autostart") then a = '<'..a end
    if a:match("^{type:'other") then a = '>'..a end
    if b:match("^{type:'autostart") then b = '<'..b end
    if b:match("^{type:'other") then b = '>'..b end
    return a < b
  end

  local function buildChoices()
    local choices = {}
    for i=1,_System.headers['properties'] and #_System.headers['properties'] or 0 do
      local id = _System.headers['properties'][i]:match("(%d+)%s+value")
      if id and id ~="" then 
        choices[#choices+1] = _format("{type:'property',deviceID:%s,value:'1'}",id)
      end
    end
    for i=1,_System.headers['globals'] and #_System.headers['globals'] or 0 do
      local name = _System.headers['globals'][i]:match("(%w+)")
      if name and name ~="" then 
        choices[#choices+1] = _format("{type:'global',name:'%s',value:''}",name)
      end
    end
    for i=1,_System.headers['events'] and #_System.headers['events'] or 0 do
      local id,t = _System.headers['events'][i]:match("(%d+)%s+(%a+)")
      if t and t=='sceneActivation' then
        choices[#choices+1]=_format("{type:'property',deviceID=%s,propertyName:'sceneActivation'}",id)
      elseif t and t=='CentralSceneEvent' then
        choices[#choices+1]=_format("{type:'event',event:{type:'CentralSceneEvent',data:{deviceId:%s,keyId:'1',keyAttribute:'Pressed'}}}",id)
      elseif t and t=='AccessControlEvent' then
        choices[#choices+1]=_format("{type:'event',event:{type:'AccessControlEvent',data:{id:%s,name:'Smith',slotId:'99',status:'Lock'}}}",id)
      end
    end
    choices[#choices+1]="{type:'autostart'}"
    choices[#choices+1]="{type:'other'}"
    json.decode("{type:'autostart'}")
    table.sort(choices,_sortE)
    return choices
  end

  require("wx")
  UI = {}
  UI.MyFrame2 = wx.wxFrame (wx.NULL, wx.wxID_ANY, "EventRunner", wx.wxDefaultPosition, wx.wxSize( 459,453 ), wx.wxCAPTION + wx.wxCLOSE_BOX + wx.wxMAXIMIZE_BOX + wx.wxMINIMIZE_BOX + wx.wxRESIZE_BORDER+wx.wxTAB_TRAVERSAL +wx.wxSTAY_ON_TOP )
  UI.MyFrame2:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )

  UI.bSizer1 = wx.wxBoxSizer( wx.wxVERTICAL )

  UI.bSizer3 = wx.wxBoxSizer( wx.wxVERTICAL )

  UI.bSizer4 = wx.wxBoxSizer( wx.wxHORIZONTAL )

  UI.m_staticText21 = wx.wxStaticText( UI.MyFrame2, wx.wxID_ANY, "Start", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.m_staticText21:Wrap( -1 )

  UI.bSizer4:Add( UI.m_staticText21, 0, wx.wxALL, 5 )

  UI.m_textCtrlStart = wx.wxTextCtrl( UI.MyFrame2, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.m_textCtrlStart:SetMinSize( wx.wxSize( 130,-1 ) )

  UI.bSizer4:Add( UI.m_textCtrlStart, 0, wx.wxALL, 5 )

  UI.m_staticText3 = wx.wxStaticText( UI.MyFrame2, wx.wxID_ANY, "Stop", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.m_staticText3:Wrap( -1 )

  UI.bSizer4:Add( UI.m_staticText3, 0, wx.wxALL, 5 )

  UI.m_textCtrlStop = wx.wxTextCtrl( UI.MyFrame2, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.m_textCtrlStop:SetMinSize( wx.wxSize( 130,-1 ) )

  UI.bSizer4:Add( UI.m_textCtrlStop, 0, wx.wxALL, 5 )

  UI.m_checkBoxSpeed = wx.wxCheckBox( UI.MyFrame2, wx.wxID_ANY, "Real-time", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.bSizer4:Add( UI.m_checkBoxSpeed, 0, wx.wxALL, 5 )


  UI.bSizer3:Add( UI.bSizer4, 1, wx.wxEXPAND, 5 )

  UI.bSizer5 = wx.wxBoxSizer( wx.wxHORIZONTAL )

  UI.m_buttonRun = wx.wxButton( UI.MyFrame2, wx.wxID_ANY, "Run>", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.bSizer5:Add( UI.m_buttonRun, 0, wx.wxALL, 5 )

  UI.m_buttonRun1 = wx.wxButton( UI.MyFrame2, wx.wxID_ANY, "1h>", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.bSizer5:Add( UI.m_buttonRun1, 0, wx.wxALL, 5 )

  UI.m_buttonRun24 = wx.wxButton( UI.MyFrame2, wx.wxID_ANY, "24h>", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.bSizer5:Add( UI.m_buttonRun24, 0, wx.wxALL, 5 )

  UI.bSizer3:Add( UI.bSizer5, 1, wx.wxEXPAND, 5 )

  local choices=buildChoices()

  UI.m_listBox1Choices = choices
  UI.m_listBox1 = wx.wxListBox( UI.MyFrame2, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, UI.m_listBox1Choices, 0 )
  UI.bSizer3:Add( UI.m_listBox1, 100, wx.wxALL + wx.wxEXPAND, 5 )


  UI.bSizer1:Add( UI.bSizer3, 1, wx.wxEXPAND, 5 )

  UI.bSizer2 = wx.wxBoxSizer( wx.wxHORIZONTAL )

  UI.m_staticText2 = wx.wxStaticText( UI.MyFrame2, wx.wxID_ANY, "Value:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.m_staticText2:Wrap( -1 )

  UI.bSizer2:Add( UI.m_staticText2, 0, wx.wxALIGN_CENTER, 5 )

  UI.m_textCtrl1 = wx.wxTextCtrl( UI.MyFrame2, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.bSizer2:Add( UI.m_textCtrl1, 100, wx.wxALIGN_BOTTOM + wx.wxALL, 5 )


  UI.bSizer1:Add( UI.bSizer2, 0, wx.wxEXPAND, 5 )


  UI.MyFrame2:SetSizer( UI.bSizer1 )
  UI.MyFrame2:Layout()

  UI.MyFrame2:Centre( wx.wxBOTH )

  UI.MyFrame2:Raise();  -- bring window to front
  UI.MyFrame2:SetFocus(); -- show the window
-- Connect Events

  UI.MyFrame2:Connect( wx.wxEVT_CLOSE_WINDOW, function(event)
      --implements CloseWindow
      if gstimer then gstimer:Stop() end
      wx.wxGetApp():ExitMainLoop()
      --fibaro:abort()
      event:Skip()
    end )

  UI.m_textCtrlStart:Connect( wx.wxEVT_COMMAND_TEXT_ENTER, function(event)
      --implements m_textCtrlStartOnTextEnter

      event:Skip()
    end )

  UI.m_textCtrlStop:Connect( wx.wxEVT_COMMAND_TEXT_ENTER, function(event)
      --implements m_textCtrl3OnTextEnter

      event:Skip()
    end )

  UI.m_checkBoxSpeed:Connect( wx.wxEVT_COMMAND_CHECKBOX_CLICKED, function(event)
      --implements m_checkBoxRTOnCheckBox
      event:Skip()
    end )

  UI.m_buttonRun:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
      --implements m_button2OnButtonClick

      event:Skip()
    end )

  UI.m_buttonRun1:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
      --implements m_buttonRun1OnButtonClick

      event:Skip()
    end )

  UI.m_buttonRun24:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
      --implements m_buttonRun24OnButtonClick

      event:Skip()
    end )

  UI.m_listBox1:Connect( wx.wxEVT_LEFT_DCLICK, function(event)
      --implements PostEvent
      local i = UI.m_listBox1:GetSelection()
      if i >= 0 then
        local str = UI.m_listBox1:GetString(i)
        local value,ev = pcall(function() return json.decode(str) end)
        if value and ev.type=='property' and ev._sensor then
          local ev2 = _copy(ev)
          ev2.value='0'
          Event.post(ev2,ev._sensor)
          ev._sensor=nil
        end
        if value and Event then
          Event.post(ev)
        elseif value then
          setTimeout(function() main(ev) end,0)
        end
        if not value then Log(LOG.ERROR,"Bad event format: %s",str) end
      end
      if _SPEEDTIME then
        gstimer:Start(1,wx.wxTIMER_ONE_SHOT )
      end
      event:Skip()
    end )

  UI.m_listBox1:Connect( wx.wxEVT_LEFT_UP, function(event)
      --implements SelectEvent
      local i = UI.m_listBox1:GetSelection()
      if i >= 0 then 
        str = UI.m_listBox1:GetString(i)
        UI.m_textCtrl1:SetValue(str)
      end
      event:Skip()
    end )

  local function _removeSelection()
    local i = UI.m_listBox1:GetSelection()
    if i >= 0 then
      local str = UI.m_listBox1:GetString(i)
      for i=1,#choices do if choices[i]==str then table.remove(choices,i) end end
      UI.m_listBox1:Delete(i)
    end
  end

  UI.m_listBox1:Connect( wx.wxEVT_KEY_UP, function(event)
      --implements KeyUp
      local c = event:GetKeyCode()
      if c == 8 then _removeSelection() end
      event:Skip()
    end )

  UI.m_textCtrl1:Connect( wx.wxEVT_CHAR, function(event)
      --implements charEnter
      local c = event:GetKeyCode()
      if c == 13 then
        local str = UI.m_textCtrl1:GetValue()
        for _,s in ipairs(choices) do
          if s==str then event:Skip(); return end
        end
        UI.m_listBox1:Clear()
        choices[#choices+1]=str
        table.sort(choices,_sortE)
        UI.m_listBox1:InsertItems(choices,0)
      elseif c == 8 then
        _removeSelection()
      end
      event:Skip()
    end )

  UI.m_textCtrlStart:SetValue(osDate("%x %X"))
  UI.m_textCtrlStop:SetValue(osDate("%x %X",osETime()))
  UI.m_checkBoxSpeed:SetValue(_SPEEDTIME and true)

  UI.m_buttonRun:Disable()
  UI.m_buttonRun1:Disable()
  UI.m_buttonRun24:Disable()
  UI.m_checkBoxSpeed:Disable()
  UI.m_textCtrlStop:Disable()
  UI.m_textCtrlStart:Disable()

  gstimer = nil

  _System.waitFor={
    ["SPEED"] = function(t) _gTime=_gTime+t return false end,
    ["NORMAL"] = function(t) socket.sleep(t) _gTime=_gTime+t return false end,
    ["SPEEDGUI"] = function(t) gstimer:Stop() gstimer:Start(1,wx.wxTIMER_ONE_SHOT) _gTime=_gTime+1 return true end,
    ["NORMALGUI"] = function(t) gstimer:Stop() _gsSt=osOrgTime(); gstimer:Start(1000*t,wx.wxTIMER_ONE_SHOT) return true end
  }

  function _System.pokeTimerQueue() gstimer:Stop() gstimer:Start(1,wx.wxTIMER_ONE_SHOT) end

  UI.MyFrame2:Connect(wx.wxEVT_TIMER, _System.runTimers) 

  UI.MyFrame2:Restore(); -- restore the window if minimized
  UI.MyFrame2:Iconize(false); -- show the window
  UI.MyFrame2:SetFocus(); -- show the window
  UI.MyFrame2:Raise();  -- bring window to front
  UI.MyFrame2:Show(true);  -- bring window to front

  function _System.exitMain() gstimer:Stop() wx.wxGetApp():ExitMainLoop() end
end

------------------- Sunset/Sunrise ---------------
-- \fibaro\usr\share\lua\5.2\common\lustrous.lua ﻿based on the United States Naval Observatory
function sunturn_time(date, rising, latitude, longitude, zenith, local_offset)
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
    local range = max - min
    local count
    if val < min then
      count = floor((min - val) / range) + 1
      return val + count * range
    elseif val >= max then
      count = floor((val - max) / range) + 1
      return val - count * range
    else
      return val
    end
  end

  local n = day_of_year(date)

  -- Convert the longitude to hour value and calculate an approximate time
  local lng_hour = longitude / 15

  local t
  if rising then -- Rising time is desired
    t = n + ((6 - lng_hour) / 24)
  else -- Setting time is desired
    t = n + ((18 - lng_hour) / 24)
  end

  -- Calculate the Sun^s mean anomaly
  local M = (0.9856 * t) - 3.289

  -- Calculate the Sun^s true longitude
  local L = fit_into_range(M + (1.916 * sin(M)) + (0.020 * sin(2 * M)) + 282.634, 0, 360)

  -- Calculate the Sun^s right ascension
  local RA = fit_into_range(atan(0.91764 * tan(L)), 0, 360)

  -- Right ascension value needs to be in the same quadrant as L
  local Lquadrant = floor(L / 90) * 90
  local RAquadrant = floor(RA / 90) * 90
  RA = RA + Lquadrant - RAquadrant

  -- Right ascension value needs to be converted into hours
  RA = RA / 15

  -- Calculate the Sun^s declination
  local sinDec = 0.39782 * sin(L)
  local cosDec = cos(asin(sinDec))

  -- Calculate the Sun^s local hour angle
  local cosH = (cos(zenith) - (sinDec * sin(latitude))) / (cosDec * cos(latitude))

  if rising and cosH > 1 then
    return "N/R" -- The sun never rises on this location on the specified date
  elseif cosH < -1 then
    return "N/S" -- The sun never sets on this location on the specified date
  end

  -- Finish calculating H and convert into hours
  local H
  if rising then
    H = 360 - acos(cosH)
  else
    H = acos(cosH)
  end
  H = H / 15

  -- Calculate local mean time of rising/setting
  local T = H + RA - (0.06571 * t) - 6.622

  -- Adjust back to UTC
  local UT = fit_into_range(T - lng_hour, 0, 24)

  -- Convert UT value to local time zone of latitude/longitude
  local LT = UT + local_offset

  return osTime(
    {
      day = date.day,
      month = date.month,
      year = date.year,
      hour = floor(LT),
      min = math.modf(frac(LT) * 60)
    }
  )
end

local function get_timezone()
  local now = osTime()
  return os.difftime(now, osTime(osDate("!*t", now)))
end

function sunCalc()
  local lat = fibaro:getValue(2, "Latitude") or _LATITUDE
  local lon = fibaro:getValue(2, "Longitude") or _LONGITUDE
  local utc = get_timezone() / 3600

  local zenith = 90.83 -- sunset/sunrise 90°50′
  local zenith_twilight = 96.0 -- civil twilight 96°0′

  local date = osDate("*t")
  if date.isdst then
    utc = utc + 1
  end

  local rise_time = osDate("*t", sunturn_time(date, true, lat, lon, zenith, utc))
  local set_time = osDate("*t", sunturn_time(date, false, lat, lon, zenith, utc))

  local rise_time_t = osDate("*t", sunturn_time(date, true, lat, lon, zenith_twilight, utc))
  local set_time_t = osDate("*t", sunturn_time(date, false, lat, lon, zenith_twilight, utc))

  local sunrise = string.format("%.2d:%.2d", rise_time.hour, rise_time.min)
  local sunset = string.format("%.2d:%.2d", set_time.hour, set_time.min)

  local sunrise_t = string.format("%.2d:%.2d", rise_time_t.hour, rise_time_t.min)
  local sunset_t = string.format("%.2d:%.2d", set_time_t.hour, set_time_t.min)

  return sunrise, sunset, sunrise_t, sunset_t
end

------------------------------------------------------

function _System.runOffline(setup)
  if _SPEEDTIME then
    setTimeout(_System.checkMaxTime,1000*3600,"Check")
  end
  if _GUI then
    if setup then setup() end
    gstimer = wx.wxTimer(UI.MyFrame2)
    if not _SPEEDTIME then
      _gsSt=nil
      gstimer:Start(1,wx.wxTIMER_ONE_SHOT )
    end
    wx.wxGetApp():MainLoop()
  else
    if setup then setup() end
    _System.runTimers()
  end
end

---- Remote server support ------------------

function _System.startServer(port)
  local someRandomIP = "192.168.1.122" --This address you make up
  local someRandomPort = "3102" --This port you make up  
  local mySocket = socket.udp() --Create a UDP socket like normal
  mySocket:setpeername(someRandomIP,someRandomPort) 
  local myDevicesIpAddress, somePortChosenByTheOS = mySocket:getsockname()-- returns IP and Port 
  local host = myDevicesIpAddress
  Log(LOG.SYSTEM,"Remote Event listener started at %s:%s",host,port)
  local s,c,err = assert(socket.bind("*", port))
  local i, p = s:getsockname()
  assert(i, p)
  return function()
    local co = coroutine.running()
    while true do
      s:settimeout(0)
      repeat
        c, err = s:accept()
        if err == 'timeout' then coroutine.yield(co,_POLLINTERVAL/1000) end
      until err ~= 'timeout'
      c:settimeout(0)
      repeat
        local l, e, j = c:receive()
        if l and l:sub(1,3)=='GET' then
          j=l:match("GET[%s%c]*/(.*)HTTP/1%.1$")
          j = urldecode(j)
          j=json.decode(j) j._sh=true
          Event.post(j)
        elseif j and j~="" then
          --c:close()
          j = urldecode(j)
          if _debugFlags.node_red then Debug(true,"Node_red:%s",j) end
          j=json.decode(j) j._sh=true
          Event.post(j)
        end
        --coroutine.yield(co,_POLLINTERVAL/1000)
      until (j and j~="") or e == 'closed'
    end
  end
end

if _PORTLISTENER then
  setTimeout(_System.startServer(_PORT),100)
end

------------------ Test ---------------------
if nil then

  function scene(arg,delay)
    for i=1,10 do
      printf("%s:Scene(%s)",osOrgDate("%X",osTime()),arg)
      fibaro:sleep(1000*delay)
    end
  end

  setTimeout(function() scene("A",5) end,nil,"A") 
  setTimeout(function() scene("B",10) end,nil,"B")
  _System.runOffline(nil)
end