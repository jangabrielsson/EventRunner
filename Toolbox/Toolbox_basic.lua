--[[
  Toolbox.
  
  Additional QuickApp functions for logging and loading other toolbox modules

  Debug flags:
  self._2JSON == true will convert tables to json strings before printing (debug etc)
  self._DEBUG == false will inhibit all self:debug messages
  self._TRACE == false will inhibit all self:trace messages
  self._NOTIFY == true will create NotificationCenter messages for self:error and self:warning
  self._HTML == true will format space/nl with html codes for log with self:*f functions
  
  Children will be loaded if there are any children (and module 'child' is loaded)
  quickAppVariables will be loaded into self.config
  Ex. a quickAppVariable "Test" with value 42 is available as self.config.Test

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
  function QuickApp:version(<string>)                 -- Return/optional check HC3 version

--]]

local QA_toolbox_version = "0.17"
local format = string.format
Toolbox_Module,modules = Toolbox_Module or {},modules or {}
local _init = QuickApp.__init
local _onInit = nil

function QuickApp.__init(self,...)
  _onInit = self.onInit
  self.onInit = self.loadToolbox
  _init(self,...)
end

_debugFlags = _debugFlags or { }

function QuickApp:loadToolbox()
  if self.properties.model ~= "ToolboxUser" then
     self:updateProperty("model","ToolboxUser")
  end
  self.debugFlags = _debugFlags
  quickApp = self 
  self._2JSON = true             -- Automatically convert tables to json when logging - debug/trace/error/warning
  self._DEBUG = true             -- False, silence self:debug statements
  self._TRACE = true             -- Same for self:trace
  self._HTML = not hc3_emulator  -- Output HTML debug statements (line beaks, spaces)
  self._NOTIFY = true            -- Automatically call notifyCenter for self:error and self:warning
  self._UNHANDLED_EVENTS = false -- Log unknow events
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
  Toolbox_Module['basic'](self)
  local ms,Module = {},Toolbox_Module
  for _,m in ipairs(modules or {}) do 
    if Module[m] then 
      self:debugf("Setup: %s (%s)",Module[m].name,Module[m].version)
      modules[m]=Module[m].init(self) 
    else self:warning("Module '"..m.."' missing") end
  end
  --modules = ms
  for m,_ in pairs(Module) do Module[m] = nil end
  self.config = {}
  for _,v in ipairs(self.properties.quickAppVariables or {}) do
    self.config[v.name] = v.value
  end
  if self.loadChildren then
    local nc = self:loadChildren()
    if nc == 0 then self:debug("No children") else self:debugf("%d children",nc) end
  end
  self.loadToolbox = function() end
  if _onInit then _onInit(self) end
  if self.main and type(self.main)=='function' then setTimeout(function() self:main() end,0) end -- If we have a main(), call it...
end

