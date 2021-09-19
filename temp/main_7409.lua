  --%%type="com.fibaro.binarySensor"
  local timer
  function QuickApp:breach(s)
    setIninterval(function() self:debug("SI") end,1000)
    self:debug("BREACHED")
    self:updateProperty("value",true)
    if timer then clearTimeout(timer) timer=nil end
    self:setVariable("foo",42)
    timer = setTimeout(function() 
       self:debug("SAFE")
       self:updateProperty("value",false); timer = nil end,
       (tonumber(s) or 10)*1000)
    self:debug("Well be safe in "..(tonumber(s) or 10).."s")
  end
  function QuickApp:onInit()
    self:debug(self.name,self.id)
  end
