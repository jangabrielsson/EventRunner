_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  modPath = "TQAEmodules/",
  temp = "temp/",
  startTime="12/24/2024-07:00",
}

-- Binary switch type should handle actions turnOn, turnOff
-- To update binary switch state, update property "value" with boolean

local function base64encode(data)
  __assert_type(data,"string" )
  local bC='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x) 
          local r,b='',x:byte() for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
          return r;
        end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return bC:sub(c+1,c+1)
      end)..({ '', '==', '=' })[#data%3+1])
end

local function basicAuthorization(user,password) 
  return "Basic "..base64encode(user..":"..password)
end

function QuickApp:turnOn()
  self:debug("binary switch turned on")
  self:updateProperty("value", true)
  self.http:request(self.httpAddress ..self.activateURL,{
      options={
        method="GET",
        headers={['Authorization']=self.creds}
      },
      success=function(response)
        self:debug("Va fan",json.encode(response))
        self:debug(response.status)
        self:debug(response.data)
        self:updateView("label1_1", "text", "Aktiverad")
      end,
      error=function(message)
        self:error(message)
      end
    })
end

function QuickApp:turnOff()
  self:debug("binary switch turned off")
  self:updateProperty("value", false) 
  self.http:request(self.httpAddress ..self.deactivateURL,{
      options={
        method="GET",
        headers={['Authorization']=self.creds}
      },
      success=function(response)
        self:debug(response.status)
        self:debug(response.data)
        self:updateView("label1_1", "text", "Deaktiverad")
      end,
      error=function(message)
        self:error(message)
      end
    })   
end


function QuickApp:onInit()
  local user="root"
  local password="pass"
  self:debug("onInit")
  self:debug(self.name,self.id)
  self.http=net.HTTPClient({timeout=3000})
  self.httpAddress="http://192.168.1.202/"
  self.activateURL="axis-cgi/virtualinput/activate.cgi?schemaversion=1&port=1"
  self.deactivateURL="axis-cgi/virtualinput/deactivate.cgi?schemaversion=1&port=1"
  if password
  then
    self.creds=basicAuthorization(user,password)
  end
  self:debug(self.httpAddress..self.activateURL)
  self:debug(self.httpAddress..self.deactivateURL)
end


