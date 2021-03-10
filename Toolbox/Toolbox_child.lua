--[[
  Toolbox child.
  
  Functions to easier create load and handle QuickAppChilds

  function QuickApp:createChild(args)                 -- Create child device, see code below...
  function QuickApp:numberOfChildren()                -- Returns number of existing children
  function QuickApp:removeAllChildren()               -- Remove all child devices
  function QuickApp:callChildren(method,...)          -- Call all child devices with method. 
  function QuickApp:setChildIconPath(childId,path)

--]]

Toolbox_Module = Toolbox_Module or {}
Toolbox_Module.childs = {
  name = "Child device manager",
  author = "jan@gabrielsson.com",
  version = "0.4"
}

function Toolbox_Module.childs.init(self)
  if Toolbox_Module.childs.inited then return Toolbox_Module.childs.inited end
  Toolbox_Module.childs.inited = true 
  local _G = _G or _ENV

  function self:setChildIconPath(childId,path)
    api.put("/devices/"..childId,{properties={icon={path=path}}})
  end

--Ex. self:callChildren("method",1,2) will call MyClass:method(1,2) 
  function self:callChildren(method,...)
    for _,child in pairs(self.childDevices or {}) do 
      if child[method] then 
        local stat,res = pcall(child[method],child,...)  
        if not stat then self:debug(res) end
      end
    end
  end

--Removes all children belonging to this device
  function self:removeAllChildren()
    for id,_ in pairs(self.childDevices or {}) do self:removeChildDevice(id) end
  end

--Returns number of children belonging to this device
  function self:numberOfChildren()
    local n = 0
    for _,_ in pairs(self.childDevices or {}) do n=n+1 end
    return n
  end

-- Used before we have a child object. Afterwards we can use child:getVariable("var")
  function self:getChildVariable(child,varName) 
    for _,v in ipairs(child.properties.quickAppVariables or {}) do
      if v.name==varName then return v.value end
    end
    return ""
  end

  function self:_annotateClass(classObj)
    if not classObj then return end
    local stat,res = pcall(function() return classObj._annotated end) 
    if stat and res then return end
    --self:debug("Annotating class")
    for _,m in ipairs({
        "notify","setType","setVisible","setEnabled","setIconMessage","setName","getView","updateProperty",
        "setView","debug","trace","error","warning","debugf","tracef","errorf","warningf","basicAuthorization"}) 
    do classObj[m] = self[m] end
    classObj._annotated = true
    classObj._2JSON = true
    classObj._DEBUG = true
    classObj._TRACE = true
    classObj._HTML  = true
    classObj.config,classObj.debugFlags = {},{}
  end

  local function setCallbacks(obj,callbacks)
    if callbacks =="" then return end
    local cbs = {}
    for _,cb in ipairs(callbacks or {}) do
      cbs[cb.name]=cbs[cb.name] or {}
      cbs[cb.name][cb.eventType] = cb.callback
    end
    obj.uiCallbacks = cbs
  end
  
--[[
  QuickApp:createChild{
    className = "MyChildDevice",      -- class name of child object
    name = "MyName",                  -- Name of child device
    type = "com.fibaro.binarySwitch", -- Type of child device
    properties = {},                  -- Initial properties
    interfaces = {},                  -- Initial interfaces
  }
--]]
  function self:createChild(args)
    local className = args.className or "QuickAppChild"
    self:_annotateClass(_G[className])
    local name = args.name or "Child"
    local tpe = args.type or "com.fibaro.binarySensor"
    local properties = args.properties or {}
    local interfaces = args.interfaces or {}
    properties.quickAppVariables = properties.quickAppVariables or {}
    local function addVar(n,v) table.insert(properties.quickAppVariables,1,{name=n,value=v}) end
    for n,v in pairs(args.quickVars or {}) do addVar(n,v) end
    local callbacks = properties.uiCallbacks
    if  callbacks then 
      local function copy(t) local r={}; for k,v in pairs(t) do r[k]=v end return r end
      callbacks = copy(callbacks)
      addVar('_callbacks',callbacks)
    end
    -- Save class name so we know when we load it next time
    addVar('className',className) -- Add first
    local child = self:createChildDevice({
        name = name,
        type=tpe,
        initialProperties = properties,
        initialInterfaces = interfaces
      },
      _G[className] -- Fetch class constructor from class name
    )
    setCallbacks(child,callbacks)
    return child
  end

-- Loads all children, called automatically at startup
  function self:loadChildren()
    local cdevs,n = api.get("/devices?parentId="..self.id) or {},0 -- Pick up all my children
    function self:initChildDevices() end -- Null function, else Fibaro calls it after onInit()...
    for _,child in ipairs(cdevs or {}) do
      local className = self:getChildVariable(child,"className")
      local callbacks = self:getChildVariable(child,"_callbacks")
      self:_annotateClass(_G[className])
      local childObject = _G[className] and _G[className](child) or QuickAppChild(child)
      self.childDevices[child.id]=childObject
      childObject.parent = self
      setCallbacks(childObject,callbacks)
      n=n+1
    end
    return n
  end

  local orgRemoveChildDevice = self.removeChildDevice
  function self:removeChildDevice(id)
    if self.childRemovedHook then
      pcall(function() self.childRemovedHook(id) end)
    end
    return orgRemoveChildDevice(self,id)
  end
  function self:setChildRemovedHook(fun) self.childRemovedHook=fun end

-- UI handler to pass button clicks to children
  function self:UIHandler(event)
    local obj = self
    if self.id ~= event.deviceId then obj = (self.childDevices or {})[event.deviceId] end
    if not obj then return end
    local elm,etyp = event.elementName, event.eventType
    local cb = obj.uiCallbacks or {}
    if obj[elm] then return obj:callAction(elm, event) end
    if cb[elm] and cb[elm][etyp] and obj[cb[elm][etyp]] then return obj:callAction(cb[elm][etyp], event) end
    if obj[elm.."Clicked"] then return obj:callAction(elm.."Clicked", event) end
    if self.EM then
      self:post({type='UI',name=event.elementName,event=event.eventType,value=event.values})
    else
      self:warning("UI callback for element:", elm, " not found.")
    end
  end
end