if dofile and not hc3_emulator then
  hc3_emulator = {
    name = "Samsung",  -- Name of QA
    poll = 2000,       -- Poll HC3 for triggers every 2000ms
    type="com.fibaro.philipsTV",
    proxy=true,
    --offline = true,
    UI = {
      {button="Power", text="Power", onReleased="power"},
      {button="Mute", text="Mute", onReleased="mute"},
    }
  }
  dofile("fibaroapiHC3.lua")
end

hc3_emulator.FILE("Toolbox/Toolbox_basic.lua","Toolbox")

local self,connect,handleDataReceived,handleError,handleDisconnected,handleConnected
local function setSelf(qa) self = qa end

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
  self.sock = net.WebSocketClient()

  self.sock:addEventListener("connected", handleConnected)
  self.sock:addEventListener("disconnected", handleDisconnected)
  self.sock:addEventListener("error", handleError)
  self.sock:addEventListener("dataReceived", handleDataReceived)

  self.sock:connect(self.url)
end

function QuickApp:onInit()
  setSelf(self)
  self:setVariable("IP","192.168.1.175")
  self.ip = self:getVariable("IP")
  self.token = self:getVariable("token") or ""
  self.url = "wss://%s:8002/api/v2/channels/samsung.remote.control?name="..self:encodeBase64("HC336")
  if self.token  and self.token ~= "" then
    self.url = self.url.."&token="..self.token
  end
  self.url=self.url:format(self.ip)
  self:debug("URL:",self.url)
  connect()
end 