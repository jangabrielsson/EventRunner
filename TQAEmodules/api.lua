--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Module REST api calls. Both for local emulator calls and external REST calls from the HC3. Uses the Webserver module

--]]
local EM,FB = ...

local json = FB.json
local HC3Request,LOG,DEBUG,Devices = EM.HC3Request,EM.LOG,EM.DEBUG,EM.Devices
local __fibaro_call,__assert_type=FB.__fibaro_call,FB.__assert_type
local copy = EM.utilities.copy

LOG.register("api","Log api.* related events")

local GUI_HANDLERS = {
  ["GET/api/callAction"] = function(_,client,ref,_,opts)
    local args = {}
    local id,action = tonumber(opts.deviceID),opts.name 
    for k,v in pairs(opts) do
      if k:sub(1,3)=='arg' then args[tonumber(k:sub(4))]=v end
    end
    local stat,err=pcall(FB.__fibaro_call,id,action,"",{args=args})
    if not stat then LOG.error("Bad callAction:%s",err) end
    client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
    return true
  end,
  ["GET/TQAE/method"] = function(_,client,ref,_,opts)
    local arg = opts.Args
    local stat,res = pcall(function()
        arg = json.decode("["..(arg or "").."]")
        --local QA = EM.getQA(tonumber(opts.qaID))
        __fibaro_call(tonumber(opts.qaID),opts.method,"",{args=arg})
        local res={}
        --local res = {QA[opts.method](QA,table.unpack(arg))}
        DEBUG("api","sys","Web call: QA(%s):%s%s = %s",opts.qaID,opts.method,json.encode(arg),json.encode(res))
      end)
    if not stat then 
      LOG.error("Web call: QA(%s):%s%s - %s",opts.qaID,opts.method,json.encode(arg),res)
    end
    client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
    return true
  end,
  ["GET/TQAE/setglobal"] = function(_,client,ref,_,opts)
    local name,value = opts.name,opts.value
    FB.fibaro.setGlobalValue(name,tostring(value))
    client:send("HTTP/1.1 302 Found\nLocation: "..(ref or "").."\n\n")
    return true
  end,
  ["GET/TQAE/debugSwitch"] = function(_,client,ref,_,opts)
    EM.debugFlags[opts.name] = not EM.debugFlags[opts.name]
    LOG.sys("debugFlags.%s=%s",opts.name,tostring(EM.debugFlags[opts.name]))
    client:send("HTTP/1.1 302 Found\nLocation: "..(ref or "").."\n\n")
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
    if not stat then LOG.error("%s",err) end
    client:send("HTTP/1.1 302 Found\nLocation: "..ref.."\n\n")
    return true
  end,   
  ["GET/TQAE/button/#id/#name"] = function(_,client,ref,_,_,id,btn)
    id = tonumber(id)
    local stat,err = pcall(function()
        local qa,env = EM.getQA(id)
        if not qa.parent then 
          env.onUIEvent(id,{deviceId=id,elementName=btn,eventType='onReleased',values={}})
        else
          local action = qa.uiCallbacks[btn]['onReleased']
          env.onAction(id,{deviceId=id,actionName=action,args={}})
        end
      end)
    if not stat then LOG.error("%s",err) end
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
local API_CALLS = { -- Intercept some api calls to the api to include emulated QAs or emulator aspects
  ["GET/devices"] = function(_,_,_,opts)
    local ds = HC3Request("GET","/devices") or {}
    for _,dev in pairs(Devices) do ds[#ds+1]=dev.dev end -- Add emulated Devices
    if next(opts)==nil then
      return ds,200
    else
      return filter(ds,opts),200
    end
  end,
--   api.get("/devices?parentId="..self.id) or {}
  ["GET/devices/#id"] = function(_,path,_,_,id)
    return Devices[id] and Devices[id].dev or HC3Request("GET",path)
  end,
  ["GET/devices/#id/properties/#name"] = function(_,path,_,_,id,prop) 
    local D = Devices[id]  -- Is it a local Device?
    if D then return D.dev.properties[prop] and { value = D.dev.properties[prop], modified=0},200 or nil
    else return HC3Request("GET",path) end
  end,
  ["POST/devices/#id/action/#name"] = function(_,path,data,_,id,action) 
    return __fibaro_call(tonumber(id),action,path,data) 
  end,
  ["PUT/devices/#id"] = function(_,path,data,id)
    if Devices[id] then
      if data.properties then
        for k,v in pairs(data.properties) do
          FB.put("plugins/updateProperty",{deviceId=id,propertyName=k,value=v})
        end
      end
      return data,202
      -- Should check other device values too - usually needs restart of QA
    else return HC3Request("GET",path, data) end
  end,

  ["GET/globalVariables"] = function(_,path,_,_)
    local globs = EM.cfg.offline and {} or HC3Request("GET",path)
    for _,v in pairs(EM.rsrc.globalVariables) do globs[#globs+1]=v end
    return globs,200
  end,
  ["GET/globalVariables/#name"] = function(_,path,_,_,name)
    return EM.rsrc.globalVariables[name] or HC3Request("GET",path)
  end,
  ["POST/globalVariables"] = function(_,path,data,_)
    if EM.cfg.offline then
      if EM.rsrc.globalVariables[data.name] then return nil,404
      else return EM.create.globalVariable(data),200 end
    else return HC3Request("POST",path,data) end
  end,
  ["PUT/globalVariables/#name"] = function(_,path,data,_,name)
    local v = EM.rsrc.globalVariables[name]
    if v then  
      EM.addRefreshEvent({
          type='GlobalVariableChangedEvent',
          created = EM.osTime(),
          data={variableName=name, newValue=data.value, oldValue=v.value}
        })
      v.value = data.value
      v.modified = EM.osTime()
      return v,200
    else return HC3Request("PUT",path,data) end
  end,
  ["DELETE/globalVariables/#name"] = function(_,path,data,_,name)
    if EM.rsrc.globalVariables[name] then
      EM.rsrc.globalVariables[name] = nil
      return nil,200
    else return HC3Request("DELETE",path,data) end
  end,

  ["GET/rooms"] = function(_,path,_,_)
    local rooms = EM.cfg.offline and {} or HC3Request("GET",path)
    for _,v in pairs(EM.rsrc.rooms) do rooms[#rooms+1]=v end
    return rooms,200
  end,
  ["GET/rooms/#id"] = function(_,path,_,_,id)
    return EM.rsrc.rooms[id] or HC3Request("GET",path)
  end,
  ["POST/rooms"] = function(_,path,data,_)
    if EM.cfg.offline then
      return EM.create.room(data),200
    else return HC3Request("POST",path,data) end
  end,
  ["POST/rooms/#id/action/setAsDefault"] = function(_,path,data,_,id)
    EM.cfg.defaultRoom = id
    if EM.cfg.offline then return id,200 else return HC3Request("POST",path,data) end
  end,
  ["PUT/rooms/#id"] = function(_,path,data,_,id)
    local r = EM.rsrc.rooms[id]
    if r then
      for k,v in pairs(data) do r[k]=v end
      return r,200
    else return HC3Request("PUT",path,data) end
  end,
  ["DELETE/rooms/#id"] = function(_,path,data,_,id)
    if EM.rsrc.rooms[id] then
      EM.rsrc.rooms[id] = nil
      return nil,200
    else return HC3Request("DELETE",path,data) end
  end,

  ["GET/sections"] = function(_,path,_,_)
    local sections = EM.cfg.offline and {} or HC3Request("GET",path)
    for _,v in pairs(EM.rsrc.sections) do sections[#sections+1]=v end
    return sections,200
  end,
  ["GET/sections/#id"] = function(_,path,_,_,id)
    return EM.rsrc.sections[id] or HC3Request("GET",path)
  end,
  ["POST/sections"] = function(_,path,data,_)
    if EM.cfg.offline then
      return EM.create.section(data),200
    else return HC3Request("POST",path,data) end
  end,
  ["PUT/sections/#id"] = function(_,path,data,_,id)
    local s = EM.rsrc.sections[id]
    if s then
      for k,v in pairs(data) do s[k]=v end
      return s,200
    else return HC3Request("PUT",path,data) end
  end,
  ["DELETE/sections/#id"] = function(_,path,data,_,id)
    if EM.rsrc.sections[id] then
      EM.rsrc.sections[id] = nil
      return nil,200
    else return HC3Request("DELETE",path,data) end
  end,

  ["GET/customEvents"] = function(_,path,_,_)
    local cevents = EM.cfg.offline and {} or HC3Request("GET",path)
    for _,v in pairs(EM.rsrc.customeEvents) do cevents[#cevents+1]=v end
    return cevents,200
  end,
  ["GET/customEvents/#name"] = function(_,path,_,name)
    return EM.rsrc.customEvents[name] or HC3Request("GET",path)
  end,
  ["POST/customEvents"] = function(_,path,data,_)
    if EM.cfg.offline then
      if EM.rsrc.customEvents[data.name] then return nil,404
      else return EM.create.customEvent(data),200 end
    else return HC3Request("POST",path,data) end
  end,
  ["POST/customEvents/#name"] = function(_,path,data,_,name)
    if EM.rsrc.customEvents[name] then
      EM.addRefreshEvent({
          type='CustomEvent',
          created = EM.osTime(),
          data={name=name, value=EM.rsrc.customEvents[name].userDescription}
        })
    else return HC3Request("POST",path,data) end
  end,
  ["PUT/customEvents/#name"] = function(_,path,data,name)
    local ce = EM.rsrc.rooms[name]
    if ce then
      for k,v in pairs(data) do ce[k]=v end
      return ce,200
    else return HC3Request("PUT",path,data) end
  end,
  ["DELETE/customEvents/#name"] = function(_,path,data,name)
    if EM.rsrc.customEvents[name] then
      EM.rsrc.customEvents[name] = nil
      return nil,200
    else return HC3Request("DELETE",path,data) end
  end,

  ["GET/scenes"] = function(_,path,_,_)
    return HC3Request("GET",path)
  end,
  ["GET/scenes/#id"] = function(_,path,_,_)
    return HC3Request("GET",path)
  end,

  ["POST/plugins/updateProperty"] = function(method,path,data,_)
    local D = Devices[data.deviceId]
    if D then
      local oldVal = D.dev.properties[data.propertyName]
      D.dev.properties[data.propertyName]=data.value 
      EM.addRefreshEvent({
          type='DevicePropertyUpdatedEvent',
          created = EM.osTime(),
          data={id=data.deviceId, property=data.propertyName, newValue=data.value, oldValue=oldVal}
        })
      if D.proxy or D.childProxy then
        return HC3Request(method,path,data)
      else return data.value,202 end
    else
      return HC3Request(method,path,data)
    end
  end,
  ["POST/plugins/updateView"] = function(method,path,data)
    local D = Devices[data.deviceId]
    if D and (D.proxy or D.childProxy) then
      HC3Request(method,path,data)
    end
  end,
  ["POST/plugins/restart"] = function(method,path,data,_)
    if Devices[data.deviceId] then
      EM.restartQA(Devices[data.deviceId])
      return true,200
    else return HC3Request(method,path,data) end
  end,
  ["POST/plugins/createChildDevice"] = function(method,path,props,_)
    local D = Devices[props.parentId]
    if props.initialProperties and next(props.initialProperties)==nil then 
      props.initialProperties = nil
    end
    if not D.proxy then
      local info = {
        parentId=props.parentId,name=props.name,
        type=props.type,properties=props.initialProperties,
        interfaces=props.initialInterfaces
      }
      local dev = EM.createDevice(info)
      Devices[dev.id]=info
      DEBUG("child","sys","Created local child device %s",dev.id)
      dev.parentId = props.parentId
      return dev,200
    else 
      local dev,err = HC3Request(method,path,props)
      if dev then
        DEBUG("child","sys","Created child device %s on HC3",dev.id)
      end
      return dev,err
    end
  end,    
  ["POST/debugMessages"] = function(_,_,args,_)
    local str,tag,typ = args.message,args.tag,args.messageType
    FB.__fibaro_add_debug_message(tag,str,typ)
    return 200
  end,
  ["DELETE/plugins/removeChildDevice/#id"] = function(method,path,data,_,id)
    local D = Devices[id]
    if D then
      Devices[id]=nil
      Devices[D.dev.parentId]:restart()
      return true,200
    else return HC3Request(method,path,data) end
  end,
  ------------- quickApp ---------
  ["GET/quickApp/#id/files"] = function(method,path,data,_,id)                     --Get files
    local D = Devices[id]
    if D then
      local f,files = D.fileMap or {},{}
      for _,v in pairs(f) do v = copy(v); v.content = nil; files[#files+1]=v end
      return files,200
    else return HC3Request(method,path,data) end
  end,
  ["GET/quickApp/#id/files/#name"] = function(method,path,data,_,id,name)         --Get specific file
    local D = Devices[id]
    if D then
      if (D.fileMap or {})[name] then return D.fileMap[name],200
      else return nil,404 end
    else return HC3Request(method,path,data) end
  end,
  ["PUT/quickApp/#id/files/#name"] = function(method,path,data,_,id,name)         --Update specific file
    local D = Devices[id]
    if D then
      if (D.fileMap or {})[name] then
        local args = type(data)=='string' and json.decode(data) or data
        D.fileMap[name] = args
        D:restartQA()
        return D.fileMap[name],200
      else return nil,404 end
    else return HC3Request(method,path,data) end
  end,
  ["PUT/quickApp/#id/files"]  = function(method,path,data,_,id)                  --Update files
    local D = Devices[id]   
    if D then
      local args = type(data)=='string' and json.decode(data) or data
      for _,f in ipairs(args) do
        if D.fileMap[f.name] then D.fileMap[f.name]=f end
      end
      D:restartQA()
      return true,200
    else return HC3Request(method,path,data) end
  end,
  ["GET/quickApp/export/#id"] = function(method,path,data,_,id)                --Export QA to fqa
    local D = Devices[id]
    if D then
      --return QA.toFQA(id,nil),200
    else return HC3Request(method,path,data) end
  end,
  ["POST/quickApp/"] = function(method,path,data)                              --Install QA
    local lcl = FB.__fibaro_local(false)
    local res,err = HC3Request(method,path,data)
    FB.__fibaro_local(lcl)
    return res,err
  end,
  ["DELETE/quickApp/#id/files/#name"]  = function(method,path,data,_,id,name)    -- Delete file
    local D = Devices[id]
    if D then
      if D.fileMap[name] then
        D.fileMap[name]=nil
        D:restartQA()
        return true,200
      else return nil,404 end
    else return HC3Request(method,path,data) end
  end,
}

local API_MAP={ GET={}, POST={}, PUT={}, DELETE={} }

function aHC3call(method,path,data, remote) -- Intercepts some cmds to handle local resources
  if remote == 'remote' then return HC3Request(method,path,data) end
  local fun,args,opts,path2 = EM.lookupPath(method,path,API_MAP)
  if type(fun)=='function' then
    local stat,res,code = pcall(fun,method,path2,data,opts,table.unpack(args))
    if not stat then return LOG.error("Bad API call:%s",res)
    elseif code~=false then return res,code end
  elseif fun~=nil then return LOG.error("Bad API call:%s",fun) end
  return HC3Request(method,path,data) -- No intercept, send request to HC3
end

-- Normal user calls to api will have pass==nil and the cmd will be intercepted if needed. __fibaro_* will always pass
function api.get(cmd, remote) return aHC3call("GET",cmd, remote) end
function api.post(cmd,data, remote) return aHC3call("POST",cmd,data, remote) end
function api.put(cmd,data, remote) return aHC3call("PUT",cmd,data, remote) end
function api.delete(cmd, remote) return aHC3call("DELETE",cmd, remote) end

function EM.addAPI(p,f) EM.addPath(p,f,API_MAP) end

EM.EMEvents('start',function(_) 
    EM.processPathMap(API_CALLS,API_MAP)

    local f1 = EM.lookupPath("GET","/devices/0",API_MAP)
    function FB.__fibaro_get_device(id) __assert_type(id,"number") return f1("GET","/devices/"..id,nil,{},id) end

    local f2 = EM.lookupPath("GET","/devices",API_MAP)
    function FB.__fibaro_get_devices() return f2("GET","/devices",nil,{}) end

    local f3 = EM.lookupPath("GET","/rooms/0",API_MAP)
    function FB.__fibaro_get_room(id) __assert_type(id,"number") return f3("GET","/rooms/"..id,nil,{},id) end

    local f4 = EM.lookupPath("GET","/scenes/0",API_MAP)
    function FB.__fibaro_get_scene(id) __assert_type(id,"number") return f4("GET","/scenes/"..id,nil,{},id) end

    local f5 = EM.lookupPath("GET","/globalVariables/x",API_MAP)
    function FB.__fibaro_get_global_variable(name) 
      __assert_type(name,"string") return f5("GET","/globalVariables/"..name,nil,{},name) 
    end

    local f6 = EM.lookupPath("GET","/devices/0/properties/x",API_MAP)
    function FB.__fibaro_get_device_property(id,prop) 
      __assert_type(id,"number") __assert_type(prop,"string")
      return f6("GET","/devices/"..id.."/properties/"..prop,nil,{},id,prop) 
    end

  end)

FB.api = api