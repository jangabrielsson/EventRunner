-- Local module, loaded into each QA's environment
__TAG="QUICKAPP"..plugin.mainDeviceId

function plugin.deleteDevice(deviceId) return api.delete("/devices/"..deviceId) end
function plugin.restart(deviceId) return api.post("/plugins/restart",{deviceId=deviceId or quickApp.id}) end
function plugin.getProperty(id,prop) return api.get("/devices/"..id.."/property/"..prop) end
function plugin.getChildDevices(id) return api.get("/devices?parentId="..(id or quickApp.id)) end
function plugin.createChildDevice(props) return api.post("/plugins/createChildDevice",props) end

class 'QuickAppBase'

function QuickAppBase:__init(dev)
  self.id         = dev.id
  self.name       = dev.name
  self.type       = dev.type
  self.enabled    = true
  self.properties = dev.properties
  self.interfaces = dev.interfaces
  self._view      = {} -- TBD
  self.uiCallbacks = {}
  for _,e in ipairs(dev.uiCallbacks or {}) do
    self.uiCallbacks[e.name] = self.uiCallbacks[e.name] or {} 
    self.uiCallbacks[e.name][e.eventType]=e.callback
  end
end

function QuickAppBase:debug(...)   fibaro.debug(__TAG,...) end
function QuickAppBase:error(...)   fibaro.error(__TAG,...) end
function QuickAppBase:warning(...) fibaro.warning(__TAG,...) end
function QuickAppBase:trace(...)   fibaro.trace(__TAG,...) end

function QuickAppBase:callAction(name,...)
  assert(self[name],"callAction: No such method "..tostring(name))
  self[name](self,...) 
end

function QuickAppBase:getVariable(name)
  __assert_type(name,'string')
  for _,v in ipairs(self.properties.quickAppVariables or {}) do if v.name==name then return v.value end end
  return ""
end

function QuickAppBase:setVariable(name,value)
  __assert_type(name,'string')
  local vars = self.properties.quickAppVariables or {}
  for _,v in ipairs(vars) do if v.name==name then v.value=value return end end
  self.properties.quickAppVariables = vars
  vars[#vars+1]={name=name,value==value}
end

function QuickAppBase:updateProperty(prop,val)
  __assert_type(prop,'string')
  if self.properties[prop] ~= val then
    self.properties[prop]=val 
    api.post("/plugins/updateProperty", {deviceId=self.id, propertyName=prop, value=val})
  end
end

function QuickAppBase:updateView(elm,typ,val)
  __assert_type(elm,'string')
  __assert_type(typ,'string')
  self:debug("updateView:",elm,typ,val)
  self._view[elm]=self._view[elm] or {} self._view[elm][typ]=val 
end

class 'QuickApp'(QuickAppBase)

function QuickApp:__init(device)
  QuickAppBase.__init(self,device)
  self.childDevices = {}
  if self.onInit then self:onInit() end
  if self._childsInited==nil then self:initChildDevices() end
  quickApp = self
end

function QuickApp:createChildDevice(props,deviceClass)
  __assert_type(props,'table')
  props.parentId = self.id
  props.initialInterfaces = props.initialInterfaces or {}
  table.insert(props.initialInterfaces,'quickAppChild')
  local device,res = api.post("/plugins/createChildDevice",props)
  assert(res==200,"Can't create child device "..res.." - "..json.encode(props))
  deviceClass = deviceClass or QuickAppChild
  local child = deviceClass(device)
  child.parent = self
  self.childDevices[device.id]=child
  return child
end

function QuickApp:removeChildDevice(id)
  __assert_type(id,'number')
  if self.childDevices[id] then
    api.delete("/plugins/removeChildDevice/" .. id)
    self.childDevices[id] = nil
  end
end

function QuickApp:initChildDevices(map)
  map = map or {}
  local children = api.get("/devices?parentId="..self.id) or {}
  local childDevices = self.childDevices
  for _,c in pairs(children) do
    if childDevices[c.id]==nil and map[c.type] then
      childDevices[c.id]=map[c.type](c)
    elseif childDevices[c.id]==nil then
      self:error("Class for the child device: %s, with type: %s not found. Using base class: QuickAppChild",c.id,c.type)
      childDevices[c.id]=QuickAppChild(c)
    end
    childDevices[c.id].parent = self
  end
  self._childsInited = true
end

class 'QuickAppChild'(QuickAppBase)

function QuickAppChild:__init(device)
  QuickAppBase.__init(self,device)
  if self.onInit then self:onInit() end
end

function onAction(id,event)
  if _VERBOSE then print("onAction: ", json.encode(event)) end
  if quickApp.actionHandler then return self:actionHandler(event) end
  if event.deviceId == quickApp.id then
    return quickApp:callAction(event.actionName, table.unpack(event.args)) 
  elseif quickApp.childDevices[event.deviceId] then
    return quickApp.childDevices[event.deviceId]:callAction(event.actionName, table.unpack(event.args)) 
  end
  quickApp:warning(format("Child with id:%s not found",id))
end

function onUIEvent(id, event)
  if _VERBOSE then print("UIEvent: ", json.encode(event)) end
  if quickApp.UIHandler then quickApp:UIHandler(event) return end
  if quickApp.uiCallbacks[event.elementName] and quickApp.uiCallbacks[event.elementName][event.eventType] then 
    quickApp:callAction(quickApp.uiCallbacks[event.elementName][event.eventType], event)
  else
    quickApp:warning(format("UI callback for element:%s not found.", event.elementName))
  end 
end