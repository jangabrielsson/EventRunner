--[[
  Toolbox.
  
  Additional QuickApp functions for logging and loading other toolbox modules.
  This is not strictly a "module" as it is neccessary for the other modules

  Debug flags:
  self._SILENT == true will supress startup log messages from the toolbox initialization phase
  self._2JSON == true will convert tables to json strings before printing (debug etc)
  self._DEBUG == false will inhibit all self:debug messages
  self._TRACE == false will inhibit all self:trace messages
  self._NOTIFY == true will create NotificationCenter messages for self:error and self:warning
  self._NOTIFYREUSE == true will reuse notifications with same title
  self._INSTALL_MISSING_MODULES == true will try to install missing modules from github reppository
  self._HTML == true will format space/nl with html codes for log with self:*f functions
  self._PROPWARN == true will warn if property don't exist when doing self:updateProperty. Default true
  self._ONACTIONLOG == false will inhibit the 'onAction' log message. Default false
  
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
local QA_toolbox_version = "0.25"
QuickApp = QuickApp or {}
local format = string.format
local _init = QuickApp.__init
local _onInit = nil
Toolbox_Module,modules = Toolbox_Module or {},modules or {} -- needs to be globals

function QuickApp.__init(self,...) -- We hijack the __init methods so we can control users :onInit() method
  _onInit = self.onInit
  self.onInit = self.loadToolbox
  _init(self,...)
end

_debugFlags = _debugFlags or { }
local fetchFiles

function QuickApp:loadToolbox()
  if not __fibaro_get_device(self.id).enabled then  
    self:debug("QA ",self.name," disabled")
    return 
  end
  if self.properties.model ~= "ToolboxUser" then
    self:updateProperty("model","ToolboxUser")
  end
  self.debugFlags = _debugFlags
  quickApp = self 
  self._2JSON = true             -- Automatically convert tables to json when logging - debug/trace/error/warning
  self._DEBUG = true             -- False, silence self:debug statements
  self._TRACE = true             -- Same for self:trace
  self._HTML = not hc3_emulator  -- Output HTML debug statements (line beaks, spaces)
  self._PROPWARN = true
  self._ONACTIONLOG = false
  self._NOTIFY = true            -- Automatically call notifyCenter for self:error and self:warning
  self._UNHANDLED_EVENTS = false -- Log unknow events
  local d = __fibaro_get_device(self.id)
  local function printf(...) self:debug(format(...)) end
  printf("QA %s - version:%s (QA toolbox %s)",self.name,_version or "1.0",QA_toolbox_version)
  if not self._SILENT then
    printf("DeviceId..:%d",d.id)
    printf("Type......:%s",d.type)
    printf("Interfaces:%s",json.encode(d.interfaces or {}))
    printf("Room......:%s",d.roomID or 0)
    printf("Visible...:%s",tostring(d.visible))
    printf("Created...:%s",os.date("%c",d.created or os.time()))
    printf("Modified..:%s",os.date("%c",d.modified or os.time()))
  end
  Toolbox_Module['basic'](self)

--  function QuickApp:loadModule(name,args)
--    args = args or {}
--    if Toolbox_Module[name] then
--      if not self._SILENT then self:debugf("Setup: %s (%s)",Toolbox_Module[name].name,Toolbox_Module[name].version) end
--      return Toolbox_Module[m].init(self,args)
--    else 
--      self:warning("Module '"..name.."' missing")
--      if self._INSTALL_MISSING_MODULES then
--        self.missingModules[#missingModules+1]=name
--      else self:warning("Set self._INSTALL_MISSING_MODULES=true to load missing modules") end
--    end 
--  end

  -- Load modules
  local ms,Module,missingModules = {},Toolbox_Module,{}

  function self:require(name,...)
    if Module[name] then
      local inited,res = Module[name].inited,Module[name].init(self,...)
      if (not inited) and (not self._SILENT) then 
        self:debugf("Setup: %s (%s)",Module[name].name,Module[name].version)
      end
      return res
    else error("Module '"..name.."' missing") end
  end

  for _,m in ipairs(modules or {}) do 
    local args = {}
    if type(m)=='table' then args = m.args or {}; m = m.name end
    if Module[m] then self:require(m,args)
    else 
      self:warning("Module '"..m.."' missing")
      if self._INSTALL_MISSING_MODULES then
        missingModules[#missingModules+1]=m
      else self:warning("Set self._INSTALL_MISSING_MODULES=true to load missing modules") end
    end
  end

  local function cont() -- stuff to do when we loaded missing modules...
    --for m,_ in pairs(Module) do Module[m] = nil end
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
    if self.main and type(self.main)=='function' then 
      setTimeout(function() 
          local stat,res = pcall(function() self:main() end)
          if not stat then self:error("main() error:",res) end
        end,0) 
    end -- If we have a main(), call it...  
  end

  -- Try to load missing modules
  if #missingModules > 0 then
    local  content = {}
    fetchFiles(missingModules,content,
      function()
        if #content>0 then
          if not hc3_emulator then
            self:debugf("Adding module(s) ..will  restart")
            for _,f in ipairs(content) do
              api.post("/quickApp/"..self.id.."/files",f)
            end
            plugin.restart(self.id)
          else self:debugf("Can't update offline") end
          cont()
        end 
      end)
  else cont() end

  local mpath = "https://raw.githubusercontent.com/jangabrielsson/EventRunner/master/Toolbox/"
  local moduleMap={
    childs      = {name="Toolbox_child",      url=mpath.."Toolbox_child.lua"},
    events      = {name="Toolbox_events",     url=mpath.."Toolbox_events.lua"},
    triggers    = {name="Toolbox_triggers",   url=mpath.."Toolbox_triggers.lua"},
    rpc         = {name="Toolbox_rpc",        url=mpath.."Toolbox_rpc.lua"},
    file        = {name="Toolbox_files",      url=mpath.."Toolbox_files.lua"},
    pubsub      = {name="Toolbox_pubsub",     url=mpath.."Toolbox_pubsub.lua"},
    profiler    = {name="Toolbox_profiler",   url=mpath.."Toolbox_profiler.lua"},
    ui          = {name="Toolbox_ui",         url=mpath.."Toolbox_ui.lua"},
    LuaCompiler = {name="Toolbox_luacompiler",url=mpath.."Toolbox_luacompiler.lua"},
    LuaParser   = {name="Toolbox_luaparser",  url=mpath.."Toolbox_luaparser.lua"},
  }

  function fetchFiles(files,content,cont)
    local req = net.HTTPClient()
    if #files == 0 then return cont() end
    local f0 = files[1]
    table.remove(files,1)
    local f = moduleMap[f0]
    if not f then quickApp:errorf("No module %s",f0) return fetchFiles(files,content,cont) end
    quickApp:debugf("Fetching module  %s",f0)
    req:request(f.url,{
        options = {method = 'GET', checkCertificate = false, timeout=20000},
        success = function(res) 
          if res.status == 200 then
            content[#content+1]={name=f.name,content=res.data,isMain=false,isOpen=false,type="lua"}
            fetchFiles(files,content,cont)
          else quickApp:errorf("Error %s fetching file %s",res.status,f.url) end
        end,
        error  = function(res) 
          quickApp:errorf("Error %s fetching file %s",res,f.url)
          fetchFiles(files,content,cont)
        end
      })
  end
end

function Toolbox_Module.basic(self)
-- tostring optionally converting tables to json or custom conversion
-- If a table has a __tostring key bound to a function that function will be used to convert the table to a string
  local _tostring = tostring
  local json2
  self._orgToString= tostring -- good to have sometimes....
  function tostring(obj) 
    if type(obj)=='table' then
      if obj.__tostring then return obj.__tostring(obj)
      elseif self._2JSON then return self:prettyJsonFlat(obj) end
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

  local htmlCodes={['\n']='<br>', [' ']='&nbsp;'}
  local function _printf(self,fun,fmt,...)
    local str,str2,t1,t0,c1 = _format(fmt,...),nil,__TAG,__TAG
    str2=str
    if self._HTML and not hc3_emulator then 
      str2 = str2:gsub("([\n%s])",function(c) return htmlCodes[c] or c end)
      str2 = str2:gsub("(#T:)(.-)(#)",function(_,t) t1=t return "" end)
      str2 = str2:gsub("(#C:)(.-)(#)",function(_,c) c1=c return "" end)
    end
    if c1 then str2=string.format("<font color=%s>%s</font>",c1,str2) end
    __TAG = t1; fun(self,str2); __TAG = t0
    return str
  end

  function self:printTagAndColor(tag,color,fmt,...)
    assert(fmt,"print needs tag, color, and args")
    fmt = _format(fmt,...)
    local t = __TAG
    __TAG = tag or __TAG
    if hc3_emulator or not color then self:tracef(fmt,...) 
    else
      self:trace("<font color="..color..">"..fmt.."</font>") 
    end
    __TAG = t
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
    return text
  end

-- Enhanced debug functions converting tables to json and with formatting version
  local _debug,_trace,_error,_warning = self.debug,self.trace,self.error,self.warning
  function self:debug(...) if self._DEBUG then return _print(self,_debug,...) else return "" end end
  function self:trace(...) if self._TRACE then return _print(self,_trace,...) else return "" end end
  function self:error(...) return notifyIf(self,"alert",_print(self,_error,...)) end
  function self:warning(...) return notifyIf(self,"warning",_print(self,_warning,...)) end
  function self:debugf(fmt,...) if self._DEBUG then return _printf(self,_debug,fmt,...) else return "" end end
  function self:tracef(fmt,...) return _printf(self,_trace,fmt,...) end
  function self:errorf(fmt,...) return notifyIf(self,"alert",_printf(self,_error,fmt,...)) end
  function self:warningf(fmt,...) return notifyIf(self,"warning",_printf(self,_warning,fmt,...)) end

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

  local _updateProperty = self.updateProperty
  function self:updateProperty(prop,value,force)
    local _props = self.properties
    if _props==nil or _props[prop] ~= nil then
      return _updateProperty(self,prop,value,force)
    elseif self._PROPWARN then self:warningf("Trying to update non-existing property - %s",prop) end
  end
-- Change type of QA. Note, if types is changed the QA will restart
--function QuickApp:setType(typ)
--  if self.typ ~= typ then api.put("/devices/"..self.id,{type=typ}) end
--  self.type = typ
--end

-- Add notification to notification center
  local cachedNots = {}
  function self:notify(priority, title, text, reuse)
    assert(({info=true,warning=true,alert=true})[priority],"Wrong 'priority' - info/warning/critical")
    if reuse==nil then reuse = self._NOTIFYREUSE end
    local msgId = nil
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
    local nid = title..self.id
    if reuse then
      if cachedNots[nid] then
        msgId = cachedNots[nid]
      else
        local notifications = api.get("/notificationCenter")
        for _,n in ipairs(notifications) do
          if n.data and n.data.deviceId == self.id and n.data.title == title then
            msgId = n.id
            break
          end
        end
      end
    end
    if msgId then
      api.put("/notificationCenter/"..msgId, data)
    else
      local d = api.post("/notificationCenter", data)
      if d then cachedNots[nid] = d.id end
    end
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
    local ref = self._orgToString({}):match("%s(.*)")
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

  do
    local sortKeys = {"type","device","deviceID","value","oldValue","val","key","arg","event","events","msg","res"}
    local sortOrder={}
    for i,s in ipairs(sortKeys) do sortOrder[s]="\n"..string.char(i+64).." "..s end
    local function keyCompare(a,b)
      local av,bv = sortOrder[a] or a, sortOrder[b] or b
      return av < bv
    end

    -- our own json encode, as we don't have 'pure' json structs, and sorts keys in order (i.e. "stable" output)
    function self:prettyJsonFlat(e) 
      local res,seen = {},{}
      local function pretty(e)
        local t = type(e)
        if t == 'string' then res[#res+1] = '"' res[#res+1] = e res[#res+1] = '"'
        elseif t == 'number' then res[#res+1] = e
        elseif t == 'boolean' or t == 'function' or t=='thread' or t=='userdata' then res[#res+1] = tostring(e)
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

    function self:prettyJsonStruct(t0)
      local res = {}
      local function isArray(t) return type(t)=='table' and t[1] end
      local function isEmpty(t) return type(t)=='table' and next(t)==nil end
      local function printf(tab,fmt,...) res[#res+1] = string.rep(' ',tab)..string.format(fmt,...) end
      local function pretty(tab,t,key)
        if type(t)=='table' then
          if isEmpty(t) then printf(0,"[]") return end
          if isArray(t) then
            printf(key and tab or 0,"[\n")
            for i,k in ipairs(t) do
              local _ = pretty(tab+1,k,true)
              if i ~= #t then printf(0,',') end
              printf(tab+1,'\n')
            end
            printf(tab,"]")
            return true
          end
          local r = {}
          for k,_ in pairs(t) do r[#r+1]=k end
          table.sort(r,keyCompare)
          printf(key and tab or 0,"{\n")
          for i,k in ipairs(r) do
            printf(tab+1,'"%s":',k)
            local _ =  pretty(tab+1,t[k])
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
          printf(key and tab or 0,'"%s"',t:gsub('(%")','\\"'))
        end
      end
      pretty(0,t0,true)
      return table.concat(res,"")
    end
  end
  json2 = self.prettyJsonFlat

  local IPaddress = nil
  function self:getHC3IPaddress(name)
    if IPaddress then return IPaddress end
    if hc3_emulator then return hc3_emulator.IPaddress
    else
      name = name or ".*"
      local networkdata = api.get("/proxy?url=http://localhost:11112/api/settings/network")
      for n,d in pairs(networkdata.networkConfig or {}) do
        if n:match(name) and d.enabled then IPaddress = d.ipConfig.ip; return IPaddress end
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

  function urlencode(str) -- very useful
    if str then
      str = str:gsub("\n", "\r\n")
      str = str:gsub("([^%w %-%_%.%~])", function(c)
          return ("%%%02X"):format(string.byte(c))
        end)
      str = str:gsub(" ", "%%20")
    end
    return str	
  end

  local function syncGet(url,user,pwd)
    local h,b = url:match("(.-)//(.*)")
    if pwd then
      pwd = urlencode(user)..":"..urlencode(pwd).."@"
    else pwd = "" end
    url=h.."//"..pwd..b
    return api.get("/proxy?url="..urlencode(url))
  end


  local function copy(expr)
    if type(expr)=='table' then
      local r = {}
      for k,v in pairs(expr) do r[k]=copy(v) end
      return r
    else return expr end
  end

  self.util = { copy = copy }

  netSync = { HTTPClient = function (log)   
      local self,queue,HTTP,key = {},{},net.HTTPClient(),0
      local _request
      local function dequeue()
        table.remove(queue,1)
        local v = queue[1]
        if v then 
          if _debugFlags.netSync then self:debugf("netSync:Pop %s (%s)",v[3],#queue) end
          --setTimeout(function() _request(table.unpack(v)) end,1) 
          _request(table.unpack(v))
        end
      end
      _request = function(url,params,key)
        params = copy(params)
        local uerr,usucc = params.error,params.success
        params.error = function(status)
          if _debugFlags.netSync then self:debugf("netSync:Error %s %s",key,status) end
          dequeue()
          if params._logErr then self:errorf(" %s:%s",log or "netSync:",tojson(status)) end
          if uerr then uerr(status) end
        end
        params.success = function(status)
          if _debugFlags.netSync then self:debugf("netSync:Success %s",key) end
          dequeue()
          if usucc then usucc(status) end
        end
        if _debugFlags.netSync then self:debugf("netSync:Calling %s",key) end
        HTTP:request(url,params)
      end
      function self:request(url,parameters)
        key = key+1
        if next(queue) == nil then
          queue[1]='RUN'
          _request(url,parameters,key)
        else 
          if _debugFlags.netSync then self:debugf("netSync:Push %s",key) end
          queue[#queue+1]={url,parameters,key} 
        end
      end
      return self
    end}

  do
    local settimeout,setinterval,encode,decode =  -- gives us a better error messages
    setTimeout, setInterval, json.encode, json.decode
    local oldClearTimout,oldSetTimout

    if not hc3_emulator then -- Patch short-sighthed setTimeout...
      clearTimeout,oldClearTimout=function(ref)
        if type(ref)=='table' and ref[1]=='%EXT%' then ref=ref[2] end
        oldClearTimout(ref)
      end,clearTimeout

      setTimeout,oldSetTimout=function(f,ms)
        local ref,maxt={'%EXT%'},2147483648-1
        local fun = function() -- wrap function to get error messages
          local stat,res = pcall(f)
          if not stat then 
            error(res,2)
          end
        end
        if ms > maxt then
          ref[2]=oldSetTimout(function() ref[2 ]=setTimeout(fun,ms-maxt)[2] end,maxt)
        else ref[2 ]=oldSetTimout(fun,math.floor(ms+0.5)) end
        return ref
      end,setTimeout

      function setInterval(fun,ms) -- can't manage looong intervals
        return setinterval(function()
            local stat,res = pcall(fun)
            if not stat then 
              error(res,2)
            end
          end,math.floor(ms+0.5))
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

  local traceFuns = {
    'call','get','getValue'
  }

  do 
    local p = print
    function print(a,...) 
      if a~='onAction: ' or self._ONACTIONLOG then
        p(a,...) 
      end
    end
  end
end