if false then 
  if dofile and not hc3_emulator then
    hc3_emulator = {
      name="QA_toolbox",
      type="com.fibaro.genericDevice",
      poll=1000,
      --deploy=true,
    }
    dofile("fibaroapiHC3.lua")
  end

  _version = "1.0"
  modules = {"childs","events","triggers","rpc"}

  function QuickApp:turnOn()
  end

  function QuickApp:turnOff()
  end

  function QuickApp:main()
    self:enableTriggerType({"device","global-variable","alarm","weather","profile","custom-event","deviceEvent","sceneEvent","onlineEvent"})

    self.debugFlags.triggers = true -- Log all incoming (enabled) triggers

    self:event({type='HTTPEvent',status=200,data='$res',tag="refresh"},
      function(env)
        self:tracef("HTTP:%s",env.p.res)
      end)

    self:HTTPEvent{
      tag="refresh",
      url="http://127.0.0.1:11111/api/settings/info",
      basicAuthorization={user="admin",password="admin"}
    }

  end

  function QuickApp:onInit()
    self._NOTIFY = true
  end
end
----------- Code -----------------------------------------------------------
----------- QA toolbox functions -------------------------------------------
--[[
function QuickApp:setView(elm,prop,fmt,...)         -- Like updateView but with format
function QuickApp:getView(elm,prop)                 -- Get value of view element
function QuickApp:setName(name)                     -- Change name of QA
--function QuickApp:setType(typ)                      -- Change type of QA
function QuickApp:setIconMessage(msg,timeout)       -- Show text under icon, optional timeout to remove message
function QuickApp:setEnabled(bool)                  -- Enable/disable QA
function QuickApp:setVisible(bool)                  -- Hide/show QA
function QuickApp:addInterfaces(interfaces)         -- Add interfaces to QA
function QuickApp:notify(priority, title, text)     -- Create notification
function QuickApp:debugf(fmt,...)                   -- Like self:debug but with format
function QuickApp:tracef(fmt,...)                   -- Like self:trace but with format
function QuickApp:errorf(fmt,...)                   -- Like self:error but with format
function QuickApp:warningf(fmt,...)                 -- Like self:warning but with format
function QuickApp:encodeBase64(data)                -- Base 64 encoder
function QuickApp:basicAuthorization(user,password) -- Create basic authorization data (for http requests)
-- Module "childs"
function QuickApp:createChild(args)                 -- Create child device, see code below...
function QuickApp:numberOfChildren()                -- Returns number of existing children
function QuickApp:removeAllChildren()               -- Remove all child devices
function QuickApp:callChildren(method,...)          -- Call all child devices with method. 
function QuickApp:setChildIconPath(childId,path)
-- Module "events"
function QuickApp:post(ev,t)                        -- Post event 'ev' at time 't'
function QuickApp:cancel(ref)                       -- Cancel post in the future
function QuickApp:event(pattern,fun)                -- Create event handler for posted events
function QuickApp:HTTPEvent(args)                   -- Asynchronous http requests
function QuickApp:RECIEVE_EVENT(ev)                 -- QA method for recieving events from outside...
-- Module "triggers"
function QuickApp:registerTriggerHandler(handler)   -- Register handler for trigger callback (function(event) ... end)
function QuickApp:enableTriggerType(trs)            -- Enable trigger type. <string> or table of <strings>
function QuickApp:enableTriggerPolling(bool)        -- Enable/disable trigger polling loop
function QuickApp:setTriggerInterval(ms)            -- Set polling interval. Default 1000ms
-- Module "rpc"
function QuickApp:importRPC(deviceId,timeout,env)   -- Import remote functions from QA with deviceId
--]]

local QA_toolbox_version = "0.9"
local format = string.format
local stat,_init = pcall(function() return QuickApp.onInit end)
_init = stat and _init
local Module = Module or {}

