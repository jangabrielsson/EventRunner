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

if _version ~= "1.0" then error("Bad version of EventRunnerDebug") end 
_SPEEDTIME         = 48*4   -- nil run the local clock in normal speed, set to an int <x> will speed the clock through <x> hours
_REMOTE            = false  -- If true use FibaroSceneAPI to call functions on HC2, else emulate them locally...
_GUI               = true

-- Server parameters
_PORTLISTENER      = false
_POLLINTERVAL      = 500 
_PORT              = 6872
_MEM               = false  -- log memory usage

-- HC2 credentials and parameters
hc2_user           = "xxx" -- used for api.x/FibaroSceneAPI calls
hc2_pwd            = "xxx" 
hc2_ip             = "192.168.1.69" -- IP of HC2
local creds = loadfile("credentials.lua") -- To not accidently commit credentials to Github...
if creds then creds() end

__fibaroSceneId    = 32     -- Set to scene ID. On HC2 this variable is defined

--- Don't touch --------------------------------------------------

_OFFLINE           = true          -- Always true if we include this file (e.g. not running on the HC2)
_HC2               = not _OFFLINE  -- Always false if we include this file
--_ENV               = 
mime = require('mime')
https = require ("ssl.https")
ltn12 = require("ltn12")
json = require("json")
socket = require("socket")
http = require("socket.http")
fibaro = {}
if _REMOTE then
  require ("FibaroSceneAPI") 
end
_ENV = _ENV or _G or {}
_debugLevel = _debugLevel or 3
_FDEB = 1 -- 0: no debug, 1: log calls, 2: log everything
function fibaro:getSourceTrigger() return {type = "autostart"} end

_format = string.format
_FIB={}
function _FIB:get(id,prop) local s,_FDEB=_FDEB,0; local v,t = fibaro:get(id,prop) _FDEB=s; return v,t end
function _FIB:getGlobal(id) local s,_FDEB=_FDEB,0; local v,t = fibaro:getGlobal(id) _FDEB= s; return v,t end

function _Msg(level,color,message,...)
  if (_debugLevel >= level) then
    local args = type(... or 42) == 'function' and {(...)()} or {...}
    message = string.format(message,table.unpack(args))
    local gc = _MEM and _format("mem:%-6.1f ",collectgarbage("count")) or ""
    fibaro:debug(string.format("%s%s %s",gc,os.date("%a %b %d %X",osTime()),message)) 
    return message
  end
end
function Debug(level,message,...) _Msg(level,DEBUGCOLOR,message,...) end
LOG = {WELCOME = "orange",DEBUG = "white", SYSTEM = "Cyan", LOG = "green", ERROR = "Tomato"}
function Log(color,message,...) return _Msg(-100,color,message,...) end

function split(s, sep)
  local fields = {}
  sep = sep or " "
  local pattern = string.format("([^%s]+)", sep)
  string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
  return fields
end

_timeAdjust = nil

function _setUpSpeedTime() -- Special version of time functions
  local _startTime = os.time()
  local _maxTime = _startTime + _SPEEDTIME*60*60
  local _sleep = 0
  function exceededTime()
    return _startTime+_sleep+(os.time()-_startTime) > _maxTime
  end
  function osDate(p,t) return t and os.date(p,t) or osDate(p,osTime()) end
  function osTime(arg1)
    if arg1 then return os.time(arg1) end
    local t = _startTime+_sleep+(os.time()-_startTime)
    return t+(_timeAdjust or 0)
  end
  function fibaro:sleep(n) 
    _sleep = _sleep + n/1000 --math.floor(n/1000) 
  end
  function _setClock(t) _timeAdjust = _timeAdjust or toTime(t)-osTime() end -- 
  function _setMaxTime(t) _maxTime = _startTime + t*60*60 end -- hours
end

osTime = function(arg) return arg and os.time(arg) or os.time()+(_timeAdjust or 0) end
function fibaro:sleep(n)  
  local t = osTime()+n/1000
  while(osTime() < t) do end -- busy wait
end
function _setClock(_)  end
function _setMaxTime(_) end -- hours

_timers = nil

