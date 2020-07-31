if dofile and not hc3_emulator then
  hc3_emulator = {
    name = "Shelly",    -- Name of QA
    poll = 2000,        -- Poll HC3 for triggers every 2000ms
    type = "com.fibaro.deviceController",
    --proxy = true,
    deploy=true,
    quickVars = {
      dev1="L1:0:admin:admin:192.168.1.141",
      dev2="L2:0:admin:admin:192.168.1.141",
      dev3="D1:0:admin:admin:fakeDim1",
      dev4="R1:0:admin:admin:fakeRGB1",
    },
    UI={
      {{button="on", text="On", onReleased="turnOn"},{button="off", text="Off", onReleased="turnOff"}},
      {button="remove", text="Regenerate children", onReleased="remove"}
      }  
  }
  dofile("fibaroapiHC3.lua")
end

hc3_emulator.FILE("Toolbox/Toolbox_basic.lua","Toolbox")
hc3_emulator.FILE("Toolbox/Toolbox_events.lua","Toolbox_events")
hc3_emulator.FILE("Toolbox/Toolbox_child.lua","Toolbox_child")

local deviceMap = {
  ['shellyplug']           = {className="SingleSwitch",fibaroType="com.fibaro.binarySwitch"},
  ['shellyplugs']          = {className="SingleSwitch",fibaroType="com.fibaro.binarySwitch"},
  ['shelly1:relay']        = {className="SingleSwitch",fibaroType="com.fibaro.binarySwitch"},
  ['shelly1pm:relay']      = {className="SingleSwitch",fibaroType="com.fibaro.binarySwitch"},
  ['shellyswitch25:relay'] = {className="SingleSwitch",fibaroType="com.fibaro.binarySwitch"},
  ['shellyswitch2:relay']  = {className="SingleSwitch",fibaroType="com.fibaro.binarySwitch"},
  ['shellyrgbw2:color']    = {className="RGB",fibaroType="com.fibaro.colorController"},
  ['shellydimmer:white']   = {className="Dimmer",fibaroType="com.fibaro.multilevelSwitch"},
  ['shellydimmersl:white'] = {className="Dimmer",fibaroType="com.fibaro.multilevelSwitch"},
  ['shellyvintage:white']  = {className="Dimmer",fibaroType="com.fibaro.multilevelSwitch"},
}

debugs = { updates = true }
modules = {"events","childs"}
local format = string.format
_version = "0.9"

INTERVAL = 2000
Shellys  = {}    -- name:ip -> device object
IPrelays = {}    -- ip -> {device1,..}
Watchers = {}

function QuickApp:onInit()
  self:post({type='start'},1)
  for id,child in pairs(self.childDevices) do
    Shellys[child.sid]=child
  end
end

class 'ShellyDevice'(QuickAppChild)
function ShellyDevice:__init(device)
  QuickAppChild.__init(self,device)
  self.className = self:getVariable("className")
  self.name = self:getVariable("name")
  self.sid = self:getVariable("sid")
  self.ip = self:getVariable("ip")
  self.creds = self:getVariable("creds")
  self.relay = self:getVariable("relay")
  self.base = "http://"..self.ip.."/"
  self.uri = "status"
  self:tracef("%s inited, IP:%s, Relay:%s, DeviceId:%s",self.className,self.ip,self.relay,self.id)
  IPrelays[self.ip]=IPrelays[self.ip] or {}
  table.insert(IPrelays[self.ip],self)
  if not Watchers[self.ip] then
    Watchers[self.ip] = self
    self:poll()
  end
end
function ShellyDevice:poll()
  quickApp:shellyRequest{
    baseURI=self.base,uri=self.uri,creds=self.creds,
    cont={type='update', dev=self},
    err=={type='updateAgain', dev=self},
  }
end

function ShellyDevice:_update(data)
  --quickApp:trace(quickApp:prettyJsonStruct(data))
  for _,d in ipairs(IPrelays[self.ip] or {}) do
    d:update(data)
  end
end

class 'SingleSwitch'(ShellyDevice)
function SingleSwitch:__init(device)
  ShellyDevice.__init(self,device)
end

