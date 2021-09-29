--[[
TQAE - Tiny QuickApp emulator for the Fibaro Home Center 3
Copyright (c) 2021 Jan Gabrielsson
Email: jan@gabrielsson.com
MIT License

Support for local shadowing global variables - and other resources

--]]
local EM,FB = ...

local json = FB.json
local HC3Request,LOG,Devices = EM.HC3Request,EM.LOG,EM.Devices
local __fibaro_get_devices,__fibaro_get_device,__fibaro_get_device_property,__fibaro_call,__assert_type=
FB.__fibaro_get_devices,FB.__fibaro_get_device,FB.__fibaro_get_device_property,FB.__fibaro_call,FB.__assert_type
local copy = EM.utilities.copy


local globals = {}

local function setup()

  function FB.__fibaro_get_global_variable(name) 
    __assert_type(name ,"string") 
    if globals[name] then 
      return globals[name],200
    else
      return HC3Request("GET","/globalVariables/"..name) 
    end
  end

  EM.addAPI("GET/globalVariables",function(method,path,data)
    end)
  EM.addAPI("GET/globalVariables/#name",function(method,path,data,name)
      if globals[name] then return globals[name],200 end
    end)
  EM.addAPI("PUT/globalVariables/#name",function(method,path,data,name)
      if not globals[name] then return end
      globals[name].value,globals[name].modified = data.value,EM.osTime()
      return globals[name],200
    end)
  EM.addAPI("POST/globalVariables",function(method,path,data)
      if globals[data.name] then return nil,400
      else
        globals[data.name] = {name=data.name, value = data.value, modified = EM.osTime() }
        return globals[data.name],200
      end
    end)
  EM.addAPI("DELETE/globalVariables/#name",function(method,path,data,name)
    end)
end

EM.EMEvents('start',function(ev) if EM.offline then setup() end end)


