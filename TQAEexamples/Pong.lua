--%%name="Pong"

function QuickApp:ping(ret)
  self:debug("Ping")
  setTimeout(function() fibaro.call(ret,"pong",self.id) end, 2000)
end

function QuickApp:onInit()
  self:debug("Pong started")
end