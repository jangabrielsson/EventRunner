local EM,FB = ...

local json = FB.json
local HC3Request,LOG,Devices = EM.HC3Request,EM.LOG,EM.Devices
local __fibaro_get_devices,__fibaro_get_device,__fibaro_get_device_property,__fibaro_call=
FB.__fibaro_get_devices,FB.__fibaro_get_device,FB.__fibaro_get_device_property,FB.__fibaro_call

local GUI_HANDLERS = {
  ["GET/api/callAction"] = function(_,client,ref,_,opts)
    local args = {}
    local id,action = tonumber(opts.deviceID),opts.name 
    for k,v in pairs(opts) do
      if k:sub(1,3)=='arg' then args[tonumber(k:sub(4))]=v end
    end
    local stat,err=pcall(FB.__fibaro_call,id,action,"",{args=args})
    if not stat then LOG("Bad callAction:%s",err) end
    client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
    return true
  end,
  ["GET/TQAE/method"] = function(_,client,ref,_,opts)
    local arg = opts.Args
    local stat,res = pcall(function()
        arg = json.decode("["..(arg or "").."]")
        local QA = EM.getQA(tonumber(opts.qaID))
        LOG("Web call: QA(%s):%s%s = %s",opts.qaID,opts.method,json.encode(arg),json.encode(res))
        local res = {QA[opts.method](QA,table.unpack(arg))}
      end)
    if not stat then 
      LOG("Error: Web call: QA(%s):%s%s - %s",opts.qaID,opts.method,json.encode(arg),res)
    end
    client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
    return true
  end,
  ["GET/TQAE/lua"] = function(_,client,ref,_,opts)
    local code = load(opts.code,nil,"t",{EM=EM,FB=FB})
    code()
    client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
    return true
  end,
  ["GET/TQAE/slider/#id/#name/#id"] = function(_,client,ref,_,_,id,slider,val)
    id = tonumber(id)
    local stat,err = pcall(function()
        local qa,env = EM.getQA(id)
        qa:updateView(slider,"value",tostring(val))
        if not qa.parent then
          env.onUIEvent(id,{deviceId=id,elementName=slider,eventType='onChanged',values={tonumber(val)}})
        else 
          local action = qa.uiCallbacks[slider]['onChanged']
          env.onAction(id,{deviceId=id,actionName=action,args={tonumber(val)}})
        end
      end)
    if not stat then LOG("ERROR %s",err) end
    client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
    return true
  end,   
  ["GET/TQAE/button/#id/#name"] = function(_,client,ref,_,_,id,btn)
    id = tonumber(id)
    local stat,err = pcall(function()
        local qa,env = EM.getQA(id)
        if not qa.parent then 
          env.onUIEvent(id,{deviceId=id,elementName=btn,eventType='onReleased',values={tonumber(val)}})
        else
          local action = qa.uiCallbacks[btn]['onReleased']
          env.onAction(id,{deviceId=id,actionName=action,args={}})
        end
      end)
    if not stat then LOG("ERROR %s",err) end
    client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
    return true
  end,
  ["POST/TQAE/action/#id"] = function(_,client,ref,body,_,id) 
    local _,env = EM.getQA(tonumber(id))
    local args = json.decode(body)
    env.onAction(id,args) 
    client:send("HTTP/1.1 302 Found\nLocation: "..(ref or "").."\n\n")
  end,
  ["POST/TQAE/ui/#id"] = function(_,client,ref,body,_,id) 
    local _,env = EM.getQA(tonumber(id))
    local args = json.decode(body)
    env.onUIEvent(id,args) 
    client:send("HTTP/1.1 302 Found\nLocation: "..(ref or "").."\n\n")
  end,
}

EM.EMEvents('start',function(_) EM.processPathMap(GUI_HANDLERS) end)

----------------------

