--%%name = "Test1"

function QuickApp:onInit()
  local n = 8
  setInterval(function() 
      self:debug("PING",n)
      n=n-1
      if n == 0 then os.exit() end
  end,250)
end