socket        = require("socket")
local http    = require("socket.http")
local ltn12   = require("ltn12")
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

apiIntercepts = { -- Intercept some api calls to the api to include emulated QAs, could be deeper a tree...
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