local api = {}
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
local API_CALLS = { -- Intercept some api calls to the api to include emulated QAs
  ["GET/devices"] = function(_,_,_,opts)
    if next(opts)==nil then
      return __fibaro_get_devices(),200
    else
      local ds = __fibaro_get_devices() 
      return filter(ds,opts),200
    end
  end,
--   api.get("/devices?parentId="..self.id) or {}
  ["GET/devices/#id"] = function(_,_,_,_,id) return __fibaro_get_device(tonumber(id)) end,
  ["GET/devices/#ud/properties/#name"] = function(_,_,_,_,id,prop) return __fibaro_get_device_property(tonumber(id),prop) end,
  ["POST/devices/#id/action/#name"] = function(_,path,data,_,id,action) return __fibaro_call(tonumber(id),action,path,data) end,
  ["POST/plugins/updateProperty"] = function(method,path,data,_)
    local dev = Devices[data.deviceId]
    if dev then 
      dev.dev.properties[data.propertyName]=data.value 
      --return data.value,202
      if dev.info and (dev.info.proxy or dev.info.childProxy) then
        return HC3Request(method,path,data)
      else return data.value,202 end
    else
      return HC3Request(method,path,data)
    end
  end,
  ["POST/plugins/updateView"] = function(method,path,data,_)
    local dev = Devices[data.deviceId]
--    local data = {
--      deviceId = self.id,
--      componentName = componentName,
--      propertyName = propertyName,
--      newValue = newValue
--    }
--    api.post("/plugins/updateView", data)
  end,
  ["POST/plugins/restart"] = function(method,path,data,_)
    if Devices[data.deviceId] then
      Devices[data.deviceId]:restart()
      return true,200
    else return HC3Request(method,path,data) end
  end,
  ["POST/plugins/createChildDevice"] = function(method,path,props,_)
    local pdev = Devices[props.parentId]
    if props.initialProperties and next(props.initialProperties)==nil then 
      props.initialProperties = nil
    end
    if not pdev.info.proxy then
      local d = EM.createDevice(nil,props.name,props.type,props.initialProperties,props.initialInterfaces)
      d.info.childProxy,d.env = true,pdev.env
      d.dev.parentId = props.parentId
      return d.dev,200
    else 
      local dev,err = HC3Request(method,path,props)
      if dev then
        Devices[dev.id] = { info= { childProxy = true }, env=pdev.env, dev=dev}
        LOG("Created device %s",dev.id)
        EM.postEMEvent({type='deviceCreated',id=dev.id})
      end
      return dev,err
    end
  end,    
  ["POST/debugMessages"] = function(_,_,args,_)
    local str,tag,typ = args.message,args.tag,args.messageType
    FB.__fibaro_add_debug_message(tag,str,typ)
    return 200
  end,
  ["PUT/devices/#id"] = function(method,path,data,_,id)
    id=tonumber(id)
    if Devices[id] then
      local dev = Devices[id].dev
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
  ["DELETE/plugins/removeChildDevice/#id"] = function(method,path,data,_,id)
    id = tonumber(id)
    if Devices[id] then
      Devices[id]=nil
      return true,200
    else return HC3Request(method,path,data) end
  end,
}

local API_MAP={}

function aHC3call(method,path,data) -- Intercepts some cmds to handle local resources
  local fun,args,opts,path2 = EM.lookupPath(method,path,API_MAP)
  if type(fun)=='function' then
    local stat,res,code = pcall(fun,method,path2,data,opts,table.unpack(args))
    if not stat then return LOG("Bad API call:%s",res)
    elseif code~=false then return res,code end
  elseif fun~=nil then return LOG("Bad API call:%s",fun) end
  return HC3Request(method,path,data) -- Call without intercept
end

-- Normal user calls to api will have pass==nil and the cmd will be intercepted if needed. __fibaro_* will always pass
function api.get(cmd) return aHC3call("GET",cmd) end
function api.post(cmd,data) return aHC3call("POST",cmd,data) end
function api.put(cmd,data) return aHC3call("PUT",cmd,data) end
function api.delete(cmd) return aHC3call("DELETE",cmd) end

EM.EMEvents('init',function(_) 
    EM.processPathMap(API_CALLS,API_MAP)
  end)

FB.api = api