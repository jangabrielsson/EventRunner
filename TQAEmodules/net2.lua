local EM,FB=...

local httpRequest = EM.httpRequest
local net = {}

local httpMeta = { __tostring = function(http) return "HTTPClient object: "..http._str end }
function net.HTTPClient(i_options)   
  local self2 = {}                   
  function self2.request(_,url,args)
    local args2 = args.options or {}
    args2.url=url
    local res,status,headers = httpRequest(args2,i_options)
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

FB.net = net