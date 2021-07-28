--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2020 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Sources included:
json           -- Copyright (c) 2020 rxi
--]]

local PARAMS=...
local embedded = PARAMS
PARAMS = PARAMS or { 
  user="admin", pwd="admin", host="192.168.1.57",
  -- ,temp = 'temp/' -- If not present will try to use temp env variables
} 

local function main(run) -- playground


--  run{file='GEA_v7.20.fqa'}
  local testQA = [[
  --%%quickVars={x='Hello'}
  function QuickApp:onInit()
    self:debug(self.name,self.id)
    self:debug("quickVar","x=",self:getVariable("x"))
    local n = 5
    setInterval(function() 
       self:debug("PP") 
       n=n-1
       if n <= 0 then os.exit() end
      end,1000)
  end
]]

  run{code=[[
print("Start")
--%%name='TestQA1'
function QuickApp:onInit()
    function self:debugf(...) self:debug(string.format(...)) end
    self:debugf("%s - %s",self.name,self.id)
    self:debugf("Name1:%s",fibaro.getName(self.id))
    self:debugf("Name2:%s",api.get("/devices/"..self.id).name)
    self:debugf("Name3:%s",__fibaro_get_device(self.id).name)
    hc3_emulator.installQA{name="MuQA",code=testQA} -- install another QA and run it
end
--]],env={testQA=testQA}}

--loadfile("emu_tests.lua")(run)
end

---------------------------------------- TQAE -------------------------------------------------------------
local stat,mobdebug = pcall(require,'mobdebug'); -- If we have mobdebug, enable coroutine debugging
if stat then mobdebug.coro() end
local http    = require("socket.http")
local socket  = require("socket")
local ltn12   = require("ltn12")
local version = "0.2"

local fmt,module,fibaro,net,api,setContext,getContext,getQA,xpresume,call,lock,class,json,loadFile,property=string.format,{} -- Shared between modules
local __assert_type
local __ternary
local __fibaro_get_device
local __fibaro_get_devices
local __fibaro_get_room
local __fibaro_get_scene
local __fibaro_get_global_variable
local __fibaro_get_device_property 
local __fibaroSleep
local __fibaro_add_debug_message

------------------------ Builtin functions ------------------------------------------------------
function module.builtin()
  net = {}
  function net.HTTPClient(i_options)   
    local self = {}                   
    function self:request(url,args)
      local req,resp = {},{}; for k,v in pairs(i_options or {}) do req[k]=v end
      for k,v in pairs(args.options or {}) do req[k]=v end
      req.timeout = (req.timeout or (i_options and i_options.timeout) or 0) / 10000.0
      req.url,req.headers,req.sink = url,req.headers or {},ltn12.sink.table(resp)
      if req.data then
        req.headers["Content-Length"] = #req.data
        req.source = ltn12.source.string(req.data)
      else req.headers["Content-Length"]=0 end
      local i,status,headers = http.request(req)
      if req.sync then return i,status,resp
      elseif tonumber(status) and status < 205 and args.success then 
        setTimeout(function() args.success({status=status,headers=headers,data=table.concat(resp)}) end,math.random(0,2))
      elseif args.error then setTimeout(function() args.error(status) end,math.random(0,2)) end
    end
    self.__tostring = function() return "HTTPClient object: "..tostring(self):match("%s(.*)") end
    return self
  end

  local HC3call2
  local apiIntercepts = { -- Intercept some api calls to the api to include emulated QAs, could be deeper a tree...
    ["GET"] = {
      ["/devices$"] = function(_,_,_,...) return __fibaro_get_devices() end,
      ["/devices/(%d+)$"] = function(_,_,_,id) return __fibaro_get_device(tonumber(id)) end,
      ["/devices/(%d+)/properties/(%w+)$"] = function(_,_,_,id,prop) return __fibaro_get_device_property(tonumber(id),prop) end,
    },
    ["POST"] = {
      ["/devices/(%d+)/action/([%w_]+)$"] = function(_,path,data,id,action)
        id=tonumber(id)
        return getQA(id) and call(id,action,table.unpack(data.args)) or HC3call2("POST",path,data)
      end,
    }
  }

  function HC3call2(method,path,data) -- Used to call out to the real HC3
    local _,status,res = net.HTTPClient():request("http://"..PARAMS.host.."/api"..path,{
        options = { method = method, data=data and json.encode(data), user=PARAMS.user, password=PARAMS.pwd, sync=true,
          headers = { ["Accept"] = '*/*',["X-Fibaro-Version"] = 2, ["Fibaro-User-PIN"] = PARAMS.pin }}
      })
    if tonumber(status) and status < 300 then return res[1] and json.decode(table.concat(res)) or nil,status else return nil,status end
  end

  local function HC3call(method,path,data) -- Intercepts some cmds to handle local resources
    for p,f in pairs(apiIntercepts[method] or {}) do
      local m = {path:match(p)}
      if #m>0 then local res,code = f(method,path,data,table.unpack(m)) if code~=false then return res,code end end
    end
    return HC3call2(method,path,data) -- Call without intercept
  end

  api = {} -- Normal user calls to api will have pass==nil and the cmd will be intercepted if needed. __fibaro_* will always pass
  function api.get(cmd) return HC3call("GET",cmd) end
  function api.post(cmd,data) return HC3call("POST",cmd,data) end
  function api.put(cmd,data) return HC3call("PUT",cmd,data) end
  function api.delete(cmd) return HC3call("DELETE",cmd) end

  function __assert_type(value,typeOfValue )
    if type(value) ~= typeOfValue then  -- Wrong parameter type, string required. Provided param 'nil' is type of nil
      error(fmt("Wrong parameter type, %s required. Provided param '%s' is type of %s",
          typeOfValue,tostring(value),type(value)),
        3)
    end
  end
  function __ternary(test, a1, a2) if test then return a1 else return a2 end end
