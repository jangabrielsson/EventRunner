local EM,FB=...

local httpRequest = EM.httpRequest
local LOG,DEBUG,encode = EM.LOG,EM.DEBUG,EM.utilities.encodeFast
local net = {}

local httpMeta = { __tostring = function(http) return "HTTPClient object: "..http._str end }
function net.HTTPClient(i_options)   
  local self2 = {}                   
  function self2.request(_,url,args)
    local args2,res,status,headers = args.options or {}
    args2.url=url
    if EM.interceptHTTP then
      res,status,headers = EM.interceptHTTP(args2,i_options)
    end
    if res == -42 then
      local ctx = EM.getContext()
      EM.systemTimer(function()
          res,status,headers = httpRequest(args2,i_options)
          args2.url=nil
          if tonumber(status) and status < 205 and args.success then 
            FB.setTimeout(function() args.success({status=status,headers=headers,data=res}) end,0,nil,ctx)
          elseif args.error then FB.setTimeout(function() args.error(status) end,0,nil,ctx) end
        end,0)
      return
    end
    args2.url=nil
    if tonumber(status) and status < 205 and args.success then 
      FB.setTimeout(function() args.success({status=status,headers=headers,data=res}) end,math.random(0,2))
    elseif args.error then FB.setTimeout(function() args.error(status) end,math.random(0,2)) end
  end
  self2._str = tostring(self2):match("%s(.*)")
  setmetatable(self2,httpMeta)
  return self2
end

function net.TCPSocket(opts2) 
  local self2 = { opts = opts2 or {} }
  self2.sock = EM.socket.tcp()
  if EM.copas then self2.sock = EM.copas.wrap(self2.sock) end
  function self2:connect(ip, port, opts) 
    for k,v in pairs(self.opts) do opts[k]=v end
    local _, err = self.sock:connect(ip,port)
    if err==nil and opts.success then opts.success()
    elseif opts.error then opts.error(err) end
  end
  function self2:read(opts) 
    local data,err = self.sock:receive() 
    if data and opts.success then opts.success(data)
    elseif data==nil and opts.error then opts.error(err) end
  end
  function self2.readUntil(_,delimiter, callbacks) end
  function self2:write(data, _) 
    local res,err = self.sock:send(data)
    if res and self.opts.success then self.opts.success(res)
    elseif res==nil and self.opts.error then self.opts.error(err) end
  end
  function self2:close() self.sock:close() end
  local pstr = "TCPSocket object: "..tostring(self2):match("%s(.*)")
  setmetatable(self2,{__tostring = function(_) return pstr end})
  return self2
end

function net.UDPSocket(opts2) 
  local self2 = { opts = opts2 or {} }
  self2.sock = EM.socket.udp()
  if self2.opts.broadcast~=nil then 
    self2.sock:setsockname(EM.IPAddress, 0)
    self2.sock:setoption("broadcast", self2.opts.broadcast) 
  end
  if self2.opts.timeout~=nil then self2.sock:settimeout(self2.opts.timeout / 1000) end

  function self2:sendTo(datagram, ip,port, callbacks)
    local stat, res = self.sock:sendto(datagram, ip, port)
    if stat and callbacks.success then 
      pcall(callbacks.success,1)
    elseif stat==nil and callbacks.error then
      pcall(callbacks.error,res)
    end
  end 
  function self2:bind(ip,port) self.sock:setsockname(ip,port) end
  function self2:receive(callbacks) 
    local stat, res = self.sock:receivefrom()
    if stat and callbacks.success then 
      pcall(callbacks.success,stat, res)
    elseif stat==nil and callbacks.error then
      pcall(callbacks.error,res)
    end
  end
  function self2:close() self.sock:close() end
  local pstr = "UDPSocket object: "..tostring(self2):match("%s(.*)")
  setmetatable(self2,{__tostring = function(_) return pstr end})
  return self2
end

