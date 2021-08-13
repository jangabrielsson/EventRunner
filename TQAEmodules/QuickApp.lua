  -- Local module, loaded into each QA's environment
  __TAG="QUICKAPP"..plugin.mainDeviceId
  
  QuickApp = {['_TYPE']='userdata'}
  function QuickApp:__init(dev) -- our QA is a fake "class"
    self.id = dev.id
    self.name=dev.name
    self.type = dev.type
    self.enabled = true
    self.properties = dev.properties
    self.interfaces = dev.interfaces
    self._view = {} -- TBD
    if self.onInit then self:onInit() end
    quickApp = self
  end

  function QuickApp:debug(...) fibaro.debug(__TAG,...) end
  function QuickApp:error(...) fibaro.error(__TAG,...) end
  function QuickApp:warning(...) fibaro.warning(__TAG,...) end
  function QuickApp:trace(...) fibaro.trace(__TAG,...) end
    
  function QuickApp:callAction(name,...)
    __assert_type(self[name],'function')
    self[name](self,...) 
    end
    
  function QuickApp:getVariable(name)
    for _,v in ipairs(self.properties.quickAppVariables or {}) do if v.name==name then return v.value end end
    return ""
  end
  
  function QuickApp:setVariable(name,value)
    local vars = self.properties.quickAppVariables or {}
    for _,v in ipairs(vars) do if v.name==name then v.value=value return end end
    self.properties.quickAppVariables = vars
    vars[#vars+1]={name=name,value==value}
  end
  
  function QuickApp:updateProperty(prop,val) 
    if self.properties[prop] ~= val then
      self.properties[prop]=val 
      api.post("/plugins/updateProperty", {deviceId=self.id, propertyName=prop, value=val})
    end
  end
  
  function QuickApp:updateView(elm,typ,val) 
    self:debug("View:",elm,typ,val)
    self._view[elm]=self._view[elm] or {} self._view[elm][typ]=val 
  end
  
  function onAction(self,event)
    if _VERBOSE then print("onAction: ", json.encode(event)) end
    if self.actionHandler then self:actionHandler(event)
    else self:callAction(event.actionName, table.unpack(event.args)) end
  end