-- basic api functions, tries to deal with local emulated QAs too. Local QAs have precedence over HC3 QAs.
  function __fibaro_get_device(id) __assert_type(id,"number") return getQA(id) or HC3call2("GET","/devices/"..id) end
  function __fibaro_get_devices() 
    local ds = HC3call2("GET","/devices") or {}
    for _,qa in pairs(getQA()) do ds[#ds+1]=qa.QA end -- Add emulated QAs
    return ds 
  end 
  function __fibaro_get_room (id) __assert_type(id,"number") return HC3call2("GET","/rooms/"..id) end
  function __fibaro_get_scene(id) __assert_type(id,"number") return HC3call2("GET","/scenes/"..id) end
  function __fibaro_get_global_variable(name) __assert_type(name ,"string") return HC3call2("GET","/globalVariables/"..name) end
  function __fibaro_get_device_property(id ,prop) 
    __assert_type(id,"number") __assert_type(prop,"string")
    local qa = getQA(id) -- Is it a local QA?
    if qa then return qa.properties[prop] and { value = qa.properties[prop], modified=0} or nil
    else return HC3call2("GET","/devices/"..id.."/properties/"..prop) end
  end
  function __fibaroSleep(ms) -- We lock all timers/coroutines except the one resuming the sleep after ms
    local r,qa,co; co,r = coroutine.running(),setTimeout(function() setContext(co,qa) lock(r,false) xpresume(co) end,ms) 
    qa = getContext() lock(r,true); coroutine.yield(co)
  end

  function __fibaro_add_debug_message(tag,type,str)
    assert(str,"Missing tag for debug")
    str=str:gsub("(</?font.->)","") str=str:gsub("(&nbsp;)"," ") -- Remove HTML tags
    print(fmt("%s [%s] [%s]: %s",os.date("[%d.%m.%Y] [%H:%M:%S]"),type,tag,str))
  end

-- Class support, mimicking LuaBind's class implementation
  local metas = {}
  for _,m in ipairs({
      "__add","__sub","__mul","__div","__mod","__pow","__unm","__idiv","__band","__bor",
      "__bxor","__bnot","__shl","__shr","__concat","__len","__eq","__lt","__le","__call",
      "__tostring"
      }) do
    metas[m]=true
  end

  function property(get,set)
    assert(type(get)=='function' and type(set)=="function","Property need function set and get")
    return {['%CLASSPROP%']=true, get=get, set=set}
  end

  local function trapIndex(props,cmt,obj)
    function cmt.__index(_,key)
      if props[key] then return props[key].get(obj) else return rawget(obj,key) end
    end
    function cmt.__newindex(_,key,val)
      if props[key] then return props[key].set(obj,val) else return rawset(obj,key,val) end
    end
  end

  function class(name)       -- Version that tries to avoid __index & __newindex to make debugging easier
    local cl,mt,cmt,props,parent= {['_TYPE']='userdata'},{},{},{}  -- We still try to be Luabind class compatible
    function cl.__copyObject(cl,obj)
      for k,v in pairs(cl) do if metas[k] then cmt[k]=v else obj[k]=v end end
      return obj
    end
    function mt.__call(tab,...)        -- Instantiation  <name>(...)
      local obj = tab.__copyObject(tab,{})
      if not tab.__init then error("Class "..name.." missing initialiser") end
      tab.__init(obj,...)
      local trapF = false
      for k,v in pairs(obj) do
        if type(v)=='table' and v['%CLASSPROP%'] then obj[k],props[k]=nil,v; trapF = true end
      end
      if trapF then trapIndex(props,cmt,obj) end
      local str = "Object "..name..":"..tostring(obj):match("%s(.*)")
      setmetatable(obj,cmt)
      if not obj.__tostring then 
        function obj:__tostring() return str end
      end
      return obj
    end
    function mt:__tostring() return "class "..name end
    setmetatable(cl,mt)
    getContext().env[name] = cl
    return function(p) -- Class creation -- class <name>
      parent = p 
      if parent then parent.__copyObject(parent,cl) end
    end 
  end
end

------------------------ fibaro.* functions -----------------------------------------------------
function module.fibaro()
  fibaro = {}
  function fibaro.alarm(arg1, action)
    if type(arg1) == "string" then fibaro.__houseAlarm(arg1)
    else
      __assert_type(arg1, "number") __assert_type(action, "string")
      local url = "/alarms/v1/partitions/"..arg1.."/actions/arm"
      if action == "arm" then api.post(url)
      elseif action == "disarm" then api.delete(url)
      else error("Wrong parameter: "..action..". Available parameters: arm, disarm", 2) end     
    end
  end

  function fibaro.__houseAlarm(action)
    __assert_type(action, "string")
    local url = "/alarms/v1/partitions/actions/arm"
    if action == "arm" then api.post(url)
    elseif action == "disarm" then api.delete(url)
    else error("Wrong parameter: '" .. action .. "'. Available parameters: arm, disarm", 3) end
  end

  function fibaro.alert(alertType, ids, notification)
    __assert_type(alertType, "string") __assert_type(ids, "table") __assert_type(notification, "string")
    local isDefined = "false"
    local actions = { 
      email = "sendGlobalEmailNotifications",
      push = "sendGlobalPushNotifications" 
    }
    if actions[alertType] == nil then
      error("Wrong parameter: '" .. alertType .. "'. Available parameters: email, push", 2) 
    end
    for _, id in ipairs(ids) do __assert_type(id, "number") end      
    for _, id in ipairs(ids) do 
      fibaro.call(id, actions[alertType], notification, isDefined)
    end
  end

  function fibaro.emitCustomEvent(name)
    __assert_type(name, "string")
    api.post("/customEvents/" .. name)
  end

  function fibaro.call(deviceId, actionName, ...)
    __assert_type(actionName, "string")
    if type(deviceId) == "table" then
      for _, id in pairs(deviceId) do __assert_type(id, "number") end      
      for _, id in pairs(deviceId) do fibaro.call(id, actionName, ...) end 
      return
    end
    __assert_type(deviceId, "number")
    local arg= {...}; arg = #arg > 0 and arg or nil
    api.post("/devices/"..deviceId.."/action/"..actionName, { args = arg })
  end

  function fibaro.callGroupAction(actionName, actionData)
    __assert_type(actionName, "string") __assert_type(actionData, "table")
    local response, status = api.post("/devices/groupAction/" .. actionName, actionData)
    if status ~= 202 then return nil
    else return response["devices"] end
  end

  function fibaro.get(deviceId, propertyName)
    __assert_type(deviceId, "number") __assert_type(propertyName, "string")
    local property = __fibaro_get_device_property(deviceId, propertyName)
    if property then return property.value, property.modified end
  end

  function fibaro.getValue(deviceId, propertyName)
    __assert_type(deviceId, "number") __assert_type(propertyName, "string")
    return (fibaro.get(deviceId, propertyName))
  end

  function fibaro.getType(deviceId)
    __assert_type(deviceId, "number")
    return (__fibaro_get_device(deviceId) or {}).type
  end

  function fibaro.getName(deviceId)
    __assert_type(deviceId, 'number')
    return (__fibaro_get_device(deviceId) or {}).name
  end

  function fibaro.getRoomID(deviceId)
    __assert_type(deviceId, 'number')
    return (__fibaro_get_device(deviceId) or {}).roomID
  end

  function fibaro.getSectionID(deviceId)
    __assert_type(deviceId, 'number')
    local dev = __fibaro_get_device(deviceId)
    if dev ~= nil then return __fibaro_get_room(dev.roomID).sectionID end
  end

  function fibaro.getRoomName(roomId)
    __assert_type(roomId, 'number')
    return (__fibaro_get_room(roomId) or {}).name
  end

  function fibaro.getRoomNameByDeviceID(deviceId)
    __assert_type(deviceId, 'number')
    local dev = __fibaro_get_device(deviceId)
    return dev and fibaro.getRoomName(dev.roomID) or nil
  end

  function fibaro.getDevicesID(filter)
    if type(filter) ~= 'table' or (type(filter) == 'table' and next(filter) == nil) then
      return fibaro.getIds(__fibaro_get_devices())
    end
    local buff={}
    local function out(s) buff[#buff+1]=s end
    out('/?')
    for c, d in pairs(filter) do
      if c == 'properties' and d ~= nil and type(d) == 'table' then
        for a, b in pairs(d) do
          if b == "nil" then out('property='..tostring(a))
          else out('property=['.. tostring(a)..','..tostring(b)..']') end
        end
      elseif c == 'interfaces' and d ~= nil and type(d) == 'table' then
        for _,b in pairs(d) do out('interface='..tostring(b)) end
      else out(tostring(c).."="..tostring(d)) end
    end
    local args = table.concat(buff,'&')
    return fibaro.getIds(api.get('/devices'..args))
  end

  function fibaro.getIds(devices)
    local ids = {}
    for _, a in pairs(devices) do
      if a ~= nil and type(a) == 'table' and a['id'] ~= nil and a['id'] > 3 then
        table.insert(ids, a['id'])
      end
    end
    return ids
  end

  function fibaro.getGlobalVariable(name)
    __assert_type(name, 'string')
    local g = __fibaro_get_global_variable(name)
    if g then return g.value, g.modified end
  end

  function fibaro.setGlobalVariable (name, value)
    __assert_type(name, 'string') __assert_type(value, 'string')
    api.put("/globalVariables/" .. name, {["value"]=tostring(value), ["invokeScenes"]=true})
  end

  function fibaro.scene(action, ids)
    __assert_type(action, "string") __assert_type(ids, "table")
    local availableActions = { execute = true , kill = true}
    assert(availableActions[action],"Wrong parameter: " .. action .. ". Available actions: execute, kill") 
    for _, id in ipairs(ids) do __assert_type(id, "number") end      
    for _, id in ipairs(ids) do api.post("/scenes/"..id.."/"..action) end
  end

  function fibaro.profile(action, profileId)
    __assert_type(profileId, "number") __assert_type(action, "string")
    local availableActions = { activateProfile = "activeProfile"} 
    assert(availableActions[action],"Wrong parameter: "..action..". Available actions: activateProfile") 
    api.post("/profiles/"..availableActions[action].."/"..profileId)
  end

  function fibaro.setTimeout(timeout, action)
    __assert_type(timeout, "number") __assert_type(action, "function")
    return setTimeout(action, timeout)
  end

  function fibaro.clearTimeout(timeoutId)
    __assert_type(timeoutId, "table")
    clearTimeout(timeoutId)
  end

  function fibaro.wakeUpDeadDevice(deviceID)
    __assert_type(deviceID, 'number')
    fibaro.call(1, 'wakeUpDeadDevice', deviceID)
  end

  function fibaro.sleep(ms)
    __assert_type(ms, "number")
    __fibaroSleep(ms)
  end

  local function d2str(...) local r,s={...},{} for i=1,#r do if r[i]~=nil then s[#s+1]=tostring(r[i]) end end return table.concat(s," ") end
  function fibaro.debug(tag,...)  __assert_type(tag,"string") __fibaro_add_debug_message(tag,"DEBUG",d2str(...)) end
  function fibaro.warning(tag,...) __assert_type(tag,"string") __fibaro_add_debug_message(tag,"WARNING",d2str(...)) end
  function fibaro.trace(tag,...) __assert_type(tag,"string") __fibaro_add_debug_message(tag,"TRACE",d2str(...)) end
  function fibaro.error(tag,...) __assert_type(tag,"string") __fibaro_add_debug_message(tag,"ERROR",d2str(...)) end

  function fibaro.useAsyncHandler(value)
    __assert_type(value, "boolean")
    --__fibaroUseAsyncHandler(value) -- TBD
  end
end

------------------------ Json encode/decode support, Copyright (c) 2020 rxi ---------------------
function module.json()
-- Copyright (c) 2020 rxi
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--
  json = { _version = "0.1.2" }
-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------
  local encode
  local escape_char_map = {
    [ "\\" ] = "\\\\",[ "\"" ] = "\\\"",[ "\b" ] = "\\b",[ "\f" ] = "\\f",[ "\n" ] = "\\n",[ "\r" ] = "\\r",[ "\t" ] = "\\t",
  }

  local escape_char_map_inv = { [ "\\/" ] = "/" }
  for k, v in pairs(escape_char_map) do escape_char_map_inv[v] = k end
  local function escape_char(c) return escape_char_map[c] or string.format("\\u%04x", c:byte()) end
  local function encode_nil(_) return "null" end


  local function encode_table(val, stack)
    local res = {}
    stack = stack or {}
    -- Circular reference?
    if stack[val] then error("circular reference") end
    stack[val] = true
    if rawget(val, 1) ~= nil or next(val) == nil then
      -- Treat as array -- check keys are valid and it is not sparse
      local n = 0
      for k in pairs(val) do 
        if type(k) ~= "number" then error("invalid table: mixed or invalid key types") end
        n = n + 1
      end
      if n ~= #val then error("invalid table: sparse array") end
      -- Encode
      for _, v in ipairs(val) do table.insert(res, encode(v, stack)) end
      stack[val] = nil
      return "[" .. table.concat(res, ",") .. "]"
    else
      -- Treat as an object
      for k, v in pairs(val) do
        if type(k) ~= "string" then error("invalid table: mixed or invalid key types") end
        table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
      end
      stack[val] = nil
      return "{" .. table.concat(res, ",") .. "}"
    end
  end

  local function encode_string(val) return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"' end

  local function encode_number(val)
    -- Check for NaN, -inf and inf
    if val ~= val or val <= -math.huge or val >= math.huge then error("unexpected number value '" .. tostring(val) .. "'") end
    return string.format("%.14g", val)
  end

  local type_func_map = {
    ["nil"] = encode_nil, ["table"] = encode_table,["string" ] = encode_string,["number"] = encode_number,["boolean"] = tostring,
    --   [ "function" ] = tostring,
  }

  encode = function(val, stack)
    local t = type(val)
    local f = type_func_map[t]
    if f then return f(val, stack) end
    error("unexpected type '" .. t .. "'")
  end

  function json.encode(val,...)
    local extras = {...}
    assert(#extras==0,"Too many arguments to json.encode?")
    local res = {pcall(encode,val)}
    if res[1] then return select(2,table.unpack(res))
    else 
      local info = debug.getinfo(2)
      error(string.format("json.encode, %s, called from %s line:%s",res[2],info.short_src,info.currentline))
    end
  end
-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------
  local parse
  local function create_set(...)
    local res = {}
    for i = 1, select("#", ...) do res[ select(i, ...) ] = true end
    return res
  end

  local space_chars   = create_set(" ", "\t", "\r", "\n")
  local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
  local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
  local literals      = create_set("true", "false", "null")

  local literal_map = { [ "true"  ] = true, [ "false" ] = false, [ "null"  ] = nil, }

  local function next_char(str, idx, set, negate)
    for i = idx, #str do if set[str:sub(i, i)] ~= negate then return i end end
    return #str + 1
  end

  local function decode_error(str, idx, msg)
    local line_count = 1
    local col_count = 1
    for i = 1, idx - 1 do
      col_count = col_count + 1
      if str:sub(i, i) == "\n" then line_count = line_count + 1 col_count = 1 end
    end
    error( string.format("%s at line %d col %d", msg, line_count, col_count) )
  end

  local function codepoint_to_utf8(n)
    -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
    local f = math.floor
    if n <= 0x7f then return string.char(n)
    elseif n <= 0x7ff then return string.char(f(n / 64) + 192, n % 64 + 128)
    elseif n <= 0xffff then return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
    elseif n <= 0x10ffff then return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128, f(n % 4096 / 64) + 128, n % 64 + 128) end
    error( string.format("invalid unicode codepoint '%x'", n) )
  end

  local function parse_unicode_escape(s)
    local n1 = tonumber( s:sub(3, 6),  16 )
    local n2 = tonumber( s:sub(9, 12), 16 )
    -- Surrogate pair?
    if n2 then return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
    else return codepoint_to_utf8(n1) end
  end

  local function parse_string(str, i)
    local has_unicode_escape = false
    local has_surrogate_escape = false
    local has_escape = false
    local last
    for j = i + 1, #str do
      local x = str:byte(j)
      if x < 32 then decode_error(str, j, "control character in string") end
      if last == 92 then -- "\\" (escape char)
        if x == 117 then -- "u" (unicode escape sequence)
          local hex = str:sub(j + 1, j + 5)
          if not hex:find("%x%x%x%x") then decode_error(str, j, "invalid unicode escape in string") end
          if hex:find("^[dD][89aAbB]") then has_surrogate_escape = true
          else has_unicode_escape = true end
        else
          local c = string.char(x)
          if not escape_chars[c] then decode_error(str, j, "invalid escape char '" .. c .. "' in string") end
          has_escape = true
        end
        last = nil
      elseif x == 34 then -- '"' (end of string)
        local s = str:sub(i + 1, j - 1)
        if has_surrogate_escape then s = s:gsub("\\u[dD][89aAbB]..\\u....", parse_unicode_escape) end
        if has_unicode_escape then s = s:gsub("\\u....", parse_unicode_escape) end
        if has_escape then s = s:gsub("\\.", escape_char_map_inv) end
        return s, j + 1
      else last = x end
    end
    decode_error(str, i, "expected closing quote for string")
  end

  local function parse_number(str, i)
    local x = next_char(str, i, delim_chars)
    local s = str:sub(i, x - 1)
    local n = tonumber(s)
    if not n then decode_error(str, i, "invalid number '" .. s .. "'") end
    return n, x
  end

  local function parse_literal(str, i)
    local x = next_char(str, i, delim_chars)
    local word = str:sub(i, x - 1)
    if not literals[word] then decode_error(str, i, "invalid literal '" .. word .. "'") end
    return literal_map[word], x
  end

  local function parse_array(str, i)
    local res = {}
    local n = 1
    i = i + 1
    while 1 do
      local x
      i = next_char(str, i, space_chars, true)
      -- Empty / end of array?
      if str:sub(i, i) == "]" then i = i + 1 break end
      -- Read token
      x, i = parse(str, i)
      res[n] = x
      n = n + 1
      -- Next token
      i = next_char(str, i, space_chars, true)
      local chr = str:sub(i, i)
      i = i + 1
      if chr == "]" then break end
      if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
    end
    return res, i
  end

  local function parse_object(str, i)
    local res = {}
    i = i + 1
    while 1 do
      local key, val
      i = next_char(str, i, space_chars, true)
      -- Empty / end of object?
      if str:sub(i, i) == "}" then i = i + 1 break end
      -- Read key
      if str:sub(i, i) ~= '"' then decode_error(str, i, "expected string for key") end
      key, i = parse(str, i)
      -- Read ':' delimiter
      i = next_char(str, i, space_chars, true)
      if str:sub(i, i) ~= ":" then decode_error(str, i, "expected ':' after key") end
      i = next_char(str, i + 1, space_chars, true)
      -- Read value
      val, i = parse(str, i)
      -- Set
      res[key] = val
      -- Next token
      i = next_char(str, i, space_chars, true)
      local chr = str:sub(i, i)
      i = i + 1
      if chr == "}" then break end
      if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
    end
    return res, i
  end

  local char_func_map = {
    [ '"' ] = parse_string, [ "0" ] = parse_number, [ "1" ] = parse_number,[ "2" ] = parse_number,
    [ "3" ] = parse_number, [ "4" ] = parse_number,[ "5" ] = parse_number,[ "6" ] = parse_number, [ "7" ] = parse_number,
    [ "8" ] = parse_number, [ "9" ] = parse_number, [ "-" ] = parse_number, [ "t" ] = parse_literal,
    [ "f" ] = parse_literal, [ "n" ] = parse_literal, [ "[" ] = parse_array,[ "{" ] = parse_object,
  }

  parse = function(str, idx)
    local chr = str:sub(idx, idx)
    local f = char_func_map[chr]
    if f then return f(str, idx) end
    decode_error(str, idx, "unexpected character '" .. chr .. "'")
  end

  function json.decode(str)
    local res = {pcall(function()
          if type(str) ~= "string" then error("expected argument of type string, got " .. type(str)) end
          local res, idx = parse(str, next_char(str, 1, space_chars, true))
          idx = next_char(str, idx, space_chars, true)
          if idx <= #str then decode_error(str, idx, "trailing garbage") end
          return res
        end)}
    if res[1] then return select(2,table.unpack(res))
    else 
      local info = debug.getinfo(2)
      error(string.format("json.encode, %s, called from %s line:%s",res[2],info.short_src,info.currentline))
    end
  end 
end

------------------------ File support -----------------------------------------------------------
function module.files()

  local function readFile(file) 
    local f = io.open(file); assert(f,"No such file:"..file) local c = f:read("*all"); f:close() return c
  end

  local TEMP = PARAMS.temp or os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "temp/" -- Try
  local function createTemp(name,content) -- Storing code fragments on disk will help debugging. TBD
    local fname = TEMP..name..".lua"  
    local f,res = io.open(fname,"w+")
    if not f then print("Warning - couldn't create temp files in "..TEMP.." "..res) return end
    f:write(content) 
    f:close()
    return fname
  end

  local function loadSource(code,fileName) -- Load code and resolve info and --FILE directives
    local files = {}
    local function gf(pattern)
      code = code:gsub(pattern,
        function(file,name)
          files[#files+1]={name=name,content=readFile(file),isMain=false,fname=file}
          return ""
        end)
    end
    gf([[%-%-FILE:%s*(.-)%s*,%s*(.-);]])
    table.insert(files,{name="main",content=code,isMain=true,fname=fileName})
    local info = code:match("%-%-%[%[QAemu(.-)%-%-%]%]")
    if info==nil then
      local il = {}
      code:gsub("%-%-%%%%(.-)[\n\r]+",function(l) il[#il+1]=l end)
      info=table.concat(il,",")
    end
    if info then 
      local code,res = load("return {"..info.."}")
      if not code then error(res) end
      info,res = code()
      if res then error(res) end
    end
    return files,(info or {})
  end

  local function loadLua(fileName) return loadSource(readFile(fileName),fileName) end

  local function loadFQA(fqa)  -- Load FQA
    local files,main = {}
    for _,f in ipairs(fqa.files) do
      local fname = createTemp(f.name,f.content) or f.name -- Create temp files for fqa files, easier to debug
      if f.isMain then f.fname=fname main=f
      else files[#files+1] = {name=f.name,content=f.content,isMain=f.isMain,fname=fname} end
    end
    table.insert(files,main)
    return files,{name=fqa.name,type=fqa.type,properties=fqa.initialProperties}
  end

  function loadFile(code,file)
    if file and not code then
      if file:match("%.fqa$") then return loadFQA(json.decode(readFile(file)))
      elseif file:match("%.lua$") then return loadLua(file)
      else error("No such file:"..file) end
    elseif type(code)=='table' then  -- fqa table
      return loadFQA(code)
    elseif code then
      local fname = file or createTemp("main",code) or "main" -- Create temp file for string code easier to debug
      return loadSource(code,fname)
    end
  end
end

------------------------ QuickApp code ----------------------------------------------------------
module.QuickApp = [[ 
  -- Easier to define it here as it is done in the right environment
  -- We load one per QA
  __TAG="QUICKAPP"..plugin.mainDeviceId
  
  QuickApp = {['_TYPE']='userdata'}
  function QuickApp:__init(dev) -- our QA is a fake "class"
    self.id = dev.id
    self.name=dev.name
    self.type = dev.type
    self.enabled = true
    self.properties = dev.properties
    self._view = {} -- TBD
    if self.onInit then self:onInit() end
    quickApp = self
  end

  function QuickApp:debug(...) fibaro.debug(__TAG,...) end
  function QuickApp:error(...) fibaro.error(__TAG,...) end
  function QuickApp:warning(...) fibaro.warning(__TAG,...) end
  function QuickApp:trace(...) fibaro.trace(__TAG,...) end
    
  function QuickApp:callAction(name,...)
    __assert_type(self[name],'function')
    self[name](self,...) 
    end
    
  function QuickApp:getVariable(name)
    for _,v in ipairs(self.properties.quickAppVariables or {}) do if v.name==name then return v.value end end
    return ""
  end
  
  function QuickApp:setVariable(name,value)
    local vars = self.properties.quickAppVariables or {}
    for _,v in ipairs(vars) do if v.name==name then v.value=value return end end
    self.properties.quickAppVariables = vars
    vars[#vars+1]={name=name,value==value}
  end
  
  function QuickApp:updateProperty(prop,val) self.properties[prop]=val end
  
  function QuickApp:updateView(elm,typ,val) 
    self:debug("View:",elm,typ,val)
    self._view[elm]=self._view[elm] or {} self._view[elm][typ]=val 
  end
  
  function onAction(self,event)
    print("onAction: ", json.encode(event))
    if self.actionHandler then self:actionHandler(event)
    else self:callAction(event.actionName, table.unpack(event.args)) end
  end
]]

------------------------ Emulator core ----------------------------------------------------------
function module.emulator()
  local QADir,tasks,procs,CO,clock,insert,gID = {},{},{},coroutine,socket.gettime,table.insert,1001
  function getQA(id) if id==nil then return QADir else local qa = QADir[id] if qa then return qa.QA,qa.env end end end
  local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
  -- meta table to print threads like "thread ..."
  local tmt={ __tostring = function(t) return t[4] end}
  -- Insert timer in queue, sorted on ascending absolute time
  local function queue(t,co,q) 
    local v={t+os.time(),co,q,tostring(co)} setmetatable(v,tmt) 
    for i=1,#tasks do if v[1]<tasks[i][1] then insert(tasks,i,v) return v end end 
    tasks[#tasks+1]=v return v 
  end

  local function deqeue(i) local v = tasks[i]; table.remove(tasks,i) end
  -- Lock or unlock QA. peek8) will return first unlocked. Used by fibaro.sleep to lock all other timers in same QA
  function lock(t,b) if t[3] then t[3].env.locked = b and t[2] or nil end end

  local function locked(t) local locked = t[3] and t[3].env.locked; return locked and locked~=t[2] end
  -- set QA context to given or current coroutine - we can then pickup the context from the current coroutine
  function setContext(co,qa) procs[co]= qa or procs[coroutine.running()]; return co,procs[co] end

  function getContext(co) co=co or coroutine.running() return procs[co] end

  local function peek() for i=1,#tasks do if not locked(tasks[i]) then return i,table.unpack(tasks[i] or {}) end end end

  function setTimeout(fun,ms) return queue(ms/1000,setContext(CO.create(fun))) end
  -- Like setTimeout but sets another QA's context - used when starting up and fibaro.cal
  local function runProc(qa,fun) procs[coroutine.running()]=qa local r=setTimeout(fun,0)  return qa end

  function clearTimeout(ref) for i=1,#tasks do if ref==tasks[i] then table.remove(tasks,i) return end end end

  function setInterval(fun,ms) local r={} local function loop() fun() r[1],r[2],r[3]=table.unpack(setTimeout(loop,ms)) end loop() return r end

  function clearInterval(ref) clearTimeout(ref) end

  -- Used by fibaro.call to hand over to called QA's thread
  function call(id,name,...)
    local args,QA = {...},QADir[id]
    runProc(QA,function() QA.env.onAction(QA.QA,{deviceId=id,actionName=name,args=args}) end) -- sim. call in another process/QA
  end
  local function type2(o) local t = type(o) return t=='table' and o._TYPE or t end
  -- Check arguments and print a QA error message 
  local function check(name,stat,err) if not stat then __fibaro_add_debug_message(name,"ERROR",err) end return stat end
  -- Resume a coroutine and handle errors
  function xpresume(co)  
    local stat,res = CO.resume(co)
    if not stat then 
      check(procs[co].env.__TAG,stat,res) debug.traceback(co) 
    end
  end

  local function installQA(qa) -- code can be string or file
    local id,name,typ,code,file,e = qa.id,qa.name,qa.type,qa.code,qa.file,qa.env
    local env = {          -- QA environment, all Lua functions available for  QA, 
      plugin={}, fibaro=copy(fibaro), os=copy(os), json=json, hc3_emulator={getmetatable=getmetatable,installQA=installQA},
      __assert_type=__assert_type, __fibaro_get_device=__fibaro_get_device, __fibaro_get_devices=__fibaro_get_devices,
      __fibaro_get_room=__fibaro_get_room, __fibaro_get_scene=__fibaro_get_scene, 
      __fibaro_get_global_variable=__fibaro_get_global_variable, __fibaro_get_device_property=__fibaro_get_device_property,
      __fibaroSleep=__fibaroSleep, __fibaro_add_debug_message=__fibaro_add_debug_message,
      setTimeout=setTimeout, setInterval=setInterval, clearTimeout=clearTimeout, clearInterval=clearInterval,assert=assert,
      coroutine=CO,table=table,select=select,pcall=pcall,tostring=tostring,print=print,net=net,api=api,string=string,error=error,
      type=type2,pairs=pairs,ipairs=ipairs,tostring=tostring,tonumber=tonumber,math=math,class=class,propert=property
    }
    for s,v in pairs(e or {}) do env[s]=v end
    -- Setup device struct
    local files,info = loadFile(code,file)
    local dev = {}
    dev.id = info.id or id or gID; gID=gID+1
    env.plugin.mainDeviceId = dev.id
    dev.name = info.name or name or "MyQuickApp"
    dev.type = info.type or typ or "com.fibaro.binarySensor"
    dev.properties = info.properties or {}
    dev.properties.quickAppVariables = dev.properties.quickAppVariables or {}
    for k,v in pairs(info.quickVars or {}) do table.insert(dev.properties.quickAppVariables,{name=k,value=v}) end

    env.os.exit=function() print("exit(0)") tasks={} coroutine.yield() end
    local _,_ = load(module.QuickApp,nil,"t",env)() -- Load QuickApp code
    local self=env.QuickApp
    QADir[dev.id]={QA=self,env=env}
    print(fmt("Loading QA :%s - ID:%s",dev.name,dev.id))
    local k = coroutine.create(function()
        for _,f in ipairs(files) do                                     -- for every file we got, load it..
          print(f.name)
          local code = check(env.__TAG,load(f.content,f.fname,"t",env)) -- Load our QA code, check syntax errors
          check(env.__TAG,pcall(code))                                  -- Run the QA code, check runtime errors
        end
      end)
    procs[k]=QADir[dev.id] coroutine.resume(k) procs[k]=nil
    print(fmt("Starting QA:%s - ID:%s",dev.name,dev.id))
    runProc(QADir[dev.id],function() env.QuickApp:__init(dev) end)  -- Start QA by "creating instance"
  end

  local function run(QAs) 
    for _,qa in ipairs(QAs[1] and QAs or {QAs}) do installQA(qa) end -- Create QAs given
    -- Timer loop - core of emulator, run each coroutine until none left or all locked
    while(true) do                     -- Loop and execute tasks when their time is up
      local i,time,co = peek()         -- Look at first enabled/unlocked task in queue
      if time == nil then break end
      local now = clock()
      if time <= now then             -- Times up?
        deqeue(i)                     -- Remove task from queue
        xpresume(co)                  -- ...and run it, xpresume handles errors
        procs[co]=nil                 -- ...clear co->QA map
      else                            
        socket.sleep(time-now)        -- "sleep" until next timer in line is up
      end                             -- ...because nothing else is running, no timer could enter before in queue.
    end                                   
    if #tasks > 0 then print("All threads locked - terminating") 
    else print("No threads left - terminating") end
    QADir = {}                         -- Clear directory of QAs
  end
  return run
end -- emulator


module.json()
module.builtin()
module.fibaro()
module.files()
local run = module.emulator()
print(fmt("Tiny QuickAppEmulator (TQAE) v%s",version))

if embedded then                -- Embedded call...
  local file = debug.getinfo(2)    -- Find out what file that called us
  if file and file.source then
    if not file.source:sub(1,1)=='@' then error("Can't locate file:"..file.source) end
    run({file=file.source:sub(2)}) -- Run that file
    os.exit()
  end
else main(run) end