-------------- WebSocket ----------------------------------
local websocket=dofile(EM.cfg.modPath.."LuWS.lua")
net._LuWS_VERSION = websocket.version

function net.WebSocketClientTls()
  local POLLINTERVAL = 1000
  local conn,err,lt = nil
  local self2 = { }
  local handlers = {}
  local function dispatch(h,...)
    if handlers[h] then
      h = handlers[h]
      local args = {...}
      FB.setTimeout(function() h(table.unpack(args)) end,0)
    end
  end
  local function listen()
    if not conn then return end
    local function loop()
      if lt == nil then return end
      websocket.wsreceive(conn)
      if lt then lt = EM.systemTimer(loop,POLLINTERVAL,"WebSocket") end
    end
    lt = EM.systemTimer(loop,0,"WebSocket")
  end
  local function stopListen() if lt then EM.clearTimeout(lt) lt = nil end end
  local function disconnected() websocket.wsclose(conn) conn=nil; stopListen(); dispatch("disconnected") end
  local function connected() self2.co = true; listen();  dispatch("connected") end
  local function dataReceived(data) dispatch("dataReceived",data) end
  local function error(err2) dispatch("error",err2) end
  local function message_handler( conn2, opcode, data, ... )
    if not opcode then
      error(data)
      disconnected()
    else
      dataReceived(data)
    end
  end
  function self2:addEventListener(h,f) handlers[h]=f end
  function self2:connect(url)
    if conn then return false end
    conn, err = websocket.wsopen( url, message_handler, nil ) --options )
    if not err then connected(); return true
    else return false,err end
  end
  function self2:send(data)
    if not conn then return false end
    if not websocket.wssend(conn,1,data) then return disconnected() end
    return true
  end
  function self2:isOpen() return conn and true end
  function self2:close() if conn then disconnected() return true end end
  local pstr = "WebSocket object: "..tostring(self2):match("%s(.*)")
  setmetatable(self2,{__tostring = function(_) return pstr end})
  return self2
end

---------------------- MQTT --------------------------
local function safeJson(e)
  if type(e)=='table' then
    for k,v in pairs(e) do e[k]=safeJson(v) end
    return e
  elseif type(e)=='function' or type(e)=='thread' or type(e)=='userdata' then return tostring(e)
  else return e end
end

local oldRequire,map = require,{}
function require(f)
  local stat,res = pcall(oldRequire,f)
  if stat then return res end
  local p=f:match("mqtt%.(%w+)")
  if p and map[p] then return map[p]
  else
    local r = loadfile(EM.cfg.modPath.."mqtt/"..p..".lua")()
    map[p]=r
    return r
  end
end
_mqtt = require("mqtt.init")
require = oldRequire
--local _mqtt=dofile(EM.cfg.modPath.."mqtt/init.lua")
local mqtt={
  interval = 1000,
  Client = {},
  QoS = {EXACTLY_ONCE=1}
}
mqtt.MSGT = {
  CONNECT = 1,
  CONNACK = 2,
  PUBLISH = 3,
  PUBACK = 4,
  PUBREC = 5,
  PUBREL = 6,
  PUBCOMP = 7,
  SUBSCRIBE = 8,
  SUBACK = 9,
  UNSUBSCRIBE = 10,
  UNSUBACK = 11,
  PINGREQ = 12,
  PINGRESP = 13,
  DISCONNECT = 14,
  AUTH = 15,
}
mqtt.MSGMAP = {
  [9]='subscribed',
  [11]='unsubscribed',
  [4]='published',  -- Should be onpublished according to doc?
  [14]='closed',
}

LOG.register("mqtt","Log MQTT related events")