function SingleSwitch:turnOn()
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "relay/"..self.relay.."?turn=on" }
end

function SingleSwitch:turnOff()
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "relay/"..self.relay.."?turn=off" }
end

function SingleSwitch:toggle()
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "relay/"..self.relay.."?turn=toggle" }
end

function SingleSwitch:update(data)
  local r = tonumber(self.relay)+1
  local relay= data.relays[r]
  local meter= data.meters and data.meters[r] or {}
  if debugs.updates then self:tracef("ID:%s, On:%s, Power:%s",self.id,relay.ison,meter.power) end
  self.total = (meter.total or 0)/60000
  if meter.power ~= self.power then
    self.power = meter.power
    self:updateProperty("power",meter.power)
  end
  self:updateProperty("value",relay.ison)
end

class 'Dimmer'(ShellyDevice)
function Dimmer:__init(device)
  ShellyDevice.__init(self,device)
end

function Dimmer:turnOn()
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "light/"..self.relay.."?turn=on" }
end

function Dimmer:turnOff()
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "light/"..self.relay.."?turn=off" }
end

function Dimmer:toggle()
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "lights/"..self.relay.."?turn=toggle" }
end

function Dimmer:setValue(value)
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "lights/"..self.relay.."?brightness="..value }
end

function Dimmer:update(data)
  local r = tonumber(self.relay)+1
  local light= data.lights[r]
  local meter= data.meters and data.meters[r] or {}
  if debugs.updates then self:tracef("ID:%s, On:%s, Power:%s",self.id,light.ison,meter.power) end
  self.total = (meter.total or 0)/60000
  if meter.power and meter.power ~= self.power then
    self.power = meter.power
    self:updateProperty("power",meter.power)
  end
  self:updateProperty("value",lights.ison and light.brightness or 0)
end

class 'RGB'(ShellyDevice)
function RGB:__init(device)
  ShellyDevice.__init(self,device)
end

function RGB:turnOn()
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "light/"..self.relay.."?turn=on" }
end

function RGB:turnOff()
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "light/"..self.relay.."?turn=off" }
end

function RGB:toggle()
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "lights/"..self.relay.."?turn=toggle" }
end

function RGB:setValue(value)
  quickApp:shellyRequest{ baseURI = self.base, creds = self.creds, uri = "lights/"..self.relay.."?gain="..value }
end

function RGB:setColor(r,g,b,w)
  local p = format("red=%s&green=%s&blue=%s&white=%s",r,g,b,w)
  quickApp:shellyRequest{ 
    baseURI = self.base, 
    creds = self.creds, 
    uri = "lights/"..self.relay.."?"..p
  }
end

function RGB:update(data)
  local r = tonumber(self.relay)+1
  local light= data.lights[r]
  local meter= data.meters and data.meters[r] or {}
  if debugs.updates then self:tracef("ID:%s, On:%s, Power:%s",self.id,light.ison,meter.power) end
  self.total = (meter.total or 0)/60000
  if meter.power ~= self.power then
    self.power = meter.power
    self:updateProperty("power",meter.power)
  end
  local c = format("%s:%s:%s:%s",light.red,light.green,light.blue,light.white)
  self:updateProperty("color",c)
  self:updateProperty("value",lights.ison and light.gain or 0)
end
----------------------------------------------------------------------------------------------

function QuickApp:turnOn() 
  self:callChildren("turnOn") 
  self:updateProperty("value",99)
end

function QuickApp:turnOff()
  self:callChildren("turnOff") 
  self:updateProperty("value",0)
end

function QuickApp:remove() self:removeAllChildren() plugin.restart() end

function QuickApp:shellyRequest(args)
  local baseURI,uri,creds,cont,err = args.baseURI,args.uri,args.creds,args.cont,args.err
  --self:trace(baseURI..uri)
  local f = baseURI:match("http://(.-)/")
  if _G[f] then _G[f](uri); return end -- testing
  net.HTTPClient():request(baseURI..uri,{
      options={
        headers={['Authorization'] = creds, ["Accept"] = 'application/json'},
      },
      success=function(res) 
        if res.status > 201 then
          self:warningf("Error:%s - %s",res.status,res.data)
          if err then err.data=res; self:post(err) end
        else
          if cont then cont.data=json.decode(res.data); self:post(cont) end
        end
      end,
      error=function(res) 
        if err then err.data=res; self:post(err) else self:post({type='error',data=res}) end
      end,
    })