function setTimeout(fun,time,doc)
  assert(type(fun)=='function' and type(time)=='number',"Bad arguments to setTimeout")
  local cp = {time=osTime()+time/1000,fun=fun,doc=doc,next=nil}
  if _timers == nil then _timers = cp
  elseif cp.time < _timers.time then cp.next = _timers; _timers = cp
  else
    local tp = _timers
    while tp.next do
      if cp.time < tp.next.time then cp.next = tp.next; tp.next = cp; return cp end
      tp = tp.next
    end
    tp.next = cp
  end
  return cp
end

function clearTimeout(ref)
  if ref and _timers == ref then
    _timers = _timers.next
  elseif ref then
    local tp = _timers
    while tp.next do
      if tp.next == ref then tp.next = ref.next return end
      tp = tp.next
    end
  end
end

if not _System then _System = {} end

function _System.dumpTimers()
  local t = _timers
  while t do
    print(_format("%s time:%s",t.doc,t.time))
    t = t.next
  end
end

function _System.countTimers()
  local t,c = _timers,0
  while t do c=c+1 t=t.next end
  return c
end

function _System.runTimers()
  while _timers ~= nil do
    if exceededTime() then
      print(_format("Max time (_speedtime), %s hours, reached, exiting",_SPEEDTIME))
      EventEngine,ScriptEngine,ScriptCompiler,RuleEngine,Util=nil,nil,nil,nil,nil
      collectgarbage("collect") 
      print(_format("Memory start-end:%.2f",collectgarbage("count")-GC))
      os.exit() 
    end
    local l = _timers.time-osTime()
    Debug(5,"Next timer %s at %s sleeping %ss",_timers.doc,osDate("%X",_timers.time),l)
    if l > 0 then
      fibaro:sleep(1000*l) 
    end
    local f = _timers.fun
    _timers = _timers.next
    f()
  end
  Debug(0,"No timmers left - exiting!")
end

function _System.setTimer(fun,time,doc) return setTimeout(fun,time,doc) end

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

