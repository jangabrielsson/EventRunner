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

function Toolbox_Module.childs(self)
  local version = "0.3"
  self:debugf("Setup: Child manager (%s)",version) 

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
        "notify","setType","setVisible","setEnabled","setIconMessage","setName","getView",
        "setView","debug","trace","error","warning","debugf","tracef","errorf","warningf","basicAuthorization"}) 
    do classObj[m] = self[m] end
    classObj._annotated = true
    classObj._2JSON = true
    classObj._DEBUG = true
    classObj._TRACE = true
    classObj._HTML  = true
    classObj.config,classObj.debugFlags = {},{}
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
    for n,v in pairs(args.quickVars or {}) do table.insert(properties.quickAppVariables,1,{name=n,value=v}) end
    -- Save class name so we know when we load it next time
    table.insert(properties.quickAppVariables,1,{name='className', value=className}) -- Add first
    local child = self:createChildDevice({
        name = name,
        type=tpe,
        initialProperties = properties,
        initialInterfaces = interfaces
      },
      _G[className] -- Fetch class constructor from class name
    )
    return child
  end

-- Loads all children, called automatically at startup
  function self:loadChildren()
    local cdevs,n = api.get("/devices?parentId="..self.id) or {},0 -- Pick up all my children
    function self:initChildDevices() end -- Null function, else Fibaro calls it after onInit()...
    for _,child in ipairs(cdevs or {}) do
      local className = self:getChildVariable(child,"className")
      self:_annotateClass(_G[className])
      local childObject = _G[className] and _G[className](child) or QuickAppChild(child)
      self.childDevices[child.id]=childObject
      childObject.parent = self
      n=n+1
    end
    return n
  end

-- UI handler to pass button clicks to children
  function self:UIHandler(event)
    local obj = self
    if self.id ~= event.deviceId then obj = self.childDevices[event.deviceId] end
    if not obj then return end
    local elm,etyp = event.elementName, event.eventType
    local cb = obj.uiCallbacks or {}
    if obj[elm] then return obj:callAction(elm, event) end
    if cb[elm] and cb[elm][etyp] then return obj:callAction(cb[elm][etyp], event) end
    if obj[elm.."Clicked"] then return obj:callAction(elm.."Clicked", table.unpack(event.values or {})) end
    self:warning("UI callback for element:", elm, " not found.")
  end
end
