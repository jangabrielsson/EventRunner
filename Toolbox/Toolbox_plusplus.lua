--[[
  Toolbox PlusPlus.
  
  Functions to make device and globals easier to manipulate

--]]

Toolbox_Module = Toolbox_Module or {}
Toolbox_Module.plusplus ={
  name = "PlusPlus",
  author = "jan@gabrielsson.com",
  version = "0.1"
}

function Toolbox_Module.plusplus.init(self)

  class "PP_Global"
  function PP_Global:getValue()
    local _marshalBool={['true']=true,['True']=true,['TRUE']=true,['false']=false,['False']=false,['FALSE']=false}
    local v = fibaro.getGlobalVariable(self.name)
    if v == nil then return v end
    local fc = v:sub(1,1)
    if fc == '[' or fc == '{' then local s,t = pcall(json.decode,v); if s then return t end end
    if tonumber(v) then return tonumber(v)
    elseif _marshalBool[v ]~=nil then return _marshalBool[v ] end
    local s,t = pcall(toTime,v); return s and t or v 
  end

  function PP_Global:setValue(v) 
    v = type(v)=='table' and (json.encode(v)) or tostring(v)
    fibaro.setGlobalVariable(self.name,v)
  end

  function PP_Global:__init(global,force) 
    self.name = global
    self.value = property(PP_Global.getValue,PP_Global.setValue)
    local t = api.get("/globalVariables/"..global)
    if t == nil and force then
      self:debug("Creating variable ",global)
      api.post("/globalVariables/"..global)
    elseif t == nil then 
      error("Variable "..global.." doesn't exists") 
    end
  end

  class"PP_Dev"
  function PP_Dev:__init(id)
    self.id = id
  end

  function PP_Dev:turnOn() fibaro.call(self.id,'turnOn') end
  function PP_Dev:turnOff() fibaro.call(self.id,'turnOff') end
  function PP_Dev:toggle() fibaro.call(self.id,'toggle') end
  function PP_Dev:setValue(value) fibaro.call(self.id,'updateProperty',value) end
  function PP_Dev:sample(time,interval,prop)
  end
  function PP_Dev:callback(prop,cb)
  end
  function PP_Dev:callback(prop,cb)
  end
  function PP_Dev:breached(cb)
  end
  function PP_Dev:safe(cb)
  end
  
end