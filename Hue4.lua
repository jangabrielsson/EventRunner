-------- Start EventScript4 ------------------
INSTALLED_MODULES['Hue4.lua']={isInstalled=true,installedVersion=0.1}

function createHueSupport()
  local self = {}
  local _setTimeout = fibaro._setTimeout

  --------------------------- Hue state changes -------------------------
  local HueData = { lights = {}, sensors = {}, groups = {}, scenes={} }
  local LIGHTPROPS = {on=true,reachable=true,bri=true}
  local SENSORPROPS = {temperature=true,buttonevent=true,presence=true,lightlevel=true,dark=true,daylight=true}
  local INTERVAL = 1000 -- Interval to poll Hue hub

  local HUEMAP = {}      -- Map from hueKey to deviceInfo
  local DEVICEMAP = nil  -- hueKey -> deviceID for installed devices
  local HUELIST = {}           -- List of all Hue devices

  local CHANGEMAP = {
    ["ZLLSwitch"] = function(ns,os) 
      if ns.lastupdated ~= os.lastupdated  or ns.buttonevent ~= os.buttonevent then
        os.buttonevent,os.lastupdated = ns.buttonevent,ns.lastupdated
        return {type='button',value=ns.buttonevent} 
      end
    end,
    ["ZLLTemperature"] = function(ns,os) 
      if ns.lastupdated ~= os.lastupdated  or ns.temperature ~= os.temperature then
        os.temperature,os.lastupdated = ns.temperature,ns.lastupdated
        return {type='temperature',value=ns.temperature} 
      end
    end,
    ["ZLLPresence"] = function(ns,os)
      if ns.lastupdated ~= os.lastupdated  or ns.presence ~= os.presence then
        os.presence,os.lastupdated = ns.presence,ns.lastupdated
        return {type='presence',value=ns.presence} 
      end
    end,
    ["ZLLLightLevel"] = function(ns,os)
      if ns.dark ~= os.dark or ns.daylight ~= os.daylight or ns.lightlevel ~= os.lightlevel then
        os.lightlevel,os.dark,os.daylight = ns.lightlevel,ns.dark,ns.daylight
        return {type='lightlevel', dark=ns.dark, daylight=os.daylight, value=os.lightlevel}
      end
    end,
    ["Extended color light"] = function(ns,os)
      if ns.on ~= os.on or ns.bri ~= os.bri or ns.reachable ~= os.reachable then
        os.on,os.bri,os.reachable = ns.on,ns.bri,ns.reachable
        return {type='lightChange', on = os.on and os.reachable, value = os.bri} 
      end
    end
  }

  local TYPM2STR = {lights="Light",sensors="Sensor",groups="Group"}
  function dev2str(d)
    return string.format("%s hueID:%s, name:'%s' type:'%s'%s",TYPM2STR[d.type],d.hueID,d.d.name,d.d.type,
      DEVICEMAP and DEVICEMAP[d.key] and " deviceID:"..DEVICEMAP[d.key] or "")
  end

  local function mkKey(hub,tp,id) return hub..tp..id end

  local function buildDeviceList(list,hub)  -- Builds HUEMAP and HUELIST
    HUELIST,HUEMAP = {},{}
    for k,v in pairs(list.lights or {}) do
      if CHANGEMAP[v.type] then HUEMAP[mkKey(hub,'light',k)]={hueID=k, type='lights',d=v} end
    end
    for k,v in pairs(list.sensors or {}) do
      if CHANGEMAP[v.type] then HUEMAP[mkKey(hub,'sensor',k)]={hueID=k, type='sensors',d=v} end
    end
    for k,v in pairs(list.groups or {}) do
      if CHANGEMAP[v.type] then HUEMAP[mkKey(hub,'group',k)]={hueID=k, type='groups',d=v} end
    end
    for k,v in pairs(HUEMAP) do v.key = k; v.__tostring=dev2str; HUELIST[#HUELIST+1]=v end
  end

--------------------------- Main Event loop -------------------------
  local main,post,_HTTP

  local function createHueReq(user,ip)
    local baseURL="http://"..ip..":80/api/"..user.."/"
    return function(url,op,payload,success,error)
      _HTTP ,op,payload = _HTTP or Util.netSync.HTTPClient(), op or "GET", payload and json.encode(payload) or ""
      _HTTP:request(baseURL..url,{
          options = {headers={['Accept']='application/json',['Content-Type']='application/json'},
            data = payload, timeout=_HUETIMEOUT or 5000, method = op},
          error = function(status) if error then error.value = status post(error) end end,
          success = function(status) if success then success.value = status post(success) end end,
        })
    end
  end

  local EVENTS = {
    ['start'] = function(e) -- {type='start', user=<user>, ip=<ip>}
      local ip,user,hub,cont = e.ip,e.user,e.hub,e.cont
      HueRequest = createHueReq(user,ip)
      HueRequest("",'GET',nil,{type='init',hub=hub, cont=cont, ip=ip},{type='startErr',hub=hub, cont=cont, ip=ip}) 
    end,

    ['init'] = function(e)
      local data = json.decode(e.value.data)
      buildDeviceList(data,e.hub)
      post({type='poll',hub=e.hub},INTERVAL)
      --print(json.encode(e))
      if e.cont then 
        Log(LOG.SYS,"Hue connected to %s",e.ip)
        e.cont() 
      end
    end,

    ['poll'] = function(e)
      HueRequest("",nil,nil,{type='checkChanges',hub=e.hub},{type='errPoll',hub=e.hub})
    end,

    ['checkChanges'] = function(e)
      local data = json.decode(e.value.data)
      local hub = e.hub
      for k,v in pairs(data.lights) do
        local key = mkKey(hub,'light',k)
        local ol = HUEMAP[key]
        if not ol and CHANGEMAP[v.type] then 
          HUEMAP[key]={hueID=k,type='lights',key='light'..k, d=v}
        else
          local change = CHANGEMAP[v.type] and CHANGEMAP[v.type](v.state,ol.d.state)
          if change then change.hub,change.hueID,change.key = e.hub,k,key; post(change) end
        end
      end
      for k,v in pairs(data.sensors) do
        if v.state then 
          local key = mkKey(hub,'sensor',k)
          local os = HUEMAP[key]
          if not os  and CHANGEMAP[v.type] then 
            HUEMAP[key]={hueID=k,type='sensors',key='sensor'..k, d=v}
          else
            local change = CHANGEMAP[v.type] and CHANGEMAP[v.type](v.state,os.d.state)
            if change then change.hub,change.hueID,change.key = e.hub,k,key; post(change) end
          end
        end
      end
      post({type='poll',hub=e.hub},INTERVAL)
    end,

    ['lightChange'] = function(e)
      --Debug(true,"Light[%s]=%s, value:%s",e.hueID,e.on,e.value)
      if DEVICEMAP[e.key] then
        local deviceID,value=DEVICEMAP[e.key],e.on and math.floor((e.value/254*99+0.5)) or 0
        fibaro._cacheDeviceProp(deviceID,"value",value)
        Event.post({type='property',deviceID=deviceID, propertyName='value',value=value}) 
      end
    end,

    ['button'] = function(e)
      --Debug(true,"Button[%s]=%s",e.hueID,e.value)
      if DEVICEMAP[e.key] then 
        local deviceID,value=DEVICEMAP[e.key],e.value
        fibaro._cacheDeviceProp(deviceID,"value",value)
        Event.post({type='property',deviceID=deviceID, propertyName='value',value=value})  
      end
    end,
    ['presence'] = function(e)
      --Debug(true,"Presence[%s]=%s",e.hueID,e.value)
      if DEVICEMAP[e.key] then 
        local deviceID,value=DEVICEMAP[e.key],e.value
        fibaro._cacheDeviceProp(deviceID,"value",value)
        Event.post({type='property',deviceID=deviceID, propertyName='value',value=value and 1 or 0}) 
      end
    end,
    ['temperature'] = function(e)
      --Debug(true,"Temperature[%s]=%s",e.hueID,e.value)
      if DEVICEMAP[e.key] then 
        local deviceID,value=DEVICEMAP[e.key],e.value/100
        fibaro._cacheDeviceProp(deviceID,"value",value)
        Event.post({type='property',deviceID=deviceID, propertyName='value',value=value}) 
      end
    end,
    ['lightlevel'] = function(e) --TODO: Lightlevel needs to be adjustes
      --Debug(true,"Lightsensor[%s]=%s (dark:%s,daylight:%s)",e.hueID,e.value,e.dark,e.daylight)
      if DEVICEMAP[e.key] then 
        local deviceID,value=DEVICEMAP[e.key],e.value
        fibaro._cacheDeviceProp(deviceID,"value",value)
        Event.post({type='property',deviceID=deviceID, propertyName='value',value=value}) 
      end
    end,

    ['errPoll'] = function(e)
      Log(LOG.ERROR,"Error:"..json.encode(e))
      post({type='poll',hub=e.hub},3*INTERVAL)
    end,

    ['startErr'] = function(e)
      Log(LOG.ERROR,"Error connecting to Hue at %s (%s)",e.ip,e.value)
      e.cont()
    end,
  }

  function main(ev) if EVENTS[ev.type] then EVENTS[ev.type](ev) end end
  function post(ev,t) _setTimeout(function() main(ev) end,t or 0) end

  function self.connect(name,ip,hub,cont)
    if not(name and ip) then 
      Log(LOG.ERROR,"Missing Hue credentials") 
      cont()
    else
      hub = hub or "Hue"
      post({type='start', user=name, ip = ip, hub=hub, cont=cont})
    end
  end

  function self.dump() for _,d in ipairs(HUELIST) do Debug(true,tostring(d)) end end

  function self.define(name,deviceID,hub)
    hub = hub or "Hue"
    for k,v in pairs(HUEMAP) do
      if k:match(hub) and v.d.name == name then
        DEVICEMAP = DEVICEMAP or {}
        DEVICEMAP[k]=deviceID
        Util.defineVirtualDevice(deviceID,nil,
          function(id,prop,...)
            local val = fibaro._EventCache.devices[prop..id]
            if val then
              return true,{val.value,val.modified}
            else return false end 
          end)
        return
      end
    end
    error("Missing Hue name "..name)
  end

  Log(LOG.SYS,"Setting up Hue support..")
  return self
end
-------- End EventScript4 ------------------