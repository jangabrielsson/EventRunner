local EM,FB=...

local httpRequest,HC3Request,LOG,Devices,QAs = EM.httpRequest,EM.HC3Request,EM.LOG,EM.Devices,EM.QAs
local __fibaro_get_devices,__fibaro_get_device,__fibaro_get_device_property,__fibaro_call=
FB.__fibaro_get_devices,FB.__fibaro_get_device,FB.__fibaro_get_device_property,FB.__fibaro_call

local net, api = {},{}

local httpMeta = { __tostring = function(http) return "HTTPClient object: "..http._str end }
function net.HTTPClient(i_options)   
  local self = {}                   
  function self:request(url,args)
    args.url=url
    local res,status,headers = httpRequest(args,i_options)
    args.url=nil
    if tonumber(status) and status < 205 and args.success then 
      FB.setTimeout(function() args.success({status=status,headers=headers,data=res}) end,math.random(0,2))
    elseif args.error then FB.setTimeout(function() args.error(status) end,math.random(0,2)) end
  end
  self._str = tostring(self):match("%s(.*)")
  setmetatable(self,httpMeta)
  return self
end

local aHC3call
local apiIntercepts = { -- Intercept some api calls to the api to include emulated QAs, could be deeper a tree...
  ["GET"] = {
    ["/devices$"] = function(_,_,_) return __fibaro_get_devices() end,
    ["/devices/(%d+)$"] = function(_,_,_,id) return __fibaro_get_device(tonumber(id)) end,
    ["/devices/(%d+)/properties/(%w+)$"] = function(_,_,_,id,prop) return __fibaro_get_device_property(tonumber(id),prop) end,
  },
  ["POST"] = {
    ["/devices/(%d+)/action/([%w_]+)$"] = function(_,path,data,id,action)
      return __fibaro_call(tonumber(id),action,path,data)
    end,
    ["/plugins/updateProperty"] = function(method,path,data)
      if Devices[data.deviceId] then Devices[data.deviceId].properties[data.propertyName]=data.value return data.value,202
      else return HC3Request(method,path,data)
      end
    end,
    ["/plugins/restart"] = function(method,path,data)
      if Devices[data.deviceId] then
        QAs[data.deviceId]:restart()
        return true,200
      else return HC3Request(method,path,data) end
    end,
  },
  ["PUT"] = {
    ["/devices/(%d+)"] = function(method,path,data,id)
      id=tonumber(id)
      if Devices[id] then
        local dev = Devices[id]
        for k,v in pairs(data) do
          if k=='properties' then
            for m,n in pairs(v) do dev.properties[m]=n end
          else
            dev[k]=v
          end
        end
        return data,202
      end
      return HC3Request(method,path,data)
    end,
  }
}

function aHC3call(method,path,data) -- Intercepts some cmds to handle local resources
  for p,f in pairs(apiIntercepts[method] or {}) do
    local m = {path:match(p)}
    if #m>0 then local res,code = f(method,path,data,table.unpack(m)) if code~=false then return res,code end end
  end
  return HC3Request(method,path,data) -- Call without intercept
end

-- Normal user calls to api will have pass==nil and the cmd will be intercepted if needed. __fibaro_* will always pass
function api.get(cmd) return aHC3call("GET",cmd) end
function api.post(cmd,data) return aHC3call("POST",cmd,data) end
function api.put(cmd,data) return aHC3call("PUT",cmd,data) end
function api.delete(cmd) return aHC3call("DELETE",cmd) end

FB.net,FB.api = net, api