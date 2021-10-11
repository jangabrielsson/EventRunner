_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
}

--%%name="Camera"
--%%type="com.fibaro.binarySwitch"

local baseURL = "http://192.168.1.xxx/"  
local activate = "axis-cgi/virtualin ... s=password"
local deactivate = "axis-cgi/virtualin ... s=password"

local function sendCommand(cmd)
  net.HTTPClient():request(baseURL..cmd,{
      options = { method = "GET" },
      success = function(resp) quickApp:debug("Success",json.encode(resp)) end,
      error = function(err) quickApp:error(err) end
    })
end

function QuickApp:turnOn()
  sendCommand(activate)
  self:updateProperty("value",true)
  self:updateProperty("status",true)
end

function QuickApp:turnOff()
  sendCommand(deactivate)
  self:updateProperty("value",false)
  self:updateProperty("status",false)
end

function QuickApp:onInit()
  self:debug(self.name,self.id)
end 
