_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  modPath = "TQAEmodules/",
  temp = "temp/",
}
--[[
  Test WebSocket QA to control Samsung Q7 TV
  Power off works...
--]]

--%%name="SamsungTV"
--%%type="com.fibaro.philipsTV"
--%%quickVars={ IP = "192.168.1.175", name = "HC3" }
--%%u1={button="Power", text="Power", onReleased="power"}
--%%u2={button="Mute", text="Mute", onReleased="mute"}

local self,connect,handleDataReceived,handleError,handleDisconnected,handleConnected
local function setSelf(qa) self = qa end

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

function QuickApp:sendCmd(key)
  self:trace("Send key:",key)
  if self.sock:isOpen() then
    local data = {
      method = "ms.remote.control", 
      params = { Cmd = "Click", DataOfCmd = key, Option=false, TypeOfRemote="SendRemoteKey"}
    }
    local ok,err = self.sock:send(json.encode(data).."\n")
    if not ok then self:warning("Send error:",err) end
  else
    self:warning("Socket closed")
  end
end

function QuickApp:mute() self:sendCmd("KEY_MUTE") end
function QuickApp:power() self:sendCmd("KEY_POWER") end

function handleConnected()
  self:debug("Connected")
end

function handleDisconnected()
  self:debug("Disconnected")
  self:debug("Trying to reconnect...")
  connect()
end

function handleError(error)
  self:error("Error:",error)
end

function handleDataReceived(resp)
  local data = json.decode(resp)
  self:debug("Event:",data.event)
  self:debug("Data:",data.data)
  if data.event == "ms.channel.connect" then
    if data.data.token then 
      self.token = data.data.token
      self:debug("token:",self.token)
      self:setVariable("token",self.token)
      local base = self.url:match("(.-)&token=") or self.url
      self.url=self.url.."&token="..self.token
    end
  end 
end 

function connect()
  self.sock = net.WebSocketClientTls()

  self.sock:addEventListener("connected", handleConnected)
  self.sock:addEventListener("disconnected", handleDisconnected)
  self.sock:addEventListener("error", handleError)
  self.sock:addEventListener("dataReceived", handleDataReceived)

  self.sock:connect(self.url)
end

function QuickApp:onInit()
  setSelf(self)
  self.ip = self:getVariable("IP")
  self.tvname = self:getVariable("name")
  self.token = self:getVariable("token") or ""
  self.url = "wss://%s:8002/api/v2/channels/samsung.remote.control?name="..base64encode(self.tvname)
  if self.token  and self.token ~= "" then
    self.url = self.url.."&token="..self.token
  end
  self.url=self.url:format(self.ip)
  self:debug("URL:",self.url)
  connect()
end 