if not _REMOTE then
-- Simple simulation of fibaro functions when offline...
-- Good enough for simple debugging
  -- caching fibaro:setValue to return right value when calling fibaro:getValue
  fibaro._fibaroCalls = {['1sunsetHour'] = {"18:00",os.time()}, ['1sunriseHour'] = {"06:00",os.time()}}
  fibaro._globals = {}

  function fibaro:debug(str) print(str) end
  function fibaro:countScenes() return 1 end
  function fibaro:abort() os.exit() end

  if not Util then
    Util = { reverseVar = function(id) return id end, prettyEncode = function(j) return json.encode(j) end  }
  end

  _simFuns = {}
  _simFuns['property'] = function(e) 
    fibaro._fibaroCalls[e.deviceID..(e.propertyName or 'value')] = {tostring(e.value),osTime()} 
  end
  _simFuns['global'] = function(e) fibaro._globals[e.name] = {e.value, osTime()} end

  function fibaro:get(id,prop)
    Debug((_FDEB > 1) and 1 or 10,"fibaro:get('%s','%s')",Util.reverseVar(id),prop)
    local keyid = id..prop
    local v = fibaro._fibaroCalls[keyid] or {'0',osTime()}
    fibaro._fibaroCalls[keyid] = v
    return table.unpack(v)
  end

  function fibaro:getValue(id,prop) return (fibaro:get(id,prop)) end

  function fibaro:getGlobal(id) 
    Debug((_FDEB > 1) and 1 or 10,"fibaro:getGlobal('%s')",id) 
    fibaro._globals[id] = fibaro._globals[id] or {"",osTime()}
    return table.unpack(fibaro._globals[id])
  end
  function fibaro:getGlobalValue(id) return (fibaro:getGlobal(id)) end
  function fibaro:getGlobalModificationTime(id) return select(2,fibaro:getGlobal(id)) end

  function fibaro:setGlobal(v,x) 
    Debug((_FDEB > 1) and 1 or 10,"fibaro:setGlobal('%s','%s')",v,x)
    if fibaro._globals[v] == nil or fibaro._globals[v][1] ~= x then
      local ev = {type='global', name=v, value=x, _sh=true}
      if Event then if Event.post then Event.post(ev) end else setTimeout(function() main(ev) end,0) end
    end
    fibaro._globals[v] = {x,osTime and osTime() or os.time()}
  end

  fibaro._getDevicesId =  {133, 136, 139, 263, 304, 309, 333, 341} -- Should be more advanced...
  function fibaro:getDevicesId(s) return fibaro._getDevicesId end

  function fibaro:startScene(id,args) 
    if args then Debug((_FDEB > 0) and 1 or 10,"fibaro:startScene(%s,%s)",Util.reverseVar(id),Util.prettyEncode(args)) 
    else Debug((_FDEB > 0) and 1 or 10,"fibaro:startScene(%s)",Util.reverseVar(id)) end
  end
  function fibaro:killScenes(id) Debug(_FDEB > 0 and 1 or 10,"fibaro:stopScene(%s)",Util.reverseVar(id)) end

  local _callFormat = {
    ["turnOn"] = "fibaro:call(%s,'%s')",
    ["turnOff"] = "fibaro:call(%s,'%s')",
    ["on"] = "fibaro:call(%s,'%s')",
    ["off"] = "fibaro:call(%s,'%s')",
    ["setR"] = "fibaro:call(%s,'%s', '%s')",
    ["setG"] = "fibaro:call(%s,'%s', '%s')",
    ["setB"] = "fibaro:call(%s,'%s', '%s')",
    ["setW"] = "fibaro:call(%s,'%s', '%s')",
    ["setArmed"] = "fibaro:call(%s,'%s', '%s')",
    ["setColor"] = "fibaro:call(%s,'%s', '%s')",
    ["setTime"] = "fibaro:call(%s,'%s', '%s')",
    ["setValue"] = "fibaro:call(%s,'%s', '%s', '%s')",
    ["setProperty"] = "fibaro:call(%s,'%s', '%s', '%s')",
    ["setSlider"] = "fibaro:call(%s,'%s', '%s')",
    ["sendPush"] = "fibaro:call(%s,'%s', '%s')",
    ["pressButton"] = "fibaro:call(%s,'%s', '%s')"
  }
  function fibaro:call(id,prop,val1,val2)
    val1 = tostring(val1 or "")
    val2 = tostring(val2 or "")
    local dstr = _callFormat[prop] or "UNKNOWN"
    dstr = _format(dstr,Util.reverseVar(id),prop,val1,val2)
    Debug((_FDEB > 0) and 1 or 10,dstr) 
    local idkey = tostring(id)
    local v = ({turnOff="0",turnOn="99",on="99",off="0"})[prop] or (prop=='setValue' and val1)
    if v then prop='value' val1=v end
    if prop == 'value' and (not fibaro._fibaroCalls[idkey..prop] or fibaro._fibaroCalls[idkey..prop][1]~=val1) then
      local ev = {type='property', deviceID=id, propertyName=prop, value=val1, _sh=true}
      if Event then Event.post(ev) else setTimeout(function() main(ev) end,0) end
    end
    fibaro._fibaroCalls[idkey..prop] = {val1,osTime()}
  end

  if _deviceTable then -- If you have a pre-made "HomeTable" structure, set it up here
    local devmap = io.open("devicemap.data", "r") -- local file with json structure
    if devmap then
      fibaro:setGlobal(_deviceTable,devmap:read("*all"))
      local t = fibaro:getGlobal(_deviceTable)
      t = json.decode(t)
      devmap:close()
    end
  end
end
------

if _GUI then
  require("wx")

  UI = {}