--[[
 onInit()
    self._2JSON == true will convert tables to json strings before printing (debug etc)
    self._DEBUG == false will inhibit all self:debug messages
    self._TRACE == false will inhibit all self:trace messages
    self._NOTIFY == true will create NotificationCenter messages for self:error and self:warning
    self._HTML == true will format space/nl with html codes for log with self:*f functions
    Children will be loaded if there are any children
    quickAppVariables will be loaded into self.config
      Ex. a quickAppVariable "Test" with value 42 is available as self.config.Test
--]]
function QuickApp:onInit()
  quickApp = self 
  self._2JSON = true
  self._DEBUG = true
  self._TRACE = true
  self._HTML = not hc3_emulator
  self._NOTIFY = false
  local d = __fibaro_get_device(self.id)
  local function printf(...) self:debug(format(...)) end
  printf("QA %s - version:%s (QA toolbox %s)",self.name,_version or "1.0",QA_toolbox_version)
  printf("DeviceId..:%d",d.id)
  printf("Type......:%s",d.type)
  printf("Interfaces:%s",json.encode(d.interfaces or {}))
  printf("Room......:%s",d.roomID or 0)
  printf("Visible...:%s",tostring(d.visible))
  printf("Created...:%s",os.date("%c",d.created or os.time()))
  printf("Modified..:%s",os.date("%c",d.modified or os.time()))
  Module['basic'](self)
  local ms = {}
  for _,m in ipairs(modules or {}) do if Module[m] then ms[m]=Module[m](self) end end
  modules = ms
  for m,_ in pairs(Module) do Module[m] = nil end
  self.config,self.debugFlags = {},{}
  for _,v in ipairs(self.properties.quickAppVariables or {}) do
    self.config[v.name] = v.value
  end
  if self.loadChildren then
    local nc = self:loadChildren()
    if nc == 0 then self:debug("No children") else self:debugf("%d children",nc) end
  end
  if _init then _init(self) end -- Call  user's own :onInit()
  if self.main and type(self.main)=='function' then setTimeout(function() self:main() end,0) end -- If we have a main(), call it...
end

