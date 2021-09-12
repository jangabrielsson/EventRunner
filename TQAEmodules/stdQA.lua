local EM,FB = ...

local json,LOG = FB.json,EM.LOG

local devices = {
  ["binarySwitch"] = 
[[
  --%%type="com.fibaro.binarySwitch"
  function QuickApp:turnOn()
    if not self.properties.value then
     self:updateProperty("value",true)
     self:updateProperty("state",true)
    end
  end
  function QuickApp:turnOff()
    if self.properties.value then
     self:updateProperty("value",false)
     self:updateProperty("state",false)
    end
  end
  function QuickApp:toggle()
    if self.properties.value then self:turnOff() else self:turnOn() end
  end
  function QuickApp:onInit()
    self:debug(self.name,self.id)
  end
]],

  ["binarySensor"] = 
[[
  --%%type="com.fibaro.binarySensor"
  local timer
  function QuickApp:breach(s)
    self:updateProperty("value",true)
    if timer then clearTimeout(timer) timer=nil end
    timer = setTimeout(function() 
       self:updateProperty("value",false); timer = nil end,
       (tonumber(s) or 10)*1000)
  end
  function QuickApp:onInit()
    self:debug(self.name,self.id)
  end
]],

  ["multilevelSwitch"] = 
[[
  --%%type="com.fibaro.multilevelSwitch"
  function QuickApp:turnOn()
  end
  function QuickApp:turnOff()
  end
  function QuickApp:setValue(value)
  end
  function QuickApp:onInit()
    self:debug(self.name,self.id)
  end
]],

  ["multilevelSensor"] = 
[[
  --%%type="com.fibaro.multilevelSensor"
  function QuickApp:setValue(value)
    self:updateProperty("value",value)
  end
  function QuickApp:onInit()
    self:debug(self.name,self.id)
  end
]],
}

local create = {}
for t,d in pairs(devices) do
  create[t] = function(id,name)
    EM.installQA{id=id,code=d,name=name} 
  end
end

EM.createDevices = create