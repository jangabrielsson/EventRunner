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

local function parseOptions(str)
  local res = {}
  str:gsub("([^&]-)=([^&]+)",function(k,v) res[k]=tonumber(v) or (v=='true' and true) or (v=='false' and false) or FB.urldecode(v) end)
  return res
end

local _fcont={['true']=true,['false']=false}
local function _fconv(s) return _fcont[s]==nil and s or _fcont[s] end
local function member(e,l) for i=1,#l do if e==l[i] then return i end end end
local fFuns = {
  interface=function(v,rsrc) return member(v,rsrc.interfaces or {}) end,
  property=function(v,rsrc) return rsrc.properties[v:match("%[(.-),")]==_fconv(v:match(",(.*)%]")) end
}

local function filter(list,props)
  if next(props)==nil then return list end
  local res = {}
  for _,rsrc in ipairs(list) do
    local flag = false
    for k,v in pairs(props) do
      if fFuns[k] then flag = fFuns[k](v,rsrc) else flag = rsrc[k]==v end
      if not flag then break end 
    end
    if flag then res[#res+1]=rsrc end
  end
  return res
end

local aHC3call
local apiIntercepts = { -- Intercept some api calls to the api to include emulated QAs, could be deeper a tree...
  ["GET"] = {
    ["/devices$"] = function(_,_,_) return __fibaro_get_devices() end,
    ["/devices%?(.*)"] = function(_,_,_,opts)
      local ds = __fibaro_get_devices() 
      opts = parseOptions(opts)
      return filter(ds,opts)
    end,
--   api.get("/devices?parentId="..self.id) or {}
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
    ["/plugins/createChildDevice"] = function(method,path,props)
      if EM.locl then
        local d = EM.createDevice(nil,props.name,props.type,props.initialProperties,props.initialInterfaces)
        d.parentId = props.parentId
        return d,200
      else return HC3Request(method,path,props) end
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
  },
  ["DELETE"] = { 
    ["/plugins/removeChildDevice/(%d+)"] = function(method,path,data,id)
      id = tonumber(id)
      if Devices[id] then
        Devices[id]=nil
        return true,200
      else return HC3Request(method,path,data) end
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