-- create MyFrame1
  UI.MyFrame1 = wx.wxFrame (wx.NULL, wx.wxID_ANY, "EventRunner", wx.wxDefaultPosition, wx.wxSize( 535,241 ), wx.wxDEFAULT_FRAME_STYLE+wx.wxTAB_TRAVERSAL )
  UI.MyFrame1:SetSizeHints( wx.wxDefaultSize, wx.wxDefaultSize )

  UI.bSizer1 = wx.wxBoxSizer( wx.wxVERTICAL )

  UI.bSizer2 = wx.wxBoxSizer( wx.wxHORIZONTAL )

  UI.m_button_run = wx.wxButton( UI.MyFrame1, wx.wxID_ANY, "Run", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.bSizer2:Add( UI.m_button_run, 0, wx.wxALL, 10 )

  UI.m_radioBox_timeChoices = { "Real time", "Speed time" }
  UI.m_radioBox_time = wx.wxRadioBox( UI.MyFrame1, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxDefaultSize, UI.m_radioBox_timeChoices, 1, wx.wxRA_SPECIFY_ROWS )
  UI.m_radioBox_time:SetSelection( 0 )
  UI.bSizer2:Add( UI.m_radioBox_time, 0, wx.wxALL, 5 )

  UI.m_staticText1 = wx.wxStaticText( UI.MyFrame1, wx.wxID_ANY, "Hours:", wx.wxPoint( -1,-1 ), wx.wxDefaultSize, 0 )
  UI.m_staticText1:Wrap( -1 )
  UI.bSizer2:Add( UI.m_staticText1, 0, wx.wxALL, 10 )

  UI.m_textCtrl_time = wx.wxTextCtrl( UI.MyFrame1, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.bSizer2:Add( UI.m_textCtrl_time, 0, wx.wxALL, 10 )
  UI.m_textCtrl_time:SetValue(_SPEEDTIME and tostring(_SPEEDTIME) or "")

  UI.bSizer1:Add( UI.bSizer2, 0, wx.wxEXPAND, 5 )

  UI.m_button_stop = wx.wxButton( UI.MyFrame1, wx.wxID_ANY, "Stop", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.bSizer1:Add( UI.m_button_stop, 0, wx.wxALL, 10 )

  UI.m_staticline1 = wx.wxStaticLine( UI.MyFrame1, wx.wxID_ANY, wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxLI_HORIZONTAL )
  UI.bSizer1:Add( UI.m_staticline1, 0, wx.wxEXPAND  + wx. wxALL, 5 )

  UI.bSizer3 = wx.wxBoxSizer( wx.wxHORIZONTAL )

  UI.m_staticText3 = wx.wxStaticText( UI.MyFrame1, wx.wxID_ANY, "Event:", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.m_staticText3:Wrap( -1 )
  UI.bSizer3:Add( UI.m_staticText3, 0, wx.wxALL, 10 )

  UI.m_textCtrl_event = wx.wxTextCtrl( UI.MyFrame1, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.bSizer3:Add( UI.m_textCtrl_event, 1, wx.wxALL, 10 )
  UI.m_textCtrl_event:SetValue("{'type':'CentralSceneEvent','event':{'data':{'keyId':'1'}}}")


  UI.bSizer1:Add( UI.bSizer3, 0, wx.wxEXPAND, 10 )

  UI.m_button_post = wx.wxButton( UI.MyFrame1, wx.wxID_ANY, "Post", wx.wxDefaultPosition, wx.wxDefaultSize, 0 )
  UI.bSizer1:Add( UI.m_button_post, 0, wx.wxALL, 10 )


  UI.MyFrame1:SetSizer( UI.bSizer1 )
  UI.MyFrame1:Layout()

  --UI.MyFrame1:Centre( wx.wxBOTH )

  -- Connect Events
  gstimer = nil
  UI.m_button_run:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
      --implements run
      local realtime = UI.m_radioBox_time:GetSelection()==0
      local speedhours = UI.m_textCtrl_time:GetValue() or "0"
      speedhours = tonumber(speedhours ~= "" and speedhours or "0")
      if not realtime then _SPEEDTIME = speedhours else _SPEEDTIME = nil end
      --Log(LOG.LOG,"Time1:%s",realtime)
      --Log(LOG.LOG,"Time2:%s",speedhours)
      if _SPEEDTIME then _setUpSpeedTime() end
      _System._setup()
      gstimer = wx.wxTimer(UI.MyFrame1)
      _System.runTimers() -- gstimer:Start(1,wx.wxTIMER_ONE_SHOT )
      event:Skip()
    end )

  UI.m_button_stop:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
      --implements stop
      if gstimer then gstimer:Stop() end
      wx.wxGetApp():ExitMainLoop()
      --fibaro:abort()
      event:Skip()
    end )

  UI.m_button_post:Connect( wx.wxEVT_COMMAND_BUTTON_CLICKED, function(event)
      --implements post
      local ev=json.decode(UI.m_textCtrl_event:GetValue())
      Log(LOG.LOG,"Posting event '%s'",UI.m_textCtrl_event:GetValue())
      if Event then
        Event.post(ev,0)
      else
        setTimeout(function() main(ev) end,0)
      end
      event:Skip()
    end )

  function gSleep(ms1,ms2)
    if _SPEEDTIME then
      if exceededTime() then
        Debug(1,"Max time (_speedtime), %s hours, reached, exiting",_SPEEDTIME)
        EventEngine,ScriptEngine,ScriptCompiler,RuleEngine,Util=nil,nil,nil,nil,nil
        collectgarbage("collect") 
        print(_format("Memory start-end:%.2f",collectgarbage("count")-GC))
        gstimer:Stop()
        wx.wxGetApp():ExitMainLoop()
      end
      fibaro:sleep(ms1) -- sleep 10min
      gstimer:Stop()
      gstimer:Start(1,wx.wxTIMER_ONE_SHOT) 
    else
      gstimer:Stop()
      gstimer:Start(ms2,wx.wxTIMER_ONE_SHOT) 
    end
  end

  function _System.runTimers()
    if _timers == nil then gSleep(10*60*1000,200) return end
    while _timers ~= nil and _timers.time-osTime() <= 0 do
      local f = _timers.fun
      _timers = _timers.next
      f()
    end
    if _timers then
      local l = _timers.time-osTime()
      Debug(5,"Timer %s sleeping %ss",_timers.doc,l)
      gSleep(1000*l,1000*l)
    else
      gSleep(10*60*1000,200)
    end
  end

  UI.MyFrame1:Connect(wx.wxEVT_TIMER, _System.runTimers) 

  UI.MyFrame1:Restore(); -- restore the window if minimized
  UI.MyFrame1:Iconize(false); -- show the window
  UI.MyFrame1:SetFocus(); -- show the window
  UI.MyFrame1:Raise();  -- bring window to front
  UI.MyFrame1:Show(true);  -- bring window to front

  function setTimeout(fun,time,doc)
    assert(type(fun)=='function' and type(time)=='number',"Bad arguments to setTimeout")
    local cp = {time=osTime()+time/1000,fun=fun,doc=doc,next=nil}
    Debug(5,"Timer %s at %s",cp.doc,osDate("%X",cp.time))
    if _timers == nil then _timers = cp
    elseif cp.time < _timers.time then cp.next = _timers; _timers = cp
    else
      local tp = _timers
      while tp.next do
        if cp.time < tp.next.time then 
          cp.next = tp.next; tp.next = cp; 
          if gstimer then 
            gstimer:Stop()
            gstimer:Start(1,wx.wxTIMER_ONE_SHOT )
          end
          return cp
        end
        tp = tp.next
      end
      tp.next = cp
    end
    if gstimer then
      gstimer:Stop()
      gstimer:Start(1,wx.wxTIMER_ONE_SHOT )
    end
    return cp
  end

end

function _System.runOffline(setup)
  if _GUI then
    _System._setup = setup
    Log(LOG.SYSTEM,"Using wxWidgets. Please press 'Run' in GUI to start scene")
    wx.wxGetApp():MainLoop()
  else
    if _SPEEDTIME then _setUpSpeedTime() end
    setup()
    _System.runTimers()
  end
end

---- Remote server support ------------------

function startServer(port)
  local someRandomIP = "192.168.1.122" --This address you make up
  local someRandomPort = "3102" --This port you make up  
  local mySocket = socket.udp() --Create a UDP socket like normal
  mySocket:setpeername(someRandomIP,someRandomPort) 
  local myDevicesIpAddress, somePortChosenByTheOS = mySocket:getsockname()-- returns IP and Port 
  local host = myDevicesIpAddress
  Log(LOG.SYSTEM,"Remote listener started at %s:%s",host,port)
  local s,c,err = assert(socket.bind("*", port))
  local i, p = s:getsockname()
  assert(i, p)
  local co = coroutine.create(
    function()
      while true do
        s:settimeout(0)
        repeat
          c, err = s:accept()
          if err == 'timeout' then coroutine.yield(true) end
        until err ~= 'timeout'
        c:settimeout(0)
        repeat
          local l, e, j = c:receive()
          if l then
            j = l:match("(%b{})")
            if j then 
              Log(LOG.LOG,"<%s>%s:",c:getpeername(),j)
              Event.post(json.decode(j))
            end
          end
          coroutine.yield(true)
        until j or e == 'closed'
      end
    end)
  return co
end

if _PORTLISTENER then
  setTimeout(function()
      _sock = startServer(_PORT)
      function _listener()
        coroutine.resume(_sock)
        setTimeout(_listener,_POLLINTERVAL)
      end
      _listener()
    end,0)
end