function mqtt.Client.connect(uri, options)
  options = options or {}
  local args = {}
  args.uri = uri
  args.uri = string.gsub(uri, "mqtt://", "")
  args.username = options.username
  args.password = options.password
  args.clean = options.cleanSession
  if args.clean == nil then args.clean=true end
  args.will = options.lastWill
  args.keep_alive = options.keepAlivePeriod
  args.id = options.clientId

  --cafile="...", certificate="...", key="..." (default false)
  if options.clientCertificate then -- Not in place...
    args.secure = {
      certificate= options.clientCertificate,
      cafile = options.certificateAuthority,
      key = "",
    }
  end

  local _client = _mqtt.client(args)
  local client={ _client=_client, _handlers={} }
  function client:addEventListener(message,handler)
    self._handlers[message]=handler
  end
  function client:subscribe(topic, options)
    options = options or {}
    local args = {}
    args.topic = topic
    args.qos = options.qos or 0
    args.callback = options.callback
    return self._client:subscribe(args)
  end
  function client:unsubscribe(topics, options)
    if type(topics)=='string' then return self._client:unsubscribe({topic=topics})
    else
      local res
      for _,t in ipairs(topics) do res=self:unsubscribe(t) end
      return res
    end
  end
  function client:publish(topic, payload, options)
    options = options or {}
    local args = {}
    args.topic = topic
    args.payload = payload
    args.qos = options.qos or 0
    args.retain = options.retain or false
    args.callback = options.callback
    return self._client:publish(args)
  end
  function client:disconnect(options)
    options = options or {}
    local args = {}
    args.callback = options.callback
    return self._client:disconnect(args)
  end
  --function client:acknowledge() end

  _client:on{
    --{"type":2,"sp":false,"rc":0}
    connect = function(connack)
      DEBUG("mqtt","trace","MQTT connect:"..encode(connack))
      if client._handlers['connected'] then
        client._handlers['connected']({sessionPresent=connack.sp,returnCode=connack.rc})
      end
    end,
    subscribe = function(event)
      DEBUG("mqtt","trace","MQTT subscribe:"..encode(event))
      if client._handlers['subscribed'] then client._handlers['subscribed'](safeJson(event)) end
    end,
    unsubscribe = function(event)
      DEBUG("mqtt","trace","MQTT unsubscribe:"..encode(event))
      if client._handlers['unsubscribed'] then client._handlers['unsubscribed'](safeJson(event)) end
    end,
    message = function(msg)
      DEBUG("mqtt","trace","MQTT message:"..encode(msg))
      local msgt = mqtt.MSGMAP[msg.type]
      if msgt and client._handlers[msgt] then client._handlers[msgt](msg)
      elseif client._handlers['message'] then client._handlers['message'](msg) end
    end,
    acknowledge = function(event)
      DEBUG("mqtt","trace","MQTT acknowledge:"..encode(event))
      if client._handlers['acknowledge'] then client._handlers['acknowledge']() end
    end,
    error = function(err)
      DEBUG("mqtt","error","MQTT error:"..err)
      if client._handlers['error'] then client._handlers['error'](err) end
    end,
    close = function(event)
      DEBUG("mqtt","trace","MQTT close:"..encode(event))
      event = safeJson(event)
      if client._handlers['closed'] then client._handlers['closed'](safeJson(event)) end
    end,
    auth = function(event)
      DEBUG("mqtt","trace","MQTT auth:"..encode(event))
      if client._handlers['auth'] then client._handlers['auth'](safeJson(event)) end
    end,
  }

  _mqtt.get_ioloop():add(client._client)
  if not mqtt._loop then
    local iter = _mqtt.get_ioloop()
    local function loop()
      iter:iteration()
      EM.systemTimer(loop,mqtt.interval,"MQTT")
    end
    mqtt._loop = EM.systemTimer(loop,mqtt.interval,"MQTT")
  end

  local pstr = "MQTT object: "..tostring(client):match("%s(.*)")
  setmetatable(client,{__tostring = function(_) return pstr end})

  return client
end

net.WebSocketClient = net.WebSocketClientTls
FB.net = net
FB.mqtt = mqtt