end

function QuickApp:main()

  self:event({type='start'},
    function(env)
      setInterval(function()
          for _,w in pairs(Watchers) do w:poll() end
        end,INTERVAL)

      for _,val in pairs(self.config) do
        local name,relay,user,pwd,ip = val:match("(.-):(.-):(.-):(.-):(.*)")
        if user and pwd and ip then
          local creds = self:basicAuthorization(user,pwd)
          self:shellyRequest{
            baseURI="http://"..ip.."/",
            uri="settings",
            creds = creds,
            cont={type='info',info={ip=ip,relay=relay,creds=creds,name=name}}
          }
        end
      end
    end)

  self:event({type='info'},
    function(env)
      local specs = env.event.data
      local ip = env.event.info.ip
      local creds = env.event.info.creds
      local relay = env.event.info.relay
      local name = env.event.info.name
      --self:debug(self:prettyJsonStruct(specs))
      local sid = name..":"..ip
      local shellyType=specs.name:match("(.-)-"):lower()
      shellyType = shellyType..(specs.mode and (":"..specs.mode) or "")
      if Shellys[sid] then
        --self:tracef("Shelly %s:%s exists",ip,i)
      else
        local map = deviceMap[shellyType]
        if not map then
          self:warning("Type %s for %s is unknown",specs.type,ip)
        else
          local d = self:createChild{
            className=map.className,
            type=map.fibaroType,
            name=name,
            interfaces={"power"},
            quickVars={sid=sid,ip=ip,creds=creds,relay=relay,name=name}
          }
          if d then Shellys[sid] = d end
        end
      end
    end)

  self:event({type='update'},
    function(env)
      local dev = env.event.dev
      local data = env.event.data
      dev:_update(data)
      self:post(function() dev:poll() end,INTERVAL)
    end)

  self:event({type='updateAgain'},
    function(env)
      self:warning(env.event.data)
      self:post(function() dev:poll() end,2*INTERVAL)
    end)

  self:event({type='error'},
    function(env)
      self:warning(env.event.data)
    end)
end

-------------------------- Simulated devices ----------------------

function fakeDim1(uri)
  if uri=='settings' then
    quickApp:post({
        type='info',
        data= {name="ShellyDimmer-*",type="SDT",mode="white"},
        info={ip='fakeDim1',relay="0",name="D1"}
        },1)
  elseif uri=="status" then
  else
    local dev = Shellys["D1:fakeDim1"]
    local cmd,val=uri:match("%?(.-)=(.*)")
    dev._value = dev._value or 0
    if cmd=='turn' then
      if val=="on" then dev:updateProperty("value",dev._value)
      elseif val=="off" then dev:updateProperty("value",0) end
    elseif cmd=="brightness" then
      dev._value = tonumber(val)
      dev:updateProperty("value",dev._value )
    end
  end
end

function fakeRGB1(uri)
  if uri=='settings' then
    quickApp:post({
        type='info',
        data= {name="ShellyRGBW2-*",type="RGB",mode="color"},
        info={ip='fakeRGB1',relay="0",name="R1"}
        },1)
  elseif uri=="status" then
  else
    local dev = Shellys["R1:fakeRGB1"]
    local cmd,val=uri:match("%?(.-)=(.*)")
    dev._value = dev._value or 0
    if cmd=='turn' then
      if val=="on" then dev:updateProperty("value",dev._value)
      elseif val=="off" then dev:updateProperty("value",0) end
    elseif cmd=="gain" then
      dev._value = tonumber(val)
      dev:updateProperty("value",dev._value )
    elseif cmd=="red" then
      local r,g,b,w = uri:match("red=(%d+)&green=(%d+)&blue=(%d+)&white=(%d+)")
      local v = format("%s,%s,%s,%s",r,g,b,w)
      dev:updateProperty("color",v)
    end
    print(uri)
  end
end