function Module.basic(self)
-- tostring optionally converting tables to json or custom conversion
  local _tostring = tostring
  self._orgToString= tostring -- good to have sometimes....
  function tostring(obj) 
    if type(obj)=='table' then
      if obj.__tostring then return obj.__tostring(obj)
      elseif self._2JSON then return json.encode(obj) end
    end
    return  _tostring(obj) 
  end

  local function _format(fmt,...)
    local args = {...}
    if #args == 0 then return fmt end
    for i,v in ipairs(args) do if type(v)=='table' then args[i]=tostring(v) end end
    return format(fmt,table.unpack(args))
  end

  local function _print(s,fun,...)
    local res = {}
    for _,obj in ipairs({...}) do res[#res+1]=tostring(obj) end
    res = table.concat(res)
    fun(s,res)
    return res
  end

  local function _printf(self,fun,fmt,...)
    local str = _format(fmt,...)
    if self._HTML then 
      str = str:gsub("(\n)","<br>")
      str = str:gsub("(%s)",'&nbsp;')
    end
    fun(self,str)
    return str
  end

  function self:encodeBase64(data)
    local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x) 
            local r,b='',x:byte() for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
            return r;
          end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
          if (#x < 6) then return '' end
          local c=0
          for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
          return b:sub(c+1,c+1)
        end)..({ '', '==', '=' })[#data%3+1])
  end

-- Create basic authorisation data, used with http requests
  function self:basicAuthorization(user,password) return "Basic "..self:encodeBase64(user..":"..password) end

  local function notifyIf(self,p,text)
    if self._NOTIFY then
      local title = text:match("(.-)[:%s]") or format("%s deviceId:%d",self.id,self.name)
      self:notify(p,title,text)
    end
  end

-- Enhanced debug functions converting tables to json and with formatting version
  local _debug,_trace,_error,_warning = self.debug,self.trace,self.error,self.warning
  function self:debug(...) if self._DEBUG then _print(self,_debug,...) end end
  function self:trace(...) if self._TRACE then _print(self,_trace,...) end end
  function self:error(...) notifyIf(self,"critical",_print(self,_error,...)) end
  function self:warning(...) notifyIf(self,"warning",_print(self,_warning,...)) end
  function self:debugf(fmt,...) if self._DEBUG then _printf(self,_debug,fmt,...) end end
  function self:tracef(fmt,...) _printf(self,_trace,fmt,...) end
  function self:errorf(fmt,...) notifyIf(self,"critical",_printf(self,_error,fmt,...)) end
  function self:warningf(fmt,...) notifyIf(self,"warning",_printf(self,_warning,fmt,...)) end

-- Like self:updateView but with formatting. Ex self:setView("label","text","Now %d days",days)
  function self:setView(elm,prop,fmt,...)
    local str = _format(fmt,...)
    self:updateView(elm,prop,str)
  end

-- Get view element value. Ex. self:getView("mySlider","value")
  function self:getView(elm,prop)
    assert(type(elm)=='string' and type(prop)=='string',"Strings expected as arguments")
    local function find(s)
      if type(s) == 'table' then
        if s.name==elm then return s[prop]
        else for _,v in pairs(s) do local r = find(v) if r then return r end end end
      end
    end
    return find(api.get("/plugins/getView?id="..self.id)["$jason"].body.sections)
  end

-- Change name of QA. Note, if name is changed the QA will restart
  function self:setName(name)
    if self.name ~= name then api.put("/devices/"..self.id,{name=name}) end
    self.name = name
  end

-- Set log text under device icon - optional timeout to clear the message
  function self:setIconMessage(msg,timeout)
    if self._logTimer then clearTimeout(self._logTimer) self._logTimer=nil end
    self:updateProperty("log", tostring(msg))
    if timeout then 
      self._logTimer=setTimeout(function() self:updateProperty("log",""); self._logTimer=nil end,1000*timeout) 
    end
  end

-- Disable QA. Note, difficult to enable QA...
  function self:setEnabled(bool)
    local d = __fibaro_get_device(self.id)
    if d.enabled ~= bool then api.put("/devices/"..self.id,{enabled=bool}) end
  end

-- Hide/show QA. Note, if state is changed the QA will restart
  function self:setVisible(bool) 
    local d = __fibaro_get_device(self.id)
    if d.visible ~= bool then api.put("/devices/"..self.id,{visible=bool}) end
  end

-- Add interfaces to QA. Note, if interfaces are added the QA will restart
  local _addInterf = self.addInterfaces
  function self:addInterfaces(interfaces) 
    local d,map = __fibaro_get_device(self.id),{}
    for _,i in ipairs(d.interfaces or {}) do map[i]=true end
    for _,i in ipairs(interfaces or {}) do
      if not map[i] then
        _addInterf(self,interfaces)
        return
      end
    end
  end

-- Change type of QA. Note, if types is changed the QA will restart
--function QuickApp:setType(typ)
--  if self.typ ~= typ then api.put("/devices/"..self.id,{type=typ}) end
--  self.type = typ
--end

-- Add notification to notification center
  function self:notify(priority, title, text)
    self._lastNotification = self._lastNotification or {}
    local msgId = title..self.id
    local data = {
      canBeDeleted = true,
      wasRead = false,
      priority = priority,
      type = "GenericDeviceNotification",
      data = {
        deviceId = self.id,
        subType = "Generic",
        title = title,
        text = tostring(text)
      }
    }
    self._lastNotification[msgId] = api.post("/notificationCenter", data)
    return self._lastNotification
  end

  do
    local oldSetTimeout = setTimeout -- gives us a better error messages when function in setTimeout crashes
    function setTimeout(fun,ms)
      return oldSetTimeout(function()
          local stat,res = pcall(fun)
          if not stat then 
            self:errorf("Error in setTimeout:%s",res)
          end
        end,ms)
    end
    function split(s, sep)
      local fields = {}
      sep = sep or " "
      local pattern = format("([^%s]+)", sep)
      string.gsub(s, pattern, function(c) fields[#fields + 1] = c end)
      return fields
    end
  end
end

------------   Device children ---------------
function Module.childs(self)
  local version = "0.1"
  self:debugf("Setup: Child manager (%s)",version) 

  function self:setChildIconPath(childId,path)
    api.put("/devices/"..childId,{properties={icon={path=path}}})
  end

--Ex. self:callChildren("method",1,2) will call MyClass:method(1,2) 
  function self:callChildren(method,...)
    for _,child in pairs(self.childDevices or {}) do 
      if child[method] then 
        local stat,res = pcall(child[method],child,...)  
        if not stat then self:debug(res) end
      end
    end
  end

--Removes all children belonging to this device
  function self:removeAllChildren()
    for id,_ in pairs(self.childDevices or {}) do self:removeChildDevice(id) end
  end

--Returns number of children belonging to this device
  function self:numberOfChildren()
    local n = 0
    for _,_ in pairs(self.childDevices or {}) do n=n+1 end
    return n
  end

-- Used before we have a child object. Afterwards we can use child:getVariable("var")
  function self:getChildVariable(child,varName) 
    for _,v in ipairs(child.properties.quickAppVariables or {}) do
      if v.name==varName then return v.value end
    end
    return ""
  end

  function QuickApp:_annotateClass(classObj)
    if not classObj then return end
    if pcall(function() return classObj._annotated end) then return end
    self:debug("Annotating class")
    for _,m in ipairs({
        "notify","setType","setVisible","setEnabled","setIconMessage","setName","getView",
        "setView","debug","trace","error","warning","debugf","tracef","errorf","warningf","basicAuthorization"}) 
    do classObj[m] = self[m] end
    classObj._annotated = true
    classObj._2JSON = true
    classObj._DEBUG = true
    classObj._TRACE = true
    classObj._HTML  = true
    classObj.config,classObj.debugFlags = {},{}
  end

--[[
  QuickApp:createChild{
    className = "MyChildDevice",      -- class name of child object
    name = "MyName",                  -- Name of child device
    type = "com.fibaro.binarySwitch", -- Type of child device
    properties = {},                  -- Initial properties
    interfaces = {},                  -- Initial interfaces
    data = ...                        -- Optional data passed to child:setup(data) after initialized
  }
--]]
  function self:createChild(args)
    local className = args.className or "QuickAppChild"
    self:_annotateClass(_G[className])
    local name = args.name or "Child"
    local tpe = args.type or "com.fibaro.binarySensor"
    local properties = args.properties or {}
    local interfaces = args.interfaces or {}
    local child = self:createChildDevice({
        name = name,
        type=tpe,
        initialProperties = properties,
        initialInterfaces = interfaces
      },
      _G[className] -- Fetch class constructor from class name
    )
    child:setVariable("className",className)  -- Save class name so we know when we load it next time
    return child
  end

-- Loads all children, called automatically at startup
  function self:loadChildren()
    local cdevs,n = api.get("/devices?parentId="..self.id) or {},0 -- Pick up all my children
    function self:initChildDevices() end -- Null function, else Fibaro calls it after onInit()...
    for _,child in ipairs(cdevs or {}) do
      local className = self:getChildVariable(child,"className")
      self:_annotateClass(_G[className])
      local childObject = _G[className] and _G[className](child) or QuickAppChild(child)
      self.childDevices[child.id]=childObject
      childObject.parent = self
      n=n+1
    end
    return n
  end

-- UI handler to pass button clicks to children
  function self:UIHandler(event)
    local obj = self
    if self.id ~= event.deviceId then obj = self.childDevices[event.deviceId] end
    if not obj then return end
    local elm,etyp = event.elementName, event.eventType
    local cb = obj.uiCallbacks or {}
    if obj[elm] then return obj:callAction(elm, event) end
    if cb[elm] and cb[elm][etyp] then return obj:callAction(cb[elm][etyp], event) end
    if obj[elm.."Clicked"] then return obj:callAction(elm.."Clicked", table.unpack(event.values or {})) end
    self:warning("UI callback for element:", elm, " not found.")
  end
end

------------   Event Manager ---------------
function Module.events(self)
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

------------   Triggers ---------------
--[[
Supported events:
{type='alarm', property='armed', id=<id>, value=<value>}
{type='alarm', property='breached', id=<id>, value=<value>}
{type='alarm', property='homeArmed', value=<value>}
{type='alarm', property='homeBreached', value=<value>}
{type='weather', property=<prop>, value=<value>, old=<value>}
{type='global-variable', property=<name>, value=<value>, old=<value>}
{type='device', id=<id>, property=<property>, value=<value>, old=<value>}
{type='device', id=<id>, property='centralSceneEvent', value={keyId=<value>, keyAttribute=<value>}}
{type='device', id=<id>, property='accessControlEvent', value=<value>}
{type='device', id=<id>, property='sceneACtivationEvent', value=<value>}
{type='profile', property='activeProfile', value=<value>, old=<value>}
{type='custom-event', name=<name>}
{type='UpdateReadyEvent', value=_}
{type='deviceEvent', id=<id>, value='removed'}
{type='deviceEvent', id=<id>, value='changedRoom'}
{type='deviceEvent', id=<id>, value='created'}
{type='deviceEvent', id=<id>, value='modified'}
{type='deviceEvent', id=<id>, value='crashed', error=<string>}
{type='sceneEvent',  id=<id>, value='started'}
{type='sceneEvent',  id=<id>, value='finished'}
{type='sceneEvent',  id=<id>, value='instance', instance=d}
{type='sceneEvent',  id=<id>, value='removed'}
{type='onlineEvent', value=<bool>}
--]]

function Module.triggers(self)
  local version = "0.2"
  self:debugf("Setup: Trigger manager (%s)",version)
  self.TR = { central={}, access={}, activation={} }
  local ENABLEDTRIGGERS={}
  local INTERVAL = 1000 -- every second, could do more often...

  local function post(ev)
    if ENABLEDTRIGGERS[ev.type] then
      if self.debugFlags.triggers then self:debugf("Incoming event:%s",ev) end
      ev._trigger=true
      ev.__tostring = _eventPrint
      if self._eventHandler then self._eventHandler(ev) end
    end
  end

  local EventTypes = { -- There are more, but these are what I seen so far...
    AlarmPartitionArmedEvent = function(d) post({type='alarm', property='armed', id = d.partitionId, value=d.armed}) end,
    AlarmPartitionBreachedEvent = function(d) post({type='alarm', property='breached', id = d.partitionId, value=d.breached}) end,
    HomeArmStateChangedEvent = function(d) post({type='alarm', property='homeArmed', value=d.newValue}) end,
    HomeBreachedEvent = function(d) post({type='alarm', property='homeBreached', value=d.breached}) end,
    WeatherChangedEvent = function(d) post({type='weather',property=d.change, value=d.newValue, old=d.oldValue}) end,
    GlobalVariableChangedEvent = function(d) 
      if d.variableName=="ERTICK" then return end
      post({type='global-variable', name=d.variableName, value=d.newValue, old=d.oldValue}) 
    end,
    DevicePropertyUpdatedEvent = function(d)
      if d.property=='quickAppVariables' then 
        local old={}; for _,v in ipairs(d.oldValue) do old[v.name] = v.value end -- Todo: optimize
        for _,v in ipairs(d.newValue) do
          if v.value ~= old[v.name] then
            post({type='quickvar', name=v.name, value=v.value, old=old[v.name]})
          end
        end
      else
        if d.property == "icon" then return end
        post({type='device', id=d.id, property=d.property, value=d.newValue, old=d.oldValue})
      end
    end,
    CentralSceneEvent = function(d) 
      self.TR.central[d.deviceId]=d;d.icon=nil 
      post({type='device', property='centralSceneEvent', id=d.deviceId, value={keyId=d.keyId, keyAttribute=d.keyAttribute}}) 
    end,
    SceneActivationEvent = function(d) 
      self.TR.activation[d.deviceId]={scene=d.sceneId, name=d.name}; 
      post({type='device', property='sceneActivationEvent', id=d.deviceId, value={sceneId=d.sceneId}})     
    end,
    AccessControlEvent = function(d) 
      self.TR.access[d.id]=d; 
      post({type='device', property='accessControlEvent', id=d.id, value=d}) 
    end,
    CustomEvent = function(d) 
      local value = api.get("/customEvents/"..d.name) 
      post({type='custom-event', name=d.name, value=value and value.userDescription}) 
    end,
    PluginChangedViewEvent = function(d) post({type='PluginChangedViewEvent', value=d}) end,
    WizardStepStateChangedEvent = function(d) post({type='WizardStepStateChangedEvent', value=d})  end,
    UpdateReadyEvent = function(d) post({type='updateReadyEvent', value=d}) end,
    DeviceRemovedEvent = function(d)  post({type='deviceEvent', id=d.id, value='removed'}) end,
    DeviceChangedRoomEvent = function(d)  post({type='deviceEvent', id=d.id, value='changedRoom'}) end,
    DeviceCreatedEvent = function(d)  post({type='deviceEvent', id=d.id, value='created'}) end,
    DeviceModifiedEvent = function(d) post({type='deviceEvent', id=d.id, value='modified'}) end,
    PluginProcessCrashedEvent = function(d) post({type='deviceEvent', id=d.deviceId, value='crashed', error=d.error}) end,
    SceneStartedEvent = function(d)   post({type='sceneEvent', id=d.id, value='started'}) end,
    SceneFinishedEvent = function(d)  post({type='sceneEvent', id=d.id, value='finished'})end,
    SceneRunningInstancesEvent = function(d) post({type='sceneEvent', id=d.id, value='instance', instance=d}) end,
    SceneRemovedEvent = function(d)  post({type='sceneEvent', id=d.id, value='removed'}) end,
    OnlineStatusUpdatedEvent = function(d) post({type='onlineEvent', value=d.online}) end,
    --onUIEvent = function(d) post({type='uievent', deviceID=d.deviceId, name=d.elementName}) end,
    ActiveProfileChangedEvent = function(d) 
      post({type='profile',property='activeProfile',value=d.newActiveProfile, old=d.oldActiveProfile}) 
    end,
    NotificationCreatedEvent = function(_) end,
    NotificationRemovedEvent = function(_) end,
    RoomCreatedEvent = function(_) end,
    RoomRemovedEvent = function(_) end,
    RoomModifiedEvent = function(_) end,
    SectionCreatedEvent = function(_) end,
    SectionRemovedEvent = function(_) end,
    SectionModifiedEvent = function(_) end,
  }

  local lastRefresh,enabled = 0,true
  local http = net.HTTPClient()
  local function loop()
    local stat,res = http:request("http://127.0.0.1:11111/api/refreshStates?last=" .. lastRefresh,{
        success=function(res) 
          local states = json.decode(res.data)
          if states then
            lastRefresh=states.last
            if states.events and #states.events>0 then 
              for _,e in ipairs(states.events) do
                local handler = EventTypes[e.type]
                if handler then handler(e.data)
                elseif handler==nil then self:debugf("[Note] Unhandled event:%s -- please report",e) end
              end
            end
            setTimeout(loop,INTERVAL)
          end  
        end,
        error=function(res) 
          self:errorf("refreshStates:%s",res)
          setTimeout(loop,1000)
        end,
      })
  end
  loop()
  function self:enableTriggerType(trs,enable) 
    if enable ~= false then enable = true end
    if type(trs)=='table' then 
      for _,t in ipairs(trs) do self:enableTriggerType(t) end
    else ENABLEDTRIGGERS[trs]=enable end
  end
  function self:enableTriggerPolling(bool) if bool ~= enabled then enabled = bool end end -- ToDo
  function self:setTriggerInterval(ms) INTERVAL = ms end
end

------------   RPC ---------------
function Module.rpc(self)
  local version = "0.1"
  self:debugf("Setup: RPC manager (%s)",version)

  local var,n = "RPC_"..self.id,0
  api.post("/globalVariables",{name=var,value=""})

  local function rpc(id,fun,args,timeout)
    fibaro.setGlobalVariable(var,"")
    n = n + 1
    fibaro.call(id,"RPC_CALL",var,n,fun,args)
    timeout = os.time()+(timeout or 3)
    while os.time() < timeout do
      local r = fibaro.getGlobalVariable(var)
      if r~="" then 
        r = json.decode(r)
        if r[1] == n then
          if not r[2] then error(r[3],3) else return select(3,table.unpack(r)) end
        end
      end
    end
    error(format("RPC timeout %s:%d",fun,id),3)
  end

  function QuickApp:RPC_CALL(var,n,fun,args)
    local res = {n,pcall(_G[fun],table.unpack(args))}
    fibaro.setGlobalVariable(var,json.encode(res))
  end

  function self:defineRPC(id, fun, timeout, tab) tab[fun]=function(...) return rpc(id, fun, {...}, timeout) end end

  function self:exportRPC(funList) self:setVariable("ExportedFuns",json.encode(funList)) end

  function self:importRPC(id,timeout,tab) 
    local d = __fibaro_get_device(id)
    assert(d,"Device does not exist")
    for _,v in ipairs(d.properties.quickAppVariables or {}) do
      if v.name=='RPCexports' then
        for _,e in ipairs(v.value) do
          self:debugf("RPC function %d:%s - %s",id,e.name,e.doc or "")
          self:defineRPC(id, e.name, timeout, tab or _G)
        end
      end
    end
  end
end