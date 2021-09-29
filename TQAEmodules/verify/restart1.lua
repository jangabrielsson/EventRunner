--%%name = "Restart1"
--%%quickVars={count=0}

function QuickApp:onInit()
  self:debug(self.name,self.id)
  local v = self:getVariable("count")
  if v < 3 then
    local n = 0
    setInterval(function() n=n+1 self:debug("PING"..v.." "..n) end,250)
    self:setVariable("count",v+1)
    setTimeout(function() 
        self:debug("Restart #"..(v+1))
        plugin.restart()
      end,1500)
  else self:debug("Done") os.exit() end
end