function Toolbox_Module.basic(self)
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
  --self._format = _format 

  function assertf(test,...) if not test then error(_format(...)) end end

  local function _print(s,fun,...)
    local res = {}
    for _,obj in ipairs({...}) do res[#res+1]=tostring(obj) end
    res = table.concat(res)
    fun(s,res)
    return res
  end

  local function _printf(self,fun,fmt,...)
    local str = _format(fmt,...)
    if self._HTML and not hc3_emulator then 
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

  local HC3version = nil
  function self:version(version)                 -- Return/optional check HC3 version
    if HC3version == nil then
      if hc3_emulator then HC3version="5.040.37"
      else HC3version = api.get("/settings/info").currentVersion.version end
    end
    if version then return version >= HC3version else return version end 
  end

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
    assert(({info=true,warning=true,critical=true})[priority],"Wrong 'priority' - info/warning/critical")
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
    if self._lastNotification[msgId] then
      local res,code = api.put("/notificationCenter/"..self._lastNotification[msgId].id, data)
      if code==200 then return self._lastNotification[msgId].id end
    end
    self._lastNotification[msgId] = api.post("/notificationCenter", data)
    return self._lastNotification[msgId] and self._lastNotification[msgId].id
  end

  local refs = {}
  function self:INTERACTIVE_OK_BUTTON(ref) if refs[ref] then refs[ref]() end refs[ref]=nil end

--  self:pushYesNo(
--    839,                                          -- Mobile ID  (api.get("/iosDevices"))
--    "Test",                                       -- Title
--    "Please, press yes",                          -- Message
--    function() self:debug("User said Yes!") end,  -- Callback function if user press yes
--    5*60                                          -- Timout in seconds, after we ignore reply.
--  )

  function self:pushYesNo(mobileId,title,message,callback,timeout)
    local ref = tostring({}):match("(0x.*)")
    api.post("/mobile/push", 
      {
        category = "YES_NO", 
        title = title, 
        message = message, 
        service = "Device", 
        data = {
          actionName = "INTERACTIVE_OK_BUTTON", 
          deviceId = self.id, 
          args = {ref}
        }, 
        action = "RunAction", 
        mobileDevices = { mobileId }, 
      })
    local timer = setTimeout(function() refs[ref]=nil; self:debug("Timeout") end, timeout*1000)
    timeout = timeout or 20*60
    refs[ref]=function() clearTimeout(timer) callback() end
  end

  do -- Used for print device table structs - sortorder for device structs
    local sortKeys = {
      'id','name','roomID','type','baseType','enabled','visible','isPlugin','parentId','viewXml','configXml',
      'interfaces','properties','view', 'actions','created','modified','sortOrder'
    }
    local sortOrder={}
    for i,s in ipairs(sortKeys) do sortOrder[s]="\n"..string.char(i+64).." "..s end
    local function keyCompare(a,b)
      local av,bv = sortOrder[a] or a, sortOrder[b] or b
      return av < bv
    end

    function self:prettyJsonStruct(t)
      local res = {}
      local function isArray(t) return type(t)=='table' and t[1] end
      local function isEmpty(t) return type(t)=='table' and next(t)==nil end
      local function isKeyVal(t) return type(t)=='table' and t[1]==nil and next(t)~=nil end
      local function printf(tab,fmt,...) res[#res+1] = string.rep(' ',tab)..string.format(fmt,...) end
      local function pretty(tab,t,key)
        if type(t)=='table' then
          if isEmpty(t) then printf(0,"[]") return end
          if isArray(t) then
            printf(key and tab or 0,"[\n")
            for i,k in ipairs(t) do
              local cr = pretty(tab+1,k,true)
              if i ~= #t then printf(0,',') end
              printf(tab+1,'\n')
            end
            printf(tab,"]")
            return true
          end
          local r = {}
          for k,v in pairs(t) do r[#r+1]=k end
          table.sort(r,keyCompare)
          printf(key and tab or 0,"{\n")
          for i,k in ipairs(r) do
            printf(tab+1,'"%s":',k)
            local cr =  pretty(tab+1,t[k])
            if i ~= #r then printf(0,',') end
            printf(tab+1,'\n')
          end
          printf(tab,"}")
          return true
        elseif type(t)=='number' then
          printf(key and tab or 0,"%s",t) 
        elseif type(t)=='boolean' then
          printf(key and tab or 0,"%s",t and 'true' or 'false') 
        elseif type(t)=='string' then
          printf(key and tab or 0,'"%s"',t)
        end
      end
      pretty(0,t,true)
      return table.concat(res,"")
    end
  end

  local IPaddress = nil
  function self:getHC3IPaddress()
    if IPaddress then return IPaddress end
    if hc3_emulator then return hc3_emulator.IPaddress
    else
      local networkdata = api.get("/proxy?url=http://localhost:11112/api/settings/network")
      networkdata = networkdata.networkConfig
      for n,d in pairs(networkdata) do
        if d.enabled then IPaddress = d.ipConfig.ip; return IPaddress end
      end
    end
  end

  self._Events = {}
  local eventHandlers = {}

  function self._Events.postEvent(event)
    for i=1,#eventHandlers do if eventHandlers[i](event) then return end end -- Handler returning true breaks chain
  end

  function self._Events.addEventHandler(handler,front)
    for _,h in ipairs(eventHandlers) do if h==handler then return end end
    if front then table.insert(eventHandlers,1,handler) else eventHandlers[#eventHandlers+1]=handler end
  end

  function self._Events.removeEventHandler(handler)
    for i=1,#eventHandlers do if eventHandlers[i]==handler then table.remove(eventHandlers,i) return end end
  end

  do
    local settimeout,setinterval,encode,decode =  -- gives us a better error messages
    setTimeout, setInterval, json.encode, json.decode
    function setTimeout(fun,ms)
      return settimeout(function()
          local stat,res = pcall(fun)
          if not stat then 
            self:errorf(res,2)
          end
        end,ms)
    end
    function setInterval(fun,ms)
      return setinterval(function()
          local stat,res = pcall(fun)
          if not stat then 
            self:errorf(res,2)
          end
        end,ms)
    end
    function json.decode(...)
      local stat,res = pcall(decode,...)
      if not stat then error(res,2) else return res end
    end
    function json.encode(...)
      local stat,res = pcall(encode,...)
      if not stat then error(res,2) else return res end
    end
  end
end