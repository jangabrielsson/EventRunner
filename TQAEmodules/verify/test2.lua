--%%name = "Test2"
function QuickApp:onInit()
  local n = 3
  setInterval(function() 
      self:debug("PONG")
      n=n-1
      if n == 0 then os.exit() end
  end,1000)
end
