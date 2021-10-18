_=loadfile and loadfile("TQAE.lua"){
  user="admin", 
  pwd="admin", 
  host="192.168.1.57",
  modPath = "TQAEmodules/",
  temp = "temp/",
  debug = { socketServer = true },
  copas=true,
}
--[[
  Test TCPSocket QA
--]]

--%%name="TCP test"
--%%type="com.fibaro.binarySwitch"
--%%quickVars={ip="192.168.1.18",port=9999}

-- Quick App template for handling the TCP device, login, get data

hc3_emulator.EM.socketServer(9999,"*l", -- Start server at port 9999, only works with async/copas
  function(str)
    local pwd = str:match("Password:(.*)")
    if pwd and pwd=="Foo" then 
      print("Correct password")
      return "Login Ok\n"
    elseif str=='On' then
      return "On Ok\n"
    elseif str=='Off' then
      return "Off Ok\n"
    end
  end)


function QuickApp:turnOn()
  self:debug("binary switch turned on")
  self:send("On\n") -- sending data to the device. In a normal implementation it will be a code with an appropriate command.
  self:updateProperty("value", true)
end

function QuickApp:turnOff()
  self:debug("binary switch turned off")
  self:send("Off\n") -- sending data to the device. In a normal implementation it will be a code with an appropriate command.
  self:updateProperty("value", false)
end

-- the method for sending data to the device
-- the method can be called from anywhere
function QuickApp:send(strToSend)
  self.sock:write(strToSend, {
      success = function() -- the function that will be triggered when the data is correctly sent
        self:debug("data sent")
      end,
      error = function(err) -- the function that will be triggered in the event of an error in data transmission
        self:debug("error while sending data")
      end
    })
end

-- method for reading data from the socket
-- since the method itself has been looped, it should not be called from other locations than QuickApp:connect
function QuickApp:waitForResponseFunction()
  self.sock:read({ -- reading a data package from the socket
      success = function(data)
        self:onDataReceived(data) -- handling of received data
        self:waitForResponseFunction() -- looping of data readout
      end,
      error = function() -- a function that will be called in case of an error when trying to receive data, e.g. disconnecting a socket
        self:debug("response error")
        self.sock:close() -- socket closed
        fibaro.setTimeout(5000, function() self:connect() end) -- re-connection attempt (every 5s)
      end
    })
end

-- a method to open a TCP connection.
-- if the connection is successful, the data readout loop will be called QuickApp:waitForResponseFunction()
function QuickApp:connect()
  self.sock = net.TCPSocket() -- creation of a TCPSocket instance
  self.sock:connect(self.ip, self.port, { -- connection to the device with the specified IP and port
      success = function() -- the function will be triggered if the connection is correct
        self:debug("connected")
        self:send("Password:Foo\n")
        self:waitForResponseFunction() -- launching a data readout "loop"
      end,
      error = function(err) -- a function that will be triggered in case of an incorrect connection, e.g. timeout
        self.sock:close() -- closing the socket
        self:debug("connection error:",err)
        fibaro.setTimeout(5000, function() self:connect() end) -- re-connection attempt (every 5s)
      end,
    })
end

-- function handling the read data
-- normally this is where the data reported by the device will be handled
function QuickApp:onDataReceived(data)
  self:debug("onDataReceived", data)
end

function QuickApp:onInit()
  self:debug("onInit")

  self.ip = self:getVariable("ip")
  self.port = tonumber(self:getVariable("port"))
  setTimeout(function() self:connect() end,0)
end