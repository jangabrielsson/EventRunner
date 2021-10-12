_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  modPath = "TQAEmodules/",
  temp = "temp/",
  startTime="12/24/2024-07:00",
}

--%%name="Hue"
--%%quickVars = {['HueID'] = "q6eLpWdYiMGq0kdQWFZB1NZHSllvKL0GsNPJeEa-", ['HueIP'] = "192.168.1.153" }
-- %%proxy = true

_version = "0.1"
local format = string.format 

MyHueDevices = { 
  [6] = {
    className = 'Light', name='Kitchen', hueType='lights', fibaroType='com.fibaro.binarySwitch',
  },
  [9] = {
    className = 'Sensor', name='Bathroom', hueType='sensors', fibaroType='com.fibaro.binarySensor',
  },
}

HueID2Child = {} -- Mapping of hue device ID to the Lua object that represents the QuickAppChild
-- We need this mapping when we poll the Hue bridge. We then get hue devices and their states. We can then look
-- upp what QuickAppChild represents that hue device and give the new state to that child.

---------------- Lights --------------------------
class 'Light'(QuickAppChild)
function Light:__init(device)
  QuickAppChild.__init(self,device)           -- Need to call super class initializer
  self.hueId = self:getVariable("hueId")      -- Read in variables for convenience. Let us access child.hueId
  self.hueType = self:getVariable("hueType") 
end

function Light:turnOn()
  quickApp:sendHueRequest(self.hueId,'lights',{on=true})
end

function Light:turnOff()
  quickApp:sendHueRequest(self.hueId,'lights',{on=false})
end

function Light:update(state) 
  self:updateProperty('value',state.on) -- On is true and off is false
  self:updateProperty('state',state.on) 
end

------------------ Sensors -----------------------
class 'Sensor'(QuickAppChild)
function Sensor:__init(device)
  QuickAppChild.__init(self,device)
  self.hueId = self:getVariable("hueId")
  self.hueType = self:getVariable("hueType")
end

function Sensor:update(state) 
  self:updateProperty('value',state.status > 0) -- My sensor has status > 0 if on...
end

------------------- ----------------------------- 
function QuickApp:pollHue()            
  local url = format("http://%s:80/api/%s/",self.HueIP,self.userID)
  net.HTTPClient():request(url,{ 
      options = { method='GET'},
      success = function(resp)
        local data = json.decode(resp.data)            -- data in form { id1 = data1, id2 = data2, ... } 
        if data and data[1] and data[1].error then
          self:error(data[1].error.description)
          return
        end
        for hueId,child in pairs(HueID2Child) do      --- This is why we need the HueID2Child table
          if data[child.hueType][tostring(hueId)] then --- We get the hueID and need to know what child to send the data too
            child:update(data[child.hueType][tostring(hueId)].state)
          end
        end
      end
    })
end

function QuickApp:sendHueRequest(id,type,data)
  local url = format("http://%s:80/api/%s/%s/%s/state",self.HueIP,self.userID,type,id)
  net.HTTPClient():request(url,{ options = { method='PUT', data = json.encode(data) }})
end

function QuickApp:createHueChild(hueId,name,hueType,fibaroType,className)
  local props = { quickAppVariables = {
      {name='className',value=className},{name='hueId', value=hueId},{name='hueType', value=hueType}
    }
  }
  HueID2Child[hueId]=self:createChildDevice({
      name = name,
      type= fibaroType,
      initialProperties = props,
      },_G[className])
end

--------------------------------------------------
function QuickApp:onInit()
  self.userID = self:getVariable('HueID')         -- Need Hue user key
  self.HueIP = self:getVariable('HueIP')          -- .. and IP to Hue bridge

  if self.userID=="" or self.HueIP=="" then -- Warn and disable QA if credentials are not provided
    self:error("Missing credentials")
    --self:setEnabled(false)
    return
  end

  local function getClass(vs) for _,v in ipairs(vs) do if v.name=='className' then return v.value end end end 
  function self:initChildDevices() end
  for _,c in ipairs(api.get("/devices?parentId="..self.id) or {}) do -- Load existing children
    self.childDevices[c.id]=_G[getClass(c.properties.quickAppVariables)](c)
  end

  for id,child in pairs(self.childDevices) do -- Create lookup table from HueId to Child
    HueID2Child[child.hueId]=child            -- Advantage of previously stored huedId with child...
  end

  for hueId,config in pairs(MyHueDevices) do  -- If not all defined hue devices exists, create them
    if not HueID2Child[hueId] then
      self:createHueChild(hueId,config.name,config.hueType,config.fibaroType,config.className)
    end
  end

  setInterval(function() self:pollHue() end,1500) -- poll Hue bridge every 1.5s
end